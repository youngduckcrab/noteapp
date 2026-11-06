// Internal (not exported). Value of the sync.heldRecords keys (07-sync 6.3.2, S-13): records
// of kinds this app does not know, kept as their exact codec bytes until an app update can
// apply them, plus a rewind mark for chunks that could not be kept.
//
//   sync.heldRecords   {"a": [writer's kinds], "e": earliest stored serverTime | null,
//                       "n": parts in use, "o": mark | null, "v": 2}
//   mark               {"a": [kinds of the app that set it] | null, "f": serverTime,
//                       "k": [kind names | "*"]}
//   sync.heldRecords.N {"p": N, "r": [entry, …], "v": 2}   ('' when unused)
//   entry              {"b": base64 record bytes, "by": author, "c": chunk id, "fv": fv text,
//                       "i": index, "id": id, "k": kind, "op": 1 | 2,
//                       "ra": releaseAtMillis (re-applied record held by K1 only),
//                       "s": serverTime, "sc": scope}
//
// All text is canonical JSON. Entries are sorted (s, c, i) and packed into the parts in that
// order; an entry is never split across parts. A chunk's unknown records are stored all
// together or not at all (then only the mark grows — contract 7.2.8 ②).
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../backend/remote_chunk.dart';
import '../codec/canonical_json.dart';
import '../codec/chunk_codec.dart';
import '../common/server_cursor.dart';
import 'meta_keys.dart';

/// A synthetic chunk of held records (original id, scope, serverTime and author; payload =
/// the assembled record bytes) and, per record of its payload, the index the record had in
/// the original chunk — the key [HeldRecords.settle] takes.
@immutable
final class ReapplyChunk {
  const ReapplyChunk(this.chunk, this.indexes);
  final RemoteChunk chunk;
  final List<int> indexes;
}

/// The rewind mark (see [HeldRecords.mark]).
typedef HeldRecordsMark = ({
  ServerCursor from,
  Set<String> kinds,
  Set<String>? writtenBy,
});

final class HeldRecords {
  HeldRecords({
    this.maxPartBytes = defaultMaxPartBytes,
    this.maxTotalBytes = defaultMaxTotalBytes,
    required Set<String> knownKinds,
  }) : knownKinds = Set.unmodifiable(knownKinds),
       _entries = [],
       _keys = {},
       _wasCorrupt = false;

  HeldRecords._(
    this.maxPartBytes,
    this.maxTotalBytes,
    this.knownKinds,
    this._entries,
    this._keys,
    this._mark,
    this._wasCorrupt,
  );

  /// Per meta value < 256 KiB (1st-round contract 7.2.10): base64 and the JSON frame fit.
  static const int defaultMaxPartBytes = 224 * 1024;

  /// Head + all parts (contract 7.2.8 ③). At the defaults it never binds: the parts hold at
  /// most maxParts × defaultMaxPartBytes = 2,016 KiB and the head stays far below the 32 KiB
  /// left — the real cap is the per-part packing (a record entry is never split across
  /// parts, 6.3.2). Tests lower it (S27 (c)) to reach the all-or-nothing branch with small
  /// records.
  static const int defaultMaxTotalBytes = 2 * 1024 * 1024;

  /// sync.heldRecords.1 … .9
  static const int maxParts = 9;

  /// The mark kind of a corrupt value: every kind.
  static const String allKinds = '*';

  /// Value version of the head and the parts.
  static const int version = 2;

  /// `{"p":1,"r":[],"v":2}` — the frame of a part around its entries.
  static const int emptyPartBytes = 20;

  final int maxPartBytes;
  final int maxTotalBytes;

  /// Kind names this app knows (written as the head's "a").
  final Set<String> knownKinds;

  /// Sorted by (serverTime, chunk id, index); fits the caps at all times.
  final List<_Entry> _entries;

  /// Dedup keys (kind, id, fv text) of [_entries].
  final Set<String> _keys;

  _Mark? _mark;
  bool _wasCorrupt;

