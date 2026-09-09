import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// `CachedRemoteImage` keeps its `@State` when SwiftUI hands it a new `url` under the same view
/// identity, which is what happens when a story moves to its next slide. Device run 40 showed
/// every slide with the first slide's picture because the loaded image outlived the URL it was
/// loaded for. These tests drive a URL change through a real hosting controller and read the
/// image the view lays out through its ideal size, so they see what the screen sees.
@MainActor
final class CachedRemoteImageTests: XCTestCase {
    private final class URLBox: ObservableObject {
        @Published var url: URL
        init(url: URL) { self.url = url }
    }

    /// Non-resizable `Image`s take their pixel size as their ideal size, so the size the hosting
    /// controller reports tells which image, if any, is on screen.
    private struct Host: View {
        @ObservedObject var box: URLBox
        var body: some View {
            CachedRemoteImage(url: box.url) { phase in
                switch phase {
                case .success(let image): image
                case .empty, .failure: Color.clear.frame(width: 1, height: 1)
                }
            }
        }
    }

    private func solidImage(side: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private func idealSize(of hosting: UIHostingController<Host>) -> CGSize {
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()
        return hosting.sizeThatFits(in: CGSize(width: 1000, height: 1000))
    }

    func testChangingTheURLShowsTheNewImageNotTheOldOne() {
        let first = URL(string: "https://example.test/run40/slide-1.png")!
        let second = URL(string: "https://example.test/run40/slide-2.png")!
        BannerImageCache.shared.store(solidImage(side: 10), for: first)
        BannerImageCache.shared.store(solidImage(side: 20), for: second)

        let box = URLBox(url: first)
        let hosting = UIHostingController(rootView: Host(box: box))
        let window = makeVisibleWindow(rootViewController: hosting)
        defer { window.isHidden = true }

        XCTAssertEqual(idealSize(of: hosting), CGSize(width: 10, height: 10), "first slide's image")

        box.url = second
        drainMainQueue()
        XCTAssertEqual(
            idealSize(of: hosting),
            CGSize(width: 20, height: 20),
            "the view must render the image for its current URL, not the one it loaded first"
        )
    }

    func testChangingToAnUncachedURLShowsNothingUntilItLoads() {
        let first = URL(string: "https://example.test/run40/slide-a.png")!
        let missing = URL(string: "https://example.test/run40/never-downloaded.png")!
        BannerImageCache.shared.store(solidImage(side: 10), for: first)

        let box = URLBox(url: first)
        let hosting = UIHostingController(rootView: Host(box: box))
        let window = makeVisibleWindow(rootViewController: hosting)
        defer { window.isHidden = true }
        XCTAssertEqual(idealSize(of: hosting), CGSize(width: 10, height: 10))

        box.url = missing
        drainMainQueue()
        // The download of `missing` is in flight (or has failed); either way the stale 10×10
        // image is gone and the placeholder is what is laid out.
        XCTAssertEqual(
            idealSize(of: hosting),
            CGSize(width: 1, height: 1),
            "a URL with no image yet shows the placeholder, never the previous image"
        )
    }
}
