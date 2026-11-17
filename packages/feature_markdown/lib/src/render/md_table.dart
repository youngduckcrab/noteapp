// GFM tables (08-markdown 8.3, B-3): scroll sideways, header in w600 on `card`, the
// column alignment kept, columns between 48 and 320 px wide (longer cells wrap).
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';

import '../markdown_keys.dart';
import '../parse/md_model.dart';
import 'md_inline.dart';

class MdTableView extends StatelessWidget {
  const MdTableView({super.key, required this.table, required this.style});

  final MdTable table;

  /// Body text style (quoted text keeps its colour).
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final s = MdRenderScope.of(context).style;
    final t = s.tokens;
    final columns = table.header.length;
    TextAlign align(int c) =>
        switch (c < table.aligns.length ? table.aligns[c] : MdAlign.none) {
          MdAlign.center => TextAlign.center,
          MdAlign.right => TextAlign.right,
          _ => TextAlign.left,
        };
    Widget cell(List<MdInline> inl, int c, {bool head = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: MdRichText(
        inlines: inl,
        style: head
            ? style.copyWith(fontWeight: FontWeight.w600, height: 1.45)
            : style.copyWith(height: 1.45),
        textAlign: align(c),
      ),
    );
    return SingleChildScrollView(
      key: MarkdownKeys.table(table.index),
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const MinColumnWidth(
          MaxColumnWidth(IntrinsicColumnWidth(), FixedColumnWidth(48)),
          FixedColumnWidth(320),
        ),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        border: TableBorder.all(
          color: t.hairline,
          borderRadius: BorderRadius.circular(t.radiusSmall),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: t.card),
            children: [
              for (var c = 0; c < columns; c++)
                cell(table.header[c], c, head: true),
            ],
          ),
          for (final row in table.rows)
            TableRow(
              children: [
                for (var c = 0; c < columns; c++)
                  cell(c < row.length ? row[c] : const [], c),
              ],
            ),
        ],
      ),
    );
  }
}
