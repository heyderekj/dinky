import SwiftUI
import DinkyCoreShared

private struct SidebarContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// `ScrollView` expands vertically to fill its proposal; `maxHeight` only caps the maximum, so the
/// panel still grows with the window. A fixed height (from measured content) makes the glass hug it.
private struct SidebarMeasuredHeight: ViewModifier {
    var height: CGFloat?

    func body(content: Content) -> some View {
        if let height {
            content.frame(height: height, alignment: .top)
        } else {
            content.frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Rounded container matching simple-mode cards so full / preset-active sidebars share the same language.
private struct SidebarCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.05)))
    }
}

private enum SidebarScope: String, CaseIterable, Identifiable {
    case images, videos, audio, pdfs, output
    var id: String { rawValue }
    var title: String {
        switch self {
        case .images: return "Images"
        case .pdfs: return "PDFs"
        case .videos: return "Videos"
        case .audio: return "Audio"
        case .output: return "Output"
        }
    }
    var icon: String {
        switch self {
        case .images: return "photo"
        case .pdfs: return "doc.text"
        case .videos: return "video"
        case .audio: return "waveform"
        case .output: return "square.and.arrow.up"
        }
    }

    /// Compact label for the four-column scope strip (narrow sidebar).
    var tabShortTitle: String {
        switch self {
        case .images: return "Images"
        case .videos: return "Video"
        case .audio: return "Audio"
        case .pdfs: return "PDFs"
        case .output: return "Output"
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @Binding var selectedFormat: CompressionFormat
    /// Opens the Settings window and selects the given tab (use `Environment(\.openSettings)` from the main window).
    var openPreferences: (PreferencesTab) -> Void

    @State private var contentHeight: CGFloat? = nil

    @AppStorage("sidebar.expanded.presets") private var expandedPresets = false
    /// Simple-mode “What to expect” detail map; default off so new sessions start collapsed.
    @AppStorage("sidebar.expandedOutcomeMap") private var expandedOutcomeMap = false
    @AppStorage("sidebar.selectedScope") private var scopeRaw: String = SidebarScope.images.rawValue

    private var presetActive: Bool { !prefs.activePresetID.isEmpty }

    private var availableMediaScopes: [SidebarScope] {
        var list: [SidebarScope] = []
        if prefs.showImagesSection { list.append(.images) }
        if prefs.showVideosSection { list.append(.videos) }
        if prefs.showAudioSection { list.append(.audio) }
        if prefs.showPDFsSection { list.append(.pdfs) }
        return list
    }

    /// Media tabs only; `.output` is chosen separately so the strip does not squeeze five segments into 260pt.
    private var availableScopes: [SidebarScope] {
        var list = availableMediaScopes
        list.append(.output)
        return list
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {

                if !prefs.savedPresets.isEmpty {
                    presetsSection
                }

                if presetActive {
                    if let active = prefs.savedPresets.first(where: { $0.id.uuidString == prefs.activePresetID }) {
                        presetSummaryWithChrome(active).transition(.opacity)
                    }
                } else if prefs.sidebarSimpleMode {
                    simpleModeExtras
                } else {
                    fullSidebarChrome
                }
            }
            .padding(12)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            // ScrollView proposes unbounded vertical space; without this the stack stretches and the
            // height preference / glass panel match the window instead of the real content.
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: SidebarContentHeightKey.self, value: geo.size.height)
                }
            )
        }
        .onPreferenceChange(SidebarContentHeightKey.self) { h in
            // Preference default is 0; first layout pass can briefly report 0 — never collapse on that.
            guard h > 0.5 else { return }
            contentHeight = h
        }
        // Propose the final width before clipping so segmented controls and text wrap inside the panel
        // instead of overflowing horizontally (which looked like left-edge clipping).
        .frame(width: 260, alignment: .topLeading)
        .clipped()
        .modifier(SidebarMeasuredHeight(height: contentHeight))
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: prefs.maxWidthEnabled)
        .animation(.easeInOut(duration: 0.2), value: prefs.maxFileSizeEnabled)
        .animation(.easeInOut(duration: 0.2), value: prefs.openFolderWhenDone)
        .animation(.easeInOut(duration: 0.2), value: prefs.stripMetadata)
        .animation(.easeInOut(duration: 0.2), value: prefs.sanitizeFilenames)
        .animation(.easeInOut(duration: 0.2), value: prefs.smartQuality)
        .animation(.easeInOut(duration: 0.2), value: prefs.contentTypeHintRaw)
        .animation(.easeInOut(duration: 0.2), value: prefs.autoFormat)
        .animation(.easeInOut(duration: 0.2), value: presetActive)
        .animation(.easeInOut(duration: 0.2), value: prefs.showImagesSection)
        .animation(.easeInOut(duration: 0.2), value: prefs.showPDFsSection)
        .animation(.easeInOut(duration: 0.2), value: prefs.showVideosSection)
        .animation(.easeInOut(duration: 0.2), value: prefs.showAudioSection)
        .animation(.easeInOut(duration: 0.2), value: prefs.audioFormatRaw)
        .animation(.easeInOut(duration: 0.2), value: prefs.audioQualityTierRaw)
        .animation(.easeInOut(duration: 0.2), value: prefs.pdfMaxFileSizeEnabled)
        .animation(.easeInOut(duration: 0.2), value: prefs.pdfOutputModeRaw)
        .animation(.easeInOut(duration: 0.2), value: prefs.pdfEnableOCR)
        .animation(.easeInOut(duration: 0.2), value: prefs.videoRemoveAudio)
        .animation(.easeInOut(duration: 0.2), value: prefs.videoCodecFamilyRaw)
        .animation(.easeInOut(duration: 0.2), value: prefs.videoMaxResolutionEnabled)
        .animation(.easeInOut(duration: 0.2), value: prefs.videoMaxResolutionLines)
        .animation(.easeInOut(duration: 0.2), value: prefs.videoMaxFPSEnabled)
        .animation(.easeInOut(duration: 0.2), value: prefs.videoMaxFPS)
        .animation(.easeInOut(duration: 0.2), value: prefs.sidebarSimpleMode)
        .animation(.easeInOut(duration: 0.2), value: scopeRaw)
        .accessibilityLabel(String(localized: "Compression settings", comment: "VoiceOver: sidebar."))
        .accessibilityHint("Choose format, quality, and output options for images, videos, audio, and PDFs.")
        .onChange(of: prefs.showImagesSection) { _, _ in syncScopeIfNeeded() }
        .onChange(of: prefs.showPDFsSection) { _, _ in syncScopeIfNeeded() }
        .onChange(of: prefs.showVideosSection) { _, _ in syncScopeIfNeeded() }
        .onChange(of: prefs.showAudioSection) { _, _ in syncScopeIfNeeded() }
        .onAppear { snapPdfFlattenQualityIfNeeded() }
        .onChange(of: prefs.pdfMaxFileSizeEnabled) { _, _ in snapPdfFlattenQualityIfNeeded() }
        .onChange(of: prefs.pdfMaxFileSizeKB) { _, _ in snapPdfFlattenQualityIfNeeded() }
        .onChange(of: prefs.pdfOutputModeRaw) { _, _ in snapPdfFlattenQualityIfNeeded() }
    }

    /// Keeps manual flatten tier in sync with max-size UI (higher tiers hidden for tight caps).
    private func snapPdfFlattenQualityIfNeeded() {
        guard prefs.pdfOutputMode == .flattenPages else { return }
        let allowed = PDFQuality.flattenUIShowableTiers(
            maxFileSizeEnabled: prefs.pdfMaxFileSizeEnabled,
            pdfMaxFileSizeKB: prefs.pdfMaxFileSizeKB
        )
        let current = PDFQuality(rawValue: prefs.pdfQualityRaw) ?? .medium
        let snapped = PDFQuality.snapFlattenStartTier(current, allowed: allowed)
        if snapped != current { prefs.pdfQualityRaw = snapped.rawValue }
    }

    private var pdfFlattenQualityChipOptions: [(String, String, String)] {
        let tiers = PDFQuality.flattenUIShowableTiers(
            maxFileSizeEnabled: prefs.pdfMaxFileSizeEnabled,
            pdfMaxFileSizeKB: prefs.pdfMaxFileSizeKB
        )
        return tiers.map { ($0.displayName, $0.rawValue, $0.description) }
    }

    // MARK: - Presets (shared)

    private var presetsSection: some View {
        sectionGroup(icon: "slider.horizontal.below.square.and.square.filled",
                     title: "Presets", isExpanded: $expandedPresets) {
            VStack(spacing: 3) {
                presetRow(id: "", name: "None", subtitle: "No preset",
                          isActive: prefs.activePresetID.isEmpty) {
                    prefs.activePresetID = ""
                }
                ForEach(prefs.savedPresets) { preset in
                    presetRow(
                        id: preset.id.uuidString,
                        name: preset.name,
                        subtitle: preset.includedMediaTypesSummaryLabel,
                        isActive: prefs.activePresetID == preset.id.uuidString
                    ) {
                        var fmt = selectedFormat
                        preset.apply(to: prefs, selectedFormat: &fmt)
                        selectedFormat = fmt
                        prefs.activePresetID = preset.id.uuidString
                    }
                }
            }
            settingsShortcutRow(title: "Edit presets", systemImage: "slider.horizontal.3") {
                openPreferences(.presets)
            }
        }
    }

    // MARK: - Simple sidebar

    private var simpleModeExtras: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarCard {
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionHeading(icon: "slider.horizontal.2.square.on.square", title: "Quick choices")

                    Toggle(String(localized: "Choose format and strength automatically", comment: "Sidebar simple mode: single automatic toggle; exits simple mode when turned off."), isOn: Binding(
                        get: { true },
                        set: { _ in
                            prefs.smartQuality = true
                            prefs.autoFormat = true
                            prefs.applySidebarSimpleMode(false)
                        }
                    ))
                    .font(.system(size: 11))
                    .accessibilityHint(String(localized: "Dinky picks WebP, AVIF, or another output format per image — new files, not a same-format JPEG squeeze. Turn off Quick choices to configure manually.", comment: "VoiceOver: simple mode automatic toggle."))

                    simpleModeOutcomeMap

                    Toggle("Open the folder when finished", isOn: Binding(
                        get: { prefs.openFolderWhenDone }, set: { prefs.openFolderWhenDone = $0 }
                    ))
                    .font(.system(size: 11))
                }
            }

            SidebarCard {
                VStack(alignment: .leading, spacing: 6) {
                    settingsSectionHeading(icon: "folder", title: "Where files go")
                    Text(outputDestinationLine)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(outputFilenameLine)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button(String(localized: "Change folder or naming…", comment: "Sidebar link to output settings.")) {
                        openPreferences(.output)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                }
            }

            SidebarCard {
                VStack(alignment: .leading, spacing: 4) {
                    settingsSectionHeading(icon: "arrow.up.right.square", title: "Shortcuts")
                    settingsShortcutRow(title: "Presets", systemImage: "slider.horizontal.3") {
                        openPreferences(.presets)
                    }
                    settingsShortcutRow(title: "Watch folders", systemImage: "eye") {
                        openPreferences(.watch)
                    }
                    settingsShortcutRow(title: "All settings", systemImage: "gearshape") {
                        openPreferences(.behavior)
                    }
                }
            }

            Button {
                prefs.applySidebarSimpleMode(false)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 12, weight: .medium))
                    Text(String(localized: "All options…", comment: "Sidebar disclosure label."))
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    /// One-line teaser + ``DisclosureGroup`` so the sidebar stays light until expanded.
    private var simpleModeOutcomeMap: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !expandedOutcomeMap {
                Text(simpleModeOutcomeSummaryLine())
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup(isExpanded: $expandedOutcomeMap) {
                VStack(alignment: .leading, spacing: 8) {
                    simpleModeOutcomeRow(
                        icon: "photo",
                        title: String(localized: "Images", comment: "Outcome map row title."),
                        friendly: simpleModeImageOutcomeFriendly(),
                        technical: simpleModeImageOutcomeTechnical()
                    )
                    simpleModeOutcomeRow(
                        icon: "doc.text",
                        title: String(localized: "PDFs", comment: "Outcome map row title."),
                        friendly: simpleModePDFFriendly(),
                        technical: simpleModePDFTechnical()
                    )
                    simpleModeOutcomeRow(
                        icon: "film",
                        title: String(localized: "Videos", comment: "Outcome map row title."),
                        friendly: simpleModeVideoFriendly(),
                        technical: simpleModeVideoTechnical()
                    )
                    if prefs.showAudioSection {
                        simpleModeOutcomeRow(
                            icon: "waveform",
                            title: String(localized: "Audio", comment: "Outcome map row title."),
                            friendly: simpleModeAudioFriendly(),
                            technical: simpleModeAudioTechnical()
                        )
                    }
                    simpleModeOutcomeRow(
                        icon: "square.and.arrow.up",
                        title: String(localized: "Output", comment: "Outcome map row title; matches Output scope tab."),
                        friendly: simpleModeOutputFriendly(),
                        technical: simpleModeOutputOutcome()
                    )
                }
                .padding(.top, 4)
                .accessibilityElement(children: .contain)
            } label: {
                Text(String(localized: "What to expect", comment: "Heading above simple-mode outcome rows."))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityHint(
                expandedOutcomeMap
                    ? String(localized: "Collapses the list of details.", comment: "VoiceOver: What to expect header when expanded.")
                    : String(localized: "Expands friendly and technical details for each type.", comment: "VoiceOver: What to expect header when collapsed.")
            )
        }
        .padding(.top, 2)
    }

    private func simpleModeOutcomeSummaryLine() -> String {
        if prefs.smartQuality {
            if prefs.autoFormat {
                return String(localized: "Dinky auto-picks modern image formats and tuning per file; same Smart Quality adjusts PDFs, video, and audio. Expand for details.", comment: "Simple sidebar outcome one-liner, smart on, auto format.")
            }
            return String(localized: "Smart Quality tunes each file from content; you still choose some format chips in All options. Expand for details.", comment: "Simple sidebar outcome one-liner, smart on, manual image format.")
        }
        return String(localized: "Fixed tiers in All options… apply until you turn Smart Quality back on. Expand for details.", comment: "Simple sidebar outcome one-liner, smart off.")
    }

    @ViewBuilder
    private func simpleModeOutcomeRow(icon: String, title: String, friendly: String, technical: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(0.9))
                .frame(width: 16, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.9))
                Text(friendly)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(technical)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String.localizedStringWithFormat(
                String(localized: "%@. %@ %@", comment: "VoiceOver: one outcome row; title, friendly sentence, technical sentence."),
                title, friendly, technical
            )
        )
    }

    private func simpleModeImageOutcomeFriendly() -> String {
        if prefs.smartQuality {
            if prefs.autoFormat {
                return String(localized: "Converts each image to a modern format (AVIF or WebP when Auto is on) and sets strength automatically.", comment: "Outcome map friendly: images, smart, auto format.")
            }
            return String(localized: "Uses your format chip — outputs that format and tweaks strength per image.", comment: "Outcome map friendly: images, smart, manual format.")
        }
        if prefs.autoFormat {
            return String(localized: "Converts to WebP or AVIF; you set the overall strength style in All options.", comment: "Outcome map friendly: images, fixed tiers, auto format.")
        }
        return String(localized: "Uses your format chips; strength style lives in All options.", comment: "Outcome map friendly: images, fixed tiers, manual format.")
    }

    private func simpleModeImageOutcomeTechnical() -> String {
        if prefs.smartQuality {
            if prefs.autoFormat {
                return String(localized: "Converts each image to WebP or AVIF (new files); compression strength adapts per file.", comment: "Simple outcome: images, smart on, auto format on.")
            }
            return String(
                format: String(localized: "%@ from the chips; compression strength adapts per file.", comment: "Simple outcome: images, smart on, manual format; argument is format name."),
                selectedFormat.displayName
            )
        }
        if prefs.autoFormat {
            return String(localized: "Converts to WebP or AVIF; strength style (Photo / Graphic / Mixed) in All options… below.", comment: "Simple outcome: images, smart off, auto format.")
        }
        return String(
            format: String(localized: "%@ from the chips; strength style in All options… below.", comment: "Simple outcome: images, smart off, manual format; argument is format name."),
            selectedFormat.displayName
        )
    }

    private func simpleModePDFFriendly() -> String {
        var base: String
        if prefs.smartQuality {
            base = String(localized: "Balances size and readability; you choose text vs flatten in All options.", comment: "Outcome map friendly: PDFs smart.")
        } else {
            base = String(localized: "You control flattening, quality, and grayscale in All options.", comment: "Outcome map friendly: PDFs fixed.")
        }
        if prefs.pdfEnableOCR {
            base += " " + String(localized: "Scan-like PDFs can be made searchable with OCR first.", comment: "Outcome map friendly: PDF OCR sentence append.")
        }
        return base
    }

    private func simpleModePDFTechnical() -> String {
        var base: String
        if prefs.smartQuality {
            base = String(localized: "PDF: flatten or keep text (All options…); tier chosen per file when flattening.", comment: "Simple outcome: PDFs with smart quality.")
        } else {
            base = String(localized: "PDF: preserve vs flatten, quality, and grayscale in All options… below.", comment: "Simple outcome: PDFs without smart quality.")
        }
        if prefs.pdfEnableOCR {
            base += " " + String(localized: "OCR runs on scans when enabled.", comment: "Simple outcome: PDF OCR technical append.")
        }
        return base
    }

    private func simpleModeVideoFriendly() -> String {
        if prefs.smartQuality {
            return String(localized: "Adjusts quality per clip; bright HDR footage is handled sensibly.", comment: "Outcome map friendly: video smart.")
        }
        return String(localized: "You pick codec, quality, and max resolution in All options.", comment: "Outcome map friendly: video fixed.")
    }

    private func simpleModeVideoTechnical() -> String {
        if prefs.smartQuality {
            return String(localized: "MP4: encoding strength adapts per clip (HDR uses HEVC when needed).", comment: "Simple outcome: videos with smart quality.")
        }
        return String(localized: "MP4: codec (H.264 / HEVC), quality, and resolution cap in All options… below.", comment: "Simple outcome: videos without smart quality.")
    }

    private func simpleModeAudioFriendly() -> String {
        let fmt = prefs.audioConversionFormat
        if prefs.smartQuality {
            return String(localized: "Exports each track using Smart Quality picks from bitrate when helpful; otherwise respects your chosen format.", comment: "Simple outcome: audio with smart quality.")
        }
        return String.localizedStringWithFormat(
            String(localized: "Exports to %@ with your chosen bitrate tier.", comment: "Simple outcome: audio without smart quality; argument is format name."),
            fmt.displayName
        )
    }

    private func simpleModeAudioTechnical() -> String {
        let fmt = prefs.audioConversionFormat
        if fmt == .mp3 {
            return String(localized: "MP3 uses bundled LAME; other formats use macOS audio conversion.", comment: "Simple outcome: audio technical with MP3.")
        }
        return String(localized: "Cross-converts with macOS conversion tools.", comment: "Simple outcome: audio technical non-MP3.")
    }

    private func simpleModeOutputFriendly() -> String {
        String(localized: "Saves where you chose in Settings; optionally reveals the folder when done.", comment: "Outcome map friendly: output.")
    }

    private func simpleModeOutputOutcome() -> String {
        let dest = outputDestinationLine
        let naming = outputFilenameLine
        let reveal = prefs.openFolderWhenDone
            ? String(localized: "Opens the output folder when finished.", comment: "Simple outcome: open folder when done on.")
            : String(localized: "Leaves the window as-is (does not open the folder).", comment: "Simple outcome: open folder when done off.")
        return "\(dest); \(naming). \(reveal)"
    }

    // MARK: - Full sidebar (scoped)

    /// Cross-cutting Smart Quality + compact media scope + always-visible Output entry.
    private var smartQualityGlobalRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(String(localized: "Smart quality (all types)", comment: "Sidebar: global smart quality for images, PDF, video, and audio."), isOn: Binding(
                get: { prefs.smartQuality }, set: { prefs.smartQuality = $0 }
            ))
            .font(.system(size: 11))
            if prefs.smartQuality {
                settingsHelperText(String(localized: "Picks encoder strength per image, per video clip, per audio file from content, and PDF flatten tier per document. Turn off to set fixed tiers per scope below.", comment: "Sidebar: unified smart quality helper."))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var mediaScopeIconRow: some View {
        HStack(spacing: 4) {
            ForEach(availableMediaScopes) { scope in
                scopeIconButton(scope)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Adjust scope", comment: "Accessibility: sidebar media scope icons."))
    }

    private func scopeIconButton(_ scope: SidebarScope) -> some View {
        let selected = effectiveScope == scope
        return Button {
            scopeRaw = scope.rawValue
        } label: {
            Image(systemName: scope.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? AnyShapeStyle(dinkyGradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scope.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var outputScopeButton: some View {
        let selected = effectiveScope == .output
        return Button {
            scopeRaw = SidebarScope.output.rawValue
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .medium))
                Text(String(localized: "Output & files", comment: "Sidebar: scope control for output options."))
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AnyShapeStyle(dinkyGradient) : AnyShapeStyle(Color.accentColor.opacity(0.12)))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Output", comment: "VoiceOver: Output scope."))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fullSidebarChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Format section
            VStack(alignment: .leading, spacing: 10) {
                settingsSectionHeading(icon: "slider.horizontal.3", title: "Adjust")
                smartQualityGlobalRow
                if !availableMediaScopes.isEmpty {
                    mediaScopeIconRow
                }
                Group {
                    switch effectiveScope {
                    case .images: imagesPanel
                    case .pdfs:   pdfsPanel
                    case .videos: videosPanel
                    case .audio:  audioPanel
                    case .output: EmptyView()
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: effectiveScope)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Output section
            sidebarOutputSection

            // Footer links + overflow
            sidebarFooterLinks
        }
    }

    private var sidebarOutputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsSectionHeading(icon: "square.and.arrow.up", title: "Output")

            // Destination + filename summary
            VStack(alignment: .leading, spacing: 3) {
                Text(outputDestinationLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(outputFilenameLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Output toggles
            Toggle(String(localized: "Reveal in Finder when done", comment: "Sidebar output: open folder toggle."), isOn: Binding(
                get: { prefs.openFolderWhenDone }, set: { prefs.openFolderWhenDone = $0 }
            )).font(.system(size: 11))
            Toggle(String(localized: "Strip metadata", comment: "Sidebar output: strip metadata toggle."), isOn: Binding(
                get: { prefs.stripMetadata }, set: { prefs.stripMetadata = $0 }
            )).font(.system(size: 11))
            Toggle(String(localized: "Sanitize filenames", comment: "Sidebar output: sanitize filenames toggle."), isOn: Binding(
                get: { prefs.sanitizeFilenames }, set: { prefs.sanitizeFilenames = $0 }
            )).font(.system(size: 11))

            settingsShortcutRow(
                title: String(localized: "Output preferences…", comment: "Sidebar: link to Output settings pane."),
                systemImage: "arrow.right"
            ) { openPreferences(.output) }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sidebarFooterLinks: some View {
        VStack(alignment: .leading, spacing: 2) {
            settingsShortcutRow(
                title: String(localized: "Presets", comment: "Sidebar footer: open Presets settings."),
                systemImage: "slider.horizontal.3"
            ) { openPreferences(.presets) }
            settingsShortcutRow(
                title: String(localized: "Watch folders", comment: "Sidebar footer: open Watch settings."),
                systemImage: "eye"
            ) { openPreferences(.watch) }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Menu {
                    Button(String(localized: "Use simple sidebar", comment: "Sidebar footer: switch back to simple mode.")) {
                        prefs.smartQuality = true
                        prefs.autoFormat = true
                        prefs.applySidebarSimpleMode(true)
                    }
                    Button(String(localized: "Which sections appear here…", comment: "Sidebar section picker hint.")) {
                        openPreferences(.sidebar)
                    }
                    Button(String(localized: "All settings…", comment: "Sidebar menu: open settings.")) {
                        openPreferences(.behavior)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsShortcutRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private func syncScopeIfNeeded() {
        let cur = SidebarScope(rawValue: scopeRaw) ?? .images
        if !availableMediaScopes.contains(cur) {
            scopeRaw = availableMediaScopes.first?.rawValue ?? SidebarScope.images.rawValue
        }
    }

    private var outputDestinationLine: String { prefs.outputDestinationSummaryLine() }

    private var outputFilenameLine: String { prefs.outputFilenameSummaryLine() }

    private var effectiveScope: SidebarScope {
        let cur = SidebarScope(rawValue: scopeRaw) ?? .images
        if availableMediaScopes.contains(cur) { return cur }
        return availableMediaScopes.first ?? .images
    }

    // MARK: - Scoped panels

    private var imagesPanel: some View { imagesContent }
    private var pdfsPanel: some View { pdfsContent }
    private var videosPanel: some View { videosContent }
    private var audioPanel: some View { audioContent }
    private var outputPanel: some View { outputContent }

    // MARK: - Type section contents

    @ViewBuilder
    private var imagesContent: some View {
        settingsSubHeader(icon: "photo.on.rectangle.angled", "Format")
        FormatChipPicker(
            autoFormat: Binding(get: { prefs.autoFormat }, set: { prefs.autoFormat = $0 }),
            selectedFormat: $selectedFormat
        )

        SettingsSectionDivider()

        settingsSubHeader(icon: "wand.and.stars", "Quality")
        if prefs.smartQuality {
            settingsHelperText(String(localized: "Smart quality is on — encoder strength is picked per file automatically.", comment: "Sidebar images: smart quality active, quality section placeholder."))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Images", comment: "Sidebar quality subsection label."))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ContentTypeChipPicker(contentTypeHintRaw: Binding(
                    get: { prefs.contentTypeHintRaw }, set: { prefs.contentTypeHintRaw = $0 }
                ))
                if prefs.pdfOutputMode == .flattenPages {
                    Text(String(localized: "PDF", comment: "Sidebar quality subsection label."))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 2)
                    QualityChipPicker(
                        options: pdfFlattenQualityChipOptions,
                        selected: Binding(get: { prefs.pdfQualityRaw }, set: { prefs.pdfQualityRaw = $0 })
                    )
                }
                Text(String(localized: "Video", comment: "Sidebar quality subsection label."))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.top, 2)
                QualityChipPicker(
                    options: VideoQuality.allCases.map { ($0.displayName, $0.rawValue, $0.description) },
                    selected: Binding(get: { prefs.videoQualityRaw }, set: { prefs.videoQualityRaw = $0 })
                )
                Text(String(localized: "Audio", comment: "Sidebar quality subsection label."))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.top, 2)
                QualityChipPicker(
                    options: AudioConversionQualityTier.allCases.map { ($0.displayName, $0.rawValue, "") },
                    selected: Binding(get: { prefs.audioQualityTierRaw }, set: { prefs.audioQualityTierRaw = $0 })
                )
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
            ))
        }

        SettingsSectionDivider()

        settingsSubHeader(icon: "arrow.left.and.right", "Max width")
        Toggle("Resize to a maximum width", isOn: Binding(
            get: { prefs.maxWidthEnabled }, set: { prefs.maxWidthEnabled = $0 }
        )).toggleStyle(.switch).font(.system(size: 11))
        if prefs.maxWidthEnabled {
            VStack(alignment: .leading, spacing: 8) {
                settingsChipGrid(presets: settingsWidthPresets, current: prefs.maxWidth, fixedColumnCount: 3) { prefs.maxWidth = $0 }
                HStack(spacing: 6) {
                    TextField("1920", value: Binding(
                        get: { prefs.maxWidth }, set: { prefs.maxWidth = max(1, $0) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 70)
                    Text(String(localized: "px", comment: "Unit: pixels.")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                settingsHelperText("Try 1920 for web, 1280 for social, 640 for email.")
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
            ))
        }

        SettingsSectionDivider()

        settingsSubHeader(icon: "gauge.with.dots.needle.67percent", "Max file size")
        Toggle("Target a smaller file size", isOn: Binding(
            get: { prefs.maxFileSizeEnabled }, set: { prefs.maxFileSizeEnabled = $0 }
        )).toggleStyle(.switch).font(.system(size: 11))
        if prefs.maxFileSizeEnabled {
            VStack(alignment: .leading, spacing: 8) {
                settingsChipGrid(presets: settingsSizePresets, current: prefs.maxFileSizeKB) { prefs.maxFileSizeKB = $0 }
                HStack(spacing: 6) {
                    TextField("2", value: Binding(
                        get: { prefs.maxFileSizeMB }, set: { prefs.maxFileSizeMB = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 70)
                    Text(String(localized: "MB", comment: "Unit: megabytes.")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                settingsHelperText("Encoder aims near this cap; exact size varies by image.")
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
            ))
        }
    }

    /// Full-width stacked choices (radio-style) — avoids cramped segmented controls in a narrow sidebar.
    private func pdfOutputModeChoice(_ mode: PDFOutputMode, title: String, subtitle: String) -> some View {
        let isSelected = prefs.pdfOutputMode == mode
        return Button {
            prefs.pdfOutputModeRaw = mode.rawValue
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.28))
                    .frame(width: 16, alignment: .center)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pdfsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingsSubHeader(icon: "doc.text.viewfinder", "Output")
            VStack(alignment: .leading, spacing: 4) {
                pdfOutputModeChoice(
                    .preserveStructure,
                    title: String(localized: "Preserve text and links", comment: "Sidebar PDF mode title."),
                    subtitle: String(localized: "Best-effort size: qpdf stream optimization, then PDFKit. Often no gain on exports that are already optimized. Keeps selectable text, links, and forms.", comment: "Sidebar PDF preserve mode subtitle.")
                )
                pdfOutputModeChoice(
                    .flattenPages,
                    title: String(localized: "Smallest file (flatten pages)", comment: "Sidebar PDF mode title."),
                    subtitle: String(localized: "Default for real compression: each page becomes a JPEG image. Use quality and optional grayscale below. No text selection.", comment: "Sidebar PDF flatten mode subtitle.")
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "PDF output mode", comment: "VoiceOver: PDF mode picker."))

            SettingsSectionDivider()

            settingsSubHeader(icon: "doc.text.magnifyingglass", String(localized: "Scanned PDFs", comment: "Sidebar PDF OCR header."))
            Toggle(String(localized: "Make scanned PDFs searchable (OCR)", comment: "Sidebar PDF OCR toggle."), isOn: Binding(
                get: { prefs.pdfEnableOCR }, set: { prefs.pdfEnableOCR = $0 }
            )).font(.system(size: 11))
            settingsHelperText(String(localized: "Adds a text layer on scan-like PDFs before compression; normal documents skip this.", comment: "Sidebar PDF OCR helper."))
            if prefs.pdfEnableOCR {
                Picker(String(localized: "OCR languages", comment: "Sidebar PDF OCR language picker."), selection: Binding(
                    get: { prefs.pdfOCRLanguages.first ?? "en-US" },
                    set: { prefs.pdfOCRLanguages = [$0] }
                )) {
                    Text("English (US)").tag("en-US")
                    Text("English (UK)").tag("en-GB")
                    Text("Français").tag("fr-FR")
                    Text("Deutsch").tag("de-DE")
                    Text("Español").tag("es-ES")
                    Text("Italiano").tag("it-IT")
                    Text("Português (Brasil)").tag("pt-BR")
                    Text("日本語").tag("ja-JP")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                settingsHelperText(String(localized: "Pick the language closest to your scans (on-device Vision).", comment: "Sidebar PDF OCR language helper."))
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                        removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                    ))
            }

            if prefs.pdfOutputMode == .preserveStructure {
                VStack(alignment: .leading, spacing: 4) {
                    settingsHelperText(String(localized: "Tries qpdf first (stream recompression), then PDFKit. Output is only kept when smaller than the original. Expect “no gain” on many web and export PDFs — that is normal. For reliable shrink, use Smallest file (flatten pages).", comment: "Sidebar PDF: preserve mode size expectations."))
                    settingsHelperText(String(localized: "Quality tiers and grayscale apply when you choose Smallest file (flatten pages).", comment: "Sidebar PDF: flatten options pointer."))

                    SettingsSectionDivider()

                    settingsSubHeader(icon: "flask", String(localized: "Advanced (experimental)", comment: "Sidebar PDF: experimental preserve subsection."))
                    Picker(String(localized: "Experimental preserve pass", comment: "Sidebar PDF: VoiceOver label for experimental picker."), selection: Binding(
                        get: { prefs.pdfPreserveExperimental },
                        set: { prefs.pdfPreserveExperimental = $0 }
                    )) {
                        ForEach(PDFPreserveExperimentalMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    settingsHelperText(String(localized: "Optional extra qpdf steps when normal preserve isn’t enough. Can affect tagged PDF structure or image sharpness. Use Off unless you need more shrink while keeping text and links.", comment: "Sidebar PDF: experimental preserve risk copy."))

                    SettingsSectionDivider()

                    settingsSubHeader(icon: "arrow.down.left.and.arrow.up.right", String(localized: "Image resolution", comment: "Sidebar PDF: image downsampling subsection."))
                    Toggle(String(localized: "Downsample embedded images", comment: "Sidebar PDF: downsampling toggle."), isOn: Binding(
                        get: { prefs.pdfResolutionDownsampling }, set: { prefs.pdfResolutionDownsampling = $0 }
                    )).toggleStyle(.switch).font(.system(size: 11))
                    settingsHelperText(String(localized: "Rasterizes image-heavy pages at 144 DPI while keeping text pages selectable. Biggest gain on 300/600 DPI scans. Text pages are unchanged.", comment: "Sidebar PDF: downsampling helper."))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                    removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                ))
            }

            if prefs.pdfOutputMode == .flattenPages {
                SettingsSectionDivider()

                settingsSubHeader(icon: "circle.lefthalf.filled", "Color")
                Toggle("Grayscale PDF", isOn: Binding(
                    get: { prefs.pdfGrayscale }, set: { prefs.pdfGrayscale = $0 }
                )).font(.system(size: 11))
                if prefs.pdfGrayscale {
                    settingsHelperText("Smaller files when color isn’t needed.")
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                            removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                        ))
                }

                SettingsSectionDivider()

                settingsSubHeader(icon: "gauge.with.dots.needle.67percent", String(localized: "Max file size", comment: "Sidebar PDF: max file size subsection header."))
                Toggle(String(localized: "Target a smaller file size", comment: "Sidebar PDF: max file size toggle."), isOn: Binding(
                    get: { prefs.pdfMaxFileSizeEnabled }, set: { prefs.pdfMaxFileSizeEnabled = $0 }
                )).toggleStyle(.switch).font(.system(size: 11))
                if prefs.pdfMaxFileSizeEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        settingsChipGrid(
                            presets: settingsPDFMaxFileSizePresets,
                            current: prefs.pdfMaxFileSizeKB,
                            fixedColumnCount: 4
                        ) { prefs.pdfMaxFileSizeKB = $0 }
                        HStack(spacing: 6) {
                            TextField("10", value: Binding(
                                get: { prefs.pdfMaxFileSizeMB }, set: { prefs.pdfMaxFileSizeMB = $0 }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 70)
                            Text(String(localized: "MB", comment: "Unit: megabytes.")).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        settingsHelperText(String(localized: "Steps down quality tiers until under the target. Exact size varies by content.", comment: "Sidebar PDF: max file size helper."))
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                        removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                    ))
                }

                SettingsSectionDivider()

                settingsSubHeader(icon: "doc.richtext", "Quality")
                QualityChipPicker(
                    options: pdfFlattenQualityChipOptions,
                    selected: Binding(get: { prefs.pdfQualityRaw }, set: { prefs.pdfQualityRaw = $0 })
                )
                if prefs.smartQuality {
                    settingsHelperText(String(localized: "Dinky picks a tier from each document. The choice below is the manual fallback if analysis fails.", comment: "Sidebar PDF: smart flatten helper."))
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                            removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                        ))
                }
                if prefs.pdfMaxFileSizeEnabled,
                   PDFQuality.flattenUIShowableTiers(maxFileSizeEnabled: true, pdfMaxFileSizeKB: prefs.pdfMaxFileSizeKB).count < PDFQuality.allCases.count {
                    settingsHelperText(String(localized: "Tighter max-size targets only list lower starting tiers; Dinky still steps down through the chain if needed.", comment: "Sidebar PDF: max size limits tier chips helper."))
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                            removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                        ))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var videosContent: some View {
        settingsSubHeader(icon: "film", "Format")
        QualityChipPicker(
            options: VideoCodecFamily.allCases.map { ($0.chipLabel, $0.rawValue, $0.description) },
            selected: Binding(get: { prefs.videoCodecFamilyRaw }, set: { prefs.videoCodecFamilyRaw = $0 })
        )

        SettingsSectionDivider()

        settingsSubHeader(icon: "wand.and.stars", "Quality")
        if prefs.smartQuality {
            settingsHelperText(String(localized: "Smart quality is on — encoder strength is picked per clip automatically.", comment: "Sidebar video: smart quality active placeholder."))
        } else {
            QualityChipPicker(
                options: VideoQuality.allCases.map { ($0.displayName, $0.rawValue, $0.description) },
                selected: Binding(get: { prefs.videoQualityRaw }, set: { prefs.videoQualityRaw = $0 })
            )
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
            ))
        }

        SettingsSectionDivider()

        settingsSubHeader(icon: "arrow.down.right.and.arrow.up.left", String(localized: "Output size", comment: "Sidebar Video: category for resolution + FPS."))
        settingsControlLabel(String(localized: "Max resolution", comment: "Sidebar Video: max resolution control label."))
        Toggle("Cap output resolution", isOn: Binding(
            get: { prefs.videoMaxResolutionEnabled }, set: { prefs.videoMaxResolutionEnabled = $0 }
        )).toggleStyle(.switch).font(.system(size: 11))
        if prefs.videoMaxResolutionEnabled {
            VStack(alignment: .leading, spacing: 8) {
                settingsChipGrid(
                    presets: settingsVideoResolutionPresets,
                    current: prefs.videoMaxResolutionLines,
                    fixedColumnCount: 4
                ) { prefs.videoMaxResolutionLines = $0 }
                settingsHelperText(String(localized: "Smaller output by limiting height. Source resolution is kept when below the cap. Smart quality still picks Balanced or High per clip; when this is on, output size is capped.", comment: "Sidebar Video: max resolution + smart quality note."))
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
            ))
        } else {
            settingsHelperText("Off keeps source resolution and just re-encodes for size. Turn this on to downscale large clips.")
        }

        settingsControlLabel(String(localized: "Frame rate", comment: "Sidebar Video: FPS control label."))
        Toggle(String(localized: "Cap frame rate", comment: "Sidebar: video FPS cap toggle."), isOn: Binding(
            get: { prefs.videoMaxFPSEnabled }, set: { prefs.videoMaxFPSEnabled = $0 }
        )).toggleStyle(.switch).font(.system(size: 11))
        if prefs.videoMaxFPSEnabled {
            VStack(alignment: .leading, spacing: 8) {
                settingsChipGrid(
                    presets: settingsVideoFPSCapPresets,
                    current: VideoFPSCapPreset.normalizeStored(prefs.videoMaxFPS),
                    fixedColumnCount: 4
                ) { prefs.videoMaxFPS = $0 }
                settingsHelperText(String(localized: "Lowers output FPS when the source runs faster than the cap (great for screen recordings). Unchanged when the source is already at or below this rate.", comment: "Sidebar Video: FPS cap helper."))
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
            ))
        } else {
            settingsHelperText(String(localized: "Off keeps the source frame rate.", comment: "Sidebar Video: FPS cap off."))
        }

        SettingsSectionDivider()

        settingsSubHeader(icon: "speaker.wave.2", "Audio")
        Toggle("Strip audio track", isOn: Binding(
            get: { prefs.videoRemoveAudio }, set: { prefs.videoRemoveAudio = $0 }
        )).font(.system(size: 11))
        if prefs.videoRemoveAudio {
            settingsHelperText("Best for screen recordings or silent clips.")
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                    removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                ))
        }
    }

    @ViewBuilder
    private var audioContent: some View {
        settingsSubHeader(icon: "waveform", "Format")
        AudioFormatChipPicker(audioFormatRaw: Binding(
            get: { prefs.audioFormatRaw }, set: { prefs.audioFormatRaw = $0 }
        ))
        if (AudioConversionFormat(rawValue: prefs.audioFormatRaw) ?? .aacM4A) == .mp3 {
            settingsHelperText(String(localized: "MP3 encoding uses the bundled LAME encoder (LGPL). WAV, AIFF, AAC/M4A, ALAC, and FLAC use macOS audio tools.", comment: "Sidebar Audio: LAME note."))
        }

        SettingsSectionDivider()

        settingsSubHeader(icon: "wand.and.stars", "Quality")
        if prefs.smartQuality {
            settingsHelperText(String(localized: "Smart quality is on — encoding strength is picked per track automatically.", comment: "Sidebar audio: smart quality active placeholder."))
        } else {
            QualityChipPicker(
                options: AudioConversionQualityTier.allCases.map { ($0.displayName, $0.rawValue, "") },
                selected: Binding(get: { prefs.audioQualityTierRaw }, set: { prefs.audioQualityTierRaw = $0 })
            )
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
            ))
        }
    }

    @ViewBuilder
    private var outputContent: some View {
        settingsSubHeader(icon: "square.and.arrow.up", "Output")
        Toggle("Reveal saved files in Finder", isOn: Binding(
            get: { prefs.openFolderWhenDone }, set: { prefs.openFolderWhenDone = $0 }
        )).font(.system(size: 11))
        if prefs.openFolderWhenDone {
            settingsHelperText("Opens the folder so you can grab outputs right away.")
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                    removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                ))
        }

        Toggle("Strip metadata", isOn: Binding(
            get: { prefs.stripMetadata }, set: { prefs.stripMetadata = $0 }
        )).font(.system(size: 11))
        if prefs.stripMetadata {
            settingsHelperText(String(localized: "Removes embedded EXIF, location, camera info, and PDF properties when supported. Finder Get Info comments are separate — turn on Preserve Finder comments below.", comment: "Sidebar: strip metadata helper."))
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                    removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                ))
        }

        Toggle(String(localized: "Preserve Finder comments", comment: "Settings UI."), isOn: Binding(
            get: { prefs.preserveFinderComments }, set: { prefs.preserveFinderComments = $0 }
        )).font(.system(size: 11))
        if prefs.preserveFinderComments {
            settingsHelperText(String(localized: "Copies Finder Get Info → Comments to the compressed file.", comment: "Sidebar: preserve Finder comments helper."))
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                    removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                ))
        }

        Toggle("Sanitize filenames", isOn: Binding(
            get: { prefs.sanitizeFilenames }, set: { prefs.sanitizeFilenames = $0 }
        )).font(.system(size: 11))
        if prefs.sanitizeFilenames {
            settingsHelperText("Lowercase, hyphens for spaces, max 75 characters.")
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                    removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                ))
        }

        settingsShortcutRow(title: "Destination & naming…", systemImage: "folder") {
            openPreferences(.output)
        }
        .padding(.top, 4)
    }

    // MARK: - Preset summary

    @ViewBuilder
    private func presetSummaryWithChrome(_ preset: CompressionPreset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    UserDefaults.standard.set(preset.id.uuidString, forKey: PreferencesTab.pendingPresetUUIDKey)
                    openPreferences(.presets)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 12, weight: .medium))
                        Text(String(localized: "Edit preset…", comment: "Sidebar: jump to preset in Settings."))
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Button {
                    prefs.activePresetID = ""
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 12, weight: .medium))
                        Text(String(localized: "Clear preset", comment: "Sidebar: deselect active preset."))
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Spacer(minLength: 0)
            }
            presetSummary(preset)
        }
    }

    @ViewBuilder
    private func presetSummary(_ preset: CompressionPreset) -> some View {
        let saveLabel: String = {
            switch preset.saveLocationRaw {
            case "downloads":    return "Downloads folder"
            case "custom":
                return prefs.customFolderDisplayPath.isEmpty
                    ? "Custom folder"
                    : URL(fileURLWithPath: prefs.customFolderDisplayPath).lastPathComponent
            case "presetCustom":
                return preset.presetCustomFolderPath.isEmpty
                    ? "Unique folder"
                    : URL(fileURLWithPath: preset.presetCustomFolderPath).lastPathComponent
            default:             return "Same folder"
            }
        }()
        let filenameLabel: String = {
            switch preset.filenameHandlingRaw {
            case "replaceOrigin": return "Replace original"
            case "customSuffix":  return "Suffix: \(preset.customSuffix)"
            default:              return "Append -dinky"
            }
        }()

        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.top, 4).padding(.bottom, 8)
            SidebarCard {
                VStack(alignment: .leading, spacing: 8) {
                summaryRow("photo",   preset.autoFormat ? "Auto" : preset.format.displayName)
                if preset.smartQuality {
                    summaryRow("wand.and.stars", String(localized: "Smart quality (all types)", comment: "Preset summary line."))
                }
                summaryRow("arrow.left.and.right",
                           preset.maxWidthEnabled ? "Max \(preset.maxWidth) px" : "No width limit")
                if preset.maxFileSizeEnabled {
                    let mb = Double(preset.maxFileSizeKB) / 1024.0
                    summaryRow("gauge.medium", "Max \(mb < 1 ? String(format: "%.1f", mb) : String(format: "%.4g", mb)) MB")
                } else {
                    summaryRow("gauge.medium", "No size limit")
                }
                let vidCodec = VideoCodecFamily(rawValue: preset.videoCodecFamilyRaw) ?? .h264
                let resCap = preset.videoMaxResolutionEnabled
                    ? "\(preset.videoMaxResolutionLines)p"
                    : "source"
                let fpsCap = preset.videoMaxFPSEnabled
                    ? " · max \(VideoFPSCapPreset.normalizeStored(preset.videoMaxFPS)) fps"
                    : ""
                summaryRow("video",
                           "\(vidCodec.chipLabel) · \(resCap)\(fpsCap)\(preset.videoRemoveAudio ? " · no audio" : "")")
                let audioFmt = AudioConversionFormat(rawValue: preset.audioFormatRaw) ?? .aacM4A
                let audioTier = AudioConversionQualityTier.resolve(preset.audioQualityTierRaw)
                let audioSummary: String = {
                    if preset.smartQuality {
                        return "\(audioFmt.displayName) · Smart quality"
                    }
                    return "\(audioFmt.displayName) · \(audioTier.displayName)"
                }()
                summaryRow("waveform", audioSummary)
                let pdfMode = PDFOutputMode(rawValue: preset.pdfOutputModeRaw) ?? .flattenPages
                if pdfMode == .flattenPages {
                    let pdfQ = PDFQuality(rawValue: preset.pdfQualityRaw) ?? .medium
                    summaryRow("doc.richtext",
                               "PDF flatten · \(pdfQ.displayName)\(preset.pdfGrayscale ? " · grayscale" : "")\(preset.pdfEnableOCR ? " · OCR" : "")")
                } else {
                    summaryRow("doc.richtext", "PDF preserve text & links\(preset.pdfEnableOCR ? " · OCR" : "")")
                }
                summaryRow("folder", saveLabel)
                summaryRow("doc.text", filenameLabel)
                if preset.stripMetadata     { summaryRow("minus.circle",    "Strip metadata") }
                if preset.sanitizeFilenames  { summaryRow("textformat.abc",  "Sanitize filenames") }
                if preset.openFolderWhenDone { summaryRow("folder.badge.plus","Open folder when done") }
                if preset.notifyWhenDone     { summaryRow("bell",            "Notify when done") }
                }
            }
        }
    }

    private func summaryRow(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(0.85))
                .frame(width: 18, alignment: .center)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.85))
        }
    }

    @ViewBuilder
    private func presetRow(id: String, name: String, subtitle: String,
                           isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.25))
                Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                Spacer()
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(isActive
                ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.08))
                : RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sectionGroup<Content: View>(
        icon: String,
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared chip pickers

/// Output format chips for audio files (sidebar + presets can reuse).
struct AudioFormatChipPicker: View {
    @Binding var audioFormatRaw: String

    var body: some View {
        let activeFormat = AudioConversionFormat(rawValue: audioFormatRaw) ?? .aacM4A
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(AudioConversionFormat.allCases) { format in
                let active = audioFormatRaw == format.rawValue
                chipCell(format.chipLabel, active: active)
                    .onTapGesture { audioFormatRaw = format.rawValue }
                    .help(format.displayName)
            }
        }
        Text(activeFormat.description)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .animation(.easeInOut(duration: 0.15), value: activeFormat.rawValue)
    }
}

