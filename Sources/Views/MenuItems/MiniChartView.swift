import SwiftUI
import Charts

private extension Color {
    static let chartTipHigh = Color(red: 232 / 255, green: 84 / 255, blue: 79 / 255)
    static let chartTipLow = Color(red: 75 / 255, green: 166 / 255, blue: 110 / 255)
}

private struct TrendRecord: Identifiable, Equatable {
    let timestamp: Date
    let value: Double

    var id: TimeInterval { timestamp.timeIntervalSince1970 }
}

private struct HoverSelection: Equatable {
    let timestamp: Date
    let value: Double
}

private func buildTrendRecords(from records: [PriceRecord]) -> [TrendRecord] {
    guard !records.isEmpty else { return [] }
    guard records.count >= 2 else {
        return records.map { TrendRecord(timestamp: $0.timestamp, value: $0.price) }
    }

    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: records[0].timestamp)
    let bucketInterval: TimeInterval = 120

    var bucketedRecords: [Int: PriceRecord] = [:]
    for record in records {
        let offset = max(0, record.timestamp.timeIntervalSince(startOfDay))
        let bucketIndex = Int(offset / bucketInterval)
        bucketedRecords[bucketIndex] = record
    }

    let rawMinRecord = records.min(by: { $0.price < $1.price })
    let rawMaxRecord = records.max(by: { $0.price < $1.price })

    var mergedRecords = bucketedRecords
        .keys
        .sorted()
        .compactMap { bucketedRecords[$0] }

    if let rawMinRecord,
       !mergedRecords.contains(where: { $0.timestamp == rawMinRecord.timestamp && $0.price == rawMinRecord.price }) {
        mergedRecords.append(rawMinRecord)
    }

    if let rawMaxRecord,
       !mergedRecords.contains(where: { $0.timestamp == rawMaxRecord.timestamp && $0.price == rawMaxRecord.price }) {
        mergedRecords.append(rawMaxRecord)
    }

    return mergedRecords
        .sorted { $0.timestamp < $1.timestamp }
        .map { TrendRecord(timestamp: $0.timestamp, value: $0.price) }
}

private struct ChartStaticShape: View, Equatable {
    let trendRecords: [TrendRecord]
    let minRecord: TrendRecord?
    let maxRecord: TrendRecord?
    let lastTrendRecord: TrendRecord?
    let yDomain: ClosedRange<Double>
    let lineColor: Color
    let currentHintText: String

    static func == (lhs: ChartStaticShape, rhs: ChartStaticShape) -> Bool {
        lhs.trendRecords == rhs.trendRecords &&
        lhs.minRecord == rhs.minRecord &&
        lhs.maxRecord == rhs.maxRecord &&
        lhs.lastTrendRecord == rhs.lastTrendRecord &&
        lhs.yDomain.lowerBound == rhs.yDomain.lowerBound &&
        lhs.yDomain.upperBound == rhs.yDomain.upperBound &&
        lhs.currentHintText == rhs.currentHintText
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
                .interpolationMethod(.linear)
            }

            ForEach(trendRecords) { record in
                LineMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Value", record.value)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineColor.opacity(0.95))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            if let maxRecord {
                PointMark(
                    x: .value("High Time", maxRecord.timestamp),
                    y: .value("High Value", maxRecord.value)
                )
                .symbolSize(12)
                .foregroundStyle(Color.chartTipHigh)
                .annotation(position: .top, spacing: 8) {
                    tipLabel(text: String(format: "%.2f", maxRecord.value), color: .chartTipHigh)
                }
            }

            if let minRecord {
                PointMark(
                    x: .value("Low Time", minRecord.timestamp),
                    y: .value("Low Value", minRecord.value)
                )
                .symbolSize(12)
                .foregroundStyle(Color.chartTipLow)
            }

