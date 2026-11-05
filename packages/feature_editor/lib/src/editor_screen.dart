// lib/src/editor_screen.dart — contract 00-overview 7.2.17, 04-editor 4.2.
//
// Foundation step B5 (contract 7.6) gave the final constructor, the screen
// states of 04-editor 6.17.1 (opening / note not found / open failed / ready)
// and the back button that flushes the note session before onClose.
// E-04 adds the per-note ProviderScope (6.13.1 #4). E-13: EditorRoot (states,
// leaving with flushAll and '저장하는 중…') and EditorBody (ui/editor_body.dart).
import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import 'scope/editor_scope.dart';
import 'ui/editor_body.dart';
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
    ref.listen<AsyncValue<core.NoteSession>>(
      core.noteSessionProvider(widget.noteId),
      (previous, next) {
        // A missing note is a normal screen state (N-6), not an error report.
        if (next
            case AsyncError(:final error, :final stackTrace, isLoading: false)
            when error is! core.EntityNotFoundException) {
          _report(error, stackTrace, 'while opening note ${widget.noteId}');
        }
      },
    );

    // Per-note scope: only EDITOR providers are overridden here (contract
    // 7.3.3); CORE and INK providers stay in the root container.
    return ProviderScope(
      key: ValueKey(widget.noteId),
      overrides: [
        editorNoteIdProvider.overrideWithValue(widget.noteId),
        editorInitialPageIdProvider.overrideWithValue(widget.initialPageId),
      ],
      child: EditorRoot(
        onClose: widget.onClose,
        onOpenSettings: widget.onOpenSettings,
      ),
    );
  }
}

/// Shown when leaving waits on flushAll for longer than this (6.17.4).
const Duration _savingNoticeDelay = Duration(milliseconds: 300);

/// Inside the per-note scope: opening / not found / open failed / no pages /
/// ready (6.17.1) from editorSessionProvider — the body is built only once it
/// has a value, so everything below may read editorSessionValueProvider —
/// and leaving (6.17.4): back button, system back (PopScope) and the
/// 'not found' / 'open failed' buttons.
class EditorRoot extends ConsumerStatefulWidget {
  const EditorRoot({super.key, required this.onClose, this.onOpenSettings});

  final VoidCallback onClose;
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<EditorRoot> createState() => _EditorRootState();
}

class _EditorRootState extends ConsumerState<EditorRoot> {
  /// A close is in progress (waiting for flushAll): further back presses are
  /// ignored, so onClose runs once.
  bool _closing = false;
  bool _showSaving = false;
  Timer? _savingTimer;

  /// With an open session: the running interaction is cancelled (a stroke
  /// whose pen has not lifted is not committed), then flushAll —
  /// session.flush() and the editor's own debounced writes — and onClose
  /// runs only after it has completed. No timeout: CORE write Futures stay
  /// pending while a failed commit is retried (contract 7.2.9 v1.2). After
  /// 300 ms '저장하는 중…' shows. Failed writes are reported by flushAll.
  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (ref.read(editorSessionProvider).value != null) {
      ref.read(editorInputRouterProvider).cancelAll();
      _savingTimer = Timer(_savingNoticeDelay, () {
        if (mounted) setState(() => _showSaving = true);
      });
      await ref.read(editorCommandsProvider).flushAll();
      _savingTimer?.cancel();
    }
    if (!mounted) return;
    widget.onClose();
  }

  void _retry() {
    ref.invalidate(core.noteSessionProvider(ref.read(editorNoteIdProvider)));
  }

  @override
  void dispose() {
    _savingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: Stack(
        fit: StackFit.expand,
        children: [_buildState(), if (_showSaving) const _SavingNotice()],
      ),
    );
  }

  Widget _buildState() {
    final session = ref.watch(editorSessionProvider);
    if (session.value case final core.NoteSession open) {
      return _ReadyOrEmpty(
        session: open,
        onBack: _close,
        onOpenSettings: widget.onOpenSettings,
      );
    }
    if (session.hasError && !session.isLoading) {
      final error = session.error;
      return error is core.EntityNotFoundException
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
    }
    return _MessageView(
      onBack: _close,
      message: EditorStrings.openingNote,
      showProgress: true,
    );
  }
}

/// EditorBody, or '페이지가 없어요' + [페이지 추가] (not on a read-only note)
/// for a note without pages (guard against a CORE rule violation, 6.17.1).
class _ReadyOrEmpty extends ConsumerWidget {
  const _ReadyOrEmpty({
    required this.session,
    required this.onBack,
    required this.onOpenSettings,
  });

  final core.NoteSession session;
  final VoidCallback onBack;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages =
        ref.watch(core.notePagesProvider(session.noteId)).value ??
        session.pages;
    if (pages.isNotEmpty) {
      return EditorBody(onBack: onBack, onOpenSettings: onOpenSettings);
    }
    final readOnly = ref.watch(editorReadOnlyProvider);
    return _MessageView(
      onBack: onBack,
      message: EditorStrings.noPages,
      actions: [
        if (!readOnly)
          FilledButton(
            onPressed: () => unawaited(
              ref.read(editorCommandsProvider).addPageAtEndLikeLast(),
            ),
            child: const Text(EditorStrings.addPage),
          ),
      ],
    );
  }
}

/// '저장하는 중…' over the screen while leaving waits on the writes; it also
/// keeps further input away.
class _SavingNotice extends StatelessWidget {
  const _SavingNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.scrim.withValues(alpha: 0.2),
      child: Center(
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text(EditorStrings.saving),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [←] of the message screens (04-editor 6.9.1: no tooltip, a semantics
/// label only).
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    icon: const Icon(Icons.arrow_back, semanticLabel: EditorStrings.back),
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
