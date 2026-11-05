// Internal (not exported): field names of the chunk documents (6.4.2) and the Timestamp ↔
// ServerCursor conversion of `su` (6.6.2) — microseconds from seconds and nanoseconds
// (web-safe ints, no 64-bit arithmetic). Shared by FirestoreChunkMapper and
// FirebaseSyncBackend (queries on 'scope' and 'su').
// cloud_firestore 7.1.0 exports its own `Type` (pipeline expressions).
import 'package:cloud_firestore/cloud_firestore.dart' hide Type;

import '../common/server_cursor.dart';

abstract final class ChunkFields {
  static const String fmt = 'fmt',
      scope = 'scope',
      by = 'by',
      n = 'n',
      bytes = 'bytes',
      maxHlc = 'maxHlc',
      kind = 'kind',
      data = 'data',
      su = 'su';

  /// Timestamp → ServerCursor (µs).
  static ServerCursor cursorOf(Timestamp t) =>
      ServerCursor(t.seconds * 1000000 + t.nanoseconds ~/ 1000);

  /// ServerCursor → Timestamp (query bounds).
  static Timestamp timestampOf(ServerCursor c) =>
      Timestamp.fromMicrosecondsSinceEpoch(c.micros);
}
