import 'dart:math';

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

const _node = '3f2a9c0d11e0b7a4';

final class _Wall {
  int ms = 1793750400000;
  Clock get clock =>
      Clock(() => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
}

void main() {
  group('Hlc', () {
    test('text form is fixed width and round-trips', () {
      const h = Hlc(1793750400000, 2, _node);
      expect(h.toString(), '001793750400000-0002-3f2a9c0d11e0b7a4');
      expect(Hlc.parse(h.toString()), h);
      expect(Hlc.zero.toString(), '000000000000000-0000-0000000000000000');
      expect(Hlc.maxCounter, 0xFFFF);
    });

    test('parse errors', () {
      expect(() => Hlc.parse('nope'), throwsFormatException);
      expect(
        () => Hlc.parse('1793750400000-0000-3f2a9c0d11e0b7a4'),
        throwsFormatException,
      );
      expect(
        () => Hlc.parse('001793750400000-00G0-3f2a9c0d11e0b7a4'),
        throwsFormatException,
      );
      expect(Hlc.tryParse(null), isNull);
      expect(Hlc.tryParse('x'), isNull);
    });

    test('string order equals compareTo order', () {
      final r = Random(7);
      final values = [
        for (var i = 0; i < 2000; i++)
          Hlc(
            r.nextInt(1000) * 1000000000 + r.nextInt(1000),
            r.nextInt(0x10000),
            generateNodeId(r),
          ),
      ];
      final byCompare = [...values]..sort();
      final byText = [...values]
        ..sort((a, b) => a.toString().compareTo(b.toString()));
      expect(byText, byCompare);
      expect(const Hlc(1, 0, _node) < const Hlc(1, 1, _node), isTrue);
      expect(const Hlc(2, 0, _node) > const Hlc(1, 9, _node), isTrue);
    });
  });

  group('HlcClock', () {
    test(
      'now() is strictly increasing, also when the wall clock goes back',
      () {
        final wall = _Wall();
        final c = HlcClock(nodeId: _node, clock: wall.clock);
        var last = c.now();
        for (var i = 0; i < 100; i++) {
          if (i == 50) wall.ms -= 60000; // clock goes back a minute
          if (i % 7 == 0) wall.ms += 1;
          final next = c.now();
          expect(next > last, isTrue);
          last = next;
        }
        expect(last.nodeId, _node);
      },
    );

    test('counter overflow moves to the next millisecond', () {
      final wall = _Wall();
      final c = HlcClock(
        nodeId: _node,
        clock: wall.clock,
        last: Hlc(wall.ms, Hlc.maxCounter, _node),
      );
      expect(c.now(), Hlc(wall.ms + 1, 0, _node));
    });

    test('receive: the four counter rules', () {
      final wall = _Wall();
      final t = wall.ms;
      // m == last == remote
      var c = HlcClock(
        nodeId: _node,
        clock: wall.clock,
        last: Hlc(t + 5, 3, _node),
      );
      expect(
        c.receive(Hlc(t + 5, 7, 'ffffffffffffffff')),
        Hlc(t + 5, 8, _node),
      );
      // m == last only
      c = HlcClock(
        nodeId: _node,
        clock: wall.clock,
        last: Hlc(t + 5, 3, _node),
      );
      expect(
        c.receive(Hlc(t + 1, 9, 'ffffffffffffffff')),
        Hlc(t + 5, 4, _node),
      );
      // m == remote only
      c = HlcClock(
        nodeId: _node,
        clock: wall.clock,
        last: Hlc(t - 5, 3, _node),
      );
      expect(
        c.receive(Hlc(t + 10, 2, 'ffffffffffffffff')),
        Hlc(t + 10, 3, _node),
      );
      // wall clock wins
      c = HlcClock(
        nodeId: _node,
        clock: wall.clock,
        last: Hlc(t - 5, 3, _node),
      );
      expect(c.receive(Hlc(t - 2, 2, 'ffffffffffffffff')), Hlc(t, 0, _node));
    });

    test('receive: +24 h is accepted, +48 h does not move the clock', () {
      final wall = _Wall();
      final c = HlcClock(nodeId: _node, clock: wall.clock);
      final before = c.now();
      const day = 24 * 3600 * 1000;
      expect(c.receive(Hlc(wall.ms + 2 * day, 0, 'ffffffffffffffff')), before);
      expect(c.last, before);
      final accepted = c.receive(Hlc(wall.ms + day, 4, 'ffffffffffffffff'));
      expect(accepted, Hlc(wall.ms + day, 5, _node));
      expect(c.now() > accepted, isTrue);
    });
  });

  test('generateNodeId: 16 lowercase hex chars', () {
    for (var i = 0; i < 50; i++) {
      expect(generateNodeId(), matches(RegExp(r'^[0-9a-f]{16}$')));
    }
    expect(generateNodeId(Random(1)), generateNodeId(Random(1)));
  });
}
