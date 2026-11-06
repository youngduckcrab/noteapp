// test/support/fake_rasterizers.dart — (v2.1, PDF-M2) solid RGBA fakes of the resolver's raster
// ports (m5-7/06-pdf 4.3.1 · 6.2.4). They draw exactly the asked size (⌈w·k⌉ × ⌈h·k⌉ — the INK
// rule) in one colour and record every call. Web-safe (VM and Chrome tests).
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/raster_ports.dart';

/// What a fake raster port does on the next call.
enum FakeRasterMode {
  /// Solid RGBA of the asked size.
  solid,

  /// Completes with null (invalid / failed).
  fail,

  /// Throws a StateError.
  throws,

  /// Never completes (a raster that hangs — the resolver's timeout / cancel).
  hang,
}

/// One recorded rasterize call.
typedef FakeRasterCall = ({core.ElementId id, double pixelsPerPt});

/// Solid straight RGBA [width] × [height] in [argb].
PdfRgbaData solidRgba(int width, int height, {int argb = 0xFF204080}) {
  final rgba = Uint8List(width * height * 4);
  final r = argb ~/ 0x10000 % 0x100,
      g = argb ~/ 0x100 % 0x100,
      b = argb % 0x100,
      a = argb ~/ 0x1000000 % 0x100;
  for (var i = 0; i < rgba.length; i += 4) {
    rgba[i] = r;
    rgba[i + 1] = g;
    rgba[i + 2] = b;
    rgba[i + 3] = a;
  }
  return PdfRgbaData(rgba, width: width, height: height, hasAlpha: true);
}

PdfRgbaData? _sized(ui.Size sizePt, double k, int argb) {
  final px = rasterPixelSize(sizePt, k);
  if (px.width < 1 || px.height < 1) return null;
  return solidRgba(px.width, px.height, argb: argb);
}

Future<PdfRgbaData?> _answer(
  FakeRasterMode mode,
  ui.Size sizePt,
  double k,
  int argb,
) => switch (mode) {
  FakeRasterMode.solid => Future.value(_sized(sizePt, k, argb)),
  FakeRasterMode.fail => Future<PdfRgbaData?>.value(),
  FakeRasterMode.throws => Future.error(StateError('fake raster failed')),
  FakeRasterMode.hang => Completer<PdfRgbaData?>().future,
};

/// Math port fake: [layoutSizes] by object id (missing → [defaultLayout]; null → invalid LaTeX),
/// the raster = solid RGBA of ⌈lw·k⌉ × ⌈lh·k⌉.
final class FakeMathRasterizer implements PdfMathRasterizer {
  FakeMathRasterizer({
    Map<core.ElementId, ui.Size?>? layoutSizes,
    this.defaultLayout = const ui.Size(40, 20),
    this.mode = FakeRasterMode.solid,
    this.argb = 0xFF102030,
  }) : layoutSizes = layoutSizes ?? {};

  final Map<core.ElementId, ui.Size?> layoutSizes;
  final ui.Size? defaultLayout;
  FakeRasterMode mode;
  final int argb;

  final List<core.ElementId> layoutCalls = [];
  final List<FakeRasterCall> calls = [];

  @override
  ui.Size? layoutSize(core.MathObject object) {
    layoutCalls.add(object.id);
    return layoutSizes.containsKey(object.id)
        ? layoutSizes[object.id]
        : defaultLayout;
  }

  @override
  Future<PdfRgbaData?> rasterize(
    core.MathObject object, {
    required double pixelsPerPt,
  }) {
    calls.add((id: object.id, pixelsPerPt: pixelsPerPt));
    final size = layoutSize(object);
    layoutCalls.removeLast(); // not a layout call of the resolver
    if (size == null) return Future<PdfRgbaData?>.value();
    return _answer(mode, size, pixelsPerPt, argb);
  }
}

/// Text port fake: solid RGBA of ⌈w·k⌉ × ⌈h·k⌉ of the frame.
final class FakeTextRasterizer implements PdfTextRasterizer {
  FakeTextRasterizer({
    this.mode = FakeRasterMode.solid,
    this.argb = 0xFF304050,
  });

  FakeRasterMode mode;
  final int argb;
  final List<FakeRasterCall> calls = [];

  @override
  Future<PdfRgbaData?> rasterize(
    core.TextBoxObject object, {
    required double pixelsPerPt,
  }) {
    calls.add((id: object.id, pixelsPerPt: pixelsPerPt));
    final r = object.frame.rect;
    return _answer(mode, ui.Size(r.width, r.height), pixelsPerPt, argb);
  }
}

/// A font source that counts reads; [fail] → TimeoutException-like failure.
final class FakeFontSource {
  FakeFontSource({this.fail = false});

  bool fail;
  final List<bool> reads = []; // bold flags in call order
  static final Uint8List regular = Uint8List.fromList(List.filled(64, 1));
  static final Uint8List bold = Uint8List.fromList(List.filled(80, 2));

  Future<Uint8List> call({required bool bold}) async {
    reads.add(bold);
    if (fail) throw TimeoutException('fake font read');
    return bold ? FakeFontSource.bold : FakeFontSource.regular;
  }
}