  /// [values]: MetaKeys.heldRecordKeys → stored text (absent / '' = empty). Corrupt head or
  /// part (bad JSON, wrong v, part count mismatch, wrong p, bad base64, a value over the caps)
  /// → records dropped and the mark becomes {f: head summary or 0, k: ['*'], a: head 'a' or
  /// null}; [wasCorrupt] true so the caller writes the converted value at once (log warning).
  /// Never throws.
  factory HeldRecords.decode(
    Map<String, String?> values, {
    required Set<String> knownKinds,
    int maxPartBytes = defaultMaxPartBytes,
    int maxTotalBytes = defaultMaxTotalBytes,
  }) {
    final out = HeldRecords(
      knownKinds: knownKinds,
      maxPartBytes: maxPartBytes,
      maxTotalBytes: maxTotalBytes,
    );
    final headText = MetaKeys.present(values[MetaKeys.heldRecords]);
    final partTexts = [
      for (final k in MetaKeys.heldRecordParts) MetaKeys.present(values[k]),
    ];
    if (headText == null) {
      if (partTexts.every((t) => t == null)) return out;
      return out.._corrupt(from: 0, writtenBy: null);
    }
    final _Head head;
    try {
      head = _Head.parse(headText);
    } on FormatException {
      return out.._corrupt(from: 0, writtenBy: null);
    }
    try {
      final entries = <_Entry>[];
      final keys = <String>{};
      for (var p = 1; p <= maxParts; p++) {
        final text = partTexts[p - 1];
        if (p > head.n) {
          if (text != null) throw const FormatException('part past n');
          continue;
        }
        if (text == null) throw const FormatException('part missing');
        for (final e in _parsePart(text, p)) {
          if (keys.add(e.key)) entries.add(e);
        }
      }
      entries.sort(_Entry.compare);
      if (!out._fits(entries)) throw const FormatException('over the caps');
      out._entries.addAll(entries);
      out._keys.addAll(keys);
      out._mark = head.mark;
      return out;
    } on FormatException {
      final summary = [?head.earliest, ?head.mark?.from];
      return out.._corrupt(
        from: summary.isEmpty ? 0 : summary.reduce((a, b) => a < b ? a : b),
        writtenBy: head.writtenBy,
      );
    }
  }

  /// The value read by [HeldRecords.decode] was corrupt and has been converted to an
  /// all-kinds mark.
  bool get wasCorrupt => _wasCorrupt;

  HeldRecords copy() => HeldRecords._(
    maxPartBytes,
    maxTotalBytes,
    knownKinds,
    List.of(_entries),
    Set.of(_keys),
    _mark,
    _wasCorrupt,
  );

  /// No record and no mark.
  bool get isEmpty => _entries.isEmpty && _mark == null;

  /// Stored records (SyncEngineDebug.heldRecords).
  int get length => _entries.length;

  /// Some stored record waits for its K1 release time (ra — [dueChunks]).
  bool get hasReleaseTimes => _entries.any((e) => e.releaseAt != null);

  /// Stored + marked kinds ('*' when corrupt).
  Set<String> get kinds => {for (final e in _entries) e.kind, ...?_mark?.kinds};

  /// Rewind mark: chunks NOT stored (over the cap, or a corrupt value). [from] = earliest
  /// chunk serverTime among them; [kinds] may contain '*'; [writtenBy] = the knownKinds of the
  /// app that set the mark (null if unknown — a corrupt head).
  HeldRecordsMark? get mark {
    final m = _mark;
    if (m == null) return null;
    return (
      from: ServerCursor(m.from),
      kinds: Set.unmodifiable(m.kinds),
      writtenBy: m.writtenBy == null ? null : Set.unmodifiable(m.writtenBy!),
    );
  }

