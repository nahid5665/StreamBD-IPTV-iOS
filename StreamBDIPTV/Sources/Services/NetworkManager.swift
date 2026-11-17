import Foundation

final class UnsafeSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

final class NetworkManager {
    static let shared = NetworkManager()

    let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config, delegate: UnsafeSessionDelegate(), delegateQueue: nil)
    }

    /// Fetches a URL, applies custom headers, and automatically runs `CryptoUtils.decryptIfNeeded`
    func fetchText(from urlString: String, headers: [String: String] = [:], method: String = "GET", body: Data? = nil) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(headers["User-Agent"] ?? AppConfig.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        let (data, _) = try await session.data(for: request)
        let rawText = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return CryptoUtils.decryptIfNeeded(rawText)
    }

    func fetchDecodable<T: Decodable>(_ type: T.Type, from urlString: String, headers: [String: String] = [:]) async throws -> T {
        let decryptedText = try await fetchText(from: urlString, headers: headers)
        guard let data = decryptedText.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}
