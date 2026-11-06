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

2nd round status: foundation step R2-B3 (m5-7/03-ink 4.13) — the whole contract
7.2.9 surface with simple bodies: objects drawn as outlines / boxes in their L-1
layer, P1 pens still drawn as ballpoint, laser `end()` → null, tape and playback
state only, image cache and formula raster empty (`null`), vector v2 lists
empty. `InkFonts`, `InkTextLayout`, `InkMathRenderer.validate` / `layout` and
`MathPreview` are final.

Status (round 1): INK-α done (03-ink 8 T01–T12: input, pressure, stroke pipeline,
outlines, pen renderers, vector chunk caches, diagnostics). Erasers, lasso,
selection, templates, raster tiles, thumbnails and vector export still run the
simple foundation (B3) bodies (03-ink 4.15) until their INK-β/γ tasks.
