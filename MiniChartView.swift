import SwiftUI

struct MiniChartView: View {
    let records: [PriceRecord]
    let isUp: Bool

    private let chartHeight: CGFloat = 80
    private let dotRadius: CGFloat = 3
    private let timeAxisHeight: CGFloat = 14

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        if records.count >= 2 {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = chartHeight
                    let prices = records.map { $0.price }
                    let minPrice = prices.min() ?? 0
                    let maxPrice = prices.max() ?? 1
                    let priceRange = max(maxPrice - minPrice, 0.01)
                    let padding: CGFloat = 14

                    let points: [CGPoint] = records.enumerated().map { i, record in
                        let x = width * CGFloat(i) / CGFloat(records.count - 1)
                        let y = padding + (height - 2 * padding) * (1 - CGFloat((record.price - minPrice) / priceRange))
                        return CGPoint(x: x, y: y)
                    }

                    let highIndex = prices.enumerated().max(by: { $0.element < $1.element })?.offset
                    let lowIndex = prices.enumerated().min(by: { $0.element < $1.element })?.offset

                    let lineColor = isUp ? Color.red : Color.goldGreen

                    ZStack {
                        Path { path in
                            guard let first = points.first else { return }
                            path.move(to: CGPoint(x: first.x, y: height))
                            path.addLine(to: first)
                            for pt in points.dropFirst() {
                                path.addLine(to: pt)
                            }
                            if let last = points.last {
                                path.addLine(to: CGPoint(x: last.x, y: height))
                            }
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [lineColor.opacity(0.3), lineColor.opacity(0.02)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        Path { path in
                            guard let first = points.first else { return }
                            path.move(to: first)
                            for pt in points.dropFirst() {
                                path.addLine(to: pt)
                            }
                        }
                        .stroke(lineColor, lineWidth: 1.5)

                        if let hi = highIndex, hi < points.count {
                            Circle()
                                .fill(Color.red)
                                .frame(width: dotRadius * 2, height: dotRadius * 2)
                                .position(points[hi])

                            Text(String(format: "%.2f", prices[hi]))
                                .font(.system(size: 8))
                                .foregroundColor(.red)
                                .position(
                                    x: clampLabelX(points[hi].x, width: width),
                                    y: max(points[hi].y - 10, 6)
                                )
                        }

                        if let lo = lowIndex, lo < points.count {
                            Circle()
                                .fill(Color.goldGreen)
                                .frame(width: dotRadius * 2, height: dotRadius * 2)
                                .position(points[lo])

                            Text(String(format: "%.2f", prices[lo]))
                                .font(.system(size: 8))
                                .foregroundColor(.goldGreen)
                                .position(
                                    x: clampLabelX(points[lo].x, width: width),
                                    y: min(points[lo].y + 10, height - 2)
                                )
                        }
                    }
                }
                .frame(height: chartHeight)

                // Time axis
                HStack {
                    Text(timeFormatter.string(from: records.first!.timestamp))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    Spacer()

                    if records.count >= 3 {
                        let midRecord = records[records.count / 2]
                        Text(timeFormatter.string(from: midRecord.timestamp))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(timeFormatter.string(from: records.last!.timestamp))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(height: timeAxisHeight)
            }
            .frame(height: chartHeight + timeAxisHeight)
        }
    }

    private func clampLabelX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let labelHalfWidth: CGFloat = 25
        return min(max(x, labelHalfWidth), width - labelHalfWidth)
    }
}
