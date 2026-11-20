import SwiftUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers

/// VLC-style playback options panel: speed, volume, brightness,
/// audio track (language) switching, and external subtitle loading.
struct PlaybackOptionsSheet: View {
    let engine: UniversalFullScreenPlayerView.PlayerEngine
    let vlcPlayer: VLCMediaPlayer?
    let avPlayer: AVPlayer?
    @Binding var speed: Float
    @Binding var vlcVolumePercent: Int
    var onPickSubtitle: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showSubtitleImporter: Bool = false
    @State private var vlcAudioOptions: [String] = []
    @State private var vlcSelectedAudioIndex: Int = 0
    @State private var avAudioOptions: [String] = []
    @State private var avSelectedAudioIndex: Int = 0

    private let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        NavigationStack {
            List {
                Section("Playback Speed") {
                    Picker("Speed", selection: $speed) {
                        ForEach(speedOptions, id: \.self) { s in
                            Text("\(String(format: "%.2f", s))×").tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: speed) { newValue in
                        applySpeed(newValue)
                    }
                }

                if engine == .vlc {
                    Section("Volume") {
                        HStack(spacing: 10) {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { Double(vlcVolumePercent) },
                                set: { newV in
                                    vlcVolumePercent = Int(newV)
                                    vlcPlayer?.audio.volume = Int(Float(newV) / 100.0 * 256.0)
                                }
                            ), in: 0...100)
                            Text("\(vlcVolumePercent)%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("Volume") {
                        Text("AVPlayer follows the system volume — use the volume buttons or Control Center.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Brightness") {
                    HStack(spacing: 10) {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.yellow)
                        Slider(value: Binding(
                            get: { Double(UIScreen.main.brightness) },
                            set: { UIScreen.main.brightness = CGFloat($0) }
                        ), in: 0.05...1.0)
                    }
                }

                Section("Audio Track / Language") {
                    if engine == .vlc {
                        if vlcAudioOptions.count > 1 {
                            Picker("Audio Track", selection: $vlcSelectedAudioIndex) {
                                ForEach(Array(vlcAudioOptions.enumerated()), id: \.offset) { idx, name in
                                    Text(name).tag(idx)
                                }
                            }
                            .onChange(of: vlcSelectedAudioIndex) { newIndex in
                                vlcPlayer?.audioTrackIndex = newIndex
                            }
                        } else {
                            Text(vlcAudioOptions.isEmpty ? "No audio track info available yet." : "Only one audio track in this stream.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if avAudioOptions.count > 1 {
                            Picker("Audio Track", selection: $avSelectedAudioIndex) {
                                ForEach(Array(avAudioOptions.enumerated()), id: \.offset) { idx, name in
                                    Text(name).tag(idx)
                                }
                            }
                            .onChange(of: avSelectedAudioIndex) { newIndex in
                                selectAVAudioTrack(at: newIndex)
                            }
                        } else {
                            Text("No additional audio tracks detected in this stream.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Subtitles") {
                    Button {
                        showSubtitleImporter = true
                    } label: {
                        Label("Load Subtitle File (.srt / .vtt)", systemImage: "doc.text.badge.plus")
                    }
                    if engine == .avPlayer {
                        Text("Subtitles use the VLC engine — picking one switches automatically.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Playback Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showSubtitleImporter,
                allowedContentTypes: [.data, .text],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    onPickSubtitle(url)
                    dismiss()
                }
            }
            .onAppear {
                refreshAudioTracks()
                if engine == .vlc, let p = vlcPlayer {
                    let raw = p.audio.volume
                    if raw >= 0 && raw <= 512 {
                        vlcVolumePercent = Int(Float(raw) / 256.0 * 100.0)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func applySpeed(_ s: Float) {
        if let ap = avPlayer {
            ap.defaultRate = s
            if ap.timeControlStatus == .playing {
                ap.rate = s
            }
        }
        vlcPlayer?.rate = s
    }

    private func refreshAudioTracks() {
        if engine == .vlc, let p = vlcPlayer {
            let names = p.audioTrackNames ?? []
            vlcAudioOptions = names
            let idx = p.audioTrackIndex
            if idx >= 0 && idx < names.count {
                vlcSelectedAudioIndex = idx
            }
        } else if let item = avPlayer?.currentItem {
            if let group = try? item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
                let options = group.options
                avAudioOptions = options.map { $0.displayName }
                if let current = item.currentMediaSelection(for: group),
                   let idx = options.firstIndex(of: current) {
                    avSelectedAudioIndex = idx
                }
            }
        }
    }

    private func selectAVAudioTrack(at index: Int) {
        guard let item = avPlayer?.currentItem,
              let group = try? item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              index < group.options.count else { return }
        item.select(option: group.options[index], in: group)
    }
}
