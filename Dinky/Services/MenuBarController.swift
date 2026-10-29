import AppKit
import SwiftUI

/// Dinky's menu bar item and its panel (same pattern as Slinky). On macOS 27 and later the panel
/// opens through the system's expanded-interface session, so it behaves like the menus beside it:
/// Control-F8 and the arrow keys reach it, and sliding across from another menu opens it. Before
/// 27, clicking the item toggles the panel.
///
/// Shown when Settings › Startup & Dock › Show in menu bar is on, and always while Dinky is
/// hidden from the Dock — then it's the only way back in.
@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    static let shared = MenuBarController()

    static let showInMenuBarKey = "showInMenuBar"

    private var item: NSStatusItem?
    private var panel: MenuBarPanelWindow?
    /// The macOS 27 session delegate (held strongly; the status item only keeps a weak reference).
    private var sessionBridge: AnyObject?

    private static var wantsItem: Bool {
        let showPref = UserDefaults.standard.object(forKey: showInMenuBarKey) as? Bool ?? true
        return showPref || DockPresenceManager.isEffectivelyHidden
    }

    /// Adds or removes the item to match Settings and Dock mode.
    func sync() {
        if Self.wantsItem { install() } else { uninstall() }
    }

    private func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // `MenuBarIcon` is the app mark, already vector + template-rendered in the asset catalog.
        // Its artwork runs edge to edge, so drawn at its native 22pt it reads bigger than the
        // system items next to it. 14pt gives about 14 × 12pt of ink, measured against the system's
        // own items (Wi-Fi 15 × 11, Spotlight 14 × 13, Control Center 12 × 12).
        let icon = NSImage(named: "MenuBarIcon")
        icon?.size = NSSize(width: 14, height: 14)
        icon?.accessibilityDescription = String(localized: "Dinky", comment: "Menu bar item accessibility label.")
        item.button?.image = icon
        self.item = item
        // The expanded-interface API is in the macOS 27 SDK (Swift 6.4); a build with an older
        // SDK, like CI's, only has the click-to-toggle path.
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            let bridge = ExpandedSessionBridge(controller: self)
            item.expandedInterfaceDelegate = bridge
            sessionBridge = bridge
            return
        }
        #endif
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
    }

    private func uninstall() {
        guard let item else { return }
        #if compiler(>=6.4)
        if #available(macOS 27, *) { item.expandedInterfaceSession?.cancel() }
        #endif
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
        sessionBridge = nil
        panel?.orderOut(nil)
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        if panel?.isVisible == true { closePanel() } else { showPanel() }
    }

    fileprivate func showPanel() {
        guard let button = item?.button, let window = button.window else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let content = panel.contentView?.subviews.first { panel.setContentSize(content.fittingSize) }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height - 4)
        if let screen = window.screen?.visibleFrame { origin.x = min(origin.x, screen.maxX - size.width - 8) }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
    }

    fileprivate func hidePanel() {
        panel?.orderOut(nil)
    }

    /// A row did its thing (or opened a window): close the way a menu would.
    func closePanel() {
        #if compiler(>=6.4)
        if #available(macOS 27, *), let session = item?.expandedInterfaceSession {
            session.cancel()
            return
        }
        #endif
        hidePanel()
    }

    private func makePanel() -> MenuBarPanelWindow {
        let root = DinkyRootModel.shared
        let host = NSHostingController(
            rootView: MenuBarPanel(vm: root.contentVM, close: { [weak self] in self?.closePanel() })
                .environmentObject(root.prefs)
        )
        host.sizingOptions = .preferredContentSize
        let panel = MenuBarPanelWindow(contentViewController: host)
        panel.styleMask = [.nonactivatingPanel, .fullSizeContentView, .borderless]
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.delegate = self

        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        host.view.wantsLayer = true
        host.view.layer?.cornerRadius = 12
        host.view.layer?.masksToBounds = true
        effect.addSubview(host.view)
        host.view.frame = effect.bounds
        host.view.autoresizingMask = [.width, .height]
        panel.contentView = effect
        panel.setContentSize(host.view.fittingSize)
        return panel
    }

    // A click somewhere else: the panel goes away the way a menu's would.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated { closePanel() }
    }
}

/// Borderless panels can't become key by default, and the panel needs to (keyboard, and closing
/// when focus moves elsewhere).
final class MenuBarPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

#if compiler(>=6.4)
/// The status item only holds its expanded-interface delegate weakly, and the protocol only exists
/// on macOS 27, so it lives in its own small object.
@available(macOS 27, *)
@MainActor
private final class ExpandedSessionBridge: NSObject, NSStatusItemExpandedInterfaceDelegate {
    weak var controller: MenuBarController?

    init(controller: MenuBarController) {
        self.controller = controller
    }

    nonisolated func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        MainActor.assumeIsolated { controller?.showPanel() }
    }

    nonisolated func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        MainActor.assumeIsolated { controller?.hidePanel() }
    }
}
#endif
