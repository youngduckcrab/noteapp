// CORE T33a — the write side of the search index on SQLite (m5-7/02-core 6.10.3, 6.10.5): the
// write hook (text boxes and math objects: add, edit, delete, undo, createNote, remote, orphan
// adoption; handwriting results: put, update, removeForPage; shapes / images not indexed), the
// owner sourceRev strings, SearchIndexWriter (pdf: sourceRev tails as given, the empty unit list
// keeping its owner, every validation rule, blob put → row commit → old blob delete, a failed
// job deleting its new boxes, orphan boxes cleaned on first use after open), rebuild
// (rebuilding true → false, idempotent, chunked queue jobs, pdf only dropped, a changed
// normalizer version at open) and index failures (C-13: the source write commits, the owner is
// pending, the next write transaction or the store open retries it — at most 20 per
// transaction, no timer).
@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:fake_async/fake_async.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/search/search_rects.dart';
import 'package:note_core/src/search/search_spacing.dart' show kInkTermsVersion;
import 'package:note_core/src/storage/db/note_database.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/drift_search_index.dart';
import 'package:note_core/src/storage/kv_keys.dart';
import 'package:note_core/src/storage/search_indexer.dart';
import 'package:note_core/testing.dart'
    show PageObjectFixtures, newerVersionWinsPolicy;
import 'package:test/test.dart';

import '../media/draft_store_support.dart';
import '../storage/storage_support.dart';
import '../sync/support/sync_support.dart';

const String _asset =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// The units of one owner, in seq order.
Future<List<SearchUnitRow>> unitsOf(
  DriftNoteStore store,
  SearchSource source,
  String key,
) =>
    (store.db.select(store.db.searchUnits)
          ..where((t) => t.source.equals(source.name) & t.ownerKey.equals(key))
          ..orderBy([(t) => OrderingTerm(expression: t.seq)]))
        .get();

Future<SearchOwnerRow?> ownerOf(
  DriftNoteStore store,
  SearchSource source,
  String key,
) =>
    (store.db.select(store.db.searchOwners)
          ..where((t) => t.source.equals(source.name) & t.ownerKey.equals(key)))
        .getSingleOrNull();

/// The FTS rowids MATCH [query] finds (FTS5 query syntax — SearchText.matchQuery).
Future<List<int>> ftsMatch(DriftNoteStore store, String query) async => [
  for (final r
      in await store.db
          .customSelect(
            'SELECT rowid AS id FROM search_fts WHERE search_fts MATCH ? '
            'ORDER BY rowid',
            variables: [Variable<String>(query)],
          )
          .get())
    r.read<int>('id'),
];

Future<int> unitCount(DriftNoteStore store) async =>
    (await store.db
            .customSelect('SELECT count(*) AS n FROM search_units')
            .getSingle())
        .read<int>('n');

/// The derived rows as comparable strings (unit ids aside), sorted: `U|<source>|…` per unit,
/// `O|<source>|…` per owner.
Future<List<String>> snapshot(DriftNoteStore store) async => [
  for (final u in await store.db.select(store.db.searchUnits).get())
    [
      'U',
      u.source,
      u.ownerKey,
      u.seq,
      u.noteId,
      u.pageId,
      u.assetId,
      u.pdfIndex,
      u.body,
      u.norm,
      u.rectL,
      u.rectT,
      u.rectR,
      u.rectB,
      u.pdfAspect,
    ].join('|'),
  for (final o in await store.db.select(store.db.searchOwners).get())
    [
      'O',
      o.source,
      o.ownerKey,
      o.noteId,
      o.pageId,
      o.sourceRev,
      o.pending,
    ].join('|'),
]..sort();

/// Every unit has its FTS row (MATCH with the query of its own norm finds it).
Future<void> expectFtsInSync(DriftNoteStore store) async {
  final units = await store.db.select(store.db.searchUnits).get();
  for (final u in units) {
    final q = SearchText.matchQuery(u.norm);
    if (q == null) continue;
    expect(await ftsMatch(store, q), contains(u.id), reason: u.body);
  }
}

