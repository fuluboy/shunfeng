import Foundation

/// Destination names heard in announcements, used as a second check on the flight number.
///
/// Live transcription once turned "CI1000 to Hong Kong" into "CI 100". The flight number alone said
/// "your flight", the destination said otherwise. When the two disagree, the app should not raise a
/// full alert; it should say it heard something that might be about you and ask you to check.
public enum Destinations {

    /// Canonical name → ways it is said in Mandarin and English announcements.
    static let aliases: [String: [String]] = [
        "Tokyo": ["東京", "成田", "羽田", "Tokyo", "Narita", "Haneda"],
        "Osaka": ["大阪", "關西", "Osaka", "Kansai"],
        "Nagoya": ["名古屋", "Nagoya"],
        "Fukuoka": ["福岡", "Fukuoka"],
        "Sapporo": ["札幌", "Sapporo"],
        "Okinawa": ["沖繩", "那霸", "Okinawa", "Naha"],
        "Seoul": ["首爾", "仁川", "金浦", "ソウル", "Seoul", "Incheon", "Gimpo"],
        "Busan": ["釜山", "Busan"],
        "Hong Kong": ["香港", "Hong Kong"],
        "Macau": ["澳門(?!航空)", "Macau"],
        "Shanghai": ["上海", "浦東", "Shanghai", "Pudong"],
        "Beijing": ["北京", "Beijing"],
        "Taipei": ["台北", "臺北", "松山", "桃園", "Taipei", "Songshan", "Taoyuan"],
        "Honolulu": ["檀香山", "ホノルル", "Honolulu"],
        "Bangkok": ["曼谷", "Bangkok"],
        "Singapore": ["新加坡", "Singapore"],
        "Manila": ["馬尼拉", "Manila"],
        "Hanoi": ["河內", "Hanoi"],
        "Da Nang": ["峴港", "Da Nang", "Danang"],
        "Kuala Lumpur": ["吉隆坡", "Kuala Lumpur"],
        "Los Angeles": ["洛杉磯", "Los Angeles"],
        "San Francisco": ["舊金山", "San Francisco"],
        "Seattle": ["西雅圖", "Seattle"],
        "New York": ["紐約", "New York"],
        "Vienna": ["維也納", "Vienna"],
    ]

    static let patterns: [(name: String, pattern: Pattern)] = aliases.map { name, words in
        (name, Pattern(words.joined(separator: "|"), caseInsensitive: true))
    }

    /// Canonical destinations named in the text.
    public static func heard(in text: String) -> Set<String> {
        Set(patterns.filter { $0.pattern.contains(in: text) }.map(\.name))
    }

    /// Canonical name for a destination the user typed or ADIP returned ("東京", "Tokyo Narita").
    public static func canonical(_ name: String) -> String? {
        patterns.first { $0.pattern.contains(in: name) }?.name
    }
}
