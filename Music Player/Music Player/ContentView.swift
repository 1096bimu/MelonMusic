//
//  ContentView.swift
//  Music Player
//
//  Created by Chen on 2026-05-05.
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let defaultAccentColorHex = "#00D9A7"
private let accentColorStorageKey = "accentColorHex"

private enum AppTab {
    case library
    case nowPlaying
    case management
}

private enum LibraryNavigationTarget: Equatable {
    case artist(String)
    case album(String)
}

private struct LibraryNavigationRequest: Equatable {
    let id = UUID()
    let target: LibraryNavigationTarget
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("usesDarkMode") private var usesDarkMode = false
    @AppStorage("isCustomizationUnlocked") private var isCustomizationUnlocked = false
    @AppStorage(accentColorStorageKey) private var accentColorHex = defaultAccentColorHex
    @StateObject private var library = MusicLibraryController()
    @StateObject private var customizationPurchaseController = CustomizationPurchaseController()
    @State private var selectedTab: AppTab = .library
    @State private var libraryNavigationRequest: LibraryNavigationRequest?
    @State private var nowPlayingTabPulse = 0
    @State private var isShowingNowPlayingTabPop = false
    @State private var nowPlayingTabCenter: CGPoint?
    @State private var pendingLibrarySelectionHaptics = 0
    @State private var isProcessingLibrarySelectionHaptics = false
    @State private var librarySelectionHaptics = UISelectionFeedbackGenerator()

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                MusicListView(
                    library: library,
                    navigationRequest: libraryNavigationRequest,
                    onShuffleAll: {
                    selectedTab = .nowPlaying
                    },
                    onSongSelected: {
                        queueLibrarySelectionFeedback()
                    }
                )
                    .tabItem {
                        Label("Library", systemImage: "music.note.list")
                    }
                    .tag(AppTab.library)

                NowPlayingView(library: library, onLibraryNavigationRequest: { target in
                        selectedTab = .library
                        libraryNavigationRequest = LibraryNavigationRequest(target: target)
                    })
                    .tabItem {
                        Label("Now Playing", systemImage: "play.circle")
                    }
                    .tag(AppTab.nowPlaying)

                ManagementView(
                    library: library,
                    customizationPurchaseController: customizationPurchaseController
                )
                    .tabItem {
                        Label("Management", systemImage: "folder.badge.gearshape")
                    }
                    .tag(AppTab.management)
            }
            .toolbarBackground(
                Color(.systemBackground).opacity(AppStyle.tabBarAndShuffleAllBackgroundOpacity),
                for: .tabBar
            )
            .toolbarBackground(.visible, for: .tabBar)

            TabBarItemCenterReader(itemIndex: 1) { center in
                nowPlayingTabCenter = center
            }

            GeometryReader { proxy in
                NowPlayingTabPopView(
                    accentColor: Color(hex: accentColorHex),
                    isVisible: isShowingNowPlayingTabPop
                )
                .position(nowPlayingTabCenter ?? fallbackNowPlayingTabCenter(in: proxy))
            }
            .allowsHitTesting(false)
        }
        .preferredColorScheme(isCustomizationUnlocked ? (usesDarkMode ? .dark : .light) : nil)
        .tint(Color(hex: accentColorHex))
        .task {
            librarySelectionHaptics.prepare()
            library.prepareStorage()
            if library.didCopyBundledSampleMusic {
                await library.scan(using: modelContext)
            } else {
                library.refreshStats(using: modelContext)
            }
            await customizationPurchaseController.start()
            if !customizationPurchaseController.hasCustomizationEntitlement {
                isCustomizationUnlocked = false
            }
        }
        .onChange(of: customizationPurchaseController.hasCustomizationEntitlement) {
            guard customizationPurchaseController.hasLoadedEntitlements else { return }

            if !customizationPurchaseController.hasCustomizationEntitlement {
                isCustomizationUnlocked = false
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                library.reconcilePlaybackAfterForeground()
            }

            if scenePhase != .active {
                library.persistTemporaryPlaylistState()
            }
        }
    }

    private func queueLibrarySelectionFeedback() {
        pendingLibrarySelectionHaptics += 1
        nowPlayingTabPulse += 1
        showNowPlayingTabPop()
        processLibrarySelectionFeedbackQueue()
    }

    private func showNowPlayingTabPop() {
        isShowingNowPlayingTabPop = false

        Task { @MainActor in
            await Task.yield()
            withAnimation(.spring(response: 0.22, dampingFraction: 0.48)) {
                isShowingNowPlayingTabPop = true
            }

            try? await Task.sleep(for: .milliseconds(170))

            withAnimation(.easeOut(duration: 0.16)) {
                isShowingNowPlayingTabPop = false
            }
        }
    }

    private func processLibrarySelectionFeedbackQueue() {
        guard !isProcessingLibrarySelectionHaptics else { return }

        isProcessingLibrarySelectionHaptics = true

        Task { @MainActor in
            while pendingLibrarySelectionHaptics > 0 {
                pendingLibrarySelectionHaptics -= 1
                librarySelectionHaptics.selectionChanged()
                librarySelectionHaptics.prepare()
                try? await Task.sleep(for: .milliseconds(90))
            }

            isProcessingLibrarySelectionHaptics = false
        }
    }

    private func fallbackNowPlayingTabCenter(in proxy: GeometryProxy) -> CGPoint {
        CGPoint(
            x: proxy.size.width / 2,
            y: proxy.size.height - proxy.safeAreaInsets.bottom - 24
        )
    }

}

