import AppKit
import SwiftUI

struct ResultsRowView: View {
    /// Fixed blue for progress UI (bar + spinner) so it never picks up multicolor accent or system tint hues.
    private static let progressBarTint = Color(red: 0.28, green: 0.56, blue: 1)
    /// Matches prior `listRowSeparatorTint` — full-width line drawn in-row because AppKit list separators stop short of trailing actions.
    private static let rowDividerColor = Color.primary.opacity(0.08)

    @ObservedObject var item: CompressionItem
    let selectedFormat: CompressionFormat
    /// When false, omit the bottom hairline (used for the last row in the queue list).
    var showBottomDivider: Bool = true
    var onForceCompress: () -> Void = {}
    var onCancelDownload: () -> Void = {}
    var onPDFFlattenSmallestRetry: () -> Void = {}
    var onPDFPreserveExperimentalRetry: (PDFPreserveExperimentalMode) -> Void = { _ in }
    @EnvironmentObject var prefs: DinkyPreferences
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    /// Matches drop zone “compressing” treatment; respects system + in-app Reduce Motion.
    private var shouldReduceMotion: Bool { prefs.reduceMotion || accessibilityReduceMotion }
    private var rowProgressAnimation: Animation {
        shouldReduceMotion ? .linear(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.86)
    }
    @State private var showingError = false
    @State private var showingPreview = false
    @State private var showingSkippedInfo = false
    @State private var showingZeroGainInfo = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                // Content-type / media-type chip
                if item.mediaType == .image {
                    if let type = item.detectedContentType {
                        contentTypeChip(type)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .fixedSize()
                            .help(type.tooltipLabel)
                    } else {
                        mediaChip(String(localized: "image", comment: "Results row: generic image chip until Smart Quality classifies (photo / graphic / mixed)."))
                            .help(String(localized: "Image file", comment: "Tooltip for generic image type chip."))
                    }
                    if item.usedFirstFrameOnly, case .done = item.status {
                        mediaChip(String(localized: "First frame", comment: "Results row: multi-frame source was compressed as a single frame."))
                            .fixedSize()
                            .help(String(localized: "Animation or other frames were omitted; only the first frame was compressed.", comment: "Tooltip: first-frame-only chip."))
                            .accessibilityLabel(String(localized: "First frame only", comment: "VoiceOver: first-frame-only chip."))
                    }
                    if showsImageFormatConversionChip {
                        mediaChip(imageFormatConversionChipLabel())
                            .fixedSize()
                            .help(String(localized: "Saved in a different format than the original — not a same-file recompress.", comment: "Tooltip: format conversion chip."))
                            .accessibilityLabel(imageFormatConversionAccessibilityLabel())
                    }
                } else if item.mediaType == .pdf {
                    if let pages = item.pageCount {
                        mediaChip("\(pages)p")
                            .help(String(localized: "\(pages) pages", comment: "Tooltip: PDF page count."))
                    } else {
                        mediaChip(String(localized: "pdf", comment: "Results row: generic PDF chip until page count is known."))
                            .help(String(localized: "PDF document", comment: "Tooltip for generic PDF type chip."))
                    }
                    mediaChip(pdfExportPolicyChipText())
                        .fixedSize()
                        .help(pdfExportPolicyChipTooltip())
                        .accessibilityLabel(pdfExportPolicyAccessibilityLabel())
                } else if item.mediaType == .video {
                    if let type = item.detectedVideoContentType {
                        videoContentTypeChip(type)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .fixedSize()
                            .help(type.tooltipLabel)
                    } else {
                        mediaChip(String(localized: "video", comment: "Results row: generic video chip when content type was not classified (e.g. Smart Quality off)."))
                            .help(String(localized: "Video file", comment: "Tooltip for generic video type chip."))
                    }
                    if item.videoIsHDR {
                        hdrBadge
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .fixedSize()
                            .help(String(localized: "HDR source — preserved with HEVC so highlights and color stay intact.", comment: "Tooltip for HDR badge."))
                    }
                    if let secs = item.videoDuration {
                        mediaChip(formattedDuration(secs))
                            .help(String(localized: "Duration", comment: "Tooltip for video duration chip."))
                    }
                    mediaChip(videoExportPolicyChipText())
                        .fixedSize()
                        .help(videoExportPolicyChipTooltip())
                        .accessibilityLabel(videoExportPolicyAccessibilityLabel())
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(rowTitle)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        if let preset = appliedPreset {
                            presetBadge(preset).fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    if case .pending = item.status {
                        Text(pendingOutputLastPathComponent())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if case .downloading = item.status {
                        Text(pendingOutputLastPathComponent())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: item.detectedContentType)
                .animation(.easeInOut(duration: 0.2), value: item.pageCount)
                .animation(.easeInOut(duration: 0.2), value: item.detectedVideoContentType)
                .animation(.easeInOut(duration: 0.2), value: item.videoIsHDR)
                .animation(.easeInOut(duration: 0.2), value: item.usedFirstFrameOnly)
                .animation(.easeInOut(duration: 0.2), value: showsImageFormatConversionChip)
                .animation(.easeInOut(duration: 0.2), value: videoExportPolicyChipText())
                .animation(.easeInOut(duration: 0.2), value: pdfExportPolicyChipText())

                sizeInfo
                statusChip
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            if showBottomDivider {
                Rectangle()
                    .fill(Self.rowDividerColor)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityRowLabel)
        .accessibilityHint(String(localized: "Double-click to open in the default app. Drag the row to move the file.", comment: "VoiceOver hint for result row."))
        .sheet(isPresented: $showingError) {
            if case .failed(let error) = item.status {
                CompressionErrorDetailView(filename: item.filename, error: error)
            }
        }
        .sheet(isPresented: $showingPreview) {
            ImagePreviewSheet(item: item)
        }
        .sheet(isPresented: $showingSkippedInfo) {
            if case .skipped(let savedPercent, let threshold) = item.status {
                CompressionSkippedDetailView(
                    filename: item.filename,
                    savedPercent: savedPercent,
                    threshold: threshold,
                    onForceCompress: { showingSkippedInfo = false; onForceCompress() }
                )
            }
        }
        .sheet(isPresented: $showingZeroGainInfo) {
            if case .zeroGain(let attemptedSize) = item.status {
                CompressionZeroGainDetailView(
                    filename: item.filename,
                    originalSize: item.originalSize,
                    attemptedSize: attemptedSize,
                    isPDF: item.mediaType == .pdf,
                    pdfOutputMode: item.zeroGainPDFOutputMode,
                    onTryFlattenSmallest: item.mediaType == .pdf ? onPDFFlattenSmallestRetry : nil,
                    onTryPreserveExperimental: (item.mediaType == .pdf && (item.zeroGainPDFOutputMode == .preserveStructure || item.zeroGainPDFOutputMode == nil))
                        ? onPDFPreserveExperimentalRetry
                        : nil
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyPrepareQuit)) { _ in
            showingError = false
            showingPreview = false
            showingSkippedInfo = false
            showingZeroGainInfo = false
        }
    }

    private var rowTitle: String {
        if let remote = item.pendingRemoteURL {
            return remote.host ?? remote.absoluteString
        }
        return item.filename
    }

    /// Row was queued with a preset when non-nil.
    private var appliedPreset: CompressionPreset? {
        guard let id = item.presetID else { return nil }
        return prefs.savedPresets.first(where: { $0.id == id })
    }

    // MARK: - Video / PDF export policy chips (preset when set, else global prefs)

    private var effectiveVideoCodecFamily: VideoCodecFamily {
        if let p = appliedPreset {
            return VideoCodecFamily(rawValue: p.videoCodecFamilyRaw) ?? .h264
        }
        return prefs.videoCodecFamily
    }

    private var effectiveVideoSmartQuality: Bool {
        appliedPreset?.smartQuality ?? prefs.smartQuality
    }

    private var effectiveVideoQuality: VideoQuality {
        if let p = appliedPreset {
            return VideoQuality.resolve(p.videoQualityRaw)
        }
        return prefs.videoQuality
    }

    private func videoExportPolicyChipText() -> String {
        let codec = effectiveVideoCodecFamily.chipLabel
        if effectiveVideoSmartQuality {
            return "\(codec) · " + String(localized: "Smart", comment: "Results row: smart quality short label on chip.")
        }
        return "\(codec) · \(effectiveVideoQuality.displayName)"
    }

    private func videoExportPolicyChipTooltip() -> String {
        if effectiveVideoSmartQuality {
            return String.localizedStringWithFormat(
                String(localized: "Output: .mp4 using %@. Smart Quality picks encoder strength per clip (HDR may use HEVC).", comment: "Results row: video policy tooltip."),
                effectiveVideoCodecFamily.chipLabel
            )
        }
        return String.localizedStringWithFormat(
            String(localized: "Output: .mp4 using %@ at %@ quality.", comment: "Results row: video policy tooltip; codec then quality."),
            effectiveVideoCodecFamily.chipLabel,
            effectiveVideoQuality.displayName
        )
    }

    private func videoExportPolicyAccessibilityLabel() -> String {
        videoExportPolicyChipTooltip()
    }

    private var effectivePDFOutputMode: PDFOutputMode {
        if let p = appliedPreset {
            return PDFOutputMode(rawValue: p.pdfOutputModeRaw) ?? .flattenPages
        }
        return prefs.pdfOutputMode
    }

    private var effectivePDFQuality: PDFQuality {
        if let p = appliedPreset {
            return PDFQuality(rawValue: p.pdfQualityRaw) ?? .medium
        }
        return prefs.pdfQuality
    }

    private func pdfExportPolicyChipText() -> String {
        switch effectivePDFOutputMode {
        case .preserveStructure:
            return String(localized: "Preserve", comment: "Results row: short PDF preserve chip.")
        case .flattenPages:
            return String.localizedStringWithFormat(
                String(localized: "Flatten · %@", comment: "Results row: PDF flatten chip; tier name."),
                effectivePDFQuality.displayName
            )
        }
    }

    private func pdfExportPolicyChipTooltip() -> String {
        switch effectivePDFOutputMode {
        case .preserveStructure:
            return String(localized: "Best-effort smaller file while keeping selectable text and links.", comment: "Results row: PDF preserve tooltip.")
        case .flattenPages:
            return String.localizedStringWithFormat(
                String(localized: "Rasterize pages to JPEG (%@ tier).", comment: "Results row: PDF flatten tooltip; tier."),
                effectivePDFQuality.displayName
            )
        }
    }

    private func pdfExportPolicyAccessibilityLabel() -> String {
        switch effectivePDFOutputMode {
        case .preserveStructure:
            return String(localized: "PDF: preserve text and links", comment: "VoiceOver: PDF preserve chip.")
        case .flattenPages:
            return String.localizedStringWithFormat(
                String(localized: "PDF: flatten, %@ quality", comment: "VoiceOver: PDF flatten chip; tier."),
                effectivePDFQuality.displayName
            )
        }
    }

    private func presetBadge(_ preset: CompressionPreset) -> some View {
        let matchesActive = (prefs.activePresetID == preset.id.uuidString)
        return Text(preset.name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(matchesActive ? Color.accentColor : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(matchesActive ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
            )
            .help(String(localized: "Preset: \(preset.name)", comment: "Tooltip: row uses this preset; argument is preset name."))
            .accessibilityLabel(String(localized: "Preset \(preset.name)", comment: "VoiceOver: preset badge; argument is name."))
    }

    private var accessibilityRowLabel: String {
        var base = "\(rowTitle), \(item.statusLabel)"
        if let p = appliedPreset {
            base += ", " + String(localized: "Preset \(p.name)", comment: "VoiceOver preset suffix; argument is preset name.")
        }
        if item.mediaType == .image, item.usedFirstFrameOnly, case .done = item.status {
            base += ", " + String(localized: "First frame only", comment: "VoiceOver: first-frame-only chip.")
        }
        if item.mediaType == .image, showsImageFormatConversionChip {
            base += ", " + imageFormatConversionAccessibilityLabel()
        }
        if item.mediaType == .video {
            base += ", " + videoExportPolicyAccessibilityLabel()
        }
        if item.mediaType == .pdf {
            base += ", " + pdfExportPolicyAccessibilityLabel()
        }
        return base
    }

    /// Expected output filename while the row is still queued (matches `CompressionPreset` / `DinkyPreferences` URL rules).
    private func pendingOutputLastPathComponent() -> String {
        let urlDL = item.isURLDownloadSource
        if let pid = item.presetID,
           let preset = prefs.savedPresets.first(where: { $0.id == pid }) {
            switch item.mediaType {
            case .image:
                let fmt = ImageCompressionFormatResolver.resolvedFormat(
                    sourceURL: item.sourceURL,
                    formatOverride: item.formatOverride,
                    preset: preset,
                    globalAutoFormat: prefs.autoFormat,
                    globalSelectedFormat: selectedFormat
                )
                return preset.outputURL(for: item.sourceURL, format: fmt, globalPrefs: prefs, isFromURLDownload: urlDL).lastPathComponent
            case .pdf:
                return preset.outputURL(for: item.sourceURL, mediaType: .pdf, globalPrefs: prefs, isFromURLDownload: urlDL).lastPathComponent
            case .video:
                return preset.outputURL(for: item.sourceURL, mediaType: .video, globalPrefs: prefs, isFromURLDownload: urlDL).lastPathComponent
            }
        }
        switch item.mediaType {
        case .image:
            let fmt = ImageCompressionFormatResolver.resolvedFormat(
                sourceURL: item.sourceURL,
                formatOverride: item.formatOverride,
                preset: nil,
                globalAutoFormat: prefs.autoFormat,
                globalSelectedFormat: selectedFormat
            )
            return prefs.outputURL(for: item.sourceURL, format: fmt, isFromURLDownload: urlDL).lastPathComponent
        case .pdf, .video:
            return prefs.outputURL(for: item.sourceURL, mediaType: item.mediaType, isFromURLDownload: urlDL).lastPathComponent
        }
    }

    private func canonicalImageExtension(_ ext: String) -> String {
        let e = ext.lowercased()
        if e == "jpeg" { return "jpg" }
        if e == "heif" { return "heic" }
        return e
    }

    /// Output file extension for display: actual file when done, otherwise resolved from settings (matches compression).
    private func imageOutputExtensionForDisplay() -> String? {
        guard item.mediaType == .image else { return nil }
        if case .done(let outURL, _, _) = item.status {
            return outURL.pathExtension
        }
        let fmt = ImageCompressionFormatResolver.resolvedFormat(
            sourceURL: item.sourceURL,
            formatOverride: item.formatOverride,
            preset: appliedPreset,
            globalAutoFormat: prefs.autoFormat,
            globalSelectedFormat: selectedFormat
        )
        return fmt.outputExtension
    }

    private var showsImageFormatConversionChip: Bool {
        guard item.mediaType == .image,
              !item.sourceURL.pathExtension.isEmpty,
              let out = imageOutputExtensionForDisplay() else { return false }
        return canonicalImageExtension(item.sourceURL.pathExtension) != canonicalImageExtension(out)
    }

    private func imageFormatConversionChipLabel() -> String {
        let src = canonicalImageExtension(item.sourceURL.pathExtension).uppercased()
        guard let outExt = imageOutputExtensionForDisplay() else { return "" }
        let dst = canonicalImageExtension(outExt).uppercased()
        return "\(src) → \(dst)"
    }

    private func imageFormatConversionAccessibilityLabel() -> String {
        let src = canonicalImageExtension(item.sourceURL.pathExtension).uppercased()
        guard let outExt = imageOutputExtensionForDisplay() else { return "" }
        let dst = canonicalImageExtension(outExt).uppercased()
        return String.localizedStringWithFormat(
            String(localized: "Converts %1$@ to %2$@", comment: "VoiceOver: format conversion chip; arguments are uppercase source extension, uppercase output extension."),
            src, dst
        )
    }

    // MARK: Size diff

    @ViewBuilder
    private var sizeInfo: some View {
        switch item.status {
        case .done(_, let orig, let out):
            HStack(spacing: 5) {
                Text(bytes(orig))
                Image(systemName: "arrow.right")
                    .imageScale(.small)
                Text(bytes(out))
                    .fontWeight(.medium)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)

        case .downloading(_, let received, let total, _):
            if let total, total > 0 {
                Text("\(bytes(received)) / \(bytes(total))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "—", comment: "Em dash when download size unknown."))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

        default:
            Text(bytes(item.originalSize))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Status chip

    @ViewBuilder
    private var statusChip: some View {
        switch item.status {
        case .pending:
            chip(String(localized: "Queued", comment: "Status chip: file waiting."), color: .secondary.opacity(0.35), fg: .primary)
                .help(String(localized: "Waiting to compress", comment: "Tooltip for queued chip."))

        case .downloading(let progress, _, let totalBytes, let displayHost):
            HStack(spacing: 8) {
                if let t = totalBytes, t > 0 {
                    HStack(spacing: 5) {
                        if !shouldReduceMotion {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(Self.progressBarTint.opacity(0.95))
                                .symbolEffect(.rotate, options: .repeating)
                                .accessibilityHidden(true)
                        }
                        ProgressView(value: progress, total: 1)
                            .scaleEffect(0.72)
                            .frame(width: 52)
                            .tint(Self.progressBarTint)
                    }
                    .animation(rowProgressAnimation, value: progress)
                    Text("\(Int((progress * 100).rounded(.towardZero)))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 5) {
                        if !shouldReduceMotion {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(Self.progressBarTint.opacity(0.95))
                                .symbolEffect(.rotate, options: .repeating)
                                .accessibilityHidden(true)
                        }
                        ProgressView()
                            .scaleEffect(0.65)
                            .tint(Self.progressBarTint)
                    }
                    Text(String(localized: "Fetching", comment: "Download status indeterminate size."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    onCancelDownload()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Cancel download", comment: "Tooltip for cancel download button."))
            }
            .help(String(localized: "Downloading from \(displayHost)", comment: "Tooltip; argument is host name."))

        case .processing:
            Group {
                if let p = item.compressionProgress {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            HStack(spacing: 5) {
                                if !shouldReduceMotion {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 11, weight: .semibold))
                                        .symbolRenderingMode(.monochrome)
                                        .foregroundStyle(Self.progressBarTint.opacity(0.95))
                                        .symbolEffect(.rotate, options: .repeating)
                                        .accessibilityHidden(true)
                                }
                                ProgressView(value: p, total: 1)
                                    .scaleEffect(0.72)
                                    .frame(width: 52)
                                    .tint(Self.progressBarTint)
                            }
                            .animation(rowProgressAnimation, value: p)
                            Text("\(Int((p * 100).rounded(.towardZero)))%")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                                .animation(rowProgressAnimation, value: p)
                        }
                        if let stage = item.compressionStageLabel {
                            Text(stage)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .help(String(localized: "Compressing — \(Int((p * 100).rounded(.towardZero))) percent", comment: "Tooltip; argument is percent."))
                } else {
                    HStack(spacing: 5) {
                        if !shouldReduceMotion {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(Self.progressBarTint.opacity(0.95))
                                .symbolEffect(.rotate, options: .repeating)
                                .accessibilityHidden(true)
                        }
                        ProgressView()
                            .scaleEffect(0.65)
                            .tint(Self.progressBarTint)
                        Text(String(localized: "Working", comment: "Compression in progress label."))
                    }
                    .help(String(localized: "Compression in progress", comment: "Tooltip for processing row."))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .done(let outputURL, _, _):
            HStack(spacing: 6) {
                if item.mediaType == .image {
                    Button {
                        showingPreview = true
                    } label: {
                        Image(systemName: "eye")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Preview before and after", comment: "Tooltip for preview button."))
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                } label: {
                    Text(String(localized: "Show in Finder", comment: "Button to reveal output in Finder."))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Reveal compressed file in Finder", comment: "Tooltip for Show in Finder."))
            }

        case .skipped(let savedPercent, let threshold):
            Button { showingSkippedInfo = true } label: {
                infoStatusChip(String(localized: "Skipped", comment: "Status chip."))
            }
            .buttonStyle(.plain)
            .help(skippedTooltip(savedPercent: savedPercent, threshold: threshold))

        case .zeroGain(let attemptedSize):
            Button { showingZeroGainInfo = true } label: {
                infoStatusChip(String(localized: "No gain", comment: "Status chip: no size reduction."))
            }
            .buttonStyle(.plain)
            .help(zeroGainTooltip(
                originalSize: item.originalSize,
                attemptedSize: attemptedSize,
                pdfOutputMode: item.mediaType == .pdf ? item.zeroGainPDFOutputMode : nil
            ))

        case .failed:
            Button { showingError = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .imageScale(.small)
                    Text(String(localized: "Error", comment: "Failed compression button label."))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.red.opacity(0.75)))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help(String(localized: "Click to see error details", comment: "Tooltip for error chip."))
        }
    }

    // MARK: - Chip styles

    private func chip(_ label: String, color: Color, fg: Color) -> some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color))
    }

    /// Skipped / no-gain status: same capsule as `chip`, with an info affordance like the error row’s icon + label.
    private func infoStatusChip(_ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle.fill")
                .imageScale(.small)
            Text(title)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.secondary.opacity(0.35)))
    }

    private func mediaChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold).lowercaseSmallCaps())
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08))
            )
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // Small, muted chip shown next to the filename when Smart Quality is on.
    // It's secondary info — colors are soft so the row's primary content still leads.
    @ViewBuilder
    private func contentTypeChip(_ type: ContentType) -> some View {
        Text(type.label)
            .font(.system(size: 9, weight: .semibold).lowercaseSmallCaps())
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08))
            )
    }

