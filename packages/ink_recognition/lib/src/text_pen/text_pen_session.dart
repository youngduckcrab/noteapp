// lib/src/text_pen/text_pen_session.dart — (internal, text pen phase 1 —
// m5-7/05-library 6.24) the recognition session of one note screen.
//
// - update → after kTextPenRecognizeDelay (500 ms) the group's recognition
//   input strokes are split into lines (conversionLinesOf — the sheet's and
//   the indexer's grouping — with pieces of one written row merged back:
//   a wide word gap must not become a line break), at most 20 lines, and
//   recognized one after another with the sheet's rule (conversionLineInput:
//   preContext, writing area) in recog.language (read for every request).
// - The engine (handwritingRecognizerProvider, read from the editor body's
//   container synchronously) is ML Kit's on Android / iOS: one native call
//   at a time, shared with the background indexer. From the update until
//   the answer the session holds RecognitionPriority, so the indexer starts
//   no next line — the pen's lines go next.
// - Every new contact, update, clear and dispose stops the timer and bumps a
//   generation: an answer counts only while its generation is current and
//   the group is the same (the engine call itself cannot be cancelled).
//   Answers are cached by the strokes' signature (the last 8).
// - The model of the language not ready → the bubble's model card (the
//   settings' model row: [받기], Wi-Fi wait, cellular); the session goes on
//   when the model arrives. No engine (web, desktop) → '이 기기에서는 …'.
// - convert (the bubble tap) waits for the answer in flight (not started
//   again), then buildTextBox (the sheet's size and colour rule) → ONE
//   CompositeCommand([RemoveElements(group), AddObjects([box])],
//   'recog-text-pen') — after checking, AFTER buildTextBox's await (it may
//   wait for the font), that the session still wants it (no clear / dispose
//   meanwhile) and that the strokes are still the ones recognized. No usable
//   answer → the conversion sheet (fix). Nothing ever converts in the
//   background.
import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../actions/action_scope.dart';
import '../actions/object_builders.dart';
import '../actions/recognition_actions.dart';
import '../common/recognition_priority.dart';
import '../common/report_error.dart';
import '../l10n/recognition_strings.dart';
import '../math_pen/math_pen_session.dart' show mathPenSignature;
import '../model/candidates.dart';
import '../model/failures.dart';
import '../ports/handwriting_recognizer.dart';
import '../ports/model_admin.dart';
import '../providers.dart';
import '../settings/recognition_settings_keys.dart';
import '../ui/conversion_sheet.dart';
import '../ui/model_downloads.dart';
import 'text_pen.dart';
import 'text_pen_bubble.dart';

/// Pen-up → recognition.
const Duration kTextPenRecognizeDelay = Duration(milliseconds: 500);

/// How many answers the session remembers.
const int kTextPenCacheSize = 8;

/// The answer of one group: the candidate texts of each line (engine
/// order, distinct, ≤ 5) in recog.language [languageTag].
@immutable
final class TextPenResult {
  const TextPenResult(this.languageTag, this.lines);
  final String languageTag;
  final List<List<String>> lines;

  /// The lines' top candidates joined like the sheet (trimmed, no empty
  /// lines, '\n').
  String get text =>
      joinLineTexts([for (final l in lines) l.isEmpty ? '' : l.first]);

  /// Something to put in a text box.
  bool get usable => text.isNotEmpty && !isTextTooLong(text);
}

/// What the bubble shows.
sealed class TextPenView {
  const TextPenView();
}

/// Nothing yet (no group).
final class TextPenIdle extends TextPenView {
  const TextPenIdle();
}

/// '인식 중…' (scheduled or running); [previous] = the last usable text.
final class TextPenWaiting extends TextPenView {
  const TextPenWaiting({this.previous});
  final String? previous;
}

/// An answer (maybe empty — nothing recognized).
final class TextPenAnswer extends TextPenView {
  const TextPenAnswer(this.result);
  final TextPenResult result;
}

/// The engine failed — '다시'.
final class TextPenFailed extends TextPenView {
  const TextPenFailed();
}

/// No handwriting engine on this device (the web, desktops).
final class TextPenNoEngine extends TextPenView {
  const TextPenNoEngine();
}

/// The model of [languageTag] is not on the device yet — the model card.
final class TextPenNeedsModel extends TextPenView {
  const TextPenNeedsModel(this.languageTag);
  final String languageTag;
}

