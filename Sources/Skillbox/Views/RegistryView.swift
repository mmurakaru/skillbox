import SwiftUI

struct RegistryView: View {
    let skillsRootPath: String
    let onInstalled: (String) -> Void
    let onBack: () -> Void

    @State private var entries: [RegistryEntry] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var query: String = ""
    @State private var installing: String?
    @State private var lastInstalledName: String?
    @State private var streamLog: String = ""
    @State private var showLogFor: String?

    @FocusState private var searchFocused: Bool

    private var filteredEntries: [RegistryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(q) ||
            entry.description.localizedCaseInsensitiveContains(q) ||
            entry.folderName.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)

            searchBar
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            Divider()

            content
        }
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            searchFocused = true
            await loadEntries()
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 12))
            }
            .buttonStyle(.borderless)

            Spacer()

            Text("Registry")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button(action: { Task { await loadEntries() } }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Reload registry")
            .disabled(isLoading)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search registry", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading vercel-labs/agent-skills…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = loadError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Button("Retry") { Task { await loadEntries() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredEntries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(query.isEmpty ? "No entries in registry" : "No matches for \"\(query)\"")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(filteredEntries) { entry in
                    row(for: entry)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    private func row(for entry: RegistryEntry) -> some View {
        let isInstalling = installing == entry.id
        let isExpanded = showLogFor == entry.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(entry.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.description)

                if isInstalling {
                    ProgressView().controlSize(.small)
                } else if lastInstalledName == entry.folderName {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                        .padding(.trailing, 4)
                } else {
                    Button("Install") {
                        Task { await install(entry: entry) }
                    }
                    .controlSize(.small)
                    .disabled(installing != nil)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isInstalling ? 0.06 : 0.0))
            )

            if isExpanded {
                Text(streamLog.isEmpty ? "Running…" : streamLog)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.08))
                    )
                    .padding(.horizontal, 10)
            }
        }
    }

    private func loadEntries() async {
        isLoading = true
        loadError = nil
        do {
            let result = try await SkillRegistry.list()
            entries = result
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func install(entry: RegistryEntry) async {
        installing = entry.id
        showLogFor = entry.id
        streamLog = ""
        let opts = SkillsCLI.InstallOptions(
            source: SkillRegistry.defaultRepo,
            skill: entry.folderName
        )
        do {
            let result = try await SkillsCLI.install(opts) { chunk in
                Task { @MainActor in
                    streamLog += chunk
                }
            }
            if result.exitCode == 0 {
                recordProvenance(skillName: entry.folderName, sourcePath: entry.path)
                lastInstalledName = entry.folderName
                onInstalled(entry.folderName)
            } else {
                streamLog += "\nFailed (exit \(result.exitCode))"
            }
        } catch {
            streamLog += "\n\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
        installing = nil
    }

    private func recordProvenance(skillName: String, sourcePath: String) {
        let folder = URL(fileURLWithPath: (skillsRootPath as NSString).expandingTildeInPath)
            .appendingPathComponent(skillName)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        let provenance = SkillProvenance(
            source: SkillRegistry.defaultRepo,
            skill: skillName,
            ref: SkillRegistry.defaultBranch,
            sha: nil,
            installedAt: Date(),
            lastCheckedAt: Date(),
            latestKnownSHA: nil
        )
        try? SkillProvenanceStore.write(provenance, to: folder)

        Task {
            if let sha = try? await SkillRegistry.latestSHA(path: sourcePath) {
                var updated = provenance
                updated.sha = sha
                updated.latestKnownSHA = sha
                try? SkillProvenanceStore.write(updated, to: folder)
            }
        }
    }
}
