//
//  HistoryStorage.swift
//  is-this-zhi
//
//  Created by Zepto on 23/4/2026.
//

import Foundation

enum HistoryStorage {
    static func load() -> [AnalysisRecord] {
        guard let data = UserDefaults.standard.data(forKey: StorageKey.historyRecords) else {
            return []
        }

        do {
            return try decoder.decode([AnalysisRecord].self, from: data)
        } catch {
            return []
        }
    }

    static func save(_ records: [AnalysisRecord]) {
        do {
            let data = try encoder.encode(records)
            UserDefaults.standard.set(data, forKey: StorageKey.historyRecords)
        } catch {
            assertionFailure("Failed to save history records: \(error)")
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum StorageKey {
    static let historyRecords = "history_records"
    static let saveHistoryEnabled = "save_history_enabled"
    static let showConfidenceEnabled = "show_confidence_enabled"
    static let strictModeEnabled = "strict_mode_enabled"
}
