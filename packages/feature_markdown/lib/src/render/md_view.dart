// The rendered view (08-markdown 8.3, 8.8, 8.11; B-3, B-11): a lazy ListView.builder of
// top-level blocks in a reading column (at most 720 px, centred; 16 px sides on a phone,
// 32 on a tablet), inside a SelectionArea. A long top-level list is split into slices of
// items so a 2,000-item list is never built at once. Jumping to a block (search landing,
// '#heading' links) jumps by an estimated offset, then refines and ensureVisible's it.
import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../markdown_keys.dart';
import '../parse/md_model.dart';
import '../strings_ko.dart';
import 'md_blocks.dart';
import 'md_inline.dart';
import 'md_style.dart';

/// Lists longer than this are split into slices of [kListSlice] items.
const int kListSplitAt = 40;
const int kListSlice = 20;

/// One child of the view's list.
@immutable
final class MdUnit {
  const MdUnit({
    required this.block,
    required this.first,
    this.node,
    this.firstItem = 0,
    this.footnotes = false,
  });

  /// Index of the block in MdDocument.blocks (-1: the footnotes).
  final int block;

  /// The first unit of its block (carries MarkdownKeys.block).
  final bool first;
  final MdNode? node;

  /// For a list slice: the index of the slice's first item in the whole list.
  final int firstItem;
  final bool footnotes;
}

/// The units of [doc] and, for every block, its first unit.
({List<MdUnit> units, List<int> blockUnit}) unitsOf(MdDocument doc) {
  final units = <MdUnit>[];
  final blockUnit = <int>[];
  for (var b = 0; b < doc.blocks.length; b++) {
    blockUnit.add(units.length);
    var first = true;
    for (final node in doc.blocks[b].nodes) {
      if (node is MdList && node.items.length > kListSplitAt) {
        for (var i = 0; i < node.items.length; i += kListSlice) {
          final end = (i + kListSlice).clamp(0, node.items.length);
          units.add(
            MdUnit(
              block: b,
              first: first,
              firstItem: i,
              node: MdList(
                ordered: node.ordered,
                start: node.start,
                items: node.items.sublist(i, end),
              ),
            ),
          );
          first = false;
        }
      } else {
        units.add(MdUnit(block: b, first: first, node: node));
        first = false;
      }
    }
  }
  if (doc.footnotes.isNotEmpty) {
    // 'block' doc.blocks.length = the footnotes (revealBlock).
    blockUnit.add(units.length);
    units.add(const MdUnit(block: -1, first: true, footnotes: true));
  }
  return (units: units, blockUnit: blockUnit);
}

/// Scroll position helper of one [MdView].
class MdViewController {
  MdViewController() : scroll = ScrollController();

  final ScrollController scroll;
  final Map<int, BuildContext> _mounted = {};
  List<MdUnit> _units = const [];
  List<int> _blockUnit = const [];
  MdDocument _doc = MdDocument.empty;
  double _width = 720;

  void dispose() => scroll.dispose();

  /// Rough height of a unit before it is built (line count × line height).
  double _estimate(int u) {
    final unit = _units[u];
    if (unit.footnotes) return 80;
    final text = unit.block < 0 || unit.block >= _doc.blocks.length
        ? ''
        : _doc.blocks[unit.block].plainText;
    final perLine = (_width / 9).clamp(20, 200);
    var lines = 1;
    for (final l in text.split('\n')) {
      lines += (l.length / perLine).ceil().clamp(1, 1 << 20);
    }
    if (unit.node is MdList) {
      lines = (unit.node! as MdList).items.length + lines ~/ 4;
    }
    return lines * 25.6 + kBlockGap;
  }

