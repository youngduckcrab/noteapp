// The native app's PDF share (lib/src/modules/pdf_share_native.dart): the
// share_plus call is given (no platform channel) — every result as a PDF file
// named after it, the title, an iPad popover origin, and the share result →
// PdfOutputOutcome.
@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:noteapp/src/modules/pdf_share.dart' as conditional;
import 'package:noteapp/src/modules/pdf_share_native.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:share_plus/share_plus.dart';

PdfExportResult _result(String name) => PdfExportResult(
  bytes: Uint8List.fromList([1, 2, 3]),
  fileName: name,
  pageCount: 1,
  elapsed: Duration.zero,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('VM / native: platformPdfShare is sharePdfFiles', () {
    expect(conditional.platformPdfShare, same(sharePdfFiles));
  });

  test(
    'every result as a PDF XFile named after it; the title; the origin',
    () async {
      final calls = <ShareParams>[];
      final outcome = await sharePdfFilesWith(
        [_result('미적분 3강.pdf'), _result('선형대수.pdf')],
        share: (params) async {
          calls.add(params);
          return const ShareResult(
            'com.example.mail',
            ShareResultStatus.success,
          );
        },
        origin: const Rect.fromLTWH(10, 20, 2, 2),
      );
      expect(outcome, PdfOutputOutcome.done);
      final params = calls.single;
      expect(params.files, hasLength(2));
      expect(
        params.files!.map((f) => f.mimeType),
        everyElement('application/pdf'),
      );
      expect(await params.files!.first.readAsBytes(), [1, 2, 3]);
      expect(params.fileNameOverrides, ['미적분 3강.pdf', '선형대수.pdf']);
      expect(params.title, 'PDF 2개');
      expect(params.sharePositionOrigin, const Rect.fromLTWH(10, 20, 2, 2));
    },
  );

  test('one file: its name as the title; the default origin is a non-empty '
      'rect inside the window (iPad popover)', () async {
    final calls = <ShareParams>[];
    await sharePdfFilesWith(
      [_result('n.pdf')],
      share: (params) async {
        calls.add(params);
        return const ShareResult('', ShareResultStatus.dismissed);
      },
    );
    expect(calls.single.title, 'n.pdf');
    final origin = calls.single.sharePositionOrigin!;
    expect(origin.isEmpty, isFalse);
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    expect((Offset.zero & size).contains(origin.center), isTrue);
  });

  test('share result → outcome: dismissed → dismissedByUser, unavailable → '
      'done; a throw is left to the sink (it answers failed)', () async {
    Future<PdfOutputOutcome> run(ShareResultStatus status) => sharePdfFilesWith(
      [_result('n.pdf')],
      share: (_) async => ShareResult('', status),
      origin: const Rect.fromLTWH(0, 0, 2, 2),
    );
    expect(
      await run(ShareResultStatus.dismissed),
      PdfOutputOutcome.dismissedByUser,
    );
    expect(await run(ShareResultStatus.unavailable), PdfOutputOutcome.done);
    expect(await run(ShareResultStatus.success), PdfOutputOutcome.done);
    await expectLater(
      sharePdfFilesWith(
        [_result('n.pdf')],
        share: (_) async => throw StateError('busy'),
        origin: const Rect.fromLTWH(0, 0, 2, 2),
      ),
      throwsStateError,
    );
  });
}
