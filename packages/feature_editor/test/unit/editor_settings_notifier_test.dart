// EditorSettingsNotifier in foundation step B5: memory only (04-editor 4.8,
// 8.1 B5). The setters change the state; the INK pressure-mode bridge runs in
// setPressureMode() and resetToDefaults() and never in build() (contract
// 7.3.3, 04-editor 6.13.1 #7). Task E-06 adds load / debounced save tests.
import 'package:feature_editor/feature_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;

void main() {
  late ProviderContainer container;
  late EditorSettingsNotifier notifier;

  setUp(() {
    container = ProviderContainer.test();
    notifier = container.read(editorSettingsProvider.notifier);
  });

  EditorSettings state() => container.read(editorSettingsProvider);

  test('starts with the defaults without a note store', () {
    expect(state(), const EditorSettings());
    expect(notifier.isLoaded, isTrue);
  });

  test('every setter updates its field', () {
    notifier.setInputMode(InputMode.penOnly);
    expect(state().inputMode, InputMode.penOnly);

    const palm = PalmRejectionSettings(
      penCooldown: Duration(milliseconds: 800),
      treatHoverAsPenActivity: false,
      maxTouchRadius: 90,
    );
    notifier.setPalmRejection(palm);
    expect(state().palmRejection, palm);

    const gestures = GestureSettings(threeFingerTapRedo: false);
    notifier.setGestures(gestures);
    expect(state().gestures, gestures);

    notifier.setPageFlipMode(PageFlipMode.horizontalPaged);
    expect(state().pageFlipMode, PageFlipMode.horizontalPaged);

    notifier.setShowDevOverlay(true);
    expect(state().showDevOverlay, isTrue);
    notifier.toggleDevOverlay();
    expect(state().showDevOverlay, isFalse);
    notifier.toggleDevOverlay();
    expect(state().showDevOverlay, isTrue);

    expect(
      state(),
      const EditorSettings(
        inputMode: InputMode.penOnly,
        palmRejection: palm,
        gestures: gestures,
        pageFlipMode: PageFlipMode.horizontalPaged,
        showDevOverlay: true,
      ),
    );
  });

  test('markStylusSeen sets the flag once and notifies once', () {
    final seen = <bool>[];
    container.listen(
      editorSettingsProvider.select((s) => s.stylusSeen),
      (previous, next) => seen.add(next),
    );
    final changes = <EditorSettings>[];
    container.listen(
      editorSettingsProvider,
      (previous, next) => changes.add(next),
    );

    notifier.markStylusSeen();
    notifier.markStylusSeen();

    expect(state().stylusSeen, isTrue);
    expect(seen, [true]);
    expect(changes, hasLength(1));
    expect(state().isPenOnlyEffective, isTrue); // auto + stylus seen
  });

  test('an equal value does not notify listeners (value equality)', () {
    final changes = <EditorSettings>[];
    container.listen(
      editorSettingsProvider,
      (previous, next) => changes.add(next),
    );
    notifier.setInputMode(InputMode.auto);
    notifier.setPalmRejection(const PalmRejectionSettings());
    notifier.setGestures(const GestureSettings());
    expect(changes, isEmpty);
  });

  test('setPressureMode pushes the mode to ink.pressureModeProvider', () {
    expect(container.read(ink.pressureModeProvider), ink.PressureMode.auto);

    notifier.setPressureMode(ink.PressureMode.alwaysSimulated);
    expect(state().pressureMode, ink.PressureMode.alwaysSimulated);
    expect(
      container.read(ink.pressureModeProvider),
      ink.PressureMode.alwaysSimulated,
    );

    notifier.setPressureMode(ink.PressureMode.alwaysReal);
    expect(
      container.read(ink.pressureModeProvider),
      ink.PressureMode.alwaysReal,
    );
  });

  test('build() does not touch ink.pressureModeProvider', () {
    // INK holds a value the editor did not set; reading the editor settings
    // (build) must leave it alone (V4: no provider writes inside build()).
    final fresh = ProviderContainer.test();
    fresh
        .read(ink.pressureModeProvider.notifier)
        .set(ink.PressureMode.alwaysReal);
    expect(
      fresh.read(editorSettingsProvider).pressureMode,
      isNot(ink.PressureMode.alwaysReal),
    );
    expect(fresh.read(ink.pressureModeProvider), ink.PressureMode.alwaysReal);
  });

  test('resetToDefaults restores defaults and pushes auto to INK', () async {
    notifier
      ..setInputMode(InputMode.fingerDrawing)
      ..setShowDevOverlay(true)
      ..markStylusSeen()
      ..setPressureMode(ink.PressureMode.alwaysSimulated);

    notifier.resetToDefaults();

    expect(state(), const EditorSettings());
    expect(container.read(ink.pressureModeProvider), ink.PressureMode.auto);
    await expectLater(notifier.flush(), completes);
  });
}
