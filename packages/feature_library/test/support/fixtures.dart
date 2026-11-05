// test/support/fixtures.dart — 05-library 8 L0. Everything is created through
// the CORE API (FakeLibraryBackend.seed*), so the same fixture works on the
// fake store and on real CORE (L21).
import 'package:note_core/note_core.dart';

import 'fake_library_backend.dart';

/// What [seedSampleLibrary] created (CORE values as returned at creation).
final class SampleLibrary {
  SampleLibrary({
    required this.homeFolders,
    required this.homeNotes,
    required this.nested,
    required this.deepNote,
  });

  /// '수학', '영어', '과학' at home (created in this order).
  final List<Folder> homeFolders;

  /// '회의록', '독서 기록', '아이디어', '일기' at home (created in this order).
  final List<Note> homeNotes;

  /// '미적분' ⊂ '수학', '극한' ⊂ '미적분', '연습 문제' ⊂ '극한' — 3 levels
  /// below a home folder.
  final List<Folder> nested;

  /// '극한 정리' in the deepest folder ('연습 문제').
  final Note deepNote;

  Folder get math => homeFolders[0];
  Folder get english => homeFolders[1];
  Folder get science => homeFolders[2];
  Folder get deepest => nested.last;
}

/// Seeds home with 3 folders and 4 notes, plus 3 levels of sub-folders under
/// '수학' with one note at the bottom. Each item is created one minute after
/// the previous one, starting at [start] (default 2026-11-01 09:00 local);
/// the backend clock is left at [after] (default 2026-11-04 14:05 local, the
/// TestClock default).
Future<SampleLibrary> seedSampleLibrary(
  FakeLibraryBackend backend, {
  DateTime? start,
  DateTime? after,
}) async {
  var at = start ?? DateTime(2026, 11, 1, 9);
  DateTime next() => at = at.add(const Duration(minutes: 1));

  final homeFolders = <Folder>[
    for (final name in const ['수학', '영어', '과학'])
      await backend.seedFolder(name, at: next()),
  ];
  final homeNotes = <Note>[
    for (final title in const ['회의록', '독서 기록', '아이디어', '일기'])
      await backend.seedNote(title, at: next()),
  ];
  final nested = <Folder>[];
  FolderId parent = homeFolders.first.id;
  for (final name in const ['미적분', '극한', '연습 문제']) {
    final folder = await backend.seedFolder(name, parentId: parent, at: next());
    nested.add(folder);
    parent = folder.id;
  }
  final deepNote = await backend.seedNote(
    '극한 정리',
    folderId: parent,
    at: next(),
  );
  backend.clock.current = after ?? DateTime(2026, 11, 4, 14, 5);
  return SampleLibrary(
    homeFolders: homeFolders,
    homeNotes: homeNotes,
    nested: nested,
    deepNote: deepNote,
  );
}
