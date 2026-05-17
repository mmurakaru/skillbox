import SwiftUI

struct SkillRowView: View {
    let skill: Skill
    let isSelected: Bool
    let overrideState: SkillOverride
    let isSyncing: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSetOverride: ((SkillOverride) -> Void)?
    let onSync: (() -> Void)?
    let onAdopt: (() -> Void)?

    @Binding var rowState: RowState

    @State private var isHoveringRow = false
    @State private var isHoveringEdit = false
    @State private var isHoveringDelete = false
    @State private var isHoveringSync = false
    @State private var isHoveringOverride = false
    @State private var isHoveringAdopt = false
    @State private var showOverrideMenu = false

    init(
        skill: Skill,
        isSelected: Bool,
        overrideState: SkillOverride = .on,
        isSyncing: Bool = false,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSetOverride: ((SkillOverride) -> Void)? = nil,
        onSync: (() -> Void)? = nil,
        onAdopt: (() -> Void)? = nil,
        rowState: Binding<RowState>
    ) {
        self.skill = skill
        self.isSelected = isSelected
        self.overrideState = overrideState
        self.isSyncing = isSyncing
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onSetOverride = onSetOverride
        self.onSync = onSync
        self.onAdopt = onAdopt
        self._rowState = rowState
    }

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
                HStack(spacing: 4) {
                    Text(skill.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if claudeBlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                            .help(claudeBlockedTooltip)
                    }
                    if let handle = skill.authorHandle {
                        authorChip(handle: handle)
                    }
                }
                Text(skill.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(skill.description)

            overrideMenu

            syncControl

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

    private func authorChip(handle: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "person.fill")
                .font(.system(size: 8, weight: .semibold))
            Text("@\(handle)")
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.12))
        )
        .help(authorChipTooltip)
    }

    private var authorChipTooltip: String {
        guard let p = skill.provenance else { return "" }
        let suffix = p.skill.map { " (\($0))" } ?? ""
        return "Tracked from \(p.source)\(suffix)"
    }

    @ViewBuilder
    private var overrideMenu: some View {
        if let onSetOverride {
            Button(action: { showOverrideMenu = true }) {
                Image(systemName: overrideState.sfSymbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(overrideForeground)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isHoveringOverride ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.1)) {
                    isHoveringOverride = hovering
                }
            }
            .popover(isPresented: $showOverrideMenu, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(SkillOverride.allCases, id: \.self) { state in
                        Button {
                            onSetOverride(state)
                            showOverrideMenu = false
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: state.sfSymbol)
                                    .font(.system(size: 11))
                                    .frame(width: 16)
                                Text(state.displayLabel)
                                    .font(.system(size: 12))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .disabled(state == overrideState)
                        .foregroundStyle(state == overrideState ? Color.secondary : Color.primary)
                    }
                }
                .padding(.vertical, 4)
                .frame(width: 170)
            }
            .help(overrideMenuTooltip)
        }
    }

    private var overrideMenuTooltip: String {
        let base = "Listing visibility: \(overrideState.displayLabel) — \(overrideState.helpText)"
        if skill.authorLocked {
            return base + " (Also locked by author in the skill file.)"
        }
        return base
    }

    private var overrideForeground: Color {
        if overrideState != .on { return .accentColor }
        return isHoveringOverride ? .accentColor : .secondary
    }

    /// Orange badge appears only when the *frontmatter* blocks Claude and the override icon
    /// wouldn't already show that (i.e. when the override is at its default `.on`).
    /// When the override is user-only/off, the override icon already shows a lock/slash;
    /// adding the orange badge there would be visual duplication.
    private var claudeBlocked: Bool {
        skill.authorLocked && overrideState == .on
    }

    private var claudeBlockedTooltip: String {
        "Locked by author (disable-model-invocation: true). Claude can't auto-invoke this skill regardless of override."
    }

    @ViewBuilder
    private var syncControl: some View {
        if isSyncing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 22, height: 22)
        } else if skill.provenance != nil, let onSync {
            Button(action: onSync) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isHoveringSync ? Color.accentColor : Color.secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isHoveringSync ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                    if skill.provenance?.hasUpdate == true {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .offset(x: -2, y: 2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.1)) {
                    isHoveringSync = hovering
                }
            }
            .help(syncTooltip)
        } else if skill.provenance == nil, let onAdopt {
            Button(action: onAdopt) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHoveringAdopt ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isHoveringAdopt ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.1)) {
                    isHoveringAdopt = hovering
                }
            }
            .help("Adopt as remote-tracked")
        }
    }

    private var syncTooltip: String {
        guard let p = skill.provenance else { return "Sync" }
        if p.hasUpdate {
            return "Sync from \(p.source) — upstream has changes"
        }
        return "Sync from \(p.source)"
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
