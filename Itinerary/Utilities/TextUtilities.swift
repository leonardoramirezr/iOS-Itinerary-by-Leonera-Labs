import Foundation

/// Replaces `{{name}}` placeholders in prompt templates.
enum PromptRenderer {
    static func render(_ template: String, values: [String: String]) -> String {
        var result = template
        for (name, value) in values {
            result = result.replacingOccurrences(of: "{{\(name)}}", with: value)
        }
        return result
    }
}

/// Finds the JSON payload inside an LLM answer that may include markdown fences or reasoning text.
enum JSONExtractor {
    static func jsonData(from text: String) -> Data? {
        var cleaned = text
        while let open = cleaned.range(of: "<think>"),
              let close = cleaned.range(of: "</think>", range: open.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(open.lowerBound..<close.upperBound)
        }
        guard let first = cleaned.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let closing: Character = cleaned[first] == "{" ? "}" : "]"
        guard let last = cleaned.lastIndex(of: closing), last > first else { return nil }
        return Data(cleaned[first...last].utf8)
    }
}

/// Language the app is running in, which is the language used in the generated itinerary.
enum AppLanguage {
    /// ISO code of the active localization, e.g. `en` or `es`.
    static var code: String {
        let identifier = Bundle.main.preferredLocalizations.first ?? "en"
        return String(identifier.prefix(2))
    }

    /// English name of the active language, used inside prompts.
    static var englishName: String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }
}

/// Formatting helpers shared by prompts and views.
enum TimeText {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// 24-hour time, e.g. `07:30`.
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// 24-hour time from minutes after midnight, e.g. `07:30`.
    static func clock(minutes: Int) -> String {
        let normalized = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    /// English long date used in prompts, e.g. `Saturday, October 24, 2026`.
    static func promptDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }

    /// Localized short time, e.g. `7:30 AM` or `7:30`.
    static func short(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Localized range, e.g. `7:30 AM – 8:00 AM`.
    static func range(_ start: Date, _ end: Date) -> String {
        "\(short(start)) – \(short(end))"
    }

    /// Localized duration, e.g. `1 hr, 30 min`.
    static func duration(minutes: Int) -> String {
        Duration.seconds(Double(max(0, minutes) * 60))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// Minutes after midnight of a date.
    static func minutesOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// Date at a wall clock time; minutes past midnight roll over to the next days.
    static func date(minutes: Int, onDayStarting dayStart: Date, calendar: Calendar = .current) -> Date {
        let dayOffset = minutes / 1440
        let remainder = minutes % 1440
        let base = calendar.date(byAdding: .day, value: dayOffset, to: dayStart) ?? dayStart
        return calendar.date(bySettingHour: remainder / 60, minute: remainder % 60, second: 0, of: base) ?? base
    }
}
