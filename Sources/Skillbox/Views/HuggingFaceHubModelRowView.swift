import AppKit
import ModelInventory
import SwiftUI

/// One Hub search result: name, lab, parameter hint, downloads, and hand-off actions on hover.
struct HuggingFaceHubModelRowView: View {
    let model: HuggingFaceHubModel
    let isInstalled: Bool

    @State private var isHovering = false
    @State private var didCopyCommand = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                            .help("Installed on this Mac")
                            .accessibilityLabel("Installed on this Mac")
                    }
                }
                Text(model.lab)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                HStack(spacing: 2) {
                    RowHoverActionButton(
                        systemImage: didCopyCommand ? "checkmark" : "doc.on.clipboard",
                        help: "Copy \(HuggingFaceHubModelHandoff.downloadCommand(for: model))",
                        action: copyDownloadCommand
                    )
                    RowHoverActionButton(systemImage: "arrow.up.right.square", help: "Open model page", action: openModelPage)
                }
            }

            VStack(alignment: .trailing, spacing: 2) {
                if let parameterHint = model.parameterHint {
                    Text(parameterHint)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let downloads = model.downloads {
                    Text("\(downloads.formatted(.number.notation(.compactName))) downloads")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
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

    private func copyDownloadCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(HuggingFaceHubModelHandoff.downloadCommand(for: model), forType: .string)
        didCopyCommand = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            didCopyCommand = false
        }
    }

    private func openModelPage() {
        guard let url = HuggingFaceHubModelHandoff.modelPageURL(for: model) else { return }
        NSWorkspace.shared.open(url)
    }
}
