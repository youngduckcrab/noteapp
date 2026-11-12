// The native output sink (output_sink_native.dart — Android / iOS app builds): available
// actions (저장 = download for one file, 공유 only with the app's PdfShareFiles), save done /
// cancelled / failed through a fake save dialog and through a scripted file_picker platform
// (the default FilePicker.saveFile path, no platform channel), share of every result and its
// failures, pdfShareFilesProvider → the sink, and the result sheet's 저장 / 공유 buttons
// (one file: both; several: 모두 공유 + 저장 per file).
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/output/output_sink_native.dart';
import 'package:pdf_io/src/ui/export_sheets.dart';

PdfExportResult _result(String name, [int size = 4]) => PdfExportResult(
  bytes: Uint8List.fromList(List.filled(size, 7)),
  fileName: name,
  pageCount: 1,
  elapsed: Duration.zero,
);

/// The save dialog: records each call and answers with [answer] (a Uri, null = closed, or
/// an error to throw).
final class _SaveDialog {
  _SaveDialog(this.answer);

  /// A Uri, null (closed) or an Error (thrown).
  Object? answer;
  final List<({String fileName, Uint8List bytes, String mimeType})> calls = [];

  Future<Uri?> call({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    calls.add((fileName: fileName, bytes: bytes, mimeType: mimeType));
    final a = answer;
    if (a is Uri?) return a;
    throw a as Error;
  }
}

/// The app's share: records each call and answers with [answer] (an outcome or an error).
final class _Share {
  _Share([this.answer = PdfOutputOutcome.done]);

  Object answer;
  final List<List<PdfExportResult>> calls = [];

  Future<PdfOutputOutcome> call(List<PdfExportResult> results) async {
    calls.add(results);
    final a = answer;
    if (a is PdfOutputOutcome) return a;
    throw a as Error;
  }
}

/// file_picker's platform with a scripted saveFile (the default save path of the sink).
final class _ScriptedSavePicker extends FilePickerPlatform {
  _ScriptedSavePicker(this.answer);

  final Uri? answer;
  final List<({String fileName, int bytes, String mimeType})> calls = [];

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    // file_picker's own parameter type (untyped return).
    // ignore: inference_failure_on_function_return_type
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls.add((fileName: fileName, bytes: bytes.length, mimeType: mimeType));
    return answer;
  }
}

