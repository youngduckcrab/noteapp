// Byte golden of the change chunk codec v1 (07-sync 6.4.4, 8 T3; contract
// 00-overview 7.4.8 golden rule). VM only: reads the file with dart:io, and
// JSON byte comparison is VM-only by contract 7.4.6.
@Tags(['golden'])
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';

import '../shared/chunk_codec_cases.dart';
import '../shared/chunk_v1_golden_bytes.dart';

void main() {
  late Uint8List file;

  setUpAll(() {
    file = File('test/goldens/chunk_v1_golden.bin').readAsBytesSync();
  });

  test('file is 824 bytes with the golden sha-256', () {
    expect(file, hasLength(824));
    expect(
      sha256.convert(file).toString(),
      '18ff3577c294b8f5360e5dcbd006c3633d3fbaa39f1e73567898236c7e5f324e',
    );
  });

  test('chunk id for node 3f2a9c0d11e0b7a4', () {
    expect(
      chunkIdOf('3f2a9c0d11e0b7a4', file),
      '3f2a9c0d11e0b7a4-18ff3577c294b8f5360e5dcb',
    );
    expect(chunkIdOf('3f2a9c0d11e0b7a4', file), hasLength(41));
  });

  test('the encoder writes the file byte for byte', () {
    expect(ChunkCodec.encode(goldenRecords()), file);
    expect(ChunkCodec.encode(ChunkCodec.decode(file)), file);
  });

  test('the shared Dart constant equals the file', () {
    expect(kChunkV1Golden, file);
  });
}
