// RecognitionStrings (m5-7/05-library 6.21, 8.2 L2-07): the contract sentence
// of 7.4.2 word for word, the action labels of 4.4.4, the developer overlay
// line of 4.4.9 and the 6.21 / 6.11.4 wording (regression).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/l10n/recognition_strings.dart';

void main() {
  test('webUnsupported = the contract 7.4.2 sentence', () {
    expect(
      RecognitionStrings.webUnsupported,
      '이 기기(웹)에서는 손글씨 인식을 쓸 수 없어요. 안드로이드 앱에서 쓸 수 있어요.',
    );
  });

  test('action labels (4.4.4)', () {
    expect(RecognitionStrings.toText, '텍스트로 변환');
    expect(RecognitionStrings.copyText, '텍스트 복사');
    expect(RecognitionStrings.toMath, '수식으로 변환');
    expect(RecognitionStrings.editMath, '수식 편집');
    expect(RecognitionStrings.mathPad, '수식');
  });

  test('the developer overlay line without an indexer (4.4.9) is what the '
      'provider shows', () {
    expect(RecognitionStrings.noIndexerLine, '손글씨 색인 없음 (이 기기에서 인식 불가)');
    final container = ProviderContainer.test();
    expect(container.read(recognitionDevOverlayLinesProvider).value, [
      RecognitionStrings.noIndexerLine,
    ]);
  });

  test('6.21 wording', () {
    expect(RecognitionStrings.unsupported, '이 기기에서는 손글씨 인식을 쓸 수 없어요.');
    expect(RecognitionStrings.noInk, '변환할 손글씨가 없어요.');
    expect(RecognitionStrings.lineProgress(2, 5), '2/5줄');
    expect(
      RecognitionStrings.modelNeeded(RecognitionStrings.languageName('ko')),
      '한국어 인식 모델을 받아야 해요(약 20MB).',
    );
    expect(RecognitionStrings.languageName('en'), '영어');
    expect(RecognitionStrings.waitingForWifi, '와이파이에 연결되면 받아요.');
    expect(RecognitionStrings.downloadOnCellular, '지금 셀룰러로 받기');
    expect(RecognitionStrings.copyFailed, '복사하지 못했어요.');
    expect(RecognitionStrings.tooManyLines(3), '나머지 3줄은 선택을 나눠 변환해 주세요.');
    expect(RecognitionStrings.manualOnly, '수식 인식 엔진이 연결되지 않아 LaTeX로 직접 입력해요.');
    expect(RecognitionStrings.consentAgree, '동의하고 쓰기');
    expect(RecognitionStrings.typeInstead, '직접 입력');
    expect(RecognitionStrings.mathQuotaExceeded, '오늘 쓸 수 있는 수식 인식 횟수를 다 썼어요.');
    expect(
      RecognitionStrings.mathOffline,
      '수식 인식 서버에 연결할 수 없어요. 인터넷 연결을 확인해 주세요.',
    );
  });

  test('sheet titles and buttons (6.12, 6.14, 6.15 — L2-13, L2-14)', () {
    expect(RecognitionStrings.cancel, '취소');
    expect(RecognitionStrings.apply, '적용');
    expect(RecognitionStrings.copyLatex, 'LaTeX 복사');
    expect(RecognitionStrings.mathPadTitle, '수식 입력');
    expect(RecognitionStrings.insert, '넣기');
    expect(RecognitionStrings.copied, '복사했어요.');
    expect(RecognitionStrings.readOnly, '읽기 전용 노트라 바꿀 수 없어요.');
    expect(RecognitionStrings.runFailed, '실행하지 못했어요.');
  });

  test('settings section (6.18) and status line (6.19) — L2-18', () {
    expect(RecognitionStrings.handwritingGroup, '손글씨 인식');
    expect(RecognitionStrings.mathGroup, '수식 인식');
    expect(RecognitionStrings.languageTitle, '인식 언어');
    expect(RecognitionStrings.languageLabel('ko'), '한국어');
    expect(RecognitionStrings.languageLabel('en'), 'English');
    expect(RecognitionStrings.wifiOnlyTitle, 'Wi-Fi에서만 모델 받기');
    expect(
      RecognitionStrings.wifiOnlyAskFirst,
      '받기 전에 셀룰러 데이터 사용을 한 번 더 물어봐요.',
    );
    expect(RecognitionStrings.autoIndexTitle, '검색용 자동 인식');
    expect(RecognitionStrings.mathEngineManual, '연결 안 됨 — LaTeX로 직접 입력해요');
    expect(RecognitionStrings.mathEngineServer, '서버 엔진');
    expect(RecognitionStrings.consentSwitch, '외부 서비스로 보내기 동의');
    expect(RecognitionStrings.indexerOff, '이 기기에서는 자동 인식을 쓸 수 없어요');
    expect(RecognitionStrings.indexerDisabled, '꺼져 있어요');
    expect(RecognitionStrings.indexerWaitingModel, '인식 모델을 기다리는 중이에요');
    expect(RecognitionStrings.indexerWaitingWifi, ' · 와이파이 대기');
    expect(RecognitionStrings.indexerIdle(12), '대기 중 · 인식한 페이지 12');
    expect(
      RecognitionStrings.indexerWaitingInput(3),
      '필기가 멈추길 기다리는 중 · 남은 페이지 3',
    );
    expect(RecognitionStrings.indexerRecognizing(3), '인식 중 · 남은 페이지 3');
    expect(RecognitionStrings.indexerPaused, '앱이 뒤에 있어 멈췄어요');
  });

  test('model rows (6.18, 6.22) — L2-18', () {
    expect(RecognitionStrings.modelTitle, '인식 모델');
    expect(RecognitionStrings.modelReady, '준비됨');
    expect(RecognitionStrings.modelNotDownloaded, '받지 않음');
    expect(RecognitionStrings.modelDownloading, '받는 중…');
    expect(RecognitionStrings.modelUnsupported, '쓸 수 없음');
    expect(RecognitionStrings.modelFailed, '받지 못했어요');
    expect(RecognitionStrings.download, '받기');
    expect(RecognitionStrings.deleteModel, '지우기');
    expect(RecognitionStrings.retry, '다시');
    expect(
      RecognitionStrings.cellularWarning,
      '셀룰러 데이터로 받을 수 있어요(약 20MB). 한 번 더 누르면 받아요.',
    );
    expect(
      RecognitionStrings.cellularConfirm,
      '셀룰러 데이터로 받아요(약 20MB). 한 번 더 누르면 받아요.',
    );
  });
}
