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
            self.addons = fetchedAddons
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

    /// Resolves all available BDIX FTP servers + Global stream sources for a title using all 24 addons
    func resolveStreams(for media: TmdbMedia, season: Int = 1, episode: Int = 1) async -> [StreamSource] {
        let isTV = !media.isMovie
        let id = media.id
        let year = media.displayDate

        return await BDIXAddonScraper.shared.resolveAllAddons(
            title: media.displayTitle,
            year: year,
            isTV: isTV,
            season: season,
            episode: episode,
            tmdbId: id
        )
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
