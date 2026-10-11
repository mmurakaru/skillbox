import SwiftUI
import AppKit

/// A regular window keeps the usage editor alive when the menu bar popover loses focus.
struct UsageSnapshotScene: Scene {
    let store: ProviderUsageStore
    var body: some Scene {
        WindowGroup("Usage snapshot", id: "usage-snapshot", for: UsageProvider.self) { $provider in
            if let provider {
                UsageSnapshotEditor(provider: provider, snapshot: store.snapshots[provider]) {
                    store.saveManualSnapshot($0)
                }
                .background(UsageEditorWindowActivation())
            }
        }
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Activates and makes the editor key, following the Settings window's focus handling.
private struct UsageEditorWindowActivation: NSViewRepresentable {
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
