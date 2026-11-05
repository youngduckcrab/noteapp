// lib/src/editor_screen.dart — contract 00-overview 7.2.17, 04-editor 4.2.
//
// Foundation step B5 (contract 7.6): the final constructor with a placeholder
// body — the note title and a back button that flushes the note session and
// then calls onClose. The screen states follow 04-editor 6.17.1 (opening /
// note not found / open failed / ready). The real screen (EditorRoot,
// EditorBody, toolbar, page viewport, per-note scope, …) comes with tasks
// E-04..E-13 of 04-editor 8.2.
import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import 'ui/editor_strings.dart';

/// The note editor screen. The app shell routes `/notes/:noteId` to it with
/// `key: ValueKey(noteId)`; the screen knows no router and only calls the
/// callbacks below. It reads CORE and INK providers directly, so the only
/// provider the app shell must override is core.noteStoreProvider
/// (contract 7.3.3).
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({
    super.key,
    required this.noteId,
    this.initialPageId,
    required this.onClose,
    this.onOpenSettings,
  });
  final String noteId;

  /// null → last viewed position of this note, else page 0 at fit width.
  final String? initialPageId;

  /// Back button / system back, called AFTER session.flush(). A missing note shows a
  /// message with a button that calls this.
  final VoidCallback onClose;

  /// "설정" in the more menu (hidden when null).
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

/// Overrides the app shell adds for this package. Always empty: EDITOR has no
/// ports. Its two slots (editorExtensionsProvider, devOverlaySectionsProvider)
/// are wired by the app shell's FeatureWiringModule (contract 7.3.3).
List<Override> featureEditorOverrides() => const <Override>[];

class _EditorScreenState extends ConsumerState<EditorScreen> {
  /// A close is in progress (waiting for session.flush()): further back
  /// presses are ignored, so onClose runs once.
  bool _closing = false;

  core.NoteSession? get _session =>
      ref.read(core.noteSessionProvider(widget.noteId)).value;

  /// Back button, system back and the 'not found' / 'open failed' buttons.
  /// With an open session, onClose runs only after session.flush() has
  /// completed. There is no timeout: CORE write Futures stay pending while a
  /// failed commit is retried (contract 7.2.9 v1.2, 04-editor 6.17.4).
  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    final session = _session;
    if (session != null) {
      try {
        await session.flush();
      } on Object catch (error, stack) {
        // 6.17.4: a failed flush is reported and the screen still closes;
        // CORE's write queue keeps retrying the in-memory state.
        _report(error, stack, 'while flushing the note session on close');
      }
    }
    if (!mounted) return;
    widget.onClose();
  }

  void _retry() {
    ref.invalidate(core.noteSessionProvider(widget.noteId));
  }

  void _report(Object error, StackTrace? stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'feature_editor',
        context: ErrorDescription(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = core.noteSessionProvider(widget.noteId);
    ref.listen<AsyncValue<core.NoteSession>>(provider, (previous, next) {
      // A missing note is a normal screen state (N-6), not an error report.
      if (next
          case AsyncError(:final error, :final stackTrace, isLoading: false)
          when error is! core.EntityNotFoundException) {
        _report(error, stackTrace, 'while opening note ${widget.noteId}');
      }
    });
    final session = ref.watch(provider);

    final Widget screen;
    if (session.value case final core.NoteSession open) {
      screen = _ReadyView(
        session: open,
        onBack: _close,
        onOpenSettings: widget.onOpenSettings,
      );
    } else if (session.hasError && !session.isLoading) {
      final error = session.error;
      screen = error is core.EntityNotFoundException
          ? _MessageView(
              onBack: _close,
              message: EditorStrings.noteNotFound,
              actions: [
                FilledButton(
                  onPressed: _close,
                  child: const Text(EditorStrings.goBack),
                ),
              ],
            )
          : _MessageView(
              onBack: _close,
              message: EditorStrings.openFailed,
              detail: kDebugMode ? '$error' : null,
              actions: [
                FilledButton(
                  onPressed: _retry,
                  child: const Text(EditorStrings.retry),
                ),
                OutlinedButton(
                  onPressed: _close,
                  child: const Text(EditorStrings.goBack),
                ),
              ],
            );
    } else {
      screen = _MessageView(
        onBack: _close,
        message: EditorStrings.openingNote,
        showProgress: true,
      );
    }

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: screen,
    );
  }
}

/// [←] of the toolbar (04-editor 6.9.1: no tooltip, a semantics label only).
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    icon: const Icon(Icons.arrow_back, semanticLabel: EditorStrings.back),
  );
}

/// B5 body: the note title and the back button; '설정' in the more menu when
/// onOpenSettings is given.
class _ReadyView extends StatelessWidget {
  const _ReadyView({
    required this.session,
    required this.onBack,
    required this.onOpenSettings,
  });

  final core.NoteSession session;
  final VoidCallback onBack;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final openSettings = onOpenSettings;
    return Scaffold(
      appBar: AppBar(
        leading: _BackButton(onPressed: onBack),
        title: Text(session.note.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (openSettings != null) _MoreMenu(onOpenSettings: openSettings),
        ],
      ),
      body: const Center(child: Text(EditorStrings.placeholderBody)),
    );
  }
}

/// [⋯] more menu (04-editor 6.9.1). B5 has only '설정'.
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      MenuItemButton(
        onPressed: onOpenSettings,
        child: const Text(EditorStrings.settings),
      ),
    ],
    builder: (context, controller, child) => IconButton(
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      icon: const Icon(Icons.more_horiz, semanticLabel: EditorStrings.more),
    ),
  );
}

/// Opening / not found / open failed (04-editor 6.17.1): a centred message
/// with optional progress indicator, detail text and buttons, under an app
/// bar that keeps the back button.
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.onBack,
    required this.message,
    this.detail,
    this.showProgress = false,
    this.actions = const [],
  });

  final VoidCallback onBack;
  final String message;
  final String? detail;
  final bool showProgress;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return Scaffold(
      appBar: AppBar(leading: _BackButton(onPressed: onBack)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showProgress) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
              ],
              Text(message, textAlign: TextAlign.center),
              if (detail != null) ...[
                const SizedBox(height: 8),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
