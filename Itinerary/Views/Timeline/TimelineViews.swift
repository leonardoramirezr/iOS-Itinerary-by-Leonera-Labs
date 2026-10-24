import SwiftUI
import UIKit

extension ItineraryItemKind {
    var color: Color {
        switch self {
        case .activity: return .indigo
        case .travel: return .gray
        case .routine: return .teal
        case .fixed: return .blue
        case .meal: return .orange
        case .rest: return .mint
        }
    }
}

/// How much information an event block can show.
enum EventCardDensity {
    case compact
    case regular
    case expanded
}

/// Colored block that represents an itinerary item.
struct EventCard: View {
    let item: ItineraryItem
    var density: EventCardDensity = .expanded

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.kind.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: item.kind.symbol)
                        .font(.caption)
                        .foregroundStyle(item.kind.color)
                    Text(item.title)
                        .font(density == .compact ? Font.caption.weight(.semibold) : Font.subheadline.weight(.semibold))
                        .lineLimit(density == .expanded ? 2 : 1)
                    if density == .compact {
                        Text(TimeText.short(item.start))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if density != .compact {
                    Text(verbatim: "\(TimeText.range(item.start, item.end)) · \(TimeText.duration(minutes: item.durationMinutes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if density == .expanded, let location = item.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, density == .compact ? 2 : 6)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(item.kind.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

/// Summary and unscheduled activities shown above the timeline.
struct ItinerarySummaryCard: View {
    let itinerary: Itinerary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !itinerary.summary.isEmpty {
                Text(itinerary.summary)
                    .font(.subheadline)
            }
            if !itinerary.unscheduled.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Could not be scheduled", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    ForEach(itinerary.unscheduled, id: \.self) { reason in
                        Text(verbatim: "• " + reason)
                            .font(.caption)
                    }
                }
            }
            Text("Generated with \(itinerary.providerName) · \(itinerary.model)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Every event has the same height, like an agenda.
struct UniformTimelineView: View {
    let itinerary: Itinerary
    let onSelect: (ItineraryItem) -> Void

    private let rowHeight: CGFloat = 76

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ItinerarySummaryCard(itinerary: itinerary)
                    .padding(.bottom, 4)
                ForEach(TimelineEntry.entries(for: itinerary.items)) { entry in
                    switch entry.content {
                    case .item(let item):
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(TimeText.short(item.start))
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                Text(TimeText.short(item.end))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: 64, alignment: .trailing)
                            .padding(.top, 6)

                            EventCard(item: item, density: .expanded)
                                .frame(height: rowHeight)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(item) }
                    case .gap(let minutes):
                        Label(String(localized: "Free time: \(TimeText.duration(minutes: minutes))"), systemImage: "hourglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 74)
                    }
                }
            }
            .padding()
        }
    }
}

/// Element of the uniform timeline: an item or the free time between two items.
struct TimelineEntry: Identifiable {
    enum Content {
        case item(ItineraryItem)
        case gap(minutes: Int)
    }

    let id: String
    let content: Content

    static func entries(for items: [ItineraryItem]) -> [TimelineEntry] {
        var result: [TimelineEntry] = []
        var previousEnd: Date?
        for item in items.sorted(by: { $0.start < $1.start }) {
            if let previousEnd {
                let gap = Int(item.start.timeIntervalSince(previousEnd) / 60)
                if gap >= 15 {
                    result.append(TimelineEntry(id: "gap-\(item.id.uuidString)", content: .gap(minutes: gap)))
                }
            }
            result.append(TimelineEntry(id: item.id.uuidString, content: .item(item)))
            previousEnd = max(previousEnd ?? item.end, item.end)
        }
        return result
    }
}

/// Google Calendar style day view: the height of every event is proportional to its duration.
struct ProportionalTimelineView: View {
    let itinerary: Itinerary
    let onSelect: (ItineraryItem) -> Void

    private let hourHeight: CGFloat = 80
    private let labelWidth: CGFloat = 52
    private let calendar = Calendar.current

