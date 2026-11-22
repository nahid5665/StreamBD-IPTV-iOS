import SwiftUI

// MARK: - Library (dx.bi's LibraryView shape): custom M3U playlists and the addon list

struct DxLibraryView: View {
    @ObservedObject var mainVM: MainViewModel
    @ObservedObject var vodVM: VODViewModel
    @StateObject private var playlistVM = PlaylistViewModel()

    @State private var section = "Playlists"
    @State private var addPlaylist = false
    @State private var newTitle = ""
    @State private var newURL = ""
    @State private var addAddon = false
    @State private var addonName = ""
    @State private var addonURL = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Section", selection: $section) {
                    Text("Playlists").tag("Playlists")
                    Text("Addons").tag("Addons")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if section == "Playlists" { playlists } else { addons }
            }
            .padding(.bottom, 30)
        }
        .background(Dx.background.ignoresSafeArea())
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if section == "Playlists" { addPlaylist = true } else { addAddon = true }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(section == "Playlists" ? "Add a playlist" : "Add an addon")
            }
        }
        .alert("New Playlist", isPresented: $addPlaylist) {
            TextField("Name", text: $newTitle)
            TextField("M3U or JSON URL", text: $newURL)
            Button("Add") {
                let t = newTitle.trimmingCharacters(in: .whitespaces)
                let u = newURL.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty && !u.isEmpty { playlistVM.addPlaylist(title: t, url: u) }
                newTitle = ""; newURL = ""
            }
            Button("Cancel", role: .cancel) { newTitle = ""; newURL = "" }
        } message: {
            Text("An M3U, JSON or myiptv:// playlist URL.")
        }
        .alert("New JS Addon", isPresented: $addAddon) {
            TextField("Name", text: $addonName)
            TextField("Addon .js URL", text: $addonURL)
            Button("Add") {
                let n = addonName.trimmingCharacters(in: .whitespaces)
                let u = addonURL.trimmingCharacters(in: .whitespaces)
                if !u.isEmpty { vodVM.addCustomJSAddon(name: n.isEmpty ? "Addon" : n, url: u) }
                addonName = ""; addonURL = ""
            }
            Button("Cancel", role: .cancel) { addonName = ""; addonURL = "" }
        } message: {
            Text("Runs in the app's JS runner, like the built-in addons.")
        }
    }

    /** The user's playlists, as dx.bi's library grid opens a title */
    private var playlists: some View {
        VStack(spacing: 12) {
            if playlistVM.playlists.isEmpty {
                DxEmptyState(title: "No Playlists", systemImage: "rectangle.stack", description: "Tap + to add an M3U or portal playlist.")
                    .padding(.top, 40)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(playlistVM.playlists) { pl in
                        NavigationLink {
                            PlaylistChannelListView(
                                playlist: EmbeddedPlaylist(name: pl.title, url: pl.url, logo: "", category: "Playlist"),
                                viewModel: mainVM
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tv.rectangle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Dx.muted)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pl.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                                    Text(pl.url).font(.caption).foregroundStyle(Dx.faint).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Dx.muted)
                            }
                            .padding(14)
                            .background(Dx.raised.opacity(0.7), in: .rect(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /** The resolvers every title page asks: the bundled ones plus what was added */
    private var addons: some View {
        VStack(spacing: 10) {
            ForEach(vodVM.addons) { addon in
                HStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.title3)
                        .foregroundStyle(addon.enabled ? Dx.accent : Dx.faint)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(addon.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                        Text(addon.url).font(.caption).foregroundStyle(Dx.faint).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { addon.enabled },
                        set: { _ in vodVM.toggleAddon(id: addon.id) }
                    ))
                    .labelsHidden()
                    .tint(Dx.accent)
                }
                .padding(14)
                .background(Dx.raised.opacity(0.7), in: .rect(cornerRadius: 18))
                .padding(.horizontal, 16)
            }
            Text("Manage everything in Profile → Addons & Settings.")
                .font(.caption)
                .foregroundStyle(Dx.muted)
                .padding(.top, 8)
        }
    }
}
