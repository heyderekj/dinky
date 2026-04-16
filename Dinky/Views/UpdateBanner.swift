// UpdateBanner.swift — slim banner surfaced at the top of the window
// when UpdateChecker finds a newer release on GitHub.

import SwiftUI
import AppKit

struct UpdateBanner: View {
    @ObservedObject var updater: UpdateChecker
    @EnvironmentObject var prefs: DinkyPreferences

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 0) {
                Text("Dinky ")
                    .foregroundStyle(.secondary)
                Text("v\(updater.availableVersion ?? "")")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(" is available")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Spacer(minLength: 8)

            if let release = updater.releaseURL {
                Button("What's new") {
                    NSWorkspace.shared.open(release)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .underline()
            }

            if let dmg = updater.downloadURL {
                Button {
                    NSWorkspace.shared.open(dmg)
                } label: {
                    Text("Download")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal:   .move(edge: .top).combined(with: .opacity)
        ))
    }
}
