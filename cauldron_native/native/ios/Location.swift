import CoreLocation
import Foundation

final class Locator: NSObject, CLLocationManagerDelegate {
    static let shared = Locator()

    private let manager = CLLocationManager()
    private var asking: [String] = []
    private var waiting: [String] = []
    private var watching: String?

    override init() {
        super.init()
        manager.delegate = self
    }

    func permission(_ id: String) {
        guard declared else { return answerRequest(id, "error", "not_declared") }
        guard manager.authorizationStatus == .notDetermined else {
            return answerRequest(id, "ok", allowed ? "granted" : "denied")
        }
        asking.append(id)
        manager.requestWhenInUseAuthorization()
    }

    func current(_ id: String, precise: Bool) {
        guard declared else { return answerRequest(id, "error", "not_declared") }
        waiting.append(id)
        manager.desiredAccuracy = precise ? kCLLocationAccuracyBest : kCLLocationAccuracyKilometer
        proceed()
    }

    func watch(_ id: String, precise: Bool, distance: Double) {
        guard declared else { return answerRequest(id, "error", "not_declared") }
        watching = id
        manager.desiredAccuracy = precise ? kCLLocationAccuracyBest : kCLLocationAccuracyKilometer
        manager.distanceFilter = distance
        proceed()
    }

    func stop() {
        watching = nil
        manager.stopUpdatingLocation()
    }

    private var declared: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil
    }

    private var allowed: Bool {
        #if os(macOS)
        manager.authorizationStatus == .authorizedAlways
        #else
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        #endif
    }

    private func proceed() {
        if manager.authorizationStatus == .notDetermined { return manager.requestWhenInUseAuthorization() }
        guard allowed else { return refuse() }
        #if os(tvOS)
        if watching != nil { manager.requestLocation() }
        #else
        if watching != nil { manager.startUpdatingLocation() }
        #endif
        if !waiting.isEmpty { manager.requestLocation() }
    }

    private func refuse() {
        for id in waiting { answerRequest(id, "error", "denied") }
        waiting = []
        if let watching { answerRequest(watching, "error", "denied") }
        watching = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        for id in asking { answerRequest(id, "ok", allowed ? "granted" : "denied") }
        asking = []
        NotificationCenter.default.post(name: .cauldronPermissionsChanged, object: nil)
        if !waiting.isEmpty || watching != nil { proceed() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let reading = Locator.reading(last)
        for id in waiting { answerRequest(id, "ok", reading) }
        waiting = []
        if let watching { answerRequest(watching, "ok", reading) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { return refuse() }
        for id in waiting { answerRequest(id, "error", "unavailable") }
        waiting = []
    }

    private static func reading(_ location: CLLocation) -> [String: Any] {
        var reading: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "time": (location.timestamp.timeIntervalSince1970 * 1000).rounded()
        ]
        if location.verticalAccuracy >= 0 { reading["altitude"] = location.altitude }
        if location.speed >= 0 { reading["speed"] = location.speed }
        if location.course >= 0 { reading["heading"] = location.course }
        return reading
    }
}
