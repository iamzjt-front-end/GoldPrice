import Foundation

// MARK: - Data Sources

enum GoldPriceSource: String, CaseIterable {
    case jdZsFinance = "京东浙商"
    case jdMsFinance = "京东民生"
    case londonGold = "伦敦金"
    case newyorkGold = "纽约金"

    var unit: String {
        switch self {
        case .jdZsFinance, .jdMsFinance:
            return "元/克"
        case .londonGold, .newyorkGold:
            return "$/oz"
        }
    }

    var isDomestic: Bool {
        switch self {
        case .jdZsFinance, .jdMsFinance: return true
        case .londonGold, .newyorkGold: return false
        }
    }

    static var domesticSources: [GoldPriceSource] {
        allCases.filter { $0.isDomestic }
    }

    static var internationalSources: [GoldPriceSource] {
        allCases.filter { !$0.isDomestic }
    }
}

// MARK: - Price Info

struct PriceInfo {
    var price: String = "--"
    var yesterdayPrice: String = "--"
    var changeRate: String = ""
    var changeAmount: String = ""
    var dayHigh: String = "--"
    var dayLow: String = "--"

    var isUp: Bool {
        guard !changeRate.isEmpty else { return true }
        return !changeRate.hasPrefix("-")
    }

    var priceDouble: Double? {
        Double(price)
    }

    var formattedPrice: String {
        guard let p = priceDouble else { return "--" }
        return String(format: "%.2f", p)
    }

    var changeIcon: String {
        isUp ? "📈" : "📉"
    }
}

// MARK: - Price History Record

struct PriceRecord: Codable {
    let timestamp: Date
    let price: Double
}

// MARK: - Gold Circle

struct GoldCirclePostItem: Identifiable, Equatable {
    let contentId: String
    let contentType: String
    let authorName: String
    let authorBadgeText: String
    let authorBadgeTexts: [String]
    let avatarURL: URL?
    let publishedAtText: String
    let title: String
    let summary: String
    let commentCountText: String
    let likeCountText: String
    let imageURLs: [URL]
    let highlightText: String
    let jumpURL: URL?
    let fetchedAt: Date

    var id: String { contentId }

    var authorInitial: String {
        authorName.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "金"
    }

    var interactionText: String {
        let parts = [
            commentCountText.isEmpty ? "" : "\(commentCountText)评论",
            likeCountText.isEmpty ? "" : "\(likeCountText)赞"
        ].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    var metadataBadgeText: String {
        let trimmedHighlight = highlightText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHighlight.isEmpty {
            return trimmedHighlight
        }
        return ""
    }

    var authorBadgeLabel: String {
        let shortBadge = authorBadgeTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0.count <= 4 }
        guard let shortBadge else {
            return ""
        }
        return shortBadge
    }

