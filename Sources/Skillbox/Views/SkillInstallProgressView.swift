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
                    Group {
                        if !installedNames.isEmpty || step.rawValue < stage.rawValue {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if step == stage {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 16, height: 16)
                    Text(step.label).font(.system(size: 12))
                }
            }
            if !installedNames.isEmpty {
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
