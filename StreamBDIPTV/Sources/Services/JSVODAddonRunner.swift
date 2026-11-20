import Foundation
import WebKit

// MARK: - Concurrency Limiter
/// Actor/Lock-based semaphore to cap concurrent headless WebKit executions (default 3)
final class ConcurrencyLimiter: @unchecked Sendable {
    private let maxConcurrent: Int
    private var currentCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()

    init(maxConcurrent: Int = 3) {
        self.maxConcurrent = maxConcurrent
    }

    func acquire() async {
        let shouldWait: Bool = {
            lock.lock()
            defer { lock.unlock() }
            if currentCount < maxConcurrent {
                currentCount += 1
                return false
            }
            return true
        }()

        if !shouldWait { return }

        await withCheckedContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }
            waiters.append(continuation)
        }
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            currentCount = max(0, currentCount - 1)
        }
    }
}

// MARK: - Native Fetch Bridge (WKScriptMessageHandlerWithReply)
/// Routes JavaScript fetch() calls to native URLSession, bypassing WebKit CORS and honoring custom headers.
final class NativeFetchBridge: NSObject, WKScriptMessageHandlerWithReply {
    private let defaultUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let dict = message.body as? [String: Any],
              let urlString = dict["url"] as? String,
              let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            replyHandler([
                "status": 400,
                "url": "",
                "headers": [String: String](),
                "body": "",
                "error": "Invalid URL"
            ], nil)
            return
        }

        let method = (dict["method"] as? String)?.uppercased() ?? "GET"
        let headers = (dict["headers"] as? [String: String]) ?? [:]
        let bodyStr = dict["body"] as? String

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8.0

        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(defaultUA, forHTTPHeaderField: "User-Agent")
        }
        if let bodyStr, !bodyStr.isEmpty, method != "GET" && method != "HEAD" {
            request.httpBody = bodyStr.data(using: .utf8)
        }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let httpResp = response as? HTTPURLResponse
                let statusCode = httpResp?.statusCode ?? 200
                let finalUrl = httpResp?.url?.absoluteString ?? urlString

                var respHeaders: [String: String] = [:]
                if let httpResp = httpResp {
                    for (k, v) in httpResp.allHeaderFields {
                        let keyStr = "\(k)".lowercased()
                        respHeaders[keyStr] = "\(v)"
                    }
                }

                let bodyText = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""

                let resultDict: [String: Any] = [
                    "status": statusCode,
                    "url": finalUrl,
                    "headers": respHeaders,
                    "body": bodyText
                ]
                await MainActor.run {
                    replyHandler(resultDict, nil)
                }
            } catch {
                let errorDict: [String: Any] = [
                    "status": 0,
                    "url": urlString,
                    "headers": [String: String](),
                    "body": "",
                    "error": error.localizedDescription
                ]
                await MainActor.run {
                    replyHandler(errorDict, nil)
                }
            }
        }
    }
}

// MARK: - Headless JS Instance (Isolated WKWebView)
@MainActor
private final class HeadlessJSInstance: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var bridge: NativeFetchBridge?
    private var didFinishContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
    }

    func setup(fetchBridge: NativeFetchBridge) async {
        self.bridge = fetchBridge
        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.addScriptMessageHandler(fetchBridge, contentWorld: .page, name: "nativeFetch")
        config.userContentController = ucc

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        await withCheckedContinuation { continuation in
            self.didFinishContinuation = continuation
            wv.loadHTMLString("<!DOCTYPE html><html><head><meta charset='utf-8'></head><body></body></html>", baseURL: URL(string: "http://localhost"))

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self, let cont = self.didFinishContinuation else { return }
                self.didFinishContinuation = nil
                cont.resume()
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.didFinishContinuation?.resume()
            self.didFinishContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.didFinishContinuation?.resume()
            self.didFinishContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.didFinishContinuation?.resume()
            self.didFinishContinuation = nil
        }
    }

    func execute(bootstrapScript: String, pluginScript: String, invokeScript: String, arguments: [String: Any]) async throws -> Any? {
        guard let wv = webView else { return nil }

        if !bootstrapScript.isEmpty {
            _ = try await wv.evaluateJavaScript(bootstrapScript)
        }

        let moduleWrapper = "var module = { exports: {} }; var exports = module.exports;\n" + pluginScript
        _ = try await wv.evaluateJavaScript(moduleWrapper)

        return try await wv.callAsyncJavaScript(invokeScript, arguments: arguments, in: nil, contentWorld: .page)
    }

    func destroy() {
        if let wv = webView {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.configuration.userContentController.removeScriptMessageHandler(forName: "nativeFetch", contentWorld: .page)
        }
        webView = nil
        bridge = nil
        didFinishContinuation = nil
    }
}

// MARK: - JSVODAddonRunner
/// Dynamic JavaScript VOD Plugin Host executing StreamBD `.js` addons inside isolated headless WebKit instances.
final class JSVODAddonRunner {
    static let shared = JSVODAddonRunner()

