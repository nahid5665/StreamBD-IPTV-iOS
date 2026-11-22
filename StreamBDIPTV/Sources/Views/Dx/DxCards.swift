import SwiftUI

// MARK: - dx.bi cards (ported from dxbi-stremio ios/Dxbi/UI/Cards.swift, adapted to the app's data)

/** A title in a row: its poster, and (Netflix's Top 10) a large number in the corner */
struct DxPosterCard: View {
    var title: TmdbMedia
    var width: CGFloat = 150
    var rank: Int?

    var body: some View {
        ZStack(alignment: .bottom) {
            DxArt(url: URL(string: title.posterURL))
                .frame(width: width, height: width * 1.5)
        }
        .frame(width: width, height: width * 1.5)
        .overlay(alignment: .topLeading) {
            if let rank {
                Text("\(rank)")
                    .font(.system(size: width * 0.3, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6)
                    .padding(.leading, 10)
                    .padding(.top, 2)
            }
        }
        .clipShape(.rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.1)))
        .contentShape(.rect(cornerRadius: 18))
    }
}

/** A live event, as dx.bi shows airing episodes: wide art, red caption, the words below */
struct DxEventCard: View {
    var event: SportzfyEvent
    var width: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DxArt(url: URL(string: event.team_a_logo ?? "") ?? URL(string: event.team_b_logo ?? ""))
                .frame(width: width, height: width * 0.56)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.isLiveNow ? "LIVE NOW" : (event.sport?.uppercased() ?? "UPCOMING"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(event.isLiveNow ? Dx.accent : Dx.muted)
                Text(event.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(event.league ?? "")
                    .font(.footnote).foregroundStyle(Dx.muted).lineLimit(1)
            }
            .padding(14)
        }
        .frame(width: width, height: width * 0.56)
        .clipShape(.rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
    }
}

/** A live TV channel: logo (or its initials) on glass, the name below — dx.bi's PosterGrid cell for channels */
struct DxChannelCard: View {
    var channel: Channel
    var width: CGFloat

    private var initials: String {
        channel.name.split(whereSeparator: { " .-".contains($0) }).compactMap(\.first).prefix(3).map(String.init).joined().uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Rectangle().fill(Dx.raised)
                if let logo = URL(string: channel.logo) {
                    DxArt(url: logo, contentMode: .fit).padding(10)
                } else {
                    Text(initials)
                        .font(.system(size: width * 0.16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: width, height: width * 0.62)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1)))
            Text(channel.name)
                .font(.caption.bold())
                .lineLimit(1)
            Text(channel.group)
                .font(.caption2)
                .foregroundStyle(Dx.muted)
                .lineLimit(1)
        }
        .frame(width: width)
        .contentShape(.rect)
    }
}

/** An episode, as Apple TV shows them: the picture above and the words on glass below */
struct DxEpisodeCard: View {
    var episode: TmdbEpisode
    var showName: String
    var width: CGFloat
    var fallbackArt: URL?

    var body: some View {
        ZStack(alignment: .bottom) {
            DxArt(url: episode.stillURL.isEmpty ? fallbackArt : URL(string: episode.stillURL))
                .frame(width: width, height: width * 0.92)
            dxFade(url: episode.stillURL.isEmpty ? fallbackArt : URL(string: episode.stillURL), from: 0.36)
                .frame(width: width, height: width * 0.92)
            VStack(alignment: .leading, spacing: 4) {
                Text("EPISODE \(episode.episode_number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Dx.muted)
                Text(episode.name ?? "Episode \(episode.episode_number)")
                    .font(.headline)
                    .lineLimit(1)
                if let overview = episode.overview {
                    Text(overview).font(.subheadline).foregroundStyle(Dx.muted).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(width: width, height: width * 0.92)
        .clipShape(.rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.1)))
        .contentShape(.rect(cornerRadius: 22))
    }
}

/**
 * The bottom of an Apple TV card: the card's own picture, more and more blurred toward the bottom,
 * coming in from clear (no line where the glass starts).
 */
struct DxBlurFade: View {
    var url: URL?
    /** Where the blur starts, from the top (0…1) */
    var from: CGFloat

    var body: some View {
        DxArt(url: url)
            .blur(radius: 26, opaque: true)
            .mask(LinearGradient(stops: [.init(color: .clear, location: from), .init(color: .black, location: min(from + 0.25, 1))], startPoint: .top, endPoint: .bottom))
            .overlay(LinearGradient(stops: [.init(color: .clear, location: from), .init(color: .black.opacity(0.4), location: 1)], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
    }
}

func dxFade(url: URL?, from: CGFloat) -> DxBlurFade {
    DxBlurFade(url: url, from: from)
}

// MARK: - Layout

/** A titled row of cards that scrolls sideways, snapping to each */
struct DxShelf<Content: View>: View {
    var title: String
    var see: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Text(title).font(.title2.bold()).lineLimit(1)
                if see != nil { Image(systemName: "chevron.right").font(.title3.weight(.bold)).foregroundStyle(Dx.muted) }
                Spacer(minLength: 0)
                if see != nil {
                    Button("See All", action: { see?() })
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Dx.muted)
                }
            }
            .padding(.horizontal, Dx.gutter)
            .onTapGesture { see?() }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) { content }
                    .padding(.horizontal, Dx.gutter)
            }
            .dxViewAlignedShelf()
            .scrollIndicators(.hidden)
        }
    }
}

/** Posters in a grid that fits the screen */
struct DxPosterGrid: View {
    var items: [TmdbMedia]
    var onEnd: (() -> Void)?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108, maximum: 170), spacing: 12)], spacing: 14) {
            ForEach(items) { title in
                Color.clear
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay { DxArt(url: URL(string: title.posterURL)) }
                    .clipShape(.rect(cornerRadius: 14))
                    .onAppear { if title.id == items.last?.id { onEnd?() } }
            }
        }
        .padding(.horizontal, 16)
    }
}

/** A channel grid cell row for Live TV discover */
struct DxChannelGrid: View {
    var channels: [Channel]
    var onPlay: (Channel) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108, maximum: 150), spacing: 12)], spacing: 16) {
            ForEach(channels, id: \.self) { ch in
                Button { onPlay(ch) } label: {
                    GeometryReader { g in
                        DxChannelCard(channel: ch, width: g.size.width)
                    }
                    .aspectRatio(0.82, contentMode: .fit)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}
