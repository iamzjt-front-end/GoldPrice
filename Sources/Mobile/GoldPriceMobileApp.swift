#if os(iOS)
import SwiftUI
import UIKit

@main
struct GoldPriceMobileApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = GoldPriceMobileViewModel()

    var body: some Scene {
        WindowGroup {
            GoldPriceMobileRootView(viewModel: viewModel)
                .onAppear {
                    viewModel.start()
                }
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        viewModel.start()
                    case .background, .inactive:
                        viewModel.stop()
                    @unknown default:
                        break
                    }
                }
        }
    }
}

struct GoldPriceMobileRootView: View {
    @ObservedObject var viewModel: GoldPriceMobileViewModel
    @State private var selectedTab: MobileRootTab

    init(viewModel: GoldPriceMobileViewModel) {
        self.viewModel = viewModel
        _selectedTab = State(initialValue: MobileRootTab.previewSelection)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTabView(viewModel: viewModel)
                .tag(MobileRootTab.home)
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }

            MarketTabView(viewModel: viewModel)
                .tag(MobileRootTab.market)
                .tabItem {
                    Label("行情", systemImage: "chart.line.uptrend.xyaxis")
                }

            TradeTabView(viewModel: viewModel)
                .tag(MobileRootTab.trade)
                .tabItem {
                    Label("交易", systemImage: "arrow.left.arrow.right.circle.fill")
                }

            SettingsTabView(viewModel: viewModel)
                .tag(MobileRootTab.settings)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .tint(.orange)
    }
}

private enum MobileRootTab: String {
    case home
    case market
    case trade
    case settings

    static var previewSelection: MobileRootTab {
        let rawValue = ProcessInfo.processInfo.environment["GOLDPRICE_PREVIEW_TAB"] ?? ""
        return MobileRootTab(rawValue: rawValue) ?? .home
    }
}

private enum MobileFormatting {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let tradeDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func signedAmountText(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "")\(format(value)) 元"
    }

    static func signedNumberText(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "")\(format(value))"
    }

    static func format(_ value: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", value)
    }

    static func timeText(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func tradeDateTimeText(_ date: Date) -> String {
        tradeDateTimeFormatter.string(from: date)
    }
}

private struct HomeTabView: View {
    @ObservedObject var viewModel: GoldPriceMobileViewModel

    private let heroSources: [GoldPriceSource] = [.jdZsFinance, .londonGold]

