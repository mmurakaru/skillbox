import Foundation

/// A throwaway directory for one test, removed when the value is deinitialized.
final class ModelInventoryTestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "model-inventory-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func writeFile(_ relativePath: String, bytes: Int) throws -> URL {
        try writeFile(relativePath, contents: Data(count: bytes))
    }

    @discardableResult
    func writeFile(_ relativePath: String, contents: Data) throws -> URL {
        let fileURL = url.appending(path: relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL)
        return fileURL
    }
}
