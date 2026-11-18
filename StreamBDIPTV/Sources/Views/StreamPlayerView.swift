import SwiftUI
import AVKit

struct AVPlayerContainerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

struct StreamPlayerSheet: View {
    let channel: Channel
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer = AVPlayer()
    @State private var selectedSourceKey: String = ""
    @State private var currentRawUrl: String = ""
    @State private var statusMessage: String? = nil

    var sourceKeys: [String] {
        let keys = Array(channel.sources.keys).sorted()
        return keys.isEmpty ? ["Default"] : keys
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                AVPlayerContainerView(player: player)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

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
                                Label("Open in VLC", systemImage: "play.rectangle.fill")
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
                        player.pause()
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
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
        }
    }

    private func playSource(rawLine: String) {
        let parsed = M3UParser.parseUrlHeaders(rawLine)
        currentRawUrl = parsed.cleanUrl

        var headers = channel.httpHeaders
        for (k, v) in parsed.headers { headers[k] = v }
        if let ua = channel.userAgent, headers["User-Agent"] == nil { headers["User-Agent"] = ua }
        if let ref = channel.httpReferer, headers["Referer"] == nil { headers["Referer"] = ref }
        if let ck = channel.cookie, headers["Cookie"] == nil { headers["Cookie"] = ck }
        if let org = channel.origin, headers["Origin"] == nil { headers["Origin"] = org }
        if headers["User-Agent"] == nil { headers["User-Agent"] = AppConfig.defaultUserAgent }

        guard let streamURL = URL(string: parsed.cleanUrl) else {
            statusMessage = "Invalid stream URL"
            return
        }

        // Configure AVURLAsset with custom HTTP headers (User-Agent, Referer, Cookie, Origin)
        let options: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": headers
        ]
        let asset = AVURLAsset(url: streamURL, options: options)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        player.play()
        statusMessage = nil
    }
}
