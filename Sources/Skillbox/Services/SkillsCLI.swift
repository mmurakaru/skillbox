import Foundation

enum SkillsCLI {
    enum Availability: Equatable {
        case available
        case missing
    }

    struct InstallOptions {
        var source: String
        var skill: String?
        var agent: String = "claude-code"
        var global: Bool = true
        var copyMode: Bool = true
    }

    enum CLIError: LocalizedError {
        case npxMissing
        case nonZeroExit(code: Int32, output: String)
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .npxMissing:
                return "Node/npx not found. Install Node.js to manage remote skills."
            case .nonZeroExit(let code, let output):
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return "skills CLI failed (exit \(code))\(trimmed.isEmpty ? "" : ":\n\(trimmed)")"
            case .launchFailed(let msg):
                return "Failed to run skills CLI: \(msg)"
            }
        }
    }

    struct RunResult {
        let exitCode: Int32
        let combinedOutput: String
    }

    // MARK: - Detection

    private static let cachedNpxPath = NpxPathCache()

    static func resolvedNpxPath() async -> String? {
        if let cached = cachedNpxPath.get() { return cached }

        // 1. Ask an interactive login zsh — picks up .zshrc setup (nvm/fnm/asdf/Homebrew shellenv).
        if let viaShell = try? await runShellRaw("command -v npx"),
           viaShell.exitCode == 0 {
            if let path = extractNpxPath(from: viaShell.combinedOutput) {
                cachedNpxPath.set(path)
                return path
            }
        }

        // 2. Probe well-known absolute paths.
        let candidates = [
            "/opt/homebrew/bin/npx",
            "/usr/local/bin/npx",
            (NSHomeDirectory() as NSString).appendingPathComponent(".volta/bin/npx"),
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            cachedNpxPath.set(candidate)
            return candidate
        }
        return nil
    }

    static func detect() async -> Availability {
        await resolvedNpxPath() != nil ? .available : .missing
    }

    static func clearDetectionCache() {
        cachedNpxPath.set(nil)
    }

    private static func extractNpxPath(from output: String) -> String? {
        for line in output.components(separatedBy: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("/"), trimmed.hasSuffix("npx"),
               FileManager.default.isExecutableFile(atPath: trimmed) {
                return trimmed
            }
        }
        return nil
    }

    // MARK: - Public commands

    @discardableResult
    static func install(
        _ options: InstallOptions,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> RunResult {
        try await runNpxSkills(args: addArgs(for: options), stream: stream)
    }

    @discardableResult
    static func update(
        skillName: String,
        agent: String = "claude-code",
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> RunResult {
        try await runNpxSkills(args: updateArgs(skillName: skillName, agent: agent), stream: stream)
    }

    @discardableResult
    static func remove(
        skillName: String,
        agent: String = "claude-code",
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> RunResult {
        try await runNpxSkills(args: removeArgs(skillName: skillName, agent: agent), stream: stream)
    }

    // MARK: - Argv builders (pure, testable)

    static func addArgs(for options: InstallOptions) -> [String] {
        var argv: [String] = ["add", options.source]
        if let skill = options.skill, !skill.isEmpty {
            argv.append(contentsOf: ["--skill", skill])
        }
        argv.append(contentsOf: ["-a", options.agent])
        if options.global { argv.append("-g") }
        if options.copyMode { argv.append("--copy") }
        argv.append("-y")
        return argv
    }

    static func updateArgs(skillName: String, agent: String = "claude-code") -> [String] {
        ["update", skillName, "-a", agent, "-g", "-y"]
    }

    static func removeArgs(skillName: String, agent: String = "claude-code") -> [String] {
        ["remove", skillName, "-a", agent, "-g", "-y"]
    }

    // MARK: - Process plumbing

    private static func runNpxSkills(
        args: [String],
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> RunResult {
        guard let npxPath = await resolvedNpxPath() else { throw CLIError.npxMissing }

        // Run npx via its absolute path through an interactive login zsh so node-version-manager
        // shims and PATH are fully populated for the subprocess (npx still needs `node` on PATH).
        let quoted = ([npxPath, "--yes", "skills"] + args)
            .map(shellQuote)
            .joined(separator: " ")
        return try await runShellRaw(quoted, stream: stream)
    }

    @discardableResult
    static func runShellRaw(
        _ command: String,
        stream: (@Sendable (String) -> Void)? = nil
    ) async throws -> RunResult {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RunResult, Error>) in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-i", "-l", "-c", command]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            let buffer = OutputBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                buffer.append(chunk)
                stream?(chunk)
            }

            task.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                if let leftover = try? pipe.fileHandleForReading.readToEnd(),
                   !leftover.isEmpty,
                   let chunk = String(data: leftover, encoding: .utf8) {
                    buffer.append(chunk)
                    stream?(chunk)
                }
                cont.resume(returning: RunResult(
                    exitCode: proc.terminationStatus,
                    combinedOutput: buffer.snapshot()
                ))
            }

            do {
                try task.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                cont.resume(throwing: CLIError.launchFailed(error.localizedDescription))
            }
        }
    }

    static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./-_")
        if s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func append(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        value += s
    }

    func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

private final class NpxPathCache: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func get() -> String? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set(_ newValue: String?) {
        lock.lock(); defer { lock.unlock() }
        value = newValue
    }
}
