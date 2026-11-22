import SwiftUI
import AVFoundation
import UIKit
import MobileVLCKit
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
    @State private var vlcSubtitleOptions: [String] = []
    @State private var vlcSelectedSubtitleIndex: Int = 0
    @State private var avSubtitleOptions: [String] = []
    @State private var avSelectedSubtitleIndex: Int = -1 // -1 = Off

    private let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        NavigationStack {
            List {
                audioSection
                subtitleSection
                speedSection
                volumeSection
                brightnessSection
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
                syncVlcVolumeFromPlayer()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var speedSection: some View {
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
    }

    private var volumeSection: some View {
        Section("Volume") {
            if engine == .vlc {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { Double(vlcVolumePercent) },
                        set: { newV in
                            vlcVolumePercent = Int(newV)
                            vlcPlayer?.audio?.volume = Int32(Float(newV) / 100.0 * 256.0)
                        }
                    ), in: 0...100)
                    Text("\(vlcVolumePercent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("AVPlayer follows the system volume — use the volume buttons or Control Center.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var brightnessSection: some View {
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
    }

    @ViewBuilder
    private var audioSection: some View {
        Section("Audio Track / Language") {
            if engine == .vlc {
                if vlcAudioOptions.count > 1 {
                    Picker("Audio Track", selection: $vlcSelectedAudioIndex) {
                        ForEach(Array(vlcAudioOptions.enumerated()), id: \.offset) { idx, name in
                            Text(name).tag(idx)
                        }
                    }
                    .onChange(of: vlcSelectedAudioIndex) { newIndex in
                        vlcPlayer?.currentAudioTrackIndex = Int32(newIndex)
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
    }

    @ViewBuilder
    private var subtitleSection: some View {
        Section("Subtitle Track") {
            if engine == .vlc {
                if vlcSubtitleOptions.count > 1 {
                    Picker("Subtitle", selection: $vlcSelectedSubtitleIndex) {
                        ForEach(Array(vlcSubtitleOptions.enumerated()), id: \.offset) { idx, name in
                            Text(name).tag(idx)
                        }
                    }
                    .onChange(of: vlcSelectedSubtitleIndex) { newIndex in
                        vlcPlayer?.currentVideoSubTitleIndex = Int32(newIndex)
                    }
                    Button("Subtitles Off") {
                        vlcSelectedSubtitleIndex = -1
                        vlcPlayer?.currentVideoSubTitleIndex = -1
                    }
                    .foregroundStyle(.red)
                } else {
                    Text("No embedded subtitle tracks in this stream yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let item = avPlayer?.currentItem {
                if avSubtitleOptions.count > 1 {
                    Picker("Subtitle", selection: $avSelectedSubtitleIndex) {
                        Text("Off").tag(-1)
                        ForEach(Array(avSubtitleOptions.enumerated()), id: \.offset) { idx, name in
                            Text(name).tag(idx)
                        }
                    }
                    .onChange(of: avSelectedSubtitleIndex) { newIndex in
                        selectAVSubtitleTrack(at: newIndex)
                    }
                } else {
                    Text("No embedded subtitle tracks in this stream yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                showSubtitleImporter = true
            } label: {
                Label("Load Subtitle File (.srt / .vtt)", systemImage: "doc.text.badge.plus")
            }
        }
    }

    // MARK: - Actions

    private func applySpeed(_ s: Float) {
        if let ap = avPlayer {
            ap.defaultRate = s
            if ap.timeControlStatus == .playing {
                ap.rate = s
            }
        }
        vlcPlayer?.rate = s
    }

    private func syncVlcVolumeFromPlayer() {
        guard engine == .vlc, let p = vlcPlayer else { return }
        let raw = p.audio?.volume ?? -1
        if raw >= 0 && raw <= 512 {
            vlcVolumePercent = Int(Float(raw) / 256.0 * 100.0)
        }
    }

    private func refreshAudioTracks() {
        if engine == .vlc, let p = vlcPlayer {
            // This VLCKit build exposes the legacy audio API: audioTrackNames is
            // [Any] and the current index lives on currentAudioTrackIndex.
            let names = (p.audioTrackNames ?? []).map { "\($0)" }
            vlcAudioOptions = names
            let idx = Int(p.currentAudioTrackIndex)
            if idx >= 0 && idx < names.count {
                vlcSelectedAudioIndex = idx
            }
            // Embedded subtitle tracks (same legacy shape as the audio API)
            let subNames = (p.videoSubTitlesNames ?? []).map { "\($0)" }
            vlcSubtitleOptions = subNames
            let subIdx = Int(p.currentVideoSubTitleIndex)
            if subIdx >= 0 && subIdx < subNames.count {
                vlcSelectedSubtitleIndex = subIdx
            }
        } else if let item = avPlayer?.currentItem {
            if let group = try? item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
                let options = group.options
                avAudioOptions = options.map { $0.displayName }
                let current = item.selectedMediaOption(in: group)
                if let current, let idx = options.firstIndex(of: current) {
                    avSelectedAudioIndex = idx
                }
            }
            if let group = try? item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                let options = group.options
                avSubtitleOptions = options.map { $0.displayName }
                let current = item.selectedMediaOption(in: group)
                avSelectedSubtitleIndex = current.flatMap { options.firstIndex(of: $0) } ?? -1
            }
        }
    }

    private func selectAVAudioTrack(at index: Int) {
        guard let item = avPlayer?.currentItem,
              let group = try? item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              index < group.options.count else { return }
        item.select(group.options[index], in: group)
    }

    private func selectAVSubtitleTrack(at index: Int) {
        guard let item = avPlayer?.currentItem,
              let group = try? item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        if index < 0 {
            item.select(nil, in: group) // Off
        } else if index < group.options.count {
            item.select(group.options[index], in: group)
        }
    }
}
