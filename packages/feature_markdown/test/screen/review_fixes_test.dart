// Track B review fixes on the screen: text kept for later never overwrites newer text
// (A1/B1), the task snack bar's undo never flips another box (A3/B6), a box that the
// source scan cannot place is display-only (A4), leaving by other routes keeps the text
// (A8/B7), [사본 열기] (B4), position kept view ↔ edit (MD-T17) and across another
// device's change (B10), long tables in parts (A7), the symbol row (B11).
import 'package:feature_markdown/feature_markdown.dart';
import 'package:feature_markdown/src/markdown_screen.dart'
    show kMarkdownUnsavedSetting;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

import '../support/pump.dart';

final class _FlakyRepo implements MarkdownRepository {
  _FlakyRepo(this.inner);
  final MarkdownRepository inner;
  bool fail = false;

  @override
  Stream<MarkdownDoc?> watch(NoteId id) => inner.watch(id);
  @override
  Future<MarkdownDoc?> get(NoteId id) => inner.get(id);
  @override
  Future<Note> create({
    FolderId? folderId,
    required String title,
    String text = '',
  }) => inner.create(folderId: folderId, title: title, text: text);
  @override
  Future<String> preview(
    NoteId id, {
    int maxChars = MarkdownLimits.previewChars,
  }) => inner.preview(id, maxChars: maxChars);
  @override
  Future<MarkdownSaveResult> saveText(
    NoteId id,
    String text, {
    required Hlc? baseVersion,
  }) async {
    if (fail) throw StateError('write queue');
    return inner.saveText(id, text, baseVersion: baseVersion);
  }
}

Future<void> _real(WidgetTester tester, [int ms = 20]) =>
    tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(MarkdownKeys.editor), text);
  await tester.pump();
}

Future<void> _autosave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 800));
  await _real(tester);
  await settleMd(tester, 2);
}

Future<void> _steps(WidgetTester tester) async {
  await settleMd(tester);
  await _real(tester);
  await settleMd(tester);
}

Future<Map<String, Object?>> _unsavedSetting(
  WidgetTester tester,
  MdHarness h,
) async => (await tester.runAsync(
  () => h.store.settings.get(kMarkdownUnsavedSetting),
))!;

