// New note dialog (05-library 6.12, 8 L12): default name '제목 없는 노트 2',
// empty title → default name, size (PageSizePreset) / orientation / the 7
// template cells / the 4 paper colors / the cover reach createNote (read
// back from CORE as PageDraft.size and background), 16:9 → landscape
// (960×540), custom 35.2 mm → error + [만들기] disabled, 35.3 mm → accepted,
// afterwards onOpenNote only.
import 'package:feature_library/src/appearance/cover_palette.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/new_note_spec.dart';
import 'package:feature_library/src/model/page_size_mm.dart';
import 'package:feature_library/src/settings/library_settings_keys.dart';
import 'package:feature_library/src/ui/dialogs/new_note_dialog.dart';
import 'package:feature_library/src/ui/pickers/template_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Page;
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<LibraryTestHarness> pumpAt(
    WidgetTester tester, {
    FolderId? folderId,
    Size size = TestSizes.ipad13Landscape,
  }) async {
    final h = LibraryTestHarness(backend, size: size);
    await h.pump(tester, folderId: folderId);
    await tester.pumpAndSettle();
    return h;
  }

  /// 새로 만들기 › 새 노트 (v2.14-ui: the grid's 새 노트 tile is gone), or
  /// the empty state's [새 노트].
  Future<void> openDialog(WidgetTester tester) async {
    final empty = find.widgetWithText(FilledButton, LibraryStrings.newNote);
    if (empty.evaluate().isNotEmpty) {
      await tester.tap(empty);
    } else {
      await tester.tap(find.text(LibraryStrings.newMenu));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MenuItemButton, LibraryStrings.newNote),
      );
    }
    await tester.pumpAndSettle();
    expect(find.byType(NewNoteDialog), findsOneWidget);
  }

  Finder createButton() =>
      find.widgetWithText(FilledButton, LibraryStrings.create);

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// [만들기], then the created note and its first page, read from CORE.
  Future<(Note, Page)> create(WidgetTester tester, LibraryTestHarness h) async {
    await tapVisible(tester, createButton());
    expect(find.byType(NewNoteDialog), findsNothing);
    final id = h.log.entries.last.substring('note:'.length);
    final note = (await real(tester, () => backend.store.library.getNote(id)))!;
    final pages = await real(tester, () => backend.store.content.pagesOf(id));
    expect(pages, hasLength(1));
    return (note, pages.single);
  }

  TextField titleField(WidgetTester tester) => tester.widget<TextField>(
    find.widgetWithText(TextField, LibraryStrings.fieldTitle),
  );

  testWidgets('default title is unique in the folder and fully selected', (
    tester,
  ) async {
    final math = await real(tester, () => backend.seedFolder('수학'));
    await real(
      tester,
      () =>
          backend.seedNote(LibraryStrings.defaultNoteTitle, folderId: math.id),
    );
    final h = await pumpAt(tester, folderId: math.id);
    await openDialog(tester);
    final controller = titleField(tester).controller!;
    expect(controller.text, '제목 없는 노트 2');
    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, '제목 없는 노트 2'.length);
    // Location: the folder section's folder.
    expect(find.text('홈 › 수학'), findsOneWidget);

    final (note, page) = await create(tester, h);
    expect(note.title, '제목 없는 노트 2');
    expect(note.folderId, math.id);
    expect(note.cover, const FirstPageCover());
    // The defaults: A4 portrait, lined, white.
    expect(page.size, PageSize.a4Portrait);
    expect(page.background, const NewNoteOptions().background);
    expect(backend.calls, [
      "createNote f:${math.id} '제목 없는 노트 2' pages:1 cover:firstPage",
    ]);
  });

  testWidgets('an empty title uses the default name; a typed one is trimmed', (
    tester,
  ) async {
    final h = await pumpAt(tester);
    await openDialog(tester);
    await tester.enterText(
      find.widgetWithText(TextField, LibraryStrings.fieldTitle),
      '   ',
    );
    var (note, _) = await create(tester, h);
    expect(note.title, LibraryStrings.defaultNoteTitle);

    await openDialog(tester);
    expect(titleField(tester).controller!.text, '제목 없는 노트 2');
    await tester.enterText(
      find.widgetWithText(TextField, LibraryStrings.fieldTitle),
      '  미적분 정리  ',
    );
    (note, _) = await create(tester, h);
    expect(note.title, '미적분 정리');
  });

  testWidgets('size, orientation, template, paper and cover reach CORE', (
    tester,
  ) async {
    final h = await pumpAt(tester);
    await openDialog(tester);
    await tapVisible(tester, find.text(LibraryStrings.pageSizeLetter));
    await tapVisible(tester, find.text(LibraryStrings.landscape));
    await tapVisible(
      tester,
      find.text(LibraryStrings.templateName(PageTemplateKind.grid)),
    );
    await tapVisible(
      tester,
      find.byTooltip(LibraryStrings.paperColorName(PaperColors.ivory)),
    );
    await tapVisible(tester, find.byTooltip(CoverPalette.names[0]));
    final (note, page) = await create(tester, h);
    expect(page.size, PageSize.letterPortrait.landscape);
    expect(page.size.width, 792);
    expect(page.size.height, 612);
    expect(
      page.background,
      TemplateBackground(
        template: PageTemplate.defaults(PageTemplateKind.grid),
        paperColorArgb: PaperColors.ivory,
      ),
    );
    expect(note.cover, ColorCover(CoverPalette.colors[0]));
    expect(backend.calls.single, endsWith('cover:color:0xFF2F4A7A'));
  });

  testWidgets('each of the 7 template cells and 4 paper colors', (
    tester,
  ) async {
    final h = await pumpAt(tester);
    final choices = TemplatePicker.choices;
    expect(choices, hasLength(7));
    for (var i = 0; i < choices.length; i++) {
      final kind = choices[i];
      final paper = PaperColors.all[i % PaperColors.all.length];
      await openDialog(tester);
      await tapVisible(tester, find.text(LibraryStrings.templateName(kind)));
      await tapVisible(
        tester,
        find.byTooltip(LibraryStrings.paperColorName(paper)),
      );
      final (_, page) = await create(tester, h);
      expect(
        page.background,
        kind == null
            ? BlankBackground(paperColorArgb: paper)
            : TemplateBackground(
                template: PageTemplate.defaults(kind),
                paperColorArgb: paper,
              ),
        reason: '$kind on $paper',
      );
    }
  });

  testWidgets('16:9 switches to landscape (960×540); portrait stays possible', (
    tester,
  ) async {
    final h = await pumpAt(tester);
    await openDialog(tester);
    await tapVisible(tester, find.text(LibraryStrings.pageSize16x9));
    var (_, page) = await create(tester, h);
    expect(page.size.width, 960);
    expect(page.size.height, 540);
    expect(PageSizePreset.match(page.size), PageSizePreset.widescreen16x9);

    await openDialog(tester);
    await tapVisible(tester, find.text(LibraryStrings.pageSize16x9));
    await tapVisible(tester, find.text(LibraryStrings.portrait));
    (_, page) = await create(tester, h);
    expect(page.size, const PageSize(540, 960));
  });

  testWidgets('custom size: 35.2 mm → error and no [만들기]; 35.3 mm → made', (
    tester,
  ) async {
    final h = await pumpAt(tester);
    await openDialog(tester);
    await tapVisible(tester, find.text(LibraryStrings.pageSizeCustom));
    final width = find.widgetWithText(TextField, LibraryStrings.customWidth);
    final height = find.widgetWithText(TextField, LibraryStrings.customHeight);
    // Starts from the size chosen so far (A4 portrait) in mm.
    expect(tester.widget<TextField>(width).controller!.text, '210.0');
    expect(tester.widget<TextField>(height).controller!.text, '297.0');
    // A custom size has no orientation.
    final orientation = tester.widget<SegmentedButton<PageOrientationChoice>>(
      find.byType(SegmentedButton<PageOrientationChoice>),
    );
    expect(orientation.onSelectionChanged, isNull);

    final rangeError = find.text(
      LibraryStrings.customSizeRange(
        PageSizeMm.minInputMm,
        PageSizeMm.maxInputMm,
      ),
    );
    expect(rangeError, findsNothing);
    await tester.enterText(width, '35.2');
    await tester.pump();
    expect(find.text('35.3~1058.3mm 사이로 입력하세요'), findsOneWidget);
    expect(tester.widget<FilledButton>(createButton()).onPressed, isNull);
    // Not a number → the same message.
    await tester.enterText(width, '');
    await tester.pump();
    expect(rangeError, findsOneWidget);
    expect(tester.widget<FilledButton>(createButton()).onPressed, isNull);
    // Above the range (1058.4 mm = 3000.2 pt).
    await tester.enterText(width, '1058.4');
    await tester.pump();
    expect(rangeError, findsOneWidget);

    await tester.enterText(width, '35.3');
    await tester.pump();
    expect(rangeError, findsNothing);
    expect(tester.widget<FilledButton>(createButton()).onPressed, isNotNull);
    final (_, page) = await create(tester, h);
    expect(page.size.width, closeTo(PageSizeMm.toPt(35.3), 1e-9));
    expect(page.size.width, closeTo(100.06, 0.01));
    expect(page.size.height, closeTo(841.89, 0.01));
    expect(PageSizePreset.match(page.size), isNull);
  });

  testWidgets('switching back to a preset after an invalid custom size', (
    tester,
  ) async {
    await pumpAt(tester);
    await openDialog(tester);
    await tapVisible(tester, find.text(LibraryStrings.pageSizeCustom));
    await tester.enterText(
      find.widgetWithText(TextField, LibraryStrings.customWidth),
      '10',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(createButton()).onPressed, isNull);
    await tapVisible(tester, find.text(LibraryStrings.pageSizeA4));
    expect(
      find.widgetWithText(TextField, LibraryStrings.customWidth),
      findsNothing,
    );
    expect(tester.widget<FilledButton>(createButton()).onPressed, isNotNull);
  });

  testWidgets('afterwards only onOpenNote — no markOpened (N-6)', (
    tester,
  ) async {
    final h = await pumpAt(tester);
    await openDialog(tester);
    final (note, _) = await create(tester, h);
    expect(h.log.entries, ['note:${note.id}']);
    expect(backend.calls.where((c) => c.startsWith('markOpened')), isEmpty);
    expect(note.lastOpenedAt, isNull);
  });

  testWidgets('[취소] creates nothing', (tester) async {
    final h = await pumpAt(tester);
    await openDialog(tester);
    await tester.tap(find.text(LibraryStrings.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(NewNoteDialog), findsNothing);
    expect(backend.calls, isEmpty);
    expect(h.log.entries, isEmpty);
  });

  testWidgets('starts from the saved new note defaults', (tester) async {
    const saved = NewNoteOptions(
      preset: PageSizePreset.letter,
      orientation: PageOrientationChoice.landscape,
      template: PageTemplateKind.dotted,
      paperColorArgb: PaperColors.gray,
    );
    await real(
      tester,
      () => backend.store.settings.set(
        LibrarySettingsKeys.newNoteDefaults,
        saved.toJson(),
      ),
    );
    final h = await pumpAt(tester);
    await openDialog(tester);
    final (_, page) = await create(tester, h);
    expect(page.size, saved.pageSize);
    expect(page.background, saved.background);
  });

  testWidgets('top bar 새로 만들기 › 새 노트 in 최근 → a note at 홈', (tester) async {
    final math = await real(tester, () => backend.seedFolder('수학'));
    final h = await pumpAt(tester, folderId: math.id);
    await tester.tap(find.text(LibraryStrings.recent));
    await tester.pumpAndSettle();
    await tester.tap(find.text(LibraryStrings.newMenu));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, LibraryStrings.newNote),
    );
    await tester.pumpAndSettle();
    expect(find.text(LibraryStrings.home), findsWidgets);
    final (note, _) = await create(tester, h);
    expect(note.folderId, isNull);
  });

  for (final size in [TestSizes.ipad13Portrait, TestSizes.compact]) {
    testWidgets('the dialog lays out at $size (custom size shown)', (
      tester,
    ) async {
      await pumpAt(tester, size: size);
      if (size == TestSizes.compact) {
        await tester.tap(find.byTooltip(LibraryStrings.newMenu));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(MenuItemButton, LibraryStrings.newNote),
        );
        await tester.pumpAndSettle();
      } else {
        await openDialog(tester);
      }
      await tapVisible(tester, find.text(LibraryStrings.pageSizeCustom));
      await tester.enterText(
        find.widgetWithText(TextField, LibraryStrings.customWidth),
        '1',
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(NewNoteDialog), findsOneWidget);
    });
  }
}
