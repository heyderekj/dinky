import DinkyCoreShared
import Foundation

/// Puts a kept result in place and deals with the original — in that order, and only for results
/// that are being kept. Encoders never touch the original; a result that's discarded (no gain,
/// under the savings minimum, failed) leaves the source exactly as it was.
public enum OutputFinalizer {
    public struct Result: Sendable, Equatable {
        public let outputURL: URL
        /// Where the original went (Trash or Backup), for Undo. Nil when it stayed put.
        public let originalRecoveryURL: URL?
    }

    public typealias Disposer = (_ original: URL, _ action: OriginalsAction, _ backupFolder: URL?) throws -> URL?

    /// - Parameters:
    ///   - produced: The encoded file.
    ///   - stagedDestination: Where `produced` belongs when it was written to a temp file. Equal to
    ///     `source` when the result replaces the original at the same path.
    public static func finalize(
        source: URL,
        produced: URL,
        stagedDestination: URL?,
        action: OriginalsAction,
        backupFolder: URL?,
        isURLDownloadSource: Bool,
        collisionStyle: CollisionNamingStyle,
        customPattern: String,
        dispose: Disposer = { try OriginalsHandler.dispose(originalAt: $0, action: $1, backupFolder: $2) },
        fileManager fm: FileManager = .default
    ) throws -> Result {
        let replacesSource = stagedDestination.map {
            $0.standardizedFileURL.path == source.standardizedFileURL.path
        } ?? false

        if isURLDownloadSource {
            // The source is Dinky's own temp download — never Trash/Backup it, just clean it up.
            if replacesSource { try? fm.removeItem(at: source) }
            let out = try place(produced, at: stagedDestination, source: source,
                                style: collisionStyle, customPattern: customPattern, fm: fm)
            if !replacesSource { try? fm.removeItem(at: source) }
            return Result(outputURL: out, originalRecoveryURL: nil)
        }

        if replacesSource {
            // The original has to make room even when it's meant to stay, so "keep" means Trash here.
            let effective: OriginalsAction = action == .keep ? .trash : action
            let recovery: URL?
            do {
                recovery = try dispose(source, effective, backupFolder)
            } catch {
                try? fm.removeItem(at: produced)
                throw error
            }
            do {
                let out = try OutputPathUniqueness.moveTempItemToUniqueOutput(
                    temp: produced, desiredOutput: source, sourceURL: source,
                    style: collisionStyle, customPattern: customPattern, fileManager: fm
                )
                return Result(outputURL: out, originalRecoveryURL: recovery)
            } catch {
                if let recovery, !fm.fileExists(atPath: source.path) {
                    try? fm.moveItem(at: recovery, to: source)
                }
                try? fm.removeItem(at: produced)
                throw error
            }
        }

        let out = try place(produced, at: stagedDestination, source: source,
                            style: collisionStyle, customPattern: customPattern, fm: fm)
        // Output is safely in place; a failed Trash/Backup leaves the original where it was.
        let recovery = action == .keep ? nil : ((try? dispose(source, action, backupFolder)) ?? nil)
        return Result(outputURL: out, originalRecoveryURL: recovery)
    }

    private static func place(
        _ produced: URL, at destination: URL?, source: URL,
        style: CollisionNamingStyle, customPattern: String, fm: FileManager
    ) throws -> URL {
        guard let destination,
              destination.standardizedFileURL.path != produced.standardizedFileURL.path
        else { return produced }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try OutputPathUniqueness.moveTempItemToUniqueOutput(
            temp: produced, desiredOutput: destination, sourceURL: source,
            style: style, customPattern: customPattern, fileManager: fm
        )
    }
}
