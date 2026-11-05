# EDITOR 진행 기록

계획서: [../04-editor.md](../04-editor.md) 8장 · 계약: [../00-overview.md](../00-overview.md) 7장 v1.4 · 작업 트리 `/home/user/wt/editor` (브랜치 `area/editor`)

## 요약

- 마지막 세션: **1** (동시 개발 단계 개발 세션 1/10)
- 다음 할 일: E-03(뷰포트 컨트롤러·위치 기억) · E-05(입력 라우터) · E-06(설정 저장) → E-04(페이지 뷰포트) → E-07 → E-08 …

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| B5 | 기반 단계에서 완료 | 4828e59 | `widget/smoke_test.dart`, `unit/api_surface_test.dart`, `unit/no_platform_imports_test.dart`. `dart_test.yaml`·6.16 ①~⑤ 검사·설정 모델 JSON도 B5에서 먼저 함 |
| E-00 | 완료 | f203d9b | `unit/no_platform_imports_test.dart`(B5에서 6.16 ①~⑤ 이미 완성), `unit/editor_strings_test.dart`, `dart_test.yaml`(B5), `integration/` 기본 '건너뜀' 확인(아래 메모), README |
| E-01 | 완료 | d32032e | `unit/helpers_smoke_test.dart`. `EditorTestHandles.viewport`·`controllerOf`는 E-03/E-04, `pumpEditor(settings:)`는 E-06, `test_data`의 화면 좌표 도우미(`pageCenterOf`·`lassoAround`·`pathThrough`)는 E-04에서 더함 |
| E-02 | 완료 | (이 커밋) | `unit/page_layout_test.dart`, `unit/camera_math_test.dart` |
| E-03 | 남음 | | `unit/viewport_controller_test.dart`, `unit/viewport_memory_test.dart` |
| E-04 | 남음 | | `widget/page_viewport_test.dart`, `unit/page_mount_test.dart` |
| E-05 | 남음 | | `unit/input_router_test.dart` (R1~R33) |
| E-06 | 남음 | | `unit/editor_settings_test.dart`, `unit/editor_setting_keys_test.dart`, `unit/editor_settings_notifier_test.dart`, `unit/pressure_mode_bridge_test.dart` (모델·JSON 일부는 B5에서 함) |
| E-07 | 남음 | | `unit/tool_controller_test.dart` |
| E-08 | 남음 | | `widget/pen_stroke_test.dart`, `widget/hover_cursor_test.dart`, `unit/editor_commands_test.dart` |
| E-09 | 남음 | | `widget/erase_test.dart` |
| E-10 | 남음 | | `unit/selection_hit_test_test.dart`, `unit/stroke_clipboard_test.dart`, `widget/lasso_test.dart` |
| E-11 | 남음 | | `widget/undo_redo_test.dart` |
| E-12 | 남음 | | `widget/shortcuts_test.dart` |
| E-13 | 남음 | | `widget/editor_screen_test.dart`, `widget/read_only_test.dart`, `widget/storage_banner_test.dart`, `widget/sync_badge_test.dart`, `widget/toolbar_test.dart`, `widget/extensions_test.dart`, `widget/scope_test.dart` |
| E-14 | 남음 | | `unit/color_math_test.dart`, `widget/color_picker_test.dart`, `goldens/hsv_wheel_golden_test.dart` |
| E-15 | 남음 | | `unit/width_mapping_test.dart`, `widget/pen_settings_panel_test.dart`, `widget/quick_pen_panel_test.dart`, `widget/eraser_panel_test.dart` |
| E-16 | 남음 | | `unit/preset_ordering_test.dart`, `widget/preset_bar_test.dart` |
| E-17 | 남음 | | `widget/page_panel_test.dart`(+ EDITOR-3-1 `rejectNext` 삭제 거부 1건), `widget/page_panel_thumbnail_test.dart`, `widget/page_panel_selection_test.dart`, `widget/navigate_to_page_test.dart`, `widget/add_page_sheet_test.dart`, `unit/page_choices_test.dart`, `widget/add_page_button_test.dart` |
| E-19 | 남음 | | `unit/dev_metrics_test.dart`, `widget/dev_overlay_test.dart`, `widget/dev_menu_test.dart` |
| E-20 | 남음 | | `widget/settings_sections_test.dart` |
| E-21 | 통합 단계 | | `integration/real_core_ink_smoke_test.dart`(뼈대만 E-00에서 작성 — 열기·`storageNotDurable` 배너·닫기. 전체 시나리오는 E-13 뒤 채움), `web/editor_browser_smoke_test.dart`(동시 개발 중 작성 가능) |
| E-22 | 남음 | | `goldens/selection_frame_golden_test.dart`, `goldens/page_viewport_layout_golden_test.dart`, `unit/performance_smoke_test.dart`, 결과 보고 |
| E-18 | 남음 (마지막 순위) | | `widget/paged_mode_test.dart` |

## 변경 요청

- 없음

## 의존성 요청

- 없음

