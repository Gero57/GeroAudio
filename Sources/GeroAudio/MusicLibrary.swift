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
    private let rootsKey = "GeroAudio.libraryRoots"

    init() {
        rootURLs = (UserDefaults.standard.stringArray(forKey: rootsKey) ?? []).map(URL.init(fileURLWithPath:))
        if !rootURLs.isEmpty { refresh() }
    }

    var albums: [Album] {
        let groups = Dictionary(grouping: tracks) { "\($0.albumArtist.isEmpty ? $0.artist : $0.albumArtist)|\($0.album)" }
        return groups.values.compactMap { group in
            guard let first = group.first else { return nil }
            return Album(title: first.album, artist: first.albumArtist.isEmpty ? first.artist : first.albumArtist,
                         year: first.year, artwork: group.compactMap(\.artwork).first,
                         tracks: group.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
        }
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
            for root in roots {
                let access = root.startAccessingSecurityScopedResource()
                defer { if access { root.stopAccessingSecurityScopedResource() } }
                guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let url as URL in enumerator {
                    guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                    let asset = AVURLAsset(url: url)
                    let metadata = asset.commonMetadata
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
                    if let item = metadata.first(where: { $0.commonKey == AVMetadataKey.commonKeyArtwork }),
                       let data = item.dataValue { artwork = NSImage(data: data) }
                    found.append(Track(id: url, url: url, title: title, artist: artist, album: album,
                                       albumArtist: artist, year: year, duration: duration, artwork: artwork))
                }
            }
            await MainActor.run {
                self?.tracks = found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                self?.isScanning = false
                self?.scanMessage = "\(found.count) brani indicizzati"
            }
        }
    }

    private func persistRoots() {
        UserDefaults.standard.set(rootURLs.map(\.path), forKey: rootsKey)
    }
}
