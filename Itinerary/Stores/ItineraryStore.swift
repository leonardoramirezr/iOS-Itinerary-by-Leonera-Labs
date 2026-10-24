import Foundation
import Observation

/// Stores generated itineraries and unsent dictation drafts, one per day.
@MainActor
@Observable
final class ItineraryStore {
    private struct Snapshot: Codable {
        var itineraries: [String: Itinerary]
        var drafts: [String: String]
    }

    /// Days older than this are removed to keep the file small.
    private static let retentionDays = 90

    private(set) var itineraries: [String: Itinerary] = [:]
    private(set) var drafts: [String: String] = [:]

    init() {
        load()
    }

    func itinerary(for day: Date) -> Itinerary? {
        itineraries[DayKey.make(for: day)]
    }

    func draft(for day: Date) -> String {
        drafts[DayKey.make(for: day)] ?? ""
    }

    func setDraft(_ text: String, for day: Date) {
        let key = DayKey.make(for: day)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard drafts[key] != (trimmed.isEmpty ? nil : text) else { return }
        drafts[key] = trimmed.isEmpty ? nil : text
        persist()
    }

    func save(_ itinerary: Itinerary) {
        itineraries[itinerary.dayKey] = itinerary
        persist()
    }

    func removeItem(id: UUID, fromDayKey dayKey: String) {
        guard var itinerary = itineraries[dayKey] else { return }
        itinerary.items.removeAll { $0.id == id }
        itineraries[dayKey] = itinerary
        persist()
    }

    func deleteItinerary(for day: Date) {
        itineraries[DayKey.make(for: day)] = nil
        persist()
    }

    private var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "itineraries.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        itineraries = snapshot.itineraries
        drafts = snapshot.drafts
    }

    private func persist() {
        prune()
        do {
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Snapshot(itineraries: itineraries, drafts: drafts))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Could not save itineraries: \(error)")
        }
    }

    private func prune() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: .now) else { return }
        let cutoffKey = DayKey.make(for: cutoff)
        // Day keys are zero padded, so string comparison follows chronological order.
        itineraries = itineraries.filter { $0.key >= cutoffKey }
        drafts = drafts.filter { $0.key >= cutoffKey }
    }
}
