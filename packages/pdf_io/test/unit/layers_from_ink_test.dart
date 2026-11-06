// layersFromInk on INK v2 vector values built with ink.InkVectorFixtures (m5-7/06-pdf 4.1.3,
// 6.2.1, 5.2; 8.2 T24 ② — PDF-M2): image vectors → PdfAssetImageRef.object(frame), text vectors
// (with lines and empty) → PdfTextBoxRef, formulas → PdfMathRef, cover → solid fills with
// opacity 1, shape pieces (objectId) are ink, and the highlighter / ink layers are the 1차
// conversion (InkEngineVectorizer.vectorize on the same strokes). The real exportPage values are
// checked after INK T42 (integration/ink_vectorizer_v2_test).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/page_layers.dart';
import 'package:pdf_io/src/ink_adapter/ink_vectorizer.dart';

const _asset =
    'c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3';
typedef _Fx = ink_testing.InkVectorFixtures;

core.Page _page({
  core.PageBackground background = const core.BlankBackground(),
}) => core.Page(
  id: 'page-1',
  noteId: 'note-1',
  sortKey: 'a',
  size: const core.PageSize(500, 700),
  background: background,
  createdAt: 0,
  updatedAt: 0,
);

core.PageContent _content({List<core.Stroke> strokes = const []}) =>
    core.PageContent(page: _page(), strokes: strokes, revision: 0);

ink.InkVectorPath _square(double x) => ink.InkVectorPath(
  Uint8List.fromList(const [0, 1, 1, 1, 3]),
  Float32List.fromList([x, 0, x + 10, 0, x + 10, 10, x, 10]),
);

core.Stroke _stroke(String id, core.PenTool tool, {required int createdAt}) {
  return core.Stroke(
    id: id,
    pageId: 'page-1',
    style: core.StrokeStyle.defaultsFor(tool),
    points: core.StrokePoints.fromList([
      for (var i = 0; i <= 8; i++)
        core.StrokePoint(60 + 25.0 * i, 100 + (i.isEven ? 0 : 8)),
    ]),
    createdAt: createdAt,
  );
}

void _expectFill(
  PdfPlanItem item, {
  required ink.InkVectorPath path,
  required int colorArgb,
  required double opacity,
}) {
  expect(item, isA<PdfFillItem>());
  final fill = item as PdfFillItem;
  expect(fill.path.verbs, path.verbs);
  expect(fill.path.coords, path.coords);
  expect(fill.colorArgb, colorArgb);
  expect(fill.opacity, opacity);
  expect(fill.blend, PdfBlend.normal);
  expect(fill.fillRule, PdfFillRule.nonZero);
}

/// The fields of two vector items (vector items have identity equality).
void _expectSameVector(PdfVectorItem actual, PdfVectorItem expected) {
  expect(actual.runtimeType, expected.runtimeType);
  expect(actual.path.verbs, expected.path.verbs);
  expect(actual.path.coords, expected.path.coords);
  expect(actual.colorArgb, expected.colorArgb);
  expect(actual.opacity, expected.opacity);
  expect(actual.blend, expected.blend);
  if (actual is PdfStrokeItem && expected is PdfStrokeItem) {
    expect(actual.width, expected.width);
    expect(actual.cap, expected.cap);
    expect(actual.join, expected.join);
  }
}

