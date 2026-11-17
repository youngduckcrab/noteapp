// (v2.17-md, 08-markdown 15.4 '앱 끝까지') The MD 문서 path through the production app: the
// real modules (CoreModule over the store the test gives, PdfModule, FeatureWiringModule
// with a fake text file picker and a recording export output), the production router and
// screens:
//
//   library → 새로 만들기 › MD 가져오기 (one .md file) → the document opens in 보기 (rendered
//   heading, task box) → 편집 → type → [←] twice (편집 → 보기 → library) → the text is
//   stored and the MD card shows it → library search finds the body → the hit opens the
//   document at /md/<id>?q= with the landing highlight → ⋯ › .md로 내보내기 › 저장 gives the
//   stored text byte for byte, named from the title → back → 새로 만들기 › 새 MD 문서 opens
//   an empty document in 편집 → type → back (보기 at full width) → back → ⋯ › 휴지통으로
//   이동 → 휴지통 → 복원 → the card is back.
//
// Controls are found by the packages' widget keys (strings — the key classes of
// feature_library live under src/, R7) and visible labels. Store work runs in real time
// (pumpUntil / settle), as in the other app smokes.
//
// Web-safe: no dart:io.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:feature_library/feature_library.dart';
import 'package:feature_markdown/feature_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/markdown_wiring.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:pdf_io/pdf_io.dart';

import 'smoke_scenario.dart';

/// The file the fake picker returns: BOM-less UTF-8, LF, Korean, a task list and math.
const String kE2eMarkdownName = '미적분 정리.md';
const String kE2eMarkdownText =
    '# 미적분 정리\n'
    '\n'
    '접선의 기울기는 **미분**으로 구한다.\n'
    '\n'
    '- [ ] 연습문제 풀기\n'
    '- [x] 개념 복습\n'
    '\n'
    r'$$\int_0^1 x^2\,dx = \frac{1}{3}$$'
    '\n';

/// The text typed in 편집 (appended paragraph).
const String kE2eTyped = '\n적분은 넓이를 구하는 도구다.\n';

/// A text file picker that returns [files] once per call (null → cancelled).
final class E2eTextSource implements TextFileSource {
  E2eTextSource(this.files);
  final List<PickedTextFile>? files;
  int calls = 0;
  @override
  bool get isSupported => true;
  @override
  Future<List<PickedTextFile>?> pickTextFiles({bool allowMultiple = true}) {
    calls++;
    return Future.value(files);
  }
}

/// An export output that records what it was given (save + share offered).
final class E2eDocumentOutput implements DocumentFileOutput {
  final List<(DocumentFile, DocumentOutputAction)> delivered = [];
  @override
  Set<DocumentOutputAction> availableActions(DocumentFile file) => {
    DocumentOutputAction.share,
    DocumentOutputAction.save,
  };
  @override
  String labelOf(DocumentOutputAction action) => switch (action) {
    DocumentOutputAction.share => '공유',
    _ => '저장',
  };
  @override
  Future<PdfOutputOutcome> deliver(
    DocumentFile file,
    DocumentOutputAction action,
  ) async {
    delivered.add((file, action));
    return PdfOutputOutcome.done;
  }
}

Finder _newMenu() => find.text('새로 만들기');
Finder _tile(String title) => find.byTooltip('$title 메뉴');

Finder _searchInput() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == '노트 검색',
);

String _location(WidgetTester tester) {
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  return (app.routerConfig! as GoRouter).state.uri.toString();
}

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _frames(tester);
}

Future<void> _waitFor(WidgetTester tester, Finder f, String reason) =>
    pumpUntil(tester, () => f.evaluate().isNotEmpty, reason: reason);

Future<List<Note>> _markdownNotes(SmokeApp app) async => [
  for (final n
      in (await app.store.library.watchListing(const LibraryQuery()).first)
          .notes)
    if (n.isMarkdown) n,
];

