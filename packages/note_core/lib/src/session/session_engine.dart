// Internal: the NoteSession implementation shared by the DB store and the fake store
// (CORE 6.14, contract 7.2.8 N-1..N-7). Pure Dart; storage goes through SessionBackend.
import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';

import '../common/errors.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../edit/applied_edit.dart';
import '../edit/command_resolver.dart';
import '../edit/commands.dart';
import '../edit/history.dart';
import '../model/note.dart';
import '../model/page.dart';
import '../model/stroke.dart';
import '../model/sync_entity.dart';
import '../sync/outbox_types.dart';
import 'note_session.dart';
import 'page_content.dart';
import 'session_backend.dart';

final class _Loaded {
  _Loaded(this.byId, this.sorted, this.content);
  final Map<ElementId, Stroke> byId;
  final List<Stroke> sorted;
  PageContent content;
  int pins = 0;
}

final class _PageDiff {
  final Set<ElementId> added = {};
  final Set<ElementId> removed = {};
  final Set<ElementId> updated = {};
  bool pageChanged = false;
  bool orderChanged = false;
  bool get isEmpty =>
      added.isEmpty && removed.isEmpty && updated.isEmpty && !pageChanged;
}

final class _Applied {
  final List<SyncEntity> written = [];
  final Set<PageId> bumped = {};
  final Map<PageId, _PageDiff> diffs = {};
  bool pagesChanged = false;
  bool noteChanged = false;
}

final class SessionEngine implements NoteSession, ResolveState {
  SessionEngine({
    required this._note,
    required List<Page> pages,
    required this.backend,
    required this.options,
    required this._hlc,
    required this._clock,
    required IdGenerator ids,
  }) : _resolver = CommandResolver(ids: ids),
       _history = EditHistory(options.history) {
    for (final p in pages) {
      _pagesById[p.id] = p;
    }
    _active = _sortedActive();
    _lastHistory = _history.state;
  }

  final SessionBackend backend;
  final NoteSessionOptions options;
  final HlcClock _hlc;
  final Clock _clock;
  final CommandResolver _resolver;
  final EditHistory _history;

  Note _note;
  final Map<PageId, Page> _pagesById = {};
  List<Page> _active = const [];
  final Map<PageId, _Loaded> _loaded = {};
  final Map<PageId, Future<PageContent>> _loading = {};
  final Map<PageId, int> _loadWaiters = {};
  final Map<EntityRef, SyncEntity> _tombstones = {};
  final Map<PageId, StreamController<PageContentChange>> _pageCtrls = {};
  final StreamController<Note> _noteCtrl = StreamController.broadcast(
    sync: true,
  );
  final StreamController<List<Page>> _pagesCtrl = StreamController.broadcast(
    sync: true,
  );
  final StreamController<HistoryState> _historyCtrl =
      StreamController.broadcast(sync: true);
  late HistoryState _lastHistory;

  int _refs = 1;
  bool _closed = false;
  bool _dispatching = false;
  int _generation = 0;

  /// Another openSession() of the same note (N-5).
  void retain() => _refs++;

  // ---- NoteSession: state -----------------------------------------------------

  @override
  NoteId get noteId => _note.id;
  @override
  Note get note => _note;
  @override
  Stream<Note> get noteStream => _noteCtrl.stream;
  @override
  bool get isReadOnly => _note.requiresNewerApp || _note.isDeleted;
  @override
  List<Page> get pages => _active;
  @override
  Stream<List<Page>> get pagesStream => _pagesCtrl.stream;
  @override
  HistoryState get history => _history.state;
  @override
  Stream<HistoryState> get historyStream => _historyCtrl.stream;
  @override
  bool get isClosed => _closed;

  // ---- ResolveState -------------------------------------------------------------

  @override
  List<Page> get activePages => _active;
  @override
  Page? knownPage(PageId id) => _pagesById[id];
  @override
  Map<ElementId, Stroke>? activeStrokes(PageId pageId) => _loaded[pageId]?.byId;
  @override
  bool isKnownStroke(ElementId id) =>
      _tombstones.containsKey(EntityRef(EntityKind.stroke, id));

