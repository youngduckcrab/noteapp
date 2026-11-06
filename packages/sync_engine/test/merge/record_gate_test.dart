import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/merge/record_gate.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/entity_fixtures.dart';

const int hour = 3600 * 1000;
const int day = 24 * hour;

/// A record of [kind] whose versions are all at [millis].
UpsertRecord rec(
  EntityKind kind, {
  int millis = kT0,
  Map<String, Object?> set = const {},
  String? id,
  bool fixVersion = true,
}) {
  final v = Hlc(millis, 0, kNodeB);
  final json = {...fixtureJson(kind, id: id), ...set};
  if (fixVersion) json['version'] = v.toString();
  return UpsertRecord(
    SyncDoc(kind: kind, id: fixtureId(json), json: json),
    EntityFieldVersions(v),
  );
}

GateVerdict check(
  SyncRecord r, {
  String scope = 'lib',
  int? reference,
  String uid = 'local',
  Set<String> purgedNotes = const {},
  Set<String> purgedFolders = const {},
  String? elementNoteId,
}) => RecordGate.check(
  r,
  scope: scope,
  referenceMillis: reference ?? kT0,
  uid: uid,
  isPurged: (ref) => switch (ref.kind) {
    EntityKind.note => purgedNotes.contains(ref.id),
    EntityKind.folder => purgedFolders.contains(ref.id),
    _ => false,
  },
  elementNoteId: elementNoteId,
);

Matcher skipped(SyncIssueCode code) =>
    isA<GateSkip>().having((s) => s.code, 'code', code);

