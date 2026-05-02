import SwiftUI

@main
struct SkillboxApp: App {
    @State private var store = SkillStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(store)
        } label: {
            Image(nsImage: MenuBarIcon.nsImage)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
