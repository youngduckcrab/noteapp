// Import rules of feature_editor, checked inside the package before INFRA's
// ws check (04-editor 6.16; contract 7.1 rules 1-2, 7.4.3).
//
// Every .dart file under lib/ and test/ is read; its directive prologue
// (library / import / export / part) is parsed with a comment- and
// string-aware scanner, so text in comments or string literals never counts.
//
// ① package:flutter/material.dart or cupertino.dart (lib and test)
// ② platform libraries in lib/: dart:io, dart:ffi, dart:html, dart:js,
//    dart:js_util, package:js, package:web — and dart:js_interop(_unsafe):
//    EDITOR has no *_browser.dart / *_native.dart files (6.16)
// ③ another package's src/ (lib and test)
// ④ testing.dart / testing_vm.dart entry points in lib/
// ⑤ other feature packages (lib and test — contract 7.1 rule 1), and
//    `.setViewport(` / `.discardPending(` calls in lib/ (only InkPageView
//    calls setViewport; a failed commit uses discardEdit — 6.16 ⑤)
//
// The checker itself is tested on synthetic sources and on a temporary
// package directory with deliberate violations.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ownPackage = 'feature_editor';

const _sdkMaterial = {
  'package:flutter/material.dart',
  'package:flutter/cupertino.dart',
};

const _platformLibraries = {
  'dart:io',
  'dart:ffi',
  'dart:html',
  'dart:js',
  'dart:js_util',
  'dart:js_interop',
  'dart:js_interop_unsafe',
};
const _platformPackages = ['package:js/', 'package:web/'];

const _otherFeaturePackages = ['feature_library', 'pdf_io', 'sync_engine'];

const _forbiddenLibCalls = {'setViewport', 'discardPending'};

