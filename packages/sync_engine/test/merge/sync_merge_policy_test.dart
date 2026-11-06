import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/merge/field_merge.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/entity_fixtures.dart';

Hlc h(int t, [String node = kNodeA]) => Hlc(kT0 + t, 0, node);

/// The note fixture as CORE holds it: [set] applied, versions base h([base])
/// plus [fv], entity.version == versions.max.
VersionedEntity note({
  Map<String, Object?> set = const {},
  int base = 0,
  Map<String, Hlc> fv = const {},
  String node = kNodeA,
}) {
  final versions = EntityFieldVersions(h(base, node), fv);
  final json = {
    ...fixtureJson(EntityKind.note),
    ...set,
    'version': versions.max.toString(),
  };
  return VersionedEntity(EntityJson.decode(EntityKind.note, json), versions);
}

Map<String, Object?> jsonOf(VersionedEntity v) => v.entity.toJson();

const DeepCollectionEquality eq = DeepCollectionEquality();

/// What CORE does with a decision (6.10.3, simplified): the new local row.
VersionedEntity? applied(
  MergeDecision d,
  VersionedEntity? local,
  VersionedEntity remote,
) => switch (d) {
  KeepLocal() => local,
  TakeRemote() => remote,
  WriteMerged(:final entity, :final versions) => VersionedEntity(
    entity,
    versions,
  ),
};

