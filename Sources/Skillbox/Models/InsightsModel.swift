import Foundation
import Observation
import AppKit

/// State for the footer Insights button. Lives at the App level so the run
/// survives popover dismissal (the user can click Insights, dismiss the popover,
/// and still get the browser report when the subprocess finishes).
@MainActor
@Observable
final class InsightsModel {
    private(set) var isRunning: Bool = false

    /// Called when an error occurs. Wired up by `SkillboxApp` to present an
    /// NSAlert; kept as a closure so the model stays AppKit-free at the type level.
    var presentError: (String) -> Void = { msg in print("Insights error: \(msg)") }

    func run(claudeOverride: String) {
        guard !isRunning else { return }

        switch ClaudeBinaryLocator.resolve(override: claudeOverride) {
        case .resolved(let claudePath):
            isRunning = true
            spawn(claudePath: claudePath)
        case .overrideMissing(let path):
            presentError(InsightsServiceError.overrideMissing(path).errorDescription ?? "binary missing")
        case .notFoundOnPath(let dirs):
            presentError(InsightsServiceError.binaryNotFound(searched: dirs).errorDescription ?? "binary not found")
        }
    }

    private func spawn(claudePath: String) {
        // /insights aggregates from ~/.claude/usage-data/, so cwd is irrelevant.
        let cwd = URL(fileURLWithPath: NSHomeDirectory())
        Task { @MainActor in
            defer { isRunning = false }
            do {
                let result = try await InsightsService.run(
                    claudePath: claudePath,
                    cwd: cwd,
                    onChunk: { _ in }
                )
                if let externalURL = InsightsLinkExtractor.firstExistingHTMLLink(in: result.markdown) {
                    NSWorkspace.shared.open(externalURL)
                    return
                }
                let title = "Skillbox insights — \(formattedNow())"
                let html = MarkdownHTMLRenderer.render(markdown: result.markdown, title: title)
                let url = try InsightsReportWriter.write(html: html)
                NSWorkspace.shared.open(url)
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                presentError(msg)
            }
        }
    }

    private func formattedNow() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date())
    }
}
