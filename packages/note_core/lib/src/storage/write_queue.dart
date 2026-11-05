// lib/src/storage/write_queue.dart (internal) — the single serial write queue (CORE 6.9).
//
// Every write (session edits, repository commands, remote apply) is a job. Jobs
// queued while a transaction runs are grouped into the next transaction (at most
// 256 jobs or 4 MiB of point data). Each job runs in its own savepoint: a domain
// error (an Error such as ArgumentError / StateError, or a NoteCoreException)
// rolls back only that job and completes its Future with the error, never
// retried. Any other failure (SQLite I/O, a failed commit) rolls the whole
// transaction back; the same jobs are retried after 100 ms → 400 ms → 1.6 s →
// 5 s (forever) and their Futures stay pending meanwhile (4.5 head).
import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../common/errors.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../model/asset.dart';
import '../model/page.dart';
import '../model/stroke.dart';
import '../model/sync_entity.dart';
import '../repo/events.dart';
import '../repo/status.dart';
import '../session/page_content.dart';
import '../sync/field_versions.dart';
import '../sync/outbox_types.dart';
import 'change_bus.dart';
import 'db/note_database.dart';
import 'field_version_writer.dart';
import 'kv_keys.dart';
import 'outbox_writer.dart';
import 'row_mappers.dart';
import 'watch_hub.dart';

/// Retry schedule of a failed commit (6.9); the last value repeats.
const List<Duration> kWriteRetryBackoff = [
  Duration(milliseconds: 100),
  Duration(milliseconds: 400),
  Duration(milliseconds: 1600),
  Duration(seconds: 5),
];

/// Group commit caps (6.9).
const int kMaxJobsPerTransaction = 256;
const int kMaxBytesPerTransaction = 4 * 1024 * 1024;

/// Whether [e], thrown by a job, is a domain error of that job (completes it, no
/// retry) rather than a storage failure (retries the transaction).
bool isDomainError(Object e) => e is Error || e is NoteCoreException;

final class _Job<T> {
  _Job(this.body, this.origin, this.bytes, this.enqueuedAt);
  final Future<T> Function(WriteTxn tx) body;
  final ChangeOrigin origin;
  final int bytes;
  final DateTime enqueuedAt;
  final Completer<T> completer = Completer<T>();

  // Result of the last (committed) attempt.
  bool ok = false;
  T? value;
  Object? error;
  StackTrace? stack;
  WriteTxn? tx;

  Future<void> attempt(WriteTxn scope, NoteDatabase db) async {
    tx = scope;
    try {
      value = await db.transaction(() => body(scope));
      ok = true;
      error = null;
    } on Object catch (e, s) {
      if (!isDomainError(e)) rethrow;
      ok = false;
      error = e;
      stack = s;
    }
  }

  void complete() {
    if (ok) {
      completer.complete(value as T);
    } else {
      completer.completeError(error!, stack);
    }
  }
}

final class WriteQueue {
  WriteQueue({
    required this.db,
    required this.hlc,
    required this.clock,
    required this.bus,
    required this.watches,
    this._persistedHlc,
  });

  final NoteDatabase db;
  final HlcClock hlc;
  final Clock clock;
  final ChangeBus bus;

  /// Watch streams re-queried after each commit, before its jobs complete.
  final WatchHub watches;
  String? _persistedHlc;

  final Queue<_Job<Object?>> _queue = Queue();
  List<_Job<Object?>> _inFlight = const [];
  bool _scheduled = false;
  bool _running = false;
  bool _closed = false;

  int _failing = 0;
  Object _failError = const FormatException('injected commit failure');

  /// Runs after each commit, after its ChangeBatches are published and before the
  /// watch streams re-query and the commit's Futures complete (open sessions, 6.14
  /// N-4 / N-7). A failure is not the commit's failure.
  Future<void> Function(List<ChangeBatch> batches)? onCommitted;

  /// Transactions attempted so far (tests: group commit).
  @visibleForTesting
  int debugTransactionCount = 0;

  PersistenceStatus _status = const PersistenceStatus(
    pendingOps: 0,
    isWriting: false,
  );
  final StreamController<PersistenceStatus> _statusCtrl =
      StreamController.broadcast();

  PersistenceStatus get status => _status;
  Stream<PersistenceStatus> get statusChanges => _statusCtrl.stream;

  /// Tests: the next [count] commits fail with [error] after the jobs ran (the
  /// transaction is rolled back and retried on the 6.9 schedule).
  @visibleForTesting
  void failNextCommits(
    int count, {
    Object error = const FormatException('injected commit failure'),
  }) {
    _failing += count;
    _failError = error;
  }

