import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/common/varuint.dart';
import 'package:sync_engine/sync_engine.dart';

import '../shared/chunk_codec_cases.dart';
import '../support/entity_fixtures.dart';
import '../support/raw_records.dart';

/// Raw record bytes: op, varuint header length, header, then [tail].
List<int> rawRecord(int op, String header, [List<int> tail = const []]) {
  final h = utf8.encode(header);
  return [op, ...VarUint.encode(h.length), ...h, ...tail];
}

/// Raw payload: magic, [version], varuint [count], records.
Uint8List rawPayload(
  List<List<int>> records, {
  int? count,
  int version = 1,
  List<int> magic = const [0x4E, 0x43],
}) => Uint8List.fromList([
  ...magic,
  version,
  ...VarUint.encode(count ?? records.length),
  for (final r in records) ...r,
]);

const String v0 = '001793750400000-0000-3f2a9c0d11e0b7a4';

String upsertHeader({
  Object? e = const {'key': 'a.b', 'valueJson': '1', 'version': v0},
  Object? fv = const {'b': v0},
  Object? id = 'a.b',
  Object? k = 'setting',
}) => jsonEncode({'e': ?e, 'fv': ?fv, 'id': ?id, 'k': ?k});

void main() {
  group('golden', chunkCodecCases);

  group('round trip', () {
    test('every CORE kind, with field versions', () {
      final records = <SyncRecord>[
        for (final kind in EntityKind.values)
          UpsertRecord(
            SyncDoc.fromEntity(fixtureEntity(kind)),
            EntityFieldVersions(Hlc.parse(hlcText(kT0)), {
              'deletedAt': Hlc.parse(hlcText(kT0 + 5, counter: 2)),
            }),
          ),
        PurgeRecord(
          const EntityRef(EntityKind.folder, 'f9'),
          Hlc.parse(hlcText(kT0 + 9)),
        ),
      ];
      final bytes = ChunkCodec.encode(records);
      final back = ChunkCodec.decode(bytes);
      expect(back, records);
      for (final r in back.whereType<UpsertRecord>()) {
        expect(r.toRemoteChange().entity, fixtureEntity(r.doc.kind));
      }
    });

    test('stroke points travel as raw bytes, not base64 text', () {
      final stroke = UpsertRecord(
        SyncDoc.fromEntity(fixtureEntity(EntityKind.stroke)),
        EntityFieldVersions(Hlc.parse(hlcText(kT0))),
      );
      final bytes = ChunkCodec.encode([stroke]);
      final text = latin1.decode(bytes);
      expect(text.contains(kG1PointsBase64), isFalse);
      expect(text.contains('"points"'), isFalse);
      expect(
        text.contains(latin1.decode(base64Decode(kG1PointsBase64))),
        isTrue,
      );
      final back = ChunkCodec.decode(bytes).single as UpsertRecord;
      expect(back.doc.json['points'], kG1PointsBase64);
    });

    test('2000 records', () {
      final records = [
        for (var i = 0; i < 2000; i++)
          PurgeRecord(
            EntityRef(EntityKind.note, 'n$i'),
            Hlc.parse(hlcText(kT0 + i)),
          ),
      ];
      expect(ChunkCodec.decode(ChunkCodec.encode(records)), records);
    });

    test('maxHlcOf is the newest record version', () {
      final records = goldenRecords();
      expect(ChunkCodec.maxHlcOf(records), Hlc.parse(kGoldenV1));
      expect(() => ChunkCodec.maxHlcOf(const []), throwsArgumentError);
    });
  });

  group('encode rejects', () {
    test('an empty or oversized record list', () {
      expect(() => ChunkCodec.encode(const []), throwsArgumentError);
      final p = PurgeRecord(
        const EntityRef(EntityKind.note, 'n'),
        Hlc.parse(v0),
      );
      expect(
        () => ChunkCodec.encode(List.filled(5001, p)),
        throwsArgumentError,
      );
    });

    test('a purge of a kind other than folder / note', () {
      expect(
        () => ChunkCodec.encodeRecord(
          PurgeRecord(const EntityRef(EntityKind.page, 'p'), Hlc.parse(v0)),
        ),
        throwsArgumentError,
      );
    });
  });

  group('decode errors are FormatException', () {
    final good = rawRecord(0x01, upsertHeader(), [0]);
    final cases = v1DecodeErrorCases();
    test('27 cases (1st round)', () => expect(cases, hasLength(27)));
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () {
        expect(() => ChunkCodec.decode(value), throwsFormatException);
      });
    }

    test('the well-formed base case decodes', () {
      final r = ChunkCodec.decode(rawPayload([good])).single as UpsertRecord;
      expect(r.doc.kind, EntityKind.setting);
      expect(r.doc.id, 'a.b');
    });
  });

  group('decodeTolerant (S-13, 6.3.1)', decodeTolerantCases);
}

