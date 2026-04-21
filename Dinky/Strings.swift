// Strings.swift — all user-facing copy in one place

import Foundation

/// One row for Settings → Shortcuts and any in-app reference lists.
struct KeyboardShortcutReference: Identifiable {
    let title: String
    let keys: String
    var id: String { title }
}

extension Notification.Name {
    static let dinkyOpenPanel     = Notification.Name("dinkyOpenPanel")
    static let dinkyOpenFiles     = Notification.Name("dinkyOpenFiles")
    static let dinkyCheckUpdates  = Notification.Name("dinkyCheckUpdates")
    static let dinkyPasteClipboard  = Notification.Name("dinkyPasteClipboard")
    static let dinkyShowHistory     = Notification.Name("dinkyShowHistory")
    /// Re-present the last completed batch summary (menu / shortcut).
    static let dinkyShowLastBatchSummary = Notification.Name("dinkyShowLastBatchSummary")
    /// `object` is `PreferencesTab.rawValue` (Int)
    static let dinkySelectPreferencesTab = Notification.Name("dinkySelectPreferencesTab")
    static let dinkyClearAll            = Notification.Name("dinkyClearAll")
    static let dinkyToggleSidebar       = Notification.Name("dinkyToggleSidebar")
    static let dinkyDeleteSelectedRows  = Notification.Name("dinkyDeleteSelectedRows")
    static let dinkyStartCompression    = Notification.Name("dinkyStartCompression")
    /// Re-register the system-wide “Clipboard Compress” hotkey (toggle or shortcut changed).
    static let dinkyGlobalPasteHotkeyChanged = Notification.Name("dinkyGlobalPasteHotkeyChanged")
    /// Posted before quit so SwiftUI can dismiss sheets; used with `applicationShouldTerminate` / `terminateLater`.
    static let dinkyPrepareQuit = Notification.Name("dinkyPrepareQuit")
}

enum S {
    // Drop zone — idle taglines cycle with each animation loop (English brand voice)
    static let dropIdleTaglines: [String] = [
        "Big in. Dinky out.",
        "Making your files dinky.",
        "Dinky does it.",
        "Big files. Dinky results.",
        "Think dinky.",
        "Drop big. Pick up dinky.",
        "Go on, get dinky.",
        "In big. Out dinky.",
        "Dinkify your files.",
        "Get dinky with it.",
        "Images, videos, PDFs — all dinky.",
    ]
    static func dropIdle(loop: Int) -> String {
        dropIdleTaglines[loop % dropIdleTaglines.count]
    }
    static let dropHover     = "Let go."

    // Processing (English brand voice)
    static let processSingle = "On it."
    static let processBatch  = "Working through the pile."
    static let processBig    = "Big batch. Give me a moment."

    // Completion (English brand voice)
    static let doneGood      = "Done. Look how little they are now."
    static let doneMixed     = "Done. Some were already pretty lean."

    // Per-file (English brand voice)
    static let skipped       = "Already tiny. Skipped."
    static let errored       = "Couldn't crunch this one. Skipped."
    static let zeroBytes     = "Couldn't make this one any smaller. Keeping the original."

    // Buttons
    static func compressButton(_ n: Int) -> String {
        if n == 1 {
            return String(localized: "Compress 1 file", comment: "Main window: primary action when one file is queued.")
        }
        return String(localized: "Compress \(n) files", comment: "Main window: primary action when multiple files are queued. Argument is the count.")
    }
    static var clear: String { String(localized: "Clear", comment: "Toolbar or list: clear completed rows.") }

    // Preferences
    static var prefsTitle: String { String(localized: "Preferences", comment: "macOS Settings window title.") }

    /// Settings › General › Behavior — global clipboard shortcut explainer (combo comes from `CustomShortcut.displayString`).
    static func behaviorPasteClipboardGlobalFootnote(currentShortcutDisplay: String) -> String {
        String(localized: "Triggers Clipboard Compress from any app while Dinky is running (currently \(currentShortcutDisplay)).", comment: "Settings footnote; argument is the shortcut key combo.")
    }

    /// Settings › General › Compression — parallel job cap (three tiers: 1, 3, or 8).
    static var concurrentCompressionPickerLabel: String {
        String(localized: "Batch speed", comment: "Settings: label for parallel compression limit picker.")
    }
    static var concurrentCompressionFootnote: String {
        String(localized: "How many files crunch at once — not image, video, or PDF quality. Fast is gentle; Fastest clears the queue sooner if your Mac is up for it.", comment: "Settings: explains batch parallelism tiers.")
    }

    /// Settings › General › Compression — optional largest-first batch order.
    static var batchLargestFirstLabel: String {
        String(localized: "Start with largest files", comment: "Settings: toggle to schedule big files first in a batch.")
    }
    static var batchLargestFirstFootnote: String {
        String(localized: "When enabled, the longest jobs run first so the batch tends to finish sooner. The default is smallest first for faster early feedback.", comment: "Settings: explains batch ordering toggle.")
    }

    static func concurrentCompressionTierOption(limit: Int) -> String {
        switch limit {
        case 1: return "Fast — one at a time, dinky zen"
        case 3: return "Faster — up to three in parallel"
        case 8: return "Fastest — up to eight, all cores welcome"
        default: return "Up to \(limit)"
        }
    }

