// The indexer under fake_async (m5-7/05-library 9.2 — fakeAsync +
// createFakeNoteStore() + FakeHandwritingRecognizer + foreground:
// ValueNotifier): one RecordingNoteStore, one note, helpers that drive the
// fake store synchronously and a log of every published status.
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/settings/recognition_settings_keys.dart';
import 'package:ink_recognition/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import 'recording_store.dart';

/// 2026-11-06 10:00 UTC — the fake store's clock (fake_async time).
final DateTime kHarnessStart = DateTime.utc(2026, 11, 6, 10);

final class IndexerHarness {
  IndexerHarness(
    this.async, {
    FakeHandwritingRecognizer? recognizer,
    bool enabled = true,
    bool foreground = true,
    int pages = 1,
    String? language,
    bool start = true,
  }) : recognizer = recognizer ?? FakeHandwritingRecognizer(),
       enabled = ValueNotifier<bool>(enabled),
       foreground = ValueNotifier<bool>(foreground) {
    store = RecordingNoteStore(
      core_testing.createFakeNoteStore(clock: async.getClock(kHarnessStart)),
    );
    if (language != null) {
      wait(store.settings.set(RecognitionSettingsKeys.language, language));
    }
    note = wait(
      store.library.createNote(
        title: 'note',
        pages: List.filled(pages, core.PageDraft.blankA4),
      ),
    );
    pageIds = [for (final p in wait(store.content.pagesOf(note.id))) p.id];
    indexer = HandwritingIndexer(
      store: store,
      recognizer: this.recognizer,
      enabled: this.enabled,
      foreground: this.foreground,
    );
    indexer.status.addListener(() => statuses.add(indexer.status.value));
    store.calls.clear();
    if (start) {
      indexer.start();
      settle();
    }
  }

  final FakeAsync async;
  final FakeHandwritingRecognizer recognizer;
  final ValueNotifier<bool> enabled;
  final ValueNotifier<bool> foreground;
  late final RecordingNoteStore store;
  late final core.Note note;
  late final List<core.PageId> pageIds;
  late final HandwritingIndexer indexer;

  /// Every value the indexer published, in order.
  final List<HandwritingIndexerStatus> statuses = [];

  core.PageId get pageId => pageIds.first;
  HandwritingIndexerStatus get status => indexer.status.value;
  HandwritingIndexerPhase get phase => status.phase;

  /// Runs microtasks (and zero-time timers) until [future] completes.
  T wait<T>(Future<T> future) {
    var done = false;
    late T value;
    Object? error;
    StackTrace? stack;
    future.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e, StackTrace s) {
        error = e;
        stack = s;
        done = true;
      },
    );
    for (var i = 0; i < 100 && !done; i++) {
      async
        ..flushMicrotasks()
        ..elapse(Duration.zero);
    }
    if (!done) throw StateError('the future did not complete');
    if (error case final e?) Error.throwWithStackTrace(e, stack!);
    return value;
  }

  /// Microtasks and zero-time timers (yields) — no time passes.
  void settle() => async
    ..flushMicrotasks()
    ..elapse(Duration.zero);

  void elapse(Duration d) => async.elapse(d);
  void elapseMs(int ms) => async.elapse(Duration(milliseconds: ms));

  /// [command] in a session of the note (opened, committed, closed).
  void execute(
    core.EditCommand command, {
    core.PageId? pageId,
    core.NoteId? noteId,
  }) {
    final session = wait(store.openSession(noteId ?? note.id));
    wait(session.openPage(pageId ?? this.pageId));
    wait(session.execute(command).persisted);
    wait(session.close());
    settle();
  }

  void addStrokes(
    List<core.Stroke> strokes, {
    core.PageId? pageId,
    core.NoteId? noteId,
  }) {
    final page = pageId ?? this.pageId;
    execute(
      core.AddStrokes(pageId: page, strokes: strokes),
      pageId: page,
      noteId: noteId,
    );
  }

  /// Another note with [pages] blank pages: (note, its page ids).
  (core.Note, List<core.PageId>) newNote(String title, {int pages = 1}) {
    final n = wait(
      store.library.createNote(
        title: title,
        pages: List.filled(pages, core.PageDraft.blankA4),
      ),
    );
    return (n, [for (final p in wait(store.content.pagesOf(n.id))) p.id]);
  }

  void removeStrokes(List<core.ElementId> ids, {core.PageId? pageId}) {
    final page = pageId ?? this.pageId;
    execute(
      core.RemoveStrokes(pageId: page, strokeIds: ids),
      pageId: page,
    );
  }

  /// A page change that leaves the strokes alone (queues the page).
  void touchPage({core.PageId? pageId, int paper = 0xFFFFF8E1}) {
    final page = pageId ?? this.pageId;
    execute(
      core.SetPageBackground(
        pageIds: [page],
        background: core.BlankBackground(paperColorArgb: paper),
      ),
      pageId: page,
    );
  }

  /// [lineCount] synthetic lines (seed [seed]) for [pageId].
  List<core.Stroke> lines({
    core.PageId? pageId,
    int lineCount = 3,
    int seed = 1,
  }) => SyntheticHandwriting.lines(
    pageId: pageId ?? this.pageId,
    lineCount: lineCount,
    seed: seed,
  );

  core.PageContent page({core.PageId? pageId}) =>
      wait(store.inner.content.loadPage(pageId ?? this.pageId));

  /// sourceRevOf the page's input strokes now.
  String revOf({core.PageId? pageId}) => core.HandwritingText.sourceRevOf(
    page(pageId: pageId).strokes.where(core.HandwritingText.isRecognitionInput),
  );

  core.HandwritingText? stored({core.PageId? pageId}) =>
      wait(store.inner.handwriting.forPage(pageId ?? this.pageId));

  /// A value written by someone else (conversion sheet, another device).
  void put(core.HandwritingText value) {
    wait(store.inner.handwriting.put(value));
    settle();
  }

  void setLanguage(String tag) {
    wait(store.settings.set(RecognitionSettingsKeys.language, tag));
    settle();
  }

  void dispose() {
    wait(indexer.dispose());
    wait(store.close());
    enabled.dispose();
    foreground.dispose();
  }
}
