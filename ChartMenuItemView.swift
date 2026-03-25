import AppKit
import SwiftUI

extension Color {
    static let goldGreen = Color(red: 74/255, green: 222/255, blue: 128/255)
}

extension NSColor {
    static let goldGreen = NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 1)
}

class SubmenuOffsetView: NSView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let w = window else { return }
        var f = w.frame
        f.origin.x += 8
        w.setFrame(f, display: false)
    }
}

class ChartMenuItemView: NSView {
    private let source: GoldPriceSource
    private let info: PriceInfo
    private let records: [PriceRecord]

    private let viewWidth: CGFloat = 260
    private let viewHeight: CGFloat = 180

    init(source: GoldPriceSource, info: PriceInfo, records: [PriceRecord]) {
        self.source = source
        self.info = info
        self.records = records
        super.init(frame: .zero)

        let hostingView = NSHostingView(rootView: ChartPanelContent(
            source: source, info: info, records: records
        ))
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

                if !info.changeRate.isEmpty {
                    HStack(spacing: 3) {
                        Text(info.isUp ? "↑" : "↓")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(info.isUp ? .red : .goldGreen)
                        Text(info.changeRate)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(info.isUp ? .red : .goldGreen)
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
                MiniChartView(records: records, isUp: info.isUp)
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
