import SwiftUI
import AppKit

enum AppTab: String, CaseIterable, Identifiable {
    case skills
    case memory
    case hooks
    case env

    var id: String { rawValue }

    var label: String {
        switch self {
        case .skills: "Skills"
        case .memory: "Memory"
        case .hooks: "Hooks"
        case .env: "Env"
        }
    }
}

enum SkillsTabRoute: Equatable {
    case list
    case newSkill
    case installFromURL
    case adopt(Skill)
}

struct PopoverView: View {
    @Environment(SkillStore.self) private var store
    @Environment(MemoryStore.self) private var memoryStore
    @Environment(HookStore.self) private var hookStore
    @Environment(EnvVarStore.self) private var envStore
    @Environment(InsightsModel.self) private var insightsModel
    @Environment(RemoteSkillService.self) private var remoteSkillService
    @Environment(SkillOverridesStore.self) private var overridesStore
    @Environment(SkillFolderSync.self) private var skillFolderSync
    @Environment(\.openSettings) private var openSettings

    @AppStorage("claudeCommand") private var claudeCommand: String = ""

    @AppStorage("editorCommand") private var editorCommand: String = ""
    @AppStorage("openTarget") private var openTargetRaw: String = OpenTarget.folder.rawValue
    @AppStorage("skillsRootPath") private var skillsRootPath: String = "~/.claude/skills"
    @AppStorage("memoryRootPath") private var memoryRootPath: String = "~/.claude/projects"
    @AppStorage("hooksClaudeHomePath") private var hooksClaudeHomePath: String = "~/.claude"
    @AppStorage("activeTab") private var activeTabRaw: String = AppTab.skills.rawValue
    @AppStorage("syncRemoteSkillsOnLaunch") private var syncRemoteSkillsOnLaunch: Bool = false

    @State private var selectedSkillID: String?
    @State private var selectedMemoryID: String?
    @State private var selectedHookID: String?
    @State private var selectedEnvID: String?
    @State private var rowStates: [String: SkillRowView.RowState] = [:]
    @State private var memoryRowStates: [String: SkillRowView.RowState] = [:]
    @State private var hookRowStates: [String: SkillRowView.RowState] = [:]
    @State private var envRowStates: [String: SkillRowView.RowState] = [:]
    @State private var skillsRoute: SkillsTabRoute = .list

    @FocusState private var searchFocused: Bool

    private var activeTab: AppTab {
        AppTab(rawValue: activeTabRaw) ?? .skills
    }

    var body: some View {
        Group {
            switch skillsRoute {
            case .list:
                shellContent
            case .newSkill:
                NewSkillForm(
                    rootPath: (skillsRootPath as NSString).expandingTildeInPath,
                    onCreate: { folderURL in
                        let stub = Skill(
                            name: folderURL.lastPathComponent,
                            description: "",
                            folderURL: folderURL,
                            modifiedAt: Date()
                        )
                        skillsRoute = .list
                        open(skill: stub)
                    },
                    onCancel: { skillsRoute = .list }
                )
            case .installFromURL:
                InstallFromURLSheet(
                    skillsRootPath: skillsRootPath,
                    onInstalled: { _ in
                        skillsRoute = .list
                        store.rescan()
                    },
                    onCancel: { skillsRoute = .list }
                )
            case .adopt(let target):
                AdoptAsRemoteSheet(
                    skill: target,
                    onAdopted: {
                        skillsRoute = .list
                        store.rescan()
                    },
                    onCancel: { skillsRoute = .list }
                )
            }
        }
        .frame(width: 360, height: 480)
        .task {
            store.configure(rootPath: skillsRootPath)
            memoryStore.configure(rootPath: memoryRootPath)
            hookStore.configure(claudeHomePath: hooksClaudeHomePath)
            envStore.configure(claudeHomePath: hooksClaudeHomePath)
            overridesStore.configure(claudeHomePath: hooksClaudeHomePath)
            ensureEditorDefault()
            if selectedSkillID == nil {
                selectedSkillID = store.filteredItems.first?.id
            }
            try? await Task.sleep(for: .milliseconds(80))
            searchFocused = true
            if syncRemoteSkillsOnLaunch {
                let remoteSkills = store.items.filter { $0.provenance != nil }
                Task.detached(priority: .background) { [weak skillFolderSync] in
                    await skillFolderSync?.syncAll(remoteSkills)
                    await MainActor.run { store.rescan() }
                }
            }
        }
        .onChange(of: skillsRootPath) { _, newValue in
            store.configure(rootPath: newValue)
        }
        .onChange(of: memoryRootPath) { _, newValue in
            memoryStore.configure(rootPath: newValue)
        }
        .onChange(of: hooksClaudeHomePath) { _, newValue in
            hookStore.configure(claudeHomePath: newValue)
            envStore.configure(claudeHomePath: newValue)
            overridesStore.configure(claudeHomePath: newValue)
        }
        .onKeyPress(.escape) {
            if skillsRoute != .list {
                skillsRoute = .list
                return .handled
            }
            if cancelAnyConfirm() { return .handled }
            NSApp.deactivate()
            return .handled
        }
    }

