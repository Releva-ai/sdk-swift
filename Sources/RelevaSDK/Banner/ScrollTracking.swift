import SwiftUI
import UIKit

/// Feeds a screen's scroll position to `RelevaClient.reportScrollPercentage` so banners and
/// stories with a `scrollPercentage` trigger can fire.
///
/// Apply it to the **content** of the `ScrollView`:
/// ```swift
/// ScrollView {
///     content
///         .relevaScrollTracking(client)
/// }
/// ```
/// The percentage is how far the content has been scrolled through its scrollable range: 0 at
/// the top, 100 when the bottom of the content reaches the bottom of the viewport. Reported
/// only when the whole-number value changes.
///
/// Implemented by observing the underlying `UIScrollView`'s offset; a SwiftUI preference read from
/// a `GeometryReader` inside the scroll view does not report on iOS 26.
public extension View {
    /// Report the enclosing `ScrollView`'s progress (0–100) to `client`.
    func relevaScrollTracking(_ client: RelevaClient) -> some View {
        relevaScrollTracking { percentage in client.reportScrollPercentage(percentage) }
    }

    /// Report the enclosing `ScrollView`'s progress (0–100) to `onChange`.
    func relevaScrollTracking(onChange: @escaping (Int) -> Void) -> some View {
        background(RelevaScrollObserver(onChange: onChange).frame(width: 0, height: 0))
    }
}

/// A zero-size view that finds the `UIScrollView` it lives in and watches its offset.
struct RelevaScrollObserver: UIViewRepresentable {
    let onChange: (Int) -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {
        uiView.onChange = onChange
    }

    final class ObserverView: UIView {
        var onChange: ((Int) -> Void)?
        private var observation: NSKeyValueObservation?
        private var lastReported = -1

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attachIfNeeded()
        }

        private func attachIfNeeded() {
            guard observation == nil, window != nil else { return }
            var candidate = superview
            while let view = candidate, !(view is UIScrollView) { candidate = view.superview }
            guard let scrollView = candidate as? UIScrollView else { return }
            observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scrollView, _ in
                self?.report(scrollView)
            }
        }

        private func report(_ scrollView: UIScrollView) {
            let inset = scrollView.adjustedContentInset
            let visible = scrollView.bounds.height - inset.top - inset.bottom
            let scrollable = scrollView.contentSize.height - visible
            guard scrollable > 1 else { return }
            let offset = scrollView.contentOffset.y + inset.top
            let percentage = max(0, min(100, Int((offset / scrollable * 100).rounded())))
            guard percentage != lastReported else { return }
            lastReported = percentage
            onChange?(percentage)
        }
    }
}
