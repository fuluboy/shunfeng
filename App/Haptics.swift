import CoreHaptics
import ShunfengCore

/// The vibration language: four levels, told apart by counting long pulses.
///
/// The first version had seven patterns built from short taps. On the phone the taps were barely
/// noticeable, and seven rhythms are too many to remember in a hurry. Now every pulse is long and
/// at full strength, and the count says how urgent it is; the details are on the screen.
///
/// iOS only plays these while the app is on screen. In the background the system notification
/// vibration is used instead, and urgent alerts repeat (see ListenerModel).
final class Haptics {

    enum Level {
        case maybe       // ●        might be about you, take a look
        case change      // ● ●      gate change, delay, new time, name call
        case actNow      // ● ● ●    boarding, final call
        case cancelled   // ━━━━     flight cancelled

        init(_ event: AnnouncementEvent) {
            switch event {
            case .boarding, .finalCall: self = .actNow
            case .cancel: self = .cancelled
            default: self = .change
            }
        }
    }

    private var engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    func play(_ level: Level) {
        switch level {
        case .maybe: pulses(1)
        case .change: pulses(2)
        case .actNow: pulses(3)
        case .cancelled: play([buzz(at: 0, duration: 1.5)])
        }
    }

    /// Long pulses with clear gaps, so they can be counted through a pocket.
    private func pulses(_ count: Int) {
        play((0..<count).map { buzz(at: Double($0) * 0.85, duration: 0.5) })
    }

    private func buzz(at time: TimeInterval, duration: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),   // a duller rumble is easier to feel
        ], relativeTime: time, duration: duration)
    }

    private func play(_ events: [CHHapticEvent]) {
        guard let engine, let pattern = try? CHHapticPattern(events: events, parameters: []) else { return }
        try? engine.start()
        try? engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
    }
}
