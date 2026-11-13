// lib/src/viewport/page_viewport.dart — 04-editor 6.4.1, 6.4.3, 6.5.1.
//
// Page placement and virtualization (E-04), the input Listener that feeds the
// InputRouter and the hover cursor layer (E-08), the selection frame, the
// selection menu and the context menu (E-10), the canvas focus (E-12 — P / E /
// L, focused again by a pointer down), the eyedropper banner (E-14), the
// add-page button, the page indicator and the page panel (E-17), the
// developer overlay (E-19) — 6.4.3 tree. (v2, E2-01) The inline text editor
// and the sheet-mode text panel (m5-7/04-editor 6.11.3, 6.11.6). (E2-10) The
// canvas joins the editor's tap group while a text session is open
// (TextFieldTapRegion — a canvas down is not the editor's onTapOutside; the
// router decides, 6.11.5) and the new text box outline (6.11.1). (E2-19) The
// position flash (6.16). (E2-18) The Apple Pencil events while the viewport
// is on screen (StylusExtrasListener — 6.5.1).
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../input/editor_shortcuts.dart';
import '../input/input_router.dart';
import '../scope/editor_scope.dart';
import '../stylus/stylus_extras_listener.dart';
import '../text/text_box_editor.dart';
import '../text/text_edit_session.dart';
import '../text/text_input_sheet.dart';
import '../ui/dev/dev_overlay.dart';
import '../ui/overlays/add_page_button.dart';
import '../ui/overlays/context_menu.dart';
import '../ui/overlays/cursor_painter.dart';
import '../ui/overlays/eyedropper_banner.dart';
import '../ui/overlays/focus_flash.dart';
import '../ui/overlays/math_pen_layer.dart';
import '../ui/overlays/new_text_box_outline.dart';
import '../ui/overlays/page_indicator.dart';
import '../ui/overlays/pull_to_add_page_indicator.dart';
import '../ui/overlays/rotation_label.dart';
import '../ui/overlays/selection_frame_painter.dart';
import '../ui/overlays/selection_menu.dart';
import '../ui/overlays/text_pen_layer.dart';
import '../ui/pages/page_panel.dart';
import 'editor_page_view.dart';
import 'viewport_controller.dart';

/// The page area: reports its size to the ViewportController and places the
/// mounted pages (visible ±1, at most 8 — 6.4.1) at screen coordinates.
/// Every pointer event over it goes to the note's InputRouter (6.5.1); an
/// EagerGestureRecognizer wins the gesture arena against ancestor recognizers
/// (route back swipe). The hover cursor is painted above the pages.
///
/// The viewport size reaches the controller one post-frame callback after a
/// layout with a new size (the controller notifies listeners outside this
/// subtree, which must not be marked dirty during layout). Until the first
/// size arrives no page is placed.
class PageViewport extends ConsumerStatefulWidget {
  const PageViewport({super.key});

  @override
  ConsumerState<PageViewport> createState() => _PageViewportState();
}

class _PageViewportState extends ConsumerState<PageViewport> {
  ViewportController? _viewport;
  Listenable? _camera;
  Size? _pendingSize;

  /// EditorPageView instances by page id, reused while their inputs stay the
  /// same (6.4.3: scrolling does not rebuild the pages).
  final Map<String, EditorPageView> _views = {};

  Listenable _cameraOf(ViewportController v) {
    if (!identical(v, _viewport)) {
      _viewport = v;
      _camera = Listenable.merge([v, v.settledScale, v.isInteracting]);
      _views.clear();
      _pendingSize = null;
    }
    return _camera!;
  }

