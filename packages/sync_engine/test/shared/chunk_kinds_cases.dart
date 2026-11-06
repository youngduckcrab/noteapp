// New-kinds golden cases (07-sync 6.2.3, S2-2) shared by the VM test
// (goldens/chunk_v1_kinds_golden_test.dart) and Chrome (web/pure_logic_browser_test.dart):
// the payload written by test/goldens/make_chunk_kinds_golden.py equals the Dart encoder's
// bytes for the five known records + one raw record of the unknown kind 'bookmark'.
// Non-integral doubles only, so the bytes are the same on both platforms. S2-6 (6.3.1):
// the tolerant decoder reads the same golden — five records + the unknown one, byte exact —
// and an 'old app' (a kind set without handwriting) holds the handwriting record.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/sync_engine.dart';

import '../support/raw_records.dart';
import 'chunk_v1_kinds_golden_bytes.dart';

const int _t0 = 1793750400000;
const String kKindsV0 = '001793750400000-0000-3f2a9c0d11e0b7a4';
const String kKindsV1 = '001793750405000-0001-3f2a9c0d11e0b7a4';

/// The five known records of the golden, in payload order (ChunkPacker.kindOrder
/// inside scope n1): page, recording, pageObject shape, pageObject text, handwriting.
List<UpsertRecord> kindsGoldenRecords() {
  final v0 = Hlc.parse(kKindsV0), v1 = Hlc.parse(kKindsV1);
  UpsertRecord up(
    EntityKind kind,
    Map<String, Object?> json, [
    Map<String, Hlc> o = const {},
  ]) => UpsertRecord(
    SyncDoc(kind: kind, id: json['id']! as String, json: json),
    EntityFieldVersions(v0, o),
  );
  return [
    up(EntityKind.page, const {
      'id': 'p1',
      'noteId': 'n1',
      'sortKey': 'a1',
      'size': [540.5, 960.5],
      'background': {'type': 'blank', 'paperColor': 4294967295},
      'createdAt': _t0,
      'updatedAt': _t0,
      'deletedAt': null,
      'version': kKindsV0,
    }),
    up(
      EntityKind.recording,
      const {
        'id': 'r1',
        'noteId': 'n1',
        'assetId':
            'a54b81412d4c4ab56653bb9e4c02912b0820bb37e2bba00722ddef4d78083d4a',
        'durationMs': 61000,
        'startedAt': _t0 - 61000,
        'title': '1교시 녹음',
        'createdAt': _t0,
        'updatedAt': _t0 + 5000,
        'deletedAt': null,
        'version': kKindsV1,
      },
      {'title': v1},
    ),
    up(EntityKind.pageObject, const {
      'id': 'o-shape',
      'pageId': 'p1',
      'type': 'shape',
      'frame': [100.5, 100.5, 300.5, 220.5, 0.25],
      'shape': 'rectangle',
      'geometry': {
        'closed': true,
        'poly': [100.5, 100.5, 300.5, 100.5, 300.5, 220.5, 100.5, 220.5],
      },
      'style': {
        'strokeColorArgb': 4279900698,
        'strokeWidth': 2.5,
        'strokeOpacity': 0.75,
        'fillColorArgb': null,
        'fillOpacity': 0.5,
        'dash': 'solid',
        'arrowHeads': 'none',
      },
      'createdAt': _t0,
      'updatedAt': _t0,
      'deletedAt': null,
      'version': kKindsV0,
    }),
    up(
      EntityKind.pageObject,
      const {
        'id': 'o-text',
        'pageId': 'p1',
        'type': 'text',
        'frame': [100.5, 300.5, 400.5, 340.5, 0.25],
        'text': '안녕 hello',
        'style': {
          'fontSizePt': 16.5,
          'colorArgb': 4279900698,
          'bold': false,
          'align': 'start',
          'lineHeight': 1.4,
          'backgroundArgb': null,
        },
        'createdAt': _t0,
        'updatedAt': _t0 + 5000,
        'deletedAt': null,
        'version': kKindsV1,
      },
      {'frame': v1, 'text': v1},
    ),
    up(EntityKind.handwriting, const {
      'id': 'hw_p1',
      'noteId': 'n1',
      'pageId': 'p1',
      'engineId': 'mlkit-digital-ink/19.0.0:ko',
      'sourceRev': '0123456789abcdef',
      'lines': [
        {
          'text': '미분 방정식',
          'alternatives': ['미분 방정석', '미분방정식'],
          'languageTag': 'ko',
          'rect': [40.5, 80.5, 320.5, 120.5],
          'strokeIds': ['s1', 's2'],
          'userConfirmed': false,
        },
      ],
      'createdAt': _t0,
      'updatedAt': _t0,
      'deletedAt': null,
      'version': kKindsV0,
    }),
  ];
}

