/// Source-text checker for the `lib/` boundary rules of sync_engine
/// (07-sync 3.1 '라이브러리 경계 규칙', contract 00-overview 7.1, 7.2.20 v1.1
/// and 7.4.3). Used by `test/no_dart_io_test.dart`.
///
/// It reads source text only (package:analyzer is not a dependency), so its
/// own tests can feed it synthetic files. A small tokenizer drops comments and
/// reads string literals: commented-out directives and directive-like text
/// inside strings are never reported.
library;

/// The public entry points of sync_engine at the top of `lib/` (contract 7.1).
const List<String> kEntryPoints = [
  'sync_engine.dart',
  'testing.dart',
  'firebase.dart',
  'platform.dart',
];

/// Entry points that are pure Dart together with everything they reach
/// (contract 7.1).
const List<String> kPureEntryPoints = ['sync_engine.dart', 'testing.dart'];

/// Entry points used by production code (the app shell at M4).
const List<String> kProductionEntryPoints = [
  'sync_engine.dart',
  'firebase.dart',
  'platform.dart',
];

/// Forbidden everywhere in `lib/` (contract 7.4.3).
const List<String> kForbiddenInLib = [
  'dart:io',
  'dart:ffi',
  'dart:html',
  'dart:js',
  'dart:js_util',
  'package:js/',
];

/// Dev dependencies that `lib/` (testing.dart included) never imports
/// (contract 7.2.20 v1.1, 07-sync 3.1).
const List<String> kDevOnlyPackages = [
  'package:fake_async/',
  'package:test/',
  'package:test_api/',
  'package:matcher/',
  'package:flutter_test/',
];

/// Web-only libraries: only `*_browser.dart` files import them (contract
/// 7.4.3).
const List<String> kWebOnly = [
  'dart:js_interop',
  'dart:js_interop_unsafe',
  'package:web/',
];

/// Never reached from [kPureEntryPoints] (07-sync 3.1: Flutter, Firebase,
/// connectivity_plus, package:web). `package:flutter` also covers
/// flutter_test / flutter_riverpod, `package:firebase_` every Firebase
/// plugin and its mocks.
const List<String> kNotInPureClosure = [
  'dart:ui',
  'package:flutter',
  'package:firebase_',
  'package:cloud_firestore',
  'package:fake_cloud_firestore',
  'package:connectivity_plus',
  'package:web/',
];

/// The rule a [BoundaryViolation] breaks.
enum BoundaryRule {
  /// `lib/` top level holds exactly [kEntryPoints] (contract 7.1).
  entryPoints,

  /// [kForbiddenInLib] imported in `lib/`.
  forbiddenImport,

  /// [kDevOnlyPackages] imported in `lib/`.
  devOnlyImport,

  /// [kWebOnly] imported outside a `*_browser.dart` file.
  webOnlyImport,

  /// A platform file (`*_browser.dart`, `*_native.dart`, `*_io.dart`) not
  /// loaded through the contract's conditional form, or a conditional URI
  /// that does not match its condition (contract 7.4.3).
  conditionalForm,

  /// A test-only entry point (`testing.dart`, `testing_vm.dart` of any
  /// package) used from `lib/`, or `src/testing/` reached from a production
  /// entry point (contract 7.1 rule 2).
  testOnlyEntry,

  /// Another package's `src/` imported (contract 7.1 rule 2).
  otherPackageSrc,

  /// [kNotInPureClosure] reached from a [kPureEntryPoints] file (contract
  /// 7.1).
  pureClosure,

  /// An in-package URI that does not resolve to a file under `lib/`.
  unresolved,
}

/// One broken rule.
final class BoundaryViolation {
  const BoundaryViolation(this.rule, this.file, this.line, this.message);

  final BoundaryRule rule;

  /// Path relative to `lib/`, with `/` separators.
  final String file;

  /// 1-based line, or 0 when the violation is not tied to a line.
  final int line;

  final String message;

  @override
  String toString() => '${rule.name}: lib/$file:$line: $message';
}

/// `import`, `export` or `part` (not `part of`).
enum DirectiveKind { import, export, part }

/// One `if (<condition>) '<uri>'` clause.
final class ConditionalUri {
  const ConditionalUri(this.condition, this.uri);

  /// The condition as written, without whitespace and comments
  /// (`dart.library.js_interop`, `dart.library.io=='true'`).
  final String condition;

  final String uri;
}

/// One import / export / part directive.
final class DartDirective {
  const DartDirective(this.kind, this.uri, this.line, this.conditionals);

  final DirectiveKind kind;

  /// The default URI (before any `if` clause).
  final String uri;

  /// 1-based line of the keyword.
  final int line;

  final List<ConditionalUri> conditionals;

