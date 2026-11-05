// Shared SyncStore contract suite (07-sync 5.1.4, C-01..C-25): one body, two
// implementations — FakeLocalStore (test/contract/fake_local_store_contract_test.dart, T6)
// and real CORE through CoreSyncLocalStore(openTestNoteStore) (test/integration/, T16).
// Every check follows a sentence of contract 7.2.10 / 7.2.11 (v1.3); when the two
// implementations disagree, the fake is fixed to the contract sentence.
//
// Time comes from a manual clock the driver's store reads (no fakeAsync — real CORE runs on
// the real event loop). Checks never assume an empty start (real CORE may seed default
// pen presets).
import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

/// HLC node of the store under test and of the simulated remote writer.
const String kContractNode = 'c0c0c0c0c0c0c0c0';
const String kRemoteNode = '0b0b0b0b0b0b0b0b';

/// Virtual start of every check.
final DateTime kContractStart = DateTime.utc(2026, 11, 1, 9);

/// G1 points of CORE 6.2.4 (base64) for remote strokes.
const String kContractPointsBase64 = 'AQED0A9klgGgHzIA9AMyMgBUUg==';

/// A clock the test moves by hand.
final class ContractClock {
  ContractClock(this._now);
  DateTime _now;
  DateTime get now => _now;
  int get millis => _now.millisecondsSinceEpoch;
  late final Clock clock = Clock(() => _now);
  void advance(Duration d) => _now = _now.add(d);
}

/// Device-local note values (C-25).
typedef NoteLocalValues = ({
  EpochMillis? lastOpenedAt,
  int pageCount,
  PageId? firstPageId,
});

/// Local edits done the way the implementation under test does them (5.1.4): the fake
/// calls localWrite / localPurge / assets.put / markOpened, real CORE uses NoteStore.library,
/// a session's AddStrokes, trash, assets.put, markOpened (openSession) and reopening.
abstract interface class SyncStoreContractDriver {
  SyncStore get sync;
  AssetStore get assets;

  /// One event per local / undo / redo commit (SyncLocalStore.localChanges).
  Stream<void> get localChanges;

  Future<FolderId> createFolder(String name);

  /// A note with one page, at the end of [folderId] (null = top level).
  Future<NoteId> createNote(String title, {FolderId? folderId});
  Future<List<PageId>> activePageIds(NoteId noteId);
  Future<void> renameNote(NoteId noteId, String title);
  Future<ElementId> addStroke(PageId pageId);
  Future<void> trashNote(NoteId noteId);
  Future<void> trashFolder(FolderId folderId);

  /// Trash purge of a trashed note (CORE 6.8).
  Future<void> purgeNote(NoteId noteId);
  Future<Asset> putAsset(Uint8List bytes);

  /// CORE markOpened (N-6): sets the device-local Note.lastOpenedAt.
  Future<void> markOpened(NoteId noteId);
  Future<NoteLocalValues> noteLocal(NoteId noteId);
  Future<int> contentRevision(PageId pageId);
  Future<bool> hasLocalBytes(AssetId assetId);

  /// Reopens the same storage (real CORE); null for an in-memory implementation.
  Future<SyncStoreContractDriver?> reopen();
  Future<void> close();
}

typedef SyncStoreContractOpen = Future<SyncStoreContractDriver> Function({
  required String deviceNodeId,
  required Clock clock,
});

/// One policy call as the store made it.
typedef PolicyCall = ({
  VersionedEntity? local,
  VersionedEntity remote,
  Set<String>? pending,
});

/// A RemoteMergePolicy that records its arguments.
final class RecordingPolicy {
  RecordingPolicy(this._decide);
  final MergeDecision Function(
    VersionedEntity? local,
    VersionedEntity remote,
    Set<String>? pending,
  )
  _decide;
  final List<PolicyCall> calls = [];

  MergeDecision call(
    VersionedEntity? local,
    VersionedEntity remote,
    Set<String>? pending,
  ) {
    calls.add((
      local: local,
      remote: remote,
      pending: pending == null ? null : Set.of(pending),
    ));
    return _decide(local, remote, pending);
  }
}

MergeDecision take(VersionedEntity? l, VersionedEntity r, Set<String>? p) =>
    const TakeRemote();

MergeDecision takeKeepingPending(
  VersionedEntity? l,
  VersionedEntity r,
  Set<String>? p,
) => const TakeRemote(dropPendingLocal: false);

MergeDecision keep(VersionedEntity? l, VersionedEntity r, Set<String>? p) =>
    const KeepLocal();

/// [base] with [set] applied and the version of [versions] (a valid RemoteUpsert).
RemoteUpsert remoteOf(
  SyncEntity base, {
  Map<String, Object?> set = const {},
  required EntityFieldVersions versions,
}) => RemoteUpsert(
  EntityJson.decode(base.kind, {
    ...base.toJson(),
    ...set,
    'version': versions.max.toString(),
  }),
  versions,
);

/// A remote entity of [kind] decoded from [json] with [versions].
RemoteUpsert remoteJson(
  EntityKind kind,
  Map<String, Object?> json,
  EntityFieldVersions versions,
) => RemoteUpsert(
  EntityJson.decode(kind, {...json, 'version': versions.max.toString()}),
  versions,
);

Map<String, Object?> remotePageJson(
  PageId id,
  NoteId noteId, {
  required String sortKey,
  required int at,
}) => {
  'id': id,
  'noteId': noteId,
  'sortKey': sortKey,
  'size': [595.2756, 841.8898],
  'background': {'type': 'blank', 'paperColor': 4294967295},
  'createdAt': at,
  'updatedAt': at,
  'deletedAt': null,
};

Map<String, Object?> remoteStrokeJson(
  String id,
  PageId pageId, {
  required int at,
}) => {
  'id': id,
  'pageId': pageId,
  'style': StrokeStyle.defaultsFor(PenTool.ballpoint).toJson(),
  'points': kContractPointsBase64,
  'recordingId': null,
  'recordingOffsetMs': null,
  'createdAt': at,
  'updatedAt': at,
  'deletedAt': null,
};