  /// Chunk-level all-or-nothing (v2.1, contract 7.2.8 ②). Dedup by (kind, id, fv text). If
  /// every unknown record of [chunk] (new and already stored) fits under maxPartBytes per part
  /// and maxTotalBytes in all, they are stored; otherwise NONE of them is stored — records
  /// already stored under chunk.id are removed — and the mark takes min(from,
  /// chunk.serverTime) and the chunk's kinds. A chunk the mark already covers (serverTime ≥
  /// mark.from and kinds ⊆ mark.kinds or '*' ∈ mark.kinds) is not stored. Returns how many
  /// records were NEW (stored or marked).
  int add(RemoteChunk chunk, List<UnknownKindRecord> records) {
    if (records.isEmpty) return 0;
    final kinds = {for (final r in records) r.kindName};
    final m = _mark;
    if (m != null &&
        chunk.serverTime.micros >= m.from &&
        (m.kinds.contains(allKinds) || m.kinds.containsAll(kinds))) {
      return 0;
    }
    final fresh = <_Entry>[];
    final freshKeys = <String>{};
    for (final r in records) {
      final e = _Entry.of(chunk, r);
      if (_keys.contains(e.key) || !freshKeys.add(e.key)) continue;
      fresh.add(e);
    }
    if (fresh.isEmpty) return 0;
    final candidate = [..._entries, ...fresh]..sort(_Entry.compare);
    if (_fits(candidate)) {
      _entries
        ..clear()
        ..addAll(candidate);
      _keys.addAll(freshKeys);
      return fresh.length;
    }
    final removedKinds = _removeChunks({chunk.id});
    _widenMark(chunk.serverTime.micros, {...kinds, ...removedKinds});
    return fresh.length;
  }

  /// Stored records whose kind [isKnown] now and that have no release time (ra), regrouped
  /// into synthetic chunks, ordered by (serverTime, chunk id, index). The records STAY stored
  /// until [settle].
  List<ReapplyChunk> knownChunks(bool Function(String kindName) isKnown) =>
      _group(_entries.where((e) => e.releaseAt == null && isKnown(e.kind)));

  /// Stored records with ra ≤ [referenceMillis] (K1-held during a re-apply), as above.
  List<ReapplyChunk> dueChunks(int referenceMillis) => _group(
    _entries.where((e) {
      final ra = e.releaseAt;
      return ra != null && ra <= referenceMillis;
    }),
  );

  /// After a successful re-apply call: records of [applied] are removed, records of
  /// [heldUntil] (chunk id + index → releaseAtMillis) stay with ra set (K1 — contract 7.2.8
  /// ⑤). Should the longer entries no longer fit the caps, the chunks of [heldUntil] go to
  /// the mark instead (their kinds are known, so the next load rewinds to them).
  void settle({
    required Iterable<(String chunkId, int index)> applied,
    required Map<(String chunkId, int index), int> heldUntil,
  }) {
    final done = applied.toSet();
    final next = <_Entry>[];
    for (final e in _entries) {
      final at = (e.chunkId, e.index);
      final ra = heldUntil[at];
      if (ra != null) {
        next.add(e.releaseAt == ra ? e : e.withReleaseAt(ra));
      } else if (done.contains(at)) {
        _keys.remove(e.key);
      } else {
        next.add(e);
      }
    }
    _entries
      ..clear()
      ..addAll(next);
    if (_fits(_entries)) return;
    _spill({for (final (chunkId, _) in heldUntil.keys) chunkId});
    if (!_fits(_entries)) _spill({for (final e in _entries) e.chunkId});
  }

  /// When the mark should fire now (a marked kind is known, or '*' and [knownKinds] holds a
  /// kind writtenBy lacks — an app update — or writtenBy == null): the mark is cleared and
  /// its from returned (the caller rewinds the cursor to from − cursorOverlap). Otherwise
  /// null.
  ServerCursor? takeMarkIfDue() {
    final m = _mark;
    if (m == null) return null;
    final writtenBy = m.writtenBy;
    final due =
        m.kinds.any((k) => k != allKinds && knownKinds.contains(k)) ||
        (m.kinds.contains(allKinds) &&
            (writtenBy == null || !writtenBy.containsAll(knownKinds)));
    if (!due) return null;
    _mark = null;
    return ServerCursor(m.from);
  }

