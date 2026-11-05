// lib/src/viewport/page_viewport.dart — 04-editor 6.4.1, 6.4.3 (E-04).
//
// E-04: page placement and virtualization. The input Listener
// (RawGestureDetector + Listener → InputRouter) and the overlays (selection
// frame, cursor, menus, page indicator, add-page button, …) are added by
// E-08..E-17 around the page stack built here.
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../scope/editor_scope.dart';
import 'editor_page_view.dart';
import 'viewport_controller.dart';

/// The page area: reports its size to the ViewportController and places the
/// mounted pages (visible ±1, at most 8 — 6.4.1) at screen coordinates.
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
    final camera = _cameraOf(viewport);
    final background = Theme.of(context).colorScheme.surfaceContainer;
    return ColoredBox(
      color: background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _reportSize(viewport, constraints.biggest);
          return ClipRect(
            child: ListenableBuilder(
              listenable: camera,
              builder: (context, _) => _buildPages(viewport),
            ),
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
