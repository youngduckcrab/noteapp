// PdfSearchIndexer (m5-7/06-pdf 4.1.1, 6.4.2–6.4.4; 8.2 T27) on CORE's fake store (memory
// search index) + FakePdfEngine text + DefaultPdfDocumentPool, through the src-only
// createPdfSearchIndexer with a hand gate. A wrapper search index ([_Search]) owns the rebuild
// status (set by hand), can hold a replaceUnits and drops the pdf rows like CORE's rebuild.
// Order 1 … n−1 then '#0', resume after dispose, '#0' current → skipped, a new sourceRev →
// again, a rebuild in the middle (no writes while it runs, every page afterwards), an overlapped
// '#0' write (removeOwner, a later indexer re-judges), already rebuilding at start, corrupt /
// password → '#0' empty + one report, engineUnavailable → stop, a pending replaceUnits holds the
// next page, a closed gate holds everything, the web document release (S-8) and dispose rules;
// the app gate's conditions (6.4.3).
import 'dart:async';
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/search_index/indexer_gate.dart';
import 'package:pdf_io/src/search_index/pdf_search_indexer.dart';
import 'package:pdf_io/src/search_index/unit_builder.dart';
import 'package:pdf_io/testing.dart';

import '../support/export_world.dart' show captureFlutterErrors;

const core.SearchSource _pdf = core.SearchSource.pdf;

/// The fake store's search index with a hand-set rebuild status, held writes and a log.
final class _Search implements core.SearchIndex {
  _Search(this.inner);

  final core.SearchIndex inner;
  final List<String> log =
      []; // 'replace <page>' / 'remove <page>' (asset prefix cut)
  bool rebuilding = false;
  int writesWhileRebuilding = 0;

  /// The next replaceUnits of [holdKey] (any key when null) waits for this.
  Completer<void>? hold;
  String? holdKey;
  final StreamController<core.SearchIndexStatus> _status =
      StreamController.broadcast(sync: true);

  void setRebuilding(bool value) {
    rebuilding = value;
    _status.add(core.SearchIndexStatus(rebuilding: value));
  }

  /// What CORE's rebuild({pdf}) does to pdf rows: drops them all.
  Future<void> dropPdfRows() => inner.rebuild(sources: {_pdf});

  static String _short(String key) => key.substring(key.indexOf('#'));

  @override
  Stream<core.SearchIndexStatus> get status => Stream.multi((c) {
    c.add(core.SearchIndexStatus(rebuilding: rebuilding));
    final sub = _status.stream.listen(c.add);
    c.onCancel = sub.cancel;
  });

  @override
  Future<void> replaceUnits(
    core.SearchSource source,
    String ownerKey,
    List<core.SearchUnitDraft> units, {
    required String sourceRev,
  }) async {
    log.add('replace ${_short(ownerKey)}');
    if (rebuilding) writesWhileRebuilding++;
    final h = hold;
    if (h != null && (holdKey == null || ownerKey.endsWith(holdKey!))) {
      hold = null;
      await h.future;
    }
    return inner.replaceUnits(source, ownerKey, units, sourceRev: sourceRev);
  }

  @override
  Future<void> removeOwner(core.SearchSource source, String ownerKey) {
    log.add('remove ${_short(ownerKey)}');
    return inner.removeOwner(source, ownerKey);
  }

  @override
  Future<String?> sourceRevOf(core.SearchSource source, String ownerKey) =>
      inner.sourceRevOf(source, ownerKey);

  @override
  Future<Map<String, String>> sourceRevs(core.SearchSource source) =>
      inner.sourceRevs(source);

  @override
  Future<List<core.PageSearchHit>> searchPages(
    String query, {
    int limit = 100,
    core.NoteId? withinNote,
  }) => inner.searchPages(query, limit: limit, withinNote: withinNote);

  @override
  Future<void> rebuild({Set<core.SearchSource>? sources}) =>
      inner.rebuild(sources: sources);
}

/// The fake store with [_Search] as its search index (the indexer reads assets and search).
final class _Store implements core.NoteStore {
  _Store(this.inner) : search = _Search(inner.search);

