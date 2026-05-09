import Foundation

enum InsightsReportWriter {
    /// Write the rendered HTML to `~/Library/Caches/Skillbox/insights-<ISO8601>.html`.
    /// Creates the parent dir if missing. Returns the file URL.
    static func write(html: String) throws -> URL {
        let cacheRoot = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = cacheRoot.appendingPathComponent("Skillbox", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let stamp = filenameTimestamp(Date())
        let fileURL = dir.appendingPathComponent("insights-\(stamp).html")
        try html.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Filesystem-safe ISO8601-ish timestamp (`2026-05-09T08-30-15Z`).
    static func filenameTimestamp(_ date: Date, timeZone: TimeZone = TimeZone(identifier: "UTC") ?? .current) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.string(from: date)
    }
}
