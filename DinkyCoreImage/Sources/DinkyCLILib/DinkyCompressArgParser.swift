import DinkyCoreShared
import Foundation

public struct DinkyCLIParseError: Error, Equatable, Sendable {
    public var message: String
    public init(message: String) { self.message = message }
}

public struct DinkyCompressParseResult: Sendable {
    public var options: DinkyCompressOptions
    public var paths: [String]
    /// Keys for flags explicitly passed on the CLI (`format`, `quality`, …) so preset merge does not clobber them.
    public var explicit: Set<String>
    public var preset: PresetCLIRef

    public init(options: DinkyCompressOptions, paths: [String], explicit: Set<String>, preset: PresetCLIRef) {
        self.options = options
        self.paths = paths
        self.explicit = explicit
        self.preset = preset
    }
}

public enum DinkyCompressArgParser {
    /// Parses `dinky compress-image` arguments (not including the subcommand token).
    public static func parse(_ args: [String]) throws -> DinkyCompressParseResult {
        var o = DinkyCompressOptions()
        var files: [String] = []
        var explicit: Set<String> = []
        var preset = PresetCLIRef()
        var i = 0
        let n = args.count
        while i < n {
            let a = args[i]
            if a == "--" {
                files.append(contentsOf: args[(i + 1)...].map { $0 })
                break
            }
            if a == "-h" || a == "--help" {
                throw DinkyCLIParseError(message: "help: use: dinky compress-image <files> [options]")
            }
            if a.hasPrefix("-") {
                switch a {
                case "--preset":
                    i += 1
                    guard i < n else { throw DinkyCLIParseError(message: "missing value for --preset") }
                    preset.name = args[i]
                case "--preset-id":
                    i += 1
                    guard i < n, let u = UUID(uuidString: args[i]) else {
                        throw DinkyCLIParseError(message: "invalid --preset-id (expected UUID)")
                    }
                    preset.id = u
                case "--preset-file":
                    i += 1
                    guard i < n else { throw DinkyCLIParseError(message: "missing value for --preset-file") }
                    preset.file = args[i]
                case "-f", "--format":
                    i += 1
                    guard i < n else { throw DinkyCLIParseError(message: "missing value for --format") }
                    o.format = args[i].lowercased()
                    explicit.insert("format")
                case "-w", "--max-width":
                    i += 1
                    guard i < n, let w = Int(args[i]) else { throw DinkyCLIParseError(message: "invalid --max-width") }
                    o.maxWidth = w
                    explicit.insert("maxWidth")
                case "--max-size-kb":
                    i += 1
                    guard i < n, let k = Int(args[i]) else { throw DinkyCLIParseError(message: "invalid --max-size-kb") }
                    o.maxFileSizeKB = k
                    explicit.insert("maxSizeKb")
                case "-o", "--output-dir":
                    i += 1
                    guard i < n else { throw DinkyCLIParseError(message: "missing --output-dir path") }
                    o.outputDir = URL(fileURLWithPath: args[i], isDirectory: true)
                    explicit.insert("outputDir")
                case "-q", "--quality":
                    i += 1
                    guard i < n, let q = Int(args[i]) else { throw DinkyCLIParseError(message: "invalid --quality") }
                    o.quality = max(0, min(100, q))
                    explicit.insert("quality")
                case "--no-smart-quality":
                    o.smartQuality = false
                    explicit.insert("smartQuality")
                case "--smart-quality":
                    o.smartQuality = true
                    explicit.insert("smartQuality")
                case "--content-hint":
                    i += 1
                    guard i < n else { throw DinkyCLIParseError(message: "missing --content-hint") }
                    o.contentTypeHint = args[i]
                    explicit.insert("contentHint")
                case "--strip-metadata", "--strip":
                    o.stripMetadata = true
                    explicit.insert("stripMetadata")
                case "--no-strip-metadata":
                    o.stripMetadata = false
                    explicit.insert("stripMetadata")
                case "--json":
                    o.json = true
                case "-j", "--parallel":
                    i += 1
                    guard i < n, let p = Int(args[i]) else { throw DinkyCLIParseError(message: "invalid --parallel") }
                    o.parallelLimit = max(1, p)
                    explicit.insert("parallel")
                case "--collision-style":
                    i += 1
                    guard i < n else { throw DinkyCLIParseError(message: "missing --collision-style") }
                    guard let s = CollisionNamingStyle(rawValue: args[i]) else {
                        throw DinkyCLIParseError(message: "unknown --collision-style")
                    }
                    o.collisionStyle = s
                    explicit.insert("collisionStyle")
                case "--collision-pattern":
                    i += 1
                    guard i < n else { throw DinkyCLIParseError(message: "missing --collision-pattern") }
                    o.collisionCustomPattern = args[i]
                    explicit.insert("collisionCustom")
                case "--chroma":
                    i += 1
                    guard i < n else { throw DinkyCLIParseError(message: "missing --chroma") }
                    let raw = args[i].lowercased()
                    switch raw {
                    case "auto":
                        o.chromaSubsamplingRaw = ChromaSubsampling.auto.rawValue
                    case "420", "yuv420":
                        o.chromaSubsamplingRaw = ChromaSubsampling.yuv420.rawValue
                    case "422", "yuv422":
                        o.chromaSubsamplingRaw = ChromaSubsampling.yuv422.rawValue
                    case "444", "yuv444":
                        o.chromaSubsamplingRaw = ChromaSubsampling.yuv444.rawValue
                    default:
                        throw DinkyCLIParseError(message: "unknown --chroma (use auto|420|422|444)")
                    }
                    explicit.insert("chromaSubsampling")
                case "--webp-lossless":
                    o.webpLossless = true
                    explicit.insert("webpLossless")
                case "--png-mode":
                    i += 1
                    guard i < n else { throw DinkyCLIParseError(message: "missing --png-mode") }
                    guard PNGOutputMode(rawValue: args[i].lowercased()) != nil else {
                        throw DinkyCLIParseError(message: "unknown --png-mode (use lossless|optimized)")
                    }
                    o.pngOutputModeRaw = args[i].lowercased()
                    explicit.insert("pngOutputMode")
                default:
                    throw DinkyCLIParseError(message: "unknown option: \(a)")
                }
            } else {
                files.append(a)
            }
            i += 1
        }
        return DinkyCompressParseResult(options: o, paths: files, explicit: explicit, preset: preset)
    }
}