  final core.NoteStore inner;

  @override
  final _Search search;

  @override
  core.AssetStore get assets => inner.assets;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Slots by hand: [open] gives them at once; otherwise they wait for [openUp]. [releaseNext]
/// asks the indexer to give its document back on the next wait (web S-8).
final class _Gate implements IndexerGate {
  bool open = true;

  /// Slots given before the gate closes by itself (null = no limit).
  int? closeAfter;
  bool releaseNext = false;
  int slots = 0;
  final List<Completer<void>> _waiting = [];

  int get waiting => _waiting.length;

  @override
  Future<void> nextSlot({void Function()? releaseDocument}) {
    final limit = closeAfter;
    if (limit != null && slots >= limit) open = false;
    if (open) {
      slots++;
      return Future<void>.value();
    }
    if (releaseNext) {
      releaseNext = false;
      releaseDocument?.call();
    }
    final c = Completer<void>();
    _waiting.add(c);
    return c.future.then((_) => slots++);
  }

  void openUp() {
    open = true;
    closeAfter = null;
    for (final c in _waiting) {
      c.complete();
    }
    _waiting.clear();
  }
}

/// The pool, counting leases held now and acquires.
final class _Pool implements PdfDocumentPool {
  _Pool(this.inner);

  final PdfDocumentPool inner;
  int held = 0, acquires = 0;

  @override
  Future<PdfDocumentLease> acquire(core.AssetId assetId) async {
    acquires++;
    final lease = await inner.acquire(assetId);
    held++;
    return _Lease(lease, () => held--);
  }

  @override
  void adopt(core.AssetId assetId, PdfEngineDocument document) =>
      inner.adopt(assetId, document);

  @override
  Stream<core.AssetId> get assetArrived => inner.assetArrived;

  @override
  Stream<core.RemoteAssetProgress>? requestRemote(core.AssetId assetId) =>
      inner.requestRemote(assetId);

  @override
  int get openCount => inner.openCount;

  @override
  Future<void> closeIdle() => inner.closeIdle();

  @override
  Future<void> dispose() => inner.dispose();
}

final class _Lease implements PdfDocumentLease {
  _Lease(this.inner, this.onRelease);
  final PdfDocumentLease inner;
  final void Function() onRelease;
  bool _released = false;

  @override
  core.AssetId get assetId => inner.assetId;

  @override
  PdfEngineDocument get document => inner.document;

  @override
  void release() {
    if (_released) return;
    _released = true;
    onRelease();
    inner.release();
  }
}

/// One rect per code unit, 6 × 10 pt boxes in a row (line breaks have none).
PdfPageTextData _page(int index, String text) => PdfPageTextData(
  pageIndex: index,
  text: text,
  charRects: [
    for (var i = 0; i < text.length; i++)
      text[i] == '\r' || text[i] == '\n'
          ? ui.Rect.zero
          : ui.Rect.fromLTWH(10 + 6.0 * i, 30, 6, 10),
  ],
);

final class _World {
  _World({int pages = 3}) {
    engine = FakePdfEngine(
      pageCount: pages,
      pageSize: const ui.Size(600, 800),
      texts: {
        for (var i = 0; i < pages; i++) i: _page(i, 'page $i text\r\n쪽 $i'),
      },
    );
    pool = _Pool(
      DefaultPdfDocumentPool(
        engine: engine,
        gateway: CorePdfNoteGateway(inner),
      ),
    );
  }

  final core.NoteStore inner = core_testing.createFakeNoteStore();
  late final _Store store = _Store(inner);
  late final FakePdfEngine engine;
  late final _Pool pool;
  final _Gate gate = _Gate();
  final List<PdfSearchIndexer> _indexers = [];
  int _pdfs = 0;

  _Search get search => store.search;

  PdfSearchIndexer indexer() {
    final indexer = createPdfSearchIndexer(store, pool: pool, gate: gate);
    _indexers.add(indexer);
    return indexer;
  }

