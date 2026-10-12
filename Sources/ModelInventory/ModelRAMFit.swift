import Foundation

/// Estimated RAM needed to load a model: its on-disk size plus runtime overhead such as the context cache.
public enum ModelRAMEstimate {
    /// Common rule of thumb for weights plus overhead at typical context lengths; long contexts need more.
    public static let overheadFactor = 1.2

    public static func bytes(forModelSize sizeBytes: Int64) -> Int64 {
        Int64((Double(sizeBytes) * overheadFactor).rounded())
    }
}

/// Whether a model's estimated RAM fits this machine's physical memory.
public enum ModelRAMFit: Sendable, Equatable {
    case fits
    case tight
    case tooBig

    /// Fits at 70% of physical memory or less, tight up to 100%, otherwise too big.
    public static func evaluate(estimatedRAMBytes: Int64, physicalMemoryBytes: Int64) -> ModelRAMFit {
        guard physicalMemoryBytes > 0 else { return .tooBig }
        if estimatedRAMBytes <= physicalMemoryBytes * 7 / 10 { return .fits }
        if estimatedRAMBytes <= physicalMemoryBytes { return .tight }
        return .tooBig
    }

    public var label: String {
        switch self {
        case .fits: "Fits"
        case .tight: "Tight"
        case .tooBig: "Too big"
        }
    }

    public var systemImage: String {
        switch self {
        case .fits: "checkmark.circle.fill"
        case .tight: "exclamationmark.triangle.fill"
        case .tooBig: "xmark.circle.fill"
        }
    }
}
