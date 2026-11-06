// HeldRecords cases (07-sync 6.3.2, S2-6) shared by the VM test (engine/held_records_test.dart)
// and Chrome (web/pure_logic_browser_test.dart): the value of the sync.heldRecords keys —
// round trip, order, dedup, the split into a head and nine parts, chunk-level all-or-nothing,
// the rewind mark, re-apply chunks and ra, corrupt values, and the count the default caps
// keep (computed from the constants and a measured entry length, never a fixed number).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/canonical_json.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/engine/held_records.dart';
import 'package:sync_engine/src/engine/meta_keys.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/raw_records.dart';

const String kHeldV0 = '001793750400000-0000-3f2a9c0d11e0b7a4';
const String kHeldV1 = '001793750405000-0001-3f2a9c0d11e0b7a4';
const String kAuthor = '3f2a9c0d11e0b7a4';

/// Every EntityKind name (an updated app).
final Set<String> kAllKinds = {for (final k in EntityKind.values) k.name};

/// An 'old app' that does not know handwriting (6.3.8).
final Set<String> kOldKinds = kAllKinds.difference({'handwriting'});

RemoteChunk heldChunk(
  String id,
  int serverTime, {
  String scope = 'n1',
  String author = kAuthor,
}) => RemoteChunk(
  id: id,
  scope: scope,
  authorNodeId: author,
  recordCount: 1,
  format: 1,
  kind: ChunkKind.delta,
  maxHlc: kHeldV0,
  payload: Uint8List(0),
  serverTime: ServerCursor(serverTime),
);

/// A bookmark upsert (a kind no app knows yet) of about [pad] + 120 bytes.
Uint8List bookmark(String id, {String v = kHeldV0, int pad = 0}) =>
    _bookmark(id, v: v, pad: pad);

Uint8List _bookmark(String id, {String v = kHeldV0, int pad = 0}) =>
    rawUpsertRecord(
      'bookmark',
      {'id': id, 'noteId': 'n1', 'label': 'x' * pad, 'version': v},
      {'b': v},
    );

/// A handwriting upsert as a newer app writes it (unknown to the old app).
Uint8List handwriting(String pageId, {String v = kHeldV0, String pad = ''}) =>
    rawUpsertRecord(
      'handwriting',
      {
        'id': 'hw_$pageId',
        'noteId': 'n1',
        'pageId': pageId,
        'engineId': 'e/1:ko',
        'sourceRev': '0123456789abcdef',
        'lines': [
          {'text': '미분 $pad', 'strokeIds': <String>[]},
        ],
        'createdAt': 1,
        'updatedAt': 1,
        'deletedAt': null,
        'version': v,
      },
      {'b': v},
    );

/// The unknown records of a payload of [records] for an app knowing [known].
List<UnknownKindRecord> unknownIn(
  List<Uint8List> records, {
  Set<String>? known,
}) => ChunkCodec.decodeTolerant(
  ChunkCodec.assemble(records),
  isKnownKind: (known ?? kOldKinds).contains,
).unknown;

HeldRecords held({
  Set<String>? known,
  int maxPartBytes = HeldRecords.defaultMaxPartBytes,
  int maxTotalBytes = HeldRecords.defaultMaxTotalBytes,
}) => HeldRecords(
  knownKinds: known ?? kOldKinds,
  maxPartBytes: maxPartBytes,
  maxTotalBytes: maxTotalBytes,
);

HeldRecords reread(
  HeldRecords h, {
  Set<String>? known,
  int maxPartBytes = HeldRecords.defaultMaxPartBytes,
  int maxTotalBytes = HeldRecords.defaultMaxTotalBytes,
}) => HeldRecords.decode(
  h.encode(),
  knownKinds: known ?? h.knownKinds,
  maxPartBytes: maxPartBytes,
  maxTotalBytes: maxTotalBytes,
);

Map<String, Object?> headOf(Map<String, String> value) =>
    jsonDecode(value[MetaKeys.heldRecords]!) as Map<String, Object?>;

