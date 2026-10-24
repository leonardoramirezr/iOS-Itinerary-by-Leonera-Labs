import CoreLocation
import Foundation

/// A geographic place chosen by the user, such as home or office.
struct Place: Codable, Hashable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// One-line description shown in the UI.
    var summary: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAddress.isEmpty || trimmedAddress == trimmedName { return trimmedName }
        if trimmedName.isEmpty { return trimmedAddress }
        return "\(trimmedName), \(trimmedAddress)"
    }

    /// Description used inside LLM prompts.
    var promptDescription: String {
        String(format: "%@ (lat %.5f, lon %.5f)", summary, latitude, longitude)
    }

    /// Straight-line distance in meters.
    func distance(to other: Place) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
