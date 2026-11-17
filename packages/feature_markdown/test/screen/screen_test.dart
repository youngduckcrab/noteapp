// B-8 … B-12 / MD-T09 / MD-T14 / MD-T15 / MD-T17 (08-markdown 8.4 … 8.9): modes, autosave
// on the screen, back / leave, banners, menu (rename, export, info), incoming changes,
// search landing on a 2,000-block document, 나란히, lifecycle flush and unsaved text,
// undo / redo, the symbol row.
import 'dart:async';

import 'package:feature_markdown/feature_markdown.dart';
import 'package:feature_markdown/slots.dart';
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

void main() {
  testWidgets('view by default; 편집 / 보기 toggle; typing autosaves', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '# 제목');
    await h.pump(tester, id);
    expect(find.byKey(MarkdownKeys.view), findsOneWidget);
    expect(find.byKey(MarkdownKeys.editor), findsNothing);
    await tester.tap(find.byKey(MarkdownKeys.mode));
    await settleMd(tester);
    expect(find.byKey(MarkdownKeys.editor), findsOneWidget);
    expect(find.byKey(MarkdownKeys.accessory), findsOneWidget);
    await _type(tester, '# 제목\n\n새 문단');
    expect(find.text('저장 중…'), findsOneWidget);
    await _autosave(tester);
    expect(await h.stored(tester, id), '# 제목\n\n새 문단');
    expect(find.text('저장됨'), findsOneWidget);
    await tester.tap(find.byKey(MarkdownKeys.mode));
    await settleMd(tester);
    expect(find.text('새 문단', findRichText: true), findsOneWidget);
  });

  testWidgets('a new document opens in 편집 (initialEdit)', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '');
    await h.pump(tester, id, initialEdit: true);
    expect(find.byKey(MarkdownKeys.editor), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(MarkdownKeys.editor));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.style?.fontFamily, 'monospace');
  });

  testWidgets('[←] and system back: 편집 → 보기 first, then close (saved)', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'a');
    await h.pump(tester, id, initialEdit: true);
    await _type(tester, 'ab');
    await tester.binding.handlePopRoute();
    await settleMd(tester);
    expect(find.byKey(MarkdownKeys.editor), findsNothing);
    expect(h.closed, 0);
    await _real(tester);
    expect(await h.stored(tester, id), 'ab');

    await tester.tap(find.byKey(MarkdownKeys.mode));
    await settleMd(tester);
    await _type(tester, 'abc');
    // [←] follows the same order as system back (08-markdown 8.4).
    await tester.tap(find.byKey(MarkdownKeys.back));
    await settleMd(tester);
    expect(find.byKey(MarkdownKeys.editor), findsNothing);
    expect(h.closed, 0);
    await tester.tap(find.byKey(MarkdownKeys.back));
    await settleMd(tester);
    await _real(tester);
    await settleMd(tester);
    expect(await h.stored(tester, id), 'abc');
    expect(h.closed, 1);
  });

  testWidgets(
    'a failed save: banner + retry; leaving asks (stay / copy / discard)',
    (tester) async {
      final h = await MdHarness.create(tester);
      final repo = _FlakyRepo(h.store.markdown)..fail = true;
      final id = await h.doc(tester, 'a');
      final clip = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clip.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
      await h.pump(
        tester,
        id,
        initialEdit: true,
        overrides: [markdownRepositoryProvider.overrideWithValue(repo)],
      );
      await _type(tester, '잃으면 안 되는 글');
      await _autosave(tester);
      expect(find.byKey(MarkdownKeys.bannerSaveFailed), findsOneWidget);
      expect(find.text('저장하지 못했어요'), findsOneWidget);

      // 편집 → 보기 first (the text stays in the buffer), then leaving asks.
      await tester.tap(find.byKey(MarkdownKeys.back));
      await settleMd(tester);
      await _real(tester);
      await settleMd(tester);
      expect(h.closed, 0);
      await tester.tap(find.byKey(MarkdownKeys.back));
      await settleMd(tester);
      await _real(tester);
      await settleMd(tester);
      expect(find.byKey(MarkdownKeys.leaveDialog), findsOneWidget);
      await tester.tap(find.byKey(MarkdownKeys.leaveStay));
      await settleMd(tester);
      expect(h.closed, 0);
      expect(find.text('잃으면 안 되는 글'), findsOneWidget);

      await tester.tap(find.byKey(MarkdownKeys.back));
      await settleMd(tester);
      await _real(tester);
      await settleMd(tester);
      await tester.tap(find.byKey(MarkdownKeys.leaveCopy));
      await settleMd(tester);
      expect(clip.last, '잃으면 안 되는 글');
      expect(h.closed, 1);

      // retry after the store recovers
      repo.fail = false;
      await tester.pumpWidget(const SizedBox());
      await _real(tester);
      await h.pump(
        tester,
        id,
        initialEdit: true,
        overrides: [markdownRepositoryProvider.overrideWithValue(repo)],
      );
      repo.fail = true;
      await _type(tester, '다시');
      await _autosave(tester);
      expect(find.byKey(MarkdownKeys.bannerRetry), findsOneWidget);
      repo.fail = false;
      await tester.tap(find.byKey(MarkdownKeys.bannerRetry));
      await _real(tester);
      await settleMd(tester);
      expect(find.byKey(MarkdownKeys.bannerSaveFailed), findsNothing);
      expect(await h.stored(tester, id), '다시');

      // discard: [버리고 나가기] really gives the text up — even when the store works
      // again by the time the screen is disposed, nothing more is saved.
      repo.fail = true;
      await _type(tester, '버릴 글');
      await tester.tap(find.byKey(MarkdownKeys.back));
      await settleMd(tester);
      await _real(tester);
      await settleMd(tester);
      await tester.tap(find.byKey(MarkdownKeys.back));
      await settleMd(tester);
      await _real(tester);
      await settleMd(tester);
      await tester.tap(find.byKey(MarkdownKeys.leaveDiscard));
      await settleMd(tester);
      expect(h.closed, 2);
      repo.fail = false;
      await tester.pumpWidget(const SizedBox());
      await _real(tester, 40);
      expect(await h.stored(tester, id), '다시');
    },
  );

  testWidgets('too large to save: its own banner, the text stays', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'a');
    await h.pump(tester, id, initialEdit: true);
    final big =
        '가' * (MarkdownLimits.maxTextBytes ~/ 3 + 10); // > 400 KB in UTF-8
    await _type(tester, big);
    await _autosave(tester);
    expect(find.byKey(MarkdownKeys.bannerTooLarge), findsOneWidget);
    expect(await h.stored(tester, id), 'a');
  });

  testWidgets(
    'read-only banners: receiving (editing blocked), too large to edit',
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, '본문');
      await tester.runAsync(() => FakeMarkdownHooks.removeBody(h.store, id));
      await h.pump(tester, id, initialEdit: true);
      expect(find.byKey(MarkdownKeys.bannerReceiving), findsOneWidget);
      expect(find.text('내용을 받는 중이에요 — 다 받을 때까지 고칠 수 없어요'), findsOneWidget);
      expect(find.byKey(MarkdownKeys.editor), findsNothing);
      await tester.pump(const Duration(minutes: 2, seconds: 1));
      expect(
        find.text('아직 내용을 받지 못했어요 — 다른 기기에서 이 문서를 한 번 열어 주세요'),
        findsOneWidget,
      );
      await tester.runAsync(
        () => FakeMarkdownHooks.remoteText(h.store, id, '# 도착'),
      );
      await settleMd(tester);
      expect(find.byKey(MarkdownKeys.bannerReceiving), findsNothing);
      expect(find.text('도착', findRichText: true), findsOneWidget);

      final big = await h.doc(tester, List.filled(3000, 'a' * 50).join('\n\n'));
      await h.pump(tester, big);
      expect(find.byKey(MarkdownKeys.bannerTooLargeToEdit), findsOneWidget);
    },
  );

  testWidgets(
    "another device's text: shown when clean; conflict copy banner when dirty",
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, '원래 글');
      await h.pump(tester, id);
      await tester.runAsync(
        () => FakeMarkdownHooks.remoteText(h.store, id, '바뀐 글'),
      );
      await settleMd(tester);
      expect(find.text('바뀐 글', findRichText: true), findsOneWidget);

      await tester.tap(find.byKey(MarkdownKeys.mode));
      await settleMd(tester);
      await _type(tester, '내 글');
      await tester.runAsync(
        () => FakeMarkdownHooks.remoteText(h.store, id, '또 다른 글'),
      );
      await settleMd(tester);
      expect(find.text('내 글'), findsOneWidget);
      await _autosave(tester);
      expect(find.byKey(MarkdownKeys.bannerConflictCopy), findsOneWidget);
      expect(await h.stored(tester, id), '내 글');
      await tester.tap(find.byKey(MarkdownKeys.bannerDismiss));
      await settleMd(tester);
      expect(find.byKey(MarkdownKeys.bannerConflictCopy), findsNothing);
    },
  );

  testWidgets('menu: rename (also by the title), export with the slot, info', (
    tester,
  ) async {
    final exported = <(String, String)>[];
    final h = await MdHarness.create(tester);
    const raw = '﻿# 가\r\n본문\r\n';
    final id = await h.doc(tester, raw, title: '처음 이름');
    await h.pump(
      tester,
      id,
      overrides: [
        markdownExportActionProvider.overrideWithValue((
          context, {
          required title,
          required text,
        }) async {
          exported.add((title, text));
        }),
      ],
    );
    await tester.tap(find.byKey(MarkdownKeys.title));
    await settleMd(tester);
    await tester.enterText(find.byKey(MarkdownKeys.renameField), '새 이름');
    await tester.tap(find.byKey(MarkdownKeys.renameOk));
    await settleMd(tester);
    await _real(tester);
    await settleMd(tester);
    expect(find.text('새 이름'), findsOneWidget);

    await tester.tap(find.byKey(MarkdownKeys.more));
    await settleMd(tester);
    expect(find.byKey(MarkdownKeys.menuExport), findsOneWidget);
    await tester.tap(find.byKey(MarkdownKeys.menuExport));
    await settleMd(tester);
    await _real(tester);
    expect(exported, [('새 이름', raw)]);

    await tester.tap(find.byKey(MarkdownKeys.more));
    await settleMd(tester);
    await tester.tap(find.byKey(MarkdownKeys.menuInfo));
    await settleMd(tester);
    expect(find.text('문서 정보'), findsOneWidget);
    expect(find.text('7자'), findsOneWidget); // '# 가\n본문\n'
    expect(find.textContaining('바이트'), findsOneWidget);
  });

  testWidgets('no export slot: no export item', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'x');
    await h.pump(tester, id);
    await tester.tap(find.byKey(MarkdownKeys.more));
    await settleMd(tester);
    expect(find.byKey(MarkdownKeys.menuExport), findsNothing);
    expect(find.byKey(MarkdownKeys.menuRename), findsOneWidget);
  });

  testWidgets('not an MD 문서: message and [노트로 열기]', (tester) async {
    final h = await MdHarness.create(tester);
    final ink = (await tester.runAsync(
      () => h.store.library.createNote(title: '필기'),
    ))!;
    await h.pump(tester, ink.id);
    expect(find.byKey(MarkdownKeys.notMarkdown), findsOneWidget);
    await tester.tap(find.byKey(MarkdownKeys.openAsNote));
    expect(h.openedAsNote, 1);
  });

  testWidgets(
    'search landing: 2,000 blocks, scrolls to the match and highlights it',
    (tester) async {
      final h = await MdHarness.create(tester);
      final text = [
        for (var i = 0; i < 2000; i++)
          i == 1503 ? '- 목록 안의 **찾을말** 하나' : '문단 번호 $i 의 글입니다.',
      ].join('\n\n');
      final id = await h.doc(tester, text);
      await h.pump(tester, id, query: '찾을 말', settle: false);
      await settleMd(tester, 4);
      // 'SearchText.normalize' folds the space? No: '찾을 말' does not match '찾을말'.
      expect(find.byKey(MarkdownKeys.highlight), findsNothing);

      await h.pump(tester, id, query: '찾을말', settle: false);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(MarkdownKeys.highlight), findsOneWidget);
      expect(find.byKey(MarkdownKeys.block(1503)), findsOneWidget);
      final rect = tester.getRect(find.byKey(MarkdownKeys.highlight));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(834));
      await tester.pump(const Duration(seconds: 3));
      await settleMd(tester);
      expect(find.byKey(MarkdownKeys.highlight), findsNothing);
    },
  );

  testWidgets('search landing inside a table and a code fence', (tester) async {
    final h = await MdHarness.create(tester);
    final text = [
      for (var i = 0; i < 300; i++) '문단 $i',
      '| a | b |\n|---|---|\n| 표안의낱말 | 2 |',
      for (var i = 0; i < 300; i++) '뒤 문단 $i',
      '```\n코드안의낱말\n```',
    ].join('\n\n');
    final id = await h.doc(tester, text);
    for (final (q, block) in [('표안의낱말', 300), ('코드안의낱말', 601)]) {
      await h.pump(tester, id, query: q, settle: false);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(MarkdownKeys.highlight), findsOneWidget, reason: q);
      expect(find.byKey(MarkdownKeys.block(block)), findsOneWidget, reason: q);
    }
  });

  testWidgets('나란히 on a wide landscape tablet; remembered; off returns to 편집', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '# 하나');
    await h.pump(tester, id, size: const Size(1194, 834), initialEdit: true);
    expect(find.byKey(MarkdownKeys.split), findsOneWidget);
    await tester.tap(find.byKey(MarkdownKeys.split));
    await settleMd(tester);
    expect(find.byKey(MarkdownKeys.editor), findsOneWidget);
    expect(find.byKey(MarkdownKeys.splitPreview), findsOneWidget);
    await _type(tester, '# 하나\n\n둘째 문단');
    await tester.pump(const Duration(milliseconds: 250));
    await settleMd(tester);
    expect(find.text('둘째 문단', findRichText: true), findsOneWidget);
    expect(
      await tester.runAsync(
        () => h.store.settings.get(
          SettingKey.boolean(
            'markdown.splitView',
            false,
            scope: SettingScope.device,
          ),
        ),
      ),
      isTrue,
    );
    await tester.tap(find.byKey(MarkdownKeys.mode));
    await settleMd(tester);
    expect(find.byKey(MarkdownKeys.splitPreview), findsNothing);
    expect(find.byKey(MarkdownKeys.editor), findsOneWidget);

    // portrait: no 나란히
    await h.pump(tester, id, size: const Size(834, 1194), initialEdit: true);
    expect(find.byKey(MarkdownKeys.split), findsNothing);
  });

  testWidgets(
    'app paused: saves and flushes; a failed save keeps the text for next time',
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
      await _type(tester, '중간');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await settleMd(tester);
      await _real(tester);
      expect(await h.stored(tester, id), '중간');

      repo.fail = true;
      await _type(tester, '살려야 할 글');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settleMd(tester);
      await _real(tester, 40);
      await settleMd(tester);
      for (final s in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await settleMd(tester);

      // closed while the store still fails (the last flush fails too), opened again
      await tester.pumpWidget(const SizedBox());
      await _real(tester);
      repo.fail = false;
      expect(await h.stored(tester, id), '중간');
      await h.pump(tester, id);
      await _real(tester);
      await settleMd(tester);
      expect(find.byKey(MarkdownKeys.bannerUnsaved), findsOneWidget);
      await tester.tap(find.byKey(MarkdownKeys.bannerUnsavedRestore));
      await settleMd(tester);
      await _real(tester);
      await settleMd(tester);
      expect(await h.stored(tester, id), '살려야 할 글');
      expect(find.byKey(MarkdownKeys.bannerUnsaved), findsNothing);
    },
  );

  testWidgets('undo / redo buttons and the symbol row', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '제목');
    await h.pump(tester, id, initialEdit: true);
    await tester.tap(find.byKey(MarkdownKeys.editor));
    await settleMd(tester);
    // put the cursor at the end, then '#' goes to the start of the line
    final field = tester.widget<TextField>(find.byKey(MarkdownKeys.editor));
    field.controller!.selection = const TextSelection.collapsed(offset: 2);
    await tester.tap(find.byKey(MarkdownKeys.accessoryButton('heading')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(field.controller!.text, '# 제목');
    await tester.tap(find.byKey(MarkdownKeys.accessoryButton('indent')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(field.controller!.text, '  # 제목');
    await tester.tap(find.byKey(MarkdownKeys.undo));
    await tester.pump();
    expect(field.controller!.text, '# 제목');
    await tester.tap(find.byKey(MarkdownKeys.redo));
    await tester.pump();
    expect(field.controller!.text, '  # 제목');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(field.controller!.text, '# 제목');
    await _autosave(tester);
    expect(await h.stored(tester, id), '# 제목');
  });

  testWidgets(
    'narrow phone bar: icon-only mode button, undo in the symbol row',
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, '아주 긴 제목이 들어가도 막대가 넘치지 않아요');
      await h.pump(
        tester,
        id,
        size: const Size(390, 844),
        initialEdit: true,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(MarkdownKeys.undo), findsNothing);
      expect(find.byKey(MarkdownKeys.accessoryButton('undo')), findsOneWidget);
      expect(find.byKey(MarkdownKeys.split), findsNothing);
      unawaited(Future<void>.value());
    },
  );
}
