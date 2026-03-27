import Foundation

struct IntradayChartPoint: Equatable {
    enum Marker: String {
        case highKey
        case lowKey
    }

    let timestamp: Date
    let price: Double
    let marker: Marker?
}

struct IntradayChartSeries: Equatable {
    let source: GoldPriceSource
    let tradeDate: Date
    let points: [IntradayChartPoint]
    let fetchedAt: Date

    var records: [PriceRecord] {
        points.map { PriceRecord(timestamp: $0.timestamp, price: $0.price) }
    }

    var high: Double? {
        points.map(\.price).max()
    }

    var low: Double? {
        points.map(\.price).min()
    }
}

final class OfficialIntradayChartService {
    static let shared = OfficialIntradayChartService()

    private let session: URLSession
    private let cacheTTL: TimeInterval = 45
    private let queue = DispatchQueue(label: "OfficialIntradayChartService")
    private var cache: [GoldPriceSource: IntradayChartSeries] = [:]
    private var inflight: [GoldPriceSource: [(Result<IntradayChartSeries, Error>) -> Void]] = [:]

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func cachedSeries(for source: GoldPriceSource) -> IntradayChartSeries? {
        queue.sync {
            guard let series = cache[source], isSeriesCurrent(series) else { return nil }
            return series
        }
    }

    func latestSeries(for source: GoldPriceSource) -> IntradayChartSeries? {
        queue.sync {
            guard let series = cache[source],
                  Calendar.current.isDate(series.tradeDate, inSameDayAs: Date()) else { return nil }
            return series
        }
    }

    func fetchIntradaySeries(
        for source: GoldPriceSource,
        forceRefresh: Bool = false,
        completion: @escaping (Result<IntradayChartSeries, Error>) -> Void
    ) {
        if !forceRefresh, let cached = cachedSeries(for: source) {
            completion(.success(cached))
            return
        }

        queue.async {
            if self.inflight[source] != nil {
                self.inflight[source]?.append(completion)
                return
            }

            self.inflight[source] = [completion]
            self.performFetch(for: source)
        }
    }

    private func performFetch(for source: GoldPriceSource) {
        guard let request = makeRequest(for: source) else {
            finish(source: source, result: .failure(ServiceError.unsupportedSource))
            return
        }

        session.dataTask(with: request) { data, _, error in
            if let error {
                self.finish(source: source, result: .failure(error))
                return
            }

            guard let data else {
                self.finish(source: source, result: .failure(ServiceError.emptyResponse))
                return
            }

            do {
                let series = try self.parseSeries(from: data, source: source)
                self.queue.async {
                    self.cache[source] = series
                }
                self.finish(source: source, result: .success(series))
            } catch {
                self.finish(source: source, result: .failure(error))
            }
        }.resume()
    }

    private func finish(source: GoldPriceSource, result: Result<IntradayChartSeries, Error>) {
        queue.async {
            let callbacks = self.inflight.removeValue(forKey: source) ?? []
            DispatchQueue.main.async {
                callbacks.forEach { $0(result) }
            }
        }
    }

    private func isSeriesCurrent(_ series: IntradayChartSeries) -> Bool {
        Calendar.current.isDate(series.tradeDate, inSameDayAs: Date()) &&
        Date().timeIntervalSince(series.fetchedAt) <= cacheTTL
    }

    private func makeRequest(for source: GoldPriceSource) -> URLRequest? {
        switch source {
        case .jdZsFinance:
            guard let url = URL(string: "https://api.jdjygold.com/gw2/generic/jrm/h5/m/stdTodayLatestPrices") else {
                return nil
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = #"reqData={"productSku":"1961543816"}"#.data(using: .utf8)
            return request
        case .jdMsFinance:
            guard let url = URL(string: "https://api.jdjygold.com/gw/generic/hj/h5/m/todayLatestPrices?reqData=%7B%7D") else {
                return nil
            }
            return URLRequest(url: url)
        case .londonGold, .newyorkGold:
            return nil
        }
    }

    private func parseSeries(from data: Data, source: GoldPriceSource) throws -> IntradayChartSeries {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let resultData = json["resultData"] as? [String: Any],
            let datas = resultData["datas"] as? [[String: Any]]
        else {
            throw ServiceError.invalidPayload
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let points = datas.compactMap { item -> IntradayChartPoint? in
            guard
                let value = item["value"] as? [String],
                value.count >= 2,
                let timestamp = formatter.date(from: value[0]),
                let price = Double(value[1])
            else {
                return nil
            }

            let marker = value.count >= 3 ? IntradayChartPoint.Marker(rawValue: value[2]) : nil
            return IntradayChartPoint(timestamp: timestamp, price: price, marker: marker)
        }

        guard let first = points.first else {
            throw ServiceError.emptySeries
        }

        return IntradayChartSeries(
            source: source,
            tradeDate: first.timestamp,
            points: points.sorted { $0.timestamp < $1.timestamp },
            fetchedAt: Date()
        )
    }
}

extension OfficialIntradayChartService {
    enum ServiceError: LocalizedError {
        case unsupportedSource
        case emptyResponse
        case invalidPayload
        case emptySeries

        var errorDescription: String? {
            switch self {
            case .unsupportedSource:
                return "当前数据源不支持官方分时"
            case .emptyResponse:
                return "官方分时接口无响应"
            case .invalidPayload:
                return "官方分时数据格式异常"
            case .emptySeries:
                return "官方分时暂无数据"
            }
        }
    }
}
