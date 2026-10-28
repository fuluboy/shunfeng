import CoreHaptics
import ShunfengCore

/// A vibration language: each kind of announcement feels different, so a deaf traveler can tell
/// "final call" from "gate change" with the phone still in a pocket.
final class Haptics {
    private var engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    /// A single soft tap: "something might be about you, take a look".
    func maybe() {
        play([tap(at: 0, intensity: 0.5, sharpness: 0.3)])
    }

    func confirmed(_ event: AnnouncementEvent) {
        switch event {
        case .gateChange:   // three sharp taps
            play([0, 0.18, 0.36].map { tap(at: $0, intensity: 1, sharpness: 0.9) })
        case .delay, .timeChange:   // two long pulses
            play([buzz(at: 0, duration: 0.45), buzz(at: 0.7, duration: 0.45)])
        case .boarding:     // two medium taps, twice
            play([0, 0.15, 0.6, 0.75].map { tap(at: $0, intensity: 0.8, sharpness: 0.6) })
        case .finalCall:    // rapid, strong, urgent
            play((0..<8).map { tap(at: Double($0) * 0.12, intensity: 1, sharpness: 1) })
        case .cancel:       // one long heavy buzz
            play([buzz(at: 0, duration: 1.2)])
        case .nameCall:     // long, short, long
            play([buzz(at: 0, duration: 0.4), tap(at: 0.55, intensity: 1, sharpness: 0.8), buzz(at: 0.75, duration: 0.4)])
        case .info:
            break
        }
    }

    private func tap(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time)
    }

    private func buzz(at time: TimeInterval, duration: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
        ], relativeTime: time, duration: duration)
    }

    private func play(_ events: [CHHapticEvent]) {
        guard let engine, let pattern = try? CHHapticPattern(events: events, parameters: []) else { return }
        try? engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
    }
}
