/// Source-text reader of the public names an entry point of sync_engine exports
/// (07-sync 4.0, T14 `api_surface_test.dart`). package:analyzer is not a dependency, so it
/// reads the dart-formatted source: top-level declarations start at column 0.
///
/// [publicSurface] follows `export` directives (with `show` / `hide`) from the entry point
/// through every exported file under `lib/`, and collects the public top-level names each
/// file declares: classes, mixins, enums, extension types, named extensions, typedefs,
/// top-level variables, functions and getters. An export of another package is reported as
/// `package:…` so a re-export of CORE is visible.
library;

import 'dart:io';

final RegExp _export = RegExp(
  r'''^export\s+'([^']+)'((?:\s+(?:show|hide)\s+[\w\s,]+)*)\s*;''',
  multiLine: true,
);
final RegExp _combinator = RegExp(
  r'(show|hide)\s+([\w\s,]+?)(?=\s+(?:show|hide)\b|$)',
);

final List<RegExp> _declarations = [
  // class / mixin / enum / extension type / typedef, with any modifiers.
  RegExp(
    r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
    r'(?:class|mixin|enum|typedef|extension\s+type)\s+(\w+)',
  ),
  // Named extension.
  RegExp(r'^extension\s+(?!on\b)(\w+)'),
  // Top-level variable.
  RegExp(r'^(?:late\s+)?(?:final|const|var)\s+(?:[\w<>?,. ]+\s+)?(\w+)\s*=?'),
  // Top-level getter.
  RegExp(r'^[\w<>?,. ]+\s+get\s+(\w+)'),
  // Top-level function (also generic).
  RegExp(r'^(?!return\b)[\w<>?,. ]+\s+(\w+)\s*[<(]'),
];

/// Public top-level names declared in [source] (not following exports).
Set<String> declaredNames(String source) {
  final names = <String>{};
  for (final line in source.split('\n')) {
    if (line.isEmpty || line.startsWith(' ') || line.startsWith('}')) continue;
    if (line.startsWith('//') || line.startsWith('@')) continue;
    if (RegExp(r'^(import|export|part|library)\b').hasMatch(line)) continue;
    for (final pattern in _declarations) {
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      final name = match.group(1)!;
      if (!name.startsWith('_')) names.add(name);
      break;
    }
  }
  return names;
}

/// Public names visible through `lib/<entryPoint>` (paths relative to the package root).
Set<String> publicSurface(String entryPoint, {String libDir = 'lib'}) =>
    _surface('$libDir/$entryPoint', <String>{});

Set<String> _surface(String path, Set<String> visiting) {
  final file = File(path);
  if (!visiting.add(file.absolute.path)) return const {};
  final source = file.readAsStringSync();
  final names = declaredNames(source);
  for (final match in _export.allMatches(source)) {
    final uri = match.group(1)!;
    final Set<String> exported;
    if (uri.startsWith('package:sync_engine/')) {
      exported = _surface(
        'lib/${uri.substring('package:sync_engine/'.length)}',
        visiting,
      );
    } else if (uri.startsWith('package:') || uri.startsWith('dart:')) {
      exported = {uri};
    } else {
      exported = _surface(
        File(path).parent.uri.resolve(uri).toFilePath(),
        visiting,
      );
    }
    names.addAll(_applyCombinators(exported, match.group(2) ?? ''));
  }
  visiting.remove(file.absolute.path);
  return names;
}

Set<String> _applyCombinators(Set<String> names, String combinators) {
  var out = names;
  for (final m in _combinator.allMatches(combinators.trim())) {
    final listed = {for (final n in m.group(2)!.split(',')) n.trim()}
      ..remove('');
    out = m.group(1) == 'show'
        ? out.intersection(listed)
        : out.difference(listed);
  }
  return out;
}
