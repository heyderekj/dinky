import DinkyCoreShared
import Foundation

enum ProcessRunnerError: LocalizedError, Sendable {
    case processFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .processFailed(let c, let m): return "Process exited \(c): \(m)"
        }
    }
}

enum ProcessRunner: Sendable {
    static func runExecutable(_ url: URL, arguments: [String]) async throws {
        let out = try await SubprocessRunner.run(url, arguments: arguments)
        guard out.status == 0 else {
            throw ProcessRunnerError.processFailed(out.status, out.stderr)
        }
    }
}
