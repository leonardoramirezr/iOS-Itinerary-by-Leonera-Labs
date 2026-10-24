import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit

/// OAuth 2.0 configuration derived from an iOS client ID created in Google Cloud Console.
struct GoogleOAuthConfig {
    private static let suffix = ".apps.googleusercontent.com"

    let clientID: String
    /// Reversed client ID, which Google accepts as the custom URL scheme of iOS clients.
    let callbackScheme: String

    var redirectURI: String { "\(callbackScheme):/oauth2redirect" }

    init(clientID rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasSuffix(Self.suffix), value.count > Self.suffix.count else {
            throw AppError.googleClientIDInvalid
        }
        clientID = value
        callbackScheme = "com.googleusercontent.apps." + String(value.dropLast(Self.suffix.count))
    }
}

/// Tokens persisted in the Keychain.
private struct GoogleTokens: Codable {
    var accessToken: String
    var expiresAt: Date
    var refreshToken: String?
    var email: String?
}

private struct GoogleTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int?
    let refreshToken: String?
    let idToken: String?
}

/// Signs in to Google with PKCE through `ASWebAuthenticationSession` (no SDK needed).
@MainActor
@Observable
final class GoogleAuthService {
    static let scopes = ["openid", "email", "https://www.googleapis.com/auth/calendar.readonly"]
    private static let tokensAccount = "google.oauth.tokens"

    private(set) var isSignedIn = false
    private(set) var email: String?

    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private var anchorProvider: PresentationAnchorProvider?

    init() {
        if let tokens = loadTokens() {
            isSignedIn = tokens.refreshToken != nil
            email = tokens.email
        }
    }

    func signIn(clientID: String) async throws {
        let config = try GoogleOAuthConfig(clientID: clientID)
        let verifier = PKCE.randomString()
        let state = PKCE.randomString()

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components?.url else { throw AppError.invalidURL("accounts.google.com") }

        let callbackURL = try await authenticate(url: url, callbackScheme: config.callbackScheme)
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = item("error") { throw AppError.googleAuthFailed(error) }
        guard item("state") == state, let code = item("code") else {
            throw AppError.googleAuthFailed("invalid_callback")
        }

        let response = try await requestToken([
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ])
        let tokens = GoogleTokens(
            accessToken: response.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600)),
            refreshToken: response.refreshToken,
            email: Self.email(fromIDToken: response.idToken)
        )
        saveTokens(tokens)
        isSignedIn = true
        email = tokens.email
    }

    func signOut() {
        if let token = loadTokens()?.refreshToken,
           let url = URL(string: "https://oauth2.googleapis.com/revoke") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = HTTP.formBody(["token": token])
            URLSession.shared.dataTask(with: request).resume()
        }
        KeychainStore.set(nil, for: Self.tokensAccount)
        isSignedIn = false
        email = nil
    }

    /// Access token for the Calendar API, refreshed when it is about to expire.
    func validAccessToken(clientID: String) async throws -> String {
        guard var tokens = loadTokens() else { throw AppError.googleNotSignedIn }
        if tokens.expiresAt > Date().addingTimeInterval(60) {
            return tokens.accessToken
        }
        guard let refreshToken = tokens.refreshToken else { throw AppError.googleNotSignedIn }
        let config = try GoogleOAuthConfig(clientID: clientID)
        do {
            let response = try await requestToken([
                "client_id": config.clientID,
                "refresh_token": refreshToken,
                "grant_type": "refresh_token"
            ])
            tokens.accessToken = response.accessToken
            tokens.expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
            if let newRefreshToken = response.refreshToken {
                tokens.refreshToken = newRefreshToken
            }
            saveTokens(tokens)
            return tokens.accessToken
        } catch AppError.http(let status, _) where status == 400 || status == 401 {
            // The refresh token was revoked or expired.
            KeychainStore.set(nil, for: Self.tokensAccount)
            isSignedIn = false
            email = nil
            throw AppError.googleSessionExpired
        }
    }

    private func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        let provider = PresentationAnchorProvider(anchor: Self.presentationAnchor())
        anchorProvider = provider
        defer {
            authSession = nil
            anchorProvider = nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error ?? AppError.googleAuthFailed("unknown"))
                }
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                continuation.resume(throwing: AppError.googleAuthFailed("could_not_start"))
            }
        }
    }

    private func requestToken(_ parameters: [String: String]) async throws -> GoogleTokenResponse {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw AppError.invalidURL("oauth2.googleapis.com")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.formBody(parameters)
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.validate(response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let token = try? decoder.decode(GoogleTokenResponse.self, from: data) else {
            throw AppError.invalidResponse
        }
        return token
    }

    private func loadTokens() -> GoogleTokens? {
        guard let json = KeychainStore.string(for: Self.tokensAccount) else { return nil }
        return try? JSONDecoder().decode(GoogleTokens.self, from: Data(json.utf8))
    }

    private func saveTokens(_ tokens: GoogleTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        KeychainStore.set(String(decoding: data, as: UTF8.self), for: Self.tokensAccount)
    }

    private static func presentationAnchor() -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
            return window
        }
        if let scene = scenes.first {
            return UIWindow(windowScene: scene)
        }
        return ASPresentationAnchor()
    }

    /// Reads the `email` claim of the ID token without verifying it; it is only shown in the UI.
    private static func email(fromIDToken token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claims["email"] as? String
    }
}

/// Supplies the window that presents the Google sign in sheet.
private final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}

/// Proof Key for Code Exchange helpers (RFC 7636).
private enum PKCE {
    static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max)
        }
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
