import Foundation

final class BDIXAddonScraper {
    static let shared = BDIXAddonScraper()

    private let defaultUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private let androidUA = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Mobile Safari/537.36"

    private init() {}

    /// Resolves streams across all verified StreamBD Addon providers.
    /// ONLY returns addons that actually have the title. No dummy or fake fallback links!
    func resolveAllAddons(title: String, year: String, isTV: Bool, season: Int, episode: Int, tmdbId: Int) async -> [StreamSource] {
        var results: [StreamSource] = []

        // Run scrapers in parallel
        async let cineplexTask = CineplexScraper.shared.resolveStreams(
            title: title,
            isTV: isTV,
            season: season,
            episode: episode
        )
        async let ctgTask = resolveCtgMovies(title: title, tmdbId: tmdbId, isTV: isTV, season: season, episode: episode)
        async let roarTask = resolveRoarZone(title: title, isTV: isTV)
        async let vixTask = resolveVixSrc(tmdbId: tmdbId, isTV: isTV, season: season, episode: episode)

        let cineplexStreams = await cineplexTask
        let ctgStreams = await ctgTask
        let roarStreams = await roarTask
        let vixStreams = await vixTask

        results.append(contentsOf: cineplexStreams)
        results.append(contentsOf: ctgStreams)
        results.append(contentsOf: roarStreams)
        results.append(contentsOf: vixStreams)

        return results
    }

