import Foundation
import SwiftUI

@MainActor
final class MainViewModel: ObservableObject {
    @Published var playlists: [EmbeddedPlaylist] = AppConfig.bundledPlaylists
    @Published var selectedCategory: String = "All"
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var activeChannel: Channel? = nil
    @Published var activePlaylist: EmbeddedPlaylist? = nil

    // Cache of channels per playlist: playlist.name -> [Channel]
    @Published var playlistChannelsCache: [String: [Channel]] = [:]
    @Published var allChannels: [Channel] = []

    var playlistCategories: [String] {
        let set = Set(playlists.map { $0.category }).sorted()
        return ["All"] + set
    }

    var filteredPlaylists: [EmbeddedPlaylist] {
        playlists.filter { pl in
            let matchesCategory = (selectedCategory == "All") || pl.category.localizedCaseInsensitiveCompare(selectedCategory) == .orderedSame
            let matchesSearch = searchQuery.isEmpty ||
                pl.name.localizedCaseInsensitiveContains(searchQuery) ||
                pl.category.localizedCaseInsensitiveContains(searchQuery)
            return matchesCategory && matchesSearch
        }
    }

    var filteredGlobalChannels: [Channel] {
        guard !searchQuery.isEmpty else { return [] }
        return allChannels.filter { ch in
            ch.name.localizedCaseInsensitiveContains(searchQuery) ||
            ch.group.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    init() {
        // Live channel refresh hook: TokenRefreshManager refreshes the BDTube
        // server list on its schedule and hands the fresh list back here so
        // cached URLs are swapped without touching active playback.
        TokenRefreshManager.shared.liveChannelRefresher = { [weak self] freshChannels in
            self?.applyRefreshedLiveChannels(freshChannels)
        }
        Task {
            await TokenRefreshManager.shared.refreshAllTokens()
        }
    }

    /// Preloads the live TV server (BDTube Live)
    func loadInitialPlaylists() async {
        guard allChannels.isEmpty else { return }
        isLoading = true

        if let bd = playlists.first(where: { $0.name == "BDTube Live" }) {
            let channels = await loadChannels(for: bd)
            if !channels.isEmpty {
                self.allChannels = channels
            }
        }

        isLoading = false
    }

    /// Swaps refreshed BDTube URLs into the cache/allChannels by normalized
    /// name (the widget matched by server id; the name is our stable key since
    /// Channel.id embeds the URL, which changes on every signed refresh).
    /// Open players keep streaming their old URL until it dies — the next
    /// tap/retry picks up the fresh token, exactly like the Samsung widget.
    private func applyRefreshedLiveChannels(_ fresh: [Channel]) {
        guard !fresh.isEmpty else { return }

        // Preserve logo when the API omits it on refresh
        var updated = fresh
        if let cached = playlistChannelsCache["BDTube Live"] {
            let oldByName = Dictionary(cached.map { (BDTubeService.key($0.name), $0) },
                                       uniquingKeysWith: { a, _ in a })
            updated = fresh.map { ch in
                guard let old = oldByName[BDTubeService.key(ch.name)], ch.logo.isEmpty else { return ch }
                return Channel(
                    name: ch.name,
                    url: ch.url,
                    logo: old.logo,
                    group: ch.group,
                    sources: ["Default": ch.url]
                )
            }
        }
        playlistChannelsCache["BDTube Live"] = updated

        // Mirror the swap into allChannels (search + global grid): replace
        // refreshed URLs in place, keep unrelated channels, append new ones.
        var freshByName = Dictionary(updated.map { (BDTubeService.key($0.name), $0) },
                                     uniquingKeysWith: { a, _ in a })
        var result: [Channel] = []
        result.reserveCapacity(allChannels.count + freshByName.count)
        for ch in allChannels {
            if let freshCh = freshByName.removeValue(forKey: BDTubeService.key(ch.name)) {
                result.append(freshCh)
            } else {
                result.append(ch)
            }
        }
        for (_, ch) in freshByName.sorted(by: { $0.key < $1.key }) {
            result.append(ch)
        }
        allChannels = result
    }

    /// Loads channels for a specific playlist (from cache or network)
    func loadChannels(for playlist: EmbeddedPlaylist) async -> [Channel] {
        if let cached = playlistChannelsCache[playlist.name], !cached.isEmpty {
            return cached
        }

        let channels = await Self.fetchPlaylistChannels(playlist: playlist)
        playlistChannelsCache[playlist.name] = channels

        // Append to allChannels for search
        for ch in channels {
            if !allChannels.contains(where: { $0.name == ch.name }) {
                allChannels.append(ch)
            }
        }
        return channels
    }

    /// Fetches and parses playlist content with token injection and JSON/M3U auto-detection
    static func fetchPlaylistChannels(playlist: EmbeddedPlaylist) async -> [Channel] {
        let urlStr = playlist.url

        // BDTube live server: dedicated service (fetch + normalize + block list)
        if urlStr.hasPrefix("bdtube://") {
            return await BDTubeService.shared.refresh()
        }

        if urlStr.hasPrefix("myiptv://proxy") {
            return await fetchMagicProxyChannels(proxyUrl: urlStr, defaultGroup: playlist.name)
        }

        guard let rawContent = try? await NetworkManager.shared.fetchText(from: urlStr) else {
            return []
        }

        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Detect JSON-based channel arrays (StreamBD IPTV Official 170 channels API)
        if trimmed.hasPrefix("[") && (trimmed.contains("\"sources\"") || trimmed.contains("\"stream_url\"") || trimmed.contains("\"channel_no\"")) {
            return parseJsonChannels(trimmed, defaultGroup: playlist.name)
        }

        // 2. Handle JS Playlists
        if trimmed.hasPrefix("// JS PLAYLIST") || trimmed.hasPrefix("// BASE_URL=") || trimmed.contains("generatePlaylist()") || trimmed.contains("generatePlusBoxPlaylist()") {
            let m3u = await JSRunner.shared.executePlaylistScript(trimmed)
            return M3UParser.parsePlaylist(m3u, defaultGroup: playlist.name)
        }

        // 3. Handle standard M3U / M3U8 playlists
        return M3UParser.parsePlaylist(trimmed, defaultGroup: playlist.name)
    }

    /// Parses StreamBD JSON channel arrays with multi-server sources
    static func parseJsonChannels(_ jsonStr: String, defaultGroup: String) -> [Channel] {
        guard let data = jsonStr.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var channels: [Channel] = []
        for item in arr {
            let name = (item["name"] as? String) ?? (item["title"] as? String) ?? "Channel"
            let group = (item["group-title"] as? String) ?? (item["category"] as? String) ?? defaultGroup
            let logo = (item["tvg-logo"] as? String) ?? (item["logo"] as? String) ?? ""
            var sources: [String: String] = [:]
            if let s = item["sources"] as? [String: String] {
                sources = s
            }
            let directUrl = (item["stream_url"] as? String) ?? (item["url"] as? String) ?? (item["link"] as? String) ?? sources.values.first ?? ""
            if !directUrl.isEmpty {
                if sources.isEmpty {
                    sources["Default"] = directUrl
                }
                channels.append(Channel(
                    name: name,
                    url: directUrl,
                    logo: logo,
                    group: group,
                    sources: sources
                ))
            }
        }
        return channels
    }

    static func fetchMagicProxyChannels(proxyUrl: String, defaultGroup: String) async -> [Channel] {
        guard let components = URLComponents(string: proxyUrl) else { return [] }
        let params = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard let targetUrl = params["url"], !targetUrl.isEmpty else { return [] }

        let arrayPath = params["array_path"] ?? ""
        let streamField = params["stream_field"] ?? "stream_name"
        let titleField = params["title_field"] ?? "title"
        let logoField = params["logo_field"] ?? "logo"
        let categoryField = params["category_field"] ?? "category"
        let prefix = params["prefix"] ?? ""
        let suffix = params["suffix"] ?? ""

        var customHeaders: [String: String] = [:]
        if let rawHeaders = params["headers"], !rawHeaders.isEmpty {
            for line in rawHeaders.components(separatedBy: .newlines) {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    customHeaders[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                        String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            }
        }

        guard let text = try? await NetworkManager.shared.fetchText(from: targetUrl, headers: customHeaders),
              let data = text.data(using: .utf8),
              let rootObj = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        var current: Any = rootObj
        if !arrayPath.isEmpty {
            for segment in arrayPath.components(separatedBy: ".") {
                if let dict = current as? [String: Any], let next = dict[segment] {
                    current = next
                }
            }
        }

        guard let array = current as? [[String: Any]] else { return [] }
        var result: [Channel] = []

        for item in array {
            guard let rawStream = item[streamField] as? String, !rawStream.isEmpty else { continue }
            let name = (item[titleField] as? String) ?? "Channel"
            let logo = (item[logoField] as? String) ?? ""
            let group = (item[categoryField] as? String) ?? defaultGroup
            let streamUrl = "\(prefix)\(rawStream)\(suffix)"

            result.append(Channel(
                name: name,
                url: streamUrl,
                logo: logo,
                group: group,
                httpHeaders: customHeaders,
                sources: ["Default": streamUrl]
            ))
        }
        return result
    }
}
