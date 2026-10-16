import Foundation

final class HLSURLProtocol: URLProtocol, @unchecked Sendable {
    enum ResponseSpec: Sendable {
        case success(
            statusCode: Int,
            data: Data,
            headers: [String: String]
        )
        case unfinished(
            statusCode: Int,
            data: Data,
            headers: [String: String]
        )
        case failingResponse(
            statusCode: Int,
            data: Data,
            headers: [String: String],
            errorCode: URLError.Code
        )
        case delayedSuccess(
            statusCode: Int,
            data: Data,
            headers: [String: String],
            delay: TimeInterval
        )
        case gatedSuccess(
            statusCode: Int,
            data: Data,
            headers: [String: String],
            gate: HLSURLProtocolResponseGate
        )
        case redirect(statusCode: Int, location: URL)
    }

    private struct LoadingAdmission {
        let response: ResponseSpec?
        let handler: (@Sendable (URL) -> Void)?
    }

    nonisolated(unsafe) private static var responses: [String: [ResponseSpec]] = [:]
    nonisolated(unsafe) private static var capturedRequestsStorage: [URLRequest] = []
    nonisolated(unsafe) private static var onStartLoading: (@Sendable (URL) -> Void)?
    nonisolated(unsafe) private static var onStopLoading: (@Sendable (URL) -> Void)?
    nonisolated(unsafe) private static var activeRequestCount = 0
    nonisolated(unsafe) private static var maximumActiveRequestCountStorage = 0
    nonisolated(unsafe) private static var requestGeneration = UUID()
    private static let lock = NSLock()
    private let lifecycleLock = NSLock()
    private let generation: UUID
    private var isActive = false
    private var hasFinished = false

    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: (any URLProtocolClient)?) {
        generation = Self.lock.withLock { Self.requestGeneration }
        super.init(request: request, cachedResponse: cachedResponse, client: client)
    }

    static func register(
        _ response: ResponseSpec,
        for url: URL
    ) {
        lock.lock()
        responses[url.absoluteString, default: []].append(response)
        lock.unlock()
    }

    static func capturedRequests() -> [URLRequest] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return capturedRequestsStorage
    }

    static func maximumActiveRequestCount() -> Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return maximumActiveRequestCountStorage
    }

    static func setStopLoadingHandler(
        _ handler: (@Sendable (URL) -> Void)?
    ) {
        lock.lock()
        onStopLoading = handler
        lock.unlock()
    }

    static func setStartLoadingHandler(
        _ handler: (@Sendable (URL) -> Void)?
    ) {
        lock.lock()
        onStartLoading = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        responses.removeAll()
        capturedRequestsStorage.removeAll()
        onStartLoading = nil
        onStopLoading = nil
        activeRequestCount = 0
        maximumActiveRequestCountStorage = 0
        requestGeneration = UUID()
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badURL)
            )
            return
        }

        guard let admission = beginLoading(url: url) else { return }
        admission.handler?(url)

        switch admission.response {
        case .success(let statusCode, let data, let headers):
            deliver(
                statusCode: statusCode,
                data: data,
                headers: headers,
                finishesLoading: true
            )
        case .unfinished(let statusCode, let data, let headers):
            deliver(
                statusCode: statusCode,
                data: data,
                headers: headers,
                finishesLoading: false
            )
        case .failingResponse(
            let statusCode,
            let data,
            let headers,
            let errorCode
        ):
            deliver(
                statusCode: statusCode,
                data: data,
                headers: headers,
                finishesLoading: false
            )
            guard isRequestActive() else { return }
            client?.urlProtocol(
                self,
                didFailWithError: URLError(errorCode)
            )
            markFinished()
        case .delayedSuccess(
            let statusCode,
            let data,
            let headers,
            let delay
        ):
            DispatchQueue.global().asyncAfter(
                deadline: .now() + delay
            ) { [weak self] in
                self?.deliver(
                    statusCode: statusCode,
                    data: data,
                    headers: headers,
                    finishesLoading: true
                )
            }
        case .gatedSuccess(let statusCode, let data, let headers, let gate):
            gate.arrive { [weak self] in
                self?.deliver(
                    statusCode: statusCode,
                    data: data,
                    headers: headers,
                    finishesLoading: true
                )
            }
        case .redirect(let statusCode, let location):
            guard
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Location": location.absoluteString
                    ]
                )
            else {
                client?.urlProtocol(
                    self,
                    didFailWithError: URLError(.badServerResponse)
                )
                markFinished()
                return
            }
            guard isRequestActive() else { return }
            var redirectedRequest = URLRequest(url: location)
            redirectedRequest.httpMethod = request.httpMethod
            client?.urlProtocol(
                self,
                wasRedirectedTo: redirectedRequest,
                redirectResponse: response
            )
            // The redirect hands ownership to the next protocol instance.
            // A subsequent failure races that handoff and cancels the new task.
            markFinished()
        case .none:
            guard isRequestActive() else { return }
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.unknown)
            )
            markFinished()
        }
    }

    override func stopLoading() {
        guard let url = request.url else {
            return
        }
        let handler = markFinished(stopped: true)
        handler?(url)
    }

    private func deliver(
        statusCode: Int,
        data: Data,
        headers: [String: String],
        finishesLoading: Bool
    ) {
        guard let url = request.url else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badURL)
            )
            markFinished()
            return
        }
        guard isRequestActive() else {
            return
        }
        guard
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            markFinished()
            return
        }
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        guard isRequestActive() else { return }
        client?.urlProtocol(self, didLoad: data)
        if finishesLoading {
            guard isRequestActive() else { return }
            client?.urlProtocolDidFinishLoading(self)
            markFinished()
        }
    }

    private func beginLoading(url: URL) -> LoadingAdmission? {
        lifecycleLock.lock()
        Self.lock.lock()
        defer {
            Self.lock.unlock()
            lifecycleLock.unlock()
        }
        // URLSession can schedule start/stop callbacks after invalidation.
        // Admit and record together, using the registry that created this
        // instance, so cancelled work cannot enter the next test's registry.
        guard !isActive, !hasFinished, generation == Self.requestGeneration else { return nil }
        isActive = true
        Self.capturedRequestsStorage.append(request)
        var queuedResponses = Self.responses[url.absoluteString] ?? []
        let response = queuedResponses.first
        if queuedResponses.count > 1 {
            queuedResponses.removeFirst()
            Self.responses[url.absoluteString] = queuedResponses
        }
        Self.activeRequestCount += 1
        Self.maximumActiveRequestCountStorage = max(
            Self.maximumActiveRequestCountStorage,
            Self.activeRequestCount
        )
        return LoadingAdmission(response: response, handler: Self.onStartLoading)
    }

    private func isRequestActive() -> Bool {
        lifecycleLock.lock()
        Self.lock.lock()
        defer {
            Self.lock.unlock()
            lifecycleLock.unlock()
        }
        return isActive && generation == Self.requestGeneration
    }

    @discardableResult
    private func markFinished(stopped: Bool = false) -> (@Sendable (URL) -> Void)? {
        lifecycleLock.lock()
        Self.lock.lock()
        defer {
            Self.lock.unlock()
            lifecycleLock.unlock()
        }
        let isCurrent = generation == Self.requestGeneration
        let handler = stopped && !hasFinished && isCurrent ? Self.onStopLoading : nil
        if isActive && isCurrent {
            Self.activeRequestCount = max(
                0,
                Self.activeRequestCount - 1
            )
        }
        isActive = false
        hasFinished = true
        return handler
    }
}
