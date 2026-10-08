# Architecture

Mio ShadowFlow separates shadow presentation decisions from both card content and platform drawing. The package contains a portable reference core; it does not ship a complete AppKit renderer, SwiftUI component, pager, or application lifecycle.

## Responsibilities

```text
Host pager / scroll region
├── Content Channel
│   └── strict logical viewport
│       ├── card surface, image, labels, palette, hit testing
│       └── live content and optional transition snapshot
├── Shadow Channel
│   └── independent host with product-specific visual bleed
│       └── stable-ID shadow descriptors
└── Visibility Controller (pure calculations)
    ├── page visibility and pageVisualOpacity
    ├── card/viewport intersection and cardShadowFactor
    └── snapshot/live owner selection
```

The host application owns animation state, view models, card identity, scroll lifecycle, accessibility, hit testing, and renderer teardown. The package accepts values and returns decisions; it does not query data sources or schedule work.

## Content and Shadow separation

The Content Channel owns the card's visible body: background, icon, text, palette, hover controls, and interaction. It remains inside the product's logical viewport and its established clipping rules.

The Shadow Channel owns only the shadow pixels. A host may be inserted at a layer in the hierarchy that can render beyond the content clip while still respecting the outer viewport and page isolation. It must not render card contents or provide hit targets. Enlarging the content viewport to make room for shadows is unsafe because neighboring page bodies may become visible.

The separation is a rendering responsibility boundary, not necessarily two independent view trees. The host app decides the concrete hierarchy and verifies ancestor clipping and z-order on its target OS versions.

## Native shadow path rendering

A Core Animation adapter can represent a card's shadow with an otherwise transparent `CALayer` and an explicit rounded-rectangle `shadowPath`. The layer frame/path describe the card body from which the shadow is produced. `shadowPath` improves shape predictability and can reduce runtime path inference, but it does not escape any ancestor's clipping or masking.

A native renderer should generally:

1. Reuse a layer record for each stable shadow descriptor ID.
2. Set its position/frame, path, shadow token, and opacity from the current descriptor.
3. Disable implicit actions for geometry updates already driven by host animation state.
4. Rebuild a path only when size or corner radius changes.
5. Detach stale layers according to an explicit cache policy and clear all layers when the host is dismantled.

This package defines the `ShadowRenderer` protocol and descriptor data only. It does not make these lifecycle decisions for the application.

## Coordinate mapping and visual bleed

The logical viewport and card frame must be expressed in the same coordinate space. The shadow host is expanded around that viewport by a configurable amount:

```text
hostFrame = logicalViewport.insetBy(dx: -bleed, dy: -bleed)
hostLocalCardFrame = logicalCardFrame.offsetBy(
    dx: -hostFrame.minX,
    dy: -hostFrame.minY
)
```

This paired conversion is important even when the viewport origin is nonzero. Expanding the host without translating card frames shifts all shadows. Hard-coding a local `+bleed` offset in a different layer is also error-prone; use one mapping helper.

Bleed is a render allowance, not a layout measurement. It must not change page width, page offset, content clipping, hit testing, scroll geometry, or transition distance. The host may clip to its own expanded bounds once it provides sufficient space for all supported shadow tokens.

A product should estimate its required bleed from the actual blur/radius, offset, backing scale, and any compositor margin, then validate all four edges. A 29 pt value and its source token values belong to one reference profile, not a package default.

## Visibility model

### Page-level opacity

During a page handoff, calculate the current page's visible extent from its frame intersected with the logical viewport. `VisibilityCalculation.edgeOpacity` applies a smoothstep between caller-supplied zero-opacity and full-opacity extents. Outside a transition it returns `1`; the host remains responsible for deciding which settled page is visible.

Page alpha represents the whole page's presentation. It should be associated with that page's identity and applied to that page's content and shadow descriptors using the same lifecycle input. Do not use the selected index's alpha to control unrelated pages.

### Per-card shadow attenuation

