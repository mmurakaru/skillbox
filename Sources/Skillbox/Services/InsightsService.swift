import Foundation

struct InsightsResult: Sendable {
    let markdown: String
    let sessionId: String?
    let costUSD: Double?
}

enum InsightsServiceError: Error, LocalizedError {
    case binaryNotFound(searched: [String])
    case overrideMissing(String)
    case launchFailed(String)
    case nonZeroExit(code: Int32, stderrTail: String)
    case malformedJSON(rawTail: String)
    case missingResultField

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let searched):
            let dirs = searched.prefix(6).joined(separator: ", ")
            return "Could not find `claude` on PATH. Searched: \(dirs)…\n\nSet a custom path in Settings → Claude CLI."
        case .overrideMissing(let path):
            return "Configured `claudeCommand` does not exist or is not executable: \(path)"
        case .launchFailed(let msg):
            return "Failed to launch claude: \(msg)"
        case .nonZeroExit(let code, let tail):
            let trimmed = tail.trimmingCharacters(in: .whitespacesAndNewlines)
            return "claude exited with code \(code).\(trimmed.isEmpty ? "" : "\n\n\(trimmed)")"
        case .malformedJSON(let tail):
            let trimmed = tail.trimmingCharacters(in: .whitespacesAndNewlines)
            return "claude output was not valid JSON.\(trimmed.isEmpty ? "" : "\n\n…\(trimmed)")"
        case .missingResultField:
            return "claude JSON response had no `result` field."
        }
    }
}

/// Spawns `claude -p "/insights" --output-format json --allowedTools Read` from a given cwd
/// and returns the parsed markdown output. Mirrors the subprocess pattern in
/// `SkillsCLI.runShellRaw` (Sources/Skillbox/Services/SkillsCLI.swift:155-197) but adapted
/// for an absolute-path binary plus structured JSON parsing on completion.
enum InsightsService {
    static func run(
        claudePath: String,
        cwd: URL,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> InsightsResult {
        let result = try await runProcess(
            claudePath: claudePath,
            cwd: cwd,
            arguments: ["-p", "/insights", "--output-format", "json", "--allowedTools", "Read"],
            onChunk: onChunk
        )
        if result.exitCode != 0 {
            throw InsightsServiceError.nonZeroExit(
                code: result.exitCode,
                stderrTail: trailingLines(result.stderr, max: 30)
            )
        }
        return try parseOutput(result.stdout)
    }

    /// Pure parsing layer - exposed for tests.
    static func parseOutput(_ stdout: String) throws -> InsightsResult {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InsightsServiceError.malformedJSON(rawTail: trailingLines(stdout, max: 20))
        }
        guard let markdown = parsed["result"] as? String else {
            throw InsightsServiceError.missingResultField
        }
        let sessionId = parsed["session_id"] as? String
        let cost = (parsed["total_cost_usd"] as? NSNumber)?.doubleValue
        return InsightsResult(markdown: markdown, sessionId: sessionId, costUSD: cost)
    }

    // MARK: - Subprocess

    private struct ProcessResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private static func runProcess(
        claudePath: String,
        cwd: URL,
        arguments: [String],
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessResult, Error>) in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: claudePath)
            task.arguments = arguments
            task.currentDirectoryURL = cwd

            // Use a login-shell-like environment so claude can find git/etc on PATH.
            var env = ProcessInfo.processInfo.environment
            let extras = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
            let currentPath = env["PATH"] ?? ""
            var dirs = currentPath.split(separator: ":").map(String.init)
            for e in extras where !dirs.contains(e) { dirs.append(e) }
            env["PATH"] = dirs.joined(separator: ":")
            task.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            task.standardOutput = stdoutPipe
            task.standardError = stderrPipe

            let stdoutBuffer = OutputAccumulator()
            let stderrBuffer = OutputAccumulator()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                stdoutBuffer.append(chunk)
                onChunk(chunk)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                stderrBuffer.append(chunk)
                onChunk(chunk)
            }

            task.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if let leftover = try? stdoutPipe.fileHandleForReading.readToEnd(),
                   !leftover.isEmpty,
                   let chunk = String(data: leftover, encoding: .utf8) {
                    stdoutBuffer.append(chunk)
                }
                if let leftover = try? stderrPipe.fileHandleForReading.readToEnd(),
                   !leftover.isEmpty,
                   let chunk = String(data: leftover, encoding: .utf8) {
                    stderrBuffer.append(chunk)
                }
                cont.resume(returning: ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdout: stdoutBuffer.snapshot(),
                    stderr: stderrBuffer.snapshot()
                ))
            }

            do {
                try task.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                cont.resume(throwing: InsightsServiceError.launchFailed(error.localizedDescription))
            }
        }
    }

    private static func trailingLines(_ text: String, max: Int) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > max else { return text }
        return lines.suffix(max).joined(separator: "\n")
    }
}

private final class OutputAccumulator: @unchecked Sendable {
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
