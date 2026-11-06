// lib/src/providers.dart — contract m5-7/00-overview 7.2.11 (m5-7/05-library
// 4.4.7–4.4.9, 6.10).
//
// The providers of the recognition service. The app shell changes them ONLY
// through recognitionOverrides() (7.3.3); feature packages never import them.
//
// - handwritingRecognizerProvider / mathRecognizerProvider: final (defaults —
//   unsupported handwriting, manual math).
// - (L2-07) recognitionOverrides(): exactly 3 overrides (4.4.8) — the
//   platform handwriting engine (stub on the web, native file otherwise —
//   platform_recognizer.dart; disposed with the container), the math engine
//   (manual without an endpoint, CallableMathRecognizer with one — its
//   http.Client closed with the container) and GeometricShapeFitter for INK.
// - (L2-11) handwritingIndexerProvider: null on the web or without an
//   available engine; otherwise an indexer whose `enabled` follows
//   recog.autoIndex (store.settings.watch). Never calls start() (INFRA's
//   idle task 'recognition.indexer' does — 7.3.3); disposed with the
//   container (dispose() is idempotent — INFRA may call it too).
// - (L2-11) recognitionDevOverlayLinesProvider: the 4.4.9 lines (status,
//   last job, model state, math engine); no indexer → the fixed line.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import 'common/report_error.dart';
import 'engines/platform_recognizer.dart';
import 'indexer/handwriting_indexer.dart';
import 'indexer/indexer_status.dart';
import 'l10n/recognition_strings.dart';
import 'math/callable_math_recognizer.dart';
import 'model/candidates.dart';
import 'ports/handwriting_recognizer.dart';
import 'ports/math_recognizer.dart';
import 'ports/model_admin.dart';
import 'settings/recognition_settings_keys.dart';
import 'shapes/geometric_shape_fitter.dart';

// --- providers: overridden ONLY through recognitionOverrides() ---
final handwritingRecognizerProvider = Provider<HandwritingRecognizer>(
  (ref) => const UnsupportedHandwritingRecognizer(),
  name: 'handwritingRecognizerProvider',
);

final mathRecognizerProvider = Provider<MathRecognizer>(
  (ref) => const ManualOnlyMathRecognizer(),
  name: 'mathRecognizerProvider',
);

@immutable
final class RecognitionConfig {
  const RecognitionConfig({this.mathEndpoint, this.idTokenProvider});

  /// callable URL (emulator in dev); null → manual only
  final Uri? mathEndpoint;

  /// M4 auth later; null → no Authorization header
  final Future<String?> Function()? idTokenProvider;

  @override
  bool operator ==(Object other) =>
      other is RecognitionConfig &&
      other.mathEndpoint == mathEndpoint &&
      other.idTokenProvider == idTokenProvider;

  @override
  int get hashCode => Object.hash(mathEndpoint, idTokenProvider);

  @override
  String toString() =>
      'RecognitionConfig(mathEndpoint: $mathEndpoint, '
      'idTokenProvider: ${idTokenProvider == null ? 'none' : 'set'})';
}

/// web: unsupported handwriting; native: ML Kit (*_native.dart); math: CallableMathRecognizer
/// (package:http, callable protocol) when mathEndpoint != null. Also overrides
/// ink.inkShapeFitterProvider with GeometricShapeFitter on every platform.
// Exactly these 3 (4.4.8); handwritingIndexerProvider and
// recognitionDevOverlayLinesProvider follow from them.
List<Override> recognitionOverrides({
  RecognitionConfig config = const RecognitionConfig(),
}) => buildRecognitionOverrides(config: config);

/// (internal) [recognitionOverrides] with the engine and HTTP client makers
/// replaceable — tests count the engine's dispose and the client's close.
List<Override> buildRecognitionOverrides({
  required RecognitionConfig config,
  HandwritingRecognizer Function() createHandwriting =
      createPlatformHandwritingRecognizer,
  http.Client Function() createClient = http.Client.new,
}) => [
  handwritingRecognizerProvider.overrideWith((ref) {
    final recognizer = createHandwriting();
    ref.onDispose(
      () => unawaited(
        recognizer.dispose().then<void>(
          (_) {},
          onError: (Object e, StackTrace s) =>
              reportRecognitionError(e, s, 'handwriting engine dispose'),
        ),
      ),
    );
    return recognizer;
  }),
  mathRecognizerProvider.overrideWith((ref) {
    final endpoint = config.mathEndpoint;
    if (endpoint == null) return const ManualOnlyMathRecognizer();
    final client = createClient();
    ref.onDispose(client.close);
    final settings = ref.watch(core.settingsRepositoryProvider);
    return CallableMathRecognizer(
      endpoint: endpoint,
      client: client,
      idTokenProvider: config.idTokenProvider,
      consent: () => settings.get(RecognitionSettingsKeys.mathConsent),
    );
  }),
  ink.inkShapeFitterProvider.overrideWithValue(const GeometricShapeFitter()),
];

