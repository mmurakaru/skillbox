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

    var symbol: String {
        switch self {
        case .skills: "shippingbox"
        case .memory: "brain"
        case .hooks: "bolt"
        case .env: "lock"
        }
    }
}

enum SkillsTabRoute: Equatable {
    case list
    case installFromURL
    case adopt(Skill)
}

struct PopoverView: View {
    @Environment(SkillStore.self) private var store
    @Environment(MemoryStore.self) private var memoryStore
    @Environment(HookStore.self) private var hookStore
    @Environment(EnvVarStore.self) private var envStore
    @Environment(RemoteSkillService.self) private var remoteSkillService
    @Environment(SkillOverridesStore.self) private var overridesStore
    @Environment(SkillFolderSync.self) private var skillFolderSync
    @Environment(SkillClassificationStore.self) private var classificationStore
    @Environment(TypeSafeSettings.self) private var typeSafeSettings
    @Environment(\.openSettings) private var openSettings


    @AppStorage("editorCommand") private var editorCommand: String = ""
    @AppStorage("openTarget") private var openTargetRaw: String = OpenTarget.folder.rawValue
    @AppStorage("skillsRootPath") private var skillsRootPath: String = "~/.agents/skills"
    @AppStorage("claudeSkillsMountPath") private var claudeSkillsMountPath: String = "~/.claude/skills"
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
            case .installFromURL:
                InstallFromURLSheet(
                    skillsRootPath: skillsRootPath,
                    claudeSkillsMountPath: claudeSkillsMountPath,
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
        .frame(width: 410, height: 480)
        .task {
            migrateLegacySkillsRootIfNeeded()
            store.configure(rootPath: skillsRootPath)
            ensureClaudeSkillMounts()
            memoryStore.configure(rootPath: memoryRootPath)
            hookStore.configure(claudeHomePath: hooksClaudeHomePath)
            envStore.configure(claudeHomePath: hooksClaudeHomePath)
            overridesStore.configure(claudeHomePath: hooksClaudeHomePath)
            ensureEditorDefault()
            if selectedSkillID == nil {
                selectedSkillID = visibleSkills.first?.id
            }
            try? await Task.sleep(for: .milliseconds(80))
            searchFocused = true
            if syncRemoteSkillsOnLaunch {
                let remoteSkills = store.items.filter { $0.provenance != nil }
                Task.detached(priority: .background) { [weak skillFolderSync] in
                    await skillFolderSync?.syncAll(remoteSkills)
                    await MainActor.run {
                        ensureClaudeSkillMounts()
                        store.rescan()
                    }
                }
            }
        }
        .onChange(of: skillsRootPath) { _, newValue in
            store.configure(rootPath: newValue)
            ensureClaudeSkillMounts()
        }
        .onChange(of: claudeSkillsMountPath) { _, _ in
            ensureClaudeSkillMounts()
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

    private var shellContent: some View {
        HStack(spacing: 0) {
            tabSidebar
            Divider()
            VStack(spacing: 0) {
                Group {
                    switch activeTab {
                    case .skills: skillsBody
                    case .memory: memoryBody
                    case .hooks: hooksBody
                    case .env: envBody
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tabSidebar: some View {
        VStack(spacing: 10) {
            ForEach(AppTab.allCases) { tab in
                tabButton(for: tab)
            }
            Spacer()
            Text("\(activeCount)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .help("\(activeCount) visible items")
            Button(action: showSettings) {
                Image(systemName: "gearshape").frame(width: 36, height: 32)
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            .keyboardShortcut(",", modifiers: .command)
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power").frame(width: 36, height: 32)
            }
            .help("Quit Skillbox")
            .accessibilityLabel("Quit Skillbox")
            .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.plain)
        .font(.system(size: 16))
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: 50)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.04))
        .background(tabShortcuts)
    }

    private func tabButton(for tab: AppTab) -> some View {
        let isSelected = activeTab == tab
        return Button(action: { activeTabRaw = tab.rawValue }) {
            Image(systemName: tab.symbol)
                .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 36, height: 36)
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
        .help(tab.label)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .glassEffect(.regular, in: .rect(cornerRadius: 6))
    }

    private var skillsBody: some View {
        @Bindable var store = store

        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                searchBar
                installButton
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            classificationControls
                .padding(.horizontal, 10)
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

    private var visibleSkills: [Skill] {
        classificationStore.filteredSkills(store.filteredItems)
    }

    private var classificationControls: some View {
        @Bindable var classifications = classificationStore
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Picker("Category", selection: $classifications.selectedCategory) {
                    Text("All categories").tag("all")
                    ForEach(SkillCategory.allCases) { category in
                        Text(category.label).tag(category.rawValue)
                    }
                    Text("Unclassified").tag("unclassified")
                }
                .labelsHidden()
                .help("Filter by category")
                Picker("Activity", selection: $classifications.selectedActivity) {
                    Text("All activities").tag("all")
                    ForEach(SkillActivity.allCases) { activity in
                        Text(activity.label).tag(activity.rawValue)
                    }
                    Text("Unclassified").tag("unclassified")
                }
                .labelsHidden()
                .help("Filter by activity")
                Spacer(minLength: 0)
                if classifications.isClassifying {
                    ProgressView().controlSize(.small)
                    Button(action: { classifications.cancelClassification() }) {
                        Image(systemName: "xmark")
                    }
                    .help("Cancel classification")
                    .accessibilityLabel("Cancel classification")
                } else {
                    Button("Classify") { classifySkills() }
                        .disabled(store.items.isEmpty)
                        .help(typeSafeSettings.apiKey.isEmpty ? "Set your TypeSafe API key in Settings" : "Classify new or changed skills with Jev")
                        .contextMenu {
                            Button("Reclassify all skills") { classifySkills(force: true) }
                        }
                }
            }
            .controlSize(.small)
            if classifications.isClassifying {
                Text("Classifying \(classifications.completedCount) / \(classifications.totalCount)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else if let message = classifications.statusMessage {
                Text(message)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(2).help(message)
            }
        }
        .onChange(of: visibleSkills.map(\.id)) { _, ids in
            if !ids.contains(selectedSkillID ?? "") { selectedSkillID = ids.first }
        }
    }

    private func classifySkills(force: Bool = false) {
        guard !typeSafeSettings.apiKey.isEmpty else { showSettings(); return }
        classificationStore.startClassification(skills: store.items, apiKey: typeSafeSettings.apiKey, force: force)
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

    private var installButton: some View {
        Button(action: { skillsRoute = .installFromURL }) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 26)
                .glassEffect(.regular, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Install skill from URL (⌘N)")
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
        .glassEffect(.regular, in: .rect(cornerRadius: 6))
    }

    private var skillsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if visibleSkills.isEmpty {
                        skillsEmptyState
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ForEach(visibleSkills) { skill in
                            SkillRowView(
                                skill: skill,
                                classification: classificationStore.classification(for: skill),
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
            } else if classificationStore.selectedCategory != "all" || classificationStore.selectedActivity != "all" {
                Text("No skills match these filters")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Clear filters") {
                    classificationStore.selectedCategory = "all"
                    classificationStore.selectedActivity = "all"
                    store.searchQuery = ""
                }
                .buttonStyle(.borderless)
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

    private var tabShortcuts: some View {
            VStack {
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
    }

    private var activeCount: Int {
        switch activeTab {
        case .skills: visibleSkills.count
        case .memory: memoryStore.filteredMemories.count
        case .hooks: hookStore.filteredHooks.count
        case .env: envStore.filteredEnvVars.count
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

    private func migrateLegacySkillsRootIfNeeded() {
        let legacy = ("~/.claude/skills" as NSString).expandingTildeInPath
        let current = (skillsRootPath as NSString).expandingTildeInPath
        let agents = ("~/.agents/skills" as NSString).expandingTildeInPath
        if current == legacy, FileManager.default.fileExists(atPath: agents) {
            skillsRootPath = "~/.agents/skills"
        }
    }

    private func ensureClaudeSkillMounts() {
        do {
            _ = try SkillMountSync.ensureAll(
                sourceRootPath: skillsRootPath,
                mountRootPath: claudeSkillsMountPath
            )
        } catch {
            print("Claude skills mount sync failed: \(error)")
        }
    }

    private func open(skill: Skill) {
        let target = OpenTarget(rawValue: openTargetRaw) ?? .folder
        let cmd = editorCommand.isEmpty ? EditorDetector.preferredCommand : editorCommand
        let path = target == .folder ? skill.folderURL.path : skill.skillFileURL.path
        EditorLauncher.openAsWorkspace(path, command: cmd)
        NSApp.deactivate()
    }

    private func performDelete(skill: Skill) {
        do {
            try FileManager.default.trashItem(at: skill.folderURL, resultingItemURL: nil)
            try? SkillMountSync.removeMount(named: skill.folderURL.lastPathComponent, mountRootPath: claudeSkillsMountPath)
            store.remove(skill)
            if selectedSkillID == skill.id {
                selectedSkillID = visibleSkills.first?.id
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
                ensureClaudeSkillMounts()
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
        let items = visibleSkills
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
              let skill = visibleSkills.first(where: { $0.id == id }) else { return }
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
