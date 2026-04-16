import SwiftUI

struct PriceChartPanel: View {
    let source: GoldPriceSource
    let info: PriceInfo
    let records: [PriceRecord]
    let chartHigh: Double?
    let chartLow: Double?
    let isLoading: Bool
    let emptyMessage: String?
    let contentWidth: CGFloat?
    let contentHeight: CGFloat?
    let showsContainerBackground: Bool

    init(
        source: GoldPriceSource,
        info: PriceInfo,
        records: [PriceRecord],
        chartHigh: Double? = nil,
        chartLow: Double? = nil,
        isLoading: Bool = false,
        emptyMessage: String? = nil,
        contentWidth: CGFloat? = nil,
        contentHeight: CGFloat? = nil,
        showsContainerBackground: Bool = true
    ) {
        self.source = source
        self.info = info
        self.records = records
        self.chartHigh = chartHigh
        self.chartLow = chartLow
        self.isLoading = isLoading
        self.emptyMessage = emptyMessage
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
        self.showsContainerBackground = showsContainerBackground
    }

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

    private var baseContent: some View {
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
                placeholder("加载中...")
            } else if let emptyMessage {
                placeholder(emptyMessage)
            } else {
                placeholder("数据积累中...")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
    }

    var body: some View {
        Group {
            if showsContainerBackground {
                baseContent
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.appCardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            } else {
                baseContent
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .frame(height: 88)
    }
}
