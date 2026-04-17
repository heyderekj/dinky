import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @Binding var selectedFormat: CompressionFormat

    private let widthPresets: [(String, Int)] = [
        ("640 px", 640), ("1080 px", 1080), ("1280 px", 1280),
        ("1920 px", 1920), ("2560 px", 2560), ("3840 px", 3840)
    ]
    private let sizePresets: [(String, Int)] = [
        ("0.5 MB", 512), ("1 MB", 1024), ("2 MB", 2048),
        ("5 MB", 5120), ("10 MB", 10240)
    ]

    private var presetActive: Bool { !prefs.activePresetID.isEmpty }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 10) {

            // ── Presets ──────────────────────────────────────────
            if !prefs.savedPresets.isEmpty {
                sectionGroup(icon: "slider.horizontal.below.square.and.square.filled", title: "Presets") {
                    VStack(spacing: 2) {
                        presetRow(id: "", name: "None", subtitle: "No preset", isActive: prefs.activePresetID.isEmpty) {
                            prefs.activePresetID = ""
                        }
                        ForEach(prefs.savedPresets) { preset in
                            presetRow(id: preset.id.uuidString, name: preset.name, subtitle: preset.format.displayName,
                                      isActive: prefs.activePresetID == preset.id.uuidString) {
                                var fmt = selectedFormat
                                preset.apply(to: prefs, selectedFormat: &fmt)
                                selectedFormat = fmt
                                prefs.activePresetID = preset.id.uuidString
                            }
                        }
                    }

                    // Summary of active preset
                    if let active = prefs.savedPresets.first(where: { $0.id.uuidString == prefs.activePresetID }) {
                        presetSummary(active)
                            .transition(.opacity)
                    }
                }
            }

            // Manual sections — hidden when a preset is controlling everything
            if !presetActive {

                // ── Format ──────────────────────────────────────────
                sectionGroup(icon: "photo", title: "Format") {
                    Picker("", selection: $selectedFormat) {
                        ForEach(CompressionFormat.allCases) { fmt in
                            Text(fmt.displayName).tag(fmt)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    helper("WebP works everywhere. AVIF is smaller but slower. PNG is lossless.")
                }

                // ── Max Width ────────────────────────────────────────
                sectionGroup(icon: "arrow.left.and.right", title: "Max Width") {
                    Toggle("Limit width", isOn: Binding(
                        get: { prefs.maxWidthEnabled },
                        set: { prefs.maxWidthEnabled = $0 }
                    ))
                    .toggleStyle(.switch).font(.caption)

                    if prefs.maxWidthEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            chipGrid(presets: widthPresets, current: prefs.maxWidth) { prefs.maxWidth = $0 }
                            HStack(spacing: 6) {
                                TextField("1920", value: Binding(
                                    get: { prefs.maxWidth },
                                    set: { prefs.maxWidth = max(1, $0) }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder).frame(width: 70)
                                Text("px").font(.caption).foregroundStyle(.secondary)
                            }
                            helper("Common for web (1920), social (1280), and email (640).")
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                            removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                        ))
                    }
                }

                // ── Max File Size ─────────────────────────────────────
                sectionGroup(icon: "gauge.medium", title: "Max File Size") {
                    Toggle("Limit file size", isOn: Binding(
                        get: { prefs.maxFileSizeEnabled },
                        set: { prefs.maxFileSizeEnabled = $0 }
                    ))
                    .toggleStyle(.switch).font(.caption)

                    if prefs.maxFileSizeEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            chipGrid(presets: sizePresets, current: prefs.maxFileSizeKB) { prefs.maxFileSizeKB = $0 }
                            HStack(spacing: 6) {
                                TextField("2", value: Binding(
                                    get: { prefs.maxFileSizeMB },
                                    set: { prefs.maxFileSizeMB = $0 }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder).frame(width: 70)
                                Text("MB").font(.caption).foregroundStyle(.secondary)
                            }
                            helper("Email typically caps at 1 MB. CMS and social platforms vary from 2–10 MB.")
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                            removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                        ))
                    }
                }

                // ── Performance ───────────────────────────────────────
                sectionGroup(icon: "cpu", title: "Performance") {
                    let levels: [(String, Int)] = [
                        ("Fast", 1),
                        ("Fastest", ProcessInfo.processInfo.activeProcessorCount)
                    ]
                    let nearest = levels.min(by: {
                        abs($0.1 - prefs.concurrentTasks) < abs($1.1 - prefs.concurrentTasks)
                    })?.1 ?? prefs.concurrentTasks
                    chipGrid(presets: levels, current: nearest) { prefs.concurrentTasks = $0 }
                    helper("Fast = one at a time. Fastest = all cores, no waiting.")
                }

                // ── Advanced ──────────────────────────────────────────
                sectionGroup(icon: "slider.horizontal.3", title: "Advanced") {
                    Toggle("Smart quality", isOn: Binding(
                        get: { prefs.smartQuality }, set: { prefs.smartQuality = $0 }
                    )).font(.caption)
                    if prefs.smartQuality {
                        helper("Auto-picks quality per image. Screenshots stay crisp. Photos squeeze harder.")
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                                removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                            ))
                    }
                    Toggle("Auto-format", isOn: Binding(
                        get: { prefs.autoFormat }, set: { prefs.autoFormat = $0 }
                    )).font(.caption)
                    if prefs.autoFormat {
                        helper("Picks AVIF for photos, WebP for everything else. Overrides the format picker above.")
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                                removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                            ))
                    }
                    Toggle("Open folder when done", isOn: Binding(
                        get: { prefs.openFolderWhenDone }, set: { prefs.openFolderWhenDone = $0 }
                    )).font(.caption)
                    Toggle("Sanitize filenames", isOn: Binding(
                        get: { prefs.sanitizeFilenames }, set: { prefs.sanitizeFilenames = $0 }
                    )).font(.caption)
                    if prefs.sanitizeFilenames {
                        helper("Lowercases, replaces spaces with hyphens, and trims to 75 characters.")
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1))),
                                removal:   .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.08)))
                            ))
                    }
                    Toggle("Strip metadata", isOn: Binding(
                        get: { prefs.stripMetadata }, set: { prefs.stripMetadata = $0 }
                    )).font(.caption)
                }
            }
        }
        .padding(12)
        }
        .clipped()
        .frame(width: 220)
        .frame(maxHeight: presetActive ? nil : .infinity, alignment: .top)
        .fixedSize(horizontal: false, vertical: presetActive)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: prefs.maxWidthEnabled)
        .animation(.easeInOut(duration: 0.2), value: prefs.maxFileSizeEnabled)
        .animation(.easeInOut(duration: 0.2), value: prefs.sanitizeFilenames)
        .animation(.easeInOut(duration: 0.2), value: prefs.manualMode)
        .animation(.easeInOut(duration: 0.2), value: prefs.smartQuality)
        .animation(.easeInOut(duration: 0.2), value: prefs.autoFormat)
        .animation(.easeInOut(duration: 0.2), value: presetActive)
    }

    // MARK: - Preset summary

    @ViewBuilder
    private func presetSummary(_ preset: CompressionPreset) -> some View {
        let saveLabel: String = {
            switch preset.saveLocationRaw {
            case "downloads": return "Downloads folder"
            case "custom":    return "Custom folder"
            default:          return "Same folder"
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
            Divider().padding(.top, 6).padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 12) {
                summaryRow("photo", preset.format.displayName)
                if preset.smartQuality  { summaryRow("wand.and.stars", "Smart quality") }
                if preset.autoFormat    { summaryRow("sparkles", "Auto-format") }
                if preset.maxWidthEnabled {
                    summaryRow("arrow.left.and.right", "Max \(preset.maxWidth) px")
                } else {
                    summaryRow("arrow.left.and.right", "No width limit")
                }
                if preset.maxFileSizeEnabled {
                    let mb = Double(preset.maxFileSizeKB) / 1024.0
                    let sizeLabel = mb < 1 ? String(format: "%.1f MB", mb) : String(format: "%.4g MB", mb)
                    summaryRow("gauge.medium", "Max \(sizeLabel)")
                } else {
                    summaryRow("gauge.medium", "No size limit")
                }
                summaryRow("folder", saveLabel)
                summaryRow("doc.text", filenameLabel)
                if preset.stripMetadata    { summaryRow("minus.circle", "Strip metadata") }
                if preset.sanitizeFilenames { summaryRow("textformat.abc", "Sanitize filenames") }
                if preset.openFolderWhenDone { summaryRow("folder.badge.plus", "Open folder when done") }
                if preset.notifyWhenDone   { summaryRow("bell", "Notify when done") }
            }
        }
    }

    private func summaryRow(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor.opacity(0.85))
                .frame(width: 20, alignment: .center)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.8))
        }
    }

    // MARK: - Chip grid

    private func chipGrid(presets: [(String, Int)], current: Int, onSelect: @escaping (Int) -> Void) -> some View {
        let columns = [GridItem(.adaptive(minimum: 52), spacing: 4)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(presets, id: \.1) { label, value in
                let active = current == value
                Text(label)
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? .white : .secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(active
                                  ? AnyShapeStyle(LinearGradient(
                                        colors: [Color(red: 0.25, green: 0.55, blue: 1.0),
                                                 Color(red: 0.45, green: 0.30, blue: 0.95)],
                                        startPoint: .leading, endPoint: .trailing))
                                  : AnyShapeStyle(Color.primary.opacity(0.08)))
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
    private func presetRow(id: String, name: String, subtitle: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.25))
                Text(name).font(.system(size: 11)).foregroundStyle(.primary)
                Spacer()
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(isActive
                ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.08))
                : RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sectionGroup<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon).imageScale(.small).foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
            }
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.05)))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
