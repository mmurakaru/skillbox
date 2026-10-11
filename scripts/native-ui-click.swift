import Foundation
import CoreGraphics
import Darwin

// The native Usage UI harness uses actual mouse events, rather than AXPress actions.
guard CommandLine.arguments.count == 3,
      let x = Double(CommandLine.arguments[1]), let y = Double(CommandLine.arguments[2]),
      x.isFinite, y.isFinite else { exit(2) }
guard CGPreflightPostEventAccess() else {
    fputs("Native UI testing requires Accessibility permission for the invoking terminal.\n", stderr)
    exit(3)
}
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)
for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { exit(4) }
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.post(tap: .cghidEventTap)
    usleep(50_000)
}
