import AVFoundation

/// Which microphone listens. The phone's own is the default: a Bluetooth hearing aid or headset mic
/// is usually worse at a distance, and is taken over by phone calls.
enum MicChoice: String, CaseIterable, Identifiable {
    case phone, external, bluetooth
    var id: String { rawValue }

    var title: String {
        switch self {
        case .phone: return "手機麥克風（建議）"
        case .external: return "外接麥克風（有線、USB-C 領夾）"
        case .bluetooth: return "藍牙（耳機、助聽器）"
        }
    }
}

/// Microphone → 16 kHz, 16-bit mono PCM chunks for Muse Voice Transcribe.
final class AudioCapture {
    /// A new engine for every start: an engine that has run keeps the microphone format it first saw, and
    /// after a switch to a Bluetooth mic, installing a tap with that stale format raised an exception and
    /// closed the app (AirPods test, Nov 1).
    private var engine = AVAudioEngine()
    private var configurationObserver: NSObjectProtocol?
    private var restart: (() -> Void)?
    /// When iOS reconfigures audio (switching to a Bluetooth mic, plugging one in) it stops the engine.
    /// Called after restarting for that, with the microphone now in use, or the error if it failed.
    var onReconfigured: ((Result<String, Error>) -> Void)?
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    /// `onChunk` gets about 85 ms of audio at a time; `onLevel` gets a 0...1 loudness for the meter.
    /// Returns the name of the microphone actually used (the chosen one may not be connected).
    @discardableResult
    func start(mic: MicChoice, onChunk: @escaping (Data) -> Void, onLevel: @escaping (Float) -> Void) throws -> String {
        // Remove the old tap: a second one raises an exception and ends the app. After a phone call iOS has
        // stopped the engine but the old tap is still installed (phone test, Nov 1).
        stopEngine()
        engine = AVAudioEngine()
        let session = AVAudioSession.sharedInstance()
        // The mic stays on in the background through the audio background mode; a wired or USB-C
        // lavalier mic becomes the input automatically.
        // Not .record: that category silences all audio output, and in phone tests it also silenced the
        // sound and vibration of the app's own notifications (banners showed, nothing was felt; LINE on the
        // same phone was fine). .playAndRecord keeps output alive; .mixWithOthers so starting to listen
        // doesn't stop the user's music or other apps.
        // Bluetooth as a microphone (HFP) only when chosen. Otherwise A2DP keeps music and sound going to
        // AirPods as output, while the input stays on the phone.
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [mic == .bluetooth ? .allowBluetoothHFP : .allowBluetoothA2DP,
                                          .mixWithOthers, .defaultToSpeaker])
        // iOS mutes all vibration and system sounds while an app records, so the mic doesn't pick them up.
        // For a deaf user the vibration *is* the alert, so it has to stay on (found in the first phone test).
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)
        let inputs = session.availableInputs ?? []
        let wanted: [AVAudioSession.Port] = switch mic {
        case .phone: [.builtInMic]
        case .external: [.headsetMic, .usbAudio, .lineIn]
        case .bluetooth: [.bluetoothHFP]
        }
        // Fall back to the phone's microphone when the chosen one isn't connected.
        let port = inputs.first { wanted.contains($0.portType) } ?? inputs.first { $0.portType == .builtInMic }
        if let port { try? session.setPreferredInput(port) }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Right after a call the microphone can report no format yet; installing a tap then also raises an
        // exception. Fail with an error instead, so the caller retries.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "AudioCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "麥克風還沒準備好"])
        }
        guard let converter = AVAudioConverter(from: format, to: target) else {
            throw NSError(domain: "AudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "無法轉換麥克風格式"])
        }
        let target = self.target
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / format.sampleRate) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var handedOver = false
            converter.convert(to: out, error: nil) { _, status in
                if handedOver {
                    status.pointee = .noDataNow
                    return nil
                }
                handedOver = true
                status.pointee = .haveData
                return buffer
            }
            guard out.frameLength > 0, let samples = out.int16ChannelData?[0] else { return }
            let count = Int(out.frameLength)
            onChunk(Data(bytes: samples, count: count * 2))

            var sum: Float = 0
            for i in 0..<count {
                let s = Float(samples[i]) / Float(Int16.max)
                sum += s * s
            }
            let db = 10 * log10(max(sum / Float(count), 1e-9))     // about -90 (silence) ... 0 (loud)
            onLevel(min(max((db + 60) / 60, 0), 1))
        }
        engine.prepare()
        try engine.start()

        // Switching to a Bluetooth mic happens a moment after start, and iOS then stops the engine: no audio
        // reached the server for 15 seconds and it closed the stream. Start again with the new format.
        restart = { [weak self] in
            guard let self else { return }
            do {
                let name = try self.start(mic: mic, onChunk: onChunk, onLevel: onLevel)
                self.onReconfigured?(.success(name))
            } catch {
                self.onReconfigured?(.failure(error))
            }
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restart?()
        }
        return session.currentRoute.inputs.first?.portName ?? port?.portName ?? "麥克風"
    }

    private func stopEngine() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    func stop() {
        stopEngine()
        restart = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
