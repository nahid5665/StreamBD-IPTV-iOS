import SwiftUI

/// On-device addon diagnostics: probes cineplexbd.net reachability, runs the
/// native scraper and the JS fallback for a known title, and shows every
/// pipeline log line so failures can be pinpointed without a Mac.
struct AddonDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logText: String = AddonDebugLog.shared.text
    @State private var isRunning: Bool = false
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(logText.isEmpty ? "No diagnostics yet.\nTap 'Run Cineplex Test' below." : logText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Addon Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = logText
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        AddonDebugLog.shared.clear()
                        logText = ""
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    runDiagnostics()
                } label: {
                    HStack(spacing: 8) {
                        if isRunning {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "stethoscope")
                        }
                        Text(isRunning ? "Running…" : "Run Cineplex Test")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .foregroundStyle(.white)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(isRunning)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .onReceive(refreshTimer) { _ in
                logText = AddonDebugLog.shared.text
            }
            .onAppear {
                logText = AddonDebugLog.shared.text
            }
        }
        .preferredColorScheme(.dark)
    }

    private func runDiagnostics() {
        isRunning = true
        Task { @MainActor in
            addonLog("======== DIAGNOSTICS RUN START ========")

            // 1. Raw reachability probes (network vs parsing failure)
            await probe(urlString: "http://cineplexbd.net", label: "homepage")
            await probe(urlString: "http://cineplexbd.net/search.php?q=Inception", label: "search")

            // 2. Native 2-step scraper (same path the addon resolution uses)
            addonLog("[Diagnostics] running native CineplexScraper for 'Inception'…")
            let streams = await CineplexScraper.shared.resolveStreams(
                title: "Inception", isTV: false, season: 1, episode: 1
            )
            addonLog("[Diagnostics] native scraper -> \(streams.count) stream(s)")
            for s in streams {
                addonLog("[Diagnostics]   [\(s.quality ?? "-")] \(s.provider ?? "-") :: \(s.url)")
            }

            // 3. JS fallback (cineplexbd.js through the WebView fetch bridge)
            if streams.isEmpty {
                addonLog("[Diagnostics] native returned 0 — running JS fallback (cineplexbd.js)…")
                if let addon = AppConfig.bundledAddons.first(where: { $0.id.lowercased().contains("cineplex") }) {
                    let ctx = MediaLookupContext(
                        tmdbId: 27205, imdbId: nil, title: "Inception", year: "2010",
                        isTV: false, season: 1, episode: 1
                    )
                    let jsStreams = (try? await JSVODAddonRunner.shared.resolveStreams(addon: addon, context: ctx)) ?? []
                    addonLog("[Diagnostics] JS runner -> \(jsStreams.count) stream(s)")
                    for s in jsStreams {
                        addonLog("[Diagnostics]   [\(s.quality ?? "-")] \(s.url)")
                    }
                }
            }

            addonLog("======== DIAGNOSTICS RUN END ========")
            logText = AddonDebugLog.shared.text
            isRunning = false
        }
    }

    private func probe(urlString: String, label: String) async {
        guard let url = URL(string: urlString) else {
            addonLog("[Diagnostics] \(label): invalid URL \(urlString)")
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let start = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            addonLog("[Diagnostics] \(label) \(urlString) -> HTTP \(code), \(data.count) bytes, \(ms)ms")
        } catch {
            addonLog("[Diagnostics] \(label) \(urlString) -> ERROR \(error.localizedDescription)")
        }
    }
}
