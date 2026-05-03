import AppKit
import SwiftUI

/// One successfully compressed row for the batch summary sheet (input → output).
struct BatchCompletionFileRow: Identifiable, Equatable, Codable {
    let id: UUID
    let sourceName: String
    let outputName: String
    let sourcePath: String
    let outputPath: String
    let originalSize: Int64
    let outputSize: Int64
    /// Whether this row can still be reverted (undo snapshot present on the queue item).
    let canUndo: Bool
}

/// One row in the batch summary file list (compressed, skipped, failed, or no gain).
enum BatchSummaryListRow: Identifiable, Equatable, Codable {
    case compressed(BatchCompletionFileRow)
    case skipped(id: UUID, fileName: String, sourcePath: String, savedPercent: Double?, threshold: Int)
    case failed(id: UUID, fileName: String, sourcePath: String, errorDescription: String)
    case zeroGain(id: UUID, fileName: String, sourcePath: String, originalSize: Int64, attemptedSize: Int64, isPDF: Bool, pdfOutputModeRaw: String?)

    var id: UUID {
        switch self {
        case .compressed(let r): return r.id
        case .skipped(let id, _, _, _, _): return id
        case .failed(let id, _, _, _): return id
        case .zeroGain(let id, _, _, _, _, _, _): return id
        }
    }

    /// Builds rows for every terminal result in the queue (same order as `items`).
    @MainActor
    static func rows(from items: [CompressionItem]) -> [BatchSummaryListRow] {
        items.compactMap { item -> BatchSummaryListRow? in
            switch item.status {
            case .done(let outputURL, let orig, let out):
                return .compressed(
                    BatchCompletionFileRow(
                        id: item.id,
                        sourceName: item.sourceURL.lastPathComponent,
                        outputName: outputURL.lastPathComponent,
                        sourcePath: item.sourceURL.path,
                        outputPath: outputURL.path,
                        originalSize: orig,
                        outputSize: out,
                        canUndo: item.undoSnapshot != nil
                    )
                )
            case .skipped(let savedPercent, let threshold):
                return .skipped(
                    id: item.id,
                    fileName: item.filename,
                    sourcePath: item.sourceURL.path,
                    savedPercent: savedPercent,
                    threshold: threshold
                )
            case .failed(let error):
                return .failed(
                    id: item.id,
                    fileName: item.filename,
                    sourcePath: item.sourceURL.path,
                    errorDescription: error.localizedDescription
                )
            case .zeroGain(let attemptedSize):
                return .zeroGain(
                    id: item.id,
                    fileName: item.filename,
                    sourcePath: item.sourceURL.path,
                    originalSize: item.originalSize,
                    attemptedSize: attemptedSize,
                    isPDF: item.mediaType == .pdf,
                    pdfOutputModeRaw: item.zeroGainPDFOutputMode?.rawValue
                )
            default:
                return nil
            }
        }
    }
}

struct CompressionBatchSummary: Identifiable, Equatable {
    let id: UUID
    let savedBytes: Int64
    let doneCount: Int
    let elapsed: TimeInterval
    let openedFolder: Bool
    let skippedCount: Int
    let outputFolderURL: URL?
    let fileRows: [BatchSummaryListRow]
    /// Done items that can be reverted (non-nil undo snapshot).
    let undoableDoneCount: Int
    /// PDFs where OCR ran and added a searchable text layer this batch.
    let pdfOCRAppliedCount: Int
}

