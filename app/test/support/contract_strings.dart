// The fixed storage banner sentences of contract 00-overview 7.4.5 (v1.1),
// letter for letter. LIBRARY and EDITOR show them (each area owns its own
// string constant); the V5 / V6 smoke tests compare both screens with these
// (docs/plans/01-infra.md 8.3 'V5 스모크 단계' 3 and 5).
abstract final class ContractStrings {
  /// StorageWarning.notDurable.
  static const String storageNotDurable =
      '이 브라우저에서는 노트가 임시로만 저장돼요. 테스트 용도로만 사용하세요.';

  /// StorageWarning.writeFailing.
  static const String storageWriteFailing =
      '저장에 계속 실패하고 있어요. 브라우저 저장 공간을 확인해 주세요.';
}
