# EDITOR 진행 기록

계획서: [../04-editor.md](../04-editor.md) 8장 · 계약: [../00-overview.md](../00-overview.md) 7장 v1.4 · 작업 트리 `/home/user/wt/editor` (브랜치 `area/editor`)

## 요약

- 마지막 세션: **2** (동시 개발 단계 개발 세션 2/10) — 이번 세션 완료: E-03·E-07 (세션 1: E-00·E-01·E-02·E-06)
- 다음 할 일: E-05(입력 라우터 R1~R33) → E-04(페이지 뷰포트, E-01·E-03 뒤) → E-08(E-04·E-05·E-07 뒤) …

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| B5 | 기반 단계에서 완료 | 4828e59 | `widget/smoke_test.dart`, `unit/api_surface_test.dart`, `unit/no_platform_imports_test.dart`. `dart_test.yaml`·6.16 ①~⑤ 검사·설정 모델 JSON도 B5에서 먼저 함 |
| E-00 | 완료 | f203d9b | `unit/no_platform_imports_test.dart`(B5에서 6.16 ①~⑤ 이미 완성), `unit/editor_strings_test.dart`, `dart_test.yaml`(B5), `integration/` 기본 '건너뜀' 확인(아래 메모), README |
| E-01 | 완료 | d32032e | `unit/helpers_smoke_test.dart`. `EditorTestHandles.viewport`·`controllerOf`는 E-03/E-04, `pumpEditor(settings:)`는 E-06, `test_data`의 화면 좌표 도우미(`pageCenterOf`·`lassoAround`·`pathThrough`)는 E-04에서 더함 |
| E-02 | 완료 | 9b78333 | `unit/page_layout_test.dart`, `unit/camera_math_test.dart` |
| E-03 | 완료 | 261c01f | `unit/viewport_controller_test.dart`, `unit/viewport_memory_test.dart` |
| E-04 | 남음 | | `widget/page_viewport_test.dart`, `unit/page_mount_test.dart` |
| E-05 | 남음 | | `unit/input_router_test.dart` (R1~R33) |
| E-06 | 완료 | 95d3366 | `unit/editor_settings_test.dart`(B5에서 완성 — scope별 JSON 왕복·잘못된 값·옛 always/never·`isPenOnlyEffective` 표), `unit/editor_setting_keys_test.dart`, `unit/editor_settings_notifier_test.dart`, `unit/pressure_mode_bridge_test.dart` |
| E-07 | 완료 | (이 커밋) | `unit/tool_controller_test.dart` |
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
- (세션 1) E-06: `editorSettingsProvider`는 이제 `core.settingsRepositoryProvider`를 watch한다 → 이 provider를 읽는 컨테이너에는 `core.noteStoreProvider`(가짜 저장소 등)가 있어야 한다(앱 루트는 항상 있음, app 테스트 통과 확인). B5 `api_surface_test`의 notifier 항목을 가짜 저장소 컨테이너로 바꾸고 `isLoaded`는 처음 `false`로 단언. 로드 전에 바뀐 키는 그 값이 이김(로드 값은 쓰기 대기 중이 아닌 키에만 적용). 원격 synced 값은 자기 echo(`lastWritten`과 같음)이거나 쓰기 대기 중이면 무시. 저장된 값 중 틀린 필드는 기본값 + 로드당 1회 `FlutterError.reportError`(`FormatException`에 필드 경로 — 옛 `always`/`never`·모르는 키·`v`는 오류 아님, 수치는 0.5 이내 차이 허용). `DebouncedSettingWriter`에 `isPending`·`isOwnEcho`·`cancel()`(초기화 전 대기 쓰기 버림)을 더하고, 스냅숏은 `schedule` 때 계산한 값(onDispose에서 provider state를 읽지 않게).
- (세션 2) E-03 `ViewportController`: `panBy(screenDelta)`는 **휠 delta 방향**(양수 dy = 아래 내용이 보임, `PointerScrollEvent.scrollDelta` 그대로)으로 정했다 — `ViewportCamera.pannedBy`(손가락 방향)와 반대. 트랙패드 `panZoomSignal.panDelta`(손가락 방향)는 E-08 `InteractionHost`가 부호를 바꿔 넘긴다. 클래스 멤버를 더함: `pages`(마지막 `updatePages` 값 — '새 값은 보관' 확인용), `isAnimating`; `ViewportAnchor`에 `==`/`hashCode`, `fromJson`은 틀린 필드에 `FormatException`.
- (세션 2) E-03 동작 세부(계획에 없던 것): `restore`는 크기·페이지가 아직 없으면 보관했다가 둘 다 생길 때 적용, `restore`·첫 배치·`setAxis`는 바로 안정화(`isInteracting` false, `settledScale = scale`) — 나머지 카메라 변경(제스처·관성·애니메이션·`panBy`·`zoomBy`·`jumpToPage`·크기/페이지 변경)은 표대로 150ms 안정화. `settleNow`는 0.1% 문턱 없이 `settledScale = camera.scale`. 스냅은 그 제스처에서 배율이 바뀐 경우만(한 손가락 팬 관성을 막지 않게), 스냅이 관성보다 먼저. `zoomStep` 결과가 1±0.05면 1. 애니메이션은 두 카메라의 공통 고정점 기준 보간(같은 배율이면 선형 팬). `jumpToPage`(세로)는 현재 배율 유지, 페이지 위 = `rect.top − pageGap/2`. `ensurePageVisible`의 '보임' = 페이지가 화면과 조금이라도 겹침. 가로 넘기기 스냅(속도 > 300 → 제스처 시작 페이지 ±1, 아니면 가운데 페이지, `cancelGesture`도 스냅)과 `fitScale`(가로 = 현재 페이지 기준)은 미리 구현했고 테스트는 E-18.
- (세션 2) E-03 `ViewportMemory`: 쓰기 때마다 저장된 목록을 먼저 읽어 이 인스턴스의 저장분을 합친다(다른 화면이 쓴 항목 유지). 틀린 항목은 버리고 읽기 1회당 1번 보고(`FormatException`, library `feature_editor`). `dispose` 뒤 `save`는 무시. 생성자는 `ViewportMemory(this._settings, {required this._now})`(호출 모양은 계획과 같음).
- (세션 2) E-07: `WidthMapping`(6.9.4, `src/ui/pen/width_mapping.dart`)을 E-15보다 먼저 만들었다 — `setWidth`가 `WidthMapping.snap`을 쓴다. 완료 조건 테스트(`unit/width_mapping_test.dart`)는 E-15에서 쓴다.
- (세션 2) E-07 세부: `ToolState.defaults()`·`ToolState.defaultPenStyles()`·`copyWith(clearPreviousTool:)`, `EraserSettings.normalized()`·`snapDiameter`(1~100, 0.5 단위), `EraserSettings.fromJson(json, invalidFields:)`(틀린 필드 이름 수집 — 범위 밖은 기본값, 클램프 아님)를 더했다. `previousTool`은 지우개가 활성일 때만 유지(지우개를 떠나면 지움, 복원 시 지우개가 아니면 버림). `selectTool`·`selectPenType`·`applyStyle`은 스포이드를 끈다. `updateStyleOf`는 `tool`을 그 도구로 고정. 펜 스타일 저장은 모든 `PenTool`(P1 포함). `editor.penStyles`의 모르는 도구 이름은 오류가 아님(건너뜀), 디코드 실패·다른 도구 이름 항목은 기본값 + 보고. 세 키의 JSON 변환은 `tool_controller.dart` 안의 비공개 `_ToolStateJson`. `resetPenDefaults`는 `reset`이 아니라 기본값을 `set`(디바운스).
- (세션 1) `EditorStrings`는 E-00에서 화면 상태·읽기 전용·저장 경고·명령 거부 문구까지 넣었다. 툴바·펜·페이지 패널 등 나머지 문구는 해당 작업에서 같은 파일에 더한다.

