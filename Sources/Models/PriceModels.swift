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

// MARK: - Position (持仓)

enum ProfitDisplayMode: String, Codable, CaseIterable {
    case off = "不显示"
    case amount = "收益金额"
    case rate = "收益率"
    case both = "都显示"
}

struct AppSettings: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case statusBarIcon
        case profitDisplay
        case refreshInterval
        case defaultAlertRepeatMode
        case defaultAlertRepeatInterval
    }

    var statusBarIcon: String = "🌕"
    var profitDisplay: ProfitDisplayMode = .off
    var refreshInterval: Int = 5
    var defaultAlertRepeatMode: AlertRepeatMode = .recurring
    var defaultAlertRepeatInterval: AlertRepeatInterval = .fiveMinutes

    init(
        statusBarIcon: String = "🌕",
        profitDisplay: ProfitDisplayMode = .off,
        refreshInterval: Int = 5,
        defaultAlertRepeatMode: AlertRepeatMode = .recurring,
        defaultAlertRepeatInterval: AlertRepeatInterval = .fiveMinutes
    ) {
        self.statusBarIcon = statusBarIcon
        self.profitDisplay = profitDisplay
        self.refreshInterval = max(1, refreshInterval)
        self.defaultAlertRepeatMode = defaultAlertRepeatMode
        self.defaultAlertRepeatInterval = defaultAlertRepeatInterval
    }

    var refreshTimeInterval: TimeInterval {
        TimeInterval(max(1, refreshInterval))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusBarIcon = try container.decodeIfPresent(String.self, forKey: .statusBarIcon) ?? "🌕"
        profitDisplay = try container.decodeIfPresent(ProfitDisplayMode.self, forKey: .profitDisplay) ?? .off
        refreshInterval = max(1, try container.decodeIfPresent(Int.self, forKey: .refreshInterval) ?? 5)
        defaultAlertRepeatMode = try container.decodeIfPresent(AlertRepeatMode.self, forKey: .defaultAlertRepeatMode) ?? .recurring
        defaultAlertRepeatInterval = try container.decodeIfPresent(AlertRepeatInterval.self, forKey: .defaultAlertRepeatInterval) ?? .fiveMinutes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(statusBarIcon, forKey: .statusBarIcon)
        try container.encode(profitDisplay, forKey: .profitDisplay)
        try container.encode(refreshInterval, forKey: .refreshInterval)
        try container.encode(defaultAlertRepeatMode, forKey: .defaultAlertRepeatMode)
        try container.encode(defaultAlertRepeatInterval, forKey: .defaultAlertRepeatInterval)
    }
}

// MARK: - Price Alert (价格提醒)

enum AlertCondition: String, Codable, CaseIterable {
    case above = "高于"
    case below = "低于"

    var displayText: String {
        switch self {
        case .above: return "＞"
        case .below: return "＜"
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
            return "价格持续满足条件时，按你设置的时间间隔重复提醒。"
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
            return "持续满足条件时\(repeatInterval.description)"
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

// MARK: - Position (持仓)

struct PositionInfo: Codable, Equatable {
    var grams: Double
    var avgPrice: Double
    var sourceRawValue: String

    var source: GoldPriceSource? {
        GoldPriceSource(rawValue: sourceRawValue)
    }

    func profit(currentPrice: Double) -> Double {
        (currentPrice - avgPrice) * grams
    }

    func profitRate(currentPrice: Double) -> Double {
        guard avgPrice > 0 else { return 0 }
        return (currentPrice - avgPrice) / avgPrice * 100
    }
}