private struct NowPlayingTabPopView: View {
    let accentColor: Color
    let isVisible: Bool

    var body: some View {
        Image(systemName: "plus.circle.fill")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(accentColor)
            .symbolRenderingMode(.hierarchical)
            .scaleEffect(isVisible ? 1.45 : 0.82)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(false)
    }
}

private struct TabBarItemCenterReader: UIViewRepresentable {
    let itemIndex: Int
    let onChange: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            updateCenter(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            updateCenter(from: uiView)
        }
    }

    private func updateCenter(from view: UIView) {
        guard let window = view.window,
              let tabBar = findTabBar(in: window)
        else {
            return
        }

        let itemViews = tabBar.subviews
            .filter { String(describing: type(of: $0)).contains("UITabBarButton") }
            .sorted { $0.frame.minX < $1.frame.minX }

        guard itemViews.indices.contains(itemIndex) else { return }

        let itemFrame = itemViews[itemIndex].convert(itemViews[itemIndex].bounds, to: window)
        onChange(CGPoint(x: itemFrame.midX, y: itemFrame.midY))
    }

    private func findTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar {
            return tabBar
        }

        for subview in view.subviews {
            if let tabBar = findTabBar(in: subview) {
                return tabBar
            }
        }

        return nil
    }
}

private struct BackgroundImageView: View {
    let imageData: Data

