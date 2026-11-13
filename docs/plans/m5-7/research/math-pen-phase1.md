# 수식 펜 1단계 설계 노트 (math pen — phase 1)

상태: **1단계 구현됨**(2026-11-13 — 사용자 '1단계 진행해줘' = 계약 변경 승인, 00-overview 7.9 v2.8 C28-01~05). 대상 브랜치 `claude/note-app-planning-bk29xb`. 아래 '구현 결과' 절이 설계와 달라진 곳을 적는다 — 코드와 다르면 코드가 기준이다.
범위: 사용자 요구 1~6 전부. **이번에 하지 않는 것**(사용자가 미룸): 다른 후보 칩, 렌더된 수식 일부만 눌러 고치기, 오래 멈추면 자동 변환 설정, 묶음 나누기·합치기.

이 노트의 결정은 계약(00-overview) 변경을 포함한다(§11). 사용자 승인('1단계 진행해줘') 뒤 00-overview 7.9 v2.8(C28-01~05)로 반영했다.

---

## 구현 결과 (1단계 — 설계와 달라진 곳)

| 항목 | 설계 | 구현 | 이유 |
|---|---|---|---|
| 수식 펜 스타일 | `ToolOptions.mathPenStyle`, JSON `"math"`, `MathPenPopup` | **볼펜 스타일을 함께 쓴다**(`ToolState.penStyles[ballpoint]`). `editor.toolOptions`·`editor.toolSelection` 형식 불변(저장값 `"math"`만 새로 나올 수 있음 — 옛 앱은 6.2.2 규칙으로 `pen`) | 열린 질문 1을 '공유'로 — 저장 형식·팝업을 늘리지 않음. 색·굵기는 볼펜 팝업에서 |
| recog 공개 이름 | `RecognitionMathPen`·`recognitionMathPen()` 2개 | 4개: + `RecognitionMathPenContext`·`RecognitionMathPenSession`. 묶음은 기존 **`RecognitionTarget`**(strokes·areaPt = 점 경계·execute)으로 넘긴다 | recog는 편집기 타입을 볼 수 없다(R8) — 세션 인터페이스가 recog 쪽에 있어야 앱 셸이 바꿔 끼운다(`app/lib/src/modules/recognition_wiring.dart` `editorMathPenOf`) |
| 다시 열기 커밋 | `commitInkEdit(before:)` 선택 인자 | 새 메서드 `EditorCommands.commitInkEditWith(controller, edit, before:, label:)` + `PenInteraction`의 선택 인자 `commit`·`onFinished` | 기존 호출·시험 불변. 읽기 전용이면 편집 버림, 그 밖의 거부면 획만 다시 커밋(필기 손실 없음) |
| 지우개 조각 | `EraseInteraction.onCommittedEdit` | 묶음 페이지의 `pageChanges`만으로 맞춘다: 사라진 소속 획과 `createdAt`·스타일·녹음(`recordingId`·`recordingOffsetMs`)이 같고 점 경계가 그 획 경계(+0.5 pt) 안에 드는 새 획(= `Stroke.fragment`)을 묶음에 넣음 | 지우개 코드 불변, 되돌리기·원격 변경과 같은 길. 경계 조건은 같은 잉크를 붙여 넣은 사본의 조각을 빼려고(검토 A-7) |
| 말풍선 위치 | 묶음 경계 위 8 px | **묶음 경계를 위아래로 `bubbleClearanceFactor`(1.0) H씩 넓힌 영역** 위 8 px. 자리가 없으면 아래, 그것도 없으면(크게 확대) 영역 오른쪽·왼쪽, 그것도 없으면 영역을 가장 덜 가리는 화면 모서리(`mathPenBubbleOffset`). 묶음이 화면 밖이면 말풍선을 숨긴다 | 위 8 px이면 지수·다음 기호의 첫 획('+'의 세로획)을 쓰려는 펜이 말풍선에 닿아 획이 되지 않았다(위젯 시험에서 발견). 화면 밖 말풍선 탭은 보이지 않는 묶음을 바꾼다(검토 B-M2) |
| 되돌린 변환 | 다시 활성 묶음 | **마지막 변환을 되돌린 바로 그 변경**(그 획들이 `added`/`updated`로 돌아옴)에서 **한 번만**, 그리고 수식 펜·지우개일 때만 활성 묶음이 된다. **`restored`**: 도구 전환·새 묶음으로는 변환하지 않는다(말풍선 탭만). 수식 펜으로 그 묶음에 쓰면 풀린다(지우개로 일부를 지워도 유지) | 사용자가 손글씨를 고른 것. 예전엔 `_lastConverted`가 남아 그 페이지의 다음 변경(다른 도구의 획 포함)마다 묶음·말풍선이 되살아났다(검토 A-4·B-H1) |
| 배경 변환 대기 중 다시 건드림 | 기다림 취소 + 묶음 다시 열기 | 넘긴 묶음은 즉시 닫히고, 변환 직전 ① `liveStrokes`로 획이 그대로인지 ② 편집기 `stillWanted` — 노트 기록(`NoteSession.history`, `HistoryState`)이 계기 때와 같은지(새 묶음이면 새 획 커밋 직후 상태) 확인해, 다르면 포기(잉크로 남음). 준비된 답이 있으면 **새 획보다 먼저** 동기로 변환한다 | 늦은 변환이 사용자의 다음 작업 위에 쌓이거나 다시 실행을 지우지 않게(검토 A-1·A-2·B-M1). 되돌리기 한 번 = 방금 쓴 획 |
| 잉크 한도 | 초과 시 ink 없이 변환 + 알림 | **배경 변환은 한도를 넘는 묶음을 변환하지 않는다**(잉크로 남음). 말풍선 탭은 먼저 묻는다('손글씨가 너무 많아요' — [취소][바꾸기]). 합류는 획 수와 **점 수**를 함께 세고(`mathPenJoins` `groupPoints`·`strokePoints`), 손글씨 + 새 획이 한도를 넘는 수식은 다시 열지 않는다(`mathInkWithin`) | 요구 3(원래 획을 간직)을 사용자 모르게 어기지 않게(검토 A-3) |
| 선택 메뉴 '⋯ 손글씨로 열기' | 다른 도구의 선택 메뉴에 추가 | **이번에 안 함.** 수식 펜 도구에서 수식을 손가락 탭(또는 손가락 그리기의 손가락 점·마우스 클릭) → [고치기][손글씨로 열기]. 손글씨로 다시 여는 길은 수식 펜뿐이다(검토 B-L3 — 1단계 제약) | 4.4.4 순서·선택 메뉴 시험을 건드리지 않음. 다른 도구에서는 기존 '수식 편집'(기호 줄 포함) |
| 수식 안의 펜 점 | frame 안 펜 점 → 메뉴 | **스타일러스 점은 쓴다**(소수점·곱셈점·i의 점 — 다시 열기 + 점). 메뉴는 손가락 탭, 손가락 그리기의 손가락 점, 마우스 클릭 | 이어 쓰기(요구 4)를 흔한 기호에서 깨지 않게(검토 B-M4) |
| 말풍선의 손바닥 | (언급 없음) | 라우터가 손바닥으로 거를 손가락(방금 펜 활동 — P1~P3, 큰 접촉 P5)의 탭은 변환하지 않는다(`InputRouter.rejectsAsPalm`) | 쓰는 손이 말풍선 아래에 닿아 변환되지 않게(검토 B-M3) |
| 고치기 위치 | 6.15.1 가운데 유지 | `ink`가 있고 돌지 않은 수식은 **왼쪽 끝과 세로 가운데**를 유지(`relayoutMath`) | 손글씨가 시작한 곳에서 시작, 길어지면 오른쪽으로만(검토 B-L1) |
| 다시 연 수식이 다시 안 바뀜 | (언급 없음) | 배경 변환이 실패하면 '수식으로 바꾸지 못해 손글씨로 남겼어요.'(편집기 알림, 되돌리기로 수식 복구) | 엔진 없음·실패에서 수식이 조용히 사라진 것처럼 보이지 않게(검토 B-L2) |
| 말풍선 탭 대기 | 진행 중 답을 기다림 | 같은 묶음의 진행 중 요청을 **그대로 기다린다**(새 요청 없음). 새 접촉·도구 전환으로 요청이 취소되면 아무것도 열지 않는다(LaTeX 창 없음). 기다리는 사이 합류한 획은 열린 묶음으로 남는다 | 검토 B-L7·A-5 |
| 엔진 켜기 뒤 | (언급 없음) | '기기에서 수식 인식' 창이 닫히면 다시 인식한다(`onRetry`) | 검토 B-L4 |
| 호버 점 | 펜만 | iPad 포즈 호버도 수식 펜의 볼펜 점을 보인다 | 검토 B-L5 |
| 인식 캐시 | 4개 | 8개(`kMathPenCacheSize`) | 되돌리기 몇 번에도 재인식 없이 |
| PNG | 서버 엔진만 | 같음 — `engine is CallableMathRecognizer`일 때만 `renderMathPng` | — |
| `recog.toMath`(선택 → 수식) | (언급 없음) | 바뀌지 않음 — 그 수식은 `ink`를 갖지 않아 다시 열 수 없다 | 범위 밖. 후속 후보 |
| INK | 바뀌는 곳 없음 | 같음 — `MathObject.ink`는 그리지 않는다(렌더·PDF·검색 색인 불변) | — |

