//
//  MusicLibraryController.swift
//  Music Player
//
//  Created by Chen on 2026-05-05.
//

import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftData
import UIKit

enum PlaybackIntent: Equatable {
    case play
    case pause
}

@MainActor
final class MusicLibraryController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var currentTrack: MusicTrack?
    @Published var isPlaying = false
    @Published var playbackIntent: PlaybackIntent = .pause
    @Published var isScanning = false
    @Published var totalSongs = 0
    @Published var documentsSizeBytes: Int64 = 0
    @Published var statusMessage = ""
    @Published var temporaryPlaylist: [MusicTrack] = []
    @Published var currentPlaylistIndex: Int?
    @Published var playlistRevision = 0
    @Published var isSingleSongLoopEnabled = false
    @Published var isPlaybackTransitioning = false
    @Published var playbackTransitionRevision = 0

    private var audioPlayer: AVAudioPlayer?
    private var audioPlayerTrackPath: String?
    private var hasConfiguredRemoteCommands = false
    private var pendingPlaybackRequest: MusicTrack?
    private var playbackTransitionTask: Task<Void, Never>?
    private(set) var didCopyBundledSampleMusic = false
    private let persistedStateKey = "temporaryPlaylistState"
    private let bundledSampleMusicVersionKey = "bundledSampleMusicVersion"
    private let bundledSampleMusicVersion = 2

    private let supportedAudioExtensions: Set<String> = [
        "aac", "aif", "aiff", "caf", "flac", "m4a", "mp3", "wav"
    ]

    nonisolated var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    nonisolated var musicDirectory: URL {
        documentsDirectory.appendingPathComponent("music", isDirectory: true)
    }

    nonisolated func albumArtwork(for track: MusicTrack) async -> UIImage? {
        let url = musicDirectory.appendingPathComponent(track.relativePath)

        if let artworkData = TaglibWrapper.getAlbumArtwork(url.path) as Data?,
           let image = UIImage(data: artworkData) {
            return image
        }

        return await avFoundationAlbumArtwork(from: url)
    }

    func prepareStorage() {
        do {
            try FileManager.default.createDirectory(
                at: musicDirectory,
                withIntermediateDirectories: true
            )
            didCopyBundledSampleMusic = try copyBundledSampleMusicIfNeeded()
            configureAudioSession()
            configureRemoteCommandsIfNeeded()
            refreshDocumentSize()
        } catch {
            statusMessage = "Could not create music folder: \(error.localizedDescription)"
        }
    }

    func refreshStats(using modelContext: ModelContext) {
        let tracks = (try? modelContext.fetch(FetchDescriptor<MusicTrack>())) ?? []
        totalSongs = tracks.count
        refreshDocumentSize()
        restoreTemporaryPlaylistIfNeeded(from: tracks)
    }

    func scan(using modelContext: ModelContext) async {
        prepareStorage()
        isScanning = true
        statusMessage = "Scanning..."

        let foundTracks = await scanMusicFolder()
        let existingTracks = (try? modelContext.fetch(FetchDescriptor<MusicTrack>())) ?? []
        existingTracks.forEach { modelContext.delete($0) }
        foundTracks.forEach { modelContext.insert($0) }

        do {
            try modelContext.save()
            totalSongs = foundTracks.count
            refreshDocumentSize()
            statusMessage = foundTracks.isEmpty ? "No music found." : "Scan complete."
            restoreTemporaryPlaylistIfNeeded(from: foundTracks)
        } catch {
            statusMessage = "Could not save scan results: \(error.localizedDescription)"
        }

        isScanning = false
    }

    func importMusicFiles(from urls: [URL], using modelContext: ModelContext) async {
        guard !urls.isEmpty else { return }

        prepareStorage()
        isScanning = true
        statusMessage = "Adding music..."

        var copiedCount = 0

        for sourceURL in urls {
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            guard supportedAudioExtensions.contains(sourceURL.pathExtension.lowercased()) else {
                continue
            }

            do {
                let destinationURL = uniqueMusicDestinationURL(for: sourceURL.lastPathComponent)
                if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    copiedCount += 1
                }
            } catch {
                statusMessage = "Could not add \(sourceURL.lastPathComponent): \(error.localizedDescription)"
            }
        }

        isScanning = false

        if copiedCount > 0 {
            await scan(using: modelContext)
        } else {
            refreshDocumentSize()
            statusMessage = "No supported music files added."
        }
    }

    func play(_ track: MusicTrack) {
        playbackIntent = .play
        moveTrackToEndOfTemporaryPlaylist(track)
        requestPlayback(of: track)
    }

    func playFromTemporaryPlaylist(at index: Int) {
        guard temporaryPlaylist.indices.contains(index) else { return }

        let track = temporaryPlaylist[index]
        currentPlaylistIndex = index

        requestPlayback(of: track)
    }

    func settlePlaylistSelection(at index: Int) {
        guard temporaryPlaylist.indices.contains(index) else { return }

        let selectedTrack = temporaryPlaylist[index]
        currentPlaylistIndex = index

        guard currentTrack?.relativePath != selectedTrack.relativePath else { return }

        requestPlayback(of: selectedTrack)
    }

    func shuffleTemporaryPlaylistKeepingCurrentSongCentered() {
        guard temporaryPlaylist.count > 1 else { return }

        let currentRelativePath = currentTrack?.relativePath
        temporaryPlaylist.shuffle()

        if let currentRelativePath,
           let newIndex = temporaryPlaylist.firstIndex(where: { $0.relativePath == currentRelativePath }) {
            let currentTrack = temporaryPlaylist.remove(at: newIndex)
            temporaryPlaylist.insert(currentTrack, at: 0)
            currentPlaylistIndex = 0
        } else if !temporaryPlaylist.isEmpty {
            currentPlaylistIndex = temporaryPlaylist.indices.first
        }

        playlistRevision += 1
    }

    func removeAllTemporaryPlaylistItemsExceptCurrent() {
        guard let currentRelativePath = currentTrack?.relativePath else { return }
        guard temporaryPlaylist.contains(where: { $0.relativePath == currentRelativePath }) else { return }

        temporaryPlaylist.removeAll { $0.relativePath != currentRelativePath }
        currentPlaylistIndex = temporaryPlaylist.indices.first
        playlistRevision += 1
    }

    func clearTemporaryPlaylistAndCurrentSelection() {
        pendingPlaybackRequest = nil
        playbackIntent = .pause
        audioPlayer?.stop()
        audioPlayer?.volume = 1
        temporaryPlaylist.removeAll()
        currentTrack = nil
        currentPlaylistIndex = nil
        audioPlayerTrackPath = nil
        isPlaying = false
        statusMessage = "Temporary playlist cleared."
        playlistRevision += 1
        playbackTransitionRevision += 1
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func replayCurrentTrack() {
        guard isPlaying, let currentTrack else { return }

        playbackIntent = .play
        requestPlayback(of: currentTrack)
    }

    func toggleSingleSongLoop() {
        isSingleSongLoopEnabled.toggle()
    }

    func reconcilePlaybackAfterForeground() {
        guard audioPlayerTrackPath == currentTrack?.relativePath else {
            isPlaying = false
            updateNowPlayingPlaybackState()
            return
        }

        if audioPlayer?.isPlaying == true {
            isPlaying = true
        } else {
            isPlaying = false
            playbackIntent = .pause
        }

        updateNowPlayingPlaybackState()
    }

    func persistTemporaryPlaylistState() {
        let state = PersistedTemporaryPlaylistState(
            playlistRelativePaths: temporaryPlaylist.map(\.relativePath),
            currentRelativePath: currentTrack?.relativePath,
            currentPlaylistIndex: currentPlaylistIndex
        )

        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: persistedStateKey)
    }

    private func restoreTemporaryPlaylistIfNeeded(from tracks: [MusicTrack]) {
        guard temporaryPlaylist.isEmpty else { return }
        guard let data = UserDefaults.standard.data(forKey: persistedStateKey),
              let state = try? JSONDecoder().decode(PersistedTemporaryPlaylistState.self, from: data)
        else {
            return
        }

        let tracksByPath = Dictionary(uniqueKeysWithValues: tracks.map { ($0.relativePath, $0) })
        temporaryPlaylist = state.playlistRelativePaths.compactMap { tracksByPath[$0] }

        if let currentRelativePath = state.currentRelativePath,
           let restoredIndex = temporaryPlaylist.firstIndex(where: { $0.relativePath == currentRelativePath }) {
            currentTrack = temporaryPlaylist[restoredIndex]
            currentPlaylistIndex = restoredIndex
            audioPlayerTrackPath = currentRelativePath
            statusMessage = "Selected \(temporaryPlaylist[restoredIndex].displayTitle)"
        } else if let savedIndex = state.currentPlaylistIndex,
                  temporaryPlaylist.indices.contains(savedIndex) {
            currentTrack = temporaryPlaylist[savedIndex]
            currentPlaylistIndex = savedIndex
            audioPlayerTrackPath = currentTrack?.relativePath
            statusMessage = "Selected \(temporaryPlaylist[savedIndex].displayTitle)"
        } else if !temporaryPlaylist.isEmpty {
            currentTrack = temporaryPlaylist.first
            currentPlaylistIndex = temporaryPlaylist.indices.first
            audioPlayerTrackPath = currentTrack?.relativePath
        }

        playbackIntent = .pause
        isPlaying = false
        playlistRevision += 1
    }

    private struct PersistedTemporaryPlaylistState: Codable {
        var playlistRelativePaths: [String]
        var currentRelativePath: String?
        var currentPlaylistIndex: Int?
    }

    private func uniqueMusicDestinationURL(for fileName: String) -> URL {
        let originalURL = musicDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            return originalURL
        }

        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let fileExtension = originalURL.pathExtension

        for suffix in 2...999 {
            let candidateName = fileExtension.isEmpty
                ? "\(baseName) \(suffix)"
                : "\(baseName) \(suffix).\(fileExtension)"
            let candidateURL = musicDirectory.appendingPathComponent(candidateName)

            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return musicDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
    }

    private func copyBundledSampleMusicIfNeeded() throws -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: bundledSampleMusicVersionKey) < bundledSampleMusicVersion else {
            return false
        }

        guard let bundledSamplesURL = Bundle.main.resourceURL?.appendingPathComponent(
            "SampleMusic",
            isDirectory: true
        ),
              FileManager.default.fileExists(atPath: bundledSamplesURL.path)
        else {
            return false
        }

        let destinationRoot = musicDirectory.appendingPathComponent("Samples", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        removeMalformedSampleMusicFolders(from: destinationRoot)

        guard let relativePaths = FileManager.default.enumerator(atPath: bundledSamplesURL.path) else {
            return false
        }

        var didCopySamples = false

        for case let relativePath as String in relativePaths {
            let sourceURL = bundledSamplesURL.appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                continue
            }

            let destinationURL = destinationRoot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                didCopySamples = true
            }
        }

        defaults.set(bundledSampleMusicVersion, forKey: bundledSampleMusicVersionKey)
        return didCopySamples
    }

    private func removeMalformedSampleMusicFolders(from destinationRoot: URL) {
        ["Users", "private", "var", "Applications"].forEach { folderName in
            let malformedURL = destinationRoot.appendingPathComponent(folderName, isDirectory: true)
            if FileManager.default.fileExists(atPath: malformedURL.path) {
                try? FileManager.default.removeItem(at: malformedURL)
            }
        }
    }

    func shuffleAll(tracks: [MusicTrack]) {
        guard !tracks.isEmpty else { return }

        playbackIntent = .play
        temporaryPlaylist = tracks.shuffled()
        currentPlaylistIndex = temporaryPlaylist.indices.first
        playlistRevision += 1

        if let firstTrack = temporaryPlaylist.first {
            requestPlayback(of: firstTrack)
        }
    }

    func addTracksAfterCurrentInTemporaryPlaylist(_ tracks: [MusicTrack]) {
        guard !tracks.isEmpty else { return }

        let currentRelativePath = currentTrack?.relativePath ?? currentPlaylistTrack?.relativePath
        let uniqueTracks = tracks.reduce(into: [MusicTrack]()) { result, track in
            guard !result.contains(where: { $0.relativePath == track.relativePath }) else { return }
            guard track.relativePath != currentRelativePath else { return }

            result.append(track)
        }

        guard !uniqueTracks.isEmpty else { return }

        let incomingRelativePaths = Set(uniqueTracks.map(\.relativePath))
        temporaryPlaylist.removeAll { incomingRelativePaths.contains($0.relativePath) }

        let insertionIndex: Int
        if let currentRelativePath,
           let currentIndex = temporaryPlaylist.firstIndex(where: { $0.relativePath == currentRelativePath }) {
            insertionIndex = temporaryPlaylist.index(after: currentIndex)
        } else if let currentPlaylistIndex,
                  temporaryPlaylist.indices.contains(currentPlaylistIndex) {
            insertionIndex = temporaryPlaylist.index(after: currentPlaylistIndex)
        } else {
            insertionIndex = temporaryPlaylist.endIndex
        }

        temporaryPlaylist.insert(contentsOf: uniqueTracks, at: insertionIndex)

        if let currentRelativePath {
            currentPlaylistIndex = temporaryPlaylist.firstIndex { $0.relativePath == currentRelativePath }
        }

        playlistRevision += 1
    }

    func togglePlayPause() {
        if playbackIntent == .play {
            playbackIntent = .pause
            requestPlayback(of: nil)
        } else {
            playbackIntent = .play

            if let audioPlayer,
               audioPlayerTrackPath == currentTrack?.relativePath,
               !isPlaybackTransitioning {
                audioPlayer.play()
                isPlaying = true
                updateNowPlayingPlaybackState()
            } else if let currentTrack {
                requestPlayback(of: currentTrack)
            } else if let currentPlaylistIndex {
                playFromTemporaryPlaylist(at: currentPlaylistIndex)
            } else if !temporaryPlaylist.isEmpty {
                playFromTemporaryPlaylist(at: 0)
            }
        }
    }

    func requestPlayback(of track: MusicTrack?) {
        pendingPlaybackRequest = track

        guard playbackTransitionTask == nil else { return }

        isPlaybackTransitioning = true

        playbackTransitionTask = Task { @MainActor in
            await fadeOutForPlaybackTransition()
            guard !Task.isCancelled else { return }

            let requestedTrack = pendingPlaybackRequest
            pendingPlaybackRequest = nil
            playbackTransitionTask = nil
            isPlaybackTransitioning = false

            guard let requestedTrack else {
                stopPlaybackAfterTransition()
                return
            }

            if playbackIntent == .play {
                startPlayback(of: requestedTrack)
            } else {
                selectTrackAfterTransition(requestedTrack)
            }
        }
    }

    private func moveTrackToEndOfTemporaryPlaylist(_ track: MusicTrack) {
        temporaryPlaylist.removeAll { $0.relativePath == track.relativePath }
        temporaryPlaylist.append(track)
        currentPlaylistIndex = temporaryPlaylist.indices.last
        playlistRevision += 1
    }

    private var currentPlaylistTrack: MusicTrack? {
        guard let currentPlaylistIndex,
              temporaryPlaylist.indices.contains(currentPlaylistIndex)
        else {
            return nil
        }

        return temporaryPlaylist[currentPlaylistIndex]
    }

    private func startPlayback(of track: MusicTrack) {
        let url = musicDirectory.appendingPathComponent(track.relativePath)

        do {
            configureAudioSession()
            configureRemoteCommandsIfNeeded()
            ensureTrackIsInTemporaryPlaylist(track)

            if audioPlayer?.isPlaying == true {
                audioPlayer?.stop()
            }

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            currentTrack = track
            audioPlayerTrackPath = track.relativePath
            isPlaying = true
            statusMessage = "Playing \(track.displayTitle)"
            currentPlaylistIndex = temporaryPlaylist.firstIndex { $0.relativePath == track.relativePath }
            playbackTransitionRevision += 1
            updateNowPlayingInfo(for: track)
        } catch {
            isPlaying = false
            updateNowPlayingPlaybackState()
            statusMessage = "Could not play \(track.fileName): \(error.localizedDescription)"
        }
    }

    private func ensureTrackIsInTemporaryPlaylist(_ track: MusicTrack) {
        if let index = temporaryPlaylist.firstIndex(where: { $0.relativePath == track.relativePath }) {
            currentPlaylistIndex = index
            return
        }

        temporaryPlaylist.append(track)
        currentPlaylistIndex = temporaryPlaylist.indices.last
        playlistRevision += 1
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            statusMessage = "Could not configure background audio: \(error.localizedDescription)"
        }
    }

    private func configureRemoteCommandsIfNeeded() {
        guard !hasConfiguredRemoteCommands else { return }
        hasConfiguredRemoteCommands = true

        UIApplication.shared.beginReceivingRemoteControlEvents()

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }

            Task { @MainActor in
                if self.playbackIntent == .pause {
                    self.togglePlayPause()
                }
            }

            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }

            Task { @MainActor in
                if self.playbackIntent == .play {
                    self.togglePlayPause()
                }
            }

            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }

            Task { @MainActor in
                self.togglePlayPause()
            }

            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }

            Task { @MainActor in
                self.playNextTemporaryPlaylistTrack()
            }

            return .success
        }
    }

    private func fadeOutForPlaybackTransition() async {
        guard let audioPlayer, audioPlayer.isPlaying else {
            try? await Task.sleep(for: .milliseconds(200))
            return
        }

        let startingVolume = audioPlayer.volume
        let steps = 8

        for step in 1...steps {
            try? await Task.sleep(for: .milliseconds(25))
            let progress = Float(step) / Float(steps)
            audioPlayer.volume = max(0, startingVolume * (1 - progress))
        }
    }

    private func stopPlaybackAfterTransition() {
        audioPlayer?.stop()
        audioPlayer?.volume = 1
        isPlaying = false
        playbackTransitionRevision += 1
        updateNowPlayingPlaybackState()
    }

    private func selectTrackAfterTransition(_ track: MusicTrack) {
        audioPlayer?.stop()
        audioPlayer?.volume = 1
        ensureTrackIsInTemporaryPlaylist(track)
        currentTrack = track
        audioPlayerTrackPath = nil
        isPlaying = false
        statusMessage = "Selected \(track.displayTitle)"
        currentPlaylistIndex = temporaryPlaylist.firstIndex { $0.relativePath == track.relativePath }
        playbackTransitionRevision += 1
        updateNowPlayingInfo(for: track)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if isSingleSongLoopEnabled,
               playbackIntent == .play,
               let currentTrack {
                requestPlayback(of: currentTrack)
            } else if playbackIntent == .play,
                      let nextIndex = nextTemporaryPlaylistIndex() {
                playFromTemporaryPlaylist(at: nextIndex)
            } else {
                isPlaying = false
                updateNowPlayingPlaybackState()
            }
        }
    }

    private func playNextTemporaryPlaylistTrack() {
        guard let nextIndex = nextTemporaryPlaylistIndex() else { return }
        playbackIntent = .play
        playFromTemporaryPlaylist(at: nextIndex)
    }

    private func nextTemporaryPlaylistIndex() -> Int? {
        guard !temporaryPlaylist.isEmpty else { return nil }

        let activeIndex: Int?

        if let currentRelativePath = currentTrack?.relativePath {
            activeIndex = temporaryPlaylist.firstIndex { $0.relativePath == currentRelativePath }
        } else {
            activeIndex = currentPlaylistIndex
        }

        guard let activeIndex else {
            return temporaryPlaylist.indices.first
        }

        let nextIndex = temporaryPlaylist.index(after: activeIndex)
        guard temporaryPlaylist.indices.contains(nextIndex) else {
            return temporaryPlaylist.indices.first
        }

        return nextIndex
    }

    private func updateNowPlayingInfo(for track: MusicTrack) {
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: track.displayTitle,
            MPMediaItemPropertyArtist: track.displayArtist,
            MPMediaItemPropertyAlbumTitle: track.displayAlbum,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: audioPlayer?.currentTime ?? 0
        ]

        if let duration = audioPlayer?.duration {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        updateNowPlayingPlaybackState()
    }

    private func updateNowPlayingPlaybackState() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }

        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioPlayer?.currentTime ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        }
    }

    private func scanMusicFolder() async -> [MusicTrack] {
        let fileURLs = musicFileURLs()
        var tracks: [MusicTrack] = []

        for fileURL in fileURLs {
            let metadata = await readMetadata(from: fileURL)
            let fileSize = fileSize(for: fileURL)
            let relativePath = relativeMusicPath(for: fileURL)
            let directory = directoryPath(from: relativePath)
            let fileName = fileURL.lastPathComponent
            let fallbackTitle = fileURL.deletingPathExtension().lastPathComponent

            tracks.append(
                MusicTrack(
                    relativePath: relativePath,
                    fileName: fileName,
                    directory: directory,
                    title: metadata.title.isEmpty ? fallbackTitle : metadata.title,
                    artist: metadata.artist,
                    albumArtist: metadata.albumArtist,
                    album: metadata.album,
                    genre: metadata.genre,
                    fileSize: fileSize
                )
            )
        }

        return tracks.sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }

    private func musicFileURLs() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: musicDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var fileURLs: [URL] = []

        for case let fileURL as URL in enumerator {
            guard isSupportedAudioFile(fileURL) else { continue }
            fileURLs.append(fileURL)
        }

        return fileURLs
    }

    private func isSupportedAudioFile(_ url: URL) -> Bool {
        supportedAudioExtensions.contains(url.pathExtension.lowercased())
    }

    private func relativeMusicPath(for url: URL) -> String {
        let musicPath = musicDirectory.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path

        guard filePath.hasPrefix(musicPath) else {
            return url.lastPathComponent
        }

        return String(filePath.dropFirst(musicPath.count + 1))
    }

    private func directoryPath(from relativePath: String) -> String {
        let directory = (relativePath as NSString).deletingLastPathComponent
        return directory == "." ? "" : directory
    }

    private func fileSize(for url: URL) -> Int64 {
        guard
            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let fileSize = resourceValues.fileSize
        else {
            return 0
        }

        return Int64(fileSize)
    }

    private func refreshDocumentSize() {
        documentsSizeBytes = folderSize(at: documentsDirectory)
    }

    private func folderSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                resourceValues.isRegularFile == true
            else {
                continue
            }

            total += Int64(resourceValues.fileSize ?? 0)
        }

        return total
    }

    private func readMetadata(from url: URL) async -> TrackMetadata {
        let tagLibMetadata = readTagLibMetadata(from: url)
        guard !tagLibMetadata.hasUsefulMetadata else {
            return tagLibMetadata
        }

        let asset = AVURLAsset(url: url)
        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        let metadata = (try? await asset.load(.metadata)) ?? []

        return TrackMetadata(
            title: tagLibMetadata.title.orFallback(await commonMetadata.string(for: .commonIdentifierTitle)),
            artist: tagLibMetadata.artist.orFallback(await commonMetadata.string(for: .commonIdentifierArtist)),
            albumArtist: tagLibMetadata.albumArtist.orFallback(await metadata.string(forRawIdentifiers: ["itsk/aART", "id3/TPE2"])),
            album: tagLibMetadata.album.orFallback(await commonMetadata.string(for: .commonIdentifierAlbumName)),
            genre: tagLibMetadata.genre.orFallback(await commonMetadata.string(for: .commonIdentifierType))
        )
    }

    private func readTagLibMetadata(from url: URL) -> TrackMetadata {
        guard let dictionary = TaglibWrapper.getMetadata(url.path) as? [String: Any] else {
            return .empty
        }

        return TrackMetadata(
            title: dictionary.metadataString(for: ["TITLE"]),
            artist: dictionary.metadataString(for: ["ARTIST"]),
            albumArtist: dictionary.metadataString(for: ["ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST", "BAND"]),
            album: dictionary.metadataString(for: ["ALBUM"]),
            genre: dictionary.metadataString(for: ["GENRE"])
        )
    }

    nonisolated private func avFoundationAlbumArtwork(from url: URL) async -> UIImage? {
        let metadata = (try? await AVURLAsset(url: url).load(.commonMetadata)) ?? []

        for item in metadata where item.commonKey?.rawValue == "artwork" {
            if let data = try? await item.load(.dataValue),
               let image = UIImage(data: data) {
                return image
            }
        }

        return nil
    }
}

