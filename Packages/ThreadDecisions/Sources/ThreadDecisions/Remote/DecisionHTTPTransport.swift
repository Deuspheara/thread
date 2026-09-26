import Foundation

/// Isolates bounded HTTP delivery from inference payload preparation and response interpretation.
protocol DecisionHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> Data
}

/// Sends ephemeral, non-redirecting requests and bounds streamed response memory.
final class URLSessionDecisionTransport: DecisionHTTPTransport, Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 5
        session = URLSession(configuration: configuration, delegate: DecisionRedirectRejection(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func send(_ request: URLRequest) async throws -> Data {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { throw RemoteDecisionError.invalidResponse }
            try DecisionHTTPResponsePolicy.validate(http)
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 65_536 else { throw RemoteDecisionError.responseTooLarge }
                data.append(byte)
            }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            throw error.code == .timedOut ? RemoteDecisionError.timedOut : RemoteDecisionError.transportUnavailable
        }
    }
}

/// Rejects unsafe status, media type and declared size before consuming response bytes.
enum DecisionHTTPResponsePolicy {
    static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200: break
        case 401, 403: throw RemoteDecisionError.authenticationRequired
        case 429: throw RemoteDecisionError.rateLimited
        case 500...599: throw RemoteDecisionError.transportUnavailable
        default: throw RemoteDecisionError.invalidResponse
        }
        guard response.mimeType?.lowercased() == "application/json" else { throw RemoteDecisionError.invalidResponse }
        guard response.expectedContentLength <= 65_536 else { throw RemoteDecisionError.responseTooLarge }
    }
}

/// Prevents authorization or context data from following backend redirects.
final class DecisionRedirectRejection: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
