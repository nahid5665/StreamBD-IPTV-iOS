import SwiftUI
import WebKit
import VLCKit

// MARK: - Liquid Glass Styles & View Modifiers

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var opacity: Double = 0.65

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(opacity))
                    // Ambient inner glow layer
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.07), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                Color.white.opacity(0.12),
                                Color.clear,
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 6)
            .shadow(color: Color.purple.opacity(0.08), radius: 20, x: 0, y: 0)
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 16, opacity: Double = 0.65) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, opacity: opacity))
    }
}

// MARK: - Spring Scale Button Style (Apple Tactile Press)

struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.7, blendDuration: 0), value: configuration.isPressed)
    }
}

// MARK: - Ambient Glow Modifier

struct AmbientGlowModifier: ViewModifier {
    var color: Color
    var radius: CGFloat = 30
    func body(content: Content) -> some View {
        content
            .background(
                color.opacity(0.25)
                    .blur(radius: radius)
                    .offset(y: 8)
            )
    }
}

extension View {
    func ambientGlow(_ color: Color, radius: CGFloat = 30) -> some View {
        self.modifier(AmbientGlowModifier(color: color, radius: radius))
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

// MARK: - Eentertainment Main Container

struct ContentView: View {
    @StateObject private var mainViewModel = MainViewModel()
    @StateObject private var vodViewModel = VODViewModel()
    @StateObject private var tokenManager = TokenRefreshManager.shared
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
                case 4:
                    SettingsNetflixView(vodVM: vodViewModel, liveVM: mainViewModel)
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
            await mainViewModel.loadInitialPlaylists()
            if vodViewModel.trendingMovies.isEmpty {
                await vodViewModel.loadCatalog()
            }
        }
    }

    private var floatingGlassTabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "Home", icon: "house.fill", tabIndex: 0)
            tabButton(title: "Live TV", icon: "tv.fill", tabIndex: 1)
            tabButton(title: "Sports", icon: "sportscourt.fill", tabIndex: 2)
            tabButton(title: "Search", icon: "magnifyingglass", tabIndex: 3)
            tabButton(title: "Settings", icon: "gearshape.fill", tabIndex: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: 32, opacity: 0.88)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func tabButton(title: String, icon: String, tabIndex: Int) -> some View {
        Button {
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.72)) {
                selectedTab = tabIndex
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: selectedTab == tabIndex ? .bold : .regular))
                    .foregroundStyle(
                        selectedTab == tabIndex
                            ? LinearGradient(colors: [Color(red: 0.4, green: 0.6, blue: 1.0), Color(red: 0.6, green: 0.3, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.gray], startPoint: .top, endPoint: .bottom)
                    )
                    .scaleEffect(selectedTab == tabIndex ? 1.12 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: selectedTab)
                Text(title)
                    .font(.system(size: 10, weight: selectedTab == tabIndex ? .bold : .medium))
                    .foregroundStyle(selectedTab == tabIndex ? Color.white : Color.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.92))
    }
}

// MARK: - Eentertainment Home View

struct NetflixHomeView: View {
    @ObservedObject var vodVM: VODViewModel
    @ObservedObject var liveVM: MainViewModel

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    // Hero Spotlight
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

                    // Quick Playlists Bar
                    quickPlaylistsRow

                    // Bollywood Hits
                    if !vodVM.bollywoodMovies.isEmpty {
                        NetflixMediaRow(title: "Bollywood & Hindi Hits", items: vodVM.bollywoodMovies, vodVM: vodVM)
                    }

