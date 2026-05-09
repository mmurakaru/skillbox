import Foundation

/// Extracts a `file://…html` link from the markdown that `/insights` returns.
///
/// The /insights skill in Claude Code may write its own polished HTML report to
/// disk and return only a brief "see file://…" notice. When that's the case,
/// skillbox should open the real report rather than rendering the notice itself.
enum InsightsLinkExtractor {
    /// Returns the first `file://*.html` URL in the markdown that resolves to an
    /// existing file on disk. Returns nil if none exist.
    static func firstExistingHTMLLink(in markdown: String) -> URL? {
        for candidate in candidateURLs(in: markdown) {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Pure parsing - exposed for tests. Returns every `file://...` URL ending in
    /// `.html` or `.htm` found in the markdown, in order of appearance, decoded.
    static func candidateURLs(in markdown: String) -> [URL] {
        // Allow most URL chars; stop at whitespace, backticks, common bracket/quote
        // characters that wrap markdown links.
        guard let regex = try? NSRegularExpression(
            pattern: #"file://[^\s)\]'"`<>]+\.html?"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let nsRange = NSRange(markdown.startIndex..., in: markdown)
        let matches = regex.matches(in: markdown, range: nsRange)
        var seen: Set<String> = []
        var urls: [URL] = []
        for match in matches {
            guard let range = Range(match.range, in: markdown) else { continue }
            var raw = String(markdown[range])
            // Trim trailing punctuation that often follows a URL in prose.
            while let last = raw.last, ".,!?;:".contains(last) {
                raw.removeLast()
            }
            guard !seen.contains(raw) else { continue }
            seen.insert(raw)
            if let url = URL(string: raw) {
                urls.append(url)
            } else if let decoded = raw.removingPercentEncoding,
                      let url = URL(string: decoded) {
                urls.append(url)
            }
        }
        return urls
    }
}
