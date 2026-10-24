import SwiftUI

/// Daily routines grouped by time of day.
struct RoutineSettingsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var editingRoutine: RoutineActivity?

    var body: some View {
        List {
            ForEach(RoutineSlot.allCases) { slot in
                Section {
                    let routines = store.settings.routines.filter { $0.slot == slot }
                    if routines.isEmpty {
                        Text("No routines")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(routines) { routine in
                        Button {
                            editingRoutine = routine
                        } label: {
                            RoutineRow(routine: routine)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { routines[$0].id }
                        store.settings.routines.removeAll { ids.contains($0.id) }
                    }
                    Button {
                        editingRoutine = RoutineActivity(name: "", slot: slot, durationMinutes: 15)
                    } label: {
                        Label("Add routine", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Label(slot.title, systemImage: slot.symbol)
                }
            }
        }
        .navigationTitle("Daily routines")
        .toolbar {
            EditButton()
        }
        .sheet(item: $editingRoutine) { routine in
            RoutineEditorView(routine: routine) { updated in
                save(updated)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Enabled routines are added to every plan, inside their time of day and with their exact duration.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    private func save(_ routine: RoutineActivity) {
        if let index = store.settings.routines.firstIndex(where: { $0.id == routine.id }) {
            store.settings.routines[index] = routine
        } else {
            store.settings.routines.append(routine)
        }
    }
}

struct RoutineRow: View {
    let routine: RoutineActivity

    var body: some View {
        HStack {
            Image(systemName: routine.isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(routine.isEnabled ? Color.accentColor : Color.secondary)
            Text(routine.name)
                .foregroundStyle(routine.isEnabled ? Color.primary : Color.secondary)
            Spacer()
            Text(TimeText.duration(minutes: routine.durationMinutes))
                .foregroundStyle(.secondary)
        }
    }
}

struct RoutineEditorView: View {
    @State var routine: RoutineActivity
    let onSave: (RoutineActivity) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $routine.name)
                    Picker("Time of day", selection: $routine.slot) {
                        ForEach(RoutineSlot.allCases) { slot in
                            Label(slot.title, systemImage: slot.symbol).tag(slot)
                        }
                    }
                    Stepper(value: $routine.durationMinutes, in: 5...240, step: 5) {
                        LabeledContent("Duration", value: TimeText.duration(minutes: routine.durationMinutes))
                    }
                    Toggle("Include in my plans", isOn: $routine.isEnabled)
                }
            }
            .navigationTitle("Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var trimmed = routine
                        trimmed.name = routine.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
