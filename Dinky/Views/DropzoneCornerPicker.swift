import SwiftUI
import AppKit
import ImageIO

/// Settings: pick the floating dropzone's corner, System Settings style — four small thumbnails of
/// your own desktop, each with a tiny dropzone in its corner and its name underneath. The chosen one
/// gets the accent ring.
struct DropzoneCornerPicker: View {
    @Binding var corner: ScreenCorner
    @State private var wallpaper: NSImage?

    /// Reading order: the top row, then the bottom row.
    private static let order: [ScreenCorner] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Self.order) { c in
                CornerTile(corner: c, isSelected: c == corner, wallpaper: wallpaper) { corner = c }
            }
        }
        .task { wallpaper = await Self.loadWallpaper() }
    }

    /// The default wallpaper of the macOS version that's running, small. The same picture for
    /// everyone on that version, and no guessing at Aerials or other moving wallpapers.
    private static func loadWallpaper() async -> NSImage? {
        let cg = await Task.detached(priority: .utility) {
            downsampled(URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic"))
        }.value
        return cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    nonisolated private static func downsampled(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }
}

private struct CornerTile: View {
    let corner: ScreenCorner
    let isSelected: Bool
    let wallpaper: NSImage?
    let select: () -> Void

    @AppStorage("reduceMotion") private var appReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private static let size = CGSize(width: 84, height: 54)

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                thumbnail
                    .frame(width: Self.size.width, height: Self.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2.5)
                            .opacity(isSelected ? 1 : 0)
                    )
                Text(corner.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(corner.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var thumbnail: some View {
        ZStack {
            if let wallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(red: 0.36, green: 0.52, blue: 0.86), Color(red: 0.58, green: 0.42, blue: 0.82)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            // Menu bar and Dock, just enough to read as a screen.
            VStack(spacing: 0) {
                Rectangle().fill(.ultraThinMaterial).frame(height: 5)
                Spacer()
                Capsule().fill(.ultraThinMaterial).frame(width: 34, height: 5).padding(.bottom, 3)
            }
            miniDropzone
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                // Inset like the real one: clear of the menu bar, the Dock and the screen edge.
                .padding(.top, corner.isTop ? 10 : 0)
                .padding(.bottom, corner.isTop ? 0 : 13)
                .padding(.horizontal, 9)
        }
    }

    /// The dropzone pill at tile scale: glass, a file card, a hint of the brand gradient.
    private var miniDropzone: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(.white)
                .frame(width: 5, height: 6.5)
                .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
            Capsule()
                .fill(LinearGradient(colors: DropZoneStyle.gradientColors, startPoint: .leading, endPoint: .trailing))
                .frame(width: 13, height: 2.5)
        }
        .padding(.horizontal, 5)
        .frame(height: 11)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .scaleEffect(isSelected ? 1 : 0.85)
        .opacity(isSelected ? 1 : 0.55)
        .animation(appReduceMotion || systemReduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6), value: isSelected)
    }

    private var alignment: Alignment {
        switch corner {
        case .bottomRight: return .bottomTrailing
        case .bottomLeft:  return .bottomLeading
        case .topRight:    return .topTrailing
        case .topLeft:     return .topLeading
        }
    }
}
