import Testing
import Foundation
@testable import Skillbox

/// Records every `security` invocation and replays canned results; never runs a real process.
final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Invocation: Equatable {
        var executablePath: String
        var arguments: [String]
        var standardInput: String?
    }

    private let lock = NSLock()
    private var recorded: [Invocation] = []
    var cannedResult = ProcessRunResult(exitCode: 0, standardOutput: "")
    /// Returned one per call before falling back to `cannedResult`.
    var cannedResultSequence: [ProcessRunResult] = []

    var invocations: [Invocation] { lock.withLock { recorded } }

    func run(executablePath: String, arguments: [String], standardInput: String?) throws -> ProcessRunResult {
        lock.withLock {
            recorded.append(Invocation(executablePath: executablePath, arguments: arguments, standardInput: standardInput))
            return cannedResultSequence.isEmpty ? cannedResult : cannedResultSequence.removeFirst()
        }
    }
}

/// In-memory Keychain used by model tests; `corruptsWrites` simulates a read-back mismatch.
final class InMemoryKeychainSecretStore: KeychainSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    var corruptsWrites = false
    private(set) var writeCount = 0

    init(values: [String: String] = [:]) { self.values = values }

    var storedValues: [String: String] { lock.withLock { values } }

    func secretNames() throws -> [String] { lock.withLock { values.keys.sorted() } }

    func readSecretValue(named name: String) throws -> String {
        guard let value = lock.withLock({ values[name] }) else { throw KeychainSecretError.secretNotFound(name) }
        return value
    }

    func writeSecretValue(_ value: String, named name: String) throws {
        lock.withLock {
            writeCount += 1
            values[name] = corruptsWrites ? value + "-corrupted" : value
        }
    }

    func deleteSecret(named name: String) throws { lock.withLock { _ = values.removeValue(forKey: name) } }
}

struct KeychainSecretStoreTests {
    @Test func writeSecretValue_sendsHexValueOnStandardInputOnly() throws {
        let runner = RecordingProcessRunner()
        let store = SystemKeychainSecretStore(processRunner: runner)

        try store.writeSecretValue("example-secret", named: "EXAMPLE_API_TOKEN")

        let invocation = try #require(runner.invocations.first)
        #expect(invocation.executablePath == "/usr/bin/security")
        #expect(invocation.arguments == ["-i"])
        let input = try #require(invocation.standardInput)
        #expect(!input.contains("example-secret"))
        #expect(input.contains("-X \"6578616d706c652d736563726574\""))
        #expect(input.contains("-s \"ai.skillbox.secret\" -a \"EXAMPLE_API_TOKEN\""))
        #expect(input.hasPrefix("add-generic-password -U "))
    }

    @Test func readSecretValue_stripsTrailingNewline() throws {
        let runner = RecordingProcessRunner()
        runner.cannedResult = ProcessRunResult(exitCode: 0, standardOutput: "example-secret\n")
        let store = SystemKeychainSecretStore(processRunner: runner)

        #expect(try store.readSecretValue(named: "EXAMPLE_API_TOKEN") == "example-secret")
        #expect(runner.invocations.first?.arguments == ["find-generic-password", "-s", "ai.skillbox.secret", "-a", "EXAMPLE_API_TOKEN", "-w"])
    }

    @Test func readSecretValue_missingItem_throwsNotFound() {
        let runner = RecordingProcessRunner()
        runner.cannedResult = ProcessRunResult(exitCode: 44, standardOutput: "")
        let store = SystemKeychainSecretStore(processRunner: runner)

        #expect(throws: KeychainSecretError.secretNotFound("EXAMPLE_API_TOKEN")) {
            try store.readSecretValue(named: "EXAMPLE_API_TOKEN")
        }
    }

    @Test func deleteSecret_missingItem_isNotAnError() throws {
        let runner = RecordingProcessRunner()
        runner.cannedResult = ProcessRunResult(exitCode: 44, standardOutput: "")
        try SystemKeychainSecretStore(processRunner: runner).deleteSecret(named: "EXAMPLE_API_TOKEN")
    }

    @Test func invalidNameOrValue_neverRunsSecurity() {
        let runner = RecordingProcessRunner()
        let store = SystemKeychainSecretStore(processRunner: runner)

        #expect(throws: KeychainSecretError.self) { try store.writeSecretValue("value", named: "BAD NAME; rm") }
        #expect(throws: KeychainSecretError.self) { try store.writeSecretValue("line one\nline two", named: "EXAMPLE_API_TOKEN") }
        #expect(throws: KeychainSecretError.self) { try store.writeSecretValue("", named: "EXAMPLE_API_TOKEN") }
        #expect(throws: KeychainSecretError.self) {
            try store.writeSecretValue(String(repeating: "a", count: KeychainSecretValidation.maximumValueByteCount + 1), named: "EXAMPLE_API_TOKEN")
        }
        #expect(runner.invocations.isEmpty)
    }

    @Test func readCommand_usesSystemSecurityTool() {
        #expect(SystemKeychainSecretStore.readCommand(forSecretNamed: "EXAMPLE_API_TOKEN")
            == "/usr/bin/security find-generic-password -s ai.skillbox.secret -a EXAMPLE_API_TOKEN -w")
    }
}

