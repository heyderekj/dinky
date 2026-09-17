import DinkyCorePDF
import DinkyCoreShared
import DinkyCoreVideo
import Foundation

/// Flags passed on the command line for `--preset` / `--preset-id` / `--preset-file`.
public struct PresetCLIRef: Sendable, Equatable {
    public var name: String?
    public var id: UUID?
    public var file: String?

    public init(name: String? = nil, id: UUID? = nil, file: String? = nil) {
        self.name = name
        self.id = id
        self.file = file
    }

    public var isEmpty: Bool { name == nil && id == nil && file == nil }
}

public enum DinkyCLIPresetError: Error, Sendable, Equatable {
    case scopeMismatch(presetName: String, includedLabel: String)
    case needsOutputDir(reason: String)
    case presetLoad(String)

    public var message: String {
        switch self {
        case .scopeMismatch(let presetName, let includedLabel):
            return "preset “\(presetName)” does not apply to this command (preset scope: \(includedLabel))."
        case .needsOutputDir(let reason):
            return reason
        case .presetLoad(let s):
            return s
        }
    }
}

public enum DinkyCLIPresetSupport: Sendable {

    @discardableResult
    public static func applyImagePresetIfNeeded(
        ref: PresetCLIRef,
        explicit: Set<String>,
        options: inout DinkyCompressOptions
    ) throws -> CompressionPreset? {
        guard !ref.isEmpty else { return nil }
        let p = try loadPreset(ref: ref)
        guard p.applies(to: .image) else {
            throw DinkyCLIPresetError.scopeMismatch(presetName: p.name, includedLabel: scopeLabel(p))
        }
        mergeImage(preset: p, explicit: explicit, into: &options)
        return p
    }

    @discardableResult
    public static func applyVideoPresetIfNeeded(
        ref: PresetCLIRef,
        explicit: Set<String>,
        options: inout DinkyVideoCompressOptions
    ) throws -> CompressionPreset? {
        guard !ref.isEmpty else { return nil }
        let p = try loadPreset(ref: ref)
        guard p.applies(to: .video) else {
            throw DinkyCLIPresetError.scopeMismatch(presetName: p.name, includedLabel: scopeLabel(p))
        }
        mergeVideo(preset: p, explicit: explicit, into: &options)
        return p
    }

    @discardableResult
    public static func applyPDFPresetIfNeeded(
        ref: PresetCLIRef,
        explicit: Set<String>,
        options: inout DinkyPdfCompressOptions
    ) throws -> CompressionPreset? {
        guard !ref.isEmpty else { return nil }
        let p = try loadPreset(ref: ref)
        guard p.applies(to: .pdf) else {
            throw DinkyCLIPresetError.scopeMismatch(presetName: p.name, includedLabel: scopeLabel(p))
        }
        mergePDF(preset: p, explicit: explicit, into: &options)
        return p
    }

    /// When `options.outputDir` is nil, derive directory from preset + source (or source folder if no preset).
    public static func outputDirectoryForSourceURL(
        preset: CompressionPreset?,
        source: URL
    ) throws -> URL {
        guard let p = preset else {
            return source.deletingLastPathComponent()
        }
        switch p.saveLocationRaw {
        case "sameFolder":
            return source.deletingLastPathComponent()
        case "downloads":
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? source.deletingLastPathComponent()
        case "custom", "presetCustom":
            let path = p.presetCustomFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                throw DinkyCLIPresetError.needsOutputDir(
                    reason: "preset uses a custom save folder but no plain path is stored; pass -o /path."
                )
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        default:
            return source.deletingLastPathComponent()
        }
    }

    public static func outputFilenameStem(
        preset: CompressionPreset?,
        source: URL,
        mediaExtension: String
    ) -> String {
        let stem = source.deletingPathExtension().lastPathComponent
        guard let p = preset else {
            return stem + "-dinky." + mediaExtension
        }
        enum FH: String {
            case appendSuffix, replaceOrigin, customSuffix
        }
        let fh = FH(rawValue: p.filenameHandlingRaw) ?? .appendSuffix
        let suffix = p.customSuffix.isEmpty ? "-dinky" : p.customSuffix
        let base: String
        switch fh {
        case .appendSuffix: base = stem + "-dinky"
        case .replaceOrigin: base = stem
        case .customSuffix: base = stem + suffix
        }
        var out = base
        if p.sanitizeFilenames {
            out = out.lowercased().replacingOccurrences(of: " ", with: "-")
            if out.count > 75 { out = String(out.prefix(75)) }
        }
        return out + "." + mediaExtension
    }

    private static func loadPreset(ref: PresetCLIRef) throws -> CompressionPreset {
        do {
            return try DinkyPresetLoader.resolve(name: ref.name, id: ref.id, presetFile: ref.file)
        } catch let e as DinkyPresetLoadError {
            throw DinkyCLIPresetError.presetLoad(describePresetLoadError(e))
        } catch {
            throw DinkyCLIPresetError.presetLoad(error.localizedDescription)
        }
    }

    private static func describePresetLoadError(_ e: DinkyPresetLoadError) -> String {
        switch e {
        case .fileNotFound(let p):
            return "preset file not found: \(p)"
        case .invalidJSON(let s):
            return "invalid preset JSON: \(s)"
        case .presetNotFound(let s):
            return "preset not found: \(s)"
        case .multiplePresetsMatch(let s):
            return "multiple presets match “\(s)” — use --preset-id"
        }
    }

    private static func scopeLabel(_ p: CompressionPreset) -> String {
        let inc = p.includedMediaTypes
        if inc == PresetMediaScopeRawCodec.allTypes { return PresetMediaScope.all.displayName }
        let order: [MediaType] = [.image, .video, .audio, .pdf]
        return order.filter { inc.contains($0) }.map { typeWord($0) }.joined(separator: ", ")
    }

