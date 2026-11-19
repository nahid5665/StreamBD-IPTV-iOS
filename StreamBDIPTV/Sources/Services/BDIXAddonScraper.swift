import Foundation

final class BDIXAddonScraper {
    static let shared = BDIXAddonScraper()

    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private init() {}

    /// Resolves streams across all major StreamBD Addon providers
    func resolveAllAddons(title: String, year: String, isTV: Bool, season: Int, episode: Int, tmdbId: Int) async -> [StreamSource] {
        var results: [StreamSource] = []

        // 1. CineplexBD BDIX
        let cineplexStreams = await CineplexScraper.shared.resolveStreams(
            title: title,
            isTV: isTV,
            season: season,
            episode: episode
        )
        results.append(contentsOf: cineplexStreams)

        // 2. CTG Movies FTP (BDIX)
        if let ctgStream = await resolveCtgMovies(title: title, year: year, isTV: isTV, season: season, episode: episode) {
            results.append(ctgStream)
        }

        // 3. RoarZone EMBY / FTP (BDIX)
        if let roarStream = await resolveRoarZone(title: title, isTV: isTV, season: season, episode: episode) {
            results.append(roarStream)
        }

        // 4. 11Plus WEB (BDIX)
        if let elevenStream = await resolve11Plus(title: title, isTV: isTV, season: season, episode: episode) {
            results.append(elevenStream)
        }

        // 5. Net Mirror (VIP Server)
        results.append(resolveNetMirror(title: title, tmdbId: tmdbId, isTV: isTV, season: season, episode: episode))

        // 6. Global High-Speed Streaming Embeds (Universal fallback)
        results.append(contentsOf: resolveGlobalEmbeds(tmdbId: tmdbId, isTV: isTV, season: season, episode: episode))

        return results
    }

    // MARK: - CTG Movies BDIX FTP Scraper
    private func resolveCtgMovies(title: String, year: String, isTV: Bool, season: Int, episode: Int) async -> StreamSource? {
        let clean = title.replacingOccurrences(of: " ", with: "+").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let searchUrlStr = "http://movie.ctgmovies.com/search.php?query=\(clean)"

        guard let url = URL(string: searchUrlStr) else { return nil }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 6

        if let (data, _) = try? await URLSession.shared.data(for: req),
           let html = String(data: data, encoding: .utf8),
           let link = extractFirstMatch(html, pattern: #"href=["'](http://movie\.ctgmovies\.com/[^"']+\.(?:mp4|mkv))["']"#) {
            return StreamSource(
                url: link,
                quality: "1080P BDIX",
                provider: "CTG Movies FTP (BDIX)",
                type: "direct",
                headers: ["User-Agent": userAgent, "Referer": "http://movie.ctgmovies.com/"]
            )
        }
        return nil
    }

    // MARK: - RoarZone EMBY / BDIX FTP
    private func resolveRoarZone(title: String, isTV: Bool, season: Int, episode: Int) async -> StreamSource? {
        let clean = title.replacingOccurrences(of: " ", with: "%20")
        let roarUrl = "http://172.16.50.4/Movies/\(clean)/\(clean).mkv"
        return StreamSource(
            url: roarUrl,
            quality: "1080P BDIX",
            provider: "RoarZone FTP (BDIX)",
            type: "direct",
            headers: ["User-Agent": userAgent]
        )
    }

    // MARK: - 11Plus WEB
    private func resolve11Plus(title: String, isTV: Bool, season: Int, episode: Int) async -> StreamSource? {
        let clean = title.replacingOccurrences(of: " ", with: "-").lowercased()
        let elevenUrl = "http://11plus.live/stream/\(clean).mp4"
        return StreamSource(
            url: elevenUrl,
            quality: "720P BDIX",
            provider: "11Plus WEB (BDIX)",
            type: "direct",
            headers: ["User-Agent": userAgent, "Referer": "http://11plus.live/"]
        )
    }

    // MARK: - Net Mirror
    private func resolveNetMirror(title: String, tmdbId: Int, isTV: Bool, season: Int, episode: Int) -> StreamSource {
        let path = isTV ? "tv/\(tmdbId)/\(season)/\(episode)" : "movie/\(tmdbId)"
        return StreamSource(
            url: "https://netmirror.app/\(path)",
            quality: "1080P VIP",
            provider: "Net Mirror",
            type: "embed"
        )
    }

    // MARK: - Global Multi-Embeds
    private func resolveGlobalEmbeds(tmdbId: Int, isTV: Bool, season: Int, episode: Int) -> [StreamSource] {
        if isTV {
            return [
                StreamSource(
                    url: "https://vidsrc.me/embed/tv?tmdb=\(tmdbId)&season=\(season)&episode=\(episode)",
                    quality: "1080P Full HD",
                    provider: "VidSrc HD",
                    type: "embed"
                ),
                StreamSource(
                    url: "https://multiembed.mov/?video_id=\(tmdbId)&tmdb=1&s=\(season)&e=\(episode)",
                    quality: "Multi-Server VIP",
                    provider: "MultiEmbed",
                    type: "embed"
                ),
                StreamSource(
                    url: "https://superembed.stream/?video_id=\(tmdbId)&tmdb=1&s=\(season)&e=\(episode)",
                    quality: "Auto 4K/1080P",
                    provider: "SuperEmbed",
                    type: "embed"
                ),
                StreamSource(
                    url: "https://www.2embed.cc/embedtv/\(tmdbId)&s=\(season)&e=\(episode)",
                    quality: "HD Fast",
                    provider: "2Embed",
                    type: "embed"
                )
            ]
        } else {
            return [
                StreamSource(
                    url: "https://vidsrc.me/embed/movie?tmdb=\(tmdbId)",
                    quality: "1080P Full HD",
                    provider: "VidSrc HD",
                    type: "embed"
                ),
                StreamSource(
                    url: "https://multiembed.mov/?video_id=\(tmdbId)&tmdb=1",
                    quality: "Multi-Server VIP",
                    provider: "MultiEmbed",
                    type: "embed"
                ),
                StreamSource(
                    url: "https://superembed.stream/?video_id=\(tmdbId)&tmdb=1",
                    quality: "Auto 4K/1080P",
                    provider: "SuperEmbed",
                    type: "embed"
                ),
                StreamSource(
                    url: "https://www.2embed.cc/embed/\(tmdbId)",
                    quality: "HD Fast",
                    provider: "2Embed",
                    type: "embed"
                )
            ]
        }
    }

    private func extractFirstMatch(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
