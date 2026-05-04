import SwiftUI
import AppKit

struct InstallFromURLSheet: View {
    @Environment(RemoteSkillService.self) private var service

    let skillsRootPath: String
    let onInstalled: (String) -> Void
    let onBrowseRegistry: () -> Void
    let onCancel: () -> Void

    @State private var rawSource: String = ""
    @State private var skillName: String = ""
    @State private var phase: Phase = .input
    @State private var logText: String = ""
    @State private var errorText: String?
    @FocusState private var sourceFocused: Bool

    enum Phase: Equatable {
        case input
        case running
        case done(installedSkill: String)
    }

    private var pathMismatchWarning: String? {
        let expanded = (skillsRootPath as NSString).expandingTildeInPath
        let defaultExpanded = (("~/.claude/skills" as NSString).expandingTildeInPath)
        if expanded != defaultExpanded {
            return "The CLI installs into \(defaultExpanded), but Skillbox is reading \(expanded). Reset the path in Settings or installs won't show up here."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch phase {
            case .input:
                inputForm
            case .running:
                runningView
            case .done(let name):
                doneView(name: name)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            sourceFocused = true
        }
    }

    private var header: some View {
        HStack {
            Text(headerTitle)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var headerTitle: String {
        switch phase {
        case .input: "Install skill from URL"
        case .running: "Installing…"
        case .done: "Installed"
        }
    }

    private var inputForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("owner/repo, GitHub URL, or git URL", text: $rawSource)
                    .textFieldStyle(.roundedBorder)
                    .focused($sourceFocused)
                    .onSubmit { runInstall() }
                    .onChange(of: rawSource) { _, _ in errorText = nil }

                Text("e.g. vercel-labs/agent-skills or https://github.com/owner/repo/tree/main/skills/foo")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Skill name in repo (optional)", text: $skillName)
                    .textFieldStyle(.roundedBorder)
                Text("For multi-skill repos: pick one. Leave blank to install all.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if let warn = pathMismatchWarning {
                Text(warn)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.orange.opacity(0.12))
                    )
            }

            if let err = errorText {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Button("Browse registry…", action: onBrowseRegistry)
                    .buttonStyle(.borderless)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Install") { runInstall() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(rawSource.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var runningView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Running skills add…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            logScroll
            Spacer()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .disabled(true)
                    .help("Cancellation not supported yet")
            }
        }
    }

    private func doneView(name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Installed \(name.isEmpty ? "skill" : name)")
                    .font(.system(size: 12, weight: .medium))
            }
            logScroll
            Spacer()
            HStack {
                Spacer()
                Button("Done") { onInstalled(name) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var logScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(logText.isEmpty ? "(no output yet)" : logText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                    .id("logEnd")
            }
            .frame(maxHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.08))
            )
            .onChange(of: logText) { _, _ in
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo("logEnd", anchor: .bottom)
                }
            }
        }
    }

    private func runInstall() {
        let trimmed = rawSource.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let trimmedSkill = skillName.trimmingCharacters(in: .whitespaces)
        phase = .running
        logText = ""

        Task { @MainActor in
            do {
                let installed = try await service.install(
                    source: trimmed,
                    skill: trimmedSkill.isEmpty ? nil : trimmedSkill,
                    rootPath: skillsRootPath
                ) { chunk in
                    logText += chunk
                }
                phase = .done(installedSkill: installed.name)
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                phase = .input
            }
        }
    }
}
