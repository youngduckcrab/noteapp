// DefaultPdfExportService v2 (m5-7/06-pdf 6.2.2 · 6.2.9 · 6.2.10; 8.2 T26) on ExportWorld v2:
// FakePdfNoteGateway + page objects, BoxInkVectorizer.planPage, RecordingComposeBackend v2, fake
// raster ports and fonts. Parts and their order, fonts once per job, the S-2 send order, the
// options (includeInk false → no objects), the object warnings, cancel while resolving,
// progress, the font wait (once per export / batch, the web stop S-12) and the memory ledger
// (big samples ≤ 16 MiB, the JPEG cache across pages, the native worker copy — CP-PDF-14 ①).
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/export_memory.dart';
import 'package:pdf_io/src/export/raster_ports.dart';
import 'package:pdf_io/src/ui/export_sheets.dart';
import 'package:pdf_io/src/ui/strings_ko.dart';
import 'package:pdf_io/testing.dart';

import '../support/export_world.dart';
import '../support/fake_rasterizers.dart';
import '../support/object_fixtures.dart';

const int mib = 1024 * 1024;

int _created = 0;

core.ElementFrame _frame(double l, double t, double w, double h) =>
    core.ElementFrame(core.PageRect(l, t, l + w, t + h));

core.ImageObject _image(
  String id,
  core.PageId pageId,
  core.AssetId assetId, {
  core.ElementFrame? frame,
}) => core.ImageObject(
  id: id,
  pageId: pageId,
  frame: frame ?? _frame(50, 50, 200, 150),
  assetId: assetId,
  pixelWidth: 64,
  pixelHeight: 48,
  createdAt: ++_created,
);

core.TextBoxObject _text(
  String id,
  core.PageId pageId,
  String text, {
  bool bold = false,
  core.ElementFrame? frame,
}) => core.TextBoxObject(
  id: id,
  pageId: pageId,
  frame: frame ?? _frame(60, 300, 300, 60),
  text: text,
  style: core.TextBoxStyle(fontSizePt: 14, bold: bold),
  createdAt: ++_created,
);

core.MathObject _math(String id, core.PageId pageId) => core.MathObject(
  id: id,
  pageId: pageId,
  frame: _frame(50, 400, 200, 100),
  latex: r'\frac{a}{b}',
  style: const core.MathStyle(),
  createdAt: ++_created,
);

/// Re-place a CORE fixture object on [pageId] with a later createdAt (z order = list order).
core.PageObject _on(core.PageId pageId, core.PageObject o) => switch (o) {
  core.TextBoxObject() => core.TextBoxObject(
    id: o.id,
    pageId: pageId,
    frame: o.frame,
    text: o.text,
    style: o.style,
    createdAt: ++_created,
  ),
  core.MathObject() => core.MathObject(
    id: o.id,
    pageId: pageId,
    frame: o.frame,
    latex: o.latex,
    style: o.style,
    createdAt: ++_created,
  ),
  _ => throw ArgumentError(o.runtimeType),
};

/// 'page.part img=[…] txt=[…] fonts=[…]' per recorded part.
List<String> _parts(RecordingComposeBackend backend) => [
  for (final p in backend.parts)
    '${p.outputIndex}.${p.part} img=${p.images} txt=${p.texts} fonts=${p.fontIds}',
];

int _reads(ExportWorld w) =>
    w.gateway.calls.where((c) => c == 'readAssetBytes').length;

Future<List<core.Page>> _note(
  ExportWorld w,
  int pages, {
  String title = 'n',
  List<core.PageDraft>? drafts,
}) async {
  final note = await w.note(title, drafts ?? List.filled(pages, blankDraft));
  return w.gateway.pagesOf(note.id);
}