extension CompressionBatchSummary: Codable {
    enum CodingKeys: String, CodingKey {
        case id, savedBytes, doneCount, elapsed, openedFolder, skippedCount, outputFolderURL, undoableDoneCount, fileRows
        case pdfOCRAppliedCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        savedBytes = try c.decode(Int64.self, forKey: .savedBytes)
        doneCount = try c.decode(Int.self, forKey: .doneCount)
        elapsed = try c.decode(TimeInterval.self, forKey: .elapsed)
        openedFolder = try c.decode(Bool.self, forKey: .openedFolder)
        skippedCount = try c.decode(Int.self, forKey: .skippedCount)
        outputFolderURL = try c.decodeIfPresent(URL.self, forKey: .outputFolderURL)
        undoableDoneCount = try c.decode(Int.self, forKey: .undoableDoneCount)
        pdfOCRAppliedCount = try c.decodeIfPresent(Int.self, forKey: .pdfOCRAppliedCount) ?? 0
        if let rows = try? c.decode([BatchSummaryListRow].self, forKey: .fileRows) {
            fileRows = rows
        } else {
            let legacy = try c.decode([BatchCompletionFileRow].self, forKey: .fileRows)
            fileRows = legacy.map { .compressed($0) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(savedBytes, forKey: .savedBytes)
        try c.encode(doneCount, forKey: .doneCount)
        try c.encode(elapsed, forKey: .elapsed)
        try c.encode(openedFolder, forKey: .openedFolder)
        try c.encode(skippedCount, forKey: .skippedCount)
        try c.encodeIfPresent(outputFolderURL, forKey: .outputFolderURL)
        try c.encode(undoableDoneCount, forKey: .undoableDoneCount)
        try c.encode(fileRows, forKey: .fileRows)
        try c.encode(pdfOCRAppliedCount, forKey: .pdfOCRAppliedCount)
    }
}

struct BatchCompletionSummarySheet: View {
    let summary: CompressionBatchSummary
    /// When false (e.g. opened from History), hide Undo / Undo All — queue may not match files on disk.
    var supportsUndo: Bool = true
    /// Opens Settings to a tab (same pipeline as the sidebar’s `openPreferences`).
    var openPreferences: (PreferencesTab) -> Void
    var onUndoAll: () -> Void
    /// Revert one file; `id` is the queue item id (`BatchCompletionFileRow.id`).
    var onUndoItem: (UUID) -> Void
    /// Force-compress / retry (skipped, failed, zero-gain rows).
    var onQueueCompress: (UUID) -> Void = { _ in }
    var onOpenZeroGainDetail: (UUID) -> Void = { _ in }
    var onOpenFailedDetail: (UUID) -> Void = { _ in }
    var onPDFFlattenSmallest: (UUID) -> Void = { _ in }
    var onPDFPreserveExperimental: (UUID, PDFPreserveExperimentalMode) -> Void = { _, _ in }
    @Environment(\.dismiss) private var dismiss

    private var failedRowCount: Int {
        summary.fileRows.filter { if case .failed = $0 { return true }; return false }.count
    }

