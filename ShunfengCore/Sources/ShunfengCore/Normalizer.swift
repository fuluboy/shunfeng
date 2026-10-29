import Foundation

/// Cleans up speech-recognition output before any rule looks at it.
///
/// Muse Voice Transcribe returns Mandarin in Simplified Chinese, often hears "CI" as 此/自/子/詞,
/// spells numbers as 一百一十, and repeats words when it stumbles. Announcers also read codes
/// out letter by letter ("C-I one zero zero", "B one R"). Everything here turns that into
/// plain codes and Traditional Chinese so the rules only have to deal with one spelling.
public enum Normalizer {

    public static func normalize(_ text: String) -> String {
        spokenCodes(asrCleanup(text))
    }

    // MARK: - Speech recognition quirks

    static let simplifiedToTraditional: [Character: Character] = {
        let simplified = Array("机门后开为点时间华长荣飞东请广误迟号国维尽达柜风响发无将这陈务员澳续见谅检现")
        let traditional = Array("機門後開為點時間華長榮飛東請廣誤遲號國維儘達櫃風響發無將這陳務員澳續見諒檢現")
        return Dictionary(uniqueKeysWithValues: zip(simplified, traditional))
    }()

    /// Airline names that tell us the code. Taoyuan announcements often say the code ("CI100"), but the
    /// recognizer loses the letters; Haneda announcements never say codes at all, only names:
    /// "日本航空8261便", "Japan Airlines flight eight two six one" (heard in a real recording).
    static let airlines: [(name: String, code: String)] = [
        ("中華航空", "CI"), ("華航", "CI"), ("China Airlines", "CI"), ("チャイナエアライン", "CI"),
        ("長榮航空", "BR"), ("長榮", "BR"), ("EVA Air", "BR"), ("Eva Air", "BR"), ("エバー航空", "BR"),
        ("星宇航空", "JX"), ("新宇航空", "JX"), ("Starlux", "JX"), ("スターラックス", "JX"),
        ("國泰航空", "CX"), ("Cathay Pacific", "CX"), ("キャセイパシフィック", "CX"), ("澳門航空", "NX"),
        ("日本航空", "JL"), ("Japan Airlines", "JL"), ("JAL", "JL"),
        ("全日空", "NH"), ("全日本空輸", "NH"), ("All Nippon Airways", "NH"), ("ANA", "NH"),
        ("中國東方航空", "MU"), ("東方航空", "MU"), ("China Eastern Airlines", "MU"), ("China Eastern", "MU"),
        ("上海航空", "FM"), ("Shanghai Airlines", "FM"),
        ("中國國際航空", "CA"), ("Air China", "CA"),
        ("大韓航空", "KE"), ("Korean Air", "KE"), ("アシアナ航空", "OZ"), ("Asiana Airlines", "OZ"),
        ("新加坡航空", "SQ"), ("Singapore Airlines", "SQ"), ("ピーチ", "MM"), ("Peach", "MM"),
        ("Delta", "DL"), ("United", "UA"), ("American Airlines", "AA"),
    ]

    /// "<airline name> [flight] 8261 [便/班]" → "<airline name> JL8261". Longest names first, so
    /// "China Eastern Airlines" wins over "China Eastern". Each number takes the airline named right
    /// before it, which matters for codeshare lists ("Shanghai Airlines 896, China Eastern 8634, ...").
    static let airlineNumber: Pattern = {
        let names = airlines.map(\.name).sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        // Case-sensitive with a letter boundary, so "ANA" or "United" can't match inside other words.
        return Pattern("(?<![A-Za-z])(\(names))\\s*(?:[Ff]light\\s*)?(?:[Nn]o\\.?\\s*)?(\\d{1,4})(?!\\d)")
    }()

    /// "flight eight two six one" → "flight 8261", "gate one four one" → "gate 141".
    static let spokenDigitsAfterKeyword = Pattern(
        "\\b(flight|gate)\\s+((?:zero|oh|one|two|three|four|five|six|seven|eight|nine)(?:[\\s-]+(?:zero|oh|one|two|three|four|five|six|seven|eight|nine))*)\\b",
        caseInsensitive: true)

