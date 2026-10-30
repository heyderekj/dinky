import AppKit
import SwiftUI
import DinkyCoreShared

/// Payload for the pre-compression confirmation sheet (user-initiated adds only).
struct PendingCompressionConfirmation: Identifiable {
    let id = UUID()
    let localURLs: [URL]
    let remoteURLs: [URL]
    let force: Bool
    let presetID: UUID?
}

struct CompressionConfirmationSheet: View {
    @Binding var selectedFormat: CompressionFormat
    let localURLs: [URL]
    let remoteURLs: [URL]
    /// Opens Settings to a tab (same as sidebar / batch summary).
    var openPreferences: (PreferencesTab) -> Void
    let onCancel: () -> Void
    let onContinue: () -> Void

    @EnvironmentObject var prefs: DinkyPreferences
    /// Filled in the background once the sheet is up; rows show the plain media label until then.
    @State private var classified: [URL: ContentType] = [:]

    private var localCount: Int { localURLs.count }
    private var remoteCount: Int { remoteURLs.count }

    private static let fileListCardInset: CGFloat = 8
    /// Per-file `ImageCompressionFormatResolver` hints only for smaller drops (classification cost).
    private static let maxPerFileFormatHints = 30

    /// Counts from ``MediaTypeDetector`` for locals (used to gate summary policy rows).
    private var localQueueTypeCounts: (image: Int, pdf: Int, video: Int, audio: Int, unknown: Int) {
        var image = 0, pdf = 0, video = 0, audio = 0, unknown = 0
        for u in localURLs {
            if let m = MediaTypeDetector.detect(u) {
                switch m {
                case .image: image += 1
                case .pdf: pdf += 1
                case .video: video += 1
                case .audio: audio += 1
                }
            } else {
                unknown += 1
            }
        }
        return (image, pdf, video, audio, unknown)
    }

    private var showImagePolicyInSummary: Bool {
        localCount > 0 && (localQueueTypeCounts.image > 0 || localQueueTypeCounts.unknown > 0)
    }

    private var showVideoPolicyInSummary: Bool { localCount > 0 && localQueueTypeCounts.video > 0 }
    private var showPdfPolicyInSummary: Bool { localCount > 0 && localQueueTypeCounts.pdf > 0 }
    private var showAudioPolicyInSummary: Bool { localCount > 0 && localQueueTypeCounts.audio > 0 }
    private var showRemoteOnlyPolicyInSummary: Bool { localCount == 0 && remoteCount > 0 }

    /// Links-only or unknown locals: show all media control sections.
    private var remoteOnlyQueue: Bool { localCount == 0 && remoteCount > 0 }

    private var showImageControls: Bool {
        let c = localQueueTypeCounts
        return c.image > 0 || c.unknown > 0 || remoteOnlyQueue
    }

    private var showVideoControls: Bool {
        let c = localQueueTypeCounts
        return c.video > 0 || c.unknown > 0 || remoteOnlyQueue
    }

    private var showPdfControls: Bool {
        let c = localQueueTypeCounts
        return c.pdf > 0 || c.unknown > 0 || remoteOnlyQueue
    }

    private var showAudioControls: Bool {
        let c = localQueueTypeCounts
        return c.audio > 0 || c.unknown > 0 || remoteOnlyQueue
    }

    private var showSmartQualityToggle: Bool {
        showImageControls || showVideoControls || showPdfControls || showAudioControls
    }

    private var presetLocked: Bool { !prefs.activePresetID.isEmpty }

    private var activePresetName: String? {
        guard let id = UUID(uuidString: prefs.activePresetID),
              let p = prefs.savedPresets.first(where: { $0.id == id }) else { return nil }
        return p.name
    }

    private var presetSummaryLine: String {
        if let name = activePresetName {
            return String.localizedStringWithFormat(
                String(localized: "Preset: %@", comment: "Compression confirm: preset name in queue summary."),
                name
            )
        }
        return String(localized: "Preset: None — settings below apply", comment: "Compression confirm: no preset in queue summary.")
    }

    var body: some View {
        content
            .task(id: localURLs) { await classifyShownImages() }
    }