    var contentTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return ""
        }
        if trimmedTitle == trimmedSummary {
            return ""
        }
        return trimmedTitle
    }

    var primaryText: String {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty {
            return trimmedSummary
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var commentButtonText: String {
        if commentCountText.isEmpty {
            return "评论"
        }
        return "评论 \(commentCountText)"
    }

    var likeDisplayText: String {
        if likeCountText.isEmpty {
            return "点赞"
        }
        return "点赞 \(likeCountText)"
    }

    var hasCommentDetail: Bool {
        jumpURL != nil
    }

    var badgeText: String {
        if !authorBadgeText.isEmpty {
            return authorBadgeText
        }
        if imageURLs.count > 1 {
            return "\(imageURLs.count)图"
        }
        if imageURLs.count == 1 {
            return "配图"
        }
        return contentType
    }
}

// MARK: - Position (持仓)

enum ProfitDisplayMode: String, Codable, CaseIterable {
    case off = "不显示"
    case amount = "收益金额"
    case rate = "收益率"
    case both = "都显示"
}

enum DailyChangeDisplayMode: String, Codable, CaseIterable {
    case off = "不显示"
    case amount = "涨跌金额"
    case rate = "涨跌幅"
    case both = "都显示"
}

enum ExtremeAlertCooldown: Int, Codable, CaseIterable {
    case oneMinute = 60
    case threeMinutes = 180
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    var shortLabel: String {
        switch self {
        case .oneMinute: return "1分"
        case .threeMinutes: return "3分"
        case .fiveMinutes: return "5分"
        case .fifteenMinutes: return "15分"
        case .thirtyMinutes: return "30分"
        }
    }
}

struct AppSettings: Codable, Equatable {
    static let defaultStatusBarSourceRawValues = [GoldPriceSource.jdZsFinance.rawValue]

    enum CodingKeys: String, CodingKey {
        case statusBarIcon
        case statusBarSourceRawValues
        case statusBarSourceRawValue
        case profitDisplay
        case statusBarProfitUsesColor
        case dailyChangeDisplay
        case refreshInterval
        case defaultAlertRepeatInterval
        case extremeAlertCooldown
    }

    var statusBarIcon: String = "🌕"
    var statusBarSourceRawValues: [String] = AppSettings.defaultStatusBarSourceRawValues
    var profitDisplay: ProfitDisplayMode = .off
    var statusBarProfitUsesColor: Bool = true
    var dailyChangeDisplay: DailyChangeDisplayMode = .off
    var refreshInterval: Int = 5
    var defaultAlertRepeatInterval: AlertRepeatInterval = .fiveMinutes
    var extremeAlertCooldown: ExtremeAlertCooldown = .threeMinutes

    init(
        statusBarIcon: String = "🌕",
        statusBarSourceRawValues: [String] = AppSettings.defaultStatusBarSourceRawValues,
        profitDisplay: ProfitDisplayMode = .off,
        statusBarProfitUsesColor: Bool = true,
        dailyChangeDisplay: DailyChangeDisplayMode = .off,
        refreshInterval: Int = 5,
        defaultAlertRepeatInterval: AlertRepeatInterval = .fiveMinutes,
        extremeAlertCooldown: ExtremeAlertCooldown = .threeMinutes
    ) {
        self.statusBarIcon = statusBarIcon
        self.statusBarSourceRawValues = AppSettings.normalizedStatusBarSourceRawValues(statusBarSourceRawValues)
        self.profitDisplay = profitDisplay
        self.statusBarProfitUsesColor = statusBarProfitUsesColor
        self.dailyChangeDisplay = dailyChangeDisplay
        self.refreshInterval = max(1, refreshInterval)
        self.defaultAlertRepeatInterval = defaultAlertRepeatInterval
        self.extremeAlertCooldown = extremeAlertCooldown
    }

    var statusBarSources: [GoldPriceSource] {
        get {
            AppSettings.normalizedStatusBarSourceRawValues(statusBarSourceRawValues).compactMap(GoldPriceSource.init(rawValue:))
        }
        set {
            statusBarSourceRawValues = AppSettings.normalizedStatusBarSources(newValue).map(\.rawValue)
        }
    }

    var primaryStatusBarSource: GoldPriceSource {
        statusBarSources.first ?? .jdZsFinance
    }

    var refreshTimeInterval: TimeInterval {
        TimeInterval(max(1, refreshInterval))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusBarIcon = try container.decodeIfPresent(String.self, forKey: .statusBarIcon) ?? "🌕"
        if let storedRawValues = try container.decodeIfPresent([String].self, forKey: .statusBarSourceRawValues) {
            statusBarSourceRawValues = AppSettings.normalizedStatusBarSourceRawValues(storedRawValues)
        } else if let storedRawValue = try container.decodeIfPresent(String.self, forKey: .statusBarSourceRawValue) {
            statusBarSourceRawValues = AppSettings.normalizedStatusBarSourceRawValues([storedRawValue])
        } else {
            statusBarSourceRawValues = AppSettings.defaultStatusBarSourceRawValues
        }
        profitDisplay = try container.decodeIfPresent(ProfitDisplayMode.self, forKey: .profitDisplay) ?? .off
        statusBarProfitUsesColor = try container.decodeIfPresent(Bool.self, forKey: .statusBarProfitUsesColor) ?? true
        dailyChangeDisplay = try container.decodeIfPresent(DailyChangeDisplayMode.self, forKey: .dailyChangeDisplay) ?? .off
        refreshInterval = max(1, try container.decodeIfPresent(Int.self, forKey: .refreshInterval) ?? 5)
        defaultAlertRepeatInterval = try container.decodeIfPresent(AlertRepeatInterval.self, forKey: .defaultAlertRepeatInterval) ?? .fiveMinutes
        extremeAlertCooldown = try container.decodeIfPresent(ExtremeAlertCooldown.self, forKey: .extremeAlertCooldown) ?? .threeMinutes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(statusBarIcon, forKey: .statusBarIcon)
        try container.encode(AppSettings.normalizedStatusBarSourceRawValues(statusBarSourceRawValues), forKey: .statusBarSourceRawValues)
        try container.encode(profitDisplay, forKey: .profitDisplay)
        try container.encode(statusBarProfitUsesColor, forKey: .statusBarProfitUsesColor)
        try container.encode(dailyChangeDisplay, forKey: .dailyChangeDisplay)
        try container.encode(refreshInterval, forKey: .refreshInterval)
        try container.encode(defaultAlertRepeatInterval, forKey: .defaultAlertRepeatInterval)
        try container.encode(extremeAlertCooldown, forKey: .extremeAlertCooldown)
    }

    private static func normalizedStatusBarSources(_ sources: [GoldPriceSource]) -> [GoldPriceSource] {
        var normalized: [GoldPriceSource] = []
        for source in sources where !normalized.contains(source) {
            normalized.append(source)
        }
        return normalized.isEmpty ? [.jdZsFinance] : normalized
    }

    private static func normalizedStatusBarSourceRawValues(_ rawValues: [String]) -> [String] {
        normalizedStatusBarSources(rawValues.compactMap(GoldPriceSource.init(rawValue:))).map(\.rawValue)
    }
}

// MARK: - Price Alert (价格提醒)

enum AlertCondition: String, Codable, CaseIterable {
    case above = "高于"
    case below = "低于"

    var displayText: String {
        switch self {
        case .above: return "≥"
        case .below: return "≤"
        }
    }
}

enum AlertRepeatMode: String, Codable, CaseIterable {
    case rearmOnCross = "重新穿越"
    case recurring = "持续提醒"

    var detailDescription: String {
        switch self {
        case .rearmOnCross:
            return "价格先回到阈值另一侧，再次穿越时才会提醒。"
        case .recurring:
            return "价格满足条件后，会按你设置的时间间隔重复提醒。"
        }
    }
}

enum AlertRepeatInterval: Int, Codable, CaseIterable {
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600

    var shortLabel: String {
        switch self {
        case .fiveMinutes: return "5分"
        case .fifteenMinutes: return "15分"
        case .thirtyMinutes: return "30分"
        case .oneHour: return "1小时"
        }
    }

    var description: String {
        "每\(shortLabel)"
    }
}

struct PriceAlert: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id
        case sourceRawValue
        case condition
        case targetPrice
        case triggered
        case repeatMode
        case repeatInterval
        case lastTriggeredAt
        case wasConditionMet
    }

    var id: String = UUID().uuidString
    var sourceRawValue: String
    var condition: AlertCondition
    var targetPrice: Double
    var triggered: Bool = false
    var repeatMode: AlertRepeatMode = .recurring
    var repeatInterval: AlertRepeatInterval = .fiveMinutes
    var lastTriggeredAt: Date? = nil
    var wasConditionMet: Bool = false

    init(
        id: String = UUID().uuidString,
        sourceRawValue: String,
        condition: AlertCondition,
        targetPrice: Double,
        triggered: Bool = false,
        repeatMode: AlertRepeatMode = .recurring,
        repeatInterval: AlertRepeatInterval = .fiveMinutes,
        lastTriggeredAt: Date? = nil,
        wasConditionMet: Bool = false
    ) {
        self.id = id
        self.sourceRawValue = sourceRawValue
        self.condition = condition
        self.targetPrice = targetPrice
        self.triggered = triggered
        self.repeatMode = repeatMode
        self.repeatInterval = repeatInterval
        self.lastTriggeredAt = lastTriggeredAt
        self.wasConditionMet = wasConditionMet
    }

    var source: GoldPriceSource? {
        GoldPriceSource(rawValue: sourceRawValue)
    }

    var repeatSummary: String {
        switch repeatMode {
        case .rearmOnCross:
            return "重新穿越阈值后再次提醒"
        case .recurring:
            return "满足条件后\(repeatInterval.description)提醒"
        }
    }

    func isConditionMet(currentPrice: Double) -> Bool {
        switch condition {
        case .above: return currentPrice >= targetPrice
        case .below: return currentPrice <= targetPrice
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        sourceRawValue = try container.decode(String.self, forKey: .sourceRawValue)
        condition = try container.decode(AlertCondition.self, forKey: .condition)
        targetPrice = try container.decode(Double.self, forKey: .targetPrice)
        triggered = try container.decodeIfPresent(Bool.self, forKey: .triggered) ?? false
        repeatMode = try container.decodeIfPresent(AlertRepeatMode.self, forKey: .repeatMode) ?? .recurring
        repeatInterval = try container.decodeIfPresent(AlertRepeatInterval.self, forKey: .repeatInterval) ?? .fiveMinutes
        lastTriggeredAt = try container.decodeIfPresent(Date.self, forKey: .lastTriggeredAt)
        wasConditionMet = try container.decodeIfPresent(Bool.self, forKey: .wasConditionMet) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceRawValue, forKey: .sourceRawValue)
        try container.encode(condition, forKey: .condition)
        try container.encode(targetPrice, forKey: .targetPrice)
        try container.encode(triggered, forKey: .triggered)
        try container.encode(repeatMode, forKey: .repeatMode)
        try container.encode(repeatInterval, forKey: .repeatInterval)
        try container.encodeIfPresent(lastTriggeredAt, forKey: .lastTriggeredAt)
        try container.encode(wasConditionMet, forKey: .wasConditionMet)
    }
}