core.NoteId _noteOf(core.Page page) => page.noteId;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a 3-page note with objects: parts in z order, each font once per job, '
      'images sent at once', () async {
    final w = ExportWorld();
    w.gateway.arriveBytes('jpeg', PdfObjectFixtures.jpegBaseline64x48);
    w.gateway.arriveBytes('png', PdfObjectFixtures.png(alpha: true));
    final pages = await _note(w, 3, title: '객체');
    w.addStroke(pages[0].id);
    w.objects
      ..addObjects(pages[0].id, [
        _image('img-a', pages[0].id, 'jpeg'),
        _text('t1', pages[0].id, 'PDF 안녕하세요'),
      ])
      ..addObjects(pages[1].id, [
        _text('t2', pages[1].id, '굵은 글씨', bold: true),
        _math('m1', pages[1].id),
      ])
      ..addObjects(pages[2].id, [
        _image('img-b', pages[2].id, 'png'),
        _text('t3', pages[2].id, 'PDF 다시'),
      ]);

    final result = await w.service.exportNote(
      _noteOf(pages[0]),
      const PdfExportOptions(),
    );

    expect(_parts(w.backend), [
      '0.1 img=[jpeg 64x48] txt=[] fonts=[]',
      '0.2 img=[] txt=[PDF 안녕하세요] fonts=[0]',
      matches(
        RegExp(r'^1\.1 img=\[rgba \d+x\d+ alpha\] txt=\[굵은 글씨\] fonts=\[1\]$'),
      ),
      '2.1 img=[rgba 64x48 alpha] txt=[] fonts=[]',
      '2.2 img=[] txt=[PDF 다시] fonts=[]',
    ]);
    // the stroke box is a path object in the text part of page 1
    final page0 = w.backend.partsOfPage(0);
    expect(
      page0[1].verbs.where((v) => v == PdfComposeOpcodes.endObject),
      hasLength(1),
    );
    expect(page0[1].verbs.last, PdfComposeOpcodes.text);
    expect(w.backend.events, [
      'begin#1',
      'addPages#1', // page 1's image
      'addPages#1', // page 1's text part + page 2 (its formula raster)
      'addPages#1', // page 3's image
      'addPages#1', // the rest
      'finish#1',
    ]);
    expect(
      [
        for (final c in w.backend.chunks) [for (final o in c) o.outputIndex],
      ],
      [
        [0],
        [0, 1],
        [2],
        [2],
      ],
    );
    expect(w.fonts.reads, [false, true], reason: 'regular once, bold once');
    expect(w.fontWaits, 1);
    expect(result.warnings, isEmpty);
    expect(w.backend.openJobCount, 0);
    final ledger = w.ledgers.single;
    expect(ledger.heldBytes, 0, reason: 'everything released at the end');
    expect(ledger.copyBytes, 0);
    expect(ledger.peakCopyBytes, greaterThan(0), reason: 'VM = native rules');
  });

  test(
    'an image item → addPages before the next item is resolved (S-2)',
    () async {
      final w = ExportWorld();
      w.gateway
        ..arriveBytes('a', PdfObjectFixtures.jpegBaseline64x48)
        ..arriveBytes('b', PdfObjectFixtures.jpegGray64x48);
      final pages = await _note(w, 1);
      final p = pages.single.id;
      w.objects.addObjects(p, [
        _image('i1', p, 'a'),
        _image('i2', p, 'b'),
        _on(p, pageSizeTextBox()),
        _math('m', p),
      ]);
      final seen = <String>[];
      w.backend.beforeAddPages = () async => seen.add(
        'reads ${_reads(w)} text ${w.text.calls.length} '
        'math ${w.math.calls.length}',
      );
      w.gateway.calls.clear();
      await w.service.exportNote(
        _noteOf(pages.single),
        const PdfExportOptions(),
      );
      expect(seen, [
        'reads 1 text 0 math 0',
        'reads 2 text 0 math 0',
        'reads 2 text 1 math 0',
        'reads 2 text 1 math 1',
      ]);
    },
  );

  test('includeInk false → no objects (strokes, images, text, math); the image '
      'background stays', () async {
    final w = ExportWorld();
    w.gateway
      ..arriveBytes('bg', PdfObjectFixtures.jpegProgressive64x48)
      ..arriveBytes('img', PdfObjectFixtures.jpegBaseline64x48);
    final pages = await _note(
      w,
      2,
      drafts: const [
        core.PageDraft(
          size: core.PageSize.a4Portrait,
          background: core.ImageBackground(assetId: 'bg'),
        ),
        blankDraft,
      ],
    );
    for (final page in pages) {
      w.addStroke(page.id);
      w.objects.addObjects(page.id, [
        _image('i-${page.id}', page.id, 'img'),
        _text('t-${page.id}', page.id, '안녕'),
        _math('m-${page.id}', page.id),
      ]);
    }
    w.gateway.calls.clear();
    final result = await w.service.exportNote(
      _noteOf(pages.first),
      const PdfExportOptions(includeInk: false),
    );
    expect(w.gateway.calls, isNot(contains('loadPage')));
    expect(_reads(w), 1, reason: 'the background only');
    expect(_parts(w.backend), ['0.1 img=[jpeg 64x48] txt=[] fonts=[]']);
    expect(w.text.calls, isEmpty);
    expect(w.math.calls, isEmpty);
    expect(w.math.layoutCalls, isEmpty);
    expect(w.fonts.reads, isEmpty);
    expect(result.warnings, isEmpty);
  });

  group('warnings (6.2.9) — 1차 first, then images · text · formulas', () {
    test('missing image bytes → left out, PdfExportMissingImages with the '
        'pages', () async {
      final w = ExportWorld();
      w.gateway.addRemoteAsset('remote');
      final pages = await _note(w, 4);
      for (final i in [1, 3]) {
        w.objects.addObjects(pages[i].id, [
          _image('i$i', pages[i].id, 'remote'),
        ]);
      }
      final result = await w.service.exportNote(
        _noteOf(pages.first),
        const PdfExportOptions(),
      );
      final warning = result.warnings.single as PdfExportMissingImages;
      expect(warning.notePageNumbers, [2, 4]);
      expect(warningLines(result), ['2, 4쪽의 이미지는 이 기기에 원본이 없거나 읽지 못해 빠졌어요']);
      expect(w.backend.parts, isEmpty);
    });

    test('missing image bytes with policy fail → assetMissing (page), the '
        'job aborted, nothing held', () async {
      final w = ExportWorld();
      w.gateway.addRemoteAsset('remote');
      final pages = await _note(w, 3);
      w.objects.addObjects(pages[2].id, [_image('i', pages[2].id, 'remote')]);
      final reports = captureFlutterErrors();
      await expectLater(
        w.service.exportNote(
          _noteOf(pages.first),
          const PdfExportOptions(
            missingAssetPolicy: PdfMissingAssetPolicy.fail,
          ),
        ),
        throwsA(
          hasCode(PdfErrorCode.assetMissing)
              .having((e) => e.detail, 'detail', '3'),
        ),
      );
      await pumpEventQueue();
      expect(w.backend.events, ['begin#1', 'abort#1']);
      expect(w.ledgers.single.heldBytes, 0);
      expect(reports, isEmpty);
    });

    test('all four kinds in their order, pages ascending', () async {
      final w = ExportWorld(
        math: FakeMathRasterizer(layoutSizes: {'m-bad': null}),
      );
      final pdf = await w.addPdf('src');
      w.gateway.dropAssetBytes(pdf);
      w.gateway.addRemoteAsset('remote');
      final pages = await _note(
        w,
        5,
        drafts: [
          blankDraft,
          blankDraft,
          blankDraft,
          blankDraft,
          w.pdfPage(pdf, 0),
        ],
      );
      w.objects
        ..addObjects(pages[3].id, [_math('m-bad', pages[3].id)])
        ..addObjects(pages[2].id, [
          _text('t-emoji', pages[2].id, '웃음 \u{1F600}'),
          _image('i', pages[2].id, 'remote'),
        ])
        ..addObjects(pages[0].id, [
          _text('t-emoji-0', pages[0].id, '\u{1F600}'),
        ]);
      final result = await w.service.exportNote(
        _noteOf(pages.first),
        const PdfExportOptions(),
      );
      expect(
        [for (final x in result.warnings) x.runtimeType],
        [
          PdfExportBlankedMissingAsset,
          PdfExportMissingImages,
          PdfExportRasterizedText,
          PdfExportSkippedFormulas,
        ],
      );
      expect(warningLines(result), [
        '5쪽은 원본이 없어 빈 페이지로 넣었어요',
        '3쪽의 이미지는 이 기기에 원본이 없거나 읽지 못해 빠졌어요',
        '1, 3쪽의 텍스트 상자 일부는 그림으로 넣었어요 — PDF에서 검색되지 않아요',
        '4쪽의 수식 일부를 그리지 못해 빠졌어요',
      ]);
    });
  });

  test('cancel while a raster is being drawn → cancelled at once, job aborted, '
      'nothing held', () async {
    final w = ExportWorld(text: FakeTextRasterizer(mode: FakeRasterMode.hang));
    final pages = await _note(w, 3);
    w.objects.addObjects(pages[1].id, [_text('t', pages[1].id, '\u{1F600}')]);
    final cancel = PdfCancelSignal();
    final export = w.service.exportNote(
      _noteOf(pages.first),
      const PdfExportOptions(),
      cancel: cancel,
    );
    final outcome = expectLater(
      export,
      throwsA(hasCode(PdfErrorCode.cancelled)),
    );
    while (w.text.calls.isEmpty) {
      await pumpEventQueue();
    }
    expect(w.ledgers.single.heldBytes, greaterThan(0), reason: 'room taken');
    cancel.cancel();
    await outcome;
    await pumpEventQueue();
    expect(w.backend.events.last, 'abort#1');
    expect(w.backend.openJobCount, 0);
    expect(w.ledgers.single.heldBytes, 0);
  });

  test(
    'progress: composing n/N once per page, never back (objects too)',
    () async {
      final w = ExportWorld();
      w.gateway.arriveBytes('j', PdfObjectFixtures.jpegBaseline64x48);
      final pages = await _note(w, 4);
      for (final page in pages) {
        w.objects.addObjects(page.id, [
          _image('i-${page.id}', page.id, 'j'),
          _math('m-${page.id}', page.id),
        ]);
      }
      final seen = <PdfProgress>[];
      await w.service.exportNote(
        _noteOf(pages.first),
        const PdfExportOptions(),
        onProgress: seen.add,
      );
      expect(seen, const [
        PdfProgress(PdfJobPhase.preparingExport),
        PdfProgress(PdfJobPhase.composing, total: 4),
        PdfProgress(PdfJobPhase.composing, done: 1, total: 4),
        PdfProgress(PdfJobPhase.composing, done: 2, total: 4),
        PdfProgress(PdfJobPhase.composing, done: 3, total: 4),
        PdfProgress(PdfJobPhase.composing, done: 4, total: 4),
        PdfProgress(PdfJobPhase.finishingExport, done: 4, total: 4),
      ]);
    },
  );

  group('fonts (6.2.2 step 1)', () {
    test('waited for once per batch; ready → text objects', () async {
      final w = ExportWorld();
      final ids = <core.NoteId>[];
      for (var i = 0; i < 3; i++) {
        final pages = await _note(w, 1, title: 'n$i');
        w.objects.addObjects(pages.single.id, [
          _text('t$i', pages.single.id, '가나다 $i'),
        ]);
        ids.add(_noteOf(pages.single));
      }
      final batch = await w.service.exportNotes(ids, const PdfExportOptions());
      expect(batch.items.every((i) => i.result != null), isTrue);
      expect(w.fontWaits, 1);
      expect(w.fonts.reads, [false, false, false], reason: 'per job');
      expect(
        [for (final p in w.backend.parts) p.fontIds],
        [
          [0],
          [0],
          [0],
        ],
        reason: 'every job is its own document',
      );
    });

    test('native, fonts not ready → the boxes are rasters + warning', () async {
      final w = ExportWorld(web: false, fontsReady: false);
      final pages = await _note(w, 2);
      w.objects.addObjects(pages[1].id, [_text('t', pages[1].id, '한글 상자')]);
      final result = await w.service.exportNote(
        _noteOf(pages.first),
        const PdfExportOptions(),
      );
      expect(w.text.calls, hasLength(1));
      expect(w.fonts.reads, isEmpty);
      expect(
        (result.warnings.single as PdfExportRasterizedText).notePageNumbers,
        [2],
      );
      expect(_parts(w.backend), [
        matches(
          RegExp(r'^1\.1 img=\[rgba \d+x\d+ alpha\] txt=\[\] fonts=\[\]$'),
        ),
      ]);
    });

    test('web, fonts not ready, a Hangul box → exportFailed '
        "'fonts-unavailable' before begin, not reported (S-12)", () async {
      final w = ExportWorld(web: true, fontsReady: false);
      final pages = await _note(w, 3);
      w.objects
        ..addObjects(pages[0].id, [_text('a', pages[0].id, 'ascii only')])
        ..addObjects(pages[2].id, [_text('k', pages[2].id, '한글')]);
      final reports = captureFlutterErrors();
      Object? error;
      try {
        await w.service.exportNote(
          _noteOf(pages.first),
          const PdfExportOptions(),
        );
      } on PdfIoException catch (e) {
        error = e;
      }
      final e = error! as PdfIoException;
      expect(e.code, PdfErrorCode.exportFailed);
      expect(e.detail, 'fonts-unavailable');
      expect(e.detail, PdfStringsKo.fontsUnavailableDetail);
      expect(e.userMessage, '글꼴을 받지 못해 내보낼 수 없어요. 인터넷에 연결한 뒤 다시 해 주세요.');
      expect(w.backend.events, isEmpty, reason: 'no begin');
      expect(w.text.calls, isEmpty);
      expect(reports, isEmpty);
      expect(
        const PdfIoException(PdfErrorCode.exportFailed).userMessage,
        'PDF를 만들지 못했어요.',
      );
    });

    test('web, fonts not ready, ASCII boxes only (or original only) → '
        'rasters + warning, 16-part chunks, no worker copy', () async {
      final w = ExportWorld(web: true, fontsReady: false);
      final pages = await _note(w, 2);
      w.objects.addObjects(pages[1].id, [_text('a', pages[1].id, 'ascii')]);
      final result = await w.service.exportNote(
        _noteOf(pages.first),
        const PdfExportOptions(),
      );
      expect(result.warnings.single, isA<PdfExportRasterizedText>());
      expect(w.ledgers.single.peakCopyBytes, 0, reason: 'web: transfer');

      w.objects.addObjects(pages[0].id, [_text('k', pages[0].id, '한글')]);
      final original = await w.service.exportNote(
        _noteOf(pages.first),
        const PdfExportOptions(includeInk: false),
      );
      expect(original.warnings, isEmpty, reason: 'no objects without ink');
    });
  });

  group('memory ledger (6.2.10)', () {
    test('big samples (6000 × 4000 PNG, page-size text box, 700 × 700 pt '
        'formula) → each RGBA ≤ 4 Mpx, peakBytes ≤ 16 MiB', () async {
      final formula = bigMathObject();
      final w = ExportWorld(
        math: FakeMathRasterizer(
          layoutSizes: {formula.id: const ui.Size(350, 350)},
        ),
      );
      w.gateway.arriveBytes('big', bigPng6000x4000());
      final pages = await _note(w, 3);
      w.objects
        ..addObjects(pages[0].id, [
          _image('big', pages[0].id, 'big', frame: _frame(0, 0, 600, 400)),
        ])
        ..addObjects(pages[1].id, [_on(pages[1].id, pageSizeTextBox())])
        ..addObjects(pages[2].id, [_on(pages[2].id, formula)]);
      await w.service.exportNote(
        _noteOf(pages.first),
        const PdfExportOptions(),
      );
      final sizes = [
        for (final p in w.backend.parts)
          for (final image in p.images)
            RegExp(r'(\d+)x(\d+)').firstMatch(image)!,
      ];
      expect(sizes, hasLength(3));
      for (final m in sizes) {
        expect(
          int.parse(m[1]!) * int.parse(m[2]!),
          lessThanOrEqualTo(PdfTuning.maxRasterPixels),
        );
      }
      expect(sizes.first[0], '2048x1365');
      expect(
        w.text.calls.single.pixelsPerPt,
        cappedPixelsPerPt(
          PdfTuning.textRasterDpi / 72,
          const ui.Size(500, 700),
        ),
      );
      expect(
        w.math.calls.single.pixelsPerPt,
        cappedPixelsPerPt(
          2 * PdfTuning.mathRasterDpi / 72,
          const ui.Size(350, 350),
        ),
      );
      final ledger = w.ledgers.single;
      expect(ledger.peakBytes, lessThanOrEqualTo(16 * mib));
      expect(ledger.overBudget, 0);
      expect(ledger.heldBytes, 0);
    });

    test('the same 6 MiB JPEG on 5 pages + a 4 Mpx raster in the middle → 2 '
        'reads, peakBytes ≤ 16 MiB; the raster page → peakCopyBytes == 16 '
        'MiB, peakTotalBytes ≤ 32 MiB (VM = native)', () async {
      final w = ExportWorld();
      w.gateway.arriveBytes(
        'j',
        paddedJpeg(PdfObjectFixtures.jpegBaseline64x48, 6 * mib),
      );
      final pages = await _note(w, 5);
      for (final page in pages) {
        w.objects.addObjects(page.id, [_image('i-${page.id}', page.id, 'j')]);
      }
      // 512 × 512 pt at 4 px/pt (the 4 Mpx cap) = 2048² RGBA = 16 MiB
      w.objects.addObjects(pages[2].id, [
        _text('big', pages[2].id, '\u{1F600}', frame: _frame(0, 0, 512, 512)),
      ]);
      w.gateway.calls.clear();
      await w.service.exportNote(
        _noteOf(pages.first),
        const PdfExportOptions(),
      );
      expect(_reads(w), 2, reason: 'cache hits, emptied by the raster');
      expect(_parts(w.backend), [
        '0.1 img=[jpeg 64x48] txt=[] fonts=[]',
        '1.1 img=[jpeg 64x48] txt=[] fonts=[]',
        '2.1 img=[jpeg 64x48] txt=[] fonts=[]',
        '2.2 img=[rgba 2048x2048 alpha] txt=[] fonts=[]',
        '3.1 img=[jpeg 64x48] txt=[] fonts=[]',
        '4.1 img=[jpeg 64x48] txt=[] fonts=[]',
      ]);
      final ledger = w.ledgers.single;
      expect(ledger.peakBytes, lessThanOrEqualTo(16 * mib));
      expect(ledger.peakCopyBytes, 16 * mib);
      expect(ledger.peakTotalBytes, lessThanOrEqualTo(32 * mib));
      expect(ledger.copyBytes, 0);
      expect(ledger.heldBytes, 0);
    });

    test('no images and no rasters → peakCopyBytes 0', () async {
      final w = ExportWorld();
      final pages = await _note(w, 3);
      for (final page in pages) {
        w.addStroke(page.id);
      }
      w.objects.addObjects(pages[1].id, [_text('t', pages[1].id, '글자만')]);
      await w.service.exportNote(
        _noteOf(pages.first),
        const PdfExportOptions(),
      );
      final ledger = w.ledgers.single;
      expect(ledger.peakCopyBytes, 0);
      expect(ledger.peakBytes, 0);
      expect(w.backend.parts, hasLength(3));
    });

    test('web: no worker copy; a JPEG clone is held as encoded while it is '
        'sent', () async {
      final w = ExportWorld(web: true);
      final jpeg = PdfObjectFixtures.jpegBaseline64x48;
      w.gateway.arriveBytes('j', jpeg);
      final pages = await _note(w, 1);
      w.objects.addObjects(pages.single.id, [
        _image('i', pages.single.id, 'j'),
      ]);
      int? during;
      w.backend.beforeAddPages = () async =>
          during = w.ledgers.single.bytesOf(ExportMemoryKind.encoded);
      await w.service.exportNote(
        _noteOf(pages.single),
        const PdfExportOptions(),
      );
      final ledger = w.ledgers.single;
      expect(during, 2 * jpeg.length, reason: 'the original + the clone');
      expect(ledger.peakCopyBytes, 0);
      expect(ledger.peakBytes, 2 * jpeg.length);
      expect(ledger.heldBytes, 0);
    });

    test('an addPages error with an image → abort, the copy and the image '
        'released', () async {
      final w = ExportWorld();
      w.gateway.arriveBytes('j', PdfObjectFixtures.jpegBaseline64x48);
      final pages = await _note(w, 1);
      w.objects.addObjects(pages.single.id, [
        _image('i', pages.single.id, 'j'),
      ]);
      w.backend.addPagesError = StateError('worker died');
      final reports = captureFlutterErrors();
      await expectLater(
        w.service.exportNote(_noteOf(pages.single), const PdfExportOptions()),
        throwsA(hasCode(PdfErrorCode.exportFailed)),
      );
      await pumpEventQueue();
      final ledger = w.ledgers.single;
      expect(ledger.copyBytes, 0);
      expect(ledger.heldBytes, 0);
      expect(ledger.peakCopyBytes, PdfObjectFixtures.jpegBaseline64x48.length);
      expect(w.backend.events.last, 'abort#1');
      expect(reports, hasLength(1));
    });
  });

  test('web rules on the VM: 16 parts per addPages', () async {
    final w = ExportWorld(web: true);
    final pages = await _note(w, 20);
    for (final page in pages) {
      w.addStroke(page.id);
    }
    await w.service.exportNote(_noteOf(pages.first), const PdfExportOptions());
    expect([for (final c in w.backend.chunks) c.length], [16, 4]);
    expect(kIsWeb, isFalse, reason: 'the VM runs the web rules here');
  });
}
