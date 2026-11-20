import Foundation

/// Unified Addon Resolver Service
/// Executes all configured VOD Addons concurrently with timeout isolation,
/// supporting BDIX FTP servers, Emby/Jellyfin (with full Series->Season->Episode lookup),
/// Stremio-protocol HTTP addons, and verified web stream providers.
final class AddonResolverService {
    static let shared = AddonResolverService()

    private let defaultUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private let androidUA = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Mobile Safari/537.36"

    private init() {}

    /// Executes a single addon with strict timeout isolation
    func resolve(addon: Addon, context: MediaLookupContext) async throws -> [StreamSource] {
        let streams = try await withTimeout(seconds: 45.0) {
            let lowerName = addon.name.lowercased()
            let lowerId = addon.id.lowercased()
            let url = addon.url.lowercased()

            // 1. RoarZone EMBY Server (Series -> Season -> Episode resolution)
            if lowerId.contains("roarzone") || lowerName.contains("roarzone") || url.contains("roarzone") {
                return await self.resolveRoarZoneEmby(context: context)
            }

            // 2. Stremio-Protocol HTTP Addons
            if url.contains("stremio") || url.hasSuffix("/manifest.json") || url.contains("/stream/") || addon.type == "stremio" {
                return await self.resolveStremioProtocol(addon: addon, context: context)
            }

            // 3. Cineplex BD [BDIX] - Fast Native Resolver with 2-Step View->Player Session & Sanitized Search
            if lowerId.contains("cineplex") || lowerName.contains("cineplex") {
                let nativeStreams = await CineplexScraper.shared.resolveStreams(
                    title: context.title,
                    isTV: context.isTV,
                    season: context.season ?? 1,
                    episode: context.episode ?? 1
                )
                if !nativeStreams.isEmpty {
                    return nativeStreams
                }
                // Fallback to JS runner if native returned empty
                if url.hasSuffix(".js") || addon.url.hasSuffix(".js") {
                    return (try? await JSVODAddonRunner.shared.resolveStreams(addon: addon, context: context)) ?? []
                }
                return []
            }

            // 4. Dynamic JavaScript VOD Plugins (*.js)
            if url.hasSuffix(".js") || addon.url.hasSuffix(".js") {
                let jsStreams = (try? await JSVODAddonRunner.shared.resolveStreams(addon: addon, context: context)) ?? []
                if !jsStreams.isEmpty {
                    return jsStreams
                }
            }

            // CTG Movies FTP [BDIX]
            if lowerId.contains("ctg") || lowerName.contains("ctg") || url.contains("ctgmovies") {
                return await self.resolveCtgMovies(context: context)
            }

            // VixSrc HD
            if lowerId.contains("vixsrc") || lowerName.contains("vixsrc") || url.contains("vixsrc") {
                return await self.resolveVixSrc(context: context)
            }

            // 5. Generic Addon Fallback
            return await self.resolveGenericAddon(addon: addon, context: context)
        }
        if AppConfig.debugAddonLogging {
            addonLog("[AddonResolver] \(addon.name) -> \(streams.count) streams")
        }
        return streams
    }

    // MARK: - 1. RoarZone EMBY Resolver (PlaybackInfo API + Direct / HLS Streams)

    private func resolveEmbyPlaybackURL(
        baseUrl: String,
        itemId: String,
        userId: String?,
        token: String
    ) async -> (directUrl: String, hlsUrl: String?) {
        var query = "api_key=\(token)"
        if let userId, !userId.isEmpty {
            query = "UserId=\(userId)&\(query)"
        }

        if let infoUrl = URL(string: "\(baseUrl)/Items/\(itemId)/PlaybackInfo?\(query)") {
            var req = URLRequest(url: infoUrl)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(token, forHTTPHeaderField: "X-Emby-Token")
            req.setValue(defaultUA, forHTTPHeaderField: "User-Agent")
            req.httpBody = "{}".data(using: .utf8)
            req.timeoutInterval = 5

            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sources = json["MediaSources"] as? [[String: Any]],
               let first = sources.first {

                let mediaSourceId = (first["Id"] as? String) ?? itemId
                let rawContainer = (first["Container"] as? String) ?? "mp4"
                let container = rawContainer.split(separator: ",").first.map(String.init) ?? "mp4"

                let directUrl: String
                if let path = first["DirectStreamUrl"] as? String, !path.isEmpty {
                    let full = path.hasPrefix("http") ? path : "\(baseUrl)\(path)"
                    directUrl = full.contains("api_key=") ? full : "\(full)\(full.contains("?") ? "&" : "?")api_key=\(token)"
                } else {
                    directUrl = "\(baseUrl)/Videos/\(itemId)/stream.\(container)?Static=true&mediaSourceId=\(mediaSourceId)&api_key=\(token)"
                }

                let hlsUrl: String? = (first["TranscodingUrl"] as? String).map { path in
                    let full = path.hasPrefix("http") ? path : "\(baseUrl)\(path)"
                    return full.contains("api_key=") ? full : "\(full)\(full.contains("?") ? "&" : "?")api_key=\(token)"
                }

                return (directUrl, hlsUrl)
            }
        }

        // Fallback without MediaSourceId guess
        return ("\(baseUrl)/Videos/\(itemId)/stream?Static=true&api_key=\(token)", nil)
    }

