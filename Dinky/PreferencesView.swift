import SwiftUI
import AppKit
import UserNotifications
import DinkyCoreShared

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

/// Accent navigation target styled like a compact settings card.
private struct PreferencesRelatedTabLink: View {
    @Environment(\.openPreferencesRelatedTab) private var openTab
    let title: String
    let tab: PreferencesTab

    var body: some View {
        Button {
            openTab(tab)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Tabs in the Settings window — use `openWindow(to:)` to deep-link from the main window sidebar.
enum PreferencesTab: Int, CaseIterable, Hashable, Identifiable {
    case behavior = 0
    case originals = 1
    case compression = 2
    case notifications = 3
    case privacy = 4
    case about = 5
    case output = 6
    case watch = 7
    case presets = 8
    case shortcuts = 9
    case sidebar = 10
    case accessibility = 11

    var id: Int { rawValue }

    static let pendingTabUserDefaultsKey = "prefs.pendingTab"
    /// Deep link: sidebar “Edit preset…” selects this preset when Presets opens.
    static let pendingPresetUUIDKey = "prefs.pendingPresetUUID"

    static var generalGroup: [PreferencesTab] {
        [.behavior, .originals, .compression, .notifications, .privacy, .about]
    }
    static var workflowGroup: [PreferencesTab] {
        [.output, .watch, .presets, .shortcuts]
    }
    static var interfaceGroup: [PreferencesTab] {
        [.sidebar, .accessibility]
    }

    var sidebarLabel: String {
        switch self {
        case .behavior: return String(localized: "Behavior", comment: "Settings sidebar item.")
        case .originals: return String(localized: "Original Files", comment: "Settings sidebar item.")
        case .compression: return String(localized: "Compression", comment: "Settings sidebar item.")
        case .notifications: return String(localized: "Notifications", comment: "Settings sidebar item.")
        case .privacy: return String(localized: "Privacy", comment: "Settings sidebar item.")
        case .about: return String(localized: "About & Support", comment: "Settings sidebar item.")
        case .output: return String(localized: "Output", comment: "Settings UI.")
        case .watch: return String(localized: "Watch", comment: "Settings UI.")
        case .presets: return String(localized: "Presets", comment: "Settings UI.")
        case .shortcuts: return String(localized: "Shortcuts", comment: "Settings UI.")
        case .sidebar: return String(localized: "Sidebar", comment: "Settings sidebar item.")
        case .accessibility: return String(localized: "Accessibility", comment: "Settings sidebar item.")
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .behavior: return "slider.horizontal.3"
        case .originals: return "doc.on.doc"
        case .compression: return "arrow.down.circle"
        case .notifications: return "bell"
        case .privacy: return "hand.raised"
        case .about: return "info.circle"
        case .output: return "folder"
        case .watch: return "eye"
        case .presets: return "slider.horizontal.3"
        case .shortcuts: return "keyboard"
        case .sidebar: return "sidebar.left"
        case .accessibility: return "accessibility"
        }
    }

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
        return migrateStoredTabIndex(raw)
    }

    /// Maps legacy TabView indices (0–5) and new split-view raw values to a pane.
    static func migrateStoredTabIndex(_ raw: Int) -> PreferencesTab {
        switch raw {
        case 0: return .behavior
        case 1: return .output
        case 2: return .watch
        case 3: return .presets
        case 4: return .shortcuts
        case 5: return .sidebar
        default: return PreferencesTab(rawValue: raw) ?? .behavior
        }
    }
}

struct PreferencesView: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @EnvironmentObject var updater: UpdateChecker

    @State private var history: [PreferencesTab] = [.behavior]
    @State private var historyIndex: Int = 0

    private var selectedTab: PreferencesTab { history[historyIndex] }

    private var selectedTabBinding: Binding<PreferencesTab> {
        Binding(get: { history[historyIndex] }, set: { selectPane($0) })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selectedTabBinding) {
                Section(String(localized: "General", comment: "Settings sidebar section header.")) {
                    ForEach(PreferencesTab.generalGroup, id: \.self) { tab in
                        Label(tab.sidebarLabel, systemImage: tab.sidebarSystemImage).tag(tab)
                    }
                }
                Section(String(localized: "Workflow", comment: "Settings sidebar section header.")) {
                    ForEach(PreferencesTab.workflowGroup, id: \.self) { tab in
                        Label(tab.sidebarLabel, systemImage: tab.sidebarSystemImage).tag(tab)
                    }
                }
                Section(String(localized: "Interface", comment: "Settings sidebar section header.")) {
                    ForEach(PreferencesTab.interfaceGroup, id: \.self) { tab in
                        Label(tab.sidebarLabel, systemImage: tab.sidebarSystemImage).tag(tab)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("")
            .toolbar(removing: .sidebarToggle)
            .toolbarBackground(.clear, for: .automatic)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            NavigationStack {
                preferencesDetail(for: selectedTab)
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(selectedTab.sidebarLabel)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button { goBack() } label: {
                                Image(systemName: "chevron.backward")
                            }
                            .buttonStyle(.bordered)
                            .help(String(localized: "Back", comment: "Preferences toolbar."))
                            .disabled(historyIndex == 0)
                        }
                        ToolbarItem(placement: .navigation) {
                            Button { goForward() } label: {
                                Image(systemName: "chevron.forward")
                            }
                            .buttonStyle(.bordered)
                            .help(String(localized: "Forward", comment: "Preferences toolbar."))
                            .disabled(historyIndex >= history.count - 1)
                        }
                        if #available(macOS 26.0, *) {
                            ToolbarSpacer(.flexible)
                        }
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarBackground(.clear, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .environment(\.openPreferencesRelatedTab) { selectPane($0) }
        .frame(width: 760, height: 560)
        .onAppear {
            if let tab = PreferencesTab.consumePendingSelection() {
                selectPane(tab)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkySelectPreferencesTab)) { note in
            guard let raw = note.object as? Int else { return }
            let tab = PreferencesTab.migrateStoredTabIndex(raw)
            selectPane(tab)
            UserDefaults.standard.removeObject(forKey: PreferencesTab.pendingTabUserDefaultsKey)
        }
    }

    private func selectPane(_ tab: PreferencesTab) {
        guard tab != selectedTab else { return }
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(tab)
        historyIndex = history.count - 1
    }

    private func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
    }

    private func goForward() {
        guard historyIndex < history.count - 1 else { return }
        historyIndex += 1
    }

    @ViewBuilder
    private func preferencesDetail(for tab: PreferencesTab) -> some View {
        switch tab {
        case .behavior:
            BehaviorPreferencesPane()
                .environmentObject(prefs)
        case .originals:
            OriginalsPreferencesPane().environmentObject(prefs)
        case .compression:
            CompressionPreferencesPane().environmentObject(prefs)
        case .notifications:
            NotificationsPreferencesPane().environmentObject(prefs)
        case .privacy:
            PrivacyPreferencesPane().environmentObject(prefs)
        case .about:
            AboutPreferencesPane().environmentObject(prefs)
        case .output:
            OutputTab().environmentObject(prefs)
        case .watch:
            WatchFoldersTab().environmentObject(prefs)
        case .presets:
            PresetsTab().environmentObject(prefs)
        case .shortcuts:
            ShortcutsTab().environmentObject(prefs)
        case .sidebar:
            SidebarPreferencesPane().environmentObject(prefs)
        case .accessibility:
            AccessibilityPreferencesPane().environmentObject(prefs)
        }
    }
}

// MARK: - General (split panes)

private struct BehaviorPreferencesPane: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @State private var launchAtLoginEnabled: Bool = LaunchAtLoginManager.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Open Dinky at login", comment: "Settings UI."), isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { newValue in
                        LaunchAtLoginManager.setEnabled(newValue)
                        launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
                    }
                ))
                if LaunchAtLoginManager.requiresApproval {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(String(localized: "Approve Dinky in System Settings → General → Login Items.", comment: "Settings UI."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "Open…", comment: "Settings UI.")) { LaunchAtLoginManager.openLoginItemsSettings() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Toggle(String(localized: "Always confirm before compressing", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.confirmBeforeEveryCompression },
                    set: { prefs.confirmBeforeEveryCompression = $0 }
                ))

                Toggle(String(localized: "Manual mode by default", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.manualMode },
                    set: { prefs.manualMode = $0 }
                ))

                Toggle(String(localized: "Global Clipboard Compress", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.pasteClipboardGlobalEnabled },
                    set: { newValue in
                        prefs.pasteClipboardGlobalEnabled = newValue
                        NotificationCenter.default.post(name: .dinkyGlobalPasteHotkeyChanged, object: nil)
                    }
                ))
                Text(S.behaviorPasteClipboardGlobalFootnote(currentShortcutDisplay: prefs.shortcut(for: .pasteClipboard).displayString))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                PreferencesRelatedTabLink(title: String(localized: "Change shortcut in Keyboard Shortcuts…", comment: "Settings UI."), tab: .shortcuts)

                Toggle(String(localized: "Show batch summary when done", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.showBatchSummaryDialog },
                    set: { prefs.showBatchSummaryDialog = $0 }
                ))

                Toggle(String(localized: "Auto-clear queue when done", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.autoClearWhenDone },
                    set: { prefs.autoClearWhenDone = $0 }
                ))
            } header: {
                Text(String(localized: "Behavior", comment: "Settings UI."))
            } footer: {
                Text(String(localized: "Confirm covers drag-and-drop, Open, the Dock, Services, and Clipboard (not Watch Folder). Manual mode waits for Compress Now. Batch summary shows savings; auto-clear removes finished rows while failures remain.", comment: "Settings UI: Behavior section summary footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLoginEnabled = LaunchAtLoginManager.isEnabled }
    }
}

private struct OriginalsPreferencesPane: View {
    @EnvironmentObject var prefs: DinkyPreferences

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "After compressing, originals:", comment: "Settings UI."), selection: Binding(
                    get: { prefs.originalsAction },
                    set: { prefs.originalsAction = $0 }
                )) {
                    Text(String(localized: "Stay where they are", comment: "Settings UI.")).tag(OriginalsAction.keep)
                    Text(String(localized: "Move to Trash", comment: "Settings UI.")).tag(OriginalsAction.trash)
                    Text(String(localized: "Move to Backup folder", comment: "Settings UI.")).tag(OriginalsAction.backup)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if prefs.originalsAction == .keep {
                    Text(String(localized: "Source files are never moved or deleted — even when Filename = Replace original (the original is only displaced when output would overwrite it).", comment: "Settings UI."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if prefs.originalsAction == .trash {
                    Text(String(localized: "Permanent once the trash is emptied.", comment: "Settings UI."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if prefs.originalsAction == .backup {
                    HStack {
                        Text(prefs.originalsBackupFolderDisplayPath.isEmpty
                             ? prefs.defaultOriginalsBackupFolderURL().path
                             : prefs.originalsBackupFolderDisplayPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "Choose…", comment: "Settings UI.")) { pickOriginalsBackupFolder() }
                            .buttonStyle(.bordered)
                        if !prefs.originalsBackupFolderBookmark.isEmpty {
                            Button(String(localized: "Use default", comment: "Settings UI.")) {
                                prefs.originalsBackupFolderBookmark = Data()
                                prefs.originalsBackupFolderDisplayPath = ""
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Text(String(localized: "Original files are moved here after a successful compress.", comment: "Settings UI."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "Original Files", comment: "Settings UI."))
            }
        }
        .formStyle(.grouped)
    }

    private func pickOriginalsBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose", comment: "Open panel default button.")
        if panel.runModal() == .OK, let url = panel.url {
            prefs.originalsBackupFolderDisplayPath = url.path
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                prefs.originalsBackupFolderBookmark = bookmark
            }
        }
    }
}

private struct CompressionPreferencesPane: View {
    @EnvironmentObject var prefs: DinkyPreferences

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Skip if savings below", comment: "Settings UI."), selection: Binding(
                    get: { prefs.minimumSavingsPercent },
                    set: { prefs.minimumSavingsPercent = $0 }
                )) {
                    Text(String(localized: "Off", comment: "Settings UI.")).tag(0)
                    Text(String(localized: "2%", comment: "Settings UI.")).tag(2)
                    Text(String(localized: "5%", comment: "Settings UI.")).tag(5)
                    Text(String(localized: "10%", comment: "Settings UI.")).tag(10)
                }
                .pickerStyle(.segmented)

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

                Toggle(S.batchLargestFirstLabel, isOn: Binding(
                    get: { prefs.batchLargestFirst },
                    set: { prefs.batchLargestFirst = $0 }
                ))

                Toggle(String(localized: "Preserve original timestamps", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.preserveTimestamps },
                    set: { prefs.preserveTimestamps = $0 }
                ))
                Toggle(String(localized: "Preserve Finder comments", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.preserveFinderComments },
                    set: { prefs.preserveFinderComments = $0 }
                ))
            } header: {
                Text(String(localized: "Compression", comment: "Settings UI."))
            } footer: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Skip-if-savings applies to images and video; PDFs keep smaller results regardless. Higher concurrency runs more encoders at once. Batch order affects perceived progress on large batches. Finder comments are separate from stripping embedded metadata in the sidebar.", comment: "Settings UI: Compression section footer."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(S.concurrentCompressionFootnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(S.batchLargestFirstFootnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PreferencesRelatedTabLink(title: String(localized: "Per-preset compression & media…", comment: "Settings UI."), tab: .presets)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct NotificationsPreferencesPane: View {
    @EnvironmentObject var prefs: DinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Play sound when done", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.playSoundEffects },
                    set: { prefs.playSoundEffects = $0 }
                ))
                Toggle(String(localized: "Notify when done", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.notifyWhenDone },
                    set: { newValue in
                        prefs.notifyWhenDone = newValue
                        if newValue { requestNotificationAuth() }
                    }
                ))
                Toggle(String(localized: "Open folder when done", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.openFolderWhenDone },
                    set: { prefs.openFolderWhenDone = $0 }
                ))
            } header: {
                Text(String(localized: "Notifications", comment: "Settings UI."))
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Notifications may be suppressed during Focus or Do Not Disturb until Dinky is allowed in System Settings → Notifications. Open Folder reveals the output directory after each batch.", comment: "Settings UI: Notifications footer."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Notification settings…", comment: "Settings UI.")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .formStyle(.grouped)
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