    private let limiter = ConcurrencyLimiter(maxConcurrent: 3)
    private var scriptCache: [String: String] = [:]
    private let cacheLock = NSLock()
    private var cryptoJsCache: String? = nil

    private init() {}

    // MARK: - Script Caching

    private func getCachedScript(for url: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return scriptCache[url]
    }

    private func cacheScript(_ script: String, for url: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        scriptCache[url] = script
    }

    func fetchScript(from urlString: String) async -> String? {
        if let cached = getCachedScript(for: urlString) {
            return cached
        }
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6.0
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return nil
        }
        cacheScript(text, for: urlString)
        return text
    }

    private func loadCryptoJs() -> String {
        if let cached = cryptoJsCache { return cached }
        if let url = Bundle.main.url(forResource: "crypto-js.min", withExtension: "js") ?? Bundle.main.url(forResource: "crypto-js", withExtension: "js"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            cryptoJsCache = text
            return text
        }
        return ""
    }

    // MARK: - Execution

    func resolveStreams(addon: Addon, context: MediaLookupContext) async throws -> [StreamSource] {
        guard let pluginScript = await fetchScript(from: addon.url) else {
            return []
        }

        await limiter.acquire()
        defer {
            limiter.release()
        }

        return try await withTimeout(seconds: 10.0) {
            return try await self.executePlugin(script: pluginScript, addon: addon, context: context)
        }
    }

    @MainActor
    private func executePlugin(script: String, addon: Addon, context: MediaLookupContext) async throws -> [StreamSource] {
        let instance = HeadlessJSInstance()
        let bridge = NativeFetchBridge()
        await instance.setup(fetchBridge: bridge)

        defer {
            instance.destroy()
        }

        let cryptoJs = loadCryptoJs()
        let bootstrap = """
        \(cryptoJs)

        window.__nativeFetchActive = true;
        if (typeof window.process === 'undefined') {
            window.process = { env: {} };
        }

        // Lightweight DOMParser-backed cheerio shim
        var cheerio = {
            load: function(htmlStr) {
                var parser = new DOMParser();
                var doc = parser.parseFromString(htmlStr || '', 'text/html');
                var wrap = function(nodes) {
                    var arr = Array.from(nodes || []);
                    arr.text = function() { return arr.map(function(n) { return n.textContent || ''; }).join(' ').trim(); };
                    arr.html = function() { return arr.map(function(n) { return n.innerHTML || ''; }).join(''); };
                    arr.attr = function(name) { return arr.length > 0 ? (arr[0].getAttribute ? arr[0].getAttribute(name) : arr[0][name]) : null; };
                    arr.each = function(fn) { arr.forEach(function(el, idx) { fn.call(el, idx, el); }); return arr; };
                    arr.find = function(sel) {
                        var res = [];
                        arr.forEach(function(n) { if (n.querySelectorAll) { res.push.apply(res, n.querySelectorAll(sel)); } });
                        return wrap(res);
                    };
                    arr.first = function() { return wrap(arr.slice(0, 1)); };
                    arr.last = function() { return wrap(arr.slice(-1)); };
                    arr.eq = function(i) { return wrap(arr.slice(i, i + 1)); };
                    return arr;
                };
                var $ = function(selector) {
                    if (!selector) return wrap([]);
                    if (typeof selector === 'object') return wrap([selector]);
                    try {
                        return wrap(doc.querySelectorAll(selector));
                    } catch(e) {
                        return wrap([]);
                    }
                };
                $.html = function() { return doc.documentElement ? doc.documentElement.outerHTML : ''; };
                return $;
            }
        };

        // Fetch-backed axios shim
        var axios = {
            get: async function(url, config) {
                var res = await window.fetch(url, { method: 'GET', headers: config && config.headers });
                var text = await res.text();
                var data = text;
                try { data = JSON.parse(text); } catch(e) {}
                return { data: data, status: res.status, headers: res.headers, ok: res.ok };
            },
            post: async function(url, body, config) {
                var res = await window.fetch(url, {
                    method: 'POST',
                    headers: config && config.headers,
                    body: typeof body === 'object' ? JSON.stringify(body) : body
                });
                var text = await res.text();
                var data = text;
                try { data = JSON.parse(text); } catch(e) {}
                return { data: data, status: res.status, headers: res.headers, ok: res.ok };
            }
        };

        // Standard Buffer shim with proper base64 encode/decode
        window.Buffer = {
            from: function(data, encoding) {
                var str = (data !== null && data !== undefined) ? String(data) : '';
                return {
                    toString: function(enc) {
                        if (enc === 'base64') {
                            try { return btoa(str); } catch(e) { return ''; }
                        } else if (encoding === 'base64') {
                            try { return atob(str); } catch(e) { return str; }
                        }
                        return str;
                    }
                };
            },
            isBuffer: function() { return false; }
        };

        // Universal Module Require Shim
        window.require = function(mod) {
            if (mod === 'crypto-js' && typeof window.CryptoJS !== 'undefined') {
                return window.CryptoJS;
            }
            if (mod === 'cheerio') {
                return cheerio;
            }
            if (mod === 'axios') {
                return axios;
            }
            return {};
        };

        // Native URLSession Fetch Bridge
        window.fetch = async function(input, init) {
            try {
                var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
                var method = (init && init.method) ? init.method : 'GET';
                var headers = (init && init.headers) ? init.headers : {};
                var body = null;
                if (init && init.body) {
                    body = (typeof init.body === 'string') ? init.body : JSON.stringify(init.body);
                }

                var res = await window.webkit.messageHandlers.nativeFetch.postMessage({
                    url: url,
                    method: method,
                    headers: headers,
                    body: body
                });

                var status = (res && typeof res.status === 'number') ? res.status : 200;
                var resHeaders = (res && res.headers) ? res.headers : {};
                var resBody = (res && typeof res.body === 'string') ? res.body : '';
                var resUrl = (res && res.url) ? res.url : url;

                return {
                    ok: status >= 200 && status < 300,
                    status: status,
                    url: resUrl,
                    headers: {
                        get: function(k) {
                            if (!k) return null;
                            var lower = String(k).toLowerCase();
                            for (var key in resHeaders) {
                                if (key.toLowerCase() === lower) return resHeaders[key];
                            }
                            return null;
                        }
                    },
                    text: async function() { return resBody; },
                    json: async function() {
                        try { return JSON.parse(resBody || '{}'); }
                        catch(e) { return {}; }
                    }
                };
            } catch (err) {
                return {
                    ok: false,
                    status: 0,
                    url: typeof input === 'string' ? input : '',
                    headers: { get: function() { return null; } },
                    text: async function() { return ''; },
                    json: async function() { return {}; }
                };
            }
        };
        """

        let invoke = """
        var runner = null;
        if (typeof module.exports === 'function') {
            runner = module.exports;
        } else if (module.exports && typeof module.exports.getStreams === 'function') {
            runner = module.exports.getStreams;
        } else if (typeof window.getStreams === 'function') {
            runner = window.getStreams;
        } else if (typeof getStreams === 'function') {
            runner = getStreams;
        }

        if (!runner) {
            return { error: 'No exported stream function found' };
        }

        try {
            var res = await runner(argType, argTmdbId, argSeason, argEpisode);
            if (res && Array.isArray(res)) {
                return res;
            } else if (res) {
                return [res];
            }
            return [];
        } catch(err) {
            return { error: String(err && err.message ? err.message : err) };
        }
        """

        let args: [String: Any] = [
            "argType": context.isTV ? "tv" : "movie",
            "argTmdbId": context.tmdbId,
            "argSeason": context.season ?? 1,
            "argEpisode": context.episode ?? 1
        ]

        let rawResult = try await instance.execute(
            bootstrapScript: bootstrap,
            pluginScript: script,
            invokeScript: invoke,
            arguments: args
        )

        return parseStreamSources(from: rawResult, addon: addon)
    }

    private func parseStreamSources(from rawResult: Any?, addon: Addon) -> [StreamSource] {
        if let dict = rawResult as? [String: Any], let errorMsg = dict["error"] as? String {
            print("[JSVODAddonRunner] Addon '\(addon.name)' JS runtime error: \(errorMsg)")
            return []
        }

        guard let array = rawResult as? [Any] else { return [] }
        var results: [StreamSource] = []

        for item in array {
            guard let dict = item as? [String: Any],
                  let urlString = (dict["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !urlString.isEmpty,
                  let url = URL(string: urlString),
                  url.scheme == "http" || url.scheme == "https" else {
                continue
            }

            let rawQuality = (dict["quality"] as? String)
                ?? (dict["resolution"] as? String)
                ?? "HD"
            let quality = rawQuality.trimmingCharacters(in: .whitespacesAndNewlines)

            let rawProvider = (dict["provider"] as? String)
                ?? (dict["name"] as? String)
                ?? (dict["title"] as? String)
                ?? addon.name
            let providerLabel = rawProvider.contains(addon.name) ? rawProvider : "\(addon.name) (\(rawProvider))"

            let streamType = (dict["type"] as? String) ?? "direct"

            var headers: [String: String] = [:]
            if let h = dict["headers"] as? [String: Any] {
                for (k, v) in h {
                    headers[k] = "\(v)"
                }
            }

            let lowerUrl = urlString.lowercased()
            let needsVLC = lowerUrl.contains(".mkv") || lowerUrl.contains(".avi") || lowerUrl.contains(".ts") || lowerUrl.contains(".flv")

            results.append(StreamSource(
                url: urlString,
                quality: quality,
                provider: providerLabel,
                type: streamType,
                headers: headers.isEmpty ? nil : headers,
                preferVLC: needsVLC
            ))
        }

        return results
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
