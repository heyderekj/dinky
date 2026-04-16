import SwiftUI

struct ResultsRowView: View {
    @ObservedObject var item: ImageItem
    @State private var showingError = false

    var body: some View {
        HStack(spacing: 12) {
            FileTypeIcon(ext: item.sourceURL.pathExtension)

            HStack(spacing: 6) {
                Text(item.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let type = item.detectedContentType {
                    contentTypeChip(type)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.2), value: item.detectedContentType)

            sizeInfo
            statusChip
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .sheet(isPresented: $showingError) {
            if case .failed(let error) = item.status {
                ErrorDetailView(filename: item.filename, error: error)
            }
        }
    }

    // MARK: Size diff

    @ViewBuilder
    private var sizeInfo: some View {
        switch item.status {
        case .done(_, let orig, let out):
            HStack(spacing: 5) {
                Text(bytes(orig))
                Image(systemName: "arrow.right")
                    .imageScale(.small)
                Text(bytes(out))
                    .fontWeight(.medium)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)

        default:
            Text(bytes(item.originalSize))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Status chip

    @ViewBuilder
    private var statusChip: some View {
        switch item.status {
        case .pending:
            chip("Queued", color: .secondary.opacity(0.35), fg: .primary)

        case .processing:
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.65)
                Text("Working")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .done(let outputURL, _, _):
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } label: {
                Text("Show in Finder")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)

        case .skipped:
            chip("Skipped", color: .secondary.opacity(0.35), fg: .primary)

        case .zeroGain:
            chip("No gain", color: .secondary.opacity(0.35), fg: .primary)

        case .failed:
            Button { showingError = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .imageScale(.small)
                    Text("Error")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.red.opacity(0.75)))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Chip styles

    private func chip(_ label: String, color: Color, fg: Color) -> some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color))
    }

    // Small, muted chip shown next to the filename when Smart Quality is on.
    // It's secondary info — colors are soft so the row's primary content still leads.
    @ViewBuilder
    private func contentTypeChip(_ type: ContentType) -> some View {
        let (bg, fg): (Color, Color) = {
            switch type {
            case .photo: return (Color.orange.opacity(0.14), Color.orange)
            case .ui:    return (Color.blue.opacity(0.14),   Color.blue)
            case .mixed: return (Color.secondary.opacity(0.18), Color.secondary)
            }
        }()
        Text(type.label)
            .font(.system(size: 9, weight: .semibold).lowercaseSmallCaps())
            .foregroundStyle(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(bg)
            )
    }

private func bytes(_ n: Int64) -> String {
        String(format: "%.2f MB", Double(n) / 1_048_576)
    }
}

// MARK: - File type icon

private struct FileTypeIcon: View {
    let ext: String

    private var label: String { ext.uppercased() }

    private var color: Color {
        switch ext.lowercased() {
        case "jpg", "jpeg": return Color(red: 0.96, green: 0.42, blue: 0.28) // orange — theme 2
        case "png":         return Color(red: 0.28, green: 0.56, blue: 1.00) // blue   — theme 1
        case "tiff":        return Color(red: 0.18, green: 0.78, blue: 0.52) // green  — theme 3
        case "bmp":         return Color(red: 0.96, green: 0.30, blue: 0.54) // pink   — theme 4
        case "webp", "avif": return Color.secondary
        default:             return Color.secondary
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color.opacity(0.15))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(color.opacity(0.30), lineWidth: 0.5)
            Text(label)
                .font(.system(size: label.count > 3 ? 6 : 7, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(width: 28, height: 24)
    }
}

// MARK: - Error detail sheet

private struct ErrorDetailView: View {
    let filename: String
    let error: Error
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red)
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Compression Failed")
                        .font(.headline)
                    Text(filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Error message
            ScrollView {
                Text(error.localizedDescription)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)

            Divider()

            // Footer
            HStack {
                Text("Tip: check that cwebp / avifenc are present in the app bundle.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Dismiss") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420)
        .background(.ultraThinMaterial)
    }
}