/// The entity of the unknown-kind record ('bookmark', last in the payload).
const Map<String, Object?> kBookmarkEntity = {
  'id': 'b1',
  'noteId': 'n1',
  'pageId': 'p1',
  'label': '1장',
  'y': 120.5,
  'createdAt': _t0,
  'updatedAt': _t0,
  'deletedAt': null,
  'version': kKindsV0,
};

/// The bookmark record bytes (S-13: what a newer app writes).
Uint8List bookmarkRecordBytes() =>
    rawUpsertRecord('bookmark', kBookmarkEntity, const {'b': kKindsV0});

void chunkKindsCases() {
  final golden = Uint8List.fromList(kChunkV1KindsGolden);

  test('new-kinds golden constant: 2,621 bytes, 6 records', () {
    expect(golden, hasLength(2621));
    expect(golden.sublist(0, 4), [0x4E, 0x43, 0x01, 0x06]);
  });

  test('the Dart encoder writes the known records of the golden byte for '
      'byte; the unknown kind is the raw record', () {
    final known = [
      for (final r in kindsGoldenRecords()) ChunkCodec.encodeRecord(r),
    ];
    expect([for (final b in known) b.length], [316, 432, 552, 535, 513]);
    expect(bookmarkRecordBytes(), hasLength(269));
    expect(ChunkCodec.assemble([...known, bookmarkRecordBytes()]), golden);
  });

  test(
    'without the unknown record the chunk round-trips through the codec',
    () {
      final records = kindsGoldenRecords();
      final payload = ChunkCodec.encode(records);
      expect(ChunkCodec.decode(payload), records);
      expect(ChunkCodec.encode(ChunkCodec.decode(payload)), payload);
    },
  );

  test('the strict v1 decoder rejects the golden (unknown kind)', () {
    expect(
      () => ChunkCodec.decode(golden),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'chunk: unknown kind',
        ),
      ),
    );
  });

  test('decodeTolerant reads the golden: the five known records and the '
      'bookmark record byte for byte (S-13)', () {
    final d = ChunkCodec.decodeTolerant(golden);
    expect(d.records, kindsGoldenRecords());
    expect(d.hasUnknown, isTrue);
    final u = d.unknown.single;
    expect(u.kindName, 'bookmark');
    expect(u.op, 0x01);
    expect(u.id, 'b1');
    expect(u.index, 5);
    expect(u.header['e'], kBookmarkEntity);
    expect(u.header['fv'], {'b': kKindsV0});
    expect(u.bytes, bookmarkRecordBytes());
    expect(golden.sublist(golden.length - u.bytes.length), u.bytes);
  });

  test('an old app (no handwriting) holds the handwriting record; the app '
      'update decodes its bytes to the same record', () {
    final old = {
      for (final k in EntityKind.values)
        if (k != EntityKind.handwriting) k.name,
    };
    final d = ChunkCodec.decodeTolerant(golden, isKnownKind: old.contains);
    final records = kindsGoldenRecords();
    expect(d.records, records.sublist(0, 4));
    expect(
      [for (final u in d.unknown) (u.kindName, u.index)],
      [('handwriting', 4), ('bookmark', 5)],
    );
    final hw = d.unknown.first;
    expect(hw.bytes, ChunkCodec.encodeRecord(records[4]));
    final updated = ChunkCodec.decodeTolerant(ChunkCodec.assemble([hw.bytes]));
    expect(updated.records, [records[4]]);
    expect(updated.hasUnknown, isFalse);
  });
}
