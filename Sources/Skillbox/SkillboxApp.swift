import SwiftUI

@main
struct SkillboxApp: App {
    @State private var store = SkillStore()
    @State private var memoryStore = MemoryStore()
    @State private var hookStore = HookStore()
    @State private var envStore = EnvVarStore()
    @State private var insightsModel: InsightsModel
    @State private var remoteSkillService = RemoteSkillService()

    init() {
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
        } label: {
            Image(nsImage: MenuBarIcon.nsImage)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
