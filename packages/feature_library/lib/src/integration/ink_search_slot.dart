// lib/src/integration/ink_search_slot.dart — (handwriting search,
// m5-7/05-library 6.19a) whether handwriting can be found by the library
// search yet. The app shell overrides the slot with an adapter over
// ink_recognition's handwriting search readiness (FeatureWiringModule, from
// the recognition module's contribution); feature_library never imports
// ink_recognition (7.1 rule 1). null (no recognition, the web) → no hint.
import 'package:flutter/foundation.dart' show ValueListenable, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;

/// Why handwriting is (not yet) found.
enum LibraryInkSearchPhase {
  /// Nothing to say (handwriting is searchable, or no engine).
  ready,

  /// '검색용 자동 인식' is off → [LibraryInkSearch.turnOnAutoIndex].
  autoIndexOff,

  /// The recognition model is missing → [LibraryInkSearch.downloadModel].
  modelMissing,

  /// The model is being downloaded.
  modelDownloading,

  /// A Wi-Fi-only download waits for Wi-Fi (cellular after a confirmation).
  waitingForWifi,

  /// The last download failed.
  modelFailed,

  /// Pages are still being recognized ([LibraryInkSearchState.remainingPages]).
  indexing,
}

@immutable
final class LibraryInkSearchState {
  const LibraryInkSearchState({
    this.phase = LibraryInkSearchPhase.ready,
    this.remainingPages = 0,
    this.confirmCellularFirst = false,
  });

  final LibraryInkSearchPhase phase;

  /// [LibraryInkSearchPhase.indexing]: pages left.
  final int remainingPages;

  /// A download may use cellular data at once: confirm before
  /// [LibraryInkSearch.downloadModel] (then `cellular: true`).
  final bool confirmCellularFirst;

  @override
  bool operator ==(Object other) =>
      other is LibraryInkSearchState &&
      other.phase == phase &&
      other.remainingPages == remainingPages &&
      other.confirmCellularFirst == confirmCellularFirst;

  @override
  int get hashCode => Object.hash(phase, remainingPages, confirmCellularFirst);

  @override
  String toString() =>
      'LibraryInkSearchState(${phase.name}, remaining $remainingPages)';
}

abstract interface class LibraryInkSearch {
  ValueListenable<LibraryInkSearchState> get state;

  /// [켜기]: turns '검색용 자동 인식' on (and asks for the model).
  Future<void> turnOnAutoIndex();

  /// [지금 받기]: downloads the model (Wi-Fi only per the setting), or with
  /// [cellular] at once — only after the user confirmed it.
  Future<void> downloadModel({bool cellular = false});

  /// The search was opened: recognize the pages waiting for it now.
  void searchOpened();
}

final libraryInkSearchProvider = Provider<LibraryInkSearch?>(
  (ref) => null,
  name: 'libraryInkSearchProvider',
); // null → no handwriting hint
