// T26b (m5-7/03-ink 8.1, 4.10, 6.12.1): InkMathRenderer.validate — the 43 LaTeX
// samples of research 03 (typical recognizer output): 42 are renderable, \tag is
// not; the short English messages of 4.10.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:note_core/note_core.dart' as core;

const _samples = <String, String>{
  'frac': r'\frac{a+b}{c}',
  'dfrac': r'\dfrac{1}{2}',
  'sup_sub': r'x^{2}+y_{1}',
  'sqrt_n': r'\sqrt[3]{x}',
  'int': r'\int_{0}^{1} f(x)\,dx',
  'iint_oint': r'\iint_D f\,dA + \oint_C \mathbf{F}\cdot d\mathbf{r}',
  'sum': r'\sum_{n=1}^{\infty} \frac{1}{n^2}',
  'lim': r'\lim_{x \to 0} \frac{\sin x}{x}',
  'pmatrix': r'\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}',
  'bmatrix': r'\begin{bmatrix} a & b \\ c & d \end{bmatrix}',
  'vmatrix': r'\begin{vmatrix} a & b \\ c & d \end{vmatrix}',
  'cases': r'\begin{cases} x+y=1 \\ x-y=2 \end{cases}',
  'mathpix_system':
      r'\left\{\begin{array}{l} x+y=1 \\ x-y=2 \end{array}\right.',
  'aligned': r'\begin{aligned} a&=b+c \\ d&=e \end{aligned}',
  'array_cc': r'\begin{array}{cc} a & b \\ c & d \end{array}',
  'greek': r'\alpha+\beta=\gamma,\ \Theta\Omega\varphi',
  'operatorname': r'\operatorname{argmax}_{x} f(x)',
  'mathrm_d': r'\frac{\mathrm{d}y}{\mathrm{d}x}',
  'mathbb': r'x \in \mathbb{R}',
  'mathcal': r'\mathcal{L}\{f\}',
  'boldsymbol': r'\boldsymbol{v}',
  'vec_hat_bar': r'\vec{v}+\hat{x}+\overline{AB}',
  'text_en': r'f(x)=1 \text{ if } x>0',
  'text_ko': r'f(x)=1 \text{ (단, } x>0 \text{)}',
  'xrightarrow': r'A \xrightarrow{f} B',
  'binom': r'\binom{n}{k}',
  'left_right': r'\left( \frac{1}{2} \right)^{2}',
  'partial_nabla': r'\frac{\partial f}{\partial x} = \nabla \cdot \vec{E}',
  'relations': r'a \leq b \geq c \neq d \approx e \equiv f',
  'dots': r'1, 2, \cdots, n \ldots',
  'prime': r"f'(x) + f''(x)",
  'underset': r'\underset{x \to 0}{\lim} f',
  'overset': r'\overset{\text{def}}{=}',
  'displaystyle': r'\displaystyle \sum_{i} x_i',
  'percent': r'50\%',
  'tag': r'E=mc^2 \tag{1}',
  'limits': r'\sum\limits_{i=1}^{n} i',
  'color': r'\color{red}{x}',
  'stackrel': r'\stackrel{?}{=}',
  'degree': r'90^{\circ}',
  'angle': r'\angle ABC = \frac{\pi}{2}',
  'therefore': r'\therefore x = 1',
  'pm': r'x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}',
};

void main() {
  test('42 of the 43 research samples are renderable; tag is not', () {
    expect(_samples, hasLength(43));
    final failed = <String, String>{};
    for (final e in _samples.entries) {
      final message = InkMathRenderer.validate(e.value);
      if (message != null) failed[e.key] = message;
    }
    expect(failed.keys, ['tag']);
    expect(failed['tag'], r'Undefined control sequence: \gdef');
  });

  test('messages: empty, too long, parser errors', () {
    expect(InkMathRenderer.validate(''), 'Empty formula');
    expect(InkMathRenderer.validate('   '), 'Empty formula');
    expect(
      InkMathRenderer.validate(
        'x' * (core.PageObjectLimits.maxLatexLength + 1),
      ),
      'Formula is too long',
    );
    expect(
      InkMathRenderer.validate('x' * core.PageObjectLimits.maxLatexLength),
      isNull,
    );
    expect(InkMathRenderer.validate(r'\frac{a'), "Expected '}', got 'EOF'");
    expect(
      InkMathRenderer.validate(r'\foo'),
      r'Undefined control sequence: \foo',
    );
    expect(InkMathRenderer.validate(r'\frac{a}{b}'), isNull);
  });
}
