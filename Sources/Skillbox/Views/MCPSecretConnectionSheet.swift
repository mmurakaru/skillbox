import SwiftUI

/// Picks a user-scope HTTP MCP server and wires one Keychain secret into its request headers.
struct MCPSecretConnectionSheet: View {
    let secretName: String
    let connector: MCPSecretConnector
    /// Settings.json copies of this secret that keep it in every agent subprocess environment.
    let plaintextCopies: [EnvVar]
    let keychainHoldsSameValue: (EnvVar) -> Bool
    let onRemovePlaintextCopy: (EnvVar) throws -> Void
    let onClose: () -> Void

    @State private var servers: [ClaudeHTTPMCPServer] = []
    @State private var selectedServerName: String?
    @State private var headerName = MCPSecretHeadersHelper.defaultHeaderName
    @State private var valuePrefix = MCPSecretHeadersHelper.defaultValuePrefix
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isConfirmingCleanup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect \(secretName) to an MCP server")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Server")
                if servers.isEmpty {
                    Text("No user-scope HTTP MCP servers found in the Claude Code config.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Picker("", selection: $selectedServerName) {
                        ForEach(servers) { server in
                            Text(serverLabel(server)).tag(Optional(server.name))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Header")
                    TextField(MCPSecretHeadersHelper.defaultHeaderName, text: $headerName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Value prefix")
                    TextField("none", text: $valuePrefix)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                .frame(width: 110)
            }

            Text("Claude Code runs a helper on each connection that reads the secret from the Keychain. Existing static headers and plaintext env copies stay as a fallback until you remove them.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let selectedServer, selectedServerUsesThisSecret, !cleanupItems(for: selectedServer).isEmpty {
                fallbackCleanup(for: selectedServer)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }

            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(selectedServerUsesThisSecret ? "Reconnect" : "Connect", action: connect)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedServerName == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .task { loadServers() }
    }

    private var selectedServer: ClaudeHTTPMCPServer? {
        servers.first { $0.name == selectedServerName }
    }

    private var selectedServerUsesThisSecret: Bool {
        guard let helper = selectedServer?.headersHelper else { return false }
        return MCPSecretHeadersHelper.commandReadsSecret(helper, secretName: secretName)
    }

    private func cleanupItems(for server: ClaudeHTTPMCPServer) -> [String] {
        var items: [String] = []
        if server.staticHeaderNames.contains(headerName) { items.append("the static \(headerName) header") }
        if !plaintextCopies.isEmpty {
            items.append(plaintextCopies.count == 1 ? "1 env copy" : "\(plaintextCopies.count) env copies")
        }
        return items
    }

    private func fallbackCleanup(for server: ClaudeHTTPMCPServer) -> some View {
        let items = cleanupItems(for: server).joined(separator: " and ")
        return VStack(alignment: .leading, spacing: 6) {
            if isConfirmingCleanup {
                Text("Sessions that started before the helper was added still use \(items) until they restart or reconnect. Remove \(items) now?")
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { isConfirmingCleanup = false }
                        .controlSize(.small)
                    Button("Remove") { removeFallbacks(from: server) }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
            } else {
                HStack {
                    Text("Still in plaintext: \(items).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Remove…") { isConfirmingCleanup = true }
                        .controlSize(.small)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func serverLabel(_ server: ClaudeHTTPMCPServer) -> String {
        let host = URL(string: server.url)?.host ?? server.url
        let marker = server.headersHelper.map { MCPSecretHeadersHelper.commandReadsSecret($0, secretName: secretName) } == true ? " - connected" : ""
        return "\(server.name) (\(host))\(marker)"
    }

    private func loadServers() {
        do {
            servers = try connector.configEditor.userScopeHTTPServers()
            if selectedServerName == nil || selectedServer == nil {
                selectedServerName = servers.first?.name
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func connect() {
        guard let serverName = selectedServerName else { return }
        errorMessage = nil
        statusMessage = nil
        do {
            try connector.connect(secretName: secretName, serverName: serverName, headerName: headerName, valuePrefix: valuePrefix)
            statusMessage = "\(serverName) reads \(headerName) from the Keychain on its next connection."
            loadServers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeFallbacks(from server: ClaudeHTTPMCPServer) {
        errorMessage = nil
        do {
            let removesStaticHeader = server.staticHeaderNames.contains(headerName)
            try PlaintextSecretCleanup(
                plaintextCopies: plaintextCopies,
                keychainHoldsSameValue: keychainHoldsSameValue,
                removeStaticHeader: removesStaticHeader
                    ? { try connector.removeStaticHeader(named: headerName, fromServer: server.name) }
                    : nil,
                removePlaintextCopy: onRemovePlaintextCopy
            ).run()
            isConfirmingCleanup = false
            statusMessage = "\(server.name) now reads \(headerName) only from the Keychain."
            loadServers()
        } catch {
            errorMessage = error.localizedDescription
            loadServers()
        }
    }
}
