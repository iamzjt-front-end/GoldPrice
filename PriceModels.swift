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
    var statusBarIcon: String = "🌕"
    var profitDisplay: ProfitDisplayMode = .off
}

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