// MARK: - Percentage Alert (涨跌幅提醒)

enum PercentageAlertMetric: String, Codable, CaseIterable {
    case netChange = "净涨跌幅"
    case intradayRange = "波动幅度"

    var detailDescription: String {
        switch self {
        case .netChange:
            return "按当日开盘价到当前价的净涨跌幅计算。"
        case .intradayRange:
            return "按当日最高价与最低价的差值，相对开盘价计算。"
        }
    }
}

struct PercentageAlert: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id
        case sourceRawValue
        case metric
        case targetPercent
        case triggered
        case repeatMode
        case repeatInterval
        case lastTriggeredAt
        case wasConditionMet
    }

    var id: String = UUID().uuidString
    var sourceRawValue: String
    var metric: PercentageAlertMetric
    var targetPercent: Double
    var triggered: Bool = false
    var repeatMode: AlertRepeatMode = .recurring
    var repeatInterval: AlertRepeatInterval = .fiveMinutes
    var lastTriggeredAt: Date? = nil
    var wasConditionMet: Bool = false

    init(
        id: String = UUID().uuidString,
        sourceRawValue: String,
        metric: PercentageAlertMetric,
        targetPercent: Double,
        triggered: Bool = false,
        repeatMode: AlertRepeatMode = .recurring,
        repeatInterval: AlertRepeatInterval = .fiveMinutes,
        lastTriggeredAt: Date? = nil,
        wasConditionMet: Bool = false
    ) {
        self.id = id
        self.sourceRawValue = sourceRawValue
        self.metric = metric
        self.targetPercent = metric == .intradayRange ? abs(targetPercent) : targetPercent
        self.triggered = triggered
        self.repeatMode = repeatMode
        self.repeatInterval = repeatInterval
        self.lastTriggeredAt = lastTriggeredAt
        self.wasConditionMet = wasConditionMet
    }

    var source: GoldPriceSource? {
        GoldPriceSource(rawValue: sourceRawValue)
    }

    var normalizedTargetPercent: Double {
        metric == .intradayRange ? abs(targetPercent) : targetPercent
    }

    var comparatorText: String {
        switch metric {
        case .netChange:
            if normalizedTargetPercent >= 0 {
                return "≥ \(PercentageAlert.formattedPercent(normalizedTargetPercent, alwaysShowSign: true))"
            } else {
                return "≤ \(PercentageAlert.formattedPercent(normalizedTargetPercent, alwaysShowSign: true))"
            }
        case .intradayRange:
            return "≥ \(PercentageAlert.formattedPercent(normalizedTargetPercent))"
        }
    }

    var repeatSummary: String {
        switch repeatMode {
        case .rearmOnCross:
            return "重新穿越阈值后再次提醒"
        case .recurring:
            return "满足条件后\(repeatInterval.description)提醒"
        }
    }

    func isConditionMet(currentPercent: Double) -> Bool {
        switch metric {
        case .netChange:
            if normalizedTargetPercent >= 0 {
                return currentPercent >= normalizedTargetPercent
            } else {
                return currentPercent <= normalizedTargetPercent
            }
        case .intradayRange:
            return currentPercent >= normalizedTargetPercent
        }
    }

    static func formattedPercent(_ value: Double, alwaysShowSign: Bool = false) -> String {
        let sign = alwaysShowSign && value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
}

