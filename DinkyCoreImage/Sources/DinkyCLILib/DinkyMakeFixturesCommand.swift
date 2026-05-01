import AVFoundation
import CoreGraphics
import CoreText
import DinkyCoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Public API

public enum DinkyMakeFixturesCommand {
    public static let manifestSchema = "dinky.fixtures.manifest/1.0.0"

    /// Developer-only: generate local media fixtures for testing Dinky (GUI / CLI / watch folder).
    public static func run(_ args: [String]) async -> (Int32, Int) {
        let config: MakeFixturesConfig
        do {
            config = try parseArgs(args)
        } catch let e as DinkyCLIParseError {
            FileHandle.standardError.write(Data("dinky: \(e.message)\n".utf8))
            return (1, 0)
        } catch {
            FileHandle.standardError.write(Data("dinky: \(error.localizedDescription)\n".utf8))
            return (1, 0)
        }

        let outURL: URL
        do {
            outURL = try resolveOutputDirectory(config: config)
        } catch {
            FileHandle.standardError.write(Data("dinky make-fixtures: \(error.localizedDescription)\n".utf8))
            return (1, 0)
        }

        var manifest = FixtureManifest(
            schema: Self.manifestSchema,
            outputDirectory: outURL.path,
            entries: []
        )

        let bin = DinkyEncoderPath.resolveBinDirectory()
        let baseSeed = config.seed == 0 ? 0xC0FFEE_BABE_BEEF : config.seed

        if config.types.contains(.images) {
            await generateImages(
                into: outURL,
                count: config.count,
                baseSeed: baseSeed,
                binDirectory: bin,
                manifest: &manifest
            )
        }
        if config.types.contains(.video) {
            await generateVideos(
                into: outURL,
                count: config.count,
                baseSeed: baseSeed,
                manifest: &manifest
            )
        }
        if config.types.contains(.pdf) {
            generatePDFs(
                into: outURL,
                count: config.count,
                baseSeed: baseSeed,
                manifest: &manifest
            )
        }

        let manifestURL = outURL.appendingPathComponent("manifest.json", isDirectory: false)
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys, .prettyPrinted]
            try enc.encode(manifest).write(to: manifestURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("dinky make-fixtures: could not write manifest: \(error.localizedDescription)\n".utf8))
            return (1, manifest.entries.count)
        }

        if config.json {
            if let data = try? JSONEncoder().encode(manifest), let s = String(data: data, encoding: .utf8) {
                print(s)
            }
        } else {
            print("dinky make-fixtures: wrote \(manifest.entries.count) fixture entries (+ manifest.json) under \(outURL.path)")
        }

        return (0, manifest.entries.count)
    }

    // MARK: - Config & manifest types

    public enum FixtureMediaType: String, CaseIterable, Sendable, Codable {
        case images
        case video
        case pdf
    }

    public struct MakeFixturesConfig: Sendable {
        public var outputDir: URL?
        public var types: Set<FixtureMediaType>
        public var count: Int
        public var seed: UInt64
        public var overwrite: Bool
        public var json: Bool

        public init(
            outputDir: URL?,
            types: Set<FixtureMediaType>,
            count: Int,
            seed: UInt64,
            overwrite: Bool,
            json: Bool
        ) {
            self.outputDir = outputDir
            self.types = types
            self.count = count
            self.seed = seed
            self.overwrite = overwrite
            self.json = json
        }
    }

    public struct FixtureManifest: Codable, Sendable {
        public var schema: String
        public var outputDirectory: String
        public var entries: [FixtureEntry]
    }

    public struct FixtureEntry: Codable, Sendable {
        public var path: String
        public var family: String
        public var format: String?
        public var bytes: Int64
        public var note: String
    }

    // MARK: - Argument parsing

    static func parseArgs(_ args: [String]) throws -> MakeFixturesConfig {
        var outputDir: URL?
        var typeList: [FixtureMediaType] = Array(FixtureMediaType.allCases)
        var count = 1
        var seed: UInt64 = 0
        var overwrite = false
        var json = false

        var i = 0
        let n = args.count
        while i < n {
            let a = args[i]
            if a == "-h" || a == "--help" {
                throw DinkyCLIParseError(
                    message: "dinky make-fixtures [--output-dir <path>] [--types images,video,pdf] [--count 1..20] [--seed <u64>] [--overwrite] [--json]"
                )
            }
            switch a {
            case "--output-dir", "-o":
                i += 1
                guard i < n else { throw DinkyCLIParseError(message: "missing value for --output-dir") }
                outputDir = URL(fileURLWithPath: args[i], isDirectory: true).standardizedFileURL
            case "--types":
                i += 1
                guard i < n else { throw DinkyCLIParseError(message: "missing value for --types") }
                let parts = args[i].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
                var set = Set<FixtureMediaType>()
                for p in parts {
                    switch p {
                    case "images", "image": set.insert(.images)
                    case "video", "videos": set.insert(.video)
                    case "pdf", "pdfs": set.insert(.pdf)
                    default: throw DinkyCLIParseError(message: "unknown media type in --types: \(p)")
                    }
                }
                guard !set.isEmpty else { throw DinkyCLIParseError(message: "--types produced empty set") }
                typeList = FixtureMediaType.allCases.filter { set.contains($0) }
            case "--count":
                i += 1
                guard i < n, let c = Int(args[i]), (1...MakeFixtures.countMax).contains(c) else {
                    throw DinkyCLIParseError(message: "--count must be an integer 1...\(MakeFixtures.countMax)")
                }
                count = c
            case "--seed":
                i += 1
                guard i < n, let s = UInt64(args[i]) else {
                    throw DinkyCLIParseError(message: "--seed must be a non-negative integer (UInt64)")
                }
                seed = s
            case "--overwrite":
                overwrite = true
            case "--json":
                json = true
            default:
                throw DinkyCLIParseError(message: "unknown flag: \(a)")
            }
            i += 1
        }

        return MakeFixturesConfig(
            outputDir: outputDir,
            types: Set(typeList),
            count: count,
            seed: seed,
            overwrite: overwrite,
            json: json
        )
    }

    // MARK: - Output directory

    private static func resolveOutputDirectory(config: MakeFixturesConfig) throws -> URL {
        let fm = FileManager.default
        let base: URL
        if let o = config.outputDir {
            base = o
        } else {
            let cwd = fm.currentDirectoryPath
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            base = URL(fileURLWithPath: cwd, isDirectory: true)
                .appendingPathComponent(".dinky-fixtures", isDirectory: true)
                .appendingPathComponent(stamp, isDirectory: true)
        }

        if config.overwrite {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            return base.standardizedFileURL
        }

        if !fm.fileExists(atPath: base.path) {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            return base.standardizedFileURL
        }

        // Unique suffix if directory exists
        var suffix = 1
        var candidate = base
        while fm.fileExists(atPath: candidate.path) {
            candidate = URL(fileURLWithPath: base.path + "-\(suffix)", isDirectory: true).standardizedFileURL
            suffix += 1
        }
        try fm.createDirectory(at: candidate, withIntermediateDirectories: true)
        return candidate.standardizedFileURL
    }

    // MARK: - Images

    private static func generateImages(
        into dir: URL,
        count: Int,
        baseSeed: UInt64,
        binDirectory: URL?,
        manifest: inout FixtureManifest
    ) async {
        let nativeFormats: [(ext: String, type: CFString, note: String)] = [
            ("png", UTType.png.identifier as CFString, "ImageIO PNG"),
            ("jpg", UTType.jpeg.identifier as CFString, "ImageIO JPEG"),
            ("tiff", UTType.tiff.identifier as CFString, "ImageIO TIFF"),
            ("bmp", UTType.bmp.identifier as CFString, "ImageIO BMP"),
            ("heic", UTType.heic.identifier as CFString, "ImageIO HEIC (if available on this OS)"),
        ]

        for batch in 0..<count {
            let batchSeed = baseSeed &+ UInt64(batch) &* 0x9E37_79B9_7F4A_7C15
            let w = 320 + (batch * 47) % 200
            let h = 240 + (batch * 31) % 180
            guard let cgImage = MakeFixtures.makeSampleCGImage(width: w, height: h, seed: batchSeed) else { continue }

            for nf in nativeFormats {
                let name = "dinky-fixture-img-b\(batch).\(nf.ext)"
                let url = dir.appendingPathComponent(name, isDirectory: false)
                do {
                    try MakeFixtures.writeCGImage(cgImage, to: url, type: nf.type, lossyQuality: nf.ext == "jpg" ? 0.82 : nil)
                    manifest.entries.append(entryForFile(url: url, family: "images", format: nf.ext, note: nf.note))
                } catch {
                    manifest.entries.append(
                        FixtureEntry(
                            path: url.path,
                            family: "images",
                            format: nf.ext,
                            bytes: 0,
                            note: "skipped: \(error.localizedDescription)"
                        )
                    )
                }
            }

            // WebP / AVIF via encoders
            let pngName = "dinky-fixture-img-b\(batch)-src.png"
            let pngURL = dir.appendingPathComponent(pngName, isDirectory: false)
            do {
                try MakeFixtures.writeCGImage(cgImage, to: pngURL, type: UTType.png.identifier as CFString, lossyQuality: nil)
            } catch {
                continue
            }
            defer { try? FileManager.default.removeItem(at: pngURL) }

            if let bin = binDirectory {
                let webpURL = dir.appendingPathComponent("dinky-fixture-img-b\(batch).webp", isDirectory: false)
                do {
                    try MakeFixtures.runEncoder(
                        bin: bin,
                        name: "cwebp",
                        args: ["-q", "80", "-preset", "picture", "-metadata", "all", pngURL.path, "-o", webpURL.path]
                    )
                    manifest.entries.append(entryForFile(url: webpURL, family: "images", format: "webp", note: "cwebp from PNG"))
                } catch {
                    manifest.entries.append(
                        FixtureEntry(path: webpURL.path, family: "images", format: "webp", bytes: 0, note: "skipped: \(error.localizedDescription)")
                    )
                }

                let avifURL = dir.appendingPathComponent("dinky-fixture-img-b\(batch).avif", isDirectory: false)
                do {
                    try MakeFixtures.runEncoder(
                        bin: bin,
                        name: "avifenc",
                        args: ["--speed", "6", "--jobs", "2", "--qcolor", "70", "--qalpha", "80", pngURL.path, avifURL.path]
                    )
                    manifest.entries.append(entryForFile(url: avifURL, family: "images", format: "avif", note: "avifenc from PNG"))
                } catch {
                    manifest.entries.append(
                        FixtureEntry(path: avifURL.path, family: "images", format: "avif", bytes: 0, note: "skipped: \(error.localizedDescription)")
                    )
                }
            } else {
                manifest.entries.append(
                    FixtureEntry(
                        path: dir.appendingPathComponent("dinky-fixture-img-b\(batch).webp", isDirectory: false).path,
                        family: "images",
                        format: "webp",
                        bytes: 0,
                        note: "skipped: DINKY_BIN not set / encoders not found for cwebp"
                    )
                )
                manifest.entries.append(
                    FixtureEntry(
                        path: dir.appendingPathComponent("dinky-fixture-img-b\(batch).avif", isDirectory: false).path,
                        family: "images",
                        format: "avif",
                        bytes: 0,
                        note: "skipped: DINKY_BIN not set / encoders not found for avifenc"
                    )
                )
            }
        }
    }

    private static func entryForFile(url: URL, family: String, format: String, note: String) -> FixtureEntry {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        return FixtureEntry(path: url.path, family: family, format: format, bytes: bytes, note: note)
    }

    // MARK: - Video

    private static func generateVideos(
        into dir: URL,
        count: Int,
        baseSeed: UInt64,
        manifest: inout FixtureManifest
    ) async {
        for batch in 0..<count {
            let seed = baseSeed &+ UInt64(batch) &* 0x85EB_CA6B
            let movURL = dir.appendingPathComponent("dinky-fixture-vid-b\(batch).mov", isDirectory: false)
            let mp4URL = dir.appendingPathComponent("dinky-fixture-vid-b\(batch).mp4", isDirectory: false)
            do {
                try await MakeFixtures.writeSyntheticVideo(url: movURL, fileType: .mov, durationSeconds: 0.75, seed: seed)
                manifest.entries.append(
                    entryForFile(url: movURL, family: "video", format: "mov", note: "synthetic H.264 via AVAssetWriter")
                )
            } catch {
                manifest.entries.append(
                    FixtureEntry(path: movURL.path, family: "video", format: "mov", bytes: 0, note: "skipped: \(error.localizedDescription)")
                )
            }
            do {
                try await MakeFixtures.writeSyntheticVideo(url: mp4URL, fileType: .mp4, durationSeconds: 0.75, seed: seed &+ 1)
                manifest.entries.append(
                    entryForFile(url: mp4URL, family: "video", format: "mp4", note: "synthetic H.264 via AVAssetWriter")
                )
            } catch {
                manifest.entries.append(
                    FixtureEntry(path: mp4URL.path, family: "video", format: "mp4", bytes: 0, note: "skipped: \(error.localizedDescription)")
                )
            }
        }
    }

    // MARK: - PDF

    private static func generatePDFs(
        into dir: URL,
        count: Int,
        baseSeed: UInt64,
        manifest: inout FixtureManifest
    ) {
        for batch in 0..<count {
            let textURL = dir.appendingPathComponent("dinky-fixture-pdf-b\(batch)-text.pdf", isDirectory: false)
            let scanURL = dir.appendingPathComponent("dinky-fixture-pdf-b\(batch)-scanlike.pdf", isDirectory: false)
            let imgSeed = baseSeed &+ UInt64(batch) &* 0xC05EDC0D
            do {
                try MakeFixtures.writeTextHeavyPDF(url: textURL, batch: batch, seed: baseSeed &+ UInt64(batch))
                manifest.entries.append(
                    entryForFile(url: textURL, family: "pdf", format: "pdf", note: "CoreGraphics + CoreText — text-heavy")
                )
            } catch {
                manifest.entries.append(
                    FixtureEntry(path: textURL.path, family: "pdf", format: "pdf", bytes: 0, note: "skipped: \(error.localizedDescription)")
                )
            }
            do {
                try MakeFixtures.writeScanLikePDF(url: scanURL, batch: batch, imageSeed: imgSeed)
                manifest.entries.append(
                    entryForFile(url: scanURL, family: "pdf", format: "pdf", note: "embedded raster page — scan-like / image-heavy")
                )
            } catch {
                manifest.entries.append(
                    FixtureEntry(path: scanURL.path, family: "pdf", format: "pdf", bytes: 0, note: "skipped: \(error.localizedDescription)")
                )
            }
        }
    }
}

