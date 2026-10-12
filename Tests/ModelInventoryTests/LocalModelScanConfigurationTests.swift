import Testing
import Foundation
@testable import ModelInventory

struct LocalModelScanConfigurationTests {
    private let home = URL(fileURLWithPath: "/tmp/example-home")

    private func disabledConfiguration(customPaths: [URL] = []) -> LocalModelScanConfiguration {
        LocalModelScanConfiguration(ollama: false, huggingFace: false, lmStudio: false,
                                    openWhispr: false, appSupport: false, customPaths: customPaths)
    }

    @Test func parseCustomPathsTrimsBlanksAndExpandsTilde() {
        let paths = LocalModelScanConfiguration.parseCustomPaths("/a/b ,  , ~/models ,")
        #expect(paths.count == 2)
        #expect(paths.first?.path == "/a/b")
        #expect(paths.last?.path.contains("~") == false)
        #expect(paths.last?.path.hasSuffix("/models") == true)
    }

    @Test func blankCustomPathsParseToNothing() {
        #expect(LocalModelScanConfiguration.parseCustomPaths("   ").isEmpty)
    }

    @Test func scannersReflectEnabledSources() {
        var configuration = disabledConfiguration()
        configuration.ollama = true
        #expect(configuration.makeScanners(home: home, applicationSupport: nil).map(\.source) == [.ollama])
    }

    @Test func allSourcesDisabledYieldsNoScanners() {
        #expect(disabledConfiguration().makeScanners(home: home, applicationSupport: nil).isEmpty)
    }

    @Test func customPathsAddCustomScanner() {
        let configuration = disabledConfiguration(customPaths: [URL(fileURLWithPath: "/tmp/models")])
        #expect(configuration.makeScanners(home: home, applicationSupport: nil).map(\.source) == [.custom])
    }

    @Test func defaultsEnableAllKnownSources() throws {
        let applicationSupport = try ModelInventoryTestDirectory()
        let sources = Set(LocalModelScanConfiguration().makeScanners(home: home, applicationSupport: applicationSupport.url).map(\.source))
        #expect(sources == [.ollama, .huggingFaceCache, .lmStudio, .openWhispr, .appSupport])
    }

    @Test func applicationSupportSweepFindsOnlyExistingModelFolders() throws {
        let applicationSupport = try ModelInventoryTestDirectory()
        try applicationSupport.writeFile("SomeApp/models/weights.gguf", bytes: 1)
        try FileManager.default.createDirectory(at: applicationSupport.url.appending(path: "OtherApp"), withIntermediateDirectories: true)

        let folders = LocalModelScanConfiguration.applicationSupportModelFolders(in: applicationSupport.url)

        #expect(folders.map(\.lastPathComponent) == ["models"])
        #expect(folders.first?.deletingLastPathComponent().lastPathComponent == "SomeApp")
    }
}
