// Pure logic once more in Chrome (07-sync 9.1.3): web ints are doubles and
// jsonEncode writes integral doubles without '.0', so codec bytes, varuint and
// cursors are checked on the browser too. Bodies live in test/shared/ and also
// run on the VM. T3: codec, varuint, ServerCursor (merge properties: T4).
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import '../shared/chunk_codec_cases.dart';
import '../shared/server_cursor_cases.dart';
import '../shared/varuint_cases.dart';

void main() {
  group('codec v1 golden', chunkCodecCases);
  group('varuint', varuintCases);
  group('ServerCursor', serverCursorCases);
}
