import Foundation

@MainActor
final class PlaylistViewModel: ObservableObject {
    @Published var playlists: [UserPlaylist] = []
    @Published var selectedPlaylistChannels: [Channel] = []
    @Published var isLoadingPlaylist: Bool = false

    private let storageKey = "streambd_user_playlists_v5"

    init() {
        loadSavedPlaylists()
    }

    func loadSavedPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([UserPlaylist].self, from: data) else {
            return
        }
        self.playlists = saved
    }

    func addPlaylist(title: String, url: String) {
        let item = UserPlaylist(title: title, url: url)
        playlists.insert(item, at: 0)
        save()
    }

    func deletePlaylist(_ item: UserPlaylist) {
        playlists.removeAll { $0.id == item.id }
        save()
    }

    func loadChannels(from playlist: UserPlaylist) async {
        isLoadingPlaylist = true
        if let text = try? await NetworkManager.shared.fetchText(from: playlist.url) {
            selectedPlaylistChannels = M3UParser.parsePlaylist(text, defaultGroup: playlist.title)
        } else {
            selectedPlaylistChannels = []
        }
        isLoadingPlaylist = false
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
