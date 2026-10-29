import SwiftUI
import AppKit
import DinkyCoreShared
import UniformTypeIdentifiers

/// The floating dropzone's content: a dinky copy of the main drop zone that lives in a screen
/// corner. A pill while files are dragged far away, swelling as they get closer; the full target
/// with preset tiles when they're near; squished cards and a shrinking byte count while working;
/// sparkles and draggable results when done.
struct FloatingDropzoneView: View {
    @ObservedObject var controller: FloatingDropzoneController
    @EnvironmentObject var prefs: DinkyPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { prefs.reduceMotion || systemReduceMotion }

    @Namespace private var glass
    @State private var mainTargeted = false
    /// The preset the track is on. `nil` is the active preset (or your settings). Sweeping over
    /// the track mid-drag moves it, and a drop anywhere on the card uses it.
    @State private var chosenPreset: UUID?
    /// Files are over the preset track itself.
    @State private var trackTargeted = false

    private var corner: ScreenCorner { controller.corner }

    private var alignment: Alignment {
        switch corner {
        case .bottomRight: return .bottomTrailing
        case .bottomLeft:  return .bottomLeading
        case .topRight:    return .topTrailing
        case .topLeft:     return .topLeading
        }
    }

    private var anchor: UnitPoint {
        switch corner {
        case .bottomRight: return .bottomTrailing
        case .bottomLeft:  return .bottomLeading
        case .topRight:    return .topTrailing
        case .topLeft:     return .topLeading
        }
    }

