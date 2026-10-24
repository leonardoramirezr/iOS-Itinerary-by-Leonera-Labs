import Foundation

/// Where fixed events are imported from.
enum CalendarSource: String, Codable, CaseIterable, Identifiable {
    case disabled
    case google
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled: return String(localized: "None")
        case .google: return String(localized: "Google Calendar")
        case .system: return String(localized: "iPhone calendars")
        }
    }
}

/// How events are drawn in the day view.
enum TimelineMode: String, Codable, CaseIterable, Identifiable {
    /// Every event has the same height regardless of its duration.
    case uniform
    /// The height of every event is proportional to its duration.
    case proportional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uniform: return String(localized: "Same height")
        case .proportional: return String(localized: "Proportional")
        }
    }
}

/// Everything the user configures. Persisted as JSON in `UserDefaults`; API keys live in the Keychain.
struct AppSettings: Codable, Equatable {
    var hasCompletedOnboarding = false
    var home: Place?
    var office: Place?
    var officeIsHome = false
    var travelMode: TravelMode = .driving
    var dayStartMinutes = 7 * 60
    var dayEndMinutes = 22 * 60
    var routines: [RoutineActivity] = RoutineActivity.defaults()
    var selectedProvider: LLMProvider = .gemini
    /// Provider settings keyed by `LLMProvider.rawValue`.
    var providers: [String: ProviderConfig] = [:]
    var transcription = TranscriptionConfig()
    /// Prompt overrides keyed by `PromptKind.rawValue`. Missing keys use the default prompt.
    var prompts: [String: String] = [:]
    var calendarSource: CalendarSource = .disabled
    var googleClientID = ""
    /// Selected Google calendars. Empty means the primary calendar.
    var googleCalendarIDs: [String] = []
    /// iPhone calendars the user turned off. Empty means every calendar.
    var excludedSystemCalendarIDs: [String] = []
    var timelineMode: TimelineMode = .proportional

    init() {}

    enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding
        case home
        case office
        case officeIsHome
        case travelMode
        case dayStartMinutes
        case dayEndMinutes
        case routines
        case selectedProvider
        case providers
        case transcription
        case prompts
        case calendarSource
        case googleClientID
        case googleCalendarIDs
        case excludedSystemCalendarIDs
        case timelineMode
    }

    /// Decodes every field independently so that new or renamed fields never wipe the whole configuration.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ defaultValue: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? defaultValue
        }
        hasCompletedOnboarding = value(.hasCompletedOnboarding, fallback.hasCompletedOnboarding)
        home = value(.home, fallback.home)
        office = value(.office, fallback.office)
        officeIsHome = value(.officeIsHome, fallback.officeIsHome)
        travelMode = value(.travelMode, fallback.travelMode)
        dayStartMinutes = value(.dayStartMinutes, fallback.dayStartMinutes)
        dayEndMinutes = value(.dayEndMinutes, fallback.dayEndMinutes)
        routines = value(.routines, fallback.routines)
        selectedProvider = value(.selectedProvider, fallback.selectedProvider)
        providers = value(.providers, fallback.providers)
        transcription = value(.transcription, fallback.transcription)
        prompts = value(.prompts, fallback.prompts)
        calendarSource = value(.calendarSource, fallback.calendarSource)
        googleClientID = value(.googleClientID, fallback.googleClientID)
        googleCalendarIDs = value(.googleCalendarIDs, fallback.googleCalendarIDs)
        excludedSystemCalendarIDs = value(.excludedSystemCalendarIDs, fallback.excludedSystemCalendarIDs)
        timelineMode = value(.timelineMode, fallback.timelineMode)
    }

    subscript(config provider: LLMProvider) -> ProviderConfig {
        get { providers[provider.rawValue] ?? ProviderConfig(provider: provider) }
        set { providers[provider.rawValue] = newValue }
    }

    /// Office used for planning; it is the home when the user works from home.
    var effectiveOffice: Place? { officeIsHome ? home : office }

    var enabledRoutines: [RoutineActivity] { routines.filter(\.isEnabled) }

    func isGoogleCalendarSelected(_ id: String) -> Bool { googleCalendarIDs.contains(id) }

    mutating func toggleGoogleCalendar(_ id: String) {
        if googleCalendarIDs.contains(id) {
            googleCalendarIDs.removeAll { $0 == id }
        } else {
            googleCalendarIDs.append(id)
        }
    }

    func isSystemCalendarSelected(_ id: String) -> Bool { !excludedSystemCalendarIDs.contains(id) }

    mutating func toggleSystemCalendar(_ id: String) {
        if excludedSystemCalendarIDs.contains(id) {
            excludedSystemCalendarIDs.removeAll { $0 == id }
        } else {
            excludedSystemCalendarIDs.append(id)
        }
    }
}
