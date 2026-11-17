// (v2.17-md, C217M-11 · 12 · 16 — docs/plans/m5-7/08-markdown.md 10, MD-T06) The app's MD 문서
// flows: import (several files, the refused ones and why, at most 20, one → it opens), the
// export file (UTF-8 bytes exactly — BOM, CRLF, Korean, emoji — the name from the title,
// MIME text/markdown / share text/plain), the export sheet over a recording output, the
// library export of a stored document byte for byte, the native share call, and the
// wiring module's overrides.
import 'dart:convert';
import 'dart:typed_data';

import 'package:feature_library/feature_library.dart';
import 'package:feature_markdown/slots.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/modules/document_share_native.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/markdown_wiring.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:share_plus/share_plus.dart';

Uint8List _b(List<int> bytes) => Uint8List.fromList(bytes);

final class _Source implements TextFileSource {
  _Source(this.files);
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

final class _Output implements DocumentFileOutput {
  _Output(this.actions);
  final Set<DocumentOutputAction> actions;
  final List<(DocumentFile, DocumentOutputAction)> delivered = [];
  @override
  Set<DocumentOutputAction> availableActions(DocumentFile file) => actions;
  @override
  String labelOf(DocumentOutputAction action) => action.name;
  @override
  Future<PdfOutputOutcome> deliver(
    DocumentFile file,
    DocumentOutputAction action,
  ) async {
    delivered.add((file, action));
    return PdfOutputOutcome.done;
  }
}

void main() {
  final bytes = _b([
    0xEF, 0xBB, 0xBF, //
    ...utf8.encode('# 회의 메모\r\n\r\n- [ ] 발표 🙂\r\n'),
  ]);

  group('importMarkdownFiles', () {
    test('several files: each decoded and created in the folder, the refused '
        'ones with their reason', () async {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      final folder = await store.library.createFolder(name: '수업');
      final outcome = await importMarkdownFiles(store.markdown, [
        PickedTextFile.fromBytes('회의.md', bytes),
        PickedTextFile.fromBytes('README.markdown', _b(utf8.encode('# 소개\n'))),
        PickedTextFile.fromBytes('cp949.txt', _b([0xC7, 0xD1])),
        PickedTextFile.fromBytes('bin.md', _b([0x61, 0x00])),
        PickedTextFile(
          name: 'huge.md',
          sizeBytes: MarkdownLimits.maxTextBytes + 1,
          readBytes: () => throw StateError('must not be read'),
        ),
      ], folderId: folder.id);
      expect(outcome.created, hasLength(2));
      expect(outcome.refused, {
        'cp949.txt': MarkdownWiringStrings.notUtf8,
        'bin.md': MarkdownWiringStrings.notText,
        'huge.md': MarkdownWiringStrings.tooLarge,
      });
      expect(outcome.cut, isFalse);
      final first = (await store.markdown.get(outcome.created.first))!;
      expect(first.note.title, '회의');
      expect(first.note.folderId, folder.id);
      expect(utf8.encode(first.text), bytes);
      final second = (await store.markdown.get(outcome.created.last))!;
      expect(second.note.title, '소개');
      expect(
        markdownImportMessage(outcome),
        '${MarkdownWiringStrings.imported(2)} · '
        '${MarkdownWiringStrings.refused(3)} — '
        '${MarkdownWiringStrings.notUtf8}, ${MarkdownWiringStrings.notText}, '
        '${MarkdownWiringStrings.tooLarge}',
      );
    });

    test('at most 20 files; one file → no message (it opens)', () async {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      final many = await importMarkdownFiles(store.markdown, [
        for (var i = 0; i < 22; i++)
          PickedTextFile.fromBytes('f$i.md', _b(utf8.encode('$i'))),
      ], folderId: null);
      expect(many.created, hasLength(MarkdownLimits.maxImportFiles));
      expect(many.cut, isTrue);
      expect(
        markdownImportMessage(many),
        contains(MarkdownWiringStrings.onlyFirst(20)),
      );
      final one = await importMarkdownFiles(store.markdown, [
        PickedTextFile.fromBytes('a.md', _b(utf8.encode('a'))),
      ], folderId: null);
      expect(markdownImportMessage(one), isNull);
      final bad = await importMarkdownFiles(store.markdown, [
        PickedTextFile.fromBytes('a.md', _b([0xFF])),
      ], folderId: null);
      expect(markdownImportMessage(bad), MarkdownWiringStrings.notUtf8);
    });
  });

  group('markdownDocumentFile (10.4)', () {
    test(
      'bytes = utf8.encode(text) exactly; name from the title; MIME types',
      () {
        const text = '﻿# 제목\r\n본문 😀 𠀀\r\n\t끝';
        final file = markdownDocumentFile(title: '회의: 메모/1', text: text);
        expect(file.bytes, utf8.encode(text));
        expect(file.bytes.take(3), [0xEF, 0xBB, 0xBF]);
        expect(file.name, '${PdfFileNaming.sanitize('회의: 메모/1')}.md');
        expect(file.mimeType, 'text/markdown');
        expect(file.shareMimeType, 'text/plain');
        expect(
          markdownDocumentFile(title: 'notes.md', text: '').name,
          'notes.md',
        );
        expect(
          markdownDocumentFile(title: 'a.markdown', text: '').name,
          'a.markdown',
        );
        expect(
          markdownDocumentFile(title: '   ', text: '').name,
          '${PdfFileNaming.sanitize('   ')}.md',
        );
      },
    );

    test('import → export gives back the same bytes', () async {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      final o = await importMarkdownFiles(store.markdown, [
        PickedTextFile.fromBytes('a.md', bytes),
      ], folderId: null);
      final doc = (await store.markdown.get(o.created.single))!;
      expect(
        markdownDocumentFile(title: doc.note.title, text: doc.text).bytes,
        bytes,
      );
    });
  });

  group('flows', () {
    Future<(ProviderContainer, BuildContext)> pumpHost(
      WidgetTester tester,
      NoteStore store,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [noteStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  ctx = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );
      return (ProviderScope.containerOf(ctx), ctx);
    }

    testWidgets('the import action: one file → its id; several → null + a '
        'message; cancel → null', (tester) async {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      final (_, ctx) = await pumpHost(tester, store);
      final one = _Source([PickedTextFile.fromBytes('하나.md', bytes)]);
      final id = await tester.runAsync(
        () => markdownImportAction(source: one)(ctx),
      );
      expect(id, isNotNull);
      expect(one.calls, 1);
      final two = _Source([
        PickedTextFile.fromBytes('a.md', _b(utf8.encode('a'))),
        PickedTextFile.fromBytes('b.md', _b(utf8.encode('b'))),
      ]);
      expect(
        await tester.runAsync(() => markdownImportAction(source: two)(ctx)),
        isNull,
      );
      await tester.pump();
      expect(find.text(MarkdownWiringStrings.imported(2)), findsOneWidget);
      final cancel = _Source(null);
      expect(
        await tester.runAsync(() => markdownImportAction(source: cancel)(ctx)),
        isNull,
      );
    });

    testWidgets(
      'the export sheet: one row per action; a tap delivers the file',
      (tester) async {
        final store = createFakeNoteStore();
        addTearDown(store.close);
        final (_, ctx) = await pumpHost(tester, store);
        final output = _Output({
          DocumentOutputAction.share,
          DocumentOutputAction.save,
        });
        final done = exportMarkdownText(
          ctx,
          title: '문서',
          text: '﻿a\r\n',
          output: output,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('md.export.share')), findsOneWidget);
        await tester.tap(find.byKey(const Key('md.export.save')));
        await tester.pumpAndSettle();
        await done;
        expect(output.delivered.single.$2, DocumentOutputAction.save);
        expect(output.delivered.single.$1.bytes, utf8.encode('﻿a\r\n'));
        expect(output.delivered.single.$1.name, '문서.md');
      },
    );

    testWidgets('the library export reads the stored text byte for byte', (
      tester,
    ) async {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      const text = '﻿# 한글 🙂\r\n';
      final note = await tester.runAsync(
        () => store.markdown.create(title: '내보낼 문서', text: text),
      );
      final (_, ctx) = await pumpHost(tester, store);
      final output = _Output({DocumentOutputAction.save});
      final done = markdownLibraryExportAction(output: output)(ctx, note!.id);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('md.export.save')));
      await tester.pumpAndSettle();
      await done;
      expect(output.delivered.single.$1.bytes, utf8.encode(text));
    });
  });

  test(
    'native share: one XFile with the share MIME type and the .md name',
    () async {
      ShareParams? sent;
      final outcome = await shareDocumentFileWith(
        markdownDocumentFile(title: '문서', text: 'a'),
        share: (params) async {
          sent = params;
          return const ShareResult('ok', ShareResultStatus.success);
        },
        origin: Rect.zero,
      );
      expect(outcome, PdfOutputOutcome.done);
      expect(sent!.files!.single.mimeType, 'text/plain');
      expect(sent!.fileNameOverrides, ['문서.md']);
    },
  );

  test('FeatureWiringModule overrides the four MD slots', () {
    final names = {
      for (final o in FeatureWiringModule().overrides()) o.toString(),
    }.join(' ');
    for (final provider in [
      libraryMarkdownImportActionProvider,
      libraryMarkdownExportActionProvider,
      markdownExportActionProvider,
    ]) {
      expect(names, contains(provider.name), reason: provider.name);
    }
    // Q1 is open: no link opener (the link sheet offers 복사 only).
    expect(names, isNot(contains(markdownOpenLinkProvider.name)));
  });
}
