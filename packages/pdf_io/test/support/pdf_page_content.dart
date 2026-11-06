// What each page of a saved PDF draws, read from its content streams (m5-7/06-pdf 8.2 T29 —
// V11 counts path objects: 'dashed pieces = INK vector pieces', 'one tape cover'). PDFium
// writes a classic cross-reference table with plain object dictionaries and Flate-compresses
// the content streams it generated on save (FPDF_SaveAsCopy), so a small scanner is enough:
// find every `N G obj … stream … endstream`, walk the page tree from the root /Pages node, join
// a page's /Contents streams and count the painting operators of its content.
//
// Web-safe: the caller passes [inflate] for /FlateDecode (VM: dart:io zlib.decode; Chrome:
// DecompressionStream('deflate') — test/web/support_inflate_browser.dart does it).
import 'dart:convert';
import 'dart:typed_data';

/// zlib (RFC 1950) data → the bytes it holds.
typedef PdfInflate = Future<Uint8List> Function(Uint8List zlib);

/// The painting operators of one page's content.
final class PdfPageOps {
  PdfPageOps(this.counts);

  /// operator → how many times the page's content uses it.
  final Map<String, int> counts;

  int _n(String op) => counts[op] ?? 0;

  /// Path objects that paint (fill and / or stroke — `n` paths only clip).
  int get paintedPaths =>
      _n('f') +
      _n('F') +
      _n('f*') +
      _n('S') +
      _n('s') +
      _n('B') +
      _n('B*') +
      _n('b') +
      _n('b*');

  /// Filled paths (`f`, `F`, `f*`, `B`, `B*`, `b`, `b*`).
  int get filledPaths =>
      _n('f') + _n('F') + _n('f*') + _n('B') + _n('B*') + _n('b') + _n('b*');

  /// XObjects drawn (images and forms — an original PDF page is a form).
  int get xObjects => _n('Do');

  /// Text objects (`BT … ET`).
  int get textObjects => _n('BT');

  @override
  String toString() => 'PdfPageOps($counts)';
}

/// The pages of a saved PDF, in page-tree order.
final class PdfPageContents {
  PdfPageContents._(this.pages);

  final List<PdfPageOps> pages;

  static Future<PdfPageContents> read(
    Uint8List bytes, {
    required PdfInflate inflate,
  }) async {
    final objects = _scanObjects(bytes);
    final root = objects.entries
        .where(
          (e) =>
              RegExp(r'/Type\s*/Pages\b').hasMatch(e.value.dict) &&
              !e.value.dict.contains('/Parent'),
        )
        .toList();
    if (root.length != 1) {
      throw StateError('expected one root /Pages node, found ${root.length}');
    }
    final pageObjects = <int>[];
    void walk(int n) {
      final dict = objects[n]?.dict ?? '';
      if (RegExp(r'/Type\s*/Pages\b').hasMatch(dict)) {
        final kids = RegExp(r'/Kids\s*\[([^\]]*)\]').firstMatch(dict)?.group(1);
        for (final m in RegExp(r'(\d+)\s+\d+\s+R').allMatches(kids ?? '')) {
          walk(int.parse(m.group(1)!));
        }
      } else if (RegExp(r'/Type\s*/Page\b').hasMatch(dict)) {
        pageObjects.add(n);
      }
    }

    walk(root.single.key);
    final pages = <PdfPageOps>[];
    for (final n in pageObjects) {
      final dict = objects[n]!.dict;
      final refs = <int>[];
      final array = RegExp(r'/Contents\s*\[([^\]]*)\]')
          .firstMatch(dict)
          ?.group(1);
      if (array != null) {
        for (final m in RegExp(r'(\d+)\s+\d+\s+R').allMatches(array)) {
          refs.add(int.parse(m.group(1)!));
        }
      } else {
        final one = RegExp(r'/Contents\s+(\d+)\s+\d+\s+R').firstMatch(dict);
        if (one != null) {
          final target = objects[int.parse(one.group(1)!)];
          if (target != null &&
              target.data == null &&
              target.dict.trimLeft().startsWith('[')) {
            // an indirect array of streams (PDFium writes one when a page's content was
            // generated more than once — several parts of one page)
            for (final m in RegExp(
              r'(\d+)\s+\d+\s+R',
            ).allMatches(target.dict)) {
              refs.add(int.parse(m.group(1)!));
            }
          } else {
            refs.add(int.parse(one.group(1)!));
          }
        }
      }
      final content = BytesBuilder(copy: false);
      for (final ref in refs) {
        final object = objects[ref];
        if (object == null || object.data == null) continue;
        content
          ..add(await _decoded(object, inflate))
          ..addByte(0x0A); // streams of one page are joined with white space
      }
      pages.add(PdfPageOps(countOperators(content.takeBytes())));
    }
    return PdfPageContents._(pages);
  }

