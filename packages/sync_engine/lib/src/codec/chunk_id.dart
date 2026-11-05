// Internal (not exported). Chunk id (6.4.5): author node + first 24 hex chars of the
// payload's sha-256 (41 chars). Same content → same id (a lost-ack retry rewrites the
// same document).
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

String chunkIdOf(String authorNodeId, Uint8List payload) =>
    '$authorNodeId-${sha256.convert(payload).toString().substring(0, 24)}';
