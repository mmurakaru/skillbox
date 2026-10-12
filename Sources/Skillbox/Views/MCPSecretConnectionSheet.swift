import SwiftUI

/// Picks a user-scope HTTP MCP server and wires one Keychain secret into its request headers.
struct MCPSecretConnectionSheet: View {
    let secretName: String
    let connector: MCPSecretConnector
    let onClose: () -> Void

    @State private var servers: [ClaudeHTTPMCPServer] = []
    @State private var selectedServerName: String?
    @State private var headerName = MCPSecretHeadersHelper.defaultHeaderName
    @State private var valuePrefix = MCPSecretHeadersHelper.defaultValuePrefix
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isConfirmingStaticHeaderRemoval = false

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

            Text("Claude Code runs a helper on each connection that reads the secret from the Keychain. Existing static headers stay as a fallback until you remove them. Remove a plaintext env copy from its row in the Env list.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let selectedServer, selectedServerUsesThisSecret, selectedServer.staticHeaderNames.contains(headerName) {
                staticHeaderCleanup(for: selectedServer)
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

    private func staticHeaderCleanup(for server: ClaudeHTTPMCPServer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isConfirmingStaticHeaderRemoval {
                Text("Sessions that started before the helper was added still send the static header until they reconnect. Remove it now?")
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { isConfirmingStaticHeaderRemoval = false }
                        .controlSize(.small)
                    Button("Remove static header") { removeStaticHeader(from: server) }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
            } else {
                HStack {
                    Text("\(server.name) still has a static \(headerName) header.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove…") { isConfirmingStaticHeaderRemoval = true }
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

    private func removeStaticHeader(from server: ClaudeHTTPMCPServer) {
        errorMessage = nil
        do {
            try connector.removeStaticHeader(named: headerName, fromServer: server.name)
            isConfirmingStaticHeaderRemoval = false
            statusMessage = "Removed the static \(headerName) header from \(server.name)."
            loadServers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
