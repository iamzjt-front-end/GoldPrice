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
    private let titleLabel = NSTextField(labelWithString: "我的持仓")
    private let gramsLabel = NSTextField(labelWithString: "")
    private let avgPriceLabel = NSTextField(labelWithString: "")
    private let profitLabel = NSTextField(labelWithString: "")
    private let rateLabel = NSTextField(labelWithString: "")
    private let trailingStack = NSStackView()

    init(position: PositionInfo, currentPrice: Double?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 44))
        setupView()
        update(position: position, currentPrice: currentPrice)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(position: PositionInfo, currentPrice: Double?) {
        gramsLabel.stringValue = "\(String(format: "%.2f", position.grams))克"
        avgPriceLabel.stringValue = "均价 \(String(format: "%.2f", position.avgPrice)) 元/克"

        if let currentPrice {
            let profit = position.profit(currentPrice: currentPrice)
            let rate = position.profitRate(currentPrice: currentPrice)
            let color = profit >= 0 ? NSColor.systemRed : .goldGreen
            profitLabel.stringValue = "\(profit >= 0 ? "+" : "")\(String(format: "%.2f", profit))元"
            rateLabel.stringValue = "\(profit >= 0 ? "+" : "")\(String(format: "%.2f", rate))%"
            profitLabel.textColor = color
            rateLabel.textColor = color
            trailingStack.isHidden = false
        } else {
            trailingStack.isHidden = true
        }

        needsDisplay = true
    }

    private func setupView() {
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        gramsLabel.font = .systemFont(ofSize: 13, weight: .medium)
        gramsLabel.textColor = .labelColor

        avgPriceLabel.font = .systemFont(ofSize: 11)
        avgPriceLabel.textColor = .secondaryLabelColor

        profitLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        rateLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        let leftMetaStack = NSStackView(views: [gramsLabel, avgPriceLabel])
        leftMetaStack.orientation = .horizontal
        leftMetaStack.alignment = .centerY
        leftMetaStack.spacing = 6

        let leftStack = NSStackView(views: [titleLabel, leftMetaStack])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 2

        trailingStack.orientation = .vertical
        trailingStack.alignment = .trailing
        trailingStack.spacing = 2
        trailingStack.addArrangedSubview(profitLabel)
        trailingStack.addArrangedSubview(rateLabel)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let container = NSStackView(views: [leftStack, spacer, trailingStack])
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        addSubview(container)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 280),
            heightAnchor.constraint(equalToConstant: 44),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }
}

class PositionChartMenuItemView: NSView {
    private let hostingView: NSHostingView<PositionChartPanelContent>

