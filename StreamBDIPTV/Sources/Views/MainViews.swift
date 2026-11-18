import SwiftUI
import AVKit
import WebKit

// MARK: - Liquid Glass Styles & View Modifiers

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var opacity: Double = 0.65

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(opacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.08),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 6)
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 16, opacity: Double = 0.65) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, opacity: opacity))
    }
}

// MARK: - Web Stream Player (For Embeds)

struct WebStreamPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        webView.load(req)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Netflix Main Container

struct ContentView: View {
    @StateObject private var mainViewModel = MainViewModel()
    @StateObject private var vodViewModel = VODViewModel()
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            Group {
                switch selectedTab {
                case 0:
                    NetflixHomeView(vodVM: vodViewModel, liveVM: mainViewModel)
                case 1:
                    LiveTVNetflixView(viewModel: mainViewModel)
                case 2:
                    EventsNetflixView()
                case 3:
                    NetflixSearchView(vodVM: vodViewModel, liveVM: mainViewModel)
                default:
                    NetflixHomeView(vodVM: vodViewModel, liveVM: mainViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Liquid Glass Floating Bottom Navigation
            floatingGlassTabBar
        }
        .preferredColorScheme(.dark)
        .task {
            if mainViewModel.allChannels.isEmpty {
                await mainViewModel.loadAllLiveChannels()
            }
            if vodViewModel.trendingMovies.isEmpty {
                await vodViewModel.loadCatalog()
            }
        }
    }

    private var floatingGlassTabBar: some View {
        HStack(spacing: 24) {
            tabButton(title: "Home", icon: "house.fill", tabIndex: 0)
            tabButton(title: "Live TV", icon: "tv.fill", tabIndex: 1)
            tabButton(title: "Sports", icon: "sportscourt.fill", tabIndex: 2)
            tabButton(title: "Search", icon: "magnifyingglass", tabIndex: 3)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .liquidGlass(cornerRadius: 32, opacity: 0.85)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func tabButton(title: String, icon: String, tabIndex: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedTab = tabIndex
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: selectedTab == tabIndex ? .bold : .regular))
                    .foregroundStyle(selectedTab == tabIndex ? Color.red : Color.gray)
                Text(title)
                    .font(.system(size: 10, weight: selectedTab == tabIndex ? .bold : .medium))
                    .foregroundStyle(selectedTab == tabIndex ? Color.white : Color.gray)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Netflix Home View

struct NetflixHomeView: View {
    @ObservedObject var vodVM: VODViewModel
    @ObservedObject var liveVM: MainViewModel

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    // Netflix Spotlight Hero
                    if let featured = vodVM.featuredMedia {
                        NetflixHeroBanner(media: featured, vodVM: vodVM)
                    }

                    // Top 10 Row (Ranked Numbers 1..10)
                    if !vodVM.top10Media.isEmpty {
                        NetflixTop10Row(title: "Top 10 Today in Bangladesh", items: vodVM.top10Media, vodVM: vodVM)
                    }

                    // Trending Movies Row
                    if !vodVM.trendingMovies.isEmpty {
                        NetflixMediaRow(title: "Trending Movies", items: vodVM.trendingMovies, vodVM: vodVM)
                    }

                    // Popular TV Shows Row
                    if !vodVM.trendingTV.isEmpty {
                        NetflixMediaRow(title: "Popular TV Shows", items: vodVM.trendingTV, vodVM: vodVM)
                    }

                    // Bengali Blockbusters (BDIX & Local)
                    if !vodVM.banglaMovies.isEmpty {
                        NetflixMediaRow(title: "Bengali Blockbusters & BDIX", items: vodVM.banglaMovies, vodVM: vodVM)
                    }

                    // Live Channels Quick Bar (Akash / Toffee / Sony)
                    if !liveVM.allChannels.isEmpty {
                        NetflixLiveChannelsRow(channels: Array(liveVM.allChannels.prefix(15)), liveVM: liveVM)
                    }

                    // Bollywood Hits
                    if !vodVM.bollywoodMovies.isEmpty {
                        NetflixMediaRow(title: "Bollywood & Hindi Hits", items: vodVM.bollywoodMovies, vodVM: vodVM)
                    }

                    Spacer(minLength: 90)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .safeAreaInset(edge: .top) {
                netflixTopHeader
            }
            .sheet(item: $vodVM.selectedMedia) { media in
                NetflixMediaDetailSheet(media: media, vodVM: vodVM)
            }
            .sheet(item: $liveVM.activeChannel) { channel in
                StreamPlayerSheet(channel: channel)
            }
        }
    }

    private var netflixTopHeader: some View {
        HStack {
            // Netflix Red "N" Logo Badge
            Text("NETFLIX")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.red, Color(red: 0.7, green: 0, blue: 0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Spacer()

            HStack(spacing: 18) {
                Text("TV Shows").font(.subheadline.weight(.semibold))
                Text("Movies").font(.subheadline.weight(.semibold))
                Text("Categories").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.85), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - Netflix Hero Banner

struct NetflixHeroBanner: View {
    let media: TmdbMedia
    @ObservedObject var vodVM: VODViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: URL(string: media.backdropURL)) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 480)
            .clipped()

            // Dark Vignette Gradients
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: .black.opacity(0.6), location: 0.7),
                    .init(color: .black, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content info & Buttons
            VStack(spacing: 12) {
                Text(media.displayTitle)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 10, x: 0, y: 4)
                    .padding(.horizontal, 20)

                HStack(spacing: 8) {
                    Text("BDIX Fast").font(.caption.bold()).foregroundStyle(.red)
                    Text("•").foregroundStyle(.gray)
                    Text(media.isMovie ? "Movie" : "Series").font(.caption.weight(.medium))
                    Text("•").foregroundStyle(.gray)
                    Text(media.displayDate).font(.caption.weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.85))

                HStack(spacing: 16) {
                    Button {
                        vodVM.selectedMedia = media
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill").font(.headline)
                            Text("Play").font(.headline.bold())
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 11)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Button {
                        vodVM.selectedMedia = media
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle").font(.headline)
                            Text("More Info").font(.headline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .liquidGlass(cornerRadius: 8, opacity: 0.6)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 16)
        }
        .frame(height: 480)
    }
}

// MARK: - Netflix Top 10 Row (With Large Numbers)

struct NetflixTop10Row: View {
    let title: String
    let items: [TmdbMedia]
    @ObservedObject var vodVM: VODViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            vodVM.selectedMedia = item
                        } label: {
                            HStack(alignment: .bottom, spacing: -24) {
                                // Huge Netflix Rank Number (1, 2, 3...)
                                Text("\(index + 1)")
                                    .font(.system(size: 96, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.black)
                                    .overlay(
                                        Text("\(index + 1)")
                                            .font(.system(size: 96, weight: .black, design: .rounded))
                                            .foregroundColor(.clear)
                                            .overlay(
                                                Text("\(index + 1)")
                                                    .font(.system(size: 96, weight: .black, design: .rounded))
                                                    .foregroundColor(Color.gray.opacity(0.9))
                                            )
                                    )
                                    .offset(y: 10)
                                    .zIndex(1)

                                AsyncImage(url: URL(string: item.posterURL)) { phase in
                                    if let img = phase.image {
                                        img.resizable().scaledToFill()
                                    } else {
                                        Color.gray.opacity(0.3)
                                    }
                                }
                                .frame(width: 115, height: 165)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .liquidGlass(cornerRadius: 10, opacity: 0.2)
                            }
                            .padding(.trailing, 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Netflix Standard Media Row

struct NetflixMediaRow: View {
    let title: String
    let items: [TmdbMedia]
    @ObservedObject var vodVM: VODViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            vodVM.selectedMedia = item
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: URL(string: item.posterURL)) { phase in
                                    if let img = phase.image {
                                        img.resizable().scaledToFill()
                                    } else {
                                        Color.gray.opacity(0.3)
                                            .overlay(Image(systemName: "film"))
                                    }
                                }
                                .frame(width: 120, height: 175)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .liquidGlass(cornerRadius: 10, opacity: 0.2)

                                Text(item.displayTitle)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                    .frame(width: 120, alignment: .leading)
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Netflix Live Channels Quick Row

struct NetflixLiveChannelsRow: View {
    let channels: [Channel]
    @ObservedObject var liveVM: MainViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live TV Channels (StreamBD)").font(.title3.bold()).foregroundStyle(.white)
                Spacer()
                Text("See All").font(.subheadline.bold()).foregroundStyle(.red)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(channels) { channel in
                        Button {
                            liveVM.activeChannel = channel
                        } label: {
                            VStack(spacing: 8) {
                                AsyncImage(url: URL(string: channel.logo)) { phase in
                                    if let img = phase.image {
                                        img.resizable().scaledToFit()
                                    } else {
                                        Image(systemName: "tv.fill").font(.title2).foregroundStyle(.red)
                                    }
                                }
                                .frame(width: 50, height: 50)
                                .padding(8)

                                Text(channel.name)
                                    .font(.system(size: 11, weight: .bold))
                                    .lineLimit(1)
                                    .frame(width: 80)
                                    .foregroundStyle(.white)
                            }
                            .padding(10)
                            .liquidGlass(cornerRadius: 14, opacity: 0.4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Netflix Media Detail Sheet (Stream Player with CineplexBD)

struct NetflixMediaDetailSheet: View {
    let media: TmdbMedia
    @ObservedObject var vodVM: VODViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var availableStreams: [StreamSource] = []
    @State private var selectedStream: StreamSource? = nil
    @State private var isLoadingStreams = true
    @State private var isPlayingDirect = false
    @State private var isPlayingEmbed = false
    @State private var selectedSeason = 1
    @State private var selectedEpisode = 1
    @State private var seasons: [TmdbSeason] = []
    @State private var episodes: [TmdbEpisode] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header Backdrop
                    ZStack(alignment: .bottomLeading) {
                        AsyncImage(url: URL(string: media.backdropURL)) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else {
                                Color.gray.opacity(0.3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipped()

                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(media.displayTitle)
                                .font(.title2.bold())
                                .foregroundStyle(.white)

                            HStack(spacing: 10) {
                                Text("98% Match").font(.caption.bold()).foregroundStyle(.green)
                                Text(media.displayDate).font(.caption).foregroundStyle(.gray)
                                Text("HD").font(.caption2.bold()).padding(.horizontal, 4).padding(.vertical, 2).background(Color.gray.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 4))
                                Text("BDIX Ready").font(.caption2.bold()).padding(.horizontal, 4).padding(.vertical, 2).background(Color.red.opacity(0.8)).clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(16)
                    }

                    // Main Action Play Button
                    Button {
                        if let first = availableStreams.first {
                            playSource(first)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill").font(.headline)
                            Text("Play").font(.headline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.horizontal, 16)

                    // Synopsis Overview
                    if let overview = media.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineSpacing(4)
                            .padding(.horizontal, 16)
                    }

                    // TV Series Seasons & Episodes Picker
                    if !media.isMovie {
                        tvSeriesSection
                    }

                    // Available Streaming Servers (CineplexBD BDIX + Global)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Streaming Servers & BDIX Sources").font(.headline).foregroundStyle(.white)
                            .padding(.horizontal, 16)

                        if isLoadingStreams {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Searching CineplexBD & Streaming Addons…").font(.caption).foregroundStyle(.gray)
                            }
                            .padding(.horizontal, 16)
                        } else if availableStreams.isEmpty {
                            Text("No stream sources found on current Wi-Fi.").font(.caption).foregroundStyle(.red)
                                .padding(.horizontal, 16)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(availableStreams) { source in
                                    Button {
                                        playSource(source)
                                    } label: {
                                        HStack {
                                            Image(systemName: source.type == "direct" ? "bolt.fill" : "globe")
                                                .foregroundStyle(source.type == "direct" ? .green : .orange)
                                            VStack(alignment: .leading) {
                                                Text(source.provider ?? "Server").font(.subheadline.bold()).foregroundStyle(.white)
                                                Text(source.quality ?? "1080P").font(.caption).foregroundStyle(.gray)
                                            }
                                            Spacer()
                                            Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(.red)
                                        }
                                        .padding(12)
                                        .liquidGlass(cornerRadius: 10, opacity: 0.35)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(.white)
                }
            }
            .task {
                await loadStreams()
            }
            .sheet(isPresented: $isPlayingDirect) {
                if let stream = selectedStream, let url = URL(string: stream.url) {
                    NativeVideoPlayerSheet(url: url, title: media.displayTitle, headers: stream.headers ?? [:])
                }
            }
            .sheet(isPresented: $isPlayingEmbed) {
                if let stream = selectedStream, let url = URL(string: stream.url) {
                    WebPlayerSheet(url: url, title: media.displayTitle)
                }
            }
        }
    }

    private var tvSeriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Season \(selectedSeason)").font(.headline).foregroundStyle(.white)
                Spacer()
                Menu {
                    ForEach(seasons) { s in
                        Button("Season \(s.season_number)") {
                            selectedSeason = s.season_number
                            Task {
                                episodes = await vodVM.fetchSeasonEpisodes(tvId: media.id, seasonNumber: s.season_number)
                                await loadStreams()
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Select Season")
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption.bold())
                    .padding(8)
                    .liquidGlass(cornerRadius: 8, opacity: 0.5)
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(episodes) { ep in
                        Button {
                            selectedEpisode = ep.episode_number
                            Task { await loadStreams() }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: URL(string: ep.stillURL)) { phase in
                                    if let img = phase.image {
                                        img.resizable().scaledToFill()
                                    } else {
                                        Color.gray.opacity(0.3)
                                    }
                                }
                                .frame(width: 140, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Text("EP \(ep.episode_number): \(ep.name ?? "Episode")")
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                    .frame(width: 140, alignment: .leading)
                                    .foregroundStyle(selectedEpisode == ep.episode_number ? .red : .white)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func loadStreams() async {
        isLoadingStreams = true
        if !media.isMovie && seasons.isEmpty {
            seasons = await vodVM.fetchTvSeasons(tvId: media.id)
            if let first = seasons.first {
                selectedSeason = first.season_number
                episodes = await vodVM.fetchSeasonEpisodes(tvId: media.id, seasonNumber: first.season_number)
            }
        }
        availableStreams = await vodVM.resolveStreams(for: media, season: selectedSeason, episode: selectedEpisode)
        isLoadingStreams = false
    }

    private func playSource(_ source: StreamSource) {
        selectedStream = source
        if source.type == "embed" {
            isPlayingEmbed = true
        } else {
            isPlayingDirect = true
        }
    }
}

// MARK: - Native Video Player Sheet with Headers

struct NativeVideoPlayerSheet: View {
    let url: URL
    let title: String
    let headers: [String: String]
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer = AVPlayer()

    var body: some View {
        NavigationStack {
            AVPlayerContainerView(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            player.pause()
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                    let item = AVPlayerItem(asset: asset)
                    player.replaceCurrentItem(with: item)
                    player.play()
                }
                .onDisappear {
                    player.pause()
                    player.replaceCurrentItem(with: nil)
                }
        }
    }
}

// MARK: - Web Player Sheet

struct WebPlayerSheet: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebStreamPlayerView(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Live TV Netflix View

struct LiveTVNetflixView: View {
    @ObservedObject var viewModel: MainViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 105), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Frosted Glass Category Filter Bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.availableGroups, id: \.self) { group in
                            Button {
                                viewModel.selectedCategory = group
                            } label: {
                                Text(group)
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(viewModel.selectedCategory == group ? Color.red : Color.white.opacity(0.12))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                if viewModel.isLoading && viewModel.allChannels.isEmpty {
                    Spacer()
                    ProgressView("Loading StreamBD Live TV Channels…").foregroundStyle(.white)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(viewModel.filteredChannels) { channel in
                                Button {
                                    viewModel.activeChannel = channel
                                } label: {
                                    VStack(spacing: 8) {
                                        AsyncImage(url: URL(string: channel.logo)) { phase in
                                            if let image = phase.image {
                                                image.resizable().scaledToFit()
                                            } else {
                                                Image(systemName: "tv.fill").font(.title2).foregroundStyle(.red)
                                            }
                                        }
                                        .frame(height: 50)
                                        .padding(4)

                                        Text(channel.name)
                                            .font(.caption.bold())
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                            .foregroundStyle(.white)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                    .liquidGlass(cornerRadius: 12, opacity: 0.35)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                        .padding(.bottom, 80)
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Live TV Channels")
            .searchable(text: $viewModel.searchQuery, prompt: "Search 130+ channels…")
            .sheet(item: $viewModel.activeChannel) { ch in
                StreamPlayerSheet(channel: ch)
            }
        }
    }
}

// MARK: - Live Events Netflix View

struct EventsNetflixView: View {
    @StateObject private var viewModel = EventsViewModel()
    @State private var activeChannel: Channel? = nil
    @State private var isResolvingEvent: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.events.isEmpty {
                    Spacer()
                    ProgressView("Loading Live Matches & Tournaments…").foregroundStyle(.white)
                    Spacer()
                } else {
                    List {
                        ForEach(viewModel.filteredEvents) { event in
                            Button {
                                Task {
                                    isResolvingEvent = true
                                    if let ch = await viewModel.fetchEventChannel(for: event) {
                                        activeChannel = ch
                                    }
                                    isResolvingEvent = false
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            if event.isLiveNow {
                                                Text("LIVE")
                                                    .font(.system(size: 9, weight: .black))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.red)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                            }
                                            Text(event.league ?? event.sport ?? "Tournament")
                                                .font(.caption.bold())
                                                .foregroundStyle(.gray)
                                        }

                                        Text(event.displayTitle)
                                            .font(.headline.bold())
                                            .foregroundStyle(.white)

                                        if let start = event.starts_at {
                                            Text(start).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.red)
                                }
                                .padding(.vertical, 6)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .padding(.bottom, 80)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Live Events")
            .sheet(item: $activeChannel) { ch in
                StreamPlayerSheet(channel: ch)
            }
        }
    }
}

// MARK: - Search View

struct NetflixSearchView: View {
    @ObservedObject var vodVM: VODViewModel
    @ObservedObject var liveVM: MainViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !vodVM.searchResults.isEmpty {
                        Text("Movies & Shows").font(.headline).foregroundStyle(.white).padding(.horizontal)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 12) {
                            ForEach(vodVM.searchResults) { item in
                                Button {
                                    vodVM.selectedMedia = item
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        AsyncImage(url: URL(string: item.posterURL)) { phase in
                                            if let img = phase.image {
                                                img.resizable().scaledToFill()
                                            } else {
                                                Color.gray.opacity(0.3)
                                            }
                                        }
                                        .frame(height: 155)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                        Text(item.displayTitle).font(.caption.bold()).lineLimit(1).foregroundStyle(.white)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    if !liveVM.filteredChannels.isEmpty && !vodVM.searchQuery.isEmpty {
                        Text("Live Channels").font(.headline).foregroundStyle(.white).padding(.horizontal)
                        ForEach(liveVM.filteredChannels.prefix(8)) { ch in
                            Button {
                                liveVM.activeChannel = ch
                            } label: {
                                HStack {
                                    AsyncImage(url: URL(string: ch.logo)) { p in
                                        if let img = p.image { img.resizable().scaledToFit() }
                                        else { Image(systemName: "tv") }
                                    }.frame(width: 30, height: 30)
                                    Text(ch.name).font(.subheadline.bold()).foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "play.fill").foregroundStyle(.red)
                                }
                                .padding(12)
                                .liquidGlass(cornerRadius: 10, opacity: 0.3)
                            }
                            .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 80)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Search")
            .searchable(text: $vodVM.searchQuery, prompt: "Search movies, shows & channels…")
            .onChange(of: vodVM.searchQuery) { newValue in
                liveVM.searchQuery = newValue
                Task { await vodVM.search() }
            }
            .sheet(item: $vodVM.selectedMedia) { media in
                NetflixMediaDetailSheet(media: media, vodVM: vodVM)
            }
            .sheet(item: $liveVM.activeChannel) { ch in
                StreamPlayerSheet(channel: ch)
            }
        }
    }
}

// MARK: - App Entry Point

@main
struct StreamBDIPTVApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
