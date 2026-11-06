// m5-7/03-ink 8.2 T40 (6.19): the playback index.
// - Per recording id, the linked strokes (recordingId + recordingOffsetMs) in
//   offset order — equal offsets keep the content z order.
// - The boundary k (first unwritten entry) and the recent range by binary search
//   (= a linear scan for random tracks).
// - Every R-4 state: written (offset + tLast ≤ p), writing (offset ≤ p < offset +
//   tLast, the points with offset + t(i) > p still to come), unwritten (offset >
//   p), recent (p − W < offset ≤ p).
// - Other recordings, strokes without a recording, a recording id without an
//   offset: not in the track.
// - A content change rebuilds only the recording whose strokes changed.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/playback_index.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/pixels.dart';

const _pageId = 'p1';

/// A stroke of [points] points (t = 0, 10, 20, … ms) linked to [recording] at [offset].
core.Stroke _rec(
  String id,
  String? recording,
  int? offset, {
  int points = 11,
  int createdAt = 1000,
}) {
  final style = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint);
  return strokeThrough(
    [for (var i = 0; i < points; i++) Offset(10.0 + i, 20)],
    style,
    id: id,
  ).copyWith(
    recordingId: recording,
    recordingOffsetMs: offset,
    createdAt: createdAt,
  );
}

InkPageContent _content(List<core.Stroke> strokes, {int revision = 1}) =>
    InkPageContent.fromCore(
      page: SyntheticInk.page(pageId: _pageId),
      strokes: strokes,
      revision: revision,
    );

List<String> _ids(PlaybackTrack t) => [for (final e in t.entries) e.stroke.id];

