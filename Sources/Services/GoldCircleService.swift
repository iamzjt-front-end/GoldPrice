import Foundation
import WebKit

final class GoldCircleService {
    static let shared = GoldCircleService()

    fileprivate enum ServiceError: LocalizedError {
        case invalidURL
        case timedOut
        case extractionFailed
        case noPosts

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "金友圈页面地址无效"
            case .timedOut:
                return "金友圈页面加载超时"
            case .extractionFailed:
                return "金友圈帖子解析失败"
            case .noPosts:
                return "暂时没有抓到最新帖子"
            }
        }
    }

    fileprivate struct ScrapedPost: Decodable {
        let contentId: String
        let contentType: String
        let authorName: String
        let authorBadgeText: String
        let authorBadgeTexts: [String]
        let avatarURL: String
        let publishedAtText: String
        let title: String
        let summary: String
        let commentCountText: String
        let likeCountText: String
        let imageURLs: [String]
        let highlightText: String
        let jumpURL: String
    }

    private let cacheTTL: TimeInterval = 300
    private let queue = DispatchQueue(label: "GoldCircleService")
    private var cache: [GoldCirclePostItem] = []
    private var fetchedAt: Date?
    private var inflight: [(Result<[GoldCirclePostItem], Error>) -> Void] = []
    @MainActor private var activeScraper: GoldCirclePageScraper?

    private init() {}

    func cachedItems() -> [GoldCirclePostItem]? {
        queue.sync {
            guard let fetchedAt, Date().timeIntervalSince(fetchedAt) <= cacheTTL, !cache.isEmpty else {
                return nil
            }
            return cache
        }
    }

    func fetchPosts(
        forceRefresh: Bool = false,
        completion: @escaping (Result<[GoldCirclePostItem], Error>) -> Void
    ) {
        if !forceRefresh, let cached = cachedItems() {
            DispatchQueue.main.async {
                completion(.success(cached))
            }
            return
        }

        queue.async {
            if !forceRefresh,
               let fetchedAt = self.fetchedAt,
               Date().timeIntervalSince(fetchedAt) <= self.cacheTTL,
               !self.cache.isEmpty {
                let cached = self.cache
                DispatchQueue.main.async {
                    completion(.success(cached))
                }
                return
            }

            if !self.inflight.isEmpty {
                self.inflight.append(completion)
                return
            }

            self.inflight = [completion]
            self.performFetch()
        }
    }

    private func performFetch() {
        DispatchQueue.main.async {
            guard let url = URL(string: "https://content.jr.jd.com/jrq/#/group?id=13245&channel=jyq&channelfrom=grouppc") else {
                self.finish(.failure(ServiceError.invalidURL))
                return
            }

            let scraper = GoldCirclePageScraper(url: url) { [weak self] result in
                guard let self = self else { return }
                Task { @MainActor in
                    self.activeScraper = nil
                }
                self.queue.async {
                    switch result {
                    case .success(let scrapedPosts):
                        let now = Date()
                        let items = scrapedPosts.map { post in
                            GoldCirclePostItem(
                                contentId: post.contentId,
                                contentType: post.contentType,
                                authorName: post.authorName,
                                authorBadgeText: post.authorBadgeText,
                                authorBadgeTexts: post.authorBadgeTexts,
                                avatarURL: URL(string: post.avatarURL),
                                publishedAtText: post.publishedAtText,
                                title: post.title,
                                summary: post.summary,
                                commentCountText: post.commentCountText,
                                likeCountText: post.likeCountText,
                                imageURLs: post.imageURLs.compactMap(URL.init(string:)),
                                highlightText: post.highlightText,
                                jumpURL: URL(string: post.jumpURL),
                                fetchedAt: now
                            )
                        }

                        guard !items.isEmpty else {
                            self.finish(.failure(ServiceError.noPosts))
                            return
                        }

                        self.cache = items
                        self.fetchedAt = now
                        self.finish(.success(items))
                    case .failure(let error):
                        self.finish(.failure(error))
                    }
                }
            }

            self.activeScraper = scraper
            scraper.start()
        }
    }

    private func finish(_ result: Result<[GoldCirclePostItem], Error>) {
        queue.async {
            let callbacks = self.inflight
            self.inflight.removeAll()
            DispatchQueue.main.async {
                callbacks.forEach { $0(result) }
            }
        }
    }
}

