import SwiftUI

// MARK: - dx.bi TitleView (ported from dxbi-stremio ios/Dxbi/UI/TitleView.swift)
// A film or show the Apple TV way: its art at the top in the art's own colour, the name, Play
// (one tap: the stream chosen last time plays at once, else the streams sheet), then the
// seasons and episodes.

/** The stream chosen last time for this title: Play plays it at once (dx.bi's justPlay) */
struct DxLastPick: Codable {
    var url: String
    var provider: String
    var headers: [String: String] = [:]
    var type: String? = nil

    private static func key(_ id: Int) -> String { "dx_last_pick_\(id)" }

    static func load(for id: Int) -> DxLastPick? {
        guard let data = UserDefaults.standard.data(forKey: key(id)) else { return nil }
        return try? JSONDecoder().decode(DxLastPick.self, from: data)
    }

    static func save(_ pick: DxLastPick, for id: Int) {
        if let data = try? JSONEncoder().encode(pick) {
            UserDefaults.standard.set(data, forKey: key(id))
        }
    }
}

struct DxTitleView: View {
    var media: TmdbMedia
    @EnvironmentObject private var vodVM: VODViewModel

    @State private var streamsOpen = false
    @State private var activePlayback: PlaybackRequest? = nil
    @State private var playbackAlertText: String? = nil
    @State private var tint = Color(white: 0.16)
    @State private var moreText = false
    @State private var cast: [TmdbCastMember] = []

    // Series
    @State private var seasons: [TmdbSeason] = []
    @State private var season: Int? = nil
    @State private var episodes: [TmdbEpisode] = []
    @State private var selectedEpisode: TmdbEpisode? = nil

    private var isTV: Bool { !media.isMovie }
    private var backdrop: URL? { media.backdropURL.isEmpty ? (media.posterURL.isEmpty ? nil : URL(string: media.posterURL)) : URL(string: media.backdropURL) }

