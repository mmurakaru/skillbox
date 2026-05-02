import SwiftUI
import AppKit

struct PopoverView: View {
    @Environment(SkillStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    @AppStorage("editorCommand") private var editorCommand: String = ""
    @AppStorage("openTarget") private var openTargetRaw: String = OpenTarget.folder.rawValue
    @AppStorage("skillsRootPath") private var skillsRootPath: String = "~/.claude/skills"

    @State private var selectedSkillID: String?
    @State private var rowStates: [String: SkillRowView.RowState] = [:]
    @State private var showingNewSkill = false

    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            if showingNewSkill {
                NewSkillForm(
                    rootPath: (skillsRootPath as NSString).expandingTildeInPath,
                    onCreate: { folderURL in
                        let stub = Skill(
                            name: folderURL.lastPathComponent,
                            description: "",
                            folderURL: folderURL,
                            modifiedAt: Date()
                        )
                        showingNewSkill = false
                        open(skill: stub)
                    },
                    onCancel: { showingNewSkill = false }
                )
            } else {
                browseContent
            }
        }
        .frame(width: 360, height: 480)
        .task {
            store.configure(rootPath: skillsRootPath)
            ensureEditorDefault()
            if selectedSkillID == nil {
                selectedSkillID = store.filteredSkills.first?.id
            }
            try? await Task.sleep(for: .milliseconds(80))
            searchFocused = true
        }
        .onChange(of: skillsRootPath) { _, newValue in
            store.configure(rootPath: newValue)
        }
        .onKeyPress(.escape) {
            if showingNewSkill {
                showingNewSkill = false
                return .handled
            }
            if cancelAnyConfirm() { return .handled }
            NSApp.deactivate()
            return .handled
        }
    }

    private var browseContent: some View {
        @Bindable var store = store

        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                searchBar
                newSkillButton
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            list

            Divider()

            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
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

    private var newSkillButton: some View {
        Button(action: { showingNewSkill = true }) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .help("New skill (⌘N)")
        .keyboardShortcut("n", modifiers: .command)
    }

    private var searchBar: some View {
        @Bindable var store = store
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search skills", text: $store.searchQuery)
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
                    if store.filteredSkills.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ForEach(store.filteredSkills) { skill in
                            SkillRowView(
                                skill: skill,
                                isSelected: selectedSkillID == skill.id,
                                onEdit: { open(skill: skill) },
                                onDelete: { performDelete(skill: skill) },
                                rowState: binding(for: skill.id)
                            )
                            .id(skill.id)
                            .onTapGesture { selectedSkillID = skill.id }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedSkillID) { _, newValue in
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
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            if let err = store.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            } else if store.searchQuery.isEmpty {
                Text("No skills found")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text((skillsRootPath as NSString).expandingTildeInPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else {
                Text("No matches for \"\(store.searchQuery)\"")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: { showSettings() }) {
                Image(systemName: "gearshape")
                Text("Settings")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)

            Button(action: { store.rescan() }) {
                Image(systemName: "arrow.clockwise")
                Text("Refresh")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r", modifiers: .command)

            Spacer()

            Text("\(store.filteredSkills.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Skillbox")
            .keyboardShortcut("q", modifiers: .command)
        }
        .font(.system(size: 11))
    }

    // MARK: - Actions

    private func binding(for id: String) -> Binding<SkillRowView.RowState> {
        Binding(
            get: { rowStates[id] ?? .normal },
            set: { rowStates[id] = $0 }
        )
    }

    private func ensureEditorDefault() {
        if editorCommand.isEmpty, let first = EditorDetector.detect().first {
            editorCommand = first.command
        }
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where isSettingsWindow(window) {
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        let id = window.identifier?.rawValue ?? ""
        return id.contains("Settings") || id.contains("settings") || window.title == "Settings"
    }

    private func open(skill: Skill) {
        let target = OpenTarget(rawValue: openTargetRaw) ?? .folder
        let cmd = editorCommand.isEmpty ? "code" : editorCommand
        EditorLauncher.open(skill: skill, command: cmd, target: target)
        NSApp.deactivate()
    }

    private func performDelete(skill: Skill) {
        let result = SkillDeleter.trash(skill)
        switch result {
        case .success:
            store.remove(skill)
            if selectedSkillID == skill.id {
                selectedSkillID = store.filteredSkills.first?.id
            }
        case .failure(let err):
            NSSound.beep()
            print("Delete failed: \(err)")
        }
    }

    private func cancelAnyConfirm() -> Bool {
        let active = rowStates.first(where: { $0.value == .confirmingDelete })
        if let active {
            rowStates[active.key] = .normal
            return true
        }
        return false
    }

    private func moveSelection(by delta: Int) {
        let items = store.filteredSkills
        guard !items.isEmpty else { return }
        searchFocused = false
        if let current = selectedSkillID, let idx = items.firstIndex(where: { $0.id == current }) {
            let next = max(0, min(items.count - 1, idx + delta))
            selectedSkillID = items[next].id
        } else {
            selectedSkillID = items.first?.id
        }
    }

    private func triggerEditOnSelected() {
        guard let id = selectedSkillID,
              let skill = store.filteredSkills.first(where: { $0.id == id }) else { return }
        open(skill: skill)
    }

    private func triggerDeleteConfirmOnSelected() {
        guard let id = selectedSkillID else { return }
        rowStates[id] = .confirmingDelete
    }
}
