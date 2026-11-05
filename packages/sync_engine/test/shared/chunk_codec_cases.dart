// Codec v1 cases shared by the VM test (codec/chunk_codec_test.dart) and
// Chrome (web/pure_logic_browser_test.dart): the golden payload (6.4.4) decodes
// to the three golden records and re-encodes to the same bytes on both
// platforms (the golden uses non-integral doubles only).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/sync_engine.dart';

import 'chunk_v1_golden_bytes.dart';

const String kGoldenV0 = '001793750400000-0000-3f2a9c0d11e0b7a4';
const String kGoldenV1 = '001793750460000-0001-3f2a9c0d11e0b7a4';

/// CORE 6.2.4 G1 points.
final Uint8List kGoldenPoints = Uint8List.fromList([
  0x01, 0x01, 0x03, 0xD0, 0x0F, 0x64, 0x96, 0x01, 0xA0, 0x1F, 0x32, 0x00, //
  0xF4, 0x03, 0x32, 0x32, 0x00, 0x54, 0x52,
]);

/// The three records of the golden chunk, in payload order.
List<SyncRecord> goldenRecords() {
  final v0 = Hlc.parse(kGoldenV0), v1 = Hlc.parse(kGoldenV1);
  return [
    UpsertRecord(
      SyncDoc(
        kind: EntityKind.setting,
        id: 'editor.theme',
        json: const {
          'deletedAt': null,
          'key': 'editor.theme',
          'updatedAt': 1793750400000,
          'valueJson': '"dark"',
          'version': kGoldenV0,
        },
      ),
      EntityFieldVersions(v0),
    ),
    UpsertRecord(
      SyncDoc(
        kind: EntityKind.stroke,
        id: 's1',
        json: {
          'createdAt': 1793750400000,
          'deletedAt': null,
          'id': 's1',
          'pageId': 'p1',
          'points': base64Encode(kGoldenPoints),
          'recordingId': null,
          'recordingOffsetMs': null,
          'style': const {
            'color': 4279970411,
            'extras': <String, Object?>{},
            'opacity': 0.9,
            'pressureCurve': [0.25, 0.25, 0.75, 0.75],
            'pressureSensitivity': 0.8,
            'smoothing': 0.55,
            'tool': 'fountain',
            'width': 2.2,
          },
          'updatedAt': 1793750460000,
          'version': kGoldenV1,
        },
      ),
      EntityFieldVersions(v0, {'style': v1}),
    ),
    PurgeRecord(const EntityRef(EntityKind.note, 'n9'), v1),
  ];
}

void chunkCodecCases() {
  final golden = Uint8List.fromList(kChunkV1Golden);

  test('golden constant: 824 bytes, starts 4E 43 01 03 01 E5 01 7B', () {
    expect(golden, hasLength(824));
    expect(golden.sublist(0, 12), [
      0x4E, 0x43, 0x01, 0x03, 0x01, 0xE5, 0x01, 0x7B, 0x22, 0x65, 0x22, 0x3A, //
    ]);
  });

  test('decodes the golden chunk to the golden records', () {
    final records = ChunkCodec.decode(golden);
    expect(records, goldenRecords());
    final stroke = records[1] as UpsertRecord;
    expect(base64Decode(stroke.doc.json['points']! as String), kGoldenPoints);
    expect(stroke.versions.of('style'), Hlc.parse(kGoldenV1));
    expect(stroke.versions.of('pageId'), Hlc.parse(kGoldenV0));
  });

  test('encode(decode(golden)) == golden', () {
    expect(ChunkCodec.encode(ChunkCodec.decode(golden)), golden);
  });

  test('encodes the golden records to the golden bytes', () {
    expect(ChunkCodec.encode(goldenRecords()), golden);
  });

  test('record lengths add up to the payload', () {
    final parts = [for (final r in goldenRecords()) ChunkCodec.encodeRecord(r)];
    expect([for (final p in parts) p.length], [233, 519, 68]);
    expect(
      ChunkCodec.payloadLength(3, parts.fold(0, (s, p) => s + p.length)),
      824,
    );
  });
}
