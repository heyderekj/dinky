// UpdateBanner.swift — slim banner surfaced at the top of the window
// when UpdateChecker finds a newer release on GitHub.

import SwiftUI
import AppKit

struct UpdateBanner: View {
    @ObservedObject var updater: UpdateChecker
    @EnvironmentObject var prefs: DinkyPreferences
    var itemCount: Int = 0

    var body: some View {
        HStack(spacing: 10) {
            // Icon — spinner while working, arrow otherwise
            Group {
                switch updater.installState {
                case .downloading, .installing:
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                default:
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 14, weight: .semibold))
                }
            }

            // Status text
            Group {
                switch updater.installState {
                case .idle:
                    HStack(spacing: 0) {
                        Text("Dinky ").foregroundStyle(.secondary)
                        Text("v\(updater.availableVersion ?? "")").fontWeight(.semibold)
                        Text(" is available").foregroundStyle(.secondary)
                    }
                case .downloading:
                    Text("Downloading…")
                        .foregroundStyle(.secondary)
                case .installing:
                    Text("Installing…").foregroundStyle(.secondary)
                case .failed(let msg):
                    Text("Update failed: \(msg)")
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.caption)

            Spacer(minLength: 8)

            // Action buttons — only shown when idle or failed
            if case .idle = updater.installState {
                if let release = updater.releaseURL {
                    Button("What's new") { NSWorkspace.shared.open(release) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .underline()
                }

                Button {
                    if itemCount > 0 {
                        let alert = NSAlert()
                        alert.messageText = "Install update now?"
                        alert.informativeText = "Your current results will be cleared when Dinky relaunches."
                        alert.addButton(withTitle: "Install")
                        alert.addButton(withTitle: "Cancel")
                        guard alert.runModal() == .alertFirstButtonReturn else { return }
                    }
                    Task { await updater.downloadAndInstall() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .imageScale(.small)
                        Text("Install Update")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor))
                }
                .buttonStyle(.plain)
            }

            if case .failed = updater.installState {
                Button {
                    Task { await updater.downloadAndInstall() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .imageScale(.small)
                        Text("Retry")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor))
                }
                .buttonStyle(.plain)
            }

            // Dismiss — hidden while install is in progress
            if case .downloading = updater.installState { } else if case .installing = updater.installState { } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        updater.installState = .idle
                        prefs.dismissedUpdateVersion = updater.availableVersion ?? ""
                        updater.dismissCurrent()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal:   .move(edge: .top).combined(with: .opacity)
        ))
    }
}
