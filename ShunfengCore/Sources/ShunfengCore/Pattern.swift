import Foundation

/// Small wrapper around NSRegularExpression. Swift's own Regex has no lookbehind,
/// and the announcement rules lean on lookbehind to keep "CI100" out of "CI1000".
struct Pattern {
    let regex: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        // Patterns are fixed strings written in this file, so a failure here is a programming error.
        regex = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    func matches(in text: String) -> [NSTextCheckingResult] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    func contains(in text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// All matched substrings, in order.
    func strings(in text: String) -> [String] {
        matches(in: text).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    /// Replace every match with the closure's result. The closure gets the match's capture groups
    /// (index 0 is the whole match, missing groups are nil).
    func replace(in text: String, with transform: ([String?]) -> String) -> String {
        var result = ""
        var cursor = text.startIndex
        for match in matches(in: text) {
            guard let whole = Range(match.range, in: text) else { continue }
            let groups: [String?] = (0..<match.numberOfRanges).map { i in
                Range(match.range(at: i), in: text).map { String(text[$0]) }
            }
            result += text[cursor..<whole.lowerBound]
            result += transform(groups)
            cursor = whole.upperBound
        }
        return result + text[cursor...]
    }

    func replace(in text: String, template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
