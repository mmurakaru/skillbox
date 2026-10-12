import CoreGraphics
import Testing

@testable import Skillbox

struct HoverActionLabelLayoutTests {
    private let bubble = CGSize(width: 100, height: 20)
    private let panel = CGSize(width: 400, height: 480)

    @Test func placesTheLabelBelowTheButtonWhenItFits() {
        let center = HoverActionLabelLayout.center(
            bubbleSize: bubble, buttonFrame: CGRect(x: 200, y: 100, width: 22, height: 22), containerSize: panel, placement: .belowOrAbove)

        #expect(center == CGPoint(x: 211, y: 136))
    }

    @Test func flipsAboveTheButtonAtTheBottomEdge() {
        let center = HoverActionLabelLayout.center(
            bubbleSize: bubble, buttonFrame: CGRect(x: 200, y: 450, width: 22, height: 22), containerSize: panel, placement: .belowOrAbove)

        #expect(center.y == 436)
    }

    @Test func keepsTheLabelInsideThePanelAtTheTrailingEdge() {
        let center = HoverActionLabelLayout.center(
            bubbleSize: bubble, buttonFrame: CGRect(x: 380, y: 100, width: 22, height: 22), containerSize: panel, placement: .belowOrAbove)

        #expect(center.x == 346)
    }

    @Test func placesTrailingLabelsBesideTheButtonAndInsideThePanel() {
        let besideSidebarIcon = HoverActionLabelLayout.center(
            bubbleSize: bubble, buttonFrame: CGRect(x: 7, y: 2, width: 36, height: 36), containerSize: panel, placement: .trailing)

        #expect(besideSidebarIcon == CGPoint(x: 97, y: 20))
    }
}
