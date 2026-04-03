import AppKit
import WebKit

private enum GoldCircleEmbeddedLayout {
    static let panelWidth: CGFloat = 430
    static let panelHeight: CGFloat = 560
    static let headerHeight: CGFloat = 46
    static let pageURL = URL(string: "https://content.jr.jd.com/jrq/#/group?id=13245&channel=jyq&channelfrom=grouppc")!
}

final class GoldCircleDetailPanelView: NSView, WKNavigationDelegate {
    private let titleLabel = NSTextField(labelWithString: "金友圈")
    private let refreshButton = NSButton()
    private let browserButton = NSButton()
    private let webView: WKWebView
    private var hasLoadedPage = false

    override init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        self.webView = webView

        super.init(frame: NSRect(
            origin: .zero,
            size: NSSize(width: GoldCircleEmbeddedLayout.panelWidth, height: GoldCircleEmbeddedLayout.panelHeight)
        ))

        wantsLayer = true

        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .labelColor

        refreshButton.bezelStyle = .texturedRounded
        refreshButton.isBordered = false
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")
        refreshButton.contentTintColor = .secondaryLabelColor
        refreshButton.target = self
        refreshButton.action = #selector(reloadPage)

        browserButton.bezelStyle = .texturedRounded
        browserButton.isBordered = false
        browserButton.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "浏览器打开")
        browserButton.contentTintColor = .secondaryLabelColor
        browserButton.target = self
        browserButton.action = #selector(openInBrowser)

        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")

        [titleLabel, refreshButton, browserButton, webView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: topAnchor, constant: 23),

            browserButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            browserButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            browserButton.widthAnchor.constraint(equalToConstant: 28),
            browserButton.heightAnchor.constraint(equalToConstant: 28),

            refreshButton.trailingAnchor.constraint(equalTo: browserButton.leadingAnchor, constant: -6),
            refreshButton.centerYAnchor.constraint(equalTo: browserButton.centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 28),
            refreshButton.heightAnchor.constraint(equalToConstant: 28),

            webView.topAnchor.constraint(equalTo: topAnchor, constant: GoldCircleEmbeddedLayout.headerHeight),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override var fittingSize: NSSize {
        NSSize(width: GoldCircleEmbeddedLayout.panelWidth, height: GoldCircleEmbeddedLayout.panelHeight)
    }

    func update() {
        ensurePageLoaded()
        needsDisplay = true
    }

    func ensurePageLoaded(forceReload: Bool = false) {
        if forceReload {
            if hasLoadedPage {
                webView.reload()
            } else {
                loadPage()
            }
            return
        }

        guard !hasLoadedPage else { return }
        loadPage()
    }

    @objc
    func reloadPage() {
        ensurePageLoaded(forceReload: true)
    }

    @objc
    private func openInBrowser() {
        NSWorkspace.shared.open(GoldCircleEmbeddedLayout.pageURL)
    }

    private func loadPage() {
        var request = URLRequest(url: GoldCircleEmbeddedLayout.pageURL)
        request.timeoutInterval = 30
        request.setValue("https://jdjr.jd.com/", forHTTPHeaderField: "Referer")
        hasLoadedPage = true
        webView.load(request)
    }
}
