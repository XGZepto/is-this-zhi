//
//  HomeView.swift
//  is-this-zhi
//
//  Created by Zepto on 23/4/2026.
//

import SwiftUI

private let homeTransition = Animation.spring(response: 0.42, dampingFraction: 0.88)

struct HomeView: View {
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
        case .idle: false
        case .loading, .result: true
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    VStack(alignment: .leading, spacing: 14) {
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
                                Label(isAnalyzing ? "鑑定中" : "鑑定", systemImage: isAnalyzing ? "hourglass" : "wand.and.stars")
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

            Text("貼上文字，看是不是支語。")
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
                    Text("貼上要鑑定的文字…")
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
            Text(prompt)
                .font(.body)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.regularMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 10) {
                Button("編輯", systemImage: "pencil") {
                    withAnimation(homeTransition) {
                        isInputExpanded = true
                    }
                }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)

                Button("清除", systemImage: "arrow.clockwise") {
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
            switch state {
            case .idle:
                EmptyView()
            case .loading:
                loadingView
            case .result(let record):
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        HighlightSummary(record: record)
                        if let summary = summary {
                            ReportScoreBadge(summary: summary, showConfidence: showConfidence)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ResultSection {
                            ResultRow(label: "哪裡怪", value: record.reason)
                            if shouldShowFixSection(for: record) {
                                ResultRow(label: "怎麼改", value: record.nextStep)
                            }
                        }

                        if !record.matchedPhrases.isEmpty || !record.suggestedAlternatives.isEmpty {
                            ResultSection {
                                if !record.matchedPhrases.isEmpty {
                                    ResultRow(label: "命中詞", value: record.matchedPhrases.joined(separator: "、"))
                                }
                                if !record.suggestedAlternatives.isEmpty {
                                    ResultRow(label: "台灣常講", value: record.suggestedAlternatives.joined(separator: "、"))
                                }
                            }
                        }
                    }

                    Label(record.analyzerSource.displayName, systemImage: "cpu")
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

    private var summary: ReportScoreBadge.Summary? {
        switch state {
        case .idle: nil
        case .loading: .loading
        case .result(let record): .record(record)
        }
    }

    private var panelAccent: Color {
        switch state {
        case .idle: .secondary
        case .loading: .blue
        case .result(let record): record.verdict.badgeColor
        }
    }

    private var loadingView: some View {
        HStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("鑑定中…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func shouldShowFixSection(for record: AnalysisRecord) -> Bool {
        record.verdict != .clear && !record.nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ReportScoreBadge: View {
    enum Summary {
        case loading
        case record(AnalysisRecord)

        var badgeTitle: String {
            switch self {
            case .loading: "分析中"
            case .record(let record): record.verdict.badgeTitle
            }
        }

        var color: Color {
            switch self {
            case .loading: .blue
            case .record(let record): record.verdict.badgeColor
            }
        }

        var scoreText: String? {
            switch self {
            case .loading: nil
            case .record(let record): "\(record.suspicionScore)"
            }
        }
    }

    let summary: Summary
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

struct ResultRow: View {
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

struct HighlightSummary: View {
    let record: AnalysisRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.headline)
                .font(.title3.weight(.semibold))

            if !record.matchedPhrases.isEmpty {
                Text(record.matchedPhrases.joined(separator: "、"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(record.verdict.badgeColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ResultSection<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
