// m5-7/04-editor 8.2 E2-10b, 6.11.2 (P-B — review S-11), 6.18: the text
// draft of a long edit session in the device key editor.textDraft.
// - TextDraftStore under fake_async: a change → ONE write 5 s later (the
//   latest draft; a session typed without a pause is still kept every 5 s),
//   the JSON shape {"v":1,"noteId","pageId","boxId","isNew","draft"}, the
//   session end removes the key only when this session wrote it, a draft of
//   another note is ignored by load and left in place, remove() only when the
//   key still holds that draft, unreadable values → null;
// - on the editor screen: the session's draft changes reach the store, the
//   key is removed right AFTER the session's one command (also when no
//   command is needed), the command stays one per session (E-6).
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/text/text_draft_store.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/settings_env.dart';

const _key = 'editor.textDraft';

core.TextBoxObject _box({
  String id = 'box-1',
  String pageId = 'p1',
  String text = '회의록',
}) => core.TextBoxObject(
  id: id,
  pageId: pageId,
  frame: core.ElementFrame(core.PageRect.fromLTWH(100, 100, 240, 30)),
  text: text,
  style: const core.TextBoxStyle(),
  createdAt: 5,
);

/// A store on a recording fake settings repository, inside fakeAsync.
({TextDraftStore store, RecordingSettings settings, core.NoteStore notes}) _env(
  FakeAsync async, {
  String noteId = 'note-a',
}) {
  final notes = createFakeNoteStore();
  final settings = RecordingSettings(notes.settings);
  return (
    store: TextDraftStore(settings: settings, noteId: noteId),
    settings: settings,
    notes: notes,
  );
}

void _change(TextDraftStore store, String text, {String boxId = 'box-1'}) =>
    store.changed(
      pageId: 'p1',
      boxId: boxId,
      isNew: false,
      draft: _box(id: boxId, text: text),
    );

Map<String, Object?> _stored(FakeAsync async, core.NoteStore notes) {
  Map<String, Object?>? out;
  unawaited(
    notes.settings.get(EditorSettingKeys.textDraft).then((v) => out = v),
  );
  async.flushMicrotasks();
  return out!;
}

