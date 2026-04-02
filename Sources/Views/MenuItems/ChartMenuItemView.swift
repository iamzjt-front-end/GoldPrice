import AppKit
import SwiftUI

extension Color {
    static let goldGreen = Color(red: 75/255, green: 166/255, blue: 110/255)
}

extension NSColor {
    static let goldGreen = NSColor(red: 75/255, green: 166/255, blue: 110/255, alpha: 1)
}

private enum ChartPanelLayout {
    static let panelWidth: CGFloat = 320
    static let panelHeight: CGFloat = 268
    static let placeholderHeight: CGFloat = 88
}

class ChartMenuItemView: NSView {
    private let hostingView: NSHostingView<ChartPanelContent>

    init(
        source: GoldPriceSource,
        info: PriceInfo,
        records: [PriceRecord],
        chartHigh: Double? = nil,
        chartLow: Double? = nil,
        isLoading: Bool = false,
        emptyMessage: String? = nil
    ) {
        self.hostingView = NSHostingView(rootView: ChartPanelContent(
            source: source,
            info: info,
            records: records,
            chartHigh: chartHigh,
            chartLow: chartLow,
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(
        source: GoldPriceSource,
        info: PriceInfo,
        records: [PriceRecord],
        chartHigh: Double? = nil,
        chartLow: Double? = nil,
        isLoading: Bool = false,
        emptyMessage: String? = nil
    ) {
        hostingView.rootView = ChartPanelContent(
            source: source,
            info: info,
            records: records,
            chartHigh: chartHigh,
            chartLow: chartLow,
            isLoading: isLoading,
            emptyMessage: emptyMessage
        )
        let fittingSize = hostingView.fittingSize
        frame.size = NSSize(width: fittingSize.width, height: fittingSize.height)
        hostingView.frame = bounds
        needsDisplay = true
    }
}

private struct ChartPanelContent: View {
    let source: GoldPriceSource
    let info: PriceInfo
    let records: [PriceRecord]
    let chartHigh: Double?
    let chartLow: Double?
    let isLoading: Bool
    let emptyMessage: String?

    private var displayHigh: String {
        if let chartHigh {
            return String(format: "%.2f", chartHigh)
        }
        return info.dayHigh
    }

    private var displayLow: String {
        if let chartLow {
            return String(format: "%.2f", chartLow)
        }
        return info.dayLow
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(source.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline) {
                Text(info.formattedPrice)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.primary)

                Text(source.unit)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                if !info.changeAmount.isEmpty || !info.changeRate.isEmpty {
                    HStack(spacing: 8) {
                        if !info.changeAmount.isEmpty {
                            Text(info.changeAmount)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(info.isUp ? .red : .goldGreen)
                        }
                        if !info.changeRate.isEmpty {
                            Text(info.changeRate)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(info.isUp ? .red : .goldGreen)
                        }
                    }
                }
            }

            if displayHigh != "--" && displayLow != "--" {
                HStack(spacing: 14) {
                    HStack(spacing: 3) {
                        Text("高")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                        Text(displayHigh)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.red)
                    }
                    HStack(spacing: 3) {
                        Text("低")
                            .font(.system(size: 12))
                            .foregroundColor(.goldGreen.opacity(0.8))
                        Text(displayLow)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.goldGreen)
                    }
                    Spacer()
                }
            }

            if records.count >= 2 {
                MiniChartView(
                    records: records,
                    isUp: info.isUp,
                    hoverValueFormatter: { value in
                        "\(String(format: "%.2f", value)) \(source.unit)"
                    },
                    currentHintText: "\(info.formattedPrice) \(source.unit)"
                )
            } else if isLoading {
                Text("加载中...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(height: ChartPanelLayout.placeholderHeight)
            } else if let emptyMessage {
                Text(emptyMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(height: ChartPanelLayout.placeholderHeight)
            } else {
                Text("数据积累中...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(height: ChartPanelLayout.placeholderHeight)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(width: ChartPanelLayout.panelWidth, height: ChartPanelLayout.panelHeight, alignment: .topLeading)
    }
}
