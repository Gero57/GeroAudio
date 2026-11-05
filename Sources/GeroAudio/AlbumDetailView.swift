import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    let onPlay: (Track) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button(action: onBack) { Label("Torna alla libreria", systemImage: "chevron.left").font(.system(size: 11, weight: .medium)) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                cover
                VStack(alignment: .leading, spacing: 8) {
                    Text(album.title).font(.system(size: 25, weight: .semibold, design: .serif))
                    Text(album.artist).font(.system(size: 15)).foregroundStyle(.secondary)
                    if let year = album.year { Text(String(year)).font(.system(size: 12)).foregroundStyle(.secondary) }
                    Text("\(album.tracks.count) brani").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button {
                        if let first = album.tracks.first { onPlay(first) }
                    } label: {
                        Label("Riproduci album", systemImage: "play.fill")
                    }.buttonStyle(.borderedProminent).tint(.cyan)
                }
                Spacer()
            }
            Divider()
            HStack {
                Text("TRACCIA").frame(maxWidth: .infinity, alignment: .leading)
                Text("FORMATO").frame(width: 75, alignment: .trailing)
                Text("DURATA").frame(width: 65, alignment: .trailing)
            }.font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            List(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                Button { onPlay(track) } label: {
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", index + 1)).foregroundStyle(.secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).foregroundStyle(.primary)
                            if track.artist != album.artist {
                                Text(track.artist).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(track.fileType).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 75, alignment: .trailing)
                        Text(time(track.duration)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 65, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.listStyle(.plain)
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var cover: some View {
        if let artwork = album.artwork {
            Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 170, height: 170).clipped().cornerRadius(5)
        } else {
            ZStack {
                LinearGradient(colors: [.blue.opacity(0.35), .black.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: 48)).foregroundStyle(.white.opacity(0.65))
            }.frame(width: 170, height: 170).cornerRadius(5)
        }
    }

    private func time(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }
}
