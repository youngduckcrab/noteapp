// E-04: PageMount (04-editor 6.4.4). A fake-store session wrapped in
// RecordingNoteSession feeds a real INK controller (ink testing's
// createTestPageController), all under fake_async.
//   - the `load` change → updateContent (content revision = session revision);
//   - a local change and an undo → updateContent once each;
//   - dispose → no subscription left, closePage once (also when it comes
//     while the page is still loading);
//   - no execute from inside a session stream listener (N-2 v1.1).
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:feature_editor/src/document/mounted_pages.dart';
import 'package:feature_editor/src/document/page_mount.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/recording_note_session.dart';
import '../helpers/test_data.dart';

const String _p0 = 'mount-p0';
const String _p1 = 'mount-p1';

final class _Env {
  _Env(this.async);

  final FakeAsync async;
  late final core.NoteStore store;
  late final RecordingNoteSession session;
  final List<ink.InkPageController> _controllers = [];
  final List<PageMount> _mounts = [];

  void open({Map<String, List<core.Stroke>> strokes = const {}}) {
    store = createFakeNoteStore();
    late core.Note note;
    unawaited(
      store.library
          .createNote(
            title: 'mount',
            pages: [
              for (final id in [_p0, _p1])
                core.PageDraft(
                  id: id,
                  size: kA4,
                  background: const core.BlankBackground(),
                ),
            ],
          )
          .then((n) => note = n),
    );
    async.flushMicrotasks();
    late core.NoteSession inner;
    unawaited(store.openSession(note.id).then((s) => inner = s));
    async.flushMicrotasks();
    session = RecordingNoteSession(inner);
    for (final MapEntry(key: pageId, value: list) in strokes.entries) {
      unawaited(inner.openPage(pageId));
      async.flushMicrotasks();
      inner.execute(
        core.AddStrokes(
          pageId: pageId,
          strokes: [for (final s in list) s.copyWith(pageId: pageId)],
        ),
      );
      inner
        ..closePage(pageId)
        ..clearHistory();
    }
    async.flushMicrotasks();
  }

  ink.InkPageController controller(String pageId) {
    final c = ink_testing.createTestPageController(pageId: pageId);
    _controllers.add(c);
    return c;
  }

  PageMount mount(
    String pageId, {
    ink.InkPageController? controller,
    void Function(core.PageContentChange change)? onContentChanged,
  }) {
    final page = session.pages.firstWhere((p) => p.id == pageId);
    final m = PageMount(
      session: session,
      page: page,
      controller: controller ?? this.controller(pageId),
      onContentChanged: onContentChanged,
    );
    _mounts.add(m);
    return m;
  }

  /// Opens [pageId] outside any mount (so commands can run on it).
  void pin(String pageId) {
    unawaited(session.inner.openPage(pageId));
    async.flushMicrotasks();
  }

  void dispose() {
    for (final m in _mounts) {
      m.dispose();
    }
    for (final c in _controllers) {
      c.dispose();
    }
    unawaited(session.inner.close());
    unawaited(store.close());
    async.flushMicrotasks();
  }
}

void _mountTest(String description, void Function(_Env env) body) {
  test(description, () {
    fakeAsync((async) {
      final env = _Env(async);
      try {
        body(env);
      } finally {
        env.dispose();
      }
    });
  });
}

core.Stroke _stroke(String id, {double y = 100, String pageId = _p0}) =>
    lineStroke(id: id, pageId: pageId, x0: 60, y0: y, x1: 300, y1: y);

