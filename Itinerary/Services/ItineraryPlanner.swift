import Foundation

/// Everything needed to plan one day.
struct PlanningRequest {
    var day: Date
    var now: Date
    var activities: String
    var settings: AppSettings
    var fixedEvents: [FixedEvent]
    /// Description of the commute between home and office.
    var commute: String
}

/// Builds the prompts, calls the LLM and turns its answer into an `Itinerary`.
enum ItineraryPlanner {
    static func plan(
        _ request: PlanningRequest,
        client: OpenAICompatibleClient,
        model: String,
        jsonMode: Bool,
        systemTemplate: String,
        userTemplate: String,
        providerName: String
    ) async throws -> Itinerary {
        let values = placeholderValues(for: request)
        let messages: [ChatMessage] = [
            .system(PromptRenderer.render(systemTemplate, values: values)),
            .user(PromptRenderer.render(userTemplate, values: values))
        ]
        let answer = try await client.complete(model: model, messages: messages, jsonMode: jsonMode)
        let parsed = try ItineraryParser.parse(answer, day: request.day)
        let items = mergingFixedEvents(into: parsed.items, fixedEvents: request.fixedEvents)
        return Itinerary(
            day: Calendar.current.startOfDay(for: request.day),
            items: items,
            summary: parsed.summary,
            unscheduled: parsed.unscheduled,
            transcript: request.activities,
            createdAt: request.now,
            providerName: providerName,
            model: model
        )
    }

    /// Values for the `{{placeholders}}` of the itinerary prompts.
    static func placeholderValues(for request: PlanningRequest, calendar: Calendar = .current) -> [String: String] {
        let settings = request.settings
        let isToday = calendar.isDate(request.day, inSameDayAs: request.now)
        var earliest = settings.dayStartMinutes
        if isToday {
            // Round the current time up to the next five minutes.
            let nowMinutes = TimeText.minutesOfDay(request.now, calendar: calendar)
            earliest = max(earliest, (nowMinutes + 4) / 5 * 5)
        }

        let office: String
        if settings.officeIsHome {
            office = "Same as home (I work from home)"
        } else {
            office = settings.office?.promptDescription ?? "Not set"
        }

        return [
            "date": TimeText.promptDate(request.day),
            "now": TimeText.clock(request.now),
            "dayStart": TimeText.clock(minutes: settings.dayStartMinutes),
            "earliestStart": TimeText.clock(minutes: earliest),
            "dayEnd": TimeText.clock(minutes: settings.dayEndMinutes),
            "home": settings.home?.promptDescription ?? "Not set",
            "office": office,
            "travelMode": settings.travelMode.promptName,
            "commute": request.commute,
            "routines": routinesDescription(settings.enabledRoutines),
            "fixedEvents": fixedEventsDescription(request.fixedEvents),
            "activities": request.activities,
            "language": AppLanguage.englishName
        ]
    }

    static func routinesDescription(_ routines: [RoutineActivity]) -> String {
        let lines = RoutineSlot.allCases.compactMap { slot -> String? in
            let entries = routines.filter { $0.slot == slot }
            guard !entries.isEmpty else { return nil }
            let list = entries.map { "\($0.name) (\($0.durationMinutes) min)" }.joined(separator: ", ")
            return "- \(slot.promptName): \(list)"
        }
        return lines.isEmpty ? "None" : lines.joined(separator: "\n")
    }

    static func fixedEventsDescription(_ events: [FixedEvent]) -> String {
        guard !events.isEmpty else { return "None" }
        return events
            .sorted { $0.start < $1.start }
            .map { event in
                var line = event.isAllDay
                    ? "- All day: \(event.title)"
                    : "- \(TimeText.clock(event.start))–\(TimeText.clock(event.end)): \(event.title)"
                if let location = event.location, !location.isEmpty {
                    line += " (at \(location))"
                }
                return line
            }
            .joined(separator: "\n")
    }

    /// Adds timed calendar events the model forgot, so fixed events are never lost.
    static func mergingFixedEvents(into items: [ItineraryItem], fixedEvents: [FixedEvent]) -> [ItineraryItem] {
        var result = items
        for event in fixedEvents where !event.isAllDay {
            let isPlanned = result.contains { item in
                abs(item.start.timeIntervalSince(event.start)) < 60
                    && (item.kind == .fixed
                        || item.title.localizedCaseInsensitiveContains(event.title)
                        || event.title.localizedCaseInsensitiveContains(item.title))
            }
            if !isPlanned {
                result.append(ItineraryItem(
                    title: event.title,
                    start: event.start,
                    end: event.end,
                    kind: .fixed,
                    location: event.location,
                    notes: nil
                ))
            }
        }
        return result.sorted { $0.start < $1.start }
    }
}

