import AppKit

/// Copies secret values to the clipboard marked as concealed, so clipboard history managers skip them.
enum SecretPasteboard {
    /// Pasteboard type defined by nspasteboard.org that clipboard managers treat as "do not record".
    static let concealedPasteboardType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    static func copyConcealed(_ value: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, concealedPasteboardType], owner: nil)
        pasteboard.setString(value, forType: .string)
        pasteboard.setString("", forType: concealedPasteboardType)
    }
}
