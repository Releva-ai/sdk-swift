import UIKit

extension UIViewController {
    /// The frontmost controller in this controller's presentation chain.
    ///
    /// `BannerPresenter` and `NpsPresenter` present from here rather than from their host, so
    /// that a banner or survey arriving while the app already has a modal up is shown over it
    /// instead of failing with "already presenting". Controllers mid-dismissal are skipped,
    /// because they cannot present anything.
    var topMostPresentedViewController: UIViewController {
        var candidate = self
        while let presented = candidate.presentedViewController, !presented.isBeingDismissed {
            candidate = presented
        }
        return candidate
    }
}