    var body: some View {
        GeometryReader { proxy in
            if let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private let localizedFallbackValues: Set<String> = [
    "Unknown Genre",
    "Unknown Album",
    "Unknown Artist",
    "Unknown Album Artist"
]

private func localizedFallbackString(_ value: String, locale: Locale) -> String {
    guard localizedFallbackValues.contains(value) else { return value }
    return String(localized: String.LocalizationValue(value), locale: locale)
}

private struct MusicListView: View {
    @ObservedObject var library: MusicLibraryController
    let navigationRequest: LibraryNavigationRequest?
    let onShuffleAll: () -> Void
    let onSongSelected: () -> Void
    @Environment(\.locale) private var locale
    @Query(sort: \MusicTrack.title, order: .forward) private var tracks: [MusicTrack]
    @AppStorage("nowPlayingShowsAlbumArtist") private var showsAlbumArtist = false
    @AppStorage("backgroundImageData") private var backgroundImageData = Data()
    @AppStorage("isAlbumSortingModeDisabled") private var isAlbumSortingModeDisabled = false
    @AppStorage("isGenreSortingModeDisabled") private var isGenreSortingModeDisabled = false
    @State private var listMode: LibraryListMode = .title

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundImageView(imageData: backgroundImageData)
                LibraryBackgroundGradient()

                GeometryReader { proxy in
                    HStack(alignment: .top, spacing: 0) {
                        libraryPage(title: listMode.topLevelHeaderTitle(showsAlbumArtist: showsAlbumArtist)) {
                            if tracks.isEmpty {
                                ContentUnavailableView(
                                    "No Music Found",
                                    systemImage: "music.note",
                                    description: Text("Add audio files to the music folder in Files, then scan from Management.")
                                )
                                .padding(.top, 40)
                            } else {
                                topLevelRows
                            }
                        }
                        .frame(width: proxy.size.width)

                        libraryPage(title: "Back") {
                            selectedTrackRows
                        }
                        .frame(width: proxy.size.width)
                    }
                    .offset(x: listMode.isSelectionMode ? -proxy.size.width : 0)
                    .animation(.snappy(duration: 0.32), value: listMode)
                }
            }
            .background(Color.clear)
            .onChange(of: showsAlbumArtist) {
                listMode = .title
            }
            .onChange(of: isGenreSortingModeDisabled) {
                if listMode.isGenreMode {
                    listMode = .title
                }
            }
            .onChange(of: isAlbumSortingModeDisabled) {
                if listMode.isAlbumMode {
                    listMode = .title
                }
            }
            .onChange(of: navigationRequest) {
                handleNavigationRequest()
            }
            .simultaneousGesture(leftEdgeBackGesture)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        handleLibraryToolbarButtonTap()
                    } label: {
                        Text(LocalizedStringKey(libraryToolbarButtonTitle))
                    }
                    .disabled(displayedTracks.isEmpty)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Color(.systemBackground).opacity(AppStyle.tabBarAndShuffleAllBackgroundOpacity),
                        in: Capsule()
                    )
                }
            }
        }
        .background(Color.clear)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var sortedTracks: [MusicTrack] {
        tracks.sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }

    private var displayedTracks: [MusicTrack] {
        switch listMode {
        case .title, .genre, .artist, .album:
            return sortedTracks
        case .genreSelection(let genre):
            return tracks(for: genre)
        case .artistSelection(let artist):
            return tracks(forArtistName: artist)
        case .albumSelection(let album):
            return tracks(forAlbumName: album)
        }
    }

    private var isShowingFilteredTrackList: Bool {
        switch listMode {
        case .genreSelection, .artistSelection, .albumSelection:
            return true
        default:
            return false
        }
    }

    private var libraryToolbarButtonTitle: String {
        isShowingFilteredTrackList ? "Add All" : "Shuffle All"
    }

    @ViewBuilder
    private func libraryPage<Rows: View>(
        title: String,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Button {
                    handleHeaderTap()
                } label: {
                    Text(LocalizedStringKey(title))
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                rows()
            }
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private var topLevelRows: some View {
        switch listMode.topLevelMode {
        case .title:
            trackRows(for: sortedTracks)
        case .genre:
            genreRows
        case .artist:
            artistRows
        case .album:
            albumRows
        case .genreSelection, .artistSelection, .albumSelection:
            EmptyView()
        }
    }

    @ViewBuilder
    private var selectedTrackRows: some View {
        switch listMode {
        case .genreSelection(let genre):
            trackRows(for: tracks(for: genre))
        case .artistSelection(let artist):
            trackRows(for: tracks(forArtistName: artist))
        case .albumSelection(let album):
            trackRows(for: tracks(forAlbumName: album))
        case .title, .genre, .artist, .album:
            EmptyView()
        }
    }

    private func handleLibraryToolbarButtonTap() {
        if isShowingFilteredTrackList {
            library.addTracksAfterCurrentInTemporaryPlaylist(displayedTracks)
            onSongSelected()
        } else {
            library.shuffleAll(tracks: sortedTracks)
            onShuffleAll()
        }
    }

    private func handleNavigationRequest() {
        guard let navigationRequest else { return }

        withAnimation(.snappy(duration: 0.32)) {
            switch navigationRequest.target {
            case .artist(let artist):
                listMode = .artistSelection(artist)
            case .album(let album):
                guard !isAlbumSortingModeDisabled else { return }
                listMode = .albumSelection(album)
            }
        }
    }

    private var genreRows: some View {
        ForEach(availableGenres, id: \.self) { genre in
            Button {
                withAnimation(.snappy(duration: 0.32)) {
                    listMode = .genreSelection(genre)
                }
            } label: {
                Text(localizedFallbackString(genre, locale: locale))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
        }
    }

    private var artistRows: some View {
        ForEach(availableArtists, id: \.self) { artist in
            Button {
                withAnimation(.snappy(duration: 0.32)) {
                    listMode = .artistSelection(artist)
                }
            } label: {
                Text(localizedFallbackString(artist, locale: locale))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
        }
    }

    private var albumRows: some View {
        ForEach(availableAlbums, id: \.self) { album in
            Button {
                withAnimation(.snappy(duration: 0.32)) {
                    listMode = .albumSelection(album)
                }
            } label: {
                Text(localizedFallbackString(album, locale: locale))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
        }
    }

    private func trackRows(for tracks: [MusicTrack]) -> some View {
        ForEach(tracks) { track in
            LibraryTrackButton(track: track) {
                guard library.currentTrack?.relativePath != track.relativePath else { return }

                library.play(track)
                onSongSelected()
            }
        }
    }

    private var availableGenres: [String] {
        Set(tracks.map { normalizedGenre($0.genre) })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var availableArtists: [String] {
        Set(tracks.map { artistName(for: $0) })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var availableAlbums: [String] {
        Set(tracks.map { normalizedAlbum($0.album) })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func tracks(for genre: String) -> [MusicTrack] {
        sortedTracks.filter { normalizedGenre($0.genre) == genre }
    }

    private func tracks(forArtistName artist: String) -> [MusicTrack] {
        sortedTracks
            .filter { artistName(for: $0) == artist }
            .sorted {
                let artistComparison = artistName(for: $0).localizedCaseInsensitiveCompare(artistName(for: $1))
                if artistComparison != .orderedSame {
                    return artistComparison == .orderedAscending
                }

                return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
    }

    private func tracks(forAlbumName album: String) -> [MusicTrack] {
        sortedTracks.filter { normalizedAlbum($0.album) == album }
    }

    private func normalizedGenre(_ genre: String) -> String {
        let trimmedGenre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedGenre.isEmpty ? "Unknown Genre" : trimmedGenre
    }

    private func normalizedAlbum(_ album: String) -> String {
        let trimmedAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedAlbum.isEmpty ? "Unknown Album" : trimmedAlbum
    }

    private func artistName(for track: MusicTrack) -> String {
        showsAlbumArtist ? track.displayAlbumArtist : track.displayArtist
    }

    private func handleHeaderTap() {
        switch listMode {
        case .title:
            listMode = firstAvailableModeAfterTitle
        case .genre:
            listMode = .artist
        case .artist:
            listMode = isAlbumSortingModeDisabled ? .title : .album
        case .album:
            listMode = .title
        case .genreSelection:
            withAnimation(.snappy(duration: 0.32)) {
                listMode = .genre
            }
        case .artistSelection:
            withAnimation(.snappy(duration: 0.32)) {
                listMode = .artist
            }
        case .albumSelection:
            withAnimation(.snappy(duration: 0.32)) {
                listMode = .album
            }
        }
    }

    private func goBackOneLevelIfNeeded() {
        guard listMode.isSelectionMode else { return }
        handleHeaderTap()
    }

    private var leftEdgeBackGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                let isLeftEdgeSwipe = value.startLocation.x <= 36
                let isMovingRight = value.translation.width > 64
                let isMostlyHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.25

                guard isLeftEdgeSwipe, isMovingRight, isMostlyHorizontal else { return }
                goBackOneLevelIfNeeded()
            }
    }

    private var firstAvailableModeAfterTitle: LibraryListMode {
        if !isGenreSortingModeDisabled {
            return .genre
        }

        return .artist
    }
}

private struct LibraryTrackButton: View {
    let track: MusicTrack
    let onTap: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(localizedFallbackString(track.displayArtist, locale: locale))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

private struct LibraryBackgroundGradient: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(.systemBackground).opacity(AppStyle.backgroundGradientMaxOpacity), location: 0),
                .init(color: Color(.systemBackground).opacity(0), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private enum LibraryListMode: Equatable {
    case title
    case genre
    case genreSelection(String)
    case artist
    case artistSelection(String)
    case album
    case albumSelection(String)

    func headerTitle(showsAlbumArtist: Bool) -> String {
        switch self {
        case .title:
            return "Title"
        case .genre:
            return "Genre"
        case .genreSelection:
            return "Back"
        case .artist:
            return showsAlbumArtist ? "Album Artist" : "Artist"
        case .artistSelection:
            return "Back"
        case .album:
            return "Album"
        case .albumSelection:
            return "Back"
        }
    }

    func topLevelHeaderTitle(showsAlbumArtist: Bool) -> String {
        topLevelMode.headerTitle(showsAlbumArtist: showsAlbumArtist)
    }

    var isGenreMode: Bool {
        switch self {
        case .genre, .genreSelection:
            return true
        default:
            return false
        }
    }

    var isAlbumMode: Bool {
        switch self {
        case .album, .albumSelection:
            return true
        default:
            return false
        }
    }

    var isSelectionMode: Bool {
        switch self {
        case .genreSelection, .artistSelection, .albumSelection:
            return true
        default:
            return false
        }
    }

    var topLevelMode: LibraryListMode {
        switch self {
        case .genreSelection:
            return .genre
        case .artistSelection:
            return .artist
        case .albumSelection:
            return .album
        default:
            return self
        }
    }

}

private struct NowPlayingView: View {
    @ObservedObject var library: MusicLibraryController
    @AppStorage("backgroundImageData") private var backgroundImageData = Data()
    @AppStorage(accentColorStorageKey) private var accentColorHex = defaultAccentColorHex
    @AppStorage("isAlbumSortingModeDisabled") private var isAlbumSortingModeDisabled = false
    @State private var loopHaptics = UINotificationFeedbackGenerator()
    @State private var shuffleClearHaptics = UINotificationFeedbackGenerator()
    @State private var repeatLongPressDidToggle = false
    @State private var shuffleLongPressDidClear = false
    var onLibraryNavigationRequest: (LibraryNavigationTarget) -> Void = { _ in }

    var body: some View {
        ZStack {
            BackgroundImageView(imageData: backgroundImageData)
            NowPlayingBackgroundGradient()

            VStack(spacing: 0) {
              

                NowPlayingMetadataView(
                    track: library.currentTrack,
                    isAlbumLinkEnabled: !isAlbumSortingModeDisabled,
                    onLibraryNavigationRequest: onLibraryNavigationRequest
                )
                    .padding(.horizontal, 28)
                    .padding(.bottom, 18)

                AlbumArtView(library: library, track: library.currentTrack)
                    .frame(width: 360, height: 360)
                    .zIndex(100)

                TemporaryPlaylistScroller(library: library)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .padding(.bottom, -8)

                HStack {
                    Button {
                        if shuffleLongPressDidClear {
                            shuffleLongPressDidClear = false
                            return
                        }

                        library.shuffleTemporaryPlaylistKeepingCurrentSongCentered()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 54, height: 54)
                            .controlButtonSurface(fill: Color(.quaternarySystemFill))
                            .foregroundStyle(Color.primary)
                            .tint(Color.primary)
                    }
                    .disabled(library.temporaryPlaylist.isEmpty)
                    .opacity(library.temporaryPlaylist.isEmpty ? AppStyle.nowPlayingControlDisabledOpacity : 1)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: AppStyle.longPressDuration)
                            .onEnded { _ in
                                shuffleLongPressDidClear = true

                                if library.playbackIntent == .play {
                                    library.removeAllTemporaryPlaylistItemsExceptCurrent()
                                } else {
                                    library.clearTemporaryPlaylistAndCurrentSelection()
                                }

                                shuffleClearHaptics.notificationOccurred(.success)
                                shuffleClearHaptics.prepare()

                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(500))
                                    shuffleLongPressDidClear = false
                                }
                            }
                    )

                    Spacer()

                    Button {
                        library.togglePlayPause()
                    } label: {
                        Image(systemName: library.playbackIntent == .play ? "pause.fill" : "play.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .frame(width: 82, height: 82)
                            .controlButtonSurface(fill: library.isPlaying ? Color(hex: accentColorHex) : Color.primary)
                            .foregroundStyle(Color(.systemBackground))
                    }
                    .disabled(library.currentTrack == nil && library.temporaryPlaylist.isEmpty)
                    .opacity(library.currentTrack == nil && library.temporaryPlaylist.isEmpty ? AppStyle.nowPlayingControlDisabledOpacity : 1)

                    Spacer()

                    Button {
                        if repeatLongPressDidToggle {
                            repeatLongPressDidToggle = false
                            return
                        }

                        library.replayCurrentTrack()
                    } label: {
                        Image(systemName: library.isSingleSongLoopEnabled ? "repeat.1" : "repeat")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 54, height: 54)
                            .controlButtonSurface(fill: library.isSingleSongLoopEnabled ? Color(hex: accentColorHex) : Color(.quaternarySystemFill))
                            .foregroundStyle(library.isSingleSongLoopEnabled ? .white : .primary)
                    }
                    .disabled(library.currentTrack == nil)
                    .opacity(library.currentTrack == nil ? AppStyle.nowPlayingControlDisabledOpacity : 1)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: AppStyle.longPressDuration)
                            .onEnded { _ in
                                repeatLongPressDidToggle = true
                                library.toggleSingleSongLoop()
                                loopHaptics.notificationOccurred(.success)
                                loopHaptics.prepare()

                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(500))
                                    repeatLongPressDidToggle = false
                                }
                            }
                    )
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                loopHaptics.prepare()
                shuffleClearHaptics.prepare()
            }
        }
    }
}