    // MARK: - 1. CTG Movies BDIX FTP Scraper (Authentic Cockpit API + Next.js RSC Watch Payload)
    private func resolveCtgMovies(title: String, tmdbId: Int, isTV: Bool, season: Int, episode: Int) async -> [StreamSource] {
        let loginUrlStr = "https://cockpit.ctgmovies.com/api/v1/auth/login"
        guard let loginUrl = URL(string: loginUrlStr) else { return [] }

        var loginReq = URLRequest(url: loginUrl)
        loginReq.httpMethod = "POST"
        loginReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        loginReq.setValue(androidUA, forHTTPHeaderField: "User-Agent")
        loginReq.setValue("https://ctgmovies.com", forHTTPHeaderField: "Origin")
        loginReq.setValue("https://ctgmovies.com/", forHTTPHeaderField: "Referer")
        loginReq.timeoutInterval = 7
        loginReq.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": "gobop98171@joystill.com",
            "password": "Joy1971"
        ])

        guard let (loginData, loginResp) = try? await URLSession.shared.data(for: loginReq),
              (loginResp as? HTTPURLResponse)?.statusCode == 200,
              let loginJson = try? JSONSerialization.jsonObject(with: loginData) as? [String: Any],
              let token = loginJson["token"] as? String else {
            return []
        }

        // Search title
        let path = isTV ? "series" : "movies"
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "https://cockpit.ctgmovies.com/api/v1/\(path)?search=\(encodedTitle)&limit=24") else {
            return []
        }

        var searchReq = URLRequest(searchUrl)
        searchReq.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        searchReq.setValue(token, forHTTPHeaderField: "x-auth-token")
        searchReq.setValue(androidUA, forHTTPHeaderField: "User-Agent")
        searchReq.timeoutInterval = 7

        guard let (searchData, searchResp) = try? await URLSession.shared.data(for: searchReq),
              (searchResp as? HTTPURLResponse)?.statusCode == 200,
              let searchJson = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any] else {
            return []
        }

        let items = (searchJson["movies"] as? [[String: Any]]) ??
                    (searchJson["series"] as? [[String: Any]]) ??
                    (searchJson["data"] as? [[String: Any]]) ?? []

        // Match TMDB ID or title
        var matchedItem: [String: Any]? = nil
        for it in items {
            if let tId = it["tmdb_id"], String(describing: tId) == String(tmdbId) {
                matchedItem = it
                break
            }
        }
        if matchedItem == nil {
            let lowerTitle = title.lowercased()
            for it in items {
                let itTitle = (it["title"] as? String ?? it["name"] as? String ?? "").lowercased()
                if itTitle.contains(lowerTitle) || lowerTitle.contains(itTitle) {
                    matchedItem = it
                    break
                }
            }
        }

        guard let matched = matchedItem,
              let watchId = matched["id"] as? String ?? matched["_id"] as? String else {
            return []
        }

        // Fetch RSC payload from Next.js watch page
        let watchType = isTV ? "episode" : "movie"
        let watchUrlStr = "https://ctgmovies.com/watch/\(watchId)?type=\(watchType)"
        guard let watchUrl = URL(string: watchUrlStr) else { return [] }

        var watchReq = URLRequest(url: watchUrl)
        watchReq.setValue("1", forHTTPHeaderField: "RSC")
        watchReq.setValue("ctg_token=\(token)", forHTTPHeaderField: "Cookie")
        watchReq.setValue(androidUA, forHTTPHeaderField: "User-Agent")
        watchReq.setValue("https://ctgmovies.com/", forHTTPHeaderField: "Referer")
        watchReq.timeoutInterval = 8

        guard let (watchData, watchResp) = try? await URLSession.shared.data(for: watchReq),
              (watchResp as? HTTPURLResponse)?.statusCode == 200,
              let rscText = String(data: watchData, encoding: .utf8) else {
            return []
        }

        // Extract direct streaming URLs from RSC payload
        var streams: [StreamSource] = []
        let pattern = #"https?://[^\s"'<>]+\.(?:mp4|mkv|m3u8)[^\s"'<>]*"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let matches = regex.matches(in: rscText, range: NSRange(rscText.startIndex..., in: rscText))
            var seen = Set<String>()

            for m in matches {
                guard let r = Range(m.range, in: rscText) else { continue }
                let link = String(rscText[r])
                if seen.insert(link).inserted {
                    let quality = link.contains("1080p") ? "1080P BluRay" : (link.contains("720p") ? "720P HD" : "BDIX Direct")
                    streams.append(StreamSource(
                        url: link,
                        quality: quality,
                        provider: "CTG Movies FTP (BDIX)",
                        type: "direct",
                        headers: [
                            "User-Agent": androidUA,
                            "Referer": "https://ctgmovies.com/",
                            "Cookie": "ctg_token=\(token)"
                        ]
                    ))
                }
            }
        }
        return streams
    }

    // MARK: - 2. RoarZone EMBY / BDIX Server (Authentic Public API)
    private func resolveRoarZone(title: String, isTV: Bool) async -> [StreamSource] {
        let authUrlStr = "https://play.roarzone.net/Users/AuthenticateByName"
        guard let authUrl = URL(string: authUrlStr) else { return [] }

        var authReq = URLRequest(url: authUrl)
        authReq.httpMethod = "POST"
        authReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authReq.setValue(defaultUA, forHTTPHeaderField: "User-Agent")
        authReq.setValue("Eentertainment", forHTTPHeaderField: "X-Emby-Client")
        authReq.setValue("iPhone", forHTTPHeaderField: "X-Emby-Device-Name")
        authReq.setValue("a82c8593-c522-41b1-bda6-d752c415a875", forHTTPHeaderField: "X-Emby-Device-Id")
        authReq.setValue("4.9.3.0", forHTTPHeaderField: "X-Emby-Client-Version")
        authReq.timeoutInterval = 7
        authReq.httpBody = try? JSONSerialization.data(withJSONObject: [
            "Username": "RoarZone_Guest",
            "Pw": ""
        ])

        guard let (authData, authResp) = try? await URLSession.shared.data(for: authReq),
              (authResp as? HTTPURLResponse)?.statusCode == 200,
              let authJson = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let token = authJson["AccessToken"] as? String,
              let userObj = authJson["User"] as? [String: Any],
              let userId = userObj["Id"] as? String else {
            return []
        }

        // Search library
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "https://play.roarzone.net/Users/\(userId)/Items?SearchTerm=\(encodedTitle)&IncludeItemTypes=Movie,Series&Recursive=true&Limit=10") else {
            return []
        }

        var searchReq = URLRequest(url: searchUrl)
        searchReq.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        searchReq.setValue(defaultUA, forHTTPHeaderField: "User-Agent")
        searchReq.timeoutInterval = 7

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
                provider: "RoarZone [Emby] (\(name))",
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
        req.timeoutInterval = 7

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
                provider: "VixSrc HD",
                type: "embed",
                headers: [
                    "User-Agent": defaultUA,
                    "Referer": "https://vixsrc.to/"
                ]
            )
        ]
    }
}