@MainActor
struct KeychainSecretsModelTests {
    private func makeEnvVar(key: String, value: String) -> EnvVar {
        EnvVar(key: key, value: value, state: .enabled, scope: .userGlobal,
               fileURL: URL(fileURLWithPath: "/tmp/settings.json"), modifiedAt: Date(), isSecret: true)
    }

    @Test func addSecret_storesAndListsName() throws {
        let keychain = InMemoryKeychainSecretStore()
        let model = KeychainSecretsModel(secretStore: keychain)

        try model.addSecret(named: "EXAMPLE_API_TOKEN", value: "abc")

        #expect(keychain.storedValues == ["EXAMPLE_API_TOKEN": "abc"])
        #expect(model.secretNames == ["EXAMPLE_API_TOKEN"])
    }

    @Test func addSecret_existingName_throwsWithoutWriting() {
        let keychain = InMemoryKeychainSecretStore(values: ["EXAMPLE_API_TOKEN": "old"])
        let model = KeychainSecretsModel(secretStore: keychain)

        #expect(throws: KeychainSecretsModelError.secretAlreadyExists("EXAMPLE_API_TOKEN")) {
            try model.addSecret(named: "EXAMPLE_API_TOKEN", value: "new")
        }
        #expect(keychain.storedValues["EXAMPLE_API_TOKEN"] == "old")
    }

    @Test func copyEnvSecret_readBackMismatch_removesNewItem() {
        let keychain = InMemoryKeychainSecretStore()
        keychain.corruptsWrites = true
        let model = KeychainSecretsModel(secretStore: keychain)

        #expect(throws: KeychainSecretsModelError.readBackMismatch("EXAMPLE_API_TOKEN")) {
            try model.copyEnvSecretToKeychain(makeEnvVar(key: "EXAMPLE_API_TOKEN", value: "abc"))
        }
        #expect(keychain.storedValues.isEmpty)
    }

    @Test func copyEnvSecret_sameValueAlreadyStored_doesNotRewrite() throws {
        let keychain = InMemoryKeychainSecretStore(values: ["EXAMPLE_API_TOKEN": "abc"])
        let model = KeychainSecretsModel(secretStore: keychain)

        try model.copyEnvSecretToKeychain(makeEnvVar(key: "EXAMPLE_API_TOKEN", value: "abc"))

        #expect(keychain.writeCount == 0)
        #expect(model.containsSecret(named: "EXAMPLE_API_TOKEN"))
    }

    @Test func copyEnvSecret_differentValueStored_throwsAndKeepsKeychainValue() {
        let keychain = InMemoryKeychainSecretStore(values: ["EXAMPLE_API_TOKEN": "other"])
        let model = KeychainSecretsModel(secretStore: keychain)

        #expect(throws: KeychainSecretsModelError.keychainHoldsDifferentValue("EXAMPLE_API_TOKEN")) {
            try model.copyEnvSecretToKeychain(makeEnvVar(key: "EXAMPLE_API_TOKEN", value: "abc"))
        }
        #expect(keychain.storedValues["EXAMPLE_API_TOKEN"] == "other")
    }

    @Test func keychainHoldsSameValue_comparesStoredValue() throws {
        let keychain = InMemoryKeychainSecretStore(values: ["EXAMPLE_API_TOKEN": "abc"])
        let model = KeychainSecretsModel(secretStore: keychain)
        model.reload()

        #expect(model.keychainHoldsSameValue(as: makeEnvVar(key: "EXAMPLE_API_TOKEN", value: "abc")))
        #expect(!model.keychainHoldsSameValue(as: makeEnvVar(key: "EXAMPLE_API_TOKEN", value: "changed")))
    }
}
