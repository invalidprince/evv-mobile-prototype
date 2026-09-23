import Foundation

/// Lightweight in-app circular buffer for diagnostic events.
/// Collects API errors, sync events, and screen-level errors so Nick
/// can POST them to the server for remote diagnosis.
///
/// 🚨 Build 92: THE BUFFER SURVIVES A PROCESS KILL.
/// Until build 91 this was memory-only, so every crash erased its own
/// evidence: Nick's frozen-then-dead app on build 91 (unresponsive OK
/// button, then gone — the signature of an iOS watchdog kill, 0x8badf00d)
/// submitted a diagnostic log containing ONLY post-relaunch entries. The
/// minutes that actually mattered died with the process.
///
/// Every entry is now appended to a JSON-lines file in Application Support
/// and the tail is reloaded at launch, so the NEXT submission carries the
/// pre-crash entries. Design notes:
///   • JSON-lines (one JSON object per line) is append-only — a kill
///     mid-write costs at most the final partial line, which the loader
///     skips. A single re-encoded JSON array would risk the whole file.
///   • Writes go through the existing concurrent queue's barrier (never the
///     main thread) and flush on every append, because a watchdog kill gives
///     no warning and no time to drain a timer. A `FileHandle` is held open
///     so the cost is one `write(2)`, not an open/close per entry.
///   • Bounded two ways — `maxEntries` in memory, and the file is trimmed
///     (rewritten from the in-memory ring) once it passes `maxFileBytes` or
///     `trimEveryNWrites` appends, so it can never grow without limit.
///   • `entryCount`/`exportEntries` keep their old shapes, so the submit
///     path (`AppState.submitDiagnosticLog` → `POST /logs`) needs no change:
///     it simply now sees the older entries too, oldest first.
final class DiagnosticLogger {
    static let shared = DiagnosticLogger()

    struct Entry: Codable {
        let timestamp: String
        let category: String   // "api", "sync", "screen", "offline", "general", "lifecycle"
        let message: String
    }

    private let queue = DispatchQueue(label: "diagnostic-logger", attributes: .concurrent)
    private var buffer: [Entry] = []
    private let maxEntries = 500

    // MARK: - Persistence state

    /// Rewrite the file from the in-memory ring once it exceeds this size.
    private let maxFileBytes: Int = 256 * 1024
    /// …or after this many appends, whichever comes first (cheap guard so a
    /// long-running session with small entries still gets compacted).
    private let trimEveryNWrites = 200

    private let fileManager = FileManager.default
    private let logFileURL: URL?
    private var handle: FileHandle?
    private var writesSinceTrim = 0
    private var bytesWritten = 0

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {
        let dir = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("EVVCache", isDirectory: true)
        if let dir = dir {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            logFileURL = dir.appendingPathComponent("diagnostic-log.jsonl")
        } else {
            logFileURL = nil
        }
        loadPersistedTail()
        openHandle()
    }

    // MARK: - Logging

    func log(_ category: String, _ message: String) {
        let entry = Entry(
            timestamp: DiagnosticLogger.isoFormatter.string(from: Date()),
            category: category,
            message: message
        )
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.buffer.append(entry)
            if self.buffer.count > self.maxEntries {
                self.buffer.removeFirst(self.buffer.count - self.maxEntries)
            }
            self.appendToDisk(entry)
        }
    }

    func logAPI(_ message: String) { log("api", message) }
    func logSync(_ message: String) { log("sync", message) }
    func logScreen(_ message: String) { log("screen", message) }
    func logOffline(_ message: String) { log("offline", message) }
    func logLifecycle(_ message: String) { log("lifecycle", message) }

    /// Relaunch boundary marker. Called once from `AppState.init()` so a
    /// submitted log reads unambiguously: everything ABOVE this line is from
    /// a previous process (i.e. from before a crash / watchdog kill / force
    /// quit), everything below is this run.
    func markLaunch() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        log("lifecycle", "=== app launched (v\(version) build \(build), \(os)) — entries above this line are from a previous run ===")
    }

    // MARK: - Export

    /// Returns all buffered entries as a JSON-compatible array of
    /// dictionaries, OLDEST FIRST — persisted pre-crash entries followed by
    /// this run's. Consumed by `AppState.submitDiagnosticLog()`.
    func exportEntries() -> [[String: String]] {
        queue.sync {
            buffer.map { ["timestamp": $0.timestamp, "category": $0.category, "message": $0.message] }
        }
    }

    /// Clears the buffer after a successful submission — including the
    /// persisted copy, otherwise every future submission would re-send
    /// entries the server already has.
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.buffer.removeAll()
            self.rewriteFile()
        }
    }

    var entryCount: Int {
        queue.sync { buffer.count }
    }

    // MARK: - Disk (all callers are already inside the barrier, or init)

    /// Load the tail of the persisted file into the buffer at launch.
    /// A truncated final line (the process died mid-write) fails to decode
    /// and is skipped rather than poisoning the whole load.
    private func loadPersistedTail() {
        guard let url = logFileURL,
              let data = try? Data(contentsOf: url),
              !data.isEmpty else { return }
        let decoder = JSONDecoder()
        var restored: [Entry] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard !line.isEmpty,
                  let entry = try? decoder.decode(Entry.self, from: Data(line)) else { continue }
            restored.append(entry)
        }
        if restored.count > maxEntries {
            restored.removeFirst(restored.count - maxEntries)
        }
        buffer = restored
    }

    private func openHandle() {
        guard let url = logFileURL else { return }
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        if let h = handle {
            let end = (try? h.seekToEnd()) ?? 0
            bytesWritten = Int(end)
        }
        // Exclude the diagnostic log from iCloud backup, matching LocalCache.
        if var u = logFileURL {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? u.setResourceValues(values)
        }
        // The buffer may already hold the reloaded tail; if the file grew
        // large across runs, compact it now rather than on the first write.
        if bytesWritten > maxFileBytes { rewriteFile() }
    }

    private func appendToDisk(_ entry: Entry) {
        guard let h = handle else { return }
        guard let line = encodeLine(entry) else { return }
        do {
            try h.write(contentsOf: line)
        } catch {
            return
        }
        bytesWritten += line.count
        writesSinceTrim += 1
        if bytesWritten > maxFileBytes || writesSinceTrim >= trimEveryNWrites {
            rewriteFile()
        }
    }

    /// Rewrite the file from the in-memory ring — this IS the trim: the ring
    /// is already capped at `maxEntries`, so the rewritten file is bounded.
    private func rewriteFile() {
        guard let url = logFileURL else { return }
        var data = Data()
        for entry in buffer {
            if let line = encodeLine(entry) { data.append(line) }
        }
        try? handle?.close()
        handle = nil
        try? data.write(to: url, options: .atomic)
        writesSinceTrim = 0
        bytesWritten = data.count
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    private func encodeLine(_ entry: Entry) -> Data? {
        guard var data = try? JSONEncoder().encode(entry) else { return nil }
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
