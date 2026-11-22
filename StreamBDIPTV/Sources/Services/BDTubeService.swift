import Foundation

/// BDTube live server client — ported from the BDTube Samsung TV widget
/// (`wgt/js/api.js` + `wgt/js/tokenManager.js` in live-tv-main).
///
/// Responsibilities:
/// 1. Fetch the channel list from the BDTube API (TV endpoint on :8889 first,
///    then the web endpoint), normalizing the several field spellings the
///    server has used (`url/streamUrl/stream_url/stream`, `logo/logoUrl/logo_url/icon`,
///    `category/group`, `name/title`).
/// 2. Parse the signed session token expiry embedded in each stream URL
///    (`session=...-<10 digits>-<10 digits>`) so TokenRefreshManager can
///    schedule a refresh 30 minutes before expiry, exactly like the widget.
@MainActor
final class BDTubeService {
    static let shared = BDTubeService()

    /// Last successfully fetched channel list (empty until first fetch).
    private(set) var lastChannels: [Channel] = []
    /// Session expiry (epoch) parsed from the last fetch, nil if URLs carry no
    /// `session=` timestamps or the value is unparseable.
    private(set) var lastSessionExpiry: Date? = nil
    /// When the list was last fetched successfully.
    private(set) var lastFetchDate: Date? = nil

    /// Coalesces concurrent refresh requests into one network call.
    private var inFlightRefresh: Task<[Channel], Never>? = nil

    private init() {}

    // MARK: - Fetch

    /// Fetches a fresh channel list. Returns the cached list on network failure
    /// (matches the widget's "keep playing on refresh failure" behavior).
    func refresh() async -> [Channel] {
        if let inFlight = inFlightRefresh {
            return await inFlight.value
        }
        let task = Task<[Channel], Never> { [weak self] in
            guard let self else { return [] }
            defer { self.inFlightRefresh = nil }

            var channels: [Channel] = []
            var lastError: String = ""

            for endpoint in [AppConfig.bdTubeAPIURL, AppConfig.bdTubeAPIURLAlt] {
                do {
                    let text = try await NetworkManager.shared.fetchText(from: endpoint, headers: [
                        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
                    ])
                    channels = Self.normalize(text)
                    if !channels.isEmpty { break }
                    lastError = "\(endpoint): empty list"
                } catch {
                    lastError = "\(endpoint): \(error.localizedDescription)"
                }
            }

            if channels.isEmpty {
                addonLog("[BDTube] refresh failed: \(lastError)")
                // Keep the previous list so playback/UI survive an outage.
                return self.lastChannels
            }

            self.lastChannels = channels
            self.lastFetchDate = Date()
            self.lastSessionExpiry = Self.sessionExpiry(from: channels)
            if let exp = self.lastSessionExpiry {
                addonLog("[BDTube] \(channels.count) channels, session expires \(exp)")
            } else {
                addonLog("[BDTube] \(channels.count) channels, no session expiry in URLs")
            }
            return channels
        }
        inFlightRefresh = task
        return await task.value
    }

    // MARK: - Normalization (port of Api.norm)

    /// Accepts either a raw JSON array or an object wrapping it
    /// (`{channels|data|items|list: [...]}`) and maps every entry with a
    /// usable stream URL into a `Channel`.
    static func normalize(_ text: String) -> [Channel] {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        var array: [[String: Any]] = []
        if let direct = root as? [[String: Any]] {
            array = direct
        } else if let obj = root as? [String: Any] {
            for key in ["channels", "data", "items", "list"] {
                if let nested = obj[key] as? [[String: Any]] {
                    array = nested
                    break
                }
            }
        }

        let blocked = Set(AppConfig.bdTubeBlockedChannels.map { Self.key($0) })
        var channels: [Channel] = []
        for (index, item) in array.enumerated() {
            let url = (item["url"] as? String)
                ?? (item["streamUrl"] as? String)
                ?? (item["stream_url"] as? String)
                ?? (item["stream"] as? String)
            guard let url, !url.isEmpty else { continue }

            let rawName = (item["name"] as? String) ?? (item["title"] as? String) ?? "Channel \(index + 1)"
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            // CFG.BLOCK parity: drop blocked channels (match by id or name).
            let itemId = (item["id"] as? String) ?? String(index)
            if blocked.contains(Self.key(itemId)) || blocked.contains(Self.key(name)) { continue }

            let logo = (item["logo"] as? String)
                ?? (item["logoUrl"] as? String)
                ?? (item["logo_url"] as? String)
                ?? (item["icon"] as? String)
                ?? ""
            let group = (item["category"] as? String) ?? (item["group"] as? String) ?? "BDTube"

            channels.append(Channel(
                name: name,
                url: url,
                logo: logo,
                group: group,
                sources: ["Default": url]
            ))
        }
        return channels
    }

    // MARK: - Session expiry (port of Tok.expiry)

    /// Widget regex: `session=[^&]*-(\d{10})-(\d{10})` — the first captured
    /// 10-digit group is the signed session's expiry epoch (seconds).
    /// Scans every channel URL and returns the latest valid expiry.
    static func sessionExpiry(from channels: [Channel]) -> Date? {
        guard let pattern = try? NSRegularExpression(pattern: #"session=[^&]*-(\d{10})-(\d{10})"#) else {
            return nil
        }
        var latest: TimeInterval? = nil
        for ch in channels {
            let range = NSRange(ch.url.startIndex..., in: ch.url)
            guard let m = pattern.firstMatch(in: ch.url, range: range),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: ch.url),
                  let epoch = TimeInterval(String(ch.url[r])) else {
                continue
            }
            if let current = latest {
                latest = max(current, epoch)
            } else {
                latest = epoch
            }
        }
        guard let epoch = latest else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    /// Ignores a wrong TV/phone clock: only trust the expiry when it is in the future.
    func validExpiry() -> Date? {
        guard let exp = lastSessionExpiry, exp > Date() else { return nil }
        return exp
    }

    /// Port of `Tok.delay`: min(2h, expiry − 30min) when expiry is < 4h away,
    /// floored at 60s. Falls back to the plain 2h interval.
    func nextRefreshDelay() -> TimeInterval {
        var delay = AppConfig.bdTubeRefreshInterval
        if let expiry = validExpiry() {
            let left = expiry.timeIntervalSinceNow
            if left > 0 && left < AppConfig.bdTubeMaxExpiryWindow {
                delay = min(delay, left - AppConfig.bdTubeRefreshBeforeExpiry)
            }
        }
        return max(delay, AppConfig.bdTubeMinRefreshDelay)
    }

    // MARK: - Matching helper (port of Api.key)

    /// Lowercase alphanumeric key used to match refreshed channels against
    /// existing ones so URL swaps never disturb playback ordering.
    static func key(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
