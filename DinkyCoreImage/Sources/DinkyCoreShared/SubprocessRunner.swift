import Foundation

/// Runs a bundled command-line tool to completion. stdout is discarded and stderr is read while the
/// tool runs: reading a pipe only after exit deadlocks as soon as a tool fills the pipe buffer
/// (~64 KB — e.g. `lame` progress on a long file), leaving the batch stuck forever.
public enum SubprocessRunner {
    public struct Output: Sendable {
        public let status: Int32
        /// The last 64 KB of stderr, for error messages.
        public let stderr: String
    }

    static let stderrLimit = 64 * 1024

    public static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> Output {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Output, Error>) in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment { process.environment = environment }
            process.standardOutput = FileHandle.nullDevice
            let errPipe = Pipe()
            process.standardError = errPipe

            let collected = StderrBox()
            let group = DispatchGroup()
            group.enter()
            process.terminationHandler = { _ in group.leave() }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
                return
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let handle = errPipe.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    collected.append(chunk)
                }
                group.leave()
            }
            group.notify(queue: .global(qos: .utility)) {
                cont.resume(returning: Output(status: process.terminationStatus, stderr: collected.string))
            }
        }
    }
}

/// Keeps only the tail of a stream; written by one reader, read after it finishes.
private final class StderrBox: @unchecked Sendable {
    private var data = Data()

    func append(_ chunk: Data) {
        data.append(chunk)
        if data.count > SubprocessRunner.stderrLimit * 2 {
            data = data.suffix(SubprocessRunner.stderrLimit)
        }
    }

    var string: String {
        String(decoding: data.suffix(SubprocessRunner.stderrLimit), as: UTF8.self)
    }
}
