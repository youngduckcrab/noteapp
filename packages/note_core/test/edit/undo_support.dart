// Helpers of the CORE T11 undo tests on the SQLite store: one open session on a note
// with one page, and the internal remote write path (applyRemote / commitRepairs). (v2.0,
// CORE T27) the page can start with page objects too.
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/row_mappers.dart';
import 'package:note_core/testing.dart';

import '../storage/storage_support.dart';

const String kRemoteNode = 'ffffffffffffffff';
var _remoteMs =
    1893456000000; // 2030: newer than every local stamp of the tests

final class UndoFixture {
  UndoFixture._(this.store, this.session, this.pageId);

  static Future<UndoFixture> open({
    List<Stroke> Function(PageId)? initial,
    List<PageObject> Function(PageId)? objects,
  }) async {
    final store = await openStore();
    const pageId = 'undo-page';
    final note = await store.library.createNote(
      title: 'undo',
      pages: [
        PageDraft(
          id: pageId,
          size: PageSize.a4Portrait,
          background: const BlankBackground(),
          strokes: initial?.call(pageId) ?? const [],
        ),
      ],
    );
    final session = await store.openSession(note.id);
    await session.openPage(pageId);
    // (v2.0) Objects keep their ids: added by the session (a draft's objects get new ids),
    // then the history is cleared — the initial page.
    if (objects != null) {
      await session
          .execute(AddObjects(pageId: pageId, objects: objects(pageId)))
          .persisted;
      session.clearHistory();
    }
    return UndoFixture._(store, session, pageId);
  }

  final DriftNoteStore store;
  final NoteSession session;
  final PageId pageId;

  Stroke stroke({int seed = 0}) => StrokeFixtures.synthetic(
    pageId: pageId,
    ids: store.ids,
    seed: seed,
    pointCount: 16,
    createdAt: 1000 + seed,
  );

  /// The stroke as the session holds it now.
  Stroke current(ElementId id) =>
      session.pageIfLoaded(pageId)!.strokeById(id) ??
      (throw StateError('stroke $id is not active'));

  /// (v2.0) The page object as the session holds it now.
  PageObject currentObject(ElementId id) =>
      session.pageIfLoaded(pageId)!.objectById(id) ??
      (throw StateError('object $id is not active'));

  Future<void> run(EditCommand command) => session.execute(command).persisted;

  /// A committed remote write of [entities] (origin remote, newer versions).
  Future<void> remote(List<SyncEntity> entities) => store.queue.run((tx) async {
    for (final e in entities) {
      await tx.putRemote(
        e,
        EntityFieldVersions(Hlc(_remoteMs++, 0, kRemoteNode)),
      );
    }
  }, origin: ChangeOrigin.remote);

  /// The stored row of stroke [id] with its field versions.
  Future<VersionedEntity> row(ElementId id) async =>
      (await readVersionedRow(store.db, EntityRef(EntityKind.stroke, id)))!;

  /// (v2.0) The stored row of page object [id] with its field versions.
  Future<VersionedEntity> objectRow(ElementId id) async =>
      (await readVersionedRow(store.db, EntityRef(EntityKind.pageObject, id)))!;

  Future<void> close() async {
    if (!session.isClosed) await session.close();
    await store.close();
  }
}
