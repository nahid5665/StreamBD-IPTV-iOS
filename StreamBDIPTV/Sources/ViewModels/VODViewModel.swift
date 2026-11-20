import Foundation

@MainActor
final class VODViewModel: ObservableObject {
    @Published var featuredMedia: TmdbMedia? = nil
    @Published var trendingMovies: [TmdbMedia] = []
    @Published var trendingTV: [TmdbMedia] = []
    @Published var top10Media: [TmdbMedia] = []
    @Published var banglaMovies: [TmdbMedia] = []
    @Published var bollywoodMovies: [TmdbMedia] = []
    @Published var searchResults: [TmdbMedia] = []
    @Published var addons: [Addon] = AppConfig.bundledAddons
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var selectedMedia: TmdbMedia? = nil

    // Live Per-Addon Resolution State
    @Published var addonStates: [String: AddonLookupState] = [:]
    @Published var availableStreams: [StreamSource] = []
    @Published var isResolvingAddons: Bool = false

    private var imdbIdCache: [Int: String] = [:]
    private var activeLookupTask: Task<Void, Never>? = nil

    private let customAddonsKey = "eentertainment_custom_addons_v2"
    private let disabledAddonsKey = "eentertainment_disabled_addons_v2"

    init() {
        loadAddons()
    }

    func loadAddons() {
        var list = AppConfig.bundledAddons
        if let data = UserDefaults.standard.data(forKey: customAddonsKey),
           let custom = try? JSONDecoder().decode([Addon].self, from: data) {
            list.append(contentsOf: custom)
        }
        let disabled = Set(UserDefaults.standard.stringArray(forKey: disabledAddonsKey) ?? [])
        for i in 0..<list.count {
            if disabled.contains(list[i].id) {
                list[i].enabled = false
            }
        }
        self.addons = list
    }

    func toggleAddon(id: String) {
        if let idx = addons.firstIndex(where: { $0.id == id }) {
            addons[idx].enabled.toggle()
            saveAddonPreferences()
        }
    }

    func addCustomStremioAddon(name: String, url: String) {
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = "stremio_\(UUID().uuidString.prefix(8))"
        let addon = Addon(id: id, name: name, url: clean, enabled: true, type: "stremio")
        addons.append(addon)
        saveCustomAddons()
    }

    func removeCustomAddon(id: String) {
        addons.removeAll { $0.id == id }
        saveCustomAddons()
        saveAddonPreferences()
    }