    private var spring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.72)
    }

    var body: some View {
        ZStack(alignment: alignment) {
            Color.clear
            if controller.stage != .hidden {
                DropzoneGlassContainer(spacing: 12) {
                    stack
                }
                // Drawn over the whole glass group: anything attached to a glass shape renders
                // beneath the glass, which hid the cards.
                .overlayPreferenceValue(MainShapeBounds.self) { anchor in
                    GeometryReader { proxy in
                        if let anchor {
                            decorations(in: proxy[anchor])
                        }
                    }
                }
                .padding(14)
                .transition(reduceMotion
                    ? .opacity
                    : .scale(scale: 0.4, anchor: anchor).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .animation(spring, value: controller.stage)
        .animation(spring, value: controller.isExpanded)
        .onHover { controller.isHovering = $0 }
        .onChange(of: mainTargeted) { _, targeted in
            if targeted { controller.dragEnteredTarget() }
        }
        // Each new drag starts back on the active preset.
        .onChange(of: controller.stage) { _, stage in
            if stage == .dragging { chosenPreset = nil; trackTargeted = false }
        }
    }

    /// Preset chips sit on the side away from the screen edge, with room between them and the
    /// target for the cards breaking out of its edge.
    @ViewBuilder
    private var stack: some View {
        VStack(spacing: 10) {
            if !corner.isTop { presetTrack }
            main
            if corner.isTop { presetTrack }
        }
    }

    @ViewBuilder
    private var main: some View {
        switch controller.stage {
        case .hidden:
            EmptyView()
        case .dragging:
            if controller.isExpanded { expandedTarget } else { pill }
        case .working:
            WorkingCard(controller: controller, reduceMotion: reduceMotion)
                .frame(width: DropzoneLayout.cardWidth)
                .dropzoneGlass(RoundedRectangle(cornerRadius: DropzoneLayout.cardCorner, style: .continuous), id: "main", in: glass)
                .anchorPreference(key: MainShapeBounds.self, value: .bounds) { $0 }
        case .done:
            DoneCard(controller: controller, corner: corner, reduceMotion: reduceMotion)
                .frame(width: DropzoneLayout.cardWidth)
                .dropzoneGlass(RoundedRectangle(cornerRadius: DropzoneLayout.cardCorner, style: .continuous), id: "main", in: glass)
                .anchorPreference(key: MainShapeBounds.self, value: .bounds) { $0 }
        }
    }

    /// Cards lean toward the screen corner as the pointer gets close.
    private var lean: CGFloat {
        reduceMotion ? 0 : controller.proximity * (corner.isLeft ? -1 : 1)
    }

    // MARK: - Ring and breakout cards

    /// The brand ring around the main shape, and the file cards spilling out over its edge on
    /// the side away from the screen corner.
    @ViewBuilder
    private func decorations(in rect: CGRect) -> some View {
        let isPill = controller.stage == .dragging && !controller.isExpanded
        ZStack(alignment: .topLeading) {
            BrandRing(isCapsule: isPill, cornerRadius: DropzoneLayout.cardCorner,
                      intensity: ringIntensity, speed: mainTargeted ? 2.2 : 1,
                      // The blurred glow redraws every frame; skip it while compression wants the CPU.
                      glows: controller.stage != .working, reduceMotion: reduceMotion)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)

            breakoutCards
                .frame(width: 48, height: 40)
                .position(cardsCenter(in: rect, isPill: isPill))
        }
        .allowsHitTesting(false)
    }

    private var ringIntensity: Double {
        switch controller.stage {
        case .hidden:   return 0
        case .dragging: return mainTargeted || trackTargeted ? 1 : 0.3 + 0.7 * Double(controller.proximity)
        case .working:  return 0.85
        case .done:     return 0.35
        }
    }

    @ViewBuilder
    private var breakoutCards: some View {
        switch controller.stage {
        case .hidden:
            EmptyView()
        case .dragging:
            MiniCardFan(types: fanTypes, lean: controller.isExpanded ? 0 : lean)
                .scaleEffect(controller.isExpanded ? (mainTargeted || trackTargeted ? 0.8 : 1.15) : 1)
                .animation(spring, value: mainTargeted || trackTargeted)
        case .working:
            SquishingCards(types: resultTypes, trigger: controller.dropID, fromSide: corner.isLeft ? -1 : 1, reduceMotion: reduceMotion)
        case .done:
            MiniCardFan(types: resultTypes).scaleEffect(0.9)
        }
    }

    /// On the pill: inside it, beside the label, peeking over its edge and lifting as the
    /// pointer nears. On the bigger cards: mostly out over the edge.
    private func cardsCenter(in rect: CGRect, isPill: Bool) -> CGPoint {
        if isPill {
            // Just peeking over the edge at rest; sinks into the pill as files get close.
            let x = corner.isLeft ? rect.maxX - 34 : rect.minX + 34
            let lift = 5 - 5 * (reduceMotion ? 0 : controller.proximity) - (mainTargeted && !reduceMotion ? 3 : 0)
            return CGPoint(x: x, y: corner.isTop ? rect.midY + lift : rect.midY - lift)
        }
        if controller.stage == .dragging {
            // Resting on the circle; dropping right into it when files are over the card.
            let y = mainTargeted || trackTargeted ? rect.minY + 59 : rect.minY + 38
            return CGPoint(x: rect.midX, y: y)
        }
        let inset: CGFloat = 52
        let x = corner.isLeft ? rect.maxX - inset : rect.minX + inset
        var lift: CGFloat = 22
        if controller.stage == .done { lift = 26 }
        return CGPoint(x: x, y: corner.isTop ? rect.maxY + lift : rect.minY - lift)
    }

    // MARK: - Pill (far)

    private var pill: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(String(localized: "Make it dinky", comment: "Floating dropzone: call to action while files are dragged."))
                .font(.callout.weight(.semibold))
            Text(draggedCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        // Room on the outer side for the cards sitting on the pill.
        .padding(corner.isLeft ? .trailing : .leading, 58)
        .padding(corner.isLeft ? .leading : .trailing, 24)
        .frame(height: 56)
        .contentShape(Capsule())
        .dropzoneGlass(Capsule(), id: "main", in: glass)
        // The cards lift further out of the pill the closer the pointer gets.
        // Swells toward the pointer, like the Dock magnifying under it.
        .scaleEffect(reduceMotion ? 1 : 1 + 0.12 * controller.proximity, anchor: anchor)
        .anchorPreference(key: MainShapeBounds.self, value: .bounds) { $0 }
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.3, dampingFraction: 0.7), value: controller.proximity)
        .onDrop(of: [.fileURL, .url], isTargeted: $mainTargeted) { controller.accept($0, presetID: nil) }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Full target (near)

    private var expandedTarget: some View {
        VStack(spacing: 10) {
            ZStack {
                LetGoRings(active: mainTargeted, reduceMotion: reduceMotion)
                Circle()
                    .fill(LinearGradient(colors: DropZoneStyle.gradientColors,
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                    .shadow(color: Color.accentColor.opacity(0.45), radius: 14, x: 0, y: 5)
                    .scaleEffect(mainTargeted && !reduceMotion ? 1.12 : 1)
                Image(systemName: "arrow.down")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, options: .repeating.speed(0.65), isActive: !reduceMotion)
                    .opacity(mainTargeted ? 0 : 1)
            }
            .frame(height: 78)

            Text(mainTargeted || trackTargeted
                 ? String(localized: "Let go.", comment: "Floating dropzone: files are over the target.")
                 : String(localized: "Make it dinky", comment: "Floating dropzone: call to action while files are dragged."))
                .font(.title3.weight(.semibold))
                .contentTransition(.opacity)
            Text(chosenPresetName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .padding(.top, 20)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(width: DropzoneLayout.cardWidth)
        .contentShape(RoundedRectangle(cornerRadius: DropzoneLayout.cardCorner, style: .continuous))
        .dropzoneGlass(RoundedRectangle(cornerRadius: DropzoneLayout.cardCorner, style: .continuous), id: "main", in: glass,
                       tint: mainTargeted ? DropZoneStyle.gradientColors[0].opacity(0.25) : nil)
        .anchorPreference(key: MainShapeBounds.self, value: .bounds) { $0 }
        .onDrop(of: [.fileURL, .url], isTargeted: $mainTargeted) { controller.accept($0, presetID: chosenPreset) }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Preset track

    /// A stack of roomy rows: the active preset nearest the target, then the others that fit what's
    /// being dragged. Sweeping up the stack mid-drag slides the gradient pill from row to row.
    @ViewBuilder
    private var presetTrack: some View {
        let presets = controller.tilePresets
        if controller.stage == .dragging, controller.isExpanded, !presets.isEmpty {
            let nearestFirst: [(label: String, id: UUID?)] =
                [(label: controller.mainTargetSubtitle, id: nil)] + presets.map { (label: $0.name, id: Optional($0.id)) }
            // Above the target the nearest row is the bottom one.
            let items = corner.isTop ? nearestFirst : nearestFirst.reversed()
            VStack(spacing: 2) {
                ForEach(items, id: \.id) { item in
                    presetSegment(item.label, id: item.id)
                }
            }
            .padding(4)
            .frame(width: DropzoneLayout.cardWidth)
            // Its own glass piece beside the target, not nested in it: a drop target inside
            // another never sees the drag on macOS, so the rows couldn't be hovered.
            .dropzoneGlass(RoundedRectangle(cornerRadius: 20, style: .continuous), id: "track", in: glass)
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.78), value: chosenPreset)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.6, anchor: corner.isTop ? .top : .bottom).combined(with: .opacity))
        }
    }

    private var chosenPresetName: String {
        guard let chosenPreset,
              let preset = controller.tilePresets.first(where: { $0.id == chosenPreset }) else {
            return controller.mainTargetSubtitle
        }
        return preset.name
    }

    private func presetSegment(_ label: String, id: UUID?) -> some View {
        let active = chosenPreset == id
        return HStack(spacing: 8) {
            Text(label)
                .font(.callout.weight(active ? .semibold : .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            if id == nil {
                Text(String(localized: "Current", comment: "Floating dropzone: marks the preset the main window is using."))
                    .font(.caption)
                    .opacity(0.75)
            }
        }
        .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 14)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background {
            if active {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: DropZoneStyle.gradientColors,
                                         startPoint: .leading, endPoint: .trailing))
                    .shadow(color: DropZoneStyle.gradientColors[1].opacity(0.35), radius: 4, x: 0, y: 1)
                    .matchedGeometryEffect(id: "presetPill", in: glass)
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url], isTargeted: Binding(
            get: { trackTargeted && chosenPreset == id },
            set: { isOn in
                if isOn {
                    chosenPreset = id
                    trackTargeted = true
                    controller.dragEnteredTarget()
                } else if chosenPreset == id {
                    // Keep the choice when leaving: sweep to a preset, then drop on the big target.
                    trackTargeted = false
                }
            }
        )) { controller.accept($0, presetID: id) }
        .onTapGesture { chosenPreset = id }
        .help(label)
        .accessibilityLabel(id == nil ? label : String(localized: "Compress with \(label)", comment: "Floating dropzone preset tile; argument is the preset name."))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: - Helpers

    private var fanTypes: [FileCardType] {
        let media = controller.dragged?.mediaTypes ?? []
        return media.isEmpty ? [.image] : media.map(FileCardType.init)
    }

    private var resultTypes: [FileCardType] {
        let order: [MediaType] = [.image, .video, .audio, .pdf]
        let media = Set(controller.results.map(\.mediaType))
        let types = order.filter(media.contains).map(FileCardType.init)
        return types.isEmpty ? fanTypes : types
    }

    private var draggedCountText: String {
        guard let d = controller.dragged else { return "" }
        if d.count == 0 {
            return String(localized: "Drop a folder", comment: "Floating dropzone: only folders are being dragged.")
        }
        if d.count == 1 {
            return String(localized: "1 file", comment: "Floating dropzone: one file is being dragged.")
        }
        return String(localized: "\(d.count) files", comment: "Floating dropzone: number of files being dragged.")
    }
}

