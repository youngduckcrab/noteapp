// Math (08-markdown 8.3, B-4): the app's KaTeX renderer (ink_engine MathPreview — a widget
// tree, sharp at every size). Inline math sits in the line (WidgetSpan, middle); block
// math is centred and scrolls sideways. When InkMathRenderer.validate fails, the source is
// shown as code in the error colour.
import 'package:flutter/widgets.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:material_ui/material_ui.dart';

import '../markdown_keys.dart';
import '../strings_ko.dart';
import 'md_inline.dart';

class MdMathView extends StatelessWidget {
  const MdMathView({
    super.key,
    required this.tex,
    required this.index,
    required this.display,
    required this.fontSize,
    this.inline = false,
  });

  final String tex;
  final int index;
  final bool display;

  /// The body text size (before the system text scale).
  final double fontSize;

  /// Inside a line of text (a WidgetSpan).
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final s = MdRenderScope.of(context).style;
    final size =
        MediaQuery.textScalerOf(context).scale(fontSize) *
        (display ? 1.15 : 1.0);
    final error = InkMathRenderer.validate(tex);
    final Widget child;
    if (error != null) {
      child = Semantics(
        label: MdStrings.mathError(error),
        child: Text(
          display ? tex : '\$$tex\$',
          style: s.codeBlock.copyWith(color: s.scheme.error),
        ),
      );
    } else {
      child = MathPreview(
        latex: tex,
        fontSize: size,
        color: s.tokens.textPrimary,
      );
    }
    final scroll = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: display ? 6 : 0, horizontal: 1),
        child: child,
      ),
    );
    if (inline && !display) {
      return KeyedSubtree(key: MarkdownKeys.math(index), child: scroll);
    }
    return Center(key: MarkdownKeys.math(index), child: scroll);
  }
}
