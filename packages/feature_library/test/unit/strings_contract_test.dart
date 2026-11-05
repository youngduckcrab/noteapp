// The storage warning sentences are fixed by contract 00-overview 7.4.5 v1.1
// (C11-24). The expected values below are the contract sentences copied as
// they are; EDITOR compares its own constants the same way, and INFRA V5
// checks both screens (05-library 6.16.2, 8 L1).
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writeFailing banner = contract 7.4.5 sentence', () {
    expect(
      LibraryStrings.storageWriteFailing,
      '저장에 계속 실패하고 있어요. 브라우저 저장 공간을 확인해 주세요.',
    );
  });

  test('notDurable banner = contract 7.4.5 sentence', () {
    expect(
      LibraryStrings.storageNotDurable,
      '이 브라우저에서는 노트가 임시로만 저장돼요. 테스트 용도로만 사용하세요.',
    );
  });

  test('custom page size range sentence (6.12)', () {
    expect(
      LibraryStrings.customSizeRange(35.3, 1058.3),
      '35.3~1058.3mm 사이로 입력하세요',
    );
  });

  test('sync badge strings with counts (6.16.1)', () {
    expect(LibraryStrings.syncInProgressCount(0), '동기화 중');
    expect(LibraryStrings.syncInProgressCount(3), '동기화 중 · 3');
    expect(LibraryStrings.syncPendingTooltip(3), '보내는 중인 변경 3개');
    expect(LibraryStrings.selectedCount(2), '2개 선택됨');
  });
}
