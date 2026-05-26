import SwiftData
import SwiftUI

struct MacNowPlayingView: View {
    @ObservedObject var library: MusicLibraryController
    var onMetadataSearchRequest: (SearchNavigationRequest) -> Void = { _ in }
    @Query(sort: \MusicTrack.titleSortKey, order: .forward) private var libraryTracks: [MusicTrack]
    @AppStorage(accentColorStorageKey) private var accentColorHex = defaultAccentColorHex
    @AppStorage("nowPlayingShowsAlbumArtist") private var showsAlbumArtist = false
    @State private var displayedFileProperties = AudioFileProperties.empty

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let track = library.currentTrack
            let shouldSeedRandomAlbums = library.temporaryPlaylist.count <= 2
            let canSeedRandomAlbums = shouldSeedRandomAlbums && libraryTracks.contains { library.isTrackUsable($0) }
            let controlSize = max(min(size.height * 0.075, 56), 38)
            let wideWidth = size.width * 2 / 3
            let artDimension = max(min(wideWidth * 0.90, size.height * 0.58), 220)

            HStack(spacing: 0) {
                VStack(spacing: 14) {
                    MacVolumeBitDepthControl(
                        library: library,
                        fileBitDepth: displayedFileProperties.bitDepth
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    NowPlayingMetadataView(
                        library: library,
                        track: track,
                        artistFontSize: max(wideWidth * 0.04, 18),
                        albumFontSize: max(wideWidth * 0.046, 22),
                        isPlaying: library.isPlaying,
                        onMetadataSearchRequest: onMetadataSearchRequest
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 118)

                    AlbumArtView(
                        library: library,
                        track: track,
                        supportsTerminalBackface: artDimension > 300,
                        fileNameFontSize: artDimension / 24,
                        filePropertiesFontSize: artDimension / 30
                    )
                    .frame(width: artDimension, height: artDimension)

                    controlBar(
                        shouldSeedRandomAlbums: shouldSeedRandomAlbums,
                        canSeedRandomAlbums: canSeedRandomAlbums,
                        controlSize: controlSize
                    )
                }
                .padding(28)
                .frame(width: size.width * 2 / 3)
                .frame(maxHeight: .infinity)

                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 0.5)

                temporaryPlaylistList
                    .frame(width: size.width / 3)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .task(id: track?.relativePath) {
                guard let track else {
                    displayedFileProperties = .empty
                    return
                }

                let relativePath = track.relativePath
                let media = await library.loadTrackMedia(for: track)

                guard library.currentTrack?.relativePath == relativePath else { return }
                displayedFileProperties = media.properties
            }
        }
    }

    private var temporaryPlaylistList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Now Playing")
                    .font(.headline)
                Spacer()
                Button {
                    library.clearTemporaryPlaylistAndCurrentSelection()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(library.temporaryPlaylist.isEmpty)
                .help("Clear Playlist")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            List(Array(library.temporaryPlaylist.enumerated()), id: \.element.relativePath) { index, track in
                Button {
                    library.playFromTemporaryPlaylist(at: index)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.displayTitle)
                                .font(.headline)
                                .lineLimit(1)
                            Text(track.displayArtist(showsAlbumArtist: showsAlbumArtist))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if track.relativePath == library.currentTrack?.relativePath {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(Color(hex: accentColorHex))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
            .overlay {
                if library.temporaryPlaylist.isEmpty {
                    ContentUnavailableView("Nothing Playing", systemImage: "music.note")
                }
            }
        }
    }

    private func controlBar(shouldSeedRandomAlbums: Bool, canSeedRandomAlbums: Bool, controlSize: CGFloat) -> some View {
        HStack(spacing: 28) {
            Button {
                if shouldSeedRandomAlbums {
                    library.addRandomAlbumsToTemporaryPlaylist(from: libraryTracks)
                } else {
                    library.shuffleTemporaryPlaylistKeepingCurrentSongCentered()
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: controlSize * 0.48, weight: .medium))
                    .frame(width: controlSize, height: controlSize)
            }
            .buttonStyle(.borderless)
            .disabled(shouldSeedRandomAlbums && !canSeedRandomAlbums)

            Button {
                if library.isWheelDesynced {
                    library.requestWheelReset()
                } else {
                    library.togglePlayPause()
                }
            } label: {
                Image(systemName: playPauseIconName)
                    .font(.system(size: controlSize * 0.62, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: controlSize * 1.2, height: controlSize * 1.2)
            }
            .buttonStyle(.borderless)
            .disabled(library.currentTrack == nil && library.temporaryPlaylist.isEmpty)

            Button {
                library.replayCurrentTrack()
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: controlSize * 0.48, weight: .medium))
                    .frame(width: controlSize, height: controlSize)
            }
            .buttonStyle(.borderless)
            .disabled(!library.isPlaying)
        }
        .foregroundStyle(.primary)
    }

    private var playPauseIconName: String {
        library.isWheelDesynced ? "memories" : (library.playbackIntent == .play ? "pause.fill" : "play.fill")
    }
}

private struct MacVolumeBitDepthControl: View {
    @ObservedObject var library: MusicLibraryController
    let fileBitDepth: Int?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { library.playbackVolume },
                    set: { library.setPlaybackVolume($0) }
                ),
                in: 0...1
            )
            .frame(width: 150)

            Text(bitDepthReadout)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .trailing)
        }
        .onAppear {
            library.refreshAudioOutputInfo()
        }
        .help(bitDepthHelpText)
    }

    private var bitDepthReadout: String {
        guard let fileBitDepth,
              let outputBitDepth = library.audioOutput.bitDepth
        else {
            return "-- bits"
        }

        guard library.playbackVolume > 0 else {
            return "0.0 bits"
        }

        let attenuationBits = log2(1 / library.playbackVolume)
        let outputHeadroomBits = Double(outputBitDepth - fileBitDepth)
        let lostBits = max(0, attenuationBits - outputHeadroomBits)
        let effectiveBits = max(0, Double(fileBitDepth) - lostBits)
        return String(format: "%.1f bits", effectiveBits)
    }

    private var bitDepthHelpText: String {
        guard let fileBitDepth,
              let outputBitDepth = library.audioOutput.bitDepth
        else {
            return "Theoretical effective bit depth. Track or output bit depth is unknown."
        }

        return "Theoretical effective bit depth. Track: \(fileBitDepth)-bit, output: \(outputBitDepth)-bit."
    }
}
