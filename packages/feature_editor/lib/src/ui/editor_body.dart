// lib/src/ui/editor_body.dart — 04-editor 6.4.3 (EditorBody), 6.9.1 layout,
// 6.17.2–6.17.4.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../input/editor_shortcuts.dart';
import '../scope/editor_scope.dart';
import '../state/popup.dart';
import '../viewport/page_viewport.dart';
import 'banners/read_only_banner.dart';
import 'banners/storage_warning_banner.dart';
import 'popup_host.dart';
import 'toolbar/editor_toolbar.dart';

/// The ready editor of one note (inside its per-note scope):
///
///   EditorShortcuts → PopupHost → Scaffold → SafeArea → Column
///   ├─ ReadOnlyBanner / StorageWarningBanner (height 0 when not shown)
///   ├─ EditorToolbar (52 px) · PresetBarView (44 px — E-16)
///   └─ Expanded: PageViewport
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

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _flush, onPause: _flush);
  }

  void _flush() => unawaited(ref.read(editorCommandsProvider).flushAll());

  @override
  void dispose() {
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
      child: PopupHost(
        child: Scaffold(
          body: SafeArea(
            child: StorageErrorNotices(
              child: CommandMessages(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ReadOnlyBanner(),
                    const StorageWarningBanner(),
                    EditorToolbar(
                      onBack: widget.onBack,
                      onOpenSettings: widget.onOpenSettings,
                    ),
                    const Divider(height: 1),
                    const Expanded(child: PageViewport()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows EditorCommands.messages (read-only refusal, failed command) as
/// snack bars.
class CommandMessages extends ConsumerStatefulWidget {
  const CommandMessages({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CommandMessages> createState() => _CommandMessagesState();
}

class _CommandMessagesState extends ConsumerState<CommandMessages> {
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(editorCommandsProvider).messages.listen(_show);
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
