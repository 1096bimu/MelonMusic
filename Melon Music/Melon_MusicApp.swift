//
//  Melon_MusicApp.swift
//  Melon Music
//
//  Created by Chen on 2026-05-25.
//

import SwiftData
import SwiftUI

@main
struct Melon_MusicApp: App {
    @StateObject private var library = MusicLibraryController()
    @StateObject private var customizationPurchaseController = CustomizationPurchaseController()

    init() {
        UserDefaults.standard.register(defaults: [
            "nowPlayingShowsAlbumArtist": false,
            "isAlbumSortingModeDisabled": false,
            "isGenreSortingModeDisabled": false,
            "sortHanziByPinyin": false,
            "sortKanaByRomaji": true,
            "isStacksViewDisabled": false,
            "usesAlternatePlayingTab": false,
            "isCustomizationUnlocked": true,
            "showsOnboardingLabels": false,
            "repeatControlMode": RepeatControlMode.restart.rawValue,
            "displayLanguageCode": "system"
        ])
        AccentComplementLineTexture.ensureStoredTexture()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                library: library,
                customizationPurchaseController: customizationPurchaseController
            )
        }
        .modelContainer(for: [MusicTrack.self, PlaylistStack.self, ExternalRootBookmark.self])

        Settings {
            MacSettingsView(
                library: library,
                customizationPurchaseController: customizationPurchaseController
            )
        }
        .modelContainer(for: [MusicTrack.self, PlaylistStack.self, ExternalRootBookmark.self])
    }
}
