# Mio ShadowFlow

[简体中文](README.zh-CN.md)

**Visibility-aware shadow rendering architecture for SwiftUI and AppKit on macOS.**

Mio ShadowFlow is a small reference core for coordinating card shadows with clipping, scrolling, and page transitions. It provides configurable visibility math, snapshot/live ownership selection, coordinate mapping for an expanded shadow host, and a renderer protocol.

> **Status:** This is a reference implementation, not yet a drop-in UI component. It does not include a complete `CALayer` renderer, a complete SwiftUI visual component, or a pager. Integrators must connect the calculations to their own view geometry and rendering lifecycle.

## Project Introduction

In a complex SwiftUI hierarchy, a card's shadow can be clipped by an ancestor even when the card itself is correctly positioned. A pager can also show a shadow pop during a snapshot-to-live handoff, retain a full-strength shadow on a card that is almost offscreen, or let neighboring page content leak when a content clip is expanded to make room for shadows.

ShadowFlow treats the card body and its shadow as separate rendering concerns. The body remains inside the product's logical content viewport. A renderer can draw only the shadow through an independent host with its own bounds. Pure geometry calculations then keep each shadow synchronized with the current page and card visibility.

The architecture is extracted from a macOS production case study. The package keeps the reusable math and small coordination types; it does not copy the originating application's pager or business UI.

## Why ShadowFlow?

SwiftUI's `.shadow()` is convenient while the view hierarchy has no restrictive clipping. In a `ScrollView`, nested pager, or clipped transition container, the shadow is still part of the view's rendered output and may be cut by a parent. Expanding the whole content viewport can make the shadow visible but may also expose card backgrounds, icons, or text from an adjacent page.

During transitions, a snapshot and its live destination may both exist. If each paints the same shadow, the result becomes darker; if neither owns it for a frame, the shadow disappears. Page-level opacity alone does not solve this when a page remains mostly visible but one edge card is only partly visible.

ShadowFlow gives these concerns separate inputs and keeps the math driven by current geometry rather than a timer or queued animation.

## Architecture

```text
Pager / Scroll Region
├── Content Channel
│   └── Logical viewport with the product's strict content clip
│       ├── card body, image, labels, palette, hit testing
│       └── current page and optional snapshot/live content
├── Shadow Channel
│   └── Independent shadow host with configurable visual bleed
│       └── one shadow descriptor per stable card identity
└── Visibility Controller (pure decisions)
    ├── page visual opacity
    ├── card/viewport intersection and edge attenuation
    └── mutually exclusive snapshot/live ownership
```

- **Content Channel** owns card surfaces, images, labels, interaction, and the logical clip. It never needs to be expanded just to reveal a shadow.
- **Shadow Channel** accepts geometry and resolved shadow parameters. A platform adapter may render a transparent native layer with an explicit shadow path outside the content clip.
- **Visibility Controller** calculates page/card visibility and chooses one shadow owner. It does not own a pager, view model, animation, or data source.

The package exposes the math and renderer contract only. The diagram describes integration responsibilities, not a bundled UI hierarchy.

## Core Algorithm

For a horizontal transition, measure the card body's intersection with the logical viewport:

```text
visibleRatio = clamp(intersectionWidth / cardWidth, 0, 1)
shadowFactor = pow(visibleRatio, exponent)
```

An exponent of `8` was used by one reference product profile. It is configurable and is not a universal default. Fully hidden bodies produce no shadow. A fully visible card has a ratio of `1`, so its transition factor remains `1`. When the transition ends, ShadowFlow restores the stable factor to `1` instead of carrying a transition attenuation into the settled page.

The final opacity can be composed as:

```text
effectiveOpacity = baseOpacity
                 × ownershipMultiplier
                 × pageVisualOpacity
                 × shadowFactor
```

Each term has a distinct role:

- `baseOpacity` comes from the application's resting or hover shadow token.
- `ownershipMultiplier` is `1` for the one active source (snapshot or live), and `0` for the other.
- `pageVisualOpacity` follows the containing page's presentation.
- `shadowFactor` attenuates an individual partially visible card during a transition.

The page term and card term are both needed: a page can still be opaque while a card at its edge is mostly clipped.

## Rendering Architecture

### Independent shadow host and `CALayer.shadowPath`

A native adapter can use a transparent `CALayer` whose `shadowPath` describes the rounded card silhouette. A separate host provides room for the blur outside the logical content viewport. The host should clip only to its own expanded bounds; the card's content remains clipped by the original logical viewport.

`shadowPath` describes the shadow source geometry. It does **not** bypass ancestor clipping. Host insertion point, ancestor masks, and z-order must be inspected in each application.

### Visual bleed

`visualBleed` is a project parameter derived from its shadow radius, offset, platform behavior, and a safety margin. In the reference profile, a 29 pt allowance was selected from the largest resting/hover extent plus margin. Do not copy that value without measuring the target UI.

### Stable layer identity

An adapter should key renderer objects by stable card identity, update positions from current geometry, and rebuild a path only when size or corner radius changes. Detaching a temporarily invisible layer and retaining it for reuse is one possible policy; define cache limits and teardown behavior for the target product.