void main() {
  _mountTest('load → updateContent with the session content', (env) {
    env.open(
      strokes: {
        _p0: [_stroke('a'), _stroke('b', y: 200)],
      },
    );
    final changes = <core.PageContentChange>[];
    final mount = env.mount(_p0, onContentChanged: changes.add);

    expect(mount.pageId, _p0);
    expect(mount.isLoaded.value, isFalse);
    expect(mount.controller.content, isNull);
    expect(env.session.calls, ['openPage:$_p0']);

    env.async.flushMicrotasks();
    final loaded = env.session.pageIfLoaded(_p0)!;
    expect(mount.isLoaded.value, isTrue);
    expect(changes.map((c) => c.origin), [core.ChangeOrigin.load]);
    expect(mount.content, same(loaded));
    final content = mount.controller.content!;
    expect(content.revision, loaded.revision);
    expect(content.page, loaded.page);
    expect(content.strokes.map((s) => s.id), ['a', 'b']);
    expect(env.session.executeDuringDelivery, isFalse);
  });

  _mountTest('an already loaded page delivers its load change', (env) {
    env.open(
      strokes: {
        _p0: [_stroke('a')],
      },
    );
    env.pin(_p0); // loaded and pinned before the mount exists
    final changes = <core.PageContentChange>[];
    final mount = env.mount(_p0, onContentChanged: changes.add);
    env.async.flushMicrotasks();

    expect(changes.map((c) => c.origin), [core.ChangeOrigin.load]);
    expect(mount.isLoaded.value, isTrue);
    expect(mount.controller.content!.strokes.map((s) => s.id), ['a']);
  });

  _mountTest('local and undo changes → updateContent once each', (env) {
    env.open();
    final changes = <core.PageContentChange>[];
    final mount = env.mount(_p0, onContentChanged: changes.add);
    env.async.flushMicrotasks();
    changes.clear();
    var notified = 0;
    mount.controller.addListener(() => notified++);

    env.session.execute(core.AddStrokes(pageId: _p0, strokes: [_stroke('n')]));
    expect(changes.map((c) => c.origin), [core.ChangeOrigin.local]);
    var content = mount.controller.content!;
    expect(content.revision, env.session.pageIfLoaded(_p0)!.revision);
    expect(content.strokes.map((s) => s.id), ['n']);

    unawaited(env.session.undo());
    env.async.flushMicrotasks();
    expect(changes.map((c) => c.origin), [
      core.ChangeOrigin.local,
      core.ChangeOrigin.undo,
    ]);
    content = mount.controller.content!;
    expect(content.revision, env.session.pageIfLoaded(_p0)!.revision);
    expect(content.strokes, isEmpty);

    unawaited(env.session.redo());
    env.async.flushMicrotasks();
    expect(changes.last.origin, core.ChangeOrigin.redo);
    expect(mount.controller.content!.strokes.map((s) => s.id), ['n']);
    expect(changes, hasLength(3));
    // Stroke changes do not change the page value: no page notification.
    expect(notified, 0);
    expect(env.session.executeDuringDelivery, isFalse);
  });

  _mountTest('changes of another page do not reach this mount', (env) {
    env.open();
    final changes = <core.PageContentChange>[];
    env.mount(_p0, onContentChanged: changes.add);
    env.pin(_p1);
    env.async.flushMicrotasks();
    changes.clear();

    env.session.execute(
      core.AddStrokes(
        pageId: _p1,
        strokes: [_stroke('x', pageId: _p1)],
      ),
    );
    expect(changes, isEmpty);
  });

  _mountTest('dispose → no subscription, closePage once, idempotent', (env) {
    env.open();
    final changes = <core.PageContentChange>[];
    final mount = env.mount(_p0, onContentChanged: changes.add);
    env.async.flushMicrotasks();
    expect(env.session.activeSubscriptions, 1);
    final before = mount.controller.content;

    mount.dispose();
    mount.dispose();
    env.async.flushMicrotasks();
    expect(mount.isDisposed, isTrue);
    expect(env.session.activeSubscriptions, 0);
    expect(env.session.countOf('closePage:$_p0'), 1);

    // Later changes reach neither the controller nor the callback.
    changes.clear();
    env.pin(_p0);
    env.session.execute(core.AddStrokes(pageId: _p0, strokes: [_stroke('z')]));
    expect(changes, isEmpty);
    expect(mount.controller.content, same(before));
  });

  _mountTest('dispose while loading releases the pin when the load ends', (
    env,
  ) {
    env.open();
    env.session.holdPageLoads();
    final mount = env.mount(_p0);
    env.async.flushMicrotasks();
    expect(mount.isLoaded.value, isFalse);

    mount.dispose();
    expect(env.session.countOf('closePage:$_p0'), 0);
    env.session.releasePageLoads();
    env.async.flushMicrotasks();
    expect(env.session.countOf('closePage:$_p0'), 1);
    expect(env.session.activeSubscriptions, 0);
    expect(mount.controller.content, isNull);
  });

  _mountTest('openPage failure is reported and leaves isLoaded false', (env) {
    env.open();
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      final missing = core.Page(
        id: 'missing-page',
        noteId: env.session.noteId,
        sortKey: 'z',
        size: kA4,
        background: const core.BlankBackground(),
        createdAt: 0,
        updatedAt: 0,
      );
      final mount = PageMount(
        session: env.session,
        page: missing,
        controller: env.controller('missing-page'),
      );
      env.async.flushMicrotasks();
      expect(mount.isLoaded.value, isFalse);
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<core.EntityNotFoundException>());
      expect(reported.single.library, 'feature_editor');
      mount.dispose();
      // The failed open took no pin: nothing to release.
      expect(env.session.countOf('closePage:missing-page'), 0);
    } finally {
      FlutterError.onError = previous;
    }
  });

  test('MountedPages: register / lookup / unregister, notified later', () {
    fakeAsync((async) {
      final env = _Env(async)..open();
      try {
        final pages = MountedPages();
        var notified = 0;
        pages.addListener(() => notified++);
        final a = env.mount(_p0);
        final b = env.mount(_p1);
        pages
          ..register(a)
          ..register(b);
        expect(notified, 0); // never from inside the registering call
        async.flushMicrotasks();
        expect(notified, 1); // coalesced
        expect(pages[_p0], same(a));
        expect(pages.all, [a, b]);
        expect(pages.pageIds, [_p0, _p1]);

        pages
          ..unregister(_p0)
          ..unregister('unknown');
        async.flushMicrotasks();
        expect(notified, 2);
        expect(pages[_p0], isNull);
        expect(pages.all, [b]);

        pages.dispose();
        expect(pages.all, isEmpty);
      } finally {
        env.dispose();
      }
    });
  });
}
