import SwiftUI

struct SkillInstallProgressView: View {
    let source: String
    let stage: SkillInstallStage
    var installedNames: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(source)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
            ForEach(SkillInstallStage.allCases, id: \.rawValue) { step in
                HStack(spacing: 10) {
                    if !installedNames.isEmpty || step.rawValue < stage.rawValue {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if step == stage {
                        ProgressView().controlSize(.small).frame(width: 16)
                    } else {
                        Image(systemName: "circle").foregroundStyle(.tertiary)
                    }
                    Text(step.label).font(.system(size: 12))
                }
            }
            if !installedNames.isEmpty {
                Text("Ready to use in Claude")
                    .font(.system(size: 13, weight: .semibold))
                Text(installedNames.joined(separator: ", "))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