  // ---- pages --------------------------------------------------------------------

  @override
  Future<PageContent> openPage(PageId pageId) async {
    _checkOpen();
    final loaded = _loaded[pageId];
    if (loaded != null) {
      loaded.pins++;
      return loaded.content;
    }
    if (!_pagesById.containsKey(pageId)) {
      throw EntityNotFoundException('Page $pageId is not in note $noteId');
    }
    // Every waiter holds one pin; _load hands them over when the page is installed.
    _loadWaiters[pageId] = (_loadWaiters[pageId] ?? 0) + 1;
    return _loading[pageId] ??= _load(pageId);
  }

  Future<PageContent> _load(PageId pageId) async {
    try {
      final strokes = await backend.loadStrokes(pageId);
      _checkOpen();
      final byId = {for (final s in strokes) s.id: s};
      final sorted = byId.values.toList()..sort(Stroke.compareOrder);
      final l = _Loaded(
        byId,
        sorted,
        PageContent(page: _pagesById[pageId]!, strokes: sorted, revision: 0),
      )..pins = _loadWaiters.remove(pageId) ?? 0;
      _loaded[pageId] = l;
      _evict();
      if (_pageCtrls[pageId]?.hasListener ?? false) {
        _dispatch(
          () => _pageCtrls[pageId]!.add(
            PageContentChange(content: l.content, origin: ChangeOrigin.load),
          ),
        );
      }
      return l.content;
    } finally {
      _loadWaiters.remove(pageId);
      unawaited(_loading.remove(pageId));
    }
  }

  @override
  void closePage(PageId pageId) {
    if (_closed) return;
    final l = _loaded[pageId];
    if (l == null) return;
    if (l.pins > 0) l.pins--;
    if (l.pins == 0) {
      // Most recently used goes last (LRU order = iteration order).
      _loaded
        ..remove(pageId)
        ..[pageId] = l;
      _evict();
    }
  }

  void _evict() {
    var unpinned = _loaded.values.where((l) => l.pins == 0).length;
    if (unpinned <= options.maxCachedPages) return;
    final victims = <PageId>[];
    for (final e in _loaded.entries) {
      if (unpinned <= options.maxCachedPages) break;
      if (e.value.pins == 0) {
        victims.add(e.key);
        unpinned--;
      }
    }
    victims.forEach(_loaded.remove);
  }

  @override
  PageContent? pageIfLoaded(PageId pageId) => _loaded[pageId]?.content;

  @override
  Stream<PageContentChange> pageChanges(PageId pageId) {
    // One synchronous broadcast controller per call. The `load` change for an already
    // loaded page is delivered one microtask after listen — or right before the next
    // change, whichever comes first — so order holds and later changes stay synchronous
    // (N-1) without delivering events from inside listen().
    StreamSubscription<PageContentChange>? source;
    PageContentChange? pendingLoad;
    late final StreamController<PageContentChange> out;
    void flushLoad() {
      final load = pendingLoad;
      if (load == null) return;
      pendingLoad = null;
      out.add(load);
    }

    out = StreamController<PageContentChange>.broadcast(
      sync: true,
      onListen: () {
        final loaded = _loaded[pageId];
        if (loaded != null) {
          pendingLoad = PageContentChange(
            content: loaded.content,
            origin: ChangeOrigin.load,
          );
          scheduleMicrotask(flushLoad);
        }
        _pageCtrls[pageId] ??= StreamController.broadcast(sync: true);
        source = _pageCtrls[pageId]!.stream.listen(
          (change) {
            flushLoad();
            out.add(change);
          },
          onError: out.addError,
          onDone: out.close,
        );
      },
      onCancel: () {
        pendingLoad = null;
        if (source != null) unawaited(source!.cancel());
        source = null;
      },
    );
    return out.stream;
  }

  // ---- commands -------------------------------------------------------------------

