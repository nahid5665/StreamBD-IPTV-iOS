import SwiftUI

/**
 * Home, the Apple TV way (dx.bi's HomeView): a tall billboard to swipe through (the title's name,
 * what it is, Play and more), then the Top 10, the catalogs and Live TV — everything snapping sideways.
 */
struct DxHomeView: View {
    @ObservedObject var mainVM: MainViewModel
    @ObservedObject var vodVM: VODViewModel
    @StateObject private var eventsVM = EventsViewModel()
    @State private var kind: String? = nil
    @State private var account = false
    @State private var activeChannel: Channel? = nil

    var body: some View {
        GeometryReader { g in
            let width = g.size.width
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    if let billboard = billboard {
                        DxBillboard(media: billboard, height: min(g.size.height * 0.74, width * 1.55))
                    } else {
                        Color.clear.frame(height: 90)
                    }
                    kinds
                    if kind == nil { liveRow }
                    if kind == nil { eventsRow }
                    if kind == nil || kind == "movie" {
                        dxRow("Top 10 Today in Bangladesh", vodVM.top10Media, rank: true)
                        dxRow("Trending Movies", vodVM.trendingMovies)
                        dxRow("Bengali Blockbusters", vodVM.banglaMovies)
                        dxRow("Bollywood & Hindi Hits", vodVM.bollywoodMovies)
                    }
                    if kind == nil || kind == "series" {
                        dxRow("Popular TV Shows", vodVM.trendingTV)
                    }
                    if vodVM.trendingMovies.isEmpty && vodVM.isLoading {
                        dxLoadingRow("Loading")
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .background(Dx.background.ignoresSafeArea())
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackgroundVisibility2(.hidden)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { account = true } label: {
                    DxAvatar(email: "Nahid", size: 44)
                        .dxGlass(interactive: true, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile and settings")
            }
        }
        .sheet(isPresented: $account) {
            DxAccountSheet(mainVM: mainVM, vodVM: vodVM)
        }
        .task { await eventsVM.loadEvents() }
        .refreshable { await eventsVM.loadEvents() }
    }

    private var billboard: TmdbMedia? {
        let withArt = vodVM.trendingMovies.filter { $0.backdrop_path != nil || $0.poster_path != nil }
        return withArt.first
    }

    /** Netflix's Movies · TV Shows chips */
    private var kinds: some View {
        let types = ["movie", "series"]
        return ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(types, id: \.self) { t in
                    let on = kind == t
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { kind = on ? nil : t }
                    } label: {
                        HStack(spacing: 6) {
                            Text(t == "movie" ? "Movies" : "TV Shows")
                            if on { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                    }
                    .dxGlassButton()
                    .tint(on ? .white : nil)
                }
            }
            .padding(.horizontal, Dx.gutter)
        }
        .scrollIndicators(.hidden)
    }

    /** The BDTube server's channels, sideways like every other row; a tap plays at once */
    private var liveRow: some View {
        DxShelf(title: "Live TV", see: nil) {
            ForEach(mainVM.allChannels.prefix(12), id: \.self) { ch in
                Button { activeChannel = ch } label: {
                    DxChannelCard(channel: ch, width: 132)
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(mainVM.allChannels.isEmpty ? 0 : 1)
        .sheet(item: $activeChannel) { ch in
            StreamPlayerSheet(channel: ch)
        }
    }

    /** Live events, as dx.bi's airing cards */
    @ViewBuilder
    private var eventsRow: some View {
        let live = eventsVM.events.filter { $0.isLiveNow }
        let upcoming = eventsVM.events.filter { !$0.isLiveNow }
        if !live.isEmpty || !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 22) {
                if !live.isEmpty {
                    DxShelf(title: "Live Now") {
                        ForEach(live.prefix(8)) { ev in
                            DxEventButton(event: ev, width: 272)
                        }
                    }
                }
                if !upcoming.isEmpty {
                    DxShelf(title: "Upcoming") {
                        ForEach(upcoming.prefix(8)) { ev in
                            DxEventButton(event: ev, width: 272)
                        }
                    }
                }
            }
        }
    }

    private func dxRow(_ name: String, _ items: [TmdbMedia], rank: Bool = false) -> some View {
        Group {
            if !items.isEmpty {
                DxShelf(title: name) {
                    ForEach(Array(items.prefix(rank ? 10 : 30).enumerated()), id: \.element.id) { i, title in
                        NavigationLink(value: DxRoute.title(title)) {
                            DxPosterCard(title: title, width: 150, rank: rank ? i + 1 : nil)
                                .dxZoomSource("tmdb-\(title.id)")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func dxLoadingRow(_ name: String) -> some View {
        DxShelf(title: name) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18).fill(Dx.raised).frame(width: 150, height: 225)
            }
        }
        .redacted(reason: .placeholder)
    }
}

/** An event card that plays: the event's channel resolves, then the player opens */
struct DxEventButton: View {
    var event: SportzfyEvent
    var width: CGFloat
    @StateObject private var eventsVM = EventsViewModel()
    @State private var channel: Channel? = nil
    @State private var busy = false

    var body: some View {
        Button {
            guard !busy else { return }
            busy = true
            Task {
                channel = await eventsVM.fetchEventChannel(for: event)
                busy = false
                if channel == nil {
                    DxToast.shared.show?("No stream for this event yet")
                }
            }
        } label: {
            DxEventCard(event: event, width: width)
                .overlay {
                    if busy { ProgressView().tint(.white) }
                }
        }
        .buttonStyle(.plain)
        .sheet(item: $channel) { ch in
            StreamPlayerSheet(channel: ch)
        }
    }
}

/**
 * The tall billboard at the top of Home: one title at a time, fading into the next (by itself every
 * few seconds, or with a swipe; either way the wait starts again). Tapping it opens the title; Play plays.
 */
struct DxBillboard: View {
    var media: TmdbMedia
    var height: CGFloat
    @State private var opened: TmdbMedia? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            picture
            info
        }
        .frame(height: height)
        .clipped()
        .contentShape(.rect)
        .onTapGesture { opened = media }
        .background(
            NavigationLink(value: DxRoute.title(media), isActive: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) { EmptyView() }
                .opacity(0)
        )
    }

    private var picture: some View {
        GeometryReader { g in
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay {
                    DxArt(url: media.backdropURL)
                }
                .clipped()
                .overlay(LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.25), .init(color: .clear, location: 0.45), .init(color: .black, location: 0.92)], startPoint: .top, endPoint: .bottom))
        }
    }

