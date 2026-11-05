// Editor menu actions (06-pdf 4.11; 8 T17): the five ids, labels and order are fixed,
// 'pdf.search' is disabled without onNavigate, the export entries open the options sheet
// with their purpose and the invocation's pages ('선택한 페이지' default), 'pdf.search'
// opens the search panel, and 'pdf.insert' inserts after the current page (else at the
// end) and then calls onNavigate(firstId, null) — with a PdfMenuInvocation built from the
// same fields INFRA's pdfMenuInvocationOf copies from EditorMenuContext (01-infra 4.5.9).
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import '../support/export_world.dart';
import '../support/render_doubles.dart';

Uint8List _pdf() => Uint8List.fromList('%PDF-1.7\n% menu\n%%EOF\n'.codeUnits);

/// The EditorMenuContext fields INFRA's pdfMenuInvocationOf reads (contract 7.2.17).
final class _EditorContext {
  _EditorContext({
    required this.noteId,
    this.currentPageId,
    this.selectedPageIds = const [],
  });

  final String noteId;
  final String? currentPageId;
  final List<String> selectedPageIds;
  final List<(String, Rect?)> navigations = [];

  void navigateToPage(String pageId, Rect? focusRectPt) =>
      navigations.add((pageId, focusRectPt));

  /// INFRA pdfMenuInvocationOf (01-infra 4.5.9): the same four fields.
  PdfMenuInvocation invocation({bool withNavigate = true}) => PdfMenuInvocation(
    noteId: noteId,
    currentPageId: currentPageId,
    selectedPageIds: selectedPageIds,
    onNavigate: withNavigate ? navigateToPage : null,
  );
}

