// T03 (03-ink 8, 4.3): pressureModeProvider — default auto, read at every
// beginStroke (a stroke keeps the mode it started with), same value → no
// notification, no override needed.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:riverpod/riverpod.dart';

void main() {
  test('default auto, works without any override', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(pressureModeProvider), PressureMode.auto);
    expect(pressureModeProvider.name, 'pressureModeProvider');
    expect(PressureMode.values.map((m) => m.name), [
      'auto',
      'alwaysReal',
      'alwaysSimulated',
    ]);
  });

  test('set notifies once per change; the same value does not notify', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final seen = <PressureMode>[];
    container.listen(
      pressureModeProvider,
      (_, next) => seen.add(next),
      fireImmediately: false,
    );
    final n = container.read(pressureModeProvider.notifier);
    n.set(PressureMode.auto);
    expect(seen, isEmpty);
    n.set(PressureMode.alwaysSimulated);
    n.set(PressureMode.alwaysSimulated);
    n.set(PressureMode.alwaysReal);
    n.set(PressureMode.alwaysReal);
    expect(seen, [PressureMode.alwaysSimulated, PressureMode.alwaysReal]);
    expect(container.read(pressureModeProvider), PressureMode.alwaysReal);
  });

  test('a new mode applies from the NEXT beginStroke; the stroke being drawn keeps its mode', () async {
    final store = core_testing.createFakeNoteStore();
    final container = ProviderContainer(
      overrides: [core.noteStoreProvider.overrideWithValue(store)],
    );
    addTearDown(() async {
      container.dispose();
      await store.close();
    });
    final sub = container.listen(inkPageControllerProvider('p1'), (_, _) {});
    addTearDown(sub.close);
    final c = sub.read()..updateContent(SyntheticInk.pageContent());
    final style = core.StrokeStyle.defaultsFor(core.PenTool.fountain);
    final samples = SyntheticInk.wave(
      const Offset(20, 100),
      samples: 30,
      pressureAt: (t) => 0.2 + 0.6 * t,
    );

    // auto + stylus with an unknown capability: pending, then real.
    final s1 = c.beginStroke(samples.first, style: style, viewScale: 1);
    expect(s1.pressureSource, PressureSource.pending);
    container
        .read(pressureModeProvider.notifier)
        .set(PressureMode.alwaysSimulated);
    // The stroke being drawn still follows auto.
    s1.addSamples(samples.skip(1));
    expect(s1.pressureSource, PressureSource.real);
    s1.end();

    // The next stroke reads alwaysSimulated, although the stylus is supported.
    final s2 = c.beginStroke(samples.first, style: style, viewScale: 1);
    expect(s2.pressureSource, PressureSource.simulated);
    container.read(pressureModeProvider.notifier).set(PressureMode.alwaysReal);
    s2.addSamples(samples.skip(1));
    expect(s2.pressureSource, PressureSource.simulated);
    s2.end();

    // And the one after that alwaysReal, even for a finger.
    final finger = SyntheticInk.line(
      const Offset(20, 200),
      const Offset(200, 200),
      kind: InkPointerKind.touch,
    );
    final s3 = c.beginStroke(finger.first, style: style, viewScale: 1);
    expect(s3.pressureSource, PressureSource.real);
    s3.cancel();
  });
}
