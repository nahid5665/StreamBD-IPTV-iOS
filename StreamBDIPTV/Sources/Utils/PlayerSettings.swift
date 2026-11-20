import Foundation

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
