import Foundation
import Darwin

public enum OutputPathUniqueness {
    public static func refreshUniqueOutput(
        currentCandidate: URL,
        sourceURL: URL,
        style: CollisionNamingStyle,
        customPattern: String
    ) -> URL {
        uniqueOutputURL(
            desired: currentCandidate,
            sourceURL: sourceURL,
            style: style,
            customPattern: customPattern
        )
    }

    public static func moveTempItemToUniqueOutput(
        temp: URL,
        desiredOutput: URL,
        sourceURL: URL,
        style: CollisionNamingStyle,
        customPattern: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let maxAttempts = 64
        var lastError: Error?
        for _ in 0..<maxAttempts {
            let finalURL = uniqueOutputURL(
                desired: desiredOutput,
                sourceURL: sourceURL,
                style: style,
                customPattern: customPattern
            )
            do {
                try fileManager.moveItem(at: temp, to: finalURL)
                return finalURL
            } catch {
                lastError = error
                guard isDestinationExistsCollision(error) else { throw error }
            }
        }
        try? fileManager.removeItem(at: temp)
        throw lastError ?? CocoaError(.fileWriteFileExists)
    }

    private static func isDestinationExistsCollision(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteFileExistsError { return true }
        if ns.domain == NSPOSIXErrorDomain, ns.code == EEXIST { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isDestinationExistsCollision(underlying)
        }
        return false
    }

    public static func uniqueOutputURL(
        desired: URL,
        sourceURL: URL,
        style: CollisionNamingStyle,
        customPattern: String = ""
    ) -> URL {
        let desiredPath = desired.standardizedFileURL.path
        let sourcePath = sourceURL.standardizedFileURL.path
        if desiredPath == sourcePath { return desired }

        let dir = desired.deletingLastPathComponent()
        let ext = desired.pathExtension
        let baseStem = desired.deletingPathExtension().lastPathComponent

        var candidate = desired
        if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }

        switch style {
        case .finderDuplicate:
            let copyFrag = String(localized: " copy", comment: "Filename: first duplicate after base name, as in Finder “file copy”.")
            var n = 1
            while true {
                let stem: String
                if n == 1 {
                    stem = baseStem + copyFrag
                } else {
                    stem = baseStem + copyFrag + " \(n)"
                }
                candidate = dir.appendingPathComponent(stem).appendingPathExtension(ext)
                if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
                n += 1
            }
        case .finderNumbered:
            var n = 1
            while true {
                let stem = "\(baseStem) (\(n))"
                candidate = dir.appendingPathComponent(stem).appendingPathExtension(ext)
                if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
                n += 1
            }
        case .custom:
            let pattern = effectiveCustomPattern(customPattern)
            var n = 1
            while true {
                let stem = stemForCustomCollision(baseStem: baseStem, pattern: pattern, index: n)
                candidate = dir.appendingPathComponent(stem).appendingPathExtension(ext)
                if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
                n += 1
            }
        }
    }

    private static func effectiveCustomPattern(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            return String(localized: " copy", comment: "Filename: first duplicate after base name, as in Finder “file copy”.")
        }
        return t
    }

    private static func stemForCustomCollision(baseStem: String, pattern: String, index: Int) -> String {
        if pattern.contains("{n}") {
            return baseStem + pattern.replacingOccurrences(of: "{n}", with: String(index))
        }
        if index == 1 {
            return baseStem + pattern
        }
        return baseStem + pattern + " \(index)"
    }
}
