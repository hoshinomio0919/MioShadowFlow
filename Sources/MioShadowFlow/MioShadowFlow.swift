import CoreGraphics
import Foundation

/// The axis used to measure how much of a card body intersects a logical viewport.
public enum ShadowVisibilityAxis: String, Equatable {
    case horizontal
    case vertical
    case both
}

/// Parameters supplied by the integrating application. No visual values are universal defaults.
public struct ShadowFlowConfiguration {
    public let visualBleed: CGFloat
    public let baseOpacity: Double
    public let radius: CGFloat
    public let offset: CGSize
    public let cornerRadius: CGFloat
    public let visibilityExponent: Double
    public let minimumVisibleExtent: CGFloat
    public let axis: ShadowVisibilityAxis

    public init(
        visualBleed: CGFloat,
        baseOpacity: Double,
        radius: CGFloat,
        offset: CGSize,
        cornerRadius: CGFloat,
        visibilityExponent: Double,
        minimumVisibleExtent: CGFloat,
        axis: ShadowVisibilityAxis
    ) {
        self.visualBleed = visualBleed
        self.baseOpacity = baseOpacity
        self.radius = radius
        self.offset = offset
        self.cornerRadius = cornerRadius
        self.visibilityExponent = visibilityExponent
        self.minimumVisibleExtent = minimumVisibleExtent
        self.axis = axis
    }
}

/// The interval over which a page's edge presentation fades in during a transition.
public struct EdgeFadeConfiguration {
    public let zeroOpacityExtent: CGFloat
    public let fullOpacityExtent: CGFloat

    public init(zeroOpacityExtent: CGFloat, fullOpacityExtent: CGFloat) {
        self.zeroOpacityExtent = zeroOpacityExtent
        self.fullOpacityExtent = fullOpacityExtent
    }
}

/// Selects one shadow source while snapshot and live content coexist.
public struct ShadowOwnership: Equatable {
    public enum Owner: Equatable {
        case live
        case snapshot
    }

    public let owner: Owner

    public init(transitionIsActive: Bool, snapshotPagesArePrepared: Bool) {
        owner = transitionIsActive && snapshotPagesArePrepared ? .snapshot : .live
    }

    public var liveMultiplier: Double { owner == .live ? 1 : 0 }
    public var snapshotMultiplier: Double { owner == .snapshot ? 1 : 0 }
    public var visibleOwnerCount: Int {
        (liveMultiplier > 0 ? 1 : 0) + (snapshotMultiplier > 0 ? 1 : 0)
    }
}

/// Maps frames from a shared logical coordinate space into an expanded shadow host.
/// Both input rectangles use the same coordinate space; returned card frames are host-local.
public struct ShadowGeometryMapping {
    public let logicalViewport: CGRect
    public let bleed: CGFloat

    public init(logicalViewport: CGRect, bleed: CGFloat) {
        precondition(bleed.isFinite && bleed >= 0, "bleed must be finite and non-negative")
        self.logicalViewport = logicalViewport
        self.bleed = bleed
    }

    public var hostFrame: CGRect {
        logicalViewport.insetBy(dx: -bleed, dy: -bleed)
    }

    public func hostLocalFrame(for logicalFrame: CGRect) -> CGRect {
        let host = hostFrame
        return logicalFrame.offsetBy(dx: -host.minX, dy: -host.minY)
    }
}

/// Resolved opacity inputs for one shadow descriptor.
/// Page lifecycle and animation progress remain owned by the host application.
public struct ShadowPresentationState {
    public let baseOpacity: Double
    public let ownershipMultiplier: Double
    public let pageVisualOpacity: Double
    public let cardVisibilityFactor: Double

    public init(
        baseOpacity: Double,
        ownershipMultiplier: Double,
        pageVisualOpacity: Double,
        cardVisibilityFactor: Double
    ) {
        self.baseOpacity = baseOpacity
        self.ownershipMultiplier = ownershipMultiplier
        self.pageVisualOpacity = pageVisualOpacity
        self.cardVisibilityFactor = cardVisibilityFactor
    }

