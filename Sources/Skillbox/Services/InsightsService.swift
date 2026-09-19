import Foundation

struct InsightsResult: Sendable {
    let reportURL: URL
    let backgroundSessionID: String
}

enum InsightsServiceError: Error, LocalizedError {
    case binaryNotFound(searched: [String])
    case overrideMissing(String)
    case launchFailed(String)
    case nonZeroExit(code: Int32, stderrTail: String)
    case missingBackgroundSessionID(rawOutput: String)
    case reportTimedOut(URL)

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
        case .missingBackgroundSessionID(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Claude did not return an Insights background-session ID.\(trimmed.isEmpty ? "" : "\n\n\(trimmed)")"
        case .reportTimedOut(let url):
            return "Claude did not update the Insights report at \(url.path) before the run timed out."
        }
    }
}

/// Starts `/insights` as a Claude background session, waits for Claude's documented
/// `usage-data/report.html` output to change, then stops the temporary session.
enum InsightsService {
    static func run(
        claudePath: String,
        cwd: URL,
        onChunk: @escaping @Sendable (String) -> Void,
        timeout: Duration = .seconds(900)
    ) async throws -> InsightsResult {
        let reportURL = reportURL()
        let previousSnapshot = fileSnapshot(at: reportURL)
        let launch = try await runProcess(
            claudePath: claudePath,
            cwd: cwd,
            arguments: ["--bg", "/insights"],
            onChunk: onChunk
        )
        if launch.exitCode != 0 {
            throw InsightsServiceError.nonZeroExit(
                code: launch.exitCode,
                stderrTail: trailingLines(launch.stderr, max: 30)
            )
        }

        let combinedOutput = launch.stdout + launch.stderr
        guard let sessionID = parseBackgroundSessionID(combinedOutput) else {
            throw InsightsServiceError.missingBackgroundSessionID(rawOutput: combinedOutput)
        }

        do {
            let freshReport = try await waitForFreshReport(
                at: reportURL,
                previousSnapshot: previousSnapshot,
                timeout: timeout
            )
            await stopBackgroundSession(sessionID, claudePath: claudePath, cwd: cwd)
            return InsightsResult(reportURL: freshReport, backgroundSessionID: sessionID)
        } catch {
            await stopBackgroundSession(sessionID, claudePath: claudePath, cwd: cwd)
            throw error
        }
    }

    /// Pure parsing layer exposed for tests.
    static func parseBackgroundSessionID(_ output: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"backgrounded\s+·\s+([A-Za-z0-9-]+)"#
        ) else {
            return nil
        }
        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              let idRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[idRange])
    }

    static func reportURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let configRoot: String
        if let configured = environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            configRoot = (configured as NSString).expandingTildeInPath
        } else {
            configRoot = (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
        }
        return URL(fileURLWithPath: configRoot)
            .appendingPathComponent("usage-data/report.html")
    }

    // MARK: - Subprocess

    private struct ProcessResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private struct FileSnapshot: Equatable {
        let modificationDate: Date?
        let size: UInt64?
    }

    private static func fileSnapshot(at url: URL) -> FileSnapshot? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return FileSnapshot(
            modificationDate: attributes[.modificationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.uint64Value
        )
    }

    private static func waitForFreshReport(
        at url: URL,
        previousSnapshot: FileSnapshot?,
        timeout: Duration
    ) async throws -> URL {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            if let currentSnapshot = fileSnapshot(at: url), currentSnapshot != previousSnapshot {
                return url
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw InsightsServiceError.reportTimedOut(url)
    }

    private static func stopBackgroundSession(
        _ sessionID: String,
        claudePath: String,
        cwd: URL
    ) async {
        _ = try? await runProcess(
            claudePath: claudePath,
            cwd: cwd,
            arguments: ["stop", sessionID],
            onChunk: { _ in }
        )
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
