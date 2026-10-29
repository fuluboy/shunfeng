// Development tool: streams a WAV file to Muse Voice Transcribe at real-time pace, like the app's
// microphone would, and prints how each announcement is read for the user's flight.
//
// Usage: META_API_KEY=... swift run shunfeng-listen <16kHz mono 16-bit WAV> <your flight, e.g. CI100>
import Foundation
import ShunfengCore

let args = CommandLine.arguments

// shunfeng-listen flight <code>...: look flights up in Taoyuan's live data (no API key needed).
if args.count >= 3, args[1] == "flight" {
    let flights = try await ADIP.fetch()
    print("ADIP: \(flights.count) flights")
    for code in args.dropFirst(2) {
        guard let f = ADIP.find(code, in: flights) else { print("\(code): not in today's data"); continue }
        print("\(f.code) \(f.kind == .departure ? "→" : "←") \(f.placeZh) \(f.placeEn) | \(f.terminal) gate \(f.gate ?? "-") | "
              + "scheduled \(f.scheduled) estimated \(f.estimated) | \(f.status) \(f.progress ?? "") | codeshares \(f.codeshares)")
    }
    exit(0)
}

// shunfeng-listen pass <photo.jpg>: read a boarding pass with Muse Spark, as the app does.
if args.count == 3, args[1] == "pass", let key = ProcessInfo.processInfo.environment["META_API_KEY"] {
    let started = Date()
    let pass = try await MetaModelAPI(apiKey: key).readBoardingPass(jpeg: try Data(contentsOf: URL(fileURLWithPath: args[2])))
    print(String(format: "%.1fs", Date().timeIntervalSince(started)), pass.flightCode ?? "-", pass.date ?? "-",
          "\(pass.from ?? "?")→\(pass.to ?? "?") (\(pass.destinationName ?? "-"))", "gate", pass.gate ?? "-",
          "boarding", pass.boardingTime ?? "-", "seat", pass.seat ?? "-",
          pass.handwrittenChanges.isEmpty ? "" : "| handwritten: \(pass.handwrittenChanges)")
    exit(0)
}

// shunfeng-listen eval <announcements.csv>: score the rules on the written announcement scripts
// (no speech recognition), as a traveler on CI100 to Tokyo would get them.
if args.count == 3, args[1] == "eval" {
    var rows = ADIP.csvRows(try String(contentsOfFile: args[2], encoding: .utf8))
    let header = rows.removeFirst().map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF} ")) }
    func column(_ name: String) -> Int { header.firstIndex(of: name)! }
    let user = UserFlight(code: "CI100", destination: "東京")
    var allRight = 0, notifyRight = 0, total = 0
    for row in rows where row.count == header.count {
        total += 1
        let r = AnnouncementRules.read(row[column("script")], myFlight: user.code)
        let notify: Bool
        if case .mine = r.match(for: user) { notify = true } else { notify = false }
        let expectNotify = row[column("should_notify")] == "True"
        // Only what the app shows the user is scored: for other flights, just that it stays quiet.
        var wrong: [String] = []
        if notify != expectNotify { wrong.append("notify \(notify)") }
        if expectNotify {
            if r.event?.rawValue != row[column("event")] { wrong.append("event \(r.event?.rawValue ?? "-")") }
            let gate = row[column("gate")], time = row[column("new_time")]
            if !gate.isEmpty && r.gate != gate { wrong.append("gate \(r.gate ?? "-")") }
            if !time.isEmpty && r.time != time { wrong.append("time \(r.time ?? "-")") }
        }
        if notify == expectNotify { notifyRight += 1 }
        if wrong.isEmpty { allRight += 1 } else { print("✗ \(row[column("id")]) \(wrong.joined(separator: ", ")) | \(row[column("script")])") }
    }
    print("notify right \(notifyRight)/\(total), everything right \(allRight)/\(total)")
    exit(0)
}

// shunfeng-listen translate "<text>": translate an announcement with Muse Spark Open, as the app does.
if args.count == 3, args[1] == "translate", let key = ProcessInfo.processInfo.environment["BASETEN_API_KEY"] {
    let started = Date()
    let text = try await MuseSparkOpen(apiKey: key).translate(args[2])
    print(String(format: "%.1fs", Date().timeIntervalSince(started)), text)
    exit(0)
}

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