struct FormatChipPicker: View {
    @Binding var autoFormat: Bool
    @Binding var selectedFormat: CompressionFormat
    /// When false, hides the technical line under the chips (e.g. simple sidebar).
    var showActiveDescription: Bool = true

    private let options: [(label: String, format: CompressionFormat?, description: String)] = [
        ("Auto",  nil,   "Converts to AVIF for photos and WebP for most other images — new files, not a same-format JPEG squeeze."),
        ("WebP",  .webp, "Broad support and solid compression."),
        ("AVIF",  .avif, "Smallest files; encoding takes longer."),
        ("PNG",   .png,  "Lossless; best for screenshots and graphics."),
        ("HEIC",  .heic, "Apple-friendly stills; good for Photos and iCloud sharing."),
    ]

    var body: some View {
        let activeDesc = options.first(where: { opt in
            opt.format == nil ? autoFormat : (!autoFormat && selectedFormat == opt.format)
        })?.description ?? ""

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
            ForEach(options, id: \.label) { opt in
                let active: Bool = opt.format == nil
                    ? autoFormat
                    : !autoFormat && selectedFormat == opt.format
                chipCell(opt.label, active: active)
                    .onTapGesture {
                        if let f = opt.format { autoFormat = false; selectedFormat = f }
                        else { autoFormat = true }
                    }
            }
        }
        if showActiveDescription && !activeDesc.isEmpty {
            Text(activeDesc)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.15), value: activeDesc)
        }
    }
}