    private func resolveRoarZoneEmby(context: MediaLookupContext) async -> [StreamSource] {
        guard let authUrl = URL(string: "https://play.roarzone.net/Users/authenticatebyname") else { return [] }

        var authReq = URLRequest(url: authUrl)
        authReq.httpMethod = "POST"
        authReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authReq.setValue("MediaBrowser Client=\"iOS\", Device=\"iPhone\", DeviceId=\"Eentertainment-iOS\", Version=\"1.0.0\"", forHTTPHeaderField: "X-Emby-Authorization")
        authReq.setValue(defaultUA, forHTTPHeaderField: "User-Agent")
        authReq.httpBody = "{\"Username\":\"RoarZone_Guest\",\"Pw\":\"\"}".data(using: .utf8)
        authReq.timeoutInterval = 5

        guard let (authData, authResp) = try? await URLSession.shared.data(for: authReq),
              (authResp as? HTTPURLResponse)?.statusCode == 200,
              let authJson = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let token = authJson["AccessToken"] as? String else {
            return []
        }

        let userObj = authJson["User"] as? [String: Any]
        let userId = userObj?["Id"] as? String

        let cleanTitle = context.title.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        if context.isTV {
            // TV Series: Search Series -> Get Season Episodes -> Match IndexNumber
            let seriesSearchUrl = "https://play.roarzone.net/Items?searchTerm=\(encodedTitle)&Recursive=true&IncludeItemTypes=Series&api_key=\(token)"
            guard let sUrl = URL(string: seriesSearchUrl) else { return [] }

            var sReq = URLRequest(url: sUrl)
            sReq.setValue(defaultUA, forHTTPHeaderField: "User-Agent")
            sReq.timeoutInterval = 5

            guard let (sData, sResp) = try? await URLSession.shared.data(for: sReq),
                  (sResp as? HTTPURLResponse)?.statusCode == 200,
                  let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
                  let seriesItems = sJson["Items"] as? [[String: Any]], !seriesItems.isEmpty,
                  let seriesId = seriesItems[0]["Id"] as? String ?? (seriesItems[0]["Id"] as? Int).map(String.init) else {
                return []
            }

            let seasonNum = context.season ?? 1
            let epNum = context.episode ?? 1
            let epUrlStr = "https://play.roarzone.net/Shows/\(seriesId)/Episodes?Season=\(seasonNum)&api_key=\(token)"
            guard let epUrl = URL(string: epUrlStr) else { return [] }

            var epReq = URLRequest(url: epUrl)
            epReq.setValue(defaultUA, forHTTPHeaderField: "User-Agent")
            epReq.timeoutInterval = 5

            guard let (epData, epResp) = try? await URLSession.shared.data(for: epReq),
                  (epResp as? HTTPURLResponse)?.statusCode == 200,
                  let epJson = try? JSONSerialization.jsonObject(with: epData) as? [String: Any],
                  let epItems = epJson["Items"] as? [[String: Any]], !epItems.isEmpty else {
                return []
            }

            // Find episode matching episode index
            let targetEpisode = epItems.first { item in
                if let idx = item["IndexNumber"] as? Int { return idx == epNum }
                return false
            } ?? epItems.first

            guard let matchedEp = targetEpisode,
                  let epId = matchedEp["Id"] as? String ?? (matchedEp["Id"] as? Int).map(String.init) else {
                return []
            }

            let epName = matchedEp["Name"] as? String ?? "Episode \(epNum)"
            let (directUrl, hlsUrl) = await resolveEmbyPlaybackURL(
                baseUrl: "https://play.roarzone.net",
                itemId: epId,
                userId: userId,
                token: token
            )

            var streams: [StreamSource] = []
            if let hls = hlsUrl {
                streams.append(StreamSource(
                    url: hls,
                    quality: "HD 1080P",
                    provider: "RoarZone [EMBY] (S\(seasonNum)E\(epNum): \(epName))",
                    type: "direct",
                    headers: [
                        "User-Agent": defaultUA,
                        "Referer": "https://play.roarzone.net/web/index.html",
                        "Origin": "https://play.roarzone.net"
                    ]
                ))
            }
            streams.append(StreamSource(
                url: directUrl,
                quality: "Direct Stream",
                provider: "RoarZone [EMBY Direct] (S\(seasonNum)E\(epNum): \(epName))",
                type: "direct",
                headers: [
                    "User-Agent": defaultUA,
                    "Referer": "https://play.roarzone.net/web/index.html",
                    "Origin": "https://play.roarzone.net"
                ]
            ))
            return streams
        } else {
            // Movie Lookup
            let movieSearchUrl = "https://play.roarzone.net/Items?searchTerm=\(encodedTitle)&Recursive=true&IncludeItemTypes=Movie&api_key=\(token)"
            guard let mUrl = URL(string: movieSearchUrl) else { return [] }

            var mReq = URLRequest(url: mUrl)
            mReq.setValue(defaultUA, forHTTPHeaderField: "User-Agent")
            mReq.timeoutInterval = 5

            guard let (mData, mResp) = try? await URLSession.shared.data(for: mReq),
                  (mResp as? HTTPURLResponse)?.statusCode == 200,
                  let mJson = try? JSONSerialization.jsonObject(with: mData) as? [String: Any],
                  let items = mJson["Items"] as? [[String: Any]], !items.isEmpty else {
                return []
            }

            var streams: [StreamSource] = []
            for item in items.prefix(2) {
                guard let itemId = item["Id"] as? String ?? (item["Id"] as? Int).map(String.init) else { continue }
                let name = item["Name"] as? String ?? context.title
                let (directUrl, hlsUrl) = await resolveEmbyPlaybackURL(
                    baseUrl: "https://play.roarzone.net",
                    itemId: itemId,
                    userId: userId,
                    token: token
                )

                if let hls = hlsUrl {
                    streams.append(StreamSource(
                        url: hls,
                        quality: "HD 1080P",
                        provider: "RoarZone [EMBY] (\(name))",
                        type: "direct",
                        headers: [
                            "User-Agent": defaultUA,
                            "Referer": "https://play.roarzone.net/web/index.html",
                            "Origin": "https://play.roarzone.net"
                        ]
                    ))
                }
                streams.append(StreamSource(
                    url: directUrl,
                    quality: "Direct Stream",
                    provider: "RoarZone [EMBY Direct] (\(name))",
                    type: "direct",
                    headers: [
                        "User-Agent": defaultUA,
                        "Referer": "https://play.roarzone.net/web/index.html",
                        "Origin": "https://play.roarzone.net"
                    ]
                ))
            }
            return streams
        }
    }

