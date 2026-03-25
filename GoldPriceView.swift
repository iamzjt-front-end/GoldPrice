import SwiftUI

struct GoldPriceView: View {
    @ObservedObject var dataService: GoldPriceService
    @State private var hoveredSource: GoldPriceSource?
    private let historyManager = PriceHistoryManager.shared

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Text("黄金价格监控")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    sectionHeader("国内金价")

                    ForEach(GoldPriceSource.domesticSources, id: \.self) { source in
                        priceRow(source: source)
                    }

                    Divider().padding(.vertical, 4)

                    sectionHeader("国际金价")

                    ForEach(GoldPriceSource.internationalSources, id: \.self) { source in
                        priceRow(source: source)
                    }

                    Divider().padding(.vertical, 4)

                    // Source picker
                    HStack(spacing: 6) {
                        Text("状态栏显示:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Picker("", selection: $dataService.currentSource) {
                            ForEach(GoldPriceSource.allCases, id: \.self) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .scaleEffect(0.85, anchor: .leading)
                        .frame(height: 20)

                        Spacer()

                        Button(action: { dataService.fetchAllPrices() }) {
                            HStack(spacing: 4) {
                                if dataService.isLoading {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11))
                                }
                                Text("刷新")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                    HStack {
                        Text("更新于 \(dateFormatter.string(from: dataService.lastUpdateTime))")
                            .font(.system(size: 10))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(width: 300, height: 520)
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func priceRow(source: GoldPriceSource) -> some View {
        let info = dataService.allSourcePrices[source]
        let hasData = info != nil && info?.price != "--"
        let isHovered = hoveredSource == source

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text(source.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 60, alignment: .leading)

                Spacer()

                if let info = info, hasData {
                    Text(info.formattedPrice)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)

                    Text(source.unit)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.leading, 2)

                    Spacer().frame(width: 8)

                    if !info.changeRate.isEmpty {
                        HStack(spacing: 2) {
                            Text(info.changeIcon)
                                .font(.system(size: 10))
                            Text(info.changeRate)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(info.isUp ? .red : .goldGreen)
                        }
                    }
                } else {
                    Text("--")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .cornerRadius(4)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    hoveredSource = hovering ? source : nil
                }
            }

            if isHovered, let info = info, hasData {
                chartPanel(source: source, info: info)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func chartPanel(source: GoldPriceSource, info: PriceInfo) -> some View {
        let records = historyManager.getTodayRecords(for: source.rawValue)

        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(info.formattedPrice)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)

                Text(source.unit)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                if !info.changeRate.isEmpty {
                    HStack(spacing: 3) {
                        Text(info.isUp ? "↑" : "↓")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(info.isUp ? .red : .goldGreen)
                        Text(info.changeRate)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(info.isUp ? .red : .goldGreen)
                    }
                }
            }

            if info.dayHigh != "--" && info.dayLow != "--" {
                HStack(spacing: 12) {
                    HStack(spacing: 2) {
                        Text("高")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.7))
                        Text(info.dayHigh)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 2) {
                        Text("低")
                            .font(.system(size: 10))
                            .foregroundColor(.goldGreen.opacity(0.7))
                        Text(info.dayLow)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
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
                    .frame(height: 40)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct GoldPriceView_Previews: PreviewProvider {
    static var previews: some View {
        GoldPriceView(dataService: GoldPriceService())
    }
}