    private var zeroGainRowCount: Int {
        summary.fileRows.filter { if case .zeroGain = $0 { return true }; return false }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Big in. Dinky out.", comment: "Batch completion sheet title; brand tagline."))
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                SummaryStatRow(
                    icon: "square.stack.3d.up.fill",
                    text: batchCompressedLabel(summary.doneCount)
                )

                if summary.savedBytes > 0 {
                    SummaryStatRow(
                        icon: "arrow.down.circle.fill",
                        text: String.localizedStringWithFormat(
                            String(localized: "%@ saved", comment: "Batch summary; argument is formatted byte size."),
                            formattedSavedBytes(summary.savedBytes)
                        )
                    )
                    if let p = SavingsPerspective.perspective(savedBytes: summary.savedBytes, seed: summary.id) {
                        SummaryStatRow(icon: p.icon, text: p.text)
                    }
                } else {
                    SummaryStatRow(
                        icon: "equal.circle",
                        text: String(localized: "No space saved (outputs were already small or similar size).", comment: "Batch summary when saved bytes zero."),
                        textSecondary: true
                    )
                }

                SummaryStatRow(
                    icon: "clock",
                    text: String.localizedStringWithFormat(
                        String(localized: "Time: %@", comment: "Batch summary; argument is formatted duration."),
                        formattedElapsed(summary.elapsed)
                    )
                )

                if summary.skippedCount > 0 {
                    SummaryStatRow(
                        icon: "minus.circle",
                        text: String.localizedStringWithFormat(
                            String(localized: "%lld skipped (below savings threshold or unchanged)", comment: "Batch summary; argument is skipped count."),
                            Int64(summary.skippedCount)
                        ),
                        textSecondary: true
                    )
                }

                if failedRowCount > 0 {
                    SummaryStatRow(
                        icon: "exclamationmark.triangle.fill",
                        text: String.localizedStringWithFormat(
                            String(localized: "%lld failed", comment: "Batch summary; argument is failure count."),
                            Int64(failedRowCount)
                        ),
                        textSecondary: true
                    )
                }

                if zeroGainRowCount > 0 {
                    SummaryStatRow(
                        icon: "arrow.uturn.backward.circle",
                        text: String.localizedStringWithFormat(
                            String(localized: "%lld no size gain", comment: "Batch summary; argument is zero-gain count."),
                            Int64(zeroGainRowCount)
                        ),
                        textSecondary: true
                    )
                }

                if summary.pdfOCRAppliedCount > 0 {
                    SummaryStatRow(
                        icon: "doc.text.magnifyingglass",
                        text: {
                            let n = summary.pdfOCRAppliedCount
                            if n == 1 {
                                return String(localized: "1 scanned PDF made searchable.", comment: "Batch summary OCR line (singular).")
                            }
                            return String.localizedStringWithFormat(
                                String(localized: "%lld scanned PDFs made searchable.", comment: "Batch summary OCR line (plural)."),
                                Int64(n)
                            )
                        }(),
                        textSecondary: true
                    )
                }

                if summary.openedFolder {
                    SummaryStatRow(
                        icon: "folder.fill",
                        text: String(localized: "Opened the output folder in Finder.", comment: "Batch summary: folder was opened."),
                        textSecondary: true,
                        subheadline: true
                    )
                } else {
                    folderNotOpenedRow
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !summary.fileRows.isEmpty {
                // Inset the list inside the glass so row rounded rects aren’t clipped by the
                // shape mask (same for ScrollView’s edge clipping).
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(summary.fileRows) { row in
                            listRowView(row)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Self.fileListCardInset)
                }
                .frame(maxHeight: 420)
                .frame(maxWidth: .infinity, alignment: .leading)
                .adaptiveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 4)
            }

            HStack {
                if supportsUndo, summary.undoableDoneCount > 0 {
                    Button(String(localized: "Undo All", comment: "Batch summary: revert all compressions in this batch.")) {
                        onUndoAll()
                        dismiss()
                    }
                }
                Spacer(minLength: 0)
                if !summary.openedFolder, let folder = summary.outputFolderURL {
                    Button(String(localized: "Open folder", comment: "Batch summary: reveal output in Finder.")) {
                        NSWorkspace.shared.open(folder)
                        dismiss()
                    }
                }
                Button(String(localized: "OK", comment: "Dismiss batch summary sheet.")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 440)
    }

