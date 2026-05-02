import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @AppStorage("skillsRootPath") private var skillsRootPath: String = "~/.claude/skills"
    @AppStorage("editorCommand") private var editorCommand: String = ""
    @AppStorage("openTarget") private var openTargetRaw: String = OpenTarget.folder.rawValue
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false

    @State private var detectedEditors: [DetectedEditor] = []

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Skills directory", text: $skillsRootPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse…") { browseForFolder() }
                }
            } header: {
                Text("Skills")
            }

            Section {
                Picker("Editor", selection: $editorCommand) {
                    if detectedEditors.isEmpty {
                        Text("No GUI editor detected").tag("")
                    }
                    ForEach(detectedEditors, id: \.command) { editor in
                        Text(editor.displayName).tag(editor.command)
                    }
                    Divider()
                    Text("Custom command…").tag("__custom__")
                }
                .pickerStyle(.menu)

                if editorCommand == "__custom__" || (!editorCommand.isEmpty && !detectedEditors.contains(where: { $0.command == editorCommand })) {
                    TextField("Custom command (e.g. /usr/local/bin/code)", text: $editorCommand)
                        .textFieldStyle(.roundedBorder)
                }

                Picker("Open target", selection: $openTargetRaw) {
                    ForEach(OpenTarget.allCases) { target in
                        Text(target.displayName).tag(target.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Editor")
            }

            Section {
                Toggle("Launch Skillbox at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        applyLaunchAtLogin(newValue)
                    }
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 380)
        .task {
            detectedEditors = EditorDetector.detect()
            syncLaunchAtLoginFromSystem()
        }
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (skillsRootPath as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            skillsRootPath = url.path
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch-at-login change failed: \(error)")
        }
    }

    private func syncLaunchAtLoginFromSystem() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
