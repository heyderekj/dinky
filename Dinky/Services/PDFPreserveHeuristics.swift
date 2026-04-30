import DinkyPDFSignals
import Foundation

/// One qpdf attempt on the preserve path (`extraArgs` append after base `--optimize-images` args).
struct PDFPreserveQpdfStep: Sendable, Equatable {
    let id: String
    let extraArgs: [String]

    static let base = PDFPreserveQpdfStep(id: "base", extraArgs: [])

    static func from(experimental: PDFPreserveExperimentalMode) -> PDFPreserveQpdfStep {
        PDFPreserveQpdfStep(id: "exp_\(experimental.rawValue)", extraArgs: experimental.extraQpdfArgs)
    }

    func extrasWithoutJPEGQuality() -> [String] {
        extraArgs.filter { !$0.hasPrefix("--jpeg-quality=") }
    }
}

/// Ordered qpdf strategies for preserve mode when Smart Quality is on (no manual experimental override).
enum PDFPreserveHeuristics {

    /// Max attempts to keep batch jobs responsive.
    private static let maxSteps = 4

    /// Builds a short chain: base pass, then image- or structure-focused passes from document signals.
    static func qpdfSteps(for s: PDFDocumentSignals) -> [PDFPreserveQpdfStep] {
        let textHeavy = s.totalTextCharsSampled >= 6000
        let imageHeavy = s.totalTextCharsSampled < 2000 && s.bytesPerPage > 100_000

        var steps: [PDFPreserveQpdfStep] = [.base]

        if imageHeavy {
            steps.append(PDFPreserveQpdfStep(id: "jpeg65", extraArgs: ["--jpeg-quality=65"]))
            steps.append(PDFPreserveQpdfStep(id: "jpeg50", extraArgs: ["--jpeg-quality=50"]))
            if !textHeavy {
                steps.append(PDFPreserveQpdfStep(id: "strip_jpeg50", extraArgs: ["--remove-structure", "--jpeg-quality=50"]))
            }
        } else if !textHeavy, s.bytesPerPage < 900_000 {
            steps.append(PDFPreserveQpdfStep(id: "strip", extraArgs: ["--remove-structure"]))
        }

        if steps.count > maxSteps {
            steps = Array(steps.prefix(maxSteps))
        }
        return steps
    }
}

enum PDFPreserveQpdfStepsResolver {

    /// Resolves which qpdf step chain to run. Manual experimental mode replaces the auto chain entirely.
    static func steps(
        sourceURL: URL,
        preserveExperimental: PDFPreserveExperimentalMode,
        smartQuality: Bool
    ) -> [PDFPreserveQpdfStep] {
        if preserveExperimental != .none {
            return [PDFPreserveQpdfStep.from(experimental: preserveExperimental)]
        }
        guard smartQuality, let signals = PDFDocumentSampler.sample(url: sourceURL) else {
            return [.base]
        }
        return PDFPreserveHeuristics.qpdfSteps(for: signals)
    }
}
