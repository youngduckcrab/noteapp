// lib/src/ui/math_pad_canvas.dart — (internal) m5-7/05-library 6.14.2: the
// math pad's handwriting area.
//
// - A temporary page (core.Page 'mathpad_<id>', blank background, size = the
//   area in logical px — pt = logical px, viewScale 1) that is NEVER stored.
//   Its strokes live in [MathPadInk] (the sheet's state); every change goes
//   to the INK controller as InkPageContent.fromCore(…, revision: ++rev).
// - The controller is ref.watch(ink.inkPageControllerProvider(pageId)) — INK
//   does not subscribe the store (05-library 5.3); it is released with the
//   sheet (autoDispose).
// - Input: Listener → InkSampleAdapter.fromPointerEvent(pagePosition:
//   localPosition) → beginStroke(ballpoint defaults, viewScale 1,
//   ShapeAssist.off — a formula stroke must never become a shape) →
//   addSample → end() → the InkEdit's strokes join the list. A down counts
//   only with the primary button bit (web pen contact, E-4). Once a pen
//   came, fingers are ignored (the 1차 EDITOR pen-only rule, simplified).
//   One pointer at a time.
// - Eraser mode: beginErase(stroke eraser) → the InkEdit's removedIds leave
//   the list. Undo = drop the last stroke, clear = empty (no commands, no
//   history — the area is not saved); those are the sheet's buttons.
// - The area claims vertical drags so a downward stroke does not drag the
//   bottom sheet closed.
import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

/// Appendix C key of the handwriting area.
const ValueKey<String> kMathPadCanvasKey = ValueKey('recog.pad.canvas');

/// The area's height: 40% of the sheet's height, at least 140 px (6.14.1).
const double kMathPadCanvasHeightFactor = 0.4;
const double kMathPadCanvasMinHeight = 140;

/// The stroke eraser's radius (pt = logical px on the temporary page).
const double kMathPadEraserRadius = 8;

/// The temporary page's id prefix (6.14.2).
const String kMathPadPagePrefix = 'mathpad_';

/// The strokes of the pad's temporary page (never stored) and the eraser
/// switch. Listeners hear every change.
final class MathPadInk extends ChangeNotifier {
  List<core.Stroke> _strokes = const [];
  bool _erasing = false;

  /// In the order they were drawn (= core.Stroke.compareOrder).
  List<core.Stroke> get strokes => _strokes;
  bool get isEmpty => _strokes.isEmpty;

  /// Eraser mode: a contact erases whole strokes instead of drawing.
  bool get erasing => _erasing;
  set erasing(bool value) {
    if (value == _erasing) return;
    _erasing = value;
    notifyListeners();
  }

  void add(Iterable<core.Stroke> strokes) {
    final added = strokes.toList(growable: false);
    if (added.isEmpty) return;
    _strokes = List.unmodifiable([..._strokes, ...added]);
    notifyListeners();
  }

  /// Removes the strokes with [ids]; whether anything went.
  bool remove(Set<String> ids) {
    final kept = [
      for (final s in _strokes)
        if (!ids.contains(s.id)) s,
    ];
    if (kept.length == _strokes.length) return false;
    _strokes = List.unmodifiable(kept);
    notifyListeners();
    return true;
  }

  /// Drops the last stroke; whether there was one.
  bool undo() {
    if (_strokes.isEmpty) return false;
    _strokes = List.unmodifiable(_strokes.sublist(0, _strokes.length - 1));
    notifyListeners();
    return true;
  }

  /// Drops every stroke; whether there was one.
  bool clear() {
    if (_strokes.isEmpty) return false;
    _strokes = const [];
    notifyListeners();
    return true;
  }
}

/// The handwriting area of the pad (6.14.2) on the temporary page [pageId].
class MathPadCanvas extends ConsumerStatefulWidget {
  const MathPadCanvas({
    super.key,
    required this.ink,
    required this.pageId,
    required this.noteId,
    required this.createdAt,
    required this.height,
    this.onContact,
    this.onEdited,
  });

  final MathPadInk ink;
  final String pageId;
  final String noteId;
  final core.EpochMillis createdAt;
  final double height;

  /// A pen (or finger, before any pen) touched the area — draw or erase.
  final VoidCallback? onContact;

  /// A gesture changed the strokes (a stroke added, strokes erased).
  final VoidCallback? onEdited;

  @override
  ConsumerState<MathPadCanvas> createState() => _MathPadCanvasState();
}

class _MathPadCanvasState extends ConsumerState<MathPadCanvas> {
  ink.InkPageController? _controller;
  core.PageSize? _size;
  int _revision = 0;
  bool _pushScheduled = false;

  int? _pointer;
  ink.InkGestureSession? _session;
  bool _penSeen = false;

  @override
  void initState() {
    super.initState();
    widget.ink.addListener(_push);
  }

