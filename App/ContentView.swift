import PhotosUI
import ShunfengCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = ListenerModel()
    @State private var showingStaffCard = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingCamera = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showingSettings = false
    /// The listening ring turns solid for a moment when an announcement about the user's flight arrives.
    @State private var detected = false
    /// A new alert opens over a blurred, dimmed screen until it is answered, so nothing behind it can be
    /// tapped by mistake and the user can focus on it. Answered alerts stay in the list below.
    @State private var modalID: UUID?
    /// Reading a boarding pass failed: the reason, shown in the popup until the user picks what to do.
    @State private var passFailure: String?
    @State private var showingPhotos = false

    private var passPopupShown: Bool { model.readingPass || passFailure != nil }

    private var modalItem: Heard? { modalID.flatMap { id in model.heard.first { $0.id == id } } }

    // Text is looked up when views are drawn, so a language change rebuilds the screen. The model (and
    // listening) lives above it and carries on.
    var body: some View {
        page.id(model.language)
    }

    private var page: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.state == .idle && model.stopNotice == nil {
                        header
                    }
                    if let banner = bannerKind {
                        StatusBanner(kind: banner, action: bannerAction)
                    }
                    alerts
                    if let notice = model.dataNotice {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(notice.text).font(Theme.label)
                                Text(L("這是機場航班資料的變化，廣播可能沒聽到。請看大螢幕確認。")).font(Theme.body)
                            }
                        } icon: { GlyphBadge(symbol: "airplane", color: Theme.info) }
                        .sfNote(Theme.info, Theme.infoBg)
                    }
                    if model.atGate {
                        HStack {
                            Label(L("你已在登機門，登機廣播不再震動提醒"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.confirmed)
                            Spacer()
                            Button(L("取消", "Undo")) { model.atGate = false }.buttonStyle(.sfText)
                        }
                        .font(Theme.body)
                    }
                    if !model.isListening {
                        flightSetup
                    }
                    FlightCard(flight: model.flight, updated: model.flightDataTime, message: model.flightDataMessage,
                               conflict: conflict, stale: model.state == .offline || model.connection == .noNetwork)
                    connectionLine
                    if model.isListening {
                        listeningSection
                    }
                    VibrationLegend { model.tryVibration($0) }
                    if !model.isListening {
                        listenButton
                    }
                    if !model.heard.isEmpty {
                        NavigationLink {
                            BroadcastLog(model: model)
                        } label: {
                            Label(L("看廣播紀錄（\(model.heard.count)）", "Announcement log (\(model.heard.count))"), systemImage: "list.bullet.rectangle")
                        }
                        .buttonStyle(.sfSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .animation(reduceMotion ? .easeOut(duration: Theme.fast) : Theme.enter, value: model.latestSure?.id)
                .animation(reduceMotion ? .easeOut(duration: Theme.fast) : Theme.enter, value: model.latestMaybe?.id)
                .animation(.easeInOut(duration: Theme.base), value: model.isListening)
            }
            .background(Theme.page)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("LogoMark").resizable().frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(L("順風 Shunfeng")).font(Theme.label).foregroundStyle(Theme.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("設定"), systemImage: "gearshape") { showingSettings = true }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView(model: model) }
            .alert(questionTitle, isPresented: questionShown, presenting: model.question) { question in
                switch question {
                case .flightEnded:
                    Button(L("我知道了")) { model.flightEndSeen(inApp: true) }
                case .stopListening:
                    Button(L("停止聆聽"), role: .destructive) { model.stopAsked() }
                    Button(L("繼續聆聽"), role: .cancel) { model.keepListening() }
                }
            } message: { question in
                switch question {
                case .flightEnded(_, let message): Text(message)
                case .stopListening(let reason): Text(reason)
                }
            }
            .fullScreenCover(isPresented: $showingStaffCard) {
                let item = model.latestSure ?? model.latestMaybe
                StaffCard(text: model.staffCard(for: item?.reading), have: whatIHave(item)) { showingStaffCard = false }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker { image in Task { await model.readBoardingPass(image) } }
                    .ignoresSafeArea()
            }
            .sheet(item: $model.scannedPass) { pass in
                BoardingPassConfirm(pass: pass, use: model.useScannedPass) {
                    model.scannedPass = nil
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { showingCamera = true } else { showingPhotos = true }
                }
            }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await model.readBoardingPass(image)
                    }
                    pickedPhoto = nil
                }
            }
            .onChange(of: model.latestSure?.id) { _, _ in present(model.latestSure) }
            .onChange(of: model.latestMaybe?.id) { _, _ in present(model.latestMaybe) }
            .onChange(of: modalItem?.acknowledged) { _, answered in
                guard answered == true else { return }
                // Leave "已確認" on screen for a moment before closing.
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    modalID = nil
                }
            }
            .onChange(of: model.heard.first?.id) { _, _ in
                guard let item = model.heard.first, item.certainty != .notYours else { return }
                detected = true
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    detected = false
                }
            }
            .onChange(of: scenePhase) { _, phase in
                EventLog.write("scene", ["phase": "\(phase)"])
                if phase == .active {
                    model.cancelUrgentRepeats()
                    model.interruptionEnded()
                    if model.state == .idle { Task { await model.checkConnection() } }
                }
            }
            .task {
                #if DEBUG
                // Replays transcripts through the real rules, to see the alert cards without an airport:
                // -replay "first announcement|second announcement" (3 s apart).
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-replay"), i + 1 < args.count {
                    for text in args[i + 1].split(separator: "|") {
                        try? await Task.sleep(for: .seconds(3))
                        model.take(String(text))
                    }
                }
                #endif
                await model.checkConnection()
            }
        }
        .overlay { alertModal }
        .overlay { passModal }
        .photosPicker(isPresented: $showingPhotos, selection: $pickedPhoto, matching: .images)
        .onChange(of: model.readingPass) { _, reading in
            if reading {
                passFailure = nil
            } else if model.scannedPass == nil, let status = model.passStatus {
                passFailure = status
            } else if let pass = model.scannedPass, pass.flightCode == nil {
                // Nothing usable came back (not a boarding pass, or too blurry): an all-empty form would
                // only confuse, so say so and offer another try instead.
                model.scannedPass = nil
                passFailure = L("照片裡找不到班號，可能不是登機證，或照片不夠清楚。")
            }
        }
        .animation(reduceMotion ? .easeOut(duration: Theme.fast) : .easeInOut(duration: Theme.base), value: modalID)
        .animation(reduceMotion ? .easeOut(duration: Theme.fast) : .easeInOut(duration: Theme.base), value: passPopupShown)
        .tint(Theme.brand)
    }

    private func present(_ item: Heard?) {
        guard let item, !item.acknowledged else { return }
        modalID = item.id
    }

    /// The blurred, dimmed backdrop swallows every tap; only the card's own buttons answer it.
    @ViewBuilder private var alertModal: some View {
        if let item = modalItem {
            ZStack {
                ModalBackdrop()
                GeometryReader { geo in
                    ScrollView {
                        AlertCard(item: item, atGate: model.atGate, answer: { model.answer($0, heardID: $1) }) {
                            showingStaffCard = true
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .transition(cardTransition)
            }
            .transition(.opacity)
            .accessibilityAddTraits(.isModal)
        }
    }

    /// Waiting for Muse Spark to read the photo, then either the confirm sheet or what went wrong.
    @ViewBuilder private var passModal: some View {
        if passPopupShown {
            let camera = UIImagePickerController.isSourceTypeAvailable(.camera)
            ZStack {
                ModalBackdrop()
                PassReadingCard(failure: model.readingPass ? nil : passFailure,
                                retakeTitle: camera ? L("重拍") : L("重新選照片"),
                                retake: {
                                    passFailure = nil
                                    if camera { showingCamera = true } else { showingPhotos = true }
                                },
                                typeInstead: {
                                    passFailure = nil
                                    model.passStatus = nil
                                })
                .padding(.horizontal, 24)
                .transition(cardTransition)
            }
            .transition(.opacity)
            .accessibilityAddTraits(.isModal)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("今天搭哪一班？")).font(Theme.title).foregroundStyle(Theme.textPrimary)
            Text(L("只在廣播跟你的航班有關時，才震動提醒你。")).font(Theme.body).foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder private var alerts: some View {
        if let item = model.latestSure {
            AlertCard(item: item, atGate: model.atGate, answer: { model.answer($0, heardID: $1) }) { showingStaffCard = true }
                .id(item.id)
                .transition(cardTransition)
        }
        if let item = model.latestMaybe {
            AlertCard(item: item, atGate: model.atGate, answer: { model.answer($0, heardID: $1) }) { showingStaffCard = true }
                .id(item.id)
                .transition(cardTransition)
        }
    }

    /// M02: slides down from under the status bar while growing from 96 %; Reduce Motion only fades.
    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .top).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
            removal: .opacity)
    }

    private var bannerKind: StatusBanner.Kind? {
        switch model.state {
        case .idle: return model.stopNotice.map { .stopped($0) }
        case .connecting: return .connecting
        case .listening: return .listening(model.micInUse)
        case .interrupted: return .paused
        case .offline: return .offline
        case .failed(let message): return .failed(message)
        }
    }

    private var bannerAction: (() -> Void)? {
        switch model.state {
        case .listening: return { model.userStop() }
        case .failed: return { model.start() }
        case .idle: return canStart ? { model.start() } : nil
        default: return nil
        }
    }

    /// The flight data and the newest announcement disagree about the gate: shown, never hidden.
    private var conflict: (heard: String, data: String)? {
        guard let item = model.latestSure ?? model.latestMaybe,
              case .disagrees(let heard, let data)? = item.verification?.gate else { return nil }
        return (heard, data)
    }

    /// "What I have" on the staff card, so staff can see at once what needs checking.
    private func whatIHave(_ item: Heard?) -> StaffCard.Have? {
        guard let item else { return nil }
        if case .disagrees(let heard, let data)? = item.verification?.gate {
            return .init(zh: "航班資料是 \(data)，廣播聽到 \(heard)（待確認）",
                         en: "The board data says \(data), but I heard \(heard). Please confirm.", sure: false)
        }
        let sure = item.certainty == .sure
        return .init(zh: "\(ListenerModel.headline(for: item, in: .zh))（\(sure ? "廣播聽到" : "可能，待確認")）",
                     en: "Announcement I got: \u{201C}\(item.original)\u{201D}", sure: sure)
    }

    private var listeningSection: some View {
        VStack(spacing: 12) {
            ListeningRing(detected: detected)
            Text(detected ? L("聽到可能相關的廣播，正在核對") : L("正在聽機場廣播"))
                .font(Theme.heading).foregroundStyle(Theme.textPrimary)
            Text(L("手機可以鎖屏放口袋。只有跟 \(model.flightCode) 有關時才會震動。",
                   "Lock your phone and put it in your pocket. It buzzes only for \(model.flightCode)."))
                .font(Theme.body).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if model.state == .listening {
                ProgressView(value: Double(model.level))
                    .tint(model.level < 0.15 ? Theme.possible : Theme.confirmed)
                    .accessibilityLabel(model.level < 0.15 ? L("收音很小") : L("收音正常"))
                if !model.partial.isEmpty {
                    Text(L("最近聽到：\(model.partial)", "Just heard: \(model.partial)"))
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var flightSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(L("班號")) {
                TextField(L("例如 CI100"), text: $model.flightCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await model.refreshFlightData(alertOnChange: false) } }
            }
            field(L("目的地")) {
                TextField(L("例如 東京"), text: $model.destination)
            }
            departureRow
            HStack(spacing: 12) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showingCamera = true } label: { Label(L("拍登機證", "Scan pass"), systemImage: "camera").lineLimit(1) }
                        .buttonStyle(.sfSecondary)
                }
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Label(L("從相簿選"), systemImage: "photo").lineLimit(1)
                }
                .buttonStyle(.sfSecondary)
            }
            if let status = model.passStatus, !passPopupShown {
                Text(status).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .disabled(model.state != .idle && !isFailed)
    }

    private func field<Input: View>(_ title: String, @ViewBuilder input: () -> Input) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            input()
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .frame(minHeight: Theme.touch)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.border, lineWidth: 1))
        }
    }

    /// Only needed when the flight isn't in Taoyuan's data: then it is how Shunfeng knows when to ask about stopping.
    @ViewBuilder private var departureRow: some View {
        if let time = model.departureTime {
            HStack {
                DatePicker(L("起飛時間", "Departs"), selection: Binding(get: { time }, set: {
                    model.departureTime = $0
                    model.departureTimeEstimated = false
                }))
                .font(Theme.body)
                Button(L("清除"), systemImage: "xmark.circle.fill") { model.departureTime = nil }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minWidth: Theme.touch, minHeight: Theme.touch)
            }
            if model.departureTimeEstimated {
                Text(L("登機證只印登機時間，起飛時間是推估的（登機後 30 分鐘），請確認。"))
                    .sfNote(Theme.possible, Theme.possibleBg)
            }
        } else if model.flight == nil {
            Button(L("設定起飛時間"), systemImage: "clock") {
                model.departureTime = Calendar.current.date(byAdding: .hour, value: 2, to: Date())
            }
            .buttonStyle(.sfText)
        }
    }

    private var questionTitle: String {
        switch model.question {
        case .flightEnded(let title, _): return title
        case .stopListening: return L("要停止聆聽嗎？")
        case nil: return ""
        }
    }

    private var questionShown: Binding<Bool> {
        // Closing the alert by its buttons is handled by the buttons; this only clears it otherwise.
        Binding(get: { model.question != nil }, set: { if !$0 { model.question = nil } })
    }

    private var isFailed: Bool {
        if case .failed = model.state { return true }
        return false
    }

    private var canStart: Bool {
        !model.flightCode.trimmingCharacters(in: .whitespaces).isEmpty && model.connection == .ok
    }

    private var listenButton: some View {
        Button {
            model.start()
        } label: {
            Label(L("開始聆聽廣播"), systemImage: "ear")
        }
        .buttonStyle(.sfPrimary)
        .disabled(!canStart)
    }

    /// Before starting: whether the service can be reached, so the start button never leads to a dead stream.
    @ViewBuilder private var connectionLine: some View {
        if model.state == .idle {
            switch model.connection {
            case .ok:
                EmptyView()
            case .checking:
                StatusBanner(kind: .connecting)
            case .noNetwork, .unreachable:
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.connection == .noNetwork
                          ? L("目前沒有網路，無法聆聽。請打開 Wi-Fi 或行動網路。")
                          : L("連不上語音辨識服務。如果連的是機場 Wi-Fi，請先打開瀏覽器完成登入（按「同意」）。"),
                          systemImage: "wifi.exclamationmark")
                        .sfNote(Theme.critical, Theme.criticalBg)
                    Button(L("重新檢查"), systemImage: "arrow.clockwise") { Task { await model.checkConnection() } }
                        .buttonStyle(.sfSecondary)
                }
            }
        }
    }
}

