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
        @Bindable var store = store

        VStack(spacing: 0) {
            HStack(spacing: 6) {
                scopePicker
                    .fixedSize()
                Spacer(minLength: 0)
                openFileButton
            }
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
        return Menu {
            Button { store.selectedScopeKey = nil } label: {
                pickerMenuItem(
                    text: "All scopes",
                    isSelected: store.selectedScopeKey == nil || store.selectedScopeKey?.isEmpty == true
                )
            }
            Divider()
            Button { store.selectedScopeKey = "global" } label: {
                pickerMenuItem(
                    text: "User Global (\(store.globalHookCount))",
                    isSelected: store.selectedScopeKey == "global"
                )
            }
            if !store.availableProjects.isEmpty {
                Divider()
                ForEach(store.availableProjects) { project in
                    Button { store.selectedScopeKey = project.path } label: {
                        pickerMenuItem(
                            text: "\(project.displayName) (\(project.count))",
                            isSelected: store.selectedScopeKey == project.path
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                Text(currentScopeLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .rect(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(currentScopeTooltip)
    }

    private func pickerMenuItem(text: String, isSelected: Bool) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark").opacity(isSelected ? 1 : 0)
        }
    }

    private var currentScopeLabel: String {
        guard let key = store.selectedScopeKey, !key.isEmpty else { return "All scopes" }
        if key == "global" { return "User Global (\(store.globalHookCount))" }
        if let project = store.availableProjects.first(where: { $0.path == key }) {
            return "\(project.displayName) (\(project.count))"
        }
        return "All scopes"
    }

    private var currentScopeTooltip: String {
        guard let key = store.selectedScopeKey, !key.isEmpty else {
            return "Showing hooks from all scopes"
        }
        if key == "global" { return "~/.claude/settings.json" }
        return key
    }

    private var openFileButton: some View {
        Button(action: openSelectedScopeFile) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(openFileButtonEnabled ? Color.secondary : Color.secondary.opacity(0.4))
                .frame(width: 28, height: 26)
                .glassEffect(.regular, in: .rect(cornerRadius: 6))
                .opacity(openFileButtonEnabled ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!openFileButtonEnabled)
        .help(openFileButtonEnabled ? "Open settings.json in editor" : "Select a scope to open its settings.json")
    }

    private var openFileButtonEnabled: Bool {
        guard let key = store.selectedScopeKey, !key.isEmpty else { return false }
        if key == "global" { return store.globalHookCount > 0 }
        return store.availableProjects.contains(where: { $0.path == key })
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

    private func openSelectedScopeFile() {
        guard let key = store.selectedScopeKey, !key.isEmpty else { return }
        let candidate: Hook? = {
            if key == "global" {
                return store.items.first(where: {
                    if case .userGlobal = $0.scope { return true }
                    return false
                })
            }
            return store.items.first(where: { $0.scope.projectPath == key })
        }()
        guard let hook = candidate else { return }
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
