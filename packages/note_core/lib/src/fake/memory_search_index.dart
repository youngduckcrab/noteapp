// Internal: the fake store's search index (m5-7/02-core 6.10.6 — CP-14). Units live in memory
// with the real index's id rule (a new unit = the current maximum id + 1, 1 when empty); the
// candidates are the units the FTS5 model (ftsCandidateMatches) or the one-character LIKE path
// selects, alive, most recent first, at most 2,000; judgement, ranking, snippets and rects are
// the shared search_pipeline code. ink / text / math are indexed by the fake store's own writes
// (objects, handwriting); pdf through SearchIndexWriter (pdf_io).
import 'dart:async';
import 'dart:math' as math;

import '../common/geometry.dart';
import '../common/ids.dart';
import '../model/handwriting.dart';
import '../model/page_background.dart';
import '../model/stroke.dart';
import '../search/search_match.dart';
import '../search/search_pipeline.dart';
import '../search/search_rects.dart';
import '../search/search_text.dart';
import '../search/search_types.dart';
import 'fake_note_store.dart';

final class _Unit {
  _Unit({
    required this.id,
    required this.source,
    required this.ownerKey,
    required this.seq,
    required this.body,
    this.noteId,
    this.pageId,
    this.rect,
    this.pdfRects = const [],
    this.pdfAspect,
    this.assetId,
    this.pdfIndex,
  }) : norm = SearchText.normalize(body) {
    terms = SearchText.indexTerms(norm);
  }
  final int id;
  final SearchSource source;
  final String ownerKey;
  final int seq;
  final String body;
  final String norm;
  late final String terms;
  final NoteId? noteId;
  final PageId? pageId;
  final PageRect? rect;
  final List<PageRect> pdfRects;
  final double? pdfAspect;
  final AssetId? assetId;
  final int? pdfIndex;

  SearchCandidate get candidate => SearchCandidate(
    id: id,
    source: source,
    ownerKey: ownerKey,
    seq: seq,
    norm: norm,
    noteId: noteId,
    pageId: pageId,
    assetId: assetId,
    pdfIndex: pdfIndex,
  );
}

final RegExp _pdfOwnerKey = RegExp(r'^[0-9a-f]{64}#[0-9]+$');

final class MemorySearchIndex implements SearchIndex {
  MemorySearchIndex(this.s);
  final FakeNoteStore s;

  /// Owners: (source, ownerKey) → sourceRev.
  final Map<(SearchSource, String), String> _owners = {};

  /// The note of each ink / text / math owner (a purge drops its owners, also those without
  /// units — 6.14.2). Pdf owners belong to an asset, not a note.
  final Map<(SearchSource, String), NoteId> _ownerNotes = {};

  /// Units by id (ascending insertion; ids follow the SQLite rowid rule).
  final Map<int, _Unit> _units = {};

  SearchIndexStatus _status = const SearchIndexStatus();
  final StreamController<SearchIndexStatus> _statusCtrl =
      StreamController.broadcast(sync: true);

  /// SQLite's rowid rule (no AUTOINCREMENT): the current maximum + 1, 1 when empty.
  int get _nextId => _units.isEmpty ? 1 : _units.keys.reduce(math.max) + 1;

  // ---- the store's own writes (ink / text / math) --------------------------------------

  void _replace(
    SearchSource source,
    String ownerKey,
    String sourceRev,
    List<_Unit Function(int id, int seq)> units, {
    NoteId? noteId,
  }) {
    _removeUnits(source, ownerKey);
    // The old rows go first, then each new row takes max + 1 (one transaction).
    var id = _nextId;
    for (var i = 0; i < units.length; i++) {
      final u = units[i](id++, i);
      _units[u.id] = u;
    }
    _owners[(source, ownerKey)] = sourceRev;
    if (noteId != null) _ownerNotes[(source, ownerKey)] = noteId;
  }

  void _removeUnits(SearchSource source, String ownerKey) => _units.removeWhere(
    (_, u) => u.source == source && u.ownerKey == ownerKey,
  );

  void _removeOwner(SearchSource source, String ownerKey) {
    _removeUnits(source, ownerKey);
    _owners.remove((source, ownerKey));
    _ownerNotes.remove((source, ownerKey));
  }

  /// A text box / math object was written (6.10.3 write hook): its owner is re-indexed, or
  /// removed when the object is deleted. Shapes, images and unknown objects have no text.
  void objectWritten(PageObject o) {
    final source = switch (o) {
      TextBoxObject() => SearchSource.text,
      MathObject() => SearchSource.math,
      _ => null,
    };
    if (source == null) return;
    if (o.isDeleted) {
      _removeOwner(source, o.id);
      return;
    }
    final body = switch (o) {
      TextBoxObject(:final text) => text,
      MathObject(:final latex) => latex,
      _ => '',
    };
    final noteId = s.pages[o.pageId]?.noteId;
    _replace(source, o.id, '${o.version}:${SearchText.normalizerVersion}', [
      if (noteId != null && body.trim().isNotEmpty)
        (id, seq) => _Unit(
          id: id,
          source: source,
          ownerKey: o.id,
          seq: seq,
          body: body,
          noteId: noteId,
          pageId: o.pageId,
          rect: o.bounds,
        ),
    ], noteId: noteId);
  }

