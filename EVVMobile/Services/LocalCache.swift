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

    // MARK: - Clear (e.g. on sign-out)

    func clearAll() {
        try? fileManager.removeItem(at: individualsURL)
        DiagnosticLogger.shared.logSync("Local cache cleared")
    }
}
