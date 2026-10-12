import Foundation

enum EnvSecretDetection {
    /// Name fragments that mark an env var as a credential, matched case-insensitively.
    static let secretNameMarkers = ["KEY", "TOKEN", "SECRET", "PASSWORD", "AUTH"]

    /// Catalog settings documented as non-credentials (e.g. a max-tokens limit) never count as secrets by name.
    static func nameLooksSecret(_ key: String) -> Bool {
        if let catalogEntry = EnvVarCatalog.entry(for: key), catalogEntry.category != .auth { return false }
        let uppercased = key.uppercased()
        return secretNameMarkers.contains { uppercased.contains($0) }
    }

    static func isSecret(key: String, markedSecretNames: Set<String>) -> Bool {
        nameLooksSecret(key) || markedSecretNames.contains(key)
    }
}

struct EnvSecretMarksFile {
    let fileURL: URL

    func load() -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL),
              let names = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(names)
    }

    func save(_ names: Set<String>) throws {
        let data = try JSONEncoder().encode(names.sorted())
        try data.write(to: fileURL, options: .atomic)
    }
}
