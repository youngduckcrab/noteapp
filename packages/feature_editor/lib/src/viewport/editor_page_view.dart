// lib/src/viewport/editor_page_view.dart — 04-editor 6.4.3, 6.4.4 (E-04).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../document/mounted_pages.dart';
import '../document/page_mount.dart';
import '../playback/playback_highlighter.dart';
import '../scope/editor_scope.dart';
import '../state/tape_state.dart';
import '../tools/selection.dart';
import 'viewport_controller.dart';

/// One page: ink.InkPageView + a loading cover until the content is loaded.
///
/// State: keeps ink.inkPageControllerProvider(page.id) alive (listenManual —
/// the provider is autoDispose, so unmounting releases INK's caches, contract
/// E-2); creates a [PageMount] and registers it in editorMountedPagesProvider;
/// dispose unregisters and disposes the mount (session.closePage).
///
/// PageViewport reuses the same instance while (page.id, page.size,
/// settledScale, pageIndex) stay the same, so scrolling does not rebuild it.
/// The three InkPageView arguments that follow the camera (ancestorScale,
/// isScaling, visiblePageRect) come from a ListenableBuilder on the viewport
/// inside this widget. EDITOR never calls controller.setViewport — InkPageView
/// does (contract 7.2.15 v1.1).
class EditorPageView extends ConsumerStatefulWidget {
  const EditorPageView({
    super.key,
    required this.page,
    required this.pageIndex,
    required this.settledScale,
  });
  final core.Page page;
  final int pageIndex;
  final double settledScale;

  /// Key of the loading cover (shown while the page content is not loaded).
  static const Key loadingCoverKey = ValueKey('editor.pageLoadingCover');

  @override
  ConsumerState<EditorPageView> createState() => _EditorPageViewState();
}

class _EditorPageViewState extends ConsumerState<EditorPageView> {
  late core.NoteSession _session;
  late MountedPages _mountedPages;
  ProviderSubscription<ink.InkPageController>? _controllerSub;
  PageMount? _mount;

  @override
  void initState() {
    super.initState();
    _session = ref.read(editorSessionValueProvider);
    _mountedPages = ref.read(editorMountedPagesProvider);
    _listen();
  }

  void _listen() {
    _controllerSub = ref.listenManual<ink.InkPageController>(
      ink.inkPageControllerProvider(widget.page.id),
      (previous, next) => _remount(next),
      fireImmediately: true,
    );
  }

  /// (Re)creates the mount for [controller]. The new mount pins the page
  /// before the old one releases it, so the page is not evicted in between.
  void _remount(ink.InkPageController controller) {
    final old = _mount;
    if (old != null && identical(old.controller, controller)) return;
    final mount = PageMount(
      session: _session,
      page: widget.page,
      controller: controller,
      onContentChanged: _onContentChanged,
      // (v2, I-10) the note-level tape 'show all', again after each content.
      tapesRevealedAll: () => ref.read(editorTapesRevealedAllProvider),
      // (v2, 6.15.2) the playback focus of the note for a new mount.
      playbackFocus: () => ref.read(editorPlaybackHighlightProvider).current,
    );
    _mount = mount;
    _mountedPages.register(mount);
    if (old != null) {
      old.dispose();
      if (mounted) setState(() {});
    }
  }

  /// Selection revalidation (6.6.6) — INK calls only, never a CORE command
  /// (this runs inside a session stream listener, N-2 v1.1).
  void _onContentChanged(core.PageContentChange change) {
    if (!mounted) return;
    ref
        .read(editorSelectionProvider.notifier)
        .revalidate(change.content.page.id, change.content);
  }

  void _unmount() {
    final mount = _mount;
    _mount = null;
    if (mount == null) return;
    if (identical(_mountedPages[mount.pageId], mount)) {
      _mountedPages.unregister(mount.pageId);
    }
    mount.dispose();
  }

  @override
  void didUpdateWidget(EditorPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.id != widget.page.id) {
      // PageViewport keys slots by page id; handled for completeness.
      _controllerSub?.close();
      _unmount();
      _listen();
    }
  }

  @override
  void dispose() {
    _controllerSub?.close();
    _controllerSub = null;
    _unmount();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mount = _mount!;
    final viewport = ref.read(editorViewportProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        _InkLayer(
          viewport: viewport,
          controller: mount.controller,
          pageId: widget.page.id,
          pageIndex: widget.pageIndex,
        ),
        ValueListenableBuilder<bool>(
          valueListenable: mount.isLoaded,
          builder: (context, loaded, _) => loaded
              ? const SizedBox.shrink()
              : const _LoadingCover(key: EditorPageView.loadingCoverKey),
        ),
      ],
    );
  }
}

/// InkPageView with the camera-dependent arguments (6.4.3): rebuilt on every
/// camera change, nothing else of the page is.
class _InkLayer extends StatefulWidget {
  const _InkLayer({
    required this.viewport,
    required this.controller,
    required this.pageId,
    required this.pageIndex,
  });

  final ViewportController viewport;
  final ink.InkPageController controller;
  final String pageId;
  final int pageIndex;

  @override
  State<_InkLayer> createState() => _InkLayerState();
}

class _InkLayerState extends State<_InkLayer> {
  late Listenable _camera;

  @override
  void initState() {
    super.initState();
    _camera = _cameraOf(widget.viewport);
  }

  @override
  void didUpdateWidget(_InkLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.viewport, widget.viewport)) {
      _camera = _cameraOf(widget.viewport);
    }
  }

  static Listenable _cameraOf(ViewportController v) =>
      Listenable.merge([v, v.settledScale, v.isInteracting]);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _camera,
    builder: (context, _) {
      final v = widget.viewport;
      final settled = v.settledScale.value;
      return ink.InkPageView(
        controller: widget.controller,
        ancestorScale: settled > 0 ? v.camera.scale / settled : 1,
        isScaling: v.isInteracting.value,
        visiblePageRect: _visiblePageRect(v),
      );
    },
  );

  /// The part of the page on screen, in page pt (Rect.zero when none of it
  /// is; null before the viewport has a camera).
  Rect? _visiblePageRect(ViewportController v) {
    final index = _indexOf(v);
    if (index == null || v.viewportSize.isEmpty) return null;
    final page = v.layout.rectOf(index);
    final visible = v.camera.visibleDocRect(v.viewportSize).intersect(page);
    if (visible.width <= 0 || visible.height <= 0) return Rect.zero;
    return visible.shift(-page.topLeft);
  }

  /// [widget.pageIndex] when it still names this page, else its current index.
  int? _indexOf(ViewportController v) {
    final pages = v.pages;
    final i = widget.pageIndex;
    if (i >= 0 && i < pages.length && pages[i].id == widget.pageId) {
      return i < v.layout.length ? i : null;
    }
    final found = pages.indexWhere((p) => p.id == widget.pageId);
    return found >= 0 && found < v.layout.length ? found : null;
  }
}

/// Light translucent cover over a page whose content is still loading
/// (6.4.4). Tool input on that page is ignored meanwhile (6.6.2 ⑤).
class _LoadingCover extends StatelessWidget {
  const _LoadingCover({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
    );
  }
}
