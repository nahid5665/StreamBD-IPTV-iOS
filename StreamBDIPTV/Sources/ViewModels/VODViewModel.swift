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

        let loadedMovies = (await tm)?.results ?? []
        let loadedTV = (await tv)?.results ?? []
        self.trendingMovies = loadedMovies
        self.trendingTV = loadedTV
        self.banglaMovies = (await bn)?.results ?? []
        self.bollywoodMovies = (await hi)?.results ?? []
        self.top10Media = Array(((await top)?.results ?? loadedMovies).prefix(10))

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

    /// Fetches all playable streams for a movie or TV episode (BDIX + Global Embeds)
    func resolveStreams(for media: TmdbMedia, season: Int = 1, episode: Int = 1) async -> [StreamSource] {
        var sources: [StreamSource] = []
        let isTV = !media.isMovie

        // 1. Live BDIX CineplexBD Scraping (Ultra fast in Bangladesh)
        let cineplexSources = await CineplexScraper.shared.resolveStreams(
            title: media.displayTitle,
            isTV: isTV,
            season: season,
            episode: episode
        )
        sources.append(contentsOf: cineplexSources)

        // 2. High-Speed Global Embed Streaming Servers
        let id = media.id
        if isTV {
            sources.append(StreamSource(
                url: "https://vidsrc.me/embed/tv?tmdb=\(id)&season=\(season)&episode=\(episode)",
                quality: "1080P",
                provider: "VidSrc HD (Server 2)",
                type: "embed"
            ))
            sources.append(StreamSource(
                url: "https://multiembed.mov/?video_id=\(id)&tmdb=1&s=\(season)&e=\(episode)",
                quality: "Multi-Server",
                provider: "MultiEmbed (Server 3)",
                type: "embed"
            ))
            sources.append(StreamSource(
                url: "https://superembed.stream/?video_id=\(id)&tmdb=1&s=\(season)&e=\(episode)",
                quality: "Auto",
                provider: "SuperEmbed (Server 4)",
                type: "embed"
            ))
        } else {
            sources.append(StreamSource(
                url: "https://vidsrc.me/embed/movie?tmdb=\(id)",
                quality: "1080P",
                provider: "VidSrc HD (Server 2)",
                type: "embed"
            ))
            sources.append(StreamSource(
                url: "https://multiembed.mov/?video_id=\(id)&tmdb=1",
                quality: "Multi-Server",
                provider: "MultiEmbed (Server 3)",
                type: "embed"
            ))
            sources.append(StreamSource(
                url: "https://superembed.stream/?video_id=\(id)&tmdb=1",
                quality: "Auto",
                provider: "SuperEmbed (Server 4)",
                type: "embed"
            ))
        }

        return sources
    }

    /// Fetches TV Show Seasons
    func fetchTvSeasons(tvId: Int) async -> [TmdbSeason] {
        let url = "\(AppConfig.tmdbBaseURL)/tv/\(tvId)?api_key=\(AppConfig.tmdbApiKey)&language=en-US"
        guard let details = try? await NetworkManager.shared.fetchDecodable(TmdbTvShowDetails.self, from: url) else {
            return [TmdbSeason(id: 1, name: "Season 1", season_number: 1, episode_count: 10)]
        }
        return (details.seasons ?? []).filter { $0.season_number > 0 }
    }

    /// Fetches TV Episodes for a season
    func fetchSeasonEpisodes(tvId: Int, seasonNumber: Int) async -> [TmdbEpisode] {
        let url = "\(AppConfig.tmdbBaseURL)/tv/\(tvId)/season/\(seasonNumber)?api_key=\(AppConfig.tmdbApiKey)&language=en-US"
        guard let res = try? await NetworkManager.shared.fetchDecodable(TmdbSeasonDetailResponse.self, from: url) else {
            return []
        }
        return res.episodes ?? []
    }
}
