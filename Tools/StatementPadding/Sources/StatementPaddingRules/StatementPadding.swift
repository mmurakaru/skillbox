import SwiftParser
import SwiftSyntax

/// One statement that needs a blank line above it (above its leading comments, when it has any).
public struct StatementPaddingViolation: Equatable, Sendable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

/// Blank lines around `if` statements, before `return`, and after a group of `let`/`var` declarations.
public enum StatementPadding {
    public static let message = "Add a blank line around if statements, after declarations, and before returns."

    public static func violations(in source: String) -> [StatementPaddingViolation] {
        let tree = Parser.parse(source: source)
        let finder = PaddingFinder(viewMode: .sourceAccurate)

        finder.walk(tree)
        let converter = SourceLocationConverter(fileName: "", tree: tree)

        return finder.itemsNeedingPadding.map { item in
            let location = item.startLocation(converter: converter, afterLeadingTrivia: true)

            return StatementPaddingViolation(line: location.line, column: location.column)
        }
    }

    public static func fixed(_ source: String) -> String {
        let tree = Parser.parse(source: source)
        let finder = PaddingFinder(viewMode: .sourceAccurate)

        finder.walk(tree)
        guard !finder.itemsNeedingPadding.isEmpty else { return source }
        let rewriter = PaddingInserter(itemIDs: Set(finder.itemsNeedingPadding.map(\.id)))

        return rewriter.rewrite(tree).description
    }

    static func needsBlankLine(between previous: CodeBlockItemSyntax, and next: CodeBlockItemSyntax) -> Bool {
        isReturn(next) || isIfStatement(next) || isIfStatement(previous)
            || (isVariableDeclaration(previous) && !isVariableDeclaration(next))
    }

    static func hasBlankLine(before item: CodeBlockItemSyntax) -> Bool {
        var newlinesBeforeFirstComment = 0

        for piece in item.leadingTrivia {
            switch piece {
            case .newlines(let count), .carriageReturnLineFeeds(let count):
                newlinesBeforeFirstComment += count
            case .spaces, .tabs, .carriageReturns:
                continue
            default:
                return newlinesBeforeFirstComment >= 2
            }
        }

        return newlinesBeforeFirstComment >= 2
    }

    /// Statements on one line (`a; b`) are left alone.
    static func startsOnNewLine(_ item: CodeBlockItemSyntax) -> Bool {
        item.leadingTrivia.contains { piece in
            if case .newlines = piece { return true }

            if case .carriageReturnLineFeeds = piece { return true }

            return false
        }
    }

    private static func isReturn(_ item: CodeBlockItemSyntax) -> Bool {
        item.item.is(ReturnStmtSyntax.self)
    }

    private static func isIfStatement(_ item: CodeBlockItemSyntax) -> Bool {
        if let expressionStatement = item.item.as(ExpressionStmtSyntax.self) {
            return expressionStatement.expression.is(IfExprSyntax.self)
        }

        return item.item.is(IfExprSyntax.self)
    }

    private static func isVariableDeclaration(_ item: CodeBlockItemSyntax) -> Bool {
        item.item.is(VariableDeclSyntax.self)
    }
}

private final class PaddingFinder: SyntaxVisitor {
    var itemsNeedingPadding: [CodeBlockItemSyntax] = []

    override func visit(_ list: CodeBlockItemListSyntax) -> SyntaxVisitorContinueKind {
        var previous: CodeBlockItemSyntax?

        for item in list {
            if let previous, StatementPadding.needsBlankLine(between: previous, and: item), StatementPadding.startsOnNewLine(item),
                !StatementPadding.hasBlankLine(before: item)
            {
                itemsNeedingPadding.append(item)
            }

            previous = item
        }

        return .visitChildren
    }
}

private final class PaddingInserter: SyntaxRewriter {
    let itemIDs: Set<SyntaxIdentifier>

    init(itemIDs: Set<SyntaxIdentifier>) {
        self.itemIDs = itemIDs
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ item: CodeBlockItemSyntax) -> CodeBlockItemSyntax {
        let visited = super.visit(item)

        guard itemIDs.contains(item.id) else { return visited }

        var pieces = Array(visited.leadingTrivia.pieces)

        if let firstNewline = pieces.firstIndex(where: { if case .newlines = $0 { return true } else { return false } }),
            case .newlines(let count) = pieces[firstNewline]
        {
            pieces[firstNewline] = .newlines(max(count, 2))
        } else if let firstNewline = pieces.firstIndex(where: {
            if case .carriageReturnLineFeeds = $0 { return true } else { return false }
        }),
            case .carriageReturnLineFeeds(let count) = pieces[firstNewline]
        {
            pieces[firstNewline] = .carriageReturnLineFeeds(max(count, 2))
        }

        return visited.with(\.leadingTrivia, Trivia(pieces: pieces))
    }
}
