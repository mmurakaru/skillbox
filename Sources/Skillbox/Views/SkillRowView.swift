import SwiftUI

struct SkillRowView: View {
    let skill: Skill
    let isSelected: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Binding var rowState: RowState

    @State private var isHoveringRow = false
    @State private var isHoveringEdit = false
    @State private var isHoveringDelete = false

    enum RowState: Equatable {
        case normal
        case confirmingDelete
    }

    var body: some View {
        ZStack {
            if rowState != .normal {
                normalContent.hidden()
            }
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
            withAnimation(.easeOut(duration: 0.12)) {
                isHoveringRow = hovering
            }
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHoveringRow { return Color.primary.opacity(0.06) }
        return .clear
    }

    private var normalContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(skill.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(skill.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(skill.description)

            iconButton(
                systemName: "pencil",
                isHovering: $isHoveringEdit,
                tint: .accentColor,
                help: "Open in editor",
                action: onEdit
            )

            iconButton(
                systemName: "trash",
                isHovering: $isHoveringDelete,
                tint: .red,
                help: "Move to Trash",
                action: { rowState = .confirmingDelete }
            )
        }
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
            withAnimation(.easeOut(duration: 0.1)) {
                isHovering.wrappedValue = hovering
            }
        }
    }

    private var confirmContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 18)

            Text("Delete ")
                .font(.system(size: 12)) +
            Text(skill.name)
                .font(.system(size: 12, weight: .semibold)) +
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
