import SwiftUI

@main
struct GeroAudioApp: App {
    @StateObject private var library = MusicLibrary()
    @StateObject private var player = AudioPlayer()
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(library)
                .environmentObject(player)
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Riproduzione") {
                Button("Play/Pausa") { player.togglePlayback() }
                    .keyboardShortcut(.space, modifiers: [])
            }
            CommandMenu("Libreria") {
                Button("Aggiungi cartella…") { library.chooseFolder() }.keyboardShortcut("o", modifiers: [.command])
                Button("Aggiorna libreria") { library.refresh() }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
