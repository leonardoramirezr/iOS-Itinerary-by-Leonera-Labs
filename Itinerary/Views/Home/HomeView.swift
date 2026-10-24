import SwiftUI

/// Main screen: the itinerary of the selected day.
struct HomeView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(ItineraryStore.self) private var itineraries
    @Environment(GoogleAuthService.self) private var googleAuth

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var isCapturePresented = false
    @State private var isSettingsPresented = false
    @State private var isDatePickerPresented = false
    @State private var selectedItem: ItineraryItem?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            VStack(spacing: 0) {
                DaySelector(day: $day)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Picker("Event height", selection: $store.settings.timelineMode) {
                    ForEach(TimelineMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Itinerary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isDatePickerPresented = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel(Text("Choose a day"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("Settings"))
                }
            }
            .safeAreaInset(edge: .bottom) {
                planButton
            }
            .sheet(isPresented: $isCapturePresented) {
                CaptureView(day: day)
                    .environment(store)
                    .environment(itineraries)
                    .environment(googleAuth)
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
                    .environment(store)
                    .environment(itineraries)
                    .environment(googleAuth)
            }
            .sheet(isPresented: $isDatePickerPresented) {
                DayPickerSheet(day: $day)
            }
            .sheet(item: $selectedItem) { item in
                EventDetailView(item: item) {
                    itineraries.removeItem(id: item.id, fromDayKey: DayKey.make(for: day))
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let itinerary = itineraries.itinerary(for: day) {
            switch store.settings.timelineMode {
            case .uniform:
                UniformTimelineView(itinerary: itinerary) { selectedItem = $0 }
            case .proportional:
                ProportionalTimelineView(itinerary: itinerary) { selectedItem = $0 }
            }
        } else {
            ContentUnavailableView {
                Label("No plan for this day", systemImage: "calendar.badge.plus")
            } description: {
                Text("Tap Plan my day and tell me everything you need to do. I will build an itinerary with travel times and your daily routines.")
            }
        }
    }

    private var planButton: some View {
        let title: LocalizedStringKey = itineraries.itinerary(for: day) == nil ? "Plan my day" : "Plan again"
        return Button {
            isCapturePresented = true
        } label: {
            Label(title, systemImage: "mic.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Previous / next day navigation with a relative title.
struct DaySelector: View {
    @Binding var day: Date

    private let calendar = Calendar.current

    var body: some View {
        HStack {
            Button {
                shift(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Previous day"))

            Spacer()

            VStack(spacing: 2) {
                Text(relativeTitle)
                    .font(.headline)
                Text(day.formatted(date: .long, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onTapGesture {
                day = calendar.startOfDay(for: .now)
            }

            Spacer()

            Button {
                shift(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Next day"))
        }
    }

    private var relativeTitle: String {
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(day) { return String(localized: "Tomorrow") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.wide)).capitalized
    }

    private func shift(by days: Int) {
        if let next = calendar.date(byAdding: .day, value: days, to: day) {
            day = calendar.startOfDay(for: next)
        }
    }
}

/// Graphical calendar to jump to any day.
struct DayPickerSheet: View {
    @Binding var day: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker("Day", selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Choose a day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Today") {
                            day = Calendar.current.startOfDay(for: .now)
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onChange(of: day) { _, newValue in
                    let start = Calendar.current.startOfDay(for: newValue)
                    if start != newValue { day = start }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
