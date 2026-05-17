import SwiftUI
import AppKit

/// Adopt an existing local skill as remote-tracked by writing a `.skillbox.json` sidecar
/// and immediately syncing the folder from the source.
struct AdoptAsRemoteSheet: View {
    @Environment(SkillFolderSync.self) private var sync

    let skill: Skill
    let onAdopted: () -> Void
    let onCancel: () -> Void

    @State private var rawSource: String = ""
    @State private var skillSubpath: String = ""
    @State private var branch: String = "main"
    @State private var phase: Phase = .input
    @State private var logText: String = ""
    @State private var errorText: String?
    @FocusState private var sourceFocused: Bool

    enum Phase: Equatable {
        case input
        case running
        case done
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch phase {
            case .input:
                inputForm
            case .running:
                runningView
            case .done:
                doneView
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
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(skill.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
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
        case .input: "Adopt as remote"
        case .running: "Syncing…"
        case .done: "Adopted"
        }
    }

    private var inputForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("owner/repo or GitHub URL", text: $rawSource)
                    .textFieldStyle(.roundedBorder)
                    .focused($sourceFocused)
                    .onSubmit { runAdopt() }
                    .onChange(of: rawSource) { _, _ in errorText = nil }
                Text("e.g. mattpocock/skills or https://github.com/mattpocock/skills/tree/main/skills/productivity/caveman")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Skill name in repo (optional)", text: $skillSubpath)
                    .textFieldStyle(.roundedBorder)
                Text("Required for multi-skill repos when the URL doesn't include a tree path. Leave blank if the source already points at the skill folder.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Branch", text: $branch)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Adopting will overwrite the local folder with the upstream contents.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let err = errorText {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Adopt + Sync") { runAdopt() }
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
                Text("Writing provenance and pulling from upstream…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            logScroll
            Spacer()
        }
    }

    private var doneView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Adopted as remote")
                    .font(.system(size: 12, weight: .medium))
            }
            logScroll
            Spacer()
            HStack {
                Spacer()
                Button("Done") { onAdopted() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var logScroll: some View {
        ScrollView {
            Text(logText.isEmpty ? "(no output yet)" : logText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
        }
        .frame(maxHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func runAdopt() {
        let trimmedSource = rawSource.trimmingCharacters(in: .whitespaces)
        guard !trimmedSource.isEmpty else { return }
        let trimmedSkill = skillSubpath.trimmingCharacters(in: .whitespaces)
        let trimmedBranch = branch.trimmingCharacters(in: .whitespaces).isEmpty
            ? "main"
            : branch.trimmingCharacters(in: .whitespaces)

        // Provisional provenance just so SkillSourceCoordinates can resolve it.
        let provisional = SkillProvenance(
            source: trimmedSource,
            skill: trimmedSkill.isEmpty ? nil : trimmedSkill,
            ref: trimmedBranch,
            sha: nil,
            installedAt: Date(),
            lastCheckedAt: nil,
            latestKnownSHA: nil
        )

        guard SkillSourceCoordinates.parse(provenance: provisional) != nil else {
            errorText = "Couldn't resolve \"\(trimmedSource)\" into owner/repo coordinates."
            return
        }

        phase = .running
        logText = "Writing \(SkillProvenance.sidecarFilename)…\n"

        Task { @MainActor in
            do {
                try SkillProvenanceStore.write(provisional, to: skill.folderURL)
                logText += "Sidecar written. Syncing from upstream…\n"

                let adoptedSkill = Skill(
                    name: skill.name,
                    description: skill.description,
                    folderURL: skill.folderURL,
                    modifiedAt: skill.modifiedAt,
                    provenance: provisional,
                    authorLocked: skill.authorLocked
                )
                let outcome = try await sync.sync(adoptedSkill)
                switch outcome {
                case .upToDate(let sha):
                    logText += "Already at upstream SHA \(sha.prefix(8)).\n"
                case .mirrored(let sha, let count):
                    logText += "Mirrored \(count) file(s) at SHA \(sha.prefix(8)).\n"
                case .unresolvableSource:
                    logText += "Could not resolve source - sidecar kept, no files pulled.\n"
                }
                phase = .done
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                logText += "Failed: \(msg)\n"
                errorText = msg
                phase = .input
            }
        }
    }
}
