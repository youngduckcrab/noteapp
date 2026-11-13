// lib/src/math_pen/math_pen_session.dart — (internal, math pen phase 1 —
// docs/plans/m5-7/research/math-pen-phase1.md 4.1, 4.3, 10, 11.2, 11.3) the
// recognition session of one note screen.
//
// - update → after kMathPenRecognizeDelay (500 ms — the brief's 0.4–0.6 s)
//   the group goes to mathRecognizerProvider's engine (read from the editor
//   body's container, synchronously before any await). The on-device engine
//   preprocesses in an isolate and runs its model off the UI thread; the
//   server engine is HTTP; only the server engine gets the page image
//   (renderMathPng) — the on-device one reads the traces.
// - Every new contact (interrupt), update, clear and dispose stops the timer,
//   completes the request's cancel and bumps a generation: an answer counts
//   only while its generation is current and the strokes are the same
//   (signature of ids + updatedAt) — only the newest answer.
// - Answers are cached by that signature (the last 8): a group brought back
//   by undo, or reopened unchanged, shows its formula at once.
// - convert: a usable answer (InkMathRenderer validates it) → buildMathFromPen
//   → ONE CompositeCommand([RemoveElements(group), AddObjects([math with the
//   group as ink])], 'recog-math-pen'), after checking the strokes are still
//   the ones recognized. The bubble tap waits for an answer in flight and
//   opens the LaTeX editor when there is none to use (no engine, consent,
//   failure, unusable answer); background conversions never open anything.
import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../actions/action_scope.dart';
import '../actions/object_builders.dart';
import '../actions/recognition_actions.dart';
import '../common/report_error.dart';
import '../l10n/recognition_strings.dart';
import '../math/callable_math_recognizer.dart';
import '../math/math_png.dart';
import '../model/failures.dart';
import '../model/handwriting_trace.dart';
import '../model/math_types.dart';
import '../ports/math_recognizer.dart';
import '../providers.dart';
import '../settings/recognition_settings_keys.dart';
import '../ui/latex_editor_sheet.dart';
import '../ui/math_pad_canvas.dart' show kMathPadPagePrefix;
import 'math_pen.dart';
import 'math_pen_bubble.dart';

/// Pen-up → recognition.
const Duration kMathPenRecognizeDelay = Duration(milliseconds: 500);

/// A background conversion waits at most this long for an answer.
const Duration kMathPenBackgroundTimeout = Duration(seconds: 10);

/// How many answers the session remembers.
const int kMathPenCacheSize = 8;

/// What the bubble shows.
sealed class MathPenView {
  const MathPenView();
}

/// Nothing yet (no group).
final class MathPenIdle extends MathPenView {
  const MathPenIdle();
}

/// '인식 중…' (scheduled or running); [previous] = the last usable formula.
final class MathPenWaiting extends MathPenView {
  const MathPenWaiting({this.previous});
  final String? previous;
}

/// An answer; [usable] = its LaTeX when it can be drawn, else null.
final class MathPenAnswer extends MathPenView {
  const MathPenAnswer(this.result, this.usable);
  final MathResult result;
  final String? usable;
}

/// The engine failed (the 6.11.4 text) — '다시'.
final class MathPenFailed extends MathPenView {
  const MathPenFailed(this.message);
  final String message;
}

/// No engine (ManualOnlyMathRecognizer, or none reachable).
final class MathPenNoEngine extends MathPenView {
  const MathPenNoEngine();
}

/// The server engine needs the user's consent first.
final class MathPenNeedsConsent extends MathPenView {
  const MathPenNeedsConsent();
}

/// The strokes' identity for the cache and the staleness check.
String mathPenSignature(Iterable<core.Stroke> strokes) =>
    [for (final s in strokes) '${s.id}:${s.updatedAt}'].join(',');

final class MathPenSession implements RecognitionMathPenSession {
  MathPenSession(
    this._context, {
    this.delay = kMathPenRecognizeDelay,
    this.backgroundTimeout = kMathPenBackgroundTimeout,
  });

  final RecognitionMathPenContext _context;
  final Duration delay;
  final Duration backgroundTimeout;

