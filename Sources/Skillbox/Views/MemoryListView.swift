import SwiftUI
import AppKit

struct MemoryListView: View {
    @Environment(MemoryStore.self) private var store

    @AppStorage("editorCommand") private var editorCommand: String = ""
    @AppStorage("memorySelectedProject") private var memorySelectedProject: String = ""

    @Binding var selectedMemoryID: String?
    @Binding var rowStates: [String: SkillRowView.RowState]

    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            HStack(spacing: 6) {
                projectPicker
                openFolderButton
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
        .onChange(of: store.memories.count) { _, _ in
            applyStickyOrDefault()
        }
        .onChange(of: store.selectedProjectPath) { _, newValue in
            memorySelectedProject = newValue ?? ""
            selectedMemoryID = store.filteredMemories.first?.id
        }
        .onChange(of: store.searchQuery) { _, _ in
            selectedMemoryID = store.filteredMemories.first?.id
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

    private func moveSelection(by delta: Int) {
        let items = store.filteredMemories
        guard !items.isEmpty else { return }
        searchFocused = false
        if let current = selectedMemoryID, let idx = items.firstIndex(where: { $0.id == current }) {
            let next = max(0, min(items.count - 1, idx + delta))
            selectedMemoryID = items[next].id
        } else {
            selectedMemoryID = items.first?.id
        }
    }

    private func triggerDeleteConfirmOnSelected() {
        guard let id = selectedMemoryID else { return }
        rowStates[id] = .confirmingDelete
    }

    private var projectPicker: some View {
        @Bindable var store = store
        return Menu {
            Button {
                store.selectedProjectPath = nil
            } label: {
                if store.selectedProjectPath == nil {
                    Label("All projects", systemImage: "checkmark")
                } else {
                    Text("All projects")
                }
            }
            Divider()
            ForEach(store.availableProjects) { project in
                Button {
                    store.selectedProjectPath = project.folderURL.path
                } label: {
                    HStack {
                        if store.selectedProjectPath == project.folderURL.path {
                            Label("\(project.displayName) (\(project.count))", systemImage: "checkmark")
                        } else {
                            Text("\(project.displayName) (\(project.count))")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(currentProjectLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(currentProjectTooltip)
    }

    private var currentProjectLabel: String {
        guard let path = store.selectedProjectPath, !path.isEmpty,
              let project = store.availableProjects.first(where: { $0.folderURL.path == path }) else {
            return "All projects"
        }
        return "\(project.displayName) (\(project.count))"
    }

    private var currentProjectTooltip: String {
        guard let path = store.selectedProjectPath, !path.isEmpty,
              let project = store.availableProjects.first(where: { $0.folderURL.path == path }) else {
            return "Showing memory entries from all projects"
        }
        return project.fullPath
    }

    private var openFolderButton: some View {
        Button(action: openSelectedProjectFolder) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(folderButtonEnabled ? Color.secondary : Color.secondary.opacity(0.4))
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(folderButtonEnabled ? 0.1 : 0.05))
                )
        }
        .buttonStyle(.plain)
        .disabled(!folderButtonEnabled)
        .help(folderButtonEnabled ? "Open memory folder in editor" : "Select a project to open its memory folder")
    }

    private var folderButtonEnabled: Bool {
        guard let path = store.selectedProjectPath, !path.isEmpty else { return false }
        return store.availableProjects.contains(where: { $0.folderURL.path == path })
    }

    private var searchBar: some View {
        @Bindable var store = store
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search memory", text: $store.searchQuery)
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
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if store.filteredMemories.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ForEach(store.filteredMemories) { memory in
                            MemoryRowView(
                                memory: memory,
                                isSelected: selectedMemoryID == memory.id,
                                showProjectName: store.selectedProjectPath == nil || store.selectedProjectPath?.isEmpty == true,
                                onEdit: { open(memory: memory) },
                                onDelete: { performDelete(memory: memory) },
                                rowState: binding(for: memory.id)
                            )
                            .id(memory.id)
                            .onTapGesture { selectedMemoryID = memory.id }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedMemoryID) { _, newValue in
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
            Image(systemName: "brain")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            if let err = store.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            } else if store.searchQuery.isEmpty {
                Text("No memory entries")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Claude saves memory during conversations.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
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
        if !memorySelectedProject.isEmpty,
           store.availableProjects.contains(where: { $0.folderURL.path == memorySelectedProject }),
           store.selectedProjectPath != memorySelectedProject {
            store.selectedProjectPath = memorySelectedProject
        }
        if selectedMemoryID == nil {
            selectedMemoryID = store.filteredMemories.first?.id
        }
    }

    private func open(memory: Memory) {
        let cmd = editorCommand.isEmpty ? "code" : editorCommand
        EditorLauncher.openPath(memory.fileURL.path, command: cmd)
        NSApp.deactivate()
    }

    private func openSelectedProjectFolder() {
        guard let path = store.selectedProjectPath, !path.isEmpty,
              let project = store.availableProjects.first(where: { $0.folderURL.path == path }) else { return }
        let memoryDir = project.folderURL.appendingPathComponent("memory")
        let cmd = editorCommand.isEmpty ? "code" : editorCommand
        EditorLauncher.openPath(memoryDir.path, command: cmd)
        NSApp.deactivate()
    }

    private func performDelete(memory: Memory) {
        let result = SkillDeleter.trashURL(memory.fileURL)
        switch result {
        case .success:
            store.remove(memory)
            if selectedMemoryID == memory.id {
                selectedMemoryID = store.filteredMemories.first?.id
            }
        case .failure(let err):
            NSSound.beep()
            print("Memory delete failed: \(err)")
        }
    }

    private func triggerEditOnSelected() {
        guard let id = selectedMemoryID,
              let memory = store.filteredMemories.first(where: { $0.id == id }) else { return }
        open(memory: memory)
    }
}
