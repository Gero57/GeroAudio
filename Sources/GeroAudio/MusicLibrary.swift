import Foundation
import AppKit
import AVFoundation
import Combine
import CryptoKit

@MainActor
final class MusicLibrary: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published var rootURLs: [URL] = []
    @Published var isScanning = false
    @Published var scanMessage = "Scegli una cartella musicale per iniziare"
    private let supported = Set(["flac", "wav", "wave", "aif", "aiff", "mp3", "m4a", "aac", "caf"])
    @Published private(set) var playlists: [String: [String]] = UserDefaults.standard.dictionary(forKey: "GeroAudio.playlists") as? [String: [String]] ?? [:]
    private let rootsKey = "GeroAudio.libraryRoots"
    private let cacheFolder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("GeroAudio/LibraryCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
    private var cacheFile: URL { cacheFolder.appendingPathComponent("library.json") }

    init() {
        rootURLs = (UserDefaults.standard.stringArray(forKey: rootsKey) ?? []).map(URL.init(fileURLWithPath:))
        loadCachedLibrary()
        if !tracks.isEmpty {
            scanMessage = "\(tracks.count) brani dalla libreria salvata"
        } else if !rootURLs.isEmpty {
            refresh()
        }
    }

    var albums: [Album] {
        // I tag artista/album possono variare tra le tracce dello stesso disco.
        // La cartella dell'album è il riferimento stabile; il titolo normalizzato
        // evita differenze dovute a spazi o maiuscole.
        let groups = Dictionary(grouping: tracks) { track in
            let folder = track.url.deletingLastPathComponent().standardizedFileURL.path
            let normalizedAlbum = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return "\(folder)|\(normalizedAlbum)"
        }
        return groups.values.compactMap { group in
            guard let first = group.first else { return nil }
            return Album(title: first.album, artist: first.albumArtist.isEmpty ? first.artist : first.albumArtist,
                         year: first.year, artwork: group.compactMap(\.artwork).first,
                         tracks: group.sorted { left, right in
                             if let leftNumber = left.trackNumber, let rightNumber = right.trackNumber, leftNumber != rightNumber {
                                 return leftNumber < rightNumber
                             }
                             if left.url == right.url && left.startTime != right.startTime { return left.startTime < right.startTime }
                             return left.title.localizedStandardCompare(right.title) == .orderedAscending
                         })
        }
    }

    func createPlaylist(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, playlists[clean] == nil else { return }
        playlists[clean] = []
        persistPlaylists()
    }

    func addAlbum(_ album: Album, to playlist: String) {
        guard playlists[playlist] != nil else { return }
        if playlists[playlist]?.contains(album.id) == false {
            playlists[playlist, default: []].append(album.id)
            persistPlaylists()
        }
    }

    func addTrack(_ track: Track, to playlist: String) {
        guard playlists[playlist] != nil else { return }
        if playlists[playlist]?.contains(track.id) == false {
            playlists[playlist, default: []].append(track.id)
            persistPlaylists()
        }
    }

    func removeTrack(_ track: Track, from playlist: String) {
        playlists[playlist]?.removeAll { $0 == track.id }
        persistPlaylists()
    }

    func removeAlbum(_ album: Album, from playlist: String) {
        let trackIDs = Set(album.tracks.map(\.id))
        playlists[playlist]?.removeAll { $0 == album.id || trackIDs.contains($0) }
        persistPlaylists()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Scegli la cartella della libreria musicale"
        panel.prompt = "Aggiungi"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls where !rootURLs.contains(url) { rootURLs.append(url) }
            persistRoots()
            refresh()
        }
    }

    func refresh() {
        guard !rootURLs.isEmpty else { tracks = []; return }
        isScanning = true
        scanMessage = "Scansione della libreria…"
        let roots = rootURLs
        let extensions = supported
        Task.detached(priority: .utility) { [weak self] in
            var found: [Track] = []
            var folderArtworkCache: [URL: NSImage] = [:]
            for root in roots {
                let access = root.startAccessingSecurityScopedResource()
                defer { if access { root.stopAccessingSecurityScopedResource() } }
                guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                let fileURLs = enumerator.compactMap { $0 as? URL }
                let cueFiles = fileURLs.filter { $0.pathExtension.lowercased() == "cue" }
                var cueReferencedAudio = Set<URL>()
                for cueURL in cueFiles {
                    let cueTracks = parseCueFile(cueURL)
                    if !cueTracks.isEmpty {
                        cueReferencedAudio.formUnion(cueTracks.map { $0.url.standardizedFileURL })
                        found.append(contentsOf: cueTracks)
                    }
                }
                for url in fileURLs {
                    guard extensions.contains(url.pathExtension.lowercased()),
                          !cueReferencedAudio.contains(url.standardizedFileURL) else { continue }
                    if url.pathExtension.lowercased() == "flac" {
                        let embeddedCueTracks = parseEmbeddedFlacCue(url)
                        if !embeddedCueTracks.isEmpty {
                            found.append(contentsOf: embeddedCueTracks)
                            continue
                        }
                    }
                    let asset = AVURLAsset(url: url)
                    let metadata = asset.commonMetadata
                    let allMetadata = asset.metadata + metadata
                    func value(_ key: AVMetadataKey) -> String? {
                        AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: .common).first?.stringValue
                    }
                    let title = value(.commonKeyTitle) ?? url.deletingPathExtension().lastPathComponent
                    let folderURL = url.deletingLastPathComponent()
                    let parentFolderURL = folderURL.deletingLastPathComponent()
                    let artist = value(.commonKeyArtist) ?? parentFolderURL.lastPathComponent
                    let album = value(.commonKeyAlbumName) ?? folderURL.lastPathComponent
                    let year = value(.commonKeyCreationDate).flatMap { Int($0.prefix(4)) }
                    let audio = try? AVAudioFile(forReading: url)
                    let duration = audio.map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
                    var artwork: NSImage?
                    if let item = allMetadata.first(where: { $0.commonKey == AVMetadataKey.commonKeyArtwork }),
                       let data = item.dataValue { artwork = NSImage(data: data) }
                    if artwork == nil {
                        if let cached = folderArtworkCache[folderURL] {
                            artwork = cached
                        } else {
                            let imageExtensions = Set(["jpg", "jpeg", "png", "tif", "tiff", "webp", "bmp"])
                            let preferredNames = ["cover", "folder", "front", "album", "artwork"]
                            let candidates = (try? FileManager.default.contentsOfDirectory(at: folderURL,
                                includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
                            let images = candidates.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
                            let orderedImages = images.sorted { left, right in
                                let leftName = left.deletingPathExtension().lastPathComponent.lowercased()
                                let rightName = right.deletingPathExtension().lastPathComponent.lowercased()
                                let leftRank = preferredNames.firstIndex(of: leftName) ?? preferredNames.count
                                let rightRank = preferredNames.firstIndex(of: rightName) ?? preferredNames.count
                                if leftRank != rightRank { return leftRank < rightRank }
                                return left.lastPathComponent.localizedStandardCompare(right.lastPathComponent) == .orderedAscending
                            }
                            for imageURL in orderedImages {
                                if let image = NSImage(contentsOf: imageURL) {
                                    folderArtworkCache[folderURL] = image
                                    artwork = image
                                    break
                                }
                            }
                        }
                    }
                    found.append(Track(id: url.path, url: url, title: title, artist: artist, album: album,
                                       albumArtist: artist, year: year, duration: duration, artwork: artwork))
                }
            }
            await MainActor.run {
                // Evita doppioni se la stessa cartella è stata aggiunta da più radici.
                let uniqueTracks = Dictionary(grouping: found, by: { $0.id })
                    .compactMap { $0.value.first }
                self?.tracks = uniqueTracks.sorted {
                    let albumOrder = $0.album.localizedStandardCompare($1.album)
                    if albumOrder != .orderedSame { return albumOrder == .orderedAscending }
                    if let leftNumber = $0.trackNumber, let rightNumber = $1.trackNumber, leftNumber != rightNumber {
                        return leftNumber < rightNumber
                    }
                    if $0.url == $1.url && $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                self?.isScanning = false
                self?.scanMessage = "\(uniqueTracks.count) brani indicizzati"
                self?.saveCachedLibrary()
            }
        }
    }

    private func loadCachedLibrary() {
        guard let data = try? Data(contentsOf: cacheFile),
              let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) else { return }
        tracks = snapshot.tracks.map { item in
            let artwork: NSImage? = item.artworkFile.flatMap { name in
                NSImage(contentsOf: cacheFolder.appendingPathComponent(name))
            }
            return Track(id: item.id, url: URL(fileURLWithPath: item.path),
                         startTime: item.startTime, endTime: item.endTime,
                         trackNumber: item.trackNumber, title: item.title,
                         artist: item.artist, album: item.album, albumArtist: item.albumArtist,
                         year: item.year, duration: item.duration, artwork: artwork)
        }
    }

    private func saveCachedLibrary() {
        var artworkFiles: [String: String] = [:]
        let records = tracks.map { track -> CachedTrack in
            let folderKey = track.url.deletingLastPathComponent().standardizedFileURL.path
            var artworkName: String?
            if let image = track.artwork, let tiff = image.tiffRepresentation {
                if let existing = artworkFiles[folderKey] {
                    artworkName = existing
                } else {
                    let digest = SHA256.hash(data: Data(folderKey.utf8)).map { String(format: "%02x", $0) }.joined()
                    let name = "cover-\(digest).tiff"
                    let destination = cacheFolder.appendingPathComponent(name)
                    if !FileManager.default.fileExists(atPath: destination.path) {
                        try? tiff.write(to: destination, options: .atomic)
                    }
                    artworkFiles[folderKey] = name
                    artworkName = name
                }
            }
            return CachedTrack(id: track.id, path: track.url.path, startTime: track.startTime,
                               endTime: track.endTime, trackNumber: track.trackNumber,
                               title: track.title, artist: track.artist, album: track.album,
                               albumArtist: track.albumArtist, year: track.year,
                               duration: track.duration, artworkFile: artworkName)
        }
        if let data = try? JSONEncoder().encode(LibrarySnapshot(tracks: records)) {
            try? data.write(to: cacheFile, options: .atomic)
        }
    }

    private func persistPlaylists() {
        UserDefaults.standard.set(playlists, forKey: "GeroAudio.playlists")
    }

    private func persistRoots() {
        UserDefaults.standard.set(rootURLs.map(\.path), forKey: rootsKey)
    }
}


