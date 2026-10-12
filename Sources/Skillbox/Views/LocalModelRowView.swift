import SwiftUI
import ModelInventory

/// One local model row: name, source, estimated RAM, size, and a RAM fit badge.
struct LocalModelRowView: View {
    let model: LocalModel
    let copyCount: Int
    let onReveal: () -> Void

    @State private var isHovering = false

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
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(model.path.path)

            if isHovering {
                Button(action: onReveal) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
                .accessibilityLabel("Reveal \(model.name) in Finder")
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