/// The big card for the newest announcement about the user's flight. A colored header band carries
/// an icon, the words and the vibration count, so color is never the only cue.
struct AlertCard: View {
    let item: Heard
    let atGate: Bool
    let answer: (UrgentAnswer, UUID) -> Void
    let askStaff: () -> Void

    private var isBoardingCall: Bool {
        item.certainty == .sure && [.boarding, .finalCall].contains(item.reading.event)
    }

    private var tone: AlertTone {
        guard item.certainty == .sure else { return .possible }
        return [.boarding, .finalCall, .cancel].contains(item.reading.event) ? .critical : .confirmed
    }

    private var level: Haptics.Level {
        item.certainty == .sure ? Haptics.Level(item.reading.event ?? .info) : .maybe
    }

    private var badge: String {
        guard item.certainty == .sure else { return L("可能・請確認") }
        switch item.reading.event {
        case .finalCall: return L("最後登機・馬上行動")
        case .boarding: return L("開始登機・馬上行動")
        case .cancel: return L("班機取消")
        case .gateChange: return L("確定・登機門變更")
        case .delay, .timeChange: return L("確定・時間變更")
        default: return L("確定")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                GlyphBadge(symbol: tone.glyph, color: Theme.onBrand, foreground: tone.color, size: 24)
                Text(badge).font(Theme.label)
                Spacer()
                Text(level.spoken).font(Theme.caption)
                // In step with the vibration only when the card just arrived.
                VibrationDots(level: level, play: Date().timeIntervalSince(item.time) < 5)
            }
            .foregroundStyle(Theme.onBrand)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(tone.color)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("\(badge)，\(level.spoken)", "\(badge), \(level.spoken)"))