/// The entries of every part, in part order.
List<Map<String, Object?>> entriesOf(Map<String, String> value) => [
  for (final k in MetaKeys.heldRecordParts)
    if (value[k]!.isNotEmpty)
      for (final e in (jsonDecode(value[k]!) as Map)['r'] as List)
        e as Map<String, Object?>,
];

/// Records per part.
List<int> partSizes(Map<String, String> value) => [
  for (final k in MetaKeys.heldRecordParts)
    if (value[k]!.isNotEmpty)
      ((jsonDecode(value[k]!) as Map)['r'] as List).length,
];

/// UTF-8 length of the entry text of a value that holds one record.
int entryLengthOf(HeldRecords single) =>
    utf8.encode(single.encode()[MetaKeys.heldRecordParts.first]!).length -
    HeldRecords.emptyPartBytes;

void heldRecordsCases() {
  test('the ten keys: the head, then sync.heldRecords.1 … .9', () {
    expect(MetaKeys.heldRecordKeys, [
      'sync.heldRecords',
      for (var i = 1; i <= 9; i++) 'sync.heldRecords.$i',
    ]);
    expect(MetaKeys.heldRecordParts, hasLength(HeldRecords.maxParts));
  });

  test('empty: absent or cleared keys decode to an empty value that encodes '
      "every key as ''", () {
    for (final values in [
      <String, String?>{},
      {for (final k in MetaKeys.heldRecordKeys) k: ''},
    ]) {
      final h = HeldRecords.decode(values, knownKinds: kOldKinds);
      expect(h.isEmpty, isTrue);
      expect(h.wasCorrupt, isFalse);
      expect(h.length, 0);
      expect(h.mark, isNull);
      expect(h.encode(), {for (final k in MetaKeys.heldRecordKeys) k: ''});
    }
  });

  test('add stores the unknown records of a chunk; encode → decode gives the '
      'same value', () {
    final h = held();
    final records = unknownIn([
      bookmark('b1'),
      handwriting('p1'),
      rawPurgeRecord('bookmark', 'b0', kHeldV1),
    ]);
    final c = heldChunk('c1', 1793750400000000, scope: 'n7');
    expect(h.add(c, records), 3);
    expect(h.length, 3);
    expect(h.kinds, {'bookmark', 'handwriting'});
    final value = h.encode();
    expect(value.keys, MetaKeys.heldRecordKeys);
    expect(headOf(value), {
      'a': kOldKinds.toList()..sort(),
      'e': 1793750400000000,
      'n': 1,
      'o': null,
      'v': 2,
    });
    final entries = entriesOf(value);
    expect(entries.first, {
      'b': base64Encode(records.first.bytes),
      'by': kAuthor,
      'c': 'c1',
      'fv': '{"b":"$kHeldV0"}',
      'i': 0,
      'id': 'b1',
      'k': 'bookmark',
      'op': 1,
      's': 1793750400000000,
      'sc': 'n7',
    });
    expect(entries.last['fv'], '{"h":"$kHeldV1"}', reason: 'a purge');
    expect(entries.last['op'], 2);
    for (final MapEntry(:key, :value) in value.entries) {
      if (value.isEmpty) continue;
      expect(canonicalJson(jsonDecode(value)), value, reason: key);
    }
    final back = reread(h);
    expect(back.wasCorrupt, isFalse);
    expect(back.encode(), value);
    expect(back.length, 3);
    expect(back.kinds, h.kinds);
  });

  test('records are sorted (serverTime, chunk id, index) whatever the order '
      'of add', () {
    final h = held();
    h.add(heldChunk('c3', 300), unknownIn([bookmark('b5')]));
    h.add(heldChunk('c1', 100), unknownIn([bookmark('b1'), bookmark('b2')]));
    h.add(heldChunk('c2b', 200), unknownIn([bookmark('b4')]));
    h.add(heldChunk('c2a', 200), unknownIn([bookmark('b3')]));
    expect(
      [for (final e in entriesOf(h.encode())) (e['s'], e['c'], e['i'])],
      [
        (100, 'c1', 0),
        (100, 'c1', 1),
        (200, 'c2a', 0),
        (200, 'c2b', 0),
        (300, 'c3', 0),
      ],
    );
    expect(headOf(h.encode())['e'], 100);
  });

  test('dedup by (kind, id, fv): a redelivered chunk, another chunk with the '
      'same record and a doubled record add nothing; another fv is kept', () {
    final h = held();
    expect(h.add(heldChunk('c1', 100), unknownIn([bookmark('b1')])), 1);
    expect(h.add(heldChunk('c1', 100), unknownIn([bookmark('b1')])), 0);
    expect(
      h.add(heldChunk('snap', 900), unknownIn([bookmark('b1')])),
      0,
      reason: 'a compaction snapshot with the same record',
    );
    expect(h.length, 1);
    expect(
      h.add(
        heldChunk('c2', 200),
        unknownIn([bookmark('b1', v: kHeldV1), bookmark('b1', v: kHeldV1)]),
      ),
      1,
    );
    expect(
      h.add(
        heldChunk('c3', 300),
        unknownIn([rawPurgeRecord('bookmark', 'b1', kHeldV0)]),
      ),
      1,
      reason: 'a purge is not the upsert',
    );
    expect(h.length, 3);
    expect([for (final e in entriesOf(h.encode())) e['c']], ['c1', 'c2', 'c3']);
  });

  group('parts', () {
    late int e;
    setUp(() {
      final one = held()
        ..add(heldChunk('c1', 101), unknownIn([bookmark('b1')]));
      e = entryLengthOf(one);
    });
    HeldRecords five(int maxPartBytes) {
      final h = held(maxPartBytes: maxPartBytes);
      for (var i = 1; i <= 5; i++) {
        expect(
          h.add(heldChunk('c$i', 100 + i), unknownIn([bookmark('b$i')])),
          1,
        );
      }
      return h;
    }

    test('next-fit: two entries fill a part exactly; the next entry starts '
        "the next part; unused parts are ''", () {
      final h = five(HeldRecords.emptyPartBytes + 2 * e + 1);
      final value = h.encode();
      expect(partSizes(value), [2, 2, 1]);
      expect(headOf(value)['n'], 3);
      expect(
        utf8.encode(value[MetaKeys.heldRecordParts[0]]!).length,
        HeldRecords.emptyPartBytes + 2 * e + 1,
      );
      for (final k in MetaKeys.heldRecordParts.skip(3)) {
        expect(value[k], '', reason: k);
      }
      for (final (i, k) in MetaKeys.heldRecordParts.take(3).indexed) {
        expect((jsonDecode(value[k]!) as Map)['p'], i + 1);
      }
      expect(
        [for (final x in entriesOf(value)) x['id']],
        ['b1', 'b2', 'b3', 'b4', 'b5'],
      );
      expect(reread(h, maxPartBytes: h.maxPartBytes).encode(), value);
    });

    test('one byte less: an entry is never split, one per part', () {
      final value = five(HeldRecords.emptyPartBytes + 2 * e).encode();
      expect(partSizes(value), [1, 1, 1, 1, 1]);
      expect(headOf(value)['n'], 5);
    });

    test(
      'a record larger than a part is never stored: its chunk is marked',
      () {
        final h = held(maxPartBytes: HeldRecords.emptyPartBytes + e - 1);
        expect(h.add(heldChunk('c1', 100), unknownIn([bookmark('b1')])), 1);
        expect(h.length, 0);
        expect(h.mark?.from, const ServerCursor(100));
        expect(h.mark?.kinds, {'bookmark'});
        expect(h.mark?.writtenBy, kOldKinds);
      },
    );

    test('nine parts at most: the tenth part-full chunk is marked', () {
      final h = held(maxPartBytes: HeldRecords.emptyPartBytes + e);
      for (var i = 1; i <= 9; i++) {
        h.add(heldChunk('c$i', 100 + i), unknownIn([bookmark('b$i')]));
      }
      expect(h.length, 9);
      expect(h.mark, isNull);
      h.add(heldChunk('d1', 200), unknownIn([bookmark('d1')]));
      expect(h.length, 9);
      expect(h.mark?.from, const ServerCursor(200));
      expect(headOf(h.encode())['n'], 9);
    });
  });

  group('chunk-level all or nothing (contract 7.2.8 ②)', () {
    // Bookmarks of about 900 B: an entry is longer than the 400 B left for the mark.
    Uint8List bookmark(String id) => _bookmark(id, pad: 600);
    late int e;
    late int total1;
    setUp(() {
      final one = held()
        ..add(heldChunk('c1', 101), unknownIn([bookmark('b1')]));
      e = entryLengthOf(one);
      total1 = [for (final t in one.encode().values) utf8.encode(t).length]
          .reduce((a, b) => a + b);
    });

    test('the total cap reached in the middle of a chunk: none of its records '
        'is stored and the mark takes its time and kinds', () {
      // Room for two entries in all: the first chunk, then one of the next three.
      final h = held(maxTotalBytes: total1 + e + 1 + 400);
      expect(h.add(heldChunk('c1', 101), unknownIn([bookmark('b1')])), 1);
      final next = unknownIn([
        bookmark('b2'),
        handwriting('p2'),
        bookmark('b3'),
      ]);
      expect(h.add(heldChunk('c2', 202), next), 3, reason: 'new = marked');
      expect(h.length, 1);
      expect([for (final x in entriesOf(h.encode())) x['c']], ['c1']);
      expect(h.mark?.from, const ServerCursor(202));
      expect(h.mark?.kinds, {'bookmark', 'handwriting'});
      expect(h.kinds, {'bookmark', 'handwriting'});
      // A smaller chunk still fits.
      expect(h.add(heldChunk('c0', 50), unknownIn([bookmark('b0')])), 1);
      expect(h.length, 2);
      expect(h.mark?.from, const ServerCursor(202));
    });

    test('records already stored under the chunk id leave too; the mark '
        'takes the earlier time', () {
      final h = held(maxTotalBytes: total1 + 2 * (e + 1) + 400);
      h.add(heldChunk('c1', 101), unknownIn([bookmark('b1')]));
      expect(h.add(heldChunk('c3', 303), unknownIn([bookmark('b3')])), 1);
      expect(h.length, 2);
      h.add(heldChunk('c4', 404), unknownIn([bookmark('b4'), bookmark('b5')]));
      expect(h.mark?.from, const ServerCursor(404));
      // c3 again, now with more records than fit (as an older decoder would have split
      // it): c3's stored record leaves as well.
      expect(
        h.add(
          heldChunk('c3', 303),
          unknownIn([
            bookmark('b3'),
            bookmark('b6'),
            bookmark('b7'),
            handwriting('p6'),
          ]),
        ),
        3,
      );
      expect([for (final x in entriesOf(h.encode())) x['c']], ['c1']);
      expect(h.mark?.from, const ServerCursor(303));
      expect(h.mark?.kinds, {'bookmark', 'handwriting'});
      final back = reread(h, maxTotalBytes: h.maxTotalBytes);
      expect(back.mark?.from, const ServerCursor(303));
      expect(back.mark?.writtenBy, kOldKinds);
      expect(back.length, 1);
    });

    test('a chunk the mark covers is not stored (time ≥ from, kinds ⊆ mark '
        'kinds); an earlier chunk or another kind is', () {
      final h = held(maxTotalBytes: total1 + 3 * (e + 1) + 400);
      h.add(
        heldChunk('big', 200),
        unknownIn([for (var i = 0; i < 9; i++) bookmark('x$i')]),
      );
      expect(h.mark?.from, const ServerCursor(200));
      expect(h.add(heldChunk('later', 250), unknownIn([bookmark('b1')])), 0);
      expect(h.add(heldChunk('same', 200), unknownIn([bookmark('b2')])), 0);
      expect(h.length, 0);
      expect(h.add(heldChunk('earlier', 150), unknownIn([bookmark('b3')])), 1);
      expect(
        h.add(heldChunk('other', 300), unknownIn([handwriting('p1')])),
        1,
        reason: 'handwriting is not in the mark',
      );
      expect(
        h.add(
          heldChunk('mixed', 300),
          unknownIn([handwriting('p2'), bookmark('b4')]),
        ),
        2,
      );
      expect(h.length, 4);
    });

    test("an all-kinds mark ('*') covers every kind from its time", () {
      final h = HeldRecords.decode({
        MetaKeys.heldRecords: '{"v":2',
      }, knownKinds: kOldKinds);
      expect(h.mark?.kinds, {'*'});
      expect(h.mark?.from, ServerCursor.zero);
      expect(h.add(heldChunk('c1', 5), unknownIn([handwriting('p1')])), 0);
      expect(h.length, 0);
    });
  });

  group('re-apply', () {
    // Held by the old app: c2 (t 200) [bookmark purge @0, handwriting p2 @1, bookmark @2]
    // and c1 (t 100) [handwriting p1 @0, two note purges (applied), handwriting p3 @3].
    late HeldRecords h;
    late List<UnknownKindRecord> c1, c2;
    setUp(() {
      h = held();
      c2 = unknownIn([
        rawPurgeRecord('bookmark', 'b0', kHeldV0),
        handwriting('p2'),
        bookmark('b2'),
      ]);
      c1 = unknownIn([
        handwriting('p1'),
        rawPurgeRecord('note', 'n8', kHeldV0),
        rawPurgeRecord('note', 'n9', kHeldV0),
        handwriting('p3', v: kHeldV1),
      ]);
      expect([for (final u in c1) u.index], [0, 3]);
      h.add(heldChunk('c2', 200, scope: 'n2', author: 'bbbbbbbbbbbbbbbb'), c2);
      h.add(heldChunk('c1', 100), c1);
    });

    test('knownChunks after the update: synthetic chunks of the records known '
        'now, (serverTime, chunk id) order, original id, scope, time and '
        'author; the records stay stored', () {
      final updated = reread(h, known: kAllKinds);
      expect(updated.length, 5);
      final chunks = updated.knownChunks(kAllKinds.contains);
      expect([for (final c in chunks) c.chunk.id], ['c1', 'c2']);
      expect(chunks[0].indexes, [0, 3]);
      expect(chunks[1].indexes, [1]);
      final first = chunks[0].chunk;
      expect(first.scope, 'n1');
      expect(first.serverTime, const ServerCursor(100));
      expect(first.authorNodeId, kAuthor);
      expect(first.recordCount, 2);
      expect(first.format, ChunkCodec.formatVersion);
      expect(first.kind, ChunkKind.delta);
      expect(first.maxHlc, kHeldV1);
      expect(first.payload, ChunkCodec.assemble([c1[0].bytes, c1[1].bytes]));
      final decoded = ChunkCodec.decodeTolerant(first.payload);
      expect(decoded.hasUnknown, isFalse);
      expect([for (final r in decoded.records) r.ref.id], ['hw_p1', 'hw_p3']);
      expect(chunks[1].chunk.scope, 'n2');
      expect(chunks[1].chunk.authorNodeId, 'bbbbbbbbbbbbbbbb');
      expect(chunks[1].chunk.serverTime, const ServerCursor(200));
      expect(updated.length, 5, reason: 'until settle');
      expect(h.knownChunks(kOldKinds.contains), isEmpty);
    });

    test('settle: applied records leave, K1 ones stay with ra; dueChunks by '
        'ra; ra survives encode → decode', () {
      final updated = reread(h, known: kAllKinds);
      updated.settle(
        applied: const [('c1', 0), ('c2', 1)],
        heldUntil: const {('c1', 3): 5000},
      );
      expect(updated.length, 3);
      expect(updated.knownChunks(kAllKinds.contains), isEmpty);
      expect(updated.dueChunks(4999), isEmpty);
      final due = updated.dueChunks(5000);
      expect([for (final c in due) c.chunk.id], ['c1']);
      expect(due.single.indexes, [3]);
      final raEntry = entriesOf(updated.encode())
          .firstWhere((x) => x['c'] == 'c1');
      expect(raEntry['ra'], 5000);
      final back = reread(updated);
      expect(back.dueChunks(6000).single.indexes, [3]);
      expect(back.knownChunks(kAllKinds.contains), isEmpty);
      back.settle(applied: const [('c1', 3)], heldUntil: const {});
      expect(back.length, 2);
      expect(back.kinds, {'bookmark'});
      expect(back.dueChunks(1 << 50), isEmpty);
    });

    test('a release time that no longer fits the caps moves its chunk to the '
        'mark; the kind is known, so the next load rewinds to it', () {
      final old = held()
        ..add(heldChunk('c1', 100), unknownIn([handwriting('p1')]))
        ..add(heldChunk('c2', 200), unknownIn([handwriting('p2')]));
      final value = HeldRecords.decode(
        old.encode(),
        knownKinds: kAllKinds,
      ).encode();
      final exact = [for (final t in value.values) utf8.encode(t).length]
          .reduce((a, b) => a + b);
      final updated = HeldRecords.decode(
        value,
        knownKinds: kAllKinds,
        maxTotalBytes: exact,
      );
      expect(updated.wasCorrupt, isFalse);
      expect(updated.length, 2);
      updated.settle(applied: const [], heldUntil: const {('c2', 0): 5000});
      expect(updated.length, 1);
      expect(updated.dueChunks(1 << 50), isEmpty);
      expect(updated.mark?.from, const ServerCursor(200));
      expect(updated.mark?.kinds, {'handwriting'});
      expect(updated.takeMarkIfDue(), const ServerCursor(200));
    });

    test('copy is independent', () {
      final c = h.copy();
      c.settle(applied: const [('c1', 0)], heldUntil: const {});
      expect(c.length, 4);
      expect(h.length, 5);
    });
  });

  group('corrupt value → all-kinds mark', () {
    late Map<String, String> good;
    setUp(() {
      final h = held()
        ..add(heldChunk('c1', 100), unknownIn([bookmark('b1')]))
        ..add(heldChunk('c2', 200), unknownIn([handwriting('p1')]));
      good = h.encode();
    });
    Map<String, String> edit(String key, String Function(String) f) => {
      ...good,
      key: f(good[key]!),
    };
    String editPart(String text, void Function(Map<String, Object?>) f) {
      final json = jsonDecode(text) as Map<String, Object?>;
      f(json);
      return canonicalJson(json);
    }

    final headBroken = <String, Map<String, String?> Function()>{
      'head is not JSON': () =>
          edit(MetaKeys.heldRecords, (t) => t.substring(1)),
      'head is a list': () => edit(MetaKeys.heldRecords, (_) => '[2]'),
      'head v 3': () =>
          edit(MetaKeys.heldRecords, (t) => editPart(t, (j) => j['v'] = 3)),
      'head n 10': () =>
          edit(MetaKeys.heldRecords, (t) => editPart(t, (j) => j['n'] = 10)),
      'head absent, part 1 present': () => {...good, MetaKeys.heldRecords: ''},
    };
    final partBroken = <String, Map<String, String?> Function()>{
      'part 1 is not JSON': () =>
          edit(MetaKeys.heldRecordParts[0], (t) => '$t}'),
      'n 1 but part 2 present': () => {
        ...good,
        MetaKeys.heldRecordParts[1]: good[MetaKeys.heldRecordParts[0]]!
            .replaceFirst('"p":1', '"p":2'),
      },
      'n 2 but part 2 missing': () =>
          edit(MetaKeys.heldRecords, (t) => editPart(t, (j) => j['n'] = 2)),
      'wrong p': () => edit(
        MetaKeys.heldRecordParts[0],
        (t) => t.replaceFirst('"p":1', '"p":3'),
      ),
      'part v 1': () => edit(
        MetaKeys.heldRecordParts[0],
        (t) => editPart(t, (j) => j['v'] = 1),
      ),
      'bad base64': () => edit(
        MetaKeys.heldRecordParts[0],
        (t) => t.replaceFirst('"b":"', '"b":"*'),
      ),
      'entry op 3': () => edit(
        MetaKeys.heldRecordParts[0],
        (t) => t.replaceFirst('"op":1', '"op":3'),
      ),
      'entry without s': () => edit(
        MetaKeys.heldRecordParts[0],
        (t) => t.replaceFirst(RegExp(r',"s":\d+'), ''),
      ),
    };

    void expectAllKindsMark(
      Map<String, String?> values, {
      required int from,
      required Set<String>? writtenBy,
    }) {
      final h = HeldRecords.decode(values, knownKinds: kOldKinds);
      expect(h.wasCorrupt, isTrue);
      expect(h.length, 0);
      expect(h.mark?.kinds, {'*'});
      expect(h.mark?.from, ServerCursor(from));
      expect(h.mark?.writtenBy, writtenBy);
      expect(h.kinds, {'*'});
      final converted = h.encode();
      expect(headOf(converted)['n'], 0);
      expect(headOf(converted)['e'], isNull);
      expect(headOf(converted)['o'], {
        'a': writtenBy == null ? null : (writtenBy.toList()..sort()),
        'f': from,
        'k': ['*'],
      });
      for (final k in MetaKeys.heldRecordParts) {
        expect(converted[k], '', reason: k);
      }
      final again = HeldRecords.decode(converted, knownKinds: kOldKinds);
      expect(again.wasCorrupt, isFalse);
      expect(again.mark?.kinds, {'*'});
      expect(again.encode(), converted);
    }

    for (final MapEntry(:key, :value) in headBroken.entries) {
      test('$key → f 0, a unknown', () {
        expectAllKindsMark(value(), from: 0, writtenBy: null);
      });
    }
    for (final MapEntry(:key, :value) in partBroken.entries) {
      test("$key → f = the head's earliest time, a = the head's kinds", () {
        expectAllKindsMark(value(), from: 100, writtenBy: kOldKinds);
      });
    }

    test(
      'an earlier mark in a readable head is kept as f (min of e and o.f)',
      () {
        final h = held(maxPartBytes: 60)
          ..add(heldChunk('c0', 40), unknownIn([bookmark('big')]));
        expect(h.mark?.from, const ServerCursor(40));
        final withRecord = held()
          ..add(heldChunk('c1', 100), unknownIn([bookmark('b1')]));
        final value = {
          ...withRecord.encode(),
          MetaKeys.heldRecords: canonicalJson({
            ...headOf(withRecord.encode()),
            'o': headOf(h.encode())['o'],
          }),
        };
        expect(
          HeldRecords.decode(value, knownKinds: kOldKinds).wasCorrupt,
          isFalse,
        );
        expectAllKindsMark(
          {...value, MetaKeys.heldRecordParts[0]: 'x'},
          from: 40,
          writtenBy: kOldKinds,
        );
      },
    );

    test('a decoded value that does not fit the caps is corrupt', () {
      final h = HeldRecords.decode(
        good,
        knownKinds: kOldKinds,
        maxPartBytes: 64,
      );
      expect(h.wasCorrupt, isTrue);
      expect(h.mark?.from, const ServerCursor(100));
    });

    test('never throws on any single-character cut of a stored value', () {
      for (final k in MetaKeys.heldRecordKeys.take(2)) {
        final text = good[k]!;
        for (var i = 0; i < text.length; i += 7) {
          final values = {...good, k: text.substring(0, i)};
          expect(
            () => HeldRecords.decode(values, knownKinds: kOldKinds),
            returnsNormally,
          );
        }
      }
    });
  });

  group('takeMarkIfDue', () {
    HeldRecords marked(Set<String> kindsOfRecords, {required Set<String> by}) {
      final h = HeldRecords(knownKinds: by, maxPartBytes: 60);
      h.add(heldChunk('c1', 700), [
        for (final k in kindsOfRecords)
          ...unknownIn([
            rawUpsertRecord(
              k,
              {'id': '${k}1', 'pad': 'x' * 80},
              {'b': kHeldV0},
            ),
          ], known: by),
      ]);
      expect(h.mark?.kinds, kindsOfRecords);
      return h;
    }

    test('a marked kind still unknown: no rewind, the mark stays', () {
      final h = marked({'handwriting'}, by: kOldKinds);
      final same = reread(h);
      expect(same.takeMarkIfDue(), isNull);
      expect(same.mark, isNotNull);
    });

    test(
      'a marked kind known now (app update): from returned, mark cleared',
      () {
        final h = marked({'handwriting', 'bookmark'}, by: kOldKinds);
        final updated = reread(h, known: kAllKinds);
        expect(updated.takeMarkIfDue(), const ServerCursor(700));
        expect(updated.mark, isNull);
        expect(updated.isEmpty, isTrue);
        expect(updated.encode(), {
          for (final k in MetaKeys.heldRecordKeys) k: '',
        });
        expect(updated.takeMarkIfDue(), isNull);
      },
    );

    test('a kind no app knows (bookmark) never rewinds', () {
      final h = marked({'bookmark'}, by: kOldKinds);
      expect(reread(h, known: kAllKinds).takeMarkIfDue(), isNull);
    });

    test("'*': rewinds only for an app knowing a kind the writer did not; "
        'at once when the writer is unknown', () {
      final writer = HeldRecords.decode({
        ...(held()..add(heldChunk('c1', 100), unknownIn([bookmark('b1')])))
            .encode(),
        MetaKeys.heldRecordParts[0]: 'x',
      }, knownKinds: kOldKinds);
      expect(writer.mark?.writtenBy, kOldKinds);
      final converted = writer.encode();
      expect(
        HeldRecords.decode(converted, knownKinds: kOldKinds).takeMarkIfDue(),
        isNull,
      );
      expect(
        HeldRecords.decode(converted, knownKinds: kAllKinds).takeMarkIfDue(),
        const ServerCursor(100),
      );
      final headless = HeldRecords.decode({
        MetaKeys.heldRecords: 'nope',
      }, knownKinds: kOldKinds);
      expect(headless.mark?.writtenBy, isNull);
      expect(
        HeldRecords.decode(
          headless.encode(),
          knownKinds: kOldKinds,
        ).takeMarkIfDue(),
        ServerCursor.zero,
      );
    });
  });

  test('default caps: same-size 10,000 B records — N = maxParts × ⌊(maxPart '
      '− 20 + 1) / (e + 1)⌋ chunks are stored, chunk N + 1 is marked, the '
      'total stays under maxTotalBytes (6.3.2, 6.12)', () {
    // One handwriting record of exactly 10,000 bytes per chunk; ids, times and chunk ids
    // of equal length so every entry has the same length e.
    Uint8List record(int i) {
      final page = 'p${'$i'.padLeft(5, '0')}';
      var pad = 9000;
      for (;;) {
        final r = handwriting(page, pad: 'x' * pad);
        if (r.length == 10000) return r;
        pad += 10000 - r.length;
      }
    }

    RemoteChunk chunk(int i) => heldChunk(
      '$kAuthor-${'$i'.padLeft(24, '0')}',
      1793750400000000 + i * 1000,
    );

    final one = held()..add(chunk(0), unknownIn([record(0)]));
    final e = entryLengthOf(one);
    final perPart =
        (HeldRecords.defaultMaxPartBytes - HeldRecords.emptyPartBytes + 1) ~/
        (e + 1);
    final n = HeldRecords.maxParts * perPart;
    final h = held();
    for (var i = 0; i < n; i++) {
      expect(h.add(chunk(i), unknownIn([record(i)])), 1);
    }
    expect(h.length, n);
    expect(h.mark, isNull);
    expect(h.add(chunk(n), unknownIn([record(n)])), 1);
    expect(h.length, n);
    expect(h.mark?.from, chunk(n).serverTime);
    expect(h.mark?.kinds, {'handwriting'});
    final value = h.encode();
    expect(partSizes(value), List.filled(HeldRecords.maxParts, perPart));
    final total = [for (final t in value.values) utf8.encode(t).length]
        .reduce((a, b) => a + b);
    expect(total, lessThan(HeldRecords.defaultMaxTotalBytes));
    for (final k in MetaKeys.heldRecordParts) {
      expect(
        utf8.encode(value[k]!).length,
        lessThanOrEqualTo(HeldRecords.defaultMaxPartBytes),
      );
    }

    // Measurements (6.12 — printed, no time assertion).
    final w = Stopwatch()..start();
    final text = h.encode();
    final encodeMs = w.elapsedMilliseconds;
    w.reset();
    final back = HeldRecords.decode(text, knownKinds: kOldKinds);
    final decodeMs = w.elapsedMilliseconds;
    expect(back.length, n);
    // ignore: avoid_print
    print(
      'HeldRecords: entry e = $e B, $perPart per part, N = $n, total $total B; '
      'encode $encodeMs ms, decode $decodeMs ms',
    );
  });
}
