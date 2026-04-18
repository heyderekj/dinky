import SwiftUI
import AppKit
import UserNotifications

// MARK: - In-window navigation (contextual links between preference tabs)

private enum OpenPreferencesRelatedTabKey: EnvironmentKey {
    static let defaultValue: (PreferencesTab) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Switch the Settings window to another tab (used for small “see also” links).
    fileprivate var openPreferencesRelatedTab: (PreferencesTab) -> Void {
        get { self[OpenPreferencesRelatedTabKey.self] }
        set { self[OpenPreferencesRelatedTabKey.self] = newValue }
    }
}

/// Small accent link, same spirit as ``SidebarView``’s “Change folder or naming…” / preset rows.
private struct PreferencesRelatedTabLink: View {
    @Environment(\.openPreferencesRelatedTab) private var openTab
    let title: String
    let tab: PreferencesTab

    var body: some View {
        Button(title) { openTab(tab) }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
    }
}

/// Tabs in the Settings window — use `openWindow(to:)` to deep-link from the main window sidebar.
enum PreferencesTab: Int, CaseIterable, Hashable {
    case general = 0
    case output = 1
    case watch = 2
    case presets = 3
    case shortcuts = 4

    static let pendingTabUserDefaultsKey = "prefs.pendingTab"

    /// Opens Settings and selects this tab (including when the window is already open).
    static func openWindow(to tab: PreferencesTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: pendingTabUserDefaultsKey)
        NotificationCenter.default.post(name: .dinkySelectPreferencesTab, object: tab.rawValue)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    fileprivate static func consumePendingSelection() -> PreferencesTab? {
        guard UserDefaults.standard.object(forKey: pendingTabUserDefaultsKey) != nil else { return nil }
        let raw = UserDefaults.standard.integer(forKey: pendingTabUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: pendingTabUserDefaultsKey)
        return PreferencesTab(rawValue: raw)
    }
}

