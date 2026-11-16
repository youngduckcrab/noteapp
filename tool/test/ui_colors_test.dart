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

final RegExp _pattern = RegExp(
  r'Color\(0x[0-9A-Fa-f]+\)|\bColors\.(?!transparent\b)[a-z]\w*',
);

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
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final code = line.contains('//')
              ? line.substring(0, line.indexOf('//'))
              : line;
          for (final m in _pattern.allMatches(code)) {
            (found[rel] ??= []).add('${i + 1}: ${m.group(0)}');
          }
        }
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
      final code = [
        for (final line in f.readAsLinesSync())
          line.contains('//') ? line.substring(0, line.indexOf('//')) : line,
      ].join('\n');
      expect(
        _pattern.allMatches(code).length,
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
}