  /// The default URI followed by every conditional URI.
  Iterable<String> get allUris => [uri, for (final c in conditionals) c.uri];
}

/// The import, export and part directives of [source], in source order.
///
/// Directives whose URI has an interpolation are skipped (not valid Dart).
List<DartDirective> scanDirectives(String source) {
  final tokens = _Lexer(source).tokenize();
  final directives = <DartDirective>[];
  var i = 0;
  while (i < tokens.length) {
    final keyword = tokens[i];
    final kind = keyword.kind != _Kind.word
        ? null
        : switch (keyword.text) {
            'import' => DirectiveKind.import,
            'export' => DirectiveKind.export,
            'part' => DirectiveKind.part,
            _ => null,
          };
    if (kind == null || (i > 0 && tokens[i - 1].isChar('.'))) {
      i++;
      continue;
    }
    final (uri, afterUri) = _readUri(tokens, i + 1);
    if (uri == null) {
      i++;
      continue;
    }
    final conditionals = <ConditionalUri>[];
    var j = afterUri;
    while (j + 1 < tokens.length &&
        tokens[j].isWord('if') &&
        tokens[j + 1].isChar('(')) {
      final condition = StringBuffer();
      var k = j + 2;
      while (k < tokens.length && !tokens[k].isChar(')')) {
        condition.write(tokens[k].text);
        k++;
      }
      final (conditionalUri, next) = _readUri(tokens, k + 1);
      if (conditionalUri == null) break;
      conditionals.add(ConditionalUri(condition.toString(), conditionalUri));
      j = next;
    }
    directives.add(
      DartDirective(kind, uri, _lineOf(source, keyword.offset), conditionals),
    );
    i = j;
  }
  return directives;
}

/// Checks the boundary rules on [libFiles] (path relative to `lib/` with `/`
/// separators → source text). Returns every violation; empty = all rules
/// hold.
List<BoundaryViolation> checkLibBoundary(Map<String, String> libFiles) {
  final violations = <BoundaryViolation>[];
  void add(BoundaryRule rule, String file, int line, String message) =>
      violations.add(BoundaryViolation(rule, file, line, message));

  final topLevel = {
    for (final path in libFiles.keys)
      if (!path.contains('/')) path,
  };
  for (final entry in kEntryPoints) {
    if (!topLevel.contains(entry)) {
      add(BoundaryRule.entryPoints, entry, 0, 'entry point is missing');
    }
  }
  for (final path in topLevel.difference(kEntryPoints.toSet())) {
    add(
      BoundaryRule.entryPoints,
      path,
      0,
      'only the entry points ${kEntryPoints.join(', ')} live at the top of '
      'lib/; move it under src/',
    );
  }

  final graph = <String, List<DartDirective>>{
    for (final MapEntry(:key, :value) in libFiles.entries)
      key: scanDirectives(value),
  };

  for (final MapEntry(key: file, value: directives) in graph.entries) {
    final isBrowserFile = file.endsWith('_browser.dart');
    for (final d in directives) {
      for (final uri in d.allUris) {
        for (final f in kForbiddenInLib) {
          if (_hits(uri, f)) {
            add(BoundaryRule.forbiddenImport, file, d.line, '$uri in lib/');
          }
        }
        for (final f in kDevOnlyPackages) {
          if (_hits(uri, f)) {
            add(
              BoundaryRule.devOnlyImport,
              file,
              d.line,
              '$uri is a dev dependency; lib/ never imports it',
            );
          }
        }
        if (!isBrowserFile && kWebOnly.any((w) => _hits(uri, w))) {
          add(
            BoundaryRule.webOnlyImport,
            file,
            d.line,
            '$uri only in *_browser.dart files',
          );
        }
        if (_testOnlyEntry.hasMatch(uri)) {
          add(
            BoundaryRule.testOnlyEntry,
            file,
            d.line,
            '$uri is a test-only entry point',
          );
        }
        final src = _otherSrc.firstMatch(uri);
        if (src != null && src.group(1) != 'sync_engine') {
          add(
            BoundaryRule.otherPackageSrc,
            file,
            d.line,
            '$uri: use the entry points of ${src.group(1)}',
          );
        }
        final target = _resolve(file, uri);
        switch (target) {
          case _Outside():
            add(BoundaryRule.unresolved, file, d.line, '$uri leaves lib/');
          case _InPackage(:final path):
            if (!libFiles.containsKey(path)) {
              add(
                BoundaryRule.unresolved,
                file,
                d.line,
                '$uri → lib/$path does not exist',
              );
            } else if (path == 'testing.dart' && !uri.startsWith('package:')) {
              add(
                BoundaryRule.testOnlyEntry,
                file,
                d.line,
                '$uri is the test-only entry point',
              );
            }
          case _External():
            break;
        }
      }
      _checkConditionalForm(d, file, add);
    }
  }

  for (final entry in kPureEntryPoints) {
    if (!libFiles.containsKey(entry)) continue;
    final via = reachableFiles(libFiles, entry, graph: graph);
    for (final file in via.keys) {
      for (final d in graph[file]!) {
        for (final uri in d.allUris) {
          if (kNotInPureClosure.any((n) => _hits(uri, n))) {
            add(
              BoundaryRule.pureClosure,
              file,
              d.line,
              '$uri reached from the pure entry point $entry '
              '(${_chain(via, file)})',
            );
          }
        }
      }
    }
  }

  for (final entry in kProductionEntryPoints) {
    if (!libFiles.containsKey(entry)) continue;
    final via = reachableFiles(libFiles, entry, graph: graph);
    for (final file in via.keys) {
      if (file == 'testing.dart' || file.startsWith('src/testing/')) {
        add(
          BoundaryRule.testOnlyEntry,
          file,
          0,
          'test helper reached from the production entry point $entry '
          '(${_chain(via, file)})',
        );
      }
    }
  }
  return violations;
}

