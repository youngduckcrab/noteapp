// The on-device math engine's LaTeX clean-up (ondevice/latex_normalizer.dart):
// the model's corpus style → compact KaTeX that InkMathRenderer renders
// (the canonical forms of the reference evaluation's latex_norm.py, meaning
// kept), the renderer-driven retry, and garbage that never throws.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' show InkMathRenderer;
import 'package:ink_recognition/src/ondevice/latex_normalizer.dart';

import '../support/math_model_fakes.dart';

String _norm(String raw) =>
    normalizeMfrLatex(raw, validate: InkMathRenderer.validate);

void main() {
  const cases = <String, String>{
    // spacing between tokens goes; a command keeps a space before a letter
    // or a digit
    r'2 + 3 = 5': '2+3=5',
    r'\frac { 1 } { n ^ { 2 } }': r'\frac{1}{n^{2}}',
    r'\int \sin x d x = \cos x + C': r'\int\sin xdx=\cos x+C',
    r'\lim _ { x \rightarrow 0 } \frac { \sin x } { x } = 1':
        r'\lim_{x\rightarrow 0}\frac{\sin x}{x}=1',
    // \underset / \overset around a big operator → limits
    r'\underset { n \mathop = 1 } { \overset { \infty } { \sum } } \frac { 1 } { n ^ { 2 } }':
        r'\sum_{n=1}^{\infty}\frac{1}{n^{2}}',
    r'\underset { n \mapsto \infty } { \operatorname* { l i m } } a _ { n }':
        r'\lim_{n\mapsto\infty}a_{n}',
    // other bases keep \overset; \stackrel → \overset
    r'\overset { a } { b } + \stackrel { c } { d }':
        r'\overset{a}{b}+\overset{c}{d}',
    // function names spelled letter by letter
    r'\operatorname* { l i m } _ { x \to 0 } f': r'\lim_{x\to 0}f',
    r'\operatorname { s i n } x + \mathrm { c o s } y': r'\sin x+\cos y',
    // \root … \of
    r'\root 3 \of { 8 } = 2': r'\sqrt[3]{8}=2',
    // matrices with \left / \right delimiters → the delimited environment
    r'\left( \begin{array} { c c } { a } & { b } \\ { c } & { d } \end{array} \right)':
        r'\begin{pmatrix}{a}&{b}\\{c}&{d}\end{pmatrix}',
    // an aligning column spec keeps the array (and its delimiters)
    r'\begin{array} { l r } a & b \\ c & d \end{array}':
        r'\begin{array}{lr}a&b\\c&d\end{array}',
    r'\left[ \begin{array} { c | c } 1 & 2 \end{array} \right]':
        r'\left[\begin{array}{c|c}1&2\end{array}\right]',
    // words in text mode keep their spaces (as ~); letter by letter they
    // join, and the corpus's own ~ stays
    r'\text { for all } x': r'\text{for~all}x',
    r'\textrm { such  that }': r'\mathrm{such~that}',
    r'\text { f o r ~ a l l } x': r'\text{for~all}x',
    r'\text { i f } x': r'\text{if}x',
    r'\left[ \begin{matrix} 1 & 0 \\ 0 & 1 \end{matrix} \right]':
        r'\begin{bmatrix}1&0\\0&1\end{bmatrix}',
    r'\left| \begin{matrix} a & b \\ c & d \end{matrix} \right|':
        r'\begin{vmatrix}a&b\\c&d\end{vmatrix}',
    r'\left\{ \begin{matrix} x + y = 2 \\ x - y = 0 \end{matrix} \right.':
        r'\begin{cases}x+y=2\\x-y=0\end{cases}',
    r'\left( \begin{matrix} a b \\ e \\ \end{matrix} \right)':
        r'\begin{pmatrix}ab\\e\end{pmatrix}',
    // capital-only alphabets
    r'\mathcal { 1 } + \mathcal { N } + \mathcal { d A }': r'1+\mathcal{N}+dA',
    // synonyms, old font switches, sizes, spacing at a group end
    r'\pi _ { V } \sp { 2 }': r'\pi_{V}^{2}',
    r'\lim _ { \bf x \rightarrow 0 } f': r'\lim_{x\rightarrow 0}f',
    r'2 \sqrt { 3 \, }': r'2\sqrt{3}',
    r'\frac { 1 } { 2 } \hspace { 1 c m } x': r'\frac{1}{2}x',
    r'\Huge \Omega ^ { 2 }': r'\Omega^{2}',
    r'\int _ { 0 } ^ { 1 } \! x ^ { 2 } \, d x': r'\int_{0}^{1}\!x^{2}\,dx',
    // sub before sup; empty scripts; \not
    r'x ^ { 2 } _ { i }': r'x_{i}^{2}',
    r'x _ { } + 1': 'x+1',
    r'\not | 2': r'\nmid 2',
    r'a \not = b': r'a\neq b',
    // unbalanced \left / \right: the pair markers go, delimiters stay
    r'\left( x + 1': '(x+1',
    r'x \right)': 'x)',
    r'\mathbf { a } \cdot \mathbf { b }': r'\mathbf{a}\cdot\mathbf{b}',
    r'$x$': 'x',
  };

  test('corpus style → compact KaTeX that renders', () {
    for (final MapEntry(key: raw, value: expected) in cases.entries) {
      final out = _norm(raw);
      expect(out, expected, reason: raw);
      expect(InkMathRenderer.validate(out), isNull, reason: '$raw → $out');
    }
  });

  test('every reference decode of the fixtures renders after normalising', () {
    final fixtures = jsonDecode(
      File('${mfrFixtures()}/mfr_decode_cases.json').readAsStringSync(),
    ) as Map<String, Object?>;
    for (final c in (fixtures['cases']! as List).cast<Map<String, Object?>>()) {
      final out = _norm(c['text']! as String);
      expect(out, isNotEmpty);
      expect(InkMathRenderer.validate(out), isNull, reason: '${c['text']}');
    }
  });

  test('a command the renderer rejects is dropped (validate-driven)', () {
    String? fake(String latex) =>
        latex.contains(r'\foo') ? r'Undefined control sequence: \foo' : null;
    expect(normalizeMfrLatex(r'a \foo + b', validate: fake), 'a+b');
    // another error: returned as is (the user edits it)
    expect(
      normalizeMfrLatex(r'\frac { a', validate: (_) => 'Expected group'),
      r'\frac{a}',
    );
    // no validator: the plain rewrite
    expect(normalizeMfrLatex(r'x ^ { 2 }'), 'x^{2}');
  });

  test('garbage never throws and stays a string', () {
    for (final raw in [
      '',
      '}}}{{{',
      r'\left\left\right',
      r'\begin{matrix} a',
      r'\end{array} } \\',
      r'\root 3',
      r'\underset { a }',
      r'\kern . 5 c m x',
      '^ _ ^',
      r'{ \i \atop 0 \atop \imath }',
    ]) {
      expect(() => _norm(raw), returnsNormally, reason: raw);
    }
    expect(_norm('^ 2'), '{}^2');
  });
}
