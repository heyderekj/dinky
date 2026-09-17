import DinkyCoreImage
import DinkyCoreShared
import Foundation

public enum DinkyCompressCommand {
    public static func run(_ args: [String]) async -> (Int32, Int) {
        let parse: DinkyCompressParseResult
        do {
            parse = try DinkyCompressArgParser.parse(args)
        } catch let e as DinkyCLIParseError {
            FileHandle.standardError.write(Data("dinky: \(e.message)\n".utf8))
            return (1, 0)
        } catch {
            FileHandle.standardError.write(Data("dinky: \(error.localizedDescription)\n".utf8))
            return (1, 0)
        }

        var opts = parse.options
        let presetUsed: CompressionPreset?
        do {
            presetUsed = try DinkyCLIPresetSupport.applyImagePresetIfNeeded(
                ref: parse.preset,
                explicit: parse.explicit,
                options: &opts
            )
        } catch let e as DinkyCLIPresetError {
            FileHandle.standardError.write(Data("dinky: \(e.message)\n".utf8))
            return (1, 0)
        } catch {
            FileHandle.standardError.write(Data("dinky: \(error.localizedDescription)\n".utf8))
            return (1, 0)
        }

        let paths = parse.paths

        guard !paths.isEmpty else {
            FileHandle.standardError.write(Data("dinky compress: no input files (see: dinky help)\n".utf8))
            return (1, 0)
        }

        guard DinkyEncoderPath.resolveBinDirectory() != nil else {
            FileHandle.standardError.write(
                Data(
                    "dinky: could not find encoders. Set DINKY_BIN to a folder with cwebp, avifenc, and oxipng, or use ./bin next to the dinky binary, or install Homebrew webp+libavif+oxipng.\n"
                        .utf8
                )
            )
            return (1, 0)
        }

        let (code, results) = await runWithOptions(opts, paths: paths, preset: presetUsed)
        printResults(opts: opts, code: code, fileResults: results)
        return (code, results.count)
    }

