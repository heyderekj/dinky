import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The menu bar panel: a header with what Dinky is doing, quick ways to compress, the latest
/// results (drag one out, or click to show it in Finder), then the usual app rows. Rows look and
/// behave like Tahoe menu items, the same as Slinky's.
struct MenuBarPanel: View {
    @ObservedObject var vm: ContentViewModel
    @EnvironmentObject var prefs: DinkyPreferences
    let close: () -> Void

    private static let recentLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, 12)
            VStack(spacing: 2) {
                MenuRow(icon: "plus.rectangle.on.folder", title: ShortcutAction.openFiles.title,
                        shortcut: prefs.shortcut(for: .openFiles).displayString) {
                    close()
                    DockPresenceManager.showMainWindow {
                        NotificationCenter.default.post(name: .dinkyOpenPanel, object: nil)
                    }
                }
                MenuRow(icon: "doc.on.clipboard", title: ShortcutAction.pasteClipboard.title,
                        shortcut: prefs.pasteClipboardGlobalEnabled ? prefs.shortcut(for: .pasteClipboard).displayString : nil) {
                    close()
                    (NSApp.delegate as? AppDelegate)?.compressFromClipboard(nil)
                }
                MenuRow(icon: "rectangle.dashed.and.arrow.up.forward", title: String(localized: "Floating dropzone", comment: "Settings UI."),
                        checked: prefs.floatingDropzoneEnabled) {
                    prefs.floatingDropzoneEnabled.toggle()
                    NotificationCenter.default.post(name: .dinkyFloatingDropzoneChanged, object: nil)
                }
            }
            .padding(6)

            if !recent.isEmpty {
                Divider().padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Recently compressed", comment: "Menu bar panel: section title for latest results."))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                    ForEach(recent) { item in
                        RecentResultRow(item: item) {
                            close()
                            NSWorkspace.shared.activateFileViewerSelecting([item.outputURL ?? item.sourceURL])
                        }
                    }
                }
                .padding(6)
            }

            Divider().padding(.horizontal, 12)
            VStack(spacing: 2) {
                MenuRow(icon: "macwindow", title: String(localized: "Open Dinky", comment: "Menu bar item: show the main window.")) {
                    close()
                    DockPresenceManager.showMainWindow()
                }
                MenuRow(icon: "gearshape", title: String(localized: "Settings…", comment: "Menu bar item: open settings."), shortcut: "⌘,") {
                    close()
                    DockPresenceManager.showSettings()
                }
                MenuRow(icon: "info.circle", title: String(localized: "About Dinky", comment: "Application menu: about panel.")) {
                    close()
                    showAboutPanel()
                }
                MenuRow(icon: "power", title: String(localized: "Quit Dinky", comment: "Menu bar item: quit the app."), shortcut: "⌘Q") {
                    NSApp.terminate(nil)
                }
            }
            .padding(6)
        }
        .frame(width: 300)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Dinky", comment: "Menu bar item accessibility label.")).font(.headline)
                HStack(spacing: 5) {
                    Circle()
                        .fill(vm.isProcessing
                              ? AnyShapeStyle(LinearGradient(colors: DropZoneStyle.gradientColors, startPoint: .leading, endPoint: .trailing))
                              : AnyShapeStyle(Color.secondary))
                        .frame(width: 6, height: 6)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            Spacer()
            if vm.isProcessing {
                Button {
                    vm.stopCompression()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Stop", comment: "Bottom bar: cancel in-flight compression."))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var status: String {
        if vm.isProcessing {
            let left = vm.items.filter { !$0.status.isTerminal }.count
            return String.localizedStringWithFormat(
                String(localized: "Compressing… %lld to go", comment: "Menu bar panel status; argument is how many files are left."),
                Int64(left)
            )
        }
        if prefs.lifetimeSavedBytes > 0 {
            return String.localizedStringWithFormat(
                String(localized: "%@ saved so far", comment: "Menu bar panel status; argument is a size like 1.2 GB."),
                ByteCountFormatter.string(fromByteCount: prefs.lifetimeSavedBytes, countStyle: .file)
            )
        }
        return String(localized: "Ready", comment: "Menu bar panel status: idle.")
    }

    private var recent: [CompressionItem] {
        Array(vm.items.filter { $0.outputURL != nil }.suffix(Self.recentLimit).reversed())
    }
}

/// A row that looks and behaves like a Tahoe menu item: icon, title, shortcut or check, highlight on hover.
private struct MenuRow: View {
    let icon: String
    let title: String
    var shortcut: String?
    var checked: Bool?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(hovering ? Color.white : Color.secondary)
                Text(title)
                Spacer()
                if let checked {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .opacity(checked ? 1 : 0)
                        .accessibilityHidden(!checked)
                } else if let shortcut {
                    Text(shortcut).foregroundStyle(hovering ? Color.white.opacity(0.75) : Color.secondary)
                }
            }
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(hovering ? Color.accentColor : .clear, in: .rect(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(checked == true ? .isSelected : [])
    }
}

/// One finished file: its icon, name and how much smaller it got. Drag it straight into another
/// app, or click to show it in Finder.
private struct RecentResultRow: View {
    @ObservedObject var item: CompressionItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let url = item.outputURL ?? item.sourceURL
        Button(action: action) {
            HStack(spacing: 9) {
                Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .data))
                    .resizable()
                    .frame(width: 22, height: 22)
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if item.savedPercent > 0 {
                    Text("−\(Int(item.savedPercent.rounded()))%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(hovering ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(hovering ? Color.accentColor : .clear, in: .rect(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .help(String(localized: "Drag to use it, click to show in Finder", comment: "Floating dropzone: result row tooltip."))
    }
}
