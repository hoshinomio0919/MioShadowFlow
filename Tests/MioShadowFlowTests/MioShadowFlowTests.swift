import CoreGraphics
import XCTest
@testable import MioShadowFlow

final class MioShadowFlowTests: XCTestCase {
    private let viewport = CGRect(x: 0, y: 0, width: 1_004, height: 800)

    private func configuration(axis: ShadowVisibilityAxis = .horizontal) -> ShadowFlowConfiguration {
        ShadowFlowConfiguration(
            visualBleed: 29,
            baseOpacity: 0.045,
            radius: 14,
            offset: CGSize(width: 0, height: 6),
            cornerRadius: 19,
            visibilityExponent: 8,
            minimumVisibleExtent: 0.5,
            axis: axis
        )
    }

    func testFullyInvisibleCardHasNoShadow() {
        let card = CGRect(x: -200, y: 100, width: 185, height: 100)
        XCTAssertEqual(
            VisibilityCalculation.cardShadowFactor(
                cardFrame: card,
                viewport: viewport,
                configuration: configuration(),
                transitionIsActive: true
            ),
            0
        )
    }

    func testFullyVisibleCardKeepsFullShadowDuringTransition() {
        let card = CGRect(x: 100, y: 100, width: 185, height: 100)
        XCTAssertEqual(
            VisibilityCalculation.cardShadowFactor(
                cardFrame: card,
                viewport: viewport,
                configuration: configuration(),
                transitionIsActive: true
            ),
            1
        )
    }

    func testPartiallyVisibleCardUsesConfiguredExponent() {
        let card = CGRect(x: -130, y: 100, width: 185, height: 100)
        let expected = pow(55.0 / 185.0, 8.0)
        XCTAssertEqual(
            VisibilityCalculation.cardShadowFactor(
                cardFrame: card,
                viewport: viewport,
                configuration: configuration(),
                transitionIsActive: true
            ),
            expected,
            accuracy: 1e-12
        )
    }

    func testStablePresentationRestoresFullShadowForPartialCard() {
        let card = CGRect(x: -130, y: 100, width: 185, height: 100)
        XCTAssertEqual(
            VisibilityCalculation.cardShadowFactor(
                cardFrame: card,
                viewport: viewport,
                configuration: configuration(),
                transitionIsActive: false
            ),
            1
        )
    }

    func testSnapshotAndLiveOwnershipAreExclusive() {
        let snapshot = ShadowOwnership(transitionIsActive: true, snapshotPagesArePrepared: true)
        XCTAssertEqual(snapshot.owner, .snapshot)
        XCTAssertEqual(snapshot.snapshotMultiplier, 1)
        XCTAssertEqual(snapshot.liveMultiplier, 0)
        XCTAssertEqual(snapshot.visibleOwnerCount, 1)

        let liveFallback = ShadowOwnership(transitionIsActive: true, snapshotPagesArePrepared: false)
        XCTAssertEqual(liveFallback.owner, .live)
        XCTAssertEqual(liveFallback.visibleOwnerCount, 1)

        let settled = ShadowOwnership(transitionIsActive: false, snapshotPagesArePrepared: true)
        XCTAssertEqual(settled.owner, .live)
        XCTAssertEqual(settled.visibleOwnerCount, 1)
    }

    func testPageOpacityAndEffectiveOpacityComposition() {
        let fade = EdgeFadeConfiguration(zeroOpacityExtent: 2, fullOpacityExtent: 24)
        XCTAssertEqual(
            VisibilityCalculation.pageVisualOpacity(
                visibleExtent: 13,
                fade: fade,
                transitionIsActive: true,
                motionOpacity: 0.5
            ),
            0.25,
            accuracy: 1e-12
        )

        let state = ShadowPresentationState(
            baseOpacity: 0.045,
            ownershipMultiplier: 1,
            pageVisualOpacity: 0.5,
            cardVisibilityFactor: 1
        )
        XCTAssertEqual(state.effectiveOpacity, 0.0225, accuracy: 1e-12)
    }

