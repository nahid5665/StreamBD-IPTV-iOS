import SwiftUI
import AVKit
import AVFoundation
import VLCKit

// MARK: - AVPlayer Container View (With Native Tap Recognizer)

class AVPlayerContainerView: UIView {
    var playerLayer: AVPlayerLayer? {
        return layer as? AVPlayerLayer
    }
    override static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        onTap?()
    }
}

struct AVPlayerViewRepresentable: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var onTap: (() -> Void)?

    func makeUIView(context: Context) -> AVPlayerContainerView {
        let view = AVPlayerContainerView(frame: .zero)
        view.playerLayer?.player = player
        view.playerLayer?.videoGravity = videoGravity
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: AVPlayerContainerView, context: Context) {
        uiView.playerLayer?.player = player
        uiView.playerLayer?.videoGravity = videoGravity
        uiView.onTap = onTap
    }
}

// MARK: - VLC Video Rendering Surface Container

class VLCVideoContainerView: UIView {
    weak var player: VLCMediaPlayer?
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentMode = .scaleAspectFit
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        contentMode = .scaleAspectFit
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        onTap?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, let player = player {
            player.drawable = self
        }
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
    var onTap: (() -> Void)? = nil

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

        func mediaPlayerStateChanged(_ aNotification: Notification) {
            guard let p = aNotification.object as? VLCMediaPlayer else { return }
            DispatchQueue.main.async {
                self.parent.onStateChanged?(p.state)
            }
        }

        func mediaPlayerTimeChanged(_ aNotification: Notification) {
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
        view.onTap = onTap

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
        uiView.onTap = onTap
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

        var customHeaderStrings: [String] = []
        for (k, v) in headers where k != "User-Agent" && k != "Referer" {
            customHeaderStrings.append("\(k): \(v)")
        }
        if !customHeaderStrings.isEmpty {
            let joined = customHeaderStrings.joined(separator: "\r\n")
            media.addOption(":http-custom-headers=\(joined)")
        }

        player.media = media
    }
}

// MARK: - Universal Fullscreen Player View (Dual-Engine AVPlayer + VLCKit)

struct UniversalFullScreenPlayerView: View {
    let url: URL
    let title: String
    let subtitle: String?
    let headers: [String: String]
    let isLive: Bool
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    // Player instances
    @State private var avPlayer: AVPlayer? = nil
    @State private var vlcPlayer: VLCMediaPlayer? = nil
    @State private var timeObserverToken: Any? = nil

    // State controls
    @State private var isPlaying: Bool = true
    @State private var showControls: Bool = true
    @State private var currentTimeText: String = "00:00"
    @State private var totalTimeText: String = "00:00"
    @State private var progressValue: Double = 0.0
    @State private var isScrubbing: Bool = false
    @State private var aspectRatioIndex: Int = 0
    @State private var hideControlsTimer: Timer? = nil
    @State private var isBuffering: Bool = true

    private var shouldUseVLC: Bool {
        let lower = url.absoluteString.lowercased()
        return lower.contains(".ts") || lower.contains("/mpegts") || lower.contains(".mkv") || lower.hasPrefix("rtmp://")
    }

