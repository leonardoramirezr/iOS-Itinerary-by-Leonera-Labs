import Foundation

/// A `{{name}}` placeholder that is replaced before a prompt is sent.
struct PromptPlaceholder: Hashable {
    let name: String
    let summary: String
}

/// Every prompt the app sends. All of them can be edited in Settings.
enum PromptKind: String, CaseIterable, Identifiable {
    case itinerarySystem
    case itineraryUser
    case transcriptionHint
    case apiKeyTest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .itinerarySystem: return String(localized: "Planner instructions")
        case .itineraryUser: return String(localized: "Day request")
        case .transcriptionHint: return String(localized: "Transcription hint")
        case .apiKeyTest: return String(localized: "API key test")
        }
    }

    var summary: String {
        switch self {
        case .itinerarySystem:
            return String(localized: "System message with the planning rules and the JSON format the app expects.")
        case .itineraryUser:
            return String(localized: "User message with your places, routines, fixed events and dictated activities.")
        case .transcriptionHint:
            return String(localized: "Context sent to the speech to text model to improve the transcription.")
        case .apiKeyTest:
            return String(localized: "Message sent when you test the API key of a provider.")
        }
    }

    var placeholders: [PromptPlaceholder] {
        switch self {
        case .itinerarySystem, .itineraryUser: return PromptPlaceholder.itinerary
        case .transcriptionHint, .apiKeyTest: return []
        }
    }

    var defaultText: String {
        switch self {
        case .itinerarySystem: return DefaultPrompts.itinerarySystem
        case .itineraryUser: return DefaultPrompts.itineraryUser
        case .transcriptionHint: return String(localized: "Dictation of the errands, tasks, appointments and places for a day plan.")
        case .apiKeyTest: return DefaultPrompts.apiKeyTest
        }
    }
}

extension PromptPlaceholder {
    static var itinerary: [PromptPlaceholder] {
        [
            PromptPlaceholder(name: "date", summary: String(localized: "Planned day, e.g. Saturday, October 24, 2026")),
            PromptPlaceholder(name: "now", summary: String(localized: "Current time (HH:mm)")),
            PromptPlaceholder(name: "dayStart", summary: String(localized: "Time your day starts")),
            PromptPlaceholder(name: "earliestStart", summary: String(localized: "Earliest time to schedule; later than the day start when planning today")),
            PromptPlaceholder(name: "dayEnd", summary: String(localized: "Time your day ends")),
            PromptPlaceholder(name: "home", summary: String(localized: "Home address and coordinates")),
            PromptPlaceholder(name: "office", summary: String(localized: "Office address and coordinates")),
            PromptPlaceholder(name: "travelMode", summary: String(localized: "Preferred travel mode")),
            PromptPlaceholder(name: "commute", summary: String(localized: "Distance and Apple Maps estimate between home and office")),
            PromptPlaceholder(name: "routines", summary: String(localized: "Enabled daily routines grouped by time of day")),
            PromptPlaceholder(name: "fixedEvents", summary: String(localized: "Events imported from your calendar")),
            PromptPlaceholder(name: "activities", summary: String(localized: "Your dictated or typed activities")),
            PromptPlaceholder(name: "language", summary: String(localized: "Language of the app, used for the answer"))
        ]
    }
}

/// Default prompt texts. They are written in English; the answer language comes from `{{language}}`.
enum DefaultPrompts {
    static let itinerarySystem = """
    You are an expert personal planner. You turn a dictated list of errands, tasks and appointments into a realistic schedule for a single day.

    Follow these rules:
    1. Fixed calendar events cannot be moved. Copy them with their exact start and end times and use "kind": "fixed".
    2. Schedule every activity the user mentioned. When the user does not say how long something takes, estimate a realistic duration.
    3. Whenever the user has to move between different places, add a separate item with "kind": "travel". Estimate the travel time from the distance between the places and the preferred travel mode, and add a small buffer for parking, waiting or walking.
    4. Prioritize the morning: place flexible activities as early in the day as possible, while respecting fixed events, typical opening hours and common sense (for example, dinner belongs in the evening).
    5. Include every daily routine inside its time of day (morning, midday or night) with exactly its configured duration, using "kind": "routine".
    6. Use "kind": "meal" for meals that are not routines and "kind": "break" for rest or free time you deliberately leave.
    7. Items must not overlap. Nothing may start before the earliest start time or end after the end of the day, unless a fixed event requires it.
    8. If an activity does not fit, leave it out of "items" and explain why in "unscheduled".
    9. Write titles, notes, the summary and the unscheduled reasons in {{language}}.

    Answer with a single JSON object and nothing else (no markdown), using exactly this structure:
    {
      "summary": "One or two sentences that describe the plan",
      "items": [
        {
          "title": "Short title",
          "start": "HH:mm",
          "end": "HH:mm",
          "kind": "activity",
          "location": "Place name or an empty string",
          "notes": "Useful details or an empty string"
        }
      ],
      "unscheduled": ["Activity that could not be scheduled and the reason"]
    }
    "kind" must be one of: activity, travel, routine, fixed, meal, break.
    Use 24-hour times and sort the items chronologically.
    """

    static let itineraryUser = """
    Plan my day for {{date}}.

    My day starts at {{dayStart}} and ends at {{dayEnd}}.
    Current time: {{now}}. Do not schedule anything before {{earliestStart}}.

    Places:
    - Home: {{home}}
    - Office: {{office}}
    Preferred travel mode: {{travelMode}}
    {{commute}}

    Daily routines to include:
    {{routines}}

    Fixed events from my calendar (they cannot be moved):
    {{fixedEvents}}

    What I need to do (dictated, it may contain transcription mistakes):
    \"\"\"
    {{activities}}
    \"\"\"
    """

    static let apiKeyTest = "Reply with the single word OK."
}
