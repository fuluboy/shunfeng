import SwiftUI
import UserNotifications

@main
struct ShunfengApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Answers from the buttons on notifications and alert cards, passed to ListenerModel.
enum UrgentAnswer: String {
    case gotIt = "GOT_IT"
    case atGate = "AT_GATE"
    /// The flight was cancelled or moved to another day, and the user has seen it.
    case flightEndSeen = "FLIGHT_END_SEEN"
    case stopListening = "STOP_LISTENING"
    case keepListening = "KEEP_LISTENING"

    /// Boarding and final calls: "got it" and "I'm at the gate". Everything else only has "got it",
    /// since most news (a delay, a cancellation) has nothing to do with being at the gate.
    static let boardingCategory = "BOARDING"
    static let generalCategory = "GENERAL"
    /// "Your flight was cancelled": seen first, then asked about stopping.
    static let flightEndCategory = "FLIGHT_END"
    static let askStopCategory = "ASK_STOP"
    static let notification = Notification.Name("ShunfengUrgentAnswer")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Boarding and final calls repeat until answered. These buttons work from the lock screen,
        // so someone already sitting at the gate can stop them without opening the app.
        let gotIt = UNNotificationAction(identifier: UrgentAnswer.gotIt.rawValue, title: "我知道了")
        let atGate = UNNotificationAction(identifier: UrgentAnswer.atGate.rawValue, title: "我已經在登機門了")
        let seen = UNNotificationAction(identifier: UrgentAnswer.flightEndSeen.rawValue, title: "我知道了")
        let stop = UNNotificationAction(identifier: UrgentAnswer.stopListening.rawValue, title: "停止聆聽")
        let keep = UNNotificationAction(identifier: UrgentAnswer.keepListening.rawValue, title: "繼續聆聽")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: UrgentAnswer.flightEndCategory, actions: [seen], intentIdentifiers: []),
            UNNotificationCategory(identifier: UrgentAnswer.askStopCategory, actions: [stop, keep], intentIdentifiers: []),
            UNNotificationCategory(identifier: UrgentAnswer.boardingCategory, actions: [gotIt, atGate], intentIdentifiers: []),
            UNNotificationCategory(identifier: UrgentAnswer.generalCategory, actions: [gotIt], intentIdentifiers: []),
        ])
        return true
    }

    /// Shows alerts as banners even while the app is open, so a vibration always comes with text.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let answer = UrgentAnswer(rawValue: response.actionIdentifier) else { return }
        let heardID = response.notification.request.content.userInfo["heardID"] as? String
        await MainActor.run {
            NotificationCenter.default.post(name: UrgentAnswer.notification, object: answer,
                                            userInfo: heardID.map { ["heardID": $0] })
        }
    }
}
