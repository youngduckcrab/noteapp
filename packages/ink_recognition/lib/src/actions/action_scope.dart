// lib/src/actions/action_scope.dart — (internal) m5-7/05-library 6.3, 6.16,
// contract 7.2.10 (v2.1, CD2-15 'first await' rule).
//
// RecognitionAction.run(context, target) is a function outside the widget
// tree: it has no WidgetRef. Every run takes, SYNCHRONOUSLY and before its
// first await, ① the ProviderContainer (RecognitionActionScope.of — one
// ProviderScope.containerOf(listen: false)) ② the ScaffoldMessenger and the
// Navigator of the editor body's context (ActionRun.capture). Providers are
// read lazily from the container (the app's root container outlives the
// editor body). After an await the run checks context.mounted and, when the
// editor is gone, ends without a snack bar or a sheet.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../ports/handwriting_recognizer.dart';
import '../ports/math_recognizer.dart';
import '../providers.dart';
import 'recognition_actions.dart';

/// The providers an action reads (6.3).
final class RecognitionActionScope {
  RecognitionActionScope._(this.container);

  /// `ProviderScope.containerOf(context, listen: false)` — once per run.
  factory RecognitionActionScope.of(BuildContext context) {
    debugLookups++;
    return RecognitionActionScope._(
      ProviderScope.containerOf(context, listen: false),
    );
  }

  /// How many times [RecognitionActionScope.of] ran (unit/recognition_actions_test
  /// pins 'one containerOf before the first microtask' per action).
  @visibleForTesting
  static int debugLookups = 0;

  final ProviderContainer container;

  /// handwritingRecognizerProvider
  HandwritingRecognizer get handwriting =>
      container.read(handwritingRecognizerProvider);

  /// mathRecognizerProvider
  MathRecognizer get math => container.read(mathRecognizerProvider);

  /// noteStoreProvider (flush before reading what was just written — 6.13.5).
  core.NoteStore get store => container.read(core.noteStoreProvider);

  /// noteContentReaderProvider
  core.NoteContentReader get content =>
      container.read(core.noteContentReaderProvider);

  core.HandwritingRepository get handwritingRepo =>
      container.read(core.handwritingRepositoryProvider);

  core.SettingsRepository get settings =>
      container.read(core.settingsRepositoryProvider);

  /// pageThumbnailRendererProvider (null in tests / foundation)
  core.PageThumbnailRenderer? get renderer =>
      container.read(core.pageThumbnailRendererProvider);

  /// idGeneratorProvider.newId()
  String newId() => container.read(core.idGeneratorProvider).newId();

  /// clockProvider.now().millisecondsSinceEpoch
  core.EpochMillis nowMs() =>
      container.read(core.clockProvider).now().millisecondsSinceEpoch;
}

/// One run of one action: what the run captured before its first await
/// (6.3) plus the two rules every run keeps — at most one `execute`
/// (6.16 — one undo step) and no snack bar once the editor body is gone.
final class ActionRun {
  ActionRun._({
    required this.actionId,
    required this.context,
    required this.target,
    required this.scope,
    required this.messenger,
    required this.navigator,
  });

  /// Captures the scope, the messenger and the navigator synchronously.
  /// Throws when [context] has no ProviderScope (the caller reports it).
  factory ActionRun.capture(
    String actionId,
    BuildContext context,
    RecognitionTarget target,
  ) {
    final scope = RecognitionActionScope.of(context);
    return ActionRun._(
      actionId: actionId,
      context: context,
      target: target,
      scope: scope,
      messenger: ScaffoldMessenger.maybeOf(context),
      navigator: Navigator.maybeOf(context),
    );
  }

  final String actionId;

  /// The editor body's context (contract 7.2.10) — mounted while the editor
  /// is open.
  final BuildContext context;
  final RecognitionTarget target;
  final RecognitionActionScope scope;
  final ScaffoldMessengerState? messenger;
  final NavigatorState? navigator;

  bool _executed = false;

  bool get mounted => context.mounted;

  /// Whether [execute] already ran.
  bool get executed => _executed;

  /// target.execute — at most one command per run (one undo step; a second
  /// call after a successful one is a bug: StateError, which the run's guard
  /// or the sheet reports). Throws like NoteSession.execute
  /// (ReadOnlyNoteException …) — a refused command does not count, so the
  /// sheet that shows the notice stays usable.
  void execute(core.EditCommand command) {
    if (_executed) {
      throw StateError('$actionId: execute runs at most once per action');
    }
    target.execute(command);
    _executed = true;
  }

  /// A snack bar through the messenger captured before the first await;
  /// nothing when the editor body is no longer mounted (6.3).
  void showSnackBar(String text) {
    if (!context.mounted) return;
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }
}