  Future<core.AssetId> addPdf() async {
    final bytes = Uint8List.fromList(
      '%PDF-1.7\n% fixture ${_pdfs++}\n%%EOF\n'.codeUnits,
    );
    final asset = await inner.assets.put(
      bytes,
      type: core.AssetType.pdf,
      mimeType: 'application/pdf',
      fileName: 'f$_pdfs.pdf',
    );
    return asset.id;
  }

  /// ownerKey suffix ('#i') → sourceRev of [assetId]'s owners.
  Future<Map<String, String>> owners(core.AssetId assetId) async => {
    for (final e in (await inner.search.sourceRevs(_pdf)).entries)
      if (e.key.startsWith('$assetId#'))
        e.key.substring(assetId.length): e.value,
  };

  Future<void> dispose() async {
    for (final i in _indexers) {
      await i.dispose();
    }
    await pool.dispose();
    await inner.close();
  }
}

/// Lets the microtask / event queue drain until [done] holds (no real time).
Future<void> _until(bool Function() done, {int rounds = 200}) async {
  for (var i = 0; i < rounds && !done(); i++) {
    await pumpEventQueue();
  }
  expect(done(), isTrue, reason: 'condition not reached');
}

Future<void> _settle() => pumpEventQueue(times: 40);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _World w;
  setUp(() => w = _World());
  tearDown(() => w.dispose());

  String want(core.AssetId id) => PdfSearchUnitBuilder.sourceRevOf(id);

  test('a new asset: pages 1 … n−1, then #0; units = page text, one rect per '
      'code unit', () async {
    final id = await w.addPdf();
    w.indexer().start();
    await _until(() => w.search.log.length == 3);
    await _settle();
    expect(w.search.log, ['replace #1', 'replace #2', 'replace #0']);
    expect(await w.owners(id), {
      '#0': want(id),
      '#1': want(id),
      '#2': want(id),
    });
    expect(w.engine.loadTextCalls, [1, 2, 0]);
    final hits = await w.inner.search.searchPages('page 2 text');
    expect(hits, isEmpty, reason: 'no note uses the asset yet');
    expect(w.pool.held, 0, reason: 'the lease is given back');
    expect(w.gate.slots, 3);
  });

  test('the units hold the page text, its rects and the page aspect', () async {
    final id = await w.addPdf();
    final note = await w.inner.library.createNote(
      title: 'n',
      pages: [
        core.PageDraft(
          size: core.PageSize.a4Portrait,
          background: core.PdfBackground(assetId: id, pdfPageIndex: 2),
        ),
      ],
    );
    w.indexer().start();
    await _until(() => w.search.log.length == 3);
    await _settle();
    final hits = await w.inner.search.searchPages('쪽 2');
    expect(hits.single.noteId, note.id);
    expect(hits.single.source, _pdf);
    expect(hits.single.rects, isNotEmpty, reason: 'rects as page fractions');
  });

  test('dispose in the middle → the next start writes only the rest', () async {
    final id = await w.addPdf();
    w.gate.closeAfter = 1;
    final a = w.indexer()..start();
    await _until(() => w.search.log.length == 1 && w.gate.waiting == 1);
    await a.dispose();
    w.gate.openUp();
    await _settle();
    expect(w.search.log, ['replace #1'], reason: 'nothing after dispose');
    expect(await w.owners(id), {'#1': want(id)});
    w.engine.loadTextCalls.clear();

    w.indexer().start();
    await _until(() => w.search.log.length == 3);
    await _settle();
    expect(w.search.log.skip(1), ['replace #2', 'replace #0']);
    expect(w.engine.loadTextCalls, [2, 0], reason: 'page 1 is current');
  });

  test("'#0' current → skipped; another sourceRev → indexed again", () async {
    final id = await w.addPdf();
    w.indexer().start();
    await _until(() => w.search.log.length == 3);
    await _settle();
    w.search.log.clear();
    w.engine.loadTextCalls.clear();

    w.indexer().start();
    await _settle();
    expect(w.search.log, isEmpty);
    expect(w.engine.loadTextCalls, isEmpty);

    // an older extractor wrote this asset ('#0' and '#1' with another sourceRev)
    for (final i in [0, 1]) {
      await w.inner.search.replaceUnits(
        _pdf,
        '$id#$i',
        const [],
        sourceRev: '$id:${core.SearchText.normalizerVersion}:x0',
      );
    }
    w.indexer().start();
    await _until(() => w.search.log.length == 2);
    await _settle();
    expect(w.search.log, ['replace #1', 'replace #0'], reason: '#2 is current');
    expect(await w.owners(id), {
      '#0': want(id),
      '#1': want(id),
      '#2': want(id),
    });
  });