    var body: some View {
        let hours = hourRange
        let slots = OverlapLayout.slots(for: itinerary.items)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ItinerarySummaryCard(itinerary: itinerary)
                    ZStack(alignment: .topLeading) {
                        hourGrid(hours)
                        GeometryReader { geometry in
                            let columnArea = max(geometry.size.width - labelWidth - 8, 0)
                            ZStack(alignment: .topLeading) {
                                ForEach(itinerary.items) { item in
                                    let slot = slots[item.id] ?? OverlapLayout.Slot(column: 0, columns: 1)
                                    let width = columnArea / CGFloat(slot.columns)
                                    let top = offset(for: item.start, hours: hours)
                                    let height = max(offset(for: item.end, hours: hours) - top, 22)
                                    EventCard(item: item, density: density(forHeight: height))
                                        .frame(width: max(width - 2, 0), height: height - 2)
                                        .offset(x: labelWidth + 8 + CGFloat(slot.column) * width, y: top + 1)
                                        .onTapGesture { onSelect(item) }
                                }
                                if let nowY = currentTimeOffset(hours: hours) {
                                    NowIndicator()
                                        .frame(width: columnArea + 8)
                                        .offset(x: labelWidth + 4, y: nowY - 4)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                    .frame(height: CGFloat(hours.count) * hourHeight)
                }
                .padding()
            }
            .onAppear {
                proxy.scrollTo(initialHour(hours), anchor: .top)
            }
        }
    }

    private func hourGrid(_ hours: Range<Int>) -> some View {
        VStack(spacing: 0) {
            ForEach(hours, id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(hourLabel(hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .trailing)
                        .offset(y: -7)
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 0.5)
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private var dayStart: Date { calendar.startOfDay(for: itinerary.day) }

    private func minutesFromDayStart(_ date: Date) -> Double {
        date.timeIntervalSince(dayStart) / 60
    }

    private var hourRange: Range<Int> {
        let starts = itinerary.items.map { Int((minutesFromDayStart($0.start) / 60).rounded(.down)) }
        let ends = itinerary.items.map { Int((minutesFromDayStart($0.end) / 60).rounded(.up)) }
        let lower = min(max(starts.min() ?? 7, 0), 23)
        let upper = min(max(ends.max() ?? 22, lower + 1), 48)
        return lower..<upper
    }

    private func offset(for date: Date, hours: Range<Int>) -> CGFloat {
        CGFloat((minutesFromDayStart(date) - Double(hours.lowerBound * 60)) / 60) * hourHeight
    }

    private func currentTimeOffset(hours: Range<Int>) -> CGFloat? {
        guard calendar.isDateInToday(itinerary.day) else { return nil }
        let value = offset(for: .now, hours: hours)
        guard value >= 0, value <= CGFloat(hours.count) * hourHeight else { return nil }
        return value
    }

    private func initialHour(_ hours: Range<Int>) -> Int {
        guard calendar.isDateInToday(itinerary.day) else { return hours.lowerBound }
        let current = calendar.component(.hour, from: .now) - 1
        return min(max(current, hours.lowerBound), hours.upperBound - 1)
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = calendar.date(byAdding: .hour, value: hour, to: dayStart) ?? dayStart
        return date.formatted(.dateTime.hour())
    }

    private func density(forHeight height: CGFloat) -> EventCardDensity {
        if height < 40 { return .compact }
        if height < 66 { return .regular }
        return .expanded
    }
}

/// Red line that marks the current time.
struct NowIndicator: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(Color.red)
                .frame(height: 1.5)
        }
    }
}

/// Places overlapping events side by side, like calendar apps do.
enum OverlapLayout {
    struct Slot {
        var column: Int
        var columns: Int
    }

    static func slots(for items: [ItineraryItem]) -> [UUID: Slot] {
        let sorted = items.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var result: [UUID: Slot] = [:]
        var cluster: [(id: UUID, column: Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flushCluster() {
            let columns = max(columnEnds.count, 1)
            for entry in cluster {
                result[entry.id] = Slot(column: entry.column, columns: columns)
            }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for item in sorted {
            if item.start >= clusterEnd {
                flushCluster()
            }
            if let column = columnEnds.firstIndex(where: { $0 <= item.start }) {
                columnEnds[column] = item.end
                cluster.append((item.id, column))
            } else {
                columnEnds.append(item.end)
                cluster.append((item.id, columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, item.end)
        }
        flushCluster()
        return result
    }
}
