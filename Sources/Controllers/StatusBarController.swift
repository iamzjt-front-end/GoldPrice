import SwiftUI
import AppKit
import Combine
import UserNotifications

private final class StatusPopupPanel: NSPanel {
    var onOrderOut: (() -> Void)?
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func orderOut(_ sender: Any?) {
        let wasVisible = isVisible
        super.orderOut(sender)
        if wasVisible {
            onOrderOut?()
        }
    }

    override func close() {
        let wasVisible = isVisible
        super.close()
        if wasVisible {
            onClose?()
        }
    }
}

private final class PopupCardContainerView: NSView {
    let hostedContentView: NSView

    init(contentView: NSView) {
        self.hostedContentView = contentView
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        updateAppearanceColors()
        translatesAutoresizingMaskIntoConstraints = false

        clearBackgrounds(in: contentView)
        contentView.appearance = NSApp.effectiveAppearance
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize {
        hostedContentView.fittingSize
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceColors()
        hostedContentView.appearance = NSApp.effectiveAppearance
        clearBackgrounds(in: hostedContentView)
    }

    private func updateAppearanceColors() {
        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let backgroundColor = isDark
            ? NSColor(calibratedWhite: 0.17, alpha: 0.98)
            : NSColor.windowBackgroundColor.withAlphaComponent(0.97)
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = (isDark
            ? NSColor.white.withAlphaComponent(0.10)
            : NSColor.black.withAlphaComponent(0.08)
        ).cgColor
    }

    private func clearBackgrounds(in view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        for subview in view.subviews {
            clearBackgrounds(in: subview)
        }
    }
}

private final class MenuMetaHeaderView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 28))

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = text

        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 280),
            heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(text: String) {
        label.stringValue = text
    }
}

private final class MenuNavigationRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let chevronLabel = NSTextField(labelWithString: "›")

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 28))

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title

        chevronLabel.font = .systemFont(ofSize: 20, weight: .regular)
        chevronLabel.textColor = .secondaryLabelColor
        chevronLabel.alignment = .right
        chevronLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(chevronLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 280),
            heightAnchor.constraint(equalToConstant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            chevronLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(title: String) {
        titleLabel.stringValue = title
    }
}

class StatusBarController: NSObject, NSMenuDelegate {
    private enum DetailPanelKind: Equatable {
        case priceChart(GoldPriceSource)
        case position
        case settings
        case alerts
        case percentageAlerts
        case profitAlerts
    }

    private enum DeferredSubmenuKind: String {
        case priceChart
        case positionChart
        case settings
        case alerts
        case percentageAlerts
        case profitAlerts
    }

    private var statusBar: NSStatusBar
    private var statusItem: NSStatusItem
    private var dataService: GoldPriceService
    private var statusBarUpdateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let historyManager = PriceHistoryManager.shared
    private let officialChartService = OfficialIntradayChartService.shared
    private var menuIsOpen = false
    private var mainMenu: NSMenu?
    private var priceItems: [GoldPriceSource: NSMenuItem] = [:]
    private var positionMenuItem: NSMenuItem?
    private var alertMenuItem: NSMenuItem?
    private var percentageAlertMenuItem: NSMenuItem?
    private var profitAlertMenuItem: NSMenuItem?
    private var updateTimeMenuItem: NSMenuItem?
    private var submenuSources: [ObjectIdentifier: GoldPriceSource] = [:]
    private var domesticChartErrors: [GoldPriceSource: String] = [:]
    private let panelModel = StatusBarPanelModel()
    private var mainPanelWindow: StatusPopupPanel?
    private var childPanelWindow: StatusPopupPanel?
    private var mainPanelHostingView: NSHostingView<StatusBarMainPanelView>?
    private var pinnedDetailPanelKind: DetailPanelKind?
    private var hoverDetailPanelKind: DetailPanelKind?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var mainPanelAnchorFrame: NSRect?
    private let appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--"

    override init() {
        statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)

        dataService = GoldPriceService()

        super.init()

        if let button = statusItem.button {
            let icon = historyManager.settings.statusBarIcon
            button.title = icon.isEmpty ? "--" : "\(icon) --"
            button.target = self
            button.action = #selector(toggleMainPanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem.menu = nil

        dataService.$currentSource
            .sink { [weak self] _ in
                self?.updateStatusBarDisplay()
                self?.syncPanelModel()
                self?.refreshVisiblePanels()
            }
            .store(in: &cancellables)

        dataService.$allSourcePrices
            .sink { [weak self] _ in
                self?.updateStatusBarDisplay()
                self?.syncPanelModel()
                self?.refreshVisiblePanels()
            }
            .store(in: &cancellables)

        syncPanelModel()
        dataService.startFetching()
        startStatusBarUpdateTimer()
    }

    deinit {
        stopStatusBarUpdateTimer()
        removeEventMonitors()
    }

    // MARK: - Status bar display

    private func startStatusBarUpdateTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateStatusBarDisplay()
            self?.syncPanelModel()
            self?.refreshVisiblePanels()
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

