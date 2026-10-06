import Foundation
import Observation

@MainActor
@Observable
final class SkillInstallModel {
    enum Phase: Equatable {
        case input, running, done
    }

    private(set) var phase: Phase = .input
    private(set) var source = ""
    private(set) var output = SkillInstallOutput()
    private(set) var installedNames: [String] = []
    private(set) var errorMessage: String?

    func installSkill(source: String, rootPath: String, mountPath: String, service: RemoteSkillService) async {
        guard phase != .running else { return }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.source = trimmed
        phase = .running
        output = SkillInstallOutput()
        installedNames = []
        errorMessage = nil
        do {
            let installed = try await service.install(source: trimmed, rootPath: rootPath, claudeMountPath: mountPath) { [weak self] in
                self?.output.append($0)
            }
            installedNames = installed.names
            phase = .done
        } catch {
            errorMessage = error.localizedDescription
            phase = .input
        }
    }
}
