import EventKit
import Foundation

/// Read-only client of the Google Calendar REST API v3.
struct GoogleCalendarAPI {
    var accessToken: String
    var session: URLSession = .shared

    private static let baseURL = "https://www.googleapis.com/calendar/v3"

    func calendars() async throws -> [CalendarInfo] {
        let response: CalendarListResponse = try await get("/users/me/calendarList", query: [
            URLQueryItem(name: "minAccessRole", value: "reader"),
            URLQueryItem(name: "maxResults", value: "250")
        ])
        return (response.items ?? []).map { item in
            CalendarInfo(
                id: item.id,
                name: item.summaryOverride ?? item.summary ?? item.id,
                sourceName: nil,
                colorHex: item.backgroundColor,
                isPrimary: item.primary ?? false
            )
        }
    }

    func events(calendarID: String, from start: Date, to end: Date) async throws -> [FixedEvent] {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~@")
        let encodedID = calendarID.addingPercentEncoding(withAllowedCharacters: allowed) ?? calendarID
        let formatter = ISO8601DateFormatter()

        var events: [FixedEvent] = []
        var pageToken: String?
        repeat {
            var query = [
                URLQueryItem(name: "timeMin", value: formatter.string(from: start)),
                URLQueryItem(name: "timeMax", value: formatter.string(from: end)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "250")
            ]
            if let pageToken {
                query.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            let response: EventsResponse = try await get("/calendars/\(encodedID)/events", query: query)
            events += (response.items ?? []).compactMap { $0.fixedEvent(calendarID: calendarID) }
            pageToken = response.nextPageToken
        } while pageToken != nil && events.count < 1000
        return events
    }

    private func get<Response: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> Response {
        var components = URLComponents(string: Self.baseURL + path)
        components?.queryItems = query
        guard let url = components?.url else { throw AppError.invalidURL(Self.baseURL + path) }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try HTTP.validate(response, data: data)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AppError.invalidResponse
        }
    }
}

private struct CalendarListResponse: Decodable {
    struct Item: Decodable {
        let id: String
        let summary: String?
        let summaryOverride: String?
        let backgroundColor: String?
        let primary: Bool?
    }

    let items: [Item]?
}

private struct EventsResponse: Decodable {
    struct Time: Decodable {
        let dateTime: String?
        let date: String?
    }

    struct Attendee: Decodable {
        let isSelf: Bool?
        let responseStatus: String?

        enum CodingKeys: String, CodingKey {
            case isSelf = "self"
            case responseStatus
        }
    }

    struct Item: Decodable {
        let id: String
        let status: String?
        let summary: String?
        let location: String?
        let start: Time?
        let end: Time?
        let attendees: [Attendee]?
        let eventType: String?

        func fixedEvent(calendarID: String) -> FixedEvent? {
            guard status != "cancelled", eventType != "workingLocation" else { return nil }
            if attendees?.contains(where: { $0.isSelf == true && $0.responseStatus == "declined" }) == true {
                return nil
            }
            guard let start, let end else { return nil }
            let title = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let displayTitle = title.isEmpty ? String(localized: "Busy") : title

            if let startText = start.dateTime, let endText = end.dateTime,
               let startDate = Self.parseDateTime(startText), let endDate = Self.parseDateTime(endText) {
                return FixedEvent(id: "\(calendarID)/\(id)", title: displayTitle, start: startDate, end: endDate, isAllDay: false, location: location)
            }
            if let startText = start.date, let endText = end.date,
               let startDate = Self.parseDay(startText), let endDate = Self.parseDay(endText) {
                return FixedEvent(id: "\(calendarID)/\(id)", title: displayTitle, start: startDate, end: endDate, isAllDay: true, location: location)
            }
            return nil
        }

        private static func parseDateTime(_ text: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text)
        }

        private static func parseDay(_ text: String) -> Date? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: text)
        }
    }

    let items: [Item]?
    let nextPageToken: String?
}

/// Calendars configured on the iPhone (iCloud, Google accounts added in Settings, Exchange…) through EventKit.
@MainActor
final class SystemCalendarService {
    static let shared = SystemCalendarService()

    private let store = EKEventStore()

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var isAccessUndetermined: Bool {
        EKEventStore.authorizationStatus(for: .event) == .notDetermined
    }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    name: calendar.title,
                    sourceName: calendar.source?.title,
                    colorHex: nil,
                    isPrimary: calendar.calendarIdentifier == store.defaultCalendarForNewEvents?.calendarIdentifier
                )
            }
            .sorted { ($0.sourceName ?? "", $0.name) < ($1.sourceName ?? "", $1.name) }
    }

    func events(from start: Date, to end: Date, excluding excludedIDs: [String]) throws -> [FixedEvent] {
        guard hasAccess else { throw AppError.calendarAccessDenied }
        let calendars = store.calendars(for: .event).filter { !excludedIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { event in
                FixedEvent(
                    id: event.calendarItemIdentifier + "/" + String(event.startDate.timeIntervalSince1970),
                    title: event.title ?? String(localized: "Busy"),
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location
                )
            }
    }
}

/// Loads the fixed events of a day from the configured calendar source.
@MainActor
enum FixedEventsLoader {
    static func load(for day: Date, settings: AppSettings, googleAuth: GoogleAuthService) async throws -> [FixedEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let events: [FixedEvent]
        switch settings.calendarSource {
        case .disabled:
            return []
        case .google:
            let token = try await googleAuth.validAccessToken(clientID: settings.googleClientID)
            let api = GoogleCalendarAPI(accessToken: token)
            let calendarIDs = settings.googleCalendarIDs.isEmpty ? ["primary"] : settings.googleCalendarIDs
            var collected: [FixedEvent] = []
            for calendarID in calendarIDs {
                collected += try await api.events(calendarID: calendarID, from: start, to: end)
            }
            events = collected
        case .system:
            events = try SystemCalendarService.shared.events(from: start, to: end, excluding: settings.excludedSystemCalendarIDs)
        }

        // The same meeting can appear in several calendars.
        var seen = Set<String>()
        return events
            .sorted { $0.start < $1.start }
            .filter { event in
                let key = "\(event.title.lowercased())|\(event.start.timeIntervalSince1970)|\(event.end.timeIntervalSince1970)"
                return seen.insert(key).inserted
            }
    }
}