void main() {
  group('TextDraftStore (fake_async)', () {
    test('a change → one write 5 s later, with the latest draft', () {
      fakeAsync((async) {
        final e = _env(async);
        _change(e.store, '회');
        async.elapse(const Duration(seconds: 2));
        _change(e.store, '회의');
        async.elapse(const Duration(milliseconds: 2900));
        expect(e.settings.writesOf(_key), isEmpty); // 4.9 s
        expect(e.store.isPending, isTrue);
        async.elapse(const Duration(milliseconds: 100));
        expect(e.settings.writesOf(_key), hasLength(1));
        expect(e.store.isPending, isFalse);
        final json = e.settings.writesOf(_key).single! as Map<String, Object?>;
        expect(json.keys.toList(), [
          'v',
          'noteId',
          'pageId',
          'boxId',
          'isNew',
          'draft',
        ]);
        expect(json['v'], 1);
        expect(json['noteId'], 'note-a');
        expect(json['pageId'], 'p1');
        expect(json['boxId'], 'box-1');
        expect(json['isNew'], false);
        expect(json['draft'], _box(text: '회의').toJson());
        // Nothing more without a change.
        async.elapse(const Duration(seconds: 30));
        expect(e.settings.writesOf(_key), hasLength(1));
        unawaited(e.notes.close());
        async.flushMicrotasks();
      });
    });

    test('typing without a pause is still kept every 5 s', () {
      fakeAsync((async) {
        final e = _env(async);
        for (var s = 0; s < 12; s++) {
          _change(e.store, 'x' * (s + 1));
          async.elapse(const Duration(seconds: 1));
        }
        // changes at 0..11 s → writes at 5 s, 10 s and 15 s
        expect(e.settings.writesOf(_key), hasLength(2));
        async.elapse(const Duration(seconds: 5));
        final writes = e.settings.writesOf(_key);
        expect(writes, hasLength(3));
        expect(
          [
            for (final w in writes)
              ((w! as Map)['draft']! as Map)['text'] as String,
          ],
          ['x' * 5, 'x' * 10, 'x' * 12],
        );
        unawaited(e.notes.close());
        async.flushMicrotasks();
      });
    });

    test('session end after a write → the key removed once; before the '
        'first write → no write, no removal', () {
      fakeAsync((async) {
        final e = _env(async);
        _change(e.store, '회의록');
        async.elapse(const Duration(seconds: 5));
        expect(_stored(async, e.notes)['boxId'], 'box-1');
        unawaited(e.store.sessionEnded());
        async.flushMicrotasks();
        expect(e.settings.writesOf(_key), [anything, 'reset']);
        expect(_stored(async, e.notes), isEmpty);

        // A short session: ended before its first write.
        _change(e.store, '짧은 글');
        async.elapse(const Duration(seconds: 3));
        unawaited(e.store.sessionEnded());
        async.elapse(const Duration(seconds: 10));
        expect(e.settings.writesOf(_key), [anything, 'reset']);
        unawaited(e.notes.close());
        async.flushMicrotasks();
      });
    });

    test("another note's draft: load ignores it, a session of this note "
        'that wrote nothing leaves it', () {
      fakeAsync((async) {
        final a = _env(async);
        _change(a.store, 'A의 글');
        async.elapse(const Duration(seconds: 5));
        final b = TextDraftStore(settings: a.settings, noteId: 'note-b');
        TextDraft? loaded;
        unawaited(b.load().then((d) => loaded = d));
        async.flushMicrotasks();
        expect(loaded, isNull);
        _change(b, 'B');
        unawaited(b.sessionEnded()); // before its write
        async.elapse(const Duration(seconds: 6));
        expect(_stored(async, a.notes)['noteId'], 'note-a');
        // A's own store sees its draft.
        unawaited(a.store.load().then((d) => loaded = d));
        async.flushMicrotasks();
        expect(loaded?.draft.text, 'A의 글');
        expect(loaded?.noteId, 'note-a');
        unawaited(a.notes.close());
        async.flushMicrotasks();
      });
    });

    test('remove(draft) only when the key still holds that draft', () {
      fakeAsync((async) {
        final e = _env(async);
        _change(e.store, '처음');
        async.elapse(const Duration(seconds: 5));
        TextDraft? first;
        unawaited(e.store.load().then((d) => first = d));
        async.flushMicrotasks();
        // A newer session overwrote it.
        _change(e.store, '나중', boxId: 'box-2');
        async.elapse(const Duration(seconds: 5));
        unawaited(e.store.remove(first!));
        async.flushMicrotasks();
        expect(_stored(async, e.notes)['boxId'], 'box-2');
        TextDraft? second;
        unawaited(e.store.load().then((d) => second = d));
        async.flushMicrotasks();
        unawaited(e.store.remove(second!));
        async.flushMicrotasks();
        expect(_stored(async, e.notes), isEmpty);
        unawaited(e.notes.close());
        async.flushMicrotasks();
      });
    });

    test('dispose drops a waiting write', () {
      fakeAsync((async) {
        final e = _env(async);
        _change(e.store, '글');
        e.store.dispose();
        async.elapse(const Duration(seconds: 10));
        expect(e.settings.writesOf(_key), isEmpty);
        unawaited(e.notes.close());
        async.flushMicrotasks();
      });
    });
  });

  group('TextDraft JSON', () {
    final draft = TextDraft(
      noteId: 'n',
      pageId: 'p1',
      boxId: 'box-1',
      isNew: true,
      draft: _box(),
    );

    test('round trip', () {
      expect(TextDraft.fromJson(draft.toJson()), draft);
      expect(draft.toJson()['draft'], _box().toJson());
    });

    test('unreadable values → null (never throws)', () {
      expect(TextDraft.fromJson(const {}), isNull);
      expect(TextDraft.fromJson({...draft.toJson(), 'isNew': 'yes'}), isNull);
      expect(TextDraft.fromJson({...draft.toJson(), 'noteId': 3}), isNull);
      expect(TextDraft.fromJson({...draft.toJson(), 'draft': 'x'}), isNull);
      expect(
        TextDraft.fromJson({
          ...draft.toJson(),
          'draft': {'type': 'text'},
        }),
        isNull,
      );
      final shape = PageObjectFixtures.shape(pageId: 'p1');
      expect(
        TextDraft.fromJson({...draft.toJson(), 'draft': shape.toJson()}),
        isNull,
      );
    });
  });

  group('on the editor screen', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await useInkTestFonts();
    });

    Future<
      ({EditorTestHandles h, _OrderedSettings settings, TextEditNotifier text})
    >
    open(WidgetTester tester) async {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      final settings = _OrderedSettings(store.settings);
      final h = await pumpEditor(
        tester,
        store: store,
        pages: 1,
        overrides: [
          core.settingsRepositoryProvider.overrideWithValue(settings),
        ],
      );
      settings.executes = () => [
        for (final c in h.recorder!.calls)
          if (c.startsWith('execute')) c,
      ];
      return (
        h: h,
        settings: settings,
        text: h.container.read(editorTextEditProvider.notifier),
      );
    }

    testWidgets('draft changes → one write 5 s later; the end removes the '
        'key right after the one AddObjects', (tester) async {
      final (:h, :settings, :text) = await open(tester);
      text.start(_box(pageId: h.pageId(0), text: ''), isNew: true);
      text.updateText('회의');
      await tester.pump(const Duration(seconds: 2));
      text.updateText('회의록 첫 줄');
      await tester.pump(const Duration(milliseconds: 2900));
      expect(settings.log.where((l) => l.startsWith('set')), isEmpty);
      await tester.pump(const Duration(milliseconds: 100));
      expect(settings.log, ['set [] ']);
      final stored = await h.store.settings.get(EditorSettingKeys.textDraft);
      expect(stored['noteId'], h.noteId);
      expect(stored['pageId'], h.pageId(0));
      expect(stored['isNew'], true);
      expect((stored['draft']! as Map)['text'], '회의록 첫 줄');
      expect(h.session.pageIfLoaded(h.pageId(0))!.objects, isEmpty);

      await text.end(reason: TextEditEndReason.tapOutside);
      await tester.pump();
      // The removal saw the command already run.
      expect(settings.log, ['set [] ', 'reset [execute:add-objects] ']);
      expect(await h.store.settings.get(EditorSettingKeys.textDraft), isEmpty);
      expect(h.session.history.undoDepth, 1);
    });

    testWidgets('no command needed (a new box left blank) → the key is '
        'removed too; a session under 5 s writes nothing', (tester) async {
      final (:h, :settings, :text) = await open(tester);
      text.start(_box(pageId: h.pageId(0), text: ''), isNew: true);
      text.updateText('   ');
      await tester.pump(const Duration(seconds: 6));
      expect(settings.log, ['set [] ']);
      await text.end(reason: TextEditEndReason.escape); // spaces only
      await tester.pump();
      expect(settings.log, ['set [] ', 'reset [] ']);

      text.start(_box(id: 'box-2', pageId: h.pageId(0), text: ''), isNew: true);
      text.updateText('짧게');
      await tester.pump(const Duration(seconds: 2));
      await text.end(reason: TextEditEndReason.tapOutside);
      await tester.pump(const Duration(seconds: 10));
      expect(settings.log, ['set [] ', 'reset [] ']); // nothing new
      expect(h.recorder!.countOf('execute:add-objects'), 1);
    });
  });
}

/// Logs each write of editor.textDraft with the session commands run so
/// far: 'set [<executes>] ' / 'reset [<executes>] '.
final class _OrderedSettings implements core.SettingsRepository {
  _OrderedSettings(this.inner);

  final core.SettingsRepository inner;
  List<String> Function() executes = () => const [];
  final List<String> log = [];

  void _log(String op, String key) {
    if (key == _key) log.add('$op [${executes().join(', ')}] ');
  }

  @override
  Future<T> get<T>(core.SettingKey<T> key) => inner.get(key);

  @override
  Stream<T> watch<T>(core.SettingKey<T> key) => inner.watch(key);

  @override
  Stream<core.SettingsSnapshot> watchAll() => inner.watchAll();

  @override
  Future<void> set<T>(core.SettingKey<T> key, T value) {
    _log('set', key.name);
    return inner.set(key, value);
  }

  @override
  Future<void> reset<T>(core.SettingKey<T> key) {
    _log('reset', key.name);
    return inner.reset(key);
  }
}
