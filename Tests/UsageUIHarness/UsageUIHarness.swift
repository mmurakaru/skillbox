import Foundation
import SwiftUI

/// Exercises production Usage views with fake sign-ins and isolated persistence. No Keychain or network calls.
@main struct SkillboxUsageUIHarness: App {
    @State private var store: ProviderUsageStore
    init() {
        let reporter = Timer(timeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated {
                let windows = NSApp.windows.map {
                    ["title": $0.title, "visible": String($0.isVisible), "key": String($0.isKeyWindow), "number": String($0.windowNumber)]
                }
                let state: [String: Any] = ["active": NSApp.isActive, "windows": windows]

                if let path = ProcessInfo.processInfo.environment["SKILLBOX_UI_HARNESS_STATE"],
                    let data = try? JSONSerialization.data(withJSONObject: state)
                {
                    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
                }
            }
        }

        RunLoop.main.add(reporter, forMode: .common)
        guard let defaults = UserDefaults(suiteName: "SkillboxUsageUIHarness.\(UUID().uuidString)") else {
            fatalError("The harness needs isolated defaults so it never touches real usage snapshots.")
        }

        let store = ProviderUsageStore(fetcher: HarnessUsageFetcher(), defaults: defaults)

        _store = State(initialValue: store)
    }
    var body: some Scene {
        MenuBarExtra("Skillbox Usage QA", systemImage: "testtube.2") {
            UsageOverviewView().environment(store).frame(width: 360, height: 480)
                .task { store.startAutoRefresh(interval: .seconds(2)) }
        }
        .menuBarExtraStyle(.window)
        UsageSnapshotScene(store: store)
        Settings { Text("Harness settings").frame(width: 440, height: 500) }
    }
}

private actor HarnessUsageFetcher: ProviderUsageFetching {
    private var reads = 0
    func fetchUsage(for provider: UsageProvider, allowKeychainPrompt: Bool) async throws -> ProviderUsageSnapshot {
        reads += 1
        FileHandle.standardError.write(Data("Fixture refresh \(provider.rawValue) count \(reads)\n".utf8))

        return .init(
            provider: provider, plan: provider == .codex ? "Pro Lite" : provider == .grok ? "SuperGrok" : "Team",
            windows: [.init(label: "Weekly limit", usedPercent: Double(reads % 100), resetsAt: Date().addingTimeInterval(604800))],
            details: [.init(label: "Credits", value: "0")], updatedAt: Date(), source: .live,
            accountEmail: "\(provider.rawValue)@example.com")
    }
}
