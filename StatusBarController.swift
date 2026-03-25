import SwiftUI
import AppKit
import Combine

class StatusBarController: NSObject, NSMenuDelegate {
    private var statusBar: NSStatusBar
    private var statusItem: NSStatusItem
    private var dataService: GoldPriceService
    private var statusBarUpdateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let historyManager = PriceHistoryManager.shared

    override init() {
        statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)

        dataService = GoldPriceService()

        super.init()

        if let button = statusItem.button {
            let icon = historyManager.settings.statusBarIcon
            button.title = icon.isEmpty ? "--" : "\(icon) --"
        }

        statusItem.menu = buildMenu()

        dataService.$currentSource
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusBarDisplay()
                self?.statusItem.menu = self?.buildMenu()
            }
            .store(in: &cancellables)

        dataService.$allSourcePrices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusBarDisplay()
                self?.statusItem.menu = self?.buildMenu()
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
        statusBarUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateStatusBarDisplay()
        }
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
    }

    // MARK: - Menu

    @discardableResult
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

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

        // Source picker submenu
        let pickerMenu = NSMenu()
        for source in GoldPriceSource.allCases {
            let item = NSMenuItem(title: source.rawValue, action: #selector(selectDisplaySource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source
            if dataService.currentSource == source {
                item.state = .on
            }
            pickerMenu.addItem(item)
        }
        let spacer = NSMenuItem()
        spacer.view = SubmenuOffsetView()
        pickerMenu.insertItem(spacer, at: 0)
        let pickerItem = NSMenuItem(title: "状态栏显示", action: nil, keyEquivalent: "")
        pickerItem.submenu = pickerMenu
        menu.addItem(pickerItem)

        menu.addItem(NSMenuItem.separator())

        // Settings (偏好设置)
        menu.addItem(makeSettingsMenuItem())

        menu.addItem(NSMenuItem.separator())

        // Update time
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeStr = "更新于 \(timeFormatter.string(from: dataService.lastUpdateTime))"
        let timeItem = NSMenuItem(title: timeStr, action: nil, keyEquivalent: "")
        timeItem.isEnabled = false
        timeItem.attributedTitle = NSAttributedString(string: timeStr, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor
        ])
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

        if let info = dataService.allSourcePrices[source], info.price != "--" {
            let priceView = PriceMenuItemView(source: source, info: info)
            item.view = priceView

            let chartSubmenu = NSMenu()
            let records = historyManager.getTodayRecords(for: source.rawValue)
            let chartView = ChartMenuItemView(source: source, info: info, records: records)
            let chartMenuItem = NSMenuItem()
            chartMenuItem.view = chartView
            chartSubmenu.addItem(chartMenuItem)
            item.submenu = chartSubmenu
        } else {
            let attrTitle = NSMutableAttributedString()
            attrTitle.append(NSAttributedString(string: source.rawValue, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]))
            attrTitle.append(NSAttributedString(string: "  --", attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
            item.attributedTitle = attrTitle
        }

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

        let editorSubmenu = NSMenu()
        let editorView = PositionEditorView(
            position: historyManager.position,
            allSources: GoldPriceSource.domesticSources
        ) { [weak self] in
            guard let self = self else { return }
            self.statusItem.menu?.cancelTracking()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.statusItem.menu = self.buildMenu()
                if let button = self.statusItem.button {
                    button.performClick(nil)
                }
            }
        }
        let editorItem = NSMenuItem()
        editorItem.view = editorView
        editorSubmenu.addItem(editorItem)
        item.submenu = editorSubmenu

        return item
    }

    private func makeSettingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "偏好设置", action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: "偏好设置", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ])

        let settingsSubmenu = NSMenu()
        let settingsView = SettingsEditorView { [weak self] in
            guard let self = self else { return }
            self.statusItem.menu?.cancelTracking()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.statusItem.menu = self.buildMenu()
                if let button = self.statusItem.button {
                    button.performClick(nil)
                }
            }
        }
        let settingsItem = NSMenuItem()
        settingsItem.view = settingsView
        settingsSubmenu.addItem(settingsItem)
        item.submenu = settingsSubmenu

        return item
    }

    // MARK: - Actions

    @objc private func selectDisplaySource(_ sender: NSMenuItem) {
        if let source = sender.representedObject as? GoldPriceSource {
            dataService.setDataSource(source)
        }
    }

    @objc private func refreshNow() {
        dataService.forceRefreshAllSources()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        dataService.forceRefreshAllSources()
    }

    func menuDidClose(_ menu: NSMenu) {}
}
