import SwiftUI

struct EnvScopeBadge: View {
    let scope: EnvScope

    var body: some View {
        Text(scope.shortLabel)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color.opacity(0.35), lineWidth: 0.5)
            )
    }

    private var color: Color {
        switch scope {
        case .userGlobal: .purple
        case .project: .blue
        case .projectLocal: .orange
        }
    }
}

/// Shared width of the leading switch or icon so names line up across settings and Keychain rows.
let envRowLeadingControlWidth: CGFloat = 36

struct EnvRowView: View {
    let envVar: EnvVar
    let isSelected: Bool
    let showProjectName: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSetSecretMark: (Bool) -> Void
    /// Names only: values are read on explicit actions, so removal re-checks that the stored value matches.
    let hasKeychainSecretWithSameName: Bool
    let onCopyToKeychain: () -> Void
    /// Removes the settings.json and stash copy after the caller verifies the Keychain value matches.
    let onRemovePlaintextCopy: () -> Void

    @Binding var rowState: SkillRowView.RowState
    /// Owned by the list so keyboard toggles reach the same confirmation as the switch.
    @Binding var isConfirmingSecretDisable: Bool

    @State private var isHoveringRow = false
    @State private var isHoveringEdit = false
    @State private var isHoveringDelete = false
    @State private var isHoveringReveal = false
    @State private var isHoveringCopy = false
    @State private var isSecretValueRevealed = false
    @State private var isHoveringKeychain = false
    @State private var isConfirmingPlaintextRemoval = false

    private static let maskedSecretValue = "••••••••"

    var body: some View {
        ZStack {
            if rowState != .normal || isConfirmingSecretDisable || isConfirmingPlaintextRemoval { normalContent.hidden() }
            if rowState == .confirmingDelete {
                confirmContent
            } else if isConfirmingSecretDisable {
                confirmSecretDisableContent
            } else if isConfirmingPlaintextRemoval {
                confirmPlaintextRemovalContent
            } else {
                normalContent
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHoveringRow = hovering }
        }
        .contextMenu { secretMarkMenu }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHoveringRow { return Color.primary.opacity(0.06) }
        return .clear
    }

    @ViewBuilder
    private var secretMarkMenu: some View {
        if EnvSecretDetection.nameLooksSecret(envVar.key) {
            Text("Secret (detected from its name)")
        } else if envVar.isSecret {
            Button("Unmark as Secret") { onSetSecretMark(false) }
        } else if !envVar.isEnabled {
            Text("Enable to mark as secret")
        } else if envVar.scope.isSharedWithVersionControl {
            Text("Move to the local scope to mark as secret")
        } else {
            Button("Mark as Secret") { onSetSecretMark(true) }
        }
    }