    /// When the batch did not auto-open Finder — accent link matches sidebar plain `Button` + `Color.accentColor` style.
    private var folderNotOpenedRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Did not open the output folder automatically.", comment: "Batch summary: folder was not opened."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Change in Settings…", comment: "Batch summary: open Settings for Open folder when done.")) {
                    openPreferences(.behavior)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Padding inside the glass card so first/last row corners stay inside the 16pt rounded mask.
    private static let fileListCardInset: CGFloat = 8

    @ViewBuilder
    private func listRowView(_ row: BatchSummaryListRow) -> some View {
        switch row {
        case .compressed(let r):
            fileRowView(r, supportsUndo: supportsUndo)
        case .skipped(let id, let fileName, let sourcePath, let savedPercent, let threshold):
            skippedSummaryRowView(
                id: id,
                fileName: fileName,
                sourcePath: sourcePath,
                savedPercent: savedPercent,
                threshold: threshold
            )
        case .failed(let id, let fileName, let sourcePath, let errorDescription):
            failedSummaryRowView(id: id, fileName: fileName, sourcePath: sourcePath, errorDescription: errorDescription)
        case .zeroGain(let id, let fileName, let sourcePath, let originalSize, let attemptedSize, let isPDF, let pdfOutputModeRaw):
            zeroGainSummaryRowView(
                id: id,
                fileName: fileName,
                sourcePath: sourcePath,
                originalSize: originalSize,
                attemptedSize: attemptedSize,
                isPDF: isPDF,
                pdfOutputModeRaw: pdfOutputModeRaw,
                onPDFPreserveExperimental: onPDFPreserveExperimental
            )
        }
    }

    private func skippedSummaryRowView(
        id: UUID,
        fileName: String,
        sourcePath: String,
        savedPercent: Double?,
        threshold: Int
    ) -> some View {
        let headline: String = {
            if let p = savedPercent {
                return String(format: String(localized: "Skipped — only %.1f%% smaller (threshold %d%%)", comment: "Batch summary skipped row; percent and threshold."), p, threshold)
            }
            return String(localized: "Skipped — already minimal", comment: "Batch summary skipped row when no percent.")
        }()
        return issueCard(
            icon: "checkmark.seal.fill",
            iconTint: .secondary,
            title: fileName,
            subtitle: headline,
            help: sourcePath
        ) {
            if supportsUndo, savedPercent != nil {
                Button(String(localized: "Compress anyway", comment: "Batch summary row: force compress skipped file.")) {
                    onQueueCompress(id)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
        }
    }

    private func failedSummaryRowView(
        id: UUID,
        fileName: String,
        sourcePath: String,
        errorDescription: String
    ) -> some View {
        issueCard(
            icon: "exclamationmark.triangle.fill",
            iconTint: Color.red,
            title: fileName,
            subtitle: errorDescription,
            help: "\(sourcePath)\n\(errorDescription)"
        ) {
            if supportsUndo {
                HStack(spacing: 6) {
                    Button(String(localized: "Retry", comment: "Batch summary row: retry failed compression.")) {
                        onQueueCompress(id)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                    Button(String(localized: "Full error…", comment: "Batch summary row: open error detail sheet.")) {
                        onOpenFailedDetail(id)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func zeroGainSummaryRowView(
        id: UUID,
        fileName: String,
        sourcePath: String,
        originalSize: Int64,
        attemptedSize: Int64,
        isPDF: Bool,
        pdfOutputModeRaw: String?,
        onPDFPreserveExperimental: @escaping (UUID, PDFPreserveExperimentalMode) -> Void
    ) -> some View {
        let mode = pdfOutputModeRaw.flatMap { PDFOutputMode(rawValue: $0) }
        let sizeNote = String.localizedStringWithFormat(
            String(localized: "%1$@ vs %2$@", comment: "Batch summary zero-gain; original vs attempted size."),
            formattedSavedBytes(originalSize),
            formattedSavedBytes(attemptedSize)
        )
        return issueCard(
            icon: "arrow.uturn.backward.circle.fill",
            iconTint: .secondary,
            title: fileName,
            subtitle: String(localized: "No size gain — original kept", comment: "Batch summary zero-gain row subtitle."),
            detail: sizeNote,
            help: sourcePath
        ) {
            if supportsUndo {
                VStack(alignment: .leading, spacing: 4) {
                    if isPDF, mode == .preserveStructure || mode == nil {
                        HStack(spacing: 6) {
                            Menu {
                                Button(String(localized: "Strip non-essential structure", comment: "Batch summary: experimental preserve retry.")) {
                                    onPDFPreserveExperimental(id, .stripNonEssentialStructure)
                                }
                                Button(String(localized: "Stronger image recompression", comment: "Batch summary: experimental preserve retry.")) {
                                    onPDFPreserveExperimental(id, .strongerImageRecompression)
                                }
                                Button(String(localized: "Maximum (both)", comment: "Batch summary: experimental preserve retry.")) {
                                    onPDFPreserveExperimental(id, .maximum)
                                }
                            } label: {
                                Text(String(localized: "Experimental preserve…", comment: "Batch summary: experimental preserve menu label."))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                            Button(String(localized: "Flatten (Smallest)", comment: "Batch summary row: PDF flatten retry.")) {
                                onPDFFlattenSmallest(id)
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                        }
                    }
                    HStack(spacing: 6) {
                        Button(String(localized: "Try again", comment: "Batch summary row: retry zero-gain file.")) {
                            onQueueCompress(id)
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                        Button(String(localized: "Details…", comment: "Batch summary row: open zero-gain explanation.")) {
                            onOpenZeroGainDetail(id)
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func issueCard(
        icon: String,
        iconTint: Color,
        title: String,
        subtitle: String,
        detail: String? = nil,
        help: String,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                actions()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.22))
        }
        .help(help)
    }

    private func fileRowView(_ row: BatchCompletionFileRow, supportsUndo: Bool) -> some View {
        let saved = row.originalSize - row.outputSize
        let pct: Double? = (row.originalSize > 0 && saved > 0)
            ? Double(saved) / Double(row.originalSize) * 100
            : nil
        let sizeLine = String.localizedStringWithFormat(
            String(localized: "%1$@ → %2$@", comment: "Batch summary per file; before → after byte sizes; arguments are formatted sizes."),
            formattedSavedBytes(row.originalSize),
            formattedSavedBytes(row.outputSize)
        )
        let fromLine = String.localizedStringWithFormat(
            String(localized: "From %@", comment: "Batch summary per file; argument is original filename."),
            row.sourceName
        )
        let helpText = "\(row.sourcePath)\n→ \(row.outputPath)"
        let a11yMetrics: String = {
            if let pct {
                let pctStr = String(
                    format: String(localized: "%.0f%% smaller", comment: "Batch summary per file; percent saved vs original."),
                    pct
                )
                return "\(sizeLine). \(pctStr)"
            }
            return sizeLine
        }()
        var accessibilitySummary = "\(row.outputName). \(fromLine). \(a11yMetrics)"
        if supportsUndo, row.canUndo {
            accessibilitySummary += ", " + String(localized: "Undo available", comment: "VoiceOver: undo available on batch summary row.")
        }

        return HStack(alignment: .top, spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: row.outputPath))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.outputName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fromLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sizeLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let pct {
                        Text(
                            String(
                                format: String(localized: "%.0f%% smaller", comment: "Batch summary per file; percent saved vs original."),
                                pct
                            )
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.55))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if supportsUndo, row.canUndo {
                Button {
                    onUndoItem(row.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption.weight(.semibold))
                        Text(String(localized: "Undo", comment: "Batch summary per file: revert this compression."))
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    }
                }
                .buttonStyle(.plain)
                .help(String(localized: "Restore the original and remove this compressed file.", comment: "Tooltip for batch summary row Undo."))
                .accessibilityLabel(String(localized: "Undo compression", comment: "VoiceOver: Undo on batch summary row."))
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.22))
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func batchCompressedLabel(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("batch_compressed_file_count", bundle: .main, comment: "Batch summary; plural by compressed file count."),
            count
        )
    }

    private func formattedSavedBytes(_ n: Int64) -> String {
        let nf = ByteCountFormatter()
        nf.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        nf.countStyle = .file
        return nf.string(fromByteCount: n)
    }

    private func formattedElapsed(_ t: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .second]
        f.unitsStyle = .positional
        f.zeroFormattingBehavior = .pad
        return f.string(from: t) ?? String(format: "%.0f", t)
    }
}
