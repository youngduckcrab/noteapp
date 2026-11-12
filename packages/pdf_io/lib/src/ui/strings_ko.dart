// lib/src/ui/strings_ko.dart — internal (not exported), 06-pdf 6.14. Every Korean UI text
// of pdf_io (polite 해요체) lives here so the wording is reviewed in one place.
import '../common/progress.dart';
import '../config.dart';
import '../errors.dart';
import '../tuning.dart';

abstract final class PdfStringsKo {
  // ---------------------------------------------------------------- errors (6.14)

  /// PdfIoException.userMessage. {max} of tooLarge / tooManyPages comes from [limits]
  /// (the config given to initializePdfIo); {detail} of assetMissing is the page list.
  static String errorMessage(
    PdfErrorCode code, {
    String? detail,
    PdfImportLimits limits = const PdfImportLimits(),
  }) => switch (code) {
    PdfErrorCode.notPdf => 'PDF 파일이 아니에요.',
    PdfErrorCode.tooLarge =>
      'PDF가 너무 커요. 최대 ${megabytes(limits.maxBytes)}MB까지 가져올 수 있어요.',
    PdfErrorCode.tooManyPages =>
      '페이지가 너무 많아요. 최대 ${limits.maxPages}쪽까지 가져올 수 있어요.',
    PdfErrorCode.passwordCancelled => '암호를 입력하지 않아 PDF를 열지 않았어요.',
    PdfErrorCode.userPasswordRefused => '암호가 걸린 PDF는 가져오지 않도록 설정되어 있어요.',
    PdfErrorCode.corrupt => 'PDF를 열 수 없어요. 파일이 손상되었을 수 있어요.',
    PdfErrorCode.engineUnavailable =>
      'PDF 엔진을 불러오지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.',
    PdfErrorCode.assetMissing =>
      detail == null || detail.isEmpty
          ? '이 기기에 PDF 원본이 없어요.'
          // A cut page list (pageList) already ends with '외 n쪽'.
          : '이 기기에 PDF 원본이 없어요. '
                '($detail${detail.endsWith('쪽') ? '' : '쪽'})',
    PdfErrorCode.noteNotFound => '노트를 찾을 수 없어요.',
    PdfErrorCode.readOnlyNote => '읽기 전용 노트라 페이지를 넣을 수 없어요.',
    PdfErrorCode.storageFailed => 'PDF를 저장하지 못했어요. 저장 공간을 확인해 주세요.',
    PdfErrorCode.exportFailed =>
      detail == fontsUnavailableDetail
          ? '글꼴을 받지 못해 내보낼 수 없어요. 인터넷에 연결한 뒤 다시 해 주세요.'
          : 'PDF를 만들지 못했어요.',
    PdfErrorCode.pickerFailed => '파일을 읽지 못했어요.',
    PdfErrorCode.cancelled => '취소했어요.',
    PdfErrorCode.busy => '다른 PDF 작업이 진행 중이에요.',
    PdfErrorCode.unsupportedPlatform => '이 기기에서는 아직 지원하지 않아요.',
  };

  /// (2차, m5-7/06-pdf 6.2.2 S-12) PdfIoException.detail of the web export stop without NoteSans
  /// (code exportFailed — the message above is picked by this detail).
  static const String fontsUnavailableDetail = 'fonts-unavailable';