    private var performance: PositionPerformance? {
        viewModel.positionPerformance
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    positionSummarySection

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(heroSources, id: \.self) { source in
                            HomeHeroPriceCard(
                                source: source,
                                info: viewModel.allSourcePrices[source] ?? PriceInfo(),
                                isLoading: viewModel.isLoading && viewModel.allSourcePrices[source] == nil,
                                lastUpdateTime: viewModel.lastUpdateTime
                            )
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appGroupedBackground.ignoresSafeArea())
            .navigationTitle("实时金价")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.refresh()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable {
                viewModel.refresh()
            }
        }
    }

    private var positionSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("持仓摘要")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("由交易记录计算")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            if let performance {
                HStack(alignment: .top, spacing: 14) {
                    homeSummaryMetric(
                        title: "平均成本（元/克）",
                        value: MobileFormatting.format(performance.avgCost),
                        tint: .orange,
                        isProminent: true
                    )

                    homeSummaryMetric(
                        title: "持仓（克）",
                        value: MobileFormatting.format(performance.currentGrams, digits: 4),
                        tint: .primary,
                        isProminent: false
                    )
                }

                HStack(alignment: .top, spacing: 14) {
                    homeSummaryMetric(
                        title: "持仓收益（元）",
                        value: MobileFormatting.signedNumberText(performance.unrealizedProfit),
                        tint: performance.unrealizedProfit >= 0 ? .red : .goldGreen,
                        isProminent: false
                    )

                    homeSummaryMetric(
                        title: "累计收益（元）",
                        value: MobileFormatting.signedNumberText(performance.cumulativeProfit),
                        tint: performance.cumulativeProfit >= 0 ? .red : .goldGreen,
                        isProminent: false
                    )
                }
            } else {
                Text("暂无持仓，交易记录会自动生成摘要。")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.appCardBackground)
        )
    }

    private func homeSummaryMetric(title: String, value: String, tint: Color, isProminent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: isProminent ? 24 : 17, weight: .bold, design: .rounded))
                .foregroundColor(value == "--" ? .primary : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct HomeHeroPriceCard: View {
    let source: GoldPriceSource
    let info: PriceInfo
    let isLoading: Bool
    let lastUpdateTime: Date

    private var dayHighValue: Double? {
        Double(info.dayHigh)
    }

    private var dayLowValue: Double? {
        Double(info.dayLow)
    }

    private var rangeProgress: Double? {
        guard
            let current = info.priceDouble,
            let high = dayHighValue,
            let low = dayLowValue,
            high > low
        else {
            return nil
        }

        return min(max((current - low) / (high - low), 0), 1)
    }

    private var accentColor: Color {
        info.isUp ? .red : .goldGreen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(source.rawValue)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)

                    Text("更新 \(MobileFormatting.timeText(lastUpdateTime))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(source.unit)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(info.formattedPrice)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.7)

                if !info.changeAmount.isEmpty || !info.changeRate.isEmpty {
                    HStack(spacing: 8) {
                        if !info.changeAmount.isEmpty {
                            changeBadge(info.changeAmount)
                        }
                        if !info.changeRate.isEmpty {
                            changeBadge(info.changeRate)
                        }
                    }
                } else {
                    Text(isLoading ? "正在同步价格..." : "等待价格同步")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            if let rangeProgress {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: rangeProgress)
                        .tint(accentColor)

                    HStack {
                        Text("低 \(info.dayLow)")
                            .foregroundColor(.goldGreen)
                        Spacer()
                        Text("高 \(info.dayHigh)")
                            .foregroundColor(.red)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
            } else {
                HStack {
                    metricPill(title: "高", value: info.dayHigh, tint: .red)
                    metricPill(title: "低", value: info.dayLow, tint: .goldGreen)
                }
            }

            HStack {
                metricPill(title: "昨收", value: info.yesterdayPrice, tint: .primary)
                Spacer()
                Text(source == .jdZsFinance ? "首页锚点" : "国际参照")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func changeBadge(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundColor(accentColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.10))
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        source == .londonGold ? Color.orange.opacity(0.16) : Color.red.opacity(0.08),
                        Color.appCardBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func metricPill(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundColor(tint.opacity(0.8))
            Text(value)
                .foregroundColor(tint)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .allowsTightening(true)
    }

}

private struct MarketTabView: View {
    @ObservedObject var viewModel: GoldPriceMobileViewModel

    private let columns = [GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    summaryHeader

                    ForEach(GoldPriceSource.allCases, id: \.self) { source in
                        PriceChartPanel(
                            source: source,
                            info: viewModel.allSourcePrices[source] ?? PriceInfo(),
                            records: viewModel.records(for: source),
                            isLoading: viewModel.isLoading && viewModel.allSourcePrices[source] == nil,
                            emptyMessage: "等待本机累计更多价格点..."
                        )
                    }
                }
                .padding(16)
            }
            .background(Color.appGroupedBackground.ignoresSafeArea())
            .navigationTitle("行情")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.refresh()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable {
                viewModel.refresh()
            }
        }
    }

    private var summaryHeader: some View {
        HStack {
            Spacer()

            Text("\(viewModel.settings.refreshInterval) 秒刷新 · 更新 \(timeText(viewModel.lastUpdateTime))")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeText(_ date: Date) -> String {
        MobileFormatting.timeText(date)
    }
}

private enum PositionTransactionFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case buy = "加仓"
    case sell = "减仓"

    var id: String { rawValue }

    func matches(_ transaction: PositionTransaction) -> Bool {
        switch self {
        case .all: return true
        case .buy: return transaction.type == .buy
        case .sell: return transaction.type == .sell
        }
    }
}

private enum PositionTransactionEditorState: Identifiable {
    case create(PositionTransactionType)
    case edit(PositionTransaction)

    var id: String {
        switch self {
        case let .create(type):
            return "create-\(type.rawValue)"
        case let .edit(transaction):
            return "edit-\(transaction.id)"
        }
    }
}

private struct TradeTabView: View {
    @ObservedObject var viewModel: GoldPriceMobileViewModel
    @State private var transactionEditor: PositionTransactionEditorState?
    @State private var selectedTransaction: PositionTransaction?
    @State private var recordFilter: PositionTransactionFilter = .all
    @State private var transactionPendingDeletion: PositionTransaction?

    private var isShowingDeleteAlert: Binding<Bool> {
        Binding(
            get: { transactionPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    transactionPendingDeletion = nil
                }
            }
        )
    }

    private var performance: PositionPerformance? {
        viewModel.positionPerformance
    }

    private var filteredTransactions: [PositionTransaction] {
        viewModel.positionTransactions.filter { recordFilter.matches($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let performance {
                        overviewCard(performance)
                        actionSection
                        profitBreakdownCard(performance)
                    } else {
                        emptySummaryCard
                        actionSection
                    }

                    transactionSection
                }
                .padding(16)
            }
            .background(Color.appGroupedBackground.ignoresSafeArea())
            .navigationTitle("交易")
            .sheet(item: $transactionEditor) { editor in
                PositionTransactionEditorView(
                    initialAction: editor.defaultAction,
                    existingTransaction: editor.transaction,
                    defaultSource: editor.transaction?.source ?? viewModel.positionSource,
                    defaultPrice: editor.transaction?.price ?? viewModel.positionCurrentPrice,
                    suggestedPrice: { source in
                        viewModel.currentPrice(for: source)
                    },
                    allTransactions: viewModel.positionTransactions
                ) { transaction in
                    switch editor {
                    case .create:
                        viewModel.addTransaction(transaction)
                    case .edit:
                        viewModel.updateTransaction(transaction)
                    }
                }
            }
            .navigationDestination(item: $selectedTransaction) { transaction in
                TradeTransactionDetailView(
                    transaction: transaction,
                    currentPrice: transaction.source.flatMap(viewModel.currentPrice(for:))
                )
            }
            .alert(
                "删除这笔交易记录？",
                isPresented: isShowingDeleteAlert,
                presenting: transactionPendingDeletion
            ) { transaction in
                Button("取消", role: .cancel) {
                    transactionPendingDeletion = nil
                }

                Button("删除", role: .destructive) {
                    viewModel.removeTransaction(id: transaction.id)
                    transactionPendingDeletion = nil
                }
            } message: { transaction in
                Text("\(transaction.type.rawValue) \(Self.format(transaction.grams, digits: 4)) 克 · \(Self.format(transaction.price)) 元/克")
            }
        }
    }

    private func overviewCard(_ performance: PositionPerformance) -> some View {
        let currentPrice = viewModel.positionCurrentPrice

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前持仓（克） · \(performance.source.rawValue)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text(Self.format(performance.currentGrams, digits: 4))
                        .font(.system(size: 30, weight: .bold))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text("当前金价（\(performance.source.unit)）")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(currentPrice.map { Self.format($0) } ?? "--")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("持仓成本（含现价手续费） \(Self.format(performance.currentCostBasis))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                supportingMetric(
                    title: "平均成本（元/克）",
                    value: Self.format(performance.avgCost),
                    tint: .orange
                )

                supportingMetric(
                    title: "保本价（含现价手续费）",
                    value: Self.format(performance.breakEvenPrice),
                    tint: .primary
                )
            }

            HStack(spacing: 12) {
                earningsTile(
                    title: "持仓收益（元）",
                    valueText: Self.signedNumberText(performance.unrealizedProfit),
                    subtitle: "按当前持仓和实时金价计算",
                    tint: performance.unrealizedProfit >= 0 ? .red : .goldGreen
                )

                earningsTile(
                    title: "累计收益（元）",
                    valueText: Self.signedNumberText(performance.cumulativeProfit),
                    subtitle: "按交易记录汇总统计",
                    tint: performance.cumulativeProfit >= 0 ? .red : .goldGreen
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.appCardBackground)
        )
    }

    private var emptySummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("交易总览")
                .font(.system(size: 22, weight: .bold))

            Text("还没有交易记录。先记一笔加仓，交易页会自动沉淀持仓、收益和完整流水。")
                .font(.system(size: 15))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                supportingMetric(
                    title: "平均成本（元/克）",
                    value: "--",
                    tint: .orange
                )

                supportingMetric(
                    title: "累计收益（元）",
                    value: "--",
                    tint: .primary
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.appCardBackground)
        )
    }

    private var actionSection: some View {
        HStack(spacing: 12) {
            Button {
                transactionPendingDeletion = nil
                transactionEditor = .create(.buy)
            } label: {
                Label("加仓", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button {
                transactionPendingDeletion = nil
                transactionEditor = .create(.sell)
            } label: {
                Label("减仓", systemImage: "minus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(.primary)
            .disabled((performance?.currentGrams ?? 0) <= 0)
        }
    }

    private func profitBreakdownCard(_ performance: PositionPerformance) -> some View {
        let breakdownItems: [(String, String, Color)] = [
            ("已实现收益（元）", Self.signedNumberText(performance.realizedProfit), performance.realizedProfit >= 0 ? .red : .goldGreen),
            ("持仓收益（元）", Self.signedNumberText(performance.unrealizedProfit), performance.unrealizedProfit >= 0 ? .red : .goldGreen),
            ("平均成本（元/克）", Self.format(performance.avgCost), .primary),
            ("累计手续费估算（元）", Self.format(performance.totalFees), .primary)
        ]

        return VStack(alignment: .leading, spacing: 14) {
            Text("收益拆解")
                .font(.system(size: 18, weight: .bold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(breakdownItems.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.0)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(item.1)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(item.2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
            }

            HStack {
                Text("累计买入（元） \(Self.format(performance.buyAmount))")
                Spacer()
                Text("累计卖出（元） \(Self.format(performance.sellAmount))")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.appCardBackground)
        )
    }

    private var transactionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("交易记录")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text("\(filteredTransactions.count) / \(viewModel.positionTransactions.count) 笔")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Picker("筛选", selection: $recordFilter) {
                ForEach(PositionTransactionFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            if filteredTransactions.isEmpty {
                Text("还没有对应的交易记录。")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
            } else {
                TradeTransactionListView(
                    transactions: filteredTransactions,
                    currentPriceProvider: { source in
                        source.flatMap(viewModel.currentPrice(for:))
                    },
                    onSelect: { transaction in
                        transactionPendingDeletion = nil
                        selectedTransaction = transaction
                    },
                    onEdit: { transaction in
                        transactionPendingDeletion = nil
                        transactionEditor = .edit(transaction)
                    },
                    onRequestDelete: { transaction in
                        selectedTransaction = nil
                        transactionEditor = nil
                        transactionPendingDeletion = transaction
                    }
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.appCardBackground)
        )
    }

    private func supportingMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func earningsTile(
        title: String,
        valueText: String,
        subtitle: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text(valueText)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(valueText == "--" ? .primary : tint)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private static func signedNumberText(_ value: Double) -> String {
        MobileFormatting.signedNumberText(value)
    }

    private static func format(_ value: Double, digits: Int = 2) -> String {
        MobileFormatting.format(value, digits: digits)
    }
}

private struct TradeTransactionListView: UIViewRepresentable {
    let transactions: [PositionTransaction]
    let currentPriceProvider: (GoldPriceSource?) -> Double?
    let onSelect: (PositionTransaction) -> Void
    let onEdit: (PositionTransaction) -> Void
    let onRequestDelete: (PositionTransaction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> SelfSizingTransactionTableView {
        let tableView = SelfSizingTransactionTableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.isScrollEnabled = false
        tableView.allowsSelection = true
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 124
        tableView.contentInset = .zero
        tableView.sectionHeaderHeight = 0
        tableView.sectionFooterHeight = 0
        tableView.tableHeaderView = UIView(frame: .zero)
        tableView.tableFooterView = UIView(frame: .zero)
        tableView.register(TradeTransactionTableViewCell.self, forCellReuseIdentifier: TradeTransactionTableViewCell.reuseIdentifier)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        return tableView
    }

    func updateUIView(_ uiView: SelfSizingTransactionTableView, context: Context) {
        context.coordinator.parent = self
        uiView.reloadData()
        uiView.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var parent: TradeTransactionListView

        init(parent: TradeTransactionListView) {
            self.parent = parent
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            parent.transactions.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            guard
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: TradeTransactionTableViewCell.reuseIdentifier,
                    for: indexPath
                ) as? TradeTransactionTableViewCell
            else {
                return UITableViewCell(style: .default, reuseIdentifier: nil)
            }

            let transaction = parent.transactions[indexPath.row]
            let currentPrice = parent.currentPriceProvider(transaction.source)
            cell.configure(transaction: transaction, currentPrice: currentPrice)
            return cell
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            let transaction = parent.transactions[indexPath.row]
            tableView.deselectRow(at: indexPath, animated: true)
            parent.onSelect(transaction)
        }

        func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            let transaction = parent.transactions[indexPath.row]

            let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
                self?.parent.onRequestDelete(transaction)
                completion(true)
            }
            deleteAction.backgroundColor = .systemRed

            let editAction = UIContextualAction(style: .normal, title: "编辑") { [weak self] _, _, completion in
                self?.parent.onEdit(transaction)
                completion(true)
            }
            editAction.backgroundColor = .systemOrange

            let configuration = UISwipeActionsConfiguration(actions: [deleteAction, editAction])
            configuration.performsFirstActionWithFullSwipe = false
            return configuration
        }
    }
}

private final class SelfSizingTransactionTableView: UITableView {
    override var contentSize: CGSize {
        didSet {
            if oldValue != contentSize {
                invalidateIntrinsicContentSize()
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentSize.height)
    }
}

private final class TradeTransactionTableViewCell: UITableViewCell {
    static let reuseIdentifier = "TradeTransactionTableViewCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(transaction: PositionTransaction, currentPrice: Double?) {
        contentConfiguration = UIHostingConfiguration {
            TradeTransactionRowCard(transaction: transaction, currentPrice: currentPrice)
        }
        .margins(.all, 0)
    }
}

private struct TradeTransactionRowCard: View {
    let transaction: PositionTransaction
    let currentPrice: Double?

    private var accent: Color {
        transaction.type == .buy ? .red : .goldGreen
    }

    private var feeEstimateText: String {
        MobileFormatting.format(transaction.feeAmount(referencePrice: currentPrice ?? transaction.price))
    }

    private var feeEstimateLabel: String {
        currentPrice == nil ? "按成交价估算手续费" : "按实时价估算手续费"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    Image(systemName: transaction.type.symbolName)
                        .foregroundColor(accent)
                    Text(transaction.type.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accent)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(MobileFormatting.tradeDateTimeText(transaction.date))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }

            HStack {
                TradeTransactionMetricView(title: "克数（克）", value: MobileFormatting.format(transaction.grams, digits: 4))
                Spacer()
                TradeTransactionMetricView(title: "成交价（元/克）", value: MobileFormatting.format(transaction.price))
                Spacer()
                TradeTransactionMetricView(title: "手续费", value: "\(MobileFormatting.format(transaction.feeRate, digits: 3))%")
            }

            Text("\(feeEstimateLabel) \(feeEstimateText) 元")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if !transaction.note.isEmpty {
                Text(transaction.note)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct TradeTransactionMetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
        }
    }
}

private struct SettingsTabView: View {
    @ObservedObject var viewModel: GoldPriceMobileViewModel
    private let dynamicIslandRefreshOptions = [5, 10, 15, 30, 60, 120, 300]

    private var appVersionText: String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildVersion) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty:
            return "\(short) (\(build))"
        case let (short?, _) where !short.isEmpty:
            return short
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return "--"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础设置") {
                    Stepper(
                        value: Binding(
                            get: { viewModel.settings.refreshInterval },
                            set: { viewModel.updateRefreshInterval($0) }
                        ),
                        in: 1...60
                    ) {
                        HStack {
                            Text("自动刷新")
                            Spacer()
                            Text("\(viewModel.settings.refreshInterval) 秒")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("灵动岛") {
                    Toggle(
                        "启用灵动岛",
                        isOn: Binding(
                            get: { viewModel.settings.dynamicIslandEnabled },
                            set: { viewModel.updateDynamicIslandEnabled($0) }
                        )
                    )

                    LabeledContent("轮播内容") {
                        Text(viewModel.settings.dynamicIslandItems.map(\.title).joined(separator: "、"))
                            .foregroundColor(.secondary)
                    }

                    ForEach(DynamicIslandDisplayItem.allCases) { item in
                        Toggle(
                            item.title,
                            isOn: Binding(
                                get: { viewModel.settings.dynamicIslandItems.contains(item) },
                                set: { viewModel.updateDynamicIslandDisplayItem(item, isEnabled: $0) }
                            )
                        )
                        .disabled(
                            !viewModel.settings.dynamicIslandEnabled ||
                            (viewModel.settings.dynamicIslandItems.count == 1 && viewModel.settings.dynamicIslandItems.contains(item))
                        )
                    }

                    Picker(
                        "刷新频率",
                        selection: Binding(
                            get: { viewModel.settings.dynamicIslandRefreshInterval },
                            set: { viewModel.updateDynamicIslandRefreshInterval($0) }
                        )
                    ) {
                        ForEach(dynamicIslandRefreshOptions, id: \.self) { interval in
                            Text(refreshLabel(for: interval)).tag(interval)
                        }
                    }
                    .disabled(!viewModel.settings.dynamicIslandEnabled)
                }

                Section {
                    LabeledContent("当前版本", value: appVersionText)
                }
            }
            .navigationTitle("设置")
        }
    }

    private func refreshLabel(for seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) 秒"
        }
        return "\(seconds / 60) 分钟"
    }
}

