// Block renderers (08-markdown 8.3, B-3/B-7): headings with a hairline under h1/h2,
// paragraphs, lists (24 px per level, ● ○ ■ by depth, ordered lists keep their start),
// task boxes (48 dp targets), quotes (4 px accent bar), rules, front matter, footnotes.
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../markdown_keys.dart';
import '../parse/md_document.dart' show plainOfInlines;
import '../parse/md_model.dart';
import '../strings_ko.dart';
import 'md_code.dart';
import 'md_image.dart';
import 'md_inline.dart';
import 'md_math.dart';
import 'md_style.dart';
import 'md_table.dart';

/// Vertical gap after a top-level block.
const double kBlockGap = 14;

/// The nodes of one block (or of a list item / quote), stacked.
class MdNodesView extends StatelessWidget {
  const MdNodesView({
    super.key,
    required this.nodes,
    this.depth = 0,
    this.quoted = false,
    this.tight = false,
  });

  final List<MdNode> nodes;

  /// List nesting depth (bullet glyph).
  final int depth;
  final bool quoted;

  /// Inside a list item: smaller gaps.
  final bool tight;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();
    if (nodes.length == 1) {
      return MdNodeView(node: nodes.single, depth: depth, quoted: quoted);
    }
    final gap = tight ? 6.0 : kBlockGap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < nodes.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == nodes.length - 1 ? 0 : gap),
            child: MdNodeView(node: nodes[i], depth: depth, quoted: quoted),
          ),
      ],
    );
  }
}

class MdNodeView extends StatelessWidget {
  const MdNodeView({
    super.key,
    required this.node,
    this.depth = 0,
    this.quoted = false,
  });

  final MdNode node;
  final int depth;
  final bool quoted;

  @override
  Widget build(BuildContext context) {
    final s = MdRenderScope.of(context).style;
    final body = quoted ? s.quoted(s.body) : s.body;
    switch (node) {
      case MdHeading(:final level, :final inlines):
        final style = s.headings[(level - 1).clamp(0, 5)];
        return Semantics(
          header: true,
          child: Padding(
            padding: EdgeInsets.only(top: level <= 2 ? 10 : 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MdRichText(
                  inlines: inlines,
                  style: quoted ? s.quoted(style) : style,
                ),
                if (level <= 2)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    height: 1,
                    color: s.tokens.hairline,
                  ),
              ],
            ),
          ),
        );
      case MdParagraph(:final inlines):
        // A paragraph that is only an image or only display math is drawn as a block.
        final solo = inlines.length == 1 ? inlines.single : null;
        if (solo is MdImage) return MdImageView(image: solo);
        if (solo is MdMath && solo.display) {
          return MdMathView(
            tex: solo.tex,
            index: solo.index,
            display: true,
            fontSize: body.fontSize ?? 16,
          );
        }
        return MdRichText(inlines: inlines, style: body);
      case MdCodeBlock():
        return MdCodeBlockView(block: node as MdCodeBlock);
      case MdMathBlock(:final tex, :final index):
        return MdMathView(
          tex: tex,
          index: index,
          display: true,
          fontSize: body.fontSize ?? 16,
        );
      case MdQuote(:final children):
        return Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: s.tokens.accent, width: 4)),
          ),
          padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2),
          child: MdNodesView(nodes: children, depth: depth, quoted: true),
        );
      case MdList():
        return MdListView(list: node as MdList, depth: depth, quoted: quoted);
      case MdTable():
        return MdTableView(table: node as MdTable, style: body);
      case MdRule():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(height: 1, color: s.tokens.hairline),
        );
      case MdFrontMatter(:final raw):
        return MdFrontMatterView(raw: raw);
    }
  }
}

/// A list (or a slice of a long top-level list: [firstItem] is the index of `items[0]`
/// in the whole list, for the numbers).
class MdListView extends StatelessWidget {
  const MdListView({
    super.key,
    required this.list,
    this.depth = 0,
    this.quoted = false,
    this.firstItem = 0,
  });

  final MdList list;
  final int depth;
  final bool quoted;
  final int firstItem;

