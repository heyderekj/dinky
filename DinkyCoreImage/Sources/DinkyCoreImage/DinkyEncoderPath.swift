import Foundation

/// Resolves the directory that contains `cwebp`, `avifenc`, and `oxipng` (same layout as Dinky.app Resources).
public enum DinkyEncoderPath: Sendable {
    /// 1) `DINKY_BIN` environment variable
    /// 2) `bin` next to the `dinky` executable
    /// 3) Homebrew on Apple Silicon (`/opt/homebrew/bin`)
    public static func resolveBinDirectory() -> URL? {
        if let e = ProcessInfo.processInfo.environment["DINKY_BIN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            let u = URL(fileURLWithPath: e, isDirectory: true)
            if isValidEncoderDir(u) { return u }
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let alongside = exe.deletingLastPathComponent().appendingPathComponent("bin", isDirectory: true)
        if isValidEncoderDir(alongside) { return alongside }

        let homebrew = URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true)
        if isValidEncoderDir(homebrew) { return homebrew }

        let homebrewX86 = URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
        if isValidEncoderDir(homebrewX86) { return homebrewX86 }
        return nil
    }

    public static func isValidEncoderDir(_ url: URL) -> Bool {
        let names = ["cwebp", "avifenc", "oxipng"]
        return names.allSatisfy {
            FileManager.default.isExecutableFile(atPath: url.appendingPathComponent($0).path)
        }
    }
}
