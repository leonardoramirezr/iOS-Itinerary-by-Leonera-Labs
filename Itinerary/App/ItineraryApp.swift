import SwiftUI

@main
struct ItineraryApp: App {
    @State private var settingsStore = SettingsStore()
    @State private var itineraryStore = ItineraryStore()
    @State private var googleAuth = GoogleAuthService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settingsStore)
                .environment(itineraryStore)
                .environment(googleAuth)
        }
    }
}

struct RootView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        if store.settings.hasCompletedOnboarding {
            HomeView()
        } else {
            OnboardingView()
        }
    }
}
