import Testing
import Foundation
@testable import Skillbox

struct SkillsCLITests {
    @Test func shellLaunchWithGUIEventQueueInStandardInput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-process-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = root.appendingPathComponent("Harness.swift")
        let executable = root.appendingPathComponent("harness")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Skillbox/Services/SkillsCLI.swift")
        try """
        import Foundation
        import Darwin
        @main struct Harness {
            static func main() async throws {
                close(STDIN_FILENO)
                precondition(kqueue() == STDIN_FILENO)
                let result = try await SkillsCLI.runShellRaw("printf skillbox-stdout; printf skillbox-stderr >&2")
                precondition(result.exitCode == 0)
                precondition(result.combinedOutput.contains("skillbox-stdout"))
                precondition(result.combinedOutput.contains("skillbox-stderr"))
                print("GUI process launch passed")
            }
        }
        """.write(to: fixture, atomically: true, encoding: .utf8)
        func run(_ path: String, _ arguments: [String]) throws -> (Int32, String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }
        let build = try run("/usr/bin/xcrun", ["swiftc", source.path, fixture.path, "-o", executable.path])
        #expect(build.0 == 0, "\(build.1)")
        let result = try run(executable.path, [])
        #expect(result.0 == 0, "\(result.1)")
        #expect(result.1.contains("GUI process launch passed"))
    }

    @Test func addArgs_withoutSkill() {
        let opts = SkillsCLI.InstallOptions(source: "vercel-labs/agent-skills")
        #expect(SkillsCLI.addArgs(for: opts) == [
            "add", "vercel-labs/agent-skills",
            "-a", "claude-code",
            "-g", "--copy", "-y"
        ])
    }

    @Test func addArgs_skipsCopyWhenDisabled() {
        let opts = SkillsCLI.InstallOptions(
            source: "owner/repo",
            global: false,
            copyMode: false
        )
        #expect(SkillsCLI.addArgs(for: opts) == [
            "add", "owner/repo",
            "-a", "claude-code",
            "-y"
        ])
    }

    @Test func updateArgs() {
        #expect(SkillsCLI.updateArgs(skillName: "find-skills") == [
            "update", "find-skills", "-a", "claude-code", "-g", "-y"
        ])
    }

    @Test func removeArgs() {
        #expect(SkillsCLI.removeArgs(skillName: "find-skills") == [
            "remove", "find-skills", "-a", "claude-code", "-g", "-y"
        ])
    }

    @Test func shellQuote_leavesSafeCharsAlone() {
        #expect(SkillsCLI.shellQuote("vercel-labs/agent-skills") == "vercel-labs/agent-skills")
        #expect(SkillsCLI.shellQuote("--skill") == "--skill")
        #expect(SkillsCLI.shellQuote("path/to/thing.tar.gz") == "path/to/thing.tar.gz")
    }

    @Test func shellQuote_quotesSpacesAndShellMeta() {
        #expect(SkillsCLI.shellQuote("a b") == "'a b'")
        #expect(SkillsCLI.shellQuote("a$b") == "'a$b'")
        #expect(SkillsCLI.shellQuote("a;b") == "'a;b'")
    }

    @Test func shellQuote_escapesEmbeddedSingleQuote() {
        #expect(SkillsCLI.shellQuote("Mary's skill") == "'Mary'\\''s skill'")
    }

    @Test func shellQuote_emptyStringIsTwoQuotes() {
        #expect(SkillsCLI.shellQuote("") == "''")
    }
}
