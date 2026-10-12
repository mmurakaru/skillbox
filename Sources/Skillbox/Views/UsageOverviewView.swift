import SwiftUI

/// Shows one stacked usage card per provider, consistently filling bars by percent used.
struct UsageOverviewView: View {
    @Environment(ProviderUsageStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var hostingWindow = UsageWindowReference()

    var body: some View {
        VStack(spacing: 0) {
            TabHeaderView(title: "Usage", subtitle: "Subscription limits · refreshes every 5 minutes") {
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(!store.refreshing.isEmpty)
                .help("Refresh live usage")
                .accessibilityLabel("Refresh live usage")
            }
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(UsageProvider.allCases) { provider in
                        ProviderUsageCard(
                            provider: provider,
                            snapshot: store.snapshots[provider],
                            error: store.errors[provider],
                            isRefreshing: store.refreshing.contains(provider),
                            onEdit: {
                                let panel = hostingWindow.window
                                NSApp.activate(ignoringOtherApps: true)
                                openWindow(id: "usage-snapshot", value: provider)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak panel] in
                                    panel?.close()
                                }
                            },
                            onUseLive: { Task { await store.refresh(provider, useLive: true, allowKeychainPrompt: provider == .claude) } },
                            onRefresh: { Task { await store.refresh(provider, useLive: true) } }
                        )
                    }
                }
                .padding(14)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
        .background(UsageHostingWindowReader { hostingWindow.window = $0 })
        .task { await store.refreshAll() }

    }
}

private struct ProviderUsageCard: View {
    let provider: UsageProvider
    let snapshot: ProviderUsageSnapshot?
    let error: String?
    let isRefreshing: Bool
    let onEdit: () -> Void
    let onUseLive: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                ProviderUsageLogo(provider: provider)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name).font(.system(size: 13, weight: .semibold))
                    if let plan = snapshot?.plan, !plan.isEmpty {
                        Text(plan).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isRefreshing { ProgressView().controlSize(.small) }
                Text(snapshot?.source == .manual ? "Manual" : snapshot == nil ? "Not connected" : error != nil ? "Last known" : Date().timeIntervalSince(snapshot!.updatedAt) > 300 ? "Cached" : "Live snapshot")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05), in: Capsule())
            }
            if let email = snapshot?.accountEmail, !email.isEmpty {
                Text(email).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .help("Connected account")
            } else if snapshot?.source == .live {
                Text("Account email unavailable").font(.caption).foregroundStyle(.secondary)
            }
            let windows = snapshot?.windows.isEmpty == false ? snapshot!.windows : provider.windowLabels.map {
                ProviderUsageWindow(label: $0, usedPercent: nil, resetsAt: nil)
            }
            ForEach(windows) { window in
                usageWindow(window)
            }
            if let snapshot, !snapshot.details.isEmpty {
                Divider()
                VStack(spacing: 5) {
                    ForEach(snapshot.details) { detail in
                        HStack(alignment: .firstTextBaseline) {
                            Text(detail.label).foregroundStyle(.secondary)
                            Spacer()
                            Text(detail.value).multilineTextAlignment(.trailing)
                        }
                        .font(.caption)
                    }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .center, spacing: 10) {
                if let snapshot {
                    Text(snapshot.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .help("Snapshot captured at \(snapshot.updatedAt.formatted())")
                }
                Spacer(minLength: 0)
                if provider == .grok, snapshot == nil {
                    Link("Connect Grok", destination: URL(string: "https://docs.x.ai/build/overview")!)
                        .help("Install the official Grok CLI and run grok login, then refresh")
                }
                Button("Refresh", action: onRefresh).disabled(isRefreshing)
                    .accessibilityIdentifier("usage-\(provider.rawValue)-refresh")
                Button(snapshot == nil ? "Add snapshot" : "Edit", action: onEdit)
                    .accessibilityIdentifier("usage-\(provider.rawValue)-edit")
                if provider == .claude, snapshot == nil || error != nil {
                    Button("Connect Claude Code", action: onUseLive).disabled(isRefreshing)
                }
            }
            .font(.system(size: 11))
            .buttonStyle(.borderless)
        }
        .padding(13)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.09)))
    }

    private func usageWindow(_ window: ProviderUsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.label).font(.system(size: 12, weight: .medium))
                Spacer()
                if let percent = window.usedPercent {
                    Text("\(percent.formatted(.number.precision(.fractionLength(0...1))))% used")
                        .monospacedDigit()
                } else {
                    Text("Unavailable")
                }
            }
            .font(.caption)
            ProgressView(value: window.usedPercent ?? 0, total: 100)
                .tint((window.usedPercent ?? 0) >= 90 ? .red : .primary)
                .opacity(window.usedPercent == nil ? 0.35 : 1)
                .accessibilityLabel(window.label)
                .accessibilityValue(window.usedPercent.map { "\($0.formatted()) percent used" } ?? "Usage unavailable")
            HStack {
                if let reset = window.resetsAt {
                    Text("\(reset <= Date() ? "Reset was" : "Resets") \(reset.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))")
                } else {
                    Text("Reset time unavailable")
                }
                Spacer()
                if let percent = window.usedPercent {
                    Text("\((100 - percent).formatted(.number.precision(.fractionLength(0...1))))% left")
                }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}


/// Captures the containing menu bar window so opening an editor can dismiss that specific panel.
private struct UsageHostingWindowReader: NSViewRepresentable {
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
private final class UsageWindowReference {
    weak var window: NSWindow?
}
