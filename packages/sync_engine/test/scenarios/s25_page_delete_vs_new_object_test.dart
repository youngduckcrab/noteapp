// S25 (07-sync 6.7.1, 6.2.6): page P deleted on A vs a new image object on P from B,
// offline. (a1) B connects first, (a2) A connects first: in both orders P comes back
// (PageRestored once) and the object shows. (b) B only writes a new handwriting result
// for P: handwriting is no evidence — P stays deleted, the result row stays.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

Page pageOn(TestDevice d, String id) => entityOn<Page>(d, EntityKind.page, id)!;

/// PageRestored notices of every device in [devices].
({List<PageRestored> restored, void Function() cancel}) listenRestored(
  List<TestDevice> devices,
) {
  final restored = <PageRestored>[];
  final subs = [
    for (final d in devices)
      d.engine.notices.listen((n) {
        if (n is PageRestored) restored.add(n);
      }),
  ];
  return (
    restored: restored,
    cancel: () {
      for (final s in subs) {
        unawaited(s.cancel());
      }
    },
  );
}

void delete({required bool bFirst}) {
  syncScenario(
    'S25 (${bFirst ? 'a1' : 'a2'}) delete on A vs new image object on B, '
    '${bFirst ? 'B' : 'A'} connects first: P restored once, object shown',
    (h) {
      final a = h.device('A');
      final b = h.device('B');
      final notices = listenRestored([a, b]);
      final note = a.createNote('S25', pages: 2);
      h.settle();
      final page = a.pageIdsOf(note).last;
      a.goOffline();
      b.goOffline();
      a.deletePage(page);
      final asset = h.run(
        b.putAsset(
          Uint8List.fromList(utf8.encode('png of S25')),
          type: AssetType.image,
          mimeType: 'image/png',
        ),
      );
      final object = b.addObject(page, type: 'image', assetId: asset);
      h.elapse(const Duration(seconds: 1));
      final (first, second) = bFirst ? (b, a) : (a, b);
      first.goOnline();
      h.settle();
      second.goOnline();
      h.settle();

      for (final d in [a, b]) {
        expect(pageOn(d, page).isDeleted, isFalse, reason: d.name);
        expect(d.pageIdsOf(note), contains(page), reason: d.name);
        expect(
          [for (final o in d.activeObjectsOf(page)) o.json['id']],
          [object],
          reason: d.name,
        );
      }
      expect(notices.restored.map((n) => n.pageId), [page]);
      h.checkConverged([a, b]);
      notices.cancel();
    },
  );
}

void main() {
  delete(bFirst: true);
  delete(bFirst: false);

  syncScenario('S25 (b) delete on A vs a new handwriting result only on B: P '
      'stays deleted, the result row stays', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final notices = listenRestored([a, b]);
    final note = a.createNote('S25b', pages: 2);
    final page = a.pageIdsOf(note).last;
    a.addStroke(page);
    h.settle();
    b.goOffline();
    a.deletePage(page);
    h.settle();
    b.putHandwriting(page, ['미분']);
    h.elapse(const Duration(seconds: 1));
    b.goOnline();
    h.settle();

    final id = HandwritingText.idFor(page);
    for (final d in [a, b]) {
      expect(pageOn(d, page).isDeleted, isTrue, reason: d.name);
      expect(d.pageIdsOf(note), isNot(contains(page)), reason: d.name);
      final row = d.doc(EntityKind.handwriting, id);
      expect(row, isNotNull, reason: d.name);
      expect(row!.json['deletedAt'], isNull, reason: d.name);
      expect(
        [for (final line in row.json['lines']! as List) (line as Map)['text']],
        ['미분'],
        reason: d.name,
      );
    }
    expect(notices.restored, isEmpty);
    h.checkConverged([a, b]);
    notices.cancel();
  });
}
