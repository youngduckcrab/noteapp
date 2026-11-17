// GFM tables (08-markdown 8.3, B-3): scroll sideways, header in w600 on `card`, the
// column alignment kept, columns between 48 and 320 px wide (longer cells wrap).
//
// A long table (over [kTableRowsAtOnce] rows) is not measured whole: IntrinsicColumnWidth
// lays every cell out twice, and a 500-row table took 4.4 s to show (review A7). Its
// column widths come from the header and the first [kTableSampleRows] rows (plain text
// measured once), and its rows are shown [kTableRowsAtOnce] at a time with [더 보기].
import 'package:material_ui/material_ui.dart';

import '../markdown_keys.dart';
import '../parse/md_document.dart' show plainOfInlines;
import '../parse/md_model.dart';
import '../strings_ko.dart';
import 'md_inline.dart';

/// Rows built at once (and per [더 보기]).
const int kTableRowsAtOnce = 100;

/// Rows measured for the column widths of a long table.
const int kTableSampleRows = 40;

class MdTableView extends StatefulWidget {
  const MdTableView({super.key, required this.table, required this.style});

  final MdTable table;

  /// Body text style (quoted text keeps its colour).
  final TextStyle style;

  @override
  State<MdTableView> createState() => _MdTableViewState();
}

class _MdTableViewState extends State<MdTableView> {
  int _shown = kTableRowsAtOnce;

  /// Fixed column widths of a long table (null: measured by the Table itself).
  List<double>? _widths;
  Object? _widthsFor;

  List<double> _measure(BuildContext context, TextStyle style) {
    final table = widget.table;
    final scaler = MediaQuery.textScalerOf(context);
    final columns = table.header.length;
    final widths = List<double>.filled(columns, 48);
    void fit(List<MdInline> cell, int c, TextStyle st) {
      final p = TextPainter(
        text: TextSpan(text: plainOfInlines(cell), style: st),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = (p.width + 20 + 1).clamp(48.0, 320.0);
      p.dispose();
      if (w > widths[c]) widths[c] = w;
    }

    final head = style.copyWith(fontWeight: FontWeight.w600, height: 1.45);
    for (var c = 0; c < columns; c++) {
      fit(table.header[c], c, head);
    }
    final body = style.copyWith(height: 1.45);
    for (final row in table.rows.take(kTableSampleRows)) {
      for (var c = 0; c < columns && c < row.length; c++) {
        fit(row[c], c, body);
      }
    }
    return widths;
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final style = widget.style;
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
    final long = table.rows.length > kTableRowsAtOnce;
    List<double>? widths;
    if (long) {
      final key = (table, style, MediaQuery.textScalerOf(context));
      if (_widthsFor != key) {
        _widths = _measure(context, style);
        _widthsFor = key;
      }
      widths = _widths;
    }
    final shown = long ? _shown.clamp(0, table.rows.length) : table.rows.length;
    final grid = SingleChildScrollView(
      key: MarkdownKeys.table(table.index),
      scrollDirection: Axis.horizontal,
      child: Table(
        columnWidths: widths == null
            ? null
            : {
                for (var c = 0; c < widths.length; c++)
                  c: FixedColumnWidth(widths[c]),
              },
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
          for (final row in table.rows.take(shown))
            TableRow(
              children: [
                for (var c = 0; c < columns; c++)
                  cell(c < row.length ? row[c] : const [], c),
              ],
            ),
        ],
      ),
    );
    if (shown >= table.rows.length) return grid;
    final rest = table.rows.length - shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        grid,
        const SizedBox(height: 4),
        TextButton(
          key: MarkdownKeys.tableMore(table.index),
          onPressed: () => setState(() => _shown += kTableRowsAtOnce),
          child: Text('${MdStrings.tableMore} · ${MdStrings.tableRest(rest)}'),
        ),
      ],
    );
  }
}