                    Spacer(minLength: 90)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .safeAreaInset(edge: .top) {
                eentertainmentTopHeader
            }
            .sheet(item: $vodVM.selectedMedia) { media in
                NetflixMediaDetailSheet(media: media, vodVM: vodVM)
            }
            .sheet(item: $liveVM.activeChannel) { channel in
                StreamPlayerSheet(channel: channel)
            }
        }
    }

    private var eentertainmentTopHeader: some View {
        HStack {
            // Eentertainment Logo — Liquid Glass gradient badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.35, green: 0.55, blue: 1.0),
                                Color(red: 0.55, green: 0.25, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: Color.purple.opacity(0.5), radius: 14, x: 0, y: 4)

                Text("Eentertainment")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
            }

            Spacer()

            HStack(spacing: 8) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                    .shadow(color: .green, radius: 4)
                Text("VLC Active")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .liquidGlass(cornerRadius: 12, opacity: 0.3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.9), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var quickPlaylistsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Featured IPTV Playlists").font(.title3.bold()).foregroundStyle(.white)
                Spacer()
                Text("44 Playlists")
                    .font(.caption.bold())
                    .foregroundStyle(Color(red: 0.4, green: 0.6, blue: 1.0))
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(liveVM.playlists.prefix(10)) { pl in
                        Button {
                            liveVM.activePlaylist = pl
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "play.tv.fill")
                                    .font(.title2)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color(red: 0.4, green: 0.6, blue: 1.0), Color(red: 0.6, green: 0.3, blue: 1.0)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )

                                Text(pl.name)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                    .foregroundStyle(.white)

                                Text(pl.category)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.gray)
                            }
                            .frame(width: 100, height: 75)
                            .padding(8)
                            .liquidGlass(cornerRadius: 14, opacity: 0.4)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .sheet(item: $liveVM.activePlaylist) { pl in
            PlaylistChannelListView(playlist: pl, viewModel: liveVM)
        }
    }
}

// MARK: - Eentertainment Hero Banner

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

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: .black.opacity(0.6), location: 0.7),
                    .init(color: .black, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 12) {
                Text(media.displayTitle)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 10, x: 0, y: 4)
                    .padding(.horizontal, 20)

                HStack(spacing: 8) {
                    Text("BDIX Fast").font(.caption.bold()).foregroundStyle(Color(red: 0.4, green: 0.6, blue: 1.0))
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
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(ScaleButtonStyle())

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
                        .liquidGlass(cornerRadius: 10, opacity: 0.6)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 16)
        }
        .frame(height: 480)
    }
}

// MARK: - Eentertainment Top 10 Row

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

// MARK: - Eentertainment Media Row

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

// MARK: - Live TV View (ALL 44 PLAYLISTS BROWSER)

struct LiveTVNetflixView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var tokenManager = TokenRefreshManager.shared

    private let columns = [
        GridItem(.adaptive(minimum: 155), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Token Refresh & Live Status Bar
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .shadow(color: .green, radius: 4)
                        Text(tokenManager.tokenStatus)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Button {
                        Task {
                            await tokenManager.refreshAllTokens()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.bold())
                            Text("Refresh")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(Color(red: 0.4, green: 0.6, blue: 1.0))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .liquidGlass(cornerRadius: 8, opacity: 0.3)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))

                // Category Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.playlistCategories, id: \.self) { cat in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.selectedCategory = cat
                                }
                            } label: {
                                Text(cat)
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        viewModel.selectedCategory == cat
                                            ? LinearGradient(colors: [Color(red: 0.35, green: 0.55, blue: 1.0), Color(red: 0.55, green: 0.25, blue: 0.95)], startPoint: .leading, endPoint: .trailing)
                                            : LinearGradient(colors: [Color.white.opacity(0.12)], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                    .shadow(color: viewModel.selectedCategory == cat ? Color.purple.opacity(0.4) : .clear, radius: 8, x: 0, y: 3)
                            }
                            .buttonStyle(ScaleButtonStyle(scale: 0.94))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                // 44 Playlists Grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(viewModel.filteredPlaylists) { playlist in
                            Button {
                                viewModel.activePlaylist = playlist
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        if !playlist.logo.isEmpty {
                                            AsyncImage(url: URL(string: playlist.logo)) { p in
                                                if let img = p.image {
                                                    img.resizable().scaledToFit()
                                                } else {
                                                    Image(systemName: "play.tv.fill").foregroundStyle(categoryColor(for: playlist.category))
                                                }
                                            }
                                            .frame(width: 32, height: 32)
                                        } else {
                                            Image(systemName: "tv.fill")
                                                .font(.title3)
                                                .foregroundStyle(categoryColor(for: playlist.category))
                                                .frame(width: 32, height: 32)
                                        }

                                        Spacer()

                                        Text(playlist.category)
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(categoryColor(for: playlist.category).opacity(0.3))
                                            .foregroundStyle(categoryColor(for: playlist.category))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.headline.bold())
                                            .lineLimit(1)
                                            .foregroundStyle(.white)

                                        Text("Tap to view channels")
                                            .font(.caption2)
                                            .foregroundStyle(.gray)
                                    }

                                    HStack {
                                        Text("Eentertainment")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.bold())
                                            .foregroundStyle(categoryColor(for: playlist.category))
                                    }
                                }
                                .padding(14)
                                .liquidGlass(cornerRadius: 14, opacity: 0.35)
                            }
                            .buttonStyle(ScaleButtonStyle(scale: 0.96))
                        }
                    }
                    .padding()
                    .padding(.bottom, 80)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Live Playlists (44)")
            .searchable(text: $viewModel.searchQuery, prompt: "Search 44 playlists…")
            .sheet(item: $viewModel.activePlaylist) { pl in
                PlaylistChannelListView(playlist: pl, viewModel: viewModel)
            }
            .sheet(item: $viewModel.activeChannel) { ch in
                StreamPlayerSheet(channel: ch)
            }
        }
    }

    private func categoryColor(for cat: String) -> Color {
        switch cat {
        case "Bangla TV": return Color(red: 0.2, green: 0.8, blue: 0.5)
        case "Sports": return Color(red: 1.0, green: 0.35, blue: 0.35)
        case "BDIX FTP": return Color(red: 0.4, green: 0.6, blue: 1.0)
        case "Indian TV": return Color(red: 0.75, green: 0.4, blue: 1.0)
        case "Bangla OTT": return Color(red: 1.0, green: 0.6, blue: 0.2)
        case "StreamBD Official": return Color(red: 0.4, green: 0.6, blue: 1.0)
        case "BDIX Portal": return Color(red: 0.3, green: 0.9, blue: 0.9)
        default: return Color(red: 1.0, green: 0.85, blue: 0.3)
        }
    }
}

