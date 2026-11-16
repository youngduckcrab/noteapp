// lib/src/ui/chrome/editor_chrome.dart — 04-editor 19 (hiding the top menu,
// detaching the preset row as a floating palette).
//
// The toolbar lives in [EditorTopMenu], which slides it up when
// EditorDeviceState.toolbarHidden is set; the floating buttons (restore pill,
// palette) are in floating_layer.dart. (v2.15-ui — 22) The preset row under
// the toolbar is gone: its pens are the toolbar's pen tray, which is what
// '팔레트로 떼어내기' now detaches.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../../state/note_search.dart';
import '../../state/popup.dart';
import '../../state/settings/editor_device_state.dart';
import '../editor_strings.dart';

/// The chrome actions (toolbar button, ⋯ items, restore pill, palette,
/// system back).
abstract final class EditorChrome {
  /// Slide of the top menu.
  static const Duration slide = Duration(milliseconds: 200);

  /// '메뉴 숨기기': closes a popup (the toolbar ones hang from buttons that
  /// go away), hides the toolbar; the first time on this device a snack bar
  /// says how to get them back.
  static void hideMenu(BuildContext context, WidgetRef ref) {
    ref.read(editorPopupProvider.notifier).close();
    final device = ref.read(editorDeviceStateProvider.notifier);
    device.setToolbarHidden(true);
    if (ref.read(editorDeviceStateProvider).seenToolbarHideHint) return;
    device.markSeenToolbarHideHint();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text(EditorStrings.menuHiddenHint)),
      );
  }

  /// The restore pill / system back: the toolbar comes back.
  static void showMenu(WidgetRef ref) =>
      ref.read(editorDeviceStateProvider.notifier).setToolbarHidden(false);

  /// '팔레트로 떼어내기' (the pen tray leaves the toolbar).
  static void detachPalette(WidgetRef ref) =>
      ref.read(editorDeviceStateProvider.notifier).setPaletteDetached(true);

  /// '메뉴에 다시 붙이기'.
  static void dockPalette(WidgetRef ref) {
    ref.read(editorPaletteExpandedProvider.notifier).set(false);
    ref.read(editorDeviceStateProvider.notifier).setPaletteDetached(false);
  }

  /// System back on the open note (EditorRoot's PopScope, only while the
  /// editor body is on screen), in this order: an open '노트에서 찾기'
  /// closes (04-editor 18.1), then an open palette, then a hidden menu comes
  /// back; true when back was used up that way (the note stays).
  static bool handleBack(WidgetRef ref) {
    if (ref.read(editorNoteSearchProvider).isOpen) {
      ref.read(editorNoteSearchProvider.notifier).close();
      return true;
    }
    final expanded = ref.read(editorPaletteExpandedProvider.notifier);
    if (ref.read(editorPaletteExpandedProvider)) {
      expanded.set(false);
      return true;
    }
    if (ref.read(editorDeviceStateProvider).toolbarHidden) {
      showMenu(ref);
      return true;
    }
    return false;
  }

  /// Keys of the ⋯ items.
  static const moreHideKey = ValueKey('editor.more.hideMenu');
  static const moreDetachKey = ValueKey('editor.more.detachPalette');
  static const moreDockKey = ValueKey('editor.more.dockPalette');

  /// The ⋯ items: 메뉴 숨기기 · 팔레트로 떼어내기 / 메뉴에 다시 붙이기.
  static List<Widget> moreMenuItems(BuildContext context, WidgetRef ref) {
    final detached = ref.watch(
      editorDeviceStateProvider.select((s) => s.paletteDetached),
    );
    return [
      MenuItemButton(
        key: moreHideKey,
        leadingIcon: const Icon(Icons.expand_less),
        onPressed: () => hideMenu(context, ref),
        child: const Text(EditorStrings.hideMenu),
      ),
      if (detached)
        MenuItemButton(
          key: moreDockKey,
          leadingIcon: const Icon(Icons.vertical_align_top),
          onPressed: () => dockPalette(ref),
          child: const Text(EditorStrings.dockPalette),
        )
      else
        MenuItemButton(
          key: moreDetachKey,
          leadingIcon: const Icon(Icons.palette_outlined),
          onPressed: () => detachPalette(ref),
          child: const Text(EditorStrings.detachPalette),
        ),
    ];
  }
}

