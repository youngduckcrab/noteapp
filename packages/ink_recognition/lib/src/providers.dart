// lib/src/providers.dart — contract m5-7/00-overview 7.2.11 (m5-7/05-library
// 4.4.7–4.4.9, 6.10).
//
// The providers of the recognition service. The app shell changes them ONLY
// through recognitionOverrides() (7.3.3); feature packages never import them.
//
// 2차 foundation step R2-B6 (contract 7.6.2):
// - handwritingRecognizerProvider / mathRecognizerProvider: final (defaults).
// - recognitionOverrides(): only INK's shape fitter port, overridden with
//   NoShapeFitter. LIBRARY L2-07 adds the platform handwriting engine and the
//   callable math engine and switches the fitter to GeometricShapeFitter
//   (exactly 3 overrides — 4.4.8).
// - handwritingIndexerProvider: null on the web or without an available
//   engine; otherwise an indexer whose `enabled` stays false (L2-11 ties it to
//   recog.autoIndex). Never calls start() (INFRA's idle task
//   'recognition.indexer' does — 7.3.3).
// - recognitionDevOverlayLinesProvider: the fixed 'no indexer' line (L2-11
//   adds the 4.4.9 lines).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import 'indexer/handwriting_indexer.dart';
import 'ports/handwriting_recognizer.dart';
import 'ports/math_recognizer.dart';

/// R2-B6 developer overlay line while there is no indexer (4.4.9). Moves to
/// RecognitionStrings with L2-07.
const String _noIndexerLine = '손글씨 색인 없음 (이 기기에서 인식 불가)';

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
// R2-B6 (contract 7.6.2): the shape fitter only, with INK's NoShapeFitter;
// [config] is not read yet (L2-07).
List<Override> recognitionOverrides({
  RecognitionConfig config = const RecognitionConfig(),
}) => [ink.inkShapeFitterProvider.overrideWithValue(const ink.NoShapeFitter())];

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
      final lines = ValueNotifier<List<String>>(const [_noIndexerLine]);
      ref.onDispose(lines.dispose);
      return lines;
    }, name: 'recognitionDevOverlayLinesProvider');
