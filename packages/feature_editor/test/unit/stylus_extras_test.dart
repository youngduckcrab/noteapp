// Stylus extras v2 (2nd-round contract m5-7/00-overview 7.2.10, m5-7/04-editor
// 4.3.4; task R2-B5, 8.1): NoStylusExtras reports StylusCapabilities.none,
// and every event type compares all its fields — timestamp included (v2.1,
// CP-E6) — so equal events can be filtered as duplicates.
import 'package:feature_editor/feature_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _t1 = Duration(milliseconds: 100);
const _t2 = Duration(milliseconds: 101);

/// false, not as a constant (so the comparison below builds a new value).
bool _no() => false;

/// [a] == [b] with equal hash codes, and [a] differs from each of [others].
void _expectValue(Object a, Object b, List<Object> others) {
  expect(a, b);
  expect(a.hashCode, b.hashCode);
  for (final other in others) {
    expect(a, isNot(other), reason: '$a vs $other');
  }
}

void main() {
  group('NoStylusExtras', () {
    test('capabilities == StylusCapabilities.none', () {
      const source = NoStylusExtras();
      expect(source.capabilities, StylusCapabilities.none);
      expect(source.capabilities, StylusCapabilities(doubleTap: _no()));
      expect(source.isSupported, isFalse);
    });

    test('events is empty', () async {
      expect(await const NoStylusExtras().events.toList(), isEmpty);
    });

    test('is the default of stylusExtrasProvider', () {
      final container = ProviderContainer.test();
      final source = container.read(stylusExtrasProvider);
      expect(source, isA<NoStylusExtras>());
      expect(source.capabilities, StylusCapabilities.none);
    });
  });

  group('StylusCapabilities', () {
    test('none is all false', () {
      const none = StylusCapabilities.none;
      expect(none.doubleTap, isFalse);
      expect(none.squeeze, isFalse);
      expect(none.barrelRoll, isFalse);
      expect(none.hoverPose, isFalse);
      expect(none.prefersPencilOnlyDrawing, isFalse);
    });

    test('compares every field', () {
      _expectValue(
        const StylusCapabilities(doubleTap: true, hoverPose: true),
        const StylusCapabilities(doubleTap: true, hoverPose: true),
        const [
          StylusCapabilities.none,
          StylusCapabilities(doubleTap: true),
          StylusCapabilities(doubleTap: true, hoverPose: true, squeeze: true),
          StylusCapabilities(
            doubleTap: true,
            hoverPose: true,
            barrelRoll: true,
          ),
          StylusCapabilities(
            doubleTap: true,
            hoverPose: true,
            prefersPencilOnlyDrawing: true,
          ),
        ],
      );
    });
  });

  group('event value equality (timestamp included)', () {
    test('StylusDoubleTap', () {
      const a = StylusDoubleTap(
        preferredAction: StylusPreferredAction.switchEraser,
        hoverPosition: Offset(1, 2),
        timestamp: _t1,
      );
      _expectValue(
        a,
        const StylusDoubleTap(
          preferredAction: StylusPreferredAction.switchEraser,
          hoverPosition: Offset(1, 2),
          timestamp: _t1,
        ),
        const [
          StylusDoubleTap(
            preferredAction: StylusPreferredAction.switchEraser,
            hoverPosition: Offset(1, 2),
            timestamp: _t2,
          ),
          StylusDoubleTap(
            preferredAction: StylusPreferredAction.switchEraser,
            hoverPosition: Offset(1, 2),
          ),
          StylusDoubleTap(
            preferredAction: StylusPreferredAction.switchPrevious,
            hoverPosition: Offset(1, 2),
            timestamp: _t1,
          ),
          StylusDoubleTap(
            preferredAction: StylusPreferredAction.switchEraser,
            timestamp: _t1,
          ),
          StylusSqueeze(
            preferredAction: StylusPreferredAction.switchEraser,
            hoverPosition: Offset(1, 2),
            timestamp: _t1,
          ),
        ],
      );
      expect(const StylusDoubleTap(), const StylusDoubleTap());
    });

    test('StylusSqueeze', () {
      const a = StylusSqueeze(
        phase: StylusSqueezePhase.began,
        preferredAction: StylusPreferredAction.showContextualPalette,
        hoverPosition: Offset(5, 6),
        timestamp: _t1,
      );
      _expectValue(
        a,
        const StylusSqueeze(
          phase: StylusSqueezePhase.began,
          preferredAction: StylusPreferredAction.showContextualPalette,
          hoverPosition: Offset(5, 6),
          timestamp: _t1,
        ),
        const [
          StylusSqueeze(
            phase: StylusSqueezePhase.began,
            preferredAction: StylusPreferredAction.showContextualPalette,
            hoverPosition: Offset(5, 6),
            timestamp: _t2,
          ),
          StylusSqueeze(
            phase: StylusSqueezePhase.ended,
            preferredAction: StylusPreferredAction.showContextualPalette,
            hoverPosition: Offset(5, 6),
            timestamp: _t1,
          ),
          StylusSqueeze(
            phase: StylusSqueezePhase.began,
            preferredAction: StylusPreferredAction.ignore,
            hoverPosition: Offset(5, 6),
            timestamp: _t1,
          ),
          StylusSqueeze(
            phase: StylusSqueezePhase.began,
            preferredAction: StylusPreferredAction.showContextualPalette,
            timestamp: _t1,
          ),
        ],
      );
      expect(const StylusSqueeze().phase, StylusSqueezePhase.ended);
      expect(
        const StylusSqueeze().preferredAction,
        StylusPreferredAction.unknown,
      );
    });

    test('StylusBarrelRoll', () {
      _expectValue(
        const StylusBarrelRoll(0.5, timestamp: _t1),
        const StylusBarrelRoll(0.5, timestamp: _t1),
        const [
          StylusBarrelRoll(0.5, timestamp: _t2),
          StylusBarrelRoll(0.5),
          StylusBarrelRoll(0.6, timestamp: _t1),
        ],
      );
      expect(const StylusBarrelRoll(1), const StylusBarrelRoll(1));
    });

    test('StylusHoverPose', () {
      const a = StylusHoverPose(
        position: Offset(10, 20),
        height: 0.3,
        altitude: 0.9,
        azimuth: 1.2,
        roll: 0.1,
        timestamp: _t1,
      );
      _expectValue(
        a,
        const StylusHoverPose(
          position: Offset(10, 20),
          height: 0.3,
          altitude: 0.9,
          azimuth: 1.2,
          roll: 0.1,
          timestamp: _t1,
        ),
        const [
          StylusHoverPose(
            position: Offset(10, 20),
            height: 0.3,
            altitude: 0.9,
            azimuth: 1.2,
            roll: 0.1,
            timestamp: _t2,
          ),
          StylusHoverPose(
            position: Offset(10, 21),
            height: 0.3,
            altitude: 0.9,
            azimuth: 1.2,
            roll: 0.1,
            timestamp: _t1,
          ),
          StylusHoverPose(
            position: Offset(10, 20),
            altitude: 0.9,
            azimuth: 1.2,
            roll: 0.1,
            timestamp: _t1,
          ),
          StylusHoverPose(
            position: Offset(10, 20),
            height: 0.3,
            azimuth: 1.2,
            roll: 0.1,
            timestamp: _t1,
          ),
          StylusHoverPose(
            position: Offset(10, 20),
            height: 0.3,
            altitude: 0.9,
            roll: 0.1,
            timestamp: _t1,
          ),
          StylusHoverPose(
            position: Offset(10, 20),
            height: 0.3,
            altitude: 0.9,
            azimuth: 1.2,
            timestamp: _t1,
          ),
        ],
      );
    });

    test('different subtypes are never equal', () {
      const events = <StylusExtraEvent>[
        StylusDoubleTap(timestamp: _t1),
        StylusSqueeze(timestamp: _t1),
        StylusBarrelRoll(0, timestamp: _t1),
        StylusHoverPose(position: Offset.zero, timestamp: _t1),
      ];
      for (var i = 0; i < events.length; i++) {
        for (var j = 0; j < events.length; j++) {
          if (i == j) continue;
          expect(events[i], isNot(events[j]));
        }
      }
    });

    test('the timestamp is on the base class', () {
      const events = <StylusExtraEvent>[
        StylusDoubleTap(timestamp: _t1),
        StylusSqueeze(timestamp: _t1),
        StylusBarrelRoll(0, timestamp: _t1),
        StylusHoverPose(position: Offset.zero, timestamp: _t1),
      ];
      for (final event in events) {
        expect(event.timestamp, _t1);
      }
      expect(
        [
          const StylusDoubleTap(),
          const StylusSqueeze(),
          const StylusBarrelRoll(0),
          const StylusHoverPose(position: Offset.zero),
        ].map((e) => e.timestamp),
        everyElement(isNull),
      );
    });
  });
}
