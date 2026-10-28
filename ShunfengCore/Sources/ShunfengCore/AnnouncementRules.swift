import Foundation

/// What an announcement is about.
public enum AnnouncementEvent: String, Codable, CaseIterable, Sendable {
    case gateChange = "gate_change"
    case delay
    case timeChange = "time_change"   // departure moved earlier
    case boarding
    case finalCall = "final_call"
    case cancel
    case nameCall = "name_call"
    case info
}

/// Everything the rules could read from one announcement, about one flight.
public struct AnnouncementReading: Equatable, Sendable {
    /// The flight this reading is about: the user's flight if it was mentioned, otherwise the first flight heard.
    public var flight: String?
    /// nil means no keyword matched; the app should ask Muse Spark or mark the alert as uncertain.
    public var event: AnnouncementEvent?
    /// New or current gate. Old gates ("changed from A5") and corrected ones are left out.
    public var gate: String?
    /// false when several gates were heard and the rules had to pick one.
    public var gateIsCertain: Bool
    /// New time as HH:mm (24-hour).
    public var time: String?
    /// Destinations named in this flight's part of the announcement (canonical names, e.g. "Tokyo").
    public var destinations: Set<String> = []
    /// The normalized text the rules worked on.
    public var normalizedText: String

    public var mentionsFlight: Bool { flight != nil }

    /// Whether this announcement is about the user's flight. A matching flight number with a
    /// different destination is not trusted: speech recognition can drop a digit (CI1000 → CI100).
    public func match(for user: UserFlight) -> FlightMatch {
        guard flight == AnnouncementRules.normalizeFlight(user.code) else { return .notMine }
        guard let mine = user.destination.flatMap(Destinations.canonical), !destinations.isEmpty,
              !destinations.contains(mine) else { return .mine }
        return .destinationConflict(heard: destinations.sorted())
    }
}

/// The flight the user is taking.
public struct UserFlight: Equatable, Sendable {
    public var code: String
    public var destination: String?

    public init(code: String, destination: String? = nil) {
        self.code = code
        self.destination = destination
    }
}

public enum FlightMatch: Equatable, Sendable {
    case mine
    /// Flight number matched but the announcement named another destination. Worth a gentle
    /// "might be about you, please check" instead of a full alert.
    case destinationConflict(heard: [String])
    case notMine
}

/// Rule-based reading of airport announcements.
///
/// Speech recognition stays neutral (it is never told the user's flight, which made it hear
/// CI110 as CI100). Deciding "is this my flight" happens here, where every value has to be
/// found in the text itself instead of guessed.
public enum AnnouncementRules {

    public static func read(_ transcript: String, myFlight: String) -> AnnouncementReading {
        let text = Normalizer.normalize(transcript)
        let flight = targetFlight(in: text, myFlight: normalizeFlight(myFlight))
        let context = flight.map { self.context(for: $0, in: text) } ?? text
        let (gate, certain) = extractGate(from: context)
        return AnnouncementReading(
            flight: flight,
            event: classifyEvent(text: text, context: flight == nil ? nil : context),
            gate: gate,
            gateIsCertain: certain,
            time: extractTime(from: context),
            destinations: Destinations.heard(in: context),
            normalizedText: text
        )
    }

    // MARK: - Flights

    // Airline codes: two letters take 1-4 digits (BR5); mixed codes (7C, B7) need 3-4 digits so a gate
    // like D14 is not read as a flight. Recognizers often write "CI 100", so one space is allowed.
    static let flightPattern = Pattern("(?<![A-Z0-9])(?:[A-Z]{2} ?\\d{1,4}|(?:[A-Z]\\d|\\d[A-Z])\\d{3,4})(?!\\d)")

