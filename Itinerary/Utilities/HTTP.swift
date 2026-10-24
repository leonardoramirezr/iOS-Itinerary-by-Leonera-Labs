import Foundation

enum HTTP {
    /// Throws `AppError.http` with the provider's error message when the status is not 2xx.
    static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AppError.http(status: http.statusCode, message: errorMessage(from: data))
        }
    }

    /// Extracts a readable message from the different error formats used by the providers.
    static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data), let message = findMessage(in: json) {
            return message
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "—" : String(text.prefix(300))
    }

    private static func findMessage(in json: Any) -> String? {
        if let array = json as? [Any] {
            for element in array {
                if let message = findMessage(in: element) { return message }
            }
            return nil
        }
        guard let dictionary = json as? [String: Any] else { return nil }
        if let error = dictionary["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let error = dictionary["error"] as? String {
            if let description = dictionary["error_description"] as? String { return "\(error): \(description)" }
            return error
        }
        if let errors = dictionary["errors"] as? [[String: Any]], let message = errors.first?["message"] as? String {
            return message
        }
        if let message = dictionary["message"] as? String { return message }
        if let detail = dictionary["detail"] as? String { return detail }
        return nil
    }

    /// `application/x-www-form-urlencoded` body.
    static func formBody(_ parameters: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}

extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
