import AppKit
import Foundation

/// Hides Dinky from the Dock and App Switcher when the user enables background mode, and gets
/// Dinky's windows back on screen from AppKit entry points (menu bar item, reopen, Services,
/// global hotkey).
@MainActor
enum DockPresenceManager {
    nonisolated static let userDefaultsKey = "hideFromDockAndAppSwitcher"

    private static var suppressInitialWindowPending = false

    /// Work that needs the main window's `ContentView` — the only observer of the open-files and
    /// paste notifications — held until a freshly opened window has appeared.
    private static var actionsAwaitingMainWindow: [() -> Void] = []

    static var hidePreference: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// Accessory mode only when the user wants hide **and** Open at login is enabled.
    static var isEffectivelyHidden: Bool {
        hidePreference && LaunchAtLoginManager.isEnabled
    }

    static func applyFromDefaults() {
        updateActivationPolicy()
        updateStatusItem()
    }

    // MARK: - Dock icon

    /// Hidden mode still shows the Dock icon — and with it Dinky's menu bar and a ⌘Tab entry —
    /// while a Dinky window is open, so the window behaves like any other app window. Once the
    /// last one closes, Dinky goes back to living in the menu bar only.
    private static func updateActivationPolicy(opening: Bool = false) {
        let showsDockIcon = !isEffectivelyHidden || opening || hasOpenWindow
        let policy: NSApplication.ActivationPolicy = showsDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    /// Minimized windows count: in hidden mode the Dock is the only way to get them back.
    private static var hasOpenWindow: Bool {
        // The main window exists briefly at launch before it's ordered out; counting it would
        // flash the Dock icon on every hidden login.
        guard !suppressInitialWindowPending else { return false }
        return NSApp.windows.contains { $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }
    }

    static func startTrackingWindows() {
        _ = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            // The closing window still reports itself visible here; look again once it's gone.
            DispatchQueue.main.async { updateActivationPolicy() }
        }
    }

    // MARK: - Menu bar item

    /// With no Dock icon there is nothing to click to get Dinky back, so hidden mode puts an item
    /// in the menu bar instead. Removed again as soon as the Dock icon returns.
    private static var statusItem: NSStatusItem?
    private static let menuTarget = StatusMenuTarget()

    private static func updateStatusItem() {
        guard isEffectivelyHidden else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // `MenuBarIcon` is the app mark, already vector + template-rendered in the asset catalog.
        // Its artwork runs edge to edge, so drawn at its native 22pt it reads bigger than the
        // system items next to it; 18pt puts the glyph at ~15pt, matching them.
        let icon = NSImage(named: "MenuBarIcon")
        icon?.size = NSSize(width: 18, height: 18)
        icon?.accessibilityDescription = String(localized: "Dinky", comment: "Menu bar item accessibility label.")
        item.button?.image = icon

        let menu = NSMenu()
        menu.addItem(menuItem(
            String(localized: "Open Dinky", comment: "Menu bar item: show the main window."),
            #selector(StatusMenuTarget.openDinky)
        ))
        menu.addItem(menuItem(
            String(localized: "Settings…", comment: "Menu bar item: open settings."),
            #selector(StatusMenuTarget.openSettings)
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            String(localized: "Quit Dinky", comment: "Menu bar item: quit the app."),
            #selector(StatusMenuTarget.quitDinky)
        ))
        item.menu = menu
        statusItem = item
    }

    private static func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = menuTarget
        return item
    }

    @MainActor
    private final class StatusMenuTarget: NSObject {
        @objc func openDinky() {
            DockPresenceManager.showMainWindow()
        }

        @objc func openSettings() {
            DockPresenceManager.showSettings()
        }

        @objc func quitDinky() {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Windows

    static func shouldSuppressInitialWindow() -> Bool {
        isEffectivelyHidden
    }

    /// Defers until after SwiftUI creates the main window so login launches can stay headless.
    static func scheduleSuppressInitialWindowIfNeeded() {
        guard shouldSuppressInitialWindow() else { return }
        suppressInitialWindowPending = true
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                guard suppressInitialWindowPending else { return }
                suppressInitialWindowPending = false
                mainContentWindow()?.orderOut(nil)
                updateActivationPolicy()
            }
        }
    }

    static func cancelInitialWindowSuppression() {
        suppressInitialWindowPending = false
    }

    /// Brings the main window forward, creating it when there isn't one — a hidden-mode launch can
    /// be restored with no windows at all. `action` runs once the window's content is live:
    /// straight away if the window already exists, otherwise when it first appears.
    static func showMainWindow(then action: (() -> Void)? = nil) {
        updateActivationPolicy(opening: true)
        activateForUserRequest()
        if let window = mainContentWindow() {
            window.makeKeyAndOrderFront(nil)
            // Activation is only a request (macOS can decline it for an app with no Dock icon);
            // without this the window can come up behind whatever app is in front.
            window.orderFrontRegardless()
            action?()
        } else {
            if let action { actionsAwaitingMainWindow.append(action) }
            SceneOpener.open(id: DinkyMainWindow.sceneID)
        }
    }

    /// Called by `ContentView` once it's on screen, to run work queued by `showMainWindow(then:)`.
    static func mainWindowDidAppear() {
        let pending = actionsAwaitingMainWindow
        actionsAwaitingMainWindow.removeAll()
        pending.forEach { $0() }
    }

    static func showSettings() {
        updateActivationPolicy(opening: true)
        activateForUserRequest()
        SceneOpener.open(id: DinkyMacPreferencesWindow.sceneID)
    }

    /// For explicit "show me Dinky" requests — the menu bar item, reopen, hotkey, Services. Since
    /// macOS 14 `NSApp.activate()` is only a request, and it's routinely declined here: the window
    /// appears, but the other app keeps focus and the menu bar. Taking activation from the
    /// frontmost app is the non-deprecated way to do what the user just asked for.
    private static func activateForUserRequest() {
        let me = ProcessInfo.processInfo.processIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != me {
            _ = NSRunningApplication.current.activate(from: frontmost, options: [])
        } else {
            NSApp.activate()
        }
    }

    /// The main window only. SwiftUI stamps its scene id on the window as soon as it exists; the
    /// frame-autosave name `TransparentWindow` sets lands a run-loop turn later.
    static func mainContentWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.frameAutosaveName == "DinkyMainWindow"
                || window.identifier?.rawValue.hasPrefix("\(DinkyMainWindow.sceneID)-") == true
        }
    }
}
