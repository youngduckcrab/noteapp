// m5-7/03-ink 6.12.2 (T36, 총괄 답 Q5): the loader of the raster host's test seam
// (OffscreenMathHost.debugExtraSvgLoader). Its SVG arrives only after [delay]
// (and after [gate] opens, when given) — the native profile / release path,
// where flutter_svg decodes on another isolate and VectorGraphic sets its
// picture later, reproduced on the VM debug and Chrome test runners (where
// flutter_svg's compute is synchronous).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// An 8 × 8 pure red square: its pixels are the only red ones in a black formula raster.
const String redSquareSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8" '
    'viewBox="0 0 8 8"><rect width="8" height="8" fill="#ff0000"/></svg>';

final class DelayedSvgLoader extends SvgLoader<String> {
  DelayedSvgLoader(this.delay, {this.gate});

  final Duration delay;
  final Completer<void>? gate;

  final List<DateTime?> _loads = [];

  /// Times the bytes were asked for.
  int get loads => _loads.length;

  @override
  Future<String?> prepareMessage(BuildContext? context) async {
    _loads.add(null);
    final g = gate;
    if (g != null) await g.future;
    await Future<void>.delayed(delay);
    return redSquareSvg;
  }

  @override
  String provideSvg(String? message) => message!;
}
