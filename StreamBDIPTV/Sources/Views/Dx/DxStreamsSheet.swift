import SwiftUI

// MARK: - dx.bi StreamsSheet (ported from dxbi-stremio ios/Dxbi/UI/StreamsSheet.swift)
// The streams for one film or episode: the pick at the top (the stream chosen last time, else the
// best that's ready), then every stream with its quality, source and provider, to filter and sort.

struct DxStreamsSheet: View {
    var heading: String
    var subheading: String?
    var items: [StreamSource]
    var isResolving: Bool
    var lastPick: DxLastPick?
    var onPlay: (StreamSource) -> Void

    private enum Sort: String, CaseIterable {
        case best = "Best Quality", provider = "Addon Order"
    }

    @State private var sort = Sort.best
    @State private var quality: String? = nil
    @State private var provider: String? = nil

    private static func res(_ s: StreamSource) -> Int {
        let q = s.quality ?? ""
        if q.contains("2160") || q.lowercased().contains("4k") { return 2160 }
        if q.contains("1440") { return 1440 }
        if q.contains("1080") { return 1080 }
        if q.contains("720") { return 720 }
        if q.contains("480") { return 480 }
        return q.lowercased().contains("4k") ? 2160 : 480
    }

    private var shown: [StreamSource] {
        let kept = items.filter { (quality == nil || $0.quality == quality) && (provider == nil || $0.provider == provider) }
        switch sort {
        case .best:
            return kept.sorted { Self.res($0) > Self.res($1) }
        case .provider:
            return kept
        }
    }

    private var best: StreamSource? {
        if let lastPick {
            return lastPick.asStreamSource
        }
        return shown.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let best { pick(best) }
                    if !items.isEmpty { filters }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { _, s in row(s) }
                    status
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /** The white card: play the stream chosen last time, else the best one ready */
    private func pick(_ best: StreamSource) -> some View {
        Button { onPlay(best) } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lastPick != nil ? "Play · Same as Last Time" : "Play the Best Stream").font(.headline)
                    Text([best.quality, best.provider].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote).opacity(0.7).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .foregroundStyle(.black)
            .background(.white, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private var filters: some View {
        let qualities = Array(Set(items.compactMap(\.quality))).sorted { a, b in
            Self.res(StreamSource(url: "x", quality: a)) > Self.res(StreamSource(url: "x", quality: b))
        }
        let providers = Array(Set(items.compactMap(\.provider).filter { !$0.isEmpty })).sorted()
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Sort", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                } label: { chip(sort.rawValue) }
                if qualities.count > 1 {
                    Menu {
                        Picker("Quality", selection: $quality) {
                            Text("Any Quality").tag(String?.none)
                            ForEach(qualities, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    } label: { chip(quality ?? "Any Quality") }
                }
                if providers.count > 1 {
                    Menu {
                        Picker("Source", selection: $provider) {
                            Text("Any Source").tag(String?.none)
                            ForEach(providers, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    } label: { chip(provider ?? "Any Source") }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ text: String, on: Bool = false, menu: Bool = true) -> some View {
        HStack(spacing: 4) {
            Text(text)
            if menu { Image(systemName: "chevron.down").font(.caption2.weight(.bold)) }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(on ? .black : .white)
        .background(on ? AnyShapeStyle(.white) : AnyShapeStyle(.clear), in: .capsule)
        .dxGlass(interactive: true, hidden: on, in: .capsule)
    }

    private func row(_ s: StreamSource) -> some View {
        let picked = lastPick != nil && s.url == lastPick?.url
        return Button { onPlay(s) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let q = s.quality, !q.isEmpty { DxBadge(text: q.uppercased(), filled: true) }
                    if let t = s.type, t == "embed" { DxBadge(text: "EMBED", colour: .yellow) }
                    if let p = s.provider, !p.isEmpty { DxBadge(text: p.uppercased()) }
                    Spacer(minLength: 0)
                    if s.preferVLC == true { DxBadge(text: "MKV/TS", colour: Dx.muted) }
                }
                Text(s.url)
                    .font(.caption)
                    .foregroundStyle(Dx.faint)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(s.provider ?? "Source")
                    .font(.headline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Dx.raised.opacity(0.7), in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(picked ? Dx.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onPlay(s) } label: { Label("Play", systemImage: "play.fill") }
            Button { UIPasteboard.general.string = s.url } label: { Label("Copy Stream URL", systemImage: "doc.on.doc") }
        }
    }

    @ViewBuilder
    private var status: some View {
        if items.isEmpty {
            if isResolving {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding streams…").foregroundStyle(Dx.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                DxEmptyState(title: "No Streams", systemImage: "play.slash", description: "Your addons may not have this one yet.")
            }
        }
    }
}
