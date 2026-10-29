import SwiftUI

// MARK: - Shared gradient (chip grids, FormatChipPicker)

let dinkyGradient = LinearGradient(
    colors: [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.45, green: 0.30, blue: 0.95)],
    startPoint: .leading,
    endPoint: .trailing
)

// MARK: - Numeric presets (sidebar + Settings presets tab)

let settingsWidthPresets: [(String, Int)] = [
    // No unit on each option: the track is narrow, and the field below says px.
    ("640", 640), ("1080", 1080), ("1280", 1280),
    ("1920", 1920), ("2560", 2560), ("3840", 3840)
]

let settingsScalePercentPresets: [(String, Int)] = [
    ("25%", 25), ("50%", 50), ("75%", 75)
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
/// Numeric quick picks as a `SlidingTrack`. `fixedColumnCount` is from the old grid layout and
/// no longer used; every preset list fits on one track.
func settingsChipGrid(
    presets: [(String, Int)],
    current: Int,
    fixedColumnCount: Int? = nil,
    onSelect: @escaping (Int) -> Void
) -> some View {
    SlidingTrack(items: presets.map { (label: $0.0, id: $0.1) }, selection: current, onSelect: onSelect)
}

// MARK: - Sliding track

/// One soft track of options; the pick is a Dinky-gradient pill that springs across to whatever
/// you choose. Replaces the boxed chip grids — one row instead of a wall of buttons.
struct SlidingTrack<ID: Hashable>: View {
    let items: [(label: String, id: ID)]
    /// `nil`, or a value no option has (a custom width typed in the field), shows no pill.
    let selection: ID?
    let onSelect: (ID) -> Void

    @Namespace private var pill
    @AppStorage("reduceMotion") private var appReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var animation: Animation {
        appReduceMotion || systemReduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.32, dampingFraction: 0.78)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.id) { item in
                let active = item.id == selection
                Button {
                    withAnimation(animation) { onSelect(item.id) }
                } label: {
                    Text(item.label)
                        .font(.system(size: 11, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(dinkyGradient)
                                    .shadow(color: Color(red: 0.35, green: 0.4, blue: 1).opacity(0.3), radius: 3, x: 0, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
        // Also slide when the value changes from elsewhere (a preset, the text field).
        .animation(animation, value: selection)
    }
}

// MARK: - Percentage resize

/// Percentage chips plus a field (sidebar + Settings presets tab). Scales width and height together.
struct ScalePercentControls: View {
    @Binding var percent: Int
    var fieldWidth: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingsChipGrid(presets: settingsScalePercentPresets, current: percent, fixedColumnCount: 3) { percent = $0 }
            HStack(spacing: 6) {
                TextField("50", value: Binding(
                    get: { percent }, set: { percent = CompressionGoals.clampedScalePercent($0) }
                ), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: fieldWidth)
                Text(verbatim: "%").foregroundStyle(.secondary)
            }
        }
    }
}