/// The 27 malformed payloads of the 1st round (6.4.4): decode throws FormatException for
/// each; decodeTolerant too, except 'unknown kind' (S-13).
Map<String, Uint8List> v1DecodeErrorCases() {
  final good = rawRecord(0x01, upsertHeader(), [0]);
  return <String, Uint8List>{
    'too short': Uint8List.fromList([0x4E, 0x43, 0x01]),
    'magic': rawPayload([good], magic: const [0x4E, 0x58]),
    'format version 2': rawPayload([good], version: 2),
    'record count 0': rawPayload(const [], count: 0),
    'record count 5001': rawPayload([good], count: 5001),
    'fewer records than counted': rawPayload([good], count: 2),
    'unknown op': rawPayload([
      rawRecord(0x03, upsertHeader(), [0]),
    ]),
    'header length 0': rawPayload([
      [0x01, 0x00, 0x00],
    ]),
    'header length over 1,000,000': rawPayload([
      [0x01, ...VarUint.encode(1000001)],
    ]),
    'header past the end': rawPayload([
      [0x01, 0x20, 0x7B],
    ]),
    'trailing bytes': Uint8List.fromList([
      ...rawPayload([good]),
      0x00,
    ]),
    'header not JSON': rawPayload([
      rawRecord(0x01, '{"e":', [0]),
    ]),
    'header not an object': rawPayload([
      rawRecord(0x01, '[1,2]', [0]),
    ]),
    'header not UTF-8': rawPayload([
      [0x01, 0x02, 0xC3, 0x28, 0x00],
    ]),
    'upsert without e': rawPayload([
      rawRecord(0x01, upsertHeader(e: null), [0]),
    ]),
    'upsert without fv': rawPayload([
      rawRecord(0x01, upsertHeader(fv: null), [0]),
    ]),
    'upsert without id': rawPayload([
      rawRecord(0x01, upsertHeader(id: null), [0]),
    ]),
    'upsert without k': rawPayload([
      rawRecord(0x01, upsertHeader(k: null), [0]),
    ]),
    'unknown kind': rawPayload([
      rawRecord(0x01, upsertHeader(k: 'widget'), [0]),
    ]),
    'setting e.key != id': rawPayload([
      rawRecord(0x01, upsertHeader(id: 'other'), [0]),
    ]),
    'e.id != id': rawPayload([
      rawRecord(0x01, upsertHeader(e: const {'id': 'x'}, id: 'y', k: 'note'), [
        0,
      ]),
    ]),
    'bad field versions': rawPayload([
      rawRecord(0x01, upsertHeader(fv: const {'b': 'nope'}), [0]),
    ]),
    'blob count 5': rawPayload([
      rawRecord(0x01, upsertHeader(), [5]),
    ]),
    'blob past the end': rawPayload([
      rawRecord(0x01, upsertHeader(), [1, 1, 0x70, 9, 1]),
    ]),
    'missing blob count': rawPayload([rawRecord(0x01, upsertHeader())]),
    'purge of a page': rawPayload([
      rawRecord(0x02, '{"h":"$v0","id":"p","k":"page"}'),
    ]),
    'purge without h': rawPayload([rawRecord(0x02, '{"id":"n","k":"note"}')]),
  };
}

