import Foundation

/// The app's two languages. Chinese is what the app is written in; English comes from the table below.
/// The choice is the app's own (Settings), so it can be switched on the spot, e.g. while recording a demo.
enum AppLanguage: String, CaseIterable, Identifiable {
    case zh, en
    var id: String { rawValue }

    static let key = "appLanguage"

    /// The user's choice, or the phone's language when they haven't chosen: Chinese for any Chinese
    /// setting, English otherwise.
    static var current: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: key), let chosen = AppLanguage(rawValue: raw) { return chosen }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en
    }

    var name: String { self == .zh ? "繁體中文" : "English" }
}

/// Text in the current language, for text without values in it: the Chinese is looked up in the table.
func L(_ zh: String) -> String {
    AppLanguage.current == .zh ? zh : (english[zh] ?? zh)
}

/// Text with values in it, written out in both languages where it is used.
func L(_ zh: String, _ en: String) -> String {
    AppLanguage.current == .zh ? zh : en
}

/// A transcript as shown to the reader. Speech recognition writes Mandarin in Simplified characters; Chinese
/// readers in Taiwan get Traditional (the rules only convert the few characters they need).
func readable(_ transcript: String) -> String {
    guard AppLanguage.current == .zh else { return transcript }
    return transcript.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? transcript
}

/// Taoyuan's flight data is in Chinese; its statuses, shown in the reader's language.
enum FlightStatusText {
    static let english = [
        "準時": "On time", "改時": "Time changed", "延遲": "Delayed", "取消": "Cancelled", "出發": "Departed",
        "已到": "Arrived", "開始登機": "Boarding", "最後登機": "Final call", "登機結束": "Gate closed",
        "已飛": "Departed", "抵達機坪": "At the gate",
    ]

    static func show(_ status: String) -> String {
        AppLanguage.current == .zh ? status : (english[status] ?? status)
    }
}