private struct NowPlayingBackgroundGradient: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(.systemBackground).opacity(AppStyle.backgroundGradientMaxOpacity), location: 0.1),
                .init(color: Color(.systemBackground).opacity(0), location: 0.4),
                .init(color: Color(.systemBackground).opacity(0), location: 0.5),
                .init(color: Color(.systemBackground).opacity(AppStyle.backgroundGradientMaxOpacity), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private extension View {
    @ViewBuilder
    func controlButtonSurface(fill: Color) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(fill.opacity(AppStyle.nowPlayingControlGlassTintOpacity)).interactive(), in: Circle())
        } else {
            self.background(fill.opacity(AppStyle.nowPlayingControlSurfaceOpacity), in: Circle())
        }
    }
}

private struct NowPlayingMetadataView: View {
    let track: MusicTrack?
    let isAlbumLinkEnabled: Bool
    let onLibraryNavigationRequest: (LibraryNavigationTarget) -> Void
    @Environment(\.locale) private var locale
    @AppStorage("nowPlayingShowsAlbumArtist") private var showsAlbumArtist = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if let track {
                    onLibraryNavigationRequest(.artist(primaryArtistRawText(for: track)))
                }
            } label: {
                ZStack(alignment: .leading) {
                    Color.clear
                    ScrollingSingleLineText(text: primaryArtistText)
                }
            }
            .buttonStyle(.plain)
            .disabled(track == nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 40)

            Button {
                if let track, isAlbumLinkEnabled {
                    onLibraryNavigationRequest(.album(track.displayAlbum))
                }
            } label: {
                ShrinkingParagraphText(text: albumText)
            }
            .buttonStyle(.plain)
            .frame(height: 66)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryArtistText: String {
        guard let track else {
            let fallback = showsAlbumArtist ? "Unknown Album Artist" : "Unknown Artist"
            return localizedFallbackString(fallback, locale: locale)
        }

        let artist = showsAlbumArtist ? track.displayAlbumArtist : track.displayArtist
        return localizedFallbackString(artist, locale: locale)
    }

    private var albumText: String {
        localizedFallbackString(track?.displayAlbum ?? "Unknown Album", locale: locale)
    }

    private func primaryArtistRawText(for track: MusicTrack) -> String {
        showsAlbumArtist ? track.displayAlbumArtist : track.displayArtist
    }
}

