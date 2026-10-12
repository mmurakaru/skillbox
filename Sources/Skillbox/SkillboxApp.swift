import Sparkle
import SwiftUI

@main
struct SkillboxApp: App {
    @State private var usageStore: ProviderUsageStore
    @State private var store: SkillStore
    @State private var memoryStore = MemoryStore()
    @State private var hookStore = HookStore()
    @State private var envStore = EnvVarStore()
    @State private var keychainSecretsModel = KeychainSecretsModel()
    @State private var localModelStore: LocalModelStore
    @State private var modelExplorerStore = ModelExplorerStore()
    @State private var insightsModel: InsightsModel
    @State private var remoteSkillService = RemoteSkillService()
    @State private var overridesStore = SkillOverridesStore()
    @State private var skillFolderSync = SkillFolderSync()
    @State private var classificationStore: SkillClassificationStore
    @State private var typeSafeSettings: TypeSafeSettings
    @State private var classificationAutomation: SkillClassificationAutomation

    private let updaterController: SPUStandardUpdaterController

    init() {
        let usageStore = ProviderUsageStore()

        self._usageStore = State(initialValue: usageStore)
        let store = SkillStore()
        let classifications = SkillClassificationStore()
        let credentials = TypeSafeSettings()

        store.configure(rootPath: UserDefaults.standard.string(forKey: "skillsRootPath") ?? "~/.agents/skills")
        self._store = State(initialValue: store)
        let localModelStore = LocalModelStore()

        localModelStore.configure(LocalModelScanSettings.configuration())
        self._localModelStore = State(initialValue: localModelStore)
        self._classificationStore = State(initialValue: classifications)
        self._typeSafeSettings = State(initialValue: credentials)
        self._classificationAutomation = State(
            initialValue: SkillClassificationAutomation(
                store: store, classifications: classifications, apiKey: { credentials.apiKey }
            ))
        let model = InsightsModel()

        model.presentError = { msg in
            let alert = NSAlert()

            alert.messageText = "Insights failed"
            alert.informativeText = msg
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        self._insightsModel = State(initialValue: model)

        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(usageStore)
                .task { usageStore.startAutoRefresh() }
                .environment(store)
                .environment(memoryStore)
                .environment(hookStore)
                .environment(envStore)
                .environment(keychainSecretsModel)
                .environment(localModelStore)
                .environment(modelExplorerStore)
                .environment(insightsModel)
                .environment(remoteSkillService)
                .environment(overridesStore)
                .environment(skillFolderSync)
                .environment(classificationStore)
                .environment(typeSafeSettings)
                .environment(\.sparkleUpdater, updaterController.updater)
        } label: {
            Image(nsImage: MenuBarIcon.nsImage)
        }
        .menuBarExtraStyle(.window)

        UsageSnapshotScene(store: usageStore)

        Settings {
            SettingsView()
                .environment(classificationStore)
                .environment(store)
                .environment(skillFolderSync)
                .environment(typeSafeSettings)
                .environment(insightsModel)
                .environment(localModelStore)
                .environment(\.sparkleUpdater, updaterController.updater)
        }
    }
}

private struct SparkleUpdaterKey: EnvironmentKey {
    static let defaultValue: SPUUpdater? = nil
}

extension EnvironmentValues {
    var sparkleUpdater: SPUUpdater? {
        get { self[SparkleUpdaterKey.self] }
        set { self[SparkleUpdaterKey.self] = newValue }
    }
}