    private let aspectRatios: [(label: String, gravity: AVLayerVideoGravity, vlcVal: String?)] = [
        ("Fit", .resizeAspect, nil),
        ("Fill", .resizeAspectFill, "FILL"),
        ("16:9", .resize, "16:9"),
        ("4:3", .resize, "4:3")
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video Canvas: AVPlayer (MP4/HLS) or VLC (TS/MKV)
            if !shouldUseVLC {
                if let p = avPlayer {
                    AVPlayerViewRepresentable(
                        player: p,
                        videoGravity: aspectRatios[aspectRatioIndex].gravity,
                        onTap: { toggleControls() }
                    )
                    .ignoresSafeArea()
                }
            } else {
                VLCPlayerView(
                    url: url,
                    headers: headers,
                    player: $vlcPlayer,
                    onStateChanged: { state in
                        isPlaying = (state == .playing)
                        isBuffering = (state == .buffering || state == .opening)
                    },
                    onTimeChanged: { curr, total in
                        guard !isScrubbing else { return }
                        currentTimeText = curr.stringValue
                        totalTimeText = total.stringValue
                        if let p = vlcPlayer {
                            progressValue = Double(p.position)
                        }
                    },
                    onTap: { toggleControls() }
                )
                .ignoresSafeArea()
            }

            // Buffering Spinner
            if isBuffering {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }

            // Permanent Top-Left Frosted Close Button (ALWAYS VISIBLE & ACCESSIBLE)
            VStack {
                HStack {
                    Button {
                        stopAndDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 18)
                    .padding(.top, 12)

                    Spacer()
                }
                Spacer()
            }
            .zIndex(100)

            // Complete Interactive HUD Controls Overlay
            if showControls {
                hudControlsOverlay
                    .transition(.opacity)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.height > 60 {
                        stopAndDismiss()
                    }
                }
        )
        .onAppear {
            setupPlayer()
            resetHideTimer()
        }
        .onDisappear {
            stopPlayback()
        }
        .statusBarHidden(!showControls)
    }

    private var hudControlsOverlay: some View {
        VStack {
            // Top Bar
            HStack(spacing: 14) {
                // Spacing for permanent close button
                Spacer().frame(width: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }

                Spacer()

                // Aspect Ratio Selector
                Button {
                    aspectRatioIndex = (aspectRatioIndex + 1) % aspectRatios.count
                    if let p = vlcPlayer {
                        p.videoAspectRatio = aspectRatios[aspectRatioIndex].vlcVal.flatMap { strdup($0) }
                    }
                    resetHideTimer()
                } label: {
                    Text(aspectRatios[aspectRatioIndex].label)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .background(
                LinearGradient(colors: [Color.black.opacity(0.85), Color.clear], startPoint: .top, endPoint: .bottom)
            )

            Spacer()

            // Center Play / Pause & 10s Skip Buttons
            HStack(spacing: 48) {
                Button {
                    seekBy(seconds: -10)
                    resetHideTimer()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Button {
                    togglePlayPause()
                    resetHideTimer()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                }

                Button {
                    seekBy(seconds: 10)
                    resetHideTimer()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            Spacer()

            // Bottom Timeline & Scrubber Bar
            VStack(spacing: 8) {
                if !isLive {
                    Slider(
                        value: $progressValue,
                        in: 0.0...1.0,
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing {
                                applyScrubSeek(to: progressValue)
                            }
                            resetHideTimer()
                        }
                    )
                    .tint(Color(red: 0.35, green: 0.55, blue: 1.0))

                    HStack {
                        Text(currentTimeText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text(totalTimeText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                } else {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("LIVE BROADCAST")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .background(
                LinearGradient(colors: [Color.clear, Color.black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            )
        }
    }

    // MARK: - Player Lifecycle & Actions

    private func setupPlayer() {
        if !shouldUseVLC {
            // Setup Native AVPlayer for MP4 & HLS
            var assetOptions: [String: Any] = [:]
            if !headers.isEmpty {
                assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = headers
            }
            let asset = AVURLAsset(url: url, options: assetOptions)
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            self.avPlayer = player

            // Periodic time observer for scrubbing bar
            let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                guard !isScrubbing else { return }
                let currentSec = CMTimeGetSeconds(time)
                if let duration = player.currentItem?.duration, duration.isValid, !duration.isIndefinite {
                    let totalSec = CMTimeGetSeconds(duration)
                    if totalSec > 0 {
                        progressValue = currentSec / totalSec
                        totalTimeText = formatTime(seconds: totalSec)
                    }
                }
                currentTimeText = formatTime(seconds: currentSec)
                isBuffering = (player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
                isPlaying = (player.timeControlStatus == .playing)
            }

            player.play()
            isPlaying = true
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            resetHideTimer()
        }
    }

    private func togglePlayPause() {
        if let p = avPlayer {
            if isPlaying {
                p.pause()
                isPlaying = false
            } else {
                p.play()
                isPlaying = true
            }
        } else if let p = vlcPlayer {
            if p.isPlaying {
                p.pause()
                isPlaying = false
            } else {
                p.play()
                isPlaying = true
            }
        }
    }

    private func seekBy(seconds: Double) {
        if let p = avPlayer {
            let target = CMTimeAdd(p.currentTime(), CMTime(seconds: seconds, preferredTimescale: 1))
            p.seek(to: target)
        } else if let p = vlcPlayer {
            if seconds > 0 { p.jumpForward(10) }
            else { p.jumpBackward(10) }
        }
    }

    private func applyScrubSeek(to progress: Double) {
        if let p = avPlayer, let duration = p.currentItem?.duration, duration.isValid {
            let total = CMTimeGetSeconds(duration)
            let target = CMTime(seconds: total * progress, preferredTimescale: 1)
            p.seek(to: target)
        } else if let p = vlcPlayer {
            p.position = Float(progress)
        }
    }

    private func stopPlayback() {
        hideControlsTimer?.invalidate()
        if let p = avPlayer {
            if let token = timeObserverToken {
                p.removeTimeObserver(token)
                timeObserverToken = nil
            }
            p.pause()
            self.avPlayer = nil
        }
        if let p = vlcPlayer {
            p.stop()
            self.vlcPlayer = nil
        }
    }

    private func stopAndDismiss() {
        stopPlayback()
        onClose?()
        dismiss()
    }

    private func resetHideTimer() {
        hideControlsTimer?.invalidate()
        hideControlsTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                showControls = false
            }
        }
    }

    private func formatTime(seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
        let sec = Int(seconds) % 60
        let min = (Int(seconds) / 60) % 60
        let hr = Int(seconds) / 3600
        if hr > 0 {
            return String(format: "%02d:%02d:%02d", hr, min, sec)
        } else {
            return String(format: "%02d:%02d", min, sec)
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
    @State private var playerStateText: String = "Connecting…"
    @State private var isPlaying: Bool = false
    @State private var isFullScreen: Bool = false
    @State private var statusMessage: String? = nil

    private var sourceKeys: [String] {
        Array(channel.sources.keys).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Video Surface
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
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        Rectangle()
                            .fill(Color.black.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    // Loading / Status Banner
                    if !isPlaying {
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text(playerStateText)
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    // Fullscreen Button
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                isFullScreen = true
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                            .padding(10)
                        }
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .padding(.horizontal)

                // Channel Info & Controls
                HStack(spacing: 12) {
                    Button {
                        if let p = vlcPlayer {
                            if p.isPlaying { p.pause() } else { p.play() }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            Text(isPlaying ? "Pause" : "Play")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                    }

                    Spacer()

                    Button {
                        isFullScreen = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "viewfinder")
                            Text("Full Screen")
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.35, green: 0.55, blue: 1.0), Color(red: 0.55, green: 0.25, blue: 0.95)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)

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
                        isLive: true,
                        onClose: {
                            isFullScreen = false
                        }
                    )
                }
            }
        }
    }

    private func playSource(rawLine: String) {
        let parsed = M3UParser.parseUrlHeaders(rawLine)
        playerStateText = "Connecting…"

        Task {
            let resolved = await TokenRefreshManager.shared.applyLiveToken(to: parsed.cleanUrl, channel: channel)
            await MainActor.run {
                currentRawUrl = resolved.url
                var headers = resolved.headers
                for (k, v) in parsed.headers { headers[k] = v }
                activeHeaders = headers
                isPlaying = true
            }
        }
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
        case .esAdded:
            break
        @unknown default:
            break
        }
    }
}
