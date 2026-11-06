import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:material_ui/material_ui.dart';

import '../app/strings.dart';
import '../settings/settings_screen.dart';
import 'app_navigator.dart';
import 'app_routes.dart';

typedef LibraryScreenBuilder = Widget Function(
  BuildContext context,
  LibraryRouteArgs args,
  AppNavigator navigator,
);
typedef EditorScreenBuilder = Widget Function(
  BuildContext context,
  EditorRouteArgs args,
  AppNavigator navigator,
);
typedef SettingsScreenBuilder = Widget Function(
  BuildContext context,
  AppNavigator navigator,
);

/// The three screens the router shows (docs/plans/01-infra.md 4.5.5, 6.6).
/// Feature screens only get callbacks; the [AppNavigator] stays in the shell.
@immutable
final class AppScreenBuilders {
  const AppScreenBuilders({
    required this.library,
    required this.editor,
    required this.settings,
  });

  /// Real screens: LibraryScreen / EditorScreen (계약 7.2.17, 7.2.18) and
  /// SettingsScreen (4.5.8). Wiring in 6.6.
  factory AppScreenBuilders.production() => const AppScreenBuilders(
    library: _productionLibrary,
    editor: _productionEditor,
    settings: _productionSettings,
  );

  /// Simple shell-owned widgets showing args as text (tests, smoke builds).
  /// The library placeholder is a StatefulWidget that counts initState calls
  /// (State-retention test, 9.1).
  factory AppScreenBuilders.placeholders() => const AppScreenBuilders(
    library: _placeholderLibrary,
    editor: _placeholderEditor,
    settings: _placeholderSettings,
  );

  final LibraryScreenBuilder library;
  final EditorScreenBuilder editor;
  final SettingsScreenBuilder settings;
}

Widget _productionLibrary(
  BuildContext context,
  LibraryRouteArgs args,
  AppNavigator navigator,
) => LibraryScreen(
  folderId: args.folderId,
  onOpenFolder: (folderId) => navigator.openLibrary(folderId: folderId),
  onOpenNote: navigator.openNote,
  // Content search hit → page + rect (2차 6.8, S2-6).
  onOpenNoteAt: (noteId, pageId, rect) =>
      navigator.openNote(noteId, pageId: pageId, focusRectPt: rect),
  onOpenSettings: navigator.openSettings,
);

Widget _productionEditor(
  BuildContext context,
  EditorRouteArgs args,
  AppNavigator navigator,
) => EditorScreen(
  key: ValueKey<String>(args.noteId),
  noteId: args.noteId,
  initialPageId: args.initialPageId,
  initialFocusRectPt: args.initialFocusRectPt,
  onClose: navigator.closeNote,
  onOpenSettings: navigator.openSettings,
);

Widget _productionSettings(BuildContext context, AppNavigator navigator) =>
    SettingsScreen(onClose: navigator.closeSettings);

Widget _placeholderLibrary(
  BuildContext context,
  LibraryRouteArgs args,
  AppNavigator navigator,
) => _LibraryPlaceholder(args: args, navigator: navigator);

Widget _placeholderEditor(
  BuildContext context,
  EditorRouteArgs args,
  AppNavigator navigator,
) => _EditorPlaceholder(
  key: ValueKey<String>(args.noteId),
  args: args,
  navigator: navigator,
);

Widget _placeholderSettings(BuildContext context, AppNavigator navigator) =>
    _SettingsPlaceholder(navigator: navigator);

/// Library placeholder. Its State takes a serial number from a counter of
/// initState calls and shows it as `library #<n>`: the same number after
/// folder changes means the route (and the State) was kept (6.6).
class _LibraryPlaceholder extends StatefulWidget {
  const _LibraryPlaceholder({required this.args, required this.navigator});

  final LibraryRouteArgs args;
  final AppNavigator navigator;

  @override
  State<_LibraryPlaceholder> createState() => _LibraryPlaceholderState();
}

class _LibraryPlaceholderState extends State<_LibraryPlaceholder> {
  static int _initStateCalls = 0;
  late final int _serial;

  @override
  void initState() {
    super.initState();
    _serial = ++_initStateCalls;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('library #$_serial'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: AppStrings.settings,
            onPressed: widget.navigator.openSettings,
          ),
        ],
      ),
      body: Center(
        child: Text('folderId: ${widget.args.folderId ?? '(root)'}'),
      ),
    );
  }
}

class _EditorPlaceholder extends StatelessWidget {
  const _EditorPlaceholder({
    super.key,
    required this.args,
    required this.navigator,
  });

  final EditorRouteArgs args;
  final AppNavigator navigator;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: AppStrings.back,
          onPressed: navigator.closeNote,
        ),
        title: const Text('editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: AppStrings.settings,
            onPressed: navigator.openSettings,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('noteId: ${args.noteId}'),
            Text('pageId: ${args.initialPageId ?? '(none)'}'),
            Text(
              'focus: ${switch (args.initialFocusRectPt) {
                final rect? => FocusRectCodec.encode(rect),
                null => '(none)',
              }}',
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPlaceholder extends StatelessWidget {
  const _SettingsPlaceholder({required this.navigator});

  final AppNavigator navigator;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: AppStrings.back,
          onPressed: navigator.closeSettings,
        ),
        title: const Text('settings'),
      ),
    );
  }
}