    private func saveCustomAddons() {
        let custom = addons.filter { $0.id.hasPrefix("stremio_") }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: customAddonsKey)
        }
    }

    private func saveAddonPreferences() {
        let disabled = addons.filter { !$0.enabled }.map { $0.id }
        UserDefaults.standard.set(disabled, forKey: disabledAddonsKey)
    }

    func loadCatalog() async {
        guard trendingMovies.isEmpty else { return }
        isLoading = true
        let key = AppConfig.tmdbApiKey
        let base = AppConfig.tmdbBaseURL

        async let tm: TmdbResponse<TmdbMedia>? = try? NetworkManager.shared.fetchDecodable(
            TmdbResponse<TmdbMedia>.self,
            from: "\(base)/trending/movie/week?api_key=\(key)&language=en-US"
        )
        async let tv: TmdbResponse<TmdbMedia>? = try? NetworkManager.shared.fetchDecodable(
            TmdbResponse<TmdbMedia>.self,
            from: "\(base)/trending/tv/week?api_key=\(key)&language=en-US"
        )
        async let bn: TmdbResponse<TmdbMedia>? = try? NetworkManager.shared.fetchDecodable(
            TmdbResponse<TmdbMedia>.self,
            from: "\(base)/discover/movie?api_key=\(key)&with_original_language=bn&sort_by=popularity.desc"
        )
        async let hi: TmdbResponse<TmdbMedia>? = try? NetworkManager.shared.fetchDecodable(
            TmdbResponse<TmdbMedia>.self,
            from: "\(base)/discover/movie?api_key=\(key)&with_original_language=hi&sort_by=popularity.desc"
        )
        async let top: TmdbResponse<TmdbMedia>? = try? NetworkManager.shared.fetchDecodable(
            TmdbResponse<TmdbMedia>.self,
            from: "\(base)/movie/top_rated?api_key=\(key)&language=en-US"
        )
        async let remoteAddons: [Addon]? = try? NetworkManager.shared.fetchDecodable(
            [Addon].self,
            from: AppConfig.addonRegistryURL
        )

        let loadedMovies = (await tm)?.results ?? []
        let loadedTV = (await tv)?.results ?? []
        self.trendingMovies = loadedMovies
        self.trendingTV = loadedTV
        self.banglaMovies = (await bn)?.results ?? []
        self.bollywoodMovies = (await hi)?.results ?? []
        self.top10Media = Array(((await top)?.results ?? loadedMovies).prefix(10))

        if let fetchedAddons = await remoteAddons, !fetchedAddons.isEmpty {
            for fa in fetchedAddons {
                if !self.addons.contains(where: { $0.id == fa.id }) {
                    self.addons.append(fa)
                }
            }
        }

        if self.featuredMedia == nil {
            self.featuredMedia = loadedMovies.first ?? loadedTV.first
        }
        isLoading = false
    }

    func search() async {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            searchResults = []
            return
        }
        let url = "\(AppConfig.tmdbBaseURL)/search/multi?api_key=\(AppConfig.tmdbApiKey)&query=\(encoded)"
        if let res = try? await NetworkManager.shared.fetchDecodable(TmdbResponse<TmdbMedia>.self, from: url) {
            searchResults = (res.results ?? []).filter { $0.backdrop_path != nil || $0.poster_path != nil }
        }
    }

    /// Fetches external IMDb ID (`tt...`) from TMDB
    func fetchExternalImdbId(tmdbId: Int, isTV: Bool) async -> String? {
        if let cached = imdbIdCache[tmdbId] { return cached }
        let endpoint = isTV ? "tv" : "movie"
        let url = "\(AppConfig.tmdbBaseURL)/\(endpoint)/\(tmdbId)/external_ids?api_key=\(AppConfig.tmdbApiKey)"
        guard let (data, resp) = try? await URLSession.shared.data(from: URL(string: url)!),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let imdb = json["imdb_id"] as? String, !imdb.isEmpty else {
            return nil
        }
        imdbIdCache[tmdbId] = imdb
        return imdb
    }

    /// Resolves all available BDIX FTP servers + Global stream sources for a title using all configured addons
    /// Updates `addonStates` and `availableStreams` in real time as each addon resolves
    func resolveStreams(for media: TmdbMedia, season: Int = 1, episode: Int = 1) async -> [StreamSource] {
        activeLookupTask?.cancel()

        isResolvingAddons = true
        availableStreams = []

        let isTV = !media.isMovie
        let id = media.id
        let year = media.displayDate

        let imdbId = await fetchExternalImdbId(tmdbId: id, isTV: isTV)
        let context = MediaLookupContext(
            tmdbId: id,
            imdbId: imdbId,
            title: media.displayTitle,
            year: year,
            isTV: isTV,
            season: season,
            episode: episode
        )

        let activeAddons = addons.filter { $0.enabled }

        // Initialize state to loading for each active addon
        var initialStates: [String: AddonLookupState] = [:]
        for a in activeAddons {
            initialStates[a.name] = .loading
        }
        self.addonStates = initialStates

        var allDiscoveredStreams: [StreamSource] = []

        await withTaskGroup(of: (String, AddonLookupState, [StreamSource]).self) { group in
            for addon in activeAddons {
                group.addTask {
                    do {
                        let streams = try await AddonResolverService.shared.resolve(addon: addon, context: context)
                        let state: AddonLookupState = streams.isEmpty ? .unavailable : .available(streams)
                        return (addon.name, state, streams)
                    } catch {
                        return (addon.name, .failed("Offline/Timeout"), [])
                    }
                }
            }

            for await (addonName, state, streams) in group {
                self.addonStates[addonName] = state
                if !streams.isEmpty {
                    self.availableStreams.append(contentsOf: streams)
                    allDiscoveredStreams.append(contentsOf: streams)
                }
            }
        }

        isResolvingAddons = false
        return allDiscoveredStreams
    }

    func cancelLookup() {
        activeLookupTask?.cancel()
        activeLookupTask = nil
        isResolvingAddons = false
    }

    func fetchTvSeasons(tvId: Int) async -> [TmdbSeason] {
        let url = "\(AppConfig.tmdbBaseURL)/tv/\(tvId)?api_key=\(AppConfig.tmdbApiKey)&language=en-US"
        guard let details = try? await NetworkManager.shared.fetchDecodable(TmdbTvShowDetails.self, from: url) else {
            return []
        }
        return (details.seasons ?? []).filter { ($0.season_number) > 0 }
    }

    func fetchSeasonEpisodes(tvId: Int, seasonNumber: Int) async -> [TmdbEpisode] {
        let url = "\(AppConfig.tmdbBaseURL)/tv/\(tvId)/season/\(seasonNumber)?api_key=\(AppConfig.tmdbApiKey)&language=en-US"
        guard let details = try? await NetworkManager.shared.fetchDecodable(TmdbSeasonDetailResponse.self, from: url) else {
            return []
        }
        return details.episodes ?? []
    }
}
