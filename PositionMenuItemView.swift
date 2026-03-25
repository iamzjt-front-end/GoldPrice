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
                    .frame(maxWidth: .infinity)
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

// MARK: - Submenu editor (right-side popover)

class PositionEditorView: EditableMenuItemView {
    init(position: PositionInfo?, allSources: [GoldPriceSource], onSave: @escaping () -> Void) {
        super.init(contentView: NSHostingView(rootView: PositionEditorContent(
            position: position,
            allSources: allSources,
            onSave: onSave
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
    let onSave: () -> Void

    init(position: PositionInfo?, allSources: [GoldPriceSource], onSave: @escaping () -> Void) {
        self.allSources = allSources
        self.onSave = onSave
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
                    onSave()
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
    init(onSave: @escaping () -> Void) {
        super.init(contentView: NSHostingView(rootView: SettingsEditorContent(onSave: onSave)), minWidth: 240)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private struct SettingsEditorContent: View {
    @State private var selectedIcon: String
    @State private var profitDisplay: ProfitDisplayMode
    @State private var saved = false

    private let iconOptions = ["🌕", "💰", "🥇", "⭐", "💛", "🪙", "📈", "G", "Au", ""]

    let onSave: () -> Void

    init(onSave: @escaping () -> Void) {
        self.onSave = onSave
        let s = PriceHistoryManager.shared.settings
        _selectedIcon = State(initialValue: s.statusBarIcon)
        _profitDisplay = State(initialValue: s.profitDisplay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("偏好设置")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

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
                    label: { $0.rawValue },
                    onSelect: {
                        profitDisplay = $0
                        saveSettings()
                    }
                )
            }

            if saved {
                HStack {
                    Spacer()
                    Text("已保存 ✓")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.goldGreen)
                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(width: 220)
    }

    private func saveSettings() {
        let settings = AppSettings(statusBarIcon: selectedIcon, profitDisplay: profitDisplay)
        PriceHistoryManager.shared.saveSettings(settings)
        saved = true
        onSave()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { saved = false }
    }
}
