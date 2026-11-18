import Foundation

final class CineplexScraper {
    static let shared = CineplexScraper()
    private let baseUrl = "http://cineplexbd.net"
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private init() {}

    /// Scrapes cineplexbd.net in real-time for direct BDIX MP4 streams
    func resolveStreams(title: String, isTV: Bool = false, season: Int = 1, episode: Int = 1) async -> [StreamSource] {
        let cleanTitle = title.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let targetClean = cleanTitle.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()

        guard let encoded = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "\(baseUrl)/search.php?q=\(encoded)") else {
            return []
        }

        var searchReq = URLRequest(url: searchUrl)
        searchReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (searchData, _) = try? await URLSession.shared.data(for: searchReq),
              let html = String(data: searchData, encoding: .utf8) else {
            return []
        }

        let blocks = html.components(separatedBy: "href=\"view.php?id=")
        var candidates: [(id: String, quality: String, title: String)] = []
        var seenIds = Set<String>()

        for block in blocks.dropFirst() {
            guard let idMatch = extractRegex(block, pattern: #"^(\d+)"#) else { continue }
            if seenIds.contains(idMatch) { continue }

            if let titleMatch = extractRegex(block, pattern: #"<span[^>]*class=["'][^"']*truncate[^"']*["'][^>]*>\s*([^<]+?)\s*</span>"#) {
                let siteClean = titleMatch.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .joined()

                if siteClean.contains(targetClean) || targetClean.contains(siteClean) {
                    seenIds.insert(idMatch)
                    let quality = extractRegex(block, pattern: #">\s*(4K|1080P|720P|480P)\s*<"#) ?? "1080P"
                    candidates.append((id: idMatch, quality: quality, title: titleMatch))
                }
            }
        }

        if candidates.isEmpty {
            // Loose fallback match
            for block in blocks.dropFirst() {
                guard let idMatch = extractRegex(block, pattern: #"^(\d+)"#), !seenIds.contains(idMatch) else { continue }
                seenIds.insert(idMatch)
                let quality = extractRegex(block, pattern: #">\s*(4K|1080P|720P|480P)\s*<"#) ?? "HD"
                candidates.append((id: idMatch, quality: quality, title: cleanTitle))
                if candidates.count >= 2 { break }
            }
        }

        var streamSources: [StreamSource] = []

        for candidate in candidates.prefix(3) {
            let viewUrlStr = "\(baseUrl)/view.php?id=\(candidate.id)"
            let streamUrlStr = isTV 
                ? "\(baseUrl)/watch.php?id=\(candidate.id)&season=\(season)&ep=\(episode)"
                : "\(baseUrl)/player.php?id=\(candidate.id)"

            guard let viewUrl = URL(string: viewUrlStr),
                  let streamPageUrl = URL(string: streamUrlStr) else { continue }

            // 1. Fetch view page for session cookie
            var viewReq = URLRequest(url: viewUrl)
            viewReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            viewReq.setValue("\(baseUrl)/", forHTTPHeaderField: "Referer")

            var viewCookie = ""
            if let (_, viewResp) = try? await URLSession.shared.data(for: viewReq),
               let httpResp = viewResp as? HTTPURLResponse,
               let cookie = httpResp.allHeaderFields["Set-Cookie"] as? String {
                viewCookie = cookie
            }

            // 2. Fetch player page for video source
            var streamReq = URLRequest(url: streamPageUrl)
            streamReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            streamReq.setValue(viewUrlStr, forHTTPHeaderField: "Referer")
            if !viewCookie.isEmpty {
                streamReq.setValue(viewCookie, forHTTPHeaderField: "Cookie")
            }

            guard let (streamData, streamResp) = try? await URLSession.shared.data(for: streamReq),
                  let playerHtml = String(data: streamData, encoding: .utf8) else {
                continue
            }

            var finalCookie = viewCookie
            if let httpResp = streamResp as? HTTPURLResponse,
               let setCookie = httpResp.allHeaderFields["Set-Cookie"] as? String {
                finalCookie = "\(viewCookie); \(setCookie)".trimmingCharacters(in: CharacterSet(charactersIn: "; "))
            }

            var videoUrl: String? = nil
            if let vsrc = extractRegex(playerHtml, pattern: #"videoSrc\s*=\s*["']([^"']+)"#) {
                videoUrl = vsrc
            } else if let src = extractRegex(playerHtml, pattern: #"<source\s+src=["']([^"']+)"#) {
                videoUrl = src
            }

            if let rawVideo = videoUrl {
                let fullUrl = rawVideo.hasPrefix("http") ? rawVideo : (rawVideo.hasPrefix("/") ? "\(baseUrl)\(rawVideo)" : "\(baseUrl)/\(rawVideo)")
                var headers: [String: String] = [
                    "User-Agent": userAgent,
                    "Referer": "\(baseUrl)/",
                    "Origin": baseUrl
                ]
                if !finalCookie.isEmpty {
                    headers["Cookie"] = finalCookie
                }

                streamSources.append(StreamSource(
                    url: fullUrl,
                    quality: candidate.quality,
                    provider: "CineplexBD (BDIX)",
                    type: "direct",
                    headers: headers
                ))
            }
        }

        return streamSources
    }

    private func extractRegex(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