    /// Shared by the `compress-image` subcommand and `dinky serve`.
    public static func runWithOptions(_ opts: DinkyCompressOptions, paths: [String], preset: CompressionPreset? = nil) async
        -> (Int32, [DinkyImageCompressFileResult])
    {
        guard let bin = DinkyEncoderPath.resolveBinDirectory() else {
            return (1, paths.map { p in
                DinkyImageCompressFileResult(
                    input: p, output: nil, originalBytes: 0, outputBytes: nil, savingsPercent: nil, detectedContent: nil, error: "encoders not found"
                )
            })
        }

        let engine = DinkyImageCompression(binDirectory: bin)
        var fileResults: [DinkyImageCompressFileResult] = []
        var anyFailed = false
        var smartQ = opts.smartQuality
        if opts.quality != nil { smartQ = false }

        for p in paths {
            let inURL = URL(fileURLWithPath: p, isDirectory: false).standardizedFileURL
            let origSize: Int64 = (try? inURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
            guard FileManager.default.isReadableFile(atPath: inURL.path) else {
                anyFailed = true
                fileResults.append(
                    DinkyImageCompressFileResult(
                        input: p,
                        output: nil,
                        originalBytes: origSize,
                        outputBytes: nil,
                        savingsPercent: nil,
                        detectedContent: nil,
                        error: "No such file or not readable"
                    )
                )
                continue
            }

            var classified: ContentType?
            if opts.format == "auto" || smartQ {
                classified = ContentClassifier.classify(inURL)
            }
            let format: CompressionFormat
            do {
                format = try resolveFormat(
                    from: opts.format,
                    sourceURL: inURL,
                    classified: classified
                )
            } catch {
                anyFailed = true
                fileResults.append(
                    DinkyImageCompressFileResult(
                        input: p,
                        output: nil,
                        originalBytes: origSize,
                        outputBytes: nil,
                        savingsPercent: nil,
                        detectedContent: classified?.rawValue,
                        error: "Invalid --format: \(opts.format)"
                    )
                )
                continue
            }

            let outDir: URL
            do {
                if let d = opts.outputDir {
                    outDir = d.standardizedFileURL
                } else {
                    outDir = try DinkyCLIPresetSupport.outputDirectoryForSourceURL(
                        preset: preset,
                        source: inURL
                    ).standardizedFileURL
                }
            } catch let e as DinkyCLIPresetError {
                anyFailed = true
                fileResults.append(
                    DinkyImageCompressFileResult(
                        input: p,
                        output: nil,
                        originalBytes: origSize,
                        outputBytes: nil,
                        savingsPercent: nil,
                        detectedContent: classified?.rawValue,
                        error: e.message
                    )
                )
                continue
            } catch {
                anyFailed = true
                fileResults.append(
                    DinkyImageCompressFileResult(
                        input: p,
                        output: nil,
                        originalBytes: origSize,
                        outputBytes: nil,
                        savingsPercent: nil,
                        detectedContent: classified?.rawValue,
                        error: error.localizedDescription
                    )
                )
                continue
            }
            try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

            let outName: String
            if let pr = preset {
                outName = DinkyCLIPresetSupport.outputFilenameStem(
                    preset: pr,
                    source: inURL,
                    mediaExtension: format.outputExtension
                )
            } else if format == .png, inURL.pathExtension.lowercased() == "png" {
                let stem = inURL.deletingPathExtension().lastPathComponent
                outName = stem + "-dinky." + format.outputExtension
            } else {
                outName = inURL.deletingPathExtension().lastPathComponent + "." + format.outputExtension
            }
            let desiredOut = outDir.appendingPathComponent(outName, isDirectory: false)

            let goals = CompressionGoals(
                maxWidth: opts.maxWidth,
                maxFileSizeKB: opts.maxFileSizeKB
            )
            let chroma = ChromaSubsampling(rawValue: opts.chromaSubsamplingRaw) ?? .auto
            let pngMode = PNGOutputMode(rawValue: opts.pngOutputModeRaw) ?? .lossless
            do {
                let r = try await engine.compress(
                    source: inURL,
                    format: format,
                    goals: goals,
                    stripMetadata: opts.stripMetadata,
                    outputURL: desiredOut,
                    originalsAction: .keep,
                    backupFolderURL: nil,
                    isURLDownloadSource: false,
                    smartQuality: smartQ,
                    contentTypeHint: opts.contentTypeHint,
                    preclassifiedContent: classified,
                    parallelCompressionLimit: opts.parallelLimit,
                    collisionNamingStyle: opts.collisionStyle,
                    collisionCustomPattern: opts.collisionCustomPattern,
                    qualityOverride: opts.quality,
                    chromaSubsampling: chroma,
                    webpLossless: opts.webpLossless,
                    pngOutputMode: pngMode,
                    progressHandler: nil
                )
                let out = r.outputSize
                let pct: Double? = r.originalSize > 0
                    ? (1.0 - Double(out) / Double(r.originalSize)) * 100.0
                    : nil
                fileResults.append(
                    DinkyImageCompressFileResult(
                        input: p,
                        output: r.outputURL.path,
                        originalBytes: r.originalSize,
                        outputBytes: out,
                        savingsPercent: pct,
                        detectedContent: r.detectedContentType?.rawValue,
                        appliedChromaSubsampling: r.appliedChromaSubsampling,
                        appliedWebpLossless: format == .webp ? r.appliedWebpLossless : nil,
                        appliedPngOutputMode: r.appliedPngOutputMode,
                        error: nil
                    )
                )
            } catch {
                anyFailed = true
                fileResults.append(
                    DinkyImageCompressFileResult(
                        input: p,
                        output: nil,
                        originalBytes: origSize,
                        outputBytes: nil,
                        savingsPercent: nil,
                        detectedContent: classified?.rawValue,
                        error: error.localizedDescription
                    )
                )
            }
        }

        return (anyFailed ? 1 : 0, fileResults)
    }

    private static func printResults(opts: DinkyCompressOptions, code: Int32, fileResults: [DinkyImageCompressFileResult]) {
        if opts.json {
            let payload = DinkyImageCompressResponse(
                schema: dinkyImageCompressResultSchema,
                success: code == 0,
                results: fileResults
            )
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let d = try? enc.encode(payload), let s = String(data: d, encoding: .utf8) {
                print(s)
            }
        } else {
            for fr in fileResults {
                if let e = fr.error {
                    print("\(fr.input): error: \(e)")
                } else if let outP = fr.output, let outB = fr.outputBytes {
                    let pct = fr.savingsPercent.map { String(format: "%.1f%%", $0) } ?? "0%"
                    print("\(fr.input) -> \(outP)  (\(fr.originalBytes) → \(outB) bytes, saved \(pct))")
                }
            }
        }
    }

    private static func resolveFormat(
        from: String,
        sourceURL: URL,
        classified: ContentType?
    ) throws -> CompressionFormat {
        let f = from.lowercased()
        if f == "auto" {
            let ct = classified ?? ContentClassifier.classify(sourceURL)
            return ct == .photo ? .avif : .webp
        }
        guard let c = CompressionFormat(rawValue: f) else {
            throw DinkyCLIParseError(message: "unknown --format: \(from)")
        }
        return c
    }
}
