import SwiftUI

@main
struct SkillboxApp: App {
    @State private var store = SkillStore()
    @State private var memoryStore = MemoryStore()
    @State private var remoteSkillService = RemoteSkillService()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(store)
                .environment(memoryStore)
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