// MARK: - Implementation helpers

private enum MakeFixtures {
    static let countMax = 20

    struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) {
            state = seed == 0 ? 0xDEAD_BEEF_4141_4141 : seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    enum Error_: Swift.Error, LocalizedError {
        case imageDestination
        case imageFinalize
        case writer(String)
        case encoder(String)

        var errorDescription: String? {
            switch self {
            case .imageDestination: return "Could not create image destination"
            case .imageFinalize: return "Could not finalize image"
            case .writer(let m): return m
            case .encoder(let m): return m
            }
        }
    }

    // MARK: Raster

    static func makeSampleCGImage(width: Int, height: Int, seed: UInt64) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        var rng = SeededRNG(seed: seed)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let c1comps: [CGFloat] = [
            .random(in: 0.12...0.42, using: &rng),
            .random(in: 0.15...0.48, using: &rng),
            .random(in: 0.18...0.52, using: &rng),
            1,
        ]
        let c2comps: [CGFloat] = [
            .random(in: 0.55...0.95, using: &rng),
            .random(in: 0.5...0.9, using: &rng),
            .random(in: 0.45...0.88, using: &rng),
            1,
        ]
        guard let c1 = CGColor(colorSpace: cs, components: c1comps),
              let c2 = CGColor(colorSpace: cs, components: c2comps),
              let gradient = CGGradient(colorsSpace: cs, colors: [c1, c2] as CFArray, locations: [0, 1])
        else { return nil }

        ctx.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: CGFloat(width), y: CGFloat(height)),
            options: []
        )

        let blobCount = 35 + Int.random(in: 0..<40, using: &rng)
        ctx.setBlendMode(.plusLighter)
        for _ in 0..<blobCount {
            let r = CGFloat.random(in: 6...CGFloat(max(width, height)) / 3, using: &rng)
            let x = CGFloat.random(in: 0...CGFloat(width), using: &rng)
            let y = CGFloat.random(in: 0...CGFloat(height), using: &rng)
            let comps: [CGFloat] = [
                .random(in: 0...1, using: &rng) * 0.55,
                .random(in: 0...1, using: &rng) * 0.55,
                .random(in: 0...1, using: &rng) * 0.55,
                .random(in: 0.12...0.5, using: &rng),
            ]
            guard let col = CGColor(colorSpace: cs, components: comps) else { continue }
            ctx.setFillColor(col)
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        ctx.setBlendMode(.normal)
        return ctx.makeImage()
    }

    static func writeCGImage(_ image: CGImage, to url: URL, type: CFString, lossyQuality: CGFloat?) throws {
        try? FileManager.default.removeItem(at: url)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw Error_.imageDestination
        }
        var props: [CFString: Any] = [:]
        if let lossyQuality {
            props[kCGImageDestinationLossyCompressionQuality] = lossyQuality
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Error_.imageFinalize }
    }

    // MARK: Encoders (WebP / AVIF)

    static func runEncoder(bin: URL, name: String, args: [String]) throws {
        let exe = bin.appendingPathComponent(name, isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: exe.path) else {
            throw Error_.encoder("missing executable \(name) in \(bin.path)")
        }
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        let existing = env["DYLD_LIBRARY_PATH"].flatMap { $0.isEmpty ? nil : $0 }
        env["DYLD_LIBRARY_PATH"] = ["/opt/homebrew/lib", existing].compactMap { $0 }.joined(separator: ":")
        p.environment = env
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            throw Error_.encoder("\(name) exited \(p.terminationStatus): \(errText)")
        }
    }

    // MARK: Video

    static func writeSyntheticVideo(url: URL, fileType: AVFileType, durationSeconds: Double, seed: UInt64) async throws {
        try? FileManager.default.removeItem(at: url)
        let width = 640
        let height = 480
        let fps: Int32 = 30
        let frameCount = max(1, Int(durationSeconds * Double(fps)))

        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_200_000,
            ] as [String: Any],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        guard writer.canAdd(input) else { throw Error_.writer("cannot add video input") }
        writer.add(input)
        guard writer.startWriting() else {
            throw Error_.writer(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: fps)
        var rng = SeededRNG(seed: seed)

        for i in 0..<frameCount {
            let t = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { throw Error_.writer("no pixel buffer pool") }
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard status == kCVReturnSuccess, let pb = pixelBuffer else {
                throw Error_.writer("CVPixelBufferPoolCreatePixelBuffer failed (\(status))")
            }
            let phase = CGFloat(i) / CGFloat(max(frameCount - 1, 1))
            let br = CGFloat.random(in: 0.15...0.95, using: &rng) * (0.7 + 0.3 * phase)
            let bg = CGFloat.random(in: 0.15...0.95, using: &rng) * (0.7 + 0.3 * (1 - phase))
            let bb = CGFloat.random(in: 0.15...0.95, using: &rng)
            CVPixelBufferLockBaseAddress(pb, [])
            defer { CVPixelBufferUnlockBaseAddress(pb, []) }
            guard let base = CVPixelBufferGetBaseAddress(pb) else { throw Error_.writer("no base address") }
            let rowBytes = CVPixelBufferGetBytesPerRow(pb)
            for row in 0..<height {
                let rPtr = base.advanced(by: row * rowBytes).assumingMemoryBound(to: UInt8.self)
                for col in 0..<width {
                    let o = col * 4
                    rPtr[o + 0] = UInt8(bb * 255)
                    rPtr[o + 1] = UInt8(bg * 255)
                    rPtr[o + 2] = UInt8(br * 255)
                    rPtr[o + 3] = 255
                }
            }
            if !adaptor.append(pb, withPresentationTime: t) {
                throw Error_.writer("appendPixelBuffer failed")
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        guard writer.status == .completed else {
            throw Error_.writer(writer.error?.localizedDescription ?? "finishWriting status=\(writer.status.rawValue)")
        }
    }

    // MARK: PDF

    static func writeTextHeavyPDF(url: URL, batch: Int, seed: UInt64) throws {
        try? FileManager.default.removeItem(at: url)
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw Error_.writer("could not create PDF context") }

        ctx.beginPDFPage(nil)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: mediaBox.height)
        ctx.scaleBy(x: 1, y: -1)

        let body =
            """
            Dinky developer fixture — text-heavy PDF (batch \(batch), seed \(seed)).

            Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer nec odio.
            Praesent libero. Sed cursus ante dapibus diam. Sed nisi. Nulla quis sem at
            nibh elementum imperdiet. Duis sagittis ipsum. Praesent mauris.

            The quick brown fox jumps over the lazy dog. 0123456789
            """
        let text = body as CFString
        let font = CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        let para = CTParagraphStyleCreate(nil, 0)
        let keys: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTParagraphStyleAttributeName: para,
        ]
        guard let attrStr = CFAttributedStringCreate(nil, text, keys as CFDictionary) else {
            throw Error_.writer("could not build attributed string for PDF")
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
        let path = CGPath(
            rect: CGRect(x: 56, y: 56, width: 500, height: 680),
            transform: nil
        )
        let len = CFAttributedStringGetLength(attrStr)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: len), path, nil)
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
        ctx.endPDFPage()
        ctx.closePDF()
    }

    static func writeScanLikePDF(url: URL, batch: Int, imageSeed: UInt64) throws {
        try? FileManager.default.removeItem(at: url)
        guard let pageImg = makeSampleCGImage(width: 900, height: 1200, seed: imageSeed) else {
            throw Error_.writer("could not raster for scan-like PDF")
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw Error_.writer("could not create PDF context") }

        ctx.beginPDFPage(nil)
        let inset: CGFloat = 24
        let drawRect = CGRect(
            x: inset,
            y: inset,
            width: mediaBox.width - inset * 2,
            height: mediaBox.height - inset * 2
        )
        ctx.draw(pageImg, in: drawRect)
        ctx.setBlendMode(.multiply)
        if let fillCs = CGColorSpace(name: CGColorSpace.sRGB),
           let shade = CGColor(colorSpace: fillCs, components: [0, 0, 0, 0.18]) {
            ctx.setFillColor(shade)
            ctx.fill(CGRect(x: inset, y: inset * 0.5, width: 220, height: 16))
        }
        ctx.setBlendMode(.normal)
        ctx.endPDFPage()
        ctx.closePDF()
        _ = batch
    }
}

