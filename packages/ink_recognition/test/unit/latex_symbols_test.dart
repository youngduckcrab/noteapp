// (math pen, phase 1 — docs/plans/m5-7/research/math-pen-phase1.md 12) The
// LaTeX editor's symbol row: every symbol the brief asks for, the snippet at
// the cursor with the cursor inside its braces, a selection wrapped (분수:
// numerator, cursor in the denominator), no cursor → at the end.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/src/ui/latex_symbols.dart';

LatexSymbol _s(String id) => kLatexSymbols.singleWhere((s) => s.id == id);

TextEditingValue _at(String text, int cursor) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: cursor),
);

void main() {
  test('the brief\'s symbols, in order, labels in Korean where words', () {
    expect(
      [for (final s in kLatexSymbols) s.id],
      [
        'frac', 'pow', 'sub', 'sqrt', 'int', 'sum', 'lim', 'pi', 'infty', //
        'pm', 'times', 'div', 'le', 'ge', 'ne', 'theta', 'alpha', 'beta',
        'paren',
      ],
    );
    expect(
      [for (final s in kLatexSymbols.take(3)) s.label],
      ['분수', '지수', '아래첨자'],
    );
    expect({
      for (final s in kLatexSymbols) s.id: s.snippet,
    }, containsPair('frac', r'\frac{}{}'));
    for (final s in kLatexSymbols) {
      expect(s.caret, inInclusiveRange(0, s.snippet.length), reason: s.id);
    }
  });

  test('braces: the cursor lands inside the first ones', () {
    final cases = {
      'frac': (r'\frac{}{}', r'\frac{'),
      'pow': ('^{}', '^{'),
      'sub': ('_{}', '_{'),
      'sqrt': (r'\sqrt{}', r'\sqrt{'),
      'lim': (r'\lim_{}', r'\lim_{'),
      'paren': ('()', '('),
    };
    for (final MapEntry(key: id, value: (snippet, before)) in cases.entries) {
      final v = insertLatexSymbol(_at('ab', 1), _s(id));
      expect(v.text, 'a${snippet}b', reason: id);
      expect(v.selection.baseOffset, 1 + before.length, reason: id);
      expect(v.selection.isCollapsed, isTrue);
    }
  });

  test('plain symbols: the cursor after the command and its space', () {
    for (final id in [
      'int', 'sum', 'pi', 'infty', 'pm', 'times', 'div', 'le', 'ge', 'ne', //
      'theta', 'alpha', 'beta',
    ]) {
      final s = _s(id);
      final v = insertLatexSymbol(_at('x', 1), s);
      expect(v.text, 'x${s.snippet}', reason: id);
      expect(v.selection.baseOffset, 1 + s.snippet.length, reason: id);
      expect(s.snippet, endsWith(' '), reason: id);
    }
    expect(_s('pi').snippet, r'\pi ');
    expect(_s('ne').snippet, r'\ne ');
  });

  test('a selection goes inside the braces; 분수: then the denominator', () {
    final sel = TextEditingValue(
      text: 'x+1=0',
      selection: const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    final frac = insertLatexSymbol(sel, _s('frac'));
    expect(frac.text, r'\frac{x+1}{}=0');
    expect(frac.selection.baseOffset, r'\frac{x+1}{'.length);
    final pow = insertLatexSymbol(sel, _s('pow'));
    expect(pow.text, '^{x+1}=0');
    expect(pow.selection.baseOffset, '^{x+1}'.length);
    final paren = insertLatexSymbol(sel, _s('paren'));
    expect(paren.text, '(x+1)=0');
    expect(paren.selection.baseOffset, '(x+1)'.length);
    // No braces: the selection is replaced.
    final pi = insertLatexSymbol(sel, _s('pi'));
    expect(pi.text, r'\pi =0');
    expect(pi.selection.baseOffset, r'\pi '.length);
  });

  test('no valid cursor (the field was never focused) → at the end', () {
    const v = TextEditingValue(text: 'x');
    final out = insertLatexSymbol(v, _s('pow'));
    expect(out.text, 'x^{}');
    expect(out.selection.baseOffset, 3);
  });
}
