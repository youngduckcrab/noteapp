// One meaning = one icon (UI stage 2, docs/plans/m5-7/01-infra.md 16). A
// kind of the ui_kit icon table that has line art (`lineArt: true` in
// packages/ui_kit/lib/src/app_icons.dart) is shown through `AppIcon(kind)`
// everywhere — toolbar, menus, dialogs — so a tool looks the same in the
// toolbar and in a menu row. Its `kind.material` (a different picture,
// often a solid one) must not be used in UI lib code.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture_workspace.dart';

/// UI packages whose lib/ is scanned (ui_kit itself defines the table).
const _scanned = [
  'packages/feature_editor/lib',
  'packages/feature_library/lib',
  'packages/ink_recognition/lib',
  'packages/pdf_io/lib',
  'packages/media_io/lib',
  'app/lib',
];

/// The kinds with line art, read from the table's source.
Set<String> _lineArtKinds() {
  final source = File(
    p.join(repoRoot, 'packages/ui_kit/lib/src/app_icons.dart'),
  ).readAsStringSync();
  return {
    for (final m in RegExp(
      r'^\s*(\w+)\(\s*Icons\.\w+,\s*lineArt:\s*true\s*\)',
      multiLine: true,
    ).allMatches(source))
      m.group(1)!,
  };
}

void main() {
  test('the table has the line-art kinds', () {
    final kinds = _lineArtKinds();
    expect(kinds, containsAll(['shape', 'text', 'insert', 'note', 'trash']));
    expect(kinds, isNot(contains('rename')));
  });

  test('no `.material` of a line-art kind in UI lib code (use AppIcon)', () {
    final kinds = _lineArtKinds();
    final pattern = RegExp(r'AppIconKind\s*\.\s*(\w+)\s*\.\s*material\b');
    final problems = <String>[];
    for (final dir in _scanned) {
      final root = Directory(p.join(repoRoot, dir));
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = p
            .relative(entity.path, from: repoRoot)
            .replaceAll(r'\', '/');
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          for (final m in pattern.allMatches(line)) {
            if (kinds.contains(m.group(1))) {
              problems.add('$rel:${i + 1}: ${m.group(0)} — use AppIcon');
            }
          }
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