void main() {
  final a = _result('미적분 3강.pdf');
  final b = _result('선형대수.pdf');

  group('availableActions', () {
    test('no share: 저장 (download) for one file only', () {
      final sink = NativePdfOutputSink(saveFile: _SaveDialog(null).call);
      expect(sink.availableActions(const []), isEmpty);
      expect(sink.availableActions([a]), {PdfOutputAction.download});
      expect(sink.availableActions([a, b]), isEmpty);
    });

    test('with the app share: 공유 for any number of files, 저장 for one', () {
      final sink = NativePdfOutputSink(
        share: _Share().call,
        saveFile: _SaveDialog(null).call,
      );
      expect(sink.availableActions(const []), isEmpty);
      expect(sink.availableActions([a]), {
        PdfOutputAction.share,
        PdfOutputAction.download,
      });
      expect(sink.availableActions([a, b]), {PdfOutputAction.share});
    });

    test('an unavailable action throws ArgumentError (no call made)', () {
      final save = _SaveDialog(Uri.parse('content://x/1'));
      final sink = NativePdfOutputSink(saveFile: save.call);
      expect(
        () => sink.deliver([a], PdfOutputAction.openInNewTab),
        throwsArgumentError,
      );
      expect(
        () => sink.deliver([a], PdfOutputAction.share),
        throwsArgumentError,
      );
      expect(
        () => sink.deliver([a, b], PdfOutputAction.download),
        throwsArgumentError,
      );
      expect(save.calls, isEmpty);
    });

    test('labels: download is 저장 natively', () {
      final sink = NativePdfOutputSink();
      expect(sink.labelOf(PdfOutputAction.download), '저장');
      expect(sink.labelOf(PdfOutputAction.share), '공유');
    });
  });

  group('저장 (download → the system save dialog)', () {
    test(
      'saved → done; the dialog gets the name, the bytes and the PDF type',
      () async {
        final save = _SaveDialog(Uri.parse('content://docs/document/42'));
        final sink = NativePdfOutputSink(saveFile: save.call);
        expect(
          await sink.deliver([a], PdfOutputAction.download),
          PdfOutputOutcome.done,
        );
        expect(save.calls.single.fileName, '미적분 3강.pdf');
        expect(save.calls.single.bytes, same(a.bytes));
        expect(save.calls.single.mimeType, 'application/pdf');
      },
    );

    test('dialog closed (null) → dismissedByUser', () async {
      final sink = NativePdfOutputSink(saveFile: _SaveDialog(null).call);
      expect(
        await sink.deliver([a], PdfOutputAction.download),
        PdfOutputOutcome.dismissedByUser,
      );
    });

    test('the dialog throws → failed (no throw out of deliver)', () async {
      final sink = NativePdfOutputSink(
        saveFile: _SaveDialog(StateError('no activity')).call,
      );
      expect(
        await sink.deliver([a], PdfOutputAction.download),
        PdfOutputOutcome.failed,
      );
    });

    test('the default goes through file_picker FilePicker.saveFile', () async {
      final previous = FilePickerPlatform.instance;
      addTearDown(() => FilePickerPlatform.instance = previous);
      final saved = _ScriptedSavePicker(Uri.file('/docs/미적분 3강.pdf'));
      FilePickerPlatform.instance = saved;
      expect(
        await NativePdfOutputSink().deliver([a], PdfOutputAction.download),
        PdfOutputOutcome.done,
      );
      expect(saved.calls.single, (
        fileName: '미적분 3강.pdf',
        bytes: 4,
        mimeType: 'application/pdf',
      ));

      final cancelled = _ScriptedSavePicker(null);
      FilePickerPlatform.instance = cancelled;
      expect(
        await NativePdfOutputSink().deliver([a], PdfOutputAction.download),
        PdfOutputOutcome.dismissedByUser,
      );
    });
  });

  group('공유 (the app share)', () {
    test('every result at once; the share outcome is passed on', () async {
      final share = _Share();
      final sink = NativePdfOutputSink(share: share.call);
      expect(
        await sink.deliver([a, b], PdfOutputAction.share),
        PdfOutputOutcome.done,
      );
      expect(share.calls.single, [same(a), same(b)]);
      share.answer = PdfOutputOutcome.dismissedByUser;
      expect(
        await sink.deliver([a], PdfOutputAction.share),
        PdfOutputOutcome.dismissedByUser,
      );
    });

    test('the share throws → failed', () async {
      final sink = NativePdfOutputSink(
        share: _Share(StateError('share sheet busy')).call,
      );
      expect(
        await sink.deliver([a], PdfOutputAction.share),
        PdfOutputOutcome.failed,
      );
    });

    test(
      'pdfShareFilesProvider reaches the platform sink (VM = native)',
      () async {
        final share = _Share();
        final container = ProviderContainer.test(
          overrides: [pdfShareFilesProvider.overrideWithValue(share.call)],
        );
        final sink = container.read(pdfOutputSinkProvider);
        expect(sink, isA<NativePdfOutputSink>());
        expect(sink.availableActions([a, b]), {PdfOutputAction.share});
        await sink.deliver([a, b], PdfOutputAction.share);
        expect(share.calls, hasLength(1));
        expect(
          ProviderContainer.test().read(pdfOutputSinkProvider).availableActions(
            [a],
          ),
          {PdfOutputAction.download},
        );
      },
    );
  });

  group('result sheet with the native sink', () {
    Future<void> pump(
      WidgetTester tester,
      PdfOutputSink sink,
      List<PdfExportResult> results,
    ) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfExportResultSheet(
            sink: sink,
            title: '${results.length}',
            files: [for (final r in results) PdfResultFile(r)],
          ),
        ),
      ),
    );

    testWidgets('one file: 공유 and 저장 (no 다운로드 / 새 탭에서 열기); taps deliver', (
      tester,
    ) async {
      final share = _Share();
      final save = _SaveDialog(Uri.parse('content://docs/1'));
      final sink = NativePdfOutputSink(share: share.call, saveFile: save.call);
      await pump(tester, sink, [a]);
      expect(find.widgetWithText(FilledButton, '공유'), findsOneWidget);
      expect(find.text('저장'), findsOneWidget);
      expect(find.text('다운로드'), findsNothing);
      expect(find.text('새 탭에서 열기'), findsNothing);

      await tester.tap(find.text('저장'));
      await tester.pump();
      expect(save.calls.single.fileName, '미적분 3강.pdf');
      await tester.tap(find.text('공유'));
      await tester.pump();
      expect(share.calls.single, [same(a)]);
      expect(find.text('파일을 넘기지 못했어요. 다시 시도해 주세요.'), findsNothing);
    });

    testWidgets(
      'a failed save shows the failure line; a closed dialog nothing',
      (tester) async {
        final save = _SaveDialog(StateError('boom'));
        await pump(tester, NativePdfOutputSink(saveFile: save.call), [a]);
        await tester.tap(find.text('저장'));
        await tester.pump();
        expect(find.text('파일을 넘기지 못했어요. 다시 시도해 주세요.'), findsOneWidget);

        save.answer = null;
        await tester.tap(find.text('저장'));
        await tester.pump();
        expect(find.text('파일을 넘기지 못했어요. 다시 시도해 주세요.'), findsNothing);
      },
    );

    testWidgets('several files: 모두 공유 + 저장 on each file', (tester) async {
      final share = _Share();
      final save = _SaveDialog(Uri.parse('content://docs/1'));
      final sink = NativePdfOutputSink(share: share.call, saveFile: save.call);
      await pump(tester, sink, [a, b]);
      expect(find.text('모두 공유'), findsOneWidget);
      expect(find.text('저장'), findsNWidgets(2));
      expect(find.text('다운로드'), findsNothing);

      await tester.tap(find.text('모두 공유'));
      await tester.pump();
      expect(share.calls.single, [same(a), same(b)]);
      await tester.tap(find.text('저장').last);
      await tester.pump();
      expect(save.calls.single.fileName, '선형대수.pdf');
    });

    testWidgets('no app share (e.g. a test container): 저장 only', (
      tester,
    ) async {
      await pump(
        tester,
        NativePdfOutputSink(saveFile: _SaveDialog(null).call),
        [a],
      );
      expect(find.text('저장'), findsOneWidget);
      expect(find.text('공유'), findsNothing);
    });
  });
}