    private static func typeWord(_ m: MediaType) -> String {
        switch m {
        case .image: return "images"
        case .video: return "videos"
        case .audio: return "audio"
        case .pdf: return "pdfs"
        }
    }

    private static func mergeImage(
        preset p: CompressionPreset,
        explicit: Set<String>,
        into o: inout DinkyCompressOptions
    ) {
        if !explicit.contains("format") {
            o.format = p.autoFormat ? "auto" : p.format.rawValue
        }
        if !explicit.contains("smartQuality") { o.smartQuality = p.smartQuality }
        if !explicit.contains("maxWidth") {
            o.maxWidth = p.maxWidthEnabled ? p.maxWidth : nil
        }
        if !explicit.contains("maxSizeKb") {
            o.maxFileSizeKB = p.maxFileSizeEnabled ? p.maxFileSizeKB : nil
        }
        if !explicit.contains("stripMetadata") { o.stripMetadata = p.stripMetadata }
        if !explicit.contains("contentHint") { o.contentTypeHint = p.contentTypeHintRaw }
        if !explicit.contains("chromaSubsampling") { o.chromaSubsamplingRaw = p.chromaSubsamplingRaw }
        if !explicit.contains("webpLossless") { o.webpLossless = p.webpLossless }
        if !explicit.contains("pngOutputMode") { o.pngOutputModeRaw = p.pngOutputModeRaw }
        if !explicit.contains("collisionStyle") {
            o.collisionStyle = CollisionNamingStyle(rawValue: p.collisionNamingStyleRaw) ?? .finderDuplicate
        }
        if !explicit.contains("collisionCustom") {
            o.collisionCustomPattern = p.collisionCustomPattern
        }
        if !explicit.contains("outputDir") {
            switch p.saveLocationRaw {
            case "downloads":
                o.outputDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            case "custom", "presetCustom":
                let path = p.presetCustomFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    o.outputDir = URL(fileURLWithPath: path, isDirectory: true)
                }
            default:
                break
            }
        }
    }

    private static func mergeVideo(
        preset p: CompressionPreset,
        explicit: Set<String>,
        into o: inout DinkyVideoCompressOptions
    ) {
        if !explicit.contains("quality") {
            o.quality = VideoQuality.resolve(p.videoQualityRaw)
        }
        if !explicit.contains("codec") {
            o.codec = VideoCodecFamily(rawValue: p.videoCodecFamilyRaw) ?? .h264
        }
        if !explicit.contains("removeAudio") { o.removeAudio = p.videoRemoveAudio }
        if !explicit.contains("maxHeight") {
            o.maxResolutionLines = p.videoMaxResolutionEnabled ? p.videoMaxResolutionLines : nil
        }
        if !explicit.contains("maxFps") {
            o.fpsCapEnabled = p.videoMaxFPSEnabled
            o.fpsCap = VideoFPSCapPreset.normalizeStored(p.videoMaxFPS)
        }
        if !explicit.contains("smartQuality") { o.smartQuality = p.smartQuality }
        if !explicit.contains("collisionStyle") {
            o.collisionStyle = CollisionNamingStyle(rawValue: p.collisionNamingStyleRaw) ?? .finderDuplicate
        }
        if !explicit.contains("collisionCustom") {
            o.collisionCustomPattern = p.collisionCustomPattern
        }
        if !explicit.contains("outputDir") {
            switch p.saveLocationRaw {
            case "downloads":
                o.outputDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            case "custom", "presetCustom":
                let path = p.presetCustomFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    o.outputDir = URL(fileURLWithPath: path, isDirectory: true)
                }
            default:
                break
            }
        }
    }

    private static func mergePDF(
        preset p: CompressionPreset,
        explicit: Set<String>,
        into o: inout DinkyPdfCompressOptions
    ) {
        if !explicit.contains("mode") {
            o.outputMode = PDFOutputMode(rawValue: p.pdfOutputModeRaw) ?? .flattenPages
        }
        if !explicit.contains("quality") {
            o.quality = PDFQuality(rawValue: p.pdfQualityRaw) ?? .medium
        }
        if !explicit.contains("smartQuality") { o.smartQuality = p.smartQuality }
        if !explicit.contains("grayscale") { o.grayscale = p.pdfGrayscale }
        if !explicit.contains("stripMetadata") { o.stripMetadata = p.stripMetadata }
        if !explicit.contains("downsample") {
            o.resolutionDownsampling = p.pdfResolutionDownsampling
        }
        if !explicit.contains("targetKb") {
            o.targetKB = p.pdfMaxFileSizeEnabled ? p.pdfMaxFileSizeKB : nil
        }
        if !explicit.contains("preserveExperimental") {
            o.preserveExperimental = PDFPreserveExperimentalMode(rawValue: p.pdfPreserveExperimentalRaw) ?? .none
        }
        if !explicit.contains("autoGrayscaleMono") {
            o.autoGrayscaleMonoScans = p.pdfAutoGrayscaleMonoScans
        }
        if !explicit.contains("collisionStyle") {
            o.collisionStyle = CollisionNamingStyle(rawValue: p.collisionNamingStyleRaw) ?? .finderDuplicate
        }
        if !explicit.contains("collisionCustom") {
            o.collisionCustomPattern = p.collisionCustomPattern
        }
        if !explicit.contains("outputDir") {
            switch p.saveLocationRaw {
            case "downloads":
                o.outputDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            case "custom", "presetCustom":
                let path = p.presetCustomFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    o.outputDir = URL(fileURLWithPath: path, isDirectory: true)
                }
            default:
                break
            }
        }
    }
}
