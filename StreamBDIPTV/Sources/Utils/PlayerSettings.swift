import Foundation
import UIKit

/// App-wide video player engine preference, persisted in UserDefaults.
/// - auto:    smart routing (VLC for TS/MKV/RTMP streams, AVPlayer first otherwise,
///            automatic VLC fallback on AVPlayer failure)
/// - vlc:     always use VLC (MobileVLCKit)
/// - avPlayer: always use AVPlayer (no automatic VLC fallback)
enum PlayerEnginePreference: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case vlc = "VLC"
    case avPlayer = "AVPlayer"

    var id: String { rawValue }
}

enum PlayerSettings {
    static let storageKey = "eentertainment_player_engine_v1"

    static var preference: PlayerEnginePreference {
        get {
            PlayerEnginePreference(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }
}

/// Where playback is handed off: inside this app, or to the installed
/// VLC app via its vlc://x-callback-url scheme (URL + title only —
/// custom headers are not forwarded to the external app).
enum PlayerDestination: String, CaseIterable, Identifiable {
    case inApp = "This App"
    case vlcApp = "VLC App"

    var id: String { rawValue }

    static let storageKey = "eentertainment_player_destination_v1"

    static var current: PlayerDestination {
        get {
            PlayerDestination(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .inApp
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }
}

/// Integration with the standalone VLC iOS app (x-callback-url scheme).
enum VLCAppIntegration {
    static var isVLCInstalled: Bool {
        guard let url = URL(string: "vlc://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Hands a stream URL to the installed VLC app. Returns false when VLC
    /// is not installed or the URL cannot be represented.
    @discardableResult
    static func open(streamURL: String, title: String?) -> Bool {
        guard let stream = URL(string: streamURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              stream.scheme == "http" || stream.scheme == "https" || stream.scheme == "rtmp" else {
            return false
        }

        var components = URLComponents(string: "vlc://x-callback-url/stream")
        var items: [URLQueryItem] = [URLQueryItem(name: "url", value: stream.absoluteString)]
        if let title, !title.isEmpty {
            items.append(URLQueryItem(name: "title", value: title))
        }
        components?.queryItems = items

        guard let vlcURL = components?.url else { return false }
        UIApplication.shared.open(vlcURL, options: [:], completionHandler: nil)
        return true
    }
}