private func parseCueFile(_ cueURL: URL) -> [Track] {
    let text = (try? String(contentsOf: cueURL, encoding: .utf8))
        ?? (try? String(contentsOf: cueURL, encoding: .isoLatin1))
    guard let text else { return [] }
    let lines = text.components(separatedBy: .newlines)
    var referencedFile: String?
    var albumTitle = cueURL.deletingPathExtension().lastPathComponent
    var albumArtist = cueURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
    var entries: [(number: Int, title: String, artist: String, seconds: TimeInterval)] = []
    var currentNumber: Int?
    var currentTitle: String?
    var currentArtist: String?
    var currentSeconds: TimeInterval?

    func quotedValue(_ line: String) -> String? {
        guard let first = line.firstIndex(of: "\""),
              let last = line[line.index(after: first)...].firstIndex(of: "\"") else { return nil }
        return String(line[line.index(after: first)..<last])
    }
    func cueTime(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 60 + parts[1] + parts[2] / 75.0
    }
    func finishEntry() {
        if let number = currentNumber, let title = currentTitle, let seconds = currentSeconds {
            entries.append((number, title, currentArtist ?? albumArtist, seconds))
        }
        currentNumber = nil
        currentTitle = nil
        currentArtist = nil
        currentSeconds = nil
    }

    for rawLine in lines {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = line.uppercased()
        if upper.hasPrefix("FILE ") {
            referencedFile = quotedValue(line) ?? line.split(separator: " ").dropFirst().first.map(String.init)
        } else if upper.hasPrefix("TRACK ") {
            finishEntry()
            currentNumber = Int(line.split(whereSeparator: { $0 == " " || $0 == "\t" }).dropFirst().first ?? "")
        } else if upper.hasPrefix("TITLE ") {
            let value = quotedValue(line)
            if currentNumber == nil, let value { albumTitle = value }
            else if let value { currentTitle = value }
        } else if upper.hasPrefix("PERFORMER ") {
            let value = quotedValue(line)
            if currentNumber == nil, let value { albumArtist = value }
            else if let value { currentArtist = value }
        } else if upper.hasPrefix("INDEX 01 "), let value = line.split(separator: " ").last {
            currentSeconds = cueTime(String(value))
        }
    }
    finishEntry()
    guard let filename = referencedFile, !entries.isEmpty else { return [] }
    let audioURL = cueURL.deletingLastPathComponent().appendingPathComponent(filename).standardizedFileURL
    guard let audio = try? AVAudioFile(forReading: audioURL) else { return [] }
    let totalDuration = Double(audio.length) / audio.processingFormat.sampleRate
    let folderURL = audioURL.deletingLastPathComponent()
    let parentArtist = albumArtist.isEmpty ? folderURL.deletingLastPathComponent().lastPathComponent : albumArtist
    let artwork = findArtwork(in: folderURL)
    return entries.enumerated().compactMap { index, entry in
        let end = index + 1 < entries.count ? entries[index + 1].seconds : totalDuration
        guard end > entry.seconds else { return nil }
        return Track(id: "\(audioURL.path)#cue-\(entry.number)", url: audioURL,
                     startTime: entry.seconds, endTime: end, trackNumber: entry.number,
                     title: entry.title, artist: entry.artist.isEmpty ? parentArtist : entry.artist,
                     album: albumTitle, albumArtist: parentArtist,
                     year: nil, duration: end - entry.seconds, artwork: artwork)
    }
}


