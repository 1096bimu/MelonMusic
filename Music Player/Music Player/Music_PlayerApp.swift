//
//  Music_PlayerApp.swift
//  Music Player
//
//  Created by Chen on 2026-05-05.
//

import SwiftData
import SwiftUI

enum AppStyle {
    static var longPressDuration = 0.5
    static var tabBarAndShuffleAllBackgroundOpacity = 0.02
    static var nowPlayingControlSurfaceOpacity = 0.5
    static var nowPlayingControlGlassTintOpacity = 0.90
    static var nowPlayingControlDisabledOpacity = 0.6
    static var backgroundGradientMaxOpacity = 0.9
    static var artistMarqueeStartDelay = 1.0
    static var artistMarqueeEndDelay = 2.0
    static var artistMarqueeResetDelay = 1.0
    static var artistMarqueeScrollSpeed = 34.0
}

@main
struct Music_PlayerApp: App {
    init() {
        UserDefaults.standard.register(defaults: [
            "nowPlayingShowsAlbumArtist": false,
            "isAlbumSortingModeDisabled": false,
            "isGenreSortingModeDisabled": false,
            "isCustomizationUnlocked": false
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: MusicTrack.self)
    }
}
