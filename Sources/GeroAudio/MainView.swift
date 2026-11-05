import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: AudioPlayer
    @State private var tab: LibraryTab = .albums
    @State private var query = ""
    @State private var sort: LibrarySort = .album
    @State private var ascending = true
    @State private var coverSize: CGFloat = 126
    @AppStorage("GeroAudio.fontScale") private var fontScale: Double = 1.0
    @State private var showOutput = false
    @State private var selectedAlbum: Album?
    @State private var selectedPlaylist: String?
    @State private var showPlaylistAlert = false
    @State private var newPlaylistName = ""
    @FocusState private var keyboardFocus: Bool

    private var visibleTracks: [Track] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.tracks.filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q) || $0.album.localizedCaseInsensitiveContains(q) }.sorted {
            let result: Bool
            switch sort {
            case .album: result = $0.album.localizedStandardCompare($1.album) == .orderedAscending
            case .artist: result = $0.artist.localizedStandardCompare($1.artist) == .orderedAscending
            case .year: result = ($0.year ?? 0) < ($1.year ?? 0)
            case .title: result = $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return ascending ? result : !result
        }
    }
    private var visibleAlbums: [Album] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.albums.filter { album in
            let matchesQuery = q.isEmpty || album.title.localizedCaseInsensitiveContains(q) || album.artist.localizedCaseInsensitiveContains(q)
            guard matchesQuery else { return false }
            guard let selectedPlaylist, let items = library.playlists[selectedPlaylist] else { return true }
            return items.contains(album.id) || album.tracks.contains { items.contains($0.id) }
        }
            .map { album in
                guard let selectedPlaylist, let items = library.playlists[selectedPlaylist],
                      !items.contains(album.id) else { return album }
                let selectedTracks = album.tracks.filter { items.contains($0.id) }
                return Album(title: album.title, artist: album.artist, year: album.year,
                             artwork: album.artwork, tracks: selectedTracks)
            }
            .sorted { ascending ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.title.localizedStandardCompare($1.title) == .orderedDescending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("Gero Audio").font(.system(size: 25, design: .serif)).italic().foregroundStyle(Color(red: 0.88, green: 0.92, blue: 1))
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                    TextField("Cerca brani, album, artisti…", text: $query).textFieldStyle(.plain)
                }.padding(10).background(Color.white.opacity(0.07)).clipShape(Capsule()).frame(maxWidth: 480)
                Spacer()
                Button { showOutput.toggle() } label: { Image(systemName: "hifispeaker").font(.system(size: 17)) }.buttonStyle(.plain).popover(isPresented: $showOutput) { outputPanel.padding(16).frame(width: 300) }
            }.padding(.horizontal, 22).frame(height: 62).background(Color(red: 0.11, green: 0.15, blue: 0.25))
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("LIBRERIA").font(.system(size: 10, weight: .bold)).foregroundStyle(.cyan)
                    ForEach(LibraryTab.allCases) { item in
                        Button { tab = item; selectedPlaylist = nil } label: {
                            Label(item.rawValue, systemImage: item == .albums ? "square.grid.2x2" : item == .tracks ? "music.note.list" : "person.2").font(.system(size: 12 * fontScale, weight: tab == item ? .semibold : .regular)).foregroundStyle(tab == item ? .white : .white.opacity(0.65))
                        }.buttonStyle(.plain)
                    }
                    HStack {
                        Text("PLAYLIST").font(.system(size: 10, weight: .bold)).foregroundStyle(.cyan)
                        Spacer()
                        Button { newPlaylistName = ""; showPlaylistAlert = true } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        }.buttonStyle(.plain).help("Crea playlist")
                    }.padding(.top, 10)
                    ForEach(library.playlists.keys.sorted(), id: \.self) { name in
                        Button {
                            selectedPlaylist = name
                            tab = .albums
                            selectedAlbum = nil
                        } label: {
                            Label(name, systemImage: "music.note.list")
                                .font(.system(size: 11 * fontScale, weight: selectedPlaylist == name ? .semibold : .regular))
                                .foregroundStyle(selectedPlaylist == name ? .white : .white.opacity(0.68))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Button { library.chooseFolder() } label: { Label("Aggiungi cartella", systemImage: "folder.badge.plus").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.75))
                }.padding(18).frame(width: 176, alignment: .leading).frame(maxHeight: .infinity).background(Color(red: 0.075, green: 0.105, blue: 0.18))
                VStack(spacing: 0) {
                    HStack {
                        Text(library.isScanning ? library.scanMessage : "\(visibleTracks.count) brani · \(visibleAlbums.count) album").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        Picker("Ordina", selection: $sort) { ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 100).controlSize(.small)
                        Button { ascending.toggle() } label: { Image(systemName: ascending ? "arrow.up" : "arrow.down") }.buttonStyle(.plain)
                        if tab == .albums { Slider(value: $coverSize, in: 80...190).frame(width: 90).help("Dimensione copertine") }
                        Image(systemName: "textformat.size").font(.system(size: 11)).foregroundStyle(.secondary)
                        Slider(value: $fontScale, in: 0.8...1.8).frame(width: 90).help("Dimensione caratteri")
                        Button { library.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Aggiorna")
                    }.padding(.horizontal, 20).padding(.vertical, 13)
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                    Group {
                        if let album = selectedAlbum {
                            AlbumDetailView(album: album, fontScale: fontScale, currentTrackID: player.currentTrack?.id, isPlaying: player.isPlaying, onPlay: { track in player.play(track, queue: album.tracks) }, onBack: { selectedAlbum = nil })
                        } else if library.tracks.isEmpty && !library.isScanning {
                            ContentUnavailableView("La libreria è vuota", systemImage: "music.note.list", description: Text("Aggiungi una cartella con i tuoi file musicali."))
                        } else if tab == .albums {
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: coverSize + 16), spacing: 20)], alignment: .leading, spacing: 22) {
                                    ForEach(visibleAlbums) { album in
                                        Button { selectedAlbum = album } label: {
                                            VStack(alignment: .leading, spacing: 5) {
                                                artwork(album.artwork, size: coverSize)
                                                Text(album.title).font(.system(size: 11 * fontScale, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                                Text(album.artist).font(.system(size: 10 * fontScale)).foregroundStyle(.white.opacity(0.58)).lineLimit(1)
                                            }.frame(width: coverSize, alignment: .leading)
                                        }.buttonStyle(.plain)
                                        .contextMenu {
                                            Menu("Aggiungi album alla playlist") {
                                                if library.playlists.isEmpty {
                                                    Text("Crea prima una playlist")
                                                } else {
                                                    ForEach(library.playlists.keys.sorted(), id: \.self) { name in
                                                        Button(name) { library.addAlbum(album, to: name) }
                                                    }
                                                }
                                            }
                                            Menu("Aggiungi singoli brani") {
                                                if library.playlists.isEmpty {
                                                    Text("Crea prima una playlist")
                                                } else {
                                                    ForEach(album.tracks) { track in
                                                        Menu(track.title) {
                                                            ForEach(library.playlists.keys.sorted(), id: \.self) { name in
                                                                Button(name) { library.addTrack(track, to: name) }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            if let selectedPlaylist {
                                                Button("Rimuovi da questa playlist", role: .destructive) {
                                                    library.removeAlbum(album, from: selectedPlaylist)
                                                }
                                            }
                                        }
                                    }
                                }.padding(22)
                            }
                        } else if tab == .tracks {
                            List(Array(visibleTracks.enumerated()), id: \.element.id) { index, track in
                                Button { player.play(track, queue: visibleTracks) } label: {
                                    HStack(spacing: 12) {
                                        Text(String(format: "%02d", index + 1)).foregroundStyle(.secondary).frame(width: 28)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(track.title).font(.system(size: 13 * fontScale)).foregroundStyle(.white)
                                            Text("\(track.artist) · \(track.album)").font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(track.fileType).font(.system(size: 9)).foregroundStyle(.secondary)
                                        Text(time(track.duration)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.plain).listRowBackground(Color.clear)
                            }.scrollContentBackground(.hidden)
                        } else {
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 18)], spacing: 22) {
                                    ForEach(Array(Set(visibleTracks.map(\.artist))).sorted(), id: \.self) { artist in
                                        Button { query = artist; tab = .albums; selectedPlaylist = nil } label: {
                                            VStack(spacing: 10) {
                                                if let image = artistArtwork(for: artist) {
                                                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                                                        .frame(width: 76, height: 76).clipShape(Circle())
                                                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                                                } else {
                                                    Image(systemName: "person.crop.circle.fill").font(.system(size: 66)).foregroundStyle(.white.opacity(0.5))
                                                }
                                                Text(artist).font(.system(size: 11 * fontScale, weight: .semibold)).foregroundStyle(.white)
                                            }.frame(width: 150)
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(24)
                            }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.background(Color(red: 0.035, green: 0.05, blue: 0.105))
            }
            HStack(spacing: 14) {
                artwork(player.currentTrack?.artwork, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.currentTrack?.title ?? "Nessun brano in riproduzione").font(.system(size: 11 * fontScale, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(player.currentTrack.map { "\($0.artist) · \($0.album)" } ?? "Gero Audio").font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }.frame(width: 220, alignment: .leading)
                Spacer()
                Button { player.previousTrack() } label: { Image(systemName: "backward.end.fill") }.buttonStyle(.plain).help("Traccia precedente")
                Button { player.togglePlayback() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 19)).frame(width: 34, height: 34) }.buttonStyle(.plain).help("Play/Pausa (barra spaziatrice)")
                Button { player.nextTrack() } label: { Image(systemName: "forward.end.fill") }.buttonStyle(.plain).help("Traccia successiva")
                Button { player.stop() } label: { Image(systemName: "stop.fill") }.buttonStyle(.plain).help("Stop")
                Text(time(player.elapsed)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                Slider(value: Binding(get: { player.elapsed }, set: { player.seek(to: $0) }), in: 0...max(1, player.currentTrack?.duration ?? 1)).tint(.cyan).frame(maxWidth: 260).disabled(player.currentTrack == nil || (player.currentTrack?.duration ?? 0) <= 0)
                Text(player.currentTrack.map { time(max(0, $0.duration - player.elapsed)) } ?? "0:00").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...1).frame(width: 85)
            }.padding(.horizontal, 20).frame(height: 78).background(Color(red: 0.02, green: 0.03, blue: 0.07))
        }
        .background(Color(red: 0.035, green: 0.05, blue: 0.105))
        .focusable()
        .focused($keyboardFocus)
        .onKeyPress(keys: [.space, .upArrow, .downArrow]) { press in
            switch press.key {
            case .space:
                player.togglePlayback()
                return .handled
            case .upArrow:
                _ = player.previousTrack()
                return .handled
            case .downArrow:
                _ = player.nextTrack()
                return .handled
            default:
                return .ignored
            }
        }
        .onAppear {
            player.refreshOutputs()
            keyboardFocus = true
        }
        .alert("Nuova playlist", isPresented: $showPlaylistAlert) {
            TextField("Nome playlist", text: $newPlaylistName)
            Button("Annulla", role: .cancel) {}
            Button("Crea") { library.createPlaylist(named: newPlaylistName) }
        } message: {
            Text("Dai un nome alla tua playlist.")
        }
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("USCITA AUDIO").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Picker("Dispositivo", selection: Binding(get: { player.selectedOutputID ?? 0 }, set: { player.selectOutput($0) })) {
                ForEach(player.outputs) { output in Text(output.name).tag(output.id) }
            }.labelsHidden()
            Button("Aggiorna dispositivi") { player.refreshOutputs() }
            Text("La selezione dell'uscita è gestita da Gero Audio, senza modificare l'uscita predefinita di macOS.").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
    private func artistArtwork(for artist: String) -> NSImage? {
        library.albums.first(where: { $0.artist.localizedCaseInsensitiveCompare(artist) == .orderedSame && $0.artwork != nil })?.artwork
    }

    private func artwork(_ image: NSImage?, size: CGFloat) -> some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else { ZStack { LinearGradient(colors: [Color(red: 0.18, green: 0.28, blue: 0.45), Color(red: 0.04, green: 0.07, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "music.note").font(.system(size: size * 0.28)).foregroundStyle(.white.opacity(0.5)) } }
        }.frame(width: size, height: size).clipped().overlay(Rectangle().stroke(.white.opacity(0.08), lineWidth: 1))
    }
    private func time(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }
}


