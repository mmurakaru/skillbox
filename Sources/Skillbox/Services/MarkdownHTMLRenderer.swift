import Foundation
import Markdown

/// Converts a Markdown string into a self-contained HTML document with
/// inlined GitHub-flavored CSS. No external network requests.
enum MarkdownHTMLRenderer {
    static func render(markdown: String, title: String) -> String {
        let document = Document(parsing: markdown)
        var visitor = HTMLVisitor()
        let body = visitor.render(document)
        return template(title: htmlEscape(title), body: body)
    }

    // MARK: - Template

    private static func template(title: String, body: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>
        \(githubCSS)
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    private static let githubCSS: String = """
    :root {
      --bg: #ffffff;
      --fg: #1f2328;
      --muted: #59636e;
      --border: #d1d9e0;
      --code-bg: #f6f8fa;
      --link: #0969da;
      --quote-border: #d1d9e0;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0d1117;
        --fg: #e6edf3;
        --muted: #9198a1;
        --border: #30363d;
        --code-bg: #151b23;
        --link: #4493f8;
        --quote-border: #3d444d;
      }
    }
    html { background: var(--bg); }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", Arial, sans-serif;
      color: var(--fg);
      background: var(--bg);
      margin: 0;
      padding: 0;
      line-height: 1.6;
    }
    .markdown-body {
      max-width: 880px;
      margin: 0 auto;
      padding: 48px 32px 96px;
      font-size: 16px;
    }
    .markdown-body h1, .markdown-body h2, .markdown-body h3,
    .markdown-body h4, .markdown-body h5, .markdown-body h6 {
      margin-top: 1.6em;
      margin-bottom: 0.6em;
      font-weight: 600;
      line-height: 1.25;
    }
    .markdown-body h1 { font-size: 2em; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
    .markdown-body h2 { font-size: 1.5em; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
    .markdown-body h3 { font-size: 1.25em; }
    .markdown-body h4 { font-size: 1em; }
    .markdown-body h5 { font-size: 0.875em; }
    .markdown-body h6 { font-size: 0.85em; color: var(--muted); }
    .markdown-body p { margin: 0 0 1em; }
    .markdown-body a { color: var(--link); text-decoration: none; }
    .markdown-body a:hover { text-decoration: underline; }
    .markdown-body strong { font-weight: 600; }
    .markdown-body em { font-style: italic; }
    .markdown-body ul, .markdown-body ol { margin: 0 0 1em; padding-left: 2em; }
    .markdown-body li { margin: 0.25em 0; }
    .markdown-body li > p { margin: 0.5em 0; }
    .markdown-body blockquote {
      margin: 0 0 1em;
      padding: 0 1em;
      color: var(--muted);
      border-left: 4px solid var(--quote-border);
    }
    .markdown-body code {
      font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
      font-size: 0.9em;
      padding: 0.2em 0.4em;
      background: var(--code-bg);
      border-radius: 4px;
    }
    .markdown-body pre {
      background: var(--code-bg);
      padding: 14px 16px;
      border-radius: 8px;
      overflow: auto;
      margin: 0 0 1em;
      line-height: 1.45;
    }
    .markdown-body pre code {
      padding: 0;
      background: transparent;
      font-size: 0.875em;
      white-space: pre;
    }
    .markdown-body hr {
      height: 1px;
      background: var(--border);
      border: 0;
      margin: 1.5em 0;
    }
    .markdown-body table {
      border-collapse: collapse;
      margin: 0 0 1em;
      width: 100%;
    }
    .markdown-body th, .markdown-body td {
      border: 1px solid var(--border);
      padding: 6px 12px;
      text-align: left;
    }
    .markdown-body th {
      background: var(--code-bg);
      font-weight: 600;
    }
    .markdown-body img { max-width: 100%; height: auto; }
    """

    // MARK: - HTML escape

    fileprivate static func htmlEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out.append("&amp;")
            case "<": out.append("&lt;")
            case ">": out.append("&gt;")
            case "\"": out.append("&quot;")
            case "'": out.append("&#39;")
            default: out.append(ch)
            }
        }
        return out
    }

    fileprivate static func htmlAttrEscape(_ s: String) -> String {
        htmlEscape(s)
    }
}