    var body: some View {
        GeometryReader { g in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(width: g.size.width)
                    VStack(alignment: .leading, spacing: 30) {
                        if isTV { episodesSection(width: g.size.width) }
                        extras
                    }
                    .padding(.vertical, 26)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        // the art's colour above, black below (what shows past either end of the page)
        .background {
            VStack(spacing: 0) {
                tint
                Color.black
            }
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: URL(string: "https://www.themoviedb.org/\(isTV ? "tv" : "movie")/\(media.id)")!) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $streamsOpen) {
            DxStreamsSheet(
                heading: media.displayTitle,
                subheading: episodeLine,
                items: vodVM.availableStreams,
                isResolving: vodVM.isResolvingAddons,
                lastPick: DxLastPick.load(for: media.id)
            ) { source in
                play(source)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $activePlayback) { request in
            UniversalVideoPlayerSheet(url: request.url, title: request.title, headers: request.headers)
        }
        .alert("Playback", isPresented: Binding(get: { playbackAlertText != nil }, set: { if !$0 { playbackAlertText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackAlertText ?? "")
        }
        .task(id: media.id) {
            await loadDetails()
        }
        .task(id: media.backdrop_path) {
            if let c = await DxArtColour.of(backdrop) {
                withAnimation(.easeOut(duration: 0.4)) { tint = c }
            }
        }
    }

    // MARK: - Loading

    private func loadDetails() async {
        if isTV {
            seasons = (await vodVM.fetchTvSeasons(tvId: media.id)).filter { $0.season_number > 0 }
            if season == nil { season = seasons.first?.season_number }
            if let s = season {
                episodes = await vodVM.fetchSeasonEpisodes(tvId: media.id, seasonNumber: s)
            }
        }
        cast = await vodVM.fetchCast(tmdbId: media.id, isTV: isTV)
        await resolve()
    }

    private func resolve() async {
        let seasonNo = isTV ? (season ?? 1) : 1
        let epNo = isTV ? (selectedEpisode?.episode_number ?? 1) : 1
        _ = await vodVM.resolveStreams(for: media, season: seasonNo, episode: epNo)
    }

    // MARK: - Playing (dx.bi way: last pick at once, else the streams sheet)

    private func start() {
        if let last = DxLastPick.load(for: media.id) {
            play(last.asStreamSource)
            return
        }
        streamsOpen = true
    }

    private func play(_ source: StreamSource) {
        guard let url = URL(string: source.url), !source.url.isEmpty else {
            playbackAlertText = "Stream URL is invalid or malformed for provider: \(source.provider ?? "Unknown")"
            return
        }

        DxLastPick.save(DxLastPick(url: source.url, provider: source.provider ?? "Default", headers: source.headers ?? [:], type: source.type), for: media.id)
        streamsOpen = false

        // Settings → External Player: hand the stream to the installed VLC app.
        if PlayerDestination.current == .vlcApp,
           source.type != "embed",
           VLCAppIntegration.isVLCInstalled {
            let handedOff = VLCAppIntegration.open(streamURL: source.url, title: source.provider ?? media.displayTitle)
            if handedOff { return }
        }

        activePlayback = PlaybackRequest(
            url: url,
            title: media.displayTitle,
            subtitle: source.provider,
            headers: source.headers ?? [:],
            isLive: false,
            isEmbed: source.type == "embed"
        )
    }

    private var playLabel: String {
        if isTV, let ep = selectedEpisode ?? episodes.first {
            return "Play S\(season ?? 1), E\(ep.episode_number)"
        }
        return "Play"
    }

    private var episodeLine: String? {
        guard isTV, let ep = selectedEpisode ?? episodes.first else { return nil }
        return "S\(season ?? 1), E\(ep.episode_number) · \(ep.name ?? "")"
    }

    // MARK: - The top: art, name, Play

    private func header(width: CGFloat) -> some View {
        let artHeight = width * 0.9
        return VStack(spacing: 14) {
            Color.clear
                .frame(width: width, height: artHeight)
                .overlay(alignment: .bottom) {
                    DxTitleLogo(name: media.displayTitle, maxHeight: 110, textSize: 38)
                        .frame(maxWidth: min(width * 0.75, 380))
                        .padding(.bottom, -10)
                }
            VStack(spacing: 14) {
                Text([dxTypeName(isTV ? "series" : "movie"), media.displayDate].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Dx.muted)
                    .padding(.top, 6)
                buttons
                if let d = media.overview {
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { moreText.toggle() } } label: {
                        Text(d)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(moreText ? nil : 3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                facts
            }
            .padding(.horizontal, Dx.gutter)
            .padding(.bottom, 24)
        }
        .background(alignment: .top) {
            // Apple TV's: the page scrolls up over the art, which stays where it is and fades and
            // blurs as it's covered (and grows when the page is pulled down)
            DxArt(url: backdrop)
                .frame(width: width, height: artHeight)
                .clipped()
                .overlay(LinearGradient(stops: [.init(color: .black.opacity(0.3), location: 0), .init(color: .clear, location: 0.3), .init(color: tint, location: 1)], startPoint: .top, endPoint: .bottom))
        }
        // the art's colour runs down to the end of the facts, where the seasons start on black
        .background(tint)
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            DxPrimaryPill(label: playLabel) { start() }
            Menu {
                Button { streamsOpen = true } label: { Label("Choose a Stream", systemImage: "list.bullet") }
                if let last = DxLastPick.load(for: media.id) {
                    Button { play(last.asStreamSource) } label: { Label("Play Last Stream", systemImage: "clock.arrow.circlepath") }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold)).frame(width: 36, height: 36)
            }
            .dxGlassButton()
            .buttonBorderShape(.circle)
        }
        .frame(maxWidth: 400)
    }

    private var facts: some View {
        HStack(spacing: 8) {
            Text(media.displayDate)
            if let v = media.vote_average, v > 0 {
                DxBadge(text: "TMDB \(String(format: "%.1f", v))")
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .foregroundStyle(Dx.muted)
    }

    // MARK: - Episodes

    @ViewBuilder
    private func episodesSection(width: CGFloat) -> some View {
        if !seasons.isEmpty && !episodes.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Menu {
                    Picker("Season", selection: Binding(get: { season ?? seasons.first?.season_number ?? 1 }, set: { newSeason in
                        season = newSeason
                        Task {
                            episodes = await vodVM.fetchSeasonEpisodes(tvId: media.id, seasonNumber: newSeason) ?? []
                            selectedEpisode = nil
                            await resolve()
                        }
                    })) {
                        ForEach(seasons) { s in Text(s.name ?? "Season \(s.season_number)").tag(s.season_number) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(seasons.first(where: { $0.season_number == (season ?? seasons.first?.season_number ?? 1) })?.name ?? "Season \(season ?? 1)")
                            .font(.title2.bold())
                        Image(systemName: "chevron.up.chevron.down").font(.headline).foregroundStyle(Dx.muted)
                    }
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, Dx.gutter)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(episodes) { ep in
                            Button {
                                selectedEpisode = ep
                                Task {
                                    await resolve()
                                    streamsOpen = true
                                }
                            } label: {
                                DxEpisodeCard(episode: ep, showName: media.displayTitle, width: min(width * 0.72, 340), fallbackArt: backdrop)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Dx.gutter)
                }
                .dxViewAlignedShelf()
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Cast, crew

    @ViewBuilder
    private var extras: some View {
        if !cast.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                DxSectionHeader(title: "Cast & Crew")
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(cast) { person in
                            VStack(spacing: 6) {
                                ZStack {
                                    Text(person.displayName.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined())
                                        .font(.title2.weight(.semibold))
                                    if let photo = person.photoURL {
                                        AsyncImage(url: photo) { phase in
                                            if let image = phase.image { image.resizable().scaledToFill() }
                                        }
                                    }
                                }
                                .frame(width: 76, height: 76)
                                .clipShape(.circle)
                                .dxGlass(in: .circle)
                                Text(person.displayName).font(.footnote).lineLimit(2).multilineTextAlignment(.center)
                                if !person.role.isEmpty { Text(person.role).font(.caption).foregroundStyle(Dx.muted).lineLimit(2).multilineTextAlignment(.center) }
                            }
                            .frame(width: 92)
                        }
                    }
                    .padding(.horizontal, Dx.gutter)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

extension DxLastPick {
    var asStreamSource: StreamSource {
        StreamSource(url: url, quality: nil, provider: provider, type: type, headers: headers.isEmpty ? nil : headers)
    }
}
