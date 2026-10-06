import SwiftUI
import Sparkle

@main
struct SkillboxApp: App {
    @State private var store: SkillStore
    @State private var memoryStore = MemoryStore()
    @State private var hookStore = HookStore()
    @State private var envStore = EnvVarStore()
    @State private var insightsModel: InsightsModel
    @State private var remoteSkillService = RemoteSkillService()
    @State private var overridesStore = SkillOverridesStore()
    @State private var skillFolderSync = SkillFolderSync()
    @State private var classificationStore: SkillClassificationStore
    @State private var typeSafeSettings: TypeSafeSettings
    @State private var classificationAutomation: SkillClassificationAutomation

    private let updaterController: SPUStandardUpdaterController

    init() {
        let store = SkillStore()
        let classifications = SkillClassificationStore()
        let credentials = TypeSafeSettings()
        store.configure(rootPath: UserDefaults.standard.string(forKey: "skillsRootPath") ?? "~/.agents/skills")
        self._store = State(initialValue: store)
        self._classificationStore = State(initialValue: classifications)
        self._typeSafeSettings = State(initialValue: credentials)
        self._classificationAutomation = State(initialValue: SkillClassificationAutomation(
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
                .environment(store)
                .environment(memoryStore)
                .environment(hookStore)
                .environment(envStore)
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

        Settings {
            SettingsView()
                .environment(classificationStore)
                .environment(store)
                .environment(skillFolderSync)
                .environment(typeSafeSettings)
                .environment(insightsModel)
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