    // MARK: - 2. CTG Movies BDIX FTP Resolver (Direct MP4 Links)

    private func resolveCtgMovies(context: MediaLookupContext) async -> [StreamSource] {
        guard let loginUrl = URL(string: "https://cockpit.ctgmovies.com/api/v1/auth/login") else { return [] }

        var loginReq = URLRequest(url: loginUrl)
        loginReq.httpMethod = "POST"
        loginReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        loginReq.setValue(androidUA, forHTTPHeaderField: "User-Agent")
        loginReq.setValue("https://ctgmovies.com", forHTTPHeaderField: "Origin")
        loginReq.setValue("https://ctgmovies.com/", forHTTPHeaderField: "Referer")
        loginReq.httpBody = "{\"email\":\"gobop98171@joystill.com\",\"password\":\"Joy1971\"}".data(using: .utf8)
        loginReq.timeoutInterval = 5

        guard let (loginData, loginResp) = try? await URLSession.shared.data(for: loginReq),
              (loginResp as? HTTPURLResponse)?.statusCode == 200,
              let loginJson = try? JSONSerialization.jsonObject(with: loginData) as? [String: Any],
              let token = loginJson["token"] as? String else {
            return []
        }

        guard let encodedTitle = context.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "https://cockpit.ctgmovies.com/api/v1/movies?search=\(encodedTitle)&limit=10") else {
            return []
        }

        var searchReq = URLRequest(url: searchUrl)
        searchReq.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        searchReq.setValue(token, forHTTPHeaderField: "x-auth-token")
        searchReq.setValue(androidUA, forHTTPHeaderField: "User-Agent")
        searchReq.timeoutInterval = 5

        guard let (searchData, searchResp) = try? await URLSession.shared.data(for: searchReq),
              (searchResp as? HTTPURLResponse)?.statusCode == 200,
              let searchJson = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let items = searchJson["movies"] as? [[String: Any]], !items.isEmpty,
              let mid = items[0]["id"] as? String ?? (items[0]["_id"] as? String) else {
            return []
        }

