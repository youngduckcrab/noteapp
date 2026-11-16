// E-17: PagePanelThumbnail (04-editor 6.11.3, EDITOR-S7, contract 7.2.11
// '페이지 패널 썸네일', 7.2.16 v1.1): a page loaded in the session →
// ink.InkPageThumbnail of the session content, refreshed 500 ms after a
// change; a fresh cache entry → Image.memory; a stale one → loadPage once;
// never openPage; the INK widget gets ink.pageBackgroundBuildersProvider and
// ink.pencilGrainProvider values (the EDITOR never overrides them).
// (v2.13-thumbs) The page objects (shapes, images, text, formulas) are part of
// the thumbnail on paths 1 and 3 (K-8 screen = thumbnail) and an object edit
// refreshes it: the thumbnail raster shows a filled shape and an image object.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:feature_editor/src/ui/pages/page_panel.dart';
import 'package:feature_editor/src/ui/pages/page_panel_thumbnail.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

/// A 1×1 PNG.
final Uint8List _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Records the reader calls (path 2 getPage, path 3 loadPage).
class _RecordingReader implements core.NoteContentReader {
  _RecordingReader(this.inner);
  final core.NoteContentReader inner;
  final List<String> calls = [];

  @override
  Future<List<core.Page>> pagesOf(core.NoteId noteId) => inner.pagesOf(noteId);

  @override
  Future<core.PageContent> loadPage(core.PageId pageId) {
    calls.add('loadPage:$pageId');
    return inner.loadPage(pageId);
  }

  @override
  Future<core.Page?> getPage(core.PageId pageId) {
    calls.add('getPage:$pageId');
    return inner.getPage(pageId);
  }
}

Future<void> _openPanel(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorToolbar.pagePanelKey));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Finder _thumbOf(String pageId) => find.descendant(
  of: find.byKey(PagePanel.itemKey(pageId)),
  matching: find.byType(PagePanelThumbnail),
);

ink.InkPageThumbnail _inkThumbOf(WidgetTester tester, String pageId) =>
    tester.widget<ink.InkPageThumbnail>(
      find.descendant(
        of: _thumbOf(pageId),
        matching: find.byType(ink.InkPageThumbnail),
      ),
    );

const _shapeFill = 0xFF0050DC;
const _imageColor = 0xFFDC1E1E;

