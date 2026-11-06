// lib/src/state/search_requery.dart — (v2) 05-library 6.1.6: when a search asks CORE again.
//
// The search is a one-time query (1차 6.14). A folder / note change asks again at once
// (1차). (v2) A change that can change content hits — page, page object, handwriting —
// asks again 1 s after the last such change, but at most 5 s after the first one, so a
// catch-up that writes more often than once a second still refreshes (S-13) and never
// asks every second. Strokes never change the index directly (handwriting arrives as a
// handwriting write), so a stroke edit asks nothing.
//
// A session commit carries the note's updatedAt as a note change next to its page /
// stroke / object changes; that note change is not a library change, so the content
// kinds decide such a batch. A trashed / purged note or any folder change is always a
// library change.
import 'dart:async' show Timer;

import 'package:note_core/note_core.dart' show ChangeBatch, EntityKind;

/// Quiet time after the last content change (6.1.6).
const Duration kSearchRequeryQuiet = Duration(seconds: 1);

/// Longest wait after the first content change (6.1.6).
const Duration kSearchRequeryMaxWait = Duration(seconds: 5);

/// What one ChangeBatch means for an open search.
enum SearchRequery { none, debounced, immediate }

/// 6.1.6 table, per batch (first rule that matches):
/// 1. a folder change, or a deleted / purged note → immediate;
/// 2. a page / pageObject / handwriting change → debounced;
/// 3. a stroke change → none (the note change beside it is the session's updatedAt);
/// 4. a note change → immediate;
/// 5. anything else (settings, presets, assets, recordings) → none.
SearchRequery searchRequeryOf(ChangeBatch batch) {
  var content = false;
  var stroke = false;
  var note = false;
  for (final c in batch.changes) {
    switch (c.kind) {
      case EntityKind.folder:
        return SearchRequery.immediate;
      case EntityKind.note:
        if (c.deleted || c.purged) return SearchRequery.immediate;
        note = true;
      case EntityKind.page || EntityKind.pageObject || EntityKind.handwriting:
        content = true;
      case EntityKind.stroke:
        stroke = true;
      case EntityKind.penPreset ||
          EntityKind.asset ||
          EntityKind.recording ||
          EntityKind.setting:
        break;
    }
  }
  if (content) return SearchRequery.debounced;
  if (stroke) return SearchRequery.none;
  return note ? SearchRequery.immediate : SearchRequery.none;
}

/// The 1 s quiet / 5 s cap timers of one open search. [requery] runs at most once per
/// window; a window starts with the first debounced batch after the last requery.
/// An immediate batch requeries at once and ends the window.
final class SearchRequeryDebouncer {
  SearchRequeryDebouncer({
    required this.requery,
    this.quiet = kSearchRequeryQuiet,
    this.maxWait = kSearchRequeryMaxWait,
  });

  final void Function() requery;
  final Duration quiet;
  final Duration maxWait;

  Timer? _quiet;
  Timer? _cap;
  bool _disposed = false;

  /// True while a debounced requery is waiting.
  bool get isPending => _quiet != null;

  void add(ChangeBatch batch) {
    if (_disposed) return;
    switch (searchRequeryOf(batch)) {
      case SearchRequery.none:
        return;
      case SearchRequery.immediate:
        _fire();
      case SearchRequery.debounced:
        _quiet?.cancel();
        _quiet = Timer(quiet, _fire);
        _cap ??= Timer(maxWait, _fire);
    }
  }

  void _fire() {
    _cancel();
    if (!_disposed) requery();
  }

  void _cancel() {
    _quiet?.cancel();
    _cap?.cancel();
    _quiet = null;
    _cap = null;
  }

  /// Idempotent; nothing runs afterwards.
  void dispose() {
    _disposed = true;
    _cancel();
  }
}
