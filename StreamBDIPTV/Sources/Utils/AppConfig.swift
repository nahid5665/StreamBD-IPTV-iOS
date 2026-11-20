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
    static let appVersion = "v5.6.3"

    // Native AES-128-CBC credentials
    static let nativeAesKey = "X3#yS@6k~u&hr$0z"
    static let nativeAesIv  = "n!0kfd&re%3#pw*s"

    // Endpoints
    static let iptvPlaylistURL   = "https://myselfhridoy.github.io/streambd-libs/playlists/IPTV.json"
    static let addonRegistryURL  = "https://myselfhridoy.github.io/streambd-libs/addons/StreamBD_IPTV_Addon.json"
    static let liveEventsApiURL  = "https://myselfhridoy.github.io/streambdAPI/api/all/events/index.enc"
    static let tmdbBaseURL       = "https://api.themoviedb.org/3"
    static let tmdbApiKey        = "460327acf6e0235a391222cb530de9c8"

    static let defaultUserAgent  = "VLC/3.0.20 LibVLC/3.0.20 (OTT Navigator; TiviMate)"
    static let browserUserAgent  = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    // ALL 44 STREAMBD IPTV PLAYLISTS BUNDLED DIRECTLY INSIDE APP
    static let bundledPlaylists: [EmbeddedPlaylist] = [
        // Bangladeshi Channels & Local OTT
        EmbeddedPlaylist(name: "AKASH GO", url: "https://raw.githubusercontent.com/ahmedstore75/Ajker-Live-Khela/HEAD/akash_go.m3u", logo: "https://play-lh.googleusercontent.com/L5ax9d0RvBuvMy6kfnMT9G-CteqBVGST5owFLLsaRrkqsRmuSrp49MugaZ1r2cl7e8M", category: "Bangla TV"),
        EmbeddedPlaylist(name: "Toffee", url: "https://myselfhridoy.github.io/streambd-libs/playlists/toffee.js", logo: "https://downloadr2.apkmirror.com/wp-content/uploads/2023/06/24/6490a7ce043bb_com.banglalink.toffeetv.png", category: "Bangla TV"),
        EmbeddedPlaylist(name: "Bioscope +", url: "https://myselfhridoy.github.io/streambd-libs/playlists/bioscope-plus.m3u", logo: "https://play-lh.googleusercontent.com/gctCHunQPvp-LBOEcfSpDeKNPxDuVDmbsv3rhApeGmefLjXC0bt5Fzt3YYGZWQ5m3g", category: "Bangla TV"),
        EmbeddedPlaylist(name: "JagoBD", url: "https://myselfhridoy.github.io/streambd-libs/playlists/jagobd.m3u", logo: "https://play-lh.googleusercontent.com/B7eTFyvy4CgBsHSGTP66pFaJ637P9Ihkoq-ZMP2zQPwlXr5QrJdFNIsK6taIbjbdcAc", category: "Bangla TV"),
        EmbeddedPlaylist(name: "Ayna OTT", url: "https://myselfhridoy.github.io/streambd-libs/playlists/ayna.js", logo: "", category: "Bangla OTT"),
        EmbeddedPlaylist(name: "OTT Plus", url: "https://myselfhridoy.github.io/streambd-libs/playlists/ottplus.js", logo: "", category: "Bangla OTT"),
        EmbeddedPlaylist(name: "iScreen", url: "https://myselfhridoy.github.io/streambd-libs/playlists/iscreen.js", logo: "", category: "Bangla OTT"),
        EmbeddedPlaylist(name: "Torongo+", url: "https://myselfhridoy.github.io/streambd-libs/playlists/torongoplus.js", logo: "", category: "Bangla OTT"),
        EmbeddedPlaylist(name: "Cirkle TV", url: "https://myselfhridoy.github.io/streambd-libs/playlists/cirkletv.js", logo: "", category: "Bangla TV"),
        EmbeddedPlaylist(name: "Rangdhanu Live", url: "https://myselfhridoy.github.io/streambd-libs/playlists/rangdhanulive.js", logo: "", category: "Bangla TV"),
        EmbeddedPlaylist(name: "RoarZone TV", url: "https://myselfhridoy.github.io/streambd-libs/playlists/roarzoneftp.js", logo: "", category: "Bangla TV"),
        EmbeddedPlaylist(name: "StreamBD IPTV", url: "https://myselfhridoy.github.io/streambdAPI/api/live_tv/live_channels.enc", logo: "", category: "StreamBD Official"),

        // Sports & Cricket
        EmbeddedPlaylist(name: "StreamBD LIVE", url: "https://myselfhridoy.github.io/streambdAPI/api/streamedPK/events.enc", logo: "", category: "Sports"),
        EmbeddedPlaylist(name: "StreamBD Events", url: "https://myselfhridoy.github.io/streambd-libs/playlists/damitv.js", logo: "", category: "Sports"),
        EmbeddedPlaylist(name: "FanCode BD", url: "https://raw.githubusercontent.com/abusaeeidx/CrestSport-IPTV-Collection/refs/heads/main/fncbd.m3u", logo: "", category: "Sports"),
        EmbeddedPlaylist(name: "FanCode Worldwide", url: "https://myselfhridoy.github.io/streambd-libs/playlists/fancodeww.js", logo: "", category: "Sports"),
        EmbeddedPlaylist(name: "CricLive", url: "https://myselfhridoy.github.io/streambd-libs/playlists/CricGo.js", logo: "", category: "Sports"),
        EmbeddedPlaylist(name: "ICC TV", url: "https://raw.githubusercontent.com/doctor-8trange/nexphi0/refs/heads/main/data/icc.m3u", logo: "", category: "Sports"),
        EmbeddedPlaylist(name: "Fifa Plus", url: "https://raw.githubusercontent.com/srhady/fifaplus/refs/heads/main/fifa_live.m3u", logo: "", category: "Sports"),
        EmbeddedPlaylist(name: "SportzX", url: "https://raw.githubusercontent.com/Ajayone8x/sportzx-playlist/refs/heads/main/Sportzx.m3u8", logo: "", category: "Sports"),
        EmbeddedPlaylist(name: "SonyLiv Events", url: "https://raw.githubusercontent.com/srhady/SonyLiv/refs/heads/main/sonyliv_playlist.m3u", logo: "", category: "Sports"),
        EmbeddedPlaylist(name: "PlayzTV Live", url: "https://raw.githubusercontent.com/abusaeeidx/BDxTV/refs/heads/main/playlist_s.m3u", logo: "", category: "Sports"),
        EmbeddedPlaylist(name: "Tapmad", url: "https://myselfhridoy.github.io/streambd-libs/playlists/tapmad.js", logo: "", category: "Sports"),

        // BDIX & FTP Server Playlists
        EmbeddedPlaylist(name: "FTP: PlusBox", url: "https://myselfhridoy.github.io/streambd-libs/playlists/plusbox.js", logo: "https://plusbox.tv/img/logo.png", category: "BDIX FTP"),
        EmbeddedPlaylist(name: "FTP: 11Plus", url: "https://myselfhridoy.github.io/streambd-libs/playlists/11plusftp.js", logo: "", category: "BDIX FTP"),
        EmbeddedPlaylist(name: "FTP: BDIPTV", url: "https://myselfhridoy.github.io/streambd-libs/playlists/bdiptv.js", logo: "", category: "BDIX FTP"),
        EmbeddedPlaylist(name: "FTP: BDIX BD 1", url: "https://myselfhridoy.github.io/streambd-libs/playlists/bdixbd1.js", logo: "", category: "BDIX FTP"),
        EmbeddedPlaylist(name: "FTP: BDIX BD 2", url: "https://myselfhridoy.github.io/streambd-libs/playlists/bdixbd2.js", logo: "", category: "BDIX FTP"),
        EmbeddedPlaylist(name: "FTP: City Plex", url: "https://myselfhridoy.github.io/streambd-libs/playlists/bdixserver001.m3u", logo: "", category: "BDIX FTP"),
        EmbeddedPlaylist(name: "FTP: IPTVIDN", url: "https://myselfhridoy.github.io/streambd-libs/playlists/iptvidn.js", logo: "", category: "BDIX FTP"),
        EmbeddedPlaylist(name: "FTP: Matha Nosto TV", url: "https://myselfhridoy.github.io/streambd-libs/playlists/mathanostotv.js", logo: "", category: "BDIX FTP"),
        EmbeddedPlaylist(name: "FTP: PlayTimeBD", url: "http://flix.playtimebd.live/rest-api//v130?portal=oxoo&key=rg26txskl4w5guz2dz7xvc8x&token=Basic YWRtaW46MTIzNA==", logo: "", category: "BDIX FTP"),
        EmbeddedPlaylist(name: "Portal Server 01", url: "https://otapp.store/rest-api/v130?portal=oxoo&key=ottbangla@android&token=Basic YWRtaW46MTIzNA==", logo: "", category: "BDIX Portal"),
        EmbeddedPlaylist(name: "Portal Server 02", url: "https://app.allconnectonlinebd.com/padmax/rest-api/v130?portal=oxoo&key=padma3340flix&token=Basic YWRtaW46MTIzNA==", logo: "", category: "BDIX Portal"),
        EmbeddedPlaylist(name: "Portal Server 03", url: "https://admin.money-hunting.shop/rest-api/v130?portal=oxoo&key=42rpxoiv8dy9sbwgg5up296h&token=Basic YWRtaW46MTIzNA==", logo: "", category: "BDIX Portal"),
        EmbeddedPlaylist(name: "Portal Server 04", url: "https://play.onushil.com/rest-api/v130?portal=oxoo&key=0334c0755f4d448&token=Basic YWRtaW46MTIzNA==", logo: "", category: "BDIX Portal"),

        // Indian & International Entertainment
        EmbeddedPlaylist(name: "Jio TV S1", url: "https://myselfhridoy.github.io/streambd-libs/playlists/jiowws1.js", logo: "", category: "Indian TV"),
        EmbeddedPlaylist(name: "Jio TV S2", url: "https://myselfhridoy.github.io/streambd-libs/playlists/jtvplus.js", logo: "", category: "Indian TV"),
        EmbeddedPlaylist(name: "Jio TV+", url: "https://raw.githubusercontent.com/amazeyourself/m3u/refs/heads/main/jtv.m3u", logo: "", category: "Indian TV"),
        EmbeddedPlaylist(name: "SonyLiv", url: "https://myselfhridoy.github.io/streambd-libs/playlists/sonyLiv.js", logo: "", category: "Indian TV"),
        EmbeddedPlaylist(name: "Zee5", url: "https://myselfhridoy.github.io/streambd-libs/playlists/zee5.js", logo: "", category: "Indian TV"),
        EmbeddedPlaylist(name: "TV Network", url: "https://myselfhridoy.github.io/streambd-libs/playlists/tvnetwork001.js", logo: "", category: "International"),
        EmbeddedPlaylist(name: "SF TV", url: "https://m3u-tvb.pages.dev/sf-playlist.m3u", logo: "", category: "International"),
        EmbeddedPlaylist(name: "YouTube TV", url: "https://pastebin.com/raw/HYjN3KfA", logo: "", category: "International")
    ]

    // ALL 24 STREAMBD VOD ADDON SCRAPERS
    static let bundledAddons: [Addon] = [
        Addon(id: "cineplexbd_parser", name: "Cineplex BD (BDIX)", url: "https://myselfhridoy.github.io/streambd-libs/addons/cineplexbd.js", enabled: true),
        Addon(id: "ctgmovies", name: "CTG Movies FTP (BDIX)", url: "https://myselfhridoy.github.io/streambd-libs/addons/ctgmovies.js", enabled: true),
        Addon(id: "netmirror_parser", name: "Net Mirror", url: "https://myselfhridoy.github.io/streambd-libs/addons/netmirror.js", enabled: true),
        Addon(id: "11plusweb_parser", name: "11Plus WEB", url: "https://myselfhridoy.github.io/streambd-libs/addons/11plusweb.js", enabled: true),
        Addon(id: "timepassbdcdn_parser", name: "TimePassBD CDN", url: "https://myselfhridoy.github.io/streambd-libs/addons/timepassbdcdn.js", enabled: true),
        Addon(id: "ibccl-ftp", name: "IBCCL FTP", url: "https://myselfhridoy.github.io/streambd-libs/addons/ibccl-ftp.js", enabled: true),
        Addon(id: "cinefreak", name: "CineFreak", url: "https://myselfhridoy.github.io/streambd-libs/addons/cinefreak.js", enabled: true),
        Addon(id: "movielinkbd", name: "MovieLinkBD", url: "https://myselfhridoy.github.io/streambd-libs/addons/movielinkbd.js", enabled: true),
        Addon(id: "hdhub4u_parser", name: "HDHub4U", url: "https://myselfhridoy.github.io/streambd-libs/addons/hdhub4u.js", enabled: true),
        Addon(id: "ftpbdweb_parser", name: "FTPBD WEB", url: "https://myselfhridoy.github.io/streambd-libs/addons/ftpbdweb.js", enabled: true),
        Addon(id: "ftpbdcdn_parser", name: "FTPBD CDN", url: "https://myselfhridoy.github.io/streambd-libs/addons/ftpbdcdn.js", enabled: true),
        Addon(id: "vixsrc_parser", name: "VixSrc", url: "https://myselfhridoy.github.io/streambd-libs/addons/vixsrc.js", enabled: true),
        Addon(id: "ppcine_parser", name: "PPCine", url: "https://myselfhridoy.github.io/streambd-libs/addons/ppcine.js", enabled: true),
        Addon(id: "moviebox_parser", name: "MovieBox", url: "https://myselfhridoy.github.io/streambd-libs/addons/moviebox.js", enabled: true),
        Addon(id: "cinetv_parser", name: "CineTV", url: "https://myselfhridoy.github.io/streambd-libs/addons/cinetv.js", enabled: true),
        Addon(id: "bingr_parser", name: "Bingr", url: "https://myselfhridoy.github.io/streambd-libs/addons/bingr-one.js", enabled: true),
        Addon(id: "vidbolt_parser", name: "VidBolt", url: "https://myselfhridoy.github.io/streambd-libs/addons/vidbolt.js", enabled: true),
        Addon(id: "vidnest_parser", name: "VidNest", url: "https://myselfhridoy.github.io/streambd-libs/addons/vidnest.js", enabled: true),
        Addon(id: "roarzone-emby", name: "RoarZone EMBY", url: "https://myselfhridoy.github.io/streambd-libs/addons/roarzone-emby.js", enabled: true),
        Addon(id: "rtally_parser", name: "Rtally", url: "https://myselfhridoy.github.io/streambd-libs/addons/rtally.js", enabled: true),
        Addon(id: "royalflic_parser", name: "RoyalFlix", url: "https://myselfhridoy.github.io/streambd-libs/addons/royalflix.js", enabled: true),
        Addon(id: "omh_parser", name: "Online Movies Hindi", url: "https://myselfhridoy.github.io/streambd-libs/addons/OMH.js", enabled: true),
        Addon(id: "nhd_parser", name: "NHD API", url: "https://myselfhridoy.github.io/streambd-libs/addons/NHD.js", enabled: true)
    ]
}
