import Foundation

/// Translates English and Japanese announcements into Traditional Chinese with Muse Spark Open, Meta's
/// open-weight model, served by Baseten. The translation is shown only as help for reading: what the app
/// decides (whose flight, which event, which gate) still comes from the rules and the flight data.
public struct MuseSparkOpen: Sendable {
    public static let endpoint = URL(string: "https://inference.baseten.co/v1/chat/completions")!
    public static let model = "meta-models/muse-spark-open-1026"
    let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Mandarin needs no translation; English sentences, and Japanese (which has kana), do.
    public static func needsTranslation(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let kana = scalars.contains { (0x3040...0x30FF).contains($0.value) }
        let han = scalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        // A few words at least: a lone "CI 100" says nothing to translate.
        let words = text.split { !$0.isLetter }.filter { $0.count > 1 && $0.unicodeScalars.allSatisfy { $0.value < 0x250 } }
        return kana || (!han && words.count >= 3)
    }

    public func translate(_ announcement: String) async throws -> String {
        let body: [String: Any] = [
            "model": Self.model,
            "reasoning_effort": "low",
            "max_tokens": 800,    // the model reasons first; less than this can leave no room for the answer
            "messages": [
                ["role": "system", "content": "Translate this airport announcement, as heard by speech recognition, "
                    + "into Traditional Chinese as used in Taiwan. Keep flight numbers, gate numbers and times exactly "
                    + "as they appear. Don't add anything that isn't said. Reply with the translation only."],
                ["role": "user", "content": announcement],
            ],
        ]
        return try await ChatCompletions.post(Self.endpoint, apiKey: apiKey, body: body, service: "Muse Spark Open")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The OpenAI-style chat completions call both Meta Model API and Baseten take.
enum ChatCompletions {
    static func post(_ url: URL, apiKey: String, body: [String: Any], service: String) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: service, code: status,
                          userInfo: [NSLocalizedDescriptionKey: "\(service) \(status): \(String(decoding: data.prefix(200), as: UTF8.self))"])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = ((json?["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any]
        return message?["content"] as? String ?? ""
    }
}
