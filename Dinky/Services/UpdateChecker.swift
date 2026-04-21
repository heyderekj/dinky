// UpdateChecker.swift — polls GitHub Releases for a newer Dinky.
// Zero dependencies. Pure URLSession + Codable.

import AppKit
import Foundation
import SwiftUI

@MainActor
final class UpdateChecker: ObservableObject {

    // MARK: - Published state
    @Published var availableVersion: String? = nil   // nil = up to date or unchecked
    @Published var releaseURL: URL? = nil            // e.g. https://github.com/.../releases/tag/v1.1.0
    @Published var downloadURL: URL? = nil           // direct DMG link
    @Published var isChecking: Bool = false
    @Published var installState: InstallState = .idle

    enum InstallState: Equatable {
        case idle
        case downloading(progress: Double)
        case installing
        case failed(String)
    }

    // MARK: - Configuration
    private let apiURL = URL(string: "https://api.github.com/repos/heyderekj/dinky/releases/latest")!
    private let throttleSeconds: TimeInterval = 60 * 60 * 24   // 24h

    // MARK: - GitHub API shape (only what we need)
    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    // MARK: - Public

    /// Outcome of a check. Only surfaced for manual checks — automatic ones
    /// stay silent so the app never nags the user on launch.
    enum CheckResult {
        case updateAvailable(version: String)
        case upToDate
        case failed
    }

    @discardableResult
    func check(manual: Bool = false, skipThrottle: Bool = false) async -> CheckResult {
        // Throttle background rechecks to once per 24h. Launch and manual checks bypass this.
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        if !manual, !skipThrottle, last > 0, now - last < throttleSeconds {
            return .upToDate
        }

        isChecking = true
        defer { isChecking = false }

        do {
            var request = URLRequest(url: apiURL, timeoutInterval: 10)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Dinky", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            UserDefaults.standard.set(now, forKey: "lastUpdateCheck")

            let remoteTag = release.tag_name
            let remote = stripV(remoteTag)
            let current = currentVersion()

            // Only surface if remote is strictly newer.
            guard compareSemver(remote, current) == .orderedDescending else {
                // Up to date — clear any stale banner state.
                availableVersion = nil
                releaseURL = nil
                downloadURL = nil
                return .upToDate
            }

            // Prefer the zip for in-app install (no hdiutil, no Gatekeeper scan).
            // Fall back to DMG if zip isn't present (older releases).
            let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
                     ?? release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
                     ?? release.assets.first

            availableVersion = remote
            releaseURL = URL(string: release.html_url)
            downloadURL = asset.flatMap { URL(string: $0.browser_download_url) }
            return .updateAvailable(version: remote)
        } catch {
            // Silent failure is intentional for automatic checks. Callers can
            // decide whether to show UI for manual checks.
            return .failed
        }
    }

    // MARK: - In-app install

