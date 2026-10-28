import ShunfengCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = ListenerModel()
    @State private var showingStaffCard = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    flightSetup
                    listenButton
                    vibrationMenu
                    statusLine
                    if model.atGate {
                        HStack {
                            Label("你已在登機門，登機廣播不再震動提醒", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button("取消") { model.atGate = false }
                        }
                        .font(.callout)
                    }
                    if let item = model.latestSure {
                        AlertCard(item: item, atGate: model.atGate, answer: { model.answer($0, heardID: $1) }) { showingStaffCard = true }
                    }
                    if let item = model.latestMaybe {
                        AlertCard(item: item, atGate: model.atGate, answer: { model.answer($0, heardID: $1) }) { showingStaffCard = true }
                    }
                    if !model.heard.isEmpty {
                        Text("聽到的廣播（原文）").font(.headline).padding(.top, 8)
                        ForEach(model.heard) { HeardRow(item: $0) }
                    }
                }
                .padding()
            }
            .navigationTitle("Shunfeng 順風")
            .fullScreenCover(isPresented: $showingStaffCard) {
                StaffCard(text: model.staffCard(for: (model.latestSure ?? model.latestMaybe)?.reading)) { showingStaffCard = false }
            }
            .onChange(of: scenePhase) { _, phase in
                EventLog.write("scene", ["phase": "\(phase)"])
                if phase == .active { model.cancelUrgentRepeats() }
            }
        }
    }

    private var flightSetup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("你的班機").font(.headline)
            TextField("班號，例如 CI100", text: $model.flightCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            TextField("目的地，例如 東京", text: $model.destination)
                .textFieldStyle(.roundedBorder)
        }
        .disabled(model.state != .idle && !isFailed)
    }

    private var isFailed: Bool {
        if case .failed = model.state { return true }
        return false
    }

    private var listenButton: some View {
        Button {
            if model.state == .idle || isFailed { model.start() } else { model.userStop() }
        } label: {
            Label(model.state == .idle || isFailed ? "開始聆聽廣播" : "停止",
                  systemImage: model.state == .idle || isFailed ? "ear" : "stop.fill")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.state == .idle || isFailed ? .blue : .red)
        .disabled(model.flightCode.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// Feel each vibration pattern, so the user learns the "vibration language" before the trip.
    private var vibrationMenu: some View {
        Menu {
            Button("可能跟你有關：震 1 下") { model.tryVibration(.maybe) }
            Button("變更（登機門、延誤、找人）：震 2 下") { model.tryVibration(.change) }
            Button("馬上行動（登機、最後登機）：震 3 下") { model.tryVibration(.actNow) }
            Button("班機取消：一長震") { model.tryVibration(.cancelled) }
        } label: {
            Label("試試震動語言", systemImage: "iphone.radiowaves.left.and.right")
                .font(.callout)
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .connecting:
            Label("連線中…", systemImage: "antenna.radiowaves.left.and.right")
        case .listening:
            VStack(alignment: .leading, spacing: 6) {
                Label("聆聽中。手機放口袋也可以，有你的消息會震動。", systemImage: "waveform")
                ProgressView(value: Double(model.level)).tint(model.level < 0.15 ? .orange : .green)
                if !model.partial.isEmpty {
                    Text(model.partial).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }
}

/// The big card for the newest announcement about the user's flight.
struct AlertCard: View {
    let item: Heard
    let atGate: Bool
    let answer: (UrgentAnswer, UUID) -> Void
    let askStaff: () -> Void

    private var isBoardingCall: Bool {
        item.certainty == .sure && [.boarding, .finalCall].contains(item.reading.event)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.certainty == .sure ? "確定" : "可能")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(item.certainty == .sure ? Color.green : Color.orange, in: Capsule())
                    .foregroundStyle(.white)
                if item.confirmations > 1 {
                    Label("聽到 \(item.confirmations) 次，內容一致", systemImage: "checkmark.seal")
                        .font(.caption)
                }
                Spacer()
                Text(item.time, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            if item.certainty == .sure {
                Text(ListenerModel.headline(for: item.reading))
                    .font(.system(size: 34, weight: .bold))
            } else {
                // Don't shout "Final call!" when we are not sure it is the user's flight.
                Text("可能跟你有關，請確認")
                    .font(.system(size: 28, weight: .bold))
                Text("廣播內容：\(ListenerModel.headline(for: item.reading))")
                    .font(.title3)
            }
            if let note = item.note {
                Text(note)
            }
            if item.certainty == .maybe {
                Label("把手機拿在手上、朝向廣播喇叭，下一次廣播會聽得更清楚。", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.callout)
            }
            if let other = item.conflictingGate {
                Label("前後兩次廣播聽到不同的登機門（\(item.reading.gate ?? "?") 和 \(other)），請看大螢幕確認。",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(.orange)
            } else if item.reading.gate != nil && !item.reading.gateIsCertain {
                Text("登機門聽起來不太確定，請看大螢幕確認。").font(.callout)
            }
            Text("「\(item.original)」").font(.footnote).foregroundStyle(.secondary)
            HStack {
                Label("到大螢幕確認", systemImage: "display")
                Spacer()
                Button("問地勤", systemImage: "person.fill.questionmark", action: askStaff)
                    .buttonStyle(.bordered)
            }
            .font(.callout)
            if item.acknowledged {
                Label("已確認", systemImage: "checkmark.circle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(.green)
            } else {
                // Same look for both answers, so neither feels like the "right" one. Only boarding calls
                // offer "at the gate"; it also stops repeats and keeps later boarding calls quiet.
                HStack(spacing: 12) {
                    Button { answer(.gotIt, item.id) } label: {
                        Text("我知道了").frame(maxWidth: .infinity)
                    }
                    if isBoardingCall && !atGate {
                        Button { answer(.atGate, item.id) } label: {
                            Text("我已經在登機門了").frame(maxWidth: .infinity)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .font(.callout.bold())
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(item.certainty == .sure ? Color.green : Color.orange, lineWidth: 3))
    }
}

struct HeardRow: View {
    let item: Heard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.reading.flight ?? "—").font(.caption.bold())
                Text(item.certainty == .notYours ? "不是你的班機" : (item.certainty == .sure ? "你的班機" : "可能是你的"))
                    .font(.caption)
                    .foregroundStyle(item.certainty == .notYours ? .secondary : .primary)
                Spacer()
                Text(item.time, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            Text(item.original).font(.footnote).foregroundStyle(item.certainty == .notYours ? .secondary : .primary)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Full-screen card to show airport staff.
struct StaffCard: View {
    let text: (zh: String, en: String)
    let close: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text(text.zh).font(.system(size: 40, weight: .bold)).multilineTextAlignment(.center)
            Text(text.en).font(.system(size: 30, weight: .semibold)).multilineTextAlignment(.center)
            Spacer()
            Button("關閉", action: close).font(.title2).buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.yellow.opacity(0.25))
    }
}
