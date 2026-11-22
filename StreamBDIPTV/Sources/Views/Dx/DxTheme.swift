import CoreImage
import SwiftUI
import UIKit

// MARK: - dx.bi design system (ported from dxbi-stremio ios/Dxbi/UI/Theme.swift)

enum Dx {
    /** dx.bi's red (Netflix's): progress, what's chosen */
    static let accent = Color(red: 0.898, green: 0.035, blue: 0.078)
    static let background = Color.black
    static let raised = Color(white: 0.12)
    static let muted = Color.white.opacity(0.62)
    static let faint = Color.white.opacity(0.4)
    static let gutter: CGFloat = 20
}

/** DX.BI in Bebas Neue, as on the desktop */
struct DxLogo: View {
    var size: CGFloat = 30
    var body: some View {
        Text("DX.BI")
            .font(.custom("BebasNeue-Regular", size: size))
            .foregroundStyle(Dx.accent)
            .shadow(color: Dx.accent.opacity(0.55), radius: size / 5)
            .accessibilityLabel("dx.bi")
    }
}

// MARK: - Compat (iOS 16 minimum; dx.bi's Compat.swift pattern)

extension View {
    /// Frosted glass behind a view (the iOS 26 Liquid Glass API needs a newer SDK than CI has;
    /// ultraThinMaterial reads the same on black). `hidden` shows none.
    @ViewBuilder
    func dxGlass<S: Shape>(interactive: Bool = false, hidden: Bool = false, in shape: S) -> some View {
        if hidden {
            self
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func dxGlassButton() -> some View {
        self.buttonStyle(.bordered)
    }

    @ViewBuilder
    func dxGlassProminentButton() -> some View {
        self.buttonStyle(.borderedProminent)
    }

    /// Circle button border on iOS 17+, capsule before it.
    @ViewBuilder
    func dxCircleBorder() -> some View {
        if #available(iOS 17.0, *) {
            self.buttonBorderShape(.circle)
        } else {
            self.buttonBorderShape(.capsule)
        }
    }

    /// Zoom transition when a card opens its title page (iOS 18+; plain push before).
    @ViewBuilder
    func dxZoomSource(_ id: String, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func dxZoomDestination(_ id: String, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }

    /// Symbols swap with a replace effect on iOS 17+.
    @ViewBuilder
    func dxSymbolReplace() -> some View {
        if #available(iOS 17.0, *) {
            self.contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }
}

extension View {
    /** The page's black, edge to edge */
    func dxScreenBackground() -> some View { background(Dx.background.ignoresSafeArea()) }
}

// MARK: - Pictures

/** A picture from the web, cached so rows scroll without reloading */
struct DxArt: View {
    var url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Dx.raised)
            }
        }
    }
}

/** A title's name drawn large in place of a logo (TMDB logos are not fetched; text is dx.bi's fallback) */
struct DxTitleLogo: View {
    var name: String
    var maxHeight: CGFloat = 100
    var textSize: CGFloat = 34
    var alignment: TextAlignment = .center

    var body: some View {
        Text(name)
            .font(.system(size: textSize, weight: .heavy))
            .multilineTextAlignment(alignment)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
            .shadow(color: .black.opacity(0.5), radius: 10)
    }
}

// MARK: - Buttons

/** Apple TV's white Play pill */
struct DxPrimaryPill: View {
    var label: String
    var icon: String = "play.fill"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .dxGlassProminentButton()
        .tint(.white)
        .foregroundStyle(.black)
        .buttonBorderShape(.capsule)
    }
}

/** A round glass button (+, ✓, ⋯) */
struct DxGlassCircle: View {
    var icon: String
    var label: String
    var size: CGFloat = 50
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .frame(width: size - 14, height: size - 14)
                .dxSymbolReplace()
        }
        .dxGlassButton()
        .dxCircleBorder()
        .accessibilityLabel(label)
    }
}

/** "Continue Watching ›": a row's title, which opens all of it */
struct DxSectionHeader: View {
    var title: String
    var action: (() -> Void)?
    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 4) {
                Text(title).font(.title2.bold()).lineLimit(1)
                if action != nil { Image(systemName: "chevron.right").font(.title3.weight(.bold)).foregroundStyle(Dx.muted) }
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .padding(.horizontal, Dx.gutter)
    }
}

/** A small outlined tag (New, 4K, HDR…) */
struct DxBadge: View {
    var text: String
    var filled = false
    var colour: Color = .white
    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .foregroundStyle(filled ? .black : colour)
            .background(filled ? AnyShapeStyle(colour) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(filled ? .clear : colour.opacity(0.7), lineWidth: 1.2))
    }
}

/** A thin progress line */
struct DxProgressLine: View {
    var value: Double
    var colour: Color = .white
    var body: some View {
        GeometryReader { g in
            Capsule().fill(.white.opacity(0.3))
                .overlay(alignment: .leading) { Capsule().fill(colour).frame(width: g.size.width * min(max(value, 0), 1)) }
        }
        .frame(height: 4)
    }
}

/** The signed-in person: their initial on a gradient disc */
struct DxAvatar: View {
    var email: String?
    var size: CGFloat = 30
    var body: some View {
        Text(String((email ?? "N").prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .semibold))
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(red: 0.35, green: 0.6, blue: 0.75), Color(red: 0.2, green: 0.4, blue: 0.55)], startPoint: .top, endPoint: .bottom), in: .circle)
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}

/** iOS 17's ContentUnavailableView with an iOS 16 fallback */
struct DxEmptyState: View {
    var title: String
    var systemImage: String
    var description: String
    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
        } else {
            VStack(spacing: 10) {
                Image(systemName: systemImage).font(.system(size: 40)).foregroundStyle(Dx.muted)
                Text(title).font(.title3.bold())
                Text(description).font(.subheadline).foregroundStyle(Dx.muted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(40)
        }
    }
}

/** iOS 17-gated viewAligned shelf scrolling */
extension View {
    @ViewBuilder
    func dxViewAlignedShelf() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTargetBehavior(.viewAligned)
        } else {
            self
        }
    }
}

// MARK: - Art colour (dx.bi's ArtColour: the poster's own colour behind a title page)

@MainActor
enum DxArtColour {
    private static var known: [URL: Color] = [:]

    static func of(_ url: URL?) async -> Color? {
        guard let url else { return nil }
        if let c = known[url] { return c }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        let colour: Color? = await Task.detached(priority: .utility) {
            guard let image = CIImage(data: data),
                  let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent)]),
                  let output = filter.outputImage else { return nil }
            var pixel = [UInt8](repeating: 0, count: 4)
            CIContext(options: [.workingColorSpace: NSNull()]).render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            // dark enough for white text, a little colour kept
            return Color(hue: h, saturation: min(s, 0.55), brightness: min(max(b * 0.62, 0.16), 0.42))
        }.value
        if let colour { known[url] = colour }
        return colour
    }
}

// MARK: - Small helpers

extension String {
    func dxIfEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

func dxTypeName(_ type: String) -> String {
    switch type {
    case "movie": "Movie"
    case "series", "tv": "TV Show"
    case "live": "Live TV"
    default: type.capitalized
    }
}