private enum DropzoneLayout {
    static let cardWidth: CGFloat = 260
    static let cardCorner: CGFloat = 26
}

// MARK: - Working

private struct WorkingCard: View {
    @ObservedObject var controller: FloatingDropzoneController
    let reduceMotion: Bool

    var body: some View {
        let items = controller.results
        let before = items.reduce(Int64(0)) { $0 + (controller.originalSizes[$1.id] ?? 0) }
        let now = items.reduce(Int64(0)) { sum, item in
            if case .done(_, _, let out) = item.status { return sum + out }
            return sum + (controller.originalSizes[item.id] ?? 0)
        }
        let finished = items.filter { $0.status.isTerminal }.count
        let fraction = items.isEmpty ? 0 : Double(finished) / Double(items.count)

        return VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(String(localized: "Making it dinky…", comment: "Floating dropzone: compressing."))
                    .font(.callout.weight(.semibold))
                HStack(spacing: 6) {
                    Text(formatted(before))
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                    Text(formatted(now))
                        .contentTransition(.numericText(countsDown: true))
                        .animation(reduceMotion ? nil : .snappy, value: now)
                }
                .font(.caption.monospacedDigit())
            }
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(DropZoneStyle.gradientColors[0])
                .animation(.easeOut(duration: 0.3), value: fraction)
        }
        .padding(18)
    }

}

