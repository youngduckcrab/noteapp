// lib/src/ondevice/latex_normalizer.dart — (internal) the on-device math
// engine's LaTeX clean-up: the model writes space-separated tokens in the
// style of its training corpus (`\frac { 1 } { n ^ { 2 } }`,
// `\underset { n = 1 } { \overset { \infty } { \sum } }`,
// `\operatorname* { l i m }`, `\root 3 \of { 8 }`,
// `\left( \begin{matrix} … \end{matrix} \right)`, `\mathcal { 1 }`, TeX
// primitives and font switches). The app's renderer (InkMathRenderer —
// flutter_math_fork, KaTeX's grammar) wants plain, compact KaTeX.
//
// The canonical forms follow the reference evaluation's canonicaliser
// (latex_norm.py — tokens, brace groups, \underset/\overset → _/^, function
// names, \root…\of, matrix environments, synonyms); unlike it, the result
// keeps the meaning AND renders: spacing commands, \left/\right pairs and
// font commands that KaTeX knows stay.
//
// [normalizeMfrLatex] never fails: with a [validate] callback (null =
// renders; else the renderer's error) it also removes commands the renderer
// reports as undefined, a few times; whatever is left is returned — a
// suggestion the user edits.
//
// [matrixColumnGutters] is ink evidence for a matrix the model wrote as one
// column (matrix_ink_hint.dart): the number of clear vertical gutters
// between the brackets. It only ever helps split such a matrix; it is used
// only when the output has exactly one matrix environment.

/// The model's LaTeX as compact, renderable KaTeX (see the file comment).
String normalizeMfrLatex(
  String raw, {
  String? Function(String latex)? validate,
  int? matrixColumnGutters,
}) {
  final gutters = matrixColumnGutters;
  var latex = _normalize(raw, gutters: gutters);
  if (validate == null || latex.isEmpty) return latex;
  final drop = <String>{};
  for (var attempt = 0; attempt < 6; attempt++) {
    final error = validate(latex);
    if (error == null) return latex;
    final cmd = _undefinedCommand(error);
    if (cmd == null || !drop.add(cmd)) break;
    final stripped = _normalize(raw, drop: drop, gutters: gutters);
    if (stripped == latex) break;
    latex = stripped;
  }
  return latex;
}

/// The command a renderer error names ('Undefined control sequence: \foo',
/// 'Unknown …', 'Unsupported …'); null for another error.
String? _undefinedCommand(String error) {
  if (!RegExp('Undefined|Unknown|Unsupported|not supported').hasMatch(error)) {
    return null;
  }
  return RegExp(r'\\[a-zA-Z]+\*?').firstMatch(error)?.group(0);
}

// --- tokens and groups --------------------------------------------------------

final RegExp _tokenRe = RegExp(r'\\[a-zA-Z]+\*?|\\.|[^\s]');
final RegExp _controlWord = RegExp(r'^\\[a-zA-Z]+\*?$');

List<String> _tokenize(String s) {
  final tokens = [for (final m in _tokenRe.allMatches(s)) m.group(0)!];
  // \begin { m a t r i x } → one token '\begin{matrix}' (and \end).
  final out = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if ((t == r'\begin' || t == r'\end') &&
        i + 1 < tokens.length &&
        tokens[i + 1] == '{') {
      final name = StringBuffer();
      var j = i + 2;
      while (j < tokens.length && RegExp(r'^[a-zA-Z*]$').hasMatch(tokens[j])) {
        name.write(tokens[j]);
        j++;
      }
      if (j < tokens.length && tokens[j] == '}' && name.isNotEmpty) {
        out.add('$t{$name}');
        i = j;
        continue;
      }
    }
    out.add(t);
  }
  return out;
}

final class _Group {
  _Group(this.nodes);
  final List<Object> nodes; // String | _Group
}

List<Object> _parse(List<String> tokens) {
  final stack = <List<Object>>[[]];
  for (final t in tokens) {
    if (t == '{') {
      final g = <Object>[];
      stack.last.add(_Group(g));
      stack.add(g);
    } else if (t == '}') {
      if (stack.length > 1) stack.removeLast(); // a stray '}' is dropped
    } else {
      stack.last.add(t);
    }
  }
  return stack.first; // unclosed groups end at the end
}

// --- tables -------------------------------------------------------------------

/// Commands dropped with nothing else (TeX primitives, size and style
/// switches, rules, line breaks the renderer has no use for).
const Set<String> _dropAlone = {
  r'\protect',
  r'\expandafter',
  r'\break',
  r'\relax',
  r'\noindent',
  r'\displaystyle',
  r'\textstyle',
  r'\scriptstyle',
  r'\scriptscriptstyle',
  r'\limits',
  r'\nolimits',
  r'\mathinner',
  r'\nulldelimiterspace',
  r'\Huge',
  r'\huge',
  r'\LARGE',
  r'\Large',
  r'\large',
  r'\small',
  r'\footnotesize',
  r'\scriptsize',
  r'\tiny',
  r'\normalsize',
  r'\hfill',
  r'\hline',
  r'\newline',
  r'\bf',
  r'\rm',
  r'\it',
  r'\cal',
  r'\sf',
  r'\tt',
  r'\mit',
  r'\boldmath',
  r'\big',
  r'\Big',
  r'\bigg',
  r'\Bigg',
  r'\bigl',
  r'\bigr',
  r'\Bigl',
  r'\Bigr',
  r'\biggl',
  r'\biggr',
  r'\Biggl',
  r'\Biggr',
  r'\middle',
  r'\b',
  r'\brack',
  r'\mathstrut',
  r'\strut',
};

