// T03 (03-ink 8, 6.4): the app's only pressure-detection rule.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/input/pressure_detector.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

PressureDetector _detector({
  InkPointerKind kind = InkPointerKind.stylus,
  PressureMode mode = PressureMode.auto,
  PressureCapability prior = PressureCapability.unknown,
  PressureCapabilityStore? store,
}) => PressureDetector(kind: kind, mode: mode, prior: prior, store: store);

void main() {
  test('ramp (+0.03 per sample) → real at the 2nd sample, reported', () {
    final store = MemoryPressureStore();
    final d = _detector(store: store);
    expect(d.source, PressureSource.pending);
    expect(d.capability, PressureCapability.unknown);
    expect(d.observe(0.30), isFalse);
    expect(d.source, PressureSource.pending);
    expect(d.observe(0.33), isTrue);
    expect(d.source, PressureSource.real);
    expect(d.capability, PressureCapability.supported);
    expect(d.constantValue, isNull);
    expect(
      store.capabilityOf(InkPointerKind.stylus),
      PressureCapability.supported,
    );
    // Decided: later values change nothing.
    for (var i = 0; i < 20; i++) {
      expect(d.observe(0.5), isFalse);
    }
    expect(d.source, PressureSource.real);
    expect(d.finish(), PressureSource.real);
  });

  test('a variation of exactly 0.02 is not enough', () {
    final d = _detector();
    d.observe(0.40);
    expect(d.observe(0.42 - 1e-9), isFalse);
    expect(d.observe(0.38 + 1e-9), isFalse);
    expect(d.source, PressureSource.pending);
  });

  for (final value in [0.5, 0.0, 1.0]) {
    test('$value held for 12 samples → unsupported at the 12th', () {
      final store = MemoryPressureStore();
      final d = _detector(store: store);
      for (var i = 1; i < 12; i++) {
        expect(d.observe(value), isFalse, reason: 'sample $i');
        expect(d.source, PressureSource.pending);
      }
      expect(d.observe(value), isTrue);
      expect(d.source, PressureSource.simulated);
      expect(d.capability, PressureCapability.unsupported);
      expect(d.constantValue, value);
      expect(
        store.capabilityOf(InkPointerKind.stylus),
        PressureCapability.unsupported,
      );
      expect(d.finish(), PressureSource.simulated);
    });
  }

  test('a run near 0.5 within the epsilons also counts', () {
    final d = _detector();
    for (var i = 0; i < 12; i++) {
      d.observe(0.5004 + (i.isEven ? 0 : 0.00005));
    }
    expect(d.capability, PressureCapability.unsupported);
  });

  test('a broken run starts over', () {
    final d = _detector();
    for (var i = 0; i < 11; i++) {
      d.observe(0.5);
    }
    d.observe(0.505); // differs by > 1e-4: new run (still within 0.02 of first)
    // 0.5 again starts another run: 11 more are not enough …
    for (var i = 0; i < 11; i++) {
      d.observe(0.5);
    }
    expect(d.source, PressureSource.pending);
    // … the 12th is.
    expect(d.observe(0.5), isTrue);
    expect(d.source, PressureSource.simulated);
  });

  test('0.37 held → stays pending; finish → simulated, capability unknown', () {
    final store = MemoryPressureStore();
    final d = _detector(store: store);
    for (var i = 0; i < 40; i++) {
      expect(d.observe(0.37), isFalse);
    }
    expect(d.source, PressureSource.pending);
    expect(d.capability, PressureCapability.unknown);
    expect(d.finish(), PressureSource.simulated);
    expect(d.source, PressureSource.simulated);
    expect(d.capability, PressureCapability.unknown);
    expect(
      store.capabilityOf(InkPointerKind.stylus),
      PressureCapability.unknown,
    );
  });

  test('null pressure (up / cancel) is ignored', () {
    final d = _detector();
    d.observe(0.30);
    expect(d.observe(null), isFalse);
    expect(d.observe(double.nan), isFalse);
    expect(d.source, PressureSource.pending);
    expect(d.observe(0.40), isTrue);
  });

  test('touch, mouse, trackpad, unknown → simulated at once', () {
    for (final kind in [
      InkPointerKind.touch,
      InkPointerKind.mouse,
      InkPointerKind.trackpad,
      InkPointerKind.unknown,
    ]) {
      final store = MemoryPressureStore();
      final d = _detector(kind: kind, store: store);
      expect(d.source, PressureSource.simulated, reason: kind.name);
      expect(d.capability, PressureCapability.unsupported);
      // Pressure values from a finger never switch it to real.
      expect(d.observe(0.1), isFalse);
      expect(d.observe(0.9), isFalse);
      expect(d.source, PressureSource.simulated);
      expect(d.finish(), PressureSource.simulated);
      expect(
        store.capabilityOf(InkPointerKind.stylus),
        PressureCapability.unknown,
      );
    }
  });

  test('prior supported → real at once', () {
    final d = _detector(prior: PressureCapability.supported);
    expect(d.source, PressureSource.real);
    expect(d.capability, PressureCapability.supported);
    expect(d.observe(0.3), isFalse);
    expect(d.observe(0.7), isFalse);
    expect(d.source, PressureSource.real);
  });

  test('prior supported, then a fixed value → unsupported re-reported', () {
    final store = MemoryPressureStore()
      ..report(InkPointerKind.stylus, PressureCapability.supported);
    final d = _detector(prior: PressureCapability.supported, store: store);
    for (var i = 0; i < 12; i++) {
      // The stroke being drawn keeps its source.
      expect(d.observe(0.5), isFalse);
    }
    expect(d.source, PressureSource.real);
    expect(d.capability, PressureCapability.unsupported);
    expect(d.constantValue, 0.5);
    expect(
      store.capabilityOf(InkPointerKind.stylus),
      PressureCapability.unsupported,
    );
    // The next stroke starts simulated.
    final next = _detector(
      prior: store.capabilityOf(InkPointerKind.stylus),
      store: store,
    );
    expect(next.source, PressureSource.simulated);
  });

  test('prior unsupported → simulated at once, no observation', () {
    final store = MemoryPressureStore()
      ..report(
        InkPointerKind.stylus,
        PressureCapability.unsupported,
        constantValue: 0.5,
      );
    final d = _detector(prior: PressureCapability.unsupported, store: store);
    expect(d.source, PressureSource.simulated);
    expect(d.capability, PressureCapability.unsupported);
    d.observe(0.2);
    expect(d.observe(0.8), isFalse);
    expect(d.source, PressureSource.simulated);
  });

  test('inverted stylus follows the stylus rule', () {
    final d = _detector(kind: InkPointerKind.invertedStylus);
    expect(d.source, PressureSource.pending);
    d.observe(0.2);
    expect(d.observe(0.3), isTrue);
    expect(d.source, PressureSource.real);
  });

  group('forced modes', () {
    test('alwaysReal → real for every kind, no observation or report', () {
      for (final kind in InkPointerKind.values) {
        for (final prior in PressureCapability.values) {
          final store = MemoryPressureStore();
          final d = _detector(
            kind: kind,
            mode: PressureMode.alwaysReal,
            prior: prior,
            store: store,
          );
          expect(d.source, PressureSource.real);
          for (var i = 0; i < 12; i++) {
            expect(d.observe(0.5), isFalse);
          }
          expect(d.finish(), PressureSource.real);
          expect(
            store.capabilityOf(InkPointerKind.stylus),
            PressureCapability.unknown,
          );
        }
      }
    });

    test('alwaysSimulated → simulated for every kind', () {
      for (final kind in InkPointerKind.values) {
        final d = _detector(kind: kind, mode: PressureMode.alwaysSimulated);
        expect(d.source, PressureSource.simulated);
        d.observe(0.1);
        expect(d.observe(0.9), isFalse);
        expect(d.finish(), PressureSource.simulated);
      }
    });

    test('a forced mode keeps the remembered stylus capability', () {
      expect(
        _detector(
          mode: PressureMode.alwaysSimulated,
          prior: PressureCapability.supported,
        ).capability,
        PressureCapability.supported,
      );
    });
  });

  test('the controller wires the detector to its store (later strokes start decided)', () {
    final c = createTestPageController()
      ..updateContent(SyntheticInk.pageContent());
    addTearDown(c.dispose);
    final ramp = SyntheticInk.wave(
      const Offset(10, 100),
      samples: 40,
      pressureAt: (t) => 0.2 + 0.6 * t,
    );
    final style = core.StrokeStyle.defaultsFor(core.PenTool.fountain);
    final s1 = c.beginStroke(ramp.first, style: style, viewScale: 1);
    expect(s1.pressureSource, PressureSource.pending);
    s1.addSamples(ramp.skip(1));
    expect(s1.pressureSource, PressureSource.real);
    s1.end();
    expect(
      c.pressureStore.capabilityOf(InkPointerKind.stylus),
      PressureCapability.supported,
    );
    final s2 = c.beginStroke(ramp.first, style: style, viewScale: 1);
    expect(s2.pressureSource, PressureSource.real);
    s2.cancel();
  });
}
