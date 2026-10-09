import AppKit
import SwiftUI

/// In-memory image cache so champion/item icons don't flicker when views re-render
/// on every poll (AsyncImage refetches whenever its view is recreated).
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 400  // a game's worth of champion, item, rune and spell icons
        return cache
    }()

    func cached(_ url: URL?) -> NSImage? {
        url.flatMap { cache.object(forKey: $0 as NSURL) }
    }

    func image(for url: URL?) async -> NSImage? {
        guard let url else { return nil }
        if let hit = cached(url) { return hit }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

enum ImageShape {
    case circle
    case rounded(CGFloat)
}

struct RemoteImage: View {
    let url: URL?
    var shape: ImageShape = .rounded(6)
    /// Scale applied inside the clip, e.g. 1.12 to crop Data Dragon's baked-in rim.
    var crop: CGFloat = 1

    @State private var image: NSImage?

    init(url: URL?, shape: ImageShape = .rounded(6), crop: CGFloat = 1) {
        self.url = url
        self.shape = shape
        self.crop = crop
        _image = State(initialValue: ImageCache.shared.cached(url))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(crop)
            } else {
                Rectangle().fill(Palette.tertiaryLabel.opacity(0.25))
            }
        }
        .clipShape(clip)
        .task(id: url) {
            image = ImageCache.shared.cached(url)
            if image == nil, let loaded = await ImageCache.shared.image(for: url) {
                image = loaded
            }
        }
    }

    private var clip: AnyShape {
        switch shape {
        case .circle: AnyShape(Circle())
        case .rounded(let radius): AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}
