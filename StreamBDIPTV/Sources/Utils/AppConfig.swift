import Foundation

enum AppConfig {
    static let appName = "StreamBD IPTV"
    static let appVersion = "v5.0"

    // Native AES-128-CBC credentials extracted from libnative-keys.so
    static let nativeAesKey = "X3#yS@6k~u&hr$0z"
    static let nativeAesIv  = "n!0kfd&re%3#pw*s"

    // Decrypted RemoteConfigManager endpoints
    static let iptvPlaylistURL   = "https://myselfhridoy.github.io/streambd-libs/playlists/IPTV.json"
    static let addonRegistryURL  = "https://myselfhridoy.github.io/streambd-libs/addons/StreamBD_IPTV_Addon.json"
    static let liveEventsApiURL  = "https://myselfhridoy.github.io/streambdAPI/api/all/events/index.enc"
    static let tmdbBaseURL       = "https://api.themoviedb.org/3"
    static let tmdbApiKey        = "460327acf6e0235a391222cb530de9c8"

    static let defaultUserAgent  = "VLC/3.0.20 LibVLC/3.0.20 (OTT Navigator; TiviMate)"
    static let browserUserAgent  = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
}
