import Foundation

enum EnvVarCategory: String, CaseIterable, Hashable {
    case auth
    case api
    case model
    case performance
    case ui
    case feature
    case experimental
    case cloud
    case debug
    case security

    var label: String {
        switch self {
        case .auth: "auth"
        case .api: "api"
        case .model: "model"
        case .performance: "perf"
        case .ui: "ui"
        case .feature: "feature"
        case .experimental: "experimental"
        case .cloud: "cloud"
        case .debug: "debug"
        case .security: "security"
        }
    }
}

struct EnvVarCatalogEntry: Hashable {
    let key: String
    let description: String
    let category: EnvVarCategory
    /// Default value to suggest in the Add sheet when this catalog entry is picked.
    let suggestedValue: String
}

/// Curated list of well-known Claude Code env vars sourced from
/// https://code.claude.com/docs/en/env-vars.md - used for autocomplete in the
/// Add sheet and tooltips on rows. Not exhaustive; users can still type any key.
enum EnvVarCatalog {
    static let entries: [EnvVarCatalogEntry] = [
        // Auth & API
        .init(key: "ANTHROPIC_API_KEY", description: "Anthropic API key", category: .auth, suggestedValue: ""),
        .init(key: "ANTHROPIC_AUTH_TOKEN", description: "Custom Authorization header (prefixed with Bearer)", category: .auth, suggestedValue: ""),
        .init(key: "ANTHROPIC_BETAS", description: "Comma-separated beta header values", category: .api, suggestedValue: ""),
        .init(key: "ANTHROPIC_CUSTOM_HEADERS", description: "Custom HTTP headers (newline-separated)", category: .api, suggestedValue: ""),
        .init(key: "ANTHROPIC_BASE_URL", description: "Override Anthropic API endpoint", category: .api, suggestedValue: ""),
        .init(key: "ANTHROPIC_BEDROCK_BASE_URL", description: "AWS Bedrock endpoint override", category: .cloud, suggestedValue: ""),
        .init(key: "ANTHROPIC_VERTEX_BASE_URL", description: "Google Vertex AI endpoint override", category: .cloud, suggestedValue: ""),
        .init(key: "ANTHROPIC_FOUNDRY_BASE_URL", description: "Azure Foundry endpoint override", category: .cloud, suggestedValue: ""),

        // Model
        .init(key: "ANTHROPIC_MODEL", description: "Model to use", category: .model, suggestedValue: ""),
        .init(key: "ANTHROPIC_DEFAULT_SONNET_MODEL", description: "Default Sonnet model id", category: .model, suggestedValue: ""),
        .init(key: "ANTHROPIC_DEFAULT_OPUS_MODEL", description: "Default Opus model id", category: .model, suggestedValue: ""),
        .init(key: "ANTHROPIC_DEFAULT_HAIKU_MODEL", description: "Default Haiku model id", category: .model, suggestedValue: ""),
        .init(key: "CLAUDE_CODE_DISABLE_1M_CONTEXT", description: "Disable 1M context window", category: .feature, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_DISABLE_LEGACY_MODEL_REMAP", description: "Prevent remapping Opus 4.0/4.1", category: .feature, suggestedValue: "1"),

        // Performance
        .init(key: "API_TIMEOUT_MS", description: "API request timeout in ms (default 600000)", category: .performance, suggestedValue: "600000"),
        .init(key: "BASH_DEFAULT_TIMEOUT_MS", description: "Default Bash command timeout in ms", category: .performance, suggestedValue: "120000"),
        .init(key: "BASH_MAX_TIMEOUT_MS", description: "Max Bash command timeout in ms", category: .performance, suggestedValue: "600000"),
        .init(key: "BASH_MAX_OUTPUT_LENGTH", description: "Max Bash output before truncation", category: .performance, suggestedValue: ""),
        .init(key: "CLAUDE_CODE_MAX_RETRIES", description: "Failed-request retry count", category: .performance, suggestedValue: "10"),
        .init(key: "CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY", description: "Max parallel read-only tools", category: .performance, suggestedValue: "10"),
        .init(key: "CLAUDE_CODE_MAX_OUTPUT_TOKENS", description: "Max output tokens per request", category: .performance, suggestedValue: ""),

        // UI
        .init(key: "CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN", description: "Disable fullscreen rendering", category: .ui, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_NO_FLICKER", description: "Enable research fullscreen mode", category: .ui, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_DISABLE_MOUSE", description: "Disable mouse in fullscreen", category: .ui, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_NATIVE_CURSOR", description: "Show terminal native cursor", category: .ui, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_DISABLE_VIRTUAL_SCROLL", description: "Disable virtual scrolling", category: .ui, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_SCROLL_SPEED", description: "Mouse scroll multiplier (1-20)", category: .ui, suggestedValue: "5"),
        .init(key: "CLAUDE_CODE_DISABLE_TERMINAL_TITLE", description: "Skip terminal title updates", category: .ui, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_HIDE_CWD", description: "Hide working directory in startup logo", category: .ui, suggestedValue: "1"),

        // Feature flags
        .init(key: "CLAUDE_CODE_DISABLE_ATTACHMENTS", description: "Disable file attachment processing", category: .feature, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_DISABLE_AUTO_MEMORY", description: "Disable auto memory", category: .feature, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_DISABLE_CRON", description: "Disable scheduled tasks", category: .feature, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_DISABLE_BACKGROUND_TASKS", description: "Disable all background tasks", category: .feature, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_DISABLE_FILE_CHECKPOINTING", description: "Disable /rewind", category: .feature, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_DISABLE_THINKING", description: "Force-disable extended thinking", category: .feature, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_DISABLE_FAST_MODE", description: "Disable fast mode", category: .feature, suggestedValue: "1"),

        // Experimental
        .init(key: "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS", description: "Enable agent teams", category: .experimental, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_FORK_SUBAGENT", description: "Enable forked subagents", category: .experimental, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS", description: "Strip experimental betas", category: .experimental, suggestedValue: "1"),

        // Debug
        .init(key: "CLAUDE_CODE_DEBUG_LOG_LEVEL", description: "Min debug log level: verbose|debug|info|warn|error", category: .debug, suggestedValue: "info"),
        .init(key: "CLAUDE_CODE_DEBUG_LOGS_DIR", description: "Override debug log path", category: .debug, suggestedValue: ""),
        .init(key: "CLAUDE_CODE_ENABLE_TELEMETRY", description: "Enable OpenTelemetry", category: .debug, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_OTEL_FLUSH_TIMEOUT_MS", description: "OTel span flush timeout in ms", category: .debug, suggestedValue: "5000"),

        // Security
        .init(key: "CLAUDE_CODE_MCP_ALLOWLIST_ENV", description: "Sandbox MCP environment", category: .security, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_SUBPROCESS_ENV_SCRUB", description: "Strip credentials from subprocess env", category: .security, suggestedValue: "1"),
        .init(key: "CLAUDE_CODE_PERFORCE_MODE", description: "Enable Perforce write protection", category: .security, suggestedValue: "1"),
    ]

    static func entry(for key: String) -> EnvVarCatalogEntry? {
        entries.first { $0.key == key }
    }

    static func description(for key: String) -> String? {
        entry(for: key)?.description
    }

    static func suggestions(matching query: String, limit: Int = 8) -> [EnvVarCatalogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return entries
            .filter { entry in
                entry.key.localizedCaseInsensitiveContains(trimmed) ||
                entry.description.localizedCaseInsensitiveContains(trimmed)
            }
            .prefix(limit)
            .map { $0 }
    }
}
