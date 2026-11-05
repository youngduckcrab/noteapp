// package:note_core/dev_tools.dart — web-safe, production code may import (EDITOR dev menu)
/// Developer tools of note_core (contract 00-overview 7.6, CORE 4.10).
library;

import 'src/common/ids.dart';
import 'src/dev/synthetic.dart';
import 'src/edit/commands.dart';
import 'src/edit/page_draft.dart';
import 'src/repo/note_store.dart';

/// CORE: synthetic handwriting-like note for iPad performance checks (strokes carry widthQ,
/// 6.2.4). Uses ONLY the NoteStore interface (library.createNote + session AddStrokes), so it
/// works on createFakeNoteStore() from B2 (CORE T5) and on the real store unchanged.
Future<NoteId> seedSyntheticNote(
  NoteStore store, {
  String title = 'perf-test',
  int pages = 50,
  int strokesPerPage = 300,
  int pointsPerStroke = 100,
  int seed = 1,
}) async {
  if (pages < 1 || pages > 2000) {
    throw ArgumentError.value(pages, 'pages', 'must be 1..2000');
  }
  if (strokesPerPage < 0) {
    throw ArgumentError.value(strokesPerPage, 'strokesPerPage', 'must be >= 0');
  }
  final note = await store.library.createNote(
    title: title,
    pages: List.filled(pages, PageDraft.blankA4),
  );
  final session = await store.openSession(note.id);
  try {
    final base = store.clock.now().millisecondsSinceEpoch;
    for (var p = 0; p < session.pages.length; p++) {
      final page = session.pages[p];
      if (strokesPerPage == 0) continue;
      await session.openPage(page.id);
      try {
        session.execute(
          AddStrokes(
            pageId: page.id,
            strokes: [
              for (var i = 0; i < strokesPerPage; i++)
                syntheticStroke(
                  pageId: page.id,
                  ids: store.ids,
                  // One reproducible seed per (seed, page, stroke).
                  seed: seed * 1000003 + p * 10007 + i,
                  pointCount: pointsPerStroke,
                  createdAt: base + i,
                ),
            ],
          ),
        );
      } finally {
        session.closePage(page.id);
      }
    }
    // Seeding is not a user edit: nothing to undo.
    session.clearHistory();
    await session.flush();
  } finally {
    await session.close();
  }
  return note.id;
}
