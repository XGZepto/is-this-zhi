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
            Section("分析") {
                Toggle("顯示分數", isOn: $showConfidence)
                Toggle("嚴格模式", isOn: $strictMode)
            }

            Section("紀錄") {
                Toggle("保留歷史", isOn: $saveHistory)
                Text(saveHistory ? "分析結果會儲存於本機。" : "不會儲存分析結果。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("關於") {
                LabeledContent("版本", value: "0.2")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("設定")
    }
}
