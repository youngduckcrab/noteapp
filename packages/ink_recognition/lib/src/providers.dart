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
// - 2차 foundation step R2-B6 still (contract 7.6.2) — handwritingIndexerProvider: null on the web or without an available
//   engine; otherwise an indexer whose `enabled` stays false (L2-11 ties it to
//   recog.autoIndex). Never calls start() (INFRA's idle task
//   'recognition.indexer' does — 7.3.3).
// - recognitionDevOverlayLinesProvider: the fixed 'no indexer' line (L2-11
//   adds the 4.4.9 lines).
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
import 'l10n/recognition_strings.dart';
import 'math/callable_math_recognizer.dart';
import 'ports/handwriting_recognizer.dart';
import 'ports/math_recognizer.dart';
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
  // R2-B6: stays false; L2-11 follows recog.autoIndex.
  final enabled = ValueNotifier<bool>(false);
  final indexer = HandwritingIndexer(
    store: ref.watch(core.noteStoreProvider),
    recognizer: recognizer,
    enabled: enabled,
  ); // foreground: default AppLifecycleListener (CP-L10)
  ref.onDispose(() {
    unawaited(indexer.dispose());
    enabled.dispose();
  });
  return indexer;
}, name: 'handwritingIndexerProvider');

/// (v2.1, CP-L2 = INFRA CP4) Developer overlay lines; same shape as mediaDevOverlayLinesProvider.
final recognitionDevOverlayLinesProvider =
    Provider<ValueListenable<List<String>>>((ref) {
      final lines = ValueNotifier<List<String>>(const [
        RecognitionStrings.noIndexerLine,
      ]);
      ref.onDispose(lines.dispose);
      return lines;
    }, name: 'recognitionDevOverlayLinesProvider');
