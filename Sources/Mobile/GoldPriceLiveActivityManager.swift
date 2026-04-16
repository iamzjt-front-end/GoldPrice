import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

@MainActor
final class GoldPriceLiveActivityManager {
    static let shared = GoldPriceLiveActivityManager()

    static var isFeatureAvailable: Bool {
        if #available(iOS 16.1, *) {
            return true
        }
        return false
    }

    private var lastPushedAt: Date?
    private var lastState: GoldPriceLiveActivityAttributes.ContentState?
    private var carouselIndex = 0

    private init() {}

    func sync(
        settings: AppSettings,
        prices: [GoldPriceSource: PriceInfo],
        performance: PositionPerformance?,
        updatedAt: Date,
        force: Bool = false
    ) {
        guard #available(iOS 16.1, *) else { return }

        guard settings.dynamicIslandEnabled else {
            lastPushedAt = nil
            lastState = nil
            carouselIndex = 0
            Task {
                await endAllActivities()
            }
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let now = Date()
        let refreshInterval = max(5, settings.dynamicIslandRefreshInterval)
        if !force, let lastPushedAt, now.timeIntervalSince(lastPushedAt) < TimeInterval(refreshInterval) {
            return
        }

        let states = makeStates(
            items: settings.dynamicIslandItems,
            prices: prices,
            performance: performance,
            refreshInterval: refreshInterval,
            updatedAt: updatedAt
        )
        guard !states.isEmpty else { return }

        if force {
            carouselIndex = 0
        }
        var state = states[carouselIndex % states.count]
        state.entries = states.map(makeEntry)
        state.refreshIntervalSeconds = refreshInterval
        carouselIndex = (carouselIndex + 1) % states.count

        Task {
            await upsertActivity(
                with: state,
                force: true
            )
        }
    }

    @available(iOS 16.1, *)
    private func upsertActivity(
        with state: GoldPriceLiveActivityAttributes.ContentState,
        force: Bool
    ) async {
        if !force {
            if lastState == state {
                return
            }
        }

        var activities = Activity<GoldPriceLiveActivityAttributes>.activities
        if activities.count > 1 {
            for activity in activities.dropFirst() {
                await activity.end(using: nil, dismissalPolicy: .immediate)
            }
            activities = Array(activities.prefix(1))
        }

        do {
            if let activity = activities.first {
                await activity.update(using: state)
            } else {
                _ = try Activity.request(
                    attributes: GoldPriceLiveActivityAttributes(title: "GoldPrice"),
                    contentState: state,
                    pushType: nil
                )
            }
            lastPushedAt = Date()
            lastState = state
        } catch {
            NSLog("[GoldPrice] Live Activity 更新失败: \(error.localizedDescription)")
        }
    }

    @available(iOS 16.1, *)
    private func endAllActivities() async {
        for activity in Activity<GoldPriceLiveActivityAttributes>.activities {
            await activity.end(using: nil, dismissalPolicy: .immediate)
        }
    }

    private func makeStates(
        items: [DynamicIslandDisplayItem],
        prices: [GoldPriceSource: PriceInfo],
        performance: PositionPerformance?,
        refreshInterval: Int,
        updatedAt: Date
    ) -> [GoldPriceLiveActivityAttributes.ContentState] {
        items.compactMap { item in
            switch item {
            case .jdZsFinance, .londonGold:
                guard
                    let source = item.source,
                    let info = prices[source],
                    info.priceDouble != nil
                else {
                    return nil
                }
                return makePriceState(
                    source: source,
                    info: info,
                    refreshInterval: refreshInterval,
                    updatedAt: updatedAt
                )
            case .profit:
                return makeProfitState(
                    performance: performance,
                    refreshInterval: refreshInterval,
                    updatedAt: updatedAt
                )
            }
        }
    }

    private func makeEntry(from state: GoldPriceLiveActivityAttributes.ContentState) -> GoldPriceLiveActivityEntry {
        GoldPriceLiveActivityEntry(
            id: state.shortSourceName,
            sourceName: state.sourceName,
            shortSourceName: state.shortSourceName,
            priceText: state.priceText,
            unitText: state.unitText,
            changeText: state.changeText,
            changeRateText: state.changeRateText,
            isUp: state.isUp
        )
    }

    private func makeState(
        source: GoldPriceSource,
        info: PriceInfo,
        refreshInterval: Int,
        updatedAt: Date
    ) -> GoldPriceLiveActivityAttributes.ContentState {
        let amount = info.changeAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        let rate = info.changeRate.trimmingCharacters(in: .whitespacesAndNewlines)
        let changeText = amount.isEmpty ? "--" : amount
        let changeRateText = rate.isEmpty ? "--" : rate

        return GoldPriceLiveActivityAttributes.ContentState(
            sourceName: source.rawValue,
            shortSourceName: source.shortLabel,
            priceText: info.formattedPrice,
            unitText: source.unit,
            changeText: changeText,
            changeRateText: changeRateText,
            refreshText: refreshDescription(seconds: refreshInterval),
            updatedAt: updatedAt,
            isUp: info.isUp
        )
    }

    private func makePriceState(
        source: GoldPriceSource,
        info: PriceInfo,
        refreshInterval: Int,
        updatedAt: Date
    ) -> GoldPriceLiveActivityAttributes.ContentState {
        makeState(
            source: source,
            info: info,
            refreshInterval: refreshInterval,
            updatedAt: updatedAt
        )
    }

    private func makeProfitState(
        performance: PositionPerformance?,
        refreshInterval: Int,
        updatedAt: Date
    ) -> GoldPriceLiveActivityAttributes.ContentState {
        guard let performance else {
            return GoldPriceLiveActivityAttributes.ContentState(
                sourceName: "持仓收益",
                shortSourceName: "收益",
                priceText: "--",
                unitText: "元",
                changeText: "暂无持仓",
                changeRateText: "--",
                refreshText: refreshDescription(seconds: refreshInterval),
                updatedAt: updatedAt,
                isUp: true
            )
        }

        return GoldPriceLiveActivityAttributes.ContentState(
            sourceName: "持仓收益",
            shortSourceName: "收益",
            priceText: signedNumberText(performance.cumulativeProfit),
            unitText: "元",
            changeText: "持仓 \(numberText(performance.currentGrams, digits: 4))克",
            changeRateText: "均价 \(numberText(performance.avgCost))",
            refreshText: refreshDescription(seconds: refreshInterval),
            updatedAt: updatedAt,
            isUp: performance.cumulativeProfit >= 0
        )
    }

    private func signedNumberText(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "")\(numberText(value))"
    }

    private func numberText(_ value: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", value)
    }

    private func refreshDescription(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) 秒刷新"
        }
        return "\(seconds / 60) 分钟刷新"
    }
}
#else
@MainActor
final class GoldPriceLiveActivityManager {
    static let shared = GoldPriceLiveActivityManager()
    static let isFeatureAvailable = false

    private init() {}

    func sync(
        settings: AppSettings,
        prices: [GoldPriceSource: PriceInfo],
        performance: PositionPerformance?,
        updatedAt: Date,
        force: Bool = false
    ) {}
}
#endif