### Snapshot/live ownership

When both snapshot and live content coexist, one resolver must select the shadow source. The owner decision should drive both shadow multipliers in the same state update. Do not infer current visibility merely from a cached snapshot being prepared.

## Installation

Add the package in Xcode using **File → Add Package Dependencies…** and enter:

```text
https://github.com/hoshinomio0919/MioShadowFlow.git
```

Or add this dependency to a Swift Package manifest:

```swift
.package(url: "https://github.com/hoshinomio0919/MioShadowFlow.git", from: "0.1.0")
```

Then add the `MioShadowFlow` product to the target that uses the reference core. The package targets macOS 13 and later.

This package currently contains a standalone math/reference core. You still need to implement and integrate the actual SwiftUI/AppKit shadow renderer for your view hierarchy.

## Usage

The following function uses only the public package API and compiles as ordinary Swift code in a macOS target that depends on the package:

```swift
import CoreGraphics
import MioShadowFlow

func calculateCardShadow() -> (ratio: Double, opacity: Double, hostFrame: CGRect) {
    let configuration = ShadowFlowConfiguration(
        visualBleed: 29,                 // example profile value; measure your own UI
        baseOpacity: 0.045,
        radius: 14,
        offset: CGSize(width: 0, height: 6),
        cornerRadius: 19,
        visibilityExponent: 8,
        minimumVisibleExtent: 0.5,
        axis: .horizontal
    )

    let viewport = CGRect(x: 0, y: 0, width: 1_004, height: 700)
    let card = CGRect(x: -55, y: 80, width: 185, height: 190)

    let ratio = VisibilityCalculation.visibleFraction(
        cardFrame: card,
        viewport: viewport,
        axis: configuration.axis,
        minimumVisibleExtent: configuration.minimumVisibleExtent
    )
    let shadowFactor = VisibilityCalculation.cardShadowFactor(
        cardFrame: card,
        viewport: viewport,
        configuration: configuration,
        transitionIsActive: true
    )

    let ownership = ShadowOwnership(
        transitionIsActive: true,
        snapshotPagesArePrepared: true
    )
    let pageOpacity = VisibilityCalculation.pageVisualOpacity(
        visibleExtent: 18,
        fade: EdgeFadeConfiguration(zeroOpacityExtent: 2, fullOpacityExtent: 24),
        transitionIsActive: true
    )
    let presentation = ShadowPresentationState(
        baseOpacity: configuration.baseOpacity,
        ownershipMultiplier: ownership.snapshotMultiplier,
        pageVisualOpacity: pageOpacity,
        cardVisibilityFactor: shadowFactor
    )

    let mapping = ShadowGeometryMapping(logicalViewport: viewport, bleed: configuration.visualBleed)
    let hostFrame = mapping.hostFrame
    let hostLocalCardFrame = mapping.hostLocalFrame(for: card)
    let descriptor = ShadowDescriptor(
        id: "card-42",
        hostLocalFrame: hostLocalCardFrame,
        opacity: presentation.effectiveOpacity,
        radius: configuration.radius,
        offset: configuration.offset,
        cornerRadius: configuration.cornerRadius
    )
    _ = descriptor // Pass descriptors to your ShadowRenderer adapter.

    return (ratio, presentation.effectiveOpacity, hostFrame)
}
```

This computes values; it does not draw a shadow. The application must pass current card and viewport frames on each presentation update and implement `ShadowRenderer` using its own AppKit/Core Animation layer tree.

## Performance

- Reuse renderer layers by stable descriptor identity instead of allocating one for every animation sample.
- Update geometry from the current pager/scroll presentation. The math has no animation queue, timer, or fixed delay.
- Disable implicit Core Animation actions when position changes are already driven by SwiftUI presentation values.
- Rebuild a rounded shadow path only when the card size or corner radius changes.
- Keep business-data projection, image loading, decoding, and palette analysis outside per-frame rendering updates.
- Measure renderer CPU cost and compositor frame time separately. A fast layer update does not prove a smooth frame.

## Limitations

- macOS is the primary target; the package requires macOS 13 or later.
- Horizontal visibility attenuation has been exercised in a real macOS product flow.
- Vertical and both-axis modes are covered by pure math tests only. Their behavior inside real ScrollViews, `NSClipView` ancestors, or nested pagers has not been verified.
- A complete native `CALayer` renderer, drop-in SwiftUI component, and pager are not included.
- Different cards, blur radii, offsets, backing scales, clips, and z-order require project-specific tuning and visual review.
- A successful package test run does not establish visual acceptance in a host application.

## Roadmap

These are plans, not completed features:

- **v0.1 Reference Core** — visibility math, ownership helper, geometry mapping, renderer protocol, tests, and documentation.
- **v0.2 Native Renderer** — explore a reusable AppKit/Core Animation adapter with lifecycle and clipping tests.
- **v0.3 SwiftUI Integration** — explore a focused SwiftUI bridge for geometry and descriptor updates.
- **v1.0 Stable API** — consider API stability after renderer integration and multi-project validation.

## License

Mio ShadowFlow is released under the [MIT License](LICENSE).