struct PreferencesView: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @EnvironmentObject var updater: UpdateChecker
    @State private var selectedTab: PreferencesTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(PreferencesTab.general)
                .environmentObject(prefs)
                .environmentObject(updater)
            OutputTab()
                .tabItem { Label("Output", systemImage: "folder") }
                .tag(PreferencesTab.output)
                .environmentObject(prefs)
            WatchFoldersTab()
                .tabItem { Label("Watch", systemImage: "eye") }
                .tag(PreferencesTab.watch)
                .environmentObject(prefs)
            PresetsTab()
                .tabItem { Label("Presets", systemImage: "slider.horizontal.3") }
                .tag(PreferencesTab.presets)
                .environmentObject(prefs)
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(PreferencesTab.shortcuts)
        }
        .environment(\.openPreferencesRelatedTab, { selectedTab = $0 })
        .frame(width: 480, height: 520)
        .onAppear {
            if let tab = PreferencesTab.consumePendingSelection() {
                selectedTab = tab
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkySelectPreferencesTab)) { note in
            guard let raw = note.object as? Int, let tab = PreferencesTab(rawValue: raw) else { return }
            selectedTab = tab
            UserDefaults.standard.removeObject(forKey: PreferencesTab.pendingTabUserDefaultsKey)
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @EnvironmentObject var updater: UpdateChecker
    @State private var confirmResetLifetime = false

    var body: some View {
        Form {
            // 1. How the app behaves at its core
            Section {
                Toggle("Manual mode", isOn: Binding(
                    get: { prefs.manualMode },
                    set: { prefs.manualMode = $0 }
                ))
                Text("Files won't compress on drop — right-click to choose format per file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Move originals to trash after compressing", isOn: Binding(
                    get: { prefs.moveOriginalsToTrash },
                    set: { prefs.moveOriginalsToTrash = $0 }
                ))
                Text("Permanent once the trash is emptied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Behavior")
            }

            // 2. How compression works
            Section {
                Picker("Skip if savings below", selection: Binding(
                    get: { prefs.minimumSavingsPercent },
                    set: { prefs.minimumSavingsPercent = $0 }
                )) {
                    Text("Off").tag(0)
                    Text("2%").tag(2)
                    Text("5%").tag(5)
                    Text("10%").tag(10)
                }
                .pickerStyle(.segmented)
                Text("Applies to images, videos, and PDFs. Skip files where savings fall below this threshold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(S.concurrentCompressionPickerLabel, selection: Binding(
                    get: { DinkyPreferences.normalizedConcurrentTasks(prefs.concurrentTasks) },
                    set: { prefs.concurrentTasks = $0 }
                )) {
                    ForEach(DinkyPreferences.concurrentCompressionTiers, id: \.self) { limit in
                        Text(S.concurrentCompressionTierOption(limit: limit))
                            .tag(limit)
                            .accessibilityLabel(S.concurrentCompressionAccessibilityLabel(limit: limit))
                    }
                }
                .pickerStyle(.menu)
                Text(S.concurrentCompressionFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Preserve original timestamps", isOn: Binding(
                    get: { prefs.preserveTimestamps },
                    set: { prefs.preserveTimestamps = $0 }
                ))
            } header: {
                Text("Compression")
            } footer: {
                PreferencesRelatedTabLink(title: "Per-preset compression & media…", tab: .presets)
            }

            // 3. Alerts
            Section {
                Toggle("Play sound when done", isOn: Binding(
                    get: { prefs.playSoundEffects },
                    set: { prefs.playSoundEffects = $0 }
                ))
                Toggle("Notify when done", isOn: Binding(
                    get: { prefs.notifyWhenDone },
                    set: { newValue in
                        prefs.notifyWhenDone = newValue
                        if newValue { requestNotificationAuth() }
                    }
                ))
                Text("To receive notifications during Focus or Do Not Disturb, allow Dinky in System Settings → Focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notifications")
            } footer: {
                Button("Notification settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }

            Section {
                Button("Reset total saved statistics…") {
                    confirmResetLifetime = true
                }
                .disabled(prefs.lifetimeSavedBytes == 0)
                Text("Clears the running total shown in History. Session history is unchanged — clear that from the History window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Statistics")
            }

            // 4. Sidebar
            Section {
                Toggle("Use simple sidebar", isOn: Binding(
                    get: { prefs.sidebarSimpleMode },
                    set: { prefs.applySidebarSimpleMode($0) }
                ))
                Text("On by default: quick choices and plain-language summaries. Turn off to show every image, video, and PDF control in the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show Images in sidebar", isOn: Binding(
                    get: { prefs.showImagesSection },
                    set: { prefs.setScopedSidebarSection(.images, isOn: $0) }
                ))
                Toggle("Show Videos in sidebar", isOn: Binding(
                    get: { prefs.showVideosSection },
                    set: { prefs.setScopedSidebarSection(.videos, isOn: $0) }
                ))
                Toggle("Show PDFs in sidebar", isOn: Binding(
                    get: { prefs.showPDFsSection },
                    set: { prefs.setScopedSidebarSection(.pdfs, isOn: $0) }
                ))
                Text(prefs.sidebarSimpleMode
                     ? "Simple sidebar shows quick choices only. Turn on a section below for the full sidebar with that tab, or turn off simple sidebar to enable every section."
                     : "Sections you turn off stay available in Settings and in the full sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Sidebar")
            } footer: {
                PreferencesRelatedTabLink(title: "Presets & automatic folders…", tab: .presets)
            }

            // 5. Accessibility
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
                PreferencesRelatedTabLink(title: "Keyboard shortcuts…", tab: .shortcuts)
                Link(S.supportEmail, destination: URL(string: "mailto:\(S.supportEmail)")!)
            } header: {
                Text("Support")
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .confirmationDialog(
            "Reset the running total of bytes saved across all sessions?",
            isPresented: $confirmResetLifetime,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                prefs.lifetimeSavedBytes = 0
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This does not clear the per-session list in History.")
        }
    }

    private func requestNotificationAuth() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            case .denied:
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
            default:
                break
            }
        }
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
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("These are the defaults for the main window. Presets can set their own folder and filename rules.")
                        .font(.caption)
                    PreferencesRelatedTabLink(title: "Per-preset output…", tab: .presets)
                }
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

// MARK: - Presets

/// Sub-panel when **Applies to** is All (Image / Video / PDF); ignored for single-type presets.
private enum PresetMediaSettingsTab: String, CaseIterable, Identifiable {
    case image, video, pdf
    var id: String { rawValue }
}

