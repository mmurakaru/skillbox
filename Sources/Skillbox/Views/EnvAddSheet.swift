import SwiftUI

/// Where a new env var is stored: a settings.json scope for plain values, the login Keychain for secrets.
enum EnvAddDestination: Equatable {
    case settings(EnvScope)
    case keychain
}

struct EnvAddSheet: View {
    let availableScopes: [EnvScope]
    /// Receives key, value, and destination; returns an error message or nil.
    let onAdd: (String, String, EnvAddDestination) -> String?
    let onCancel: () -> Void

    @State private var keyText: String = ""
    @State private var valueText: String = ""
    @State private var selectedScopeIndex: Int = 0
    @State private var isMarkedSecret: Bool = false
    @State private var errorMessage: String?
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add env var")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Key")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("CLAUDE_CODE_…", text: $keyText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($keyFocused)
                    .onChange(of: keyText) { _, newValue in
                        if let entry = EnvVarCatalog.entry(for: newValue), valueText.isEmpty {
                            valueText = entry.suggestedValue
                        }
                    }

                if !suggestions.isEmpty {
                    suggestionsList
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Value")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Secret", isOn: secretToggleBinding)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .disabled(nameLooksSecret)
                        .help(nameLooksSecret ? "Detected as a secret from its name" : "Store this value in the login Keychain")
                }
                Group {
                    if isSecret {
                        SecureField("Secret value", text: $valueText)
                    } else {
                        TextField("1", text: $valueText)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isSecret ? "Storage" : "Scope")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if isSecret {
                    Label("Login Keychain", systemImage: "key.fill")
                        .font(.system(size: 12))
                    Text("Nothing is written to settings.json, so the value doesn't reach every process Claude Code starts.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("", selection: $selectedScopeIndex) {
                        ForEach(Array(availableScopes.enumerated()), id: \.offset) { index, scope in
                            Text(scopeLabel(scope)).tag(index)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            keyFocused = true
        }
    }

    private var nameLooksSecret: Bool {
        EnvSecretDetection.nameLooksSecret(keyText.trimmingCharacters(in: .whitespaces))
    }

    private var isSecret: Bool { nameLooksSecret || isMarkedSecret }

    private var secretToggleBinding: Binding<Bool> {
        Binding(get: { isSecret }, set: { isMarkedSecret = $0 })
    }

    private var suggestions: [EnvVarCatalogEntry] {
        EnvVarCatalog.suggestions(matching: keyText, limit: 5)
            .filter { $0.key != keyText }
    }

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions, id: \.key) { entry in
                Button(action: {
                    keyText = entry.key

                    if valueText.isEmpty { valueText = entry.suggestedValue }
                }) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.key)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                        Text(entry.description)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func scopeLabel(_ scope: EnvScope) -> String {
        switch scope {
        case .userGlobal: "User Global (~/.claude/settings.json)"
        case .project(let name, _): "\(name) (project)"
        case .projectLocal(let name, _): "\(name) (local)"
        }
    }

    private func submit() {
        let trimmedKey = keyText.trimmingCharacters(in: .whitespaces)

        guard !trimmedKey.isEmpty else { return }
        let destination: EnvAddDestination

        if isSecret {
            destination = .keychain
        } else {
            guard availableScopes.indices.contains(selectedScopeIndex) else { return }
            destination = .settings(availableScopes[selectedScopeIndex])
        }

        if let addError = onAdd(trimmedKey, valueText, destination) {
            errorMessage = addError
        }
    }
}
