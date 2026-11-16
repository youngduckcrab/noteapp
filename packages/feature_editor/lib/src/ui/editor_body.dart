// lib/src/ui/editor_body.dart — 04-editor 6.4.3 (EditorBody), 6.9.1 layout,
// 6.17.2–6.17.4; (v2) the bottom panel slot (m5-7/04-editor 6.15.4 — E2-16),
// (P-B) the kept text draft banner (6.11.2 — E2-10b).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../commands/extension_runner.dart';
import '../input/editor_shortcuts.dart';
import '../playback/playback_highlighter.dart';
import '../scope/editor_scope.dart';
import '../state/popup.dart';
import '../text/text_edit_session.dart';
import '../viewport/page_viewport.dart';
import 'banners/read_only_banner.dart';
import 'banners/storage_warning_banner.dart';
import 'banners/text_draft_banner.dart';
import 'chrome/editor_chrome.dart';
import 'editor_strings.dart';
import 'panels/editor_panel_slot.dart';
import 'popup_host.dart';
import 'toolbar/editor_toolbar.dart';

/// The ready editor of one note (inside its per-note scope):
///
///   EditorShortcuts → (v2) PlaybackHighlightDriver → PopupHost → Scaffold →
///   SafeArea → Column
///   ├─ ReadOnlyBanner / StorageWarningBanner / (v2) TextDraftBanner
///   │  (height 0 when not shown)
///   ├─ EditorTopMenu: EditorToolbar (52 px) · PresetBarView (44 px) — (04-
///   │  editor 19) hidden / the row detached as a palette
///   ├─ Expanded: PageViewport — Row[EditorFloatingLayer (restore pill,
///   │  palette) over the pages, NoteSearchPanel]
///   └─ (v2) EditorPanelArea: the bottom panel slot while open (≤ 40 % of
///      the Column height — 6.15.4)
///
/// Also: command and storage-error snack bars, flushAll when the app is
/// hidden or paused (AppLifecycleListener — 6.17.4), and turning read only
/// while open cancels the running interaction and closes the popup (6.17.2).
class EditorBody extends ConsumerStatefulWidget {
  const EditorBody({super.key, required this.onBack, this.onOpenSettings});

  final VoidCallback onBack;
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends ConsumerState<EditorBody> {
  late final AppLifecycleListener _lifecycle;
  ExtensionRunner? _runner;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _flush, onPause: _flush);
    // (v2, m5-7/04-editor 4.3.1) the slot callbacks get this body's context
    // (it stays mounted when a menu closes).
    ref.listenManual<ExtensionRunner>(editorExtensionRunnerProvider, (
      previous,
      next,
    ) {
      previous?.bindBody(null);
      (_runner = next).bindBody(_bodyContext);
    }, fireImmediately: true);
  }

  BuildContext _bodyContext() => context;

  /// (v2, E2-10 — 6.11.5) an open text session ends first (appHidden — its
  /// one command), then the writes.
  void _flush() => unawaited(_endTextAndFlush());

  Future<void> _endTextAndFlush() async {
    final text = ref.read(editorTextEditProvider.notifier);
    await text.end(reason: TextEditEndReason.appHidden);
    if (!mounted) return;
    await ref.read(editorCommandsProvider).flushAll();
  }

  @override
  void dispose() {
    _runner?.bindBody(null);
    _runner = null;
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(editorReadOnlyProvider, (previous, readOnly) {
      if (!readOnly || previous == true) return;
      ref.read(editorInputRouterProvider).cancelAll();
      ref.read(editorPopupProvider.notifier).close();
    });
    return EditorShortcuts(
      child: PlaybackHighlightDriver(
        child: PopupHost(
          child: Scaffold(
            body: SafeArea(
              child: StorageErrorNotices(
                child: CommandMessages(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ReadOnlyBanner(),
                        const StorageWarningBanner(),
                        const TextDraftBanner(),
                        EditorTopMenu(
                          toolbar: EditorToolbar(
                            onBack: widget.onBack,
                            onOpenSettings: widget.onOpenSettings,
                          ),
                        ),
                        const Expanded(child: PageViewport()),
                        EditorPanelArea(bodyHeight: constraints.maxHeight),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows EditorCommands.messages (read-only refusal, failed command) and
/// EditorCommands.pagesDeleted ("페이지를 삭제했어요 [되돌리기]" — 6.11.1) as
/// snack bars.
class CommandMessages extends ConsumerStatefulWidget {
  const CommandMessages({super.key, required this.child});

  final Widget child;

  /// Key of the snack bar action "되돌리기" after deleting pages.
  static const undoDeleteKey = ValueKey('editor.pagesDeleted.undo');

  @override
  ConsumerState<CommandMessages> createState() => _CommandMessagesState();
}

class _CommandMessagesState extends ConsumerState<CommandMessages> {
  StreamSubscription<String>? _sub;
  StreamSubscription<int>? _deletedSub;

  @override
  void initState() {
    super.initState();
    final commands = ref.read(editorCommandsProvider);
    _sub = commands.messages.listen(_show);
    _deletedSub = commands.pagesDeleted.listen((_) => _showDeleted());
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showDeleted() {
    if (!mounted) return;
    final commands = ref.read(editorCommandsProvider);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(EditorStrings.pagesDeleted),
          action: SnackBarAction(
            key: CommandMessages.undoDeleteKey,
            label: EditorStrings.undo,
            onPressed: () => unawaited(commands.undo()),
          ),
        ),
      );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_deletedSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
