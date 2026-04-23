//
//  AnalysisEngine.swift
//  is-this-zhi
//
//  Created by Zepto on 23/4/2026.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AnalysisRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let input: String
    let verdict: AnalysisVerdict
    let analyzerSource: AnalyzerSource
    let headline: String
    let reason: String
    let nextStep: String
    let suspicionScore: Int
    let matchedPhrases: [String]
    let suggestedAlternatives: [String]
    let analyzedAt: Date
    let strictModeUsed: Bool
}

enum AnalyzerSource: String, Codable, Hashable {
    case foundationModels
    case fallbackRules

    var displayName: String {
        switch self {
        case .foundationModels: "Apple Intelligence 裝置端模型"
        case .fallbackRules: "本機備援規則"
        }
    }

    var shortLabel: String {
        switch self {
        case .foundationModels: "AI"
        case .fallbackRules: "備援"
        }
    }
}

enum AnalysisVerdict: String, Codable, Hashable {
    case suspected
    case borderline
    case clear
}

enum AnalysisEngine {
    static func analyze(text: String, strictMode: Bool) async -> AnalysisRecord {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        if model.isAvailable {
            do {
                return try await analyzeWithFoundationModels(text: text, strictMode: strictMode, model: model)
            } catch {
                return fallbackAnalyze(
                    text: text,
                    strictMode: strictMode,
                    fallbackReason: "Apple 模型這次沒回穩，先用本機規則抓一輪。"
                )
            }
        } else {
            return fallbackAnalyze(
                text: text,
                strictMode: strictMode,
                fallbackReason: foundationModelUnavailableMessage(for: model.availability)
            )
        }
        #else
        return fallbackAnalyze(
            text: text,
            strictMode: strictMode,
            fallbackReason: "目前執行環境沒有 FoundationModels，先用本機規則抓一輪。"
        )
        #endif
    }

    private static func fallbackAnalyze(text: String, strictMode: Bool, fallbackReason: String? = nil) -> AnalysisRecord {
        let matches = keywordMappings.filter { text.contains($0.keyword) }
        let suspicionBase = matches.reduce(0) { partialResult, match in
            partialResult + match.weight
        }
        let suspicionScore = min(100, suspicionBase + (strictMode ? 18 : 0))

        let verdict: AnalysisVerdict
        if suspicionScore >= 55 {
            verdict = .suspected
        } else if suspicionScore >= 28 {
            verdict = .borderline
        } else {
            verdict = .clear
        }

        let matchedPhrases = matches.map(\.keyword)
        let alternatives = Array(Set(matches.map(\.taiwanAlternative))).sorted()

        let headline: String
        let reason: String
        let nextStep: String

        switch verdict {
        case .suspected:
            headline = "支語味很重，八成會被留言區直接點名"
            reason = matchedPhrases.isEmpty
                ? "整句語感就很不像台灣人平常會講的話，就算沒抓到明顯關鍵詞，還是很容易讓人皺眉。"
                : "命中 \(matchedPhrases.joined(separator: "、"))，這幾個詞在台灣 Threads 上本來就很常被拿來抓支語。"
            nextStep = alternatives.isEmpty
                ? "建議整句重寫成台灣人真的會講的樣子，不然發出去大概又要看人家糾正。"
                : "先換成 \(alternatives.joined(separator: "、")) 這種台灣常講的說法，至少不用一發出去就在那邊解釋半天。"
        case .borderline:
            headline = "有點那個味道，先不要太有自信"
            reason = matchedPhrases.isEmpty
                ? "這句不到鐵證，但語感已經有點歪掉，遇到比較敏感的台灣網友還是可能被挑出來。"
                : "命中 \(matchedPhrases.joined(separator: "、"))，單看不一定致命，但放在一起就開始讓人警鈴大作。"
            nextStep = alternatives.isEmpty
                ? "保守一點就順成你平常真的會講的台灣用語，免得等等還要補充說明。"
                : "想省事的話，直接改成 \(alternatives.joined(separator: "、"))，不要給人家抓語病的空間。"
        case .clear:
            headline = "目前看起來還算台灣味"
            reason = strictMode
                ? "連嚴格模式都沒抓到太多問題，這次大致上算安全。"
                : "目前沒看到很明顯的支語特徵，這句先不用自己嚇自己。"
            nextStep = "這次先過關。下次再看到怪詞，一樣貼上來讓它現形。"
        }

        let finalNextStep = if let fallbackReason {
            "\(nextStep) \(fallbackReason)"
        } else {
            nextStep
        }

        return AnalysisRecord(
            id: UUID(),
            input: text,
            verdict: verdict,
            analyzerSource: .fallbackRules,
            headline: headline,
            reason: reason,
            nextStep: finalNextStep,
            suspicionScore: suspicionScore,
            matchedPhrases: matchedPhrases,
            suggestedAlternatives: alternatives,
            analyzedAt: .now,
            strictModeUsed: strictMode
        )
    }

    #if canImport(FoundationModels)
    private static func analyzeWithFoundationModels(
        text: String,
        strictMode: Bool,
        model: SystemLanguageModel
    ) async throws -> AnalysisRecord {
        let session = LanguageModelSession(model: model, instructions: promptInstructions(strictMode: strictMode))
        let response = try await session.respond(to: prompt(text: text), generating: LLMAnalysisResult.self)
        let content = response.content

        return AnalysisRecord(
            id: UUID(),
            input: text,
            verdict: AnalysisVerdict(rawValue: content.verdict.lowercased()) ?? .borderline,
            analyzerSource: .foundationModels,
            headline: content.headline,
            reason: content.reason,
            nextStep: content.nextStep,
            suspicionScore: min(max(content.suspicionScore, 0), 100),
            matchedPhrases: content.matchedPhrases,
            suggestedAlternatives: content.suggestedAlternatives,
            analyzedAt: .now,
            strictModeUsed: strictMode
        )
    }

