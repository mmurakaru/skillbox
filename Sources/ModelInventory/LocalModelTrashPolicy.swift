import Foundation

/// Which local models Skillbox may move to the Trash.
public enum LocalModelTrashPolicy {
    /// Ollama tags share content-addressed blobs, so trashing one manifest could orphan or break others.
    public static func canMoveToTrash(_ model: LocalModel) -> Bool {
        model.format != .ollamaBlob
    }
}
