# pdf_io

Owned by PDF: PDF import, PDF page backgrounds (rendering) and PDF export. Plan:
[docs/plans/06-pdf.md](../../docs/plans/06-pdf.md), contract:
[00-overview.md 7.2.19](../../docs/plans/00-overview.md) (7.3.3 for the app shell).

Web first (iPad Safari) and web safe throughout: platform code sits behind conditional
imports (`*_browser.dart` / `*_native.dart`). PDFium does the work on both sides —
pdfrx's `pdfium.wasm` in Web Workers on the web, PDFium over FFI on the VM (tests).

## Entry points

| Import | Use |
|---|---|
| `package:pdf_io/pdf_io.dart` | The public API. Its `show` list is the complete list of exported names (06-pdf 4.15, checked by `test/contract/api_surface_test.dart`) |
| `package:pdf_io/testing.dart` | `test/` only (06-pdf 4.14): `PdfFixtureBuilder` / `PdfFixturePage` / `PdfFixtureText` (PDFs built in the test, nothing committed), `FakePdfEngine`, `FakePdfNoteGateway`, `FakePdfFileSource`, `FakePdfOutputSink`, `RecordingComposeBackend`, `BoxInkVectorizer`, `FakeRemoteAssetFetcher` |

## Using it

App start-up (INFRA `PdfModule`, contract 7.3.3). `initializePdfIo` is idempotent and
returns in under 10 ms: it records the config, points pdfrx at its wasm modules,
registers the PDFium license texts (read only when the license list opens) and, by
default, starts the engine warm-up without waiting for it. Engine failures surface
later as `PdfIoException(engineUnavailable)` on the first PDF use.

```dart
await initializePdfIo(config: const PdfIoConfig());

runApp(ProviderScope(
  overrides: [
    ...coreOverrides,      // core.noteStoreProvider — the first PDF page drawn needs it
    ...pdfIoOverrides(),   // the ONLY override of ink.pageBackgroundBuildersProvider
  ],
  child: const NoteApp(),
));
```

`pdfIoOverrides()` = `pdfIoConfigProvider` + `ink.pageBackgroundBuildersProvider` →
`[PdfBackgroundLayerBuilder, ink.TemplateBackgroundLayerBuilder]`. Reading it builds
nothing else: the PDF builder reaches the renderer lazily on its first PDF page.

Library and editor (wired by INFRA, contract 7.2.18 / 7.2.17):

```dart
// LibraryPdfImportAction / LibraryPdfExportAction shapes.
libraryPdfImportActionProvider.overrideWithValue(importPdfAsNewNote);
libraryPdfExportActionProvider.overrideWithValue(exportNotesAsPdf);

final noteId = await importPdfAsNewNote(context, folderId: folderId); // null = no note
await exportNotesAsPdf(context, noteIds); // one PDF per note, then share all / download

// Editor '더보기' menu (pdf.export, pdf.share, pdf.print, pdf.search) and the
// '페이지 추가' sources (pdf.insert).
final invocation = PdfMenuInvocation(
  noteId: noteId,
  currentPageId: currentPageId,
  selectedPageIds: selectedPageIds,
  onNavigate: menuContext.navigateToPage, // (pageId, focusRectPt)
);
for (final action in pdfEditorMoreMenuActions()) {
  if (action.isEnabled?.call(invocation) ?? true) {
    // shown as action.label / action.icon; on tap:
    await action.run(context, invocation);
  }
}
```

The flows (`runPdfImportFlow`, `runPdfExportFlow`, `showPdfSearchPanel`) need an
ancestor `ProviderScope`, show their own errors and never throw for user-level
failures. Other callers reach the services through providers
(`pdfImportServiceProvider`, `pdfExportServiceProvider`, `pdfTextServiceProvider`, …,
06-pdf 4.12). The developer overlay reads `pdfRenderStatsProvider`
(`ValueListenable<PdfRenderStats>`: cache bytes by kind, queue, render times,
`overBudgetBytes`).

`PdfIoConfig` (06-pdf 4.1): import limits (300 MB hard limit, 100 MB warning, 2,000
pages), render budget (by default web 32 / 64 / 16 MiB = 112 MiB, native
64 / 160 / 32 MiB), cover thumbnail on / off, the user-password policy (store a
decrypted copy, or refuse), the warm-up switch and the two web asset URLs below.

