import SwiftUI

/// Every prompt the app uses.
struct PromptsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        List {
            Section {
                ForEach(PromptKind.allCases) { kind in
                    NavigationLink {
                        PromptEditorView(kind: kind)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(kind.title)
                                if store.isPromptCustomized(kind) {
                                    Text("Edited")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2), in: Capsule())
                                        .foregroundStyle(.orange)
                                }
                            }
                            Text(kind.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Placeholders such as {{activities}} are replaced before the prompt is sent.")
            }
        }
        .navigationTitle("Prompts")
    }
}

/// Editor of one prompt with its placeholders.
struct PromptEditorView: View {
    let kind: PromptKind

    @Environment(SettingsStore.self) private var store
    @State private var text = ""
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 320)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text(kind.title)
            } footer: {
                Text(kind.summary)
            }

            if !kind.placeholders.isEmpty {
                Section {
                    ForEach(kind.placeholders, id: \.self) { placeholder in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "{{\(placeholder.name)}}")
                                .font(.footnote.monospaced().weight(.semibold))
                            Text(placeholder.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Placeholders")
                } footer: {
                    if kind == .itinerarySystem {
                        Text("Keep the JSON structure of the default prompt: the app reads summary, items (title, start, end, kind, location, notes) and unscheduled.")
                    }
                }
            }

            Section {
                Button("Restore default", role: .destructive) {
                    text = kind.defaultText
                }
                .disabled(text == kind.defaultText)
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            text = store.prompt(kind)
        }
        .onChange(of: text) { _, newValue in
            guard didLoad else { return }
            store.setPrompt(newValue, for: kind)
        }
    }
}