나머지는 아래 설계 그대로다(묶음 상수 3.2, JSON 5.3, 변환 명령 11.3, 기호 표 12, 엔진 없음 10). 시험: note_core `test/model/math_ink_test.dart`·골든 `math_ink.json`, sync_engine `field_merge_test` ink 두 사례·`field_units_test`·`core_json_keys_test`, feature_editor `test/unit/math_pen_group_test.dart`·`test/unit/math_pen_bubble_place_test.dart`·`test/widget/math_pen_test.dart`('review:' 시험들)(가짜 세션 `test/helpers/fake_math_pen.dart`), ink_recognition `test/unit/latex_symbols_test.dart`·`test/unit/math_pen_builders_test.dart`·`test/widget/math_pen_session_test.dart`, app `test/modules/recognition_wiring_test.dart`(editorMathPenOf).

## 0. 한눈에 보는 결정

| 항목 | 결정 |
|---|---|
| 도구 | `EditorTool.math` 새 값(모달 도구). 툴바 '도구 더보기'(도형·텍스트 옆) `editor.toolbar.math`. `EditorExtensions.mathPen == null`이면 버튼 없음 |
| 획 | 수식 펜 획 = **보통 `ballpoint` 획**(`AddStrokes`, 획마다 한 단계). 묶음 소속은 **저장하지 않는다**(편집기 메모리만). 멈춤은 변환하지 않는다 |
| 묶음 | 편집기 `MathPenController`가 활성 묶음 하나(페이지 하나)를 가진다. 펜을 뗀 뒤 획 경계로 판정(§3) |
| 인식 | recog 쪽 `MathPenSession`이 펜을 뗀 뒤 **500 ms** 디바운스 → 기존 `MathRecognizer` 포트(`mathRecognizerProvider`). 새 접촉 = 타이머 끊기 + 진행 중 요청 `cancel` + 세대 번호(최신 답만) |
| 변환 계기 | ① 말풍선 탭 ② 다른 도구로 전환(**지우개 제외**) ③ 활성 묶음에서 먼 곳에 수식 펜 획(새 묶음 시작 + 옛 묶음 변환). 노트·페이지를 떠나면 **변환하지 않고 잉크로 남는다** |
| 변환 명령 | `CompositeCommand([RemoveElements(묶음 획), AddObjects([수식(ink 포함)])], label: 'recog-math-pen')` — 되돌리기 한 번에 손글씨 그대로 |
| 원본 획 보관 | `MathObject.ink: List<Stroke>`(JSON 키 `ink`, 없으면 `null`). 옛 JSON은 `ink` 없음 → 빈 목록. 옛 앱은 모르는 키 무시(page_object.dart:59) |
| 다시 열기 | 수식 펜 획의 **시작점**이 잉크가 있는 수식의 frame + 여백 안 → 펜을 뗄 때 `CompositeCommand([RemoveElements([수식]), AddStrokes(ink 새 id + 새 획)])` 한 단계. '손글씨로 열기'는 새 획 없이 같은 명령 |
| 고치기 | 수식 펜 도구에서 수식 탭 → 수식 말풍선 [고치기][손글씨로 열기]. 고치기 = 기존 `LatexEditorSheet`(editMath 흐름) + **기호 줄** |
| 엔진 없음 | 말풍선 '수식 인식이 꺼져 있어요' + (네이티브) [기기에서 수식 인식 켜기] + [LaTeX로 입력]. 말풍선 탭 = LaTeX 편집 창(손으로 입력) → 같은 변환 명령 |
| 연결 | 편집기에 새 확장 지점 `EditorExtensions.mathPen`(타입 `EditorMathPen`). recog는 `recognitionMathPen()`을 내보내고 앱 셸(`recognition_wiring.dart`)이 바꿔 끼운다 — 기존 선택·삽입 항목과 같은 길(00-overview:81 규칙 3) |

---

## 1. 근거로 읽은 코드·계약 (file:line)

- `EditorTool { pen, eraser, lasso, shape, text }` + 주석 "math are actions of the insert menu, not modal tools" — `packages/feature_editor/lib/src/tools/tool_state.dart:10-12`, 계획 04-editor.md:1536. → 주석·계획을 함께 고친다.
- 저장된 `activeTool`의 모르는 이름 → `pen`, 보고 없음 — 04-editor.md:1560-1568, `tool_controller.dart:432-446`. → 옛 앱이 `"math"`를 읽어도 안전.
- 상호작용 결정 순서 `beginInteraction` — `interaction_host.dart:215-415`(도구 switch 309~), 펜 점 가로채기 `interceptPenDot` `:747`, 손가락 탭 사슬 `tapGesture` `:897`.
- 한 제스처 = 한 `InkEdit` = 한 명령 `commitInkEdit` — `commands/editor_commands.dart:107`; 확장용 `executeForExtension` `:417`.
- `PenInteraction.end` → `_session.end` → `commitInkEdit` — `tools/pen_interaction.dart:146-158`.
- 확장 지점 모음 `EditorExtensions` — `di/editor_extensions.dart`(필드 목록 `:96-104`, 값 동등 `:113-127`). 피처 패키지는 recog를 import하지 않는다 — 00-overview.md:81, `tool/workspace_rules.yaml:9,14`(R8 의존 표).
- 앱 셸 연결 — `app/lib/src/modules/recognition_module.dart`(`ShellContribution` 만들기), `app/lib/src/modules/recognition_wiring.dart`(`RecognitionAction` → 편집기 항목), `app/lib/src/bootstrap/app_module.dart:86-118`(`ShellContribution`), `modules/feature_wiring_module.dart:269-285`(`EditorExtensions(...)`).
- 수식 객체 — `packages/note_core/lib/src/model/math_object.dart`(필드 `:22-27`, `transformed` `:68-79`, `copyTo` `:81-95`, `toJson` `:118-123`, `_fromJson` `:125-136`).
- 알려진 종류의 모르는 키는 무시, 필수 키 오류는 기록 버림 — `page_object.dart:56-59`.
- JSON 키 표·"종류별 키 집합은 고정 — 값이 없어도 키를 쓴다" — 00-overview.md:1153-1175. SYNC 대조: `packages/sync_engine/lib/src/model/field_units.dart:54-58`(`keysOf(pageObject)`), `:96-114`(`wholeUnitExcept` — 새 키는 한 단위에 합류, `:101-102`), `packages/sync_engine/test/support/entity_fixtures.dart:73`(`kPageObjectTypeKeys`), `test/integration/core_json_keys_test.dart`, `packages/note_core/test/model/object_json_test.dart:265-283`, 골든 `packages/note_core/test/goldens/json/math.json`·`math_no_engine.json`.
- "배포된 옛 앱이 없고 사용자 한 명이 모든 기기를 함께 갱신" — 00-overview.md:1191 (옛 앱이 `ink`를 지우는 위험의 크기).
- `AddStrokes`는 새 id만(삭제된 id 재사용 불가) — `edit/command_resolver.dart:505-527`; 객체 한도 검사 `checkObjectLimits` `:120`.
- `Stroke.fragment`는 `createdAt`을 유지 — `model/stroke.dart:75-86` (지우개 조각을 묶음에 이어 붙이는 근거).
- 기존 수식 만들기·명령 — `ink_recognition/lib/src/actions/object_builders.dart`(`replaceStrokesCommand` `:174`, `buildMathFromStrokes` `:211`, `relayoutMath` `:278`, `mathFontSizeFor`).
- LaTeX 편집 창 — `ink_recognition/lib/src/ui/latex_editor_sheet.dart`(`openLatexEditor` `:71`, `openToMath`, `LatexRecognition`, 취소·세대 `_recognize`).
- 패드의 멈춤 인식·취소 규칙 — `ui/math_pad_sheet.dart:106`(`kMathPadPause` 1 s), 05-library.md:2145-2147(6.14.3), 1983(6.11.6).
- 동작 순서 고정(INFRA S2-3) — `actions/recognition_actions.dart:88-95`(`RecognitionActionIds`), 05-library.md:753(4.4.4). 선택 메뉴 확장 항목은 막대에 2개까지 — `ui/overlays/selection_menu.dart:64`.
- 엔진 선택(기기 안 → 서버 → 수동) — `ink_recognition/lib/src/providers.dart:112-130`; 기기 안 엔진은 전처리 isolate + 런타임 UI 스레드 밖 — `ondevice/on_device_math_recognizer.dart:7-11`. 설정 타일 `settings/on_device_math_tile.dart`(`OnDeviceMathTile`).
- 오버레이 자리 — `viewport/page_viewport.dart:146-191`(Listener 안: 프레임·라벨, 밖 형제: `SelectionMenu` 등 — 탭이 라우터로 가지 않음).
- `InkPageController.hitTestObject` 규칙 — `ink_engine/lib/src/render/ink_page_controller.dart:570-598`.
- `MathPreview(latex, fontSize, color, onError)` — `ink_engine/lib/src/math/math_preview.dart:11-28`.
- R14(패키지 사이 공개 이름 겹침 금지) — `tool/src/export_names.dart:1-8`. R11(`dart format`) — `tool/src/rules.dart:4-7`.