            VStack(alignment: .leading, spacing: 12) {
                if item.certainty == .sure {
                    Text(ListenerModel.headline(for: item)).font(Theme.alert).foregroundStyle(tone.color)
                } else {
                    // Don't shout "Final call!" when we are not sure it is the user's flight.
                    Text(L("可能跟你有關，請確認")).font(Theme.alert).foregroundStyle(tone.color)
                    Text(L("廣播內容：\(ListenerModel.headline(for: item))", "Announcement: \(ListenerModel.headline(for: item))")).font(Theme.heading).foregroundStyle(Theme.textBody)
                }
                if let note = item.note {
                    Text(note).font(Theme.body).foregroundStyle(Theme.textBody)
                }
                if item.confirmations > 1 {
                    Label(L("聽到 \(item.confirmations) 次，內容一致", "Heard \(item.confirmations) times, the same each time"), systemImage: "checkmark.seal").font(Theme.body)
                }
                if item.certainty == .maybe {
                    Label(L("把手機拿在手上、朝向廣播喇叭，下一次廣播會聽得更清楚。"), systemImage: "iphone.radiowaves.left.and.right")
                        .font(Theme.body).foregroundStyle(Theme.textBody)
                }
                if let v = item.verification { VerificationView(verification: v) }
                if let other = item.conflictingGate {
                    Label(L("前後兩次廣播聽到不同的登機門（\(item.reading.gate ?? "?") 和 \(other)），請看大螢幕確認。",
                            "Two announcements gave different gates (\(item.reading.gate ?? "?") and \(other)). Please check the board."),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.label).foregroundStyle(Theme.possible)
                } else if item.reading.gate != nil && !item.reading.gateIsCertain {
                    Text(L("登機門聽起來不太確定，請看大螢幕確認。")).font(Theme.body).foregroundStyle(Theme.possible)
                }
                Text(L("\(item.time.formatted(date: .omitted, time: .shortened)) \(AnnouncementLanguage.name(of: item.original))廣播",
                       "\(item.time.formatted(date: .omitted, time: .shortened)) \(AnnouncementLanguage.name(of: item.original)) announcement"))
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                Text("「\(item.original)」").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                if let translation = item.translation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("中文翻譯（Muse Spark Open，僅供參考）")).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        Text(translation).font(Theme.body).foregroundStyle(Theme.textPrimary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.brandTint, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
                }
                if item.acknowledged {
                    Label(L("已確認"), systemImage: "checkmark.circle.fill")
                        .font(Theme.label).foregroundStyle(Theme.confirmed)
                        .transition(.opacity)
                } else {
                    // Same weight for both answers, so neither feels like the "right" one. Only boarding
                    // calls offer "at the gate"; it also stops repeats and keeps later boarding calls quiet.
                    Button(L("我知道了")) { answer(.gotIt, item.id) }.buttonStyle(.sfPrimary)
                    if isBoardingCall && !atGate {
                        Button(L("我已經在登機門了")) { answer(.atGate, item.id) }.buttonStyle(.sfSecondary)
                    }
                }
                Button { askStaff() } label: {
                    Label(L("給地勤看大字卡"), systemImage: "person.fill.questionmark")
                }
                .buttonStyle(item.certainty == .maybe && !item.acknowledged ? .sfSecondary : .sfText)
            }
            .padding(20)
            .animation(.easeInOut(duration: Theme.base), value: item.acknowledged)
        }
        .background(tone.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusOverlay))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusOverlay).strokeBorder(tone.color, lineWidth: 2))
    }
}

