import SwiftData
import SwiftUI

struct LibrarySearchView: View {
    @ObservedObject var library: MusicLibraryController
    let navigationRequest: SearchNavigationRequest?
    let onBack: () -> Void
    let onSongSelected: () -> Void
    let onAddAll: () -> Void
    let onShuffleAll: () -> Void
    @Query(sort: \MusicTrack.titleSortKey, order: .forward) private var tracks: [MusicTrack]
    @AppStorage("nowPlayingShowsAlbumArtist") private var showsAlbumArtist = false
    @AppStorage(accentColorStorageKey) private var accentColorHex = defaultAccentColorHex
    @State private var searchText = ""

    private var searchResults: [MusicTrack] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return library.usableTracks(from: tracks)
            .filter { track in
                searchableText(for: track)
                    .range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            .sorted(by: MusicLibraryController.compareTracksByTitleSortKey)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView("Search", systemImage: "magnifyingglass")
                    } else if searchResults.isEmpty {
                        ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                    } else {
                        ForEach(searchResults, id: \.relativePath) { track in
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
                    }
                } header: {
                    HStack {
                        Button {
                            searchText = ""
                            onBack()
                        } label: {
                            DecoratedListTitle(
                                title: "Back",
                                accentColorHex: accentColorHex,
                                isLineAnimated: library.isPlaying
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button("Add All") {
                            library.addTracksAfterCurrentInTemporaryPlaylist(searchResults)
                            onAddAll()
                            searchText = ""
                            onBack()
                        }
                        .disabled(searchResults.isEmpty)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: Text("Search"))
            .onChange(of: navigationRequest) {
                guard let navigationRequest else { return }
                searchText = navigationRequest.query
            }
        }
    }

    private func searchableText(for track: MusicTrack) -> String {
        [
            track.displayTitle,
            track.fileName,
            track.directory,
            track.relativePath,
            track.artist,
            track.albumArtist ?? "",
            track.album,
            track.genre
        ].joined(separator: " ")
    }
}
