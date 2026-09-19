import Testing
@testable import Skillbox

struct EditorDetectorTests {
    @Test func zedIsPreferredDefaultEditor() {
        #expect(EditorDetector.preferredCommand == "zed")
        #expect(EditorDetector.knownEditors.first?.command == EditorDetector.preferredCommand)
    }
}
