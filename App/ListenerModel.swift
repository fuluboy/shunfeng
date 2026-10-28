import AVFoundation
import Foundation
import ShunfengCore
import UIKit
import UserNotifications

/// How sure Shunfeng is that an announcement is about the user's flight.
enum Certainty {
    /// Flight and destination agree. Full alert.
    case sure
    /// Something points at the user's flight but not everything agrees. Gentle tap, "please check".
    case maybe
    /// Someone else's flight. Shown in the log only.
    case notYours
}

/// One announcement as heard and read.
struct Heard: Identifiable {
    let id = UUID()
    let time: Date
    var original: String
    var reading: AnnouncementReading
    let certainty: Certainty
    let note: String?
    /// How many times this same news has been heard (Mandarin and English versions agree).
    var confirmations = 1
    /// The user tapped "我知道了".
    var acknowledged = false
    /// A later version of the same news named this other gate (Japanese said 141, English only "one").
    var conflictingGate: String?
}

@MainActor
final class ListenerModel: ObservableObject {
    enum State: Equatable {
        case idle, connecting, listening
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var level: Float = 0
    @Published var partial = ""
    @Published var heard: [Heard] = []
    @Published var flightCode: String {
        didSet {
            // The text field writes the same value back when it loses focus (e.g. when a button is tapped),
            // which cleared "at the gate" in the phone test. Only a real change of flight counts.
            guard flightCode != oldValue else { return }
            UserDefaults.standard.set(flightCode, forKey: "flightCode")
            atGate = false
        }
    }
    /// The user said they are already at the gate: boarding calls are then logged quietly instead of
    /// repeating, so the last minutes before boarding aren't full of buzzing. A gate change, delay or
    /// cancellation clears it, because then they may need to move.
    @Published var atGate = false
    @Published var destination: String {
        didSet { UserDefaults.standard.set(destination, forKey: "destination") }
    }

    /// The newest sure news about the user's flight: the big card. A later "maybe" must not push it away.
    var latestSure: Heard? { heard.first { $0.certainty == .sure } }
    /// A "maybe" newer than the latest sure news, shown as a second, smaller card.
    var latestMaybe: Heard? {
        guard let maybe = heard.first(where: { $0.certainty == .maybe }) else { return nil }
        return maybe.time > (latestSure?.time ?? .distantPast) ? maybe : nil
    }

    private let audio = AudioCapture()
    private let haptics = Haptics()
    private var transcriber: RealtimeTranscriber?
    private var sender: Task<Void, Never>?
    private var chunks: AsyncStream<Data>.Continuation?

    init() {
        flightCode = UserDefaults.standard.string(forKey: "flightCode") ?? ""
        destination = UserDefaults.standard.string(forKey: "destination") ?? ""
        NotificationCenter.default.addObserver(forName: UrgentAnswer.notification, object: nil, queue: .main) { [weak self] note in
            guard let answer = note.object as? UrgentAnswer else { return }
            let id = (note.userInfo?["heardID"] as? String).flatMap(UUID.init)
            MainActor.assumeIsolated { self?.answer(answer, heardID: id) }
        }
    }

    /// From the buttons on an urgent notification or on the alert card.
    func answer(_ answer: UrgentAnswer, heardID: UUID?) {
        cancelUrgentRepeats()
        if answer == .atGate { atGate = true }
        if let i = heard.firstIndex(where: { $0.id == heardID }) { heard[i].acknowledged = true }
        EventLog.write("urgent_answer", ["answer": answer.rawValue])
    }

    var user: UserFlight {
        UserFlight(code: flightCode, destination: destination.isEmpty ? nil : destination)
    }

    // MARK: - Listening

