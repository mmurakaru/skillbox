import AppKit
import SwiftUI

/// A regular window keeps the usage editor alive when the menu bar popover loses focus.
struct UsageSnapshotScene: Scene {
    let store: ProviderUsageStore
    var body: some Scene {
        WindowGroup("Usage snapshot", id: "usage-snapshot", for: UsageProvider.self) { $provider in
            if let provider {
                UsageSnapshotEditor(provider: provider, snapshot: store.snapshots[provider]) {
                    store.saveManualSnapshot($0)
                }
                .background(RegularWindowActivation())
            }
        }
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