/// Commands dropped together with their one argument.
const Set<String> _dropWithArg = {
  r'\hspace',
  r'\hspace*',
  r'\vspace',
  r'\vspace*',
  r'\phantom',
  r'\hphantom',
  r'\vphantom',
  r'\label',
  r'\tag',
};

/// Commands dropped together with a following TeX dimension / number.
const Set<String> _dropWithDimension = {
  r'\kern',
  r'\lower',
  r'\raise',
  r'\unitlength',
  r'\romannumeral',
  r'\mkern',
  r'\hskip',
  r'\vskip',
};

/// One-for-one replacements (synonyms the renderer lacks, text-mode letters).
const Map<String, String> _replace = {
  r'\sp': '^',
  r'\sb': '_',
  r'\lbrack': '[',
  r'\rbrack': ']',
  r'\hdots': r'\ldots',
  r'\ddag': r'\ddagger',
  r'\dag': r'\dagger',
  r'\lnot': r'\neg',
  r'\i': 'i',
  r'\j': 'j',
  r'\o': 'o',
  r'\O': 'O',
  r'\L': 'L',
  r'\l': 'l',
  r'\AA': 'A',
  r'\aa': 'a',
  r'\ss': 's',
  r'\Alpha': 'A',
  r'\Beta': 'B',
  r'\Epsilon': 'E',
  r'\Zeta': 'Z',
  r'\Eta': 'H',
  r'\Iota': 'I',
  r'\Kappa': 'K',
  r'\Mu': 'M',
  r'\Nu': 'N',
  r'\Omicron': 'O',
  r'\Rho': 'P',
  r'\Tau': 'T',
  r'\Chi': 'X',
  r'\omicron': 'o',
  r'\bigtriangledown': r'\nabla',
  r'\textbackslash': r'\backslash',
  // display-math brackets the model writes around a matrix: plain brackets
  r'\[': '[',
  r'\]': ']',
};

/// Function names the model spells out letter by letter.
const Set<String> _functions = {
  'lim',
  'limsup',
  'liminf',
  'sin',
  'cos',
  'tan',
  'cot',
  'sec',
  'csc',
  'arcsin',
  'arccos',
  'arctan',
  'sinh',
  'cosh',
  'tanh',
  'coth',
  'log',
  'ln',
  'lg',
  'exp',
  'max',
  'min',
  'sup',
  'inf',
  'det',
  'gcd',
  'deg',
  'dim',
  'ker',
  'arg',
  'hom',
  'Pr',
  'mod',
};

/// Font commands whose argument is kept as is.
const Map<String, String> _fonts = {
  r'\mathrm': r'\mathrm',
  r'\mathit': r'\mathit',
  r'\mathbf': r'\mathbf',
  r'\boldsymbol': r'\boldsymbol',
  r'\bm': r'\boldsymbol',
  r'\pmb': r'\boldsymbol',
  r'\mathsf': r'\mathsf',
  r'\mathtt': r'\mathtt',
  r'\textrm': r'\mathrm',
  r'\mbox': r'\mathrm',
  r'\textsc': r'\mathrm',
  r'\textup': r'\mathrm',
  r'\textit': r'\mathit',
  r'\textbf': r'\mathbf',
  r'\textsf': r'\mathsf',
  r'\texttt': r'\mathtt',
  r'\mathnormal': '',
  r'\operatorname': r'\operatorname',
  r'\operatorname*': r'\operatorname',
  r'\text': r'\text',
};

/// Letter-only alphabets: kept only around capital letters (`\mathcal{1}`,
/// `\mathcal{dA}` are recognition slips).
const Set<String> _capitalAlphabets = {
  r'\mathcal',
  r'\mathscr',
  r'\mathbb',
  r'\mathfrak',
};

/// Class wrappers around one symbol (`\mathop { = }`).
const Set<String> _classWrappers = {
  r'\mathop',
  r'\mathord',
  r'\mathrel',
  r'\mathbin',
  r'\mathpunct',
  r'\mathopen',
  r'\mathclose',
};

/// Operators that take limits: `\underset{a}{\sum}` → `\sum_{a}`.
const Set<String> _bigOperators = {
  r'\sum',
  r'\prod',
  r'\coprod',
  r'\int',
  r'\iint',
  r'\iiint',
  r'\oint',
  r'\bigcup',
  r'\bigcap',
  r'\bigoplus',
  r'\bigotimes',
  r'\bigodot',
  r'\bigvee',
  r'\bigwedge',
  r'\bigsqcup',
  r'\biguplus',
  r'\lim',
  r'\limsup',
  r'\liminf',
  r'\max',
  r'\min',
  r'\sup',
  r'\inf',
  r'\det',
  r'\gcd',
  r'\Pr',
};

/// Spacing commands (kept, except at a group's end).
const Set<String> _spacing = {
  r'\,',
  r'\!',
  r'\;',
  r'\:',
  r'\ ',
  '~',
  r'\quad',
  r'\qquad',
  r'\enspace',
  r'\thinspace',
};