void main() {
  final textBox = core_testing.PageObjectFixtures.textBox(
    pageId: 'page-1',
    id: 'text-1',
  );
  final emptyText = core_testing.PageObjectFixtures.textBox(
    pageId: 'page-1',
    id: 'text-2',
    text: '',
  );
  final formula = core_testing.PageObjectFixtures.math(
    pageId: 'page-1',
    id: 'math-1',
  );
  final frame = core.ElementFrame(
    const core.PageRect(40, 50, 240, 200),
    rotation: -0.5,
  );

  test('image vectors → PdfAssetImageRef.object(assetId, frame), z order', () {
    final layers = layersFromInk(
      _Fx.pageVectors(
        underlay: [
          _Fx.imageVector(
            assetId: _asset,
            frame: frame,
            pixelWidth: 4000,
            pixelHeight: 3000,
          ),
          _Fx.imageVector(
            assetId: 'd' * 64,
            frame: const core.ElementFrame(core.PageRect(0, 0, 10, 10)),
            pixelWidth: 1,
            pixelHeight: 1,
          ),
        ],
      ),
      _content(),
      background: PdfPageBackgroundPart.none,
    );
    // pixelWidth / pixelHeight are not used — the resolver reads the bytes' real size (6.2.4).
    expect(layers.underlay, [
      PdfAssetImageRef.object(assetId: _asset, frame: frame),
      PdfAssetImageRef.object(
        assetId: 'd' * 64,
        frame: const core.ElementFrame(core.PageRect(0, 0, 10, 10)),
      ),
    ]);
    expect(layers.pageSize, const ui.Size(500, 700));
    expect(layers.highlighter, isEmpty);
    expect(layers.ink, isEmpty);
    expect(layers.annotations, isEmpty);
    expect(layers.cover, isEmpty);
  });

  test(
    'text vectors (lines / none) → PdfTextBoxRef, formulas → PdfMathRef',
    () {
      final layers = layersFromInk(
        _Fx.pageVectors(
          annotations: [
            _Fx.textVector(
              object: textBox,
              lines: [
                _Fx.textLine(text: '안녕', x: 0, baselineY: 13.5, width: 28),
                _Fx.textLine(
                  text: 'hello',
                  x: 1.5,
                  baselineY: 31,
                  width: 33.25,
                ),
              ],
            ),
            _Fx.mathVector(object: formula),
            _Fx.textVector(object: emptyText), // fonts not loaded → no lines
          ],
        ),
        _content(),
        background: PdfPageBackgroundPart.none,
      );
      expect(layers.annotations, [
        PdfTextBoxRef(textBox, const [
          (text: '안녕', x: 0, baselineY: 13.5, width: 28),
          (text: 'hello', x: 1.5, baselineY: 31, width: 33.25),
        ]),
        PdfMathRef(formula),
        PdfTextBoxRef(emptyText, const []),
      ]);
    },
  );

  test('cover (tape) → a solid fill, opacity 1, colour opaque', () {
    final tape = _square(100);
    final layers = layersFromInk(
      _Fx.pageVectors(
        cover: [
          _Fx.fillShape(
            strokeId: 'tape-1',
            tool: core.PenTool.tape,
            path: tape,
            colorArgb: 0x80E0C080,
            opacity: 0.4,
          ),
        ],
      ),
      _content(),
      background: PdfPageBackgroundPart.none,
    );
    expect(layers.cover, hasLength(1));
    _expectFill(
      layers.cover.single,
      path: tape,
      colorArgb: 0xFFE0C080,
      opacity: 1,
    );
  });

  test('ink shapes: strokes and shape pieces (objectId) in z order', () {
    final pen = _square(0), border = _square(20), dash = _square(40);
    final layers = layersFromInk(
      _Fx.pageVectors(
        inkShapes: [
          _Fx.fillShape(
            strokeId: 'pen-1',
            tool: core.PenTool.ballpoint,
            path: pen,
            colorArgb: 0xFF1A1A1A,
          ),
          _Fx.fillShape(
            strokeId: 'shape-1',
            tool: core.PenTool.ballpoint,
            path: border,
            colorArgb: 0xFF2255AA,
            opacity: 0.6,
            objectId: 'shape-1',
          ),
          _Fx.fillShape(
            strokeId: 'dash-1',
            tool: core.PenTool.dashed,
            path: dash,
            colorArgb: 0xFF00AA00,
          ),
        ],
      ),
      _content(),
      background: PdfPageBackgroundPart.none,
    );
    expect(layers.ink, hasLength(3));
    _expectFill(layers.ink[0], path: pen, colorArgb: 0xFF1A1A1A, opacity: 1);
    _expectFill(
      layers.ink[1],
      path: border,
      colorArgb: 0xFF2255AA,
      opacity: 0.6,
    );
    _expectFill(layers.ink[2], path: dash, colorArgb: 0xFF00AA00, opacity: 1);
  });

  test(
    'highlighter groups → one stroke item per (width, cap), Multiply kept',
    () {
      final a = _square(0), b = _square(30), c = _square(60);
      final layers = layersFromInk(
        _Fx.pageVectors(
          highlighterGroups: [
            _Fx.highlighterGroup(
              colorArgb: 0xFFFFEB3B,
              opacity: 0.35,
              blend: ink.InkBlendMode.multiply,
              lines: [
                _Fx.highlighterLine(
                  strokeId: 'h1',
                  centerline: a,
                  width: 12,
                  cap: ink.InkCap.round,
                ),
                _Fx.highlighterLine(
                  strokeId: 'h2',
                  centerline: b,
                  width: 20,
                  cap: ink.InkCap.square,
                ),
                _Fx.highlighterLine(
                  strokeId: 'h3',
                  centerline: c,
                  width: 12,
                  cap: ink.InkCap.round,
                ),
              ],
            ),
          ],
        ),
        _content(),
        background: PdfPageBackgroundPart.none,
      );
      expect(layers.highlighter, hasLength(2));
      final first = layers.highlighter[0], second = layers.highlighter[1];
      expect((first.width, first.cap), (12, PdfLineCap.round));
      expect(first.path.verbs, [...a.verbs, ...c.verbs]);
      expect((second.width, second.cap), (20, PdfLineCap.square));
      for (final item in layers.highlighter) {
        expect(item.colorArgb, 0xFFFFEB3B);
        expect(item.opacity, 0.35);
        expect(item.blend, PdfBlend.multiply);
        expect(item.join, PdfLineJoin.round);
      }
    },
  );

  test(
    'strokes: the highlighter and ink layers equal the 1차 vectorize items',
    () {
      final strokes = [
        _stroke('pen', core.PenTool.ballpoint, createdAt: 1),
        _stroke('marker', core.PenTool.highlighter, createdAt: 2),
        _stroke('pencil', core.PenTool.pencil, createdAt: 3),
        _stroke('fountain', core.PenTool.fountain, createdAt: 4),
      ];
      final page = _page();
      final vectors = ink.InkVectorExport.exportPage(
        ink.InkPageContent.fromCore(page: page, strokes: strokes, revision: 0),
        options: ink.InkExportOptions(
          paperColorArgb: page.background.paperColorArgb,
        ),
      );
      final layers = layersFromInk(
        vectors,
        core.PageContent(page: page, strokes: strokes, revision: 0),
        background: PdfPageBackgroundPart.none,
      );
      final first = const InkEngineVectorizer().vectorize(
        page,
        strokes,
        includeInk: true,
        includeTemplate: false,
      );
      final converted = <PdfVectorItem>[...layers.highlighter, ...layers.ink];
      expect(converted, hasLength(first.ink.length));
      for (var i = 0; i < converted.length; i++) {
        _expectSameVector(converted[i], first.ink[i]);
      }
      expect(
        layers.highlighter,
        isNotEmpty,
        reason: 'INK exports highlighters',
      );
      expect(layers.ink, isNotEmpty, reason: 'INK exports pen fills');
    },
  );

  test('the background part passes through; planFromLayers puts it first', () {
    const image = PdfAssetImageRef.background(
      assetId: _asset,
      fit: core.ImageFit.fill,
      pageSize: ui.Size(500, 700),
    );
    const background = PdfPageBackgroundPart(
      paperArgb: core.PaperColors.ivory,
      image: image,
    );
    final layers = layersFromInk(
      _Fx.pageVectors(
        underlay: [
          _Fx.imageVector(
            assetId: _asset,
            frame: frame,
            pixelWidth: 10,
            pixelHeight: 10,
          ),
        ],
        annotations: [_Fx.mathVector(object: formula)],
      ),
      _content(),
      background: background,
    );
    expect(layers.background, background);
    final plan = planFromLayers(
      layers,
      includeInk: true,
      includeTemplate: true,
    );
    expect(plan.items, hasLength(4));
    expect(plan.items[0], isA<PdfFillItem>());
    expect(plan.items.sublist(1), [
      image,
      PdfAssetImageRef.object(assetId: _asset, frame: frame),
      PdfMathRef(formula),
    ]);
  });

  test('empty vectors → empty layers (only size and background)', () {
    final layers = layersFromInk(
      _Fx.pageVectors(),
      _content(),
      background: PdfPageBackgroundPart.none,
    );
    expect(layers, const PdfPageLayers(pageSize: ui.Size(500, 700)));
  });

  test(
    'InkEngineVectorizer.planPage = planFromLayers(layersFromInk(exportPage))',
    () {
      const background = core.BlankBackground(
        paperColorArgb: core.PaperColors.ivory,
      );
      final page = _page(background: background);
      final strokes = [
        _stroke('pen', core.PenTool.ballpoint, createdAt: 1),
        _stroke('marker', core.PenTool.highlighter, createdAt: 2),
      ];
      final content = core.PageContent(
        page: page,
        strokes: strokes,
        revision: 0,
      );
      final plan = const InkEngineVectorizer().planPage(
        content,
        includeInk: true,
        includeTemplate: true,
      );
      final vectors = ink.InkVectorExport.exportPage(
        ink.InkPageContent.fromCore(page: page, strokes: strokes, revision: 0),
      );
      final expected = planFromLayers(
        layersFromInk(
          vectors,
          content,
          background: const PdfPageBackgroundPart(
            paperArgb: core.PaperColors.ivory,
          ),
        ),
        includeInk: true,
        includeTemplate: true,
      );
      expect(plan.items, hasLength(expected.items.length));
      for (var i = 0; i < plan.items.length; i++) {
        _expectSameVector(
          plan.items[i] as PdfVectorItem,
          expected.items[i] as PdfVectorItem,
        );
      }
      // includeInk false: the paper only (INK's export is not needed).
      final paperOnly = const InkEngineVectorizer().planPage(
        content,
        includeInk: false,
        includeTemplate: true,
      );
      expect(paperOnly.items, hasLength(1));
      expect(
        (paperOnly.items.single as PdfFillItem).colorArgb,
        core.PaperColors.ivory,
      );
    },
  );
}