    private var info: some View {
        VStack(spacing: 12) {
            Group {
                if !media.displayDate.isEmpty { DxBadge(text: media.displayDate) }
                DxTitleLogo(name: media.displayTitle, maxHeight: 110, textSize: 40)
                    .frame(maxWidth: 320)
                Text([dxTypeName(media.isMovie ? "movie" : "series")] + (media.genrePreview))
                    .font(.subheadline)
                    .foregroundStyle(Dx.muted)
                if let d = media.overview {
                    Text(d).font(.footnote).foregroundStyle(Dx.faint).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: 360)
                }
            }
            .allowsHitTesting(false)
            HStack(spacing: 14) {
                NavigationLink(value: DxRoute.title(media)) {
                    Label("Play", systemImage: "play.fill").font(.headline).frame(width: 150, height: 50)
                }
                .dxGlassProminentButton()
                .tint(.white)
                .foregroundStyle(.black)
                DxGlassCircle(icon: "info.circle", label: "More Info") {
                    opened = media
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 34)
    }
}

extension TmdbMedia {
    /** Up to two genres aren't fetched in lists; the type alone reads fine (dx.bi's billboard line) */
    var genrePreview: [String] { [] }
}

extension View {
    /// iOS 16-safe hidden toolbar background.
    @ViewBuilder
    func toolbarBackgroundVisibility2(_ visibility: Visibility) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbarBackground(visibility, for: .navigationBar)
        } else {
            self
        }
    }
}
