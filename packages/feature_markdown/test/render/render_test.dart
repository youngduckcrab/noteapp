// B-3 … B-7, B-14 / MD-T12 / MD-T13 / MD-T14 (08-markdown 8.3, 8.5, 8.6): every element
// of the owner's list renders with its key, links ask first (open only with the slot and
// a safe scheme), '#heading' links scroll, task boxes toggle the source, accessibility
// labels, text scale 2.0 without overflow.
import 'dart:convert';

import 'package:feature_markdown/feature_markdown.dart';
import 'package:feature_markdown/slots.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/pump.dart';
import '../support/sample_doc.dart';

void main() {
  late List<MethodCall> clipboard;

  setUp(() {
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        });
  });

  String? copied() => clipboard.isEmpty
      ? null
      : (clipboard.last.arguments as Map)['text'] as String?;

  testWidgets('the sample renders every element with its key', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, kSampleMarkdown);
    await h.pump(tester, id, size: const Size(1194, 3000));
    expect(find.byKey(MarkdownKeys.view), findsOneWidget);
    expect(find.text('회의록 — 2학기 프로젝트', findRichText: true), findsWidgets);
    for (var i = 0; i < 5; i++) {
      expect(
        find.byKey(MarkdownKeys.task(i)),
        findsOneWidget,
        reason: 'task $i',
      );
    }
    expect(find.byKey(MarkdownKeys.table(0)), findsOneWidget);
    expect(find.byKey(MarkdownKeys.code(0)), findsOneWidget);
    expect(find.byKey(MarkdownKeys.codeCopy(0)), findsOneWidget);
    expect(find.byKey(MarkdownKeys.math(0)), findsOneWidget); // inline
    expect(find.byKey(MarkdownKeys.math(1)), findsOneWidget); // block
    expect(find.byKey(MarkdownKeys.image(0)), findsOneWidget);
    expect(find.text('이미지를 불러오지 않았어요'), findsOneWidget);
    expect(find.text('images.example.com'), findsOneWidget);
    expect(find.byKey(MarkdownKeys.block(0)), findsOneWidget);
    expect(find.text('각주'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('task checkbox toggles the source, saves, offers undo', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    const src = '- [ ] 하나\n- [x] 둘';
    final id = await h.doc(tester, src);
    await h.pump(tester, id);
    final box = tester.widget<Checkbox>(find.byKey(MarkdownKeys.task(0)));
    expect(box.value, isFalse);
    expect(box.onChanged, isNotNull);
    await tester.tap(find.byKey(MarkdownKeys.task(0)));
    await settleMd(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await settleMd(tester);
    expect(await h.stored(tester, id), '- [x] 하나\n- [x] 둘');
    expect(
      tester.widget<Checkbox>(find.byKey(MarkdownKeys.task(0))).value,
      isTrue,
    );
    expect(find.byKey(MarkdownKeys.taskUndo), findsOneWidget);
    await tester.tap(find.byKey(MarkdownKeys.taskUndo));
    await settleMd(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await settleMd(tester);
    expect(await h.stored(tester, id), src);
  });

  testWidgets('boxes are display-only in a trashed document', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '- [ ] 하나');
    await tester.runAsync(() => h.store.library.trashItems([NoteRef(id)]));
    await h.pump(tester, id);
    expect(find.byKey(MarkdownKeys.bannerTrashed), findsOneWidget);
    expect(
      tester.widget<Checkbox>(find.byKey(MarkdownKeys.task(0))).onChanged,
      isNull,
    );
    expect(
      tester.widget<ButtonStyleButton>(find.byKey(MarkdownKeys.mode)).onPressed,
      isNull,
    );
  });

  testWidgets('code copy puts the code on the clipboard', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '```js\nconst a = "가";\n```');
    await h.pump(tester, id);
    expect(find.text('js'), findsOneWidget);
    await tester.tap(find.byKey(MarkdownKeys.codeCopy(0)));
    await settleMd(tester);
    expect(copied(), 'const a = "가";');
  });

  group('links', () {
    Future<void> tapLink(WidgetTester tester, String text) async {
      await tester.tapOnText(find.textRange.ofSubstring(text));
      await settleMd(tester);
    }

    testWidgets('without the open slot: sheet with copy only', (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, '[문서](https://example.com/a?b=1) 끝');
      await h.pump(tester, id);
      await tapLink(tester, '문서');
      expect(find.byKey(MarkdownKeys.linkSheet), findsOneWidget);
      expect(find.text('https://example.com/a?b=1'), findsOneWidget);
      expect(find.byKey(MarkdownKeys.linkSheetOpen), findsNothing);
      await tester.tap(find.byKey(MarkdownKeys.linkSheetCopy));
      await settleMd(tester);
      expect(copied(), 'https://example.com/a?b=1');
      expect(find.byKey(MarkdownKeys.linkSheet), findsNothing);
    });

    testWidgets('with the slot: open http(s) only after asking', (
      tester,
    ) async {
      final opened = <Uri>[];
      final h = await MdHarness.create(tester);
      final id = await h.doc(
        tester,
        '[웹](https://example.com) [나쁜](javascript:alert(1)) [메일](mailto:a@b.c)',
      );
      await h.pump(
        tester,
        id,
        overrides: [
          markdownOpenLinkProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
      );
      expect(opened, isEmpty);
      await tapLink(tester, '웹');
      await tester.tap(find.byKey(MarkdownKeys.linkSheetOpen));
      await settleMd(tester);
      expect(opened, [Uri.parse('https://example.com')]);

      await tapLink(tester, '나쁜');
      expect(find.byKey(MarkdownKeys.linkSheet), findsOneWidget);
      expect(find.byKey(MarkdownKeys.linkSheetOpen), findsNothing);
      expect(find.text('이 주소는 앱에서 열 수 없어서 복사만 돼요'), findsOneWidget);
      await tester.tap(find.byKey(MarkdownKeys.linkSheetCancel));
      await settleMd(tester);

      await tapLink(tester, '메일');
      expect(find.byKey(MarkdownKeys.linkSheetOpen), findsOneWidget);
      expect(opened, hasLength(1));
    });

    testWidgets("'#heading' links scroll inside the document", (tester) async {
      final h = await MdHarness.create(tester);
      final body = [
        '[끝으로](#마지막-장)',
        for (var i = 0; i < 80; i++) '문단 $i 입니다.',
        '## 마지막 장',
        '여기',
      ].join('\n\n');
      final id = await h.doc(tester, body);
      await h.pump(tester, id, size: const Size(800, 600));
      expect(find.text('마지막 장', findRichText: true), findsNothing);
      await tapLink(tester, '끝으로');
      await settleMd(tester, 20);
      expect(find.text('마지막 장', findRichText: true), findsOneWidget);
      expect(find.byKey(MarkdownKeys.linkSheet), findsNothing);
    });
  });

  testWidgets('invalid math shows its source in the error colour', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, r'잘못된 $\frac{a$ 식');
    await h.pump(tester, id);
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(MarkdownKeys.math(0)),
        matching: find.byType(Text),
      ),
    );
    final scheme = buildStyleTheme(
      AppStyle.craft,
      Brightness.light,
    ).colorScheme;
    expect(text.style?.color, scheme.error);
    expect(text.data, r'$\frac{a$');
  });

  testWidgets('data: images draw; relative paths explain', (tester) async {
    // 1x1 transparent PNG
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
    expect(base64Decode(png), isNotEmpty);
    final h = await MdHarness.create(tester);
    final id = await h.doc(
      tester,
      '![점](data:image/png;base64,$png)\n\n![지도](images/map.png)',
    );
    await h.pump(tester, id);
    expect(
      find.descendant(
        of: find.byKey(MarkdownKeys.image(0)),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(find.text('원본 파일의 이미지는 가져오지 않았어요'), findsOneWidget);
  });

  testWidgets('front matter is a folded box', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '---\ntitle: 비밀\n---\n# 본문');
    await h.pump(tester, id);
    expect(find.byKey(MarkdownKeys.frontMatter), findsOneWidget);
    expect(find.text('title: 비밀'), findsNothing);
    await tester.tap(find.text('문서 정보 (머리말)'));
    await settleMd(tester);
    expect(find.text('title: 비밀'), findsOneWidget);
  });

  testWidgets('semantics: task boxes and links are labelled', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '- [x] 장보기\n\n[링크 글](https://e.com)');
    await h.pump(tester, id);
    expect(find.bySemanticsLabel(RegExp('할 일: 장보기, 끝남')), findsOneWidget);
    final links = <String>[];
    void walk(SemanticsNode n) {
      final data = n.getSemanticsData();
      if (data.flagsCollection.isLink) links.add(data.label);
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(
      tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!,
    );
    expect(links, contains('링크 글'));
    handle.dispose();
  });

  for (final size in const [Size(390, 844), Size(1194, 834)]) {
    testWidgets('text scale 2.0 holds at ${size.width.toInt()} px', (
      tester,
    ) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, kSampleMarkdown);
      await h.pump(tester, id, size: size, textScale: 2);
      expect(tester.takeException(), isNull);
      await h.pump(tester, id, size: size, textScale: 2, initialEdit: true);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty document shows a hint', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '');
    await h.pump(tester, id);
    expect(find.text('아직 내용이 없어요'), findsOneWidget);
  });
}