  /// The index of the first block whose unit is (at least partly) on screen.
  int? firstVisibleBlock() {
    if (!scroll.hasClients) return null;
    final keys = _mounted.keys.toList()..sort();
    for (final u in keys) {
      final ctx = _mounted[u]!;
      if (!ctx.mounted) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) continue;
      final top = viewport.getOffsetToReveal(box, 0).offset;
      if (top + box.size.height > scroll.offset) return _units[u].block;
    }
    return null;
  }

  /// The first block on screen whose start is drawn (its first unit), and how far its
  /// top is below the top of the view (negative: scrolled past). null when none.
  ({int block, double dy})? topAnchor() {
    if (!scroll.hasClients) return null;
    final keys = _mounted.keys.toList()..sort();
    for (final u in keys) {
      final unit = _units[u];
      if (!unit.first || unit.block < 0) continue;
      final top = _topOf(u);
      if (top == null) continue;
      final box = _mounted[u]!.findRenderObject()! as RenderBox;
      if (top + box.size.height > scroll.offset) {
        return (block: unit.block, dy: top - scroll.offset);
      }
    }
    return null;
  }

  /// Scrolls so block [block]'s top is [dy] below the top of the view (see [topAnchor]).
  Future<void> restoreAnchor(int block, double dy) async {
    if (!await revealBlock(block)) return;
    final u = _blockUnit[block];
    final top = _topOf(u);
    if (top == null || !scroll.hasClients) return;
    final pos = scroll.position;
    pos.jumpTo((top - dy).clamp(pos.minScrollExtent, pos.maxScrollExtent));
  }

  double? _topOf(int u) {
    final ctx = _mounted[u];
    if (ctx == null || !ctx.mounted) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(box, 0).offset;
  }

  /// Brings block [block] into view (near the top); `doc.blocks.length` = the
  /// footnotes. False when it could not.
  Future<bool> revealBlock(int block) async {
    if (block < 0 || block >= _blockUnit.length) return false;
    final unit = _blockUnit[block];
    if (unit >= _units.length) return false;
    if (!scroll.hasClients) return false;
    // First jump: the estimated offset.
    if (!_mounted.containsKey(unit)) {
      var y = 0.0;
      for (var u = 0; u < unit; u++) {
        y += _estimate(u);
      }
      final pos = scroll.position;
      pos.jumpTo(y.clamp(pos.minScrollExtent, pos.maxScrollExtent));
      await _frame();
    }
    for (var attempt = 0; attempt < 16; attempt++) {
      final ctx = _mounted[unit];
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, alignment: 0.05);
        return true;
      }
      if (!scroll.hasClients) return false;
      final pos = scroll.position;
      final seen = _mounted.keys.toList()..sort();
      final avg =
          (pos.maxScrollExtent + pos.viewportDimension) /
          _units.length.clamp(1, 1 << 30);
      double target;
      if (seen.isEmpty) {
        target = 0;
      } else if (unit < seen.first) {
        target = pos.pixels - (seen.first - unit + 1) * avg;
      } else {
        target = pos.pixels + (unit - seen.last + 1) * avg;
      }
      final clamped = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (clamped == pos.pixels) {
        // At an end of the (estimated) extent: nudge.
        pos.jumpTo(
          (pos.pixels +
                  (unit < (seen.firstOrNull ?? 0) ? -1 : 1) *
                      pos.viewportDimension)
              .clamp(pos.minScrollExtent, pos.maxScrollExtent),
        );
      } else {
        pos.jumpTo(clamped);
      }
      await _frame();
    }
    return false;
  }

  Future<void> _frame() {
    SchedulerBinding.instance.scheduleFrame();
    return SchedulerBinding.instance.endOfFrame;
  }
}

class MdView extends StatefulWidget {
  const MdView({
    super.key,
    required this.document,
    required this.controller,
    required this.onLink,
    required this.onFootnote,
    required this.onToggleTask,
    required this.canToggleTask,
    this.highlightBlock,
    this.listKey = MarkdownKeys.view,
  });

  final MdDocument document;
  final MdViewController controller;
  final void Function(MdLink link) onLink;
  final void Function(String label) onFootnote;
  final void Function(int task) onToggleTask;
  final bool Function(int task) canToggleTask;

