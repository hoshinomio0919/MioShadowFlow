# Integration Guide

This guide is for macOS SwiftUI and AppKit applications with clipped cards, complex `ScrollView` hierarchies, nested pagers, or `LazyVGrid` layouts. Mio ShadowFlow provides geometry math and a renderer contract; the host application still supplies the actual renderer and lifecycle.

## Before integrating

Record the current behavior and identify:

- the logical content viewport and its coordinate space;
- each ancestor that clips or masks content;
- scroll and page motion state, including interrupted/retargeted transitions;
- stable card and page identities;
- current resting/hover shadow tokens;
- any transition snapshots or duplicated live views;
- renderer insertion point and z-order;
- target macOS versions and display backing scales.

Do not begin by changing pager width, page offset, scroll behavior, or motion timing. First prove which layer clips the shadow and which layer draws the card body.

## Choose project parameters

`ShadowFlowConfiguration` deliberately has no universal defaults. Measure and supply:

- `visualBleed`: enough room for the shadow blur, offset, and target compositing margin;
- `baseOpacity`, `radius`, `offset`, and `cornerRadius`: the actual product shadow token;
- `visibilityExponent`: transition edge response;
- `minimumVisibleExtent`: small-intersection threshold in points;
- `axis`: `.horizontal`, `.vertical`, or `.both` for the math to evaluate.

A 29 pt bleed and exponent `8` are values from one reference product profile. They are not safe defaults for other radii, offsets, card sizes, backing scales, scroll axes, or ancestors. Recalculate them for the target UI.

For page edge handoff, separately configure `EdgeFadeConfiguration`. Its interval should be narrow enough to avoid a broad crossfade unless broad fading is an explicit product decision. Page fade and per-card fade solve different problems.

## SwiftUI integration checklist

- [ ] Keep card body, icon, text, palette, controls, and hit targets in the original logical content viewport.
- [ ] Keep the strict content clip that prevents adjacent-page body leakage.
- [ ] Measure card frames in a named/shared coordinate space; viewport and card rectangles must use the same space.
- [ ] Read geometry from current presentation values so animation and rapid retarget use the same frame.
- [ ] Publish one descriptor per stable card ID; do not rebuild the full business grid for each geometry update.
- [ ] Route descriptors to one shadow host whose ancestor chain and z-order have been verified.
- [ ] Do not put a second `.shadow()` on the live/snapshot source when the external renderer owns that visual shadow.
- [ ] Tie page alpha to the page that owns each descriptor; do not use a global selected-index alpha for all pages.
- [ ] Calculate per-card visibility from the card body, not its expanded shadow bounds.
- [ ] Keep input/hit testing on the content channel; the shadow host should not intercept clicks.
- [ ] Tear down descriptors when their page/host is destroyed and define a bounded layer-cache policy.

A `GeometryReader`, anchor preferences, or AppKit bridge can provide geometry, but choose the least expensive mechanism compatible with the host's existing layout. The package does not prescribe a view-tree implementation.

## AppKit / Core Animation integration checklist

- [ ] Place the transparent host where it can render outside the content clip but remains bounded by the intended overall viewport.
- [ ] Verify every ancestor's `masksToBounds`, clipping, mask, and compositing behavior.
- [ ] Use a native `shadowPath` for a known rounded silhouette when appropriate.
- [ ] Map the logical card frame into host-local coordinates through `ShadowGeometryMapping`.
- [ ] Reuse `CALayer` instances by stable descriptor identity.
- [ ] Disable implicit actions for position/opacity updates driven by SwiftUI/AppKit presentation geometry.
- [ ] Rebuild `shadowPath` only when geometry affecting the path changes.
- [ ] Re-evaluate host geometry when window bounds, display scale, scroll viewport, or bleed parameters change.
- [ ] Remove stale layers and clear references during dismantle/teardown.
- [ ] Ensure transparent shadow layers do not change accessibility order or hit testing.

An explicit `shadowPath` controls the source silhouette; it does not bypass clipping. Inspect the complete layer/view hierarchy on the target OS.

## ScrollView and nested pager considerations

A nested pager commonly has three distinct geometries:

1. **Logical content viewport** — controls which card body pixels and interactions are allowed.
2. **Page presentation frame** — follows the existing pager animation and may be fractional during motion.
3. **Shadow host frame** — provides external allowance for blur without changing either of the first two.

Do not substitute one frame for another. Shadow bleed must not enter the page-offset formula or widen the logical viewport. If content has both horizontal strict clipping and vertical allowance, preserve that axis policy in the content channel and create the shadow allowance separately.

For `LazyVGrid`, publish only materialized/visible card geometry where practical. Keep image decode, palette generation, network work, and list projection out of the per-frame shadow update.

## Snapshot/live handoff

- [ ] Identify whether both snapshot and live content exist at the same time.
- [ ] Resolve one owner from the same transition lifecycle used by the host.
- [ ] Apply the owner's multiplier to all corresponding shadow sources from that single decision.
- [ ] Do not equate snapshot preparation with actual page visibility.
- [ ] Confirm no frame has both owners visible and no handoff frame has neither owner unintentionally.
- [ ] Confirm settlement restores the intended live owner and canonical product shadow token.

`ShadowOwnership` helps represent the exclusive choice but does not create snapshots or verify they are on-screen.

## Validation sequence

1. **Math checks:** invisible, fully visible, partial, epsilon boundary, stable restoration, both host origins, fractional coordinates, axis behavior, repeated retarget inputs, and owner exclusivity.
2. **Layer diagnostics:** temporarily disable content or shadow rendering one at a time to identify the source of clipping or bands. Remove diagnostic switches afterward.
3. **Geometry captures:** inspect all four viewport edges at early, middle, late, and settled points, including hover and fractional motion.
4. **Interaction checks:** scroll, click, accessibility, interrupted open/close, rapid page switching, resize, and display-scale changes.
5. **Performance checks:** measure descriptor updates, layer allocations/path rebuilds, CPU cost, and compositor frame time separately.
6. **Human visual review:** compare against the actual host app. Package tests do not declare visual success.

## Common integration mistakes

- Expanding a content clip to make a shadow visible.
- Mapping logical card frames as if the shadow host origin were unchanged.
- Using shadow bounds rather than the actual card body for visibility.
- Allowing the live card and its snapshot clone to both own shadow.
- Applying page alpha to a different page's descriptors.
- Using a fixed delay to synchronize a shadow handoff.
- Recreating layer trees or scanning business data on every frame.
- Treating the reference bleed or exponent as a generic preset.

When an artifact appears, use an A/B that changes exactly one rendering source while keeping motion and geometry unchanged. Correct the diagnosed channel only.
