import Foundation
import Combine

@MainActor
final class TokenRefreshManager: ObservableObject {
    static let shared = TokenRefreshManager()

    @Published var lastRefreshTime: Date? = nil
    @Published var isRefreshing: Bool = false
    @Published var tokenStatus: String = "Ready"

    /// Called after every successful BDTube channel refresh with the fresh
    /// channel list. MainViewModel registers a hook that swaps the signed URLs
    /// into its caches without interrupting active playback (BDTube widget parity).
    var liveChannelRefresher: (@MainActor ([Channel]) -> Void)? = nil

    // Active tokens cache (kept for user-added playlists; e.g. PlusBox URLs)
    private var activeTokens: [String: String] = [:]
    private var plusBoxChannelTokens: [String: (token: String, timestamp: Date)] = [:]
    private var timerCancellable: AnyCancellable?

    private init() {
        startScheduledRefreshTimer(delay: AppConfig.bdTubeRefreshInterval)
    }

    /// Starts a periodic refresh loop. The interval is dynamic:
    /// min(2h, signed session expiry − 30min), floored at 60s — ported from
    /// the BDTube widget's Tok.schedule/Tok.delay.
    func startScheduledRefreshTimer(delay: TimeInterval) {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: delay, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.refreshAllTokens()
                }
            }
        addonLog("[TokenRefresh] next auto-refresh in \(Int(delay))s")
    }

    /// Refresh all playlist tokens immediately (at launch and on schedule)
    func refreshAllTokens() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        tokenStatus = "Refreshing live tokens…"

        // 1. Refresh the BDTube server list (signed session URLs)
        let freshChannels = await BDTubeService.shared.refresh()
        if !freshChannels.isEmpty {
            liveChannelRefresher?(freshChannels)
        }

        // 2. Clear old cached PlusBox channel tokens so fresh ones are requested on next play
        plusBoxChannelTokens.removeAll()

        lastRefreshTime = Date()
        isRefreshing = false
        tokenStatus = "Tokens Active (\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)))"

        // 3. Re-schedule from the parsed session expiry (BDTube widget parity)
        startScheduledRefreshTimer(delay: BDTubeService.shared.nextRefreshDelay())
    }

    /// Dynamically fetches a fresh token for a specific PlusBox channel on demand
    func fetchPlusBoxToken(for channelName: String) async -> String {
        // Return cached token if less than 90 minutes old
        if let cached = plusBoxChannelTokens[channelName],
           Date().timeIntervalSince(cached.timestamp) < 5400 {
            return cached.token
        }

        guard let url = URL(string: "https://plusbox.tv/token.php") else { return "" }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Mobile Safari/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue("https://plusbox.tv/", forHTTPHeaderField: "Referer")
        req.setValue("https://plusbox.tv", forHTTPHeaderField: "Origin")
        req.httpBody = "ch_name=\(channelName)".data(using: .utf8)
        req.timeoutInterval = 5

        if let (data, resp) = try? await URLSession.shared.data(for: req),
           let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
           let tokenStr = String(data: data, encoding: .utf8) {
            let cleanToken = tokenStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanToken.isEmpty && !cleanToken.contains("<html") {
                plusBoxChannelTokens[channelName] = (token: cleanToken, timestamp: Date())
                return cleanToken
            }
        }
        return ""
    }

    /// Injects fresh tokens and headers into a stream URL before playback
    func applyLiveToken(to rawUrl: String, channel: Channel) async -> (url: String, headers: [String: String]) {
        var finalUrl = rawUrl
        var headers = channel.httpHeaders

        // PlusBox dynamic token
        if rawUrl.contains("plusboxChannel=") || rawUrl.contains("plusbox.tv") {
            var channelKey = ""
            if let range = rawUrl.range(of: "plusboxChannel=([^|&\\s]+)", options: .regularExpression) {
                let match = String(rawUrl[range])
                channelKey = match.replacingOccurrences(of: "plusboxChannel=", with: "")
            }
            if channelKey.isEmpty {
                let clean = rawUrl.components(separatedBy: "|").first ?? rawUrl
                if let u = URL(string: clean) {
                    let comps = u.pathComponents.filter { $0 != "/" }
                    if let first = comps.first { channelKey = first }
                }
            }
            if !channelKey.isEmpty {
                let token = await fetchPlusBoxToken(for: channelKey)
                let baseStream = rawUrl.components(separatedBy: "|").first ?? rawUrl
                if !token.isEmpty {
                    finalUrl = "\(baseStream)?token=\(token)"
                } else {
                    finalUrl = baseStream
                }
                headers["User-Agent"] = AppConfig.browserUserAgent
                headers["Referer"] = "https://backend.plusbox.tv/\(channelKey)/embed.html"
                headers["Origin"] = "https://plusbox.tv"
            }
        }

        // Toffee headers
        if rawUrl.contains("toffeelive") || channel.group.localizedCaseInsensitiveContains("Toffee") {
            headers["User-Agent"] = "Toffee (Linux; Android 12; Pixel 6) ExoPlayerLib/2.18.1"
            headers["Origin"] = "https://toffeelive.com"
        }

        return (finalUrl, headers)
    }
}
