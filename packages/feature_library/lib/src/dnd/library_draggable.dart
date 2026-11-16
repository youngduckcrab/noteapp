// lib/src/dnd/library_draggable.dart — 05-library 6.10.1: the drag source of
// tiles, list rows and sidebar tree rows, and the card under the pointer.
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../l10n/library_strings.dart';
import '../ui/layout/library_metrics.dart';
import 'drag_payload.dart';
import 'library_drag_scope.dart';

/// `LongPressDraggable<LibraryDragHandle>` with LIBRARY defaults:
/// delay 400 ms, pointerDragAnchorStrategy, feedback = LibraryDragFeedback,
/// childWhenDragging = child at opacity 0.4, all pointer kinds (touch,
/// stylus, mouse), hapticFeedbackOnStart (default true; no-op on web).
/// Forwards onDragUpdate / onDragEnd to LibraryDragScope.
///
/// The dragged child stays the same element (an Opacity around it, not a
/// separate childWhenDragging widget), and asks its lazy list to keep it
/// alive while the drag runs (scrolled out of view by the edge auto scroll).
class LibraryDraggable extends StatefulWidget {
  const LibraryDraggable({
    super.key,
    required this.payloadBuilder,
    required this.feedbackBuilder,
    required this.child,
    this.onDragStarted,
    this.onLongPressReleased,
    this.enabled = true,
  });

  /// Wrapped in a new LibraryDragHandle on every build. Content tiles read the
  /// selection with ref.read and the display order from
  /// libraryContentProvider(section).value.
  final LibraryDragPayload Function() payloadBuilder;

  /// Draggable.feedback is also fixed at build time, so LibraryDraggable
  /// passes a small widget that calls this with handle.payload when the
  /// overlay builds it (after the drag started). Usually returns
  /// LibraryDragFeedback(payload: payload, ...).
  final Widget Function(LibraryDragPayload payload) feedbackBuilder;
  final Widget child;
  final VoidCallback? onDragStarted;

  /// Long press released without moving (< kTouchSlop from the down point)
  /// and not dropped: sidebar rows open their menu; content tiles do nothing
  /// more (they are already selected).
  final VoidCallback? onLongPressReleased;
  final bool enabled;

  @override
  State<LibraryDraggable> createState() => _LibraryDraggableState();
}

class _LibraryDraggableState extends State<LibraryDraggable>
    with AutomaticKeepAliveClientMixin {
  bool _dragging = false;

  /// Global position of the last pointer down on this widget.
  Offset? _down;

  /// Farthest the pointer got from [_down] during the running drag.
  double _maxDistance = 0;

  LibraryDragHandle? _handle;

  /// Captured at the drag start: the drag may end after this widget is gone.
  LibraryDragScopeState? _scope;

  @override
  bool get wantKeepAlive => _dragging;

  void _onStarted(LibraryDragHandle handle) {
    _handle = handle;
    _maxDistance = 0;
    _scope = LibraryDragScope.maybeOf(context)?..dragStart();
    setState(() => _dragging = true);
    updateKeepAlive();
    widget.onDragStarted?.call();
  }

  void _onUpdate(DragUpdateDetails details) {
    final down = _down;
    if (down != null) {
      _maxDistance = math.max(
        _maxDistance,
        (details.globalPosition - down).distance,
      );
    }
    _scope?.dragUpdate(details.globalPosition);
  }

  /// Both Draggable.onDragCompleted and onDraggableCanceled: unlike
  /// onDragEnd they also run when this widget is gone.
  void _onEnded() {
    final handle = _handle;
    _handle = null;
    _scope?.dragEnd();
    _scope = null;
    if (!_dragging) return;
    _dragging = false;
    if (!mounted) return;
    setState(() {});
    updateKeepAlive();
    if (handle != null && !handle.dropped && _maxDistance < kTouchSlop) {
      widget.onLongPressReleased?.call();
    }
  }

  @override
  void dispose() {
    if (_dragging) _scope?.dragEnd();
    _scope = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!widget.enabled) return widget.child;
    final handle = LibraryDragHandle(widget.payloadBuilder);
    final child = Opacity(
      opacity: _dragging ? LibraryMetrics.dragSourceOpacity : 1,
      child: widget.child,
    );
    return Listener(
      onPointerDown: (event) => _down = event.position,
      child: LongPressDraggable<LibraryDragHandle>(
        data: handle,
        delay: LibraryMetrics.longPressDelay,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        maxSimultaneousDrags: 1,
        feedback: _LazyFeedback(
          handle: handle,
          builder: widget.feedbackBuilder,
        ),
        onDragStarted: () => _onStarted(handle),
        onDragUpdate: _onUpdate,
        onDragCompleted: _onEnded,
        onDraggableCanceled: (_, _) => _onEnded(),
        child: child,
      ),
    );
  }
}

