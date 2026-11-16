// lib/src/state/note_search.dart — (v2.13-search) m5-7/04-editor 17: the
// in-note search ('노트에서 찾기'), per note.
//
// Before this, the editor had no search of its own: the only search inside a
// note was pdf_io's 'PDF에서 찾기' (more menu item 'pdf.search'), which reads
// the PDF text layer and nothing else — handwriting, text boxes, converted
// text and formulas were found only by the library search. This searches
// CORE's index (SearchIndex.searchPages withinNote — the same query the
// library runs: recognised handwriting with Korean spacing tolerance, text
// boxes, formulas (LaTeX), PDF text), one hit per page, listed in page order;
// a hit's rects are the matched units in page pt (PageSearchHit.rects).
//
// The query runs [kNoteSearchDebounce] after the last keystroke. While the
// search is open it asks again [kNoteSearchRequeryQuiet] after the last
// page / page object / handwriting change of this note (new handwriting is
// recognised in the background) or SearchIndex.status event (PDF text
// indexed). Opening it and every applied query tell the handwriting slot
// (editorInkSearchProvider) so this note's pages are recognised first.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show Rect;
import 'package:note_core/note_core.dart' as core;

import '../di/editor_ink_search.dart';
import '../scope/editor_scope.dart';

/// After the last keystroke.
const Duration kNoteSearchDebounce = Duration(milliseconds: 250);

/// After the last content change of the note while the search is open.
const Duration kNoteSearchRequeryQuiet = Duration(seconds: 1);

/// At most this many pages are listed.
const int kNoteSearchLimit = 300;

/// One page's hit, in this note's page order.
@immutable
final class NoteSearchResult {
  const NoteSearchResult({
    required this.pageId,
    required this.pageIndex,
    required this.source,
    required this.snippet,
    required this.matchRange,
    required this.rectsPt,
  });

  final String pageId;

  /// 0-based index in the note (the list shows pageIndex + 1).
  final int pageIndex;
  final core.SearchSource source;
  final String snippet;
  final (int, int) matchRange;

  /// The matched parts in displayed page pt (may be empty: position
  /// unknown — the page is still shown).
  final List<Rect> rectsPt;

  /// The union of [rectsPt], or null without rects.
  Rect? get boundsPt => rectsPt.isEmpty
      ? null
      : rectsPt
            .skip(1)
            .fold<Rect>(rectsPt.first, (a, b) => a.expandToInclude(b));

  static const _rects = ListEquality<Rect>();

  @override
  bool operator ==(Object other) =>
      other is NoteSearchResult &&
      other.pageId == pageId &&
      other.pageIndex == pageIndex &&
      other.source == source &&
      other.snippet == snippet &&
      other.matchRange == matchRange &&
      _rects.equals(other.rectsPt, rectsPt);

  @override
  int get hashCode => Object.hash(
    pageId,
    pageIndex,
    source,
    snippet,
    matchRange,
    _rects.hash(rectsPt),
  );

  @override
  String toString() =>
      'NoteSearchResult(p${pageIndex + 1}, ${source.name}, "$snippet")';
}

@immutable
final class NoteSearchState {
  const NoteSearchState({
    this.isOpen = false,
    this.query = '',
    this.results = const [],
    this.searching = false,
    this.failed = false,
    this.selectedPageId,
  });

  final bool isOpen;
  final String query;

  /// Of [query] (empty for an empty query), page order.
  final List<NoteSearchResult> results;

  /// A query is waiting or running.
  final bool searching;

  /// The last query failed.
  final bool failed;

  /// The result the user went to (highlighted strongest), or null.
  final String? selectedPageId;

  NoteSearchResult? get selected =>
      results.firstWhereOrNull((r) => r.pageId == selectedPageId);

  NoteSearchState copyWith({
    bool? isOpen,
    String? query,
    List<NoteSearchResult>? results,
    bool? searching,
    bool? failed,
    String? Function()? selectedPageId,
  }) => NoteSearchState(
    isOpen: isOpen ?? this.isOpen,
    query: query ?? this.query,
    results: results ?? this.results,
    searching: searching ?? this.searching,
    failed: failed ?? this.failed,
    selectedPageId: selectedPageId != null
        ? selectedPageId()
        : this.selectedPageId,
  );

  static const _results = ListEquality<NoteSearchResult>();

  @override
  bool operator ==(Object other) =>
      other is NoteSearchState &&
      other.isOpen == isOpen &&
      other.query == query &&
      _results.equals(other.results, results) &&
      other.searching == searching &&
      other.failed == failed &&
      other.selectedPageId == selectedPageId;

  @override
  int get hashCode => Object.hash(
    isOpen,
    query,
    _results.hash(results),
    searching,
    failed,
    selectedPageId,
  );

  @override
  String toString() =>
      'NoteSearchState(open: $isOpen, "$query", ${results.length} results'
      '${searching ? ', searching' : ''}${failed ? ', failed' : ''})';
}

/// Per note (scoped).
class NoteSearchNotifier extends Notifier<NoteSearchState> {
  Timer? _debounce;
  Timer? _requery;
  int _generation = 0;
  StreamSubscription<core.ChangeBatch>? _changes;
  StreamSubscription<core.SearchIndexStatus>? _status;

