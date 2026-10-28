import Foundation

/// Streams microphone audio to Muse Voice Transcribe over its realtime WebSocket.
///
/// Audio goes out as raw 16-bit mono PCM in binary frames, paced at real time. In ENDPOINTING mode
/// the server splits speech into turns by itself, which suits announcements: each announcement
/// arrives as one `turnComplete`. Transcription stays neutral on purpose: no keywords about the
/// user's flight, because biasing made similar flight numbers come out as the user's flight.
public final class RealtimeTranscriber: @unchecked Sendable {

    public enum Event: Equatable, Sendable {
        case sessionStarted(id: String)
        case speechStarted(turn: Int)
        /// Text so far for the current turn (replaces the previous partial).
        case partial(String)
        /// Final text for one turn, ready for AnnouncementRules.
        case turnComplete(turn: Int, text: String)
        case error(String)
        case closed
    }

    public static let endpoint = URL(string: "wss://api.meta.ai/v1/asr/realtime")!
    public static let model = "muse-voice-transcribe-1.0"
    public static let sampleRate = 16_000

    private let apiKey: String
    private var task: URLSessionWebSocketTask?

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Opens the stream and starts delivering events. Returns once the handshake is sent;
    /// `sessionStarted` follows when the server accepts it.
    public func start(onEvent: @escaping @Sendable (Event) -> Void) async throws {
        let task = URLSession.shared.webSocketTask(with: Self.endpoint)
        self.task = task
        task.resume()

        // The handshake has to arrive within 10 seconds. Authorization goes in this first frame, not a header.
        let handshake: [String: Any] = [
            "authorization": ["accessToken": "Bearer \(apiKey)"],
            "audioEncoding": "PCM_16KHZ",
            "model": Self.model,
            "mode": "ENDPOINTING",
            "partialMode": "CUMULATIVE",
            "emitAudioProgress": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: handshake)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))

        Task { await Self.receive(from: task, onEvent: onEvent) }
    }

    /// Sends one chunk of 16 kHz, 16-bit little-endian mono PCM. Keep it close to real time:
    /// the server rejects streams that run more than five seconds ahead.
    public func send(pcm: Data) async throws {
        try await task?.send(.data(pcm))
    }

    /// Ends the audio. The server sends the last turn and then closes the socket.
    public func finish() async throws {
        try await task?.send(.string(#"{"type":"endStream"}"#))
    }

    public func cancel() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private static func receive(from task: URLSessionWebSocketTask, onEvent: @Sendable (Event) -> Void) async {
        while true {
            do {
                let message = try await task.receive()
                guard case .string(let text) = message, let event = parse(text) else { continue }
                onEvent(event)
            } catch {
                onEvent(.closed)
                return
            }
        }
    }

    /// Server messages are dispatched on `type`; unknown types are ignored as the docs ask.
    static func parse(_ text: String) -> Event? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return nil }
        switch json["type"] as? String {
        case nil:
            return (json["sessionId"] as? String).map { .sessionStarted(id: $0) }
        case "speechStart":
            return .speechStarted(turn: json["turnId"] as? Int ?? 0)
        case "transcript":
            return .partial(json["transcript"] as? String ?? "")
        case "speechComplete":
            return .turnComplete(turn: json["turnId"] as? Int ?? 0, text: json["transcript"] as? String ?? "")
        case "error":
            return .error(json["message"] as? String ?? text)
        default:
            return nil
        }
    }
}