## Web assets

| Asset | Served at (default) | Declared by | Config |
|---|---|---|---|
| `pdfium.wasm`, `pdfium_worker.js`, `pdfium_client.js` | `assets/packages/pdfrx/assets/` | pdfrx 2.11.0 | `PdfIoConfig.pdfiumWasmModulesUrl` (null = the pdfrx default, resolved against `document.baseURI`) |
| `web/pdf_io_compose_ext.js` — the compose commands added to a pdfrx worker running as the separate compose Worker (06-pdf 6.11.6) | `assets/packages/pdf_io/web/pdf_io_compose_ext.js` | this package, web only (`platforms: [web]`) | `PdfIoConfig.composeExtensionUrl` |
| `licenses/*` — PDFium notices | `assets/packages/pdf_io/licenses/` | this package, all platforms | — |

- pdfrx is pinned to exactly 2.11.0 (contract 7.5): the compose extension relies on
  the internals of its worker script (`functions`, `encodePdf`, `Pdfium`,
  `StringUtils`). An incompatible worker makes export fail with `engineUnavailable`
  ('PDF 내보내기 엔진 버전이 맞지 않아요'). Upgrading pdfrx means re-running the compose
  probes (T13 / T14) and updating the sha256 in `tool/prepare_web_test.dart`.
- The app's web build must keep these files reachable under `assets/packages/…`
  (service worker and caching rules included). Nothing is fetched before the first
  PDF is opened or exported, except by the warm-up.

## Tests

From `packages/pdf_io`, or `dart run tool/ws.dart test --package pdf_io` from the
workspace root. Tags are declared in `dart_test.yaml`.

| Command | What runs |
|---|---|
| `flutter test` | VM: `contract/`, `unit/`, `widget/`, `goldens/` (`golden`), `pdfium/` (`pdfium`, real PDFium). `test/web/` is excluded by `@TestOn('browser')`; `integration` and `perf` are skipped |
| `dart run tool/prepare_web_test.dart && flutter test --platform chrome test/web` | Chrome: pdfrx wasm rendering and text, the compose Worker, output sink, file source and the pure logic shared with the VM. The preparation copies the pdfrx wasm files and the compose extension into `test/web/pdfium/` (git-ignored; from the pub cache, no network) and fails when `pdfium.wasm` is not the build the extension was checked against. `dart run tool/ws.dart test --platform chrome --package pdf_io` runs the preparation first |
| `flutter test --run-skipped -t perf test/perf` | Performance (wall clock, run by hand): 500-page open + info ≤ 2 s, 500 pages × 200 strokes composed on the native backend ≤ 30 s, a 500-page scroll simulation within the 112 MiB web budget |
| `flutter test --platform chrome --run-skipped -t perf test/web/perf_compose_500_test.dart` | Performance in Chrome: the same compose on the web backend ≤ 40 s (after the preparation above) |
| `dart run tool/ws.dart test --run-skipped -t integration` | Integration stage only: the CORE gateway on the real note store, INK thumbnails and the INK vectorizer |

Real PDFium on the VM: the `pdfium_dart` build hook downloads PDFium chromium/8125
from GitHub (about 3.8 MB) and builds a small C library with gcc on the first run;
later runs use `build/native_assets/linux/libpdfium.so` or the hooks cache. Set
`PDFIUM_PATH` to use another `libpdfium.so`. Every `test/pdfium/` test calls
`initPdfiumForTests()` (`test/support/pdfium_env.dart`) in `setUpAll`.

Conventions: test PDFs are built in the test with `PdfFixtureBuilder`; test code uses
no network; widget tests use the iPad Pro 13" logical size (1032 × 1376); timing
uses fake time everywhere except the `perf` tests.

## Third-party notices

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md): the pub packages (collected by
Flutter automatically) and PDFium with its third-party components, whose verbatim
license texts are in [`licenses/`](licenses/) and registered by `initializePdfIo`.
FreeType and the Independent JPEG Group also ask for a credit in the app's
documentation (open item before the stage-2 release).