private struct ScrollingSingleLineText: View {
    let text: String
    @State private var containerWidth = 0.0
    @State private var textWidth = 0.0
    @State private var textOffset = 0.0
    @State private var marqueeTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            Text(text)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: textOffset)
                .background {
                    GeometryReader { textProxy in
                        Color.clear
                            .preference(key: SingleLineTextWidthKey.self, value: textProxy.size.width)
                    }
                }
                .frame(width: proxy.size.width, alignment: .leading)
                .clipped()
                .mask(alignment: .leading) {
                    SingleLineTextFadeMask(isOverflowing: isOverflowing)
                }
                .onAppear {
                    updateContainerWidth(proxy.size.width)
                }
                .onChange(of: proxy.size.width) {
                    updateContainerWidth(proxy.size.width)
                }
                .onPreferenceChange(SingleLineTextWidthKey.self) { width in
                    textWidth = width
                    restartMarqueeIfNeeded()
                }
        }
        .onChange(of: text) {
            textOffset = 0
            restartMarqueeIfNeeded()
        }
        .onDisappear {
            marqueeTask?.cancel()
        }
    }

    private var overflowDistance: Double {
        max(0, textWidth - containerWidth)
    }

    private var isOverflowing: Bool {
        overflowDistance > 1
    }

    private func updateContainerWidth(_ width: Double) {
        guard containerWidth != width else { return }

        containerWidth = width
        restartMarqueeIfNeeded()
    }

    private func restartMarqueeIfNeeded() {
        marqueeTask?.cancel()

        guard isOverflowing else {
            textOffset = 0
            return
        }

        let distance = overflowDistance
        let duration = distance / max(AppStyle.artistMarqueeScrollSpeed, 1)

        marqueeTask = Task { @MainActor in
            textOffset = 0

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AppStyle.artistMarqueeStartDelay))
                guard !Task.isCancelled else { return }

                withAnimation(.linear(duration: duration)) {
                    textOffset = -distance
                }

                try? await Task.sleep(for: .seconds(duration + AppStyle.artistMarqueeEndDelay))
                guard !Task.isCancelled else { return }

                withAnimation(.easeOut(duration: AppStyle.artistMarqueeResetDelay)) {
                    textOffset = 0
                }

                try? await Task.sleep(for: .seconds(AppStyle.artistMarqueeResetDelay))
            }
        }
    }
}

