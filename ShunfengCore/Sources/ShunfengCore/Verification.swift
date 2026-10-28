import Foundation

/// What the live flight data says about something heard in an announcement.
///
/// Announcements usually come before the data is updated (the data refreshes every 5 minutes), so a
/// disagreement is reported, never resolved by quietly picking one side.
public struct Verification: Equatable, Sendable {

    public enum Gate: Equatable, Sendable {
        /// Heard and data agree.
        case agrees(String)
        /// The gate wasn't heard (Mandarin transcripts often drop the digits); the data has one.
        case fromData(String)
        /// Heard one gate, data says another.
        case disagrees(heard: String, data: String)
        /// Nothing to compare.
        case unknown
    }

    public enum Status: Equatable, Sendable {
        case agrees
        /// The data doesn't show it (yet): e.g. a cancellation announced while the data still says 準時.
        case notYetInData(dataStatus: String)
        /// Not something the data can confirm (boarding, name calls...).
        case notApplicable
    }

    public var gate: Gate
    public var status: Status

    /// The gate to show: the heard one, or the data's when nothing was heard.
    public var bestGate: String? {
        switch gate {
        case .agrees(let g), .fromData(let g): return g
        case .disagrees(let heard, _): return heard
        case .unknown: return nil
        }
    }

    public static func check(_ reading: AnnouncementReading, against flight: ADIPFlight?) -> Verification {
        guard let flight else { return Verification(gate: .unknown, status: .notApplicable) }
        return Verification(gate: gate(heard: reading.gate, data: flight.gate),
                            status: status(reading.event, flight))
    }

    static func gate(heard: String?, data: String?) -> Gate {
        switch (heard, data) {
        case let (h?, d?): return h == d ? .agrees(d) : .disagrees(heard: h, data: d)
        case let (nil, d?): return .fromData(d)
        default: return .unknown
        }
    }

    static func status(_ event: AnnouncementEvent?, _ flight: ADIPFlight) -> Status {
        switch event {
        case .cancel:
            return flight.status == "取消" ? .agrees : .notYetInData(dataStatus: flight.status)
        case .delay:
            return ["改時", "延遲"].contains(flight.status) || minutesLate(flight) >= 15
                ? .agrees : .notYetInData(dataStatus: flight.status)
        case .timeChange:
            return minutesLate(flight) <= -15 ? .agrees : .notYetInData(dataStatus: flight.status)
        default:
            return .notApplicable
        }
    }

    /// Estimated minus scheduled time, in minutes (negative when moved earlier).
    static func minutesLate(_ flight: ADIPFlight) -> Int {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd HH:mm"
        format.timeZone = TimeZone(identifier: "Asia/Taipei")
        guard let s = format.date(from: flight.scheduled), let e = format.date(from: flight.estimated) else { return 0 }
        return Int(e.timeIntervalSince(s) / 60)
    }

    // MARK: - Changes in the data itself

    /// A change between two fetches of the user's flight that an announcement may have carried
    /// (or that the microphone missed): a new gate or a new status.
    public enum DataChange: Equatable, Sendable {
        case gate(from: String?, to: String)
        case status(from: String, to: String)
    }

    public static func changes(from old: ADIPFlight, to new: ADIPFlight) -> [DataChange] {
        var out: [DataChange] = []
        if let gate = new.gate, gate != old.gate { out.append(.gate(from: old.gate, to: gate)) }
        // Only statuses a traveler must act on; 出發/已到 just mean the flight left or landed.
        if new.status != old.status, ["改時", "延遲", "取消"].contains(new.status) {
            out.append(.status(from: old.status, to: new.status))
        }
        return out
    }
}
