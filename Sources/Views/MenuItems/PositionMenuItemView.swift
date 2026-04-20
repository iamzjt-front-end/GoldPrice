import AppKit
import SwiftUI

private enum PositionMenuItemLayout {
    static let rowWidth: CGFloat = 300
    static let rowHeight: CGFloat = 56
}

private enum PositionDetailLayout {
    static let panelWidth: CGFloat = 420
}

// MARK: - Base class for editable menu item views (handles focus & paste in NSMenu)

class EditableMenuItemView: NSView {
    fileprivate let hostedContentView: NSView
    fileprivate let minWidth: CGFloat
    private let dynamicallyResizes: Bool
    private var isUpdatingLayoutSize = false

    init(contentView: NSView, minWidth: CGFloat, dynamicallyResizes: Bool = false) {
        self.hostedContentView = contentView
        self.minWidth = minWidth
        self.dynamicallyResizes = dynamicallyResizes
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
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKey()
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

    override func layout() {
        super.layout()
        guard dynamicallyResizes else { return }
        updateLayoutSizeIfNeeded()
    }

    fileprivate func updateLayoutSizeIfNeeded() {
        guard !isUpdatingLayoutSize else { return }
        isUpdatingLayoutSize = true
        defer { isUpdatingLayoutSize = false }

        let size = hostedContentView.fittingSize
        let targetSize = NSSize(width: max(size.width, minWidth), height: size.height)
        guard abs(frame.width - targetSize.width) > 0.5 || abs(frame.height - targetSize.height) > 0.5 else { return }

        frame.size = targetSize
        hostedContentView.frame = bounds

        if let submenuWindow = window {
            var windowFrame = submenuWindow.frame
            let deltaHeight = targetSize.height - windowFrame.height
            windowFrame.size.width = targetSize.width
            windowFrame.size.height = targetSize.height
            windowFrame.origin.y -= deltaHeight
            submenuWindow.setFrame(windowFrame, display: true, animate: true)
        }
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
    private var trackingArea: NSTrackingArea?
    private let onHover: (Bool) -> Void
    private let onActivate: () -> Void
    private let titleLabel = NSTextField(labelWithString: "我的持仓")
    private let gramsLabel = NSTextField(labelWithString: "")
    private let avgPriceLabel = NSTextField(labelWithString: "")
    private let profitLabel = NSTextField(labelWithString: "")
    private let rateLabel = NSTextField(labelWithString: "")
    private let trailingStack = NSStackView()

    init(
        position: PositionInfo,
        currentPrice: Double?,
        onHover: @escaping (Bool) -> Void = { _ in },
        onActivate: @escaping () -> Void = {}
    ) {
        self.onHover = onHover
        self.onActivate = onActivate
        super.init(frame: NSRect(x: 0, y: 0, width: PositionMenuItemLayout.rowWidth, height: PositionMenuItemLayout.rowHeight))
        setupView()
        update(position: position, currentPrice: currentPrice)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        if let trackingArea { addTrackingArea(trackingArea) }
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
    override func mouseDown(with event: NSEvent) { onActivate() }

    func update(position: PositionInfo, currentPrice: Double?) {
        gramsLabel.stringValue = "\(String(format: "%.4f", position.grams))克"
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

        avgPriceLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        avgPriceLabel.textColor = .labelColor

        gramsLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        gramsLabel.textColor = .secondaryLabelColor

        profitLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        rateLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        let leftMetaStack = NSStackView(views: [avgPriceLabel, gramsLabel])
        leftMetaStack.orientation = .vertical
        leftMetaStack.alignment = .leading
        leftMetaStack.spacing = 1

        let leftStack = NSStackView(views: [titleLabel, leftMetaStack])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 3

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
            widthAnchor.constraint(equalToConstant: PositionMenuItemLayout.rowWidth),
            heightAnchor.constraint(equalToConstant: PositionMenuItemLayout.rowHeight),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }
}

class PositionChartMenuItemView: NSView {
    private let hostingView: NSHostingView<PositionChartPanelContent>

    init(
        position: PositionInfo,
        currentPrice: Double,
        profitRecords: [PriceRecord],
        isLoading: Bool = false,
        emptyMessage: String? = nil
    ) {
        let currentProfit = position.profit(currentPrice: currentPrice)
        let currentRate = position.profitRate(currentPrice: currentPrice)

        self.hostingView = NSHostingView(rootView: PositionChartPanelContent(
            position: position,
            currentPrice: currentPrice,
            currentProfit: currentProfit,
            currentRate: currentRate,
            profitRecords: profitRecords,
            isLoading: isLoading,
            emptyMessage: emptyMessage
        ))
        super.init(frame: .zero)
        let fittingSize = hostingView.fittingSize
        self.frame = NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height)
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(
        position: PositionInfo,
        currentPrice: Double,
        profitRecords: [PriceRecord],
        isLoading: Bool = false,
        emptyMessage: String? = nil
    ) {
        let currentProfit = position.profit(currentPrice: currentPrice)
        let currentRate = position.profitRate(currentPrice: currentPrice)

        hostingView.rootView = PositionChartPanelContent(
            position: position,
            currentPrice: currentPrice,
            currentProfit: currentProfit,
            currentRate: currentRate,
            profitRecords: profitRecords,
            isLoading: isLoading,
            emptyMessage: emptyMessage
        )

        let fittingSize = hostingView.fittingSize
        frame.size = NSSize(width: fittingSize.width, height: fittingSize.height)
        hostingView.frame = bounds
        needsDisplay = true
    }
}

class PositionDetailPanelView: NSView {
    private let contentWidth: CGFloat = PositionDetailLayout.panelWidth
    private let infoHostingView: NSHostingView<PositionInfoContent>
    private let dividerContainer = NSView()
    private let divider = NSBox()
    private var chartView: PositionChartMenuItemView?

    init(position: PositionInfo?, allSources: [GoldPriceSource], sourcePrices: [GoldPriceSource: PriceInfo]) {
        self.infoHostingView = NSHostingView(rootView: PositionInfoContent(position: position))
        super.init(frame: .zero)

        wantsLayer = true
        infoHostingView.autoresizingMask = [.width]
        addSubview(infoHostingView)

        dividerContainer.autoresizingMask = [.width]
        divider.boxType = .separator
        divider.autoresizingMask = [.width]
        dividerContainer.addSubview(divider)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updatePosition(_ position: PositionInfo?) {
        infoHostingView.rootView = PositionInfoContent(position: position)
        rebuildLayout()

        guard let window = self.window else { return }
        var frame = window.frame
        let targetSize = self.preferredPanelSize()
        let deltaHeight = targetSize.height - frame.height
        frame.size = targetSize
        frame.origin.y -= deltaHeight
        window.setFrame(frame, display: true, animate: true)
    }

    func updateChart(
        position: PositionInfo?,
        currentPrice: Double?,
        profitRecords: [PriceRecord],
        isLoading: Bool = false,
        emptyMessage: String? = nil
    ) {
        guard let position, let currentPrice else {
            chartView?.removeFromSuperview()
            chartView = nil
            dividerContainer.removeFromSuperview()
            rebuildLayout()
            return
        }

        if let chartView {
            chartView.update(
                position: position,
                currentPrice: currentPrice,
                profitRecords: profitRecords,
                isLoading: isLoading,
                emptyMessage: emptyMessage
            )
        } else {
            let view = PositionChartMenuItemView(
                position: position,
                currentPrice: currentPrice,
                profitRecords: profitRecords,
                isLoading: isLoading,
                emptyMessage: emptyMessage
            )
            view.autoresizingMask = [.width]
            addSubview(view)
            chartView = view
        }

        if dividerContainer.superview == nil {
            addSubview(dividerContainer)
        }

        rebuildLayout()
    }

    override var fittingSize: NSSize {
        preferredPanelSize()
    }

    override var intrinsicContentSize: NSSize {
        preferredPanelSize()
    }

    func preferredPanelSize() -> NSSize {
        NSSize(width: contentWidth, height: calculatedHeight())
    }

    private func calculatedHeight() -> CGFloat {
        let infoHeight = measuredHeight(of: infoHostingView)
        let chartHeight = chartView.map(measuredHeight(of:)) ?? 0
        let dividerHeight: CGFloat = chartView == nil ? 0 : 9
        return chartHeight + dividerHeight + infoHeight
    }

    private func rebuildLayout() {
        let chartHeight = chartView.map(measuredHeight(of:)) ?? 0
        let infoHeight = measuredHeight(of: infoHostingView)
        let dividerHeight: CGFloat = chartView == nil ? 0 : 9
        let totalHeight = chartHeight + dividerHeight + infoHeight

        frame = NSRect(x: 0, y: 0, width: contentWidth, height: totalHeight)

        var currentY = totalHeight

        if let chartView {
            currentY -= chartHeight
            chartView.frame = NSRect(x: 0, y: currentY, width: contentWidth, height: chartHeight)

            currentY -= dividerHeight
            dividerContainer.frame = NSRect(x: 0, y: currentY, width: contentWidth, height: dividerHeight)
            divider.frame = NSRect(x: 14, y: 4, width: contentWidth - 28, height: 1)
        }

        infoHostingView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: infoHeight)
        needsLayout = true
    }

    private func measuredHeight(of view: NSView) -> CGFloat {
        view.layoutSubtreeIfNeeded()
        let fitting = view.fittingSize.height
        if fitting > 1 { return fitting }
        let intrinsic = view.intrinsicContentSize.height
        if intrinsic > 1 { return intrinsic }
        return max(view.frame.height, 1)
    }
}

// MARK: - Position Info (read-only display in position sub-panel)

private struct PositionInfoContent: View {
    let position: PositionInfo?

    var body: some View {
        if let position {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text("持仓概览")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    Spacer(minLength: 0)

                    Text("成本已含手续费")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.orange.opacity(0.95))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                        )
                }

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        heroMetric(
                            title: "持仓均价",
                            value: "\(String(format: "%.2f", position.avgPrice)) 元/克",
                            caption: "买入加权均价"
                        )

                        heroDivider

                        heroMetric(
                            title: "成本价",
                            value: "\(String(format: "%.2f", position.breakEvenPrice)) 元/克",
                            caption: "含手续费保本价"
                        )
                    }

                    Rectangle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 1)
                        .padding(.horizontal, 14)