  /// A handwriting result was written: one unit per non-empty line (6.10.3 'ink').
  void handwritingWritten(HandwritingText h) {
    final key = HandwritingText.idFor(h.pageId);
    if (h.isDeleted) {
      _removeOwner(SearchSource.ink, key);
      return;
    }
    final lines = [
      for (final l in h.lines)
        if (SearchText.normalize(l.text).isNotEmpty) l,
    ];
    _replace(
      SearchSource.ink,
      key,
      '${h.sourceRev}:${h.version}:${SearchText.normalizerVersion}',
      [
        for (final l in lines)
          (id, seq) => _Unit(
            id: id,
            source: SearchSource.ink,
            ownerKey: key,
            seq: seq,
            body: l.text,
            noteId: h.noteId,
            pageId: h.pageId,
            rect: l.rect,
          ),
      ],
      noteId: h.noteId,
    );
  }

  /// A purged note: the owners of its objects and handwriting go (pdf owners are per asset
  /// and stay — 6.14.2).
  void notePurged(NoteId noteId) {
    final gone = [
      for (final e in _ownerNotes.entries)
        if (e.value == noteId) e.key,
    ];
    for (final (source, key) in gone) {
      _removeOwner(source, key);
    }
  }

  // ---- SearchIndexWriter (pdf only) ------------------------------------------------------

  static void _checkPdf(SearchSource source, String ownerKey) {
    if (source != SearchSource.pdf) {
      throw ArgumentError.value(
        source,
        'source',
        'only pdf is written through SearchIndexWriter (CORE indexes ink / text / math)',
      );
    }
    if (!_pdfOwnerKey.hasMatch(ownerKey)) {
      throw ArgumentError.value(
        ownerKey,
        'ownerKey',
        "must be '<assetId>#<pdfPageIndex>'",
      );
    }
  }

  @override
  Future<String?> sourceRevOf(SearchSource source, String ownerKey) async =>
      _owners[(source, ownerKey)];

  @override
  Future<Map<String, String>> sourceRevs(SearchSource source) async => {
    for (final e in _owners.entries)
      if (e.key.$1 == source) e.key.$2: e.value,
  };

  @override
  Future<void> replaceUnits(
    SearchSource source,
    String ownerKey,
    List<SearchUnitDraft> units, {
    required String sourceRev,
  }) {
    try {
      _checkPdf(source, ownerKey);
      if (sourceRev.isEmpty || sourceRev.length > 200) {
        throw ArgumentError.value(sourceRev, 'sourceRev', '1..200 chars');
      }
      if (units.length > 10000) {
        throw ArgumentError.value(units.length, 'units', 'at most 10,000');
      }
      for (final u in units) {
        if (u.body.length > 200000) {
          throw ArgumentError.value(u.body.length, 'body', 'at most 200,000');
        }
        if (u.rects.isNotEmpty && u.rects.length != u.body.length) {
          throw ArgumentError.value(
            u.rects.length,
            'rects',
            'empty or one per UTF-16 code unit of body (${u.body.length})',
          );
        }
        for (final r in u.rects) {
          for (final f in [r.left, r.top, r.right, r.bottom]) {
            if (!f.isFinite || f < -1e-6 || f > 1 + 1e-6) {
              throw ArgumentError.value(r, 'rects', 'fractions in [0, 1]');
            }
          }
        }
        final a = u.pdfPageAspect;
        if (a != null && !(a.isFinite && a > 0)) {
          throw ArgumentError.value(a, 'pdfPageAspect', 'finite and > 0');
        }
      }
    } on ArgumentError catch (e, st) {
      return Future.error(e, st);
    }
    final hash = ownerKey.indexOf('#');
    final assetId = ownerKey.substring(0, hash);
    final pdfIndex = int.parse(ownerKey.substring(hash + 1));
    return s.write(() {
      _replace(source, ownerKey, sourceRev, [
        for (final u in units)
          (id, seq) => _Unit(
            id: id,
            source: source,
            ownerKey: ownerKey,
            seq: seq,
            body: u.body,
            // Stored at the real index's precision (1/65535 — SearchRectsCodec).
            pdfRects: u.rects.isEmpty
                ? const []
                : SearchRectsCodec.decode(SearchRectsCodec.encode(u.rects)),
            pdfAspect: u.pdfPageAspect,
            assetId: assetId,
            pdfIndex: pdfIndex,
          ),
      ]);
    });
  }

