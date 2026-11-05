// DefaultPdfImportService (06-pdf 4.6, 6.3, 6.4, 6.5; 8 T5) with FakePdfEngine,
// FakePdfNoteGateway and the render doubles (pool T7 / renderer T8 come later).
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import '../support/render_doubles.dart';

TypeMatcher<PdfIoException> _code(PdfErrorCode code) =>
    isA<PdfIoException>().having((e) => e.code, 'code', code);

Uint8List _pdfBytes([String body = 'body']) =>
    Uint8List.fromList('%PDF-1.7\n% $body\n%%EOF\n'.codeUnits);

/// '강의자료.PDF' in NFD (conjoining jamo), as iOS / macOS file names may arrive.
const String _nfdName = '강의자료.PDF';

final class _Harness {
  _Harness({
    FakePdfEngine? engine,
    this.config = const PdfIoConfig(),
    bool withThumbnailRenderer = false,
  }) : engine = engine ?? FakePdfEngine(pageCount: 3),
       thumbnailRenderer = withThumbnailRenderer
           ? ScriptedThumbnailRenderer()
           : null {
    service = DefaultPdfImportService(
      engine: this.engine,
      gateway: gateway,
      pool: pool,
      renderer: renderer,
      config: config,
      thumbnailRenderer: thumbnailRenderer,
    );
  }

  final FakePdfEngine engine;
  final PdfIoConfig config;
  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  final RecordingDocumentPool pool = RecordingDocumentPool();
  final SolidThumbnailRenderer renderer = SolidThumbnailRenderer();
  final ScriptedThumbnailRenderer? thumbnailRenderer;
  late final DefaultPdfImportService service;
  final List<PdfProgress> progress = [];

  Future<PdfImportSession> open(
    PickedPdfFile file, {
    PdfPasswordCallback? onPassword,
    PdfCancelSignal? cancel,
  }) => service.open(
    file,
    onPassword: onPassword,
    onProgress: progress.add,
    cancel: cancel,
  );
}

