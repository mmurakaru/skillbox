import Foundation

/// Providers have separate subscription quotas; their percentages are never added together.
enum UsageProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex, grok, claude
    var id: String { rawValue }
    var name: String {
        switch self {
        case .codex: "Codex"
        case .grok: "Grok"
        case .claude: "Claude Code"
        }
    }
    var windowLabels: [String] {
        switch self {
        case .codex: ["5-hour limit", "Weekly limit"]
        case .grok: ["Weekly limit"]
        case .claude: ["Current session", "Weekly limit"]
        }
    }
}

/// A missing percentage is unknown, whereas zero means the provider reported no usage.
struct ProviderUsageWindow: Codable, Identifiable, Equatable, Sendable {
    var label: String
    var usedPercent: Double?
    var resetsAt: Date?
    var id: String { label }
}

/// Non-quota values retain their provider's unit or currency instead of being summed.
struct ProviderUsageDetail: Codable, Identifiable, Equatable, Sendable {
    var label: String
    var value: String
    var id: String { label }
}

/// Usage snapshots contain display values only, never authentication credentials.
struct ProviderUsageSnapshot: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case live, manual }
    var provider: UsageProvider
    var plan: String?
    var windows: [ProviderUsageWindow]
    var details: [ProviderUsageDetail] = []
    var updatedAt: Date
    var source: Source
    var accountEmail: String? = nil
}


extension ProviderUsageSnapshot {
    /// Updates old saved Grok labels without changing their plan, percentages, or reset times.
    func normalizingUsageLabels() -> ProviderUsageSnapshot {
        guard provider == .grok else { return self }
        var snapshot = self
        snapshot.windows = windows.map { window in
            var window = window
            if window.label == "Weekly SuperGrok limit" { window.label = "Weekly limit" }
            if window.label == "Monthly SuperGrok limit" { window.label = "Monthly limit" }
            return window
        }
        return snapshot
    }
}