---

## 2. 도구 (feature_editor)

### 2.1 모델

```dart
// src/tools/tool_state.dart
/// (v2) Image insertion is an action of the insert menu. (math pen, phase 1) math is a modal
/// tool when EditorExtensions.mathPen is set; otherwise it is never offered and a stored
/// "math" falls back to pen.
enum EditorTool { pen, eraser, lasso, shape, text, math }
```

- `ToolController.selectTool(EditorTool.math)` — `lastTool` 규칙 그대로(04-editor 6.2.1).
- `editor.toolSelection` 읽기: `"math"`인데 `mathPen == null`(인식 기능 끔·웹 빌드에서 recog 모듈 없음) → `pen`(보고 안 함 — 6.2.2와 같은 앞으로 호환 규칙). 판정은 `ToolController`가 아니라 툴바/호스트에서: 상태는 `math`로 두되 호스트가 `mathPen == null`이면 `pen`처럼 동작 → 저장값이 오가며 사라지지 않는다. (구현 단순화 대안: 로드 시 `pen`으로 바꿈 — 기능 스위치 왕복 시 도구가 바뀌는 것 외 문제 없음. 기본은 전자.)
- 읽기 전용 노트: 수식 펜 버튼 비활성(다른 그리기 도구와 같음).

### 2.2 도구 옵션 (`ToolOptions`, `editor.toolOptions`)

```dart
// src/tools/tool_options.dart — 새 필드
final core.StrokeStyle mathPenStyle; // tool == ballpoint 강제, normalized
// JSON: {..., "math": {"style": StrokeStyle.toJson()}}  — "v" 1 그대로(키 추가, 옛 앱 무시)
// 기본: StrokeStyle.defaultsFor(PenTool.ballpoint).copyWith(colorArgb: 0xFF1A1A1A).normalized()
```

- 읽기: `"math"` 없음/잘못됨 → 기본값(6.2.2 규칙, 잘못된 경우만 보고).
- 수식 펜 획은 일반 볼펜 획이므로 렌더·PDF·검색(`HandwritingText.isRecognitionInput`)·옛 앱 모두 그대로다.

### 2.3 UI · 키

| 위치 | 내용 | 키 |
|---|---|---|
| `ui/toolbar/overflow_tools_menu.dart` | 도형·텍스트 다음 '수식 펜'(아이콘 `Icons.functions`), 활성 시 접힌 단추에도 표시 | `editor.toolbar.math` |
| 같은 단추 두 번째 탭 | `MathPenPopup`(새 `ui/pen/math_pen_popup.dart`): 색 줄(기존 `ColorSwatch`·최근 색) + `WidthSlider` — 펜 팝업 부품 재사용 | `editor.mathPen.popup` |
| 호버 | 펜과 같은 `PenDotCursor`(스타일 = `mathPenStyle`) | — |
| 말풍선 층 | §6 | `editor.mathPen.bubble`, `editor.mathPen.formulaMenu`, `editor.mathPen.reopen` |

문구(편집기, `ui/editor_strings.dart`): `'수식 펜'`, `'손글씨로 열기'`, `'원래 손글씨가 너무 커서 다시 열 수 없게 바꿨어요.'`.

---

## 3. 묶음(그룹) — 소속 표시와 판정

### 3.1 저장하지 않는다

묶음 소속은 편집기 메모리(`MathPenController`)에만 있다. 획 자체에는 표시를 남기지 않는다(새 키 없음 → `Stroke` JSON·SYNC `keysOf(stroke)` 불변). 근거: 요구 2 "떠나도 획이 사라지지 않게" — 변환 안 된 묶음은 그냥 잉크로 남으면 되고, 다시 열 때 필요한 원본은 수식 쪽 `ink`에 있다(§5).

```dart
// src/tools/math_pen/math_pen_group.dart (feature_editor, 내부)
@immutable
final class MathPenGroup {
  final String pageId;
  final List<String> strokeIds;          // z 순서
  final Set<String> knownIds;            // 한 번이라도 소속이었던 id (되돌리기·다시하기로 돌아오면 다시 소속)
  final core.MathObject? reopenedFrom;   // 다시 연 묶음이면 그 수식(지워진 상태의 사본)
  final int revision;                    // 소속·획이 바뀔 때마다 +1
}
```

### 3.2 판정 (펜을 뗀 뒤, 획 경계로)

수식 펜 획이 커밋되면(`InkEdit.added.single`) 그 획 `s`에 대해:

1. **다시 열기 후보**(§7)가 있으면 그것이 이긴다 — 단, 활성 묶음에 합류 조건(2)도 맞으면 합류가 먼저(방금 쓰던 수식을 이어 쓰는 경우).
2. 활성 묶음 `G`가 같은 페이지에 있고 `gap(s, G) ≤ 조건`이면 합류.
3. 아니면 새 묶음 `{s}`; 옛 `G`는 변환 계기 ③(`newGroup`)으로 넘긴다.

```
H      = clamp(median(height of pointBounds of G's strokes, 높이 < 2 pt 인 점 획 제외), 8, 72) pt
         (G가 비면 s 자신의 높이, 같은 clamp)
gapX(m) = max(0, max(s.left − m.right, m.left − s.right))      m = G의 소속 획 하나(pointBounds)
gapY(m) = max(0, max(s.top − m.bottom, m.top − s.bottom))
합류    ⇔ ∃ m ∈ G: gapX(m) ≤ 1.5·H  ∧  gapY(m) ≤ 0.6·H   (가장 가까운 소속 획 기준 — 합 경계 아님, 굵기 부풀림 없음)
상한    G의 획 수 + 1 ≤ maxMathInkStrokes(400) ∧ G의 점 수 + s의 점 수 ≤ maxMathInkPoints(40 000) — 넘으면 새 묶음
```

| 상수 | 값 | 이유 |
|---|---|---|
| `kMathPenGapX` | 1.5·H | 'x²' 다음 '+1'처럼 기호 사이 간격(보통 0.3~1.0 H)과 지수를 넉넉히 넣고, 다음 식(보통 ≥ 2 H 띄움)은 뗀다 |
| `kMathPenGapY` | 0.6·H (검토 B-6으로 1.0에서 내림) | 분수 분자·분모, 첨자, 근호 안 줄(보통 0~0.5 H)을 넣는다. 줄 노트(8 mm ≈ 23 pt, H ≈ 12~15 pt)의 다음 줄은 이 줄 글자 아래 0.5~0.9 H라 대부분 뗀다 — 좁은 줄에 크게 쓰면 여전히 붙는다(잃는 것은 없음, 한 수식이 됨). 실기기 확인 항목 |
| 다시 열기 여백 | 옆 clamp(0.5·h, 8, 40) pt, 위아래 clamp(0.3·h, 4, 16) pt (h = frame 높이) | 옆('+1')은 넉넉히, 위아래는 좁게 — 수식 바로 아래에서 시작한 다음 줄이 그 수식을 다시 열지 않게(검토 B-6) |
| 말풍선 비움 | 위아래 1.0·H (`bubbleClearanceFactor`) | 합류 영역보다 넓게 — 다음 기호의 첫 획이 묶음 위에서 시작하는 일이 잦다 |
| H 범위 | 8~72 pt | 점·짧은 선이 H를 0으로 끌어내리지 않게, 큰 기호(∫, 큰 괄호)가 부풀리지 않게 중앙값 |

순수 함수 `mathPenJoins(members:, stroke:, groupPoints:, strokePoints:)`로 두고 단위 시험(§12)한다. 다른 페이지의 획은 언제나 3(새 묶음).

### 3.3 소속 맞추기 (되돌리기·원격·지우개)

- `MathPenController`는 활성 묶음 페이지의 `session.pageChanges(pageId)`를 구독한다. 변경마다 `strokeIds = knownIds ∩ 살아 있는 획`(z 순서). 비면 묶음 닫힘(변환 없음).
- 지우개 조각: (구현) 묶음 페이지의 변경에서, 사라진 소속 획과 `createdAt`·스타일·녹음이 같고 점 경계가 그 획 경계 안에 드는 새 획(`Stroke.fragment` — stroke.dart:75)을 `knownIds`·`strokeIds`에 더한다. 되돌리기로 원본이 돌아오면 `knownIds`라서 다시 소속, 조각은 사라져 빠진다.
- 소속이 바뀌면 `revision++` → `session.update(group)`(인식 다시 예약).

---

## 4. 상태 기계

### 4.1 두 층

| 층 | 어디 | 상태 |
|---|---|---|
| 묶음 수명 | feature_editor `src/tools/math_pen/math_pen_controller.dart`(노트 범위 provider `editorMathPenProvider`, `ChangeNotifier`) | `idle` · `writing` · `open` · `converting` (+ 기록 `lastConverted`) |
| 인식 | ink_recognition `src/math_pen/math_pen_session.dart`(`EditorMathPenSession` 구현) | `scheduled` · `recognizing` · `result(latex, engineId, usable)` · `failed(text)` · `noEngine` · `needsConsent` |

