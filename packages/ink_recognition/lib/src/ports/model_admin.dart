// lib/src/ports/model_admin.dart — (internal) model management beside the
// contract port (m5-7/05-library 6.7.4). Implemented by the ML Kit adapter
// (L2-08) and FakeHandwritingRecognizer; the indexer (6.9.6) and the settings
// section (6.18) check `recognizer is RecognizerModelAdmin` — the contract
// port HandwritingRecognizer has no delete and no change stream.

/// Model management of a handwriting engine (no public name — 4.3).
abstract interface class RecognizerModelAdmin {
  /// languageTag whose state changed (download / delete)
  Stream<String> get modelChanges;
  Future<void> deleteModel(String languageTag);

  /// android true, iOS false (plugin ignores the flag)
  bool get enforcesWifiOnly;
}
