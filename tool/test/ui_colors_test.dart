// Hard-coded colours in UI code (docs/plans/m5-7/01-infra.md 14.5, contract
// 00-overview 7.4.11 v2.14-ui). The screen styles and dark mode only reach
// colours that come from the theme (ColorScheme / ui_kit StyleTokens). A
// `Color(0x…)` literal or a `Colors.<name>` constant (other than
// `Colors.transparent`) in the lib/ code of a UI package is allowed only in
// the files below, each for document data (ink, paper, cover, highlight)
// that must not change with the theme, and only as many times as listed.
// ui_kit is the token source and is not scanned.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture_workspace.dart';

/// UI packages whose lib/ is scanned.
const _scanned = [
  'packages/feature_editor/lib',
  'packages/feature_library/lib',
  'packages/ink_recognition/lib',
  'packages/pdf_io/lib',
  'packages/media_io/lib',
  'packages/feature_markdown/lib', // v2.17-md
  'app/lib',
];

/// file → allowed number of matches, with the reason.
const Map<String, (int, String)> _allowed = {
  'packages/feature_editor/lib/src/ui/toolbar/mic_button.dart': (
    1,
    'recording dot: the universal "recording" red in every style',
  ),
  'packages/feature_editor/lib/src/ui/search/note_search_panel.dart': (
    1,
    'search highlight fill (marker yellow on paper)',
  ),
  'packages/feature_library/lib/src/appearance/cover_palette.dart': (
    3,
    'cover title colours and spine shade: printed on the cover colour',
  ),
  'app/lib/src/settings/appearance_section.dart': (
    3,
    'ink lines on the paper of the style preview swatches',
  ),
};

/// Over the whole file (comments stripped by [_code]), so a literal that
/// dart format wrapped (`Color(` / `0xFF…` on the next line) is caught too,
/// as are `Color.fromARGB` / `Color.fromRGBO` / `Color.from` with number
/// literals.
final RegExp _pattern = RegExp(
  r'\bColor\(\s*0x[0-9A-Fa-f]+\s*,?\s*\)'
  r'|\bColor\.from(?:ARGB|RGBO)\(\s*[\d.]'
  r'|\bColor\.from\(\s*alpha:\s*[\d.]'
  r'|\bColors\.(?!transparent\b)[a-z]\w*',
);

/// [source] without `//` and `/* */` comments; string literals are kept
/// (a `://` inside a string does not hide the rest of the line). Newlines
/// are kept, so offsets map to the same line numbers.
String _code(String source) {
  final out = StringBuffer();
  var i = 0;
  final n = source.length;
  while (i < n) {
    final c = source[i];
    final next = i + 1 < n ? source[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < n && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      i += 2;
      while (i < n &&
          !(source[i] == '*' && i + 1 < n && source[i + 1] == '/')) {
        if (source[i] == '\n') out.write('\n');
        i++;
      }
      i += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      final triple = source.startsWith(c * 3, i);
      final quote = triple ? c * 3 : c;
      final raw = i > 0 && source[i - 1] == 'r';
      out.write(quote);
      i += quote.length;
      while (i < n && !source.startsWith(quote, i)) {
        if (!raw && source[i] == '\\' && i + 1 < n) {
          out.write(source.substring(i, i + 2));
          i += 2;
          continue;
        }
        if (!triple && source[i] == '\n') break;
        out.write(source[i]);
        i++;
      }
      if (i < n && source.startsWith(quote, i)) {
        out.write(quote);
        i += quote.length;
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// "line: match" for every hit in [source].
List<String> _hits(String source) {
  final code = _code(source);
  String at(Match m) {
    final line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
    return '$line: ${m.group(0)!.replaceAll(RegExp(r'\s+'), ' ')}';
  }

  return [for (final m in _pattern.allMatches(code)) at(m)];
}

bool _skipped(String path) =>
    path.endsWith('.g.dart') || path.endsWith('.freezed.dart');

void main() {
  test('no new hard-coded colour in UI lib code outside the allowlist', () {
    final found = <String, List<String>>{};
    for (final dir in _scanned) {
      final root = Directory(p.join(repoRoot, dir));
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = p
            .relative(entity.path, from: repoRoot)
            .replaceAll(r'\', '/');
        if (_skipped(rel)) continue;
        final hits = _hits(entity.readAsStringSync());
        if (hits.isNotEmpty) found[rel] = hits;
      }
    }
    final problems = <String>[
      for (final MapEntry(key: file, value: hits) in found.entries)
        if ((_allowed[file]?.$1 ?? 0) < hits.length)
          [
            '$file has ${hits.length} hard-coded colour(s),',
            '${_allowed[file]?.$1 ?? 0} allowed — use the theme',
            '(colorScheme / StyleTokens.of(context)):\n ',
            hits.join('\n  '),
          ].join(' '),
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('the allowlist has no stale entries (each file still needs its '
      'count)', () {
    for (final MapEntry(key: file, value: (count, _)) in _allowed.entries) {
      final f = File(p.join(repoRoot, file));
      expect(f.existsSync(), isTrue, reason: '$file is gone');
      expect(
        _hits(f.readAsStringSync()).length,
        count,
        reason: '$file: lower the allowed count',
      );
    }
  });

  test('the pattern catches literals and named colours, not transparent', () {
    expect(_pattern.hasMatch('color: Color(0xFF112233),'), isTrue);
    expect(_pattern.hasMatch('color: Colors.white,'), isTrue);
    expect(_pattern.hasMatch('color: Colors.black54,'), isTrue);
    expect(_pattern.hasMatch('color: Colors.transparent,'), isFalse);
    expect(_pattern.hasMatch('Color(style.colorArgb)'), isFalse);
  });

  test('(review) wrapped literals, fromARGB / fromRGBO / from, and code '
      'after a `://` string are caught; comments are not', () {
    expect(_hits('final c = Color(\n  0xFF112233,\n);'), [
      '1: Color( 0xFF112233, )',
    ]);
    expect(_hits('final c = Color.fromARGB(255, 1, 2, 3);'), hasLength(1));
    expect(_hits('final c = Color.fromRGBO(1, 2, 3, 1);'), hasLength(1));
    expect(
      _hits('final c = Color.from(alpha: 1, red: 0, green: 0, blue: 0);'),
      hasLength(1),
    );
    expect(_hits('final c = Color.fromARGB(a, r, g, b);'), isEmpty);
    expect(_hits("const url = 'https://x'; final c = Colors.white;"), [
      '1: Colors.white',
    ]);
    expect(
      _hits('// Color(0xFF000000)\n/* Colors.red */\nfinal a = 1;'),
      isEmpty,
    );
    expect(
      _hits("final s = '// not a comment'; final c = Colors.black;"),
      hasLength(1),
    );
    expect(_hits('a;\nb;\nColor(0xFF000000);'), ['3: Color(0xFF000000)']);
  });
}
