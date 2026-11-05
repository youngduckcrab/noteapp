// E-16: PresetOrdering.reorderSubset (04-editor 6.10) — the bar shows a
// subset (pinned + group filter); moving one chip inside it gives the FULL
// active id order for core.PenPresetRepository.reorderPresets. Also the pure
// helpers next to it (presetsInOrder, effectiveGroupFilter) and the order
// CORE keeps after reorderPresets(full order) on the fake store.
import 'package:feature_editor/src/state/preset_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

core.PenPreset _preset(String id, {String? group, bool pinned = true}) =>
    core.PenPreset(
      id: id,
      ownerId: 'local',
      name: id,
      style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
      group: group,
      pinned: pinned,
      sortKey: id,
      createdAt: 0,
      updatedAt: 0,
    );

final _all = [
  for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) _preset(id),
];

List<String> _move(List<String> subset, int from, int to) =>
    PresetOrdering.reorderSubset(
      all: _all,
      subsetIds: subset,
      oldIndex: from,
      newIndex: to,
    );

void main() {
  group('reorderSubset', () {
    test('moving inside an interleaved subset rewrites only its slots', () {
      // Subset b, d, f (a, c, e are unpinned or in another group).
      expect(_move(['b', 'd', 'f'], 0, 2), ['a', 'd', 'c', 'f', 'e', 'b']);
      expect(_move(['b', 'd', 'f'], 2, 0), ['a', 'f', 'c', 'b', 'e', 'd']);
      expect(_move(['b', 'd', 'f'], 1, 0), ['a', 'd', 'c', 'b', 'e', 'f']);
      expect(_move(['b', 'd', 'f'], 0, 1), ['a', 'd', 'c', 'b', 'e', 'f']);
    });

    test('newIndex is the final index after removal (onReorderItem)', () {
      // a → index 3 of the list without it: b c d a e f.
      expect(_move(['a', 'b', 'c', 'd', 'e', 'f'], 0, 3), [
        'b',
        'c',
        'd',
        'a',
        'e',
        'f',
      ]);
      // f → front.
      expect(_move(['a', 'b', 'c', 'd', 'e', 'f'], 5, 0), [
        'f',
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);
    });

    test('a subset at the end or the start of the list', () {
      expect(_move(['e', 'f'], 0, 1), ['a', 'b', 'c', 'd', 'f', 'e']);
      expect(_move(['a', 'b'], 1, 0), ['b', 'a', 'c', 'd', 'e', 'f']);
    });

    test('the same index gives the CORE order unchanged', () {
      expect(_move(['b', 'd', 'f'], 1, 1), ['a', 'b', 'c', 'd', 'e', 'f']);
      expect(_move(['c'], 0, 0), ['a', 'b', 'c', 'd', 'e', 'f']);
    });

    test('the result holds every active id exactly once', () {
      for (var from = 0; from < 3; from++) {
        for (var to = 0; to < 3; to++) {
          final order = _move(['a', 'c', 'e'], from, to);
          expect(order.toSet(), {'a', 'b', 'c', 'd', 'e', 'f'});
          expect(order, hasLength(6));
          // Non-members never move.
          expect([order[1], order[3], order[5]], ['b', 'd', 'f']);
        }
      }
    });

    test('subset ids that are not active are dropped', () {
      // x was deleted meanwhile: [b, x, d] → move b to the end → x, d, b →
      // d, b in the slots of the members.
      expect(_move(['b', 'x', 'd'], 0, 2), ['a', 'd', 'c', 'b', 'e', 'f']);
    });

    test('indexes outside the subset throw a RangeError', () {
      expect(() => _move(['b', 'd'], 2, 0), throwsRangeError);
      expect(() => _move(['b', 'd'], 0, 2), throwsRangeError);
      expect(() => _move(['b', 'd'], -1, 0), throwsRangeError);
      expect(() => _move(const [], 0, 0), throwsRangeError);
    });

    test('the result is unmodifiable', () {
      expect(() => _move(['b', 'd'], 0, 1).add('z'), throwsUnsupportedError);
    });

    test(
      'CORE keeps the full order after reorderPresets (fake store)',
      () async {
        final store = createFakeNoteStore();
        addTearDown(store.close);
        final repo = store.penPresets;
        var all = await repo.getPresets();
        expect(all.map((p) => p.name), ['볼펜', '만년필', '형광펜', '연필', '마커']);
        // Unpin 만년필 and 연필: the bar shows 볼펜, 형광펜, 마커.
        for (final p in [all[1], all[3]]) {
          await repo.updatePreset(p.copyWith(pinned: false));
        }
        all = await repo.getPresets();
        final subset = [
          for (final p in all)
            if (p.pinned) p.id,
        ];
        // 마커 (2) → front of the bar.
        final order = PresetOrdering.reorderSubset(
          all: all,
          subsetIds: subset,
          oldIndex: 2,
          newIndex: 0,
        );
        await repo.reorderPresets(order);
        final after = await repo.getPresets();
        expect(after.map((p) => p.id), order);
        expect(after.map((p) => p.name), ['마커', '만년필', '볼펜', '연필', '형광펜']);
      },
    );
  });

  group('presetsInOrder', () {
    test('null order keeps the list', () {
      expect(presetsInOrder(_all, null), same(_all));
    });

    test('listed ids first in that order, the others after, kept in order', () {
      final order = presetsInOrder(_all, ['e', 'a', 'c']);
      expect(order.map((p) => p.id), ['e', 'a', 'c', 'b', 'd', 'f']);
    });

    test('ids of the order that are not in the list are ignored', () {
      final order = presetsInOrder(_all.sublist(0, 3), ['z', 'c', 'b', 'a']);
      expect(order.map((p) => p.id), ['c', 'b', 'a']);
    });
  });

  group('effectiveGroupFilter', () {
    final grouped = [
      _preset('a', group: '수업용'),
      _preset('b'),
      _preset('c', group: '필기', pinned: false),
    ];

    test('null stays null', () {
      expect(effectiveGroupFilter(grouped, null), isNull);
    });

    test('a group some preset has (pinned or not) applies', () {
      expect(effectiveGroupFilter(grouped, '수업용'), '수업용');
      expect(effectiveGroupFilter(grouped, '필기'), '필기');
    });

    test('a group no preset has any more is all groups', () {
      expect(effectiveGroupFilter(grouped, '없는 그룹'), isNull);
      expect(effectiveGroupFilter(const [], '수업용'), isNull);
    });
  });
}