/// null unless recognizer available (and never on the web — G-1). The
/// provider disposes the indexer; it never starts it (INFRA's idle task
/// 'recognition.indexer' calls start() — 7.3.3).
final handwritingIndexerProvider = Provider<HandwritingIndexer?>((ref) {
  final recognizer = ref.watch(handwritingRecognizerProvider);
  if (kIsWeb || !recognizer.isAvailable) return null;
  final store = ref.watch(core.noteStoreProvider);
  // recog.autoIndex (device scope); false until the first value. A plain
  // stream subscription, not ref.listen: INFRA only reads this provider
  // (its idle task), and a provider nobody listens to is paused by
  // Riverpod 3 — the setting must reach the indexer anyway.
  final enabled = ValueNotifier<bool>(false);
  var disposed = false;
  final autoIndex = store.settings
      .watch(RecognitionSettingsKeys.autoIndex)
      .listen(
        (value) {
          if (!disposed) enabled.value = value;
        },
        onError: (Object e, StackTrace s) =>
            reportRecognitionError(e, s, 'recog.autoIndex'),
      );
  final indexer = HandwritingIndexer(
    store: store,
    recognizer: recognizer,
    enabled: enabled,
  ); // foreground: default AppLifecycleListener (CP-L10)
  ref.onDispose(() {
    disposed = true;
    unawaited(autoIndex.cancel());
    unawaited(indexer.dispose());
    enabled.dispose();
  });
  return indexer;
}, name: 'handwritingIndexerProvider');

/// (v2.1, CP-L2 = INFRA CP4) Developer overlay lines; same shape as mediaDevOverlayLinesProvider.
// 4.4.9: 'phase · lang · queue n · done n · failed n' (status.toString()),
// 'job <ms> ms · lines n · page <id>' ('job —' before the first job),
// 'model <lang>: ready|notDownloaded|downloading|unsupported' (+ ' · waiting
// for Wi-Fi' while a wifiOnly download waits), 'math: manual|callable(consent
// on|off)' (another engine: 'math: <engineId>'). No indexer → the fixed line.
final recognitionDevOverlayLinesProvider =
    Provider<ValueListenable<List<String>>>((ref) {
      final indexer = ref.watch(handwritingIndexerProvider);
      if (indexer == null) {
        final fixed = ValueNotifier<List<String>>(const [
          RecognitionStrings.noIndexerLine,
        ]);
        ref.onDispose(fixed.dispose);
        return fixed;
      }
      final recognizer = ref.watch(handwritingRecognizerProvider);
      final math = ref.watch(mathRecognizerProvider);
      final settings = ref.watch(core.settingsRepositoryProvider);
      final metrics = metricsOf(indexer);
      var lang = 'ko';
      RecognitionModelState? model;
      bool? consent;
      var disposed = false;
      var modelAsk = 0;

      List<String> build() {
        final status = indexer.status.value;
        final job = metrics.lastJob.value;
        final waitingWifi =
            status.phase == HandwritingIndexerPhase.waitingModel &&
            (status.lastError?.contains('waiting for Wi-Fi') ?? false);
        final jobLine = job == null
            ? 'job —'
            : 'job ${job.ourMs.toStringAsFixed(1)} ms · '
                  'lines ${job.lines} · page ${job.pageId}';
        final wifi = waitingWifi ? ' · waiting for Wi-Fi' : '';
        final modelLine = 'model $lang: ${model?.name ?? '—'}$wifi';
        final mathLine = switch (math) {
          ManualOnlyMathRecognizer() => 'math: manual',
          CallableMathRecognizer() =>
            'math: callable(consent ${consent ?? false ? 'on' : 'off'})',
          _ => math.isAvailable ? 'math: ${math.engineId}' : 'math: manual',
        };
        return [status.toString(), jobLine, modelLine, mathLine];
      }

      final lines = ValueNotifier<List<String>>(build());
      void update() {
        if (!disposed) lines.value = build();
      }

      Future<void> askModel() async {
        final ask = ++modelAsk;
        final tag = lang;
        RecognitionModelState? state;
        try {
          state = await recognizer.modelState(tag);
        } on Object {
          state = null;
        }
        if (disposed || ask != modelAsk) return;
        model = state;
        update();
      }

      indexer.status.addListener(update);
      metrics.lastJob.addListener(update);
      final subscriptions = <StreamSubscription<Object?>>[
        settings.watch(RecognitionSettingsKeys.language).listen((value) {
          lang = recognitionLanguageOf(value);
          unawaited(askModel());
        }),
        if (math is CallableMathRecognizer)
          settings.watch(RecognitionSettingsKeys.mathConsent).listen((value) {
            consent = value;
            update();
          }),
        if (recognizer case final RecognizerModelAdmin admin)
          admin.modelChanges.listen((tag) {
            if (tag == lang) unawaited(askModel());
          }),
      ];
      unawaited(askModel());
      ref.onDispose(() {
        disposed = true;
        indexer.status.removeListener(update);
        metrics.lastJob.removeListener(update);
        for (final s in subscriptions) {
          unawaited(s.cancel());
        }
        lines.dispose();
      });
      return lines;
    }, name: 'recognitionDevOverlayLinesProvider');
