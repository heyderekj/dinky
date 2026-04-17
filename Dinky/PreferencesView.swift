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

            // 3. Alerts
            Section {
                Toggle("Play sound when done", isOn: Binding(
                    get: { prefs.playSoundEffects },
                    set: { prefs.playSoundEffects = $0 }
                ))
                Toggle("Notify when done", isOn: Binding(
                    get: { prefs.notifyWhenDone },
                    set: { prefs.notifyWhenDone = $0 }
                ))
            } header: {
                Text("Notifications")
            }

            // 4. App modes
            Section {
                Toggle("Menu bar mode", isOn: Binding(
                    get: { prefs.menuBarMode },
                    set: { prefs.menuBarMode = $0 }
                ))
                Text("Adds a Dinky icon to the menu bar. Drop images onto it to compress without opening the main window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Menu Bar")
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

            // 6. Updates
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

            Section {
                Toggle("Auto-watch folder", isOn: Binding(
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
                        Button("Choose…") { pickWatchFolder() }
                            .buttonStyle(.bordered)
                    }
                    Text("New images added to this folder are automatically compressed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Watch Folder")
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private func pickWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch"
        if panel.runModal() == .OK, let url = panel.url {
            prefs.watchedFolderPath = url.path
        }
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
                                Text(preset.format.displayName)
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
            Picker("Format", selection: binding(\.format, snapshot: snapshot)) {
                Text("WebP").tag(CompressionFormat.webp)
                Text("AVIF").tag(CompressionFormat.avif)
                Text("PNG").tag(CompressionFormat.png)
            }
            .pickerStyle(.segmented)
            Toggle("Smart quality", isOn: binding(\.smartQuality, snapshot: snapshot))
            Toggle("Auto-format", isOn: binding(\.autoFormat, snapshot: snapshot))
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
            Picker("Save to", selection: binding(\.saveLocationRaw, snapshot: snapshot)) {
                Text("Same folder as original").tag("sameFolder")
                Text("Downloads folder").tag("downloads")
                Text("Custom folder (set in Output)").tag("custom")
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
        Section("Advanced") {
            Toggle("Strip metadata", isOn: binding(\.stripMetadata, snapshot: snapshot))
            Toggle("Sanitize filenames", isOn: binding(\.sanitizeFilenames, snapshot: snapshot))
            Toggle("Open folder when done", isOn: binding(\.openFolderWhenDone, snapshot: snapshot))
        }
        Section("Notifications") {
            Toggle("Notify when done", isOn: binding(\.notifyWhenDone, snapshot: snapshot))
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
        prefs.savedPresets = prefs.savedPresets.filter { $0.id != id }
        if let next = prefs.savedPresets.last {
            withAnimation { selectedID = next.id }
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
                            .fill(active
                                  ? AnyShapeStyle(LinearGradient(
                                        colors: [Color(red: 0.25, green: 0.55, blue: 1.0),
                                                 Color(red: 0.45, green: 0.30, blue: 0.95)],
                                        startPoint: .leading, endPoint: .trailing))
                                  : AnyShapeStyle(Color.primary.opacity(0.08)))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(value) }
            }
        }
    }
}