    /// "CI 0100", "ci100" → "CI100".
    public static func normalizeFlight(_ code: String) -> String {
        let compact = code.uppercased().filter { !$0.isWhitespace }
        guard compact.count > 2 else { return compact }
        let airline = compact.prefix(2)
        let digits = compact.dropFirst(2).drop(while: { $0 == "0" })
        return String(airline) + (digits.isEmpty ? "0" : String(digits))
    }

    public static func flights(in text: String) -> [String] {
        flightPattern.strings(in: text).map(normalizeFlight)
    }

    static func targetFlight(in text: String, myFlight: String) -> String? {
        let found = flights(in: text)
        return found.contains(myFlight) ? myFlight : found.first
    }

    // Split on punctuation, but not on the dot inside "3.20 PM".
    static let clausePattern = Pattern("(?:[^。，,.;；！!？?：]|(?<=\\d)\\.(?=\\d))+")

    /// The clauses that talk about `flight`: start where it is mentioned, pause at a clause that only
    /// names other flights, pick up again when it is mentioned again. Recognizers add stray commas,
    /// so "CI100與，CI110班機旅客請注意，CI100改至B7" still keeps the B7 clause.
    static func context(for flight: String, in text: String) -> String {
        var kept: [String] = []
        var active = false
        for clause in clausePattern.strings(in: text) {
            let named = flights(in: clause)
            if named.contains(flight) {
                active = true
            } else if !named.isEmpty {
                active = false
            }
            if active { kept.append(clause) }
        }
        return kept.joined(separator: "，")
    }

    // MARK: - Gate and time

    /// Taoyuan-style gates: a letter and digits ("A5", "B1R").
    static let gatePattern = Pattern("(?<![A-Z0-9])[A-D]\\d{1,2}R?(?![A-Z0-9])")
    /// Number-only gates, which need a word around them to be told apart from other numbers:
    /// Haneda "141番ゲート", "47番搭乗口", "gate 141", and Chinese "141號登機門".
    static let numberedGatePattern = Pattern("[Gg]ate\\s+(\\d{1,3})(?!\\d)|(?<!\\d)(\\d{1,3})\\s*(?:番\\s*)?(?:ゲート|搭乗口)|(?<!\\d)(\\d{1,3})\\s*號\\s*登機門")

    /// All gates named in the text, in the order they are said.
    static func gates(in text: String) -> [String] {
        let lettered = gatePattern.matches(in: text).compactMap { m in
            Range(m.range, in: text).map { (pos: $0.lowerBound, gate: String(text[$0])) }
        }
        let numbered = numberedGatePattern.matches(in: text).compactMap { m -> (pos: String.Index, gate: String)? in
            for i in 1...3 {
                if let r = Range(m.range(at: i), in: text) { return (r.lowerBound, String(text[r])) }
            }
            return nil
        }
        return (lettered + numbered).sorted { $0.pos < $1.pos }.map(\.gate)
    }

    /// The new or current gate. Gates named as the old one ("由A5改", "from A5 to"), negated ("not B7")
    /// or corrected ("B7的廣播有誤") are dropped. If several remain, the last one wins and is marked uncertain.
    static func extractGate(from context: String) -> (String?, Bool) {
        let candidates = gates(in: context)
        let dropped = Set(candidates.filter { gate in
            let g = NSRegularExpression.escapedPattern(for: gate)
            return Pattern("由\\s*\(g)\\s*(?:更)?改|from\\s+(?:gate\\s+)?\(g)\\s+to|\(g)\\s+(?:has\\s+)?(?:been\\s+)?changed\\s+to|not\\s+(?:gate\\s+)?\(g)|\(g)[^，。,.]*有誤",
                           caseInsensitive: true).contains(in: context)
        })
        var remaining: [String] = []
        for gate in candidates where !dropped.contains(gate) && !remaining.contains(gate) {
            remaining.append(gate)
        }
        switch remaining.count {
        case 0: return (nil, true)
        case 1: return (remaining[0], true)
        default: return (remaining.last, false)
        }
    }