            if let lastTrendRecord {
                PointMark(
                    x: .value("Current Time", lastTrendRecord.timestamp),
                    y: .value("Current Value", lastTrendRecord.value)
                )
                .symbolSize(1)
                .foregroundStyle(Color.clear)
                .annotation(position: .trailing, spacing: 6) {
                    weakHintLabel(text: currentHintText, color: lineColor)
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
        .chartXAxis(.hidden)
        .chartYScale(domain: yDomain)
        .chartPlotStyle { plotContent in
            plotContent
                .padding(.top, 22)
                .background(Color.clear)
        }
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

    private func weakHintLabel(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundColor(color.opacity(0.78))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct MiniChartView: View {
    let records: [PriceRecord]
    let isUp: Bool
    let hoverValueFormatter: (Double) -> String
    let currentHintText: String

    private let trendRecords: [TrendRecord]
    private let minRecord: TrendRecord?
    private let maxRecord: TrendRecord?
    private let lastTrendRecord: TrendRecord?
    private let yDomain: ClosedRange<Double>
    private let xMarks: [Date]
    private let lineColor: Color

    @State private var hoverSelection: HoverSelection?
    @State private var axisLabelPositions: [TimeInterval: CGFloat] = [:]

    init(
        records: [PriceRecord],
        isUp: Bool,
        hoverValueFormatter: @escaping (Double) -> String,
        currentHintText: String
    ) {
        self.records = records
        self.isUp = isUp
        self.hoverValueFormatter = hoverValueFormatter
        self.currentHintText = currentHintText

        let trendRecords = buildTrendRecords(from: records)
        self.trendRecords = trendRecords

        let minRecord = trendRecords.min(by: { $0.value < $1.value })
        let maxRecord = trendRecords.max(by: { $0.value < $1.value })
        self.minRecord = minRecord
        self.maxRecord = maxRecord
        self.lastTrendRecord = trendRecords.last

        let prices = trendRecords.map(\.value)
        let minValue = prices.min() ?? 0
        let maxValue = prices.max() ?? 1
        let range = max(maxValue - minValue, 1)
        let lowerPadding = max(range * 0.50, 4.0)
        let upperPadding = max(range * 0.12, 0.8)
        self.yDomain = (minValue - lowerPadding)...(maxValue + upperPadding)

        if let first = trendRecords.first?.timestamp, let last = trendRecords.last?.timestamp {
            let middle = trendRecords[trendRecords.count / 2].timestamp
            self.xMarks = [first, middle, last]
        } else {
            self.xMarks = []
        }

        self.lineColor = isUp ? .red : .goldGreen
    }

    var body: some View {
        VStack(spacing: 0) {
            ChartStaticShape(
                trendRecords: trendRecords,
                minRecord: minRecord,
                maxRecord: maxRecord,
                lastTrendRecord: lastTrendRecord,
                yDomain: yDomain,
                lineColor: lineColor,
                currentHintText: currentHintText
            )
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plotFrame = geometry[proxy.plotAreaFrame]

                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onAppear {
                                updateAxisLabelPositions(using: proxy, plotFrame: plotFrame)
                            }
                            .onChange(of: geometry.size) { _ in
                                updateAxisLabelPositions(using: proxy, plotFrame: plotFrame)
                            }
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard plotFrame.contains(location) else {
                                        hoverSelection = nil
                                        return
                                    }

                                    let relativeX = location.x - plotFrame.origin.x
                                    guard let hoveredDate = proxy.value(atX: relativeX, as: Date.self),
                                          let nextSelection = interpolatedSelection(for: hoveredDate) else {
                                        hoverSelection = nil
                                        return
                                    }

                                    if shouldUpdateHoverSelection(to: nextSelection) {
                                        hoverSelection = nextSelection
                                    }
                                case .ended:
                                    hoverSelection = nil
                                }
                            }

                        Group {
                            if let hoverSelection,
                               let x = proxy.position(forX: hoverSelection.timestamp),
                               let y = proxy.position(forY: hoverSelection.value) {
                                let chartX = plotFrame.origin.x + x
                                let chartY = plotFrame.origin.y + y
                                let tooltipY = chartY < plotFrame.midY ? chartY + 28 : chartY - 28
                                let clampedTooltipX = min(max(chartX, plotFrame.minX + 52), plotFrame.maxX - 52)

                                Path { path in
                                    path.move(to: CGPoint(x: chartX, y: plotFrame.minY))
                                    path.addLine(to: CGPoint(x: chartX, y: plotFrame.maxY))
                                }
                                .stroke(Color.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .allowsHitTesting(false)

                                Circle()
                                    .fill(lineColor)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.9), lineWidth: 2)
                                    )
                                    .position(x: chartX, y: chartY)
                                    .allowsHitTesting(false)

                                hoverLabel(timestamp: hoverSelection.timestamp, valueText: hoverValueFormatter(hoverSelection.value))
                                    .position(x: clampedTooltipX, y: tooltipY)
                                    .allowsHitTesting(false)
                            }
                        }
                        .zIndex(2)

                        Group {
                            if let minRecord,
                               let x = proxy.position(forX: minRecord.timestamp),
                               let y = proxy.position(forY: minRecord.value) {
                                let chartX = plotFrame.origin.x + x
                                let chartY = plotFrame.origin.y + y
                                let labelX = min(max(chartX, plotFrame.minX + 44), plotFrame.maxX - 44)
                                let labelY = chartY + 18

                                tipLabel(text: String(format: "%.2f", minRecord.value), color: .chartTipLow)
                                    .position(x: labelX, y: labelY)
                                    .allowsHitTesting(false)
                            }
                        }
                        .zIndex(1)
                    }
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
            }
            .frame(height: 94)