/// Builds the feedback from the handle when the overlay builds it.
class _LazyFeedback extends StatelessWidget {
  const _LazyFeedback({required this.handle, required this.builder});

  final LibraryDragHandle handle;
  final Widget Function(LibraryDragPayload payload) builder;

  @override
  Widget build(BuildContext context) => builder(handle.payload);
}

/// The card under a dragging pointer (6.10.1): 200 × 56, elevation 8, opacity
/// 0.92, `[icon][name]` for one item ([icon] / [label] of the pressed item),
/// `[content_copy]['항목 n개']` with two cards behind it for several. Drawn
/// above and to the left of the pointer so a finger does not hide it.
class LibraryDragFeedback extends StatelessWidget {
  const LibraryDragFeedback({
    super.key,
    required this.payload,
    this.icon,
    this.kind,
    required this.label,
    this.iconColor,
  }) : assert(icon != null || kind != null, 'an icon or a kind');

  final LibraryDragPayload payload;

  /// Of the pressed item (a one-item payload is always the pressed item): a
  /// folder's own icon (data, FolderIcons) …
  final IconData? icon;

  /// … or a meaning of the ui_kit icon table (a note).
  final AppIconKind? kind;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final count = payload.items.length;
    final many = count > 1;
    const w = LibraryMetrics.dragFeedbackWidth;
    const h = LibraryMetrics.dragFeedbackHeight;
    const shift = LibraryMetrics.dragFeedbackStackShift;
    final behind = many ? 2 : 0;
    final scheme = Theme.of(context).colorScheme;
    final color = many ? scheme.onSurface : iconColor ?? scheme.onSurface;
    final kind = this.kind;
    final front = _FeedbackCard(
      glyph: many
          ? Icon(Icons.content_copy, size: 24, color: color)
          : kind != null
          ? AppIcon(kind, size: 24, color: color)
          : Icon(icon, size: 24, color: color),
      label: many ? LibraryStrings.itemCount(count) : label,
    );
    return Transform.translate(
      offset: const Offset(
        -LibraryMetrics.dragFeedbackGapX,
        -LibraryMetrics.dragFeedbackGapY - h,
      ),
      child: Opacity(
        opacity: LibraryMetrics.dragFeedbackOpacity,
        child: SizedBox(
          width: w + behind * shift,
          height: h + behind * shift,
          child: Stack(
            children: [
              for (var i = behind; i > 0; i--)
                Positioned(
                  left: i * shift,
                  top: i * shift,
                  width: w,
                  height: h,
                  child: const _FeedbackCard(),
                ),
              Positioned(left: 0, top: 0, width: w, height: h, child: front),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({this.glyph, this.label});

  /// Both null: a card behind the front one.
  final Widget? glyph;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final glyph = this.glyph, label = this.label;
    return Material(
      elevation: LibraryMetrics.dragFeedbackElevation,
      color: scheme.surfaceContainerHigh,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: glyph == null || label == null
          ? const SizedBox.expand()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  glyph,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
