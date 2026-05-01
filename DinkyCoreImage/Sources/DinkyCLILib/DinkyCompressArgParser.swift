import Foundation

public struct DinkyCLIParseError: Error, Equatable, Sendable {
    public var message: String
    public init(message: String) { self.message = message }
}

/// Parses `dinky compress` arguments (flags and file paths). Does not include the `compress` subcommand token.
public enum DinkyCompressArgParser {
    public static func parse(_ args: [String]) throws -> (DinkyCompressOptions, [String]) {
        var o = DinkyCompressOptions()
        var files: [String] = []
        var i = 0
        let n = args.count
        while i < n {
            let a = args[i]
            if a == "--" {
                files.append(contentsOf: args[(i + 1)...].map { $0 })
                break
            }
            if a == "-h" || a == "--help" {
                throw DinkyCLIParseError(message: "help: use: dinky compress <files> [--format] [--output-dir] [--json] ...")
            }
            if a.hasPrefix("-") {
                switch a {
                case "-f", "--format":
                    i += 1
                    guard i < n else { throw DinkyCLIParseError(message: "missing value for --format") }
                    o.format = args[i].lowercased()
                case "-w", "--max-width":
                    i += 1
                    guard i < n, let w = Int(args[i]) else { throw DinkyCLIParseError(message: "invalid --max-width") }
                    o.maxWidth = w
                case "--max-size-kb":
                    i += 1
                    guard i < n, let k = Int(args[i]) else { throw DinkyCLIParseError(message: "invalid --max-size-kb") }
                    o.maxFileSizeKB = k
                case "-o", "--output-dir":
                    i += 1
                    guard i < n else { throw DinkyCLIParseError(message: "missing --output-dir path") }
                    o.outputDir = URL(fileURLWithPath: args[i], isDirectory: true)
                case "-q", "--quality":
                    i += 1
                    guard i < n, let q = Int(args[i]) else { throw DinkyCLIParseError(message: "invalid --quality") }
                    o.quality = max(0, min(100, q))
                case "--no-smart-quality":
                    o.smartQuality = false
                case "--content-hint":
                    i += 1
                    guard i < n else { throw DinkyCLIParseError(message: "missing --content-hint") }
                    o.contentTypeHint = args[i]
                case "--strip-metadata", "--strip":
                    o.stripMetadata = true
                case "--no-strip-metadata":
                    o.stripMetadata = false
                case "--json":
                    o.json = true
                case "-j", "--parallel":
                    i += 1
                    guard i < n, let p = Int(args[i]) else { throw DinkyCLIParseError(message: "invalid --parallel") }
                    o.parallelLimit = max(1, p)
                default:
                    throw DinkyCLIParseError(message: "unknown option: \(a)")
                }
            } else {
                files.append(a)
            }
            i += 1
        }
        return (o, files)
    }
}
