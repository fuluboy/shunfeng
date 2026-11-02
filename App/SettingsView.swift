import SwiftUI

/// Settings that change how long Shunfeng listens.
struct SettingsView: View {
    @ObservedObject var model: ListenerModel
    @Environment(\.dismiss) private var dismiss

    private var micNote: String {
        switch model.mic {
        case .phone:
            return L("用 iPhone 本身的麥克風收音。戴 AirPods 或助聽器時，聲音照樣可以從它們播出，收音仍然用手機。")
        case .external:
            return L("接上有線或 USB-C 麥克風（例如領夾麥克風）時用它收音；沒接的時候改用手機麥克風。")
        case .bluetooth:
            return L("用藍牙耳機或助聽器的麥克風收音。不建議：這類麥克風是設計來收你自己說話的，實測用 AirPods 收 1～2 公尺外的廣播，12 則只收到 3 個片段，手機麥克風則全部收到。選這個時，耳機裡的音樂也會變成電話音質；講電話或視訊時麥克風會被通話佔用，這段時間的廣播會漏掉。")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Both languages in the label, so it can be found whichever one is showing.
                    Picker("語言 Language", selection: $model.language) {
                        ForEach(AppLanguage.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("語言 Language")
                } footer: {
                    Text(L("廣播翻譯也會翻成這個語言。", "Announcements are translated into this language too."))
                }
                Section {
                    Picker(L("收音裝置"), selection: $model.mic) {
                        ForEach(MicChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(L("收音裝置"))
                } footer: {
                    Text(micNote + (model.isListening ? L("\n\n聆聽中切換會重新連線，中間約 1～2 秒聽不到。") : ""))
                }
                Section {
                    Toggle(L("班機結束後自動停止聆聽"), isOn: $model.autoStop)
                } footer: {
                    Text(L("""
                    班機起飛後自動停止聆聽。班機取消或改到隔天時，會先告訴你，再問你要不要停止。\
                    沒有航班資料的班機，快到起飛時間時會問你；一直沒有回應，就會自動停止。

                    停止後不再收音，可以省電、省網路，也省下語音辨識的使用費用（聽越久花越多）。\
                    關掉這個選項，就會一直聽到你按「停止」為止。
                    """, """
                    Listening stops when your flight departs. If it's cancelled or moved to the next day, \
                    you're told first, then asked whether to stop. For flights without flight data, you're asked \
                    near departure time, and listening stops if nobody answers.

                    Stopping saves battery, data and speech recognition costs (the longer it listens, the more it costs). \
                    With this off, it listens until you tap Stop.
                    """))
                }
                Section {
                    VibrationLegend { model.tryVibration($0) }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                } header: {
                    Text(L("震動語言"))
                } footer: {
                    Text(L("App 在前景時每下震 0.5 秒；在背景時改用系統震動，次數一樣。"))
                }
                Section {
                    LabeledContent(L("沒有網路時"), value: L("暫停，恢復後自動繼續"))
                } footer: {
                    Text(L("進電梯、停車場斷網時會暫停，網路恢復就自動繼續聽；斷網超過 1 分鐘會通知你留意大螢幕。斷網超過 30 分鐘（多半是飛航模式）就停止聆聽並通知你。"))
                }
                // Last: a developer setting, not something travelers need.
                Section {
                    Toggle(L("測試模式：記錄所有轉寫", "Test mode: keep every transcript"), isOn: $model.testMode)
                } footer: {
                    Text(L("平常 App 只在手機上保留跟航班有關的廣播文字，旁人說的話不會留下。測試模式會保留麥克風聽到的每一句話，只在開發測試時打開。",
                           "Normally the app keeps only announcement text about flights on this phone; what people nearby say is not kept. Test mode keeps every line the microphone hears. Use it only for testing."))
                }
            }
            .navigationTitle(L("設定"))
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.brand)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("完成")) { dismiss() } }
            }
        }
    }
}