// MARK: - Done

private struct DoneCard: View {
    @ObservedObject var controller: FloatingDropzoneController
    let corner: ScreenCorner
    let reduceMotion: Bool
    @State private var burst = false
    @State private var nudge = 0
    /// The drag-out nudge plays for the first few results ever, then Dinky trusts you know.
    @AppStorage("floatingDropzoneNudgesShown") private var nudgesShown = 0
    private static let nudgeLimit = 3

    private static let maxRows = 4

    var body: some View {
        let items = controller.results
        let saved = items.reduce(Int64(0)) { $0 + $1.savedBytes }

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    SparkleBurst(radius: 26, starSize: 7, trigger: burst)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(LinearGradient(colors: DropZoneStyle.gradientColors,
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        .symbolEffect(.bounce, value: burst)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(saved > 0
                         ? String(localized: "Saved \(formatted(saved))", comment: "Floating dropzone: total saved; argument is a size like 3.2 MB.")
                         : String(localized: "Already tiny", comment: "Floating dropzone: nothing could be made smaller."))
                        .font(.callout.weight(.semibold))
                    Text(String(localized: "Drag them anywhere", comment: "Floating dropzone: results can be dragged out."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    controller.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Close", comment: "Floating dropzone: close button."))
            }

            VStack(spacing: 2) {
                ForEach(Array(items.prefix(Self.maxRows).enumerated()), id: \.element.id) { index, item in
                    if index == 0 {
                        ResultChip(item: item) { controller.reveal(item) }
                            .modifier(DragOutNudge(trigger: nudge, corner: corner))
                    } else {
                        ResultChip(item: item) { controller.reveal(item) }
                    }
                }
            }

            HStack {
                if items.count > Self.maxRows {
                    Text(String(localized: "+\(items.count - Self.maxRows) more", comment: "Floating dropzone: more results than shown."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "Open Dinky", comment: "Floating dropzone: show the main window.")) {
                    controller.openMainWindow()
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.medium))
            }
        }
        .padding(14)
        .modifier(ConcentricContainer(cornerRadius: DropzoneLayout.cardCorner))
        .onAppear {
            burst.toggle()
            guard !reduceMotion, nudgesShown < Self.nudgeLimit,
                  items.contains(where: { $0.outputURL != nil }) else { return }
            nudgesShown += 1
            // After the sparkles settle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { nudge += 1 }
        }
    }
}

/// One result: drag it out to use the compressed file, click it to show it in Finder.
private struct ResultChip: View {
    @ObservedObject var item: CompressionItem
    let onReveal: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: FileTypeIcon.icon(for: item.outputURL ?? item.sourceURL))
                .resizable()
                .frame(width: 22, height: 22)
            Text((item.outputURL ?? item.sourceURL).lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            badge
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            if hovering { RowHighlight() }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onReveal)
        .onDrag {
            NSItemProvider(contentsOf: item.outputURL ?? item.sourceURL) ?? NSItemProvider()
        }
        .help(String(localized: "Drag to use it, click to show in Finder", comment: "Floating dropzone: result row tooltip."))
    }