void main() {
  test('lib/ and test/ follow the import rules (6.16 ①-⑤)', () {
    final violations = checkPackage(Directory.current);
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the scan covers lib/ and test/', () {
    final files = dartFilesOf(Directory.current).map((f) => f.path).toList();
    expect(files, contains('lib/feature_editor.dart'));
    expect(files, contains('test/unit/no_platform_imports_test.dart'));
    expect(
      files.every((p) => p.startsWith('lib/') || p.startsWith('test/')),
      isTrue,
    );
  });

  group('checker', () {
    test('① SDK Material / Cupertino in lib and test', () {
      for (final path in ['lib/src/a.dart', 'test/a_test.dart']) {
        expect(
          violationsOf(path, "import 'package:flutter/material.dart';"),
          hasLength(1),
        );
        expect(
          violationsOf(path, "export 'package:flutter/cupertino.dart' show X;"),
          hasLength(1),
        );
      }
      expect(
        violationsOf(
          'lib/src/a.dart',
          "import 'package:material_ui/material_ui.dart';\n"
              "import 'package:flutter/widgets.dart';",
        ),
        isEmpty,
      );
    });

    test('② platform libraries in lib only', () {
      for (final uri in [
        'dart:io',
        'dart:html',
        'dart:js_interop',
        'package:web/web.dart',
        'package:js/js.dart',
      ]) {
        expect(
          violationsOf('lib/src/a.dart', "import '$uri';"),
          hasLength(1),
          reason: uri,
        );
        expect(violationsOf('test/a_test.dart', "import '$uri';"), isEmpty);
      }
      expect(violationsOf('lib/src/a.dart', "import 'dart:async';"), isEmpty);
      expect(
        violationsOf('lib/src/a.dart', "import 'dart:ui' as ui;"),
        isEmpty,
      );
    });

    test('② conditional URIs are checked too', () {
      expect(
        violationsOf(
          'lib/src/a.dart',
          "import 'a_stub.dart'\n"
              "    if (dart.library.js_interop) 'a_browser.dart'\n"
              "    if (dart.library.io) 'dart:io';",
        ),
        hasLength(1),
      );
    });

    test("③ another package's src/ in lib and test", () {
      for (final path in ['lib/src/a.dart', 'test/a_test.dart']) {
        expect(
          violationsOf(path, "import 'package:note_core/src/model/note.dart';"),
          hasLength(1),
        );
        expect(
          violationsOf(path, "import 'package:ink_engine/src/x.dart' as x;"),
          hasLength(1),
        );
        expect(
          violationsOf(path, "import 'package:feature_editor/src/a.dart';"),
          isEmpty,
        );
      }
    });

    test('④ testing entry points in lib only', () {
      for (final uri in [
        'package:note_core/testing.dart',
        'package:note_core/testing_vm.dart',
        'package:ink_engine/testing.dart',
      ]) {
        expect(
          violationsOf('lib/src/a.dart', "import '$uri';"),
          hasLength(1),
          reason: uri,
        );
        expect(violationsOf('test/a_test.dart', "import '$uri';"), isEmpty);
      }
      expect(
        violationsOf(
          'lib/src/a.dart',
          "import 'package:note_core/dev_tools.dart';\n"
              "import 'package:ink_engine/dev_tools.dart';",
        ),
        isEmpty,
      );
    });

    test('⑤ other feature packages in lib and test', () {
      for (final package in _otherFeaturePackages) {
        for (final path in ['lib/src/a.dart', 'test/a_test.dart']) {
          expect(
            violationsOf(path, "import 'package:$package/$package.dart';"),
            hasLength(1),
            reason: '$path $package',
          );
        }
      }
    });

    test('⑤ setViewport / discardPending calls in lib only', () {
      const source = '''
void f(dynamic c) {
  c.setViewport(1);
  c
      .discardPending ();
}
''';
      expect(violationsOf('lib/src/a.dart', source), hasLength(2));
      expect(violationsOf('test/a_test.dart', source), isEmpty);
      expect(
        violationsOf('lib/src/a.dart', 'void setViewport() {}\n'),
        isEmpty,
        reason: 'a declaration is not a call',
      );
    });

    test('comments and string literals never count', () {
      const source = r"""
// import 'package:flutter/material.dart';
/* import 'dart:io';
   /* nested */ c.setViewport(1);
*/
/// Calls `controller.setViewport(...)`? No: InkPageView does.
import 'package:material_ui/material_ui.dart';

const a = "import 'dart:io';";
const b = '''
export 'package:note_core/src/x.dart';
c.discardPending();
''';
final c = 'x ${'nested'.length} c.setViewport(';
final d = r'\';
""";
      expect(violationsOf('lib/src/a.dart', source), isEmpty);
    });

    test('directives after annotations and library are read', () {
      const source = '''
@TestOn('vm')
@Tags(['x'])
library;

import 'dart:io';
''';
      expect(violationsOf('lib/src/a.dart', source), hasLength(1));
    });

    test('a directive-looking string after the prologue is code, not a '
        'directive', () {
      const source = '''
import 'dart:async';

void main() {
  print("import 'dart:io';");
}
''';
      expect(violationsOf('lib/src/a.dart', source), isEmpty);
    });

    test('scans a package directory (temporary files)', () {
      final root = Directory.systemTemp.createTempSync('editor_imports_');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/lib/src/bad.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          "import 'dart:io';\nimport 'package:flutter/material.dart';\n",
        );
      File('${root.path}/lib/good.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync("import 'dart:async';\n");
      File('${root.path}/test/x_test.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          "import 'dart:io';\nimport 'package:pdf_io/pdf_io.dart';\n",
        );
      File('${root.path}/tool/ignored.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync("import 'package:flutter/material.dart';\n");

      final violations = checkPackage(root);
      expect(violations, hasLength(3), reason: violations.join('\n'));
      expect(
        violations.where((v) => v.startsWith('lib/src/bad.dart')),
        hasLength(2),
      );
      expect(
        violations.where((v) => v.startsWith('test/x_test.dart')),
        hasLength(1),
      );
    });
  });
}

// ---- checker ---------------------------------------------------------------

/// .dart files under lib/ and test/ of [root], as paths relative to [root]
/// with '/' separators.
List<({String path, File file})> dartFilesOf(Directory root) {
  final rootPath = root.absolute.uri.path;
  return [
    for (final dir in ['lib', 'test'])
      if (Directory('${root.path}/$dir').existsSync())
        for (final entity in Directory(
          '${root.path}/$dir',
        ).listSync(recursive: true, followLinks: false))
          if (entity is File && entity.path.endsWith('.dart'))
            (
              path: entity.absolute.uri.path.substring(rootPath.length),
              file: entity,
            ),
  ]..sort((a, b) => a.path.compareTo(b.path));
}

List<String> checkPackage(Directory root) => [
  for (final f in dartFilesOf(root))
    ...violationsOf(f.path, f.file.readAsStringSync()),
];

/// Rule violations of one file; [path] is relative to the package root.
List<String> violationsOf(String path, String source) {
  final inLib = path.startsWith('lib/');
  final tokens = _Lexer(source).run();
  final out = <String>[];
  for (final uri in _directiveUris(tokens)) {
    if (_sdkMaterial.contains(uri)) {
      out.add('$path: $uri — use package:material_ui (6.16 ①)');
    }
    if (inLib &&
        (_platformLibraries.contains(uri) ||
            _platformPackages.any(uri.startsWith))) {
      out.add('$path: $uri — no platform libraries in lib/ (6.16 ②)');
    }
    if (uri.startsWith('package:')) {
      final segments = uri.substring('package:'.length).split('/');
      final package = segments.first;
      if (package != _ownPackage &&
          segments.length > 1 &&
          segments[1] == 'src') {
        out.add("$path: $uri — another package's src/ (6.16 ③)");
      }
      final file = segments.last;
      if (inLib &&
          segments.length == 2 &&
          (file == 'testing.dart' || file == 'testing_vm.dart')) {
        out.add('$path: $uri — test-only entry point in lib/ (6.16 ④)');
      }
      if (_otherFeaturePackages.contains(package)) {
        out.add(
          '$path: $uri — feature packages never import each other '
          '(contract 7.1 rule 1, 6.16 ⑤)',
        );
      }
    }
  }
  if (inLib) {
    for (var i = 0; i + 2 < tokens.length; i++) {
      if (tokens[i].isSymbol('.') &&
          tokens[i + 1].kind == _Kind.word &&
          _forbiddenLibCalls.contains(tokens[i + 1].text) &&
          tokens[i + 2].isSymbol('(')) {
        out.add('$path: .${tokens[i + 1].text}( call in lib/ (6.16 ⑤)');
      }
    }
  }
  return out;
}

/// URIs (default and conditional) of the import / export directives in the
/// directive prologue: annotations, `library`, `import`, `export` and `part`
/// up to the first declaration.
List<String> _directiveUris(List<_Token> t) {
  final uris = <String>[];
  var k = 0;
  int skipParens(int at) {
    var depth = 0;
    for (var j = at; j < t.length; j++) {
      if (t[j].isSymbol('(')) depth++;
      if (t[j].isSymbol(')') && --depth == 0) return j + 1;
    }
    return t.length;
  }

  while (k < t.length) {
    final tok = t[k];
    if (tok.isSymbol('@')) {
      k++; // annotation: name(.name)* [(arguments)]
      if (k < t.length && t[k].kind == _Kind.word) k++;
      while (k + 1 < t.length &&
          t[k].isSymbol('.') &&
          t[k + 1].kind == _Kind.word) {
        k += 2;
      }
      if (k < t.length && t[k].isSymbol('(')) k = skipParens(k);
      continue;
    }
    if (tok.kind != _Kind.word) break;
    final keyword = tok.text;
    if (keyword != 'library' &&
        keyword != 'import' &&
        keyword != 'export' &&
        keyword != 'part') {
      break;
    }
    var depth = 0;
    k++;
    while (k < t.length && !t[k].isSymbol(';')) {
      if (t[k].isSymbol('(')) depth++;
      if (t[k].isSymbol(')')) depth--;
      // Strings inside `if (...)` conditions are not URIs.
      if ((keyword == 'import' || keyword == 'export') &&
          t[k].kind == _Kind.string &&
          depth == 0) {
        uris.add(t[k].text);
      }
      k++;
    }
    k++; // ';'
  }
  return uris;
}

enum _Kind { word, string, symbol }

final class _Token {
  const _Token(this.kind, this.text);
  final _Kind kind;

  /// The word, the symbol character, or the string body without quotes.
  final String text;

  bool isSymbol(String s) => kind == _Kind.symbol && text == s;

  @override
  String toString() => '$kind($text)';
}

/// A small Dart scanner: words, string literals (single, double, triple,
/// raw, with nested `${...}` interpolation) and one-character symbols.
/// Comments (line, doc and nested block comments) and numbers are skipped.
final class _Lexer {
  _Lexer(this.src);

  final String src;
  int i = 0;
  final List<_Token> tokens = [];

  List<_Token> run() {
    _code(untilClosingBrace: false);
    return tokens;
  }

  static bool _isWordStart(String c) => RegExp(r'[A-Za-z_$]').hasMatch(c);
  static bool _isWordPart(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);

  void _code({required bool untilClosingBrace}) {
    var depth = 0;
    while (i < src.length) {
      final c = src[i];
      if (src.startsWith('//', i)) {
        final end = src.indexOf('\n', i);
        i = end < 0 ? src.length : end + 1;
      } else if (src.startsWith('/*', i)) {
        _blockComment();
      } else if (c == "'" || c == '"') {
        _string(raw: false);
      } else if ((c == 'r' || c == 'R') &&
          i + 1 < src.length &&
          (src[i + 1] == "'" || src[i + 1] == '"')) {
        i++;
        _string(raw: true);
      } else if (_isWordStart(c)) {
        final start = i;
        while (i < src.length && _isWordPart(src[i])) {
          i++;
        }
        tokens.add(_Token(_Kind.word, src.substring(start, i)));
      } else if (RegExp('[0-9]').hasMatch(c)) {
        while (i < src.length && RegExp('[0-9A-Za-z_]').hasMatch(src[i])) {
          i++;
        }
      } else if (c.trim().isEmpty) {
        i++;
      } else {
        if (c == '{') depth++;
        if (c == '}') {
          if (untilClosingBrace && depth == 0) {
            i++;
            return;
          }
          depth--;
        }
        tokens.add(_Token(_Kind.symbol, c));
        i++;
      }
    }
  }

  void _blockComment() {
    var depth = 0;
    while (i < src.length) {
      if (src.startsWith('/*', i)) {
        depth++;
        i += 2;
      } else if (src.startsWith('*/', i)) {
        depth--;
        i += 2;
        if (depth == 0) return;
      } else {
        i++;
      }
    }
  }

  void _string({required bool raw}) {
    final quote = src[i];
    final triple = src.startsWith(quote * 3, i);
    final close = triple ? quote * 3 : quote;
    i += close.length;
    final start = i;
    while (i < src.length) {
      if (src.startsWith(close, i)) {
        tokens.add(_Token(_Kind.string, src.substring(start, i)));
        i += close.length;
        return;
      }
      final c = src[i];
      if (!raw && c == r'\') {
        i += 2;
      } else if (!raw && c == r'$' && src.startsWith(r'${', i)) {
        i += 2;
        _code(untilClosingBrace: true);
      } else if (!triple && c == '\n') {
        break; // unterminated single-line string: stop at the line end
      } else {
        i++;
      }
    }
    tokens.add(_Token(_Kind.string, src.substring(start, i)));
  }
}
