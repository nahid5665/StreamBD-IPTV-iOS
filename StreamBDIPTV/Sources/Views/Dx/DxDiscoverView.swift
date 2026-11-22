import SwiftUI

// MARK: - Discover (dx.bi's DiscoverView): every catalog by type, catalog and genre

struct DxDiscoverView: View {
    @ObservedObject var mainVM: MainViewModel
    @ObservedObject var vodVM: VODViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Type", selection: $type) {
                    Text("Movies").tag("movie")
                    Text("TV Shows").tag("series")
                    Text("Live TV").tag("live")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                switch type {
                case "live": liveTV
                default:
                    DxCatalogGrid(kind: type, fixedName: nil)
                        .id(type) // a fresh grid per Movies / TV Shows so its catalog reloads
                }
            }
            .padding(.bottom, 30)
        }
        .background(Dx.background.ignoresSafeArea())
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.large)
    }

    @State private var type = "movie"

    /** The BDTube server's channels: category chips + the grid (dx.bi's catalog pickers) */
    @ViewBuilder
    private var liveTV: some View {
        let groups = ["All"] + Set(mainVM.allChannels.map { $0.group }).sorted()
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(groups, id: \.self) { grp in
                        Button { group = grp } label: {
                            Text(grp)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .foregroundStyle(group == grp ? .black : .white)
                                .background(group == grp ? AnyShapeStyle(.white) : AnyShapeStyle(.clear), in: .capsule)
                                .dxGlass(interactive: true, hidden: group == grp, in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            if mainVM.allChannels.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(60)
            } else {
                DxChannelGrid(channels: filtered, onPlay: { ch in activeChannel = ch })
            }
        }
        .sheet(item: $activeChannel) { ch in
            StreamPlayerSheet(channel: ch)
        }
    }

    @State private var group = "All"
    @State private var activeChannel: Channel? = nil

    private var filtered: [Channel] {
        group == "All" ? mainVM.allChannels : mainVM.allChannels.filter { $0.group == group }
    }
}

// MARK: - One catalog's posters, with its catalog chips (Movies / TV Shows)

struct DxCatalogGrid: View {
    var kind: String
    var fixedName: String?

    @State private var items: [TmdbMedia] = []
    @State private var page = 1
    @State private var loading = false
    @State private var catalog: String = ""

    private struct CatalogSpec {
        let name: String
        let path: String
    }

    private var catalogs: [CatalogSpec] {
        if kind == "series" {
            return [
                CatalogSpec(name: "Popular", path: "tv/popular"),
                CatalogSpec(name: "Trending", path: "trending/tv/week"),
                CatalogSpec(name: "Top Rated", path: "tv/top_rated"),
                CatalogSpec(name: "Airing Today", path: "tv/airing_today")
            ]
        }
        return [
            CatalogSpec(name: "Popular", path: "movie/popular"),
            CatalogSpec(name: "Trending", path: "trending/movie/week"),
            CatalogSpec(name: "Top Rated", path: "movie/top_rated"),
            CatalogSpec(name: "Bangla", path: "discover/movie?with_original_language=bn&sort_by=popularity.desc"),
            CatalogSpec(name: "Bollywood", path: "discover/movie?with_original_language=hi&sort_by=popularity.desc")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if fixedName == nil {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(catalogs, id: \.name) { spec in
                            Button { load(spec) } label: {
                                Text(spec.name)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .foregroundStyle(catalog == spec.path ? .black : .white)
                                    .background(catalog == spec.path ? AnyShapeStyle(.white) : AnyShapeStyle(.clear), in: .capsule)
                                    .dxGlass(interactive: true, hidden: catalog == spec.path, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }

            if items.isEmpty && loading {
                ProgressView().frame(maxWidth: .infinity).padding(60)
            } else if items.isEmpty {
                DxEmptyState(title: "Nothing here", systemImage: "square.grid.2x2", description: "This catalog has nothing for that choice.")
                    .padding(.top, 30)
            } else {
                DxPosterGrid(items: items, onEnd: { loadMore() })
                if loading { ProgressView().frame(maxWidth: .infinity).padding() }
            }
        }
        .onAppear { if catalog.isEmpty { load(catalogs[0]) } }
    }

    private func load(_ spec: CatalogSpec) {
        catalog = spec.path
        page = 1
        items = []
        fetch()
    }

    private func loadMore() {
        guard !loading else { return }
        page += 1
        fetch()
    }

    private func fetch() {
        let sep = catalog.path.contains("?") ? "&" : "?"
        let urlString = "\(AppConfig.tmdbBaseURL)/\(catalog.path)\(sep)api_key=\(AppConfig.tmdbApiKey)&page=\(page)"
        guard !loading, let url = URL(string: urlString) else { return }
        loading = true
        Task {
            defer { loading = false }
            if let res = try? await NetworkManager.shared.fetchDecodable(TmdbResponse<TmdbMedia>.self, from: url.absoluteString) {
                let fresh = (res.results ?? []).filter { $0.poster_path != nil }
                items = page == 1 ? fresh : (items + fresh)
            }
        }
    }
}