/// The answer of the shown request: [result] null on a failure (the bubble
/// shows it) or when [cancelled] (a newer contact / update / clear).
typedef _Shown = ({TextPenResult? result, bool cancelled});

/// The group's lines for the engine: the recognition input strokes split
/// by conversionLinesOf, pieces of one written row merged back (their
/// vertical bands overlap by at least half the smaller height), at most
/// kMaxConversionLines.
List<ConversionLineInput> textPenLinesOf(List<core.Stroke> strokes) {
  final lines = <ConversionLineInput>[];
  for (final line in conversionLinesOf(recognitionInputsOf(strokes))) {
    final i = lines.indexWhere((l) => _sameRow(l.rect, line.rect));
    if (i < 0) {
      lines.add(line);
    } else {
      final a = lines[i];
      final left = a.rect.left <= line.rect.left;
      lines[i] = ConversionLineInput([
        if (left) ...a.strokes else ...line.strokes,
        if (left) ...line.strokes else ...a.strokes,
      ]);
    }
  }
  return lines.take(kMaxConversionLines).toList();
}

bool _sameRow(core.PageRect a, core.PageRect b) {
  final overlap =
      (a.bottom < b.bottom ? a.bottom : b.bottom) -
      (a.top > b.top ? a.top : b.top);
  final smaller = a.height < b.height ? a.height : b.height;
  return smaller > 0 && overlap >= 0.5 * smaller;
}

final class TextPenSession implements RecognitionTextPenSession {
  TextPenSession(this._context, {this.delay = kTextPenRecognizeDelay});

  final RecognitionPenContext _context;
  final Duration delay;

  final ValueNotifier<TextPenView> _view = ValueNotifier(const TextPenIdle());
  final LinkedHashMap<String, TextPenResult> _cache = LinkedHashMap();
  RecognitionTarget? _group;
  Timer? _timer;
  Future<_Shown>? _inflight;
  String? _inflightSignature;
  int _generation = 0;

  /// Bumped by clear and dispose: a conversion that awaited asks it.
  int _epoch = 0;
  String? _lastUsable;
  VoidCallback? _release;
  ModelDownloads? _downloads;
  StreamSubscription<String>? _modelChanges;
  bool _disposed = false;

  /// What the bubble shows (tests).
  ValueListenable<TextPenView> get view => _view;

  /// How many recognitions went to the engine (tests).
  @visibleForTesting
  int requests = 0;

  @override
  Listenable get changes => _view;

  void _show(TextPenView v) {
    if (!_disposed) _view.value = v;
  }

  ProviderContainer? _container() {
    final context = _context.bodyContext();
    if (context == null || !context.mounted) return null;
    try {
      return ProviderScope.containerOf(context, listen: false);
    } catch (e, s) {
      reportRecognitionError(e, s, 'reading the text pen providers');
      return null;
    }
  }

