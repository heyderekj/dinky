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
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = binary
            process.arguments = args

            var env = ProcessInfo.processInfo.environment
            let binDir = binary.deletingLastPathComponent()
            let bundledLib = binDir.deletingLastPathComponent().appendingPathComponent("lib", isDirectory: true)
            var parts: [String] = []
            if FileManager.default.fileExists(atPath: bundledLib.path) {
                parts.append(bundledLib.path)
            }
            parts.append("/opt/homebrew/lib")
            parts.append("/usr/local/lib")
            if let existing = env["DYLD_LIBRARY_PATH"], !existing.isEmpty { parts.append(existing) }
            env["DYLD_LIBRARY_PATH"] = parts.joined(separator: ":")
            process.environment = env

            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe()
            process.terminationHandler = { p in
                let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                    encoding: .utf8) ?? ""
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: DinkyPDFProcessError.processFailed(p.terminationStatus, stderr))
                }
            }
            do { try process.run() }
            catch { cont.resume(throwing: error) }
        }
    }
}