  @override
  CommandReceipt execute(EditCommand command) {
    _checkOpen();
    if (_dispatching) {
      throw StateError(
        'NoteSession.execute() was called from inside a session stream listener; '
        'defer it with scheduleMicrotask (contract 7.2.8 N-2)',
      );
    }
    _checkWritable();
    final now = _clock.now().millisecondsSinceEpoch;
    final resolved = _resolver.resolve(
      command,
      this,
      now: now,
      version: _hlc.now(),
    );
    final edit = resolved.edit;
    if (edit.isEmpty) {
      return CommandReceipt(edit: edit, persisted: Future<void>.value());
    }
    _generation++;
    final applied = _install([for (final d in edit.deltas) d.after!], now);
    _history.push(edit);
    final persisted = _write(
      ChangeOrigin.local,
      applied,
      resolved.changedFields,
    );
    _emit(applied, ChangeOrigin.local);
    return CommandReceipt(edit: edit, persisted: persisted);
  }

  @override
  Future<CommandReceipt> executeAsync(EditCommand command) async {
    _checkOpen();
    _checkWritable();
    final pins = await _pin(_pagesNeeded(command));
    try {
      return execute(command);
    } finally {
      _unpin(pins);
    }
  }

  Set<PageId> _pagesNeeded(EditCommand c) => switch (c) {
    AddStrokes(:final pageId) ||
    RemoveStrokes(:final pageId) ||
    SplitStrokes(:final pageId) ||
    TransformElements(:final pageId) ||
    RestyleStrokes(:final pageId) ||
    ClearPage(:final pageId) => {pageId},
    DuplicatePages(:final pageIds) => pageIds.toSet(),
    CompositeCommand(:final commands) => {
      for (final sub in commands) ..._pagesNeeded(sub),
    },
    InsertPages() ||
    DeletePages() ||
    MovePages() ||
    SetPageBackground() ||
    ResizePages() => const {},
  };

  /// Pins every known page of [ids]; always awaits at least once (N-2).
  Future<List<PageId>> _pin(Iterable<PageId> ids) async {
    await Future<void>.value();
    final pinned = <PageId>[];
    try {
      for (final id in ids) {
        if (!_pagesById.containsKey(id)) continue;
        await openPage(id);
        pinned.add(id);
      }
    } on Object {
      _unpin(pinned);
      rethrow;
    }
    return pinned;
  }

  void _unpin(List<PageId> pinned) => pinned.forEach(closePage);

  // ---- undo / redo ----------------------------------------------------------------

  @override
  Future<UndoRedoResult> undo() => _undoRedo(redo: false);

  @override
  Future<UndoRedoResult> redo() => _undoRedo(redo: true);

  Future<UndoRedoResult> _undoRedo({required bool redo}) async {
    _checkOpen();
    _checkWritable();
    var skippedEntries = 0;
    while (true) {
      final entry = redo ? _history.redoTop : _history.undoTop;
      if (entry == null) {
        return UndoRedoResult(applied: false, skippedEntries: skippedEntries);
      }
      final gen = _generation;
      final pins = await _pin(_strokePagesOf(entry.edit));
      try {
        _checkOpen();
        _checkWritable();
        // A new edit happened meanwhile: this undo/redo is cancelled (6.7.2).
        if (gen != _generation) {
          return UndoRedoResult(applied: false, skippedEntries: skippedEntries);
        }
        final top = redo ? _history.redoTop : _history.undoTop;
        if (!identical(top, entry)) continue; // another undo/redo went first
        final result = _applyStep(entry, redo: redo);
        if (result == null) {
          redo ? _history.dropRedoTop() : _history.dropUndoTop();
          skippedEntries++;
          _emitHistory();
          continue;
        }
        return UndoRedoResult(
          applied: true,
          edit: result.$1,
          skippedEntities: result.$2,
          skippedEntries: skippedEntries,
        );
      } finally {
        _unpin(pins);
      }
    }
  }

  Set<PageId> _strokePagesOf(AppliedEdit edit) => {
    for (final d in edit.deltas)
      if (d.after case final Stroke s) s.pageId,
  };

