// lib/src/repo/markdown_import.dart — (v2.17-md) contract 00-overview 7.9 C217M-16,
// m5-7/08-markdown 10.2: the bytes of a picked .md / .markdown / .txt file → the text and
// title of a new MD 문서. Pure Dart; UTF-8 only. The text is the decoded file as it is — a
// BOM (U+FEFF) and CRLF line ends stay in it, so `utf8.encode(result.text)` gives back the
// file's bytes exactly (08-markdown 4.6).
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../common/errors.dart';
import 'markdown_repository.dart';

/// Why a file cannot become an MD 문서.
enum MarkdownDecodeFailure {
  /// Over `MarkdownLimits.check` (text bytes or the encoded sync record).
  tooLarge,

  /// Holds a NUL byte (a binary file).
  notText,

  /// Not valid UTF-8 (e.g. a CP949 file).
  notUtf8,
}

@immutable
final class MarkdownDecodeResult {
  const MarkdownDecodeResult.ok({
    required String this.text,
    required String this.title,
  }) : failure = null;
  const MarkdownDecodeResult.failed(MarkdownDecodeFailure this.failure)
    : text = null,
      title = null;

  /// The file's text, unchanged (null on failure).
  final String? text;

  /// The document title (null on failure).
  final String? title;
  final MarkdownDecodeFailure? failure;

  bool get isOk => failure == null;

  @override
  bool operator ==(Object other) =>
      other is MarkdownDecodeResult &&
      other.text == text &&
      other.title == title &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(text, title, failure);

  @override
  String toString() => isOk
      ? 'MarkdownDecodeResult("$title", ${text!.length} chars)'
      : 'MarkdownDecodeResult(${failure!.name})';
}

abstract final class MarkdownImport {
  /// The title when nothing else gives one.
  static const String fallbackTitle = '가져온 문서';

  /// The longest title (library names).
  static const int maxTitleChars = 200;

  /// File names that say nothing about the document (case-insensitive, without the
  /// extension): the title then comes from the front matter `title:` or the first h1.
  static const Set<String> genericNames = {
    'readme',
    'index',
    'untitled',
    '제목 없음',
    'document',
    'notes',
  };

  static const List<String> _extensions = ['.markdown', '.md', '.txt'];

  /// [bytes] of the file [fileName] (its name only, or a path — the last segment counts).
  static MarkdownDecodeResult decode(
    Uint8List bytes, {
    required String fileName,
  }) {
    if (bytes.contains(0)) {
      return const MarkdownDecodeResult.failed(MarkdownDecodeFailure.notText);
    }
    // Dart's UTF-8 decoder drops a leading BOM: count them and put them back, so the
    // text encodes to exactly these bytes.
    var boms = 0;
    while (bytes.length >= (boms + 1) * 3 &&
        bytes[boms * 3] == 0xEF &&
        bytes[boms * 3 + 1] == 0xBB &&
        bytes[boms * 3 + 2] == 0xBF) {
      boms++;
    }
    final String text;
    try {
      text =
          '\uFEFF' * boms +
          const Utf8Decoder(allowMalformed: false).convert(bytes, boms * 3);
    } on FormatException {
      return const MarkdownDecodeResult.failed(MarkdownDecodeFailure.notUtf8);
    }
    try {
      MarkdownLimits.check(text);
    } on MarkdownTooLargeException {
      return const MarkdownDecodeResult.failed(MarkdownDecodeFailure.tooLarge);
    }
    return MarkdownDecodeResult.ok(text: text, title: titleFor(fileName, text));
  }

  /// The title of a document from [fileName] with the text [text] (10.2).
  static String titleFor(String fileName, String text) {
    var name = fileName.split(RegExp(r'[/\\]')).last;
    final lower = name.toLowerCase();
    for (final ext in _extensions) {
      // A name that is only the extension ('.md') has no title part.
      if (lower.endsWith(ext)) {
        name = name.substring(0, name.length - ext.length);
        break;
      }
    }
    name = _clean(name);
    if (name.isNotEmpty && !genericNames.contains(name.toLowerCase())) {
      return _cut(name);
    }
    final fromText = _titleFromText(text);
    if (fromText != null) return _cut(fromText);
    return name.isNotEmpty ? _cut(name) : fallbackTitle;
  }

  static final RegExp _h1 = RegExp(r'^\s{0,3}#\s+(.+?)(\s+#+)?\s*$');
  static final RegExp _frontTitle = RegExp(r'''^title\s*:\s*(.+?)\s*$''');

  static String? _titleFromText(String text) {
    var lines = text
        .replaceFirst('﻿', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    if (lines.isNotEmpty && lines.first.trim() == '---') {
      final end = lines.indexWhere(
        (l) => l.trim() == '---' || l.trim() == '...',
        1,
      );
      if (end > 0) {
        for (final l in lines.sublist(1, end)) {
          final m = _frontTitle.firstMatch(l);
          if (m != null) {
            var v = m.group(1)!;
            if (v.length >= 2 &&
                ((v.startsWith('"') && v.endsWith('"')) ||
                    (v.startsWith("'") && v.endsWith("'")))) {
              v = v.substring(1, v.length - 1);
            }
            final t = _clean(v);
            if (t.isNotEmpty) return t;
          }
        }
        lines = lines.sublist(end + 1);
      }
    }
    var inFence = false;
    for (final l in lines) {
      final t = l.trimLeft();
      if (t.startsWith('```') || t.startsWith('~~~')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;
      final m = _h1.firstMatch(l);
      if (m != null) {
        final h = _clean(
          m.group(1)!.replaceAll(RegExp(r'(\*{1,3}|_{2,3}|~~|`+)'), ''),
        );
        if (h.isNotEmpty) return h;
      }
    }
    return null;
  }

  /// Hangul composed (NFC for Hangul — macOS hands out decomposed names), control
  /// characters dropped, whitespace runs folded, trimmed.
  static String _clean(String s) =>
      composeHangul(s)
          .replaceAll(RegExp(r'[\u0000-\u001F\u007F​﻿]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  static String _cut(String s) {
    if (s.length <= maxTitleChars) return s;
    var cut = maxTitleChars;
    final unit = s.codeUnitAt(cut - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) cut--;
    return s.substring(0, cut).trimRight();
  }

  /// Conjoining jamo (L V [T]) and LV + T composed into precomposed syllables.
  @visibleForTesting
  static String composeHangul(String s) {
    const sBase = 0xAC00, lBase = 0x1100, vBase = 0x1161, tBase = 0x11A7;
    const lCount = 19, vCount = 21, tCount = 28, nCount = vCount * tCount;
    final out = StringBuffer();
    final units = s.runes.toList();
    var i = 0;
    while (i < units.length) {
      final c = units[i];
      if (c >= lBase &&
          c < lBase + lCount &&
          i + 1 < units.length &&
          units[i + 1] >= vBase &&
          units[i + 1] < vBase + vCount) {
        var syllable =
            sBase + ((c - lBase) * vCount + (units[i + 1] - vBase)) * tCount;
        i += 2;
        if (i < units.length && units[i] > tBase && units[i] < tBase + tCount) {
          syllable += units[i] - tBase;
          i++;
        }
        out.writeCharCode(syllable);
        continue;
      }
      if (c >= sBase &&
          c < sBase + lCount * nCount &&
          (c - sBase) % tCount == 0 &&
          i + 1 < units.length &&
          units[i + 1] > tBase &&
          units[i + 1] < tBase + tCount) {
        out.writeCharCode(c + units[i + 1] - tBase);
        i += 2;
        continue;
      }
      out.writeCharCode(c);
      i++;
    }
    return out.toString();
  }
}