사용자 문서의 `idle/writing/recognizing/result/converted/reopened`와의 대응: recognizing·result = `open` 안의 인식 상태, converted = `idle` + `lastConverted`, reopened = `open` + `group.reopenedFrom != null`.

### 4.2 전이표 (묶음 수명)

| 지금 | 사건 | 다음 | 하는 일 |
|---|---|---|---|
| idle/open | 수식 펜 down | writing | `session.interrupt()`(타이머 끊기·요청 취소), 다시 열기 후보 계산(§7) |
| writing | 펜 점이 수식 frame 안(여백 없이) | 이전 상태 | 점 획 취소, 수식 말풍선(§8) |
| writing | 획 커밋 — 합류 | open | `session.update(G')` |
| writing | 획 커밋 — 다시 열기 | open(reopened) | 한 명령(§7) → 새 묶음 = ink 획 + 새 획. 옛 활성 묶음이 있었으면 그것은 `convert(newGroup)` |
| writing | 획 커밋 — 먼 곳 | open(새 묶음) | 옛 묶음 `convert(newGroup)`(뒤에서, §4.3) |
| writing | 커밋 거부(읽기 전용 경쟁 등) | 이전 상태 | 아무것도 안 함(획은 INK가 버림 — 기존 규칙) |
| open | 말풍선 탭 | converting | `session.convert(G, bubbleTap)` |
| open | 도구 전환(→ pen/lasso/shape/text) | converting | `convert(toolSwitch)` |
| open | 도구 전환(→ eraser), 임시 지우개 | open | 묶음 유지(§9). 지우개 → 다른 도구(수식 펜 아님)로 가면 그때 `convert(toolSwitch)` |
| open | 소속이 0개(되돌리기·삭제·원격) | idle | `session.clear()` |
| open | 읽기 전용이 됨, 페이지 삭제, 노트 화면 dispose | idle | `clear()` — **변환 없음, 잉크로 남음** |
| converting | 명령 성공 | idle | `lastConverted = {pageId, mathId, strokeIds}` |
| converting | 결과 없음·실패·시트 취소 | open 또는 idle | 말풍선 탭에서 취소 → open, 배경 변환 실패 → 그 묶음은 잉크로 남고 idle(새 묶음이 이미 활성일 수 있음) |
| idle | 되돌리기로 `lastConverted.mathId`가 사라지고 그 획들이 모두 다시 살아남 | open | 같은 묶음을 활성으로(명령 없음). 인식 결과 캐시(§5.3 서명) 재사용 |

### 4.3 배경 변환(계기 ②·③)

- 서명(정렬된 `id:updatedAt`)이 같은 **쓸 수 있는**(`usableLatex != null`) 결과가 이미 있으면 즉시 변환.
- 인식 중이면 그 답을 최대 `kMathPenBackgroundConvertTimeout = 10 s` 기다려 쓸 수 있으면 변환. 기다리는 동안 그 묶음의 획을 다시 건드리면(합류·지우개) 기다림을 취소하고 묶음을 다시 연다.
- 엔진 없음·동의 필요·실패·쓸 수 없는 결과·시간 초과 → 변환하지 않음(잉크로 남음). 시트를 저절로 띄우지 않는다(사용자가 다른 일로 넘어간 순간이기 때문).
- 변환 직전에 `context.liveStrokes(pageId, ids)`로 획이 그대로인지 확인(하나라도 없거나 `updatedAt`이 다르면 포기).

---

## 5. 수식 객체에 원본 획 보관 (note_core)

### 5.1 고른 방식과 버린 방식

| 안 | 내용 | 판정 |
|---|---|---|
| **A (채택)** | `MathObject.ink: List<Stroke>` — 획을 수식 JSON 안에 그대로(Stroke JSON) | 자기 완결, 새 엔티티·테이블·DB 스키마 없음, `Stroke` 코덱·`==`·`transformed` 재사용. 새 공개 타입 없음 |
| B | 획을 지운(soft-delete) 채 두고 수식에 `sourceStrokeIds` | 휴지통 비우기·동기화 압축이 지운 획을 영구 삭제하면 다시 열 수 없음. 같은 id 재추가는 금지(command_resolver.dart:526) |
| C | 획을 살려 두고 숨김 표시 | 옛 앱·PDF·썸네일·검색이 손글씨와 수식을 둘 다 그림. `Stroke` 키 추가 필요 |
| D | `MathInk` 새 값 타입(점만) | 새 공개 타입·코덱·시험. A보다 크고 얻는 것 없음 |

### 5.2 모델

```dart
// model/math_object.dart
MathObject({..., this.engineId, List<Stroke> ink = const [], ...}) : ink = List.unmodifiable(ink);
/// (math pen) The handwriting this formula was converted from (reopen). Each stroke has
/// pageId == this.pageId, version == null, deletedAt == null; ids are informational only
/// (reopen gives new ids). Page coordinates; moved / scaled / rotated with the formula
/// (transformed), never changed by an edit of the LaTeX (relayout keeps it).
final List<Stroke> ink;
```

- `copyWith({..., List<Stroke>? ink})`, `==`/`hashCode`에 `ListEquality<Stroke>` 추가.
- `transformed(m, scaleWidth)`: frame·글자 크기(기존) + `ink = [for s in ink: s.transformed(m, scaleWidth: scaleWidth)]`. 수식은 꼭짓점·변 핸들이 없어(object_resize.dart:107) 비균등 크기 변경 경로가 없다 → 닮음 변환만 → 잉크가 frame과 정확히 같이 움직인다. 붙여넣기·복제는 `transformed(move).copyTo` 경로라 함께 옮겨진다.
- `copyTo(id, pageId, createdAt)`: `ink`를 `s.copyWith(pageId: pageId, version: null)`로 복사. `copyWithMeta`: `ink` 유지.
- `estimatedBytes`: `160 + 2·latex.length + Σ s.estimatedBytes`(02-core 4.3 식에 항 추가).
- 한도(새 상수, `PageObjectLimits`): `maxMathInkStrokes = 400`, `maxMathInkPoints = 40000`(모든 획 점 합). `checkObjectLimits`(command_resolver.dart:120)에 `MathObject` 갈래 추가 — 넘으면 `ArgumentError`. recog는 넘는 묶음을 `ink: []`로 변환하고 알림(§2.3 문구).
- 렌더(INK)·PDF·검색 색인은 `ink`를 보지 않는다(바뀌는 곳 없음).

### 5.3 JSON (00-overview 7.2.7 표의 `math` 행 + `ink`)

```json
{"id":"0193…b6","pageId":"0193…3333","type":"math",
 "frame":[100.0,200.0,182.5,231.0,0.0],
 "latex":"x^{2}+1",
 "style":{"colorArgb":4279900698,"fontSizePt":24.5},
 "engine":"ondevice/mfr-…",
 "ink":[
   {"id":"0193…c1","pageId":"0193…3333","style":{"tool":"ballpoint", …},
    "points":"<StrokePointsCodec base64>","recordingId":null,"recordingOffsetMs":null,
    "createdAt":1793750400001,"updatedAt":1793750400001,"deletedAt":null,"version":null}
 ],
 "createdAt":1793750400005,"updatedAt":1793750400005,"deletedAt":null,"version":"…"}
```

- **쓰기**: 키는 언제나 쓴다(7.2.7 v2.1 "값이 없어도 키를 쓴다" — 00-overview.md:1175). 잉크가 없으면 `"ink": null`(`engine: null`과 같은 모양, 빈 배열 대신 null로 바이트 절약).
- **읽기**: 키 없음(옛 JSON)·`null` → `[]`. 배열이지만 항목이 깨짐(키 누락·잘못된 base64) → **`ink`만 `[]`로 읽고 수식은 살린다**. 결정 이유: CORE 6.2.6은 알려진 종류의 필수 키 오류면 기록을 버리지만(page_object.dart:56-59), `ink`는 선택 키이고 수식 자체가 사용자 내용이다. 이 경우 다시 쓰면 `ink`는 `null`이 된다(정규화가 아니라 잃음 — 깨진 자료라 허용, §13 위험 R3에 기록).
- **옛 앱**: `MathObject._fromJson`이 `ink`를 무시하고 수식은 그대로 보이고 동기화된다. 옛 앱이 그 수식을 옮기거나 색을 바꾸면 자기 JSON(키 없음)이 그 단위를 이겨 `ink`가 사라진다 → 그 수식은 다시 열 수 없게 될 뿐 손실은 아니다. 배포된 옛 앱이 없으므로(00-overview.md:1191) 현실적 위험은 개발 기기 사이뿐.
- **SYNC**: `keysOf(pageObject)`에 `'ink'` 추가(field_units.dart:54-58), `kPageObjectTypeKeys['math']`에 `'ink'` 추가(entity_fixtures.dart:73). `wholeUnitExcept(pageObject)`는 바꾸지 않는다 → `ink`는 frame·latex·style과 **한 병합 단위**(field_units.dart:96-102 "A key added … joins the one unit"). 그래서 동시 편집에서 frame과 ink가 서로 다른 기기 값으로 섞이지 않는다.
- **필드 버전**: `UpdateObjects`는 값이 바뀐 키만 새 버전(00-overview 7.2.3). 고치기(relayout)는 `ink`를 바꾸지 않는다.
- **DB**: `page_objects.data_json`에 들어감 → 스키마 불변. 백업: JSON 왕복.
- **골든**: `math.json`·`math_no_engine.json`에 `"ink": null` 추가, 새 `math_ink.json`(획 2개). `core_json_keys_test`의 `_kindOf`에 `'math_ink' => EntityKind.pageObject`.

