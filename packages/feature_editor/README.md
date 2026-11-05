# feature_editor

Owned by **EDITOR**: the note editor screen (writing surface, input routing,
toolbar, pen settings, preset bar, page panel and developer overlay).
Plan: [docs/plans/04-editor.md](../../docs/plans/04-editor.md) ·
progress: [docs/plans/progress/editor.md](../../docs/plans/progress/editor.md) ·
contract: [00-overview.md](../../docs/plans/00-overview.md) 7.2.17.

## Public API

`package:feature_editor/feature_editor.dart` is the only entry point
(contract 7.1). Its `show` lists are exactly the names of 04-editor 4.1:
`EditorScreen`, `featureEditorOverrides`, the extension points
(`EditorExtensions`, `EditorMenuItem`, `EditorMenuContext`,
`editorExtensionsProvider`, `DevOverlaySection`, `devOverlaySectionsProvider`),
the stylus extras interface (`StylusExtrasSource` family,
`stylusExtrasProvider`), the settings model and notifier (`EditorSettings`,
`InputMode`, `PageFlipMode`, `PalmRejectionSettings`, `GestureSettings`,
`EditorSettingsNotifier`, `editorSettingsProvider`) and the four settings
sections for the app's settings screen. Everything under `lib/src/` is private
(`unit/api_surface_test.dart`).

Depends on `note_core` (imported as `core.`) and `ink_engine` (as `ink.`)
only, never on `feature_library`, `pdf_io` or `sync_engine`: the app shell
connects them.

## Rules

- Material comes from `package:material_ui/material_ui.dart` only, in lib and
  test. No `dart:io` / `dart:html` / `package:web` in `lib/`; the package needs
  no platform files. `unit/no_platform_imports_test.dart` checks this together
  with the other 04-editor 6.16 rules.
- Riverpod 3.4.3 without code generation; every provider has `name:`.
- User-facing strings are Korean 해요체 constants in
  `lib/src/ui/editor_strings.dart` (no intl). The two storage-warning
  sentences are the contract 7.4.5 fixed sentences
  (`unit/editor_strings_test.dart`).

## Tests

Run from this directory:

```sh
flutter test                                   # VM: unit/, widget/, goldens/
flutter test --platform chrome test/web        # browser tests (@TestOn('browser'))
flutter test --run-skipped -t integration      # integration stage only (E-21)
```

- `test/unit/`, `test/widget/`: VM tests on CORE's `createFakeNoteStore()` and
  the INK implementation. No real-time waits: `fake_async` / `tester.pump`.
- `test/goldens/`: `@Tags(['golden'])` + `@TestOn('vm')`.
- `test/integration/`: `@Tags(['integration'])`, real CORE + real INK. The
  `integration` tag is skipped by default in `dart_test.yaml`, so these run
  only in the integration stage (`ws test --run-skipped -t integration`).
- `test/web/`: `@TestOn('browser')`.
- Every tag is a string literal and is declared in `dart_test.yaml` first
  (`ws check` R15). Screen size: iPad Pro 13" logical 1032×1376 / 1376×1032.
