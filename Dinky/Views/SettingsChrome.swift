import SwiftUI

// MARK: - Shared gradient (chip grids, FormatChipPicker)

let dinkyGradient = LinearGradient(
    colors: [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.45, green: 0.30, blue: 0.95)],
    startPoint: .leading,
    endPoint: .trailing
)

// MARK: - Numeric presets (sidebar + Settings presets tab)

let settingsWidthPresets: [(String, Int)] = [
    ("640 px", 640), ("1080 px", 1080), ("1280 px", 1280),
    ("1920 px", 1920), ("2560 px", 2560), ("3840 px", 3840)
]

let settingsSizePresets: [(String, Int)] = [
    ("0.5 MB", 512), ("1 MB", 1024), ("2 MB", 2048),
    ("5 MB", 5120), ("10 MB", 10240)
]

// MARK: - PDF max file size (flatten target)

private let pdfMaxFileSizeKBMin = 5 * 1024
private let pdfMaxFileSizeKBMax = 25 * 1024

/// Quick picks: 5–15 MB in 5 MB steps, plus 25 MB max (values are KiB).
let settingsPDFMaxFileSizePresets: [(String, Int)] = [
    ("5 MB", 5 * 1024),
    ("10 MB", 10 * 1024),
    ("15 MB", 15 * 1024),
    ("25 MB", 25 * 1024),
]

/// Clamps PDF max-size targets to 5–25 MB (matches chip presets and manual entry).
func clampPDFMaxFileSizeKB(_ kb: Int) -> Int {
    min(pdfMaxFileSizeKBMax, max(pdfMaxFileSizeKBMin, kb))
}

let settingsVideoResolutionPresets: [(String, Int)] = [
    ("480p", 480), ("720p", 720), ("1080p", 1080), ("2160p", 2160)
]

let settingsVideoFPSCapPresets: [(String, Int)] = [
    ("60", 60), ("30", 30), ("24", 24), ("15", 15),
]

// MARK: - Section chrome (sidebar + Settings)

/// Matches grouped settings subsection titles: icon + 13pt semibold.
func settingsSectionHeading(icon: String, title: String) -> some View {
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

func settingsSubHeader(icon: String, _ title: String) -> some View {
    settingsSectionHeading(icon: icon, title: title)
}

/// Second-line label under a category heading (e.g. “Max resolution” inside “Output size”).
func settingsControlLabel(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
}

struct SettingsSectionDivider: View {
    var body: some View {
        Divider().padding(.vertical, 4)
    }
}

func settingsHelperText(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
}

// MARK: - Chip grid

/// - Parameter fixedColumnCount: When set (e.g. `3` for six width presets), uses a balanced fixed grid; otherwise `.adaptive` packing.
func settingsChipGrid(
    presets: [(String, Int)],
    current: Int,
    fixedColumnCount: Int? = nil,
    onSelect: @escaping (Int) -> Void
) -> some View {
    let columns: [GridItem]
    if let count = fixedColumnCount, count > 0 {
        columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: count)
    } else {
        columns = [GridItem(.adaptive(minimum: 50), spacing: 4)]
    }
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
