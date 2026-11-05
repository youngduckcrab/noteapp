# ink_engine — owned by INK

Ink engine: stroke building and rendering, pens, erasers, lasso geometry, page
templates and thumbnails. Plan: [docs/plans/03-ink.md](../../docs/plans/03-ink.md);
contract: [00-overview 7.2.15 / 7.2.16](../../docs/plans/00-overview.md).

Entry points (03-ink 4.0 / 4.14):

- `package:ink_engine/ink_engine.dart` — the public API (`show` list = 03-ink 4.0).
- `package:ink_engine/dev_tools.dart` — `InkDevTools` (web safe, developer menu).
- `package:ink_engine/testing.dart` — test helpers, `test/` only
  (`createTestPageController`, `SyntheticInk`, `FakeInkClock`, `testInkCoreServices`,
  `MemoryPressureStore`, `SolidBackgroundBuilder`).

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

Status: INK-α done (03-ink 8 T01–T12: input, pressure, stroke pipeline,
outlines, pen renderers, vector chunk caches, diagnostics). Erasers, lasso,
selection, templates, raster tiles, thumbnails and vector export still run the
simple foundation (B3) bodies (03-ink 4.15) until their INK-β/γ tasks.