struct ContentTypeChipPicker: View {
    @Binding var contentTypeHintRaw: String

    private let options: [(label: String, raw: String, description: String)] = [
        ("Photo",   "photo",   "Stronger compression for real-world photos."),
        ("Graphic", "graphic", "Keeps edges crisp for screenshots, UI, illustrations, and logos."),
        ("Mixed",   "mixed",   "Balanced when the image mixes both."),
    ]

    /// Coerce the legacy "ui" stored value to the new "graphic" raw, so old prefs still highlight the right chip.
    private var normalizedRaw: String {
        contentTypeHintRaw == "ui" ? "graphic" : contentTypeHintRaw
    }

    var body: some View {
        let activeRaw = normalizedRaw
        let activeDesc = options.first(where: { activeRaw == $0.raw })?.description ?? ""

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(options, id: \.raw) { opt in
                let active = activeRaw == opt.raw
                chipCell(opt.label, active: active)
                    .onTapGesture { contentTypeHintRaw = opt.raw }
            }
        }
        if !activeDesc.isEmpty {
            Text(activeDesc)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.15), value: activeDesc)
        }
    }
}

struct QualityChipPicker: View {
    let options: [(label: String, raw: String, description: String)]
    @Binding var selected: String

    var body: some View {
        let activeDesc = options.first(where: { selected == $0.raw })?.description ?? ""
        HStack(spacing: 4) {
            ForEach(options, id: \.raw) { opt in
                let active = selected == opt.raw
                chipCell(opt.label, active: active)
                    .onTapGesture { selected = opt.raw }
            }
        }
        if !activeDesc.isEmpty {
            Text(activeDesc)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.15), value: activeDesc)
        }
    }
}

private func chipCell(_ label: String, active: Bool) -> some View {
    Text(label)
        .font(.system(size: 11, weight: active ? .semibold : .regular))
        .foregroundStyle(active ? .white : .secondary)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(active ? AnyShapeStyle(dinkyGradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
        )
        .contentShape(Rectangle())
}