    private func triggerInsights() {
        insightsModel.run(claudeOverride: claudeCommand)
    }

    private func openClaudeMd() {
        let path = (hooksClaudeHomePath as NSString).expandingTildeInPath
        let target = (path as NSString).appendingPathComponent("CLAUDE.md")
        let cmd = editorCommand.isEmpty ? "code" : editorCommand
        EditorLauncher.openPath(target, command: cmd)
        NSApp.deactivate()
    }

    private var shellContent: some View {
        VStack(spacing: 0) {
            tabSwitcher
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

            Divider()

            Group {
                switch activeTab {
                case .skills: skillsBody
                case .memory: memoryBody
                case .hooks: hooksBody
                case .env: envBody
                }
            }

            Divider()

            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
    }

    private func tabButton(for tab: AppTab) -> some View {
        let isSelected = activeTab == tab
        return Button(action: { activeTabRaw = tab.rawValue }) {
            Text(tab.label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
                        }
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 6))
    }

    private var skillsBody: some View {
        @Bindable var store = store

        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                searchBar
                installButton
                newSkillButton
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()

            skillsList
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

    private var memoryBody: some View {
        MemoryListView(
            selectedMemoryID: $selectedMemoryID,
            rowStates: $memoryRowStates
        )
    }

    private var hooksBody: some View {
        HookListView(
            selectedHookID: $selectedHookID,
            rowStates: $hookRowStates
        )
    }

    private var envBody: some View {
        EnvListView(
            selectedEnvID: $selectedEnvID,
            rowStates: $envRowStates
        )
    }

    private var newSkillButton: some View {
        Button(action: { skillsRoute = .newSkill }) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 26)
                .glassEffect(.regular, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("New skill (⌘N)")
        .keyboardShortcut("n", modifiers: .command)
    }

    private var installButton: some View {
        Button(action: { skillsRoute = .installFromURL }) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 26)
                .glassEffect(.regular, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Install skill from URL")
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
        .glassEffect(.regular, in: .rect(cornerRadius: 6))
    }

    private var skillsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if store.filteredItems.isEmpty {
                        skillsEmptyState
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ForEach(store.filteredItems) { skill in
                            SkillRowView(
                                skill: skill,
                                isSelected: selectedSkillID == skill.id,
                                overrideState: overridesStore.state(for: skill.name),
                                isSyncing: skillFolderSync.isSyncing(skill),
                                onEdit: { open(skill: skill) },
                                onDelete: { performDelete(skill: skill) },
                                onSetOverride: { newState in setOverride(skill, to: newState) },
                                onSync: skill.provenance != nil ? { triggerSync(skill) } : nil,
                                onAdopt: skill.provenance == nil ? { skillsRoute = .adopt(skill) } : nil,
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
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onChange(of: selectedSkillID) { _, newValue in
                if let id = newValue {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var skillsEmptyState: some View {
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

            Button(action: { activeRescan() }) {
                Image(systemName: "arrow.clockwise")
                Text("Refresh")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r", modifiers: .command)

            Button(action: triggerInsights) {
                if insightsModel.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "lightbulb")
                }
                Text("Insights")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("i", modifiers: .command)
            .disabled(insightsModel.isRunning)
            .help(insightsModel.isRunning ? "Generating insights…" : "Run /insights and open report")

            Button(action: openClaudeMd) {
                Image(systemName: "text.book.closed")
                Text("CLAUDE.md")
            }
            .buttonStyle(.borderless)
            .help("Open ~/.claude/CLAUDE.md")

            Spacer()

            Text("\(activeCount)")
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
        .background(
            HStack {
                Button("") { activeTabRaw = AppTab.skills.rawValue }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { activeTabRaw = AppTab.memory.rawValue }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { activeTabRaw = AppTab.hooks.rawValue }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { activeTabRaw = AppTab.env.rawValue }
                    .keyboardShortcut("4", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }

    private var activeCount: Int {
        switch activeTab {
        case .skills: store.filteredItems.count
        case .memory: memoryStore.filteredMemories.count
        case .hooks: hookStore.filteredHooks.count
        case .env: envStore.filteredEnvVars.count
        }
    }

    private func activeRescan() {
        switch activeTab {
        case .skills: store.rescan()
        case .memory: memoryStore.rescan()
        case .hooks: hookStore.rescan()
        case .env: envStore.rescan()
        }
    }

    // MARK: - Actions (skills)

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

    private func open(skill: Skill) {
        let target = OpenTarget(rawValue: openTargetRaw) ?? .folder
        let cmd = editorCommand.isEmpty ? "code" : editorCommand
        EditorLauncher.open(skill: skill, command: cmd, target: target)
        NSApp.deactivate()
    }

    private func performDelete(skill: Skill) {
        do {
            try FileManager.default.trashItem(at: skill.folderURL, resultingItemURL: nil)
            store.remove(skill)
            if selectedSkillID == skill.id {
                selectedSkillID = store.filteredItems.first?.id
            }
        } catch {
            NSSound.beep()
            print("Delete failed: \(error)")
        }
    }

    private func setOverride(_ skill: Skill, to state: SkillOverride) {
        do {
            try overridesStore.set(skill.name, to: state)
        } catch {
            NSSound.beep()
            print("Override write failed: \(error)")
        }
    }

    private func triggerSync(_ skill: Skill) {
        Task { @MainActor in
            do {
                _ = try await skillFolderSync.sync(skill)
                store.rescan()
            } catch {
                NSSound.beep()
                print("Sync failed for \(skill.name): \(error)")
            }
        }
    }

    private func cancelAnyConfirm() -> Bool {
        if let active = rowStates.first(where: { $0.value == .confirmingDelete }) {
            rowStates[active.key] = .normal
            return true
        }
        if let active = memoryRowStates.first(where: { $0.value == .confirmingDelete }) {
            memoryRowStates[active.key] = .normal
            return true
        }
        if let active = hookRowStates.first(where: { $0.value == .confirmingDelete }) {
            hookRowStates[active.key] = .normal
            return true
        }
        if let active = envRowStates.first(where: { $0.value == .confirmingDelete }) {
            envRowStates[active.key] = .normal
            return true
        }
        return false
    }

    private func moveSelection(by delta: Int) {
        let items = store.filteredItems
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
              let skill = store.filteredItems.first(where: { $0.id == id }) else { return }
        open(skill: skill)
    }

    private func triggerDeleteConfirmOnSelected() {
        guard let id = selectedSkillID else { return }
        rowStates[id] = .confirmingDelete
    }

    // MARK: - Settings

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

}
