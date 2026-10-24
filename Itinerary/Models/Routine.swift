import Foundation

/// Time of the day in which a daily routine happens.
enum RoutineSlot: String, Codable, CaseIterable, Identifiable {
    case morning
    case midday
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return String(localized: "Morning")
        case .midday: return String(localized: "Midday")
        case .night: return String(localized: "Night")
        }
    }

    var symbol: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .midday: return "sun.max.fill"
        case .night: return "moon.stars.fill"
        }
    }

    /// English description used inside LLM prompts.
    var promptName: String {
        switch self {
        case .morning: return "Morning (right after waking up)"
        case .midday: return "Midday (around lunch time)"
        case .night: return "Night (before going to bed)"
        }
    }
}

/// A recurring daily activity, such as taking a shower or exercising.
struct RoutineActivity: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var slot: RoutineSlot
    var durationMinutes: Int
    var isEnabled = true

    /// Routines created on first launch, in the language of the device.
    static func defaults() -> [RoutineActivity] {
        [
            RoutineActivity(name: String(localized: "Shower"), slot: .morning, durationMinutes: 15),
            RoutineActivity(name: String(localized: "Get ready"), slot: .morning, durationMinutes: 20),
            RoutineActivity(name: String(localized: "Breakfast"), slot: .morning, durationMinutes: 20),
            RoutineActivity(name: String(localized: "Exercise"), slot: .morning, durationMinutes: 45),
            RoutineActivity(name: String(localized: "Lunch"), slot: .midday, durationMinutes: 60),
            RoutineActivity(name: String(localized: "Dinner"), slot: .night, durationMinutes: 45),
            RoutineActivity(name: String(localized: "Prepare for tomorrow"), slot: .night, durationMinutes: 15)
        ]
    }
}
