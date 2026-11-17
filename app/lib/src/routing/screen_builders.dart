import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
// (v2.17-md, C217M-13 — 08-markdown 11, 17) the MD 문서 screen and its markdown parser
// are loaded on first use on the web (main.dart.js budget); natively the library is in
// the binary and loadLibrary completes at once.
import 'package:feature_markdown/feature_markdown.dart' deferred as md;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show noteStoreProvider;

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
typedef MarkdownScreenBuilder = Widget Function(
  BuildContext context,
  MarkdownRouteArgs args,
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
    this.markdown = _placeholderMarkdown,
  });

  /// Real screens: LibraryScreen / EditorScreen (계약 7.2.17, 7.2.18) and
  /// SettingsScreen (4.5.8). Wiring in 6.6.
  factory AppScreenBuilders.production() => const AppScreenBuilders(
    library: _productionLibrary,
    editor: _productionEditor,
    settings: _productionSettings,
    markdown: _productionMarkdown,
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

  /// (v2.17-md) The MD 문서 screen (`/md/:noteId`).
  final MarkdownScreenBuilder markdown;
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
  // (v2.17-md) MD 문서 go straight to /md/ (no redirect, no DB read on the way).
  onOpenMarkdown: (noteId, {query, edit = false}) =>
      navigator.openMarkdown(noteId, query: query, edit: edit),
);

/// (v2.17-md, 08-markdown 11 — review U19) The deferred feature_markdown library: loaded
/// once (one static Future), and after that the screen is built synchronously (no empty
/// frame on later openings).
abstract final class MarkdownScreenLoader {
  static Future<void>? _load;
  static bool _loaded = false;

  /// tests: the deferred load (a failing one, to test the retry).
  @visibleForTesting
  static Future<void> Function() loadLibrary = _loadDeferred;
  static Future<void> _loadDeferred() => md.loadLibrary();

  /// Whether the MD 문서 screen can be built synchronously.
  static bool get isLoaded => _loaded;

  /// Starts (or joins) the load; FeatureWiringModule's idle task calls it on native
  /// builds. A failed load is forgotten, so the next call (the screen's 다시 시도, or the
  /// next opening) tries again.
  static Future<void> load() => _load ??= loadLibrary().then(
    (_) {
      _loaded = true;
    },
    onError: (Object e, StackTrace s) {
      _load = null;
      Error.throwWithStackTrace(e, s);
    },
  );

  @visibleForTesting
  static void resetForTest() {
    _load = null;
    _loaded = false;
    loadLibrary = _loadDeferred;
  }
}

Widget _productionMarkdown(
  BuildContext context,
  MarkdownRouteArgs args,
  AppNavigator navigator,
) => _DeferredMarkdownScreen(
  key: ValueKey<String>('md:${args.noteId}'),
  args: args,
  navigator: navigator,
);

/// Also records the opening (Library '최근' — the ink editor's openSession does it for
/// notes; an MD 문서 never opens a session).
class _DeferredMarkdownScreen extends StatefulWidget {
  const _DeferredMarkdownScreen({
    super.key,
    required this.args,
    required this.navigator,
  });

  final MarkdownRouteArgs args;
  final AppNavigator navigator;

  @override
  State<_DeferredMarkdownScreen> createState() =>
      _DeferredMarkdownScreenState();
}

class _DeferredMarkdownScreenState extends State<_DeferredMarkdownScreen> {
  MarkdownRouteArgs get args => widget.args;
  AppNavigator get navigator => widget.navigator;

  @override
  void initState() {
    super.initState();
    try {
      final store = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(noteStoreProvider);
      unawaited(
        store.library.markOpened(args.noteId).catchError((Object _) {}),
      );
    } on Object {
      // No store in this tree (placeholder tests): nothing to record.
    }
  }

  Widget _screen() => md.MarkdownScreen(
    noteId: args.noteId,
    initialQuery: args.initialQuery,
    initialEdit: args.initialEdit,
    onClose: navigator.closeMarkdown,
    onOpenAsNote: () {
      navigator.closeMarkdown();
      navigator.openNote(args.noteId);
    },
  );

  Future<void>? _loading;

  void _retry() => setState(() {
    _loading = MarkdownScreenLoader.load();
  });

  @override
  Widget build(BuildContext context) {
    if (MarkdownScreenLoader.isLoaded) return _screen();
    return FutureBuilder<void>(
      future: _loading ??= MarkdownScreenLoader.load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return _screen();
        }
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: AppStrings.back,
              onPressed: navigator.closeMarkdown,
            ),
          ),
          body: Center(
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          AppStrings.markdownLoadFailed,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const Key('md.load.retry'),
                        onPressed: _retry,
                        child: const Text(AppStrings.retry),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}

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

/// (v2.17-md) `markdown <id> q=<query> edit` + a back button.
Widget _placeholderMarkdown(
  BuildContext context,
  MarkdownRouteArgs args,
  AppNavigator navigator,
) => Scaffold(
  key: ValueKey<String>('md:${args.noteId}'),
  appBar: AppBar(
    leading: IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: AppStrings.back,
      onPressed: navigator.closeMarkdown,
    ),
    title: const Text('markdown'),
  ),
  body: Center(
    child: Text(
      'markdown ${args.noteId}'
      '${args.initialQuery == null ? '' : ' q=${args.initialQuery}'}'
      '${args.initialEdit ? ' edit' : ''}',
    ),
  ),
);

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