  /// MetaKeys.heldRecordKeys → text for every key ('' for an unused part — writeMeta cannot
  /// delete; all '' when empty). Canonical JSON, records sorted (s, c, i) and packed into
  /// parts in that order.
  Map<String, String> encode() {
    if (isEmpty) {
      return {for (final k in MetaKeys.heldRecordKeys) k: MetaKeys.cleared};
    }
    final parts = _layout(_entries);
    if (parts == null) throw StateError('HeldRecords over the caps');
    return {
      MetaKeys.heldRecords: _headText(parts.length, _earliestOf(_entries)),
      for (final (i, k) in MetaKeys.heldRecordParts.indexed)
        k: i < parts.length ? _partText(i + 1, parts[i]) : MetaKeys.cleared,
    };
  }

  // ---------------------------------------------------------------------------------------

  void _corrupt({required int from, required Set<String>? writtenBy}) {
    _entries.clear();
    _keys.clear();
    _mark = _Mark(from, const {allKinds}, writtenBy);
    _wasCorrupt = true;
  }

  void _widenMark(int from, Set<String> kinds) {
    final m = _mark;
    _mark = m == null
        ? _Mark(from, kinds, knownKinds)
        : _Mark(from < m.from ? from : m.from, {
            ...m.kinds,
            ...kinds,
          }, m.writtenBy);
  }

  /// Removes every record of [chunkIds]; returns their kinds.
  Set<String> _removeChunks(Set<String> chunkIds) {
    final kinds = <String>{};
    _entries.removeWhere((e) {
      if (!chunkIds.contains(e.chunkId)) return false;
      kinds.add(e.kind);
      _keys.remove(e.key);
      return true;
    });
    return kinds;
  }

  /// Moves the records of [chunkIds] to the mark.
  void _spill(Set<String> chunkIds) {
    int? from;
    for (final e in _entries) {
      if (chunkIds.contains(e.chunkId) &&
          (from == null || e.serverTime < from)) {
        from = e.serverTime;
      }
    }
    if (from == null) return;
    _widenMark(from, _removeChunks(chunkIds));
  }

  int? _earliestOf(List<_Entry> sorted) =>
      sorted.isEmpty ? null : sorted.first.serverTime;

  String _headText(int partCount, int? earliest) {
    final m = _mark;
    return canonicalJson({
      'a': knownKinds.toList()..sort(),
      'e': earliest,
      'n': partCount,
      'o': m?.toJson(),
      'v': version,
    });
  }

  static String _partText(int p, List<_Entry> entries) =>
      '{"p":$p,"r":[${entries.map((e) => e.json).join(',')}],"v":$version}';

  /// Next-fit packing of [sorted] into at most maxParts parts of maxPartBytes; null when it
  /// does not fit.
  List<List<_Entry>>? _layout(List<_Entry> sorted) {
    final parts = <List<_Entry>>[];
    var current = <_Entry>[];
    var bytes = emptyPartBytes;
    for (final e in sorted) {
      final grow = current.isEmpty ? e.length : e.length + 1;
      if (bytes + grow <= maxPartBytes) {
        current.add(e);
        bytes += grow;
        continue;
      }
      if (current.isEmpty || parts.length + 1 == maxParts) return null;
      parts.add(current);
      current = [e];
      bytes = emptyPartBytes + e.length;
      if (bytes > maxPartBytes) return null;
    }
    if (current.isNotEmpty) parts.add(current);
    return parts;
  }

  /// [sorted] fits maxPartBytes per part, maxParts parts and maxTotalBytes in all.
  bool _fits(List<_Entry> sorted) {
    final parts = _layout(sorted);
    if (parts == null) return false;
    var total = _utf8Length(_headText(parts.length, _earliestOf(sorted)));
    for (final part in parts) {
      total += emptyPartBytes + part.length - 1;
      for (final e in part) {
        total += e.length;
      }
    }
    return total <= maxTotalBytes;
  }

  static List<ReapplyChunk> _group(Iterable<_Entry> sorted) {
    final byChunk = <String, List<_Entry>>{};
    for (final e in sorted) {
      (byChunk[e.chunkId] ??= []).add(e);
    }
    final out = [for (final entries in byChunk.values) _synthetic(entries)];
    out.sort((a, b) {
      final byTime = a.chunk.serverTime.compareTo(b.chunk.serverTime);
      return byTime != 0 ? byTime : a.chunk.id.compareTo(b.chunk.id);
    });
    return out;
  }