  /// Operator counts of [content] (strings, hex strings, names, numbers, arrays, dictionaries
  /// and inline image data are skipped).
  static Map<String, int> countOperators(Uint8List content) {
    final text = latin1.decode(content);
    final counts = <String, int>{};
    var i = 0;
    final n = text.length;
    bool white(int c) =>
        c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C || c == 0;
    bool delimiter(int c) => '()<>[]{}/%'.codeUnits.contains(c);
    while (i < n) {
      final c = text.codeUnitAt(i);
      if (white(c)) {
        i++;
      } else if (c == 0x25) {
        // % comment to the end of the line
        while (i < n &&
            text.codeUnitAt(i) != 0x0A &&
            text.codeUnitAt(i) != 0x0D) {
          i++;
        }
      } else if (c == 0x28) {
        // ( literal string ), nested parentheses and \ escapes
        var depth = 0;
        while (i < n) {
          final d = text.codeUnitAt(i);
          if (d == 0x5C) {
            i += 2;
            continue;
          }
          if (d == 0x28) depth++;
          if (d == 0x29) {
            depth--;
            if (depth == 0) {
              i++;
              break;
            }
          }
          i++;
        }
      } else if (c == 0x3C && i + 1 < n && text.codeUnitAt(i + 1) != 0x3C) {
        // < hex string >
        final end = text.indexOf('>', i);
        i = end < 0 ? n : end + 1;
      } else if (delimiter(c)) {
        // '/' name, '<<' '>>' '[' ']' '{' '}' — skip the delimiter (and a name's characters)
        i++;
        if (c == 0x2F) {
          while (i < n &&
              !white(text.codeUnitAt(i)) &&
              !delimiter(text.codeUnitAt(i))) {
            i++;
          }
        } else if ((c == 0x3C || c == 0x3E) &&
            i < n &&
            text.codeUnitAt(i) == c) {
          i++;
        }
      } else {
        final start = i;
        while (i < n &&
            !white(text.codeUnitAt(i)) &&
            !delimiter(text.codeUnitAt(i))) {
          i++;
        }
        final token = text.substring(start, i);
        if (RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)$').hasMatch(token) ||
            token == 'true' ||
            token == 'false' ||
            token == 'null') {
          continue; // an operand
        }
        counts[token] = (counts[token] ?? 0) + 1;
        if (token == 'ID') {
          // inline image data up to EI
          final end = text.indexOf(RegExp(r'\sEI\b'), i);
          i = end < 0 ? n : end + 3;
          counts['EI'] = (counts['EI'] ?? 0) + 1;
        }
      }
    }
    return counts;
  }
}

final class _PdfObject {
  _PdfObject(this.dict, this.data);
  final String dict;
  final Uint8List? data; // raw stream bytes (still filtered)
}

Future<Uint8List> _decoded(_PdfObject object, PdfInflate inflate) async {
  final filter = RegExp(r'/Filter\s*\[?\s*/(\w+)')
      .firstMatch(object.dict)
      ?.group(1);
  return switch (filter) {
    null => object.data!,
    'FlateDecode' => inflate(object.data!),
    final other => throw UnsupportedError('content filter /$other'),
  };
}

Map<int, _PdfObject> _scanObjects(Uint8List bytes) {
  final text = latin1.decode(bytes);
  final header = RegExp(r'(\d+)\s+\d+\s+obj\b');
  final found =
      <int, (String, int?, int?)>{}; // dict, data start, length or ref
  final lengthRefs = <int, int>{};
  var from = 0;
  while (true) {
    final m = header.firstMatch(text.substring(from));
    if (m == null) break;
    final number = int.parse(m.group(1)!);
    final start = from + m.end;
    final endobj = text.indexOf('endobj', start);
    final end = endobj < 0 ? text.length : endobj;
    final stream = text.indexOf('stream', start);
    if (stream >= 0 && stream < end) {
      final dict = text.substring(start, stream);
      var dataStart = stream + 6;
      if (text.codeUnitAt(dataStart) == 0x0D) dataStart++;
      if (text.codeUnitAt(dataStart) == 0x0A) dataStart++;
      final ref = RegExp(r'/Length\s+(\d+)\s+\d+\s+R').firstMatch(dict);
      final direct = ref != null
          ? null
          : RegExp(r'/Length\s+(\d+)').firstMatch(dict);
      if (ref != null) lengthRefs[number] = int.parse(ref.group(1)!);
      found[number] = (
        dict,
        dataStart,
        direct == null ? null : int.parse(direct.group(1)!),
      );
      final endstream = text.indexOf('endstream', dataStart);
      from = endstream < 0 ? text.length : endstream + 9;
    } else {
      found[number] = (text.substring(start, end), null, null);
      from = end < text.length ? end + 6 : text.length;
    }
  }
  final out = <int, _PdfObject>{};
  for (final MapEntry(key: n, value: (dict, dataStart, length))
      in found.entries) {
    if (dataStart == null) {
      out[n] = _PdfObject(dict, null);
      continue;
    }
    var size = length;
    if (size == null && lengthRefs[n] != null) {
      size = int.tryParse(found[lengthRefs[n]!]?.$1.trim() ?? '');
    }
    size ??= text.indexOf('endstream', dataStart) - dataStart;
    out[n] = _PdfObject(
      dict,
      Uint8List.sublistView(bytes, dataStart, dataStart + size),
    );
  }
  return out;
}
