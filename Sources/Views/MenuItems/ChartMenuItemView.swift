import AppKit
import SwiftUI

extension Color {
    static let goldGreen = Color(red: 99/255, green: 171/255, blue: 142/255)
}

extension NSColor {
    static let goldGreen = NSColor(red: 99/255, green: 171/255, blue: 142/255, alpha: 1)
}

class SubmenuOffsetView: NSView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let w = window else { return }
        var frame = w.frame
        frame.origin.x += 8
        w.setFrame(frame, display: false)
    }
}

class ChartMenuItemView: NSView {
    private let hostingView: NSHostingView<ChartPanelContent>

    init(source: GoldPriceSource, info: PriceInfo, records: [PriceRecord]) {
        self.hostingView = NSHostingView(rootView: ChartPanelContent(
            source: source, info: info, records: records
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
        guard let submenuWindow = window else { return }
        var frame = submenuWindow.frame
        frame.origin.x += 8
        submenuWindow.setFrame(frame, display: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(source: GoldPriceSource, info: PriceInfo, records: [PriceRecord]) {
        hostingView.rootView = ChartPanelContent(source: source, info: info, records: records)
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

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(source.rawValue)
                    .font(.system(size: 14, weight: .semibold))
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

            if info.dayHigh != "--" && info.dayLow != "--" {
                HStack(spacing: 14) {
                    HStack(spacing: 3) {
                        Text("高")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                        Text(info.dayHigh)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.red)
                    }
                    HStack(spacing: 3) {
                        Text("低")
                            .font(.system(size: 12))
                            .foregroundColor(.goldGreen.opacity(0.8))
                        Text(info.dayLow)
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