  @override
  void didUpdateWidget(MathPadCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.ink, widget.ink)) {
      oldWidget.ink.removeListener(_push);
      widget.ink.addListener(_push);
      _schedulePush();
    }
  }

  @override
  void dispose() {
    widget.ink.removeListener(_push);
    _session?.cancel();
    _session = null;
    super.dispose();
  }

  /// The current strokes and page size to the controller (not during build).
  void _push() {
    final controller = _controller;
    final size = _size;
    if (controller == null || size == null || !mounted) return;
    final page = core.Page(
      id: widget.pageId,
      noteId: widget.noteId,
      sortKey: 'a0',
      size: size,
      background: const core.BlankBackground(),
      createdAt: widget.createdAt,
      updatedAt: widget.createdAt,
    );
    controller.updateContent(
      ink.InkPageContent.fromCore(
        page: page,
        strokes: widget.ink.strokes,
        revision: ++_revision,
      ),
    );
  }

  void _schedulePush() {
    if (_pushScheduled) return;
    _pushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pushScheduled = false;
      _push();
    });
  }

  void _down(PointerDownEvent event) {
    final controller = _controller;
    if (controller == null || _pointer != null) return;
    if (event.buttons & kPrimaryButton == 0) return; // hover / other button
    final isPen =
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    if (isPen) {
      _penSeen = true;
    } else if (_penSeen && event.kind == PointerDeviceKind.touch) {
      return; // a pen came: fingers rest on the screen
    }
    final sample = ink.InkSampleAdapter.fromPointerEvent(
      event,
      pagePosition: event.localPosition,
    );
    _pointer = event.pointer;
    widget.onContact?.call();
    _session = widget.ink.erasing
        ? controller.beginErase(
            sample,
            spec: const ink.EraserSpec(
              mode: ink.EraserMode.stroke,
              radius: kMathPadEraserRadius,
            ),
            viewScale: 1,
          )
        : controller.beginStroke(
            sample,
            style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
            viewScale: 1,
            shapeAssist: ink.ShapeAssist.off,
          );
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final sample = ink.InkSampleAdapter.fromPointerEvent(
      event,
      pagePosition: event.localPosition,
    );
    switch (_session) {
      case final ink.StrokeSession s when s.isActive:
        s.addSample(sample);
      case final ink.EraserSession s when s.isActive:
        s.addSample(sample);
      default:
        break;
    }
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final session = _session;
    _session = null;
    final sample = ink.InkSampleAdapter.fromPointerEvent(
      event,
      pagePosition: event.localPosition,
    );
    switch (session) {
      case final ink.StrokeSession s when s.isActive:
        final edit = s.end(sample);
        if (edit != null && edit.added.isNotEmpty) {
          widget.ink.add(edit.added);
          widget.onEdited?.call();
        }
      case final ink.EraserSession s when s.isActive:
        final edit = s.end(sample);
        if (edit != null && widget.ink.remove(edit.removedIds)) {
          widget.onEdited?.call();
        } else {
          _push(); // nothing left the list: drop the controller's pending edit
        }
      default:
        break;
    }
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _session?.cancel();
    _session = null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(ink.inkPageControllerProvider(widget.pageId));
    if (!identical(controller, _controller)) {
      _controller = controller;
      _schedulePush();
    }
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: kMathPadCanvasKey,
      height: widget.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = core.PageSize(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                if (size != _size) {
                  _size = size;
                  _schedulePush();
                }
                return GestureDetector(
                  // wins the vertical drag over the sheet's drag-to-close
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) {},
                  onVerticalDragUpdate: (_) {},
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _down,
                    onPointerMove: _move,
                    onPointerUp: _up,
                    onPointerCancel: _cancel,
                    child: ink.InkPageView(controller: controller),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// recog.toMath's read-only strokes view (6.15.3): the chosen strokes on a
/// temporary page (math_png.dart mathAreaPage — moved to the area's top-left,
/// never stored), scaled to fit [height] keeping the page's aspect ratio. No
/// input.
class MathStrokesView extends ConsumerStatefulWidget {
  const MathStrokesView({
    super.key,
    required this.page,
    required this.strokes,
    required this.height,
  });

  final core.Page page;
  final List<core.Stroke> strokes;
  final double height;

  @override
  ConsumerState<MathStrokesView> createState() => _MathStrokesViewState();
}

class _MathStrokesViewState extends ConsumerState<MathStrokesView> {
  ink.InkPageController? _controller;
  int _revision = 0;

  void _schedulePush() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _controller;
      if (!mounted || controller == null) return;
      controller.updateContent(
        ink.InkPageContent.fromCore(
          page: widget.page,
          strokes: widget.strokes,
          revision: ++_revision,
        ),
      );
    });
  }

  @override
  void didUpdateWidget(MathStrokesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page ||
        !identical(oldWidget.strokes, widget.strokes)) {
      _schedulePush();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(ink.inkPageControllerProvider(widget.page.id));
    if (!identical(controller, _controller)) {
      _controller = controller;
      _schedulePush();
    }
    final size = widget.page.size;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: kMathStrokesViewKey,
      height: widget.height,
      child: Center(
        child: AspectRatio(
          aspectRatio: size.width / size.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: IgnorePointer(
              child: ink.InkPageView(controller: controller),
            ),
          ),
        ),
      ),
    );
  }
}

/// The read-only strokes view's key (not appendix C).
const ValueKey<String> kMathStrokesViewKey = ValueKey('recog.sheet.strokes');

/// The read-only strokes view's height (logical px).
const double kMathStrokesViewHeight = 96;
