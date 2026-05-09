import Testing
import Foundation
@testable import Skillbox

struct HookScannerTests {
    private func makeFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-hook-scanner-\(UUID().uuidString).json")
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func write(_ json: String, to url: URL) throws {
        try json.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func scan_emptyObject_returnsEmpty() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write("{}", to: url)

        let result = try HookScanner.scan(fileURL: url, scope: .userGlobal)
        #expect(result.isEmpty)
    }

    @Test func scan_settingsWithoutHooksKey_returnsEmpty() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"{"theme": "dark"}"#, to: url)

        let result = try HookScanner.scan(fileURL: url, scope: .userGlobal)
        #expect(result.isEmpty)
    }

    @Test func scan_singleCommandHook_parsesAllFields() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"""
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "echo hi",
                    "timeout": 30,
                    "statusMessage": "running"
                  }
                ]
              }
            ]
          }
        }
        """#, to: url)

        let result = try HookScanner.scan(fileURL: url, scope: .userGlobal)
        #expect(result.count == 1)
        let hook = try #require(result.first)
        #expect(hook.eventName == .preToolUse)
        #expect(hook.matcher == "Bash")
        #expect(hook.kind == .command)
        #expect(hook.payload == "echo hi")
        #expect(hook.timeout == 30)
        #expect(hook.statusMessage == "running")
        #expect(hook.jsonPointer == "/hooks/PreToolUse/0/hooks/0")
        #expect(hook.scope == .userGlobal)
    }

    @Test func scan_multipleEventsAndRuleGroups_yieldsStablePointers() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"""
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  { "type": "command", "command": "a" },
                  { "type": "command", "command": "b" }
                ]
              },
              {
                "matcher": "Edit|Write",
                "hooks": [
                  { "type": "command", "command": "c" }
                ]
              }
            ],
            "PostToolUse": [
              {
                "hooks": [
                  { "type": "command", "command": "d" }
                ]
              }
            ]
          }
        }
        """#, to: url)

        let result = try HookScanner.scan(fileURL: url, scope: .userGlobal)
        #expect(result.count == 4)

        let pointers = Set(result.map(\.jsonPointer))
        #expect(pointers.contains("/hooks/PreToolUse/0/hooks/0"))
        #expect(pointers.contains("/hooks/PreToolUse/0/hooks/1"))
        #expect(pointers.contains("/hooks/PreToolUse/1/hooks/0"))
        #expect(pointers.contains("/hooks/PostToolUse/0/hooks/0"))

        // Rule group with no matcher -> matcher is nil.
        let postHook = try #require(result.first(where: { $0.eventName == .postToolUse }))
        #expect(postHook.matcher == nil)
    }

    @Test func scan_unknownEventName_fallsBackToOther() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"""
        {
          "hooks": {
            "FutureEvent": [
              { "hooks": [ { "type": "command", "command": "x" } ] }
            ]
          }
        }
        """#, to: url)

        let result = try HookScanner.scan(fileURL: url, scope: .userGlobal)
        let hook = try #require(result.first)
        #expect(hook.eventName == .other("FutureEvent"))
    }

    @Test func scan_unknownType_fallsBackToOther() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"""
        {
          "hooks": {
            "PreToolUse": [
              { "hooks": [ { "type": "future_kind", "command": "x" } ] }
            ]
          }
        }
        """#, to: url)

        let hook = try #require(try HookScanner.scan(fileURL: url, scope: .userGlobal).first)
        #expect(hook.kind == .other("future_kind"))
        #expect(hook.payload == "x")
    }

    @Test func scan_httpHook_extractsURLAsPayload() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"""
        {
          "hooks": {
            "Notification": [
              { "hooks": [ { "type": "http", "url": "https://example.com/hook" } ] }
            ]
          }
        }
        """#, to: url)

        let hook = try #require(try HookScanner.scan(fileURL: url, scope: .userGlobal).first)
        #expect(hook.kind == .http)
        #expect(hook.payload == "https://example.com/hook")
    }

    @Test func scan_capturesIfCondition() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"""
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "if": "Bash(git push *)",
                "hooks": [ { "type": "command", "command": "block" } ]
              }
            ]
          }
        }
        """#, to: url)

        let hook = try #require(try HookScanner.scan(fileURL: url, scope: .userGlobal).first)
        #expect(hook.ifCondition == "Bash(git push *)")
    }

    @Test func scan_skipsMalformedRuleEntries() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"""
        {
          "hooks": {
            "PreToolUse": [
              "not an object",
              { "matcher": "Bash" },
              { "matcher": "Bash", "hooks": [ "also not an object", { "type": "command", "command": "ok" } ] }
            ]
          }
        }
        """#, to: url)

        let result = try HookScanner.scan(fileURL: url, scope: .userGlobal)
        #expect(result.count == 1)
        #expect(result.first?.payload == "ok")
    }
}
