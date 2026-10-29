import DinkyCoreShared
import Foundation

/// Thrown when an external tool (e.g. qpdf) exits non-zero.
public enum DinkyPDFProcessError: LocalizedError, Sendable {
    case processFailed(Int32, String)
    case outputMissing

    public var errorDescription: String? {
        switch self {
        case .processFailed(let c, let e): return "Process exited \(c): \(e)"
        case .outputMissing: return "Output file was not created."
        }
    }
}

public enum PDFProcessRunner: Sendable {
    public static func run(_ binary: URL, args: [String]) async throws {
        let out = try await SubprocessRunner.run(binary, arguments: args)
        guard out.status == 0 else {
            throw DinkyPDFProcessError.processFailed(out.status, out.stderr)
        }
    }
}
