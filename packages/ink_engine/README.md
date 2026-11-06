# ink_engine — owned by INK

Ink engine: stroke building and rendering, pens, erasers, lasso geometry, page
templates and thumbnails; (2nd round) page objects, playback emphasis,
memorization tape, the shape assist port, formulas and the text box font.
Plans: [docs/plans/03-ink.md](../../docs/plans/03-ink.md),
[docs/plans/m5-7/03-ink.md](../../docs/plans/m5-7/03-ink.md); contract:
[00-overview 7.2.15 / 7.2.16](../../docs/plans/00-overview.md),
[m5-7/00-overview 7.2.9](../../docs/plans/m5-7/00-overview.md).

Entry points (03-ink 4.0 / 4.14):

- `package:ink_engine/ink_engine.dart` — the public API (`show` list = 03-ink 4.0).
- `package:ink_engine/dev_tools.dart` — `InkDevTools` (web safe, developer menu).
- `package:ink_engine/testing.dart` — test helpers, `test/` only
  (`createTestPageController` (+ `shapeFitter:`), `SyntheticInk` (+ `loopThenHold`,
  `pageContentWith`), `FakeInkClock`, `testInkCoreServices`, `MemoryPressureStore`,
  `SolidBackgroundBuilder`, `FakeInkShapeFitter`, `useInkTestFonts`,
  `debugSetInkFontSource`, `loadKatexFontsForTest`, `InkVectorFixtures`,
  `testPngBytes`). Chrome tests that touch `InkFonts` / `InkTextLayout` call
  `useInkTestFonts()` in `setUpAll` (rootBundle does not answer there).

Calling rules for EDITOR (03-ink 5.3, summary): feed every pointer sample through
`InkSampleAdapter`; one gesture = one session = one `InkEdit` = one
`noteSession.execute(edit.toCommand())`; on a failed commit call
`controller.discardEdit(edit)`; forward every `pageChanges` event to
`controller.updateContent(InkPageContent.fromCore(...))`; never call
`controller.setViewport` (InkPageView does); `viewScale` = logical px per pt.

Name clash (contract v1.4 C14-01): `SelectionGeometry` is also a class in
`package:flutter/rendering.dart`. A file that imports both uses
`import 'package:flutter/rendering.dart' hide SelectionGeometry;` or
`import 'package:ink_engine/ink_engine.dart' as ink;`. `widgets.dart` and
`material_ui` do not export the Flutter class.

ink lab (`example/`, 03-ink T23): the engine on one page with the CORE fake
store for the M0 checks on the iPad — see [example/README.md](example/README.md).

2nd round, objects (m5-7/03-ink 5.6): pass `objects:` to `InkPageContent.fromCore`;
`select` takes stroke and object ids; hide the text box being edited with
`setHiddenObjectIds` and show drafts with `setPreviewObjects` (a preview with a
committed id replaces it; previews win over hidden ids); `InkEdit.toCommand()`
gives `RemoveElements` / `CompositeCommand` when objects are involved. Text boxes
are measured with `InkTextLayout.measure` (EDITOR writes the height into the
frame) and edited with `InkTextLayout.textStyleOf` / `strutStyleOf` and zero
padding. Formulas: `InkMathRenderer.validate` / `layout`, `MathPreview` for the
pad. The NoteSans files are not in FontManifest: `InkFonts.ensureLoaded()` loads
them when a text box is first drawn or measured.

Rules other areas meet (m5-7/03-ink 6.14, 6.15, 6.21 — final since the 2nd
round integration):

- `hitTestObject`: text boxes, formulas, images and unknown objects take a point
  inside their (rotated) frame within the tolerance; a shape takes it on its
  outline (distance ≤ tolerance + width / 2, arrow heads included) and inside
  only when it is filled (nonzero). The inside of an unfilled shape lets the
  tap through.
- Erasers (both modes): a shape goes whole when the swept capsule comes within
  `R + width / 2` of its outline or overlaps a filled inside — the inside of an
  unfilled shape is safe. Text, images and formulas are never erased.
- `InkVectorExport.exportPage`: a dashed stroke is ONE `InkFillShape` whose
  sub-paths are its dash outlines (and dots) — one nonzero fill paints it like
  the screen (K-8). Count dash pieces by sub-paths
  (`InkPathVerb.moveTo`), not by shapes. A shape piece has `objectId` =
  `strokeId` = the object id; tape goes to `cover` only.
- Automatic shape correction (`ShapeAssist.holdToSnap`, T39): the hold is
  `InkTuning.shapeHoldMs` within `InkTuning.shapeHoldRadiusPx` (logical px) of
  the anchor — the last sample that left the radius, timed by sample times; with
  no samples a `dart:async` timer started at the anchor fires it (a test that
  holds still pumps past `shapeHoldMs`). A pen-up sample is not a move.
- `InkDiagnostics.developerValues` (contract v2.5 C25-02): `playbackPaintUs`,
  `annotationPaintUs`, `mathCacheBytes` — a key is there only when measured.

Status (2nd round): T24–T43 done (m5-7/03-ink 8.1–8.2 — P1 pens, objects, layer
4′ playback emphasis, laser, tape, shape assist, text box and formula render,
image cache, thumbnail and vector export v2, benchmarks B12–B20 —
[benchmark/README.md](benchmark/README.md)); T44 (ink lab v2, P-C) is deferred
(C25-04). Integration: every case runs on the merged tree, the hand-off cases on
the fake and the real CORE store (`unit/interop/fake_store_handoff_test.dart`).
Device acceptance (m5-7/03-ink 9.6) is after the integration; a failed item
becomes a `PenProfile` / `InkTuning` tuning task.