// MARK: - AST visitor

private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    mutating func render(_ markup: Markup) -> String {
        visit(markup)
    }

    mutating func defaultVisit(_ markup: Markup) -> String {
        renderChildren(of: markup)
    }

    mutating func visitDocument(_ document: Document) -> String {
        renderChildren(of: document)
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = max(1, min(6, heading.level))
        return "<h\(level)>\(renderChildren(of: heading))</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        // Inside list items, drop the <p> wrapper so tight lists render naturally
        // (`<li>text</li>` instead of `<li><p>text</p></li>`). The CSS handles spacing.
        if paragraph.parent is ListItem {
            return renderChildren(of: paragraph)
        }
        return "<p>\(renderChildren(of: paragraph))</p>\n"
    }

    mutating func visitText(_ text: Text) -> String {
        MarkdownHTMLRenderer.htmlEscape(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(renderChildren(of: emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(renderChildren(of: strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(renderChildren(of: strikethrough))</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(MarkdownHTMLRenderer.htmlEscape(inlineCode.code))</code>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let lang = codeBlock.language?.trimmingCharacters(in: .whitespaces) ?? ""
        let attr = lang.isEmpty ? "" : " class=\"language-\(MarkdownHTMLRenderer.htmlAttrEscape(lang))\""
        return "<pre><code\(attr)>\(MarkdownHTMLRenderer.htmlEscape(codeBlock.code))</code></pre>\n"
    }

    mutating func visitLink(_ link: Link) -> String {
        let href = MarkdownHTMLRenderer.htmlAttrEscape(link.destination ?? "")
        return "<a href=\"\(href)\">\(renderChildren(of: link))</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let src = MarkdownHTMLRenderer.htmlAttrEscape(image.source ?? "")
        let alt = MarkdownHTMLRenderer.htmlAttrEscape(image.plainText)
        return "<img src=\"\(src)\" alt=\"\(alt)\">"
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> String {
        "<ul>\n\(renderChildren(of: list))</ul>\n"
    }

    mutating func visitOrderedList(_ list: OrderedList) -> String {
        let start = list.startIndex
        let attr = start == 1 ? "" : " start=\"\(start)\""
        return "<ol\(attr)>\n\(renderChildren(of: list))</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        "<li>\(renderChildren(of: listItem))</li>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\n\(renderChildren(of: blockQuote))</blockquote>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        // Pass through verbatim - swift-markdown gives us the raw HTML.
        inlineHTML.rawHTML
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        html.rawHTML
    }

    mutating func visitTable(_ table: Table) -> String {
        var out = "<table>\n"
        out += "<thead>\n"
        out += visit(table.head)
        out += "</thead>\n"
        if !table.body.isEmpty {
            out += "<tbody>\n"
            out += visit(table.body)
            out += "</tbody>\n"
        }
        out += "</table>\n"
        return out
    }

    mutating func visitTableHead(_ head: Table.Head) -> String {
        var row = "<tr>"
        for child in head.children {
            if let cell = child as? Table.Cell {
                row += "<th>\(renderChildren(of: cell))</th>"
            }
        }
        row += "</tr>\n"
        return row
    }

    mutating func visitTableBody(_ body: Table.Body) -> String {
        var out = ""
        for child in body.children {
            if let row = child as? Table.Row {
                out += visit(row)
            }
        }
        return out
    }

    mutating func visitTableRow(_ row: Table.Row) -> String {
        var out = "<tr>"
        for child in row.children {
            if let cell = child as? Table.Cell {
                out += "<td>\(renderChildren(of: cell))</td>"
            }
        }
        out += "</tr>\n"
        return out
    }

    // MARK: - Helpers

    private mutating func renderChildren(of markup: Markup) -> String {
        var out = ""
        for child in markup.children {
            out += visit(child)
        }
        return out
    }
}
