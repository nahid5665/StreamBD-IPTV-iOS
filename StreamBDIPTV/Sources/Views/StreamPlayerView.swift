import SwiftUI
import VLCKit

struct VLCPlayerContainerView: UIViewRepresentable {
    let url: URL
    let headers: [String: String]
    @Binding var player: VLCMediaPlayer?

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        let mediaPlayer = VLCMediaPlayer()
        mediaPlayer.drawable = view

        let media = VLCMedia(url: url)

        var vlcOptions: [AnyHashable: Any] = [
            ":network-caching": 3000,
            ":clock-jitter": 0,
            ":clock-synchro": 0
        ]
        if let ua = headers["User-Agent"] {
            vlcOptions[":http-user-agent"] = ua
        }
        if let ref = headers["Referer"] {
            vlcOptions[":http-referrer"] = ref
        }
        for (k, v) in headers {
            vlcOptions[":http-header"] = "\(k): \(v)"
        }
        media.addOptions(vlcOptions)

        mediaPlayer.media = media
        mediaPlayer.play()

        DispatchQueue.main.async {
            self.player = mediaPlayer
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct StreamPlayerSheet: View {
    let channel: Channel
    @Environment(\.dismiss) private var dismiss

    @State private var vlcPlayer: VLCMediaPlayer? = nil
    @State private var selectedSourceKey: String = ""
    @State private var currentRawUrl: String = ""
    @State private var statusMessage: String? = nil
    @State private var isPlaying = true

    var sourceKeys: [String] {
        let keys = Array(channel.sources.keys).sorted()
        return keys.isEmpty ? ["Default"] : keys
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Universal VLC / FFmpeg Player Container (Plays MKV, M3U8, TS, FLV, MP4)
                if let url = URL(string: currentRawUrl), !currentRawUrl.isEmpty {
                    VLCPlayerContainerView(
                        url: url,
                        headers: resolvedHeaders,
                        player: $vlcPlayer
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay(ProgressView("Loading Stream…"))
                        .padding(.horizontal)
                }

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
                            .padding(12)
                            .background(Color.red)
                            .clipShape(Circle())
                    }

                    Button {
                        if let player = vlcPlayer {
                            player.stop()
                            player.play()
                            isPlaying = true
                        }
                    } label: {
                        Label("Reload Stream", systemImage: "arrow.clockwise")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

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

                VStack(alignment: .leading, spacing: 8) {
                    Text(channel.name)
                        .font(.title3.bold())
                    Text(channel.group)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = currentRawUrl
                            statusMessage = "Stream URL copied to clipboard"
                        } label: {
                            Label("Copy Stream URL", systemImage: "doc.on.doc")
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
            .navigationTitle(channel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        vlcPlayer?.stop()
                        dismiss()
                    }
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

    private var resolvedHeaders: [String: String] {
        let parsed = M3UParser.parseUrlHeaders(currentRawUrl)
        var headers = channel.httpHeaders
        for (k, v) in parsed.headers { headers[k] = v }
        if let ua = channel.userAgent, headers["User-Agent"] == nil { headers["User-Agent"] = ua }
        if let ref = channel.httpReferer, headers["Referer"] == nil { headers["Referer"] = ref }
        if let ck = channel.cookie, headers["Cookie"] == nil { headers["Cookie"] = ck }
        if let org = channel.origin, headers["Origin"] == nil { headers["Origin"] = org }
        if headers["User-Agent"] == nil { headers["User-Agent"] = AppConfig.defaultUserAgent }
        return headers
    }

    private func playSource(rawLine: String) {
        let parsed = M3UParser.parseUrlHeaders(rawLine)
        currentRawUrl = parsed.cleanUrl

        guard let streamURL = URL(string: parsed.cleanUrl) else {
            statusMessage = "Invalid stream URL"
            return
        }

        if let player = vlcPlayer {
            let media = VLCMedia(url: streamURL)
            var vlcOptions: [AnyHashable: Any] = [
                ":network-caching": 3000,
                ":clock-jitter": 0,
                ":clock-synchro": 0
            ]
            if let ua = resolvedHeaders["User-Agent"] {
                vlcOptions[":http-user-agent"] = ua
            }
            if let ref = resolvedHeaders["Referer"] {
                vlcOptions[":http-referrer"] = ref
            }
            for (k, v) in resolvedHeaders {
                vlcOptions[":http-header"] = "\(k): \(v)"
            }
            media.addOptions(vlcOptions)
            player.media = media
            player.play()
            isPlaying = true
        }
        statusMessage = nil
    }
}
