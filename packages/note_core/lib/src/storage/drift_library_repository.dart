// lib/src/storage/drift_library_repository.dart (internal) — LibraryRepository on SQLite
// (CORE 6.8, behaviour contract C-1..C-10 of 4.5).
//
// Same meaning as the fake store's library (test/shared/library_contract.dart runs on
// both). Every mutation is one write-queue job: argument errors are thrown before
// enqueue, state errors (EntityNotFoundException, FolderCycleException) inside the
// job, which rolls back only that job (savepoint) and is never retried. Watch streams
// re-query after every commit that wrote folders or notes (WatchHub).
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../common/errors.dart';
import '../common/ids.dart';
import '../common/sort_keys.dart';
import '../common/sort_planner.dart';
import '../common/text_normalize.dart';
import '../edit/command_resolver.dart';
import '../edit/page_draft.dart';
import '../model/folder.dart';
import '../model/note.dart';
import '../model/page.dart';
import '../model/stroke.dart';
import '../model/sync_entity.dart';
import '../repo/folder_tree.dart';
import '../repo/folder_tree_equality.dart';
import '../repo/library_repository.dart';
import '../repo/library_types.dart';
import '../sync/outbox_types.dart';
import 'db/note_database.dart';
import 'drift_note_store.dart';
import 'entity_diff.dart';
import 'row_mappers.dart';
import 'watch_hub.dart';
import 'write_queue.dart';

/// Strokes read per query when a note is copied (6.8).
const int kCopyStrokeChunk = 2000;

/// C-6: trimmed, String.length 1..[max].
String checkLibraryName(String name, {int max = 200, String what = 'name'}) {
  final t = name.trim();
  if (t.isEmpty || t.length > max) {
    throw ArgumentError.value(
      name,
      what,
      'must be 1..$max characters after trim',
    );
  }
  return t;
}

void _checkIcon(String? icon) {
  if (icon != null && icon.length > 32) {
    throw ArgumentError.value(icon, 'icon', 'at most 32 characters');
  }
}

/// C-5: [name] + [suffix] within [max] code units; the original name is cut, never in
/// the middle of a surrogate pair.
String nameWithSuffix(String name, String suffix, {int max = 200}) {
  if (name.length + suffix.length <= max) return name + suffix;
  var cut = max - suffix.length;
  if (cut > 0 && cut < name.length) {
    final unit = name.codeUnitAt(cut - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) cut--;
  }
  return name.substring(0, cut.clamp(0, name.length)) + suffix;
}

/// The LIKE pattern of a normalized query: `%`, `_` and `\` escaped with `\` (6.8).
String likeContains(String normalized) {
  final escaped = normalized
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}

bool _touchesLibrary(CommitTouch t) =>
    t.kinds.contains(EntityKind.folder) || t.kinds.contains(EntityKind.note);

bool _touchesFolders(CommitTouch t) => t.kinds.contains(EntityKind.folder);

bool _touchesNotes(CommitTouch t) => t.kinds.contains(EntityKind.note);

const ListEquality<Note> _notesEq = ListEquality<Note>();

/// Listing order of 6.8: name → normalized name then id, created/updated → value then
/// id (both reversed when descending), custom → (sortKey, id).
int Function(T, T) listingOrder<T>(
  LibraryQuery q, {
  required String Function(T) norm,
  required int Function(T) createdAt,
  required int Function(T) updatedAt,
  required String Function(T) sortKey,
  required String Function(T) id,
}) {
  int then(int c, T a, T b) => c != 0 ? c : id(a).compareTo(id(b));
  final sign = q.sort != LibrarySortField.custom && q.descending ? -1 : 1;
  return (a, b) =>
      sign *
      switch (q.sort) {
        LibrarySortField.name => then(norm(a).compareTo(norm(b)), a, b),
        LibrarySortField.createdAt => then(
          createdAt(a).compareTo(createdAt(b)),
          a,
          b,
        ),
        LibrarySortField.updatedAt => then(
          updatedAt(a).compareTo(updatedAt(b)),
          a,
          b,
        ),
        LibrarySortField.custom => compareSortKeyThenId(
          sortKey(a),
          id(a),
          sortKey(b),
          id(b),
        ),
      };
}