/// Relations `\not` combines with.
const Set<String> _negatable = {
  '<',
  '>',
  r'\in',
  r'\subset',
  r'\supset',
  r'\subseteq',
  r'\supseteq',
  r'\equiv',
  r'\sim',
  r'\simeq',
  r'\approx',
  r'\cong',
  r'\leq',
  r'\geq',
  r'\parallel',
  r'\ni',
  r'\le',
  r'\ge',
  r'\prec',
  r'\succ',
};

/// `\left D … \right D'` around a matrix → the delimited environment.
String? _matrixFor(String open, String close) => switch ((open, close)) {
  ('(', ')') => 'pmatrix',
  ('[', ']') => 'bmatrix',
  ('|', '|') => 'vmatrix',
  (r'\|', r'\|') || (r'\Vert', r'\Vert') => 'Vmatrix',
  (r'\{', r'\}') || (r'\lbrace', r'\rbrace') => 'Bmatrix',
  (r'\{', '.') || (r'\lbrace', '.') => 'cases',
  _ => null,
};

const Set<String> _matrixLike = {
  'matrix',
  'array',
  'smallmatrix',
  'pmatrix',
  'bmatrix',
  'vmatrix',
  'Vmatrix',
  'Bmatrix',
  'cases',
  'aligned',
  'gathered',
  'split',
};

// --- the rewrite --------------------------------------------------------------

String _normalize(String raw, {Set<String> drop = const {}, int? gutters}) {
  var s = raw.trim();
  while (s.startsWith(r'$')) {
    s = s.substring(1);
  }
  while (s.endsWith(r'$') && !s.endsWith(r'\$')) {
    s = s.substring(0, s.length - 1);
  }
  final nodes = _parse(_tokenize(_keepTextSpaces(s)));
  final rewritten = _Rewriter(drop).run(nodes);
  final tokens = <String>[];
  _flatten(rewritten, tokens);
  final tidy = _tidy(tokens);
  // the ink hint describes one matrix: with more than one it says nothing
  final matrices = tidy
      .where(
        (t) =>
            t.startsWith(r'\begin{') &&
            _matrixLike.contains(t.substring(7, t.length - 1)),
      )
      .length;
  return _serialize(
    _cleanMatrices(tidy, gutters: matrices == 1 ? gutters : null),
  );
}

/// Text-mode arguments written as words (`\text { for all }` — not the
/// corpus's letter-by-letter `\text { f o r ~ a l l }`, where a space is
/// `~`): the spaces between words are meaningful there, so they become `~`
/// before the tokens drop all whitespace.
String _keepTextSpaces(String s) => s.replaceAllMapped(
  RegExp(
    r'(\\(?:text|textrm|textit|textbf|textsf|texttt|textup|textsc|mbox))'
    r'\s*\{([^{}\\]*)\}',
  ),
  (m) {
    final content = m.group(2)!.trim();
    if (!RegExp('[A-Za-z]{2,}').hasMatch(content)) return m.group(0)!;
    return '${m.group(1)}{${content.replaceAll(RegExp(r'\s+'), '~')}}';
  },
);

final class _Rewriter {
  _Rewriter(this.drop);

  final Set<String> drop;

  /// Per open `\begin{array}`: whether it stays an array (its column spec
  /// aligns: l / r / |) or became a matrix (all c).
  final List<bool> _arrays = [];

