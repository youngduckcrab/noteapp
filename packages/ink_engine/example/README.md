# ink lab (03-ink T23, INK-O1)

One page of a note on the CORE fake store (`createFakeNoteStore()`), wired the
way EDITOR wires INK (03-ink 5.3): the five pens, stroke / partial eraser
(the inverted stylus end always erases), lasso (drag inside the selection to
move it), undo / redo, clear, +1,000 / +3,000 synthetic strokes
(`InkDevTools`), paper cycling (blank + 6 templates, dark paper), zoom 1× /
2× / 4×, pressure mode (`pressureModeProvider`), 'Finger draws' and the
developer numbers (`InkDiagnostics.snapshot`) used by the iPad checks of
03-ink 9.3. Fingers scroll unless 'Finger draws' is on; the stylus and the
mouse draw.

```sh
cd packages/ink_engine/example
flutter pub get
flutter test                 # test/smoke_test.dart
flutter build web            # build/web
flutter run -d web-server --web-hostname 0.0.0.0   # open on the iPad
```

Not a workspace member yet: it resolves on its own (path dependencies, its
`pubspec.lock` is not in git). INFRA registers it (root `workspace:` list,
`lib_exceptions: packages/ink_engine/example/lib/` — lib/ imports
`package:note_core/testing.dart` — and the `web-experiment` channel); then the
path / override entries in `pubspec.yaml` become `resolution: workspace` with
`any` constraints and the `pubspec.lock` line of `.gitignore` goes.
