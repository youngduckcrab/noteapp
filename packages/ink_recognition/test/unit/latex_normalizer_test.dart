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
    // the model's matrices: an empty last column, fonts on the entries,
    // an aligning spec and bare or display-math brackets around it
    r'\left[ \begin{array} { c c } { \mathbf { a } } & { } \\ { \mathbf { b } } & { } \\ \end{array} \right]':
        r'\begin{bmatrix}{a}\\{b}\end{bmatrix}',
    r'\left( \begin{array} { l l } { \mathtt { a } } & { } \\ { \mathtt { b } } & { } \\ \end{array} \right)':
        r'\begin{pmatrix}{a}\\{b}\end{pmatrix}',
    r'\left[ \begin{array} { l l l } { 1 } & { 2 } & { } \\ { 3 } & { 4 } & { } \\ \end{array} \right]':
        r'\begin{bmatrix}{1}&{2}\\{3}&{4}\end{bmatrix}',
    r'[ \begin{array} { c } { a } \\ { b } \end{array} \]':
        r'\begin{bmatrix}{a}\\{b}\end{bmatrix}',
    r'\lbrack \begin{matrix} a \\ b \end{matrix} \rbrack + 1':
        r'\begin{bmatrix}a\\b\end{bmatrix}+1',
    r'\left\{ \begin{array} { l } x = 1 \\ y = 2 \end{array} \right.':
        r'\begin{cases}x=1\\y=2\end{cases}',
    r'\left[ \begin{matrix} { } & { \mathbf { a } } & { } & { } \\ { } & { \mathbf { b } } & { } & { } \\ \end{matrix} \right]':
        r'\begin{bmatrix}{a}\\{b}\end{bmatrix}',
    r'\left[ \begin{array} { c c } { \ } & { a } \\ { \ } & { b } \\ \end{array} \right]':
        r'\begin{bmatrix}{a}\\{b}\end{bmatrix}',
    r'[ \begin{matrix} a \\ b \\ \end{matrix} ]':
        r'\begin{bmatrix}a\\b\end{bmatrix}',
    // a spec that is longer than the columns follows them
    r'\begin{array} { l l l } a & b & { } \\ c & d & { } \end{array}':
        r'\begin{array}{ll}a&b\\c&d\end{array}',
    // a matrix the model wrote as one column (a tight column gap): the
    // cells hold whole rows → split when every row is the same number of
    // entries and the model marked them apart (spacing, a text / font
    // wrapper) or they are all letters
    r'\left[ \begin{array} { r } { a b } \\ { c d } \\ \end{array} \right]':
        r'\begin{bmatrix}a&b\\c&d\end{bmatrix}',
    r'\left[ \begin{array} { c } { \textrm { a b } } \\ { \textrm { c d } } \\ \end{array} \right]':
        r'\begin{bmatrix}a&b\\c&d\end{bmatrix}',
    r'\left[ \begin{array} { c } { \textsf { x y } } \\ { \textsf { z w } } \\ \end{array} \right]':
        r'\begin{bmatrix}x&y\\z&w\end{bmatrix}',
    r'\left[ \begin{array} { c } { \textbf { a } \textbf { b } } \\ { \textbf { c } \textbf { d } } \\ \end{array} \right]':
        r'\begin{bmatrix}a&b\\c&d\end{bmatrix}',
    r'\left[ \begin{array} { c } { a \ b } \\ { c \ d } \\ \end{array} \right]':
        r'\begin{bmatrix}a&b\\c&d\end{bmatrix}',
    r'\left[ \begin{array} { c } { x y } \\ { z w } \\ \end{array} \right]':
        r'\begin{bmatrix}x&y\\z&w\end{bmatrix}',
    r'\left[ \begin{array} { c } { x _ { 1 } y _ { 1 } } \\ { x _ { 2 } y _ { 2 } } \end{array} \right]':
        r'\begin{bmatrix}x_{1}&y_{1}\\x_{2}&y_{2}\end{bmatrix}',
    // digits split only with a signal (else they may be numbers)
    r'\left[ \begin{array} { r } { 1 \, 2 } \\ { 3 \, 4 } \\ \end{array} \right]':
        r'\begin{bmatrix}1&2\\3&4\end{bmatrix}',
    r'\left[ \begin{array} { c } { 1 ~ 2 } \\ { 3 ~ 4 } \\ \end{array} \right]':
        r'\begin{bmatrix}1&2\\3&4\end{bmatrix}',
    r'\left[ \begin{array} { c } { - 1 \, 2 } \\ { 3 \, - 4 } \end{array} \right]':
        r'\begin{bmatrix}-1&2\\3&-4\end{bmatrix}',
    r'\left[ \begin{array} { r } { 1 2 } \\ { 3 4 } \\ \end{array} \right]':
        r'\begin{bmatrix}{12}\\{34}\end{bmatrix}',
    r'\left[ \begin{matrix} 1 2 \\ 3 4 \end{matrix} \right]':
        r'\begin{bmatrix}12\\34\end{bmatrix}',
    // with spacing between the entries, digits run together are one number
    r'\left[ \begin{array} { c } { 1 0 \, 2 0 } \\ { 3 0 \, 4 0 } \\ \end{array} \right]':
        r'\begin{bmatrix}10&20\\30&40\end{bmatrix}',
    r'\left[ \begin{array} { c } { 1 2 \; 3 4 } \\ { 5 6 \; 7 8 } \\ \end{array} \right]':
        r'\begin{bmatrix}12&34\\56&78\end{bmatrix}',
    r'\left[ \begin{array} { c } { - 1 0 \, 2 } \\ { 3 \, - 4 0 } \end{array} \right]':
        r'\begin{bmatrix}-10&2\\3&-40\end{bmatrix}',
    // a math font around a row is how the model writes plain handwriting
    // too: not a signal (a text font is)
    r'\left[ \begin{array} { c } { \mathbf { 1 2 } } \\ { \mathbf { 3 4 } } \end{array} \right]':
        r'\begin{bmatrix}{12}\\{34}\end{bmatrix}',
    r'\left[ \begin{array} { c } { \textbf { 1 2 } } \\ { \textbf { 3 4 } } \end{array} \right]':
        r'\begin{bmatrix}1&2\\3&4\end{bmatrix}',
    // a common factor in every row is a column vector, not a column
    // (the model's real [kx; ky], [ax; ay], [xt; yt])
    r'\left[ \begin{array} { l } { \mathsf { k x } } \\ { \mathsf { k y } } \\ \end{array} \right]':
        r'\begin{bmatrix}{kx}\\{ky}\end{bmatrix}',
    r'\left[ \begin{array} { c } { \mathrm { a x } } \\ { \mathrm { a y } } \\ \end{array} \right]':
        r'\begin{bmatrix}{\mathrm{ax}}\\{\mathrm{ay}}\end{bmatrix}',
    r'\left[ \begin{matrix} { x t } \\ { y t } \end{matrix} \right]':
        r'\begin{bmatrix}{xt}\\{yt}\end{bmatrix}',
    r'\left[ \begin{array} { c c } { \boldsymbol { k } \boldsymbol { x } } & { \boldsymbol { } } \\ { \boldsymbol { k } \boldsymbol { y } } & { \boldsymbol { } } \\ \end{array} \right]':
        r'\begin{bmatrix}{{k}{x}}\\{{k}{y}}\end{bmatrix}',
    r'\left[ \begin{array} { c } { \lambda x } \\ { \lambda y } \end{array} \right]':
        r'\begin{bmatrix}{\lambda x}\\{\lambda y}\end{bmatrix}',
    r'\left[ \begin{array} { c } { \mathrm { d } x } \\ { \mathrm { d } y } \end{array} \right]':
        r'\begin{bmatrix}{\mathrm{d}x}\\{\mathrm{d}y}\end{bmatrix}',
    r'\left[ \begin{array} { c } { \mathrm { k m } } \\ { \mathrm { c m } } \end{array} \right]':
        r'\begin{bmatrix}{\mathrm{km}}\\{\mathrm{cm}}\end{bmatrix}',
    // spacing is evidence enough; an upright d stays upright
    r'\left[ \begin{array} { c } { \mathrm { d } \, x } \\ { \mathrm { d } \, y } \end{array} \right]':
        r'\begin{bmatrix}\mathrm{d}&x\\\mathrm{d}&y\end{bmatrix}',
    r'\left[ \begin{array} { c } { d x } \\ { d y } \end{array} \right]':
        r'\begin{bmatrix}{dx}\\{dy}\end{bmatrix}',
    // …but a 2×2 or 3×3 of letters still splits
    r'\left[ \begin{array} { c } { a b c } \\ { d e f } \\ { g h i } \end{array} \right]':
        r'\begin{bmatrix}a&b&c\\d&e&f\\g&h&i\end{bmatrix}',
    // a math font on every entry is a signal; around the whole row, or a
    // text font around a number, is not
    r'\left[ \begin{array} { c } { \mathbf { 1 } \mathbf { 2 } } \\ { \mathbf { 3 } \mathbf { 4 } } \end{array} \right]':
        r'\begin{bmatrix}1&2\\3&4\end{bmatrix}',
    r'\left[ \begin{array} { c } { \mathrm { 1 2 } } \\ { \mathrm { 3 4 } } \end{array} \right]':
        r'\begin{bmatrix}{\mathrm{12}}\\{\mathrm{34}}\end{bmatrix}',
    r'\left[ \begin{array} { c } { \textrm { 12 } } \\ { \textrm { 34 } } \end{array} \right]':
        r'\begin{bmatrix}{\mathrm{12}}\\{\mathrm{34}}\end{bmatrix}',
    // with spacing, only the spacing separates: a group of letters, or rows
    // that split differently, stay joined
    r'\left[ \begin{array} { c } { a b \, c } \\ { d e \, f } \end{array} \right]':
        r'\begin{bmatrix}{ab\,c}\\{de\,f}\end{bmatrix}',
    r'\left[ \begin{array} { c } { 1 0 \, 2 0 } \\ { 3 4 } \end{array} \right]':
        r'\begin{bmatrix}{10\,20}\\{34}\end{bmatrix}',
    // words in a text font are text
    r'\left[ \begin{array} { c } { \text { if } } \\ { \text { or } } \end{array} \right]':
        r'\begin{bmatrix}{\text{if}}\\{\text{or}}\end{bmatrix}',
    r'\left[ \begin{array} { c } { \text { ab } } \\ { \text { cd } } \end{array} \right]':
        r'\begin{bmatrix}{\text{ab}}\\{\text{cd}}\end{bmatrix}',
    r'\left[ \begin{array} { c } { \text { on } } \\ { \text { up } } \end{array} \right]':
        r'\begin{bmatrix}{\text{on}}\\{\text{up}}\end{bmatrix}',
    // …but a word outside the matrix says nothing about it
    r'\left[ \begin{array} { c } { a b } \\ { c d } \end{array} \right] \text { if }':
        r'\begin{bmatrix}a&b\\c&d\end{bmatrix}\text{if}',
    // letters alone split only a matrix with delimiters (a bare stack, a
    // sum's limits, may be products)
    r'\begin{array} { c } { a b } \\ { c d } \end{array}':
        r'\begin{matrix}{ab}\\{cd}\end{matrix}',
    r'\sum _ { \begin{array} { c } { i j } \\ { k l } \end{array} } x':
        r'\sum_{\begin{matrix}{ij}\\{kl}\end{matrix}}x',
    // one entry per row, an operator, a point: nothing to split
    r'\left[ \begin{array} { c } { a + b } \\ { c + d } \end{array} \right]':
        r'\begin{bmatrix}{a+b}\\{c+d}\end{bmatrix}',
    r'\left[ \begin{array} { c } { 1 . 5 } \\ { 2 . 5 } \end{array} \right]':
        r'\begin{bmatrix}{1.5}\\{2.5}\end{bmatrix}',
    r'\left[ \begin{array} { c } { x ^ { 2 } } \\ { y ^ { 2 } } \end{array} \right]':
        r'\begin{bmatrix}{x^{2}}\\{y^{2}}\end{bmatrix}',
    // cases and aligned are never split
    r'\left\{ \begin{array} { l } { a b } \\ { c d } \end{array} \right.':
        r'\begin{cases}{ab}\\{cd}\end{cases}',
    r'\begin{aligned} a b \\ c d \end{aligned}':
        r'\begin{aligned}ab\\cd\end{aligned}',
    // a split array keeps its column's alignment
    r'\begin{array} { r } a \, b \\ c \, d \end{array}':
        r'\begin{array}{rr}a&b\\c&d\end{array}',
    // a wide column gap: empty columns inside go, and empty rows
    r'\left[ \begin{array} { c c c } { a } & { } & { b } \\ { c } & { } & { d } \\ \end{array} \right]':
        r'\begin{bmatrix}{a}&{b}\\{c}&{d}\end{bmatrix}',
    r'\left[ \begin{array} { c c c } { a } & { } & { b } \\ { } & { } & { } \\ { c } & { } & { d } \\ \end{array} \right]':
        r'\begin{bmatrix}{a}&{b}\\{c}&{d}\end{bmatrix}',
    r'\left[ \begin{array} { c c c } { { \bf a } } & { } & { } & { \textsf { b } } \\ { { \bf c } } & { } & { } & { \textsf { d } } \\ \end{array} \right]':
        r'\begin{bmatrix}{a}&{b}\\{c}&{d}\end{bmatrix}',
    r'\begin{array} { l c r } a & { } & b \\ c & { } & d \end{array}':
        r'\begin{array}{lr}a&b\\c&d\end{array}',
    r'\left[ \begin{matrix} a & { } & b \\ c \end{matrix} \right]':
        r'\begin{bmatrix}a&b\\c\end{bmatrix}',
    // a ruled spec with a letter per column keeps its columns (the rules
    // would move); an extra padding column still goes
    r'\left[ \begin{array} { c c | c } { 1 } & { } & { 2 } \\ { 3 } & { } & { 4 } \end{array} \right]':
        r'\left[\begin{array}{cc|c}{1}&{}&{2}\\{3}&{}&{4}\end{array}\right]',
    r'\left[ \begin{array} { c | c | c } { a } & { } & { b } \\ { c } & { } & { d } \end{array} \right]':
        r'\left[\begin{array}{c|c|c}{a}&{}&{b}\\{c}&{}&{d}\end{array}\right]',
    r'\left[ \begin{array} { c c | c } { 1 } & { 2 } & { 3 } & { } \\ { 4 } & { 5 } & { 6 } & { } \end{array} \right]':
        r'\left[\begin{array}{cc|c}{1}&{2}&{3}\\{4}&{5}&{6}\end{array}\right]',
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

  test('ink gutters split a one-column matrix of digits', () {
    String norm(String raw, int? gutters) => normalizeMfrLatex(
      raw,
      validate: InkMathRenderer.validate,
      matrixColumnGutters: gutters,
    );
    const digits =
        r'\left[ \begin{array} { r } { 1 2 } \\ { 3 4 } \\ \end{array} \right]';
    expect(norm(digits, 1), r'\begin{bmatrix}1&2\\3&4\end{bmatrix}');
    // a count that does not fit, or none: the digits stay numbers
    expect(norm(digits, 0), r'\begin{bmatrix}{12}\\{34}\end{bmatrix}');
    expect(norm(digits, 2), r'\begin{bmatrix}{12}\\{34}\end{bmatrix}');
    expect(norm(digits, null), r'\begin{bmatrix}{12}\\{34}\end{bmatrix}');
    // three entries a row, two gutters; one row is enough with ink
    expect(
      norm(r'\left[ \begin{matrix} 1 2 3 \end{matrix} \right]', 2),
      r'\begin{bmatrix}1&2&3\end{bmatrix}',
    );
    // the hint never blocks a split the LaTeX itself shows
    expect(
      norm(
        r'\left[ \begin{array} { c } { 1 \, 2 } \\ { 3 \, 4 } \end{array} \right]',
        0,
      ),
      r'\begin{bmatrix}1&2\\3&4\end{bmatrix}',
    );
    // with two matrices the hint says nothing
    expect(
      norm(
        r'\left[ \begin{matrix} 1 2 \\ 3 4 \end{matrix} \right] \left[ \begin{matrix} 5 6 \\ 7 8 \end{matrix} \right]',
        1,
      ),
      r'\begin{bmatrix}12\\34\end{bmatrix}\begin{bmatrix}56\\78\end{bmatrix}',
    );
    // never in cases
    expect(
      norm(r'\left\{ \begin{matrix} 1 2 \\ 3 4 \end{matrix} \right.', 1),
      r'\begin{cases}12\\34\end{cases}',
    );
    // a matrix with nothing in it stays
    expect(
      norm(r'\begin{matrix} { } & { } \\ { } & { } \end{matrix}', null),
      r'\begin{matrix}{}&{}\\{}&{}\end{matrix}',
    );
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
