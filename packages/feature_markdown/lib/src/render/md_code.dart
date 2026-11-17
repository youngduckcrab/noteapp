// Fenced and indented code (08-markdown 8.3, B-3): a card, monospace, no wrapping
// (scrolls sideways), the language name and [복사]. No syntax colouring.
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../markdown_keys.dart';
import '../parse/md_model.dart';
import '../strings_ko.dart';
import 'md_inline.dart';

class MdCodeBlockView extends StatelessWidget {
  const MdCodeBlockView({super.key, required this.block});

  final MdCodeBlock block;

  @override
  Widget build(BuildContext context) {
    final s = MdRenderScope.of(context).style;
    final t = s.tokens;
    final hasLanguage = (block.language ?? '').isNotEmpty;
    final copy = IconButton(
      key: MarkdownKeys.codeCopy(block.index),
      tooltip: MdStrings.codeCopy,
      visualDensity: VisualDensity.compact,
      icon: AppIcon(AppIconKind.copyText, size: 18, color: t.textSecondary),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: block.code));
        if (!context.mounted) return;
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text(MdStrings.copied)));
      },
    );
    Widget code(EdgeInsets padding) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Text(
        block.code,
        softWrap: false,
        style: s.codeBlock.copyWith(color: t.textPrimary),
      ),
    );
    return Container(
      key: MarkdownKeys.code(block.index),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.radiusMedium),
        border: Border.all(color: t.hairline),
      ),
      child: hasLanguage
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 14, right: 2, top: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          block.language!,
                          style: s.small.copyWith(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      copy,
                    ],
                  ),
                ),
                code(const EdgeInsets.fromLTRB(14, 0, 14, 14)),
              ],
            )
          // No language: no empty header line — [복사] sits beside the code.
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: code(const EdgeInsets.fromLTRB(14, 12, 8, 14))),
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 2),
                  child: copy,
                ),
              ],
            ),
    );
  }
}
