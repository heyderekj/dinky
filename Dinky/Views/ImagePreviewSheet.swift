import SwiftUI
import AppKit

struct ImagePreviewSheet: View {
    let item: CompressionItem
    @Environment(\.dismiss) private var dismiss

    enum PreviewMode { case sideBySide, slider }
    @State private var mode: PreviewMode = .sideBySide
    @State private var sliderPosition: CGFloat = 0.5

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if case .done(let outputURL, let origSize, let outSize) = item.status {
                Group {
                    if mode == .sideBySide {
                        sideBySideView(outputURL: outputURL, origSize: origSize, outSize: outSize)
                    } else {
                        sliderView(outputURL: outputURL, origSize: origSize, outSize: outSize)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("", selection: $mode) {
                Text(String(localized: "Side by Side", comment: "Image preview mode.")).tag(PreviewMode.sideBySide)
                Text(String(localized: "Slider", comment: "Image preview mode.")).tag(PreviewMode.slider)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .labelsHidden()

            Spacer()

            Text(item.filename)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220)

            Spacer()

            Button(String(localized: "Done", comment: "Dismiss preview sheet.")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sideBySideView(outputURL: URL, origSize: Int64, outSize: Int64) -> some View {
        HStack(spacing: 1) {
            imagePane(url: item.sourceURL, label: String(localized: "Original", comment: "Preview pane label."), size: origSize)
            Divider()
            imagePane(url: outputURL, label: String(localized: "Compressed", comment: "Preview pane label."), size: outSize)
        }
    }

    private func imagePane(url: URL, label: String, size: Int64) -> some View {
        VStack(spacing: 6) {
            if let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(formattedSize(size))
                    .font(.system(.caption, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func sliderView(outputURL: URL, origSize: Int64, outSize: Int64) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Compressed image fills the background
                if let img = NSImage(contentsOf: outputURL) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Original image clipped to the left portion
                if let img = NSImage(contentsOf: item.sourceURL) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .mask(
                            Rectangle()
                                .frame(width: geo.size.width * sliderPosition)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                }

                // Divider line + handle
                let x = geo.size.width * sliderPosition
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .shadow(radius: 4)
                    .offset(x: x - 1)

                Circle()
                    .fill(.white)
                    .frame(width: 28, height: 28)
                    .shadow(radius: 4)
                    .overlay(
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
                    .offset(x: x - 14, y: 0)
                    .frame(maxHeight: .infinity)

                // Labels
                VStack {
                    Spacer()
                    HStack {
                        label("Original", size: origSize, alignment: .leading)
                            .padding(.leading, 12)
                            .opacity(sliderPosition > 0.15 ? 1 : 0)
                        Spacer()
                        label("Compressed", size: outSize, alignment: .trailing)
                            .padding(.trailing, 12)
                            .opacity(sliderPosition < 0.85 ? 1 : 0)
                    }
                    .padding(.bottom, 12)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        sliderPosition = max(0, min(1, value.location.x / geo.size.width))
                    }
            )
        }
        .padding(12)
    }

    private func label(_ text: String, size: Int64, alignment: Alignment) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 2) {
            Text(text)
                .font(.caption.weight(.semibold))
            Text(formattedSize(size))
                .font(.system(.caption2, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .foregroundStyle(.primary)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        String(format: "%.2f MB", Double(bytes) / 1_048_576)
    }
}
