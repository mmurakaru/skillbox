import Foundation

/// Client-side parameter size filter for Hub results; the list API has no reliable size field.
public enum ModelParameterSizeBucket: String, CaseIterable, Identifiable, Sendable {
    case any
    case small
    case medium
    case large
    case extraLarge

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .any: "Any size"
        case .small: "≤ 4B"
        case .medium: "4-13B"
        case .large: "13-34B"
        case .extraLarge: "> 34B"
        }
    }

    public func matches(_ parameterHint: String?) -> Bool {
        guard let bounds = billionBounds else { return true }
        guard let billions = Self.billions(from: parameterHint) else { return false }
        return billions > bounds.exclusiveLower && billions <= bounds.inclusiveUpper
    }

    private var billionBounds: (exclusiveLower: Double, inclusiveUpper: Double)? {
        switch self {
        case .any: nil
        case .small: (-.infinity, 4)
        case .medium: (4, 13)
        case .large: (13, 34)
        case .extraLarge: (34, .infinity)
        }
    }

    /// Parses "135M", "8B", "1.5B", or "8X7B" (56, the mixture total) into billions of parameters.
    public static func billions(from parameterHint: String?) -> Double? {
        guard let hint = parameterHint?.lowercased(), let unit = hint.last, unit == "b" || unit == "m" else { return nil }
        let factors = hint.dropLast().split(separator: "x").compactMap { Double($0) }
        guard !factors.isEmpty else { return nil }
        let count = factors.reduce(1, *)
        return unit == "m" ? count / 1_000 : count
    }
}
