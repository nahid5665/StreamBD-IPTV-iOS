import SwiftUI
import VLCKit

// MARK: - VLC Video Rendering Surface Container

class VLCVideoContainerView: UIView {
    weak var player: VLCMediaPlayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentMode = .scaleAspectFit
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        contentMode = .scaleAspectFit
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Ensure player binds to drawable once the view has positive dimensions
        if let player = player, bounds.width > 0, bounds.height > 0 {
            if player.drawable as? UIView != self {
                player.drawable = self
            }
        }
    }
}

// MARK: - SwiftUI Representable for VLC Player

struct VLCPlayerView: UIViewRepresentable {
    let url: URL
    let headers: [String: String]
    @Binding var player: VLCMediaPlayer?
    var onStateChanged: ((VLCMediaPlayerState) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, VLCMediaPlayerDelegate {
        var parent: VLCPlayerView
        var player: VLCMediaPlayer?
        var currentUrl: URL?

        init(_ parent: VLCPlayerView) {
            self.parent = parent
            super.init()
        }

        func mediaPlayerStateChanged(_ aNotification: Notification!) {
            guard let p = aNotification.object as? VLCMediaPlayer else { return }
            DispatchQueue.main.async {
                self.parent.onStateChanged?(p.state)
            }
        }
    }

    func makeUIView(context: Context) -> VLCVideoContainerView {
        let view = VLCVideoContainerView(frame: UIScreen.main.bounds)
        let mediaPlayer = VLCMediaPlayer()
        mediaPlayer.delegate = context.coordinator
        context.coordinator.player = mediaPlayer
        view.player = mediaPlayer
        mediaPlayer.drawable = view

        loadMedia(into: mediaPlayer, url: url, headers: headers)
        context.coordinator.currentUrl = url

        DispatchQueue.main.async {
            self.player = mediaPlayer
            mediaPlayer.play()
        }
        return view
    }

    func updateUIView(_ uiView: VLCVideoContainerView, context: Context) {
        uiView.player = context.coordinator.player
        if context.coordinator.currentUrl != url {
            context.coordinator.currentUrl = url
            if let p = context.coordinator.player {
                loadMedia(into: p, url: url, headers: headers)
                DispatchQueue.main.async {
                    p.play()
                }
            }
        }
    }

    static func dismantleUIView(_ uiView: VLCVideoContainerView, coordinator: Coordinator) {
        coordinator.player?.stop()
        coordinator.player?.drawable = nil
        coordinator.player = nil
        uiView.player = nil
    }

    private func loadMedia(into player: VLCMediaPlayer, url: URL, headers: [String: String]) {
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=3000")
        media.addOption(":clock-jitter=0")
        media.addOption(":clock-synchro=0")

        if let ua = headers["User-Agent"] {
            media.addOption(":http-user-agent=\(ua)")
        } else {
            media.addOption(":http-user-agent=\(AppConfig.defaultUserAgent)")
        }

        if let ref = headers["Referer"] {
            media.addOption(":http-referrer=\(ref)")
        }

        for (k, v) in headers where k != "User-Agent" && k != "Referer" {
            media.addOption(":http-header=\(k): \(v)")
        }

        player.media = media
    }
}

// MARK: - Stream Player Sheet (For Live TV & Direct Streams)

struct StreamPlayerSheet: View {
    let channel: Channel
    @Environment(\.dismiss) private var dismiss

    @State private var vlcPlayer: VLCMediaPlayer? = nil
    @State private var selectedSourceKey: String = ""
    @State private var currentRawUrl: String = ""
    @State private var activeHeaders: [String: String] = [:]
    @State private var isPlaying: Bool = true
    @State private var playerStateText: String = "Connecting…"
    @State private var statusMessage: String? = nil

