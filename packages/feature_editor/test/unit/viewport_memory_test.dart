// E-03: ViewportMemory (04-editor 6.3.5, stored form 6.14) on the fake store
// with fake_async: editor.viewport (device) keeps the 50 most recent notes
// (LRU by `at`), saves are debounced 2 s, flush/dispose write at once, entries
// stored meanwhile are merged, invalid entries are dropped and reported, and an
// anchor whose page is gone restores page 0 (ViewportController.restore).
import 'dart:async';
import 'dart:ui' show Offset, Size;

import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/viewport/viewport_controller.dart';
import 'package:feature_editor/src/viewport/viewport_memory.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/settings_env.dart';
import '../helpers/test_data.dart';

final _key = EditorSettingKeys.viewport;
const _second = Duration(seconds: 1);
const _ms = Duration(milliseconds: 1);

ViewportAnchor _anchor(String pageId, {double dy = 0, double zoom = 1}) =>
    ViewportAnchor(pageId: pageId, offsetInPage: Offset(0, dy), zoom: zoom);

/// A ViewportMemory on [env]'s recording settings with a settable clock.
final class _MemoryEnv {
  _MemoryEnv(this.env) : _clock = _Clock() {
    memory = ViewportMemory(env.settings, now: () => _clock.now);
  }
  final SettingsEnv env;
  final _Clock _clock;
  late final ViewportMemory memory;
  set now(int ms) => _clock.now = ms;

  ViewportAnchor? load(String noteId) {
    ViewportAnchor? result;
    unawaited(memory.load(noteId).then((a) => result = a));
    env.async.flushMicrotasks();
    return result;
  }

  List<Map<String, Object?>> get storedEntries => [
    for (final e in (env.storedValue(_key)['entries'] as List? ?? const []))
      Map<String, Object?>.from(e as Map),
  ];

  List<Object?> get writes => env.settings.writesOf(_key.name);
}

final class _Clock {
  int now = 1730700000000;
}

