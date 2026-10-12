import SwiftUI

/// One Keychain-backed env secret. The value is read from the Keychain only on reveal or copy.
struct KeychainSecretRowView: View {
    let secretName: String
    let readValue: () async throws -> String
    let onDelete: () -> Void
    let onConnectToMCPServer: () -> Void
    let onError: (Error) -> Void

    @State private var revealedValue: String?
    @State private var isConfirmingDelete = false
    @State private var isHoveringRow = false

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
                    Spacer(minLength: 0)
                }
                HStack(spacing: 4) {
                    KeychainStorageBadge()
                    Text("= \(revealedValue ?? "••••••••")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(
                "\(secretName)\nsecret - stored in the login Keychain, not in settings.json or agent environments\nreadable without a prompt by processes running as you through the security tool"
            )

            RowIconActionButton(
                systemName: revealedValue == nil ? "eye" : "eye.slash",
                tint: .accentColor,
                label: revealedValue == nil ? "Reveal value" : "Hide value",
                action: toggleReveal
            )
            RowIconActionButton(
                systemName: "doc.on.doc",
                tint: .accentColor,
                label: "Copy value",
                action: copyValue
            )
            RowIconActionButton(
                systemName: "point.3.connected.trianglepath.dotted",
                tint: .accentColor,
                label: "Connect to an MCP server",
                action: onConnectToMCPServer
            )
            // Keeps buttons in the same columns as settings-backed secret rows.
            Color.clear.frame(width: 22, height: 22)
            RowIconActionButton(
                systemName: "trash",
                tint: .red,
                label: "Delete from Keychain",
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
                .font(.system(size: 12))
                + Text(secretName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                + Text(" from the Keychain?")
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

        Task {
            do { revealedValue = try await readValue() } catch { onError(error) }
        }
    }

    private func copyValue() {
        Task {
            do { SecretPasteboard.copyConcealed(try await readValue()) } catch { onError(error) }
        }
    }

}

struct KeychainStorageBadge: View {
    var body: some View {
        Text("Keychain")
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.green)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.green.opacity(0.35), lineWidth: 0.5))
    }
}
