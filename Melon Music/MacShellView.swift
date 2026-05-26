import SwiftData
import SwiftUI

struct MacShellView: View {
    @ObservedObject var library: MusicLibraryController
    @Query(sort: \MusicTrack.titleSortKey, order: .forward) private var tracks: [MusicTrack]
    @AppStorage("nowPlayingShowsAlbumArtist") private var showsAlbumArtist = false
    @AppStorage(accentColorStorageKey) private var accentColorHex = defaultAccentColorHex
    @State private var searchText = ""
    @State private var sortMode: MacLibrarySortMode = .title
    @State private var filter: MacLibraryFilter = .none

    private var visibleTracks: [MusicTrack] {
        let usableTracks = library.usableTracks(from: tracks)
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchFilteredTracks: [MusicTrack]

        if trimmedSearch.isEmpty {
            searchFilteredTracks = usableTracks
        } else {
            searchFilteredTracks = usableTracks.filter { track in
                searchableText(for: track)
                    .range(of: trimmedSearch, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }

        let filteredTracks = searchFilteredTracks.filter {
            filter.includes(track: $0, showsAlbumArtist: showsAlbumArtist)
        }
        return filteredTracks.sorted(by: sortMode.comparator(showsAlbumArtist: showsAlbumArtist))
    }

    private var shouldShowGroups: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && filter == .none
            && sortMode != .title
    }

    private var visibleGroups: [MacLibraryGroup] {
        let usableTracks = library.usableTracks(from: tracks)

        switch sortMode {
        case .title:
            return []
        case .artist:
            return groups(
                from: usableTracks,
                key: { $0.displayArtist(showsAlbumArtist: showsAlbumArtist) },
                sortKey: \.artistSortKey,
                indexKey: \.artistIndexKey,
                makeFilter: { .artist($0) }
            )
        case .album:
            return groups(
                from: usableTracks,
                key: \.displayAlbum,
                sortKey: \.albumSortKey,
                indexKey: \.albumIndexKey,
                makeFilter: { .album($0) }
            )
        case .genre:
            return groups(
                from: usableTracks,
                key: { $0.genre.isEmpty ? "Unknown Genre" : $0.genre },
                sortKey: { MusicLibraryController.titleSortKeys(for: $0.genre.isEmpty ? "Unknown Genre" : $0.genre).sortKey },
                indexKey: { MusicLibraryController.titleSortKeys(for: $0.genre.isEmpty ? "Unknown Genre" : $0.genre).indexKey },
                makeFilter: { .genre($0) }
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                libraryPane
                    .frame(width: proxy.size.width / 3)

                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 0.5)

                MacNowPlayingView(
                    library: library,
                    onMetadataSearchRequest: { request in
                        filter = .none
                        searchText = request.query
                    }
                )
                    .frame(width: proxy.size.width * 2 / 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background)
    }

    private var libraryPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear Search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding([.horizontal, .top], 14)
            .padding(.bottom, 8)

            ScrollViewReader { scrollProxy in
                GeometryReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if filter != .none {
                                Button {
                                    filter = .none
                                } label: {
                                    Label(filter.title, systemImage: "chevron.left")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }

                            if shouldShowGroups {
                                ForEach(visibleGroups) { group in
                                    Button {
                                        filter = group.filter
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(group.title)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text("\(group.tracks.count) Tracks")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .id(group.id)
                                }
                            } else {
                                ForEach(visibleTracks, id: \.relativePath) { track in
                                    Button {
                                        library.playOrQueueAfterCurrent(track)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(track.displayTitle)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text(track.displayArtist(showsAlbumArtist: showsAlbumArtist))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .id(track.relativePath)
                                }
                            }
                        }
                        .padding(.trailing, titleScrollIndexEntries.count > 1 ? 32 : 0)
                    }
                    .overlay(alignment: .trailing) {
                        MacTitleScrollIndex(
                            entries: titleScrollIndexEntries,
                            availableHeight: proxy.size.height,
                            accentColor: Color(hex: accentColorHex)
                        ) { targetID in
                            withAnimation(.interactiveSpring(response: 0.14, dampingFraction: 0.9, blendDuration: 0)) {
                                scrollProxy.scrollTo(targetID, anchor: .center)
                            }
                        }
                        .padding(.trailing, 8)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Add All") {
                library.addTracksAfterCurrentInTemporaryPlaylist(visibleTracks)
            }
            .disabled(visibleTracks.isEmpty)

            Button("Shuffle All") {
                library.shuffleAll(tracks: visibleTracks)
            }
            .disabled(visibleTracks.isEmpty)

            Divider()

            Button("Sort by Title") {
                sortMode = .title
                filter = .none
            }
            Button("Sort by Artist") {
                sortMode = .artist
                filter = .none
            }
            Button("Sort by Album") {
                sortMode = .album
                filter = .none
            }
            Button("Sort by Genre") {
                sortMode = .genre
                filter = .none
            }
        }
    }

    private var titleScrollIndexEntries: [MacLibraryScrollIndexEntry] {
        if shouldShowGroups {
            switch sortMode {
            case .artist, .album:
                return groupScrollIndexEntries
            case .title, .genre:
                return []
            }
        }

        var entriesByKey: [String: MacLibraryScrollIndexEntry] = [:]

        for (order, track) in visibleTracks.enumerated() {
            let key = scrollIndexKey(for: track)

            if let existing = entriesByKey[key] {
                entriesByKey[key] = existing.addingOccurrence()
            } else {
                entriesByKey[key] = MacLibraryScrollIndexEntry(
                    key: key,
                    targetID: track.relativePath,
                    occurrenceCount: 1,
                    order: order
                )
            }
        }

        return entriesByKey.values.sorted {
            if $0.order != $1.order {
                return $0.order < $1.order
            }

            return $0.key < $1.key
        }
    }

    private func scrollIndexKey(for track: MusicTrack) -> String {
        switch sortMode {
        case .title, .genre:
            return track.titleIndexKey.isEmpty
                ? MusicLibraryController.titleSortKeys(for: track.displayTitle).indexKey
                : track.titleIndexKey
        case .artist:
            return track.artistIndexKey.isEmpty
                ? MusicLibraryController.titleSortKeys(for: track.displayArtist(showsAlbumArtist: showsAlbumArtist)).indexKey
                : track.artistIndexKey
        case .album:
            return track.albumIndexKey.isEmpty
                ? MusicLibraryController.titleSortKeys(for: track.displayAlbum).indexKey
                : track.albumIndexKey
        }
    }

    private var groupScrollIndexEntries: [MacLibraryScrollIndexEntry] {
        var entriesByKey: [String: MacLibraryScrollIndexEntry] = [:]

        for (order, group) in visibleGroups.enumerated() {
            let key = group.indexKey.isEmpty
                ? MusicLibraryController.titleSortKeys(for: group.title).indexKey
                : group.indexKey

            if let existing = entriesByKey[key] {
                entriesByKey[key] = existing.addingOccurrenceCount(group.tracks.count)
            } else {
                entriesByKey[key] = MacLibraryScrollIndexEntry(
                    key: key,
                    targetID: group.id,
                    occurrenceCount: group.tracks.count,
                    order: order
                )
            }
        }

        return entriesByKey.values.sorted {
            if $0.order != $1.order {
                return $0.order < $1.order
            }

            return $0.key < $1.key
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

    private func groups(
        from tracks: [MusicTrack],
        key: (MusicTrack) -> String,
        sortKey: (MusicTrack) -> String,
        indexKey: (MusicTrack) -> String,
        makeFilter: (String) -> MacLibraryFilter
    ) -> [MacLibraryGroup] {
        Dictionary(grouping: tracks, by: key)
            .map { title, tracks in
                let fallbackKeys = MusicLibraryController.titleSortKeys(for: title)
                let groupSortKey = tracks
                    .map { sortKey($0) }
                    .filter { !$0.isEmpty }
                    .min() ?? fallbackKeys.sortKey
                let groupIndexKey = tracks
                    .map { indexKey($0) }
                    .first { !$0.isEmpty } ?? fallbackKeys.indexKey

                return MacLibraryGroup(
                    title: title,
                    tracks: tracks.sorted(by: MusicLibraryController.compareTracksByTitleSortKey),
                    filter: makeFilter(title),
                    sortKey: groupSortKey,
                    indexKey: groupIndexKey
                )
            }
            .sorted {
                if $0.sortKey != $1.sortKey {
                    return $0.sortKey < $1.sortKey
                }

                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }
}

private enum MacLibrarySortMode {
    case title
    case artist
    case album
    case genre

    func comparator(showsAlbumArtist: Bool) -> (MusicTrack, MusicTrack) -> Bool {
        switch self {
        case .title:
            return MusicLibraryController.compareTracksByTitleSortKey
        case .artist:
            return { lhs, rhs in
                if lhs.artistSortKey != rhs.artistSortKey {
                    return lhs.artistSortKey < rhs.artistSortKey
                }

                let lhsArtist = lhs.displayArtist(showsAlbumArtist: showsAlbumArtist)
                let rhsArtist = rhs.displayArtist(showsAlbumArtist: showsAlbumArtist)
                if lhsArtist != rhsArtist {
                    return lhsArtist.localizedCaseInsensitiveCompare(rhsArtist) == .orderedAscending
                }
                return MusicLibraryController.compareTracksByTitleSortKey(lhs, rhs)
            }
        case .album:
            return { lhs, rhs in
                if lhs.albumSortKey != rhs.albumSortKey {
                    return lhs.albumSortKey < rhs.albumSortKey
                }
                return MusicLibraryController.compareTracksByTitleSortKey(lhs, rhs)
            }
        case .genre:
            return { lhs, rhs in
                if lhs.genre != rhs.genre {
                    return lhs.genre.localizedCaseInsensitiveCompare(rhs.genre) == .orderedAscending
                }
                return MusicLibraryController.compareTracksByTitleSortKey(lhs, rhs)
            }
        }
    }
}

private enum MacLibraryFilter: Equatable {
    case none
    case artist(String)
    case album(String)
    case genre(String)

    var title: String {
        switch self {
        case .none:
            return "Library"
        case .artist(let value), .album(let value), .genre(let value):
            return value
        }
    }

    func includes(track: MusicTrack, showsAlbumArtist: Bool) -> Bool {
        switch self {
        case .none:
            return true
        case .artist(let artist):
            return track.displayArtist(showsAlbumArtist: showsAlbumArtist) == artist
        case .album(let album):
            return track.displayAlbum == album
        case .genre(let genre):
            return (track.genre.isEmpty ? "Unknown Genre" : track.genre) == genre
        }
    }
}

private struct MacLibraryGroup: Identifiable {
    let title: String
    let tracks: [MusicTrack]
    let filter: MacLibraryFilter
    let sortKey: String
    let indexKey: String

    var id: String { "\(sortKey)-\(title)" }
}

private struct MacLibraryScrollIndexEntry: Identifiable, Equatable {
    let key: String
    let targetID: String
    let occurrenceCount: Int
    let order: Int

    var id: String { key }

    func addingOccurrence() -> MacLibraryScrollIndexEntry {
        addingOccurrenceCount(1)
    }

    func addingOccurrenceCount(_ count: Int) -> MacLibraryScrollIndexEntry {
        MacLibraryScrollIndexEntry(
            key: key,
            targetID: targetID,
            occurrenceCount: occurrenceCount + count,
            order: order
        )
    }
}

private struct MacTitleScrollIndex: View {
    let entries: [MacLibraryScrollIndexEntry]
    let availableHeight: CGFloat
    let accentColor: Color
    let onSelect: (String) -> Void
    @State private var activeKey: String?
    @State private var displayedKey = ""
    @State private var displayedTouchY: CGFloat = 0
    @State private var dismissTask: Task<Void, Never>?
    @State private var feedback = UISelectionFeedbackGenerator()

    private let rowHeight: CGFloat = 13
    private let magnifierSize: CGFloat = 44

    var body: some View {
        let visibleEntries = thinnedEntries
        let capsuleHeight = CGFloat(visibleEntries.count) * rowHeight + 12

        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                ForEach(visibleEntries) { entry in
                    Text(entry.key)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(activeKey == entry.key ? accentColor : .secondary)
                        .frame(width: 18, height: rowHeight)
                        .contentShape(Rectangle())
                }
            }
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .frame(maxWidth: .infinity, alignment: .trailing)

            Text(displayedKey)
                .font(.headline.bold())
                .foregroundStyle(.primary)
                .frame(width: magnifierSize, height: magnifierSize)
                .background(.thinMaterial, in: Circle())
                .position(
                    x: magnifierSize / 2 - 4,
                    y: min(max(displayedTouchY, magnifierSize / 2), availableHeight - magnifierSize / 2)
                )
                .blur(radius: activeKey == nil ? 14 : 0)
                .opacity(activeKey == nil ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: activeKey == nil)
                .allowsHitTesting(false)
        }
        .opacity(visibleEntries.count > 1 ? 1 : 0)
        .allowsHitTesting(visibleEntries.count > 1)
        .contentShape(Rectangle())
        .frame(width: magnifierSize + 28)
        .frame(maxHeight: .infinity, alignment: .trailing)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    dismissTask?.cancel()
                    dismissTask = nil
                    displayedTouchY = value.location.y
                    let topInset = max((availableHeight - capsuleHeight) / 2, 0)
                    selectEntry(at: value.location.y - topInset - 6, from: visibleEntries)
                }
                .onEnded { _ in
                    dismissTask?.cancel()
                    dismissTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled else { return }
                        activeKey = nil
                    }
                }
        )
        .onAppear {
            feedback.prepare()
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    private var thinnedEntries: [MacLibraryScrollIndexEntry] {
        guard !entries.isEmpty else { return [] }

        let maxCount = max(1, Int((availableHeight * AppStyle.titleScrollIndexHeightFraction) / rowHeight))
        guard entries.count > maxCount else { return entries }

        let selectedIDs = Set(
            entries
                .sorted {
                    if $0.occurrenceCount != $1.occurrenceCount {
                        return $0.occurrenceCount > $1.occurrenceCount
                    }

                    return $0.order < $1.order
                }
                .prefix(maxCount)
                .map(\.id)
        )

        return entries.filter { selectedIDs.contains($0.id) }
    }

    private func selectEntry(at yPosition: CGFloat, from visibleEntries: [MacLibraryScrollIndexEntry]) {
        guard !visibleEntries.isEmpty else { return }

        let index = min(max(Int(yPosition / rowHeight), 0), visibleEntries.count - 1)
        let entry = visibleEntries[index]

        guard activeKey != entry.key else { return }

        activeKey = entry.key
        displayedKey = entry.key
        feedback.selectionChanged()
        feedback.prepare()
        onSelect(entry.targetID)
    }
}