void _run(void Function(_MemoryEnv m) body) {
  runSettingsEnv((env) {
    final m = _MemoryEnv(env);
    body(m);
    m.memory.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the key is editor.viewport with device scope', () {
    expect(_key.name, 'editor.viewport');
    expect(_key.scope, core.SettingScope.device);
  });

  test('a burst of saves writes once, 2 s after the last one', () {
    _run((m) {
      m.memory.save('n1', _anchor('p1', dy: 10));
      m.env.async.elapse(const Duration(milliseconds: 500));
      m.memory.save('n1', _anchor('p1', dy: 20));
      m.env.async.elapse(const Duration(milliseconds: 500));
      m.memory.save('n1', _anchor('p2', dy: 30, zoom: 1.5));
      m.env.async.elapse(_second * 2 - _ms);
      expect(m.writes, isEmpty);
      m.env.async.elapse(_ms);
      m.env.async.flushMicrotasks();
      expect(m.writes, hasLength(1));
      expect(m.storedEntries, [
        {
          'noteId': 'n1',
          'pageId': 'p2',
          'dx': 0.0,
          'dy': 30.0,
          'zoom': 1.5,
          'at': 1730700000000,
        },
      ]);
      expect(m.env.storedValue(_key)['v'], 1);
    });
  });

  test('load: a saved anchor (before and after the write), unknown → null', () {
    _run((m) {
      expect(m.load('n1'), isNull);
      m.memory.save('n1', _anchor('p3', dy: 120.5, zoom: 2));
      expect(
        m.load('n1'),
        _anchor('p3', dy: 120.5, zoom: 2),
        reason: 'pending',
      );
      m.env.async.elapse(_second * 2);
      expect(m.writes, hasLength(1));
      // A new instance reads it back from CORE.
      final other = ViewportMemory(m.env.settings, now: () => 0);
      ViewportAnchor? loaded;
      unawaited(other.load('n1').then((a) => loaded = a));
      m.env.async.flushMicrotasks();
      expect(loaded, _anchor('p3', dy: 120.5, zoom: 2));
      expect(m.load('n2'), isNull);
      other.dispose();
    });
  });

  test('keeps the 50 most recent notes (LRU by at)', () {
    _run((m) {
      for (var i = 0; i < 50; i++) {
        m.now = 1000 + i;
        m.memory.save('n$i', _anchor('p'));
      }
      unawaited(m.memory.flush());
      m.env.async.flushMicrotasks();
      expect(m.storedEntries, hasLength(50));

      // Viewing n0 again makes it the newest; n50 pushes out n1 (now oldest).
      m.now = 2000;
      m.memory.save('n0', _anchor('p', dy: 5));
      m.now = 2001;
      m.memory.save('n50', _anchor('p'));
      m.env.async.elapse(_second * 2);
      final entries = m.storedEntries;
      expect(entries, hasLength(50));
      final ids = [for (final e in entries) e['noteId']];
      expect(ids.first, 'n50', reason: 'newest first');
      expect(ids[1], 'n0');
      expect(ids, isNot(contains('n1')));
      expect(ids, contains('n2'));
      expect(entries[1]['dy'], 5.0);
      final ats = [for (final e in entries) e['at'] as int];
      expect(ats, [...ats]..sort((a, b) => b.compareTo(a)));
    });
  });

  test('a write keeps entries another instance stored meanwhile', () {
    _run((m) {
      final other = ViewportMemory(m.env.settings, now: () => 5);
      m.memory.save('mine', _anchor('a'));
      other.save('theirs', _anchor('b'));
      unawaited(other.flush());
      m.env.async.flushMicrotasks();
      m.env.async.elapse(_second * 2);
      final ids = {for (final e in m.storedEntries) e['noteId']};
      expect(ids, {'mine', 'theirs'});
      other.dispose();
    });
  });

  test('flush writes now; dispose flushes; nothing to write → no write', () {
    _run((m) {
      unawaited(m.memory.flush());
      m.env.async.flushMicrotasks();
      expect(m.writes, isEmpty);

      m.memory.save('n1', _anchor('p1'));
      var flushed = false;
      unawaited(m.memory.flush().then((_) => flushed = true));
      m.env.async.flushMicrotasks();
      expect(flushed, isTrue);
      expect(m.writes, hasLength(1));
      m.env.async.elapse(_second * 5);
      expect(m.writes, hasLength(1), reason: 'the debounce timer is gone');

      final last = ViewportMemory(m.env.settings, now: () => 9);
      last.save('n2', _anchor('p2'));
      last.dispose();
      m.env.async.flushMicrotasks();
      expect(m.writes, hasLength(2));
      last.save('n3', _anchor('p3')); // after dispose: ignored
      m.env.async.elapse(_second * 5);
      expect(m.writes, hasLength(2));
    });
  });

  test('the write Future waits for a slow commit (no timeout)', () {
    runSettingsEnv((env) {
      final memory = ViewportMemory(env.settings, now: () => 1);
      memory.save('n1', _anchor('p1'));
      var flushed = false;
      unawaited(memory.flush().then((_) => flushed = true));
      env.async.elapse(const Duration(seconds: 2));
      expect(flushed, isFalse);
      env.async.elapse(const Duration(seconds: 2));
      expect(flushed, isTrue);
      memory.dispose();
    }, commitDelay: const Duration(seconds: 3));
  });

  test('invalid stored entries are dropped and reported once per read', () {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
    _run((m) {
      m.env.storeValue(_key, {
        'v': 1,
        'entries': [
          {'noteId': 'ok', 'pageId': 'p', 'dx': 1, 'dy': 2, 'zoom': 1, 'at': 3},
          {'noteId': 7, 'pageId': 'p', 'dx': 0, 'dy': 0, 'zoom': 1, 'at': 1},
          {
            'noteId': 'bad',
            'pageId': 'p',
            'dx': 0,
            'dy': 0,
            'zoom': -1,
            'at': 1,
          },
          'junk',
        ],
      });
      expect(
        m.load('ok'),
        const ViewportAnchor(pageId: 'p', offsetInPage: Offset(1, 2), zoom: 1),
      );
      expect(reported, hasLength(1));
      expect(reported.single.library, 'feature_editor');
      expect(reported.single.exception, isA<FormatException>());
      expect(m.load('bad'), isNull);
      expect(reported, hasLength(2), reason: 'once per read');

      // The next write drops them from the stored list.
      m.memory.save('n1', _anchor('p1'));
      m.env.async.elapse(_second * 2);
      expect({for (final e in m.storedEntries) e['noteId']}, {'ok', 'n1'});
    });
  });

  test('an anchor whose page is gone restores page 0', () {
    _run((m) {
      m.memory.save('note', _anchor('deleted-page', dy: 300, zoom: 2));
      m.env.async.elapse(_second * 2);
      final anchor = m.load('note');
      expect(anchor!.pageId, 'deleted-page');

      final pages = [
        for (var i = 0; i < 3; i++)
          core.Page(
            id: 'p$i',
            noteId: 'note',
            sortKey: '$i',
            size: kA4,
            background: const core.BlankBackground(),
            createdAt: 0,
            updatedAt: 0,
          ),
      ];
      final viewport = ViewportController()
        ..updatePages(pages)
        ..updateViewportSize(const Size(1032, 1376))
        ..restore(anchor);
      expect(viewport.currentPageIndex.value, 0);
      expect(viewport.captureAnchor()!.pageId, 'p0');
      expect(viewport.zoom, closeTo(1, 1e-12));
      viewport.dispose();
    });
  });
}
