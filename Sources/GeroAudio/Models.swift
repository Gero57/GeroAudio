import Foundation
import AppKit

struct Track: Identifiable, Hashable {
    let id: String
    let url: URL
    var startTime: TimeInterval = 0
    var endTime: TimeInterval? = nil
    var trackNumber: Int? = nil
    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var year: Int?
    var duration: TimeInterval
    var artwork: NSImage?
    var fileType: String { url.pathExtension.uppercased() }
    static func == (lhs: Track, rhs: Track) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
struct Album: Identifiable, Hashable {
    var id: String { tracks.first?.url.deletingLastPathComponent().standardizedFileURL.path ?? "\(artist)|\(title)" }
    let title: String
    let artist: String
    let year: Int?
    let artwork: NSImage?
    let tracks: [Track]
    static func == (lhs: Album, rhs: Album) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
enum LibrarySort: String, CaseIterable, Identifiable {
    case album = "Album", artist = "Artista", year = "Anno", title = "Titolo"
    var id: String { rawValue }
}
enum LibraryTab: String, CaseIterable, Identifiable {
    case tracks = "Brani", albums = "Album", artists = "Artisti"
    var id: String { rawValue }
}