void decodeTolerantCases() {
  final setting = rawRecord(0x01, upsertHeader(), [0]);
  final purgeNote = rawRecord(0x02, '{"h":"$v0","id":"n1","k":"note"}');
  final widgetBlobs = rawUpsertRecord(
    'widget',
    const {'id': 'w1', 'noteId': 'n1'},
    const {'b': v0},
    blobs: {
      'ink': Uint8List.fromList([1, 2, 3]),
      'audio': Uint8List.fromList([9]),
    },
  );
  final widgetPurge = rawPurgeRecord('widget', 'w2', v0);

  test('known upserts and purges are records, as decode gives them', () {
    final payload = rawPayload([setting, purgeNote]);
    final d = ChunkCodec.decodeTolerant(payload);
    expect(d.records, ChunkCodec.decode(payload));
    expect(d.records, hasLength(2));
    expect(d.unknown, isEmpty);
    expect(d.hasUnknown, isFalse);
  });

  test('an upsert of an unknown kind keeps its exact bytes, blobs included; '
      'the records around it decode', () {
    final payload = rawPayload([setting, widgetBlobs, purgeNote]);
    final d = ChunkCodec.decodeTolerant(payload);
    expect(d.records, [
      ...ChunkCodec.decode(rawPayload([setting])),
      ...ChunkCodec.decode(rawPayload([purgeNote])),
    ]);
    final u = d.unknown.single;
    expect(u.kindName, 'widget');
    expect(u.op, 0x01);
    expect(u.id, 'w1');
    expect(u.index, 1);
    expect(u.header, {
      'e': {'id': 'w1', 'noteId': 'n1'},
      'fv': {'b': v0},
      'id': 'w1',
      'k': 'widget',
    });
    expect(u.bytes, widgetBlobs);
    expect(
      u.bytes.length,
      greaterThan(
        rawUpsertRecord(
          'widget',
          const {'id': 'w1', 'noteId': 'n1'},
          const {'b': v0},
        ).length,
      ),
      reason: 'the blob bytes stay in the record',
    );
    expect(() => ChunkCodec.decode(payload), throwsFormatException);
  });

  test('a purge of an unknown kind is an UnknownKindRecord with op 0x02', () {
    final d = ChunkCodec.decodeTolerant(rawPayload([widgetPurge, setting]));
    expect(d.records, hasLength(1));
    final u = d.unknown.single;
    expect((u.kindName, u.op, u.id, u.index), ('widget', 0x02, 'w2', 0));
    expect(u.header, {'h': v0, 'id': 'w2', 'k': 'widget'});
    expect(u.bytes, widgetPurge);
  });

  group('still a FormatException for the whole chunk', () {
    final cases = <String, Uint8List>{
      for (final MapEntry(:key, :value) in v1DecodeErrorCases().entries)
        if (key != 'unknown kind') 'v1: $key': value,
      'purge of a known kind other than folder / note (stroke)': rawPayload([
        rawRecord(0x02, '{"h":"$v0","id":"s","k":"stroke"}'),
      ]),
      'k is not a string': rawPayload([
        rawRecord(0x01, upsertHeader(k: 7), [0]),
      ]),
      'unknown upsert without id': rawPayload([
        rawRecord(0x01, upsertHeader(id: null, k: 'widget'), [0]),
      ]),
      'unknown upsert with a numeric id': rawPayload([
        rawRecord(0x01, upsertHeader(id: 3, k: 'widget'), [0]),
      ]),
      'unknown upsert without e': rawPayload([
        rawRecord(0x01, upsertHeader(e: null, k: 'widget'), [0]),
      ]),
      'unknown upsert with a list e': rawPayload([
        rawRecord(0x01, upsertHeader(e: const [1], k: 'widget'), [0]),
      ]),
      'unknown upsert without fv': rawPayload([
        rawRecord(0x01, upsertHeader(fv: null, k: 'widget'), [0]),
      ]),
      'unknown upsert with 5 blobs': rawPayload([
        rawRecord(0x01, upsertHeader(k: 'widget'), [5]),
      ]),
      'unknown upsert with a blob past the end': rawPayload([
        rawRecord(0x01, upsertHeader(k: 'widget'), [1, 1, 0x70, 9, 1]),
      ]),
      'unknown upsert without a blob count': rawPayload([
        rawRecord(0x01, upsertHeader(k: 'widget')),
      ]),
      'unknown purge without h': rawPayload([
        rawRecord(0x02, '{"id":"w","k":"widget"}'),
      ]),
      'unknown purge without id': rawPayload([
        rawRecord(0x02, '{"h":"$v0","k":"widget"}'),
      ]),
      'unknown record followed by trailing bytes': Uint8List.fromList([
        ...rawPayload([widgetPurge]),
        0x00,
      ]),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () {
        expect(() => ChunkCodec.decodeTolerant(value), throwsFormatException);
        expect(() => ChunkCodec.decode(value), throwsFormatException);
      });
    }
  });

  test('the v1 case "unknown kind" becomes an UnknownKindRecord', () {
    final d = ChunkCodec.decodeTolerant(v1DecodeErrorCases()['unknown kind']!);
    expect(d.records, isEmpty);
    expect((d.unknown.single.kindName, d.unknown.single.id), ('widget', 'a.b'));
  });

  test('a known kind whose entity CORE cannot decode is still a record '
      '(the gate skips it — 1st round)', () {
    final payload = rawPayload([
      rawRecord(
        0x01,
        upsertHeader(
          e: const {'id': 'n1', 'title': 5, 'sortKey': null},
          id: 'n1',
          k: 'note',
        ),
        [0],
      ),
    ]);
    final d = ChunkCodec.decodeTolerant(payload);
    expect(d.records, ChunkCodec.decode(payload));
    final r = d.records.single as UpsertRecord;
    expect((r.doc.kind, r.doc.json['title']), (EntityKind.note, 5));
    expect(d.unknown, isEmpty);
  });

  test('isKnownKind: an EntityKind the app does not know is held; a name it '
      'accepts that is no EntityKind cannot be decoded and is held too', () {
    final note = ChunkCodec.encodeRecord(
      UpsertRecord(
        SyncDoc.fromEntity(fixtureEntity(EntityKind.note)),
        EntityFieldVersions(Hlc.parse(v0)),
      ),
    );
    final payload = rawPayload([note, setting, widgetPurge]);
    final noNote = ChunkCodec.decodeTolerant(
      payload,
      isKnownKind: (k) => k != 'note',
    );
    expect([for (final r in noNote.records) r.ref.kind], [EntityKind.setting]);
    expect(
      [for (final u in noNote.unknown) (u.kindName, u.index)],
      [('note', 0), ('widget', 2)],
    );
    expect(noNote.unknown.first.bytes, note);

    final all = ChunkCodec.decodeTolerant(payload, isKnownKind: (_) => true);
    expect(
      [for (final r in all.records) r.ref.kind],
      [EntityKind.note, EntityKind.setting],
    );
    expect([for (final u in all.unknown) u.kindName], ['widget']);
  });

  test('decodeTolerant on 2,000 known records gives what decode gives '
      '(time printed — 6.12, no time assertion)', () {
    final records = [
      for (var i = 0; i < 2000; i++)
        PurgeRecord(
          EntityRef(EntityKind.note, 'n$i'),
          Hlc.parse(hlcText(kT0 + i)),
        ),
    ];
    final payload = ChunkCodec.encode(records);
    expect(ChunkCodec.decodeTolerant(payload).records, records);
    int micros(void Function() body) {
      final w = Stopwatch()..start();
      for (var r = 0; r < 20; r++) {
        body();
      }
      return w.elapsedMicroseconds ~/ 20;
    }

    for (var warm = 0; warm < 3; warm++) {
      micros(() => ChunkCodec.decode(payload));
      micros(() => ChunkCodec.decodeTolerant(payload));
    }
    final strict = micros(() => ChunkCodec.decode(payload));
    final tolerant = micros(() => ChunkCodec.decodeTolerant(payload));
    // ignore: avoid_print
    print('decode $strict µs, decodeTolerant $tolerant µs (2,000 records)');
  });
}
