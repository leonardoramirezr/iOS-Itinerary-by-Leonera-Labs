import Foundation

/// Where the models of a provider are listed: its base URL and the key that unlocks it.
struct ModelSource: Equatable {
    var baseURL: String
    var apiKey: String
}

/// Models offered by a provider. `idle` when there is no key to list them with.
enum ModelListState: Equatable {
    case idle
    case loaded([String])
    case failure(String)
}

/// Lists the models of any OpenAI-compatible API through `GET {baseURL}/models`.
enum ModelCatalog {
    /// Pause after the last change, so typing a key does not send one request per character.
    static let debounce = Duration.milliseconds(600)

    /// Model identifiers available for the key, sorted. Gemini prefixes them with `models/`, which is dropped.
    static func fetch(_ source: ModelSource) async throws -> [String] {
        let endpoint = source.baseURL + "/models"
        guard let url = URL(string: endpoint), url.scheme?.hasPrefix("http") == true else {
            throw AppError.invalidURL(endpoint)
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(source.apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.validate(response, data: data)
        guard let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            throw AppError.invalidResponse
        }
        let prefix = "models/"
        return decoded.data
            .map { $0.id.hasPrefix(prefix) ? String($0.id.dropFirst(prefix.count)) : $0.id }
            .sorted()
    }

    /// Waits for the debounce, then lists the models. Returns `nil` when the task was cancelled, because the answer is stale.
    static func load(_ source: ModelSource) async -> ModelListState? {
        guard !source.apiKey.isEmpty else { return .idle }
        try? await Task.sleep(for: debounce)
        guard !Task.isCancelled else { return nil }
        do {
            let models = try await fetch(source)
            guard !Task.isCancelled else { return nil }
            return .loaded(models)
        } catch {
            guard !Task.isCancelled else { return nil }
            return .failure(error.localizedDescription)
        }
    }
}

private struct ModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}