  @override
  Future<void> removeOwner(SearchSource source, String ownerKey) {
    try {
      _checkPdf(source, ownerKey);
    } on ArgumentError catch (e, st) {
      return Future.error(e, st);
    }
    return s.write(() => _removeOwner(source, ownerKey));
  }

  // ---- queries ---------------------------------------------------------------------------

  bool _livePage(PageId? pageId, NoteId? withinNote) {
    final p = pageId == null ? null : s.pages[pageId];
    if (p == null || p.isDeleted) return false;
    if (withinNote != null && p.noteId != withinNote) return false;
    return s.activeNote(p.noteId) != null;
  }

  List<SearchPageRef> _pdfPages(AssetId? assetId, int? index, NoteId? within) =>
      [
        for (final p in s.pages.values)
          if (p.background
              case PdfBackground(assetId: final a, pdfPageIndex: final i)
              when a == assetId && i == index)
            if (_livePage(p.id, within)) (noteId: p.noteId, pageId: p.id),
      ];

  bool _alive(_Unit u, NoteId? within) => u.source == SearchSource.pdf
      ? _pdfPages(u.assetId, u.pdfIndex, within).isNotEmpty
      : _livePage(u.pageId, within);

  /// [searchPages] plus whether the candidate cap or [limit] cut the result.
  ({List<PageSearchHit> hits, bool truncated}) search(
    String query, {
    required int limit,
    NoteId? withinNote,
  }) {
    final q = SearchText.normalize(query);
    if (q.isEmpty || limit <= 0) return (hits: const [], truncated: false);
    final match = SearchText.matchQuery(q);
    final ids = _units.keys.toList()..sort((a, b) => b.compareTo(a));
    final candidates = <SearchCandidate>[];
    var capped = false;
    for (final id in ids) {
      final u = _units[id]!;
      final hit = match == null
          ? likeCandidateMatches(u.norm, q)
          : ftsCandidateMatches(u.terms, match);
      if (!hit || !_alive(u, withinNote)) continue;
      if (candidates.length == kSearchCandidateCap) {
        capped = true;
        break;
      }
      candidates.add(u.candidate);
    }
    final ranked = rankSearchCandidates(
      candidates,
      q,
      pdfPages: (c) => _pdfPages(c.assetId, c.pdfIndex, withinNote),
      noteUpdatedAt: (n) => s.notes[n]?.updatedAt ?? 0,
      limit: limit,
    );
    final hits = [
      for (final page in ranked.pages)
        searchHitOf(
          page,
          q,
          detail: (c) {
            final u = _units[c.id]!;
            return (
              body: u.body,
              rect: u.rect,
              pdfRects: u.pdfRects,
              pdfAspect: u.pdfAspect,
            );
          },
          pageWidth: s.pages[page.pageId]!.size.width,
          pageHeight: s.pages[page.pageId]!.size.height,
        ),
    ];
    return (hits: List.unmodifiable(hits), truncated: capped || ranked.more);
  }

  @override
  Future<List<PageSearchHit>> searchPages(
    String query, {
    int limit = 100,
    NoteId? withinNote,
  }) async => search(query, limit: limit, withinNote: withinNote).hits;

  @override
  Stream<SearchIndexStatus> get status => Stream.multi((c) {
    c.add(_status);
    final sub = _statusCtrl.stream.listen(c.add);
    c.onCancel = sub.cancel;
  });

  void _setStatus(SearchIndexStatus next) {
    if (next == _status) return;
    _status = next;
    _statusCtrl.add(next);
  }

  /// Drops the derived rows of [sources] and rebuilds ink / text / math from the stored
  /// handwriting and objects; pdf rows are only dropped (pdf_io refills them — 6.10.5).
  @override
  Future<void> rebuild({Set<SearchSource>? sources}) async {
    final which = sources ?? SearchSource.values.toSet();
    _setStatus(
      SearchIndexStatus(
        pendingOwners: _status.pendingOwners,
        rebuilding: true,
        lastRebuildAt: _status.lastRebuildAt,
      ),
    );
    try {
      await s.write(() {
        for (final key in _owners.keys.toList()) {
          if (which.contains(key.$1)) _removeOwner(key.$1, key.$2);
        }
        for (final o in s.objects.values) {
          final source = switch (o) {
            TextBoxObject() => SearchSource.text,
            MathObject() => SearchSource.math,
            _ => null,
          };
          if (source != null && which.contains(source) && !o.isDeleted) {
            objectWritten(o);
          }
        }
        if (which.contains(SearchSource.ink)) {
          for (final h in s.handwritingRows.values) {
            if (!h.isDeleted) handwritingWritten(h);
          }
        }
      });
    } finally {
      _setStatus(
        SearchIndexStatus(
          pendingOwners: _status.pendingOwners,
          lastRebuildAt: s.now,
        ),
      );
    }
  }

  Future<void> dispose() => _statusCtrl.close();
}
