import Foundation

enum JSONMemberTextEditorError: Error, Equatable {
    case malformedJSON
    case memberNotFound([String])
}

/// Re-encoding the whole Claude Code config would reorder keys and reformat numbers, so only one member's text changes.
enum JSONMemberTextEditor {
    static func replacingMember(at path: [String], in text: String, with newValue: Any) throws -> String {
        let bytes = Array(text.utf8)
        var scanner = Scanner(bytes: bytes)
        let span = try scanner.valueSpan(at: path)
        let indentLevel = scanner.indentLevel(ofValueStartingAt: span.lowerBound)
        let originalValue = try JSONSerialization.jsonObject(with: Data(bytes[span]), options: .fragmentsAllowed)
        let rendered = try render(newValue, original: (originalValue, Array(bytes[span])), indentLevel: indentLevel)
        return String(decoding: bytes[..<span.lowerBound], as: UTF8.self) + rendered + String(decoding: bytes[span.upperBound...], as: UTF8.self)
    }

    private static func render(_ value: Any, original: (value: Any, text: [UInt8])?, indentLevel: Int) throws -> String {
        if let original, (value as AnyObject).isEqual(original.value) {
            return String(decoding: original.text, as: UTF8.self)
        }
        guard let object = value as? [String: Any] else {
            return try renderFresh(value, indentLevel: indentLevel)
        }
        guard let original, original.value is [String: Any] else {
            return try renderFresh(object, indentLevel: indentLevel)
        }
        var scanner = Scanner(bytes: original.text)
        let originalMembers = try scanner.objectMembers(startingAt: 0)
        let originalKeys = originalMembers.map(\.key)
        let orderedKeys = originalKeys.filter { object[$0] != nil } + object.keys.filter { !originalKeys.contains($0) }.sorted()
        guard !orderedKeys.isEmpty else { return "{}" }
        let memberIndent = String(repeating: "  ", count: indentLevel + 1)
        let lines = try orderedKeys.map { key -> String in
            let originalMember = originalMembers.first { $0.key == key }
            let originalPair = try originalMember.map { member -> (Any, [UInt8]) in
                let memberText = Array(original.text[member.valueSpan])
                return (try JSONSerialization.jsonObject(with: Data(memberText), options: .fragmentsAllowed), memberText)
            }
            return memberIndent + (try encodeString(key)) + ": " + (try render(object[key]!, original: originalPair, indentLevel: indentLevel + 1))
        }
        return "{\n" + lines.joined(separator: ",\n") + "\n" + String(repeating: "  ", count: indentLevel) + "}"
    }

    /// Matches `JSON.stringify(value, null, 2)` for values that have no original text to keep.
    private static func renderFresh(_ value: Any, indentLevel: Int) throws -> String {
        let indent = String(repeating: "  ", count: indentLevel)
        let memberIndent = indent + "  "
        if let object = value as? [String: Any] {
            guard !object.isEmpty else { return "{}" }
            let lines = try object.keys.sorted().map { memberIndent + (try encodeString($0)) + ": " + (try renderFresh(object[$0]!, indentLevel: indentLevel + 1)) }
            return "{\n" + lines.joined(separator: ",\n") + "\n" + indent + "}"
        }
        if let array = value as? [Any] {
            guard !array.isEmpty else { return "[]" }
            let lines = try array.map { memberIndent + (try renderFresh($0, indentLevel: indentLevel + 1)) }
            return "[\n" + lines.joined(separator: ",\n") + "\n" + indent + "]"
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private static func encodeString(_ string: String) throws -> String {
        try renderFresh(string, indentLevel: 0)
    }

    private struct Member {
        let key: String
        let valueSpan: Range<Int>
    }

    private struct Scanner {
        let bytes: [UInt8]
        var position = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func valueSpan(at path: [String]) throws -> Range<Int> {
            position = 0
            skipWhitespace()
            var span = position..<(try endOfValue(startingAt: position))
            for (depth, key) in path.enumerated() {
                guard let member = try objectMembers(startingAt: span.lowerBound).first(where: { $0.key == key }) else {
                    throw JSONMemberTextEditorError.memberNotFound(Array(path[...depth]))
                }
                span = member.valueSpan
            }
            return span
        }

        func indentLevel(ofValueStartingAt offset: Int) -> Int {
            var lineStart = offset
            while lineStart > 0, bytes[lineStart - 1] != UInt8(ascii: "\n") { lineStart -= 1 }
            var spaces = 0
            while lineStart + spaces < offset, bytes[lineStart + spaces] == UInt8(ascii: " ") { spaces += 1 }
            return spaces / 2
        }

        mutating func objectMembers(startingAt offset: Int) throws -> [Member] {
            position = offset
            skipWhitespace()
            guard current == UInt8(ascii: "{") else { throw JSONMemberTextEditorError.malformedJSON }
            position += 1
            var members: [Member] = []
            skipWhitespace()
            if current == UInt8(ascii: "}") { return members }
            while true {
                skipWhitespace()
                let keyStart = position
                let keyEnd = try endOfString(startingAt: keyStart)
                let key = try JSONSerialization.jsonObject(with: Data(bytes[keyStart..<keyEnd]), options: .fragmentsAllowed) as? String
                guard let key else { throw JSONMemberTextEditorError.malformedJSON }
                position = keyEnd
                skipWhitespace()
                guard current == UInt8(ascii: ":") else { throw JSONMemberTextEditorError.malformedJSON }
                position += 1
                skipWhitespace()
                let valueStart = position
                let valueEnd = try endOfValue(startingAt: valueStart)
                members.append(Member(key: key, valueSpan: valueStart..<valueEnd))
                position = valueEnd
                skipWhitespace()
                if current == UInt8(ascii: ",") { position += 1; continue }
                guard current == UInt8(ascii: "}") else { throw JSONMemberTextEditorError.malformedJSON }
                return members
            }
        }

        private var current: UInt8? { position < bytes.count ? bytes[position] : nil }

        private mutating func skipWhitespace() {
            while let byte = current, byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 { position += 1 }
        }

        private func endOfString(startingAt offset: Int) throws -> Int {
            guard offset < bytes.count, bytes[offset] == UInt8(ascii: "\"") else { throw JSONMemberTextEditorError.malformedJSON }
            var index = offset + 1
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "\\"): index += 2
                case UInt8(ascii: "\""): return index + 1
                default: index += 1
                }
            }
            throw JSONMemberTextEditorError.malformedJSON
        }

        private func endOfValue(startingAt offset: Int) throws -> Int {
            guard offset < bytes.count else { throw JSONMemberTextEditorError.malformedJSON }
            switch bytes[offset] {
            case UInt8(ascii: "\""):
                return try endOfString(startingAt: offset)
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                var depth = 0
                var index = offset
                while index < bytes.count {
                    switch bytes[index] {
                    case UInt8(ascii: "\""):
                        index = try endOfString(startingAt: index)
                        continue
                    case UInt8(ascii: "{"), UInt8(ascii: "["):
                        depth += 1
                    case UInt8(ascii: "}"), UInt8(ascii: "]"):
                        depth -= 1
                        if depth == 0 { return index + 1 }
                    default:
                        break
                    }
                    index += 1
                }
                throw JSONMemberTextEditorError.malformedJSON
            default:
                var index = offset
                while index < bytes.count, ![UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), 0x20, 0x0A, 0x0D, 0x09].contains(bytes[index]) {
                    index += 1
                }
                return index
            }
        }
    }
}
