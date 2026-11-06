// lib/src/ui/strings_ko.dart — MediaStringsKo (m5-7/06-pdf 6.16; 해요체, 1차 7.4.5). Every
// user-visible string of media_io lives here.
//
// R2-B4 (T30): the placeholder strings. T36a: the recording / status / playback rows and the
// consent sheet. T36b: the list, the name / delete sheets, the stuck-draft row and the web
// download. T33: the native interruption line and the foreground service notification. T35b:
// image import.
abstract final class MediaStringsKo {
  /// Recording panel title.
  static const String panelTitle = '녹음';

  /// Close button of the panel (tooltip / semantics).
  static const String close = '닫기';

  // --- recording row (6.13.1) ---
  static const String record = '녹음';
  static const String recordSemantics = '녹음 시작';
  static const String pause = '일시정지';
  static const String resume = '이어서';
  static const String stop = '정지';
  static const String stopOther = '그 녹음 정지';
  static const String recordingNow = '녹음 중';

  // --- status line (6.13.2, 6.16) ---
  /// Fixed consent notice (contract 7.4.4) — the consent sheet and the idle line.
  static const String consent = '다른 사람의 목소리를 녹음할 때는 미리 동의를 받아 주세요.';
  static const String unsupportedDevice = '이 기기에서 녹음할 수 없어요';
  static const String unsupportedWeb = '이 브라우저에서는 녹음할 수 없어요';
  static const String permissionNative =
      '마이크 권한이 없어요. 설정 → 필기노트 → 마이크에서 허용해 주세요.';
  static const String permissionWeb = '브라우저에서 이 사이트의 마이크 사용을 허용해 주세요.';
  static const String microphoneNotFound = '마이크를 찾지 못했어요';
  static const String microphoneBusy = '다른 앱이 마이크를 쓰고 있어요';
  static const String starting = '녹음을 준비하고 있어요…';
  static const String finishing = '녹음을 저장하고 있어요…';
  static const String hiddenTab = '화면을 벗어나 녹음이 멈췄어요. 이어서 녹음할까요?';

  /// (T33) Native: a call / Siri / another app's audio paused the recording (6.9.2) — 6.16 has
  /// no row for it; the hiddenTab line's shape with the cause the user can see.
  static const String systemInterruption = '다른 소리 때문에 녹음이 멈췄어요. 이어서 녹음할까요?';
  static const String resumeRecording = '이어서 녹음';
  static const String microphoneLost = '마이크가 끊겨 이어서 녹음할 수 없어요. 정지해서 저장해 주세요.';
  static const String storageBacklog = '저장이 밀려 녹음을 멈췄어요';
  static const String saveFailed = '녹음을 저장하지 못했어요. 앱을 다시 열면 복구해요.';
  static const String draftLost =
      '다른 창에서 이 녹음을 정리했어요. 지금까지의 녹음은 그 창의 녹음 목록에 있어요.';
  static const String otherNoteRecording = '다른 노트에서 녹음 중이에요';
  static const String webFormatWarning = '이 브라우저 녹음은 아이패드 앱에서 재생되지 않을 수 있어요';

  // --- playback row (6.13.1, 6.16) ---
  static const String play = '재생';
  static const String pausePlayback = '일시정지';
  static const String back10 = '10초 뒤로';
  static const String forward10 = '10초 앞으로';
  static const String position = '재생 위치';
  static const String speed = '재생 속도';
  static const String tapToSeek = '필기 탭 재생';
  static const String cannotPlay = '이 녹음은 이 기기에서 재생할 수 없어요';
  static const String assetMissing = '이 녹음 파일이 아직 이 기기에 없어요';
  static const String noPlayWhileRecording = '녹음 중에는 재생할 수 없어요';

  // --- consent sheet (6.13.3 ①) ---
  static const String cancel = '취소';
  static const String startRecording = '녹음 시작';

  // --- recordings list (6.13.1) ---
  /// Default name of a recording without a title: '녹음 N' by startedAt order (7.2.4).
  static String defaultTitle(int n) => '녹음 $n';
  static const String recoveredBadge = '복구됨';
  static const String webmWarning = '⚠ 아이패드 앱에서는 재생되지 않을 수 있어요';
  static const String recordingActions = '녹음 메뉴';
  static const String openRecording = '이 녹음 열기';

  /// '이 노트의 녹음 3개 · 27.6 MB'
  static String listTotal(int count, String size) => '이 노트의 녹음 $count개 · $size';

  /// '11월 5일 14:02'
  static String dateTime(DateTime t) =>
      '${t.month}월 ${t.day}일 ${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  // --- name / delete sheets (6.13.1) ---
  static const String rename = '이름 바꾸기';
  static const String delete = '삭제';
  static const String nameHint = '비우면 기본 이름';
  static const String save = '저장';
  static const String deleteRecordingQuestion =
      '이 녹음을 지울까요? 녹음과 함께 쓴 필기는 그대로 남아요.';

  // --- drafts that could not be recovered (6.10.3, 6.13.2) and the web download (6.10.4) ---
  static const String stuckDrafts = '복구하지 못한 녹음이 있어요';
  static const String retry = '다시 시도';
  static const String draftActions = '복구하지 못한 녹음 메뉴';
  static const String discardDraft = '지우기';
  static const String discardDraftQuestion = '이 녹음을 지울까요? 되돌릴 수 없어요.';
  static const String downloadFile = '파일로 내려받기';
  static const String saveFile = '저장하기';

  // --- (T35b) image import (6.16 — snack bars and the preparing sheet) ---
  static const String imageUnsupportedFormat = '이 형식의 이미지는 넣을 수 없어요';
  static const String imageTooLarge = '이미지가 너무 커서 넣을 수 없어요';
  static const String imageDecodeFailed = '이미지를 읽지 못했어요';
  static const String clipboardEmpty = '클립보드에 이미지가 없어요';
  static const String clipboardDenied = '붙여넣기를 허용한 뒤 다시 눌러 주세요';
  static const String cameraUnavailable = '카메라를 쓸 수 없어요';
  static const String imageSaveFailed = '이미지를 저장하지 못했어요';
  static const String imagePreparing = '이미지를 준비하고 있어요…';

  /// 6.12.5: `이미지-<yyyyMMdd-HHmmss>` (+ the stored format's extension).
  static String imageFileStem(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '이미지-${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  // --- (T33) the Android microphone foreground service notification (6.9.4) ---
  static const String foregroundChannelName = '녹음';
  static const String foregroundTitle = '필기노트 녹음 중';
  static const String foregroundText = '탭하면 노트로 돌아가요';

  /// '0.5×', '0.75×', '1.0×' … (the same text on the VM and the web — no double.toString).
  static String speedLabel(double speed) {
    final hundredths = (speed * 100).round();
    return '${(hundredths / 100).toStringAsFixed(hundredths % 10 == 0 ? 1 : 2)}×';
  }
}
