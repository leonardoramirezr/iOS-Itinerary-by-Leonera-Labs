import Foundation
import Observation

/// State of the dictation screen: recording, transcription, fixed events and planning.
@MainActor
@Observable
final class CaptureModel {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case planning
    }

    var transcript = ""
    var errorMessage: String?
    private(set) var phase: Phase = .idle
    private(set) var fixedEvents: [FixedEvent] = []
    private(set) var fixedEventsError: String?
    private(set) var isLoadingFixedEvents = false
    private(set) var hasLoadedFixedEvents = false

    let recorder = AudioRecorder()

    var isBusy: Bool { phase == .transcribing || phase == .planning }

    func toggleRecording(store: SettingsStore) async {
        errorMessage = nil
        if recorder.isRecording {
            guard let fileURL = recorder.stop() else {
                phase = .idle
                return
            }
            await transcribe(fileURL, store: store)
        } else {
            do {
                try await recorder.start()
                phase = .recording
            } catch {
                phase = .idle
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelRecording() {
        recorder.cancel()
        if phase == .recording { phase = .idle }
    }

    private func transcribe(_ fileURL: URL, store: SettingsStore) async {
        phase = .transcribing
        defer {
            phase = .idle
            try? FileManager.default.removeItem(at: fileURL)
        }
        do {
            guard let apiKey = KeychainStore.apiKey(for: .groq) else { throw AppError.missingTranscriptionKey }
            let config = store.settings.transcription
            let service = TranscriptionService(baseURL: config.resolvedBaseURL, model: config.model, apiKey: apiKey)
            let text = try await service.transcribe(
                fileURL: fileURL,
                prompt: store.prompt(.transcriptionHint),
                language: AppLanguage.code
            )
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { throw AppError.emptyTranscription }
            let existing = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            transcript = existing.isEmpty ? cleaned : existing + "\n" + cleaned
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadFixedEvents(for day: Date, settings: AppSettings, googleAuth: GoogleAuthService) async {
        isLoadingFixedEvents = true
        defer {
            isLoadingFixedEvents = false
            hasLoadedFixedEvents = true
        }
        do {
            fixedEvents = try await FixedEventsLoader.load(for: day, settings: settings, googleAuth: googleAuth)
            fixedEventsError = nil
        } catch {
            fixedEvents = []
            fixedEventsError = error.localizedDescription
        }
    }

    /// Plans the day with the selected provider. Returns `nil` and sets `errorMessage` on failure.
    func generate(for day: Date, store: SettingsStore, googleAuth: GoogleAuthService) async -> Itinerary? {
        errorMessage = nil
        let activities = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !activities.isEmpty else {
            errorMessage = AppError.emptyActivities.localizedDescription
            return nil
        }

        phase = .planning
        defer { phase = .idle }

        let settings = store.settings
        if !hasLoadedFixedEvents {
            await loadFixedEvents(for: day, settings: settings, googleAuth: googleAuth)
        }

        do {
            let provider = settings.selectedProvider
            let config = settings[config: provider]
            guard let apiKey = KeychainStore.apiKey(for: provider) else {
                throw AppError.missingAPIKey(provider: provider.displayName)
            }
            if provider.requiresAccountID && config.accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AppError.missingAccountID
            }
            let request = PlanningRequest(
                day: day,
                now: Date(),
                activities: activities,
                settings: settings,
                fixedEvents: fixedEvents,
                commute: await CommuteEstimator.describe(settings: settings, day: day)
            )
            return try await ItineraryPlanner.plan(
                request,
                client: OpenAICompatibleClient(baseURL: config.resolvedBaseURL, apiKey: apiKey),
                model: config.model.trimmingCharacters(in: .whitespacesAndNewlines),
                jsonMode: config.useJSONMode,
                systemTemplate: store.prompt(.itinerarySystem),
                userTemplate: store.prompt(.itineraryUser),
                providerName: provider.displayName
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
