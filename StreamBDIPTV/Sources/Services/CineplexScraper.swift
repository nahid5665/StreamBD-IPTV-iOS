import Foundation

final class CineplexScraper {
    static let shared = CineplexScraper()
    private let baseUrl = "http://cineplexbd.net"
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    private init() {}

    private func sanitizeQuery(_ text: String) -> String {
        var s = text.replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "&", with: "and")
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeUAStrategy: (label: String, ua: String?)? = nil

    /// Scrapes cineplexbd.net in real-time for direct BDIX MP4 / HLS streams
    func resolveStreams(title: String, isTV: Bool = false, season: Int = 1, episode: Int = 1) async -> [StreamSource] {
        // APK-parity: warm the site in a real WebKit session first so any JS
        // challenge runs and session/CF cookies land in the shared jar.
        await SitePrewarmer.shared.prewarm(origin: baseUrl)

        let cleanTitle = sanitizeQuery(title)
        var candidates = await searchCandidates(query: cleanTitle)

        // Fallback: If title has a colon (e.g., "Avatar: The Way of Water" -> "Avatar"), search primary title prefix
        if candidates.isEmpty && title.contains(":") {
            let primaryPrefix = sanitizeQuery(title.components(separatedBy: ":").first ?? "")
            if !primaryPrefix.isEmpty && primaryPrefix != cleanTitle {
                candidates = await searchCandidates(query: primaryPrefix)
            }
        }

        var streamSources: [StreamSource] = []

        for candidate in candidates {
            let isCandidateTV = isTV || (candidate.kind.lowercased() == "watch")
            let viewUrlStr = "\(baseUrl)/view.php?id=\(candidate.id)"

            // Step 1: Visit view.php to establish session and capture initial session cookie
            var viewCookie = ""
            if let vUrl = URL(string: viewUrlStr) {
            var vReq = URLRequest(url: vUrl)
            applyActiveUA(to: vReq)
            vReq.setValue("\(baseUrl)/", forHTTPHeaderField: "Referer")
            vReq.timeoutInterval = 8
            do {
                let (_, vResp) = try await URLSession.shared.data(for: vReq)
                if let httpResp = vResp as? HTTPURLResponse {
                    addonLog("[CineplexScraper] view.php?id=\(candidate.id) -> HTTP \(httpResp.statusCode)")
                    viewCookie = Self.extractCookies(from: httpResp, for: vUrl)
                }
            } catch {
                addonLog("[CineplexScraper] view.php?id=\(candidate.id) ERROR \(error.localizedDescription)")
                continue
            }
            }

            // Step 2: Request player.php (movie) or watch.php (series) with captured cookie and referer
            let pUrlStr = isCandidateTV
                ? "\(baseUrl)/watch.php?id=\(candidate.id)&season=\(season)&ep=\(episode)"
                : "\(baseUrl)/player.php?id=\(candidate.id)"

            guard let pUrl = URL(string: pUrlStr) else { continue }
            var pReq = URLRequest(url: pUrl)
            applyActiveUA(to: pReq)
            pReq.setValue(viewUrlStr, forHTTPHeaderField: "Referer")
            if !viewCookie.isEmpty {
                pReq.setValue(viewCookie, forHTTPHeaderField: "Cookie")
            }
            pReq.timeoutInterval = 8

            let pData: Data
            let pResp: URLResponse
            do {
                (pData, pResp) = try await URLSession.shared.data(for: pReq)
            } catch {
                addonLog("[CineplexScraper] \(isCandidateTV ? "watch.php" : "player.php")?id=\(candidate.id) ERROR \(error.localizedDescription)")
                continue
            }
            guard let pHtml = String(data: pData, encoding: .utf8) else {
                addonLog("[CineplexScraper] player response undecodable for id \(candidate.id)")
                continue
            }
            if let httpResp = pResp as? HTTPURLResponse {
                addonLog("[CineplexScraper] \(isCandidateTV ? "watch" : "player").php?id=\(candidate.id) -> HTTP \(httpResp.statusCode), \(pData.count) bytes")
            }

            var playerCookie = ""
            if let httpResp = pResp as? HTTPURLResponse {
                playerCookie = Self.extractCookies(from: httpResp, for: pUrl)
            }
            let combinedCookie = viewCookie.isEmpty ? playerCookie : (playerCookie.isEmpty ? viewCookie : "\(viewCookie); \(playerCookie)")

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

            guard let streamPath = rawStream else {
                addonLog("[CineplexScraper] candidate \(candidate.id): no videoSrc/source found in player HTML")
                continue
            }

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
            if !combinedCookie.isEmpty {
                reqHeaders["Cookie"] = combinedCookie
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

    /// Applies the UA strategy that won during search (session default / iOS
    /// Safari / desktop Chrome) so view.php and player.php are fetched the
    /// same way the site accepted.
    private func applyActiveUA(to request: URLRequest) {
        if let strategy = activeUAStrategy {
            if let ua = strategy.ua {
                request.setValue(ua, forHTTPHeaderField: "User-Agent")
            }
            // nil strategy UA = session default: intentionally no explicit header
        } else {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
    }

    /// Robust Set-Cookie extraction: case-insensitive header scan, HTTPCookie
    /// parsing, then shared-jar fallback. URLSession may fold Set-Cookie headers
    /// into HTTPCookieStorage and omit them from allHeaderFields entirely.
    private static func extractCookies(from response: HTTPURLResponse, for url: URL) -> String {
        var collected: [String] = []

        let fields = response.allHeaderFields
        for (key, value) in fields {
            if "\(key)".caseInsensitiveCompare("set-cookie") == .orderedSame {
                collected.append("\(value)")
            }
        }

        if let castFields = fields as? [String: String] {
            let parsed = HTTPCookie.cookies(withResponseHeaderFields: castFields, for: url)
            for c in parsed {
                collected.append("\(c.name)=\(c.value)")
            }
        }

        if collected.isEmpty {
            let jar = HTTPCookieStorage.shared.cookies(for: url) ?? []
            for c in jar {
                collected.append("\(c.name)=\(c.value)")
            }
        }

        // De-duplicate identical pairs while preserving order
        var seen = Set<String>()
        var unique: [String] = []
        for c in collected where !c.isEmpty {
            if seen.insert(c).inserted { unique.append(c) }
        }
        let result = unique.joined(separator: "; ")
        if AppConfig.debugAddonLogging {
            addonLog("[CineplexScraper] cookies from \(url.path): \(result.count) chars")
        }
        return result
    }

    private func searchCandidates(query: String) async -> [(kind: String, id: String, title: String)] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "\(baseUrl)/search.php?q=\(encoded)") else {
            addonLog("[CineplexScraper] invalid search URL for '\(query)'")
            return []
        }

        // UA strategies, most-proven first: the diagnostics probe (session default
        // UA, no explicit header) is confirmed to reach the site, so try that
        // before assuming a specific browser UA. The first strategy that both
        // fetches successfully AND yields candidates wins.
        let strategies: [(label: String, ua: String?)] = [
            ("session-default", nil),
            ("ios-safari", AppConfig.browserUserAgent),
            ("desktop-chrome", userAgent)
        ]

        var best: [(kind: String, id: String, title: String)] = []

        for strategy in strategies {
            var req = URLRequest(url: searchUrl)
            if let ua = strategy.ua {
                req.setValue(ua, forHTTPHeaderField: "User-Agent")
            }
            req.timeoutInterval = 10

            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
                    addonLog("[CineplexScraper] search via \(strategy.label): HTTP \(code), empty/undecodable body (\(data.count) bytes)")
                    continue
                }

                let parsed = parseCandidates(from: html, query: query)
                addonLog("[CineplexScraper] search via \(strategy.label): HTTP \(code), \(data.count) bytes -> \(parsed.count) candidates")
                if parsed.count > best.count { best = parsed }
                if !parsed.isEmpty {
                    activeUAStrategy = strategy
                    return parsed
                }
            } catch {
                addonLog("[CineplexScraper] search via \(strategy.label): ERROR \(error.localizedDescription)")
            }
        }

        addonLog("[CineplexScraper] search '\(query)' -> \(best.count) candidates (after all UA strategies)")
        return best
    }

