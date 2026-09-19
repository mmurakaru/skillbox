import Testing
import Foundation
@testable import Skillbox

struct InsightsServiceTests {
    @Test func parseBackgroundSessionID_extractsID() {
        let output = """
        backgrounded · 4cfcfe41
          claude agents             list sessions
          claude attach 4cfcfe41    open in this terminal
        """
        #expect(InsightsService.parseBackgroundSessionID(output) == "4cfcfe41")
    }

    @Test func parseBackgroundSessionID_acceptsUUIDStyleID() {
        let output = "backgrounded · 4cfcfe41-1234-abcd"
        #expect(InsightsService.parseBackgroundSessionID(output) == "4cfcfe41-1234-abcd")
    }

    @Test func parseBackgroundSessionID_rejectsOldPrintModeReceipt() {
        let output = #"{"result":"","local_command":"insights","type":"result"}"#
        #expect(InsightsService.parseBackgroundSessionID(output) == nil)
    }

    @Test func reportURL_usesDefaultClaudeDirectory() {
        let url = InsightsService.reportURL(environment: [:])
        #expect(url.path == NSHomeDirectory() + "/.claude/usage-data/report.html")
    }

    @Test func reportURL_honorsClaudeConfigDirectory() {
        let url = InsightsService.reportURL(environment: ["CLAUDE_CONFIG_DIR": "/tmp/custom-claude"])
        #expect(url.path == "/tmp/custom-claude/usage-data/report.html")
    }
}
