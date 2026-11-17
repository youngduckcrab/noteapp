// The rendered view (08-markdown 8.3, 8.8, 8.11; B-3, B-11): a lazy ListView.builder of
// top-level blocks in a reading column (at most 720 px, centred; 16 px sides on a phone,
// 32 on a tablet), inside a SelectionArea. A long top-level list is split into slices of
// items so a 2,000-item list is never built at once. Jumping to a block (search landing,
// '#heading' links) jumps by an estimated offset, then refines and ensureVisible's it.
import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'package:ui_kit/ui_kit.dart';

import '../live/live_edit.dart';
import '../live/live_units.dart';
import '../markdown_keys.dart';
import '../parse/list_items.dart';
import '../parse/md_model.dart';
import '../strings_ko.dart';
import 'md_blocks.dart';
import 'md_inline.dart';
import 'md_style.dart';

/// Lists longer than this are split into slices of [kListSlice] items.
const int kListSplitAt = 40;
const int kListSlice = 20;

/// What a unit of the live view is besides drawn markdown.
enum MdUnitSpecial {
  none,

  /// The live block field (08-markdown 24).
  field,

  /// '눌러서 이어 쓰기' under the last block.
  addEnd,

  /// The empty document's '여기에 쓰세요'.
  placeholder,

  /// A footnote / link reference definition chip.
  definition,
}

/// One child of the view's list.
@immutable
final class MdUnit {
  const MdUnit({
    required this.block,
    required this.first,
    this.node,
    this.firstItem = 0,
    this.footnotes = false,
    this.live,
    this.special = MdUnitSpecial.none,
    this.gap = kBlockGap,
    this.widestNumber,
  });

  /// The live edit unit this child shows (tapping it opens that unit).
  final LiveUnit? live;
  final MdUnitSpecial special;

  /// Space under the unit.
  final double gap;

  /// For one item of an ordered list: the list's last number (aligned numbers).
  final int? widestNumber;

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

/// The live view's state of one [MdView] (08-markdown 24): null = draw only.
@immutable
final class MdLiveView {
  const MdLiveView({
    required this.layout,
    required this.active,
    required this.field,
    required this.onTapUnit,
    required this.onAddEnd,
    this.onPointerDownUnit,
    this.onTapOutside,
  });

  /// A tap in the view that no unit, link, box or field took (the margins, the space
  /// below the document): the open block closes (24.4 '밖 누름 = 확정').
  final VoidCallback? onTapOutside;

  /// A pointer went down on a unit (before a link inside it takes the tap).
  final void Function(LiveUnit unit)? onPointerDownUnit;

  /// The edit units of the drawn parse.
  final LiveLayout layout;

  /// The range the open field replaces (of [layout]'s source), or null.
  final LiveRange? active;

  /// Builds the open field.
  final WidgetBuilder field;

  /// A unit was tapped at [global] (its context gives the drawn text there).
  final void Function(LiveUnit unit, Offset global, BuildContext context)
  onTapUnit;

