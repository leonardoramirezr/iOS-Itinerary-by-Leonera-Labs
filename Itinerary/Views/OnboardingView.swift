import SwiftUI

/// First launch: asks where the home and the office are.
struct OnboardingView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.day.timeline.left")
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                        Text("Welcome to Itinerary")
                            .font(.title2.bold())
                        Text("Tell me where your home and your office are. I use them to estimate travel times when I plan your day.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section("Where is your home?") {
                    NavigationLink {
                        PlacePickerView(title: String(localized: "Home"), place: $store.settings.home)
                    } label: {
                        PlaceRow(title: String(localized: "Home"), symbol: "house.fill", place: store.settings.home)
                    }
                }

                Section {
                    Toggle("My home is also my office", isOn: $store.settings.officeIsHome)
                    if !store.settings.officeIsHome {
                        NavigationLink {
                            PlacePickerView(title: String(localized: "Office"), place: $store.settings.office)
                        } label: {
                            PlaceRow(title: String(localized: "Office"), symbol: "building.2.fill", place: store.settings.office)
                        }
                    }
                } header: {
                    Text("Where is your office?")
                } footer: {
                    Text("You can change both places later in Settings.")
                }

                Section {
                    Button {
                        store.settings.hasCompletedOnboarding = true
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canContinue)
                }
            }
            .navigationTitle("Itinerary by Leonera Labs")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var canContinue: Bool {
        store.settings.home != nil && (store.settings.officeIsHome || store.settings.office != nil)
    }
}
