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
    let original: String
    let reading: AnnouncementReading
    let certainty: Certainty
    let note: String?
    /// How many times this same news has been heard (Mandarin and English versions agree).
    var confirmations = 1
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
        didSet { UserDefaults.standard.set(flightCode, forKey: "flightCode") }
    }
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
        case .turnComplete(_, let text):
            partial = ""
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { take(text) }
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
            if let event = item.reading.event { haptics.confirmed(event) }
            let title = Self.headline(for: item.reading)
            notify(title: repeatCount > 1 ? "\(title)（第 \(repeatCount) 次廣播）" : title, body: item.original)
        case .maybe:
            haptics.maybe()
            notify(title: "可能跟你的班機有關", body: item.note ?? item.original)
        case .notYours:
            break
        }
    }

    private func notify(title: String, body: String) {
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
        EventLog.write("notify", ["title": title, "with_sound": content.sound != nil])
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - Wording

    static func headline(for r: AnnouncementReading) -> String {
        switch r.event {
        case .gateChange: return r.gate.map { "登機門改到 \($0)" } ?? "登機門有變更（沒聽清楚是哪個門）"
        case .delay: return r.time.map { "班機延誤，新時間 \($0)" } ?? "班機延誤"
        case .timeChange: return r.time.map { "起飛提前到 \($0)！" } ?? "起飛時間提前！"
        case .boarding: return r.gate.map { "開始登機・\($0) 登機門" } ?? "開始登機"
        case .finalCall: return "最後登機廣播！"
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