    /// Characters the recognizer writes when it hears the letters "C I".
    static let ciSounds = "此自子词詞四慈辭字"

    static let stutter = Pattern(#"([^\x00-\x7f]{2,6})\1+"#)
    static let ciBeforeNumber = Pattern("[\(ciSounds)](?=\\s*(?:[一二兩三四五六七八九][百千]|\\d{2,4}))")
    static let chineseNumber = Pattern("[零一二兩三四五六七八九十百千]+")
    static let chineseFlightNumber = Pattern("[零一二三四五六七八九十]{2,3}(?=\\s*[班便])")
    // Gate numbers in words: Japanese "四十七番搭乗口", Chinese "十二號登機門".
    static let chineseGateNumber = Pattern("[零一二三四五六七八九十]{1,3}(?=\\s*(?:番|號\\s*登機門))")
    static let arabicClock = Pattern(#"(上午|早上|中午|下午|晚上)?\s*(\d{1,2})\s*點\s*(?:(\d{1,2})\s*分)?"#)
    // Not after a hyphen: in "C-I100" the code is already there, spelled out.
    static let bareFlightNumber = Pattern("(?<![A-Z0-9-])(?:[\(ciSounds)]|[A-Z](?![A-Z]))?\\s*(\\d{2,4})(?=\\s*(?:班|便|飛|維持|改|前往))")

    static func asrCleanup(_ text: String) -> String {
        var t = String(text.map { simplifiedToTraditional[$0] ?? $0 })
        t = stutter.replace(in: t, template: "$1")                      // 一百一百 → 一百
        t = ciBeforeNumber.replace(in: t, template: "CI")               // 此一百 → CI一百
        t = chineseNumber.replace(in: t) { g in chineseHundreds(g[0]!) } // 一百一十 → 110
        t = chineseFlightNumber.replace(in: t) { g in String(chineseSmallNumber(g[0]!)) } // 五十七班 → 57班
        t = chineseGateNumber.replace(in: t) { g in String(chineseSmallNumber(g[0]!)) }   // 四十七番 → 47番
        t = arabicClock.replace(in: t) { g in                           // 15 點 20 分 → 15:20
            var hour = Int(g[2]!)!
            if let period = g[1], ["下午", "晚上"].contains(period), hour < 12 { hour += 12 }
            return String(format: "%02d:%02d", hour, Int(g[3] ?? "0") ?? 0)
        }
        t = spokenDigitsAfterKeyword.replace(in: t) { g in              // flight eight two six one → flight 8261
            g[1]! + " " + g[2]!.split(whereSeparator: { $0 == " " || $0 == "-" })
                .map { $0.lowercased() == "oh" ? "0" : (digitWords[$0.lowercased()] ?? "") }.joined()
        }
        let codeOf = Dictionary(airlines.map { ($0.name.lowercased(), $0.code) }, uniquingKeysWith: { a, _ in a })
        t = airlineNumber.replace(in: t) { g in                         // 日本航空8261便 → 日本航空 JL8261便
            "\(g[1]!) \(codeOf[g[1]!.lowercased()] ?? "")\(g[2]!)"
        }
        // Put the airline code back on numbers that lost it ("華航 自一百班機" → "CI100班機").
        let mentioned = airlines.compactMap { a in t.range(of: a.name).map { (pos: $0.lowerBound, code: a.code) } }
        if let first = mentioned.min(by: { $0.pos < $1.pos }) {
            t = bareFlightNumber.replace(in: t) { g in first.code + g[1]! }
        }
        return t
    }

    static let digitValue: [Character: Int] = [
        "零": 0, "〇": 0, "一": 1, "二": 2, "兩": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]

    /// 一百 → 100, 一百一十 → 110, 一千 → 1000. Only numbers containing 百 or 千 are touched,
    /// so ordinary words like 一般 stay as they are. Anything after the number is kept.
    static func chineseHundreds(_ s: String) -> String {
        guard s.contains("百") || s.contains("千") else { return s }
        let chars = Array(s)
        var i = 0, value = 0
        // "百四十一" (Japanese gate 141) has no digit before 百, which means one hundred.
        func digit(followedBy unit: Character) -> Int? {
            // Only inside a longer number, so a lone 千 (千葉) or 百 (百貨) stays a word.
            if chars.count > 1, i < chars.count, chars[i] == unit {
                i += 1
                return 1
            }
            guard i + 1 < chars.count, let d = digitValue[chars[i]], chars[i + 1] == unit else { return nil }
            i += 2
            return d
        }
        if let k = digit(followedBy: "千") { value += k * 1000 }
        if let h = digit(followedBy: "百") { value += h * 100 }
        if i < chars.count, chars[i] == "零" { i += 1 }
        if let t = digit(followedBy: "十") {
            value += t * 10
        } else if i < chars.count, chars[i] == "十" {
            value += 10
            i += 1
        }
        if i < chars.count, let u = digitValue[chars[i]] {
            value += u
            i += 1
        }
        guard i > 0 else { return s }
        return String(value) + String(chars[i...])
    }

    // MARK: - Codes read out loud

    static let digitWords = ["zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
                             "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9"]
    static let spokenToken = "(?:[A-Z]|\\d+|" + digitWords.keys.joined(separator: "|") + "|hundred)"
    static let spokenRun = Pattern("(?<![\\w-])\(spokenToken)(?:[\\s-]+\(spokenToken))+(?![\\w-])")
    static let letterHyphen = Pattern("(?<=[A-Z])-(?=[A-Z])")
    // "B 7" → "B7". Only a lone gate letter, so "CI 100" and "BR 192" (handled as flights) are left alone.
    static let spacedGate = Pattern("(?<![A-Za-z0-9])([A-D]) (\\d{1,2}R?)(?!\\d)")
    // The recognizer sometimes puts a space in between ("C 三"), so one space is swallowed too.
    static let chineseDigitsAfterCode = Pattern("(?<=[A-Z0-9]) ?[零〇一二三四五六七八九]+")
    static let chineseClock = Pattern("(上午|早上|中午|下午|晚上)?([零一二兩三四五六七八九十]{1,3})點(?:([零一二三四五六七八九十]{1,3})分)?")

    static func spokenCodes(_ text: String) -> String {
        // "C I one zero zero" → "CI100", "B one R" → "B1R". Only runs that mix letters and numbers,
        // so plain English sentences are left alone. Must run before C-I → CI.
        var t = spokenRun.replace(in: text) { g in
            let run = g[0]!
            let hasLetter = run.range(of: "[A-Z]", options: .regularExpression) != nil
            let hasNumber = run.range(of: "\\d|hundred|" + digitWords.keys.joined(separator: "|"),
                                      options: .regularExpression) != nil
            guard hasLetter && hasNumber else { return run }
            return run.split(whereSeparator: { $0 == " " || $0 == "-" }).map { token -> String in
                let lower = token.lowercased()
                if lower == "hundred" { return "00" }
                return digitWords[lower] ?? String(token)
            }.joined()
        }
        t = letterHyphen.replace(in: t, template: "")                   // C-I → CI
        t = spacedGate.replace(in: t, template: "$1$2")                 // B 7 → B7
        t = chineseDigitsAfterCode.replace(in: t) { g in               // B七 → B7, C 三 → C3
            g[0]!.compactMap { digitValue[$0].map(String.init) }.joined()
        }
        t = chineseClock.replace(in: t) { g in                          // 下午三點四十分 → 15:40
            var hour = chineseSmallNumber(g[2]!)
            if let period = g[1], ["下午", "晚上"].contains(period), hour < 12 { hour += 12 }
            return String(format: "%02d:%02d", hour, g[3].map(chineseSmallNumber) ?? 0)
        }
        return t
    }

    /// 十五 → 15, 二十 → 20, 五十七 → 57, 五七 → 57 (clock times and flight numbers without 百).
    static func chineseSmallNumber(_ s: String) -> Int {
        if let ten = s.firstIndex(of: "十") {
            let tens = s[..<ten].first.flatMap { digitValue[$0] } ?? 1
            let ones = s[s.index(after: ten)...].first.flatMap { digitValue[$0] } ?? 0
            return tens * 10 + ones
        }
        return Int(s.compactMap { digitValue[$0].map(String.init) }.joined()) ?? 0
    }
}