void main() {
  late DriftNoteStore store;
  late Note n;
  late List<PageId> pages;

  DriftSearchIndex index() => store.search;

  setUp(() async {
    store = await openStore();
    n = await store.library.createNote(
      title: 'search',
      pages: const [PageDraft.blankA4, PageDraft.blankA4],
    );
    pages = [for (final p in await store.content.pagesOf(n.id)) p.id];
  });
  tearDown(() => store.close());

  Future<NoteSession> sessionOn(PageId pageId) async {
    final s = await store.openSession(n.id);
    await s.openPage(pageId);
    return s;
  }

  /// Adds [objects] to page 0 in one session commit; returns the session (open).
  Future<NoteSession> add(List<PageObject> objects, {PageId? pageId}) async {
    final p = pageId ?? pages[0];
    final s = await sessionOn(p);
    await s.execute(AddObjects(pageId: p, objects: objects)).persisted;
    return s;
  }

  Future<PageObject> stored(String id) async =>
      (await store.content.loadPage(pages[0])).objects
          .singleWhere((o) => o.id == id);

  group('text boxes and math objects (write hook)', () {
    test('a text box is indexed with its commit: one unit, sourceRev <version>:1, FTS', () async {
      final s = await add([
        PageObjectFixtures.textBox(
          pageId: pages[0],
          id: 't1',
          text: '오늘 회의록을 정리했다 meeting notes',
        ),
      ]);
      await s.close();
      final o = await stored('t1');
      final owner = (await ownerOf(store, SearchSource.text, 't1'))!;
      expect(owner.sourceRev, '${o.version}:${SearchText.normalizerVersion}');
      expect(owner.pending, isFalse);
      expect(owner.noteId, n.id);
      expect(owner.pageId, pages[0]);
      expect(
        await index().sourceRevOf(SearchSource.text, 't1'),
        owner.sourceRev,
      );
      final units = await unitsOf(store, SearchSource.text, 't1');
      expect(units, hasLength(1));
      final u = units.single;
      expect(u.body, '오늘 회의록을 정리했다 meeting notes');
      expect(u.norm, SearchText.normalize(u.body));
      expect(u.noteId, n.id);
      expect(u.pageId, pages[0]);
      expect(
        (u.rectL, u.rectT, u.rectR, u.rectB),
        (o.bounds.left, o.bounds.top, o.bounds.right, o.bounds.bottom),
      );
      expect(u.rectsRef, isNull);
      expect(await ftsMatch(store, SearchText.matchQuery('회의록')!), [u.id]);
      expect(await ftsMatch(store, SearchText.matchQuery('meet')!), [u.id]);
    });

    test('editing re-indexes: the old FTS row goes, the new unit is the most recent', () async {
      final s = await add([
        PageObjectFixtures.textBox(pageId: pages[0], id: 't1', text: '방정식'),
        PageObjectFixtures.textBox(pageId: pages[0], id: 't2', text: '확률'),
      ]);
      final before = (await unitsOf(store, SearchSource.text, 't1')).single;
      final o = (await stored('t1')) as TextBoxObject;
      await s
          .execute(
            UpdateObjects(
              pageId: pages[0],
              objects: [o.copyWith(text: '정식 계약서')],
            ),
          )
          .persisted;
      final after = (await unitsOf(store, SearchSource.text, 't1')).single;
      expect(after.body, '정식 계약서');
      final t2 = (await unitsOf(store, SearchSource.text, 't2')).single;
      expect(after.id, greaterThan(t2.id));
      expect(await ftsMatch(store, SearchText.matchQuery('방정')!), isEmpty);
      expect(await ftsMatch(store, SearchText.matchQuery('계약')!), [after.id]);
      expect(before.id, isNot(after.id));
      final v = (await stored('t1')).version;
      expect(
        await index().sourceRevOf(SearchSource.text, 't1'),
        '$v:${SearchText.normalizerVersion}',
      );
      await s.close();
    });

    test(
      'delete removes the owner and its units; undo brings them back',
      () async {
        final s = await add([
          PageObjectFixtures.textBox(pageId: pages[0], id: 't1', text: '단어 암기'),
        ]);
        await s
            .execute(RemoveElements(pageId: pages[0], elementIds: const ['t1']))
            .persisted;
        expect(await ownerOf(store, SearchSource.text, 't1'), isNull);
        expect(await unitsOf(store, SearchSource.text, 't1'), isEmpty);
        expect(await ftsMatch(store, SearchText.matchQuery('암기')!), isEmpty);
        await s.undo();
        await s.flush();
        final u = (await unitsOf(store, SearchSource.text, 't1')).single;
        expect(u.body, '단어 암기');
        expect(await ftsMatch(store, SearchText.matchQuery('암기')!), [u.id]);
        final v = (await stored('t1')).version;
        expect(
          await index().sourceRevOf(SearchSource.text, 't1'),
          '$v:${SearchText.normalizerVersion}',
        );
        await s.close();
      },
    );

    test('a math object: source math, body = latex', () async {
      final s = await add([
        PageObjectFixtures.math(pageId: pages[0], id: 'm1'),
      ]);
      await s.close();
      final o = (await stored('m1')) as MathObject;
      final u = (await unitsOf(store, SearchSource.math, 'm1')).single;
      expect(u.body, o.latex);
      expect(u.source, 'math');
      expect(await ownerOf(store, SearchSource.text, 'm1'), isNull);
    });

    test(
      'a body that normalizes to nothing: the owner without units',
      () async {
        final s = await add([
          PageObjectFixtures.textBox(pageId: pages[0], id: 't1', text: ''),
          PageObjectFixtures.textBox(pageId: pages[0], id: 't2', text: ' ​\n　'),
        ]);
        await s.close();
        for (final id in ['t1', 't2']) {
          expect(await ownerOf(store, SearchSource.text, id), isNotNull);
          expect(await unitsOf(store, SearchSource.text, id), isEmpty);
        }
      },
    );

    test('shapes, images and unknown objects are not indexed', () async {
      final s = await add([
        PageObjectFixtures.shape(pageId: pages[0], id: 's1'),
      ]);
      await s.close();
      await store.sync.applyRemote([
        upsert(
          PageObjectFixtures.image(pageId: pages[0], id: 'i1', assetId: _asset),
          remoteAfter(store),
        ),
        upsert(
          PageObjectFixtures.unknown(pageId: pages[0], id: 'u1'),
          remoteAfter(store),
        ),
      ], policy: newerVersionWinsPolicy);
      expect(await store.db.select(store.db.searchOwners).get(), isEmpty);
      expect(await unitCount(store), 0);
    });

    test('createNote with PageDraft.objects indexes the text', () async {
      final note = await store.library.createNote(
        title: 'drafted',
        pages: [
          PageDraft(
            size: PageSize.a4Portrait,
            background: const BlankBackground(),
            objects: [
              PageObjectFixtures.textBox(
                pageId: 'ignored',
                id: 'd1',
                text: '초안 글',
              ),
            ],
          ),
        ],
      );
      final page = (await store.content.pagesOf(note.id)).single;
      final o = (await store.content.loadPage(page.id)).objects.single;
      final u = (await unitsOf(store, SearchSource.text, o.id)).single;
      expect(u.body, '초안 글');
      expect(u.noteId, note.id);
      expect(u.pageId, page.id);
    });

    test('remote: applyRemote indexes; an orphan gets its unit when its page arrives', () async {
      await store.sync.applyRemote([
        upsert(
          PageObjectFixtures.textBox(pageId: pages[1], id: 'r1', text: '원격 글'),
          remoteAfter(store),
        ),
      ], policy: newerVersionWinsPolicy);
      final r1 = (await unitsOf(store, SearchSource.text, 'r1')).single;
      expect((r1.noteId, r1.pageId, r1.body), (n.id, pages[1], '원격 글'));

      // The object comes before its page: an owner without units, then adopted.
      await store.sync.applyRemote([
        upsert(
          PageObjectFixtures.textBox(
            pageId: 'p-late',
            id: 'r2',
            text: '늦은 페이지',
          ),
          remoteAfter(store),
        ),
      ], policy: newerVersionWinsPolicy);
      expect(await ownerOf(store, SearchSource.text, 'r2'), isNotNull);
      expect(await unitsOf(store, SearchSource.text, 'r2'), isEmpty);
      await store.sync.applyRemote([
        upsert(page('p-late', n.id), remoteAfter(store)),
      ], policy: newerVersionWinsPolicy);
      final r2 = (await unitsOf(store, SearchSource.text, 'r2')).single;
      expect((r2.noteId, r2.pageId, r2.body), (n.id, 'p-late', '늦은 페이지'));
      expect((await ownerOf(store, SearchSource.text, 'r2'))!.noteId, n.id);

      // A remote delete removes the owner.
      final o = (await store.content.loadPage(pages[1])).objects.single;
      await store.sync.applyRemote([
        upsert(o.copyWithMeta(updatedAt: 9, deletedAt: 9), remoteAfter(store)),
      ], policy: newerVersionWinsPolicy);
      expect(await ownerOf(store, SearchSource.text, 'r1'), isNull);
      await expectFtsInSync(store);
    });
  });

  group('handwriting results (ink)', () {
    HandwritingText result(
      List<String> lines, {
      String rev = '0000000000000000',
    }) => HandwritingText(
      noteId: n.id,
      pageId: pages[0],
      engineId: 'fake/1:ko',
      sourceRev: rev,
      lines: [
        for (final (i, t) in lines.indexed)
          HandwritingLine(
            text: t,
            rect: PageRect(10, 10.0 + 40 * i, 200, 40.0 + 40 * i),
            strokeIds: ['s$i'],
          ),
      ],
      createdAt: 1,
    );

    test('put: one unit per non-empty line (rect = line rect), sourceRev with the version', () async {
      await store.handwriting.put(result(['회의록', '  ', '정리']));
      final h = (await store.handwriting.forPage(pages[0]))!;
      final key = HandwritingText.idFor(pages[0]);
      final units = await unitsOf(store, SearchSource.ink, key);
      expect([for (final u in units) u.body], ['회의록', '정리']);
      expect([for (final u in units) u.seq], [0, 1]);
      expect(
        [for (final u in units) (u.rectT, u.rectB)],
        [(10.0, 40.0), (90.0, 120.0)],
      );
      expect(
        await index().sourceRevOf(SearchSource.ink, key),
        '${'0' * 16}:${h.version}:${SearchText.normalizerVersion}',
      );
    });

    test('update re-indexes; removeForPage removes the owner', () async {
      final key = HandwritingText.idFor(pages[0]);
      await store.handwriting.put(result(['하나']));
      await store.handwriting.update(
        pages[0],
        (cur) => cur!.copyWith(
          lines: [cur.lines.single.copyWith(text: '둘 셋')],
          sourceRev: '1' * 16,
        ),
      );
      expect(
        [for (final u in await unitsOf(store, SearchSource.ink, key)) u.body],
        ['둘 셋'],
      );
      expect(
        await index().sourceRevOf(SearchSource.ink, key),
        startsWith('${'1' * 16}:'),
      );
      await store.handwriting.removeForPage(pages[0]);
      expect(await ownerOf(store, SearchSource.ink, key), isNull);
      expect(await unitCount(store), 0);
    });
  });

  group('SearchIndexWriter (pdf)', () {
    const ok = '$_asset#0';

    List<PageRect> boxes(String body, {double top = 0.1}) => [
      for (var i = 0; i < body.length; i++)
        PageRect(i / 100, top, (i + 1) / 100, top + 0.02),
    ];

    test(
      'sourceRevOf / sourceRevs keep the string as given (:x2 tail)',
      () async {
        await index().replaceUnits(SearchSource.pdf, ok, const [
          SearchUnitDraft(body: '피디에프'),
        ], sourceRev: '$_asset:1:x2');
        await index().replaceUnits(
          SearchSource.pdf,
          '$_asset#7',
          const [],
          sourceRev: 'r' * 200,
        );
        expect(await index().sourceRevOf(SearchSource.pdf, ok), '$_asset:1:x2');
        expect(await index().sourceRevs(SearchSource.pdf), {
          ok: '$_asset:1:x2',
          '$_asset#7': 'r' * 200,
        });
        expect(await index().sourceRevs(SearchSource.text), isEmpty);
        final u = (await unitsOf(store, SearchSource.pdf, ok)).single;
        expect(
          (u.assetId, u.pdfIndex, u.noteId, u.pageId),
          (_asset, 0, null, null),
        );
      },
    );

    test('replaceUnits(…, []) keeps the owner with its sourceRev (units, FTS, boxes go)', () async {
      await index().replaceUnits(SearchSource.pdf, ok, [
        SearchUnitDraft(body: '글자', rects: boxes('글자')),
      ], sourceRev: 'r1');
      expect(await index().blobs.keys(kSearchBlobRoot), hasLength(1));
      await index().replaceUnits(
        SearchSource.pdf,
        ok,
        const [],
        sourceRev: 'r2',
      );
      expect(await index().sourceRevOf(SearchSource.pdf, ok), 'r2');
      expect(await unitsOf(store, SearchSource.pdf, ok), isEmpty);
      expect(await ftsMatch(store, SearchText.matchQuery('글자')!), isEmpty);
      expect(await index().blobs.keys(kSearchBlobRoot), isEmpty);
      await index().removeOwner(SearchSource.pdf, ok);
      expect(await index().sourceRevOf(SearchSource.pdf, ok), isNull);
    });

    test(
      'validation: every rule is an ArgumentError and nothing changes',
      () async {
        final s = index();
        Future<void> units(List<SearchUnitDraft> u, {String rev = 'r'}) =>
            s.replaceUnits(SearchSource.pdf, ok, u, sourceRev: rev);
        final bad = <String, Future<void> Function()>{
          'ink': () =>
              s.replaceUnits(SearchSource.ink, ok, const [], sourceRev: 'r'),
          'text': () =>
              s.replaceUnits(SearchSource.text, ok, const [], sourceRev: 'r'),
          'math': () =>
              s.replaceUnits(SearchSource.math, ok, const [], sourceRev: 'r'),
          'key without #': () => s.replaceUnits(
            SearchSource.pdf,
            _asset,
            const [],
            sourceRev: 'r',
          ),
          'key 63 hex': () => s.replaceUnits(
            SearchSource.pdf,
            '${_asset.substring(1)}#0',
            const [],
            sourceRev: 'r',
          ),
          'key upper hex': () => s.replaceUnits(
            SearchSource.pdf,
            '${_asset.toUpperCase()}#0',
            const [],
            sourceRev: 'r',
          ),
          'key index': () => s.replaceUnits(
            SearchSource.pdf,
            '$_asset#-1',
            const [],
            sourceRev: 'r',
          ),
          'units > 10,000': () => units([
            for (var i = 0; i <= 10000; i++) const SearchUnitDraft(body: 'x'),
          ]),
          'body > 200,000': () => units([SearchUnitDraft(body: 'x' * 200001)]),
          'rects length': () => units(const [
            SearchUnitDraft(body: 'abc', rects: [PageRect.zero]),
          ]),
          'fraction > 1': () => units(const [
            SearchUnitDraft(body: 'a', rects: [PageRect(0, 0, 1.5, 1)]),
          ]),
          'fraction < 0': () => units(const [
            SearchUnitDraft(body: 'a', rects: [PageRect(-0.01, 0, 0.5, 1)]),
          ]),
          'fraction NaN': () => units(const [
            SearchUnitDraft(
              body: 'a',
              rects: [PageRect(double.nan, 0, 0.5, 1)],
            ),
          ]),
          'aspect 0': () =>
              units(const [SearchUnitDraft(body: 'a', pdfPageAspect: 0)]),
          'aspect negative': () =>
              units(const [SearchUnitDraft(body: 'a', pdfPageAspect: -1)]),
          'aspect infinite': () => units(const [
            SearchUnitDraft(body: 'a', pdfPageAspect: double.infinity),
          ]),
          'empty rev': () => units(const [], rev: ''),
          'rev > 200': () => units(const [], rev: 'r' * 201),
          'remove ink': () => s.removeOwner(SearchSource.ink, ok),
          'remove bad key': () => s.removeOwner(SearchSource.pdf, 'x#0'),
        };
        for (final MapEntry(key: name, value: call) in bad.entries) {
          await expectLater(call(), throwsArgumentError, reason: name);
        }
        expect(await s.sourceRevs(SearchSource.pdf), isEmpty);
        expect(await store.db.select(store.db.searchUnits).get(), isEmpty);
        expect(await s.blobs.keys(kSearchBlobRoot), isEmpty);
        // The limits themselves are allowed (1e-6 slack, clamped when stored).
        await units([
          const SearchUnitDraft(
            body: 'ab',
            rects: [PageRect(-1e-7, 0, 0.5, 1), PageRect(0.5, 0, 1 + 1e-7, 1)],
            pdfPageAspect: 0.75,
          ),
        ], rev: 'r' * 200);
        final u = (await unitsOf(store, SearchSource.pdf, ok)).single;
        expect(u.pdfAspect, 0.75);
        final decoded = SearchRectsCodec.decode(
          (await s.blobs.get(u.rectsRef!))!,
        );
        expect(decoded.first.left, 0);
        expect(decoded.last.right, 1);
      },
    );

    test(
      'boxes put → rows committed → old boxes deleted; a key is never reused',
      () async {
        final s = index();
        await s.replaceUnits(SearchSource.pdf, ok, [
          SearchUnitDraft(body: '첫째', rects: boxes('첫째')),
          const SearchUnitDraft(body: '상자 없음'),
          SearchUnitDraft(body: '둘째', rects: boxes('둘째', top: 0.5)),
        ], sourceRev: 'r1');
        final first = await unitsOf(store, SearchSource.pdf, ok);
        final firstKeys = [for (final u in first) u.rectsRef];
        expect(firstKeys[1], isNull);
        final pattern = RegExp('^si/pdf/$_asset/0/[0-9a-f]{16}-(\\d{4})\$');
        expect(pattern.firstMatch(firstKeys[0]!)!.group(1), '0000');
        expect(pattern.firstMatch(firstKeys[2]!)!.group(1), '0002');
        expect(s.debugLog, [
          'put ${firstKeys[0]}',
          'put ${firstKeys[2]}',
          'commit $ok',
        ]);
        expect(
          SearchRectsCodec.decode((await s.blobs.get(firstKeys[2]!))!),
          SearchRectsCodec.decode(
            SearchRectsCodec.encode(boxes('둘째', top: 0.5)),
          ),
        );
        s.debugLog.clear();

        await s.replaceUnits(SearchSource.pdf, ok, [
          SearchUnitDraft(body: '셋째', rects: boxes('셋째')),
        ], sourceRev: 'r2');
        final second = (await unitsOf(store, SearchSource.pdf, ok)).single;
        expect(firstKeys, isNot(contains(second.rectsRef)));
        expect(s.debugLog, [
          'put ${second.rectsRef}',
          'commit $ok',
          'delete ${firstKeys[0]}',
          'delete ${firstKeys[2]}',
        ]);
        expect(await s.blobs.keys(kSearchBlobRoot), [second.rectsRef]);
        expect(await ftsMatch(store, SearchText.matchQuery('첫째')!), isEmpty);
        expect(await ftsMatch(store, SearchText.matchQuery('셋째')!), [
          second.id,
        ]);
      },
    );

    test('a failed job deletes its new boxes and keeps the old ones', () async {
      final s = index();
      await s.replaceUnits(SearchSource.pdf, ok, [
        SearchUnitDraft(body: '원래', rects: boxes('원래')),
      ], sourceRev: 'r1');
      final before = await snapshot(store);
      final oldKeys = await s.blobs.keys(kSearchBlobRoot);
      s.debugLog.clear();
      s.indexer.failNextIndexWrites(1);
      await expectLater(
        s.replaceUnits(SearchSource.pdf, ok, [
          SearchUnitDraft(body: '새것', rects: boxes('새것')),
        ], sourceRev: 'r2'),
        throwsStateError,
      );
      expect(s.debugLog, hasLength(2));
      expect(s.debugLog.first, startsWith('put '));
      expect(s.debugLog.last, 'delete ${s.debugLog.first.substring(4)}');
      expect(await s.blobs.keys(kSearchBlobRoot), oldKeys);
      expect(await snapshot(store), before);
      expect(await s.sourceRevOf(SearchSource.pdf, ok), 'r1');
      // A commit retry (storage failure) is not a failure of the call.
      store.queue.failNextCommits(1);
      await s.replaceUnits(SearchSource.pdf, ok, const [
        SearchUnitDraft(body: '다시'),
      ], sourceRev: 'r3');
      expect(await s.sourceRevOf(SearchSource.pdf, ok), 'r3');
      expect(await s.blobs.keys(kSearchBlobRoot), isEmpty);
    });

    test('orphan boxes are removed on the first writer use after open; referenced ones stay', () async {
      final dir = await Directory.systemTemp.createTemp('core_t33a_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/notes.sqlite';
      final idb = newIdbFactoryMemory();
      var s = await openDraftStore(path, idb);
      await s.search.replaceUnits(SearchSource.pdf, ok, [
        SearchUnitDraft(body: '남음', rects: boxes('남음')),
      ], sourceRev: 'r');
      final kept = await s.search.blobs.keys(kSearchBlobRoot);
      expect(kept, hasLength(1));
      // A cut call: its box was put, its rows never committed.
      const orphan = 'si/pdf/$_asset/1/0123456789abcdef-0000';
      await s.search.blobs.put(orphan, SearchRectsCodec.encode(boxes('끊김')));
      await s.close();

      s = await openDraftStore(path, idb);
      addTearDown(s.close);
      expect(
        await s.search.blobs.keys(kSearchBlobRoot),
        unorderedEquals([...kept, orphan]),
      );
      // Reads do not clean; the first writer call does, before its own puts.
      expect(await s.search.sourceRevs(SearchSource.pdf), {ok: 'r'});
      expect(await s.search.blobs.keys(kSearchBlobRoot), hasLength(2));
      await s.search.removeOwner(SearchSource.pdf, '$_asset#9');
      expect(s.search.debugLog, ['orphan $orphan']);
      expect(await s.search.blobs.keys(kSearchBlobRoot), kept);
      // The asset chunks and drafts share the store: other prefixes are untouched.
      expect(await s.search.blobs.keys(''), kept);
    });
  });

  group('rebuild', () {
    Future<void> fill() async {
      final s = await add([
        PageObjectFixtures.textBox(pageId: pages[0], id: 't1', text: '다시 만들기'),
        PageObjectFixtures.math(pageId: pages[0], id: 'm1'),
        PageObjectFixtures.textBox(pageId: pages[0], id: 't2', text: ''),
        PageObjectFixtures.textBox(pageId: pages[0], id: 't3', text: '지운 글'),
      ]);
      await s
          .execute(RemoveElements(pageId: pages[0], elementIds: const ['t3']))
          .persisted;
      await s.close();
      await store.handwriting.put(
        HandwritingText(
          noteId: n.id,
          pageId: pages[1],
          engineId: 'fake/1:ko',
          sourceRev: '0' * 16,
          lines: const [
            HandwritingLine(
              text: '손글씨 줄',
              rect: PageRect(1, 2, 3, 4),
              strokeIds: ['s'],
            ),
          ],
          createdAt: 1,
        ),
      );
      await index().replaceUnits(SearchSource.pdf, '$_asset#0', [
        SearchUnitDraft(
          body: '다시 피디에프',
          rects: [for (var i = 0; i < 7; i++) const PageRect(0, 0, 0.1, 0.1)],
        ),
      ], sourceRev: 'r');
    }

    test('rebuilding true → false, lastRebuildAt; ink / text / math the same, pdf dropped', () async {
      await fill();
      final before = await snapshot(store);
      final statuses = <SearchIndexStatus>[];
      final sub = index().status.listen(statuses.add);
      addTearDown(sub.cancel);
      await index().rebuild();
      await Future<void>.delayed(Duration.zero);
      expect(statuses.first, const SearchIndexStatus());
      expect(statuses.any((s) => s.rebuilding), isTrue);
      expect(statuses.last.rebuilding, isFalse);
      final at = statuses.last.lastRebuildAt!;
      final after = await snapshot(store);
      expect(after, [
        for (final r in before)
          if (!r.startsWith('U|pdf|') && !r.startsWith('O|pdf|')) r,
      ]);
      expect(await index().sourceRevs(SearchSource.pdf), isEmpty);
      expect(await index().blobs.keys(kSearchBlobRoot), isEmpty);
      await expectFtsInSync(store);
      final kv = await (store.db.select(
        store.db.kv,
      )..where((t) => t.key.equals(KvKeys.searchLastRebuildAt))).getSingle();
      expect(kv.value, '$at');

      // Idempotent.
      await index().rebuild();
      expect(await snapshot(store), after);
      await expectFtsInSync(store);
      expect(
        await ftsMatch(store, SearchText.matchQuery('만들기')!),
        hasLength(1),
      );
    });

    test('rebuild({text}) leaves the other sources as they are', () async {
      await fill();
      final before = await snapshot(store);
      await index().rebuild(sources: {SearchSource.text});
      expect(await snapshot(store), before);
      expect(await index().blobs.keys(kSearchBlobRoot), hasLength(1));
      await expectFtsInSync(store);
    });

    test('queue jobs of $kSearchRebuildChunk source rows', () async {
      final drafts = [
        for (var p = 0; p < 5; p++)
          PageDraft(
            size: PageSize.a4Portrait,
            background: const BlankBackground(),
            objects: [
              for (var i = 0; i < 90; i++)
                PageObjectFixtures.textBox(
                  pageId: 'x',
                  id: 'b$p-$i',
                  text: '글 $p $i',
                  rect: PageRect(10, 10.0 + i * 5, 200, 14.0 + i * 5),
                ),
            ],
          ),
      ];
      await store.library.createNote(title: 'many', pages: drafts);
      final before = await snapshot(store);
      expect(before.where((r) => r.startsWith('U|')), hasLength(450));
      final t0 = store.queue.debugTransactionCount;
      await index().rebuild(sources: {SearchSource.text});
      // drop + 3 chunks (200, 200, 50) + kv.
      expect(store.queue.debugTransactionCount - t0, 5);
      expect(await snapshot(store), before);
    });

    test('(ink spacing) ink rows without the compact terms are rebuilt once at open', () async {
      final dir = await Directory.systemTemp.createTemp('core_ink_terms_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/notes.sqlite';
      final idb = newIdbFactoryMemory();
      var s = await openDraftStore(path, idb);
      final note = await s.library.createNote(title: 'ink');
      final page = (await s.content.pagesOf(note.id)).single.id;
      await s.handwriting.put(
        HandwritingText(
          noteId: note.id,
          pageId: page,
          engineId: 'fake/1:ko',
          sourceRev: '0000000000000000',
          lines: const [
            HandwritingLine(
              text: '회의 록',
              rect: PageRect(10, 10, 200, 30),
              strokeIds: ['s1'],
            ),
          ],
          createdAt: 1,
        ),
      );
      expect(await s.search.searchPages('회의록'), hasLength(1));
      // As an older build wrote it: plain terms, no kv value.
      await s.db.customStatement("UPDATE search_fts SET g = '회의 록'");
      await (s.db.delete(
        s.db.kv,
      )..where((t) => t.key.equals(KvKeys.searchInkTermsVersion))).go();
      expect(await s.search.searchPages('회의록'), isEmpty);
      await s.close();

      s = await openDraftStore(path, idb);
      addTearDown(s.close);
      await s.search.status.firstWhere(
        (st) => !st.rebuilding && st.lastRebuildAt != null,
      );
      expect(await s.search.searchPages('회의록'), hasLength(1));
      final kv = await (s.db.select(
        s.db.kv,
      )..where((t) => t.key.equals(KvKeys.searchInkTermsVersion))).getSingle();
      expect(kv.value, '$kInkTermsVersion');
    });

    test('(ink spacing) without ink rows the ink terms version is recorded at open', () async {
      final dir = await Directory.systemTemp.createTemp('core_ink_terms0_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/notes.sqlite';
      final idb = newIdbFactoryMemory();
      var s = await openDraftStore(path, idb);
      await (s.db.delete(
        s.db.kv,
      )..where((t) => t.key.equals(KvKeys.searchInkTermsVersion))).go();
      await s.close();

      s = await openDraftStore(path, idb);
      final kv = await (s.db.select(
        s.db.kv,
      )..where((t) => t.key.equals(KvKeys.searchInkTermsVersion))).getSingle();
      expect(kv.value, '$kInkTermsVersion');
      // Ink written now already has the terms: the next open rebuilds nothing.
      final note = await s.library.createNote(title: 'ink');
      final page = (await s.content.pagesOf(note.id)).single.id;
      await s.handwriting.put(
        HandwritingText(
          noteId: note.id,
          pageId: page,
          engineId: 'fake/1:ko',
          sourceRev: '0000000000000000',
          lines: const [
            HandwritingLine(
              text: '회의 록',
              rect: PageRect(10, 10, 200, 30),
              strokeIds: ['s1'],
            ),
          ],
          createdAt: 1,
        ),
      );
      await s.close();

      s = await openDraftStore(path, idb);
      addTearDown(s.close);
      final st = await s.search.status.first;
      expect(st.rebuilding, isFalse);
      expect(st.lastRebuildAt, isNull);
      expect(await s.search.searchPages('회의록'), hasLength(1));
    });

    test(
      'a changed normalizer version rebuilds at open, without blocking it',
      () async {
        final dir = await Directory.systemTemp.createTemp('core_t33a_');
        addTearDown(() => dir.delete(recursive: true));
        final path = '${dir.path}/notes.sqlite';
        final idb = newIdbFactoryMemory();
        var s = await openDraftStore(path, idb);
        final note = await s.library.createNote(
          title: 'v',
          pages: [
            PageDraft(
              size: PageSize.a4Portrait,
              background: const BlankBackground(),
              objects: [
                PageObjectFixtures.textBox(pageId: 'x', id: 'v1', text: '판 올림'),
              ],
            ),
          ],
        );
        final before = await snapshot(s);
        // An index built by another normalizer: wrong rows, another version.
        await s.db.customStatement(
          "INSERT INTO search_fts (search_fts) VALUES ('delete-all')",
        );
        await s.db.delete(s.db.searchUnits).go();
        await s.db
            .into(s.db.kv)
            .insertOnConflictUpdate(
              KvCompanion.insert(
                key: KvKeys.searchNormalizerVersion,
                value: '0',
              ),
            );
        await s.close();

        s = await openDraftStore(path, idb);
        addTearDown(s.close);
        final status = await s.search.status.firstWhere(
          (st) => !st.rebuilding && st.lastRebuildAt != null,
        );
        expect(status.pendingOwners, 0);
        expect(await snapshot(s), before);
        final kv =
            await (s.db.select(s.db.kv)
                  ..where((t) => t.key.equals(KvKeys.searchNormalizerVersion)))
                .getSingle();
        expect(kv.value, '${SearchText.normalizerVersion}');
        expect(await s.content.pagesOf(note.id), hasLength(1));
      },
    );
  });

  group('index failures (C-13)', () {
    test('the source write commits and completes; the owner is pending; status shows it', () async {
      final statuses = <SearchIndexStatus>[];
      final sub = index().status.listen(statuses.add);
      addTearDown(sub.cancel);
      index().indexer.failNextIndexWrites(1);
      final s = await add([
        PageObjectFixtures.textBox(pageId: pages[0], id: 't1', text: '보류'),
      ]);
      await s.close();
      await Future<void>.delayed(Duration.zero);
      expect(await stored('t1'), isA<TextBoxObject>());
      final owner = (await ownerOf(store, SearchSource.text, 't1'))!;
      expect(owner.pending, isTrue);
      expect(await unitsOf(store, SearchSource.text, 't1'), isEmpty);
      expect(statuses.last.pendingOwners, 1);
      expect(index().indexer.pendingOwners, 1);

      // The next write transaction (any) re-indexes it.
      await store.library.renameNote(n.id, 'renamed');
      await Future<void>.delayed(Duration.zero);
      expect((await ownerOf(store, SearchSource.text, 't1'))!.pending, isFalse);
      expect((await unitsOf(store, SearchSource.text, 't1')).single.body, '보류');
      expect(statuses.last.pendingOwners, 0);
      expect([for (final st in statuses) st.pendingOwners], [0, 1, 0]);
    });

    test('no timer retries: pending stays until a write comes', () {
      fakeAsync((async) {
        late DriftNoteStore st;
        openStore(clock: async.getClock(DateTime.utc(2026, 11, 6)))
            .then((v) => st = v);
        async.flushMicrotasks();
        late List<PageId> ps;
        st.library
            .createNote(title: 'f', pages: const [PageDraft.blankA4])
            .then((note) async {
              ps = [for (final p in await st.content.pagesOf(note.id)) p.id];
              st.search.indexer.failNextIndexWrites(1);
              final session = await st.openSession(note.id);
              await session.openPage(ps[0]);
              await session
                  .execute(
                    AddObjects(
                      pageId: ps[0],
                      objects: [
                        PageObjectFixtures.textBox(pageId: ps[0], id: 'f1'),
                      ],
                    ),
                  )
                  .persisted;
              await session.close();
            });
        async.flushMicrotasks();
        expect(st.search.indexer.pendingOwners, 1);
        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(hours: 1));
        expect(st.search.indexer.pendingOwners, 1);
        st.library.createFolder(name: 'w');
        async.flushMicrotasks();
        expect(st.search.indexer.pendingOwners, 0);
        expect(async.pendingTimers, isEmpty);
        st.close();
        async.flushMicrotasks();
      });
    });

    test(
      'at most $kSearchRetryPerTransaction owners per transaction',
      () async {
        index().indexer.failNextIndexWrites(25);
        final s = await add([
          for (var i = 0; i < 25; i++)
            PageObjectFixtures.textBox(
              pageId: pages[0],
              id: 'p$i',
              text: '보류 $i',
              rect: PageRect(10, 10.0 + i * 10, 200, 18.0 + i * 10),
            ),
        ]);
        await s.close();
        expect(index().indexer.pendingOwners, 25);
        await store.library.renameNote(n.id, 'one');
        expect(index().indexer.pendingOwners, 5);
        await store.library.renameNote(n.id, 'two');
        expect(index().indexer.pendingOwners, 0);
        expect(await unitCount(store), 25);
        await expectFtsInSync(store);
      },
    );

    test(
      'a pending owner whose source row is gone: the retry removes it',
      () async {
        index().indexer.failNextIndexWrites(1);
        await store.handwriting.put(
          HandwritingText(
            noteId: n.id,
            pageId: pages[0],
            engineId: 'fake/1:ko',
            sourceRev: '0' * 16,
            lines: const [
              HandwritingLine(text: '사라짐', rect: PageRect.zero, strokeIds: []),
            ],
            createdAt: 1,
          ),
        );
        final key = HandwritingText.idFor(pages[0]);
        expect((await ownerOf(store, SearchSource.ink, key))!.pending, isTrue);
        await store.db.delete(store.db.handwriting).go();
        await store.library.renameNote(n.id, 'x');
        expect(await ownerOf(store, SearchSource.ink, key), isNull);
        expect(index().indexer.pendingOwners, 0);
      },
    );

    test(
      'a failing retry keeps the owner pending (the write still commits)',
      () async {
        index().indexer.failNextIndexWrites(2);
        final s = await add([
          PageObjectFixtures.textBox(pageId: pages[0], id: 't1', text: '두 번'),
        ]);
        await s.close();
        await store.library.renameNote(n.id, 'retry fails');
        expect((await store.library.getNote(n.id))!.title, 'retry fails');
        expect(index().indexer.pendingOwners, 1);
        await store.library.renameNote(n.id, 'retry works');
        expect(index().indexer.pendingOwners, 0);
      },
    );

    test('store open: pending owners are retried by one queue job', () async {
      final dir = await Directory.systemTemp.createTemp('core_t33a_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/notes.sqlite';
      final idb = newIdbFactoryMemory();
      var s = await openDraftStore(path, idb);
      final note = await s.library.createNote(
        title: 'o',
        pages: const [PageDraft.blankA4],
      );
      final page = (await s.content.pagesOf(note.id)).single.id;
      s.search.indexer.failNextIndexWrites(1);
      final session = await s.openSession(note.id);
      await session.openPage(page);
      await session
          .execute(
            AddObjects(
              pageId: page,
              objects: [
                PageObjectFixtures.textBox(pageId: page, id: 'o1', text: '열기'),
              ],
            ),
          )
          .persisted;
      await session.close();
      expect(s.search.indexer.pendingOwners, 1);
      await s.close();

      s = await openDraftStore(path, idb);
      addTearDown(s.close);
      await s.flush();
      expect(s.search.indexer.pendingOwners, 0);
      expect(await s.search.status.first, const SearchIndexStatus());
      expect((await unitsOf(s, SearchSource.text, 'o1')).single.body, '열기');
    });
  });
}