  /// Bytes → MiB text: whole numbers without a fraction, otherwise one decimal.
  static String megabytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    final rounded = mb.roundToDouble();
    if ((mb - rounded).abs() < 0.05) return rounded.toStringAsFixed(0);
    return mb.toStringAsFixed(1);
  }

  // ---------------------------------------------------------------- progress (4.2, 6.3)

  static String phaseLabel(PdfJobPhase phase) => switch (phase) {
    PdfJobPhase.readingFile => '파일 읽는 중',
    PdfJobPhase.openingPdf => 'PDF 여는 중',
    PdfJobPhase.storingPdf => '저장 중',
    PdfJobPhase.creatingPages => '페이지 만드는 중',
    PdfJobPhase.coverThumbnail => '표지 만드는 중',
    PdfJobPhase.preparingExport => '내보낼 준비 중',
    PdfJobPhase.composing => '페이지 합성 중',
    PdfJobPhase.finishingExport => 'PDF 마무리 중',
  };

  /// 'PDF 여는 중', '페이지 합성 중 (12/40)' (count only when total > 0).
  static String progressLabel(PdfProgress progress) {
    final phase = phaseLabel(progress.phase);
    if (progress.total <= 0) return phase;
    return '$phase (${progress.done}/${progress.total})';
  }

  /// '노트 2/5 · 페이지 합성 중 (12/40)'
  static String batchProgressLabel(PdfBatchProgress progress) =>
      '노트 ${progress.noteIndex + 1}/${progress.noteCount} · '
      '${progressLabel(progress.current)}';

  // ---------------------------------------------------------------- background (6.7.7, 6.8)

  static const String backgroundNoSource = 'PDF 원본이 이 기기에 없어요';

  /// [percent] null when the total size is unknown (the % is left out).
  static String backgroundDownloading(int? percent) =>
      percent == null ? 'PDF 원본을 받는 중이에요' : 'PDF 원본을 받는 중이에요 ($percent%)';

  static const String backgroundWaiting = '다른 기기에서 PDF 원본을 올리는 중이에요';
  static const String backgroundOffline = '오프라인이라 PDF 원본을 받을 수 없어요';
  static const String backgroundDownloadFailed = 'PDF 원본을 받지 못했어요';
  static const String backgroundNeedsPassword = '암호가 필요한 PDF예요';
  static const String backgroundRenderFailed = 'PDF 페이지를 표시할 수 없어요';

  // ---------------------------------------------------------------- result sheets (6.12, 6.14)

  /// 1-based page numbers → '3, 5, 7–9' (runs joined with an en dash). More than
  /// PdfTuning.missingPagesListMax entries → the first ones and ' 외 n쪽' (n = pages left out).
  static String pageList(List<int> pageNumbers) {
    final pages = pageNumbers.toSet().toList()..sort();
    final runs = <(int, int)>[];
    for (final p in pages) {
      if (runs.isNotEmpty && runs.last.$2 + 1 == p) {
        runs[runs.length - 1] = (runs.last.$1, p);
      } else {
        runs.add((p, p));
      }
    }
    String runText((int, int) r) =>
        r.$1 == r.$2 ? '${r.$1}' : '${r.$1}–${r.$2}';
    const max = PdfTuning.missingPagesListMax;
    if (runs.length <= max) return runs.map(runText).join(', ');
    final shown = runs.take(max).map(runText).join(', ');
    var rest = 0;
    for (final r in runs.skip(max)) {
      rest += r.$2 - r.$1 + 1;
    }
    return '$shown 외 $rest쪽';
  }

  /// '{pages}쪽은 원본이 없어 빈 페이지로 넣었어요' (a cut list already ends with '외 n쪽').
  static String missingPagesWarning(List<int> notePageNumbers) {
    final list = pageList(notePageNumbers);
    final pages = list.endsWith('쪽') ? list : '$list쪽';
    return '$pages은 원본이 없어 빈 페이지로 넣었어요';
  }

  /// (2차, m5-7/06-pdf 4.1.5) '{pages}쪽의 이미지는 이 기기에 원본이 없거나 읽지 못해 빠졌어요'.
  static String missingImagesWarning(List<int> notePageNumbers) =>
      '${_pagesOf(notePageNumbers)}의 이미지는 이 기기에 원본이 없거나 읽지 못해 빠졌어요';

  /// (2차) '{pages}쪽의 텍스트 상자 일부는 그림으로 넣었어요 — PDF에서 검색되지 않아요'.
  static String rasterizedTextWarning(List<int> notePageNumbers) =>
      '${_pagesOf(notePageNumbers)}의 텍스트 상자 일부는 그림으로 넣었어요 — PDF에서 검색되지 않아요';

  /// (2차) '{pages}쪽의 수식 일부를 그리지 못해 빠졌어요'.
  static String skippedFormulasWarning(List<int> notePageNumbers) =>
      '${_pagesOf(notePageNumbers)}의 수식 일부를 그리지 못해 빠졌어요';

  /// pageList + '쪽' (a cut list already ends with '외 n쪽').
  static String _pagesOf(List<int> notePageNumbers) {
    final list = pageList(notePageNumbers);
    return list.endsWith('쪽') ? list : '$list쪽';
  }

  static String batchSummary({
    required int noteCount,
    required int doneCount,
  }) => '노트 $noteCount개 중 $doneCount개를 PDF로 만들었어요';

  static String batchStoppedAtSizeLimit(int notReachedCount) =>
      '용량이 커서 나머지 $notReachedCount개는 만들지 않았어요. 나눠서 내보내 주세요';

  static String batchCancelled(int notReachedCount) =>
      '취소해서 나머지 $notReachedCount개는 만들지 않았어요';

  // ---------------------------------------------------------------- import sheet (6.3, 4.11)

  static const String importNewNoteTitle = 'PDF 가져오기';
  static const String importIntoNoteTitle = 'PDF에서 페이지 삽입';
  static const String importNewNoteHint = 'PDF 파일을 골라 새 노트로 만들어요.';
  static const String importIntoNoteHint = 'PDF 파일을 골라 페이지를 이 노트에 넣어요.';
  static const String pickPdfButton = 'PDF 파일 선택';
  static const String pickAnotherButton = '다른 파일 선택';
  static const String importButton = '가져오기';
  static const String pageRangeLabel = '가져올 페이지';
  static const String pageRangeHint = '비워 두면 전체예요. 예: 1-3, 5, 8-';

  /// '12쪽 · 3.4MB'
  static String fileSummary({required int pageCount, required int bytes}) =>
      '$pageCount쪽 · ${megabytes(bytes)}MB';

  /// Success snack bar of the import flow.
  static String importDone(int pageCount) => '$pageCount쪽을 가져왔어요';

  static const String importProgressTitle = 'PDF 가져오는 중';

  static const String largeFileTitle = '큰 PDF예요';

  /// Above PdfImportLimits.warnBytes (6.3).
  static String largeFileBody(int bytes) =>
      '이 PDF는 ${megabytes(bytes)}MB예요. 가져오는 데 시간이 걸리고 저장 공간을 많이 써요. '
      '계속할까요?';

  // ---------------------------------------------------------------- dialogs (6.3, 6.4)

  static const String passwordDialogTitle = 'PDF 암호';
  static const String passwordFieldLabel = '암호';

  /// Shown from the second request on (U6).
  static const String passwordWrong = '암호가 틀렸어요. 다시 입력해 주세요.';
  static const String confirm = '확인';
  static const String passwordDialogNote = '암호를 푼 사본이 노트에 저장돼요';

  // ---------------------------------------------------------------- search panel (6.10.2)

  static const String searchTitle = 'PDF에서 찾기';
  static const String searchHint = '찾을 내용';
  static const String searchPrevious = '이전 결과';
  static const String searchNext = '다음 결과';

  /// While scanning; '(scanned/total쪽)' once the PDF page count is known.
  static String searchProgress(int scanned, int total) =>
      total > 0 ? '찾는 중 ($scanned/$total쪽)' : '찾는 중';

  /// [current] is 0-based, -1 = none selected.
  static String searchResultCount(int count, int current) =>
      current >= 0 ? '결과 $count개 중 ${current + 1}번째' : '결과 $count개';
  static const String searchNoResults = '찾는 내용이 없어요';
  static const String searchNoPdfPages = '이 노트에는 PDF 페이지가 없어요';

  /// PdfSearchState.truncated (PdfTuning.maxSearchHits).
  static String searchTruncated(int max) => '결과가 많아 처음 $max개만 보여요';

  /// Leading label of a hit (PdfSearchHit.notePageNumber).
  static String searchHitPage(int notePageNumber) => '$notePageNumber쪽';

  /// Progress dialogs and the search panel while core.storageWarningOf(...) == writeFailing.
  static const String storageDelay = '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.';

  /// The only button of the import progress dialog during a storage delay (6.3).
  static const String close = '닫기';
  static const String cancel = '취소';

  // ---------------------------------------------------------------- export flows (6.12)

  static const String exportTitle = 'PDF로 내보내기';

  /// Options sheet title of a bulk export (6.12.1 step 2; one note → its title).
  static String batchExportTitle(int noteCount) =>
      '$exportTitle · 노트 $noteCount개';
  static const String includeInk = '필기 포함';
  static const String includeTemplates = '속지 포함';
  static const String exportButton = '내보내기';
  static const String exportProgressTitle = 'PDF 만드는 중';

  /// Result sheet title of a single export.
  static const String exportDone = 'PDF를 만들었어요';

  /// '미적분 3강.pdf · 2.4MB'
  static String exportFileLine(String fileName, int bytes) =>
      '$fileName · ${megabytes(bytes)}MB';
  static const String batchFailedHeader = '만들지 못한 노트';

  /// A failed batch item: '{title}: {userMessage}' (a missing note has no title).
  static String batchFailedLine(String title, String message) =>
      '${title.isEmpty ? '노트' : title}: $message';
  static const String shareAll = '모두 공유';
  static const String share = '공유';
  static const String download = '다운로드';

  /// Native: PdfOutputAction.download opens the system save dialog.
  static const String save = '저장';
  static const String openInNewTab = '새 탭에서 열기';

  /// PdfOutputOutcome.needsUserGesture (Safari: the tap's user activation expired).
  static const String needsUserGesture = '한 번 더 눌러 주세요';
  static const String deliverFailed = '파일을 넘기지 못했어요. 다시 시도해 주세요.';

  // ---------------------------------------------------------------- single export (4.11)

  /// Options sheet titles by PdfExportPurpose (save / share / print — the menu labels).
  static const String shareTitle = 'PDF 공유';
  static const String printTitle = '인쇄';
  static const String rangeAll = '노트 전체';
  static const String rangeCurrent = '현재 페이지';
  static const String rangeSelected = '선택한 페이지';

  /// '12쪽' — the page count of a range, or the number of the current page.
  static String pages(int count) => '$count쪽';

  /// Web: the PDF originals of the chosen range exceed PdfTuning.warnExportSourceBytesWeb
  /// (6.11.2 step 3) — a warning only, the export can go on.
  static String largeExportSource(int bytes) =>
      '원본 PDF가 ${megabytes(bytes)}MB예요. 기기 메모리가 부족하면 내보내기가 멈출 수 있어요.';

  /// Result sheet of PdfExportPurpose.print (6.12): print from the share sheet, or (no file
  /// sharing) from the PDF opened in a new tab.
  static const String printViaShare = '공유 시트에서 프린트를 고르세요';
  static const String printViaNewTab = '새 탭에서 PDF를 열어 인쇄하세요';
}
