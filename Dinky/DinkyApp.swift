import SwiftUI
import AppKit

/// Shares one `DinkyPreferences` instance between `ContentViewModel` and the environment.
@MainActor
private final class DinkyRootModel: ObservableObject {
    let prefs: DinkyPreferences
    let contentVM: ContentViewModel

    init() {
        let p = DinkyPreferences()
        self.prefs = p
        self.contentVM = ContentViewModel(prefs: p)
    }
}

@main
struct DinkyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var root = DinkyRootModel()
    @StateObject private var updater = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView(prefs: root.prefs, vm: root.contentVM)
                .environmentObject(root.prefs)
                .environmentObject(updater)
                // Two-part guard against SwiftUI spawning extra windows for each file URL:
                // The scene-level modifier (matching: []) prevents new scenes from being created;
                // preferring: ["*"] makes this window actively claim all incoming external events.
                .handlesExternalEvents(preferring: Set(["*"]), allowing: Set(["*"]))
                .background(.ultraThinMaterial)        // frosted glass fill
                .background(TransparentWindow())       // makes NSWindow itself see-through
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        }
        .handlesExternalEvents(matching: Set<String>())
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 440, height: 440)
        .defaultWindowPlacement { _, context in
            let display = context.defaultDisplay
            let center  = CGPoint(x: display.visibleRect.midX, y: display.visibleRect.midY)
            return WindowPlacement(center)
        }
        .commands {
            CommandGroup(after: .newItem) {
                DinkyShortcutCommands(prefs: root.prefs)
            }
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "About Dinky", comment: "Application menu: about panel.")) {
                    showAboutPanel()
                }
            }
            CommandGroup(after: .appInfo) {
                Button(String(localized: "Check for Updates…", comment: "Application menu: check for updates.")) {
                    NotificationCenter.default.post(name: .dinkyCheckUpdates, object: nil)
                }
                Button(String(localized: "History…", comment: "Application menu: open compression history.")) {
                    NotificationCenter.default.post(name: .dinkyShowHistory, object: nil)
                }
                LastBatchSummaryCommands(vm: root.contentVM)
            }
            // Replace the default Help menu (which triggers the unhelpful
            // "Help isn't available for Dinky" alert because we don't ship
            // a `.help` bundle — adding one would add weight, see CLAUDE.md).
            CommandGroup(replacing: .help) {
                HelpMenuCommands(updater: updater)
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(root.prefs)
                .environmentObject(updater)
        }

        // Opened via the Help menu. Single-instance; reuses the same
        // window if it's already on screen.
        Window("Dinky Help", id: "help") {
            HelpWindow()
                .environmentObject(root.prefs)
        }
        .defaultSize(width: 820, height: 600)
        .commandsRemoved()
    }
}

// MARK: - Last batch summary (fixed shortcut)

private struct LastBatchSummaryCommands: View {
    @ObservedObject var vm: ContentViewModel

    var body: some View {
        Button(String(localized: "Last Batch Summary…", comment: "Application menu: reopen the last batch completion dialog.")) {
            NotificationCenter.default.post(name: .dinkyShowLastBatchSummary, object: nil)
        }
        .disabled(vm.lastBatchSummary == nil)
        .keyboardShortcut(DinkyFixedShortcut.showLastBatchSummary.shortcut.swiftUIKeyboardShortcut)
    }
}

// MARK: - File menu shortcuts (user-customizable)

private struct DinkyShortcutCommands: View {
    @ObservedObject var prefs: DinkyPreferences