    private var normalContent: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { envVar.isEnabled },
                set: { _ in
                    if envVar.isSecret && envVar.isEnabled {
                        isConfirmingSecretDisable = true
                    } else {
                        onToggle()
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .frame(width: envRowLeadingControlWidth)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(envVar.key)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(envVar.isEnabled ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    EnvScopeBadge(scope: envVar.scope)
                    if envVar.isSecret && hasKeychainSecretWithSameName {
                        KeychainStorageBadge()
                            .help("The login Keychain has a secret with this name")
                    } else if envVar.isSecret {
                        Image(systemName: "key.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Secret")
                    }
                    if envVar.isSecret && envVar.scope.isSharedWithVersionControl {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Secret in a shared project file")
                    }
                    Spacer(minLength: 0)
                }
                Text(secondaryLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(envVar.isEnabled ? 1.0 : 0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(helpText)

            if envVar.isSecret {
                iconButton(
                    systemName: isSecretValueRevealed ? "eye.slash" : "eye",
                    isHovering: $isHoveringReveal,
                    tint: .accentColor,
                    help: isSecretValueRevealed ? "Hide value" : "Reveal value",
                    action: { isSecretValueRevealed.toggle() }
                )
                iconButton(
                    systemName: "doc.on.doc",
                    isHovering: $isHoveringCopy,
                    tint: .accentColor,
                    help: "Copy value",
                    action: { SecretPasteboard.copyConcealed(envVar.value) }
                )
                iconButton(
                    systemName: hasKeychainSecretWithSameName ? "xmark.bin" : "key.horizontal",
                    isHovering: $isHoveringKeychain,
                    tint: hasKeychainSecretWithSameName ? .orange : .green,
                    help: hasKeychainSecretWithSameName ? "Remove plaintext copy after checking the Keychain holds the same value. Claude Code then stops getting it as an env var, so connect it to an MCP server first if a server needs it." : "Copy to Keychain",
                    action: {
                        if hasKeychainSecretWithSameName {
                            isConfirmingPlaintextRemoval = true
                        } else {
                            onCopyToKeychain()
                        }
                    }
                )
            }

            if envVar.isEnabled {
                iconButton(
                    systemName: "pencil",
                    isHovering: $isHoveringEdit,
                    tint: .accentColor,
                    help: "Open settings.json in editor",
                    action: onEdit
                )
            } else {
                Color.clear.frame(width: 22, height: 22)
            }

            iconButton(
                systemName: "trash",
                isHovering: $isHoveringDelete,
                tint: .red,
                help: "Remove permanently",
                action: { rowState = .confirmingDelete }
            )
        }
    }

    private var secondaryLine: String {
        let valuePart: String
        if envVar.value.isEmpty {
            valuePart = "(empty)"
        } else if envVar.isSecret && !isSecretValueRevealed {
            valuePart = "= \(Self.maskedSecretValue)"
        } else {
            valuePart = "= \(envVar.value)"
        }
        if showProjectName {
            switch envVar.scope {
            case .userGlobal:
                return valuePart
            case .project(let name, _), .projectLocal(let name, _):
                return "[\(name)] \(valuePart)"
            }
        }
        return valuePart
    }

    private var helpText: String {
        var lines = [envVar.isSecret ? envVar.key : "\(envVar.key) = \(envVar.value)"]
        if envVar.isSecret {
            lines.append("secret - value hidden; env values reach every process Claude Code starts")
        }
        if envVar.isSecret && envVar.scope.isSharedWithVersionControl {
            lines.append("this file is meant for version control - move the secret to the local scope")
        }
        if let catalogDescription = EnvVarCatalog.description(for: envVar.key) {
            lines.append(catalogDescription)
        }
        switch envVar.scope {
        case .userGlobal:
            lines.append("scope: User Global")
        case .project(_, let path):
            lines.append("project: \(path)")
        case .projectLocal(_, let path):
            lines.append("project (local): \(path)")
        }
        if !envVar.isEnabled {
            lines.append("disabled - value preserved in skillbox-env-stash.json")
        }
        return lines.joined(separator: "\n")
    }

    private func iconButton(
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

    private var confirmContent: some View {
        confirmationRow(
            verb: "Delete",
            detail: "?",
            confirmTint: .red,
            onCancel: { rowState = .normal },
            onConfirm: {
                onDelete()
                rowState = .normal
            }
        )
    }

    private var confirmSecretDisableContent: some View {
        confirmationRow(
            verb: "Disable",
            detail: "? Its value is removed, not stashed.",
            confirmTint: .orange,
            onCancel: { isConfirmingSecretDisable = false },
            onConfirm: {
                onToggle()
                isConfirmingSecretDisable = false
            }
        )
    }

    private var confirmPlaintextRemovalContent: some View {
        confirmationRow(
            verb: "Remove",
            detail: " from settings.json? Claude Code loses it.",
            confirmTint: .orange,
            onCancel: { isConfirmingPlaintextRemoval = false },
            onConfirm: {
                onRemovePlaintextCopy()
                isConfirmingPlaintextRemoval = false
            }
        )
    }

    private func confirmationRow(
        verb: String,
        detail: String,
        confirmTint: Color,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 18)

            Text("\(verb) ")
                .font(.system(size: 12)) +
            Text(envVar.key)
                .font(.system(size: 12, weight: .semibold, design: .monospaced)) +
            Text(detail)
                .font(.system(size: 12))

            Spacer()

            Button("Cancel", action: onCancel)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)

            Button(verb, action: onConfirm)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(confirmTint)
        }
    }
}