/// The files of [libFiles] reached from [entry] through imports, exports and
/// parts (default and conditional URIs), each mapped to the file it was
/// first reached from (`null` for [entry]).
Map<String, String?> reachableFiles(
  Map<String, String> libFiles,
  String entry, {
  Map<String, List<DartDirective>>? graph,
}) {
  List<DartDirective> directivesOf(String file) =>
      graph?[file] ?? scanDirectives(libFiles[file]!);
  final via = <String, String?>{entry: null};
  final queue = [entry];
  while (queue.isNotEmpty) {
    final file = queue.removeLast();
    for (final d in directivesOf(file)) {
      for (final uri in d.allUris) {
        if (_resolve(file, uri) case _InPackage(:final path)
            when libFiles.containsKey(path) && !via.containsKey(path)) {
          via[path] = file;
          queue.add(path);
        }
      }
    }
  }
  return via;
}

void _checkConditionalForm(
  DartDirective d,
  String file,
  void Function(BoundaryRule, String, int, String) add,
) {
  if (_platformFile(d.uri) != null) {
    add(
      BoundaryRule.conditionalForm,
      file,
      d.line,
      '${d.uri} is a platform file; load it only through a conditional '
      "${d.kind.name}: '<x>_stub.dart' "
      "if (dart.library.js_interop) '<x>_browser.dart' "
      "if (dart.library.ffi) '<x>_native.dart'",
    );
  }
  for (final c in d.conditionals) {
    final expected = switch (_platformFile(c.uri)) {
      _Platform.browser => const {'dart.library.js_interop'},
      _Platform.native => const {'dart.library.ffi', 'dart.library.io'},
      null => const <String>{},
    };
    if (!expected.contains(c.condition)) {
      add(
        BoundaryRule.conditionalForm,
        file,
        d.line,
        "if (${c.condition}) '${c.uri}': use "
        "if (dart.library.js_interop) '<x>_browser.dart' or "
        "if (dart.library.ffi) '<x>_native.dart'",
      );
    }
  }
}

enum _Platform { browser, native }

_Platform? _platformFile(String uri) {
  if (uri.endsWith('_browser.dart')) return _Platform.browser;
  if (uri.endsWith('_native.dart') || uri.endsWith('_io.dart')) {
    return _Platform.native;
  }
  return null;
}

final RegExp _testOnlyEntry = RegExp(r'^package:[^/]+/testing(_vm)?\.dart$');
final RegExp _otherSrc = RegExp(r'^package:([^/]+)/src/');

/// `dart:` patterns match exactly (`dart:js` is not `dart:js_interop`), the
/// others are prefixes.
bool _hits(String uri, String pattern) =>
    pattern.startsWith('dart:') ? uri == pattern : uri.startsWith(pattern);

String _chain(Map<String, String?> via, String file) {
  final chain = <String>[file];
  for (var f = via[file]; f != null; f = via[f]) {
    chain.add(f);
  }
  return chain.reversed.join(' → ');
}

sealed class _Target {
  const _Target();
}

final class _InPackage extends _Target {
  const _InPackage(this.path);

  final String path;
}

final class _External extends _Target {
  const _External();
}

final class _Outside extends _Target {
  const _Outside();
}

const String _ownPackage = 'package:sync_engine/';