  /// Enqueues [body]; it runs inside the next transaction. [bytes] counts toward
  /// the 4 MiB cap (point data).
  Future<T> run<T>(
    Future<T> Function(WriteTxn tx) body, {
    ChangeOrigin origin = ChangeOrigin.local,
    int bytes = 0,
  }) {
    if (_closed) return Future.error(StateError('The note store is closed'));
    final job = _Job<Object?>(body, origin, bytes, clock.now());
    _queue.add(job);
    _setStatus(pendingOps: _pending);
    _schedule(Duration.zero);
    return job.completer.future.then((v) => v as T);
  }

  /// Every job queued before this call is done; pending while a commit is retried.
  Future<void> flush() {
    final jobs = [..._inFlight, ..._queue];
    if (jobs.isEmpty) return Future<void>.value();
    return Future.wait([
      for (final j in jobs)
        j.completer.future.then<void>((_) {}, onError: (Object _) {}),
    ]);
  }

  int get _pending => _queue.length + _inFlight.length;

  void _schedule(Duration delay) {
    // Not stopped by close(): queued and retried jobs still run (close flushes).
    if (_scheduled || _running) return;
    if (_queue.isEmpty && _inFlight.isEmpty) return;
    _scheduled = true;
    if (delay == Duration.zero) {
      scheduleMicrotask(_attempt);
    } else {
      Timer(delay, _attempt);
    }
  }

  List<_Job<Object?>> _take() {
    final taken = <_Job<Object?>>[];
    var bytes = 0;
    while (_queue.isNotEmpty && taken.length < kMaxJobsPerTransaction) {
      final next = _queue.first;
      if (taken.isNotEmpty && bytes + next.bytes > kMaxBytesPerTransaction) {
        break;
      }
      bytes += next.bytes;
      taken.add(_queue.removeFirst());
    }
    return taken;
  }

  Future<void> _attempt() async {
    _scheduled = false;
    if (_inFlight.isEmpty) _inFlight = _take();
    final batch = _inFlight;
    if (batch.isEmpty) return;
    _running = true;
    _setStatus(isWriting: true);
    final now = clock.now().millisecondsSinceEpoch;
    try {
      debugTransactionCount++;
      String? hlcText;
      await db.transaction(() async {
        for (final job in batch) {
          await job.attempt(WriteTxn._(this, job.origin, now), db);
        }
        if (_failing > 0) {
          _failing--;
          Error.throwWithStackTrace(_failError, StackTrace.current);
        }
        final text = hlc.last.toString();
        if (text != _persistedHlc) {
          await db
              .into(db.kv)
              .insertOnConflictUpdate(
                KvCompanion.insert(key: KvKeys.hlcLast, value: text),
              );
          hlcText = text;
        }
      });
      if (hlcText != null) _persistedHlc = hlcText;
    } on Object catch (e) {
      _running = false;
      final failures = _status.consecutiveFailures + 1;
      _setStatus(
        isWriting: false,
        lastError: e,
        lastErrorAt: clock.now().millisecondsSinceEpoch,
        consecutiveFailures: failures,
      );
      final i = failures - 1 < kWriteRetryBackoff.length
          ? failures - 1
          : kWriteRetryBackoff.length - 1;
      _schedule(kWriteRetryBackoff[i]);
      return;
    }
    final committed = clock.now();
    _setStatus(
      pendingOps: _queue.length,
      isWriting: false,
      lastCommittedAt: committed.millisecondsSinceEpoch,
      lastCommitLatency: committed.difference(batch.first.enqueuedAt),
      consecutiveFailures: 0,
    );
    final ok = [
      for (final j in batch)
        if (j.ok) j.tx!,
    ];
    for (final tx in ok) {
      for (final f in tx._after) {
        f();
      }
    }
    final batches = batchesOf([
      for (final tx in ok) (tx.origin, tx._changes),
    ], committed.millisecondsSinceEpoch);
    bus.publish(batches);
    final hook = onCommitted;
    if (hook != null && batches.isNotEmpty) {
      try {
        await hook(batches);
      } on Object {
        // Session refresh is best effort; the commit itself succeeded.
      }
    }
    // Watch streams re-emit before the Futures of this commit complete (C-1, 4.5 head).
    await watches.committed(
      CommitTouch(
        {for (final tx in ok) ...tx._touched},
        {for (final tx in ok) ...tx._kvTouched},
      ),
    );
    _inFlight = const [];
    _running = false;
    for (final j in batch) {
      j.complete();
    }
    _setStatus(pendingOps: _pending);
    _schedule(Duration.zero);
  }