// MARK: - Playlist Channel List View

struct PlaylistChannelListView: View {
    let playlist: EmbeddedPlaylist
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var channels: [Channel] = []
    @State private var isLoading = true
    @State private var searchQuery = ""

    private var filteredChannels: [Channel] {
        if searchQuery.isEmpty { return channels }
        return channels.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 105), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    Spacer()
                    ProgressView("Loading \(playlist.name) Channels…")
                        .tint(.red)
                        .foregroundStyle(.white)
                    Spacer()
                } else if channels.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.yellow)
                        Text("No channels available in this playlist.")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(filteredChannels) { channel in
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
                        .padding(.bottom, 40)
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(playlist.name)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "Search channels…")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(.white)
                }
            }
            .task {
                isLoading = true
                channels = await viewModel.loadChannels(for: playlist)
                isLoading = false
            }
            .sheet(item: $viewModel.activeChannel) { ch in
                StreamPlayerSheet(channel: ch)
            }
        }
    }
}

// MARK: - Eentertainment Media Detail Sheet (Stream Player with Addon Scrapers)

struct NetflixMediaDetailSheet: View {
    let media: TmdbMedia
    @ObservedObject var vodVM: VODViewModel
    @Environment(\.dismiss) private var dismiss

    // Live addon results: bound directly to vodVM.availableStreams so streams
    // appear progressively as each addon resolves (not all at once at the end).
    @State private var activePlayback: PlaybackRequest? = nil
    @State private var playbackAlertText: String? = nil
    @State private var showPlaybackAlert: Bool = false
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
                        if let first = vodVM.availableStreams.first {
                            playSource(first)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill").font(.headline)
                            Text("Play").font(.headline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.35, green: 0.55, blue: 1.0), Color(red: 0.55, green: 0.25, blue: 0.95)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Color.purple.opacity(0.5), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(ScaleButtonStyle())
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

                    // Stream Providers & Addon Names
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Addon Availability & Streams")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)

                        // Real-Time Addon Status Badges Bar
                        if !vodVM.addonStates.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(vodVM.addonStates.keys).sorted(), id: \.self) { addonName in
                                        let state = vodVM.addonStates[addonName] ?? .idle
                                        HStack(spacing: 6) {
                                            switch state {
                                            case .loading:
                                                ProgressView().tint(.white).scaleEffect(0.65)
                                                Text(addonName).font(.caption2).foregroundStyle(.white.opacity(0.8))
                                            case .available(let list):
                                                Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
                                                Text("\(addonName) (\(list.count))").font(.caption2.bold()).foregroundStyle(.white)
                                            case .unavailable:
                                                Image(systemName: "minus.circle").font(.caption2).foregroundStyle(.gray)
                                                Text(addonName).font(.caption2).foregroundStyle(.gray)
                                            case .failed:
                                                Image(systemName: "exclamationmark.circle").font(.caption2).foregroundStyle(.orange)
                                                Text(addonName).font(.caption2).foregroundStyle(.orange.opacity(0.85))
                                            case .idle:
                                                EmptyView()
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(Capsule())
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        if vodVM.isResolvingAddons && vodVM.availableStreams.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView().tint(Color(red: 0.4, green: 0.6, blue: 1.0))
                                Text("Checking BDIX servers & addons in parallel…")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                            .padding(.horizontal, 16)
                        } else if vodVM.availableStreams.isEmpty && !vodVM.isResolvingAddons {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No playable streams found on checked addons for this title.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Button {
                                    Task { await loadStreams() }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Retry Addons")
                                    }
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 16)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(vodVM.availableStreams) { source in
                                    Button {
                                        playSource(source)
                                    } label: {
                                        HStack {
                                            Image(systemName: source.type == "direct" ? "bolt.fill" : "globe")
                                                .foregroundStyle(source.type == "direct" ? Color(red: 0.2, green: 0.9, blue: 0.5) : Color(red: 1.0, green: 0.6, blue: 0.2))

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(source.provider ?? "Server")
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.white)
                                                Text(source.quality ?? "1080P")
                                                    .font(.caption2)
                                                    .foregroundStyle(.gray)
                                            }

                                            Spacer()

                                            Text(source.type == "direct" ? "Direct Play" : "Web Embed")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(source.type == "direct" ? Color(red: 0.2, green: 0.9, blue: 0.5) : Color(red: 1.0, green: 0.6, blue: 0.2))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.white.opacity(0.08))
                                                .clipShape(Capsule())

                                            // Hand this stream to the installed VLC app
                                            if source.type != "embed" {
                                                Button {
                                                    let opened = VLCAppIntegration.open(
                                                        streamURL: source.url,
                                                        title: source.provider ?? media.displayTitle
                                                    )
                                                    if !opened {
                                                        playbackAlertText = "VLC app not found on this iPhone."
                                                        showPlaybackAlert = true
                                                    }
                                                } label: {
                                                    Image(systemName: "cone.fill")
                                                        .font(.system(size: 14, weight: .bold))
                                                        .foregroundStyle(.orange)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 5)
                                                        .background(Color.orange.opacity(0.18))
                                                        .clipShape(Capsule())
                                                }
                                                .buttonStyle(ScaleButtonStyle(scale: 0.9))
                                            }

                                            Image(systemName: "play.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [Color(red: 0.4, green: 0.6, blue: 1.0), Color(red: 0.6, green: 0.3, blue: 1.0)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        }
                                        .padding(12)
                                        .liquidGlass(cornerRadius: 10, opacity: 0.35)
                                    }
                                    .buttonStyle(ScaleButtonStyle(scale: 0.97))
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
            .fullScreenCover(item: $activePlayback) { request in
                if request.isEmbed {
                    WebPlayerSheet(url: request.url, title: request.title)
                } else {
                    UniversalFullScreenPlayerView(
                        url: request.url,
                        title: request.title,
                        subtitle: request.subtitle,
                        headers: request.headers,
                        isLive: request.isLive,
                        onClose: {
                            activePlayback = nil
                        }
                    )
                }
            }
            .alert("Cannot Play Stream", isPresented: $showPlaybackAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(playbackAlertText ?? "Unable to play stream.")
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
        if !media.isMovie && seasons.isEmpty {
            seasons = await vodVM.fetchTvSeasons(tvId: media.id)
            if let first = seasons.first {
                selectedSeason = first.season_number
                episodes = await vodVM.fetchSeasonEpisodes(tvId: media.id, seasonNumber: first.season_number)
            }
        }
        // Results stream into vodVM.availableStreams live as each addon resolves.
        _ = await vodVM.resolveStreams(for: media, season: selectedSeason, episode: selectedEpisode)
    }

    private func playSource(_ source: StreamSource) {
        guard let url = URL(string: source.url), !source.url.isEmpty else {
            playbackAlertText = "Stream URL is invalid or malformed for provider: \(source.provider ?? "Unknown")"
            showPlaybackAlert = true
            return
        }

        // Settings -> External Player: hand the stream to the installed VLC app.
        // Embed pages can't be played by VLC — they always stay in-app.
        if PlayerDestination.current == .vlcApp,
           source.type != "embed",
           VLCAppIntegration.isVLCInstalled {
            let handedOff = VLCAppIntegration.open(streamURL: source.url, title: source.provider ?? media.displayTitle)
            if handedOff { return }
        }

        let isEmbed = (source.type == "embed")
        activePlayback = PlaybackRequest(
            url: url,
            title: media.displayTitle,
            subtitle: source.provider,
            headers: source.headers ?? [:],
            isLive: false,
            isEmbed: isEmbed
        )
    }
}

// MARK: - Universal Video Player Sheet (Powered by VLCKit for MKV, TS, M3U8, MP4)

struct UniversalVideoPlayerSheet: View {
    let url: URL
    let title: String
    let headers: [String: String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        UniversalFullScreenPlayerView(
            url: url,
            title: title,
            subtitle: nil,
            headers: headers,
            isLive: false,
            onClose: {
                dismiss()
            }
        )
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
                            .foregroundStyle(.white)
                    }
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

// MARK: - Eentertainment Search View

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

