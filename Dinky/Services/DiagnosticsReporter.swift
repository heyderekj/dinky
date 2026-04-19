import AppKit
import Combine
import Foundation
import MetricKit

// MARK: - Crash report model

/// Shown after an unclean exit and/or when MetricKit delivers crash diagnostics.
struct CrashReport: Identifiable, Equatable {
    let id = UUID()
    var subtitle: String
    var metricKitSummary: String?
}

// MARK: - Reporter

/// Crash sentinel + MetricKit subscriber + pre-filled `mailto:` / GitHub issue URLs.
@MainActor
final class DiagnosticsReporter: NSObject, ObservableObject {
    static let shared = DiagnosticsReporter()

    @Published var pendingCrashReport: CrashReport?

    private var monitoringStarted = false
    private var metricKitSubscribed = false

    private static let sentinelName = ".crash_sentinel"
    private static let diagnosticsFileName = "diagnostics.json"
    private static let crashReportingEnabledKey = "crashReportingEnabled"

    private var appSupportDinkyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dinky", isDirectory: true)
    }

    private var sentinelURL: URL {
        appSupportDinkyURL.appendingPathComponent(Self.sentinelName)
    }

    private var diagnosticsJSONURL: URL {
        appSupportDinkyURL.appendingPathComponent(Self.diagnosticsFileName)
    }

    func startMonitoring() {
        guard !monitoringStarted else { return }
        monitoringStarted = true

        try? FileManager.default.createDirectory(at: appSupportDinkyURL, withIntermediateDirectories: true)

        let hadSentinel = FileManager.default.fileExists(atPath: sentinelURL.path)
        if hadSentinel {
            let subtitle = String(localized: "The previous session ended unexpectedly. Nothing is uploaded automatically — choose an option below if you’d like to share details.", comment: "Post-crash prompt subtitle after unclean quit.")
            pendingCrashReport = CrashReport(subtitle: subtitle, metricKitSummary: nil)
        }

        FileManager.default.createFile(atPath: sentinelURL.path, contents: Data(), attributes: nil)

        applyCrashReportingPreference()
    }

    func clearSentinel() {
        try? FileManager.default.removeItem(at: sentinelURL)
    }

    func dismissPendingReport() {
        pendingCrashReport = nil
    }

    /// Whether the in-app opt-in for MetricKit crash diagnostics is on. Reads `UserDefaults`
    /// directly so this reporter doesn't depend on the `DinkyPreferences` instance lifecycle.
    var isCrashReportingEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.crashReportingEnabledKey)
    }

    /// Subscribe / unsubscribe from MetricKit to match the user's in-app opt-in.
    /// Safe to call repeatedly — the actual `add`/`remove` only fires when state changes.
    func applyCrashReportingPreference() {
        let shouldSubscribe = isCrashReportingEnabled
        if shouldSubscribe, !metricKitSubscribed {
            MXMetricManager.shared.add(self)
            metricKitSubscribed = true
        } else if !shouldSubscribe, metricKitSubscribed {
            MXMetricManager.shared.remove(self)
            metricKitSubscribed = false
        }
    }

    // MARK: - Post-crash URLs (uses pending report context)

    func postCrashEmailURL() -> URL {
        var extra = ""
        if let s = pendingCrashReport?.metricKitSummary, !s.isEmpty {
            extra = String(localized: "## Apple diagnostic summary\n\n\(s)\n\n", comment: "Email body: Markdown heading and MetricKit crash text. Argument is diagnostic dump.")
        }
        return Self.emailURL(subject: String(localized: "Crash report — Dinky", comment: "Email subject for crash report."), extraBody: extra)
    }

    func postCrashGitHubURL() -> URL {
        var extra = ""
        if let s = pendingCrashReport?.metricKitSummary, !s.isEmpty {
            extra = String(localized: "## Apple diagnostic summary\n\n\(s)\n\n", comment: "GitHub issue body: Markdown heading and MetricKit crash text. Argument is diagnostic dump.")
        }
        return Self.githubIssueURL(title: String(localized: "Crash — Dinky", comment: "GitHub issue title for crash report."), extraBody: extra)
    }

    // MARK: - Shared diagnostic text + URL builders

    /// Shared context for mail and GitHub pre-fill (version, OS, date).
    static func diagnosticContextBlock() -> String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let date = ISO8601DateFormatter().string(from: Date())
        return """
        App: Dinky v\(ver) (build \(build))
        macOS: \(osString)
        Date: \(date)


        """
    }

    /// Pre-filled email to support. `extraBody` is appended after the diagnostic block.
    static func emailURL(subject: String, extraBody: String = "") -> URL {
        let body = diagnosticContextBlock() + extraBody
        guard var components = URLComponents(string: "mailto:\(S.supportEmail)") else {
            return URL(string: "mailto:\(S.supportEmail)")!
        }
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url ?? URL(string: "mailto:\(S.supportEmail)")!
    }

    /// Pre-filled new GitHub issue. `extraBody` is appended after a short template.
    static func githubIssueURL(title: String, extraBody: String = "") -> URL {
        let body =
            diagnosticContextBlock()
            + "## What happened\n\n"
            + extraBody
            + "\n\n## Steps to reproduce\n\n1. \n\n"
        var components = URLComponents(string: "https://github.com/heyderekj/dinky/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url ?? URL(string: "https://github.com/heyderekj/dinky/issues/new")!
    }

    // MARK: - MetricKit payloads

    private func ingestDiagnosticPayloads(_ payloads: [MXDiagnosticPayload]) {
        savePayloadsJSON(payloads)

        var crashSummaries: [String] = []
        for payload in payloads {
            guard let crashes = payload.crashDiagnostics else { continue }
            for c in crashes {
                crashSummaries.append(summarizeCrashDiagnostic(c))
            }
        }
        guard !crashSummaries.isEmpty else { return }

        let combined = crashSummaries.joined(separator: "\n\n---\n\n")

        if var report = pendingCrashReport {
            report.metricKitSummary = combined
            pendingCrashReport = report
        } else {
            pendingCrashReport = CrashReport(
                subtitle: String(localized: "Crash diagnostics from Apple are available for this device. Nothing was sent automatically — use the buttons below if you want to share them.", comment: "Post-crash prompt when MetricKit data arrives."),
                metricKitSummary: combined
            )
        }
    }

    private func summarizeCrashDiagnostic(_ diagnostic: MXCrashDiagnostic) -> String {
        let data = diagnostic.callStackTree.jsonRepresentation()
        if let s = String(data: data, encoding: .utf8) {
            let truncated = String(s.prefix(8000))
            return String(localized: "Call stack tree (JSON, truncated):\n\(truncated)", comment: "MetricKit crash export header plus JSON; keep newline.")
        }
        return String(describing: diagnostic)
    }

    private func savePayloadsJSON(_ payloads: [MXDiagnosticPayload]) {
        var root: [[String: Any]] = []
        let fmt = ISO8601DateFormatter()
        for p in payloads {
            var dict: [String: Any] = [
                "timeStampBegin": fmt.string(from: p.timeStampBegin),
                "timeStampEnd": fmt.string(from: p.timeStampEnd),
            ]
            if let crashes = p.crashDiagnostics {
                dict["crashDiagnosticsCount"] = crashes.count
            }
            root.append(dict)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: diagnosticsJSONURL, options: .atomic)
    }
}

// MARK: - MXMetricManagerSubscriber

extension DiagnosticsReporter: MXMetricManagerSubscriber {
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Task { @MainActor in
            self.ingestDiagnosticPayloads(payloads)
        }
    }
}
