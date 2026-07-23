import Foundation

/// Lightweight in-app circular buffer for diagnostic events.
/// Collects API errors, sync events, and screen-level errors so Nick
/// can POST them to the server for remote diagnosis.
final class DiagnosticLogger {
    static let shared = DiagnosticLogger()

    struct Entry: Codable {
        let timestamp: String
        let category: String   // "api", "sync", "screen", "offline", "general"
        let message: String
    }

    private let queue = DispatchQueue(label: "diagnostic-logger", attributes: .concurrent)
    private var buffer: [Entry] = []
    private let maxEntries = 200

    private init() {}

    // MARK: - Logging

    func log(_ category: String, _ message: String) {
        let entry = Entry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            category: category,
            message: message
        )
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.buffer.append(entry)
            if self.buffer.count > self.maxEntries {
                self.buffer.removeFirst(self.buffer.count - self.maxEntries)
            }
        }
    }

    func logAPI(_ message: String) { log("api", message) }
    func logSync(_ message: String) { log("sync", message) }
    func logScreen(_ message: String) { log("screen", message) }
    func logOffline(_ message: String) { log("offline", message) }

    // MARK: - Export

    /// Returns all buffered entries as a JSON-compatible array of dictionaries.
    func exportEntries() -> [[String: String]] {
        queue.sync {
            buffer.map { ["timestamp": $0.timestamp, "category": $0.category, "message": $0.message] }
        }
    }

    /// Clears the buffer after a successful submission.
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?.buffer.removeAll()
        }
    }

    var entryCount: Int {
        queue.sync { buffer.count }
    }
}
