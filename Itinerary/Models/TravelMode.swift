import Foundation

/// Preferred way to move between places.
enum TravelMode: String, Codable, CaseIterable, Identifiable {
    case driving
    case transit
    case walking
    case cycling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .driving: return String(localized: "Car")
        case .transit: return String(localized: "Public transport")
        case .walking: return String(localized: "Walking")
        case .cycling: return String(localized: "Bicycle")
        }
    }

    var symbol: String {
        switch self {
        case .driving: return "car.fill"
        case .transit: return "bus.fill"
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        }
    }

    /// English name used inside LLM prompts.
    var promptName: String {
        switch self {
        case .driving: return "car"
        case .transit: return "public transport"
        case .walking: return "walking"
        case .cycling: return "bicycle"
        }
    }
}