  /// Applies one history step; null when every entity was skipped (no-op entry).
  (AppliedEdit, int)? _applyStep(HistoryEntry entry, {required bool redo}) {
    final now = _clock.now().millisecondsSinceEpoch;
    final v = _hlc.now();
    final written = <EntityDelta>[];
    final fields = <EntityRef, Set<String>>{};
    final expected = <EntityRef, Hlc?>{};
    final skip = <EntityRef>{...entry.skip};
    var skipped = 0;
    final deltas = redo ? entry.edit.deltas : entry.edit.deltas.reversed;
    for (final d in deltas) {
      final ref = EntityRef(d.kind, d.id);
      final cur = _current(d);
      if (cur == null ||
          skip.contains(ref) ||
          _history.canonical(ref, cur.version) != entry.expected[ref]) {
        // Changed by someone else since (6.7.3): this entity is left alone.
        skipped++;
        skip.add(ref);
        continue;
      }
      final SyncEntity target;
      final Hlc? canonicalOf;
      if (redo) {
        target = _restamp(d.after!, now, v);
        canonicalOf = d.after!.version;
      } else if (d.before == null) {
        target = _deleted(cur, now, v);
        canonicalOf = null;
      } else {
        target = _restamp(d.before!, now, v);
        canonicalOf = d.before!.version;
      }
      final changed = changedFieldsOf(cur, target);
      if (changed.isEmpty) {
        expected[ref] = _history.canonical(ref, cur.version);
        continue;
      }
      written.add(
        EntityDelta(kind: d.kind, id: d.id, before: cur, after: target),
      );
      fields[ref] = changed;
      _history.alias(ref, v, canonicalOf);
      expected[ref] = _history.canonical(ref, v);
    }
    if (written.isEmpty) return null;
    entry
      ..expected = expected
      ..skip = skip;
    redo ? _history.moveRedoTopToUndo() : _history.moveUndoTopToRedo();
    final applied = _install([for (final w in written) w.after!], now);
    final origin = redo ? ChangeOrigin.redo : ChangeOrigin.undo;
    unawaited(_write(origin, applied, fields));
    _emit(applied, origin);
    final edit = AppliedEdit(
      label: entry.edit.label,
      deltas: List.unmodifiable(written),
      version: v,
      affectedPageIds: Set.unmodifiable({
        for (final w in written)
          if (w.after case Stroke(:final pageId)) pageId else w.id,
      }),
    );
    return (edit, skipped);
  }

  SyncEntity? _current(EntityDelta d) {
    final ref = EntityRef(d.kind, d.id);
    final sample = d.after ?? d.before;
    if (sample is Page) return _pagesById[d.id];
    if (sample is Stroke) {
      return _loaded[sample.pageId]?.byId[d.id] ?? _tombstones[ref];
    }
    return null;
  }

  static SyncEntity _restamp(SyncEntity e, EpochMillis now, Hlc v) =>
      switch (e) {
        Stroke() => e.copyWith(updatedAt: now, version: v),
        Page() => e.copyWith(updatedAt: now, version: v),
        _ => throw StateError('History holds an unexpected ${e.kind.name}'),
      };

  static SyncEntity _deleted(SyncEntity e, EpochMillis now, Hlc v) =>
      switch (e) {
        Stroke() => e.copyWith(deletedAt: now, updatedAt: now, version: v),
        Page() => e.copyWith(deletedAt: now, updatedAt: now, version: v),
        _ => throw StateError('History holds an unexpected ${e.kind.name}'),
      };

  @override
  void clearHistory() {
    if (_closed) return;
    _history.clear();
    _tombstones.clear();
    _emitHistory();
  }

  // ---- memory update + events ----------------------------------------------------

