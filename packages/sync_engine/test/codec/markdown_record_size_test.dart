// (v2.17-md, C217M-04 · 06 — m5-7/08-markdown 4.4, review D4) An MD 문서 body that passes
// MarkdownLimits.check always fits one sync record: the encoded record of the largest
// allowed texts (400,000 bytes of Hangul; control characters up to maxEncodedBytes) stays
// under SyncConfig.chunkHardLimitBytes, and the record's overhead over encodedBytesOf is
// well inside the 100,000 bytes MarkdownLimits leaves for the other keys.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/sync_engine.dart';

UpsertRecord _record(String text) {
  final v = Hlc(1793750400000, 0xffff, 'abcdef0123456789');
  final body = MarkdownText(
    noteId: '0193f1d2-7c40-7000-8000-00000000a001',
    text: text,
    createdAt: 1793750400000,
    version: v,
  );
  return UpsertRecord(SyncDoc.fromEntity(body), EntityFieldVersions(v));
}

void main() {
  final limit = const SyncConfig().chunkHardLimitBytes;

  final cases = <String, String>{
    'Hangul at maxTextBytes': '가' * (MarkdownLimits.maxTextBytes ~/ 3),
    'ASCII at maxTextBytes': 'a' * MarkdownLimits.maxTextBytes,
    'control characters at maxEncodedBytes':
        '\u0001' * ((MarkdownLimits.maxEncodedBytes - 2) ~/ 6),
    'emoji': '😀' * (MarkdownLimits.maxTextBytes ~/ 4),
  };
  for (final MapEntry(key: name, value: text) in cases.entries) {
    test(name, () {
      MarkdownLimits.check(text); // allowed
      final bytes = ChunkCodec.encodeRecord(_record(text)).length;
      expect(bytes, lessThan(limit));
      final overhead = bytes - MarkdownLimits.encodedBytesOf(text);
      expect(
        overhead,
        lessThan(limit - MarkdownLimits.maxEncodedBytes),
        reason: 'overhead $overhead',
      );
    });
  }
}
