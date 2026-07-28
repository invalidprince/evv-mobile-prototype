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
    private static let fixTimeout: TimeInterval = 15
    /// How long to wait for the user to answer the permission dialog.
    private static let authTimeout: TimeInterval = 30

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
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
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