## 다음 세션 메모

- 환경: `export PATH=/opt/flutter/bin:$PATH CHROME_EXECUTABLE=/usr/local/bin/chrome-nosandbox`. 패키지 테스트는 `packages/feature_editor`에서 `flutter test`(약 25초).
- E-00 확인 결과(세션 1): `flutter test test/integration` → `~1 All tests skipped`(사유 문구 표시). `flutter test --run-skipped -t integration` → 그 테스트만 실행, `UnimplementedError`로 실패(예상대로).
- 계획서 C13-05 반영 완료: 머리 상태 줄 '승인', 계약 인용 v1.4, 13.3 표(EDITOR-3-1·3-2·3-3·4-1, C14-01·02).
- EDITOR-3-1: CORE 호출은 `EditorCommands._run`·`_runAsync`·`_runHistory` 셋뿐(E-08에서 만들 때). E-17 `page_panel_test`에 `rejectNext` 삭제 거부 1건.
- 테스트 도구 사용법: `final h = await pumpEditor(tester, strokesByPageIndex: {0: [strokeA]})` → `h.session`(실제 가짜 저장소 세션), `h.recorder!.calls`·`rejectNext(e)`, `h.container`(EditorScreen 아래 가장 안쪽 ProviderScope — E-04/E-13에서 노트별 scope가 생기면 자동으로 그것), `h.driver`(PointerDriver — 논리 포인터 번호는 `device`, 이벤트 `pointer`는 down마다 새 값), `h.pageId(i)`. 위젯 밖 `Listener`로 받은 이벤트는 `_TransformedPointer*Event`라 `isA<PointerDownEvent>()`로 비교.
- 설정 테스트 환경: `test/helpers/settings_env.dart`의 `runSettingsEnv((env) { env.storeValue(key, {...}); env.load(); ... })` — fake_async + 가짜 저장소 + `RecordingSettings`(CORE에 닿은 set/reset 기록, `writesOf(name)`). `commitDelay:`로 커밋 지연. E-07 `tool_controller_test`도 이것을 쓰면 된다.
- 뷰포트 테스트(세션 2): `test/unit/viewport_controller_test.dart`의 `_viewportTest`·`_controller()` 패턴 — `testWidgets` 안에서 `tester.pump`가 컨트롤러 `Ticker`·150ms 안정화 `Timer`를 움직인다. 컨트롤러는 **본문 끝에서** dispose(testWidgets의 남은 타이머 검사가 tear-down보다 먼저라 `addTearDown`으로는 안 됨). 1032×1376에서 A4 fit = 1000/595.2756 ≈ 1.68, 페이지 i 위 = 24 + i·865.89 pt.
- 기반 단계 메모: `/home/user/wt/notes/foundation-editor.md`. 스모크 테스트에서 커밋 지연을 쓰는 저장소는 tear-down이 아니라 본문 끝에서 `close()`(실패 시 멈춤 방지).
