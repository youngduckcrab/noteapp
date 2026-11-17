// test/support/library_test_harness.dart — 05-library 5.7 (L0). The ONE
// harness name (LibraryTestHarness, LIBRARY-2-6).
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId;

import 'fake_library_backend.dart';
import 'pump_library.dart';
import 'test_sizes.dart';

/// Router stand-in around LibraryScreen: onOpenFolder changes folderId of the
/// SAME State (like INFRA's shared page key, 5.2 I-2); every callback goes to
/// [log].
final class LibraryTestHarness {
  LibraryTestHarness(
    this.backend, {
    this.size = TestSizes.ipad13Landscape,
    this.extraOverrides = const [],
    this.withOpenNoteAt = true,
    this.withOpenMarkdown = true,
  });

  final FakeLibraryBackend backend;

  /// Logical px, DPR 2 (test_sizes.dart, 9.1).
  final Size size;

  /// Renderer, PDF slots, syncBadgeProvider, ...
  final List<Override> extraOverrides;

  /// (v2) Passes onOpenNoteAt (→ [log]); false leaves it null so content
  /// hits fall back to onOpenNote (6.1.4).
  final bool withOpenNoteAt;

  /// (v2.17-md) Passes onOpenMarkdown (→ [log] `'md:<id>'`, `' q=<query>'`, `' edit'`);
  /// false leaves it null (MD 문서 open through onOpenNote).
  final bool withOpenMarkdown;
  final NavigationLog log = NavigationLog();

  final GlobalKey<_RouterStandInState> _routerKey = GlobalKey();
  FolderId? _folderId;

  /// The folderId the LibraryScreen currently gets.
  FolderId? get currentFolderId => _folderId;

  /// The screen's widget (folderId and callbacks as last built).
  LibraryScreen screen(WidgetTester tester) =>
      tester.widget<LibraryScreen>(find.byType(LibraryScreen));

  /// pumpLibrary: size + DPR 2, ProviderScope(overrides: backend.overrides +
  /// extraOverrides), material_ui MaterialApp, LibraryScreen(folderId:
  /// folderId, callbacks → log / route).
  /// (v2.14-ui) [theme] goes to the MaterialApp.
  Future<void> pump(
    WidgetTester tester, {
    FolderId? folderId,
    ThemeData? theme,
  }) async {
    _folderId = folderId;
    await pumpLibrary(
      tester,
      overrides: [...backend.overrides, ...extraOverrides],
      size: size,
      theme: theme,
      home: _RouterStandIn(key: _routerKey, harness: this),
    );
  }

  /// Same as a route change: rebuilds with the new folderId, State kept.
  Future<void> goToFolder(WidgetTester tester, FolderId? folderId) async {
    _route(folderId);
    await tester.pump();
  }

  void _route(FolderId? folderId) {
    _folderId = folderId;
    _routerKey.currentState?.refresh();
  }
}

final class NavigationLog {
  /// `'folder:<id>'` | `'folder:home'` | `'note:<id>'` | `'settings'` |
  /// (v2) `'noteAt:<noteId>/<pageId>'` (+ `' <l>,<t>,<r>,<b>'` when a rect
  /// came), in call order.
  final List<String> entries = [];

  /// (v2) Every onOpenNoteAt call: (noteId, pageId, focusRectPt).
  final List<(String, String, Rect?)> openNoteAt = [];

  void clear() {
    entries.clear();
    openNoteAt.clear();
  }

  void _openMarkdown(String noteId, {String? query, bool edit = false}) =>
      entries.add(
        'md:$noteId${query == null ? '' : ' q=$query'}${edit ? ' edit' : ''}',
      );

  void _openNoteAt(String noteId, String pageId, Rect? rect) {
    openNoteAt.add((noteId, pageId, rect));
    entries.add(
      rect == null
          ? 'noteAt:$noteId/$pageId'
          : 'noteAt:$noteId/$pageId '
                '${rect.left},${rect.top},${rect.right},${rect.bottom}',
    );
  }
}

class _RouterStandIn extends StatefulWidget {
  const _RouterStandIn({super.key, required this.harness});

  final LibraryTestHarness harness;

  @override
  State<_RouterStandIn> createState() => _RouterStandInState();
}

class _RouterStandInState extends State<_RouterStandIn> {
  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final h = widget.harness;
    return LibraryScreen(
      folderId: h.currentFolderId,
      onOpenFolder: (id) {
        h.log.entries.add(id == null ? 'folder:home' : 'folder:$id');
        h._route(id);
      },
      onOpenNote: (id) => h.log.entries.add('note:$id'),
      onOpenNoteAt: h.withOpenNoteAt ? h.log._openNoteAt : null,
      onOpenMarkdown: h.withOpenMarkdown ? h.log._openMarkdown : null,
      onOpenSettings: () => h.log.entries.add('settings'),
    );
  }
}
