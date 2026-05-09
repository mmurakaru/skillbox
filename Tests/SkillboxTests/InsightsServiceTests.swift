import Testing
import Foundation
@testable import Skillbox

struct InsightsServiceTests {
    @Test func parseOutput_validJSON_returnsAllFields() throws {
        let json = #"""
        {
          "session_id": "abc-123",
          "result": "# Insights\n\nLooks good.",
          "total_cost_usd": 0.0421
        }
        """#
        let result = try InsightsService.parseOutput(json)
        #expect(result.markdown == "# Insights\n\nLooks good.")
        #expect(result.sessionId == "abc-123")
        #expect(result.costUSD == 0.0421)
    }

    @Test func parseOutput_resultOnly_succeedsWithMissingOptionals() throws {
        let json = #"{"result": "hello"}"#
        let result = try InsightsService.parseOutput(json)
        #expect(result.markdown == "hello")
        #expect(result.sessionId == nil)
        #expect(result.costUSD == nil)
    }

    @Test func parseOutput_malformedJSON_throws() {
        #expect(throws: InsightsServiceError.self) {
            try InsightsService.parseOutput("not json")
        }
    }

    @Test func parseOutput_validJSONWithoutResult_throwsMissingResult() {
        do {
            _ = try InsightsService.parseOutput(#"{"session_id": "x"}"#)
            Issue.record("expected throw")
        } catch InsightsServiceError.missingResultField {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func parseOutput_handlesLeadingTrailingWhitespace() throws {
        let result = try InsightsService.parseOutput("  \n{\"result\": \"x\"}\n  ")
        #expect(result.markdown == "x")
    }
}
