import Foundation
import Observation
import OSLog

// MARK: - Protocol
protocol APIClientProtocol {
    func send<T: Decodable>(_ endpoint: APIEndpoint) async throws(APIError) -> T
    func send(_ endpoint: APIEndpoint) async throws(APIError)
    /// Sends an endpoint as `multipart/form-data` with the supplied parts.
    /// Used for the feedback POST (text + optional screenshot image).
    func sendMultipart<T: Decodable>(_ endpoint: APIEndpoint, parts: [MultipartPart]) async throws(APIError) -> T
}

/// One field in a multipart/form-data body. Pass strings via
/// `MultipartPart.text(name:value:)` and binary blobs (e.g. JPEG bytes) via
/// `MultipartPart.file(name:filename:mimeType:data:)`.
struct MultipartPart: Sendable {
    let name: String
    let filename: String?
    let mimeType: String?
    let data: Data

    static func text(name: String, value: String) -> MultipartPart {
        MultipartPart(name: name, filename: nil, mimeType: nil, data: Data(value.utf8))
    }

    static func file(name: String, filename: String, mimeType: String, data: Data) -> MultipartPart {
        MultipartPart(name: name, filename: filename, mimeType: mimeType, data: data)
    }
}

// MARK: - Concrete Client
// @Observable so it can be injected via .environment(apiClient) in SwiftUI.
@Observable
final class APIClient: APIClientProtocol {
    private let session: URLSession
    private let tokenStore: TokenStore
    private let tokenRefresher: TokenRefresher

    init(session: URLSession = .shared, tokenStore: TokenStore, tokenRefresher: TokenRefresher) {
        self.session = session
        self.tokenStore = tokenStore
        self.tokenRefresher = tokenRefresher
    }

    // MARK: - Send with Response
    func send<T: Decodable>(_ endpoint: APIEndpoint) async throws(APIError) -> T {
        let data = try await execute(endpoint, retried: false)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch let err as DecodingError {
            Logger.networking.error("Decoding failure for \(endpoint.path): \(err)")
            throw .decoding(err)
        } catch {
            throw .unknown(error)
        }
    }

    // MARK: - Send without Response
    func send(_ endpoint: APIEndpoint) async throws(APIError) {
        _ = try await execute(endpoint, retried: false)
    }

    // MARK: - Multipart
    func sendMultipart<T: Decodable>(_ endpoint: APIEndpoint, parts: [MultipartPart]) async throws(APIError) -> T {
        let data = try await executeMultipart(endpoint, parts: parts, retried: false)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch let err as DecodingError {
            Logger.networking.error("Decoding failure for \(endpoint.path): \(err)")
            throw .decoding(err)
        } catch {
            throw .unknown(error)
        }
    }

    // MARK: - Core Execution

    /// Outcome of `processResponse`: either the success `Data` or a signal
    /// that the caller should refresh the token and re-run the request.
    /// Returning a value (rather than recursing through a closure) keeps
    /// `processResponse` agnostic to how the original request was built and
    /// sidesteps a Swift typed-throws inference issue with closure params.
    private enum ResponseOutcome {
        case data(Data)
        case shouldRetry
    }

    private func execute(_ endpoint: APIEndpoint, retried: Bool) async throws(APIError) -> Data {
        let sentAccessToken = await tokenStore.getAccessToken()
        let request: URLRequest
        do {
            request = try endpoint.urlRequest(baseURL: APIConfig.baseURL, accessToken: sentAccessToken)
        } catch {
            throw .unknown(error)
        }

        Logger.networking.debug("\(endpoint.method.rawValue) \(endpoint.path)")
        let (data, response) = try await performRequest(request)
        let outcome = try await processResponse(
            data: data,
            response: response,
            endpoint: endpoint,
            sentAccessToken: sentAccessToken,
            retried: retried
        )
        switch outcome {
        case .data(let d):     return d
        case .shouldRetry:     return try await execute(endpoint, retried: true)
        }
    }

