import DinkyCoreImage
import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct CompressionResult {
    let outputURL: URL
    let originalSize: Int64
    let outputSize: Int64
    var originalRecoveryURL: URL? = nil
    let detectedContentType: ContentType?
    var videoDuration: Double? = nil
    var videoContentType: VideoContentType? = nil
    var videoIsHDR: Bool = false
    var videoEffectiveCodec: VideoCodecFamily? = nil
    var usedFirstFrameOnly: Bool = false
}

enum CompressionError: LocalizedError {
    case binaryNotFound(String)
    case processFailed(Int32, String)
    case outputMissing
    case pdfLoadFailed
    case pdfPageRenderFailed(Int)
    case videoExportFailed(String)
    case videoExportSessionUnavailable
    case heicTranscodeFailed
    case heicEncodeFailed
    case imageResizeFailed
    case imageReadFailed
    case imageWriteFailed

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let n): return "Binary '\(n)' not found in app bundle."
        case .processFailed(let c, let e): return "Process exited \(c): \(e)"
        case .outputMissing: return "Output file was not created."
        case .pdfLoadFailed: return "Could not open the PDF file."
        case .pdfPageRenderFailed(let p): return "Could not render page \(p + 1)."
        case .videoExportFailed(let msg): return "Video export failed: \(msg)"
        case .videoExportSessionUnavailable: return "Could not create export session for this video."
        case .heicTranscodeFailed: return "Could not read or convert this HEIC/HEIF image."
        case .heicEncodeFailed:
            return String(localized: "Could not encode this image as HEIC.", comment: "Error when HEIC export fails.")
        case .imageResizeFailed: return "Could not resize this image for the width limit."
        case .imageReadFailed:
            return String(localized: "Could not read image data from this file.", comment: "Error when ImageIO fails to read source.")
        case .imageWriteFailed:
            return String(localized: "Could not write the compressed image file.", comment: "Error when ImageIO fails to finalize output.")
        }
    }
}