  /// '눌러서 이어 쓰기' (or the empty document's placeholder).
  final VoidCallback onAddEnd;
}

/// The units of the live view: list blocks one unit per top-level item, definitions as
/// chips, the units under [active] replaced by one field, an [addEnd] row last.
({List<MdUnit> units, List<int> blockUnit}) liveUnitsOf(
  LiveLayout layout,
  LiveRange? active,
) {
  final doc = layout.doc;
  final units = <MdUnit>[];
  final blockUnit = <int>[];
  var fieldPlaced = false;
  bool covered(int start, int end) =>
      active != null &&
      !active.pending &&
      start < active.end &&
      end > active.start;
  void field(int block) {
    if (fieldPlaced) return;
    fieldPlaced = true;
    units.add(
      MdUnit(
        block: block,
        first: blockUnit[block] == units.length,
        special: MdUnitSpecial.field,
      ),
    );
  }

  // A new block between blocks (Enter at the end / start of one — 24.17 L′1): the field
  // goes in front of the first unit at or after its place.
  void pendingBefore(int start, int block) {
    if (fieldPlaced ||
        active == null ||
        !active.pending ||
        start < active.start) {
      return;
    }
    fieldPlaced = true;
    units.add(MdUnit(block: block, first: false, special: MdUnitSpecial.field));
  }

  for (var b = 0; b < doc.blocks.length; b++) {
    final block = doc.blocks[b];
    pendingBefore(block.start, b > 0 ? b - 1 : 0);
    blockUnit.add(units.length);
    final spans = layout.items[b];
    if (spans != null) {
      final items = blockListItems(block)!;
      final mine = layout.unitsOfBlock(b).toList();
      for (var i = 0; i < spans.length; i++) {
        if (i > 0) pendingBefore(spans[i].start, b);
        if (covered(spans[i].start, spans[i].end)) {
          field(b);
          continue;
        }
        final (list, item) = items[i];
        final k = list.items.indexOf(item);
        final last = i == spans.length - 1;
        final sameList = !last && identical(items[i + 1].$1, list);
        final nextTask = sameList && items[i + 1].$2.task != null;
        units.add(
          MdUnit(
            block: b,
            first: blockUnit[b] == units.length,
            node: MdList(
              ordered: list.ordered,
              start: list.start,
              items: [item],
            ),
            firstItem: k,
            live: mine[i],
            gap: !sameList ? kBlockGap : (nextTask ? 0 : 4),
            widestNumber: list.ordered
                ? list.start + list.items.length - 1
                : null,
          ),
        );
      }
      continue;
    }
    final unit = layout.unitsOfBlock(b).firstOrNull;
    if (covered(block.start, block.end) ||
        (active != null &&
            !active.pending &&
            block.start == block.end &&
            block.start == active.start)) {
      field(b);
      continue;
    }
    if (block.nodes.isEmpty) {
      units.add(
        MdUnit(
          block: b,
          first: true,
          live: unit,
          special: MdUnitSpecial.definition,
        ),
      );
      continue;
    }
    var first = true;
    for (final node in block.nodes) {
      if (node is MdList && node.items.length > kListSplitAt) {
        for (var i = 0; i < node.items.length; i += kListSlice) {
          final end = (i + kListSlice).clamp(0, node.items.length);
          units.add(
            MdUnit(
              block: b,
              first: first,
              firstItem: i,
              live: unit,
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
        units.add(MdUnit(block: b, first: first, node: node, live: unit));
        first = false;
      }
    }
  }
  if (active != null && !fieldPlaced) {
    // A new block at the end (or the empty document's first one).
    units.add(
      MdUnit(
        block: doc.blocks.length,
        first: false,
        special: MdUnitSpecial.field,
      ),
    );
  } else if (active == null) {
    units.add(
      MdUnit(
        block: doc.blocks.length,
        first: false,
        special: doc.blocks.isEmpty
            ? MdUnitSpecial.placeholder
            : MdUnitSpecial.addEnd,
      ),
    );
  }
  if (doc.footnotes.isNotEmpty) {
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
    final live = unit.live;
    if (live?.item != null) {
      lines = 1 + ((live!.end - live.start) / perLine).ceil();
    } else if (unit.node is MdList) {
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
    this.onStartEditing,
    this.live,
  });

  /// Live block editing (08-markdown 24); null draws only.
  final MdLiveView? live;

  final MdDocument document;
  final MdViewController controller;
  final void Function(MdLink link) onLink;
  final void Function(String label) onFootnote;
  final void Function(int task) onToggleTask;
  final bool Function(int task) canToggleTask;

  /// The block drawn highlighted (search landing); null for none.
  final int? highlightBlock;
  final Key listKey;

  /// An empty document shows [편집하기] calling this (null: the text alone).
  final VoidCallback? onStartEditing;

  @override
  State<MdView> createState() => _MdViewState();
}

class _MdViewState extends State<MdView> {
  late ({List<MdUnit> units, List<int> blockUnit}) _units;

  @override
  void initState() {
    super.initState();
    _units = _compute();
    _sync();
  }

  ({List<MdUnit> units, List<int> blockUnit}) _compute() {
    final live = widget.live;
    if (live == null) return unitsOf(widget.document);
    return liveUnitsOf(live.layout, live.active);
  }

  @override
  void didUpdateWidget(MdView old) {
    super.didUpdateWidget(old);
    final live = widget.live;
    final was = old.live;
    if (!identical(old.document, widget.document) ||
        (live == null) != (was == null) ||
        (live != null &&
            (!identical(live.layout, was!.layout) ||
                live.active != was.active))) {
      _units = _compute();
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
          if (units.isEmpty && widget.live == null) {
            return Center(
              key: widget.listKey,
              child: Padding(
                padding: EdgeInsets.all(pad),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      AppIconKind.markdownDoc,
                      size: 40,
                      color: style.tokens.textSecondary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      MdStrings.emptyDoc,
                      textAlign: TextAlign.center,
                      style: style.body.copyWith(
                        color: style.tokens.textSecondary,
                      ),
                    ),
                    if (widget.onStartEditing != null) ...[
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        key: MarkdownKeys.emptyEdit,
                        onPressed: widget.onStartEditing,
                        icon: const AppIcon(AppIconKind.editSource, size: 20),
                        label: const Text(MdStrings.emptyEdit),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          final fieldAt = units.indexWhere(
            (u) => u.special == MdUnitSpecial.field,
          );
          final outside = widget.live?.onTapOutside;
          return SelectionArea(
            child: _outside(
              outside,
              ListView.builder(
                key: widget.listKey,
                controller: widget.controller.scroll,
                padding: EdgeInsets.only(top: 20, bottom: 96),
                itemCount: units.length,
                // The open field is kept alive while scrolled away (_KeepAlive): it has its
                // own key, so its kept element moves with it and never stays behind under
                // a drawn unit — a kept-alive, unlaid-out paragraph inside the
                // SelectionArea broke selection after switching blocks (24.17 L′13).
                findChildIndexCallback: (key) {
                  if (key == _fieldItemKey) return fieldAt < 0 ? null : fieldAt;
                  if (key is ValueKey<int>) {
                    final i = key.value;
                    return i < units.length && i != fieldAt ? i : null;
                  }
                  return null;
                },
                itemBuilder: (context, u) => Align(
                  key: u == fieldAt ? _fieldItemKey : ValueKey<int>(u),
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: (kReadingWidth + 2 * pad).clamp(
                      0,
                      constraints.maxWidth,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(pad, 0, pad, units[u].gap),
                      child: _UnitSlot(
                        controller: widget.controller,
                        index: u,
                        child: _unit(units[u], style),
                      ),
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

  /// Taps that nothing inside the list takes (deeper recognizers win the arena).
  static Widget _outside(VoidCallback? onTap, Widget list) => onTap == null
      ? list
      : GestureDetector(
          key: MarkdownKeys.liveOutside,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: list,
        );

  Widget _unit(MdUnit unit, MdStyle style) {
    final live = widget.live;
    switch (unit.special) {
      case MdUnitSpecial.field:
        Widget field = _KeepAlive(
          // A tap on the field's frame is a tap on the field, not outside it.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: SelectionContainer.disabled(child: live!.field(context)),
          ),
        );
        if (unit.first && unit.block >= 0) {
          field = KeyedSubtree(
            key: MarkdownKeys.block(unit.block),
            child: field,
          );
        }
        return field;
      case MdUnitSpecial.addEnd:
      case MdUnitSpecial.placeholder:
        final placeholder = unit.special == MdUnitSpecial.placeholder;
        return _LiveRow(
          key: placeholder
              ? MarkdownKeys.livePlaceholder
              : MarkdownKeys.liveAddEnd,
          onTap: live!.onAddEnd,
          minHeight: placeholder ? 160 : 120,
          icon: placeholder ? null : AppIconKind.add,
          text: placeholder ? MdStrings.livePlaceholder : MdStrings.liveAddEnd,
          style: style,
        );
      case MdUnitSpecial.definition:
        final u = unit.live!;
        final src = live!.layout.doc.source.substring(u.start, u.end);
        final label = src.split('\n').first.trim();
        return _Tappable(
          unit: u,
          live: live,
          child: Container(
            key: MarkdownKeys.liveDefinition(unit.block),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: style.tokens.hairline),
              borderRadius: BorderRadius.circular(style.tokens.radiusSmall),
            ),
            child: Text(
              '${label.startsWith('[^') ? MdStrings.liveDefinition : MdStrings.liveLinkDefinition}  $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.small.copyWith(
                fontFamily: kMonoFamily,
                fontFamilyFallback: kMonoFallback,
              ),
            ),
          ),
        );
      case MdUnitSpecial.none:
        break;
    }
    Widget child;
    if (unit.footnotes) {
      child = MdFootnotesView(footnotes: widget.document.footnotes);
    } else {
      final node = unit.node!;
      child = node is MdList
          ? MdListView(
              list: node,
              firstItem: unit.firstItem,
              widestNumber: unit.widestNumber,
            )
          : MdNodeView(node: node);
    }
    if (live != null && unit.live != null) {
      child = _Tappable(unit: unit.live!, live: live, child: child);
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

const ValueKey<String> _fieldItemKey = ValueKey('md.view.fieldItem');

/// Keeps the open field alive while it is scrolled out of the list's cache (its
/// controller and focus live in the screen; 24.15 D′12).
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// A drawn unit that opens its live field on a tap (finger or pen). Taps on task
/// boxes, links, buttons inside win (they are deeper in the gesture arena).
class _Tappable extends StatelessWidget {
  const _Tappable({
    required this.unit,
    required this.live,
    required this.child,
  });

  final LiveUnit unit;
  final MdLiveView live;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => live.onPointerDownUnit?.call(unit),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => live.onTapUnit(unit, d.globalPosition, context),
      child: child,
    ),
  );
}

/// '눌러서 이어 쓰기' / '여기에 쓰세요'.
class _LiveRow extends StatelessWidget {
  const _LiveRow({
    super.key,
    required this.onTap,
    required this.minHeight,
    required this.text,
    required this.style,
    this.icon,
  });

  final VoidCallback onTap;
  final double minHeight;
  final String text;
  final MdStyle style;
  final AppIconKind? icon;

  @override
  Widget build(BuildContext context) {
    final t = style.tokens;
    return Semantics(
      button: true,
      label: text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    AppIcon(icon!, size: 18, color: t.textTertiary),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      text,
                      style: style.body.copyWith(color: t.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