    /// Same look as `contentTypeChip` but for video classification (screen / camera / video).
    @ViewBuilder
    private func videoContentTypeChip(_ type: VideoContentType) -> some View {
        Text(type.label)
            .font(.system(size: 9, weight: .semibold).lowercaseSmallCaps())
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08))
            )
    }

    /// Tinted "HDR" badge — slightly stronger than the muted chips so HDR preservation stands out.
    private var hdrBadge: some View {
        Text(String(localized: "HDR", comment: "High dynamic range badge."))
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor.opacity(0.14))
            )
    }

private func bytes(_ n: Int64) -> String {
        String(format: String(localized: "%.2f MB", comment: "File size with megabytes unit."), Double(n) / 1_048_576)
    }

    // MARK: - Tooltips for skipped / no-gain chips

    private func skippedTooltip(savedPercent: Double?, threshold: Int) -> String {
        if let p = savedPercent {
            return String(format: String(localized: "Would only save %.1f%% (your threshold is %d%%). Click for details.", comment: "Skipped tooltip."), p, threshold)
        }
        return String(localized: "Already optimized — encoder couldn't make it smaller. Click for details.", comment: "Skipped tooltip.")
    }

    private func zeroGainTooltip(originalSize: Int64, attemptedSize: Int64, pdfOutputMode: PDFOutputMode?) -> String {
        let diff = attemptedSize - originalSize
        if pdfOutputMode == .preserveStructure, diff > 0 {
            return String(format: String(localized: "System PDF rewrite would have been %.2f MB larger (not saved). Click for details.", comment: "Zero-gain tooltip: preserve PDF."),
                          Double(diff) / 1_048_576)
        }
        if diff > 0 {
            return String(format: String(localized: "Compressed version was %.2f MB larger. Original kept. Click for details.", comment: "Zero-gain tooltip."),
                          Double(diff) / 1_048_576)
        }
        return String(localized: "Compressed version wasn't smaller. Original kept. Click for details.", comment: "Zero-gain tooltip.")
    }
}

// MARK: - File type icon

private struct FileTypeIcon: View {
    let ext: String

    private var label: String { ext.uppercased() }

    private var color: Color {
        switch ext.lowercased() {
        case "jpg", "jpeg":       return Color(red: 0.96, green: 0.42, blue: 0.28) // orange
        case "png":               return Color(red: 0.28, green: 0.56, blue: 1.00) // blue
        case "tiff":              return Color(red: 0.18, green: 0.78, blue: 0.52) // green
        case "bmp":               return Color(red: 0.96, green: 0.30, blue: 0.54) // pink
        case "pdf":               return Color(red: 0.92, green: 0.18, blue: 0.18) // red
        case "mp4", "mov", "m4v": return Color(red: 0.55, green: 0.28, blue: 0.95) // purple
        case "webp", "avif":      return Color.secondary
        default:                  return Color.secondary
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color.opacity(0.15))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(color.opacity(0.30), lineWidth: 0.5)
            Text(label)
                .font(.system(size: label.count > 3 ? 6 : 7, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(width: 28, height: 24)
    }
}