final class DriftLibraryRepository implements LibraryRepository {
  DriftLibraryRepository(this.s);
  final DriftNoteStore s;

  NoteDatabase get _db => s.db;
  WriteQueue get _q => s.queue;
  OwnerId get _owner => s.ownerId;

  // ---- reads ---------------------------------------------------------------------

  Future<FolderRow?> _folderRow(FolderId id) =>
      (_db.select(_db.folders)
            ..where((t) => t.id.equals(id) & t.ownerId.equals(_owner)))
          .getSingleOrNull();

  Future<NoteRow?> _noteRow(NoteId id) =>
      (_db.select(_db.notes)
            ..where((t) => t.id.equals(id) & t.ownerId.equals(_owner)))
          .getSingleOrNull();

  Future<FolderRow?> _activeFolderRow(FolderId id) =>
      (_db.select(_db.folders)..where(
            (t) =>
                t.id.equals(id) &
                t.ownerId.equals(_owner) &
                t.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  Future<NoteRow?> _activeNoteRow(NoteId id) =>
      (_db.select(_db.notes)..where(
            (t) =>
                t.id.equals(id) &
                t.ownerId.equals(_owner) &
                t.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  /// Active folders of the current owner (the FolderTree input).
  Future<List<Folder>> activeFolders() async {
    final rows = await (_db.select(
      _db.folders,
    )..where((t) => t.ownerId.equals(_owner) & t.deletedAt.isNull())).get();
    return [for (final r in rows) folderOf(r)];
  }

  Future<FolderTree> _tree() async => FolderTree(await activeFolders());

  /// Active direct children of [parent] (exactly that parent; null = parentId NULL).
  Future<List<FolderRow>> _childFolderRows(FolderId? parent) =>
      (_db.select(_db.folders)..where(
            (t) =>
                t.ownerId.equals(_owner) &
                t.deletedAt.isNull() &
                (parent == null
                    ? t.parentId.isNull()
                    : t.parentId.equals(parent)),
          ))
          .get();

  Future<List<NoteRow>> _childNoteRows(FolderId? parent) =>
      (_db.select(_db.notes)..where(
            (t) =>
                t.ownerId.equals(_owner) &
                t.deletedAt.isNull() &
                (parent == null
                    ? t.folderId.isNull()
                    : t.folderId.equals(parent)),
          ))
          .get();

  Future<List<String>> _folderKeys(FolderId? parent) async => [
    for (final r in await _childFolderRows(parent)) r.sortKey,
  ];

  Future<List<String>> _noteKeys(FolderId? parent) async => [
    for (final r in await _childNoteRows(parent)) r.sortKey,
  ];

  static String? _maxKey(Iterable<String> keys) {
    String? max;
    for (final k in keys) {
      if (max == null || k.compareTo(max) > 0) max = k;
    }
    return max;
  }

  /// Ids of the active folders of the owner, as a sub-select (top-level listing).
  BaseSelectStatement<TypedResult> _activeFolderIds() {
    final p = _db.alias(_db.folders, 'p');
    return _db.selectOnly(p)
      ..addColumns([p.id])
      ..where(p.ownerId.equals(_owner) & p.deletedAt.isNull());
  }

  // ---- queries ----------------------------------------------------------------------

  @override
  Stream<FolderTree> watchFolderTree() => s.watches.watch(
    affects: _touchesFolders,
    query: _tree,
    equals: sameFolderTree,
  );

  @override
  Stream<LibraryListing> watchListing(LibraryQuery query) =>
      s.watches.watch(affects: _touchesLibrary, query: () => _listing(query));

  Future<LibraryListing> _listing(LibraryQuery q) async {
    final folderId = q.folderId;
    final f = _db.folders;
    final n = _db.notes;
    final Expression<bool> fPlace;
    final Expression<bool> nPlace;
    if (folderId != null) {
      if (await _activeFolderRow(folderId) == null) {
        return LibraryListing(
          folderId: folderId,
          folders: const [],
          notes: const [],
        );
      }
      fPlace = f.parentId.equals(folderId);
      nPlace = n.folderId.equals(folderId);
    } else {
      // Top level also lists items whose parent is missing or trashed (6.8).
      fPlace =
          f.parentId.isNull() | f.parentId.isNotInQuery(_activeFolderIds());
      nPlace =
          n.folderId.isNull() | n.folderId.isNotInQuery(_activeFolderIds());
    }
    final fRows =
        await (_db.select(f)..where(
              (t) => t.ownerId.equals(_owner) & t.deletedAt.isNull() & fPlace,
            ))
            .get();
    final nRows =
        await (_db.select(n)..where(
              (t) => t.ownerId.equals(_owner) & t.deletedAt.isNull() & nPlace,
            ))
            .get();
    fRows.sort(
      listingOrder<FolderRow>(
        q,
        norm: (r) => r.nameNorm,
        createdAt: (r) => r.createdAt,
        updatedAt: (r) => r.updatedAt,
        sortKey: (r) => r.sortKey,
        id: (r) => r.id,
      ),
    );
    nRows.sort(
      listingOrder<NoteRow>(
        q,
        norm: (r) => r.titleNorm,
        createdAt: (r) => r.createdAt,
        updatedAt: (r) => r.updatedAt,
        sortKey: (r) => r.sortKey,
        id: (r) => r.id,
      ),
    );
    return LibraryListing(
      folderId: folderId,
      folders: List.unmodifiable([for (final r in fRows) folderOf(r)]),
      notes: List.unmodifiable([for (final r in nRows) noteOf(r)]),
    );
  }

  @override
  Stream<Note?> watchNote(NoteId id) =>
      s.watches.watch(affects: _touchesNotes, query: () => getNote(id));

  @override
  Future<Note?> getNote(NoteId id) async {
    final r = await _noteRow(id);
    return r == null ? null : noteOf(r);
  }

  @override
  Future<Folder?> getFolder(FolderId id) async {
    final r = await _folderRow(id);
    return r == null ? null : folderOf(r);
  }

  @override
  Stream<List<Note>> watchRecentNotes({int limit = 20}) => s.watches.watch(
    affects: _touchesNotes,
    query: () async {
      final rows =
          await (_db.select(_db.notes)
                ..where(
                  (t) =>
                      t.ownerId.equals(_owner) &
                      t.deletedAt.isNull() &
                      t.lastOpenedAt.isNotNull(),
                )
                ..orderBy([
                  (t) => OrderingTerm.desc(t.lastOpenedAt),
                  (t) => OrderingTerm.asc(t.id),
                ])
                ..limit(limit))
              .get();
      return List<Note>.unmodifiable([for (final r in rows) noteOf(r)]);
    },
    equals: _notesEq.equals,
  );

  @override
  Stream<List<Note>> watchFavoriteNotes() => s.watches.watch(
    affects: _touchesNotes,
    query: () async {
      final rows =
          await (_db.select(_db.notes)
                ..where(
                  (t) =>
                      t.ownerId.equals(_owner) &
                      t.deletedAt.isNull() &
                      t.isFavorite.equals(true),
                )
                ..orderBy([
                  (t) => OrderingTerm.desc(t.updatedAt),
                  (t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      return List<Note>.unmodifiable([for (final r in rows) noteOf(r)]);
    },
    equals: _notesEq.equals,
  );

  @override
  Future<LibrarySearchResult> searchLibrary(
    String query, {
    int limit = 50,
  }) async {
    final q = normalizeForSearch(query);
    if (q.isEmpty) {
      return LibrarySearchResult(
        query: query,
        folders: const [],
        notes: const [],
      );
    }
    final pattern = likeContains(q);
    final fRows =
        await (_db.select(_db.folders)
              ..where(
                (t) =>
                    t.ownerId.equals(_owner) &
                    t.deletedAt.isNull() &
                    t.nameNorm.like(pattern, escapeChar: r'\'),
              )
              ..orderBy([
                (t) => OrderingTerm.desc(t.updatedAt),
                (t) => OrderingTerm.asc(t.id),
              ])
              ..limit(limit))
            .get();
    final nRows =
        await (_db.select(_db.notes)
              ..where(
                (t) =>
                    t.ownerId.equals(_owner) &
                    t.deletedAt.isNull() &
                    t.titleNorm.like(pattern, escapeChar: r'\'),
              )
              ..orderBy([
                (t) => OrderingTerm.desc(t.updatedAt),
                (t) => OrderingTerm.asc(t.id),
              ])
              ..limit(limit))
            .get();
    return LibrarySearchResult(
      query: query,
      folders: List.unmodifiable([for (final r in fRows) folderOf(r)]),
      notes: List.unmodifiable([for (final r in nRows) noteOf(r)]),
    );
  }

  // ---- write helpers ------------------------------------------------------------------

  Future<void> _requireTarget(FolderId? id) async {
    if (id != null && await _activeFolderRow(id) == null) {
      throw EntityNotFoundException('Folder $id does not exist');
    }
  }

  Future<Folder> _folder(FolderId id) async {
    final r = await _folderRow(id);
    if (r == null) throw EntityNotFoundException('Folder $id does not exist');
    return folderOf(r);
  }

  Future<Note> _note(NoteId id) async {
    final r = await _noteRow(id);
    if (r == null) throw EntityNotFoundException('Note $id does not exist');
    return noteOf(r);
  }

  /// Writes [next] when it differs from [before]; updatedAt = the transaction time.
  Future<void> _putFolder(WriteTxn tx, Folder before, Folder next) async {
    final fields = changedJsonKeys(before, next);
    if (fields.isEmpty) return;
    await tx.putLocal(next.copyWith(updatedAt: tx.now), fields);
  }

  Future<void> _putNote(WriteTxn tx, Note before, Note next) async {
    final fields = changedJsonKeys(before, next);
    if (fields.isEmpty) return;
    await tx.putLocal(next.copyWith(updatedAt: tx.now), fields);
  }

  ({List<Folder> folders, List<Note> notes}) _sorted(
    List<Folder> fs,
    List<Note> ns,
  ) {
    fs.sort((a, b) => compareSortKeyThenId(a.sortKey, a.id, b.sortKey, b.id));
    ns.sort((a, b) => compareSortKeyThenId(a.sortKey, a.id, b.sortKey, b.id));
    return (folders: fs, notes: ns);
  }

  /// The active items of [items] (each id once), sorted by (sortKey, id); a missing or
  /// trashed item is EntityNotFoundException.
  Future<({List<Folder> folders, List<Note> notes})> _resolveActive(
    List<LibraryItemRef> items,
  ) async {
    final fs = <Folder>[];
    final ns = <Note>[];
    for (final ref in items.toSet()) {
      switch (ref) {
        case FolderRef(:final id):
          final r = await _activeFolderRow(id);
          if (r == null) {
            throw EntityNotFoundException('Folder $id does not exist');
          }
          fs.add(folderOf(r));
        case NoteRef(:final id):
          final r = await _activeNoteRow(id);
          if (r == null) {
            throw EntityNotFoundException('Note $id does not exist');
          }
          ns.add(noteOf(r));
      }
    }
    return _sorted(fs, ns);
  }

  // ---- folders ------------------------------------------------------------------------

  @override
  Future<Folder> createFolder({
    FolderId? parentId,
    required String name,
    int? colorArgb,
    String? icon,
  }) async {
    final n = checkLibraryName(name);
    _checkIcon(icon);
    return _q.run((tx) async {
      await _requireTarget(parentId);
      final f = Folder(
        id: s.ids.newId(),
        ownerId: _owner,
        parentId: parentId,
        name: n,
        colorArgb: colorArgb,
        icon: icon,
        sortKey: sortKeyAfterAll(await _folderKeys(parentId)),
        createdAt: tx.now,
        updatedAt: tx.now,
      );
      final v = await tx.putLocal(f, const {kAllFields}, isNew: true);
      return f.copyWith(version: v.max);
    });
  }

  @override
  Future<void> renameFolder(FolderId id, String name) async {
    final n = checkLibraryName(name);
    return _q.run((tx) async {
      final f = await _folder(id);
      await _putFolder(tx, f, f.copyWith(name: n));
    });
  }

  @override
  Future<void> setFolderAppearance(
    FolderId id, {
    int? colorArgb,
    String? icon,
    bool clearColor = false,
    bool clearIcon = false,
  }) async {
    _checkIcon(icon);
    return _q.run((tx) async {
      final f = await _folder(id);
      await _putFolder(
        tx,
        f,
        f.copyWith(
          colorArgb: colorArgb,
          clearColor: clearColor,
          icon: icon,
          clearIcon: clearIcon,
        ),
      );
    });
  }

  // ---- notes --------------------------------------------------------------------------

  @override
  Future<Note> createNote({
    FolderId? folderId,
    required String title,
    List<PageDraft> pages = const [PageDraft.blankA4],
    NoteCover cover = const FirstPageCover(),
  }) async {
    final t = checkLibraryName(title, what: 'title');
    if (pages.isEmpty || pages.length > 2000) {
      throw ArgumentError.value(
        pages.length,
        'pages',
        'must be 1..2000 drafts',
      );
    }
    final draftIds = <PageId>[];
    var bytes = 0;
    for (final d in pages) {
      final id = d.id;
      if (id != null) {
        if (!isValidEntityId(id)) {
          throw ArgumentError.value(id, 'draft.id', 'invalid entity id');
        }
        draftIds.add(id);
      }
      for (final st in d.strokes) {
        bytes += st.points.length * 8;
      }
    }
    if (draftIds.toSet().length != draftIds.length) {
      throw ArgumentError('Draft page ids must be new and unique');
    }
    return _q.run((tx) async {
      await _requireTarget(folderId);
      if (draftIds.isNotEmpty) {
        final taken =
            await (_db.selectOnly(_db.pages)
                  ..addColumns([_db.pages.id])
                  ..where(_db.pages.id.isIn(draftIds))
                  ..limit(1))
                .get();
        if (taken.isNotEmpty) {
          throw ArgumentError('Draft page ids must be new and unique');
        }
      }
      final noteId = s.ids.newId();
      final pageIds = [for (final d in pages) d.id ?? s.ids.newId()];
      final note = Note(
        id: noteId,
        ownerId: _owner,
        folderId: folderId,
        title: t,
        cover: cover,
        sortKey: sortKeyAfterAll(await _noteKeys(folderId)),
        createdAt: tx.now,
        updatedAt: tx.now,
        pageCount: pages.length,
        firstPageId: pageIds.first,
      );
      final v = await tx.putLocal(note, const {kAllFields}, isNew: true);
      final keys = SortKeys.nBetween(null, null, pages.length);
      for (var i = 0; i < pages.length; i++) {
        final d = pages[i];
        await tx.putLocal(
          Page(
            id: pageIds[i],
            noteId: noteId,
            sortKey: keys[i],
            size: d.size.clamped(),
            background: d.background,
            createdAt: tx.now,
            updatedAt: tx.now,
          ),
          const {kAllFields},
          isNew: true,
        );
        for (final st in d.strokes) {
          await tx.putLocal(
            Stroke(
              id: s.ids.newId(),
              pageId: pageIds[i],
              style: st.style.normalized(),
              points: st.points,
              recordingId: st.recordingId,
              recordingOffsetMs: st.recordingOffsetMs,
              createdAt: st.createdAt,
              updatedAt: tx.now,
            ),
            const {kAllFields},
            strokeNoteId: noteId,
            isNew: true,
          );
        }
      }
      return note.copyWith(version: v.max);
    }, bytes: bytes);
  }

  @override
  Future<void> renameNote(NoteId id, String title) async {
    final t = checkLibraryName(title, what: 'title');
    return _q.run((tx) async {
      final n = await _note(id);
      await _putNote(tx, n, n.copyWith(title: t));
    });
  }

  @override
  Future<void> setFavorite(List<NoteId> ids, bool favorite) =>
      _q.run((tx) async {
        for (final id in ids.toSet()) {
          final r = await _noteRow(id);
          if (r == null || r.isFavorite == favorite) continue;
          final n = noteOf(r);
          await _putNote(tx, n, n.copyWith(isFavorite: favorite));
        }
      });

  @override
  Future<void> setCover(NoteId id, NoteCover cover) => _q.run((tx) async {
    final n = await _note(id);
    await _putNote(tx, n, n.copyWith(cover: cover));
  });

  @override
  Future<void> setTags(NoteId id, List<String> tags) async {
    final clean = [for (final t in tags) t.trim()];
    if (clean.length > 50 || clean.any((t) => t.isEmpty || t.length > 32)) {
      throw ArgumentError.value(
        tags,
        'tags',
        'at most 50 tags of 1..32 characters',
      );
    }
    return _q.run((tx) async {
      final n = await _note(id);
      await _putNote(tx, n, n.copyWith(tags: List.unmodifiable(clean)));
    });
  }

  @override
  Future<void> markOpened(NoteId id) => _q.run((tx) async {
    final n = await _note(id);
    // Local only (N-6): no version bump, no outbox, no ChangeBatch entry.
    await tx.putLocal(n.copyWith(lastOpenedAt: tx.now), const {'lastOpenedAt'});
  });

  // ---- mixed --------------------------------------------------------------------------

  @override
  Future<void> moveItems(
    List<LibraryItemRef> items, {
    required FolderId? targetFolderId,
  }) => _q.run((tx) async {
    await _requireTarget(targetFolderId);
    final r = await _resolveActive(items);
    if (targetFolderId != null && r.folders.isNotEmpty) {
      final tree = await _tree();
      for (final f in r.folders) {
        if (tree.isSelfOrDescendant(targetFolderId, of: f.id)) {
          throw FolderCycleException(
            'Folder ${f.id} cannot move into itself or its descendant '
            '$targetFolderId',
          );
        }
      }
    }
    final fs = [
      for (final f in r.folders)
        if (f.parentId != targetFolderId) f,
    ];
    final ns = [
      for (final n in r.notes)
        if (n.folderId != targetFolderId) n,
    ];
    if (fs.isNotEmpty) {
      final keys = SortKeys.nBetween(
        _maxKey(await _folderKeys(targetFolderId)),
        null,
        fs.length,
      );
      for (var i = 0; i < fs.length; i++) {
        await _putFolder(
          tx,
          fs[i],
          fs[i].copyWith(
            parentId: targetFolderId,
            clearParentId: targetFolderId == null,
            sortKey: keys[i],
          ),
        );
      }
    }
    if (ns.isNotEmpty) {
      final keys = SortKeys.nBetween(
        _maxKey(await _noteKeys(targetFolderId)),
        null,
        ns.length,
      );
      for (var i = 0; i < ns.length; i++) {
        await _putNote(
          tx,
          ns[i],
          ns[i].copyWith(
            folderId: targetFolderId,
            clearFolderId: targetFolderId == null,
            sortKey: keys[i],
          ),
        );
      }
    }
  });

  @override
  Future<void> reorderItem(
    LibraryItemRef item, {
    LibraryItemRef? after,
    LibraryItemRef? before,
  }) => reorderItems([item], after: after, before: before);

  @override
  Future<void> reorderItems(
    List<LibraryItemRef> items, {
    LibraryItemRef? after,
    LibraryItemRef? before,
  }) async {
    if (items.isEmpty) return;
    final isFolder = items.first is FolderRef;
    final all = [...items, ?after, ?before];
    if (all.any((r) => (r is FolderRef) != isFolder)) {
      throw ArgumentError('reorderItems: folders and notes cannot be mixed');
    }
    final ids = {for (final r in items) r.id};
    if ((after != null && ids.contains(after.id)) ||
        (before != null && ids.contains(before.id))) {
      throw ArgumentError('reorderItems: the anchor is one of the moved items');
    }
    return _q.run((tx) async {
      final r = await _resolveActive(items);
      final anchor = after ?? before;
      final List<({String key, String id, String? parent})> moving = isFolder
          ? [
              for (final f in r.folders)
                (key: f.sortKey, id: f.id, parent: f.parentId),
            ]
          : [
              for (final n in r.notes)
                (key: n.sortKey, id: n.id, parent: n.folderId),
            ];
      final parent = moving.first.parent;
      if (moving.any((m) => m.parent != parent)) {
        throw ArgumentError('reorderItems: items have different parents');
      }
      final List<KeyedId> all = isFolder
          ? [
              for (final f in await _childFolderRows(parent))
                (key: f.sortKey, id: f.id),
            ]
          : [
              for (final n in await _childNoteRows(parent))
                (key: n.sortKey, id: n.id),
            ];
      final siblings = [
        for (final x in all)
          if (!ids.contains(x.id)) x,
      ]..sort((a, b) => compareSortKeyThenId(a.key, a.id, b.key, b.id));
      var index = siblings.length;
      if (anchor != null) {
        final at = siblings.indexWhere((x) => x.id == anchor.id);
        if (at < 0) {
          throw ArgumentError.value(
            anchor.id,
            'anchor',
            'not an active sibling of the moved items',
          );
        }
        index = after != null ? at + 1 : at;
      }
      final plan = planSortKeys(siblings, index, moving.length);
      final newKeys = {
        for (var i = 0; i < moving.length; i++) moving[i].id: plan.keys[i],
        ...plan.rekeyed,
      };
      for (final e in newKeys.entries) {
        if (isFolder) {
          final f = await _folder(e.key);
          await _putFolder(tx, f, f.copyWith(sortKey: e.value));
        } else {
          final n = await _note(e.key);
          await _putNote(tx, n, n.copyWith(sortKey: e.value));
        }
      }
    });
  }

  @override
  Future<List<LibraryItemRef>> copyItems(
    List<LibraryItemRef> items, {
    required FolderId? targetFolderId,
    String nameSuffix = '',
  }) async {
    if (nameSuffix.length >= 200) {
      throw ArgumentError.value(
        nameSuffix,
        'nameSuffix',
        'shorter than 200 characters',
      );
    }
    return _q.run((tx) async {
      await _requireTarget(targetFolderId);
      final sources = <SyncEntity>[];
      for (final ref in items) {
        final SyncEntity? e = switch (ref) {
          FolderRef(:final id) => await _activeFolderRow(
            id,
          ).then((r) => r == null ? null : folderOf(r)),
          NoteRef(:final id) => await _activeNoteRow(
            id,
          ).then((r) => r == null ? null : noteOf(r)),
        };
        if (e == null) {
          throw EntityNotFoundException('${ref.id} does not exist');
        }
        sources.add(e);
      }
      final tree = await _tree();
      var folderKey = _maxKey(await _folderKeys(targetFolderId));
      var noteKey = _maxKey(await _noteKeys(targetFolderId));
      final out = <LibraryItemRef>[];
      for (final e in sources) {
        if (e is Folder) {
          folderKey = SortKeys.between(folderKey, null);
          out.add(
            FolderRef(
              await _copyFolder(
                tx,
                tree,
                e,
                targetFolderId,
                folderKey,
                nameWithSuffix(e.name, nameSuffix),
              ),
            ),
          );
        } else if (e is Note) {
          noteKey = SortKeys.between(noteKey, null);
          out.add(
            NoteRef(
              await copyNote(
                tx,
                e,
                folderId: targetFolderId,
                sortKey: noteKey,
                title: nameWithSuffix(e.title, nameSuffix),
              ),
            ),
          );
        }
      }
      return out;
    });
  }

  Future<FolderId> _copyFolder(
    WriteTxn tx,
    FolderTree tree,
    Folder f,
    FolderId? parent,
    String key,
    String name,
  ) async {
    final childNotes = await _childNoteRows(f.id);
    final copy = Folder(
      id: s.ids.newId(),
      ownerId: _owner,
      parentId: parent,
      name: name,
      colorArgb: f.colorArgb,
      icon: f.icon,
      sortKey: key,
      createdAt: tx.now,
      updatedAt: tx.now,
    );
    await tx.putLocal(copy, const {kAllFields}, isNew: true);
    for (final c in tree.childrenOf(f.id)) {
      await _copyFolder(tx, tree, c, copy.id, c.sortKey, c.name);
    }
    for (final r in childNotes) {
      final n = noteOf(r);
      await copyNote(
        tx,
        n,
        folderId: copy.id,
        sortKey: n.sortKey,
        title: n.title,
      );
    }
    return copy.id;
  }

  /// Copy of [n] with its active pages and strokes under new ids, active, in [folderId]
  /// (6.8; also the path of duplicateNoteForRecovery, 6.10.5). Assets are shared.
  Future<NoteId> copyNote(
    WriteTxn tx,
    Note n, {
    required FolderId? folderId,
    required String sortKey,
    required String title,
  }) async {
    final pageRows = await (_db.select(
      _db.pages,
    )..where((t) => t.noteId.equals(n.id) & t.deletedAt.isNull())).get();
    final pages = [for (final r in pageRows) pageOf(r)]..sort(comparePages);
    final id = s.ids.newId();
    final newPageIds = [for (final _ in pages) s.ids.newId()];
    await tx.putLocal(
      Note(
        id: id,
        ownerId: _owner,
        folderId: folderId,
        title: title,
        cover: n.cover,
        tags: n.tags,
        isFavorite: n.isFavorite,
        sortKey: sortKey,
        schemaVersion: n.schemaVersion,
        createdAt: tx.now,
        updatedAt: tx.now,
        pageCount: pages.length,
        firstPageId: newPageIds.firstOrNull,
      ),
      const {kAllFields},
      isNew: true,
    );
    for (var i = 0; i < pages.length; i++) {
      final p = pages[i];
      final pageId = newPageIds[i];
      await tx.putLocal(
        Page(
          id: pageId,
          noteId: id,
          sortKey: p.sortKey,
          size: p.size,
          background: p.background,
          createdAt: tx.now,
          updatedAt: tx.now,
        ),
        const {kAllFields},
        isNew: true,
      );
      for (var offset = 0; ; offset += kCopyStrokeChunk) {
        final rows =
            await (_db.select(_db.strokes)
                  ..where((t) => t.pageId.equals(p.id) & t.deletedAt.isNull())
                  ..orderBy([(t) => OrderingTerm.asc(t.id)])
                  ..limit(kCopyStrokeChunk, offset: offset))
                .get();
        for (final r in rows) {
          final st = strokeOf(r);
          await tx.putLocal(
            Stroke(
              id: s.ids.newId(),
              pageId: pageId,
              style: st.style,
              points: st.points,
              recordingId: st.recordingId,
              recordingOffsetMs: st.recordingOffsetMs,
              createdAt: st.createdAt,
              updatedAt: tx.now,
            ),
            const {kAllFields},
            strokeNoteId: id,
            isNew: true,
          );
        }
        if (rows.length < kCopyStrokeChunk) break;
      }
    }
    return id;
  }

  @override
  Future<void> trashItems(List<LibraryItemRef> items) => _q.run((tx) async {
    final refs = items.toSet();
    for (final ref in refs) {
      final exists = switch (ref) {
        FolderRef(:final id) => await _folderRow(id) != null,
        NoteRef(:final id) => await _noteRow(id) != null,
      };
      if (!exists) throw EntityNotFoundException('${ref.id} does not exist');
    }
    FolderTree? tree;
    for (final ref in refs) {
      switch (ref) {
        case FolderRef(:final id):
          final r = await _activeFolderRow(id);
          if (r == null) continue; // already in the trash
          tree ??= await _tree();
          final group = {id, ...tree.descendantsOf(id)};
          for (final fid in group) {
            final row = await _activeFolderRow(fid);
            if (row == null) continue;
            final g = folderOf(row);
            await _putFolder(
              tx,
              g,
              g.copyWith(deletedAt: tx.now, trashRootId: id),
            );
          }
          final noteRows =
              await (_db.select(_db.notes)..where(
                    (t) =>
                        t.ownerId.equals(_owner) &
                        t.deletedAt.isNull() &
                        t.folderId.isIn(group),
                  ))
                  .get();
          for (final nr in noteRows) {
            final n = noteOf(nr);
            await _putNote(
              tx,
              n,
              n.copyWith(deletedAt: tx.now, trashRootId: id),
            );
          }
          tree = null; // folders changed
        case NoteRef(:final id):
          final r = await _activeNoteRow(id);
          if (r == null) continue;
          final n = noteOf(r);
          await _putNote(tx, n, n.copyWith(deletedAt: tx.now, trashRootId: id));
      }
    }
  });
}