    private static func promptInstructions(strictMode: Bool) -> String {
        """
        你是一個帶著不耐煩語氣、但判斷要準的「台灣 Threads 支語巡邏員」。
        任務是分析輸入文字是否會被台灣網友視為帶有中國大陸網路用語或支語感。
        回傳時請站在台灣使用者角度說話，不要假裝中國用語是正常，也不要用像對岸平台文案那樣的語氣。
        文風可以酸一點，但重點是具體、好懂、像台灣網友真的會講的繁體中文。
        `verdict` 只能是 suspected、borderline、clear 其中之一。
        `suspicionScore` 必須是 0 到 100 的整數。
        `headline`、`reason`、`nextStep` 請用繁體中文。
        `matchedPhrases` 只列出輸入裡實際出現、而且可疑的詞。
        `suggestedAlternatives` 只列出台灣常見替代說法；沒有就回空陣列。
        \(strictMode ? "目前是嚴格模式，只要稍微偏離台灣慣用語感就可以拉高分數。" : "目前是一般模式，只有在支語感比較明顯時才給高分。")

        參考範例：
        輸入：這個視頻質量很高
        輸出：{verdict: suspected, suspicionScore: 90, headline: 支語味很重，滑到都會想停下來皺眉, reason: 命中「視頻」「質量」這種典型對岸用法，在台灣很容易直接被判定有支語味。, nextStep: 改成「這個影片品質很好」比較像台灣人會講的，不用等留言區來教。, matchedPhrases: [視頻, 質量], suggestedAlternatives: [影片, 品質]}

        輸入：等等搭地鐵回家再發視頻給你
        輸出：{verdict: suspected, suspicionScore: 94, headline: 支語直接露餡，這句發出去很難不被抓, reason: 命中「地鐵」「視頻」，都是台灣網友很常直接開抓的詞。, nextStep: 直接改成「等等搭捷運回家再傳影片給你」，省得還要在留言區補課。, matchedPhrases: [地鐵, 視頻], suggestedAlternatives: [捷運, 影片]}

        輸入：這功能可以再優化一下
        輸出：{verdict: borderline, suspicionScore: 38, headline: 有點那個味道，先不要太放心, reason: 「優化」不是百分之百不行，但在某些語境裡很容易被覺得像對岸產品文案。, nextStep: 想講得更像台灣人，可以改成「改善」或「調整」。, matchedPhrases: [優化], suggestedAlternatives: [改善, 調整]}

        輸入：這篇文章寫得很順
        輸出：{verdict: clear, suspicionScore: 8, headline: 目前看起來還算台灣味, reason: 這句沒有明顯支語特徵，台灣日常語感也算自然。, nextStep: 這次先過關，下一句怪的再貼上來查。, matchedPhrases: [], suggestedAlternatives: []}
        """
    }

    private static func prompt(text: String) -> String {
        """
        請分析這段文字：
        \(text)
        """
    }

    private static func foundationModelUnavailableMessage(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            "Apple 模型可用。"
        case .unavailable(.deviceNotEligible):
            "這台裝置不支援 Apple Intelligence，先用本機規則頂著。"
        case .unavailable(.appleIntelligenceNotEnabled):
            "Apple Intelligence 還沒開，先用本機規則頂著。"
        case .unavailable(.modelNotReady):
            "Apple 模型還在準備，先用本機規則頂著。"
        case .unavailable:
            "Apple 模型現在不給用，先用本機規則頂著。"
        }
    }
    #endif

    private static let keywordMappings: [KeywordMapping] = [
        .init(keyword: "視頻", taiwanAlternative: "影片", weight: 36),
        .init(keyword: "質量", taiwanAlternative: "品質", weight: 28),
        .init(keyword: "小哥哥", taiwanAlternative: "帥哥", weight: 34),
        .init(keyword: "小姐姐", taiwanAlternative: "正妹", weight: 34),
        .init(keyword: "土豆", taiwanAlternative: "馬鈴薯", weight: 30),
        .init(keyword: "信息", taiwanAlternative: "資訊", weight: 22),
        .init(keyword: "屏幕", taiwanAlternative: "螢幕", weight: 24),
        .init(keyword: "軟件", taiwanAlternative: "軟體", weight: 24),
        .init(keyword: "優化", taiwanAlternative: "改善", weight: 16),
        .init(keyword: "牛逼", taiwanAlternative: "很猛", weight: 26),
        .init(keyword: "高鐵站", taiwanAlternative: "高鐵站", weight: 0),
        .init(keyword: "地鐵", taiwanAlternative: "捷運", weight: 30),
        .init(keyword: "外賣", taiwanAlternative: "外送", weight: 32),
        .init(keyword: "打印", taiwanAlternative: "列印", weight: 24),
        .init(keyword: "小姐姐們", taiwanAlternative: "大家", weight: 28)
    ]
}

private struct KeywordMapping {
    let keyword: String
    let taiwanAlternative: String
    let weight: Int
}

#if canImport(FoundationModels)
@Generable
private struct LLMAnalysisResult {
    @Guide(description: "Use exactly one of: suspected, borderline, clear.")
    let verdict: String
    let suspicionScore: Int
    let headline: String
    let reason: String
    let nextStep: String
    let matchedPhrases: [String]
    let suggestedAlternatives: [String]
}
#endif
