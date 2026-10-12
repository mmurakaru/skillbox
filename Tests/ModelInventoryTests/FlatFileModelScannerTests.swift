import Testing
import Foundation
@testable import ModelInventory

struct FlatFileModelScannerTests {
    @Test func findsWeightFilesWithSizesAndFormats() throws {
        let directory = try ModelInventoryTestDirectory()
        try directory.writeFile("qwen3.5-9b-q4_k_m.gguf", bytes: 1234)
        try directory.writeFile("nested/llama-3-8b.safetensors", bytes: 50)
        try directory.writeFile("notes.txt", bytes: 10)

        let models = FlatFileModelScanner(source: .custom, roots: [directory.url])
            .scan()
            .sorted { $0.sizeBytes > $1.sizeBytes }

        #expect(models.map(\.name) == ["qwen3.5-9b-q4_k_m", "llama-3-8b"])
        #expect(models.map(\.sizeBytes) == [1234, 50])
        #expect(models.map(\.format) == [.gguf, .safetensors])
        #expect(models.allSatisfy { $0.source == .custom })
    }

    @Test func missingRootYieldsNothing() throws {
        let directory = try ModelInventoryTestDirectory()
        let scanner = FlatFileModelScanner(source: .custom, roots: [directory.url.appending(path: "missing")])
        #expect(scanner.scan().isEmpty)
    }

    @Test func inventoryDropsRepeatedIDsAndSortsLargestFirst() throws {
        let directory = try ModelInventoryTestDirectory()
        try directory.writeFile("small.gguf", bytes: 100)
        try directory.writeFile("big.gguf", bytes: 9000)

        let models = LocalModelInventory.aggregate([
            FlatFileModelScanner(source: .custom, roots: [directory.url]),
            FlatFileModelScanner(source: .custom, roots: [directory.url]),
        ])

        #expect(models.map(\.name) == ["big", "small"])
    }
}