/// Tolerant parser for the JSON itinerary returned by the model.
enum ItineraryParser {
    struct Result {
        var summary: String
        var items: [ItineraryItem]
        var unscheduled: [String]
    }

    private static let timeExpression = try! NSRegularExpression(pattern: "(\\d{1,2}):(\\d{2})")

    static func parse(_ answer: String, day: Date, calendar: Calendar = .current) throws -> Result {
        guard let data = JSONExtractor.jsonData(from: answer),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            throw AppError.unreadableItinerary(preview(of: answer))
        }

        let object = json as? [String: Any] ?? [:]
        let rawItems: [[String: Any]]
        if let array = json as? [[String: Any]] {
            rawItems = array
        } else {
            rawItems = firstArray(in: object, keys: ["items", "events", "itinerary", "schedule", "plan"])
        }

        let dayStart = calendar.startOfDay(for: day)
        var items: [ItineraryItem] = []
        for raw in rawItems {
            guard let startText = string(in: raw, keys: ["start", "start_time", "startTime", "from", "time"]),
                  let startMinutes = minutes(from: startText) else { continue }

            var endMinutes: Int
            if let endText = string(in: raw, keys: ["end", "end_time", "endTime", "to"]),
               let parsedEnd = minutes(from: endText) {
                endMinutes = parsedEnd
            } else if let duration = integer(in: raw, keys: ["duration", "duration_minutes", "durationMinutes", "minutes"]) {
                endMinutes = startMinutes + duration
            } else {
                endMinutes = startMinutes + 30
            }
            if endMinutes < startMinutes { endMinutes += 1440 }
            if endMinutes == startMinutes { endMinutes += 15 }

            items.append(ItineraryItem(
                title: string(in: raw, keys: ["title", "name", "activity", "summary"]) ?? String(localized: "Activity"),
                start: TimeText.date(minutes: startMinutes, onDayStarting: dayStart, calendar: calendar),
                end: TimeText.date(minutes: endMinutes, onDayStarting: dayStart, calendar: calendar),
                kind: ItineraryItemKind(llmValue: string(in: raw, keys: ["kind", "type", "category"])),
                location: string(in: raw, keys: ["location", "place", "address"]),
                notes: string(in: raw, keys: ["notes", "note", "description", "details"])
            ))
        }

        guard !items.isEmpty else { throw AppError.unreadableItinerary(preview(of: answer)) }
        items.sort { $0.start < $1.start }

        let unscheduledValue: Any? = object["unscheduled"] ?? object["unscheduled_activities"] ?? object["not_scheduled"]
        return Result(
            summary: string(in: object, keys: ["summary", "overview"]) ?? "",
            items: items,
            unscheduled: stringList(unscheduledValue)
        )
    }

    /// Minutes after midnight of the first `H:mm` time in the text. Understands am/pm suffixes.
    static func minutes(from text: String) -> Int? {
        let lowercased = text.lowercased()
        let range = NSRange(lowercased.startIndex..., in: lowercased)
        guard let match = timeExpression.firstMatch(in: lowercased, range: range),
              let hourRange = Range(match.range(at: 1), in: lowercased),
              let minuteRange = Range(match.range(at: 2), in: lowercased),
              var hour = Int(lowercased[hourRange]),
              let minute = Int(lowercased[minuteRange]) else { return nil }
        let compact = lowercased.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
        if compact.contains("pm"), hour < 12 { hour += 12 }
        if compact.contains("am"), hour == 12 { hour = 0 }
        guard hour <= 24, minute < 60 else { return nil }
        return hour * 60 + minute
    }

    private static func preview(of answer: String) -> String {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
    }

    private static func firstArray(in object: [String: Any], keys: [String]) -> [[String: Any]] {
        for key in keys {
            if let array = object[key] as? [[String: Any]] { return array }
        }
        return []
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let text = object[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let number = object[key] as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func integer(in object: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let number = object[key] as? NSNumber { return number.intValue }
            if let text = object[key] as? String, let value = Int(text.filter(\.isNumber)) { return value }
        }
        return nil
    }

    /// Accepts a string, an array of strings, an array of `{title, reason}` objects, or a mix of them.
    private static func stringList(_ value: Any?) -> [String] {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        guard let elements = value as? [Any] else { return [] }
        return elements.compactMap { element -> String? in
            if let text = element as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            guard let object = element as? [String: Any] else { return nil }
            let title = string(in: object, keys: ["title", "name", "activity"])
            let reason = string(in: object, keys: ["reason", "why", "notes"])
            switch (title, reason) {
            case let (title?, reason?): return "\(title): \(reason)"
            case let (title?, nil): return title
            case let (nil, reason?): return reason
            default: return nil
            }
        }
    }
}
