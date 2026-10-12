import SwiftUI

/// One Keychain-backed env secret. The value is read from the Keychain only on reveal or copy.
struct KeychainSecretRowView: View {
    let secretName: String
    let readValue: () throws -> String
    let onDelete: () -> Void
    let onError: (Error) -> Void

    @State private var revealedValue: String?
    @State private var isConfirmingDelete = false
    @State private var isHoveringRow = false
    @State private var isHoveringReveal = false
    @State private var isHoveringCopy = false
    @State private var isHoveringDelete = false

    var body: some View {
        ZStack {
            if isConfirmingDelete { normalContent.hidden() }
            if isConfirmingDelete { confirmDeleteContent } else { normalContent }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHoveringRow ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHoveringRow = hovering }
        }
    }

    private var normalContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: envRowLeadingControlWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(secretName)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    KeychainStorageBadge()
                    Spacer(minLength: 0)
                }
                Text("= \(revealedValue ?? "••••••••")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("\(secretName)\nsecret - stored in the login Keychain, not in settings.json")

            rowButton(
                systemName: revealedValue == nil ? "eye" : "eye.slash",
                isHovering: $isHoveringReveal,
                tint: .accentColor,
                help: revealedValue == nil ? "Reveal value" : "Hide value",
                action: toggleReveal
            )
            rowButton(
                systemName: "doc.on.doc",
                isHovering: $isHoveringCopy,
                tint: .accentColor,
                help: "Copy value",
                action: copyValue
            )
            // Keeps buttons in the same columns as settings-backed secret rows.
            Color.clear.frame(width: 22, height: 22)
            Color.clear.frame(width: 22, height: 22)
            rowButton(
                systemName: "trash",
                isHovering: $isHoveringDelete,
                tint: .red,
                help: "Delete from Keychain",
                action: { isConfirmingDelete = true }
            )
        }
    }

    private var confirmDeleteContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 18)
            Text("Delete ")
                .font(.system(size: 12)) +
            Text(secretName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced)) +
            Text(" from the Keychain?")
                .font(.system(size: 12))
            Spacer()
            Button("Cancel") { isConfirmingDelete = false }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            Button("Delete") {
                isConfirmingDelete = false
                onDelete()
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    private func toggleReveal() {
        if revealedValue != nil {
            revealedValue = nil
            return
        }
        do { revealedValue = try readValue() } catch { onError(error) }
    }

    private func copyValue() {
        do { SecretPasteboard.copyConcealed(try readValue()) } catch { onError(error) }
    }

    private func rowButton(
        systemName: String,
        isHovering: Binding<Bool>,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovering.wrappedValue ? tint : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering.wrappedValue ? tint.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovering.wrappedValue = hovering }
        }
    }
}

struct KeychainStorageBadge: View {
    var body: some View {
        Text("Keychain")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.green.opacity(0.35), lineWidth: 0.5))
    }
}
