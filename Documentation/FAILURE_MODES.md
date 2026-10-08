# Failure Modes and Mitigations

This document records rendering failure patterns observed while developing a visibility-aware shadow architecture. The examples are intentionally described without private repository paths, user data, screenshots, or product business code. Each recommendation addresses the diagnosed layer rather than hiding an artifact with unrelated layout changes.

## 1. Whole-viewport clipping

**Problem**  Card shadows disappear at the edge of a scroll or pager viewport even though the card body is still visible.

**Root Cause**  The shadow is part of the same rendered view output as the card and is clipped by a restrictive ancestor such as a SwiftUI clip, scroll viewport, or AppKit clip view.

**Incorrect Approach**  Assume `.shadow()` or an explicit `shadowPath` bypasses ancestor clipping. Expanding every ancestor clip without separating content and shadow can expose neighboring page contents.

**Recommended Solution**  Inspect the full ancestor and layer tree. Keep the logical content clip intact and render only shadow pixels through a separately placed shadow host with a bounded visual bleed. Verify the host's z-order and all four edges on the target hierarchy.

## 2. Expanding the content clip

**Problem**  Shadows become visible, but icons, card surfaces, palette fills, text, or neighboring page contents appear beyond their intended viewport.

**Root Cause**  The same expanded viewport is being used for both content and shadow rendering. Extra bounds intended for blur are also available to ordinary page content.

**Incorrect Approach**  Increase the page width, relax the content mask, disable strict clipping, or add a white overlay to cover leaked content.

**Recommended Solution**  Preserve the logical content viewport and its clipping rules. Give only the Shadow Channel a separately measured host region. Keep layout, animation distance, and hit-testing geometry tied to the logical viewport.

## 3. `destinationOut` antialias halo

**Problem**  A thin gray outline or one-device-pixel fringe appears around rounded cards, especially while cards move through fractional positions.

**Root Cause**  A shadow-only layer was built by drawing a rounded shadow source and erasing the card body with a same-boundary `destinationOut` mask. Antialiased boundary pixels retained partial alpha after subtraction.

**Incorrect Approach**  Keep tuning two coincident antialiased edges indefinitely, or disable antialiasing and accept jagged corners.

**Recommended Solution**  Prefer a native shadow path that represents the rounded card contour while the card body remains in a separate content channel. If a mask-based approach is unavoidable, validate its edge math at the target backing scale and fractional positions rather than assuming matching paths cancel perfectly.

## 4. Double shadows during snapshot/live handoff

**Problem**  A card shadow becomes too dark during a transition and returns to its normal strength after settlement.

**Root Cause**  The transition snapshot and live destination both draw the same shadow at the same time. Two partially transparent shadows compound opacity.

**Incorrect Approach**  Let both trees render independently, or attempt to correct the result with an arbitrary global opacity reduction.

**Recommended Solution**  Select one explicit owner per stable card identity. Drive snapshot and live multipliers from the same handoff decision, and verify that exactly one visible shadow source exists during transition and settlement.

## 5. Incorrect shadow ownership

**Problem**  A shadow disappears briefly, appears stale, or belongs to a page that is no longer visible during a handoff.

**Root Cause**  Ownership follows data preparation alone, a selected index, or one view's lifecycle rather than the current presentation. A prepared snapshot may be offscreen or already obsolete.

**Incorrect Approach**  Treat “snapshot exists” as equivalent to “snapshot is the visible owner,” or maintain independent owner state in each page.

**Recommended Solution**  Resolve ownership centrally from the same transition lifecycle that determines the visible page. Associate decisions with stable page/card identity and update both render paths from that single result.

## 6. Incorrect shadow host origin

**Problem**  Right and bottom shadows look complete while left and top shadows are cut, or every shadow shifts after the host is expanded.

**Root Cause**  The host size was enlarged but its origin and the card-to-host coordinate conversion were not updated together. Local coordinates were interpreted as if the viewport started at zero.

**Incorrect Approach**  Change only host width/height, or scatter hand-written positive/negative bleed offsets through the renderer.

**Recommended Solution**  Compute the host frame by insetting the logical viewport by negative bleed, then map every logical card frame through the same helper using the host origin. Test nonzero viewport origins and fractional card coordinates.

## 7. Offscreen shadow leakage

**Problem**  A card's shadow appears at a viewport edge even though the card body is completely outside the visible content region.

**Root Cause**  Eligibility was based on the expanded shadow rectangle or on host intersection rather than the actual card body. A generous bleed host can intersect the viewport even when the card itself does not.

**Incorrect Approach**  Treat “shadow host contains pixels” or “expanded card bounds intersect” as proof that the card is eligible.

**Recommended Solution**  Calculate eligibility from the real card body intersected with the logical content viewport. Use the expanded bounds only as render allowance, never as the content visibility test.

## 8. Page-level alpha alone is insufficient

**Problem**  A narrow shadow band remains at a page edge while the outgoing page itself is still mostly visible.

**Root Cause**  Page alpha describes the page as a whole. At an intermediate point it can remain `1`, while a card at that page's boundary has only a small visible portion. The card shadow remains full strength unless it has its own visibility factor.

**Incorrect Approach**  Apply only page edge opacity to card shadows, or infer card visibility from selected page identity.

**Recommended Solution**  Compose the matching page's visual opacity with a separate per-card factor calculated from the card body's current intersection. Keep the shared shadow owner and edge eligibility associated with that same presentation page.

## 9. Partially visible cards retain full transition shadow

**Problem**  A card body is clipped to a sliver, but its full shadow remains visible and forms a gray edge band.

**Root Cause**  Eligibility used only `intersectionWidth > 0`; any positive intersection therefore received the full base shadow. A page-level alpha may not help if the page is still opaque.

**Incorrect Approach**  Use a binary nonzero-intersection test as the entire transition rule, or fade the card body and assume its separately rendered shadow follows automatically.

**Recommended Solution**  During transitions, calculate the body's visible fraction and apply a configurable attenuation curve such as `pow(visibleRatio, exponent)`. Restore factor `1` for an eligible partially visible card when settled, and keep fully invisible cards at `0`. Validate edge thresholds against real geometry and visual review.

## Diagnostic rule

A gray band is not enough evidence to identify its source. It may be shadow, content, a clip boundary, or compositing. Use controlled A/B diagnostics that disable one rendering channel at a time while preserving geometry and motion. Change only the layer confirmed to produce the artifact.