/// One announcement in the log (M08: the translation opens with a spring, its text fades in).
struct BroadcastRow: View {
    let item: Heard
    let translate: () -> Void
    @State private var translating = false
    @State private var shown = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(item.time.formatted(date: .omitted, time: .shortened)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                Chip(text: AnnouncementLanguage.name(of: item.original))
                switch item.certainty {
                case .sure: Chip(text: L("你的航班"), color: Theme.info, background: Theme.infoBg)
                case .maybe: Chip(text: L("可能是你的"), color: Theme.possible, background: Theme.possibleBg)
                case .notYours: Chip(text: L("跟你無關"), color: Theme.textSecondary)
                }
                Spacer()
                if item.translation != nil {
                    Button(shown ? L("收起翻譯") : L("看翻譯")) { shown.toggle() }
                        .buttonStyle(SFButtonStyle(kind: .secondary)).fixedSize()
                } else if MuseSparkOpen.needsTranslation(item.original, into: AppLanguage.current == .en ? .english : .traditionalChinese) {
                    Button(translating ? L("翻譯中…") : L("翻譯")) {
                        translating = true
                        translate()
                    }
                    .buttonStyle(SFButtonStyle(kind: .secondary)).fixedSize()
                    .disabled(translating)
                }
            }
            Text(item.original).font(Theme.body)
                .foregroundStyle(item.certainty == .notYours ? Theme.textSecondary : Theme.textBody)
            if let translation = item.translation, shown {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("中文翻譯（Muse Spark Open）")).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    Text(translation).font(Theme.body).foregroundStyle(Theme.textPrimary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.brandTint, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .sfCard(padding: 16)
        .clipped()
        .animation(reduceMotion ? .easeOut(duration: Theme.fast) : .spring(response: 0.35, dampingFraction: 0.9), value: shown)
        .animation(reduceMotion ? .easeOut(duration: Theme.fast) : .spring(response: 0.35, dampingFraction: 0.9), value: item.translation)
    }
}

