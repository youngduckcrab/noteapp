// testing_web.dart (2nd-round contract 7.6, C2-39; m5-7/02-core 4.9, 4.11): the browser-only
// entry point's names with their contract types. B2-α (8.1 T22): compile and name references
// only — both helpers are UnimplementedError('CORE T23b: …') until CORE T23b, which replaces
// this test with the open → write → close → reopen → delete scenario.
@TestOn('browser')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/testing_web.dart';
import 'package:test/test.dart';

void main() {
  test('openWebTestNoteStore / deleteWebTestNoteStore (CORE T23b)', () {
    final Future<NoteStore> Function(String) open = openWebTestNoteStore;
    final Future<void> Function(String) delete = deleteWebTestNoteStore;
    final pending = throwsA(
      isA<UnimplementedError>().having(
        (e) => e.message,
        'message',
        startsWith('CORE T23b: '),
      ),
    );
    expect(open('b2_alpha'), pending);
    expect(delete('b2_alpha'), pending);
  });
}