        // Fetch detail with direct links
        guard let detailUrl = URL(string: "https://cockpit.ctgmovies.com/api/v1/movies/\(mid)") else { return [] }

        var detailReq = URLRequest(url: detailUrl)
        detailReq.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        detailReq.setValue(token, forHTTPHeaderField: "x-auth-token")
        detailReq.setValue(androidUA, forHTTPHeaderField: "User-Agent")
        detailReq.timeoutInterval = 5

        guard let (detailData, detailResp) = try? await URLSession.shared.data(for: detailReq),
              (detailResp as? HTTPURLResponse)?.statusCode == 200,
              let detailJson = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any] else {
            return []
        }

        let movieObj = (detailJson["movie"] as? [String: Any]) ?? detailJson
        guard let links = movieObj["links"] as? [[String: Any]], !links.isEmpty else { return [] }

        var streams: [StreamSource] = []
        for l in links.prefix(3) {
            guard let rawUrl = l["url"] as? String, !rawUrl.isEmpty else { continue }
            let quality = l["quality"] as? String ?? "1080P Full HD"
            let serverName = l["source_display"] as? String ?? "Server"

            streams.append(StreamSource(
                url: rawUrl,
                quality: quality,
                provider: "CTG Movies FTP [BDIX] (\(serverName))",
                type: "direct",
                headers: [
                    "User-Agent": defaultUA,
                    "Referer": "https://ctgmovies.com/"
                ]
            ))
        }

        return streams
    }

    // MARK: - 3. VixSrc HD Stream Resolver

    private func resolveVixSrc(context: MediaLookupContext) async -> [StreamSource] {
        let path = context.isTV
            ? "api/tv/\(context.tmdbId)/\(context.season ?? 1)/\(context.episode ?? 1)"
            : "api/movie/\(context.tmdbId)"
        guard let url = URL(string: "https://vixsrc.to/\(path)") else { return [] }

        var req = URLRequest(url: url)
        req.setValue(defaultUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 5

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let src = json["src"] as? String, !src.isEmpty else {
            return []
        }

        let fullEmbedUrl = src.hasPrefix("http") ? src : "https://vixsrc.to\(src)"
        return [
            StreamSource(
                url: fullEmbedUrl,
                quality: "1080P Full HD",
                provider: "VixSrc HD (Multi-Server)",
                type: "embed",
                headers: [
                    "User-Agent": defaultUA,
                    "Referer": "https://vixsrc.to/"
                ]
            )
        ]
    }

    // MARK: - 4. Stremio HTTP Addon Protocol Resolver

    private func resolveStremioProtocol(addon: Addon, context: MediaLookupContext) async -> [StreamSource] {
        guard let imdbId = context.imdbId, !imdbId.isEmpty else { return [] }

        var baseUrl = addon.url.replacingOccurrences(of: "/manifest.json", with: "")
        if baseUrl.hasSuffix("/") { baseUrl.removeLast() }

        let streamEndpoint = context.isTV
            ? "\(baseUrl)/stream/series/\(imdbId):\(context.season ?? 1):\(context.episode ?? 1).json"
            : "\(baseUrl)/stream/movie/\(imdbId).json"

        guard let url = URL(string: streamEndpoint) else { return [] }

        var req = URLRequest(url: url)
        req.setValue(defaultUA, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 6

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]] else {
            return []
        }

        var results: [StreamSource] = []
        for s in streams.prefix(4) {
            guard let streamUrl = s["url"] as? String, streamUrl.hasPrefix("http") else { continue }
            let name = s["name"] as? String ?? addon.name
            let title = s["title"] as? String ?? "Stream"
            let quality = title.contains("1080") ? "1080P" : (title.contains("4k") || title.contains("2160") ? "4K" : (title.contains("720") ? "720P" : "HD"))

            var customHeaders: [String: String] = [:]
            if let hints = s["behaviorHints"] as? [String: Any],
               let proxyHeaders = hints["proxyHeaders"] as? [String: Any],
               let requestHeaders = proxyHeaders["request"] as? [String: String] {
                customHeaders = requestHeaders
            }

            results.append(StreamSource(
                url: streamUrl,
                quality: quality,
                provider: "\(name) (\(title))",
                type: "direct",
                headers: customHeaders.isEmpty ? ["User-Agent": defaultUA] : customHeaders
            ))
        }

        return results
    }

    // MARK: - 5. Generic Addon Endpoint Fallback

    private func resolveGenericAddon(addon: Addon, context: MediaLookupContext) async -> [StreamSource] {
        if addon.url.lowercased().hasSuffix(".js") {
            return (try? await JSVODAddonRunner.shared.resolveStreams(addon: addon, context: context)) ?? []
        }
        return []
    }

    // MARK: - Timeout Isolation Helper

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
