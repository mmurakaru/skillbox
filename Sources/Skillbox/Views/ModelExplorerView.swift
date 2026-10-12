import ModelInventory
import SwiftUI

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
                .help("Clear search")
                .accessibilityLabel("Clear search")
                .hoverActionLabel("Clear search")
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

            Picker("Format", selection: $explorer.query.formatFilter) {
                Text("Format").tag(String?.none)
                Text("GGUF").tag(String?("gguf"))
                Text("MLX").tag(String?("mlx"))
            }
            .labelsHidden()
            .fixedSize()
            .help("Weight format")
            .onChange(of: explorer.query.formatFilter) { runSearch() }

            Picker("Size", selection: $explorer.sizeBucket) {
                ForEach(ModelParameterSizeBucket.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .help("Parameter count")
            .onChange(of: explorer.sizeBucket) { previousBucket, newBucket in
                // A size filter asks the Hub for more repos, so switching it on or off needs a new search.
                if (previousBucket == .any) != (newBucket == .any) { runSearch() }
            }

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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if explorer.unknownSizeCountHiddenByFilter > 0 {
                        Text(unknownSizeNote)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }

                    ForEach(explorer.displayedResults) { hubModel in
                        HuggingFaceHubModelRowView(
                            model: hubModel,
                            isInstalled: HuggingFaceHubModelHandoff.isInstalled(hubModel, localModels: localModels.models)
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
    }

    private var unknownSizeNote: String {
        let count = explorer.unknownSizeCountHiddenByFilter

        return count == 1
            ? "1 repo is hidden because its name has no parameter count."
            : "\(count) repos are hidden because their names have no parameter count."
    }

    private var emptyResultsMessage: String {
        if explorer.results.isEmpty { return "No models found" }

        guard explorer.unknownSizeCountHiddenByFilter > 0 else { return "No models in this size range" }

        return "No models in this size range. \(unknownSizeNote)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(explorer.errorMessage ?? emptyResultsMessage)
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
