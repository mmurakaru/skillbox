import Testing
import Foundation
@testable import Skillbox

@MainActor
struct HookStoreTests {
    private func makeHook(
        event: HookEventName = .preToolUse,
        matcher: String? = "Bash",
        kind: HookKind = .command,
        payload: String = "echo hi",
        scope: HookScope = .userGlobal,
        pointer: String = "/hooks/PreToolUse/0/hooks/0",
        fileURL: URL = URL(fileURLWithPath: "/tmp/settings.json")
    ) -> Hook {
        Hook(
            eventName: event,
            matcher: matcher,
            ifCondition: nil,
            kind: kind,
            payload: payload,
            timeout: nil,
            statusMessage: nil,
            scope: scope,
            fileURL: fileURL,
            jsonPointer: pointer,
            modifiedAt: Date()
        )
    }

    // MARK: - filteredHooks

    @Test func filtered_emptyQueryNoSelection_returnsAll() {
        let store = HookStore(seedHooks: [
            makeHook(event: .preToolUse, payload: "a"),
            makeHook(event: .postToolUse, payload: "b", pointer: "/hooks/PostToolUse/0/hooks/0"),
        ])
        #expect(store.filteredHooks.count == 2)
    }

    @Test func filtered_globalScopeSelected_returnsOnlyGlobalHooks() {
        let store = HookStore(seedHooks: [
            makeHook(payload: "global", scope: .userGlobal),
            makeHook(
                payload: "project",
                scope: .project(name: "alpha", path: "/Users/me/alpha"),
                pointer: "/hooks/PreToolUse/0/hooks/1",
                fileURL: URL(fileURLWithPath: "/Users/me/alpha/.claude/settings.json")
            ),
        ])
        store.selectedScopeKey = "global"
        #expect(store.filteredHooks.map(\.payload) == ["global"])
    }

    @Test func filtered_projectScopeSelected_returnsCommittedAndLocalForThatProject() {
        let projectPath = "/Users/me/alpha"
        let store = HookStore(seedHooks: [
            makeHook(
                payload: "committed",
                scope: .project(name: "alpha", path: projectPath),
                pointer: "/hooks/PreToolUse/0/hooks/0",
                fileURL: URL(fileURLWithPath: "\(projectPath)/.claude/settings.json")
            ),
            makeHook(
                payload: "local",
                scope: .projectLocal(name: "alpha", path: projectPath),
                pointer: "/hooks/PreToolUse/0/hooks/0",
                fileURL: URL(fileURLWithPath: "\(projectPath)/.claude/settings.local.json")
            ),
            makeHook(payload: "global", scope: .userGlobal),
        ])
        store.selectedScopeKey = projectPath
        let payloads = store.filteredHooks.map(\.payload).sorted()
        #expect(payloads == ["committed", "local"])
    }

    @Test func filtered_searchByEventName_matchesCaseInsensitive() {
        let store = HookStore(seedHooks: [
            makeHook(event: .preToolUse, payload: "a"),
            makeHook(event: .sessionStart, payload: "b", pointer: "/hooks/SessionStart/0/hooks/0"),
        ])
        store.searchQuery = "session"
        #expect(store.filteredHooks.map(\.payload) == ["b"])
    }

    @Test func filtered_searchByMatcher_matches() {
        let store = HookStore(seedHooks: [
            makeHook(matcher: "Bash", payload: "a"),
            makeHook(matcher: "Edit", payload: "b", pointer: "/hooks/PreToolUse/1/hooks/0"),
        ])
        store.searchQuery = "edit"
        #expect(store.filteredHooks.map(\.payload) == ["b"])
    }

    @Test func filtered_searchByPayload_matches() {
        let store = HookStore(seedHooks: [
            makeHook(payload: "echo blocked"),
            makeHook(payload: "echo allowed", pointer: "/hooks/PreToolUse/0/hooks/1"),
        ])
        store.searchQuery = "blocked"
        #expect(store.filteredHooks.map(\.payload) == ["echo blocked"])
    }

    @Test func filtered_emptySelectedScopeKey_treatedAsAll() {
        let store = HookStore(seedHooks: [
            makeHook(payload: "a"),
            makeHook(
                payload: "b",
                scope: .project(name: "x", path: "/p"),
                pointer: "/hooks/PreToolUse/0/hooks/1"
            ),
        ])
        store.selectedScopeKey = ""
        #expect(store.filteredHooks.count == 2)
    }

    // MARK: - availableProjects

    @Test func availableProjects_groupsByPathAndIncludesBothLocalAndCommitted() {
        let path = "/Users/me/alpha"
        let store = HookStore(seedHooks: [
            makeHook(scope: .project(name: "alpha", path: path)),
            makeHook(scope: .projectLocal(name: "alpha", path: path), pointer: "/hooks/PreToolUse/0/hooks/1"),
            makeHook(scope: .userGlobal, pointer: "/hooks/PreToolUse/0/hooks/2"),
        ])
        let projects = store.availableProjects
        #expect(projects.count == 1)
        let proj = try? #require(projects.first)
        #expect(proj?.path == path)
        #expect(proj?.count == 2)
    }

