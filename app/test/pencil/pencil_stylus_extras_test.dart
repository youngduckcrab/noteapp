// PencilStylusExtrasSource and its mapping functions (X35 — docs/plans/m5-7/
// 01-infra.md 4.6.5, 6.12.3 and 6.12.4; contract 00-overview 7.2.10 v2.1 and
// 7.2.13): both 6.12.3 tables row by row, the timestamp of all four event
// kinds (CP-E6), capabilities fixed at construction, unknown phases dropped,
// broadcast and the last cancel reaching the source.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteapp/src/pencil/pencil_stylus_extras.dart';
import 'package:pencil_bridge/pencil_bridge.dart';

const _t = Duration(seconds: 12, microseconds: 345678);

/// Source stream that counts its listeners (broadcast like PencilBridge.events).
final class _CountingSource {
  late final StreamController<PencilEvent> controller =
      StreamController<PencilEvent>.broadcast(
        onListen: () => listens++,
        onCancel: () => cancels++,
      );
  int listens = 0;
  int cancels = 0;

  Future<void> close() => controller.close();
}

void main() {
  group('events (6.12.3 first table)', () {
    final rows = <(String, PencilEvent, StylusExtraEvent)>[
      (
        'tap → double tap (z dropped)',
        const PencilTap(
          _t,
          preferredAction: 'switchEraser',
          position: Offset(10, 20),
          z: 0.4,
        ),
        const StylusDoubleTap(
          preferredAction: StylusPreferredAction.switchEraser,
          hoverPosition: Offset(10, 20),
          timestamp: _t,
        ),
      ),
      (
        'tap without position',
        const PencilTap(_t, preferredAction: 'ignore'),
        const StylusDoubleTap(
          preferredAction: StylusPreferredAction.ignore,
          timestamp: _t,
        ),
      ),
      (
        'squeeze → squeeze (z, roll dropped)',
        const PencilSqueeze(
          _t,
          phase: 'began',
          preferredAction: 'showContextualPalette',
          position: Offset(1, 2),
          z: 0.5,
          roll: 0.25,
        ),
        const StylusSqueeze(
          phase: StylusSqueezePhase.began,
          preferredAction: StylusPreferredAction.showContextualPalette,
          hoverPosition: Offset(1, 2),
          timestamp: _t,
        ),
      ),
      (
        'hover → hover pose (z → height)',
        const PencilHover(
          _t,
          position: Offset(100.5, 200.25),
          z: 0.1,
          altitude: 1.2,
          azimuth: -0.5,
          roll: 0.3,
        ),
        const StylusHoverPose(
          position: Offset(100.5, 200.25),
          height: 0.1,
          altitude: 1.2,
          azimuth: -0.5,
          roll: 0.3,
          timestamp: _t,
        ),
      ),
      (
        'hover with position only',
        const PencilHover(_t, position: Offset(3, 4)),
        const StylusHoverPose(position: Offset(3, 4), timestamp: _t),
      ),
      (
        'roll → barrel roll',
        const PencilRoll(_t, angle: 1.5),
        const StylusBarrelRoll(1.5, timestamp: _t),
      ),
    ];
    for (final (name, pencil, stylus) in rows) {
      test(name, () {
        final mapped = stylusEventOf(pencil);
        expect(mapped, stylus);
        // CP-E6: the native time is passed on as it is.
        expect(mapped!.timestamp, pencil.timestamp);
      });
    }

    test('all four kinds carry the timestamp (CP-E6)', () {
      for (final (i, event) in <PencilEvent>[
        const PencilTap(Duration(microseconds: 1), preferredAction: 'x'),
        const PencilSqueeze(
          Duration(microseconds: 2),
          phase: 'ended',
          preferredAction: 'x',
        ),
        const PencilHover(Duration(microseconds: 3), position: Offset.zero),
        const PencilRoll(Duration(microseconds: 4), angle: 0),
      ].indexed) {
        expect(stylusEventOf(event)!.timestamp, Duration(microseconds: i + 1));
      }
    });

    test('a squeeze with an unknown phase is dropped', () {
      expect(
        stylusEventOf(
          const PencilSqueeze(_t, phase: 'wobble', preferredAction: 'ignore'),
        ),
        isNull,
      );
    });
  });

  group('wire strings → enums', () {
    test('every preferred action name maps to its value', () {
      for (final action in StylusPreferredAction.values) {
        expect(stylusPreferredActionOf(action.name), action);
      }
      expect(
        stylusPreferredActionOf('newAction2030'),
        StylusPreferredAction.unknown,
      );
      expect(stylusPreferredActionOf(''), StylusPreferredAction.unknown);
      expect(
        stylusPreferredActionOf('SwitchEraser'),
        StylusPreferredAction.unknown,
      );
    });

    test('every squeeze phase name maps to its value', () {
      for (final phase in StylusSqueezePhase.values) {
        expect(stylusSqueezePhaseOf(phase.name), phase);
      }
      expect(stylusSqueezePhaseOf('wobble'), isNull);
      expect(stylusSqueezePhaseOf('Began'), isNull);
    });

    test('the wire action names of pencil_bridge are the enum names', () {
      // PencilWire.actions (01-infra 4.4.2) — repeated here because the wire
      // table is internal to pencil_bridge.
      const wireActions = {
        'ignore',
        'switchEraser',
        'switchPrevious',
        'showColorPalette',
        'showInkAttributes',
        'showContextualPalette',
        'runSystemShortcut',
        'unknown',
      };
      expect(
        StylusPreferredAction.values.map((a) => a.name).toSet(),
        wireActions,
      );
    });
  });

  group('capabilities (6.12.3 second table)', () {
    test('doubleTap is always true; the rest is copied', () {
      expect(
        stylusCapabilitiesOf(const PencilCapabilities(os: '15.0')),
        const StylusCapabilities(doubleTap: true),
      );
      expect(
        stylusCapabilitiesOf(
          const PencilCapabilities(os: '17.5', squeeze: true),
        ),
        const StylusCapabilities(doubleTap: true, squeeze: true),
      );
      expect(
        stylusCapabilitiesOf(const PencilCapabilities(os: '17.5', roll: true)),
        const StylusCapabilities(doubleTap: true, barrelRoll: true),
      );
      expect(
        stylusCapabilitiesOf(const PencilCapabilities(os: '16.1', hover: true)),
        const StylusCapabilities(doubleTap: true, hoverPose: true),
      );
      expect(
        stylusCapabilitiesOf(
          const PencilCapabilities(os: '15.0', prefersPencilOnlyDrawing: true),
        ),
        const StylusCapabilities(
          doubleTap: true,
          prefersPencilOnlyDrawing: true,
        ),
      );
      expect(
        stylusCapabilitiesOf(
          const PencilCapabilities(
            os: '18.0',
            squeeze: true,
            hover: true,
            roll: true,
            prefersPencilOnlyDrawing: true,
            preferredTapAction: 'switchEraser',
            preferredSqueezeAction: 'showContextualPalette',
          ),
        ),
        const StylusCapabilities(
          doubleTap: true,
          squeeze: true,
          barrelRoll: true,
          hoverPose: true,
          prefersPencilOnlyDrawing: true,
        ),
      );
    });

    test('the fallback is os ? with everything false → double tap only', () {
      expect(kPencilFallbackCapabilities.os, '?');
      expect(kPencilFallbackCapabilities, const PencilCapabilities(os: '?'));
      expect(
        stylusCapabilitiesOf(kPencilFallbackCapabilities),
        const StylusCapabilities(doubleTap: true),
      );
    });
  });

  group('PencilStylusExtrasSource', () {
    test('isSupported is true; capabilities are the start value, fixed for '
        'the run', () async {
      final source = _CountingSource();
      final extras = PencilStylusExtrasSource(
        capabilities: const PencilCapabilities(os: '17.5', hover: true),
        events: source.controller.stream,
      );
      expect(extras, isA<StylusExtrasSource>());
      expect(extras.isSupported, isTrue);
      const expected = StylusCapabilities(doubleTap: true, hoverPose: true);
      expect(extras.capabilities, expected);
      // Events (even a squeeze) do not change the capabilities.
      final sub = extras.events.listen((_) {});
      source.controller.add(
        const PencilSqueeze(_t, phase: 'began', preferredAction: 'ignore'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(extras.capabilities, expected);
      expect(identical(extras.capabilities, extras.capabilities), isTrue);
      await sub.cancel();
    });

    test('events are mapped in order; unknown phases are dropped', () async {
      final source = _CountingSource();
      final extras = PencilStylusExtrasSource(
        capabilities: kPencilFallbackCapabilities,
        events: source.controller.stream,
      );
      final received = <StylusExtraEvent>[];
      final sub = extras.events.listen(received.add);
      source.controller
        ..add(const PencilTap(_t, preferredAction: 'switchPrevious'))
        ..add(const PencilSqueeze(_t, phase: '??', preferredAction: 'ignore'))
        ..add(const PencilRoll(_t, angle: 0.5));
      await Future<void>.delayed(Duration.zero);
      expect(received, const [
        StylusDoubleTap(
          preferredAction: StylusPreferredAction.switchPrevious,
          timestamp: _t,
        ),
        StylusBarrelRoll(0.5, timestamp: _t),
      ]);
      await sub.cancel();
    });

    test(
      'broadcast; the last cancel cancels the source subscription',
      () async {
        final source = _CountingSource();
        final extras = PencilStylusExtrasSource(
          capabilities: kPencilFallbackCapabilities,
          events: source.controller.stream,
        );
        expect(extras.events.isBroadcast, isTrue);
        expect(
          source.listens,
          0,
          reason: 'nothing subscribes before a listener',
        );

        final a = <StylusExtraEvent>[];
        final b = <StylusExtraEvent>[];
        final subA = extras.events.listen(a.add);
        final subB = extras.events.listen(b.add);
        expect(source.listens, 1);

        source.controller.add(const PencilRoll(_t, angle: 1));
        await Future<void>.delayed(Duration.zero);
        expect(a, hasLength(1));
        expect(b, hasLength(1));

        await subA.cancel();
        expect(source.cancels, 0);
        await subB.cancel();
        expect(source.cancels, 1, reason: 'last cancel reaches the source');

        final subC = extras.events.listen((_) {});
        expect(source.listens, 2, reason: 'a new listener subscribes again');
        await subC.cancel();
        expect(source.cancels, 2);
      },
    );
  });
}
