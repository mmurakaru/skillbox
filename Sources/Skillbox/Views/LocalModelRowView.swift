import SwiftUI
import ModelInventory

/// One local model row: name, source, estimated RAM, size, RAM fit badge, and loaded state.
struct LocalModelRowView: View {
    let model: LocalModel
    let copyCount: Int
    let runtimeState: ModelRuntimeState?
    let canMoveToTrash: Bool
    let onReveal: () -> Void
    let onStop: () -> Void
    let onMoveToTrash: () -> Void

    @State private var isHovering = false
    @State private var isConfirmingStop = false
    @State private var isConfirmingTrash = false

    private static let physicalMemoryBytes = Int64(ProcessInfo.processInfo.physicalMemory)

    private var estimatedRAMBytes: Int64 {
        ModelRAMEstimate.bytes(forModelSize: model.sizeBytes)
    }

    private var ramFit: ModelRAMFit {
        ModelRAMFit.evaluate(estimatedRAMBytes: estimatedRAMBytes, physicalMemoryBytes: Self.physicalMemoryBytes)
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(model.source.displayName)
                    Text("~\(estimatedRAMBytes.formattedFileSize) RAM")
                    if copyCount > 1 {
                        Text("\(copyCount) copies")
                            .foregroundStyle(.orange)
                    }
                    if let runtimeState {
                        Text("Loaded")
                            .foregroundStyle(.blue)
                            .help("Loaded in memory by \(runtimeState.hostName)")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(model.path.path)

            if isHovering {
                hoverActions
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(model.sizeBytes.formattedFileSize)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                ramFitBadge
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .confirmationDialog("Unload \(model.name)?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
            Button("Unload", role: .destructive, action: onStop)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(stopMessage)
        }
        .confirmationDialog("Move \(model.name) to the Trash?", isPresented: $isConfirmingTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive, action: onMoveToTrash)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.sizeBytes.formattedFileSize) at \(model.path.path)")
        }
    }

    private var stopMessage: String {
        switch runtimeState?.stopTarget {
        case .ollama: "Ollama unloads the model and frees about \(estimatedRAMBytes.formattedFileSize) of memory."
        case .process(_, let commandName): "Stops the \(commandName) process that serves this model."
        case .none: ""
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 2) {
            if runtimeState?.stopTarget != nil {
                rowActionButton(systemImage: "stop.circle", help: "Unload from memory") { isConfirmingStop = true }
            }
            rowActionButton(systemImage: "folder", help: "Reveal in Finder", action: onReveal)
            if canMoveToTrash {
                rowActionButton(systemImage: "trash", help: "Move to Trash") { isConfirmingTrash = true }
            }
        }
    }

    private func rowActionButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel("\(help): \(model.name)")
    }

    private var ramFitBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: ramFit.systemImage)
            Text(ramFit.label)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(ramFitTint)
        .help("Estimated \(estimatedRAMBytes.formattedFileSize) of \(Self.physicalMemoryBytes.formattedFileSize) RAM")
    }

    private var ramFitTint: Color {
        switch ramFit {
        case .fits: .green
        case .tight: .orange
        case .tooBig: .red
        }
    }
}