  test('a rebuild in the middle of an asset → no writes while it runs, every '
      'page afterwards (PDF-M4)', () async {
    final id = await w.addPdf();
    w.gate.closeAfter = 1;
    w.indexer().start();
    await _until(() => w.search.log.length == 1 && w.gate.waiting == 1);
    w.search.setRebuilding(true);
    await w.search.dropPdfRows();
    w.gate.openUp();
    await _settle();
    expect(w.search.writesWhileRebuilding, 0);
    expect(await w.owners(id), isEmpty);
    w.search.setRebuilding(false);
    await _until(() => w.search.log.length == 4);
    await _settle();
    expect(w.search.log, [
      'replace #1',
      'replace #1',
      'replace #2',
      'replace #0',
    ], reason: 're-judged after the rebuild: page 1 was dropped');
    expect(await w.owners(id), {
      '#0': want(id),
      '#1': want(id),
      '#2': want(id),
    });
  });

  test("a '#0' write committed after the rebuild's delete → removeOwner; a "
      'later indexer re-judges and every page exists', () async {
    final id = await w.addPdf();
    w.search
      ..hold = Completer<void>()
      ..holdKey = '#0';
    final held = w.search.hold!;
    final a = w.indexer()..start();
    await _until(() => w.search.log.length == 3); // '#0' is held
    w.search.setRebuilding(true);
    await w.search.dropPdfRows();
    held.complete(); // the '#0' write lands after the delete
    await _until(() => w.search.log.contains('remove #0'));
    await _settle();
    expect(await w.owners(id), isEmpty, reason: 'no false completion mark');
    expect(debugPdfSearchIndexerQueue(a).dirty, {id});
    await a.dispose(); // the app closes during the rebuild
    w.search.setRebuilding(false);
    await _settle();
    expect(w.search.log, [
      'replace #1',
      'replace #2',
      'replace #0',
      'remove #0',
    ], reason: 'a disposed indexer writes nothing');

    w.indexer().start();
    await _until(() => w.search.log.length == 7);
    await _settle();
    expect(await w.owners(id), {
      '#0': want(id),
      '#1': want(id),
      '#2': want(id),
    });
  });

  test('the same overlap with the indexer kept → it re-indexes the dirty '
      'asset after the rebuild', () async {
    final id = await w.addPdf();
    w.search
      ..hold = Completer<void>()
      ..holdKey = '#0';
    final held = w.search.hold!;
    w.indexer().start();
    await _until(() => w.search.log.length == 3);
    w.search.setRebuilding(true);
    await w.search.dropPdfRows();
    held.complete();
    await _until(() => w.search.log.contains('remove #0'));
    w.search.setRebuilding(false);
    await _until(() => w.search.log.length == 7);
    await _settle();
    expect(w.search.log.skip(4), ['replace #1', 'replace #2', 'replace #0']);
    expect(await w.owners(id), {
      '#0': want(id),
      '#1': want(id),
      '#2': want(id),
    });
  });

  test('already rebuilding at start → waits, then catches up', () async {
    final id = await w.addPdf();
    w.search.setRebuilding(true);
    w.indexer().start();
    await _settle();
    expect(w.search.log, isEmpty);
    expect(w.engine.loadTextCalls, isEmpty);
    w.search.setRebuilding(false);
    await _until(() => w.search.log.length == 3);
    expect(w.search.writesWhileRebuilding, 0);
    expect((await w.owners(id)).keys, unorderedEquals(['#0', '#1', '#2']));
  });

