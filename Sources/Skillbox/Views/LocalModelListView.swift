import AppKit
import ModelInventory
import SwiftUI

/// Models tab: the AI models stored on this Mac, with size, RAM fit, and duplicate copies.
struct LocalModelListView: View {
    @Environment(LocalModelStore.self) private var store
    @State private var trashErrorMessage: String?

    @State private var isWindowVisible = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                summary
                Spacer(minLength: 0)
                findDuplicatesButton
                rescanButton
            }
            .frame(height: 26)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            searchBar
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            Divider()

            if let trashErrorMessage {
                ErrorBannerView(message: trashErrorMessage) { self.trashErrorMessage = nil }
            }

            list
        }
        .background(WindowVisibilityReader { isWindowVisible = $0 })
        .task(id: isWindowVisible) {
            guard isWindowVisible else { return }
            while !Task.isCancelled {
                await store.refreshRuntimeStates()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onAppear { store.watchModelFoldersCreatedSinceLastCheck() }
    }

    private func moveToTrash(_ model: LocalModel) {
        do {
            try store.moveToTrash(model)
            trashErrorMessage = nil
        } catch {
            trashErrorMessage = "Could not move \(model.name) to the Trash: \(error.localizedDescription)"
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(store.models.count) model\(store.models.count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold))

            if !store.models.isEmpty {
                HStack(spacing: 4) {
                    Text("\(store.totalBytes.formattedFileSize) on disk")

                    if store.reclaimableBytes > 0 {
                        Text("· \(store.reclaimableBytes.formattedFileSize) reclaimable")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    private var findDuplicatesButton: some View {
        toolbarIconButton(
            systemImage: "doc.on.doc",
            isBusy: store.isDetectingDuplicates,
            isDisabled: store.models.isEmpty || store.isDetectingDuplicates,
            help: "Find duplicate copies",
            action: { store.findDuplicates() }
        )
    }

    private var rescanButton: some View {
        toolbarIconButton(
            systemImage: "arrow.clockwise",
            isBusy: store.isScanning,
            isDisabled: store.isScanning,
            help: "Rescan model folders",
            action: { store.rescan() }
        )
    }

    private func toolbarIconButton(
        systemImage: String,
        isBusy: Bool,
        isDisabled: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 26)
            .glassEffect(.regular, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .accessibilityLabel(help)
    }

    private var searchBar: some View {
        @Bindable var store = store

        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search models", text: $store.searchQuery)
                .textFieldStyle(.plain)

            if !store.searchQuery.isEmpty {
                Button(action: { store.searchQuery = "" }) {
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

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if store.filteredModels.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ForEach(store.filteredModels) { model in
                        LocalModelRowView(
                            model: model,
                            copyCount: store.copyCount(for: model),
                            runtimeState: store.runtimeState(for: model),
                            canMoveToTrash: LocalModelTrashPolicy.canMoveToTrash(model),
                            onReveal: { NSWorkspace.shared.activateFileViewerSelecting([model.path]) },
                            onStop: { Task { await store.stop(model) } },
                            onMoveToTrash: { moveToTrash(model) }
                        )
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "internaldrive")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            if store.isScanning && store.models.isEmpty {
                Text("Scanning model folders…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if store.searchQuery.isEmpty {
                Text("No local models found")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Skillbox looks in Ollama, the Hugging Face cache, LM Studio, and app model folders. Choose sources in Settings.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            } else {
                Text("No matches for \"\(store.searchQuery)\"")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
