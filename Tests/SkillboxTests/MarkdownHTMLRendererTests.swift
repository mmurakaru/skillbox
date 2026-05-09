import Testing
import Foundation
@testable import Skillbox

struct MarkdownHTMLRendererTests {
    private func render(_ md: String) -> String {
        MarkdownHTMLRenderer.render(markdown: md, title: "test")
    }

    @Test func emitsCompleteDocumentSkeleton() {
        let html = render("hello")
        #expect(html.contains("<!doctype html>"))
        #expect(html.contains("<html lang=\"en\">"))
        #expect(html.contains("<title>test</title>"))
        #expect(html.contains("<article class=\"markdown-body\">"))
        #expect(html.contains("</article>"))
    }

    @Test func rendersHeading() {
        let html = render("# Hello")
        #expect(html.contains("<h1>Hello</h1>"))
    }

    @Test func rendersHeadingLevels() {
        let html = render("## Two\n\n### Three")
        #expect(html.contains("<h2>Two</h2>"))
        #expect(html.contains("<h3>Three</h3>"))
    }

    @Test func rendersParagraph() {
        let html = render("plain paragraph")
        #expect(html.contains("<p>plain paragraph</p>"))
    }

    @Test func rendersStrongAndEmphasis() {
        let html = render("**bold** and *italic*")
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<em>italic</em>"))
    }

    @Test func rendersInlineCode() {
        let html = render("use `npm install`")
        #expect(html.contains("<code>npm install</code>"))
    }

    @Test func rendersFencedCodeBlockWithLanguage() {
        let html = render("```swift\nlet x = 1\n```")
        #expect(html.contains("<pre><code class=\"language-swift\">"))
        #expect(html.contains("let x = 1"))
        #expect(html.contains("</code></pre>"))
    }

    @Test func rendersUnorderedList() {
        let html = render("- a\n- b\n- c")
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>a</li>"))
        #expect(html.contains("<li>b</li>"))
        #expect(html.contains("</ul>"))
    }

    @Test func rendersOrderedList() {
        let html = render("1. one\n2. two")
        #expect(html.contains("<ol>"))
        #expect(html.contains("<li>one</li>"))
        #expect(html.contains("<li>two</li>"))
    }

    @Test func rendersLink() {
        let html = render("[home](https://example.com)")
        #expect(html.contains("<a href=\"https://example.com\">home</a>"))
    }

    @Test func rendersBlockquote() {
        let html = render("> wisdom")
        #expect(html.contains("<blockquote>"))
        #expect(html.contains("wisdom"))
        #expect(html.contains("</blockquote>"))
    }

    @Test func rendersThematicBreak() {
        let html = render("alpha\n\n---\n\nbeta")
        #expect(html.contains("<hr>"))
    }

    @Test func escapesHTMLSpecialCharsInText() {
        let html = render("a < b & c > d")
        #expect(html.contains("a &lt; b &amp; c &gt; d"))
    }

    @Test func escapesAttributeContents() {
        let html = render("[\"q\"](https://example.com/?x=1&y=2)")
        // Ampersand escaped in URL attribute.
        #expect(html.contains("&amp;y=2"))
    }

    @Test func rendersTable() {
        let html = render("""
        | Col A | Col B |
        | --- | --- |
        | 1 | 2 |
        | 3 | 4 |
        """)
        #expect(html.contains("<table>"))
        #expect(html.contains("<th>Col A</th>"))
        #expect(html.contains("<td>1</td>"))
        #expect(html.contains("<td>4</td>"))
    }
}