void main() {
  test('is a RemoteMergePolicy', () {
    const RemoteMergePolicy policy = SyncMergePolicy.decide;
    expect(policy(null, note(), null), isA<TakeRemote>());
  });

  group('no local row', () {
    test('no pending entry: TakeRemote(dropPendingLocal: true)', () {
      final d = SyncMergePolicy.decide(null, note(), null);
      expect(d, isA<TakeRemote>());
      expect((d as TakeRemote).dropPendingLocal, isTrue);
    });

    test('unsent local purge ({*}): KeepLocal (SYNC-2-2)', () {
      expect(
        SyncMergePolicy.decide(null, note(), {kAllFields}),
        isA<KeepLocal>(),
      );
    });

    test('any pending entry without a row keeps the local state', () {
      expect(SyncMergePolicy.decide(null, note(), {'title'}), isA<KeepLocal>());
    });
  });

  group('local row', () {
    test('echo of the same snapshot: KeepLocal', () {
      final v = note(fv: {'title': h(2)});
      expect(SyncMergePolicy.decide(v, v, {'title'}), isA<KeepLocal>());
      expect(
        SyncMergePolicy.decide(v, note(fv: {'title': h(2)}), null),
        isA<KeepLocal>(),
      );
    });

    test('stale remote (every unit older or equal): KeepLocal', () {
      final local = note(set: {'title': 'new'}, fv: {'title': h(5)});
      final remote = note(set: {'title': 'old'}, fv: {'title': h(3)});
      expect(
        SyncMergePolicy.decide(local, remote, {'title'}),
        isA<KeepLocal>(),
      );
    });

    test('remote newer everywhere it differs: TakeRemote, pending dropped', () {
      final local = note(set: {'title': 'mine'}, fv: {'title': h(2)});
      final remote = note(
        set: {'title': 'theirs', 'isFavorite': false},
        fv: {'title': h(4, kNodeB), 'isFavorite': h(4, kNodeB)},
      );
      final d = SyncMergePolicy.decide(local, remote, {'title'});
      expect(d, isA<TakeRemote>());
      expect((d as TakeRemote).dropPendingLocal, isTrue);
    });

    test('each side won a unit: WriteMerged with version == versions.max', () {
      final local = note(set: {'title': 'mine'}, fv: {'title': h(5)});
      final remote = note(
        set: {'folderId': 'f9', 'sortKey': 'z0'},
        fv: {'folderId': h(7, kNodeB)},
      );
      final d = SyncMergePolicy.decide(local, remote, {'title'});
      expect(d, isA<WriteMerged>());
      final w = d as WriteMerged;
      expect(w.entity.version, w.versions.max);
      expect(w.versions.max, h(7, kNodeB));
      final json = w.entity.toJson();
      expect(json['title'], 'mine');
      expect(json['folderId'], 'f9');
      expect(json['sortKey'], 'z0');
      expect(w.fieldsToUpload, {'title'});
      // The decision is the FieldMerge result.
      final merged = FieldMerge.mergeRecords(
        UpsertRecord.fromVersioned(local),
        UpsertRecord.fromVersioned(remote),
      );
      expect(eq.equals(json, merged.doc.json), isTrue);
      expect(w.versions, merged.versions);
    });

    test('fieldsToUpload = pending ∩ fields of the units local won', () {
      final local = note(
        set: {
          'title': 'mine',
          'tags': ['x'],
          'isFavorite': false,
        },
        fv: {'title': h(5), 'tags': h(5), 'isFavorite': h(1)},
      );
      final remote = note(
        set: {
          'isFavorite': true,
          'cover': {'type': 'color', 'color': 7},
        },
        fv: {'isFavorite': h(3, kNodeB), 'cover': h(3, kNodeB)},
      );
      // isFavorite is pending but lost to the server's newer value.
      final d = SyncMergePolicy.decide(local, remote, {'title', 'isFavorite'});
      expect((d as WriteMerged).fieldsToUpload, {'title'});
      // No pending entry: nothing to upload.
      final none = SyncMergePolicy.decide(local, remote, null);
      expect((none as WriteMerged).fieldsToUpload, isEmpty);
    });

    test("pending '*' expands to every non-meta key of the local row", () {
      final local = note(
        set: {'title': 'mine', 'folderId': 'fL', 'sortKey': 'a8'},
        base: 5,
      );
      final remote = note(
        set: {'isFavorite': false},
        fv: {'isFavorite': h(9, kNodeB)},
      );
      final d = SyncMergePolicy.decide(local, remote, {kAllFields});
      final upload = (d as WriteMerged).fieldsToUpload;
      expect(upload, contains('title'));
      expect(upload, containsAll(['folderId', 'sortKey']));
      expect(upload, isNot(contains('isFavorite')));
      expect(upload.any(FieldUnits.metaKeys.contains), isFalse);
      expect(upload, isNot(contains(kAllFields)));
    });

    test('(2nd round, S2-8) one id created on two devices (hw_<pageId>, each '
        'with its own createdAt): the winning snapshot brings its createdAt, so '
        'KeepLocal / TakeRemote leave both sides with the merged row', () {
      VersionedEntity hw({
        required int createdAt,
        required String text,
        required Hlc at,
      }) {
        final versions = EntityFieldVersions(at, const {});
        final fixture = handwritingFixture().toJson();
        final json = {
          ...fixture,
          'createdAt': createdAt,
          'updatedAt': createdAt,
          'lines': [
            {...(fixture['lines']! as List).first as Map, 'text': text},
          ],
          'version': versions.max.toString(),
        };
        return VersionedEntity(
          EntityJson.decode(EntityKind.handwriting, json),
          versions,
        );
      }

      final early = hw(createdAt: kT0 + 1, text: 'early', at: h(1));
      final late = hw(createdAt: kT0 + 9, text: 'late', at: h(9, kNodeB));
      final merged = FieldMerge.mergeRecords(
        UpsertRecord.fromVersioned(early),
        UpsertRecord.fromVersioned(late),
      );
      expect(merged.doc.json['createdAt'], kT0 + 9);
      // The later device receives the earlier create: it keeps its row.
      final onLate = SyncMergePolicy.decide(late, early, {kAllFields});
      expect(onLate, isA<KeepLocal>());
      expect(eq.equals(jsonOf(late), merged.doc.json), isTrue);
      // The earlier device receives the later write: it takes it whole.
      final onEarly = SyncMergePolicy.decide(early, late, {kAllFields});
      expect(onEarly, isA<TakeRemote>());
      expect(
        applied(onEarly, early, late)!.entity.toJson()['createdAt'],
        kT0 + 9,
      );
    });

    test('same input twice gives the same decision (pure)', () {
      final local = note(set: {'title': 'mine'}, fv: {'title': h(5)});
      final remote = note(
        set: {
          'tags': ['z'],
        },
        fv: {'tags': h(6, kNodeB)},
      );
      final d1 =
          SyncMergePolicy.decide(local, remote, {'title'}) as WriteMerged;
      final d2 =
          SyncMergePolicy.decide(local, remote, {'title'}) as WriteMerged;
      expect(d1.entity, d2.entity);
      expect(d1.versions, d2.versions);
      expect(d1.fieldsToUpload, d2.fieldsToUpload);
    });
  });

  test('6.3.4 counterexample converges with field versions', () {
    // Both devices have note N at t0. A (offline) renames it at t1, B (offline)
    // moves it at t2 > t1. B uploads first.
    final start = note();
    final a = note(set: {'title': 'A title'}, fv: {'title': h(1)});
    final b = note(set: {'folderId': 'f2'}, fv: {'folderId': h(2, kNodeB)});
    expect(jsonOf(start)['title'], isNot('A title'));

    // A receives B's record while its rename is pending.
    final dA = SyncMergePolicy.decide(a, b, {'title'});
    expect(dA, isA<WriteMerged>());
    expect((dA as WriteMerged).fieldsToUpload, {'title'});
    final aNow = applied(dA, a, b)!;
    expect(jsonOf(aNow)['title'], 'A title');
    expect(jsonOf(aNow)['folderId'], 'f2');

    // A uploads its merged snapshot; B (nothing pending) receives it. An
    // entity-version rule (remote t1 < local t2) would reject the title here.
    final dB = SyncMergePolicy.decide(b, aNow, null);
    expect(dB, isA<TakeRemote>());
    final bNow = applied(dB, b, aNow)!;

    expect(eq.equals(jsonOf(aNow), jsonOf(bNow)), isTrue);
    expect(aNow.versions, bNow.versions);
    // A's echo of the same state changes nothing.
    expect(SyncMergePolicy.decide(aNow, bNow, null), isA<KeepLocal>());
  });
}
