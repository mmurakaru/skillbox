import Foundation
import Security

/// Keychain service under which Skillbox stores env secrets; the account is the variable name.
let keychainSecretServiceName = "ai.skillbox.secret"

enum KeychainSecretError: Error, LocalizedError, Equatable {
    case invalidSecretName(String)
    case invalidSecretValue(String)
    case secretNotFound(String)
    case securityToolFailed(operation: String, exitCode: Int32)
    case keychainListFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidSecretName(let name):
            "Keychain secret name '\(name)' must start with a letter or underscore and contain only letters, digits, and underscores."
        case .invalidSecretValue(let reason):
            "Keychain secret value rejected: \(reason)"
        case .secretNotFound(let name):
            "Keychain secret '\(name)' was not found."
        case .securityToolFailed(let operation, let exitCode):
            "Keychain \(operation) failed: security exited with status \(exitCode)."
        case .keychainListFailed(let status):
            "Keychain secrets could not be listed: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))"
        }
    }
}

/// Validates env secret names and values before they reach the Keychain or a helper command.
enum KeychainSecretValidation {
    /// Upper bound that keeps a hex-encoded write command inside one `security -i` input line.
    static let maximumValueByteCount = 1_500

    static func validateName(_ name: String) throws {
        guard name.wholeMatch(of: /[A-Za-z_][A-Za-z0-9_]*/) != nil else {
            throw KeychainSecretError.invalidSecretName(name)
        }
    }

    static func validateValue(_ value: String) throws {
        guard !value.isEmpty else { throw KeychainSecretError.invalidSecretValue("the value is empty") }
        guard value.utf8.count <= maximumValueByteCount else {
            throw KeychainSecretError.invalidSecretValue("the value is longer than \(maximumValueByteCount) bytes")
        }
        guard !value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw KeychainSecretError.invalidSecretValue("the value contains a newline or another control character")
        }
    }
}

/// Reads and writes env secrets in the login Keychain. Tests use an in-memory fake.
protocol KeychainSecretStoring: Sendable {
    func secretNames() throws -> [String]
    func readSecretValue(named name: String) throws -> String
    func writeSecretValue(_ value: String, named name: String) throws
    func deleteSecret(named name: String) throws
}

struct ProcessRunResult: Equatable, Sendable {
    var exitCode: Int32
    var standardOutput: String
}

/// Runs an external tool with arguments and optional standard input. Tests use a recording fake.
protocol ProcessRunning: Sendable {
    func run(executablePath: String, arguments: [String], standardInput: String?) throws -> ProcessRunResult
}

struct SystemProcessRunner: ProcessRunning {
    func run(executablePath: String, arguments: [String], standardInput: String?) throws -> ProcessRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        let inputPipe = Pipe()
        process.standardInput = standardInput == nil ? FileHandle.nullDevice : inputPipe
        // A tool that exits before reading stdin would otherwise kill the app with SIGPIPE.
        _ = fcntl(inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try process.run()
        if let standardInput {
            try inputPipe.fileHandleForWriting.write(contentsOf: Data(standardInput.utf8))
            try inputPipe.fileHandleForWriting.close()
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessRunResult(exitCode: process.terminationStatus, standardOutput: String(decoding: output, as: UTF8.self))
    }
}

/// Uses Apple's signed `security` tool so helpers read items without prompts after Skillbox's ad-hoc signature changes.
struct SystemKeychainSecretStore: KeychainSecretStoring {
    static let securityToolPath = "/usr/bin/security"

    var processRunner: any ProcessRunning = SystemProcessRunner()

    /// Shell command a harness helper runs to print one secret's value.
    static func readCommand(forSecretNamed name: String) -> String {
        "\(securityToolPath) find-generic-password -s \(keychainSecretServiceName) -a \(name) -w"
    }

    func secretNames() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainSecretServiceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw KeychainSecretError.keychainListFailed(status)
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    func readSecretValue(named name: String) throws -> String {
        try KeychainSecretValidation.validateName(name)
        let result = try processRunner.run(
            executablePath: Self.securityToolPath,
            arguments: ["find-generic-password", "-s", keychainSecretServiceName, "-a", name, "-w"],
            standardInput: nil
        )
        if result.exitCode == Self.itemNotFoundExitCode { throw KeychainSecretError.secretNotFound(name) }
        guard result.exitCode == 0 else {
            throw KeychainSecretError.securityToolFailed(operation: "read", exitCode: result.exitCode)
        }
        return String(result.standardOutput.dropLast(result.standardOutput.hasSuffix("\n") ? 1 : 0))
    }

    /// Sends the command on stdin with a hex password, so the value never appears in a process argument list.
    func writeSecretValue(_ value: String, named name: String) throws {
        try KeychainSecretValidation.validateName(name)
        try KeychainSecretValidation.validateValue(value)
        let hexValue = value.utf8.map { String(format: "%02x", $0) }.joined()
        let command = "add-generic-password -U -s \"\(keychainSecretServiceName)\" -a \"\(name)\" -l \"Skillbox secret: \(name)\" -X \"\(hexValue)\"\n"
        let result = try processRunner.run(executablePath: Self.securityToolPath, arguments: ["-i"], standardInput: command)
        guard result.exitCode == 0 else {
            throw KeychainSecretError.securityToolFailed(operation: "write", exitCode: result.exitCode)
        }
    }

    func deleteSecret(named name: String) throws {
        try KeychainSecretValidation.validateName(name)
        let result = try processRunner.run(
            executablePath: Self.securityToolPath,
            arguments: ["delete-generic-password", "-s", keychainSecretServiceName, "-a", name],
            standardInput: nil
        )
        guard result.exitCode == 0 || result.exitCode == Self.itemNotFoundExitCode else {
            throw KeychainSecretError.securityToolFailed(operation: "delete", exitCode: result.exitCode)
        }
    }

    /// `security` exits with errSecItemNotFound (-25300) truncated to 44.
    private static let itemNotFoundExitCode: Int32 = 44
}