  test('corrupt or password-protected → #0 empty with the current sourceRev, '
      'one report each; not tried again', () async {
    final bad = await w.addPdf();
    final locked = await w.addPdf();
    final good = await w.addPdf();
    w.engine.beforeOpen = (name) async {
      if (name.endsWith(bad)) {
        throw const PdfIoException(PdfErrorCode.corrupt);
      }
      if (name.endsWith(locked)) {
        throw const PdfIoException(PdfErrorCode.passwordCancelled);
      }
    };
    final reports = captureFlutterErrors();
    w.indexer().start();
    await _until(() => w.search.log.length == 5);
    await _settle();
    expect(await w.owners(bad), {'#0': want(bad)});
    expect(await w.owners(locked), {'#0': want(locked)});
    expect((await w.owners(good)).keys, unorderedEquals(['#0', '#1', '#2']));
    expect(reports, hasLength(2));
    final opens = w.engine.openCalls.length;
    w.indexer().start();
    await _settle();
    expect(w.engine.openCalls.length, opens, reason: 'all three are done');
  });

  test('a page whose text fails → that page empty, one report, the next pages '
      'go on', () async {
    final id = await w.addPdf();
    w.engine.beforeLoadText = (i) async {
      if (i == 1) throw StateError('broken text');
    };
    final reports = captureFlutterErrors();
    w.indexer().start();
    await _until(() => w.search.log.length == 3);
    await _settle();
    expect((await w.owners(id)).keys, unorderedEquals(['#0', '#1', '#2']));
    expect(reports, hasLength(1));
    final hits = await w.inner.search.searchPages('page 1');
    expect(hits, isEmpty);
  });

  test('engineUnavailable → the loop stops and drops its queue', () async {
    await w.addPdf();
    await w.addPdf();
    w.engine.initError = const PdfIoException(PdfErrorCode.engineUnavailable);
    final reports = captureFlutterErrors();
    final indexer = w.indexer()..start();
    await _until(() => !debugPdfSearchIndexerQueue(indexer).running);
    await _settle();
    expect(w.search.log, isEmpty);
    expect(debugPdfSearchIndexerQueue(indexer).queued, isEmpty);
    expect(reports, hasLength(1));
  });

  test('a replaceUnits that does not complete holds the next page', () async {
    await w.addPdf();
    final hold = w.search.hold = Completer<void>();
    w.indexer().start();
    await _until(() => w.search.log.length == 1);
    await _settle();
    expect(w.engine.loadTextCalls, [1]);
    hold.complete();
    await _until(() => w.search.log.length == 3);
    expect(w.engine.loadTextCalls, [1, 2, 0]);
  });

  test(
    'a closed gate: no page read, nothing written; open → it goes on',
    () async {
      await w.addPdf();
      w.gate.open = false;
      w.indexer().start();
      await _settle();
      expect(w.gate.waiting, 1);
      expect(w.engine.loadTextCalls, isEmpty);
      expect(w.search.log, isEmpty);
      w.gate.openUp();
      await _until(() => w.search.log.length == 3);
    },
  );

  test('web S-8: another document opens → the lease is given back; the gate '
      'opens → borrowed again, page progress kept', () async {
    await w.addPdf();
    w.gate.closeAfter = 1;
    w.gate.releaseNext = true;
    w.indexer().start();
    await _until(() => w.search.log.length == 1 && w.gate.waiting == 1);
    expect(w.pool.held, 0, reason: 'given back while waiting');
    expect(w.pool.acquires, 1);
    w.gate.openUp();
    await _until(() => w.search.log.length == 3);
    expect(w.pool.acquires, 2);
    expect(w.engine.loadTextCalls, [1, 2, 0]);
    expect(w.search.log, ['replace #1', 'replace #2', 'replace #0']);
  });

  test(
    'bytesArrived queues a new PDF asset; other assets are ignored',
    () async {
      final first = await w.addPdf();
      w.indexer().start();
      await _until(() => w.search.log.length == 3);
      final second = await w.addPdf();
      await w.inner.assets.put(
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
        type: core.AssetType.image,
        mimeType: 'image/png',
      );
      await _until(() => w.search.log.length == 6);
      await _settle();
      expect((await w.owners(first)).length, 3);
      expect((await w.owners(second)).length, 3);
    },
  );