    // Recognizers write 3:20 PM as "3.20 PM" or "10 50 AM", so the separator can be ":", "." or a space.
    // (ICU reads a set starting with "[:" as a POSIX class, hence "[.\s:]".)
    static let timePattern = Pattern("(?<![\\d:])(\\d{1,2})(?:[.\\s:](\\d{2}))?\\s*([AaPp])\\.?[Mm]\\b|(?<![\\d:])(\\d{1,2}):(\\d{2})(?!\\d)")

    static func extractTime(from context: String) -> String? {
        guard let m = timePattern.matches(in: context).first else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: context).map { String(context[$0]) } }
        if let meridiem = group(3)?.lowercased(), var hour = group(1).flatMap(Int.init) {
            if meridiem == "p" && hour < 12 { hour += 12 }
            if meridiem == "a" && hour == 12 { hour = 0 }
            return String(format: "%02d:%@", hour, group(2) ?? "00")
        }
        guard let hour = group(4).flatMap(Int.init), let minute = group(5) else { return nil }
        return String(format: "%02d:%@", hour, minute)
    }

    // MARK: - Event

    // Checked in this order. Cancel matters most; name calls, final calls, earlier departures and delays
    // come before gate changes because those announcements usually mention a gate too.
    // Japanese wording comes from Haneda: 最終案内 (final call), 欠航 (cancelled), 〇〇様 (paging).
    // 皆様 / お客様 ("everyone", "passengers") are in almost every Japanese announcement, so a name call
    // needs 様 without them in front.
    static let eventKeywords: [(AnnouncementEvent, Pattern)] = [
        (.cancel, Pattern("取消|欠航|運休|cancel", caseInsensitive: true)),
        (.nameCall, Pattern("先生|小姐|女士|(?<![皆客])様|お呼び出し|passenger\\s+[A-Z][a-z]+(?:\\s+[A-Z][\\w-]+)?\\s+(?:traveling|travelling|on|booked)|please\\s+report\\s+to")),
        (.finalCall, Pattern("最後登機|最後一次登機|最終案内|最終のご案内|final\\s+(?:boarding\\s+)?call|final\\s+boarding|last\\s+call|proceed\\s+(?:immediately\\s+)?to\\s+gate\\s+\\S+\\s+immediately", caseInsensitive: true)),
        (.timeChange, Pattern("提前|提早|繰り上げ|早まり|moved\\s+(?:up|earlier)|(?:depart|leave)\\s+earlier|earlier\\s+than", caseInsensitive: true)),
        (.delay, Pattern("延後|延誤|延遲|遅れ|遅延|delay", caseInsensitive: true)),
        (.boarding, Pattern("開始登機|現在登機|搭乗(?:を)?開始|ご搭乗いただけます|now\\s+boarding|(?:may|can)\\s+(?:now\\s+)?board|begin\\s+boarding", caseInsensitive: true)),
        (.gateChange, Pattern("登機門(?:由\\S+?)?(?:更改|改|調整)|改至|改到|改回|改為|仍為|(?:搭乗口|ゲート)(?:が|の)?変更|gate\\s+change|new\\s+gate|gate\\s+(?:has\\s+)?(?:been\\s+)?changed|changed\\s+to|now\\s+departing\\s+from\\s+gate|not\\s+gate|更正|correction", caseInsensitive: true)),
    ]

    /// Looks at the flight's own clauses first, then the whole announcement (batch cancellations put
    /// "以下班機取消" before the list of flights). No keyword and no flight means general info.
    /// nil means "not sure"; the caller decides whether to ask Muse Spark.
    static func classifyEvent(text: String, context: String?) -> AnnouncementEvent? {
        for part in [context, text].compactMap({ $0 }) {
            if let hit = eventKeywords.first(where: { $0.1.contains(in: part) }) {
                return hit.0
            }
        }
        return flights(in: text).isEmpty ? .info : nil
    }
}
