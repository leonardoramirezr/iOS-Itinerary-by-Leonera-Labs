import Foundation

/// An immovable event imported from a calendar.
struct FixedEvent: Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
}

/// A calendar the user can import events from.
struct CalendarInfo: Identifiable, Hashable {
    var id: String
    var name: String
    /// Account or source that owns the calendar, e.g. "Gmail" or "iCloud".
    var sourceName: String?
    var colorHex: String?
    var isPrimary = false
}
