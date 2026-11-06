// T26a (m5-7/03-ink 8.1, 4.10, 6.10.2): InkTextLayout with the real NoteSans —
// height = lines × fontSize × lineHeight (forced strut), an empty text is one line,
// the three alignments, bold is wider, measureSync (null before the load, = measure
// after it, the fallback value after a failure), textStyleOf / strutStyleOf are what
// INK paints with, and an EditableText with the same styles and no padding lays the
// glyphs out where INK's paragraph does (E-6).
// (T34) measure = the drawn paragraph: a text box framed at the measured height
// clips nothing (one line less clips the last line); rasterize puts the glyphs on
// the pixels of the screen drawing (no background).
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/object/object_painter.dart';
import 'package:ink_engine/src/text/fonts.dart';
import 'package:ink_engine/src/text/text_layout.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

final _editKey = GlobalKey(debugLabel: 'editable');

Future<Uint8List> _files({required bool bold}) async =>
    File('assets/fonts/NoteSans-${bold ? 'Bold' : 'Regular'}.ttf')
        .readAsBytesSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const style = core.TextBoxStyle(); // 16 pt, line height 1.4

  group('with NoteSans loaded', () {
    setUpAll(() async {
      debugSetInkFontSource(_files);
      await InkFonts.ensureLoaded();
    });
    tearDownAll(() => debugSetInkFontSource(null));

    test('height = lines × the forced strut line (fontSize × lineHeight, which the '
        'engine rounds to whole pt); empty = one line', () async {
      final lines = buildTextBoxParagraph(
        '가\nb\n다',
        style,
        300,
      ).computeLineMetrics();
      expect(lines, hasLength(3));
      final lineH = lines.first.height;
      expect(lineH, closeTo(16 * 1.4, 0.5));
      // forced strut: a Hangul line and a Latin line have the same height
      expect(lines.map((l) => l.height).toSet(), {lineH});
      final one = await InkTextLayout.measure('안녕 hello', style, widthPt: 300);
      expect(one.width, 300);
      expect(
        one.height,
        closeTo(16 * 1.4, 0.01),
        reason: 'max(paragraph, 1 line)',
      );
      final three = await InkTextLayout.measure('가\nb\n다', style, widthPt: 300);
      expect(three.height, closeTo(3 * lineH, 0.01));
      final empty = await InkTextLayout.measure('', style, widthPt: 300);
      expect(empty.height, closeTo(16 * 1.4, 0.01));
      final big = await InkTextLayout.measure(
        'x\ny',
        const core.TextBoxStyle(fontSizePt: 30, lineHeight: 2),
        widthPt: 300,
      );
      expect(big.height, closeTo(120, 0.01));
      // wrapping: a long Korean text in a narrow box takes several whole lines
      final wrapped = await InkTextLayout.measure(
        '안녕하세요 필기노트입니다 이 문장은 줄바꿈 시험을 위한 긴 문장입니다',
        style,
        widthPt: 120,
      );
      expect(wrapped.height, greaterThan(2 * lineH));
      expect(
        wrapped.height / lineH,
        closeTo((wrapped.height / lineH).roundToDouble(), 0.01),
      );
    });

    test('alignment: start → left, center, end → right', () {
      double lineLeft(core.TextAlignKind a) {
        final p = buildTextBoxParagraph('abc', style.copyWith(align: a), 200);
        final m = p.computeLineMetrics().single;
        return m.left;
      }

      final p = buildTextBoxParagraph('abc', style, 200);
      final w = p.computeLineMetrics().single.width;
      expect(lineLeft(core.TextAlignKind.start), closeTo(0, 0.01));
      expect(lineLeft(core.TextAlignKind.center), closeTo((200 - w) / 2, 0.01));
      expect(lineLeft(core.TextAlignKind.end), closeTo(200 - w, 0.01));
    });

    test('bold lays out with another width', () {
      final regular = buildTextBoxParagraph('필기 노트 Hello', style, 1000);
      final bold = buildTextBoxParagraph(
        '필기 노트 Hello',
        style.copyWith(bold: true),
        1000,
      );
      expect((bold.longestLine - regular.longestLine).abs(), greaterThan(0.5));
    });

    test('measureSync = measure once loaded', () async {
      final sync = InkTextLayout.measureSync('가나다\nabc', style, widthPt: 150);
      final async = await InkTextLayout.measure(
        '가나다\nabc',
        style,
        widthPt: 150,
      );
      expect(sync, async);
    });

    test('textStyleOf / strutStyleOf are the painted styles (CP-INK-3)', () {
      final s = const core.TextBoxStyle(
        fontSizePt: 20,
        colorArgb: 0xFF123456,
        bold: true,
        lineHeight: 1.6,
      );
      final t = InkTextLayout.textStyleOf(s);
      expect(t.fontFamily, 'NoteSans');
      expect(t.fontSize, 20);
      expect(t.height, 1.6);
      expect(t.color, const Color(0xFF123456));
      expect(t.fontWeight, FontWeight.w700);
      expect(InkTextLayout.textStyleOf(style).fontWeight, FontWeight.w400);
      final strut = InkTextLayout.strutStyleOf(s);
      expect(strut.fontFamily, 'NoteSans');
      expect(strut.fontSize, 20);
      expect(strut.height, 1.6);
      expect(strut.forceStrutHeight, isTrue);
    });

    testWidgets('an EditableText with the same styles and no padding = the INK '
        'paragraph (first-line glyph box, line height, height)', (
      tester,
    ) async {
      const text = '안녕 hello\n둘째 줄';
      const width = 240.0;
      final controller = TextEditingController(text: text);
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: _editKey,
              child: SizedBox(
                width: width,
                child: EditableText(
                  controller: controller,
                  focusNode: focus,
                  style: InkTextLayout.textStyleOf(style),
                  strutStyle: InkTextLayout.strutStyleOf(style),
                  textAlign: TextAlign.left,
                  maxLines: null,
                  textScaler: TextScaler.noScaling,
                  cursorColor: const Color(0xFF000000),
                  backgroundCursorColor: const Color(0xFF808080),
                ),
              ),
            ),
          ),
        ),
      );
      final editable = tester.allRenderObjects
          .whereType<RenderEditable>()
          .single;
      final paragraph = buildTextBoxParagraph(text, style, width);
      expect(editable.size.height, closeTo(paragraph.height, 0.01));
      expect(
        editable.preferredLineHeight,
        closeTo(paragraph.computeLineMetrics().first.height, 0.01),
      );
      // the glyphs land on the same pixels (E-6: nothing jumps when editing ends)
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_editKey),
      );
      final editPixels = await tester.runAsync(() async {
        final image = await boundary.toImage();
        return _darkBox(image);
      });
      final inkPixels = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawParagraph(paragraph, Offset.zero);
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          width.ceil(),
          paragraph.height.ceil(),
        );
        picture.dispose();
        return _darkBox(image);
      });
      expect(editPixels!.count, greaterThan(50));
      expect(editPixels.box, inkPixels!.box);
      expect(
        (editPixels.count - inkPixels.count).abs(),
        lessThanOrEqualTo(inkPixels.count ~/ 50),
      );
    });
  });

  group('T34: the drawn text box', () {
    setUpAll(() async {
      debugSetInkFontSource(_files);
      await InkFonts.ensureLoaded();
    });
    tearDownAll(() => debugSetInkFontSource(null));

    core.TextBoxObject box(
      String text,
      core.TextBoxStyle s,
      core.PageRect r, {
      double rotation = 0,
    }) => core.TextBoxObject(
      id: 'tb',
      pageId: 'p1',
      frame: core.ElementFrame(r, rotation: rotation),
      text: text,
      style: s,
      createdAt: 1,
    );

    /// The box drawn by the annotation painter at [k] px per pt, the frame's top-left at
    /// the image origin, [w] × [h] pt of image.
    Future<ByteData> drawn(
      core.TextBoxObject o,
      double w,
      double h, {
      double k = 2,
    }) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..scale(k)
        ..translate(-o.frame.rect.left, -o.frame.rect.top);
      expect(
        paintObjectSimple(canvas, o, paperArgb: 0xFFFFFFFF, onePx: 1 / k),
        isTrue,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage((w * k).ceil(), (h * k).ceil());
      picture.dispose();
      final data = (await image.toByteData())!;
      image.dispose();
      return data;
    }

    int alphaDiff(ByteData a, ByteData b) {
      expect(a.lengthInBytes, b.lengthInBytes);
      var n = 0;
      for (var i = 3; i < a.lengthInBytes; i += 4) {
        if ((a.getUint8(i) - b.getUint8(i)).abs() > 8) n++;
      }
      return n;
    }

    int inked(ByteData a) {
      var n = 0;
      for (var i = 3; i < a.lengthInBytes; i += 4) {
        if (a.getUint8(i) > 128) n++;
      }
      return n;
    }

    test('measure = the drawn paragraph: framed at the measured height nothing '
        'is clipped, one line less clips the last line', () async {
      final cases = <(String, core.TextBoxStyle, double)>[
        ('안녕 hello\n둘째 줄\n셋째', style, 200),
        (
          '안녕하세요 필기노트입니다 이 문장은 줄바꿈 시험을 위한 긴 문장입니다',
          style.copyWith(align: core.TextAlignKind.center, bold: true),
          140,
        ),
        (
          'Big gy\n큰 글씨',
          const core.TextBoxStyle(fontSizePt: 30, lineHeight: 2),
          260,
        ),
        ('한 줄', const core.TextBoxStyle(fontSizePt: 12, lineHeight: 1), 120),
      ];
      for (final (text, s, w) in cases) {
        final measured = await InkTextLayout.measure(text, s, widthPt: w);
        final p = buildTextBoxParagraph(text, s, w);
        expect(measured.height, closeTo(p.height, 0.01), reason: text);
        final lineH = p.computeLineMetrics().last.height;
        final h = measured.height;
        final exact = await drawn(
          box(text, s, core.PageRect(30, 40, 30 + w, 40 + h)),
          w,
          h + 60,
        );
        final roomy = await drawn(
          box(text, s, core.PageRect(30, 40, 30 + w, 40 + h + 60)),
          w,
          h + 60,
        );
        expect(inked(exact), greaterThan(50), reason: text);
        expect(alphaDiff(exact, roomy), 0, reason: 'nothing clipped: $text');
        final short = await drawn(
          box(text, s, core.PageRect(30, 40, 30 + w, 40 + h - lineH)),
          w,
          h + 60,
        );
        expect(
          alphaDiff(short, roomy),
          greaterThan(20),
          reason: 'the last line is clipped: $text',
        );
      }
    });

    test('rasterize puts the glyphs on the pixels of the screen drawing (no '
        'background)', () async {
      for (final s in [
        style,
        style.copyWith(
          bold: true,
          align: core.TextAlignKind.center,
          backgroundArgb: 0xFF00AA00,
        ),
        const core.TextBoxStyle(
          fontSizePt: 28,
          lineHeight: 1.2,
          align: core.TextAlignKind.end,
        ),
      ]) {
        final o = box(
          '안녕 hello\n둘째 줄 가나다 wrapping text',
          s,
          const core.PageRect(100, 50, 340, 150),
        );
        final raster = await InkTextLayout.rasterize(o, pixelsPerPt: 2);
        expect(raster, isNotNull);
        expect((raster!.width, raster.height), (480, 200));
        final rasterBytes = (await raster.toByteData())!;
        raster.dispose();
        expect(
          rasterBytes.getUint8((198 * 480 + 2) * 4 + 3),
          0,
          reason: 'transparent: the background is not drawn',
        );
        final screen = await drawn(
          o.copyWith(style: s.copyWith(clearBackground: true)),
          240,
          100,
        );
        expect(inked(screen), greaterThan(200));
        expect(alphaDiff(rasterBytes, screen), 0);
      }
    });
  });

  group('before and after a load', () {
    tearDown(() => debugSetInkFontSource(null));

    test(
      'measureSync: null before the load (and starts it), then = measure',
      () async {
        debugSetInkFontSource(_files);
        expect(InkFontsDebug.isLoaded, isFalse);
        expect(InkTextLayout.measureSync('abc', style, widthPt: 100), isNull);
        expect(InkFontsDebug.isLoading, isTrue, reason: 'it started the load');
        await InkFonts.ensureLoaded();
        final sync = InkTextLayout.measureSync('abc', style, widthPt: 100);
        expect(sync, await InkTextLayout.measure('abc', style, widthPt: 100));
      },
    );

    test(
      'after a failed load: the fallback-font value, no exception',
      () async {
        debugSetInkFontSource(
          ({required bool bold}) async => throw StateError('x'),
        );
        final measured = await InkTextLayout.measure(
          'abc',
          style,
          widthPt: 100,
        );
        expect(measured.height, closeTo(16 * 1.4, 0.01));
        expect(InkFontsDebug.isLoaded, isFalse);
        expect(InkTextLayout.measureSync('abc', style, widthPt: 100), measured);
      },
    );
  });

  test('the raster scale keeps ≤ 4 Mpx and ≤ 8192 px a side', () {
    final k = rasterScaleFor(595, 842, 300 / 72);
    expect((595 * k).ceil() * (842 * k).ceil(), lessThanOrEqualTo(4194304));
    expect(rasterScaleFor(10, 10, 2), 2);
    final long = rasterScaleFor(14400, 10, 4);
    expect((14400 * long).ceil(), lessThanOrEqualTo(8192));
  });
}

/// The bounding box (x0, y0, x1, y1) and count of the clearly inked pixels.
Future<({List<int> box, int count})> _darkBox(ui.Image image) async {
  final data = (await image.toByteData())!;
  var x0 = image.width, y0 = image.height, x1 = -1, y1 = -1, count = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (data.getUint8((y * image.width + x) * 4 + 3) > 128) {
        count++;
        if (x < x0) x0 = x;
        if (y < y0) y0 = y;
        if (x > x1) x1 = x;
        if (y > y1) y1 = y;
      }
    }
  }
  image.dispose();
  return (box: [x0, y0, x1, y1], count: count);
}
