import Foundation

/// Speech to text through Groq's OpenAI-compatible `audio/transcriptions` endpoint.
struct TranscriptionService {
    var baseURL: String
    var model: String
    var apiKey: String
    var session: URLSession = .shared

    func transcribe(fileURL: URL, prompt: String, language: String?) async throws -> String {
        let endpoint = baseURL + "/audio/transcriptions"
        guard let url = URL(string: endpoint) else { throw AppError.invalidURL(endpoint) }
        let audio = try Data(contentsOf: fileURL)
        let boundary = "Boundary-\(UUID().uuidString)"

        var body = Data()
        func addField(_ name: String, _ value: String) {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }
        addField("model", model.trimmingCharacters(in: .whitespacesAndNewlines))
        addField("response_format", "json")
        addField("temperature", "0")
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            addField("prompt", trimmedPrompt)
        }
        if let language, !language.isEmpty {
            addField("language", language)
        }
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        body.appendString("Content-Type: audio/m4a\r\n\r\n")
        body.append(audio)
        body.appendString("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(for: request, from: body)
        try HTTP.validate(response, data: data)
        guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            throw AppError.invalidResponse
        }
        return decoded.text
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}