A page can still be mostly visible while an edge card is almost entirely clipped. For a horizontal integration:

```text
intersectionWidth = max(0, min(card.maxX, viewport.maxX)
                           - max(card.minX, viewport.minX))
visibleRatio = clamp(intersectionWidth / card.width, 0, 1)
```

During a transition, the reference factor is:

```text
shadowFactor = pow(visibleRatio, visibilityExponent)
```

A minimum visible extent can suppress sub-pixel intersections. The exponent and epsilon are configuration choices. In `.vertical`, visibility uses the height fraction; in `.both`, it uses visible area fraction. These axis options are mathematical helpers and do not imply real UI validation for those scrolling behaviors.

When transition is inactive, a partially visible eligible card returns a factor of `1`. This deliberately restores the ordinary product shadow instead of leaving transition attenuation in settled scrolling. A fully invisible card still returns `0` because there is no positive intersection.

### Page and card composition

The host may compose the resolved opacity as:

```text
effectiveOpacity = baseOpacity
                 × ownershipMultiplier
                 × pageVisualOpacity
                 × cardShadowFactor
```

Each term should be applied once. If a shared pager already folds page visibility into a descriptor, a renderer must not multiply it again. Resting/hover shadow opacity is the base token; radius, offset, and corner radius are not opacity multipliers.

## Shadow ownership

Snapshot and live content may coexist during a transition. `ShadowOwnership` chooses one source:

```text
transition active AND snapshot pages prepared -> snapshot
otherwise                                      -> live
```

The two multipliers are mutually exclusive. The host must supply the preparation flag with the meaning expected by its lifecycle, and should ensure that prepared content is actually the visible/appropriate source before changing ownership. Preparation alone must not leave a stale snapshot shadow after the snapshot is no longer presented.

The helper is intentionally small. It does not create snapshots, detect visibility, or coordinate view removal. Those remain application concerns.

## Transition and settled lifecycle

For each presentation sample, the host should use current geometry from its existing animation state:

1. Resolve each page's current frame and page identity.
2. Resolve each card's frame in the shared logical coordinate space.
3. Compute page opacity and card visibility from the matching page/viewport pair.
4. Select the shadow owner for that identity.
5. Emit descriptors to the existing renderer.
6. On settlement, restore the stable shadow factor and the correct live owner without a separate timer or completion state machine.

Rapid retargeting should recompute from the current frame. Avoid queues, fixed delays, or geometry offset accumulation. The package math itself does not animate.

## Cache lifecycle and performance

The reference layer does not define a layer-cache policy. A host renderer should decide:

- whether offscreen descriptors are detached or retained;
- how removed identities are evicted;
- how many records can be retained;
- how resizing or backing-scale changes invalidate geometry/path data;
- how teardown removes native sublayers and references.

Per update, the intended calculation cost is rectangle intersection, clamping, a power/smoothstep function, and descriptor composition. Keep data projection, network access, image loading/decoding, palette extraction, and view-model refresh outside the rendering update. Reuse native layers by stable identity and measure both CPU update time and compositor behavior.

## Public API map

- `ShadowFlowConfiguration`: caller-supplied bleed, shadow token, exponent, visibility epsilon, and axis.
- `EdgeFadeConfiguration`: caller-supplied page edge fade interval.
- `VisibilityCalculation`: intersection, visible fraction, card factor, and page opacity math.
- `ShadowOwnership`: mutually exclusive live/snapshot multipliers.
- `ShadowGeometryMapping`: expanded host frame and host-local card frame.
- `ShadowPresentationState`: bounded multiplicative opacity composition.
- `ShadowDescriptor` / `ShadowRenderer`: narrow platform-adapter contract.

## Verification boundaries

The package tests validate pure Swift calculations and state helpers. Horizontal behavior has reference product usage. Vertical and both-axis modes are tested as geometry only. None of these tests validate a host app's `CALayer` hierarchy, clipping, z-order, hover, scroll behavior, performance, or visual acceptance.
