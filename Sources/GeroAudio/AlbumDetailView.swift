import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    var fontScale: Double = 1.0
    let onPlay: (Track) -> Void
    let onBack: () -> Void

    private let pageBlue = Color(red: 0.055, green: 0.075, blue: 0.16)
    private let lineBlue = Color(red: 0.20, green: 0.25, blue: 0.40)
    private let accentBlue = Color(red: 0.40, green: 0.56, blue: 0.91)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                Label("Libreria", systemImage: "chevron.left")
                    .font(.system(size: 11 * fontScale, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.68))
            .padding(.bottom, 22)

            HStack(alignment: .top, spacing: 22) {
                cover
                VStack(alignment: .leading, spacing: 7) {
                    Text(album.title)
                        .font(.system(size: 27 * fontScale, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                    Text(album.artist)
                        .font(.system(size: 13 * fontScale, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.78))
                    HStack(spacing: 7) {
                        if let year = album.year {
                            Text(String(year))
                            Text("·")
                        }
                        Text("\(album.tracks.count) brani")
                        Text("·")
                        Text(totalDuration)
                    }
                    .font(.system(size: 10 * fontScale))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .padding(.top, 2)

                    Button {
                        if let first = album.tracks.first { onPlay(first) }
                    } label: {
                        Label("Riproduci album", systemImage: "play.fill")
                            .font(.system(size: 11 * fontScale, weight: .semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.20, green: 0.34, blue: 0.62))
                    .padding(.top, 8)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 27)

            HStack(spacing: 12) {
                Text("TRAC").frame(width: 38, alignment: .trailing)
                Text("TITOLO").frame(maxWidth: .infinity, alignment: .leading)
                Text("ARTISTA").frame(width: 160, alignment: .leading)
                Text("FORMATO").frame(width: 74, alignment: .trailing)
                Text("DURATA").frame(width: 62, alignment: .trailing)
            }
            .font(.system(size: 9 * fontScale, weight: .medium))
            .foregroundStyle(accentBlue.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(lineBlue).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                        Button { onPlay(track) } label: {
                            HStack(spacing: 12) {
                                Text(String(index + 1))
                                    .frame(width: 38, alignment: .trailing)
                                    .foregroundStyle(Color.white.opacity(0.58))
                                Text(track.title)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .frame(width: 160, alignment: .leading)
                                    .foregroundStyle(Color.white.opacity(0.70))
                                    .lineLimit(1)
                                Text(track.fileType)
                                    .frame(width: 74, alignment: .trailing)
                                    .foregroundStyle(Color.white.opacity(0.58))
                                Text(time(track.duration))
                                    .frame(width: 62, alignment: .trailing)
                                    .foregroundStyle(Color.white.opacity(0.82))
                                    .monospacedDigit()
                            }
                            .font(.system(size: 10 * fontScale))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                            .background(index.isMultiple(of: 2) ? Color.white.opacity(0.025) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) { Rectangle().fill(lineBlue.opacity(0.68)).frame(height: 0.5) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .background {
            ZStack {
                pageBlue
                LinearGradient(colors: [Color(red: 0.09, green: 0.12, blue: 0.24).opacity(0.55), pageBlue.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }.ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var cover: some View {
        if let artwork = album.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 112, height: 112)
                .clipped()
                .cornerRadius(3)
        } else {
            ZStack {
                LinearGradient(colors: [Color(red: 0.17, green: 0.23, blue: 0.39), Color(red: 0.07, green: 0.09, blue: 0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .frame(width: 112, height: 112)
            .cornerRadius(3)
        }
    }

    private var totalDuration: String {
        time(album.tracks.reduce(0) { $0 + $1.duration })
    }

    private func time(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let seconds = Int(value)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
