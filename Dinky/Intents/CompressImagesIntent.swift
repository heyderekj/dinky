import AppIntents
import Foundation

struct CompressImagesIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "Compress Images",
        comment: "Shortcuts app: intent title."
    )
    static var description = IntentDescription(
        LocalizedStringResource(
            "Compresses image files using Dinky and returns the compressed versions. Uses your chosen format below, plus Smart quality (if enabled), strip metadata, resize, and file-size limits from the app’s Settings — not Auto format from the sidebar.",
            comment: "Shortcuts app: intent description."
        ),
        categoryName: LocalizedStringResource("Images", comment: "Shortcuts app: intent category.")
    )

    @Parameter(
        title: LocalizedStringResource("Images", comment: "Shortcuts: images parameter title."),
        description: LocalizedStringResource("The image files to compress.", comment: "Shortcuts: images parameter description.")
    )
    var images: [IntentFile]

    @Parameter(
        title: LocalizedStringResource("Format", comment: "Shortcuts: output format parameter title."),
        description: LocalizedStringResource("Output format for compressed images.", comment: "Shortcuts: format parameter description."),
        default: .webp
    )
    var format: CompressionFormatEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Compress \(\.$images) as \(\.$format)")
    }

    func perform() async throws -> some ReturnsValue<[IntentFile]> {
        let outputFormat = format.compressionFormat
        let settings = DinkyPreferences.compressionSettingsForIntent()
        let goals = settings.goals
        var results: [IntentFile] = []

        for image in images {
            // IntentFile.filename is non-optional String; use URL to parse extension and stem
            let srcURL = URL(fileURLWithPath: image.filename)
            let ext = srcURL.pathExtension.isEmpty ? "jpg" : srcURL.pathExtension
            let stem = srcURL.deletingPathExtension().lastPathComponent.isEmpty
                ? String(localized: "image", comment: "Default filename stem for Shortcuts output when source has no name.")
                : srcURL.deletingPathExtension().lastPathComponent

            let tmpIn = FileManager.default.temporaryDirectory
                .appendingPathComponent("dinky_intent_\(UUID().uuidString)")
                .appendingPathExtension(ext)
            let tmpOut = FileManager.default.temporaryDirectory
                .appendingPathComponent("dinky_intent_\(UUID().uuidString)")
                .appendingPathExtension(outputFormat.outputExtension)

            // IntentFile.data is non-throwing
            try image.data.write(to: tmpIn)
            defer { try? FileManager.default.removeItem(at: tmpIn) }

            let result = try await CompressionService.shared.compress(
                source: tmpIn,
                format: outputFormat,
                goals: goals,
                stripMetadata: settings.stripMetadata,
                outputURL: tmpOut,
                originalsAction: .keep,
                backupFolderURL: nil,
                isURLDownloadSource: false,
                smartQuality: settings.smartQuality,
                contentTypeHint: settings.contentTypeHint
            )
            defer { try? FileManager.default.removeItem(at: result.outputURL) }

            let outData = try Data(contentsOf: result.outputURL)
            let outFilename = stem + "." + outputFormat.outputExtension
            results.append(IntentFile(data: outData, filename: outFilename,
                                      type: .init(filenameExtension: outputFormat.outputExtension)))
        }

        return .result(value: results)
    }
}

enum CompressionFormatEntity: String, AppEnum {
    case webp, avif, png

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Format", comment: "Shortcuts: format type name.")
    )
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .webp: DisplayRepresentation(title: LocalizedStringResource("WebP", comment: "Image format name.")),
        .avif: DisplayRepresentation(title: LocalizedStringResource("AVIF", comment: "Image format name.")),
        .png: DisplayRepresentation(title: LocalizedStringResource("PNG", comment: "Image format name.")),
    ]

    var compressionFormat: CompressionFormat {
        switch self {
        case .webp: return .webp
        case .avif: return .avif
        case .png:  return .png
        }
    }
}