---

## 6. 말풍선 위젯과 층

### 6.1 층 (feature_editor)

- 새 `ui/overlays/math_pen_bubble_layer.dart` — `MathPenBubbleLayer`(ConsumerWidget). `page_viewport.dart`의 **Listener 바깥 형제**로 `SelectionMenu` 바로 앞에 둔다(:182-183) → 말풍선 탭이 입력 라우터로 가지 않는다(획이 되지 않음).
- 위치: 묶음 경계(page pt, `G`의 획 bounds 합)를 `viewport.pageToScreen`으로 바꿔, 그 **위 8 px**, 가로 가운데를 경계 왼쪽에 맞춤. 위 공간이 말풍선 높이보다 적으면 아래. 화면 안으로 clamp(좌우 8 px). `Listenable.merge([controller, viewport, session.state])`로 다시 그림(NewTextBoxOutline 패턴 — new_text_box_outline.dart).
- 크기: 최대 너비 320 px, 최소 높이 44 px(탭 목표), 둥근 모서리, `Material` elevation 2. 선택이 드래그 중이거나 텍스트 세션 중이면 숨김.
- 내용은 recog가 만든다: `session.buildBubble(context, MathPenBubbleView(group, onTap))`. 편집기는 틀(위치·그림자·탭 영역 `InkWell` + 키 `editor.mathPen.bubble`)만.

### 6.2 내용 (ink_recognition `src/math_pen/math_pen_bubble.dart`)

| 인식 상태 | 보임 | 탭 |
|---|---|---|
| scheduled / recognizing | `'인식 중…'`(작은 진행 표시) + 직전 결과가 있으면 흐리게 | 결과가 오면 변환(대기 표시 `'인식이 끝나면 바꿔요'`) |
| result(usable) | `MathPreview(latex, fontSize: 20, color: onSurface)`를 `FittedBox(scaleDown)` | 변환 |
| result(unusable — `InkMathRenderer.validate` 오류) | LaTeX 글자(고정폭, 한 줄 생략) + `'그릴 수 없는 결과예요. 눌러서 고쳐요.'` | LaTeX 편집 창(결과를 채워서) |
| failed | `RecognitionStrings.mathFailure(...)` 문구 + [다시] | LaTeX 편집 창(빈 칸 + 획 보기) |
| needsConsent | `'외부 수식 인식 동의가 필요해요.'` | LaTeX 편집 창(동의 카드 포함 — 기존 `LatexRecognition` 흐름) |
| noEngine | §10 | §10 |

키(recog, 부록 C 밖): `recog.mathPen.preview`, `recog.mathPen.status`, `recog.mathPen.retry`, `recog.mathPen.enableOnDevice`, `recog.mathPen.typeLatex`.

---

## 7. 다시 열기 — 판정과 명령

### 7.1 적중

수식 펜 down의 페이지 점 `p`에서(호스트, `beginInteraction`의 `case EditorTool.math`):

```
후보 = 페이지의 활성 MathObject 중 ink.isNotEmpty 이고
       frame.contains(p, tolerance: margin(m)) 인 것 — 여러 개면 frame까지 거리가 가장 짧은 것, 같으면 위(z)
margin(m) = clamp(0.5 × m.frame.rect.height, 8, 40) pt   (kMathReopenMarginFactor 0.5, 범위 8~40 pt)
```

- `ElementFrame.contains(p, tolerance:)`(00-overview 7.2.2)를 쓴다 — 회전된 수식도 정확. 후보는 `session.pageIfLoaded(pageId).objects`에서(INK `hitTestObject`는 종류를 고르지 않고 여백 개념이 다름).
- 잉크가 없는 수식(수식 패드로 넣은 것, 옛 앱이 지운 것) 근처는 보통 획 → 새 묶음.

### 7.2 펜을 뗄 때

- 펜 점(4 px·200 ms — 04-editor 6.3.7)이고 `p`가 frame **안**(여백 0)이면 → 점 획 취소, 수식 말풍선(§8). 라우터의 `interceptPenDot` 경로에 ④m 단계로 넣는다(테이프 ②·탭 재생 ③ 다음).
- 아니면 한 명령으로 커밋:

```dart
// feature_editor src/tools/math_pen/math_pen_commands.dart
core.CompositeCommand reopenCommand(core.MathObject math, {
  required String Function() newId, required core.EpochMillis now,
  core.Stroke? withStroke, // the pen stroke of this contact (InkEdit.added.single)
}) => core.CompositeCommand([
  core.RemoveElements(pageId: math.pageId, elementIds: [math.id]),
  core.AddStrokes(pageId: math.pageId, strokes: [
    for (final s in reopenedStrokes(math, newId: newId, now: now)) s,
    if (withStroke != null) withStroke,
  ]),
], label: withStroke == null ? 'editor-math-reopen' : 'editor-math-reopen-write');

/// ink with new ids, pageId = math.pageId, createdAt kept (z order), updatedAt = now,
/// version / deletedAt null; colour = math.style.colorArgb when the formula was recoloured
/// (its colour differs from dominantColorOf(ink)), else each stroke's own.
List<core.Stroke> reopenedStrokes(core.MathObject math, {...});
```

- 커밋 경로: `EditorCommands.commitInkEdit(controller, edit, {core.EditCommand? before})` 새 선택 인자 — `before`가 있으면 `CompositeCommand([before.commands…, edit.toCommand()])`를 한 번 실행하고, 거부되면 `discardEdit(edit)`(기존). 이렇게 하면 "다시 열고 + 이어 쓴 획"이 **되돌리기 한 번**이다. 다시 열기 명령이 실패하면(그 사이 원격 삭제 등 `ArgumentError`) `before` 없이 획만 다시 커밋 — 필기는 언제나 남는다(04-editor 6.3.5 "가로채지 않은 펜 입력은 언제나 획").
- `PenInteraction`에 선택 인자 `commit: bool Function(ink.InkEdit edit)?`를 더해 수식 펜이 커밋을 대신한다(기본은 지금 경로 그대로).
- 다시 연 묶음: `strokeIds = reopened ids + 새 획`, `reopenedFrom = math`. 세션은 `update`에서 `reopenedFrom.latex`를 **새 획 없이 다시 연 서명**에 대한 결과로 미리 넣어 둔다 → '손글씨로 열기' 직후 바로 탭하면 (사용자가 손으로 고친 것까지) 그대로 돌아온다. 획이 바뀌면 인식이 다시 돈다(요구 4: old+new 전체).
- 되돌리기: 다시 열기 단계를 되돌리면 수식이 돌아오고 다시 연 획은 사라짐 → 묶음 소속 0 → 닫힘.

---

## 8. 수식 탭 메뉴

- 수식 펜 도구에서 수식 위 **손가락 탭**(`tapGesture(1)` 사슬 ③ 다음 새 ④m) 또는 frame 안 **펜 점**(§7.2) → 편집기가 그 수식에 붙은 '수식 말풍선'을 같은 층에 띄운다(`editor.mathPen.formulaMenu`). 항목:
  - **[고치기]** — `session.fix(context, math)` → recog가 기존 `openLatexEditor`(latex_editor_sheet.dart:71, editMath 흐름 = `UpdateObjects` 한 단계, `relayoutMath`로 가운데 유지, `engineId 'manual'`, **`ink` 유지**)를 기호 줄과 함께 연다.
  - **[손글씨로 열기]**(잉크가 있을 때만, 키 `editor.mathPen.reopen`) — 편집기 자신이 `reopenCommand(math)` 실행 + 묶음 활성.
  - [LaTeX 복사] — recog `copyDirect` 재사용(선택 사항, 첫 await 전 `Clipboard.setData` 규칙 — 05-library LIBRARY-M8).
- 다른 도구(올가미 탭 선택 등)의 선택 메뉴: 기존 `recog.editMath`('수식 편집')가 그대로 같은 시트(기호 줄 포함)를 연다. 편집기는 단일 수식 + 잉크 + `mathPen != null`일 때 '⋯'에 내장 항목 **'손글씨로 열기'**(`editor.selectionMenu.reopenMath`)를 더한다(누르면 도구를 수식 펜으로 바꾸고 다시 연다). 확장 항목 순서(4.4.4 — recognition_actions.dart:88-95)는 건드리지 않는다.

---

## 9. 열린 묶음에서의 지우개

