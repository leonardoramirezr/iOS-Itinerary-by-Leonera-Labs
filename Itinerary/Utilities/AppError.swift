import Foundation

/// Errors shown to the user. Messages are localized.
enum AppError: LocalizedError {
    case missingAPIKey(provider: String)
    case missingAccountID
    case missingTranscriptionKey
    case invalidURL(String)
    case http(status: Int, message: String)
    case invalidResponse
    case emptyResponse
    case emptyActivities
    case unreadableItinerary(String)
    case microphoneDenied
    case recordingFailed
    case emptyTranscription
    case placeNotFound
    case locationDenied
    case calendarAccessDenied
    case googleClientIDInvalid
    case googleNotSignedIn
    case googleSessionExpired
    case googleAuthFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return String(localized: "Add an API key for \(provider) in Settings.")
        case .missingAccountID:
            return String(localized: "Add your Cloudflare account ID in Settings.")
        case .missingTranscriptionKey:
            return String(localized: "Add your Groq API key in Settings › Speech to text.")
        case .invalidURL(let url):
            return String(localized: "The URL is not valid: \(url)")
        case .http(let status, let message):
            return String(localized: "The server answered with error \(status): \(message)")
        case .invalidResponse:
            return String(localized: "The server sent an unexpected response.")
        case .emptyResponse:
            return String(localized: "The model returned an empty answer.")
        case .emptyActivities:
            return String(localized: "Dictate or type at least one activity.")
        case .unreadableItinerary(let preview):
            return String(localized: "The model answer could not be read as an itinerary. Answer: \(preview)")
        case .microphoneDenied:
            return String(localized: "Microphone access is off. Turn it on in the iPhone Settings app.")
        case .recordingFailed:
            return String(localized: "The recording could not be started.")
        case .emptyTranscription:
            return String(localized: "No speech was detected in the recording.")
        case .placeNotFound:
            return String(localized: "The place could not be found.")
        case .locationDenied:
            return String(localized: "Location access is off. Turn it on in the iPhone Settings app.")
        case .calendarAccessDenied:
            return String(localized: "Calendar access is off. Turn it on in the iPhone Settings app.")
        case .googleClientIDInvalid:
            return String(localized: "Enter a valid Google OAuth client ID. It ends with .apps.googleusercontent.com.")
        case .googleNotSignedIn:
            return String(localized: "Connect your Google account in Settings › Calendar.")
        case .googleSessionExpired:
            return String(localized: "Your Google session expired. Connect your account again in Settings › Calendar.")
        case .googleAuthFailed(let reason):
            return String(localized: "Google sign in failed: \(reason)")
        }
    }
}
