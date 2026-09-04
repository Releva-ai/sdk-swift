import SwiftUI
import UIKit

/// In-memory images for banner designs, so a popup or bar appears with its pictures already in
/// place instead of flashing empty and filling in a moment later (device run 24). The view
/// model prefetches a design's images before it shows an overlay banner, with a short timeout
/// so a slow image never holds the banner back for long.
@MainActor
final class BannerImageCache {
    static let shared = BannerImageCache()

    private var images: [URL: UIImage] = [:]
    private var inflight: [URL: Task<UIImage?, Never>] = [:]

    private init() {}

    func cached(_ url: URL) -> UIImage? { images[url] }

    /// The image at `url`, from memory when seen before, otherwise downloaded once (concurrent
    /// callers share the download).
    func load(_ url: URL) async -> UIImage? {
        if let image = images[url] { return image }
        if let task = inflight[url] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return UIImage(data: data)
        }
        inflight[url] = task
        let image = await task.value
        inflight[url] = nil
        if let image = image { images[url] = image }
        return image
    }

    /// Starts loading every URL and returns when all are in or `timeout` has passed, whichever
    /// is first. Loads that miss the timeout keep going so the image still lands as soon as
    /// it can.
    func prefetch(_ urls: [URL], timeout: TimeInterval) async {
        let pending = urls.filter { images[$0] == nil }
        guard !pending.isEmpty else { return }

        let loader = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for url in pending {
                    group.addTask { @MainActor in _ = await self.load(url) }
                }
            }
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loader.value }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000)) }
            await group.next()
            group.cancelAll()
        }
    }

    /// Every http(s) value under a `url` key anywhere in the design: body and row background
    /// images, image blocks, carousel slides.
    static func imageURLs(in design: [String: JSONValue]) -> [URL] {
        var out: [URL] = []
        var seen = Set<String>()
        func walk(_ value: JSONValue, key: String?) {
            if let object = value.objectValue {
                for (k, v) in object { walk(v, key: k) }
            } else if let array = value.arrayValue {
                for v in array { walk(v, key: nil) }
            } else if key == "url", let s = value.stringValue, s.hasPrefix("http"),
                      !seen.contains(s), let url = URL(string: s) {
                seen.insert(s)
                out.append(url)
            }
        }
        for (k, v) in design { walk(v, key: k) }
        return out
    }
}

/// What `CachedRemoteImage` has for its URL right now.
enum CachedImagePhase {
    case empty
    case success(Image)
    case failure
}

/// `AsyncImage` over `BannerImageCache`: renders synchronously when the image was prefetched,
/// otherwise loads it once and re-renders.
struct CachedRemoteImage<Content: View>: View {
    let url: URL
    let content: (CachedImagePhase) -> Content

    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL, @ViewBuilder content: @escaping (CachedImagePhase) -> Content) {
        self.url = url
        self.content = content
        _image = State(initialValue: BannerImageCache.shared.cached(url))
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                guard image == nil, !failed else { return }
                let loaded = await BannerImageCache.shared.load(url)
                if let loaded = loaded { image = loaded } else { failed = true }
            }
    }

    private var phase: CachedImagePhase {
        if let image = image { return .success(Image(uiImage: image)) }
        return failed ? .failure : .empty
    }
}