  List<Object> run(List<Object> nodes) {
    final out = <Object>[];
    var i = 0;
    Object? argAt(int j) => j < nodes.length ? nodes[j] : null;
    while (i < nodes.length) {
      final n = nodes[i];
      if (n is _Group) {
        out.add(_Group(run(n.nodes)));
        i++;
        continue;
      }
      final t = n as String;
      if (drop.contains(t) || _dropAlone.contains(t)) {
        i++;
        continue;
      }
      if (_dropWithArg.contains(t)) {
        i += argAt(i + 1) == null ? 1 : 2;
        continue;
      }
      if (_dropWithDimension.contains(t)) {
        i = _skipDimension(nodes, i + 1);
        continue;
      }
      if (t == r'\array' || t == r'\begin{array}') {
        // a centred spec ({ c c }) → matrix (columns follow &); one that
        // aligns ({ l r }, { c | c }) stays: KaTeX renders array
        final spec = argAt(i + 1);
        final hasSpec = spec is _Group && _isColumnSpec(spec);
        final aligns =
            hasSpec &&
            spec.nodes.every(
              (n) => RegExp(r'^[clr|]$').hasMatch(n as String),
            ) &&
            spec.nodes.any((n) => n != 'c');
        _arrays.add(aligns);
        if (aligns) {
          out
            ..add(r'\begin{array}')
            ..add(_Group(List.of(spec.nodes)));
        } else {
          out.add(r'\begin{matrix}');
        }
        i += hasSpec ? 2 : 1;
        continue;
      }
      if (t == r'\end{array}') {
        final kept = _arrays.isNotEmpty && _arrays.removeLast();
        out.add(kept ? r'\end{array}' : r'\end{matrix}');
        i++;
        continue;
      }
      if (t == r'\root') {
        final of = nodes.indexOf(r'\of', i + 1);
        if (of > i) {
          final index = run(nodes.sublist(i + 1, of));
          final radicand = argAt(of + 1);
          out
            ..add(r'\sqrt')
            ..add('[')
            ..addAll(_ungroup(index))
            ..add(']')
            ..add(_asGroup(radicand == null ? const [] : run([radicand])));
          i = radicand == null ? of + 1 : of + 2;
          continue;
        }
        i++;
        continue;
      }
      if (_fonts.containsKey(t) || _capitalAlphabets.contains(t)) {
        final arg = argAt(i + 1);
        if (arg == null) {
          i++;
          continue;
        }
        final letters = _letters(arg);
        if (letters != null &&
            _functions.contains(letters) &&
            (t.startsWith(r'\operatorname') ||
                t == r'\mathrm' ||
                letters.length > 1)) {
          out.add('\\$letters');
          i += 2;
          continue;
        }
        final inner = run(arg is _Group ? arg.nodes : [arg]);
        if (_capitalAlphabets.contains(t)) {
          if (letters != null && RegExp(r'^[A-Z]+$').hasMatch(letters)) {
            out
              ..add(t)
              ..add(_Group(inner));
          } else {
            out.addAll(inner);
          }
        } else {
          final font = _fonts[t]!;
          if (font.isEmpty || inner.isEmpty) {
            out.addAll(inner);
          } else {
            out
              ..add(font)
              ..add(_Group(inner));
          }
        }
        i += 2;
        continue;
      }
      if (_classWrappers.contains(t)) {
        final arg = argAt(i + 1);
        if (arg != null) out.addAll(run(arg is _Group ? arg.nodes : [arg]));
        i += arg == null ? 1 : 2;
        continue;
      }
      if (t == r'\underset' || t == r'\overset' || t == r'\stackrel') {
        final a = argAt(i + 1), b = argAt(i + 2);
        if (a == null || b == null) {
          i++;
          continue;
        }
        final script = run(a is _Group ? a.nodes : [a]);
        final base = run(b is _Group ? b.nodes : [b]);
        final mark = t == r'\underset' ? '_' : '^';
        if (base.isNotEmpty && _bigOperators.contains(base.first)) {
          out
            ..addAll(base)
            ..add(mark)
            ..add(_Group(script));
        } else {
          out
            ..add(t == r'\stackrel' ? r'\overset' : t)
            ..add(_Group(script))
            ..add(_Group(base));
        }
        i += 3;
        continue;
      }
      if (t == r'\not') {
        // only before a relation; `\not |` is \nmid, `\not =` is \neq
        final next = argAt(i + 1);
        if (next == '|' || next == r'\mid') {
          out.add(r'\nmid');
          i += 2;
        } else if (next == '=') {
          out.add(r'\neq');
          i += 2;
        } else if (next is String && _negatable.contains(next)) {
          out
            ..add(t)
            ..add(next);
          i += 2;
        } else {
          i++;
        }
        continue;
      }
      final replaced = _replace[t];
      if (replaced != null) {
        out.add(replaced);
        i++;
        continue;
      }
      out.add(t);
      i++;
    }
    return _pairDelimiters(out);
  }
}

int _skipDimension(List<Object> nodes, int i) {
  final numberish = RegExp(r'^[-+.,0-9]$');
  while (i < nodes.length &&
      nodes[i] is String &&
      numberish.hasMatch(nodes[i] as String)) {
    i++;
  }
  // a unit (pt, cm, mm, em, ex, mu, in, sp, bp, pc)
  if (i + 1 < nodes.length && nodes[i] is String && nodes[i + 1] is String) {
    final unit = '${nodes[i]}${nodes[i + 1]}';
    if (const {
      'pt',
      'cm',
      'mm',
      'em',
      'ex',
      'mu',
      'in',
      'sp',
      'bp',
      'pc',
    }.contains(unit)) {
      i += 2;
    }
  }
  return i;
}

bool _isColumnSpec(_Group g) =>
    g.nodes.isNotEmpty &&
    g.nodes.every(
      (n) => n is String && RegExp(r'^[clr|@pmb.0-9]$').hasMatch(n),
    );

/// The letters of a group made only of single letters (`{ l i m }` → 'lim').
String? _letters(Object node) {
  final nodes = node is _Group ? node.nodes : [node];
  if (nodes.isEmpty) return null;
  final b = StringBuffer();
  for (final n in nodes) {
    if (n is! String || !RegExp(r'^[a-zA-Z]$').hasMatch(n)) return null;
    b.write(n);
  }
  return b.toString();
}

List<Object> _ungroup(List<Object> nodes) =>
    nodes.length == 1 && nodes.first is _Group
    ? (nodes.first as _Group).nodes
    : nodes;

_Group _asGroup(List<Object> nodes) => _Group(_ungroup(nodes));