  void _setStatus({
    int? pendingOps,
    bool? isWriting,
    int? lastCommittedAt,
    Duration? lastCommitLatency,
    Object? lastError,
    int? lastErrorAt,
    int? consecutiveFailures,
  }) {
    final s = _status;
    final next = PersistenceStatus(
      pendingOps: pendingOps ?? s.pendingOps,
      isWriting: isWriting ?? s.isWriting,
      lastCommittedAt: lastCommittedAt ?? s.lastCommittedAt,
      lastCommitLatency: lastCommitLatency ?? s.lastCommitLatency,
      lastError: lastError ?? s.lastError,
      lastErrorAt: lastErrorAt ?? s.lastErrorAt,
      consecutiveFailures: consecutiveFailures ?? s.consecutiveFailures,
    );
    if (next == s) return;
    _status = next;
    if (!_statusCtrl.isClosed) _statusCtrl.add(next);
  }

  /// Refuses new jobs, waits for the queued ones, then closes the status stream.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await flush();
    await _statusCtrl.close();
  }
}

/// One job's view of the running transaction.
final class WriteTxn {
  WriteTxn._(this._queue, this.origin, this.now);

  final WriteQueue _queue;
  final ChangeOrigin origin;

  /// Wall-clock ms of this transaction (outbox enqueuedAt).
  final EpochMillis now;
  final List<EntityChange> _changes = [];
  final List<void Function()> _after = [];
  final Set<EntityKind> _touched = {};
  final Set<String> _kvTouched = {};
  final Map<PageId, NoteId?> _pageNotes = {};

  NoteDatabase get db => _queue.db;

  /// A new local HLC value (6.4).
  Hlc stamp() => _queue.hlc.now();

  /// Merges a remote HLC value into the clock (6.4 receive).
  void receive(Hlc remote) => _queue.hlc.receive(remote);

  void addChange(EntityChange change) {
    _touched.add(change.kind);
    _changes.add(change);
  }

  /// Marks a raw write of [kind] rows (watch streams re-query; no ChangeBatch entry).
  void touch(EntityKind kind) => _touched.add(kind);

  /// Marks a write of the kv row [key] (device settings, meta).
  void touchKv(String key) => _kvTouched.add(key);

  /// Runs [f] after the commit, before ChangeBatches are published (in-memory caches).
  void afterCommit(void Function() f) => _after.add(f);

  /// The note of an active or trashed page row (null when there is no row).
  Future<NoteId?> noteIdOfPage(PageId pageId) async {
    if (_pageNotes.containsKey(pageId)) return _pageNotes[pageId];
    final row =
        await (db.selectOnly(db.pages)
              ..addColumns([db.pages.noteId])
              ..where(db.pages.id.equals(pageId)))
            .getSingleOrNull();
    return _pageNotes[pageId] = row?.read(db.pages.noteId);
  }

  /// Local write of [entity] whose JSON keys [fields] changed (`{*}` = all, e.g. new).
  /// Stamps a new HLC, writes the row with field versions, records the outbox entry
  /// and the EntityChange. Only local-only / meta fields → no stamp, no outbox.
  /// Returns the stored field versions (max = the entity's new version).
  /// [isNew]: the caller knows there is no row (fresh id) — skips reading it.
  /// [fixedVersion]: the version to write instead of a new stamp (seed data such as
  /// the default presets, 6.2.2). [assetChunkCount]: the local assets.chunk_count
  /// (null keeps the row's value; 0 for a new row).
  Future<EntityFieldVersions> putLocal(
    SyncEntity entity,
    Iterable<String> fields, {
    NoteId? strokeNoteId,
    bool isNew = false,
    Hlc? fixedVersion,
    int? assetChunkCount,
  }) async {
    final ref = EntityRef(entity.kind, entity.id);
    final current = isNew ? null : await readVersionedRow(db, ref);
    var synced = syncedFieldsOf(entity.kind, fields);
    if (current == null && synced.isEmpty) synced = const {kAllFields};
    final hints = await _hints(entity, strokeNoteId);
    _touched.add(entity.kind);
    if (synced.isEmpty) {
      // Local-only change: the row's versions stay.
      await writeEntityRow(
        db,
        entity,
        current!.versions,
        strokeNoteId: hints.noteId,
        assetChunkCount: assetChunkCount,
      );
      return current.versions;
    }
    final h = fixedVersion ?? stamp();
    final versions = localVersionsAfter(current?.versions, synced, h);
    await writeEntityRow(
      db,
      entity,
      versions,
      strokeNoteId: hints.noteId,
      assetChunkCount: assetChunkCount,
    );
    await recordOutbox(
      db,
      kind: entity.kind,
      id: entity.id,
      noteId: hints.noteId,
      pageId: hints.pageId,
      op: OutboxOp.upsert,
      fields: synced,
      hlc: h,
      now: now,
    );
    addChange(
      EntityChange(
        kind: entity.kind,
        id: entity.id,
        noteId: hints.noteId,
        pageId: hints.pageId,
        deleted: entity.isDeleted,
      ),
    );
    return versions;
  }