    /// Classifying is a thumbnail decode plus Vision per file; it used to run on every render.
    private func classifyShownImages() async {
        guard localURLs.count <= Self.maxPerFileFormatHints else { return }
        for url in localURLs where MediaTypeDetector.detect(url) == .image && classified[url] == nil {
            let ct = await Task.detached(priority: .userInitiated) { ContentClassifier.classify(url) }.value
            guard !Task.isCancelled else { return }
            classified[url] = ct
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "Confirm compression", comment: "Compression confirm sheet title."))
                    .font(.headline)

                Text(leadText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                summaryCard

                if !localURLs.isEmpty || !remoteURLs.isEmpty {
                    Text(String(localized: "What’s queued", comment: "Compression confirm: pending list section."))
                        .font(.subheadline.weight(.semibold))

                    pendingListCard
                }

                Text(String(localized: "How it will run", comment: "Compression confirm: controls section."))
                    .font(.subheadline.weight(.semibold))

                controlsCard

                Toggle(String(localized: "Always confirm before compressing", comment: "Compression confirm sheet."), isOn: Binding(
                    get: { prefs.confirmBeforeEveryCompression },
                    set: { prefs.confirmBeforeEveryCompression = $0 }
                ))

                HStack(alignment: .center) {
                    Button(String(localized: "Open Settings…", comment: "Compression confirm: open Settings.")) {
                        openPreferences(.output)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    Spacer(minLength: 0)
                    Button(String(localized: "Cancel", comment: "Compression confirm sheet.")) {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button(String(localized: "Continue", comment: "Compression confirm sheet.")) {
                        onContinue()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 440, maxWidth: 560)
        .frame(minHeight: 400, idealHeight: 560)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SummaryStatRow(
                icon: "square.stack.3d.up.fill",
                text: queueTotalLine
            )

            SummaryStatRow(
                icon: "slider.horizontal.3",
                text: presetSummaryLine,
                textSecondary: true,
                subheadline: true
            )

            if let strip = mediaCountStripContent {
                SummaryMediaCountStrip(
                    segments: strip.segments,
                    accessibilitySummary: strip.accessibilityLabel
                )
            }

            if showImagePolicyInSummary {
                SummaryPolicyGroup(
                    icon: "photo.on.rectangle.angled",
                    lines: [prefs.imageCompressionPolicySummaryLine(selectedFormat: selectedFormat)]
                )
            }
            if showVideoPolicyInSummary {
                SummaryPolicyGroup(
                    icon: "film",
                    lines: prefs.videoCompressionPolicySummaryRows()
                )
            }
            if showPdfPolicyInSummary {
                SummaryPolicyGroup(
                    icon: "doc.text.fill",
                    lines: prefs.pdfCompressionPolicySummaryRows()
                )
            }
            if showAudioPolicyInSummary {
                SummaryPolicyGroup(
                    icon: "waveform",
                    lines: prefs.audioCompressionPolicySummaryRows()
                )
            }
            if showRemoteOnlyPolicyInSummary {
                SummaryStatRow(
                    icon: "link",
                    text: prefs.remoteLinksCompressionPolicySummaryLine(),
                    textSecondary: true,
                    subheadline: true
                )
            }
            if let manual = prefs.manualModeQueueSummaryLine() {
                SummaryStatRow(icon: "hand.raised", text: manual, textSecondary: true, subheadline: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var queueTotalLine: String {
        if localCount > 0, remoteCount > 0 {
            let locals = compressConfirmPluralCount("compress_confirm_local_files", count: localCount)
            let links = compressConfirmPluralCount("compress_confirm_links", count: remoteCount)
            return String.localizedStringWithFormat(
                NSLocalizedString("compress_confirm_comma_pair", bundle: .main, comment: "Compression confirm: join two count phrases with a comma."),
                locals, links
            )
        }
        if remoteCount > 0 {
            return compressConfirmPluralCount("compress_confirm_links_to_fetch", count: remoteCount)
        }
        return compressConfirmPluralCount("compress_confirm_local_files", count: localCount)
    }

    private var mediaCountStripContent: (segments: [(icon: String, count: Int)], accessibilityLabel: String)? {
        var counts: [MediaType: Int] = [:]
        var unknown = 0
        for u in localURLs {
            if let m = MediaTypeDetector.detect(u) {
                counts[m, default: 0] += 1
            } else {
                unknown += 1
            }
        }
        var segments: [(icon: String, count: Int)] = []
        var phrases: [String] = []
        for t in [MediaType.image, .video, .audio, .pdf] {
            if let c = counts[t], c > 0 {
                segments.append((iconForMedia(t), c))
                phrases.append(mediaCountLabel(type: t, count: c))
            }
        }
        if unknown > 0 {
            segments.append(("questionmark.circle", unknown))
            phrases.append(compressConfirmPluralCount("compress_confirm_other_files_unknown", count: unknown))
        }
        guard !segments.isEmpty else { return nil }
        return (segments, phrases.joined(separator: ", "))
    }

    private func mediaCountLabel(type: MediaType, count: Int) -> String {
        let key: String
        switch type {
        case .image: key = "compress_confirm_images"
        case .pdf: key = "compress_confirm_pdfs"
        case .video: key = "compress_confirm_videos"
        case .audio: key = "compress_confirm_audio"
        }
        return compressConfirmPluralCount(key, count: count)
    }

    /// Plural-aware phrases for the String Catalog (`compress_confirm_*` keys).
    private func compressConfirmPluralCount(_ key: String, count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString(key, bundle: .main, comment: "Compression confirm: plural count phrase."),
            Int64(count)
        )
    }

    private func iconForMedia(_ type: MediaType) -> String {
        switch type {
        case .image: return "photo"
        case .pdf: return "doc.text.fill"
        case .video: return "film"
        case .audio: return "waveform"
        }
    }

    // MARK: - Pending list

    private var pendingListCard: some View {
        let shownLocals = Array(localURLs.prefix(Self.maxPerFileFormatHints))
        let overflow = localURLs.count - shownLocals.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(shownLocals, id: \.self) { url in
                    pendingLocalRow(url: url)
                }
                if overflow > 0 {
                    SummaryStatRow(
                        icon: "ellipsis.circle",
                        text: compressConfirmPluralCount("compress_confirm_more_locals", count: overflow),
                        textSecondary: true,
                        subheadline: true
                    )
                }
                ForEach(remoteURLs, id: \.self) { url in
                    pendingRemoteRow(url: url)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Self.fileListCardInset)
        }
        .frame(maxHeight: 420)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func pendingLocalRow(url: URL) -> some View {
        let media = MediaTypeDetector.detect(url)
        let icon = media.map { iconForMedia($0) } ?? "doc"
        let subtitle = localRowSubtitle(url: url, media: media)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func localRowSubtitle(url: URL, media: MediaType?) -> String {
        guard let media else {
            return String(localized: "Type unknown — will detect when compressing", comment: "Compression confirm: unknown media.")
        }
        switch media {
        case .image:
            if localURLs.count <= Self.maxPerFileFormatHints,
               let fmt = ImageCompressionFormatResolver.knownFormat(
                   formatOverride: nil,
                   preset: nil,
                   globalAutoFormat: prefs.autoFormat,
                   globalSelectedFormat: selectedFormat,
                   classifiedContent: classified[url]
               ) {
                return String.localizedStringWithFormat(
                    String(localized: "Image → .%@", comment: "Compression confirm: resolved output extension."),
                    fmt.outputExtension
                )
            }
            return String(localized: "Image", comment: "Compression confirm: media label.")
        case .pdf:
            return prefs.pdfPendingRowSubtitleLine()
        case .video:
            return prefs.videoPendingRowSubtitleLine()
        case .audio:
            return prefs.audioPendingRowSubtitleLine()
        }
    }

    private func pendingRemoteRow(url: URL) -> some View {
        let host = url.host ?? url.absoluteString
        let tail = url.path.isEmpty ? url.absoluteString : url.path
        let pathTail = (tail as NSString).lastPathComponent
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(host)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !pathTail.isEmpty, pathTail != "/" {
                    Text(pathTail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(String(localized: "Downloads before compressing.", comment: "Compression confirm: remote URL row."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Controls

    private var pdfFlattenChipOptions: [(String, String, String)] {
        PDFQuality.allCases.map { ($0.displayName, $0.rawValue, $0.description) }
    }

    private func clearActivePresetForManualEdit() {
        if !prefs.activePresetID.isEmpty {
            prefs.activePresetID = ""
        }
    }

    private func selectPreset(_ id: UUID?) {
        guard let id else {
            prefs.activePresetID = ""
            return
        }
        guard let preset = prefs.savedPresets.first(where: { $0.id == id }) else { return }
        var fmt = selectedFormat
        preset.apply(to: prefs, selectedFormat: &fmt)
        $selectedFormat.wrappedValue = fmt
        prefs.activePresetID = id.uuidString
    }

    private var presetPickerSelection: Binding<UUID?> {
        Binding(
            get: { UUID(uuidString: prefs.activePresetID) },
            set: { selectPreset($0) }
        )
    }

    private var clearingAutoFormatBinding: Binding<Bool> {
        Binding(
            get: { prefs.autoFormat },
            set: { new in
                clearActivePresetForManualEdit()
                prefs.autoFormat = new
            }
        )
    }

    private var clearingSelectedFormatBinding: Binding<CompressionFormat> {
        Binding(
            get: { selectedFormat },
            set: { new in
                clearActivePresetForManualEdit()
                $selectedFormat.wrappedValue = new
            }
        )
    }

    private var clearingSmartQualityBinding: Binding<Bool> {
        Binding(
            get: { prefs.smartQuality },
            set: { new in
                clearActivePresetForManualEdit()
                prefs.smartQuality = new
            }
        )
    }

    private var clearingVideoCodecBinding: Binding<String> {
        Binding(
            get: { prefs.videoCodecFamilyRaw },
            set: { new in
                clearActivePresetForManualEdit()
                prefs.videoCodecFamilyRaw = new
            }
        )
    }

    private var clearingAudioFormatBinding: Binding<String> {
        Binding(
            get: { prefs.audioFormatRaw },
            set: { new in
                clearActivePresetForManualEdit()
                prefs.audioFormatRaw = new
            }
        )
    }

    private var clearingAudioQualityBinding: Binding<String> {
        Binding(
            get: { prefs.audioQualityTierRaw },
            set: { new in
                clearActivePresetForManualEdit()
                prefs.audioQualityTierRaw = new
            }
        )
    }

    private var clearingPdfOutputModeBinding: Binding<PDFOutputMode> {
        Binding(
            get: { prefs.pdfOutputMode },
            set: { new in
                clearActivePresetForManualEdit()
                prefs.pdfOutputModeRaw = new.rawValue
            }
        )
    }

    private var clearingPdfQualityBinding: Binding<String> {
        Binding(
            get: { prefs.pdfQualityRaw },
            set: { new in
                clearActivePresetForManualEdit()
                prefs.pdfQualityRaw = new
            }
        )
    }

    private var clearingSaveLocationBinding: Binding<SaveLocation> {
        Binding(
            get: { prefs.saveLocation },
            set: { new in
                clearActivePresetForManualEdit()
                prefs.saveLocation = new
            }
        )
    }

    private var clearingFilenameHandlingBinding: Binding<FilenameHandling> {
        Binding(
            get: { prefs.filenameHandling },
            set: { new in
                clearActivePresetForManualEdit()
                prefs.filenameHandling = new
            }
        )
    }

    private var clearingCustomSuffixBinding: Binding<String> {
        Binding(
            get: { prefs.customSuffix },
            set: { new in
                clearActivePresetForManualEdit()
                prefs.customSuffix = new
            }
        )
    }

    private var clearingOriginalsActionBinding: Binding<OriginalsAction> {
        Binding(
            get: { prefs.originalsAction },
            set: { new in
                clearActivePresetForManualEdit()
                prefs.originalsAction = new
            }
        )
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                confirmMediaSectionHeader(
                    systemImage: "square.stack.3d.up.fill",
                    title: String(localized: "Preset", comment: "Compression confirm: preset section.")
                )
                Spacer(minLength: 0)
                if !prefs.savedPresets.isEmpty {
                    Button(String(localized: "Edit presets…", comment: "Compression confirm: open Presets tab.")) {
                        openPreferences(.presets)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }
            }

            Picker(String(localized: "Preset", comment: "Compression confirm: preset picker accessibility."), selection: presetPickerSelection) {
                Text(String(localized: "None", comment: "Compression confirm: no preset.")).tag(Optional<UUID>.none)
                ForEach(prefs.savedPresets) { preset in
                    Text(preset.name).tag(Optional.some(preset.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if presetLocked, let name = activePresetName {
                Text(String.localizedStringWithFormat(
                    String(localized: "Using preset “%@” — choose None to adjust settings here.", comment: "Compression confirm: preset locked hint; argument is preset name."),
                    name
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                if showImageControls {
                    confirmMediaSectionHeader(systemImage: "photo.on.rectangle.angled", title: String(localized: "Images", comment: "Compression confirm: media section."))
                    FormatChipPicker(
                        autoFormat: clearingAutoFormatBinding,
                        selectedFormat: clearingSelectedFormatBinding,
                        showActiveDescription: true
                    )
                }

                if showSmartQualityToggle {
                    Toggle(String(localized: "Smart quality (all types)", comment: "Sidebar: global smart quality for images, PDF, and video."), isOn: clearingSmartQualityBinding)
                        .font(.callout)
                    Text(String(localized: "When on, Dinky picks encoder strength per file (images, PDF flatten, video, audio). Turn off for manual choices in each section below.", comment: "Compression confirm: smart quality footnote."))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showVideoControls {
                    confirmMediaSectionHeader(systemImage: "film", title: String(localized: "Video", comment: "Compression confirm: media section."))
                    QualityChipPicker(
                        options: VideoCodecFamily.allCases.map { ($0.chipLabel, $0.rawValue, $0.description) },
                        selected: clearingVideoCodecBinding
                    )
                }

                if showPdfControls {
                    confirmMediaSectionHeader(systemImage: "doc.text.fill", title: String(localized: "PDF", comment: "Compression confirm: media section."))
                    Picker(String(localized: "PDF output", comment: "Compression confirm: PDF output picker accessibility."), selection: clearingPdfOutputModeBinding) {
                        ForEach(PDFOutputMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    if prefs.pdfOutputMode == .flattenPages {
                        QualityChipPicker(
                            options: pdfFlattenChipOptions,
                            selected: clearingPdfQualityBinding
                        )
                    }
                }

                if showAudioControls {
                    confirmMediaSectionHeader(systemImage: "waveform", title: String(localized: "Audio", comment: "Compression confirm: media section."))
                    Picker(String(localized: "Output format", comment: "Compression confirm: audio format picker."), selection: clearingAudioFormatBinding) {
                        ForEach(AudioConversionFormat.allCases, id: \.rawValue) { f in
                            Text(f.displayName).tag(f.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    if (AudioConversionFormat(rawValue: prefs.audioFormatRaw) ?? .aacM4A) == .mp3 {
                        Text(String(localized: "MP3 uses bundled LAME (LGPL); other formats use macOS conversion.", comment: "Compression confirm: LAME note."))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !prefs.smartQuality {
                        QualityChipPicker(
                            options: AudioConversionQualityTier.allCases.map { ($0.displayName, $0.rawValue, "") },
                            selected: clearingAudioQualityBinding
                        )
                    }
                }

                Picker(String(localized: "Save to", comment: "Settings UI."), selection: clearingSaveLocationBinding) {
                    Text(String(localized: "Same folder as original", comment: "Settings UI.")).tag(SaveLocation.sameFolder)
                    Text(String(localized: "Downloads folder", comment: "Settings UI.")).tag(SaveLocation.downloads)
                    Text(String(localized: "Custom folder…", comment: "Settings UI.")).tag(SaveLocation.custom)
                }
                .labelsHidden()
                .pickerStyle(.menu)

                if prefs.saveLocation == .custom {
                    HStack {
                        Text(prefs.customFolderDisplayPath.isEmpty
                             ? String(localized: "No folder selected", comment: "Settings UI.") : prefs.customFolderDisplayPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "Choose…", comment: "Settings UI.")) { pickCustomFolder() }
                            .buttonStyle(.bordered)
                    }
                }

                Picker(String(localized: "Filename", comment: "Settings UI."), selection: clearingFilenameHandlingBinding) {
                    Text(String(localized: "Append \"-dinky\" suffix", comment: "Settings UI.")).tag(FilenameHandling.appendSuffix)
                    Text(String(localized: "Replace original", comment: "Settings UI.")).tag(FilenameHandling.replaceOrigin)
                    Text(String(localized: "Custom suffix", comment: "Settings UI.")).tag(FilenameHandling.customSuffix)
                }
                .labelsHidden()
                .pickerStyle(.menu)

                if prefs.filenameHandling == .customSuffix {
                    HStack {
                        Text(String(localized: "Suffix", comment: "Settings UI."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(String(localized: "-dinky", comment: "Settings UI."), text: clearingCustomSuffixBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                }

                Picker(String(localized: "After compressing, originals:", comment: "Settings UI."), selection: clearingOriginalsActionBinding) {
                    Text(String(localized: "Stay where they are", comment: "Settings UI.")).tag(OriginalsAction.keep)
                    Text(String(localized: "Move to Trash", comment: "Settings UI.")).tag(OriginalsAction.trash)
                    Text(String(localized: "Move to Backup folder", comment: "Settings UI.")).tag(OriginalsAction.backup)
                }
                .labelsHidden()
                .pickerStyle(.menu)

                if prefs.originalsAction == .backup {
                    HStack {
                        Text(prefs.originalsBackupFolderDisplayPath.isEmpty
                             ? prefs.defaultOriginalsBackupFolderURL().path
                             : prefs.originalsBackupFolderDisplayPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "Choose…", comment: "Settings UI.")) { pickOriginalsBackupFolder() }
                            .buttonStyle(.bordered)
                        if !prefs.originalsBackupFolderBookmark.isEmpty {
                            Button(String(localized: "Use default", comment: "Settings UI.")) {
                                clearActivePresetForManualEdit()
                                prefs.originalsBackupFolderBookmark = Data()
                                prefs.originalsBackupFolderDisplayPath = ""
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .disabled(presetLocked)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func confirmMediaSectionHeader(systemImage: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private func pickCustomFolder() {
        clearActivePresetForManualEdit()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose", comment: "Open panel default button.")
        if panel.runModal() == .OK, let url = panel.url {
            prefs.customFolderDisplayPath = url.path
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                prefs.customFolderBookmark = bookmark
            }
            prefs.saveLocation = .custom
        }
    }

    private func pickOriginalsBackupFolder() {
        clearActivePresetForManualEdit()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose", comment: "Open panel default button.")
        if panel.runModal() == .OK, let url = panel.url {
            prefs.originalsBackupFolderDisplayPath = url.path
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                prefs.originalsBackupFolderBookmark = bookmark
            }
        }
    }

    private var leadText: String {
        if localCount > 0, remoteCount > 0 {
            let files = compressConfirmPluralCount("compress_confirm_add_files", count: localCount)
            let links = compressConfirmPluralCount("compress_confirm_links", count: remoteCount)
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "compress_confirm_lead_add_and_fetch",
                    bundle: .main,
                    comment: "Compression confirm lead; arguments are pluralized count phrases."
                ),
                files, links
            )
        }
        if remoteCount > 0 {
            let links = compressConfirmPluralCount("compress_confirm_links", count: remoteCount)
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "compress_confirm_lead_fetch",
                    bundle: .main,
                    comment: "Compression confirm lead; argument is a pluralized link count phrase."
                ),
                links
            )
        }
        if localCount > 0 {
            let files = compressConfirmPluralCount("compress_confirm_add_files", count: localCount)
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "compress_confirm_lead_add",
                    bundle: .main,
                    comment: "Compression confirm lead; argument is a pluralized file count phrase."
                ),
                files
            )
        }
        return String(localized: "You’re about to add files to the queue.", comment: "Compression confirm lead fallback.")
    }
}