/// Per note: whether the floating pen palette is open (PenPalette; system
/// back closes it first — [EditorChrome.handleBack]).
class EditorPaletteExpandedNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(editorNoteIdProvider);
    return false;
  }

  void set(bool expanded) {
    if (state != expanded) state = expanded;
  }
}

final editorPaletteExpandedProvider =
    NotifierProvider<EditorPaletteExpandedNotifier, bool>(
      EditorPaletteExpandedNotifier.new,
      dependencies: [editorNoteIdProvider],
      name: 'editorPaletteExpandedProvider',
    );

/// Toolbar (52 px, the pen tray in it unless the palette is detached) ·
/// divider. Hidden ([EditorDeviceState.toolbarHidden]): slides
/// up in [EditorChrome.slide] and leaves the tree, so the page gets the room
/// and nothing anchors to a button that is not on screen. The stored value
/// arriving after the screen opened applies without the slide.
class EditorTopMenu extends ConsumerStatefulWidget {
  const EditorTopMenu({super.key, required this.toolbar});

  final Widget toolbar;

  static const menuKey = ValueKey('editor.topMenu');

  @override
  ConsumerState<EditorTopMenu> createState() => _EditorTopMenuState();
}

class _EditorTopMenuState extends ConsumerState<EditorTopMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: EditorChrome.slide,
    value: ref.read(editorDeviceStateProvider).toolbarHidden ? 0 : 1,
  );

  /// Whether the device state had been loaded at the last build.
  bool _loaded = false;

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(editorDeviceStateProvider.select((s) => s.toolbarHidden), (
      _,
      hidden,
    ) {
      final target = hidden ? 0.0 : 1.0;
      if (!_loaded) {
        _slide.value = target; // the stored value: no slide
      } else {
        _slide.animateTo(target, curve: Curves.easeOutCubic);
      }
    });
    _loaded = ref.read(editorDeviceStateProvider.notifier).isLoaded;
    return AnimatedBuilder(
      animation: _slide,
      builder: (context, child) {
        if (_slide.value == 0) return const SizedBox.shrink();
        if (_slide.value == 1) return child!;
        return ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: _slide.value,
            child: child,
          ),
        );
      },
      child: Column(
        key: EditorTopMenu.menuKey,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [widget.toolbar, const Divider(height: 1)],
      ),
    );
  }
}

/// [⌃] of the toolbar, right after [←]: '메뉴 숨기기' (the same item is in
/// [⋯]). In a row that scrolls or shows the title it is a plain button; in
/// the others [MenuHideSlot] shows it only when the row has room to spare.
class MenuHideButton extends ConsumerWidget {
  const MenuHideButton({super.key});

  static const buttonKey = ValueKey('editor.toolbar.hideMenu');

  /// Its width in the toolbar row.
  static const double width = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    key: buttonKey,
    onPressed: () => EditorChrome.hideMenu(context, ref),
    icon: const Icon(Icons.expand_less, semanticLabel: EditorStrings.hideMenu),
  );
}

/// The toolbar's Spacer (between [←] and [▤]) holding [MenuHideButton] at
/// its left when it is at least [MenuHideButton.width] wide — so a crowded
/// row (folded or not, any optional buttons) never overflows because of it.
class MenuHideSlot extends StatelessWidget {
  const MenuHideSlot({super.key});

  @override
  Widget build(BuildContext context) => Expanded(
    child: LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= MenuHideButton.width
          ? const Align(
              alignment: Alignment.centerLeft,
              child: MenuHideButton(),
            )
          : const SizedBox.shrink(),
    ),
  );
}
