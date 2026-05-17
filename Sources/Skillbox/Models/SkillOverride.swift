import Foundation

/// Mirrors Claude Code's `skillOverrides` values in `~/.claude/settings.json`.
/// An absent entry is treated as `.on`.
enum SkillOverride: String, CaseIterable, Codable {
    case on
    case nameOnly = "name-only"
    case userInvocableOnly = "user-invocable-only"
    case off

    var displayLabel: String {
        switch self {
        case .on: "On"
        case .nameOnly: "Name only"
        case .userInvocableOnly: "User-only"
        case .off: "Off"
        }
    }

    var helpText: String {
        switch self {
        case .on: "Name + description listed to Claude. Claude can auto-invoke."
        case .nameOnly: "Only the name listed to Claude. Saves listing budget."
        case .userInvocableOnly: "Hidden from Claude's listing. You can still invoke it manually."
        case .off: "Hidden from Claude and from the /skills menu."
        }
    }

    var sfSymbol: String {
        switch self {
        case .on: "eye"
        case .nameOnly: "tag"
        case .userInvocableOnly: "lock.fill"
        case .off: "eye.slash.fill"
        }
    }

    /// Next state when the user clicks/cycles.
    var next: SkillOverride {
        switch self {
        case .on: .nameOnly
        case .nameOnly: .userInvocableOnly
        case .userInvocableOnly: .off
        case .off: .on
        }
    }
}
