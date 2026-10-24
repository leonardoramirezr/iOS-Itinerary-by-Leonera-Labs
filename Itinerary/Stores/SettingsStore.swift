import Foundation
import Observation

/// Observable owner of `AppSettings`. Every change is written to `UserDefaults` immediately.
@MainActor
@Observable
final class SettingsStore {
    private static let storageKey = "app.settings.v1"

    private var storage: AppSettings
    private let defaults: UserDefaults

    var settings: AppSettings {
        get { storage }
        set {
            storage = newValue
            save()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            storage = decoded
        } else {
            storage = AppSettings()
        }
    }

    /// Current text of a prompt: the user override or the default.
    func prompt(_ kind: PromptKind) -> String {
        settings.prompts[kind.rawValue] ?? kind.defaultText
    }

    func setPrompt(_ text: String, for kind: PromptKind) {
        if text == kind.defaultText {
            settings.prompts[kind.rawValue] = nil
        } else {
            settings.prompts[kind.rawValue] = text
        }
    }

    func isPromptCustomized(_ kind: PromptKind) -> Bool {
        settings.prompts[kind.rawValue] != nil
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