private struct SingleLineTextFadeMask: View {
    let isOverflowing: Bool

    var body: some View {
        LinearGradient(
            stops: isOverflowing ? [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.86),
                .init(color: .clear, location: 1)
            ] : [
                .init(color: .black, location: 0),
                .init(color: .black, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct SingleLineTextWidthKey: PreferenceKey {
    static let defaultValue = 0.0

    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = nextValue()
    }
}

private struct ShrinkingParagraphText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(nil)
            .minimumScaleFactor(0.35)
            .allowsTightening(true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AlbumArtView: View {
    @ObservedObject var library: MusicLibraryController
    let track: MusicTrack?
    @State private var artworkImage: UIImage?
    @State private var artworkTask: Task<Void, Never>?
    @State private var artworkOpacity = 0.0

    var body: some View {
        ZStack {
            if let artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(artworkOpacity)
            }
        }
        .onAppear {
            loadArtwork()
        }
        .onDisappear {
            artworkTask?.cancel()
        }
        .onChange(of: track?.relativePath) {
            loadArtwork()
        }
    }

    private func loadArtwork() {
        artworkTask?.cancel()

        guard let track else {
            withAnimation(.easeInOut(duration: 0.2)) {
                artworkOpacity = 0
            }

            artworkTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                artworkImage = nil
            }
            return
        }

        artworkTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.2)) {
                artworkOpacity = 0
            }

            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            let image = await Task.detached(priority: .utility) {
                await library.albumArtwork(for: track)
            }.value

            guard !Task.isCancelled else { return }

            artworkImage = image

            withAnimation(.easeInOut(duration: 0.2)) {
                artworkOpacity = image == nil ? 0 : 1
            }
        }
    }
}

