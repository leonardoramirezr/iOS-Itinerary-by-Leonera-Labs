import Foundation

/// LLM providers supported by the app. All of them are called through their OpenAI-compatible API.
enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case gemini
    case openAI
    case cloudflare
    case nvidia
    case groq

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .openAI: return "OpenAI"
        case .cloudflare: return "Cloudflare Workers AI"
        case .nvidia: return "NVIDIA NIM"
        case .groq: return "Groq"
        }
    }

    /// Base URL of the OpenAI-compatible API (`/chat/completions` is appended).
    var defaultBaseURL: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openAI: return "https://api.openai.com/v1"
        case .cloudflare: return "https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/v1"
        case .nvidia: return "https://integrate.api.nvidia.com/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .openAI: return "gpt-5-mini"
        case .cloudflare: return "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
        case .nvidia: return "meta/llama-3.3-70b-instruct"
        case .groq: return "openai/gpt-oss-120b"
        }
    }

    /// Whether `response_format: json_object` is sent by default.
    var defaultUsesJSONMode: Bool {
        switch self {
        case .gemini, .openAI, .groq: return true
        case .cloudflare, .nvidia: return false
        }
    }

    /// Cloudflare needs the account identifier inside the base URL.
    var requiresAccountID: Bool { self == .cloudflare }

    /// Page where the user can create an API key.
    var apiKeyURL: URL {
        switch self {
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")!
        case .cloudflare: return URL(string: "https://dash.cloudflare.com/profile/api-tokens")!
        case .nvidia: return URL(string: "https://build.nvidia.com/settings/api-keys")!
        case .groq: return URL(string: "https://console.groq.com/keys")!
        }
    }

    /// Keychain account that stores the API key. Groq's key is shared with speech to text.
    var keychainAccount: String { "apikey.\(rawValue)" }
}

/// User-editable connection settings of a provider.
struct ProviderConfig: Codable, Equatable {
    var baseURL: String
    var model: String
    var accountID: String
    var useJSONMode: Bool

    init(provider: LLMProvider) {
        baseURL = provider.defaultBaseURL
        model = provider.defaultModel
        accountID = ""
        useJSONMode = provider.defaultUsesJSONMode
    }

    /// Base URL with the account placeholder replaced and without a trailing slash.
    var resolvedBaseURL: String {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        url = url.replacingOccurrences(of: "{account_id}", with: accountID.trimmingCharacters(in: .whitespacesAndNewlines))
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }
}

/// Speech to text settings (Groq Whisper through the OpenAI-compatible API).
struct TranscriptionConfig: Codable, Equatable {
    static let defaultBaseURL = "https://api.groq.com/openai/v1"
    static let defaultModel = "whisper-large-v3-turbo"

    var baseURL = TranscriptionConfig.defaultBaseURL
    var model = TranscriptionConfig.defaultModel

    var resolvedBaseURL: String {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }
}
