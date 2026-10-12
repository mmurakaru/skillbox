import Testing
import Foundation
@testable import Skillbox

struct EnvSecretDetectionTests {
    @Test(arguments: ["EXAMPLE_API_TOKEN", "service_api_key", "DB_PASSWORD", "CLIENT_SECRET", "ANTHROPIC_AUTH_TOKEN"])
    func nameLooksSecret_credentialNames_areSecret(name: String) {
        #expect(EnvSecretDetection.nameLooksSecret(name))
    }

    @Test(arguments: ["CLAUDE_CODE_DISABLE_THINKING", "API_TIMEOUT_MS", "EXAMPLE_BASE_URL"])
    func nameLooksSecret_plainNames_areNotSecret(name: String) {
        #expect(!EnvSecretDetection.nameLooksSecret(name))
    }

    @Test func nameLooksSecret_documentedNonCredentialCatalogVar_isNotSecret() {
        #expect(!EnvSecretDetection.nameLooksSecret("CLAUDE_CODE_MAX_OUTPUT_TOKENS"))
    }

    @Test func isSecret_markedName_isSecretEvenWithoutMarker() {
        #expect(EnvSecretDetection.isSecret(key: "DATABASE_URL", markedSecretNames: ["DATABASE_URL"]))
        #expect(!EnvSecretDetection.isSecret(key: "DATABASE_URL", markedSecretNames: []))
    }

    @Test func secretMarksFile_roundTripsNames() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-secret-marks-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let marksFile = EnvSecretMarksFile(fileURL: fileURL)

        #expect(marksFile.load().isEmpty)
        try marksFile.save(["B_NAME", "A_NAME"])
        #expect(marksFile.load() == ["A_NAME", "B_NAME"])
    }
}
