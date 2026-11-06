// E2-01 (m5-7/04-editor 6.11.2, 6.11.5, E-6): the text edit session.
// - textSessionCommand: every row of the 6.11.5 table → 0 or 1 command;
// - hiddenIdsOf / previewObjectsOf: the hidden-id and preview table;
// - TextEditNotifier on the editor screen (fake store, real R2-B3 INK):
//   one command per session, undoDepth +1 (or 0), the measured height,
//   end twice with two reasons → one command and the first reason, the
//   characters still being composed are stored, hidden ids on the page
//   controller during the session, the sheet-mode preview, a remotely
//   deleted original → a new box with a new id.
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';

core.TextBoxObject _box({
  String id = 'box-1',
  String pageId = 'p1',
  String text = '회의록',
  double width = 240,
  core.TextBoxStyle style = const core.TextBoxStyle(),
}) => core.TextBoxObject(
  id: id,
  pageId: pageId,
  frame: core.ElementFrame(core.PageRect.fromLTWH(100, 100, width, 30)),
  text: text,
  style: style,
  createdAt: 5,
);

TextEditState _state(
  core.TextBoxObject box, {
  required bool isNew,
  WebTextInputMode mode = WebTextInputMode.inline,
}) => TextEditState(
  pageId: box.pageId,
  boxId: box.id,
  original: isNew ? null : box,
  draft: box,
  isNew: isNew,
  mode: mode,
);