    init(position: PositionInfo, currentPrice: Double, records: [PriceRecord]) {
        let profitRecords = records.map { record in
            PriceRecord(timestamp: record.timestamp, price: position.profit(currentPrice: record.price))
        }
        let currentProfit = position.profit(currentPrice: currentPrice)
        let currentRate = position.profitRate(currentPrice: currentPrice)

        self.hostingView = NSHostingView(rootView: PositionChartPanelContent(
            position: position,
            currentPrice: currentPrice,
            currentProfit: currentProfit,
            currentRate: currentRate,
            profitRecords: profitRecords
        ))
        super.init(frame: .zero)
        let fittingSize = hostingView.fittingSize
        self.frame = NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height)
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(position: PositionInfo, currentPrice: Double, records: [PriceRecord]) {
        let profitRecords = records.map { record in
            PriceRecord(timestamp: record.timestamp, price: position.profit(currentPrice: record.price))
        }
        let currentProfit = position.profit(currentPrice: currentPrice)
        let currentRate = position.profitRate(currentPrice: currentPrice)

        hostingView.rootView = PositionChartPanelContent(
            position: position,
            currentPrice: currentPrice,
            currentProfit: currentProfit,
            currentRate: currentRate,
            profitRecords: profitRecords
        )

        let fittingSize = hostingView.fittingSize
        frame.size = NSSize(width: fittingSize.width, height: fittingSize.height)
        hostingView.frame = bounds
        needsDisplay = true
    }
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
        currentProfit >= 0
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
                MiniChartView(
                    records: profitRecords,
                    isUp: isUp,
                    hoverValueFormatter: { value in
                        "\(value >= 0 ? "+" : "")\(String(format: "%.2f", value)) 元"
                    },
                    currentHintText: "\(currentProfit >= 0 ? "+" : "")\(String(format: "%.2f", currentProfit)) 元"
                )
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
        )), minWidth: 320)
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
                    .frame(width: 120)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("买入均价 (元/克)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("例如: 980.50", text: $avgPriceText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .frame(width: 120)
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
        .frame(width: 320)
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
    private enum SettingsTab: String, CaseIterable {
        case display = "显示"
        case alerts = "提醒"
    }

    @State private var selectedTab: SettingsTab = .display
    @State private var selectedIcon: String
    @State private var profitDisplay: ProfitDisplayMode
    @State private var dailyChangeDisplay: DailyChangeDisplayMode
    @State private var refreshIntervalSeconds: Int
    @State private var refreshIntervalText: String
    @State private var selectedSource: GoldPriceSource
    @State private var defaultAlertRepeatMode: AlertRepeatMode
    @State private var defaultAlertRepeatInterval: AlertRepeatInterval
    @State private var saved = false

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
        _dailyChangeDisplay = State(initialValue: s.dailyChangeDisplay)
        _refreshIntervalSeconds = State(initialValue: s.refreshInterval)
        _refreshIntervalText = State(initialValue: "\(s.refreshInterval)")
        _selectedSource = State(initialValue: currentSource)
        _defaultAlertRepeatMode = State(initialValue: s.defaultAlertRepeatMode)
        _defaultAlertRepeatInterval = State(initialValue: s.defaultAlertRepeatInterval)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("偏好设置")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            settingsTabs

            Group {
                switch selectedTab {
                case .display:
                    displaySettingsSection
                case .alerts:
                    alertSettingsSection
                }
            }

            Spacer(minLength: 0)

            Divider()

            HStack {
                Spacer()
                if saved {
                    Text("已保存 ✓")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.goldGreen)
                }
                Button("保存") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var settingsTabs: some View {
        HStack(spacing: 18) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)

                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                            .clipShape(Capsule())
                    }
                    .frame(width: 34)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var displaySettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("状态栏显示数据源")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(GoldPriceSource.allCases, id: \.self) { source in
                        Button(action: {
                            selectedSource = source
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
                Text("状态栏显示当日涨跌")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                segmentedPicker(
                    items: DailyChangeDisplayMode.allCases,
                    selected: dailyChangeDisplay,
                    label: { mode in
                        switch mode {
                        case .off: return "关"
                        case .amount: return "金额"
                        case .rate: return "涨跌幅"
                        case .both: return "全部"
                        }
                    },
                    onSelect: {
                        dailyChangeDisplay = $0
                    }
                )
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
                }

                Text("支持自定义整数秒，最小 1s。当前: \(refreshIntervalSeconds)s")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var alertSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(AlertRepeatMode.allCases, id: \.self) { mode in
                    Button(action: {
                        defaultAlertRepeatMode = mode
                    }) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: defaultAlertRepeatMode == mode ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13))
                                .foregroundColor(defaultAlertRepeatMode == mode ? .accentColor : .secondary)
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
                        .background(defaultAlertRepeatMode == mode ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(
                                    defaultAlertRepeatMode == mode ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.06),
                                    lineWidth: defaultAlertRepeatMode == mode ? 1 : 0.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if defaultAlertRepeatMode == .recurring {
                VStack(alignment: .leading, spacing: 6) {
                    Text("默认提醒间隔")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    segmentedPicker(
                        items: AlertRepeatInterval.allCases,
                        selected: defaultAlertRepeatInterval,
                        label: { $0.shortLabel },
                        onSelect: {
                            defaultAlertRepeatInterval = $0
                        }
                    )
                }
            }
        }
    }

    private func saveSettings() {
        syncRefreshIntervalInput()
        let settings = AppSettings(
            statusBarIcon: selectedIcon,
            profitDisplay: profitDisplay,
            dailyChangeDisplay: dailyChangeDisplay,
            refreshInterval: refreshIntervalSeconds,
            defaultAlertRepeatMode: defaultAlertRepeatMode,
            defaultAlertRepeatInterval: defaultAlertRepeatInterval
        )
        PriceHistoryManager.shared.saveSettings(settings)
        onSourceChange(selectedSource)
        onSave()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            saved = false
        }
    }

    private func syncRefreshIntervalInput() {
        let parsed = Int(refreshIntervalText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? refreshIntervalSeconds
        refreshIntervalSeconds = max(1, parsed)
        refreshIntervalText = "\(refreshIntervalSeconds)"
    }
}

