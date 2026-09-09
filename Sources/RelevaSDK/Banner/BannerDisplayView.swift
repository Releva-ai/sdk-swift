import SwiftUI
import Combine

/// A SwiftUI view modifier that wraps content and displays banners.
///
/// Usage:
/// ```swift
/// HomeView()
///     .bannerDisplay(client: relevaClient, targetSelector: "#home-content") { url in
///         handleDeepLink(url)
///     }
/// ```
public struct BannerDisplayModifier: ViewModifier {
    let client: RelevaClient
    let targetSelector: String
    let onLinkTap: (String) -> Void

    @StateObject private var viewModel = BannerDisplayViewModel()

    public func body(content: Content) -> some View {
        ZStack {
            // Main content with static banners
            VStack(spacing: 0) {
                // afterbegin static banners
                ForEach(viewModel.staticBannersBeforeContent, id: \.token) { banner in
                    bannerContentView(for: banner)
                }

                // Original content
                if !viewModel.hasReplaceBanner {
                    content
                } else {
                    // Replace banner
                    ForEach(viewModel.replaceBanners, id: \.token) { banner in
                        bannerContentView(for: banner)
                    }
                }

                // beforeend / afterend static banners
                ForEach(viewModel.staticBannersAfterContent, id: \.token) { banner in
                    bannerContentView(for: banner)
                }
            }

            // Popup, flyout and bar banners are drawn by `BannerOverlayHost` in a window above
            // the app's navigation and tab bars (see BannerOverlayWindow.swift).
        }
        .onAppear {
            viewModel.usesOverlayWindow = true
            viewModel.start(tracker: client, targetSelector: targetSelector, onLinkTap: onLinkTap)
            BannerOverlayHost.shared.attach(viewModel, onLinkTap: onLinkTap)
        }
        .onDisappear {
            BannerOverlayHost.shared.detach(viewModel)
            viewModel.stop()
        }
    }

    // MARK: - Banner Content View

    @ViewBuilder
    private func bannerContentView(for banner: BannerResponse) -> some View {
        if let design = banner.design {
            DesignRenderer.render(design: design, maxWidth: UIScreen.main.bounds.width) { url in
                viewModel.trackClick(banner)
                onLinkTap(url)
            }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Add banner display capability to this view.
    /// - Parameters:
    ///   - client: The RelevaClient instance
    ///   - targetSelector: CSS selector for static banner targeting (e.g., "#home-content")
    ///   - onLinkTap: Callback when a banner link is tapped. Required — apps must handle link navigation.
    public func bannerDisplay(
        client: RelevaClient,
        targetSelector: String,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        self.modifier(BannerDisplayModifier(
            client: client,
            targetSelector: targetSelector,
            onLinkTap: onLinkTap
        ))
    }
}

// MARK: - Tracking Seam

/// The part of `RelevaClient` that banner display uses.
///
/// `RelevaClient` builds its own `NetworkService` over `URLSession.shared`, so a test that
/// handed one to a view model or presenter would perform real network I/O. This protocol lets
/// a test substitute a spy instead. It is internal: `RelevaClient`'s public surface is unchanged.
@MainActor
protocol BannerTracker: AnyObject {
    func bannerImpression(_ banner: BannerResponse)
    func bannerAction(_ banner: BannerResponse, action: String)
}

extension RelevaClient: BannerTracker {}

// MARK: - ViewModel

@MainActor
class BannerDisplayViewModel: ObservableObject {
    @Published var staticBannersBeforeContent: [BannerResponse] = []
    @Published var staticBannersAfterContent: [BannerResponse] = []
    @Published var replaceBanners: [BannerResponse] = []
    @Published var barBanners: [BannerResponse] = []
    @Published var popupBanner: BannerResponse?
    @Published var flyoutBanner: BannerResponse?

    var hasReplaceBanner: Bool { !replaceBanners.isEmpty }

    /// Set by the SwiftUI modifier: overlay banners of this view model are drawn by
    /// `BannerOverlayHost`. `BannerPresenter` draws its own and leaves this false.
    var usesOverlayWindow = false

    /// Display types that do not need a place in the host's view hierarchy, and so can be
    /// shown by an overlay-only surface such as `BannerPresenter`.
    private static let overlayDisplayTypes: Set<String> = ["popup", "flyout", "bar"]

    private var tracker: BannerTracker?
    private var targetSelector: String = ""
    private var overlayOnly = false
    private var onLinkTap: ((String) -> Void)?
    private var cancellable: AnyCancellable?
    private var displayedBanners = Set<String>()

    /// - Parameter overlayOnly: when `true`, static and replace banners are dropped instead of
    ///   being collected into `staticBannersBeforeContent` and friends. `BannerPresenter` sets
    ///   this because it has nowhere to put a banner that belongs inline in the host's content,
    ///   and counting an impression for a banner that is never drawn would be a false report.
    func start(
        tracker: BannerTracker,
        targetSelector: String,
        overlayOnly: Bool = false,
        onLinkTap: ((String) -> Void)?
    ) {
        self.tracker = tracker
        self.targetSelector = targetSelector
        self.overlayOnly = overlayOnly
        self.onLinkTap = onLinkTap

        cancellable = BannerDisplayController.shared.bannerPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] banner in
                self?.handleBanner(banner)
            }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
        prefetchTasks.values.forEach { $0.cancel() }
        prefetchTasks.removeAll()
        // Same release the cancelled-prefetch path needs above: a queued banner never ran
        // `show(_:)`, so nothing else would ever clear it from `displayedBanners`.
        queuedPopups.forEach { displayedBanners.remove($0.token) }
        queuedFlyouts.forEach { displayedBanners.remove($0.token) }
        queuedPopups.removeAll()
        queuedFlyouts.removeAll()
    }