/// Within one brace level: `\left D … \right D'` pairs. A matrix
/// environment right inside a pair becomes the delimited environment; with
/// unbalanced \left / \right every one of them goes (the delimiters stay,
/// `.` goes).
List<Object> _pairDelimiters(List<Object> nodes) {
  var lefts = 0, rights = 0;
  for (final n in nodes) {
    if (n == r'\left') lefts++;
    if (n == r'\right') rights++;
  }
  final out = <Object>[];
  if (lefts != rights || !_wellOrdered(nodes)) {
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      if (n == r'\left' || n == r'\right') {
        if (i + 1 < nodes.length && nodes[i + 1] == '.') i++;
        continue;
      }
      out.add(n);
    }
    return out;
  }
  for (var i = 0; i < nodes.length; i++) {
    final n = nodes[i];
    if (n == r'\left' && i + 2 < nodes.length) {
      final open = nodes[i + 1];
      final begin = nodes[i + 2];
      if (open is String && begin is String && begin.startsWith(r'\begin{')) {
        final env = begin.substring(7, begin.length - 1);
        final end = nodes.indexOf('\\end{$env}', i + 3);
        if (_matrixLike.contains(env) &&
            end > 0 &&
            end + 2 < nodes.length &&
            nodes[end + 1] == r'\right' &&
            nodes[end + 2] is String) {
          final target = _matrixFor(open, nodes[end + 2] as String);
          // (an array left here has an aligning spec: its delimiters stay)
          if (target != null && env == 'matrix') {
            out
              ..add('\\begin{$target}')
              ..addAll(nodes.sublist(i + 3, end))
              ..add('\\end{$target}');
            i = end + 2;
            continue;
          }
        }
      }
    }
    out.add(n);
  }
  return out;
}

bool _wellOrdered(List<Object> nodes) {
  var depth = 0;
  for (var i = 0; i < nodes.length; i++) {
    final n = nodes[i];
    if (n == r'\left' || n == r'\right') {
      // a delimiter must follow, and not a group
      if (i + 1 >= nodes.length || nodes[i + 1] is _Group) return false;
      depth += n == r'\left' ? 1 : -1;
      if (depth < 0) return false;
    }
  }
  return depth == 0;
}

void _flatten(List<Object> nodes, List<String> out) {
  for (final n in nodes) {
    if (n is _Group) {
      out.add('{');
      _flatten(n.nodes, out);
      out.add('}');
    } else {
      out.add(n as String);
    }
  }
}

/// Token-level tidying: no `\\` right before `\end{…}`, empty scripts go,
/// `X ^ {a} _ {b}` → `X _ {b} ^ {a}`, a script with no base gets `{}`.
List<String> _tidy(List<String> t) {
  var tokens = List<String>.of(t);
  // trailing row separators
  for (var i = tokens.length - 2; i >= 0; i--) {
    if (tokens[i] == r'\\' && tokens[i + 1].startsWith(r'\end{')) {
      tokens.removeAt(i);
    }
  }
  // spacing right before a group's end or at the end (`\sqrt{3\,}`)
  for (var i = tokens.length - 1; i >= 0; i--) {
    if (_spacing.contains(tokens[i]) &&
        (i == tokens.length - 1 || tokens[i + 1] == '}')) {
      tokens.removeAt(i);
    }
  }
  // empty scripts: ^ { } / _ { }
  for (var i = tokens.length - 3; i >= 0; i--) {
    if ((tokens[i] == '^' || tokens[i] == '_') &&
        tokens[i + 1] == '{' &&
        tokens[i + 2] == '}') {
      tokens.removeRange(i, i + 3);
    }
  }
  // sub before sup when both follow a base: X ^ A _ B → X _ B ^ A
  tokens = _orderScripts(tokens);
  // a script with nothing before it (start, after '{', '&', '\\')
  final out = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    if ((tok == '^' || tok == '_') &&
        (out.isEmpty ||
            out.last == '{' ||
            out.last == '&' ||
            out.last == r'\\' ||
            out.last == '^' ||
            out.last == '_' ||
            out.last.startsWith(r'\begin{'))) {
      out
        ..add('{')
        ..add('}');
    }
    out.add(tok);
  }
  // double scripts on one base (x ^ a ^ b) → wrap the first in braces
  return _fixDoubleScripts(out);
}

/// The end index (exclusive) of the script argument starting at [i].
int _argEnd(List<String> t, int i) {
  if (i >= t.length) return i;
  if (t[i] != '{') return i + 1;
  var depth = 0;
  for (var j = i; j < t.length; j++) {
    if (t[j] == '{') depth++;
    if (t[j] == '}') {
      depth--;
      if (depth == 0) return j + 1;
    }
  }
  return t.length;
}

List<String> _orderScripts(List<String> t) {
  final out = List<String>.of(t);
  for (var i = 0; i < out.length; i++) {
    if (out[i] != '^') continue;
    final supEnd = _argEnd(out, i + 1);
    if (supEnd < out.length && out[supEnd] == '_') {
      final subEnd = _argEnd(out, supEnd + 1);
      final sup = out.sublist(i, supEnd);
      final sub = out.sublist(supEnd, subEnd);
      out.replaceRange(i, subEnd, [...sub, ...sup]);
      i = i + sub.length + sup.length - 1;
    }
  }
  return out;
}

List<String> _fixDoubleScripts(List<String> t) {
  final out = List<String>.of(t);
  for (var i = 0; i < out.length; i++) {
    if (out[i] != '^' && out[i] != '_') continue;
    final end = _argEnd(out, i + 1);
    // after X^a, X_a^b: a third script of a kind already seen gets a base
    if (end < out.length && out[end] == out[i]) {
      out.insertAll(end, const ['{', '}']);
    } else if (end < out.length && (out[end] == '^' || out[end] == '_')) {
      final end2 = _argEnd(out, end + 1);
      if (end2 < out.length && (out[end2] == '^' || out[end2] == '_')) {
        out.insertAll(end2, const ['{', '}']);
      }
    }
  }
  return out;
}

