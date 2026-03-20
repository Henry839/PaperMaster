import Foundation

struct NetworkTransport {
    private static let retryDelaysNanoseconds: [UInt64] = [
        350_000_000,
        1_000_000_000
    ]

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    static func data(from url: URL) async throws -> (Data, URLResponse) {
        try await execute {
            try await session.data(from: url)
        }
    }

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var requestWithTimeout = request
        if requestWithTimeout.timeoutInterval <= 0 {
            requestWithTimeout.timeoutInterval = 30
        }
        let preparedRequest = requestWithTimeout

        return try await execute { [preparedRequest] in
            try await session.data(for: preparedRequest)
        }
    }

    private static func execute(
        operation: @escaping @Sendable () async throws -> (Data, URLResponse)
    ) async throws -> (Data, URLResponse) {
        var attempt = 0

        while true {
            do {
                let result = try await operation()
                if shouldRetry(response: result.1), attempt < retryDelaysNanoseconds.count {
                    try await Task.sleep(nanoseconds: retryDelaysNanoseconds[attempt])
                    attempt += 1
                    continue
                }
                return result
            } catch {
                guard shouldRetry(error: error), attempt < retryDelaysNanoseconds.count else {
                    throw error
                }

                try await Task.sleep(nanoseconds: retryDelaysNanoseconds[attempt])
                attempt += 1
            }
        }
    }

    private static func shouldRetry(response: URLResponse) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        let statusCode = httpResponse.statusCode
        return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }

    private static func shouldRetry(error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
        case .timedOut,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .resourceUnavailable,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }
}
