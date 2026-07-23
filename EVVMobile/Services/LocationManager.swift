import Foundation
import CoreLocation

/// Lightweight wrapper around CLLocationManager for acquiring GPS coordinates
/// during clock-in. Requests "when in use" permission and provides a one-shot
/// location fetch.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isAcquiring = false
    @Published var locationAcquired = false
    @Published var locationError: String?

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    /// Request location permission (call early, e.g. at login)
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Acquire current location (one-shot). Returns the location or nil on failure.
    func acquireLocation() async -> CLLocation? {
        // Reset state
        await MainActor.run {
            isAcquiring = true
            locationAcquired = false
            locationError = nil
        }

        // Check authorization
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            await MainActor.run {
                isAcquiring = false
                locationError = "Location access denied"
            }
            return nil
        }

        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // Wait briefly for the permission dialog
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                await MainActor.run {
                    isAcquiring = false
                    locationError = "Location access denied"
                }
                return nil
            }
        }

        // Request location
        let location = await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            self.continuation = cont
            self.manager.requestLocation()
        }

        await MainActor.run {
            isAcquiring = false
            if let loc = location {
                lastLocation = loc
                locationAcquired = true
            } else {
                locationError = "Could not determine location"
            }
        }

        return location
    }

    /// Current lat/lng/accuracy if available
    var currentCoordinates: (lat: Double, lng: Double, accuracy: Double)? {
        guard let loc = lastLocation else { return nil }
        return (lat: loc.coordinate.latitude, lng: loc.coordinate.longitude, accuracy: loc.horizontalAccuracy)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationManager error: \(error.localizedDescription)")
        continuation?.resume(returning: nil)
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}
