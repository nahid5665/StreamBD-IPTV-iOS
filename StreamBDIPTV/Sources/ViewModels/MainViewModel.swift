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
        // Start background token refresh on init
        Task {
            await TokenRefreshManager.shared.refreshAllTokens()
        }
    }

    /// Preloads essential playlists (AKASH GO, Toffee, FanCode, Cineplex)
    func loadInitialPlaylists() async {
        guard allChannels.isEmpty else { return }
        isLoading = true

        // Load AKASH GO as the default primary channels
        if let akash = playlists.first(where: { $0.name == "AKASH GO" }) {
            let channels = await loadChannels(for: akash)
            self.allChannels = channels
        }

        isLoading = false
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

    /// Fetches and parses playlist content with token injection
    static func fetchPlaylistChannels(playlist: EmbeddedPlaylist) async -> [Channel] {
        let urlStr = playlist.url

        if urlStr.hasPrefix("myiptv://proxy") {
            return await fetchMagicProxyChannels(proxyUrl: urlStr, defaultGroup: playlist.name)
        }

        guard let rawContent = try? await NetworkManager.shared.fetchText(from: urlStr) else {
            return []
        }

        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle JS Playlists
        if trimmed.hasPrefix("// JS PLAYLIST") || trimmed.hasPrefix("// BASE_URL=") || trimmed.contains("generatePlaylist()") || trimmed.contains("generatePlusBoxPlaylist()") {
            let m3u = await JSRunner.shared.executePlaylistScript(trimmed)
            return M3UParser.parsePlaylist(m3u, defaultGroup: playlist.name)
        }

        return M3UParser.parsePlaylist(trimmed, defaultGroup: playlist.name)
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
