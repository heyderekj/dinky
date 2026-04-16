// Strings.swift — all user-facing copy in one place

import Foundation

extension Notification.Name {
    static let dinkyOpenPanel     = Notification.Name("dinkyOpenPanel")
    static let dinkyOpenFiles     = Notification.Name("dinkyOpenFiles")
    static let dinkyCheckUpdates  = Notification.Name("dinkyCheckUpdates")
}

enum S {
    // Drop zone — idle taglines cycle with each animation loop
    static let dropIdleTaglines: [String] = [
        "Big in. Dinky out.",
        "Making your images dinky.",
        "Dinky does it.",
        "Big files. Dinky results.",
        "Think dinky.",
        "Drop big. Pick up dinky.",
        "Go on, get dinky.",
        "In big. Out dinky.",
        "Dinkify your images.",
        "Get dinky with it.",
    ]
    static func dropIdle(loop: Int) -> String {
        dropIdleTaglines[loop % dropIdleTaglines.count]
    }
    static let dropHover     = "Let go."

    // Processing
    static let processSingle = "On it."
    static let processBatch  = "Working through the pile."
    static let processBig    = "Big batch. Give me a moment."

    // Completion
    static let doneGood      = "Done. Look how little they are now."
    static let doneMixed     = "Done. Some were already pretty lean."

    // Per-file
    static let skipped       = "Already tiny. Skipped."
    static let errored       = "Couldn't crunch this one. Skipped."
    static let zeroBytes     = "Couldn't make this one any smaller. Keeping the original."

    // Buttons
    static func compressButton(_ n: Int) -> String {
        n == 1 ? "Compress 1 image" : "Compress \(n) images"
    }
    static let clear         = "Clear"

    // Preferences
    static let prefsTitle    = "Preferences"

    // Format names
    static let webp = "WebP"
    static let avif = "AVIF"
    static let png  = "PNG"
}
