import Foundation

enum EnvSecretDetection {
    /// Whole `_`-separated name tokens, so names like `GIT_AUTHOR_NAME` or `KEYBOARD_LAYOUT` do not count.
    static let secretNameTokens: Set<String> = ["KEY", "TOKEN", "SECRET", "PASSWORD", "AUTH"]

    /// Catalog settings documented as non-credentials (e.g. a max-tokens limit) never count as secrets by name.
    static func nameLooksSecret(_ key: String) -> Bool {
        if let catalogEntry = EnvVarCatalog.entry(for: key), catalogEntry.category != .auth { return false }
        return key.uppercased().split(separator: "_").contains { secretNameTokens.contains(String($0)) }
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