void main() {
  test('accepts a valid record of every kind', () {
    for (final kind in EntityKind.values) {
      expect(check(rec(kind)), isA<GateAccept>(), reason: kind.name);
    }
    expect(
      check(
        PurgeRecord(
          const EntityRef(EntityKind.note, 'n1'),
          Hlc(kT0, 0, kNodeB),
        ),
      ),
      isA<GateAccept>(),
    );
  });

  group('malformed → skip (malformedRemoteData)', () {
    test('invalid entity id', () {
      final r = rec(EntityKind.note, id: 'bad id!');
      expect(check(r), skipped(SyncIssueCode.malformedRemoteData));
      // Setting keys are not entity ids (dots allowed).
      expect(
        check(rec(EntityKind.setting, id: 'editor.theme')),
        isA<GateAccept>(),
      );
    });

    test('version missing, malformed or != fv.max', () {
      // The fixture's version (node A) differs from fv.max (node B).
      final otherVersion = rec(EntityKind.note, fixVersion: false);
      expect(check(otherVersion), skipped(SyncIssueCode.malformedRemoteData));
      final withoutKey = UpsertRecord(
        SyncDoc(
          kind: EntityKind.note,
          id: 'n1',
          json: {...fixtureJson(EntityKind.note)}..remove('version'),
        ),
        EntityFieldVersions(Hlc(kT0, 0, kNodeA)),
      );
      expect(check(withoutKey), skipped(SyncIssueCode.malformedRemoteData));
      final garbage = rec(
        EntityKind.note,
        set: {'version': 'x'},
        fixVersion: false,
      );
      expect(check(garbage), skipped(SyncIssueCode.malformedRemoteData));
    });

    test('CORE cannot decode the entity', () {
      final r = rec(EntityKind.note, set: {'tags': 'not-a-list'});
      expect(check(r), skipped(SyncIssueCode.malformedRemoteData));
    });

    test('purge of a kind other than folder / note', () {
      final p = PurgeRecord(
        const EntityRef(EntityKind.page, 'p1'),
        Hlc(kT0, 0, kNodeB),
      );
      expect(check(p), skipped(SyncIssueCode.malformedRemoteData));
      final f = PurgeRecord(
        const EntityRef(EntityKind.folder, 'f1'),
        Hlc(kT0, 0, kNodeB),
      );
      expect(check(f), isA<GateAccept>());
    });
  });

  test('ownerId of another user → skip (foreignOwnerData)', () {
    for (final kind in [
      EntityKind.folder,
      EntityKind.note,
      EntityKind.penPreset,
      EntityKind.asset,
    ]) {
      expect(
        check(rec(kind), uid: 'user-2'),
        skipped(SyncIssueCode.foreignOwnerData),
        reason: kind.name,
      );
      expect(
        check(rec(kind, set: {'ownerId': 'user-2'}), uid: 'user-2'),
        isA<GateAccept>(),
      );
    }
    // Kinds without ownerId are not checked.
    expect(check(rec(EntityKind.stroke), uid: 'user-2'), isA<GateAccept>());
  });

  group('permanent deletion view → drop', () {
    test('upserts of a purged folder or note', () {
      expect(check(rec(EntityKind.note), purgedNotes: {'n1'}), isA<GateDrop>());
      expect(
        check(rec(EntityKind.folder), purgedFolders: {'f1'}),
        isA<GateDrop>(),
      );
      expect(
        check(rec(EntityKind.note), purgedNotes: {'n2'}),
        isA<GateAccept>(),
      );
    });

    test(
      'page and recording of a purged note (by noteId), other notes pass',
      () {
        for (final kind in [EntityKind.page, EntityKind.recording]) {
          expect(
            check(rec(kind), purgedNotes: {'n1'}),
            isA<GateDrop>(),
            reason: kind.name,
          );
          expect(
            check(rec(kind, set: {'noteId': 'n2'}), purgedNotes: {'n1'}),
            isA<GateAccept>(),
            reason: kind.name,
          );
        }
      },
    );

    test('stroke by chunk scope; lib scope uses the resolved note', () {
      final s = rec(EntityKind.stroke);
      expect(check(s, scope: 'n1', purgedNotes: {'n1'}), isA<GateDrop>());
      expect(check(s, scope: 'n2', purgedNotes: {'n1'}), isA<GateAccept>());
      expect(
        check(s, purgedNotes: {'n1'}),
        isA<GateAccept>(),
        reason: 'unknown page',
      );
      expect(
        check(s, purgedNotes: {'n1'}, elementNoteId: 'n1'),
        isA<GateDrop>(),
      );
      expect(
        check(s, purgedNotes: {'n1'}, elementNoteId: 'n2'),
        isA<GateAccept>(),
      );
    });

    test('(2nd round, 6.2.4) a handwriting result by its noteId, whatever the '
        'chunk scope; other notes pass', () {
      final hw = rec(EntityKind.handwriting);
      expect(hw.doc.json['noteId'], 'n1');
      for (final scope in ['lib', 'n1', 'n2']) {
        expect(
          check(hw, scope: scope, purgedNotes: {'n1'}),
          isA<GateDrop>().having(
            (d) => d.reason,
            'reason',
            contains('of permanently deleted note n1'),
          ),
          reason: scope,
        );
      }
      expect(
        check(rec(EntityKind.handwriting, set: {'noteId': 'n2'}), scope: 'n1'),
        isA<GateAccept>(),
      );
      expect(
        check(
          rec(EntityKind.handwriting, set: {'noteId': 'n2'}),
          purgedNotes: {'n1'},
        ),
        isA<GateAccept>(),
      );
    });

    test('(2nd round, 6.2.4) a page object (every type, an unknown one too) by '
        'chunk scope; lib scope uses the note found through its page', () {
      for (final type in ['shape', 'text', 'image', 'math', 'sticker']) {
        final json = objectFixture(type).toJson();
        final o = UpsertRecord(
          SyncDoc(
            kind: EntityKind.pageObject,
            id: json['id']! as String,
            json: json,
          ),
          EntityFieldVersions(Hlc.parse(json['version']! as String)),
        );
        expect(
          check(o, scope: 'n1', purgedNotes: {'n1'}),
          isA<GateDrop>(),
          reason: type,
        );
        expect(
          check(o, scope: 'n2', purgedNotes: {'n1'}),
          isA<GateAccept>(),
          reason: type,
        );
        expect(
          check(o, purgedNotes: {'n1'}),
          isA<GateAccept>(),
          reason: '$type: lib scope, unknown page (kept as an orphan)',
        );
        expect(
          check(o, purgedNotes: {'n1'}, elementNoteId: 'n1'),
          isA<GateDrop>(),
          reason: type,
        );
        expect(
          check(o, purgedNotes: {'n1'}, elementNoteId: 'n2'),
          isA<GateAccept>(),
          reason: type,
        );
      }
    });

    test('(2nd round) page objects and handwriting results have no owner: '
        'another uid passes', () {
      for (final kind in [EntityKind.pageObject, EntityKind.handwriting]) {
        expect(
          check(rec(kind), uid: 'user-9'),
          isA<GateAccept>(),
          reason: '$kind',
        );
      }
    });

    test('purge records of a purged note still pass', () {
      final p = PurgeRecord(
        const EntityRef(EntityKind.note, 'n1'),
        Hlc(kT0, 0, kNodeB),
      );
      expect(check(p, purgedNotes: {'n1'}), isA<GateAccept>());
    });

    test('drop comes before hold', () {
      expect(
        check(rec(EntityKind.note, millis: kT0 + 3 * day), purgedNotes: {'n1'}),
        isA<GateDrop>(),
      );
    });
  });

  group('K1 hold at g + 24 h (contract 7.2.10 v1.1)', () {
    const serverT = kT0;
    final serverTime = ServerCursor(serverT * 1000);

    test('receiving clock fast: g = serverTime', () {
      final g = RecordGate.referenceMillis(serverTime, serverT + 3 * hour);
      expect(g, serverT);
      expect(
        check(rec(EntityKind.note, millis: g + day), reference: g),
        isA<GateAccept>(),
      );
      final held = check(
        rec(EntityKind.note, millis: g + day + 1),
        reference: g,
      );
      expect(held, isA<GateHold>());
      expect((held as GateHold).releaseAtMillis, g + 1);
    });

    test('receiving clock slow: g = wall', () {
      final wall = serverT - 2 * hour;
      final g = RecordGate.referenceMillis(serverTime, wall);
      expect(g, wall);
      expect(
        check(rec(EntityKind.note, millis: wall + day), reference: g),
        isA<GateAccept>(),
      );
      // Within serverTime + 24 h but beyond wall + 24 h: held (S14b(d)).
      final r = rec(EntityKind.note, millis: serverT + 23 * hour);
      final held = check(r, reference: g);
      expect(held, isA<GateHold>());
      expect((held as GateHold).releaseAtMillis, serverT - hour);
      expect(
        check(rec(EntityKind.note, millis: wall + day + 1), reference: g),
        isA<GateHold>(),
      );
    });

    test('the record max over every field counts', () {
      final v0 = Hlc(kT0, 0, kNodeB), v1 = Hlc(kT0 + day + 5, 0, kNodeB);
      final json = {...fixtureJson(EntityKind.note), 'version': v1.toString()};
      final r = UpsertRecord(
        SyncDoc(kind: EntityKind.note, id: 'n1', json: json),
        EntityFieldVersions(v0, {'title': v1}),
      );
      expect(check(r, reference: kT0), isA<GateHold>());
    });

    test('purge records are never held', () {
      final p = PurgeRecord(
        const EntityRef(EntityKind.note, 'n1'),
        Hlc(kT0 + 3 * day, 0, kNodeB),
      );
      expect(check(p), isA<GateAccept>());
    });

    test(
      'release: min(serverNow, wall) == releaseAt releases, − 1 ms keeps',
      () {
        const releaseAt = kT0 + 5 * hour;
        expect(RecordGate.isReleased(releaseAt, releaseAt), isTrue);
        expect(RecordGate.isReleased(releaseAt, releaseAt - 1), isFalse);
        // g' = min(serverNow, wall): a slow wall clock delays the release.
        final serverNow = ServerCursor((releaseAt + hour) * 1000);
        expect(
          RecordGate.isReleased(
            releaseAt,
            RecordGate.referenceMillis(serverNow, releaseAt - 1),
          ),
          isFalse,
        );
        expect(
          RecordGate.isReleased(
            releaseAt,
            RecordGate.referenceMillis(serverNow, releaseAt),
          ),
          isTrue,
        );
        // A record held at receipt passes the K1 check at its releaseAt.
        final r = rec(EntityKind.note, millis: kT0 + day + 7);
        final held = check(r, reference: kT0) as GateHold;
        expect(check(r, reference: held.releaseAtMillis), isA<GateAccept>());
        expect(check(r, reference: held.releaseAtMillis - 1), isA<GateHold>());
      },
    );

    test('a configurable limit', () {
      final r = rec(EntityKind.note, millis: kT0 + hour + 1);
      expect(
        RecordGate.check(
          r,
          scope: 'lib',
          referenceMillis: kT0,
          uid: 'local',
          isPurged: (_) => false,
          limit: const Duration(hours: 1),
        ),
        isA<GateHold>(),
      );
    });
  });
}
