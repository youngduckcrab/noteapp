# LIBRARY 진행 기록

## 요약

- 마지막 세션: 2 (동시 개발 단계) — L5·L6 완료(세션 1: C13-05·L0·L1·L3·L4, L2는 기반 단계 B6에서 완료)
- 다음 할 일: L7 (`LibraryActions`) → L8 (레이아웃 셸)
- 기준: 계획서 `docs/plans/05-library.md` 8장(작업 분해), 통합 계약 00-overview 7장 v1.4

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| B6 | 기반 단계에서 완료 | 676d241 | `test/feature_library_smoke_test.dart`, `unit/api_surface_test.dart` |
| C13-05 | 완료 | 307bd78 | 계획서 상태 줄 '승인'·계약 v1.4 인용·13.3 최종 승인 표(LIBRARY-3-1~3-3, 4-1, C14-01·02) |
| L0 | 완료 | 1d25517 | `unit/fake_library_backend_test.dart`, `widget/scenarios_on_fake_test.dart` — `test/support/`(TestClock, FakeLibraryBackend, FakeThumbnailRenderer, TestSizes, fixtures, pump_library, LibraryTestHarness), `test/shared/library_scenarios.dart` |
| L1 | 완료 | c2a55ea | `unit/date_format_test.dart`, `unit/josa_test.dart`, `unit/names_test.dart`, `unit/strings_contract_test.dart` |
| L2 | 기반 단계에서 완료 | 676d241 | `unit/appearance_test.dart` (B6에서 4.4 실제 값·L2 검사 전부) |
| L3 | 완료 | 9c8ebc2 | `unit/sort_test.dart`, `unit/prefs_notifier_test.dart`, `unit/settings_keys_test.dart`, `unit/page_size_mm_test.dart`, `unit/new_note_options_test.dart`, `shared/new_note_options_cases.dart`, `web/new_note_options_browser_test.dart` |
| L4 | 완료 | 9deed79 | `unit/section_test.dart`, `unit/selection_test.dart` |
| L5 | 완료 | d12ef32 | `unit/tree_flatten_test.dart`, `unit/breadcrumb_test.dart`, `unit/location_label_test.dart` |
| L6 | 완료 | (이 커밋) | `unit/content_provider_test.dart`, `unit/expansion_test.dart` |
| L7 | 남음 | | `unit/actions_test.dart` |
| L8 | 남음 | | `unit/grid_metrics_test.dart`, `widget/layout_test.dart` |
| L9 | 남음 | | `unit/sync_badge_look_test.dart`, `widget/sidebar_test.dart` |
| L10 | 남음 | | `widget/listing_test.dart`, `widget/breadcrumb_bar_test.dart`, `widget/folder_missing_test.dart` |
| L11 | 남음 | | `unit/cover_scheduler_test.dart`, `widget/cover_view_test.dart` |
| L12 | 남음 | | `widget/new_note_dialog_test.dart`, `widget/new_folder_dialog_test.dart` |
| L13 | 남음 | | `widget/item_actions_test.dart`, `widget/folder_picker_test.dart` |
| L14 | 남음 | | `widget/multi_select_test.dart` |
| L15 | 남음 | | `unit/drop_decision_test.dart`, `unit/drag_handle_test.dart`, `unit/auto_scroll_test.dart`, `widget/drag_drop_test.dart`, `widget/auto_scroll_widget_test.dart` |
| L16 | 남음 | | `widget/trash_view_test.dart` |
| L17 | 남음 | | `widget/recent_favorites_test.dart`, `widget/search_test.dart` |
| L18 | 남음 | | `widget/integration_slots_test.dart`, `widget/storage_banner_test.dart`, `widget/settings_section_test.dart` |
| L19 | 남음 | | `goldens/library_golden_test.dart`, `widget/performance_test.dart`, `widget/a11y_test.dart` |
| L20 | 남음 | | `web/library_browser_test.dart` (+ L3 `web/new_note_options_browser_test.dart`) |
| L21 | 통합 단계 | | `integration/core_contract_test.dart` (`@Tags(['integration'])`, 미리 써 둬도 됨) |

## 변경 요청

- 없음

## 의존성 요청

- 없음

## 계획과 다르게 한 점