                    HStack(spacing: 10) {
                        compactMetric(
                            title: "克数",
                            value: "\(String(format: "%.4f", position.grams)) 克"
                        )

                        compactMetric(
                            title: "手续费",
                            value: "\(String(format: "%.2f", position.totalFee)) 元"
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.orange.opacity(0.045),
                                    Color.primary.opacity(0.018)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 0.8)
                )
                .overlay(alignment: .topLeading) {
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.88))
                        .frame(width: 78, height: 3)
                        .padding(.leading, 14)
                        .padding(.top, 1)
                }
            }
            .padding(14)
            .frame(width: PositionDetailLayout.panelWidth, alignment: .leading)
        }
    }

    private var heroDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(width: 1)
            .padding(.vertical, 16)
    }

    private func heroMetric(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 21, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.88))
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private func compactMetric(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(.primary.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 0.7)
        )
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
            VStack(alignment: .leading, spacing: 3) {
                Text("我的持仓")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("均价 \(String(format: "%.2f", position.avgPrice)) 元/克")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("\(String(format: "%.4f", position.grams))克")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
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
    let isLoading: Bool
    let emptyMessage: String?

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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer(minLength: 0)
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

            HStack(alignment: .bottom, spacing: 12) {
                chartMetaMetric(title: "现价", value: "\(String(format: "%.2f", currentPrice)) 元/克")

                Spacer(minLength: 0)

                if let highProfit = highProfit, let lowProfit = lowProfit {
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
            } else if isLoading {
                Text("加载中...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(height: 60)
            } else if let emptyMessage {
                Text(emptyMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(height: 60)
            } else {
                Text("数据积累中...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(height: 60)
            }
        }
        .padding(14)
        .frame(width: PositionDetailLayout.panelWidth)
    }

    private func chartMetaMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Trade Record Editor (right-side popover)

class PositionEditorView: EditableMenuItemView {
    private let hostingView: NSHostingView<TradeRecordListContent>
    private var externalContentChange: (() -> Void)?

    init(
        position: PositionInfo?,
        allSources: [GoldPriceSource],
        sourcePrices: [GoldPriceSource: PriceInfo],
        onContentChange: (() -> Void)? = nil
    ) {
        let hostingView = NSHostingView(rootView: TradeRecordListContent(
            allSources: allSources,
            onContentChange: {}
        ))
        self.hostingView = hostingView
        self.externalContentChange = onContentChange
        super.init(contentView: hostingView, minWidth: PositionDetailLayout.panelWidth, dynamicallyResizes: true)
        hostingView.rootView = TradeRecordListContent(
            allSources: allSources,
            onContentChange: { [weak self] in
                DispatchQueue.main.async {
                    self?.updateLayoutSizeIfNeeded()
                    self?.externalContentChange?()
                }
            }
        )
    }
    required init?(coder: NSCoder) { fatalError() }

    func setOnContentChange(_ handler: @escaping () -> Void) {
        externalContentChange = handler
    }
}

// MARK: - Trade Record List Content

private struct TradeRecordListContent: View {
    let allSources: [GoldPriceSource]
    let onContentChange: () -> Void

    @State private var transactions: [PositionTransaction] = PriceHistoryManager.shared.positionTransactions
    @State private var showAddForm = false
    @State private var showClearConfirmation = false
    @State private var deletingTransactionId: String?
    @State private var feedbackText: String?
    @State private var feedbackIsError = false

    private var sortedTransactions: [PositionTransaction] {
        transactions.sorted {
            if $0.date == $1.date {
                return $0.id > $1.id
            }
            return $0.date > $1.date
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("交易记录")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                if !transactions.isEmpty {
                    if showClearConfirmation {
                        Button("确认清仓") {
                            clearAllTransactions()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("取消") {
                            showClearConfirmation = false
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button(action: {
                            showClearConfirmation = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10, weight: .bold))
                                Text("清仓")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAddForm.toggle()
                    }
                    onContentChange()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showAddForm ? "xmark" : "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(showAddForm ? "取消" : "新增")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Add form
            if showAddForm {
                TradeRecordFormContent(
                    allSources: allSources,
                    onSave: { transaction in
                        PriceHistoryManager.shared.addPositionTransaction(transaction)
                        transactions = PriceHistoryManager.shared.positionTransactions
                        showAddForm = false
                        showFeedback("已添加", isError: false)
                        onContentChange()
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Transaction list
            if sortedTransactions.isEmpty {
                VStack(spacing: 6) {
                    Text("暂无交易记录")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("点击右上角「新增」添加交易记录")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(sortedTransactions, id: \.id) { transaction in
                            transactionRow(transaction)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            // Data source picker
            VStack(alignment: .leading, spacing: 7) {
                Text("收益计算相对数据源")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                segmentedPicker(
                    items: allSources,
                    selected: currentSource,
                    label: { $0.rawValue },
                    onSelect: { newSource in
                        updateSource(newSource)
                    }
                )
            }

            // Feedback
            if let feedbackText {
                Text(feedbackText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(feedbackIsError ? .red : .goldGreen)
            }
        }
        .padding(14)
        .frame(width: PositionDetailLayout.panelWidth, alignment: .leading)
    }

    private var currentSource: GoldPriceSource {
        let sourceRaw = PriceHistoryManager.shared.position?.sourceRawValue
            ?? PriceHistoryManager.shared.positionTransactions.last?.sourceRawValue
            ?? allSources.first?.rawValue
            ?? GoldPriceSource.jdZsFinance.rawValue
        return GoldPriceSource(rawValue: sourceRaw) ?? .jdZsFinance
    }

    private func updateSource(_ newSource: GoldPriceSource) {
        var updated = transactions
        let now = Date()
        for i in updated.indices {
            updated[i].sourceRawValue = newSource.rawValue
        }
        PriceHistoryManager.shared.savePositionTransactions(updated)
        transactions = PriceHistoryManager.shared.positionTransactions
        onContentChange()
    }

    // MARK: - Transaction Row

    private func transactionRow(_ transaction: PositionTransaction) -> some View {
        let isDeleting = deletingTransactionId == transaction.id

        return HStack(alignment: .center, spacing: 8) {
            // Type badge
            Text(transaction.type.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(transaction.type == .buy ? .red : .goldGreen)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(transaction.type == .buy ? Color.red.opacity(0.1) : Color.goldGreen.opacity(0.1))
                .clipShape(Capsule())

            // Details
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("\(String(format: "%.2f", transaction.price)) 元/克")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)

                    Text("\(String(format: "%.4f", transaction.grams))克")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                }

                HStack(spacing: 8) {
                    Text("手续费 \(String(format: "%.2f", transaction.fee))元")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(formatDate(transaction.date))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Delete button / confirm
            if isDeleting {
                Button("确认删除") {
                    deleteTransaction(id: transaction.id)
                }
                .font(.system(size: 10))
                .foregroundColor(.red)
                .buttonStyle(.plain)

                Button("取消") {
                    deletingTransactionId = nil
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    deletingTransactionId = transaction.id
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isDeleting ? Color.red.opacity(0.05) : Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isDeleting ? Color.red.opacity(0.2) : Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }

    private func deleteTransaction(id: String) {
        PriceHistoryManager.shared.removePositionTransaction(id: id)
        transactions = PriceHistoryManager.shared.positionTransactions
        deletingTransactionId = nil
        showFeedback("已删除", isError: false)
        onContentChange()
    }

    private func clearAllTransactions() {
        PriceHistoryManager.shared.clearPosition()
        transactions = PriceHistoryManager.shared.positionTransactions
        showClearConfirmation = false
        showAddForm = false
        showFeedback("已清仓", isError: false)
        onContentChange()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func showFeedback(_ text: String, isError: Bool) {
        feedbackText = text
        feedbackIsError = isError
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            feedbackText = nil
        }
    }
}

// MARK: - Trade Record Form

private struct TradeRecordFormContent: View {
    let allSources: [GoldPriceSource]
    let onSave: (PositionTransaction) -> Void

    @State private var selectedType: PositionTransactionType = .buy
    @State private var priceText: String = ""
    @State private var gramsText: String = ""
    @State private var feeText: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type selector
            segmentedPicker(
                items: PositionTransactionType.allCases,
                selected: selectedType,
                label: { $0.rawValue },
                onSelect: { selectedType = $0 }
            )

            // Input fields
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("均价 (元/克)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    PastableTextField(text: $priceText, placeholder: "例如: 980.50")
                        .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("克数")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    PastableTextField(text: $gramsText, placeholder: "例如: 10.0000")
                        .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("手续费 (元)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    PastableTextField(text: $feeText, placeholder: "例如: 5.00")
                        .frame(width: 80)
                }
            }

            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }

            // Save button
            HStack {
                Spacer()
                Button("保存") {
                    performSave()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func performSave() {
        guard let price = Double(priceText.trimmingCharacters(in: .whitespacesAndNewlines)),
              price > 0 else {
            errorMessage = "请输入有效的均价"
            return
        }
        guard let grams = Double(gramsText.trimmingCharacters(in: .whitespacesAndNewlines)),
              grams > 0 else {
            errorMessage = "请输入有效的克数"
            return
        }
        let fee = Double(feeText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard fee >= 0 else {
            errorMessage = "手续费不能为负数"
            return
        }

        let sourceRawValue = PriceHistoryManager.shared.position?.sourceRawValue
            ?? PriceHistoryManager.shared.positionTransactions.last?.sourceRawValue
            ?? allSources.first?.rawValue
            ?? GoldPriceSource.jdZsFinance.rawValue

        let transaction = PositionTransaction(
            sourceRawValue: sourceRawValue,
            type: selectedType,
            grams: grams,
            price: price,
            fee: fee
        )
        onSave(transaction)
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
        )), minWidth: 320)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private struct SettingsEditorContent: View {
    @State private var selectedIcon: String
    @State private var profitDisplay: ProfitDisplayMode
    @State private var statusBarPriceUsesDailyChangeColor: Bool
    @State private var statusBarDailyChangeUsesColor: Bool
    @State private var statusBarProfitUsesColor: Bool
    @State private var dailyChangeDisplay: DailyChangeDisplayMode
    @State private var refreshIntervalSeconds: Int
    @State private var refreshIntervalText: String
    @State private var selectedStatusBarSources: [GoldPriceSource]
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
        _statusBarPriceUsesDailyChangeColor = State(initialValue: s.statusBarPriceUsesDailyChangeColor)
        _statusBarDailyChangeUsesColor = State(initialValue: s.statusBarDailyChangeUsesColor)
        _statusBarProfitUsesColor = State(initialValue: s.statusBarProfitUsesColor)
        _dailyChangeDisplay = State(initialValue: s.dailyChangeDisplay)
        _refreshIntervalSeconds = State(initialValue: s.refreshInterval)
        _refreshIntervalText = State(initialValue: "\(s.refreshInterval)")
        _selectedStatusBarSources = State(initialValue: s.statusBarSources.isEmpty ? [currentSource] : s.statusBarSources)
        _defaultAlertRepeatInterval = State(initialValue: s.defaultAlertRepeatInterval)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("偏好设置")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            settingsContent

            Spacer(minLength: 0)

            Divider()

            HStack {
                Spacer()
                HStack(spacing: 8) {
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
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("状态栏显示数据源")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text("支持多选。已选顺序就是状态栏显示顺序，第一个会作为主展示源。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(orderedStatusBarSources, id: \.self) { source in
                        statusBarSourceRow(source)
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
                Text("状态栏显示当日金价涨跌")
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

                settingsToggleRow(title: "当日金价涨跌幅颜色", isOn: $statusBarPriceUsesDailyChangeColor)
                settingsToggleRow(title: "当日涨跌幅颜色", isOn: $statusBarDailyChangeUsesColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("状态栏显示总收益")
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

                settingsToggleRow(title: "状态栏收益颜色", isOn: $statusBarProfitUsesColor)
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

                Text("价格满足条件后，重复提醒会遵守此间隔。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func saveSettings() {
        syncRefreshIntervalInput()
        let settings = AppSettings(
            statusBarIcon: selectedIcon,
            statusBarSourceRawValues: selectedStatusBarSources.map(\.rawValue),
            profitDisplay: profitDisplay,
            statusBarPriceUsesDailyChangeColor: statusBarPriceUsesDailyChangeColor,
            statusBarDailyChangeUsesColor: statusBarDailyChangeUsesColor,
            statusBarProfitUsesColor: statusBarProfitUsesColor,
            dailyChangeDisplay: dailyChangeDisplay,
            refreshInterval: refreshIntervalSeconds,
            defaultAlertRepeatInterval: defaultAlertRepeatInterval
        )
        PriceHistoryManager.shared.saveSettings(settings)
        syncExistingAlerts(with: settings)
        onSourceChange(selectedStatusBarSources.first ?? .jdZsFinance)
        onSave()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            saved = false
        }
    }

    private func syncExistingAlerts(with settings: AppSettings) {
        let historyManager = PriceHistoryManager.shared

        let syncedPriceAlerts = historyManager.alerts.map { alert in
            var updated = alert
            updated.repeatMode = .recurring
            updated.repeatInterval = settings.defaultAlertRepeatInterval
            return updated
        }
        historyManager.saveAlerts(syncedPriceAlerts)

        let syncedPercentageAlerts = historyManager.percentageAlerts.map { alert in
            var updated = alert
            updated.repeatMode = .recurring
            updated.repeatInterval = settings.defaultAlertRepeatInterval
            return updated
        }
        historyManager.savePercentageAlerts(syncedPercentageAlerts)

        let syncedProfitAlerts = historyManager.profitAlerts.map { alert in
            var updated = alert
            updated.repeatMode = .recurring
            updated.repeatInterval = settings.defaultAlertRepeatInterval
            return updated
        }
        historyManager.saveProfitAlerts(syncedProfitAlerts)
    }

    private func syncRefreshIntervalInput() {
        let parsed = Int(refreshIntervalText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? refreshIntervalSeconds
        refreshIntervalSeconds = max(1, parsed)
        refreshIntervalText = "\(refreshIntervalSeconds)"
    }

    private var orderedStatusBarSources: [GoldPriceSource] {
        selectedStatusBarSources + GoldPriceSource.allCases.filter { !selectedStatusBarSources.contains($0) }
    }

    private func settingsToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Spacer(minLength: 0)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.top, 2)
    }

    @ViewBuilder
    private func statusBarSourceRow(_ source: GoldPriceSource) -> some View {
        let isSelected = selectedStatusBarSources.contains(source)
        let selectedIndex = selectedStatusBarSources.firstIndex(of: source)

        HStack(spacing: 8) {
            Text(isSelected ? "\(selectedIndex.map { $0 + 1 } ?? 0)" : "•")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 18, height: 18)
                .background(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.isDomestic ? "国内" : "国际")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05)
                        )
                        .clipShape(Capsule())

                    Text(source.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)

                    Text(source.unit)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text(isSelected ? "已显示在状态栏" : "未显示")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Button(action: {
                    moveStatusBarSource(source, offset: -1)
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundColor(canMoveStatusBarSource(source, offset: -1) ? .primary : .secondary.opacity(0.35))
                .disabled(!canMoveStatusBarSource(source, offset: -1))

                Button(action: {
                    moveStatusBarSource(source, offset: 1)
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundColor(canMoveStatusBarSource(source, offset: 1) ? .primary : .secondary.opacity(0.35))
                .disabled(!canMoveStatusBarSource(source, offset: 1))

                Button(action: {
                    toggleStatusBarSource(source)
                }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06),
                    lineWidth: isSelected ? 1 : 0.5
                )
        )
    }

    private func toggleStatusBarSource(_ source: GoldPriceSource) {
        if let index = selectedStatusBarSources.firstIndex(of: source) {
            guard selectedStatusBarSources.count > 1 else { return }
            selectedStatusBarSources.remove(at: index)
        } else {
            selectedStatusBarSources.append(source)
        }
    }

    private func canMoveStatusBarSource(_ source: GoldPriceSource, offset: Int) -> Bool {
        guard let index = selectedStatusBarSources.firstIndex(of: source) else { return false }
        let destination = index + offset
        return destination >= 0 && destination < selectedStatusBarSources.count
    }

    private func moveStatusBarSource(_ source: GoldPriceSource, offset: Int) {
        guard let index = selectedStatusBarSources.firstIndex(of: source) else { return }
        let destination = index + offset
        guard destination >= 0, destination < selectedStatusBarSources.count else { return }
        selectedStatusBarSources.swapAt(index, destination)
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

class ProfitAlertEditorView: EditableMenuItemView {
    private let hostingView: NSHostingView<ProfitAlertEditorContent>

    init() {
        let hostingView = NSHostingView(rootView: ProfitAlertEditorContent(onContentChange: {}))
        self.hostingView = hostingView
        super.init(contentView: hostingView, minWidth: 300)
        hostingView.rootView = ProfitAlertEditorContent(onContentChange: { [weak self] in
            DispatchQueue.main.async {
                self?.updateLayoutSizeIfNeeded()
            }
        })
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
                    .font(.system(size: 16, weight: .semibold))
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
                        repeatMode: .recurring,
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private var compactRepeatSummary: String {
        "提醒间隔 · \(PriceHistoryManager.shared.settings.defaultAlertRepeatInterval.shortLabel)"
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
                    .font(.system(size: 16, weight: .semibold))
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
        "提醒间隔 · \(PriceHistoryManager.shared.settings.defaultAlertRepeatInterval.shortLabel)"
    }

    private var netChangeAlerts: [PercentageAlert] {
        alerts
            .filter { $0.metric == .netChange }
            .sorted { $0.normalizedTargetPercent < $1.normalizedTargetPercent }
    }

    private var intradayRangeAlerts: [PercentageAlert] {
        alerts
            .filter { $0.metric == .intradayRange }
            .sorted { $0.normalizedTargetPercent < $1.normalizedTargetPercent }
    }

    private var percentageAlertTabs: some View {
        HStack(spacing: 18) {
            ForEach(PercentageAlertTab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
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
            let metricAlerts = metric == .netChange ? netChangeAlerts : intradayRangeAlerts

            if metricAlerts.isEmpty {
                Text("暂无提醒规则")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: sharedMetricListHeight, alignment: .center)
            } else if metricAlerts.count <= 4 {
                percentageAlertSection(title: metric.rawValue, alerts: metricAlerts)
                    .frame(height: sharedMetricListHeight, alignment: .top)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    percentageAlertSection(title: metric.rawValue, alerts: metricAlerts)
                }
                .frame(height: sharedMetricListHeight)
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

    private var sharedMetricListHeight: CGFloat {
        let maxCount = max(netChangeAlerts.count, intradayRangeAlerts.count)
        let rowHeight: CGFloat = 28
        let sectionHeaderHeight: CGFloat = 18
        let verticalPadding: CGFloat = 8
        let contentHeight = CGFloat(maxCount) * rowHeight + sectionHeaderHeight + verticalPadding
        return min(max(contentHeight, 44), 120)
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
                repeatMode: .recurring,
                repeatInterval: settings.defaultAlertRepeatInterval
            )
        )
        PriceHistoryManager.shared.savePercentageAlerts(alerts)
        targetText.wrappedValue = ""
    }
}

private struct ProfitAlertEditorContent: View {
    private enum ProfitAlertTab: String, CaseIterable {
        case profit = "浮盈"
        case loss = "浮亏"

        var kind: ProfitAlertKind {
            switch self {
            case .profit: return .profit
            case .loss: return .loss
            }
        }
    }

    @State private var alerts: [ProfitAlert] = PriceHistoryManager.shared.profitAlerts
    @State private var selectedTab: ProfitAlertTab = .profit
    @State private var selectedMetric: ProfitAlertMetric = .amount
    @State private var targetText: String = ""

    let onContentChange: () -> Void

    private var position: PositionInfo? {
        PriceHistoryManager.shared.position
    }

    private var positionSource: GoldPriceSource? {
        position?.source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("收益提醒")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text(compactRepeatSummary)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            profitAlertTabs

            if let position {
                metricEditorSection(position: position)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("请先设置持仓")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("收益提醒依赖持仓克数、买入均价、手续费和收益计算相对数据源。")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
        }
        .padding(14)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            onContentChange()
        }
        .onChange(of: alerts) { _ in
            onContentChange()
        }
    }

    private var compactRepeatSummary: String {
        "提醒间隔 · \(PriceHistoryManager.shared.settings.defaultAlertRepeatInterval.shortLabel)"
    }

    private var filteredAlerts: [ProfitAlert] {
        alerts
            .filter { $0.kind == selectedTab.kind }
            .sorted {
                if $0.metric == $1.metric {
                    return $0.normalizedTargetValue < $1.normalizedTargetValue
                }
                return $0.metric.rawValue < $1.metric.rawValue
            }
    }

    private var profitAlerts: [ProfitAlert] {
        alerts.filter { $0.kind == .profit }
    }

    private var lossAlerts: [ProfitAlert] {
        alerts.filter { $0.kind == .loss }
    }

    private var profitAlertTabs: some View {
        HStack(spacing: 18) {
            ForEach(ProfitAlertTab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
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
                    .frame(width: 50)
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

    private func metricEditorSection(position: PositionInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let sourceName = positionSource?.rawValue ?? position.sourceRawValue

            Text("当前持仓：\(sourceName)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            if filteredAlerts.isEmpty {
                Text("暂无提醒规则")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: sharedListHeight, alignment: .center)
            } else if filteredAlerts.count <= 4 {
                profitAlertSection(title: selectedTab.rawValue, alerts: filteredAlerts)
                    .frame(height: sharedListHeight, alignment: .top)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    profitAlertSection(title: selectedTab.rawValue, alerts: filteredAlerts)
                }
                .frame(height: sharedListHeight)
            }

            Divider()

            Text("添加提醒")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            segmentedPicker(
                items: ProfitAlertMetric.allCases,
                selected: selectedMetric,
                label: { $0.rawValue },
                onSelect: { selectedMetric = $0 }
            )

            HStack(spacing: 6) {
                PastableTextField(
                    text: $targetText,
                    placeholder: selectedMetric == .amount ? "目标金额，如 100" : "目标百分比，如 2"
                )
                .frame(height: 22)

                Text(selectedMetric == .amount ? "元" : "%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(descriptionText)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            HStack {
                Spacer()
                Button("添加") {
                    appendAlert()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var descriptionText: String {
        switch (selectedTab.kind, selectedMetric) {
        case (.profit, .amount):
            return "浮盈金额达到你设置的目标值时提醒，只允许正数。"
        case (.profit, .rate):
            return "浮盈百分比达到你设置的目标值时提醒，只允许正数。"
        case (.loss, .amount):
            return "浮亏金额达到你设置的目标值时提醒，只允许正数。"
        case (.loss, .rate):
            return "浮亏百分比达到你设置的目标值时提醒，只允许正数。"
        }
    }

    private var sharedListHeight: CGFloat {
        let maxCount = max(profitAlerts.count, lossAlerts.count)
        let rowHeight: CGFloat = 28
        let sectionHeaderHeight: CGFloat = 18
        let verticalPadding: CGFloat = 8
        let contentHeight = CGFloat(maxCount) * rowHeight + sectionHeaderHeight + verticalPadding
        return min(contentHeight, 120)
    }

    private func profitAlertSection(title: String, alerts: [ProfitAlert]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.leading, 2)

            ForEach(alerts, id: \.id) { alert in
                profitAlertRow(alert)
            }
        }
    }

    private func profitAlertRow(_ alert: ProfitAlert) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(alert.sourceRawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)

                    Text("\(alert.kind.rawValue)\(alert.metric.shortTitle) \(alert.comparatorText)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }

            Spacer()

            if alert.triggered {
                Button("重置") {
                    PriceHistoryManager.shared.resetProfitAlert(id: alert.id)
                    alerts = PriceHistoryManager.shared.profitAlerts
                }
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .buttonStyle(.plain)
            }

            Button(action: {
                PriceHistoryManager.shared.removeProfitAlert(id: alert.id)
                alerts = PriceHistoryManager.shared.profitAlerts
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

    private func appendAlert() {
        let settings = PriceHistoryManager.shared.settings
        guard let source = positionSource,
              let target = Double(targetText.trimmingCharacters(in: .whitespacesAndNewlines)),
              target > 0 else { return }

        alerts.append(
            ProfitAlert(
                sourceRawValue: source.rawValue,
                kind: selectedTab.kind,
                metric: selectedMetric,
                targetValue: abs(target),
                repeatMode: .recurring,
                repeatInterval: settings.defaultAlertRepeatInterval
            )
        )
        PriceHistoryManager.shared.saveProfitAlerts(alerts)
        targetText = ""
    }
}

// MARK: - Extreme Price Alert editor submenu (新高新低提醒)

class ExtremePriceAlertEditorView: EditableMenuItemView {
    init() {
        super.init(contentView: NSHostingView(rootView: ExtremePriceAlertEditorContent()), minWidth: 300)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private struct ExtremePriceAlertEditorContent: View {
    @State private var configs: [GoldPriceSource: ExtremePriceAlertConfig] = {
        var map: [GoldPriceSource: ExtremePriceAlertConfig] = [:]
        for config in PriceHistoryManager.shared.extremePriceAlertConfigs {
            if let source = config.source {
                map[source] = config
            }
        }
        return map
    }()

    @State private var cooldown: ExtremeAlertCooldown = PriceHistoryManager.shared.settings.extremeAlertCooldown

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("新高新低提醒")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            Text("开启后，当日价格创新高或新低时自动通知。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                ForEach(GoldPriceSource.allCases, id: \.self) { source in
                    sourceRow(source)
                }
            }

            Divider()

            HStack {
                Text("提醒间隔")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Picker("", selection: $cooldown) {
                    ForEach(ExtremeAlertCooldown.allCases, id: \.self) { interval in
                        Text(interval.shortLabel).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .onChange(of: cooldown) { newValue in
                    var settings = PriceHistoryManager.shared.settings
                    settings.extremeAlertCooldown = newValue
                    PriceHistoryManager.shared.saveSettings(settings)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sourceRow(_ source: GoldPriceSource) -> some View {
        let config = configs[source] ?? ExtremePriceAlertConfig(sourceRawValue: source.rawValue, notifyOnNewHigh: false, notifyOnNewLow: false)
        let highOn = config.notifyOnNewHigh
        let lowOn = config.notifyOnNewLow

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Text(source.unit)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            toggleButton(label: "新高", isOn: highOn) {
                var updated = config
                updated.notifyOnNewHigh.toggle()
                save(updated, for: source)
            }

            toggleButton(label: "新低", isOn: lowOn) {
                var updated = config
                updated.notifyOnNewLow.toggle()
                save(updated, for: source)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(config.isEnabled ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    config.isEnabled ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06),
                    lineWidth: config.isEnabled ? 1 : 0.5
                )
        )
    }

    private func toggleButton(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundColor(isOn ? .accentColor : .secondary)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isOn ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isOn ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private func save(_ config: ExtremePriceAlertConfig, for source: GoldPriceSource) {
        configs[source] = config
        PriceHistoryManager.shared.setExtremePriceAlertConfig(config)
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