  @override
  Widget build(BuildContext context) {
    final scope = MdRenderScope.of(context);
    final s = scope.style;
    final body = quoted ? s.quoted(s.body) : s.body;
    final scaler = MediaQuery.textScalerOf(context);
    final lineHeight = scaler.scale(body.fontSize ?? 16) * (body.height ?? 1.6);
    final last = list.start + firstItem + list.items.length - 1;
    var numberWidth = kListIndent;
    if (list.ordered) {
      // The widest number, measured (long numbers and large text scales never wrap).
      final painter = TextPainter(
        text: TextSpan(
          text: '$last.',
          style: body.copyWith(fontWeight: FontWeight.w500),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      numberWidth = (painter.width + 8).ceilToDouble().clamp(
        kListIndent,
        160.0,
      );
      painter.dispose();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < list.items.length; i++)
          Padding(
            // Task rows are 48 dp high already (their tap targets).
            padding: EdgeInsets.only(
              top: i == 0 || list.items[i].task != null ? 0 : 4,
            ),
            child: _item(
              context,
              scope,
              list.items[i],
              list.start + firstItem + i,
              body,
              lineHeight,
              numberWidth,
            ),
          ),
      ],
    );
  }

  Widget _item(
    BuildContext context,
    MdRenderScope scope,
    MdListItem item,
    int number,
    TextStyle body,
    double lineHeight,
    double numberWidth,
  ) {
    final s = scope.style;
    final task = item.task;
    final Widget marker;
    var topPad = 0.0;
    if (task != null) {
      const target = 48.0;
      topPad = ((target - lineHeight) / 2).clamp(0, 24).toDouble();
      final enabled = scope.canToggleTask(task.index);
      final text = item.children.isEmpty
          ? ''
          : switch (item.children.first) {
              MdParagraph(:final inlines) => plainOfInlines(inlines),
              _ => '',
            };
      marker = SizedBox(
        width: 32,
        height: target,
        child: OverflowBox(
          maxWidth: target,
          child: Semantics(
            label: MdStrings.taskLabel(text, task.checked),
            child: Checkbox(
              key: MarkdownKeys.task(task.index),
              value: task.checked,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onChanged: enabled ? (_) => scope.onToggleTask(task.index) : null,
            ),
          ),
        ),
      );
    } else {
      final glyph = list.ordered
          ? '$number.'
          : switch (depth % 3) {
              0 => '•',
              1 => '◦',
              _ => '▪',
            };
      marker = SizedBox(
        width: numberWidth,
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(
            glyph,
            maxLines: 1,
            softWrap: false,
            textAlign: list.ordered ? TextAlign.right : TextAlign.center,
            style: body.copyWith(
              color: list.ordered ? body.color : s.tokens.textSecondary,
              fontWeight: list.ordered ? FontWeight.w500 : FontWeight.w700,
            ),
          ),
        ),
      );
    }
    final done = task?.checked ?? false;
    Widget content = MdNodesView(
      nodes: item.children,
      depth: depth + 1,
      quoted: quoted || done,
      tight: true,
    );
    if (topPad > 0) {
      content = Padding(
        padding: EdgeInsets.only(top: topPad),
        child: content,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        marker,
        Expanded(child: content),
      ],
    );
  }
}

/// The YAML front matter, folded by default (key md.frontMatter).
class MdFrontMatterView extends StatefulWidget {
  const MdFrontMatterView({super.key, required this.raw});

  final String raw;

  @override
  State<MdFrontMatterView> createState() => _MdFrontMatterViewState();
}

class _MdFrontMatterViewState extends State<MdFrontMatterView> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = MdRenderScope.of(context).style;
    final t = s.tokens;
    return Container(
      key: MarkdownKeys.frontMatter,
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.radiusMedium),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(t.radiusMedium),
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    AppIcon(AppIconKind.info, size: 18, color: t.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(MdStrings.frontMatter, style: s.small),
                    ),
                    AppIcon(
                      _open ? AppIconKind.hideMenu : AppIconKind.chevronDown,
                      size: 20,
                      color: t.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                widget.raw,
                softWrap: false,
                style: s.codeBlock.copyWith(color: t.textPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

/// The footnotes at the end of the document.
class MdFootnotesView extends StatelessWidget {
  const MdFootnotesView({super.key, required this.footnotes});

  final List<MdFootnote> footnotes;

  @override
  Widget build(BuildContext context) {
    final s = MdRenderScope.of(context).style;
    final small = s.body.copyWith(fontSize: 14, height: 1.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 1, color: s.tokens.hairline),
        const SizedBox(height: 10),
        Text(
          MdStrings.footnotes,
          style: s.small.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        for (final f in footnotes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: kListIndent + 4,
                  child: Text(
                    '${f.number}.',
                    style: small.copyWith(color: s.tokens.textSecondary),
                  ),
                ),
                Expanded(child: _small(context, f.children, small)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _small(BuildContext context, List<MdNode> nodes, TextStyle style) {
    final paragraphs = nodes.whereType<MdParagraph>().toList();
    if (paragraphs.length == nodes.length) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in paragraphs)
            MdRichText(inlines: p.inlines, style: style),
        ],
      );
    }
    return MdNodesView(nodes: nodes, tight: true);
  }
}
