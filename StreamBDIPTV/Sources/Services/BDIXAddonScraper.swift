import Foundation

final class BDIXAddonScraper {
    static let shared = BDIXAddonScraper()

    private let defaultUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private let androidUA = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Mobile Safari/537.36"

    private init() {}

    /// Resolves streams across all verified StreamBD Addon providers.
    /// ONLY returns addons that actually possess the title. No fake static fallbacks!
    func resolveAllAddons(title: String, year: String, isTV: Bool, season: Int, episode: Int, tmdbId: Int) async -> [StreamSource] {
        var results: [StreamSource] = []

        // Run authentic scrapers in parallel with async let
        async let cineplexTask = CineplexScraper.shared.resolveStreams(
            title: title,
            isTV: isTV,
            season: season,
            episode: episode
        )
        async let ctgTask = resolveCtgMovies(title: title, tmdbId: tmdbId, isTV: isTV, season: season, episode: episode)
        async let roarTask = resolveRoarZone(title: title, isTV: isTV)
        async let vixTask = resolveVixSrc(tmdbId: tmdbId, isTV: isTV, season: season, episode: episode)
        async let mlbdTask = MovieLinkBDScraper.shared.resolveStreams(title: title, year: year, isTV: isTV, season: season, episode: episode, tmdbId: tmdbId)

        let cineplexStreams = await cineplexTask
        let ctgStreams = await ctgTask
        let roarStreams = await roarTask
        let vixStreams = await vixTask
        let mlbdStreams = await mlbdTask

        results.append(contentsOf: cineplexStreams)
        results.append(contentsOf: ctgStreams)
        results.append(contentsOf: roarStreams)
        results.append(contentsOf: vixStreams)
        results.append(contentsOf: mlbdStreams)

        return results
    }

    // MARK: - 1. CTG Movies BDIX FTP Scraper (Cockpit API v1 with Direct MP4 Links)
    private func resolveCtgMovies(title: String, tmdbId: Int, isTV: Bool, season: Int, episode: Int) async -> [StreamSource] {
        let loginUrlStr = "https://cockpit.ctgmovies.com/api/v1/auth/login"
        guard let loginUrl = URL(string: loginUrlStr) else { return [] }

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

        // Search title
        let path = isTV ? "series" : "movies"
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "https://cockpit.ctgmovies.com/api/v1/\(path)?search=\(encodedTitle)&limit=10") else {
            return []
        }

        var searchReq = URLRequest(url: searchUrl)
        searchReq.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        searchReq.setValue(token, forHTTPHeaderField: "x-auth-token")
        searchReq.setValue(androidUA, forHTTPHeaderField: "User-Agent")
        searchReq.timeoutInterval = 5

        guard let (searchData, searchResp) = try? await URLSession.shared.data(for: searchReq),
              (searchResp as? HTTPURLResponse)?.statusCode == 200,
              let searchJson = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any] else {
            return []
        }

        let items = (searchJson["movies"] as? [[String: Any]]) ??
                    (searchJson["series"] as? [[String: Any]]) ??
                    (searchJson["data"] as? [[String: Any]]) ?? []

        guard let matchedItem = items.first else { return [] }
        guard let mid = matchedItem["id"] as? String ?? (matchedItem["_id"] as? String) else { return [] }
        let displayTitle = matchedItem["title"] as? String ?? title

        // Fetch Detail to get direct MP4 download links
        let detailUrlStr = isTV
            ? "https://cockpit.ctgmovies.com/api/v1/series/\(mid)"
            : "https://cockpit.ctgmovies.com/api/v1/movies/\(mid)"
        guard let detailUrl = URL(string: detailUrlStr) else { return [] }

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

        let movieObj = (detailJson["movie"] as? [String: Any]) ?? (detailJson["series"] as? [String: Any]) ?? detailJson
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

    // MARK: - 2. RoarZone EMBY Server Scraper (Public Authentication + HLS Master Playlist)
    private func resolveRoarZone(title: String, isTV: Bool) async -> [StreamSource] {
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

        let itemType = isTV ? "Series" : "Movie"
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "https://play.roarzone.net/Items?searchTerm=\(encodedTitle)&Recursive=true&IncludeItemTypes=\(itemType)&api_key=\(token)") else {
            return []
        }

        var searchReq = URLRequest(url: searchUrl)
        searchReq.setValue(defaultUA, forHTTPHeaderField: "User-Agent")
        searchReq.timeoutInterval = 5

        guard let (searchData, searchResp) = try? await URLSession.shared.data(for: searchReq),
              (searchResp as? HTTPURLResponse)?.statusCode == 200,
              let searchJson = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let items = searchJson["Items"] as? [[String: Any]], !items.isEmpty else {
            return []
        }

        var streams: [StreamSource] = []
        for item in items.prefix(2) {
            guard let itemId = item["Id"] as? String ?? (item["Id"] as? Int).map(String.init) else { continue }
            let name = item["Name"] as? String ?? title
            let masterUrl = "https://play.roarzone.net/videos/\(itemId)/master.m3u8?api_key=\(token)&VideoCodec=hevc,h264&AudioCodec=aac,mp3"
            streams.append(StreamSource(
                url: masterUrl,
                quality: "HD 1080P",
                provider: "RoarZone [EMBY] (\(name))",
                type: "direct",
                headers: [
                    "User-Agent": defaultUA,
                    "Referer": "https://play.roarzone.net/web/index.html"
                ]
            ))
        }
        return streams
    }

    // MARK: - 3. VixSrc HD Stream Resolver
    private func resolveVixSrc(tmdbId: Int, isTV: Bool, season: Int, episode: Int) async -> [StreamSource] {
        let path = isTV ? "api/tv/\(tmdbId)/\(season)/\(episode)" : "api/movie/\(tmdbId)"
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
}