  @override
  NoteSearchState build() {
    ref.watch(editorNoteIdProvider);
    ref.onDispose(_stop);
    return const NoteSearchState();
  }

  String get _noteId => ref.read(editorNoteIdProvider);

  void _stop() {
    _debounce?.cancel();
    _debounce = null;
    _requery?.cancel();
    _requery = null;
    _generation++;
    unawaited(_changes?.cancel());
    unawaited(_status?.cancel());
    _changes = null;
    _status = null;
  }

  /// Opens the search (the query and its results are kept from the last
  /// time, and asked again).
  void open() {
    if (state.isOpen) return;
    state = state.copyWith(isOpen: true);
    ref.read(editorInkSearchProvider)?.searchOpened(_noteId);
    final store = ref.read(core.noteStoreProvider);
    _changes = store.changes.listen(_onChanges, onError: (Object _) {});
    _status = ref
        .read(core.searchIndexProvider)
        .status
        .listen((_) => _scheduleRequery(), onError: (Object _) {});
    if (state.query.trim().isNotEmpty) _run();
  }

  /// Closes it; the highlight goes away, the query stays.
  void close() {
    if (!state.isOpen) return;
    _stop();
    state = state.copyWith(
      isOpen: false,
      searching: false,
      selectedPageId: () => null,
    );
  }

  void toggle() => state.isOpen ? close() : open();

  /// The field changed: asks [kNoteSearchDebounce] after the last change.
  void setQuery(String query) {
    if (query == state.query) return;
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _generation++;
      state = state.copyWith(
        query: query,
        results: const [],
        searching: false,
        failed: false,
        selectedPageId: () => null,
      );
      return;
    }
    state = state.copyWith(query: query, searching: true);
    _debounce = Timer(kNoteSearchDebounce, () {
      _debounce = null;
      ref.read(editorInkSearchProvider)?.searchOpened(_noteId);
      _run();
    });
  }

  /// [enter]: asks now.
  void submit() {
    _debounce?.cancel();
    _debounce = null;
    if (state.query.trim().isEmpty) return;
    ref.read(editorInkSearchProvider)?.searchOpened(_noteId);
    _run();
  }

  void select(String? pageId) =>
      state = state.copyWith(selectedPageId: () => pageId);

  void _onChanges(core.ChangeBatch batch) {
    final noteId = _noteId;
    final touches = batch.changes.any(
      (c) =>
          (c.kind == core.EntityKind.page ||
              c.kind == core.EntityKind.pageObject ||
              c.kind == core.EntityKind.handwriting) &&
          (c.noteId == null || c.noteId == noteId),
    );
    if (touches) _scheduleRequery();
  }

  void _scheduleRequery() {
    if (!state.isOpen || state.query.trim().isEmpty) return;
    _requery?.cancel();
    _requery = Timer(kNoteSearchRequeryQuiet, () {
      _requery = null;
      if (_debounce == null) _run();
    });
  }

  void _run() {
    final query = state.query;
    if (query.trim().isEmpty) return;
    final generation = ++_generation;
    if (!state.searching) state = state.copyWith(searching: true);
    final noteId = _noteId;
    final index = ref.read(core.searchIndexProvider);
    unawaited(
      index
          .searchPages(query, limit: kNoteSearchLimit, withinNote: noteId)
          .then(
            (hits) {
              if (generation != _generation) return;
              final results = _resultsOf(hits);
              final selected = state.selectedPageId;
              state = state.copyWith(
                results: results,
                searching: false,
                failed: false,
                selectedPageId: () =>
                    results.any((r) => r.pageId == selected) ? selected : null,
              );
            },
            onError: (Object error, StackTrace stack) {
              if (generation != _generation) return;
              FlutterError.reportError(
                FlutterErrorDetails(
                  exception: error,
                  stack: stack,
                  library: 'feature_editor',
                  context: ErrorDescription('while searching inside the note'),
                ),
              );
              state = state.copyWith(searching: false, failed: true);
            },
          ),
    );
  }

  List<NoteSearchResult> _resultsOf(List<core.PageSearchHit> hits) {
    final pages = ref.read(editorSessionValueProvider).pages;
    final indexOf = {for (final (i, p) in pages.indexed) p.id: i};
    final noteId = _noteId;
    final results = <NoteSearchResult>[
      for (final h in hits)
        if (h.noteId == noteId)
          if (indexOf[h.pageId] case final i?)
            NoteSearchResult(
              pageId: h.pageId,
              pageIndex: i,
              source: h.source,
              snippet: h.snippet,
              matchRange: h.matchRange,
              rectsPt: List.unmodifiable([
                for (final r in h.rects)
                  if (r.right > r.left && r.bottom > r.top)
                    Rect.fromLTRB(r.left, r.top, r.right, r.bottom),
              ]),
            ),
    ]..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return List.unmodifiable(results);
  }
}

final editorNoteSearchProvider =
    NotifierProvider<NoteSearchNotifier, NoteSearchState>(
      NoteSearchNotifier.new,
      dependencies: [editorNoteIdProvider, editorSessionValueProvider],
      name: 'editorNoteSearchProvider',
    );