/// Boots, runs the path, shuts down.
Future<void> runMarkdownEndToEnd(WidgetTester tester, CoreModule core) async {
  final source = E2eTextSource([
    PickedTextFile.fromBytes(
      kE2eMarkdownName,
      Uint8List.fromList(utf8.encode(kE2eMarkdownText)),
    ),
  ]);
  final output = E2eDocumentOutput();
  final app = await bootSmokeAppWith(
    tester,
    modules: [
      core,
      PdfModule(),
      FeatureWiringModule(
        importMarkdown: markdownImportAction(source: source),
        markdownOutput: output,
      ),
    ],
  );
  // Wide landscape tablet: the sidebar (휴지통) is on screen.
  tester.view.physicalSize = const Size(2752, 2064);
  await _frames(tester);

  // 1. 새로 만들기 › MD 가져오기 → the document opens in 보기.
  await _tap(tester, _newMenu());
  expect(find.byKey(const Key('library.new.markdown')), findsOneWidget);
  await _tap(tester, find.byKey(const Key('library.new.importMarkdown')));
  await _waitFor(tester, find.byKey(MarkdownKeys.view), 'the imported doc');
  expect(source.calls, 1);
  final imported = (await settle(
    tester,
    'the listing',
    () => _markdownNotes(app),
  )).single;
  expect(imported.title, '미적분 정리');
  expect(_location(tester), '/md/${imported.id}');
  expect(find.text('미적분 정리', findRichText: true), findsWidgets);
  expect(find.byKey(MarkdownKeys.task(0)), findsOneWidget);
  expect(find.byKey(MarkdownKeys.math(0)), findsOneWidget);
  expect(find.byKey(MarkdownKeys.editor), findsNothing);

  // 2. 편집 → type → [←] (편집 → 보기) → [←] (library): stored, the card follows.
  await _tap(tester, find.byKey(MarkdownKeys.mode));
  expect(find.byKey(MarkdownKeys.editor), findsOneWidget);
  final edited = '$kE2eMarkdownText$kE2eTyped';
  await tester.enterText(find.byKey(MarkdownKeys.editor), edited);
  await _frames(tester);
  await _tap(tester, find.byKey(MarkdownKeys.back));
  expect(find.byKey(MarkdownKeys.editor), findsNothing);
  expect(find.byKey(MarkdownKeys.view), findsOneWidget);
  expect(find.textContaining('넓이를 구하는', findRichText: true), findsWidgets);
  await _tap(tester, find.byKey(MarkdownKeys.back));
  await _waitFor(tester, find.byType(LibraryScreen), 'the library again');
  await pumpUntil(
    tester,
    () => find.byKey(MarkdownKeys.screen).evaluate().isEmpty,
    reason: 'the MD screen closed',
  );
  final stored = await settle(
    tester,
    'the stored text',
    () => app.store.markdown.get(imported.id),
  );
  expect(stored!.text, edited);
  expect(_tile('미적분 정리'), findsOneWidget);

  // 3. Library search finds the body; the hit opens the document with the query.
  await tester.enterText(_searchInput(), '기울기');
  await tester.pump(const Duration(milliseconds: 300));
  final hit = find.byKey(ValueKey('library.hit.markdown.${imported.id}'));
  await _waitFor(tester, hit, 'the content search hit');
  await _tap(tester, hit);
  await _waitFor(tester, find.byKey(MarkdownKeys.view), 'the doc from search');
  expect(
    _location(tester),
    '/md/${imported.id}?q=${Uri.encodeQueryComponent('기울기')}',
  );
  await _waitFor(
    tester,
    find.byKey(MarkdownKeys.highlight),
    'the search landing highlight',
  );

  // 4. ⋯ › .md로 내보내기 › 저장: the stored text byte for byte, named from the title.
  await _tap(tester, find.byKey(MarkdownKeys.more));
  await _tap(tester, find.byKey(MarkdownKeys.menuExport));
  await _waitFor(
    tester,
    find.byKey(const Key('md.export.save')),
    'the export sheet',
  );
  await _tap(tester, find.byKey(const Key('md.export.save')));
  await pumpUntil(
    tester,
    () => output.delivered.isNotEmpty,
    reason: 'the export delivered',
  );
  final (file, action) = output.delivered.single;
  expect(action, DocumentOutputAction.save);
  expect(file.name, '미적분 정리.md');
  expect(file.bytes, utf8.encode(edited));

  // Back to the library (the search stays as typed: clear it).
  await _tap(tester, find.byKey(MarkdownKeys.back));
  await _waitFor(tester, find.byType(LibraryScreen), 'the library (3)');
  await tester.enterText(_searchInput(), '');
  await _frames(tester);

  // 5. 새로 만들기 › 새 MD 문서 → name dialog → 만들기 → opens in 편집.
  await _tap(tester, _newMenu());
  await _tap(tester, find.byKey(const Key('library.new.markdown')));
  await _tap(tester, find.text('만들기'));
  await _waitFor(tester, find.byKey(MarkdownKeys.editor), 'the new doc (편집)');
  // Typed, then [←] → 보기: the rendered text keeps the full width (it collapsed to a
  // 0 px column, one character per line, while the editor stayed mounted Offstage).
  await tester.enterText(
    find.byKey(MarkdownKeys.editor),
    '# 새 문서\n\n처음 적는 문단입니다. The first paragraph.\n',
  );
  await _frames(tester);
  await _tap(tester, find.byKey(MarkdownKeys.back));
  await _waitFor(tester, find.byKey(MarkdownKeys.view), 'the new doc (보기)');
  expect(
    tester.getSize(find.byKey(MarkdownKeys.view)).width,
    greaterThan(
      tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
    ),
  );
  await _tap(tester, find.byKey(MarkdownKeys.back));
  await _waitFor(tester, find.byType(LibraryScreen), 'the library (4)');
  await pumpUntil(
    tester,
    () => find.byKey(MarkdownKeys.screen).evaluate().isEmpty,
    reason: 'the new doc closed',
  );
  final both = await settle(tester, 'two docs', () => _markdownNotes(app));
  expect(both, hasLength(2));
  expect(both.map((n) => n.title), contains('새 MD 문서'));

  // 6. ⋯ › 휴지통으로 이동 → 휴지통 → 복원 → back in the library.
  await _waitFor(tester, _tile('미적분 정리'), 'the card');
  await _tap(tester, find.byTooltip('미적분 정리 메뉴'));
  await _tap(tester, find.widgetWithText(MenuItemButton, '휴지통으로 이동'));
  await pumpUntil(
    tester,
    () => _tile('미적분 정리').evaluate().isEmpty,
    reason: 'the card left the listing',
  );
  final trashed = await settle(
    tester,
    'the trashed doc',
    () => app.store.markdown.get(imported.id),
  );
  expect(trashed!.note.deletedAt, isNotNull);
  await _tap(tester, find.text('휴지통').first);
  await _waitFor(tester, find.byTooltip('미적분 정리 메뉴'), 'the trash row');
  await _tap(tester, find.byTooltip('미적분 정리 메뉴'));
  await _tap(tester, find.widgetWithText(MenuItemButton, '복원'));
  await pumpUntil(
    tester,
    () => find.byTooltip('미적분 정리 메뉴').evaluate().isEmpty,
    reason: 'the trash row left',
  );
  final restored = await settle(
    tester,
    'the restored doc',
    () => app.store.markdown.get(imported.id),
  );
  expect(restored!.note.deletedAt, isNull);
  expect(restored.text, edited);
  await _tap(tester, find.text('홈').first);
  await _waitFor(tester, _tile('미적분 정리'), 'the card back on 홈');
  // Recent lists the opened document too.
  await _tap(tester, find.text('최근').first);
  await _waitFor(tester, _tile('미적분 정리'), 'the card in 최근');
  expect(app.errorLog.records, isEmpty, reason: '${app.errorLog}');

  await app.shutdown(tester);
}
