import StatementPaddingRules
import Testing

struct StatementPaddingTests {
    private func function(_ body: String) -> String {
        "func example() {\n" + body + "}\n"
    }

    @Test func returnAfterAnotherStatementNeedsABlankLine() {
        let source = function("    work()\n    return\n")

        #expect(StatementPadding.violations(in: source) == [StatementPaddingViolation(line: 3, column: 5)])
        #expect(StatementPadding.fixed(source) == function("    work()\n\n    return\n"))
    }

    @Test func ifStatementNeedsBlankLinesAboveAndBelow() {
        let source = function("    work()\n    if flag {\n        work()\n    } else {\n        work()\n    }\n    work()\n")

        #expect(
            StatementPadding.fixed(source)
                == function("    work()\n\n    if flag {\n        work()\n    } else {\n        work()\n    }\n\n    work()\n"))
    }

    @Test func consecutiveDeclarationsStayTogetherButNeedABlankLineAfterTheGroup() {
        let source = function("    let first = 1\n    var second = 2\n    use(first, second)\n")

        #expect(StatementPadding.fixed(source) == function("    let first = 1\n    var second = 2\n\n    use(first, second)\n"))
    }

    @Test func blankLineGoesAboveTheLeadingComment() {
        let source = function("    let value = 1\n    // Explains the call.\n    use(value)\n")

        #expect(StatementPadding.fixed(source) == function("    let value = 1\n\n    // Explains the call.\n    use(value)\n"))
    }

    @Test func paddedCodeAndSingleStatementsAreLeftAlone() {
        let source = function("    let value = 1\n\n    if value > 0 {\n        return\n    }\n\n    return\n")

        #expect(StatementPadding.violations(in: source).isEmpty)
        #expect(StatementPadding.fixed(source) == source)
    }

    @Test func ifExpressionAssignedToAVariableIsADeclarationNotAnIfStatement() {
        let source = function("    let value = if flag { 1 } else { 2 }\n    let other = 3\n")

        #expect(StatementPadding.violations(in: source).isEmpty)
    }

    @Test func switchCaseBodiesArePadded() {
        let source = "switch mode {\ncase .on:\n    let value = 1\n    use(value)\ndefault:\n    break\n}\n"

        #expect(StatementPadding.fixed(source) == "switch mode {\ncase .on:\n    let value = 1\n\n    use(value)\ndefault:\n    break\n}\n")
    }

    @Test func statementsSharingALineAreLeftAlone() {
        let source = function("    let value = 1; use(value)\n")

        #expect(StatementPadding.violations(in: source).isEmpty)
    }
}