                    if !liveVM.filteredGlobalChannels.isEmpty && !vodVM.searchQuery.isEmpty {
                        Text("Live Channels").font(.headline).foregroundStyle(.white).padding(.horizontal)
                        ForEach(liveVM.filteredGlobalChannels.prefix(8)) { ch in
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

// MARK: - Eentertainment Settings & Stremio Addons Management

struct SettingsNetflixView: View {
    @ObservedObject var vodVM: VODViewModel
    @ObservedObject var liveVM: MainViewModel

    @State private var newAddonName: String = ""
    @State private var newAddonUrl: String = ""
    @State private var addonAlert: String? = nil
    @State private var showAddonAlert: Bool = false
    @State private var showAddonDiagnostics: Bool = false
    @AppStorage(PlayerSettings.storageKey) private var playerPreferenceRaw: String = PlayerEnginePreference.auto.rawValue
    @AppStorage(PlayerDestination.storageKey) private var playerDestinationRaw: String = PlayerDestination.inApp.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text("Addons, Streams & Player Configuration")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    // Install Custom Stremio HTTP Addon Section
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Add Stremio Addon", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("Paste any addon URL — a .js scraper addon (e.g. https://cdn.jsdelivr.net/gh/.../addons/movielinkbd.js) or a Stremio manifest (https://.../manifest.json)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 12) {
                            TextField("Addon Name (e.g. MovieLinkBD)", text: $newAddonName)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)

                            TextField("Addon URL (.js scraper or /manifest.json)", text: $newAddonUrl)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .keyboardType(.URL)
                                .padding(12)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)

                            Button {
                                addStremioAddon()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Install Addon")
                                        .font(.subheadline.bold())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.35, green: 0.55, blue: 1.0), Color(red: 0.55, green: 0.25, blue: 0.95)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .disabled(newAddonUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(16)
                        .liquidGlass(cornerRadius: 16, opacity: 0.5)

                        // Popular Presets
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Popular Presets (Tap to fill)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    presetButton(title: "Torrentio HTTP", url: "https://torrentio.strem.fun/manifest.json")
                                    presetButton(title: "Cinemeta", url: "https://v3-cinemeta.strem.io/manifest.json")
                                    presetButton(title: "CyberFlix", url: "https://cyberflix.kodi.al/manifest.json")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // Active Addons List (Toggle & Manage)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Installed Addons", systemImage: "puzzlepiece.extension.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(vodVM.addons.filter { $0.enabled }.count) Active")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        }

                        VStack(spacing: 8) {
                            ForEach(vodVM.addons) { addon in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(addon.name)
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.white)
                                            if addon.type == "stremio" || addon.id.hasPrefix("stremio_") {
                                                Text("Stremio")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(.purple)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.purple.opacity(0.2))
                                                    .clipShape(Capsule())
                                            }
                                        }

                                        Text(addon.url)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    // Custom user addon can be deleted
                                    if addon.id.hasPrefix("stremio_") || addon.id.hasPrefix("js_") {
                                        Button {
                                            vodVM.removeCustomAddon(id: addon.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                                .foregroundStyle(.red.opacity(0.85))
                                                .padding(6)
                                        }
                                    }

                                    Toggle("", isOn: Binding(
                                        get: { addon.enabled },
                                        set: { _ in vodVM.toggleAddon(id: addon.id) }
                                    ))
                                    .labelsHidden()
                                    .tint(Color(red: 0.35, green: 0.55, blue: 1.0))
                                }
                                .padding(12)
                                .liquidGlass(cornerRadius: 12, opacity: 0.35)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // Video Player Engine Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Video Player", systemImage: "play.rectangle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("Choose which engine plays your streams. VLC handles more formats (TS, MKV, RTMP) with custom headers; AVPlayer is Apple-native with AirPlay and Picture-in-Picture. Auto picks the best engine per stream and falls back automatically.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Picker("Player Engine", selection: $playerPreferenceRaw) {
                            ForEach(PlayerEnginePreference.allCases) { pref in
                                Text(pref.rawValue).tag(pref.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: playerPreferenceRaw) { newValue in
                            if let pref = PlayerEnginePreference(rawValue: newValue) {
                                PlayerSettings.preference = pref
                            }
                        }

                        Text(PlayerSettings.preference == .vlc
                             ? "VLC engine active for all streams (MobileVLCKit)."
                             : PlayerSettings.preference == .avPlayer
                             ? "AVPlayer engine active for all streams (no automatic VLC fallback)."
                             : "Auto: VLC for TS/MKV/RTMP, AVPlayer for the rest.")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    .padding(16)
                    .liquidGlass(cornerRadius: 16, opacity: 0.5)
                    .padding(.horizontal, 20)

                    // External Player (VLC App Handoff)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("External Player", systemImage: "arrow.up.forward.app.fill")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Picker("Playback Destination", selection: $playerDestinationRaw) {
                            ForEach(PlayerDestination.allCases) { dest in
                                Text(dest.rawValue).tag(dest.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: playerDestinationRaw) { newValue in
                            if let dest = PlayerDestination(rawValue: newValue) {
                                PlayerDestination.current = dest
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: VLCAppIntegration.isVLCInstalled ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(VLCAppIntegration.isVLCInstalled ? .green : .gray)
                            Text(VLCAppIntegration.isVLCInstalled
                                 ? "VLC app detected on this iPhone."
                                 : "VLC app not installed — download it from the App Store.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Text(PlayerDestination.current == .vlcApp
                             ? "Streams open in the VLC app. Note: custom headers (Referer/Cookie) are not forwarded, so some protected BDIX streams may refuse in VLC — use the in-app engine for those."
                             : "Streams play inside this app with the engine chosen above.")
                            .font(.caption2)
                            .foregroundStyle(PlayerDestination.current == .vlcApp ? .orange : .secondary)
                    }
                    .padding(16)
                    .liquidGlass(cornerRadius: 16, opacity: 0.5)
                    .padding(.horizontal, 20)

                    // Addon Diagnostics
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Diagnostics", systemImage: "stethoscope")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Button {
                            showAddonDiagnostics = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform.path")
                                Text("Addon Diagnostics (Cineplex Test)")
                                    .font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.horizontal, 20)

                    // App Information
                    VStack(spacing: 6) {
                        Text(AppConfig.appName)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Version \(AppConfig.appVersion) — Dual-Engine Video Player")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Addon Notice", isPresented: $showAddonAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(addonAlert ?? "")
            }
            .sheet(isPresented: $showAddonDiagnostics) {
                AddonDiagnosticsView()
            }
        }
    }

    private func presetButton(title: String, url: String) -> some View {
        Button {
            newAddonName = title
            newAddonUrl = url
        } label: {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private func addStremioAddon() {
        let trimmed = newAddonUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            addonAlert = "Addon URL must begin with http:// or https://"
            showAddonAlert = true
            return
        }

        let name = newAddonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Addon" : newAddonName

        if trimmed.lowercased().hasSuffix(".js") {
            // Plain JS scraper addon (streambd-libs style, jsdelivr/github.io/etc.)
            vodVM.addCustomJSAddon(name: name, url: trimmed)
            newAddonName = ""
            newAddonUrl = ""
            addonAlert = "Installed \(name) as a JS addon!"
            showAddonAlert = true
        } else {
            // Stremio protocol manifest
            let manifestUrl = trimmed.hasSuffix("/manifest.json") ? trimmed : (trimmed.hasSuffix("/") ? "\(trimmed)manifest.json" : "\(trimmed)/manifest.json")
            vodVM.addCustomStremioAddon(name: name, url: manifestUrl)
            newAddonName = ""
            newAddonUrl = ""
            addonAlert = "Installed \(name) as a Stremio addon!"
            showAddonAlert = true
        }
    }
}

// MARK: - App Entry Point

@main
struct EentertainmentApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
