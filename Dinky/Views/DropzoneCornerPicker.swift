import SwiftUI

/// Settings: pick the floating dropzone's corner on a little screen. The chosen corner shows a
/// mini dropzone (glass pill, file cards, brand ring); the others are click targets.
struct DropzoneCornerPicker: View {
    @Binding var corner: ScreenCorner
    @AppStorage("reduceMotion") private var appReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered: ScreenCorner?

    private var reduceMotion: Bool { appReduceMotion || systemReduceMotion }
    private static let screenSize = CGSize(width: 260, height: 156)

    var body: some View {
        ZStack {
            screen
            ForEach(ScreenCorner.allCases) { c in
                cornerTarget(c)
            }
        }
        .frame(width: Self.screenSize.width, height: Self.screenSize.height)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.72), value: corner)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Corner", comment: "Settings UI: where the floating dropzone appears."))
    }

    /// A tiny desktop: wallpaper, menu bar, Dock.
    private var screen: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(red: 0.13, green: 0.16, blue: 0.28), Color(red: 0.22, green: 0.14, blue: 0.30)]
                        : [Color(red: 0.78, green: 0.85, blue: 0.98), Color(red: 0.88, green: 0.80, blue: 0.96)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle()
                .fill(.white.opacity(colorScheme == .dark ? 0.08 : 0.45))
                .frame(height: 9)
            VStack {
                Spacer()
                Capsule()
                    .fill(.white.opacity(colorScheme == .dark ? 0.12 : 0.5))
                    .frame(width: 90, height: 11)
                    .padding(.bottom, 5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private func alignment(_ c: ScreenCorner) -> Alignment {
        switch c {
        case .bottomRight: return .bottomTrailing
        case .bottomLeft:  return .bottomLeading
        case .topRight:    return .topTrailing
        case .topLeft:     return .topLeading
        }
    }

    private func cornerTarget(_ c: ScreenCorner) -> some View {
        let selected = c == corner
        return Button {
            corner = c
        } label: {
            ZStack {
                if selected {
                    MiniDropzone(fromLeft: c.isLeft, reduceMotion: reduceMotion)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.4, anchor: unitPoint(c)).combined(with: .opacity))
                } else {
                    Capsule()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                        .foregroundStyle(Color.primary.opacity(hovered == c ? 0.45 : 0.18))
                        .frame(width: 62, height: 20)
                }
            }
            .frame(width: 84, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? c : (hovered == c ? nil : hovered) }
        .padding(.top, c.isTop ? 12 : 0)
        .padding(.bottom, c.isTop ? 0 : 18)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(c))
        .accessibilityLabel(c.displayName)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func unitPoint(_ c: ScreenCorner) -> UnitPoint {
        switch c {
        case .bottomRight: return .bottomTrailing
        case .bottomLeft:  return .bottomLeading
        case .topRight:    return .topTrailing
        case .topLeft:     return .topLeading
        }
    }
}

/// The dropzone pill in miniature: glass, two file cards bobbing on it, a slowly turning ring.
private struct MiniDropzone: View {
    let fromLeft: Bool
    let reduceMotion: Bool

    private static let ringColors: [Color] = [
        DropZoneStyle.gradientColors[0], DropZoneStyle.gradientColors[1],
        Color(red: 0.93, green: 0.38, blue: 0.78), DropZoneStyle.gradientColors[1], DropZoneStyle.gradientColors[0],
    ]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Capsule()
                    .fill(.regularMaterial)
                Capsule()
                    .strokeBorder(AngularGradient(colors: Self.ringColors, center: .center,
                                                  angle: .degrees((t / 4).truncatingRemainder(dividingBy: 1) * 360)),
                                  lineWidth: 1.4)
                HStack(spacing: 5) {
                    ZStack {
                        ForEach(0..<2, id: \.self) { i in
                            FinderStyleFileCard(type: i == 0 ? .image : .pdf, width: 9, height: 12, cornerRadius: 2)
                                .rotationEffect(.degrees(Double(i) * 12 - 6 + sin(t * 2.4 + Double(i)) * 2))
                                .offset(x: CGFloat(i) * 4 - 2, y: CGFloat(sin(t * 2.6 + Double(i) * 1.4)) * 0.8 - 2)
                        }
                    }
                    .frame(width: 16)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 24, height: 3)
                }
            }
            .frame(width: 62, height: 20)
            .shadow(color: DropZoneStyle.gradientColors[1].opacity(0.35), radius: 4, x: 0, y: 1)
        }
        .accessibilityHidden(true)
    }
}
