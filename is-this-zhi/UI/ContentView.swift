//
//  ContentView.swift
//  is-this-zhi
//
//  Created by Zepto on 23/4/2026.
//

import SwiftUI

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

private enum AppTab: Hashable {
    case home
    case history
    case settings
}

#Preview {
    ContentView()
}
