// lib/src/di/editor_ink_search.dart — (v2.13-search, m5-7/04-editor 17)
// whether handwriting can be found by the in-note search ('노트에서 찾기')
// yet. The app shell overrides the slot with an adapter over
// ink_recognition's handwriting search readiness (FeatureWiringModule, from
// the recognition module's contribution) — the same readiness the library's
// search hint reads; feature_editor never imports ink_recognition or
// feature_library (7.1 rule 1). null (no recognition, the web) → no hint.
import 'package:flutter/foundation.dart' show Listenable, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;

/// Why handwriting is (not yet) found inside the note.
enum EditorInkSearchPhase {
  /// Nothing to say (this note's handwriting is searchable, or no engine).
  ready,

  /// '검색용 자동 인식' is off → [EditorInkSearch.turnOnAutoIndex].
  autoIndexOff,

  /// The recognition model is missing → [EditorInkSearch.downloadModel].
  modelMissing,

  /// The model is being downloaded.
  modelDownloading,

  /// A Wi-Fi-only download waits for Wi-Fi (cellular after a confirmation).
  waitingForWifi,

  /// The last download failed.
  modelFailed,

  /// Pages of this note are still being recognized
  /// ([EditorInkSearchState.remainingPages]; 0 while they are counted).
  indexing,

  /// Handwriting cannot be recognized on this device — said once, no action.
  unsupported,
}

@immutable
final class EditorInkSearchState {
  const EditorInkSearchState({
    this.phase = EditorInkSearchPhase.ready,
    this.remainingPages = 0,
    this.confirmCellularFirst = false,
  });

  final EditorInkSearchPhase phase;

  /// [EditorInkSearchPhase.indexing]: pages of this note left.
  final int remainingPages;

  /// A download may use cellular data at once: confirm before
  /// [EditorInkSearch.downloadModel] (then `cellular: true`).
  final bool confirmCellularFirst;

  @override
  bool operator ==(Object other) =>
      other is EditorInkSearchState &&
      other.phase == phase &&
      other.remainingPages == remainingPages &&
      other.confirmCellularFirst == confirmCellularFirst;

  @override
  int get hashCode => Object.hash(phase, remainingPages, confirmCellularFirst);

  @override
  String toString() =>
      'EditorInkSearchState(${phase.name}, remaining $remainingPages)';
}

/// The handwriting side of the in-note search.
abstract interface class EditorInkSearch {
  /// Fires when [stateOf] may answer differently.
  Listenable get changes;

  /// What the in-note search of note [noteId] says about handwriting now.
  EditorInkSearchState stateOf(String noteId);

  /// [켜기]: turns '검색용 자동 인식' on (and asks for the model).
  Future<void> turnOnAutoIndex();

  /// [지금 받기]: downloads the model (Wi-Fi only per the setting), or with
  /// [cellular] at once — only after the user confirmed it.
  Future<void> downloadModel({bool cellular = false});

  /// The in-note search of [noteId] opened or applied a query: that note's
  /// pages waiting for recognition go first (cheap; may be called often).
  void searchOpened(String noteId);
}

final editorInkSearchProvider = Provider<EditorInkSearch?>(
  (ref) => null,
  name: 'editorInkSearchProvider',
); // null → no handwriting hint
