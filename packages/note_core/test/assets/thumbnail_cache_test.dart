// CORE T13 — ThumbnailCacheImpl (6.13, contract 7.2.11): device-local records keyed
// by page id, freshness by contentRevision, updates after write / delete, dropped
// when the page is purged from the trash, never in the outbox.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';

PageThumbnail _thumb(
  PageId pageId, {
  int rev = 0,
  int length = 16,
  String mime = 'image/png',
}) => PageThumbnail(
  pageId: pageId,
  contentRevision: rev,
  width: 384,
  height: 512,
  mimeType: mime,
  bytes: Uint8List.fromList([for (var i = 0; i < length; i++) (i + rev) % 256]),
);

void main() {
  late DriftNoteStore store;
  late ThumbnailCache cache;
  late List<PageId> updates;
  setUp(() async {
    store = await openStore();
    cache = store.thumbnails;
    updates = [];
    cache.updates.listen(updates.add);
  });
  tearDown(() => store.close());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('write / read keeps every field; overwrite replaces', () async {
    expect(await cache.read('p1'), isNull);
    await cache.write(_thumb('p1', rev: 2, length: 40, mime: 'image/webp'));
    final t = (await cache.read('p1'))!;
    expect(t.pageId, 'p1');
    expect(t.contentRevision, 2);
    expect(t.width, 384);
    expect(t.height, 512);
    expect(t.mimeType, 'image/webp');
    expect(t.bytes, _thumb('p1', rev: 2, length: 40).bytes);
    await cache.write(_thumb('p1', rev: 3, length: 8));
    final again = (await cache.read('p1'))!;
    expect(again.contentRevision, 3);
    expect(again.bytes, hasLength(8));
    expect(await cache.read('p2'), isNull);
  });

  test('updates emits the page id after each write and delete', () async {
    await cache.write(_thumb('p1'));
    await cache.write(_thumb('p2'));
    await cache.delete('p1');
    await cache.delete('missing');
    await settle();
    expect(updates, ['p1', 'p2', 'p1', 'missing']);
    expect(await cache.read('p1'), isNull);
    expect(await cache.read('p2'), isNotNull);
  });

  test('a read right after a write (not awaited) sees it', () async {
    unawaited(cache.write(_thumb('p1', rev: 5)));
    expect((await cache.read('p1'))!.contentRevision, 5);
  });

  test('isStaleFor: other page or other contentRevision', () async {
    final note = await store.library.createNote(title: 'n');
    final page = (await store.content.pagesOf(note.id)).single;
    await cache.write(_thumb(page.id, rev: page.contentRevision));
    final t = (await cache.read(page.id))!;
    expect(t.isStaleFor(page), isFalse);
    expect(t.isStaleFor(page.copyWith(contentRevision: 1)), isTrue);
    final other = await store.library.createNote(title: 'o');
    expect(
      t.isStaleFor((await store.content.pagesOf(other.id)).single),
      isTrue,
    );
  });

  test('allowed for a page never opened in a session; not synced (no outbox, '
      'no ChangeBatch)', () async {
    final note = await store.library.createNote(title: 'n');
    final page = (await store.content.pagesOf(note.id)).single;
    await store.db.delete(store.db.outbox).go();
    final batches = <ChangeBatch>[];
    final sub = store.changes.listen(batches.add);
    addTearDown(sub.cancel);
    await cache.write(_thumb(page.id));
    await cache.delete(page.id);
    await settle();
    expect(await readOutbox(store.db), isEmpty);
    expect(batches, isEmpty);
  });

  test(
    'purging a note from the trash drops the thumbnails of its pages',
    () async {
      final note = await store.library.createNote(
        title: 'n',
        pages: const [PageDraft.blankA4, PageDraft.blankA4],
      );
      final keep = await store.library.createNote(title: 'keep');
      final pages = await store.content.pagesOf(note.id);
      final kept = (await store.content.pagesOf(keep.id)).single;
      for (final p in [...pages, kept]) {
        await cache.write(_thumb(p.id));
      }
      await store.library.trashItems([NoteRef(note.id)]);
      for (final p in pages) {
        expect(await cache.read(p.id), isNotNull, reason: 'trash keeps them');
      }
      await store.trash.purge([NoteRef(note.id)]);
      for (final p in pages) {
        expect(await cache.read(p.id), isNull);
      }
      expect(await cache.read(kept.id), isNotNull);
    },
  );

  test('usage counts the stored image bytes', () async {
    await cache.write(_thumb('p1', length: 100));
    await cache.write(_thumb('p2', length: 20));
    await cache.write(_thumb('p1', length: 50));
    expect((await store.assets.usage()).thumbnailBytes, 70);
  });

  test('a reopened file store keeps its thumbnails', () async {
    final dir = await Directory.systemTemp.createTemp('note_core_thumbs_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/notes.db';
    final first = await openStore(filePath: path);
    await first.thumbnails.write(_thumb('p9', rev: 4));
    await first.close();
    final again = await openStore(filePath: path);
    addTearDown(() async {
      await again.close();
      await deleteLocalNoteData(NoteStoreConfig(nativeDatabasePath: path));
    });
    expect((await again.thumbnails.read('p9'))!.contentRevision, 4);
  });

  test('after close: StateError', () async {
    final s = await openStore();
    await s.close();
    await expectLater(s.thumbnails.read('p1'), throwsStateError);
    await expectLater(s.thumbnails.write(_thumb('p1')), throwsStateError);
  });
}
