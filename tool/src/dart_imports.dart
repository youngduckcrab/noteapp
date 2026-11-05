/// Import / export directive scanner (docs/plans/01-infra.md 6.2).
///
/// Directives are read from the token stream of `dart_tokens.dart`, so
/// directives spread over several lines and conditional clauses
/// (`if (dart.library.js_interop) 'x_browser.dart'`) are handled, and
/// commented-out directives are ignored.
library;

import 'dart_tokens.dart';

/// `import` or `export`.
enum DirectiveKind { import, export }

/// One `if (<test>) '<uri>'` clause of a conditional import / export.
final class ConditionalUri {
  const ConditionalUri(this.condition, this.uri);

  /// The condition as written without spaces, e.g. `dart.library.js_interop`
  /// or `dart.library.io=="true"`.
  final String condition;

  final String uri;

  @override
  String toString() => 'if ($condition) $uri';
}

/// One import or export directive.
final class DartDirective {
  const DartDirective({
    required this.kind,
    required this.uri,
    required this.line,
    this.conditionalUris = const [],
  });

  final DirectiveKind kind;

  /// The default URI (the one before any `if` clause).
  final String uri;

  /// 1-based line of the `import` / `export` keyword.
  final int line;

  final List<ConditionalUri> conditionalUris;

  /// The default URI followed by every conditional URI.
  Iterable<String> get allUris sync* {
    yield uri;
    for (final c in conditionalUris) {
      yield c.uri;
    }
  }

  bool get isConditional => conditionalUris.isNotEmpty;

  @override
  String toString() =>
      '${kind.name} $uri${conditionalUris.map((c) => ' $c').join()} '
      '(line $line)';
}

/// Returns the import and export directives of [source] in source order.
///
/// Directives whose URI contains an interpolation are skipped (they are not
/// valid Dart).
List<DartDirective> scanDirectives(String source) {
  final tokens = tokenizeDart(source);
  final lines = LineIndex(source);
  final directives = <DartDirective>[];
  for (var i = 0; i + 1 < tokens.length; i++) {
    final keyword = tokens[i];
    final DirectiveKind kind;
    if (keyword.isIdentifier('import')) {
      kind = DirectiveKind.import;
    } else if (keyword.isIdentifier('export')) {
      kind = DirectiveKind.export;
    } else {
      continue;
    }
    if (i > 0 && tokens[i - 1].isPunctuation('.')) continue;
    final uriToken = tokens[i + 1];
    if (uriToken.kind != DartTokenKind.string || uriToken.value == null) {
      continue;
    }
    final conditions = <ConditionalUri>[];
    var j = i + 2;
    while (j + 1 < tokens.length &&
        tokens[j].isIdentifier('if') &&
        tokens[j + 1].isPunctuation('(')) {
      final condition = StringBuffer();
      var k = j + 2;
      while (k < tokens.length && !tokens[k].isPunctuation(')')) {
        condition.write(tokens[k].lexeme);
        k++;
      }
      if (k + 1 >= tokens.length) break;
      final conditionalUri = tokens[k + 1];
      if (conditionalUri.kind != DartTokenKind.string ||
          conditionalUri.value == null) {
        break;
      }
      conditions.add(
        ConditionalUri(condition.toString(), conditionalUri.value!),
      );
      j = k + 2;
    }
    directives.add(
      DartDirective(
        kind: kind,
        uri: uriToken.value!,
        line: lines.lineOf(keyword.offset),
        conditionalUris: List.unmodifiable(conditions),
      ),
    );
    i = j - 1;
  }
  return directives;
}
