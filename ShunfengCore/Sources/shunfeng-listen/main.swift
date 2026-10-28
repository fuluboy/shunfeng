// Development tool: streams a WAV file to Muse Voice Transcribe at real-time pace, like the app's
// microphone would, and prints how each announcement is read for the user's flight.
//
// Usage: META_API_KEY=... swift run shunfeng-listen <16kHz mono 16-bit WAV> <your flight, e.g. CI100>
import Foundation
import ShunfengCore

let args = CommandLine.arguments
guard args.count == 3, let apiKey = ProcessInfo.processInfo.environment["META_API_KEY"] else {
    FileHandle.standardError.write(Data("usage: META_API_KEY=... shunfeng-listen <file.wav> <flight>\n".utf8))
    exit(2)
}
let myFlight = args[2]

/// Returns the PCM payload of a WAV file (the "data" chunk). afconvert adds extra chunks,
/// so the header is not always 44 bytes.
func pcmPayload(of url: URL) throws -> Data {
    let wav = try Data(contentsOf: url)
    var offset = 12
    while offset + 8 <= wav.count {
        let id = String(decoding: wav[offset..<offset + 4], as: UTF8.self)
        let size = wav[offset + 4..<offset + 8].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        if id == "data" { return wav[offset + 8..<min(offset + 8 + size, wav.count)] }
        offset += 8 + size + (size & 1)
    }
    throw NSError(domain: "shunfeng-listen", code: 1, userInfo: [NSLocalizedDescriptionKey: "no data chunk"])
}

let pcm = try pcmPayload(of: URL(fileURLWithPath: args[1]))
let transcriber = RealtimeTranscriber(apiKey: apiKey)
let (closed, closedSignal) = AsyncStream<Void>.makeStream()
let started = Date()

try await transcriber.start { event in
    let t = String(format: "%5.1fs", Date().timeIntervalSince(started))
    switch event {
    case .sessionStarted:
        print("\(t)  connected")
    case .turnComplete(let turn, let text):
        let r = AnnouncementRules.read(text, myFlight: myFlight)
        let mine = r.flight == AnnouncementRules.normalizeFlight(myFlight)
        print("\(t)  turn \(turn): \(text)")
        print("        → flight \(r.flight ?? "-")  event \(r.event?.rawValue ?? "unsure")  gate \(r.gate ?? "-")\(r.gateIsCertain ? "" : "?")  time \(r.time ?? "-")  \(mine ? "★ YOUR FLIGHT" : "")")
    case .error(let message):
        print("\(t)  error: \(message)")
    case .closed:
        print("\(t)  closed")
        closedSignal.finish()
    case .speechStarted, .partial:
        break
    }
}

// 80 ms chunks, sent at real time.
let chunkBytes = RealtimeTranscriber.sampleRate * 2 * 80 / 1000
var offset = pcm.startIndex
while offset < pcm.endIndex {
    let end = min(offset + chunkBytes, pcm.endIndex)
    try await transcriber.send(pcm: pcm[offset..<end])
    offset = end
    try await Task.sleep(nanoseconds: 80_000_000)
}
try await transcriber.finish()
for await _ in closed {}
