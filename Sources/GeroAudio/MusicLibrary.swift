import Foundation
import AppKit
import AVFoundation
import Combine

@MainActor
final class MusicLibrary: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published var rootURLs: [URL] = []
    @Published var isScanning = false
    @Published var scanMessage = "Scegli una cartella musicale per iniziare"
    private let supported = Set(["flac", "wav", "wave", "aif", "aiff", "mp3", "m4a", "aac", "caf"])
    @Published private(set) var playlists: [String: [String]] = UserDefaults.standard.dictionary(forKey: "GeroAudio.playlists") as? [String: [String]] ?? [:]
    private let rootsKey = "GeroAudio.libraryRoots"

    init() {
        rootURLs = (UserDefaults.standard.stringArray(forKey: rootsKey) ?? []).map(URL.init(fileURLWithPath:))
        if !rootURLs.isEmpty { refresh() }
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

    func removeAlbum(_ album: Album, from playlist: String) {
        playlists[playlist]?.removeAll { $0 == album.id }
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
                self?.scanMessage = "\(found.count) brani indicizzati"
            }
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
    var artwork: NSImage?
    for name in ["cover", "folder", "front", "album", "artwork"] {
        for ext in ["jpg", "jpeg", "png", "tif", "tiff"] {
            if let image = NSImage(contentsOf: folderURL.appendingPathComponent(name).appendingPathExtension(ext)) {
                artwork = image
                break
            }
        }
        if artwork != nil { break }
    }
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