  static ReapplyChunk _synthetic(List<_Entry> entries) {
    entries.sort((a, b) => a.index.compareTo(b.index));
    final first = entries.first;
    String? maxHlc;
    for (final e in entries) {
      final h = e.hlcText;
      if (h != null && (maxHlc == null || h.compareTo(maxHlc) > 0)) maxHlc = h;
    }
    return ReapplyChunk(
      RemoteChunk(
        id: first.chunkId,
        scope: first.scope,
        authorNodeId: first.author,
        recordCount: entries.length,
        format: ChunkCodec.formatVersion,
        kind: ChunkKind.delta,
        maxHlc: maxHlc ?? '',
        payload: ChunkCodec.assemble([for (final e in entries) e.bytes]),
        serverTime: ServerCursor(first.serverTime),
      ),
      [for (final e in entries) e.index],
    );
  }

  static List<_Entry> _parsePart(String text, int p) {
    final json = _decodeJson(text);
    if (json is! Map<String, Object?>) {
      throw const FormatException('part is not an object');
    }
    if (json['v'] != version) throw const FormatException('part version');
    if (json['p'] != p) throw const FormatException('part number');
    final r = json['r'];
    if (r is! List<Object?>) throw const FormatException('part records');
    return [for (final e in r) _Entry.parse(e)];
  }
}

/// UTF-8 length of [text] without encoding it (as utf8.encode counts: a lone surrogate is
/// U+FFFD, three bytes).
int _utf8Length(String text) {
  var n = 0;
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final c = units[i];
    if (c < 0x80) {
      n += 1;
    } else if (c < 0x800) {
      n += 2;
    } else if (c >= 0xD800 &&
        c <= 0xDBFF &&
        i + 1 < units.length &&
        units[i + 1] >= 0xDC00 &&
        units[i + 1] <= 0xDFFF) {
      n += 4;
      i++;
    } else {
      n += 3;
    }
  }
  return n;
}

Object? _decodeJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    throw const FormatException('not JSON');
  }
}

int _int(Object? v, String what) {
  if (v is! int || v < 0) throw FormatException('bad $what');
  return v;
}

String _str(Object? v, String what) {
  if (v is! String) throw FormatException('bad $what');
  return v;
}

Set<String> _names(Object? v, String what) {
  if (v is! List<Object?>) throw FormatException('bad $what');
  return {for (final n in v) _str(n, what)};
}

@immutable
final class _Mark {
  const _Mark(this.from, this.kinds, this.writtenBy);
  final int from;
  final Set<String> kinds;
  final Set<String>? writtenBy;

  Map<String, Object?> toJson() => {
    'a': writtenBy == null ? null : (writtenBy!.toList()..sort()),
    'f': from,
    'k': kinds.toList()..sort(),
  };

  static _Mark? parse(Object? json) {
    if (json == null) return null;
    if (json is! Map<String, Object?>) throw const FormatException('bad mark');
    final a = json['a'];
    final kinds = _names(json['k'], 'mark kinds');
    if (kinds.isEmpty) throw const FormatException('empty mark');
    return _Mark(
      _int(json['f'], 'mark from'),
      kinds,
      a == null ? null : _names(a, 'mark writer'),
    );
  }
}

final class _Head {
  _Head(this.n, this.earliest, this.writtenBy, this.mark);
  final int n;
  final int? earliest;
  final Set<String> writtenBy;
  final _Mark? mark;

  static _Head parse(String text) {
    final json = _decodeJson(text);
    if (json is! Map<String, Object?>) {
      throw const FormatException('head is not an object');
    }
    if (json['v'] != HeldRecords.version) {
      throw const FormatException('head version');
    }
    final n = _int(json['n'], 'n');
    if (n > HeldRecords.maxParts) throw const FormatException('n');
    final e = json['e'];
    return _Head(
      n,
      e == null ? null : _int(e, 'e'),
      _names(json['a'], 'a'),
      _Mark.parse(json['o']),
    );
  }
}

