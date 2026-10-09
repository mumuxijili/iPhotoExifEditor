import Foundation
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("usesMainlandChinaMapCorrection")
    private var usesMainlandChinaCorrection = false

    var body: some View {
        NavigationStack {
            Form {
                Section("地图坐标") {
                    Toggle(
                        "中国大陆地图校正（GCJ‑02）",
                        isOn: $usesMainlandChinaCorrection
                    )

                    Text(
                        "开启后，地图显示使用 GCJ‑02；地图选点、标记拖动和搜索结果会转换回 WGS‑84 后再进入照片草稿。"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("关于") {
                    LabeledContent("应用", value: "iPhotoExifEditor")
                    LabeledContent("版本", value: Self.versionDescription)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "未知"
        let build = info?["CFBundleVersion"] as? String ?? "未知"
        return "\(version) (\(build))"
    }
}
