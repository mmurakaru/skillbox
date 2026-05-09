import Foundation

enum EnvVarState: Hashable {
    case enabled
    case disabled
}

enum EnvScope: Hashable {
    case userGlobal
    case project(name: String, path: String)
    case projectLocal(name: String, path: String)

    var shortLabel: String {
        switch self {
        case .userGlobal: "Global"
        case .project: "Project"
        case .projectLocal: "Local"
        }
    }

    var displayName: String {
        switch self {
        case .userGlobal: "User Global"
        case .project(let name, _): name
        case .projectLocal(let name, _): name
        }
    }

    /// Path used to group `.project` and `.projectLocal` under one entry in the picker.
    var projectPath: String? {
        switch self {
        case .userGlobal: nil
        case .project(_, let path), .projectLocal(_, let path): path
        }
    }
}

struct EnvVar: Identifiable, Hashable {
    let id: String
    let key: String
    let value: String
    let state: EnvVarState
    let scope: EnvScope
    let fileURL: URL
    let modifiedAt: Date

    init(
        key: String,
        value: String,
        state: EnvVarState,
        scope: EnvScope,
        fileURL: URL,
        modifiedAt: Date
    ) {
        self.id = "\(fileURL.path)#\(key)"
        self.key = key
        self.value = value
        self.state = state
        self.scope = scope
        self.fileURL = fileURL
        self.modifiedAt = modifiedAt
    }

    var isEnabled: Bool { state == .enabled }
}
