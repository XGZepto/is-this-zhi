//
//  HistoryView.swift
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

struct HistoryView: View {
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
                .strokeBorder(record.verdict.badgeColor.opacity(0.10), lineWidth: 1)
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
