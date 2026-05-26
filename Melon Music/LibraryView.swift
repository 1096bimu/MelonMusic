import SwiftData
import SwiftUI

struct MusicListView: View {
    @ObservedObject var library: MusicLibraryController
    let navigationRequest: LibraryNavigationRequest?
    let onShuffleAll: () -> Void
    let onSongSelected: () -> Void
    let onAddAll: () -> Void
    @Query(sort: \MusicTrack.titleSortKey, order: .forward) private var tracks: [MusicTrack]
    @AppStorage("nowPlayingShowsAlbumArtist") private var showsAlbumArtist = false
    @AppStorage(accentColorStorageKey) private var accentColorHex = defaultAccentColorHex

    private var visibleTracks: [MusicTrack] {
        library.usableTracks(from: tracks)
            .sorted(by: MusicLibraryController.compareTracksByTitleSortKey)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(visibleTracks, id: \.relativePath) { track in
                        Button {
                            library.playOrQueueAfterCurrent(track)
                            onSongSelected()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.displayTitle)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(track.displayArtist(showsAlbumArtist: showsAlbumArtist))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        DecoratedListTitle(
                            title: "Library",
                            accentColorHex: accentColorHex,
                            isLineAnimated: library.isPlaying
                        )
                        Spacer()
                        Button("Add All") {
                            library.addTracksAfterCurrentInTemporaryPlaylist(visibleTracks)
                            onAddAll()
                        }
                        .disabled(visibleTracks.isEmpty)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Library")
        }
    }
}
