import AppKit
import SwiftUI

struct ResultsRowView: View {
    @ObservedObject var item: CompressionItem
    let selectedFormat: CompressionFormat
    var onForceCompress: () -> Void = {}
    var onCancelDownload: () -> Void = {}
    @EnvironmentObject var prefs: DinkyPreferences
    @State private var showingError = false
    @State private var showingPreview = false
    @State private var showingSkippedInfo = false
    @State private var showingZeroGainInfo = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                // Content-type / media-type chip
                if item.mediaType == .image, let type = item.detectedContentType {
                    contentTypeChip(type)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .fixedSize()
                        .help(type.tooltipLabel)
                } else if item.mediaType == .pdf, let pages = item.pageCount {
                    mediaChip("\(pages)p")
                        .help(String(localized: "\(pages) pages", comment: "Tooltip: PDF page count."))
                } else if item.mediaType == .video {
                    if let type = item.detectedVideoContentType {
                        videoContentTypeChip(type)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .fixedSize()
                            .help(type.tooltipLabel)
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
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(rowTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
            .animation(.easeInOut(duration: 0.2), value: item.detectedVideoContentType)
            .animation(.easeInOut(duration: 0.2), value: item.videoIsHDR)

            sizeInfo
            statusChip
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityRowLabel)
        .accessibilityHint(String(localized: "Double-click to open in the default app. Drag the row to move the file.", comment: "VoiceOver hint for result row."))
        .onHover { isHovering = $0 }
        .sheet(isPresented: $showingError) {
            if case .failed(let error) = item.status {
                ErrorDetailView(filename: item.filename, error: error)
            }
        }
        .sheet(isPresented: $showingPreview) {
            ImagePreviewSheet(item: item)
        }
        .sheet(isPresented: $showingSkippedInfo) {
            if case .skipped(let savedPercent, let threshold) = item.status {
                SkippedDetailView(
                    filename: item.filename,
                    savedPercent: savedPercent,
                    threshold: threshold,
                    onForceCompress: { showingSkippedInfo = false; onForceCompress() }
                )
            }
        }
        .sheet(isPresented: $showingZeroGainInfo) {
            if case .zeroGain(let attemptedSize) = item.status {
                ZeroGainDetailView(
                    filename: item.filename,
                    originalSize: item.originalSize,
                    attemptedSize: attemptedSize
                )
            }
        }
    }

    private var rowTitle: String {
        if let remote = item.pendingRemoteURL {
            return remote.host ?? remote.absoluteString
        }
        return item.filename
    }

    private var accessibilityRowLabel: String {
        "\(rowTitle), \(item.statusLabel)"
    }

    /// Expected output filename while the row is still queued (matches `CompressionPreset` / `DinkyPreferences` URL rules).
    private func pendingOutputLastPathComponent() -> String {
        let urlDL = item.isURLDownloadSource
        if let pid = item.presetID,
           let preset = prefs.savedPresets.first(where: { $0.id == pid }) {
            switch item.mediaType {
            case .image:
                let fmt = item.formatOverride ?? preset.format
                return preset.outputURL(for: item.sourceURL, format: fmt, globalPrefs: prefs, isFromURLDownload: urlDL).lastPathComponent
            case .pdf:
                return preset.outputURL(for: item.sourceURL, mediaType: .pdf, globalPrefs: prefs, isFromURLDownload: urlDL).lastPathComponent
            case .video:
                return preset.outputURL(for: item.sourceURL, mediaType: .video, globalPrefs: prefs, isFromURLDownload: urlDL).lastPathComponent
            }
        }
        switch item.mediaType {
        case .image:
            return prefs.outputURL(for: item.sourceURL, format: item.formatOverride ?? selectedFormat, isFromURLDownload: urlDL).lastPathComponent
        case .pdf, .video:
            return prefs.outputURL(for: item.sourceURL, mediaType: item.mediaType, isFromURLDownload: urlDL).lastPathComponent
        }
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
                    ProgressView(value: progress, total: 1)
                        .scaleEffect(0.72)
                        .frame(width: 52)
                    Text("\(Int((progress * 100).rounded(.towardZero)))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .scaleEffect(0.65)
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
                if item.mediaType == .video, let p = item.videoExportProgress {
                    HStack(spacing: 6) {
                        ProgressView(value: p, total: 1)
                            .scaleEffect(0.72)
                            .frame(width: 52)
                        Text("\(Int((p * 100).rounded(.towardZero)))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .help(String(localized: "Encoding video — \(Int((p * 100).rounded(.towardZero))) percent", comment: "Tooltip; argument is percent."))
                } else {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.65)
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
            Group {
                if isHovering {
                    Button { onForceCompress() } label: {
                        Text(String(localized: "Compress anyway", comment: "Force compress skipped file."))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Force compress even if savings are minimal", comment: "Tooltip."))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Button { showingSkippedInfo = true } label: {
                        chip(String(localized: "Skipped", comment: "Status chip."), color: .secondary.opacity(0.35), fg: .primary)
                    }
                    .buttonStyle(.plain)
                    .help(skippedTooltip(savedPercent: savedPercent, threshold: threshold))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isHovering)

        case .zeroGain(let attemptedSize):
            Button { showingZeroGainInfo = true } label: {
                chip(String(localized: "No gain", comment: "Status chip: no size reduction."), color: .secondary.opacity(0.35), fg: .primary)
            }
            .buttonStyle(.plain)
            .help(zeroGainTooltip(originalSize: item.originalSize, attemptedSize: attemptedSize))

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

    private func zeroGainTooltip(originalSize: Int64, attemptedSize: Int64) -> String {
        let diff = attemptedSize - originalSize
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

// MARK: - Error detail sheet

private struct ErrorDetailView: View {
    let filename: String
    let error: Error
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red)
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Compression Failed", comment: "Error sheet title."))
                        .font(.headline)
                    Text(filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Error message
            ScrollView {
                Text(error.localizedDescription)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)

            Divider()

            // Footer
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(String(localized: "Email Error…", comment: "Send error by email.")) {
                        NSWorkspace.shared.open(
                            DiagnosticsReporter.emailURL(
                                subject: String(localized: "Error — \(filename)", comment: "Email subject; argument is filename."),
                                extraBody: error.localizedDescription
                            )
                        )
                    }
                    Button(String(localized: "GitHub Issue…", comment: "Open GitHub issue for error.")) {
                        NSWorkspace.shared.open(
                            DiagnosticsReporter.githubIssueURL(
                                title: String(localized: "Error: \(filename)", comment: "Issue title; argument is filename."),
                                extraBody: error.localizedDescription
                            )
                        )
                    }
                    Spacer()
                    Button(String(localized: "Dismiss", comment: "Close sheet.")) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                Text(String(localized: "Tip: check that cwebp / avifenc are present in the app bundle.", comment: "Error sheet footer."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Skipped detail sheet

private struct SkippedDetailView: View {
    let filename: String
    let savedPercent: Double?
    let threshold: Int
    let onForceCompress: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var headlineText: String {
        if let p = savedPercent {
            return String(format: String(localized: "Would only save %.1f%%", comment: "Skipped detail headline."), p)
        }
        return String(localized: "Already at minimum size", comment: "Skipped detail headline.")
    }

    private var bodyText: String {
        if let p = savedPercent {
            return String(format:
                String(localized: "Dinky compressed this file but the result was only %.1f%% smaller — under your %d%% threshold, so the original was kept.\n\nLower the threshold in Settings → General → Skip if savings below to compress files like this automatically, or click Compress Anyway to force this one.", comment: "Skipped detail body."),
                p, threshold)
        }
        return String(localized: "The encoder couldn't make this file any smaller. It's likely already optimized for its format.\n\nForcing compression won't help here, but you can try a different format (e.g. WebP or AVIF) from the sidebar.", comment: "Skipped detail body.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(headlineText).font(.headline)
                    Text(filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                Text(bodyText)
                    .font(.system(.body))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 220)

            Divider()

            HStack {
                if savedPercent != nil {
                    Button(String(localized: "Compress Anyway", comment: "Force compress from sheet.")) { onForceCompress() }
                }
                Spacer()
                Button(String(localized: "Dismiss", comment: "Close sheet.")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Zero-gain detail sheet

private struct ZeroGainDetailView: View {
    let filename: String
    let originalSize: Int64
    let attemptedSize: Int64
    @Environment(\.dismiss) private var dismiss

    private var diffText: String {
        let diff = attemptedSize - originalSize
        let mb = Double(abs(diff)) / 1_048_576
        if diff > 0 {
            return String(format: String(localized: "%.2f MB larger", comment: "Comparison: output larger than original."), mb)
        }
        return String(localized: "the same size", comment: "Comparison: file sizes equal.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "No size gain", comment: "Zero-gain sheet title.")).font(.headline)
                    Text(filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    sizePill(String(localized: "Original", comment: "Size pill label."), value: bytes(originalSize))
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    sizePill(String(localized: "Compressed", comment: "Size pill label."), value: bytes(attemptedSize), highlight: true)
                }

                Text(String(localized: "The compressed version was \(diffText) than the original, so Dinky kept the original.\n\nThis usually happens with files that are already heavily optimized, or when re-encoding to a format that doesn't suit the content (e.g. lossy → lossless). Try a different format from the sidebar, or leave this file as-is.", comment: "Zero-gain explanation; argument describes size relationship phrase."))
                    .font(.system(.body))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "Dismiss", comment: "Close sheet.")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420)
        .background(.ultraThinMaterial)
    }

    private func bytes(_ n: Int64) -> String {
        String(format: String(localized: "%.2f MB", comment: "File size with megabytes unit."), Double(n) / 1_048_576)
    }

    private func sizePill(_ label: String, value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(highlight ? .primary : .secondary)
                .fontWeight(highlight ? .semibold : .regular)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
