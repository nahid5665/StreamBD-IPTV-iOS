import SwiftUI

// MARK: - dx.bi AccountView (ported from dxbi-stremio ios/Dxbi/UI/AccountView.swift)
// Profile: the app, the addons, the server, the settings — no more fifth tab.

struct DxAccountSheet: View {
    @ObservedObject var mainVM: MainViewModel
    @ObservedObject var vodVM: VODViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        DxAvatar(email: "Nahid").scaleEffect(1.6).frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DX.BI").font(.custom("BebasNeue-Regular", size: 24)).foregroundStyle(Dx.accent)
                            Text("\(mainVM.allChannels.count) live channels · \(vodVM.addons.count) addons").font(.footnote).foregroundStyle(Dx.muted)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }
                Section {
                    NavigationLink { SettingsNetflixView(vodVM: vodVM, liveVM: mainVM) } label: { Label("Addons & Settings", systemImage: "slider.horizontal.3") }
                    NavigationLink { AddonDiagnosticsView() } label: { Label("Addon Diagnostics", systemImage: "stethoscope") }
                    NavigationLink { LibraryViewPlaceholder() } label: { Label("Custom Playlists", systemImage: "rectangle.stack.fill") }
                    NavigationLink { PlaybackSettingsRow() } label: { Label("Playback", systemImage: "play.rectangle.fill") }
                }
                Section {
                    Button {
                        Task { await TokenRefreshManager.shared.refreshAllTokens() }
                        DxToast.shared.show?("Live tokens refreshed")
                    } label: {
                        Label("Refresh Live Tokens Now", systemImage: "arrow.clockwise")
                    }
                } footer: {
                    Text("dx.bi-style UI · Eentertainment \(AppConfig.appVersion) · Not affiliated with Stremio.")
                }
            }
            .scrollContentBackground2(.hidden)
            .background(Color.black)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Library's playlists live in the Library tab; this row links the same screen.
struct LibraryViewPlaceholder: View {
    var body: some View {
        DxEmptyState(title: "Playlists & Addons", systemImage: "rectangle.stack", description: "Find them in the Library tab, plus + to add new ones.")
    }
}

/// The player engine / destination switches, grouped like dx.bi's PlaybackSettingsView.
struct PlaybackSettingsRow: View {
    var body: some View {
        Form {
            Section("Engine") {
                Picker("Player engine", selection: Binding(
                    get: { PlayerSettings.preference },
                    set: { PlayerSettings.preference = $0 }
                )) {
                    ForEach(PlayerEnginePreference.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Destination") {
                Picker("Play in", selection: Binding(
                    get: { PlayerDestination.current },
                    set: { PlayerDestination.current = $0 }
                )) {
                    ForEach(PlayerDestination.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("Playback")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    @ViewBuilder
    func scrollContentBackground2(_ visibility: Visibility) -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(visibility)
        } else {
            self
        }
    }
}
