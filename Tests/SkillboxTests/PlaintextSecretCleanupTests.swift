import Foundation
import Testing

@testable import Skillbox

@MainActor
struct PlaintextSecretCleanupTests {
    private func makeCopy(value: String, fileName: String) -> EnvVar {
        EnvVar(
            key: "EXAMPLE_API_TOKEN", value: value, state: .enabled, scope: .userGlobal,
            fileURL: URL(fileURLWithPath: "/tmp/\(fileName)"), modifiedAt: Date(), isSecret: true)
    }

    @Test func run_withOneMismatchedCopy_removesNothing() async {
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

        await #expect(throws: KeychainSecretsModelError.keychainHoldsDifferentValue("EXAMPLE_API_TOKEN")) { try await cleanup.run() }
        #expect(!removedStaticHeader)
        #expect(removedCopies.isEmpty)
    }

    @Test func run_withMatchingCopies_removesHeaderAndEveryCopy() async throws {
        let copies = [makeCopy(value: "stored", fileName: "settings.json"), makeCopy(value: "stored", fileName: "settings.local.json")]
        var removedStaticHeader = false
        var removedCopies: [EnvVar] = []
        let cleanup = PlaintextSecretCleanup(
            plaintextCopies: copies,
            keychainHoldsSameValue: { $0.value == "stored" },
            removeStaticHeader: { removedStaticHeader = true },
            removePlaintextCopy: { removedCopies.append($0) }
        )

        try await cleanup.run()

        #expect(removedStaticHeader)
        #expect(removedCopies == copies)
    }

    @Test func run_failingAfterTheHeaderRemoval_listsWhatWasRemoved() async {
        struct ExampleRemovalError: LocalizedError {
            var errorDescription: String? { "settings.json is read-only." }
        }
        let copy = makeCopy(value: "stored", fileName: "settings.json")
        let cleanup = PlaintextSecretCleanup(
            plaintextCopies: [copy],
            keychainHoldsSameValue: { _ in true },
            removeStaticHeader: {},
            removePlaintextCopy: { _ in throw ExampleRemovalError() }
        )

        await #expect(throws: PlaintextSecretCleanupError.partiallyRemoved(removed: ["the static header"], reason: "settings.json is read-only.")) {
            try await cleanup.run()
        }
    }
}
