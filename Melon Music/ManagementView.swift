import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MacSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var library: MusicLibraryController
    @ObservedObject var customizationPurchaseController: CustomizationPurchaseController
    @AppStorage("usesDarkMode") private var usesDarkMode = false
    @AppStorage(accentColorStorageKey) private var accentColorHex = defaultAccentColorHex
    @AppStorage("nowPlayingShowsAlbumArtist") private var showsAlbumArtist = false
    @AppStorage("sortHanziByPinyin") private var sortHanziByPinyin = false
    @AppStorage("sortKanaByRomaji") private var sortKanaByRomaji = true
    @AppStorage("displayLanguageCode") private var displayLanguageCode = "system"
    @State private var accentColor = Color(hex: defaultAccentColorHex)
    @State private var isAddingFolder = false

    var body: some View {
        Form {
            Section("Music Library") {
                Button {
                    Task {
                        library.usesInternalLibraryRoot = false
                        await library.scan(using: modelContext)
                    }
                } label: {
                    Label(library.isScanning ? "Scanning..." : "Scan", systemImage: "arrow.clockwise")
                }

                Button {
                    isAddingFolder = true
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }

                LabeledContent("Total Songs", value: "\(library.totalSongs)")
            }

            Section("Folders") {
                if library.externalRootBookmarks.isEmpty {
                    Text("No folders added.")
                        .foregroundStyle(.secondary)
                }

                ForEach(library.externalRootBookmarks) { root in
                    HStack(spacing: 10) {
                        Toggle(
                            root.displayName,
                            isOn: Binding(
                                get: { !library.excludedTopLevelFolders.contains(root.displayName) },
                                set: { library.setFolder(root.displayName, isIncluded: $0) }
                            )
                        )

                        Spacer()

                        if !root.isAvailable {
                            Text("Offline")
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            library.removeExternalFolderBookmark(id: root.id, using: modelContext)
                        } label: {
                            Image(systemName: "eject")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove Folder")
                    }
                }
            }

            Section("Customization") {
                Toggle("Dark Mode", isOn: $usesDarkMode)

                ColorPicker("Accent Color", selection: $accentColor, supportsOpacity: false)
                    .onChange(of: accentColor) {
                        guard let hex = accentColor.hexString() else { return }
                        accentColorHex = hex
                        AccentComplementLineTexture.storeTexture(for: hex)
                    }
            }

            Section("Sorting Options") {
                Toggle("Prioritize Album Artist Tag", isOn: $showsAlbumArtist)
                Toggle("Sort Hanzi by Pinyin", isOn: $sortHanziByPinyin)
                Toggle("Sort Kana by Romaji", isOn: $sortKanaByRomaji)

                Picker("Display Language", selection: $displayLanguageCode) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                    Text("Simplified Chinese").tag("zh-Hans")
                    Text("Japanese").tag("ja")
                }

                Text("Language changes apply after restart.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            library.usesInternalLibraryRoot = false
            library.loadExternalBookmarks(using: modelContext)
            accentColor = Color(hex: accentColorHex)
            applyDisplayLanguage(displayLanguageCode)
        }
        .onChange(of: displayLanguageCode) {
            applyDisplayLanguage(displayLanguageCode)
        }
        .fileImporter(
            isPresented: $isAddingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first
            else {
                return
            }

            Task {
                await library.addExternalFolderBookmark(from: url, using: modelContext)
            }
        }
    }

    private func applyDisplayLanguage(_ code: String) {
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }
}