private struct PrivacyPreferencesPane: View {
    @EnvironmentObject var prefs: DinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Share crash diagnostics with Dinky", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.crashReportingEnabled },
                    set: { newValue in
                        prefs.crashReportingEnabled = newValue
                        DiagnosticsReporter.shared.applyCrashReportingPreference()
                    }
                ))
            } header: {
                Text(String(localized: "Privacy", comment: "Settings UI."))
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "When on, Apple's MetricKit can deliver anonymous crash and hang diagnostics to Dinky on your Mac. Nothing leaves your device until you choose to send a report. Requires \u{201C}Share with App Developers\u{201D} in System Settings → Privacy & Security → Analytics & Improvements.", comment: "Settings UI."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Open Analytics & Improvements settings…", comment: "Settings UI.")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Analytics")!)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutPreferencesPane: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @State private var confirmResetLifetime = false

    var body: some View {
        Form {
            Section {
                Button(String(localized: "Reset total saved statistics…", comment: "Settings UI.")) {
                    confirmResetLifetime = true
                }
                .disabled(prefs.lifetimeSavedBytes == 0)
            } header: {
                Text(String(localized: "Session history", comment: "Settings UI."))
            } footer: {
                Text(String(localized: "Clears the running total shown in History. Session history is unchanged — clear that from the History window.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                PreferencesRelatedTabLink(title: String(localized: "Keyboard shortcuts…", comment: "Settings UI."), tab: .shortcuts)
                Link(S.supportEmail, destination: URL(string: "mailto:\(S.supportEmail)")!)
            } header: {
                Text(String(localized: "Support", comment: "Settings UI."))
            }

            Section {
                Text(String(localized: "Dinky includes advanced local tools for pro users: a `dinky` command-line tool and optional local HTTP mode (`dinky serve`) for automation and AI agents.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Quirky but straightforward: give Dinky file paths, get smaller files back. Everything runs on your Mac.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(String(localized: "CLI docs and examples…", comment: "Settings UI."), destination: URL(string: "https://github.com/heyderekj/dinky/blob/main/docs/local-cli.md")!)
            } header: {
                Text(String(localized: "Pro tools (CLI/API)", comment: "Settings UI."))
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            String(localized: "Reset the running total of bytes saved across all sessions?", comment: "Settings UI."),
            isPresented: $confirmResetLifetime,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Reset", comment: "Settings UI."), role: .destructive) {
                prefs.lifetimeSavedBytes = 0
            }
            Button(String(localized: "Cancel", comment: "Settings UI."), role: .cancel) {}
        } message: {
            Text(String(localized: "This does not clear the per-session list in History.", comment: "Settings UI."))
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyPrepareQuit)) { _ in
            confirmResetLifetime = false
        }
    }
}

// MARK: - Sidebar & Accessibility

private struct SidebarPreferencesPane: View {
    @EnvironmentObject var prefs: DinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Use simple sidebar", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.sidebarSimpleMode },
                    set: { prefs.applySidebarSimpleMode($0) }
                ))

                Toggle(String(localized: "Show Images in sidebar", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.showImagesSection },
                    set: { prefs.setScopedSidebarSection(.images, isOn: $0) }
                ))
                Toggle(String(localized: "Show Audio in sidebar", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.showAudioSection },
                    set: { prefs.setScopedSidebarSection(.audio, isOn: $0) }
                ))
                Toggle(String(localized: "Show Videos in sidebar", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.showVideosSection },
                    set: { prefs.setScopedSidebarSection(.videos, isOn: $0) }
                ))
                Toggle(String(localized: "Show PDFs in sidebar", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.showPDFsSection },
                    set: { prefs.setScopedSidebarSection(.pdfs, isOn: $0) }
                ))
            } header: {
                Text(String(localized: "Sidebar", comment: "Settings UI."))
            } footer: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(prefs.sidebarSimpleMode
                         ? String(localized: "Simple sidebar shows quick choices only. Turn on a section above to add its full scope to the sidebar, or turn off simple sidebar to show every section.", comment: "Settings UI.")
                         : String(localized: "Sections you turn off stay available in Settings and in the full sidebar.", comment: "Settings UI."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PreferencesRelatedTabLink(title: String(localized: "Presets & automatic folders…", comment: "Settings UI."), tab: .presets)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccessibilityPreferencesPane: View {
    @EnvironmentObject var prefs: DinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Reduce motion", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.reduceMotion },
                    set: { prefs.reduceMotion = $0 }
                ))
            } header: {
                Text(String(localized: "Accessibility", comment: "Settings UI."))
            } footer: {
                Text(String(localized: "Replaces the drop zone animation with a still arrangement of cards.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Output

private struct OutputTab: View {
    @EnvironmentObject var prefs: DinkyPreferences

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Defaults for the main window. Presets can set their own folder and filename rules.", comment: "Settings Output tab intro."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PreferencesRelatedTabLink(title: String(localized: "Per-preset output…", comment: "Settings UI."), tab: .presets)
                }
                .padding(.vertical, 2)

                Picker(String(localized: "Save to", comment: "Settings UI."), selection: Binding(
                    get: { prefs.saveLocation },
                    set: { prefs.saveLocation = $0 }
                )) {
                    Text(String(localized: "Same folder as original", comment: "Settings UI.")).tag(SaveLocation.sameFolder)
                    Text(String(localized: "Downloads folder", comment: "Settings UI.")).tag(SaveLocation.downloads)
                    Text(String(localized: "Custom folder…", comment: "Settings UI.")).tag(SaveLocation.custom)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if prefs.saveLocation == .custom {
                    HStack {
                        Text(prefs.customFolderDisplayPath.isEmpty
                             ? String(localized: "No folder selected", comment: "Settings UI.") : prefs.customFolderDisplayPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "Choose…", comment: "Settings UI.")) { pickCustomFolder() }
                            .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text(String(localized: "Save Location", comment: "Settings UI."))
            }

            Section {
                Picker(String(localized: "Filename", comment: "Settings UI."), selection: Binding(
                    get: { prefs.filenameHandling },
                    set: { prefs.filenameHandling = $0 }
                )) {
                    Text(String(localized: "Append \"-dinky\" suffix", comment: "Settings UI.")).tag(FilenameHandling.appendSuffix)
                    Text(String(localized: "Replace original", comment: "Settings UI.")).tag(FilenameHandling.replaceOrigin)
                    Text(String(localized: "Custom suffix", comment: "Settings UI.")).tag(FilenameHandling.customSuffix)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if prefs.filenameHandling == .customSuffix {
                    HStack {
                        Text(String(localized: "Suffix", comment: "Settings UI."))
                            .foregroundStyle(.secondary)
                        TextField(String(localized: "-dinky", comment: "Settings UI."), text: Binding(
                            get: { prefs.customSuffix },
                            set: { prefs.customSuffix = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    }
                }
            } header: {
                Text(String(localized: "Filename", comment: "Settings UI."))
            }

            Section {
                Picker(S.duplicateNamingPickerAccessibilityLabel, selection: Binding(
                    get: { prefs.collisionNamingStyle },
                    set: { prefs.collisionNamingStyle = $0 }
                )) {
                    ForEach(CollisionNamingStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if prefs.collisionNamingStyle == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(S.duplicateNamingCustomFieldLabel)
                                .foregroundStyle(.secondary)
                            TextField(
                                S.duplicateNamingCustomPlaceholder,
                                text: Binding(
                                    get: { prefs.collisionCustomPattern },
                                    set: { prefs.collisionCustomPattern = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 160)
                            .accessibilityLabel(S.duplicateNamingCustomFieldLabel)
                        }
                        Text(S.duplicateNamingCustomHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(String(localized: "Duplicate naming", comment: "Settings UI: section for name collisions."))
            } footer: {
                Text(S.duplicateNamingSectionFooter)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func pickCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose", comment: "Open panel default button.")
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

/// Which media type’s settings are shown when **Applies to** includes more than one type.
private enum PresetMediaSettingsTab: String, CaseIterable, Identifiable, Hashable {
    case image, video, audio, pdf
    var id: String { rawValue }

    var mediaType: MediaType {
        switch self {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        case .pdf: return .pdf
        }
    }

    static let canonicalDisplayOrder: [PresetMediaSettingsTab] = [.image, .video, .audio, .pdf]

    static func tab(for media: MediaType) -> PresetMediaSettingsTab {
        switch media {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        case .pdf: return .pdf
        }
    }
}

private struct PresetsTab: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @State private var selectedID: UUID? = nil
    @State private var presetMediaSettingsTab: PresetMediaSettingsTab = .image

    private var selectedPreset: CompressionPreset? {
        prefs.savedPresets.first { $0.id == selectedID }
    }

    private func liveSnapshot(_ snapshot: CompressionPreset) -> CompressionPreset {
        prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
    }

    @ViewBuilder
    private func presetOverrideBadgeIfNeeded(_ differs: Bool) -> some View {
        if differs {
            Text(String(localized: "Overrides default", comment: "Settings UI: preset differs from global preference."))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.08)))
        }
    }

    @ViewBuilder
    private func presetUseDefaultLink(_ action: @escaping () -> Void) -> some View {
        Button(String(localized: "Use Settings default", comment: "Settings UI: apply global preference to preset.")) {
            action()
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .font(.caption)
        .foregroundStyle(Color.accentColor)
    }

    /// One-line summary so presets are distinguishable in the list without expanding.
    private func presetListSecondaryLine(_ preset: CompressionPreset) -> String {
        let included = preset.includedMediaTypes
        let all = PresetMediaScopeRawCodec.allTypes
        var parts: [String] = [preset.includedMediaTypesSummaryLabel]
        let imageFmt = preset.autoFormat
            ? String(localized: "Auto", comment: "Preset list: automatic image format.")
            : preset.format.displayName
        let vid = (VideoCodecFamily(rawValue: preset.videoCodecFamilyRaw) ?? .h264).chipLabel

        if included == all {
            parts.append(contentsOf: allMediaTypesPresetSummaryFragments(preset, imageFmt: imageFmt, vid: vid))
        } else {
            let order: [MediaType] = [.image, .video, .audio, .pdf]
            for m in order where included.contains(m) {
                parts.append(contentsOf: singleMediaSummaryFragments(media: m, preset: preset, imageFmt: imageFmt, vid: vid))
            }
        }
        return parts.joined(separator: " · ")
    }

    private func allMediaTypesPresetSummaryFragments(_ preset: CompressionPreset, imageFmt: String, vid: String) -> [String] {
        var parts: [String] = [imageFmt, vid]
        let af = AudioConversionFormat(rawValue: preset.audioFormatRaw) ?? .aacM4A
        parts.append(af.displayName)
        let pdfMode = PDFOutputMode(rawValue: preset.pdfOutputModeRaw) ?? .flattenPages
        if pdfMode == .flattenPages {
            let q = PDFQuality(rawValue: preset.pdfQualityRaw) ?? .medium
            parts.append(String(localized: "PDF \(q.displayName)", comment: "Preset list: flattened PDF quality tier."))
        } else {
            parts.append(String(localized: "PDF preserve", comment: "Preset list: PDF preserve structure."))
        }
        if preset.pdfEnableOCR {
            parts.append(String(localized: "OCR", comment: "Preset list: PDF OCR enabled."))
        }
        return parts
    }

    private func singleMediaSummaryFragments(media: MediaType, preset: CompressionPreset, imageFmt: String, vid: String) -> [String] {
        switch media {
        case .image:
            var parts: [String] = [imageFmt]
            if preset.maxWidthEnabled {
                parts.append(String(localized: "max \(preset.maxWidth) px", comment: "Preset list: max width pixels."))
            }
            if preset.maxFileSizeEnabled {
                let mb = Double(preset.maxFileSizeKB) / 1024.0
                let mbStr = mb < 1 ? String(format: "%.1f", mb) : String(format: "%.4g", mb)
                parts.append(String(localized: "≤\(mbStr) MB", comment: "Preset list: target file size cap."))
            }
            return parts
        case .video:
            var parts: [String] = [vid]
            if preset.videoMaxResolutionEnabled {
                parts.append("\(preset.videoMaxResolutionLines)p")
            } else {
                parts.append(String(localized: "full res", comment: "Preset list: video no resolution cap."))
            }
            if preset.videoMaxFPSEnabled {
                parts.append(
                    String.localizedStringWithFormat(
                        String(localized: "max %lld fps", comment: "Preset list: video FPS cap."),
                        Int64(VideoFPSCapPreset.normalizeStored(preset.videoMaxFPS))
                    )
                )
            }
            if preset.videoRemoveAudio {
                parts.append(String(localized: "no audio", comment: "Preset list: audio stripped."))
            }
            return parts
        case .audio:
            let af = AudioConversionFormat(rawValue: preset.audioFormatRaw) ?? .aacM4A
            let tier = AudioConversionQualityTier.resolve(preset.audioQualityTierRaw)
            return [af.displayName, tier.displayName]
        case .pdf:
            var parts: [String] = []
            let pdfMode = PDFOutputMode(rawValue: preset.pdfOutputModeRaw) ?? .flattenPages
            if pdfMode == .flattenPages {
                let q = PDFQuality(rawValue: preset.pdfQualityRaw) ?? .medium
                parts.append(String(localized: "Flatten \(q.displayName)", comment: "Preset list: PDF flatten + quality."))
                if preset.pdfGrayscale {
                    parts.append(String(localized: "grayscale", comment: "Preset list: PDF grayscale."))
                }
            } else {
                parts.append(String(localized: "Preserve", comment: "Preset list: PDF preserve links."))
            }
            if preset.pdfEnableOCR {
                parts.append(String(localized: "OCR", comment: "Preset list: PDF OCR enabled."))
            }
            return parts
        }
    }

    var body: some View {
        Form {
            presetChooserSection

            if let preset = selectedPreset {
                presetDetailSections(preset)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.15), value: selectedID)
        .animation(.easeInOut(duration: 0.15), value: presetMediaSettingsTab)
        .animation(.easeInOut(duration: 0.15), value: selectedPreset?.presetMediaScopeRaw)
        .onAppear {
            consumePendingPresetUUIDIfNeeded()
            if selectedID == nil { selectedID = prefs.savedPresets.first?.id }
        }
        .onChange(of: selectedID) { _, newID in
            guard let id = newID,
                  let p = prefs.savedPresets.first(where: { $0.id == id }) else { return }
            syncMediaTabToIncluded(p.includedMediaTypes)
        }
        .onChange(of: selectedPreset?.presetMediaScopeRaw) { _, raw in
            guard let raw else { return }
            clampPresetMediaSettingsTab(included: PresetMediaScopeRawCodec.includedTypes(from: raw))
        }
        .onChange(of: prefs.savedPresets.map(\.id)) { _, _ in
            if let id = selectedID, !prefs.savedPresets.contains(where: { $0.id == id }) {
                selectedID = prefs.savedPresets.first?.id
            } else if selectedID == nil {
                selectedID = prefs.savedPresets.first?.id
            }
        }
    }

    @ViewBuilder
    private var presetChooserSection: some View {
        Section {
            if prefs.savedPresets.isEmpty {
                VStack(alignment: .center, spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "No presets yet", comment: "Settings UI: presets empty state title."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Create one to save your favorite combinations of format and quality settings.", comment: "Settings UI: presets empty state hint."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            } else {
                Picker(selection: Binding(
                    get: { selectedID ?? prefs.savedPresets.first?.id ?? UUID() },
                    set: { selectedID = $0 }
                )) {
                    ForEach(prefs.savedPresets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                } label: {
                    Text(String(localized: "Editing", comment: "Settings UI: which preset is being edited."))
                }
                if let preset = selectedPreset {
                    Text(presetListSecondaryLine(preset))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 8) {
                Button {
                    addPreset()
                } label: {
                    Label(String(localized: "New Preset", comment: "Settings UI: create a new preset."),
                          systemImage: "plus")
                }
                Button {
                    duplicateSelected()
                } label: {
                    Label(String(localized: "Duplicate", comment: "Settings UI: duplicate selected preset."),
                          systemImage: "doc.on.doc")
                }
                .disabled(selectedID == nil)
                Spacer()
                Button(role: .destructive) {
                    deleteSelected()
                } label: {
                    Label(String(localized: "Delete", comment: "Settings UI: delete selected preset."),
                          systemImage: "trash")
                }
                .disabled(selectedID == nil)
            }
        } header: {
            Text(String(localized: "Presets", comment: "Settings UI."))
        }
    }

    private func consumePendingPresetUUIDIfNeeded() {
        guard let idStr = UserDefaults.standard.string(forKey: PreferencesTab.pendingPresetUUIDKey),
              let u = UUID(uuidString: idStr) else { return }
        UserDefaults.standard.removeObject(forKey: PreferencesTab.pendingPresetUUIDKey)
        if prefs.savedPresets.contains(where: { $0.id == u }) {
            selectedID = u
        }
    }

    private func syncMediaTabToIncluded(_ included: Set<MediaType>) {
        if included.count == 1, let only = included.first {
            presetMediaSettingsTab = PresetMediaSettingsTab.tab(for: only)
            return
        }
        clampPresetMediaSettingsTab(included: included)
    }

    private func clampPresetMediaSettingsTab(included: Set<MediaType>) {
        if included.contains(presetMediaSettingsTab.mediaType) { return }
        presetMediaSettingsTab = PresetMediaSettingsTab.canonicalDisplayOrder.first { included.contains($0.mediaType) } ?? .image
    }

    private func includedMediaTypes(for snapshot: CompressionPreset) -> Set<MediaType> {
        let live = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
        return live.includedMediaTypes
    }

    private func mediaSettingsTabsShown(for snapshot: CompressionPreset) -> [PresetMediaSettingsTab] {
        let inc = includedMediaTypes(for: snapshot)
        return PresetMediaSettingsTab.canonicalDisplayOrder.filter { inc.contains($0.mediaType) }
    }

    private func effectiveMediaTab(for snapshot: CompressionPreset) -> PresetMediaSettingsTab {
        let inc = includedMediaTypes(for: snapshot)
        if inc.count == 1, let only = inc.first {
            return PresetMediaSettingsTab.tab(for: only)
        }
        if inc.contains(presetMediaSettingsTab.mediaType) {
            return presetMediaSettingsTab
        }
        return PresetMediaSettingsTab.canonicalDisplayOrder.first { inc.contains($0.mediaType) } ?? .image
    }

    private func presetAppliesToBinding(_ type: MediaType, snapshot: CompressionPreset) -> Binding<Bool> {
        Binding(
            get: { includedMediaTypes(for: snapshot).contains(type) },
            set: { newValue in
                var types = includedMediaTypes(for: snapshot)
                if newValue {
                    types.insert(type)
                } else {
                    if types.count <= 1, types.contains(type) { return }
                    types.remove(type)
                }
                self.set(\.presetMediaScopeRaw, to: PresetMediaScopeRawCodec.serialize(types), for: snapshot)
                clampPresetMediaSettingsTab(included: types)
            }
        )
    }

    @ViewBuilder
    private func presetAppliesToMultiSelectRow(snapshot: CompressionPreset) -> some View {
        let live = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
        LabeledContent(String(localized: "Applies to", comment: "Settings UI.")) {
            Menu {
                ForEach([MediaType.image, .video, .audio, .pdf], id: \.self) { type in
                    Toggle(isOn: presetAppliesToBinding(type, snapshot: snapshot)) {
                        Text(type.presetAppliesToSegmentLabel)
                    }
                }
            } label: {
                Text(live.includedMediaTypesSummaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHint(String(localized: "Shows a menu to choose which file types use this preset.", comment: "VoiceOver: preset Applies to menu."))
        }
    }


    @ViewBuilder
    private func presetDetailSections(_ snapshot: CompressionPreset) -> some View {
        Section(String(localized: "Name", comment: "Settings UI.")) {
            TextField(String(localized: "Preset name", comment: "Settings UI."), text: binding(\.name, snapshot: snapshot))
        }
        Section(String(localized: "Compression", comment: "Settings UI.")) {
            let liveForQuality = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
            Toggle(String(localized: "Smart quality", comment: "Settings UI."), isOn: binding(\.smartQuality, snapshot: snapshot))
            if !liveForQuality.smartQuality {
                if includedMediaTypes(for: snapshot).count > 1 {
                    Picker(String(localized: "Manual compression", comment: "Settings UI."), selection: $presetMediaSettingsTab) {
                        ForEach(mediaSettingsTabsShown(for: snapshot), id: \.self) { tab in
                            Text(tab.mediaType.presetAppliesToSegmentLabel).tag(tab)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(String(localized: "Manual compression by media type", comment: "VoiceOver label for segmented media picker."))
                }
                switch effectiveMediaTab(for: snapshot) {
                case .image:
                    EmptyView()
                case .video:
                    presetManualCompressionVideoControls(snapshot)
                case .audio:
                    presetManualCompressionAudioControls(snapshot)
                case .pdf:
                    presetManualCompressionPDFControls(snapshot)
                }
            } else {
                Text(String(localized: "Adjusts compression from each file: image encoding from content, video strength from resolution and bitrate, PDF tier from the document.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            presetAppliesToMultiSelectRow(snapshot: snapshot)
            if includedMediaTypes(for: snapshot).count > 1 {
                Picker(String(localized: "Media settings", comment: "Settings UI."), selection: $presetMediaSettingsTab) {
                    ForEach(mediaSettingsTabsShown(for: snapshot), id: \.self) { tab in
                        Text(tab.mediaType.presetAppliesToSegmentLabel).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(String(localized: "Media settings", comment: "VoiceOver label for media segmented control."))
            }
            switch effectiveMediaTab(for: snapshot) {
            case .image:
                presetImageControls(snapshot)
            case .video:
                presetVideoControls(snapshot)
            case .audio:
                presetAudioControls(snapshot)
            case .pdf:
                presetPDFControls(snapshot)
            }
        } header: {
                Text(String(localized: "Media", comment: "Settings UI."))
            } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Watch folders use this preset only for matching file types. Other files use the global sidebar settings.", comment: "Settings UI."))
                    .font(.caption)
                PreferencesRelatedTabLink(title: String(localized: "Global watch folder…", comment: "Settings UI."), tab: .watch)
            }
        }
        Section {
            let liveForDest = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
            Picker(String(localized: "Save to", comment: "Settings UI."), selection: binding(\.saveLocationRaw, snapshot: snapshot)) {
                Text(String(localized: "Same folder as original", comment: "Settings UI.")).tag("sameFolder")
                Text(String(localized: "Downloads folder", comment: "Settings UI.")).tag("downloads")
                if !prefs.customFolderDisplayPath.isEmpty || liveForDest.saveLocationRaw == "custom" {
                    Text(prefs.customFolderDisplayPath.isEmpty
                         ? String(localized: "Global custom folder (not set)", comment: "Settings UI.")
                         : URL(fileURLWithPath: prefs.customFolderDisplayPath).lastPathComponent)
                        .tag("custom")
                }
                Text(String(localized: "Unique folder…", comment: "Settings UI.")).tag("presetCustom")
            }
            if liveForDest.saveLocationRaw == "presetCustom" {
                HStack {
                    Text(liveForDest.presetCustomFolderPath.isEmpty
                         ? String(localized: "No folder selected", comment: "Settings UI.")
                         : URL(fileURLWithPath: liveForDest.presetCustomFolderPath).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(String(localized: "Choose…", comment: "Settings UI.")) { pickPresetCustomFolder(for: snapshot) }
                        .buttonStyle(.bordered)
                }
            }
            Picker(String(localized: "Filename", comment: "Settings UI."), selection: binding(\.filenameHandlingRaw, snapshot: snapshot)) {
                Text(String(localized: "Append \"-dinky\" suffix", comment: "Settings UI.")).tag("appendSuffix")
                Text(String(localized: "Replace original", comment: "Settings UI.")).tag("replaceOrigin")
                Text(String(localized: "Custom suffix", comment: "Settings UI.")).tag("customSuffix")
            }
            if snapshot.filenameHandlingRaw == "customSuffix" {
                HStack {
                    Text(String(localized: "Suffix", comment: "Settings UI.")).foregroundStyle(.secondary)
                    TextField(String(localized: "-dinky", comment: "Settings UI."), text: binding(\.customSuffix, snapshot: snapshot))
                }
            }
        } header: {
            Text(String(localized: "Destination", comment: "Settings UI."))
        } footer: {
            PreferencesRelatedTabLink(title: String(localized: "Default Output settings…", comment: "Settings UI."), tab: .output)
        }
        Section {
            let liveCollision = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
            Picker(S.duplicateNamingPickerAccessibilityLabel, selection: binding(\.collisionNamingStyleRaw, snapshot: snapshot)) {
                ForEach(CollisionNamingStyle.allCases) { style in
                    Text(style.displayName).tag(style.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if CollisionNamingStyle(rawValue: liveCollision.collisionNamingStyleRaw) == .custom {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(S.duplicateNamingCustomFieldLabel)
                            .foregroundStyle(.secondary)
                        TextField(
                            S.duplicateNamingCustomPlaceholder,
                            text: binding(\.collisionCustomPattern, snapshot: snapshot)
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 160)
                        .accessibilityLabel(S.duplicateNamingCustomFieldLabel)
                    }
                    Text(S.duplicateNamingCustomHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(String(localized: "Duplicate naming", comment: "Settings UI: section for name collisions."))
        } footer: {
            Text(S.duplicateNamingSectionFooter)
                .font(.caption)
        }
        Section(String(localized: "Watch Folder", comment: "Settings UI.")) {
            let liveForWatch = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
            Toggle(String(localized: "Watch this folder", comment: "Settings UI."), isOn: binding(\.watchFolderEnabled, snapshot: snapshot))
            if liveForWatch.watchFolderEnabled {
                Picker(String(localized: "Folder", comment: "Settings UI."), selection: binding(\.watchFolderModeRaw, snapshot: snapshot)) {
                    Text(String(localized: "Use global watch", comment: "Settings UI.")).tag("global")
                    Text(String(localized: "Unique folder…", comment: "Settings UI.")).tag("unique")
                }
                if liveForWatch.watchFolderModeRaw == "global" {
                    Text(String(localized: "Uses the folder set in Settings → Watch → Global, with the main window’s current settings. Add a unique folder below only if you want this preset’s options applied automatically somewhere else.", comment: "Settings UI."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PreferencesRelatedTabLink(title: String(localized: "Edit global watch folder…", comment: "Settings UI."), tab: .watch)
                }
                if liveForWatch.watchFolderModeRaw == "unique" {
                    HStack {
                        Text(liveForWatch.watchFolderPath.isEmpty
                             ? String(localized: "No folder selected", comment: "Settings UI.")
                             : URL(fileURLWithPath: liveForWatch.watchFolderPath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "Choose…", comment: "Settings UI.")) { pickWatchFolder(for: snapshot) }
                            .buttonStyle(.bordered)
                    }
                }
                Text(String(localized: "Unique folder: new files are compressed with this preset’s saved options, independent of the sidebar.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section(String(localized: "Advanced", comment: "Settings UI.")) {
            Toggle(String(localized: "Strip metadata", comment: "Settings UI."), isOn: binding(\.stripMetadata, snapshot: snapshot))
            presetOverrideBadgeIfNeeded(liveSnapshot(snapshot).stripMetadata != prefs.stripMetadata)
            if liveSnapshot(snapshot).stripMetadata != prefs.stripMetadata {
                presetUseDefaultLink { set(\.stripMetadata, to: prefs.stripMetadata, for: snapshot) }
            }
            Text(String(localized: "Removes embedded EXIF, GPS, camera info, PDF properties (title, subject, keywords), and color profiles when supported. Does not remove Finder’s Get Info → Comments; use Preserve Finder comments in Settings → Compression for that.", comment: "Settings UI: Strip metadata explanation."))
                    .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(String(localized: "Sanitize filenames", comment: "Settings UI."), isOn: binding(\.sanitizeFilenames, snapshot: snapshot))
            presetOverrideBadgeIfNeeded(liveSnapshot(snapshot).sanitizeFilenames != prefs.sanitizeFilenames)
            if liveSnapshot(snapshot).sanitizeFilenames != prefs.sanitizeFilenames {
                presetUseDefaultLink { set(\.sanitizeFilenames, to: prefs.sanitizeFilenames, for: snapshot) }
            }
            Text(String(localized: "Replaces spaces and special characters to improve cross-platform compatibility.", comment: "Settings UI."))
                    .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(String(localized: "Open folder when done", comment: "Settings UI."), isOn: binding(\.openFolderWhenDone, snapshot: snapshot))
            presetOverrideBadgeIfNeeded(liveSnapshot(snapshot).openFolderWhenDone != prefs.openFolderWhenDone)
            if liveSnapshot(snapshot).openFolderWhenDone != prefs.openFolderWhenDone {
                presetUseDefaultLink { set(\.openFolderWhenDone, to: prefs.openFolderWhenDone, for: snapshot) }
            }
            Text(String(localized: "Opens the output folder in Finder after each compression batch.", comment: "Settings UI."))
                    .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section(String(localized: "Notifications", comment: "Settings UI.")) {
            Toggle(String(localized: "Notify when done", comment: "Settings UI."), isOn: binding(\.notifyWhenDone, snapshot: snapshot))
            presetOverrideBadgeIfNeeded(liveSnapshot(snapshot).notifyWhenDone != prefs.notifyWhenDone)
            if liveSnapshot(snapshot).notifyWhenDone != prefs.notifyWhenDone {
                presetUseDefaultLink { set(\.notifyWhenDone, to: prefs.notifyWhenDone, for: snapshot) }
            }
            Text(String(localized: "Sends a macOS notification when a compression batch finishes.", comment: "Settings UI."))
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
                    options: pdfFlattenChipOptionsForPreset(snapshot),
                    selected: binding(\.pdfQualityRaw, snapshot: snapshot)
                )
                .onAppear { snapPresetPdfFlattenQuality(snapshot) }
            } else {
                Text(String(localized: "Low / Medium / High apply when Smallest file (flatten) is selected under Media.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Manual video controls when Smart quality is off. Codec, resolution cap, and audio live under Media.
    @ViewBuilder
    private func presetManualCompressionVideoControls(_ snapshot: CompressionPreset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Output resolution and codec live under Media.", comment: "Settings UI."))
                    .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func presetImageControls(_ snapshot: CompressionPreset) -> some View {
        let live = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
        VStack(alignment: .leading, spacing: 10) {
            settingsSubHeader(icon: "photo.on.rectangle.angled", String(localized: "Format", comment: "Settings UI: Media image subsection."))
            FormatChipPicker(
                autoFormat: binding(\.autoFormat, snapshot: snapshot),
                selectedFormat: binding(\.format, snapshot: snapshot)
            )

            SettingsSectionDivider()

            settingsSubHeader(icon: "wand.and.stars", String(localized: "Quality", comment: "Settings UI: Media image subsection."))
            if live.smartQuality {
                settingsHelperText(String(localized: "Picks encoder strength per image from content (photo vs. graphic). Turn off Smart quality under Compression to choose Photo, Graphic, or Mixed.", comment: "Settings UI."))
            } else {
                ContentTypeChipPicker(contentTypeHintRaw: binding(\.contentTypeHintRaw, snapshot: snapshot))
            }

            SettingsSectionDivider()

            settingsSubHeader(icon: "arrow.left.and.right", String(localized: "Max width", comment: "Settings UI: Media image subsection."))
            Toggle(String(localized: "Limit width", comment: "Settings UI."), isOn: binding(\.maxWidthEnabled, snapshot: snapshot))
            if live.maxWidthEnabled {
                settingsChipGrid(
                    presets: settingsWidthPresets,
                    current: live.maxWidth,
                    fixedColumnCount: 3
                ) { set(\.maxWidth, to: $0, for: snapshot) }
                HStack(spacing: 6) {
                    TextField("", value: binding(\.maxWidth, snapshot: snapshot), format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 80)
                        .labelsHidden()
                    Text(String(localized: "px", comment: "Unit abbreviation for pixels.")).foregroundStyle(.secondary)
                }
                settingsHelperText(String(localized: "Try 1920 for web, 1280 for social, 640 for email.", comment: "Settings UI."))
            }

            SettingsSectionDivider()

            settingsSubHeader(icon: "gauge.with.dots.needle.67percent", String(localized: "Max file size", comment: "Settings UI: Media image subsection."))
            Toggle(String(localized: "Limit file size", comment: "Settings UI."), isOn: binding(\.maxFileSizeEnabled, snapshot: snapshot))
            if live.maxFileSizeEnabled {
                settingsChipGrid(
                    presets: settingsSizePresets,
                    current: live.maxFileSizeKB
                ) { set(\.maxFileSizeKB, to: $0, for: snapshot) }
                HStack(spacing: 6) {
                    TextField("", value: mbBinding(for: snapshot), format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 80)
                        .labelsHidden()
                    Text(String(localized: "MB", comment: "Unit abbreviation for megabytes.")).foregroundStyle(.secondary)
                }
                settingsHelperText(String(localized: "Encoder aims near this cap; exact size varies by image.", comment: "Settings UI."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func presetPDFControls(_ snapshot: CompressionPreset) -> some View {
        let livePDF = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
        VStack(alignment: .leading, spacing: 10) {
            settingsSubHeader(icon: "doc.text.viewfinder", String(localized: "Output", comment: "Settings UI: Media PDF subsection."))
            Picker(String(localized: "Output", comment: "Settings UI."), selection: binding(\.pdfOutputModeRaw, snapshot: snapshot)) {
                Text(String(localized: "Preserve text (best-effort size)", comment: "Settings UI: PDF output mode.")).tag(PDFOutputMode.preserveStructure.rawValue)
                Text(String(localized: "Smallest file (flatten)", comment: "Settings UI: PDF output mode.")).tag(PDFOutputMode.flattenPages.rawValue)
            }
            .pickerStyle(.segmented)

            SettingsSectionDivider()

            settingsSubHeader(icon: "doc.text.magnifyingglass", String(localized: "Scanned PDFs", comment: "Settings UI: PDF OCR subsection."))
            Toggle(String(localized: "Make scanned PDFs searchable (OCR)", comment: "Settings UI: PDF OCR toggle."), isOn: binding(\.pdfEnableOCR, snapshot: snapshot))
                .font(.system(size: 12))
            settingsHelperText(String(localized: "When a document looks like a scan, Dinky adds a text layer first, then compresses. Born-digital PDFs skip this step.", comment: "Settings UI: PDF OCR helper."))
            if livePDF.pdfEnableOCR {
                Picker(String(localized: "OCR languages", comment: "Settings UI: PDF OCR language picker accessibility."), selection: pdfOCRPrimaryLanguageBinding(for: snapshot)) {
                    Text("English (US)").tag("en-US")
                    Text("English (UK)").tag("en-GB")
                    Text("Français").tag("fr-FR")
                    Text("Deutsch").tag("de-DE")
                    Text("Español").tag("es-ES")
                    Text("Italiano").tag("it-IT")
                    Text("Português (Brasil)").tag("pt-BR")
                    Text("日本語").tag("ja-JP")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                settingsHelperText(String(localized: "Recognition uses Apple’s on-device Vision engine; pick the closest language to your documents.", comment: "Settings UI: OCR language helper."))
            }

            if PDFOutputMode(rawValue: livePDF.pdfOutputModeRaw) == .preserveStructure {
                settingsHelperText(String(localized: "qpdf + PDFKit; keeps structure only when the result is smaller. Many PDFs won’t shrink. Low / Medium / High and grayscale apply when Smallest file (flatten) is selected.", comment: "Settings UI: PDF preserve expectations."))

                SettingsSectionDivider()

                settingsSubHeader(icon: "flask", String(localized: "Advanced (experimental)", comment: "Settings UI: PDF experimental preserve."))
                Picker(String(localized: "Experimental preserve pass", comment: "Settings UI: PDF experimental picker accessibility."), selection: binding(\.pdfPreserveExperimentalRaw, snapshot: snapshot)) {
                    ForEach(PDFPreserveExperimentalMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                settingsHelperText(String(localized: "Optional extra qpdf steps for this preset when preserve finds little gain. May affect tags or image quality; leave Off unless you need it.", comment: "Settings UI: PDF experimental preserve helper."))

                SettingsSectionDivider()

                settingsSubHeader(icon: "arrow.down.left.and.arrow.up.right", String(localized: "Image resolution", comment: "Settings UI: PDF image downsampling."))
                Toggle(String(localized: "Downsample embedded images", comment: "Settings UI: PDF downsampling toggle."), isOn: binding(\.pdfResolutionDownsampling, snapshot: snapshot))
                settingsHelperText(String(localized: "Rasterizes image-heavy pages at 144 DPI while keeping text pages selectable. Best for 300/600 DPI scans; no effect on vector or text-only PDFs.", comment: "Settings UI: PDF downsampling helper."))
            }

            if PDFOutputMode(rawValue: livePDF.pdfOutputModeRaw) == .flattenPages {
                SettingsSectionDivider()

                settingsSubHeader(icon: "circle.lefthalf.filled", String(localized: "Color", comment: "Settings UI: Media PDF subsection."))
                Toggle(String(localized: "Grayscale PDF", comment: "Settings UI."), isOn: binding(\.pdfGrayscale, snapshot: snapshot))
                if livePDF.pdfGrayscale {
                    settingsHelperText(String(localized: "Smaller files when color isn’t needed.", comment: "Settings UI."))
                }
                Toggle(String(localized: "Auto-grayscale monochrome scans", comment: "Settings UI: PDF Smart Quality."), isOn: binding(\.pdfAutoGrayscaleMonoScans, snapshot: snapshot))
                if livePDF.smartQuality, livePDF.pdfAutoGrayscaleMonoScans {
                    settingsHelperText(String(localized: "When Smart quality is on, flatten may use grayscale for PDFs that look like black-and-white office scans, even if Grayscale PDF is off.", comment: "Settings UI: PDF auto mono helper."))
                }

                SettingsSectionDivider()

                settingsSubHeader(icon: "gauge.with.dots.needle.67percent", String(localized: "Max file size", comment: "Settings UI: Media PDF subsection."))
                Toggle(String(localized: "Target a smaller file size", comment: "Settings UI: PDF max file size toggle."), isOn: binding(\.pdfMaxFileSizeEnabled, snapshot: snapshot))
                if livePDF.pdfMaxFileSizeEnabled {
                    settingsChipGrid(
                        presets: settingsPDFMaxFileSizePresets,
                        current: livePDF.pdfMaxFileSizeKB,
                        fixedColumnCount: 4
                    ) { set(\.pdfMaxFileSizeKB, to: $0, for: snapshot) }
                    HStack(spacing: 6) {
                        TextField("", value: pdfMbBinding(for: snapshot), format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                            .labelsHidden()
                        Text(String(localized: "MB", comment: "Unit abbreviation for megabytes.")).foregroundStyle(.secondary)
                    }
                    settingsHelperText(String(localized: "Steps down quality tiers until under the target. Exact size varies by content.", comment: "Settings UI: PDF max file size helper."))
                }

                SettingsSectionDivider()

                settingsSubHeader(icon: "doc.richtext", String(localized: "Quality", comment: "Settings UI: Media PDF subsection."))
                QualityChipPicker(
                    options: pdfFlattenChipOptionsForPreset(snapshot),
                    selected: binding(\.pdfQualityRaw, snapshot: snapshot)
                )
                if livePDF.smartQuality {
                    settingsHelperText(String(localized: "Manual tier is the fallback when smart analysis can’t run.", comment: "Settings UI: PDF smart flatten helper."))
                }
                if livePDF.pdfMaxFileSizeEnabled,
                   PDFQuality.flattenUIShowableTiers(maxFileSizeEnabled: true, pdfMaxFileSizeKB: livePDF.pdfMaxFileSizeKB).count < PDFQuality.allCases.count {
                    settingsHelperText(String(localized: "Tighter max-size targets only list lower starting tiers; Dinky still steps down through the chain if needed.", comment: "Settings UI: PDF max size limits tier chips helper."))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { snapPresetPdfFlattenQuality(snapshot) }
        .onChange(of: livePDF.pdfOutputModeRaw) { _, _ in snapPresetPdfFlattenQuality(snapshot) }
        .onChange(of: livePDF.pdfMaxFileSizeEnabled) { _, _ in snapPresetPdfFlattenQuality(snapshot) }
        .onChange(of: livePDF.pdfMaxFileSizeKB) { _, _ in snapPresetPdfFlattenQuality(snapshot) }
    }

    @ViewBuilder
    private func presetVideoControls(_ snapshot: CompressionPreset) -> some View {
        let liveVideo = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
        VStack(alignment: .leading, spacing: 10) {
            settingsSubHeader(icon: "film", String(localized: "Format", comment: "Settings UI: Media video codec."))
            QualityChipPicker(
                options: VideoCodecFamily.allCases.map { ($0.chipLabel, $0.rawValue, $0.description) },
                selected: binding(\.videoCodecFamilyRaw, snapshot: snapshot)
            )

            SettingsSectionDivider()

            settingsSubHeader(icon: "wand.and.stars", String(localized: "Quality", comment: "Settings UI: Media video subsection."))
            if liveVideo.smartQuality {
                settingsHelperText(String(localized: "Picks encoder strength per clip from resolution and bitrate. Turn off Smart quality under Compression for a fixed tier.", comment: "Settings UI."))
            } else {
                QualityChipPicker(
                    options: VideoQuality.allCases.map { ($0.displayName, $0.rawValue, $0.description) },
                    selected: binding(\.videoQualityRaw, snapshot: snapshot)
                )
            }

            SettingsSectionDivider()

            settingsSubHeader(icon: "arrow.down.right.and.arrow.up.left", String(localized: "Output size", comment: "Sidebar Video: category for resolution + FPS."))
            settingsControlLabel(String(localized: "Max resolution", comment: "Sidebar Video: max resolution control label."))
            Toggle(String(localized: "Cap output resolution", comment: "Settings UI."), isOn: binding(\.videoMaxResolutionEnabled, snapshot: snapshot))
            if liveVideo.videoMaxResolutionEnabled {
                settingsChipGrid(
                    presets: settingsVideoResolutionPresets,
                    current: liveVideo.videoMaxResolutionLines,
                    fixedColumnCount: 4
                ) { set(\.videoMaxResolutionLines, to: $0, for: snapshot) }
                settingsHelperText(String(localized: "Source resolution is kept when below the cap. Smart quality below ignores this.", comment: "Settings UI."))
            } else {
                settingsHelperText(String(localized: "Off keeps source resolution and just re-encodes for size.", comment: "Settings UI."))
            }

            settingsControlLabel(String(localized: "Frame rate", comment: "Sidebar Video: FPS control label."))
            Toggle(String(localized: "Cap frame rate", comment: "Settings UI: video FPS cap toggle."), isOn: binding(\.videoMaxFPSEnabled, snapshot: snapshot))
            if liveVideo.videoMaxFPSEnabled {
                settingsChipGrid(
                    presets: settingsVideoFPSCapPresets,
                    current: VideoFPSCapPreset.normalizeStored(liveVideo.videoMaxFPS),
                    fixedColumnCount: 4
                ) { set(\.videoMaxFPS, to: $0, for: snapshot) }
                settingsHelperText(String(localized: "Lowers output FPS when the source runs faster than the cap (great for screen recordings). Source timing is unchanged when it is already at or below this rate.", comment: "Settings UI: video FPS cap helper."))
            } else {
                settingsHelperText(String(localized: "Off keeps the source frame rate.", comment: "Settings UI: FPS cap off."))
            }

            SettingsSectionDivider()

            settingsSubHeader(icon: "speaker.wave.2", String(localized: "Audio", comment: "Settings UI: Media video subsection."))
            Toggle(String(localized: "Strip audio track", comment: "Settings UI."), isOn: binding(\.videoRemoveAudio, snapshot: snapshot))
            if liveVideo.videoRemoveAudio {
                settingsHelperText(String(localized: "Best for screen recordings or silent clips.", comment: "Settings UI."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func presetAudioControls(_ snapshot: CompressionPreset) -> some View {
        let liveAudio = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
        VStack(alignment: .leading, spacing: 10) {
            settingsSubHeader(icon: "waveform", String(localized: "Format", comment: "Settings UI: audio output."))
            AudioFormatChipPicker(audioFormatRaw: binding(\.audioFormatRaw, snapshot: snapshot))
            if (AudioConversionFormat(rawValue: liveAudio.audioFormatRaw) ?? .aacM4A) == .mp3 {
                settingsHelperText(String(localized: "MP3 encoding uses the bundled LAME encoder (LGPL). WAV/AIFF/AAC/M4A/FLAC use macOS audio tools.", comment: "Settings UI: audio mp3 legal note."))
            }
            SettingsSectionDivider()
            settingsSubHeader(icon: "wand.and.stars", String(localized: "Quality", comment: "Settings UI: audio tier."))
            if liveAudio.smartQuality {
                settingsHelperText(String(localized: "Picks encoding strength from the track. Turn off Smart quality under Compression for a fixed tier.", comment: "Settings UI."))
            } else {
                QualityChipPicker(
                    options: AudioConversionQualityTier.allCases.map { ($0.displayName, $0.rawValue, "") },
                    selected: binding(\.audioQualityTierRaw, snapshot: snapshot)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presetManualCompressionAudioControls(_ snapshot: CompressionPreset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            presetAudioControls(snapshot)
        }
    }

    private func addPreset() {
        let count = prefs.savedPresets.count + 1
        let preset = CompressionPreset(name: String(localized: "Preset \(count)", comment: "Default name for new preset; argument is number."), from: prefs, format: .webp)
        var list = prefs.savedPresets
        list.append(preset)
        prefs.savedPresets = list
        withAnimation { selectedID = preset.id }
    }

    private func duplicateSelected() {
        guard let id = selectedID,
              let source = prefs.savedPresets.first(where: { $0.id == id }) else { return }
        let existingNames = Set(prefs.savedPresets.map(\.name))
        let newName = CompressionPreset.uniqueDuplicatePresetName(baseName: source.name, existingNames: existingNames)
        let copy = CompressionPreset(duplicating: source, name: newName)
        var list = prefs.savedPresets
        list.append(copy)
        prefs.savedPresets = list
        withAnimation { selectedID = copy.id }
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
        panel.prompt = String(localized: "Watch", comment: "Open panel: choose folder to watch.")
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
        panel.prompt = String(localized: "Choose", comment: "Open panel default button.")
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

    private func pdfFlattenChipOptionsForPreset(_ snapshot: CompressionPreset) -> [(String, String, String)] {
        let live = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
        let tiers = PDFQuality.flattenUIShowableTiers(
            maxFileSizeEnabled: live.pdfMaxFileSizeEnabled,
            pdfMaxFileSizeKB: live.pdfMaxFileSizeKB
        )
        return tiers.map { ($0.displayName, $0.rawValue, $0.description) }
    }

    private func snapPresetPdfFlattenQuality(_ snapshot: CompressionPreset) {
        let live = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
        guard PDFOutputMode(rawValue: live.pdfOutputModeRaw) == .flattenPages else { return }
        let allowed = PDFQuality.flattenUIShowableTiers(
            maxFileSizeEnabled: live.pdfMaxFileSizeEnabled,
            pdfMaxFileSizeKB: live.pdfMaxFileSizeKB
        )
        let current = PDFQuality(rawValue: live.pdfQualityRaw) ?? .medium
        let snapped = PDFQuality.snapFlattenStartTier(current, allowed: allowed)
        if snapped != current { set(\.pdfQualityRaw, to: snapped.rawValue, for: snapshot) }
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

    private func pdfMbBinding(for snapshot: CompressionPreset) -> Binding<Double> {
        Binding(
            get: {
                let live = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
                return Double(live.pdfMaxFileSizeKB) / 1024.0
            },
            set: { set(\.pdfMaxFileSizeKB, to: clampPDFMaxFileSizeKB(Int($0 * 1024)), for: snapshot) }
        )
    }

    /// Single primary Vision locale tag; stored as a one-element `pdfOCRLanguages` array.
    private func pdfOCRPrimaryLanguageBinding(for snapshot: CompressionPreset) -> Binding<String> {
        Binding(
            get: {
                let live = prefs.savedPresets.first(where: { $0.id == snapshot.id }) ?? snapshot
                return live.pdfOCRLanguages.first ?? "en-US"
            },
            set: { set(\.pdfOCRLanguages, to: [$0], for: snapshot) }
        )
    }

}

// MARK: - Watch Folders

private struct WatchFoldersTab: View {
    @EnvironmentObject var prefs: DinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Watch a folder", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.folderWatchEnabled },
                    set: { prefs.folderWatchEnabled = $0 }
                ))
                if prefs.folderWatchEnabled {
                    HStack {
                        Text(prefs.watchedFolderPath.isEmpty
                             ? String(localized: "No folder selected", comment: "Settings UI.")
                             : URL(fileURLWithPath: prefs.watchedFolderPath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "Choose…", comment: "Settings UI.")) { pickGlobalWatchFolder() }
                            .buttonStyle(.bordered)
                    }
                    Text(String(localized: "The global folder uses whatever settings are in the main window (sidebar). Presets can add separate watched folders in their own settings.", comment: "Settings UI."))
                    .font(.caption)
                        .foregroundStyle(.secondary)

                    PreferencesRelatedTabLink(title: String(localized: "Sidebar sections…", comment: "Settings UI: link to sidebar pane."), tab: .sidebar)
                }
            } header: {
                Text(String(localized: "Global", comment: "Settings UI."))
            }

            Section {
                if prefs.savedPresets.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "No presets yet. Create one to watch a folder with saved compression options.", comment: "Settings UI."))
                    .foregroundStyle(.secondary)
                        PreferencesRelatedTabLink(title: String(localized: "Open Presets…", comment: "Settings UI."), tab: .presets)
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
                Text(String(localized: "Presets", comment: "Settings UI."))
            }
        }
        .formStyle(.grouped)
    }

    private func pickGlobalWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Watch", comment: "Open panel: choose folder to watch.")
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
                ? String(localized: "No folder set — configure in Presets", comment: "Watch row hint.")
                : URL(fileURLWithPath: live.watchFolderPath).lastPathComponent
        }
        if !prefs.watchedFolderPath.isEmpty {
            let folder = URL(fileURLWithPath: prefs.watchedFolderPath).lastPathComponent
            return String(localized: "Global (\(folder))", comment: "Watch row: uses global folder; argument is folder name.")
        }
        return String(localized: "Global watch — choose folder in Watch tab", comment: "Watch row hint.")
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
    @EnvironmentObject private var prefs: DinkyPreferences
    @State private var shortcutErrors: [ShortcutAction: String] = [:]
    @State private var recordingAction: ShortcutAction?

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    shortcutRow(for: action)
                }
                HStack {
                    Spacer()
                    Button(S.shortcutsResetAll) {
                        prefs.resetAllShortcuts()
                        shortcutErrors = [:]
                        recordingAction = nil
                    }
                    .disabled(ShortcutAction.allCases.allSatisfy { prefs.isDefaultShortcut($0) })
                }
            } header: {
                Text(S.shortcutsCustomizableHeader)
            } footer: {
                Text(S.shortcutsTabServicesFooter)
                    .font(.caption)
            }

            Section {
                ForEach(S.fixedMenuShortcutReference) { row in
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
                Text(S.shortcutsFixedHeader)
            }

            Section {
                Text(S.shortcutsAppDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Shortcuts app", comment: "Settings UI."))
            }

            Section {
                Text(S.shortcutsTabHelpFooter(helpMenuShortcut: DinkyFixedShortcut.dinkyHelp.shortcut.displayString))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "More help", comment: "Settings UI."))
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func shortcutRow(for action: ShortcutAction) -> some View {
        let s = prefs.shortcut(for: action)
        let sysWarn = ShortcutValidator.systemWarning(for: s)
        let isRecording = recordingAction == action
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(action.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    ShortcutRecorderField(
                        prefs: prefs,
                        action: action,
                        isRecording: recordingBinding(for: action),
                        inlineError: errorBinding(for: action)
                    )
                    .frame(minWidth: 128, maxWidth: 160)
                    if let w = sysWarn, !isRecording {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help("\(S.shortcutsSystemWarningPrefix) \(w)")
                            .accessibilityLabel("\(S.shortcutsSystemWarningPrefix) \(w)")
                    }
                    if isRecording {
                        Button(S.shortcutsCancelEdit) {
                            recordingAction = nil
                            shortcutErrors.removeValue(forKey: action)
                        }
                        .fixedSize()
                    } else {
                        Button(S.shortcutsEdit) {
                            shortcutErrors.removeValue(forKey: action)
                            recordingAction = action
                        }
                        .fixedSize()
                        if !prefs.isDefaultShortcut(action) {
                            Button(S.shortcutsResetRow) {
                                prefs.resetShortcut(action)
                                shortcutErrors.removeValue(forKey: action)
                            }
                            .fixedSize()
                        }
                    }
                }
            }
            if isRecording {
                Text(S.shortcutsRecorderHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let err = shortcutErrors[action] {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: action, shortcut: s, systemWarn: sysWarn, isRecording: isRecording))
    }

    private func accessibilityLabel(for action: ShortcutAction, shortcut: CustomShortcut, systemWarn: String?, isRecording: Bool) -> String {
        var parts = "\(action.title), \(shortcut.displayString)"
        if isRecording { parts += ", recording — \(S.shortcutsRecorderHint)" }
        if let w = systemWarn, !isRecording { parts += ", \(S.shortcutsSystemWarningPrefix) \(w)" }
        if let e = shortcutErrors[action] { parts += ", \(e)" }
        return parts
    }

    private func recordingBinding(for action: ShortcutAction) -> Binding<Bool> {
        Binding(
            get: { recordingAction == action },
            set: { newValue in
                if newValue {
                    if recordingAction != action {
                        if let prev = recordingAction {
                            shortcutErrors.removeValue(forKey: prev)
                        }
                        recordingAction = action
                    }
                } else if recordingAction == action {
                    recordingAction = nil
                }
            }
        )
    }

    private func errorBinding(for action: ShortcutAction) -> Binding<String?> {
        Binding(
            get: { shortcutErrors[action] },
            set: { newVal in
                if let newVal {
                    shortcutErrors[action] = newVal
                } else {
                    shortcutErrors.removeValue(forKey: action)
                }
            }
        )
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
