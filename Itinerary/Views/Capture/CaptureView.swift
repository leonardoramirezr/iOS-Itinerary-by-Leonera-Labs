import SwiftUI

/// Dictation screen: records the activities, shows what will be considered and generates the itinerary.
struct CaptureView: View {
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var store
    @Environment(ItineraryStore.self) private var itineraries
    @Environment(GoogleAuthService.self) private var googleAuth
    @State private var model = CaptureModel()

    var body: some View {
        NavigationStack {
            Form {
                recorderSection

                Section {
                    TextEditor(text: $model.transcript)
                        .frame(minHeight: 140)
                        .disabled(model.isBusy)
                } header: {
                    Text("What do you need to do?")
                } footer: {
                    Text("Dictate or type your errands, tasks and appointments. Every recording is added to the text, and you can edit it before generating.")
                }

                fixedEventsSection
                routinesSection

                if let errorMessage = model.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    LabeledContent("Model", value: "\(store.settings.selectedProvider.displayName) · \(store.settings[config: store.settings.selectedProvider].model)")
                        .font(.footnote)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        Task { await generate() }
                    }
                    .disabled(!canGenerate)
                }
            }
            .overlay {
                if model.phase == .planning {
                    PlanningOverlay()
                }
            }
            .interactiveDismissDisabled(model.phase != .idle)
            .task {
                if model.transcript.isEmpty {
                    let draft = itineraries.draft(for: day)
                    model.transcript = draft.isEmpty ? (itineraries.itinerary(for: day)?.transcript ?? "") : draft
                }
                await model.loadFixedEvents(for: day, settings: store.settings, googleAuth: googleAuth)
            }
            .onDisappear {
                model.cancelRecording()
                itineraries.setDraft(model.transcript, for: day)
            }
        }
    }

    private var canGenerate: Bool {
        model.phase == .idle && !model.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recorderSection: some View {
        Section {
            VStack(spacing: 12) {
                Button {
                    Task { await model.toggleRecording(store: store) }
                } label: {
                    ZStack {
                        Circle()
                            .fill(model.recorder.isRecording ? Color.red : Color.accentColor)
                            .frame(width: 88, height: 88)
                            .scaleEffect(model.recorder.isRecording ? 1 + CGFloat(model.recorder.level) * 0.15 : 1)
                            .animation(.easeOut(duration: 0.1), value: model.recorder.level)
                        Image(systemName: model.recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
                .accessibilityLabel(model.recorder.isRecording ? Text("Stop recording") : Text("Start recording"))

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if model.phase == .transcribing {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var statusText: LocalizedStringKey {
        switch model.phase {
        case .recording:
            let elapsed = Duration.seconds(model.recorder.elapsed).formatted(.time(pattern: .minuteSecond))
            return "Recording… \(elapsed)"
        case .transcribing:
            return "Transcribing…"
        case .planning:
            return "Building your itinerary…"
        case .idle:
            return "Tap the microphone and dictate your activities"
        }
    }

    @ViewBuilder
    private var fixedEventsSection: some View {
        Section {
            if store.settings.calendarSource == .disabled {
                Text("No calendar connected. You can connect Google Calendar in Settings.")
                    .foregroundStyle(.secondary)
            } else if model.isLoadingFixedEvents {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading events…")
                }
            } else if let error = model.fixedEventsError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if model.fixedEvents.isEmpty {
                Text("No events on this day.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.fixedEvents) { event in
                    FixedEventRow(event: event)
                }
            }
        } header: {
            Text("Fixed events")
        } footer: {
            Text("Calendar events keep their time; the plan is built around them.")
        }
    }

    private var routinesSection: some View {
        Section("Daily routines") {
            let routines = store.settings.enabledRoutines
            if routines.isEmpty {
                Text("No routines enabled.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(RoutineSlot.allCases) { slot in
                    let names = routines
                        .filter { $0.slot == slot }
                        .map { "\($0.name) (\(TimeText.duration(minutes: $0.durationMinutes)))" }
                    if !names.isEmpty {
                        LabeledContent {
                            Text(names.joined(separator: ", "))
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Label(slot.title, systemImage: slot.symbol)
                        }
                    }
                }
            }
        }
    }

    private func generate() async {
        guard let itinerary = await model.generate(for: day, store: store, googleAuth: googleAuth) else { return }
        itineraries.save(itinerary)
        dismiss()
    }
}

struct FixedEventRow: View {
    let event: FixedEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                Text(event.isAllDay ? String(localized: "All day") : TimeText.range(event.start, event.end))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PlanningOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Building your itinerary…")
                    .font(.headline)
                Text("This can take a few seconds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
