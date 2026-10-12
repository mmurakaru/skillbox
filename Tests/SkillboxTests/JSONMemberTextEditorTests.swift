import Foundation
import Testing
@testable import Skillbox

struct JSONMemberTextEditorTests {
    @Test func replacingMember_numberWithBoolean_rewritesTheValue() throws {
        let text = """
        {
          "server": {
            "enabled": 1,
            "url": "https://mcp.example.com/mcp"
          }
        }
        """

        let updated = try JSONMemberTextEditor.replacingMember(
            at: ["server"], in: text, with: ["enabled": true, "url": "https://mcp.example.com/mcp"] as [String: Any]
        )

        #expect(updated.contains(#""enabled": true"#))
        #expect(updated.contains(#""url": "https://mcp.example.com/mcp""#))
    }

    @Test func replacingMember_unchangedBooleanAndNumber_keepTheirText() throws {
        let text = """
        {
          "server": {
            "enabled": true,
            "retries": 1.0
          }
        }
        """

        let updated = try JSONMemberTextEditor.replacingMember(
            at: ["server"], in: text, with: ["enabled": true, "retries": 1.0, "added": "x"] as [String: Any]
        )

        #expect(updated.contains(#""enabled": true"#))
        #expect(updated.contains(#""retries": 1.0"#))
        #expect(updated.contains(#""added": "x""#))
    }
}
