// T11: PurgedSet (6.7.4, 6.6.6) — stored purges spread over sync.purged.0 … 4 by the first
// sha-256 byte, at most 2,000 per key (the newest), entries older than 400 days dropped when
// their key is rewritten, each value under 256 KiB; plus the in-memory view of unsent local
// purges (outbox op purge entries) that is never written to meta and moves to the stored set
// once the purge is committed.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/engine/meta_keys.dart';
import 'package:sync_engine/src/merge/purged_set.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/local_writes.dart';
import '../support/merge_rig.dart';

int nowOf(MergeRig r) => r.a.clock.now().millisecondsSinceEpoch;

PurgeRecord purgeAt(EntityRef ref, int millis, [int counter = 0]) =>
    PurgeRecord(ref, Hlc(millis, counter, kNodeB));

/// Note refs whose stored key is [index].
List<EntityRef> refsOfKey(int index, int count) {
  final out = <EntityRef>[];
  for (var i = 0; out.length < count; i++) {
    final ref = noteRef('n$i');
    if (PurgedSet.keyIndexOf(ref) == index) out.add(ref);
  }
  return out;
}

void main() {
  test('refs spread over the five keys by the first sha-256 byte; only the '
      'changed keys are written', () {
    withMergeRig((r) {
      final set = PurgedSet(sync: r.a.sync);
      r.run(set.load());
      final refs = [for (var i = 0; i < 100; i++) noteRef('n$i')];
      final used = {for (final ref in refs) PurgedSet.keyIndexOf(ref)};
      expect(used, {0, 1, 2, 3, 4});
      expect(PurgedSet.refText(noteRef('n1')), 'note:n1');
      final now = nowOf(r);
      final one = refsOfKey(3, 1).single;
      final updates = set.updatesFor([purgeAt(one, now)], nowMillis: now);
      expect(updates.keys, [MetaKeys.purged[3]]);
      expect(set.contains(one), isFalse, reason: 'memory waits for absorb');
      r.run(r.a.sync.writeMeta(updates));
      set.absorb(updates);
      expect(set.isStored(one), isTrue);
      // The same purge again (or an older one) changes nothing.
      expect(set.updatesFor([purgeAt(one, now - 5)], nowMillis: now), isEmpty);
      // load() reads it back.
      final again = PurgedSet(sync: r.a.sync);
      r.run(again.load());
      expect(again.isStored(one), isTrue);
      expect(again.storedCount, 1);
    });
  });

  test(
    'at most 2,000 entries per key (the newest), each value under 256 KiB',
    () {
      withMergeRig((r) {
        final set = PurgedSet(sync: r.a.sync);
        final now = nowOf(r);
        final refs = refsOfKey(0, 2100);
        final updates = set.updatesFor([
          for (final (i, ref) in refs.indexed) purgeAt(ref, now - 100000 + i),
        ], nowMillis: now);
        final text = updates[MetaKeys.purged[0]]!;
        expect(utf8.encode(text).length, lessThan(256 * 1024));
        final stored = (jsonDecode(text) as Map<String, Object?>).keys.toSet();
        expect(stored, hasLength(2000));
        expect(stored.contains(PurgedSet.refText(refs.first)), isFalse);
        expect(stored.contains(PurgedSet.refText(refs.last)), isTrue);
        set.absorb(updates);
        expect(set.storedCount, 2000);
      });
    },
  );

  test(
    'entries older than 400 days are dropped when their key is rewritten',
    () {
      withMergeRig((r) {
        final set = PurgedSet(sync: r.a.sync);
        final now = nowOf(r);
        const day = 24 * 60 * 60 * 1000;
        final [old, kept, fresh] = refsOfKey(2, 3);
        set.absorb(
          set.updatesFor([
            purgeAt(old, now - 401 * day),
            purgeAt(kept, now - 399 * day),
          ], nowMillis: now - 2 * day),
        );
        expect(set.isStored(old), isTrue);
        set.absorb(set.updatesFor([purgeAt(fresh, now)], nowMillis: now));
        expect(set.isStored(old), isFalse);
        expect(set.isStored(kept), isTrue);
        expect(set.isStored(fresh), isTrue);
      });
    },
  );

  test('unsent local purges: in the view (contains) but never in meta; once '
      'committed they are stored', () {
    withMergeRig((r) {
      r.write(r.a, [noteWrite('n'), pageWrite('p', 'n')]);
      r.ackAll(r.a);
      r.a.localPurge(noteRef('n'), group: [noteRef('n')]);
      final set = PurgedSet(sync: r.a.sync, localChanges: r.a.localChanges);
      r.run(set.load());
      expect(set.local, {noteRef('n')});
      expect(set.contains(noteRef('n')), isTrue);
      expect(set.isStored(noteRef('n')), isFalse);
      expect(r.a.meta.keys.where((k) => k.startsWith('sync.purged.')), isEmpty);
      // Sent: the upload pipeline reports the committed purge, the outbox is acked.
      final entry = r.a.outbox.single;
      r.run(
        set.addCommitted([
          PurgeRecord(entry.ref, entry.hlc),
        ], nowMillis: nowOf(r)),
      );
      r.ackAll(r.a);
      expect(set.isStored(noteRef('n')), isTrue);
      expect(
        r.a.meta[MetaKeys.purged[PurgedSet.keyIndexOf(noteRef('n'))]],
        contains('note:n'),
      );
      r.run(set.refreshLocal());
      expect(set.local, isEmpty);
      expect(set.contains(noteRef('n')), isTrue);
      unawaited(set.dispose());
    });
  });

  test('a local change marks the view stale; refreshIfStale reads the outbox '
      'again (to the end)', () {
    withMergeRig((r) {
      final set = PurgedSet(
        sync: r.a.sync,
        localChanges: r.a.localChanges,
        outboxPageSize: 2,
      );
      r.run(set.load());
      expect(set.isStale, isFalse);
      for (var i = 0; i < 5; i++) {
        r.write(r.a, [noteWrite('x$i')]);
      }
      r.write(r.a, [noteWrite('n')]);
      r.async.flushMicrotasks();
      expect(set.isStale, isTrue);
      r.a.localPurge(noteRef('n'), group: [noteRef('n')]);
      r.async.flushMicrotasks();
      r.run(set.refreshIfStale());
      expect(set.isStale, isFalse);
      expect(set.local, {noteRef('n')});
      set.markStale();
      expect(set.isStale, isTrue);
      unawaited(set.dispose());
    });
  });

  test('malformed stored values are dropped while reading', () {
    withMergeRig((r) {
      r.run(
        r.a.sync.writeMeta({
          MetaKeys.purged[0]: 'not json',
          MetaKeys.purged[1]: '{"note:a": "bad hlc", "note:b": 3}',
          MetaKeys.purged[2]: MetaKeys.cleared,
        }),
      );
      final set = PurgedSet(sync: r.a.sync);
      r.run(set.load());
      expect(set.storedCount, 0);
    });
  });
}
