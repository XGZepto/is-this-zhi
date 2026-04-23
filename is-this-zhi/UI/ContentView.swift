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
                    HistoryView(historyRecords: $historyRecords, showConfidence: showConfidence)
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

private let homeTransition = Animation.spring(response: 0.42, dampingFraction: 0.88)

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
    @State private var isInputExpanded = true
    @State private var resultState: ResultState = .idle
    @Namespace private var homeAnimation

    private var canAnalyze: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAnalyzing
    }

    private var hasPrompt: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowResultPanel: Bool {
        switch resultState {
        case .idle:
            false
        case .loading, .result:
            true
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    VStack(alignment: .leading, spacing: 14) {
                        Text("可疑用語通報")
                            .font(.headline)

                        if shouldShowResultPanel && !isInputExpanded {
                            collapsedInputCard
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        } else {
                            expandedInputEditor
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                                    removal: .opacity
                                ))
                        }

                        if isInputExpanded && hasPrompt {
                            Button {
                                analyzePrompt()
                            } label: {
                                Label(isAnalyzing ? "正在開抓" : "馬上鑑定", systemImage: isAnalyzing ? "hourglass" : "wand.and.stars")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(!canAnalyze)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(18)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .animation(homeTransition, value: isInputExpanded)
                    .animation(homeTransition, value: hasPrompt)
                    .animation(homeTransition, value: isAnalyzing)

                    if shouldShowResultPanel {
                        ResultPanel(state: resultState, showConfidence: showConfidence)
                            .id("result-panel")
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
                .animation(homeTransition, value: shouldShowResultPanel)
            }
            .onChange(of: shouldShowResultPanel) { _, shouldShow in
                guard shouldShow else { return }
                withAnimation(homeTransition) {
                    proxy.scrollTo("result-panel", anchor: .top)
                }
            }
        }
        .background(AppBackground())
        #if canImport(UIKit)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("這是支語嗎")
                .font(.largeTitle.weight(.bold))

            Text("又看到怪用法就不用忍。貼上去，立刻看看是不是支語又在洗版，省得整串留言都在幫忙糾正。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var expandedInputEditor: some View {
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
            .matchedGeometryEffect(id: "input-shell", in: homeAnimation)
    }

    private var collapsedInputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("本次送審文字", systemImage: "text.quote")
                        .font(.subheadline.weight(.semibold))
                    Text("已完成支語檢查")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("已分析")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Text(prompt)
                .font(.body)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.regularMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 10) {
                Button("修改內容", systemImage: "pencil") {
                    withAnimation(homeTransition) {
                        isInputExpanded = true
                    }
                }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)

                Button("重新開始", systemImage: "arrow.clockwise") {
                    startNewCheck()
                }
                .buttonStyle(.glass)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .matchedGeometryEffect(id: "input-shell", in: homeAnimation)
    }

    private func analyzePrompt() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !isAnalyzing else { return }

        withAnimation(homeTransition) {
            isInputExpanded = false
            isAnalyzing = true
            resultState = .loading
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))

            let record = await AnalysisEngine.analyze(text: trimmedPrompt, strictMode: strictMode)
            withAnimation(homeTransition) {
                resultState = .result(record)
                isAnalyzing = false
            }

            guard saveHistory else { return }
            historyRecords.insert(record, at: 0)
        }
    }

    private func startNewCheck() {
        withAnimation(homeTransition) {
            prompt = ""
            isInputExpanded = true
            isAnalyzing = false
            resultState = .idle
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let summary = summary {
                    ReportScoreBadge(summary: summary, showConfidence: showConfidence)
                }
            }

            switch state {
            case .idle:
                EmptyView()
            case .loading:
                loadingView
            case .result(let record):
                VStack(alignment: .leading, spacing: 16) {
                    HighlightSummary(record: record)

                    VStack(alignment: .leading, spacing: 14) {
                        ResultSection(title: "分析內容") {
                            ResultRow(label: "哪裡怪", value: record.reason)
                            if shouldShowFixSection(for: record) {
                                ResultRow(label: "怎麼改", value: record.nextStep)
                            }
                        }

                        if !record.matchedPhrases.isEmpty || !record.suggestedAlternatives.isEmpty {
                            ResultSection(title: "命中與替代") {
                                if !record.matchedPhrases.isEmpty {
                                    ResultRow(label: "命中詞", value: record.matchedPhrases.joined(separator: "、"))
                                }
                                if !record.suggestedAlternatives.isEmpty {
                                    ResultRow(label: "台灣常講", value: record.suggestedAlternatives.joined(separator: "、"))
                                }
                            }
                        }
                    }

                    HStack {
                        Label(record.analyzerSource.displayName, systemImage: "cpu")
                        Spacer()
                        if showConfidence {
                            Text("嫌疑分數 \(record.suspicionScore) / 100")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(panelAccent.opacity(0.4), lineWidth: 1.2)
        }
        .shadow(color: panelAccent.opacity(0.14), radius: 22, y: 10)
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

    private var subtitle: String {
        switch state {
        case .idle:
            ""
        case .loading:
            "正在把這句拿去做支語體檢。"
        case .result(let record):
            record.verdict.displayTitle
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

    private var summary: ReportSummary? {
        switch state {
        case .idle:
            nil
        case .loading:
            .loading
        case .result(let record):
            .record(record)
        }
    }

    private var panelAccent: Color {
        switch state {
        case .idle:
            .secondary
        case .loading:
            .blue
        case .result(let record):
            record.verdict.badgeColor
        }
    }

    private var loadingView: some View {
        HStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            VStack(alignment: .leading, spacing: 4) {
                Text("巡邏中")
                    .font(.subheadline.weight(.semibold))
                Text("等一下，正在把這句拆開看看到底哪裡有那個味道。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func shouldShowFixSection(for record: AnalysisRecord) -> Bool {
        record.verdict != .clear && !record.nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

private struct HighlightSummary: View {
    let record: AnalysisRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(record.verdict.displayTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(record.verdict.badgeColor)

            Text(record.headline)
                .font(.body)

            if !record.matchedPhrases.isEmpty {
                LabeledContent("主要命中", value: record.matchedPhrases.joined(separator: "、"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(record.verdict.badgeColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ResultSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ReportScoreBadge: View {
    let summary: ReportSummary
    let showConfidence: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(summary.badgeTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(summary.color)

            if showConfidence, let scoreText = summary.scoreText {
                Text(scoreText)
                    .font(.title3.weight(.bold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(summary.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private enum ReportSummary {
    case loading
    case record(AnalysisRecord)

    var badgeTitle: String {
        switch self {
        case .loading:
            "分析中"
        case .record(let record):
            record.verdict.badgeTitle
        }
    }

    var color: Color {
        switch self {
        case .loading:
            .blue
        case .record(let record):
            record.verdict.badgeColor
        }
    }

    var scoreText: String? {
        switch self {
        case .loading:
            nil
        case .record(let record):
            "\(record.suspicionScore)"
        }
    }
}

private struct HistoryView: View {
    @Binding var historyRecords: [AnalysisRecord]
    let showConfidence: Bool

    #if canImport(UIKit)
    @State private var editMode: EditMode = .inactive
    #endif
    @State private var selectedRecordIDs = Set<AnalysisRecord.ID>()
    @State private var selectedRecord: AnalysisRecord?

    private var sortedRecords: [AnalysisRecord] {
        historyRecords.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.analyzedAt > rhs.analyzedAt
        }
    }

    private var isEditing: Bool {
        #if canImport(UIKit)
        editMode.isEditing
        #else
        false
        #endif
    }

    private var selectedRecords: [AnalysisRecord] {
        sortedRecords.filter { selectedRecordIDs.contains($0.id) }
    }

    private var hasSelectedRecords: Bool {
        !selectedRecordIDs.isEmpty
    }

    var body: some View {
        List(selection: $selectedRecordIDs) {
            if historyRecords.isEmpty {
                ContentUnavailableView(
                    "目前還沒抓到支語",
                    systemImage: "clock.badge.questionmark",
                    description: Text("之後每一筆可疑說法、每一次成功抓包，都會留在這裡方便回頭盤點。")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(sortedRecords) { record in
                    Button {
                        guard !isEditing else { return }
                        selectedRecord = record
                    } label: {
                        HistoryRow(record: record)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            togglePin(for: record.id)
                        } label: {
                            Label(record.isPinned ? "取消置頂" : "置頂", systemImage: record.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(.yellow)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteRecord(id: record.id)
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(record.isPinned ? "取消置頂" : "置頂", systemImage: record.isPinned ? "pin.slash" : "pin") {
                            togglePin(for: record.id)
                        }
                        Button("刪除", systemImage: "trash", role: .destructive) {
                            deleteRecord(id: record.id)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        #if canImport(UIKit)
        .environment(\.editMode, $editMode)
        #endif
        .navigationTitle("紀錄")
        .navigationDestination(item: $selectedRecord) { record in
            HistoryDetailView(record: record, showConfidence: showConfidence)
        }
        .toolbar {
            if !historyRecords.isEmpty {
                #if canImport(UIKit)
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "完成" : "選取") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            let leavingEditMode = isEditing
                            editMode = leavingEditMode ? .inactive : .active
                            if leavingEditMode {
                                selectedRecordIDs.removeAll()
                            }
                        }
                    }
                }
                #endif

            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditing && hasSelectedRecords {
                HistoryBatchBar(
                    canPin: true,
                    selectedCount: selectedRecordIDs.count,
                    pinActionTitle: selectedRecords.allSatisfy(\.isPinned) ? "取消置頂" : "置頂",
                    onPin: togglePinForSelection,
                    onDelete: deleteSelection
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: isEditing)
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: selectedRecordIDs)
    }

    private func deleteRecord(id: AnalysisRecord.ID) {
        historyRecords.removeAll { $0.id == id }
        selectedRecordIDs.remove(id)
    }

    private func deleteSelection() {
        historyRecords.removeAll { selectedRecordIDs.contains($0.id) }
        selectedRecordIDs.removeAll()
    }

    private func togglePin(for id: AnalysisRecord.ID) {
        guard let index = historyRecords.firstIndex(where: { $0.id == id }) else { return }
        historyRecords[index].isPinned.toggle()
    }

    private func togglePinForSelection() {
        let shouldPin = selectedRecords.contains { !$0.isPinned }
        for id in selectedRecordIDs {
            guard let index = historyRecords.firstIndex(where: { $0.id == id }) else { continue }
            historyRecords[index].isPinned = shouldPin
        }
    }
}

private struct HistoryRow: View {
    let record: AnalysisRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if record.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    Text(record.input)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(record.analyzedAt.formatted(date: .abbreviated, time: .shortened))

                    if !record.matchedPhrases.isEmpty {
                        Text("命中 \(record.matchedPhrases.count)")
                    }

                    if record.suspicionScore > 0 {
                        Text("分數 \(record.suspicionScore)")
                    }

                    Label(record.analyzerSource.shortLabel, systemImage: "cpu")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(record.verdict.badgeTitle)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(record.verdict.badgeColor.opacity(0.18), in: Capsule())
                .foregroundStyle(record.verdict.badgeColor)
        }
        .padding(14)
        .background(historyRowBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(historyRowBorder, lineWidth: 1)
        }
    }

    private var historyRowBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.gray.opacity(0.08)
        #endif
    }

    private var historyRowBorder: Color {
        record.verdict.badgeColor.opacity(0.10)
    }
}

private struct HistoryBatchBar: View {
    let canPin: Bool
    let selectedCount: Int
    let pinActionTitle: String
    let onPin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("已選 \(selectedCount) 筆")
                .font(.subheadline.weight(.semibold))

            Spacer()

            if canPin {
                Button(pinActionTitle, systemImage: "pin") {
                    onPin()
                }
                .buttonStyle(.glass)
            }

            Button("刪除", systemImage: "trash") {
                onDelete()
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct HistoryDetailView: View {
    let record: AnalysisRecord
    let showConfidence: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HighlightSummary(record: record)

                ResultSection(title: "原文") {
                    Text(record.input)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ResultSection(title: "分析內容") {
                    ResultRow(label: "哪裡怪", value: record.reason)
                    if record.verdict != .clear {
                        ResultRow(label: "怎麼改", value: record.nextStep)
                    }
                }

                if !record.matchedPhrases.isEmpty || !record.suggestedAlternatives.isEmpty {
                    ResultSection(title: "命中與替代") {
                        if !record.matchedPhrases.isEmpty {
                            ResultRow(label: "命中詞", value: record.matchedPhrases.joined(separator: "、"))
                        }
                        if !record.suggestedAlternatives.isEmpty {
                            ResultRow(label: "台灣常講", value: record.suggestedAlternatives.joined(separator: "、"))
                        }
                    }
                }

                ResultSection(title: "記錄資訊") {
                    ResultRow(label: "分析時間", value: record.analyzedAt.formatted(date: .complete, time: .shortened))
                    ResultRow(label: "分析方式", value: record.analyzerSource.displayName)
                    if showConfidence {
                        ResultRow(label: "支語嫌疑分數", value: "\(record.suspicionScore) / 100")
                    }
                    ResultRow(label: "狀態", value: record.isPinned ? "已置頂" : "一般")
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppBackground())
        .navigationTitle("完整報告")
        .toolbarTitleDisplayMode(.inline)
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
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("設定")
    }
}

private struct AppBackground: View {
    var body: some View {
        Color.groupedAppBackground
            .ignoresSafeArea()
    }
}

private extension AnalysisVerdict {
    var displayTitle: String {
        switch self {
        case .suspected: "支語警報"
        case .borderline: "可疑邊緣"
        case .clear: "暫時安全"
        }
    }

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
    static var groupedAppBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
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
