import Darwin
import Foundation

// swiftlint:disable no_untyped_dictionaries - JSON trust boundary: parses JSON printed by another tool.

/// Reads quota windows through Claude's trusted CLI without accessing its foreign Keychain entry.
struct ClaudeCLIUsageReader: Sendable {
    struct Identity: Equatable, Sendable {
        let email: String?
        let accountID: String?
        let organizationID: String?
        let plan: String?
    }

    let commandRunner: @Sendable ([String]) async throws -> Data
    static let usageArguments = [
        "-p", "/usage", "--strict-mcp-config", "--tools", "", "--no-session-persistence",
        "--settings", "{\"remoteControlAtStartup\":false,\"disableAllHooks\":true}",
    ]

    static func fetchInstalledCLIUsage() async throws -> ProviderUsageSnapshot? {
        guard case .resolved(let path) = ClaudeBinaryLocator.resolve(override: UserDefaults.standard.string(forKey: "claudeCommand")) else {
            return nil
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SkillboxClaudeUsage-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = Self(commandRunner: { arguments in
            try await runCommand(path: path, directory: directory, arguments: arguments)
        })

        return try await reader.fetchUsage()
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        let before = try Self.decodeIdentity(await commandRunner(["auth", "status"]))
        var report = String(decoding: try await commandRunner(Self.usageArguments), as: UTF8.self)

        // A cold CLI can return insights before its quota request completes. Retry once, never infer quotas.
        if (try? Self.decodeReport(report, identity: before)) == nil {
            report = String(decoding: try await commandRunner(Self.usageArguments), as: UTF8.self)
        }

        let after = try Self.decodeIdentity(await commandRunner(["auth", "status"]))

        guard before == after else {
            throw UsageFetchError.unavailable(
                "Claude Code account changed while reading usage. Refresh to read the newly connected account.")
        }

        return try Self.decodeReport(report, identity: before)
    }

    static func decodeIdentity(_ data: Data) throws -> Identity {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["loggedIn"] as? Bool == true, json["authMethod"] as? String == "claude.ai"
        else {
            throw UsageFetchError.unavailable("Claude Code has no subscription sign-in. Run claude auth login, then refresh.")
        }

        return Identity(
            email: json["email"] as? String, accountID: json["accountId"] as? String,
            organizationID: json["orgId"] as? String, plan: ProviderUsageIdentity.planLabel(json["subscriptionType"] as? String))
    }

    /// Only anchored Current session/week rows are quotas; insight percentages are local activity statistics.
    static func decodeReport(_ report: String, identity: Identity, now: Date = Date()) throws -> ProviderUsageSnapshot {
        let regex = try NSRegularExpression(
            pattern: #"^Current (session|week(?: \(([^)]+)\))?):\s*([0-9]+(?:\.[0-9]+)?)% (used|left)(?:\s*[·|]\s*resets (.+))?$"#,
            options: [.caseInsensitive])
        var windows: [ProviderUsageWindow] = []

        for line in report.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)

            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
            func field(_ index: Int) -> String? {
                Range(match.range(at: index), in: line).map { String(line[$0]) }
            }
            guard let percent = field(3).flatMap(Double.init), percent.isFinite, (0...100).contains(percent) else { continue }
            let scope = field(2)
            let label =
                field(1)?.lowercased() == "session"
                ? "Current session"
                : scope.map { $0.lowercased() == "all models" ? "Weekly limit" : "\($0) weekly limit" } ?? "Weekly limit"

            guard !windows.contains(where: { $0.label == label }) else { continue }
            windows.append(
                .init(
                    label: label, usedPercent: field(4)?.lowercased() == "left" ? 100 - percent : percent,
                    resetsAt: field(5).flatMap { parseResetDate($0, now: now) }))
        }
        guard !windows.isEmpty else {
            throw UsageFetchError.unavailable(
                "Claude Code did not report quota percentages for this account. Check /usage in Claude Code or add a dashboard snapshot.")
        }

        return .init(provider: .claude, plan: identity.plan, windows: windows, updatedAt: now, source: .live, accountEmail: identity.email)
    }

    private static func parseResetDate(_ text: String, now: Date) -> Date? {
        let regex = try? NSRegularExpression(pattern: #"^(.+) \(([^)]+)\)$"#)
        let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        let zone = match.flatMap { Range($0.range(at: 2), in: text) }.flatMap { TimeZone(identifier: String(text[$0])) }
        let dateText = match.flatMap { Range($0.range(at: 1), in: text) }.map { String(text[$0]) } ?? text
        var calendar = Calendar(identifier: .gregorian)

        calendar.timeZone = zone ?? .current
        let formatter = DateFormatter()

        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        let year = calendar.component(.year, from: now)

        for format in ["MMM d 'at' h:mma yyyy", "MMM d 'at' ha yyyy"] {
            formatter.dateFormat = format

            if let date = formatter.date(from: "\(dateText) \(year)") {
                return date.timeIntervalSince(now) < -180 * 86400 ? calendar.date(byAdding: .year, value: 1, to: date) : date
            }
        }

        return nil
    }

    /// Bounded, cancellable read-only subprocess; output is private and deleted after every probe.
    private static func runCommand(path: String, directory: URL, arguments: [String]) async throws -> Data {
        let worker = Task.detached {
            let task = Process()

            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = arguments
            task.currentDirectoryURL = directory
            var environment = ProcessInfo.processInfo.environment

            environment["PATH"] = ClaudeBinaryLocator.pathDirs().joined(separator: ":")
            task.environment = environment
            let outputURL = directory.appendingPathComponent(UUID().uuidString)

            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let output = try FileHandle(forWritingTo: outputURL)

            defer {
                try? output.close()
                try? FileManager.default.removeItem(at: outputURL)
            }
            task.standardInput = FileHandle.nullDevice
            task.standardOutput = output
            task.standardError = FileHandle.nullDevice
            try task.run()
            defer {
                if task.isRunning {
                    kill(task.processIdentifier, SIGKILL)
                    task.waitUntilExit()
                }
            }
            let deadline = Date().addingTimeInterval(arguments == ["auth", "status"] ? 10 : 30)

            while task.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else {
                    throw UsageFetchError.unavailable("Claude Code usage timed out. Try refreshing again.")
                }
                let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0

                guard size < 1_048_576 else { throw UsageFetchError.invalidResponse }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard task.terminationStatus == 0 else {
                throw UsageFetchError.unavailable("Claude Code could not read usage. Check claude auth status and /usage in your terminal.")
            }

            return try Data(contentsOf: outputURL)
        }

        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
}
