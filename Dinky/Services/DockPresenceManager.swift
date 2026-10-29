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
        MenuBarController.shared.sync()
    }

    // MARK: - Dock icon

    /// Hidden mode still shows the Dock icon — and with it Dinky's menu bar and a ⌘Tab entry —
    /// while a Dinky window is open, so the window behaves like any other app window. Once the
    /// last one closes, Dinky goes back to living in the menu bar only.
    /// Returns true when this call switched Dinky from menu-bar-only to a regular Dock app.
    @discardableResult
    private static func updateActivationPolicy(opening: Bool = false) -> Bool {
        let showsDockIcon = !isEffectivelyHidden || opening || hasOpenWindow
        let policy: NSApplication.ActivationPolicy = showsDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return false }
        NSApp.setActivationPolicy(policy)
        return policy == .regular
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
        activateForUserRequest(becameRegular: updateActivationPolicy(opening: true))
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
        activateForUserRequest(becameRegular: updateActivationPolicy(opening: true))
        SceneOpener.open(id: DinkyMacPreferencesWindow.sceneID)
    }

    /// For explicit "show me Dinky" requests — the menu bar item, reopen, hotkey, Services. Since
    /// macOS 14 `NSApp.activate()` is only a request, and it's routinely declined here: the window
    /// appears, but the other app keeps focus and the menu bar. Taking activation from the
    /// frontmost app is the non-deprecated way to do what the user just asked for.
    private static func activateForUserRequest(becameRegular: Bool = false) {
        let me = ProcessInfo.processInfo.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier != me ? $0 : nil }
        activateNow(from: frontmost)
        if becameRegular, let frontmost { refreshMenuBar(bouncingThrough: frontmost) }
    }

    private static func activateNow(from frontmost: NSRunningApplication?) {
        if let frontmost {
            _ = NSRunningApplication.current.activate(from: frontmost, options: [])
        } else {
            NSApp.activate()
        }
    }

    /// Going from menu-bar-only to a Dock app leaves the menu bar showing the previous app's
    /// contents until Dinky loses focus and gets it back — switching away and back by hand fixes
    /// it. So do that once: hand focus to the app you were just in, then take it back. Of the
    /// variants tried by hand this worked best; bouncing through the Dock instead flickered.
    private static func refreshMenuBar(bouncingThrough previous: NSRunningApplication) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            _ = previous.activate(from: .current, options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                _ = NSRunningApplication.current.activate(from: previous, options: [])
                NSApp.orderedWindows.first(where: \.canBecomeMain)?.makeKeyAndOrderFront(nil)
            }
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
