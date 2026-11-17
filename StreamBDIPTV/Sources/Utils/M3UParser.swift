import Foundation

enum M3UParser {
    struct ParsedUrl {
        var cleanUrl: String
        var headers: [String: String]
        var drmKeyPair: String?
        var tokenUrl: String?
    }

    /// Parses pipe-separated URL parameters (`url|User-Agent=...|Referer=...|Cookie=...|Origin=...`)
    static func parseUrlHeaders(_ rawLine: String) -> ParsedUrl {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pipeIdx = trimmed.firstIndex(of: "|") else {
            return ParsedUrl(cleanUrl: trimmed, headers: [:])
        }
        let cleanUrl = String(trimmed[..<pipeIdx]).trimmingCharacters(in: .whitespaces)
        let paramPart = String(trimmed[trimmed.index(after: pipeIdx)...])

        var headers: [String: String] = [:]
        var drmKey: String? = nil
        var tokenUrl: String? = nil

        let segments = paramPart.components(separatedBy: "|")
        for seg in segments {
            guard let eqIdx = seg.firstIndex(of: "=") else { continue }
            let key = String(seg[..<eqIdx]).trimmingCharacters(in: .whitespaces).lowercased()
            let val = String(seg[seg.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "user-agent", "http-user-agent":
                headers["User-Agent"] = val
            case "referer", "referrer", "http-referer", "http-referrer", "playref", "streamref":
                headers["Referer"] = val
            case "origin", "http-origin":
                headers["Origin"] = val
            case "cookie", "http-cookie":
                headers["Cookie"] = val
            case "drm-key", "drmkey":
                drmKey = val
            case "tokenurl", "token-url":
                tokenUrl = val
            default:
                headers[key] = val
            }
        }
        return ParsedUrl(cleanUrl: cleanUrl, headers: headers, drmKeyPair: drmKey, tokenUrl: tokenUrl)
    }

    static func normalizeLogo(_ rawLogo: String) -> String {
        let trimmed = rawLogo.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed.replacingOccurrences(of: " ", with: "%20")
        }
        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }
        return "https://cdnhost.akashbd.net/assets/uploads/channels_images/\(trimmed)?v=10.5.10"
    }

    /// Parses `#EXTM3U` or JSON channel arrays into `[Channel]`
    static func parsePlaylist(_ content: String, defaultGroup: String = "Live TV") -> [Channel] {
        let decrypted = CryptoUtils.decryptIfNeeded(content)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if decrypted.hasPrefix("[") || decrypted.hasPrefix("{") {
            return parseJSONPlaylist(decrypted, defaultGroup: defaultGroup)
        }

        var channels: [Channel] = []
        var currentName = "Unknown Channel"
        var currentLogo = ""
        var currentGroup = defaultGroup
        var currentHeaders: [String: String] = [:]
        var currentDrmKey: String? = nil

        let lines = decrypted.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.uppercased().hasPrefix("#EXTINF:") {
                if let logoMatch = extractRegex(line, pattern: #"(?:tvg-logo|logo)=["']([^"']+)["']"#) {
                    currentLogo = normalizeLogo(logoMatch)
                }
                if let groupMatch = extractRegex(line, pattern: #"group-title=["']([^"']+)["']"#) {
                    currentGroup = groupMatch
                }
                if let commaIdx = line.lastIndex(of: ",") {
                    let parsedName = String(line[line.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
                    if !parsedName.isEmpty { currentName = parsedName }
                }
                if let ua = extractRegex(line, pattern: #"http-user-agent=["']([^"']+)["']"#) {
                    currentHeaders["User-Agent"] = ua
                }
                if let ref = extractRegex(line, pattern: #"http-refer(?:r)?er=["']([^"']+)["']"#) {
                    currentHeaders["Referer"] = ref
                }
            } else if line.uppercased().hasPrefix("#EXTGRP:") {
                currentGroup = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else if line.uppercased().hasPrefix("#EXTVLCOPT:") {
                let opt = String(line.dropFirst(11))
                if let eq = opt.firstIndex(of: "=") {
                    let k = String(opt[..<eq]).lowercased().trimmingCharacters(in: .whitespaces)
                    let v = String(opt[opt.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                    if k.contains("user-agent") { currentHeaders["User-Agent"] = v }
                    if k.contains("referrer") || k.contains("referer") { currentHeaders["Referer"] = v }
                    if k.contains("origin") { currentHeaders["Origin"] = v }
                    if k.contains("cookie") { currentHeaders["Cookie"] = v }
                }
            } else if line.uppercased().hasPrefix("#KODIPROP:INPUTSTREAM.ADAPTIVE.LICENSE_KEY=") {
                currentDrmKey = String(line.dropFirst("#KODIPROP:inputstream.adaptive.license_key=".count))
            } else if !line.hasPrefix("#") {
                let parsed = parseUrlHeaders(line)
                var mergedHeaders = currentHeaders
                for (k, v) in parsed.headers { mergedHeaders[k] = v }

                let drmKey = parsed.drmKeyPair ?? currentDrmKey
                let drm = drmKey != nil ? DrmConfig(type: "clearkey", licenseServer: nil, rawKeyPair: drmKey) : nil

                let ch = Channel(
                    name: currentName,
                    url: parsed.cleanUrl,
                    logo: currentLogo,
                    group: currentGroup.isEmpty ? defaultGroup : currentGroup,
                    userAgent: mergedHeaders["User-Agent"],
                    cookie: mergedHeaders["Cookie"],
                    httpReferer: mergedHeaders["Referer"],
                    origin: mergedHeaders["Origin"],
                    httpHeaders: mergedHeaders,
                    tokenUrl: parsed.tokenUrl,
                    drm: drm,
                    sources: ["Server 1": line]
                )
                channels.append(ch)

                currentName = "Unknown Channel"
                currentLogo = ""
                currentHeaders = [:]
                currentDrmKey = nil
            }
        }
        return channels
    }

    static func parseJSONPlaylist(_ jsonStr: String, defaultGroup: String = "Live TV") -> [Channel] {
        guard let data = jsonStr.data(using: .utf8),
              let jsonObj = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        let items: [[String: Any]]
        if let arr = jsonObj as? [[String: Any]] {
            items = arr
        } else if let dict = jsonObj as? [String: Any] {
            if let chs = dict["channels"] as? [[String: Any]] { items = chs }
            else if let st = dict["streams"] as? [[String: Any]] { items = st }
            else if let dt = dict["data"] as? [[String: Any]] { items = dt }
            else { items = [] }
        } else {
            items = []
        }

        var result: [Channel] = []
        for item in items {
            let name = (item["name"] as? String)
                ?? (item["title"] as? String)
                ?? (item["tv_name"] as? String)
                ?? "Unknown Channel"
            let rawLogo = (item["tvg-logo"] as? String)
                ?? (item["logo"] as? String)
                ?? (item["image"] as? String)
                ?? (item["poster_url"] as? String)
                ?? ""
            let group = (item["group-title"] as? String)
                ?? (item["group"] as? String)
                ?? (item["category"] as? String)
                ?? defaultGroup

            var rawUrl = (item["url"] as? String)
                ?? (item["stream_url"] as? String)
                ?? (item["link"] as? String)
                ?? ""
            var sourcesMap: [String: String] = [:]
            if let sourcesDict = item["sources"] as? [String: String] {
                sourcesMap = sourcesDict
                if rawUrl.isEmpty, let first = sourcesDict.values.first {
                    rawUrl = first
                }
            }
            if rawUrl.isEmpty { continue }

            let parsed = parseUrlHeaders(rawUrl)
            var headers = parsed.headers
            if let ua = (item["userAgent"] as? String) ?? (item["user-agent"] as? String) {
                headers["User-Agent"] = ua
            }
            if let ref = (item["referer"] as? String) ?? (item["httpReferer"] as? String) {
                headers["Referer"] = ref
            }
            if let ck = item["cookie"] as? String {
                headers["Cookie"] = ck
            }
            if let org = item["origin"] as? String {
                headers["Origin"] = org
            }
            if sourcesMap.isEmpty {
                sourcesMap["Default"] = rawUrl
            }

            result.append(Channel(
                name: name,
                url: parsed.cleanUrl,
                logo: normalizeLogo(rawLogo),
                group: group,
                userAgent: headers["User-Agent"],
                cookie: headers["Cookie"],
                httpReferer: headers["Referer"],
                origin: headers["Origin"],
                httpHeaders: headers,
                tokenUrl: (item["tokenUrl"] as? String) ?? parsed.tokenUrl,
                sources: sourcesMap
            ))
        }
        return result
    }

    private static func extractRegex(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
