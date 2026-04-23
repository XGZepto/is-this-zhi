//
//  ContentView.swift
//  is-this-zhi
//
//  Created by Zepto on 23/4/2026.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @State private var historyRecords: [AnalysisRecord]
    @AppStorage(StorageKey.saveHistoryEnabled) private var saveHistory = true
    @AppStorage(StorageKey.showConfidenceEnabled) private var showConfidence = true
    @AppStorage(StorageKey.strictModeEnabled) private var strictMode = false

    init() {
        _historyRecords = State(initialValue: HistoryStorage.load())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("首頁", systemImage: "sparkle.magnifyingglass", value: AppTab.home) {
                NavigationStack {
                    HomeView(
                        historyRecords: $historyRecords,
                        saveHistory: saveHistory,
                        showConfidence: showConfidence,
                        strictMode: strictMode
                    )
                }
            }

            Tab("紀錄", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                NavigationStack {
                    HistoryView(historyRecords: $historyRecords)
                }
            }

            Tab("設定", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack {
                    SettingsView(
                        saveHistory: $saveHistory,
                        showConfidence: $showConfidence,
                        strictMode: $strictMode
                    )
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onChange(of: historyRecords) { _, newValue in
            HistoryStorage.save(newValue)
        }
    }
}

private enum AppTab: Hashable {
    case home
    case history
    case settings
}

private struct HomeView: View {
    @Binding var historyRecords: [AnalysisRecord]
    let saveHistory: Bool
    let showConfidence: Bool
    let strictMode: Bool

    @State private var prompt = ""
    @State private var isAnalyzing = false
    @State private var resultState: ResultState = .idle

    private var canAnalyze: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAnalyzing
    }

    private var hasVisibleResult: Bool {
        if case .result = resultState {
            return true
        }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                VStack(alignment: .leading, spacing: 14) {
                    Text("可疑用語通報")
                        .font(.headline)

                    TextEditor(text: $prompt)
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if prompt.isEmpty {
                                Text("又看到沒聽過的講法？貼上來，馬上看看是不是又有支語跑進時間線。")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 22)
                                    .allowsHitTesting(false)
                            }
                        }

                    Button {
                        analyzePrompt()
                    } label: {
                        Label(isAnalyzing ? "正在開抓" : "馬上鑑定", systemImage: isAnalyzing ? "hourglass" : "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canAnalyze)
                }
                .padding(18)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                ResultPanel(state: resultState, showConfidence: showConfidence)
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppBackground())
        .navigationTitle("這是支語嗎")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("重設", systemImage: "arrow.counterclockwise") {
                    prompt = ""
                    resultState = .idle
                }
                .buttonStyle(.glass)
                .disabled(prompt.isEmpty && !hasVisibleResult)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("這是支語嗎")
                .font(.largeTitle.weight(.bold))

            Text("又看到怪用法就不用忍。貼上去，立刻看看是不是支語又在洗版，省得整串留言都在幫忙糾正。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }

    private func analyzePrompt() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !isAnalyzing else { return }

        isAnalyzing = true
        resultState = .loading

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))

            let record = await AnalysisEngine.analyze(text: trimmedPrompt, strictMode: strictMode)
            resultState = .result(record)
            isAnalyzing = false

            guard saveHistory else { return }
            historyRecords.insert(record, at: 0)
        }
    }
}

private enum ResultState {
    case idle
    case loading
    case result(AnalysisRecord)
}

private struct ResultPanel: View {
    let state: ResultState
    let showConfidence: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            switch state {
            case .idle:
                Text("看到哪句怪怪的就貼上來。要不要開噴先不急，先確認是不是支語再說。")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 88)
            case .result(let record):
                VStack(alignment: .leading, spacing: 12) {
                    ResultRow(label: "抓到沒", value: record.headline)
                    ResultRow(label: "哪裡怪", value: record.reason)
                    ResultRow(label: "怎麼改", value: record.nextStep)

                    if showConfidence {
                        ResultRow(label: "支語嫌疑分數", value: "\(record.suspicionScore) / 100")
                    }

                    if !record.matchedPhrases.isEmpty {
                        ResultRow(label: "命中詞", value: record.matchedPhrases.joined(separator: "、"))
                    }

                    if !record.suggestedAlternatives.isEmpty {
                        ResultRow(label: "台灣常講", value: record.suggestedAlternatives.joined(separator: "、"))
                    }

                    ResultRow(label: "分析方式", value: record.analyzerSource.displayName)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var title: String {
        switch state {
        case .idle: "支語巡邏中"
        case .loading: "正在全面清查"
        case .result(let record):
            switch record.verdict {
            case .suspected: "支語警報結果"
            case .borderline: "差點踩雷提醒"
            case .clear: "目前暫時沒事"
            }
        }
    }

    private var systemImage: String {
        switch state {
        case .idle: "text.viewfinder"
        case .loading: "hourglass"
        case .result(let record):
            switch record.verdict {
            case .suspected: "exclamationmark.bubble"
            case .borderline: "exclamationmark.circle"
            case .clear: "checkmark.seal"
            }
        }
    }
}

private struct ResultRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryView: View {
    @Binding var historyRecords: [AnalysisRecord]

    var body: some View {
        List {
            if historyRecords.isEmpty {
                ContentUnavailableView(
                    "目前還沒抓到支語",
                    systemImage: "clock.badge.questionmark",
                    description: Text("之後每一筆可疑說法、每一次成功抓包，都會留在這裡方便回頭盤點。")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(historyRecords) { record in
                    HistoryRow(record: record)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                .onDelete(perform: deleteRecords)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("紀錄")
        .toolbar {
            if !historyRecords.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("清空紀錄", systemImage: "trash") {
                        historyRecords.removeAll()
                    }
                }
            }
        }
    }

    private func deleteRecords(at offsets: IndexSet) {
        historyRecords.remove(atOffsets: offsets)
    }
}

private struct HistoryRow: View {
    let record: AnalysisRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.headline)
                        .font(.headline)
                    Text(record.input)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 12)

                Text(record.verdict.badgeTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(record.verdict.badgeColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(record.verdict.badgeColor)
            }

            if !record.matchedPhrases.isEmpty {
                Text("命中詞：\(record.matchedPhrases.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(record.analyzedAt.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text("\(record.analyzerSource.shortLabel) \(record.suspicionScore)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct SettingsView: View {
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
                LabeledContent("資料儲存", value: "本機 UserDefaults")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("設定")
    }
}

private struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                .appBackgroundBase,
                Color(.systemTeal).opacity(0.18),
                Color(.systemPink).opacity(0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private extension AnalysisVerdict {
    var badgeTitle: String {
        switch self {
        case .suspected: "抓到"
        case .borderline: "可疑"
        case .clear: "暫安"
        }
    }

    var badgeColor: Color {
        switch self {
        case .suspected: .red
        case .borderline: .orange
        case .clear: .green
        }
    }
}

private extension Color {
    static var appBackgroundBase: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.clear
        #endif
    }
}

#Preview {
    ContentView()
}
