import SwiftUI
import AppKit

struct PreferencesView: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @EnvironmentObject var updater: UpdateChecker

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .environmentObject(prefs)
                .environmentObject(updater)
            OutputTab()
                .tabItem { Label("Output", systemImage: "folder") }
                .environmentObject(prefs)
        }
        .frame(width: 460, height: 360)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @EnvironmentObject var updater: UpdateChecker

    var body: some View {
        Form {
            Section {
                Toggle("Smart quality", isOn: Binding(
                    get: { prefs.smartQuality },
                    set: { prefs.smartQuality = $0 }
                ))
                Text("Detects photos vs. screenshots and adjusts quality so text stays crisp and photos squeeze harder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Skip already-optimized files", isOn: Binding(
                    get: { prefs.skipAlreadyOptimized },
                    set: { prefs.skipAlreadyOptimized = $0 }
                ))
                Text("Skips files where savings would be less than 2%.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Preserve original timestamps", isOn: Binding(
                    get: { prefs.preserveTimestamps },
                    set: { prefs.preserveTimestamps = $0 }
                ))
            } header: {
                Text("Compression")
            }

            Section {
                Toggle("Play sound when done", isOn: Binding(
                    get: { prefs.playSoundEffects },
                    set: { prefs.playSoundEffects = $0 }
                ))
            } header: {
                Text("Notifications")
            }

            Section {
                Toggle("Reduce motion", isOn: Binding(
                    get: { prefs.reduceMotion },
                    set: { prefs.reduceMotion = $0 }
                ))
                Text("Replaces the drop zone animation with a still arrangement of cards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Accessibility")
            }

            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { prefs.checkForUpdatesOnLaunch },
                    set: { prefs.checkForUpdatesOnLaunch = $0 }
                ))
                Text("Dinky will quietly check GitHub for a new release when you launch the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

// MARK: - Output

private struct OutputTab: View {
    @EnvironmentObject var prefs: DinkyPreferences

    var body: some View {
        Form {
            Section {
                Picker("Save to", selection: Binding(
                    get: { prefs.saveLocation },
                    set: { prefs.saveLocation = $0 }
                )) {
                    Text("Same folder as original").tag(SaveLocation.sameFolder)
                    Text("Downloads folder").tag(SaveLocation.downloads)
                    Text("Custom folder…").tag(SaveLocation.custom)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if prefs.saveLocation == .custom {
                    HStack {
                        Text(prefs.customFolderDisplayPath.isEmpty
                             ? "No folder selected" : prefs.customFolderDisplayPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { pickCustomFolder() }
                            .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("Save Location")
            }

            Section {
                Picker("Filename", selection: Binding(
                    get: { prefs.filenameHandling },
                    set: { prefs.filenameHandling = $0 }
                )) {
                    Text("Append \"-dinky\" suffix").tag(FilenameHandling.appendSuffix)
                    Text("Replace original").tag(FilenameHandling.replaceOrigin)
                    Text("Custom suffix").tag(FilenameHandling.customSuffix)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if prefs.filenameHandling == .customSuffix {
                    HStack {
                        Text("Suffix")
                            .foregroundStyle(.secondary)
                        TextField("-dinky", text: Binding(
                            get: { prefs.customSuffix },
                            set: { prefs.customSuffix = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    }
                }
            } header: {
                Text("Filename")
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private func pickCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            prefs.customFolderDisplayPath = url.path
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                prefs.customFolderBookmark = bookmark
            }
            prefs.saveLocation = .custom
        }
    }
}