    func start() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "MetaAPIKey") as? String, !key.isEmpty, !key.hasPrefix("$(") else {
            state = .failed("這個版本沒有 API key，請用設定好 META_API_KEY 的環境重新建置。")
            return
        }
        state = .connecting
        EventLog.write("start", ["flight": flightCode, "destination": destination])
        Task {
            // Ask for permissions before opening the stream. The server drops a stream whose audio falls
            // behind real time, and a permission dialog would stall the audio for as long as it is open.
            guard await AVAudioApplication.requestRecordPermission() else {
                EventLog.write("mic_denied")
                state = .failed("需要麥克風權限才能聽廣播。請到「設定 → 隱私權與安全性 → 麥克風」打開 Shunfeng。")
                return
            }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            guard state == .connecting else { return }   // the user pressed stop meanwhile
            connect(apiKey: key)
        }
    }

    private func connect(apiKey key: String) {
        let transcriber = RealtimeTranscriber(apiKey: key)
        self.transcriber = transcriber
        // One sender task keeps audio chunks in order.
        let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(200))
        chunks = continuation
        sender = Task {
            var bytes = 0
            for await chunk in stream {
                try? await transcriber.send(pcm: chunk)
                bytes += chunk.count
                // About every 10 seconds of audio, note that audio is still flowing (and in which app state).
                if bytes / 320_000 != (bytes - chunk.count) / 320_000 {
                    EventLog.write("audio_sent", ["seconds": bytes / 32_000, "level": Double(self.level)])
                }
            }
        }
        EventLog.write("connect")

        Task { [weak self] in
            do {
                try await transcriber.start { event in
                    // Ignore late events from a connection that was already replaced.
                    Task { @MainActor in
                        if self?.transcriber === transcriber { self?.handle(event) }
                    }
                }
                try self?.audio.start(
                    onChunk: { continuation.yield($0) },
                    onLevel: { value in Task { @MainActor in self?.level = value } }
                )
            } catch {
                EventLog.write("start_failed", ["error": error.localizedDescription])
                self?.state = .failed("無法開始收音：\(error.localizedDescription)")
                self?.stop()
            }
        }
    }

    /// Called by the stop button: also forgets reconnect history.
    func userStop() {
        reconnects = []
        stop()
        state = .idle
    }

    func stop() {
        audio.stop()
        chunks?.finish()
        sender?.cancel()
        transcriber?.cancel()
        transcriber = nil
        if case .failed = state {} else { state = .idle }
        level = 0
        partial = ""
    }

    private func handle(_ event: RealtimeTranscriber.Event) {
        switch event {
        case .sessionStarted(let id):
            EventLog.write("session_started", ["session": id])
            state = .listening
        case .partial(let text):
            partial = text
        case .turnComplete(let turn, let text):
            partial = ""
            // Every turn goes in the log, including general info the app ignores, so real-airport
            // recordings can be checked by hand against what was actually announced.
            EventLog.write("turn", ["turn": turn, "text": text])
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { break }
            // The recognizer can split one announcement into turns: at Haneda "日本航空8261便…最終案内" came
            // first and "百四十一番ゲート…" a few seconds later. A turn that names no flight, right after one
            // that did, belongs to it.
            if let last = lastTurn, Date().timeIntervalSince(last.at) < 8,
               AnnouncementRules.flights(in: Normalizer.normalize(text)).isEmpty,
               !AnnouncementRules.flights(in: Normalizer.normalize(last.text)).isEmpty {
                let combined = last.text + " " + text
                lastTurn = (combined, Date())
                merge(combined)
            } else if followUp(text) {
                lastTurn = (text, Date())
            } else {
                lastTurn = (text, Date())
                take(text)
            }
        case .error(let message):
            // Usually the audio fell behind real time (a call, a Siri prompt, a network hiccup).
            // Reconnect instead of making the user notice and press start again.
            lastError = message
            EventLog.write("stream_error", ["message": message])
            reconnect()
        case .closed:
            EventLog.write("stream_closed", ["state": "\(state)"])
            // Sessions end after 60 minutes or on network trouble; keep listening if the user didn't stop.
            if state == .listening || state == .connecting { reconnect() }
        case .speechStarted:
            break
        }
    }

    private var lastTurn: (text: String, at: Date)?

    /// A flight-less announcement repeating recent news ("passengers on this flight…" after a Japanese
    /// final call) counts as hearing it again. A different gate is flagged, not taken: the card says the
    /// two versions disagree and asks the user to check the board.
    private func followUp(_ text: String) -> Bool {
        guard let i = heard.firstIndex(where: { $0.certainty != .notYours && Date().timeIntervalSince($0.time) < 90 }),
              case .confirms(let otherGate) = AnnouncementRules.followUp(text, to: heard[i].reading, user: user) else {
            return false
        }
        heard[i].confirmations += 1
        EventLog.write("follow_up", ["text": text, "confirmations": heard[i].confirmations, "conflicting_gate": otherGate ?? ""])
        if let otherGate, heard[i].conflictingGate == nil {
            heard[i].conflictingGate = otherGate
            heard[i].reading.gateIsCertain = false
            haptics.play(.maybe)
            notify(title: "登機門不確定，請看大螢幕",
                   body: "前後兩次廣播聽到不同的登機門（\(heard[i].reading.gate ?? "?") 和 \(otherGate)）。",
                   heardID: heard[i].id)
        } else if UIApplication.shared.applicationState != .active {
            alert(heard[i], repeatCount: heard[i].confirmations)
        }
        return true
    }

    /// A follow-up turn completed an announcement already shown: update that card (for example with the
    /// gate) instead of treating the fragment as news of its own.
    private func merge(_ combined: String) {
        let reading = AnnouncementRules.read(combined, myFlight: flightCode)
        guard let i = heard.firstIndex(where: { $0.reading.flight == reading.flight && $0.reading.event == reading.event
            && Date().timeIntervalSince($0.time) < 60 }) else {
            take(combined)
            return
        }
        let gainedGate = heard[i].reading.gate == nil && reading.gate != nil
        heard[i].reading = reading
        heard[i].original = combined
        EventLog.write("turn_merged", ["text": combined, "gate": reading.gate ?? ""])
        if gainedGate && heard[i].certainty == .sure {
            notify(title: Self.headline(for: reading), body: combined, heardID: heard[i].id,
                   urgent: [.boarding, .finalCall].contains(reading.event))
        }
    }

    private var lastError: String?
    private var reconnects: [Date] = []

    private func reconnect() {
        guard transcriber != nil else { return }   // already stopped by the user
        reconnects = reconnects.filter { Date().timeIntervalSince($0) < 60 } + [Date()]
        stop()
        // Give up after repeated failures in one minute and say so: never pretend to be listening.
        guard reconnects.count <= 3 else {
            state = .failed("收音連線一直中斷（\(lastError ?? "連線關閉")）。請確認網路後再按一次開始。")
            return
        }
        state = .connecting
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard state == .connecting,
                  let key = Bundle.main.object(forInfoDictionaryKey: "MetaAPIKey") as? String else { return }
            connect(apiKey: key)
        }
    }

    // MARK: - Deciding what to tell the user

    /// Exposed for previews and for replaying test transcripts.
    func take(_ text: String) {
        let reading = AnnouncementRules.read(text, myFlight: flightCode)
        guard reading.event != .info else { return }

        var certainty = Certainty.notYours
        var note: String?
        switch reading.match(for: user) {
        case .mine where reading.event != nil:
            certainty = .sure
        case .mine:
            certainty = .maybe
            note = "聽到你的班號，但聽不清楚是什麼消息。"
        case .destinationConflict(let heardPlaces):
            certainty = .maybe
            note = "聽到 \(reading.flight ?? "")，但廣播說的目的地是 \(heardPlaces.joined(separator: "、"))，跟你的不同。"
        case .notMine:
            break
        }

        // The same news in Mandarin and then English counts as hearing it twice, which raises confidence.
        if certainty != .notYours,
           let i = heard.firstIndex(where: { $0.reading.flight == reading.flight && $0.reading.event == reading.event
               && Date().timeIntervalSince($0.time) < 180 }) {
            heard[i].confirmations += 1
            EventLog.write("heard_again", ["text": text, "confirmations": heard[i].confirmations])
            if heard[i].certainty == .maybe && certainty == .sure {
                heard[i] = Heard(time: Date(), original: text, reading: reading, certainty: .sure, note: nil,
                                 confirmations: heard[i].confirmations)
                alert(heard[i])
            } else if UIApplication.shared.applicationState != .active || [.boarding, .finalCall].contains(reading.event) {
                // Same news again. Normally that only raises confidence, but with the screen off the first
                // alert may have gone unseen, and boarding calls are repeated because people miss them.
                alert(heard[i], repeatCount: heard[i].confirmations)
            }
            return
        }

        let item = Heard(time: Date(), original: text, reading: reading, certainty: certainty, note: note)
        EventLog.write("heard", ["text": text, "flight": reading.flight ?? "", "event": reading.event?.rawValue ?? "",
                                 "gate": reading.gate ?? "", "time_said": reading.time ?? "",
                                 "certainty": "\(certainty)", "note": note ?? ""])
        heard.insert(item, at: 0)
        alert(item)
    }

    private func alert(_ item: Heard, repeatCount: Int = 1) {
        switch item.certainty {
        case .sure:
            let event = item.reading.event
            let title = Self.headline(for: item.reading)
            let boardingCall = [.boarding, .finalCall].contains(event)
            if atGate && boardingCall {
                // Already at the gate: note it without buzzing or repeating.
                notify(title: "（你已在登機門）\(title)", body: item.original, quiet: true)
                return
            }
            if atGate && [.gateChange, .delay, .timeChange, .cancel].contains(event) {
                atGate = false
                EventLog.write("at_gate_cleared", ["event": event?.rawValue ?? ""])
            }
            if let event { haptics.play(Haptics.Level(event)) }
            notify(title: repeatCount > 1 ? "\(title)（第 \(repeatCount) 次廣播）" : title, body: item.original,
                   heardID: item.id, urgent: boardingCall)
        case .maybe:
            haptics.play(.maybe)
            notify(title: "可能跟你的班機有關", body: item.note ?? item.original, heardID: item.id)
        case .notYours:
            break
        }
    }

    static let urgentRepeatPrefix = "urgent-repeat-"

    /// `urgent`: in the background the system vibration is the same for every alert, so boarding and
    /// final calls are repeated every 30 seconds (up to 4 times) until the user opens the app.
    private func notify(title: String, body: String, heardID: UUID? = nil, urgent: Bool = false, quiet: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // In the foreground our own vibration pattern is the signal. iOS does not let Core Haptics play in
        // the background, so with the screen off the notification must carry the system alert instead,
        // or a deaf user in a pocket would feel nothing.
        content.sound = UIApplication.shared.applicationState == .active ? nil : .default
        // Gate changes and final calls can't wait for a Focus mode to end. Time-sensitive alerts get
        // through a Focus when the user allows them (iOS asks the first time one arrives).
        content.interruptionLevel = .timeSensitive
        // Buttons on the notification: boarding calls get "我已經在登機門了" as well as "我知道了".
        content.categoryIdentifier = urgent ? UrgentAnswer.boardingCategory : UrgentAnswer.generalCategory
        if let heardID { content.userInfo = ["heardID": heardID.uuidString] }
        if quiet {
            content.sound = nil
            content.interruptionLevel = .passive
        }
        EventLog.write("notify", ["title": title, "with_sound": content.sound != nil, "urgent": urgent, "quiet": quiet])
        let center = UNUserNotificationCenter.current()
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))

        guard urgent, UIApplication.shared.applicationState != .active else { return }
        for n in 1...4 {
            let again = content.mutableCopy() as! UNMutableNotificationContent
            again.title = "提醒：\(title)"
            again.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(30 * n), repeats: false)
            center.add(UNNotificationRequest(identifier: Self.urgentRepeatPrefix + UUID().uuidString,
                                             content: again, trigger: trigger))
        }
        EventLog.write("urgent_repeats_scheduled", ["title": title])
    }

    /// The user opened the app, so the urgent repeats have done their job.
    func cancelUrgentRepeats() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(Self.urgentRepeatPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Lets the user learn the vibration language, and check that vibration works at all.
    func tryVibration(_ level: Haptics.Level) {
        haptics.play(level)
        EventLog.write("try_vibration", ["level": "\(level)"])
    }

    // MARK: - Wording

    /// The gate as shown in a headline; an uncertain one says so instead of looking definite.
    private static func gate(_ r: AnnouncementReading) -> String? {
        r.gate.map { r.gateIsCertain ? $0 : "\($0)（待確認）" }
    }

    static func headline(for r: AnnouncementReading) -> String {
        switch r.event {
        case .gateChange: return gate(r).map { "登機門改到 \($0)" } ?? "登機門有變更（沒聽清楚是哪個門）"
        case .delay: return r.time.map { "班機延誤，新時間 \($0)" } ?? "班機延誤"
        case .timeChange: return r.time.map { "起飛提前到 \($0)！" } ?? "起飛時間提前！"
        case .boarding: return gate(r).map { "開始登機・\($0) 登機門" } ?? "開始登機"
        case .finalCall: return gate(r).map { "最後登機！\($0) 號登機門" } ?? "最後登機廣播！"
        case .cancel: return "班機取消"
        case .nameCall: return "廣播在找人，可能是你"
        case .info, nil: return "有一則廣播提到你的班號"
        }
    }

    /// What to show airport staff, in both languages.
    func staffCard(for r: AnnouncementReading?) -> (zh: String, en: String) {
        let flight = r?.flight ?? flightCode
        switch r?.event {
        case .cancel:
            return ("我是聽障旅客，聽說 \(flight) 取消了。請問我該怎麼改票？",
                    "I'm deaf. I think flight \(flight) was cancelled. How can I rebook?")
        case .delay, .timeChange:
            return ("我是聽障旅客。請問 \(flight) 現在幾點起飛？",
                    "I'm deaf. What time does flight \(flight) depart now?")
        default:
            return ("我是聽障旅客。請問 \(flight) 現在在哪個登機門？",
                    "I'm deaf. Which gate is flight \(flight) at now?")
        }
    }
}