        let dailyChangeMode = historyManager.settings.dailyChangeDisplay
        if dailyChangeMode != .off {
            let changeAmount = info.changeAmount.trimmingCharacters(in: .whitespacesAndNewlines)
            let changeRate = info.changeRate.trimmingCharacters(in: .whitespacesAndNewlines)
            let dailyChangeText: String?

            switch dailyChangeMode {
            case .off:
                dailyChangeText = nil
            case .amount:
                dailyChangeText = changeAmount.isEmpty ? nil : changeAmount
            case .rate:
                dailyChangeText = changeRate.isEmpty ? nil : changeRate
            case .both:
                if !changeAmount.isEmpty && !changeRate.isEmpty {
                    dailyChangeText = "\(changeAmount) (\(changeRate))"
                } else if !changeAmount.isEmpty {
                    dailyChangeText = changeAmount
                } else if !changeRate.isEmpty {
                    dailyChangeText = changeRate
                } else {
                    dailyChangeText = nil
                }
            }

            if let dailyChangeText {
                title += "  \(dailyChangeText)"
            }
        }

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
        checkPercentageAlerts()
        checkProfitAlerts()
    }

    private func syncPanelModel() {
        panelModel.currentSource = dataService.currentSource
        panelModel.allSourcePrices = dataService.allSourcePrices
        panelModel.position = historyManager.position
        panelModel.lastUpdateTime = dataService.lastUpdateTime
        panelModel.appVersion = appVersion
        panelModel.alertCount = historyManager.alerts.count
        panelModel.percentageAlertCount = historyManager.percentageAlerts.count
        panelModel.profitAlertCount = historyManager.profitAlerts.count
    }

    @objc
    private func toggleMainPanel() {
        if let mainPanelWindow, mainPanelWindow.isVisible {
            closeAllPanels()
        } else {
            showMainPanel()
        }
    }

    private func showMainPanel() {
        let window = mainPanelWindow ?? createMainPanelWindow()
        window.appearance = NSApp.effectiveAppearance
        window.contentView?.appearance = NSApp.effectiveAppearance
        syncPanelModel()
        updateMainPanelRootView()

        guard let hostingView = mainPanelHostingView else { return }
        let size = hostingView.fittingSize
        if mainPanelAnchorFrame == nil {
            mainPanelAnchorFrame = currentStatusButtonFrame()
        }
        window.setContentSize(size)
        positionMainPanel(window: window, size: size)
        window.orderFrontRegardless()
        installEventMonitorsIfNeeded()
    }

    private func createMainPanelWindow() -> StatusPopupPanel {
        let window = StatusPopupPanel()
        window.acceptsMouseMovedEvents = true
        window.onOrderOut = { [weak self] in
            self?.handleMainPanelDidHide()
        }
        window.onClose = { [weak self] in
            self?.handleMainPanelDidHide()
        }
        let hostingView = NSHostingView(rootView: makeMainPanelRootView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        mainPanelHostingView = hostingView
        window.contentView = hostingView
        mainPanelWindow = window
        return window
    }

    private func updateMainPanelRootView() {
        mainPanelHostingView?.rootView = makeMainPanelRootView()
    }

    private func makeMainPanelRootView() -> StatusBarMainPanelView {
        StatusBarMainPanelView(
            model: panelModel,
            onPriceHover: { [weak self] source in
                self?.showHoverDetail(.priceChart(source))
            },
            onPositionHover: { [weak self] in
                self?.showHoverDetail(.position)
            },
            onSettingsClick: { [weak self] in
                self?.showHoverDetail(.settings)
            },
            onAlertsClick: { [weak self] in
                self?.showHoverDetail(.alerts)
            },
            onPercentageAlertsClick: { [weak self] in
                self?.showHoverDetail(.percentageAlerts)
            },
            onProfitAlertsClick: { [weak self] in
                self?.showHoverDetail(.profitAlerts)
            },
            onQuit: { [weak self] in
                self?.quitApp()
            }
        )
    }

    private func showHoverDetail(_ kind: DetailPanelKind) {
        NSLog("[GoldPrice] showHoverDetail: \(String(describing: kind))")
        hoverDetailPanelKind = kind
        showChildPanel(for: kind)
    }

    private func clearHoverDetail() {
        hoverDetailPanelKind = nil
        if let pinnedDetailPanelKind {
            showChildPanel(for: pinnedDetailPanelKind)
        } else {
            hideChildPanel()
        }
    }

    private func togglePinnedDetail(_ kind: DetailPanelKind) {
        if pinnedDetailPanelKind == kind {
            if hoverDetailPanelKind != nil {
                hoverDetailPanelKind = nil
                showChildPanel(for: kind)
            } else {
                pinnedDetailPanelKind = nil
                if let hoverDetailPanelKind {
                    showChildPanel(for: hoverDetailPanelKind)
                } else {
                    hideChildPanel()
                }
            }
            return
        }

        pinnedDetailPanelKind = kind
        hoverDetailPanelKind = nil
        showChildPanel(for: kind)
    }

    private var activeDetailPanelKind: DetailPanelKind? {
        hoverDetailPanelKind ?? pinnedDetailPanelKind
    }

    private func showChildPanel(for kind: DetailPanelKind) {
        NSLog("[GoldPrice] showChildPanel start: \(String(describing: kind))")
        guard let (contentView, size) = makeChildPanelContent(for: kind) else { return }
        NSLog("[GoldPrice] showChildPanel content size: \(size.width)x\(size.height)")
        let window = childPanelWindow ?? createChildPanelWindow()
        window.appearance = NSApp.effectiveAppearance
        let container = PopupCardContainerView(contentView: contentView)
        container.frame = NSRect(origin: .zero, size: size)
        container.appearance = NSApp.effectiveAppearance
        window.contentView = container
        window.contentView?.appearance = NSApp.effectiveAppearance
        window.setContentSize(size)
        positionChildPanel(window: window, size: size)
        window.orderFrontRegardless()
        NSLog("[GoldPrice] showChildPanel visible frame: \(window.frame)")
    }

    private func createChildPanelWindow() -> StatusPopupPanel {
        let window = StatusPopupPanel()
        window.acceptsMouseMovedEvents = true
        childPanelWindow = window
        return window
    }

    private func handleMainPanelDidHide() {
        childPanelWindow?.orderOut(nil)
        hoverDetailPanelKind = nil
        pinnedDetailPanelKind = nil
        mainPanelAnchorFrame = nil
        removeEventMonitors()
    }

    private func hideChildPanel() {
        childPanelWindow?.orderOut(nil)
    }

    private func closeAllPanels() {
        mainPanelWindow?.orderOut(nil)
        childPanelWindow?.orderOut(nil)
        hoverDetailPanelKind = nil
        pinnedDetailPanelKind = nil
        mainPanelAnchorFrame = nil
        removeEventMonitors()
    }

    private func refreshVisiblePanels() {
        guard let mainPanelWindow, mainPanelWindow.isVisible else { return }
        updateMainPanelRootView()
        if let hostingView = mainPanelHostingView {
            let size = hostingView.fittingSize
            mainPanelWindow.setContentSize(size)
            positionMainPanel(window: mainPanelWindow, size: size)
        }

        guard let activeDetailPanelKind else { return }
        switch activeDetailPanelKind {
        case .priceChart(let source):
            refreshPriceChildPanel(source: source)
        case .position:
            refreshPositionChildPanel()
        case .settings, .alerts, .percentageAlerts, .profitAlerts:
            break
        }
    }

    private func installEventMonitorsIfNeeded() {
        guard localEventMonitor == nil, globalEventMonitor == nil else { return }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .mouseMoved]) { [weak self] event in
            self?.handleLocalPanelEvent(event)
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .mouseMoved]) { [weak self] event in
            self?.handleGlobalPanelEvent(event)
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func handleLocalPanelEvent(_ event: NSEvent) {
        guard let location = event.window?.convertPoint(toScreen: event.locationInWindow) else { return }
        handlePanelEvent(event, screenLocation: location)
    }

    private func handleGlobalPanelEvent(_ event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.handlePanelEvent(event, screenLocation: event.locationInWindow)
        }
    }

    private func handlePanelEvent(_ event: NSEvent, screenLocation: NSPoint) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            guard !pointIsInsideManagedPanels(screenLocation) && !pointIsInsideStatusButton(screenLocation) else { return }
            closeAllPanels()
        default:
            break
        }
    }

    private func pointIsInsideManagedPanels(_ point: NSPoint) -> Bool {
        if let mainPanelWindow, mainPanelWindow.isVisible, mainPanelWindow.frame.contains(point) {
            return true
        }
        if let childPanelWindow, childPanelWindow.isVisible, childPanelWindow.frame.contains(point) {
            return true
        }
        if let mainPanelWindow,
           let childPanelWindow,
           mainPanelWindow.isVisible,
           childPanelWindow.isVisible {
            let mainFrame = mainPanelWindow.frame
            let childFrame = childPanelWindow.frame

            let corridorMinX = min(mainFrame.maxX, childFrame.maxX)
            let corridorMaxX = max(mainFrame.minX, childFrame.minX)
            let corridorMinY = min(mainFrame.minY, childFrame.minY)
            let corridorMaxY = max(mainFrame.maxY, childFrame.maxY)

            if corridorMaxX > corridorMinX {
                let corridor = NSRect(
                    x: corridorMinX,
                    y: corridorMinY,
                    width: corridorMaxX - corridorMinX,
                    height: corridorMaxY - corridorMinY
                )
                if corridor.contains(point) {
                    return true
                }
            }
        }
        return false
    }

    private func pointIsInsideStatusButton(_ point: NSPoint) -> Bool {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return false }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        return buttonFrame.contains(point)
    }

    private func positionMainPanel(window: NSWindow, size: NSSize) {
        guard let anchorFrame = mainPanelAnchorFrame ?? currentStatusButtonFrame() else { return }
        let visibleFrame = statusItem.button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        var originX = anchorFrame.maxX - size.width
        var originY = anchorFrame.minY - size.height - 8

        originX = min(max(originX, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        originY = max(visibleFrame.minY + 8, originY)

        window.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: size), display: true)
    }

    private func positionChildPanel(window: NSWindow, size: NSSize) {
        guard let mainPanelWindow else { return }
        let visibleFrame = mainPanelWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let spacing: CGFloat = 2

        var originX = mainPanelWindow.frame.maxX + spacing
        if originX + size.width > visibleFrame.maxX - 8 {
            originX = mainPanelWindow.frame.minX - spacing - size.width
        }

        var originY = mainPanelWindow.frame.maxY - size.height
        originY = min(originY, visibleFrame.maxY - size.height - 8)
        originY = max(originY, visibleFrame.minY + 8)

        window.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: size), display: true)
        NSLog("[GoldPrice] positionChildPanel main=\(mainPanelWindow.frame) child=\(window.frame) visible=\(visibleFrame)")
    }

    private func currentStatusButtonFrame() -> NSRect? {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return nil }
        return buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func makeChildPanelContent(for kind: DetailPanelKind) -> (NSView, NSSize)? {
        switch kind {
        case .priceChart(let source):
            guard let view = makePriceChartView(for: source) else { return nil }
            return (view, preferredSize(for: view))
        case .position:
            let view = makePositionDetailView()
            return (view, preferredSize(for: view))
        case .settings:
            let view = SettingsEditorView(
                currentSource: dataService.currentSource,
                onSourceChange: { [weak self] source in
                    self?.dataService.setDataSource(source)
                    self?.updateStatusBarDisplay()
                    self?.syncPanelModel()
                    self?.refreshVisiblePanels()
                },
                onSave: { [weak self] in
                    self?.dataService.reloadRefreshIntervalFromSettings()
                    self?.updateStatusBarDisplay()
                    self?.syncPanelModel()
                    self?.refreshVisiblePanels()
                }
            )
            return (view, preferredSize(for: view))
        case .alerts:
            let view = AlertEditorView()
            return (view, preferredSize(for: view))
        case .percentageAlerts:
            let view = PercentageAlertEditorView()
            return (view, preferredSize(for: view))
        case .profitAlerts:
            let view = ProfitAlertEditorView()
            return (view, preferredSize(for: view))
        }
    }

    private func makePriceChartView(for source: GoldPriceSource) -> ChartMenuItemView? {
        guard let info = dataService.allSourcePrices[source], info.price != "--" else { return nil }

        if usesOfficialIntradayChart(for: source) {
            let latestSeries = officialChartService.latestSeries(for: source)
            let emptyMessage = latestSeries == nil ? domesticChartErrors[source] : nil
            let view = ChartMenuItemView(
                source: source,
                info: info,
                records: latestSeries?.records ?? [],
                chartHigh: latestSeries?.high,
                chartLow: latestSeries?.low,
                isLoading: latestSeries == nil,
                emptyMessage: emptyMessage
            )
            requestDomesticPriceChartUpdate(view: view, source: source)
            return view
        }

        let records = historyManager.getTodayRecords(for: source.rawValue)
        return ChartMenuItemView(source: source, info: info, records: records)
    }

    private func makePositionDetailView() -> NSView {
        let view = PositionDetailPanelView(position: historyManager.position, allSources: GoldPriceSource.domesticSources)

        if let position = historyManager.position,
           let source = position.source,
           let currentPrice = dataService.allSourcePrices[source]?.priceDouble {
            if usesOfficialIntradayChart(for: source) {
                let latestSeries = officialChartService.latestSeries(for: source)
                let profitRecords = latestSeries.map { buildProfitRecords(for: position, records: $0.records) } ?? []
                view.updateChart(
                    position: position,
                    currentPrice: currentPrice,
                    profitRecords: profitRecords,
                    isLoading: latestSeries == nil,
                    emptyMessage: latestSeries == nil ? nil : domesticChartErrors[source]
                )
                requestDomesticPositionChartUpdate(detailView: view, position: position, source: source, currentPrice: currentPrice)
            } else {
                let records = historyManager.getTodayRecords(for: source.rawValue)
                view.updateChart(
                    position: position,
                    currentPrice: currentPrice,
                    profitRecords: buildProfitRecords(for: position, records: records)
                )
            }
        } else {
            view.updateChart(position: nil, currentPrice: nil, profitRecords: [])
        }

        return view
    }

    private func refreshPriceChildPanel(source: GoldPriceSource) {
        guard let childPanelWindow,
              childPanelWindow.isVisible,
              let container = childPanelWindow.contentView as? PopupCardContainerView,
              let view = container.hostedContentView as? ChartMenuItemView,
              let info = dataService.allSourcePrices[source],
              info.price != "--" else { return }

        if usesOfficialIntradayChart(for: source) {
            let latestSeries = officialChartService.latestSeries(for: source)
            let emptyMessage = latestSeries == nil ? domesticChartErrors[source] : nil
            view.update(
                source: source,
                info: info,
                records: latestSeries?.records ?? [],
                chartHigh: latestSeries?.high,
                chartLow: latestSeries?.low,
                isLoading: latestSeries == nil && emptyMessage == nil,
                emptyMessage: emptyMessage
            )
            requestDomesticPriceChartUpdate(view: view, source: source)
        } else {
            let records = historyManager.getTodayRecords(for: source.rawValue)
            view.update(source: source, info: info, records: records)
        }

        let size = preferredSize(for: view)
        container.frame.size = size
        childPanelWindow.setContentSize(size)
        positionChildPanel(window: childPanelWindow, size: size)
    }

    private func refreshPositionChildPanel() {
        guard let childPanelWindow, childPanelWindow.isVisible else { return }
        guard case .position = activeDetailPanelKind else { return }

        guard let detailView = (childPanelWindow.contentView as? PopupCardContainerView)?.hostedContentView as? PositionDetailPanelView else {
            showChildPanel(for: .position)
            return
        }

        if let position = historyManager.position,
           let source = position.source,
           let currentPrice = dataService.allSourcePrices[source]?.priceDouble {
            if usesOfficialIntradayChart(for: source) {
                let latestSeries = officialChartService.latestSeries(for: source)
                let profitRecords = latestSeries.map { buildProfitRecords(for: position, records: $0.records) } ?? []
                detailView.updateChart(
                    position: position,
                    currentPrice: currentPrice,
                    profitRecords: profitRecords,
                    isLoading: latestSeries == nil,
                    emptyMessage: latestSeries == nil ? nil : domesticChartErrors[source]
                )
                requestDomesticPositionChartUpdate(detailView: detailView, position: position, source: source, currentPrice: currentPrice)
            } else {
                let records = historyManager.getTodayRecords(for: source.rawValue)
                detailView.updateChart(
                    position: position,
                    currentPrice: currentPrice,
                    profitRecords: buildProfitRecords(for: position, records: records)
                )
            }
        } else {
            detailView.updateChart(position: nil, currentPrice: nil, profitRecords: [])
        }

        let size = preferredSize(for: detailView)
        if let container = childPanelWindow.contentView as? PopupCardContainerView {
            container.frame.size = size
        }
        childPanelWindow.setContentSize(size)
        positionChildPanel(window: childPanelWindow, size: size)
    }

    private func preferredSize(for view: NSView) -> NSSize {
        view.layoutSubtreeIfNeeded()
        let fitting = view.fittingSize
        if fitting.width > 1, fitting.height > 1 {
            return fitting
        }
        let intrinsic = view.intrinsicContentSize
        if intrinsic.width > 1, intrinsic.height > 1 {
            return intrinsic
        }
        let frame = view.frame.size
        if frame.width > 1, frame.height > 1 {
            return frame
        }
        return NSSize(width: 320, height: 240)
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
        percentageAlertMenuItem = nil
        profitAlertMenuItem = nil
        updateTimeMenuItem = nil
        submenuSources.removeAll()

        // Update time
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeStr = "更新于 \(timeFormatter.string(from: dataService.lastUpdateTime))"
        let timeItem = NSMenuItem(title: timeStr, action: nil, keyEquivalent: "")
        timeItem.isEnabled = false
        timeItem.view = MenuMetaHeaderView(text: timeStr)
        updateTimeMenuItem = timeItem
        menu.addItem(timeItem)

        menu.addItem(NSMenuItem.separator())

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

        // Settings (偏好设置)
        menu.addItem(makeSettingsMenuItem())

        // Alerts (价格提醒)
        menu.addItem(makeAlertMenuItem())

        // Percentage Alerts (涨跌幅提醒)
        menu.addItem(makePercentageAlertMenuItem())

        // Profit Alerts (收益提醒)
        menu.addItem(makeProfitAlertMenuItem())

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
        item.view = MenuNavigationRowView(title: "偏好设置")
        item.submenu = makeDeferredSubmenu(kind: .settings)

        return item
    }
    private func makeAlertMenuItem() -> NSMenuItem {
        let alertCount = historyManager.alerts.count
        let title = alertCount > 0 ? "价格提醒 (\(alertCount))" : "价格提醒"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.view = MenuNavigationRowView(title: title)
        item.submenu = makeDeferredSubmenu(kind: .alerts)
        alertMenuItem = item
        return item
    }

    private func makePercentageAlertMenuItem() -> NSMenuItem {
        let alertCount = historyManager.percentageAlerts.count
        let title = alertCount > 0 ? "涨跌幅提醒 (\(alertCount))" : "涨跌幅提醒"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.view = MenuNavigationRowView(title: title)
        item.submenu = makeDeferredSubmenu(kind: .percentageAlerts)
        percentageAlertMenuItem = item
        return item
    }

    private func makeProfitAlertMenuItem() -> NSMenuItem {
        let alertCount = historyManager.profitAlerts.count
        let title = alertCount > 0 ? "收益提醒 (\(alertCount))" : "收益提醒"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.view = MenuNavigationRowView(title: title)
        item.submenu = makeDeferredSubmenu(kind: .profitAlerts)
        profitAlertMenuItem = item
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
        syncPanelModel()
        refreshVisiblePanels()
        refreshPriceItems()
        refreshPositionItem()
        refreshAlertMenuItemTitle()
        refreshPercentageAlertMenuItemTitle()
        refreshProfitAlertMenuItemTitle()
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
        if let view = item.view as? MenuNavigationRowView {
            view.update(title: title)
        } else {
            item.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ])
        }
    }

    private func refreshPercentageAlertMenuItemTitle() {
        guard let item = percentageAlertMenuItem else { return }
        let alertCount = historyManager.percentageAlerts.count
        let title = alertCount > 0 ? "涨跌幅提醒 (\(alertCount))" : "涨跌幅提醒"
        item.title = title
        if let view = item.view as? MenuNavigationRowView {
            view.update(title: title)
        } else {
            item.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ])
        }
    }

    private func refreshProfitAlertMenuItemTitle() {
        guard let item = profitAlertMenuItem else { return }
        let alertCount = historyManager.profitAlerts.count
        let title = alertCount > 0 ? "收益提醒 (\(alertCount))" : "收益提醒"
        item.title = title
        if let view = item.view as? MenuNavigationRowView {
            view.update(title: title)
        } else {
            item.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ])
        }
    }

    private func refreshUpdateTimeItem() {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeStr = "更新于 \(timeFormatter.string(from: dataService.lastUpdateTime))"
        updateTimeMenuItem?.title = timeStr
        if let view = updateTimeMenuItem?.view as? MenuMetaHeaderView {
            view.update(text: timeStr)
        } else {
            updateTimeMenuItem?.attributedTitle = updateTimeAttributedString(for: timeStr)
        }
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

    private func usesOfficialIntradayChart(for source: GoldPriceSource) -> Bool {
        source == .jdZsFinance || source == .jdMsFinance
    }

    private func refreshPriceSubmenu(_ menu: NSMenu, source: GoldPriceSource) {
        guard let info = dataService.allSourcePrices[source], info.price != "--" else { return }
        if usesOfficialIntradayChart(for: source) {
            let latestSeries = officialChartService.latestSeries(for: source)
            let emptyMessage = latestSeries == nil ? domesticChartErrors[source] : nil

            if let chartView = menu.items.first?.view as? ChartMenuItemView {
                chartView.update(
                    source: source,
                    info: info,
                    records: latestSeries?.records ?? [],
                    chartHigh: latestSeries?.high,
                    chartLow: latestSeries?.low,
                    isLoading: latestSeries == nil && emptyMessage == nil,
                    emptyMessage: emptyMessage
                )
            } else {
                populatePriceSubmenu(menu, source: source)
                return
            }

            if latestSeries != nil || domesticChartErrors[source] == nil {
                requestDomesticPriceChartUpdate(menu: menu, source: source)
            }
            return
        }

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
        if usesOfficialIntradayChart(for: source) {
            let latestSeries = officialChartService.latestSeries(for: source)
            let chartProfitRecords = latestSeries.map { buildProfitRecords(for: position, records: $0.records) } ?? []
            let emptyMessage = latestSeries == nil ? domesticChartErrors[source] : nil

            if let chartView = menu.items.first?.view as? PositionChartMenuItemView {
                chartView.update(
                    position: position,
                    currentPrice: currentPrice,
                    profitRecords: chartProfitRecords,
                    isLoading: latestSeries == nil && emptyMessage == nil,
                    emptyMessage: emptyMessage
                )
            } else {
                populatePositionSubmenu(menu)
                return
            }

            if latestSeries != nil || domesticChartErrors[source] == nil {
                requestDomesticPositionChartUpdate(menu: menu, position: position, source: source, currentPrice: currentPrice)
            }
            return
        }

        let records = historyManager.getTodayRecords(for: source.rawValue)
        let profitRecords = buildProfitRecords(for: position, records: records)
        if let chartView = menu.items.first?.view as? PositionChartMenuItemView {
            chartView.update(position: position, currentPrice: currentPrice, profitRecords: profitRecords)
        } else {
            populatePositionSubmenu(menu)
        }
    }

    private func populatePriceSubmenu(_ menu: NSMenu, source: GoldPriceSource) {
        menu.removeAllItems()
        guard let info = dataService.allSourcePrices[source], info.price != "--" else { return }
        let chartView: ChartMenuItemView

        if usesOfficialIntradayChart(for: source) {
            let latestSeries = officialChartService.latestSeries(for: source)
            let emptyMessage = latestSeries == nil ? nil : domesticChartErrors[source]
            chartView = ChartMenuItemView(
                source: source,
                info: info,
                records: latestSeries?.records ?? [],
                chartHigh: latestSeries?.high,
                chartLow: latestSeries?.low,
                isLoading: latestSeries == nil,
                emptyMessage: emptyMessage
            )
        } else {
            let records = historyManager.getTodayRecords(for: source.rawValue)
            chartView = ChartMenuItemView(source: source, info: info, records: records)
        }

        let chartMenuItem = NSMenuItem()
        chartMenuItem.view = chartView
        menu.addItem(chartMenuItem)

        if usesOfficialIntradayChart(for: source) {
            requestDomesticPriceChartUpdate(menu: menu, source: source)
        }
    }

    private func populatePositionSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()

        if let pos = historyManager.position,
           let source = pos.source,
           let info = dataService.allSourcePrices[source],
           let currentPrice = info.priceDouble {
            let chartView: PositionChartMenuItemView

            if usesOfficialIntradayChart(for: source) {
                let latestSeries = officialChartService.latestSeries(for: source)
                let chartProfitRecords = latestSeries.map { buildProfitRecords(for: pos, records: $0.records) } ?? []
                chartView = PositionChartMenuItemView(
                    position: pos,
                    currentPrice: currentPrice,
                    profitRecords: chartProfitRecords,
                    isLoading: latestSeries == nil,
                    emptyMessage: latestSeries == nil ? nil : domesticChartErrors[source]
                )
            } else {
                let records = historyManager.getTodayRecords(for: source.rawValue)
                let profitRecords = buildProfitRecords(for: pos, records: records)
                chartView = PositionChartMenuItemView(
                    position: pos,
                    currentPrice: currentPrice,
                    profitRecords: profitRecords
                )
            }

            let chartItem = NSMenuItem()
            chartItem.view = chartView
            menu.addItem(chartItem)
            menu.addItem(.separator())

            if usesOfficialIntradayChart(for: source) {
                requestDomesticPositionChartUpdate(menu: menu, position: pos, source: source, currentPrice: currentPrice)
            }
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

    private func populatePercentageAlertsSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let alertView = PercentageAlertEditorView()
        let alertItem = NSMenuItem()
        alertItem.view = alertView
        menu.addItem(alertItem)
    }

    private func populateProfitAlertsSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let alertView = ProfitAlertEditorView()
        let alertItem = NSMenuItem()
        alertItem.view = alertView
        menu.addItem(alertItem)
    }

    private func requestDomesticPriceChartUpdate(menu: NSMenu, source: GoldPriceSource) {
        officialChartService.fetchIntradaySeries(for: source) { [weak self, weak menu] result in
            guard let self, let menu else { return }
            guard let info = self.dataService.allSourcePrices[source], info.price != "--" else { return }
            guard let chartView = menu.items.first?.view as? ChartMenuItemView else { return }

            switch result {
            case .success(let series):
                self.domesticChartErrors[source] = nil
                chartView.update(
                    source: source,
                    info: info,
                    records: series.records,
                    chartHigh: series.high,
                    chartLow: series.low
                )
            case .failure(let error):
                self.domesticChartErrors[source] = error.localizedDescription
                if let latestSeries = self.officialChartService.latestSeries(for: source) {
                    chartView.update(
                        source: source,
                        info: info,
                        records: latestSeries.records,
                        chartHigh: latestSeries.high,
                        chartLow: latestSeries.low
                    )
                } else {
                    chartView.update(
                        source: source,
                        info: info,
                        records: [],
                        isLoading: false,
                        emptyMessage: error.localizedDescription
                    )
                }
            }
        }
    }

    private func requestDomesticPositionChartUpdate(
        menu: NSMenu,
        position: PositionInfo,
        source: GoldPriceSource,
        currentPrice: Double
    ) {
        officialChartService.fetchIntradaySeries(for: source) { [weak self, weak menu] result in
            guard let self, let menu else { return }
            guard let chartView = menu.items.first?.view as? PositionChartMenuItemView else { return }

            switch result {
            case .success(let series):
                self.domesticChartErrors[source] = nil
                chartView.update(
                    position: position,
                    currentPrice: currentPrice,
                    profitRecords: self.buildProfitRecords(for: position, records: series.records)
                )
            case .failure(let error):
                self.domesticChartErrors[source] = error.localizedDescription
                if let latestSeries = self.officialChartService.latestSeries(for: source) {
                    chartView.update(
                        position: position,
                        currentPrice: currentPrice,
                        profitRecords: self.buildProfitRecords(for: position, records: latestSeries.records)
                    )
                } else {
                    chartView.update(
                        position: position,
                        currentPrice: currentPrice,
                        profitRecords: [],
                        isLoading: false,
                        emptyMessage: error.localizedDescription
                    )
                }
            }
        }
    }

    private func requestDomesticPriceChartUpdate(view: ChartMenuItemView, source: GoldPriceSource) {
        officialChartService.fetchIntradaySeries(for: source) { [weak self, weak view] result in
            guard let self, let view else { return }
            guard let info = self.dataService.allSourcePrices[source], info.price != "--" else { return }

            switch result {
            case .success(let series):
                self.domesticChartErrors[source] = nil
                view.update(
                    source: source,
                    info: info,
                    records: series.records,
                    chartHigh: series.high,
                    chartLow: series.low
                )
            case .failure(let error):
                self.domesticChartErrors[source] = error.localizedDescription
                if let latestSeries = self.officialChartService.latestSeries(for: source) {
                    view.update(
                        source: source,
                        info: info,
                        records: latestSeries.records,
                        chartHigh: latestSeries.high,
                        chartLow: latestSeries.low
                    )
                } else {
                    view.update(
                        source: source,
                        info: info,
                        records: [],
                        isLoading: false,
                        emptyMessage: error.localizedDescription
                    )
                }
            }

            self.refreshChildPanelSizeIfNeeded()
        }
    }

    private func requestDomesticPositionChartUpdate(
        view: PositionChartMenuItemView,
        position: PositionInfo,
        source: GoldPriceSource,
        currentPrice: Double
    ) {
        officialChartService.fetchIntradaySeries(for: source) { [weak self, weak view] result in
            guard let self, let view else { return }

            switch result {
            case .success(let series):
                self.domesticChartErrors[source] = nil
                view.update(
                    position: position,
                    currentPrice: currentPrice,
                    profitRecords: self.buildProfitRecords(for: position, records: series.records)
                )
            case .failure(let error):
                self.domesticChartErrors[source] = error.localizedDescription
                if let latestSeries = self.officialChartService.latestSeries(for: source) {
                    view.update(
                        position: position,
                        currentPrice: currentPrice,
                        profitRecords: self.buildProfitRecords(for: position, records: latestSeries.records)
                    )
                } else {
                    view.update(
                        position: position,
                        currentPrice: currentPrice,
                        profitRecords: [],
                        isLoading: false,
                        emptyMessage: error.localizedDescription
                    )
                }
            }

            self.refreshChildPanelSizeIfNeeded()
        }
    }

    private func requestDomesticPositionChartUpdate(
        detailView: PositionDetailPanelView,
        position: PositionInfo,
        source: GoldPriceSource,
        currentPrice: Double
    ) {
        officialChartService.fetchIntradaySeries(for: source) { [weak self, weak detailView] result in
            guard let self, let detailView else { return }

            switch result {
            case .success(let series):
                self.domesticChartErrors[source] = nil
                detailView.updateChart(
                    position: position,
                    currentPrice: currentPrice,
                    profitRecords: self.buildProfitRecords(for: position, records: series.records)
                )
            case .failure(let error):
                self.domesticChartErrors[source] = error.localizedDescription
                if let latestSeries = self.officialChartService.latestSeries(for: source) {
                    detailView.updateChart(
                        position: position,
                        currentPrice: currentPrice,
                        profitRecords: self.buildProfitRecords(for: position, records: latestSeries.records)
                    )
                } else {
                    detailView.updateChart(
                        position: position,
                        currentPrice: currentPrice,
                        profitRecords: [],
                        isLoading: false,
                        emptyMessage: error.localizedDescription
                    )
                }
            }

            self.refreshChildPanelSizeIfNeeded()
        }
    }

    private func refreshChildPanelSizeIfNeeded() {
        guard let childPanelWindow,
              childPanelWindow.isVisible,
              let contentView = childPanelWindow.contentView else { return }
        let size = preferredSize(for: contentView)
        guard size.width > 1, size.height > 1 else { return }
        childPanelWindow.setContentSize(size)
        positionChildPanel(window: childPanelWindow, size: size)
    }

    private func buildProfitRecords(for position: PositionInfo, records: [PriceRecord]) -> [PriceRecord] {
        records.map { record in
            PriceRecord(timestamp: record.timestamp, price: position.profit(currentPrice: record.price))
        }
    }

    private func checkPriceAlerts() {
        let now = Date()
        var alerts = historyManager.alerts
        var didUpdateAlerts = false

        let groupedAlertIDs = Dictionary(grouping: alerts.indices, by: { index in
            priceAlertGroupKey(sourceRawValue: alerts[index].sourceRawValue, condition: alerts[index].condition)
        })

        for index in alerts.indices {
            let alert = alerts[index]

            guard let source = alert.source,
                  let info = dataService.allSourcePrices[source],
                  let currentPrice = info.priceDouble else { continue }

            let activeAlertID = activePriceAlertID(
                in: groupedAlertIDs[priceAlertGroupKey(sourceRawValue: alert.sourceRawValue, condition: alert.condition)] ?? [],
                alerts: alerts,
                currentPrice: currentPrice,
                condition: alert.condition
            )
            let conditionMet = alert.id == activeAlertID
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

    private func activePriceAlertID(
        in indices: [Int],
        alerts: [PriceAlert],
        currentPrice: Double,
        condition: AlertCondition
    ) -> String? {
        let candidates = indices.map { alerts[$0] }

        switch condition {
        case .above:
            return candidates
                .filter { currentPrice >= $0.targetPrice }
                .max(by: { $0.targetPrice < $1.targetPrice })?
                .id
        case .below:
            return candidates
                .filter { currentPrice <= $0.targetPrice }
                .min(by: { $0.targetPrice < $1.targetPrice })?
                .id
        }
    }

    private func priceAlertGroupKey(sourceRawValue: String, condition: AlertCondition) -> String {
        "\(sourceRawValue)|\(condition.rawValue)"
    }

    private func checkPercentageAlerts() {
        let now = Date()
        var alerts = historyManager.percentageAlerts
        var didUpdateAlerts = false

        let groupedAlertIDs = Dictionary(grouping: alerts.indices, by: { index in
            percentageAlertGroupKey(for: alerts[index])
        })

        for index in alerts.indices {
            let alert = alerts[index]
            guard let source = alert.source,
                  let metricValue = percentageMetricValue(for: source, metric: alert.metric) else { continue }

            let activeAlertID = activePercentageAlertID(
                in: groupedAlertIDs[percentageAlertGroupKey(for: alert)] ?? [],
                alerts: alerts,
                currentPercent: metricValue,
                metric: alert.metric
            )
            let conditionMet = alert.id == activeAlertID
            let shouldNotify = shouldNotify(
                repeatMode: alert.repeatMode,
                conditionMet: conditionMet,
                wasConditionMet: alert.wasConditionMet,
                lastTriggeredAt: alert.lastTriggeredAt,
                interval: alert.repeatInterval,
                now: now
            )

            if shouldNotify {
                alerts[index].triggered = true
                alerts[index].lastTriggeredAt = now
                sendPercentageAlertNotification(alert: alert, currentPercent: metricValue)
                didUpdateAlerts = true
            }

            if alerts[index].wasConditionMet != conditionMet {
                alerts[index].wasConditionMet = conditionMet
                didUpdateAlerts = true
            }
        }

        if didUpdateAlerts {
            historyManager.savePercentageAlerts(alerts)
            refreshMenuContent()
        }
    }

    private func activePercentageAlertID(
        in indices: [Int],
        alerts: [PercentageAlert],
        currentPercent: Double,
        metric: PercentageAlertMetric
    ) -> String? {
        let candidates = indices.map { alerts[$0] }

        switch metric {
        case .netChange:
            if currentPercent >= 0 {
                return candidates
                    .filter { $0.normalizedTargetPercent >= 0 && currentPercent >= $0.normalizedTargetPercent }
                    .max(by: { $0.normalizedTargetPercent < $1.normalizedTargetPercent })?
                    .id
            } else {
                return candidates
                    .filter { $0.normalizedTargetPercent < 0 && currentPercent <= $0.normalizedTargetPercent }
                    .min(by: { $0.normalizedTargetPercent < $1.normalizedTargetPercent })?
                    .id
            }
        case .intradayRange:
            return candidates
                .filter { currentPercent >= $0.normalizedTargetPercent }
                .max(by: { $0.normalizedTargetPercent < $1.normalizedTargetPercent })?
                .id
        }
    }

    private func percentageAlertGroupKey(for alert: PercentageAlert) -> String {
        let directionKey: String
        switch alert.metric {
        case .netChange:
            directionKey = alert.normalizedTargetPercent >= 0 ? "up" : "down"
        case .intradayRange:
            directionKey = "range"
        }
        return "\(alert.sourceRawValue)|\(alert.metric.rawValue)|\(directionKey)"
    }

    private func checkProfitAlerts() {
        let now = Date()
        guard let position = historyManager.position,
              let source = position.source,
              let currentPrice = dataService.allSourcePrices[source]?.priceDouble else { return }

        let currentProfit = position.profit(currentPrice: currentPrice)
        let currentRate = position.profitRate(currentPrice: currentPrice)
        var alerts = historyManager.profitAlerts
        var didUpdateAlerts = false

        for index in alerts.indices {
            let alert = alerts[index]
            guard alert.sourceRawValue == source.rawValue else { continue }

            let conditionMet = alert.isConditionMet(currentProfit: currentProfit, currentRate: currentRate)
            let shouldNotify = shouldNotify(
                repeatMode: alert.repeatMode,
                conditionMet: conditionMet,
                wasConditionMet: alert.wasConditionMet,
                lastTriggeredAt: alert.lastTriggeredAt,
                interval: alert.repeatInterval,
                now: now
            )

            if shouldNotify {
                alerts[index].triggered = true
                alerts[index].lastTriggeredAt = now
                sendProfitAlertNotification(alert: alert, currentProfit: currentProfit, currentRate: currentRate)
                didUpdateAlerts = true
            }

            if alerts[index].wasConditionMet != conditionMet {
                alerts[index].wasConditionMet = conditionMet
                didUpdateAlerts = true
            }
        }

        if didUpdateAlerts {
            historyManager.saveProfitAlerts(alerts)
            refreshMenuContent()
        }
    }

    private func shouldNotify(
        repeatMode: AlertRepeatMode,
        conditionMet: Bool,
        wasConditionMet: Bool,
        lastTriggeredAt: Date?,
        interval: AlertRepeatInterval,
        now: Date
    ) -> Bool {
        switch repeatMode {
        case .rearmOnCross:
            return conditionMet && !wasConditionMet
        case .recurring:
            if conditionMet && !wasConditionMet {
                return true
            } else if conditionMet, let lastTriggeredAt {
                return now.timeIntervalSince(lastTriggeredAt) >= TimeInterval(interval.rawValue)
            } else {
                return conditionMet && lastTriggeredAt == nil
            }
        }
    }

    private func percentageMetricValue(for source: GoldPriceSource, metric: PercentageAlertMetric) -> Double? {
        let records = historyManager.getTodayRecords(for: source.rawValue)
        guard let openPrice = records.first?.price, openPrice > 0 else { return nil }

        switch metric {
        case .netChange:
            guard let currentPrice = dataService.allSourcePrices[source]?.priceDouble else { return nil }
            return (currentPrice - openPrice) / openPrice * 100
        case .intradayRange:
            let high = records.map(\.price).max() ?? openPrice
            let low = records.map(\.price).min() ?? openPrice
            return (high - low) / openPrice * 100
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

    private func sendPercentageAlertNotification(alert: PercentageAlert, currentPercent: Double) {
        let thresholdText = alert.comparatorText
        let currentText = PercentageAlert.formattedPercent(currentPercent, alwaysShowSign: alert.metric == .netChange)

        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[GoldPrice] Percentage alert triggered: \(alert.sourceRawValue) \(alert.metric.rawValue) \(thresholdText), current: \(currentText)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(alert.sourceRawValue) \(alert.metric.rawValue) \(thresholdText)"
        content.body = "当前\(alert.metric.rawValue)：\(currentText)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "percentage-alert-\(alert.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[GoldPrice] 涨跌幅通知发送失败: \(error.localizedDescription)")
            } else {
                NSLog("[GoldPrice] 涨跌幅通知已发送: \(content.title)")
            }
        }
    }

    private func sendProfitAlertNotification(alert: ProfitAlert, currentProfit: Double, currentRate: Double) {
        let thresholdText = alert.comparatorText
        let currentText: String

        switch alert.metric {
        case .amount:
            currentText = "\(currentProfit >= 0 ? "+" : "")\(String(format: "%.2f", currentProfit))元"
        case .rate:
            currentText = "\(currentRate >= 0 ? "+" : "")\(String(format: "%.2f", currentRate))%"
        }

        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[GoldPrice] Profit alert triggered: \(alert.sourceRawValue) \(alert.kind.rawValue)\(alert.metric.shortTitle) \(thresholdText), current: \(currentText)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(alert.sourceRawValue) \(alert.kind.rawValue)\(alert.metric.shortTitle) \(thresholdText)"
        content.body = "当前\(alert.kind.rawValue)\(alert.metric.shortTitle)：\(currentText)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "profit-alert-\(alert.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[GoldPrice] 收益提醒通知发送失败: \(error.localizedDescription)")
            } else {
                NSLog("[GoldPrice] 收益提醒通知已发送: \(content.title)")
            }
        }
    }

    // MARK: - Actions

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
        case .percentageAlerts:
            populatePercentageAlertsSubmenu(menu)
        case .profitAlerts:
            populateProfitAlertsSubmenu(menu)
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
