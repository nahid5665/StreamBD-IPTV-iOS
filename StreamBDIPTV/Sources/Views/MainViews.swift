import SwiftUI

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}


struct LiveTVView: View {
    @ObservedObject var viewModel: MainViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.availableGroups, id: \.self) { group in
                            Button {
                                viewModel.selectedCategory = group
                            } label: {
                                Text(group)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(viewModel.selectedCategory == group ? Color.red : Color.secondary.opacity(0.15))
                                    .foregroundStyle(viewModel.selectedCategory == group ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                if viewModel.isLoading && viewModel.allChannels.isEmpty {
                    Spacer()
                    ProgressView("Loading StreamBD Live TV Channels…")
                    Spacer()
                } else if viewModel.filteredChannels.isEmpty {
                    Spacer()
                    EmptyStateView(title: "No Channels Found", systemImage: "tv.slash", message: "Try another category or tap refresh.")
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(viewModel.filteredChannels) { channel in
                                Button {
                                    viewModel.activeChannel = channel
                                } label: {
                                    VStack(spacing: 8) {
                                        AsyncImage(url: URL(string: channel.logo)) { phase in
                                            if let image = phase.image {
                                                image
                                                    .resizable()
                                                    .scaledToFit()
                                            } else {
                                                Image(systemName: "tv.fill")
                                                    .font(.title)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(height: 56)
                                        .padding(6)

                                        Text(channel.name)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("StreamBD Live TV")
            .searchable(text: $viewModel.searchQuery, prompt: "Search channels & categories…")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.loadAllLiveChannels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(item: $viewModel.activeChannel) { ch in
                StreamPlayerSheet(channel: ch)
            }
        }
    }
}

struct EventsView: View {
    @StateObject private var viewModel = EventsViewModel()
    @State private var activeChannel: Channel? = nil
    @State private var isResolvingEvent: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Toggle("LIVE ONLY", isOn: $viewModel.liveOnly)
                            .toggleStyle(.button)
                            .tint(.red)
                            .font(.caption.bold())

                        ForEach(viewModel.availableSports, id: \.self) { sport in
                            Button {
                                viewModel.selectedSport = sport
                            } label: {
                                Text(sport)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(viewModel.selectedSport == sport ? Color.red : Color.secondary.opacity(0.15))
                                    .foregroundStyle(viewModel.selectedSport == sport ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                if viewModel.isLoading && viewModel.events.isEmpty {
                    Spacer()
                    ProgressView("Loading Live Sports Events…")
                    Spacer()
                } else if viewModel.filteredEvents.isEmpty {
                    Spacer()
                    EmptyStateView(title: "No Events Found", systemImage: "sportscourt", message: "Pull to refresh or check back at match kickoff.")
                    Spacer()
                } else {
                    List(viewModel.filteredEvents) { event in
                        Button {
                            Task {
                                isResolvingEvent = true
                                if let ch = await viewModel.fetchEventChannel(for: event) {
                                    activeChannel = ch
                                }
                                isResolvingEvent = false
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        if event.isLiveNow {
                                            Text("LIVE")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.red)
                                                .foregroundStyle(.white)
                                                .clipShape(Capsule())
                                        }
                                        Text(event.league ?? event.sport ?? "Match")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(event.displayTitle)
                                        .font(.headline)
                                    if let starts = event.starts_at, !starts.isEmpty {
                                        Text(starts)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.red)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Live Events")
            .overlay {
                if isResolvingEvent {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        ProgressView("Resolving Event Streams…")
                            .padding(20)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.loadEvents() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                if viewModel.events.isEmpty {
                    await viewModel.loadEvents()
                }
            }
            .sheet(item: $activeChannel) { ch in
                StreamPlayerSheet(channel: ch)
            }
        }
    }
}

struct MediaVODView: View {
    @StateObject private var viewModel = VODViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !viewModel.searchResults.isEmpty {
                        mediaSection(title: "Search Results", items: viewModel.searchResults)
                    }
                    mediaSection(title: "Trending Movies", items: viewModel.trendingMovies)
                    mediaSection(title: "Trending TV Shows", items: viewModel.trendingTV)
                    mediaSection(title: "Bengali Movies", items: viewModel.banglaMovies)
                    mediaSection(title: "Bollywood Hits", items: viewModel.bollywoodMovies)
                }
                .padding(.vertical)
            }
            .navigationTitle("Movies & TV")
            .searchable(text: $viewModel.searchQuery, prompt: "Search movies & TV shows…")
            .onSubmit(of: .search) {
                Task { await viewModel.search() }
            }
            .task {
                await viewModel.loadCatalog()
            }
        }
    }

    @ViewBuilder
    private func mediaSection(title: String, items: [TmdbMedia]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: URL(string: item.posterURL)) { phase in
                                    if let img = phase.image {
                                        img.resizable().scaledToFill()
                                    } else {
                                        Color.secondary.opacity(0.2)
                                            .overlay(Image(systemName: "film"))
                                    }
                                }
                                .frame(width: 120, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                                Text(item.displayTitle)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(width: 120, alignment: .leading)

                                Text(item.displayDate)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct PlaylistsStreamView: View {
    @StateObject private var viewModel = PlaylistViewModel()
    @State private var newTitle: String = ""
    @State private var newUrl: String = ""
    @State private var directUrl: String = ""
    @State private var directReferer: String = ""
    @State private var directUserAgent: String = ""
    @State private var directCookie: String = ""
    @State private var activeChannel: Channel? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Direct Network Stream Player") {
                    TextField("Stream URL (.m3u8 / .mp4 / pipe URL)", text: $directUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Referer (Optional)", text: $directReferer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("User-Agent (Optional)", text: $directUserAgent)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Cookie (Optional)", text: $directCookie)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        let parsed = M3UParser.parseUrlHeaders(directUrl)
                        var headers = parsed.headers
                        if !directReferer.isEmpty { headers["Referer"] = directReferer }
                        if !directUserAgent.isEmpty { headers["User-Agent"] = directUserAgent }
                        if !directCookie.isEmpty { headers["Cookie"] = directCookie }
                        activeChannel = Channel(
                            name: "Network Stream",
                            url: parsed.cleanUrl,
                            logo: "",
                            group: "Custom Stream",
                            userAgent: headers["User-Agent"],
                            cookie: headers["Cookie"],
                            httpReferer: headers["Referer"],
                            httpHeaders: headers,
                            sources: ["Direct": directUrl]
                        )
                    } label: {
                        Label("Play Network Stream", systemImage: "play.fill")
                    }
                    .disabled(directUrl.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Add Custom M3U / JSON Playlist") {
                    TextField("Playlist Title", text: $newTitle)
                    TextField("Playlist URL (M3U / JSON)", text: $newUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Add Playlist") {
                        viewModel.addPlaylist(title: newTitle.isEmpty ? "Custom Playlist" : newTitle, url: newUrl)
                        newTitle = ""
                        newUrl = ""
                    }
                    .disabled(newUrl.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Saved Playlists") {
                    if viewModel.playlists.isEmpty {
                        Text("No custom playlists added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.playlists) { pl in
                            NavigationLink {
                                CustomPlaylistDetailView(playlist: pl, viewModel: viewModel)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(pl.title).font(.headline)
                                    Text(pl.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .onDelete { idxSet in
                            for i in idxSet {
                                viewModel.deletePlaylist(viewModel.playlists[i])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Playlists & Stream")
            .sheet(item: $activeChannel) { ch in
                StreamPlayerSheet(channel: ch)
            }
        }
    }
}

struct CustomPlaylistDetailView: View {
    let playlist: UserPlaylist
    @ObservedObject var viewModel: PlaylistViewModel
    @State private var activeChannel: Channel? = nil

    var body: some View {
        List(viewModel.selectedPlaylistChannels) { ch in
            Button {
                activeChannel = ch
            } label: {
                HStack {
                    Text(ch.name).font(.body.weight(.medium))
                    Spacer()
                    Text(ch.group).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if viewModel.isLoadingPlaylist {
                ProgressView("Loading Playlist…")
            }
        }
        .navigationTitle(playlist.title)
        .task {
            await viewModel.loadChannels(from: playlist)
        }
        .sheet(item: $activeChannel) { ch in
            StreamPlayerSheet(channel: ch)
        }
    }
}

struct ContentView: View {
    @StateObject private var mainViewModel = MainViewModel()

    var body: some View {
        TabView {
            LiveTVView(viewModel: mainViewModel)
                .tabItem {
                    Label("Live TV", systemImage: "tv.fill")
                }

            EventsView()
                .tabItem {
                    Label("Live Events", systemImage: "sportscourt.fill")
                }

            MediaVODView()
                .tabItem {
                    Label("Movies & TV", systemImage: "film.stack.fill")
                }

            PlaylistsStreamView()
                .tabItem {
                    Label("Playlists", systemImage: "list.bullet.rectangle.portrait.fill")
                }
        }
        .tint(.red)
        .task {
            if mainViewModel.allChannels.isEmpty {
                await mainViewModel.loadAllLiveChannels()
            }
        }
    }
}

@main
struct StreamBDIPTVApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