    var body: some View {
        Button(String(localized: "Open Files…", comment: "File menu: open file picker.")) {
            NotificationCenter.default.post(name: .dinkyOpenPanel, object: nil)
        }
        .keyboardShortcut(prefs.shortcut(for: .openFiles).swiftUIKeyboardShortcut)

        Button(String(localized: "Clipboard Compress", comment: "File menu: compress from clipboard.")) {
            NSApp.sendAction(Selector(("compressFromClipboard:")), to: nil, from: nil)
        }
        .keyboardShortcut(prefs.shortcut(for: .pasteClipboard).swiftUIKeyboardShortcut)

        Divider()

        Button(String(localized: "Compress Now", comment: "File menu: run compression.")) {
            NotificationCenter.default.post(name: .dinkyStartCompression, object: nil)
        }
        .keyboardShortcut(prefs.shortcut(for: .compressNow).swiftUIKeyboardShortcut)

        Button(String(localized: "Clear All", comment: "File menu: clear file list.")) {
            NotificationCenter.default.post(name: .dinkyClearAll, object: nil)
        }
        .keyboardShortcut(prefs.shortcut(for: .clearAll).swiftUIKeyboardShortcut)

        Button(String(localized: "Format & Options Sidebar", comment: "File menu: toggle compression sidebar.")) {
            NotificationCenter.default.post(name: .dinkyToggleSidebar, object: nil)
        }
        .keyboardShortcut("\\", modifiers: [.command, .shift])

        Button(String(localized: "Delete Selected", comment: "File menu: delete selected rows.")) {
            NotificationCenter.default.post(name: .dinkyDeleteSelectedRows, object: nil)
        }
        .keyboardShortcut(prefs.shortcut(for: .deleteSelected).swiftUIKeyboardShortcut)
    }
}

// MARK: - Help menu

/// Wrapped in its own view so we can pull `openWindow` out of the environment
/// (CommandGroup closures don't expose environment directly). `updater` is
/// passed in explicitly because environment objects don't reliably propagate
/// into command builders across all macOS versions.
private struct HelpMenuCommands: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var updater: UpdateChecker

    private static let repoURL = URL(string: "https://github.com/heyderekj/dinky")!
    private static let siteURL = URL(string: "https://dinkyfiles.com")!
    private static let leaveReviewURL = URL(string: "https://github.com/heyderekj/dinky/discussions/new?category=reviews")!

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Release notes for whichever version is more interesting: the available
    /// update if one's been found, otherwise the version the user is on.
    private var releaseNotesURL: URL {
        if let url = updater.releaseURL { return url }
        return URL(string: "https://github.com/heyderekj/dinky/releases/tag/v\(currentVersion)")!
    }

    private var versionLabel: String {
        if let newer = updater.availableVersion {
            return String(localized: "Version \(currentVersion) — \(newer) available", comment: "Help menu: version row when an update is available. First argument is current version, second is available version.")
        }
        return String(localized: "Version \(currentVersion)", comment: "Help menu: version row when no update. Argument is current version.")
    }

    var body: some View {
        // `?` requires shift; SwiftUI only fires when the modifier set matches the actual keystroke,
        // so we must declare both. (Bare `.command` shows ⌘? in the menu but never triggers.)
        Button(String(localized: "Dinky Help", comment: "Help menu: open help window.")) { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: [.command, .shift])

        Divider()

        // Info row — always disabled. Reflects update state when known.
        Button(versionLabel) {}
            .disabled(true)

        Button(String(localized: "What’s New…", comment: "Help menu: open release notes.")) {
            NSWorkspace.shared.open(releaseNotesURL)
        }
        Button(String(localized: "Check for Updates…", comment: "Help menu: check for updates.")) {
            NotificationCenter.default.post(name: .dinkyCheckUpdates, object: nil)
        }

        Divider()

        Button(String(localized: "GitHub Repo", comment: "Help menu: open source repository.")) {
            NSWorkspace.shared.open(Self.repoURL)
        }
        Button(String(localized: "Leave a Review…", comment: "Help menu: open GitHub Discussions reviews category.")) {
            NSWorkspace.shared.open(Self.leaveReviewURL)
        }
        Button(String(localized: "Report a Bug…", comment: "Help menu: report a bug.")) {
            NSWorkspace.shared.open(DiagnosticsReporter.githubIssueURL(title: String(localized: "Bug: ", comment: "Prefill for GitHub issue title.")))
        }
        Button(String(localized: "Give Feedback…", comment: "Help menu: send feedback email.")) {
            NSWorkspace.shared.open(
                DiagnosticsReporter.emailURL(
                    subject: String(localized: "Feedback — Dinky v\(currentVersion)", comment: "Email subject for feedback. Argument is app version."),
                    extraBody: "## Feedback\n\n"
                )
            )
        }
        Button(String(localized: "Visit dinkyfiles.com", comment: "Help menu: open marketing site.")) {
            NSWorkspace.shared.open(Self.siteURL)
        }
        Button(String(localized: "Email Support…", comment: "Help menu: contact support.")) {
            NSWorkspace.shared.open(
                DiagnosticsReporter.emailURL(
                    subject: String(localized: "Support — Dinky v\(currentVersion)", comment: "Email subject for support. Argument is app version."),
                    extraBody: "## How can we help?\n\n"
                )
            )
        }
    }
}