            if xMarks.count == 3 {
                axisLabelsRow
                    .frame(height: 22)
                    .padding(.top, 7)
            }
        }
    }

    private var axisLabelsRow: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(Array(xMarks.enumerated()), id: \.offset) { _, mark in
                    let fallbackX = geometry.size.width / CGFloat(max(xMarks.count - 1, 1)) * CGFloat(xMarks.firstIndex(of: mark) ?? 0)
                    let x = axisLabelPositions[mark.timeIntervalSince1970] ?? fallbackX
                    let clampedX = min(max(x, 22), geometry.size.width - 22)

                    axisLabel(mark)
                        .frame(width: 44)
                        .position(x: clampedX, y: 11)
                }
            }
        }
    }

    private func shouldUpdateHoverSelection(to nextSelection: HoverSelection) -> Bool {
        guard let current = hoverSelection else { return true }
        let timeDelta = abs(current.timestamp.timeIntervalSince(nextSelection.timestamp))
        let valueDelta = abs(current.value - nextSelection.value)
        let valueThreshold = max((yDomain.upperBound - yDomain.lowerBound) / 220, 0.02)
        return timeDelta > 2 || valueDelta > valueThreshold
    }

    private func interpolatedSelection(for date: Date) -> HoverSelection? {
        guard let first = trendRecords.first, let last = trendRecords.last else { return nil }

        if date <= first.timestamp {
            return HoverSelection(timestamp: first.timestamp, value: first.value)
        }
        if date >= last.timestamp {
            return HoverSelection(timestamp: last.timestamp, value: last.value)
        }

        var lowerBound = 0
        var upperBound = trendRecords.count - 1

        while lowerBound + 1 < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if trendRecords[middle].timestamp <= date {
                lowerBound = middle
            } else {
                upperBound = middle
            }
        }

        let lowerRecord = trendRecords[lowerBound]
        let upperRecord = trendRecords[upperBound]
        let lowerDelta = abs(lowerRecord.timestamp.timeIntervalSince(date))
        let upperDelta = abs(upperRecord.timestamp.timeIntervalSince(date))
        let selectedRecord = lowerDelta <= upperDelta ? lowerRecord : upperRecord

        return HoverSelection(timestamp: selectedRecord.timestamp, value: selectedRecord.value)
    }

    private func hoverLabel(timestamp: Date, valueText: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timestamp, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Text(valueText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func tipLabel(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .fixedSize()
    }

    private func axisLabel(_ date: Date) -> some View {
        Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            .font(.system(size: 9))
            .foregroundColor(.secondary)
    }

    private func updateAxisLabelPositions(using proxy: ChartProxy, plotFrame: CGRect) {
        var nextPositions: [TimeInterval: CGFloat] = [:]
        for mark in xMarks {
            if let x = proxy.position(forX: mark) {
                nextPositions[mark.timeIntervalSince1970] = plotFrame.origin.x + x
            }
        }
        if !nextPositions.isEmpty {
            axisLabelPositions = nextPositions
        }
    }
}
