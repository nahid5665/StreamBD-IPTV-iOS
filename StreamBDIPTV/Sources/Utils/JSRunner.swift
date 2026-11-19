import Foundation
import JavaScriptCore

final class JSRunner {
    static let shared = JSRunner()

    /// Native Swift implementation of the bundled `plusbox.js`, `server1_jio.js`, `server2_jio.js` and remote `// JS PLAYLIST` scripts
    func executePlaylistScript(_ jsCode: String) async -> String {
        // 1. PlusBox Fast Native Resolver
        if jsCode.contains("plusbox.tv") {
            return await executePlusBoxNative()
        }

        // 2. Jio TV Servers
        if jsCode.contains("jhome.ipl2026.workers.dev") {
            return await executeJioServerNative(portalURL: "https://jhome.ipl2026.workers.dev/", groupName: "Jio Server 1")
        }
        if jsCode.contains("05.teachub.workers.dev") {
            return await executeJioServerNative(portalURL: "https://05.teachub.workers.dev/", groupName: "Jio Server 2")
        }

        // 3. 11Plus FTP Live
        if jsCode.contains("ott.playtimebd.live") {
            return await executeGenericPortalNative(baseUrl: "http://ott.playtimebd.live:8085/", groupName: "11Plus FTP")
        }

        // 4. BDIPTV Live
        if jsCode.contains("tv.bdiptv.net") {
            return await executeGenericPortalNative(baseUrl: "https://tv.bdiptv.net/", groupName: "BDIPTV")
        }

        // 5. BDIX BD 1 (JSON)
        if jsCode.contains("198.195.239.50") {
            return await executeJsonChannelsNative(url: "http://198.195.239.50/tv_channels.json", groupName: "BDIX BD 1")
        }

        // 6. IPTVIDN
        if jsCode.contains("iptvidn.com") {
            return await executeGenericPortalNative(baseUrl: "https://iptvidn.com/", groupName: "IPTVIDN")
        }

        // 7. Matha Nosto TV
        if jsCode.contains("172.172.172.2") {
            return await executeGenericPortalNative(baseUrl: "http://172.172.172.2/", groupName: "Matha Nosto TV")
        }

        // Generic JavaScriptCore execution: invokes generatePlaylist() if defined
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let context = JSContext() else {
                    continuation.resume(returning: "")
                    return
                }
                var emittedM3U = ""

                let fetchUrlBlock: @convention(block) (String, String?) -> String = { urlStr, headersJson in
                    var headers: [String: String] = [:]
                    if let hj = headersJson,
                       let data = hj.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                        headers = parsed
                    }
                    var req = URLRequest(url: URL(string: urlStr) ?? URL(fileURLWithPath: "/"))
                    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
                    req.timeoutInterval = 4
                    let sem = DispatchSemaphore(value: 0)
                    var resultText = ""
                    let task = URLSession.shared.dataTask(with: req) { data, _, _ in
                        if let d = data { resultText = String(data: d, encoding: .utf8) ?? "" }
                        sem.signal()
                    }
                    task.resume()
                    _ = sem.wait(timeout: .now() + 5)
                    return resultText
                }

                let sendBlock: @convention(block) (String) -> Void = { m3u in
                    emittedM3U = m3u
                }

                context.setObject(fetchUrlBlock, forKeyedSubscript: "__nativeFetchUrl" as NSString)
                context.setObject(sendBlock, forKeyedSubscript: "__nativeSend" as NSString)

                let bootstrap = """
                var streamBD = {
                    fetchUrl: function(u, h) { return __nativeFetchUrl(u, h || null); },
                    send: function(res) { __nativeSend(String(res || "")); },
                    log: function(msg) {}
                };
                var fetch = async function(u, opts) {
                    var h = (opts && opts.headers) ? JSON.stringify(opts.headers) : null;
                    var txt = __nativeFetchUrl(u, h);
                    return {
                        ok: txt.length > 0,
                        status: txt.length > 0 ? 200 : 500,
                        text: async function() { return txt; },
                        json: async function() { return JSON.parse(txt || "{}"); }
                    };
                };
                """
                context.evaluateScript(bootstrap)
                context.evaluateScript(jsCode)

