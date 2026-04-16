// UpdateChecker.swift — polls GitHub Releases for a newer Dinky.
// Zero dependencies. Pure URLSession + Codable.

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
    func check(manual: Bool = false) async -> CheckResult {
        // Throttle automatic checks to once per 24h.
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        if !manual, last > 0, now - last < throttleSeconds {
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

            // Find the DMG asset (fallback to first asset if somehow not named .dmg).
            let dmg = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
                   ?? release.assets.first

            availableVersion = remote
            releaseURL = URL(string: release.html_url)
            downloadURL = dmg.flatMap { URL(string: $0.browser_download_url) }
            return .updateAvailable(version: remote)
        } catch {
            // Silent failure is intentional for automatic checks. Callers can
            // decide whether to show UI for manual checks.
            return .failed
        }
    }

    // MARK: - In-app install

    /// Downloads the DMG via URLSession (no quarantine added), mounts it,
    /// copies Dinky.app over itself, then relaunches from the new binary.
    func downloadAndInstall() async {
        guard let dmgURL = downloadURL else { return }
        installState = .downloading(progress: 0)

        do {
            // ── 1. Download ───────────────────────────────────────────
            let tempDMG = FileManager.default.temporaryDirectory
                .appendingPathComponent("Dinky-update.dmg")

            let (asyncBytes, response) = try await URLSession.shared.bytes(from: dmgURL)
            let total = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Length")
                .flatMap(Int64.init) ?? 0

            var received: Int64 = 0
            var buffer = Data()
            if total > 0 { buffer.reserveCapacity(Int(total)) }

            for try await byte in asyncBytes {
                buffer.append(byte)
                received += 1
                if total > 0 {
                    installState = .downloading(progress: Double(received) / Double(total))
                }
            }
            try buffer.write(to: tempDMG)

            // ── 2. Mount ──────────────────────────────────────────────
            installState = .installing
            let mountOut = try await shell("/usr/bin/hdiutil",
                                           ["attach", tempDMG.path,
                                            "-nobrowse", "-noautoopen", "-readonly"])

            // hdiutil prints lines like: /dev/diskX  <type>  /Volumes/Name
            guard let mountPoint = mountOut
                .components(separatedBy: "\n")
                .first(where: { $0.contains("/Volumes/") })?
                .components(separatedBy: "\t")
                .last?
                .trimmingCharacters(in: .whitespaces),
                  !mountPoint.isEmpty
            else { throw UpdateError.mountFailed }

            // ── 3. Copy app over itself ───────────────────────────────
            let source = URL(fileURLWithPath: mountPoint).appendingPathComponent("Dinky.app")
            let dest   = Bundle.main.bundleURL  // replace the running app in-place

            // Use shell cp -R so we don't accidentally add quarantine via FM
            try await shell("/bin/cp", ["-Rf", source.path, dest.deletingLastPathComponent().path])

            // ── 4. Detach ─────────────────────────────────────────────
            _ = try? await shell("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
            try? FileManager.default.removeItem(at: tempDMG)

            // ── 5. Relaunch ───────────────────────────────────────────
            // Small delay so this process can finish tearing down cleanly.
            let appPath = dest.path
            Process.launchedProcess(launchPath: "/bin/sh",
                                    arguments: ["-c", "sleep 0.6 && open '\(appPath)'"])
            NSApp.terminate(nil)

        } catch {
            installState = .failed(error.localizedDescription)
        }
    }

    private enum UpdateError: LocalizedError {
        case mountFailed
        var errorDescription: String? { "Couldn't mount the update disk image." }
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
