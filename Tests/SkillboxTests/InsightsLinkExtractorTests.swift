import Testing
import Foundation
@testable import Skillbox

struct InsightsLinkExtractorTests {
    @Test func candidates_emptyMarkdown_returnsEmpty() {
        #expect(InsightsLinkExtractor.candidateURLs(in: "").isEmpty)
    }

    @Test func candidates_noFileURL_returnsEmpty() {
        let md = "Just some prose with [a link](https://example.com)."
        #expect(InsightsLinkExtractor.candidateURLs(in: md).isEmpty)
    }

    @Test func candidates_findsBareFileURL() {
        let md = "Your shareable insights report is ready: file:///Users/me/report.html"
        let urls = InsightsLinkExtractor.candidateURLs(in: md)
        #expect(urls.count == 1)
        #expect(urls.first?.path == "/Users/me/report.html")
    }

    @Test func candidates_stripsTrailingPunctuation() {
        let md = "See file:///Users/me/report.html."
        let urls = InsightsLinkExtractor.candidateURLs(in: md)
        #expect(urls.first?.path == "/Users/me/report.html")
    }

    @Test func candidates_handlesMarkdownLinkSyntax() {
        let md = "Open [the report](file:///Users/me/report.html) for details."
        let urls = InsightsLinkExtractor.candidateURLs(in: md)
        #expect(urls.first?.path == "/Users/me/report.html")
    }

    @Test func candidates_supportsHtmExtension() {
        let md = "old: file:///tmp/legacy.htm"
        let urls = InsightsLinkExtractor.candidateURLs(in: md)
        #expect(urls.first?.lastPathComponent == "legacy.htm")
    }

    @Test func candidates_dedupesIdenticalURLs() {
        let md = "twice: file:///x.html and again file:///x.html"
        #expect(InsightsLinkExtractor.candidateURLs(in: md).count == 1)
    }

    @Test func candidates_capturesMultiple() {
        let md = """
        First: file:///a.html
        Second: file:///b.html
        """
        let urls = InsightsLinkExtractor.candidateURLs(in: md).map(\.lastPathComponent)
        #expect(urls == ["a.html", "b.html"])
    }

    @Test func firstExisting_returnsNilWhenNothingExistsOnDisk() {
        let md = "see file:///definitely/does/not/exist-\(UUID().uuidString).html"
        #expect(InsightsLinkExtractor.firstExistingHTMLLink(in: md) == nil)
    }

    @Test func firstExisting_returnsURLWhenFileExists() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-link-\(UUID().uuidString).html")
        try "<html></html>".write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let md = "report at \(temp.absoluteString)"
        let url = InsightsLinkExtractor.firstExistingHTMLLink(in: md)
        #expect(url?.path == temp.path)
    }

    @Test func firstExisting_skipsMissingFilesAndReturnsFirstExisting() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-link-real-\(UUID().uuidString).html")
        try "<html></html>".write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let md = """
        first: file:///nope-\(UUID().uuidString).html
        second: \(temp.absoluteString)
        """
        let url = InsightsLinkExtractor.firstExistingHTMLLink(in: md)
        #expect(url?.path == temp.path)
    }
}
