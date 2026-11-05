import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/common/varuint.dart';
import 'package:sync_engine/sync_engine.dart';

import '../shared/chunk_codec_cases.dart';
import '../support/entity_fixtures.dart';

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
    final cases = <String, Uint8List>{
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
        rawRecord(
          0x01,
          upsertHeader(e: const {'id': 'x'}, id: 'y', k: 'note'),
          [0],
        ),
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
}