- L0 `FakeLibraryBackend`: 5.7 시그니처에 더해 `queries`(래퍼를 거친 읽기 호출 기록 — 예: `'watchListing LibraryQuery(folder: null, updatedAt, desc)'`, `"searchLibrary '<q>' limit:50"`)를 두었다. `folderTreeProvider`가 래퍼를 거치는지(L0 완료 조건), 정렬이 `LibraryQuery`로 전달되는지(L10), 검색 디바운스 횟수(L17)를 확인하는 데 쓴다. `library`·`trash`의 정적 타입은 `RecordingLibraryRepository`·`RecordingTrashRepository`(각각 CORE 인터페이스 구현).
- L0 `calls` 형식은 `fake_library_backend.dart` 클래스 주석에 표로 적었다(예: `moveItems [n:<id>, f:<id>] -> f:<id>`, 대상 `null`은 `home`). 기록은 지연·실패 주입보다 먼저 남는다(실패한 호출도 기록). 씨앗 도우미(`seed*`)·`remoteChange`는 래퍼를 거치지 않아 기록·주입이 없다.
- L0 `seedOpened`는 `openSession` → `close()` 뒤 `store.flush()`까지 기다린다(가짜의 `markOpened`는 커밋을 기다리지 않음 — N-6). `seedNote(favorite: true)`는 만든 뒤 `setFavorite`하고 다시 읽은 값을 돌려준다.
- L0 `FakeThumbnailRenderer`: `failFor`·`nullFor`는 호출이 시작될 때 판정한다(`delay` 동안 테스트가 집합을 바꿔도 진행 중인 렌더 결과는 그대로 — L11 경합 테스트용).
- L1 `LibraryStrings`: 6.18 주요 문구 표 + 6.16.1 동기화 툴팁 문구 + `close`('닫기')·`loadFailed`('불러오지 못했어요', 6.19)를 넣었다. 동기화 중 문구는 상수 `syncInProgress`와 함수 `syncInProgressCount(n)`로 나눴다(이름이 같은 상수·함수를 둘 수 없음). 조사 문장 도우미 `quotedWithObject`·`quotedWithDirection`(`'<이름>'을` 형태)을 더했다. 한 화면 부분에서만 쓰는 문구는 그 작업(L8~L18) 때 추가한다.
- L1 `KoreanJosa`: 끝 공백은 무시, 빈 문자열·기호·한글 자모(완성형 음절이 아닌 것)는 '을(를)'·'(으)로'. `names.dart`에 `kMaxUniqueNameNumber = 999` 상수를 더했다.
- L3 `NewNoteOptions.fromJson`: `"template": null`(키 있음)은 빈 페이지, 키가 없거나 모르는 값이면 기본값(`lined`) — `toJson`이 빈 페이지를 `null`로 쓰므로 왕복을 위해 둘을 구분했다. `paper`는 정수로 표현되는 수(웹 `int`/VM `double` 정수값)만 받고 `PaperColors.all` 밖이면 흰색. `isCustom` getter와 `NewNoteSpec`(6.12, `toPageDraft`)·값 동등도 L3에서 같이 만들었다.
- L3 `LibraryPrefsNotifier.selectSort`: `sortField`·`sortDescending` 두 쓰기를 기다리지 않고 연달아 넣어 한 커밋으로 묶는다(중간 스냅숏에 한쪽만 바뀐 값이 오지 않게). 쓰기 실패는 `reportLibraryError`(`lib/src/common/report_error.dart`, `library: 'feature_library'`)로 보고하고 낙관적 상태는 유지.
- L3 `providers.dart`에는 지금 `libraryPrefsProvider`·`newNoteDefaultsProvider`만 있다. 나머지 provider는 해당 작업 때 같은 파일에 더한다.
- L4 `LibrarySelection`: 계획의 private 생성자 대신 공개 팩터리 `LibrarySelection.activeWith(keys)`(중복 제거, 첫 순서 유지)를 두었다 — 알림자 파일에서 만들 수 있어야 해서. `contains`용 `Set`을 함께 들고 있다(1,000개 타일에서 O(n²) 방지). `isEmpty`, `keyOfRef(LibraryItemRef)` 도우미를 더했다. `begin(first)`는 이미 선택된 키를 유지하고 `first`를 덧붙인다. 같은 섹션 값을 다시 넣으면(`showRouteFolder` 등) 선택은 유지되고, 검색어가 바뀌면 다른 섹션이라 선택이 비워진다.
- L5 `flattenFolderTree` 5단계(순환 폴더): '방문하지 않은 폴더'를 '보인 행'이 아니라 '어느 루트에서도 닿지 않는 폴더'(펼침과 무관한 도달 집합)로 읽었다 — 그대로 읽으면 접힌 폴더의 자식까지 최상위에 나오기 때문. 닿지 않는 폴더를 이름순으로 보며, 아직 덮이지 않은 것만 최상위처럼 내보내고 그 하위 전체를 덮음으로 표시한다(순환 x↔y는 한 줄 x로 보이고 펼치면 y가 그 아래). 도달 집합 계산 때문에 비용은 O(전체 폴더 수)(2,000개 테스트 통과).
- L5 `breadcrumb.dart`에 `breadcrumbPath(tree, folderId)`(= `[홈, ...tree.pathTo(id)]`, 트리에 없으면 `[홈]`) 도우미와 세 슬롯 타입의 값 동등을 더했다. `compressBreadcrumb`는 `maxVisible >= 2`를 assert. 크기 등급별 칸 수(4·3·2)는 L8/L10의 상단 막대에서 정한다.
- L5 `LibraryStrings`에 `pathSeparator`(' › ')·`ellipsis`('…')를 더했고 `locationLabel`이 쓴다. `kLocationLabelMaxNames = 3` 상수.
- L6 `libraryContentProvider`·`sidebarRowsProvider`: 보기 설정이 로드되기 전에는 `AsyncLoading`(휴지통 섹션 포함 모든 섹션). 단 `settingsSnapshotProvider`가 오류면 기본 정렬로 로드된 것으로 본다(설정 스트림 오류로 화면이 영원히 로딩에 머무르지 않게). 사이드바 행도 정렬(이름/사용자 지정)에 따라 순서가 바뀌므로 같은 규칙으로 기다린다. 검색 상한 50은 `kLibrarySearchLimit` 상수(`providers.dart`).
- L6 `folderLookupProvider`: `folderTreeProvider.future`에 더해 `trashItemsProvider`도 watch한다 — 휴지통에 있는 폴더를 다른 기기가 영구 삭제하면 트리는 바뀌지 않아(값 동등) 다시 계산되지 않기 때문. 트리에 없고 `getFolder`가 휴지통 아닌 폴더를 주면(트리 갱신 직전 경합) `active`.
- L6 `trashCountProvider`: 오류면 이전 값이 있어도 0.
- L6 `FolderExpansionNotifier`: 상태 `Set`은 펼친 순서(오래된 것 → 최근)로 순회한다. 이미 펼친 id를 다시 펼치면 자리 그대로(`expandAll`이 아무것도 바꾸지 않으면 같은 상태 객체·저장 없음). 저장된 목록이 오기 전에 접은 id는 복원하지 않고, 그 전에 디바운스가 끝나면 쓰지 않고 로드 뒤 500ms에 쓴다(저장된 id를 덮어쓰지 않게). 트리는 `ref.listen(folderTreeProvider)`로 따라가며 마지막 값으로 거른다(트리가 아직 없으면 거르지 않음). `ref.onDispose`에서는 `state`를 읽을 수 없어(Riverpod 3 생명주기 규칙) 사본 `_current`를 쓴다. 로드 실패는 `reportLibraryError` 1회 후 빈 상태.
- L0 공유 시나리오 목록에는 지금 하네스 시나리오 1건('a route change keeps the LibraryScreen State')만 있다. L21의 8건은 해당 화면 작업(L10~L18) 때 추가한다.

