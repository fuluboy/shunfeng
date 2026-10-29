import SwiftUI

/// Settings that change how long Shunfeng listens.
struct SettingsView: View {
    @ObservedObject var model: ListenerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("班機結束後自動停止聆聽", isOn: $model.autoStop)
                } footer: {
                    Text("""
                    班機起飛後自動停止聆聽。班機取消或改到隔天時，會先告訴你，再問你要不要停止。\
                    沒有航班資料的班機，快到起飛時間時會問你；一直沒有回應，就會自動停止。

                    停止後不再收音，可以省電、省網路，也省下語音辨識的使用費用（聽越久花越多）。\
                    關掉這個選項，就會一直聽到你按「停止」為止。
                    """)
                }
                Section {
                    LabeledContent("切到飛航模式", value: "一律停止聆聽")
                } footer: {
                    Text("沒有網路就聽不到廣播，所以手機切到飛航模式時，會自動停止並通知你。")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}
