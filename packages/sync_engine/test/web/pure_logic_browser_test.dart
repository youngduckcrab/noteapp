// Pure logic once more in Chrome (07-sync 9.1.3): web ints are doubles and
// jsonEncode writes integral doubles without '.0', so codec bytes, varuint and
// cursors are checked on the browser too. Bodies live in test/shared/ and also
// run on the VM. T3: codec, varuint, ServerCursor; T4: merge properties
// (seeds 1..3; 2nd round S2-1: with pageObject, handwriting and recording);
// S2-2: the new-kinds golden; S2-6: tolerant decoding of that golden and the
// HeldRecords value (sync.heldRecords keys).
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import '../shared/chunk_codec_cases.dart';
import '../shared/chunk_kinds_cases.dart';
import '../shared/held_records_cases.dart';
import '../shared/merge_properties_cases.dart';
import '../shared/server_cursor_cases.dart';
import '../shared/varuint_cases.dart';

void main() {
  group('codec v1 golden', chunkCodecCases);
  group('codec v1 new-kinds golden', chunkKindsCases);
  group('HeldRecords', heldRecordsCases);
  group('varuint', varuintCases);
  group('ServerCursor', serverCursorCases);
  group(
    'FieldMerge properties',
    () => mergePropertiesCases(seeds: const [1, 2, 3]),
  );
}
