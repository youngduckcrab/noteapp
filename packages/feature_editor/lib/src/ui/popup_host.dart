// lib/src/ui/popup_host.dart — 04-editor 6.9.2 (PopupHost).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/popup.dart';
import 'eraser/eraser_popup.dart';
import 'pen/pen_settings_popup.dart';
import 'pen/quick_pen_popup.dart';

/// Toolbar anchors the popups follow (CompositedTransformTarget links).
class PopupAnchors {
  final LayerLink pen = LayerLink();
  final LayerLink eraser = LayerLink();
}

/// Shows editorPopupProvider's popup with an OverlayPortal (its overlay child
/// stays a logical descendant here: provider scope, shortcuts, focus) next to
/// the toolbar button it belongs to (CompositedTransformFollower), above a
/// full-screen transparent barrier: a pointer down on the barrier closes the
/// popup and is consumed (nothing is drawn on the canvas).
///
/// E-13 shows the toolbar popups (pen settings, quick pen, eraser); the
/// context menus stay with InteractionHost (E-10); the add-page sheet (E-17)
/// and the preset dialogs (E-16) join here.
class PopupHost extends ConsumerStatefulWidget {
  const PopupHost({super.key, required this.child});

  final Widget child;

  static const barrierKey = ValueKey('editor.popup.barrier');

  /// The anchors of the enclosing PopupHost.
  static PopupAnchors anchorsOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_PopupAnchorsScope>();
    assert(scope != null, 'No PopupHost above this context');
    return scope!.anchors;
  }

  @override
  ConsumerState<PopupHost> createState() => _PopupHostState();
}

class _PopupHostState extends ConsumerState<PopupHost> {
  final PopupAnchors _anchors = PopupAnchors();
  final OverlayPortalController _portal = OverlayPortalController();

  void _sync(EditorPopup? popup) {
    final show = _layoutOf(popup) != null;
    if (show && !_portal.isShowing) _portal.show();
    if (!show && _portal.isShowing) _portal.hide();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync(ref.read(editorPopupProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(editorPopupProvider, (_, next) => _sync(next));
    return _PopupAnchorsScope(
      anchors: _anchors,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _PopupLayer(anchors: _anchors),
        child: widget.child,
      ),
    );
  }
}

/// The anchor and the panel of a toolbar popup; null for the others.
({LinkPick link, Widget panel})? _layoutOf(EditorPopup? popup) =>
    switch (popup) {
      PenSettingsPopup() => (
        link: LinkPick.pen,
        panel: const PenSettingsPanel(),
      ),
      QuickPenPopup() => (link: LinkPick.pen, panel: const QuickPenPanel()),
      EraserSettingsPopup() => (
        link: LinkPick.eraser,
        panel: const EraserSettingsPanel(),
      ),
      _ => null,
    };

/// Which toolbar button a popup hangs from.
enum LinkPick { pen, eraser }

class _PopupLayer extends ConsumerWidget {
  const _PopupLayer({required this.anchors});

  final PopupAnchors anchors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = _layoutOf(ref.watch(editorPopupProvider));
    if (layout == null) return const SizedBox.shrink();
    final link = switch (layout.link) {
      LinkPick.pen => anchors.pen,
      LinkPick.eraser => anchors.eraser,
    };
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            key: PopupHost.barrierKey,
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) =>
                ref.read(editorPopupProvider.notifier).close(),
          ),
        ),
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          offset: const Offset(0, 6),
          child: Align(alignment: Alignment.topLeft, child: layout.panel),
        ),
      ],
    );
  }
}

class _PopupAnchorsScope extends InheritedWidget {
  const _PopupAnchorsScope({required this.anchors, required super.child});

  final PopupAnchors anchors;

  @override
  bool updateShouldNotify(_PopupAnchorsScope oldWidget) =>
      !identical(anchors, oldWidget.anchors);
}

/// Frame of a popup panel: 340 px wide, at most min(600, available) high,
/// scrolls when longer (6.9.3).
class PopupPanelFrame extends StatelessWidget {
  const PopupPanelFrame({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height - 120;
    return Material(
      elevation: 3,
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 340,
          minWidth: 340,
          maxHeight: maxHeight.clamp(120, 600),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
