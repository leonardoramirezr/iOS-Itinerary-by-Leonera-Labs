import SwiftUI
import UIKit

/// Chooses where fixed events come from: Google Calendar (OAuth) or the calendars configured on the iPhone.
struct CalendarSettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(GoogleAuthService.self) private var googleAuth
    @Environment(\.openURL) private var openURL

    @State private var calendars: [CalendarInfo] = []
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var systemAccessGranted = false

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("Source", selection: $store.settings.calendarSource) {
                    ForEach(CalendarSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
            } footer: {
                Text("Events of the selected calendars are imported as fixed events and the plan is built around them.")
            }

            switch store.settings.calendarSource {
            case .disabled:
                EmptyView()
            case .google:
                googleSections
            case .system:
                systemSections
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.settings.calendarSource) {
            await reloadCalendars()
        }
    }

    @ViewBuilder
    private var googleSections: some View {
        @Bindable var bindableStore = store
        Section {
            TextField("OAuth client ID", text: $bindableStore.settings.googleClientID, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
            if googleAuth.isSignedIn {
                LabeledContent("Connected as", value: googleAuth.email ?? "—")
                Button("Disconnect", role: .destructive) {
                    googleAuth.signOut()
                    calendars = []
                }
            } else {
                Button {
                    Task { await connectGoogle() }
                } label: {
                    HStack {
                        Label("Connect Google Calendar", systemImage: "person.crop.circle.badge.plus")
                        if isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isWorking || store.settings.googleClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Google account")
        } footer: {
            Text("Create an OAuth client of type iOS in Google Cloud Console with the bundle ID of this app and paste its client ID here. The README explains every step.")
        }

        if googleAuth.isSignedIn {
            calendarListSection(
                isSelected: { store.settings.isGoogleCalendarSelected($0) },
                toggle: { store.settings.toggleGoogleCalendar($0) }
            )
        }
    }

    @ViewBuilder
    private var systemSections: some View {
        if systemAccessGranted {
            calendarListSection(
                isSelected: { store.settings.isSystemCalendarSelected($0) },
                toggle: { store.settings.toggleSystemCalendar($0) }
            )
        } else {
            Section {
                if SystemCalendarService.shared.isAccessUndetermined {
                    Button("Allow calendar access") {
                        Task { await requestSystemAccess() }
                    }
                } else {
                    Text("Calendar access is off.")
                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            } footer: {
                Text("Google accounts added in the iPhone Settings app also appear here.")
            }
        }
    }

    private func calendarListSection(isSelected: @escaping (String) -> Bool, toggle: @escaping (String) -> Void) -> some View {
        Section {
            if isWorking && calendars.isEmpty {
                ProgressView()
            } else if calendars.isEmpty {
                Text("No calendars found.")
                    .foregroundStyle(.secondary)
            }
            ForEach(calendars) { calendar in
                Button {
                    toggle(calendar.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(calendar.colorHex.flatMap(Color.init(hex:)) ?? Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendar.name)
                                .foregroundStyle(.primary)
                            if let source = calendar.sourceName {
                                Text(source)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if isSelected(calendar.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        } header: {
            Text("Calendars")
        }
    }

    private func reloadCalendars() async {
        errorMessage = nil
        calendars = []
        switch store.settings.calendarSource {
        case .disabled:
            return
        case .google:
            guard googleAuth.isSignedIn else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                let token = try await googleAuth.validAccessToken(clientID: store.settings.googleClientID)
                let list = try await GoogleCalendarAPI(accessToken: token).calendars()
                calendars = list.sorted { ($0.isPrimary ? 0 : 1, $0.name) < ($1.isPrimary ? 0 : 1, $1.name) }
                if store.settings.googleCalendarIDs.isEmpty, let primary = list.first(where: \.isPrimary) {
                    store.settings.googleCalendarIDs = [primary.id]
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        case .system:
            systemAccessGranted = SystemCalendarService.shared.hasAccess
            if systemAccessGranted {
                calendars = SystemCalendarService.shared.calendars()
            }
        }
    }

    private func connectGoogle() async {
        isWorking = true
        errorMessage = nil
        do {
            try await googleAuth.signIn(clientID: store.settings.googleClientID)
            isWorking = false
            await reloadCalendars()
        } catch is CancellationError {
            isWorking = false
        } catch {
            isWorking = false
            errorMessage = error.localizedDescription
        }
    }

    private func requestSystemAccess() async {
        do {
            systemAccessGranted = try await SystemCalendarService.shared.requestAccess()
            if !systemAccessGranted {
                errorMessage = AppError.calendarAccessDenied.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await reloadCalendars()
    }
}

extension Color {
    /// Creates a color from `#RRGGBB`.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
