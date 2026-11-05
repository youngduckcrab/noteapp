/// A small Dart tokenizer used by the workspace checks.
///
/// It is not a full Dart lexer: it only has to tell comments, string literals,
/// identifiers and punctuation apart well enough for the directive scanner
/// (`dart_imports.dart`) and the R15 tag scanner (`test_tags.dart`). Comments
/// are dropped, so commented-out code is never reported.
library;

/// The kind of a [DartToken].
enum DartTokenKind {
  /// An identifier or keyword (`import`, `tags`, `Tags`, `const` ...).
  identifier,

  /// A string literal. [DartToken.value] holds its text when the literal has
  /// no interpolation.
  string,

  /// A number literal.
  number,

  /// Any other single character (`@`, `(`, `[`, `,`, `:`, `;` ...).
  punctuation,
}

/// One token of a Dart source file.
final class DartToken {
  const DartToken(this.kind, this.lexeme, this.offset, {this.value});

  final DartTokenKind kind;

  /// The token text as written in the source.
  final String lexeme;

  /// Offset of the first character in the source.
  final int offset;

  /// For [DartTokenKind.string]: the literal value, or `null` when the
  /// literal contains an interpolation (`$x`, `${...}`) and is therefore not
  /// a plain literal.
  final String? value;

  bool isIdentifier(String name) =>
      kind == DartTokenKind.identifier && lexeme == name;

  bool isPunctuation(String char) =>
      kind == DartTokenKind.punctuation && lexeme == char;

  @override
  String toString() => '$kind($lexeme @$offset)';
}

/// Maps source offsets to 1-based line numbers.
final class LineIndex {
  LineIndex(String source) : _lineStarts = _computeLineStarts(source);

  final List<int> _lineStarts;

  static List<int> _computeLineStarts(String source) {
    final starts = <int>[0];
    for (var i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == 0x0A) starts.add(i + 1);
    }
    return starts;
  }

  /// The 1-based line that contains [offset].
  int lineOf(int offset) {
    var low = 0;
    var high = _lineStarts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_lineStarts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low + 1;
  }
}

/// Splits [source] into tokens, dropping whitespace and comments.
///
/// Unterminated strings or comments end at the end of the input instead of
/// throwing: the checks must keep working on files that do not compile.
List<DartToken> tokenizeDart(String source) => _Lexer(source).tokenize();

final class _Lexer {
  _Lexer(this._s);

  final String _s;
  int _i = 0;

  List<DartToken> tokenize() {
    final tokens = <DartToken>[];
    while (true) {
      final token = _next();
      if (token == null) return tokens;
      tokens.add(token);
    }
  }

  /// Returns the next token, or `null` at the end of the input.
  DartToken? _next() {
    _skipTrivia();
    if (_i >= _s.length) return null;
    final start = _i;
    final c = _s[_i];
    if (_isIdentifierStart(c)) {
      // Raw string prefix: r'...' / r"..."
      if (c == 'r' && _i + 1 < _s.length && _isQuote(_s[_i + 1])) {
        _i++;
        return _string(start, raw: true);
      }
      while (_i < _s.length && _isIdentifierPart(_s[_i])) {
        _i++;
      }
      return DartToken(
        DartTokenKind.identifier,
        _s.substring(start, _i),
        start,
      );
    }
    if (_isDigit(c)) {
      while (_i < _s.length &&
          (_isIdentifierPart(_s[_i]) ||
              (_s[_i] == '.' && _i + 1 < _s.length && _isDigit(_s[_i + 1])))) {
        _i++;
      }
      return DartToken(DartTokenKind.number, _s.substring(start, _i), start);
    }
    if (_isQuote(c)) return _string(start, raw: false);
    _i++;
    return DartToken(DartTokenKind.punctuation, c, start);
  }

  void _skipTrivia() {
    while (_i < _s.length) {
      final c = _s[_i];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f') {
        _i++;
      } else if (_s.startsWith('//', _i)) {
        final end = _s.indexOf('\n', _i);
        _i = end < 0 ? _s.length : end + 1;
      } else if (_s.startsWith('/*', _i)) {
        _skipBlockComment();
      } else if (c == '﻿') {
        _i++;
      } else {
        return;
      }
    }
  }

  void _skipBlockComment() {
    // Dart block comments nest.
    var depth = 0;
    while (_i < _s.length) {
      if (_s.startsWith('/*', _i)) {
        depth++;
        _i += 2;
      } else if (_s.startsWith('*/', _i)) {
        depth--;
        _i += 2;
        if (depth == 0) return;
      } else {
        _i++;
      }
    }
  }

  DartToken _string(int start, {required bool raw}) {
    final quote = _s[_i];
    final triple = _s.startsWith(quote * 3, _i);
    final delimiter = triple ? quote * 3 : quote;
    _i += delimiter.length;
    final buffer = StringBuffer();
    var interpolated = false;
    while (_i < _s.length) {
      if (_s.startsWith(delimiter, _i)) {
        _i += delimiter.length;
        break;
      }
      final c = _s[_i];
      if (!triple && c == '\n') break; // unterminated single-line string
      if (!raw && c == r'\') {
        if (_i + 1 < _s.length) buffer.write(_escaped(_s[_i + 1]));
        _i += 2;
        continue;
      }
      if (!raw && c == r'$') {
        interpolated = true;
        _i++;
        if (_i < _s.length && _s[_i] == '{') {
          _i++;
          _skipInterpolation();
        } else {
          while (_i < _s.length && _isIdentifierPart(_s[_i])) {
            _i++;
          }
        }
        continue;
      }
      buffer.write(c);
      _i++;
    }
    return DartToken(
      DartTokenKind.string,
      _s.substring(start, _i > _s.length ? _s.length : _i),
      start,
      value: interpolated ? null : buffer.toString(),
    );
  }

  /// Skips `${ ... }` (the `${` is already consumed), including nested
  /// braces, strings and comments.
  void _skipInterpolation() {
    var depth = 1;
    while (depth > 0) {
      final token = _next();
      if (token == null) return;
      if (token.isPunctuation('{')) depth++;
      if (token.isPunctuation('}')) depth--;
    }
  }

  static String _escaped(String c) => switch (c) {
    'n' => '\n',
    't' => '\t',
    'r' => '\r',
    _ => c,
  };

  static bool _isQuote(String c) => c == "'" || c == '"';

  static bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 0x30 && u <= 0x39;
  }

  static bool _isIdentifierStart(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5A) || // A-Z
        (u >= 0x61 && u <= 0x7A) || // a-z
        u == 0x5F || // _
        u == 0x24; // $
  }

  static bool _isIdentifierPart(String c) =>
      _isIdentifierStart(c) || _isDigit(c);
}
