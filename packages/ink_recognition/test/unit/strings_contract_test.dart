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
}
