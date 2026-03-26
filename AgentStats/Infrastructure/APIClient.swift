import Foundation

// MARK: - APIError

enum APIError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, data: Data?)
    case decodingError(Error)
    case networkError(Error)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL is invalid."
        case .httpError(let code, _):
            return "HTTP error \(code)."
        case .decodingError(let underlying):
            return "Response decoding failed: \(underlying.localizedDescription)"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .unauthorized:
            return "Request was unauthorized (HTTP 401/403). Re-authentication required."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(Int(seconds)) seconds."
            }
            return "Rate limited by server."
        }
    }
}

// MARK: - APIClient

/// Actor-based HTTP client used by all service providers.
///
/// Callers supply headers directly, keeping auth logic in the providers.
actor APIClient {

    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - Public API

    /// Fetches a URL and decodes the response body as `T`.
    func fetch<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        headers: [String: String]
    ) async throws -> T {
        let data = try await fetchRaw(from: url, headers: headers)
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Fetches a URL and returns the raw response body as `Data`.
    func fetchRaw(
        from url: URL,
        headers: [String: String]
    ) async throws -> Data {
        let request = buildRequest(url: url, headers: headers)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.networkError(urlError)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            // Non-HTTP responses are unexpected in this context.
            throw APIError.networkError(
                NSError(domain: "APIClient", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response received."])
            )
        }

        switch http.statusCode {
        case 200..<300:
            return data

        case 401, 403:
            throw APIError.unauthorized

        case 429:
            let retryAfter = parseRetryAfter(from: http)
            throw APIError.rateLimited(retryAfter: retryAfter)

        default:
            throw APIError.httpError(statusCode: http.statusCode, data: data.isEmpty ? nil : data)
        }
    }

    // MARK: - Private helpers

    private func buildRequest(url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        // The header value is either a delay-seconds integer or an HTTP-date.
        if let seconds = TimeInterval(value) {
            return seconds
        }
        // Attempt to parse as HTTP-date.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }
}
