import SwiftUI

struct InstallFromURLSheet: View {
    @Environment(RemoteSkillService.self) private var service
    let skillsRootPath: String
    let claudeSkillsMountPath: String
    let onInstalled: (String) -> Void
    let onCancel: () -> Void

    @State private var rawSource = ""
    @State private var model = SkillInstallModel()
    @FocusState private var sourceFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.phase == .done ? "Skills installed" : "Install remote skills")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(model.phase == .running)
                .help("Close")
                .accessibilityLabel("Close installation")
            }
            if model.phase == .input {
                TextField("Repository or skill folder URL", text: $rawSource)
                    .textFieldStyle(.roundedBorder)
                    .focused($sourceFocused)
                    .onSubmit { runInstall() }
                Text("Paste owner/repo or a GitHub URL. For one skill from a collection, paste its folder URL.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if let error = model.errorMessage {
                    Text(error).font(.system(size: 12)).foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            } else {
                SkillInstallProgressView(source: model.source, stage: model.output.stage, installedNames: model.installedNames)
            }
            Spacer()
            HStack {
                Spacer()
                switch model.phase {
                case .input:
                    Button("Cancel", action: onCancel)
                    Button("Install", action: runInstall)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(rawSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                case .running:
                    Text("Installation is in progress…")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                case .done:
                    Button("Done") { onInstalled(model.installedNames.first ?? "") }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { sourceFocused = true }
        .onKeyPress(.escape) {
            if model.phase != .running { onCancel() }
            return .handled
        }
    }

    private func runInstall() {
        Task { @MainActor in
            await model.installSkill(source: rawSource, rootPath: skillsRootPath, mountPath: claudeSkillsMountPath, service: service)
        }
    }
}