_Target _resolve(String fromFile, String uri) {
  if (uri.startsWith(_ownPackage)) {
    return _InPackage(uri.substring(_ownPackage.length));
  }
  if (uri.startsWith('dart:') || uri.startsWith('package:')) {
    return const _External();
  }
  final Uri resolved;
  try {
    resolved = Uri.parse('file:///lib/$fromFile').resolve(uri);
  } on FormatException {
    return const _Outside();
  }
  if (resolved.scheme != 'file' || !resolved.path.startsWith('/lib/')) {
    return const _Outside();
  }
  return _InPackage(resolved.path.substring('/lib/'.length));
}

/// Reads one URI (adjacent string literals are concatenated) at [start].
/// Returns `(null, start)` when there is no plain string literal there.
(String?, int) _readUri(List<_Token> tokens, int start) {
  final uri = StringBuffer();
  var i = start;
  while (i < tokens.length && tokens[i].kind == _Kind.string) {
    final value = tokens[i].value;
    if (value == null) return (null, start);
    uri.write(value);
    i++;
  }
  return i == start ? (null, start) : (uri.toString(), i);
}

int _lineOf(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < source.length; i++) {
    if (source.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

enum _Kind { word, string, other }

final class _Token {
  const _Token(this.kind, this.text, this.offset, [this.value]);

  final _Kind kind;

  /// The lexeme as written.
  final String text;

  final int offset;

  /// String literal value; `null` when it has an interpolation.
  final String? value;

  bool isWord(String word) => kind == _Kind.word && text == word;

  bool isChar(String char) => kind == _Kind.other && text == char;
}

/// Splits Dart source into words, string literals and single characters,
/// dropping whitespace and comments. Unterminated strings and comments end at
/// the end of the input (the checker must not throw on broken files).
final class _Lexer {
  _Lexer(this._s);

  final String _s;
  int _i = 0;

  List<_Token> tokenize() => [for (var t = _next(); t != null; t = _next()) t];

  _Token? _next() {
    _skipTrivia();
    if (_i >= _s.length) return null;
    final start = _i;
    final c = _s[_i];
    if (c == 'r' && _i + 1 < _s.length && _isQuote(_s[_i + 1])) {
      _i++;
      return _string(start, raw: true);
    }
    if (_isWordChar(c)) {
      while (_i < _s.length && _isWordChar(_s[_i])) {
        _i++;
      }
      return _Token(_Kind.word, _s.substring(start, _i), start);
    }
    if (_isQuote(c)) return _string(start, raw: false);
    _i++;
    return _Token(_Kind.other, c, start);
  }

  void _skipTrivia() {
    while (_i < _s.length) {
      if (_s.startsWith('//', _i)) {
        final end = _s.indexOf('\n', _i);
        _i = end < 0 ? _s.length : end + 1;
      } else if (_s.startsWith('/*', _i)) {
        var depth = 0;
        while (_i < _s.length) {
          if (_s.startsWith('/*', _i)) {
            depth++;
            _i += 2;
          } else if (_s.startsWith('*/', _i)) {
            depth--;
            _i += 2;
            if (depth == 0) break;
          } else {
            _i++;
          }
        }
      } else if (_s[_i].trim().isEmpty || _s[_i] == '﻿') {
        _i++;
      } else {
        return;
      }
    }
  }

  _Token _string(int start, {required bool raw}) {
    final quote = _s[_i];
    final delimiter = _s.startsWith(quote * 3, _i) ? quote * 3 : quote;
    _i += delimiter.length;
    final value = StringBuffer();
    var interpolated = false;
    while (_i < _s.length) {
      if (_s.startsWith(delimiter, _i)) {
        _i += delimiter.length;
        break;
      }
      final c = _s[_i];
      if (delimiter.length == 1 && c == '\n') break;
      if (!raw && c == r'\') {
        if (_i + 1 < _s.length) value.write(_s[_i + 1]);
        _i += 2;
      } else if (!raw && c == r'$') {
        interpolated = true;
        _i++;
        if (_i < _s.length && _s[_i] == '{') {
          _i++;
          for (var depth = 1; depth > 0;) {
            final t = _next();
            if (t == null) break;
            if (t.isChar('{')) depth++;
            if (t.isChar('}')) depth--;
          }
        } else {
          while (_i < _s.length && _isWordChar(_s[_i]) && _s[_i] != r'$') {
            _i++;
          }
        }
      } else {
        value.write(c);
        _i++;
      }
    }
    return _Token(
      _Kind.string,
      _s.substring(start, _i),
      start,
      interpolated ? null : value.toString(),
    );
  }

  static bool _isQuote(String c) => c == "'" || c == '"';

  static bool _isWordChar(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x30 && u <= 0x39) || // 0-9
        (u >= 0x41 && u <= 0x5A) || // A-Z
        (u >= 0x61 && u <= 0x7A) || // a-z
        u == 0x5F || // _
        u == 0x24; // $
  }
}
