import AppKit
import Carbon.HIToolbox

/// System-wide hotkey for “Clipboard Compress” via Carbon `RegisterEventHotKey` (no SPM, no Accessibility prompt).
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private static let hotKeySignature: OSType = {
        let s = "DNKY"
        var o: OSType = 0
        for b in s.utf8 { o = (o << 8) + OSType(b) }
        return o
    }()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private init() {}

    /// Reads `UserDefaults` keys written by `DinkyPreferences` (`shortcut.pasteClipboardGlobal`, `shortcut.pasteClipboard`).
    func syncFromDefaults() {
        let d = UserDefaults.standard
        let globalOn = d.object(forKey: "shortcut.pasteClipboardGlobal") as? Bool ?? false
        guard globalOn else {
            unregister()
            return
        }
        let data = d.data(forKey: "shortcut.pasteClipboard") ?? Data()
        let shortcut: CustomShortcut
        if data.isEmpty {
            shortcut = ShortcutAction.pasteClipboard.defaultShortcut
        } else {
            shortcut = (try? JSONDecoder().decode(CustomShortcut.self, from: data)) ?? ShortcutAction.pasteClipboard.defaultShortcut
        }
        register(shortcut)
    }

    /// Registers the given shortcut, replacing any previous registration.
    func register(_ shortcut: CustomShortcut) {
        unregister()
        guard let parts = Self.carbonKeyCodeAndModifiers(for: shortcut) else {
            return
        }
        ensureKeyboardEventHandlerInstalled()

        var hkID = EventHotKeyID()
        hkID.signature = Self.hotKeySignature
        hkID.id = 1

        let status = RegisterEventHotKey(
            parts.keyCode,
            parts.modifiers,
            hkID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            hotKeyRef = nil
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    // MARK: - Activation + notification

    private func handleHotKeyPressed() {
        DispatchQueue.main.async {
            DockPresenceManager.showMainWindow {
                NotificationCenter.default.post(name: .dinkyPasteClipboard, object: nil)
            }
        }
    }

    // MARK: - Carbon event handler

    private func ensureKeyboardEventHandlerInstalled() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyCallback,
            1,
            &spec,
            nil,
            &eventHandler
        )
        if status != noErr {
            eventHandler = nil
        }
    }

    private static let hotKeyCallback: EventHandlerUPP = { _, event, _ -> OSStatus in
        guard let event else { return OSStatus(eventNotHandledErr) }
        var hkID = EventHotKeyID()
        let err = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hkID
        )
        guard err == noErr, hkID.signature == GlobalHotkeyManager.hotKeySignature, hkID.id == 1 else {
            return OSStatus(eventNotHandledErr)
        }
        GlobalHotkeyManager.shared.handleHotKeyPressed()
        return noErr
    }

    // MARK: - CustomShortcut → Carbon

    private struct CarbonParts {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    private static func carbonKeyCodeAndModifiers(for shortcut: CustomShortcut) -> CarbonParts? {
        guard let keyCode = virtualKeyCode(for: shortcut.key) else { return nil }
        let mods = carbonModifierMask(NSEvent.ModifierFlags(rawValue: shortcut.modifiers))
        return CarbonParts(keyCode: keyCode, modifiers: mods)
    }

    private static func carbonModifierMask(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    /// Virtual key codes (US ANSI) matching `CustomShortcut` / `ShortcutRecorderField` output.
    private static func virtualKeyCode(for key: String) -> UInt32? {
        switch key {
        case "return": return UInt32(kVK_Return)
        case "tab": return UInt32(kVK_Tab)
        case "delete": return UInt32(kVK_Delete)
        case "deleteForward": return UInt32(kVK_ForwardDelete)
        case "escape": return UInt32(kVK_Escape)
        case "space": return UInt32(kVK_Space)
        case "upArrow": return UInt32(kVK_UpArrow)
        case "downArrow": return UInt32(kVK_DownArrow)
        case "leftArrow": return UInt32(kVK_LeftArrow)
        case "rightArrow": return UInt32(kVK_RightArrow)
        case "\\": return UInt32(kVK_ANSI_Backslash)
        case ",": return UInt32(kVK_ANSI_Comma)
        case ".": return UInt32(kVK_ANSI_Period)
        case "/": return UInt32(kVK_ANSI_Slash)
        case ";": return UInt32(kVK_ANSI_Semicolon)
        case "'": return UInt32(kVK_ANSI_Quote)
        case "[": return UInt32(kVK_ANSI_LeftBracket)
        case "]": return UInt32(kVK_ANSI_RightBracket)
        case "`": return UInt32(kVK_ANSI_Grave)
        case "-": return UInt32(kVK_ANSI_Minus)
        case "=": return UInt32(kVK_ANSI_Equal)
        default:
            break
        }

        guard key.count == 1, let ch = key.first else { return nil }
        let lower = String(ch).lowercased()
        guard let c = lower.first else { return nil }

        if c.isLetter {
            return letterKeyCode(c)
        }
        if c.isNumber {
            return digitKeyCode(c)
        }

        switch c {
        case "'": return UInt32(kVK_ANSI_Quote)
        case ",": return UInt32(kVK_ANSI_Comma)
        case ".": return UInt32(kVK_ANSI_Period)
        case "/": return UInt32(kVK_ANSI_Slash)
        case ";": return UInt32(kVK_ANSI_Semicolon)
        case "[": return UInt32(kVK_ANSI_LeftBracket)
        case "\\": return UInt32(kVK_ANSI_Backslash)
        case "]": return UInt32(kVK_ANSI_RightBracket)
        case "`": return UInt32(kVK_ANSI_Grave)
        case "-": return UInt32(kVK_ANSI_Minus)
        case "=": return UInt32(kVK_ANSI_Equal)
        default: return nil
        }
    }

    private static func letterKeyCode(_ c: Character) -> UInt32? {
        switch c {
        case "a": return UInt32(kVK_ANSI_A)
        case "b": return UInt32(kVK_ANSI_B)
        case "c": return UInt32(kVK_ANSI_C)
        case "d": return UInt32(kVK_ANSI_D)
        case "e": return UInt32(kVK_ANSI_E)
        case "f": return UInt32(kVK_ANSI_F)
        case "g": return UInt32(kVK_ANSI_G)
        case "h": return UInt32(kVK_ANSI_H)
        case "i": return UInt32(kVK_ANSI_I)
        case "j": return UInt32(kVK_ANSI_J)
        case "k": return UInt32(kVK_ANSI_K)
        case "l": return UInt32(kVK_ANSI_L)
        case "m": return UInt32(kVK_ANSI_M)
        case "n": return UInt32(kVK_ANSI_N)
        case "o": return UInt32(kVK_ANSI_O)
        case "p": return UInt32(kVK_ANSI_P)
        case "q": return UInt32(kVK_ANSI_Q)
        case "r": return UInt32(kVK_ANSI_R)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "u": return UInt32(kVK_ANSI_U)
        case "v": return UInt32(kVK_ANSI_V)
        case "w": return UInt32(kVK_ANSI_W)
        case "x": return UInt32(kVK_ANSI_X)
        case "y": return UInt32(kVK_ANSI_Y)
        case "z": return UInt32(kVK_ANSI_Z)
        default: return nil
        }
    }

    private static func digitKeyCode(_ c: Character) -> UInt32? {
        switch c {
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        case "0": return UInt32(kVK_ANSI_0)
        default: return nil
        }
    }
}
