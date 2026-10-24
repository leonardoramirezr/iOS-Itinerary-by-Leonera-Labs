import CoreLocation
import Foundation
import MapKit
import Observation

/// Address autocompletion backed by `MKLocalSearchCompleter`.
@Observable
final class LocationSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        if trimmed.isEmpty {
            completer.cancel()
            results = []
        } else {
            completer.queryFragment = trimmed
        }
    }

    /// Resolves a completion into a place with coordinates.
    func resolve(_ completion: MKLocalSearchCompletion) async throws -> Place {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        guard let item = response.mapItems.first else { throw AppError.placeNotFound }
        let coordinate = item.placemark.coordinate
        return Place(
            name: completion.title,
            address: completion.subtitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }
}

/// One-shot current location with reverse geocoding.
final class CurrentLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    @MainActor
    func currentPlace() async throws -> Place {
        let location = try await requestLocation()
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let street = [placemark?.thoroughfare, placemark?.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        let address = [street, placemark?.locality ?? "", placemark?.administrativeArea ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return Place(
            name: placemark?.name ?? String(localized: "Current location"),
            address: address,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    @MainActor
    private func requestLocation() async throws -> CLLocation {
        if let pending = continuation {
            continuation = nil
            pending.resume(throwing: CancellationError())
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                // The request continues in `locationManagerDidChangeAuthorization`.
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(with: .failure(AppError.locationDenied))
            default:
                manager.requestLocation()
            }
        }
    }

    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: .failure(AppError.locationDenied))
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        finish(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: .failure(error))
    }
}

/// Estimates the commute between home and office for the prompt.
enum CommuteEstimator {
    @MainActor
    static func describe(settings: AppSettings, day: Date) async -> String {
        guard let home = settings.home else { return "Home location is not set." }
        if settings.officeIsHome { return "I work from home, so there is no commute to an office." }
        guard let office = settings.office else { return "Office location is not set." }

        var text = String(format: "Straight-line distance between home and office: %.1f km.", home.distance(to: office) / 1000)
        let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
        if let minutes = await travelMinutes(from: home, to: office, mode: settings.travelMode, departure: max(morning, .now)) {
            text += " Apple Maps estimates about \(minutes) minutes from home to the office by \(settings.travelMode.promptName)."
        }
        return text
    }

    @MainActor
    private static func travelMinutes(from origin: Place, to destination: Place, mode: TravelMode, departure: Date) async -> Int? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.departureDate = departure
        switch mode {
        case .driving: request.transportType = .automobile
        case .transit: request.transportType = .transit
        case .walking: request.transportType = .walking
        case .cycling: return nil
        }
        guard let response = try? await MKDirections(request: request).calculateETA() else { return nil }
        return Int((response.expectedTravelTime / 60).rounded())
    }
}
