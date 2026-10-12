import AppKit

/// Copies secret values to the clipboard marked as concealed, so clipboard history managers skip them.
@MainActor
enum SecretPasteboard {
    /// Pasteboard type defined by nspasteboard.org that clipboard managers treat as "do not record".
    static let concealedPasteboardType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    /// Long enough to paste once, short enough that a forgotten secret does not stay on the clipboard.
    static let clearDelay: Duration = .seconds(60)

    static func copyConcealed(_ value: String, to pasteboard: NSPasteboard = .general, clearAfter delay: Duration = clearDelay) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, concealedPasteboardType], owner: nil)
        pasteboard.setString(value, forType: .string)
        pasteboard.setString("", forType: concealedPasteboardType)
        let copiedChangeCount = pasteboard.changeCount

        Task {
            try? await Task.sleep(for: delay)
            clearIfUnchanged(pasteboard, since: copiedChangeCount)
        }
    }

    /// A newer copy by the user or another app changes the count, and that content must stay.
    static func clearIfUnchanged(_ pasteboard: NSPasteboard, since changeCount: Int) {
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.clearContents()
    }
}
