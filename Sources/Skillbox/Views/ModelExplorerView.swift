import SwiftUI
import ModelInventory

/// Explore tab: browse Hugging Face Hub models by search, lab, format, size, and sort.
struct ModelExplorerView: View {
    @Environment(ModelExplorerStore.self) private var explorer
    @Environment(LocalModelStore.self) private var localModels

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)

            filterBar
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            statusBar
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .task { await explorer.searchOncePerSession() }
    }

    private var searchBar: some View {
        @Bindable var explorer = explorer
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Hugging Face", text: $explorer.query.search)
                .textFieldStyle(.plain)
                .onSubmit { runSearch() }
            if !explorer.query.search.isEmpty {
                Button(action: {
                    explorer.query.search = ""
                    runSearch()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 6))
    }

    private var filterBar: some View {
        @Bindable var explorer = explorer
        return HStack(spacing: 6) {
            TextField("Lab", text: $explorer.query.author)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .onSubmit { runSearch() }
                .help("Organization on Hugging Face, for example Qwen")

            Picker("Format", selection: $explorer.query.library) {
                Text("Format").tag(String?.none)
                Text("GGUF").tag(String?("gguf"))
                Text("MLX").tag(String?("mlx"))
            }
            .labelsHidden()
            .fixedSize()
            .help("Weight format")
            .onChange(of: explorer.query.library) { runSearch() }

            Picker("Size", selection: $explorer.sizeBucket) {
                ForEach(ModelParameterSizeBucket.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .help("Parameter count")

            Picker("Sort", selection: $explorer.query.sort) {
                ForEach(HuggingFaceHubSort.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .help("Sort order")
            .onChange(of: explorer.query.sort) { runSearch() }
        }
        .controlSize(.small)
    }

    private func runSearch() {
        Task { await explorer.search() }
    }

    @ViewBuilder
    private var content: some View {
        if explorer.isLoading && explorer.results.isEmpty {
            ProgressView()
                .controlSize(.small)
        } else if explorer.displayedResults.isEmpty {
            emptyState
        } else {
            let localModelNames = localModels.models.map(\.name)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(explorer.displayedResults) { hubModel in
                        HuggingFaceHubModelRowView(
                            model: hubModel,
                            isInstalled: HuggingFaceHubModelHandoff.isInstalled(hubModel, localModelNames: localModelNames)
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(explorer.errorMessage ?? (explorer.results.isEmpty ? "No models found" : "No models in this size range"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            if let message = explorer.errorMessage, !explorer.results.isEmpty {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.secondary)
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    Text(lastSyncedLabel(now: timeline.date))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if explorer.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .font(.system(size: 10))
        .frame(height: 16)
    }

    private func lastSyncedLabel(now: Date) -> String {
        guard let lastSynced = explorer.lastSynced else { return "Not synced yet" }
        guard now.timeIntervalSince(lastSynced) >= 60 else { return "Synced just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Synced \(formatter.localizedString(for: lastSynced, relativeTo: now))"
    }
}
