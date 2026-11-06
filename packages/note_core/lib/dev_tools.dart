// package:note_core/dev_tools.dart — web-safe, production code may import (EDITOR dev menu)
/// Developer tools of note_core (contract 00-overview 7.6, CORE 4.10). (v2.2) v1 DB copy
/// API for the INFRA developer menu — 2nd-round contract 7.2.7 (C22-01, CORE CP-17).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'src/common/ids.dart';
import 'src/dev/synthetic.dart';
import 'src/dev/synthetic_objects.dart';
import 'src/edit/commands.dart';
import 'src/edit/page_draft.dart';
import 'src/model/asset.dart';
import 'src/model/stroke.dart' show PageObjectLimits;
import 'src/repo/note_store.dart';
import 'src/storage/drift_note_store.dart';
import 'src/storage/v1_copy/v1_copy.dart' show v1CopyFileName;

/// CORE: synthetic handwriting-like note for iPad performance checks (strokes carry widthQ,
/// 6.2.4). Uses ONLY the NoteStore interface (library.createNote + session AddStrokes), so it
/// works on createFakeNoteStore() from B2 (CORE T5) and on the real store unchanged.
/// (v2.0, CORE CP-9 — approved P-C) [objectsPerPage] page objects on every page too (session
/// AddObjects, after the strokes; 0..PageObjectLimits.maxObjectsPerPage): a grid over the page
/// in a fixed mix — per 17 objects 10 shapes (every ShapeKind in turn), 5 text boxes, 1 math
/// and 1 image (one 64 × 48 PNG asset per note, put once through store.assets) — so 340 is
/// INK's object page (200 shapes, 100 text boxes, 20 math, 20 images). Same seed, same objects.
Future<NoteId> seedSyntheticNote(
  NoteStore store, {
  String title = 'perf-test',
  int pages = 50,
  int strokesPerPage = 300,
  int pointsPerStroke = 100,
  int seed = 1,
  int objectsPerPage = 0,
}) async {
  if (pages < 1 || pages > 2000) {
    throw ArgumentError.value(pages, 'pages', 'must be 1..2000');
  }
  if (strokesPerPage < 0) {
    throw ArgumentError.value(strokesPerPage, 'strokesPerPage', 'must be >= 0');
  }
  if (objectsPerPage < 0 ||
      objectsPerPage > PageObjectLimits.maxObjectsPerPage) {
    throw ArgumentError.value(
      objectsPerPage,
      'objectsPerPage',
      'must be 0..${PageObjectLimits.maxObjectsPerPage}',
    );
  }
  final note = await store.library.createNote(
    title: title,
    pages: List.filled(pages, PageDraft.blankA4),
  );
  final AssetId? imageAssetId = objectsPerPage >= kSyntheticObjectCycle
      ? (await store.assets.put(
          syntheticPng(seed: seed),
          type: AssetType.image,
          mimeType: 'image/png',
          fileName: 'synthetic.png',
        )).id
      : null;
  final session = await store.openSession(note.id);
  try {
    final base = store.clock.now().millisecondsSinceEpoch;
    for (var p = 0; p < session.pages.length; p++) {
      final page = session.pages[p];
      if (strokesPerPage == 0 && objectsPerPage == 0) continue;
      await session.openPage(page.id);
      try {
        if (strokesPerPage > 0) {
          session.execute(
            AddStrokes(
              pageId: page.id,
              strokes: [
                for (var i = 0; i < strokesPerPage; i++)
                  syntheticStroke(
                    pageId: page.id,
                    ids: store.ids,
                    // One reproducible seed per (seed, page, stroke).
                    seed: seed * 1000003 + p * 10007 + i,
                    pointCount: pointsPerStroke,
                    createdAt: base + i,
                  ),
              ],
            ),
          );
        }
        if (objectsPerPage > 0) {
          session.execute(
            AddObjects(
              pageId: page.id,
              objects: syntheticObjects(
                pageId: page.id,
                ids: store.ids,
                count: objectsPerPage,
                size: page.size,
                imageAssetId: imageAssetId,
                seed: seed,
                createdAt: base + strokesPerPage,
              ),
            ),
          );
        }
      } finally {
        session.closePage(page.id);
      }
    }
    // Seeding is not a user edit: nothing to undo.
    session.clearHistory();
    await session.flush();
  } finally {
    await session.close();
  }
  return note.id;
}

// package:note_core/dev_tools.dart — (v2.2, C22-01 — CORE CP-17) v1 DB copy for the INFRA developer menu
@immutable
final class V1DatabaseCopyInfo {
  const V1DatabaseCopyInfo({
    required this.createdAt,
    required this.bytes,
    required this.normalOpens,
    required this.fileName,
    this.failure,
  });
  final EpochMillis createdAt;
  final int bytes;
  final int normalOpens;

  /// 'noteapp-v1-backup.sqlite' (native, a SQLite file) | 'noteapp-v1-backup.sql.txt' (web, the canonical dump)
  final String fileName;

  /// Set when the copy could not be made ('quota' | 'io' | 'other'); bytes is 0 then.
  final String? failure;

  @override
  bool operator ==(Object other) =>
      other is V1DatabaseCopyInfo &&
      other.createdAt == createdAt &&
      other.bytes == bytes &&
      other.normalOpens == normalOpens &&
      other.fileName == fileName &&
      other.failure == failure;

  @override
  int get hashCode =>
      Object.hash(createdAt, bytes, normalOpens, fileName, failure);

  @override
  String toString() =>
      'V1DatabaseCopyInfo($fileName, $bytes B, opens: $normalOpens'
      '${failure == null ? '' : ', failure: $failure'})';
}

/// null when there is no copy and no failure record (new DB, deleted, or a store without one — fakes).
/// CORE: the real store records the copy made right before its v1 → v2 upgrade (02-core 6.12.4,
/// T24); normalOpens counts the opens that ended without error since then.
Future<V1DatabaseCopyInfo?> v1DatabaseCopyInfo(NoteStore store) async {
  if (store is! DriftNoteStore) return null;
  final r = await store.v1Copies.record();
  if (r == null) return null;
  return V1DatabaseCopyInfo(
    createdAt: r.createdAt,
    bytes: r.bytes,
    normalOpens: r.normalOpens,
    fileName: v1CopyFileName(r.method),
    failure: r.failure,
  );
}

/// The copy in ≤ 4 MiB chunks (INFRA writes a file / web download). StateError when there is none.
/// CORE: a native copy is the SQLite file, a web copy the canonical dump text (6.12.4); a failure
/// record alone is 'none'. A store without one (the fake store) has none.
Stream<Uint8List> readV1DatabaseCopy(NoteStore store) {
  if (store is DriftNoteStore) return store.v1Copies.read();
  return Stream.error(StateError('This store has no v1 database copy'));
}

/// Deletes the copy and its kv record; no-op when none.
/// CORE: the bytes first, then the record (a failure record is deleted the same way); no-op for
/// a store without one (the fake store).
Future<void> deleteV1DatabaseCopy(NoteStore store) async {
  if (store is DriftNoteStore) await store.v1Copies.delete();
}