    /// Plain label for assistive tech (localized).
    static func concurrentCompressionAccessibilityLabel(limit: Int) -> String {
        switch limit {
        case 1:
            return String(localized: "Up to one file compressing at a time", comment: "VoiceOver label for batch speed option.")
        case 3:
            return String(localized: "Up to three files compressing at a time", comment: "VoiceOver label for batch speed option.")
        case 8:
            return String(localized: "Up to eight files compressing at a time", comment: "VoiceOver label for batch speed option.")
        default:
            return String(localized: "Up to \(limit) files compressing at a time", comment: "VoiceOver label for batch speed option; argument is numeric limit.")
        }
    }

    // Format names (technical; keep recognizable)
    static let webp = "WebP"
    static let avif = "AVIF"
    static let png  = "PNG"
    static let heic = "HEIC"

    /// Shown in About, Settings, and linked with `mailto:`.
    static let supportEmail = "help@dinkyfiles.com"

    // Paste from clipboard
    static var pasteEmptyTitle: String { String(localized: "Nothing to paste", comment: "Alert title when clipboard has no compressible item.") }
    static var pasteEmptyMessage: String {
        String(localized: "Copy a supported file in Finder, or copy an image (PNG or TIFF), then try again.", comment: "Alert message for empty clipboard paste.")
    }
    static var pasteDuplicateTitle: String { String(localized: "Already in the list", comment: "Alert title when pasted file is already queued.") }
    static var pasteDuplicateMessage: String {
        String(localized: "That file is already queued — drop something new or clear the list first.", comment: "Alert message for duplicate paste.")
    }

    // Settings → Shortcuts
    static var shortcutsTabServicesFooter: String {
        String(localized: "Assign shortcuts for Finder’s “Compress with Dinky” in System Settings → Keyboard → Keyboard Shortcuts → Services.", comment: "Settings Shortcuts tab footer.")
    }
    static func shortcutsTabHelpFooter(helpMenuShortcut: String) -> String {
        String(localized: "For watch folders, presets, and full troubleshooting, open Dinky Help from the Help menu (\(helpMenuShortcut)).", comment: "Settings Shortcuts tab footer; argument is help shortcut.")
    }
    static var shortcutsAppDescription: String {
        String(localized: "Dinky exposes Compress Images, Compress PDFs, and Compress Videos actions in the Shortcuts app. Pipe files from Finder or other actions through Dinky — same engines as in-app compression (images: format + Smart quality + resize + metadata; PDF and video follow Settings for those types).", comment: "Settings: Shortcuts app integration description.")
    }

    static var shortcutsCustomizableHeader: String { String(localized: "Customize", comment: "Settings Shortcuts section header.") }
    static var shortcutsFixedHeader: String { String(localized: "System & help", comment: "Settings Shortcuts section header for fixed shortcuts.") }
    static var shortcutsResetAll: String { String(localized: "Reset All Shortcuts", comment: "Button to reset all custom shortcuts.") }
    static var shortcutsResetRow: String { String(localized: "Reset", comment: "Button to reset one shortcut row.") }
    static var shortcutsEdit: String { String(localized: "Edit", comment: "Button to start recording a new shortcut.") }
    static var shortcutsCancelEdit: String { String(localized: "Cancel", comment: "Button to cancel shortcut recording.") }
    static var shortcutsRecorderPrompt: String { String(localized: "Press a key…", comment: "Placeholder while waiting for shortcut keys.") }
    static var shortcutsRecorderHint: String {
        String(localized: "Press a combo to save · Esc to cancel · Delete to reset", comment: "Hint under shortcut recorder field.")
    }
    static var shortcutsConflictPrefix: String { String(localized: "Already used by", comment: "Prefix when shortcut conflicts; followed by action name.") }
    static var shortcutsSystemWarningPrefix: String { String(localized: "Overrides macOS:", comment: "Prefix when shortcut may override a system shortcut.") }

    // Settings → Output (duplicate filenames when saving)
    static var duplicateNamingPickerAccessibilityLabel: String {
        String(localized: "If that filename is already taken", comment: "VoiceOver label for duplicate-naming style picker.")
    }
    static var duplicateNamingSectionFooter: String {
        String(localized: "Only when a file with the same name is already in the save folder — Dinky picks the next free name.", comment: "Settings: duplicate naming section footer.")
    }
    static var duplicateNamingCustomFieldLabel: String {
        String(localized: "Text to add", comment: "Settings: label for custom duplicate filename text field.")
    }
    static var duplicateNamingCustomPlaceholder: String {
        String(localized: "Examples: _backup, holiday{n}", comment: "Settings: placeholder for custom duplicate pattern field.")
    }
    /// Explains `{n}` in plain language; middots match Shortcuts recorder hint rhythm.
    static var duplicateNamingCustomHint: String {
        String(localized: "Use {n} where the number should go — holiday{n} becomes holiday1, holiday2 · Skip {n} and we only add a number if there’s still a clash", comment: "Settings: caption under custom duplicate field.")
    }

    /// Non-customizable menu items (matches `DinkyFixedShortcut` + system Settings).
    static var fixedMenuShortcutReference: [KeyboardShortcutReference] {
        DinkyFixedShortcut.allCases.map {
            KeyboardShortcutReference(title: $0.title, keys: $0.shortcut.displayString)
        }
    }
}