  /// Remote write (internal path of applyRemote / commitRepairs): stores [entity] with
  /// [versions] as given (no re-stamp, no outbox), keeps local-only columns of an
  /// existing row, merges the version into the HLC unless [advanceClock] is false (the
  /// caller receives once). A stroke whose page row is not here is an orphan: it is
  /// stored with note_id '' and listed in the batch of the commit that brings its page
  /// (6.10.1, 6.10.3, contract 7.2.10 v1.2). [assetChunkCount]: chunk_count of a new
  /// asset row. Returns the routing hints (noteId null for an orphan stroke).
  Future<({NoteId? noteId, PageId? pageId})> putRemote(
    SyncEntity entity,
    EntityFieldVersions versions, {
    bool advanceClock = true,
    int? assetChunkCount,
  }) async {
    _touched.add(entity.kind);
    final hints = await _hints(entity, null);
    final orphan = entity is Stroke && hints.noteId == null;
    await writeEntityRow(
      db,
      entity,
      versions,
      keepLocal: true,
      strokeNoteId: hints.noteId ?? '',
      assetChunkCount: assetChunkCount,
    );
    if (!orphan) {
      addChange(
        EntityChange(
          kind: entity.kind,
          id: entity.id,
          noteId: hints.noteId,
          pageId: hints.pageId,
          deleted: entity.isDeleted,
        ),
      );
    }
    if (entity is Page) await _adoptOrphans(entity);
    if (advanceClock) receive(versions.max);
    return hints;
  }

  /// Forgets the cached page → note lookups (after page rows were deleted).
  void forgetPageNotes() => _pageNotes.clear();

  /// Deletes the row of [ref]; records an outbox purge unless [outbox] is false.
  Future<void> purge(
    EntityRef ref, {
    bool outbox = true,
    NoteId? noteId,
    PageId? pageId,
  }) async {
    await deleteEntityRow(db, ref);
    if (outbox) {
      await recordOutbox(
        db,
        kind: ref.kind,
        id: ref.id,
        noteId: noteId,
        pageId: pageId,
        op: OutboxOp.purge,
        fields: const {kAllFields},
        hlc: stamp(),
        now: now,
      );
    }
    addChange(
      EntityChange(
        kind: ref.kind,
        id: ref.id,
        noteId: noteId,
        pageId: pageId,
        purged: true,
      ),
    );
  }

  Future<({NoteId? noteId, PageId? pageId})> _hints(
    SyncEntity e,
    NoteId? strokeNoteId,
  ) async {
    switch (e) {
      case Page(:final id, :final noteId):
        _pageNotes[id] = noteId;
        return (noteId: noteId, pageId: null);
      case Stroke(:final pageId):
        return (
          noteId: strokeNoteId ?? await noteIdOfPage(pageId),
          pageId: pageId,
        );
      case Recording(:final noteId):
        return (noteId: noteId, pageId: null);
      default:
        return (noteId: null, pageId: null);
    }
  }

  Future<void> _adoptOrphans(Page page) async {
    final s = db.strokes;
    final rows =
        await (db.selectOnly(s)
              ..addColumns([s.id, s.deletedAt])
              ..where(s.pageId.equals(page.id) & s.noteId.equals('')))
            .get();
    if (rows.isEmpty) return;
    await (db.update(s)
          ..where((t) => t.pageId.equals(page.id) & t.noteId.equals('')))
        .write(StrokesCompanion(noteId: Value(page.noteId)));
    final o = db.outbox;
    await (db.update(o)..where(
          (t) =>
              t.entityKind.equals(EntityKind.stroke.name) &
              t.pageId.equals(page.id) &
              (t.noteId.isNull() | t.noteId.equals('')),
        ))
        .write(OutboxCompanion(noteId: Value(page.noteId)));
    for (final r in rows) {
      addChange(
        EntityChange(
          kind: EntityKind.stroke,
          id: r.read(s.id)!,
          noteId: page.noteId,
          pageId: page.id,
          deleted: r.read(s.deletedAt) != null,
        ),
      );
    }
  }
}
