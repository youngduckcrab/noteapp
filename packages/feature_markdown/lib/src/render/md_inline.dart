// Inline content → InlineSpans (08-markdown 8.3, B-3/B-4/B-6). Links are TextSpans with a
// tap recognizer (so long links wrap like text); math and images are WidgetSpans.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';

import '../parse/md_model.dart';
import '../strings_ko.dart';
import 'md_image.dart';
import 'md_math.dart';
import 'md_style.dart';

/// What the rendered blocks need from the screen.
class MdRenderScope extends InheritedWidget {
  const MdRenderScope({
    super.key,
    required this.style,
    required this.onLink,
    required this.onFootnote,
    required this.onToggleTask,
    required this.canToggleTask,
    required super.child,
  });

  final MdStyle style;
  final void Function(MdLink link) onLink;
  final void Function(String label) onFootnote;
  final void Function(int task) onToggleTask;

  /// Whether box i may be toggled (its source position is known and editing is allowed).
  final bool Function(int task) canToggleTask;

  static MdRenderScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MdRenderScope>()!;

  @override
  bool updateShouldNotify(MdRenderScope old) =>
      style != old.style ||
      onLink != old.onLink ||
      onToggleTask != old.onToggleTask ||
      canToggleTask != old.canToggleTask;
}

/// A paragraph-like run of inline content with working link taps.
class MdRichText extends StatefulWidget {
  const MdRichText({
    super.key,
    required this.inlines,
    required this.style,
    this.textAlign = TextAlign.start,
  });

  final List<MdInline> inlines;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  State<MdRichText> createState() => _MdRichTextState();
}

class _MdRichTextState extends State<MdRichText> {
  final List<GestureRecognizer> _recognizers = [];

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final scope = MdRenderScope.of(context);
    final spans = buildInlineSpans(
      context,
      widget.inlines,
      widget.style,
      scope: scope,
      recognizers: _recognizers,
    );
    return Text.rich(
      TextSpan(children: spans, style: widget.style),
      textAlign: widget.textAlign,
    );
  }
}

/// The spans of [inlines]; tap recognizers are added to [recognizers] (the caller
/// disposes them).
List<InlineSpan> buildInlineSpans(
  BuildContext context,
  List<MdInline> inlines,
  TextStyle style, {
  required MdRenderScope scope,
  required List<GestureRecognizer> recognizers,
  MdLink? inLink,
}) {
  final s = scope.style;
  final out = <InlineSpan>[];
  for (final x in inlines) {
    switch (x) {
      case MdText(:final text):
        out.add(
          TextSpan(
            text: text,
            style: style,
            recognizer: _last(inLink, recognizers),
          ),
        );
      case MdStyled(:final mark, :final children):
        final next = switch (mark) {
          MdMark.strong => style.copyWith(fontWeight: FontWeight.w700),
          MdMark.em => style.copyWith(fontStyle: FontStyle.italic),
          MdMark.del => style.copyWith(
            decoration: TextDecoration.combine([
              ?style.decoration,
              TextDecoration.lineThrough,
            ]),
            decorationColor: s.tokens.textSecondary,
          ),
          MdMark.code || MdMark.kbd => s.inlineCode.copyWith(
            fontSize: (style.fontSize ?? 16) * 0.9,
          ),
          MdMark.sub ||
          MdMark.sup => style.copyWith(fontSize: (style.fontSize ?? 16) * 0.75),
        };
        out.addAll(
          buildInlineSpans(
            context,
            children,
            next,
            scope: scope,
            recognizers: recognizers,
            inLink: inLink,
          ),
        );
      case MdCodeSpan(:final code):
        out.add(
          TextSpan(
            // Thin spaces pad the fill a little on both sides.
            text: ' $code ',
            style: s.inlineCode.copyWith(
              fontSize: (style.fontSize ?? 16) * 0.9,
            ),
            recognizer: _last(inLink, recognizers),
          ),
        );
      case MdLink():
        final tap = TapGestureRecognizer()..onTap = () => scope.onLink(x);
        recognizers.add(tap);
        out.add(
          TextSpan(
            style: s.link(style),
            semanticsLabel: null,
            mouseCursor: SystemMouseCursors.click,
            children: buildInlineSpans(
              context,
              x.children.isEmpty ? [MdText(x.href)] : x.children,
              s.link(style),
              scope: scope,
              recognizers: recognizers,
              inLink: x,
            ),
          ),
        );
      case MdImage():
        out.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: MdImageView(image: x, inline: true),
          ),
        );
      case MdMath():
        out.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: MdMathView(
              tex: x.tex,
              index: x.index,
              display: x.display,
              fontSize: style.fontSize ?? 16,
              inline: true,
            ),
          ),
        );
      case MdBreak():
        out.add(TextSpan(text: '\n', style: style));
      case MdFootnoteRef(:final label, :final number):
        out.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: Semantics(
              button: true,
              label: '${MdStrings.footnotes} $number',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => scope.onFootnote(label),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Text(
                    '$number',
                    style: style.copyWith(
                      fontSize: (style.fontSize ?? 16) * 0.7,
                      height: 1,
                      color: s.tokens.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    }
  }
  return out;
}

/// Inside a link every text piece shares the link's recognizer (the last one added).
GestureRecognizer? _last(MdLink? link, List<GestureRecognizer> recognizers) =>
    link == null || recognizers.isEmpty ? null : recognizers.last;