  test('catch-up order: most recent asset first', () async {
    final older = await w.addPdf();
    final newer = await w.addPdf();
    w.engine.beforeLoadText = null;
    final opened = <String>[];
    w.engine.beforeOpen = (name) async => opened.add(name);
    w.indexer().start();
    await _until(() => w.search.log.length == 6);
    expect(opened, ['asset:$newer', 'asset:$older']);
  });

  test('dispose before start, twice, and start after dispose', () async {
    await w.addPdf();
    final indexer = w.indexer();
    await indexer.dispose();
    indexer.start();
    await _settle();
    expect(w.search.log, isEmpty);
    expect(debugPdfSearchIndexerState(indexer).started, isFalse);
    await indexer.dispose();
    final other = w.indexer()..start();
    await other.dispose();
    await other.dispose();
    await _settle();
    expect(kIsWeb, isFalse);
  });

  test('the public constructor: its own pool, the always-open gate', () async {
    final indexer = PdfSearchIndexer(w.inner);
    final state = debugPdfSearchIndexerState(indexer);
    expect(state.pool, isNull);
    expect(state.gate, isA<AlwaysOpenIndexerGate>());
    indexer.start();
    await indexer.dispose(); // no asset: nothing opened, nothing to wait for
  });

  group('AppIndexerGate (6.4.3)', () {
    PdfRenderStats stats({int queued = 0, int inflight = 0, int open = 0}) =>
        PdfRenderStats(
          previewBytes: 0,
          tileBytes: 0,
          thumbnailBytes: 0,
          liveImages: 0,
          queued: queued,
          inflight: inflight,
          rendered: 0,
          cancelled: 0,
          lastRenderMs: 0,
          p95RenderMs: 0,
          openDocuments: open,
          overBudgetBytes: 0,
        );

    ({AppIndexerGate gate, ValueNotifier<PdfRenderStats> render}) appGate({
      required bool web,
    }) {
      final render = ValueNotifier(PdfRenderStats.zero);
      final gateProvider = Provider<AppIndexerGate>(
        (ref) => AppIndexerGate(ref, web: web),
        name: 'testAppIndexerGateProvider',
      );
      final container = ProviderContainer(
        overrides: [pdfRenderStatsProvider.overrideWithValue(render)],
      );
      addTearDown(container.dispose);
      return (gate: container.read(gateProvider), render: render);
    }

    test('render queue, app hidden, and (web) another document', () {
      final (:gate, :render) = appGate(web: true);
      expect(gate.closedBecause(), isNull);
      render.value = stats(queued: 1);
      expect(gate.closedBecause(), IndexerGateClosed.rendering);
      render.value = stats(inflight: 2);
      expect(gate.closedBecause(), IndexerGateClosed.rendering);
      render.value = stats(open: 1);
      expect(gate.closedBecause(), isNull, reason: "the indexer's own one");
      render.value = stats(open: 2);
      expect(gate.closedBecause(), IndexerGateClosed.otherDocument);
      final binding = TestWidgetsFlutterBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      addTearDown(
        () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      );
      expect(gate.closedBecause(), IndexerGateClosed.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(gate.closedBecause(), IndexerGateClosed.otherDocument);
      final native = appGate(web: false);
      native.render.value = stats(open: 3);
      expect(native.gate.closedBecause(), isNull, reason: 'web only (S-8)');
    });

    test('nextSlot: the document released once, waits while closed, then '
        'the slice gap', () {
      fakeAsync((async) {
        final (:gate, :render) = appGate(web: true);
        render.value = stats(open: 2);
        var released = 0, given = 0;
        gate.nextSlot(releaseDocument: () => released++).then((_) => given++);
        async.elapse(const Duration(seconds: 1));
        expect(released, 1);
        expect(given, 0);
        render.value = stats(open: 1);
        async.elapse(PdfTuning.indexSliceGap);
        expect(given, 1);
        gate.nextSlot().then((_) => given++);
        async.flushMicrotasks();
        expect(given, 1, reason: 'within the gap after the last slot');
        async.elapse(PdfTuning.indexSliceGap);
        expect(given, 2);
      });
    });
  });
}