actor CompressionService {
    static let shared = CompressionService()
    private let binDir: URL
    private let imagePipeline: DinkyImageCompression

    private init() {
        guard let url = Bundle.main.resourceURL else {
            fatalError("Bundle.main.resourceURL is nil — app bundle is malformed")
        }
        self.binDir = url
        self.imagePipeline = DinkyImageCompression(binDirectory: url)
    }

    func compress(
        source: URL,
        format: CompressionFormat,
        goals: CompressionGoals,
        stripMetadata: Bool,
        outputURL: URL,
        originalsAction: OriginalsAction = .keep,
        backupFolderURL: URL? = nil,
        isURLDownloadSource: Bool = false,
        smartQuality: Bool = false,
        contentTypeHint: String = "auto",
        preclassifiedContent: ContentType? = nil,
        parallelCompressionLimit: Int = 3,
        collisionNamingStyle: CollisionNamingStyle = .finderDuplicate,
        collisionCustomPattern: String = "",
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> CompressionResult {
        do {
            let r = try await imagePipeline.compress(
                source: source,
                format: format,
                goals: goals,
                stripMetadata: stripMetadata,
                outputURL: outputURL,
                originalsAction: originalsAction,
                backupFolderURL: backupFolderURL,
                isURLDownloadSource: isURLDownloadSource,
                smartQuality: smartQuality,
                contentTypeHint: contentTypeHint,
                preclassifiedContent: preclassifiedContent,
                parallelCompressionLimit: parallelCompressionLimit,
                collisionNamingStyle: collisionNamingStyle,
                collisionCustomPattern: collisionCustomPattern,
                qualityOverride: nil,
                progressHandler: progressHandler
            )
            return CompressionResult(
                outputURL: r.outputURL,
                originalSize: r.originalSize,
                outputSize: r.outputSize,
                originalRecoveryURL: r.originalRecoveryURL,
                detectedContentType: r.detectedContentType,
                usedFirstFrameOnly: r.usedFirstFrameOnly
            )
        } catch let e as DinkyImageCompressionError {
            throw e.asAppError()
        }
    }

    // MARK: - Process runner (qpdf + other CLIs)

    private func run(_ binary: URL, args: [String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = binary
            process.arguments     = args

            var env = ProcessInfo.processInfo.environment
            let existing = env["DYLD_LIBRARY_PATH"].flatMap { $0.isEmpty ? nil : $0 }
            env["DYLD_LIBRARY_PATH"] = ["/opt/homebrew/lib", existing].compactMap { $0 }.joined(separator: ":")
            process.environment = env

            let errPipe = Pipe()
            process.standardError  = errPipe
            process.standardOutput = Pipe()
            process.terminationHandler = { p in
                let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                    encoding: .utf8) ?? ""
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: CompressionError.processFailed(p.terminationStatus, stderr))
                }
            }
            do    { try process.run() }
            catch { cont.resume(throwing: error) }
        }
    }

    // MARK: - PDF compression

    private func qpdfBinaryURL() -> URL? {
        let u = binDir.appendingPathComponent("qpdf")
        guard FileManager.default.isExecutableFile(atPath: u.path) else { return nil }
        return u
    }

    /// Structural/stream optimization via bundled `qpdf` (smaller output only when `originalSize` check passes in caller).
    private func runQpdfPreserve(
        source: URL,
        output: URL,
        stripMetadata: Bool,
        binary: URL,
        extraQpdfArgs: [String]
    ) async throws {
        var args: [String] = [
            source.path,
            output.path,
            "--object-streams=generate",
            "--compress-streams=y",
            "--recompress-flate",
            "--compression-level=9",
            "--remove-unreferenced-resources=yes",
            "--coalesce-contents",
            "--optimize-images",
        ]
        args.append(contentsOf: extraQpdfArgs)
        if stripMetadata {
            args.append(contentsOf: ["--remove-metadata", "--remove-info"])
        }
        do {
            try await run(binary, args: args)
        } catch {
            let withoutJpeg = extraQpdfArgs.filter { !$0.hasPrefix("--jpeg-quality=") }
            var fallback = [
                source.path,
                output.path,
                "--object-streams=generate",
                "--compress-streams=y",
                "--recompress-flate",
                "--compression-level=9",
                "--remove-unreferenced-resources=yes",
                "--coalesce-contents",
            ]
            fallback.append(contentsOf: withoutJpeg)
            if stripMetadata {
                fallback.append(contentsOf: ["--remove-metadata", "--remove-info"])
            }
            try await run(binary, args: fallback)
        }
    }

    func compressPDF(
        source: URL,
        outputMode: PDFOutputMode,
        quality: PDFQuality,
        grayscale: Bool,
        stripMetadata: Bool,
        outputURL: URL,
        flattenLastResort: Bool = false,
        flattenUltra: Bool = false,
        preserveQpdfSteps: [PDFPreserveQpdfStep] = [.base],
        targetBytes: Int64? = nil,
        resolutionDownsampling: Bool = false,
        collisionNamingStyle: CollisionNamingStyle = .finderDuplicate,
        collisionCustomPattern: String = "",
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> CompressionResult {
        let tPDF = CFAbsoluteTimeGetCurrent()
        let originalSize = fileSize(source)

        var effOut = OutputPathUniqueness.uniqueOutputURL(
            desired: outputURL,
            sourceURL: source,
            style: collisionNamingStyle,
            customPattern: collisionCustomPattern
        )

        try FileManager.default.createDirectory(
            at: effOut.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var winningPreserveQpdfStepId: String? = nil
        switch outputMode {
        case .preserveStructure:
            progressHandler?(0.06)
            let fm = FileManager.default
            var usedQpdf = false
            if let qpdfBin = qpdfBinaryURL() {
                let steps = preserveQpdfSteps.isEmpty ? [PDFPreserveQpdfStep.base] : preserveQpdfSteps
                let n = max(steps.count, 1)
                var bestQpdfURL: URL? = nil
                var bestQpdfSize: Int64 = originalSize
                for (idx, step) in steps.enumerated() {
                    let qpdfTmp = fm.temporaryDirectory.appendingPathComponent("dinky_qpdf_\(UUID().uuidString).pdf")
                    progressHandler?(0.06 + 0.08 * Float(idx + 1) / Float(n))
                    do {
                        try await runQpdfPreserve(
                            source: source,
                            output: qpdfTmp,
                            stripMetadata: stripMetadata,
                            binary: qpdfBin,
                            extraQpdfArgs: step.extraArgs
                        )
                        let qSz = fileSize(qpdfTmp)
                        if qSz > 0 && qSz < bestQpdfSize {
                            if let prev = bestQpdfURL { try? fm.removeItem(at: prev) }
                            bestQpdfURL = qpdfTmp
                            bestQpdfSize = qSz
                            winningPreserveQpdfStepId = step.id
                            // Without a size target, first improvement is good enough.
                            // With a target, keep trying steps until we're under it.
                            let targetMet = targetBytes.map { qSz <= $0 } ?? true
                            if targetMet { break }
                        } else {
                            try? fm.removeItem(at: qpdfTmp)
                        }
                    } catch {
                        try? fm.removeItem(at: qpdfTmp)
                        continue
                    }
                }
                if let best = bestQpdfURL {
                    effOut = try OutputPathUniqueness.moveTempItemToUniqueOutput(
                        temp: best,
                        desiredOutput: effOut,
                        sourceURL: source,
                        style: collisionNamingStyle,
                        customPattern: collisionCustomPattern,
                        fileManager: fm
                    )
                    usedQpdf = true
                }
            }
            if !usedQpdf {
                let ph = progressHandler
                effOut = try await Task.detached {
                    try PDFCompressor.preserveStructure(
                        source: source,
                        stripMetadata: stripMetadata,
                        outputURL: effOut,
                        collisionSourceURL: source,
                        collisionNamingStyle: collisionNamingStyle,
                        collisionCustomPattern: collisionCustomPattern,
                        progress: ph
                    )
                }.value
            } else {
                progressHandler?(1)
            }

            if resolutionDownsampling, fm.fileExists(atPath: effOut.path),
               let structureDoc = PDFDocument(url: effOut) {
                let dsURL = fm.temporaryDirectory.appendingPathComponent("dinky_pdf_ds_\(UUID().uuidString).pdf")
                if let mixed = PDFImageDownsampler.downsample(source: source, structureDoc: structureDoc, stripMetadata: stripMetadata),
                   mixed.write(to: dsURL) {
                    let dsSz = fileSize(dsURL)
                    if dsSz > 0 && dsSz < fileSize(effOut) {
                        try? fm.removeItem(at: effOut)
                        try fm.moveItem(at: dsURL, to: effOut)
                    } else {
                        try? fm.removeItem(at: dsURL)
                    }
                }
            }
        case .flattenPages:
            effOut = OutputPathUniqueness.refreshUniqueOutput(
                currentCandidate: effOut,
                sourceURL: source,
                style: collisionNamingStyle,
                customPattern: collisionCustomPattern
            )
            let ph = progressHandler
            let ultra = flattenUltra
            let lastResort = flattenLastResort && !ultra
            try await Task.detached {
                try PDFCompressor.compressFlattened(
                    source: source, quality: quality, grayscale: grayscale,
                    stripMetadata: stripMetadata, outputURL: effOut,
                    lastResortFlatten: lastResort,
                    ultraLastResortFlatten: ultra,
                    progress: ph
                )
            }.value
        }
        CompressionTiming.logPhase("pdf.compress.\(outputMode == .flattenPages ? "flatten" : "preserve")", startedAt: tPDF)

        guard FileManager.default.fileExists(atPath: effOut.path) else {
            throw CompressionError.outputMissing
        }

        let outSz = fileSize(effOut)
        let chainIds = preserveQpdfSteps.isEmpty ? "base" : preserveQpdfSteps.map(\.id).joined(separator: ">")
        PDFCompressionMetrics.logOutcome(
            outputMode: outputMode,
            originalBytes: originalSize,
            outputBytes: outSz,
            flattenLastResort: flattenLastResort,
            flattenUltra: flattenUltra,
            preserveQpdfChain: outputMode == .preserveStructure ? chainIds : nil,
            preserveQpdfWinningStep: winningPreserveQpdfStepId
        )

        return CompressionResult(outputURL: effOut,
                                 originalSize: originalSize,
                                 outputSize: outSz,
                                 detectedContentType: nil)
    }

    // MARK: - Video compression

    func compressVideo(
        source: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        maxResolutionLines: Int? = nil,
        outputURL: URL,
        videoContentType: VideoContentType? = nil,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> CompressionResult {
        try await compressVideo(
            asset: VideoCompressor.makeURLAsset(url: source),
            source: source,
            quality: quality,
            codec: codec,
            removeAudio: removeAudio,
            maxResolutionLines: maxResolutionLines,
            outputURL: outputURL,
            videoContentType: videoContentType,
            progressHandler: progressHandler
        )
    }

    /// Reuses a pre-built ``AVURLAsset`` (e.g. shared with ``VideoSmartQuality``) to avoid reopening the file.
    /// - Parameter maxResolutionLines: Optional output-height cap (mirrors images' Max width). `nil` keeps source resolution.
    /// - Parameter videoContentType: When already known (Smart Quality classified it), surfaced in the result for the UI chip.
    func compressVideo(
        asset: AVURLAsset,
        source: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        maxResolutionLines: Int? = nil,
        outputURL: URL,
        videoContentType: VideoContentType? = nil,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> CompressionResult {
        let originalSize = fileSize(source)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let resolved = try await VideoCompressor.compress(
            asset: asset,
            sourceForMetadata: source,
            quality: quality,
            codec: codec,
            removeAudio: removeAudio,
            maxResolutionLines: maxResolutionLines,
            outputURL: outputURL,
            progressHandler: progressHandler
        )

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CompressionError.outputMissing
        }

        return CompressionResult(
            outputURL: outputURL,
            originalSize: originalSize,
            outputSize: fileSize(outputURL),
            detectedContentType: nil,
            videoDuration: resolved.durationSeconds,
            videoContentType: videoContentType,
            videoIsHDR: resolved.isHDR,
            videoEffectiveCodec: resolved.codec
        )
    }

    // MARK: - Helpers

    private func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }
}
