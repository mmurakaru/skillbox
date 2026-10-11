import Foundation
import Security
import Testing
@testable import Skillbox

struct TypeSafeCredentialTests {
    @Test func startupReadSuppressesDialogsAndRestoresPreviousInteractionState() throws {
        var interaction: Bool = true
        var changes: [Bool] = []
        let credentials = TypeSafeCredentials(copyMatching: { query in
            #expect(interaction == false)
            #expect(query[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUIFail as String)
            #expect(query[kSecAttrService as String] as? String == "ai.skillbox.typesafe")
            return (errSecSuccess, Data("fixture-key".utf8))
        }, getInteraction: { (errSecSuccess, interaction) }, setInteraction: { value in
            interaction = value
            changes.append(value)
            return errSecSuccess
        })
        #expect(try credentials.readAPIKey() == "fixture-key")
        #expect(changes == [false, true])
        #expect(interaction == true)
    }

    @Test func failedStartupReadRestoresStateAndKeepsCredentialProtected() {
        var interaction: Bool = true
        let credentials = TypeSafeCredentials(copyMatching: { _ in (errSecInteractionNotAllowed, nil) },
            getInteraction: { (errSecSuccess, interaction) }, setInteraction: { interaction = $0; return errSecSuccess })
        #expect(throws: (any Error).self) { try credentials.readAPIKey() }
        #expect(interaction == true)
    }

    @Test func inabilityToDisableDialogsDoesNotAttemptCredentialRead() {
        var reads = 0
        let credentials = TypeSafeCredentials(copyMatching: { _ in reads += 1; return (errSecSuccess, nil) },
            getInteraction: { (errSecSuccess, true) }, setInteraction: { _ in errSecAuthFailed })
        #expect(throws: (any Error).self) { try credentials.readAPIKey() }
        #expect(reads == 0)
    }

    @MainActor @Test func startupNeedsNoPermissionButExplicitUnlockCanRequestIt() {
        var requests: [Bool] = []
        let settings = TypeSafeSettings(readKey: { allowPrompt in
            requests.append(allowPrompt)
            if !allowPrompt { throw NSError(domain: "Fixture", code: Int(errSecInteractionNotAllowed)) }
            return "fixture-key"
        })
        #expect(requests == [false])
        #expect(settings.apiKey.isEmpty)
        #expect(settings.needsUnlock)
        settings.unlockSavedAPIKey()
        #expect(requests == [false, true])
        #expect(settings.apiKey == "fixture-key")
        #expect(!settings.needsUnlock)
        #expect(settings.lastError == nil)
    }

    @Test func missingKeyAndExplicitReadPreserveExistingInteractionPolicy() throws {
        let credentials = TypeSafeCredentials(copyMatching: { query in
            #expect(query[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUIAllow as String)
            return (errSecItemNotFound, nil)
        }, getInteraction: { Issue.record("Explicit reads must not change global interaction policy"); return (errSecSuccess, true) },
        setInteraction: { _ in Issue.record("Explicit reads must not change global interaction policy"); return errSecSuccess })
        #expect(try credentials.readAPIKey(allowPrompt: true).isEmpty)
    }
}