  final ValueNotifier<MathPenView> _view = ValueNotifier(const MathPenIdle());
  final LinkedHashMap<String, MathResult> _cache = LinkedHashMap();
  RecognitionTarget? _group;
  Timer? _timer;
  Completer<void>? _cancel;
  int _generation = 0;
  String? _lastUsable;
  bool _disposed = false;

  /// What the bubble shows (tests).
  ValueListenable<MathPenView> get view => _view;

  /// How many requests went to an engine (tests).
  @visibleForTesting
  int requests = 0;

  @override
  Listenable get changes => _view;

  void _show(MathPenView v) {
    if (!_disposed) _view.value = v;
  }

  /// The engine of the editor's container, or null (no body).
  MathRecognizer? _engine() {
    final context = _context.bodyContext();
    if (context == null || !context.mounted) return null;
    try {
      return ProviderScope.containerOf(
        context,
        listen: false,
      ).read(mathRecognizerProvider);
    } catch (e, s) {
      reportRecognitionError(e, s, 'reading the math engine');
      return null;
    }
  }

  void _remember(String signature, MathResult result) {
    _cache.remove(signature);
    _cache[signature] = result;
    while (_cache.length > kMathPenCacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _generation++;
    final cancel = _cancel;
    _cancel = null;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
  }

  @override
  void update(
    RecognitionTarget group, {
    core.MathObject? reopenedFrom,
    Set<String> reopenedStrokeIds = const {},
  }) {
    if (_disposed) return;
    _stop();
    _group = group;
    if (reopenedFrom != null && reopenedStrokeIds.isNotEmpty) {
      final seed = mathPenSignature(
        group.strokes.where((s) => reopenedStrokeIds.contains(s.id)),
      );
      if (!_cache.containsKey(seed) &&
          group.strokes.where((s) => reopenedStrokeIds.contains(s.id)).length ==
              reopenedStrokeIds.length) {
        _remember(
          seed,
          MathResult(
            latex: reopenedFrom.latex,
            engineId: reopenedFrom.engineId ?? kManualMathEngineId,
            latency: Duration.zero,
          ),
        );
      }
    }
    final signature = mathPenSignature(group.strokes);
    final cached = _cache[signature];
    if (cached != null) {
      _showAnswer(cached);
      return;
    }
    final engine = _engine();
    if (engine == null || !engine.isAvailable) {
      _show(const MathPenNoEngine());
      return;
    }
    _show(MathPenWaiting(previous: _lastUsable));
    final generation = _generation;
    _timer = Timer(delay, () {
      if (generation != _generation || _disposed) return;
      unawaited(_recognizeShown(group, signature, engine));
    });
  }

  void _showAnswer(MathResult result) {
    final usable = usableLatex(result.latex);
    if (usable != null) _lastUsable = usable;
    _show(MathPenAnswer(result, usable));
  }

  /// The request whose answer the bubble shows.
  Future<MathResult?> _recognizeShown(
    RecognitionTarget group,
    String signature,
    MathRecognizer engine,
  ) async {
    _timer = null;
    final generation = ++_generation;
    final cancel = Completer<void>();
    _cancel = cancel;
    bool current() =>
        !_disposed && generation == _generation && identical(_group, group);
    try {
      final result = await _recognize(group, engine, cancel.future);
      if (!current()) return null;
      _remember(signature, result);
      _showAnswer(result);
      return result;
    } on RecognizerCancelled {
      return null; // a newer request follows (or none is wanted)
    } on RecognizerConsentRequired {
      if (current()) _show(const MathPenNeedsConsent());
    } on RecognizerUnsupported {
      if (current()) _show(const MathPenNoEngine());
    } on RecognitionFailure catch (failure) {
      if (current()) {
        _show(
          MathPenFailed(
            RecognitionStrings.mathFailure(failure) ??
                RecognitionStrings.mathFailed,
          ),
        );
      }
    } catch (e, s) {
      reportRecognitionError(e, s, 'recognizing a math pen group');
      if (current()) _show(const MathPenFailed(RecognitionStrings.mathFailed));
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
    }
    return null;
  }

  /// One engine call for [group] (the image only for the server engine).
  Future<MathResult> _recognize(
    RecognitionTarget group,
    MathRecognizer engine,
    Future<void> cancel,
  ) async {
    requests++;
    MathPng? png;
    if (engine is CallableMathRecognizer) {
      final context = _context.bodyContext();
      final scope = context == null || !context.mounted
          ? null
          : RecognitionActionScope.of(context);
      if (scope != null) {
        png = await renderMathPng(
          scope.renderer,
          group.strokes,
          areaPt: group.areaPt,
          pageId: '$kMathPadPagePrefix${scope.newId()}',
          noteId: group.noteId,
          nowMs: scope.nowMs(),
        );
      }
    }
    return engine.recognize(
      MathInput(
        traces: [for (final s in group.strokes) HandwritingTrace.fromStroke(s)],
        png: png?.png,
        pngPxPerPt: png?.pxPerPt,
      ),
      cancel: cancel,
    );
  }

  /// Retries the shown group (the bubble's '다시').
  void retry() {
    final group = _group;
    if (group != null) update(group);
  }

  @override
  void interrupt() {
    if (_disposed) return;
    final wasWaiting = _timer != null || _cancel != null;
    _stop();
    // The next update schedules again; until then the bubble says '인식 중…'.
    if (wasWaiting) _show(MathPenWaiting(previous: _lastUsable));
  }

  @override
  void clear() {
    if (_disposed) return;
    _stop();
    _group = null;
    _show(const MathPenIdle());
  }

  // ---- conversion ----

  @override
  Future<bool> convert(
    RecognitionTarget group, {
    required bool interactive,
  }) async {
    if (_disposed) return false;
    final signature = mathPenSignature(group.strokes);
    final engine = _engine(); // before any await
    var result = _cache[signature];
    if (!interactive) {
      if (result == null && engine != null && engine.isAvailable) {
        result = await _recognizeAlone(group, engine);
        if (result != null) _remember(signature, result);
      }
      final usable = result == null ? null : usableLatex(result.latex);
      if (usable == null || result == null) return false;
      return _execute(group, usable, result.engineId);
    }
    // The bubble tap.
    var needsConsent = _view.value is MathPenNeedsConsent;
    var failed = _view.value is MathPenFailed;
    if (result == null &&
        engine != null &&
        engine.isAvailable &&
        !needsConsent &&
        !failed) {
      _stop();
      _group = group;
      _show(MathPenWaiting(previous: _lastUsable));
      result = await _recognizeShown(group, signature, engine);
      needsConsent = _view.value is MathPenNeedsConsent;
      failed = _view.value is MathPenFailed;
    }
    if (_disposed) return false;
    final usable = result == null ? null : usableLatex(result.latex);
    if (usable != null && result != null) {
      return _execute(group, usable, result.engineId);
    }
    return _openEditor(
      group,
      engine ?? const ManualOnlyMathRecognizer(),
      initialLatex: result?.latex ?? '',
      recognize: result == null,
    );
  }

  /// A request of its own (a background conversion — the shown request may
  /// be for another group): null on any failure or after the timeout.
  Future<MathResult?> _recognizeAlone(
    RecognitionTarget group,
    MathRecognizer engine,
  ) async {
    final cancel = Completer<void>();
    final timer = Timer(backgroundTimeout, () {
      if (!cancel.isCompleted) cancel.complete();
    });
    try {
      return await _recognize(group, engine, cancel.future);
    } on RecognitionFailure {
      return null;
    } catch (e, s) {
      reportRecognitionError(e, s, 'recognizing a math pen group');
      return null;
    } finally {
      timer.cancel();
      if (!cancel.isCompleted) cancel.complete();
    }
  }

  /// The strokes of [group] as they are now, when they are still the ones
  /// recognized (same ids and updatedAt), else null.
  List<core.Stroke>? _liveOf(RecognitionTarget group) {
    final live = _context.liveStrokes(group.pageId, [
      for (final s in group.strokes) s.id,
    ]);
    if (live == null || live.length != group.strokes.length) return null;
    for (var i = 0; i < live.length; i++) {
      if (live[i].updatedAt != group.strokes[i].updatedAt) return null;
    }
    return live;
  }

  /// The formula of [latex] for [strokes], or null.
  core.MathObject? _build(
    RecognitionActionScope scope,
    RecognitionTarget group,
    List<core.Stroke> strokes,
    String latex,
    String engineId,
  ) => buildMathFromPen(
    id: scope.newId(),
    pageId: group.pageId,
    nowMs: scope.nowMs(),
    latex: latex,
    engineId: engineId,
    strokes: strokes,
  );

  core.EditCommand _command(
    RecognitionTarget group,
    List<core.Stroke> strokes,
    core.MathObject math,
  ) => replaceStrokesCommand(
    pageId: group.pageId,
    strokes: strokes,
    object: math,
    label: kMathPenLabel,
  );

  bool _execute(RecognitionTarget group, String latex, String engineId) {
    final context = _context.bodyContext();
    if (context == null || !context.mounted || _disposed) return false;
    final live = _liveOf(group);
    if (live == null) return false; // the strokes changed meanwhile
    final scope = RecognitionActionScope.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final math = _build(scope, group, live, latex, engineId);
    if (math == null) return false;
    try {
      _context.execute(_command(group, live, math));
    } on core.ReadOnlyNoteException {
      messenger?.showSnackBar(
        const SnackBar(content: Text(RecognitionStrings.readOnly)),
      );
      return false;
    } catch (e, s) {
      reportRecognitionError(e, s, 'converting a math pen group');
      messenger?.showSnackBar(
        const SnackBar(content: Text(RecognitionStrings.runFailed)),
      );
      return false;
    }
    if (math.ink.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(content: Text(RecognitionStrings.mathPenInkTooLarge)),
      );
    }
    return true;
  }

