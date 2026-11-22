import SwiftUI

// MARK: - dx.bi streams panel (styled like dxbi-stremio's title-page addon panel)
// The white best-pick card, then the addon panel: sort/provider chips, the stream count,
// one clean row per addon (bold provider left, quality/muted info right) and the red
// "Install addons" button at the end.

struct DxStreamsSheet: View {
    var heading: String
    var subheading: String?
    var items: [StreamSource]
    var isResolving: Bool
    var lastPick: DxLastPick?
    var onPlay: (StreamSource) -> Void

    @EnvironmentObject private var mainVM: MainViewModel
    @EnvironmentObject private var vodVM: VODViewModel
    @State private var showAddons = false

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
        return 480
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
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let best { pick(best) }
                    if !items.isEmpty { panelHeader }
                    if !items.isEmpty {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { _, s in row(s) }
                        }
                    }
                    installAddons
                    status
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showAddons) {
            NavigationStack {
                SettingsNetflixView(vodVM: vodVM, liveVM: mainVM)
            }
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
        .padding(.bottom, 16)
    }

    /** dx.bi's panel header: "Addon order" + "Provider" drop-down chips, stream count at the right */
    private var panelHeader: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Sort", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                } label: {
                    chip(sort == .best ? "Addon order" : sort.rawValue)
                }
                if providers.count > 1 {
                    Menu {
                        Picker("Source", selection: $provider) {
                            Text("Any Provider").tag(String?.none)
                            ForEach(providers, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    } label: {
                        chip(provider ?? "Provider")
                    }
                }
                Spacer(minLength: 0)
                Text("\(items.count) stream\(items.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Dx.muted)
            }
            if qualities.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(qualities, id: \.self) { q in
                            Button { quality = (quality == q) ? nil : q } label: {
                                Text(q)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .foregroundStyle(quality == q ? .black : .white)
                                    .background(quality == q ? AnyShapeStyle(.white) : AnyShapeStyle(.clear), in: .capsule)
                                    .dxGlass(interactive: true, hidden: quality == q, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.bottom, 10)
    }

    private var qualities: [String] {
        Array(Set(items.compactMap(\.quality))).sorted { a, b in
            Self.res(StreamSource(url: "x", quality: a)) > Self.res(StreamSource(url: "x", quality: b))
        }
    }

    private var providers: [String] {
        Array(Set(items.compactMap(\.provider).filter { !$0.isEmpty })).sorted()
    }

    /** Sort / provider drop-down chips (dx.bi's "Addon order · Provider" pair) */
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

    /** One clean panel row: bold provider left, quality/muted info right (dx.bi's list) */
    private func row(_ s: StreamSource) -> some View {
        let picked = lastPick != nil && s.url == lastPick?.url
        return Button { onPlay(s) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(s.provider?.isEmpty == false ? s.provider! : "Source")
                        .font(.headline)
                        .foregroundStyle(picked ? Dx.accent : .white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text([s.quality, s.type == "embed" ? "Embed" : "Direct"].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Dx.muted)
                        .lineLimit(1)
                }
                Text(s.url)
                    .font(.caption)
                    .foregroundStyle(Dx.faint)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 13)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 0.7)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onPlay(s) } label: { Label("Play", systemImage: "play.fill") }
            Button { UIPasteboard.general.string = s.url } label: { Label("Copy Stream URL", systemImage: "doc.on.doc") }
        }
    }

    /** dx.bi's red Install addons button */
    private var installAddons: some View {
        Button { showAddons = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text("Install addons")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .foregroundStyle(.white)
        .background(Dx.accent, in: .rect(cornerRadius: 16))
        .buttonStyle(.plain)
        .padding(.top, 22)
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
