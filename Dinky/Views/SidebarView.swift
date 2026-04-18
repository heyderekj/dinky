import SwiftUI

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

private enum SidebarScope: String, CaseIterable, Identifiable {
    case images, videos, pdfs, output
    var id: String { rawValue }
    var title: String {
        switch self {
        case .images: return "Images"
        case .pdfs: return "PDFs"
        case .videos: return "Videos"
        case .output: return "Output"
        }
    }
    var icon: String {
        switch self {
        case .images: return "photo"
        case .pdfs: return "doc.text"
        case .videos: return "video"
        case .output: return "square.and.arrow.up"
        }
    }

    /// Short label for the scope tab strip (narrow sidebar).
    var tabShortTitle: String {
        switch self {
        case .images: return "Images"
        case .pdfs: return "PDFs"
        case .videos: return "Video"
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
    @AppStorage("sidebar.selectedScope") private var scopeRaw: String = SidebarScope.images.rawValue

    private let widthPresets: [(String, Int)] = [
        ("640 px", 640), ("1080 px", 1080), ("1280 px", 1280),
        ("1920 px", 1920), ("2560 px", 2560), ("3840 px", 3840)
    ]
    private let sizePresets: [(String, Int)] = [
        ("0.5 MB", 512), ("1 MB", 1024), ("2 MB", 2048),
        ("5 MB", 5120), ("10 MB", 10240)
    ]

    private var presetActive: Bool { !prefs.activePresetID.isEmpty }

    private var availableScopes: [SidebarScope] {
        var list: [SidebarScope] = []
        if prefs.showImagesSection { list.append(.images) }
        if prefs.showVideosSection { list.append(.videos) }
        if prefs.showPDFsSection { list.append(.pdfs) }
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
                        presetSummary(active).transition(.opacity)
                    }
                } else if prefs.sidebarSimpleMode {
                    simpleModeExtras
                } else {
                    fullSidebarChrome
                }
            }
            .padding(10)
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
        .clipped()
        .frame(width: 228)
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
        .animation(.easeInOut(duration: 0.2), value: prefs.pdfGrayscale)
        .animation(.easeInOut(duration: 0.2), value: prefs.pdfOutputModeRaw)
        .animation(.easeInOut(duration: 0.2), value: prefs.videoRemoveAudio)
        .animation(.easeInOut(duration: 0.2), value: prefs.videoCodecFamilyRaw)
        .animation(.easeInOut(duration: 0.2), value: prefs.sidebarSimpleMode)
        .animation(.easeInOut(duration: 0.2), value: scopeRaw)
        .accessibilityLabel("Compression settings")
        .accessibilityHint("Choose format, quality, and output options for images, videos, and PDFs.")
        .onChange(of: prefs.showImagesSection) { _, _ in syncScopeIfNeeded() }
        .onChange(of: prefs.showPDFsSection) { _, _ in syncScopeIfNeeded() }
        .onChange(of: prefs.showVideosSection) { _, _ in syncScopeIfNeeded() }
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
                        subtitle: PresetMediaScope(rawValue: preset.presetMediaScopeRaw)?.displayName
                            ?? PresetMediaScope.all.displayName,
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
            VStack(alignment: .leading, spacing: 8) {
                sidebarSectionHeading(icon: "slider.horizontal.2.square.on.square", title: "Quick choices")

                Toggle("Choose formats automatically", isOn: Binding(
                    get: { prefs.autoFormat }, set: { prefs.autoFormat = $0 }
                ))
                .font(.system(size: 11))

                if !prefs.autoFormat {
                    FormatChipPicker(
                        autoFormat: Binding(get: { prefs.autoFormat }, set: { prefs.autoFormat = $0 }),
                        selectedFormat: $selectedFormat,
                        showActiveDescription: false
                    )
                }

                Toggle("Tune compression from content", isOn: Binding(
                    get: { prefs.smartQuality }, set: { prefs.smartQuality = $0 }
                ))
                .font(.system(size: 11))

                Text(simpleQuickSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Open the folder when finished", isOn: Binding(
                    get: { prefs.openFolderWhenDone }, set: { prefs.openFolderWhenDone = $0 }
                ))
                .font(.system(size: 11))
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.05)))

            VStack(alignment: .leading, spacing: 6) {
                sidebarSectionHeading(icon: "folder", title: "Where files go")
                Text(outputDestinationLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(outputFilenameLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("Change folder or naming…") {
                    openPreferences(.output)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.05)))

            VStack(alignment: .leading, spacing: 4) {
                sidebarSectionHeading(icon: "arrow.up.right.square", title: "Shortcuts")
                settingsShortcutRow(title: "Presets", systemImage: "slider.horizontal.3") {
                    openPreferences(.presets)
                }
                settingsShortcutRow(title: "Watch folders", systemImage: "eye") {
                    openPreferences(.watch)
                }
                settingsShortcutRow(title: "All settings", systemImage: "gearshape") {
                    openPreferences(.general)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.05)))

            Button {
                prefs.applySidebarSimpleMode(false)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 12, weight: .medium))
                    Text("All options…")
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    /// One short line under the simple-mode toggles (full detail lives in All options).
    private var simpleQuickSummary: String {
        if prefs.smartQuality {
            if prefs.autoFormat {
                return "Automatic format and compression for each file."
            }
            return "Compression per file; image format follows the chip above."
        }
        if prefs.autoFormat {
            return "WebP or AVIF per image. Other types: use All options."
        }
        return "Fine-tune image, video, and PDF defaults in All options."
    }

    // MARK: - Full sidebar (scoped)

    private var fullSidebarChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                sidebarSectionHeading(icon: "slider.horizontal.3", title: "Adjust")
                scopeTabBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                switch effectiveScope {
                case .images:  imagesPanel
                case .pdfs:    pdfsPanel
                case .videos:  videosPanel
                case .output:  outputPanel
                }
            }

            sidebarSectionsFooter
        }
    }

    private var scopeTabBar: some View {
        HStack(spacing: 4) {
            ForEach(availableScopes) { scope in
                let selected = effectiveScope == scope
                Button {
                    scopeRaw = scope.rawValue
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: scope.icon)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 22, height: 15)
                        Text(scope.tabShortTitle)
                            .font(.system(size: 9, weight: selected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .help(scope.title)
            }
        }
    }

    private var sidebarSectionsFooter: some View {
        Button {
            openPreferences(.general)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
                Text("Which sections appear here…")
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
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
        let cur = SidebarScope(rawValue: scopeRaw) ?? .output
        if !availableScopes.contains(cur), let first = availableScopes.first {
            scopeRaw = first.rawValue
        }
    }

    private var outputDestinationLine: String {
        switch prefs.saveLocation {
        case .sameFolder: return "Saves next to originals"
        case .downloads:  return "Saves to Downloads"
        case .custom:
            return prefs.customFolderDisplayPath.isEmpty
                ? "Custom folder (not set in Settings)"
                : URL(fileURLWithPath: prefs.customFolderDisplayPath).lastPathComponent
        }
    }

    private var outputFilenameLine: String {
        switch prefs.filenameHandling {
        case .appendSuffix:  return "Adds “-dinky” before the extension"
        case .replaceOrigin: return "Replaces the original"
        case .customSuffix:  return "Custom suffix: \(prefs.customSuffix)"
        }
    }

    private var effectiveScope: SidebarScope {
        let cur = SidebarScope(rawValue: scopeRaw) ?? .output
        if availableScopes.contains(cur) { return cur }
        return availableScopes.first ?? .output
    }

    // MARK: - Scoped panels

    private var imagesPanel: some View { imagesContent }
    private var pdfsPanel: some View { pdfsContent }
    private var videosPanel: some View { videosContent }
    private var outputPanel: some View { outputContent }

    // MARK: - Type section contents

    @ViewBuilder
    private var imagesContent: some View {
        subHeader(icon: "photo.on.rectangle.angled", "Format")
        FormatChipPicker(
            autoFormat: Binding(get: { prefs.autoFormat }, set: { prefs.autoFormat = $0 }),
            selectedFormat: $selectedFormat
        )

        sectionDivider

        subHeader(icon: "wand.and.stars", "Quality")
        Toggle("Smart quality", isOn: Binding(
            get: { prefs.smartQuality }, set: { prefs.smartQuality = $0 }
        )).font(.system(size: 11))
        if prefs.smartQuality {
            helper("For images: encoding strength from content. Videos and PDFs: tier from each file (see those tabs).")
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                    removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                ))
        } else {
            ContentTypeChipPicker(contentTypeHintRaw: Binding(
                get: { prefs.contentTypeHintRaw }, set: { prefs.contentTypeHintRaw = $0 }
            ))
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
            ))
        }

        sectionDivider

        subHeader(icon: "arrow.left.and.right", "Max width")
        Toggle("Resize to a maximum width", isOn: Binding(
            get: { prefs.maxWidthEnabled }, set: { prefs.maxWidthEnabled = $0 }
        )).toggleStyle(.switch).font(.system(size: 11))
        if prefs.maxWidthEnabled {
            VStack(alignment: .leading, spacing: 8) {
                chipGrid(presets: widthPresets, current: prefs.maxWidth) { prefs.maxWidth = $0 }
                HStack(spacing: 6) {
                    TextField("1920", value: Binding(
                        get: { prefs.maxWidth }, set: { prefs.maxWidth = max(1, $0) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 70)
                    Text("px").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                helper("Try 1920 for web, 1280 for social, 640 for email.")
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
            ))
        }

        sectionDivider

        subHeader(icon: "gauge.with.dots.needle.67percent", "Max file size")
        Toggle("Target a smaller file size", isOn: Binding(
            get: { prefs.maxFileSizeEnabled }, set: { prefs.maxFileSizeEnabled = $0 }
        )).toggleStyle(.switch).font(.system(size: 11))
        if prefs.maxFileSizeEnabled {
            VStack(alignment: .leading, spacing: 8) {
                chipGrid(presets: sizePresets, current: prefs.maxFileSizeKB) { prefs.maxFileSizeKB = $0 }
                HStack(spacing: 6) {
                    TextField("2", value: Binding(
                        get: { prefs.maxFileSizeMB }, set: { prefs.maxFileSizeMB = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 70)
                    Text("MB").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                helper("Encoder aims near this cap; exact size varies by image.")
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
            ))
        }
    }

    @ViewBuilder
    private var pdfsContent: some View {
        subHeader(icon: "doc.text.viewfinder", "Output")
        Picker("PDF output", selection: Binding(
            get: { prefs.pdfOutputModeRaw },
            set: { prefs.pdfOutputModeRaw = $0 }
        )) {
            Text("Preserve text & links").tag(PDFOutputMode.preserveStructure.rawValue)
            Text("Flatten (smallest)").tag(PDFOutputMode.flattenPages.rawValue)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityLabel("PDF output mode")

        if prefs.pdfOutputMode == .preserveStructure {
            helper("Rewrites the PDF and strips metadata. Text, links, and forms stay usable. File size may change a little.")
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                    removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                ))
        }

        if prefs.pdfOutputMode == .flattenPages {
            sectionDivider

            subHeader(icon: "doc.richtext", "Quality")
            QualityChipPicker(
                options: PDFQuality.allCases.map { ($0.displayName, $0.rawValue, $0.description) },
                selected: Binding(get: { prefs.pdfQualityRaw }, set: { prefs.pdfQualityRaw = $0 })
            )
            .disabled(prefs.smartQuality)
            if prefs.smartQuality {
                helper("Dinky picks a tier from each document. Turn off Smart quality under Images for a fixed Low / Medium / High. Manual tier is still used as a fallback if analysis fails.")
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                        removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                    ))
            }

            sectionDivider

            subHeader(icon: "circle.lefthalf.filled", "Color")
            Toggle("Grayscale PDF", isOn: Binding(
                get: { prefs.pdfGrayscale }, set: { prefs.pdfGrayscale = $0 }
            )).font(.system(size: 11))
            if prefs.pdfGrayscale {
                helper("Smaller files when color isn’t needed.")
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                        removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                    ))
            }
        } else {
            helper("Quality tiers and grayscale apply when you choose Flatten (smallest).")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var videosContent: some View {
        subHeader(icon: "film", "Format")
        QualityChipPicker(
            options: VideoCodecFamily.allCases.map { ($0.chipLabel, $0.rawValue, $0.description) },
            selected: Binding(get: { prefs.videoCodecFamilyRaw }, set: { prefs.videoCodecFamilyRaw = $0 })
        )

        sectionDivider

        subHeader(icon: "video.badge.waveform", "Quality")
        QualityChipPicker(
            options: VideoQuality.allCases.map { ($0.displayName, $0.rawValue, $0.description) },
            selected: Binding(get: { prefs.videoQualityRaw }, set: { prefs.videoQualityRaw = $0 })
        )
        .disabled(prefs.smartQuality)
        if prefs.smartQuality {
            helper("Dinky picks export strength from each video’s resolution and bitrate. Turn off Smart quality under Images to choose manually. Codec below still applies.")
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                    removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                ))
        }

        sectionDivider

        subHeader(icon: "speaker.wave.2", "Audio")
        Toggle("Strip audio track", isOn: Binding(
            get: { prefs.videoRemoveAudio }, set: { prefs.videoRemoveAudio = $0 }
        )).font(.system(size: 11))
        if prefs.videoRemoveAudio {
            helper("Best for screen recordings or silent clips.")
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                    removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                ))
        }
    }

    @ViewBuilder
    private var outputContent: some View {
        subHeader(icon: "square.and.arrow.up", "Output")
        Toggle("Reveal saved files in Finder", isOn: Binding(
            get: { prefs.openFolderWhenDone }, set: { prefs.openFolderWhenDone = $0 }
        )).font(.system(size: 11))
        if prefs.openFolderWhenDone {
            helper("Opens the folder so you can grab outputs right away.")
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                    removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                ))
        }

        Toggle("Strip metadata", isOn: Binding(
            get: { prefs.stripMetadata }, set: { prefs.stripMetadata = $0 }
        )).font(.system(size: 11))
        if prefs.stripMetadata {
            helper("Removes EXIF, location, and camera data when supported.")
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                    removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                ))
        }

        Toggle("Sanitize filenames", isOn: Binding(
            get: { prefs.sanitizeFilenames }, set: { prefs.sanitizeFilenames = $0 }
        )).font(.system(size: 11))
        if prefs.sanitizeFilenames {
            helper("Lowercase, hyphens for spaces, max 75 characters.")
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

    // MARK: - Sub-section helpers

    private var sectionDivider: some View {
        Divider().padding(.vertical, 4)
    }

    /// Matches ``sectionGroup`` title row: icon + 13pt semibold (see Presets).
    private func sidebarSectionHeading(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
    }

    private func subHeader(icon: String, _ title: String) -> some View {
        sidebarSectionHeading(icon: icon, title: title)
    }

    // MARK: - Preset summary

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
            VStack(alignment: .leading, spacing: 8) {
                summaryRow("photo",   preset.autoFormat ? "Auto" : preset.format.displayName)
                if preset.smartQuality { summaryRow("wand.and.stars", "Smart quality") }
                summaryRow("arrow.left.and.right",
                           preset.maxWidthEnabled ? "Max \(preset.maxWidth) px" : "No width limit")
                if preset.maxFileSizeEnabled {
                    let mb = Double(preset.maxFileSizeKB) / 1024.0
                    summaryRow("gauge.medium", "Max \(mb < 1 ? String(format: "%.1f", mb) : String(format: "%.4g", mb)) MB")
                } else {
                    summaryRow("gauge.medium", "No size limit")
                }
                let vidCodec = VideoCodecFamily(rawValue: preset.videoCodecFamilyRaw) ?? .h264
                let vidQ = VideoQuality(rawValue: preset.videoQualityRaw) ?? .medium
                summaryRow("video",
                           "\(vidCodec.chipLabel) · \(vidQ.displayName)\(preset.videoRemoveAudio ? " · no audio" : "")")
                let pdfMode = PDFOutputMode(rawValue: preset.pdfOutputModeRaw) ?? .preserveStructure
                if pdfMode == .flattenPages {
                    let pdfQ = PDFQuality(rawValue: preset.pdfQualityRaw) ?? .medium
                    summaryRow("doc.richtext",
                               "PDF flatten · \(pdfQ.displayName)\(preset.pdfGrayscale ? " · grayscale" : "")")
                } else {
                    summaryRow("doc.richtext", "PDF preserve text & links")
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

    // MARK: - Chip grid

    private func chipGrid(presets: [(String, Int)], current: Int, onSelect: @escaping (Int) -> Void) -> some View {
        let columns = [GridItem(.adaptive(minimum: 50), spacing: 4)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(presets, id: \.1) { label, value in
                let active = current == value
                Text(label)
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? .white : .secondary)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(active ? AnyShapeStyle(dinkyGradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(value) }
            }
        }
    }

    // MARK: - Helpers

    private func helper(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
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

/// MARK: - Shared chip pickers

let dinkyGradient = LinearGradient(
    colors: [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.45, green: 0.30, blue: 0.95)],
    startPoint: .leading, endPoint: .trailing
)

struct FormatChipPicker: View {
    @Binding var autoFormat: Bool
    @Binding var selectedFormat: CompressionFormat
    /// When false, hides the technical line under the chips (e.g. simple sidebar).
    var showActiveDescription: Bool = true

    private let options: [(label: String, format: CompressionFormat?, description: String)] = [
        ("Auto",  nil,   "Uses AVIF for photos and WebP for most other images."),
        ("WebP",  .webp, "Broad support and solid compression."),
        ("AVIF",  .avif, "Smallest files; encoding takes longer."),
        ("PNG",   .png,  "Lossless; best for screenshots and graphics."),
    ]

    var body: some View {
        let activeDesc = options.first(where: { opt in
            opt.format == nil ? autoFormat : (!autoFormat && selectedFormat == opt.format)
        })?.description ?? ""

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
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
        ("Photo", "photo", "Stronger compression for real-world photos."),
        ("UI",    "ui",    "Keeps edges sharp for screenshots and UI."),
        ("Mixed", "mixed", "Balanced when the image mixes both."),
    ]

    var body: some View {
        let activeDesc = options.first(where: { contentTypeHintRaw == $0.raw })?.description ?? ""

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(options, id: \.raw) { opt in
                let active = contentTypeHintRaw == opt.raw
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
        let count = min(options.count, 3)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: count), spacing: 4) {
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
