import SwiftUI
import AppKit

struct HookListView: View {
    @Environment(HookStore.self) private var store

    @AppStorage("editorCommand") private var editorCommand: String = ""
    @AppStorage("hooksSelectedScope") private var hooksSelectedScope: String = ""

    @Binding var selectedHookID: String?
    @Binding var rowStates: [String: SkillRowView.RowState]

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                scopePicker
                    .frame(maxWidth: 240, alignment: .leading)
                Spacer(minLength: 0)
                Color.clear.frame(width: 28, height: 26)
                    .accessibilityHidden(true)
            }
            .frame(height: 26)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            HStack(spacing: 6) {
                searchBar
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            Divider()

            list
        }
        .task {
            applyStickyOrDefault()
        }
        .onChange(of: store.items.count) { _, _ in
            applyStickyOrDefault()
        }
        .onChange(of: store.selectedScopeKey) { _, newValue in
            hooksSelectedScope = newValue ?? ""
            selectedHookID = store.filteredHooks.first?.id
        }
        .onChange(of: store.searchQuery) { _, _ in
            selectedHookID = store.filteredHooks.first?.id
        }
        .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.return) {
            if searchFocused { return .ignored }
            triggerEditOnSelected()
            return .handled
        }
        .onKeyPress(.delete) {
            if searchFocused { return .ignored }
            triggerDeleteConfirmOnSelected()
            return .handled
        }
    }

    private var scopePicker: some View {
        @Bindable var store = store
        return Picker("Scope", selection: $store.selectedScopeKey) {
            Text("All scopes").tag(String?.none)
            Text("User Global (\(store.globalHookCount))").tag(Optional("global"))
            ForEach(store.availableProjects) { project in
                Text("\(project.displayName) (\(project.count))").tag(Optional(project.path))
            }
        }
        .labelsHidden()
        .lineLimit(1)
        .truncationMode(.middle)
        .controlSize(.small)
        .help(currentScopeTooltip)
    }

    private var currentScopeTooltip: String {
        guard let key = store.selectedScopeKey, !key.isEmpty else {
            return "Showing hooks from all scopes"
        }
        if key == "global" { return "~/.claude/settings.json" }
        return key
    }

    private var searchBar: some View {
        @Bindable var store = store
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search hooks", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { triggerEditOnSelected() }
            if !store.searchQuery.isEmpty {
                Button(action: { store.searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 6))
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if store.filteredHooks.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ForEach(store.filteredHooks) { hook in
                            HookRowView(
                                hook: hook,
                                isSelected: selectedHookID == hook.id,
                                showProjectName: store.selectedScopeKey == nil || store.selectedScopeKey?.isEmpty == true,
                                onEdit: { open(hook: hook) },
                                onDelete: { performDelete(hook: hook) },
                                rowState: binding(for: hook.id)
                            )
                            .id(hook.id)
                            .onTapGesture { selectedHookID = hook.id }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onChange(of: selectedHookID) { _, newValue in
                if let id = newValue {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            if let err = store.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            } else if store.searchQuery.isEmpty {
                Text("No hooks configured")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Hooks live in ~/.claude/settings.json and per-project .claude/settings.json files.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            } else {
                Text("No matches for \"\(store.searchQuery)\"")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func binding(for id: String) -> Binding<SkillRowView.RowState> {
        Binding(
            get: { rowStates[id] ?? .normal },
            set: { rowStates[id] = $0 }
        )
    }

    private func applyStickyOrDefault() {
        if !hooksSelectedScope.isEmpty,
           store.selectedScopeKey != hooksSelectedScope {
            if hooksSelectedScope == "global" || store.availableProjects.contains(where: { $0.path == hooksSelectedScope }) {
                store.selectedScopeKey = hooksSelectedScope
            }
        }
        if selectedHookID == nil {
            selectedHookID = store.filteredHooks.first?.id
        }
    }

    private func moveSelection(by delta: Int) {
        let items = store.filteredHooks
        guard !items.isEmpty else { return }
        searchFocused = false
        if let current = selectedHookID, let idx = items.firstIndex(where: { $0.id == current }) {
            let next = max(0, min(items.count - 1, idx + delta))
            selectedHookID = items[next].id
        } else {
            selectedHookID = items.first?.id
        }
    }

    private func triggerEditOnSelected() {
        guard let id = selectedHookID,
              let hook = store.filteredHooks.first(where: { $0.id == id }) else { return }
        open(hook: hook)
    }

    private func triggerDeleteConfirmOnSelected() {
        guard let id = selectedHookID else { return }
        rowStates[id] = .confirmingDelete
    }

    private func open(hook: Hook) {
        let cmd = editorCommand.isEmpty ? "code" : editorCommand
        EditorLauncher.openPath(hook.fileURL.path, command: cmd)
        NSApp.deactivate()
    }

    private func performDelete(hook: Hook) {
        do {
            try store.delete(hook)
            if selectedHookID == hook.id {
                selectedHookID = store.filteredHooks.first?.id
            }
        } catch {
            NSSound.beep()
            print("Hook delete failed: \(error)")
        }
    }
}
