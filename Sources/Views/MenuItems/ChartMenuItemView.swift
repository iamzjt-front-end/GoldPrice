import AppKit
import SwiftUI

private enum ChartPanelLayout {
    static let panelWidth: CGFloat = 320
    static let panelHeight: CGFloat = 268
}

class ChartMenuItemView: NSView {
    private let hostingView: NSHostingView<PriceChartPanel>

    init(
        source: GoldPriceSource,
        info: PriceInfo,
        records: [PriceRecord],
        chartHigh: Double? = nil,
        chartLow: Double? = nil,
        isLoading: Bool = false,
        emptyMessage: String? = nil
    ) {
        self.hostingView = NSHostingView(rootView: PriceChartPanel(
            source: source,
            info: info,
            records: records,
            chartHigh: chartHigh,
            chartLow: chartLow,
            isLoading: isLoading,
            emptyMessage: emptyMessage,
            contentWidth: ChartPanelLayout.panelWidth,
            contentHeight: ChartPanelLayout.panelHeight,
            showsContainerBackground: false
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
        hostingView.rootView = PriceChartPanel(
            source: source,
            info: info,
            records: records,
            chartHigh: chartHigh,
            chartLow: chartLow,
            isLoading: isLoading,
            emptyMessage: emptyMessage,
            contentWidth: ChartPanelLayout.panelWidth,
            contentHeight: ChartPanelLayout.panelHeight,
            showsContainerBackground: false
        )
        let fittingSize = hostingView.fittingSize
        frame.size = NSSize(width: fittingSize.width, height: fittingSize.height)
        hostingView.frame = bounds
        needsDisplay = true
    }
}