// MARK: - Position (持仓)

enum ProfitAlertKind: String, Codable, CaseIterable {
    case profit = "浮盈"
    case loss = "浮亏"
}

enum ProfitAlertMetric: String, Codable, CaseIterable {
    case amount = "达到目标金额"
    case rate = "达到目标百分比"

    var shortTitle: String {
        switch self {
        case .amount:
            return "金额"
        case .rate:
            return "百分比"
        }
    }
}

struct ProfitAlert: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id
        case sourceRawValue
        case kind
        case metric
        case targetValue
        case triggered
        case repeatMode
        case repeatInterval
        case lastTriggeredAt
        case wasConditionMet
    }

    var id: String = UUID().uuidString
    var sourceRawValue: String
    var kind: ProfitAlertKind
    var metric: ProfitAlertMetric
    var targetValue: Double
    var triggered: Bool = false
    var repeatMode: AlertRepeatMode = .recurring
    var repeatInterval: AlertRepeatInterval = .fiveMinutes
    var lastTriggeredAt: Date? = nil
    var wasConditionMet: Bool = false

    init(
        id: String = UUID().uuidString,
        sourceRawValue: String,
        kind: ProfitAlertKind,
        metric: ProfitAlertMetric,
        targetValue: Double,
        triggered: Bool = false,
        repeatMode: AlertRepeatMode = .recurring,
        repeatInterval: AlertRepeatInterval = .fiveMinutes,
        lastTriggeredAt: Date? = nil,
        wasConditionMet: Bool = false
    ) {
        self.id = id
        self.sourceRawValue = sourceRawValue
        self.kind = kind
        self.metric = metric
        self.targetValue = abs(targetValue)
        self.triggered = triggered
        self.repeatMode = repeatMode
        self.repeatInterval = repeatInterval
        self.lastTriggeredAt = lastTriggeredAt
        self.wasConditionMet = wasConditionMet
    }

    var source: GoldPriceSource? {
        GoldPriceSource(rawValue: sourceRawValue)
    }

    var normalizedTargetValue: Double {
        abs(targetValue)
    }

    var comparatorText: String {
        switch metric {
        case .amount:
            return "≥ \(ProfitAlert.formattedAmount(normalizedTargetValue))"
        case .rate:
            return "≥ \(ProfitAlert.formattedPercent(normalizedTargetValue))"
        }
    }

    var repeatSummary: String {
        switch repeatMode {
        case .rearmOnCross:
            return "重新穿越阈值后再次提醒"
        case .recurring:
            return "满足条件后\(repeatInterval.description)提醒"
        }
    }

    func isConditionMet(currentProfit: Double, currentRate: Double) -> Bool {
        switch (kind, metric) {
        case (.profit, .amount):
            return currentProfit >= normalizedTargetValue
        case (.loss, .amount):
            return currentProfit <= -normalizedTargetValue
        case (.profit, .rate):
            return currentRate >= normalizedTargetValue
        case (.loss, .rate):
            return currentRate <= -normalizedTargetValue
        }
    }

    static func formattedAmount(_ value: Double) -> String {
        "\(String(format: "%.2f", value))元"
    }

    static func formattedPercent(_ value: Double) -> String {
        "\(String(format: "%.2f", value))%"
    }
}