private func findArtwork(in folder: URL) -> NSImage? {
    let imageExtensions = Set(["jpg", "jpeg", "png", "tif", "tiff", "webp", "bmp"])
    let preferredNames = ["cover", "folder", "front", "album", "artwork"]
    let files = (try? FileManager.default.contentsOfDirectory(at: folder,
        includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
    let images = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    let ordered = images.sorted { left, right in
        let leftName = left.deletingPathExtension().lastPathComponent.lowercased()
        let rightName = right.deletingPathExtension().lastPathComponent.lowercased()
        let leftRank = preferredNames.firstIndex(of: leftName) ?? preferredNames.count
        let rightRank = preferredNames.firstIndex(of: rightName) ?? preferredNames.count
        if leftRank != rightRank { return leftRank < rightRank }
        return left.lastPathComponent.localizedStandardCompare(right.lastPathComponent) == .orderedAscending
    }
    for url in ordered {
        if let image = NSImage(contentsOf: url) { return image }
    }
    return nil
}

private func parseEmbeddedFlacCue(_ url: URL) -> [Track] {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
    defer { try? handle.close() }
    guard let signature = try? handle.read(upToCount: 4), signature == Data("fLaC".utf8) else { return [] }

    var cueBlock: Data?
    while true {
        guard let header = try? handle.read(upToCount: 4), header.count == 4 else { break }
        let isLast = (header[0] & 0x80) != 0
        let type = header[0] & 0x7F
        let length = (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])
        if type == 5 {
            cueBlock = try? handle.read(upToCount: length)
            break
        }
        let offset = (try? handle.offset()) ?? 0
        try? handle.seek(toOffset: offset + UInt64(length))
        if isLast { break }
    }
    guard let data = cueBlock, data.count >= 396 else { return [] }

    func uint(_ offset: Int, _ count: Int) -> UInt64? {
        guard offset >= 0, count > 0, offset + count <= data.count else { return nil }
        var value: UInt64 = 0
        for index in offset..<(offset + count) { value = (value << 8) | UInt64(data[index]) }
        return value
    }

    guard let countValue = uint(395, 1), let audio = try? AVAudioFile(forReading: url) else { return [] }
    let sampleRate = audio.processingFormat.sampleRate
    let totalDuration = Double(audio.length) / sampleRate
    let trackCount = Int(countValue)
    var cursor = 396
    var entries: [(number: Int, start: TimeInterval)] = []

    for _ in 0..<trackCount {
        guard let sampleOffset = uint(cursor, 8),
              let number = uint(cursor + 8, 1),
              let indexCount = uint(cursor + 22, 1) else { return [] }
        let indexBase = cursor + 23
        var indexOneOffset: UInt64 = 0
        for index in 0..<Int(indexCount) {
            guard let offset = uint(indexBase + index * 12, 8),
                  let indexNumber = uint(indexBase + index * 12 + 8, 1) else { return [] }
            if indexNumber == 1 { indexOneOffset = offset }
        }
        if number != 170 {
            entries.append((Int(number), Double(sampleOffset + indexOneOffset) / sampleRate))
        }
        cursor = indexBase + Int(indexCount) * 12
        if cursor > data.count { return [] }
    }

    guard !entries.isEmpty else { return [] }
    let folder = url.deletingLastPathComponent()
    let albumTitle = folder.lastPathComponent
    let artist = folder.deletingLastPathComponent().lastPathComponent
    let artwork = findArtwork(in: folder)
    return entries.enumerated().compactMap { index, entry in
        let end = index + 1 < entries.count ? entries[index + 1].start : totalDuration
        guard end > entry.start, entry.start < totalDuration else { return nil }
        return Track(id: "\(url.path)#embedded-cue-\(entry.number)", url: url,
                     startTime: entry.start, endTime: end, trackNumber: entry.number,
                     title: String(format: "Traccia %02d", entry.number),
                     artist: artist, album: albumTitle, albumArtist: artist,
                     year: nil, duration: end - entry.start, artwork: artwork)
    }
}


private struct LibrarySnapshot: Codable {
    let tracks: [CachedTrack]
}

private struct CachedTrack: Codable {
    let id: String
    let path: String
    let startTime: TimeInterval
    let endTime: TimeInterval?
    let trackNumber: Int?
    let title: String
    let artist: String
    let album: String
    let albumArtist: String
    let year: Int?
    let duration: TimeInterval
    let artworkFile: String?
}
