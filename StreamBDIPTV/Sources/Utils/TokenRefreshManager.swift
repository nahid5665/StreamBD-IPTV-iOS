import Foundation
import Combine

@MainActor
final class TokenRefreshManager: ObservableObject {
    static let shared = TokenRefreshManager()

    @Published var lastRefreshTime: Date? = nil
    @Published var isRefreshing: Bool = false
    @Published var tokenStatus: String = "Ready"

    // Active tokens cache: key -> token/cookie string
    private var activeTokens: [String: String] = [:]
    private var timerCancellable: AnyCancellable?

    private init() {
        startScheduledRefreshTimer()
    }

    /// Starts a periodic 2-hour (7200 seconds) refresh loop
    func startScheduledRefreshTimer() {
        timerCancellable?.cancel()
        // Refresh every 2 hours (7200 seconds)
        timerCancellable = Timer.publish(every: 7200, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.refreshAllTokens()
                }
            }
    }

    /// Refresh all playlist tokens immediately (called at launch and every 2 hours)
    func refreshAllTokens() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        tokenStatus = "Refreshing playlist tokens…"

        // 1. Refresh Jio TV Session Tokens (S1 & S2)
        await refreshJioSessionToken()

        // 2. Refresh PlusBox Token
        await refreshPlusBoxToken()

        // 3. Refresh Oxoo Portal Tokens
        refreshOxooPortalTokens()

        lastRefreshTime = Date()
        isRefreshing = false
        tokenStatus = "Tokens Active (Updated: \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)))"
    }

    /// Returns the latest active token for a provider
    func getToken(for provider: String) -> String? {
        return activeTokens[provider]
    }

    /// Injects fresh tokens and headers into a stream URL before playback
    func applyLiveToken(to rawUrl: String, channel: Channel) -> (url: String, headers: [String: String]) {
        var finalUrl = rawUrl
        var headers = channel.httpHeaders

        // Jio TV Token Replacement
        if rawUrl.contains("workers.dev") || channel.group.localizedCaseInsensitiveContains("Jio") {
            if let sessionCookie = activeTokens["jio_session"] {
                headers["Cookie"] = sessionCookie
                headers["Referer"] = "https://jp.ipl2026.workers.dev/"
                headers["Origin"] = "https://jp.ipl2026.workers.dev"
            }
        }

        // PlusBox Token Replacement
        if rawUrl.contains("plusbox.tv") || channel.group.localizedCaseInsensitiveContains("PlusBox") {
            if let token = activeTokens["plusbox"] {
                if finalUrl.contains("token=") {
                    // Replace existing expired token parameter with fresh one
                    let regex = try? NSRegularExpression(pattern: #"token=[^&|]+"#)
                    finalUrl = regex?.stringByReplacingMatches(
                        in: finalUrl,
                        range: NSRange(finalUrl.startIndex..., in: finalUrl),
                        withTemplate: "token=\(token)"
                    ) ?? finalUrl
                }
            }
            headers["User-Agent"] = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36"
            headers["Referer"] = "https://backend.plusbox.tv/"
            headers["Origin"] = "https://plusbox.tv"
        }

        // Toffee headers
        if rawUrl.contains("toffeelive") || channel.group.localizedCaseInsensitiveContains("Toffee") {
            headers["User-Agent"] = "Toffee (Linux; Android 12; Pixel 6) ExoPlayerLib/2.18.1"
            headers["Origin"] = "https://toffeelive.com"
        }

        return (finalUrl, headers)
    }

    // MARK: - Private Token Refreshers

    private func refreshJioSessionToken() async {
        guard let url = URL(string: "https://s.ipl2026.workers.dev/create-session") else { return }
        var req = URLRequest(url: url)
        req.setValue("https://jp.ipl2026.workers.dev", forHTTPHeaderField: "Origin")
        req.setValue("https://jp.ipl2026.workers.dev/", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 8

        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let sessionId = json["sessionId"] as? String {
            activeTokens["jio_session"] = "session=\(sessionId)"
        }
    }

    private func refreshPlusBoxToken() async {
        guard let url = URL(string: "https://plusbox.tv/token.php") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("https://plusbox.tv/", forHTTPHeaderField: "Referer")
        req.setValue("https://plusbox.tv", forHTTPHeaderField: "Origin")
        req.httpBody = "ch_name=somoy_tv".data(using: .utf8)
        req.timeoutInterval = 8

        if let (data, resp) = try? await URLSession.shared.data(for: req),
           let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
           let tokenStr = String(data: data, encoding: .utf8) {
            let cleanToken = tokenStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanToken.isEmpty {
                activeTokens["plusbox"] = cleanToken
            }
        }
    }

    private func refreshOxooPortalTokens() {
        // Standard Oxoo base64 token
        activeTokens["oxoo_default"] = "Basic YWRtaW46MTIzNA=="
    }
}