/// Screen 07: every announcement heard, newest first, with translations.
struct BroadcastLog: View {
    @ObservedObject var model: ListenerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("英日文廣播可以按「翻譯」。")).font(Theme.body).foregroundStyle(Theme.textSecondary)
                ForEach(model.heard) { item in BroadcastRow(item: item) { model.translate(item) } }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .background(Theme.page)
        .navigationTitle(L("廣播紀錄"))
    }
}

/// Full-screen card to show airport staff.
struct StaffCard: View {
    let text: (zh: String, en: String)
    /// What the app has heard so far, so staff know what to check. Orange only while it is unconfirmed.
    struct Have { let zh: String; let en: String; let sure: Bool }
    let have: Have?
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("請給地勤人員看・Please show to staff").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    Text(text.zh).font(Theme.staffCard).foregroundStyle(Theme.textPrimary)
                    Divider().overlay(Theme.border)
                    Text(text.en).font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.textBody)
                    Text("請寫下來或指給我看・Please write or point")
                        .font(Theme.label).sfNote(Theme.info, Theme.infoBg)
                }
                .padding(24)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusOverlay))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusOverlay).strokeBorder(Theme.borderStrong, lineWidth: 2))
                if let have {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("我目前收到的・What I have").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        Text(have.zh).font(Theme.heading).foregroundStyle(have.sure ? Theme.textPrimary : Theme.possible)
                        Text(have.en).font(Theme.body).foregroundStyle(Theme.textBody)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(have.sure ? Theme.brandTint : Theme.possibleBg, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard)
                        .strokeBorder(have.sure ? Theme.border : Theme.possible, lineWidth: 1))
                }
                Button(L("返回"), action: close).buttonStyle(.sfSecondary)
            }
            .padding(24)
        }
        .background(Theme.page)
    }
}

