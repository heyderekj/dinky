import AppKit
import Foundation

/// Hides Dinky from the Dock and App Switcher when the user enables background mode.
enum DockPresenceManager {
    static let userDefaultsKey = "hideFromDockAndAppSwitcher"

    private static var suppressInitialWindowPending = false

    static var hidePreference: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// Accessory mode only when the user wants hide **and** Open at login is enabled.
    static var isEffectivelyHidden: Bool {
        hidePreference && LaunchAtLoginManager.isEnabled
    }

    static func applyFromDefaults() {
        NSApp.setActivationPolicy(isEffectivelyHidden ? .accessory : .regular)
        updateStatusItem()
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

    private final class StatusMenuTarget: NSObject {
        @objc func openDinky() {
            DockPresenceManager.showMainWindow()
        }

        @objc func openSettings() {
            // Show the main window first: the preferences scene is opened by `ContentView`, so it
            // has to be on screen to receive this.
            DockPresenceManager.showMainWindow()
            NotificationCenter.default.post(name: .dinkyOpenMacPreferences, object: nil)
        }

        @objc func quitDinky() {
            NSApp.terminate(nil)
        }
    }

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
            }
        }
    }

    static func cancelInitialWindowSuppression() {
        suppressInitialWindowPending = false
    }

    static func showMainWindow() {
        // Opening a running accessory app from Finder/Spotlight puts it back to .regular, which
        // would restore the Dock icon for the rest of the session. Re-assert the user's choice
        // before activating, so the window returns under the policy they actually asked for.
        applyFromDefaults()
        NSApp.activate(ignoringOtherApps: true)
        bringMainWindowForward()
    }

    static func mainContentWindow() -> NSWindow? {
        if let window = NSApp.windows.first(where: { $0.frameAutosaveName == "DinkyMainWindow" }) {
            return window
        }
        return NSApp.windows.first(where: { window in
            window.canBecomeKey
                && window.title != "Dinky Help"
                && window.title != "Settings"
                && window.frameAutosaveName != "help"
        })
    }

    static func bringMainWindowForward() {
        if let window = mainContentWindow() {
            window.makeKeyAndOrderFront(nil)
            return
        }
        NSApp.sendAction(Selector(("newWindow:")), to: nil, from: nil)
    }
}