    @ViewBuilder
    private var badge: some View {
        switch item.status {
        case .done:
            // Neutral chip, like the main results list — green read poorly on the glass.
            Text("−\(Int(item.savedPercent.rounded()))%")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .help(item.statusLabel)
        default:
            Text(String(localized: "Kept", comment: "Floating dropzone: file wasn't made smaller, original kept."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(item.statusLabel)
        }
    }
}

/// A one-time hint that results can be dragged out: the first result lifts off the card toward
/// the open screen, tips, and settles back.
private struct DragOutNudge: ViewModifier {
    let trigger: Int
    let corner: ScreenCorner

    private struct Tug {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lift: CGFloat = 1
        var tilt: Double = 0
    }

    func body(content: Content) -> some View {
        // Away from the screen corner, where the files would go.
        let outX: CGFloat = corner.isLeft ? 1 : -1
        let outY: CGFloat = corner.isTop ? 1 : -1
        return content
            .keyframeAnimator(initialValue: Tug(), trigger: trigger) { chip, v in
                chip
                    .scaleEffect(v.lift)
                    .rotationEffect(.degrees(v.tilt * Double(-outX)))
                    .shadow(color: .black.opacity(0.18 * Double(v.lift - 1) * 12), radius: 8, x: 0, y: 4)
                    .offset(x: v.x * outX, y: v.y * outY)
            } keyframes: { _ in
                KeyframeTrack(\.lift) {
                    SpringKeyframe(1.06, duration: 0.25, spring: .snappy)
                    LinearKeyframe(1.06, duration: 0.3)
                    SpringKeyframe(1, duration: 0.45, spring: .bouncy)
                }
                KeyframeTrack(\.x) {
                    LinearKeyframe(0, duration: 0.15)
                    SpringKeyframe(10, duration: 0.35, spring: .smooth)
                    SpringKeyframe(0, duration: 0.5, spring: .bouncy)
                }
                KeyframeTrack(\.y) {
                    LinearKeyframe(0, duration: 0.15)
                    SpringKeyframe(8, duration: 0.35, spring: .smooth)
                    SpringKeyframe(0, duration: 0.5, spring: .bouncy)
                }
                KeyframeTrack(\.tilt) {
                    LinearKeyframe(0, duration: 0.15)
                    SpringKeyframe(-3, duration: 0.35, spring: .smooth)
                    SpringKeyframe(0, duration: 0.5, spring: .bouncy)
                }
            }
    }
}

/// On macOS 26+ the hover highlight nests concentrically inside the card's corners.
private struct RowHighlight: View {
    var body: some View {
        if #available(macOS 26, *) {
            ConcentricRectangle(corners: .concentric(minimum: .fixed(8)), isUniform: true)
                .fill(Color.primary.opacity(0.07))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        }
    }
}

private struct ConcentricContainer: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content.containerShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Cards

/// A small fan of the same Finder-style cards the main drop zone's idle animation uses.
/// `lean` (-1…1) tips them toward the screen corner as the pointer gets close.
private struct MiniCardFan: View {
    let types: [FileCardType]
    var lean: CGFloat = 0

