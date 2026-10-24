import SwiftUI

/// Result of an API key test.
enum KeyTestState: Equatable {
    case idle
    case testing
    case success(String)
    case failure(String)
}

/// Button that tests an API key and shows the result below it.
struct KeyTestSection: View {
    let state: KeyTestState
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label("Test API key", systemImage: "checkmark.shield")
                Spacer()
                switch state {
                case .idle:
                    EmptyView()
                case .testing:
                    ProgressView()
                case .success:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failure:
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
            }
        }
        .disabled(isDisabled || state == .testing)

        switch state {
        case .success(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.green)
        case .failure(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        case .idle, .testing:
            EmptyView()
        }
    }
}

/// List of the LLM providers.
struct ProvidersView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        List {
            Section {
                ForEach(LLMProvider.allCases) { provider in
                    NavigationLink {
                        ProviderDetailView(provider: provider)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.displayName)
                                Text(store.settings[config: provider].model)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if provider == store.settings.selectedProvider {
                                Text("In use")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                            Image(systemName: KeychainStore.apiKey(for: provider) == nil ? "key" : "key.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Every provider is called through its OpenAI-compatible API. Keys are stored in the iOS Keychain of this device.")
            }
        }
        .navigationTitle("Providers")
    }
}

/// API key, model and endpoint of one provider.
struct ProviderDetailView: View {
    let provider: LLMProvider

    @Environment(SettingsStore.self) private var store
    @State private var apiKey = ""
    @State private var config: ProviderConfig
    @State private var testState: KeyTestState = .idle
    @State private var didLoad = false

    init(provider: LLMProvider) {
        self.provider = provider
        _config = State(initialValue: ProviderConfig(provider: provider))
    }

    var body: some View {
        Form {
            Section {
                SecureField("API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                KeyTestSection(state: testState, isDisabled: !canTest) {
                    Task { await testKey() }
                }
                Link(destination: provider.apiKeyURL) {
                    Label("Get an API key", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("API key")
            } footer: {
                if provider == .groq {
                    Text("This key is also used for speech to text.")
                }
            }

            if provider.requiresAccountID {
                Section {
                    TextField("Account ID", text: $config.accountID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Cloudflare account")
                } footer: {
                    Text("Find it in the Cloudflare dashboard, under Workers AI. The API token needs the Workers AI permission.")
                }
            }

            Section {
                TextField("Model", text: $config.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Base URL", text: $config.baseURL, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.footnote.monospaced())
                Toggle("JSON mode", isOn: $config.useJSONMode)
                Button("Restore defaults") {
                    let accountID = config.accountID
                    config = ProviderConfig(provider: provider)
                    config.accountID = accountID
                }
            } header: {
                Text("Model")
            } footer: {
                Text("The app calls {base URL}/chat/completions. JSON mode sends response_format json_object; it is retried without it if the provider rejects it.")
            }

            Section {
                if store.settings.selectedProvider == provider {
                    Label("This provider is in use", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Use this provider") {
                        store.settings.selectedProvider = provider
                    }
                }
            }
        }
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            apiKey = KeychainStore.string(for: provider.keychainAccount) ?? ""
            config = store.settings[config: provider]
        }
        .onChange(of: apiKey) { _, newValue in
            KeychainStore.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.keychainAccount)
            testState = .idle
        }
        .onChange(of: config) { _, newValue in
            store.settings[config: provider] = newValue
            testState = .idle
        }
    }

    private var canTest: Bool {
        let hasKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAccount = !provider.requiresAccountID || !config.accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasKey && hasAccount
    }

    private func testKey() async {
        testState = .testing
        let client = OpenAICompatibleClient(
            baseURL: config.resolvedBaseURL,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            let reply = try await client.complete(
                model: config.model,
                messages: [.user(store.prompt(.apiKeyTest))],
                jsonMode: false
            )
            let snippet = String(reply.prefix(80))
            testState = .success(String(localized: "The key works. \(config.model) replied: \(snippet)"))
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}

/// Groq speech to text settings.
struct TranscriptionSettingsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var apiKey = ""
    @State private var testState: KeyTestState = .idle
    @State private var didLoad = false

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                SecureField("Groq API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                KeyTestSection(state: testState, isDisabled: apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    Task { await testKey() }
                }
                Link(destination: LLMProvider.groq.apiKeyURL) {
                    Label("Get an API key", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("Groq")
            } footer: {
                Text("Your dictation is transcribed by Groq. The same key is used by the Groq LLM provider.")
            }

            Section {
                TextField("Model", text: $store.settings.transcription.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Base URL", text: $store.settings.transcription.baseURL, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.footnote.monospaced())
                Button("Restore defaults") {
                    store.settings.transcription = TranscriptionConfig()
                }
            } header: {
                Text("Model")
            } footer: {
                Text("The app calls {base URL}/audio/transcriptions.")
            }
        }
        .navigationTitle("Speech to text")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            apiKey = KeychainStore.string(for: LLMProvider.groq.keychainAccount) ?? ""
        }
        .onChange(of: apiKey) { _, newValue in
            KeychainStore.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: LLMProvider.groq.keychainAccount)
            testState = .idle
        }
    }

    private func testKey() async {
        testState = .testing
        let config = store.settings.transcription
        let service = TranscriptionService(
            baseURL: config.resolvedBaseURL,
            model: config.model,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            let models = try await service.availableModels()
            let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if models.isEmpty || models.contains(model) {
                testState = .success(String(localized: "The key works and \(model) is available."))
            } else {
                testState = .failure(String(localized: "The key works, but the model \(model) was not found."))
            }
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}
