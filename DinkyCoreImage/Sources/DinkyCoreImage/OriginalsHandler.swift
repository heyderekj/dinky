import DinkyCoreShared
import Foundation

public enum OriginalsHandler {
    @discardableResult
    public static func dispose(originalAt url: URL, action: OriginalsAction, backupFolder: URL?) throws -> URL? {
        switch action {
        case .keep:
            return nil
        case .trash:
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            return resulting as URL?
        case .backup:
            guard let folder = backupFolder else {
                throw OriginalsHandlerError.missingBackupFolder
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = uniqueDestination(in: folder, for: url)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }
}

public enum OriginalsHandlerError: LocalizedError {
    case missingBackupFolder
    public var errorDescription: String? {
        switch self {
        case .missingBackupFolder:
            return "Backup folder is not set or could not be accessed."
        }
    }
}

public extension OriginalsHandler {
    static func uniqueDestination(in folder: URL, for original: URL) -> URL {
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let stem = "\(base) (\(n))"
            candidate = folder.appendingPathComponent(stem).appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