                // Trigger generatePlaylist() if defined in the script
                let invokeScript = """
                (async function() {
                    try {
                        if (typeof generatePlaylist === 'function') {
                            var r = await generatePlaylist();
                            streamBD.send(r);
                        } else if (typeof generatePlusBoxPlaylist === 'function') {
                            var r2 = await generatePlusBoxPlaylist();
                            streamBD.send(r2);
                        }
                    } catch(e) {}
                })();
                """
                context.evaluateScript(invokeScript)
                continuation.resume(returning: emittedM3U)
            }
        }
    }

    // MARK: - Fast Native PlusBox Parser (Zero blocking loops)
    private func executePlusBoxNative() async -> String {
        let baseUrl = "https://plusbox.tv"
        let ua = AppConfig.browserUserAgent
        guard let html = try? await NetworkManager.shared.fetchText(from: baseUrl, headers: ["User-Agent": ua]) else {
            return ""
        }
        let pattern = #"<a\s+class="playignitor thumbnail"([^>]*)>\s*<img([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return "" }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        var m3u = "#EXTM3U\n"
        for m in matches {
            guard m.numberOfRanges >= 3,
                  let r1 = Range(m.range(at: 1), in: html),
                  let r2 = Range(m.range(at: 2), in: html) else { continue }
            let aAttrs = String(html[r1])
            let imgAttrs = String(html[r2])
            guard let title = extractAttr(aAttrs, "href=\"#([^\"]+)\""),
                  let dataName = extractAttr(aAttrs, "data-name=\"([^\"]+)\""),
                  let rawImg = extractAttr(imgAttrs, "src=\"([^\"]+)\"") else { continue }
            let imgUrl = rawImg.hasPrefix("http") ? rawImg : "\(baseUrl)/\(rawImg)"
            let streamUrl = "https://backend.plusbox.tv/\(dataName)/tracks-v1/index.fmp4.m3u8"
            let embedUrl = "https://backend.plusbox.tv/\(dataName)/embed.html?mute=false&autoplay=true&volume=50"
            m3u += "#EXTINF:-1 tvg-logo=\"\(imgUrl)\" group-title=\"PlusBox TV\",\(title)\n\(streamUrl)|plusboxChannel=\(dataName)|User-Agent=\(ua)|Referer=\(embedUrl)|Origin=\(baseUrl)\n"
        }
        return m3u
    }

    // MARK: - Fast Native Jio TV Parser
    private func executeJioServerNative(portalURL: String, groupName: String) async -> String {
        do {
            let html = try await NetworkManager.shared.fetchText(from: portalURL, headers: [
                "User-Agent": AppConfig.browserUserAgent
            ])
            let sessionText = try await NetworkManager.shared.fetchText(
                from: "https://s.ipl2026.workers.dev/create-session",
                headers: [
                    "Origin": "https://jp.ipl2026.workers.dev",
                    "Referer": "https://jp.ipl2026.workers.dev/"
                ]
            )
            guard let sessionData = sessionText.data(using: .utf8),
                  let sessionJson = try? JSONSerialization.jsonObject(with: sessionData) as? [String: Any],
                  let sessionId = sessionJson["sessionId"] as? String else {
                return ""
            }
            let cookie = "session=\(sessionId)"
            let referer = "https://jp.ipl2026.workers.dev/"
            let origin = "https://jp.ipl2026.workers.dev"

            let pattern = #"<div class="card"[^>]*>[\s\S]*?<img src="([^"]+)"[\s\S]*?<div class="title">([^<]+)</div>[\s\S]*?<a class="play" href="[^"]*\?id=([^"]+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return "" }
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

            var m3u = "#EXTM3U\n"
            for m in matches {
                guard m.numberOfRanges >= 4,
                      let r1 = Range(m.range(at: 1), in: html),
                      let r2 = Range(m.range(at: 2), in: html),
                      let r3 = Range(m.range(at: 3), in: html) else { continue }
                let logo = String(html[r1]).trimmingCharacters(in: .whitespacesAndNewlines)
                let title = String(html[r2]).trimmingCharacters(in: .whitespacesAndNewlines)
                let id = String(html[r3]).trimmingCharacters(in: .whitespacesAndNewlines)
                let streamUrl = "https://s.ipl2026.workers.dev/live.m3u8?id=\(id)|Cookie=\(cookie)|Referer=\(referer)|Origin=\(origin)"
                m3u += "#EXTINF:-1 tvg-logo=\"\(logo)\" group-title=\"\(groupName)\",\(title)\n\(streamUrl)\n"
            }
            return m3u
        } catch {
            return ""
        }
    }

    // MARK: - Fast Native Generic Portal Parser (11Plus, BDIPTV, IPTVIDN)
    private func executeGenericPortalNative(baseUrl: String, groupName: String) async -> String {
        let ua = AppConfig.browserUserAgent
        guard let url = URL(string: baseUrl) else { return "" }
        var req = URLRequest(url: url)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 4

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return ""
        }

        let pattern = #"<li\s+class=["']([^"']+)["'][^>]*>[\s\S]*?onclick=["'][^'"]*href=['"]([^'"]+)['"][^>]*>[\s\S]*?<img\s+[^>]*src=["']([^'"]+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return "" }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        var m3u = "#EXTM3U\n"
        let origin = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        for m in matches {
            guard m.numberOfRanges >= 4,
                  let rCategory = Range(m.range(at: 1), in: html),
                  let rStream = Range(m.range(at: 2), in: html),
                  let rLogo = Range(m.range(at: 3), in: html) else { continue }

            let streamPath = String(html[rStream]).trimmingCharacters(in: .whitespacesAndNewlines)
            let logoPath = String(html[rLogo]).trimmingCharacters(in: .whitespacesAndNewlines)
            let category = String(html[rCategory]).trimmingCharacters(in: .whitespacesAndNewlines)

            if category.contains("nav-item") || streamPath.isEmpty { continue }

            let streamUrl = streamPath.hasPrefix("http") ? streamPath : "\(origin)/\(streamPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
            let logoUrl = logoPath.hasPrefix("http") ? logoPath : "\(origin)/\(logoPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"

            let fileName = logoPath.split(separator: "/").last?.split(separator: "?").first.map(String.init) ?? "Channel"
            var channelName = fileName.replacingOccurrences(of: "\\.[^/.]+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[-_]", with: " ")
                .capitalized

            if channelName.isEmpty { channelName = "Channel" }

            m3u += "#EXTINF:-1 tvg-logo=\"\(logoUrl)\" group-title=\"\(groupName)\",\(channelName)\n\(streamUrl)|User-Agent=\(ua)|Referer=\(baseUrl)|Origin=\(origin)\n"
        }
        return m3u
    }

    // MARK: - Fast Native JSON Channels Parser (BDIX BD 1)
    private func executeJsonChannelsNative(url: String, groupName: String) async -> String {
        guard let u = URL(string: url) else { return "" }
        var req = URLRequest(url: u)
        req.timeoutInterval = 4

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return ""
        }

        var m3u = "#EXTM3U\n"
        for item in json {
            let name = item["name"] as? String ?? item["title"] as? String ?? "Channel"
            let logo = item["logo"] as? String ?? item["icon"] as? String ?? ""
            let streamUrl = item["url"] as? String ?? item["stream_url"] as? String ?? ""
            if !streamUrl.isEmpty {
                m3u += "#EXTINF:-1 tvg-logo=\"\(logo)\" group-title=\"\(groupName)\",\(name)\n\(streamUrl)\n"
            }
        }
        return m3u
    }

    private func extractAttr(_ text: String, _ pattern: String) -> String? {
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