/// A [w]×[h] PNG of one colour.
Future<Uint8List> _solidPng(int argb, int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = ui.Color(argb),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

core.ShapeObject _filledShape(String pageId, core.PageRect rect) {
  final s = PageObjectFixtures.shape(pageId: pageId, rect: rect, id: 'shape-1');
  return s.copyWith(style: s.style.copyWith(fillColorArgb: _shapeFill));
}

/// The RGBA bytes of the thumbnail raster of [pageId] (null = no raster yet).
Future<({int width, int height, ByteData bytes})?> _rasterOf(
  WidgetTester tester,
  String pageId,
) async {
  final raw = find.descendant(
    of: _thumbOf(pageId),
    matching: find.byType(RawImage),
  );
  if (raw.evaluate().isEmpty) return null;
  final image = tester.widget<RawImage>(raw).image;
  if (image == null) return null;
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  return (width: image.width, height: image.height, bytes: bytes!);
}

/// The colour at page point ([xPt], [yPt]) of [raster] for a page [pageWidthPt] wide.
int _argbAt(
  ({int width, int height, ByteData bytes}) raster,
  double pageWidthPt,
  double xPt,
  double yPt,
) {
  final scale = raster.width / pageWidthPt;
  final x = (xPt * scale).round(), y = (yPt * scale).round();
  final i = (y * raster.width + x) * 4;
  final b = raster.bytes;
  return (b.getUint8(i + 3) << 24) |
      (b.getUint8(i) << 16) |
      (b.getUint8(i + 1) << 8) |
      b.getUint8(i + 2);
}

bool _near(int a, int b, {int tol = 12}) {
  for (final shift in [16, 8, 0]) {
    if ((((a >> shift) & 0xFF) - ((b >> shift) & 0xFF)).abs() > tol) {
      return false;
    }
  }
  return true;
}

/// Lets the thumbnail rasters (Picture.toImage, image decodes) finish.
Future<void> _settleRasters(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets('a loaded page → InkPageThumbnail of the session content, '
      'refreshed 500 ms after the last change; listened only while shown', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 3);
    final rec = h.recorder!;
    final before = rec.activeSubscriptions;
    await _openPanel(tester);
    expect(rec.activeSubscriptions, greaterThan(before));
    final id = h.pageId(0);
    final loaded = h.session.pageIfLoaded(id)!;
    var thumb = _inkThumbOf(tester, id);
    expect(thumb.width, PagePanel.thumbnailWidth);
    expect(thumb.content.pageId, id);
    expect(thumb.content.revision, loaded.revision);
    expect(thumb.content.strokes, isEmpty);

    h.session.execute(
      core.AddStrokes(
        pageId: id,
        strokes: [strokeA.copyWith(pageId: id)],
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // A second change restarts the 500 ms.
    h.session.execute(
      core.AddStrokes(
        pageId: id,
        strokes: [strokeB.copyWith(pageId: id)],
      ),
    );
    await tester.pump(const Duration(milliseconds: 499));
    expect(_inkThumbOf(tester, id).content.strokes, isEmpty);
    await tester.pump(const Duration(milliseconds: 2));
    thumb = _inkThumbOf(tester, id);
    expect(thumb.content.strokes, hasLength(2));
    expect(thumb.content.revision, h.session.pageIfLoaded(id)!.revision);

    await tester.tap(find.byKey(EditorToolbar.pagePanelKey));
    await tester.pump();
    expect(rec.activeSubscriptions, before, reason: 'no subscription left');
  });

  testWidgets('not loaded: a fresh cache entry → Image; a stale one → '
      'loadPage once → InkPageThumbnail; never openPage', (tester) async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    late _RecordingReader reader;
    final h = await pumpEditor(
      tester,
      store: store,
      pages: 12,
      overrides: [
        core.noteContentReaderProvider.overrideWith(
          (ref) => reader = _RecordingReader(store.content),
        ),
      ],
    );
    final fresh = h.pageId(4);
    final stale = h.pageId(5);
    final none = h.pageId(3);
    expect(h.session.pageIfLoaded(fresh), isNull);
    expect(h.session.pageIfLoaded(stale), isNull);
    expect(h.session.pageIfLoaded(none), isNull);
    final committed = (await store.content.getPage(fresh))!;
    final staleCommitted = (await store.content.getPage(stale))!;
    Future<void> writeCache(core.PageId id, int revision) =>
        store.thumbnails.write(
          core.PageThumbnail(
            pageId: id,
            contentRevision: revision,
            width: 1,
            height: 1,
            mimeType: 'image/png',
            bytes: _png,
          ),
        );
    await writeCache(fresh, committed.contentRevision);
    await writeCache(stale, staleCommitted.contentRevision + 1);
    h.recorder!.clearCalls();

    await _openPanel(tester);
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    // Fresh cache → the image (no loadPage).
    expect(
      find.descendant(
        of: _thumbOf(fresh),
        matching: find.byKey(PagePanelThumbnail.imageKey),
      ),
      findsOneWidget,
    );
    expect(reader.calls, contains('getPage:$fresh'));
    expect(reader.calls, isNot(contains('loadPage:$fresh')));
    // Stale cache → loadPage once → INK thumbnail of the committed content.
    expect(reader.calls.where((c) => c == 'loadPage:$stale'), hasLength(1));
    expect(_inkThumbOf(tester, stale).content.pageId, stale);
    // No cache → loadPage too.
    expect(reader.calls.where((c) => c == 'loadPage:$none'), hasLength(1));
    expect(_inkThumbOf(tester, none).content.pageId, none);
    // Never pinned.
    expect(
      h.recorder!.calls.where(
        (c) =>
            c == 'openPage:$fresh' ||
            c == 'openPage:$stale' ||
            c == 'openPage:$none',
      ),
      isEmpty,
    );
    expect(h.session.pageIfLoaded(fresh), isNull);
    expect(h.session.pageIfLoaded(stale), isNull);
  });

  testWidgets('INK arguments are the provider values (contract 7.2.16 v1.1)', (
    tester,
  ) async {
    final builders = <ink.PageBackgroundLayerBuilder>[
      const ink_testing.SolidBackgroundBuilder(),
      const ink.TemplateBackgroundLayerBuilder(),
    ];
    final h = await pumpEditor(
      tester,
      pages: 2,
      overrides: [
        ink.pageBackgroundBuildersProvider.overrideWithValue(builders),
      ],
    );
    await _openPanel(tester);
    final container = h.container;
    for (var i = 0; i < 2; i++) {
      final thumb = _inkThumbOf(tester, h.pageId(i));
      expect(identical(thumb.backgroundBuilders, builders), isTrue);
      expect(
        identical(
          thumb.backgroundBuilders,
          container.read(ink.pageBackgroundBuildersProvider),
        ),
        isTrue,
      );
      expect(
        identical(thumb.pencilGrain, container.read(ink.pencilGrainProvider)),
        isTrue,
      );
    }
  });

  test('height: 120 × h / w, at most 200', () {
    expect(
      PagePanelThumbnail.heightFor(core.PageSize.a4Portrait, 120),
      closeTo(120 * 841.8898 / 595.2756, 1e-9),
    );
    expect(
      PagePanelThumbnail.heightFor(core.PageSize.widescreen16x9, 120),
      closeTo(67.5, 1e-9),
    );
    expect(
      PagePanelThumbnail.heightFor(const core.PageSize(300, 3000), 120),
      200,
    );
  });

  group('(v2.13-thumbs) page objects in the thumbnail', () {
    const shapeRect = core.PageRect(60, 60, 300, 260);
    const imageRect = core.PageRect(60, 420, 360, 720);

    testWidgets('a loaded page: shape and image objects are passed and '
        'drawn; an object edit refreshes the thumbnail', (tester) async {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      final png = (await tester.runAsync(
        () => _solidPng(_imageColor, 40, 40),
      ))!;
      final asset = await store.assets.put(
        png,
        type: core.AssetType.image,
        mimeType: 'image/png',
      );
      const seeded = 'seeded';
      final h = await pumpEditor(
        tester,
        store: store,
        pages: 2,
        objectsByPageIndex: {
          0: [
            _filledShape(seeded, shapeRect),
            PageObjectFixtures.image(
              pageId: seeded,
              assetId: asset.id,
              rect: imageRect,
              pixelWidth: 40,
              pixelHeight: 40,
              id: 'image-1',
            ),
          ],
        },
      );
      final id = h.pageId(0);
      expect(h.session.pageIfLoaded(id), isNotNull);
      await _openPanel(tester);
      final thumb = _inkThumbOf(tester, id);
      expect(
        thumb.content.objects.map((o) => o.id),
        containsAll(<String>['shape-1', 'image-1']),
      );
      await _settleRasters(tester);
      final pageWidth = core.PageSize.a4Portrait.width;
      var raster = (await _rasterOf(tester, id))!;
      expect(
        _near(_argbAt(raster, pageWidth, 180, 160), _shapeFill),
        isTrue,
        reason: 'the shape fill is drawn',
      );
      expect(
        _near(_argbAt(raster, pageWidth, 210, 570), _imageColor),
        isTrue,
        reason: 'the image object is drawn',
      );

      // Moving the shape: the thumbnail follows 500 ms later.
      final shape =
          h.session.pageIfLoaded(id)!.objectById('shape-1')!
              as core.ShapeObject;
      h.session.execute(
        core.UpdateObjects(
          pageId: id,
          objects: [
            shape.copyWith(
              geometry: core.ShapeGeometry.rectangle(
                const core.PageRect(300, 60, 540, 260),
              ),
            ),
          ],
        ),
      );
      await tester.pump(PagePanelThumbnail.refreshDelay);
      await tester.pump(const Duration(milliseconds: 1));
      await _settleRasters(tester);
      raster = (await _rasterOf(tester, id))!;
      expect(
        _near(_argbAt(raster, pageWidth, 420, 160), _shapeFill),
        isTrue,
        reason: 'the moved shape is drawn at its new place',
      );
      expect(
        _near(_argbAt(raster, pageWidth, 100, 160), _shapeFill),
        isFalse,
        reason: 'not at the old place',
      );
    });

    testWidgets('a page not loaded (path 3): the committed objects are '
        'passed', (tester) async {
      const seeded = 'seeded';
      final h = await pumpEditor(
        tester,
        pages: 12,
        objectsByPageIndex: {
          5: [
            _filledShape(seeded, shapeRect),
            PageObjectFixtures.textBox(pageId: seeded, id: 'text-1'),
            PageObjectFixtures.math(pageId: seeded, id: 'math-1'),
          ],
        },
      );
      final id = h.pageId(5);
      expect(h.session.pageIfLoaded(id), isNull);
      await _openPanel(tester);
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(
        _inkThumbOf(tester, id).content.objects.map((o) => o.id),
        containsAll(<String>['shape-1', 'text-1', 'math-1']),
      );
    });
  });
}
