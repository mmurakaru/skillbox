import Foundation

enum HookEventName: Hashable {
    case preToolUse
    case postToolUse
    case userPromptSubmit
    case notification
    case stop
    case subagentStop
    case sessionStart
    case sessionEnd
    case preCompact
    case other(String)

    var canonicalKey: String {
        switch self {
        case .preToolUse: "PreToolUse"
        case .postToolUse: "PostToolUse"
        case .userPromptSubmit: "UserPromptSubmit"
        case .notification: "Notification"
        case .stop: "Stop"
        case .subagentStop: "SubagentStop"
        case .sessionStart: "SessionStart"
        case .sessionEnd: "SessionEnd"
        case .preCompact: "PreCompact"
        case .other(let raw): raw
        }
    }

    var displayLabel: String { canonicalKey }

    /// Stable sort order; canonical events first in lifecycle order, .other after.
    var sortKey: (Int, String) {
        switch self {
        case .preToolUse: (0, canonicalKey)
        case .postToolUse: (1, canonicalKey)
        case .userPromptSubmit: (2, canonicalKey)
        case .notification: (3, canonicalKey)
        case .stop: (4, canonicalKey)
        case .subagentStop: (5, canonicalKey)
        case .sessionStart: (6, canonicalKey)
        case .sessionEnd: (7, canonicalKey)
        case .preCompact: (8, canonicalKey)
        case .other(let raw): (100, raw)
        }
    }

    static func parse(_ raw: String) -> HookEventName {
        switch raw {
        case "PreToolUse": .preToolUse
        case "PostToolUse": .postToolUse
        case "UserPromptSubmit": .userPromptSubmit
        case "Notification": .notification
        case "Stop": .stop
        case "SubagentStop": .subagentStop
        case "SessionStart": .sessionStart
        case "SessionEnd": .sessionEnd
        case "PreCompact": .preCompact
        default: .other(raw)
        }
    }
}

enum HookKind: Hashable {
    case command
    case http
    case prompt
    case agent
    case mcpTool
    case other(String)

    var displayLabel: String {
        switch self {
        case .command: "command"
        case .http: "http"
        case .prompt: "prompt"
        case .agent: "agent"
        case .mcpTool: "mcp_tool"
        case .other(let raw): raw
        }
    }

    static func parse(_ raw: String) -> HookKind {
        switch raw {
        case "command": .command
        case "http": .http
        case "prompt": .prompt
        case "agent": .agent
        case "mcp_tool": .mcpTool
        default: .other(raw)
        }
    }
}

enum HookScope: Hashable {
    case userGlobal
    case project(name: String, path: String)
    case projectLocal(name: String, path: String)

    var shortLabel: String {
        switch self {
        case .userGlobal: "Global"
        case .project: "Project"
        case .projectLocal: "Local"
        }
    }

    var displayName: String {
        switch self {
        case .userGlobal: "User Global"
        case .project(let name, _): name
        case .projectLocal(let name, _): name
        }
    }

    /// Path used for grouping in the scope picker - `.project` and `.projectLocal`
    /// share the same project path so a single picker entry covers both.
    var projectPath: String? {
        switch self {
        case .userGlobal: nil
        case .project(_, let path), .projectLocal(_, let path): path
        }
    }
}

struct Hook: Identifiable, Hashable {
    let id: String
    let eventName: HookEventName
    let matcher: String?
    let ifCondition: String?
    let kind: HookKind
    let payload: String
    let timeout: Int?
    let statusMessage: String?
    let scope: HookScope
    let fileURL: URL
    let jsonPointer: String
    let modifiedAt: Date

    init(
        eventName: HookEventName,
        matcher: String?,
        ifCondition: String?,
        kind: HookKind,
        payload: String,
        timeout: Int?,
        statusMessage: String?,
        scope: HookScope,
        fileURL: URL,
        jsonPointer: String,
        modifiedAt: Date
    ) {
        self.id = "\(fileURL.path)#\(jsonPointer)"
        self.eventName = eventName
        self.matcher = matcher
        self.ifCondition = ifCondition
        self.kind = kind
        self.payload = payload
        self.timeout = timeout
        self.statusMessage = statusMessage
        self.scope = scope
        self.fileURL = fileURL
        self.jsonPointer = jsonPointer
        self.modifiedAt = modifiedAt
    }

    var displayMatcher: String { matcher ?? "*" }

    var titleLine: String {
        "\(eventName.displayLabel) · \(displayMatcher)"
    }
}