private let english: [String: String] = [
        "手機麥克風（建議）": "Phone microphone (recommended)",
        "外接麥克風（有線、USB-C 領夾）": "External mic (wired or USB-C clip-on)",
        "藍牙（耳機、助聽器）": "Bluetooth (earbuds, hearing aids)",
        "麥克風": "Microphone",
        "麥克風還沒準備好": "The microphone isn't ready yet",
        "無法轉換麥克風格式": "Can't convert the microphone's audio format",
        "從照片讀到的內容，請檢查一次。": "Read from your photo. Please check it once.",
        "班號": "Flight",
        "日期": "Date",
        "航線": "Route",
        "登機門": "Gate",
        "登機時間": "Boarding",
        "起飛時間": "Departure time",
        "起飛": "Departure",
        "座位": "Seat",
        "由 Meta 的 Muse Spark 從照片讀出。": "Read from the photo by Meta's Muse Spark.",
        "資料正確，使用這班": "Looks right, use this flight",
        "重拍": "Retake",
        "確認登機證資料": "Check your boarding pass",
        "手寫修改": "Handwritten change",
        "讀不到": "Not found",
        "讀不出登機證": "Couldn't read the boarding pass",
        "照片要清楚、不反光，整張登機證都在畫面裡。": "Use a clear photo without glare, with the whole pass in the frame.",
        "改成手動輸入班號": "Enter the flight by hand",
        "正在讀取登機證": "Reading your boarding pass",
        "Muse Spark 正在從照片讀出班號、日期與登機門，通常要幾秒鐘。讀完會請你確認一次。": "Muse Spark is reading the flight, date and gate from the photo. It usually takes a few seconds, then you check it once.",
        "正在讀取登機證，請稍候": "Reading your boarding pass, please wait",
        "這是機場航班資料的變化，廣播可能沒聽到。請看大螢幕確認。": "This change comes from the airport's flight data; the announcement may have been missed. Please check the departure board.",
        "你已在登機門，登機廣播不再震動提醒": "You're at the gate: boarding calls won't buzz anymore",
        "順風 Shunfeng": "Shunfeng",
        "設定": "Settings",
        "我知道了": "Got it",
        "停止聆聽": "Stop listening",
        "繼續聆聽": "Keep listening",
        "照片裡找不到班號，可能不是登機證，或照片不夠清楚。": "No flight number in this photo. It may not be a boarding pass, or it isn't clear enough.",
        "重新選照片": "Choose another photo",
        "今天搭哪一班？": "Which flight today?",
        "只在廣播跟你的航班有關時，才震動提醒你。": "Your phone buzzes only when an announcement is about your flight.",
        "聽到可能相關的廣播，正在核對": "Heard something that may be yours, checking",
        "正在聽機場廣播": "Listening to airport announcements",
        "收音很小": "Sound is faint",
        "收音正常": "Sound level OK",
        "例如 CI100": "e.g. CI100",
        "目的地": "Destination",
        "例如 東京": "e.g. Tokyo",
        "拍登機證": "Scan boarding pass",
        "從相簿選": "From photos",
        "清除": "Clear",
        "登機證只印登機時間，起飛時間是推估的（登機後 30 分鐘），請確認。": "The pass only shows boarding time, so departure is estimated (30 minutes later). Please check.",
        "設定起飛時間": "Set departure time",
        "要停止聆聽嗎？": "Stop listening?",
        "開始聆聽廣播": "Start listening",
        "目前沒有網路，無法聆聽。請打開 Wi-Fi 或行動網路。": "No internet, so Shunfeng can't listen. Turn on Wi-Fi or mobile data.",
        "連不上語音辨識服務。如果連的是機場 Wi-Fi，請先打開瀏覽器完成登入（按「同意」）。": "Can't reach the speech service. On airport Wi-Fi, open your browser and finish signing in (tap \"Agree\") first.",
        "重新檢查": "Check again",
        "可能・請確認": "Maybe · please check",
        "最後登機・馬上行動": "Final call · go now",
        "開始登機・馬上行動": "Boarding · go now",
        "班機取消": "Flight cancelled",
        "確定・登機門變更": "Confirmed · gate change",
        "確定・時間變更": "Confirmed · time change",
        "確定": "Confirmed",
        "可能跟你有關，請確認": "May be about you, please check",
        "把手機拿在手上、朝向廣播喇叭，下一次廣播會聽得更清楚。": "Hold your phone toward the speaker to hear the next announcement better.",
        "登機門聽起來不太確定，請看大螢幕確認。": "The gate wasn't clear. Please check the departure board.",
        "中文翻譯（Muse Spark Open，僅供參考）": "English translation (Muse Spark Open, for reference only)",
        "已確認": "Acknowledged",
        "我已經在登機門了": "I'm at the gate",
        "給地勤看大字卡": "Show card to staff",
        "你的航班": "Your flight",
        "可能是你的": "Maybe yours",
        "跟你無關": "Not yours",
        "收起翻譯": "Hide translation",
        "看翻譯": "Show translation",
        "翻譯中…": "Translating…",
        "翻譯": "Translate",
        "中文翻譯（Muse Spark Open）": "English translation (Muse Spark Open)",
        "英日文廣播可以按「翻譯」。": "Tap \"Translate\" on Mandarin or Japanese announcements.",
        "廣播紀錄": "Announcement log",
        "返回": "Back",
        "? 資料可能過時": "? Data may be out of date",
        "? 待確認": "? Unconfirmed",
        "✓ 機場資料": "✓ Airport data",
        "表定起飛": "Scheduled",
        "預計": "Estimated",
        "未定": "TBD",
        "廣播和機場資料不一致，請看大螢幕或問地勤": "Announcement and airport data disagree. Check the board or ask staff",
        "航班資料也顯示了這個變化": "The flight data shows this change too",
        "沒辦法讀這張照片。": "Can't read this photo.",
        "Muse Spark 讀取登機證中…": "Muse Spark is reading your boarding pass…",
        "上次的聆聽意外中斷了（App 被關閉或手機重新開機），中斷後的廣播都沒有聽到。請按「開始聆聽」繼續。": "Listening stopped unexpectedly last time (the app was closed or the phone restarted), so announcements after that were not heard. Tap \"Start listening\" to continue.",
        "這個版本沒有 API key，請用設定好 META_API_KEY 的環境重新建置。": "This build has no API key. Rebuild with META_API_KEY set.",
        "需要麥克風權限才能聽廣播。請到「設定 → 隱私權與安全性 → 麥克風」打開 Shunfeng。": "Shunfeng needs the microphone to hear announcements. Turn it on in Settings → Privacy & Security → Microphone.",
        "自動停止已關閉，Shunfeng 會繼續聆聽，直到你按停止。": "Auto stop is off, so Shunfeng keeps listening until you tap Stop.",
        "你的班機已起飛，已自動停止聆聽。": "Your flight has departed, so listening stopped.",
        "你的班機已取消": "Your flight is cancelled",
        "按「我知道了」之後，會問你要不要停止聆聽。": "After you tap \"Got it\", you'll be asked whether to stop listening.",
        "班機已取消或改期，今天應該不需要再聽廣播了。": "Your flight was cancelled or moved, so you probably don't need announcements today.",
        "已依你的選擇停止聆聽。": "Stopped listening, as you chose.",
        "沒有收到回應，已自動停止聆聽。": "No answer, so listening stopped.",
        "已過起飛時間，兩次詢問都沒有回應。還在機場的話，打開 App 按開始就會繼續聽。": "Departure time has passed and both questions went unanswered. If you're still at the airport, open the app and tap Start.",
        "已經上飛機就可以停止。沒有回應的話，一小時後會再問一次。": "If you're on board, you can stop. With no answer, you'll be asked again in an hour.",
        "15 分鐘內沒有回應，就會自動停止聆聽。": "With no answer in 15 minutes, listening stops.",
        "Shunfeng 還在暫停（通話打斷收音）": "Shunfeng is still paused (a call interrupted listening)",
        "通話結束後如果沒有自動繼續聽，請打開 Shunfeng。": "If listening didn't resume after your call, open Shunfeng.",
        "通話中，暫停聆聽廣播": "On a call: listening paused",
        "通話結束後會自動繼續聽。這段時間請留意大螢幕。": "Listening resumes when the call ends. Watch the departure board meanwhile.",
        "通話結束，繼續聆聽廣播": "Call ended: listening again",
        "Shunfeng 又在聽廣播了。": "Shunfeng is listening again.",
        "連不上語音辨識服務，現在聽不到廣播。請確認網路；機場 Wi-Fi 可能要先打開瀏覽器按「同意」。App 會每 30 秒自動重試，也可以按「重新連線」。": "Can't reach the speech service, so announcements can't be heard now. Check your connection; airport Wi-Fi may need you to tap \"Agree\" in a browser. The app retries every 30 seconds, or tap \"Reconnect\".",
        "連不上網路，現在聽不到廣播": "No connection: announcements can't be heard now",
        "請確認網路；機場 Wi-Fi 可能要先打開瀏覽器按「同意」。App 會自動重試，連上後繼續聽。": "Check your connection; airport Wi-Fi may need you to tap \"Agree\" in a browser. The app retries and resumes when connected.",
        "已重新連上，繼續聆聽": "Reconnected: listening again",
        "Shunfeng 已經沒在聽廣播了": "Shunfeng has stopped listening",
        "App 被關掉或手機重新開機，現在聽不到廣播。請打開 Shunfeng 按「開始聆聽」。": "The app was closed or the phone restarted, so announcements can't be heard. Open Shunfeng and tap \"Start listening\".",
        "沒有網路，暫時聽不到廣播": "No internet: announcements can't be heard for now",
        "網路恢復後會自動繼續聽。這段時間請留意大螢幕。": "Listening resumes when you're back online. Watch the departure board meanwhile.",
        "沒有網路已超過 30 分鐘（可能是飛航模式），已停止聆聽。": "No internet for over 30 minutes (airplane mode?), so listening stopped.",
        "還在機場的話，恢復網路後打開 App 按開始就會繼續聽。": "If you're still at the airport, open the app and tap Start once you're online.",
        "無法收音，現在聽不到廣播": "Can't record: announcements can't be heard now",
        "麥克風可能被其他 App 佔用。請打開 Shunfeng 按「重新連線」。": "Another app may be using the microphone. Open Shunfeng and tap \"Reconnect\".",
        "登機門不確定，請看大螢幕": "Gate unclear, check the board",
        "聽到你的班號，但聽不清楚是什麼消息。": "Heard your flight number, but not what the news was.",
        "可能跟你的班機有關": "May be about your flight",
        "登機門有變更（沒聽清楚是哪個門）": "Gate changed (the new gate wasn't clear)",
        "班機延誤": "Flight delayed",
        "起飛時間提前！": "Departure moved earlier!",
        "開始登機": "Now boarding",
        "最後登機廣播！": "Final call!",
        "廣播在找人，可能是你": "A passenger is being paged, maybe you",
        "有一則廣播提到你的班號": "An announcement mentioned your flight",
        "聽": "Listen",
        "震動代表什麼（點一下試試）": "What the buzzes mean (tap to try)",
        "正在聆聽廣播": "Listening",
        "連線中…": "Connecting…",
        "通話中，暫停聆聽": "On a call, paused",
        "沒有網路": "No internet",
        "連不上語音服務": "Can't reach speech service",
        "已停止聆聽": "Not listening",
        "鎖屏也會繼續聽": "Keeps listening when locked",
        "馬上就好": "Almost ready",
        "通話結束後自動恢復，這段時間請看大螢幕": "Resumes after the call. Watch the board meanwhile",
        "現在聽不到廣播，請看大螢幕。網路恢復後自動繼續": "Can't hear announcements now. Watch the board; resumes when back online",
        "停止": "Stop",
        "重新連線": "Reconnect",
        "開始聆聽": "Start listening",
        "用 iPhone 本身的麥克風收音。戴 AirPods 或助聽器時，聲音照樣可以從它們播出，收音仍然用手機。": "Uses the iPhone's own microphone. With AirPods or hearing aids, sound still plays through them while the phone listens.",
        "接上有線或 USB-C 麥克風（例如領夾麥克風）時用它收音；沒接的時候改用手機麥克風。": "Uses a wired or USB-C microphone (like a clip-on mic) when one is plugged in, and the phone's microphone otherwise.",
        "用藍牙耳機或助聽器的麥克風收音。不建議：這類麥克風是設計來收你自己說話的，實測用 AirPods 收 1～2 公尺外的廣播，12 則只收到 3 個片段，手機麥克風則全部收到。選這個時，耳機裡的音樂也會變成電話音質；講電話或視訊時麥克風會被通話佔用，這段時間的廣播會漏掉。": "Uses the microphone of Bluetooth earbuds or hearing aids. Not recommended: these mics are made for your own voice. In our test, AirPods caught 3 fragments of 12 announcements from 1–2 m away; the phone's microphone caught all 12. Music in your earbuds also drops to phone-call quality, and calls take over the mic, so announcements during a call are missed.",
        "收音裝置": "Microphone",
        "\n\n聆聽中切換會重新連線，中間約 1～2 秒聽不到。": "\n\nSwitching while listening reconnects; about 1–2 seconds won't be heard.",
        "班機結束後自動停止聆聽": "Stop listening when the trip is over",
        "震動語言": "Buzz language",
        "App 在前景時每下震 0.5 秒；在背景時改用系統震動，次數一樣。": "Each buzz lasts 0.5 s with the app open; in the background the system vibration is used, same count.",
        "沒有網路時": "Without internet",
        "暫停，恢復後自動繼續": "Pause, resume automatically",
        "進電梯、停車場斷網時會暫停，網路恢復就自動繼續聽；斷網超過 1 分鐘會通知你留意大螢幕。斷網超過 30 分鐘（多半是飛航模式）就停止聆聽並通知你。": "In elevators and car parks, listening pauses and resumes when you're back online; after 1 minute offline you're told to watch the board. After 30 minutes offline (usually airplane mode), listening stops and you're told.",
        "完成": "Done",
        "可能": "Maybe",
        "變更": "Change",
        "馬上行動": "Go now",
        "長震": "one long buzz",
        "日文": "Japanese",
        "英文": "English",
        "中文": "Mandarin",
]