/// The user's flight as Taoyuan's live data shows it. A gate disagreement or stale data is labelled
/// 待確認, never shown as confirmed (M05: the gate changes with a numeric roll).
struct FlightCard: View {
    let flight: ADIPFlight?
    let updated: Date?
    let message: String?
    var conflict: (heard: String, data: String)?
    var stale = false

    var body: some View {
        if let f = flight {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(f.airline) \(f.code)").font(Theme.heading).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if stale {
                        Chip(text: L("? 資料可能過時"), color: Theme.possible, background: Theme.possibleBg, outlined: true)
                    } else if conflict != nil {
                        Chip(text: L("? 待確認"), color: Theme.possible, background: Theme.possibleBg, outlined: true)
                    } else {
                        Chip(text: L("✓ 機場資料"), color: Theme.confirmed, background: Theme.confirmedBg, outlined: true)
                    }
                }
                Text(L("\(f.terminal) 台北桃園  →  \(f.placeZh) \(f.placeEn)", "\(f.terminal) Taipei Taoyuan  →  \(f.placeEn)")).font(Theme.body).foregroundStyle(Theme.textSecondary)
                HStack(alignment: .lastTextBaseline, spacing: 24) {
                    cell(L("登機門"), gateText, font: Theme.metric, color: conflict != nil || stale ? Theme.possible : Theme.textPrimary)
                    cell(L("表定起飛"), String(f.scheduled.suffix(5)))
                    if f.estimated != f.scheduled { cell(L("預計"), String(f.estimated.suffix(5))) }
                }
                Text(FlightStatusText.show(f.status) + (f.progress.map { "・" + FlightStatusText.show($0) } ?? "")).font(Theme.label).foregroundStyle(Theme.textBody)
                if !f.codeshares.isEmpty {
                    Text(L("共享班號：\(f.codeshares.joined(separator: "、"))", "Codeshares: \(f.codeshares.joined(separator: ", "))")).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                Text(footer).font(Theme.caption).foregroundStyle(conflict != nil || stale ? Theme.possible : Theme.textSecondary)
            }
            .sfCard(padding: 20)
        } else if let message {
            Text(message).font(Theme.body).foregroundStyle(Theme.textSecondary)
        }
    }

    private var gateText: String {
        if let conflict { return "\(conflict.data) / \(conflict.heard)" }
        return flight?.gate ?? L("未定")
    }

    private var footer: String {
        let time = updated.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—"
        if stale { return L("沒有網路：資料停在 \(time)，可能不是最新", "Offline: data from \(time), may be out of date") }
        if conflict != nil { return L("廣播和機場資料不一致，請看大螢幕或問地勤") }
        return L("資料來源：桃園機場即時航班・\(time) 更新（每 5 分鐘）", "Source: Taoyuan Airport live flight data · updated \(time) (every 5 min)")
    }

    private func cell(_ title: String, _ value: String, font: Font = Theme.heading, color: Color = Theme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            Text(value).font(font).foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: Theme.slow), value: value)
        }
    }
}

