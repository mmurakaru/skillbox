import Foundation

/// Combines scanner results into the local model inventory.
public enum LocalModelInventory {
    /// Runs every scanner, drops repeated ids, and sorts largest first. Safe off the main thread.
    public static func aggregate(_ scanners: [any LocalModelScanner]) -> [LocalModel] {
        var seenIDs = Set<String>()
        var models: [LocalModel] = []
        for scanner in scanners {
            for model in scanner.scan() where seenIDs.insert(model.id).inserted {
                models.append(model)
            }
        }
        return models.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
