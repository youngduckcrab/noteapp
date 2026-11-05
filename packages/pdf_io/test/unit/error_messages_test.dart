// Korean UI texts (06-pdf 6.14, 8 T1): every error code, result-sheet page lists, storage delay.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/ui/strings_ko.dart';

void main() {
  test('every PdfErrorCode has its 6.14 message', () {
    const expected = {
      PdfErrorCode.notPdf: 'PDF 파일이 아니에요.',
      PdfErrorCode.tooLarge: 'PDF가 너무 커요. 최대 300MB까지 가져올 수 있어요.',
      PdfErrorCode.tooManyPages: '페이지가 너무 많아요. 최대 2000쪽까지 가져올 수 있어요.',
      PdfErrorCode.passwordCancelled: '암호를 입력하지 않아 PDF를 열지 않았어요.',
      PdfErrorCode.userPasswordRefused: '암호가 걸린 PDF는 가져오지 않도록 설정되어 있어요.',
      PdfErrorCode.corrupt: 'PDF를 열 수 없어요. 파일이 손상되었을 수 있어요.',
      PdfErrorCode.engineUnavailable:
          'PDF 엔진을 불러오지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.',
      PdfErrorCode.assetMissing: '이 기기에 PDF 원본이 없어요.',
      PdfErrorCode.noteNotFound: '노트를 찾을 수 없어요.',
      PdfErrorCode.readOnlyNote: '읽기 전용 노트라 페이지를 넣을 수 없어요.',
      PdfErrorCode.storageFailed: 'PDF를 저장하지 못했어요. 저장 공간을 확인해 주세요.',
      PdfErrorCode.exportFailed: 'PDF를 만들지 못했어요.',
      PdfErrorCode.pickerFailed: '파일을 읽지 못했어요.',
      PdfErrorCode.cancelled: '취소했어요.',
      PdfErrorCode.busy: '다른 PDF 작업이 진행 중이에요.',
      PdfErrorCode.unsupportedPlatform: '이 기기에서는 아직 지원하지 않아요.',
    };
    expect(expected.keys.toSet(), PdfErrorCode.values.toSet());
    for (final code in PdfErrorCode.values) {
      expect(
        PdfIoException(code).userMessage,
        expected[code],
        reason: code.name,
      );
    }
  });

  test('assetMissing shows the page list from detail', () {
    expect(
      const PdfIoException(
        PdfErrorCode.assetMissing,
        detail: '3, 5',
      ).userMessage,
      '이 기기에 PDF 원본이 없어요. (3, 5쪽)',
    );
  });

  test('{max} follows the import limits', () {
    const limits = PdfImportLimits(maxBytes: 100 * 1024 * 1024, maxPages: 500);
    expect(
      PdfStringsKo.errorMessage(PdfErrorCode.tooLarge, limits: limits),
      'PDF가 너무 커요. 최대 100MB까지 가져올 수 있어요.',
    );
    expect(
      PdfStringsKo.errorMessage(PdfErrorCode.tooManyPages, limits: limits),
      '페이지가 너무 많아요. 최대 500쪽까지 가져올 수 있어요.',
    );
    expect(PdfStringsKo.megabytes(1536 * 1024), '1.5');
  });

  test('result sheet page list: runs with an en dash', () {
    expect(PdfStringsKo.pageList([3, 5, 7, 8, 9]), '3, 5, 7–9');
    expect(PdfStringsKo.pageList([9, 7, 8, 3, 5, 5]), '3, 5, 7–9');
    expect(PdfStringsKo.pageList([1]), '1');
    expect(PdfStringsKo.pageList([1, 2]), '1–2');
    expect(
      PdfStringsKo.missingPagesWarning([3, 5, 7, 8, 9]),
      '3, 5, 7–9쪽은 원본이 없어 빈 페이지로 넣었어요',
    );
  });

  test("more than 10 entries → '외 n쪽'", () {
    // 12 separate pages: 10 shown, 2 left out.
    final pages = [for (var i = 1; i <= 12; i++) i * 2];
    expect(
      PdfStringsKo.pageList(pages),
      '2, 4, 6, 8, 10, 12, 14, 16, 18, 20 외 2쪽',
    );
    // The left-out entries count their pages: 11 runs, the last one 30–33 (4 pages).
    final runs = [for (var i = 1; i <= 10; i++) i * 2, 30, 31, 32, 33];
    expect(PdfStringsKo.pageList(runs), endsWith('20 외 4쪽'));
    expect(
      PdfStringsKo.missingPagesWarning(pages),
      '2, 4, 6, 8, 10, 12, 14, 16, 18, 20 외 2쪽은 원본이 없어 빈 페이지로 넣었어요',
    );
    // Exactly 10 entries: no cut.
    expect(
      PdfStringsKo.pageList(pages.take(10).toList()),
      isNot(contains('외')),
    );
  });

  test('storage delay text and its button (6.3, 6.14)', () {
    expect(PdfStringsKo.storageDelay, '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.');
    expect(PdfStringsKo.close, '닫기');
  });

  test('progress labels', () {
    expect(const PdfProgress(PdfJobPhase.openingPdf).label, 'PDF 여는 중');
    expect(
      const PdfProgress(PdfJobPhase.composing, done: 12, total: 40).label,
      '페이지 합성 중 (12/40)',
    );
    for (final phase in PdfJobPhase.values) {
      expect(PdfProgress(phase).label, isNotEmpty, reason: phase.name);
    }
    expect(
      const PdfBatchProgress(
        noteIndex: 1,
        noteCount: 5,
        current: PdfProgress(PdfJobPhase.composing, done: 12, total: 40),
      ).label,
      '노트 2/5 · 페이지 합성 중 (12/40)',
    );
  });

  test('batch and background texts', () {
    expect(
      PdfStringsKo.batchSummary(noteCount: 5, doneCount: 3),
      '노트 5개 중 3개를 PDF로 만들었어요',
    );
    expect(
      PdfStringsKo.batchStoppedAtSizeLimit(2),
      '용량이 커서 나머지 2개는 만들지 않았어요. 나눠서 내보내 주세요',
    );
    expect(PdfStringsKo.batchCancelled(2), '취소해서 나머지 2개는 만들지 않았어요');
    expect(PdfStringsKo.backgroundDownloading(42), 'PDF 원본을 받는 중이에요 (42%)');
    expect(PdfStringsKo.backgroundDownloading(null), 'PDF 원본을 받는 중이에요');
  });
}