String _serialize(List<String> tokens) {
  final b = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    if (i > 0 && _controlWord.hasMatch(tokens[i - 1])) {
      // a letter would continue the command's name; a digit only reads
      // better apart (`\to 0`)
      final c = tok.codeUnitAt(0);
      final letter = (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);
      final digit = c >= 0x30 && c <= 0x39;
      if (letter || digit) b.write(' ');
    }
    b.write(tok);
  }
  return b.toString();
}

// --- matrices -----------------------------------------------------------------

/// Font commands the model puts on every matrix entry (`{ \mathbf { a } }`):
/// handwriting has no bold or typewriter letters, so inside a matrix they go.
const Set<String> _matrixFonts = {
  r'\mathbf',
  r'\mathtt',
  r'\mathsf',
  r'\boldsymbol',
  r'\mathit',
};

/// Bare delimiters that make a delimited matrix (`[ \begin{matrix} … ]`).
const Set<String> _bareOpen = {'(', '[', '|', r'\|', r'\{'};

/// Matrix environments, token level (inner ones first):
/// - in a matrix (not aligned / gathered / split) every column that is empty
///   in every row goes, at the edges or inside (the model pads a matrix with
///   `{ } &` and `& { }`, and writes a wide gap as an empty column), and so
///   does every empty row; an array's column spec follows the remaining
///   columns;
/// - a matrix the model wrote as one column whose cells hold whole rows
///   (`{ a b } \\ { c d }` — a tight column gap) is split into columns
///   ([_splitColumn]);
/// - font commands on the entries go;
/// - delimiters around it (`\left[ … \right]`, or bare `[ … ]`) make the
///   delimited environment (bmatrix, pmatrix, …) — for an array too, unless
///   its spec draws lines (`c|c`).
List<String> _cleanMatrices(List<String> t, {int? gutters}) {
  final out = <String>[];
  var i = 0;
  while (i < t.length) {
    final tok = t[i];
    final env = tok.startsWith(r'\begin{')
        ? tok.substring(7, tok.length - 1)
        : null;
    final end = env == null ? -1 : _matchingEnd(t, i);
    if (env == null || end < 0 || !_matrixLike.contains(env)) {
      out.add(tok);
      i++;
      continue;
    }
    var bodyStart = i + 1;
    List<String>? spec;
    if (env == 'array' && bodyStart < end && t[bodyStart] == '{') {
      final specEnd = _argEnd(t, bodyStart);
      spec = t.sublist(bodyStart + 1, specEnd - 1);
      bodyStart = specEnd;
    }

    // delimiters around it
    String? open, close;
    var before = 0, after = 0;
    if (out.length >= 2 && out[out.length - 2] == r'\left') {
      open = out.last;
      before = 2;
      if (end + 2 < t.length && t[end + 1] == r'\right') {
        close = t[end + 2];
        after = 2;
      }
    } else if (out.isNotEmpty && _bareOpen.contains(out.last)) {
      open = out.last;
      before = 1;
      if (end + 1 < t.length) {
        close = t[end + 1];
        after = 1;
      }
    }
    final lines = spec != null && spec.contains('|');
    final target = open != null && close != null && !lines
        ? (env == 'matrix' || env == 'array' ? _matrixFor(open, close) : null)
        : null;

    final grid = env == 'aligned' || env == 'gathered' || env == 'split';
    final rows = [
      for (final row in _splitTop(
        _cleanMatrices(t.sublist(bodyStart, end)),
        r'\\',
      ))
        _splitTop(row, '&'),
    ];
    final width = _width(rows);
    final kept = grid ? null : _dropEmpty(rows);
    final split = grid || lines || env == 'cases' || target == 'cases'
        ? null
        : _splitColumn(rows, gutters);
    if (split != null) {
      rows
        ..clear()
        ..addAll(split);
    } else if (!grid) {
      for (final r in rows) {
        for (var c = 0; c < r.length; c++) {
          r[c] = _dropFonts(r[c]);
        }
      }
    }
    final columns = _width(rows);

    final body = <String>[];
    for (var r = 0; r < rows.length; r++) {
      if (r > 0) body.add(r'\\');
      for (var c = 0; c < rows[r].length; c++) {
        if (c > 0) body.add('&');
        body.addAll(rows[r][c]);
      }
    }
    if (target != null) {
      out
        ..removeRange(out.length - before, out.length)
        ..add('\\begin{$target}')
        ..addAll(body)
        ..add('\\end{$target}');
      i = end + 1 + after;
      continue;
    }
    out.add(tok);
    if (spec != null) {
      out
        ..add('{')
        ..addAll(
          lines
              ? spec
              : _fitSpec(spec, columns, width: width, kept: kept, split: split),
        )
        ..add('}');
    }
    out
      ..addAll(body)
      ..add(t[end]);
    i = end + 1;
  }
  return out;
}

