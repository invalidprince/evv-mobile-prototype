import Foundation
import CoreLocation

/// Lightweight wrapper around CLLocationManager for acquiring GPS coordinates
/// during clock-in / clock-out. Requests "when in use" permission and provides
/// a one-shot location fetch with a hard timeout so callers never hang.
///
/// IMPORTANT: CLLocationManager must be created on a thread with a run loop
/// (in practice, the main thread) or its delegate callbacks are never
/// delivered. All interaction with the manager is routed through the main
/// queue for that reason.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    @Published var lastLocation: CLLocation?
    @Published var lastFixDate: Date?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isAcquiring = false
    @Published var locationAcquired = false
    @Published var locationError: String?

    private var manager: CLLocationManager!
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    /// Hard cap on how long a one-shot fix may take before resolving nil.
    private static let fixTimeout: TimeInterval = 10
    /// How long to wait for the user to answer the permission dialog.
    private static let authTimeout: TimeInterval = 30
    /// A cached fix younger than this is accepted without waiting for GPS.
    private static let cachedFixMaxAge: TimeInterval = 60
    /// Maximum horizontal accuracy (meters) for an acceptable cached fix.
    private static let cachedFixMaxAccuracy: CLLocationAccuracy = 150

    override init() {
        super.init()
        if Thread.isMainThread {
            setupManager()
        } else {
            DispatchQueue.main.sync { self.setupManager() }
        }
    }

    private func setupManager() {
        manager = CLLocationManager()
        manager.delegate = self
        // Ten-meter accuracy resolves much faster than kCLLocationAccuracyBest
        // and is far tighter than any geofence we check against (~300 ft).
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorizationStatus = manager.authorizationStatus
    }

    /// Returns a recent, reasonably accurate cached location if one exists
    /// (either our own last fix or the system's cached location).
    private func recentCachedLocation() -> CLLocation? {
        let candidates = [lastLocation, manager.location].compactMap { $0 }
        for loc in candidates {
            let age = Date().timeIntervalSince(loc.timestamp)
            if age >= 0 && age < Self.cachedFixMaxAge
                && loc.horizontalAccuracy >= 0
                && loc.horizontalAccuracy <= Self.cachedFixMaxAccuracy {
                return loc
            }
        }
        return nil
    }

    /// Fire-and-forget warm-up: kicks off a location fix in the background so
    /// that by the time the user reaches a punch confirmation the coordinates
    /// are already available. Safe to call repeatedly.
    func warmUp() {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways
            || status == .notDetermined else { return }
        if isAcquiring { return }
        if recentCachedLocation() != nil { return }  // already warm
        Task { _ = await self.acquireLocation() }
    }

    /// Request location permission (call early, e.g. at login).
    func requestPermission() {
        DispatchQueue.main.async {
            self.manager.requestWhenInUseAuthorization()
        }
    }

    /// Acquire current location (one-shot). Returns the location or nil on
    /// failure/denial/timeout. Never throws and never hangs.
    func acquireLocation() async -> CLLocation? {
        await MainActor.run {
            isAcquiring = true
            locationAcquired = false
            locationError = nil
        }

        // Resolve authorization first. If the user hasn't been asked yet,
        // trigger the prompt and wait (bounded) for an answer.
        var status = manager.authorizationStatus
        if status == .notDetermined {
            requestPermission()
            let deadline = Date().addingTimeInterval(Self.authTimeout)
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 250_000_000)
                status = manager.authorizationStatus
                if status != .notDetermined { break }
            }
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            await MainActor.run {
                isAcquiring = false
                locationError = "Location access denied"
            }
            return nil
        }

        // Fast path: accept a recent cached fix (<60s old, reasonable
        // accuracy) instead of waiting for a brand-new GPS solution.
        if let cached = recentCachedLocation() {
            await MainActor.run {
                lastLocation = cached
                lastFixDate = Date()
                isAcquiring = false
                locationAcquired = true
            }
            return cached
        }

        // One-shot fix with a hard timeout.
        let location: CLLocation? = await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            DispatchQueue.main.async {
                // If a previous request is somehow still pending, fail it
                // so we never leak/double-resume a continuation.
                if let pending = self.continuation {
                    self.continuation = nil
                    pending.resume(returning: nil)
                }
                self.continuation = cont
                self.manager.requestLocation()
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.fixTimeout) {
                    if let timedOut = self.continuation {
                        self.continuation = nil
                        timedOut.resume(returning: nil)
                    }
                }
            }
        }

        await MainActor.run {
            isAcquiring = false
            if let loc = location {
                lastLocation = loc
                lastFixDate = Date()
                locationAcquired = true
            } else {
                locationError = "Could not determine location"
            }
        }

        return location
    }

    /// Current lat/lng/accuracy if available.
    var currentCoordinates: (lat: Double, lng: Double, accuracy: Double)? {
        guard let loc = lastLocation else { return nil }
        return (lat: loc.coordinate.latitude, lng: loc.coordinate.longitude, accuracy: loc.horizontalAccuracy)
    }

    // MARK: - CLLocationManagerDelegate
    // Delegate callbacks arrive on the main thread (manager created there).

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Always cache the newest fix — even a fix that arrives after a
        // timeout benefits the next punch via the cached-fix fast path.
        if let newest = locations.last {
            lastLocation = newest
            lastFixDate = Date()
        }
        let cont = continuation
        continuation = nil
        cont?.resume(returning: locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationManager error: \(error.localizedDescription)")
        let cont = continuation
        continuation = nil
        cont?.resume(returning: nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}
