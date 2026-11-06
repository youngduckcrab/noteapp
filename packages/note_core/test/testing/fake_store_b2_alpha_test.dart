// The B2-α state of createFakeNoteStore() (m5-7/02-core 8.1 'B2 상태', column 'B2-α 끝'):
// the 2nd-round members wait for CORE T23b, object commands for CORE T23a.
import 'package:note_core/testing.dart';

import '../shared/b2_alpha_store_cases.dart';

void main() {
  defineB2AlphaStoreTests(
    createFakeNoteStore,
    tasks: (
      recordings: 'T23b',
      drafts: 'T23b',
      handwriting: 'T23b',
      search: 'T23b',
      v1Copy: '-',
      objects: null,
    ),
    hasV1CopyApi: false,
  );
}