private struct TrackMetadata {
    var title: String
    var artist: String
    var albumArtist: String
    var album: String
    var genre: String

    static let empty = TrackMetadata(
        title: "",
        artist: "",
        albumArtist: "",
        album: "",
        genre: ""
    )

    var hasUsefulMetadata: Bool {
        !title.isEmpty ||
        !artist.isEmpty ||
        !albumArtist.isEmpty ||
        !album.isEmpty ||
        !genre.isEmpty
    }
}

private extension Array where Element == AVMetadataItem {
    func string(for identifier: AVMetadataIdentifier) async -> String {
        guard let item = AVMetadataItem.metadataItems(from: self, filteredByIdentifier: identifier).first else {
            return ""
        }

        return ((try? await item.load(.stringValue)) ?? "")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func string(forRawIdentifiers identifiers: [String]) async -> String {
        for identifier in identifiers {
            let value = await string(for: AVMetadataIdentifier(rawValue: identifier))
            if !value.isEmpty {
                return value
            }
        }

        return ""
    }
}

private extension Dictionary where Key == String, Value == Any {
    func metadataString(for keys: [String]) -> String {
        for key in keys {
            if let value = self[key] as? String {
                let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedValue.isEmpty {
                    return trimmedValue
                }
            }
        }

        return ""
    }
}

private extension String {
    func orFallback(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
