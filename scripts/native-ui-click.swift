import Foundation
import CoreGraphics
import Darwin

// Address keyboard input to the harness PID so a focus change cannot type into another app.
let arguments = CommandLine.arguments
if arguments.count == 4, arguments[1] == "type", let pid = Int32(arguments[2]) {
    guard CGPreflightPostEventAccess() else { exit(3) }
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { exit(4) }
        event.flags = down ? .maskCommand : []
        event.postToPid(pid)
    }
    usleep(50_000)
    let text = Array(arguments[3].utf16)
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { exit(4) }
        event.flags = []
        text.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        event.postToPid(pid)
    }
    exit(0)
}
if arguments.count == 3, arguments[1] == "escape", let pid = Int32(arguments[2]) {
    guard CGPreflightPostEventAccess() else { exit(3) }
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down) else { exit(4) }
        event.postToPid(pid)
    }
    exit(0)
}
guard arguments.count == 3,
      let x = Double(arguments[1]), let y = Double(arguments[2]),
      x.isFinite, y.isFinite else { exit(2) }
guard CGPreflightPostEventAccess() else {
    fputs("Native UI testing requires Accessibility permission for the invoking terminal.\n", stderr)
    exit(3)
}
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)
for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { exit(4) }
    event.flags = []
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.post(tap: .cghidEventTap)
    usleep(50_000)
}
