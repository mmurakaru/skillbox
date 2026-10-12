import SwiftUI

enum EnvWindowIdentifier {
    static let addEnvVar = "env-add"
    static let mcpSecretConnection = "mcp-secret-connection"
}

/// Regular windows keep typing and multi-step flows alive when the menu bar panel loses focus.
struct EnvWindowScenes: Scene {
    let envStore: EnvVarStore
    let keychainSecrets: KeychainSecretsModel

    var body: some Scene {
        Window("Add env var", id: EnvWindowIdentifier.addEnvVar) {
            EnvAddWindowContent()
                .environment(envStore)
                .environment(keychainSecrets)
                .background(RegularWindowActivation())
        }
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        WindowGroup("Connect to an MCP server", id: EnvWindowIdentifier.mcpSecretConnection, for: String.self) { $secretName in
            if let secretName {
                MCPSecretConnectionWindowContent(secretName: secretName)
                    .environment(envStore)
                    .environment(keychainSecrets)
                    .background(RegularWindowActivation())
            }
        }
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

private struct EnvAddWindowContent: View {
    @Environment(EnvVarStore.self) private var store
    @Environment(KeychainSecretsModel.self) private var keychainSecrets
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        EnvAddForm(
            availableScopes: store.addableScopes,
            onAdd: { key, value, destination in
                do {
                    switch destination {
                    case .settings(let scope):
                        try store.add(key: key, value: value, scope: scope)
                    case .keychain:
                        try await keychainSecrets.addSecret(named: key, value: value)
                    }
                    dismissWindow(id: EnvWindowIdentifier.addEnvVar)

                    return nil
                } catch {
                    return error.localizedDescription
                }
            },
            onCancel: { dismissWindow(id: EnvWindowIdentifier.addEnvVar) }
        )
    }
}

private struct MCPSecretConnectionWindowContent: View {
    let secretName: String

    @Environment(EnvVarStore.self) private var store
    @Environment(KeychainSecretsModel.self) private var keychainSecrets
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        MCPSecretConnectionForm(
            secretName: secretName,
            connector: MCPSecretConnector(),
            plaintextCopies: store.plaintextCopies(ofSecretNamed: secretName),
            keychainHoldsSameValue: { await keychainSecrets.keychainHoldsSameValue(as: $0) },
            onRemovePlaintextCopy: { try store.delete($0) },
            onClose: { dismissWindow(id: EnvWindowIdentifier.mcpSecretConnection, value: secretName) }
        )
    }
}
