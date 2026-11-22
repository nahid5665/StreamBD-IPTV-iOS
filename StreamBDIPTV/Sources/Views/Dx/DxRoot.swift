import SwiftUI

// MARK: - dx.bi root (ported from dxbi-stremio ios/Dxbi/App.swift)
// Four tabs (Home · Discover · Library · Search), every screen dx.bi's motion:
// titles open by growing out of the card that was tapped (iOS 18+), springs everywhere.

enum DxTab: Hashable { case home, discover, library, search }

/// Where a tab's stack can go
enum DxRoute: Hashable {
    case title(TmdbMedia)
    /// A row's See All: which catalog and its name
    case browse(name: String, kind: String)
    case channels(group: String)
}

struct DxRootView: View {
    @StateObject private var mainVM = MainViewModel()
    @StateObject private var vodVM = VODViewModel()
    @State private var tab: DxTab = .home
    @State private var account = false
    @State private var introVisible = true
    @State private var message: String? = nil

    var body: some View {
        ZStack {
            tabs
        }
        .background(Dx.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let message {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .dxGlass(in: .capsule)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { self.message = nil }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message)
        .sheet(isPresented: $account) {
            DxAccountSheet(mainVM: mainVM, vodVM: vodVM)
                .environmentObject(mainVM)
                .environmentObject(vodVM)
        }
        // the intro: DX.BI on black, then the tabs come in
        .overlay {
            if introVisible {
                DxIntroView()
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(.easeOut(duration: 0.45)) { introVisible = false }
                    }
            }
        }
        .task {
            await mainVM.loadInitialPlaylists()
            if vodVM.trendingMovies.isEmpty {
                await vodVM.loadCatalog()
            }
        }
        .onAppear {
            // A tiny toast helper for the deep screens
            DxToast.shared.show = { text in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { message = text }
                Task {
                    try? await Task.sleep(for: .seconds(2.2))
                    withAnimation(.easeOut(duration: 0.3)) { if message == text { message = nil } }
                }
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            DxStack { DxHomeView(mainVM: mainVM, vodVM: vodVM) }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(DxTab.home)
            DxStack { DxDiscoverView(mainVM: mainVM, vodVM: vodVM) }
                .tabItem { Label("Discover", systemImage: "square.grid.2x2.fill") }
                .tag(DxTab.discover)
            DxStack { DxLibraryView(mainVM: mainVM, vodVM: vodVM) }
                .tabItem { Label("Library", systemImage: "rectangle.stack.fill") }
                .tag(DxTab.library)
            DxStack { DxSearchView(mainVM: mainVM, vodVM: vodVM) }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(DxTab.search)
        }
        .tint(.white)
        .environmentObject(mainVM)
        .environmentObject(vodVM)
    }
}

// MARK: - A tab's navigation, with every screen it can open (dx.bi's Stack)

struct DxStack<Content: View>: View {
    @ViewBuilder var content: Content
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: DxRoute.self) { route in
                    switch route {
                    case .title(let media):
                        DxTitleView(media: media)
                            .dxZoomDestination("tmdb-\(media.id)", in: zoom)
                    case .browse(let name, let kind):
                        DxBrowseView(name: name, kind: kind)
                    case .channels(let group):
                        DxChannelsView(group: group)
                    }
                }
        }
        .environment(\.dxZoom, zoom)
    }
}

private struct DxZoomKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /** The tab's namespace: titles open by growing out of the card that was tapped */
    var dxZoom: Namespace.ID? {
        get { self[DxZoomKey.self] }
        set { self[DxZoomKey.self] = newValue }
    }
}

extension View {
    /** The card a title opens from (see DxStack) */
    func dxZoomSource(_ id: String) -> some View {
        modifier(DxZoomSourceModifier(id: id))
    }
}

struct DxZoomSourceModifier: ViewModifier {
    var id: String
    @Environment(\.dxZoom) private var zoom
    func body(content: Content) -> some View {
        content.dxZoomSource(id, in: zoom)
    }
}

// MARK: - Tiny global toast (dx.bi's message capsule)

@MainActor
final class DxToast {
    static let shared = DxToast()
    var show: ((String) -> Void)? = nil
}

// MARK: - The intro: DX.BI on black, glowing in (dx.bi's splash)

struct DxIntroView: View {
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(colors: [Dx.accent.opacity(0.22), .black, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            DxLogo(size: 84)
                .scaleEffect(shown ? 1 : 0.8)
                .opacity(shown ? 1 : 0)
        }
        .task {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { shown = true }
        }
    }
}

// MARK: - See All (a row's catalog page)

struct DxBrowseView: View {
    var name: String
    var kind: String

    var body: some View {
        DxCatalogGrid(kind: kind, fixedName: name)
            .background(Dx.background.ignoresSafeArea())
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - All channels of one group (See All from a Live TV row)

struct DxChannelsView: View {
    var group: String
    @EnvironmentObject private var mainVM: MainViewModel
    @State private var activeChannel: Channel? = nil

    var body: some View {
        ScrollView {
            DxChannelGrid(channels: channels, onPlay: { ch in activeChannel = ch })
                .padding(.vertical, 10)
        }
        .background(Dx.background.ignoresSafeArea())
        .navigationTitle(group)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeChannel) { ch in
            StreamPlayerSheet(channel: ch)
        }
    }

    private var channels: [Channel] {
        let all = mainVM.allChannels
        return group == "All" ? all : all.filter { $0.group == group }
    }
}
