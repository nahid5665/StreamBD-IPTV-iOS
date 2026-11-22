import SwiftUI

// MARK: - Search (dx.bi's SearchView): recent searches, hints, then shelf results

struct DxSearchView: View {
    @ObservedObject var mainVM: MainViewModel
    @ObservedObject var vodVM: VODViewModel
    @State private var query = ""
    @State private var searched = ""
    @AppStorage("dx_recent_searches") private var recentText = ""
    @State private var activeChannel: Channel? = nil

    private var recent: [String] { recentText.split(separator: "\n").map(String.init) }

    var body: some View {
        ScrollView {
            if searched.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    if !recent.isEmpty {
                        HStack {
                            Text("Recent Searches").font(.title3.bold())
                            Spacer()
                            Button("Clear") { recentText = "" }.font(.subheadline)
                        }
                        ForEach(recent, id: \.self) { r in
                            Button { query = r; run() } label: {
                                Label(r, systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }
                    }
                    hints.padding(.top, recent.isEmpty ? 60 : 30)
                }
                .padding(.horizontal, Dx.gutter)
            } else {
                LazyVStack(alignment: .leading, spacing: 28) {
                    // Live TV channels first: they play at once
                    let channelHits = mainVM.allChannels.filter { $0.name.localizedCaseInsensitiveContains(searched) }
                    if !channelHits.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Live TV").font(.title2.bold()).padding(.horizontal, Dx.gutter)
                            DxChannelGrid(channels: Array(channelHits.prefix(12)), onPlay: { ch in activeChannel = ch })
                        }
                    }

                    let rows = vodVM.searchResults
                    if !rows.isEmpty {
                        DxShelf(title: "Movies & Shows") {
                            ForEach(rows.prefix(20)) { title in
                                NavigationLink(value: DxRoute.title(title)) {
                                    DxPosterCard(title: title, width: 130)
                                        .dxZoomSource("tmdb-\(title.id)")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if rows.isEmpty && channelHits.isEmpty && !loading {
                        DxEmptyState.searchFallback(text: searched)
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity).padding(40) }
                }
            }
        }
        .padding(.bottom, 30)
        .background(Dx.background.ignoresSafeArea())
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Films, shows, channels")
        .onSubmit(of: .search, run)
        .onChange(of: query) { q in if q.isEmpty { searched = "" } }
        .sheet(item: $activeChannel) { ch in
            StreamPlayerSheet(channel: ch)
        }
        .task(id: query) {
            // as they type, after a moment's pause (dx.bi's debounce)
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 3 else { return }
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled, q != searched { searched = q; run() }
        }
    }

    @State private var loading = false

    private func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searched = q
        recentText = ([q] + recent.filter { $0 != q }).prefix(8).joined(separator: "\n")
        loading = true
        Task {
            vodVM.searchQuery = q
            await vodVM.search()
            loading = false
        }
    }

    /** Nothing typed yet: what Search finds, as dx.bi's desktop app says it */
    private var hints: some View {
        VStack(spacing: 30) {
            Text("You can search anything…").font(.title3).foregroundStyle(Dx.muted)
            HStack(alignment: .top, spacing: 12) {
                ForEach([("film.stack", "Movies, series & anime"), ("tv", "Live TV from your server"), ("person.fill", "Actors & directors")], id: \.0) { icon, label in
                    VStack(spacing: 12) {
                        Image(systemName: icon).font(.system(size: 34)).frame(height: 40)
                        Text(label).font(.footnote).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Dx.muted)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension DxEmptyState {
    static func searchFallback(text: String) -> DxEmptyState {
        DxEmptyState(title: "No Results", systemImage: "magnifyingglass", description: "Nothing matches “\(text)”.")
    }
}
