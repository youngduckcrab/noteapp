# LIBRARY 진행 기록

## 요약

- 마지막 세션: 1 (동시 개발 단계)
- 다음 할 일: L3 (보기 설정 · 설정 키 · 새 노트 옵션) — L2는 기반 단계에서 완료
- 기준: 계획서 `docs/plans/05-library.md` 8장(작업 분해), 통합 계약 00-overview 7장 v1.4

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| B6 | 기반 단계에서 완료 | 676d241 | `test/feature_library_smoke_test.dart`, `unit/api_surface_test.dart` |
| C13-05 | 완료 | 307bd78 | 계획서 상태 줄 '승인'·계약 v1.4 인용·13.3 최종 승인 표(LIBRARY-3-1~3-3, 4-1, C14-01·02) |
| L0 | 완료 | 1d25517 | `unit/fake_library_backend_test.dart`, `widget/scenarios_on_fake_test.dart` — `test/support/`(TestClock, FakeLibraryBackend, FakeThumbnailRenderer, TestSizes, fixtures, pump_library, LibraryTestHarness), `test/shared/library_scenarios.dart` |
| L1 | 완료 | (L1 커밋) | `unit/date_format_test.dart`, `unit/josa_test.dart`, `unit/names_test.dart`, `unit/strings_contract_test.dart` |
| L2 | 기반 단계에서 완료 | 676d241 | `unit/appearance_test.dart` (B6에서 4.4 실제 값·L2 검사 전부) |
| L3 | 남음 | | `unit/sort_test.dart`, `unit/prefs_notifier_test.dart`, `unit/settings_keys_test.dart`, `unit/page_size_mm_test.dart`, `unit/new_note_options_test.dart`, `shared/new_note_options_cases.dart`, `web/new_note_options_browser_test.dart` |
| L4 | 남음 | | `unit/section_test.dart`, `unit/selection_test.dart` |
| L5 | 남음 | | `unit/tree_flatten_test.dart`, `unit/breadcrumb_test.dart`, `unit/location_label_test.dart` |
| L6 | 남음 | | `unit/content_provider_test.dart`, `unit/expansion_test.dart` |
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
- L0 공유 시나리오 목록에는 지금 하네스 시나리오 1건('a route change keeps the LibraryScreen State')만 있다. L21의 8건은 해당 화면 작업(L10~L18) 때 추가한다.

## 다음 세션 메모

- 기반 단계 인수인계: `/home/user/wt/notes/foundation-library.md`. B6에서 L2 외형 레지스트리(4.4 실제 값)와 그 테스트가 이미 끝났다.
- 테스트 기반(L0): 위젯 테스트는 `LibraryTestHarness(FakeLibraryBackend(), size: …, extraOverrides: …)` → `h.pump(tester, folderId: …)`, `h.goToFolder`, `h.log.entries`, `h.backend.calls`/`queries`. 씨앗은 `seedSampleLibrary(backend)`(홈 폴더 3·노트 4, 수학 › 미적분 › 극한 › 연습 문제 + '극한 정리'). 시간 흐름이 있는 단위 테스트는 `fakeAsync` 안에서 백엔드를 만든다(가짜의 커밋 재시도·`latency`가 Timer).
- `LibraryStrings`에는 B6 자리표시 문구(home, folders, settings, newNote, defaultNoteTitle, errorGeneric)만 있다. 전체 표는 L1.