## 다음 세션 메모

- 기반 단계 인수인계: `/home/user/wt/notes/foundation-library.md`. B6에서 L2 외형 레지스트리(4.4 실제 값)와 그 테스트가 이미 끝났다.
- 테스트 기반(L0): 위젯 테스트는 `LibraryTestHarness(FakeLibraryBackend(), size: …, extraOverrides: …)` → `h.pump(tester, folderId: …)`, `h.goToFolder`, `h.log.entries`, `h.backend.calls`/`queries`. 씨앗은 `seedSampleLibrary(backend)`(홈 폴더 3·노트 4, 수학 › 미적분 › 극한 › 연습 문제 + '극한 정리'). 시간 흐름이 있는 단위 테스트는 `fakeAsync` 안에서 백엔드를 만든다(가짜의 커밋 재시도·`latency`가 Timer).
- L1 이후 `LibraryStrings`에 6.18 주요 표가 있다. 새 화면 문구는 그 작업에서 이 파일에 더한다(위젯에 한국어 리터럴 금지).
- provider는 모두 `lib/src/state/providers.dart`에 모은다(지금: `libraryPrefsProvider`, `newNoteDefaultsProvider`, `librarySectionProvider`, `librarySelectionProvider`). `selection_notifier.dart`가 `providers.dart`를 import한다(순환 import, Dart에서 허용).
- 오류 보고는 `reportLibraryError(error, stack, context)`(`lib/src/common/report_error.dart`).
- 세션 1 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 패키지 VM 테스트 175개 통과, `flutter test --platform chrome test/web` 6개 통과(L3 브라우저 파일).
