// lib/src/ui/latex_symbols.dart — (internal, math pen phase 1 —
// docs/plans/m5-7/research/math-pen-phase1.md 12) the symbol row of the
// LaTeX editor: buttons that put a LaTeX snippet at the cursor, the cursor
// inside its braces.
import 'package:flutter/services.dart' show TextEditingValue, TextSelection;
import 'package:meta/meta.dart';

import '../l10n/recognition_strings.dart';

/// One button of the row: [snippet] goes in at the cursor and the cursor
/// lands at [caret] (an offset in [snippet]).
@immutable
final class LatexSymbol {
  const LatexSymbol(this.id, this.label, this.snippet, this.caret);
  final String id;
  final String label;
  final String snippet;
  final int caret;
}

/// The row, in this order (the brief's list: 분수, 지수, 아래첨자, √, ∫, ∑,
/// lim, π, ∞, ±, ×, ÷, ≤, ≥, ≠, θ, α, β, ( )).
const List<LatexSymbol> kLatexSymbols = [
  LatexSymbol('frac', RecognitionStrings.symbolFraction, r'\frac{}{}', 6),
  LatexSymbol('pow', RecognitionStrings.symbolPower, '^{}', 2),
  LatexSymbol('sub', RecognitionStrings.symbolSubscript, '_{}', 2),
  LatexSymbol('sqrt', '√', r'\sqrt{}', 6),
  LatexSymbol('int', '∫', r'\int ', 5),
  LatexSymbol('sum', '∑', r'\sum ', 5),
  LatexSymbol('lim', 'lim', r'\lim_{}', 6),
  LatexSymbol('pi', 'π', r'\pi ', 4),
  LatexSymbol('infty', '∞', r'\infty ', 7),
  LatexSymbol('pm', '±', r'\pm ', 4),
  LatexSymbol('times', '×', r'\times ', 7),
  LatexSymbol('div', '÷', r'\div ', 5),
  LatexSymbol('le', '≤', r'\le ', 4),
  LatexSymbol('ge', '≥', r'\ge ', 4),
  LatexSymbol('ne', '≠', r'\ne ', 4),
  LatexSymbol('theta', 'θ', r'\theta ', 7),
  LatexSymbol('alpha', 'α', r'\alpha ', 7),
  LatexSymbol('beta', 'β', r'\beta ', 6),
  LatexSymbol('paren', '( )', '()', 1),
];

/// [symbol] put into [value] (pure):
/// - no selection: the snippet goes in at the cursor (at the end when the
///   selection is not valid — the field had no cursor yet) and the cursor
///   lands at [LatexSymbol.caret] — inside the first braces;
/// - a selection: when the snippet has braces / parentheses, the selected
///   text goes inside the first ones ('x' + 지수 → '^{x}') and the cursor
///   lands in the next empty braces (분수: the denominator) or after the
///   closing one; a snippet without them replaces the selection.
TextEditingValue insertLatexSymbol(TextEditingValue value, LatexSymbol symbol) {
  final text = value.text;
  final sel = value.selection;
  final valid = sel.isValid && sel.start >= 0 && sel.end <= text.length;
  final start = valid ? sel.start : text.length;
  final end = valid ? sel.end : text.length;
  final selected = text.substring(start, end);
  final snippet = symbol.snippet;
  final open = _firstOpening(snippet);
  final String inserted;
  final int caret;
  if (selected.isEmpty || open < 0) {
    inserted = snippet;
    caret = symbol.caret;
  } else {
    inserted =
        '${snippet.substring(0, open + 1)}$selected'
        '${snippet.substring(open + 1)}';
    final close = open + 1 + selected.length; // the closing bracket
    final next = inserted.indexOf('{}', close + 1);
    caret = next >= 0 ? next + 1 : close + 1;
  }
  return TextEditingValue(
    text: text.replaceRange(start, end, inserted),
    selection: TextSelection.collapsed(offset: start + caret),
  );
}

int _firstOpening(String snippet) {
  final brace = snippet.indexOf('{');
  final paren = snippet.indexOf('(');
  if (brace < 0) return paren;
  if (paren < 0) return brace;
  return brace < paren ? brace : paren;
}
