import SwiftUI
import AppKit

private struct PriceRowRepresentable: NSViewRepresentable {
    let source: GoldPriceSource
    let info: PriceInfo
    let onHover: (Bool) -> Void
    let onActivate: () -> Void

    func makeNSView(context: Context) -> PriceMenuItemView {
        PriceMenuItemView(source: source, info: info, onHover: onHover, onActivate: onActivate)
    }

    func updateNSView(_ nsView: PriceMenuItemView, context: Context) {
        nsView.update(source: source, info: info)
    }
}

private struct PositionRowRepresentable: NSViewRepresentable {
    let position: PositionInfo
    let currentPrice: Double?
    let onHover: (Bool) -> Void
    let onActivate: () -> Void

    func makeNSView(context: Context) -> PositionDisplayView {
        PositionDisplayView(position: position, currentPrice: currentPrice, onHover: onHover, onActivate: onActivate)
    }

    func updateNSView(_ nsView: PositionDisplayView, context: Context) {
        nsView.update(position: position, currentPrice: currentPrice)
    }
}

final class StatusBarPanelModel: ObservableObject {
    @Published var currentSource: GoldPriceSource = .jdZsFinance
    @Published var allSourcePrices: [GoldPriceSource: PriceInfo] = [:]
    @Published var position: PositionInfo?
    @Published var lastUpdateTime: Date = Date()
    @Published var appVersion: String = "--"
    @Published var alertCount: Int = 0
    @Published var percentageAlertCount: Int = 0
    @Published var profitAlertCount: Int = 0
}

struct HoverPopupContainer<Main: View, Child: View>: View {
    @State private var hoverMain = false
    @State private var hoverChild = false

    let spacing: CGFloat
    let isPinned: Bool
    let isEnabled: Bool
    let onDismissHoverChild: () -> Void
    let main: Main
    let child: Child

    init(
        spacing: CGFloat = 12,
        isPinned: Bool = false,
        isEnabled: Bool,
        onDismissHoverChild: @escaping () -> Void,
        @ViewBuilder main: () -> Main,
        @ViewBuilder child: () -> Child
    ) {
        self.spacing = spacing
        self.isPinned = isPinned
        self.isEnabled = isEnabled
        self.onDismissHoverChild = onDismissHoverChild
        self.main = main()
        self.child = child()
    }

    private var isVisible: Bool {
        isEnabled && (isPinned || hoverMain || hoverChild)
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            main
                .onHover { inside in
                    hoverMain = inside
                    if !inside && !hoverChild && !isPinned {
                        onDismissHoverChild()
                    }
                }

            if isVisible {
                child
                    .onHover { inside in
                        hoverChild = inside
                        if !inside && !hoverMain && !isPinned {
                            onDismissHoverChild()
                        }
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isVisible)
    }
}

struct StatusBarMainPanelView: View {
    @ObservedObject var model: StatusBarPanelModel

    let onPriceHover: (GoldPriceSource) -> Void
    let onPositionHover: () -> Void
    let onSettingsClick: () -> Void
    let onAlertsClick: () -> Void
    let onPercentageAlertsClick: () -> Void
    let onProfitAlertsClick: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("更新于 \(timeText)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Text("版本 v\(model.appVersion)")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary)
            }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 14)

            sectionHeader("国内金价")
                .padding(.top, 10)

            ForEach(GoldPriceSource.domesticSources, id: \.self) { source in
                priceRow(source)
            }

            Divider()
                .padding(.horizontal, 14)
                .padding(.top, 8)

            sectionHeader("国际金价")
                .padding(.top, 10)

            ForEach(GoldPriceSource.internationalSources, id: \.self) { source in
                priceRow(source)
            }

            Divider()
                .padding(.horizontal, 14)
                .padding(.top, 8)

            positionRow
                .padding(.top, 8)

            Divider()
                .padding(.horizontal, 14)
                .padding(.top, 6)

            navigationRow(title: "偏好设置", onHover: onSettingsClick, action: onSettingsClick)
                .padding(.top, 2)
            navigationRow(title: model.alertCount > 0 ? "价格提醒 (\(model.alertCount))" : "价格提醒", onHover: onAlertsClick, action: onAlertsClick)
            navigationRow(title: model.percentageAlertCount > 0 ? "涨跌幅提醒 (\(model.percentageAlertCount))" : "涨跌幅提醒", onHover: onPercentageAlertsClick, action: onPercentageAlertsClick)
            navigationRow(title: model.profitAlertCount > 0 ? "收益提醒 (\(model.profitAlertCount))" : "收益提醒", onHover: onProfitAlertsClick, action: onProfitAlertsClick)

            Divider()
                .padding(.horizontal, 14)
                .padding(.top, 6)

        Button(action: onQuit) {
            HStack {
                Text("退出")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .frame(width: 300, alignment: .leading)
        .background(panelBackground)
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: model.lastUpdateTime)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
    }

    private func priceRow(_ source: GoldPriceSource) -> some View {
        let info = model.allSourcePrices[source] ?? PriceInfo()
        return PriceRowRepresentable(source: source, info: info, onHover: { inside in
            if inside { onPriceHover(source) }
        }, onActivate: {
            onPriceHover(source)
        })
        .frame(width: 280, height: 28)
    }

    private var positionRow: some View {
        Group {
            if let position = model.position {
                let currentPrice = position.source.flatMap { source in
                    model.allSourcePrices[source]?.priceDouble
                }
                PositionRowRepresentable(position: position, currentPrice: currentPrice, onHover: { inside in
                    if inside { onPositionHover() }
                }, onActivate: {
                    onPositionHover()
                })
                .frame(width: 280, height: 44)
            } else {
                HStack {
                    Text("我的持仓")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("未设置")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { onPositionHover() }
                }
            }
        }
    }

    private func navigationRow(title: String, onHover: @escaping () -> Void, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Text("›")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { inside in
            if inside { onHover() }
        }
    }
}
