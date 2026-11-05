# LIBRARY 진행 기록

## 요약

- 마지막 세션: 1 (동시 개발 단계)
- 다음 할 일: L0 (골격 · 테스트 기반)
- 기준: 계획서 `docs/plans/05-library.md` 8장(작업 분해), 통합 계약 00-overview 7장 v1.4

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| B6 | 기반 단계에서 완료 | 676d241 | `test/feature_library_smoke_test.dart`, `unit/api_surface_test.dart` |
| C13-05 | 완료 | (이 커밋) | 계획서 상태 줄 '승인'·계약 v1.4 인용·13.3 최종 승인 표(LIBRARY-3-1~3-3, 4-1, C14-01·02) |
| L0 | 남음 | | `unit/fake_library_backend_test.dart`, `widget/scenarios_on_fake_test.dart` |
| L1 | 남음 | | `unit/date_format_test.dart`, `unit/josa_test.dart`, `unit/names_test.dart`, `unit/strings_contract_test.dart` |
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

- 없음

## 다음 세션 메모

- 기반 단계 인수인계: `/home/user/wt/notes/foundation-library.md`. B6에서 L2 외형 레지스트리(4.4 실제 값)와 그 테스트가 이미 끝났다.
- `LibraryStrings`에는 B6 자리표시 문구(home, folders, settings, newNote, defaultNoteTitle, errorGeneric)만 있다. 전체 표는 L1.