final class _Entry {
  _Entry({
    required this.chunkId,
    required this.serverTime,
    required this.scope,
    required this.author,
    required this.index,
    required this.kind,
    required this.op,
    required this.id,
    required this.fv,
    required this.bytes,
    this.releaseAt,
    this.base64Text,
  });

  factory _Entry.of(RemoteChunk chunk, UnknownKindRecord r) => _Entry(
    chunkId: chunk.id,
    serverTime: chunk.serverTime.micros,
    scope: chunk.scope,
    author: chunk.authorNodeId,
    index: r.index,
    kind: r.kindName,
    op: r.op,
    id: r.id ?? '',
    // A purge has no field versions: its HLC stands in (6.3.2 dedup key).
    fv: canonicalJson(r.op == 0x02 ? {'h': r.header['h']} : r.header['fv']),
    bytes: r.bytes,
  );

  factory _Entry.parse(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('entry is not an object');
    }
    final op = json['op'];
    if (op is! int || (op != 0x01 && op != 0x02)) {
      throw const FormatException('entry op');
    }
    final Uint8List bytes;
    final b = _str(json['b'], 'b');
    try {
      bytes = base64Decode(b);
    } on FormatException {
      throw const FormatException('entry bytes');
    }
    if (bytes.isEmpty || bytes[0] != op) {
      throw const FormatException('entry bytes');
    }
    final ra = json['ra'];
    return _Entry(
      chunkId: _str(json['c'], 'c'),
      serverTime: _int(json['s'], 's'),
      scope: _str(json['sc'], 'sc'),
      author: _str(json['by'], 'by'),
      index: _int(json['i'], 'i'),
      kind: _str(json['k'], 'k'),
      op: op,
      id: _str(json['id'], 'id'),
      fv: _str(json['fv'], 'fv'),
      bytes: bytes,
      releaseAt: ra == null ? null : _int(ra, 'ra'),
      base64Text: b,
    );
  }

  final String chunkId;
  final int serverTime;
  final String scope;
  final String author;
  final int index;
  final String kind;
  final int op;
  final String id;
  final String fv;
  final Uint8List bytes;
  final int? releaseAt;

  /// Dedup key (kind, id, fv text).
  late final String key = '$kind\u0000$id\u0000$fv';

  /// The stored 'b' text when read back (no second base64 pass).
  final String? base64Text;

  /// Canonical JSON; 'b' (first key, base64 needs no escaping) is written as is.
  late final String json = () {
    final rest = canonicalJson({
      'by': author,
      'c': chunkId,
      'fv': fv,
      'i': index,
      'id': id,
      'k': kind,
      'op': op,
      'ra': ?releaseAt,
      's': serverTime,
      'sc': scope,
    });
    return '{"b":"${base64Text ?? base64Encode(bytes)}",${rest.substring(1)}';
  }();

  /// UTF-8 length of [json].
  late final int length = _utf8Length(json);

  /// Newest HLC text of the record (field versions max, or the purge HLC); null if unreadable.
  String? get hlcText {
    try {
      final v = jsonDecode(fv);
      if (op == 0x02) {
        return v is Map<String, Object?> && v['h'] is String
            ? Hlc.parse(v['h']! as String).toString()
            : null;
      }
      return v is Map<String, Object?>
          ? EntityFieldVersions.fromJson(v).max.toString()
          : null;
    } on FormatException {
      return null;
    }
  }

  _Entry withReleaseAt(int releaseAt) => _Entry(
    chunkId: chunkId,
    serverTime: serverTime,
    scope: scope,
    author: author,
    index: index,
    kind: kind,
    op: op,
    id: id,
    fv: fv,
    bytes: bytes,
    releaseAt: releaseAt,
    base64Text: base64Text,
  );

  static int compare(_Entry a, _Entry b) {
    final byTime = a.serverTime.compareTo(b.serverTime);
    if (byTime != 0) return byTime;
    final byChunk = a.chunkId.compareTo(b.chunkId);
    return byChunk != 0 ? byChunk : a.index.compareTo(b.index);
  }
}