core.EditCommand? _command(
  TextEditState s,
  core.TextBoxObject finalDraft, {
  core.PageObject? loaded,
}) => textSessionCommand(
  s,
  finalDraft,
  loaded: loaded,
  newId: () => 'new-id',
  now: 77,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await useInkTestFonts();
  });
  tearDown(() => TextEditNotifier.debugIsWebOverride = null);

  group('textSessionCommand (6.11.5 table)', () {
    final original = _box();

    test('new box, only spaces → no command', () {
      final s = _state(_box(text: ''), isNew: true);
      expect(_command(s, _box(text: '  \n ')), isNull);
    });

    test('new box with text → AddObjects([draft])', () {
      final s = _state(_box(text: ''), isNew: true);
      final draft = _box(text: '안녕');
      final c = _command(s, draft);
      expect(c, isA<core.AddObjects>());
      c as core.AddObjects;
      expect(c.pageId, 'p1');
      expect(c.objects, [draft]);
    });

    test('existing box unchanged (text, style, width) → no command', () {
      final s = _state(original, isNew: false);
      // A new measured height alone is no change.
      final remeasured = withHeight(original, 55);
      expect(_command(s, remeasured, loaded: original), isNull);
    });

    test('existing box changed → UpdateObjects([draft])', () {
      final s = _state(original, isNew: false);
      for (final draft in [
        original.copyWith(text: '회의록 abc'),
        original.copyWith(style: const core.TextBoxStyle(bold: true)),
        _box(width: 300),
      ]) {
        final c = _command(s, draft, loaded: original);
        expect(c, isA<core.UpdateObjects>(), reason: '$draft');
        expect((c! as core.UpdateObjects).objects, [draft]);
      }
    });

    test('existing box changed, original deleted remotely → AddObjects with a '
        'new id', () {
      final s = _state(original, isNew: false);
      final c = _command(s, original.copyWith(text: '살린 글'));
      expect(c, isA<core.AddObjects>());
      final added =
          (c! as core.AddObjects).objects.single as core.TextBoxObject;
      expect(added.id, 'new-id');
      expect(added.createdAt, 77);
      expect(added.text, '살린 글');
      expect(added.pageId, 'p1');
    });

    test('existing box emptied → RemoveElements([boxId]); already gone → no '
        'command', () {
      final s = _state(original, isNew: false);
      final c = _command(s, original.copyWith(text: ' '), loaded: original);
      expect(c, isA<core.RemoveElements>());
      expect((c! as core.RemoveElements).elementIds, ['box-1']);
      expect(_command(s, original.copyWith(text: '')), isNull);
    });
  });

  test('hiddenIdsOf / previewObjectsOf', () {
    final box = _box();
    expect(hiddenIdsOf(null), isEmpty);
    expect(hiddenIdsOf(_state(box, isNew: true)), isEmpty);
    for (final mode in WebTextInputMode.values) {
      expect(hiddenIdsOf(_state(box, isNew: false, mode: mode)), {'box-1'});
    }
    expect(previewObjectsOf(null), isEmpty);
    expect(previewObjectsOf(_state(box, isNew: false)), isEmpty);
    expect(
      previewObjectsOf(_state(box, isNew: false, mode: WebTextInputMode.sheet)),
      [box],
    );
    expect(
      previewObjectsOf(_state(box, isNew: true, mode: WebTextInputMode.sheet)),
      [box],
    );
  });

  test('withHeight keeps the top-left, width and rotation; at least one '
      'line', () {
    final box = _box().copyWith(
      frame: core.ElementFrame(
        core.PageRect.fromLTWH(10, 20, 200, 30),
        rotation: 0.5,
      ),
    );
    final tall = withHeight(box, 90);
    expect(tall.frame.rect, core.PageRect.fromLTWH(10, 20, 200, 90));
    expect(tall.frame.rotation, 0.5);
    final low = withHeight(box, 1);
    final oneLine = box.style.fontSizePt * box.style.lineHeight;
    expect(low.frame.rect.bottom - low.frame.rect.top, oneLine);
  });

  group('TextEditNotifier on the editor screen', () {
    Future<(EditorTestHandles, TextEditNotifier)> open(
      WidgetTester tester, {
      List<core.PageObject> objects = const [],
    }) async {
      final h = await pumpEditor(
        tester,
        pages: 1,
        objectsByPageIndex: {0: objects},
      );
      return (h, h.container.read(editorTextEditProvider.notifier));
    }

    List<String> executes(EditorTestHandles h) => [
      for (final c in h.recorder!.calls)
        if (c.startsWith('execute')) c,
    ];

    testWidgets('a new box: one AddObjects, measured height, undoDepth 1', (
      tester,
    ) async {
      final (h, notifier) = await open(tester);
      final box = _box(pageId: h.pageId(0), text: '');
      notifier.start(box, isNew: true);
      expect(h.container.read(editorTextEditProvider)!.isNew, isTrue);
      expect(h.controllerOf(0).hiddenObjectIds, isEmpty);
      notifier.updateText('회의록 abc');
      await notifier.end(reason: TextEditEndReason.tapOutside);
      await tester.pump();

      expect(executes(h), ['execute:add-objects']);
      expect(h.session.history.undoDepth, 1);
      final stored =
          h.session.pageIfLoaded(h.pageId(0))!.objectById('box-1')!
              as core.TextBoxObject;
      expect(stored.text, '회의록 abc');
      final measured = ink.InkTextLayout.measureSync(
        '회의록 abc',
        stored.style,
        widthPt: 240,
      )!;
      expect(
        stored.frame.rect.bottom - stored.frame.rect.top,
        closeTo(measured.height, 1e-9),
      );
      expect(h.container.read(editorTextEditProvider), isNull);
      expect(notifier.lastEndReason, TextEditEndReason.tapOutside);
    });

    testWidgets('end twice with two reasons → one command, the first reason', (
      tester,
    ) async {
      final (h, notifier) = await open(tester);
      notifier
        ..start(_box(pageId: h.pageId(0), text: ''), isNew: true)
        ..updateText('한 번');
      final first = notifier.end(reason: TextEditEndReason.tapOutside);
      final second = notifier.end(reason: TextEditEndReason.toolChange);
      await first;
      await second;
      await notifier.end(reason: TextEditEndReason.escape);
      expect(executes(h), ['execute:add-objects']);
      expect(notifier.lastEndReason, TextEditEndReason.tapOutside);
      expect(h.session.history.undoDepth, 1);
    });

    testWidgets('a new box left empty → no command', (tester) async {
      final (h, notifier) = await open(tester);
      notifier.start(_box(pageId: h.pageId(0), text: ''), isNew: true);
      notifier.updateText('   ');
      await notifier.end(reason: TextEditEndReason.tapOutside);
      expect(executes(h), isEmpty);
      expect(h.session.history.undoDepth, 0);
    });

    testWidgets('the characters still being composed are stored', (
      tester,
    ) async {
      final (h, notifier) = await open(tester);
      notifier.start(_box(pageId: h.pageId(0), text: ''), isNew: true);
      // V1: an IME value with a composing range — controller.text has them.
      final controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: '안녕',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 1, end: 2),
        ),
      );
      addTearDown(controller.dispose);
      notifier.updateText(controller.text);
      await notifier.end(reason: TextEditEndReason.tapOutside);
      final stored =
          h.session.pageIfLoaded(h.pageId(0))!.objectById('box-1')!
              as core.TextBoxObject;
      expect(stored.text, '안녕');
    });

    testWidgets('an existing box: hidden while editing, UpdateObjects at the '
        'end', (tester) async {
      final seeded = PageObjectFixtures.textBox(
        pageId: 'x',
        id: 'tb-1',
        text: '처음',
      );
      final (h, notifier) = await open(tester, objects: [seeded]);
      final box =
          h.session.pageIfLoaded(h.pageId(0))!.objectById('tb-1')!
              as core.TextBoxObject;
      notifier.start(box, isNew: false);
      expect(h.controllerOf(0).hiddenObjectIds, {'tb-1'});
      expect(h.controllerOf(0).previewObjects, isEmpty, reason: 'inline');
      notifier.updateText('처음 고침');
      await notifier.end(reason: TextEditEndReason.focusLost);

      expect(executes(h), ['execute:update-objects']);
      expect(h.session.history.undoDepth, 1);
      expect(h.controllerOf(0).hiddenObjectIds, isEmpty);
      final stored =
          h.session.pageIfLoaded(h.pageId(0))!.objectById('tb-1')!
              as core.TextBoxObject;
      expect(stored.text, '처음 고침');
    });

    testWidgets('an existing box left as it was → no command', (tester) async {
      final seeded = PageObjectFixtures.textBox(pageId: 'x', id: 'tb-1');
      final (h, notifier) = await open(tester, objects: [seeded]);
      final box = h.session.pageIfLoaded(h.pageId(0))!.objectById('tb-1')!;
      notifier.start(box as core.TextBoxObject, isNew: false);
      notifier.updateText(box.text);
      await notifier.end(reason: TextEditEndReason.escape);
      expect(executes(h), isEmpty);
      expect(h.session.history.undoDepth, 0);
      expect(h.controllerOf(0).hiddenObjectIds, isEmpty);
    });

    testWidgets('an existing box emptied → RemoveElements', (tester) async {
      final seeded = PageObjectFixtures.textBox(pageId: 'x', id: 'tb-1');
      final (h, notifier) = await open(tester, objects: [seeded]);
      final box = h.session.pageIfLoaded(h.pageId(0))!.objectById('tb-1')!;
      notifier.start(box as core.TextBoxObject, isNew: false);
      notifier.updateText('');
      await notifier.end(reason: TextEditEndReason.tapOutside);
      expect(executes(h), ['execute:remove-elements']);
      expect(h.session.pageIfLoaded(h.pageId(0))!.objectCount, 0);
      expect(h.session.history.undoDepth, 1);
    });

    testWidgets('the original deleted meanwhile → a new box with a new id', (
      tester,
    ) async {
      final seeded = PageObjectFixtures.textBox(pageId: 'x', id: 'tb-1');
      final (h, notifier) = await open(tester, objects: [seeded]);
      final box = h.session.pageIfLoaded(h.pageId(0))!.objectById('tb-1')!;
      notifier.start(box as core.TextBoxObject, isNew: false);
      notifier.updateText('지켜야 할 글');
      // Another change deletes the box (here through the session itself).
      h.session.execute(
        core.RemoveElements(pageId: h.pageId(0), elementIds: const ['tb-1']),
      );
      await notifier.end(reason: TextEditEndReason.tapOutside);

      expect(executes(h), ['execute:add-objects']);
      final objects = h.session.pageIfLoaded(h.pageId(0))!.objects;
      expect(objects, hasLength(1));
      final kept = objects.single as core.TextBoxObject;
      expect(kept.id, isNot('tb-1'));
      expect(kept.text, '지켜야 할 글');
    });

    testWidgets('sheet mode (web): a same-id preview and the id hidden', (
      tester,
    ) async {
      TextEditNotifier.debugIsWebOverride = true;
      final seeded = PageObjectFixtures.textBox(pageId: 'x', id: 'tb-1');
      final (h, notifier) = await open(tester, objects: [seeded]);
      h.container
          .read(editorDeviceStateProvider.notifier)
          .setWebTextInput(WebTextInputMode.sheet);
      expect(notifier.modeForNewSession, WebTextInputMode.sheet);
      final box = h.session.pageIfLoaded(h.pageId(0))!.objectById('tb-1')!;
      notifier.start(box as core.TextBoxObject, isNew: false);
      notifier.updateText('미리보기');
      final c = h.controllerOf(0);
      expect(c.hiddenObjectIds, {'tb-1'});
      expect(c.previewObjects.single.id, 'tb-1');
      expect((c.previewObjects.single as core.TextBoxObject).text, '미리보기');
      await notifier.end(reason: TextEditEndReason.done);
      expect(c.previewObjects, isEmpty);
      expect(c.hiddenObjectIds, isEmpty);
      expect(h.session.history.undoDepth, 1);
    });

    testWidgets('native: the mode is inline whatever the developer choice', (
      tester,
    ) async {
      TextEditNotifier.debugIsWebOverride = false;
      final (h, notifier) = await open(tester);
      h.container
          .read(editorDeviceStateProvider.notifier)
          .setWebTextInput(WebTextInputMode.sheet);
      expect(notifier.modeForNewSession, WebTextInputMode.inline);
      TextEditNotifier.debugIsWebOverride = true;
      h.container
          .read(editorDeviceStateProvider.notifier)
          .setWebTextInput(WebTextInputMode.textarea);
      expect(
        notifier.modeForNewSession,
        WebTextInputMode.inline,
        reason: 'textarea (E2-11, P-C) is not built yet',
      );
    });

    testWidgets('starting a new session ends the previous one first', (
      tester,
    ) async {
      final (h, notifier) = await open(tester);
      notifier
        ..start(_box(pageId: h.pageId(0), text: '', id: 'a'), isNew: true)
        ..updateText('첫 상자')
        ..start(_box(pageId: h.pageId(0), text: '', id: 'b'), isNew: true);
      await notifier.ending;
      expect(executes(h), ['execute:add-objects']);
      expect(h.container.read(editorTextEditProvider)!.boxId, 'b');
      expect(h.session.pageIfLoaded(h.pageId(0))!.objectById('a'), isNotNull);
      expect(editorSessionValueProvider, isNotNull);
    });
  });
}