/// How an announcement compares with the flight data. Disagreement is shown, never hidden.
struct VerificationView: View {
    let verification: Verification

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch verification.gate {
            case .agrees(let g):
                Label(L("航班資料也是 \(g)", "The flight data says \(g) too"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.confirmed)
            case .fromData(let g):
                Label(L("廣播沒聽清楚登機門，航班資料顯示 \(g)", "The gate wasn't clear; the flight data shows \(g)"), systemImage: "airplane.circle").foregroundStyle(Theme.textBody)
            case .disagrees(let heard, let data):
                Label(L("廣播說 \(heard)，航班資料是 \(data)。廣播通常比資料早更新，請看大螢幕確認。",
                         "The announcement said \(heard), the flight data says \(data). Announcements usually come first; please check the board."),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.possible)
            case .unknown:
                EmptyView()
            }
            switch verification.status {
            case .agrees:
                Label(L("航班資料也顯示了這個變化"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.confirmed)
            case .notYetInData(let status):
                Label(L("航班資料還沒更新（目前顯示「\(status)」）", "Not in the flight data yet (it shows \u{201C}\(status)\u{201D})"), systemImage: "clock").foregroundStyle(Theme.textBody)
            case .notApplicable:
                EmptyView()
            }
        }
        .font(Theme.body)
    }
}