- 툴바 지우개로 바꾸거나 펜 버튼·지우개 끝(임시 지우개 — 04-editor 6.2.3)으로 지워도 묶음은 **열린 채**다(전환 계기 ②의 예외). 지우는 동안 `session.interrupt()`(접촉 시작 시), 커밋 뒤 §3.3으로 소속 갱신 → `update` → 500 ms 뒤 묶음 전체 재인식(요구 5a).
- 부분 지우개 조각은 묶음에 남는다(§3.3), 획 지우개는 빠진다. 수식 객체는 지우개로 지워지지 않는다(tool_state.dart:24-26 `eraseShapes` 주석 — 기존 규칙).
- `returnToPreviousTool`이 켜져 있으면 지우개가 끝나고 수식 펜으로 돌아온다(기존 규칙) → 이어 쓰기.
- 변환된 수식을 고쳐 쓰려면: 다시 열기(이어 쓰기 또는 '손글씨로 열기') → 지우개 → 다시 쓰기 → 탭.

---

## 10. 엔진 없음 · 웹

- 판정: `scope.math.isAvailable == false`(= `ManualOnlyMathRecognizer` — math_recognizer.dart). 말풍선: `'수식 인식이 꺼져 있어요.'`
  - [기기에서 수식 인식 켜기] — `onDevicePlatform`에 모델 관리자가 있을 때만(안드로이드·iOS, 웹·데스크톱 아님). 누르면 시트에 기존 `OnDeviceMathTile`(settings/on_device_math_tile.dart)을 그대로 띄운다 — 설정 화면 길을 앱 셸에 새로 만들지 않는다. 켜고 모델이 준비되면 `mathRecognizerProvider`가 바뀌고(providers.dart:115) 세션이 새 엔진으로 즉시 재인식.
  - [LaTeX로 입력] = 말풍선 탭과 같음: `LatexEditorSheet`(제목 '수식으로 변환', 기본 '수식으로 바꾸기', `LatexRecognition(engine: ManualOnly, strokesPage/strokes = 묶음)` → `manualOnly` 안내 + 획 보기) → 누르면 **같은 변환 명령**(§11 `buildMathFromPen`, `engineId 'manual'`, ink 포함).
- 웹: 기기 안 엔진 없음(on_device_platform_stub.dart). 서버 엔진이 설정됐으면(`MATH_ENDPOINT`) 동의 흐름, 아니면 위 엔진 없음 흐름. 그 밖의 동작(입력 판정 `StylusContactRule.web`, 펜 점, 말풍선)은 같다. PNG 렌더(`renderMathPng`)는 서버 엔진일 때만 만든다 — 기기 안 엔진은 traces만 쓰므로 UI 스레드의 래스터를 아낀다(§11.2).
- 배경 변환(§4.3)은 엔진 없음이면 일어나지 않는다 → 도구를 바꾸면 그냥 잉크로 남는다.

---

## 11. 인식 호출 · 변환 명령 (ink_recognition)

### 11.1 확장 지점 (계약 7.2.10 추가 — feature_editor `di/editor_extensions.dart`)

```dart
@immutable
class EditorExtensions { …; final EditorMathPen? mathPen; } // null → no math pen tool (== by identity of open)

@immutable
class EditorMathPen {
  const EditorMathPen({required this.open});
  /// Once per note screen (editor body mounted); disposed with it.
  final EditorMathPenSession Function(EditorMathPenContext context) open;
}

/// Built by the editor per note screen (no ==).
@immutable
class EditorMathPenContext {
  final String noteId;
  final core.PageSize Function(String pageId) pageSizeOf;
  /// ONE command (one undo step); throws like NoteSession.execute (EditorCommands.executeForExtension).
  final void Function(core.EditCommand command) execute;
  /// The current strokes for [ids] on [pageId] (z order) or null when any is gone / changed since [revision].
  final List<core.Stroke>? Function(String pageId, List<String> ids) liveStrokes;
  /// The editor body's context (mounted while the screen is open) — sheets, ActionRun.capture.
  final BuildContext Function() bodyContext;
}

@immutable
class EditorMathGroup {             // a value copy made by the editor
  final String pageId; final List<core.Stroke> strokes; final Rect boundsPt;
  final int revision; final core.MathObject? reopenedFrom;
}

enum EditorMathConvertTrigger { bubbleTap, toolSwitch, newGroup }

abstract interface class EditorMathPenSession {
  void update(EditorMathGroup group);     // strokes changed → schedule recognition
  void interrupt();                       // a new contact: stop the timer, cancel in flight
  void clear();                           // the group is gone, no conversion
  /// Converts [group] with ONE execute; completes true when it ran. bubbleTap may open a sheet.
  Future<bool> convert(EditorMathGroup group, EditorMathConvertTrigger trigger,
      {bool Function()? stillWanted}); // (검토 반영) 배경 변환은 execute 직전에 묻는다
  Future<void> fix(core.MathObject math); // '고치기'
  ValueListenable<Object?> get bubbleState; // repaint signal for the layer
  Widget buildBubble(BuildContext context, EditorMathGroup group, VoidCallback onTap);
  void dispose();
}
```

- 이름이 recog 쪽과 겹치지 않는다(R14): recog는 `RecognitionMathPen`·`recognitionMathPen()`을 내보내고, 앱 셸 `recognition_wiring.dart`의 `editorMathPenOf(RecognitionMathPen)`가 위 타입으로 바꾼다(선택 항목 `selectionMenuItemOf`와 같은 모양). recog의 세션 클래스는 `src/`의 내부 이름.
- `ShellContribution`에 `mathPen` 필드(`app_module.dart:86`), `hasEditorItems`에 포함; `FeatureWiringModule`이 `EditorExtensions(mathPen: …)`로 넘김(`feature_wiring_module.dart:279`). 인식 기능 스위치를 끄면 모듈이 없으므로 도구도 사라진다(V15와 같은 규칙).

### 11.2 인식

- `kMathPenRecognizeDelay = 500 ms`(사용자 요구 0.4~0.6 s의 가운데; 패드의 1 s보다 짧음 — 말풍선은 변환하지 않으므로 빨리 보여도 된다). `update`마다 타이머 다시.
- 시작: 세대 `g = ++generation`, `cancel = Completer()`, 입력 = `MathInput(traces: strokes.map(HandwritingTrace.fromStroke), png: 서버 엔진일 때만 renderMathPng(...))`(math_png.dart), `engine.recognize(input, cancel: cancel.future)`. 엔진은 run 시작 시 `RecognitionActionScope`처럼 컨테이너에서 한 번 읽는다(`ProviderScope.containerOf(bodyContext())` — 첫 await 전).
- `interrupt`/`update`/`clear`/`dispose` → 타이머 끊기 + `cancel.complete()` + `generation++`. 답은 `g == generation`이고 서명이 같을 때만 반영(최신 답만 — 요구 1). `RecognizerCancelled`는 조용히 무시.
- UI 스레드 밖: 기기 안 엔진은 전처리 isolate + 런타임이 UI 스레드 밖(on_device_math_recognizer.dart:7-11), 서버 엔진은 http. 세션 자체는 가벼운 상태만.
- 결과 캐시: `Map<서명, MathResult>` 최근 4개(되돌리기로 돌아온 묶음·다시 연 묶음 재사용).

### 11.3 변환 명령

```dart
// object_builders.dart — 새 함수 (기존 buildMathFromStrokes 옆)
/// Math pen: f = mathFontSizeFor(boundsHeight: ink height, baseHeight: layout(latex,18).height);
/// frame LEFT = ink bounds left, vertically centred on the ink; colour = dominantColorOf;
/// ink = the group strokes (z order, version null) — [] when over the ink limits.
core.MathObject? buildMathFromPen({required String id, required String pageId,
    required core.EpochMillis nowMs, required String latex, required String engineId,
    required List<core.Stroke> strokes, required Rect inkBoundsPt});

const String kMathPenLabel = 'recog-math-pen';
// command = replaceStrokesCommand(pageId:, strokes: group strokes, object: math, label: kMathPenLabel)
//         = CompositeCommand([RemoveElements(ids), AddObjects([math])])  — object_builders.dart:174
```

- 높이 기준은 획의 **점 경계**(굵기 부풀림 없는 `pointBounds`) — "잉크 높이와 대략 같게"(요구 3). 넓이는 레이아웃이 정한다(왼쪽 맞춤이므로 오른쪽으로 늘거나 준다).
- 실행은 `context.execute` 한 번(`ActionRun.execute`의 '최대 1회' 규칙 재사용). `ReadOnlyNoteException` → `RecognitionStrings.readOnly` 스낵바, 묶음 유지.
- 객체 한도(페이지 2000개) 넘으면 → 기존 알림, 변환 없음.

---

## 12. LaTeX 편집 창 기호 줄

`latex_editor_sheet.dart`의 `TextField` 아래(칩 줄 위)에 가로 스크롤 `LatexSymbolRow`. 세 흐름(editMath · toMath · 수식 펜 수동)에 모두 보인다. 수식 패드 시트는 이번에 바꾸지 않는다.

