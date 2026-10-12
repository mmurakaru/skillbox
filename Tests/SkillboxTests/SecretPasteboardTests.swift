import AppKit
import Testing
@testable import Skillbox

@MainActor
struct SecretPasteboardTests {
    @Test func copyConcealed_clearsTheSecretAfterTheDelay() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        SecretPasteboard.copyConcealed("example-secret", to: pasteboard, clearAfter: .milliseconds(50))
        #expect(pasteboard.string(forType: .string) == "example-secret")
        #expect(pasteboard.types?.contains(SecretPasteboard.concealedPasteboardType) == true)

        try await Task.sleep(for: .milliseconds(300))
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test func copyConcealed_keepsANewerCopy() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        SecretPasteboard.copyConcealed("example-secret", to: pasteboard, clearAfter: .milliseconds(50))
        pasteboard.clearContents()
        pasteboard.setString("copied later", forType: .string)

        try await Task.sleep(for: .milliseconds(300))
        #expect(pasteboard.string(forType: .string) == "copied later")
    }
}