// MARK: - About panel

/// Opens a standard macOS About window with a custom credits block underneath
/// the app name and version. We show the live bundle size (so the "dinky" claim
/// stays honest as the app evolves) plus clickable links to the site and repo.
private func showAboutPanel() {
    let credits = NSMutableAttributedString()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineSpacing = 2

    let baseAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.secondaryLabelColor,
        .paragraphStyle: paragraph
    ]
    var linkAttrs: [NSAttributedString.Key: Any] = baseAttrs
    // Leave .foregroundColor to the system link color so URLs look like links.
    linkAttrs.removeValue(forKey: .foregroundColor)

    credits.append(NSAttributedString(string: bundleSizeString() + "\n", attributes: baseAttrs))

    var siteAttrs = linkAttrs
    siteAttrs[.link] = URL(string: "https://dinkyfiles.com")!
    credits.append(NSAttributedString(string: "dinkyfiles.com\n", attributes: siteAttrs))

    var ghAttrs = linkAttrs
    ghAttrs[.link] = URL(string: "https://github.com/heyderekj/dinky")!
    credits.append(NSAttributedString(string: "github.com/heyderekj/dinky\n", attributes: ghAttrs))

    var supportAttrs = linkAttrs
    supportAttrs[.link] = URL(string: "mailto:\(S.supportEmail)")!
    credits.append(NSAttributedString(string: S.supportEmail, attributes: supportAttrs))

    NSApplication.shared.orderFrontStandardAboutPanel(options: [
        NSApplication.AboutPanelOptionKey.credits: credits
    ])
    NSApplication.shared.activate(ignoringOtherApps: true)
}

/// Computes the real size of the installed app bundle, rounded to 1 decimal in MB.
/// Walks the bundle tree at runtime so this stays accurate as the app evolves.
private func bundleSizeString() -> String {
    let url = Bundle.main.bundleURL
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
    var total: Int64 = 0
    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) {
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: keys)
            if values?.isRegularFile == true {
                let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
                total += Int64(size)
            }
        }
    }
    let mb = Double(total) / 1_048_576.0
    return String(format: "%.1f MB", mb)
}

// MARK: - Post-crash / MetricKit prompt

/// Shown when the crash sentinel fired and/or MetricKit delivered crash diagnostics.
struct PostCrashReportSheet: View {
    let report: CrashReport
    @ObservedObject var diagnostics: DiagnosticsReporter

    private var headline: String {
        // Apple’s MetricKit English phrase; keep literal for reliable matching.
        if report.subtitle.contains("Crash diagnostics from Apple") {
            return String(localized: "Crash diagnostics", comment: "Post-crash sheet title when Apple diagnostics present.")
        }
        return String(localized: "Dinky crashed last time", comment: "Post-crash sheet title for generic crash.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline)
                        .font(.headline)
                    Text(report.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 16)

            if let mk = report.metricKitSummary, !mk.isEmpty {
                Text(String(localized: "Apple diagnostic summary", comment: "Label above MetricKit crash summary text."))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                ScrollView {
                    Text(mk)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(.bottom, 16)
            }

            HStack {
                Button(String(localized: "Email Report…", comment: "Post-crash sheet: send report by email.")) {
                    NSWorkspace.shared.open(diagnostics.postCrashEmailURL())
                    diagnostics.dismissPendingReport()
                }
                Button(String(localized: "GitHub Issue…", comment: "Post-crash sheet: open GitHub issue.")) {
                    NSWorkspace.shared.open(diagnostics.postCrashGitHubURL())
                    diagnostics.dismissPendingReport()
                }
                Spacer()
                Button(String(localized: "Dismiss", comment: "Post-crash sheet: close without sending.")) {
                    diagnostics.dismissPendingReport()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 440)
        .background(.ultraThinMaterial)
    }
}

// Reaches into the hosting NSWindow and clears its background so the
// SwiftUI .ultraThinMaterial above can show the blur/vibrancy through.
private struct TransparentWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Defer until the view is in the window hierarchy
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.setFrameAutosaveName("DinkyMainWindow")
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.setFrameAutosaveName("DinkyMainWindow")
    }
}