## 계획과 다르게 한 점

- (세션 1) E-21 테스트 파일 `test/integration/real_core_ink_smoke_test.dart`를 E-00에서 뼈대로 먼저 만들었다 — E-00 완료 조건('기본 `flutter test`에서 `test/integration/`이 건너뜀, `--run-skipped -t integration`에서만 실행')을 실제 파일로 확인하려고. 지금 강제 실행하면 B2 CORE `openTestNoteStore`가 `UnimplementedError`라 실패한다(= 실제로 돈다, V7과 같음). 배너 단언은 E-13 전에는 통과할 수 없다. 완료 판정은 통합 단계.
- (세션 1) `editor_strings_test`에 계약 비교 2건 외에 'lib/에서 고정 문장이 `editor_strings.dart`에만 있음' 1건을 더했다(배너가 상수를 읽도록 강제).
- (세션 1) E-01: 6.5.5의 인터페이스 파일 3개(`lib/src/input/input_sample.dart`·`input_targets.dart`, `lib/src/tools/tool_interaction.dart`)를 E-05보다 먼저 만들었다 — `RecordingInputTargets`가 구현할 인터페이스라서. 시그니처는 6.5.5 그대로, `InputPolicy`·`NavigationUpdate`에 `==`/`hashCode`만 더함.
- (세션 1) E-01: `pumpEditor`가 시드 노트의 페이지 id를 `seededPageId(seedKey, i)`(= `seed<n>-p<i>`)로 고정하고, `strokesByPageIndex`의 획은 `copyWith(pageId:)`로 그 페이지에 맞춰 세션 `AddStrokes`로 넣은 뒤 `clearHistory()` — 획 id를 유지하려고(`PageDraft.strokes`는 id를 새로 매김). `EditorTestHandles`에 `pageId(i)`·`seedKey`·`closeCount`를 더함. `RecordingNoteSession`은 거부된 호출을 `'execute:<label>:rejected'`로 기록하고, `close`·`clearHistory`도 기록한다. `executeDuringDelivery`는 계획 문장대로 `execute`만 본다(`executeAsync`·`undo`·`redo`는 첫 await 뒤 적용이라 N-2상 허용).
- (세션 1) E-02: `PageLayout`의 세부 규칙(계획에 없던 것): `pageIndexAt`은 페이지 가장자리 포함, `nearestPageIndex`는 간격에서 가까운 쪽(같으면 앞 페이지), `rangeIntersecting`은 주축 구간만 보고 맞닿음도 포함, 빈 목록은 `contentSize` 주축 = 앞뒤 여백 합·`nearestPageIndex`는 `StateError`. `CameraMath.clampScale`(공개 아님, 내부 도우미)과 `ViewportCamera.copyWith`, `PageLayout`의 `==`를 더함. `fitScale`은 빈 레이아웃·0 크기에서 1.
- (세션 1) `EditorStrings`는 E-00에서 화면 상태·읽기 전용·저장 경고·명령 거부 문구까지 넣었다. 툴바·펜·페이지 패널 등 나머지 문구는 해당 작업에서 같은 파일에 더한다.

## 다음 세션 메모

- 환경: `export PATH=/opt/flutter/bin:$PATH CHROME_EXECUTABLE=/usr/local/bin/chrome-nosandbox`. 패키지 테스트는 `packages/feature_editor`에서 `flutter test`(약 25초).
- E-00 확인 결과(세션 1): `flutter test test/integration` → `~1 All tests skipped`(사유 문구 표시). `flutter test --run-skipped -t integration` → 그 테스트만 실행, `UnimplementedError`로 실패(예상대로).
- 계획서 C13-05 반영 완료: 머리 상태 줄 '승인', 계약 인용 v1.4, 13.3 표(EDITOR-3-1·3-2·3-3·4-1, C14-01·02).
- EDITOR-3-1: CORE 호출은 `EditorCommands._run`·`_runAsync`·`_runHistory` 셋뿐(E-08에서 만들 때). E-17 `page_panel_test`에 `rejectNext` 삭제 거부 1건.
- 테스트 도구 사용법: `final h = await pumpEditor(tester, strokesByPageIndex: {0: [strokeA]})` → `h.session`(실제 가짜 저장소 세션), `h.recorder!.calls`·`rejectNext(e)`, `h.container`(EditorScreen 아래 가장 안쪽 ProviderScope — E-04/E-13에서 노트별 scope가 생기면 자동으로 그것), `h.driver`(PointerDriver — 논리 포인터 번호는 `device`, 이벤트 `pointer`는 down마다 새 값), `h.pageId(i)`. 위젯 밖 `Listener`로 받은 이벤트는 `_TransformedPointer*Event`라 `isA<PointerDownEvent>()`로 비교.
- 기반 단계 메모: `/home/user/wt/notes/foundation-editor.md`. 스모크 테스트에서 커밋 지연을 쓰는 저장소는 tear-down이 아니라 본문 끝에서 `close()`(실패 시 멈춤 방지).
