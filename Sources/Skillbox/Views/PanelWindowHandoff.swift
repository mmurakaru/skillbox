import AppKit
import SwiftUI

/// Clicking a sheet attached to the menu bar panel makes the panel resign key and close, so input flows open regular windows.
@MainActor
enum PanelWindowHandoff {
    /// Opens the window first and closes the panel a moment later, so the app never has no window to activate.
    static func open(closing panel: NSWindow?, _ openWindow: () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak panel] in
            panel?.close()
        }
    }
}

/// Captures the containing menu bar window so opening a regular window can dismiss that specific panel.
struct HostingWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()

        view.onWindow = onWindow

        return view
    }

    func updateNSView(_ nsView: WindowView, context: Context) { nsView.onWindow = onWindow }

    final class WindowView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let capturedWindow = window

            DispatchQueue.main.async { [weak self] in self?.onWindow?(capturedWindow) }
        }
    }
}

@MainActor
final class HostingWindowReference {
    weak var window: NSWindow?
}

/// Activates and makes a regular window key, following the Settings window's focus handling.
struct RegularWindowActivation: NSViewRepresentable {
    func makeNSView(context: Context) -> ActivationView { ActivationView() }

    func updateNSView(_ nsView: ActivationView, context: Context) {}

    final class ActivationView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }

            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak window] in
                NSApp.activate(ignoringOtherApps: true)
                window?.orderFrontRegardless()
                window?.makeKeyAndOrderFront(nil)
            }
        }
    }
}