  _Applied _install(List<SyncEntity> afters, EpochMillis now) {
    final a = _Applied();
    final created = <PageId>{};
    for (final e in afters) {
      final ref = EntityRef(e.kind, e.id);
      switch (e) {
        case Stroke():
          final l = _loaded[e.pageId];
          if (l != null) {
            final diff = a.diffs[e.pageId] ??= _PageDiff();
            final old = l.byId[e.id];
            if (e.isDeleted) {
              if (old != null) {
                l.byId.remove(e.id);
                diff.removed.add(e.id);
              }
            } else {
              l.byId[e.id] = e;
              if (old == null) {
                diff.added.add(e.id);
              } else {
                diff.updated.add(e.id);
                if (old.createdAt != e.createdAt) diff.orderChanged = true;
              }
            }
          }
          if (e.isDeleted) {
            _tombstones[ref] = e;
          } else {
            _tombstones.remove(ref);
          }
          a.bumped.add(e.pageId);
          a.written.add(e);
        case Page():
          final old = _pagesById[e.id];
          final page = e.copyWith(contentRevision: old?.contentRevision ?? 0);
          _pagesById[e.id] = page;
          if (old == null) {
            created.add(e.id);
          } else if (old.size != page.size ||
              old.background != page.background) {
            a.bumped.add(e.id);
          }
          if (_loaded.containsKey(e.id)) {
            (a.diffs[e.id] ??= _PageDiff()).pageChanged = true;
          }
        default:
          throw StateError('A session cannot write a ${e.kind.name}');
      }
    }
    a.bumped.removeAll(created);
    for (final id in a.bumped) {
      final p = _pagesById[id];
      if (p == null) continue;
      _pagesById[id] = p.copyWith(contentRevision: p.contentRevision + 1);
      if (_loaded.containsKey(id)) a.diffs[id] ??= _PageDiff();
    }
    for (final e in afters) {
      if (e is Page) a.written.add(_pagesById[e.id]!);
    }
    // Active page list (N-1 v1.1: a changed Page value is a change of the list).
    final active = _sortedActive();
    if (active.length != _active.length ||
        Iterable<int>.generate(active.length)
            .any((i) => !identical(active[i], _active[i]))) {
      _active = active;
      a.pagesChanged = true;
    }
    // Loaded page contents.
    for (final entry in a.diffs.entries) {
      final l = _loaded[entry.key]!;
      _resort(l, entry.value);
      l.content = PageContent(
        page: _pagesById[entry.key]!,
        strokes: l.sorted,
        revision: l.content.revision + 1,
      );
    }
    // Note: local derived values (C-9).
    final first = _active.isEmpty ? null : _active.first.id;
    final note = _note.copyWith(
      updatedAt: math.max(now, _note.updatedAt),
      pageCount: _active.length,
      firstPageId: first,
      clearFirstPageId: first == null,
    );
    if (note != _note) {
      _note = note;
      a.noteChanged = true;
    }
    return a;
  }

  void _resort(_Loaded l, _PageDiff d) {
    if (d.orderChanged) {
      l.sorted
        ..clear()
        ..addAll(l.byId.values)
        ..sort(Stroke.compareOrder);
      return;
    }
    if (d.removed.isNotEmpty) {
      l.sorted.removeWhere((s) => d.removed.contains(s.id));
    }
    if (d.updated.isNotEmpty) {
      for (var i = 0; i < l.sorted.length; i++) {
        final id = l.sorted[i].id;
        if (d.updated.contains(id)) l.sorted[i] = l.byId[id]!;
      }
    }
    for (final id in d.added) {
      final s = l.byId[id]!;
      var lo = 0, hi = l.sorted.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (Stroke.compareOrder(l.sorted[mid], s) < 0) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      l.sorted.insert(lo, s);
    }
  }

  List<Page> _sortedActive() => List.unmodifiable(
    _pagesById.values.where((p) => !p.isDeleted).toList()..sort(comparePages),
  );