/// The index of the `\end{…}` closing the `\begin{…}` at [i]; -1 if none.
int _matchingEnd(List<String> t, int i) {
  var depth = 0;
  for (var j = i; j < t.length; j++) {
    if (t[j].startsWith(r'\begin{')) depth++;
    if (t[j].startsWith(r'\end{')) {
      depth--;
      if (depth == 0) return j;
    }
  }
  return -1;
}

/// [t] split at [sep] outside braces and inner environments.
List<List<String>> _splitTop(List<String> t, String sep) {
  final parts = <List<String>>[[]];
  var depth = 0;
  for (final tok in t) {
    if (tok == '{' || tok.startsWith(r'\begin{')) depth++;
    if (tok == '}' || tok.startsWith(r'\end{')) depth--;
    if (tok == sep && depth == 0) {
      parts.add([]);
    } else {
      parts.last.add(tok);
    }
  }
  return parts;
}

/// [cell] without font commands, and without the braces they leave
/// doubled (`{ \mathbf { a } }` → `{a}`).
List<String> _dropFonts(List<String> cell) {
  var out = [
    for (var k = 0; k < cell.length; k++)
      if (!(_matrixFonts.contains(cell[k]) &&
          k + 1 < cell.length &&
          cell[k + 1] == '{'))
        cell[k],
  ];
  while (out.length >= 4 &&
      out[0] == '{' &&
      out[1] == '{' &&
      _argEnd(out, 0) == out.length &&
      _argEnd(out, 1) == out.length - 1) {
    out = out.sublist(1, out.length - 1);
  }
  return out;
}

bool _emptyCell(List<String> cell) =>
    cell.every((t) => t == '{' || t == '}' || _spacing.contains(t));

int _width(List<List<List<String>>> rows) =>
    rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);

/// Every column empty in all rows goes (a row shorter than the widest has
/// empty cells at its end), and every empty row; a matrix with nothing in
/// it stays. The indices of the columns kept; null when nothing changed.
List<int>? _dropEmpty(List<List<List<String>>> rows) {
  if (rows.every((r) => r.every(_emptyCell))) return null;
  rows.removeWhere((r) => r.every(_emptyCell));
  final width = _width(rows);
  final kept = [
    for (var c = 0; c < width; c++)
      if (rows.any((r) => c < r.length && !_emptyCell(r[c]))) c,
  ];
  if (kept.length == width) return null;
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    rows[r] = [
      for (final c in kept)
        if (c < row.length) row[c],
    ];
  }
  return kept;
}

/// An array spec with one letter per column: the letters of the columns
/// [kept] (when the spec had one per column), one column's letter for
/// every column it was [split] into; otherwise extra letters go and `c`
/// fills.
List<String> _fitSpec(
  List<String> spec,
  int columns, {
  int width = 0,
  List<int>? kept,
  List<List<List<String>>>? split,
}) {
  var letters = spec.where((s) => RegExp('^[clr]\$').hasMatch(s)).toList();
  if (kept != null && letters.length == width) {
    letters = [for (final c in kept) letters[c]];
  }
  if (split != null && letters.length == 1) {
    letters = List.filled(columns, letters.single);
  }
  if (letters.length == columns || columns == 0) return letters;
  return [
    for (var k = 0; k < columns; k++) k < letters.length ? letters[k] : 'c',
  ];
}

// --- one-column matrices ------------------------------------------------------

/// Font and text wrappers the model puts around a whole row or around each
/// entry (`{ \textrm { a b } }` arrives as `\mathrm`, `\textbf { a }` as
/// `\mathbf`, `\bf` is already gone).
const Set<String> _rowWrappers = {
  r'\mathrm',
  r'\mathsf',
  r'\mathtt',
  r'\mathbf',
  r'\mathit',
  r'\boldsymbol',
  r'\text',
  r'\textrm',
  r'\textsf',
  r'\texttt',
  r'\textbf',
  r'\textit',
  r'\textup',
  r'\mbox',
};

/// Letter-like commands an entry may be (a letter for rule (b)).
const Set<String> _letterCommands = {
  r'\alpha',
  r'\beta',
  r'\gamma',
  r'\delta',
  r'\epsilon',
  r'\varepsilon',
  r'\zeta',
  r'\eta',
  r'\theta',
  r'\vartheta',
  r'\iota',
  r'\kappa',
  r'\lambda',
  r'\mu',
  r'\nu',
  r'\xi',
  r'\pi',
  r'\varpi',
  r'\rho',
  r'\varrho',
  r'\sigma',
  r'\varsigma',
  r'\tau',
  r'\upsilon',
  r'\phi',
  r'\varphi',
  r'\chi',
  r'\psi',
  r'\omega',
  r'\Gamma',
  r'\Delta',
  r'\Theta',
  r'\Lambda',
  r'\Xi',
  r'\Pi',
  r'\Sigma',
  r'\Upsilon',
  r'\Phi',
  r'\Psi',
  r'\Omega',
  r'\ell',
  r'\hbar',
  r'\imath',
  r'\jmath',
  r'\aleph',
};

/// Symbol commands an entry may be (not letters).
const Set<String> _symbolCommands = {
  r'\infty',
  r'\partial',
  r'\nabla',
  r'\emptyset',
  r'\varnothing',
};

final class _Atom {
  _Atom(this.tokens, {required this.letter});

  final List<String> tokens;