// MARK: - Alert editor submenu (价格提醒)

class AlertEditorView: EditableMenuItemView {
    init() {
        super.init(contentView: NSHostingView(rootView: AlertEditorContent()), minWidth: 300)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class PercentageAlertEditorView: EditableMenuItemView {
    init() {
        super.init(contentView: NSHostingView(rootView: PercentageAlertEditorContent()), minWidth: 300)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private struct AlertEditorContent: View {
    @State private var alerts: [PriceAlert] = PriceHistoryManager.shared.alerts
    @State private var selectedSource: GoldPriceSource = .jdZsFinance
    @State private var selectedCondition: AlertCondition = .above
    @State private var priceText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("价格提醒")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text(compactRepeatSummary)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

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

            HStack {
                Spacer()
                Button("添加") {
                    let settings = PriceHistoryManager.shared.settings
                    guard let price = Double(priceText), price > 0 else { return }
                    let alert = PriceAlert(
                        sourceRawValue: selectedSource.rawValue,
                        condition: selectedCondition,
                        targetPrice: price,
                        repeatMode: settings.defaultAlertRepeatMode,
                        repeatInterval: settings.defaultAlertRepeatInterval
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
        .frame(width: 300)
    }

    private var defaultRepeatSummary: String {
        let settings = PriceHistoryManager.shared.settings
        switch settings.defaultAlertRepeatMode {
        case .rearmOnCross:
            return "新提醒默认使用：重新穿越。可在“偏好设置”中修改。"
        case .recurring:
            return "新提醒默认使用：持续提醒，间隔\(settings.defaultAlertRepeatInterval.shortLabel)。可在“偏好设置”中修改。"
        }
    }

    private var compactRepeatSummary: String {
        let settings = PriceHistoryManager.shared.settings
        switch settings.defaultAlertRepeatMode {
        case .rearmOnCross:
            return "重新穿越"
        case .recurring:
            return "持续提醒 · \(settings.defaultAlertRepeatInterval.shortLabel)"
        }
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

                    Text("\(alert.condition.displayText) \(String(format: "%.2f", alert.targetPrice))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }
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
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PercentageAlertEditorContent: View {
    private enum PercentageAlertTab: String, CaseIterable {
        case netChange = "净涨跌幅"
        case intradayRange = "波动幅度"

        var metric: PercentageAlertMetric {
            switch self {
            case .netChange: return .netChange
            case .intradayRange: return .intradayRange
            }
        }
    }

    @State private var alerts: [PercentageAlert] = PriceHistoryManager.shared.percentageAlerts
    @State private var selectedTab: PercentageAlertTab = .netChange
    @State private var netChangeSource: GoldPriceSource = .jdZsFinance
    @State private var intradayRangeSource: GoldPriceSource = .jdZsFinance
    @State private var netChangeTargetText: String = ""
    @State private var intradayRangeTargetText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("涨跌幅提醒")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text(compactRepeatSummary)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            percentageAlertTabs

            Group {
                switch selectedTab {
                case .netChange:
                    metricEditorSection(
                        metric: .netChange,
                        source: $netChangeSource,
                        targetText: $netChangeTargetText,
                        placeholder: "目标幅度，如 2 或 -2",
                        description: "净涨跌幅按开盘价到当前价计算；负数表示下跌幅度。"
                    )
                case .intradayRange:
                    metricEditorSection(
                        metric: .intradayRange,
                        source: $intradayRangeSource,
                        targetText: $intradayRangeTargetText,
                        placeholder: "目标波动幅度，如 2",
                        description: "波动幅度按当日最高价与最低价差值，相对开盘价计算，只允许正数。"
                    )
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var compactRepeatSummary: String {
        let settings = PriceHistoryManager.shared.settings
        switch settings.defaultAlertRepeatMode {
        case .rearmOnCross:
            return "重新穿越"
        case .recurring:
            return "持续提醒 · \(settings.defaultAlertRepeatInterval.shortLabel)"
        }
    }

    private var percentageAlertTabs: some View {
        HStack(spacing: 18) {
            ForEach(PercentageAlertTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)

                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                            .clipShape(Capsule())
                    }
                    .frame(width: tab == .netChange ? 56 : 50)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private func metricEditorSection(
        metric: PercentageAlertMetric,
        source: Binding<GoldPriceSource>,
        targetText: Binding<String>,
        placeholder: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let metricAlerts = alerts
                .filter { $0.metric == metric }
                .sorted { $0.normalizedTargetPercent < $1.normalizedTargetPercent }

            if metricAlerts.isEmpty {
                Text("暂无提醒规则")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    percentageAlertSection(title: metric.rawValue, alerts: metricAlerts)
                }
                .frame(height: 100)
            }

            Divider()

            Text("添加提醒")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            segmentedPicker(
                items: GoldPriceSource.allCases,
                selected: source.wrappedValue,
                label: { $0.rawValue },
                onSelect: { source.wrappedValue = $0 }
            )

            HStack(spacing: 6) {
                PastableTextField(text: targetText, placeholder: placeholder)
                    .frame(height: 22)

                Text("%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(description)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            HStack {
                Spacer()
                Button("添加") {
                    appendAlert(metric: metric, source: source.wrappedValue, targetText: targetText)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func percentageAlertSection(title: String, alerts: [PercentageAlert]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.leading, 2)

            ForEach(alerts, id: \.id) { alert in
                percentageAlertRow(alert)
            }
        }
    }

    private func percentageAlertRow(_ alert: PercentageAlert) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(alert.sourceRawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)

                    Text("\(alert.metric.rawValue) \(alert.comparatorText)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }

            Spacer()

            if alert.triggered {
                Button("重置") {
                    if let index = alerts.firstIndex(where: { $0.id == alert.id }) {
                        alerts[index].triggered = false
                        alerts[index].lastTriggeredAt = nil
                        alerts[index].wasConditionMet = false
                        PriceHistoryManager.shared.savePercentageAlerts(alerts)
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .buttonStyle(.plain)
            }

            Button(action: {
                alerts.removeAll { $0.id == alert.id }
                PriceHistoryManager.shared.savePercentageAlerts(alerts)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func appendAlert(metric: PercentageAlertMetric, source: GoldPriceSource, targetText: Binding<String>) {
        let settings = PriceHistoryManager.shared.settings
        guard let target = Double(targetText.wrappedValue) else { return }
        let normalizedTarget = metric == .intradayRange ? abs(target) : target
        alerts.append(
            PercentageAlert(
                sourceRawValue: source.rawValue,
                metric: metric,
                targetPercent: normalizedTarget,
                repeatMode: settings.defaultAlertRepeatMode,
                repeatInterval: settings.defaultAlertRepeatInterval
            )
        )
        PriceHistoryManager.shared.savePercentageAlerts(alerts)
        targetText.wrappedValue = ""
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
