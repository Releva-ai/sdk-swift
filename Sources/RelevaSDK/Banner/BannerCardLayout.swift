import SwiftUI

/// Where a bar's card sits and what it pads, resolved the way sdk-react-native's
/// `BannerDisplayWidget` lays a bar out on iOS.
///
/// The bar is a layer and a card. The layer spans the width of the box it is positioned in, pinned
/// to the edge the vertical anchor names, or spans its height too with the card centred in it. In
/// the overlay window that box starts below the status bar. The card inside is
/// the authored size, or the layer's width and its content's height, and pads by whatever part of
/// the system UI its laid-out frame overlaps, as a `SafeAreaView` does. An offset translates the
/// card after layout, so neither the layer nor that padding moves with it.
struct BarCardLayout: Equatable {
    let horizontal: BannerCardStyle.Anchor
    /// `start`, `center` or `end`, never `stretch`: a bar always belongs to an edge or the middle.
    let vertical: BannerCardStyle.Anchor
    /// `cardWidth` resolved against the container, or `nil` to fill it.
    let cardWidth: CGFloat?
    /// `cardHeight` resolved against the container, or `nil` to hug the content.
    let cardHeight: CGFloat?
    /// The system UI the card's laid-out frame overlaps, which it pads by.
    let insets: EdgeInsets
    let translation: CGSize
    /// How far the close control and its gutter move in when a card that reaches the container's
    /// right edge is translated past it, so the control stays on screen.
    let closeInset: CGFloat
    /// A centred layer spans the height of the box it is positioned in and centres its card in it.
    let spansHeight: Bool

    /// A layer anchored to one side hugs its card; otherwise it spans the container's width.
    var hugsWidth: Bool { horizontal == .start || horizontal == .end }

    /// Where the card sits across the layer: an authored width narrower than a spanning layer
    /// starts at its leading edge unless the card is centred.
    var cardAlignment: HorizontalAlignment {
        switch horizontal {
        case .end: return .trailing
        case .center: return .center
        case .start, .stretch: return .leading
        }
    }

    /// Where a layer that hugs its card sits in the container.
    var layerAlignment: HorizontalAlignment { horizontal == .end ? .trailing : .leading }

    /// - Parameters:
    ///   - container: the window, which percentages resolve against and whose width the layer spans.
    ///   - safeArea: the parts of the box the layer is positioned in that are under system UI.
    ///   - touchesEdge: whether this bar is the one flush with its edge (the first top bar, the
    ///     last bottom bar), and so the one that meets the status bar or the home indicator.
    ///   - canSpanHeight: `false` where the container has no height to span (a presenter slot).
    init(
        style: BannerCardStyle,
        displayPosition: String?,
        container: CGSize,
        safeArea: EdgeInsets,
        touchesEdge: Bool,
        canSpanHeight: Bool = true
    ) {
        let anchors = style.anchors(for: .bar, displayPosition: displayPosition)
        horizontal = anchors.horizontal
        vertical = anchors.vertical
        cardWidth = style.width?.resolved(in: container.width)
        cardHeight = style.height?.resolved(in: container.height)
        spansHeight = canSpanHeight && anchors.vertical == .center

        let width = cardWidth ?? container.width
        let minX: CGFloat
        switch anchors.horizontal {
        case .end: minX = container.width - width
        case .center: minX = (container.width - width) / 2
        case .start, .stretch: minX = 0
        }

        let flush = touchesEdge && anchors.vertical != .center
        insets = EdgeInsets(
            top: flush && anchors.vertical == .start ? safeArea.top : 0,
            leading: max(0, safeArea.leading - minX),
            bottom: flush && anchors.vertical == .end ? safeArea.bottom : 0,
            trailing: max(0, minX + width - (container.width - safeArea.trailing))
        )
        translation = style.offsetTranslation(horizontal: anchors.horizontal, vertical: anchors.vertical, in: container)

        let reachesRightEdge = cardWidth == nil && (anchors.horizontal == .stretch || anchors.horizontal == .end)
        closeInset = reachesRightEdge ? max(0, translation.width) : 0
    }
}

/// Where a flyout's card sits, resolved the way sdk-react-native's `BannerDisplayWidget` places a
/// flyout on iOS.
///
/// The card is 80% of the window wide unless `cardWidth` says otherwise, against the side the
/// horizontal anchor names, and runs the full height of the box it is placed in unless `cardHeight`
/// is authored, in which case it hangs off the vertical anchor. A card with neither size key is
/// full-bleed in the window and insets its content by the system UI it overlaps; a sized card is
/// placed inside the safe area and insets nothing.
struct FlyoutCardLayout: Equatable {
    /// `start`, `center` or `end`: `cardPositionHorizontal`, else `displayPosition`.
    let horizontal: BannerCardStyle.Anchor
    /// The anchor the card hangs off: `stretch` (top to bottom) unless `cardHeight` is authored.
    let vertical: BannerCardStyle.Anchor
    /// Whether `cardWidth` or `cardHeight` is authored.
    let isSized: Bool
    /// The box the card is placed in: the safe area when sized, else the window.
    let box: CGRect
    /// The card's frame in the window, before its offset.
    let frame: CGRect
    /// The system UI an unsized card overlaps, which its content and close control are inset by.
    let insets: EdgeInsets
    let translation: CGSize

    /// The close control sits on the card's inner edge: the leading one for a right-hand card.
    var closeOnLeading: Bool { horizontal == .end }

    /// Which way the card casts its shadow: away from the edge it is docked to.
    var shadowDirection: CGFloat {
        switch horizontal {
        case .start: return 1
        case .end: return -1
        case .center, .stretch: return 0
        }
    }

    init(style: BannerCardStyle, displayPosition: String?, window: CGSize, safeArea: EdgeInsets) {
        let anchors = style.anchors(for: .flyout, displayPosition: displayPosition)
        horizontal = anchors.horizontal
        vertical = style.height == nil ? .stretch : anchors.vertical
        isSized = style.width != nil || style.height != nil

        box = isSized
            ? CGRect(
                x: safeArea.leading,
                y: safeArea.top,
                width: max(window.width - safeArea.leading - safeArea.trailing, 0),
                height: max(window.height - safeArea.top - safeArea.bottom, 0)
            )
            : CGRect(origin: .zero, size: window)

        let width = style.width?.resolved(in: box.width) ?? window.width * 0.8
        let height = style.height?.resolved(in: box.height) ?? box.height
        let minX: CGFloat
        switch anchors.horizontal {
        case .start: minX = box.minX
        case .center, .stretch: minX = box.midX - width / 2
        case .end: minX = box.maxX - width
        }
        let minY: CGFloat
        switch vertical {
        case .end: minY = box.maxY - height
        case .center: minY = box.midY - height / 2
        case .start, .stretch: minY = box.minY
        }
        frame = CGRect(x: minX, y: minY, width: width, height: height)

        insets = isSized
            ? EdgeInsets()
            : EdgeInsets(
                top: max(0, safeArea.top - frame.minY),
                leading: max(0, safeArea.leading - frame.minX),
                bottom: max(0, frame.maxY - (window.height - safeArea.bottom)),
                trailing: max(0, frame.maxX - (window.width - safeArea.trailing))
            )
        // The sign rule reads the resolved anchors, so a right-hand card negates even when its
        // side comes from `displayPosition`; percentages resolve against the window.
        translation = style.offsetTranslation(horizontal: anchors.horizontal, vertical: anchors.vertical, in: window)
    }
}