    var body: some View {
        let shown = Array(types.prefix(3))
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, type in
                let spread = CGFloat(index) - CGFloat(shown.count - 1) / 2
                FinderStyleFileCard(type: type, width: 26, height: 35, cornerRadius: 5)
                    .rotationEffect(.degrees(Double(spread * 9 + lean * 8)))
                    .offset(x: spread * 9 + lean * 3, y: abs(spread) * 2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The drop moment, borrowed from the main drop zone's idle animation: the Dinky hand carries the
/// cards in from the screen edge, pinches them smaller, and slips back out.
private struct SquishingCards: View {
    let types: [FileCardType]
    let trigger: UUID
    /// The hand comes from the screen edge: +1 from the right, -1 from the left.
    let fromSide: CGFloat
    let reduceMotion: Bool

    private struct Pinch {
        var cardsX: CGFloat = 0
        var cardsY: CGFloat = 0
        var sx: CGFloat = 0.86
        var sy: CGFloat = 0.86
        var handX: CGFloat = 160
        var handY: CGFloat = 0
    }

    var body: some View {
        if reduceMotion {
            MiniCardFan(types: types)
                .scaleEffect(1.15)
        } else {
            ZStack {
                Color.clear
            }
            .keyframeAnimator(initialValue: Pinch(cardsX: 280, cardsY: -12, sx: 1, sy: 1, handX: 296), trigger: trigger) { _, v in
                ZStack {
                    MiniCardFan(types: types)
                        .scaleEffect(1.15)
                        .scaleEffect(x: v.sx, y: v.sy, anchor: .bottom)
                        .offset(x: v.cardsX * fromSide, y: v.cardsY)
                    Image("pinch-hand")
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 35)
                        .scaleEffect(x: fromSide < 0 ? -1 : 1)
                        .offset(x: v.handX * fromSide, y: v.handY)
                        .accessibilityHidden(true)
                }
            } keyframes: { _ in
                // Carry in (cards trail the hand), set down, pinch, let go, leave.
                KeyframeTrack(\.cardsX) {
                    SpringKeyframe(0, duration: 0.42, spring: .snappy)
                }
                KeyframeTrack(\.cardsY) {
                    SpringKeyframe(0, duration: 0.42, spring: .snappy)
                }
                KeyframeTrack(\.handX) {
                    SpringKeyframe(16, duration: 0.42, spring: .snappy)
                    LinearKeyframe(16, duration: 0.35)
                    CubicKeyframe(310, duration: 0.45)
                }
                KeyframeTrack(\.handY) {
                    LinearKeyframe(-6, duration: 0.42)
                    CubicKeyframe(4, duration: 0.12)
                    CubicKeyframe(-12, duration: 0.18)
                    CubicKeyframe(-4, duration: 0.4)
                }
                KeyframeTrack(\.sx) {
                    LinearKeyframe(1, duration: 0.44)
                    CubicKeyframe(1.2, duration: 0.1)
                    SpringKeyframe(0.86, duration: 0.45, spring: .bouncy)
                }
                KeyframeTrack(\.sy) {
                    LinearKeyframe(1, duration: 0.44)
                    CubicKeyframe(0.66, duration: 0.1)
                    SpringKeyframe(0.86, duration: 0.45, spring: .bouncy)
                }
            }
        }
    }
}

/// Pulsing rings behind the "let go" circle — the main drop zone's hover look, smaller.
private struct LetGoRings: View {
    let active: Bool
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(active ? 0.3 : 0.18), lineWidth: 1.5)
                .frame(width: 100, height: 100)
            Circle()
                .stroke(Color.accentColor.opacity(active ? 0.4 : 0.28), lineWidth: 1.5)
                .frame(width: 78, height: 78)
        }
        .scaleEffect(pulse ? 1.1 : 1)
        .opacity(pulse ? 0.35 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Glass

/// Liquid Glass on macOS 26+, so the pill, the full target and the preset tiles morph into one
/// another; frosted material before that.
private struct DropzoneGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func dropzoneGlass<S: Shape, ID: Hashable & Sendable>(
        _ shape: S,
        id: ID,
        in namespace: Namespace.ID,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
                .glassEffectID(id, in: namespace)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
        }
    }
}

// MARK: - Brand ring

private struct MainShapeBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A thin ring in the Dinky gradient that slowly circles the dropzone, with a soft glow that
/// brightens as files get close and peaks when they're over it.
private struct BrandRing: View {
    let isCapsule: Bool
    let cornerRadius: CGFloat
    /// 0…1
    let intensity: Double
    /// Turns per 4 seconds.
    let speed: Double
    var glows = true
    let reduceMotion: Bool

