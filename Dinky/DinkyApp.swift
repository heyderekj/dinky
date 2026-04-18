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
                .background(.ultraThinMaterial)        // frosted glass fill
                .background(TransparentWindow())       // makes NSWindow itself see-through
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        }
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
                Button("Open Files…") {
                    NotificationCenter.default.post(name: .dinkyOpenPanel, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Compress from Clipboard") {
                    NSApp.sendAction(Selector(("compressFromClipboard:")), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Divider()

                Button("Compress Now") {
                    NotificationCenter.default.post(name: .dinkyStartCompression, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Clear All") {
                    NotificationCenter.default.post(name: .dinkyClearAll, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .option])

                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .dinkyToggleSidebar, object: nil)
                }
                .keyboardShortcut("\\", modifiers: [.command, .shift])

                Button("Delete Selected") {
                    NotificationCenter.default.post(name: .dinkyDeleteSelectedRows, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Dinky") {
                    showAboutPanel()
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    NotificationCenter.default.post(name: .dinkyCheckUpdates, object: nil)
                }
                Button("History…") {
                    NotificationCenter.default.post(name: .dinkyShowHistory, object: nil)
                }
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

        // Opened via the Help menu (⌘?). Single-instance; reuses the same
        // window if it's already on screen.
        Window("Dinky Help", id: "help") {
            HelpWindow()
        }
        .defaultSize(width: 820, height: 600)
        .commandsRemoved()
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
    private static let issuesURL = URL(string: "https://github.com/heyderekj/dinky/issues/new")!
    private static let siteURL = URL(string: "https://dinkyfiles.com")!

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
            return "Version \(currentVersion) — \(newer) available"
        }
        return "Version \(currentVersion)"
    }

    var body: some View {
        // `?` requires shift; SwiftUI only fires when the modifier set matches the actual keystroke,
        // so we must declare both. (Bare `.command` shows ⌘? in the menu but never triggers.)
        Button("Dinky Help") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: [.command, .shift])

        Divider()

        // Info row — always disabled. Reflects update state when known.
        Button(versionLabel) {}
            .disabled(true)

        Button("What's New…") {
            NSWorkspace.shared.open(releaseNotesURL)
        }
        Button("Check for Updates…") {
            NotificationCenter.default.post(name: .dinkyCheckUpdates, object: nil)
        }

        Divider()

        Button("GitHub Repo") {
            NSWorkspace.shared.open(Self.repoURL)
        }
        Button("Report a Bug…") {
            NSWorkspace.shared.open(Self.issuesURL)
        }
        Button("Visit dinkyfiles.com") {
            NSWorkspace.shared.open(Self.siteURL)
        }
        Button("Email Support…") {
            NSWorkspace.shared.open(URL(string: "mailto:\(S.supportEmail)")!)
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
