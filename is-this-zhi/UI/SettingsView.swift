//
//  SettingsView.swift
//  is-this-zhi
//
//  Created by Zepto on 23/4/2026.
//

import SwiftUI

struct SettingsView: View {
    @Binding var saveHistory: Bool
    @Binding var showConfidence: Bool
    @Binding var strictMode: Bool

    var body: some View {
        Form {
            Section("巡邏強度") {
                Toggle("顯示支語嫌疑分數", isOn: $showConfidence)
                Toggle("寧可多抓也不要漏掉", isOn: $strictMode)
            }

            Section("戰情保存") {
                Toggle("保留抓包紀錄", isOn: $saveHistory)
                Text(saveHistory ? "每次分析完都會自動寫進本機紀錄。" : "關掉後照樣能查，但不會把結果留下來。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("關於") {
                LabeledContent("App", value: "這是支語嗎")
                LabeledContent("版本", value: "0.2")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("設定")
    }
}
