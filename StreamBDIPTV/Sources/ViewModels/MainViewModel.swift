import Foundation
import SwiftUI

@MainActor
final class MainViewModel: ObservableObject {
    @Published var categories: [LiveCategory] = []
    @Published var allChannels: [Channel] = []
    @Published var selectedCategory: String = "All"
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var activeChannel: Channel? = nil

    var filteredChannels: [Channel] {
        allChannels.filter { ch in
            let matchesGroup = (selectedCategory == "All") || ch.group.localizedCaseInsensitiveCompare(selectedCategory) == .orderedSame
            let matchesSearch = searchQuery.isEmpty ||
                ch.name.localizedCaseInsensitiveContains(searchQuery) ||
                ch.group.localizedCaseInsensitiveContains(searchQuery)
            return matchesGroup && matchesSearch
        }
    }

    var availableGroups: [String] {
        let groups = Set(allChannels.map { $0.group }).sorted()
        return ["All"] + groups
    }

    func loadAllLiveChannels() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        var combined: [Channel] = []

        // 1. Fetch remote categories from decrypted RemoteConfig IPTV.json
        // The API returns either `{"playlists":{...}}` or `[{"playlists":{...}}]`
        do {
            let rawText = try await NetworkManager.shared.fetchText(from: AppConfig.iptvPlaylistURL)
            guard let jsonData = rawText.data(using: .utf8) else { throw URLError(.cannotDecodeContentData) }

            let decoder = JSONDecoder()
            var playlistsDict: [String: PlaylistInfo] = [:]

            // Try decoding as a single LiveCategoryResponse first
            if let single = try? decoder.decode(LiveCategoryResponse.self, from: jsonData) {
                playlistsDict = single.playlists
            }
            // Then try as an array of LiveCategoryResponse (actual API format)
            else if let arr = try? decoder.decode([LiveCategoryResponse].self, from: jsonData),
                    let first = arr.first {
                playlistsDict = first.playlists
            }
            // Fallback: try as raw JSON and extract manually
            else if let rawJson = try? JSONSerialization.jsonObject(with: jsonData) {
                var rootObj: [String: Any]? = nil
                if let dict = rawJson as? [String: Any] {
                    rootObj = dict
                } else if let arr = rawJson as? [[String: Any]], let first = arr.first {
                    rootObj = first
                }
                if let pls = rootObj?["playlists"] as? [String: [String: Any]] {
                    for (name, info) in pls {
                        if let url = info["url"] as? String {
                            let logo = info["logo"] as? String
                            playlistsDict[name] = PlaylistInfo(url: url, logo: logo)
                        }
                    }
                }
            }

            var fetchedCategories: [LiveCategory] = []
            for (catName, info) in playlistsDict.sorted(by: { $0.key < $1.key }) {
                let logoUrl = M3UParser.normalizeLogo(info.logo ?? "")
                fetchedCategories.append(LiveCategory(name: catName, url: info.url, logo: logoUrl))
            }
            self.categories = fetchedCategories

            // Fetch channels from each remote playlist concurrently
            await withTaskGroup(of: [Channel].self) { group in
                for cat in fetchedCategories {
                    group.addTask {
                        await Self.fetchCategoryChannels(category: cat)
                    }
                }
                for await catChannels in group {
                    combined.append(contentsOf: catChannels)
                }
            }
        } catch {
            self.errorMessage = "Remote catalog note: \(error.localizedDescription)"
        }

        // 2. Also execute bundled JS Playlists (Server 1 Jio, Server 2 Jio, PlusBox)
        for bundledJs in ["server1_jio", "server2_jio", "plusbox"] {
            if let path = Bundle.main.path(forResource: bundledJs, ofType: "js"),
               let script = try? String(contentsOfFile: path, encoding: .utf8) {
                let m3u = await JSRunner.shared.executePlaylistScript(script)
                if !m3u.isEmpty {
                    let parsed = M3UParser.parsePlaylist(m3u, defaultGroup: bundledJs.uppercased())
                    combined.append(contentsOf: parsed)
                }
            }
        }

        // 3. Merge metadata/logos from bundled assets/channels.json
        let bundledLogoMap = Self.loadBundledLogoMap()
        for idx in combined.indices {
            if combined[idx].logo.isEmpty,
               let mappedLogo = bundledLogoMap[combined[idx].name.lowercased()] {
                combined[idx].logo = mappedLogo
            }
        }

        // Deduplicate by name + url while preserving multi-source entries
        var seen: [String: Int] = [:]
        var deduped: [Channel] = []
        for ch in combined {
            let key = ch.name.lowercased().trimmingCharacters(in: .whitespaces)
            if let existingIdx = seen[key] {
                let sourceLabel = "Server \(deduped[existingIdx].sources.count + 1)"
                deduped[existingIdx].sources[sourceLabel] = ch.sources.values.first ?? ch.url
            } else {
                seen[key] = deduped.count
                deduped.append(ch)
            }
        }

        self.allChannels = deduped
        self.isLoading = false
    }

    static func fetchCategoryChannels(category: LiveCategory) async -> [Channel] {
        let urlStr = category.url
        if urlStr.hasPrefix("myiptv://proxy") {
            return await fetchMagicProxyChannels(proxyUrl: urlStr, defaultGroup: category.name)
        }
        guard let rawContent = try? await NetworkManager.shared.fetchText(from: urlStr) else {
            return []
        }
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("// JS PLAYLIST") || trimmed.hasPrefix("// BASE_URL=") || trimmed.contains("generatePlaylist()") {
            let m3u = await JSRunner.shared.executePlaylistScript(trimmed)
            return M3UParser.parsePlaylist(m3u, defaultGroup: category.name)
        }
        return M3UParser.parsePlaylist(trimmed, defaultGroup: category.name)
    }

    /// Mirrors `Lm6/a` (`myiptv://proxy?url=...&array_path=...&stream_field=...&title_field=...`)
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
            for seg in arrayPath.split(separator: ".") {
                if let dict = current as? [String: Any], let next = dict[String(seg)] {
                    current = next
                }
            }
        }
        guard let arr = current as? [[String: Any]] else { return [] }

        var channels: [Channel] = []
        for item in arr {
            guard let rawStream = item[streamField] as? String, !rawStream.isEmpty else { continue }
            let title = (item[titleField] as? String) ?? "Channel"
            let logo = M3UParser.normalizeLogo((item[logoField] as? String) ?? "")
            let group = (item[categoryField] as? String) ?? defaultGroup
            let fullLine = "\(prefix)\(rawStream)\(suffix)"
            let parsed = M3UParser.parseUrlHeaders(fullLine)
            channels.append(Channel(
                name: title,
                url: parsed.cleanUrl,
                logo: logo,
                group: group,
                userAgent: parsed.headers["User-Agent"],
                cookie: parsed.headers["Cookie"],
                httpReferer: parsed.headers["Referer"],
                origin: parsed.headers["Origin"],
                httpHeaders: parsed.headers,
                tokenUrl: parsed.tokenUrl,
                sources: ["Default": fullLine]
            ))
        }
        return channels
    }

    static func loadBundledLogoMap() -> [String: String] {
        guard let path = Bundle.main.path(forResource: "channels", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let items = try? JSONDecoder().decode([BundledChannelItem].self, from: data) else {
            return [:]
        }
        var map: [String: String] = [:]
        for item in items {
            let logo = M3UParser.normalizeLogo(item.tvgLogo ?? item.image ?? "")
            if !logo.isEmpty {
                map[item.name.lowercased()] = logo
            }
        }
        return map
    }
}
