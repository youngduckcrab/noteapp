// m5-7/04-editor 8.2 E2-10b, 6.11.2 (P-B — review S-11), appendix C
// (editor.textDraft.restore · .discard): opening a note whose text draft was
// left in editor.textDraft (a reloaded tab, an app that died) shows
// '저장되지 않은 글이 있어요 [되살리기] [버리기]'.
// - 되살리기 → ONE AddObjects step with a NEW id (the original box is not
//   touched), the page comes into view, the key is removed, the banner goes;
//   undo takes the restored box away again;
// - 버리기 → the key removed, no command;
// - a draft of another note → no banner, the key left as it is; an
//   unreadable value → no banner;
// - the draft's page is gone → the current page; a read-only note → only
//   버리기.
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/text/text_draft_store.dart';
import 'package:feature_editor/src/ui/banners/text_draft_banner.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

core.TextBoxObject _box({
  String id = 'box-1',
  String pageId = 'seed',
  String text = '원본',
}) => core.TextBoxObject(
  id: id,
  pageId: pageId,
  frame: core.ElementFrame(core.PageRect.fromLTWH(120, 160, 240, 30)),
  text: text,
  style: const core.TextBoxStyle(),
  createdAt: 5,
);

const _written = '회의록: 원본에 이어 쓴 긴 글';

/// pumpEditor with one page holding the original box 'box-1' ('원본') and
/// [draft] (from the seeded note id and page ids) in editor.textDraft.
Future<EditorTestHandles> _open(
  WidgetTester tester, {
  required TextDraft Function(String noteId, String page0) draft,
  Object? rawDraft,
  bool trash = false,
  int pages = 1,
}) => pumpEditor(
  tester,
  pages: pages,
  objectsByPageIndex: {
    0: [_box()],
  },
  beforePump: (store, noteId, pageId) async {
    await store.settings.set(
      EditorSettingKeys.textDraft,
      rawDraft is Map<String, Object?>
          ? rawDraft
          : draft(noteId, pageId(0)).toJson(),
    );
    if (trash) await store.library.trashItems([core.NoteRef(noteId)]);
  },
);

TextDraft _edited(String noteId, String page0) => TextDraft(
  noteId: noteId,
  pageId: page0,
  boxId: 'box-1',
  isNew: false,
  draft: _box(pageId: page0, text: _written),
);

Finder get _banner => find.byKey(TextDraftBanner.bannerKey);

List<String> _executes(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

List<core.PageObject> _objects(EditorTestHandles h, int index) =>
    h.session.pageIfLoaded(h.pageId(index))!.objects;

Future<Map<String, Object?>> _key(EditorTestHandles h) =>
    h.store.settings.get(EditorSettingKeys.textDraft);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 500)); // + the flash
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await useInkTestFonts();
  });

  testWidgets('a draft of this note → the banner; 되살리기 → one AddObjects '
      'step, a new id, the original untouched, the key removed', (
    tester,
  ) async {
    final h = await _open(tester, draft: _edited);
    await tester.pump();
    expect(_banner, findsOneWidget);
    expect(find.text(EditorStrings.textDraftFound), findsOneWidget);
    expect(find.byKey(TextDraftBanner.restoreKey), findsOneWidget);
    expect(find.byKey(TextDraftBanner.discardKey), findsOneWidget);
    expect(
      find.descendant(of: _banner, matching: find.text('되살리기')),
      findsOneWidget,
    );
    expect(_executes(h), isEmpty);

    await tester.tap(find.byKey(TextDraftBanner.restoreKey));
    await _settle(tester);

    expect(_executes(h), ['executeAsync:add-objects']);
    expect(h.session.history.undoDepth, 1);
    final objects = _objects(h, 0);
    expect(objects, hasLength(2));
    final original = objects.firstWhere((o) => o.id == 'box-1');
    expect((original as core.TextBoxObject).text, '원본');
    final restored = objects.firstWhere((o) => o.id != 'box-1');
    expect(restored, isA<core.TextBoxObject>());
    expect((restored as core.TextBoxObject).text, _written);
    expect(restored.pageId, h.pageId(0));
    expect(restored.frame, original.frame);
    expect(await _key(h), isEmpty);
    expect(_banner, findsNothing);

    // One step: undo takes the restored box away, the original stays.
    await h.session.undo();
    await tester.pump();
    expect([for (final o in _objects(h, 0)) o.id], ['box-1']);
  });

  testWidgets('버리기 → the key removed, no command, the banner goes', (
    tester,
  ) async {
    final h = await _open(tester, draft: _edited);
    await tester.pump();
    expect(_banner, findsOneWidget);
    await tester.tap(find.byKey(TextDraftBanner.discardKey));
    await _settle(tester);
    expect(_banner, findsNothing);
    expect(await _key(h), isEmpty);
    expect(_executes(h), isEmpty);
    expect([for (final o in _objects(h, 0)) o.id], ['box-1']);
  });

  testWidgets("another note's draft → no banner, the key left as it is", (
    tester,
  ) async {
    final h = await _open(
      tester,
      draft: (noteId, page0) => TextDraft(
        noteId: 'other-note',
        pageId: 'other-page',
        boxId: 'box-9',
        isNew: true,
        draft: _box(id: 'box-9', pageId: 'other-page', text: '다른 노트'),
      ),
    );
    await tester.pump();
    expect(_banner, findsNothing);
    expect((await _key(h))['noteId'], 'other-note');
  });

  testWidgets('an unreadable value → no banner', (tester) async {
    await _open(tester, draft: _edited, rawDraft: const {'v': 1, 'noteId': 3});
    await tester.pump();
    expect(_banner, findsNothing);
  });

  testWidgets("the draft's page is gone → restored on the current page "
      '(a new box draft gets a new id too)', (tester) async {
    final h = await _open(
      tester,
      pages: 2,
      draft: (noteId, page0) => TextDraft(
        noteId: noteId,
        pageId: 'deleted-page',
        boxId: 'new-box',
        isNew: true,
        draft: _box(id: 'new-box', pageId: 'deleted-page', text: _written),
      ),
    );
    await tester.pump();
    expect(h.viewport.currentPageIndex.value, 0);
    await tester.tap(find.byKey(TextDraftBanner.restoreKey));
    await _settle(tester);
    expect(_executes(h), ['executeAsync:add-objects']);
    final restored = _objects(h, 0).where((o) => o.id != 'box-1').single;
    expect(restored.id, isNot('new-box'));
    expect(restored.pageId, h.pageId(0));
    expect((restored as core.TextBoxObject).text, _written);
    expect(await _key(h), isEmpty);
  });

  testWidgets('a read-only note → 되살리기 disabled, 버리기 still removes the '
      'key', (tester) async {
    final h = await _open(tester, draft: _edited, trash: true);
    await tester.pump();
    expect(_banner, findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(TextDraftBanner.restoreKey))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(TextDraftBanner.discardKey));
    await _settle(tester);
    expect(await _key(h), isEmpty);
    expect(_executes(h), isEmpty);
  });
}
