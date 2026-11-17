// (v2.17-md, m5-7/08-markdown 12.1, MD-T02 fake half) The fake store passes the shared
// MarkdownRepository contract (test/shared/markdown_contract.dart).
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../shared/markdown_contract.dart';

void main() {
  defineMarkdownContract((clock) => createFakeNoteStore(clock: clock), (
    removeBody: FakeMarkdownHooks.removeBody,
    remoteText: FakeMarkdownHooks.remoteText,
  ));

  test('FakeMarkdownHooks refuse a store that is not the fake', () {
    expect(
      () => FakeMarkdownHooks.removeBody(_NotFake(), 'x'),
      throwsArgumentError,
    );
  });
}

final class _NotFake implements NoteStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