    /// Downloads the zip via URLSession (no quarantine), unzips with ditto,
    /// then replaces the running bundle **after** this process exits (shell script).
    /// Copying over `Bundle.main.bundleURL` while running hangs — never do that in-process.
    func downloadAndInstall() async {
        guard let assetURL = downloadURL else { return }
        installState = .downloading(progress: 0)

        do {
            // ── 1. Download ───────────────────────────────────────────
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory
            let ext = assetURL.pathExtension.lowercased()
            let tempFile = tmp.appendingPathComponent("Dinky-update.\(ext)")

            let (downloadedURL, _) = try await URLSession.shared.download(from: assetURL)
            _ = try? fm.removeItem(at: tempFile)
            try fm.moveItem(at: downloadedURL, to: tempFile)

            installState = .installing
            let dest = Bundle.main.bundleURL

            let stagedApp: URL
            var cleanupPaths: [String] = [tempFile.path]

            if ext == "zip" {
                let unzipDir = tmp.appendingPathComponent("Dinky-update-extracted")
                _ = try? fm.removeItem(at: unzipDir)
                try await shell("/usr/bin/ditto", ["-xk", tempFile.path, unzipDir.path])
                let source = unzipDir.appendingPathComponent("Dinky.app")
                guard fm.fileExists(atPath: source.path) else {
                    throw UpdateError.missingAppInArchive
                }
                stagedApp = source
                cleanupPaths.append(unzipDir.path)
            } else {
                let mountOut = try await shell(
                    "/usr/bin/hdiutil",
                    ["attach", tempFile.path, "-nobrowse", "-noautoopen", "-readonly"]
                )
                guard let mountPoint = parseHDIMountPoint(from: mountOut) else {
                    throw UpdateError.mountFailed
                }
                let mountedApp = URL(fileURLWithPath: mountPoint).appendingPathComponent("Dinky.app")
                guard fm.fileExists(atPath: mountedApp.path) else {
                    try? await shell("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
                    throw UpdateError.missingAppInArchive
                }
                let stagedCopy = tmp.appendingPathComponent("Dinky-staged-\(UUID().uuidString).app")
                _ = try? fm.removeItem(at: stagedCopy)
                try await shell("/usr/bin/ditto", [mountedApp.path, stagedCopy.path])
                try? await shell("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
                stagedApp = stagedCopy
                cleanupPaths.append(stagedCopy.path)
            }

            try launchDeferredBundleReplace(stagedApp: stagedApp, destination: dest, cleanupPaths: cleanupPaths)

            // Clear the sentinel now so a forced exit below doesn't produce a false crash report.
            DiagnosticsReporter.shared.clearSentinel()

            // Hard-exit fallback: NSApp.terminate's terminateLater reply sometimes
            // never fires when called from a Swift concurrency Task on @MainActor,
            // leaving the app stuck on "Installing…". A background thread guarantees
            // the process exits so the installer script can replace the bundle.
            Thread.detachNewThread {
                Thread.sleep(forTimeInterval: 4)
                exit(0)
            }

            NSApp.terminate(nil)

        } catch {
            installState = .failed(error.localizedDescription)
        }
    }

    /// Writes a shell script that waits for this process to quit, replaces the app bundle, cleans up, and opens the new app.
    private func launchDeferredBundleReplace(stagedApp: URL, destination: URL, cleanupPaths: [String]) throws {
        let fm = FileManager.default
        let scriptURL = fm.temporaryDirectory.appendingPathComponent("dinky-install-\(UUID().uuidString).sh")
        let pid = ProcessInfo.processInfo.processIdentifier
        var lines: [String] = [
            "#!/bin/bash",
            // No set -e: we want open to run even if xattr exits non-zero.
            // Poll until this PID is gone (handles both the fast NSApp.terminate path
            // and the 4-second hard-exit fallback). 10s cap is a safety valve.
            "deadline=$(( $(date +%s) + 10 ))",
            "while kill -0 \(pid) 2>/dev/null && [ $(date +%s) -lt $deadline ]; do sleep 0.2; done",
            "rm -rf \(bashSingleQuotedPath(destination.path)) || exit 1",
            "/usr/bin/ditto \(bashSingleQuotedPath(stagedApp.path)) \(bashSingleQuotedPath(destination.path)) || exit 1",
            // Strip quarantine so Gatekeeper doesn't block the freshly-written bundle.
            "/usr/bin/xattr -rd com.apple.quarantine \(bashSingleQuotedPath(destination.path)) 2>/dev/null || true",
        ]
        for p in cleanupPaths {
            lines.append("rm -rf \(bashSingleQuotedPath(p))")
        }
        // -n forces a new instance rather than connecting to any stale Launch Services entry.
        lines.append("/usr/bin/open -n \(bashSingleQuotedPath(destination.path))")
        try lines.joined(separator: "\n").write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: scriptURL.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptURL.path]
        try proc.run()
    }

    private func bashSingleQuotedPath(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func parseHDIMountPoint(from mountOut: String) -> String? {
        guard let line = mountOut
            .components(separatedBy: "\n")
            .first(where: { $0.contains("/Volumes/") })?
            .components(separatedBy: "\t")
            .last
        else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum UpdateError: LocalizedError {
        case mountFailed
        case missingAppInArchive
        var errorDescription: String? {
            switch self {
            case .mountFailed:
                return String(localized: "Couldn't mount the update disk image.", comment: "In-app updater error.")
            case .missingAppInArchive:
                return String(localized: "The update didn’t contain Dinky.app.", comment: "In-app updater error.")
            }
        }
    }

    @discardableResult
    private func shell(_ path: String, _ args: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError  = pipe
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                let msg = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? "exit \(p.terminationStatus)"
                throw NSError(domain: "DinkyUpdater", code: Int(p.terminationStatus),
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                          encoding: .utf8) ?? ""
        }.value
    }

    /// Dismiss the current banner for this version. Persists so it won't reappear
    /// until a strictly newer version is published.
    func dismissCurrent() {
        guard let v = availableVersion else { return }
        UserDefaults.standard.set(v, forKey: "dismissedUpdateVersion")
        availableVersion = nil
    }

    /// Whether the UI should show the banner (respects dismissed-version pref).
    func shouldShow(dismissedVersion: String) -> Bool {
        guard let v = availableVersion, !v.isEmpty else { return false }
        if dismissedVersion.isEmpty { return true }
        // Show if a newer version has shipped than the one the user dismissed.
        return compareSemver(v, dismissedVersion) == .orderedDescending
    }

    // MARK: - Version helpers

    private func currentVersion() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return stripV(v)
    }

    private func stripV(_ s: String) -> String {
        var s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// Compare semver-ish strings like "1.2.0" / "1.10.3". Non-numeric components
    /// are treated as 0, so pre-release suffixes lose to plain versions — fine for us.
    private func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
        let ap = a.split(separator: ".").map { Int($0) ?? 0 }
        let bp = b.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(ap.count, bp.count)
        for i in 0..<count {
            let x = i < ap.count ? ap[i] : 0
            let y = i < bp.count ? bp[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }
}
