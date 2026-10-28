import Foundation
import UIKit

/// Appends one JSON line per event to Documents/shunfeng-log.jsonl, so a test session can be
/// reviewed afterwards (pull it with `xcrun devicectl device copy from ... --domain-type appDataContainer`).
/// It records what was heard and decided, and whether the app was in the foreground, which is what
/// "it didn't vibrate with the screen off" questions need.
enum EventLog {
    static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("shunfeng-log.jsonl")
    private static let queue = DispatchQueue(label: "EventLog")
    private static let formatter = ISO8601DateFormatter()

    @MainActor
    static func write(_ kind: String, _ fields: [String: Any] = [:]) {
        let appState: String
        switch UIApplication.shared.applicationState {
        case .active: appState = "foreground"
        case .background: appState = "background"
        default: appState = "inactive"
        }
        var entry = fields
        entry["kind"] = kind
        entry["time"] = formatter.string(from: Date())
        entry["app"] = appState
        queue.async {
            guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data + Data("\n".utf8))
                try? handle.close()
            } else {
                try? (data + Data("\n".utf8)).write(to: url)
            }
        }
    }
}
