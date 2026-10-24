import Foundation

struct ChatMessage: Hashable {
    var role: String
    var content: String

    static func system(_ content: String) -> ChatMessage { ChatMessage(role: "system", content: content) }
    static func user(_ content: String) -> ChatMessage { ChatMessage(role: "user", content: content) }
}

/// Client for `POST {baseURL}/chat/completions` of any OpenAI-compatible API.
struct OpenAICompatibleClient {
    var baseURL: String
    var apiKey: String
    var session: URLSession = .shared

    /// Returns the text of the first choice. When JSON mode is rejected with HTTP 400 the request is retried without it.
    func complete(model: String, messages: [ChatMessage], jsonMode: Bool) async throws -> String {
        do {
            return try await send(model: model, messages: messages, jsonMode: jsonMode)
        } catch AppError.http(let status, _) where jsonMode && status == 400 {
            return try await send(model: model, messages: messages, jsonMode: false)
        }
    }

    private func send(model: String, messages: [ChatMessage], jsonMode: Bool) async throws -> String {
        let endpoint = baseURL + "/chat/completions"
        guard let url = URL(string: endpoint), url.scheme?.hasPrefix("http") == true else {
            throw AppError.invalidURL(endpoint)
        }
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines),
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try HTTP.validate(response, data: data)
        guard let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data) else {
            throw AppError.invalidResponse
        }
        let content = decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { throw AppError.emptyResponse }
        return content
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message?
    }

    let choices: [Choice]?
}