```dart
// src/ui/latex_symbols.dart (internal)
@immutable final class LatexSymbol { final String id, label, snippet; final int caret; } // caret: offset in snippet
const kLatexSymbols = [
  LatexSymbol('frac', '분수', r'\frac{}{}', 6),  LatexSymbol('pow', '지수', '^{}', 2),
  LatexSymbol('sub', '아래첨자', '_{}', 2),         LatexSymbol('sqrt', '√', r'\sqrt{}', 6),
  LatexSymbol('int', '∫', r'\int ', 5),          LatexSymbol('sum', '∑', r'\sum ', 5),
  LatexSymbol('lim', 'lim', r'\lim_{}', 6),      LatexSymbol('pi', 'π', r'\pi ', 4),
  LatexSymbol('infty', '∞', r'\infty ', 7),      LatexSymbol('pm', '±', r'\pm ', 4),
  LatexSymbol('times', '×', r'\times ', 7),      LatexSymbol('div', '÷', r'\div ', 5),
  LatexSymbol('le', '≤', r'\le ', 4),            LatexSymbol('ge', '≥', r'\ge ', 4),
  LatexSymbol('ne', '≠', r'\ne ', 4),            LatexSymbol('theta', 'θ', r'\theta ', 7),
  LatexSymbol('alpha', 'α', r'\alpha ', 7),      LatexSymbol('beta', 'β', r'\beta ', 6),
  LatexSymbol('paren', '( )', '()', 1),
];
/// Pure: [snippet] replaces the selection; a non-empty selection goes inside the first
/// braces / parentheses of the snippet when it has some; the caret lands at [caret]
/// (after the wrapped text when wrapping).
TextEditingValue insertLatexSymbol(TextEditingValue value, LatexSymbol symbol);
```

- 단추: `TextButton`(최소 44×44, 키 `recog.sheet.symbol.<id>`), `focusNode`가 없는 단추라 `TextField` 포커스·키보드가 유지되도록 `canRequestFocus: false`로 감싸고 누른 뒤 `_focus.requestFocus()`. 포커스가 없었거나 선택이 무효(-1)면 끝에 넣는다.
- 삽입은 사용자 편집으로 친다(`_programmatic = false` → `_manualEdited`, engineId 'manual' — 6.14.4 규칙 그대로). 150 ms 검증·미리보기는 기존.

---

## 13. 바꿀·더할 파일 전체

### note_core (CORE)
- 변경 `lib/src/model/math_object.dart` — `ink` 필드·`copyWith`·`transformed`·`copyTo`·`copyWithMeta`·`estimatedBytes`·`toJson`/`_fromJson`·`==`.
- 변경 `lib/src/model/page_object.dart` — `PageObjectLimits.maxMathInkStrokes`·`maxMathInkPoints`.
- 변경 `lib/src/edit/command_resolver.dart` — `checkObjectLimits` 수식 갈래.
- 변경 `test/model/object_json_test.dart`(키 집합 `math`에 `ink`, 왕복·키 없음·null·깨진 항목), `test/goldens/json/math.json`·`math_no_engine.json`(+`"ink": null`), 새 `test/goldens/json/math_ink.json`, `test/model/object_transform_test`류(잉크가 함께 변형), resolver 한도 시험, `test/api_surface_test.dart`(새 상수·생성자 인자).
- 변경 `docs/plans/m5-7/02-core.md` 4.2·4.3·6.3 (식·키 표).

### sync_engine (SYNC)
- 변경 `lib/src/model/field_units.dart` — `keysOf(pageObject)`에 `'ink'`.
- 변경 `test/support/entity_fixtures.dart` — `kPageObjectTypeKeys['math']`에 `'ink'`; `test/integration/core_json_keys_test.dart` `_kindOf`에 `math_ink`; `test/model/field_units_test.dart`(ink가 한 단위 안), `test/merge/field_merge_test.dart`에 '옛 스냅샷(ink 없음) vs 새 스냅샷' 사례.

### feature_editor (EDITOR)
- 변경 `lib/src/tools/tool_state.dart`(enum·주석), `tool_controller.dart`(폴백 규칙), `tool_options.dart`(`mathPenStyle`, JSON `"math"`).
- 새 `lib/src/tools/math_pen/math_pen_group.dart`(값·판정 `mathPenJoins`·상수), `math_pen_controller.dart`(상태 기계·pageChanges 구독·도구 전환 감시·lastConverted), `math_pen_commands.dart`(`reopenCommand`·`reopenedStrokes`·적중 `reopenCandidateAt`).
- 변경 `lib/src/tools/interaction_host.dart`(`case EditorTool.math`, `interceptPenDot` ④m, `tapGesture` ④m, 지우개 커밋 전달, 호버), `pen_interaction.dart`(`commit` 선택 인자), `erase_interaction.dart`(`onCommittedEdit`), `commands/editor_commands.dart`(`commitInkEdit(before:)`).
- 변경 `lib/src/di/editor_extensions.dart`(새 타입 5개 + 필드), `lib/feature_editor.dart`(export `show`에 새 이름), `lib/src/scope/editor_scope.dart`(`editorMathPenProvider`, 세션 수명).
- 새 `lib/src/ui/overlays/math_pen_bubble_layer.dart`, `lib/src/ui/pen/math_pen_popup.dart`; 변경 `viewport/page_viewport.dart`(층 추가), `ui/toolbar/overflow_tools_menu.dart`, `ui/toolbar/editor_toolbar.dart`(접힌 단추 아이콘), `ui/overlays/selection_menu.dart`('⋯' 손글씨로 열기), `ui/editor_strings.dart`.
- 시험: §14. `test/unit/api_surface_test.dart` 갱신.
- 문서: `docs/plans/m5-7/04-editor.md` 6.2.1·6.2.4·6.3.5 표·6.3.6 8단계·4.2(7.2.10 인용)·부록 A·C.

### ink_recognition (LIBRARY)
- 새 `lib/src/math_pen/math_pen_session.dart`(세션·디바운스·취소·캐시·배경 변환), `math_pen_bubble.dart`(말풍선 내용), `math_pen.dart`(`RecognitionMathPen`·`recognitionMathPen()` 공개 값).
- 변경 `lib/src/actions/object_builders.dart`(`buildMathFromPen`, `kMathPenLabel`), `lib/src/ui/latex_editor_sheet.dart`(기호 줄, 수식 펜 수동 변환 진입 `openMathPenEditor`), 새 `lib/src/ui/latex_symbols.dart`, `lib/src/l10n/recognition_strings.dart`(아래 문구), `lib/ink_recognition.dart`(export 2개 — R14).
- 새 문구(기존 어조): `mathPenTitle '수식 펜'`, `mathPenRecognizing = recognizing('인식 중…')` 재사용, `mathPenWaiting '인식이 끝나면 바꿔요.'`, `mathPenUnusable '그릴 수 없는 결과예요. 눌러서 고쳐요.'`, `mathPenOff '수식 인식이 꺼져 있어요.'`, `mathPenEnableOnDevice '기기에서 수식 인식 켜기'`, `mathPenTypeLatex 'LaTeX로 입력'`, `mathPenConsent '외부 수식 인식 동의가 필요해요.'`, `fixMath '고치기'`, `inkTooLarge '원래 손글씨가 너무 커서 다시 열 수 없게 바꿨어요.'`, 기호 라벨 `'분수'·'지수'·'아래첨자'`.
- 문서: `docs/plans/m5-7/05-library.md` 4.2 내보내기·6.14~6.15 옆 새 절 '수식 펜'.

### app (INFRA)
- 변경 `lib/src/bootstrap/app_module.dart`(`ShellContribution.mathPen`), `lib/src/modules/recognition_module.dart`(기여), `lib/src/modules/recognition_wiring.dart`(`editorMathPenOf`), `lib/src/modules/feature_wiring_module.dart`(넘김). 시험: `app_module_context_test`·`feature_switch_test`(인식 끔 → 도구 없음)·wiring 단위 시험.

### 계약 (00-overview — 총괄)
- 7.2.2 `MathObject` 블록·`PageObjectLimits`, 7.2.7 키 표 `math` 행 + `ink`, 7.2.8 SYNC 키, 7.2.10 `EditorExtensions.mathPen`·새 타입, 7.2.11 recog 내보내기 2개, 변경 표에 새 행(예: C2-4x '수식 펜 — 추가'), 부록 C 키.

---

## 14. 시험 계획