final class _World {
  _World() {
    container = ProviderContainer(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        core.pageThumbnailRendererProvider.overrideWithValue(
          ScriptedThumbnailRenderer(),
        ),
        pdfEngineProvider.overrideWithValue(engine),
        pdfNoteGatewayProvider.overrideWithValue(gateway),
        pdfDocumentPoolProvider.overrideWithValue(RecordingDocumentPool()),
        pdfPageRendererProvider.overrideWithValue(SolidThumbnailRenderer()),
        pdfFileSourceProvider.overrideWithValue(files),
        pdfComposeBackendProvider.overrideWithValue(RecordingComposeBackend()),
        pdfInkVectorizerProvider.overrideWithValue(const BoxInkVectorizer()),
        pdfOutputSinkProvider.overrideWithValue(FakePdfOutputSink()),
      ],
    );
  }

  final core.NoteStore store = core_testing.createFakeNoteStore();
  final FakePdfEngine engine = FakePdfEngine(pageCount: 2);
  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  final FakePdfFileSource files = FakePdfFileSource();
  late final ProviderContainer container;
  late BuildContext context;

  Future<(core.NoteId, List<core.PageId>)> note(int pageCount) async {
    final note = await gateway.createNote(
      title: '수학',
      pages: [for (var i = 0; i < pageCount; i++) blankDraft],
    );
    final pages = await gateway.pagesOf(note.id);
    return (note.id, [for (final p in pages) p.id]);
  }

  Widget app() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            this.context = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );

  Future<void> dispose() async {
    container.dispose();
    await store.close();
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

PdfMenuAction _action(List<PdfMenuAction> actions, String id) =>
    actions.singleWhere((a) => a.id == id);

/// The range chosen on the export options sheet ('all' / 'current' / 'selected').
String _chosenRange(WidgetTester tester) {
  final group = tester.widget(
    _inSheet(find.byWidgetPredicate((w) => w is RadioGroup<Object?>)),
  ) as RadioGroup<Object?>;
  return (group.groupValue! as Enum).name;
}

void main() {
  test('ids, labels and order are fixed; search needs onNavigate', () {
    final more = pdfEditorMoreMenuActions();
    expect(
      [for (final a in more) a.id],
      ['pdf.export', 'pdf.share', 'pdf.print', 'pdf.search'],
    );
    expect(
      [for (final a in more) a.label],
      ['PDF로 내보내기', 'PDF 공유', '인쇄', 'PDF에서 찾기'],
    );
    final add = pdfEditorAddPageSources();
    expect([for (final a in add) a.id], ['pdf.insert']);
    expect(add.single.label, 'PDF에서 페이지 삽입');
    for (final a in [...more, ...add]) {
      expect(a.icon, isA<IconData>(), reason: a.id);
    }

    final editor = _EditorContext(noteId: 'n1');
    final search = _action(more, 'pdf.search');
    expect(search.isEnabled!(editor.invocation()), isTrue);
    expect(search.isEnabled!(editor.invocation(withNavigate: false)), isFalse);
    for (final id in ['pdf.export', 'pdf.share', 'pdf.print']) {
      final enabled = _action(more, id).isEnabled;
      expect(
        enabled == null || enabled(editor.invocation(withNavigate: false)),
        isTrue,
        reason: id,
      );
    }
  });

  testWidgets('export entries: their purpose and the invocation pages', (
    tester,
  ) async {
    final w = _World();
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final (noteId, pages) = await w.note(3);
    final editor = _EditorContext(
      noteId: noteId,
      currentPageId: pages[1],
      selectedPageIds: [pages[2], pages[0]],
    );
    final more = pdfEditorMoreMenuActions();

    for (final (id, title) in [
      ('pdf.export', 'PDF로 내보내기'),
      ('pdf.share', 'PDF 공유'),
      ('pdf.print', '인쇄'),
    ]) {
      final run = _action(more, id).run(w.context, editor.invocation());
      await _settle(tester);
      expect(_inSheet(find.text(title)), findsOneWidget, reason: id);
      expect(_chosenRange(tester), 'selected', reason: id);
      await tester.tap(_inSheet(find.text('취소')));
      await _settle(tester);
      await run;
    }

    // A full run: the current page (2nd) → '수학 (p2).pdf'.
    final run = _action(more, 'pdf.export').run(w.context, editor.invocation());
    await _settle(tester);
    await tester.tap(_inSheet(find.text('현재 페이지')));
    await tester.pump();
    await tester.tap(_inSheet(find.text('내보내기')));
    await _settle(tester);
    expect(_inSheet(find.textContaining('수학 (p2).pdf')), findsOneWidget);
    await tester.tap(_inSheet(find.text('닫기')));
    await _settle(tester);
    await run;
    expect(editor.navigations, isEmpty);
  });

  testWidgets('pdf.search opens the search panel of the note', (tester) async {
    final w = _World();
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final (noteId, _) = await w.note(1);
    final editor = _EditorContext(noteId: noteId);
    final run = _action(
      pdfEditorMoreMenuActions(),
      'pdf.search',
    ).run(w.context, editor.invocation());
    await _settle(tester);
    expect(find.text('찾을 내용'), findsOneWidget);
    Navigator.of(w.context).pop();
    await _settle(tester);
    await run;
    expect(find.byType(BottomSheet), findsNothing);

    // Disabled entry run anyway (no onNavigate): nothing opens.
    await _action(
      pdfEditorMoreMenuActions(),
      'pdf.search',
    ).run(w.context, editor.invocation(withNavigate: false));
    await _settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets(
    'pdf.insert: after the current page, then onNavigate(firstId, null)',
    (tester) async {
      final w = _World();
      addTearDown(w.dispose);
      await tester.pumpWidget(w.app());
      final (noteId, pages) = await w.note(3);
      final editor = _EditorContext(noteId: noteId, currentPageId: pages[0]);
      w.files.enqueue(PickedPdfFile.fromBytes('자료.pdf', _pdf()));

      final insert = pdfEditorAddPageSources().single;
      final run = insert.run(w.context, editor.invocation());
      await _settle(tester);
      expect(_inSheet(find.text('PDF에서 페이지 삽입')), findsOneWidget);
      await tester.tap(find.text('PDF 파일 선택'));
      await _settle(tester);
      await tester.tap(find.text('가져오기'));
      await _settle(tester);
      await run;

      final after = [for (final p in await w.gateway.pagesOf(noteId)) p.id];
      expect(after, hasLength(5));
      expect(after.first, pages[0]);
      expect(after.sublist(3), [pages[1], pages[2]]);
      expect(editor.navigations, [(after[1], null)]);

      // No current page → at the end; a cancelled pick → no navigation.
      final atEnd = _EditorContext(noteId: noteId);
      w.files.enqueue(PickedPdfFile.fromBytes('끝.pdf', _pdf()));
      final second = insert.run(w.context, atEnd.invocation());
      await _settle(tester);
      await tester.tap(find.text('PDF 파일 선택'));
      await _settle(tester);
      await tester.tap(find.text('가져오기'));
      await _settle(tester);
      await second;
      final last = [for (final p in await w.gateway.pagesOf(noteId)) p.id];
      expect(last, hasLength(7));
      expect(last.sublist(0, 5), after);
      expect(atEnd.navigations, [(last[5], null)]);

      final cancelled = _EditorContext(noteId: noteId, currentPageId: pages[2]);
      final third = insert.run(w.context, cancelled.invocation());
      await _settle(tester);
      await tester.tap(
        find.text('PDF 파일 선택'),
      ); // empty queue → the pick is cancelled
      await _settle(tester);
      await third;
      expect(cancelled.navigations, isEmpty);
      expect(await w.gateway.pagesOf(noteId), hasLength(7));
      await _settle(tester);
    },
  );
}
