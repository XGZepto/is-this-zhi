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
    var isPinned: Bool = false
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
        let matches = findMatches(in: text)
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

    private static func findMatches(in text: String) -> [KeywordMapping] {
        // Sort longest-first so multi-character phrases win over their substrings
        // (e.g. "小姐姐們" should match before "小姐姐").
        let sortedKeywords = keywordMappings.sorted { $0.keyword.count > $1.keyword.count }
        var consumedRanges: [Range<String.Index>] = []
        var hits: [KeywordMapping] = []

        for mapping in sortedKeywords {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(of: mapping.keyword, range: searchStart..<text.endIndex) {
                let overlaps = consumedRanges.contains { $0.overlaps(range) }
                if !overlaps {
                    consumedRanges.append(range)
                    hits.append(mapping)
                }
                searchStart = range.upperBound
            }
        }
        return hits
    }

    private static let keywordMappings: [KeywordMapping] = [
        // ── Tech / digital ──
        .init(keyword: "視頻", taiwanAlternative: "影片", weight: 36, category: .tech),
        .init(keyword: "短視頻", taiwanAlternative: "短影片", weight: 38, category: .tech),
        .init(keyword: "音頻", taiwanAlternative: "音訊", weight: 28, category: .tech),
        .init(keyword: "質量", taiwanAlternative: "品質", weight: 28, category: .tech),
        .init(keyword: "信息", taiwanAlternative: "資訊", weight: 22, category: .tech),
        .init(keyword: "短信", taiwanAlternative: "簡訊", weight: 30, category: .tech),
        .init(keyword: "屏幕", taiwanAlternative: "螢幕", weight: 24, category: .tech),
        .init(keyword: "軟件", taiwanAlternative: "軟體", weight: 28, category: .tech),
        .init(keyword: "硬件", taiwanAlternative: "硬體", weight: 28, category: .tech),
        .init(keyword: "插件", taiwanAlternative: "外掛", weight: 24, category: .tech),
        .init(keyword: "鼠標", taiwanAlternative: "滑鼠", weight: 30, category: .tech),
        .init(keyword: "鍵盤俠", taiwanAlternative: "鍵盤戰士", weight: 22, category: .tech),
        .init(keyword: "硬盤", taiwanAlternative: "硬碟", weight: 28, category: .tech),
        .init(keyword: "光盤", taiwanAlternative: "光碟", weight: 28, category: .tech),
        .init(keyword: "U盤", taiwanAlternative: "隨身碟", weight: 30, category: .tech),
        .init(keyword: "內存", taiwanAlternative: "記憶體", weight: 26, category: .tech),
        .init(keyword: "存儲", taiwanAlternative: "儲存", weight: 22, category: .tech),
        .init(keyword: "存盤", taiwanAlternative: "存檔", weight: 22, category: .tech),
        .init(keyword: "登錄", taiwanAlternative: "登入", weight: 22, category: .tech),
        .init(keyword: "註冊賬號", taiwanAlternative: "註冊帳號", weight: 24, category: .tech),
        .init(keyword: "賬號", taiwanAlternative: "帳號", weight: 22, category: .tech),
        .init(keyword: "賬戶", taiwanAlternative: "帳戶", weight: 22, category: .tech),
        .init(keyword: "打印", taiwanAlternative: "列印", weight: 24, category: .tech),
        .init(keyword: "打字機", taiwanAlternative: "印表機", weight: 18, category: .tech),
        .init(keyword: "打印機", taiwanAlternative: "印表機", weight: 26, category: .tech),
        .init(keyword: "復印", taiwanAlternative: "影印", weight: 24, category: .tech),
        .init(keyword: "掃碼", taiwanAlternative: "掃條碼", weight: 18, category: .tech),
        .init(keyword: "二維碼", taiwanAlternative: "QR Code", weight: 26, category: .tech),
        .init(keyword: "智能手機", taiwanAlternative: "智慧型手機", weight: 24, category: .tech),
        .init(keyword: "智能", taiwanAlternative: "智慧", weight: 14, category: .tech),
        .init(keyword: "互聯網", taiwanAlternative: "網際網路", weight: 30, category: .tech),
        .init(keyword: "聯網", taiwanAlternative: "連線", weight: 18, category: .tech),
        .init(keyword: "網盤", taiwanAlternative: "雲端硬碟", weight: 26, category: .tech),
        .init(keyword: "網銀", taiwanAlternative: "網路銀行", weight: 26, category: .tech),
        .init(keyword: "頻道", taiwanAlternative: "頻道", weight: 0, category: .tech),
        .init(keyword: "公眾號", taiwanAlternative: "粉絲專頁", weight: 36, category: .tech),
        .init(keyword: "朋友圈", taiwanAlternative: "動態消息", weight: 36, category: .tech),
        .init(keyword: "點贊", taiwanAlternative: "按讚", weight: 32, category: .tech),
        .init(keyword: "拉黑", taiwanAlternative: "封鎖", weight: 30, category: .tech),
        .init(keyword: "鏈接", taiwanAlternative: "連結", weight: 28, category: .tech),
        .init(keyword: "視窗化", taiwanAlternative: "視窗化", weight: 0, category: .tech),
        .init(keyword: "刷機", taiwanAlternative: "刷機", weight: 0, category: .tech),
        .init(keyword: "山寨機", taiwanAlternative: "仿冒機", weight: 22, category: .tech),
        .init(keyword: "編程", taiwanAlternative: "程式設計", weight: 24, category: .tech),
        .init(keyword: "代碼", taiwanAlternative: "程式碼", weight: 22, category: .tech),
        .init(keyword: "源碼", taiwanAlternative: "原始碼", weight: 22, category: .tech),
        .init(keyword: "渠道", taiwanAlternative: "管道", weight: 22, category: .tech),
        .init(keyword: "服務器", taiwanAlternative: "伺服器", weight: 28, category: .tech),
        .init(keyword: "數據", taiwanAlternative: "資料", weight: 20, category: .tech),
        .init(keyword: "數據庫", taiwanAlternative: "資料庫", weight: 26, category: .tech),
        .init(keyword: "操作系統", taiwanAlternative: "作業系統", weight: 26, category: .tech),
        .init(keyword: "默認", taiwanAlternative: "預設", weight: 22, category: .tech),
        .init(keyword: "缺省", taiwanAlternative: "預設", weight: 22, category: .tech),
        .init(keyword: "高清", taiwanAlternative: "高畫質", weight: 22, category: .tech),
        .init(keyword: "分辨率", taiwanAlternative: "解析度", weight: 24, category: .tech),
        .init(keyword: "刷新率", taiwanAlternative: "更新率", weight: 18, category: .tech),
        .init(keyword: "佔用率", taiwanAlternative: "使用率", weight: 16, category: .tech),
        .init(keyword: "下崗", taiwanAlternative: "失業", weight: 22, category: .business),
        .init(keyword: "信號", taiwanAlternative: "訊號", weight: 22, category: .tech),
        .init(keyword: "牛批", taiwanAlternative: "很猛", weight: 30, category: .internetSlang),
        .init(keyword: "牛逼", taiwanAlternative: "很猛", weight: 32, category: .internetSlang),
        .init(keyword: "牛b", taiwanAlternative: "很猛", weight: 26, category: .internetSlang),

        // ── Food / dining ──
        .init(keyword: "土豆", taiwanAlternative: "馬鈴薯", weight: 30, category: .food),
        .init(keyword: "西紅柿", taiwanAlternative: "番茄", weight: 30, category: .food),
        .init(keyword: "獼猴桃", taiwanAlternative: "奇異果", weight: 28, category: .food),
        .init(keyword: "菠蘿", taiwanAlternative: "鳳梨", weight: 30, category: .food),
        .init(keyword: "牛油果", taiwanAlternative: "酪梨", weight: 28, category: .food),
        .init(keyword: "車厘子", taiwanAlternative: "櫻桃", weight: 26, category: .food),
        .init(keyword: "三文魚", taiwanAlternative: "鮭魚", weight: 30, category: .food),
        .init(keyword: "金槍魚", taiwanAlternative: "鮪魚", weight: 30, category: .food),
        .init(keyword: "吞拿魚", taiwanAlternative: "鮪魚", weight: 28, category: .food),
        .init(keyword: "意粉", taiwanAlternative: "義大利麵", weight: 24, category: .food),
        .init(keyword: "速食麵", taiwanAlternative: "泡麵", weight: 16, category: .food),
        .init(keyword: "方便麵", taiwanAlternative: "泡麵", weight: 28, category: .food),
        .init(keyword: "酸奶", taiwanAlternative: "優格", weight: 28, category: .food),
        .init(keyword: "奶昔", taiwanAlternative: "奶昔", weight: 0, category: .food),
        .init(keyword: "雪糕", taiwanAlternative: "冰淇淋", weight: 24, category: .food),
        .init(keyword: "冰棍", taiwanAlternative: "冰棒", weight: 24, category: .food),
        .init(keyword: "外賣", taiwanAlternative: "外送", weight: 32, category: .food),
        .init(keyword: "點外賣", taiwanAlternative: "叫外送", weight: 34, category: .food),
        .init(keyword: "打包", taiwanAlternative: "外帶", weight: 22, category: .food),
        .init(keyword: "便當盒", taiwanAlternative: "便當盒", weight: 0, category: .food),
        .init(keyword: "盒飯", taiwanAlternative: "便當", weight: 30, category: .food),
        .init(keyword: "勺子", taiwanAlternative: "湯匙", weight: 24, category: .food),
        .init(keyword: "餐巾紙", taiwanAlternative: "面紙", weight: 18, category: .food),

        // ── Transport ──
        .init(keyword: "地鐵", taiwanAlternative: "捷運", weight: 30, category: .transport),
        .init(keyword: "公交車", taiwanAlternative: "公車", weight: 30, category: .transport),
        .init(keyword: "公交", taiwanAlternative: "公車", weight: 26, category: .transport),
        .init(keyword: "出租車", taiwanAlternative: "計程車", weight: 30, category: .transport),
        .init(keyword: "打車", taiwanAlternative: "叫車", weight: 26, category: .transport),
        .init(keyword: "打的", taiwanAlternative: "叫車", weight: 24, category: .transport),
        .init(keyword: "摩的", taiwanAlternative: "機車計程車", weight: 22, category: .transport),
        .init(keyword: "摩托", taiwanAlternative: "機車", weight: 24, category: .transport),
        .init(keyword: "電動車", taiwanAlternative: "電動機車", weight: 14, category: .transport),
        .init(keyword: "自行車", taiwanAlternative: "腳踏車", weight: 24, category: .transport),
        .init(keyword: "單車", taiwanAlternative: "腳踏車", weight: 18, category: .transport),
        .init(keyword: "小轎車", taiwanAlternative: "轎車", weight: 18, category: .transport),
        .init(keyword: "車牌號", taiwanAlternative: "車牌", weight: 16, category: .transport),
        .init(keyword: "高速公路", taiwanAlternative: "國道", weight: 14, category: .transport),
        .init(keyword: "堵車", taiwanAlternative: "塞車", weight: 28, category: .transport),
        .init(keyword: "車位", taiwanAlternative: "車位", weight: 0, category: .transport),
        .init(keyword: "停車位", taiwanAlternative: "停車格", weight: 16, category: .transport),

        // ── Daily life ──
        .init(keyword: "土著", taiwanAlternative: "在地人", weight: 22, category: .dailyLife),
        .init(keyword: "立馬", taiwanAlternative: "馬上", weight: 18, category: .dailyLife),
        .init(keyword: "搞定", taiwanAlternative: "處理好", weight: 14, category: .dailyLife),
        .init(keyword: "搞笑", taiwanAlternative: "好笑", weight: 10, category: .dailyLife),
        .init(keyword: "媳婦", taiwanAlternative: "老婆", weight: 22, category: .dailyLife),
        .init(keyword: "愛人", taiwanAlternative: "另一半", weight: 24, category: .dailyLife),
        .init(keyword: "老公", taiwanAlternative: "老公", weight: 0, category: .dailyLife),
        .init(keyword: "對象", taiwanAlternative: "交往對象", weight: 22, category: .dailyLife),
        .init(keyword: "處對象", taiwanAlternative: "交往", weight: 28, category: .dailyLife),
        .init(keyword: "找對象", taiwanAlternative: "找另一半", weight: 26, category: .dailyLife),
        .init(keyword: "閨蜜", taiwanAlternative: "好姊妹", weight: 22, category: .dailyLife),
        .init(keyword: "咋", taiwanAlternative: "怎麼", weight: 22, category: .dailyLife),
        .init(keyword: "咋辦", taiwanAlternative: "怎麼辦", weight: 26, category: .dailyLife),
        .init(keyword: "為啥", taiwanAlternative: "為什麼", weight: 22, category: .dailyLife),
        .init(keyword: "啥子", taiwanAlternative: "什麼", weight: 20, category: .dailyLife),
        .init(keyword: "倆", taiwanAlternative: "兩個", weight: 16, category: .dailyLife),
        .init(keyword: "賊好", taiwanAlternative: "超棒", weight: 22, category: .dailyLife),
        .init(keyword: "賊棒", taiwanAlternative: "超棒", weight: 22, category: .dailyLife),
        .init(keyword: "夠嗆", taiwanAlternative: "難說", weight: 18, category: .dailyLife),
        .init(keyword: "整挺好", taiwanAlternative: "搞得不錯", weight: 22, category: .dailyLife),
        .init(keyword: "整這出", taiwanAlternative: "搞這個", weight: 18, category: .dailyLife),
        .init(keyword: "鬧哪樣", taiwanAlternative: "搞什麼", weight: 18, category: .dailyLife),
        .init(keyword: "起鬨", taiwanAlternative: "起鬨", weight: 0, category: .dailyLife),
        .init(keyword: "瓶子", taiwanAlternative: "瓶子", weight: 0, category: .dailyLife),
        .init(keyword: "塑料", taiwanAlternative: "塑膠", weight: 22, category: .dailyLife),
        .init(keyword: "雷鋒", taiwanAlternative: "好心人", weight: 14, category: .dailyLife),
        .init(keyword: "猴賽雷", taiwanAlternative: "厲害", weight: 22, category: .internetSlang),
        .init(keyword: "厲害了", taiwanAlternative: "太強了", weight: 16, category: .internetSlang),
        .init(keyword: "走心", taiwanAlternative: "用心", weight: 24, category: .internetSlang),
        .init(keyword: "扎心", taiwanAlternative: "戳心", weight: 24, category: .internetSlang),
        .init(keyword: "硬核", taiwanAlternative: "硬派", weight: 22, category: .internetSlang),
        .init(keyword: "顏值", taiwanAlternative: "外貌", weight: 26, category: .internetSlang),
        .init(keyword: "高大上", taiwanAlternative: "高級", weight: 22, category: .internetSlang),
        .init(keyword: "接地氣", taiwanAlternative: "貼近生活", weight: 24, category: .internetSlang),
        .init(keyword: "戲精", taiwanAlternative: "做作", weight: 22, category: .internetSlang),
        .init(keyword: "凡爾賽", taiwanAlternative: "炫耀", weight: 22, category: .internetSlang),
        .init(keyword: "內卷", taiwanAlternative: "惡性競爭", weight: 26, category: .internetSlang),
        .init(keyword: "躺平", taiwanAlternative: "擺爛", weight: 18, category: .internetSlang),
        .init(keyword: "佛系", taiwanAlternative: "隨緣", weight: 16, category: .internetSlang),
        .init(keyword: "氪金", taiwanAlternative: "課金", weight: 22, category: .internetSlang),
        .init(keyword: "白嫖", taiwanAlternative: "免費玩", weight: 20, category: .internetSlang),
        .init(keyword: "雙標", taiwanAlternative: "雙重標準", weight: 12, category: .internetSlang),
        .init(keyword: "翻車", taiwanAlternative: "出包", weight: 16, category: .internetSlang),
        .init(keyword: "打臉", taiwanAlternative: "被打臉", weight: 12, category: .internetSlang),
        .init(keyword: "尬聊", taiwanAlternative: "硬聊", weight: 16, category: .internetSlang),
        .init(keyword: "尬舞", taiwanAlternative: "尬舞", weight: 0, category: .internetSlang),
        .init(keyword: "尬", taiwanAlternative: "尷尬", weight: 0, category: .internetSlang),
        .init(keyword: "鬧鐘", taiwanAlternative: "鬧鐘", weight: 0, category: .dailyLife),

        // ── People / address ──
        .init(keyword: "小哥哥", taiwanAlternative: "帥哥", weight: 34, category: .address),
        .init(keyword: "小姐姐們", taiwanAlternative: "大家", weight: 30, category: .address),
        .init(keyword: "小姐姐", taiwanAlternative: "正妹", weight: 34, category: .address),
        .init(keyword: "親", taiwanAlternative: "親愛的", weight: 0, category: .address),
        .init(keyword: "大佬", taiwanAlternative: "大神", weight: 22, category: .address),
        .init(keyword: "大爺", taiwanAlternative: "阿伯", weight: 22, category: .address),
        .init(keyword: "大媽", taiwanAlternative: "阿姨", weight: 22, category: .address),
        .init(keyword: "姑娘", taiwanAlternative: "女生", weight: 20, category: .address),
        .init(keyword: "小夥子", taiwanAlternative: "年輕人", weight: 24, category: .address),
        .init(keyword: "妹紙", taiwanAlternative: "妹子", weight: 22, category: .address),
        .init(keyword: "妹子", taiwanAlternative: "女生", weight: 14, category: .address),
        .init(keyword: "妹妹們", taiwanAlternative: "大家", weight: 18, category: .address),
        .init(keyword: "童鞋", taiwanAlternative: "同學", weight: 24, category: .address),
        .init(keyword: "盆友", taiwanAlternative: "朋友", weight: 22, category: .address),

        // ── Business / commerce ──
        .init(keyword: "貓膩", taiwanAlternative: "貓膩", weight: 18, category: .business),
        .init(keyword: "貓兒膩", taiwanAlternative: "蹊蹺", weight: 18, category: .business),
        .init(keyword: "套路", taiwanAlternative: "招數", weight: 22, category: .business),
        .init(keyword: "走心服務", taiwanAlternative: "用心服務", weight: 22, category: .business),
        .init(keyword: "性價比", taiwanAlternative: "CP值", weight: 28, category: .business),
        .init(keyword: "包郵", taiwanAlternative: "免運", weight: 30, category: .business),
        .init(keyword: "下單", taiwanAlternative: "下訂", weight: 18, category: .business),
        .init(keyword: "拍下", taiwanAlternative: "下單", weight: 22, category: .business),
        .init(keyword: "賣家秀", taiwanAlternative: "商品照", weight: 24, category: .business),
        .init(keyword: "買家秀", taiwanAlternative: "客戶實拍", weight: 24, category: .business),
        .init(keyword: "差評", taiwanAlternative: "負評", weight: 24, category: .business),
        .init(keyword: "好評", taiwanAlternative: "好評", weight: 0, category: .business),
        .init(keyword: "退貨", taiwanAlternative: "退貨", weight: 0, category: .business),
        .init(keyword: "客服小姐姐", taiwanAlternative: "客服", weight: 32, category: .business),
        .init(keyword: "客服MM", taiwanAlternative: "客服", weight: 24, category: .business),
        .init(keyword: "團購", taiwanAlternative: "團購", weight: 0, category: .business),
        .init(keyword: "秒殺", taiwanAlternative: "限時搶購", weight: 18, category: .business),
        .init(keyword: "拼團", taiwanAlternative: "揪團", weight: 24, category: .business),
        .init(keyword: "代購", taiwanAlternative: "代購", weight: 0, category: .business),
        .init(keyword: "微商", taiwanAlternative: "微商", weight: 22, category: .business),
        .init(keyword: "上架", taiwanAlternative: "上架", weight: 0, category: .business),
        .init(keyword: "下架", taiwanAlternative: "下架", weight: 0, category: .business),
        .init(keyword: "鋪貨", taiwanAlternative: "舖貨", weight: 16, category: .business),
        .init(keyword: "渠道商", taiwanAlternative: "通路商", weight: 26, category: .business),
        .init(keyword: "代理商", taiwanAlternative: "經銷商", weight: 14, category: .business),
        .init(keyword: "賦能", taiwanAlternative: "強化", weight: 22, category: .business),
        .init(keyword: "閉環", taiwanAlternative: "完整流程", weight: 22, category: .business),
        .init(keyword: "對標", taiwanAlternative: "比照", weight: 22, category: .business),
        .init(keyword: "復盤", taiwanAlternative: "檢討", weight: 22, category: .business),
        .init(keyword: "落地", taiwanAlternative: "實際執行", weight: 18, category: .business),
        .init(keyword: "拉通", taiwanAlternative: "整合", weight: 22, category: .business),
        .init(keyword: "顆粒度", taiwanAlternative: "細節層次", weight: 22, category: .business),
        .init(keyword: "抓手", taiwanAlternative: "切入點", weight: 22, category: .business),
        .init(keyword: "賽道", taiwanAlternative: "市場", weight: 18, category: .business),
        .init(keyword: "風口", taiwanAlternative: "趨勢", weight: 18, category: .business),
        .init(keyword: "格局", taiwanAlternative: "格局", weight: 0, category: .business),
        .init(keyword: "調性", taiwanAlternative: "風格", weight: 18, category: .business),
        .init(keyword: "品牌調性", taiwanAlternative: "品牌風格", weight: 22, category: .business),
        .init(keyword: "拍攝周期", taiwanAlternative: "拍攝週期", weight: 14, category: .business),

        // ── Education ──
        .init(keyword: "幼兒園", taiwanAlternative: "幼稚園", weight: 24, category: .education),
        .init(keyword: "小學", taiwanAlternative: "國小", weight: 14, category: .education),
        .init(keyword: "初中", taiwanAlternative: "國中", weight: 26, category: .education),
        .init(keyword: "高中", taiwanAlternative: "高中", weight: 0, category: .education),
        .init(keyword: "大學畢業生", taiwanAlternative: "大學畢業生", weight: 0, category: .education),
        .init(keyword: "大專", taiwanAlternative: "專科", weight: 14, category: .education),
        .init(keyword: "本科", taiwanAlternative: "大學", weight: 26, category: .education),
        .init(keyword: "研究生", taiwanAlternative: "碩士生", weight: 18, category: .education),
        .init(keyword: "博士生", taiwanAlternative: "博士生", weight: 0, category: .education),
        .init(keyword: "考研", taiwanAlternative: "考研究所", weight: 22, category: .education),
        .init(keyword: "高考", taiwanAlternative: "學測", weight: 30, category: .education),
        .init(keyword: "中考", taiwanAlternative: "會考", weight: 24, category: .education),
        .init(keyword: "班主任", taiwanAlternative: "班導師", weight: 24, category: .education),
        .init(keyword: "校服", taiwanAlternative: "制服", weight: 22, category: .education),

        // ── Medical ──
        .init(keyword: "激素", taiwanAlternative: "荷爾蒙", weight: 22, category: .medical),
        .init(keyword: "輸液", taiwanAlternative: "點滴", weight: 24, category: .medical),
        .init(keyword: "打點滴", taiwanAlternative: "打點滴", weight: 0, category: .medical),
        .init(keyword: "防控", taiwanAlternative: "防疫", weight: 22, category: .medical),
        .init(keyword: "陽了", taiwanAlternative: "確診", weight: 26, category: .medical),
        .init(keyword: "核酸", taiwanAlternative: "PCR", weight: 24, category: .medical),
        .init(keyword: "口罩", taiwanAlternative: "口罩", weight: 0, category: .medical),

        // ── Entertainment / fashion ──
        .init(keyword: "番劇", taiwanAlternative: "動畫", weight: 22, category: .entertainment),
        .init(keyword: "彈幕", taiwanAlternative: "彈幕", weight: 0, category: .entertainment),
        .init(keyword: "刷劇", taiwanAlternative: "追劇", weight: 22, category: .entertainment),
        .init(keyword: "追星", taiwanAlternative: "追星", weight: 0, category: .entertainment),
        .init(keyword: "愛豆", taiwanAlternative: "偶像", weight: 26, category: .entertainment),
        .init(keyword: "老鐵", taiwanAlternative: "好兄弟", weight: 24, category: .entertainment),
        .init(keyword: "直男", taiwanAlternative: "直男", weight: 0, category: .entertainment),
        .init(keyword: "直播帶貨", taiwanAlternative: "直播導購", weight: 22, category: .entertainment),
        .init(keyword: "網紅", taiwanAlternative: "網紅", weight: 0, category: .entertainment),
        .init(keyword: "達人", taiwanAlternative: "達人", weight: 0, category: .entertainment),
        .init(keyword: "博主", taiwanAlternative: "部落客", weight: 24, category: .entertainment),
        .init(keyword: "Up主", taiwanAlternative: "創作者", weight: 22, category: .entertainment),
        .init(keyword: "彈窗", taiwanAlternative: "彈出視窗", weight: 22, category: .tech),
        .init(keyword: "私信", taiwanAlternative: "私訊", weight: 26, category: .tech),
        .init(keyword: "群聊", taiwanAlternative: "群組", weight: 22, category: .tech),
        .init(keyword: "群裏", taiwanAlternative: "群組裡", weight: 22, category: .tech),
        .init(keyword: "墨鏡", taiwanAlternative: "太陽眼鏡", weight: 14, category: .fashion),
        .init(keyword: "帽衫", taiwanAlternative: "帽T", weight: 18, category: .fashion),
        .init(keyword: "T恤", taiwanAlternative: "T恤", weight: 0, category: .fashion),

        // ── Misc ──
        .init(keyword: "雷人", taiwanAlternative: "誇張", weight: 22, category: .internetSlang),
        .init(keyword: "雷到", taiwanAlternative: "嚇到", weight: 22, category: .internetSlang),
        .init(keyword: "搞事情", taiwanAlternative: "找麻煩", weight: 22, category: .internetSlang),
        .init(keyword: "槓精", taiwanAlternative: "酸民", weight: 22, category: .internetSlang),
        .init(keyword: "杠精", taiwanAlternative: "酸民", weight: 22, category: .internetSlang),
        .init(keyword: "鋼鐵直男", taiwanAlternative: "直男", weight: 18, category: .internetSlang),
        .init(keyword: "紮心", taiwanAlternative: "戳心", weight: 22, category: .internetSlang),
        .init(keyword: "走花路", taiwanAlternative: "前途光明", weight: 18, category: .internetSlang),
        .init(keyword: "C位", taiwanAlternative: "中央位置", weight: 22, category: .internetSlang),
        .init(keyword: "出道", taiwanAlternative: "出道", weight: 0, category: .entertainment)
    ]
}

private struct KeywordMapping {
    let keyword: String
    let taiwanAlternative: String
    let weight: Int
    let category: ZhiCategory
}

private enum ZhiCategory {
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
