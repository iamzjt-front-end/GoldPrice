import Foundation

class PriceHistoryManager {
    static let shared = PriceHistoryManager()

    private var history: [String: [PriceRecord]] = [:]
    private let queue = DispatchQueue(label: "com.goldprice.history", qos: .userInitiated)
    private let fileURL: URL
    private let positionURL: URL
    private let settingsURL: URL
    private let alertsURL: URL
    private let percentageAlertsURL: URL
    private let profitAlertsURL: URL
    private(set) var position: PositionInfo?
    private(set) var settings: AppSettings = AppSettings()
    private(set) var alerts: [PriceAlert] = []
    private(set) var percentageAlerts: [PercentageAlert] = []
    private(set) var profitAlerts: [ProfitAlert] = []

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GoldPrice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("priceHistory.json")
        positionURL = dir.appendingPathComponent("position.json")
        settingsURL = dir.appendingPathComponent("settings.json")
        alertsURL = dir.appendingPathComponent("alerts.json")
        percentageAlertsURL = dir.appendingPathComponent("percentageAlerts.json")
        profitAlertsURL = dir.appendingPathComponent("profitAlerts.json")
        loadHistory()
        loadPosition()
        loadSettings()
        loadAlerts()
        loadPercentageAlerts()
        loadProfitAlerts()
        migrateFromUserDefaultsIfNeeded()
        cleanupAllSources()
    }

    // MARK: - Public API

    func recordPrice(_ price: Double, for sourceKey: String) {
        queue.sync {
            if history[sourceKey] == nil {
                history[sourceKey] = []
            }
            history[sourceKey]?.append(PriceRecord(timestamp: Date(), price: price))
            cleanupOldData(for: sourceKey)
            saveHistory()
        }
    }

    func recordPrices(_ records: [PriceRecord], for sourceKey: String) {
        queue.sync {
            if history[sourceKey] == nil {
                history[sourceKey] = []
            }
            let existing = Set(history[sourceKey]!.map { Int($0.timestamp.timeIntervalSince1970) })
            let newRecords = records.filter { !existing.contains(Int($0.timestamp.timeIntervalSince1970)) }
            history[sourceKey]?.append(contentsOf: newRecords)
            cleanupOldData(for: sourceKey)
            saveHistory()
        }
    }

    func getTodayRecords(for sourceKey: String) -> [PriceRecord] {
        queue.sync {
            let startOfDay = Calendar.current.startOfDay(for: Date())
            return (history[sourceKey] ?? [])
                .filter { $0.timestamp >= startOfDay }
                .sorted { $0.timestamp < $1.timestamp }
        }
    }

    func getHighLow(for sourceKey: String) -> (high: Double?, low: Double?) {
        queue.sync {
            let startOfDay = Calendar.current.startOfDay(for: Date())
            let records = (history[sourceKey] ?? [])
                .filter { $0.timestamp >= startOfDay }
                .sorted { $0.timestamp < $1.timestamp }
            let prices = records.map { $0.price }
            return (prices.max(), prices.min())
        }
    }

    // MARK: - Position

    func savePosition(_ pos: PositionInfo) {
        position = pos
        if let data = try? JSONEncoder().encode(pos) {
            try? data.write(to: positionURL, options: .atomic)
        }
    }

    func clearPosition() {
        position = nil
        try? FileManager.default.removeItem(at: positionURL)
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

    // MARK: - Alerts

    func saveAlerts(_ list: [PriceAlert]) {
        alerts = list
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: alertsURL, options: .atomic)
        }
    }

    func addAlert(_ alert: PriceAlert) {
        alerts.append(alert)
        saveAlerts(alerts)
    }

    func removeAlert(id: String) {
        alerts.removeAll { $0.id == id }
        saveAlerts(alerts)
    }

    func markAlertTriggered(id: String) {
        if let idx = alerts.firstIndex(where: { $0.id == id }) {
            alerts[idx].triggered = true
            alerts[idx].lastTriggeredAt = Date()
            saveAlerts(alerts)
        }
    }

    func resetAlert(id: String) {
        if let idx = alerts.firstIndex(where: { $0.id == id }) {
            alerts[idx].triggered = false
            alerts[idx].lastTriggeredAt = nil
            alerts[idx].wasConditionMet = false
            saveAlerts(alerts)
        }
    }

    private func loadAlerts() {
        guard let data = try? Data(contentsOf: alertsURL) else { return }
        if let loaded = try? JSONDecoder().decode([PriceAlert].self, from: data) {
            alerts = loaded
        }
    }

    // MARK: - Percentage Alerts

    func savePercentageAlerts(_ list: [PercentageAlert]) {
        percentageAlerts = list
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: percentageAlertsURL, options: .atomic)
        }
    }

    func addPercentageAlert(_ alert: PercentageAlert) {
        percentageAlerts.append(alert)
        savePercentageAlerts(percentageAlerts)
    }

    func removePercentageAlert(id: String) {
        percentageAlerts.removeAll { $0.id == id }
        savePercentageAlerts(percentageAlerts)
    }

    func resetPercentageAlert(id: String) {
        if let idx = percentageAlerts.firstIndex(where: { $0.id == id }) {
            percentageAlerts[idx].triggered = false
            percentageAlerts[idx].lastTriggeredAt = nil
            percentageAlerts[idx].wasConditionMet = false
            savePercentageAlerts(percentageAlerts)
        }
    }

    private func loadPercentageAlerts() {
        guard let data = try? Data(contentsOf: percentageAlertsURL) else { return }
        if let loaded = try? JSONDecoder().decode([PercentageAlert].self, from: data) {
            percentageAlerts = loaded
        }
    }

    // MARK: - Profit Alerts

    func saveProfitAlerts(_ list: [ProfitAlert]) {
        profitAlerts = list
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: profitAlertsURL, options: .atomic)
        }
    }

    func addProfitAlert(_ alert: ProfitAlert) {
        profitAlerts.append(alert)
        saveProfitAlerts(profitAlerts)
    }

    func removeProfitAlert(id: String) {
        profitAlerts.removeAll { $0.id == id }
        saveProfitAlerts(profitAlerts)
    }

    func resetProfitAlert(id: String) {
        if let idx = profitAlerts.firstIndex(where: { $0.id == id }) {
            profitAlerts[idx].triggered = false
            profitAlerts[idx].lastTriggeredAt = nil
            profitAlerts[idx].wasConditionMet = false
            saveProfitAlerts(profitAlerts)
        }
    }

    private func loadProfitAlerts() {
        guard let data = try? Data(contentsOf: profitAlertsURL) else { return }
        if let loaded = try? JSONDecoder().decode([ProfitAlert].self, from: data) {
            profitAlerts = loaded
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