  /// The LaTeX editor for the group: typing by hand (no engine), the consent
  /// card, a retry, or fixing an unusable answer. ONE command on 수식으로
  /// 바꾸기.
  Future<bool> _openEditor(
    RecognitionTarget group,
    MathRecognizer engine, {
    required String initialLatex,
    required bool recognize,
  }) async {
    final context = _context.bodyContext();
    if (context == null || !context.mounted) return false;
    final ActionRun run;
    try {
      run = ActionRun.capture('recog.mathPen', context, group);
    } catch (e, s) {
      reportRecognitionError(e, s, 'opening the math pen editor');
      return false;
    }
    final scope = run.scope;
    final settings = scope.settings;
    final view = mathAreaPage(
      group.strokes,
      areaPt: group.areaPt,
      pageId: '$kMathPadPagePrefix${scope.newId()}',
      noteId: group.noteId,
      nowMs: scope.nowMs(),
    );
    final recognition = recognize
        ? LatexRecognition(
            engine: engine,
            input: () => Future.value(
              MathInput(
                traces: [
                  for (final s in group.strokes) HandwritingTrace.fromStroke(s),
                ],
              ),
            ),
            strokesPage: view?.page,
            strokes: view?.strokes ?? const [],
            onAgreeToConsent: () =>
                settings.set(RecognitionSettingsKeys.mathConsent, true),
          )
        : null;
    try {
      return await openMathPenEditor(
        run,
        initialLatex: initialLatex,
        recognition: recognition,
        onConvert: (latex, engineId) {
          final live = _liveOf(group);
          if (live == null) return RecognitionStrings.runFailed;
          final math = _build(scope, group, live, latex, engineId);
          if (math == null) return RecognitionStrings.runFailed;
          run.execute(_command(group, live, math));
          if (math.ink.isEmpty) {
            run.showSnackBar(RecognitionStrings.mathPenInkTooLarge);
          }
          return null;
        },
      );
    } catch (e, s) {
      reportRecognitionError(e, s, 'in the math pen editor');
      return false;
    }
  }

  @override
  Future<void> fix(RecognitionTarget formula) {
    final context = _context.bodyContext();
    final math = soleMathOf(formula);
    if (context == null || !context.mounted || math == null) {
      return Future<void>.value();
    }
    return runRecognitionAction(
      RecognitionActionIds.editMath,
      context,
      formula,
      (run) => openLatexEditor(run, math),
    );
  }

  @override
  Widget buildBubble(
    BuildContext context,
    RecognitionTarget group,
    VoidCallback onConvert,
  ) => ValueListenableBuilder<MathPenView>(
    valueListenable: _view,
    builder: (context, view, _) =>
        MathPenBubble(view: view, onConvert: onConvert, onRetry: retry),
  );

  @override
  void dispose() {
    if (_disposed) return;
    _stop();
    _disposed = true;
    _view.dispose();
  }
}
