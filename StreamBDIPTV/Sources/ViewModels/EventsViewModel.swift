import Foundation

@MainActor
final class EventsViewModel: ObservableObject {
    @Published var events: [SportzfyEvent] = []
    @Published var selectedSport: String = "All"
    @Published var liveOnly: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    var availableSports: [String] {
        let sports = Set(events.compactMap { $0.sport }.filter { !$0.isEmpty }).sorted()
        return ["All"] + sports
    }

    var filteredEvents: [SportzfyEvent] {
        events.filter { ev in
            let matchesSport = (selectedSport == "All") || (ev.sport?.localizedCaseInsensitiveCompare(selectedSport) == .orderedSame)
            let matchesLive = !liveOnly || ev.isLiveNow
            return matchesSport && matchesLive
        }
    }

    func loadEvents() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await NetworkManager.shared.fetchDecodable(
                SportzfyApiResponse.self,
                from: AppConfig.liveEventsApiURL
            )
            self.events = response.events ?? []
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Mirrors `Ly6/c->d`: constructs `{baseDir}/{event.id}/{fileName}` (`.../api/all/events/{id}/index.enc`)
    func fetchEventChannel(for event: SportzfyEvent) async -> Channel? {
        let baseUrl = AppConfig.liveEventsApiURL
        guard let slashIdx = baseUrl.lastIndex(of: "/") else { return nil }
        let baseDir = String(baseUrl[..<slashIdx])
        let fileName = String(baseUrl[baseUrl.index(after: slashIdx)...])
        let streamEndpoint = "\(baseDir)/\(event.id)/\(fileName)"

        do {
            let response = try await NetworkManager.shared.fetchDecodable(
                SportzfyStreamResponse.self,
                from: streamEndpoint
            )
            guard let streams = response.streams, !streams.isEmpty else { return nil }

            var sourcesMap: [String: String] = [:]
            for (idx, st) in streams.enumerated() {
                guard let sUrl = st.stream_url, !sUrl.isEmpty else { continue }
                let label = (st.label?.isEmpty == false) ? st.label! : "Source \(idx + 1)"
                var finalUrl = sUrl
                if let kid = st.drm_kid, let key = st.drm_key, !kid.isEmpty, !key.isEmpty {
                    finalUrl += "|drm-type=clearkey|drm-key=\(kid):\(key)"
                }
                sourcesMap[label] = finalUrl
            }

            guard let firstRaw = sourcesMap.values.first else { return nil }
            let parsed = M3UParser.parseUrlHeaders(firstRaw)
            return Channel(
                name: event.displayTitle,
                url: parsed.cleanUrl,
                logo: event.league_icon ?? event.team_a_logo ?? "",
                group: event.league ?? event.sport ?? "Live Event",
                userAgent: parsed.headers["User-Agent"],
                cookie: parsed.headers["Cookie"],
                httpReferer: parsed.headers["Referer"],
                origin: parsed.headers["Origin"],
                httpHeaders: parsed.headers,
                isLiveEvent: true,
                sources: sourcesMap
            )
        } catch {
            return nil
        }
    }
}