// MARK: - Extreme Price Alert (新高新低提醒)

struct ExtremePriceAlertConfig: Codable, Equatable {
    var sourceRawValue: String
    var notifyOnNewHigh: Bool = true
    var notifyOnNewLow: Bool = true

    var source: GoldPriceSource? {
        GoldPriceSource(rawValue: sourceRawValue)
    }

    var isEnabled: Bool {
        notifyOnNewHigh || notifyOnNewLow
    }
}

enum PositionFeeMode: String, Codable, CaseIterable {
    case perGram = "每克固定"
    case percentage = "百分比"

    var inputUnit: String {
        switch self {
        case .perGram:
            return "元/克"
        case .percentage:
            return "%"
        }
    }
}

struct PositionInfo: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case lots
        case grams
        case avgPrice
        case sourceRawValue
        case feeModeRawValue
        case feeValue
        case totalFee
    }

    struct Lot: Codable, Equatable, Identifiable {
        var id: String
        var grams: Double
        var price: Double

        init(id: String = UUID().uuidString, grams: Double, price: Double) {
            self.id = id
            self.grams = grams
            self.price = price
        }
    }

    var lots: [Lot]
    var sourceRawValue: String
    var feeModeRawValue: String
    var feeValue: Double

    init(
        lots: [Lot],
        sourceRawValue: String,
        feeMode: PositionFeeMode = .perGram,
        feeValue: Double = 0
    ) {
        self.lots = lots.filter { $0.grams > 0 && $0.price > 0 }
        self.sourceRawValue = sourceRawValue
        self.feeModeRawValue = feeMode.rawValue
        self.feeValue = max(0, feeValue)
    }

    init(
        grams: Double,
        avgPrice: Double,
        sourceRawValue: String,
        feeMode: PositionFeeMode = .perGram,
        feeValue: Double = 0
    ) {
        self.init(
            lots: [Lot(grams: grams, price: avgPrice)],
            sourceRawValue: sourceRawValue,
            feeMode: feeMode,
            feeValue: feeValue
        )
    }

    var grams: Double {
        lots.reduce(0) { $0 + $1.grams }
    }

    var purchaseCost: Double {
        lots.reduce(0) { $0 + ($1.grams * $1.price) }
    }

    var totalCost: Double {
        purchaseCost + totalFee
    }

    var avgPrice: Double {
        let totalGrams = grams
        guard totalGrams > 0 else { return 0 }
        return purchaseCost / totalGrams
    }

    var breakEvenPrice: Double {
        let totalGrams = grams
        guard totalGrams > 0 else { return 0 }
        return totalCost / totalGrams
    }

    var source: GoldPriceSource? {
        GoldPriceSource(rawValue: sourceRawValue)
    }

    var feeMode: PositionFeeMode {
        PositionFeeMode(rawValue: feeModeRawValue) ?? .perGram
    }

    var totalFee: Double {
        switch feeMode {
        case .perGram:
            return max(0, feeValue) * grams
        case .percentage:
            return purchaseCost * max(0, feeValue) / 100
        }
    }

    func profit(currentPrice: Double) -> Double {
        (currentPrice * grams) - totalCost
    }

    func profitRate(currentPrice: Double) -> Double {
        guard totalCost > 0 else { return 0 }
        return profit(currentPrice: currentPrice) / totalCost * 100
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceRawValue = try container.decode(String.self, forKey: .sourceRawValue)

        if let decodedLots = try container.decodeIfPresent([Lot].self, forKey: .lots), !decodedLots.isEmpty {
            lots = decodedLots.filter { $0.grams > 0 && $0.price > 0 }
        } else {
            let legacyGrams = try container.decode(Double.self, forKey: .grams)
            let legacyAvgPrice = try container.decode(Double.self, forKey: .avgPrice)
            lots = [Lot(grams: legacyGrams, price: legacyAvgPrice)].filter { $0.grams > 0 && $0.price > 0 }
        }

        if let decodedFeeMode = try container.decodeIfPresent(String.self, forKey: .feeModeRawValue),
           let feeMode = PositionFeeMode(rawValue: decodedFeeMode) {
            feeModeRawValue = feeMode.rawValue
            feeValue = max(0, try container.decodeIfPresent(Double.self, forKey: .feeValue) ?? 0)
        } else if let decodedFeeValue = try container.decodeIfPresent(Double.self, forKey: .feeValue) {
            feeModeRawValue = PositionFeeMode.perGram.rawValue
            feeValue = max(0, decodedFeeValue)
        } else {
            let legacyTotalFee = max(0, try container.decodeIfPresent(Double.self, forKey: .totalFee) ?? 0)
            let totalGrams = lots.reduce(0) { $0 + $1.grams }
            feeModeRawValue = PositionFeeMode.perGram.rawValue
            feeValue = totalGrams > 0 ? legacyTotalFee / totalGrams : 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lots, forKey: .lots)
        try container.encode(grams, forKey: .grams)
        try container.encode(avgPrice, forKey: .avgPrice)
        try container.encode(sourceRawValue, forKey: .sourceRawValue)
        try container.encode(feeMode.rawValue, forKey: .feeModeRawValue)
        try container.encode(max(0, feeValue), forKey: .feeValue)
        try container.encode(totalFee, forKey: .totalFee)
    }
}
