import AppKit
import Testing

@testable import Skillbox

@MainActor
struct SecretPasteboardTests {
    @Test func copyConcealed_clearsTheSecretAfterTheDelay() async {
        let pasteboard = NSPasteboard.withUniqueName()

        defer { pasteboard.releaseGlobally() }

        let pendingClear = SecretPasteboard.copyConcealed("example-secret", to: pasteboard, clearAfter: .milliseconds(50))

        #expect(pasteboard.string(forType: .string) == "example-secret")
        #expect(pasteboard.types?.contains(SecretPasteboard.concealedPasteboardType) == true)

        await pendingClear.value
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test func copyConcealed_keepsANewerCopy() async {
        let pasteboard = NSPasteboard.withUniqueName()

        defer { pasteboard.releaseGlobally() }

        let pendingClear = SecretPasteboard.copyConcealed("example-secret", to: pasteboard, clearAfter: .milliseconds(50))

        pasteboard.clearContents()
        pasteboard.setString("copied later", forType: .string)

        await pendingClear.value
        #expect(pasteboard.string(forType: .string) == "copied later")
    }
}
