import DinkyCoreImage
import DinkyCorePDF
import DinkyCoreShared
import Foundation

public enum DinkyPdfCompressCommand: Sendable {
    private static func cliPdfMode(_ m: PDFOutputMode) -> String {
        switch m {
        case .preserveStructure: return "preserve"
        case .flattenPages: return "flatten"
        }
    }

    public static func run(_ args: [String]) async -> (Int32, Int) {
        let parse: DinkyPdfCompressParseResult
        do {
            parse = try DinkyPdfCompressArgParser.parse(args)
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
            presetUsed = try DinkyCLIPresetSupport.applyPDFPresetIfNeeded(
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
            FileHandle.standardError.write(Data("dinky compress-pdf: no input files (see: dinky help)\n".utf8))
            return (1, 0)
        }

        guard let bin = DinkyEncoderPath.resolveBinDirectory() else {
            FileHandle.standardError.write(
                Data(
                    "dinky: could not find tools directory. Set DINKY_BIN to a folder with cwebp, avifenc, oxipng (and qpdf for best preserve-mode results), or use ./bin next to the dinky binary.\n"
                        .utf8
                )
            )
            return (1, 0)
        }
        let qpdf = DinkyEncoderPath.qpdfExecutable(inBinDirectory: bin)

        let (code, results) = await runWithOptions(opts, paths: paths, preset: presetUsed, qpdfBinary: qpdf)
        printResults(opts: opts, code: code, results: results)
        return (code, results.count)
    }

    public static func runWithOptions(
        _ opts: DinkyPdfCompressOptions,
        paths: [String],
        preset: CompressionPreset? = nil,
        qpdfBinary: URL? = nil
    ) async -> (Int32, [DinkyPdfCompressFileResult]) {
        var fileResults: [DinkyPdfCompressFileResult] = []
        var anyFailed = false

        for p in paths {
            let inURL = URL(fileURLWithPath: p, isDirectory: false).standardizedFileURL
            let origSize: Int64 = (try? inURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
            guard FileManager.default.isReadableFile(atPath: inURL.path) else {
                anyFailed = true
                fileResults.append(
                    DinkyPdfCompressFileResult(
                        input: p,
                        output: nil,
                        originalBytes: origSize,
                        outputBytes: nil,
                        savingsPercent: nil,
                        mode: cliPdfMode(opts.outputMode),
                        qpdfStepUsed: nil,
                        appliedDownsampling: nil,
                        error: "No such file or not readable"
                    )
                )
                continue
            }

            let outDir: URL
            do {
                if let d = opts.outputDir {
                    outDir = d.standardizedFileURL
                } else {
                    outDir = try DinkyCLIPresetSupport.outputDirectoryForSourceURL(preset: preset, source: inURL)
                        .standardizedFileURL
                }
            } catch let e as DinkyCLIPresetError {
                anyFailed = true
                fileResults.append(
                    DinkyPdfCompressFileResult(
                        input: p,
                        output: nil,
                        originalBytes: origSize,
                        outputBytes: nil,
                        savingsPercent: nil,
                        mode: cliPdfMode(opts.outputMode),
                        qpdfStepUsed: nil,
                        appliedDownsampling: nil,
                        error: e.message
                    )
                )
                continue
            } catch {
                anyFailed = true
                fileResults.append(
                    DinkyPdfCompressFileResult(
                        input: p,
                        output: nil,
                        originalBytes: origSize,
                        outputBytes: nil,
                        savingsPercent: nil,
                        mode: cliPdfMode(opts.outputMode),
                        qpdfStepUsed: nil,
                        appliedDownsampling: nil,
                        error: error.localizedDescription
                    )
                )
                continue
            }

            try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let outName = DinkyCLIPresetSupport.outputFilenameStem(preset: preset, source: inURL, mediaExtension: "pdf")
            let baseDesired = outDir.appendingPathComponent(outName, isDirectory: false)
            let uniqueDesired = OutputPathUniqueness.uniqueOutputURL(
                desired: baseDesired,
                sourceURL: inURL,
                style: opts.collisionStyle,
                customPattern: opts.collisionCustomPattern
            )

            var pdfQuality = opts.quality
            var monoLikelihood: Double = 0
            if opts.outputMode == .flattenPages, opts.smartQuality {
                let inferred = PDFSmartQuality.inferFlattenQualityAndMono(
                    url: inURL,
                    fallback: opts.quality,
                    autoGrayscaleMonoScans: opts.autoGrayscaleMonoScans
                )
                pdfQuality = inferred.quality
                monoLikelihood = inferred.monoLikelihood
            } else if opts.smartQuality, opts.outputMode == .preserveStructure {
                pdfQuality = PDFSmartQuality.inferQuality(url: inURL, fallback: opts.quality)
            }

            let effectiveGrayscale: Bool = {
                guard opts.outputMode == .flattenPages else { return opts.grayscale }
                if opts.grayscale { return true }
                if opts.smartQuality, opts.autoGrayscaleMonoScans, monoLikelihood >= 0.5 { return true }
                return false
            }()

            let preserveSteps: [PDFPreserveQpdfStep] = {
                guard opts.outputMode == .preserveStructure else { return [.base] }
                if opts.preserveExperimental != .none {
                    return [PDFPreserveQpdfStep.from(experimental: opts.preserveExperimental)]
                }
                return PDFPreserveQpdfStepsResolver.steps(
                    sourceURL: inURL,
                    preserveExperimental: opts.preserveExperimental,
                    smartQuality: opts.smartQuality
                )
            }()

            let targetBytes: Int64? = opts.targetKB.map { Int64($0) * 1024 }

            // Only a size target steps flatten below the chosen quality.
            let qualities: [PDFQuality] =
                opts.outputMode == .flattenPages && targetBytes != nil
                ? PDFQuality.flattenQualityFallbackChain(startingAt: pdfQuality)
                : [pdfQuality]

            var best: DinkyPDFCompressResult?
            var attemptFailed: String?
            for q in qualities {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("dinky_pdf_try_\(q.rawValue)_\(UUID().uuidString).pdf")
                do {
                    let r = try await DinkyPDFPipeline.compress(
                        source: inURL,
                        outputMode: opts.outputMode,
                        quality: q,
                        grayscale: effectiveGrayscale,
                        stripMetadata: opts.stripMetadata,
                        outputURL: tmp,
                        flattenLastResort: false,
                        flattenUltra: false,
                        preserveQpdfSteps: preserveSteps,
                        targetBytes: targetBytes,
                        resolutionDownsampling: opts.outputMode == .preserveStructure && opts.resolutionDownsampling,
                        collisionNamingStyle: opts.collisionStyle,
                        collisionCustomPattern: opts.collisionCustomPattern,
                        qpdfBinary: qpdfBinary,
                        progressHandler: nil
                    )
                    guard r.outputSize < origSize else {
                        try? FileManager.default.removeItem(at: r.outputURL)
                        continue
                    }
                    if best == nil || r.outputSize < best!.outputSize {
                        if let b = best { try? FileManager.default.removeItem(at: b.outputURL) }
                        best = r
                    } else {
                        try? FileManager.default.removeItem(at: r.outputURL)
                    }
                    if targetBytes == nil { break }
                    if let t = targetBytes, r.outputSize <= t { break }
                } catch {
                    attemptFailed = error.localizedDescription
                    break
                }
            }

            if let err = attemptFailed {
                anyFailed = true
                fileResults.append(
                    DinkyPdfCompressFileResult(
                        input: p,
                        output: nil,
                        originalBytes: origSize,
                        outputBytes: nil,
                        savingsPercent: nil,
                        mode: cliPdfMode(opts.outputMode),
                        qpdfStepUsed: nil,
                        appliedDownsampling: nil,
                        error: err
                    )
                )
                continue
            }

            guard let result = best else {
                anyFailed = true
                fileResults.append(
                    DinkyPdfCompressFileResult(
                        input: p,
                        output: nil,
                        originalBytes: origSize,
                        outputBytes: nil,
                        savingsPercent: nil,
                        mode: cliPdfMode(opts.outputMode),
                        qpdfStepUsed: nil,
                        appliedDownsampling: nil,
                        error: "Could not produce a smaller PDF (try flatten mode or a different file)"
                    )
                )
                continue
            }

            let finalURL = uniqueDesired
            do {
                try FileManager.default.createDirectory(
                    at: finalURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try? FileManager.default.removeItem(at: finalURL)
                }
                try FileManager.default.moveItem(at: result.outputURL, to: finalURL)
            } catch {
                anyFailed = true
                try? FileManager.default.removeItem(at: result.outputURL)
                fileResults.append(
                    DinkyPdfCompressFileResult(
                        input: p,
                        output: nil,
                        originalBytes: origSize,
                        outputBytes: nil,
                        savingsPercent: nil,
                        mode: cliPdfMode(opts.outputMode),
                        qpdfStepUsed: result.winningPreserveQpdfStepId,
                        appliedDownsampling: result.appliedResolutionDownsampling,
                        error: error.localizedDescription
                    )
                )
                continue
            }

            let outBytes: Int64 = (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? result.outputSize
            let pct: Double? = origSize > 0 ? (1.0 - Double(outBytes) / Double(origSize)) * 100.0 : nil
            fileResults.append(
                DinkyPdfCompressFileResult(
                    input: p,
                    output: finalURL.path,
                    originalBytes: origSize,
                    outputBytes: outBytes,
                    savingsPercent: pct,
                    mode: cliPdfMode(opts.outputMode),
                    qpdfStepUsed: result.winningPreserveQpdfStepId,
                    appliedDownsampling: result.appliedResolutionDownsampling,
                    error: nil
                )
            )
        }

        return (anyFailed ? 1 : 0, fileResults)
    }

    private static func printResults(opts: DinkyPdfCompressOptions, code: Int32, results: [DinkyPdfCompressFileResult]) {
        if opts.json {
            let payload = DinkyPdfCompressResponse(
                schema: dinkyPdfCompressResultSchema,
                success: code == 0,
                results: results
            )
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let d = try? enc.encode(payload), let s = String(data: d, encoding: .utf8) {
                print(s)
            }
        } else {
            for fr in results {
                if let e = fr.error {
                    print("\(fr.input): error: \(e)")
                } else if let outP = fr.output, let outB = fr.outputBytes {
                    let pct = fr.savingsPercent.map { String(format: "%.1f%%", $0) } ?? "0%"
                    print("\(fr.input) -> \(outP)  (\(fr.originalBytes) → \(outB) bytes, saved \(pct))")
                }
            }
        }
    }
}
