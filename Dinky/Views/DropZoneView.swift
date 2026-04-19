import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum DropZonePhase: Equatable {
    case idle, hovering, processing, done
}

struct DropZoneView: View {
    var phase: DropZonePhase
    let onOpenPanel: () -> Void
    var onPaste: () -> Void = {}
    var onLoop: () -> Void = {}

    @EnvironmentObject var prefs: DinkyPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var shouldReduceMotion: Bool { prefs.reduceMotion || systemReduceMotion }

    @State private var doneFlash      = false
    @State private var ringScale      : CGFloat = 1.0
    @State private var ringOpacity    : Double  = 0.5
    @State private var sparkleScale   : CGFloat = 0
    @State private var sparkleOpacity : Double  = 0

    var body: some View {
        ZStack {
            // Content sits beneath the animation so cards pass over the label
            VStack(spacing: 18) {
                if phase != .idle { symbolView }
                labelView
            }

            // Idle animation floats on top
            if phase == .idle {
                if shouldReduceMotion {
                    StaticCardStack()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    IdleAnimation(onLoop: onLoop)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onOpenPanel() }
        .onChange(of: phase) { _, new in
            if new == .done { doneFlash.toggle(); triggerSparkles() }
        }
    }

    @ViewBuilder
    private var symbolView: some View {
        switch phase {
        case .idle:
            EmptyView() // handled by background layer above

        case .hovering:
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1.5)
                    .frame(width: 144, height: 144)
                    .scaleEffect(ringScale).opacity(ringOpacity)
                Circle()
                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 1.5)
                    .frame(width: 110, height: 110)
                    .scaleEffect(ringScale).opacity(ringOpacity)
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.28, green: 0.56, blue: 1.0),
                                 Color(red: 0.52, green: 0.28, blue: 0.96)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.accentColor.opacity(0.45), radius: 18, x: 0, y: 6)
                Image(systemName: "arrow.down")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, options: .repeating.speed(0.65))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                    ringScale = 1.12; ringOpacity = 0.12
                }
            }

        case .processing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.rotate, options: .repeating)

        case .done:
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    let angle = Double(i) * 60 * (.pi / 180)
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(sparkleColors[i % sparkleColors.count])
                        .offset(x: CGFloat(cos(angle)) * 54 * sparkleScale,
                                y: CGFloat(sin(angle)) * 54 * sparkleScale)
                        .scaleEffect(sparkleScale > 0 ? 1 : 0.1)
                        .opacity(sparkleOpacity)
                }
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(Color.green)
                    .symbolEffect(.bounce, value: doneFlash)
            }
        }
    }

    private let sparkleColors: [Color] = [.yellow, .orange, .pink, .purple, .cyan, .green]

    @ViewBuilder
    private var labelView: some View {
        switch phase {
        case .idle:
            VStack(spacing: 5) {
                Text(String(localized: "Drop files here", comment: "Drop zone idle hint."))
                    .font(.title3).foregroundStyle(.primary)
                Text(String(localized: "or click to browse", comment: "Drop zone idle hint."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(action: onPaste) {
                    Text(String(localized: "or paste (\(prefs.shortcut(for: .pasteClipboard).displayString))", comment: "Drop zone; argument is paste shortcut."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        case .hovering:
            Text(String(localized: "Release to compress", comment: "Drop zone while dragging files."))
                .font(.title3.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(
                    Capsule().fill(LinearGradient(
                        colors: [Color(red: 0.28, green: 0.56, blue: 1.0),
                                 Color(red: 0.52, green: 0.28, blue: 0.96)],
                        startPoint: .leading, endPoint: .trailing))
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 12, x: 0, y: 4))
        case .processing:
            Text(String(localized: "Compressing…", comment: "Drop zone during compression.")).font(.title3).foregroundStyle(.secondary)
        case .done:
            Text(String(localized: "All done!", comment: "Drop zone when batch completes.")).font(.title3.weight(.medium)).foregroundStyle(Color.green)
        }
    }

    private func triggerSparkles() {
        sparkleScale = 0; sparkleOpacity = 1
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { sparkleScale = 1 }
        withAnimation(.easeOut(duration: 0.55).delay(0.3))             { sparkleOpacity = 0 }
    }
}

// MARK: - Idle drag animation

// MARK: - File card type

private enum FileCardType {
    case image, video, pdf

    /// UTTypes aligned with Dinky-supported types (see `MediaType`).
    var workspaceContentType: UTType {
        switch self {
        case .image: return .jpeg
        case .video: return .mpeg4Movie
        case .pdf:   return .pdf
        }
    }

    /// Resolved while the given `ColorScheme`’s `NSAppearance` is current so Finder-style file icons match light / dark UI.
    func workspaceIcon(for colorScheme: ColorScheme) -> NSImage {
        let ut = workspaceContentType
        let name: NSAppearance.Name = (colorScheme == .dark) ? .darkAqua : .aqua
        guard let appearance = NSAppearance(named: name) else {
            return NSWorkspace.shared.icon(for: ut)
        }
        var icon: NSImage!
        appearance.performAsCurrentDrawingAppearance {
            icon = NSWorkspace.shared.icon(for: ut)
        }
        return icon
    }
}

/// Uniform portrait tiles for the idle fan — same footprint so the stack reads like a deck of cards (system icons letterbox inside).
private enum IdleFileCardLayout {
    static let portraitWidth: CGFloat = 54
    static let portraitHeight: CGFloat = 74
    static let staticCorner: CGFloat = 7
    static let animatedCorner: CGFloat = 11
}

/// Final positions for the 3-card fan (reduce-motion + `playTwoTrips`): left / centre / right with shared baseline. Draw order remains PDF → video → image (back → front).
private enum IdleThreeCardFan {
    static let landingY: CGFloat = -80

    static var image: CGSize { CGSize(width: -22, height: landingY - 2) }
    static var video: CGSize { CGSize(width: 0, height: landingY - 2) }
    static var pdf: CGSize { CGSize(width: 22, height: landingY - 2) }
}

// MARK: - Finder-style file card (system document icons)

private struct FinderStyleFileCard: View {
    let type: FileCardType
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 8

    @Environment(\.colorScheme) private var colorScheme

    /// Drop shadow (not `Color.primary`) — avoids a bright halo on dark / tinted backgrounds.
    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.38) : Color.black.opacity(0.12)
    }

    private var shadowRadius: CGFloat { colorScheme == .dark ? 10 : 6 }
    private var shadowY: CGFloat { colorScheme == .dark ? 5 : 3 }

    var body: some View {
        let icon = type.workspaceIcon(for: colorScheme)
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            Group {
                if icon.isTemplate {
                    Image(nsImage: icon)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(Color.secondary)
                } else {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .padding(min(width, height) * 0.12)
        }
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        .frame(width: width, height: height)
        .id("\(type)-\(colorScheme)")
    }
}

// MARK: - Static card stack (reduce motion)

struct StaticCardStack: View {
    var body: some View {
        ZStack {
            // PDF — back
            FinderStyleFileCard(type: .pdf, width: IdleFileCardLayout.portraitWidth, height: IdleFileCardLayout.portraitHeight, cornerRadius: IdleFileCardLayout.staticCorner)
                .offset(x: IdleThreeCardFan.pdf.width, y: IdleThreeCardFan.pdf.height)
                .rotationEffect(.degrees(7))
            // Video — middle
            FinderStyleFileCard(type: .video, width: IdleFileCardLayout.portraitWidth, height: IdleFileCardLayout.portraitHeight, cornerRadius: IdleFileCardLayout.staticCorner)
                .offset(x: IdleThreeCardFan.video.width, y: IdleThreeCardFan.video.height)
                .rotationEffect(.degrees(0))
            // Image — front
            FinderStyleFileCard(type: .image, width: IdleFileCardLayout.portraitWidth, height: IdleFileCardLayout.portraitHeight, cornerRadius: IdleFileCardLayout.staticCorner)
                .offset(x: IdleThreeCardFan.image.width, y: IdleThreeCardFan.image.height)
                .rotationEffect(.degrees(-7))
        }
    }
}

// MARK: - Animated idle

struct IdleAnimation: View {

    var onLoop: () -> Void = {}
    var landingOffset: CGSize = CGSize(width: 0, height: -80)

    @State private var animationID  : UUID    = UUID()
    @State private var finished     : Bool    = false
    @State private var viewSize     : CGSize  = CGSize(width: 440, height: 380)
    @State private var cursorOffset : CGSize  = .zero
    @State private var cursorLifted : Bool    = false
    @State private var card1Offset  : CGSize  = .zero
    @State private var card2Offset  : CGSize  = .zero
    @State private var card3Offset  : CGSize  = .zero
    @State private var card1Angle   : Double  = 0
    @State private var card2Angle   : Double  = 0
    @State private var card3Angle   : Double  = 0
    @State private var card1Opacity : Double  = 0
    @State private var card2Opacity : Double  = 0
    @State private var card3Opacity : Double  = 0
    @State private var entryCorner  : Corner  = .bottomRight
    @State private var step         : Int     = 0

    private var cardCount   : Int { step % 2 == 0 ? 2 : 1 }
    private var animStyle   : Int { step % 3 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // card3 — PDF (back; drawn first)
                photoCard(type: .pdf)
                    .offset(card3Offset)
                    .rotationEffect(.degrees(card3Angle))
                    .opacity(card3Opacity)

                // card2 — video (middle)
                photoCard(type: .video)
                    .offset(card2Offset)
                    .rotationEffect(.degrees(card2Angle))
                    .opacity(card2Opacity)

                // card1 — image (front)
                photoCard(type: .image)
                    .offset(card1Offset)
                    .rotationEffect(.degrees(card1Angle))
                    .opacity(card1Opacity)

                Image("pinch-hand")
                    .interpolation(.high)
                    .frame(width: 60, height: 50)
                    .offset(cursorOffset)
                    .offset(x: 18, y: cursorLifted ? -11 : 0)
            }
            // Fill the full ZStack area so offsets are relative to the true centre
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Elements enter/exit naturally at the edge — no artificial fade needed
            .clipped()
            .onChange(of: geo.size) { _, s in viewSize = s }
            .onAppear { viewSize = geo.size }
        }
        .task(id: animationID) { await runLoop() }
        .onHover { hovering in
            if hovering && finished {
                finished = false
                animationID = UUID()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification))   { _ in entryCorner = Self.currentCorner() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in entryCorner = Self.currentCorner() }
        .onAppear { entryCorner = Self.currentCorner() }
    }

    private func photoCard(type: FileCardType) -> some View {
        FinderStyleFileCard(
            type: type,
            width: IdleFileCardLayout.portraitWidth,
            height: IdleFileCardLayout.portraitHeight,
            cornerRadius: IdleFileCardLayout.animatedCorner
        )
    }

    // MARK: - Corner

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
        var sign: Double {
            switch self {
            case .topLeft, .bottomRight:  return  1
            case .topRight, .bottomLeft: return -1
            }
        }
    }

    // Start just beyond the visible edge so elements enter naturally via clipping
    private func edgeOffset(corner: Corner, extra: CGFloat = 70) -> CGSize {
        let x = viewSize.width  / 2 + extra
        let y = viewSize.height / 2 + extra
        switch corner {
        case .topLeft:     return CGSize(width: -x, height: -y)
        case .topRight:    return CGSize(width:  x, height: -y)
        case .bottomLeft:  return CGSize(width: -x, height:  y)
        case .bottomRight: return CGSize(width:  x, height:  y)
        }
    }

    static func currentCorner() -> Corner {
        let win = NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
        guard let win, let screen = win.screen ?? NSScreen.main else { return .bottomRight }
        let wc = CGPoint(x: win.frame.midX, y: win.frame.midY)
        let sc = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        // Always enter from the bottom — only left/right varies by window position
        return wc.x >= sc.x ? .bottomLeft : .bottomRight
    }

    // MARK: - Loop

    private func runLoop() async {
        await sleep(200)
        guard !Task.isCancelled else { return }
        // Single sequence: cursor enters, drops image → video → pdf, then exits off-screen.
        // Cards remain visible as the final resting state until the user hovers back in.
        await playTwoTrips()
        onLoop()
        finished = true
    }

    // ── Variant A: straight drag in, release, exit ───────────────
    private func playDragAndDrop() async {
        let s = edgeOffset(corner: entryCorner)
        let g = entryCorner.sign
        let lh = landing.height
        await snap(cursor: s,
                   c1: CGSize(width: s.width + 22 * g, height: s.height + 15),
                   c2: CGSize(width: s.width + 38 * g, height: s.height + 26),
                   a1: 14 * g, a2: 22 * g,
                   op1: cardCount >= 1 ? 1 : 0, op2: cardCount >= 2 ? 1 : 0)

        // Travel to landing point — cards trail cursor from their corner
        let travel = travelDuration()
        withAnimation(.timingCurve(0.22, 0.0, 0.28, 1.0, duration: travel)) {
            cursorOffset = landing
            card1Offset  = CGSize(width: 14 * g, height: lh + 10)
            card2Offset  = CGSize(width: 24 * g, height: lh + 18)
            card1Angle   = 4 * g;  card2Angle = 8 * g
        }
        await sleep(Int(travel * 1000))

        // Release — cursor lifts, cards spring to centred resting position
        withAnimation(.spring(response: 0.30, dampingFraction: 0.52)) {
            cursorLifted = true
            card1Offset  = CGSize(width: -9, height: lh + 4)
            card2Offset  = CGSize(width:  9, height: lh + 14)
            card1Angle   = -4;  card2Angle = 5
        }
        await sleep(500)

        // Cursor exits back to corner
        withAnimation(.timingCurve(0.55, 0.0, 1.0, 1.0, duration: 0.45)) {
            cursorOffset = s; cursorLifted = false
        }
        await sleep(300)

        withAnimation(.easeOut(duration: 0.18)) { card1Opacity = 0; card2Opacity = 0; card3Opacity = 0 }
        await sleep(220)
    }

    // ── Variant B: overshoot arc then spring ─────────────────────
    private func playSwoop() async {
        let s = edgeOffset(corner: entryCorner, extra: 80)
        let g = entryCorner.sign
        let lh = landing.height
        await snap(cursor: s,
                   c1: CGSize(width: s.width + 20 * g, height: s.height + 14),
                   c2: CGSize(width: s.width + 36 * g, height: s.height + 24),
                   a1: 18 * g, a2: 26 * g,
                   op1: cardCount >= 1 ? 1 : 0, op2: cardCount >= 2 ? 1 : 0)

        let travel = travelDuration()
        // Overshoot past centre — cards trail with corner-side lean
        withAnimation(.timingCurve(0.4, 0.0, 0.55, 1.0, duration: travel * 0.65)) {
            cursorOffset = CGSize(width: -10 * g, height: lh - 8)
            card1Offset  = CGSize(width:  -6 * g, height: lh - 4)
            card2Offset  = CGSize(width:   6 * g, height: lh + 6)
            card1Angle   = -3 * g;  card2Angle = 3 * g
        }
        await sleep(Int(travel * 650))

        // Spring back — settle centred above text
        withAnimation(.spring(response: 0.38, dampingFraction: 0.60)) {
            cursorOffset = landing
            card1Offset  = CGSize(width: -9, height: lh + 4)
            card2Offset  = CGSize(width:  9, height: lh + 14)
            card1Angle   = -4;  card2Angle = 5
        }
        await sleep(420)

        withAnimation(.spring(response: 0.28, dampingFraction: 0.48)) {
            cursorLifted = true
            card1Offset  = CGSize(width: -9, height: lh + 8)
            card2Offset  = CGSize(width:  9, height: lh + 18)
        }
        await sleep(460)

        withAnimation(.timingCurve(0.55, 0.0, 1.0, 1.0, duration: 0.40)) {
            cursorOffset = s; cursorLifted = false
        }
        await sleep(280)

        withAnimation(.easeOut(duration: 0.16)) { card1Opacity = 0; card2Opacity = 0; card3Opacity = 0 }
        await sleep(200)
    }

    // ── Variant C: three separate trips ──────────────────────────
    private func playTwoTrips() async {
        let s = edgeOffset(corner: entryCorner)
        let g = entryCorner.sign
        let lh = landing.height
        let travel = travelDuration()

        // If cards from a previous run are still on screen, fade them out before resetting layout
        if card1Opacity > 0 || card2Opacity > 0 || card3Opacity > 0 {
            withAnimation(.easeOut(duration: 0.20)) {
                card1Opacity = 0; card2Opacity = 0; card3Opacity = 0
            }
            await sleep(220)
        }

        // Trip 1 — portrait card, settles left
        await snap(cursor: s,
                   c1: CGSize(width: s.width + 18 * g, height: s.height + 12),
                   c2: s, a1: 13 * g, a2: 0, op1: 1, op2: 0)

        withAnimation(.timingCurve(0.22, 0.0, 0.28, 1.0, duration: travel)) {
            cursorOffset = CGSize(width: 8 * g, height: lh + 6)
            card1Offset  = CGSize(width: 16 * g, height: lh + 10)
            card1Angle   = 4 * g
        }
        await sleep(Int(travel * 1000))

        withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
            cursorLifted = true
            card1Offset  = CGSize(width: IdleThreeCardFan.image.width, height: IdleThreeCardFan.image.height)
            card1Angle   = -7
        }
        await sleep(260)
        withAnimation(.timingCurve(0.55, 0.0, 1.0, 1.0, duration: 0.40)) {
            cursorOffset = s; cursorLifted = false
        }
        await sleep(340)

        // Trip 2 — centre card (video)
        card2Offset = CGSize(width: s.width + 28 * g, height: s.height + 18)
        card2Angle  = 18 * g
        withAnimation(.easeIn(duration: 0.08)) { card2Opacity = 1 }

        withAnimation(.timingCurve(0.22, 0.0, 0.28, 1.0, duration: travel)) {
            cursorOffset = CGSize(width: 6 * g, height: lh + 4)
            card2Offset  = CGSize(width: 18 * g, height: lh + 14)
            card2Angle   = 6 * g
        }
        await sleep(Int(travel * 1000))

        withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
            cursorLifted = true
            card2Offset  = CGSize(width: IdleThreeCardFan.video.width, height: IdleThreeCardFan.video.height)
            card2Angle   = 0
        }
        await sleep(260)
        withAnimation(.timingCurve(0.55, 0.0, 1.0, 1.0, duration: 0.40)) {
            cursorOffset = s; cursorLifted = false
        }
        await sleep(340)

        // Trip 3 — PDF (back of fan)
        card3Offset = CGSize(width: s.width + 36 * g, height: s.height + 22)
        card3Angle  = 24 * g
        withAnimation(.easeIn(duration: 0.08)) { card3Opacity = 1 }

        withAnimation(.timingCurve(0.22, 0.0, 0.28, 1.0, duration: travel)) {
            cursorOffset = landing
            card3Offset  = CGSize(width: 22 * g, height: lh - 2)
            card3Angle   = 7 * g
        }
        await sleep(Int(travel * 1000))

        withAnimation(.spring(response: 0.28, dampingFraction: 0.50)) {
            cursorLifted = true
            card3Offset  = CGSize(width: IdleThreeCardFan.pdf.width, height: IdleThreeCardFan.pdf.height)
            card3Angle   = 7
        }
        await sleep(460)

        // Cursor exits off-screen — cards stay put as the final resting frame.
        // Animation is considered "complete" until the user hovers back in (see `.onHover` in body).
        withAnimation(.timingCurve(0.55, 0.0, 1.0, 1.0, duration: 0.45)) {
            cursorOffset = s
            cursorLifted = false
        }
        await sleep(460)
    }

    // MARK: - Helpers

    /// Where the cursor and cards land — above the centred label text
    private var landing: CGSize { landingOffset }

    /// Scale travel duration to window size — bigger window = slightly longer drag
    private func travelDuration() -> Double {
        let diagonal = sqrt(viewSize.width * viewSize.width + viewSize.height * viewSize.height)
        return min(2.0, max(0.9, Double(diagonal) / 600))
    }

    @MainActor
    private func snap(cursor c: CGSize,
                       c1: CGSize, c2: CGSize,
                       a1: Double, a2: Double,
                       op1: Double, op2: Double) async {
        cursorOffset = c
        card1Offset  = c1;   card2Offset  = c2
        card1Angle   = a1;   card2Angle   = a2
        card1Opacity = op1;  card2Opacity = op2
        card3Opacity = 0
        cursorLifted = false
    }

    private func sleep(_ ms: Int) async {
        try? await Task.sleep(for: .milliseconds(ms))
    }
}

