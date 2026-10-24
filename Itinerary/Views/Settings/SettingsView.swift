import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        PlacePickerView(title: String(localized: "Home"), place: $store.settings.home)
                    } label: {
                        PlaceRow(title: String(localized: "Home"), symbol: "house.fill", place: store.settings.home)
                    }
                    Toggle("My home is also my office", isOn: $store.settings.officeIsHome)
                    if !store.settings.officeIsHome {
                        NavigationLink {
                            PlacePickerView(title: String(localized: "Office"), place: $store.settings.office)
                        } label: {
                            PlaceRow(title: String(localized: "Office"), symbol: "building.2.fill", place: store.settings.office)
                        }
                    }
                    Picker("Travel mode", selection: $store.settings.travelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                } header: {
                    Text("Places")
                }

                Section {
                    DatePicker("Day starts", selection: $store.settings.dayStartMinutes.timeOfDay, displayedComponents: .hourAndMinute)
                    DatePicker("Day ends", selection: $store.settings.dayEndMinutes.timeOfDay, displayedComponents: .hourAndMinute)
                    NavigationLink {
                        RoutineSettingsView()
                    } label: {
                        LabeledContent("Daily routines", value: "\(store.settings.enabledRoutines.count)")
                    }
                } header: {
                    Text("Your day")
                } footer: {
                    Text("Flexible activities are placed in the morning whenever possible.")
                }

                Section {
                    Picker("Provider", selection: $store.settings.selectedProvider) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    NavigationLink("Providers and API keys") {
                        ProvidersView()
                    }
                    NavigationLink("Speech to text") {
                        TranscriptionSettingsView()
                    }
                    NavigationLink("Prompts") {
                        PromptsView()
                    }
                } header: {
                    Text("Artificial intelligence")
                }

                Section {
                    NavigationLink {
                        CalendarSettingsView()
                    } label: {
                        LabeledContent("Fixed events", value: store.settings.calendarSource.title)
                    }
                } header: {
                    Text("Calendar")
                }

                Section {
                    Picker("Event height", selection: $store.settings.timelineMode) {
                        ForEach(TimelineMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } header: {
                    Text("Display")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                } header: {
                    Text("About")
                } footer: {
                    Text("Itinerary by Leonera Labs")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

extension Binding where Value == Int {
    /// Exposes minutes after midnight as a `Date` for `DatePicker`.
    var timeOfDay: Binding<Date> {
        Binding<Date>(
            get: {
                let minutes = wrappedValue
                return Calendar.current.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }
}
