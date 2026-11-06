/// Static check of the app shell's two native storage paths
/// (docs/plans/m5-7/01-infra.md 6.9 'app shell static test', J4; contract
/// 00-overview 7.2.6 v2.1 — CORE review S-11 · X-6). The 1st-round shell
/// passed no native path, so the 1st-round APK could not keep notes; this
/// check makes the container tests fail first when the shell drops a path
/// again.
///
/// The Dart files are read as a token list ([dartTokens] — comments dropped,
/// string literals one token each), so formatting and comments never matter.
/// `tool/test/native_config_test.dart` runs [appShellStoragePathProblems] on
/// the committed files and breaks every rule once.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Repo-relative paths of the files [AppShellStorageSources.load] reads.
abstract final class AppShellStoragePaths {
  static const String libDir = 'app/lib';
  static const String barrel = 'app/lib/src/storage/native_storage_paths.dart';
  static const String nativeFile =
      'app/lib/src/storage/native_storage_paths_native.dart';
  static const String stubFile =
      'app/lib/src/storage/native_storage_paths_stub.dart';
  static const String coreModule = 'app/lib/src/modules/core_module.dart';
  static const String productionModules =
      'app/lib/src/modules/production_modules.dart';
}

/// The app's `lib/` Dart files by repo-relative path (`/` separators).
final class AppShellStorageSources {
  const AppShellStorageSources(this.files);

  /// Reads every `.dart` file under `app/lib/` of [repoRoot].
  factory AppShellStorageSources.load(String repoRoot) {
    final lib = Directory(p.join(repoRoot, AppShellStoragePaths.libDir));
    final files = <String, String>{};
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = p.posix.joinAll(
        p.split(p.relative(entity.path, from: repoRoot)),
      );
      files[relative] = entity.readAsStringSync();
    }
    return AppShellStorageSources(files);
  }

  final Map<String, String> files;

  /// A copy with [path]'s text replaced (null removes the file).
  AppShellStorageSources withFile(String path, String? text) =>
      AppShellStorageSources({
        for (final MapEntry(:key, :value) in files.entries)
          if (key != path) key: value,
        path: ?text,
      });
}

/// Dart source as tokens: identifiers and keywords, numbers, string literals
/// (one token each, normalized to `'<content>'` — raw and triple-quoted
/// forms too; interpolation is kept as text), and punctuation (`?.`, `??`,
/// `??=`, `=>`, `==`, `!=`, `<=`, `>=`, `...`, `..`, `&&`, `||` as one
/// token, everything else one character). Line and block comments (nested)
/// are dropped.
List<String> dartTokens(String source) {
  final tokens = <String>[];
  var i = 0;
  final n = source.length;
  bool at(String s) => source.startsWith(s, i);
  while (i < n) {
    final c = source[i];
    if (c == ' ' || c == '\n' || c == '\r' || c == '\t') {
      i++;
    } else if (at('//')) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? n : end + 1;
    } else if (at('/*')) {
      var depth = 0;
      while (i < n) {
        if (at('/*')) {
          depth++;
          i += 2;
        } else if (at('*/')) {
          depth--;
          i += 2;
          if (depth == 0) break;
        } else {
          i++;
        }
      }
    } else if (c == "'" ||
        c == '"' ||
        (c == 'r' &&
            i + 1 < n &&
            (source[i + 1] == "'" || source[i + 1] == '"'))) {
      final raw = c == 'r';
      if (raw) i++;
      final quote = source[i];
      final triple = at(quote * 3);
      final close = triple ? quote * 3 : quote;
      i += close.length;
      final buffer = StringBuffer();
      while (i < n && !at(close)) {
        if (!raw && source[i] == r'\' && i + 1 < n) {
          buffer.write(source.substring(i, i + 2));
          i += 2;
        } else {
          buffer.write(source[i]);
          i++;
        }
      }
      i += close.length;
      tokens.add("'$buffer'");
    } else if (_isIdentifierStart(c)) {
      final start = i;
      while (i < n && _isIdentifierPart(source[i])) {
        i++;
      }
      tokens.add(source.substring(start, i));
    } else if (_isDigit(c)) {
      final start = i;
      while (i < n && (_isIdentifierPart(source[i]) || source[i] == '.')) {
        i++;
      }
      tokens.add(source.substring(start, i));
    } else {
      final op = _operators.firstWhere(at, orElse: () => c);
      tokens.add(op);
      i += op.length;
    }
  }
  return tokens;
}

const List<String> _operators = [
  '??=',
  '...',
  '?.',
  '??',
  '=>',
  '==',
  '!=',
  '<=',
  '>=',
  '..',
  '&&',
  '||',
];

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

bool _isIdentifierStart(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 0x41 && u <= 0x5a) ||
      (u >= 0x61 && u <= 0x7a) ||
      c == '_' ||
      c == r'$';
}

bool _isIdentifierPart(String c) => _isIdentifierStart(c) || _isDigit(c);

