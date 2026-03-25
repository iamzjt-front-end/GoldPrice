import AppKit
import SwiftUI

// MARK: - Base class for editable menu item views (handles focus & paste in NSMenu)

class EditableMenuItemView: NSView {
    init(contentView: NSView, minWidth: CGFloat) {
        super.init(frame: .zero)
        let size = contentView.fittingSize
        self.frame = NSRect(x: 0, y: 0, width: max(size.width, minWidth), height: size.height)
        contentView.frame = bounds
        contentView.autoresizingMask = [.width, .height]
        addSubview(contentView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let submenuWindow = window else { return }
        var frame = submenuWindow.frame
        frame.origin.x += 8
        submenuWindow.setFrame(frame, display: false)
        DispatchQueue.main.async {
            submenuWindow.makeKey()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let chars = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        let sel: Selector?
        switch chars {
        case "v": sel = #selector(NSText.paste(_:))
        case "c": sel = #selector(NSText.copy(_:))
        case "x": sel = #selector(NSText.cut(_:))
        case "a": sel = #selector(NSText.selectAll(_:))
        case "z":
            sel = event.modifierFlags.contains(.shift)
                ? Selector(("redo:"))
                : #selector(UndoManager.undo)
        default: sel = nil
        }
        if let sel = sel {
            return NSApp.sendAction(sel, to: nil, from: self)
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Shared segmented picker

private func segmentedPicker<T: Hashable>(
    items: [T], selected: T, label: @escaping (T) -> String, onSelect: @escaping (T) -> Void
) -> some View {
    HStack(spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            Button(action: { onSelect(item) }) {
                Text(label(item))
                    .font(.system(size: 11, weight: selected == item ? .semibold : .regular))
                    .foregroundColor(selected == item ? .white : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(selected == item ? Color.accentColor : Color.clear)
            }
            .buttonStyle(.plain)

            if index < items.count - 1 {
                Divider().frame(height: 16)
            }
        }
    }
    .background(Color.primary.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 7))
    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
}

// MARK: - Main menu row (read-only display)

class PositionDisplayView: NSView {
    init(position: PositionInfo, currentPrice: Double?) {
        super.init(frame: .zero)

        let hostingView = NSHostingView(rootView: PositionDisplayContent(
            position: position, currentPrice: currentPrice
        ))
        let size = hostingView.fittingSize
        self.frame = NSRect(x: 0, y: 0, width: max(size.width, 280), height: size.height)
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    required init?(coder: NSCoder) { fatalError() }
}

class PositionChartMenuItemView: NSView {
    init(position: PositionInfo, currentPrice: Double, records: [PriceRecord]) {
        super.init(frame: .zero)

        let profitRecords = records.map { record in
            PriceRecord(timestamp: record.timestamp, price: position.profit(currentPrice: record.price))
        }
        let currentProfit = position.profit(currentPrice: currentPrice)
        let currentRate = position.profitRate(currentPrice: currentPrice)

        let hostingView = NSHostingView(rootView: PositionChartPanelContent(
            position: position,
            currentPrice: currentPrice,
            currentProfit: currentProfit,
            currentRate: currentRate,
            profitRecords: profitRecords
        ))
        let fittingSize = hostingView.fittingSize
        self.frame = NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height)
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private struct PositionDisplayContent: View {
    let position: PositionInfo
    let currentPrice: Double?

    private var profit: Double? {
        guard let cp = currentPrice else { return nil }
        return position.profit(currentPrice: cp)
    }

    private var profitRate: Double? {
        guard let cp = currentPrice else { return nil }
        return position.profitRate(currentPrice: cp)
    }

    private var isProfit: Bool {
        (profit ?? 0) >= 0
    }

    private var profitColor: Color {
        isProfit ? .red : .goldGreen
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("我的持仓")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Text("\(String(format: "%.2f", position.grams))克")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text("均价 \(String(format: "%.2f", position.avgPrice)) 元/克")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let profit = profit, let rate = profitRate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(profit >= 0 ? "+" : "")\(String(format: "%.2f", profit))元")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(profitColor)

                    Text("\(profit >= 0 ? "+" : "")\(String(format: "%.2f", rate))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(profitColor)
                }
            } else {
                Text("--")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct PositionChartPanelContent: View {
    let position: PositionInfo
    let currentPrice: Double
    let currentProfit: Double
    let currentRate: Double
    let profitRecords: [PriceRecord]

    private var isUp: Bool {
        guard let first = profitRecords.first?.price else { return currentProfit >= 0 }
        return currentProfit >= first
    }

    private var profitColor: Color {
        currentProfit >= 0 ? .red : .goldGreen
    }

    private var highProfit: Double? {
        profitRecords.map(\.price).max()
    }

    private var lowProfit: Double? {
        profitRecords.map(\.price).min()
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("我的持仓")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if let source = position.source {
                    Text(source.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(currentProfit >= 0 ? "+" : "")\(String(format: "%.2f", currentProfit))")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(profitColor)

                Text("元")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(currentRate >= 0 ? "+" : "")\(String(format: "%.2f", currentRate))%")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(profitColor)
            }

            HStack(spacing: 12) {
                Text("现价 \(String(format: "%.2f", currentPrice)) 元/克")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if let highProfit = highProfit, let lowProfit = lowProfit {
                    Spacer()

                    HStack(spacing: 3) {
                        Text("高")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                        Text("\(highProfit >= 0 ? "+" : "")\(String(format: "%.2f", highProfit))")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.red)
                    }

                    HStack(spacing: 3) {
                        Text("低")
                            .font(.system(size: 12))
                            .foregroundColor(.goldGreen.opacity(0.8))
                        Text("\(lowProfit >= 0 ? "+" : "")\(String(format: "%.2f", lowProfit))")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.goldGreen)
                    }
                }
            }

            if profitRecords.count >= 2 {
                MiniChartView(records: profitRecords, isUp: isUp)
            } else {
                Text("数据积累中...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(height: 60)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

// MARK: - Submenu editor (right-side popover)

class PositionEditorView: EditableMenuItemView {
    init(position: PositionInfo?, allSources: [GoldPriceSource]) {
        super.init(contentView: NSHostingView(rootView: PositionEditorContent(
            position: position,
            allSources: allSources
        )), minWidth: 240)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private struct PositionEditorContent: View {
    @State private var gramsText: String
    @State private var avgPriceText: String
    @State private var selectedSource: GoldPriceSource
    @State private var saved = false

    let allSources: [GoldPriceSource]

    init(position: PositionInfo?, allSources: [GoldPriceSource]) {
        self.allSources = allSources
        _gramsText = State(initialValue: position.map { String(format: "%.2f", $0.grams) } ?? "")
        _avgPriceText = State(initialValue: position.map { String(format: "%.2f", $0.avgPrice) } ?? "")
        _selectedSource = State(initialValue: position?.source ?? allSources.first ?? .jdZsFinance)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("持仓设置")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 6) {
                Text("持仓克数")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("例如: 10.00", text: $gramsText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("买入均价 (元/克)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("例如: 980.50", text: $avgPriceText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("收益计算相对数据源")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                segmentedPicker(
                    items: allSources,
                    selected: selectedSource,
                    label: { $0.rawValue },
                    onSelect: { selectedSource = $0 }
                )
            }

            HStack {
                Spacer()
                if saved {
                    Text("已保存 ✓")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.goldGreen)
                }
                Button("保存") {
                    guard let grams = Double(gramsText), let avgPrice = Double(avgPriceText),
                          grams > 0, avgPrice > 0 else { return }
                    let pos = PositionInfo(
                        grams: grams,
                        avgPrice: avgPrice,
                        sourceRawValue: selectedSource.rawValue
                    )
                    PriceHistoryManager.shared.savePosition(pos)
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        saved = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}

// MARK: - Settings submenu (偏好设置)

class SettingsEditorView: EditableMenuItemView {
    init(
        currentSource: GoldPriceSource,
        onSourceChange: @escaping (GoldPriceSource) -> Void,
        onSave: @escaping () -> Void
    ) {
        super.init(contentView: NSHostingView(rootView: SettingsEditorContent(
            currentSource: currentSource,
            onSourceChange: onSourceChange,
            onSave: onSave
        )), minWidth: 280)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private struct SettingsEditorContent: View {
    @State private var selectedIcon: String
    @State private var profitDisplay: ProfitDisplayMode
    @State private var refreshIntervalSeconds: Int
    @State private var refreshIntervalText: String
    @State private var selectedSource: GoldPriceSource

    private let iconOptions = ["🌕", "💰", "🥇", "⭐", "💛", "🪙", "📈", "G", "Au", ""]

    let onSourceChange: (GoldPriceSource) -> Void
    let onSave: () -> Void

    init(
        currentSource: GoldPriceSource,
        onSourceChange: @escaping (GoldPriceSource) -> Void,
        onSave: @escaping () -> Void
    ) {
        self.onSourceChange = onSourceChange
        self.onSave = onSave
        let s = PriceHistoryManager.shared.settings
        _selectedIcon = State(initialValue: s.statusBarIcon)
        _profitDisplay = State(initialValue: s.profitDisplay)
        _refreshIntervalSeconds = State(initialValue: s.refreshInterval)
        _refreshIntervalText = State(initialValue: "\(s.refreshInterval)")
        _selectedSource = State(initialValue: currentSource)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("偏好设置")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 6) {
                Text("状态栏显示数据源")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(GoldPriceSource.allCases, id: \.self) { source in
                        Button(action: {
                            selectedSource = source
                            onSourceChange(source)
                            onSave()
                        }) {
                            HStack(spacing: 8) {
                                Text(source.isDomestic ? "国内" : "国际")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(selectedSource == source ? .accentColor : .secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        selectedSource == source ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05)
                                    )
                                    .clipShape(Capsule())

                                Text(source.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)

                                Text(source.unit)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Spacer()

                                Image(systemName: selectedSource == source ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(selectedSource == source ? .accentColor : .secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(selectedSource == source ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(
                                        selectedSource == source ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06),
                                        lineWidth: selectedSource == source ? 1 : 0.5
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("状态栏图标")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button(action: {
                            selectedIcon = icon
                            saveSettings()
                        }) {
                            Text(icon.isEmpty ? "无" : icon)
                                .font(.system(size: icon.count <= 1 && !icon.isEmpty ? 18 : 13))
                                .frame(width: 36, height: 32)
                                .background(selectedIcon == icon ? Color.accentColor : Color.primary.opacity(0.06))
                                .foregroundColor(selectedIcon == icon ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedIcon == icon ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("状态栏显示收益")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                segmentedPicker(
                    items: ProfitDisplayMode.allCases,
                    selected: profitDisplay,
                    label: { mode in
                        switch mode {
                        case .off: return "关"
                        case .amount: return "金额"
                        case .rate: return "收益率"
                        case .both: return "全部"
                        }
                    },
                    onSelect: {
                        profitDisplay = $0
                        saveSettings()
                    }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("刷新频率")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    PastableTextField(text: $refreshIntervalText, placeholder: "秒数")
                        .frame(width: 72, height: 22)

                    Text("s")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    Button("应用") {
                        applyRefreshInterval()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text("支持自定义整数秒，最小 1s。当前: \(refreshIntervalSeconds)s")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

        }
        .padding(14)
        .frame(width: 280)
    }

    private func saveSettings() {
        let settings = AppSettings(
            statusBarIcon: selectedIcon,
            profitDisplay: profitDisplay,
            refreshInterval: refreshIntervalSeconds
        )
        PriceHistoryManager.shared.saveSettings(settings)
        onSave()
    }

    private func applyRefreshInterval() {
        let parsed = Int(refreshIntervalText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? refreshIntervalSeconds
        refreshIntervalSeconds = max(1, parsed)
        refreshIntervalText = "\(refreshIntervalSeconds)"
        saveSettings()
    }
}

// MARK: - Alert editor submenu (价格提醒)

class AlertEditorView: EditableMenuItemView {
    init() {
        super.init(contentView: NSHostingView(rootView: AlertEditorContent()), minWidth: 360)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private struct AlertEditorContent: View {
    @State private var alerts: [PriceAlert] = PriceHistoryManager.shared.alerts
    @State private var selectedSource: GoldPriceSource = .jdZsFinance
    @State private var selectedCondition: AlertCondition = .above
    @State private var selectedRepeatMode: AlertRepeatMode = .rearmOnCross
    @State private var selectedRepeatInterval: AlertRepeatInterval = .fifteenMinutes
    @State private var priceText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("价格提醒")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            if alerts.isEmpty {
                Text("暂无提醒规则")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                let aboveAlerts = alerts.filter { $0.condition == .above }.sorted { $0.targetPrice < $1.targetPrice }
                let belowAlerts = alerts.filter { $0.condition == .below }.sorted { $0.targetPrice > $1.targetPrice }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        if !aboveAlerts.isEmpty {
                            alertSection(title: "📈 高于", alerts: aboveAlerts)
                        }
                        if !belowAlerts.isEmpty {
                            alertSection(title: "📉 低于", alerts: belowAlerts)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            Text("添加提醒")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            segmentedPicker(
                items: GoldPriceSource.allCases,
                selected: selectedSource,
                label: { $0.rawValue },
                onSelect: { selectedSource = $0 }
            )

            HStack(spacing: 6) {
                segmentedPicker(
                    items: AlertCondition.allCases,
                    selected: selectedCondition,
                    label: { $0.rawValue },
                    onSelect: { selectedCondition = $0 }
                )
                .frame(width: 90)

                PastableTextField(text: $priceText, placeholder: "目标价格")
                    .frame(height: 22)
            }

            Text("提醒方式")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(AlertRepeatMode.allCases, id: \.self) { mode in
                    Button(action: {
                        selectedRepeatMode = mode
                    }) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: selectedRepeatMode == mode ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13))
                                .foregroundColor(selectedRepeatMode == mode ? .accentColor : .secondary)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)

                                Text(mode.detailDescription)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(selectedRepeatMode == mode ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(
                                    selectedRepeatMode == mode ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.06),
                                    lineWidth: selectedRepeatMode == mode ? 1 : 0.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedRepeatMode == .recurring {
                Text("提醒间隔")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                segmentedPicker(
                    items: AlertRepeatInterval.allCases,
                    selected: selectedRepeatInterval,
                    label: { $0.shortLabel },
                    onSelect: { selectedRepeatInterval = $0 }
                )
            }

            HStack {
                Spacer()
                Button("添加") {
                    guard let price = Double(priceText), price > 0 else { return }
                    let alert = PriceAlert(
                        sourceRawValue: selectedSource.rawValue,
                        condition: selectedCondition,
                        targetPrice: price,
                        repeatMode: selectedRepeatMode,
                        repeatInterval: selectedRepeatInterval
                    )
                    PriceHistoryManager.shared.addAlert(alert)
                    alerts = PriceHistoryManager.shared.alerts
                    priceText = ""
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func alertSection(title: String, alerts: [PriceAlert]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.leading, 2)

            ForEach(alerts, id: \.id) { alert in
                alertRow(alert)
            }
        }
    }

    private func alertRow(_ alert: PriceAlert) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(alert.sourceRawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)

                    Text("\(alert.condition.rawValue) \(String(format: "%.2f", alert.targetPrice))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }

                Text(alert.repeatSummary)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if alert.triggered {
                Button("重置") {
                    PriceHistoryManager.shared.resetAlert(id: alert.id)
                    self.alerts = PriceHistoryManager.shared.alerts
                }
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .buttonStyle(.plain)
            }

            Button(action: {
                PriceHistoryManager.shared.removeAlert(id: alert.id)
                self.alerts = PriceHistoryManager.shared.alerts
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - NSTextField wrapper for use in NSMenu

private struct PastableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.placeholderString = placeholder
        tf.font = .systemFont(ofSize: 13)
        tf.isBordered = true
        tf.isBezeled = true
        tf.bezelStyle = .roundedBezel
        tf.delegate = context.coordinator
        tf.stringValue = text
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PastableTextField
        init(_ parent: PastableTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }
    }
}
