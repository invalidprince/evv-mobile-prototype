import Foundation

/// Persistent on-disk cache for offline data (individuals, services, etc.).
/// Stores JSON files in the app's Application Support directory so they survive
/// app restarts but are excluded from iCloud backup.
final class LocalCache {
    static let shared = LocalCache()

    private let fileManager = FileManager.default
    private let cacheDir: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("EVVCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - File paths

    private var individualsURL: URL { cacheDir.appendingPathComponent("individuals.json") }
    private var offlineQueueURL: URL { cacheDir.appendingPathComponent("offline-queue.json") }

    // MARK: - Cached envelope (data + timestamp)

    private struct CachedEnvelope<T: Codable>: Codable {
        let data: T
        let lastUpdated: Date
    }

    // MARK: - Individuals

    /// Persist the individuals list (includes each individual's authorized services).
    func saveIndividuals(_ individuals: [ServerIndividualOption]) {
        let envelope = CachedEnvelope(data: individuals, lastUpdated: Date())
        do {
            let data = try JSONEncoder().encode(envelope)
            try data.write(to: individualsURL, options: .atomic)
            DiagnosticLogger.shared.logSync("Cached \(individuals.count) individuals to disk")
        } catch {
            DiagnosticLogger.shared.logAPI("Failed to cache individuals: \(error.localizedDescription)")
        }
    }

    /// Load cached individuals (nil if never cached).
    func loadIndividuals() -> [ServerIndividualOption]? {
        guard let data = try? Data(contentsOf: individualsURL),
              let envelope = try? JSONDecoder().decode(CachedEnvelope<[ServerIndividualOption]>.self, from: data) else {
            return nil
        }
        DiagnosticLogger.shared.logSync("Loaded \(envelope.data.count) individuals from cache")
        return envelope.data
    }

    /// Timestamp of the last successful individuals cache write.
    func individualsLastUpdated() -> Date? {
        guard let data = try? Data(contentsOf: individualsURL),
              let envelope = try? JSONDecoder().decode(CachedEnvelope<[ServerIndividualOption]>.self, from: data) else {
            return nil
        }
        return envelope.lastUpdated
    }

    // MARK: - Offline queue (EVV punches must survive an app kill/restart)

    private struct QueueEnvelope: Codable {
        let staffId: String?
        let actions: [QueuedAction]
        let lastUpdated: Date
    }

    /// Persist the offline action queue. Written on EVERY queue mutation so a
    /// killed/crashed app never loses a queued punch (they are legal EVV
    /// records). The owning staff id is stored alongside so a different user
    /// signing in on the same device can never replay someone else's punches
    /// under their own token.
    func saveOfflineQueue(_ actions: [QueuedAction], staffId: String?) {
        if actions.isEmpty {
            try? fileManager.removeItem(at: offlineQueueURL)
            return
        }
        let envelope = QueueEnvelope(staffId: staffId, actions: actions, lastUpdated: Date())
        do {
            let data = try JSONEncoder().encode(envelope)
            try data.write(to: offlineQueueURL, options: .atomic)
        } catch {
            DiagnosticLogger.shared.logAPI("Failed to persist offline queue: \(error.localizedDescription)")
        }
    }

    /// Load the persisted offline queue for this staff member. Returns nil if
    /// nothing was saved or the saved queue belongs to a different staff id
    /// (in which case it is deliberately left on disk untouched — the owner
    /// may sign back in).
    func loadOfflineQueue(matching staffId: String) -> [QueuedAction]? {
        guard let data = try? Data(contentsOf: offlineQueueURL),
              let envelope = try? JSONDecoder().decode(QueueEnvelope.self, from: data) else {
            return nil
        }
        guard envelope.staffId == staffId else {
            DiagnosticLogger.shared.logSync("Persisted offline queue belongs to another staff id — not restoring")
            return nil
        }
        DiagnosticLogger.shared.logSync("Restored \(envelope.actions.count) offline action(s) from disk")
        return envelope.actions
    }

    // MARK: - Clear (e.g. on sign-out)

    func clearAll() {
        try? fileManager.removeItem(at: individualsURL)
        try? fileManager.removeItem(at: offlineQueueURL)
        DiagnosticLogger.shared.logSync("Local cache cleared")
    }
}