  void _reportSize(ViewportController viewport, Size size) {
    if (!size.isFinite || size == viewport.viewportSize) {
      _pendingSize = null;
      return;
    }
    if (_pendingSize != null) {
      _pendingSize = size; // a callback is already scheduled
      return;
    }
    _pendingSize = size;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final pending = _pendingSize;
      _pendingSize = null;
      if (!mounted || pending == null || !identical(_viewport, viewport)) {
        return;
      }
      viewport.updateViewportSize(pending);
    });
  }

  EditorPageView _viewFor(core.Page page, int index, double settledScale) {
    final cached = _views[page.id];
    if (cached != null &&
        cached.page.size == page.size &&
        cached.pageIndex == index &&
        cached.settledScale == settledScale) {
      return cached;
    }
    return _views[page.id] = EditorPageView(
      key: ValueKey(page.id),
      page: page,
      pageIndex: index,
      settledScale: settledScale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = ref.watch(editorViewportProvider);
    final router = ref.watch(editorInputRouterProvider);
    final host = ref.watch(editorInteractionHostProvider);
    final camera = _cameraOf(viewport);
    final scheme = Theme.of(context).colorScheme;
    // (v2, 6.11.3 '탭 묶음') only while a session is open — else the 1st
    // round (other text fields' onTapOutside on a canvas down).
    final editing = ref.watch(editorTextEditProvider.select((s) => s != null));
    return ColoredBox(
      color: scheme.surfaceContainer,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _reportSize(viewport, constraints.biggest);
          return Stack(
            fit: StackFit.expand,
            children: [
              TextFieldTapRegion(
                enabled: editing,
                child: EditorCanvasFocus(
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    gestures: const {EagerGestureRecognizer: _eagerFactory},
                    child: _InputListener(
                      router: router,
                      // (v2, E2-18) hover poses → viewport coordinates of
                      // this box (6.5.3).
                      child: StylusExtrasListener(
                        child: ClipRect(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ListenableBuilder(
                                listenable: camera,
                                builder: (context, _) => _buildPages(viewport),
                              ),
                              const SelectionFrame(),
                              // (v2, E2-06) the angle tag of a rotate drag
                              // (6.6.6).
                              const RotationLabel(),
                              // (v2, E2-10) the text tool's new box (6.11.1).
                              const NewTextBoxOutline(),
                              // (v2, E2-19) the position flash (6.16).
                              const FocusFlash(),
                              IgnorePointer(
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    painter: CursorPainter(
                                      cursor: host.cursor,
                                      ringColor: scheme.onSurface.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Siblings of the Listener: their taps never reach the router.
              // (v2, E2-01) The text editor over its box (6.11.3).
              const TextBoxEditorLayer(),
              // (math pen, phase 1) the bubble and the formula menu.
              const MathPenLayer(),
              // (text pen, phase 1) its bubble.
              const TextPenLayer(),
              const SelectionMenu(),
              const EditorContextMenu(),
              const AddPageButton(),
              // (04-editor 6.11.7) the strip a pull past the document end reveals.
              const PullToAddPageIndicator(),
              const PageIndicator(),
              const EyedropperBanner(),
              const PagePanel(),
              // (v2, E2-01) Sheet-mode text input at the top (6.11.6 A).
              const TextInputSheet(),
              const DevOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPages(ViewportController viewport) {
    final range = viewport.mountedRange;
    if (range == null) {
      _views.clear();
      return const SizedBox.expand();
    }
    final camera = viewport.camera;
    final settled = viewport.settledScale.value;
    final pages = viewport.pages;
    final layout = viewport.layout;
    final keep = <String>{};
    final slots = <Widget>[];
    for (var i = range.first; i <= range.last; i++) {
      final page = pages[i];
      final rect = layout.rectOf(i);
      final topLeft = camera.docToScreen(rect.topLeft);
      keep.add(page.id);
      slots.add(
        Positioned(
          key: ValueKey(page.id),
          left: topLeft.dx,
          top: topLeft.dy,
          width: rect.width * settled,
          height: rect.height * settled,
          // ≠ 1 only while a pinch / zoom animation has not settled (6.4.3).
          child: Transform.scale(
            scale: camera.scale / settled,
            alignment: Alignment.topLeft,
            child: _viewFor(page, i, settled),
          ),
        ),
      );
    }
    _views.removeWhere((id, _) => !keep.contains(id));
    return Stack(clipBehavior: Clip.none, children: slots);
  }
}

const _eagerFactory = _EagerFactory();

/// Factory of the EagerGestureRecognizer in front of the page area.
final class _EagerFactory
    extends GestureRecognizerFactory<EagerGestureRecognizer> {
  const _EagerFactory();

  @override
  EagerGestureRecognizer constructor() => EagerGestureRecognizer();

  @override
  void initializer(EagerGestureRecognizer instance) {}
}

/// Raw pointer events → InputRouter.handlePointerEvent (positions are local to
/// the page area = viewport coordinates).
class _InputListener extends StatelessWidget {
  const _InputListener({required this.router, required this.child});

  final InputRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final handle = router.handlePointerEvent;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: handle,
      onPointerMove: handle,
      onPointerUp: handle,
      onPointerCancel: handle,
      onPointerHover: handle,
      onPointerSignal: handle,
      onPointerPanZoomStart: handle,
      onPointerPanZoomUpdate: handle,
      onPointerPanZoomEnd: handle,
      child: child,
    );
  }
}