  Future<void> _write(
    ChangeOrigin origin,
    _Applied a,
    Map<EntityRef, Set<String>> fields,
  ) {
    final writtenPages = {
      for (final e in a.written)
        if (e is Page) e.id,
    };
    return backend.write(
      SessionWrite(
        origin: origin,
        entities: List.unmodifiable(a.written),
        changedFields: fields,
        localPages: [
          for (final id in a.bumped)
            if (!writtenPages.contains(id) && _pagesById[id] != null)
              _pagesById[id]!,
        ],
        note: _note,
      ),
    );
  }

  void _emit(_Applied a, ChangeOrigin origin) {
    _dispatch(() {
      for (final e in a.diffs.entries) {
        final l = _loaded[e.key];
        if (!(_pageCtrls[e.key]?.hasListener ?? false) || l == null) continue;
        final d = e.value;
        _pageCtrls[e.key]!.add(
          PageContentChange(
            content: l.content,
            origin: origin,
            added: Set.unmodifiable(d.added),
            removed: Set.unmodifiable(d.removed),
            updated: Set.unmodifiable(d.updated),
            pageChanged: d.pageChanged,
          ),
        );
      }
      if (a.pagesChanged) _pagesCtrl.add(_active);
      _emitHistoryLocked();
      if (a.noteChanged) _noteCtrl.add(_note);
    });
  }

  void _emitHistory() => _dispatch(_emitHistoryLocked);

  void _emitHistoryLocked() {
    final state = _history.state;
    if (state == _lastHistory) return;
    _lastHistory = state;
    _historyCtrl.add(state);
  }

  void _dispatch(void Function() fire) {
    final outer = _dispatching;
    _dispatching = true;
    try {
      fire();
    } finally {
      _dispatching = outer;
    }
  }

  /// N-7: a remote write (applyRemote, commitRepairs) committed rows of this note. The
  /// store passes the committed values read back: [pages] (null = row gone), the strokes
  /// of loaded pages in [strokes] (stroke id → its page and row, null row = gone), and
  /// [contentPages], the pages whose strokes changed. Not in the history; a later undo
  /// skips these entities (their versions changed, 6.7.3).
  void remoteCommitted({
    Note? note,
    Map<PageId, Page?> pages = const {},
    Map<ElementId, (PageId, Stroke?)> strokes = const {},
    Set<PageId> contentPages = const {},
  }) {
    if (_closed) return;
    final diffs = <PageId, _PageDiff>{};
    final bumped = <PageId>{...contentPages};
    for (final MapEntry(key: id, value: row) in pages.entries) {
      final old = _pagesById[id];
      bumped.remove(id);
      if (row == null || row.noteId != noteId) {
        if (old != null) {
          _pagesById.remove(id);
          _loaded.remove(id);
        }
        continue;
      }
      // Local revision: current + 1 (6.10.3 (d)), never below the stored value.
      final rev = old == null
          ? row.contentRevision
          : math.max(row.contentRevision, old.contentRevision + 1);
      _pagesById[id] = row.copyWith(contentRevision: rev);
      if (_loaded.containsKey(id)) {
        (diffs[id] ??= _PageDiff()).pageChanged = true;
      }
    }
    for (final MapEntry(key: id, value: (pageId, row)) in strokes.entries) {
      final l = _loaded[pageId];
      if (l == null) continue;
      final diff = diffs[pageId] ??= _PageDiff();
      final old = l.byId[id];
      final ref = EntityRef(EntityKind.stroke, id);
      if (row == null || row.isDeleted || row.pageId != pageId) {
        if (old != null) {
          l.byId.remove(id);
          diff.removed.add(id);
        }
        if (row != null && row.isDeleted) {
          _tombstones[ref] = row;
        } else {
          _tombstones.remove(ref);
        }
        continue;
      }
      _tombstones.remove(ref);
      l.byId[id] = row;
      if (old == null) {
        diff.added.add(id);
      } else {
        diff.updated.add(id);
        if (old.createdAt != row.createdAt) diff.orderChanged = true;
      }
    }
    for (final id in bumped) {
      final p = _pagesById[id];
      if (p == null) continue;
      _pagesById[id] = p.copyWith(contentRevision: p.contentRevision + 1);
      if (_loaded.containsKey(id)) diffs[id] ??= _PageDiff();
    }
    final a = _Applied();
    final active = _sortedActive();
    if (active.length != _active.length ||
        Iterable<int>.generate(active.length)
            .any((i) => !identical(active[i], _active[i]))) {
      _active = active;
      a.pagesChanged = true;
    }
    for (final MapEntry(key: id, value: d) in diffs.entries) {
      final l = _loaded[id];
      if (l == null) continue;
      _resort(l, d);
      l.content = PageContent(
        page: _pagesById[id]!,
        strokes: l.sorted,
        revision: l.content.revision + 1,
      );
      a.diffs[id] = d;
    }
    final base = note ?? _note;
    final first = _active.isEmpty ? null : _active.first.id;
    final merged = base.copyWith(
      updatedAt: math.max(base.updatedAt, _note.updatedAt),
      pageCount: _active.length,
      firstPageId: first,
      clearFirstPageId: first == null,
    );
    if (merged != _note) {
      _note = merged;
      a.noteChanged = true;
    }
    _emit(a, ChangeOrigin.remote);
  }

