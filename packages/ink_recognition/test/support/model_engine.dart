// A handwriting engine whose model downloads the test finishes (m5-7/05-library
// 6.7.4 — the settings rows of L2-18; the conversion sheet's model card
// (L2-15) and the lab's rows (L2-19) can use it too). Like the ML Kit
// adapter: modelState is `downloading` while one of its ensureModel calls
// runs (unless another one already finished); a finished download makes the
// model ready and emits modelChanges.
// FakeHandwritingRecognizer (testing.dart) finishes ensureModel at once, so
// it cannot show 'waiting for Wi-Fi'.
import 'dart:async';

import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/ports/model_admin.dart';

final class ControlledModelEngine
    implements HandwritingRecognizer, RecognizerModelAdmin {
  ControlledModelEngine({this.enforcesWifiOnly = true});

  /// true = Android, false = iPad.
  @override
  bool enforcesWifiOnly;

  /// modelState answers; a missing tag → notDownloaded.
  final Map<String, RecognitionModelState> states = {};

  /// Every ensureModel call (tag, wifiOnly), in order.
  final List<(String, bool)> ensureCalls = [];
  final List<String> deleteCalls = [];
  final List<Completer<void>> _downloads = [];
  final StreamController<String> _changes = StreamController.broadcast();

  @override
  Stream<String> get modelChanges => _changes.stream;

  @override
  String get engineId => 'controlled';

  @override
  bool get isAvailable => true;

  /// A finished download wins over another request of the tag that still
  /// runs (Android's Wi-Fi request after [지금 셀룰러로 받기] — 6.7.4).
  @override
  Future<RecognitionModelState> modelState(String languageTag) async {
    if (states[languageTag] == RecognitionModelState.ready) {
      return RecognitionModelState.ready;
    }
    final running = [
      for (final (i, (tag, _)) in ensureCalls.indexed)
        if (tag == languageTag && !_downloads[i].isCompleted) i,
    ];
    if (running.isNotEmpty) return RecognitionModelState.downloading;
    return states[languageTag] ?? RecognitionModelState.notDownloaded;
  }

  @override
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true}) {
    ensureCalls.add((languageTag, wifiOnly));
    final download = Completer<void>();
    _downloads.add(download);
    return download.future;
  }

  /// Ends the [index]-th ensureModel call (default: the last) — the model is
  /// ready and modelChanges gets its tag.
  void finish([int? index]) {
    final i = index ?? ensureCalls.length - 1;
    final tag = ensureCalls[i].$1;
    states[tag] = RecognitionModelState.ready;
    _downloads[i].complete();
    _changes.add(tag);
  }

  /// Fails the [index]-th ensureModel call (default: the last).
  void fail(Object error, [int? index]) {
    _downloads[index ?? ensureCalls.length - 1].completeError(error);
  }

  @override
  Future<void> deleteModel(String languageTag) async {
    deleteCalls.add(languageTag);
    states[languageTag] = RecognitionModelState.notDownloaded;
    _changes.add(languageTag);
  }

  @override
  Future<List<TextCandidate>> recognizeLine(
    HandwritingLineInput line, {
    required String languageTag,
  }) async => const [];

  @override
  Future<void> dispose() async {
    unawaited(_changes.close());
  }
}