    public var effectiveOpacity: Double {
        Self.unit(baseOpacity)
            * Self.unit(ownershipMultiplier)
            * Self.unit(pageVisualOpacity)
            * Self.unit(cardVisibilityFactor)
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

/// Pure geometry and visibility functions. These functions do not schedule or animate work.
public enum VisibilityCalculation {
    /// Returns nil for invalid or non-intersecting rectangles.
    public static func intersection(_ lhs: CGRect, _ rhs: CGRect) -> CGRect? {
        guard isFinite(lhs), isFinite(rhs), lhs.width > 0, lhs.height > 0,
              rhs.width > 0, rhs.height > 0 else { return nil }
        let minX = max(lhs.minX, rhs.minX)
        let minY = max(lhs.minY, rhs.minY)
        let maxX = min(lhs.maxX, rhs.maxX)
        let maxY = min(lhs.maxY, rhs.maxY)
        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Returns the visible fraction along the selected axis. `.both` uses area fraction.
    public static func visibleFraction(
        cardFrame: CGRect,
        viewport: CGRect,
        axis: ShadowVisibilityAxis,
        minimumVisibleExtent: CGFloat = 0
    ) -> Double {
        guard let overlap = intersection(cardFrame, viewport),
              cardFrame.width > 0, cardFrame.height > 0,
              minimumVisibleExtent.isFinite, minimumVisibleExtent >= 0 else { return 0 }

        let fraction: CGFloat
        switch axis {
        case .horizontal:
            guard overlap.width > minimumVisibleExtent else { return 0 }
            fraction = overlap.width / cardFrame.width
        case .vertical:
            guard overlap.height > minimumVisibleExtent else { return 0 }
            fraction = overlap.height / cardFrame.height
        case .both:
            guard overlap.width > minimumVisibleExtent,
                  overlap.height > minimumVisibleExtent else { return 0 }
            fraction = (overlap.width / cardFrame.width) * (overlap.height / cardFrame.height)
        }
        return Double(min(1, max(0, fraction)))
    }

    /// Calculates the per-card transition factor. Stable presentation restores a factor of one.
    public static func cardShadowFactor(
        cardFrame: CGRect,
        viewport: CGRect,
        configuration: ShadowFlowConfiguration,
        transitionIsActive: Bool
    ) -> Double {
        let fraction = visibleFraction(
            cardFrame: cardFrame,
            viewport: viewport,
            axis: configuration.axis,
            minimumVisibleExtent: configuration.minimumVisibleExtent
        )
        guard fraction > 0 else { return 0 }
        guard transitionIsActive else { return 1 }
        guard configuration.visibilityExponent.isFinite,
              configuration.visibilityExponent >= 0 else { return 0 }
        return pow(fraction, configuration.visibilityExponent)
    }

    /// Smoothstep edge fade. Supply project-specific extents; no timing is involved.
    public static func edgeOpacity(
        visibleExtent: CGFloat,
        fade: EdgeFadeConfiguration,
        transitionIsActive: Bool
    ) -> Double {
        guard transitionIsActive else { return 1 }
        guard visibleExtent.isFinite,
              fade.zeroOpacityExtent.isFinite,
              fade.fullOpacityExtent.isFinite,
              fade.fullOpacityExtent > fade.zeroOpacityExtent else { return 0 }
        let t = min(1, max(0,
            (visibleExtent - fade.zeroOpacityExtent)
                / (fade.fullOpacityExtent - fade.zeroOpacityExtent)
        ))
        return Double(t * t * (3 - 2 * t))
    }

    /// Combines a host-provided motion opacity with the configured page edge fade.
    public static func pageVisualOpacity(
        visibleExtent: CGFloat,
        fade: EdgeFadeConfiguration,
        transitionIsActive: Bool,
        motionOpacity: Double = 1
    ) -> Double {
        let motion = motionOpacity.isFinite ? min(1, max(0, motionOpacity)) : 0
        return edgeOpacity(
            visibleExtent: visibleExtent,
            fade: fade,
            transitionIsActive: transitionIsActive
        ) * motion
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.minX.isFinite && rect.minY.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.maxX.isFinite && rect.maxY.isFinite
    }
}

/// A renderer input. `hostLocalFrame` is relative to the shadow host, not the logical viewport.
public struct ShadowDescriptor {
    public let id: String
    public let hostLocalFrame: CGRect
    public let opacity: Double
    public let radius: CGFloat
    public let offset: CGSize
    public let cornerRadius: CGFloat

    public init(
        id: String,
        hostLocalFrame: CGRect,
        opacity: Double,
        radius: CGFloat,
        offset: CGSize,
        cornerRadius: CGFloat
    ) {
        self.id = id
        self.hostLocalFrame = hostLocalFrame
        self.opacity = opacity
        self.radius = radius
        self.offset = offset
        self.cornerRadius = cornerRadius
    }
}

/// Minimal adapter contract; this package does not ship a Core Animation renderer yet.
/// Implementations should reuse layers by descriptor ID and rebuild paths only when geometry changes.
public protocol ShadowRenderer: AnyObject {
    func update(shadows: [ShadowDescriptor], hostFrame: CGRect)
    func removeAllShadows()
}
