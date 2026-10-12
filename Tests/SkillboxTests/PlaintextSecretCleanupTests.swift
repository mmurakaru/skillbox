import Foundation
import Testing

@testable import Skillbox

struct PlaintextSecretCleanupTests {
    private func makeCopy(value: String, fileName: String) -> EnvVar {
        EnvVar(
            key: "EXAMPLE_API_TOKEN", value: value, state: .enabled, scope: .userGlobal,
            fileURL: URL(fileURLWithPath: "/tmp/\(fileName)"), modifiedAt: Date(), isSecret: true)
    }

    @Test func run_withOneMismatchedCopy_removesNothing() {
        let matchingCopy = makeCopy(value: "stored", fileName: "settings.json")
        let mismatchedCopy = makeCopy(value: "changed", fileName: "settings.local.json")
        var removedStaticHeader = false
        var removedCopies: [EnvVar] = []
        let cleanup = PlaintextSecretCleanup(
            plaintextCopies: [matchingCopy, mismatchedCopy],
            keychainHoldsSameValue: { $0.value == "stored" },
            removeStaticHeader: { removedStaticHeader = true },
            removePlaintextCopy: { removedCopies.append($0) }
        )

        #expect(throws: KeychainSecretsModelError.keychainHoldsDifferentValue("EXAMPLE_API_TOKEN")) { try cleanup.run() }
        #expect(!removedStaticHeader)
        #expect(removedCopies.isEmpty)
    }

    @Test func run_withMatchingCopies_removesHeaderAndEveryCopy() throws {
        let copies = [makeCopy(value: "stored", fileName: "settings.json"), makeCopy(value: "stored", fileName: "settings.local.json")]
        var removedStaticHeader = false
        var removedCopies: [EnvVar] = []
        let cleanup = PlaintextSecretCleanup(
            plaintextCopies: copies,
            keychainHoldsSameValue: { $0.value == "stored" },
            removeStaticHeader: { removedStaticHeader = true },
            removePlaintextCopy: { removedCopies.append($0) }
        )

        try cleanup.run()

        #expect(removedStaticHeader)
        #expect(removedCopies == copies)
    }
}
