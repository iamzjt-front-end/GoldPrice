import SwiftUI
import AppKit
import Combine
import UserNotifications

class StatusBarController: NSObject, NSMenuDelegate {
    private enum DeferredSubmenuKind: String {
        case priceChart
        case positionChart
        case settings
        case alerts
    }

    private var statusBar: NSStatusBar
    private var statusItem: NSStatusItem
    private var dataService: GoldPriceService
    private var statusBarUpdateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let historyManager = PriceHistoryManager.shared
    private var menuIsOpen = false
    private var mainMenu: NSMenu?
    private var priceItems: [GoldPriceSource: NSMenuItem] = [:]
    private var positionMenuItem: NSMenuItem?
    private var alertMenuItem: NSMenuItem?
    private var updateTimeMenuItem: NSMenuItem?
    private var submenuSources: [ObjectIdentifier: GoldPriceSource] = [:]

    override init() {
        statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)

        dataService = GoldPriceService()

        super.init()

        if let button = statusItem.button {
            let icon = historyManager.settings.statusBarIcon
            button.title = icon.isEmpty ? "--" : "\(icon) --"
        }

        let menu = buildMenu()
        mainMenu = menu
        statusItem.menu = menu

        dataService.$currentSource
            .sink { [weak self] _ in
                self?.updateStatusBarDisplay()
                self?.refreshMenuContent()
            }
            .store(in: &cancellables)

        dataService.$allSourcePrices
            .sink { [weak self] _ in
                self?.updateStatusBarDisplay()
                self?.refreshMenuContent()
            }
            .store(in: &cancellables)

