// Byte golden of codec v1 with the 2nd-round kinds and one record of a kind this app does
// not know (07-sync 6.2.3, S2-2). The file comes from test/goldens/make_chunk_kinds_golden.py
// (run once with python3 -I — not by tests), written separately from the Dart encoder.
// VM only: reads the file with dart:io.
@Tags(['golden'])
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
import 'package:sync_engine/src/codec/chunk_packer.dart';

import '../shared/chunk_kinds_cases.dart';
import '../shared/chunk_v1_kinds_golden_bytes.dart';

void main() {
  late Uint8List file;

  setUpAll(() {
    file = File('test/goldens/chunk_v1_kinds_golden.bin').readAsBytesSync();
  });

  test('file is 2,621 bytes with the golden sha-256', () {
    expect(file, hasLength(2621));
    expect(
      sha256.convert(file).toString(),
      '877eebff84d671bbeab67801666a7af9eb2bec2b289b4f27f7a910d61ab4f11f',
    );
    expect(
      chunkIdOf('3f2a9c0d11e0b7a4', file),
      '3f2a9c0d11e0b7a4-877eebff84d671bbeab67801',
    );
  });

  test('the shared Dart constant equals the file', () {
    expect(kChunkV1KindsGolden, file);
  });

  test('Python bytes = Dart encoder (known records + raw unknown record)', () {
    expect(
      ChunkCodec.assemble([
        for (final r in kindsGoldenRecords()) ChunkCodec.encodeRecord(r),
        bookmarkRecordBytes(),
      ]),
      file,
    );
  });

  test('the known records are in ChunkPacker order and decode with CORE', () {
    final records = kindsGoldenRecords();
    final sorted = [...records]..sort(ChunkPacker.compareRecords);
    expect(sorted, records);
    for (final r in records) {
      final entity = r.doc.toEntity();
      expect(entity.kind, r.doc.kind);
      expect(entity.id, r.doc.id);
      expect(entity.version, r.versions.max, reason: r.doc.id);
    }
    final text = records[3].doc.toEntity() as TextBoxObject;
    expect(text.text, '안녕 hello');
    final recording = records[1].doc.toEntity() as Recording;
    expect(recording.title, '1교시 녹음');
    final hw = records[4].doc.toEntity() as HandwritingText;
    expect(hw.lines.single.alternatives, ['미분 방정석', '미분방정식']);
  });

  group('shared', chunkKindsCases);
}
