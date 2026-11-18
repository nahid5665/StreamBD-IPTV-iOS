import Foundation

struct DrmConfig: Codable, Hashable {
    var type: String = ""
    var licenseServer: String? = nil
    var rawKeyPair: String? = nil
}

struct Channel: Identifiable, Codable, Hashable {
    var id: String { "\(name)|\(url)" }
    var name: String
    var url: String
    var logo: String
    var group: String
    var userAgent: String? = nil
    var cookie: String? = nil
    var httpReferer: String? = nil
    var origin: String? = nil
    var httpHeaders: [String: String] = [:]
    var tokenUrl: String? = nil
    var tokenMatch: String? = nil
    var tokenReplace: String? = nil
    var tokenId: Int? = nil
    var drm: DrmConfig? = nil
    var isLiveEvent: Bool = false
    var sources: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case name, url, logo, group, userAgent, cookie, httpReferer, origin, httpHeaders
        case tokenUrl, tokenMatch, tokenReplace, tokenId, drm, isLiveEvent, sources
    }
}

struct BundledChannelItem: Codable {
    let id: Int?
    let name: String
    let image: String?
    let channel_no: String?
    let resolution: String?
    let groupTitle: String?
    let tvgLogo: String?

    enum CodingKeys: String, CodingKey {
        case id, name, image, channel_no, resolution
        case groupTitle = "group-title"
        case tvgLogo = "tvg-logo"
    }
}

struct PlaylistInfo: Codable, Hashable {
    let url: String
    let logo: String?
}

struct LiveCategoryResponse: Codable {
    let playlists: [String: PlaylistInfo]
}

struct LiveCategory: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let url: String
    let logo: String
    var channels: [Channel] = []
}

struct SportzfyApiResponse: Codable {
    let ok: Bool?
    let source: String?
    let count: Int?
    let events: [SportzfyEvent]?
}

struct SportzfyEvent: Identifiable, Codable, Hashable {
    let kind: String?
    let id: String
    let parent: String?
    let enc_parent: String?

    private enum CodingKeys: String, CodingKey {
        case kind = "_kind"
        case id, parent, enc_parent
        case sport, league, round
        case team_a_name, team_a_logo, team_b_name, team_b_logo
        case starts_at, is_live, league_icon, priority
    }
    let sport: String?
    let league: String?
    let round: String?
    let team_a_name: String?
    let team_a_logo: String?
    let team_b_name: String?
    let team_b_logo: String?
    let starts_at: String?
    let is_live: Int?
    let league_icon: String?
    let priority: Int?

    var isLiveNow: Bool { (is_live ?? 0) == 1 }
    var displayTitle: String {
        let a = team_a_name ?? "Team A"
        let b = team_b_name ?? "Team B"
        return b.isEmpty ? a : "\(a) vs \(b)"
    }
}

struct SportzfyStream: Identifiable, Codable, Hashable {
    var id: String
    var label: String?
    var stream_type: String?
    var stream_url: String?
    var drm_kid: String?
    var drm_key: String?
    var sort_order: Int?
}

struct SportzfyStreamResponse: Codable {
    let ok: Bool?
    let source: String?
    let parent: String?
    let event: SportzfyEvent?
    let streams: [SportzfyStream]?
}

struct TmdbResponse<T: Codable>: Codable {
    let page: Int?
    let results: [T]?
    let total_pages: Int?
    let total_results: Int?
}

struct TmdbMedia: Identifiable, Codable, Hashable {
    let id: Int
    let title: String?
    let name: String?
    let original_title: String?
    let original_name: String?
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
    let media_type: String?
    let release_date: String?
    let first_air_date: String?
    let vote_average: Double?

    var displayTitle: String { title ?? name ?? original_title ?? original_name ?? "Unknown" }
    var displayDate: String { String((release_date ?? first_air_date ?? "").prefix(4)) }
    var isMovie: Bool { (media_type ?? (title != nil ? "movie" : "tv")) == "movie" }
    var posterURL: String {
        guard let p = poster_path, !p.isEmpty else { return "" }
        return "https://image.tmdb.org/t/p/w500\(p)"
    }
    var backdropURL: String {
        guard let b = backdrop_path, !b.isEmpty else { return posterURL }
        return "https://image.tmdb.org/t/p/w1280\(b)"
    }
}

struct TmdbSeason: Identifiable, Codable, Hashable {
    let id: Int
    let name: String?
    let season_number: Int
    let episode_count: Int?
}

struct TmdbTvShowDetails: Codable {
    let id: Int
    let name: String?
    let number_of_seasons: Int?
    let seasons: [TmdbSeason]?
}

struct Addon: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var url: String
    var enabled: Bool = true
}

struct StreamSource: Identifiable, Codable, Hashable {
    var id: String { "\(provider ?? "Source")|\(url)" }
    var url: String
    var quality: String? = "HD"
    var provider: String? = "Default"
    var type: String? = nil
    var headers: [String: String]? = nil
}

struct UserPlaylist: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var url: String
    var createdAt: Date = Date()
}
