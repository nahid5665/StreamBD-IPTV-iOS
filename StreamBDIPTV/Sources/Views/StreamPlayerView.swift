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
    var onTimeChanged: ((VLCTime, VLCTime) -> Void)? = nil

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

        func mediaPlayerTimeChanged(_ aNotification: Notification!) {
            guard let p = aNotification.object as? VLCMediaPlayer else { return }
            DispatchQueue.main.async {
                self.parent.onTimeChanged?(p.time, p.media?.length ?? VLCTime.null())
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
            media.addOption(":http-referer=\(ref)")
        }

        // Custom HTTP Headers (Cookie, Origin, Auth tokens)
        var customHeaderStrings: [String] = []
        for (k, v) in headers where k != "User-Agent" && k != "Referer" {
            customHeaderStrings.append("\(k): \(v)")
            media.addOption(":http-header=\(k): \(v)")
        }
        if !customHeaderStrings.isEmpty {
            let joined = customHeaderStrings.joined(separator: "\r\n")
            media.addOption(":http-custom-headers=\(joined)")
        }

        player.media = media
    }
}

// MARK: - Universal Fullscreen Player View (With Complete HUD Controls & Scrubbing)

struct UniversalFullScreenPlayerView: View {
    let url: URL
    let title: String
    let subtitle: String?
    let headers: [String: String]
    let isLive: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var vlcPlayer: VLCMediaPlayer? = nil
    @State private var isPlaying: Bool = true
    @State private var showControls: Bool = true
    @State private var currentTimeText: String = "00:00"
    @State private var totalTimeText: String = "00:00"
    @State private var progressValue: Double = 0.0
    @State private var isScrubbing: Bool = false
    @State private var aspectRatioIndex: Int = 0
    @State private var hideControlsTimer: Timer? = nil

    private let aspectRatios: [(label: String, val: String?)] = [
        ("Fit", nil),
        ("16:9", "16:9"),
        ("Fill", "FILL"),
        ("4:3", "4:3")
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video Canvas
            VLCPlayerView(
                url: url,
                headers: headers,
                player: $vlcPlayer,
                onStateChanged: { state in
                    isPlaying = (state == .playing)
                },
                onTimeChanged: { curr, total in
                    guard !isScrubbing else { return }
                    currentTimeText = curr.stringValue ?? "00:00"
                    totalTimeText = total.stringValue ?? "00:00"
                    if let p = vlcPlayer {
                        progressValue = Double(p.position)
                    }
                }
            )
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls.toggle()
                }
                if showControls { resetHideTimer() }
            }

            // HUD Overlays
            if showControls {
                hudControlsOverlay
                    .transition(.opacity)
            }
        }
        .onAppear {
            resetHideTimer()
        }
        .onDisappear {
            hideControlsTimer?.invalidate()
            vlcPlayer?.stop()
            vlcPlayer = nil
        }
        .statusBarHidden(!showControls)
    }

    private var hudControlsOverlay: some View {
        VStack {
            // Top Bar
            HStack(spacing: 14) {
                Button {
                    vlcPlayer?.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.85))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()

                // Aspect Ratio Toggle
                Button {
                    aspectRatioIndex = (aspectRatioIndex + 1) % aspectRatios.count
                    let currentRatio = aspectRatios[aspectRatioIndex]
                    if let p = vlcPlayer {
                        if let r = currentRatio.val, r != "FILL" {
                            let cString = (r as NSString).utf8String
                            p.videoAspectRatio = UnsafeMutablePointer(mutating: cString)
                        } else {
                            p.videoAspectRatio = nil
                        }
                    }
                } label: {
                    Text(aspectRatios[aspectRatioIndex].label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }

                // Fullscreen Exit
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Spacer()

            // Center Play/Pause & Skip Controls
            HStack(spacing: 48) {
                // Rewind 10s
                Button {
                    if let p = vlcPlayer {
                        p.jumpBackward(10)
                    }
                    resetHideTimer()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white)
                }

                // Play / Pause
                Button {
                    if let p = vlcPlayer {
                        if p.isPlaying {
                            p.pause()
                            isPlaying = false
                        } else {
                            p.play()
                            isPlaying = true
                        }
                    }
                    resetHideTimer()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(20)
                        .background(Color.white.opacity(0.25))
                        .clipShape(Circle())
                }

                // Forward 10s
                Button {
                    if let p = vlcPlayer {
                        p.jumpForward(10)
                    }
                    resetHideTimer()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            Spacer()

            // Bottom Bar (Scrubbing / Progress)
            VStack(spacing: 6) {
                if !isLive {
                    // Timeline Slider
                    HStack(spacing: 12) {
                        Text(currentTimeText)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)

                        Slider(
                            value: $progressValue,
                            in: 0...1,
                            onEditingChanged: { editing in
                                isScrubbing = editing
                                if !editing, let p = vlcPlayer {
                                    p.position = Float(progressValue)
                                }
                                resetHideTimer()
                            }
                        )
                        .tint(Color(red: 0.4, green: 0.6, blue: 1.0))

                        Text(totalTimeText)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                } else {
                    HStack {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("LIVE BROADCAST")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.7), Color.clear, Color.black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func resetHideTimer() {
        hideControlsTimer?.invalidate()
        hideControlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                showControls = false
            }
        }
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
    @State private var isFullScreen: Bool = false

    var sourceKeys: [String] {
        let keys = Array(channel.sources.keys).sorted()
        return keys.isEmpty ? ["Default"] : keys
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Universal VLC Player View
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
                                    ProgressView().tint(Color(red: 0.4, green: 0.6, blue: 1.0))
                                    Text(playerStateText).font(.caption).foregroundStyle(.gray)
                                }
                            )
                    }

                    // Live Badge & Fullscreen Button
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

                            // Fullscreen Button
                            Button {
                                isFullScreen = true
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.75))
                                    .clipShape(Circle())
                            }
                            .padding(10)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal)

                // Quick Playback Controls
                HStack(spacing: 20) {
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
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.35, green: 0.55, blue: 1.0), Color(red: 0.55, green: 0.25, blue: 0.95)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    // Fullscreen Trigger Pill
                    Button {
                        isFullScreen = true
                    } label: {
                        Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.35, green: 0.55, blue: 1.0), Color(red: 0.55, green: 0.25, blue: 0.95)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
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
                                        .background(
                                            selectedSourceKey == key
                                                ? LinearGradient(colors: [Color(red: 0.35, green: 0.55, blue: 1.0), Color(red: 0.55, green: 0.25, blue: 0.95)], startPoint: .leading, endPoint: .trailing)
                                                : LinearGradient(colors: [Color.white.opacity(0.12)], startPoint: .leading, endPoint: .trailing)
                                        )
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Channel Info
                VStack(alignment: .leading, spacing: 6) {
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
            .fullScreenCover(isPresented: $isFullScreen) {
                if let streamURL = URL(string: currentRawUrl) {
                    UniversalFullScreenPlayerView(
                        url: streamURL,
                        title: channel.name,
                        subtitle: channel.group,
                        headers: activeHeaders,
                        isLive: true
                    )
                }
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
