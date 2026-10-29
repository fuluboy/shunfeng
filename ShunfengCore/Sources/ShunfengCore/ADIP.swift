import Foundation

/// One row of Taoyuan Airport's live flight data (ADIP open data, updated every 5 minutes).
public struct ADIPFlight: Equatable, Sendable {
    public enum Kind: String, Sendable { case departure = "D", arrival = "A" }

    public var code: String            // "CI100"
    public var kind: Kind
    public var airline: String         // 中華航空
    public var terminal: String        // T2
    public var gate: String?           // nil when not assigned (cancelled flights usually have none)
    public var scheduled: String       // "2026-10-28 09:30"
    public var estimated: String       // "2026-10-28 09:29"
    public var placeZh: String         // 東京
    public var placeEn: String         // Tokyo
    public var status: String          // 準時 / 改時 / 延遲 / 取消 / 出發 / 已到
    public var progress: String?       // 開始登機 / 最後登機 / 登機結束 / 已飛 ...
    /// The plane has left the gate (or is in the air).
    public var hasDeparted: Bool { kind == .departure && (status == "出發" || progress == "已飛") }
    /// The airline flying the plane has an aircraft type; codeshare rows leave it empty.
    public var isOperating: Bool
    /// Other flight numbers on the same plane. Empty when it can't be told for sure.
    public var codeshares: [String] = []

    var carousel = ""
    var counter = ""
}

/// Taoyuan Airport's live flight data. Announcements often come before the data changes, so the data
/// confirms or fills in what was heard; it never silently overrides it.
public enum ADIP {
    public static let url = URL(string: "https://odp.taoyuan-airport.com/dataset/2023081816?format=csv")!

    public static func fetch() async throws -> [ADIPFlight] {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        return parse(data)
    }

    /// Parses the CSV. Fields are quoted; flight numbers come with leading spaces (" 310"); the file
    /// sometimes starts with a byte-order mark and sometimes doesn't.
    public static func parse(_ data: Data) -> [ADIPFlight] {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let rows = csvRows(text)
        guard let header = rows.first else { return [] }
        let column = Dictionary(header.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        func field(_ row: [String], _ name: String) -> String {
            guard let i = column[name], i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespaces)
        }
        var flights: [ADIPFlight] = rows.dropFirst().compactMap { row in
            guard let kind = ADIPFlight.Kind(rawValue: field(row, "種類")) else { return nil }
            let gate = field(row, "機門")
            let progress = field(row, "航班動態中文")
            return ADIPFlight(
                code: AnnouncementRules.normalizeFlight(field(row, "航空公司代碼") + field(row, "班次")),
                kind: kind,
                airline: field(row, "航空公司中文"),
                terminal: field(row, "航廈"),
                gate: gate.isEmpty ? nil : gate,
                scheduled: field(row, "表訂日期") + " " + field(row, "表訂時間").prefix(5),
                estimated: field(row, "預計日期") + " " + field(row, "預計時間").prefix(5),
                placeZh: field(row, "往來地點中文"),
                placeEn: field(row, "往來地點英文"),
                status: field(row, "航班狀態"),
                progress: progress.isEmpty ? nil : progress,
                isOperating: !field(row, "機型").isEmpty,
                carousel: field(row, "行李轉盤"),
                counter: field(row, "報到櫃台")
            )
        }
        linkCodeshares(&flights)
        return flights
    }

    /// The user's flight. Departures first: the app is for people waiting to fly out.
    public static func find(_ code: String, in flights: [ADIPFlight]) -> ADIPFlight? {
        let code = AnnouncementRules.normalizeFlight(code)
        let matches = flights.filter { $0.code == code }
        return matches.first { $0.kind == .departure } ?? matches.first
    }

    // MARK: - Codeshares

    /// Rows for the same plane share kind, time, place, gate, terminal, carousel and counter. Cancelled
    /// flights have no gate, so without terminal/carousel/counter different planes leaving at the same
    /// time for the same city got merged (seen in a typhoon-day snapshot). A group with two operating
    /// airlines is still ambiguous, and then no codeshares are claimed at all.
    static func linkCodeshares(_ flights: inout [ADIPFlight]) {
        struct Key: Hashable { let parts: [String] }
        var groups: [Key: [Int]] = [:]
        for (i, f) in flights.enumerated() {
            let key = Key(parts: [f.kind.rawValue, f.scheduled, f.placeEn, f.gate ?? "", f.terminal, f.carousel, f.counter])
            groups[key, default: []].append(i)
        }
        for members in groups.values where members.count > 1 {
            guard members.filter({ flights[$0].isOperating }).count == 1 else { continue }
            let codes = members.map { flights[$0].code }
            for i in members {
                flights[i].codeshares = codes.filter { $0 != flights[i].code }
            }
        }
    }

    // MARK: - CSV

    public static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = text.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? chars.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    let next = chars.next()
                    if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                } else {
                    field.append(c)
                }
                continue
            }
            switch c {
            case "\"": quoted = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n", "\r":
                row.append(field); field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            default: field.append(c)
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}
