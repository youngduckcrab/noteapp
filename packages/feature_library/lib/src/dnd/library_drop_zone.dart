// lib/src/dnd/library_drop_zone.dart — 05-library 6.10.2 / 6.10.4: one drop
// target of the screen (tile, list row, sidebar row, breadcrumb crumb).
// DragTarget<LibraryDragHandle> that accepts every library drag
// (onWillAcceptWithDetails is always true — the real decision needs the
// position), decides in onMove with decideDrop, draws the highlight through
// [builder], and runs the decision on drop. A stay with the pointer
// (700 ms) can trigger [onHold]: the collapsed tree row expands, '…' of the
// breadcrumb opens its menu.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show LibrarySortField, folderTreeProvider;

import '../model/section.dart';
import '../state/providers.dart';
import '../ui/layout/library_metrics.dart';
import '../ui/library_scope.dart';
import '../ui/menus/item_action_flows.dart';
import 'drag_payload.dart';
import 'drop_decision.dart';

class LibraryDropZone extends ConsumerStatefulWidget {
  const LibraryDropZone({
    super.key,
    required this.target,
    required this.builder,
    this.onHold,
    this.holdNeedsDrop = true,
    this.onDropped,
  });

  /// null: no drop here, only [onHold] ('…' of the breadcrumb).
  final LibraryDropTarget? target;

  /// [decision] = what a drop at the pointer would do (null: nothing, no
  /// highlight).
  final Widget Function(BuildContext context, DropDecision? decision) builder;

  /// Called once after the pointer stayed LibraryMetrics.autoExpandDelay over
  /// this zone — with a DropInto decision when [holdNeedsDrop].
  final VoidCallback? onHold;
  final bool holdNeedsDrop;

  /// After a decision ran here (the hidden path menu closes).
  final VoidCallback? onDropped;

  @override
  ConsumerState<LibraryDropZone> createState() => _LibraryDropZoneState();
}

class _LibraryDropZoneState extends ConsumerState<LibraryDropZone> {
  DropDecision? _decision;
  Timer? _holdTimer;

  /// [LibraryDropZone.onHold] ran for the current stay.
  bool _held = false;

  DropDecision? _decide(DragTargetDetails<LibraryDragHandle> details) {
    final target = widget.target;
    if (target == null) return null;
    final tree = ref.read(folderTreeProvider).value;
    if (tree == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return decideDrop(
      payload: details.data.payload,
      target: target,
      tree: tree,
      customSort: target is TileDropTarget && _customSort(),
      localPosition: box.globalToLocal(details.offset),
      targetSize: box.size,
    );
  }

  /// The content is a folder section in the custom order.
  bool _customSort() {
    final route = LibraryScope.read(context).routeFolderId;
    return ref.read(librarySectionProvider(route)) is FolderSection &&
        ref.read(libraryPrefsProvider).sort.field == LibrarySortField.custom;
  }

  void _show(DropDecision? decision) {
    if (decision != _decision) setState(() => _decision = decision);
  }

  void _onMove(DragTargetDetails<LibraryDragHandle> details) {
    final decision = _decide(details);
    _show(decision);
    final wantsHold =
        widget.onHold != null &&
        (!widget.holdNeedsDrop || decision is DropInto);
    if (!wantsHold) {
      _cancelHold();
    } else if (_holdTimer == null && !_held) {
      _holdTimer = Timer(LibraryMetrics.autoExpandDelay, () {
        _holdTimer = null;
        _held = true;
        if (mounted) widget.onHold?.call();
      });
    }
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  void _reset() {
    _cancelHold();
    _held = false;
    _show(null);
  }

  void _onAccept(DragTargetDetails<LibraryDragHandle> details) {
    final decision = _decide(details);
    _reset();
    if (decision == null) return;
    final handle = details.data;
    handle.markDropped();
    runDropFlow(context, handle.payload, decision);
    widget.onDropped?.call();
  }

  @override
  void dispose() {
    _cancelHold();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<LibraryDragHandle>(
      onWillAcceptWithDetails: (_) => true,
      onMove: _onMove,
      onLeave: (_) => _reset(),
      onAcceptWithDetails: _onAccept,
      builder: (context, _, _) => widget.builder(context, _decision),
    );
  }
}
