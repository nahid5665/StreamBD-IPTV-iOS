import Foundation

@MainActor
final class VODViewModel: ObservableObject {
    @Published var trendingMovies: [TmdbMedia] = []
    @Published var trendingTV: [TmdbMedia] = []
    @Published var banglaMovies: [TmdbMedia] = []
    @Published var bollywoodMovies: [TmdbMedia] = []
    @Published var searchResults: [TmdbMedia] = []
    @Published var addons: [Addon] = []
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false

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
        async let addonList: [Addon]? = try? NetworkManager.shared.fetchDecodable(
            [Addon].self,
            from: AppConfig.addonRegistryURL
        )

        self.trendingMovies = (await tm)?.results ?? []
        self.trendingTV = (await tv)?.results ?? []
        self.banglaMovies = (await bn)?.results ?? []
        self.bollywoodMovies = (await hi)?.results ?? []
        self.addons = (await addonList) ?? []
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
            searchResults = res.results ?? []
        }
    }
}