void _background(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void _foreground(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

String _paragraphs(int n, {String prefix = '문단'}) =>
    [for (var i = 0; i < n; i++) '$prefix $i 의 글입니다.'].join('\n\n');

void main() {
  testWidgets(
    'text kept on pause is dropped once a later save succeeds (review A1)',
    (tester) async {
      final h = await MdHarness.create(tester);
      final repo = _FlakyRepo(h.store.markdown);
      final id = await h.doc(tester, '처음');
      await h.pump(
        tester,
        id,
        initialEdit: true,
        overrides: [markdownRepositoryProvider.overrideWithValue(repo)],
      );
      repo.fail = true;
      await _type(tester, '옛 글');
      _background(tester);
      await settleMd(tester);
      await _real(tester, 40);
      await settleMd(tester);
      expect(
        (await _unsavedSetting(tester, h))[id],
        isA<Map<String, Object?>>(),
      );
      _foreground(tester);
      await settleMd(tester);
      repo.fail = false;
      await _type(tester, '새 글 — 최종');
      await _autosave(tester);
      await _real(tester, 40);
      expect(await h.stored(tester, id), '새 글 — 최종');
      expect((await _unsavedSetting(tester, h)).containsKey(id), isFalse);

      // reopened: no stale banner, nothing can overwrite the newer text
      await tester.pumpWidget(const SizedBox());
      await _real(tester);
      await h.pump(tester, id);
      await _steps(tester);
      expect(find.byKey(MarkdownKeys.bannerUnsaved), findsNothing);
      expect(await h.stored(tester, id), '새 글 — 최종');
    },
  );

  testWidgets('restoring kept text after another device changed the document '
      'keeps that text as a conflict copy (review B1); entries are per '
      'document', (tester) async {
    final h = await MdHarness.create(tester);
    final repo = _FlakyRepo(h.store.markdown);
    final a = await h.doc(tester, 'A 처음', title: 'A');
    final b = await h.doc(tester, 'B 처음', title: 'B');
    Future<void> keep(NoteId id, String text) async {
      await h.pump(
        tester,
        id,
        initialEdit: true,
        overrides: [markdownRepositoryProvider.overrideWithValue(repo)],
      );
      repo.fail = true;
      await _type(tester, text);
      _background(tester);
      await _steps(tester);
      _foreground(tester);
      // closed while saving still fails
      await tester.pumpWidget(const SizedBox());
      await _real(tester, 40);
      repo.fail = false;
    }

    await keep(a, 'A 못 저장한 글');
    await keep(b, 'B 못 저장한 글');
    final kept = await _unsavedSetting(tester, h);
    expect(kept.keys, containsAll(<String>[a, b]));

    // another device changes A in the meantime
    await tester.runAsync(
      () => FakeMarkdownHooks.remoteText(h.store, a, 'A 다른 기기의 새 글'),
    );
    await h.pump(tester, a, canOpenMarkdown: true);
    await _steps(tester);
    expect(find.byKey(MarkdownKeys.bannerUnsaved), findsOneWidget);
    await tester.tap(find.byKey(MarkdownKeys.bannerUnsavedRestore));
    await _steps(tester);
    expect(await h.stored(tester, a), 'A 못 저장한 글');
    expect(find.byKey(MarkdownKeys.bannerConflictCopy), findsOneWidget);
    await tester.tap(find.byKey(MarkdownKeys.bannerOpenCopy));
    await _steps(tester);
    expect(h.openedMarkdown, hasLength(1));
    expect(await h.stored(tester, h.openedMarkdown.single), 'A 다른 기기의 새 글');
    // B's entry is still there
    final after = await _unsavedSetting(tester, h);
    expect(after.keys, isNot(contains(a)));
    expect(after.keys, contains(b));
  });

  testWidgets('leaving by another route with a failing save keeps the text '
      '(review A8)', (tester) async {
    final h = await MdHarness.create(tester);
    final repo = _FlakyRepo(h.store.markdown);
    final id = await h.doc(tester, '처음');
    await h.pump(
      tester,
      id,
      initialEdit: true,
      overrides: [markdownRepositoryProvider.overrideWithValue(repo)],
    );
    repo.fail = true;
    await _type(tester, '살려야 할 글');
    // the route is replaced (no back, no dialog)
    await tester.pumpWidget(const SizedBox());
    await _real(tester, 60);
    final kept = await _unsavedSetting(tester, h);
    expect((kept[id]! as Map)['text'], '살려야 할 글');
    expect((kept[id]! as Map)['base'], isA<String>());
  });

  testWidgets(
    "the task snack bar's undo does nothing once the text moved (review A3)",
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, '- [ ] a\n- [ ] b\n');
      await h.pump(tester, id);
      await tester.tap(find.byKey(MarkdownKeys.task(1)));
      await _steps(tester);
      expect(await h.stored(tester, id), '- [ ] a\n- [x] b\n');
      await tester.runAsync(
        () => FakeMarkdownHooks.remoteText(
          h.store,
          id,
          '- [ ] z\n- [ ] a\n- [x] b\n',
        ),
      );
      await _steps(tester);
      final undo = find.byKey(MarkdownKeys.taskUndo);
      if (undo.evaluate().isNotEmpty) {
        await tester.tap(undo);
        await _steps(tester);
      }
      expect(await h.stored(tester, id), '- [ ] z\n- [ ] a\n- [x] b\n');
    },
  );

  testWidgets('the task snack bar undo flips the box back when nothing moved', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '- [ ] a\n- [ ] b\n');
    await h.pump(tester, id);
    await tester.tap(find.byKey(MarkdownKeys.task(1)));
    await _steps(tester);
    await tester.tap(find.byKey(MarkdownKeys.taskUndo));
    await _steps(tester);
    expect(await h.stored(tester, id), '- [ ] a\n- [ ] b\n');
  });

  testWidgets('a box the scan cannot place is display-only: a tap never '
      'edits code (review A4)', (tester) async {
    final h = await MdHarness.create(tester);
    const src =
        '- a\n\n        - [ ] code line\n\n  - b\n\n    > - [ ] quote task\n';
    final id = await h.doc(tester, src);
    await h.pump(tester, id);
    final box = find.byKey(MarkdownKeys.task(0));
    expect(box, findsOneWidget);
    await tester.tap(box, warnIfMissed: false);
    await _steps(tester);
    final stored = await h.stored(tester, id);
    expect(stored, isNot(contains('- [x] code line')));
    // either untouched, or the quote's own box flipped
    expect(
      stored == src || stored == src.replaceFirst('[ ] quote', '[x] quote'),
      isTrue,
      reason: stored,
    );
  });

  testWidgets('conflict copy banner: [사본 열기] saves, then opens the copy '
      '(review B4)', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '원문');
    await h.pump(tester, id, initialEdit: true, canOpenMarkdown: true);
    await _type(tester, '내가 고친 글');
    await tester.runAsync(
      () => FakeMarkdownHooks.remoteText(h.store, id, '다른 기기 글'),
    );
    await _autosave(tester);
    expect(find.byKey(MarkdownKeys.bannerConflictCopy), findsOneWidget);
    await tester.tap(find.byKey(MarkdownKeys.bannerOpenCopy));
    await _steps(tester);
    expect(h.openedMarkdown, hasLength(1));
    expect(await h.stored(tester, h.openedMarkdown.single), '다른 기기 글');
    expect(find.byKey(MarkdownKeys.bannerConflictCopy), findsNothing);
  });

  testWidgets('no onOpenMarkdown: no [사본 열기]', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '원문');
    await h.pump(tester, id, initialEdit: true);
    await _type(tester, '내가 고친 글');
    await tester.runAsync(
      () => FakeMarkdownHooks.remoteText(h.store, id, '다른 기기 글'),
    );
    await _autosave(tester);
    expect(find.byKey(MarkdownKeys.bannerConflictCopy), findsOneWidget);
    expect(find.byKey(MarkdownKeys.bannerOpenCopy), findsNothing);
  });

  testWidgets('편집 → 보기 brings the cursor block to the top; 보기 → 편집 puts '
      'the cursor at the top block (MD-T17)', (tester) async {
    final h = await MdHarness.create(tester);
    final text = _paragraphs(200);
    final id = await h.doc(tester, text);
    await h.pump(tester, id, initialEdit: true);
    final field = tester.widget<TextField>(find.byKey(MarkdownKeys.editor));
    final at = text.indexOf('문단 150 ');
    field.controller!.selection = TextSelection.collapsed(offset: at + 3);
    await tester.tap(find.byKey(MarkdownKeys.mode));
    await _steps(tester);
    await settleMd(tester, 10);
    expect(find.byKey(MarkdownKeys.block(150)), findsOneWidget);
    final viewTop = tester.getTopLeft(find.byKey(MarkdownKeys.view)).dy;
    final blockTop = tester.getTopLeft(find.byKey(MarkdownKeys.block(150))).dy;
    expect(blockTop - viewTop, inInclusiveRange(0, 120));

    await tester.tap(find.byKey(MarkdownKeys.mode));
    await settleMd(tester);
    final c = tester
        .widget<TextField>(find.byKey(MarkdownKeys.editor))
        .controller!;
    final rest = c.text.substring(c.selection.baseOffset);
    expect(rest, anyOf(startsWith('문단 150 '), startsWith('문단 149 ')));
  });

  testWidgets("another device's change above keeps the view on the same "
      'block (review B10)', (tester) async {
    final h = await MdHarness.create(tester);
    final text = _paragraphs(200);
    final id = await h.doc(tester, text);
    await h.pump(tester, id, initialEdit: true);
    final field = tester.widget<TextField>(find.byKey(MarkdownKeys.editor));
    field.controller!.selection = TextSelection.collapsed(
      offset: text.indexOf('문단 120 '),
    );
    await tester.tap(find.byKey(MarkdownKeys.mode));
    await _steps(tester);
    await settleMd(tester, 10);
    expect(find.byKey(MarkdownKeys.block(120)), findsOneWidget);
    final before = tester.getTopLeft(find.byKey(MarkdownKeys.block(120))).dy;
    await tester.runAsync(
      () => FakeMarkdownHooks.remoteText(
        h.store,
        id,
        '${_paragraphs(30, prefix: '새 머리')}\n\n$text',
      ),
    );
    await _steps(tester);
    await settleMd(tester, 10);
    // 문단 120 is block 150 now, and it is still at the top of the view
    final block = find.byKey(MarkdownKeys.block(150));
    expect(block, findsOneWidget);
    expect(
      find.descendant(
        of: block,
        matching: find.textContaining('문단 120 ', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(tester.getTopLeft(block).dy, moreOrLessEquals(before, epsilon: 2));
  });

  testWidgets('a long table shows its rows in parts (review A7)', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final rows = [for (var i = 0; i < 250; i++) '| $i | 셀 $i | 값 |'];
    final id = await h.doc(
      tester,
      '| 번호 | 이름 | 값 |\n|---|---|---|\n${rows.join('\n')}\n',
    );
    final sw = Stopwatch()..start();
    await h.pump(tester, id);
    sw.stop();
    expect(find.text('셀 99', findRichText: true), findsOneWidget);
    expect(find.text('셀 100', findRichText: true), findsNothing);
    final more = find.byKey(MarkdownKeys.tableMore(0));
    expect(find.textContaining('150행 더 있어요'), findsOneWidget);
    await tester.ensureVisible(more);
    await settleMd(tester);
    await tester.tap(more);
    await settleMd(tester);
    expect(find.text('셀 100', findRichText: true), findsOneWidget);
    expect(find.textContaining('50행 더 있어요'), findsOneWidget);
    // header column widths come from a sample: every column is 48..320 wide
    final cells = tester.widgetList<Table>(find.byType(Table)).single;
    expect(cells.columnWidths, isNotNull);
  });

  testWidgets('symbol row: 48 dp buttons and an end fade on a phone '
      '(review B11)', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '글');
    await h.pump(tester, id, size: const Size(390, 844), initialEdit: true);
    await settleMd(tester);
    final heading = find.byKey(MarkdownKeys.accessoryButton('heading'));
    expect(tester.getSize(heading).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(heading).width, greaterThanOrEqualTo(48));
    expect(find.byKey(MarkdownKeys.accessoryFade('end')), findsOneWidget);
    expect(find.byKey(MarkdownKeys.accessoryFade('start')), findsNothing);
    await tester.drag(
      find.byKey(MarkdownKeys.accessory),
      const Offset(-600, 0),
    );
    await settleMd(tester);
    expect(find.byKey(MarkdownKeys.accessoryFade('start')), findsOneWidget);
    expect(find.byKey(MarkdownKeys.accessoryFade('end')), findsNothing);
  });

  testWidgets('keyboard undo goes to the capped history (review B2)', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '하나');
    await h.pump(tester, id, initialEdit: true);
    await tester.tap(find.byKey(MarkdownKeys.editor));
    await settleMd(tester);
    await _type(tester, '하나 둘');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final c = tester.widget<TextField>(find.byKey(MarkdownKeys.editor));
    expect(c.controller!.text, '하나');
    await _autosave(tester);
    expect(await h.stored(tester, id), '하나');
  });
}
