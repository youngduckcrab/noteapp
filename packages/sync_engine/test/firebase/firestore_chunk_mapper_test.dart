// T17: chunk documents (6.4.2). toFirestore → fromFirestore keeps every field (su = the
// server's Timestamp in µs); a pending su (null) or any malformed field → null.
import 'dart:typed_data';

// cloud_firestore 7.1.0 exports its own `Type` (pipeline expressions).
import 'package:cloud_firestore/cloud_firestore.dart' hide Type;
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/firebase.dart';
import 'package:sync_engine/src/firebase/chunk_fields.dart';
import 'package:sync_engine/sync_engine.dart';

final _write = ChunkWrite(
  id: '0123456789abcdef-00112233445566778899aabb',
  scope: 'note-1',
  authorNodeId: '0123456789abcdef',
  recordCount: 3,
  format: 1,
  kind: ChunkKind.snapshot,
  maxHlc: '00001ae2f2b1c0000-0000-0123456789abcdef',
  payload: Uint8List.fromList([1, 3, 5, 7, 9]),
);

/// The document as the server stores it: su resolved to [at].
Map<String, Object?> _stored(ChunkWrite write, Timestamp at) => {
  ...FirestoreChunkMapper.toFirestore(write),
  ChunkFields.su: at,
};

void main() {
  test(
    'toFirestore: the 6.4.2 fields, data as a Blob, su = serverTimestamp',
    () {
      final doc = FirestoreChunkMapper.toFirestore(_write);
      expect(doc.keys.toSet(), {
        'fmt',
        'scope',
        'by',
        'n',
        'bytes',
        'maxHlc',
        'kind',
        'data',
        'su',
      });
      expect(doc['fmt'], 1);
      expect(doc['scope'], 'note-1');
      expect(doc['by'], '0123456789abcdef');
      expect(doc['n'], 3);
      expect(doc['bytes'], 5);
      expect(doc['maxHlc'], _write.maxHlc);
      expect(doc['kind'], 'snapshot');
      expect((doc['data']! as Blob).bytes, _write.payload);
      expect(doc['su'], FieldValue.serverTimestamp());
      expect(FirestoreChunkMapper.collection, 'changes');
    },
  );

  test('round trip: every field back, su → ServerCursor in µs', () {
    final at = Timestamp(1793500000, 123456789);
    final chunk = FirestoreChunkMapper.fromFirestore(
      _write.id,
      _stored(_write, at),
    )!;
    expect(chunk.id, _write.id);
    expect(chunk.scope, _write.scope);
    expect(chunk.authorNodeId, _write.authorNodeId);
    expect(chunk.recordCount, _write.recordCount);
    expect(chunk.format, _write.format);
    expect(chunk.kind, _write.kind);
    expect(chunk.maxHlc, _write.maxHlc);
    expect(chunk.payload, _write.payload);
    expect(chunk.serverTime, const ServerCursor(1793500000123456));
    for (final kind in ChunkKind.values) {
      final w = ChunkWrite(
        id: 'x',
        scope: 'lib',
        authorNodeId: 'b',
        recordCount: 1,
        format: 1,
        kind: kind,
        maxHlc: 'h',
        payload: Uint8List(1),
      );
      expect(
        FirestoreChunkMapper.fromFirestore('x', _stored(w, at))!.kind,
        kind,
      );
    }
  });

  test('Timestamp ↔ ServerCursor: µs, sub-µs dropped, web-safe', () {
    final at = Timestamp(1793500000, 999);
    expect(ChunkFields.cursorOf(at), const ServerCursor(1793500000000000));
    const c = ServerCursor(1793500000654321);
    final t = ChunkFields.timestampOf(c);
    expect(t.seconds, 1793500000);
    expect(t.nanoseconds, 654321000);
    expect(ChunkFields.cursorOf(t), c);
  });

  test('su still pending (null, or the FieldValue sentinel) → null', () {
    final pending = FirestoreChunkMapper.toFirestore(_write);
    expect(FirestoreChunkMapper.fromFirestore(_write.id, pending), isNull);
    expect(
      FirestoreChunkMapper.fromFirestore(_write.id, {
        ...pending,
        ChunkFields.su: null,
      }),
      isNull,
    );
  });

  test('malformed documents → null', () {
    final good = _stored(_write, Timestamp(1, 0));
    expect(FirestoreChunkMapper.fromFirestore(_write.id, good), isNotNull);
    final broken = <String, Map<String, Object?>>{
      'fmt missing': {...good}..remove('fmt'),
      'fmt text': {...good, 'fmt': '1'},
      'n zero': {...good, 'n': 0},
      'n text': {...good, 'n': '3'},
      'scope empty': {...good, 'scope': ''},
      'scope missing': {...good}..remove('scope'),
      'by missing': {...good}..remove('by'),
      'maxHlc number': {...good, 'maxHlc': 5},
      'kind unknown': {...good, 'kind': 'merge'},
      'data missing': {...good}..remove('data'),
      'data text': {...good, 'data': 'AQMF'},
      'bytes ≠ data length': {...good, 'bytes': 6},
    };
    for (final MapEntry(key: what, value: doc) in broken.entries) {
      expect(
        FirestoreChunkMapper.fromFirestore(_write.id, doc),
        isNull,
        reason: what,
      );
    }
    expect(FirestoreChunkMapper.fromFirestore('', good), isNull);
    // A Uint8List data field (some SDK paths) is accepted.
    expect(
      FirestoreChunkMapper.fromFirestore(_write.id, {
        ...good,
        'data': Uint8List.fromList([1, 3, 5, 7, 9]),
      })!.payload,
      _write.payload,
    );
  });
}
