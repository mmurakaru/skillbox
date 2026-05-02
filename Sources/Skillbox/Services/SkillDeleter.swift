import Foundation

enum SkillDeleter {
    @discardableResult
    static func trash(_ skill: Skill) -> Result<Void, Error> {
        do {
            try FileManager.default.trashItem(at: skill.folderURL, resultingItemURL: nil)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
