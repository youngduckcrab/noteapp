// (v2.17-md, 08-markdown 9 — review finding) The size of an MD 문서 list row is read once
// per (noteId, updatedAt): other library writes do not read the body again; an edit (a
// new updatedAt) does.
import 'package:feature_library/src/state/markdown_preview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

final class _CountingMarkdown implements MarkdownRepository {
  _CountingMarkdown(this.inner);
  final MarkdownRepository inner;
  int gets = 0;

  @override
  Future<MarkdownDoc?> get(NoteId id) {
    gets++;
    return inner.get(id);
  }

  @override
  Stream<MarkdownDoc?> watch(NoteId id) => inner.watch(id);

  @override
  Future<Note> create({
    FolderId? folderId,
    required String title,
    String text = '',
  }) => inner.create(folderId: folderId, title: title, text: text);

  @override
  Future<MarkdownSaveResult> saveText(
    NoteId id,
    String text, {
    required Hlc? baseVersion,
  }) => inner.saveText(id, text, baseVersion: baseVersion);

  @override
  Future<String> preview(
    NoteId id, {
    int maxChars = MarkdownLimits.previewChars,
  }) => inner.preview(id, maxChars: maxChars);
}

void main() {
  test('one body read per (noteId, updatedAt)', () async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final repo = _CountingMarkdown(store.markdown);
    final container = ProviderContainer.test(
      overrides: [
        noteStoreProvider.overrideWithValue(store),
        markdownRepositoryProvider.overrideWithValue(repo),
      ],
    );
    final note = await store.markdown.create(title: 'm', text: '가나다');
    final key = (noteId: note.id, updatedAt: note.updatedAt);
    final sub = container.listen(libraryMarkdownSizeProvider(key), (_, _) {});
    addTearDown(sub.close);
    expect(await container.read(libraryMarkdownSizeProvider(key).future), 9);
    // Other library writes: no new read.
    await store.library.createNote(title: 'ink');
    await store.library.renameNote(note.id, 'm2');
    await Future<void>.delayed(Duration.zero);
    expect(await container.read(libraryMarkdownSizeProvider(key).future), 9);
    expect(repo.gets, 1);
    // An edit gives a new updatedAt → a new key → one more read.
    final doc = (await store.markdown.get(note.id))!;
    repo.gets = 0;
    await store.markdown.saveText(note.id, 'abc', baseVersion: doc.textVersion);
    final edited = (await store.library.getNote(note.id))!;
    expect(
      await container.read(
        libraryMarkdownSizeProvider((
          noteId: note.id,
          updatedAt: edited.updatedAt,
        )).future,
      ),
      3,
    );
    expect(repo.gets, 1);
  });
}