private struct TradeTransactionDetailView: View {
    let transaction: PositionTransaction
    let currentPrice: Double?

    private var sourceLabel: String {
        transaction.source?.rawValue ?? "未指定"
    }

    private var amountLabel: String {
        MobileFormatting.format(transaction.grossAmount)
    }

    private var priceLabel: String {
        MobileFormatting.format(transaction.price)
    }

    private var feeEstimateTitle: String {
        currentPrice == nil ? "手续费估算（按成交价）" : "手续费估算（按实时价）"
    }

    var body: some View {
        Form {
            Section("概览") {
                LabeledContent("操作类型", value: transaction.type.rawValue)
                LabeledContent("数据源", value: sourceLabel)
                LabeledContent(
                    "交易时间",
                    value: MobileFormatting.tradeDateTimeText(transaction.date)
                )
            }

            Section("价格与数量") {
                LabeledContent("克数（克）", value: MobileFormatting.format(transaction.grams, digits: 4))
                LabeledContent("成交价（元/克）", value: priceLabel)
                LabeledContent("交易金额（元）", value: amountLabel)
                LabeledContent("手续费费率（%）", value: MobileFormatting.format(transaction.feeRate, digits: 3))
                LabeledContent(
                    feeEstimateTitle,
                    value: MobileFormatting.format(transaction.feeAmount(referencePrice: currentPrice ?? transaction.price))
                )
            }

            Section("备注") {
                if transaction.note.isEmpty {
                    Text("这笔交易没有备注。")
                        .foregroundColor(.secondary)
                } else {
                    Text(transaction.note)
                }
            }
        }
        .navigationTitle("交易详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PositionTransactionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let existingTransaction: PositionTransaction?
    let defaultPrice: Double?
    let suggestedPrice: (GoldPriceSource) -> Double?
    let allTransactions: [PositionTransaction]
    let onSave: (PositionTransaction) -> Void

    @State private var action: PositionTransactionType
    @State private var selectedSource: GoldPriceSource
    @State private var grams: String
    @State private var price: String
    @State private var fee: String
    @State private var date = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    init(
        initialAction: PositionTransactionType,
        existingTransaction: PositionTransaction? = nil,
        defaultSource: GoldPriceSource,
        defaultPrice: Double?,
        suggestedPrice: @escaping (GoldPriceSource) -> Double?,
        allTransactions: [PositionTransaction],
        onSave: @escaping (PositionTransaction) -> Void
    ) {
        self.existingTransaction = existingTransaction
        self.defaultPrice = defaultPrice
        self.suggestedPrice = suggestedPrice
        self.allTransactions = allTransactions
        self.onSave = onSave

        let seedTransaction = existingTransaction
        let seedSource = seedTransaction?.source ?? defaultSource
        let seedPrice = seedTransaction?.price ?? suggestedPrice(seedSource) ?? defaultPrice

        _action = State(initialValue: seedTransaction?.type ?? initialAction)
        _selectedSource = State(initialValue: seedSource)
        _grams = State(initialValue: seedTransaction.map { Self.stringValue($0.grams, digits: 4) } ?? "")
        _price = State(initialValue: seedPrice.map { Self.stringValue($0) } ?? "")
        _fee = State(initialValue: seedTransaction.map { Self.stringValue($0.feeRate, digits: 3) } ?? "0")
        _date = State(initialValue: seedTransaction?.date ?? Date())
        _note = State(initialValue: seedTransaction?.note ?? "")
    }

    private var navigationTitle: String {
        existingTransaction == nil ? "新增交易" : "编辑交易"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("交易信息") {
                    Picker("操作", selection: $action) {
                        ForEach(PositionTransactionType.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }

                    Picker("数据源", selection: $selectedSource) {
                        ForEach(GoldPriceSource.allCases, id: \.self) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }

                    DatePicker("交易时间", selection: $date, displayedComponents: [.date, .hourAndMinute])

                    TextField("克数", text: $grams)
                        .keyboardType(.decimalPad)
                    TextField("成交价（元/克）", text: $price)
                        .keyboardType(.decimalPad)
                    TextField("手续费（%）", text: $fee)
                        .keyboardType(.decimalPad)

                    if action == .sell {
                        Text("保存时会校验该时点可用持仓，不能超过实际可减数量。")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Text("手续费会按当前实时金价换算成金额。")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Section("备注") {
                    TextField("可选备注", text: $note, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }

            }
            .onChange(of: selectedSource) { source in
                if let latestPrice = suggestedPrice(source) {
                    price = Self.stringValue(latestPrice)
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        guard
            let parsedGrams = Double(grams.trimmingCharacters(in: .whitespacesAndNewlines)),
            parsedGrams > 0
        else {
            errorMessage = "请输入有效的交易克数。"
            return
        }

        guard
            let parsedPrice = Double(price.trimmingCharacters(in: .whitespacesAndNewlines)),
            parsedPrice > 0
        else {
            errorMessage = "请输入有效的成交价。"
            return
        }

        guard let parsedFee = Double(fee.trimmingCharacters(in: .whitespacesAndNewlines)), parsedFee >= 0 else {
            errorMessage = "手续费要填百分比数字，可以为 0。"
            return
        }

        let transaction = PositionTransaction(
            id: existingTransaction?.id ?? UUID().uuidString,
            date: date,
            sourceRawValue: selectedSource.rawValue,
            type: action,
            grams: parsedGrams,
            price: parsedPrice,
            fee: parsedFee,
            note: note
        )

        let updatedTransactions = allTransactions.filter { $0.id != transaction.id } + [transaction]
        if let invalidSell = PositionLedger.firstInsufficientSell(in: updatedTransactions) {
            if invalidSell.transaction.id == transaction.id {
                errorMessage = "这笔减仓超过该时点可用持仓，最多可减 \(Self.stringValue(invalidSell.availableGrams, digits: 4)) 克。"
            } else {
                errorMessage = "这次保存会让 \(MobileFormatting.tradeDateTimeText(invalidSell.transaction.date)) 的减仓记录超出持仓，请调整后再试。"
            }
            return
        }

        onSave(transaction)
        dismiss()
    }

    private static func stringValue(_ value: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", value)
            .replacingOccurrences(of: #"(\.\d*?[1-9])0+$"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\.0+$"#, with: "", options: .regularExpression)
    }
}

private extension PositionTransactionEditorState {
    var defaultAction: PositionTransactionType {
        switch self {
        case let .create(action):
            return action
        case let .edit(transaction):
            return transaction.type
        }
    }

    var transaction: PositionTransaction? {
        switch self {
        case .create:
            return nil
        case let .edit(transaction):
            return transaction
        }
    }
}
#endif
