import Foundation

enum HookScanner {
    /// Parses one settings.json file. For every entry in
    /// `hooks.<EventName>[*].hooks[*]`, yields one `Hook` with a stable
    /// RFC 6901 JSON pointer (`/hooks/<EventName>/<ruleIdx>/hooks/<innerIdx>`).
    /// Returns an empty array if the file has no `hooks` object.
    static func scan(fileURL: URL, scope: HookScope) throws -> [Hook] {
        let data = try Data(contentsOf: fileURL)
        let parsed = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = parsed as? [String: Any],
              let hooksMap = root["hooks"] as? [String: Any] else {
            return []
        }

        let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()

        var result: [Hook] = []
        for (eventKey, eventValueAny) in hooksMap {
            guard let ruleGroups = eventValueAny as? [Any] else { continue }
            let event = HookEventName.parse(eventKey)
            for (ruleIdx, ruleAny) in ruleGroups.enumerated() {
                guard let rule = ruleAny as? [String: Any] else { continue }
                let matcher = rule["matcher"] as? String
                let ifCondition = rule["if"] as? String
                guard let inner = rule["hooks"] as? [Any] else { continue }
                for (innerIdx, hookAny) in inner.enumerated() {
                    guard let hookDict = hookAny as? [String: Any] else { continue }
                    let kind = HookKind.parse((hookDict["type"] as? String) ?? "")
                    let pointer = "/hooks/\(escape(eventKey))/\(ruleIdx)/hooks/\(innerIdx)"
                    result.append(
                        Hook(
                            eventName: event,
                            matcher: matcher,
                            ifCondition: ifCondition,
                            kind: kind,
                            payload: extractPayload(from: hookDict, kind: kind),
                            timeout: hookDict["timeout"] as? Int,
                            statusMessage: hookDict["statusMessage"] as? String,
                            scope: scope,
                            fileURL: fileURL,
                            jsonPointer: pointer,
                            modifiedAt: modifiedAt
                        )
                    )
                }
            }
        }
        return result
    }

    private static func extractPayload(from dict: [String: Any], kind: HookKind) -> String {
        switch kind {
        case .command:
            return (dict["command"] as? String) ?? ""
        case .http:
            return (dict["url"] as? String) ?? ""
        case .prompt:
            return (dict["prompt"] as? String) ?? ""
        case .agent, .mcpTool:
            if let names = dict["hooks"] as? [String], !names.isEmpty {
                return names.joined(separator: ", ")
            }
            return (dict["prompt"] as? String) ?? ""
        case .other:
            return (dict["command"] as? String)
                ?? (dict["url"] as? String)
                ?? (dict["prompt"] as? String)
                ?? ""
        }
    }

    /// RFC 6901: `~` -> `~0`, `/` -> `~1`. Order matters.
    private static func escape(_ token: String) -> String {
        token
            .replacingOccurrences(of: "~", with: "~0")
            .replacingOccurrences(of: "/", with: "~1")
    }
}
