import Foundation

final class CineplexScraper {
    static let shared = CineplexScraper()
    private let baseUrl = "http://cineplexbd.net"
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    private init() {}

    /// Scrapes cineplexbd.net in real-time for direct BDIX MP4 streams
    func resolveStreams(title: String, isTV: Bool = false, season: Int = 1, episode: Int = 1) async -> [StreamSource] {
        let cleanTitle = title.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let encoded = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "\(baseUrl)/search.php?q=\(encoded)") else {
            return []
        }

        var searchReq = URLRequest(url: searchUrl)
        searchReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        searchReq.timeoutInterval = 5

        guard let (searchData, _) = try? await URLSession.shared.data(for: searchReq),
              let html = String(data: searchData, encoding: .utf8) else {
            return []
        }

        // Extract view.php?id=... and title from alt attribute or text
        let pattern = #"href=[\"']view\.php\?id=(\d+)[\"'][^>]*>[\s\S]*?(?:alt=[\"']([^\"']+)[\"']|<span[^>]*>([^<]+)</span>)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var seenIds = Set<String>()
        var candidates: [(id: String, title: String)] = []

        for m in matches {
            guard m.numberOfRanges >= 2,
                  let r1 = Range(m.range(at: 1), in: html) else { continue }
            let id = String(html[r1])
            if seenIds.contains(id) { continue }
            seenIds.insert(id)

            var matchedTitle = cleanTitle
            if m.numberOfRanges >= 3, let r2 = Range(m.range(at: 2), in: html) {
                matchedTitle = String(html[r2])
            } else if m.numberOfRanges >= 4, let r3 = Range(m.range(at: 3), in: html) {
                matchedTitle = String(html[r3])
            }
            candidates.append((id: id, title: matchedTitle))
            if candidates.count >= 3 { break }
        }

        var streamSources: [StreamSource] = []

        for candidate in candidates {
            let pUrlStr = isTV
                ? "\(baseUrl)/watch.php?id=\(candidate.id)&season=\(season)&ep=\(episode)"
                : "\(baseUrl)/player.php?id=\(candidate.id)"

            guard let pUrl = URL(string: pUrlStr) else { continue }
            var pReq = URLRequest(url: pUrl)
            pReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            pReq.setValue("\(baseUrl)/view.php?id=\(candidate.id)", forHTTPHeaderField: "Referer")
            pReq.timeoutInterval = 5

            guard let (pData, _) = try? await URLSession.shared.data(for: pReq),
                  let pHtml = String(data: pData, encoding: .utf8) else { continue }

            // Extract videoSrc = '...' or source src='...'
            let vPattern = #"videoSrc\s*=\s*[\"']([^\"']+)[\"']"#
            guard let vRegex = try? NSRegularExpression(pattern: vPattern, options: [.caseInsensitive]),
                  let vMatch = vRegex.firstMatch(in: pHtml, range: NSRange(pHtml.startIndex..., in: pHtml)),
                  vMatch.numberOfRanges > 1,
                  let vRange = Range(vMatch.range(at: 1), in: pHtml) else { continue }

            let rawVideo = String(pHtml[vRange])
            let fullUrl = rawVideo.hasPrefix("http") ? rawVideo : "\(baseUrl)\(rawVideo.hasPrefix("/") ? "" : "/")\(rawVideo)"

            let quality = rawVideo.contains("1080") ? "1080P Full HD" : (rawVideo.contains("720") ? "720P HD" : (rawVideo.contains("4K") ? "4K UHD" : "HD BDIX"))

            streamSources.append(StreamSource(
                url: fullUrl,
                quality: quality,
                provider: "Cineplex BD [BDIX] (\(candidate.title))",
                type: "direct",
                headers: [
                    "User-Agent": userAgent,
                    "Referer": "\(baseUrl)/",
                    "Origin": baseUrl
                ]
            ))
        }

        return streamSources
    }
}