    private static let colors: [Color] = [
        DropZoneStyle.gradientColors[0],
        DropZoneStyle.gradientColors[1],
        Color(red: 0.93, green: 0.38, blue: 0.78),
        DropZoneStyle.gradientColors[1],
        DropZoneStyle.gradientColors[0],
    ]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let turns = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate / 4 * speed
            let gradient = AngularGradient(colors: Self.colors, center: .center,
                                           angle: .degrees(turns.truncatingRemainder(dividingBy: 1) * 360))
            ZStack {
                if glows {
                    ring(lineWidth: 7, style: gradient)
                        .blur(radius: 9)
                        .opacity(0.6 * intensity)
                }
                ring(lineWidth: 1.5, style: gradient)
                    .opacity(0.25 + 0.75 * intensity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: intensity)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func ring(lineWidth: CGFloat, style: AngularGradient) -> some View {
        if isCapsule {
            Capsule().strokeBorder(style, lineWidth: lineWidth)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(style, lineWidth: lineWidth)
        }
    }
}

private let byteFormatter: ByteCountFormatter = {
    let nf = ByteCountFormatter()
    nf.allowedUnits = [.useKB, .useMB, .useGB]
    nf.countStyle = .file
    return nf
}()

private func formatted(_ bytes: Int64) -> String {
    byteFormatter.string(fromByteCount: bytes)
}

/// Result rows re-render on every progress tick; look icons up once per file type, not per path.
@MainActor
private enum FileTypeIcon {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        let ext = url.pathExtension.lowercased()
        if let cached = cache[ext] { return cached }
        let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        cache[ext] = icon
        return icon
    }
}