/// Captures FlutterError reports for the duration of [body].
Future<List<FlutterErrorDetails>> _captureReports(
  Future<void> Function() body,
) async {
  final reports = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reports.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return reports;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('open', () {
    test('reads, opens and describes the file (steps 1–6)', () async {
      final h = _Harness(
        config: const PdfIoConfig(limits: PdfImportLimits(warnBytes: 10)),
      );
      final bytes = _pdfBytes();
      final session = await h.open(
        PickedPdfFile.fromBytes('lecture.pdf', bytes),
      );
      expect(h.progress, const [
        PdfProgress(PdfJobPhase.readingFile),
        PdfProgress(PdfJobPhase.openingPdf),
      ]);
      expect(h.engine.ensureInitializedCalls, greaterThanOrEqualTo(1));
      final call = h.engine.openCalls.single;
      expect(call.sourceName, startsWith('import:'));
      expect(call.fileName, 'lecture.pdf');
      expect(call.transferOwnership, isFalse);
      expect(session.info.pageCount, 3);
      expect(session.byteLength, bytes.length);
      expect(session.isLargeFile, isTrue);
      expect(session.willStoreDecryptedCopy, isFalse);
      expect(session.suggestedTitle, 'lecture');
      expect(h.engine.openDocumentCount, 1);
      await session.dispose();
      await session.dispose(); // idempotent
      expect(h.engine.openDocumentCount, 0);
    });

    test('isLargeFile is false at warnBytes', () async {
      final bytes = _pdfBytes();
      final h = _Harness(
        config: PdfIoConfig(limits: PdfImportLimits(warnBytes: bytes.length)),
      );
      final session = await h.open(PickedPdfFile.fromBytes('a.pdf', bytes));
      expect(session.isLargeFile, isFalse);
      await session.dispose();
    });

    test('NFD file name → composed suggested title', () async {
      final h = _Harness();
      final session = await h.open(
        PickedPdfFile.fromBytes(_nfdName, _pdfBytes()),
      );
      expect(session.suggestedTitle, '강의자료');
      await session.dispose();
    });

    test('declared size over maxBytes → tooLarge before reading', () async {
      final h = _Harness(
        config: const PdfIoConfig(limits: PdfImportLimits(maxBytes: 100)),
      );
      var reads = 0;
      final file = PickedPdfFile(
        name: 'big.pdf',
        sizeBytes: 101,
        readBytes: () async {
          reads++;
          return _pdfBytes();
        },
      );
      await expectLater(h.open(file), throwsA(_code(PdfErrorCode.tooLarge)));
      expect(reads, 0);
      expect(h.progress, isEmpty);
    });

    test(
      'read size over maxBytes → tooLarge (size unknown up front)',
      () async {
        final h = _Harness(
          config: const PdfIoConfig(limits: PdfImportLimits(maxBytes: 20)),
        );
        final file = PickedPdfFile(
          name: 'big.pdf',
          readBytes: () async => _pdfBytes('x' * 40),
        );
        await expectLater(h.open(file), throwsA(_code(PdfErrorCode.tooLarge)));
        expect(h.engine.openCalls, isEmpty);
      },
    );

    test('more pages than maxPages → tooManyPages, document closed', () async {
      final h = _Harness(
        engine: FakePdfEngine(pageCount: 3),
        config: const PdfIoConfig(limits: PdfImportLimits(maxPages: 2)),
      );
      await expectLater(
        h.open(PickedPdfFile.fromBytes('a.pdf', _pdfBytes())),
        throwsA(_code(PdfErrorCode.tooManyPages)),
      );
      expect(h.engine.documents, hasLength(1));
      expect(h.engine.openDocumentCount, 0);
    });

    test(
      'notPdf: no %PDF- in the first 1024 bytes; engine not asked',
      () async {
        final h = _Harness();
        final late = Uint8List(1100)
          ..fillRange(0, 1100, 0x20)
          ..setAll(1050, '%PDF-'.codeUnits);
        await expectLater(
          h.open(PickedPdfFile.fromBytes('x.pdf', late)),
          throwsA(_code(PdfErrorCode.notPdf)),
        );
        await expectLater(
          h.open(
            PickedPdfFile.fromBytes(
              'x.pdf',
              Uint8List.fromList('hello'.codeUnits),
            ),
          ),
          throwsA(_code(PdfErrorCode.notPdf)),
        );
        expect(h.engine.openCalls, isEmpty);
        final early = Uint8List(1100)
          ..fillRange(0, 1100, 0x20)
          ..setAll(500, '%PDF-'.codeUnits);
        final session = await h.open(PickedPdfFile.fromBytes('y.pdf', early));
        await session.dispose();
      },
    );

    test('readBytes failure → pickerFailed with the cause', () async {
      final h = _Harness();
      final file = PickedPdfFile(
        name: 'a.pdf',
        readBytes: () => Future.error(StateError('disk')),
      );
      await expectLater(
        h.open(file),
        throwsA(
          _code(PdfErrorCode.pickerFailed)
              .having((e) => e.cause, 'cause', isA<StateError>()),
        ),
      );
    });

    test('engine init failure → engineUnavailable', () async {
      final engine = FakePdfEngine()
        ..initError = const PdfIoException(PdfErrorCode.engineUnavailable);
      final h = _Harness(engine: engine);
      await expectLater(
        h.open(PickedPdfFile.fromBytes('a.pdf', _pdfBytes())),
        throwsA(_code(PdfErrorCode.engineUnavailable)),
      );
    });

    test('engine open error passes through (corrupt)', () async {
      final engine = FakePdfEngine()
        ..openError = const PdfIoException(PdfErrorCode.corrupt);
      final h = _Harness(engine: engine);
      await expectLater(
        h.open(PickedPdfFile.fromBytes('a.pdf', _pdfBytes())),
        throwsA(_code(PdfErrorCode.corrupt)),
      );
    });
  });

  group('passwords (6.4)', () {
    test('user password: wrong, then right → decrypted copy stored', () async {
      final engine = FakePdfEngine(pageCount: 2, userPassword: 'secret');
      final h = _Harness(engine: engine);
      final asked = <int>[];
      final bytes = _pdfBytes('locked');
      final session = await h.open(
        PickedPdfFile.fromBytes('locked.pdf', bytes),
        onPassword: (request) async {
          asked.add(request.attempt);
          expect(request.fileName, 'locked.pdf');
          return request.attempt == 1 ? 'wrong' : 'secret';
        },
      );
      expect(asked, [1, 2]);
      expect(session.info.usedPassword, isTrue);
      expect(session.willStoreDecryptedCopy, isTrue);
      final result = await session.commit(const PdfImportAsNewNote());
      expect(result.storedDecryptedCopy, isTrue);
      expect(engine.encodeCalls, 1);
      final stored = await h.gateway.readAssetBytes(result.assetId);
      expect(stored, isNot(equals(bytes)));
      expect(
        String.fromCharCodes(stored!),
        endsWith(FakePdfEngine.noSecurityMarker),
      );
      // The stored copy opens without a password (what the pool will do later).
      final reopened = await engine.open(stored, sourceName: 'asset:x');
      expect(reopened.info.usedPassword, isFalse);
      await reopened.dispose();
      // The engine document is closed, not adopted (the pool opens the copy).
      expect(h.pool.adopted, isEmpty);
      expect(engine.documents.first.isDisposed, isTrue);
    });

    test('dismissed password dialog → passwordCancelled', () async {
      final h = _Harness(engine: FakePdfEngine(userPassword: 'pw'));
      await expectLater(
        h.open(
          PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
          onPassword: (_) async => null,
        ),
        throwsA(_code(PdfErrorCode.passwordCancelled)),
      );
      await expectLater(
        h.open(PickedPdfFile.fromBytes('a.pdf', _pdfBytes())),
        throwsA(_code(PdfErrorCode.passwordCancelled)),
      );
    });

    test('more than maxPasswordAttempts → passwordCancelled', () async {
      final h = _Harness(
        engine: FakePdfEngine(userPassword: 'pw'),
        config: const PdfIoConfig(
          limits: PdfImportLimits(maxPasswordAttempts: 3),
        ),
      );
      var asked = 0;
      await expectLater(
        h.open(
          PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
          onPassword: (_) async {
            asked++;
            return 'nope';
          },
        ),
        throwsA(_code(PdfErrorCode.passwordCancelled)),
      );
      expect(asked, 3);
    });

    test(
      'permission password only → no prompt, original bytes stored',
      () async {
        final engine = FakePdfEngine(ownerPasswordOnly: true);
        final h = _Harness(engine: engine);
        var asked = 0;
        final bytes = _pdfBytes('owner');
        final session = await h.open(
          PickedPdfFile.fromBytes('owner.pdf', bytes),
          onPassword: (_) async {
            asked++;
            return 'x';
          },
        );
        expect(asked, 0);
        expect(session.info.isEncrypted, isTrue);
        expect(session.willStoreDecryptedCopy, isFalse);
        final result = await session.commit(const PdfImportAsNewNote());
        expect(result.storedDecryptedCopy, isFalse);
        expect(engine.encodeCalls, 0);
        expect(await h.gateway.readAssetBytes(result.assetId), bytes);
      },
    );

    test('refuse policy → userPasswordRefused without asking', () async {
      final h = _Harness(
        engine: FakePdfEngine(userPassword: 'pw'),
        config: const PdfIoConfig(
          userPasswordPolicy: PdfUserPasswordPolicy.refuse,
        ),
      );
      var asked = 0;
      await expectLater(
        h.open(
          PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
          onPassword: (_) async {
            asked++;
            return 'pw';
          },
        ),
        throwsA(_code(PdfErrorCode.userPasswordRefused)),
      );
      expect(asked, 0);
      expect(h.engine.openDocumentCount, 0);
    });

    test('refuse policy still opens a permission-password-only PDF', () async {
      final h = _Harness(
        engine: FakePdfEngine(ownerPasswordOnly: true),
        config: const PdfIoConfig(
          userPasswordPolicy: PdfUserPasswordPolicy.refuse,
        ),
      );
      final session = await h.open(
        PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
      );
      expect(session.info.isEncrypted, isTrue);
      await session.dispose();
    });
  });

  group('commit', () {
    test('new note: step order, progress, pages, adopt, cover', () async {
      final engine = FakePdfEngine(
        pages: const [
          PdfPageInfo(
            index: 0,
            width: 595.2755737,
            height: 841.8897705,
            rotationQuarterTurns: 0,
          ),
          PdfPageInfo(
            index: 1,
            width: 792,
            height: 612,
            rotationQuarterTurns: 1,
          ),
          PdfPageInfo(index: 2, width: 50, height: 50, rotationQuarterTurns: 0),
        ],
      );
      final h = _Harness(engine: engine);
      final bytes = _pdfBytes('three');
      final session = await h.open(PickedPdfFile.fromBytes('3쪽.pdf', bytes));
      h.progress.clear();
      final result = await session.commit(
        const PdfImportAsNewNote(folderId: 'folder-1'),
        onProgress: h.progress.add,
      );
      expect(h.progress, const [
        PdfProgress(PdfJobPhase.storingPdf),
        PdfProgress(PdfJobPhase.creatingPages, done: 0, total: 3),
        PdfProgress(PdfJobPhase.creatingPages, done: 3, total: 3),
        PdfProgress(PdfJobPhase.coverThumbnail),
      ]);
      expect(h.gateway.calls, [
        'putPdf',
        'createNote',
        'pagesOf',
        'loadPage',
        'writeThumbnail',
      ]);
      final note = (await h.gateway.getNote(result.noteId))!;
      expect(note.title, '3쪽');
      expect(note.folderId, 'folder-1');
      final pages = await h.gateway.pagesOf(result.noteId);
      expect(result.insertedPageIds, [for (final p in pages) p.id]);
      expect(result.firstPageId, pages.first.id);
      expect(result.createdNewNote, isTrue);
      expect(result.sourcePageCount, 3);
      expect(result.storedDecryptedCopy, isFalse);
      expect(await h.gateway.readAssetBytes(result.assetId), bytes);
      expect(h.gateway.assets[result.assetId]!.fileName, '3쪽.pdf');
      // 6.5: rounded to 0.001 pt; 50×50 scaled up to 72×72.
      expect(
        [for (final p in pages) p.size],
        const [
          core.PageSize(595.276, 841.89),
          core.PageSize(792, 612),
          core.PageSize(72, 72),
        ],
      );
      expect(
        [for (final p in pages) p.background],
        [
          for (var i = 0; i < 3; i++)
            core.PdfBackground(assetId: result.assetId, pdfPageIndex: i),
        ],
      );
      // 6.3 step 5: the opened document goes to the pool, still open.
      final (adoptedId, adoptedDoc) = h.pool.adopted.single;
      expect(adoptedId, result.assetId);
      expect(adoptedDoc, same(engine.documents.single));
      expect(adoptedDoc.isDisposed, isFalse);
      // dispose after commit leaves the pool's document alone.
      await session.dispose();
      expect(adoptedDoc.isDisposed, isFalse);
      expect(
        () => session.commit(const PdfImportAsNewNote()),
        throwsStateError,
      );
    });

    test('given title wins; blank title → suggested title', () async {
      final h = _Harness();
      final s1 = await h.open(PickedPdfFile.fromBytes(_nfdName, _pdfBytes()));
      final r1 = await s1.commit(const PdfImportAsNewNote(title: '내 노트'));
      expect((await h.gateway.getNote(r1.noteId))!.title, '내 노트');
      final s2 = await h.open(
        PickedPdfFile.fromBytes(_nfdName, _pdfBytes('2')),
      );
      final r2 = await s2.commit(const PdfImportAsNewNote(title: '  '));
      expect((await h.gateway.getNote(r2.noteId))!.title, '강의자료');
      final s3 = await h.open(
        PickedPdfFile.fromBytes(_nfdName, _pdfBytes('3')),
      );
      final r3 = await s3.commit(const PdfImportAsNewNote());
      expect((await h.gateway.getNote(r3.noteId))!.title, '강의자료');
    });

    test('range: only the chosen pages, ascending', () async {
      final h = _Harness(engine: FakePdfEngine(pageCount: 5));
      final session = await h.open(
        PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
      );
      final result = await session.commit(
        const PdfImportAsNewNote(),
        range: PdfPageRange.parse('4, 2-3', pageCount: 5),
      );
      final pages = await h.gateway.pagesOf(result.noteId);
      expect(
        [
          for (final p in pages)
            (p.background as core.PdfBackground).pdfPageIndex,
        ],
        [1, 2, 3],
      );
      expect(result.sourcePageCount, 5);
      // The cover is drawn from the first imported PDF page.
      expect(h.renderer.thumbnailCalls.single.pdfPageIndex, 1);
    });

    test(
      'range resolving to no page → FormatException, nothing stored',
      () async {
        final h = _Harness(engine: FakePdfEngine(pageCount: 3));
        final session = await h.open(
          PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
        );
        await expectLater(
          session.commit(
            const PdfImportAsNewNote(),
            range: PdfPageRange.parse('5-', pageCount: 9),
          ),
          throwsFormatException,
        );
        expect(h.gateway.calls, isEmpty);
        await session.dispose();
        expect(h.engine.openDocumentCount, 0);
      },
    );

    test('into a note: position passed, one insert, no cover', () async {
      final h = _Harness(engine: FakePdfEngine(pageCount: 2));
      final note = await h.gateway.createNote(
        title: 'n',
        pages: const [core.PageDraft.blankA4, core.PageDraft.blankA4],
      );
      final before = await h.gateway.pagesOf(note.id);
      h.gateway.calls.clear();
      final session = await h.open(
        PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
      );
      final result = await session.commit(
        PdfImportIntoNote(
          noteId: note.id,
          position: core.PageAfter(before.first.id),
        ),
        onProgress: h.progress.add,
      );
      expect(h.gateway.calls, ['putPdf', 'insertPages']);
      expect(result.createdNewNote, isFalse);
      expect(result.noteId, note.id);
      final after = await h.gateway.pagesOf(note.id);
      expect(
        [for (final p in after) p.id],
        [before[0].id, ...result.insertedPageIds, before[1].id],
      );
      expect(h.progress.last.phase, PdfJobPhase.creatingPages);
      expect(h.gateway.thumbnails, isEmpty);
      expect(h.pool.adopted.single.$1, result.assetId);
    });

    test(
      'into a trashed / unknown note → readOnlyNote / noteNotFound',
      () async {
        final h = _Harness();
        final note = await h.gateway.createNote(
          title: 'n',
          pages: const [core.PageDraft.blankA4],
        );
        h.gateway.trashNote(note.id);
        final session = await h.open(
          PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
        );
        await expectLater(
          session.commit(
            PdfImportIntoNote(
              noteId: note.id,
              position: const core.PageAtEnd(),
            ),
          ),
          throwsA(_code(PdfErrorCode.readOnlyNote)),
        );
        await expectLater(
          session.commit(
            const PdfImportIntoNote(
              noteId: 'missing',
              position: core.PageAtEnd(),
            ),
          ),
          throwsA(_code(PdfErrorCode.noteNotFound)),
        );
        expect(h.pool.adopted, isEmpty);
        await session.dispose();
        expect(h.engine.openDocumentCount, 0);
      },
    );
  });

  group('cover (6.3 step 6, 6.9)', () {
    test('own path: PNG on paper, long side 512, contentRevision', () async {
      final h = _Harness(engine: FakePdfEngine(pageCount: 2));
      final session = await h.open(
        PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
      );
      final result = await session.commit(const PdfImportAsNewNote());
      final call = h.renderer.thumbnailCalls.single;
      expect(call.assetId, result.assetId);
      expect(call.pdfPageIndex, 0);
      expect(call.longSidePx, 512);
      final thumb = h.gateway.thumbnails[result.firstPageId]!;
      final page = (await h.gateway.pagesOf(result.noteId)).first;
      expect(thumb.pageId, page.id);
      expect(thumb.contentRevision, page.contentRevision);
      expect(thumb.mimeType, 'image/png');
      expect(thumb.height, 512);
      expect(thumb.width, (595.276 / 841.89 * 512).round());
      final codec = await ui.instantiateImageCodec(thumb.bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, thumb.width);
      expect(frame.image.height, thumb.height);
      frame.image.dispose();
      codec.dispose();
      expect(h.gateway.thumbnails, hasLength(1));
    });

    test('thumbnailRenderer present → used instead of the own path', () async {
      final h = _Harness(withThumbnailRenderer: true);
      final session = await h.open(
        PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
      );
      final result = await session.commit(const PdfImportAsNewNote());
      expect(h.thumbnailRenderer!.calls, [(result.firstPageId, 512)]);
      expect(h.renderer.thumbnailCalls, isEmpty);
      expect(h.gateway.thumbnails[result.firstPageId]!.bytes, [1, 2, 3]);
    });

    test('generateCoverThumbnail false → no cover', () async {
      final h = _Harness(
        config: const PdfIoConfig(generateCoverThumbnail: false),
      );
      final session = await h.open(
        PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
      );
      await session.commit(
        const PdfImportAsNewNote(),
        onProgress: h.progress.add,
      );
      expect(h.gateway.calls, ['putPdf', 'createNote', 'pagesOf']);
      expect(
        h.progress.map((p) => p.phase),
        isNot(contains(PdfJobPhase.coverThumbnail)),
      );
    });

    test('null cover → nothing written, nothing reported', () async {
      final h1 = _Harness(withThumbnailRenderer: true);
      h1.thumbnailRenderer!.returnNull = true;
      final h2 = _Harness()..renderer.returnNull = true;
      final reports = await _captureReports(() async {
        for (final h in [h1, h2]) {
          final session = await h.open(
            PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
          );
          await session.commit(const PdfImportAsNewNote());
          expect(h.gateway.thumbnails, isEmpty);
        }
      });
      expect(reports, isEmpty);
    });

    test('cover failure is reported once and the import succeeds', () async {
      final h1 = _Harness(withThumbnailRenderer: true);
      h1.thumbnailRenderer!.error = StateError('ink');
      final h2 = _Harness()..renderer.error = StateError('render');
      final results = <PdfImportResult>[];
      final reports = await _captureReports(() async {
        for (final h in [h1, h2]) {
          final session = await h.open(
            PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
          );
          results.add(await session.commit(const PdfImportAsNewNote()));
          expect(h.gateway.thumbnails, isEmpty);
        }
      });
      expect(results, hasLength(2));
      expect(reports, hasLength(2));
      for (final report in reports) {
        expect(report.library, 'pdf_io');
        expect(report.exception, isA<StateError>());
      }
    });
  });

  group('cancel', () {
    test('already cancelled → cancelled before reading', () async {
      final h = _Harness();
      var reads = 0;
      final file = PickedPdfFile(
        name: 'a.pdf',
        readBytes: () async {
          reads++;
          return _pdfBytes();
        },
      );
      await expectLater(
        h.open(file, cancel: PdfCancelSignal()..cancel()),
        throwsA(_code(PdfErrorCode.cancelled)),
      );
      expect(reads, 0);
    });

    test('while reading → cancelled at once', () async {
      final h = _Harness();
      final reading = Completer<Uint8List>();
      final cancel = PdfCancelSignal();
      final opening = h.open(
        PickedPdfFile(name: 'a.pdf', readBytes: () => reading.future),
        cancel: cancel,
      );
      await pumpEventQueue();
      cancel.cancel();
      await expectLater(opening, throwsA(_code(PdfErrorCode.cancelled)));
      reading.complete(_pdfBytes());
      await pumpEventQueue();
      expect(h.engine.openCalls, isEmpty);
    });

    test(
      'while opening → cancelled at once; the late document is closed',
      () async {
        final gate = Completer<void>();
        final engine = FakePdfEngine()..beforeOpen = (_) => gate.future;
        final h = _Harness(engine: engine);
        final cancel = PdfCancelSignal();
        final opening = h.open(
          PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
          cancel: cancel,
        );
        await pumpEventQueue();
        expect(engine.openCalls, hasLength(1));
        cancel.cancel();
        await expectLater(opening, throwsA(_code(PdfErrorCode.cancelled)));
        gate.complete();
        await pumpEventQueue();
        expect(engine.documents, hasLength(1));
        expect(engine.openDocumentCount, 0);
      },
    );

    test('while the password dialog is up → cancelled', () async {
      final h = _Harness(engine: FakePdfEngine(userPassword: 'pw'));
      final dialog = Completer<String?>();
      final cancel = PdfCancelSignal();
      final opening = h.open(
        PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
        cancel: cancel,
        onPassword: (_) => dialog.future,
      );
      await pumpEventQueue();
      cancel.cancel();
      await expectLater(opening, throwsA(_code(PdfErrorCode.cancelled)));
      dialog.complete(null);
      await pumpEventQueue();
      expect(h.engine.openDocumentCount, 0);
    });

    test(
      'commit with a cancelled signal → cancelled, nothing stored',
      () async {
        final h = _Harness();
        final session = await h.open(
          PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
        );
        await expectLater(
          session.commit(
            const PdfImportAsNewNote(),
            cancel: PdfCancelSignal()..cancel(),
          ),
          throwsA(_code(PdfErrorCode.cancelled)),
        );
        expect(h.gateway.calls, isEmpty);
        await session.dispose();
        expect(h.engine.openDocumentCount, 0);
      },
    );

    test(
      'after storing, before the pages (last cancel point) → cancelled',
      () async {
        final h = _Harness();
        final session = await h.open(
          PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
        );
        final cancel = PdfCancelSignal();
        await expectLater(
          session.commit(
            const PdfImportAsNewNote(),
            cancel: cancel,
            onProgress: (p) {
              if (p.phase == PdfJobPhase.creatingPages) cancel.cancel();
            },
          ),
          throwsA(_code(PdfErrorCode.cancelled)),
        );
        expect(h.gateway.calls, ['putPdf']);
        expect(h.pool.adopted, isEmpty);
        await session.dispose();
        expect(h.engine.openDocumentCount, 0);
      },
    );

    test('once createNote is called the commit is not cancellable', () async {
      final h = _Harness();
      final session = await h.open(
        PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
      );
      final cancel = PdfCancelSignal();
      var held = false;
      final committing = session.commit(
        const PdfImportAsNewNote(),
        cancel: cancel,
        onProgress: (p) {
          if (p == const PdfProgress(PdfJobPhase.creatingPages, total: 3)) {
            h.gateway.holdWrites();
            held = true;
          }
        },
      );
      await pumpEventQueue();
      expect(held, isTrue);
      expect(h.gateway.calls.last, 'createNote');
      expect(h.gateway.heldWriteCount, 1);
      cancel.cancel();
      h.gateway.releaseWrites();
      final result = await committing;
      expect(result.insertedPageIds, hasLength(3));
    });

    test('PDF-3-1: cancel while putPdf waits (held write) → cancelled at once', () async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final h = _Harness();
        final session = await h.open(
          PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
        );
        h.gateway.holdWrites();
        final cancel = PdfCancelSignal();
        final committing = session.commit(
          const PdfImportAsNewNote(),
          cancel: cancel,
        );
        await pumpEventQueue();
        expect(h.gateway.calls, ['putPdf']);
        expect(h.gateway.heldWriteCount, 1);
        cancel.cancel();
        // Still held: only the race with the cancel signal can end the commit.
        await expectLater(committing, throwsA(_code(PdfErrorCode.cancelled)));
        expect(h.gateway.calls, ['putPdf']);
        expect(h.gateway.calls, isNot(contains('createNote')));
        expect(h.gateway.calls, isNot(contains('insertPages')));
        h.gateway.releaseWrites();
        await pumpEventQueue();
        // The late put stored an asset no page points at (CORE GC later — 6.3).
        expect(h.gateway.assets, hasLength(1));
        expect(h.pool.adopted, isEmpty);
        await session.dispose();
        expect(h.engine.openDocumentCount, 0);
      }, (error, stack) => errors.add(error));
      expect(errors, isEmpty);
    });

    test(
      'dispose during a held commit: the commit closes the document',
      () async {
        final h = _Harness();
        final session = await h.open(
          PickedPdfFile.fromBytes('a.pdf', _pdfBytes()),
        );
        h.gateway.holdWrites();
        final committing = session.commit(const PdfImportAsNewNote());
        await pumpEventQueue();
        await session.dispose();
        expect(h.engine.openDocumentCount, 1); // the commit still uses it
        h.gateway.releaseWrites();
        final result = await committing;
        expect(result.insertedPageIds, hasLength(3));
        expect(h.pool.adopted, isEmpty);
        expect(h.engine.openDocumentCount, 0);
      },
    );
  });
}
