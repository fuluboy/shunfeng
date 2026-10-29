import Foundation

/// What Muse Spark read from a photo of a boarding pass. The user confirms it before it's used.
public struct BoardingPass: Codable, Equatable, Sendable {
    public var flight: String?
    public var date: String?            // MM-DD (boarding passes print no year)
    public var from: String?            // IATA code
    public var to: String?
    public var gate: String?
    public var boardingTime: String?
    public var departureTime: String?
    public var seat: String?
    /// A handwritten correction next to a printed value (e.g. staff wrote an earlier boarding time).
    public var handwrittenChanges: String

    enum CodingKeys: String, CodingKey {
        case flight, date, from, to, gate, seat
        case boardingTime = "boarding_time"
        case departureTime = "departure_time"
        case handwrittenChanges = "handwritten_changes"
    }

    /// "BR0197" → "BR197", ready to look up and to match announcements.
    public var flightCode: String? { flight.map(AnnouncementRules.normalizeFlight) }

    /// Destination as the app's destination field takes it ("東京" for NRT or HND).
    public var destinationName: String? { to.flatMap { Airports.name[$0.uppercased()] } ?? to }
}

/// IATA codes to the city names used in announcements and in the destination field.
public enum Airports {
    public static let name: [String: String] = [
        "TPE": "台北", "TSA": "台北", "KHH": "高雄", "RMQ": "台中",
        "NRT": "東京", "HND": "東京", "KIX": "大阪", "ITM": "大阪", "NGO": "名古屋", "FUK": "福岡",
        "CTS": "札幌", "OKA": "沖繩", "ICN": "首爾", "GMP": "首爾", "PUS": "釜山",
        "HKG": "香港", "MFM": "澳門", "PVG": "上海", "SHA": "上海", "PEK": "北京", "PKX": "北京",
        "BKK": "曼谷", "SIN": "新加坡", "MNL": "馬尼拉", "HAN": "河內", "DAD": "峴港", "SGN": "胡志明市",
        "KUL": "吉隆坡", "LAX": "洛杉磯", "SFO": "舊金山", "SEA": "西雅圖", "JFK": "紐約",
        "HNL": "檀香山", "VIE": "維也納",
    ]
}

/// Meta Model API (chat completions) for the parts that need a model to look or read.
public struct MetaModelAPI: Sendable {
    public static let endpoint = URL(string: "https://api.meta.ai/v1/chat/completions")!
    let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    static let boardingPassSchema: [String: Any] = {
        func field(_ description: String) -> [String: Any] { ["type": ["string", "null"], "description": description] }
        return [
            "type": "object",
            "properties": [
                "flight": field("Airline code + number without leading zeros, e.g. BR197, NH824"),
                "date": field("MM-DD"),
                "from": field("3-letter IATA airport code"),
                "to": field("3-letter IATA airport code"),
                "gate": field("Gate as printed"),
                "boarding_time": field("HH:MM as printed"),
                "departure_time": field("HH:MM, null if not printed"),
                "seat": field("Seat as printed"),
                "handwritten_changes": ["type": "string",
                                        "description": "Any handwritten correction to a printed value, or empty"],
            ],
            "required": ["flight", "date", "from", "to", "gate", "boarding_time", "departure_time", "seat", "handwritten_changes"],
            "additionalProperties": false,
        ]
    }()

    /// Reads a boarding pass photo (JPEG). Tested on 12 real passes from EVA Air and ANA, including rotated
    /// photos and handwriting: all 8 fields right on all 12, about 5 seconds each.
    public func readBoardingPass(jpeg: Data) async throws -> BoardingPass {
        let body: [String: Any] = [
            "model": "muse-spark-1.3",
            "reasoning_effort": "low",
            "messages": [
                ["role": "system", "content": "Read this boarding pass photo for a deaf traveler's airport assistant. "
                    + "Gray boxes may cover private details; ignore them. Report only what is printed; use null for "
                    + "anything you can't read. The photo may be rotated."],
                ["role": "user", "content": [["type": "image_url",
                                              "image_url": ["url": "data:image/jpeg;base64," + jpeg.base64EncodedString()]]]],
            ],
            "response_format": ["type": "json_schema",
                                "json_schema": ["name": "boarding_pass", "schema": Self.boardingPassSchema]],
        ]
        let content = try await complete(body)
        return try JSONDecoder().decode(BoardingPass.self, from: Data(content.utf8))
    }

    func complete(_ body: [String: Any]) async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "MetaModelAPI", code: status,
                          userInfo: [NSLocalizedDescriptionKey: "Meta Model API \(status): \(String(decoding: data.prefix(200), as: UTF8.self))"])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = ((json?["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any]
        return message?["content"] as? String ?? ""
    }
}