void main() {
  group('track', () {
    test('linked strokes in offset order; equal offsets keep the z order; '
        'others left out', () {
      final index = PlaybackIndex()
        ..update(
          _content([
            _rec('c', 'r1', 300, createdAt: 1),
            _rec('a', 'r1', 100, createdAt: 2),
            _rec('x', 'r2', 50, createdAt: 3),
            _rec('n', null, null, createdAt: 4),
            _rec('no-offset', 'r1', null, createdAt: 5),
            _rec('b1', 'r1', 200, createdAt: 6),
            _rec('b2', 'r1', 200, createdAt: 7),
          ]),
        );
      final t = index.trackOf('r1')!;
      expect(_ids(t), ['a', 'b1', 'b2', 'c']);
      expect([for (final e in t.entries) e.offsetMs], [100, 200, 200, 300]);
      expect(t.entries.first.durationMs, 100, reason: 'last t of 11 points');
      expect(t.maxDurationMs, 100);
      expect(_ids(index.trackOf('r2')!), ['x']);
      expect(index.trackOf('none'), isNull);
      expect(index.recordingIds.toSet(), {'r1', 'r2'});
      expect(() => t.entries.add(t.entries.first), throwsUnsupportedError);
    });

    test('a one-point stroke has tLast 0 (written as soon as it starts)', () {
      final index = PlaybackIndex()
        ..update(_content([_rec('dot', 'r', 500, points: 1)]));
      final t = index.trackOf('r')!;
      expect(t.entries.single.durationMs, 0);
      expect(t.stateAt(0, 499), PlaybackState.unwritten);
      expect(t.stateAt(0, 500), PlaybackState.written);
    });

    test('boundary and recent range = a linear scan (random tracks)', () {
      final random = math.Random(40);
      for (var round = 0; round < 20; round++) {
        final strokes = [
          for (var i = 0; i < 1 + random.nextInt(200); i++)
            _rec(
              's$round-$i',
              'r',
              random.nextInt(5000),
              points: 1 + random.nextInt(30),
              createdAt: i,
            ),
        ];
        final t = (PlaybackIndex()..update(_content(strokes))).trackOf('r')!;
        for (var i = 1; i < t.length; i++) {
          expect(
            t.entries[i - 1].offsetMs,
            lessThanOrEqualTo(t.entries[i].offsetMs),
          );
        }
        for (var q = 0; q < 50; q++) {
          final p = random.nextInt(5600) - 300;
          final w = random.nextInt(3000);
          final k = t.boundary(p);
          for (var i = 0; i < t.length; i++) {
            expect(t.entries[i].offsetMs > p, i >= k, reason: 'k at $p');
          }
          final (start, end) = t.recentRange(p, w);
          expect(end, k);
          for (var i = 0; i < t.length; i++) {
            expect(
              i >= start && i < end,
              t.isRecent(i, p, w),
              reason: 'recent $i at $p, $w',
            );
          }
          final writing = t.writing(p);
          expect(writing, [
            for (var i = 0; i < t.length; i++)
              if (t.stateAt(i, p) == PlaybackState.writing) i,
          ]);
        }
      }
    });
  });

  group('R-4 states', () {
    // 'w' runs from 1000 to 1100 ms (11 points, 10 ms apart)
    final t =
        (PlaybackIndex()..update(
              _content([
                _rec('early', 'r', 0),
                _rec('w', 'r', 1000),
                _rec('late', 'r', 5000),
              ]),
            ))
            .trackOf('r')!;

    test('written / writing / unwritten at the edges', () {
      // early: 0..100
      expect(t.stateAt(0, 100), PlaybackState.written);
      expect(t.stateAt(0, 99), PlaybackState.writing);
      expect(t.stateAt(1, 999), PlaybackState.unwritten);
      expect(t.stateAt(1, 1000), PlaybackState.writing);
      expect(t.stateAt(1, 1099), PlaybackState.writing);
      expect(t.stateAt(1, 1100), PlaybackState.written);
      expect(t.stateAt(2, 4999), PlaybackState.unwritten);
      expect(t.writing(1050), [1]);
      expect(t.writing(1100), isEmpty);
      expect(t.boundary(1050), 2);
      expect(t.boundary(999), 1);
      expect(t.boundary(-1), 0);
    });

    test('the points still to be written: offset + t(i) > p', () {
      expect(t.firstUnwrittenPoint(1, 1000), 1, reason: 't(0) = 0 is written');
      expect(t.firstUnwrittenPoint(1, 1045), 5);
      expect(t.firstUnwrittenPoint(1, 1050), 6);
      expect(t.firstUnwrittenPoint(1, 1100), 11, reason: 'all written');
      expect(t.firstUnwrittenPoint(1, 999), 0, reason: 'none written');
    });

    test('recent: p − W < offset ≤ p, both edges', () {
      expect(t.isRecent(1, 1000, 2000), isTrue, reason: 'offset = p');
      expect(t.isRecent(1, 2999, 2000), isTrue);
      expect(t.isRecent(1, 3000, 2000), isFalse, reason: 'offset = p − W');
      expect(t.isRecent(1, 999, 2000), isFalse, reason: 'not started');
      expect(t.recentRange(1050, 2000), (0, 2));
      expect(t.recentRange(3050, 2000), (2, 2), reason: 'empty');
      expect(t.recentRange(5000, 0), (3, 3), reason: 'W = 0 → nothing');
    });
  });

  group('rebuilds', () {
    test(
      'a content change rebuilds only the recording whose strokes changed',
      () {
        final a1 = _rec('a1', 'A', 0);
        final a2 = _rec('a2', 'A', 500);
        final b1 = _rec('b1', 'B', 0);
        final n1 = _rec('n1', null, null);
        final index = PlaybackIndex()..update(_content([a1, a2, b1, n1]));
        final ta = index.trackOf('A')!;
        final tb = index.trackOf('B')!;
        expect(index.buildsOf('A'), 1);
        expect(index.buildsOf('B'), 1);
        // the same content again, a new content with the same instances
        index.update(_content([a1, a2, b1, n1], revision: 2));
        expect(identical(index.trackOf('A'), ta), isTrue);
        expect(identical(index.trackOf('B'), tb), isTrue);
        // a stroke without a recording changes: nothing rebuilt
        index.update(
          _content([a1, a2, b1, _rec('n2', null, null)], revision: 3),
        );
        expect(identical(index.trackOf('A'), ta), isTrue);
        expect(identical(index.trackOf('B'), tb), isTrue);
        // A gets a stroke: A only
        final a3 = _rec('a3', 'A', 900);
        index.update(_content([a1, a2, a3, b1], revision: 4));
        expect(_ids(index.trackOf('A')!), ['a1', 'a2', 'a3']);
        expect(identical(index.trackOf('B'), tb), isTrue);
        expect(index.buildsOf('A'), 2);
        expect(index.buildsOf('B'), 1);
        // a stroke of B is replaced (same id, new instance): B only
        index.update(
          _content([
            a1,
            a2,
            a3,
            b1.copyWith(recordingOffsetMs: 10),
          ], revision: 5),
        );
        expect(index.trackOf('B')!.entries.single.offsetMs, 10);
        expect(index.buildsOf('A'), 2);
        expect(index.buildsOf('B'), 2);
        // B's last stroke goes: no track
        index.update(_content([a1, a2, a3], revision: 6));
        expect(index.trackOf('B'), isNull);
        expect(index.buildsOf('A'), 2);
      },
    );

    test('a track is built on first use only', () {
      final index = PlaybackIndex()
        ..update(_content([_rec('a', 'A', 0), _rec('b', 'B', 0)]));
      expect(index.buildsOf('A'), 0);
      index.trackOf('A');
      index.trackOf('A');
      expect(index.buildsOf('A'), 1);
      expect(index.buildsOf('B'), 0);
    });
  });
}
