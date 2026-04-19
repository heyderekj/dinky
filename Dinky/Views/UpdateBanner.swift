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
                        Text(String(localized: "Dinky ", comment: "Update banner before version number.")).foregroundStyle(.secondary)
                        Text("v\(updater.availableVersion ?? "")").fontWeight(.semibold)
                        Text(String(localized: " is available", comment: "Update banner after version number.")).foregroundStyle(.secondary)
                    }
                case .downloading:
                    Text(String(localized: "Downloading…", comment: "Update banner status."))
                        .foregroundStyle(.secondary)
                case .installing:
                    Text(String(localized: "Installing…", comment: "Update banner status.")).foregroundStyle(.secondary)
                case .failed(let msg):
                    Text(String(localized: "Update failed: \(msg)", comment: "Update banner error; argument is message."))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.caption)

            Spacer(minLength: 8)

            // Action buttons — only shown when idle or failed
            if case .idle = updater.installState {
                Button(String(localized: "Loving Dinky? Leave a review", comment: "Update banner: link to GitHub Discussions reviews.")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/heyderekj/dinky/discussions/new?category=reviews")!)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .underline()

                if let release = updater.releaseURL {
                    Button(String(localized: "What’s new", comment: "Update banner link to release notes.")) { NSWorkspace.shared.open(release) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .underline()
                }

                Button {
                    if itemCount > 0 {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "Install update now?", comment: "Alert when installing with queued files.")
                        alert.informativeText = String(localized: "Your current results will be cleared when Dinky relaunches.", comment: "Alert detail for install with queue.")
                        alert.addButton(withTitle: String(localized: "Install", comment: "Alert confirm button."))
                        alert.addButton(withTitle: String(localized: "Cancel", comment: "Alert cancel button."))
                        guard alert.runModal() == .alertFirstButtonReturn else { return }
                    }
                    Task { await updater.downloadAndInstall() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .imageScale(.small)
                        Text(String(localized: "Install Update", comment: "Update banner primary button."))
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
                        Text(String(localized: "Retry", comment: "Update banner after failure."))
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
                .help(String(localized: "Dismiss", comment: "Tooltip for dismiss update banner."))
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