  /// The block drawn highlighted (search landing); null for none.
  final int? highlightBlock;
  final Key listKey;

  @override
  State<MdView> createState() => _MdViewState();
}

class _MdViewState extends State<MdView> {
  late ({List<MdUnit> units, List<int> blockUnit}) _units;

  @override
  void initState() {
    super.initState();
    _units = unitsOf(widget.document);
    _sync();
  }

  @override
  void didUpdateWidget(MdView old) {
    super.didUpdateWidget(old);
    if (!identical(old.document, widget.document)) {
      _units = unitsOf(widget.document);
    }
    _sync();
  }

  void _sync() {
    widget.controller
      .._units = _units.units
      .._blockUnit = _units.blockUnit
      .._doc = widget.document;
  }

  @override
  Widget build(BuildContext context) {
    final style = MdStyle.of(context);
    final units = _units.units;
    return MdRenderScope(
      style: style,
      onLink: widget.onLink,
      onFootnote: widget.onFootnote,
      onToggleTask: widget.onToggleTask,
      canToggleTask: widget.canToggleTask,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pad = MdStyle.sidePadding(constraints.maxWidth);
          widget.controller._width = (constraints.maxWidth - 2 * pad).clamp(
            100,
            kReadingWidth,
          );
          if (units.isEmpty) {
            return Center(
              key: widget.listKey,
              child: Padding(
                padding: EdgeInsets.all(pad),
                child: Text(
                  MdStrings.emptyDoc,
                  textAlign: TextAlign.center,
                  style: style.small,
                ),
              ),
            );
          }
          return SelectionArea(
            child: ListView.builder(
              key: widget.listKey,
              controller: widget.controller.scroll,
              padding: EdgeInsets.only(top: 20, bottom: 96),
              itemCount: units.length,
              itemBuilder: (context, u) => Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: (kReadingWidth + 2 * pad).clamp(
                    0,
                    constraints.maxWidth,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, kBlockGap),
                    child: _UnitSlot(
                      controller: widget.controller,
                      index: u,
                      child: _unit(units[u], style),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _unit(MdUnit unit, MdStyle style) {
    Widget child;
    if (unit.footnotes) {
      child = MdFootnotesView(footnotes: widget.document.footnotes);
    } else {
      final node = unit.node!;
      child = node is MdList
          ? MdListView(list: node, firstItem: unit.firstItem)
          : MdNodeView(node: node);
    }
    if (unit.block >= 0 && unit.block == widget.highlightBlock) {
      child = AnimatedContainer(
        key: unit.first ? MarkdownKeys.highlight : null,
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: style.tokens.accentSoft,
          borderRadius: BorderRadius.circular(style.tokens.radiusSmall),
          border: Border.all(color: style.tokens.accent, width: 1.5),
        ),
        padding: const EdgeInsets.all(6),
        child: child,
      );
    }
    if (unit.first && unit.block >= 0) {
      child = KeyedSubtree(key: MarkdownKeys.block(unit.block), child: child);
    }
    return child;
  }
}

/// Registers its context with the controller while mounted (for jumps).
class _UnitSlot extends StatefulWidget {
  const _UnitSlot({
    required this.controller,
    required this.index,
    required this.child,
  });

  final MdViewController controller;
  final int index;
  final Widget child;

  @override
  State<_UnitSlot> createState() => _UnitSlotState();
}

class _UnitSlotState extends State<_UnitSlot> {
  @override
  void initState() {
    super.initState();
    widget.controller._mounted[widget.index] = context;
  }

  @override
  void didUpdateWidget(_UnitSlot old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index || old.controller != widget.controller) {
      if (old.controller._mounted[old.index] == context) {
        old.controller._mounted.remove(old.index);
      }
      widget.controller._mounted[widget.index] = context;
    }
  }

  @override
  void dispose() {
    if (widget.controller._mounted[widget.index] == context) {
      widget.controller._mounted.remove(widget.index);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
