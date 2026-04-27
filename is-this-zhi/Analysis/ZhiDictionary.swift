//
//  ZhiDictionary.swift
//  is-this-zhi
//
//  Loads the curated zhīyǔ keyword list from `zhi-dictionary.json`.
//  Edit entries in the JSON file — no Swift recompile needed for the data.
//
//  JSON schema (array of objects):
//    {
//      "keyword":           "視頻",        // suspicious phrase as it appears in input
//      "taiwanAlternative": "影片",        // natural Taiwanese phrasing surfaced in UI
//      "weight":            36,            // suspicion score added on hit (0 = neutral
//                                          // anchor that consumes the substring so a
//                                          // shorter weighted entry won't double-count)
//      "category":          "tech"         // see ZhiCategory cases below
//    }
//

import Foundation
import os

struct KeywordMapping: Decodable {
    let keyword: String
    let taiwanAlternative: String
    let weight: Int
    let category: ZhiCategory
}

enum ZhiCategory: String, Decodable {
    case tech
    case food
    case transport
    case dailyLife
    case internetSlang
    case business
    case education
    case medical
    case entertainment
    case fashion
    case address
    case sports
    case measure
}

enum ZhiDictionary {
    /// Loaded once on first access. If the bundled JSON is missing or malformed
    /// we log loudly and fall back to an empty list — the analyzer will still
    /// run but every input will look clean to the rule engine.
    static let entries: [KeywordMapping] = loadEntries()

    private static let resourceName = "zhi-dictionary"
    private static let logger = Logger(subsystem: "xgzepto.is-this-zhi", category: "ZhiDictionary")

    private static func loadEntries() -> [KeywordMapping] {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json") else {
            logger.error("Missing \(resourceName).json in app bundle — fallback engine will see no keywords.")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([KeywordMapping].self, from: data)
        } catch {
            logger.error("Failed to decode \(resourceName).json: \(error.localizedDescription)")
            return []
        }
    }
}
