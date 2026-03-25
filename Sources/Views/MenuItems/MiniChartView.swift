import SwiftUI
import Charts

private extension Color {
    static let chartTipHigh = Color(red: 232 / 255, green: 84 / 255, blue: 79 / 255)
    static let chartTipLow = Color(red: 99 / 255, green: 171 / 255, blue: 142 / 255)
}

private struct TrendRecord: Identifiable {
    let timestamp: Date
    let value: Double

    var id: TimeInterval { timestamp.timeIntervalSince1970 }
}

private func emaSmooth(_ values: [Double], alpha: Double) -> [Double] {
    guard let first = values.first else { return [] }

    var result: [Double] = [first]
    for value in values.dropFirst() {
        let next = alpha * value + (1 - alpha) * result[result.count - 1]
        result.append(next)
    }
    return result
}

private func buildTrendRecords(from records: [PriceRecord]) -> [TrendRecord] {
    guard records.count >= 3 else {
        return records.map { TrendRecord(timestamp: $0.timestamp, value: $0.price) }
    }

    let smoothed = emaSmooth(emaSmooth(records.map(\.price), alpha: 0.22), alpha: 0.18)
    let targetCount = min(28, max(14, records.count / 8))
    let bucketSize = max(1, Int(ceil(Double(records.count) / Double(targetCount))))

    var trendRecords: [TrendRecord] = []
    var index = 0

    while index < records.count {
        let end = min(index + bucketSize, records.count)
        let smoothedBucket = Array(smoothed[index..<end])
        let bucketCenter = index + ((end - index) / 2)
        let averageValue = smoothedBucket.reduce(0, +) / Double(smoothedBucket.count)
        trendRecords.append(TrendRecord(timestamp: records[bucketCenter].timestamp, value: averageValue))
        index = end
    }

    if let first = records.first {
        trendRecords[0] = TrendRecord(timestamp: first.timestamp, value: first.price)
    }
    if let last = records.last {
        trendRecords[trendRecords.count - 1] = TrendRecord(timestamp: last.timestamp, value: last.price)
    }

    if let maxRecord = records.max(by: { $0.price < $1.price }) {
        trendRecords.append(TrendRecord(timestamp: maxRecord.timestamp, value: maxRecord.price))
    }
    if let minRecord = records.min(by: { $0.price < $1.price }) {
        trendRecords.append(TrendRecord(timestamp: minRecord.timestamp, value: minRecord.price))
    }

    let deduplicated = Dictionary(
        trendRecords.map { ($0.timestamp.timeIntervalSince1970, $0) },
        uniquingKeysWith: { _, new in new }
    )

    return deduplicated.values.sorted { $0.timestamp < $1.timestamp }
}

struct MiniChartView: View {
    let records: [PriceRecord]
    let isUp: Bool

    private var trendRecords: [TrendRecord] {
        buildTrendRecords(from: records)
    }

    private var prices: [Double] {
        records.map(\.price)
    }

    private var minRecord: PriceRecord? {
        records.min(by: { $0.price < $1.price })
    }

    private var maxRecord: PriceRecord? {
        records.max(by: { $0.price < $1.price })
    }

    private var yDomain: ClosedRange<Double> {
        let minValue = prices.min() ?? 0
        let maxValue = prices.max() ?? 1
        let padding = max((maxValue - minValue) * 0.12, 0.5)
        return (minValue - padding)...(maxValue + padding)
    }

    private var xMarks: [Date] {
        guard let first = records.first?.timestamp, let last = records.last?.timestamp else { return [] }
        let middle = records[records.count / 2].timestamp
        return [first, middle, last]
    }

    private var lineColor: Color {
        isUp ? .red : .goldGreen
    }

    var body: some View {
        Chart {
            ForEach(trendRecords) { record in
                AreaMark(
                    x: .value("Time", record.timestamp),
                    yStart: .value("Baseline", yDomain.lowerBound),
                    yEnd: .value("Value", record.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [lineColor.opacity(0.18), lineColor.opacity(0.015)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            ForEach(trendRecords) { record in
                LineMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Value", record.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(lineColor.opacity(0.95))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            if let maxRecord {
                PointMark(
                    x: .value("High Time", maxRecord.timestamp),
                    y: .value("High Value", maxRecord.price)
                )
                .symbolSize(42)
                .foregroundStyle(Color.chartTipHigh)
                .annotation(position: .top, spacing: 8) {
                    tipLabel(text: String(format: "%.2f", maxRecord.price), color: .chartTipHigh)
                }
            }

            if let minRecord {
                PointMark(
                    x: .value("Low Time", minRecord.timestamp),
                    y: .value("Low Value", minRecord.price)
                )
                .symbolSize(42)
                .foregroundStyle(Color.chartTipLow)
                .annotation(position: .bottom, spacing: 8) {
                    tipLabel(text: String(format: "%.2f", minRecord.price), color: .chartTipLow)
                }
            }
        }
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8))
                    .foregroundStyle(Color.primary.opacity(0.05))
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel().foregroundStyle(.clear)
            }
        }
        .chartXAxis {
            AxisMarks(values: xMarks) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartPlotStyle { plotContent in
            plotContent
                .padding(.top, 14)
                .padding(.bottom, 4)
                .background(Color.clear)
        }
        .frame(height: 128)
    }

    private func tipLabel(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
