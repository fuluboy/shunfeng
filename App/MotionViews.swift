import SwiftUI

// Motion from the Figma page "Motion" (25:113). Every piece has a Reduce Motion version, and none of
// them carries information that isn't also in words on the screen.

/// M01 — the listening ring. Three cyan waves leave the center every second and fade out over 3 s,
/// so the user can see the app is listening. When a relevant announcement is being checked, the
/// waves stop and the center turns solid.
struct ListeningRing: View {
    var detected = false
    var size: CGFloat = 128
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if reduceMotion {
                // No movement: the rings stay put and slowly brighten and dim (3 s), still saying "listening".
                TimelineView(.animation(paused: detected)) { context in
                    let pulse = 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / 3)
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            Circle().stroke(Theme.accent.opacity(0.2 + 0.4 * pulse), lineWidth: 2)
                                .scaleEffect(1.2 + CGFloat(i) * 0.25)
                        }
                    }
                }
                .opacity(detected ? 0 : 1)
            } else {
                TimelineView(.animation(paused: detected)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            let phase = ((t + Double(i)).truncatingRemainder(dividingBy: 3)) / 3
                            Circle().stroke(Theme.accent, lineWidth: 2)
                                .scaleEffect(1 + 0.9 * phase)
                                .opacity(0.7 * (1 - phase))
                        }
                    }
                }
                .opacity(detected ? 0 : 1)
            }
            Circle()
                .stroke(Theme.brand, lineWidth: detected ? 6 : 2)
                .scaleEffect(detected ? 1.18 : 1)
                .opacity(detected ? 1 : 0)
            Circle()
                .fill(detected ? Theme.brand : Theme.brandTint)
                .overlay(Circle().strokeBorder(Theme.brand, lineWidth: 2))
            // The character 聽 ("listen") in Chinese; an ear in English.
            Group {
                if AppLanguage.current == .zh { Text("聽") } else { Image(systemName: "ear") }
            }
                .font(Theme.title)
                .foregroundStyle(detected ? Theme.onBrand : Theme.textPrimary)
        }
        .frame(width: size, height: size)
        .frame(width: size * 1.9, height: size * 1.9)
        .animation(reduceMotion ? nil : .easeOut(duration: Theme.slow), value: detected)
        .accessibilityElement()
        .accessibilityLabel(detected ? L("聽到可能相關的廣播，正在核對") : L("正在聽機場廣播"))
    }
}

/// M03 — the vibration on screen. Dots light up in step with Haptics: a 500 ms buzz every 850 ms.
/// After counting, all dots stay filled so the count can still be read later. "Cancelled" is one
/// long bar that fills over 1.5 s.
struct VibrationDots: View {
    let level: Haptics.Level
    var color: Color = Theme.onBrand
    /// Play in step with a vibration happening now; otherwise just show the pattern.
    var play = false
    var dot: CGFloat = 9
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = 0
    @State private var glowing = -1
    @State private var barFill: CGFloat = 0

    var body: some View {
        HStack(spacing: dot * 0.6) {
            if level == .cancelled {
                Capsule().fill(color.opacity(0.3))
                    .overlay(alignment: .leading) {
                        GeometryReader { g in Capsule().fill(color).frame(width: g.size.width * barFill) }
                    }
                    .frame(width: dot * 4, height: dot * 0.7)
            } else {
                ForEach(0..<level.dots, id: \.self) { i in
                    Circle()
                        .fill(i < filled ? color : color.opacity(0.3))
                        .frame(width: dot, height: dot)
                        .scaleEffect(glowing == i ? 1.2 : 1)
                        .shadow(color: glowing == i ? color.opacity(0.9) : .clear, radius: 4)
                }
            }
        }
        .accessibilityHidden(true)
        .task(id: play) { await run() }
    }

    private func run() async {
        guard play, !reduceMotion else {
            filled = level.dots
            barFill = 1
            return
        }
        filled = 0
        barFill = 0
        if level == .cancelled {
            withAnimation(.linear(duration: 1.5)) { barFill = 1 }
            return
        }
        for i in 0..<level.dots {
            withAnimation(.easeOut(duration: 0.08)) { filled = i + 1; glowing = i }
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeIn(duration: 0.12)) { glowing = -1 }
            try? await Task.sleep(for: .milliseconds(350))
        }
    }
}

/// The vibration language, taught where it is needed. Tapping a cell plays it (M12 reuses M03).
struct VibrationLegend: View {
    let tryIt: (Haptics.Level) -> Void
    @State private var playing: Haptics.Level?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("震動代表什麼（點一下試試）")).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                ForEach(Haptics.Level.all, id: \.self) { level in
                    Button {
                        guard playing == nil else { return }
                        playing = level
                        tryIt(level)
                        Task {
                            try? await Task.sleep(for: .milliseconds(level == .cancelled ? 1600 : level.dots * 850))
                            playing = nil
                        }
                    } label: {
                        VStack(spacing: 6) {
                            VibrationDots(level: level, color: level.color, play: playing == level)
                                .frame(height: 14)
                            Text(level.meaning).font(Theme.caption).foregroundStyle(Theme.textBody)
                        }
                        .frame(maxWidth: .infinity, minHeight: Theme.touchLarge)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl)
                            .strokeBorder(playing == level ? level.color : Theme.border, lineWidth: playing == level ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("\(level.spoken)：\(level.meaning)。點一下試試", "\(level.spoken): \(level.meaning). Tap to try"))
                }
            }
        }
    }
}

