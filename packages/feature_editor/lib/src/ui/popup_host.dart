// lib/src/ui/popup_host.dart — 04-editor 6.9.2 (PopupHost).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../di/editor_extensions.dart';
import '../state/popup.dart';
import 'editor_strings.dart';
import 'eraser/eraser_popup.dart';
import 'pages/add_page_sheet.dart';
import 'pen/pen_settings_popup.dart';
import 'pen/quick_pen_popup.dart';
import 'presets/preset_manager_sheet.dart';
import 'presets/save_preset_dialog.dart';

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
/// context menus stay with InteractionHost (E-10). E-16: the preset save
/// dialog and manager sheet have no anchor — they sit in the middle of the
/// screen (above the keyboard) over a light scrim; so does the add-page
/// sheet (E-17).
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

  /// Runs an extension item picked inside a popup (the add-page sheet's
  /// '다른 소스' row, 4.5) with the PopupHost's own context, which stays
  /// mounted after the popup closes: awaited, never twice at the same time;
  /// an exception is reported and shows '실행하지 못했어요'.
  static Future<void> runMenuItem(
    BuildContext context,
    EditorMenuItem item,
    EditorMenuContext menu,
  ) {
    final scope = context.getInheritedWidgetOfExactType<_PopupAnchorsScope>();
    assert(scope != null, 'No PopupHost above this context');
    return scope!.host._runMenuItem(item, menu);
  }

  @override
  ConsumerState<PopupHost> createState() => _PopupHostState();
}

class _PopupHostState extends ConsumerState<PopupHost> {
  final PopupAnchors _anchors = PopupAnchors();
  final OverlayPortalController _portal = OverlayPortalController();
  final Set<String> _running = {};

  Future<void> _runMenuItem(EditorMenuItem item, EditorMenuContext menu) async {
    if (!_running.add(item.id)) return;
    try {
      await item.onSelected(context, menu);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while running menu item ${item.id}'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text(EditorStrings.commandFailed)),
          );
      }
    } finally {
      _running.remove(item.id);
    }
  }

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
      host: this,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _PopupLayer(anchors: _anchors),
        child: widget.child,
      ),
    );
  }
}

/// The anchor (null = centred) and the panel of a popup PopupHost shows;
/// null for the others.
({LinkPick? link, Widget panel})? _layoutOf(
  EditorPopup? popup,
) => switch (popup) {
  PenSettingsPopup() => (link: LinkPick.pen, panel: const PenSettingsPanel()),
  QuickPenPopup() => (link: LinkPick.pen, panel: const QuickPenPanel()),
  EraserSettingsPopup() => (
    link: LinkPick.eraser,
    panel: const EraserSettingsPanel(),
  ),
  SavePresetPopup() => (link: null, panel: const SavePresetDialog()),
  PresetManagerPopup() => (link: null, panel: const PresetManagerSheet()),
  final AddPagePopup popup => (link: null, panel: AddPageSheet(popup: popup)),
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
      null => null,
    };
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            key: PopupHost.barrierKey,
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) =>
                ref.read(editorPopupProvider.notifier).close(),
            child: link == null
                ? ColoredBox(
                    color: Theme.of(context).colorScheme.scrim
                        .withValues(alpha: 0.32),
                  )
                : null,
          ),
        ),
        if (link != null)
          CompositedTransformFollower(
            link: link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 6),
            child: Align(alignment: Alignment.topLeft, child: layout.panel),
          )
        else
          Positioned.fill(
            child: Padding(
              padding: MediaQuery.viewInsetsOf(context),
              child: Center(child: layout.panel),
            ),
          ),
      ],
    );
  }
}

class _PopupAnchorsScope extends InheritedWidget {
  const _PopupAnchorsScope({
    required this.anchors,
    required this.host,
    required super.child,
  });

  final PopupAnchors anchors;
  final _PopupHostState host;

  @override
  bool updateShouldNotify(_PopupAnchorsScope oldWidget) =>
      !identical(anchors, oldWidget.anchors);
}

/// Frame of a popup panel: [width] px wide (pen settings 340, quick pen and
/// eraser 300), at most min(600, available) high, scrolls when longer
/// (6.9.3).
class PopupPanelFrame extends StatelessWidget {
  const PopupPanelFrame({
    super.key,
    required this.title,
    required this.children,
    this.width = 340,
  });

  final String title;
  final List<Widget> children;
  final double width;

  /// Inner padding on every side.
  static const double padding = 16;

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
          maxWidth: width,
          minWidth: width,
          maxHeight: maxHeight.clamp(120, 600),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(padding),
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
