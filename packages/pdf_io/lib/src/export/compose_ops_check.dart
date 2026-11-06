// lib/src/export/compose_ops_check.dart — m5-7/06-pdf 6.2.6 (PDF T21). Internal (not in the
// barrel).
//
// The structural checks a compose backend makes before it interprets one part: every verb is
// known and has its coordinates, a path object starts with moveTo and ends with endObject
// (paint index in range), `image` / `text` ops come only outside a path object (1차 'ops end
// inside an object'), their image / text index is in range, a text op's font is loaded (this
// part's fonts or an earlier part's), and the coordinates are used up exactly. Web-safe.
import 'compose_plan.dart';

/// Throws ArgumentError when [ops] breaks a rule above. [loadedFonts]: font ids earlier parts
/// of the same job carried; a part carrying one of them again is an error too (a font id
/// rides on the first part that uses it, never again — 4.1.4).
void checkComposeOps(PdfComposePageOps ops, {Set<int> loadedFonts = const {}}) {
  final verbs = ops.verbs, coords = ops.coords;
  if (ops.paints.length % PdfComposeOpcodes.paintStride != 0) {
    throw ArgumentError.value(
      ops.paints.length,
      'paints',
      'not a multiple of ${PdfComposeOpcodes.paintStride}',
    );
  }
  for (final id in ops.fonts.keys) {
    if (loadedFonts.contains(id)) {
      throw ArgumentError.value(id, 'fonts', 'font already loaded in this job');
    }
  }
  final paintCount = ops.paints.length ~/ PdfComposeOpcodes.paintStride;
  var c = 0;
  var open = false;
  double take(int v, int n) {
    if (c + n > coords.length) {
      throw ArgumentError.value(
        coords.length,
        'coords',
        'verb $v needs $n more values',
      );
    }
    final first = coords[c];
    c += n;
    return first;
  }

  int index(double value, int count, String what, int v) {
    final i = value.toInt();
    if (i != value || i < 0 || i >= count) {
      throw ArgumentError.value(value, what, 'verb $v: out of range 0..$count');
    }
    return i;
  }

  for (var v = 0; v < verbs.length; v++) {
    switch (verbs[v]) {
      case PdfComposeOpcodes.moveTo:
        take(v, 2);
        open = true;
      case PdfComposeOpcodes.lineTo || PdfComposeOpcodes.cubicTo:
        if (!open) {
          throw ArgumentError.value(verbs[v], 'verbs', 'verb $v: no moveTo');
        }
        take(v, verbs[v] == PdfComposeOpcodes.lineTo ? 2 : 6);
      case PdfComposeOpcodes.close:
        if (!open) {
          throw ArgumentError.value(verbs[v], 'verbs', 'verb $v: no moveTo');
        }
      case PdfComposeOpcodes.endObject:
        if (!open) {
          throw ArgumentError.value(
            verbs[v],
            'verbs',
            'verb $v: endObject outside an object',
          );
        }
        index(take(v, 1), paintCount, 'paint', v);
        open = false;
      case PdfComposeOpcodes.image:
        if (open) {
          throw ArgumentError.value(
            verbs[v],
            'verbs',
            'verb $v: image inside an open path object',
          );
        }
        index(
          take(v, PdfComposeOpcodes.imageArgs),
          ops.images.length,
          'image',
          v,
        );
      case PdfComposeOpcodes.text:
        if (open) {
          throw ArgumentError.value(
            verbs[v],
            'verbs',
            'verb $v: text inside an open path object',
          );
        }
        final start = c;
        index(take(v, PdfComposeOpcodes.textArgs), ops.texts.length, 'text', v);
        final fontId = coords[start + 1].toInt();
        if (!ops.fonts.containsKey(fontId) && !loadedFonts.contains(fontId)) {
          throw ArgumentError.value(
            fontId,
            'fontId',
            'verb $v: font not loaded',
          );
        }
      default:
        throw ArgumentError.value(verbs[v], 'verbs', 'verb $v: unknown opcode');
    }
  }
  if (open) throw ArgumentError('ops end inside an object');
  if (c != coords.length) {
    throw ArgumentError.value(
      coords.length,
      'coords',
      '$c values used by the verbs',
    );
  }
}