/// The backdrop of every popup: blurred and dimmed, and it takes every tap, so only the popup's own
/// buttons do anything and the user can focus on it.
struct ModalBackdrop: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(0.45))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {}
            .accessibilityHidden(true)
    }
}

/// A boarding pass being read: a cyan line sweeps over the pass, top to bottom and back, like a scan
/// (ambient loop, 1.6 s each way). With Reduce Motion the line stays in the middle and slowly fades in
/// and out instead, so the popup still shows that work is going on.
struct PassScanAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Driven by the clock rather than a repeating animation started on appear, which a popup's own
        // entrance animation can swallow.
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = t.truncatingRemainder(dividingBy: 3.2) / 3.2
            let tri = phase < 0.5 ? phase * 2 : 2 - phase * 2
            let eased = tri * tri * (3 - 2 * tri)
            let pulse = 0.5 + 0.5 * sin(t * 2 * .pi / 1.6)
            pass(lineY: reduceMotion ? 44 : 6 + 78 * eased, lineOpacity: reduceMotion ? 0.3 + 0.7 * pulse : 1)
        }
        .frame(width: 140, height: 94)
        .accessibilityHidden(true)
    }

    private func pass(lineY: CGFloat, lineOpacity: Double) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: Theme.radiusOverlay)
                .fill(Theme.brandTint)
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusOverlay).strokeBorder(Theme.brand, lineWidth: 2))
            Image(systemName: "airplane")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.brand)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Capsule()
                .fill(Theme.accent)
                .frame(height: 4)
                .shadow(color: Theme.accent.opacity(0.9), radius: 6)
                .padding(.horizontal, 8)
                .opacity(lineOpacity)
                .offset(y: lineY)
        }
    }
}

/// M07 — the status bar at the top. Colors cross-fade in 250 ms and the icon swaps with a symbol
/// effect; only "reconnecting" moves continuously.
struct StatusBanner: View {
    enum Kind: Equatable {
        case listening(String?), connecting, paused, offline, failed(String), stopped(String)
    }

    let kind: Kind
    var action: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            GlyphBadge(symbol: symbol, color: tint)
                .symbolEffect(.pulse, options: .repeating, isActive: kind == .connecting && !reduceMotion)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.label).foregroundStyle(isNeutral ? Theme.textPrimary : tint)
                Text(subtitle).font(Theme.caption).foregroundStyle(Theme.textBody)
            }
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SFButtonStyle(kind: isNeutral ? .secondary : .primary))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(borderColor, lineWidth: borderWidth))
        .animation(.easeInOut(duration: Theme.base), value: kind)
        .accessibilityElement(children: .combine)
    }

    private var isNeutral: Bool {
        switch kind {
        case .listening, .connecting, .stopped: true
        default: false
        }
    }

    private var borderColor: Color {
        switch kind {
        case .listening, .connecting: Theme.border
        case .stopped: Theme.borderStrong
        default: tint
        }
    }

    /// Stopped and every problem state keep a 2 pt outline, so they stand out from normal listening.
    private var borderWidth: CGFloat {
        switch kind {
        case .listening, .connecting: 1
        default: 2
        }
    }

    private var symbol: String {
        switch kind {
        case .listening: "waveform"
        case .connecting: "arrow.clockwise"
        case .paused: "phone.fill"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark"
        case .stopped: "stop.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .listening: Theme.confirmed
        case .connecting: Theme.brand
        case .paused: Theme.possible
        case .offline, .failed: Theme.critical
        case .stopped: Theme.textSecondary
        }
    }

    private var background: Color {
        switch kind {
        case .listening, .connecting: Theme.brandTint
        case .paused: Theme.possibleBg
        case .offline, .failed: Theme.criticalBg
        case .stopped: Theme.subtle
        }
    }

    private var title: String {
        switch kind {
        case .listening: L("正在聆聽廣播")
        case .connecting: L("連線中…")
        case .paused: L("通話中，暫停聆聽")
        case .offline: L("沒有網路")
        case .failed: L("連不上語音服務")
        case .stopped: L("已停止聆聽")
        }
    }

    private var subtitle: String {
        switch kind {
        case .listening(let mic): mic.map { L("收音：\($0)・鎖屏也會繼續聽", "Mic: \($0) · keeps listening when locked") } ?? L("鎖屏也會繼續聽")
        case .connecting: L("馬上就好")
        case .paused: L("通話結束後自動恢復，這段時間請看大螢幕")
        case .offline: L("現在聽不到廣播，請看大螢幕。網路恢復後自動繼續")
        case .failed(let message): message
        case .stopped(let message): message
        }
    }

    private var actionTitle: String? {
        switch kind {
        case .listening: L("停止")
        case .failed: L("重新連線")
        case .stopped: L("開始聆聽")
        default: nil
        }
    }
}
