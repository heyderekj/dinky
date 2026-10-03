import DinkyCoreShared
import Foundation

public enum LameRunnerError: LocalizedError, Sendable {
    case lameMissing(URL)
    case processFailed(Int32, String)

    public var errorDescription: String? {
        switch self {
        case .lameMissing(let u): return "LAME encoder not found or not executable at \(u.path)"
        case .processFailed(let c, let m): return "lame exited \(c): \(m)"
        }
    }
}

/// Encode MP3 from a linear PCM WAV (produced by `afconvert`).
public enum LameRunner: Sendable {
    public static func encodeMP3(fromWAV wavURL: URL, to mp3URL: URL, bitrateKbps: Int, lameBinary: URL)
        async throws
    {
        guard FileManager.default.isExecutableFile(atPath: lameBinary.path) else {
            throw LameRunnerError.lameMissing(lameBinary)
        }

        try FileManager.default.createDirectory(
            at: mp3URL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: mp3URL)

        // `-q 2`: good tradeoff; `-b`: CBR for predictable sizing (matches tier labels).
        let args = ["-q", "2", "-b", "\(bitrateKbps)", wavURL.path, mp3URL.path]

        let out = try await SubprocessRunner.run(lameBinary, arguments: args)
        guard out.status == 0 else {
            throw LameRunnerError.processFailed(out.status, out.stderr)
        }

        guard FileManager.default.fileExists(atPath: mp3URL.path) else {
            throw LameRunnerError.processFailed(-1, "Output file missing after lame.")
        }
    }
}