private struct TemporaryPlaylistScroller: View {
    @ObservedObject var library: MusicLibraryController
    @State private var selectedTrackPath = ""
    @State private var isScrolling = false
    @State private var settleTask: Task<Void, Never>?
    @State private var isSyncingSelection = false
    @State private var haptics = UISelectionFeedbackGenerator()

    var body: some View {
        Group {
            if library.temporaryPlaylist.isEmpty {
                ContentUnavailableView(
                    "Nothing Playing",
                    systemImage: "music.note",
                    description: Text("Choose a song from Music to start a temporary playlist.")
                )
            } else {
                Picker("", selection: $selectedTrackPath) {
                    ForEach(library.temporaryPlaylist, id: \.relativePath) { track in
                        TemporaryPlaylistRow(
                            track: track,
                            isCentered: track.relativePath == selectedTrackPath
                        )
                        .tag(track.relativePath)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity, maxHeight: 150)
                .clipped()
                .onAppear {
                    haptics.prepare()
                    syncSelectedTrack()
                }
                .onDisappear {
                    settleTask?.cancel()
                }
                .onChange(of: library.currentTrack?.relativePath) {
                    syncSelectedTrack()
                }
                .onChange(of: library.playlistRevision) {
                    syncSelectedTrack()
                }
                .onChange(of: library.playbackTransitionRevision) {
                    syncSelectedTrack()
                }
                .onChange(of: library.playbackIntent) {
                    if library.playbackIntent == .pause {
                        cancelPendingSettle()
                    }
                }
                .onChange(of: selectedTrackPath) {
                    handleSelectionChange()
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            interruptPendingSelection()
                        }
                        .onEnded { _ in
                            scheduleSelectionSettleForCurrentSelection()
                        }
                )
                .padding(.horizontal, 20)
            }
        }
    }

    private func syncSelectedTrack() {
        guard !library.temporaryPlaylist.isEmpty else {
            selectedTrackPath = ""
            return
        }

        if let currentRelativePath = library.currentTrack?.relativePath,
           library.temporaryPlaylist.contains(where: { $0.relativePath == currentRelativePath }) {
            setSelectedTrackPathFromSync(currentRelativePath)
        } else if !library.temporaryPlaylist.contains(where: { $0.relativePath == selectedTrackPath }),
                  let firstTrack = library.temporaryPlaylist.first {
            setSelectedTrackPathFromSync(firstTrack.relativePath)
        }
    }

    private func interruptPendingSelection() {
        if !isScrolling {
            isScrolling = true
        }

        settleTask?.cancel()
    }

    private func scheduleSelectionSettleForCurrentSelection() {
        guard
            !selectedTrackPath.isEmpty,
            let index = library.temporaryPlaylist.firstIndex(where: { $0.relativePath == selectedTrackPath })
        else {
            return
        }

        scheduleSelectionSettle(at: index)
    }

    private func handleSelectionChange() {
        guard !isSyncingSelection else { return }
        guard
            !selectedTrackPath.isEmpty,
            let index = library.temporaryPlaylist.firstIndex(where: { $0.relativePath == selectedTrackPath })
        else {
            return
        }

        if !isScrolling {
            isScrolling = true
        }

        haptics.selectionChanged()
        haptics.prepare()

        scheduleSelectionSettle(at: index)
    }

    private func scheduleSelectionSettle(at index: Int) {
        settleTask?.cancel()

        settleTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(800))
                isScrolling = false
                library.settlePlaylistSelection(at: index)
            } catch {
                // New wheel movement cancels this pending selection.
            }
        }
    }

    private func cancelPendingSettle() {
        settleTask?.cancel()
        settleTask = nil
        isScrolling = false
    }

    private func setSelectedTrackPathFromSync(_ path: String) {
        guard selectedTrackPath != path else { return }

        isSyncingSelection = true
        selectedTrackPath = path

        Task { @MainActor in
            await Task.yield()
            isSyncingSelection = false
        }
    }
}

private struct TemporaryPlaylistRow: View {
    let track: MusicTrack
    let isCentered: Bool