    /// Sends a `URLRequest` through the session, mapping URLError to the
    /// typed `.network` case and anything else to `.unknown`. Used by both
    /// the JSON and multipart paths so they share a single error map.
    private func performRequest(_ request: URLRequest) async throws(APIError) -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            Logger.networking.error("Network error: \(urlError)")
            throw .network(urlError)
        } catch {
            throw .unknown(error)
        }
    }

    /// Shared response handling for `execute` and `executeMultipart`:
    /// HTTPURLResponse cast, 401-then-token-refresh signal, and status-code
    /// validation against `data`. The caller decides how to re-run the
    /// request when `.shouldRetry` is returned.
    private func processResponse(
        data: Data,
        response: URLResponse,
        endpoint: APIEndpoint,
        sentAccessToken: String?,
        retried: Bool
    ) async throws(APIError) -> ResponseOutcome {
        guard let http = response as? HTTPURLResponse else {
            throw .unknown(URLError(.badServerResponse))
        }

        Logger.networking.debug("\(http.statusCode) \(endpoint.path)")

        // Only attempt refresh if the failed request actually carried an access token.
        // Otherwise the 401 came from an unauthenticated endpoint (sign-in, refresh) and
        // refreshing makes no sense — it would just mask the real error.
        if http.statusCode == 401 && !retried && sentAccessToken != nil {
            Logger.networking.info("401 on \(endpoint.path) — attempting token refresh.")
            try await tokenRefresher.refresh()
            return .shouldRetry
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = APIClient.previewBody(data)
            // Body marked private — non-2xx payloads can contain auth tokens,
            // PII, or other sensitive material. Status code and path stay public
            // so the log line is still useful in production.
            Logger.networking.error("HTTP \(http.statusCode) on \(endpoint.path): \(body, privacy: .private)")
            let message = APIError.decodeServerMessage(from: data)
            throw .httpError(statusCode: http.statusCode, message: message, data: data)
        }

        return .data(data)
    }

    // Cap response-body previews used in error logs so we don't spill huge
    // payloads (or anything beyond a quick diagnostic snippet) into the
    // unified log buffer.
    private static let bodyPreviewLimit = 512

    private static func previewBody(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            return "<\(data.count) bytes, non-utf8>"
        }
        if text.count <= bodyPreviewLimit {
            return text
        }
        let prefix = text.prefix(bodyPreviewLimit)
        return "\(prefix)…(\(text.count - bodyPreviewLimit) more chars)"
    }

    // MARK: - Multipart Execution
    private func executeMultipart(
        _ endpoint: APIEndpoint,
        parts: [MultipartPart],
        retried: Bool
    ) async throws(APIError) -> Data {
        let sentAccessToken = await tokenStore.getAccessToken()

        let boundary = "Boundary-\(UUID().uuidString)"
        let body = APIClient.encodeMultipart(parts: parts, boundary: boundary)

        // Reuse the endpoint's URL but build the request manually so we can
        // override Content-Type with the multipart boundary header.
        let pathURL = APIConfig.baseURL.appending(path: endpoint.path)
        var request = URLRequest(url: pathURL)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = sentAccessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        Logger.networking.debug("\(endpoint.method.rawValue) \(endpoint.path) (multipart, \(body.count) bytes)")
        let (data, response) = try await performRequest(request)
        let outcome = try await processResponse(
            data: data,
            response: response,
            endpoint: endpoint,
            sentAccessToken: sentAccessToken,
            retried: retried
        )
        switch outcome {
        case .data(let d):     return d
        case .shouldRetry:     return try await executeMultipart(endpoint, parts: parts, retried: true)
        }
    }

    /// Encode the parts into a multipart/form-data body. Each part's headers
    /// follow RFC 7578 — `Content-Disposition: form-data; name="..."`, plus
    /// `filename` and `Content-Type` for file parts.
    static func encodeMultipart(parts: [MultipartPart], boundary: String) -> Data {
        var data = Data()
        let boundaryPrefix = "--\(boundary)\r\n"

        for part in parts {
            data.append(boundaryPrefix.data(using: .utf8)!)

            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            disposition += "\r\n"
            data.append(disposition.data(using: .utf8)!)

            if let mimeType = part.mimeType {
                data.append("Content-Type: \(mimeType)\r\n".data(using: .utf8)!)
            }

            data.append("\r\n".data(using: .utf8)!)
            data.append(part.data)
            data.append("\r\n".data(using: .utf8)!)
        }

        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }
}