/// Index of the first occurrence of [pattern] in [tokens] at or after
/// [from], or -1.
int indexOfTokens(List<String> tokens, List<String> pattern, [int from = 0]) {
  outer:
  for (var i = from; i + pattern.length <= tokens.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (tokens[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Number of occurrences of [pattern] in [tokens].
int countTokens(List<String> tokens, List<String> pattern) {
  var count = 0;
  var i = indexOfTokens(tokens, pattern);
  while (i >= 0) {
    count++;
    i = indexOfTokens(tokens, pattern, i + pattern.length);
  }
  return count;
}

/// The tokens of the `{ … }` or `=> … ;` body of the function whose name is
/// at [name] (its parameter list is skipped, braces of named parameters
/// included), without the braces / arrow / semicolon. Null when there is
/// none.
List<String>? _bodyAfter(List<String> tokens, int name) {
  final open = tokens.indexOf('(', name);
  if (open < 0) return null;
  final start = open + _parenthesized(tokens, open).length + 2;
  for (var i = start; i < tokens.length; i++) {
    if (tokens[i] == '{') {
      var depth = 0;
      for (var j = i; j < tokens.length; j++) {
        if (tokens[j] == '{') depth++;
        if (tokens[j] == '}') depth--;
        if (depth == 0) return tokens.sublist(i + 1, j);
      }
      return null;
    }
    if (tokens[i] == '=>') {
      var depth = 0;
      for (var j = i + 1; j < tokens.length; j++) {
        if (const {'(', '[', '{'}.contains(tokens[j])) depth++;
        if (const {')', ']', '}'}.contains(tokens[j])) depth--;
        if (depth == 0 && tokens[j] == ';') return tokens.sublist(i + 1, j);
      }
      return null;
    }
  }
  return null;
}

/// The tokens between the parentheses that open at [open] (exclusive).
List<String> _parenthesized(List<String> tokens, int open) {
  var depth = 0;
  for (var j = open; j < tokens.length; j++) {
    if (tokens[j] == '(') depth++;
    if (tokens[j] == ')') depth--;
    if (depth == 0) return tokens.sublist(open + 1, j);
  }
  return tokens.sublist(open + 1);
}

bool _isImportOf(List<String> tokens, int i, String prefix) =>
    (tokens[i] == 'import' || tokens[i] == 'export') &&
    i + 1 < tokens.length &&
    tokens[i + 1].startsWith("'$prefix");

/// One line per broken rule (empty = the shell passes both paths):
///
/// 1. `native_storage_paths.dart` exports `native_storage_paths_stub.dart`
///    `if (dart.library.io) 'native_storage_paths_native.dart'` `show
///    resolveNativeStoragePaths` (the stub and the native file both define
///    it).
/// 2. Only `native_storage_paths_native.dart` imports `package:path_provider/`
///    in `app/lib`, and no other `lib/` file names the native file (it is
///    reached through the conditional export only).
/// 3. `defaultNoteStoreConfig` sets `nativeDatabasePath:` and
///    `nativeAssetDirectoryPath:` exactly once each, from the `databasePath`
///    and `assetDirectoryPath` of ONE local variable that is
///    `context.maybe<NativeStoragePaths>()`.
/// 4. `CoreModule`'s constructor defaults are `nativePaths =
///    resolveNativeStoragePaths` and `configFor = defaultNoteStoreConfig`.
/// 5. `productionModules()` and `modulesFor()` construct `CoreModule()` with
///    no argument (the defaults above).
List<String> appShellStoragePathProblems(AppShellStorageSources sources) {
  final problems = <String>[];
  List<String>? tokensOf(String path) {
    final text = sources.files[path];
    if (text == null) {
      problems.add('$path: missing');
      return null;
    }
    return dartTokens(text);
  }

  // 1. The conditional export.
  if (tokensOf(AppShellStoragePaths.barrel) case final barrel?) {
    const conditional = [
      'export',
      "'native_storage_paths_stub.dart'",
      'if',
      '(',
      'dart',
      '.',
      'library',
      '.',
      'io',
      ')',
      "'native_storage_paths_native.dart'",
      'show',
      'resolveNativeStoragePaths',
    ];
    if (indexOfTokens(barrel, conditional) < 0) {
      problems.add(
        '${AppShellStoragePaths.barrel}: must export '
        "'native_storage_paths_stub.dart' if (dart.library.io) "
        "'native_storage_paths_native.dart' show resolveNativeStoragePaths",
      );
    }
  }
  for (final path in [
    AppShellStoragePaths.stubFile,
    AppShellStoragePaths.nativeFile,
  ]) {
    final tokens = tokensOf(path);
    if (tokens == null) continue;
    const head = [
      'Future',
      '<',
      'NativeStoragePaths',
      '?',
      '>',
      'resolveNativeStoragePaths',
      '(',
      ')',
    ];
    if (indexOfTokens(tokens, head) < 0) {
      problems.add(
        '$path: must define Future<NativeStoragePaths?> '
        'resolveNativeStoragePaths()',
      );
    }
  }

  // 2. path_provider only in the native file; the native file only through
  // the conditional export.
  final paths = sources.files.keys.toList()..sort();
  for (final path in paths) {
    final tokens = dartTokens(sources.files[path]!);
    for (var i = 0; i < tokens.length; i++) {
      if (_isImportOf(tokens, i, 'package:path_provider/') &&
          path != AppShellStoragePaths.nativeFile) {
        problems.add(
          '$path: imports package:path_provider/ — only '
          '${p.posix.basename(AppShellStoragePaths.nativeFile)} may',
        );
      }
      if ((tokens[i] == 'import' || tokens[i] == 'export') &&
          i + 1 < tokens.length &&
          tokens[i + 1].endsWith("native_storage_paths_native.dart'") &&
          path != AppShellStoragePaths.barrel) {
        problems.add(
          '$path: names native_storage_paths_native.dart — use '
          'native_storage_paths.dart (conditional export)',
        );
      }
    }
  }
  if (sources.files[AppShellStoragePaths.nativeFile] case final native?) {
    final tokens = dartTokens(native);
    final imports = [
      for (var i = 0; i < tokens.length; i++)
        if (_isImportOf(tokens, i, 'package:path_provider/')) i,
    ];
    if (imports.isEmpty) {
      problems.add(
        '${AppShellStoragePaths.nativeFile}: must import '
        'package:path_provider/ (getApplicationSupportDirectory)',
      );
    }
  }

  // 3. and 4. CoreModule and defaultNoteStoreConfig.
  if (tokensOf(AppShellStoragePaths.coreModule) case final core?) {
    problems.addAll(_defaultConfigProblems(core));
    for (final (field, value, name) in const [
      ('_nativePaths', 'resolveNativeStoragePaths', 'nativePaths'),
      ('_configFor', 'defaultNoteStoreConfig', 'configFor'),
    ]) {
      if (indexOfTokens(core, ['this', '.', field, '=', value]) < 0) {
        problems.add(
          '${AppShellStoragePaths.coreModule}: CoreModule($name:) must '
          'default to $value',
        );
      }
    }
  }

  // 5. The production lists use the defaults.
  if (tokensOf(AppShellStoragePaths.productionModules) case final modules?) {
    for (final function in ['productionModules', 'modulesFor']) {
      final head = indexOfTokens(modules, [function, '(']);
      final body = head < 0 ? null : _bodyAfter(modules, head);
      if (body == null) {
        problems.add(
          '${AppShellStoragePaths.productionModules}: $function() not found',
        );
        continue;
      }
      final uses = [
        for (var i = 0; i < body.length; i++)
          if (body[i] == 'CoreModule' &&
              i + 1 < body.length &&
              body[i + 1] == '(')
            _parenthesized(body, i + 1),
      ];
      if (uses.isEmpty || uses.any((arguments) => arguments.isNotEmpty)) {
        problems.add(
          '${AppShellStoragePaths.productionModules}: $function() must '
          'construct CoreModule() with no argument (default nativePaths and '
          'configFor)',
        );
      }
    }
  }
  return problems;
}

List<String> _defaultConfigProblems(List<String> core) {
  const where = '${AppShellStoragePaths.coreModule}: defaultNoteStoreConfig';
  final head = indexOfTokens(core, [
    'NoteStoreConfig',
    'defaultNoteStoreConfig',
    '(',
  ]);
  final body = head < 0 ? null : _bodyAfter(core, head);
  if (body == null) return ['$where not found'];
  final problems = <String>[];
  // `final|var <name> = context.maybe<NativeStoragePaths>();`
  final variables = <String>{
    for (var i = 1; i + 9 < body.length; i++)
      if (body[i + 1] == '=' &&
          indexOfTokens(body.sublist(i + 2, i + 10), const [
                'context',
                '.',
                'maybe',
                '<',
                'NativeStoragePaths',
                '>',
                '(',
                ')',
              ]) ==
              0)
        body[i],
  };
  final sources = <String, String?>{};
  for (final (field, property) in const [
    ('nativeDatabasePath', 'databasePath'),
    ('nativeAssetDirectoryPath', 'assetDirectoryPath'),
  ]) {
    final count = countTokens(body, [field, ':']);
    if (count != 1) {
      problems.add('$where: $field: must be set exactly once (found $count)');
      continue;
    }
    final at = indexOfTokens(body, [field, ':']) + 2;
    final value = at + 3 <= body.length ? body.sublist(at, at + 3) : <String>[];
    final ok =
        value.length == 3 &&
        variables.contains(value[0]) &&
        (value[1] == '?.' || value[1] == '.') &&
        value[2] == property;
    if (!ok) {
      problems.add(
        '$where: $field: must be <paths>?.$property with paths = '
        'context.maybe<NativeStoragePaths>()',
      );
    }
    sources[field] = ok ? value[0] : null;
  }
  final names = sources.values.whereType<String>().toSet();
  if (sources.length == 2 &&
      sources.values.every((v) => v != null) &&
      names.length != 1) {
    problems.add(
      '$where: nativeDatabasePath and nativeAssetDirectoryPath must come from '
      'the same NativeStoragePaths value',
    );
  }
  return problems;
}
