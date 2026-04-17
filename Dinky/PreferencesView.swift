import SwiftUI
import AppKit
import UserNotifications

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
            WatchFoldersTab()
                .tabItem { Label("Watch", systemImage: "eye") }
                .environmentObject(prefs)
            PresetsTab()
                .tabItem { Label("Presets", systemImage: "slider.horizontal.3") }
                .environmentObject(prefs)
        }
        .frame(width: 480, height: 460)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @EnvironmentObject var updater: UpdateChecker

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
                Text("Skip files where compression savings fall below this threshold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Preserve original timestamps", isOn: Binding(
                    get: { prefs.preserveTimestamps },
                    set: { prefs.preserveTimestamps = $0 }
                ))
            } header: {
                Text("Compression")
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
            }

            // 4. Accessibility
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

        }
        .formStyle(.grouped)
        .padding(.top, 8)
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

private struct PresetsTab: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @State private var selectedID: UUID? = nil

    private var selectedPreset: CompressionPreset? {
        prefs.savedPresets.first { $0.id == selectedID }
    }

    var body: some View {
        Form {
            presetListSection
            if let preset = selectedPreset { presetDetailSections(preset) }
        }
        .formStyle(.grouped)
        .animation(.easeInOut(duration: 0.2), value: selectedID)
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
                                Text(preset.autoFormat ? "Auto" : preset.format.displayName)
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
        Section("Format") {
            FormatChipPicker(
                autoFormat: binding(\.autoFormat, snapshot: snapshot),
                selectedFormat: binding(\.format, snapshot: snapshot)
            )
        }
        Section("Quality") {
            let liveForQuality = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
            Toggle("Smart quality", isOn: binding(\.smartQuality, snapshot: snapshot))
            if !liveForQuality.smartQuality {
                ContentTypeChipPicker(contentTypeHintRaw: binding(\.contentTypeHintRaw, snapshot: snapshot))
            } else {
                Text("Detects content type per image automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section("Max Width") {
            Toggle("Limit width", isOn: binding(\.maxWidthEnabled, snapshot: snapshot))
            if snapshot.maxWidthEnabled {
                presetChips(
                    presets: [("640", 640), ("1080", 1080), ("1280", 1280),
                              ("1920", 1920), ("2560", 2560), ("3840", 3840)],
                    current: snapshot.maxWidth,
                    onSelect: { set(\.maxWidth, to: $0, for: snapshot) }
                )
                HStack(spacing: 6) {
                    TextField("", value: binding(\.maxWidth, snapshot: snapshot), format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 80)
                        .labelsHidden()
                    Text("px").foregroundStyle(.secondary)
                }
            }
        }
        Section("Max File Size") {
            Toggle("Limit file size", isOn: binding(\.maxFileSizeEnabled, snapshot: snapshot))
            if snapshot.maxFileSizeEnabled {
                presetChips(
                    presets: [("0.5 MB", 512), ("1 MB", 1024), ("2 MB", 2048),
                              ("5 MB", 5120), ("10 MB", 10240)],
                    current: snapshot.maxFileSizeKB,
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
        Section("Destination") {
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
        }
        Section("Watch Folder") {
            let liveForWatch = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
            Toggle("Watch this folder", isOn: binding(\.watchFolderEnabled, snapshot: snapshot))
            if liveForWatch.watchFolderEnabled {
                Picker("Folder", selection: binding(\.watchFolderModeRaw, snapshot: snapshot)) {
                    Text("Same as destination").tag("destination")
                    Text("Unique folder…").tag("unique")
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
                Text("New images added to this folder are automatically compressed using this preset.")
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
                    Text("New images dropped here are compressed with your current settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Global")
            }

            Section {
                if prefs.savedPresets.isEmpty {
                    Text("No presets yet. Add one in the Presets tab.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
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
        switch live.saveLocationRaw {
        case "downloads":    return "Downloads"
        case "custom":       return prefs.customFolderDisplayPath.isEmpty ? "Custom folder" : URL(fileURLWithPath: prefs.customFolderDisplayPath).lastPathComponent
        case "presetCustom": return live.presetCustomFolderPath.isEmpty ? "Unique output folder" : URL(fileURLWithPath: live.presetCustomFolderPath).lastPathComponent
        default:             return "Same folder as source"
        }
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
