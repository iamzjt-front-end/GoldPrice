import AppKit
import SwiftUI

class PriceMenuItemView: NSView {
    private var trackingArea: NSTrackingArea?
    private let onHover: (Bool) -> Void

    init(source: GoldPriceSource, info: PriceInfo, onHover: @escaping (Bool) -> Void = { _ in }) {
        self.onHover = onHover
        super.init(frame: .zero)

        let hostingView = NSHostingView(rootView: PriceRowContent(source: source, info: info))
        let fittingSize = hostingView.fittingSize
        self.frame = NSRect(x: 0, y: 0, width: max(fittingSize.width, 280), height: fittingSize.height)
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
}

private struct PriceRowContent: View {
    let source: GoldPriceSource
    let info: PriceInfo

    var body: some View {
        HStack(spacing: 0) {
            Text(source.rawValue)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer().frame(width: 8)

            Text("\(info.formattedPrice) \(source.unit)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            if !info.changeRate.isEmpty {
                HStack(spacing: 2) {
                    Text(info.changeIcon)
                        .font(.system(size: 11))
                    Text(info.changeRate)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(info.isUp ? .red : .goldGreen)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
