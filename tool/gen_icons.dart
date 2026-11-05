// Generates the web app icons in app/web (docs/plans/01-infra.md 6.9
// '아이콘'): indigo background, a white rounded sheet of paper with three
// ruled lines and a diagonal pen stroke. Maskable icons keep the drawing
// inside the central 80 % safe zone.
//
// Usage (workspace root): dart run tool/gen_icons.dart [--out app/web]
// The outputs are committed; ws check R13 verifies their pixel sizes.
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// One generated file, relative to the web directory.
typedef IconSpec = ({String path, int size, bool maskable});

/// Every icon the web app references (index.html, manifest.json).
const List<IconSpec> iconSpecs = [
  (path: 'favicon.png', size: 32, maskable: false),
  (path: 'icons/Icon-180.png', size: 180, maskable: false),
  (path: 'icons/Icon-192.png', size: 192, maskable: false),
  (path: 'icons/Icon-512.png', size: 512, maskable: false),
  (path: 'icons/Icon-maskable-192.png', size: 192, maskable: true),
  (path: 'icons/Icon-maskable-512.png', size: 512, maskable: true),
];

/// Side of the master drawing that every size is reduced from.
const int _master = 1024;

/// App seed color (theme 0xFF3949AB) and the ruled-line tint.
final img.Color _indigo = img.ColorRgb8(0x39, 0x49, 0xAB);
final img.Color _white = img.ColorRgb8(0xFF, 0xFF, 0xFF);
final img.Color _rule = img.ColorRgb8(0xC5, 0xCA, 0xE9);

/// Draws the icon on a [_master]-sized canvas. [maskable] shrinks the
/// drawing into the central 80 % (the maskable safe zone).
img.Image _draw({required bool maskable}) {
  final canvas = img.Image(width: _master, height: _master);
  img.fill(canvas, color: _indigo);
  final inset = maskable ? 0.1 : 0.0;
  final scale = 1 - 2 * inset;
  int at(double unit) => ((inset + unit * scale) * _master).round();
  int len(double unit) => (unit * scale * _master).round();

  // Paper: 56 % wide, centered.
  img.fillRect(
    canvas,
    x1: at(0.22),
    y1: at(0.15),
    x2: at(0.78),
    y2: at(0.85),
    radius: len(0.06),
    color: _white,
  );
  // Three ruled lines.
  for (final y in [0.34, 0.46, 0.58]) {
    img.fillRect(
      canvas,
      x1: at(0.30),
      y1: at(y) - len(0.012),
      x2: at(0.70),
      y2: at(y) + len(0.012),
      radius: len(0.012),
      color: _rule,
    );
  }
  // Diagonal pen stroke with round ends: discs stamped along the segment.
  final (x1, y1, x2, y2) = (at(0.32), at(0.76), at(0.64), at(0.66));
  final steps = (x2 - x1).abs() + (y2 - y1).abs();
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    img.fillCircle(
      canvas,
      x: (x1 + (x2 - x1) * t).round(),
      y: (y1 + (y2 - y1) * t).round(),
      radius: len(0.0225),
      color: _indigo,
    );
  }
  return canvas;
}

/// PNG bytes of one icon. Deterministic for the same package:image version.
Uint8List renderIcon(int size, {required bool maskable}) {
  final master = _draw(maskable: maskable);
  final icon = size == _master
      ? master
      : img.copyResize(
          master,
          width: size,
          height: size,
          interpolation: img.Interpolation.average,
        );
  return img.encodePng(icon, level: 9);
}

/// Writes every [iconSpecs] file under [webDir]; returns the written paths.
List<String> writeIcons(String webDir) {
  final written = <String>[];
  for (final spec in iconSpecs) {
    final file = File(p.join(webDir, spec.path));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(renderIcon(spec.size, maskable: spec.maskable));
    written.add(file.path);
  }
  return written;
}

void main(List<String> args) {
  var out = p.join('app', 'web');
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--out' && i + 1 < args.length) {
      out = args[++i];
    } else {
      stderr.writeln('usage: dart run tool/gen_icons.dart [--out <web dir>]');
      exitCode = 64;
      return;
    }
  }
  for (final path in writeIcons(out)) {
    stdout.writeln('wrote $path');
  }
}
