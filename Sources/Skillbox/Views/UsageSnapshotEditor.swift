import SwiftUI

/// Manual usage entry leaves blank fields unknown and stores reset dates in the user's local time.
struct UsageSnapshotEditor: View {
    let provider: UsageProvider
    let onSave: (ProviderUsageSnapshot) -> Void
    private let preservedDetails: [ProviderUsageDetail]
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var email: String
    @State private var subscriptionPrice: String
    @State private var renewalDate: String
    @State private var plan: String
    @State private var windows: [WindowEntry]
    @State private var credits: String
    @State private var autoReload: String
    @State private var resets: String
    @State private var currency: String
    @State private var resetExpiry: String

    private struct WindowEntry: Identifiable {
        var label: String
        var percent: String
        var hasReset: Bool
        var reset: Date
        var id: String { label }
    }

    init(provider: UsageProvider, snapshot: ProviderUsageSnapshot?, onSave: @escaping (ProviderUsageSnapshot) -> Void) {
        self.provider = provider
        self.onSave = onSave
        let editableLabels: Set<String> = ["Credits", "Credit unit", "Auto-reload", "Extra usage", "Reset passes", "Reset pass expiry", "Subscription price", "Renews"]
        self.preservedDetails = (snapshot?.details ?? []).filter { !editableLabels.contains($0.label) }
        _email = State(initialValue: snapshot?.accountEmail ?? "")
        _plan = State(initialValue: snapshot?.plan ?? "")
        let existing = snapshot?.windows ?? []
        let labels = existing.isEmpty ? provider.windowLabels : existing.map(\.label)
        _windows = State(initialValue: labels.map { label in
            let window = existing.first { $0.label == label }
            return WindowEntry(label: label, percent: window?.usedPercent.map { String($0) } ?? "",
                               hasReset: window?.resetsAt != nil, reset: window?.resetsAt ?? Date())
        })
        func detail(_ label: String) -> String { snapshot?.details.first { $0.label == label }?.value ?? "" }
        _subscriptionPrice = State(initialValue: detail("Subscription price"))
        _renewalDate = State(initialValue: detail("Renews"))
        _credits = State(initialValue: detail("Credits"))
        _autoReload = State(initialValue: detail(provider == .claude ? "Extra usage" : "Auto-reload"))
        _resets = State(initialValue: detail("Reset passes"))
        _resetExpiry = State(initialValue: detail("Reset pass expiry"))
        _currency = State(initialValue: detail("Credit unit").isEmpty ? (provider == .codex ? "credits" : provider == .grok ? "USD" : "EUR") : detail("Credit unit"))
    }

    private var isValid: Bool {
        windows.allSatisfy { entry in
            entry.percent.isEmpty || Double(entry.percent).map { $0.isFinite && (0...100).contains($0) } == true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(provider.name) snapshot").font(.headline)
            Text("Copy values from your provider's usage page. Enter percent used, not percent remaining. Blank fields stay unavailable.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Connected account email", text: $email).accessibilityIdentifier("usage-editor-email")
                    TextField("Plan", text: $plan).accessibilityIdentifier("usage-editor-plan")
                    TextField("Subscription price, e.g. €20/month", text: $subscriptionPrice).accessibilityIdentifier("usage-editor-price")
                    TextField("Renewal date from billing page", text: $renewalDate).accessibilityIdentifier("usage-editor-renewal")
                    ForEach($windows) { $entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(entry.label)
                                Spacer()
                                TextField("Used %", text: $entry.percent).frame(width: 80)
                            }
                            Toggle("Known reset time", isOn: $entry.hasReset)
                            if entry.hasReset {
                                DatePicker("Resets", selection: $entry.reset, displayedComponents: [.date, .hourAndMinute])
                            }
                        }
                    }
                    Divider()
                    HStack {
                        TextField("Credit balance", text: $credits)
                        TextField("Unit / currency", text: $currency).frame(width: 110)
                    }
                    Picker(provider == .claude ? "Extra usage" : "Auto-reload", selection: $autoReload) {
                        Text("Unknown").tag("")
                        Text("Enabled").tag("Enabled")
                        Text("Disabled").tag("Disabled")
                    }
                    if provider != .grok {
                        TextField("Available reset passes", text: $resets)
                        TextField("Reset pass expiry, e.g. 22 Oct", text: $resetExpiry)
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
            if !isValid { Text("Percent used must be a number between 0 and 100.").font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismissWindow(id: "usage-snapshot", value: provider) }.keyboardShortcut(.cancelAction).accessibilityIdentifier("usage-editor-cancel")
                Button("Save snapshot") {
                    var details = preservedDetails
                    if !subscriptionPrice.isEmpty { details.append(.init(label: "Subscription price", value: subscriptionPrice)) }
                    if !renewalDate.isEmpty { details.append(.init(label: "Renews", value: renewalDate)) }
                    if !credits.isEmpty {
                        details.append(.init(label: "Credits", value: credits))
                        if !currency.isEmpty { details.append(.init(label: "Credit unit", value: currency)) }
                    }
                    if !autoReload.isEmpty { details.append(.init(label: provider == .claude ? "Extra usage" : "Auto-reload", value: autoReload)) }
                    if provider != .grok, !resets.isEmpty { details.append(.init(label: "Reset passes", value: resets)) }
                    if provider != .grok, !resetExpiry.isEmpty { details.append(.init(label: "Reset pass expiry", value: resetExpiry)) }
                    onSave(.init(provider: provider, plan: plan.isEmpty ? nil : plan,
                                 windows: windows.map { .init(label: $0.label, usedPercent: Double($0.percent), resetsAt: $0.hasReset ? $0.reset : nil) },
                                 details: details, updatedAt: Date(), source: .manual, accountEmail: email.isEmpty ? nil : email))
                    dismissWindow(id: "usage-snapshot", value: provider)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid).accessibilityIdentifier("usage-editor-save")
            }
        }
        .padding(20)
        .frame(width: 440, height: 500)
    }
}
