import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'appearance.dart';
import 'theme.dart';

/// (v2.14-ui split, 01-infra 14.3) The note-editor route's theme: the
/// 필기 화면 스타일 (AppAppearance.editorStyle) in the brightness the app
/// theme shows — the one '밝기' setting resolved against the platform
/// brightness, as MaterialApp resolves themeMode.
///
/// appRouterProvider wraps the editor screen in it (createAppRouter's
/// wrapEditor), so the editor's toolbar, pens and panels read the editor
/// style's StyleTokens while the library, settings and their dialogs keep
/// the home style.
/// Dialogs, sheets and popup menus opened from inside the editor carry it
/// too: showDialog / showModalBottomSheet / showMenu capture the inherited
/// themes of the context they are opened from (InheritedTheme.capture), and
/// MenuAnchor / OverlayPortal children build under the anchor's context.
/// A route pushed by hand must pass `themes:` (pdf_io flows.dart).
class EditorStyleScope extends ConsumerWidget {
  const EditorStyleScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appAppearanceProvider);
    final brightness = appearance.effectiveBrightness(
      MediaQuery.platformBrightnessOf(context),
    );
    return Theme(
      data: buildAppTheme(
        style: appearance.editorStyle,
        brightness: brightness,
      ),
      child: child,
    );
  }
}
