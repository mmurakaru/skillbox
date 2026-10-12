import Testing
import Foundation
@testable import ModelInventory

struct DuplicateModelDetectorTests {
    private func writeModel(_ name: String, contents: Data, in directory: ModelInventoryTestDirectory) throws -> LocalModel {
        let url = try directory.writeFile(name, contents: contents)
        return LocalModel(
            id: "custom:\(url.path)",
            name: url.deletingPathExtension().lastPathComponent,
            source: .custom,
            path: url,
            format: .gguf,
            sizeBytes: Int64(contents.count)
        )
    }

    @Test func groupsIdenticalFilesAndComputesReclaimableBytes() async throws {
        let directory = try ModelInventoryTestDirectory()
        let shared = Data(repeating: 7, count: 4096)
        let first = try writeModel("copy-a.gguf", contents: shared, in: directory)
        let second = try writeModel("copy-b.gguf", contents: shared, in: directory)
        let other = try writeModel("other.gguf", contents: Data(repeating: 9, count: 4096), in: directory)

        let groups = await DuplicateModelDetector().findDuplicates(in: [first, second, other])

        #expect(groups.count == 1)
        #expect(Set(groups.first?.models.map(\.id) ?? []) == [first.id, second.id])
        #expect(groups.first?.reclaimableBytes == 4096)
    }

    @Test func neverGroupsUniqueSizes() async throws {
        let directory = try ModelInventoryTestDirectory()
        let small = try writeModel("a.gguf", contents: Data(repeating: 1, count: 100), in: directory)
        let large = try writeModel("b.gguf", contents: Data(repeating: 1, count: 200), in: directory)
        #expect(await DuplicateModelDetector().findDuplicates(in: [small, large]).isEmpty)
    }

    @Test func doesNotGroupSameSizeWithDifferentContent() async throws {
        let directory = try ModelInventoryTestDirectory()
        let first = try writeModel("a.gguf", contents: Data(repeating: 1, count: 512), in: directory)
        let second = try writeModel("b.gguf", contents: Data(repeating: 2, count: 512), in: directory)
        #expect(await DuplicateModelDetector().findDuplicates(in: [first, second]).isEmpty)
    }

    @Test func groupsByProvidedDigestWithoutReadingFiles() async {
        let first = LocalModel(id: "ollama:a", name: "a", source: .ollama,
                               path: URL(fileURLWithPath: "/nonexistent/a"), format: .ollamaBlob,
                               sizeBytes: 10, digest: "sha256:abc")
        let second = LocalModel(id: "ollama:b", name: "b", source: .ollama,
                                path: URL(fileURLWithPath: "/nonexistent/b"), format: .ollamaBlob,
                                sizeBytes: 10, digest: "sha256:abc")

        let groups = await DuplicateModelDetector().findDuplicates(in: [first, second])

        #expect(groups.count == 1)
        #expect(groups.first?.reclaimableBytes == 10)
    }
}
