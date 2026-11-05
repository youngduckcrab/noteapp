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
# at the repository root: one workspace resolution, one pubspec.lock
flutter pub get
dart run tool/ws.dart test --package ink_lab   # test/smoke_test.dart (VM)

cd packages/ink_engine/example
flutter build web            # build/web
flutter run -d web-server --web-hostname 0.0.0.0   # open on the iPad
```

A workspace member since the integration step (INFRA-O1, 01-infra 1.3):
`ink_lab`, `resolution: workspace`, listed in the root `workspace:` and
resolved with the other members into the root `pubspec.lock`, so
`flutter pub get` runs at the repository root. `tool/workspace_rules.yaml`
allows it `note_core` and `ink_engine` (`allowed_dependencies`), lets its
`lib/` import `package:note_core/testing.dart` (`lib_exceptions`) and keeps it
out of R14 as an app (`app_members`). The manual `web-experiment` workflow
with input `target: ink_lab` builds it and deploys it to the 7-day Hosting
channel `exp-ink-lab`.
