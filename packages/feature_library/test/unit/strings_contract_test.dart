// The storage warning sentences are fixed by contract 00-overview 7.4.5 v1.1
// (C11-24). The expected values below are the contract sentences copied as
// they are; EDITOR compares its own constants the same way, and INFRA V5
// checks both screens (05-library 6.16.2, 8 L1).
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' show SearchSource;

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

  test('(v2) content search strings (6.21)', () {
    expect(LibraryStrings.searchHint, '노트 검색');
    expect(LibraryStrings.searchContentGroup(7), '노트 내용 (7)');
    expect(LibraryStrings.contentMore(2), '이 노트에서 2개 더 보기');
    expect(LibraryStrings.contentTruncated, '내용 결과가 많아요. 검색어를 더 입력해 보세요.');
    expect(
      [for (final s in SearchSource.values) LibraryStrings.sourceLabel(s)],
      ['손글씨', 'PDF', '텍스트', '수식'],
    );
    expect(LibraryStrings.pageLabel(3), '3쪽');
    expect(LibraryStrings.pageUnknown, '페이지');
    expect(
      LibraryStrings.contentHitSemantics('회의록', '3쪽', '손글씨', '회의 안건'),
      '회의록, 3쪽, 손글씨, 회의 안건',
    );
    // 1차 sentences next to them are unchanged.
    expect(LibraryStrings.searchTruncated, '결과가 많아요. 검색어를 더 입력해 보세요.');
    expect(LibraryStrings.searchFolderGroup(3), '폴더 (3)');
    expect(LibraryStrings.searchNoteGroup(12), '노트 (12)');
  });
}
