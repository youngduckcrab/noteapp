// lib/src/dnd/library_drag_scope.dart — 05-library 6.10.4: what happens
// around a drag (above every LibraryDraggable of the screen): edge auto
// scrolling of the registered lists and the drawer opening at the left
// screen edge. LibraryDraggable forwards its pointer here
// (Draggable.onDragUpdate — an outer DragTarget would stop getting onMove as
// soon as an inner target accepts).
import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

import '../ui/layout/library_metrics.dart';
import 'edge_auto_scroller.dart';

class LibraryDragScope extends StatefulWidget {
  const LibraryDragScope({
    super.key,
    required this.child,
    this.onDrawerEdgeHold,
  });

  final Widget child;

  /// Called after the pointer stayed within 24 px of the left screen edge for
  /// 600 ms during a drag (medium/compact: opens the drawer).
  final VoidCallback? onDrawerEdgeHold;

  static LibraryDragScopeState of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No LibraryDragScope above this widget');
    return scope!;
  }

  static LibraryDragScopeState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<LibraryDragScopeState>();

  /// Whether a LibraryDraggable drag runs (false without a scope).
  static ValueListenable<bool> draggingOf(BuildContext context) =>
      maybeOf(context)?.dragging ?? _never;

  static final ValueNotifier<bool> _never = ValueNotifier<bool>(false);

  @override
  State<LibraryDragScope> createState() => _LibraryDragScopeState();
}

abstract class LibraryDragScopeState extends State<LibraryDragScope> {
  void registerRegion(AutoScrollRegionState region);
  void unregisterRegion(AutoScrollRegionState region);

  /// A drag started (before Draggable.onDragStarted's own work).
  void dragStart();
  void dragUpdate(Offset globalPosition);
  void dragEnd();

  /// True from dragStart to dragEnd: the content pane keeps the top bar
  /// (breadcrumb drop targets) and the grid keeps its layout while a drag
  /// that started selection mode runs.
  ValueListenable<bool> get dragging;
}

class _LibraryDragScopeState extends LibraryDragScopeState {
  final ValueNotifier<bool> _dragging = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get dragging => _dragging;

  /// Registration order: a later one (the drawer's tree) wins where regions
  /// overlap.
  final List<AutoScrollRegionState> _regions = [];

  /// The region the pointer was last in; it keeps scrolling (at full speed)
  /// while the pointer is above / below it.
  AutoScrollRegionState? _current;
  Timer? _edgeTimer;

  /// The edge hold fired for the current stay in the edge zone.
  bool _edgeFired = false;

  @override
  void registerRegion(AutoScrollRegionState region) {
    if (!_regions.contains(region)) _regions.add(region);
  }

  @override
  void unregisterRegion(AutoScrollRegionState region) {
    _regions.remove(region);
    if (identical(_current, region)) _current = null;
  }

  @override
  void dragStart() => _dragging.value = true;

  @override
  void dragUpdate(Offset globalPosition) {
    _updateRegions(globalPosition);
    _updateDrawerEdge(globalPosition);
  }

  void _updateRegions(Offset p) {
    AutoScrollRegionState? inside;
    for (final region in _regions.reversed) {
      final rect = region.globalRect;
      if (rect != null && rect.contains(p)) {
        inside = region;
        break;
      }
    }
    if (inside != null) {
      _current = inside;
    } else {
      final rect = _current?.globalRect;
      if (rect == null || p.dx < rect.left || p.dx > rect.right) {
        _current = null;
      }
    }
    for (final region in _regions) {
      final rect = region.globalRect;
      if (identical(region, _current) && rect != null) {
        region.scroller.update(p, rect);
      } else {
        region.scroller.stop();
      }
    }
  }

  void _updateDrawerEdge(Offset p) {
    final hold = widget.onDrawerEdgeHold;
    final box = context.findRenderObject();
    final inZone =
        hold != null &&
        box is RenderBox &&
        box.hasSize &&
        box.globalToLocal(p).dx < LibraryMetrics.drawerEdgeZone;
    if (!inZone) {
      _cancelEdge();
      return;
    }
    if (_edgeTimer != null || _edgeFired) return;
    _edgeTimer = Timer(LibraryMetrics.drawerEdgeDelay, () {
      _edgeTimer = null;
      _edgeFired = true;
      if (mounted) widget.onDrawerEdgeHold?.call();
    });
  }

  void _cancelEdge() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _edgeFired = false;
  }

  @override
  void dragEnd() {
    for (final region in _regions) {
      region.scroller.stop();
    }
    _current = null;
    _cancelEdge();
    _dragging.value = false;
  }

  @override
  void dispose() {
    _cancelEdge();
    _dragging.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A scroll view that scrolls by itself while a drag pointer is near its
/// top / bottom edge (registered with the LibraryDragScope above it).
class AutoScrollRegion extends StatefulWidget {
  const AutoScrollRegion({
    super.key,
    required this.controller,
    required this.child,
  });

  /// The controller of the scroll view in [child].
  final ScrollController controller;
  final Widget child;

  @override
  State<AutoScrollRegion> createState() => AutoScrollRegionState();
}

class AutoScrollRegionState extends State<AutoScrollRegion>
    with TickerProviderStateMixin {
  late EdgeAutoScroller _scroller;
  LibraryDragScopeState? _scope;

  EdgeAutoScroller get scroller => _scroller;

  /// Global rect of this region; null while it has no layout.
  Rect? get globalRect {
    if (!mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void initState() {
    super.initState();
    _scroller = EdgeAutoScroller(controller: widget.controller, vsync: this);
    _scope = LibraryDragScope.maybeOf(context);
    _scope?.registerRegion(this);
  }

  @override
  void didUpdateWidget(AutoScrollRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _scroller.dispose();
      _scroller = EdgeAutoScroller(controller: widget.controller, vsync: this);
    }
  }

  @override
  void dispose() {
    _scope?.unregisterRegion(this);
    _scroller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
