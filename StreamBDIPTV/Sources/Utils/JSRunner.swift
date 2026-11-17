import Foundation
import JavaScriptCore

final class JSRunner {
    static let shared = JSRunner()

    /// Native Swift implementation of the bundled `plusbox.js`, `server1_jio.js`, `server2_jio.js` and remote `// JS PLAYLIST` scripts
    func executePlaylistScript(_ jsCode: String) async -> String {
        // Fast native paths for known StreamBD JS playlists
        if jsCode.contains("plusbox.tv") {
            return await executePlusBoxNative()
        }
        if jsCode.contains("jhome.ipl2026.workers.dev") {
            return await executeJioServerNative(portalURL: "https://jhome.ipl2026.workers.dev/", groupName: "Jio Server 1")
        }
        if jsCode.contains("05.teachub.workers.dev") {
            return await executeJioServerNative(portalURL: "https://05.teachub.workers.dev/", groupName: "Jio Server 2")
        }

        // Generic JavaScriptCore fallback with synchronous bridge for `streamBD.fetchUrl` & `streamBD.send`
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
                    let sem = DispatchSemaphore(value: 0)
                    var resultText = ""
                    Task {
                        resultText = (try? await NetworkManager.shared.fetchText(from: urlStr, headers: headers)) ?? ""
                        sem.signal()
                    }
                    _ = sem.wait(timeout: .now() + 20)
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
                continuation.resume(returning: emittedM3U)
            }
        }
    }

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
            guard let title = extractAttr(aAttrs, ##"href="#([^"]+)"##),
                  let dataName = extractAttr(aAttrs, #"data-name="([^"]+)""#),
                  let rawImg = extractAttr(imgAttrs, #"src="([^"]+)""#) else { continue }
            let imgUrl = rawImg.hasPrefix("http") ? rawImg : "\(baseUrl)/\(rawImg)"
            let body = "ch_name=\(dataName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dataName)".data(using: .utf8)
            let token = (try? await NetworkManager.shared.fetchText(
                from: "\(baseUrl)/token.php",
                headers: [
                    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                    "X-Requested-With": "XMLHttpRequest",
                    "User-Agent": ua,
                    "Referer": "\(baseUrl)/",
                    "Origin": baseUrl
                ],
                method: "POST",
                body: body
            ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "token_blank"

            let finalToken = token.isEmpty ? "token_blank" : token
            let streamUrl = "https://backend.plusbox.tv/\(dataName)/tracks-v1/index.fmp4.m3u8?token=\(finalToken)"
            let embedUrl = "https://backend.plusbox.tv/\(dataName)/embed.html?mute=false&autoplay=true&volume=50&token=\(finalToken)"
            m3u += "#EXTINF:-1 tvg-logo=\"\(imgUrl)\" group-title=\"PlusBox TV\",\(title)\n\(streamUrl)|User-Agent=\(ua)|Referer=\(embedUrl)|Origin=\(baseUrl)\n"
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
