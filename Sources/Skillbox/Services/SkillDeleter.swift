import Foundation

enum SkillDeleter {
    @discardableResult
    static func trash(_ skill: Skill) -> Result<Void, Error> {
        trashURL(skill.folderURL)
    }

    @discardableResult
    static func trashURL(_ url: URL) -> Result<Void, Error> {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
