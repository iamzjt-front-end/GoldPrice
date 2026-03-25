import Foundation

class PriceHistoryManager {
    static let shared = PriceHistoryManager()

    private var history: [String: [PriceRecord]] = [:]
    private let fileURL: URL
    private let positionURL: URL
    private let settingsURL: URL
    private(set) var position: PositionInfo?
    private(set) var settings: AppSettings = AppSettings()

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GoldPrice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("priceHistory.json")
        positionURL = dir.appendingPathComponent("position.json")
        settingsURL = dir.appendingPathComponent("settings.json")
        loadHistory()
        loadPosition()
        loadSettings()
        migrateFromUserDefaultsIfNeeded()
        cleanupAllSources()
    }

    // MARK: - Public API

    func recordPrice(_ price: Double, for sourceKey: String) {
        if history[sourceKey] == nil {
            history[sourceKey] = []
        }
        history[sourceKey]?.append(PriceRecord(timestamp: Date(), price: price))
        cleanupOldData(for: sourceKey)
        saveHistory()
    }

    func recordPrices(_ records: [PriceRecord], for sourceKey: String) {
        if history[sourceKey] == nil {
            history[sourceKey] = []
        }
        let existing = Set(history[sourceKey]!.map { Int($0.timestamp.timeIntervalSince1970) })
        let newRecords = records.filter { !existing.contains(Int($0.timestamp.timeIntervalSince1970)) }
        history[sourceKey]?.append(contentsOf: newRecords)
        cleanupOldData(for: sourceKey)
        saveHistory()
    }

    func getTodayRecords(for sourceKey: String) -> [PriceRecord] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return (history[sourceKey] ?? [])
            .filter { $0.timestamp >= startOfDay }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func getHighLow(for sourceKey: String) -> (high: Double?, low: Double?) {
        let records = getTodayRecords(for: sourceKey)
        let prices = records.map { $0.price }
        return (prices.max(), prices.min())
    }

    // MARK: - Position

    func savePosition(_ pos: PositionInfo) {
        position = pos
        if let data = try? JSONEncoder().encode(pos) {
            try? data.write(to: positionURL, options: .atomic)
        }
    }

    private func loadPosition() {
        guard let data = try? Data(contentsOf: positionURL) else { return }
        position = try? JSONDecoder().decode(PositionInfo.self, from: data)
    }

    // MARK: - Settings

    func saveSettings(_ s: AppSettings) {
        settings = s
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    private func loadSettings() {
        guard let data = try? Data(contentsOf: settingsURL) else { return }
        if let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = loaded
        }
    }

    // MARK: - Persistence (file-based)

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(history) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let loaded = try? decoder.decode([String: [PriceRecord]].self, from: data) {
            history = loaded
        }
    }

    private func migrateFromUserDefaultsIfNeeded() {
        let legacyKey = "priceHistoryV2"
        guard let data = UserDefaults.standard.data(forKey: legacyKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let legacy = try? decoder.decode([String: [PriceRecord]].self, from: data) {
            for (key, records) in legacy {
                recordPrices(records, for: key)
            }
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }

    private func cleanupAllSources() {
        for key in history.keys {
            cleanupOldData(for: key)
        }
        saveHistory()
    }

    private func cleanupOldData(for sourceKey: String) {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        history[sourceKey] = history[sourceKey]?.filter { $0.timestamp >= startOfDay }
    }
}
