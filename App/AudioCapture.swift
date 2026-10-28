import AVFoundation

/// Microphone → 16 kHz, 16-bit mono PCM chunks for Muse Voice Transcribe.
final class AudioCapture {
    private let engine = AVAudioEngine()
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    /// `onChunk` gets about 85 ms of audio at a time; `onLevel` gets a 0...1 loudness for the meter.
    func start(onChunk: @escaping (Data) -> Void, onLevel: @escaping (Float) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        // .record keeps the mic on in the background (with the audio background mode); a wired or
        // USB-C lavalier mic becomes the input automatically.
        try session.setCategory(.record, mode: .default, options: [.allowBluetoothHFP])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
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
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