  /// A letter or a letter-like command (with its scripts), not a digit.
  final bool letter;
}

final class _RowAtoms {
  _RowAtoms(this.atoms, {required this.signal});

  final List<_Atom> atoms;

  /// The model marked the entries apart: spacing between them, or a text /
  /// font wrapper around the whole row or around every entry.
  final bool signal;
}

final RegExp _letterRe = RegExp(r'^[a-zA-Z]$');
final RegExp _digitRe = RegExp(r'^[0-9]$');

/// The entries of one cell that holds a whole row (`a b`, `1 \, 2`,
/// `\mathrm { a b }`, `\mathbf { a } \mathbf { b }`, `x _ { 1 } y _ { 1 }`,
/// `- 1 \, 2`); null when anything else is in it (an operator, a
/// relation, `.`, `,`, `\frac` …).
_RowAtoms? _rowAtoms(List<String> cell) {
  var c = cell;
  var wrapped = false;
  while (true) {
    if (c.length >= 2 && c.first == '{' && _argEnd(c, 0) == c.length) {
      c = c.sublist(1, c.length - 1);
    } else if (c.length >= 3 &&
        _rowWrappers.contains(c.first) &&
        c[1] == '{' &&
        _argEnd(c, 1) == c.length) {
      c = c.sublist(2, c.length - 1);
      wrapped = true;
    } else {
      break;
    }
  }
  final atoms = <_Atom>[];
  var spaced = false, pendingSeparator = false, afterSeparator = true;
  var wrappedAtoms = 0;
  var i = 0;
  while (i < c.length) {
    final tok = c[i];
    if (_spacing.contains(tok)) {
      if (atoms.isNotEmpty) pendingSeparator = true;
      afterSeparator = true;
      i++;
      continue;
    }
    final tokens = <String>[];
    // a unary sign only at the start or right after a separator
    if ((tok == '-' || tok == '+') && afterSeparator) {
      tokens.add(tok);
      i++;
      if (i >= c.length) return null;
    }
    final core = c[i];
    bool letter;
    if (_letterRe.hasMatch(core) || _letterCommands.contains(core)) {
      letter = true;
      tokens.add(core);
      i++;
    } else if (_digitRe.hasMatch(core) || _symbolCommands.contains(core)) {
      letter = false;
      tokens.add(core);
      i++;
    } else if (core == '{' ||
        (_rowWrappers.contains(core) && i + 1 < c.length && c[i + 1] == '{')) {
      final wrapper = core != '{';
      if (wrapper) wrappedAtoms++;
      final open = wrapper ? i + 1 : i;
      final close = _argEnd(c, open);
      final inner = c.sublist(open + 1, close - 1);
      if (inner.isEmpty || _emptyCell(inner)) return null;
      final single = _rowAtoms(inner);
      final one = single != null && single.atoms.length == 1;
      letter = one && single.atoms.single.letter;
      i = close;
      final scripted = i < c.length && (c[i] == '_' || c[i] == '^');
      if (one && (!scripted || single.atoms.single.tokens.length == 1)) {
        // `{ a }`, `\mathbf { a }` → a
        tokens.addAll(single.atoms.single.tokens);
      } else {
        tokens
          ..add('{')
          ..addAll(inner)
          ..add('}');
      }
    } else {
      return null;
    }
    while (i < c.length && (c[i] == '_' || c[i] == '^')) {
      if (i + 1 >= c.length) return null;
      final argEnd = _argEnd(c, i + 1);
      tokens.addAll(c.sublist(i, argEnd));
      i = argEnd;
    }
    if (pendingSeparator) spaced = true;
    pendingSeparator = false;
    afterSeparator = false;
    atoms.add(_Atom(tokens, letter: letter));
  }
  final n = atoms.length;
  return _RowAtoms(
    atoms,
    signal: n >= 2 && (spaced || wrapped || wrappedAtoms == n),
  );
}

/// A matrix the model wrote as one column whose cells hold whole rows →
/// its columns, or null to leave it. Every row must be the same number n
/// (2…8) of entries ([_rowAtoms]), and one of: the model marked them apart
/// in some row (spacing, a text / font wrapper); every entry is a letter
/// (`[ab; cd]` — a column of products is rarer in notes than a 2×2 matrix;
/// at least two rows); or the ink shows n − 1 clear [gutters] between the
/// brackets. Digits alone stay joined (`[12; 34]` may be numbers).
List<List<List<String>>>? _splitColumn(
  List<List<List<String>>> rows,
  int? gutters,
) {
  if (rows.isEmpty || rows.any((r) => r.length != 1)) return null;
  final parsed = <_RowAtoms>[];
  for (final r in rows) {
    final atoms = _rowAtoms(r.single);
    if (atoms == null) return null;
    parsed.add(atoms);
  }
  final n = parsed.first.atoms.length;
  if (n < 2 || n > 8 || parsed.any((p) => p.atoms.length != n)) return null;
  final signal = parsed.any((p) => p.signal);
  final letters =
      rows.length >= 2 && parsed.every((p) => p.atoms.every((a) => a.letter));
  final ink = gutters != null && gutters == n - 1;
  if (!signal && !letters && !ink) return null;
  return [
    for (final p in parsed) [for (final a in p.atoms) a.tokens],
  ];
}
