import AppKit
import SwiftUI

/// Reports whether the hosting window is on screen; a menu bar panel keeps its views alive while hidden.
struct WindowVisibilityReader: NSViewRepresentable {
    let onVisibilityChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()

        view.onVisibilityChange = onVisibilityChange

        return view
    }

    func updateNSView(_ nsView: VisibilityView, context: Context) {
        nsView.onVisibilityChange = onVisibilityChange
    }

    final class VisibilityView: NSView {
        var onVisibilityChange: ((Bool) -> Void)?
        private var occlusionObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }

            occlusionObserver = nil
            guard let window else {
                report(false)

                return
            }
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    self?.report(window?.occlusionState.contains(.visible) == true)
                }
            }
            report(window.occlusionState.contains(.visible))
        }

        private func report(_ isVisible: Bool) {
            let callback = onVisibilityChange

            DispatchQueue.main.async { callback?(isVisible) }
        }
    }
}