private struct PresetsTab: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @State private var selectedID: UUID? = nil
    @State private var presetMediaSettingsTab: PresetMediaSettingsTab = .image

    private var selectedPreset: CompressionPreset? {
        prefs.savedPresets.first { $0.id == selectedID }
    }

    private func presetListSecondaryLine(_ preset: CompressionPreset) -> String {
        let scope = PresetMediaScope(rawValue: preset.presetMediaScopeRaw)?.displayName ?? PresetMediaScope.all.displayName
        let fmt = preset.autoFormat ? "Auto" : preset.format.displayName
        return "\(scope) · \(fmt)"
    }

    var body: some View {
        Form {
            presetListSection
            if let preset = selectedPreset { presetDetailSections(preset) }
        }
        .formStyle(.grouped)
        .animation(.easeInOut(duration: 0.2), value: selectedID)
        .animation(.easeInOut(duration: 0.15), value: presetMediaSettingsTab)
        .animation(.easeInOut(duration: 0.15), value: selectedPreset?.presetMediaScopeRaw)
        .onChange(of: selectedID) { _, newID in
            guard let id = newID,
                  let p = prefs.savedPresets.first(where: { $0.id == id }) else { return }
            syncMediaTabToPresetScope(PresetMediaScope(rawValue: p.presetMediaScopeRaw) ?? .all)
        }
        .onChange(of: selectedPreset?.presetMediaScopeRaw) { _, raw in
            guard let raw, let scope = PresetMediaScope(rawValue: raw) else { return }
            switch scope {
            case .all: break
            case .image: presetMediaSettingsTab = .image
            case .pdf: presetMediaSettingsTab = .pdf
            case .video: presetMediaSettingsTab = .video
            }
        }
    }

    private func syncMediaTabToPresetScope(_ scope: PresetMediaScope) {
        switch scope {
        case .all: break
        case .image: presetMediaSettingsTab = .image
        case .pdf: presetMediaSettingsTab = .pdf
        case .video: presetMediaSettingsTab = .video
        }
    }

    private func presetMediaScope(for snapshot: CompressionPreset) -> PresetMediaScope {
        let live = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
        return PresetMediaScope(rawValue: live.presetMediaScopeRaw) ?? .all
    }

    private func effectiveMediaTab(for snapshot: CompressionPreset) -> PresetMediaSettingsTab {
        switch presetMediaScope(for: snapshot) {
        case .all: return presetMediaSettingsTab
        case .image: return .image
        case .pdf: return .pdf
        case .video: return .video
        }
    }

    private var presetListSection: some View {
        Section {
            if prefs.savedPresets.isEmpty {
                Text("No presets yet. Click Add to create one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                ForEach(prefs.savedPresets) { preset in
                    Button {
                        withAnimation { selectedID = (selectedID == preset.id) ? nil : preset.id }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).foregroundStyle(.primary)
                                Text(presetListSecondaryLine(preset))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedID == preset.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 12) {
                Button { addPreset() } label: { Label("Add", systemImage: "plus") }
                if selectedID != nil {
                    Button(role: .destructive) { deleteSelected() } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                Spacer()
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Presets")
        }
    }

    @ViewBuilder
    private func presetDetailSections(_ snapshot: CompressionPreset) -> some View {
        Section("Name") {
            TextField("Preset name", text: binding(\.name, snapshot: snapshot))
        }
        Section("Compression") {
            let liveForQuality = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
            Toggle("Smart quality", isOn: binding(\.smartQuality, snapshot: snapshot))
            if !liveForQuality.smartQuality {
                if presetMediaScope(for: snapshot) == .all {
                    Picker("Manual compression", selection: $presetMediaSettingsTab) {
                        Text("Image").tag(PresetMediaSettingsTab.image)
                        Text("Video").tag(PresetMediaSettingsTab.video)
                        Text("PDF").tag(PresetMediaSettingsTab.pdf)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Manual compression by media type")
                }
                switch effectiveMediaTab(for: snapshot) {
                case .image:
                    ContentTypeChipPicker(contentTypeHintRaw: binding(\.contentTypeHintRaw, snapshot: snapshot))
                case .video:
                    presetManualCompressionVideoControls(snapshot)
                case .pdf:
                    presetManualCompressionPDFControls(snapshot)
                }
            } else {
                Text("Adjusts compression from each file: image encoding from content, video strength from resolution and bitrate, PDF tier from the document.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            Picker("Applies to", selection: binding(\.presetMediaScopeRaw, snapshot: snapshot)) {
                ForEach(PresetMediaScope.allCases) { scope in
                    Text(scope.displayName).tag(scope.rawValue)
                }
            }
            if presetMediaScope(for: snapshot) == .all {
                Picker("Media settings", selection: $presetMediaSettingsTab) {
                    Text("Image").tag(PresetMediaSettingsTab.image)
                    Text("Video").tag(PresetMediaSettingsTab.video)
                    Text("PDF").tag(PresetMediaSettingsTab.pdf)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Media settings")
            }
            switch effectiveMediaTab(for: snapshot) {
            case .image:
                presetImageControls(snapshot)
            case .video:
                presetVideoControls(snapshot)
            case .pdf:
                presetPDFControls(snapshot)
            }
        } header: {
            Text("Media")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Watch folders use this preset only for matching file types. Other files use the global sidebar settings.")
                    .font(.caption)
                PreferencesRelatedTabLink(title: "Global watch folder…", tab: .watch)
            }
        }
        Section {
            let liveForDest = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
            Picker("Save to", selection: binding(\.saveLocationRaw, snapshot: snapshot)) {
                Text("Same folder as original").tag("sameFolder")
                Text("Downloads folder").tag("downloads")
                if !prefs.customFolderDisplayPath.isEmpty || liveForDest.saveLocationRaw == "custom" {
                    Text(prefs.customFolderDisplayPath.isEmpty
                         ? "Global custom folder (not set)"
                         : URL(fileURLWithPath: prefs.customFolderDisplayPath).lastPathComponent)
                        .tag("custom")
                }
                Text("Unique folder…").tag("presetCustom")
            }
            if liveForDest.saveLocationRaw == "presetCustom" {
                HStack {
                    Text(liveForDest.presetCustomFolderPath.isEmpty
                         ? "No folder selected"
                         : URL(fileURLWithPath: liveForDest.presetCustomFolderPath).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { pickPresetCustomFolder(for: snapshot) }
                        .buttonStyle(.bordered)
                }
            }
            Picker("Filename", selection: binding(\.filenameHandlingRaw, snapshot: snapshot)) {
                Text("Append \"-dinky\" suffix").tag("appendSuffix")
                Text("Replace original").tag("replaceOrigin")
                Text("Custom suffix").tag("customSuffix")
            }
            if snapshot.filenameHandlingRaw == "customSuffix" {
                HStack {
                    Text("Suffix").foregroundStyle(.secondary)
                    TextField("-dinky", text: binding(\.customSuffix, snapshot: snapshot))
                }
            }
        } header: {
            Text("Destination")
        } footer: {
            PreferencesRelatedTabLink(title: "Default Output settings…", tab: .output)
        }
        Section("Watch Folder") {
            let liveForWatch = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
            Toggle("Watch this folder", isOn: binding(\.watchFolderEnabled, snapshot: snapshot))
            if liveForWatch.watchFolderEnabled {
                Picker("Folder", selection: binding(\.watchFolderModeRaw, snapshot: snapshot)) {
                    Text("Use global watch").tag("global")
                    Text("Unique folder…").tag("unique")
                }
                if liveForWatch.watchFolderModeRaw == "global" {
                    Text("Uses the folder set in Settings → Watch → Global, with the main window’s current settings. Add a unique folder below only if you want this preset’s options applied automatically somewhere else.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PreferencesRelatedTabLink(title: "Edit global watch folder…", tab: .watch)
                }
                if liveForWatch.watchFolderModeRaw == "unique" {
                    HStack {
                        Text(liveForWatch.watchFolderPath.isEmpty
                             ? "No folder selected"
                             : URL(fileURLWithPath: liveForWatch.watchFolderPath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { pickWatchFolder(for: snapshot) }
                            .buttonStyle(.bordered)
                    }
                }
                Text("Unique folder: new files are compressed with this preset’s saved options, independent of the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section("Advanced") {
            Toggle("Strip metadata", isOn: binding(\.stripMetadata, snapshot: snapshot))
            Text("Removes EXIF, GPS, camera info, and color profiles. Reduces file size slightly.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Sanitize filenames", isOn: binding(\.sanitizeFilenames, snapshot: snapshot))
            Text("Replaces spaces and special characters to improve cross-platform compatibility.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Open folder when done", isOn: binding(\.openFolderWhenDone, snapshot: snapshot))
            Text("Opens the output folder in Finder after each compression batch.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Notifications") {
            Toggle("Notify when done", isOn: binding(\.notifyWhenDone, snapshot: snapshot))
            Text("Sends a macOS notification when a compression batch finishes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Fixed PDF tier when Smart quality is off (flatten mode). Output mode lives under Media.
    @ViewBuilder
    private func presetManualCompressionPDFControls(_ snapshot: CompressionPreset) -> some View {
        let live = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
        VStack(alignment: .leading, spacing: 8) {
            if PDFOutputMode(rawValue: live.pdfOutputModeRaw) == .flattenPages {
                QualityChipPicker(
                    options: PDFQuality.allCases.map { ($0.displayName, $0.rawValue, $0.description) },
                    selected: binding(\.pdfQualityRaw, snapshot: snapshot)
                )
            } else {
                Text("Low / Medium / High apply when Flatten (smallest) is selected under Media.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Fixed video strength when Smart quality is off. Codec and audio live under Media.
    @ViewBuilder
    private func presetManualCompressionVideoControls(_ snapshot: CompressionPreset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            QualityChipPicker(
                options: VideoQuality.allCases.map { ($0.displayName, $0.rawValue, $0.description) },
                selected: binding(\.videoQualityRaw, snapshot: snapshot)
            )
            Text("Codec and audio options are under Media.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func presetImageControls(_ snapshot: CompressionPreset) -> some View {
        let live = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
        // Single container so Form doesn’t allocate one row per child (Divider/Toggle rows looked like blank gaps).
        VStack(alignment: .leading, spacing: 10) {
            FormatChipPicker(
                autoFormat: binding(\.autoFormat, snapshot: snapshot),
                selectedFormat: binding(\.format, snapshot: snapshot)
            )
            Divider()
            Toggle("Limit width", isOn: binding(\.maxWidthEnabled, snapshot: snapshot))
            if live.maxWidthEnabled {
                presetChips(
                    presets: [("640", 640), ("1080", 1080), ("1280", 1280),
                              ("1920", 1920), ("2560", 2560), ("3840", 3840)],
                    current: live.maxWidth,
                    onSelect: { set(\.maxWidth, to: $0, for: snapshot) }
                )
                HStack(spacing: 6) {
                    TextField("", value: binding(\.maxWidth, snapshot: snapshot), format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 80)
                        .labelsHidden()
                    Text("px").foregroundStyle(.secondary)
                }
            }
            Divider()
            Toggle("Limit file size", isOn: binding(\.maxFileSizeEnabled, snapshot: snapshot))
            if live.maxFileSizeEnabled {
                presetChips(
                    presets: [("0.5 MB", 512), ("1 MB", 1024), ("2 MB", 2048),
                              ("5 MB", 5120), ("10 MB", 10240)],
                    current: live.maxFileSizeKB,
                    onSelect: { set(\.maxFileSizeKB, to: $0, for: snapshot) }
                )
                HStack(spacing: 6) {
                    TextField("", value: mbBinding(for: snapshot), format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 80)
                        .labelsHidden()
                    Text("MB").foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func presetPDFControls(_ snapshot: CompressionPreset) -> some View {
        let livePDF = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
        VStack(alignment: .leading, spacing: 10) {
            Picker("Output", selection: binding(\.pdfOutputModeRaw, snapshot: snapshot)) {
                Text("Preserve text & links").tag(PDFOutputMode.preserveStructure.rawValue)
                Text("Flatten (smallest)").tag(PDFOutputMode.flattenPages.rawValue)
            }
            .pickerStyle(.segmented)

            if PDFOutputMode(rawValue: livePDF.pdfOutputModeRaw) == .flattenPages {
                QualityChipPicker(
                    options: PDFQuality.allCases.map { ($0.displayName, $0.rawValue, $0.description) },
                    selected: binding(\.pdfQualityRaw, snapshot: snapshot)
                )
                .disabled(livePDF.smartQuality)
                if livePDF.smartQuality {
                    Text("Manual tier is a fallback when smart analysis can’t run. Turn off Smart quality under Compression to fix Low / Medium / High.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Grayscale PDF", isOn: binding(\.pdfGrayscale, snapshot: snapshot))
                if livePDF.pdfGrayscale {
                    Text("Smaller files when color isn’t needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Low / Medium / High and grayscale apply when Flatten (smallest) is selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func presetVideoControls(_ snapshot: CompressionPreset) -> some View {
        let liveVideo = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
        VStack(alignment: .leading, spacing: 10) {
            QualityChipPicker(
                options: VideoCodecFamily.allCases.map { ($0.chipLabel, $0.rawValue, $0.description) },
                selected: binding(\.videoCodecFamilyRaw, snapshot: snapshot)
            )
            QualityChipPicker(
                options: VideoQuality.allCases.map { ($0.displayName, $0.rawValue, $0.description) },
                selected: binding(\.videoQualityRaw, snapshot: snapshot)
            )
            .disabled(liveVideo.smartQuality)
            if liveVideo.smartQuality {
                Text("Manual video quality is a fallback when metadata can’t be read. Codec above always applies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Strip audio track", isOn: binding(\.videoRemoveAudio, snapshot: snapshot))
            if liveVideo.videoRemoveAudio {
                Text("Best for screen recordings or silent clips.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addPreset() {
        let count = prefs.savedPresets.count + 1
        let preset = CompressionPreset(name: "Preset \(count)", from: prefs, format: .webp)
        var list = prefs.savedPresets
        list.append(preset)
        prefs.savedPresets = list
        withAnimation { selectedID = preset.id }
    }

    private func deleteSelected() {
        guard let id = selectedID else { return }
        selectedID = nil
        if prefs.activePresetID == id.uuidString { prefs.activePresetID = "" }
        prefs.savedPresets = prefs.savedPresets.filter { $0.id != id }
        if let next = prefs.savedPresets.last {
            withAnimation { selectedID = next.id }
        }
    }

    private func pickWatchFolder(for snapshot: CompressionPreset) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch"
        if panel.runModal() == .OK, let url = panel.url {
            set(\.watchFolderPath, to: url.path, for: snapshot)
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                set(\.watchFolderBookmark, to: bookmark, for: snapshot)
            }
        }
    }

    private func pickPresetCustomFolder(for snapshot: CompressionPreset) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            set(\.presetCustomFolderPath, to: url.path, for: snapshot)
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                set(\.presetCustomFolderBookmark, to: bookmark, for: snapshot)
            }
        }
    }

    // Looks up the live preset by UUID for the getter; falls back to snapshot
    // during SwiftUI's teardown pass so the getter never reads a stale index.
    private func binding<T>(_ keyPath: WritableKeyPath<CompressionPreset, T>, snapshot: CompressionPreset) -> Binding<T> {
        Binding(
            get: {
                (prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot)[keyPath: keyPath]
            },
            set: {
                guard let idx = prefs.savedPresets.firstIndex(where: { $0.id == snapshot.id }) else { return }
                var presets = prefs.savedPresets
                presets[idx][keyPath: keyPath] = $0
                prefs.savedPresets = presets
            }
        )
    }

    private func set<T>(_ keyPath: WritableKeyPath<CompressionPreset, T>, to value: T, for snapshot: CompressionPreset) {
        guard let idx = prefs.savedPresets.firstIndex(where: { $0.id == snapshot.id }) else { return }
        var presets = prefs.savedPresets
        presets[idx][keyPath: keyPath] = value
        prefs.savedPresets = presets
    }

    private func mbBinding(for snapshot: CompressionPreset) -> Binding<Double> {
        Binding(
            get: {
                let live = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
                return Double(live.maxFileSizeKB) / 1024.0
            },
            set: { set(\.maxFileSizeKB, to: max(1, Int($0 * 1024)), for: snapshot) }
        )
    }

    private func presetChips(presets: [(String, Int)], current: Int, onSelect: @escaping (Int) -> Void) -> some View {
        let columns = [GridItem(.adaptive(minimum: 60), spacing: 4)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(presets, id: \.1) { label, value in
                let active = current == value
                Text(label)
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? .white : .secondary)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(active ? AnyShapeStyle(dinkyGradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(value) }
            }
        }
    }
}

// MARK: - Watch Folders

private struct WatchFoldersTab: View {
    @EnvironmentObject var prefs: DinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle("Watch a folder", isOn: Binding(
                    get: { prefs.folderWatchEnabled },
                    set: { prefs.folderWatchEnabled = $0 }
                ))
                if prefs.folderWatchEnabled {
                    HStack {
                        Text(prefs.watchedFolderPath.isEmpty
                             ? "No folder selected"
                             : URL(fileURLWithPath: prefs.watchedFolderPath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { pickGlobalWatchFolder() }
                            .buttonStyle(.bordered)
                    }
                    Text("The global folder uses whatever settings are in the main window (sidebar). Presets can add separate watched folders in their own settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    PreferencesRelatedTabLink(title: "Sidebar & behavior in General…", tab: .general)
                }
            } header: {
                Text("Global")
            }

            Section {
                if prefs.savedPresets.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No presets yet. Create one to watch a folder with saved compression options.")
                            .foregroundStyle(.secondary)
                        PreferencesRelatedTabLink(title: "Open Presets…", tab: .presets)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } else {
                    ForEach(prefs.savedPresets) { preset in
                        WatchFolderPresetRow(preset: preset)
                            .environmentObject(prefs)
                    }
                }
            } header: {
                Text("Presets")
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private func pickGlobalWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch"
        if panel.runModal() == .OK, let url = panel.url {
            prefs.watchedFolderPath = url.path
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                prefs.watchedFolderBookmark = bookmark
            }
        }
    }
}

private struct WatchFolderPresetRow: View {
    @EnvironmentObject var prefs: DinkyPreferences
    let preset: CompressionPreset

    private var live: CompressionPreset {
        prefs.savedPresets.first(where: { $0.id == preset.id }) ?? preset
    }

    var body: some View {
        Toggle(live.name, isOn: enabledBinding)
        if live.watchFolderEnabled {
            HStack {
                Image(systemName: "folder")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Text(resolvedFolderLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, 20)
        }
    }

    private var resolvedFolderLabel: String {
        if live.watchFolderModeRaw == "unique" {
            return live.watchFolderPath.isEmpty
                ? "No folder set — configure in Presets"
                : URL(fileURLWithPath: live.watchFolderPath).lastPathComponent
        }
        if !prefs.watchedFolderPath.isEmpty {
            return "Global (\(URL(fileURLWithPath: prefs.watchedFolderPath).lastPathComponent))"
        }
        return "Global watch — choose folder in Watch tab"
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { live.watchFolderEnabled },
            set: { newValue in
                guard let idx = prefs.savedPresets.firstIndex(where: { $0.id == preset.id }) else { return }
                var list = prefs.savedPresets
                list[idx].watchFolderEnabled = newValue
                prefs.savedPresets = list
            }
        )
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    var body: some View {
        Form {
            Section {
                ForEach(S.keyboardShortcutReference) { row in
                    HStack(spacing: 12) {
                        Text(row.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 12)
                        KeyComboView(combo: row.keys)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.title), \(row.keys)")
                }
            } header: {
                Text("Menu commands")
            } footer: {
                Text(S.shortcutsTabServicesFooter)
                    .font(.caption)
            }

            Section {
                Text(S.shortcutsAppDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Shortcuts app")
            }

            Section {
                Text(S.shortcutsTabHelpFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("More help")
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

/// Renders a compact key combo like `⌘⇧V` as individual keycaps.
private struct KeyComboView: View {
    let combo: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(combo.enumerated()), id: \.offset) { _, ch in
                KeyCapView(label: String(ch))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A single keycap, sized to its content but with a uniform minimum so modifier glyphs and letters line up.
private struct KeyCapView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }
}