### 단위 (VM)
- note_core: `MathObject` JSON 왕복(ink 있음/없음/`null`/키 없음/깨진 항목 → `[]`), 골든 3개, 키 집합 고정(`object_json_test` 6.3 그룹), `transformed`가 ink 점·굵기·캘리그래피 각까지 같은 `m`, `copyTo`가 ink pageId 갱신, `estimatedBytes`, `checkObjectLimits` 한도, `==`.
- sync_engine: `field_units_test`(ink ∈ keysOf, 한 단위), `core_json_keys_test`(골든 `math_ink`), 병합: 옛 스냅샷이 이기면 ink 없음, 새 스냅샷이 이기면 ink 있음(결정적).
- feature_editor: `math_pen_group_test`(합류 표 — 지수·분수·다음 식·다음 줄·점 획·H clamp·400 상한·다른 페이지), `math_pen_controller_test`(전이표 행마다: 펜 down → interrupt, 먼 획 → 옛 묶음 convert(newGroup), 도구 전환 → convert(toolSwitch), 지우개 전환 → 유지, 지우개 → 펜 → convert, 되돌리기로 소속 0 → clear, 변환 되돌리기 → 다시 활성, 읽기 전용 → clear, dispose → 변환 없음), `math_pen_commands_test`(다시 열기 명령 모양·새 id·createdAt 유지·색 규칙·적중 여백 회전 frame), `tool_options_test`(`"math"` 읽기·폴백), `tool_controller_test`(`"math"` 저장·mathPen 없을 때 pen처럼).
- ink_recognition: `math_pen_session_test`(FakeAsync: 500 ms 디바운스, interrupt가 진행 중 요청 cancel·세대, 늦은 옛 답 무시, 서명 캐시, 배경 변환 10 s 상한·쓸 수 없는 결과 → 변환 없음, execute 최대 1회, ReadOnly 처리), `object_builders_test`(`buildMathFromPen` 왼쪽 맞춤·세로 가운데·글자 크기·ink 한도 초과 → `[]`, 명령 라벨), `latex_symbols_test`(`insertLatexSymbol` — 커서·선택 감싸기·선택 없음·끝 삽입, 목록이 요구 기호 전부), `strings_contract_test`(새 문구).

### 위젯 (VM)
- feature_editor `widget/math_pen_test.dart`: 가짜 `EditorMathPen`(기록하는 세션)으로 — 툴바 단추는 `mathPen` 있을 때만, 수식 펜 획이 보통 획으로 커밋, 말풍선 위치(위/아래 뒤집기, 화면 clamp), 말풍선 탭이 라우터로 가지 않고 `convert(bubbleTap)`, 수식 근처 획 → 한 명령으로 다시 열기 + 되돌리기 한 번에 원래대로, frame 안 펜 점 → 수식 메뉴(점 획 없음), 손가락 탭 → 수식 메뉴, 선택 메뉴 '⋯'의 손글씨로 열기.
- ink_recognition `widget/math_pen_bubble_test.dart`: 상태별 내용(인식 중·결과 MathPreview 키·쓸 수 없음·실패 [다시]·동의·엔진 없음 단추, 웹에서 '기기에서' 단추 없음), `widget/latex_editor_sheet_test.dart`에 기호 줄(누르면 커서가 중괄호 안, 포커스 유지, 미리보기 갱신).

### 통합 (VM, 가짜 인식기)
- `feature_editor/test/integration/math_pen_flow_test.dart` 또는 앱 `app/test/…/math_pen_smoke_test.dart`: 실제 CORE(`openTestNoteStore`) + 실제 INK + recog `FakeMathRecognizer`(testing.dart — 입력 획 수로 정한 답, 지연·취소 기록) + 앱 셸 연결 — 시나리오: ① x² 쓰기 → 말풍선 'x^{2}' → 탭 → 수식 1개·획 0개·ink 2획 ② 되돌리기 → 획 2개 정확히(같은 id·점) ③ 다시하기 → 수식 ④ 옆에 '+1' → 다시 열기 + 재인식 → 'x^{2}+1' → 펜 도구로 전환 → 배경 변환 ⑤ 고치기 → 기호 줄로 `\frac{}{}` 넣고 적용 → `UpdateObjects`, ink 유지 ⑥ 손글씨로 열기 → 지우개로 한 획 지우기 → 재인식 → 탭 ⑦ 엔진 없음(`ManualOnly`) → 말풍선 안내 → 탭 → LaTeX 입력 → 변환 ⑧ 노트 닫기 시 열린 묶음은 획 그대로(다시 열어 확인) ⑨ 빠르게 쓰는 동안 늦은 답이 반영되지 않음.
- 브라우저(`--platform chrome --package feature_editor` / `ink_recognition`): 말풍선 탭·웹 스타일러스 접촉 규칙에서 수식 펜 획, 기호 줄 포커스(웹 IME), `math_ink` 골든 왕복(`note_core` 브라우저 시험 한 줄).
- 저장소 규칙: `dart run tool/ws.dart check --strict`(R11 format·R14 새 이름), 루트 `flutter analyze`, `ws test`, `dart test tool/test`, `flutter build web --release` + `ws web-budget check`(새 위젯·문구만 — 예산 영향 작음, 확인).

---

## 15. 위험과 제약

| # | 위험 / 제약 | 대응 |
|---|---|---|
| R1 | 계약 변경(7.2.2·7.2.7·7.2.8·7.2.10·7.2.11) — 승인 전 구현 금지 규칙(04-editor 12.1) | 이 노트로 CP 한 묶음을 올리고, 1단계 구현 첫 커밋 전에 00-overview 변경 행 반영 |
| R2 | 옛 앱이 수식을 고치면 `ink` 소실(단위 병합에서 옛 스냅샷 승리) | 수식은 남음, 다시 열기만 불가. 배포된 옛 앱 없음(00-overview:1191). 병합 시험으로 결정성 확인 |
| R3 | 깨진 `ink` 항목을 `[]`로 읽음 → 다시 쓰면 `null`(원본 사라짐) | 선택 키라 수식 보존을 우선. 단위 시험에 명시. 대안(기록 버림)은 사용자 내용 손실이 더 큼 |
| R4 | 데이터 크기: 획 400개·점 40,000개 한도 ≈ JSON 370 KB/수식(검토 A 측정 — 기록 하나 1,000,000 B 한도 안), 기록 메모리(`estimatedBytes`) | (검토 반영) 배경 변환은 한도 초과면 변환하지 않음, 말풍선 탭은 묻고 ink 없이. 합류·다시 열기가 점 수도 센다. 보통 수식은 수 KB |
| R5 | 펜 점 vs 점 기호 | (검토 반영) 스타일러스 점은 언제나 쓴다(수식 안이면 다시 열기 + 점). 메뉴는 손가락 탭·마우스 클릭 |
| R6 | 지우개 예외로 "도구 전환 = 변환" 규칙이 비대칭 | 요구 5a를 위해 필요. 말풍선이 지우개 중에도 남아 상태가 보인다 |
| R7 | 배경 변환이 사용자가 다른 일을 할 때 일어남(최대 10 s 뒤) | (검토 반영) 노트 기록이 계기 때와 다르면 포기(`stillWanted`) — 늦은 단계가 다음 작업 위에 쌓이거나 다시 실행을 지우지 않음. 새 묶음 계기에서 답이 늦으면 그 새 획 **하나** 뒤에만 들어갈 수 있다(그 경우 되돌리기 순서는 변환 → 획). 획이 바뀌었으면 포기(`liveStrokes`) |
| R8 | 동의가 필요한 서버 엔진: 말풍선만으로는 동의 못 받음 | 탭 → 기존 동의 카드가 있는 LaTeX 창(G-3 규칙 그대로) |
| R9 | `EditorTool` 값 추가 — exhaustive switch(호스트 `case`, 호버, 툴바) | 컴파일러가 모두 찾음. feature_editor 내부 enum이라 다른 패키지 영향 없음 |
| R10 | R14: 편집기·recog 공개 이름 충돌 | `EditorMathPen*` vs `RecognitionMathPen`/`recognitionMathPen` |
| R11 | 다시 열기+새 획 한 명령은 `commitInkEdit` 시그니처 변경(내부) | 선택 인자, 기존 호출 불변. 실패 시 획만 다시 커밋(필기 손실 없음) |
| R12 | 검색: 변환된 손글씨는 `HandwritingText` 입력에서 빠짐(수식 latex는 색인 대상 아님) | 이번 범위 밖, 기록만 |
| R13 | (검토 A-8) 두 기기가 같은 수식을 동시에 다시 열면 각자 새 id로 손글씨를 더해 동기화 뒤 손글씨가 두 벌. 다시 열기와 원격 '고치기'가 겹치면 수식은 지워지고(`deletedAt`은 따로 병합) LaTeX 고침은 사라진다 | 기존 '수식으로 바꾸기'와 같은 모양 — 잃는 획은 없음(남는 쪽은 손글씨). 기록만 |
| R14 | (검토 B-L6) 글꼴 크기는 손글씨 높이만으로 정한다 — 조판 폭이 손글씨 폭과 많이 다르면 옆 손글씨와 겹칠 수 있다 | 시험 글꼴(KaTeX 대체)로는 x^{2}가 손글씨 폭의 약 2배였지만 실제 글꼴 측정 전에는 폭 제한을 넣지 않는다. 실기기 확인 항목 |

## 16. 열린 질문 (기본 진행)

1. 수식 펜 스타일을 펜(볼펜) 스타일과 공유할지 — 기본: 따로(`ToolOptions.mathPenStyle`).
2. 변환 시 frame 세로 맞춤 — 기본: 잉크 세로 가운데(왼쪽 맞춤은 요구대로).
3. `recog.editMath` 라벨을 '고치기'로 바꿀지 — 기본: 선택 메뉴는 '수식 편집' 유지(4.4.4 문구 시험), 수식 펜 메뉴만 '고치기'.
