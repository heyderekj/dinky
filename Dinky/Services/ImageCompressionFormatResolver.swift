import Foundation

/// Resolves which ``CompressionFormat`` will be used for an image job — matches
/// ``ContentView.compressImageItem`` (before PNG-source validation).
enum ImageCompressionFormatResolver {

    /// When `classifiedContent` is provided (same run as compression), it is used instead of
    /// classifying again so Smart Quality + Auto format do not double-call ``ContentClassifier``.
    static func resolvedFormat(
        sourceURL: URL,
        formatOverride: CompressionFormat?,
        preset: CompressionPreset?,
        globalAutoFormat: Bool,
        globalSelectedFormat: CompressionFormat,
        classifiedContent: ContentType? = nil
    ) -> CompressionFormat {
        let autoFmt = preset?.autoFormat ?? globalAutoFormat
        var format = formatOverride ?? preset?.format ?? globalSelectedFormat
        if autoFmt, formatOverride == nil {
            let ct = classifiedContent ?? ContentClassifier.classify(sourceURL)
            format = ct == .photo ? .avif : .webp
        }
        return format
    }

    /// For views: never classifies. Classifying is a thumbnail decode plus Vision, and a row used to
    /// run it several times per render. `nil` while Auto format waits on the background
    /// classification (`CompressionItem.detectedContentType`).
    static func knownFormat(
        formatOverride: CompressionFormat?,
        preset: CompressionPreset?,
        globalAutoFormat: Bool,
        globalSelectedFormat: CompressionFormat,
        classifiedContent: ContentType?
    ) -> CompressionFormat? {
        let autoFmt = preset?.autoFormat ?? globalAutoFormat
        if autoFmt, formatOverride == nil {
            guard let classifiedContent else { return nil }
            return classifiedContent == .photo ? .avif : .webp
        }
        return formatOverride ?? preset?.format ?? globalSelectedFormat
    }
}
