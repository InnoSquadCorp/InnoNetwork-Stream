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

    nonisolated(unsafe) private static var responses: [String: [ResponseSpec]] = [:]
    nonisolated(unsafe) private static var capturedRequestsStorage: [URLRequest] = []
    nonisolated(unsafe) private static var onStartLoading: (@Sendable (URL) -> Void)?
    nonisolated(unsafe) private static var onStopLoading: (@Sendable (URL) -> Void)?
    nonisolated(unsafe) private static var activeRequestCount = 0
    nonisolated(unsafe) private static var maximumActiveRequestCountStorage = 0
    nonisolated(unsafe) private static var requestGeneration = UUID()
    private static let lock = NSLock()
    private let lifecycleLock = NSLock()
    private var isActive = false
    private var activeGeneration: UUID?

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

        Self.lock.lock()
        Self.capturedRequestsStorage.append(request)
        var queuedResponses =
            Self.responses[url.absoluteString] ?? []
        let responseSpec = queuedResponses.first
        if queuedResponses.count > 1 {
            queuedResponses.removeFirst()
            Self.responses[url.absoluteString] = queuedResponses
        }
        let startLoadingHandler = Self.onStartLoading
        let generation = Self.requestGeneration
        Self.lock.unlock()
        guard markActive(generation: generation) else { return }
        startLoadingHandler?(url)

        switch responseSpec {
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
        Self.lock.lock()
        let handler = Self.onStopLoading
        Self.lock.unlock()
        handler?(url)
        markFinished()
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
        client?.urlProtocol(self, didLoad: data)
        if finishesLoading {
            client?.urlProtocolDidFinishLoading(self)
            markFinished()
        }
    }

    private func markActive(generation: UUID) -> Bool {
        lifecycleLock.lock()
        Self.lock.lock()
        defer {
            Self.lock.unlock()
            lifecycleLock.unlock()
        }
        guard generation == Self.requestGeneration else { return false }
        isActive = true
        activeGeneration = generation
        Self.activeRequestCount += 1
        Self.maximumActiveRequestCountStorage = max(
            Self.maximumActiveRequestCountStorage,
            Self.activeRequestCount
        )
        return true
    }

    private func isRequestActive() -> Bool {
        lifecycleLock.lock()
        defer {
            lifecycleLock.unlock()
        }
        return isActive
    }

    private func markFinished() {
        lifecycleLock.lock()
        let wasActive = isActive
        let generation = activeGeneration
        isActive = false
        activeGeneration = nil
        lifecycleLock.unlock()
        guard wasActive else {
            return
        }
        Self.lock.lock()
        // Session invalidation can deliver an old stop after the next test
        // resets the registry. It must not decrement the new test's count.
        if generation == Self.requestGeneration {
            Self.activeRequestCount = max(
                0,
                Self.activeRequestCount - 1
            )
        }
        Self.lock.unlock()
    }
}
