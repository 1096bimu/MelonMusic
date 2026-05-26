import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var library: MusicLibraryController
    @ObservedObject var customizationPurchaseController: CustomizationPurchaseController
    @AppStorage("usesDarkMode") private var usesDarkMode = false
    @AppStorage("sortHanziByPinyin") private var sortHanziByPinyin = false
    @AppStorage("sortKanaByRomaji") private var sortKanaByRomaji = true
    @AppStorage("nowPlayingShowsAlbumArtist") private var showsAlbumArtist = false
    @AppStorage(accentColorStorageKey) private var accentColorHex = defaultAccentColorHex

    var body: some View {
        MacShellView(library: library)
            .frame(minWidth: 980, minHeight: 640)
            .preferredColorScheme(usesDarkMode ? .dark : .light)
            .tint(Color(hex: accentColorHex))
            .task {
                library.usesInternalLibraryRoot = false
                library.prepareStorage()
                library.refreshStats(using: modelContext)
                library.recomputeSortKeys(using: modelContext)
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    library.reconcilePlaybackAfterForeground()
                } else {
                    library.wheelCommitCounter += 1
                    library.persistTemporaryPlaylistState()
                }
            }
            .onChange(of: sortHanziByPinyin) {
                library.recomputeSortKeys(using: modelContext)
            }
            .onChange(of: sortKanaByRomaji) {
                library.recomputeSortKeys(using: modelContext)
            }
            .onChange(of: showsAlbumArtist) {
                library.recomputeSortKeys(using: modelContext)
            }
            .alert(item: $library.missingPlaybackFileAlert) { alert in
                Alert(
                    title: Text("File Not Found"),
                    message: Text("Could not find \(alert.trackTitle). Scan now to update the library?"),
                    primaryButton: .default(Text("Scan Now")) {
                        Task {
                            await library.scan(using: modelContext)
                        }
                    },
                    secondaryButton: .cancel(Text("Cancel"))
                )
            }
    }
}

#Preview {
    ContentView(
        library: MusicLibraryController(),
        customizationPurchaseController: CustomizationPurchaseController()
    )
    .modelContainer(for: [MusicTrack.self, PlaylistStack.self, ExternalRootBookmark.self], inMemory: true)
}
