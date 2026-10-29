import AVFoundation
import Foundation
import Network
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
    /// What Taoyuan's live flight data says about it, when the flight is in the data.
    var verification: Verification?
    /// Muse Spark Open's Traditional Chinese for an English or Japanese announcement. Only a reading aid.
    var translation: String?
}

@MainActor
final class ListenerModel: ObservableObject {
    enum State: Equatable {
        case idle, connecting, listening
        /// Still meant to be listening, but there is no network: resumes by itself when it comes back.
        case offline
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
            flight = nil
            flightDataMessage = nil
            departureTime = nil
            flightEndAsked = nil
        }
    }
    /// The user's flight in Taoyuan's live data (nil when not found, e.g. flights from other airports).
    @Published var flight: ADIPFlight?
    @Published var flightDataTime: Date?
    /// Why there is no flight data, shown instead of the flight card.
    @Published var flightDataMessage: String?
    /// A change in the flight data that may not have been announced (or that the microphone missed).
    @Published var dataNotice: (text: String, time: Date)?
    private var refresher: Task<Void, Never>?

    // MARK: - Stopping when the trip is over

    /// Stop listening when the flight has left, and offer to when it was cancelled or moved to another day.
    /// Listening is the main running cost (speech recognition is billed per hour of audio), and it also
    /// uses battery and data.
    @Published var autoStop: Bool {
        didSet { UserDefaults.standard.set(autoStop, forKey: "autoStop") }
    }
    /// When the flight leaves, from the boarding pass or set by hand. Used only when there is no flight data
    /// to tell whether it has left (flights from airports other than Taoyuan).
    @Published var departureTime: Date? {
        didSet { UserDefaults.standard.set(departureTime, forKey: "departureTime") }
    }
    /// The departure time was worked out from the boarding time (only that was printed).
    @Published var departureTimeEstimated = false
    /// A question waiting for the user, shown as an alert.
    @Published var question: Question?
    /// Why listening stopped without the user pressing stop.
    @Published var stopNotice: String?

    enum Question: Identifiable {
        /// The flight was cancelled or moved: seen first, then (with auto stop on) asked about stopping.
        case flightEnded(title: String, message: String)
        case stopListening(reason: String)

        var id: String {
            switch self {
            case .flightEnded(let title, _): return "ended " + title
            case .stopListening(let reason): return "stop " + reason
            }
        }
    }

    /// Flight code and reason already shown, so the 5-minute refresh doesn't ask again.
    private var flightEndAsked: String?
    private var departureWatch: Task<Void, Never>?
    /// The departure-time question: how many times asked without an answer, and when last.
    private var departureAsk: (count: Int, at: Date)?
    /// After "繼續聆聽", don't ask about the departure time again before this.
    private var nextDepartureAsk: Date?
    private let network = NWPathMonitor()
    private var networkOnline = true
    private var offlineCheck: Task<Void, Never>?
    /// Offline this long is not an elevator or a car park any more, but most likely airplane mode.
    static let offlineStopAfter: TimeInterval = 30 * 60

    // MARK: - Boarding pass

    /// Read from a photo, waiting for the user to confirm.
    @Published var scannedPass: BoardingPass?
    /// "讀取中…" or why reading failed.
    @Published var passStatus: String?

    private var apiKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "MetaAPIKey") as? String,
              !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }

    func readBoardingPass(_ image: UIImage) async {
        guard let key = apiKey, let jpeg = PhotoPrep.jpeg(image) else {
            passStatus = "沒辦法讀這張照片。"
            return
        }
        passStatus = "Muse Spark 讀取登機證中…"
        let started = Date()
        do {
            scannedPass = try await MetaModelAPI(apiKey: key).readBoardingPass(jpeg: jpeg)
            passStatus = nil
            EventLog.write("boarding_pass", ["flight": scannedPass?.flightCode ?? "", "to": scannedPass?.to ?? "",
                                             "seconds": Date().timeIntervalSince(started),
                                             "handwritten": scannedPass?.handwrittenChanges ?? ""])
        } catch {
            passStatus = "讀不出登機證（\(error.localizedDescription)）。可以重拍，或直接輸入班號。"
            EventLog.write("boarding_pass_failed", ["error": error.localizedDescription])
        }
    }

    /// The user confirmed what was read: fill in the flight and look it up in the flight data.
    func useScannedPass() {
        guard let pass = scannedPass else { return }
        if let code = pass.flightCode { flightCode = code }
        if let name = pass.destinationName { destination = name }
        if let departure = pass.departure() {
            departureTime = departure.date
            departureTimeEstimated = departure.estimated
        }
        scannedPass = nil
        Task { await refreshFlightData(alertOnChange: false) }
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
        autoStop = UserDefaults.standard.object(forKey: "autoStop") as? Bool ?? true
        departureTime = UserDefaults.standard.object(forKey: "departureTime") as? Date
        network.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        network.start(queue: .main)
        NotificationCenter.default.addObserver(forName: UrgentAnswer.notification, object: nil, queue: .main) { [weak self] note in
            guard let answer = note.object as? UrgentAnswer else { return }
            let id = (note.userInfo?["heardID"] as? String).flatMap(UUID.init)
            MainActor.assumeIsolated { self?.answer(answer, heardID: id) }
        }
    }

    /// From the buttons on an urgent notification or on the alert card.
    func answer(_ answer: UrgentAnswer, heardID: UUID?) {
        cancelUrgentRepeats()
        switch answer {
        case .atGate: atGate = true
        case .flightEndSeen: flightEndSeen(inApp: false)
        case .stopListening: stopAsked()
        case .keepListening: keepListening()
        case .gotIt: break
        }
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
        stopNotice = nil
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
            // Record what the user actually allowed, so "a banner appeared but no sound or vibration"
            // can be told apart from a switched-off setting by reading the log.
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            func on(_ s: UNNotificationSetting) -> String { s == .enabled ? "on" : (s == .disabled ? "off" : "n/a") }
            EventLog.write("notification_settings", [
                "authorized": settings.authorizationStatus == .authorized,
                "sound": on(settings.soundSetting), "alert": on(settings.alertSetting),
                "lock_screen": on(settings.lockScreenSetting), "time_sensitive": on(settings.timeSensitiveSetting),
            ])
            guard isListening else { return }   // the user pressed stop meanwhile
            await refreshFlightData(alertOnChange: false)
            guard isListening else { return }
            if networkOnline { connect(apiKey: key) } else { wentOffline() }
            watchDepartureTime()
            // The data is updated every 5 minutes; follow it while listening.
            refresher?.cancel()
            refresher = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 300_000_000_000)
                    guard !Task.isCancelled else { return }
                    await self?.refreshFlightData(alertOnChange: true)
                }
            }
        }
    }

    // MARK: - Flight data (Taoyuan ADIP)

    /// Looks the user's flight up in Taoyuan's live data. Fills in an empty destination, re-checks what
    /// was already heard, and with `alertOnChange` warns about gate or status changes in the data itself.
    func refreshFlightData(alertOnChange: Bool) async {
        let code = flightCode
        guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let flights = try await ADIP.fetch()
            flightDataTime = Date()
            guard let found = ADIP.find(code, in: flights) else {
                flight = nil
                flightDataMessage = "桃園機場今天的航班資料裡找不到 \(code)。目前只能核對桃園的航班，廣播判讀照常運作。"
                EventLog.write("adip", ["flight": code, "found": false])
                return
            }
            flightDataMessage = nil
            if destination.isEmpty { destination = found.placeZh }
            if alertOnChange, let old = flight, old.code == found.code {
                for change in Verification.changes(from: old, to: found) {
                    // A cancellation or a move to another day gets its own message and question below.
                    if case .status = change, found.isCancelled || found.isMovedToNextDay { continue }
                    dataChanged(change)
                }
            }
            // Only a departure seen while listening counts: a flight that left before the user pressed
            // start may be yesterday's or today's of a trip that is tomorrow.
            let departedNow = alertOnChange && flight?.code == found.code && flight?.hasDeparted == false && found.hasDeparted
            flight = found
            for i in heard.indices where heard[i].certainty != .notYours {
                applyVerification(to: &heard[i])
            }
            EventLog.write("adip", ["flight": found.code, "found": true, "gate": found.gate ?? "", "status": found.status,
                                    "estimated": found.estimated, "codeshares": found.codeshares.joined(separator: ",")])
            if departedNow {
                flightDeparted()
            } else if isListening {
                flightEnded(found)
            }
        } catch {
            flightDataMessage = "暫時拿不到航班資料（\(error.localizedDescription)），廣播判讀照常運作。"
            EventLog.write("adip_failed", ["error": error.localizedDescription])
        }
    }

    var isListening: Bool { [.listening, .connecting, .offline].contains(state) }

    /// The flight has left: listening any longer only costs data, battery and model usage. Say so,
    /// so nobody thinks they are still covered.
    private func flightDeparted() {
        let code = flight?.code ?? flightCode
        guard autoStop else {
            notify(title: "航班資料：\(code) 已起飛", body: "自動停止已關閉，Shunfeng 會繼續聆聽，直到你按停止。")
            return
        }
        EventLog.write("auto_stop", ["flight": code, "reason": "departed"])
        stopWithNotice("你的班機已起飛，已自動停止聆聽。",
                       body: "航班資料顯示 \(code) 已出發，Shunfeng 不再收音。還在機場的話，打開 App 按開始就會繼續聽。")
    }

    /// Stops listening on its own and says why, on screen and as a notification.
    private func stopWithNotice(_ notice: String, body: String) {
        userStop()
        question = nil
        stopNotice = notice
        notify(title: notice, body: body)
    }

    /// Cancelled, or moved to another day: tell the user first; only once they have seen it, ask whether to
    /// stop listening. The news matters more than saving usage, so it never stops on its own.
    private func flightEnded(_ f: ADIPFlight) {
        let reason: (key: String, title: String, message: String)
        if f.isCancelled {
            reason = ("cancel", "你的班機已取消", "航班資料顯示 \(f.code) 已取消。請看大螢幕，或問櫃台怎麼改票。")
        } else if f.isMovedToNextDay {
            reason = ("next_day", "你的班機改到 \(f.estimated.dropFirst(5).prefix(5).replacingOccurrences(of: "-", with: "/")) 起飛",
                      "航班資料顯示 \(f.code) 預計 \(f.estimated.dropFirst(5).replacingOccurrences(of: "-", with: "/")) 起飛，不是今天。")
        } else {
            return
        }
        guard flightEndAsked != f.code + reason.key else { return }
        flightEndAsked = f.code + reason.key
        EventLog.write("flight_ended", ["flight": f.code, "reason": reason.key])
        question = .flightEnded(title: reason.title, message: reason.message)
        haptics.play(f.isCancelled ? .cancelled : .change)
        let more = autoStop ? "按「我知道了」之後，會問你要不要停止聆聽。" : ""
        notify(title: reason.title, body: reason.message + more, category: UrgentAnswer.flightEndCategory)
    }

    /// The user saw the cancellation or new day. Now ask about stopping (unless auto stop is off).
    func flightEndSeen(inApp: Bool) {
        question = nil
        guard autoStop, isListening else { return }
        let reason = "班機已取消或改期，今天應該不需要再聽廣播了。"
        if inApp {
            // Let the first alert finish closing before the next one opens.
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                question = .stopListening(reason: reason)
            }
        } else {
            question = .stopListening(reason: reason)
            notify(title: "要停止聆聽嗎？", body: reason, category: UrgentAnswer.askStopCategory)
        }
    }

    func stopAsked() {
        EventLog.write("auto_stop", ["reason": "user_said_stop"])
        userStop()
        question = nil
        stopNotice = "已依你的選擇停止聆聽。"
    }

    func keepListening() {
        EventLog.write("keep_listening")
        question = nil
        departureAsk = nil
        nextDepartureAsk = Date().addingTimeInterval(3600)
    }

    /// Without flight data, the departure time is the only clue. From 5 minutes before it, ask whether to
    /// stop; no answer → ask again an hour later; still no answer 15 minutes after that → stop and say so.
    private func watchDepartureTime() {
        departureWatch?.cancel()
        departureAsk = nil
        nextDepartureAsk = nil
        departureWatch = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkDepartureTime()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func checkDepartureTime(now: Date = Date()) {
        guard autoStop, isListening, flight == nil, let departure = departureTime else { return }
        if let ask = departureAsk {
            let waited = now.timeIntervalSince(ask.at)
            if ask.count == 1, waited >= 3600 {
                askAboutDeparture(departure, count: 2)
            } else if ask.count == 2, waited >= 15 * 60 {
                EventLog.write("auto_stop", ["reason": "no_answer"])
                stopWithNotice("沒有收到回應，已自動停止聆聽。",
                               body: "已過起飛時間，兩次詢問都沒有回應。還在機場的話，打開 App 按開始就會繼續聽。")
            }
            return
        }
        if let next = nextDepartureAsk, now < next { return }
        if now >= departure.addingTimeInterval(-5 * 60) { askAboutDeparture(departure, count: 1) }
    }

    private func askAboutDeparture(_ departure: Date, count: Int) {
        departureAsk = (count, Date())
        let time = departure.formatted(date: .omitted, time: .shortened)
        let reason = departure > Date() ? "快到起飛時間 \(time) 了" : "已過起飛時間 \(time)"
        EventLog.write("ask_stop", ["reason": "departure_time", "count": count])
        question = .stopListening(reason: "\(reason)，但沒有航班資料能確認班機是否已起飛。")
        notify(title: "\(reason)，要停止聆聽嗎？",
               body: count == 1 ? "已經上飛機就可以停止。沒有回應的話，一小時後會再問一次。"
                                : "15 分鐘內沒有回應，就會自動停止聆聽。",
               category: UrgentAnswer.askStopCategory)
    }

    /// No network: an elevator, a car park, or airplane mode. iOS doesn't tell apps which, so pause and
    /// resume by itself when the network is back. Because the user can't hear announcements meanwhile, say
    /// so after a minute. Only after a long time offline (most likely airplane mode) stop for good.
    private func networkChanged(online: Bool) {
        networkOnline = online
        EventLog.write("network", ["online": online, "state": "\(state)"])
        if online {
            offlineCheck?.cancel()
            guard state == .offline, let key = apiKey else { return }
            reconnects = []
            state = .connecting
            connect(apiKey: key)
        } else if isListening, state != .offline {
            wentOffline()
        }
    }

    private func wentOffline() {
        stop()
        state = .offline
        offlineCheck?.cancel()
        offlineCheck = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled, self?.state == .offline else { return }
            self?.notify(title: "沒有網路，暫時聽不到廣播",
                         body: "網路恢復後會自動繼續聽。這段時間請留意大螢幕。")
            try? await Task.sleep(nanoseconds: UInt64((Self.offlineStopAfter - 60) * 1_000_000_000))
            guard !Task.isCancelled, self?.state == .offline else { return }
            EventLog.write("auto_stop", ["reason": "offline"])
            self?.stopWithNotice("沒有網路已超過 30 分鐘（可能是飛航模式），已停止聆聽。",
                                 body: "還在機場的話，恢復網路後打開 App 按開始就會繼續聽。")
        }
    }

    private func dataChanged(_ change: Verification.DataChange) {
        let text: String
        switch change {
        case .gate(_, let to): text = "航班資料：登機門改到 \(to)"
        case .status(_, let to): text = "航班資料：班機狀態變成「\(to)」"
        }
        dataNotice = (text, Date())
        haptics.play(.change)
        notify(title: text, body: "這是機場航班資料的變化，廣播可能沒聽到。請看大螢幕確認。")
        EventLog.write("adip_change", ["text": text])
    }

    /// Checks a heard item against the flight data. A disagreeing gate is marked uncertain on the card.
    private func applyVerification(to item: inout Heard) {
        guard let flight else { return }
        let v = Verification.check(item.reading, against: flight)
        item.verification = v
        if case .disagrees = v.gate { item.reading.gateIsCertain = false }
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
        refresher?.cancel()
        departureWatch?.cancel()
        departureAsk = nil
        offlineCheck?.cancel()
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
        translate(heard[i])
        if gainedGate && heard[i].certainty == .sure {
            notify(title: Self.headline(for: reading), body: combined, heardID: heard[i].id,
                   urgent: [.boarding, .finalCall].contains(reading.event))
        }
    }

    private var lastError: String?
    private var reconnects: [Date] = []

    private func reconnect() {
        guard transcriber != nil else { return }   // already stopped by the user
        // A dropped network is not a failure: wait for it instead of using up the retries.
        guard networkOnline else {
            wentOffline()
            return
        }
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
                translate(heard[i])
            } else if UIApplication.shared.applicationState != .active || [.boarding, .finalCall].contains(reading.event) {
                // Same news again. Normally that only raises confidence, but with the screen off the first
                // alert may have gone unseen, and boarding calls are repeated because people miss them.
                alert(heard[i], repeatCount: heard[i].confirmations)
            }
            return
        }

        var item = Heard(time: Date(), original: text, reading: reading, certainty: certainty, note: note)
        if certainty != .notYours { applyVerification(to: &item) }
        EventLog.write("heard", ["text": text, "flight": reading.flight ?? "", "event": reading.event?.rawValue ?? "",
                                 "gate": reading.gate ?? "", "time_said": reading.time ?? "",
                                 "certainty": "\(certainty)", "note": note ?? ""])
        heard.insert(item, at: 0)
        alert(item)
        if certainty != .notYours { translate(item) }
    }

    /// Adds a translation when the announcement was English or Japanese. Automatic only for the user's
    /// flight; others are translated when the user taps "翻譯", so a busy airport doesn't cost a model call
    /// per announcement. It arrives a few seconds after the alert and never changes it: the alert must not
    /// wait on, or depend on, a translation.
    func translate(_ item: Heard) {
        guard MuseSparkOpen.needsTranslation(item.original),
              let key = Bundle.main.object(forInfoDictionaryKey: "BasetenAPIKey") as? String,
              !key.isEmpty, !key.hasPrefix("$(") else { return }
        let text = item.original
        Task {
            let started = Date()
            do {
                let translation = try await MuseSparkOpen(apiKey: key).translate(text)
                // The card may have been merged with a later turn meanwhile; that text gets its own translation.
                guard let i = heard.firstIndex(where: { $0.id == item.id && $0.original == text }) else { return }
                heard[i].translation = translation
                EventLog.write("translated", ["text": text, "translation": translation,
                                              "seconds": Date().timeIntervalSince(started)])
            } catch {
                EventLog.write("translate_failed", ["error": error.localizedDescription])
            }
        }
    }

    private func alert(_ item: Heard, repeatCount: Int = 1) {
        switch item.certainty {
        case .sure:
            let event = item.reading.event
            let title = Self.headline(for: item)
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
    private func notify(title: String, body: String, heardID: UUID? = nil, urgent: Bool = false, quiet: Bool = false,
                        category: String? = nil) {
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
        content.categoryIdentifier = category ?? (urgent ? UrgentAnswer.boardingCategory : UrgentAnswer.generalCategory)
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

    /// Headline for a card or notification: when the gate wasn't heard but the flight data has one,
    /// it is shown and labelled as coming from the data.
    static func headline(for item: Heard) -> String {
        var r = item.reading
        if r.gate == nil, case .fromData(let g)? = item.verification?.gate {
            r.gate = "\(g)（航班資料）"
            r.gateIsCertain = true
        }
        return headline(for: r)
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