        dataService.startFetching()
        startStatusBarUpdateTimer()
    }

    deinit {
        stopStatusBarUpdateTimer()
    }

    // MARK: - Status bar display

    private func startStatusBarUpdateTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateStatusBarDisplay()
            if self?.menuIsOpen == true {
                self?.refreshMenuContent()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusBarUpdateTimer = timer
    }

    private func stopStatusBarUpdateTimer() {
        statusBarUpdateTimer?.invalidate()
        statusBarUpdateTimer = nil
    }

    private func updateStatusBarDisplay() {
        guard let button = statusItem.button else { return }

        let icon = historyManager.settings.statusBarIcon
        let prefix = icon.isEmpty ? "" : "\(icon) "

        let source = dataService.currentSource
        guard let info = dataService.allSourcePrices[source], info.price != "--" else {
            button.title = "\(prefix)--"
            return
        }

        var title = "\(prefix)\(info.formattedPrice)"

        let profitMode = historyManager.settings.profitDisplay
        if profitMode != .off,
           let pos = historyManager.position,
           let posSource = pos.source,
           let posInfo = dataService.allSourcePrices[posSource],
           let cp = posInfo.priceDouble {
            let p = pos.profit(currentPrice: cp)
            let r = pos.profitRate(currentPrice: cp)
            let signP = p >= 0 ? "+" : ""
            let signR = r >= 0 ? "+" : ""
            switch profitMode {
            case .amount:
                title += "  \(signP)\(String(format: "%.2f", p))"
            case .rate:
                title += "  \(signR)\(String(format: "%.2f", r))%"
            case .both:
                title += "  \(signP)\(String(format: "%.2f", p)) (\(signR)\(String(format: "%.2f", r))%)"
            case .off:
                break
            }
        }

        button.title = title
        checkPriceAlerts()
    }

    // MARK: - Menu

    @discardableResult
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        priceItems.removeAll()
        positionMenuItem = nil
        alertMenuItem = nil
        updateTimeMenuItem = nil
        submenuSources.removeAll()

        // Domestic
        addSectionHeader("国内金价", to: menu)
        for source in GoldPriceSource.domesticSources {
            menu.addItem(makePriceMenuItem(source: source))
        }

        menu.addItem(NSMenuItem.separator())

        // International
        addSectionHeader("国际金价", to: menu)
        for source in GoldPriceSource.internationalSources {
            menu.addItem(makePriceMenuItem(source: source))
        }

        menu.addItem(NSMenuItem.separator())

        // Position (我的持仓)
        menu.addItem(makePositionMenuItem())

        menu.addItem(NSMenuItem.separator())

        // Alerts (价格提醒)
        menu.addItem(makeAlertMenuItem())

        // Settings (偏好设置)
        menu.addItem(makeSettingsMenuItem())

        menu.addItem(NSMenuItem.separator())

        // Update time
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeStr = "更新于 \(timeFormatter.string(from: dataService.lastUpdateTime))"
        let timeItem = NSMenuItem(title: timeStr, action: nil, keyEquivalent: "")
        timeItem.isEnabled = false
        timeItem.attributedTitle = updateTimeAttributedString(for: timeStr)
        updateTimeMenuItem = timeItem
        menu.addItem(timeItem)

        // Refresh
        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func addSectionHeader(_ title: String, to menu: NSMenu) {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        menu.addItem(header)
    }

    private func makePriceMenuItem(source: GoldPriceSource) -> NSMenuItem {
        let item = NSMenuItem(title: source.rawValue, action: nil, keyEquivalent: "")
        let info = dataService.allSourcePrices[source] ?? PriceInfo()
        item.view = PriceMenuItemView(source: source, info: info)
        item.submenu = makeDeferredSubmenu(kind: .priceChart, source: source)
        priceItems[source] = item
        return item
    }

    private func makePositionMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "我的持仓", action: nil, keyEquivalent: "")

        if let pos = historyManager.position {
            var currentPrice: Double? = nil
            if let source = pos.source, let info = dataService.allSourcePrices[source] {
                currentPrice = info.priceDouble
            }
            let displayView = PositionDisplayView(position: pos, currentPrice: currentPrice)
            item.view = displayView
        } else {
            item.attributedTitle = NSAttributedString(string: "我的持仓  未设置 →", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
        }
        item.submenu = makeDeferredSubmenu(kind: .positionChart)
        positionMenuItem = item
        return item
    }

    private func makeSettingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "偏好设置", action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: "偏好设置", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ])
        item.submenu = makeDeferredSubmenu(kind: .settings)

        return item
    }
    private func makeAlertMenuItem() -> NSMenuItem {
        let alertCount = historyManager.alerts.count
        let title = alertCount > 0 ? "价格提醒 (\(alertCount))" : "价格提醒"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ])
        item.submenu = makeDeferredSubmenu(kind: .alerts)
        alertMenuItem = item
        return item
    }

    private func makeDeferredSubmenu(kind: DeferredSubmenuKind, source: GoldPriceSource? = nil) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.identifier = NSUserInterfaceItemIdentifier(kind.rawValue)
        if let source {
            submenuSources[ObjectIdentifier(menu)] = source
        }
        return menu
    }

    private func refreshMenuContent() {
        refreshPriceItems()
        refreshPositionItem()
        refreshAlertMenuItemTitle()
        refreshUpdateTimeItem()
        refreshOpenSubmenusIfNeeded()
    }

    private func refreshPriceItems() {
        for source in GoldPriceSource.allCases {
            guard let item = priceItems[source] else { continue }
            let info = dataService.allSourcePrices[source] ?? PriceInfo()
            if let view = item.view as? PriceMenuItemView {
                view.update(source: source, info: info)
            } else {
                item.view = PriceMenuItemView(source: source, info: info)
            }
        }
    }

    private func refreshPositionItem() {
        guard let item = positionMenuItem else { return }

        if let position = historyManager.position {
            let currentPrice = position.source.flatMap { source in
                dataService.allSourcePrices[source]?.priceDouble
            }
            item.attributedTitle = nil
            if let view = item.view as? PositionDisplayView {
                view.update(position: position, currentPrice: currentPrice)
            } else {
                item.view = PositionDisplayView(position: position, currentPrice: currentPrice)
            }
        } else {
            item.view = nil
            item.attributedTitle = NSAttributedString(string: "我的持仓  未设置 →", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
        }
    }

    private func refreshAlertMenuItemTitle() {
        guard let item = alertMenuItem else { return }
        let alertCount = historyManager.alerts.count
        let title = alertCount > 0 ? "价格提醒 (\(alertCount))" : "价格提醒"
        item.title = title
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ])
    }

    private func refreshUpdateTimeItem() {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeStr = "更新于 \(timeFormatter.string(from: dataService.lastUpdateTime))"
        updateTimeMenuItem?.title = timeStr
        updateTimeMenuItem?.attributedTitle = updateTimeAttributedString(for: timeStr)
    }

    private func updateTimeAttributedString(for text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor
        ])
    }

    private func refreshOpenSubmenusIfNeeded() {
        for source in GoldPriceSource.allCases {
            guard let submenu = priceItems[source]?.submenu, !submenu.items.isEmpty else { continue }
            refreshPriceSubmenu(submenu, source: source)
        }

        if let submenu = positionMenuItem?.submenu, !submenu.items.isEmpty {
            refreshPositionSubmenu(submenu)
        }
    }

    private func refreshPriceSubmenu(_ menu: NSMenu, source: GoldPriceSource) {
        guard let info = dataService.allSourcePrices[source], info.price != "--" else { return }
        let records = historyManager.getTodayRecords(for: source.rawValue)

        if let chartView = menu.items.first?.view as? ChartMenuItemView {
            chartView.update(source: source, info: info, records: records)
        } else {
            populatePriceSubmenu(menu, source: source)
        }
    }

    private func refreshPositionSubmenu(_ menu: NSMenu) {
        guard let position = historyManager.position,
              let source = position.source,
              let currentPrice = dataService.allSourcePrices[source]?.priceDouble else { return }

        let records = historyManager.getTodayRecords(for: source.rawValue)
        if let chartView = menu.items.first?.view as? PositionChartMenuItemView {
            chartView.update(position: position, currentPrice: currentPrice, records: records)
        } else {
            populatePositionSubmenu(menu)
        }
    }

    private func populatePriceSubmenu(_ menu: NSMenu, source: GoldPriceSource) {
        menu.removeAllItems()
        guard let info = dataService.allSourcePrices[source], info.price != "--" else { return }

        let records = historyManager.getTodayRecords(for: source.rawValue)
        let chartView = ChartMenuItemView(source: source, info: info, records: records)
        let chartMenuItem = NSMenuItem()
        chartMenuItem.view = chartView
        menu.addItem(chartMenuItem)
    }

    private func populatePositionSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()

        if let pos = historyManager.position,
           let source = pos.source,
           let info = dataService.allSourcePrices[source],
           let currentPrice = info.priceDouble {
            let records = historyManager.getTodayRecords(for: source.rawValue)
            let chartView = PositionChartMenuItemView(
                position: pos,
                currentPrice: currentPrice,
                records: records
            )
            let chartItem = NSMenuItem()
            chartItem.view = chartView
            menu.addItem(chartItem)
            menu.addItem(.separator())
        }

        let editorView = PositionEditorView(
            position: historyManager.position,
            allSources: GoldPriceSource.domesticSources
        )
        let editorItem = NSMenuItem()
        editorItem.view = editorView
        menu.addItem(editorItem)
    }

    private func populateSettingsSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let settingsView = SettingsEditorView(
            currentSource: dataService.currentSource,
            onSourceChange: { [weak self] source in
                self?.dataService.setDataSource(source)
                self?.updateStatusBarDisplay()
                self?.refreshMenuContent()
            }
        ) { [weak self] in
            self?.dataService.reloadRefreshIntervalFromSettings()
            self?.updateStatusBarDisplay()
            self?.refreshMenuContent()
        }
        let settingsItem = NSMenuItem()
        settingsItem.view = settingsView
        menu.addItem(settingsItem)
    }

    private func populateAlertsSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let alertView = AlertEditorView()
        let alertItem = NSMenuItem()
        alertItem.view = alertView
        menu.addItem(alertItem)
    }

    private func checkPriceAlerts() {
        let now = Date()
        var alerts = historyManager.alerts
        var didUpdateAlerts = false

        for index in alerts.indices {
            let alert = alerts[index]

            guard let source = alert.source,
                  let info = dataService.allSourcePrices[source],
                  let currentPrice = info.priceDouble else { continue }

            let conditionMet = alert.isConditionMet(currentPrice: currentPrice)
            let shouldNotify: Bool

            switch alert.repeatMode {
            case .rearmOnCross:
                shouldNotify = conditionMet && !alert.wasConditionMet
            case .recurring:
                if conditionMet && !alert.wasConditionMet {
                    shouldNotify = true
                } else if conditionMet, let lastTriggeredAt = alert.lastTriggeredAt {
                    shouldNotify = now.timeIntervalSince(lastTriggeredAt) >= TimeInterval(alert.repeatInterval.rawValue)
                } else {
                    shouldNotify = conditionMet && alert.lastTriggeredAt == nil
                }
            }

            if shouldNotify {
                alerts[index].triggered = true
                alerts[index].lastTriggeredAt = now
                sendAlertNotification(alert: alert, currentPrice: currentPrice, unit: source.unit)
                didUpdateAlerts = true
            }

            if alerts[index].wasConditionMet != conditionMet {
                alerts[index].wasConditionMet = conditionMet
                didUpdateAlerts = true
            }
        }

        if didUpdateAlerts {
            historyManager.saveAlerts(alerts)
            refreshMenuContent()
        }
    }

    private func sendAlertNotification(alert: PriceAlert, currentPrice: Double, unit: String) {
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[GoldPrice] Alert triggered: \(alert.sourceRawValue) \(alert.condition.displayText) \(alert.targetPrice), current: \(currentPrice)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "\(alert.sourceRawValue) \(alert.condition.displayText) \(String(format: "%.2f", alert.targetPrice))"
        content.body = "当前价格：\(String(format: "%.2f", currentPrice)) \(unit)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "price-alert-\(alert.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[GoldPrice] 通知发送失败: \(error.localizedDescription)")
            } else {
                NSLog("[GoldPrice] 通知已发送: \(content.title)")
            }
        }
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        dataService.forceRefreshAllSources()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        if menu === mainMenu {
            menuIsOpen = true
            refreshMenuContent()
            dataService.forceRefreshAllSources()
            return
        }

        guard let identifier = menu.identifier?.rawValue,
              let kind = DeferredSubmenuKind(rawValue: identifier) else { return }

        switch kind {
        case .priceChart:
            guard let source = submenuSources[ObjectIdentifier(menu)] else { return }
            populatePriceSubmenu(menu, source: source)
        case .positionChart:
            populatePositionSubmenu(menu)
        case .settings:
            populateSettingsSubmenu(menu)
        case .alerts:
            populateAlertsSubmenu(menu)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === mainMenu {
            menuIsOpen = false
            return
        }

        menu.removeAllItems()
    }
}