    func testEdgeFadeUsesSmoothstepAndStablePageIsUnaffected() {
        let fade = EdgeFadeConfiguration(zeroOpacityExtent: 2, fullOpacityExtent: 24)
        XCTAssertEqual(VisibilityCalculation.edgeOpacity(visibleExtent: 2, fade: fade, transitionIsActive: true), 0)
        XCTAssertEqual(VisibilityCalculation.edgeOpacity(visibleExtent: 13, fade: fade, transitionIsActive: true), 0.5, accuracy: 1e-12)
        XCTAssertEqual(VisibilityCalculation.edgeOpacity(visibleExtent: 24, fade: fade, transitionIsActive: true), 1)
        XCTAssertEqual(VisibilityCalculation.edgeOpacity(visibleExtent: 0, fade: fade, transitionIsActive: false), 1)
    }

    func testShadowHostGeometryAndFractionalMapping() {
        let mapping = ShadowGeometryMapping(logicalViewport: viewport, bleed: 29)
        XCTAssertEqual(mapping.hostFrame, CGRect(x: -29, y: -29, width: 1_062, height: 858))

        let cardA = mapping.hostLocalFrame(for: CGRect(x: 0.25, y: 10.5, width: 185, height: 100))
        let cardB = mapping.hostLocalFrame(for: CGRect(x: 0.5, y: 10.75, width: 185, height: 100))
        XCTAssertEqual(cardA.origin, CGPoint(x: 29.25, y: 39.5))
        XCTAssertEqual(cardB.minX - cardA.minX, 0.25, accuracy: 1e-12)
    }

    func testMappingSupportsNonzeroSharedCoordinateOrigin() {
        let viewport = CGRect(x: 100.5, y: 7.25, width: 400, height: 300)
        let mapping = ShadowGeometryMapping(logicalViewport: viewport, bleed: 29)
        let card = mapping.hostLocalFrame(for: CGRect(x: 100.75, y: 7.5, width: 50, height: 50))
        XCTAssertEqual(card.origin, CGPoint(x: 29.25, y: 29.25))
    }

    func testHorizontalVisibility() {
        let card = CGRect(x: -50, y: 0, width: 100, height: 100)
        XCTAssertEqual(
            VisibilityCalculation.cardShadowFactor(
                cardFrame: card,
                viewport: viewport,
                configuration: configuration(axis: .horizontal),
                transitionIsActive: true
            ),
            pow(0.5, 8),
            accuracy: 1e-12
        )
    }

    func testVerticalVisibility() {
        let card = CGRect(x: 0, y: -50, width: 100, height: 100)
        XCTAssertEqual(
            VisibilityCalculation.cardShadowFactor(
                cardFrame: card,
                viewport: viewport,
                configuration: configuration(axis: .vertical),
                transitionIsActive: true
            ),
            pow(0.5, 8),
            accuracy: 1e-12
        )
    }

    func testBothAxisVisibilityUsesVisibleAreaFraction() {
        let card = CGRect(x: -50, y: -50, width: 100, height: 100)
        XCTAssertEqual(
            VisibilityCalculation.cardShadowFactor(
                cardFrame: card,
                viewport: viewport,
                configuration: configuration(axis: .both),
                transitionIsActive: true
            ),
            pow(0.25, 8),
            accuracy: 1e-12
        )
    }

    func testRepeatedRetargetCalculationsUseCurrentGeometry() {
        let samples: [CGFloat] = [-180, -130, -55, -0.25, 0.25, -80, 0]
        var lastFactor = 0.0
        for x in samples {
            let card = CGRect(x: x, y: 100, width: 185, height: 100)
            lastFactor = VisibilityCalculation.cardShadowFactor(
                cardFrame: card,
                viewport: viewport,
                configuration: configuration(),
                transitionIsActive: true
            )
        }
        XCTAssertEqual(lastFactor, 1)
    }
}
