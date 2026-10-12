import Foundation
import StatementPaddingRules

/// `statement-padding lint|fix <file or folder>...` checks or rewrites every `.swift` file under the given paths.
let arguments = Array(CommandLine.arguments.dropFirst())

guard let mode = arguments.first, ["lint", "fix"].contains(mode), arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: statement-padding lint|fix <path>...\n".utf8))
    exit(2)
}

func swiftFiles(under path: String) -> [URL] {
    let url = URL(fileURLWithPath: path)
    var isDirectory: ObjCBool = false

    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
    guard isDirectory.boolValue else { return url.pathExtension == "swift" ? [url] : [] }

    let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)

    return (enumerator?.allObjects as? [URL] ?? [])
        .filter { $0.pathExtension == "swift" && !$0.path.contains("/.build/") }
        .sorted { $0.path < $1.path }
}

var violationCount = 0

for file in arguments.dropFirst().flatMap(swiftFiles(under:)) {
    guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }

    if mode == "fix" {
        let fixed = StatementPadding.fixed(source)

        if fixed != source {
            try fixed.write(to: file, atomically: true, encoding: .utf8)
        }

        continue
    }

    for violation in StatementPadding.violations(in: source) {
        violationCount += 1
        print("\(file.path):\(violation.line):\(violation.column): error: [StatementPadding] \(StatementPadding.message)")
    }
}

exit(violationCount == 0 ? 0 : 1)
