import SwiftUI
import AppKit

@main
struct DinkyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var prefs = DinkyPreferences()
    @StateObject private var updater = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView(prefs: prefs)
                .environmentObject(prefs)
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
                Button("Open Images…") {
                    NotificationCenter.default.post(name: .dinkyOpenPanel, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
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
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(prefs)
                .environmentObject(updater)
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
    siteAttrs[.link] = URL(string: "https://dinkyimg.app")!
    credits.append(NSAttributedString(string: "dinkyimg.app\n", attributes: siteAttrs))

    var ghAttrs = linkAttrs
    ghAttrs[.link] = URL(string: "https://github.com/heyderekj/dinky")!
    credits.append(NSAttributedString(string: "github.com/heyderekj/dinky", attributes: ghAttrs))

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
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
    }
}
