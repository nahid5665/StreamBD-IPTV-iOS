import Foundation

final class CineplexScraper {
    static let shared = CineplexScraper()
    private let baseUrl = "http://cineplexbd.net"
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    private init() {}

    /// Scrapes cineplexbd.net in real-time for direct BDIX MP4 / HLS streams
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
        searchReq.timeoutInterval = 7

        guard let (searchData, _) = try? await URLSession.shared.data(for: searchReq),
              let html = String(data: searchData, encoding: .utf8) else {
            return []
        }

        // Extract both view.php?id= (movies) and watch.php?id= (series) along with title from alt attribute
        let pattern = #"<a\s+href=[\"'](view|watch)\.php\?id=(\d+)[\"'][\s\S]*?<img\s+[^>]*alt=[\"']([^\"']+)[\"']"#
        var candidates: [(kind: String, id: String, title: String)] = []
        var seenIds = Set<String>()

        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for m in matches {
                guard m.numberOfRanges >= 4,
                      let r1 = Range(m.range(at: 1), in: html),
                      let r2 = Range(m.range(at: 2), in: html),
                      let r3 = Range(m.range(at: 3), in: html) else { continue }

                let kind = String(html[r1])
                let id = String(html[r2])
                let matchedTitle = String(html[r3]).trimmingCharacters(in: .whitespacesAndNewlines)

                if seenIds.contains(id) { continue }
                seenIds.insert(id)

                candidates.append((kind: kind, id: id, title: matchedTitle))
                if candidates.count >= 4 { break }
            }
        }

        // Fallback loose match if card pattern didn't capture enough
        if candidates.isEmpty {
            let loosePattern = #"href=[\"'](view|watch)\.php\?id=(\d+)[\"']"#
            if let looseRegex = try? NSRegularExpression(pattern: loosePattern, options: [.caseInsensitive]) {
                let matches = looseRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for m in matches {
                    guard m.numberOfRanges >= 3,
                          let r1 = Range(m.range(at: 1), in: html),
                          let r2 = Range(m.range(at: 2), in: html) else { continue }
                    let kind = String(html[r1])
                    let id = String(html[r2])
                    if seenIds.contains(id) { continue }
                    seenIds.insert(id)
                    candidates.append((kind: kind, id: id, title: cleanTitle))
                    if candidates.count >= 3 { break }
                }
            }
        }

        var streamSources: [StreamSource] = []

        for candidate in candidates {
            let isCandidateTV = isTV || (candidate.kind.lowercased() == "watch")
            let pUrlStr = isCandidateTV
                ? "\(baseUrl)/watch.php?id=\(candidate.id)&season=\(season)&ep=\(episode)"
                : "\(baseUrl)/player.php?id=\(candidate.id)"

            guard let pUrl = URL(string: pUrlStr) else { continue }
            var pReq = URLRequest(url: pUrl)
            pReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            pReq.setValue("\(baseUrl)/", forHTTPHeaderField: "Referer")
            pReq.timeoutInterval = 7

            guard let (pData, pResp) = try? await URLSession.shared.data(for: pReq),
                  let pHtml = String(data: pData, encoding: .utf8) else { continue }

            var cookieHeader = ""
            if let httpResp = pResp as? HTTPURLResponse {
                if let cookies = httpResp.allHeaderFields["Set-Cookie"] as? String {
                    cookieHeader = cookies
                }
            }

            // Extract stream URL: check videoSrc (movie) or source src (series)
            var rawStream: String? = nil

            let vPattern = #"videoSrc\s*=\s*[\"']([^\"']+)[\"']"#
            if let vRegex = try? NSRegularExpression(pattern: vPattern, options: [.caseInsensitive]),
               let vMatch = vRegex.firstMatch(in: pHtml, range: NSRange(pHtml.startIndex..., in: pHtml)),
               vMatch.numberOfRanges > 1,
               let vRange = Range(vMatch.range(at: 1), in: pHtml) {
                rawStream = String(pHtml[vRange])
            }

            if rawStream == nil {
                let sPattern = #"<source\s+[^>]*src=[\"']([^\"']+)[\"']"#
                if let sRegex = try? NSRegularExpression(pattern: sPattern, options: [.caseInsensitive]),
                   let sMatch = sRegex.firstMatch(in: pHtml, range: NSRange(pHtml.startIndex..., in: pHtml)),
                   sMatch.numberOfRanges > 1,
                   let sRange = Range(sMatch.range(at: 1), in: pHtml) {
                    rawStream = String(pHtml[sRange])
                }
            }

            guard let streamPath = rawStream else { continue }

            let fullUrl: String
            if streamPath.hasPrefix("http://") || streamPath.hasPrefix("https://") {
                fullUrl = streamPath
            } else {
                fullUrl = "\(baseUrl)\(streamPath.hasPrefix("/") ? "" : "/")\(streamPath)"
            }

            let quality = streamPath.contains("1080") ? "1080P Full HD" : (streamPath.contains("720") ? "720P HD" : (streamPath.contains("4K") ? "4K UHD" : (streamPath.contains(".m3u8") ? "HLS Adaptive" : "HD BDIX")))

            var reqHeaders: [String: String] = [
                "User-Agent": userAgent,
                "Referer": pUrlStr,
                "Origin": baseUrl
            ]
            if !cookieHeader.isEmpty {
                reqHeaders["Cookie"] = cookieHeader
            }

            let label = isCandidateTV ? "Cineplex BD [BDIX] (\(candidate.title) S\(season)E\(episode))" : "Cineplex BD [BDIX] (\(candidate.title))"

            streamSources.append(StreamSource(
                url: fullUrl,
                quality: quality,
                provider: label,
                type: "direct",
                headers: reqHeaders
            ))
        }

        return streamSources
    }
}