    /// How long an overlay banner waits for its images before it is shown anyway.
    static let imagePrefetchTimeout: TimeInterval = 1.5
    /// Keyed by a per-task id (`Task` itself is not `Equatable`) so a finished task can prune
    /// itself instead of this accumulating one entry per overlay banner for the view model's life.
    private var prefetchTasks: [UUID: Task<Void, Never>] = [:]

    private func handleBanner(_ banner: BannerResponse) {
        guard shouldDisplay(banner) else { return }
        guard !displayedBanners.contains(banner.token) else { return }
        displayedBanners.insert(banner.token)

        // Overlay banners appear all at once: load the design's images first, bounded by
        // `imagePrefetchTimeout`. Static banners render as they load.
        if Self.overlayDisplayTypes.contains(banner.displayType ?? ""),
           let design = banner.design {
            let urls = BannerImageCache.imageURLs(in: design)
            if !urls.isEmpty {
                let taskId = UUID()
                let task = Task { @MainActor [weak self] in
                    await BannerImageCache.shared.prefetch(urls, timeout: Self.imagePrefetchTimeout)
                    guard let self = self else { return }
                    defer { self.prefetchTasks.removeValue(forKey: taskId) }
                    // `stop()` cancels this task and clears the queues but has no reference to
                    // `banner.token` to release from `displayedBanners` — do it here, or a
                    // banner whose prefetch loses the race with a tab switch could never be
                    // shown again for the life of this view model (`initialize` re-arms and
                    // re-triggers it, but the guard on `displayedBanners` above drops it).
                    guard !Task.isCancelled else {
                        self.displayedBanners.remove(banner.token)
                        return
                    }
                    self.show(banner)
                }
                prefetchTasks[taskId] = task
                return
            }
        }
        show(banner)
    }

    private func show(_ banner: BannerResponse) {
        defer {
            if usesOverlayWindow, Self.overlayDisplayTypes.contains(banner.displayType ?? "") {
                BannerOverlayHost.shared.contentChanged(in: self, onLinkTap: onLinkTap)
            }
        }
        switch banner.displayType {
        case "popup":
            // One popup at a time; a second one waits and is shown, and counted, when the first
            // closes.
            if popupBanner != nil {
                queuedPopups.append(banner)
                return
            }
            popupBanner = banner
        case "flyout":
            if flyoutBanner != nil {
                queuedFlyouts.append(banner)
                return
            }
            flyoutBanner = banner
        case "bar":
            barBanners.append(banner)
        case "static":
            addStaticBanner(banner)
        default:
            addStaticBanner(banner)
        }

        trackImpression(banner)
    }

    /// Popups and flyouts that arrived while another was on screen; each is shown, and its
    /// impression counted, when the current one is dismissed.
    private var queuedPopups: [BannerResponse] = []
    private var queuedFlyouts: [BannerResponse] = []

    private func shouldDisplay(_ banner: BannerResponse) -> Bool {
        // A missing design, or one with no rows or content, is neither shown nor counted.
        guard let design = banner.design, Self.hasRenderableContent(design) else { return false }
        guard banner.displayType != "custom" else { return false }
        if overlayOnly { return Self.overlayDisplayTypes.contains(banner.displayType ?? "") }
        if banner.displayType == "static" && banner.cssSelector != targetSelector { return false }
        return true
    }

    /// `true` when at least one row has a column with content.
    static func hasRenderableContent(_ design: [String: JSONValue]) -> Bool {
        let rows = design["body"]?["rows"]?.arrayValue ?? []
        return rows.contains { row in
            (row["columns"]?.arrayValue ?? []).contains { column in
                !(column["contents"]?.arrayValue ?? []).isEmpty
            }
        }
    }

    private func addStaticBanner(_ banner: BannerResponse) {
        let strategy = banner.displayStrategy ?? "afterbegin"
        switch strategy {
        case "afterbegin":
            staticBannersBeforeContent.append(banner)
        case "beforeend", "afterend":
            staticBannersAfterContent.append(banner)
        case "replace":
            replaceBanners.append(banner)
        default:
            staticBannersAfterContent.append(banner)
        }
    }

    // MARK: - Dismiss

    func dismissPopup(_ banner: BannerResponse, track: Bool = true) {
        popupBanner = nil
        displayedBanners.remove(banner.token)
        if track { trackDismiss(banner) }
        if !queuedPopups.isEmpty { show(queuedPopups.removeFirst()) }
    }

    func dismissFlyout(_ banner: BannerResponse, track: Bool = true) {
        flyoutBanner = nil
        displayedBanners.remove(banner.token)
        if track { trackDismiss(banner) }
        if !queuedFlyouts.isEmpty { show(queuedFlyouts.removeFirst()) }
    }

    func dismissBar(_ banner: BannerResponse) {
        barBanners.removeAll { $0.token == banner.token }
        displayedBanners.remove(banner.token)
        trackDismiss(banner)
    }

    // MARK: - Tracking

    func trackImpression(_ banner: BannerResponse) {
        guard let tracker = tracker else { return }
        tracker.bannerImpression(banner)
    }

    func trackClick(_ banner: BannerResponse) {
        guard let tracker = tracker else { return }
        tracker.bannerAction(banner, action: "bannerClick")
    }

    func trackDismiss(_ banner: BannerResponse) {
        guard let tracker = tracker else { return }
        tracker.bannerAction(banner, action: "bannerClose")
    }
}
