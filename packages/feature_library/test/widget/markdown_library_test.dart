// (v2.17-md, C217M-11, m5-7/08-markdown 9, MD-T10) MD 문서 in the library: the new menu's
// '새 MD 문서' (name dialog → create → open in edit mode) and 'MD 가져오기' (slot, one call
// at a time, a returned id opens it), the MD card (preview text + 'MD' mark, updated after
// an edit), opening a card → onOpenMarkdown, the ⋯ menu (no cover, no PDF, '.md로
// 내보내기'), the content search row of an MD body → onOpenMarkdown with the query, and the
// bulk PDF export leaving MD 문서 out.
import 'dart:async';

import 'package:feature_library/feature_library.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/ui/content/note_cover_view.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
import 'package:feature_library/src/ui/dialogs/new_markdown_dialog.dart';
import 'package:feature_library/src/ui/top_bar/library_search_field.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/fake_library_backend.dart';
import '../support/library_test_harness.dart';

Finder menuItem(String label) => find.widgetWithText(MenuItemButton, label);

final Finder searchInput = find.descendant(
  of: find.byType(LibrarySearchField),
  matching: find.byType(TextField),
);

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<LibraryTestHarness> pumpAt(
    WidgetTester tester, {
    String? folderId,
    List<Override> overrides = const [],
  }) async {
    final h = LibraryTestHarness(backend, extraOverrides: overrides);
    await h.pump(tester, folderId: folderId);
    await tester.pumpAndSettle();
    return h;
  }

  Future<void> openNewMenu(WidgetTester tester) async {
    await tester.tap(find.text(LibraryStrings.newMenu));
    await tester.pumpAndSettle();
  }

  Future<Note> createMd(WidgetTester tester, String title, String text) => real(
    tester,
    () => backend.store.markdown.create(title: title, text: text),
  );

  testWidgets('새 MD 문서: unique default name → create → open in edit mode', (
    tester,
  ) async {
    await createMd(tester, LibraryStrings.defaultMarkdownTitle, '');
    final h = await pumpAt(tester);
    await openNewMenu(tester);
    expect(find.byKey(const Key('library.new.markdown')), findsOneWidget);
    // No import slot: no 'MD 가져오기'.
    expect(find.byKey(const Key('library.new.importMarkdown')), findsNothing);
    await tester.tap(find.byKey(const Key('library.new.markdown')));
    await tester.pumpAndSettle();
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(NewMarkdownDialog.titleFieldKey),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.controller.text, '${LibraryStrings.defaultMarkdownTitle} 2');
    await tester.enterText(
      find.descendant(
        of: find.byKey(NewMarkdownDialog.titleFieldKey),
        matching: find.byType(EditableText),
      ),
      '수업 정리',
    );
    await tester.tap(find.text(LibraryStrings.create));
    await tester.pumpAndSettle();
    final notes = (await real(
      tester,
      () => backend.store.library.watchListing(const LibraryQuery()).first,
    )).notes;
    final created = notes.singleWhere((n) => n.title == '수업 정리');
    expect(created.isMarkdown, isTrue);
    expect(h.log.entries.last, 'md:${created.id} edit');
  });

  testWidgets('MD 가져오기: the slot gets the folder; a returned id opens it; '
      'disabled while it runs', (tester) async {
    final folder = await real(
      tester,
      () => backend.store.library.createFolder(name: '수업'),
    );
    final imported = await createMd(tester, '가져온 문서', '# 제목');
    final gate = Completer<String?>();
    final calls = <String?>[];
    final h = await pumpAt(
      tester,
      folderId: folder.id,
      overrides: [
        libraryMarkdownImportActionProvider.overrideWithValue((
          context, {
          folderId,
        }) {
          calls.add(folderId);
          return gate.future;
        }),
      ],
    );
    await openNewMenu(tester);
    await tester.tap(find.byKey(const Key('library.new.importMarkdown')));
    await tester.pump();
    expect(calls, [folder.id]);
    await openNewMenu(tester);
    final item = tester.widget<MenuItemButton>(
      find.byKey(const Key('library.new.importMarkdown')),
    );
    expect(item.onPressed, isNull, reason: 'one import at a time');
    gate.complete(imported.id);
    await tester.pumpAndSettle();
    expect(h.log.entries.last, 'md:${imported.id}');
  });

  testWidgets('the MD card: preview text + MD mark, no thumbnail; it follows '
      'an edit; a tap opens it with onOpenMarkdown', (tester) async {
    final note = await createMd(tester, '회의', '# 회의 메모\n\n- 첫 안건');
    final h = await pumpAt(tester);
    final card = find.descendant(
      of: find.widgetWithText(NoteTile, '회의'),
      matching: find.byType(MarkdownCoverCard),
    );
    expect(card, findsOneWidget);
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(MarkdownCoverCard.badgeKey),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('회의 메모', findRichText: true),
      ),
      findsOneWidget,
    );
    backend.clock.advance(const Duration(minutes: 1));
    final doc = (await real(
      tester,
      () => backend.store.markdown.get(note.id),
    ))!;
    await real(
      tester,
      () => backend.store.markdown.saveText(
        note.id,
        '# 바뀐 제목\n',
        baseVersion: doc.textVersion,
      ),
    );
    await tester.pumpAndSettle();
    await real(tester, () => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('바뀐 제목', findRichText: true),
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(NoteTile, '회의'));
    await tester.pumpAndSettle();
    expect(h.log.entries.last, 'md:${note.id}');
  });

  testWidgets('an empty MD card shows the MD 문서 mark, not a blank page '
      '(owner review)', (tester) async {
    await createMd(tester, '빈 문서', '');
    await createMd(tester, '글 있음', '본문');
    await pumpAt(tester);
    await real(tester, () => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    Finder mark(String title) => find.descendant(
      of: find.descendant(
        of: find.widgetWithText(NoteTile, title),
        matching: find.byType(MarkdownCoverCard),
      ),
      matching: find.byWidgetPredicate(
        (w) =>
            w is AppIcon && w.kind == AppIconKind.markdownDoc && w.size == 40,
      ),
    );
    expect(mark('빈 문서'), findsOneWidget);
    expect(mark('글 있음'), findsNothing);
  });

  testWidgets('without onOpenMarkdown an MD card goes through onOpenNote', (
    tester,
  ) async {
    final note = await createMd(tester, '문서', 'x');
    final h = LibraryTestHarness(backend, withOpenMarkdown: false);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NoteTile, '문서'));
    await tester.pumpAndSettle();
    expect(h.log.entries.last, 'note:${note.id}');
  });

  testWidgets('⋯ of an MD 문서: no 표지 변경, no PDF로 내보내기; .md로 내보내기 runs '
      'the slot with its id', (tester) async {
    final note = await createMd(tester, '문서', 'x');
    final exported = <String>[];
    await pumpAt(
      tester,
      overrides: [
        libraryPdfExportActionProvider.overrideWithValue((c, ids) async {}),
        libraryMarkdownExportActionProvider.overrideWithValue((c, id) async {
          exported.add(id);
        }),
      ],
    );
    await tester.tap(find.byTooltip(LibraryStrings.itemMenu('문서')));
    await tester.pumpAndSettle();
    expect(menuItem(LibraryStrings.changeCover), findsNothing);
    expect(menuItem(LibraryStrings.exportPdfOne), findsNothing);
    expect(menuItem(LibraryStrings.rename), findsOneWidget);
    await tester.tap(find.byKey(const Key('library.menu.exportMarkdown')));
    await tester.pumpAndSettle();
    expect(exported, [note.id]);
  });

  testWidgets('the content search finds an MD body: a 문서 row that opens the '
      'document with the query', (tester) async {
    final note = await createMd(tester, '강의', '# 미분\n\n접선의 기울기를 구한다');
    final h = await pumpAt(tester);
    await tester.enterText(searchInput, '기울기');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final row = find.byKey(ValueKey('library.hit.markdown.${note.id}'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(
        of: row,
        matching: find.text(LibraryStrings.markdownKind),
      ),
      findsNWidgets(2), // the source badge and the place ('문서', not 'n쪽')
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(h.log.entries.last, 'md:${note.id} q=기울기');
  });

  test('size labels', () {
    expect(LibraryStrings.markdownSize(820), '820 B');
    expect(LibraryStrings.markdownSize(2100), '2.1 KB');
    expect(LibraryStrings.markdownSize(1300000), '1.3 MB');
    expect(LibraryStrings.markdownListMeta('어제', 2100), '어제 · 문서 · 2.1 KB');
    expect(LibraryStrings.markdownListMeta('어제', null), '어제 · 문서');
  });
}