    @Test func availableProjects_sortedByDisplayName() {
        let store = HookStore(seedHooks: [
            makeHook(scope: .project(name: "zeta", path: "/z"), pointer: "/hooks/PreToolUse/0/hooks/0"),
            makeHook(scope: .project(name: "alpha", path: "/a"), pointer: "/hooks/PreToolUse/0/hooks/1"),
            makeHook(scope: .project(name: "mu", path: "/m"), pointer: "/hooks/PreToolUse/0/hooks/2"),
        ])
        let names = store.availableProjects.map(\.displayName)
        #expect(names == ["alpha", "mu", "zeta"])
    }

    // MARK: - deleteAtPointer (pure JSON-tree mutation)

    @Test func deleteAtPointer_removesInnerEntry_preservingNeighbours() throws {
        var root: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "matcher": "Bash",
                        "hooks": [
                            ["type": "command", "command": "a"],
                            ["type": "command", "command": "b"],
                        ],
                    ],
                ],
            ],
        ]
        try HookStore.deleteAtPointer(in: &root, pointer: "/hooks/PreToolUse/0/hooks/0")

        let hooksMap = try #require(root["hooks"] as? [String: Any])
        let pre = try #require(hooksMap["PreToolUse"] as? [Any])
        let rule = try #require(pre.first as? [String: Any])
        let inner = try #require(rule["hooks"] as? [Any])
        #expect(inner.count == 1)
        let onlyEntry = try #require(inner.first as? [String: Any])
        #expect(onlyEntry["command"] as? String == "b")
    }

    @Test func deleteAtPointer_collapsesEmptyRuleGroup() throws {
        var root: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "matcher": "Bash",
                        "hooks": [["type": "command", "command": "a"]],
                    ],
                    [
                        "matcher": "Edit",
                        "hooks": [["type": "command", "command": "b"]],
                    ],
                ],
            ],
        ]
        try HookStore.deleteAtPointer(in: &root, pointer: "/hooks/PreToolUse/0/hooks/0")

        let hooksMap = try #require(root["hooks"] as? [String: Any])
        let pre = try #require(hooksMap["PreToolUse"] as? [Any])
        #expect(pre.count == 1)
        let rule = try #require(pre.first as? [String: Any])
        #expect(rule["matcher"] as? String == "Edit")
    }

    @Test func deleteAtPointer_collapsesEmptyEventArray() throws {
        var root: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "a"]]],
                ],
                "PostToolUse": [
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "b"]]],
                ],
            ],
        ]
        try HookStore.deleteAtPointer(in: &root, pointer: "/hooks/PreToolUse/0/hooks/0")

        let hooksMap = try #require(root["hooks"] as? [String: Any])
        #expect(hooksMap["PreToolUse"] == nil)
        #expect(hooksMap["PostToolUse"] != nil)
    }

    @Test func deleteAtPointer_collapsesTopLevelHooksKey() throws {
        var root: [String: Any] = [
            "theme": "dark",
            "hooks": [
                "PreToolUse": [
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "a"]]],
                ],
            ],
        ]
        try HookStore.deleteAtPointer(in: &root, pointer: "/hooks/PreToolUse/0/hooks/0")

        #expect(root["hooks"] == nil)
        #expect(root["theme"] as? String == "dark")
    }

    @Test func deleteAtPointer_invalidPointer_throws() {
        var root: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "a"]]],
                ],
            ],
        ]
        #expect(throws: HookStoreError.self) {
            try HookStore.deleteAtPointer(in: &root, pointer: "/hooks/PreToolUse/9/hooks/0")
        }
    }

    // MARK: - delete (full file roundtrip)

    @Test func delete_writesValidJSONBack() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-hook-delete-\(UUID().uuidString).json")
        try #"""
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  { "type": "command", "command": "a" },
                  { "type": "command", "command": "b" }
                ]
              }
            ]
          }
        }
        """#.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = HookStore()
        let hook = makeHook(
            event: .preToolUse,
            matcher: "Bash",
            payload: "a",
            scope: .userGlobal,
            pointer: "/hooks/PreToolUse/0/hooks/0",
            fileURL: url
        )
        try store.delete(hook)

        let data = try Data(contentsOf: url)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hooksMap = try #require(parsed?["hooks"] as? [String: Any])
        let pre = try #require(hooksMap["PreToolUse"] as? [Any])
        let rule = try #require(pre.first as? [String: Any])
        let inner = try #require(rule["hooks"] as? [Any])
        let only = try #require(inner.first as? [String: Any])
        #expect(only["command"] as? String == "b")
    }
}
