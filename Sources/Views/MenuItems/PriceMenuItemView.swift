import AppKit

class PriceMenuItemView: NSView {
    private var trackingArea: NSTrackingArea?
    private let onHover: (Bool) -> Void
    private let sourceLabel = NSTextField(labelWithString: "")
    private let priceLabel = NSTextField(labelWithString: "")
    private let changeIconLabel = NSTextField(labelWithString: "")
    private let changeRateLabel = NSTextField(labelWithString: "")

    init(source: GoldPriceSource, info: PriceInfo, onHover: @escaping (Bool) -> Void = { _ in }) {
        self.onHover = onHover
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 34))

        setupView()
        update(source: source, info: info)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(source: GoldPriceSource, info: PriceInfo) {
        sourceLabel.stringValue = source.rawValue
        priceLabel.stringValue = info.price == "--" ? "--" : "\(info.formattedPrice) \(source.unit)"
        changeIconLabel.stringValue = info.changeRate.isEmpty ? "" : info.changeIcon
        changeRateLabel.stringValue = info.changeRate
        changeRateLabel.textColor = info.isUp ? .systemRed : .goldGreen
        needsDisplay = true
    }

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

    private func setupView() {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        sourceLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        sourceLabel.textColor = .labelColor

        priceLabel.font = .systemFont(ofSize: 13, weight: .medium)
        priceLabel.textColor = .labelColor

        changeIconLabel.font = .systemFont(ofSize: 11)
        changeRateLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let changeStack = NSStackView(views: [changeIconLabel, changeRateLabel])
        changeStack.orientation = .horizontal
        changeStack.alignment = .centerY
        changeStack.spacing = 2

        container.addArrangedSubview(sourceLabel)
        container.addArrangedSubview(priceLabel)
        container.addArrangedSubview(spacer)
        container.addArrangedSubview(changeStack)
        addSubview(container)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 280),
            heightAnchor.constraint(equalToConstant: 34),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }
}