    var sourceKeys: [String] {
        let keys = Array(channel.sources.keys).sorted()
        return keys.isEmpty ? ["Default"] : keys
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Universal VLC Player View (Plays MKV, M3U8, TS, FLV, MP4)
                ZStack {
                    if let streamURL = URL(string: currentRawUrl), !currentRawUrl.isEmpty {
                        VLCPlayerView(
                            url: streamURL,
                            headers: activeHeaders,
                            player: $vlcPlayer,
                            onStateChanged: { state in
                                handlePlayerState(state)
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                    } else {
                        Rectangle()
                            .fill(Color.black)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .overlay(
                                VStack(spacing: 10) {
                                    ProgressView().tint(.red)
                                    Text(playerStateText).font(.caption).foregroundStyle(.gray)
                                }
                            )
                    }

                    // Live Badge
                    VStack {
                        HStack {
                            HStack(spacing: 4) {
                                Circle().fill(Color.red).frame(width: 6, height: 6)
                                Text("LIVE").font(.system(size: 10, weight: .black)).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Capsule())
                            .padding(10)

                            Spacer()

                            Text(playerStateText)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.75))
                                .clipShape(Capsule())
                                .padding(10)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal)

                // Quick Playback Controls
                HStack(spacing: 24) {
                    Button {
                        if let player = vlcPlayer {
                            if player.isPlaying {
                                player.pause()
                                isPlaying = false
                            } else {
                                player.play()
                                isPlaying = true
                            }
                        }
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(Color.red)
                            .clipShape(Circle())
                    }

                    Button {
                        if let player = vlcPlayer {
                            player.stop()
                            player.play()
                            isPlaying = true
                            playerStateText = "Reloading…"
                        }
                    } label: {
                        Label("Reload Stream", systemImage: "arrow.clockwise")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Button {
                        // Refresh token for this stream
                        Task {
                            await TokenRefreshManager.shared.refreshAllTokens()
                            playSource(rawLine: currentRawUrl)
                            statusMessage = "Live token refreshed!"
                        }
                    } label: {
                        Label("Refresh Token", systemImage: "key.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.green.opacity(0.3))
                            .clipShape(Capsule())
                    }
                }

                // Multi-Server Source Switcher
                if sourceKeys.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(sourceKeys, id: \.self) { key in
                                Button {
                                    selectedSourceKey = key
                                    if let raw = channel.sources[key] {
                                        playSource(rawLine: raw)
                                    }
                                } label: {
                                    Text(key)
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selectedSourceKey == key ? Color.red : Color.secondary.opacity(0.2))
                                        .foregroundStyle(selectedSourceKey == key ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Channel Info & Fallback Buttons
                VStack(alignment: .leading, spacing: 8) {
                    Text(channel.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(channel.group)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = currentRawUrl
                            statusMessage = "Stream URL copied to clipboard"
                        } label: {
                            Label("Copy URL", systemImage: "doc.on.doc")
                                .font(.footnote.weight(.medium))
                        }
                        .buttonStyle(.bordered)

                        if let vlcUrl = URL(string: "vlc-x-callback://x-callback-url/stream?url=\(currentRawUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                            Link(destination: vlcUrl) {
                                Label("External VLC", systemImage: "play.rectangle.fill")
                                    .font(.footnote.weight(.medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(channel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        vlcPlayer?.stop()
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .onAppear {
                let firstKey = sourceKeys.first ?? "Default"
                selectedSourceKey = firstKey
                let raw = channel.sources[firstKey] ?? channel.url
                playSource(rawLine: raw)
            }
            .onDisappear {
                vlcPlayer?.stop()
                vlcPlayer = nil
            }
        }
    }

    private func playSource(rawLine: String) {
        let parsed = M3UParser.parseUrlHeaders(rawLine)
        let resolved = TokenRefreshManager.shared.applyLiveToken(to: parsed.cleanUrl, channel: channel)

        currentRawUrl = resolved.url
        var headers = resolved.headers
        for (k, v) in parsed.headers { headers[k] = v }
        activeHeaders = headers

        playerStateText = "Connecting…"
        isPlaying = true
    }

    private func handlePlayerState(_ state: VLCMediaPlayerState) {
        switch state {
        case .opening:
            playerStateText = "Opening stream…"
        case .buffering:
            playerStateText = "Buffering…"
        case .playing:
            playerStateText = "Playing"
            isPlaying = true
        case .paused:
            playerStateText = "Paused"
            isPlaying = false
        case .stopped:
            playerStateText = "Stopped"
            isPlaying = false
        case .error:
            playerStateText = "Playback Error"
            isPlaying = false
        case .ended:
            playerStateText = "Stream Ended"
            isPlaying = false
        @unknown default:
            break
        }
    }
}