  /// The store committed a change of the note row (rename, trash, restore, ...).
  void noteCommitted(Note stored) {
    if (_closed) return;
    final first = _active.isEmpty ? null : _active.first.id;
    final merged = stored.copyWith(
      updatedAt: math.max(stored.updatedAt, _note.updatedAt),
      pageCount: _active.length,
      firstPageId: first,
      clearFirstPageId: first == null,
    );
    if (merged == _note) return;
    _note = merged;
    _dispatch(() => _noteCtrl.add(_note));
  }

  // ---- lifecycle ----------------------------------------------------------------

  @override
  Future<void> flush() => backend.flush();

  @override
  Future<void> close() async {
    if (_closed) return;
    _refs--;
    if (_refs > 0) return;
    _closed = true;
    backend.sessionClosed(noteId);
    await backend.flush();
    _loaded.clear();
    _tombstones.clear();
    _history.clear();
    for (final c in _pageCtrls.values) {
      unawaited(c.close());
    }
    _pageCtrls.clear();
    unawaited(_noteCtrl.close());
    unawaited(_pagesCtrl.close());
    unawaited(_historyCtrl.close());
  }

  void _checkOpen() {
    if (_closed) {
      throw SessionClosedException('Session of note $noteId is closed');
    }
  }

  void _checkWritable() {
    if (isReadOnly) {
      throw ReadOnlyNoteException(
        _note.requiresNewerApp
            ? 'Note $noteId was written by a newer app version'
            : 'Note $noteId is in the trash',
      );
    }
  }
}

/// JSON keys whose values differ between two versions of an entity, meta keys excluded
/// (CORE 6.7.6). Strokes and pages are compared field by field (no point encoding).
Set<String> changedFieldsOf(SyncEntity a, SyncEntity b) {
  if (a is Stroke && b is Stroke) {
    return {
      if (a.pageId != b.pageId) 'pageId',
      if (a.style != b.style) 'style',
      if (!identical(a.points, b.points) && !a.points.contentEquals(b.points))
        'points',
      if (a.recordingId != b.recordingId) 'recordingId',
      if (a.recordingOffsetMs != b.recordingOffsetMs) 'recordingOffsetMs',
      if (a.deletedAt != b.deletedAt) 'deletedAt',
    };
  }
  if (a is Page && b is Page) {
    return {
      if (a.noteId != b.noteId) 'noteId',
      if (a.sortKey != b.sortKey) 'sortKey',
      if (a.size != b.size) 'size',
      if (a.background != b.background) 'background',
      if (a.deletedAt != b.deletedAt) 'deletedAt',
    };
  }
  const meta = {'id', 'key', 'version', 'createdAt', 'updatedAt'};
  final ja = a.toJson(), jb = b.toJson();
  return {
    for (final k in {...ja.keys, ...jb.keys})
      if (!meta.contains(k) && '${ja[k]}' != '${jb[k]}') k,
  };
}