    private func parseCandidates(from html: String, query: String) -> [(kind: String, id: String, title: String)] {
        var candidates: [(kind: String, id: String, title: String)] = []
        var seenIds = Set<String>()

        // 1. Flexible card regex matching href="(view|watch).php?id=..." and alt="..." or truncate title
        let cardPattern = #"<a\b[^>]*?\bhref=[\"'](view|watch)\.php\?id=(\d+)[\"'][^>]*>([\s\S]*?)</a>"#
        if let cardRegex = try? NSRegularExpression(pattern: cardPattern, options: [.caseInsensitive]) {
            let matches = cardRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for m in matches {
                guard m.numberOfRanges >= 4,
                      let r1 = Range(m.range(at: 1), in: html),
                      let r2 = Range(m.range(at: 2), in: html),
                      let r3 = Range(m.range(at: 3), in: html) else { continue }

                let kind = String(html[r1])
                let id = String(html[r2])
                let cardBody = String(html[r3])

                if seenIds.contains(id) { continue }

                // Try to extract title from img alt or truncate span
                var cardTitle = query
                let altPattern = #"alt=[\"']([^\"']+)[\"']"#
                if let altRegex = try? NSRegularExpression(pattern: altPattern, options: [.caseInsensitive]),
                   let altMatch = altRegex.firstMatch(in: cardBody, range: NSRange(cardBody.startIndex..., in: cardBody)),
                   altMatch.numberOfRanges > 1,
                   let altR = Range(altMatch.range(at: 1), in: cardBody) {
                    cardTitle = String(cardBody[altR]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    let spanPattern = #"<span[^>]*class=[\"'][^\"']*truncate[^\"']*[\"'][^>]*>([^<]+)</span>"#
                    if let spanRegex = try? NSRegularExpression(pattern: spanPattern, options: [.caseInsensitive]),
                       let spanMatch = spanRegex.firstMatch(in: cardBody, range: NSRange(cardBody.startIndex..., in: cardBody)),
                       spanMatch.numberOfRanges > 1,
                       let spanR = Range(spanMatch.range(at: 1), in: cardBody) {
                        cardTitle = String(cardBody[spanR]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }

                seenIds.insert(id)
                candidates.append((kind: kind, id: id, title: cardTitle))
                if candidates.count >= 4 { break }
            }
        }

        // 2. Loose fallback if card regex didn't capture enough
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
                    candidates.append((kind: kind, id: id, title: query))
                    if candidates.count >= 3 { break }
                }
            }
        }

        return candidates
    }
}