  void _remember(String signature, TextPenResult result) {
    _cache.remove(signature);
    _cache[signature] = result;
    while (_cache.length > kTextPenCacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _hold(ProviderContainer container) {
    if (_release != null) return;
    try {
      _release = container.read(recognitionPriorityProvider).hold();
    } catch (e, s) {
      reportRecognitionError(e, s, 'holding the recognition priority');
    }
  }

  void _letGo() {
    final release = _release;
    _release = null;
    release?.call();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _generation++;
    _inflight = null;
    _inflightSignature = null;
    _letGo();
  }

  /// Watches the model downloads and the engine's model changes once the
  /// bubble asked for a model: the group is recognized again when it may be
  /// there.
  void _watchModels(ProviderContainer container, HandwritingRecognizer engine) {
    if (_downloads != null || _disposed) return;
    try {
      final downloads = container.read(modelDownloadsProvider);
      downloads.addListener(_onModelEvent);
      _downloads = downloads;
    } catch (e, s) {
      reportRecognitionError(e, s, 'watching the model downloads');
    }
    if (engine case final RecognizerModelAdmin admin) {
      _modelChanges = admin.modelChanges.listen((_) => _onModelEvent());
    }
  }

  void _onModelEvent() {
    if (_disposed || _view.value is! TextPenNeedsModel) return;
    retry();
  }

  @override
  void update(RecognitionTarget group) {
    if (_disposed) return;
    _stop();
    _group = group;
    final signature = mathPenSignature(group.strokes);
    final cached = _cache[signature];
    if (cached != null) {
      _showAnswer(cached);
      return;
    }
    final container = _container();
    final engine = _engineOf(container);
    if (container == null || engine == null || !engine.isAvailable) {
      _show(const TextPenNoEngine());
      return;
    }
    _show(TextPenWaiting(previous: _lastUsable));
    _hold(container);
    final generation = _generation;
    _timer = Timer(delay, () {
      if (generation != _generation || _disposed) return;
      unawaited(_recognizeShown(group, signature, container, engine));
    });
  }

  HandwritingRecognizer? _engineOf(ProviderContainer? container) {
    if (container == null) return null;
    try {
      return container.read(handwritingRecognizerProvider);
    } catch (e, s) {
      reportRecognitionError(e, s, 'reading the handwriting engine');
      return null;
    }
  }

  void _showAnswer(TextPenResult result) {
    if (result.usable) _lastUsable = result.text;
    _show(TextPenAnswer(result));
  }

  /// The request whose answer the bubble shows (kept in [_inflight] so a
  /// bubble tap waits for it instead of starting again).
  Future<_Shown> _recognizeShown(
    RecognitionTarget group,
    String signature,
    ProviderContainer container,
    HandwritingRecognizer engine,
  ) {
    _timer = null;
    final generation = ++_generation;
    _hold(container);
    final future = _runShown(group, signature, container, engine, generation);
    if (generation == _generation) {
      _inflight = future;
      _inflightSignature = signature;
    }
    return future;
  }

  Future<_Shown> _runShown(
    RecognitionTarget group,
    String signature,
    ProviderContainer container,
    HandwritingRecognizer engine,
    int generation,
  ) async {
    bool current() =>
        !_disposed && generation == _generation && identical(_group, group);
    const cancelled = (result: null, cancelled: true);
    var lang = kRecognitionLanguages.first;
    try {
      try {
        lang = recognitionLanguageOf(
          await container
              .read(core.settingsRepositoryProvider)
              .get(RecognitionSettingsKeys.language),
        );
      } catch (e, s) {
        reportRecognitionError(e, s, 'reading recog.language');
      }
      if (!current()) return cancelled;
      final state = await engine.modelState(lang);
      if (!current()) return cancelled;
      switch (state) {
        case RecognitionModelState.unsupported:
          _show(const TextPenNoEngine());
          return (result: null, cancelled: false);
        case RecognitionModelState.notDownloaded ||
            RecognitionModelState.downloading:
          _watchModels(container, engine);
          _show(TextPenNeedsModel(lang));
          return (result: null, cancelled: false);
        case RecognitionModelState.ready:
          break;
      }
      final lines = textPenLinesOf(group.strokes);
      final texts = <List<String>>[];
      for (final (i, line) in lines.indexed) {
        final previous = i == 0 || texts[i - 1].isEmpty
            ? ''
            : texts[i - 1].first;
        requests++;
        final List<TextCandidate> candidates = await engine.recognizeLine(
          conversionLineInput(
            line,
            previousText: previous,
            pageWidth: group.pageSize.width,
          ),
          languageTag: lang,
        );
        // Stale: the later lines are not asked for.
        if (!current()) return cancelled;
        texts.add(conversionCandidateTexts(candidates));
      }
      final result = TextPenResult(lang, List.unmodifiable(texts));
      _remember(signature, result);
      _showAnswer(result);
      return (result: result, cancelled: false);
    } on ModelNotReady {
      if (!current()) return cancelled;
      _watchModels(container, engine);
      _show(TextPenNeedsModel(lang));
    } on RecognizerUnsupported {
      if (!current()) return cancelled;
      _show(const TextPenNoEngine());
    } on RecognitionFailure {
      if (!current()) return cancelled; // expected (6.22) — not reported
      _show(const TextPenFailed());
    } catch (e, s) {
      reportRecognitionError(e, s, 'recognizing a text pen group');
      if (!current()) return cancelled;
      _show(const TextPenFailed());
    } finally {
      if (generation == _generation) {
        _inflight = null;
        _inflightSignature = null;
        _letGo();
      }
    }
    return (result: null, cancelled: false);
  }

  /// Recognizes the shown group again (the bubble's '다시', a model that
  /// arrived).
  void retry() {
    final group = _group;
    if (group != null) update(group);
  }

  @override
  void interrupt() {
    if (_disposed) return;
    final wasWaiting = _timer != null || _inflight != null;
    _stop();
    // The next update schedules again; until then the bubble says '인식 중…'.
    if (wasWaiting) _show(TextPenWaiting(previous: _lastUsable));
  }

  @override
  void clear() {
    if (_disposed) return;
    _stop();
    _epoch++;
    _group = null;
    _show(const TextPenIdle());
  }

  // ---- conversion ----

  @override
  Future<bool> convert(RecognitionTarget group) async {
    if (_disposed) return false;
    final signature = mathPenSignature(group.strokes);
    final container = _container(); // before any await
    final engine = _engineOf(container);
    var result = _cache[signature];
    final view = _view.value;
    final blocked =
        view is TextPenNeedsModel ||
        view is TextPenNoEngine ||
        view is TextPenFailed;
    if (result == null &&
        container != null &&
        engine != null &&
        engine.isAvailable &&
        !blocked) {
      final _Shown shown;
      final inflight = _inflight;
      if (inflight != null &&
          _inflightSignature == signature &&
          identical(_group, group)) {
        shown = await inflight; // the same request: no new one
      } else {
        _stop();
        _group = group;
        _show(TextPenWaiting(previous: _lastUsable));
        shown = await _recognizeShown(group, signature, container, engine);
      }
      // The user went on (a new contact, a tool switch …): nothing opens.
      if (shown.cancelled) return false;
      result = shown.result;
    }
    if (_disposed) return false;
    if (result != null && result.usable) return _execute(group, result.text);
    return fix(group);
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

  Future<bool> _execute(RecognitionTarget group, String text) async {
    final context = _context.bodyContext();
    if (context == null || !context.mounted || _disposed) return false;
    final live = _liveOf(group);
    if (live == null) return false; // the strokes changed meanwhile
    final RecognitionActionScope scope;
    try {
      scope = RecognitionActionScope.of(context);
    } catch (e, s) {
      reportRecognitionError(e, s, 'converting a text pen group');
      return false;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final epoch = _epoch;
    try {
      final box = await buildTextBox(
        id: scope.newId(),
        pageId: group.pageId,
        nowMs: scope.nowMs(),
        text: text,
        inputStrokes: live,
        boundsPt: group.areaPt,
        pageSize: group.pageSize,
      );
      // buildTextBox may wait for the font: still wanted, still the same
      // strokes?
      if (_disposed || epoch != _epoch || !context.mounted) return false;
      final again = _liveOf(group);
      if (again == null) return false;
      _context.execute(
        replaceStrokesCommand(
          pageId: group.pageId,
          strokes: again,
          object: box,
          label: kTextPenLabel,
        ),
      );
    } on core.ReadOnlyNoteException {
      messenger?.showSnackBar(
        const SnackBar(content: Text(RecognitionStrings.readOnly)),
      );
      return false;
    } catch (e, s) {
      reportRecognitionError(e, s, 'converting a text pen group');
      messenger?.showSnackBar(
        const SnackBar(content: Text(RecognitionStrings.runFailed)),
      );
      return false;
    }
    return true;
  }

  @override
  Future<bool> fix(RecognitionTarget group) async {
    if (_disposed) return false;
    final context = _context.bodyContext();
    if (context == null || !context.mounted) return false;
    final inputs = recognitionInputsOf(group.strokes);
    if (inputs.isEmpty) return false;
    final ActionRun run;
    try {
      run = ActionRun.capture(kTextPenActionId, context, group);
    } catch (e, s) {
      reportRecognitionError(e, s, 'opening the text pen sheet');
      return false;
    }
    try {
      await openConversion(run, inputs: inputs, copy: false);
    } catch (e, s) {
      reportRecognitionError(e, s, 'in the text pen sheet');
      return false;
    }
    return run.executed;
  }

  @override
  Widget buildBubble(
    BuildContext context,
    RecognitionTarget group,
    VoidCallback onConvert,
    VoidCallback onFix,
  ) => ValueListenableBuilder<TextPenView>(
    valueListenable: _view,
    builder: (context, view, _) =>
        TextPenBubble(view: view, onFix: onFix, onRetry: retry),
  );

  @override
  void dispose() {
    if (_disposed) return;
    _stop();
    _epoch++;
    _disposed = true;
    _downloads?.removeListener(_onModelEvent);
    _downloads = null;
    unawaited(_modelChanges?.cancel()); // never awaited (fake_async)
    _modelChanges = null;
    _view.dispose();
  }
}

/// The ActionRun id of the text pen's sheet.
const String kTextPenActionId = 'recog.textPen';
