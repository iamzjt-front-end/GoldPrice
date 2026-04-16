import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

struct GoldPriceLiveActivityEntry: Codable, Hashable, Identifiable {
    var id: String
    var sourceName: String
    var shortSourceName: String
    var priceText: String
    var unitText: String
    var changeText: String
    var changeRateText: String
    var isUp: Bool
}

struct GoldPriceLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var sourceName: String
        var shortSourceName: String
        var priceText: String
        var unitText: String
        var changeText: String
        var changeRateText: String
        var refreshText: String
        var updatedAt: Date
        var isUp: Bool
        var entries: [GoldPriceLiveActivityEntry]? = nil
        var refreshIntervalSeconds: Int? = nil

        func currentEntry(at date: Date) -> GoldPriceLiveActivityEntry {
            let displayEntries = entries?.isEmpty == false ? entries! : [fallbackEntry]
            guard displayEntries.count > 1 else {
                return displayEntries[0]
            }

            let interval = TimeInterval(max(5, refreshIntervalSeconds ?? 15))
            let elapsed = max(0, date.timeIntervalSince(updatedAt))
            let index = Int(elapsed / interval) % displayEntries.count
            return displayEntries[index]
        }

        private var fallbackEntry: GoldPriceLiveActivityEntry {
            GoldPriceLiveActivityEntry(
                id: shortSourceName,
                sourceName: sourceName,
                shortSourceName: shortSourceName,
                priceText: priceText,
                unitText: unitText,
                changeText: changeText,
                changeRateText: changeRateText,
                isUp: isUp
            )
        }
    }

    var title: String
}
#endif
