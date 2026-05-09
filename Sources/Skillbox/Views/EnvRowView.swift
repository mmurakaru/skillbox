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

struct EnvRowView: View {
    let envVar: EnvVar
    let isSelected: Bool
    let showProjectName: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Binding var rowState: SkillRowView.RowState

    @State private var isHoveringRow = false
    @State private var isHoveringEdit = false
    @State private var isHoveringDelete = false

    var body: some View {
        ZStack {
            if rowState != .normal { normalContent.hidden() }
            if rowState == .confirmingDelete {
                confirmContent
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
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHoveringRow { return Color.primary.opacity(0.06) }
        return .clear
    }

    private var normalContent: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { envVar.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(envVar.key)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(envVar.isEnabled ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    EnvScopeBadge(scope: envVar.scope)
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
        let valuePart = envVar.value.isEmpty ? "(empty)" : "= \(envVar.value)"
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
        var lines = ["\(envVar.key) = \(envVar.value)"]
        if let desc = EnvVarCatalog.description(for: envVar.key) {
            lines.append(desc)
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
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovering.wrappedValue = hovering }
        }
    }

    private var confirmContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 18)

            Text("Delete ")
                .font(.system(size: 12)) +
            Text(envVar.key)
                .font(.system(size: 12, weight: .semibold, design: .monospaced)) +
            Text("?")
                .font(.system(size: 12))

            Spacer()

            Button("Cancel") { rowState = .normal }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)

            Button("Delete") {
                onDelete()
                rowState = .normal
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
}
