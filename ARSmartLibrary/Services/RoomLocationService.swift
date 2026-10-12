import Combine
import CoreLocation
import Foundation

@MainActor
final class RoomLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isRequesting = false
    @Published private(set) var message = "Room location is optional."
    @Published private(set) var latestGeotag: RoomGeotag?
    var onCaptured: ((RoomGeotag) -> Void)?

    private var manager: CLLocationManager?
    private var requestedFix = false

    func requestLocation() {
        guard !isRequesting else { return }
        isRequesting = true
        message = "Getting the room's approximate location…"
        let manager = CLLocationManager()
        self.manager = manager
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.delegate = self
        handleAuthorization(manager, mayRequestPermission: true)
    }

    func cancel() {
        guard isRequesting else { return }
        finish(message: "Location request canceled.")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.handleAuthorization(manager)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self, self.manager === manager, isRequesting else { return }
            let now = Date()
            let tag = locations.sorted { $0.timestamp > $1.timestamp }
                .compactMap { try? RoomGeotag.capture(from: $0, now: now) }.first
            guard let tag else {
                finish(message: "A recent location accurate within 100 meters was unavailable. Try again near a window or entrance.")
                return
            }
            latestGeotag = tag
            finish(message: "Approximate room location captured.")
            onCaptured?(tag)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.manager === manager, isRequesting else { return }
            if (error as? CLError)?.code == .denied {
                finish(message: "Location access is unavailable. You can allow it in Settings; AR mapping still works.")
            } else {
                finish(message: "Your location could not be found. Try again near a window or entrance; AR mapping still works.")
            }
        }
    }

    private func handleAuthorization(_ manager: CLLocationManager, mayRequestPermission: Bool = false) {
        guard self.manager === manager, isRequesting else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            message = "Allow location access to add the room's approximate location."
            if mayRequestPermission { manager.requestWhenInUseAuthorization() }
        case .authorizedWhenInUse, .authorizedAlways:
            guard !requestedFix else { return }
            requestedFix = true
            message = "Getting the room's approximate location…"
            manager.requestLocation()
        case .denied:
            finish(message: "Location access is off. You can allow it in Settings; AR mapping still works.")
        case .restricted:
            finish(message: "Location access is restricted on this device. AR mapping still works.")
        @unknown default:
            finish(message: "Location is unavailable on this device. AR mapping still works.")
        }
    }

    private func finish(message: String) {
        manager?.stopUpdatingLocation()
        manager?.delegate = nil
        manager = nil
        requestedFix = false
        isRequesting = false
        self.message = message
    }
}