    var body: some View {
        VStack(spacing: 5) {
            Text(track.displayTitle)
                .font(isCentered ? .title3.bold() : .headline)
                .foregroundStyle(isCentered ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .multilineTextAlignment(.center)
     
        .frame(height: 22)
        .padding(.horizontal, 18)
        .scaleEffect(isCentered ? 1 : 1)
        .opacity(isCentered ? 1 : 0.75)
        .animation(.snappy(duration: 0.2), value: isCentered)
    }
}

private struct ManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var library: MusicLibraryController
    @ObservedObject var customizationPurchaseController: CustomizationPurchaseController
    @AppStorage("usesDarkMode") private var usesDarkMode = false
    @AppStorage("isCustomizationUnlocked") private var isCustomizationUnlocked = false
    @AppStorage("backgroundImageData") private var backgroundImageData = Data()
    @AppStorage(accentColorStorageKey) private var accentColorHex = defaultAccentColorHex
    @State private var isShowingBackgroundPicker = false
    @State private var isShowingMusicFilePicker = false
    @State private var backgroundPickerLongPressDidClear = false
    @State private var backgroundPickerHaptics = UINotificationFeedbackGenerator()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            await library.scan(using: modelContext)
                        }
                    } label: {
                        Label {
                            Text(LocalizedStringKey(library.isScanning ? "Scanning..." : "Scan"))
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(library.isScanning)
                }

                Section("Music Library") {
                    Button {
                        isShowingMusicFilePicker = true
                    } label: {
                        Label("Add Music Files", systemImage: "plus")
                    }
                    .disabled(library.isScanning)

                    LabeledContent("Total Songs", value: "\(library.totalSongs)")
                    LabeledContent("Documents Size", value: library.documentsSizeBytes.formattedByteCount)
                }

                Section("Supporter") {
                    Toggle("Unlock Customization", isOn: customizationUnlockBinding)
                        .disabled(customizationPurchaseController.isPurchasing)

                    Button {
                        Task {
                            if await customizationPurchaseController.restorePurchases() {
                                isCustomizationUnlocked = true
                            }
                        }
                    } label: {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                    }
                    .disabled(customizationPurchaseController.isPurchasing)

                    if customizationPurchaseController.isPurchasing {
                        HStack {
                            ProgressView()
                            Text("Purchasing...")
                        }
                    }

                    if !customizationPurchaseController.purchaseErrorMessage.isEmpty {
                        Text(customizationPurchaseController.purchaseErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if isCustomizationUnlocked {
                    Section("Appearance") {
                        Toggle("Dark Mode", isOn: $usesDarkMode)

                        ColorPicker("Accent Color", selection: accentColorBinding, supportsOpacity: false)

                        Button {
                            if backgroundPickerLongPressDidClear {
                                backgroundPickerLongPressDidClear = false
                                return
                            }

                            isShowingBackgroundPicker = true
                        } label: {
                            Label("Choose Background Image", systemImage: "photo")
                        }
                        .foregroundStyle(.primary)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: AppStyle.longPressDuration)
                                .onEnded { _ in
                                    backgroundPickerLongPressDidClear = true
                                    backgroundImageData = Data()
                                    backgroundPickerHaptics.notificationOccurred(.success)
                                    backgroundPickerHaptics.prepare()

                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(500))
                                        backgroundPickerLongPressDidClear = false
                                    }
                                }
                        )
                    }
                }
            }
            .navigationTitle("Management")
            .sheet(isPresented: $isShowingBackgroundPicker) {
                SingleImagePicker { imageData in
                    backgroundImageData = imageData
                }
            }
            .fileImporter(
                isPresented: $isShowingMusicFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }

                Task {
                    await library.importMusicFiles(from: urls, using: modelContext)
                }
            }
            .onAppear {
                backgroundPickerHaptics.prepare()
            }
        }
    }

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: accentColorHex) },
            set: { accentColorHex = $0.hexString() ?? defaultAccentColorHex }
        )
    }

    private var customizationUnlockBinding: Binding<Bool> {
        Binding(
            get: { isCustomizationUnlocked },
            set: { newValue in
                if !newValue {
                    isCustomizationUnlocked = false
                    return
                }

                Task {
                    if await customizationPurchaseController.enableCustomizationIfPossible() {
                        isCustomizationUnlocked = true
                    } else {
                        isCustomizationUnlocked = false
                    }
                }
            }
        )
    }
}

private struct SingleImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImagePicked: (Data) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .compatible

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            dismiss: dismiss,
            onImagePicked: onImagePicked
        )
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let dismiss: DismissAction
        let onImagePicked: (Data) -> Void

        init(dismiss: DismissAction, onImagePicked: @escaping (Data) -> Void) {
            self.dismiss = dismiss
            self.onImagePicked = onImagePicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            dismiss()

            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self)
            else {
                return
            }

            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.85)
                else {
                    return
                }

                Task { @MainActor in
                    self.onImagePicked(data)
                }
            }
        }
    }
}

private extension Int64 {
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

private extension Color {
    init(hex: String) {
        let cleanedHex = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard cleanedHex.count == 6,
              let value = Int(cleanedHex, radix: 16)
        else {
            self = .blue
            return
        }

        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self = Color(red: red, green: green, blue: blue)
    }

    func hexString() -> String? {
        let color = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: MusicTrack.self, inMemory: true)
}