@MainActor
private final class GoldCirclePageScraper: NSObject, WKNavigationDelegate {
    private static let viewportSize = CGSize(width: 390, height: 844)

    private let url: URL
    private let completion: (Result<[GoldCircleService.ScrapedPost], Error>) -> Void

    private var webView: WKWebView?
    private var timeoutWorkItem: DispatchWorkItem?
    private var pollAttempts = 0
    private var hasFinished = false

    init(
        url: URL,
        completion: @escaping (Result<[GoldCircleService.ScrapedPost], Error>) -> Void
    ) {
        self.url = url
        self.completion = completion
        super.init()
    }

    func start() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // The circle page does not render feed cards into the DOM when the viewport is 0x0.
        let webView = WKWebView(
            frame: NSRect(origin: .zero, size: Self.viewportSize),
            configuration: configuration
        )
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        self.webView = webView

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("https://jdjr.jd.com/", forHTTPHeaderField: "Referer")
        webView.load(request)

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.finish(.failure(GoldCircleService.ServiceError.timedOut))
        }
        self.timeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeoutWorkItem)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pollForPosts()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func pollForPosts() {
        guard !hasFinished, let webView else { return }

        webView.evaluateJavaScript(Self.extractionScript) { [weak self] result, error in
            guard let self = self, !self.hasFinished else { return }

            if let error {
                self.finish(.failure(error))
                return
            }

            guard
                let resultString = result as? String,
                let data = resultString.data(using: .utf8)
            else {
                self.retryPolling()
                return
            }

            do {
                let response = try JSONDecoder().decode(GoldCircleScrapeResponse.self, from: data)
                switch response.status {
                case "ready" where !response.posts.isEmpty:
                    self.finish(.success(response.posts))
                case "ready", "switching", "waiting", "collecting":
                    self.retryPolling()
                default:
                    self.finish(.failure(GoldCircleService.ServiceError.extractionFailed))
                }
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    private func retryPolling() {
        pollAttempts += 1
        guard pollAttempts < 24 else {
            finish(.failure(GoldCircleService.ServiceError.noPosts))
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.pollForPosts()
        }
    }

    private func finish(_ result: Result<[GoldCircleService.ScrapedPost], Error>) {
        guard !hasFinished else { return }
        hasFinished = true
        timeoutWorkItem?.cancel()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        completion(result)
    }

    private struct GoldCircleScrapeResponse: Decodable {
        let status: String
        let posts: [GoldCircleService.ScrapedPost]
    }

    private static let extractionScript = #"""
    (() => {
      const normalizeURL = (value) => {
        if (!value) return '';
        if (value.startsWith('//')) return `https:${value}`;
        return value;
      };

      const textValue = (value) => (value || '').replace(/\s+/g, ' ').trim();

      const parseJSON = (value) => {
        if (!value) return {};
        try { return JSON.parse(value); } catch (_) { return {}; }
      };

      const tabs = Array.from(document.querySelectorAll('.van-tab'));
      const latestIndex = tabs.findIndex((element) => textValue(element.textContent).includes('最新'));
      const activeIndex = tabs.findIndex((element) => element.classList.contains('van-tab--active'));

      if (latestIndex >= 0 && activeIndex !== latestIndex) {
        window.__goldCircleScrapeState = { scrollPasses: 0, lastCount: 0 };
        tabs[latestIndex].click();
        window.scrollTo(0, 0);
        return JSON.stringify({ status: 'switching', posts: [] });
      }

      const panes = Array.from(document.querySelectorAll('.van-tab__pane'));
      const paneIndex = latestIndex >= 0 ? latestIndex : (activeIndex >= 0 ? activeIndex : 0);
      const activePane = panes[paneIndex] || panes[0];
      if (!activePane) {
        return JSON.stringify({ status: 'waiting', posts: [] });
      }

      const cards = Array.from(activePane.querySelectorAll('.feedList'));
      const seen = new Set();

      const posts = cards.map((card) => {
        const anchor = card.querySelector('.feed_msg[data-qidian-spj]') || card.querySelector('.h-user[data-qidian-spj]') || card.querySelector('[data-qidian-spj]');
        const spj = parseJSON(anchor?.getAttribute('data-qidian-spj'));
        const contentId = textValue(spj.contentId || '');
        const contentType = textValue(spj.contentType || '');

        if (!contentId || seen.has(contentId)) {
          return null;
        }
        seen.add(contentId);

        const authorName = textValue(card.querySelector('.nicname')?.textContent);
        const authorBadgeTexts = Array.from(card.querySelectorAll('.new-tag span'))
          .map((element) => textValue(element.textContent))
          .filter(Boolean);
        const authorBadgeText = authorBadgeTexts[0] || '';
        const publishedAtText = textValue(card.querySelector('.h-u-title > p:last-child')?.textContent);

        const title = textValue(
          card.querySelector('.feed_msg .m4 span')?.textContent ||
          card.querySelector('.feed_msg .van-multi-ellipsis--l2 span')?.textContent
        );
        const summary = textValue(card.querySelector('.feed_msg .content-text')?.textContent);

        const sanitizeCount = (value, fallbackLabel) => {
          const normalized = textValue(value);
          if (!normalized || normalized === fallbackLabel) {
            return '';
          }
          return normalized;
        };

        const commentCountText = sanitizeCount(
          card.querySelector('.i-other [clstag*="feed_comment"] span:last-child')?.textContent,
          '评论'
        );
        const likeCountText = sanitizeCount(
          card.querySelector('.i-other [clstag*="feed_like"] span:last-child')?.textContent,
          '点赞'
        );

        const imageURLs = Array.from(card.querySelectorAll('.feed_grid .g-img img'))
          .map((image) => normalizeURL(image.getAttribute('data-src') || image.getAttribute('src') || ''))
          .filter((value) => value && !value.startsWith('data:image/gif'));

        const rightTextLines = Array.from(card.querySelectorAll('.right-text p, .right-text span, .right-text strong'))
          .map((element) => textValue(element.textContent))
          .filter(Boolean);

        const metricTexts = Array.from(card.querySelectorAll('.middle .m-item'))
          .map((element) => {
            const label = textValue(element.querySelector('span')?.textContent);
            const value = textValue(element.querySelector('strong')?.textContent);
            if (!label && !value) return '';
            return `${label} ${value}`.trim();
          })
          .filter(Boolean);

        const highlightCandidates = [...authorBadgeTexts, ...rightTextLines, ...metricTexts];
        const highlightText = highlightCandidates.find((text) => /收益|持仓|热议|粉丝|金价/.test(text)) || '';

        const avatarURL = Array.from(card.querySelectorAll('.feed_head .h-user img'))
          .map((image) => normalizeURL(image.getAttribute('data-src') || image.getAttribute('src') || ''))
          .find((value) => value && !value.includes('/mcmkt') && !value.endsWith('.png') && !value.includes('width=189')) || '';

        const isDynamic = contentType.includes('动态');
        const jumpURL = isDynamic
          ? `https://roma.jd.com/content/dynamic-detail?createdPin=1&contentId=${contentId}&channelType=&channelfrom=grouppc`
          : `https://content.jr.jd.com/article/index.html?pageId=${contentId}&channelType=&channelfrom=grouppc`;

        if (!authorName || (!title && !summary)) {
          return null;
        }

        return {
          contentId,
          contentType: isDynamic ? '动态' : (contentType || '文章'),
          authorName,
          authorBadgeText,
          authorBadgeTexts,
          avatarURL,
          publishedAtText,
          title,
          summary,
          commentCountText,
          likeCountText,
          imageURLs,
          highlightText,
          jumpURL
        };
      }).filter(Boolean);

      if (!window.__goldCircleScrapeState) {
        window.__goldCircleScrapeState = { scrollPasses: 0, lastCount: 0 };
      }

      const scrapeState = window.__goldCircleScrapeState;
      const previousCount = Number(scrapeState.lastCount || 0);
      const currentCount = posts.length;
      const bodyHeight = Math.max(
        document.body?.scrollHeight || 0,
        document.documentElement?.scrollHeight || 0
      );
      const reachedBottom = window.scrollY + window.innerHeight >= bodyHeight - 80;
      const grew = currentCount > previousCount;
      scrapeState.lastCount = Math.max(previousCount, currentCount);

      if (currentCount > 0 && scrapeState.scrollPasses < 3 && (!reachedBottom || grew)) {
        scrapeState.scrollPasses += 1;
        window.scrollTo(0, bodyHeight);
        return JSON.stringify({
          status: 'collecting',
          posts
        });
      }

      return JSON.stringify({
        status: posts.length > 0 ? 'ready' : 'waiting',
        posts
      });
    })();
    """#
}