Map<String, Object?> remoteAssetJson(
  Uint8List bytes, {
  required OwnerId ownerId,
  required int at,
  String? storagePath,
}) => {
  'id': sha256.convert(bytes).toString(),
  'ownerId': ownerId,
  'type': 'pdf',
  'mimeType': 'application/pdf',
  'size': bytes.length,
  'fileName': 'remote.pdf',
  'storagePath': storagePath,
  'createdAt': at,
  'deletedAt': null,
};

Uint8List contractBytes(int seed, [int length = 1000]) => Uint8List.fromList(
  List<int>.generate(length, (i) => (i * 31 + seed) % 251),
);

void expectInvariant(VersionedEntity? row) {
  expect(row, isNotNull);
  expect(row!.entity.version, row.versions.max, reason: 'version == max');
}

/// Registers the suite. [realCore] enables the real-CORE-only checks (reopen).
void syncStoreContract(
  String implementation,
  SyncStoreContractOpen open, {
  bool realCore = false,
}) {
  group('SyncStore contract ($implementation)', () {
    late ContractClock clock;
    late SyncStoreContractDriver d;
    // true until open succeeds: a failing open leaves nothing to close.
    var closed = true;

    setUp(() async {
      clock = ContractClock(kContractStart);
      closed = true;
      d = await open(deviceNodeId: kContractNode, clock: clock.clock);
      closed = false;
    });
    tearDown(() async {
      if (!closed) await d.close();
    });

    Future<VersionedEntity?> read(EntityKind kind, String id) async =>
        (await d.sync.readVersioned([EntityRef(kind, id)])).single;
    Future<List<OutboxEntry>> pending() => d.sync.pendingChanges(limit: 100000);
    Future<OutboxEntry?> entryOf(EntityKind kind, String id) async =>
        (await pending())
            .where((e) => e.kind == kind && e.entityId == id)
            .firstOrNull;
    Future<void> ackAll() async {
      final all = await pending();
      await d.sync.acknowledge([for (final e in all) e.ack]);
    }

    /// Remote HLC [ahead] of the store's clock.
    Hlc remoteHlc(Duration ahead, [int counter = 0]) =>
        Hlc(clock.now.add(ahead).millisecondsSinceEpoch, counter, kRemoteNode);

    /// Counts localChanges events while [body] runs (and the event queue drains).
    Future<int> localEventsDuring(Future<void> Function() body) async {
      var count = 0;
      final sub = d.localChanges.listen((_) => count++);
      await pumpEventQueue();
      count = 0;
      await body();
      await pumpEventQueue();
      await sub.cancel();
      return count;
    }

    test('C-01 deviceNodeId is the HLC node of local writes', () async {
      expect(d.sync.deviceNodeId, kContractNode);
      final n = await d.createNote('a');
      final row = await read(EntityKind.note, n);
      expectInvariant(row);
      expect(row!.entity.version!.nodeId, kContractNode);
      final p = (await d.activePageIds(n)).single;
      final s = await d.addStroke(p);
      expect(
        (await read(EntityKind.stroke, s))!.versions.max.nodeId,
        kContractNode,
      );
    });

    test('C-02 pendingChanges: seq order, limit, afterSeq', () async {
      await d.createNote('a');
      clock.advance(const Duration(seconds: 1));
      await d.createNote('b');
      await d.createNote('c');
      final all = await pending();
      expect(all.length, greaterThanOrEqualTo(6));
      for (var i = 1; i < all.length; i++) {
        expect(all[i].seq, greaterThan(all[i - 1].seq));
      }
      expect(await d.sync.pendingChanges(limit: 2), all.take(2).toList());
      expect(
        await d.sync.pendingChanges(afterSeq: all.first.seq),
        all.skip(1).take(500).toList(),
      );
      expect(
        await d.sync.pendingChanges(afterSeq: all[2].seq, limit: 2),
        all.skip(3).take(2).toList(),
      );
      expect(await d.sync.pendingChanges(afterSeq: all.last.seq), isEmpty);
    });

    test('C-03 outbox merge: one entry per entity, seq kept, rev + 1, field '
        'union, * absorbs, purge wins', () async {
      final n = await d.createNote('a');
      final created = (await entryOf(EntityKind.note, n))!;
      expect(created.changedFields, {kAllFields});
      expect(created.op, OutboxOp.upsert);
      await d.renameNote(n, 'b');
      final absorbed = (await entryOf(EntityKind.note, n))!;
      expect(absorbed.seq, created.seq);
      expect(absorbed.rev, created.rev + 1);
      expect(absorbed.changedFields, {kAllFields});
      expect((await pending()).where((e) => e.entityId == n), hasLength(1));

      await ackAll();
      await d.renameNote(n, 'c');
      final renamed = (await entryOf(EntityKind.note, n))!;
      expect(renamed.changedFields, {'title'});
      await d.trashNote(n);
      final trashed = (await entryOf(EntityKind.note, n))!;
      expect(trashed.seq, renamed.seq);
      expect(trashed.rev, renamed.rev + 1);
      expect(trashed.changedFields, {'title', 'deletedAt', 'trashRootId'});
      await d.purgeNote(n);
      final purged = (await entryOf(EntityKind.note, n))!;
      expect(purged.op, OutboxOp.purge);
      expect(purged.seq, renamed.seq);
      expect(purged.rev, greaterThan(trashed.rev));
      expect((await pending()).where((e) => e.entityId == n), hasLength(1));
    });

    test('C-04 hints: noteId for page and stroke, pageId for stroke', () async {
      final n = await d.createNote('a');
      final p = (await d.activePageIds(n)).single;
      final s = await d.addStroke(p);
      final pageEntry = (await entryOf(EntityKind.page, p))!;
      expect(pageEntry.noteId, n);
      final strokeEntry = (await entryOf(EntityKind.stroke, s))!;
      expect(strokeEntry.noteId, n);
      expect(strokeEntry.pageId, p);
    });

    test(
      'C-05 acknowledge deletes matching (seq, rev); newer revs stay',
      () async {
        await ackAll();
        final n1 = await d.createNote('a');
        await d.createNote('b');
        final sent = await pending();
        final sentN1 = sent.firstWhere((e) => e.entityId == n1);
        await d.renameNote(n1, 'a2');
        await d.sync.acknowledge([for (final e in sent) e.ack]);
        final left = await pending();
        expect(left.map((e) => e.entityId), [n1]);
        expect(left.single.seq, sentN1.seq);
        expect(left.single.rev, greaterThan(sentN1.rev));
        await d.sync.acknowledge([left.single.ack]);
        expect(await pending(), isEmpty);
      },
    );

    test('C-06 watchPendingCount follows writes and acks', () async {
      final values = <int>[];
      final sub = d.sync.watchPendingCount().listen(values.add);
      await pumpEventQueue();
      expect(values, isNotEmpty);
      expect(values.last, (await pending()).length);
      await d.createNote('a');
      await pumpEventQueue();
      expect(values.last, (await pending()).length);
      await ackAll();
      await pumpEventQueue();
      expect(values.last, 0);
      for (var i = 1; i < values.length; i++) {
        expect(values[i], isNot(values[i - 1]), reason: 'distinct values');
      }
      await sub.cancel();
    });

    test(
      'C-07 readVersioned: soft-deleted rows, purged and unknown ids',
      () async {
        final n = await d.createNote('a');
        await d.trashNote(n);
        final trashed = await read(EntityKind.note, n);
        expectInvariant(trashed);
        expect(trashed!.entity.isDeleted, isTrue);
        await d.purgeNote(n);
        expect(await read(EntityKind.note, n), isNull);
        expect(
          await d.sync.readVersioned(const [
            EntityRef(EntityKind.note, 'unknown-note'),
            EntityRef(EntityKind.stroke, 'unknown-stroke'),
          ]),
          [null, null],
        );
      },
    );

    test('C-08 a local write stamps only its changed fields', () async {
      final n = await d.createNote('a');
      final before = (await read(EntityKind.note, n))!;
      expect(before.versions.overrides, isEmpty, reason: "'*' resets all");
      clock.advance(const Duration(seconds: 1));
      await d.renameNote(n, 'b');
      final after = (await read(EntityKind.note, n))!;
      expectInvariant(after);
      expect(after.versions.of('title'), after.entity.version);
      expect(after.versions.of('title') > before.versions.max, isTrue);
      for (final f in ['folderId', 'sortKey', 'cover', 'tags', 'deletedAt']) {
        expect(after.versions.of(f), before.versions.of(f), reason: f);
      }
    });

    test('C-09 policy arguments: null without entry, the entry fields, {*} '
        'for an unsent purge', () async {
      final n = await d.createNote('a');
      await ackAll();
      final local = (await read(EntityKind.note, n))!;
      final none = RecordingPolicy(keep);
      await d.sync.applyRemote([
        remoteOf(
          local.entity,
          set: {'title': 'r'},
          versions: EntityFieldVersions(remoteHlc(const Duration(seconds: 1))),
        ),
      ], policy: none.call);
      expect(none.calls, hasLength(1));
      expect(none.calls.single.pending, isNull);
      expect(none.calls.single.local, local);
      expect(none.calls.single.remote.entity.toJson()['title'], 'r');

      await d.renameNote(n, 'b');
      final upsert = RecordingPolicy(keep);
      await d.sync.applyRemote([
        remoteOf(
          local.entity,
          set: {'title': 'r'},
          versions: EntityFieldVersions(remoteHlc(const Duration(seconds: 2))),
        ),
      ], policy: upsert.call);
      expect(upsert.calls.single.pending, {'title'});

      final n2 = await d.createNote('x');
      await ackAll();
      final row2 = (await read(EntityKind.note, n2))!;
      await d.trashNote(n2);
      await d.purgeNote(n2);
      final purgeEntry = (await entryOf(EntityKind.note, n2))!;
      expect(purgeEntry.op, OutboxOp.purge);
      final purged = RecordingPolicy(keep);
      final report = await d.sync.applyRemote([
        remoteOf(
          row2.entity,
          set: {'title': 'remote edit'},
          versions: EntityFieldVersions(remoteHlc(const Duration(minutes: 1))),
        ),
      ], policy: purged.call);
      expect(purged.calls.single.local, isNull);
      expect(purged.calls.single.pending, {kAllFields});
      expect(report.kept, 1);
      expect(await read(EntityKind.note, n2), isNull);
      expect(await entryOf(EntityKind.note, n2), purgeEntry);
    });

    test('C-10 KeepLocal writes nothing and keeps the pending entry', () async {
      final n = await d.createNote('a');
      await ackAll();
      await d.renameNote(n, 'b');
      final local = (await read(EntityKind.note, n))!;
      final entry = (await entryOf(EntityKind.note, n))!;
      final report = await d.sync.applyRemote([
        remoteOf(
          local.entity,
          set: {'title': 'r'},
          versions: EntityFieldVersions(remoteHlc(const Duration(hours: 1))),
        ),
      ], policy: keep);
      expect(report.kept, 1);
      expect(report.taken + report.merged + report.purged, 0);
      expect(await read(EntityKind.note, n), local);
      expect(await entryOf(EntityKind.note, n), entry);
    });

    test('C-11 TakeRemote stores the remote entity and versions as given', () async {
      final n = await d.createNote('a');
      await ackAll();
      await d.renameNote(n, 'b');
      final local = (await read(EntityKind.note, n))!;
      final rv = EntityFieldVersions(
        Hlc(local.versions.base.millis, 1, kRemoteNode),
        {'title': remoteHlc(const Duration(minutes: 1))},
      );
      final report = await d.sync.applyRemote([
        remoteOf(local.entity, set: {'title': 'r'}, versions: rv),
      ], policy: take);
      expect(report.taken, 1);
      final row = (await read(EntityKind.note, n))!;
      expectInvariant(row);
      expect(row.versions, rv, reason: 'no re-stamping');
      expect(row.entity.toJson()['title'], 'r');
      expect(
        await entryOf(EntityKind.note, n),
        isNull,
        reason: 'dropPendingLocal: true',
      );

      final n2 = await d.createNote('c');
      await ackAll();
      await d.renameNote(n2, 'd');
      final local2 = (await read(EntityKind.note, n2))!;
      final entry2 = (await entryOf(EntityKind.note, n2))!;
      await d.sync.applyRemote([
        remoteOf(
          local2.entity,
          set: {'isFavorite': true},
          versions: EntityFieldVersions(remoteHlc(const Duration(minutes: 2))),
        ),
      ], policy: takeKeepingPending);
      expect(
        (await read(EntityKind.note, n2))!.entity.toJson()['isFavorite'],
        isTrue,
      );
      expect(
        await entryOf(EntityKind.note, n2),
        entry2,
        reason: 'dropPendingLocal: false',
      );

      // (v1.3) a pending purge entry is deleted whatever dropPendingLocal says.
      final n3 = await d.createNote('e');
      await ackAll();
      final row3 = (await read(EntityKind.note, n3))!;
      await d.trashNote(n3);
      await d.purgeNote(n3);
      expect((await entryOf(EntityKind.note, n3))!.op, OutboxOp.purge);
      await d.sync.applyRemote([
        remoteOf(
          row3.entity,
          versions: EntityFieldVersions(remoteHlc(const Duration(minutes: 3))),
        ),
      ], policy: takeKeepingPending);
      expectInvariant(await read(EntityKind.note, n3));
      expect(await entryOf(EntityKind.note, n3), isNull);
    });

    test('C-12 WriteMerged: entry fields become F exactly', () async {
      final n = await d.createNote('a');
      await ackAll();
      await d.renameNote(n, 'b');
      final local = (await read(EntityKind.note, n))!;
      final entry = (await entryOf(EntityKind.note, n))!;
      final mv = EntityFieldVersions(local.versions.base, {
        ...local.versions.overrides,
        'isFavorite': remoteHlc(const Duration(minutes: 1)),
      });
      final merged = remoteOf(
        local.entity,
        set: {'isFavorite': true},
        versions: mv,
      );
      final report = await d.sync.applyRemote(
        [merged],
        policy: (l, r, p) {
          return WriteMerged(
            merged.entity,
            mv,
            fieldsToUpload: const {'title', 'isFavorite'},
          );
        },
      );
      expect(report.merged, 1);
      final row = (await read(EntityKind.note, n))!;
      expectInvariant(row);
      expect(row.versions, mv);
      expect(row.entity.toJson()['isFavorite'], isTrue);
      final after = (await entryOf(EntityKind.note, n))!;
      expect(after.seq, entry.seq);
      expect(after.rev, entry.rev + 1);
      expect(after.op, OutboxOp.upsert);
      expect(after.changedFields, {'title', 'isFavorite'});

      final mv2 = EntityFieldVersions(mv.base, {
        ...mv.overrides,
        'tags': remoteHlc(const Duration(minutes: 2)),
      });
      final merged2 = remoteOf(
        row.entity,
        set: {
          'tags': ['t'],
        },
        versions: mv2,
      );
      await d.sync.applyRemote(
        [merged2],
        policy: (l, r, p) {
          return WriteMerged(merged2.entity, mv2, fieldsToUpload: const {});
        },
      );
      expect(await entryOf(EntityKind.note, n), isNull, reason: 'F empty');

      final mv3 = EntityFieldVersions(mv2.base, {
        ...mv2.overrides,
        'cover': remoteHlc(const Duration(minutes: 3)),
      });
      final merged3 = remoteOf(
        merged2.entity,
        set: {
          'cover': {'type': 'color', 'color': 4294960640},
        },
        versions: mv3,
      );
      await d.sync.applyRemote(
        [merged3],
        policy: (l, r, p) {
          return WriteMerged(
            merged3.entity,
            mv3,
            fieldsToUpload: const {'title'},
          );
        },
      );
      final fresh = (await entryOf(EntityKind.note, n))!;
      expect(fresh.changedFields, {'title'}, reason: 'no entry → new entry');
      expect(fresh.op, OutboxOp.upsert);

      // (v1.3) a pending purge entry becomes an upsert entry of F / is deleted.
      for (final fields in [
        const {'title'},
        const <String>{},
      ]) {
        final p = await d.createNote('p');
        await ackAll();
        final prow = (await read(EntityKind.note, p))!;
        await d.trashNote(p);
        await d.purgeNote(p);
        final purgeEntry = (await entryOf(EntityKind.note, p))!;
        final pv = EntityFieldVersions(remoteHlc(const Duration(minutes: 4)));
        final pm = remoteOf(prow.entity, versions: pv);
        await d.sync.applyRemote(
          [pm],
          policy: (l, r, x) {
            return WriteMerged(pm.entity, pv, fieldsToUpload: fields);
          },
        );
        expectInvariant(await read(EntityKind.note, p));
        final now = await entryOf(EntityKind.note, p);
        if (fields.isEmpty) {
          expect(now, isNull);
        } else {
          expect(now!.op, OutboxOp.upsert);
          expect(now.changedFields, fields);
          expect(now.seq, purgeEntry.seq);
          expect(now.rev, purgeEntry.rev + 1);
        }
      }
    });

    test('C-13 HLC receive: local writes go above the applied max; values past '
        'wall + 24 h do not move the clock', () async {
      final n = await d.createNote('a');
      await ackAll();
      final local = (await read(EntityKind.note, n))!;
      final ahead = remoteHlc(const Duration(hours: 1), 5);
      await d.sync.applyRemote([
        remoteOf(local.entity, versions: EntityFieldVersions(ahead)),
      ], policy: take);
      await d.renameNote(n, 'b');
      final renamed = (await read(EntityKind.note, n))!;
      expect(renamed.entity.version! > ahead, isTrue);

      final n2 = await d.createNote('c');
      await ackAll();
      final local2 = (await read(EntityKind.note, n2))!;
      final far = remoteHlc(const Duration(hours: 25));
      await d.sync.applyRemote([
        remoteOf(local2.entity, versions: EntityFieldVersions(far)),
      ], policy: take);
      clock.advance(const Duration(seconds: 1));
      final n3 = await d.createNote('d');
      final v3 = (await read(EntityKind.note, n3))!.entity.version!;
      expect(v3 < far, isTrue);
      expect(
        v3.millis,
        lessThan(
          clock.now.add(const Duration(hours: 2)).millisecondsSinceEpoch,
        ),
      );
    });

    test('C-14 metaUpdates commit with the changes; a policy error rolls back '
        'everything and is rethrown', () async {
      final n = await d.createNote('a');
      final n2 = await d.createNote('b');
      await ackAll();
      final local = (await read(EntityKind.note, n))!;
      final local2 = (await read(EntityKind.note, n2))!;
      await d.sync.applyRemote(
        [
          remoteOf(
            local.entity,
            set: {'title': 'r1'},
            versions: EntityFieldVersions(
              remoteHlc(const Duration(seconds: 1)),
            ),
          ),
        ],
        policy: take,
        metaUpdates: {'sync.cursor': 'c1'},
      );
      expect(await d.sync.readMeta('sync.cursor'), 'c1');
      final r1 = (await read(EntityKind.note, n))!;
      expect(r1.entity.toJson()['title'], 'r1');

      final error = _PolicyError();
      await expectLater(
        d.sync.applyRemote(
          [
            remoteOf(
              local.entity,
              set: {'title': 'r2'},
              versions: EntityFieldVersions(
                remoteHlc(const Duration(seconds: 2)),
              ),
            ),
            remoteOf(
              local2.entity,
              set: {'title': 'x'},
              versions: EntityFieldVersions(
                remoteHlc(const Duration(seconds: 3)),
              ),
            ),
          ],
          policy: (l, r, p) {
            if (r.entity.id == n2) throw error;
            return const TakeRemote();
          },
          metaUpdates: {'sync.cursor': 'c2'},
        ),
        throwsA(same(error)),
      );
      expect(await d.sync.readMeta('sync.cursor'), 'c1');
      expect(await read(EntityKind.note, n), r1);
      expect(await read(EntityKind.note, n2), local2);
    });

    test('C-15 remote and repair writes do not fire localChanges', () async {
      final n = await d.createNote('a');
      await ackAll();
      final local = (await read(EntityKind.note, n))!;
      final remoteEvents = await localEventsDuring(() async {
        await d.sync.applyRemote([
          remoteOf(
            local.entity,
            set: {'title': 'r'},
            versions: EntityFieldVersions(
              remoteHlc(const Duration(seconds: 1)),
            ),
          ),
        ], policy: take);
        final row = (await read(EntityKind.note, n))!;
        await d.sync.commitRepairs([
          (entity: row.entity, fields: const {'folderId', 'sortKey'}),
        ]);
        await d.sync.reassignOwner(from: kLocalOwnerId, to: 'user-1');
        await d.sync.writeMeta({'sync.x': '1'});
      });
      expect(remoteEvents, 0);
      final localEvents = await localEventsDuring(() => d.renameNote(n, 'b'));
      expect(localEvents, 1);
    });

    test(
      'C-16 affected Note.updatedAt = max(current, applied), no outbox',
      () async {
        final n = await d.createNote('a');
        final p = (await d.activePageIds(n)).single;
        await ackAll();
        final note0 = (await read(EntityKind.note, n))!;
        final u0 = (note0.entity as Note).updatedAt;
        final later = clock.now
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch;
        await d.sync.applyRemote([
          remoteJson(
            EntityKind.stroke,
            remoteStrokeJson('s-remote-1', p, at: later),
            EntityFieldVersions(remoteHlc(const Duration(hours: 1))),
          ),
        ], policy: take);
        final note1 = (await read(EntityKind.note, n))!;
        expect((note1.entity as Note).updatedAt, later);
        expect(note1.versions, note0.versions);
        expect(await entryOf(EntityKind.note, n), isNull);

        await d.sync.applyRemote([
          remoteJson(
            EntityKind.stroke,
            remoteStrokeJson('s-remote-2', p, at: u0 - 86400000),
            EntityFieldVersions(remoteHlc(const Duration(hours: 1), 1)),
          ),
        ], policy: take);
        expect(
          ((await read(EntityKind.note, n))!.entity as Note).updatedAt,
          later,
        );
        expect(await pending(), isEmpty);
      },
    );

    test(
      'C-17 RemotePurge removes the trash group and its outbox entries',
      () async {
        final n = await d.createNote('a');
        final p = (await d.activePageIds(n)).single;
        final s = await d.addStroke(p);
        final other = await d.createNote('other');
        final report = await d.sync.applyRemote([
          RemotePurge(EntityKind.note, n),
        ], policy: take);
        expect(report.purged, 1);
        expect(
          await d.sync.readVersioned([
            EntityRef(EntityKind.note, n),
            EntityRef(EntityKind.page, p),
            EntityRef(EntityKind.stroke, s),
          ]),
          [null, null, null],
        );
        final ids = (await pending()).map((e) => e.entityId).toSet();
        expect(ids.intersection({n, p, s}), isEmpty);
        expect(ids, contains(other));
      },
    );

    test('C-18 invalid input is rejected and changes nothing', () async {
      final n = await d.createNote('a');
      final n2 = await d.createNote('b');
      await ackAll();
      final local = (await read(EntityKind.note, n))!;
      final local2 = (await read(EntityKind.note, n2))!;
      final good = remoteOf(
        local.entity,
        set: {'title': 'g'},
        versions: EntityFieldVersions(remoteHlc(const Duration(seconds: 1))),
      );
      final bad = RemoteUpsert(
        EntityJson.decode(EntityKind.note, {
          ...local2.entity.toJson(),
          'version': remoteHlc(const Duration(seconds: 1)).toString(),
        }),
        EntityFieldVersions(remoteHlc(const Duration(seconds: 2))),
      );
      await expectLater(
        d.sync.applyRemote([good, bad], policy: take),
        throwsArgumentError,
      );
      await expectLater(
        d.sync.applyRemote([
          good,
          RemotePurge(EntityKind.page, 'p-x'),
        ], policy: take),
        throwsArgumentError,
      );
      await expectLater(
        d.sync.applyRemote([good], policy: take, metaUpdates: {'cursor': 'x'}),
        throwsArgumentError,
      );
      await expectLater(
        d.sync.applyRemote(
          [good],
          policy: take,
          metaUpdates: {'sync.big': 'x' * (256 * 1024 + 1)},
        ),
        throwsArgumentError,
      );
      expect(await read(EntityKind.note, n), local);

      final v1 = remoteHlc(const Duration(seconds: 3));
      final v2 = remoteHlc(const Duration(seconds: 4));
      final broken = remoteOf(local2.entity, versions: EntityFieldVersions(v1));
      await expectLater(
        d.sync.applyRemote(
          [good, broken],
          policy: (l, r, p) {
            if (r.entity.id == n2) {
              return WriteMerged(
                broken.entity,
                EntityFieldVersions(v2),
                fieldsToUpload: const {'title'},
              );
            }
            return const TakeRemote();
          },
          metaUpdates: {'sync.cursor': 'c'},
        ),
        throwsStateError,
      );
      expect(await read(EntityKind.note, n), local);
      expect(await read(EntityKind.note, n2), local2);
      expect(await d.sync.readMeta('sync.cursor'), isNull);
      expect(await pending(), isEmpty);
    });

    test('C-19 commitRepairs: one fresh HLC per call, only the given fields, '
        'queued, meta keys ignored', () async {
      final f = await d.createFolder('F');
      final n = await d.createNote('a', folderId: f);
      await ackAll();
      final note0 = (await read(EntityKind.note, n))!;
      final folder0 = (await read(EntityKind.folder, f))!;
      clock.advance(const Duration(seconds: 1));
      await d.sync.commitRepairs([
        (
          entity: EntityJson.decode(EntityKind.note, {
            ...note0.entity.toJson(),
            'folderId': null,
            'sortKey': 'a5',
            'title': 'not taken',
          }),
          fields: const {'folderId', 'sortKey', 'updatedAt'},
        ),
        (
          entity: EntityJson.decode(EntityKind.folder, {
            ...folder0.entity.toJson(),
            'name': 'F2',
          }),
          fields: const {'name'},
        ),
      ]);
      final note1 = (await read(EntityKind.note, n))!;
      final folder1 = (await read(EntityKind.folder, f))!;
      expectInvariant(note1);
      expectInvariant(folder1);
      final h = note1.versions.of('folderId');
      expect(h > note0.versions.max, isTrue);
      expect(note1.versions.of('sortKey'), h);
      expect(folder1.versions.of('name'), h, reason: 'one HLC per call');
      expect(note1.versions.of('title'), note0.versions.of('title'));
      expect(folder1.versions.of('parentId'), folder0.versions.of('parentId'));
      final json = note1.entity.toJson();
      expect(json['folderId'], isNull);
      expect(json['sortKey'], 'a5');
      expect(json['title'], 'a');
      expect(folder1.entity.toJson()['name'], 'F2');
      expect((await entryOf(EntityKind.note, n))!.changedFields, {
        'folderId',
        'sortKey',
      });
      expect((await entryOf(EntityKind.folder, f))!.changedFields, {'name'});
      await expectLater(
        d.sync.commitRepairs([
          (entity: note1.entity, fields: const <String>{}),
        ]),
        throwsArgumentError,
      );
    });

    test('C-20 meta KV: sync. prefix, 256 KiB, one transaction', () async {
      expect(await d.sync.readMeta('sync.a'), isNull);
      await d.sync.writeMeta({'sync.a': '1', 'sync.b': '2'});
      expect(await d.sync.readMeta('sync.a'), '1');
      expect(await d.sync.readMeta('sync.b'), '2');
      await expectLater(
        d.sync.writeMeta({'sync.c': '3', 'other': '4'}),
        throwsArgumentError,
      );
      expect(await d.sync.readMeta('sync.c'), isNull);
      await expectLater(
        d.sync.writeMeta({'sync.d': 'x' * (256 * 1024 + 1)}),
        throwsArgumentError,
      );
      await d.sync.writeMeta({'sync.e': 'x' * (256 * 1024)});
      expect((await d.sync.readMeta('sync.e'))!.length, 256 * 1024);
      await expectLater(d.sync.readMeta('cursor'), throwsArgumentError);
    });

    test('C-21 reassignOwner moves owned rows and keeps the outbox', () async {
      final f = await d.createFolder('F');
      final n = await d.createNote('a', folderId: f);
      final asset = await d.putAsset(contractBytes(1));
      final before = await pending();
      final note0 = (await read(EntityKind.note, n))!;
      await d.sync.reassignOwner(from: kLocalOwnerId, to: 'user-1');
      expect(d.sync.ownerId, 'user-1');
      for (final ref in [
        EntityRef(EntityKind.folder, f),
        EntityRef(EntityKind.note, n),
        EntityRef(EntityKind.asset, asset.id),
      ]) {
        final row = await read(ref.kind, ref.id);
        expectInvariant(row);
        expect(row!.entity.toJson()['ownerId'], 'user-1', reason: '$ref');
      }
      expect((await read(EntityKind.note, n))!.versions, note0.versions);
      expect(await pending(), before);
      await expectLater(
        d.sync.reassignOwner(from: kLocalOwnerId, to: 'user-2'),
        throwsStateError,
      );
      await d.sync.reassignOwner(from: 'user-1', to: 'user-1');
      expect(d.sync.ownerId, 'user-1');
      if (realCore) {
        final reopened = await d.reopen();
        closed = true;
        expect(reopened, isNotNull);
        expect(reopened!.sync.ownerId, 'user-1');
        await reopened.close();
      }
    });

    test('C-22 duplicateNoteForRecovery: trashed source, active copy, folder, '
        'suffix, outbox *, one localChanges', () async {
      final f = await d.createFolder('F');
      final n = await d.createNote('t', folderId: f);
      final p = (await d.activePageIds(n)).single;
      await d.addStroke(p);
      await d.addStroke(p);
      await d.trashNote(n);
      await ackAll();
      NoteId? copy;
      final events = await localEventsDuring(() async {
        copy = await d.sync.duplicateNoteForRecovery(n, titleSuffix: ' (복구)');
      });
      expect(events, 1);
      expect(copy, isNotNull);
      expect(copy, isNot(n));
      final row = (await read(EntityKind.note, copy!))!;
      expectInvariant(row);
      final json = row.entity.toJson();
      expect(json['title'], 't (복구)');
      expect(json['folderId'], f);
      expect(json['deletedAt'], isNull);
      expect(json['trashRootId'], isNull);
      final pages = await d.activePageIds(copy!);
      expect(pages, hasLength(1));
      expect(pages.single, isNot(p));
      final entries = await pending();
      expect(
        entries.every((e) => e.changedFields.contains(kAllFields)),
        isTrue,
      );
      expect(
        entries.where((e) => e.kind == EntityKind.note).single.entityId,
        copy,
      );
      expect(
        entries.where((e) => e.kind == EntityKind.page).single.entityId,
        pages.single,
      );
      final strokes = entries
          .where((e) => e.kind == EntityKind.stroke)
          .toList();
      expect(strokes, hasLength(2));
      for (final s in strokes) {
        expect(s.pageId, pages.single);
        expect(s.noteId, copy);
        expectInvariant(await read(EntityKind.stroke, s.entityId));
      }
      expect((await read(EntityKind.note, n))!.entity.isDeleted, isTrue);

      // An inactive folder → top level.
      final f2 = await d.createFolder('F2');
      final n2 = await d.createNote('u', folderId: f2);
      await d.trashFolder(f2);
      final copy2 = await d.sync.duplicateNoteForRecovery(n2, titleSuffix: '!');
      final json2 = (await read(EntityKind.note, copy2!))!.entity.toJson();
      expect(json2['folderId'], isNull);
      expect(json2['title'], 'u!');

      expect(
        await d.sync.duplicateNoteForRecovery('unknown-note', titleSuffix: 'x'),
        isNull,
      );
    });

    test('C-23 AssetStore: markUploaded, putDownloadedBytes hash check, '
        'bytesArrived, listAssets filters', () async {
      final arrived = <AssetId>[];
      final sub = d.assets.bytesArrived.listen(arrived.add);
      final bytes = contractBytes(7);
      late Asset asset;
      final putEvents = await localEventsDuring(() async {
        asset = await d.putAsset(bytes);
      });
      expect(putEvents, greaterThanOrEqualTo(1));
      expect(arrived, [asset.id]);
      expect(asset.id, sha256.convert(bytes).toString());
      expect(await d.assets.hasBytes(asset.id), isTrue);
      await ackAll();
      final path = 'users/user-1/assets/${asset.id}';
      final events = await localEventsDuring(
        () => d.assets.markUploaded(asset.id, path),
      );
      expect(events, 1);
      expect((await entryOf(EntityKind.asset, asset.id))!.changedFields, {
        'storagePath',
      });
      expect((await d.assets.getAsset(asset.id))!.storagePath, path);
      expectInvariant(await read(EntityKind.asset, asset.id));
      expect(
        (await d.assets.listAssets(uploaded: true)).map((a) => a.id),
        contains(asset.id),
      );
      expect(
        (await d.assets.listAssets(uploaded: false)).map((a) => a.id),
        isNot(contains(asset.id)),
      );

      final bytes2 = contractBytes(9, 2000);
      final json2 = remoteAssetJson(
        bytes2,
        ownerId: d.sync.ownerId,
        at: clock.millis,
        storagePath: 'x/y',
      );
      final id2 = json2['id']! as String;
      await d.sync.applyRemote([
        remoteJson(
          EntityKind.asset,
          json2,
          EntityFieldVersions(remoteHlc(const Duration(seconds: 1))),
        ),
      ], policy: take);
      expect(await d.assets.hasBytes(id2), isFalse);
      expect(
        (await d.assets.listAssets(hasLocalBytes: false)).map((a) => a.id),
        contains(id2),
      );
      await expectLater(
        d.assets.putDownloadedBytes(id2, bytes),
        throwsA(isA<AssetHashMismatchException>()),
      );
      expect(await d.assets.hasBytes(id2), isFalse);
      await d.assets.putDownloadedBytes(id2, bytes2);
      await pumpEventQueue();
      expect(arrived, [asset.id, id2]);
      expect(await d.assets.readBytes(id2), bytes2);
      expect((await d.assets.getAsset(id2))!.hasLocalBytes, isTrue);
      expect(
        (await d.assets.listAssets(hasLocalBytes: true)).map((a) => a.id),
        containsAll([asset.id, id2]),
      );
      await sub.cancel();
    });

    test('C-24 orphans are stored; writes before login are queued', () async {
      expect(d.sync.ownerId, kLocalOwnerId);
      final n = await d.createNote('a');
      expect(await entryOf(EntityKind.note, n), isNotNull);
      await d.sync.applyRemote([
        remoteJson(
          EntityKind.stroke,
          remoteStrokeJson('s-orphan-1', 'p-orphan-1', at: clock.millis),
          EntityFieldVersions(remoteHlc(const Duration(seconds: 1))),
        ),
      ], policy: take);
      expect(await read(EntityKind.stroke, 's-orphan-1'), isNotNull);
      await d.sync.applyRemote([
        remoteJson(
          EntityKind.page,
          remotePageJson('p-orphan-1', n, sortKey: 'a5', at: clock.millis),
          EntityFieldVersions(remoteHlc(const Duration(seconds: 2))),
        ),
      ], policy: take);
      final rows = await d.sync.readVersioned(const [
        EntityRef(EntityKind.stroke, 's-orphan-1'),
        EntityRef(EntityKind.page, 'p-orphan-1'),
      ]);
      expect(rows.every((r) => r != null), isTrue);
      expect(await d.activePageIds(n), contains('p-orphan-1'));
    });

    test('C-25 device-local values are kept or recomputed on remote and repair '
        'writes', () async {
      final n = await d.createNote('a');
      final p0 = (await d.activePageIds(n)).single;
      clock.advance(const Duration(minutes: 1));
      await d.markOpened(n);
      final opened = await d.noteLocal(n);
      expect(opened.lastOpenedAt, isNotNull);
      expect(opened.pageCount, 1);
      expect(opened.firstPageId, p0);
      await ackAll();

      // TakeRemote of the note.
      var note = (await read(EntityKind.note, n))!;
      await d.sync.applyRemote([
        remoteOf(
          note.entity,
          set: {'title': 'r1'},
          versions: EntityFieldVersions(remoteHlc(const Duration(seconds: 1))),
        ),
      ], policy: take);
      expect(await d.noteLocal(n), opened);

      // WriteMerged of the note.
      note = (await read(EntityKind.note, n))!;
      final mv = EntityFieldVersions(note.versions.base, {
        'title': remoteHlc(const Duration(seconds: 2)),
      });
      final merged = remoteOf(note.entity, set: {'title': 'r2'}, versions: mv);
      await d.sync.applyRemote(
        [merged],
        policy: (l, r, p) {
          return WriteMerged(merged.entity, mv, fieldsToUpload: const {});
        },
      );
      expect(await d.noteLocal(n), opened);

      // Repair write of the note.
      note = (await read(EntityKind.note, n))!;
      await d.sync.commitRepairs([
        (
          entity: EntityJson.decode(EntityKind.note, {
            ...note.entity.toJson(),
            'sortKey': 'a7',
          }),
          fields: const {'folderId', 'sortKey'},
        ),
      ]);
      expect(await d.noteLocal(n), opened);

      // A remote page before p0: recomputed count and first page; a new row starts at 0.
      final rev0 = await d.contentRevision(p0);
      await d.sync.applyRemote([
        remoteJson(
          EntityKind.page,
          remotePageJson('p-remote-1', n, sortKey: 'Zz', at: clock.millis),
          EntityFieldVersions(remoteHlc(const Duration(seconds: 3))),
        ),
      ], policy: take);
      final withPage = await d.noteLocal(n);
      expect(withPage.lastOpenedAt, opened.lastOpenedAt);
      expect(withPage.pageCount, 2);
      expect(withPage.firstPageId, 'p-remote-1');
      expect(await d.contentRevision('p-remote-1'), 0);
      expect(await d.contentRevision(p0), rev0);

      // A remote stroke on p0 and a repair of p0: + 1 each.
      await d.sync.applyRemote([
        remoteJson(
          EntityKind.stroke,
          remoteStrokeJson('s-remote-9', p0, at: clock.millis),
          EntityFieldVersions(remoteHlc(const Duration(seconds: 4))),
        ),
      ], policy: take);
      expect(await d.contentRevision(p0), rev0 + 1);
      final page0 = (await read(EntityKind.page, p0))!;
      await d.sync.commitRepairs([
        (entity: page0.entity, fields: const {'deletedAt'}),
      ]);
      expect(await d.contentRevision(p0), rev0 + 2);

      // Assets: a remote asset without bytes has none; bytes + remote storagePath keep them.
      final remoteBytes = contractBytes(3, 500);
      final json = remoteAssetJson(
        remoteBytes,
        ownerId: d.sync.ownerId,
        at: clock.millis,
      );
      final remoteId = json['id']! as String;
      await d.sync.applyRemote([
        remoteJson(
          EntityKind.asset,
          json,
          EntityFieldVersions(remoteHlc(const Duration(seconds: 5))),
        ),
      ], policy: take);
      expect(await d.hasLocalBytes(remoteId), isFalse);
      expect(
        (await d.assets.listAssets(hasLocalBytes: false)).map((a) => a.id),
        contains(remoteId),
      );

      final mine = await d.putAsset(contractBytes(4, 600));
      final mineRow = (await read(EntityKind.asset, mine.id))!;
      final av = EntityFieldVersions(mineRow.versions.base, {
        'storagePath': remoteHlc(const Duration(seconds: 6)),
      });
      final withPath = remoteOf(
        mineRow.entity,
        set: {'storagePath': 'users/u/assets/${mine.id}'},
        versions: av,
      );
      await d.sync.applyRemote(
        [withPath],
        policy: (l, r, p) {
          return WriteMerged(withPath.entity, av, fieldsToUpload: const {});
        },
      );
      expect(await d.hasLocalBytes(mine.id), isTrue);
      expect(
        (await d.assets.getAsset(mine.id))!.storagePath,
        'users/u/assets/${mine.id}',
      );
    });
  });
}

final class _PolicyError implements Exception {
  @override
  String toString() => '_PolicyError';
}
