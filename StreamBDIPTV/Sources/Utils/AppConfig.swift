import Foundation

struct EmbeddedPlaylist: Hashable, Identifiable {
    var id: String { name }
    let name: String
    let url: String
    let logo: String
    let category: String
}

enum AppConfig {
    static let appName = "Eentertainment"
    static let appVersion = "v5.8.2"

    /// Verbose addon-pipeline logging (fetch bridge, scrapers, prewarm).
    /// Visible in Console.app / idevicesyslog under the app process.
    static let debugAddonLogging = true

    // Native AES-128-CBC credentials
    static let nativeAesKey = "X3#yS@6k~u&hr$0z"
    static let nativeAesIv  = "n!0kfd&re%3#pw*s"

    // Endpoints
    static let iptvPlaylistURL   = "https://myselfhridoy.github.io/streambd-libs/playlists/IPTV.json"
    static let addonRegistryURL  = "https://myselfhridoy.github.io/streambd-libs/addons/StreamBD_IPTV_Addon.json"
    static let liveEventsApiURL  = "https://myselfhridoy.github.io/streambdAPI/api/all/events/index.enc"
    static let tmdbBaseURL       = "https://api.themoviedb.org/3"
    static let tmdbApiKey        = "460327acf6e0235a391222cb530de9c8"

    // BDTube live server (BDTube TV widget API — TV-app endpoint first, web fallback)
    static let bdTubeAPIURL      = "http://10.99.99.99:8889/api/channels"
    static let bdTubeAPIURLAlt   = "http://10.99.99.99/api/channels"
    // Auto token refresh schedule (ported from the BDTube Samsung TV widget):
    // refresh every 2h, or 30min before the signed session expiry — whichever is sooner.
    static let bdTubeRefreshInterval: TimeInterval = 7200        // CFG.REFRESH_INTERVAL_MS
    static let bdTubeRefreshBeforeExpiry: TimeInterval = 1800    // CFG.REFRESH_BEFORE_EXPIRY_MS
    static let bdTubeMaxExpiryWindow: TimeInterval = 14400       // only pre-schedule if expiry < 4h away
    static let bdTubeMinRefreshDelay: TimeInterval = 60
    // Channels never shown/played (CFG.BLOCK)
    static let bdTubeBlockedChannels: [String] = ["DISCOVERY.HD"]

    static let defaultUserAgent  = "VLC/3.0.20 LibVLC/3.0.20 (OTT Navigator; TiviMate)"
    static let browserUserAgent  = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    // LIVE TV SERVER — the user's BDTube server (replaces all bundled
    // StreamBD/BDIX/Jio/PlusBox playlist servers). "bdtube://" is resolved
    // by MainViewModel.fetchPlaylistChannels -> BDTubeService with auto
    // session-token refresh handled by TokenRefreshManager.
    static let bundledPlaylists: [EmbeddedPlaylist] = [
        EmbeddedPlaylist(
            name: "BDTube Live",
            url: "bdtube://channels",
            logo: "",
            category: "BDTube"
        )
    ]

    // USER-SELECTED BUNDLED ADDONS (native resolvers; more can be added in Settings)
    static let bundledAddons: [Addon] = [
        Addon(id: "cineplexbd_parser", name: "Cineplex BD (BDIX)", url: "https://myselfhridoy.github.io/streambd-libs/addons/cineplexbd.js", enabled: true),
        Addon(id: "ctgmovies", name: "CTG Movies FTP (BDIX)", url: "https://myselfhridoy.github.io/streambd-libs/addons/ctgmovies.js", enabled: true),
        Addon(id: "roarzone-emby", name: "RoarZone EMBY", url: "https://myselfhridoy.github.io/streambd-libs/addons/roarzone-emby.js", enabled: true)
    ]

    // MARK: - Player Configuration Defaults & Persistence
    static var preferredPlayerStyle: PlayerStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: "preferredPlayerStyle") ?? PlayerStyle.netflixPro.rawValue
            return PlayerStyle(rawValue: raw) ?? .netflixPro
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "preferredPlayerStyle")
        }
    }

    static var defaultSkipIntroSeconds: Double {
        get {
            let val = UserDefaults.standard.double(forKey: "defaultSkipIntroSeconds")
            return val > 0 ? val : 85.0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "defaultSkipIntroSeconds")
        }
    }

    static var autoShowSkipIntro: Bool {
        get {
            if UserDefaults.standard.object(forKey: "autoShowSkipIntro") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "autoShowSkipIntro")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "autoShowSkipIntro")
        }
    }
}

// MARK: - Player Style Definition
enum PlayerStyle: String, CaseIterable, Identifiable {
    case netflixPro = "netflixPro"
    case classic = "classic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .netflixPro: return "Netflix Pro Player"
        case .classic: return "Classic Player"
        }
    }

    var badge: String {
        switch self {
        case .netflixPro: return "PRO UI"
        case .classic: return "ORIGINAL"
        }
    }

    var subtitle: String {
        switch self {
        case .netflixPro: return "Netflix UI, Skip Intro, Screen Lock, Gestures & Speed Control"
        case .classic: return "Standard StreamBD dual-engine player interface"
        }
    }

    var iconName: String {
        switch self {
        case .netflixPro: return "play.tv.fill"
        case .classic: return "play.circle.fill"
        }
    }
}
