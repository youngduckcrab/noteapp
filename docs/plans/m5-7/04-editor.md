# 04 · EDITOR — 에디터 화면 (2차 라운드 M5·M6·M7)

> 상태: **승인 · 계약 v2.3** (동시 개발 착수 2026-11-06 — C22-09: 5.5 '가정' 확인, v2.2·v2.3이 바꾼 문장의 인용을 맞춤, 00-review '최종 승인'의 EDITOR-F1~F4 처리 — 13.5) · 최종 승인 2026-11-05 · 통합 계약 v2.2 — [00-review.md '최종 승인'](00-review.md#최종-승인), 이 영역의 개발 중 반영 항목은 그 절의 '영역별 개발 중 반영' 표 · 승인한 판본: 수정 3회차 + 총괄 직접 수정(13.4). 이 계획서와 계약이 다르면 계약이 우선이다. 이전 상태: **수정 3회차** (통합 계약 **v2.1** 기준 — 7.9 마지막 행 C21-35, 2026-11-05) — 총괄 검토에서 나온 새 모순 2건(5.1.2 '자동 도형 보정 확정' 매핑 행을 덮는 시험이 P-B E2-15뿐이라 10 #4가 P-B에 묶임, INFRA V5 자동 도형 단계가 EDITOR 자신의 P-B E2-15에도 묶여 10 #5·E2-23이 P-B에 묶임)을 반영했다(13.3). 수정 2회차는 총괄 승인 검토에서 나온 새 모순 2건(텍스트 세션 중 1차 `EditorCanvasFocus`가 편집기 포커스를 빼앗음, E2-21 자동 도형 단계가 P-B에 묶임)을 반영했다(13.2). 수정 1회차는 총괄 검토 [00-review.md](00-review.md) 3.4 EDITOR-M1~M14와 권장 S-1·S-11·S-12를 반영했다(13.1). 초안은 v2.0 기준이었다
>
> 작성 2026-11-05 · 영역 ID **EDITOR** · 소유 경로 `packages/feature_editor/` · 기준: [00-overview.md 7장 '통합 계약 v2.1'](00-overview.md) — **이 문서와 7장이 다르면 7장이 우선**한다. 7장이 덮어쓰지 않은 곳은 1차 계약 v1.5(1차 통합 반영 — 시그니처는 v1.4와 같음, 1차 [00-overview.md](../00-overview.md) 7장)가 그대로 유효하다.
> 이어받는 문서: 1차 EDITOR 계획서(승인본 v0.3, `/home/user/wt/editor/docs/plans/04-editor.md`, 이하 **'1차 계획서'**) · 바탕 코드: (v2.1, CD2-01) **1차 통합 HEAD** `/home/user/noteapp`(브랜치 `claude/note-app-planning-bk29xb`, 통합 계약 v1.5 커밋 `18c5ae5` 이후 — (v2.2, C22-08) 2차 바탕은 1차 통합 HEAD `b6c9d0a`, `18c5ae5` 인용은 이 HEAD로 읽는다. EDITOR 소유 경로의 코드 차이는 없다)의 `packages/feature_editor` — `lib/`는 1차 작업 트리 `/home/user/wt/editor`(`93dc827`)와 같고(`diff -rq` 차이 0, 16,911줄), `test/`는 통합에서 3파일이 바뀌고 `test/web/editor_browser_smoke_test.dart`가 더해져 시험 파일 61개다 [확인]. 아래 줄 번호 인용은 같은 `lib/` 기준이라 그대로 맞고, 기반 단계 시작 때 한 번 더 확인한다 · 조사: [01-hooks](research/01-hooks.md) · [02-audio-stylus](research/02-audio-stylus.md) · [03-recognition](research/03-recognition.md) · [04-native](research/04-native.md) · 판정: [judgement.md](drafts/judgement.md) · 함께 본 영역 계획서: [01-infra.md](01-infra.md)(6.12 `pencil_bridge` 어댑터, 13절 자리 표), [02-core.md](02-core.md)(5.3 EDITOR, 12.1 CP-1·CP-2)

이 문서를 읽는 법

- 절 번호: `7.x`는 2차 계약(00-overview 7장), **'1차 7.x'**는 1차 계약, **'1차 계획서 6.6.5'**는 이어받는 1차 EDITOR 계획서의 절이다.
- 코드의 `core.` = `package:note_core/note_core.dart`, `ink.` = `package:ink_engine/ink_engine.dart`(1차와 같이 접두사 import).
- `// 계약 v2.1 7.2.x 원문`이 붙은 코드 블록은 계약을 **글자 그대로** 옮긴 것이다(1차 계획서와 같은 규칙 — 블록의 일부만 옮길 때는 이어진 앞부분·뒷부분만 자르고 그 사실을 표시 줄에 적는다). 그 밖의 Dart 블록은 EDITOR 내부 설계이고, 본문 없는 멤버(`;`로 끝남)는 시그니처만 적은 것이다.
- **[확인]**은 이 컨테이너에서 코드를 읽거나 명령을 실행해 확인한 사실이다(경로·줄 번호 — 1차 작업 트리 기준). 계약과 다르게 해야 한다고 본 점은 계약대로 쓰고 **12.1 '계약 변경 제안'**에만 적는다.
- 등급 P-A/P-B/P-C는 00-overview 3.4다. 작업 ID는 1차 E-xx와 섞이지 않게 **E2-xx**로 쓴다.

계획 중 확인한 것 (스크래치 `/tmp/claude-0/plan57-scratch/editor57/probe`, Flutter 3.47.9 / Dart 3.13.7)

| # | 확인 내용 | 결과 |
|---|---|---|
| V1 | `EditableText`를 `Transform.rotate(π/12)` + `Transform.scale(1.5)` 안에 두고(페이지 회전·확대 상태의 텍스트 상자 편집을 흉내), `testTextInput.updateEditingValue`로 IME 조합 값(`'안ㄴ'` → `'안녕'`, `composing` 범위 있음)을 넣은 뒤 바깥을 탭 | `TapRegion.onTapOutside`가 정확히 1회 불리고 그 순간 `controller.text == '안녕'`(조합 중 글자 포함), 포커스 해제. VM 위젯 시험 통과 [확인]. (수정 1회차) 이 결과는 '조합 중 글자도 내용에 들어감'·'변환 안의 편집기'의 근거로만 쓴다 — `onTapOutside`는 포인터 **down**마다 불려 스크롤·핀치에도 세션이 끝나므로(검토 M-2) 세션 끝 판정은 라우터로 옮겼다(6.11.5, V6) |
| V2 | 웹 대체안 B(6.11.6)의 뼈대: `HtmlElementView.fromTagName(tagName: 'textarea', onElementCreated: …)` + `dart:js_interop`·`dart:js_interop_unsafe`로 `value` 읽기·쓰기·`input` 이벤트, `*_browser.dart`를 `if (dart.library.js_interop)` 조건부 export | `flutter analyze` 0건 [확인]. **`package:web` 없이** SDK 라이브러리만으로 되므로 `pubspec.yaml` 변화가 없다 |
| V3 | `material_ui` 1.10.0 `Icons`(pub 캐시 `lib/src/icons.dart`)에 이번에 쓸 아이콘 — `text_fields`·`interests`·`category`·`add`·`add_photo_alternate`·`photo_library`·`photo_camera`·`folder_open`·`content_paste`·`content_cut`·`content_copy`·`rotate_right`·`palette`·`format_bold`·`format_align_left/center/right`·`format_color_text`·`horizontal_rule`·`arrow_right_alt`·`rectangle_outlined`·`circle_outlined`·`change_history`·`pentagon`·`star_outline`·`polyline`·`draw`·`gesture`·`line_style`·`flare`·`visibility_off`·`mic`·`mic_none`·`image` | 모두 있음 [확인] |
| V4 | 1차 EDITOR 코드의 확장 자리 | `enum EditorTool { pen, eraser, lasso } // M5: shape, text, image, math`(`tools/tool_state.dart` 8), `InputRouter._onPenDown`은 버튼 비트를 보지 않고 down 즉시 상호작용 시작(`input/input_router.dart` 200–225), 손가락 2·3 탭은 `GestureSettings`의 bool로 거름(`_endTouch` 498–517), `EditorSelection.strokeIds`(`tools/selection.dart`), 앱 클립보드는 획만(`tools/stroke_clipboard.dart`), 선택 메뉴 `[복사][삭제][선택 해제]`(`ui/overlays/selection_menu.dart`), `PenInteraction.start`는 `beginStroke`에 `meta`를 넘기지 않음(`tools/pen_interaction.dart` 58–62), `PageMount._onChange`는 `InkPageContent.fromCore(page:, strokes:, revision:)`만(`document/page_mount.dart` 86–92), `_ToolStateJson.selectionFromJson`은 모르는 도구 이름을 이미 `pen`으로 읽되 '잘못된 필드'로 보고함(`tools/tool_controller.dart` 388–420), `StylusExtrasSource`를 구독하는 곳 없음 [확인] |
| V6 | (수정 1회차, `test/text_region_probe_test.dart`) 편집기를 `material_ui` `TextField`(`InputDecoration.collapsed`, `groupId` 기본값 `EditableText`, `onTapOutside` 기록)로 회전·확대 변환 안에 두고, 그 **아래 형제**인 '페이지 뷰포트'(`Listener`)를 `TextFieldTapRegion(enabled: 편집 중)`으로 감쌈 | ① collapsed 장식의 `contentPadding == EdgeInsets.zero`·`isCollapsed` ② 뷰포트의 한 손가락 탭·두 손가락 끌기·스타일러스 down → `onTapOutside` 0회(뷰포트 `Listener`는 down 4개를 모두 받음, 포커스 유지), 툴바 자리 탭 → 1회 ③ `enabled: false`면 같은 스타일러스 down에 1회(웹·스타일러스 기본 동작이 포커스를 푸는 경로) ④ iOS 변형: 두 번 탭 → 낱말 선택 + `AdaptiveTextSelectionToolbar`(단추 6), 그 메뉴를 눌러도 `onTapOutside` 0회. 4개 모두 통과 [확인]. Flutter 선택 손잡이·메뉴는 `TextFieldTapRegion`(기본 묶음 `EditableText`)으로 감싸여 있다(`/opt/flutter/packages/flutter/lib/src/widgets/text_selection.dart` 1805·1836·1980 [확인]) — 6.11.3·6.11.5 설계 근거 |
| V5 | 1차 INK 코드 | `SelectionGeometry.rotate(bounds:, radians:)`·`snapAngle(step π/12, threshold 3°)`·`transformedCorners`, `InkSelection.previewTransform`·`recolor`·`duplicate`·`delete`, `InkEdit`의 공개 `const` 생성자(시험에서 `InkEdit(kind: addShape, …)`를 직접 만들 수 있음), `InkStrokeMeta(recordingId:, recordingOffsetMs:)`(`stroke/stroke_meta.dart`) [확인] |
| V7 | (수정 2회차, `test/canvas_focus_session_probe_test.dart`) 1차 `EditorCanvasFocus`(`input/editor_shortcuts.dart` 222–230 — 캔버스 포인터 down마다 마이크로태스크로 캔버스 `FocusNode.requestFocus()`)를 그대로 옮긴 `Focus` + `Listener`로 캔버스를 감싸고, 그 안을 `TextFieldTapRegion(enabled: 세션)`으로, 편집기 `TextField`는 위쪽 형제로 둠(1차 `page_viewport.dart` 117과 6.11.3 배치). 세션 여부는 `ValueNotifier<bool>`(= `editorTextEditProvider != null`), 세션 끝은 라우터처럼 비동기(16 ms 뒤 null) | ① 대조(1차 그대로): 두 손가락 끌기 → `onTapOutside` 0회인데 편집기 포커스 잃음 1회·`hasFocus == false`(총괄 시제품 `approve-editor/probe/test/canvas_focus_probe_test.dart`와 같은 결과) ② 고친 판(세션 중 down에서 요청하지 않음): 두 손가락 끌기·핀치·라우터가 세션을 끝내지 않은 스타일러스 down 뒤 포커스 잃음 0회·`hasFocus` 유지·`onTapOutside` 0회, 캔버스 `Listener`는 down 5개를 모두 받음 ③ 펜 접촉으로 세션이 비동기로 끝남 → 캔버스가 주 포커스 ④ 되찾기를 끈 판에서도 포커스된 편집기가 트리에서 빠지면 Flutter 포커스 범위 이력으로 캔버스가 주 포커스가 됨 — 되찾기는 이 이력에 기대지 않으려는 멱등 보강 ⑤ 다른 입력란 `requestFocus()` → 세션 끝, 캔버스가 빼앗지 않음(그 입력란이 주 포커스) ⑥ 편집기 `unfocus()`(키보드 '내림' 흉내) → 세션 끝 뒤 캔버스가 주 포커스. 6개 모두 통과 [확인]. V6은 `EditorCanvasFocus` 없는 맨 `Listener`로만 확인해 이 경로를 보지 못했다 — 6.11.3 '캔버스 포커스 양보'의 근거 |

---

## 목차

1. [목적과 범위](#1-목적과-범위)
2. [PLAN.md 요구사항 대응표](#2-planmd-요구사항-대응표)
3. [소유 경로와 패키지 구조](#3-소유-경로와-패키지-구조)
4. [공개 API](#4-공개-api)
5. [사용하는 다른 영역의 계약](#5-사용하는-다른-영역의-계약)
6. [설계 상세](#6-설계-상세)
7. [외부 패키지](#7-외부-패키지)
8. [작업 분해](#8-작업-분해)
9. [테스트 계획](#9-테스트-계획)
10. [완료 기준](#10-완료-기준)
11. [리스크와 대응](#11-리스크와-대응)
12. [총괄에게 묻는 질문 · 계약 변경 제안](#12-총괄에게-묻는-질문--계약-변경-제안)
13. [검토 반영 내역](#13-검토-반영-내역)
- [부록 A. 확장 지점 · 자리 사용표 (개요 6장 13절)](#부록-a-확장-지점--자리-사용표-개요-6장-13절)
- [부록 B. 네이티브 · 권한 요구표 (개요 6장 14절)](#부록-b-네이티브--권한-요구표-개요-6장-14절)
- [부록 C. 통합 시험용 위젯 키 (INFRA V5·V6)](#부록-c-통합-시험용-위젯-키-infra-v5v6)

---

## 1. 목적과 범위

### 1.1 목적

1차에서 만든 에디터(필기·입력 분배·카메라·올가미·펜 설정·페이지 패널) 위에 **M5 편집 강화의 모든 상호작용**, **M6의 '필기 ↔ 녹음' 연동**, **M5·M6·M7을 다른 영역이 채울 자리**를 더한다. 렌더·적중 판정·선택 기하는 INK(7.2.9), 저장 모델·명령은 CORE(7.2.2·7.2.3), 녹음기·재생기·이미지 선택은 `media_io`, 인식 엔진과 변환 창은 `ink_recognition`, Pencil 플러그인은 `pencil_bridge`가 한다. EDITOR는 이들을 **사용자의 한 동작 = 명령 한 번 = 되돌리기 1단계**로 엮는 손이다(1차 계약 E-1, 1차 계획서 5.1.3).

1차 7.8에서 미룬 것 중 M5와 맞닿은 세 가지(올가미 회전·색 변경 UI, 제스처 동작 변경, 이미지 페이지)를 이번에 한다. 무거운 UI 두 개(녹음 패널, 인식 변환 창·수식 입력 패드)는 자리만 열고 각 서비스 패키지가 채운다(00-overview 2.4).

### 1.2 이번 범위 (00-overview 3.1 표의 EDITOR 몫, 3.4 등급)

| # | 기능 | EDITOR가 하는 일 | 등급 | 작업 | 웹 | 실기기 첫 확인 |
|---|---|---|---|---|---|---|
| M5-1 | 올가미 고급 | 획 + 객체 **혼합 선택**, **회전 핸들(15° 맞춤)**, 90° 돌리기, **색 변경**, **잘라내기**, 복제, 붙여넣기(획 + 객체), 앱 클립보드 v2, 선택 우선 규칙 (a′)(6.6.2 — 그리기 도구에서는 핸들만 우선), 단일 객체 핸들(회전된 객체 모서리 크기 조절 `ObjectResize.cornerScale`) | P-A | E2-06·E2-07a~c·E2-08 | ✔ | 웹 B-5 |
| M5-2 | 텍스트 상자 | 텍스트 도구, 편집 오버레이(`material_ui` `TextField` collapsed — 선택 손잡이·붙여넣기 메뉴, 글자 모양 INK `textStyleOf`·`strutStyleOf`), 세션 끝은 라우터가 판정(스크롤·핀치·손바닥에는 유지), 상자 단위 서식(크기·색·굵게·정렬·배경), 폭 핸들, 이동·크기·회전(선택 공통), **편집 세션 1회 = 명령 1회**(E-6), 한글 IME, **웹 대체안 두 가지**(A 시트 입력란 — P-A, B `<textarea>` 겹치기 — P-C) | P-A (B안 P-C) | E2-01·E2-10·E2-11 | ✔ | 웹 B-2 |
| M5-3 | 이미지 삽입 | 삽입 메뉴 → `editorImageImporterProvider` → 배치 → `AddObjects([ImageObject])`, 이동·크기(비율 고정)·회전, 컨텍스트 메뉴 '이미지 붙여넣기'(소스에 `clipboard`가 있을 때) | P-A | E2-12 | ✔ | 웹 B-3, APK |
| M5-4 | 이미지 페이지 | 페이지 추가 시트 '이미지' 줄 → `InsertPages([PageDraft(background: ImageBackground)])` | P-A | E2-12 | ✔ | 웹 B-3 |
| M5-5 | 도형 도구 | 7종 끌어 그리기(직선·화살표·사각형·원/타원·삼각형·다각형·별), 각도·정비율 맞춤, 테두리 색·굵기·선 스타일·채우기·화살촉, 단일 도형 핸들(크기·회전), 꼭짓점 편집(별은 P-C) | P-A (별 꼭짓점 P-C) | E2-08·E2-09 | ✔ | 웹 B-4 |
| M5-6 | 자동 도형 보정 | 설정(켬/끔), `shapeAssistFor` 순수 함수 → `beginStroke(shapeAssist: holdToSnap)`, `InkEdit(addShape)` 커밋(판정·미리보기는 INK·recog — 커밋은 1차 `commitInkEdit` 경로 그대로이고, 그 1단계 단언은 (수정 3회차) P-A E2-09 `widget/shape_tool_test.dart`), `FEATURE_RECOGNITION=false`(`NoShapeFitter`)면 토글 숨김(CD2-16), 개발자 토글 켬일 때만 도형 표본 링 버퍼(6.20) | P-B | E2-15·(통합) E2-21b | ✔ | 웹 B-4 |
| M5-7 | 제스처 사용자 지정 | `GestureSettings` v2(동작 매핑) 읽기·쓰기·적용, 동작 실행기, 설정 화면 편집 UI | P-A | R2-B5·E2-04b·E2-05 | ✔ | 웹 B-7 |
| M5-8 | S펜 측면 버튼 · 지우개 끝 | **E-4 접촉 판정**(웹 접촉 비트), 펜 버튼·`invertedStylus` 제스처 → '누른 채 쓰는 동안' 지우개(또는 올가미) | P-A | E2-04a | △ 안드로이드 Chrome | APK A-2 |
| M5-9 | Apple Pencil 이벤트 소비 | `stylusExtrasProvider` 구독: 더블탭·스퀴즈 → 동작(시스템 설정 따르기), 호버 자세 → 커서·팜 리젝션, 배럴 롤 → 캘리그래피 펜촉 각, `capabilities`(앱 시작 때 한 번 — v2.1)로 설정 항목 숨김, 스퀴즈·롤 줄은 그 기기에서 첫 이벤트를 받은 뒤 보임(CD2-24) | P-B | E2-18 | ✘(항목 숨김) | TF 뒤 C-1 |
| M5-10 | 붓펜·캘리그래피·점선 | 펜 선택기에 노출, 펜별 고급 설정(펜촉 각·비율·롤 따르기, 점선 간격) | P-A | E2-14 | ✔ | 웹 B-6 |
| M5-11 | 레이저 포인터 | 펜 선택기 노출, 사라짐 시간 설정, 명령 없음(E-3·K-9) | P-A | E2-14 | ✔ | 웹 B-6 |
| M5-12 | 암기 테이프 | 테이프 펜, 탭으로 드러내기·가리기(손가락 탭·펜 점 탭 — 4 px·200 ms), '테이프 모두 보이기/가리기'(`updateContent` 뒤마다 다시 적용) | P-A | E2-14 | ✔ | 웹 B-6 |
| M6-1·M6-3 | 녹음·재생 바 | **자리만**: 툴바 마이크 버튼 + 하단 패널 자리(`recordingPanel`), 녹음 중 표시. 패널 UI는 `media_io.RecordingPanel` | P-A | E2-16 | ✔ | 웹 B-8 |
| M6-4 | 획별 녹음 시점 · 재생 강조 · 탭 재생 | 펜 다운 `InkStrokeMeta`(R-1·E-5), 재생 강조 `Ticker` → `setPlaybackFocus`, 필기 탭 → `seekMs(offset − preRoll)` + 재생 — (v2.1 R-5) **탭 재생 상태**에서만(녹음기 `idle`, 손가락: 패널 열림 또는 재생·일시정지 / 펜 점: 재생·일시정지만, `end()` 전 판정·`cancel()`), 강조 초점은 열린 뒤 재생·탐색이 있었을 때만, `tapToSeek` 플래그 소유 | P-A | E2-16·E2-17 | ✔ | 웹 B-8, APK A-5 |
| M6-5 | 녹음 끊김 복구 | 하는 일 없음 — 복구된 녹음은 원래 `recordingId`를 지키므로(V16) 녹음 중 쓴 획의 강조·탭 재생이 그대로 동작함을 시험으로 확인 | P-A | E2-17 | ✔ | 웹 B-14 |
| M7-1·M7-6 | 손글씨 → 텍스트, 수식 | **자리만**: `selectionMenuItems`(문맥 `EditorSelectionContext`), `insertMenuItems`(문맥 `EditorInsertContext`) | P-A(자리) | E2-07c·E2-12 | ✔ | APK A-4 |
| M7-2~4 | 검색 결과 위치로 열기 | `EditorScreen.initialFocusRectPt` → 그 사각형이 보이게 + 깜빡임 | P-A | E2-19 | ✔ | 웹 B-10 |
| M7-5 | 수식 객체 | 이동·크기·회전·색 변경은 선택 공통(E2-06·E2-07b). 입력·편집 UI는 recog | P-A | E2-06·E2-07b | ✔ | 웹 B-11 |
| 공통 | 도구 선택 저장값 폴백 | 모르는 도구 이름 → `pen`(7.4.10), 오류 보고 안 함 | P-A | E2-03 | ✔ | — |
| 공통 | 지우개 v2 | 닿은 도형 통째로 지우기(`EraserSpec.eraseShapes`, U22), 페이지 전체 지우기에 '객체도 지우기' | P-A | E2-19 | ✔ | 웹 |

### 1.3 이후 범위 (이번에는 하지 않거나 자리만 둔다)

- 재생 중 '따라가기'(지금 쓰이던 획이 있는 페이지로 자동 이동) — 노트 전체 획의 녹음 시점 색인이 필요하다(열린 페이지만 알 수 있음). 이번에는 열린 페이지만 강조한다.
- **캔버스 수준** 시스템 클립보드 연동(앱 밖 텍스트를 붙여넣어 새 텍스트 상자 만들기, 선택 획을 이미지로 복사) — P-C로도 넣지 않는다. **텍스트 상자 편집 중의 글자 붙여넣기·복사는 된다**(편집기 `TextField`의 붙여넣기 메뉴·⌘V — 시스템 클립보드, 6.11.3·6.7.6). 이미지 붙여넣기는 `media_io`가 `ImageImportSource.clipboard`로 준다(웹 `navigator.clipboard.read`가 있을 때).
- 그리드 스냅·자(F-11 P1), 객체 z 순서 바꾸기, 이미지 자르기·투명도, 텍스트 글자 단위 서식·목록·표(00-overview 3.6).
- 별 꼭짓점 편집(P-C — 시간이 남으면 E2-08 안에서), 발표 모드(외부 화면).
- 다른 노트의 페이지 복사(F-13, U23) — 페이지 추가 시트의 '다른 노트' 줄은 이번에도 없다.
- 녹음 시계 보정(R-3 실측 뒤), 녹음 텍스트 변환(P2).

### 1.4 제외 (다른 영역 책임 — EDITOR는 쓰기만 한다)

| 무엇 | 영역 | EDITOR 쪽 접점 |
|---|---|---|
| 객체·새 펜의 렌더, 적중(`hitTestObject`·`hitTestTape`·`hitTestRecorded`), 선택 기하, 미리보기 객체 그리기, 재생 강조·테이프·레이저 그리기, 도형 보정 발동·미리보기, `InkTextLayout`·`InkFonts` | INK | 5.2 |
| 페이지 객체 모델·JSON·명령 해석·되돌리기, 녹음 저장소, 오디오 포트 정의·`Unsupported*` 기본값, 가짜 저장소·가짜 녹음기 | CORE | 5.1 |
| 녹음기·재생기·녹음 패널 UI·이미지 선택·정규화(`importImageForNote`) | PDF(`media_io`) | 자리: `recordingPanel`, `editorImageImporterProvider` |
| 도형 판정 알고리즘, 손글씨·수식 인식, 변환 창·수식 입력 패드·LaTeX 편집 창 | LIBRARY(`ink_recognition`) | 자리: `selectionMenuItems`, `insertMenuItems` |
| Pencil 플러그인(Swift), `PencilStylusExtrasSource` 어댑터, 자리 override 연결, 라우팅 `?page=&focus=`, 설정 화면 틀 | INFRA | 4.2 자리 전부, `stylusExtrasProvider` |

### 1.5 1차 대비 바뀌는 EDITOR 공개 표면 (7.0.1 중 EDITOR 행)

| # | 변경 | 분류 | EDITOR가 맞출 곳 |
|---|---|---|---|
| C2-22 | `EditorExtensions`에 `selectionMenuItems`·`insertMenuItems`·`recordingPanel`, 새 값 타입 6종, `editorImageImporterProvider`, `EditorScreen.initialFocusRectPt` | 추가 | R2-B5에서 타입·provider·생성자 인자, 동작은 E2-07c·E2-12·E2-16·E2-19 |
| C2-23 | `GestureSettings.actions` + `EditorGesture`·`EditorAction`, 1차 bool 3개 유지(JSON 읽기·쓰기 호환) | 추가 | R2-B5에서 모델·JSON, 적용은 E2-04b·E2-05 |
| C2-24 | `StylusExtrasSource.capabilities` | 깨짐(구현은 EDITOR `NoStylusExtras` + INFRA 새 어댑터뿐) | R2-B5 |
| C2-25 | `StylusHoverPose`, `StylusDoubleTap`·`StylusSqueeze` 선택 인자, `StylusPreferredAction`·`StylusSqueezePhase`·`StylusCapabilities`, (v2.1, CP-E6) `StylusExtraEvent.timestamp`(선택) | 깨짐(형식상, 구독자 없음) + 추가 | R2-B5 |

이 밖에 **1차 계약 7.2.17이 정의를 EDITOR 4.8에 맡긴 타입**(`EditorSettings`·`GestureSettings`)에 선택 인자를 더한다(4.3.3 — 기존 호출은 그대로 컴파일). 계약 문구가 바뀌지 않으므로 7.0.1 표에는 없다(12.2 Q12 — 총괄 답: 올리지 않아도 된다. 다만 `PlaybackHighlightStyle`은 빼고 INK `InkPlaybackStyle`을 그대로 쓴다 — 수정 1회차에 반영, `WebTextInputMode`도 EDITOR 내부 device 키로 옮겨 새 공개 이름은 14개다 — 4.1·4.3.3).

---

## 2. PLAN.md 요구사항 대응표

EDITOR가 직접 구현하거나 자리를 여는 항목만 적는다. '작업'은 8.2 ID, '시험'은 9.2 파일이다.

### 2.1 기능 명세 (PLAN 4장)

| PLAN | 요구 | EDITOR 설계 | 작업 | 대표 시험 |
|---|---|---|---|---|
| F-03 붓펜·캘리그래피·점선 (P1) | 필압 민감·끝 가늘어짐, 펜촉 각도, 선 스타일 | 펜 선택기 두 줄(기본 5·추가 5), 펜별 고급 설정(`InkStyleExtras` 키 — 6.14), 롤 → 펜촉 각(6.5.4) | E2-14·E2-18 | `widget/pen_types_v2_test.dart`, `widget/pen_extras_controls_test.dart`, `unit/barrel_roll_test.dart` |
| F-03 레이저·암기 테이프 (P1) | 잠시 뒤 사라짐 / 가렸다가 탭하면 보임 | 레이저는 명령 없음(6.14.3), 테이프 탭 가로채기(6.3.5), 모두 보이기/가리기(6.14.4) | E2-14 | `widget/laser_test.dart`, `widget/tape_test.dart` |
| F-03 호버 미리보기 | 닿기 전 위치·굵기 | 웹·안드로이드: 1차 hover 커서. iPad 네이티브: `StylusHoverPose` → 커서(높이로 크기·투명도 — 6.5.3) | E2-18 | `widget/stylus_extras_test.dart` |
| F-08 1회 = 1단계 | 모든 새 동작 | 5.1.2 명령 매핑 표(도형·텍스트·이미지·색·잘라내기·붙여넣기·복제·핸들·꼭짓점) | 전부 | 각 위젯 시험의 `undoDepth` 단언 |
| F-09 펜 버튼·더블탭으로 지우개 | 지우개 전환 | 펜 버튼 = 누른 채 지우개(`eraserWhileHeld`), 더블탭 = 시스템 설정 따르기(`switchEraser` → `toggleEraser`) | E2-04a·E2-18 | `unit/input_router_test.dart` R34~R46, `unit/follow_system_test.dart` |
| F-09 (2차) 도형 지우기 | — | 지우개가 닿은 도형은 통째로(U22 — 획 지우개·부분 지우개 모두, 부분 지우개는 INK `CompositeCommand` 한 번 — CP-INK-2), 텍스트·이미지·수식은 지우지 않음. 지우개 패널 '도형도 지우기' | E2-19 | `widget/erase_v2_test.dart` |
| F-10 손글씨 → 텍스트 | 올가미 선택 → 변환 | 선택 메뉴 자리 + `EditorSelectionContext`(획·객체·`execute`) — 변환 창은 recog | E2-07c | `widget/selection_extensions_test.dart` |
| F-11 도형 도구 | 7종, 테두리·채우기·선 스타일, 크기·회전·꼭짓점 | 6.9 도형 도구, 6.6.5 핸들·꼭짓점 | E2-08·E2-09 | `widget/shape_tool_test.dart`, `widget/object_handles_test.dart`, `widget/vertex_edit_test.dart` |
| F-11 자동 도형 보정 | 펜 멈추면 반듯한 도형 | 6.10 — 설정 + `shapeAssistFor` → `ShapeAssist.holdToSnap` + `addShape` 커밋 | E2-15·(통합) E2-21b, 커밋 경로 시험은 P-A E2-09 | `unit/shape_assist_for_test.dart`, `widget/shape_assist_test.dart`, (수정 3회차, P-A — 커밋 경로 `AddObjects` 1단계) `widget/shape_tool_test.dart`, (P-B 통합) `integration/shape_assist_smoke_test.dart` |
| F-12 제스처 매핑 | 각 항목 켜기/끄기·동작 변경 | 6.4 — `actionFor` 디스패처, 설정 UI | E2-04b·E2-05 | `unit/gesture_settings_test.dart`, `widget/gesture_settings_section_test.dart` |
| F-12 S펜 측면 버튼 | 지우개 전환 | 6.3.2 E-4 접촉 판정 + 제스처 | E2-04a | `unit/stylus_contact_test.dart`, `unit/input_router_test.dart` |
| F-12 Pencil 더블탭·스퀴즈 | 지우개 전환 / 도구 팔레트 | 6.5 — `followSystem` 표, 스퀴즈는 `ended`에서 `hoverPosition`에 팔레트 | E2-18 | `widget/stylus_extras_test.dart` |
| F-13 이미지 페이지 | 페이지 종류 '이미지' | 6.12.3 — 페이지 추가 시트 '이미지' 줄 | E2-12 | `widget/add_page_sheet_test.dart` v2 |
| F-14 수식 객체 | 이동·크기·색, 다시 편집, LaTeX 복사 | 이동·크기·회전·색은 선택 공통, '다시 편집'·'LaTeX 복사'·수식 입력 패드는 recog 자리 항목 | E2-06·E2-07b·E2-12 | `widget/lasso_mixed_test.dart`, `widget/insert_menu_test.dart` |
| F-16 녹음 버튼 · 재생 바 | 녹음·일시정지·정지, 재생 바 | 툴바 마이크 버튼 + 하단 패널 자리(6.15.4) — 패널은 media | E2-16 | `widget/recording_panel_slot_test.dart` |
| F-16 필기 연동 | 획마다 녹음 시점, 재생 시 강조, 탭 → 그 시점부터 | 6.15.1~6.15.3(탭 재생 상태 R-5 v2.1) | E2-16·E2-17 | `unit/recording_link_test.dart`, `unit/playback_highlight_logic_test.dart`, `widget/playback_highlight_test.dart`, `widget/tap_to_seek_test.dart` |

### 2.2 추가 기능 (PLAN 5장) · 아키텍처 (7장) · 화면 (8장) · 로드맵 (10장)

| PLAN | 요구 | EDITOR 설계 | 작업 |
|---|---|---|---|
| 5.1 올가미 (M5 고급) | 회전·색 변경·복사, 변환의 전제 | 6.6~6.8 | E2-06·E2-07a·E2-07b |
| 5.1 텍스트 상자 | 키보드 입력 | 6.11 | E2-01·E2-10 |
| 5.1 이미지 삽입 | 사진·카메라·스크린샷 붙여넣기 | 6.12 (스크린샷 붙여넣기 = 웹 클립보드 소스) | E2-12 |
| 5.2 레이저 포인터·암기 테이프 | P1 | 6.14 | E2-14 |
| 5.2 손글씨 검색 | 결과 열기 | 6.16 `initialFocusRectPt` | E2-19 |
| 5.2 키보드 단축키 | P1 | 6.7.6 ⌘X·⌘D, 도구 키 S(도형)·T(텍스트) | E2-07a·E2-13 |
| 5.4 필기 지연 | 20 ms | 펜 다운 경로에 더하는 일은 `offsetNowMs()` 한 번과 버튼 비트 검사뿐(6.22 수치) | E2-04a·E2-16 |
| 7.3 레이어 순서 | 배경 → 형광펜 → 필기·도형·텍스트 → 선택 | INK L-1을 그대로 쓴다. EDITOR 오버레이(선택 프레임·핸들·텍스트 편집기)는 그 위 | — |
| 7.5 되돌리기 | 사용자 동작 1회 = 1단계 | 5.1.2 | 전부 |
| 7.6 기능 스위치 | 유료 기능 끄기 | 자리가 비면 해당 UI를 숨김(E-7) — 녹음 버튼·인식 메뉴·이미지 삽입 | E2-07c·E2-12·E2-16 |
| 8 상단 툴바 | 펜·지우개·올가미·도형·텍스트·이미지·수식·녹음·되돌리기 | 6.13 툴바 v2(이미지·수식은 '+ 삽입' 메뉴) | E2-13 |
| 8 녹음 재생 바 | 에디터 안 | 하단 패널 자리(화면 높이 40% 이하 — 7.4.10) | E2-16 |
| 8 설정 > 입력 > 제스처 매핑 | 편집 | 6.4.4 | E2-05 |
| 10 M5 | 다섯 항목 | 1.2 표 | — |
| 10 M6 | 녹음 연동 | 1.2 표 | — |
| 10 M7 | 인식 | 자리(1.2 표) | — |

---

## 3. 소유 경로와 패키지 구조

EDITOR는 `packages/feature_editor/` 아래만 고친다. 다른 경로가 필요하면 진행 기록에 '변경 요청'으로 남긴다. 공개 진입점은 1차와 같이 `lib/feature_editor.dart` **하나**다(`testing.dart` 없음 — 1차 계약 7.1). 아래 트리는 1차 트리(1차 계획서 3절)에 더하는 것만 적는다: **(새)** 새 파일, **(확장)** 1차 파일을 넓힘, **(이름 바꿈)** 내부 파일 이름 변경.

```text
packages/feature_editor/
├─ pubspec.yaml                          # 변화 없음 (7절)
├─ dart_test.yaml                        # 변화 없음 — golden {}, integration {skip}
├─ lib/
│  ├─ feature_editor.dart                # (확장) export 추가 — 4.1
│  └─ src/
│     ├─ editor_screen.dart              # (확장) initialFocusRectPt, editorInitialFocusRectProvider override
│     ├─ di/
│     │  ├─ editor_extensions.dart       # (확장) selection/insert 메뉴 항목·문맥, 패널 자리 타입
│     │  ├─ editor_image_importer.dart   # (새) EditorImageImporter · editorImageImporterProvider
│     │  ├─ dev_overlay_section.dart     # 변화 없음
│     │  └─ stylus_extras.dart           # (확장) Stylus v2 타입, NoStylusExtras.capabilities
│     ├─ scope/editor_scope.dart         # (확장) 6.19 새 scoped provider
│     ├─ document/
│     │  ├─ page_mount.dart              # (확장) objects 전달, 새 마운트에 재생 강조·테이프 상태 적용
│     │  └─ mounted_pages.dart           # 변화 없음
│     ├─ input/
│     │  ├─ input_router.dart            # (확장) E-4 접촉 판정, 펜 버튼·지우개 끝 제스처, 동작 기반 탭·길게 누르기
│     │  ├─ stylus_contact.dart          # (새) StylusContactRule · 접촉/버튼 판정 순수 함수
│     │  ├─ input_targets.dart           # (확장) beginInteraction(gesture:), noteStylusPoseHover
│     │  ├─ input_sample.dart            # 변화 없음
│     │  ├─ input_thresholds.dart        # (확장) penTapMaxMovement 4 px · penTapMaxDuration 200 ms (6.3.7)
│     │  └─ editor_shortcuts.dart        # (확장) ⌘X·⌘D·S·T, 텍스트 편집 중 양보, EditorCanvasFocus 세션 중 포커스 양보·끝난 뒤 되찾기 (6.11.3)
│     ├─ actions/                        # (새)
│     │  ├─ editor_action_runner.dart    # EditorAction 실행기 (6.4.3)
│     │  └─ follow_system.dart           # StylusPreferredAction → EditorAction (6.5.2)
│     ├─ stylus/                         # (새)
│     │  ├─ stylus_extras_listener.dart  # StylusExtrasSource 구독 (6.5)
│     │  └─ barrel_roll.dart             # 최근 롤 값 → 펜촉 각 (6.5.4)
│     ├─ tools/
│     │  ├─ tool_state.dart              # (확장) EditorTool + shape·text, lastTool·lastPenType
│     │  ├─ tool_controller.dart         # (확장) 폴백(7.4.10), previousTool 맞바꿈, 도형·텍스트 도구
│     │  ├─ tool_options.dart            # (새) ToolOptions(도형·텍스트 기본값) · editorToolOptionsProvider
│     │  ├─ interaction_host.dart        # (확장) 선택 우선 규칙 (a′), 임시 도구, 탭 가로채기, 텍스트 세션 끝 판정, 새 도구 분기
│     │  ├─ pen_interaction.dart         # (확장) 녹음 메타, shapeAssist, 롤 각, 레이저, 탭 가로채기(end() 전 — cancel)
│     │  ├─ shape_assist_for.dart        # (새) shapeAssistFor(settings, penType, fitter) 순수 함수 (6.10)
│     │  ├─ shape_samples.dart           # (새) 도형 표본 링 버퍼 — 개발자 토글 켬일 때만 (6.20)
│     │  ├─ erase_interaction.dart       # (확장) eraseShapes
│     │  ├─ lasso_interaction.dart       # (확장) allIds, 탭 → 객체 선택
│     │  ├─ selection.dart               # (확장) elementIds(획 + 객체), origin(6.6.2), 재검증 elementById
│     │  ├─ selection_hit_test.dart      # (확장) 회전 핸들, 8방향, 회전된 프레임
│     │  ├─ selection_transform_interaction.dart  # (확장) 이동 시작 문턱, 회전, 탭 콜백
│     │  ├─ element_clipboard.dart       # (이름 바꿈 ← stroke_clipboard.dart) 획 + 객체
│     │  ├─ shape_interaction.dart       # (새) 도형 끌어 그리기 (6.9)
│     │  ├─ shape_drafts.dart            # (새) 끌기 → ShapeGeometry, 각도·정비율 맞춤
│     │  ├─ object_handles.dart          # (새) 단일 객체 핸들 배치·적중 (6.6.5)
│     │  ├─ object_resize.dart           # (새) 핸들 끌기 수학: cornerScale(회전된 frame) · resize · moveVertex
│     │  ├─ object_edit_interaction.dart # (새) 핸들·꼭짓점 끌기 → setPreviewObjects → UpdateObjects
│     │  └─ text_tool_interaction.dart   # (새) 텍스트 도구 탭·끌기 (6.11.1)
│     ├─ text/                           # (새)
│     │  ├─ text_edit_session.dart       # TextEditSession · editorTextEditProvider (E-6)
│     │  ├─ text_box_editor.dart         # material_ui TextField(collapsed) 오버레이 (안 0 inline)
│     │  ├─ text_draft_store.dart        # (P-B) 긴 세션 초안 주기 저장·복구 제안 (6.11.2)
│     │  ├─ text_input_sheet.dart        # 웹 대체안 A: 시트 입력란
│     │  ├─ textarea_overlay.dart        # 웹 대체안 B 진입 (조건부 export) — P-C
│     │  ├─ textarea_overlay_stub.dart   #   VM·네이티브: 빈 위젯
│     │  └─ textarea_overlay_browser.dart#   웹: HtmlElementView + dart:js_interop (V2)
│     ├─ objects/                        # (새)
│     │  ├─ object_factory.dart          # id·pageId·createdAt 채움, 한도 검사
│     │  ├─ object_placement.dart        # 삽입 위치·크기 (이미지·붙여넣기·텍스트 새 상자)
│     │  └─ image_flows.dart             # 이미지 삽입 · 이미지 페이지 흐름 (6.12)
│     ├─ playback/                       # (새)
│     │  ├─ recording_link.dart          # R-1 → InkStrokeMeta (6.15.1)
│     │  ├─ playback_highlighter.dart    # PlaybackHighlightLogic(출력 주입) + Driver(Ticker) (6.15.2)
│     │  └─ tap_to_seek.dart             # 탭 재생 상태(R-5) · 탭 → hitTestRecorded → seekMs (6.15.3)
│     ├─ commands/
│     │  ├─ editor_commands.dart         # (확장) cut·duplicate·recolor·rotate90·paste v2·삽입·텍스트 커밋·확장 실행
│     │  └─ extension_runner.dart        # (새) 자리 콜백 실행·오류 처리 (E-7)
│     ├─ state/
│     │  ├─ settings/editor_settings.dart          # (확장) GestureSettings v2, 4.3.3 필드
│     │  ├─ settings/editor_settings_notifier.dart # (확장) 새 setter
│     │  ├─ settings/editor_setting_keys.dart      # (확장) toolOptions, playbackPreRollMs, deviceState, textDraft — all 형 List<SettingKey<Object?>>
│     │  ├─ settings/editor_device_state.dart      # (새) 내부 device 키: 웹 입력 방식·도형 표본 토글·Pencil 첫 이벤트 (6.18)
│     │  ├─ settings/pre_roll.dart                 # (새) editorPreRollMsProvider (6.19)
│     │  ├─ panel.dart                   # (새) 하단 패널 열림 상태
│     │  ├─ tape_state.dart              # (새) '모두 보이기' 노트 단위 상태
│     │  └─ popup.dart                   # (확장) 새 팝업 종류·위치 지정 팝업
│     └─ ui/
│        ├─ editor_body.dart             # (확장) 하단 패널 자리, 재생 강조 구동기, 텍스트 편집기 층
│        ├─ editor_strings.dart          # (확장)
│        ├─ popup_host.dart              # (확장) 새 앵커(도형·텍스트·삽입·색), 좌표 팝업
│        ├─ toolbar/ editor_toolbar.dart (확장) · insert_menu.dart (새) · mic_button.dart (새) · more_menu.dart (확장: 테이프)
│        ├─ pen/     pen_type_selector.dart (확장: 10종) · pen_extras_controls.dart (새) · pen_settings_popup.dart (확장) · quick_pen_popup.dart (확장: 좌표)
│        ├─ shape/   shape_tool_popup.dart (새) · shape_style_controls.dart (새)
│        ├─ text/    text_format_bar.dart (새) · text_tool_popup.dart (새)
│        ├─ overlays/ selection_frame_painter.dart (확장: 회전 프레임·회전 핸들·객체 핸들·꼭짓점)
│        │            selection_menu.dart (확장: 잘라내기·색·더보기·확장 항목)
│        │            recolor_popup.dart (새) · rotation_label.dart (새) · focus_flash.dart (새)
│        │            context_menu.dart (확장: 이미지 붙여넣기) · cursor_painter.dart (확장: 호버 자세)
│        ├─ panels/  editor_panel_slot.dart (새: 40% 이하 하단 자리)
│        ├─ pages/   add_page_sheet.dart (확장: '이미지' 줄)
│        ├─ eraser/  eraser_popup.dart (확장: 도형도 지우기)
│        ├─ settings/ editor_settings_sections.dart (확장) · gesture_action_tile.dart (새)
│        └─ dev/     dev_metrics.dart (확장) · dev_overlay.dart (확장) · ../toolbar/dev_menu.dart (확장)
└─ test/
   ├─ helpers/   (확장) pump_editor.dart(객체·녹음 시드) · pointer_driver.dart(펜 버튼·웹 접촉 순서)
   │             (새) fake_stylus_extras.dart · fake_image_importer.dart · fake_extensions.dart · ink_edit_builders.dart
   │                  mapping_table.dart(5.1.2 표 + 행마다 덮는 P-A 시험 파일 — 9.3)   (재생 호출 기록은 CORE FakeAudioPlayback.calls — CP-8 승인)
   ├─ unit/      (9.2 표)
   ├─ widget/    (9.2 표)
   ├─ goldens/   (확장) selection_frame_v2_golden_test.dart · object_handles_golden_test.dart
   ├─ integration/ (확장) objects_smoke_test.dart · recording_link_smoke_test.dart · (P-B) shape_assist_smoke_test.dart(E2-21b)   (@Tags(['integration']))
   └─ web/       (확장) editor_browser_smoke_v2_test.dart · text_input_browser_test.dart · textarea_overlay_browser_test.dart (P-C)
```

- **이름 바꿈 하나**: `tools/stroke_clipboard.dart` → `tools/element_clipboard.dart`(`StrokeClipboardNotifier` → `ElementClipboardNotifier`, provider 이름 `editorClipboardProvider`는 유지). 내부 이름이라 계약과 무관하다. 시험 `unit/stroke_clipboard_test.dart`도 `element_clipboard_test.dart`로 옮긴다.
- **플랫폼 파일 하나(P-C)**: `text/textarea_overlay_browser.dart`가 EDITOR의 첫 `*_browser.dart`다. `dart:js_interop`·`dart:js_interop_unsafe`(SDK)만 쓰고 `package:web`은 쓰지 않는다(V2). INFRA `ws check` R4의 `web_only_imports`·`web_suffixes` 규칙 안이다(`tool/workspace_rules.yaml` [확인]). 1차 계획서 6.16 'EDITOR는 플랫폼별 파일이 필요 없다'는 6.24로 바꾼다(EDITOR 내부 규칙).
- 1차의 `test/web/editor_browser_smoke_test.dart`는 1차 작업 트리의 `area/editor` 브랜치에는 없고 1차 통합 브랜치(`claude/note-app-planning-bk29xb`)의 커밋 `299001b`에 있다 [확인 — `git branch --contains`]. 2차 작업 트리는 1차 통합 뒤 `main`에서 만들므로 그 파일 위에 v2를 더한다((v2.1) 바탕인 1차 통합 HEAD `/home/user/noteapp`에 이미 있다 [확인]).

`pubspec.yaml`(1차 그대로 — 7절): `flutter_riverpod 3.4.3`, `material_ui 1.10.0`, `meta 1.19.0`, `collection 1.19.1`, `note_core: any`, `ink_engine: any`, dev `fake_async 1.3.3`. 플러그인을 넣지 않는다(7.4.1 R16, 2.3 규칙 3).

`dart_test.yaml`: 1차 그대로(`golden: {}`, `integration: {skip: …}`). EDITOR는 `media`·`emulator` 태그를 쓰지 않는다(오디오는 CORE 가짜 포트로만 — 7.4.6).

---

## 4. 공개 API

다른 영역(INFRA 앱 셸·설정 화면·자리 연결)이 쓰는 것만 `package:feature_editor/feature_editor.dart`로 내보낸다. 계약 7.2.10의 정의를 4.2에 글자 그대로 옮기고, 계약이 EDITOR에 맡긴 세부만 4.3에 더한다.

### 4.1 내보내기 목록 v2

```dart
// lib/feature_editor.dart — every exported name (unit/api_surface_test.dart compares this list)
export 'src/di/dev_overlay_section.dart' show DevOverlaySection, devOverlaySectionsProvider;   // v1.4
export 'src/di/editor_extensions.dart'
    show
        EditorExtensions,                    // v1.4 + v2.0 fields
        EditorMenuItem, EditorMenuContext,   // v1.4
        editorExtensionsProvider,            // v1.4
        EditorSelectionContext, EditorSelectionMenuItem,   // (v2.0)
        EditorInsertContext, EditorInsertMenuItem,         // (v2.0)
        EditorPanelBuilder, EditorPanelContext;            // (v2.0)
export 'src/di/editor_image_importer.dart'
    show EditorImageImporter, editorImageImporterProvider;   // (v2.0)
export 'src/di/stylus_extras.dart'
    show
        StylusExtrasSource, StylusExtraEvent, StylusDoubleTap, StylusSqueeze,
        StylusBarrelRoll, NoStylusExtras, stylusExtrasProvider,            // v1.4
        StylusHoverPose, StylusPreferredAction, StylusSqueezePhase,
        StylusCapabilities;                                                // (v2.0)
export 'src/editor_screen.dart' show EditorScreen, featureEditorOverrides;   // + initialFocusRectPt
export 'src/state/settings/editor_settings.dart'
    show
        EditorSettings, InputMode, PageFlipMode, PalmRejectionSettings, GestureSettings,   // v1.4
        EditorGesture, EditorAction;                                                        // (v2.0)
        // (수정 1회차) PlaybackHighlightStyle 삭제 — EditorSettings.playbackHighlight는 ink.InkPlaybackStyle,
        // WebTextInputMode 삭제 — EDITOR 내부 device 키(editor.deviceState, 6.18)
export 'src/state/settings/editor_settings_notifier.dart'
    show EditorSettingsNotifier, editorSettingsProvider;   // v1.4
export 'src/ui/settings/editor_settings_sections.dart'
    show EditorInputSettingsSection, EditorPenSettingsSection,
        EditorPageSettingsSection, EditorDeveloperSettingsSection;   // v1.4 (내용만 확장)
```

- 새 공개 이름 **14개**(계약 7.2.10의 타입 12 + `editorImageImporterProvider` + `EditorPanelBuilder` — 수정 1회차에 `PlaybackHighlightStyle`·`WebTextInputMode` 2개를 뺐다, 검토 S-10·총괄 Q12 답)는 다른 8개 패키지의 공개 진입점과 겹치지 않는다(R14). [확인] 1차 작업 트리 7개의 `lib/*.dart` export 목록과 계약 7.2.11~7.2.13의 새 이름(`RecognitionTarget`·`RecordingPanel`·`PencilEvent` 계열 등)에 같은 이름이 없다. 재생 강조 방식은 INK `ink.InkPlaybackStyle`을 그대로 쓴다(1차 `EditorSettings`가 이미 `ink.PressureMode`를 그대로 쓰는 것과 같다 — `editor_settings.dart` [확인]).
- `featureEditorOverrides()`는 1차처럼 빈 목록이다. 새 자리(`editorImageImporterProvider`·`stylusExtrasProvider`·`editorExtensionsProvider`)는 INFRA `FeatureWiringModule`이 override한다(7.3.3).

### 4.2 확장 지점 · 제스처 · 펜 버튼 (계약 7.2.10 원문)

`// 계약 v2.1 7.2.10 원문` (코드 블록 셋과 표·문장까지 그대로 — `(v2.1)` 표시 문장 포함)

```dart
// --- extension points: 추가 ---
@immutable
class EditorExtensions {
  const EditorExtensions({this.moreMenuItems = const [], this.addPageSources = const [],
      this.appBarTrailing, this.selectionMenuItems = const [], this.insertMenuItems = const [],
      this.recordingPanel});
  /* v1.4: moreMenuItems, addPageSources, appBarTrailing (still reserved) */
  final List<EditorSelectionMenuItem> selectionMenuItems;   // recog: toText, copyText, toMath, editMath
  final List<EditorInsertMenuItem> insertMenuItems;         // recog: mathPad
  final EditorPanelBuilder? recordingPanel;                 // media_io RecordingPanel; null → mic button hidden
}

@immutable
class EditorSelectionContext {
  const EditorSelectionContext({required this.noteId, required this.pageId, required this.pageSize,
      required this.strokes, required this.objects, required this.boundsPt, required this.execute,
      required this.clearSelection});
  final String noteId, pageId;
  final core.PageSize pageSize;
  final List<core.Stroke> strokes;               // selected, z order
  final List<core.PageObject> objects;           // selected, z order
  final Rect boundsPt;                           // page pt
  /// Runs ONE command on the note session (one undo step). Throws like NoteSession.execute
  /// (ReadOnlyNoteException …); the caller shows the message.
  final void Function(core.EditCommand command) execute;
  final VoidCallback clearSelection;
}
@immutable
class EditorSelectionMenuItem {
  const EditorSelectionMenuItem({required this.id, required this.label, required this.icon,
      required this.onSelected, this.isVisible});
  final String id; final String label; final IconData icon;
  final Future<void> Function(BuildContext context, EditorSelectionContext selection) onSelected;
  final bool Function(EditorSelectionContext selection)? isVisible;
}
@immutable
class EditorInsertContext {
  const EditorInsertContext({required this.noteId, required this.pageId, required this.pageSize,
      required this.visibleRectPt, required this.execute, required this.selectObject});
  final String noteId, pageId; final core.PageSize pageSize;
  final Rect visibleRectPt;                      // insert near its center
  final void Function(core.EditCommand command) execute;
  final void Function(String objectId) selectObject;   // select what was just inserted
}
@immutable
class EditorInsertMenuItem {
  const EditorInsertMenuItem({required this.id, required this.label, required this.icon,
      required this.onSelected});
  final String id; final String label; final IconData icon;
  final Future<void> Function(BuildContext context, EditorInsertContext insert) onSelected;
}
typedef EditorPanelBuilder = Widget Function(BuildContext context, EditorPanelContext panel);
@immutable
class EditorPanelContext {
  const EditorPanelContext({required this.noteId, required this.tapToSeek,
      required this.setTapToSeek, required this.close});
  final String noteId;
  final ValueListenable<bool> tapToSeek;         // EDITOR owns the flag (finger tap on a recorded stroke → seek)
  final ValueChanged<bool> setTapToSeek;
  final VoidCallback close;
}

/// Image picking + normalization lives in media_io; EDITOR only calls this slot.
@immutable
class EditorImageImporter {
  const EditorImageImporter({required this.sources, required this.pick});
  final Set<core.ImageImportSource> sources;
  final Future<core.ImportedImage?> Function(BuildContext context, core.ImageImportSource source) pick;
}
final editorImageImporterProvider = Provider<EditorImageImporter?>((ref) => null,
    name: 'editorImageImporterProvider');      // null → image insert / image page hidden

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({/* v1.4 */, this.initialFocusRectPt});
  /// With initialPageId: bring this page rect (pt) into view and flash it (search hits).
  final Rect? initialFocusRectPt;
}
```

- (v2.1) **자리 콜백의 시작과 `context`**: EDITOR는 `EditorSelectionMenuItem.onSelected`·`EditorInsertMenuItem.onSelected`·`EditorImageImporter.pick`을 사용자 누름 처리(`onPressed`) 안에서 **동기적으로** 부른다 — 돌아온 Future를 기다리는 일과 메뉴·시트 닫기는 그 뒤다. 넘기는 `context`는 메뉴가 아니라 **에디터 본문**의 것이고, 항목이 끝날 때까지 에디터가 열려 있으면 mounted다. 받는 쪽은 브라우저 API(파일 선택 input, `navigator.clipboard.read`·`writeText`)를 첫 `await` 전에 부르고, `ProviderScope.containerOf`·`ScaffoldMessenger`·`Navigator`도 첫 `await` 전에 잡는다. iPad Safari는 사용자 동작 직후에만 선택기·클립보드를 연다 [추측 — 7.8 B-3·B-11에서 확인].
- (v2.1) `isVisible`은 메뉴를 그릴 때마다 불린다 — 가볍게, provider를 읽지 않는다(CP-L5). 그 예외는 항목을 숨기고 보고만 한다(E-7 예외).

```dart
// --- gestures: 추가 (v1.4 bool keys kept for reading / writing compatibility) ---
enum EditorGesture { twoFingerTap, threeFingerTap, fingerLongPress, penButton, invertedStylus,
  pencilDoubleTap, pencilSqueeze }
enum EditorAction { none, undo, redo, contextMenu, eraserWhileHeld, lassoWhileHeld, toggleEraser,
  previousTool, toolPalette, colorPalette, followSystem }

@immutable
class GestureSettings {
  const GestureSettings({this.twoFingerTapUndo = true, this.threeFingerTapRedo = true,
      this.longPressMenu = true, this.actions = const {}});
  /* v1.4 bools */
  final Map<EditorGesture, EditorAction> actions;          // missing key → defaultFor
  EditorAction actionFor(EditorGesture gesture);
  static EditorAction defaultFor(EditorGesture gesture);   // table below
  static Set<EditorAction> allowedFor(EditorGesture gesture);
  /// JSON: v1.4 keys + "actions": {"twoFingerTap": "undo", …}. Read: actions[k] wins, else the
  /// v1.4 bool (false → none), else default; unknown names ignored. Write: both (bool = action != none).
  Map<String, Object?> toJson();
  factory GestureSettings.fromJson(Map<String, Object?> json);
}
```

| `EditorGesture` | 기본 | 고를 수 있는 동작 |
|---|---|---|
| `twoFingerTap` | `undo` | none, undo, redo, toggleEraser |
| `threeFingerTap` | `redo` | none, undo, redo, toggleEraser |
| `fingerLongPress` | `contextMenu` | none, contextMenu |
| `penButton` (S펜 측면 버튼을 누른 채 쓰기) | `eraserWhileHeld` | none, eraserWhileHeld, lassoWhileHeld |
| `invertedStylus` (지우개 끝) | `eraserWhileHeld` | none, eraserWhileHeld |
| `pencilDoubleTap` | `followSystem` | none, followSystem, toggleEraser, previousTool, colorPalette, toolPalette, undo |
| `pencilSqueeze` | `followSystem` | none, followSystem, toolPalette, colorPalette, toggleEraser |

- `followSystem`: `StylusPreferredAction`을 따른다 — switchEraser → toggleEraser, switchPrevious → previousTool, showColorPalette → colorPalette, showInkAttributes·showContextualPalette → toolPalette(스퀴즈는 `hoverPosition`에 띄움), ignore·runSystemShortcut·unknown → none.
- Pencil 항목은 `stylusExtrasProvider.capabilities`가 지원할 때만 설정 화면에 보인다. (v2.1) `squeeze`·`barrelRoll` 능력은 OS 가용성(iPadOS 17.5+)일 뿐 펜 종류가 아니다 — 스퀴즈·롤 설정은 그 기기에서 첫 스퀴즈·롤 이벤트를 받은 뒤 보인다(Pencil 2·USB-C 펜슬에서 쓸 수 없는 항목을 숨김, U1).

```dart
// --- stylus extras: 깨짐(구독자 없음) / 추가 ---
// (v2.1, CP-E6) base class gains an optional event time; subclasses pass super.timestamp.
//   sealed class StylusExtraEvent { const StylusExtraEvent({this.timestamp}); final Duration? timestamp; }
//   iOS: same base as PencilEvent.timestamp (systemUptime); null when the source has none.
enum StylusPreferredAction { ignore, switchEraser, switchPrevious, showColorPalette,
  showInkAttributes, showContextualPalette, runSystemShortcut, unknown }
enum StylusSqueezePhase { began, changed, ended, cancelled }
final class StylusDoubleTap extends StylusExtraEvent {
  const StylusDoubleTap({this.preferredAction = StylusPreferredAction.unknown, this.hoverPosition});
  final StylusPreferredAction preferredAction; final Offset? hoverPosition;   // global logical px
}
final class StylusSqueeze extends StylusExtraEvent {
  const StylusSqueeze({this.phase = StylusSqueezePhase.ended,
      this.preferredAction = StylusPreferredAction.unknown, this.hoverPosition});
  final StylusSqueezePhase phase; final StylusPreferredAction preferredAction; final Offset? hoverPosition;
}
final class StylusBarrelRoll extends StylusExtraEvent { const StylusBarrelRoll(this.angle); final double angle; }  // v1.4
final class StylusHoverPose extends StylusExtraEvent {
  const StylusHoverPose({required this.position, this.height, this.altitude, this.azimuth, this.roll});
  final Offset position;                         // global logical px
  final double? height;                          // 0..1 (UIKit zOffset)
  final double? altitude, azimuth, roll;         // rad
}
@immutable
class StylusCapabilities {
  const StylusCapabilities({this.doubleTap = false, this.squeeze = false, this.barrelRoll = false,
      this.hoverPose = false, this.prefersPencilOnlyDrawing = false});
  final bool doubleTap, squeeze, barrelRoll, hoverPose, prefersPencilOnlyDrawing;
  static const StylusCapabilities none = StylusCapabilities();
}
abstract interface class StylusExtrasSource {
  bool get isSupported;                          // v1.4
  StylusCapabilities get capabilities;           // (v2.0) read once at app start — (v2.1) a change in
                                                 // iPadOS settings applies on the next app start
  Stream<StylusExtraEvent> get events;           // v1.4
}
```

입력 규칙(E-4, 조사 02 8·10·12.5): **네이티브**에서는 `PointerDownEvent` 자체가 '닿음'이고, **웹**에서는 `buttons & kStylusContact(0x01) != 0`일 때만 닿음이다(웹은 버튼을 누른 채 띄우면 닿기 전에 `down(0x02)`가 온다). 닿는 순간 `buttons & kPrimaryStylusButton != 0`이면 `penButton` 동작, `kind == invertedStylus`이면 `invertedStylus` 동작으로 그 제스처를 시작한다. 띄운 채 버튼만 눌렀다 떼는 토글은 쓰지 않는다(삼성 Air command·엔진이 `ACTION_BUTTON_PRESS`를 넘기지 않음). (v2.1, CP-E4) 웹에서 접촉 중 `buttons & kStylusContact == 0`인 `move`가 오면 그 접촉의 끝이다(이후 다시 닿으면 새 접촉 — 버튼을 누른 채 펜만 떼면 `up` 없이 `move(0x02)`가 온다, 조사 02 8.4).

### 4.3 EDITOR가 정하는 세부 (계약이 EDITOR에 맡긴 부분)

#### 4.3.1 값 동등 · 자리 항목 규칙

- `EditorExtensions`의 `==`·`hashCode`는 1차와 같이 목록 순서까지 비교하고(`ListEquality`), 새 필드 셋(`selectionMenuItems`·`insertMenuItems`·`recordingPanel`)을 더한다. `recordingPanel`은 Dart 함수 `==`로 비교한다((v2.3, C23-05) 1차 `EditorMenuItem`·`appBarTrailing`과 같음 — 같은 인스턴스 메서드의 tear-off가 다른 값으로 보이지 않게. `identical`이 아님).
- `EditorSelectionMenuItem`·`EditorInsertMenuItem`·`EditorImageImporter`는 1차 `EditorMenuItem`과 같은 규칙으로 필드 전부를 비교하는 `==`를 둔다(함수 필드는 Dart 함수 `==` — C23-05). 문맥 타입(`EditorSelectionContext`·`EditorInsertContext`·`EditorPanelContext`)은 열릴 때마다 새로 만드는 일회용 값이라 `==`를 두지 않는다(`@immutable`만).
- 자리 항목의 `id`는 위젯 키(`ValueKey('editor.ext.<id>')`)와 시험에서 쓴다. 같은 목록 안에서 `id`가 겹치면 뒤의 것을 버리고 `FlutterError.reportError` 1회(개발 중 실수 발견용).
- 항목 실행 규칙(계약 7.2.10 (v2.1) '자리 콜백의 시작과 `context`' + E-7 — 1차 `EditorMenuItem`은 메뉴를 먼저 닫고 `await`했지만 2차 자리는 순서가 다르다, 검토 S-6·CD2-15): 메뉴 항목·시트 단추의 `onPressed` 안에서 ① 두 번 누름 검사(같은 항목이 끝나기 전이면 무시) ② `final future = item.onSelected(bodyContext, ctx)`(이미지 출처는 `importer.pick(bodyContext, source)`)를 **동기적으로** 부른다 — 이 줄 앞에 `await`·`Future.delayed`·`addPostFrameCallback`이 없다(사용자 동작 활성화가 살아 있는 동안 브라우저 선택기·클립보드가 열리게) ③ 그다음 메뉴·시트를 닫는다(`MenuController.close()` / `Navigator.pop`) ④ `future`를 기다린다. ②의 동기 예외와 `Future` 오류 모두 `FlutterError.reportError(library: 'feature_editor', context: 'while running <id>')` 후 스낵바 '실행하지 못했어요'(1차 `EditorStrings.commandFailed`) — 동기 예외여도 ③은 한다. 이 처리는 `commands/extension_runner.dart` 하나에 둔다.
- 넘기는 `context` = **에디터 본문**(`EditorBody`의 `State.context`). `ExtensionRunner`는 `EditorBody`가 넘긴 `BuildContext Function()`으로만 context를 얻고, 메뉴 항목·시트·팝업의 context는 넘기지 않는다(메뉴가 닫히면 unmounted — recog는 `ProviderScope.containerOf`, media는 `showModalBottomSheet`에 이 context를 쓴다). 항목이 끝나기 전에 노트 화면을 떠나면 그 context는 unmounted가 되므로 끝난 뒤 처리(스낵바·`selectObject`)는 `mounted` 검사 뒤에만 한다.
- `isVisible`은 메뉴를 그릴 때마다 부른다(계약 (v2.1) — 가볍게·provider를 읽지 않는 것은 항목 쪽 책임, CP-L5). 예외면 그 항목을 숨기고 `FlutterError.reportError`(같은 메뉴 열림에서 항목마다 한 번)만 한다 — 사용자 문구는 없다(E-7 (v2.1) 예외).

#### 4.3.2 `GestureSettings` 세부 (1차 계약 7.2.17이 EDITOR 4.8에 맡긴 타입)

계약 7.2.10의 멤버에 다음만 더한다(모두 '추가' — 기존 호출이 그대로 컴파일된다).

```dart
// src/state/settings/editor_settings.dart — EDITOR detail of contract 7.2.10 GestureSettings
@immutable
class GestureSettings {
  /* contract 7.2.10 members */
  /// v1.4 copyWith + [actions]. Entries whose action is not in allowedFor(gesture) are dropped.
  GestureSettings copyWith({bool? twoFingerTapUndo, bool? threeFingerTapRedo,
      bool? longPressMenu, Map<EditorGesture, EditorAction>? actions});
  /// actions with [gesture] → [action] (the v1.4 bool of that gesture follows: action != none).
  GestureSettings withAction(EditorGesture gesture, EditorAction action);
  /// Every gesture at defaultFor (bools true, actions empty).
  static const GestureSettings defaults = GestureSettings();
  // ==, hashCode: the three bools + MapEquality(actions); toString
}
```

읽기·쓰기 규칙(계약 문장 'Read: actions[k] wins, else the v1.4 bool (false → none), else default; unknown names ignored. Write: both (bool = action != none)'의 EDITOR 풀이):

| 단계 | 규칙 |
|---|---|
| `actionFor(g)` | ① `actions[g]`가 있고 `allowedFor(g)`에 들면 그 값 ② 없으면 v1.4 bool이 있는 제스처(`twoFingerTap`↔`twoFingerTapUndo`, `threeFingerTap`↔`threeFingerTapRedo`, `fingerLongPress`↔`longPressMenu`)의 bool이 `false`면 `none` ③ 그 밖은 `defaultFor(g)` |
| `fromJson` | v1.4 키 `twoFingerUndo`·`threeFingerRedo`·`longPressMenu`(bool, 잘못된 형식은 기본값 `true`)와 `actions`(객체). (v2.3, R2-B5) 읽은 뒤 v1.4 bool 셋을 `actionFor(g) != none`으로 다시 맞춘다 — `fromJson(toJson(x)) == x`. `actions`의 키 = `EditorGesture.name`, 값 = `EditorAction.name`. 모르는 제스처·모르는 동작·`allowedFor` 밖 동작은 **조용히 버린다**(오류 보고 없음 — 새 판이 만든 값). `actions`가 객체가 아니면 통째로 무시 |
| `toJson` | `{"twoFingerUndo": actionFor(twoFingerTap) != none, "threeFingerRedo": …, "longPressMenu": …, "actions": {명시된 항목만, 이름순}}`. 명시되지 않은 제스처는 쓰지 않는다 — 기본값이 다음 판에서 바뀌어도 사용자가 손대지 않은 항목은 새 기본값을 따른다 |
| `withAction(g, a)` | (v2.3, C23-05 — R2-B5 코드에 맞춘 문구) `a`가 `allowedFor(g)` 밖이면 그대로(`this`). `a == defaultFor(g)`이고 `g`의 이전 v1.4 bool이 `false`가 아니면 `actions`에서 `g`를 지운다. 이전 bool이 `false`인 제스처는 기본값이어도 명시 항목 `actions[g] = a`로 남긴다(옛 앱이 bool만 읽어도 같은 결과가 되게 — 결과 `actionFor`는 어느 쪽이든 기본값). 그 밖은 `actions[g] = a`. 마지막으로 그 제스처의 v1.4 bool을 `a != none`으로 맞춘다 |
| 옛 앱과 섞일 때 | 옛 앱(1차)은 bool만 읽는다. 새 앱이 `twoFingerTap = redo`로 바꾸면 bool은 `true`라 옛 앱은 '되돌리기'로 동작한다(옛 앱은 다른 동작을 모름 — 받아들임). 옛 앱이 bool만 바꿔 쓰면 `actions`는 그대로 남아 새 앱에서 ①이 이긴다 — 옛 앱의 '끄기'가 새 앱에서 무시될 수 있다. 실연결 전이고 사용자 한 명이 모든 기기를 함께 갱신하므로(D4와 같은 근거) 받아들인다 |

JSON 예(`editor.settings.synced`의 `gestures`):

```json
{"twoFingerUndo": true, "threeFingerRedo": false, "longPressMenu": true,
 "actions": {"penButton": "lassoWhileHeld", "threeFingerTap": "none", "twoFingerTap": "redo"}}
```

#### 4.3.3 `EditorSettings` 추가 필드 (1차 계약이 EDITOR 4.8에 맡긴 타입)

```dart
// src/state/settings/editor_settings.dart — added optional fields (defaults keep v1.4 behaviour)
@immutable
class EditorSettings {
  const EditorSettings({/* v1.4 fields */,
      this.shapeAssist = true,                                   // synced (U14: on, can be turned off)
      this.playbackHighlight = ink.InkPlaybackStyle.dimUnwritten,   // synced — the INK enum as is (Q12)
      this.tapToSeek = true});                                   // device (7.4.4 '탭 재생 켬')
  final bool shapeAssist;
  final ink.InkPlaybackStyle playbackHighlight;
  final bool tapToSeek;
  // copyWith / toJson(scope) / fromJson / == / hashCode / toString extended with the three fields
}

// src/state/settings/editor_device_state.dart — EDITOR-internal, NOT exported (device key editor.deviceState)
enum WebTextInputMode { inline, sheet, textarea }                // 6.11.6; native always inline
@immutable
class EditorDeviceState {
  const EditorDeviceState({this.webTextInput = WebTextInputMode.inline,
      this.collectShapeSamples = false, this.seenSqueeze = false, this.seenBarrelRoll = false});
  final WebTextInputMode webTextInput;      // developer menu, web only (6.11.6)
  final bool collectShapeSamples;           // developer toggle '도형 표본 모으기' (6.20, U18), default off
  final bool seenSqueeze, seenBarrelRoll;   // a squeeze / barrel roll event arrived on this device (6.5.1, CD2-24)
  /// {"v":1,"webTextInput":"inline","collectShapeSamples":false,"seenSqueeze":false,"seenBarrelRoll":false}
  Map<String, Object?> toJson();
  factory EditorDeviceState.fromJson(Map<String, Object?> json);   // unknown / wrong type → default, no report
}
/// Root (all notes), 500 ms debounce like EditorSettingsNotifier.
final editorDeviceStateProvider = NotifierProvider<EditorDeviceStateNotifier, EditorDeviceState>(…);
```

- 저장 위치는 6.18 표. `fromJson`은 1차와 같이 모르는 값을 기본값으로 읽는다. `playbackHighlight`의 JSON 값은 `InkPlaybackStyle.name`(`"dimUnwritten"`·`"highlightRecent"`)이다.
- `EditorSettingsNotifier`에 `setShapeAssist(bool)`·`setPlaybackHighlight(ink.InkPlaybackStyle)`·`setTapToSeek(bool)`을 더한다(1차 setter와 같은 500 ms 디바운스 쓰기). 웹 입력 방식·도형 표본 토글·Pencil 첫 이벤트는 공개 `EditorSettings`가 아니라 내부 `EditorDeviceStateNotifier`(`setWebTextInput`·`setCollectShapeSamples`·`markSeenSqueeze`·`markSeenBarrelRoll`)가 가진다 — 개발자 메뉴·Pencil 소비만 쓰는 값이라 공개 표면에 둘 이유가 없다(검토 S-10).
- 'preRoll'(R-5)은 계약이 키 이름 `editor.playback.preRollMs`(정수 키 — 7.4.4 v2.1)를 정했으므로 `EditorSettings`가 아니라 그 키를 읽고 쓰는 `editorPreRollMsProvider`(6.19)로 따로 둔다.

#### 4.3.4 `NoStylusExtras` · `EditorScreen`

```dart
class NoStylusExtras implements StylusExtrasSource {
  const NoStylusExtras();
  @override bool get isSupported => false;                                 // v1.4
  @override StylusCapabilities get capabilities => StylusCapabilities.none; // (v2.0)
  @override Stream<StylusExtraEvent> get events => const Stream<StylusExtraEvent>.empty();
}
```

- `EditorScreen.initialFocusRectPt`: `initialPageId`가 없거나 노트에 없는 페이지면 무시한다(INFRA 13절 표 '`page`와 함께일 때'와 같음). 쓰는 법은 6.16. 노트 화면 안의 scoped provider `editorInitialFocusRectProvider`로 넘긴다(1차 `editorInitialPageIdProvider`와 같은 방식).
- `StylusExtraEvent` 하위 타입의 값 동등: `StylusDoubleTap`·`StylusSqueeze`·`StylusBarrelRoll`·`StylusHoverPose`·`StylusCapabilities`는 필드 전부(`StylusExtraEvent.timestamp` 포함 — v2.1, CP-E6)를 비교하는 `==`·`hashCode`를 둔다(시험·중복 이벤트 거르기용). 하위 타입 생성자는 계약대로 `super.timestamp`를 받는다(`StylusBarrelRoll(this.angle, {super.timestamp})` 꼴 — 위치 인자 `angle`은 v1.4 그대로).

---

## 5. 사용하는 다른 영역의 계약

계약 7장의 이름·형태를 그대로 쓴다. EDITOR가 쓰는 정의를 원문 그대로 옮기고(`// 계약 v2.1 7.2.x 원문`), 그 아래에 EDITOR의 사용 규칙을 적는다.

### 5.1 CORE (`package:note_core/note_core.dart`, X18·X19·X20)

| # | 인터페이스 | EDITOR가 쓰는 곳 |
|---|---|---|
| X18 | `PageObject` 계열, `AddObjects`·`UpdateObjects`·`RemoveElements`·`ClearPage.includeObjects`, `PageContent.objects` | 도형·텍스트·이미지 도구, 핸들·꼭짓점 편집, 선택 메뉴, 클립보드, 페이지 마운트 |
| X19 | `audioRecorderServiceProvider`·`audioPlaybackServiceProvider`, `noteRecordingsProvider` | 펜 다운 녹음 메타(R-1), 재생 강조, 탭 재생, 마이크 버튼 녹음 중 표시 |
| X20 | `ImageImportSource`·`ImportedImage`(값 타입만) | 이미지 삽입·이미지 페이지 흐름(가져오기 자체는 자리 너머 media) |

#### 5.1.1 페이지 객체 (7.2.2)

`// 계약 v2.1 7.2.2 원문`

```dart
// lib/src/common/geometry.dart — (v2.0) added
@immutable
final class PagePoint {
  const PagePoint(this.x, this.y);               // pt, page coordinates, y down
  final double x, y;
  PagePoint transformed(Affine2 m);
}

/// (v2.0) Rotated box in page pt. [rect] is the UNROTATED box; [rotation] (rad, clockwise
/// on screen because y is down) turns it about rect's center.
@immutable
final class ElementFrame {
  const ElementFrame(this.rect, {this.rotation = 0});
  final PageRect rect;                           // width, height in [0, 14400] (a straight line's frame may be flat)
  final double rotation;                         // normalized to (-pi, pi]
  PagePoint get center;
  List<PagePoint> get corners;                   // tl, tr, br, bl after rotation
  PageRect get bounds;                           // AABB of corners
  /// Similarity transforms (move / uniform scale / rotate) are exact: center' = m(center),
  /// width·s, height·s, rotation + m.rotation, s = m.uniformScale. Other transforms are
  /// approximated the same way (EDITOR sends non-uniform resizes as UpdateObjects).
  ElementFrame transformed(Affine2 m);
  bool contains(PagePoint p, {double tolerance = 0});
  List<double> toJson();                         // [left, top, right, bottom, rotation]
  factory ElementFrame.fromJson(List<Object?> json);   // FormatException on bad input; (v2.1) never normalizes
  // (v2.1, CP-4) static const double maxSide = 14400 (= PageSize.maxSide; fromJson rejects larger);
  //   ElementFrame normalized() — sides clamped [0, maxSide] around the center, rotation folded
  //   into (-pi, pi]; ==, hashCode. PagePoint: ==, hashCode (no JSON of its own).
}
```

```dart
// lib/src/model/stroke.dart — PageElement stays sealed; the new subtypes are `part` files
// of this library (page_object.dart, shape_object.dart, …).
sealed class PageElement implements SyncEntity { /* v1.4: id, pageId, bounds, createdAt, updatedAt */ }
final class Stroke extends PageElement { /* v1.4 */ }

/// (v2.0) Every page element that is not a Stroke: EntityKind.pageObject, table
/// `page_objects`, subtype chosen by JSON `type`.
sealed class PageObject extends PageElement {
  const PageObject();
  @override EntityKind get kind => EntityKind.pageObject;
  String get type;                               // 'shape' | 'text' | 'image' | 'math' | unknown
  ElementFrame get frame;
  @override EpochMillis? get deletedAt;
  @override Hlc? get version;
  /// Assets this object references (ImageObject: {assetId}); others empty.
  Set<AssetId> get referencedAssets;
  /// (v2.1) THE object transform rule. CORE's resolver (TransformElements) and every preview
  /// (INK selection / pending display, EDITOR) call this same function (INK review M-2):
  ///   frame / geometry transformed by m; s = m.uniformScale;
  ///   ShapeObject: style.strokeWidth × s clamped [0.1, 30] when [scaleWidth];
  ///   TextBoxObject: style.fontSizePt × s clamped [6, 144] (CP-2 — wrap width and text scale
  ///   together, so the frame height still fits; K-6);
  ///   MathObject: style.fontSizePt × s clamped [6, 144]; ImageObject: frame only;
  ///   UnknownObject: returns itself unchanged.
  PageObject transformed(Affine2 m, {bool scaleWidth = true});
  /// Paste / duplicate / page copy: new id, page and createdAt; version and deletedAt cleared.
  PageObject copyTo({required ElementId id, required PageId pageId, required EpochMillis createdAt});
  PageObject copyWithMeta({EpochMillis? updatedAt, EpochMillis? deletedAt,
      bool clearDeletedAt = false, Hlc? version});
  /// (v2.1, CP-4) History memory estimate (02-core 4.3 formula).
  int get estimatedBytes;
  @override Map<String, Object?> toJson();
  /// Dispatches on `type`; an unknown type → UnknownObject (never throws for that reason).
  /// (v2.1, CP-6) A known type with an enum name this app does not know (`shape`, `dash`,
  /// `arrowHeads`, `align`) is also read as UnknownObject. Never normalizes (remote values
  /// round-trip unchanged; normalization happens when a LOCAL command is resolved).
  factory PageObject.fromJson(Map<String, Object?> json);
}

abstract final class PageObjectLimits {
  static const int maxObjectsPerPage = 2000;
  static const int maxTextLength = 10000;        // TextBoxObject.text, String.length
  static const int maxLatexLength = 4000;
  static const int maxPolylinePoints = 64;
}
```

```dart
// --- shapes ---
enum ShapeKind { line, arrow, rectangle, ellipse, triangle, polygon, star }
enum LineDash { solid, dashed, dotted }          // INK renders; dash lengths in multiples of strokeWidth
enum ArrowHeads { none, end, both }

@immutable
final class ShapeStyle {
  const ShapeStyle({required this.strokeColorArgb, this.strokeWidth = 2.0, this.strokeOpacity = 1.0,
      this.dash = LineDash.solid, this.fillColorArgb, this.fillOpacity = 1.0,
      this.arrowHeads = ArrowHeads.none});
  static const double minWidth = 0.1, maxWidth = 30.0;   // = StrokeStyle range
  final int strokeColorArgb;                     // alpha forced to 0xFF by normalized() (1차 K-5와 같음)
  final double strokeWidth;                      // pt
  final double strokeOpacity;                    // [0.05, 1]
  final LineDash dash;
  final int? fillColorArgb;                      // null = no fill
  final double fillOpacity;                      // [0, 1]
  final ArrowHeads arrowHeads;                   // line / arrow only; others ignore it
  /// Arrowhead length in pt: max(6, 3 * strokeWidth). Part of the bounds rule below.
  double get arrowHeadLength;
  ShapeStyle normalized();
  ShapeStyle copyWith({int? strokeColorArgb, double? strokeWidth, double? strokeOpacity,
      LineDash? dash, int? fillColorArgb, bool clearFill = false, double? fillOpacity,
      ArrowHeads? arrowHeads});
  Map<String, Object?> toJson();
  factory ShapeStyle.fromJson(Map<String, Object?> json);
}

/// Shape geometry in ABSOLUTE page pt. Vertex editing moves PolylineGeometry.points.
sealed class ShapeGeometry {
  const ShapeGeometry();
  ShapeGeometry transformed(Affine2 m);
  ElementFrame get frame;                        // polyline: AABB of points (rotation 0); ellipse: its frame
  Object toJson();                               // {"poly":[x0,y0,…],"closed":bool} | {"ellipse":[l,t,r,b,rot]}
  factory ShapeGeometry.fromJson(Object? json);
  // Templates (pure geometry, used by EDITOR's shape tool and the shape fitter):
  static PolylineGeometry line(PagePoint a, PagePoint b);
  static PolylineGeometry rectangle(PageRect r, {double rotation = 0});         // 4 points, clockwise from top-left
  static EllipseGeometry ellipse(PageRect r, {double rotation = 0});
  static PolylineGeometry triangle(PageRect r);                                 // isosceles, apex up
  static PolylineGeometry regularPolygon(PageRect r, int sides, {double rotation = 0});   // 3..12
  static PolylineGeometry star(PageRect r, {int points = 5, double innerRatio = 0.5});    // 2·points vertices
}
final class PolylineGeometry extends ShapeGeometry {
  const PolylineGeometry(this.points, {required this.closed});
  final List<PagePoint> points;                  // 2..PageObjectLimits.maxPolylinePoints
  final bool closed;
}
final class EllipseGeometry extends ShapeGeometry {
  const EllipseGeometry(this.ellipseFrame);
  final ElementFrame ellipseFrame;               // bounding box before rotation
}

final class ShapeObject extends PageObject {
  ShapeObject({required this.id, required this.pageId, required this.shapeKind,
      required this.geometry, required this.style, required this.createdAt, int? updatedAt,
      this.deletedAt, this.version});
  @override String get type => 'shape';
  final ShapeKind shapeKind;                     // UI meaning only; geometry is the truth
  final ShapeGeometry geometry;
  final ShapeStyle style;
  @override ElementFrame get frame => geometry.frame;
  /// Derived, identical on every device (K-6):
  ///   geometry.frame.bounds.inflate(style.strokeWidth * 0.75
  ///       + (arrowHeads != none && shapeKind is line|arrow ? style.arrowHeadLength : 0))
  @override PageRect get bounds;
  ShapeObject copyWith({ShapeKind? shapeKind, ShapeGeometry? geometry, ShapeStyle? style,
      EpochMillis? updatedAt});
  // id, pageId, createdAt, updatedAt, deletedAt, version — as Stroke
}
```

```dart
// --- text boxes, images, math ---
enum TextAlignKind { start, center, end }

@immutable
final class TextBoxStyle {
  const TextBoxStyle({this.fontSizePt = 16, this.colorArgb = 0xFF1A1A1A, this.bold = false,
      this.align = TextAlignKind.start, this.lineHeight = 1.4, this.backgroundArgb});
  static const double minFontSize = 6, maxFontSize = 144;
  final double fontSizePt;
  final int colorArgb;                           // alpha 0xFF
  final bool bold;
  final TextAlignKind align;
  final double lineHeight;                       // [1.0, 3.0], multiple of fontSizePt
  final int? backgroundArgb;                     // null = transparent
  TextBoxStyle normalized();
  TextBoxStyle copyWith({double? fontSizePt, int? colorArgb, bool? bold, TextAlignKind? align,
      double? lineHeight, int? backgroundArgb, bool clearBackground = false});
  Map<String, Object?> toJson();
  factory TextBoxStyle.fromJson(Map<String, Object?> json);
}

final class TextBoxObject extends PageObject {
  TextBoxObject({required this.id, required this.pageId, required this.frame, required this.text,
      required this.style, required this.createdAt, int? updatedAt, this.deletedAt, this.version});
  @override String get type => 'text';
  /// frame.rect.width = wrap width; height = laid-out height written by EDITOR with
  /// INK InkTextLayout.measure (7.2.9). INK clips the text to the frame (K-6).
  @override final ElementFrame frame;
  final String text;                             // plain text, '\n' = line break, ≤ maxTextLength
  final TextBoxStyle style;
  @override PageRect get bounds => frame.bounds;
  TextBoxObject copyWith({ElementFrame? frame, String? text, TextBoxStyle? style, EpochMillis? updatedAt});
}

final class ImageObject extends PageObject {
  ImageObject({required this.id, required this.pageId, required this.frame, required this.assetId,
      required this.pixelWidth, required this.pixelHeight, required this.createdAt, int? updatedAt,
      this.deletedAt, this.version});
  @override String get type => 'image';
  @override final ElementFrame frame;            // aspect = pixel aspect unless the user unlocks it
  final AssetId assetId;                         // AssetType.image, mime image/jpeg | image/png (7.2.6)
  final int pixelWidth, pixelHeight;             // intrinsic size of the stored bytes
  @override PageRect get bounds => frame.bounds;
  @override Set<AssetId> get referencedAssets => {assetId};
  ImageObject copyWith({ElementFrame? frame, EpochMillis? updatedAt});
}

@immutable
final class MathStyle {
  const MathStyle({this.colorArgb = 0xFF1A1A1A, this.fontSizePt = 18});
  static const double minFontSize = 6, maxFontSize = 144;   // (v2.1, CP-5)
  final int colorArgb;
  final double fontSizePt;                       // [6, 144]; scaled by TransformElements
  MathStyle normalized();                        // (v2.1) alpha 0xFF, size clamped
  MathStyle copyWith({int? colorArgb, double? fontSizePt});   // (v2.1)
  Map<String, Object?> toJson();
  factory MathStyle.fromJson(Map<String, Object?> json);
}

final class MathObject extends PageObject {
  MathObject({required this.id, required this.pageId, required this.frame, required this.latex,
      required this.style, this.engineId, required this.createdAt, int? updatedAt, this.deletedAt,
      this.version});
  @override String get type => 'math';
  /// Laid out by INK InkMathRenderer at style.fontSizePt when inserted / edited; INK draws the
  /// formula contain-fitted into the frame (K-6), so devices with other metrics stay inside.
  @override final ElementFrame frame;
  final String latex;                            // ≤ maxLatexLength; INK validate() == null before insert
  final MathStyle style;
  final String? engineId;                        // provenance: 'manual', 'mathpix/…', 'claude/…'
  @override PageRect get bounds => frame.bounds;
  MathObject copyWith({ElementFrame? frame, String? latex, MathStyle? style, String? engineId,
      EpochMillis? updatedAt});
}

/// Object written by a newer app (or, v2.1 CP-6, a known type with an unknown enum name). It can
/// be selected, deleted and copied as a whole and is synced unchanged; it cannot be transformed or
/// edited. JSON round-trips key-for-key (C-12).
final class UnknownObject extends PageObject {
  /// (v2.1, CP-4) rawJson must carry id, pageId, type, createdAt, updatedAt (FormatException
  /// otherwise); kept as an unmodifiable deep copy; frame / deletedAt / version read from it.
  UnknownObject(Map<String, Object?> rawJson);
  @override final String type;
  final Map<String, Object?> rawJson;
  /// From rawJson['frame'] when decodable, else ElementFrame(PageRect(0, 0, 1, 1)).
  @override final ElementFrame frame;
  @override PageRect get bounds => frame.bounds;
  /// (v2.1) A string `assetId` key in rawJson is reported (so a later asset GC keeps it).
  @override Set<AssetId> get referencedAssets;
  /// (v2.1) rawJson with the meta keys (id, pageId, createdAt, updatedAt, deletedAt, version) set
  /// to the current values; every other key as read. ==, hashCode: deep equality of toJson().
  @override Map<String, Object?> toJson();
}
```

EDITOR 사용 규칙

- **새 객체를 만들 때**(도형·텍스트·이미지·붙여넣기): `id = ref.read(core.idGeneratorProvider).newId()`, `createdAt = clock.now().millisecondsSinceEpoch`(여러 개면 `createdAt + i` — 1차 획 클립보드 규칙), `version == null`, `pageId = 넣을 페이지`. `objects/object_factory.dart` 한 곳에서만 만든다.
- **스타일은 언제나 `normalized()`**를 거쳐 넣는다(`ShapeStyle`·`TextBoxStyle`·(v2.1, CP-5) `MathStyle` — 알파 0xFF·범위). EDITOR는 수식 스타일을 만들지 않고 색 변경만 INK `recolor`로 한다. 원격에서 온 값은 `fromJson`이 정규화하지 않으므로(v2.1, CP-6) EDITOR가 화면·편집에 쓸 때 다시 정규화하지 않는다 — 로컬 명령이 해석될 때 CORE가 정규화한다.
- **객체 변형은 CORE `PageObject.transformed(m, {scaleWidth})` 하나**(v2.1 단일 규칙 — CD2-07): EDITOR가 만드는 미리보기 사본(텍스트 상자 시트 미리보기 제외 — 변형이 아님)과 붙여넣기 이동은 이 함수만 쓰고, 도형 굵기·텍스트·수식 글자 크기 배율을 EDITOR가 따로 계산하지 않는다. 그래서 미리보기 = 커밋 결과다.
- **한도**: 넣기 전에 `content.objectCount + 새 개수 > PageObjectLimits.maxObjectsPerPage`면 명령을 보내지 않고 안내(6.21). 텍스트는 입력기에서 `maxTextLength`로 자르고, 다각형 변 수·별 꼭짓점은 `maxPolylinePoints` 안(다각형 3~12, 별 꼭짓점 4~16 → 점 8~32).
- **`UnknownObject`**: 선택·삭제·복사·붙여넣기만 한다. 핸들·색 변경·스타일 편집 대상에서 뺀다(`UpdateObjects`는 `ArgumentError` — 7.2.3). 변형(`TransformElements`)은 CORE가 건너뛴다.
- 회전 각은 `ElementFrame.rotation`(시계 방향, (-π, π])을 그대로 쓴다. EDITOR는 뒤집기(행렬식 < 0)를 보내지 않는다(CORE CP-12 ①과 같은 이해).

#### 5.1.2 페이지 내용 · 명령 (7.2.3) · EDITOR 명령 매핑 v2

`// 계약 v2.1 7.2.3 원문`

```dart
final class PageContent {                                         // 추가
  PageContent({required this.page, required List<Stroke> strokes,
      List<PageObject> objects = const [], required this.revision});
  final List<PageObject> objects;              // active only, Stroke.compareOrder
  PageObject? objectById(ElementId id);
  PageElement? elementById(ElementId id);       // stroke or object
  int get objectCount;
  // page, strokes, revision, strokeById, strokeCount — v1.4
}
// PageContentChange.added/removed/updated: element ids (strokes AND objects) — v1.4 type, wider meaning

final class PageDraft {                                           // 추가
  const PageDraft({this.id, required this.size, required this.background,
      this.strokes = const [], this.objects = const []});
  final List<PageObject> objects;              // copied with new ids by InsertPages / DuplicatePages
  factory PageDraft.copyOf(PageContent content); // strokes AND objects
}
```

```dart
// (v2.1, CP-1) new commands in the v1.4 command shape — const, named arguments, label.
// EditCommand is sealed; the only exhaustive switch is CORE's resolver.
/// objects: new ids, version == null, pageId == this.pageId. ≤ PageObjectLimits.maxObjectsPerPage.
final class AddObjects extends EditCommand {
  const AddObjects({required this.pageId, required this.objects});
  final PageId pageId; final List<PageObject> objects;
  @override String get label => 'add-objects';
}
/// Replace by id (same id, same type). UnknownObject or a missing id → ArgumentError before any
/// change. Only JSON keys whose value changed get a new field version (1차 7.2.10, C-11).
final class UpdateObjects extends EditCommand {
  const UpdateObjects({required this.pageId, required this.objects});
  final PageId pageId; final List<PageObject> objects;
  @override String get label => 'update-objects';
}
/// Removes strokes AND objects by id; unknown / already deleted / repeated ids ignored (like
/// RemoveStrokes). (v2.1) A List like every v1.4 id list (RemoveStrokes.strokeIds,
/// TransformElements.elementIds) — callers write [id], not {id}.
final class RemoveElements extends EditCommand {
  const RemoveElements({required this.pageId, required this.elementIds});
  final PageId pageId; final List<ElementId> elementIds;
  @override String get label => 'remove-elements';
}

// changed meaning — 규칙 (v1.4 constructors are named; shown here as v1.4 defines them)
// TransformElements({pageId, elementIds, transform, scaleStrokeWidth = true}): strokes as v1.4
//   (Stroke.transformed(m, scaleWidth:) — (v2.1) calligraphy nib angle turns with it, C2-38) AND
//   objects via PageObject.transformed(m, scaleWidth: scaleStrokeWidth) — the single rule (7.2.2).
// ClearPage({pageId, filter = StrokeFilter.all, includeObjects = false}) — 추가 (named, optional):
//   includeObjects removes every PageObject too (filter applies to strokes only).
// InsertPages / DuplicatePages: PageDraft.objects copied with new ids.
// DeletePages / note purge / note copy / backup: objects follow strokes (CORE 동작 계약).
```

EDITOR 명령 매핑(04-editor 5.1 표에 더할 것):

| 사용자 동작 | 명령 (한 번 = 되돌리기 1단계) |
|---|---|
| 도형 그리기 완료, 자동 보정 확정 | `AddObjects([ShapeObject])` (자동 보정 때 원래 획은 저장되지 않음) |
| 텍스트 상자 만들기 → 입력 → 포커스 해제 | 새 상자: `AddObjects`, 기존 상자: `UpdateObjects` (편집 세션 1회 = 1단계, E-6) |
| 핸들로 비율 무시 크기 조절, 꼭짓점 이동, 스타일 변경 | `UpdateObjects` |
| 선택 이동·비율 유지 크기·회전 | `TransformElements` (획 + 객체) |
| 선택 색 변경 | `CompositeCommand([RestyleStrokes, UpdateObjects])` (빈 쪽은 뺌) |
| 잘라내기 | 클립보드 복사 + `RemoveElements` 한 번 |
| 붙여넣기 | `CompositeCommand([AddStrokes, AddObjects])` (빈 쪽은 뺌) |
| 손글씨 → 텍스트 상자 | `CompositeCommand([RemoveElements(획), AddObjects([TextBoxObject])])` (recog가 `execute`로) |
| 이미지 삽입 | `AddObjects([ImageObject])`, 이미지 페이지: `InsertPages([PageDraft(background: ImageBackground)])` |
| (v2.1) 텍스트 편집 세션 끝 — 내용을 모두 지움 | `RemoveElements` |
| (v2.1) 현재 페이지 전체 지우기(객체 포함) | `ClearPage(includeObjects: true)` |
| (v2.1) 선택 복제 | `CompositeCommand([AddStrokes, AddObjects])` (빈 쪽은 뺌) |
| (v2.1) 부분 지우개가 도형에 닿음 | `CompositeCommand([SplitStrokes 또는 RemoveStrokes, RemoveElements(도형)])` (INK `toCommand` — CP-INK-2. 되돌리기 1번에 조각과 도형이 함께 돌아온다) |

(v2.1) 표의 명령은 위 블록의 이름 있는 인자 모양이다(표에서는 줄여 적는다).

- (v2.1, C21-07) 새 명령 3종은 1차 명령 모양(`const`, 이름 있는 인자, `label`)이고 `RemoveElements.elementIds`는 `List<ElementId>`다(CP-E1 = CORE CP-1 승인, 총괄 CD2-06). EDITOR는 `[id]`로 쓴다(`{id}` 아님). 1차 명령(`ClearPage`·`TransformElements`·`InsertPages` 등)도 모두 이름 있는 인자다(1차 `commands.dart` [확인]). EDITOR 코드는 `commands/editor_commands.dart` 한 파일에서만 명령을 만든다. INK `toCommand`가 만드는 `RemoveElements`도 같은 `List` 형이다(7.2.9 표 — `elementIds: removedIds` → INK가 `.toList()`, 1차 `InkEdit.removedIds`가 `Set`인 것과 같은 처리).

EDITOR 명령 매핑 전체(1차 계획서 5.1.3 표 + 위 원문 표 — 모두 '한 번 = 되돌리기 1단계', 표기는 실제 호출 모양. `test/helpers/mapping_table.dart`가 이 표를 그대로 옮긴다 — 9.3. (수정 3회차) `mapping_table.dart`는 행마다 그 행을 덮는 시험 파일도 함께 적고, 덮는 시험은 모두 **P-A 작업**의 완료 조건 시험이다 — 8.2 자르기 순서대로 P-B·P-C 작업(3.4)을 미뤄도 `unit/mapping_coverage_test.dart`(10 #4)가 완료를 판정할 수 있게 한다):

| 사용자 동작 | 명령 (실제 호출) | 근거 |
|---|---|---|
| 도형 도구로 끌어 그리기 | `AddObjects(pageId: p, objects: [shape])` | 원문 1행 |
| 자동 도형 보정 확정 | `InkEdit(addShape).toCommand()` = `AddObjects(pageId: p, objects: addedObjects)` | 원문 1행, 7.2.9 표. (수정 3회차) 덮는 시험은 P-A E2-09 `widget/shape_tool_test.dart` — 1차 `commitInkEdit` 경로와 R2-B3의 `InkEditKind.addShape`(`InkEdit` v2·`toCommand` 최종 — 5.2.4)만 쓰므로 P-B E2-15·INK T39를 기다리지 않는다 |
| 텍스트 편집 세션 끝(새 상자, 내용 있음) / (기존 상자, 바뀜) | `AddObjects(pageId: p, objects: [draft])` / `UpdateObjects(pageId: p, objects: [draft])` | 원문 2행, E-6 |
| 텍스트 편집 세션 끝(기존 상자, 내용을 모두 지움) | `RemoveElements(pageId: p, elementIds: [boxId])` | 원문 (v2.1) 10행(CP-E5 승인) — 빈 상자를 남기지 않는다(12.2 Q5) |
| 텍스트 편집 세션 끝(기존 상자, 그 사이 원격 삭제) | `AddObjects(pageId: p, objects: [draft.copyTo(id: 새 id, …)])` — `UpdateObjects`를 보내지 않는다(6.11.5, 검토 S-1) | EDITOR 추가 — 쓴 글을 잃지 않음 |
| 단일 객체의 변 핸들(비율 무시), 텍스트 폭 핸들, 꼭짓점 이동, 도형 스타일 변경(선택한 도형 여럿이면 한꺼번에) | `UpdateObjects(pageId: p, objects: [...])` | 원문 3행 |
| 이동·모서리 핸들(비율 유지 — 회전된 단일 객체는 `ObjectResize.cornerScale`, 6.6.5)·회전 핸들·90° 돌리기 | `InkSelection.setPreviewTransform(m)` → `commitTransform()` → `TransformElements(pageId:, elementIds:, transform: m, scaleStrokeWidth: true)` | 원문 4행. 텍스트·수식 글자 크기와 도형 굵기도 같이 배율(`PageObject.transformed` — CP-2 승인, 7.2.2) |
| 색 변경 | `InkSelection.recolor(argb)` → `CompositeCommand([RestyleStrokes, UpdateObjects])`(빈 쪽은 뺌) | 원문 5행 |
| 잘라내기 | 앱 클립보드 복사(명령 아님) + `InkSelection.delete()` → `RemoveStrokes`(획만) / `RemoveElements(pageId:, elementIds: removedIds)`(객체 섞임) | 원문 6행 |
| 붙여넣기 | `CompositeCommand([AddStrokes(pageId:, strokes:), AddObjects(pageId:, objects:)])` — 한쪽이 비면 남은 명령 하나만 | 원문 7행(빈 쪽은 뺌 — CP-E5 승인) |
| 복제 | `InkSelection.duplicate()` → `CompositeCommand([AddStrokes, AddObjects])`(빈 쪽은 뺌) | 원문 (v2.1) 12행 |
| 이미지 삽입 / 이미지 페이지 | `AddObjects(pageId: p, objects: [image])` / `InsertPages(drafts: [PageDraft(size:, background: ImageBackground(…))], position: …)` | 원문 9행 |
| 현재 페이지 전체 지우기(객체 포함) | `ClearPage(pageId: p, filter: f, includeObjects: true)` | 원문 (v2.1) 11행(CP-E5 승인) — 6.17 |
| 획 지우개가 도형에 닿음 | `InkEdit(eraseStrokes, removedObjectIds: {도형})`.toCommand() → `RemoveElements(pageId:, elementIds: removedIds)` | 7.2.9 표 (v2.1), U22 |
| **부분 지우개**가 도형에 닿음 | `InkEdit(splitStrokes, removedObjectIds: {도형})`.toCommand() → `CompositeCommand([SplitStrokes 또는 RemoveStrokes, RemoveElements(pageId:, elementIds: [도형 id…])])`(빈 쪽은 뺌) — 한 제스처 = 한 명령, 되돌리기 1번에 조각과 도형이 함께 돌아온다 | 원문 (v2.1) 13행, 7.2.9 표(CP-INK-2) — `widget/erase_v2_test.dart` |
| 확장 항목(recog 변환 등) | 자리 문맥의 `execute(command)` 한 번 | 7.2.10 `EditorSelectionContext.execute` |

- 펜 버튼·지우개 끝으로 시작한 임시 지우개·임시 올가미도 위 규칙 그대로다(도구가 바뀌지 않을 뿐).
- 텍스트 편집 중의 글자 입력, 핸들·회전 끌기 중의 미리보기, 도형 끌기 미리보기, 재생 강조, 테이프 드러냄, 레이저는 **명령이 아니다**.
- 지우개 명령은 EDITOR가 만들지 않는다 — INK `toCommand`의 결과를 1차 `commitInkEdit`로 그대로 보낸다. EDITOR 시험은 그 결과(명령 수·`undoDepth`·되돌린 뒤 CORE 내용)를 단언한다.

#### 5.1.3 녹음 · 오디오 포트 (7.2.4)

`// 계약 v2.1 7.2.4 원문 (오디오 포트·연결 규칙 — 녹음 엔티티·저장소 블록은 EDITOR가 noteRecordingsProvider만 쓰므로 생략)`

```dart
// lib/src/media/audio_ports.dart — (v2.0) pure Dart ports. Implemented by media_io, consumed
// by EDITOR (and media_io's own panel). One recorder and one player per app.
enum AudioSupport { supported, unsupported, permissionDenied, permissionPermanentlyDenied }
enum RecorderPhase { idle, starting, recording, paused, finishing }

@immutable
final class RecorderStatus {
  const RecorderStatus({this.phase = RecorderPhase.idle, this.recordingId, this.noteId,
      this.activeMs = 0, this.backgroundCapable = false, this.interrupted = false,
      this.mimeType, this.crossPlatformPlayable = true, this.error});
  final RecorderPhase phase;
  final RecordingId? recordingId;
  final NoteId? noteId;                          // the note the recording belongs to
  final int activeMs;                            // audio-timeline length so far (pauses excluded)
  final bool backgroundCapable;                  // native FGS / UIBackgroundModes; false on web
  final bool interrupted;                        // paused by the system / hidden tab, not the user
  final String? mimeType;                        // what is actually being written
  final bool crossPlatformPlayable;              // false for webm/opus (iOS native can't play it)
  final Object? error;
  bool get isActive;                             // recording || paused (UI only — recovery uses pendingDrafts)
  // ==, hashCode (1차 7.4.4), (v2.1, CP-7) copyWith
}

abstract interface class AudioRecorderService {
  RecorderStatus get status;
  Stream<RecorderStatus> get statusStream;       // emits current value on listen
  Future<AudioSupport> checkSupport({bool requestPermission = false});
  /// [recordingId] is generated by the caller (core.idGeneratorProvider) BEFORE start so the
  /// first stroke can link to it. Throws StateError when another recording is active and
  /// (v2.1, CP-PDF-5) UnsupportedError when checkSupport() != supported (fakes too).
  Future<void> start({required RecordingId recordingId, required NoteId noteId});
  Future<void> pause();
  Future<void> resume();
  /// Finishes the file, stores Asset(audio) then Recording (M-1). null when nothing was recorded.
  /// (v2.1, CP-PDF-5) If storing fails the draft is kept and stop() throws — the next start-up
  /// recovery finishes it with the same recordingId (createRecording is idempotent per id).
  Future<Recording?> stop();
  Future<void> cancel();                         // discards the draft; no Recording row
  /// Audio-timeline ms now (pauses excluded); null unless phase == recording. Synchronous and
  /// cheap — EDITOR calls it at pen down (R-1, R-2).
  int? offsetNowMs();
  /// (v2.1, CP6 = CP-PDF-3 + PDF review M-5) Drafts to recover. Excludes this app's active session
  /// (phase starting … finishing), drafts being recovered, and drafts updated within
  /// max(10 s, 5 × the chunk interval) — they may belong to another tab that is still recording
  /// (D19). The recovery decision uses this list only (callers do not look at status.isActive).
  Future<List<RecordingDraft>> pendingDrafts();
  Future<Recording?> recoverDraft(String draftId);
}

enum PlaybackPhase { idle, loading, ready, playing, paused, completed, failed }
@immutable
final class PlaybackStatus {
  const PlaybackStatus({this.phase = PlaybackPhase.idle, this.recordingId, this.durationMs = 0,
      this.speed = 1.0, this.unsupportedFormat = false, this.error});
  final PlaybackPhase phase; final RecordingId? recordingId; final int durationMs;
  final double speed;                            // [0.5, 2.0]
  final bool unsupportedFormat;                  // e.g. webm on iOS native
  final Object? error;
  // ==, hashCode, (v2.1, CP-7) copyWith. Unsupported* behaviour table: 02-core 6.8.2 (CP-7).
}
abstract interface class AudioPlaybackService {
  PlaybackStatus get status;
  Stream<PlaybackStatus> get statusStream;
  /// Bytes via AssetStore; when missing locally and remoteAssetFetcherProvider is set,
  /// ensureLocal first (P-2 pattern). Closes any open recording.
  Future<void> open(Recording recording);
  Future<void> play();                           // (v2.1, CP-PDF-10) no-op while the recorder is active
  Future<void> pause();
  Future<void> seekMs(int positionMs);           // clamped to [0, durationMs]
  Future<void> setSpeed(double speed);           // clamped to [0.5, 2.0]
  /// Extrapolated position (no platform call). Call every frame.
  int positionMs();
  Future<void> close();
}

// Defaults: web/VM without media_io → unsupported (no throw on read).
final audioRecorderServiceProvider = Provider<AudioRecorderService>(
    (ref) => const UnsupportedAudioRecorder(), name: 'audioRecorderServiceProvider');
final audioPlaybackServiceProvider = Provider<AudioPlaybackService>(
    (ref) => const UnsupportedAudioPlayback(), name: 'audioPlaybackServiceProvider');
final recordingRepositoryProvider = Provider<RecordingRepository>(/* store.recordings */);
final noteRecordingsProvider =
    StreamProvider.autoDispose.family<List<Recording>, NoteId>(/* watchRecordings */);
// testing.dart: FakeAudioRecorder (controllable clock, phases, interruptions),
//               FakeAudioPlayback (manual position, speed) — 1차 7.4.8 공용 가짜
```

획 ↔ 녹음 연결 규칙(계약 문장, 조사 02 6·12.4 채택):

| # | 규칙 |
|---|---|
| R-1 | 펜 다운 순간 `recorder.status.phase == recording` **그리고** `status.noteId == 지금 노트`일 때만 `InkStrokeMeta(recordingId, offsetNowMs())`를 넘긴다. 일시정지 중·다른 노트에서 녹음 중에 쓴 획은 연결하지 않는다(사용자 질문 U12 기본값) |
| R-2 | `recordingOffsetMs`는 **오디오 타임라인 위치**(일시정지 제외)다. 벽시계 차(`createdAt − startedAt`)를 쓰지 않는다. media_io는 단조 `Stopwatch`를 녹음기 상태 이벤트에 맞춰 멈추고 이어 간다 |
| R-3 | `Recording.durationMs` = 저장된 파일 안의 오디오 타임라인 길이(디코더가 읽는 길이). (v2.1) 웹 WebM에는 Duration이 없으므로 media가 **마지막 블록의 타임코드 + 그 블록(패킷)의 길이**(`TimecodeScale` 반영. (v2.2, C22-04) 블록 길이는 Opus면 TOC의 프레임 크기 × 프레임 수 — Chrome은 20 ms × 3 = 60 ms)로 계산해 넣는다 — 녹음 시계 값으로 패치하지 않는다(파싱이 실패할 때만 시계 값 + 개발자 표시 'duration from clock'). 시계 활성 시간과의 차이는 개발자 표시에만 보인다(보정 필드는 실측 뒤 판단 — 조사 02 D9, 7.8 A-5) |
| R-4 | 재생 위치 p에서 획은 `recordingOffsetMs + t_last ≤ p`이면 '쓴 획', `offset ≤ p < offset + t_last`이면 '쓰는 중'이다(INK 7.2.9 재생 강조) |
| R-5 | 필기 탭 재생은 `seekMs(max(0, offset − preRollMs))` 후 재생, `preRollMs` 기본 1500(설정 `editor.playback.preRollMs`, synced). (v2.1) **탭 재생 상태**에서만 가로챈다: 설정 `tapToSeek` 켬 + 녹음기 `phase == idle` + ① 손가락 한 번 탭은 녹음 패널이 열려 있거나 재생기가 `playing`·`paused`일 때 ② 펜 탭(이동 ≤ 4 px·≤ 200 ms — 점만)은 재생기가 `playing`·`paused`일 때만. 판정은 획 세션 `end()` **전에** 하고 가로채면 `cancel()` — 가로채지 않은 펜 입력은 언제나 획이 된다(필기 손실 없음). 재생 강조 초점은 이 녹음을 연 뒤 한 번이라도 `playing`이었거나 `seekMs`가 불린 뒤에만 넣는다 — 열기만 한 `ready`(패널 열기·녹음 정지 직후 자동 열기)는 초점 없음(정지 직후 필기가 흐려지지 않게, PDF 검토 M-8) |
| R-6 | 부분 지우개 조각·붙여넣기·복제는 `recordingId/OffsetMs`를 유지한다(v1.4 그대로). **노트 복사**는 녹음 행도 새 id로 복사하고(에셋은 같은 해시), 복사된 획의 `recordingId`를 새 id로 바꾼다(CORE `copyNote` 동작 계약) |
| R-7 | `recordingId`가 가리키는 녹음 행이 없거나 삭제됐으면 '연결 없음'으로 다룬다(오류 아님). 녹음이 취소(`cancel`)되면 이미 쓴 획의 `recordingId`는 그대로 남고 연결 없음이 된다 |
| R-8 | 녹음 시작·정지·이름·삭제는 되돌리기 히스토리 밖이다(삭제는 확인 창) |

EDITOR 사용 규칙(E-5 구체화)

- **R-1**: 펜 다운 처리(`PenInteraction.start`, 웹은 접촉 순간 — 6.3.2) 안에서 `final rec = ref.read(core.audioRecorderServiceProvider); final s = rec.status;`를 **동기적으로** 읽는다. `s.phase == RecorderPhase.recording && s.noteId == noteId && s.recordingId != null`이고 `rec.offsetNowMs()`가 `null`이 아니면 `ink.InkStrokeMeta(recordingId: s.recordingId, recordingOffsetMs: offset)`, 아니면 빈 메타. `statusStream` 구독 값(마이크 버튼 표시용)은 쓰지 않는다 — 스트림 값은 한 이벤트 늦을 수 있다.
- **R-2**: EDITOR는 시간 차를 계산하지 않는다. `createdAt`과 녹음 시작 시각의 차를 어디서도 쓰지 않는다.
- **R-4**: 강조 계산은 INK(`setPlaybackFocus`)가 한다. EDITOR는 위치만 넘긴다.
- **R-5**: 탭 재생 = `seekMs(max(0, offset − preRollMs))` 후 `play()`. `preRollMs`는 `editorPreRollMsProvider`(키 `editor.playback.preRollMs` — 6.18·6.19). (v2.1) 가로채는 조건은 **탭 재생 상태**뿐이다 — `tapToSeek` 켬 + `recorder.status.phase == idle` + ① 손가락 한 번 탭: 패널 열림(`editorPanelProvider`) 또는 재생기 `playing`·`paused` ② 펜 점 탭(≤ 4 px·≤ 200 ms): 재생기 `playing`·`paused`만. 판정은 `StrokeSession.end()` 전, 가로채면 `cancel()`(6.3.5). 재생 강조 초점도 R-5의 '활성' 규칙을 따른다(6.15.2). 녹음 중에는 가로채지 않으므로 CP-PDF-10(녹음 중 `play()` 무시)과 겹쳐 '소리 없이 점만 사라짐'이 생기지 않는다.
- **R-6·R-7**: 붙여넣기·복제된 획은 INK·CORE가 연결을 유지한다. EDITOR는 `recordingId`가 가리키는 녹음이 노트 녹음 목록에 없으면 탭 재생 대상에서 뺀다(`hitTestRecorded(recordingId: 지금 열린 녹음)`이 거른다).
- **R-8**: 녹음 시작·정지·이름·삭제는 패널(media)이 한다. EDITOR의 되돌리기와 섞이지 않는다.

#### 5.1.4 이미지 가져오기 타입 (7.2.6)

`// 계약 v2.1 7.2.6 원문 (EDITOR가 쓰는 앞부분)`

```dart
enum ImageImportSource { photos, camera, files, clipboard }

@immutable
final class ImportedImage {
  const ImportedImage({required this.asset, required this.pixelWidth, required this.pixelHeight});
  final Asset asset;                             // AssetType.image, already in AssetStore
  final int pixelWidth, pixelHeight;
}

abstract final class ImageImportLimits {
  static const int maxLongSidePx = 2048;         // larger photos are downscaled (media_io)
  static const int maxBytes = 8 * 1024 * 1024;   // after re-encoding
  static const Set<String> storedMimeTypes = {'image/jpeg', 'image/png'};   // HEIC/WebP/GIF converted
}
```

- EDITOR는 `ImportedImage.asset.id`·`pixelWidth`·`pixelHeight`만 읽는다. 이미지 바이트·디코드·`ImageImportLimits` 검사는 media(M-3)와 INK(`InkImageCache`)의 일이다.
- 붙여넣은 `ImageObject`는 원래 `assetId`를 그대로 참조한다(같은 에셋 — 노트가 달라도 `AssetStore`는 하나).

#### 5.1.5 시험 도우미 (7.6 '기반 단계 시험 도우미')

`// 계약 v2.1 7.6 원문 (기반 단계 시험 도우미 블록의 앞부분 — note_core/testing.dart · testing_web.dart · ink_engine/testing.dart. 뒤의 ink_recognition·media_io 부분은 EDITOR가 쓰지 않아 생략)`

```dart
// package:note_core/testing.dart — v2.0 additions (web-safe, test/ only)
/// v1.4 signature unchanged. v2.0 behaviour: page objects (AddObjects / UpdateObjects /
/// RemoveElements / TransformElements / ClearPage.includeObjects / PageDraft.objects), recordings
/// (RecordingRepository), recording drafts (memory), handwriting (HandwritingRepository, (v2.1)
/// incl. update / notesWithStalePages) and a memory SearchIndex that applies (v2.1, CP-14) the
/// SAME judgement, candidate order and ranking code as the real FTS index — results AND order
/// equal the real store for the 7.7 V10 query set. openTestNoteStore (testing_vm.dart) is the
/// real CORE v2.
NoteStore createFakeNoteStore({/* v1.4 args */});
abstract final class PageObjectFixtures {
  static ShapeObject shape({required String pageId, ShapeKind kind = ShapeKind.rectangle,
      PageRect rect = const PageRect(100, 100, 300, 220), int createdAt = 1, String? id});
  static TextBoxObject textBox({required String pageId, String text = '안녕 hello',
      PageRect rect = const PageRect(100, 300, 400, 340), int createdAt = 1, String? id});
  static ImageObject image({required String pageId, required AssetId assetId,
      PageRect rect = const PageRect(100, 400, 300, 550), int pixelWidth = 400,
      int pixelHeight = 300, int createdAt = 1, String? id});
  static MathObject math({required String pageId, String latex = r'\frac{a}{b}',
      PageRect rect = const PageRect(100, 600, 200, 650), int createdAt = 1, String? id});
  static UnknownObject unknown({required String pageId, String type = 'sticker',
      PageRect rect = const PageRect(400, 100, 450, 150), String? id});
}
/// Controllable recorder: no real time, no plugin. stop() writes Asset(audio, 'audio/mp4',
/// silent bytes) then Recording (M-1) into [store]. (v2.1) start() with support != supported
/// throws UnsupportedError (as the real recorder); recording writes drafts to
/// store.recordingDrafts; pendingDrafts() follows the 7.2.4 exclusion rule. With the real
/// in-memory CORE inside testWidgets, asset writes go through idb_shim timers — pump / runAsync.
final class FakeAudioRecorder implements AudioRecorderService {
  FakeAudioRecorder({required NoteStore store, AudioSupport support = AudioSupport.supported});
  void advance(Duration elapsed);        // recorder clock; offsetNowMs() follows (pauses excluded)
  void interrupt();                      // system / hidden-tab pause → interrupted = true
  int stopDurationErrorMs = 0;           // durationMs = clock + this (R-3)
  /// (v2.1, CP-8) Closed tab / killed app: in-memory state dropped, phase idle, the draft written
  /// so far stays for pendingDrafts() / recoverDraft() of a new recorder (V16 shape).
  Future<void> abandon();
}
final class FakeAudioPlayback implements AudioPlaybackService {
  FakeAudioPlayback();
  void setPositionMs(int positionMs);    // positionMs() returns it; seekMs() also sets it
  /// (v2.1, CP-8) Calls in order: 'open:<recordingId>', 'play', 'pause', 'seek:<ms>', 'speed:<x>', 'close'.
  List<String> get calls;
}

// package:note_core/testing_web.dart — (v2.1) browser tests only (test/web/, Chrome)
/// The REAL web store (IndexedDB + drift web worker) under a unique [name]; needs the files of
/// CORE's tool/prepare_web_test.dart. For PDF V8 / V16 / V11 and CORE's own browser tests.
Future<NoteStore> openWebTestNoteStore(String name);
Future<void> deleteWebTestNoteStore(String name);

// package:ink_engine/testing.dart — (v2.1) contract additions (INK 4.12 is the full list:
// createTestPageController(shapeFitter:), FakeInkShapeFitter, SyntheticInk.loopThenHold /
// pageContentWith, loadKatexFontsForTest (VM), debugSetInkFontSource, testPngBytes)
/// Installs the small bundled test font (base64 Hangul + Latin subset) as the InkFonts source.
/// Every Chrome test that touches InkFonts / InkTextLayout (EDITOR, LIBRARY, PDF, INFRA) calls it
/// in setUpAll. Web safe.
Future<void> useInkTestFonts();
/// Hand-built vector export values (PDF tests before INK T42). Each factory takes every public
/// field of its value type as a named argument with the same name and type.
abstract final class InkVectorFixtures {
  static InkPageVectors pageVectors({/* highlighterGroups, inkShapes, underlay, annotations, cover, bounds */});
  static InkFillShape fillShape({/* strokeId, tool, path, colorArgb, opacity, objectId */});
  static InkHighlighterGroup highlighterGroup({/* … */});
  static InkHighlighterLine highlighterLine({/* … */});
  static InkImageVector imageVector({/* assetId, frame, pixelWidth, pixelHeight */});
  static InkTextVector textVector({/* object, lines */});
  static InkTextLine textLine({/* text, x, baselineY, width */});
  static InkMathVector mathVector({/* object */});
}
```

- EDITOR 시험은 위 가짜만 쓴다(플러그인 채널을 건드리지 않음 — 7.4.6). (v2.1) CORE CP-8이 승인되어 탭 재생 시험의 `seekMs`·`play` 호출 순서는 `FakeAudioPlayback.calls`(`['open:<id>', 'seek:<ms>', 'play']`)로 단언한다 — 초안의 EDITOR 감싸개(`test/helpers/recording_playback.dart`)는 만들지 않는다. 가짜 녹음기를 `testWidgets` 안에서 실제 메모리 CORE와 쓸 때의 에셋 쓰기 타이머는 주석대로 `pump`·`runAsync`로 넘긴다.
- (v2.1, C21-26) `InkFonts`·`InkTextLayout`을 건드리는 **Chrome 시험**(`test/web/` 전부 — 텍스트 상자·도형이 페이지에 있으면 썸네일·렌더가 글꼴을 부른다)은 `setUpAll(useInkTestFonts)`로 시작한다(`flutter test --platform chrome`에서 `rootBundle.load`가 응답하지 않음). VM 시험은 INK 기본 글꼴 적재 그대로다. 자동 도형 시험은 `FakeInkShapeFitter`·`SyntheticInk.loopThenHold`(INK 4.12)를 쓴다(5.2.4·E2-15·E2-21b).

#### 5.1.6 CORE에 기대하는 동작

| # | 보장 | EDITOR가 기대는 곳 |
|---|---|---|
| C-11 | `TransformElements`는 획과 객체를 한 커밋으로. `UpdateObjects`는 값이 바뀐 키만 새 필드 버전 | 혼합 선택 이동·회전 1단계, 스타일 변경 |
| C-12 | `UnknownObject` 키 보존 | 복사·붙여넣기 |
| 1차 N-1~N-7 | 세션 실행·스트림 규칙 | 모든 명령은 1차 `_run`/`_runAsync`(N-2: 리스너 안 `execute` 금지) |
| 7.2.3 | `UpdateObjects`의 `UnknownObject`·없는 id → 변경 전 `ArgumentError` | 핸들·텍스트 편집 중 원격 삭제 — EDITOR는 `UpdateObjects`를 보내기 **전에** `session.pageIfLoaded(pageId)?.objectById(id) == null`을 동기로 검사해 '원본 사라짐'을 명령 없이 처리한다(검토 S-1 — 1차 `_run`의 `default:` 갈래가 `ArgumentError`를 '실행하지 못했어요' + 보고로 처리하므로 [확인 `commands/editor_commands.dart` 608–635]). 검사와 실행 사이에 지워지는 경합만 `_run`의 1차 처리로 간다 — 6.6.7·6.21 |

### 5.2 INK (`package:ink_engine/ink_engine.dart`, X25)

#### 5.2.1 사용하는 정의 (7.2.9)

`// 계약 v2.1 7.2.9 원문 (펜 extras · 층 · 객체 렌더 · 선택 · 편집 · 글꼴/텍스트 배치 — 배경·벡터 내보내기는 EDITOR가 쓰지 않아 생략. 마지막 코드 블록은 원문 '배경 · 벡터 · 수식 · 글꼴' 블록의 뒷부분)`

```dart
// --- style extras keys (INK owns; CORE stores in StrokeStyle.extras) — 추가 ---
abstract final class InkStyleExtras {
  static const String highlighterStraightening = 'hlStraight';   // v1.4
  static const String nibAngleDeg = 'nibAngleDeg';     // calligraphy, [0, 180), default 45
  static const String nibAspect = 'nibAspect';         // calligraphy, minor/major (0.1..1], default 0.25
  static const String followBarrelRoll = 'rollNib';    // calligraphy, bool, default true (native Pencil Pro)
  static const String dash = 'dash';                   // dashed, [on, off, …] × width, default [4, 3]
  static const String laserFadeMs = 'laserFadeMs';     // laser, [300, 5000], default 1500
  static const String tapeStyle = 'tapeStyle';         // tape, 'solid' | 'striped', default 'solid'
}
enum InkTapeStyle { solid, striped }
extension StrokeStyleInk on core.StrokeStyle {
  /* v1.4: profile, previewRadius, highlighterStraightening, withHighlighterStraightening */
  double get nibAngleDeg; double get nibAspect; bool get followBarrelRoll;
  List<double> get dashPattern; int get laserFadeMs; InkTapeStyle get tapeStyle;
  core.StrokeStyle withInkExtras({double? nibAngleDeg, double? nibAspect, bool? followBarrelRoll,
      List<double>? dashPattern, int? laserFadeMs, InkTapeStyle? tapeStyle});
}
// PenProfile.of (v2.0): brush → filledOutline (high pressure gain, long taper);
// calligraphy → nibOutline; dashed → dashedPolyline (round caps); laser → transientTrail;
// tape → filledOutline, square cap, layer cover.
enum InkRenderMethod { filledOutline, strokedPolyline, nibOutline, dashedPolyline, transientTrail }  // 깨짐(값 추가)
enum InkLayer { highlighter, ink, cover }                                                             // 깨짐(값 추가)
enum InkRenderLayer { background, underlay, highlighterBase, highlighterActive, inkBase, inkActive,
  annotation, cover, overlay }                                                                        // 깨짐(값 추가)
```

`StrokeStyle.defaultsFor`(CORE)의 P1 5종 값은 v1.4 값을 유지하고 extras 기본값만 위 표로 채운다(색·굵기 조정은 INK가 렌더를 확정한 뒤 CORE에 변경 요청). 모든 새 펜은 1차 K-1(`Stroke.bounds` 공식)을 지킨다: 캘리그래피 펜촉 반길이 = `width·f/2` = `2·width·widthQ`, 테이프 사각 캡 0.7071·w ≤ 0.75·w, 점선 원형 캡.

**층 규칙 L-1** (아래에서 위로, 조사 01 R3 + PLAN 7.3):

| 순서 | 층 | 내용 | 층 안의 순서 |
|---|---|---|---|
| 1 | background | 종이·속지·PDF·이미지 배경 | — |
| 2 | underlay | `ImageObject` | `compareOrder` |
| 3 | highlighter | 형광펜 획 | `compareOrder` (v1.4) |
| 4 | ink | 일반 획 + `ShapeObject` | `compareOrder` — 도형과 획이 섞인다 |
| 4′ | (v2.1) ink 위 살아 있는 표시(`inkActive` 끝 — 기본 그림·타일과 무관하게 매 paint) | 재생 흐림·강조(K-7), 자동 도형 보정 미리보기 | — |
| 5 | annotation | `TextBoxObject`, `MathObject`, `UnknownObject` 자리표시 | `compareOrder` |
| 6 | cover | 암기 테이프 획(드러낸 것은 테두리만) | `compareOrder` |
| 7 | overlay | 선택 표시, 올가미, 레이저 자취. (v2.1) 재생 강조·도형 보정 미리보기는 4′로 옮겼다 — overlay에 두면 테이프·텍스트 위에 획 모양이 드러난다 | — |

```dart
// --- content: 추가 ---
final class InkPageContent {
  factory InkPageContent.fromCore({required core.Page page, required List<core.Stroke> strokes,
      List<core.PageObject> objects = const [], required int revision});
  List<core.PageObject> get objects;
}

// --- page controller: 추가 ---
final class InkPageController extends ChangeNotifier {
  /* v1.4 */
  /// ids may mix strokes and objects; unknown ids ignored.
  InkSelection select(Set<String> elementIds);
  /// Topmost object at the point (annotation → ink → underlay); UnknownObject included.
  core.PageObject? hitTestObject(Offset pagePoint, {double tolerance = 4.0});
  /// Not drawn (e.g. the text box under EDITOR's EditableText). Selection still sees them.
  void setHiddenObjectIds(Set<String> ids);
  /// Transient objects drawn with the same renderer (shape tool drag, vertex drag, image being
  /// placed). An entry whose id equals a committed object REPLACES it on screen; the others are
  /// drawn in their L-1 layer. (v2.1) A preview is drawn even when its id is hidden (preview wins
  /// over setHiddenObjectIds). Empty list = none. Never stored, never exported.
  void setPreviewObjects(List<core.PageObject> objects);
  // (v2.1) read-only views of what was set (EDITOR tests observe their own calls — EDITOR M-1)
  Set<String> get hiddenObjectIds;
  List<core.PageObject> get previewObjects;
  InkPlaybackFocus? get playbackFocus;
  // playback (M6)
  void setPlaybackFocus(InkPlaybackFocus? focus);           // null = off (K-7)
  InkStroke? hitTestRecorded(Offset pagePoint, {String? recordingId, double tolerance = 8.0});
  // memorization tape (state per controller, never stored — U10)
  InkStroke? hitTestTape(Offset pagePoint);
  bool isTapeRevealed(String strokeId);
  void toggleTape(String strokeId);
  /// Applies to the tapes present now; tapes that arrive later start covered. (v2.1) EDITOR keeps
  /// the note-level 'show all' and re-applies it after every updateContent. Lifetime = controller.
  void setAllTapesRevealed(bool revealed);
}
@immutable
final class InkPlaybackFocus {
  const InkPlaybackFocus({required this.recordingId, required this.positionMs,
      this.style = InkPlaybackStyle.dimUnwritten, this.recentWindowMs = 2000});
  final String recordingId;
  final int positionMs;                          // audio timeline, same scale as Stroke.recordingOffsetMs
  final InkPlaybackStyle style;
  /// Strokes that started in (positionMs − recentWindowMs, positionMs] get the emphasis outline
  /// (both styles). dimUnwritten also draws unwritten ink-layer strokes at
  /// InkTuning.playbackDimOpacity ((v2.1, CP-INK-8) highlighter / tape strokes are not dimmed —
  /// emphasis outline only). Drawn in layer 4′, never over annotation / cover (K-9).
  /// Strokes of other recordings / without a recording: unchanged.
  final int recentWindowMs;
}
enum InkPlaybackStyle { dimUnwritten, highlightRecent }

// beginStroke (v1.4) + shapeAssist — 추가
StrokeSession beginStroke(InkSample first, {required core.StrokeStyle style,
    required double viewScale, InkStrokeMeta meta = const InkStrokeMeta(),
    ShapeAssist shapeAssist = ShapeAssist.off});
enum ShapeAssist { off, holdToSnap }
// StrokeSession — 추가: after the pen holds still ≥ InkTuning.shapeHoldMs (500) within
// InkTuning.shapeHoldRadiusPx (8 logical px) the session asks inkShapeFitterProvider; a fit
// shows in layer 4′ (v2.1); moving again cancels it; end() then yields InkEdit(addShape).
final class StrokeSession implements InkGestureSession {   // (v2.1 정정) final as in v1.4 — no outside implementations
  /* v1.4 */
  ValueListenable<InkShapeFit?> get shapePreview;
  ShapeAssist get shapeAssist;                   // (v2.1) what beginStroke received
}
// laser: StrokeSession.end() returns null (no InkEdit, E-3); the trail fades over laserFadeMs.

/// (v2.0) Shape recognition port. INK detects the hold; the fitter decides.
abstract interface class InkShapeFitter {
  /// Centerline points of the stroke so far (page pt). null = not a shape (keep the stroke).
  InkShapeFit? fit(List<Offset> points, {required double viewScale});
}
@immutable
final class InkShapeFit {
  const InkShapeFit({required this.kind, required this.geometry, required this.score});
  final core.ShapeKind kind; final core.ShapeGeometry geometry; final double score;   // score [0,1]
}
final class NoShapeFitter implements InkShapeFitter { const NoShapeFitter(); }
/// Overridden ONLY through ink_recognition's recognitionOverrides() (7.3.3).
final inkShapeFitterProvider = Provider<InkShapeFitter>((ref) => const NoShapeFitter(),
    name: 'inkShapeFitterProvider');

// --- selection / lasso / eraser / edit: 추가 ---
final class InkSelection {
  /* v1.4: strokeIds, strokes, bounds, previewTransform, setPreviewTransform, commitTransform,
     delete, duplicate, recolor — now also cover objects (recolor: shape stroke color, text and
     math color; images unchanged) */
  Set<String> get objectIds;
  Set<String> get allIds;
  List<core.PageObject> get objects;
}
final class LassoOptions { /* v1.4 */ final bool includeObjects; }   // default true: object center inside → selected
final class EraserSpec { /* v1.4 */ final bool eraseShapes; }        // default true: touching a shape removes it whole
enum InkEditKind { addStroke, eraseStrokes, splitStrokes, transformStrokes, recolorStrokes,
  deleteStrokes, duplicateStrokes, addShape }                          // 깨짐(값 추가)
final class InkEdit {
  /* v1.4 */
  final List<core.PageObject> addedObjects;     // addShape, duplicateStrokes
  final List<core.PageObject> updatedObjects;   // recolorStrokes on objects
  /// (v2.1, INK C-3) Which of removedIds are objects — public optional constructor argument
  /// (default const {}); removedIds keeps every removed id; part of ==. A public-constructed
  /// eraseStrokes with a shape id therefore removes the shape instead of being ignored.
  final Set<String> removedObjectIds;
}
```

| `InkEditKind` | `toCommand()` (v2.0) |
|---|---|
| `addShape` | `core.AddObjects(pageId: …, objects: addedObjects)` |
| `eraseStrokes`, `deleteStrokes` | (v2.1) `removedObjectIds`가 비면 `core.RemoveStrokes`(v1.4), 아니면 `core.RemoveElements(elementIds: removedIds)` |
| `splitStrokes` | (v2.1, CP-INK-2) `removedObjectIds`가 비면 v1.4(`SplitStrokes`), 아니면 `core.CompositeCommand([SplitStrokes(획 조각) 또는 RemoveStrokes, RemoveElements(removedObjectIds)])`(빈 쪽은 뺌) — 한 제스처 = 한 명령 |
| `transformStrokes` | `core.TransformElements`(획 + 객체 — 이름은 v1.4 유지) |
| `recolorStrokes` | `core.CompositeCommand([RestyleStrokes, UpdateObjects])`(빈 쪽은 뺌) |
| `duplicateStrokes` | `core.CompositeCommand([AddStrokes, AddObjects])`(빈 쪽은 뺌) |
| 그 밖 | v1.4 |

```dart
// --- math, fonts, text layout: 추가 ---
abstract final class InkMathRenderer {
  /// null = renderable; else a short English error (unknown command …) for the LaTeX editor.
  static String? validate(String latex);
  static InkMathLayout? layout(String latex, {required double fontSizePt});   // size in pt
  /// Offscreen raster (thumbnails, PDF at 300 dpi, screen cache buckets). Web (CanvasKit) safe.
  /// (v2.1) Waits for asynchronously loaded glyph pictures (\sqrt, stretchy arrows / braces —
  /// flutter_svg) before capturing, bounded in count and time; returns null rather than an
  /// incomplete image. Requests are served one at a time. Output ≤ 4 Mpx (7.4.5): pixelsPerPt is
  /// lowered to fit.
  static Future<ui.Image?> rasterize(String latex, {required int colorArgb,
      required double fontSizePt, required double pixelsPerPt});
}
@immutable final class InkMathLayout { final Size sizePt; final double baselinePt; }
/// flutter_math_fork Math.tex with explicit textStyle (fontSize, color) — never SelectableMath.
class MathPreview extends StatelessWidget {
  const MathPreview({super.key, required this.latex, required this.fontSize, required this.color,
      this.onError});
}
abstract final class InkFonts {
  static const String noteSans = 'NoteSans';    // text boxes; packages/ink_engine/assets/fonts/
  static Future<void> ensureLoaded();           // lazy FontLoader — not in FontManifest (no startup download)
  static Future<Uint8List> noteSansBytes({bool bold = false});   // PDF embedding
  // (v2.1) both fail after InkTuning.fontLoadTimeoutMs (5 s) instead of waiting forever;
  // Chrome tests use useInkTestFonts() (7.6 — rootBundle does not answer there)
  static bool covers(String text);              // every char in the bundled subset?
}
abstract final class InkTextLayout {
  /// Height EDITOR writes into TextBoxObject.frame for the given width (same metrics INK paints with).
  static Future<Size> measure(String text, core.TextBoxStyle style, {required double widthPt});
  /// (v2.1) Same value as measure once InkFonts is loaded; null before (EDITOR live drafts).
  static Size? measureSync(String text, core.TextBoxStyle style, {required double widthPt});
  /// (v2.1, CP-INK-3) The paragraph style INK paints with. EDITOR's text editor uses exactly these
  /// with zero inner padding, so the text does not jump when the session ends (E-6).
  static TextStyle textStyleOf(core.TextBoxStyle style);
  static StrutStyle strutStyleOf(core.TextBoxStyle style);   // forceStrutHeight: true, height = lineHeight
  /// (v2.1, CP-PDF-7) Frame-size raster on a transparent background (box background not drawn),
  /// same 4 Mpx cap as InkMathRenderer.rasterize — PDF raster fallback.
  static Future<ui.Image?> rasterize(core.TextBoxObject object, {required double pixelsPerPt});
}
```

- 썸네일(`InkPageThumbnailRenderer`): 이미지 배경·객체를 합성한다. 이미지·글꼴·수식이 2초 안에 준비되지 않으면 `null`(1차 규칙: 호출자는 캐시하지 않고 다시 시도). (v2.1, CP-INK-6) 썸네일 렌더러·`InkPageThumbnail`·컨트롤러는 배경 빌더 목록의 첫 `ImageBackgroundLayerBuilder.images`를 이미지 객체 캐시로 쓴다(목록에 없으면 자리표시 — `pdfIoOverrides()`가 기본 목록을 유지해야 하는 이유). `inkImageCacheProvider`·`defaultPageBackgroundBuilders`는 `core.assetStoreProvider`를 지연으로 읽는다. 텍스트 상자 페이지의 썸네일도 `NoteSans` 적재를 일으킨다(7.4.5 '처음 그릴 때'에 썸네일 포함).
- 웹 캘리그래피: 방위각이 항상 0이므로 `nibAngleDeg` 고정 각만 쓴다. 네이티브 iPad에서 `followBarrelRoll`이 켜져 있고 Pencil Pro 롤(7.2.10 `StylusBarrelRoll`)이 오면, EDITOR가 **펜 다운 순간의 롤 값**을 그 획 스타일의 `nibAngleDeg`에 더해 넘긴다. 획마다 고정 각이 되어 다시 열어도 같은 모양으로 그려지고, 점 코덱 v1(점별 롤 채널 없음)을 바꾸지 않는다(조사 02 9.3 '최근 롤 값 근사').
- (v2.1, CP-INK-7) 레이저 자취 색은 `InkTuning.laserArgb` 고정이고 `StrokeStyle.colorArgb`를 쓰지 않는다(EDITOR 펜 선택기는 레이저 색을 숨김).
- (v2.1, CP-INK-11) 계약이 INK에 맡긴 세부(`InkTuning` 상수, `testing.dart` v2, `MathPreview.onError`의 형 `ValueChanged<String>?`, `InkImageCache` 멤버)는 03-ink 4.10·4.12가 단일 출처다.
- (v2.1) 미리보기·대기 표시의 객체 변형은 CORE `PageObject.transformed(m, scaleWidth:)`를 그대로 쓴다(7.2.2 — 해석기와 같은 함수라 미리보기 = 커밋).

#### 5.2.2 호출 규약 v2 (1차 계획서 5.2.2에 더함)

| # | 규약 | 근거 |
|---|---|---|
| I-1 | 페이지 마운트는 `InkPageContent.fromCore(page:, strokes:, objects: c.objects, revision:)`로 넘긴다 | 7.2.9 |
| I-2 | 텍스트 편집 중 숨길 id는 EDITOR 상태 `TextEditState`가 정한다(순수 함수 `hiddenIdsOf(state)` — 기존 상자는 방식과 무관하게 `{boxId}`(E-6 문장 그대로), 새 상자는 `{}`. `sheet` 방식은 여기에 같은 id 미리보기를 더한다 — 미리보기 > 숨김, v2.1). 그 값을 편집 중인 페이지 컨트롤러에 `setHiddenObjectIds`로 넣고, 끝나면 `{}`(명령이 반영된 직후 같은 프레임) | E-6, 검토 M-1 |
| I-3 | 도형 끌기·꼭짓점·변 핸들·텍스트 폭 끌기·시트 방식 초안의 미리보기는 `setPreviewObjects([…])`로만 그린다(EDITOR가 객체를 따로 그리지 않음 — B P4). 같은 id 항목은 커밋된 객체를 화면에서 대신하고, (v2.1) **숨김보다 우선**한다(같은 id를 숨겨도 미리보기는 보임). 사본의 변형은 CORE `PageObject.transformed`(CD2-07). 끝·취소에 `setPreviewObjects(const [])`. 빈 곳 끌기의 **새 텍스트 상자 테두리**는 객체가 아니므로 EDITOR overlay가 직접 그린다(INK 변경 없음 — 00-review 2.3) | 7.2.9 (v2.1) |
| I-4 | 선택은 `select(elementIds)`(획·객체 섞음), 올가미 결과는 `InkSelection.allIds`를 쓴다 | 7.2.9 |
| I-5 | 이동·비율 유지 크기·회전은 `InkSelection.setPreviewTransform` → `commitTransform()`, 색은 `recolor`, 삭제는 `delete`, 복제는 `duplicate` — 모두 `EditorCommands.commitInkEdit`(1차 실패 처리 `discardEdit` 그대로) | 1차 7.2.15 + 7.2.9 |
| I-6 | 회전 각도 맞춤은 `ink.SelectionGeometry.snapAngle`(15°, ±3° — 기본 인자 그대로), 회전 행렬은 `SelectionGeometry.rotate(bounds:, radians:)`(다중 선택) 또는 `core.Affine2.rotation(θ, originX: frame.center.x, originY: …)`(단일 객체 — 프레임 중심). 단일 객체의 모서리(비율 유지) 크기 조절 행렬은 `ObjectResize.cornerScale(frame, corner, delta)`(회전된 반대 모서리 고정 — 6.6.5), 다중 선택은 `SelectionGeometry.resize(keepAspect: true)`(축 정렬 프레임) | INK 1차 공개 API, 검토 S-2 |
| I-7 | 펜 다운: `beginStroke(first, style:, viewScale:, meta: 녹음 메타, shapeAssist: 설정·펜 종류에 따라)` | 7.2.9, E-5 |
| I-8 | 레이저 `StrokeSession.end()`가 `null`이면 커밋하지 않는다(정상 — K-9). 최근 색에도 넣지 않는다 | K-9 |
| I-9 | 재생 강조는 마운트된 모든 컨트롤러에 같은 `InkPlaybackFocus`를 매 프레임 넣는다(K-7이 허용). 새로 마운트되는 페이지에도 지금 값을 넣는다. (v2.1 R-5) 초점은 그 녹음이 **활성**(열린 뒤 `playing`이었거나 `seekMs` 뒤)일 때만 넣고, 그 전에는 `null`(6.15.2) | K-7, R-5 |
| I-10 | 테이프 탭은 `hitTestTape(pagePoint)` → `toggleTape(id)`. '모두 보이기/가리기'는 노트 단위 상태(`editorTapesRevealedAllProvider`)를 두고 마운트된 모든 컨트롤러에 `setAllTapesRevealed`, 새로 마운트되는 페이지와 (v2.1) **그 컨트롤러의 `updateContent` 뒤마다** 다시 넣는다(INK 의미 그대로 — 나중에 들어온 테이프는 가려진 채로 오므로). 낱개 토글은 컨트롤러 수명이라 페이지가 마운트에서 빠지면 다시 가려진다 — 받아들인다(6.14.4) | 7.2.9 (v2.1), U10 |
| I-11 | 탭 재생 적중은 `hitTestRecorded(pagePoint, recordingId: 열린 녹음, tolerance: 12 / camera.scale)`(손가락 크기를 생각해 화면 12 px) | 7.2.9 |
| I-12 | 객체 탭 선택은 `hitTestObject(pagePoint, tolerance: 6 / camera.scale)` | 7.2.9 |
| I-13 | 텍스트 높이: 세션 끝에 `InkTextLayout.measure(text, style, widthPt:)`의 높이를 frame에 쓴다. 편집 중·시트 미리보기의 실시간 높이는 (v2.1) `measureSync`(글꼴 적재 전 `null` → 편집기 렌더 높이). 편집기 글자 모양은 (v2.1, CP-INK-3) `InkTextLayout.textStyleOf(style)`·`strutStyleOf(style)` + 안쪽 여백 0(6.11.3). 글꼴은 `InkFonts.ensureLoaded()` 뒤 `InkFonts.noteSans`(실패는 5 s 상한 — v2.1) | 7.2.9 (v2.1), 7.4.5 |
| I-14 | EDITOR는 `setViewport`·`discardPending`을 부르지 않는다(1차 6.16 ⑤ 그대로) | 1차 7.2.15 |
| I-15 | (v2.1) 읽기 getter `hiddenObjectIds`·`previewObjects`·`playbackFocus`·`StrokeSession.shapeAssist`는 **시험에서만** 읽는다. `lib/`는 자기 상태(`TextEditState`·`PlaybackHighlightLogic`·`shapeAssistFor` 결과)를 원본으로 두고 INK에서 되읽지 않는다 — 시험은 EDITOR 결정(자기 이음새)과 INK에 넘긴 값(getter)을 따로 단언한다 | 7.2.9 (v2.1), 검토 M-1 |

#### 5.2.3 INK에 기대하는 동작

| # | 보장 | EDITOR 쪽 영향 |
|---|---|---|
| K-6 | 객체 렌더 외곽 ⊆ CORE `bounds` | 선택 프레임이 객체를 다 덮는다 |
| K-7 | `setPlaybackFocus` 매 프레임 호출 허용, 타일 재생성 없음 | 6.15.2 `Ticker` 설계 |
| K-8 | 화면·썸네일·내보내기 순서 = L-1 | 텍스트 편집기 오버레이·빈 곳 끌기 상자 테두리·선택 프레임만 EDITOR가 위에 그림 |
| K-9 | 레이저 `InkEdit` 없음, 테이프 상태 저장 안 함, (v2.1) 재생 흐림·강조와 도형 보정 미리보기는 층 4′(가린 테이프·텍스트·수식 픽셀을 바꾸지 않음) | 6.14.3·6.14.4·6.15.2 — EDITOR는 초점 값만 넘김 |
| (규칙) | `InkSelection.recolor`는 객체도 다룸(도형 테두리·텍스트·수식 색, 이미지 그대로) | 색 변경에 EDITOR 분기 없음 |
| (규칙) | `EraserSpec.eraseShapes` 기본 true | 지우개 패널 토글 기본값 |

#### 5.2.4 기반 단계 INK(R2-B3)로 되는 것 · 안 되는 것

R2-B3은 '단순하지만 동작하는 구현'이다(7.6.2 (v2.1) R2-B3 행, 03-ink 4.13 표). EDITOR 동시 개발은 그 위에서 아래처럼 시험한다. **INK 가짜는 없다** — `InkPageController`·`StrokeSession`은 `final class`라 밖에서 구현·상속할 수 없고(1차 `ink_page_controller.dart` 128, `sessions.dart` 195 [확인], 계약 v2.1 정정), 03-ink 5.6도 'EDITOR 시험은 실제 INK'다. 그래서 위젯 시험은 ① **EDITOR 이음새**(순수 함수·상태·출력 주입)로 EDITOR의 결정을 단언하고 ② 실제 컨트롤러의 **읽기 getter**(v2.1)로 INK에 넘긴 값을 확인하며 ③ CORE 결과(명령 수·`undoDepth`·내용)를 단언한다(검토 M-1, CD2-08).

| INK 기능 | R2-B3 (03-ink 4.13 · 7.6.2 v2.1) | EDITOR 시험 방법 |
|---|---|---|
| 객체 그리기(L-1 층 경계 상자 + 기본 그리기), `select`·`hitTestObject`(frame `contains`), `LassoOptions.includeObjects` | 동작 | 그대로 |
| `InkSelection.objectIds/allIds/objects`, 미리보기 변형·`commitTransform`·`delete`·`duplicate`·`recolor`의 객체 처리 | 동작(`toCommand` 최종) | 그대로 — CORE 결과 단언 |
| `InkEdit` v2·`toCommand`·`removedObjectIds` | **최종** | 그대로 — 부분 지우개 + 도형 합성 명령(`widget/erase_v2_test.dart`) |
| `EraserSpec.eraseShapes` | 지우개 원과 도형 `bounds` 겹침 → 통째로 | 그대로 |
| `setHiddenObjectIds`·`setPreviewObjects`(같은 id 대체, 미리보기 > 숨김) + getter `hiddenObjectIds`·`previewObjects` | 동작 | 결정은 `TextEditState`(`hiddenIdsOf`)·`ObjectEditInteraction`이 만든 사본으로, 넘긴 값은 getter로(`object_handles_test`·`text_box_test`·`text_input_sheet_test`·`shape_tool_test`) |
| `beginStroke(shapeAssist:)` + getter `StrokeSession.shapeAssist` | 받기만, `shapePreview`는 늘 `null`(→ `addShape`가 나오지 않음) | 결정은 순수 함수 `shapeAssistFor`(`unit/shape_assist_for_test.dart`), 넘긴 값은 세션 getter(`widget/shape_assist_test.dart`), 커밋 경로는 `ink_edit_builders`의 `InkEdit(addShape)` → `commitInkEdit`((수정 3회차) P-A E2-09 `widget/shape_tool_test.dart` — 5.1.2 매핑 행이 P-B E2-15에 묶이지 않게). 실제 멈춤 → `addShape`는 (수정 2회차) INK T39·E2-15가 둘 다 병합됐을 때만 통합 E2-21b(P-B)에서 `inkShapeFitterProvider`를 INK `FakeInkShapeFitter(fit: …)`로 바꾸고 `SyntheticInk.loopThenHold` 표본을 포인터로 몰아 확인(검토 S-4) |
| 레이저 `end() → null` | **동작**(K-9, C2-37을 R2-B3에 적용) — 사라지는 효과만 없음 | 실제 INK로 `widget/laser_test.dart`(동시 개발 중 — 가짜 세션 없음, 검토 S-4) |
| `setPlaybackFocus` + getter `playbackFocus` | 상태만 저장(그리기 없음) | 결정은 `PlaybackHighlightLogic`의 출력 주입(`unit/playback_highlight_logic_test.dart`), 넘긴 값은 마운트된 컨트롤러 getter(`widget/playback_highlight_test.dart`) |
| `hitTestRecorded` | 동작(1차 적중 + 녹음 id 거르기) | 그대로 — 탭 재생 시험 |
| 테이프 API | 드러냄 집합 동작, `hitTestTape`는 bounds, 그리기는 볼펜 | `isTapeRevealed`로 단언 |
| `InkTextLayout.measure`·`measureSync`·`textStyleOf`·`strutStyleOf`, `InkFonts` | **실제 동작**(글꼴 파일 포함) | 그대로. Chrome 시험은 `setUpAll(useInkTestFonts)`. 글자 골든은 하지 않는다(7.4.6 — Ahem만) |
| 재생 흐림·강조 그리기, 도형 보정 미리보기(층 4′), 새 펜 모양 | 없음 / 볼펜 프로필 | 화면 결과는 통합 E2-21(도형 보정은 P-B E2-21b)·실기기(B-4·B-6·B-8) |

### 5.3 media · recog · pencil — 자리 너머 (EDITOR는 import하지 않음 — 7.1 규칙 4·5)

| # | 제공 | 자리 | INFRA 변환 | EDITOR가 기대는 것 |
|---|---|---|---|---|
| X29 | media `supportedImageSources`·`importImageForNote` | `editorImageImporterProvider` | `EditorImageImporter(sources: supportedImageSources(), pick: importImageForNote)` | `pick`이 `null`이면 취소(안내 없음), 예외면 E-7. 돌려받은 에셋은 이미 `AssetStore`에 있음. (v2.1) EDITOR는 `pick`을 누름 처리 안에서 동기 시작하고 본문 context를 넘긴다 — media는 브라우저 선택기를 첫 `await` 전에 연다(7.2.10, CP-PDF-11 준비 중 시트). `FEATURE_MEDIA`와 무관하게 연결된다(D17) |
| X29 | media `RecordingPanel` | `EditorExtensions.recordingPanel` | `EditorPanelContext` → `RecordingPanel(noteId, tapToSeek, onTapToSeekChanged, onClose)` | 패널은 7.4.10 규칙(테마 색, 44×44, 자체 `Navigator.push` 없음). 높이는 EDITOR 자리가 40%로 막는다 |
| X30 | recog `recognitionSelectionActions`·`recognitionInsertActions` | `selectionMenuItems`·`insertMenuItems` | `RecognitionTarget` ↔ 문맥 1:1(X30 v2.1: 삽입 문맥의 `done` = 마지막 추가 객체 `selectObject`, 선택 문맥의 `done` = `clearSelection` — recog는 바꾸기 뒤에만 부름, CP13·CP-L3). recog `isVisible`은 가볍게(CP-L5), INFRA `insertMenuItemOf`는 `isVisible`을 버리므로 삽입 메뉴 항목은 늘 보인다 | 변환 창·패드는 `showModalBottomSheet`(50% 이하). 실패는 recog 자기 창에서(G-1) — EDITOR 스낵바는 예외가 새어 나올 때만 |
| X35 | `pencil_bridge` → `PencilStylusExtrasSource` | `stylusExtrasProvider` | 01-infra 6.12.3 표(문자열 → enum, 모르는 phase 이벤트 버림, 능력 조회 실패 시 더블탭만) | `events`가 오류를 흘리지 않음(01-infra 6.12.1). 웹·안드로이드는 `NoStylusExtras` |

### 5.4 INFRA

- 7.3.3 표의 EDITOR 행(`editorExtensionsProvider`·`editorImageImporterProvider`·`devOverlaySectionsProvider`·`stylusExtrasProvider`) override와 라우트 `?page=&focus=` → `EditorScreen(initialPageId:, initialFocusRectPt:)`.
- 설정 화면은 EDITOR 섹션 위젯 4개를 그대로 넣는다(1차). 제스처 편집 UI·녹음 재생 설정은 그 섹션 안에 있다(6.4.4·6.15.3) — INFRA 일 없음.
- V5·V6 앱 스모크가 쓰는 위젯 키는 부록 C(계약 아님 — 바꿀 때 INFRA에 알림).

### 5.5 동시 개발 중 가짜와 가정 (00-overview 4.3 표 EDITOR 행 구체화)

| 의존 | 개발 중 쓰는 것 | 위치 |
|---|---|---|
| CORE 모델·명령·세션 | `createFakeNoteStore()` v2, `PageObjectFixtures`(R2-B2) | `note_core/testing.dart` |
| CORE 오디오 포트 | `FakeAudioRecorder(store:)`(`advance`·`interrupt`·(v2.1) `abandon`)·`FakeAudioPlayback`(`setPositionMs`, (v2.1) `calls` — 호출 순서 단언) override | 같음 |
| INK | R2-B3 실제 INK(단순 구현 + (v2.1) 읽기 getter 4개 — 5.2.4). INK 가짜는 만들지 않는다(`final class`). `addShape` 커밋 경로는 `test/helpers/ink_edit_builders.dart`가 `ink.InkEdit(kind: ink.InkEditKind.addShape, pageId:, addedObjects: [PageObjectFixtures.shape(…)])`를 만든다. 자동 도형 흐름은 INK `FakeInkShapeFitter`·`SyntheticInk.loopThenHold`(통합 E2-21b — P-B, INK T39·E2-15가 둘 다 병합됐을 때만), Chrome 시험 글꼴은 `useInkTestFonts` | `ink_engine` + `ink_engine/testing.dart` + EDITOR test helper |
| 이미지 가져오기 | `FakeImageImporter(sources: {...}, next: ImportedImage?)` — `pick`이 가짜 저장소 `AssetStore.put(PNG 1×1, type: image)` 뒤 그 에셋으로 `ImportedImage`, `throwNext`로 예외 | `test/helpers/fake_image_importer.dart` |
| 선택·삽입 메뉴 항목 | 받은 문맥을 기록하고 `execute`로 명령 하나를 보내는 시험 항목(`RecordingSelectionItem`·`RecordingInsertItem`) | `test/helpers/fake_extensions.dart` |
| 녹음 패널 | `(context, panel) => _TestPanel(panel)` — 탭 재생 토글·닫기 버튼만 | 같음 |
| Pencil | `FakeStylusExtras(capabilities:)` — `StreamController.broadcast()`로 이벤트 주입 | `test/helpers/fake_stylus_extras.dart` |
| 실제 결합 | 통합 단계 E2-21(실제 INK + `openTestNoteStore()` + 가짜 오디오 포트)·(P-B) E2-21b, INFRA V5·V6 | `test/integration/` |

가정(기반 단계 뒤 실제 타입으로 바꿈 — 7.6 끝 문장): 없음. 초안의 'CP-1이 정해지기 전에는 위치 인자' 가정은 v2.1에서 이름 있는 인자로 정해져 지웠다(C21-07). (동시 개발 착수 2026-11-06, C22-09) 기반 단계 R2-B2·R2-B3 실제 타입으로 확인했다 — 위 표의 이음새는 모두 `note_core/testing.dart`·`ink_engine/testing.dart`에 있다. (v2.3, C23-07) `FakeInkShapeFitter`의 설정 필드는 `result`(생성자 인자는 `fit:` 그대로 — 시험은 `fitter.result = x`), `InkMathRenderer.layout`을 일반 `test()`에서 부르면 먼저 `TestWidgetsFlutterBinding.ensureInitialized()`.

---

## 6. 설계 상세

1차 계획서 6장의 구조(카메라·가상화·입력 분배·도구 상호작용·커밋 인계·되돌리기·툴바·페이지 패널·개발자 표시·상태 관리·저장 형식)는 그대로다. 아래는 **바뀌거나 더하는 것만** 적고, 절마다 이어받는 1차 계획서 절을 밝힌다.

### 6.1 구성도 (1차 계획서 6.1에 더함)

```text
EditorScreen(noteId, initialPageId, initialFocusRectPt)            ── per-note ProviderScope
└─ EditorRoot → EditorBody
   ├─ StylusExtrasListener (6.5)       stylusExtrasProvider.events ─┐
   ├─ PlaybackHighlightDriver (6.15.2) Ticker → PlaybackHighlightLogic → output │
   ├─ EditorToolbar v2 (6.13)  [펜][지우개][올가미][도형][텍스트] [+삽입] [마이크] …
   ├─ PresetBarView (1차)                                            │
   ├─ PageViewport (1차)                                             ▼
   │   ├─ Listener → InputRouter v2 (6.3) ── InputTargets ──► InteractionHost v2
   │   │        E-4 contact rule · gesture hints · tap intercept      │ beginInteraction(sample, source, gesture)
   │   │                                                              ├─ Pen / Erase / Lasso (1차, 확장)
   │   │                                                              ├─ ShapeInteraction (6.9)
   │   │                                                              ├─ TextToolInteraction (6.11)
   │   │                                                              ├─ SelectionTransform v2 (6.6) · ObjectEdit (6.6.5)
   │   │                                                              └─ EditorActionRunner (6.4.3) ◄── gestures / pencil
   │   ├─ EditorPageView × ≤8 → ink.InkPageView (INK draws objects, previews, tape, laser, playback focus)
   │   ├─ SelectionFrame v2 (rotated frame, rotation handle, object handles, vertices)
   │   ├─ NewTextBoxOutline (6.11.1 — EDITOR overlay while dragging a new box; not an INK preview)
   │   ├─ FocusFlash (6.16)
   │   │   (the Listener's page area is wrapped in TextFieldTapRegion(enabled: a text session is open) — 6.11.3)
   │   └─ siblings above the Listener (their touches never reach the router — 1차 page_viewport.dart):
   │       TextBoxEditorLayer (6.11 — material_ui TextField overlay) · TextFormatBar · SelectionMenu …
   ├─ SelectionMenu v2 · EditorContextMenu v2 · InsertMenu · RecolorPopup · format bars (PopupHost)
   └─ EditorPanelSlot (6.15.4) ── EditorExtensions.recordingPanel(context, EditorPanelContext)   ≤ 40% height

EditorCommands v2 (the only place that runs CORE commands) ── core.NoteSession
ExtensionRunner (E-7) ── selection / insert items, image importer, panel builder
```

- 데이터 흐름은 1차와 같다: 사용자 동작 → (INK 세션 → `InkEdit`) 또는 (EDITOR가 만든 객체) → `EditorCommands`가 명령 **하나** → CORE 세션 → `pageChanges` → `PageMount` → `controller.updateContent`(획 + 객체).
- 새 상태는 모두 노트 단위 scoped provider(6.19)에 두고, 포인터 이벤트 처리에서 provider 상태를 바꾸지 않는 1차 규칙(1차 계획서 6.13.1 #1)을 지킨다. 끌기 미리보기는 INK(`setPreviewTransform`·`setPreviewObjects`)가 그린다.

### 6.2 도구 모델 v2 (1차 계획서 6.6.1 확장)

#### 6.2.1 `EditorTool` · `ToolState`

```dart
// src/tools/tool_state.dart
/// (v2) Image insertion and math are actions of the insert menu, not modal tools.
enum EditorTool { pen, eraser, lasso, shape, text }

@immutable
class ToolState {
  const ToolState({required this.activeTool, required this.penType, required this.penStyles,
      this.previousTool, this.lastTool, this.lastPenType,
      this.eraser = const EraserSettings(), this.eyedropperActive = false});
  /* v1.4 fields: activeTool, previousTool (eraser return), penType, penStyles, eraser, eyedropperActive */
  /// (v2) The tool and pen type that were active before the last switch (any tool) —
  /// EditorAction.previousTool swaps (activeTool, penType) with these. Persisted (device).
  final EditorTool? lastTool;
  final core.PenTool? lastPenType;
  ToolState copyWith({/* v1.4 */, EditorTool? lastTool, core.PenTool? lastPenType,
      bool clearLast = false});
}
```

- `ToolController.selectTool(t)`·`selectPenType(p)`는 바뀌기 전 값(`activeTool`, `penType`)을 `lastTool`·`lastPenType`에 넣는다(같은 값으로 바뀌면 그대로). 1차 `previousTool`(지우개에서 돌아갈 도구) 규칙은 바꾸지 않는다.
- `swapWithLast()`(새): `lastTool == null`이면 아무것도 안 함. 아니면 (활성 도구, 펜 종류) ↔ (`lastTool`, `lastPenType ?? penType`). Apple '이전 도구로 전환'(`switchPrevious`)과 같은 의미다(12.2 Q7).
- 도구를 바꾸면 1차처럼 선택이 풀린다(올가미로 바꿀 때만 남음 — 1차 `EditorSelectionNotifier` 규칙을 새 도구에도). 2차 규칙: **텍스트 편집 세션이 열려 있으면 도구를 바꾸기 전에 세션을 끝낸다**(6.11.5 — 커밋 먼저).
- 읽기 전용 노트에서는 도형·텍스트 도구 버튼도 비활성(1차 펜·지우개·올가미와 같음).

#### 6.2.2 저장값 폴백 (7.4.10)

`editor.toolSelection`(device) 형식은 1차 + 두 필드: `{"v":1,"activeTool":"pen","penType":"ballpoint","previousTool":null,"lastTool":"lasso","lastPenType":"ballpoint"}`.

| 저장값 | 읽기 |
|---|---|
| `activeTool`이 모르는 이름(새 판의 도구, 예 `"ruler"`) | `pen`. **오류 보고하지 않는다**(예상된 앞으로 호환 — 1차 코드는 '잘못된 필드'로 보고했다 [확인 V4]) |
| `activeTool`이 문자열이 아님 | `pen` + 1차처럼 잘못된 필드 보고 1회 |
| `penType`·`lastPenType`이 모르는 `wireName` | `ballpoint` / `null`(보고 안 함) |
| `previousTool`·`lastTool`이 모르는 이름 | `null`(보고 안 함) |
| `activeTool`이 `shape`·`text`인데 노트가 읽기 전용 | 도구는 그대로 두고 입력만 막는다(1차와 같음) |

같은 규칙을 `editor.toolOptions`의 `shape.kind`에도 쓴다(모르는 `ShapeKind` → `rectangle`).

#### 6.2.3 임시 도구 (펜 버튼 · 지우개 끝)

- 임시 도구는 `ToolState`를 바꾸지 않는다. 라우터가 접촉 순간 정한 제스처(6.3.3)를 `beginInteraction(sample, source:, gesture:)`로 넘기고, 호스트가 그 접촉 하나에만 다른 상호작용을 만든다.
- `eraserWhileHeld` → `EraseInteraction`(현재 `ToolState.eraser` 설정, `returnToPreviousTool`은 쓰지 않음), `lassoWhileHeld` → `LassoInteraction`. 획 도중 버튼을 누르거나 떼도 그 접촉의 상호작용은 바뀌지 않는다(접촉 순간에 정함 — E-4).
- 임시 올가미로 만든 선택은 도구가 펜이어도 남고, **선택 우선 규칙**(6.6.2)으로 바로 옮기거나 돌릴 수 있다.
- 텍스트 편집 세션 중의 펜 버튼 접촉은 세션을 먼저 끝낸다(모든 펜 접촉과 같음 — 6.11.5).

#### 6.2.4 `ToolOptions` — 도형·텍스트 도구 기본값

```dart
// src/tools/tool_options.dart
@immutable
class ToolOptions {
  const ToolOptions({this.shapeKind = core.ShapeKind.rectangle,
      this.shapeStyle = const core.ShapeStyle(strokeColorArgb: 0xFF1A1A1A),
      this.polygonSides = 5, this.starPoints = 5,
      this.textStyle = const core.TextBoxStyle()});
  final core.ShapeKind shapeKind;
  final core.ShapeStyle shapeStyle;   // normalized; arrowHeads used by line / arrow only
  final int polygonSides;             // 3..12 (ShapeGeometry.regularPolygon)
  final int starPoints;               // 4..16 (2·points ≤ PageObjectLimits.maxPolylinePoints)
  final core.TextBoxStyle textStyle;  // normalized; the style of a new text box
  Map<String, Object?> toJson();      // {"v":1,"shape":{"kind":…,"style":ShapeStyle.toJson(),"sides":5,"points":5},"text":TextBoxStyle.toJson()}
  factory ToolOptions.fromJson(Map<String, Object?> json);   // invalid → defaults (6.2.2 rule)
}
/// Global (all notes), key editor.toolOptions (synced), 500 ms debounce — like ToolController.
final editorToolOptionsProvider = NotifierProvider<ToolOptionsNotifier, ToolOptions>(…);
```

- 화살표(`ShapeKind.arrow`)를 고르면 `arrowHeads`가 `none`일 때 `end`로 바꿔 쓴다(직선은 그대로). 화살촉은 직선·화살표에만 뜻이 있다(7.2.2 주석).
- 도형 테두리 기본색은 현재 펜 색이 아니라 도구 자체 값이다(도형과 필기를 다른 색으로 쓰는 경우가 많다). 도형 팝업에 '펜 색 쓰기' 단추를 둔다.
- 텍스트 서식 바에서 바꾼 서식은 그 상자와 `textStyle` 둘 다에 반영한다(다음 상자가 같은 서식으로 시작).

### 6.3 입력 v2 (1차 계획서 6.5 확장)

#### 6.3.1 바뀌는 점 한눈에

| 1차 | 2차 |
|---|---|
| 펜(스타일러스·마우스) `PointerDownEvent` = 즉시 상호작용 | 스타일러스는 **접촉 판정 규칙**(`StylusContactRule.native`/`.web`)을 거친다. 마우스는 1차 그대로 |
| 펜 버튼 비트·`invertedStylus`를 보지 않음 | 접촉 순간 `penButton`·`invertedStylus` 제스처를 정해 `beginInteraction(gesture:)`로 |
| 손가락 2·3 탭을 bool로 거름, 길게 누르기 타이머를 bool로 켬 | `GestureSettings.actionFor(g) != none`으로 거르고, 실행은 호스트의 동작 실행기(6.4.3) |
| 손가락 1 탭 = 닫기 | 닫기 전에 **탭 가로채기**(텍스트 세션 끝 → 테이프 → 탭 재생 → 객체 선택 — 6.3.5) |
| (텍스트 편집은 1차에 없음) | 텍스트 세션 중에는 **라우터가 세션 끝을 정한다**: 펜·마우스 접촉, 손가락 한 번 탭(판정 뒤), 길게 누르기 동작만 끝내고, 두 손가락 끌기·핀치·거부된 손바닥·웹 공중 down·펜 전용 한 손가락 끌기는 세션을 유지한다(6.11.5, 검토 M-2). (수정 2회차) 세션 중에는 1차 `EditorCanvasFocus`가 캔버스 down에서 포커스를 가져가지 않는다(6.11.3 '캔버스 포커스 양보', V7) |
| 펜 탭 = 손가락 탭 문턱(20 px·250 ms) | **펜 점 탭**(4 px·200 ms)만 가로채기 대상, 판정은 `end()` 전(6.3.5 — v2.1 R-5) |
| 호버는 Flutter 포인터 호버만 | iOS 네이티브는 `StylusHoverPose`도 펜 활동으로 센다(팜 리젝션 P3 — 6.5.3) |

#### 6.3.2 접촉 판정 (E-4)

```dart
// src/input/stylus_contact.dart
enum StylusContactRule { native, web }   // chosen once: kIsWeb ? web : native (7.4.1 — kIsWeb only)

/// Pure functions, unit-tested with synthetic PointerEvents (no binding).
abstract final class StylusContact {
  /// native: a PointerDownEvent is contact. web: contact only while buttons & kStylusContact != 0.
  static bool isContact(StylusContactRule rule, PointerEvent e);
  /// The gesture that starts at contact: invertedStylus kind → invertedStylus;
  /// buttons & kPrimaryStylusButton != 0 → penButton; else null.
  static EditorGesture? gestureAtContact(PointerEvent e);
}
```

웹 스타일러스 포인터는 상태 둘을 오간다(조사 02 8.4 CDP 실측 순서):

| 받은 이벤트(웹, `kind: stylus`) | 상태 | 라우터 동작 |
|---|---|---|
| `down`, `buttons & 0x01 == 0`(예 `0x02` — 띄운 채 배럴 버튼) | **공중**(airborne) | 상호작용을 시작하지 않는다. 펜 활동 시각만 기록(팜 리젝션 P2·P3), 호버 커서 갱신(`hover(sample)`) |
| 공중에서 `move`, `buttons & 0x01 == 0` | 공중 | 호버 커서만 |
| 공중에서 `move`, `buttons & 0x01 != 0`(예 `0x03`) | **접촉** | 이 `move`를 접촉 순간으로 보고 `beginInteraction(sample(이 move), gesture: gestureAtContact(e))`. P4(펜이 닿으면 손가락 모두 거부)도 이때 |
| 접촉 중 `move`, `buttons & 0x01 != 0` | 접촉 | 1차 그대로 `interaction.move` |
| 접촉 중 `move`, `buttons & 0x01 == 0`(버튼은 누른 채 펜만 뗌) | 공중 | **그 접촉의 끝**: `interaction.end(sample)`. 같은 포인터가 다시 닿으면 새 상호작용(계약 E-4 (v2.1) 문장 — CP-E4 승인) |
| `up` / `cancel` | — | 접촉 중이면 `end` / `cancel`, 공중이면 아무것도 없음 |
| `down`, `buttons & 0x01 != 0` | 접촉 | 1차와 같이 바로 시작(버튼 없이 닿는 보통 경우) |

- 네이티브(안드로이드·iOS)는 1차 그대로 `down` = 접촉이다. 안드로이드 엔진은 닿은 채 버튼이면 `down(buttons: 0x02)`(접촉 비트 없음)를 준다 [확인 — 조사 02 8.2] — 네이티브 규칙은 접촉 비트를 보지 않으므로 그대로 시작하고 `penButton` 제스처가 된다.
- 띄운 채 버튼만 눌렀다 떼는 토글은 쓰지 않는다(7.2.10 E-4). 호버 이벤트의 `buttons`는 보지 않는다.
- 공중 `down`이 와도 Flutter 쪽에서는 그 포인터가 '눌린' 상태라 `PointerHoverEvent`가 아니라 `PointerMoveEvent`가 온다. 그래서 공중 상태를 라우터가 따로 기억한다(`_Track.airborne`).
- 마우스는 규칙 밖이다. 마우스 오른쪽 버튼 = 컨텍스트 메뉴(1차), 왼쪽 = 접촉.

#### 6.3.3 펜 버튼 · 지우개 끝 → 제스처 → 상호작용

| 접촉 순간 | 제스처 | `actionFor` 결과 | 상호작용 |
|---|---|---|---|
| `kind == invertedStylus` | `invertedStylus` | `eraserWhileHeld`(기본) | 임시 지우개 |
| | | `none` | 현재 도구 그대로 |
| `buttons & kPrimaryStylusButton != 0` | `penButton` | `eraserWhileHeld`(기본) | 임시 지우개 |
| | | `lassoWhileHeld` | 임시 올가미 |
| | | `none` | 현재 도구 그대로 |
| 그 밖 | 없음 | — | 현재 도구 |

- 펜 버튼 제스처는 **모든 도구에서** 같다(도형·텍스트 도구 중에도 버튼을 누른 채 쓰면 지우개). 스포이드가 켜져 있으면 스포이드가 이긴다(1차 결정 순서 ①).
- 읽기 전용 노트에서는 임시 지우개·올가미도 시작하지 않는다(1차 ②) — 단 임시 올가미는 선택만 하므로 허용할 수도 있으나, 1차가 읽기 전용에서 올가미를 막았으므로 같게 둔다.

#### 6.3.4 손가락 탭 · 길게 누르기 v2

- `_endTouch`의 2·3 손가락 분기: `case 2 when gestures.actionFor(EditorGesture.twoFingerTap) != EditorAction.none` → `tapGesture(2, centroid)`. 3도 같다. 1 손가락은 1차처럼 언제나 `tapGesture(1, centroid)`.
- 길게 누르기 타이머는 `actionFor(fingerLongPress) != none`일 때만 건다(1차 `longPressMenu` 자리).
- 호스트 `tapGesture(n)`: n = 2·3이면 `EditorActionRunner.run(actionFor(g), GestureSource(centroid))`. n = 1이면 6.3.5의 순서.
- (수정 1회차, 검토 M-2) **텍스트 편집 세션 중의 손가락**: 설정이 손가락 필기여도 세션 동안은 손가락을 펜 전용 모드처럼 다룬다 — 한 손가락 끌기 = 스크롤, 두 손가락 = 내비게이션(1차), 손가락 down은 상호작용을 시작하지 않는다(그래야 핀치의 첫 손가락 down이 세션을 끝내지 않는다 — 1차 P6은 손가락 획을 시작한 뒤에야 내비게이션으로 바꾼다). 세션을 끝내는 손가락 입력은 ① 한 손가락 탭 확정(`tapGesture(1)` — up에서 탭 판정이 난 뒤, 6.3.5 ⓪) ② 길게 누르기 동작 실행(`fingerLongPress`가 `none`이 아닐 때 — 세션을 끝낸 뒤 메뉴) ③ 2·3 손가락 탭의 `undo`·`redo`(6.11.7)뿐이다. 거부된 접촉(팜 리젝션 P1~P4)은 탭이 되지 않으므로 세션을 끝내지 않는다.

#### 6.3.5 탭 가로채기 (테이프 · 탭 재생 · 객체 선택)

탭 판정은 둘로 나눈다(계약 R-5 (v2.1) — 펜은 '점'만 탭으로 보아 짧은 획을 버리지 않는다, 검토 M-3·CD2-14).

| 종류 | 문턱 | 쓰는 곳 |
|---|---|---|
| 손가락 탭 | 1차 그대로: 이동 ≤ `tapMaxMovement`(20 px), 1 손가락 ≤ `singleTapMaxDuration`(250 ms) | ⓪~⑥ |
| **펜 점 탭** | 이동 ≤ `penTapMaxMovement`(**4 px**), 시간 ≤ `penTapMaxDuration`(**200 ms**) — 6.3.7 | ②·③ |
| 손가락 필기 모드의 손가락 획 | 펜 점 문턱(점만). 탭 재생 조건은 손가락(아래 ①) | ②·③ |

| 순서 | 조건 | 결과 | 펜 점 탭일 때 |
|---|---|---|---|
| ⓪ | 텍스트 편집 세션이 열려 있음(손가락 탭 — 펜은 접촉 순간 이미 끝냄, 6.3.6 3) | 세션 끝(`canvasTap`) — 끝(이 탭은 소비: 새 상자·선택을 만들지 않음) | — |
| ① | 컨텍스트 메뉴·팝업이 열려 있음(손가락 탭만) | 닫기 — 끝 | — |
| ② | 탭 지점에 테이프(`hitTestTape`) | `toggleTape(id)` — 끝 | `session.cancel()` — 점 획 없음 |
| ③ | **탭 재생 상태**(아래)이고 열린 녹음의 획(`hitTestRecorded`, I-11) | `seekMs(max(0, offset − preRoll))` + `play()` — 끝 | `session.cancel()` — 점 획 없음 |
| ④ | 도구가 올가미·도형이고 객체(`hitTestObject`) | 그 객체 선택 — 끝 | — (올가미·도형은 획을 만들지 않음) |
| ⑤ | 도구가 텍스트이고 텍스트 상자 | 그 상자 편집 시작(6.11.1) | — |
| ⑥ | 손가락 탭 | 1차: 선택 해제 | — |
| ⑦ | 펜 | 1차 그대로(점 획 커밋 등) | 점 획 |

**탭 재생 상태** — 계약 R-5 (v2.1)를 순수 함수 하나로 둔다(`playback/tap_to_seek.dart`, `unit/tap_to_seek_state_test.dart`가 조합 전부를 대조):

```dart
enum TapKind { finger, penDot }
/// R-5 (v2.1): tapToSeek on + recorder idle + (finger: panel open OR playing/paused;
/// pen dot: playing/paused only) + the open recording belongs to this note.
bool tapToSeekActive({required TapKind kind, required bool tapToSeekSetting,
    required core.RecorderPhase recorderPhase, required bool panelOpen,
    required core.PlaybackStatus playback, required Set<String> noteRecordingIds});
```

- 손가락: 패널이 열려 있으면 `ready`(패널을 열면 media가 최근 녹음을 재생 없이 연다 — 06-pdf 6.13.3)여도 탭 재생이다. 패널이 닫혀 있고 재생·일시정지가 아니면(녹음 정지 직후의 자동 열림 `ready` 포함) 가로채지 않는다.
- 펜 점: 재생·일시정지 중일 때만. 패널만 열린 상태의 펜 점은 점 획이다(00-review 2.4 — 마침표는 남는다).
- 녹음기가 `idle`이 아니면(`starting`~`finishing`) 어느 쪽도 가로채지 않는다. 녹음 중 `play()`는 media가 무시하므로(CP-PDF-10) 가로채면 소리 없이 점만 사라지기 때문이다.
- 읽는 값은 모두 동기다: `recorder.status`, `playback.status`(`editorPlaybackStatusProvider`의 마지막 값이 아니라 서비스의 `status` getter — R-1과 같은 이유), `editorPanelProvider`, `noteRecordingsProvider(noteId)`의 현재 값(로드 전이면 빈 집합 → 가로채지 않음).
- **판정 시점**(v2.1): `PenInteraction.end(sample)`은 `_session.end()`를 부르기 **전에** 펜 점 탭인지(이동·시간) 보고, 맞으면 `host.interceptPenDot(pagePoint)`(②·③만)를 부른다. 가로챘으면 `_session.cancel()`(INK가 활성 획을 지움 — 명령 없음)하고 `end()`는 부르지 않는다. 가로채지 않았으면 `end()` → 1차 커밋 경로. `end()` 뒤에는 가로채지 않는다(대기 표시가 된 획을 `discardEdit`으로 되돌리는 경로를 만들지 않음).
- 가로채지 않은 펜 입력은 언제나 획이 된다(필기 손실 없음 — R-5). 예외는 테이프 위 점·재생(일시정지) 중 녹음된 획 위 점뿐이다(12.2 Q3).
- 펜 전용 모드의 손가락 탭은 1차처럼 `tapGesture(1)`로 온다(⓪~⑥). 손가락 필기 모드의 손가락은 `PenInteraction`으로 시작하므로 펜과 같은 경로(`end()` 전 판정)를 타되, 위 표대로 문턱은 펜 점·조건은 손가락이다 — 짧은 손가락 획을 버리지 않으면서 패널이 열려 있으면 손가락 점으로 재생할 수 있게.

#### 6.3.6 `beginInteraction` 결정 순서 v2 (1차 계획서 6.6.2 확장)

```dart
// src/input/input_targets.dart — (v2) added parameters
abstract interface class InputTargets {
  /* v1.4 members */
  ToolInteraction? beginInteraction(InputSample sample,
      {required InteractionSource source, EditorGesture? gesture});   // (v2) gesture at contact
  /// (v2) Native iPad: a StylusHoverPose arrived (palm rejection P3 uses it — 6.5.3).
  void noteStylusPoseHover();
}
```

1. 스포이드(1차 ①).
2. 읽기 전용 → `null`(1차 ②).
3. **텍스트 편집 세션이 열려 있음**(펜·마우스 접촉 — 손가락은 세션 중 여기로 오지 않음, 6.3.4) → 세션 끝(`penContact`)을 시작하고 계속한다. 세션 끝은 멱등이고 명령은 `end()` 안에서 한 번만 나간다(6.11.2). 편집기 `TextField`의 `onTapOutside`는 캔버스 down에서 불리지 않는다(뷰포트가 같은 탭 묶음 — 6.11.3, V6). (수정 2회차) 세션이 열려 있는 동안 1차 `EditorCanvasFocus`는 캔버스 down에서 포커스를 요청하지 않고, 캔버스 포커스는 세션이 끝난 뒤 돌려받는다(6.11.3 '캔버스 포커스 양보', V7) — 그래서 이 단계까지 오지 않는 down(두 손가락 끌기·핀치·거부된 손바닥·펜 전용 한 손가락 끌기·웹 공중 down)은 편집기 포커스를 건드리지 않는다.
4. `gesture`가 있고 동작이 `eraserWhileHeld`/`lassoWhileHeld` → 임시 지우개/올가미(6.2.3).
5. **선택 우선 (a′)**(6.6.2): 선택이 있고 down이 선택의 **핸들**(모서리·변·회전·꼭짓점)에 닿음 → 선택 변형·객체 편집(도구와 무관). down이 **본체**(프레임 + 8 px)에 닿음 → 도구가 올가미이거나 선택의 `origin`이 `lasso`·`paste`·`insert`이면 이동, 아니면(도형 도구로 그려 생긴 선택, 그리기 도구의 탭 선택) 선택을 풀고 8로 간다(그 down이 새 도형·새 획이 된다 — 검토 M-4).
6. 페이지 밖·간격 → 선택 해제(1차 ④ — 올가미만이던 것을 모든 도구로).
7. 다른 페이지 → 선택 해제(1차). 마운트·로드 안 된 페이지 → `null`(1차 ⑤).
8. 도구별: 펜 → `PenInteraction`(녹음 메타·도형 보정·롤 각 — 6.10·6.15.1·6.5.4), 지우개 → `EraseInteraction`, 올가미 → `LassoInteraction`, 도형 → `ShapeInteraction`(6.9), 텍스트 → `TextToolInteraction`(6.11.1).

`hitsSelection(screen)`(라우터가 펜 전용 모드의 손가락에 묻는 것)도 5와 같은 규칙이다 — 핸들은 언제나, 본체는 `origin`(또는 올가미 도구)이 이동을 허용할 때만 `true`.

#### 6.3.7 수치 (1차 계획서 6.5.8 표에 더함)

| 이름 | 값 | 쓰는 곳 |
|---|---|---|
| 펜 점 탭 문턱 (v2.1 R-5) | 이동 ≤ `penTapMaxMovement` = 4 px, 시간 ≤ `penTapMaxDuration` = 200 ms(`InputThresholds` 새 필드 — 손가락 탭 문턱 20 px·250 ms와 따로) | 6.3.5·6.14.4 |
| 테이프·객체 적중 허용 | 화면 6 px(`6 / scale` pt) | I-12 |
| 탭 재생 적중 허용 | 화면 12 px | I-11 |
| 선택 이동 시작 문턱 | 화면 4 px(그 안에서 끝나면 탭 — 변형 명령 없음) | 6.6.2 |
| 회전 핸들 거리 | 프레임 위 변 중앙에서 바깥으로 28 px, 지름 시각 14 px · 적중 44 px | 6.6.6 |
| 변 핸들 | 시각 10×10 px 사각, 적중 반경 22 px(모서리 핸들과 같음) | 6.6.5 |
| 꼭짓점 핸들 | 시각 지름 10 px 원, 적중 반경 18 px, 가까운 것 우선 | 6.6.5 |
| 도형 최소 크기 | 대각선 화면 8 px 미만이면 탭 | 6.9 |
| 각도 맞춤 | `SelectionGeometry.snapAngle` 기본(15°, ±3°) | 6.6.6·6.9 |
| 정비율 맞춤 | `abs(w/h − 1) ≤ 0.06`이면 정사각·원 | 6.9 |
| 롤 값 유효 시간 | 펜 다운 전 500 ms 안의 마지막 롤 | 6.5.4 |
| 포즈 호버 펜 활동 | 1차 `penCooldown`과 같은 값, 라우터 단조 시계 기준 | 6.5.3 |

### 6.4 제스처 매핑 (M5-7, 1차 7.8 미룬 항목)

#### 6.4.1 동작 정의

| `EditorAction` | 실행 (`EditorActionRunner.run`) | 쓰는 제스처 |
|---|---|---|
| `none` | 아무것도 안 함 | 전부 |
| `undo` / `redo` | `commands.undo()` / `redo()`(상호작용 중 무시, 텍스트 편집 중이면 세션을 먼저 끝냄 — 6.11.7) | 탭, 더블탭 |
| `contextMenu` | 그 지점 컨텍스트 메뉴(1차 `_menuAt`) | 손가락 길게 누르기 |
| `eraserWhileHeld` / `lassoWhileHeld` | 라우터가 접촉에 쓰는 표시(6.2.3). 실행기에서는 아무것도 안 함 | 펜 버튼, 지우개 끝 |
| `toggleEraser` | 지우개면 `returnFromEraser()`(이전 도구), 아니면 `selectTool(eraser)` | 탭, 더블탭, 스퀴즈 |
| `previousTool` | `swapWithLast()`(6.2.1) | 더블탭 |
| `toolPalette` | 빠른 펜 팝업(펜 종류·색·굵기 — 1차 `QuickPenPopup`)을 **위치 지정**으로 연다(스퀴즈·더블탭의 `hoverPosition`이 있으면 그 점, 없으면 펜 버튼 앵커) | 더블탭, 스퀴즈 |
| `colorPalette` | 색 팝업(최근 색·사용자 팔레트 — 1차 색 패널의 줄 둘)을 같은 위치 규칙으로 | 더블탭, 스퀴즈 |
| `followSystem` | `StylusPreferredAction`을 6.5.2 표로 바꿔 다시 `run` | 더블탭, 스퀴즈 |

#### 6.4.2 제스처별 연결

| `EditorGesture` | 들어오는 곳 | 1차 대비 |
|---|---|---|
| `twoFingerTap`, `threeFingerTap` | `InputRouter._endTouch` → `tapGesture(2/3)` | bool → `actionFor` |
| `fingerLongPress` | 라우터 길게 누르기 타이머 → `longPress` | bool → `actionFor` |
| `penButton`, `invertedStylus` | 라우터 접촉 판정(6.3.2·6.3.3) | 새 |
| `pencilDoubleTap`, `pencilSqueeze` | `StylusExtrasListener`(6.5) | 새 |

#### 6.4.3 동작 실행기

```dart
// src/actions/editor_action_runner.dart — per note (scoped)
sealed class ActionSource { const ActionSource(); }
final class GestureSource extends ActionSource { const GestureSource(this.at); final Offset at; }   // viewport px
final class PencilSource extends ActionSource {
  const PencilSource({this.hoverGlobal, required this.preferred});
  final Offset? hoverGlobal; final StylusPreferredAction preferred; }

class EditorActionRunner {
  EditorActionRunner(this._ref, {required EditorCommands commands});
  /// Runs [action] once. followSystem → followSystemAction(source.preferred) (6.5.2).
  /// Ignored while a tool interaction runs (router.hasActiveInteraction) except palettes.
  void run(EditorAction action, ActionSource source);
}
```

- 모든 동작은 명령을 하나 이하로 만든다(undo·redo는 1차 `_runHistory`). 도구 전환·팝업은 명령이 아니다.
- 읽기 전용 노트: `toggleEraser`·`previousTool`·팔레트는 무시(도구가 비활성), `undo`·`redo`는 1차처럼 CORE가 거절(N-4) → 안내.

#### 6.4.4 설정 화면 편집 UI (`EditorInputSettingsSection` 안)

1차 섹션의 '제스처'(읽기 전용 표)를 편집 가능한 목록으로 바꾼다.

| 줄 | 보이는 조건 | 탭하면 |
|---|---|---|
| 두 손가락 탭 · 세 손가락 탭 · 손가락 길게 누르기 | 언제나 | 동작 고르기 시트(`allowedFor`의 값만, 라디오) |
| 펜 측면 버튼을 누른 채 쓰기(S펜 등) | 언제나(안내: '안드로이드 S펜·일부 펜에서 동작해요') | 같음 |
| 펜 뒤쪽 지우개 | 웹이 아닐 때(`!kIsWeb` — 웹 엔진은 `invertedStylus`를 만들지 않는다, 조사 02 8.4, 검토 S-12(b)). 안내: '지우개 끝이 있는 펜에서 동작해요' | 같음 |
| Apple Pencil 두 번 탭 | `stylusExtrasProvider.capabilities.doubleTap` | 같음 |
| Apple Pencil 스퀴즈 | `capabilities.squeeze` **그리고** 이 기기에서 스퀴즈 이벤트를 한 번 받음(`EditorDeviceState.seenSqueeze` — 계약 7.2.10 (v2.1), CD2-24) | 같음 |
| (고정, 바꿀 수 없음) 두 손가락 끌기 스크롤 · 핀치 확대 · 펜 전용에서 한 손가락 끌기 스크롤 | 언제나 | 없음(회색 글자) |
| [기본값으로] | 언제나 | `GestureSettings.defaults` |

- 동작 이름 문구(해요체 아님 — 명사형 메뉴 문구): 없음 · 되돌리기 · 다시 실행 · 메뉴 열기 · 누르는 동안 지우개 · 누르는 동안 올가미 · 지우개 켜고 끄기 · 이전 도구 · 도구 팔레트 · 색 팔레트 · iPad 설정 따르기.
- 바꾸면 `editorSettingsProvider.notifier.setGestures(gestures.withAction(g, a))`(1차 setter — 500 ms 디바운스, synced).
- 시트는 `material_ui` `showModalBottomSheet`(7.4.10). 위젯 키는 부록 C.
- (고정 제스처에 더함) **당겨서 페이지 추가**: 문서 끝에서 탐색 끌기(펜 전용 = 한 손가락·두 손가락, 손가락 그리기·`auto` = 두 손가락, 트랙패드)를 더 당겨 잠깐 멈췄다 놓으면 '+ 페이지'와 같은 명령으로 페이지를 더한다. 바꿀 수 없고 설정 시트에도 없다. 설계는 1차 계획서 [04-editor 6.11.7](../04-editor.md#6117-당겨서-페이지-추가)(이 문서의 6.11.7과는 다른 절).

### 6.5 Apple Pencil 부가 이벤트 소비 (M5-9 — P-B)

#### 6.5.1 구독 수명

- `StylusExtrasListener`(노트 화면 위젯)가 `ref.watch(stylusExtrasProvider)`의 `events`를 화면이 열린 동안만 구독한다(`initState` → `dispose` 취소). `isSupported == false`면 구독하지 않는다. 이벤트 스트림 오류는 무시한다(INFRA 어댑터가 흘리지 않음 — 01-infra 6.12.1).
- (v2.1, CD2-24) `capabilities`는 INFRA가 **앱 시작 때 한 번** 읽은 값이다. iPadOS 설정('펜슬로만 그리기'·두 번 탭/스퀴즈 선호 동작)을 앱 실행 중에 바꾸면 다음 시작 때 반영된다 — 설정 화면 Pencil 줄 아래에 'iPad 설정을 바꾸면 앱을 다시 열 때 반영돼요'를 보인다. 이벤트의 `preferredAction`은 이벤트마다 오므로 '시스템 설정 따르기'의 동작 자체는 바로 따라간다.
- (v2.1) `squeeze`·`barrelRoll` 능력은 OS 가용성일 뿐 펜 종류가 아니므로, 처음 받은 `StylusSqueeze`·`StylusBarrelRoll`(또는 `roll`이 있는 `StylusHoverPose`)에서 `EditorDeviceStateNotifier.markSeenSqueeze()`·`markSeenBarrelRoll()`을 한 번 부른다(device 저장 — 다시 시작해도 보임). 그 전에는 스퀴즈·롤 설정 줄을 숨긴다(Pencil 2·USB-C 펜슬에서 쓸 수 없는 항목 숨김, U1). 이벤트 처리는 그와 무관하게 늘 한다.
- 에디터 화면은 한 번에 하나만 열린다(1차 라우팅 — 노트 화면이 겹치지 않음). 화면이 바뀌는 중에 온 이벤트는 새 화면의 구독이 시작된 뒤부터만 받는다.

| 이벤트 | 처리 |
|---|---|
| `StylusDoubleTap(preferredAction, hoverPosition)` | `run(actionFor(pencilDoubleTap), PencilSource(hoverGlobal: hoverPosition, preferred: preferredAction))` |
| `StylusSqueeze(phase, preferredAction, hoverPosition)` | `phase == ended`일 때만 `run(actionFor(pencilSqueeze), …)`. `began`·`changed`·`cancelled`는 무시(Apple 예제 — 조사 02 9.1) |
| `StylusHoverPose(position, height, …)` | 6.5.3 |
| `StylusBarrelRoll(angle)` | 6.5.4 |

#### 6.5.2 `followSystem` 변환 (계약 7.2.10 문장의 표)

| `StylusPreferredAction` | `EditorAction` |
|---|---|
| `switchEraser` | `toggleEraser` |
| `switchPrevious` | `previousTool` |
| `showColorPalette` | `colorPalette` |
| `showInkAttributes`, `showContextualPalette` | `toolPalette`(스퀴즈는 `hoverPosition`에 띄움) |
| `ignore`, `runSystemShortcut`, `unknown` | `none` |

`src/actions/follow_system.dart`의 순수 함수 `EditorAction followSystemAction(StylusPreferredAction)` — `unit/follow_system_test.dart`가 8값 전부를 대조한다.

#### 6.5.3 호버 자세 (iPad 네이티브)

- iOS 네이티브의 Pencil 호버는 Flutter에 `kind: mouse` 호버로 와서(높이 없음, 조사 02 8.3) 1차 커서 규칙(마우스 호버엔 펜 점 커서 없음)으로는 펜 점이 보이지 않는다. `capabilities.hoverPose`가 참이면 **호버 커서의 출처를 `StylusHoverPose`로 바꾼다**: `position`(전역 → 뷰포트 지역) 위치에 1차 `PenDotCursor`, 지름은 1차 공식 × (1 + 0.5 × (1 − height))(가까울수록 실제 굵기에 가까움 — `height` 0..1), 투명도 50%. 300 ms 동안 포즈가 없으면 숨김(1차 시간 그대로).
- 같은 이벤트로 `InputTargets.noteStylusPoseHover()` → 라우터가 단조 시계 시각을 펜 호버 시각으로 기록 → 팜 리젝션 P3(`treatHoverAsPenActivity`)가 네이티브 iPad에서도 동작한다. (v2.1, CP-E6 승인 — P-B) 이벤트에 `timestamp`(iOS `systemUptime` 기준 — `PointerEvent.timeStamp`와 같은 기준 [추측, C-1에서 확인])가 있으면 그 값을 쓰고, `null`이면 라우터의 `Stopwatch`로 잰다. 두 기준을 섞어 비교하지 않는다 — 기준이 같다는 것이 실기기(C-1)에서 확인되기 전에는 포즈 호버 시각을 `Stopwatch` 쪽 장부에 따로 두고 손가락 down도 같은 `Stopwatch`로 잰 시각과 비교한다.
- `prefersPencilOnlyDrawing`(iPadOS '펜슬로만 그리기')이 참이면 입력 모드 `auto`가 첫 스타일러스를 보기 전부터 펜 전용으로 동작한다(`penOnlyEffective = penOnly || auto && (stylusSeen || prefersPencilOnlyDrawing)`). 1차 `EditorSettings.isPenOnlyEffective`는 설정 값만 아는 getter라 능력을 모르므로 그대로 두고, 위 식은 **입력 정책**을 만드는 곳 — 1차 `InteractionHost.policy` getter(라우터가 포인터 down마다 읽는 `InputPolicy` 스냅샷, `tools/interaction_host.dart` 122 [확인]) — 가 `stylusExtrasProvider.capabilities`를 함께 읽어 `penOnly`에 넣는다(검토 S-12(c)). 같은 스냅샷에 (2차) `textSessionActive`(6.3.4 — 세션 중 손가락을 펜 전용처럼)도 더한다. 설정 화면 입력 모드 안내에 'iPad 설정을 따르고 있어요'를 보인다.

#### 6.5.4 배럴 롤 → 캘리그래피 펜촉 각

- `BarrelRollTracker`(노트 화면 단위)가 마지막 롤 각(라디안)과 받은 시각(단조 시계)을 기억한다. 출처는 `StylusBarrelRoll.angle`과 `StylusHoverPose.roll`(호버 중 롤) 둘 다다.
- 펜 다운에서 `style.tool == PenTool.calligraphy`이고 `style.followBarrelRoll`이고 `capabilities.barrelRoll`이고 마지막 롤이 500 ms 안이면: `nibAngleDeg' = (style.nibAngleDeg + roll·180/π) mod 180`, 넘기는 스타일 = `style.withInkExtras(nibAngleDeg: nibAngleDeg')`. 그 획 하나에만 쓰고 펜 설정(`editor.penStyles`)은 바꾸지 않는다(7.2.9 끝 문단 — 획마다 고정 각).
- 웹·안드로이드는 롤 이벤트가 없어 언제나 고정 각이다. 설정의 '펜슬 돌리기로 각도 조절' 줄은 `capabilities.barrelRoll` **그리고** `seenBarrelRoll`일 때만 보인다(v2.1 — 6.5.1). 롤 유효 시간(500 ms)은 이벤트 `timestamp`가 있으면 그것과 펜 다운 `PointerEvent.timeStamp`의 차로, 없으면 라우터 `Stopwatch`로 잰다(6.5.3과 같은 규칙).

### 6.6 선택 v2 (M5-1, 1차 계획서 6.6.5·6.6.6 확장)

#### 6.6.1 `EditorSelection` v2

```dart
// src/tools/selection.dart
/// (v2, 검토 M-4) Where the selection came from — decides whether a body drag moves it (6.6.2).
enum SelectionOrigin { lasso, paste, insert, drawn, tap }

@immutable
class EditorSelection {
  const EditorSelection({required this.pageId, required this.elementIds,
      this.origin = SelectionOrigin.lasso, this.isDragging = false, this.vertexMode = false});
  final String pageId;
  final Set<String> elementIds;     // (v2) strokes AND objects (was strokeIds)
  final SelectionOrigin origin;     // (v2) 6.6.3 table; kept when the same ids are re-selected
  final bool isDragging;            // menu hidden while true
  final bool vertexMode;            // (v2) single polyline shape: vertex handles shown (6.6.5)
}
class EditorSelectionNotifier extends Notifier<EditorSelection?> {
  /* v1.4: select, clear, setDragging, revalidate — select gains {SelectionOrigin origin = lasso} */
  void setVertexMode(bool value);   // (v2) only for a single ShapeObject with PolylineGeometry
}
```

- `select(pageId, ids)`는 `controller.select(ids)`(INK가 획·객체를 함께 받음)의 결과 `InkSelection.allIds`를 담는다.
- 선택의 '종류'는 저장하지 않고 필요할 때 INK 선택에서 읽는다: `sel.strokeIds`, `sel.objectIds`, `sel.objects`. **단일 객체 선택** = `strokeIds.isEmpty && objects.length == 1`.

#### 6.6.2 선택 우선 규칙 (a′)

선택이 있을 때 down의 처리(6.3.6 ⑤ — 검토 M-4, 총괄 Q8 답 '(a′)'):

| down 위치 | 올가미 도구 | 그리기 도구(펜·지우개·도형·텍스트) |
|---|---|---|
| 핸들(모서리·변·회전·꼭짓점) | 선택 조작 | 선택 조작(도구와 무관) |
| 본체(프레임을 8 px 부풀린 영역 — 1차 `bodyInflate`) | 이동(이동 시작 문턱 4 px) | `origin`이 `lasso`·`paste`·`insert`이면 이동(문턱 4 px). `drawn`·`tap`이면 **선택을 풀고 도구 동작**(새 도형·새 획·새 상자) |
| 그 밖 | 선택 해제 + 도구 동작(1차) | 선택 해제 + 도구 동작 |

- 이유: 도형 도구로 그린 도형·그리기 도구에서 탭으로 고른 객체는 '이 도구로 계속 그린다'가 흔한 흐름이다(사각형 안에 원, 표 그리기, 겹친 도형 — 초안은 이것이 막혔다). 핸들은 작고 가장자리에 있어 그리기와 겹치지 않으므로 그대로 우선한다. 올가미(임시 올가미 포함)·붙여넣기·삽입 메뉴는 사용자가 '이것을 다루겠다'고 고른 결과라 도구를 바꾸지 않고 바로 옮길 수 있어야 한다 — B-5 '펜 도구에서 선택 끌기'는 이 선택들로 그대로다(00-review 3.4 검토 질문 1 답).
- 이미지 삽입 직후(`insert`) 이미지 위 펜 끌기는 이동이다. 그 위에 쓰려면 빈 곳을 한 번 눌러 선택을 푼다(총괄 결정 — 11 리스크 3).
- 본체 위 down은 **이동 시작 문턱**(화면 4 px)을 넘어야 이동 미리보기를 시작한다. 문턱 전에 끝나면 '선택 탭'이다: 텍스트 도구 + 단일 텍스트 상자 → 편집 시작, 그 밖 → 아무것도 하지 않음(명령 없음). 1차는 작은 흔들림도 `TransformElements` 1단계를 만들었다 — 이번에 고친다.
- 판정은 `InteractionHost`의 순수 함수 `selectionPriority(origin, tool, hit) → {handle, move, drop}` 하나에 둔다(`unit/selection_priority_test.dart`가 표 전부를 대조). 라우터의 `hitsSelection`도 같은 함수를 쓴다(6.3.6).

#### 6.6.3 선택이 생기는 곳

| 곳 | 선택 | `origin` | 도구 |
|---|---|---|---|
| 올가미(1차) | `LassoSession.end()`의 `allIds`(`LassoOptions.includeObjects` 기본 — 객체 중심이 올가미 안) | `lasso` | 그대로 |
| 올가미 도구 탭 | `hitTestObject` 적중 객체 하나(6.3.5 ④) | `lasso` | 그대로 |
| 임시 올가미(펜 버튼) | 올가미와 같음 | `lasso` | 그대로(펜 등) |
| 도형 도구 탭 | 적중 객체 하나(도형이 아니어도 — 6.3.5 ④) | `tap` | 그대로 — 핸들·메뉴로 고치고, 옮기려면 올가미로 |
| 텍스트 도구로 텍스트 상자가 아닌 객체 탭 | 그 객체 | `tap` | 그대로 |
| 붙여넣기·복제·이미지 붙여넣기(컨텍스트 메뉴·⌘V) | 새 id 전부 | `paste` | 1차: 올가미로 바꿈 → 2차: **도구를 바꾸지 않는다**(Q8) |
| 도형 그리기 끝 | 새 도형 | `drawn` | 그대로 — 핸들로 바로 고치고, 본체 down은 다음 도형(6.9.2) |
| 이미지 삽입(삽입 메뉴) | 새 이미지 | `insert` | 그대로 |
| 확장 `EditorInsertContext.selectObject(id)`(수식 패드 등) | 그 객체 | `insert` | 그대로 |
| 변형·색 변경·90° 돌리기 뒤 같은 id 다시 선택 | 같은 id | 앞 선택 그대로 | 그대로 |
| 텍스트 편집 세션 끝·자동 도형 보정 | 없음(선택하지 않음 — 계속 쓰기 쉽게) | — | 그대로 |

#### 6.6.4 프레임 · 핸들

| 선택 | 프레임(점선, 1차 모양) | 핸들 | 끌기 결과 |
|---|---|---|---|
| 여럿(획만·혼합·객체 여럿) | 축 정렬 `sel.bounds`. 미리보기 중에는 `SelectionGeometry.transformedCorners(bounds, previewTransform)`(회전된 사각형) | 모서리 4(비율 유지) + 회전 1 | `TransformElements` |
| 단일 `ShapeObject`(폴리라인) | `object.frame`(점의 축 정렬 상자 — 7.2.2: 폴리라인 frame은 회전 0) | 모서리 4 + 변 4 + 회전 1, `vertexMode`면 꼭짓점 N | 모서리·회전 `TransformElements`, 변·꼭짓점 `UpdateObjects` |
| 단일 `ShapeObject`(직선·화살표) | 두 끝점을 잇는 선 + 상자 없음 | 끝점 2(언제나 꼭짓점 모드) + 회전 없음 | `UpdateObjects` |
| 단일 `ShapeObject`(타원) | `EllipseGeometry.ellipseFrame`(회전된 상자) | 모서리 4 + 변 4 + 회전 1 | 모서리·회전 `TransformElements`, 변 `UpdateObjects` |
| 단일 `TextBoxObject` | `frame`(회전된 상자) | 왼쪽·오른쪽 변(폭) + 모서리 4 + 회전 1 | 폭 `UpdateObjects`(높이 다시 잼), 모서리 `TransformElements`(`cornerScale` — 글자 크기도 배율, CP-2 승인), 회전 `TransformElements` |
| 단일 `ImageObject` | `frame`(회전된 상자) | 모서리 4(비율 유지) + 회전 1. '비율 고정 풀기'(메뉴)를 켜면 변 4 추가 | 모서리·회전 `TransformElements`, 변 `UpdateObjects` |
| 단일 `MathObject` | `frame` | 모서리 4 + 회전 1 | `TransformElements`(`cornerScale`, 글자 크기도 배율 — `PageObject.transformed` 7.2.2) |
| 단일 `UnknownObject` | `frame` | 없음 | 끌어도 움직이지 않는다(`TransformElements`가 건너뜀 — 미리보기도 하지 않음). 메뉴는 삭제·복사·잘라내기만 |

- 단일 객체의 모서리 핸들(비율 유지)은 **회전된 frame의 모서리**에 그리고, 끌면 `ObjectResize.cornerScale`(6.6.5)이 회전된 반대 모서리를 고정한 균일 배율 행렬을 만든다(검토 S-2 승격 — `SelectionGeometry.resize`는 축 정렬 `bounds`만 받아 회전된 객체에서는 반대 모서리가 고정되지 않는다 [확인 INK `selection_geometry.dart` 41–80]). 다중 선택의 모서리는 축 정렬 프레임이라 1차 `SelectionGeometry.resize(keepAspect: true)` 그대로다.
- 핸들 모양은 1차와 같은 색(`colorScheme.primary` 테두리 + 흰 채움), 모서리는 원, 변은 사각, 꼭짓점은 작은 원, 회전 핸들은 원 + 위 변 중앙까지 잇는 선. 회전된 프레임에서는 핸들도 프레임 방향으로 돌아간다.
- 프레임·핸들은 1차처럼 EDITOR 오버레이(`SelectionFramePainter` v2)가 그리고 INK 컨트롤러 알림으로만 다시 그린다(provider 상태 변경 없음).

#### 6.6.5 단일 객체 핸들 · 꼭짓점 편집 (`ObjectEditInteraction`)

```dart
// src/tools/object_resize.dart — pure math, unit-tested
abstract final class ObjectResize {
  /// (수정 1회차, 검토 S-2 → EDITOR-M5) Corner handle (keep aspect) of a single — possibly rotated —
  /// object. delta is turned into the frame's local axes (−frame.rotation) and projected on the
  /// diagonal from the opposite corner o to the dragged corner c: s = (|c − o| + proj) / |c − o|,
  /// clamped so no side goes below the minimum (4 pt; text 40 pt wide; image 16 pt) or above
  /// ElementFrame.maxSide. Returns T(o) · S(s) · T(−o) — a uniform scale about the ROTATED opposite
  /// corner (frame.corners[(i + 2) % 4]), so rotation is unchanged and o stays put. Fed to
  /// InkSelection.setPreviewTransform → commitTransform → TransformElements (PageObject.transformed).
  static core.Affine2 cornerScale(core.ElementFrame frame, ink.SelectionHandle corner,
      Offset deltaPagePt);
  /// Edge handle drag in the object's frame-local axes (rotation undone, then redone).
  /// Returns the edited copy (same id) or null when the result would be smaller than the minimum.
  static core.PageObject? resize(core.PageObject object, ink.SelectionHandle handle,
      Offset deltaPagePt, {required bool keepAspect});
  /// Moves vertex [index] of a PolylineGeometry shape; [snapAngle] snaps the edge angle (line / arrow).
  static core.ShapeObject moveVertex(core.ShapeObject shape, int index, Offset deltaPagePt,
      {bool snapAngle = true});
  /// Text box width handle: new frame width (min 40 pt), height re-measured by the caller.
  static core.TextBoxObject resizeTextWidth(core.TextBoxObject box, ink.SelectionHandle side,
      Offset deltaPagePt);
}
```

| 객체 | 변 핸들 | 모서리 핸들(비율 유지) |
|---|---|---|
| 폴리라인 도형 | 프레임 축(=페이지 축)으로 한쪽만 늘림: 점마다 `x' = anchor + (x − anchor)·s` — 회전된 사각형을 늘리면 평행사변형이 된다(받아들임) | `cornerScale`(폴리라인 frame은 회전 0이라 축 정렬 결과와 같음) → `TransformElements` |
| 타원 | 타원 프레임의 지역 축으로 `rect` 크기 변경, `rotation` 유지 → `EllipseGeometry(ElementFrame(rect', rotation: θ))` | `cornerScale` → `TransformElements` |
| 텍스트 상자 | 왼쪽·오른쪽만(폭). 위·아래는 없음(높이는 내용으로 정해짐) | `cornerScale` → `TransformElements` — (v2.1, CP-2 = CP-E2 승인) `PageObject.transformed`가 `fontSizePt × s`([6, 144])로 줄바꿈 폭과 글자를 함께 배율하므로 frame 높이가 그대로 맞는다(K-6). 초안의 '`UpdateObjects` 우회'는 지웠다 |
| 이미지 | 비율 고정 풀었을 때만 | `cornerScale` → `TransformElements` |
| 수식 | 없음 | `cornerScale` → `TransformElements`(글자 크기 배율) |

- 모서리(비율 유지) 끌기 중 미리보기는 `sel.setPreviewTransform(cornerScale(…))`(INK가 객체를 `PageObject.transformed`로 그림 — 미리보기 = 커밋), 끝은 `commitTransform()` → `commitInkEdit`(1차 실패 처리).
- 변·꼭짓점·텍스트 폭 끌기 중 미리보기: `controller.setPreviewObjects([편집된 사본])`(같은 id라 화면에서 원본을 대신 — I-3). 끝: (검토 S-1) 먼저 `session.pageIfLoaded(pageId)?.objectById(id)`를 **동기로** 본다 — `null`(원격 삭제)이면 명령을 보내지 않고 미리보기만 지운다(스낵바·보고 없음). 있으면 `UpdateObjects(pageId: p, objects: [사본])`를 `_run`으로 → 성공이면 `setPreviewObjects(const [])` + 같은 id 다시 선택, 실패(읽기 전용 경합 — 1차 안내, 검사와 실행 사이 원격 삭제 — 1차 `_rejected` `default:` 처리)면 미리보기만 지운다(6.21).
- 꼭짓점 끌기: 직선·화살표는 다른 끝점 기준 각도를 `snapAngle`로 맞춘다. 다각형·삼각형·사각형·별은 맞춤 없음. 별은 P-C(점이 많아 핸들이 겹침 — 00-overview 3.4 P-C 그대로). 꼭짓점 모드는 메뉴 '꼭짓점 편집'으로 켜고 선택이 풀리면 꺼진다.
- `shapeKind`는 꼭짓점을 옮겨도 바꾸지 않는다(7.2.2 'UI meaning only').
- 최소 크기: 프레임 한 변 4 pt(텍스트 폭 40 pt, 이미지 16 pt) 아래로는 줄지 않는다(그 값에서 멈춤).

#### 6.6.6 회전 핸들

- 끌기: 프레임 중심 c(화면)에서 down 각 φ₀, 지금 각 φ. 다중 선택과 **단일 폴리라인 도형**은 상대 각 `Δ = snapAngle(φ − φ₀)`, `t = SelectionGeometry.rotate(bounds: sel.bounds, radians: Δ)`(폴리라인은 `frame.rotation`이 늘 0이고 점 자체가 돌므로 '절대 각'이 뜻이 없다 — 7.2.2, 검토 S-2). frame에 회전이 있는 단일 객체(텍스트·이미지·타원·수식)는 **절대 각을 맞춘다**: `θ' = snapAngle(frame.rotation + (φ − φ₀))`, `Δ = θ' − frame.rotation`, 회전 중심은 객체 프레임 중심. → `sel.setPreviewTransform(t)`, 끝 `commitTransform()` → `commitInkEdit`.
- 끌기 중 각도 표시: 회전 핸들 옆에 '30°' 같은 작은 꼬리표(`RotationLabel` — 절대 각은 회전이 있는 단일 객체, 상대 각은 다중 선택·폴리라인).
- 시험 각(검토 S-2·S-12(f)): 포인터 좌표에서 나온 각은 부동소수 오차가 있어 맞춤 문턱(±3°) **경계값을 쓰지 않는다** — 맞춤은 `32° → 30°`·`47° → 45°`, 안 맞춤은 `20° → 20°`처럼 경계에서 1° 이상 떨어진 값.
- **90° 돌리기**(선택 메뉴 '더보기'): `rotate(bounds, π/2)` 미리보기 없이 바로 `commitTransform` — V5 스모크가 쓰는 결정적 경로이기도 하다.
- 회전 뒤 다중 선택의 프레임은 회전된 내용의 축 정렬 상자로 다시 계산된다(같은 id 다시 선택).

#### 6.6.7 재검증 v2 (1차 계획서 6.6.6)

- `revalidate(pageId, content)`: `ids ∩ {content.elementById(id) != null}`. 1차의 `strokeById`를 `elementById`로.
- 핸들·꼭짓점·회전 끌기 중(`isDragging`)에 원격 변경으로 대상이 사라지면, 끝에서 명령 전에 동기 검사(6.6.5 — 검토 S-1)로 알아채 미리보기를 지우고 조용히 끝낸다(명령 없음·안내 없음·보고 없음 — 대상이 이미 없음). `TransformElements` 경로(모서리·회전)는 CORE가 없는 id를 무시하므로(1차 규칙) 남은 요소만 움직인다.

### 6.7 선택 메뉴 v2

#### 6.7.1 항목 배치

1차 막대(선택 프레임 8 px 위, 공간 없으면 아래)를 그대로 쓰고 항목을 바꾼다.

```text
[잘라내기] [복사] [삭제] [색 ●] [확장 항목 …] [⋯]
                                                └ 더보기: 복제 · 90° 돌리기 · (단일 도형) 스타일 · 꼭짓점 편집
                                                          · (단일 텍스트) 편집 · 서식 · (단일 이미지) 비율 고정 풀기/잠그기
                                                          · 넘친 확장 항목 · 선택 해제
```

- 막대에 보이는 확장 항목은 **최대 2개**(목록 순서), 나머지는 '⋯'로. 막대 폭이 뷰포트보다 넓으면 확장 항목부터 '⋯'로 옮긴다.
- 읽기 전용: 잘라내기·삭제·색·복제·돌리기·스타일·편집 비활성(1차 삭제와 같음), 복사·확장 항목은 그대로(확장 항목은 `execute`가 CORE에서 거절되면 recog가 안내).
- `UnknownObject`만 있는 선택: 색·스타일·돌리기 숨김.
- 끌기 중 숨김(1차).

#### 6.7.2 색 변경

- '색 ●'(지금 선택의 대표 색 — 첫 요소 색) → `RecolorPopup`(막대에 붙어 열림): 최근 색 줄 + 사용자 팔레트 줄(1차 `editorColorPaletteProvider`) + '더 보기'(1차 색 패널 전체를 같은 팝업 안에서). 색 하나를 누르면 `commitInkEdit(controller, sel.recolor(argb))` → 1단계, 팝업 닫힘, 선택 유지, 그 색을 최근 색에 넣음.
- 이미지만 있는 선택이면 '색'을 숨긴다(INK가 이미지는 바꾸지 않음).

#### 6.7.3 잘라내기 · 복사 · 삭제 · 복제

- 복사: 선택 요소(획 + 객체)를 CORE 상태(`session.pageIfLoaded(pageId).elementById`)에서 읽어 앱 클립보드에(6.8). 명령 아님.
- 잘라내기: 복사 → `commitInkEdit(controller, sel.delete())`(1단계). 삭제가 거절되면 클립보드 내용은 남는다(복사는 이미 됨 — 받아들임).
- 삭제: 1차 그대로(객체가 섞이면 INK가 `RemoveElements`).
- 복제: `commitInkEdit(controller, sel.duplicate())` → 성공이면 새 요소(`edit.added` id + `edit.addedObjects` id)를 선택.

#### 6.7.4 확장 항목 (`selectionMenuItems`) · `EditorSelectionContext`

```dart
// src/commands/extension_runner.dart (excerpt)
EditorSelectionContext selectionContext(EditorSelection s, ink.InkSelection sel) {
  final content = session.pageIfLoaded(s.pageId)!;
  return EditorSelectionContext(
    noteId: noteId, pageId: s.pageId, pageSize: content.page.size,
    strokes: [for (final st in content.strokes) if (s.elementIds.contains(st.id)) st],   // z order
    objects: [for (final o in content.objects) if (s.elementIds.contains(o.id)) o],      // z order
    boundsPt: sel.bounds,
    execute: executeForExtension,   // session.execute(command); rethrows (contract: 'Throws like NoteSession.execute')
    clearSelection: () => selections.clear());
}
```

- `execute`는 1차 `_run`과 달리 예외를 **다시 던진다**(계약 문장). 다만 `ReadOnlyNoteException`이면 던지기 전에 `editorReadOnlyProvider`를 새로 고친다(1차 `_rejected`와 같은 부수 효과). 확장 항목 하나가 `execute`를 여러 번 부르면 되돌리기도 여러 단계다(계약 'ONE command' — 지키는 것은 항목 쪽 책임, 시험 항목으로 단언).
- `isVisible(context)`는 메뉴를 그릴 때마다 부른다(계약 (v2.1) — 가볍게, provider를 읽지 않음). 예외면 그 항목을 숨기고 보고만 한다(E-7 (v2.1) 예외 — 문구 없음, 4.3.1).
- 항목을 누르면 `onPressed` 안에서 `onSelected(bodyContext, selectionContext(...))`를 **동기적으로** 시작한 뒤 막대·'⋯' 메뉴를 닫는다(4.3.1 — 계약 7.2.10 (v2.1)). 문맥은 누른 순간에 만든 것이라 항목이 끝나기 전에 선택이 바뀌어도 그 값은 그대로다(값 복사). recog 변환은 `execute` 뒤 `clearSelection`을 부른다(CP-L3 — X30 `done` 규칙).
- 페이지가 아직 로드되지 않았으면(`pageIfLoaded == null` — 선택은 로드된 페이지에서만 생기므로 정상에서는 없음) 확장 항목을 숨긴다.

#### 6.7.5 단일 객체 스타일 · 서식

- 도형 '스타일' → `ShapeStyleControls`(도형 도구 팝업과 같은 위젯)를 팝업으로. 조절이 끝날 때마다(색 누름, 굵기 슬라이더 놓음, 선 종류·채우기·화살촉 바꿈) `UpdateObjects([shape.copyWith(style: …normalized())])` 1단계. 선택한 도형이 여럿이면(도형만 있는 다중 선택) 메뉴에 '스타일'을 보이고 한꺼번에 `UpdateObjects`(1단계).
- 텍스트 '편집' → 편집 세션 시작(6.11). '서식' → 서식 바만 띄우고 바꿀 때마다 `UpdateObjects`(높이 다시 잼) 1단계 — 편집 세션 밖의 서식 변경.

#### 6.7.6 단축키 (1차 계획서 6.8 표에 더함, 캔버스 포커스일 때만)

| 키 | 동작 |
|---|---|
| ⌘/Ctrl + X | 잘라내기 |
| ⌘/Ctrl + D | 복제 |
| ⌘/Ctrl + C / V | 1차(복사 / 붙여넣기 — v2 클립보드) |
| Delete·Backspace | 1차(선택 삭제) |
| S / T | 도형 도구 / 텍스트 도구(1차 P·E·L과 같은 규칙) |
| Esc | 텍스트 편집 중이면 세션 끝(커밋), 아니면 1차 |

텍스트 편집 중에는 위 키를 모두 편집기(`TextField`)에 양보한다(⌘Z·⌘X·⌘C·⌘V·Delete는 글자 편집 — 1차 HEX 입력란 규칙과 같음). 이때 ⌘C·⌘V는 **시스템 클립보드**의 글자 복사·붙여넣기다(1.3 — 캔버스 수준 붙여넣기와 다름). 하드웨어 키보드가 없는 iPad에서도 편집기의 두 번 탭 낱말 선택·선택 손잡이·붙여넣기 메뉴로 같은 일을 한다(6.11.3, B-15).

### 6.8 앱 클립보드 v2 · 붙여넣기 (1차 계획서 6.6.7 확장)

```dart
// src/tools/element_clipboard.dart (renamed from stroke_clipboard.dart)
@immutable
class ElementClipboardContent {
  const ElementClipboardContent({required this.elements, required this.bounds});
  /// Strokes and objects together, core.Stroke.compareOrder (z order); ids replaced on paste.
  final List<core.PageElement> elements;
  final Rect bounds;                       // page pt, union of element bounds
  int get objectCount;
}
class ElementClipboardNotifier extends Notifier<ElementClipboardContent?> {
  void copy(List<core.PageElement> elements);   // resets the paste offset counter
  /// v1.4 placement rules (centre at [center], clamp, +16 pt per repeated paste). Each element i
  /// (z order): stroke → s.transformed(move, scaleWidth: false).copyWith(id, pageId, createdAt + i);
  /// object → o.transformed(move).copyTo(id: newId(), pageId: pageId, createdAt: createdAt + i).
  ({List<core.Stroke> strokes, List<core.PageObject> objects}) instantiate({required String pageId,
      required Size pageSize, required Offset center, required bool explicitPoint,
      required String Function() newId, required core.EpochMillis createdAt});
}
final editorClipboardProvider = NotifierProvider<ElementClipboardNotifier, ElementClipboardContent?>(…);   // name kept
```

- 붙여넣기 명령: 획과 객체가 모두 있으면 `CompositeCommand([AddStrokes, AddObjects])`, 한쪽만 있으면 그 명령 하나(1단계). 넣기 전 객체 한도 검사(5.1.1).
- `UnknownObject`는 `transformed`가 자신을 그대로 돌려주므로 붙여넣으면 원래 좌표에 남는다(드묾 — 받아들임). 이미지 객체는 같은 `assetId`를 참조한다.
- 붙여넣은 뒤 새 요소를 선택하고 **도구는 바꾸지 않는다**(6.6.3).
- 컨텍스트 메뉴(길게 누르기·오른쪽 클릭, 1차): `[붙여넣기]`(앱 클립보드에 내용이 있을 때) · `[이미지 붙여넣기]`(`editorImageImporterProvider`의 `sources`에 `clipboard`가 있을 때 — 6.12, 누르면 `pick(bodyContext, clipboard)`을 `onPressed` 안에서 동기 시작한 뒤 메뉴를 닫는다 — 4.3.1, `navigator.clipboard.read`가 사용자 동작 직후에만 열리므로) · `[올가미 도구]`(1차). ⌘V는 앱 클립보드가 있으면 그것, 없고 `clipboard` 소스가 있으면 이미지 붙여넣기(키 이벤트 처리 안에서 동기 시작 — 웹 키 입력도 사용자 동작이다 [추측, B-3에서 확인]). 붙여넣은 선택의 `origin`은 `paste`(6.6.3).
- 시스템 클립보드와는 동기화하지 않는다(1.3).

### 6.9 도형 도구 (M5-5)

#### 6.9.1 도구 팝업

도형 도구가 활성일 때 그 버튼을 다시 누르거나 길게 누르면 `ShapeToolPopup`(1차 펜 팝업과 같은 틀, 폭 340):

| 줄 | 내용 |
|---|---|
| 종류 | 7칸: 직선 `horizontal_rule` · 화살표 `arrow_right_alt` · 사각형 `rectangle_outlined` · 원/타원 `circle_outlined` · 삼각형 `change_history` · 다각형 `pentagon`(변 수 3~12 단추) · 별 `star_outline`(꼭짓점 4~16 단추) |
| 테두리 색 | 1차 색 줄(최근 색·팔레트·더 보기) + '펜 색 쓰기' |
| 굵기 | 1차 `WidthSlider`(범위 `ShapeStyle.minWidth`~`maxWidth` = 펜과 같음) |
| 선 종류 | 실선·파선·점선(`LineDash`) |
| 채우기 | 없음 + 색 줄 + 채우기 투명도(0~100%, 기본 100%) — 직선·화살표는 숨김 |
| 화살촉 | 없음·끝·양쪽(`ArrowHeads`) — 직선·화살표에만 |

값은 `editorToolOptionsProvider`(6.2.4)에 저장한다.

#### 6.9.2 끌어 그리기 (`ShapeInteraction`)

1. down(페이지 pt `p0`) — 선택 우선 규칙 (a′)(6.6.2)을 통과한 down만 온다: 선택의 핸들 위 down은 여기로 오지 않고, 방금 그린 도형(`origin: drawn`)·탭 선택(`tap`)의 **본체** 위 down은 여기로 온다(사각형 안에서 원 그리기 — 검토 M-4). 기존 선택을 푼다.
2. move(`p1`): `ShapeDrafts.geometry(kind, p0, p1, options)`로 기하를 만들고 `ShapeObject(id: 'editor.shapePreview', …)`를 `controller.setPreviewObjects([preview])`.
3. up: 대각선이 화면 8 px 미만 → 탭(6.3.5 ④ — 객체 선택/해제). 아니면 `object_factory`로 새 id·`createdAt`의 `ShapeObject`를 만들어 `AddObjects(pageId: p, objects: [shape])` → 성공이면 미리보기를 지우고 새 도형을 `origin: drawn`으로 선택(핸들로 바로 고칠 수 있음). 거절이면 미리보기만 지움.
4. cancel: 미리보기 지움, 명령 없음.

```dart
// src/tools/shape_drafts.dart — pure, unit-tested
abstract final class ShapeDrafts {
  static core.ShapeGeometry geometry(core.ShapeKind kind, core.PagePoint p0, core.PagePoint p1,
      ToolOptions options);
}
```

| 종류 | 기하 (`r = Rect.fromPoints(p0, p1)`) | 맞춤 |
|---|---|---|
| 직선·화살표 | `ShapeGeometry.line(p0, p1)` | `p0` 기준 각도 `snapAngle`(15°, ±3°) |
| 사각형 | `ShapeGeometry.rectangle(r)` | `abs(w/h − 1) ≤ 0.06` → 정사각형(긴 변 기준, `p0` 고정) |
| 원/타원 | `ShapeGeometry.ellipse(r)` | 같은 문턱 → 원 |
| 삼각형 | `ShapeGeometry.triangle(r)` | 없음 |
| 다각형 | `ShapeGeometry.regularPolygon(r, sides)` | 정비율 맞춤 |
| 별 | `ShapeGeometry.star(r, points: starPoints)` | 정비율 맞춤 |

- 하드웨어 키보드 Shift를 누르고 있으면 맞춤 문턱을 무한대로(항상 정비율·15° 단위), Alt면 맞춤 끔. iPad에서 키보드가 없으면 위 문턱만 쓴다.
- 스타일은 `options.shapeStyle.normalized()`, 화살표는 `arrowHeads == none`이면 `end`.

### 6.10 자동 도형 보정 (M5-6 — P-B)

- 설정 `EditorSettings.shapeAssist`(synced, 기본 켬 — U14). 펜 설정 팝업 '고급'과 설정 > 펜 섹션에 같은 토글.
- 펜 다운: 결정은 순수 함수 하나다(검토 M-1 — 시험 이음새):

```dart
// src/tools/shape_assist_for.dart — unit/shape_assist_for_test.dart compares the whole table
ink.ShapeAssist shapeAssistFor(EditorSettings settings, core.PenTool penType, ink.InkShapeFitter fitter) =>
    settings.shapeAssist && fitter is! ink.NoShapeFitter && _assistPens.contains(penType)
        ? ink.ShapeAssist.holdToSnap : ink.ShapeAssist.off;
// _assistPens = {ballpoint, fountain, pencil, marker, brush, calligraphy, dashed}
```

  `PenInteraction.start`가 이 값을 `beginStroke(…, shapeAssist:)`에 넘긴다. 형광펜(1차 직선 보정이 있음)·레이저(저장 안 함)·테이프는 뺀다(12.2 Q4). 넘긴 값은 시험에서 `StrokeSession.shapeAssist` getter(v2.1)로 확인한다(5.2.4).
- 멈춤 감지·판정·미리보기는 INK + `inkShapeFitterProvider`. 펜을 떼면 `StrokeSession.end()`가 `InkEdit(addShape)`를 내고 EDITOR는 1차 경로 그대로 `commitInkEdit`(1단계). 새 코드가 없는 경로라 그 1단계 단언은 P-A E2-09 `widget/shape_tool_test.dart`가 맡는다(수정 3회차 — 5.1.2 매핑 커버리지가 P-B에 묶이지 않게). 원래 획은 저장되지 않는다(7.2.3 원문). 새 도형을 선택하지 않는다(필기 흐름을 끊지 않음).
- `ref.read(ink.inkShapeFitterProvider) is ink.NoShapeFitter`(인식 기능이 꺼진 빌드 — (v2.1, CD2-16) `FEATURE_RECOGNITION=false`가 `recognitionOverrides()`를 빼면 이렇게 된다)이면 토글 줄을 숨기고 `off`로 보낸다(INFRA CP14·V15와 맞음).
- 오인식 표본: 개발자 토글 '도형 표본 모으기'가 켜져 있을 때만 `PenInteraction`이 세션 표본을 링 버퍼에 넣는다(6.20 — 검토 S-5).
- 녹음 메타: `addShape`로 바뀐 도형은 `ShapeObject`에 녹음 필드가 없어 녹음 연결을 잃는다(받아들임 — 12.2 Q9).

### 6.11 텍스트 상자 (M5-2)

#### 6.11.1 시작

| 텍스트 도구에서 | 결과 |
|---|---|
| 기존 텍스트 상자 위 탭(`hitTestObject`가 `TextBoxObject`) | 그 상자 편집 세션 |
| 빈 곳 탭 | 새 상자: 왼쪽 위 = 탭 지점, 폭 = `min(240, 페이지 오른쪽 − x − 16)`(최소 40 pt — 모자라면 왼쪽으로 민다), 서식 = `ToolOptions.textStyle` |
| 빈 곳 끌기(이동 > 탭 문턱) | 새 상자, 폭 = 끈 가로 길이(최소 40 pt), 왼쪽 위 = 끈 사각형의 왼쪽 위. 끄는 동안의 **빈 상자 테두리는 EDITOR overlay가 직접 그린다**(`NewTextBoxOutline` — 객체가 아니므로 `setPreviewObjects`를 쓰지 않음, INK 변경 없음 — 00-review 2.3 INK X-5) |
| 다른 객체 위 탭 | 그 객체 선택(`origin: tap` — 편집하지 않음, 본체 down은 새 상자) |
| 올가미·붙여넣기·삽입으로 생긴 선택의 본체 끌기 | 이동(선택 우선 (a′) — 6.6.2) |

다른 도구에서는 선택 메뉴 '편집'으로만 시작한다(올가미로 상자를 골라 '편집'). 텍스트 상자를 옮기려면 올가미(또는 펜 버튼 임시 올가미)로 고른다.

E2-01(첫 작업)이 텍스트 도구(E2-03)보다 먼저 돌 수 있게 **개발자 메뉴 '텍스트 상자 시험'**(지금 페이지 보이는 영역 가운데에 새 상자 세션을 연다, 키 `editor.dev.textBoxProbe`)을 둔다. 텍스트 도구가 생긴 뒤에도 남긴다(B-2·B-15를 같은 조건으로 되풀이 확인 — 검토 S-3).

#### 6.11.2 편집 세션 (E-6)

```dart
// src/text/text_edit_session.dart — per note (scoped)
@immutable
class TextEditState {
  const TextEditState({required this.pageId, required this.boxId, required this.original,
      required this.draft, required this.isNew, required this.mode});
  final String pageId, boxId;
  final core.TextBoxObject? original;   // null for a new box (not in CORE yet)
  final core.TextBoxObject draft;       // frame / text / style being edited
  final bool isNew;
  final WebTextInputMode mode;          // inline on native; 6.11.6 on web
}
/// (수정 1회차, 검토 M-1) The ids INK must hide — derived from EDITOR state, unit-tested:
/// existing box → {boxId} in every mode (E-6); new box → {}. Sheet mode ALSO puts a same-id
/// preview, which is drawn although the id is hidden (preview wins — 7.2.9 v2.1).
Set<String> hiddenIdsOf(TextEditState? state);
class TextEditNotifier extends Notifier<TextEditState?> {
  void start(core.TextBoxObject box, {required bool isNew});   // applies hiddenIdsOf to the page controller
  void updateText(String text);         // draft only — not a command
  void updateStyle(core.TextBoxStyle style);
  void updateWidth(double widthPt);
  /// Ends the session exactly once (idempotent — the first reason wins): measures the final
  /// height, runs at most ONE command (6.11.5), clears hidden ids in the same frame.
  /// Completes after the command ran.
  Future<void> end({required TextEditEndReason reason});
}
enum TextEditEndReason {
  penContact,     // pen / mouse contact on the canvas (router, 6.3.6 step 3)
  canvasTap,      // one-finger tap confirmed on the canvas (router, 6.3.5 ⓪)
  longPress,      // finger long-press action ran (router, 6.3.4)
  tapOutside,     // pointer down outside the editor tap group: toolbar, panel, sheet, app bar
  focusLost,      // the editor FocusNode lost focus: iPad keyboard 'hide', system focus move,
                  // another text field (수정 1회차, 검토 M-2). Never a canvas pointer down:
                  // EditorCanvasFocus does not request focus during a session (6.11.3, 수정 2회차)
  escape, toolChange, undoRedo, pageUnmounted, leaving, appHidden,
}
final editorTextEditProvider = NotifierProvider<TextEditNotifier, TextEditState?>(…);   // scoped
```

- 세션은 노트에 하나다. 새 세션을 열면 앞 세션을 먼저 끝낸다.
- 세션 중 원격 변경으로 원래 상자가 지워지면(`revalidate`에서 발견) 세션은 열어 두고, 끝날 때 **명령 전 동기 검사**(검토 S-1)로 알아채 `UpdateObjects`를 보내지 않고 **새 상자로 넣는다**(`AddObjects`, 새 id — 쓴 글을 잃지 않음, 6.11.5).
- (P-B, 검토 S-11) **긴 세션 초안 보관**: 세션 중 초안이 바뀌면 5 s마다(마지막 변경 뒤 한 번) EDITOR 내부 device 키 `editor.textDraft`에 `{"v":1,"noteId","pageId","boxId","isNew","draft": TextBoxObject.toJson()}`를 덮어 쓰고, 세션 끝의 명령이 끝나면(또는 명령이 필요 없으면) 지운다. 노트를 열 때 그 노트의 초안이 남아 있으면 배너 '저장되지 않은 글이 있어요 [되살리기] [버리기]'를 보이고, 되살리기 = 새 id의 `AddObjects` 1단계(원래 상자는 건드리지 않음 — 중복은 사용자가 지움). 명령은 여전히 세션 끝 1회다(E-6 그대로). 웹 탭이 메모리 압박으로 다시 열리거나(B-13) 앱이 죽어도 회의록 같은 긴 글을 잃지 않게 한다. `text/text_draft_store.dart`.

#### 6.11.3 오버레이 배치 · 편집기 · 글꼴 · 높이

- **편집기 = `material_ui` `TextField`**(검토 S-7 → EDITOR-M7): 날것 `EditableText`는 선택 제스처·선택 손잡이·복사/붙여넣기 메뉴를 따로 달아야 하고, 하드웨어 키보드 없는 iPad에서는 글을 고르거나 붙여넣을 방법이 없다. `TextField`는 두 번 탭 낱말 선택·선택 손잡이·적응형 메뉴를 준다(`material_ui` 1.10.0 `lib/src/text_field.dart` 224·325·346 [확인], V6 ④). 설정:

```dart
// src/text/text_box_editor.dart (excerpt)
TextField(
  key: const ValueKey('editor.textEditor'),
  controller: _controller, focusNode: _focus, autofocus: true,
  maxLines: null, minLines: 1,
  decoration: const InputDecoration.collapsed(hintText: null),   // contentPadding == EdgeInsets.zero (V6 ①)
  style: ink.InkTextLayout.textStyleOf(draft.style),             // (v2.1, CP-INK-3) exactly what INK paints
  strutStyle: ink.InkTextLayout.strutStyleOf(draft.style),       // forceStrutHeight, height = lineHeight
  textAlign: _alignOf(draft.style.align),
  cursorColor: scheme.primary,
  inputFormatters: [LengthLimitingTextInputFormatter(core.PageObjectLimits.maxTextLength)],
  onTapOutside: (_) => notifier.end(reason: TextEditEndReason.tapOutside),   // never the canvas — below
  // groupId: default (EditableText) — Flutter's own selection handles / toolbar are wrapped in a
  // TextFieldTapRegion of this group (text_selection.dart 1805·1836·1980), so touching them is "inside".
)
```

- **글자 모양은 INK와 같게**(CP-INK-3 지지·사용 — 12.1): 색·굵기·크기·줄 높이·글꼴을 EDITOR가 따로 바꾸지 않고 `textStyleOf`·`strutStyleOf`를 그대로 쓰며 안쪽 여백은 0이다(collapsed). 그래서 세션이 끝나 INK가 그릴 때 글자가 튀지 않는다(E-6, B-15). 배경색은 편집기 뒤 `ColoredBox`(INK와 같은 frame 크기). 선택 색은 `colorScheme.primary` 계열.
- **배치**: `TextBoxEditorLayer`는 페이지 뷰포트 바깥 `Stack`에서 입력 `Listener`의 **위쪽 형제**다(1차 `page_viewport.dart`의 '형제는 라우터에 닿지 않음' 자리 — `SelectionMenu`와 같은 곳 [확인]). 그래서 편집기 위의 손가락·펜은 `TextField`만 받고 라우터는 모른다. 세션의 `draft.frame`을 화면 좌표로: `Positioned`(페이지 → 화면) + `Transform.rotate(frame.rotation, 프레임 중심)` + `Transform.scale(camera.scale)`. 그 안의 편집기는 **페이지 pt 단위**(폭 = `frame.rect.width`, 글자 = `fontSizePt`)라 INK가 그릴 줄바꿈과 같다(V1·V6이 변환 안의 편집기를 확인).
- **탭 묶음**: 세션이 열린 동안 페이지 뷰포트의 캔버스(입력 `Listener` 영역)를 `TextFieldTapRegion(enabled: 세션 있음)`으로 감싼다 — 편집기·서식 바와 **같은 묶음**(`EditableText`)이라 캔버스 down에서는 `onTapOutside`가 불리지 않는다(V6 ②). 캔버스 안에서 세션을 끝낼지는 라우터가 정한다(6.11.5). 세션이 없을 때는 `enabled: false`라 1차와 같다(다른 입력란 — 제목 등 — 의 기본 동작에 영향 없음). 초안의 '`TextEditGroup` 따로 만들기'는 Flutter 선택 손잡이·메뉴가 기본 묶음을 쓰므로 기본 묶음 하나로 바꿨다.
- **캔버스 포커스 양보**(수정 2회차 — 총괄 승인 검토, V7): 1차 `EditorCanvasFocus`(`input/editor_shortcuts.dart` 222–230 [확인])는 캔버스 전체를 감싸고(`viewport/page_viewport.dart` 117 [확인]) 포인터 down마다 마이크로태스크로 캔버스 `FocusNode.requestFocus()`를 부른다. 탭 묶음은 `onTapOutside`만 막고 이 요청은 막지 못하므로, 그대로 두면 편집 중 두 손가락 끌기·핀치·거부된 손바닥·펜 전용 한 손가락 끌기·웹 공중 down의 **첫 down**에서 편집기가 포커스를 잃고 `focusLost`로 세션이 끝난다(V7 ① — 6.11.5 표의 '유지'와 어긋남). 그래서 `EditorCanvasFocus`를 이렇게 넓힌다:
  1. **세션 중에는 요청하지 않는다**: 텍스트 세션 동안(`ref.read(editorTextEditProvider) != null`) `_onPointerDown`은 마이크로태스크를 예약하지 않는다. 판정은 그 down을 처리하는 순간의 상태다 — 안쪽 `_InputListener`(라우터)가 같은 down을 먼저 받아 세션 끝(`penContact`)을 시작했고 상태가 이미 `null`이면 1차 경로(요청)로, 아직 `null`이 아니면 요청하지 않고 2로 간다. 끝은 멱등이라(6.11.2) 어느 쪽이든 명령은 한 번이다.
  2. **끝난 뒤 돌려받는다**: `EditorCanvasFocus`가 `editorTextEditProvider`를 `ref.listen`해 `null`이 아니던 값이 `null`이 되면 마이크로태스크로, 그때 주 포커스(`FocusManager.instance.primaryFocus`)가 `null`·포커스 범위 노드(`FocusScopeNode`)·편집기 자신의 노드 중 하나이면 캔버스 `requestFocus()`를 부른다. 다른 입력란(펜 굵기·HEX·대화 상자 등)이 포커스를 가졌으면 빼앗지 않는다(`focusLost` 끝 — V7 ⑤). 포커스된 편집기가 트리에서 빠지면 Flutter 포커스 범위 이력만으로도 캔버스에 돌아오지만(V7 ④) 이 이력에 기대지 않는다 — 키보드 '내림'으로 포커스가 범위 노드에 간 경우(V7 ⑥)와 시트 방식(편집기가 캔버스 밖 패널)도 같은 규칙으로 덮는다. 되찾은 뒤 1차 도구 단축키(P·E·L, 2차 S·T)가 다시 캔버스에서 동작한다(6.7.6).
  3. 그래서 세션 중 `focusLost`의 출처는 6.11.2 주석의 셋(키보드 '내림'·시스템 포커스 이동·다른 입력란)뿐이고, 캔버스 안의 끝은 라우터 표(6.11.5)로만 정해진다. 되찾기 때문에 편집기가 포커스를 잃는 것은 세션이 이미 `null`인 뒤라 `end()`가 아무것도 하지 않는다. 세션이 없을 때의 down은 1차 그대로다(다른 입력란의 `onTapOutside` 뒤 마지막 요청이 이기는 1차 마이크로태스크 규칙 유지).
  4. 웹(`inline`·안 B)에서 브라우저가 캔버스 down 때 숨은 DOM 입력 요소(안 B는 `<textarea>`)의 포커스를 Flutter 포커스와 따로 빼는지는 컨테이너에서 판정할 수 없다 [추측] — B-15 '스크롤·핀치 중 편집 유지'에서 본다. Flutter 쪽 요청이 없으므로 적어도 프레임워크가 연결을 닫지는 않는다.
  5. 시험은 실제 `PageViewport`(1차 `EditorCanvasFocus`·`RawGestureDetector`·`_InputListener` 그대로)에서 한다 — 맨 `Listener` 하네스로는 이 경로가 보이지 않는다(V6의 한계, E2-10 `text_box_test`).
- 글꼴: `ink.InkFonts.ensureLoaded()`를 세션 시작에 부르고(이미 적재됐으면 즉시), 적재 전에는 `textStyleOf`가 주는 대체 글꼴로 보였다가 적재되면 다시 빌드한다(지연 적재 — 7.4.5. 5 s 안에 실패하면 시스템 글꼴 그대로 — 6.21).
- **높이**: 입력 중에는 편집기가 스스로 늘어난다(`maxLines: null`). 오버레이의 frame 높이(배경·선택 프레임)는 (v2.1) `InkTextLayout.measureSync(text, style, widthPt:)`(글꼴 적재 전 `null`이면 편집기 렌더 높이)로 매 글자 갱신하고, 세션 끝에 `InkTextLayout.measure(…)`의 높이를 `frame`에 쓴다(계약 7.2.2 주석). 최소 높이 = 한 줄(`fontSizePt × lineHeight`).
- 카메라가 움직이면(두 손가락 스크롤·핀치·펜 전용 한 손가락 스크롤 — 세션은 유지, 6.11.5) 오버레이가 따라간다(카메라 `ListenableBuilder` — 다시 빌드는 이 레이어만). 편집 중인 페이지가 마운트 범위 밖으로 나가면 세션을 끝낸다(`pageUnmounted`).
- 가상 키보드: iPad 키보드가 올라와도 캔버스를 다시 배치하지 않는다(1차 계획서 6.15 #6). 대신 세션 시작·키보드 높이 변화(`MediaQuery.viewInsetsOf`를 이 레이어만 읽음) 때 상자 아래쪽이 키보드에 가리면 `viewport.revealPageRect`로 그만큼만 스크롤한다. `TextField.scrollPadding`은 0으로 둔다(바깥 `Scrollable`이 없어 쓰이지 않지만 이중 스크롤을 막음).

#### 6.11.4 서식 바

세션 중 상자 위(공간 없으면 아래)에 `TextFormatBar`: `[−] 16 [+]`(크기 6~144, 프리셋 10·12·14·16·20·24·32·48) · 색(최근 색 5 + '더 보기') · **B** · 정렬 3 · 배경(없음/색). 바꾸면 `updateStyle`(명령 아님 — 세션 끝에 한꺼번에). 서식 바는 `TextFieldTapRegion`(편집기와 같은 기본 묶음)으로 감싸 눌러도 세션이 끝나지 않고, 단추는 포커스를 가져가지 않는다(`canRequestFocus: false` — 포커스 잃음이 끝 사유이므로). '더 보기' 색 패널은 HEX 입력란을 뺀 판으로 연다(입력란이 포커스를 가져가면 세션이 끝나므로). 바뀐 서식은 `ToolOptions.textStyle`에도 쓴다(6.2.4).

#### 6.11.5 세션 끝 · 명령

| 세션 | 끝날 때 상태 | 명령 (하나 이하) |
|---|---|---|
| 새 상자 | 내용이 공백뿐 | 없음 |
| 새 상자 | 내용 있음 | `AddObjects(pageId: p, objects: [draft])` |
| 기존 상자 | 글·서식·폭이 그대로 | 없음 |
| 기존 상자 | 바뀜(원본 있음) | `UpdateObjects(pageId: p, objects: [draft])` |
| 기존 상자 | 바뀜, 원본이 원격에서 지워짐(명령 전 동기 검사 — S-1) | `AddObjects(pageId: p, objects: [draft.copyTo(id: 새 id, …)])` |
| 기존 상자 | 내용을 모두 지움 | `RemoveElements(pageId: p, elementIds: [boxId])`(원본이 이미 없으면 명령 없음) |

**끝나는 때**(검토 M-2 → EDITOR-M2 — 캔버스 안은 **라우터가** 정한다):

| 입력 | 세션 | 근거 |
|---|---|---|
| 캔버스의 펜·마우스 **접촉**(E-4 — 웹 공중 `down(0x02)`는 접촉 아님) | 끝(`penContact`) → 그 접촉은 현재 도구로 이어짐 | 6.3.6 3 |
| 캔버스의 손가락 **한 번 탭 확정**(up에서 탭 판정 뒤) | 끝(`canvasTap`), 탭은 소비 | 6.3.5 ⓪ |
| 손가락 길게 누르기 동작 실행 | 끝(`longPress`) → 메뉴 | 6.3.4 |
| 2·3 손가락 탭의 `undo`·`redo`, 툴바 되돌리기 | 끝(`undoRedo`) → 노트 되돌리기 | 6.11.7 |
| 두 손가락 끌기·핀치, 펜 전용(또는 세션 중) 한 손가락 끌기 스크롤, 관성 스크롤 | **유지** — 오버레이가 카메라를 따라감, 편집기 포커스 유지(캔버스가 포커스를 요청하지 않음) | 6.3.4, 6.11.3 |
| 팜 리젝션으로 거부된 접촉(P1~P4), 웹 공중 down, 펜 호버 | **유지** | 6.3.2 |
| 편집기 위의 탭·끌기·두 번 탭·선택 손잡이·붙여넣기 메뉴, 서식 바 | **유지**(`TextField`·서식 바가 받음 — 라우터에 안 옴) | 6.11.3·6.11.4, V6 ④ |
| 편집기 묶음 밖의 down(툴바·하단 패널·시트·앱 바) | 끝(`tapOutside`) | `TextField.onTapOutside` |
| 편집기 `FocusNode`가 포커스를 잃음(iPad 키보드 '내림' 단추, 시스템 포커스 이동, 다른 입력란) — 캔버스 down은 포커스를 가져가지 않으므로 여기에 들지 않음 | 끝(`focusLost`) → 캔버스가 포커스를 되찾음(다른 입력란이 가졌으면 그대로) | 수정 1회차, (수정 2회차) 6.11.3 '캔버스 포커스 양보' |
| Esc, 도구 바꿈, 페이지가 마운트에서 빠짐, 화면 떠남(1차 `flushAll` 앞), 앱 숨김(1차 `AppLifecycleListener`) | 끝(각 사유) | 초안 그대로 |

- 끝은 멱등이다 — 한 동작이 사유 둘을 만들어도(예: 툴바 단추 down = `tapOutside` + 그 단추의 도구 바꿈) 명령은 한 번이다(첫 사유가 이긴다).
- 조합 중(IME `composing`이 유효)인 글자도 내용에 넣는다(Flutter `controller.text`는 조합 중 글자를 포함 — V1). 끝내기 전에 `controller.clearComposing()`을 불러 IME 상태를 닫는다.
- 명령 전 동기 검사(검토 S-1): 기존 상자 세션은 끝에서 `session.pageIfLoaded(pageId)?.objectById(boxId)`를 먼저 본다 — `null`이면 위 표의 '원본이 원격에서 지워짐' 줄(새 id `AddObjects`)이고 `UpdateObjects`를 보내지 않는다. 그래서 '원본 사라짐'과 '읽기 전용'이 갈린다(1차 `_run`은 둘 다 `null`을 돌려줌).
- 명령이 읽기 전용으로 거절되면(경합) 1차 안내를 보이고 숨김을 풀되, (검토 S-11) **쓴 글을 시스템 클립보드에 복사**하고 '편집한 글을 클립보드에 복사해 두었어요'를 함께 보인다(`Clipboard.setData` — 텍스트만, 앱 클립보드는 건드리지 않음). `editor.textDraft` 초안도 지운다(되살려도 다시 거절되므로).
- 길이 한도: `LengthLimitingTextInputFormatter(PageObjectLimits.maxTextLength)`.

#### 6.11.6 웹 IME와 대체안 (00-overview 8장 위험 #4)

Flutter 웹은 편집기마다 숨은 DOM 입력 요소를 두고 IME 조합을 받는다. iPad Safari에서의 한글 조합·자동 완성·받침 이동·변환된 위치(회전·확대)에서의 품질은 실기기에서만 판정된다(B-2·B-15). 그래서 입력 방식을 셋으로 두고 **개발자 메뉴에서 바꿀 수 있게** 한다(EDITOR 내부 `EditorDeviceState.webTextInput`, device, 웹에서만 의미 — 네이티브는 언제나 `inline`. 공개 `EditorSettings`에서 옮김 — 4.3.3).

| 방식 | 구성 | 장점 | 단점 | 등급 |
|---|---|---|---|---|
| `inline`(기본) | 6.11.3의 변환된 `TextField` 오버레이 | 상자 위에서 바로 씀, 코드 하나로 웹·네이티브 | 변환된 입력 요소 위치 때문에 Safari가 화면을 밀거나 조합 표시가 어긋날 수 있음 [추측] | P-A |
| **안 A** `sheet` | 상자를 누르면 화면 **위쪽**에 붙은 입력 패널(EDITOR 자체 UI — 아래 규칙) 안의 변환 없는 여러 줄 `TextField`(서식 바 포함). 입력하는 동안 캔버스의 상자는 같은 id 미리보기로 실시간 반영, [완료]·패널 밖 탭 = 세션 끝 | 변환·회전 없는 평범한 입력란이라 Flutter 웹 입력의 가장 흔한 경로. 순수 Flutter | 상자 위에서 직접 쓰는 느낌이 아님 | P-A |
| **안 B** `textarea` | 웹 전용 `HtmlElementView.fromTagName('textarea')`를 상자 위에 겹치고(CSS로 글자 크기 = `fontSizePt × scale`, 회전 = `transform: rotate`), Safari 기본 IME가 조합을 처리. `input` 이벤트로 `updateText`, `blur` = 세션 끝(`focusLost`). `*_browser.dart`(V2 — `dart:js_interop`만) | 브라우저 자체 입력이라 조합 품질이 Safari 그대로 | 글꼴 차이(DOM은 웹 글꼴 → `NoteSans`를 CSS `@font-face`로 같게 해야 함), 플랫폼 뷰 비용, 서식 바와의 포커스 경계 | P-C |

**안 A(시트 방식) 규칙**(검토 S-8 → EDITOR-M10):

- **미리보기 우선**: 시트 방식도 기존 상자를 E-6대로 숨기고(`hiddenIdsOf` → `{boxId}` — 6.11.2) 같은 id의 초안을 `setPreviewObjects([draft])`로 넣는다. (v2.1) 미리보기는 숨김보다 우선하므로 초안이 보이고 원본은 보이지 않는다(7.2.9 v2.1, X-3 — 초안에서 '숨김이 이기면 미리보기가 안 보임'이던 빈칸). 숨김을 먼저 넣고 미리보기를 넣는 순서에 기대지 않는다.
- **초안 높이**: 미리보기 초안의 frame 높이는 (v2.1) `InkTextLayout.measureSync(text, style, widthPt:)`로 매 글자 갱신한다. `null`(글꼴 적재 전)이면 직전 값을 두고 `measure`의 Future가 오면 고친다(그 사이 줄 수가 늘면 잘려 보일 수 있음 — 적재는 세션 시작에 이미 부름).
- **입력 패널 위치**: 화면 아래쪽 50% 시트는 iPad 가상 키보드(가로에서 화면의 약 40%)에 가린다. 그래서 바닥 시트가 아니라 **에디터 본문 위쪽에 붙은 패널**(툴바 바로 아래, 높이 ≤ 화면의 40%, 편집 중인 상자는 패널 아래 보이는 곳으로 `revealPageRect`)로 띄우고, 키보드 높이(`MediaQuery.viewInsetsOf`)가 있으면 패널 높이를 `min(40%, 화면 높이 − viewInsets.bottom − 툴바 − 120 px)`로 줄인다. 이 패널은 EDITOR 자체 UI라 7.4.10 '바닥 시트' 규칙(다른 영역 UI용)의 대상이 아니다(00-review 3.4 검토 질문 4 답). Safari에서 Flutter 웹이 `viewInsets`를 정확히 받는지는 [추측]이라 위쪽 배치를 기본으로 하고, B-2에서 확인한다.
- 시험: `widget/text_input_sheet_test.dart`에 '`viewInsets.bottom` 400 → 패널이 키보드 위·높이 축소', '미리보기 초안 = getter `previewObjects`의 같은 id이고 `hiddenObjectIds == {id}`(둘 다 넣어도 초안이 그려짐 — 미리보기 우선)', '[완료] → 명령 1회'.

- 순서: E2-01에서 `inline` + `sheet`의 최소판을 먼저 만들어 Chrome 시험(웹 컴파일·세션 규칙 — 9.2)을 통과시키고, **iPad에서 먼저 볼 수 있으면**(12.2 Q1 — Hosting이 있으면, U24) 미리보기로 B-2·B-15를 앞당긴다(수정 2회차: E2-01 미리보기에서는 IME·선택 손잡이만 본다 — B-15의 '스크롤·핀치 중 편집 유지'는 뷰포트 탭 묶음·라우터 끝 규칙·캔버스 포커스 양보가 들어오는 E2-10 뒤에 판정). 결과에 따라 기본값을 `sheet`로 바꾸거나 안 B(E2-11)를 진행한다. 안 B는 B-2가 `inline`·`sheet` 둘 다 불합격일 때만 하고, **시작 전에** 시제품 시험 한 번으로 `HtmlElementView.fromTagName`이 `flutter test --platform chrome` 바인딩에서 실제 `<textarea>`를 만들고 `onElementCreated`를 부르는지 확인한다(V2는 `flutter analyze`만 — 검토 S-9). 안 되면 E2-11의 Chrome 시험은 '컴파일·조건부 export'까지로 줄이고 동작은 B-2 실기기로만 본다.
- 세 방식 모두 같은 `TextEditNotifier`를 쓰므로 명령·되돌리기 규칙(6.11.5)은 같다.

#### 6.11.7 키보드 · 되돌리기와의 관계

- 편집 중 ⌘Z/⌘⇧Z는 편집기(`TextField`)의 글자 되돌리기다(Flutter `UndoHistory`). 노트 되돌리기가 아니다.
- 툴바의 되돌리기 단추·두 손가락 탭(동작 `undo`)·Pencil 동작 `undo`는 **세션을 먼저 끝낸 뒤**(커밋) 노트 되돌리기를 한다 — 결과적으로 방금 세션 전체가 되돌아간다(세션 1회 = 1단계와 맞음).
- 편집 중에는 1차 도구 단축키(P·E·L·S·T)가 글자로 들어간다(캔버스 포커스가 아니므로).

### 6.12 이미지 삽입 · 이미지 페이지 (M5-3·M5-4)

#### 6.12.1 자리

`ref.watch(editorImageImporterProvider)`가 `null`이거나 `sources`가 비면 이미지 관련 UI(삽입 메뉴 '이미지', 페이지 추가 시트 '이미지' 줄, 컨텍스트 메뉴 '이미지 붙여넣기')를 **모두 숨긴다**(E-7).

| `ImageImportSource` | 메뉴 문구 | 아이콘 |
|---|---|---|
| `photos` | 사진 보관함 | `photo_library` |
| `camera` | 카메라로 찍기 | `photo_camera` |
| `files` | 파일에서 | `folder_open` |
| `clipboard` | 붙여넣기 | `content_paste` |

#### 6.12.2 이미지 삽입

1. 삽입 메뉴(6.13) '이미지 › 출처'를 누르면 그 `onPressed` 안에서 `ExtensionRunner`가 `importer.pick(bodyContext, source)`를 **동기적으로 시작**하고(Future를 받아 둠), 그다음 메뉴를 닫고, 그 Future를 기다린다(4.3.1 — 계약 7.2.10·7.4.2 (v2.1), 검토 S-6 → EDITOR-M6). iPad Safari의 파일 선택 input `click()`·`navigator.clipboard.read()`는 사용자 동작 직후에만 열리므로 메뉴 닫힘 애니메이션 뒤로 미루지 않는다. 넘기는 context는 에디터 본문의 것이다(메뉴가 닫혀도 mounted — media는 이 context로 준비 중 시트를 띄운다, CP-PDF-11). 한 번에 하나 — 진행 중이면 메뉴 항목 비활성.
2. `null` → 끝(취소, 안내 없음). 예외 → E-7(보고 + '이미지를 넣지 못했어요').
3. 배치(`ObjectPlacement.forImage`): 대상 = 지금 페이지(1차 `currentPageIndex`), 보이는 영역 `visibleRectPt`(뷰포트와 페이지의 교집합, 비면 페이지 전체). 폭 = `min(pixelWidth × 0.5, visible.width × 0.6, page.width × 0.8)`, 높이 = 폭 × `pixelHeight / pixelWidth`(높이가 `visible.height × 0.6`·`page.height × 0.8`을 넘으면 높이 기준으로 다시), 중심 = `visible.center`(페이지 안으로 클램프), 회전 0.
4. 한도 검사 → `ImageObject(id, pageId, frame, assetId: imported.asset.id, pixelWidth, pixelHeight, createdAt)` → `_runAsync(AddObjects(pageId: p, objects: [image]))` → 성공이면 그 이미지를 `origin: insert`로 선택(본체 끌기 = 이동 — 6.6.2). 노트 화면을 그 사이 떠났으면(`bodyContext.mounted == false`) 명령을 보내지 않는다(에셋은 media가 이미 넣었고 참조가 없으면 1차 에셋 정리가 거둔다).
5. 읽기 전용 노트에서는 메뉴가 비활성이다. `pick` 도중 읽기 전용이 되면 4에서 CORE가 거절 → 1차 안내.

'이미지 붙여넣기'(컨텍스트 메뉴·⌘V)는 출처 `clipboard`로 같은 흐름이고, 위치만 길게 누른 지점(페이지 위면)이 중심이다.

#### 6.12.3 이미지 페이지

- 페이지 추가 시트(1차 `AddPageSheet`)에 줄 '이미지'(`add_photo_alternate`)를 더한다: 출처 단추들. 누르면 그 `onPressed` 안에서 시트의 '위치'(1차 `PagePosition` 선택)를 기억하고 `pick(bodyContext, source)`를 **동기 시작한 뒤** 시트를 닫는다(`Navigator.pop`) — 순서가 초안('닫은 뒤 `pick`')과 반대다(4.3.1, 검토 S-6).
- 페이지 크기: **지금 페이지 크기를 쓰되 방향은 이미지에 맞춘다**(가로 이미지면 가로, 정사각에 가까우면(`0.9 ≤ w/h ≤ 1.1`) 지금 방향). 배경 = `core.ImageBackground(assetId: …, fit: core.ImageFit.contain, paperColorArgb: 지금 페이지 종이 색)`.
- 명령: `InsertPages(drafts: [PageDraft(size:, background:)], position: 기억한 위치)` 1단계 → 1차처럼 새 페이지로 이동.
- 이미지 페이지의 썸네일·렌더는 INK(`ImageBackgroundLayerBuilder`)다. 1차 페이지 패널의 '배경 바꾸기'는 이미지 배경을 고르지 않는다(이번에는 삽입만 — 12.2 Q6).

### 6.13 삽입 메뉴 · 툴바 v2

#### 6.13.1 툴바

```text
[←] [제목…] [▤] │ [펜][지우개][올가미][도형][텍스트] │ [+] [🎤] │ [↶][↷] │ [✋] [100%] [☁] [⋯]
```

- 도형 `interests`·텍스트 `text_fields` 단추는 1차 도구 단추(`ToolButton`)와 같다: 비활성 → 그 도구로, 활성 다시 누름·길게 누름 → 도구 팝업(`ShapeToolPopup`·`TextToolPopup`).
- `[+]`(`add`): 삽입 메뉴(`InsertMenu`, `MenuAnchor`) — 이미지 하위 메뉴(6.12.1, 자리 있을 때) + `insertMenuItems`(목록 순서). 둘 다 비면 단추를 숨긴다(E-7). 읽기 전용이면 비활성.
- `[🎤]`(`mic_none`, 녹음 중이면 `mic` + 빨간 점): `recordingPanel != null`일 때만(6.15.4). 단추 자체(`MicButton`)는 E2-16이 1차 툴바의 되돌리기 단추 앞에 넣고, E2-13은 툴바 v2 배치로 옮기기만 한다(검토 S-3 — 녹음 연동이 툴바 v2를 기다리지 않게).
- 좁은 폭: 툴바 폭 < 720 px(분할 화면 등 — A-6)이면 `[도형][텍스트][+][🎤]`를 `[⋯도구]` 하나로 접는다(메뉴로). 제목은 폭 ≥ 1000 px일 때만(1차 700 → 단추가 늘어서).
- 1차 단추 키는 그대로, 새 키는 부록 C.

#### 6.13.2 `EditorInsertContext` 만들기

```dart
EditorInsertContext insertContext() {
  final index = viewport.currentPageIndex.value; final page = session.pages[index];
  return EditorInsertContext(noteId: noteId, pageId: page.id, pageSize: page.size,
      visibleRectPt: ObjectPlacement.visibleRectPt(viewport, index),   // 6.12.2 step 3
      execute: executeForExtension,                                    // rethrows (6.7.4)
      selectObject: (id) => selections.select(page.id, {id}));         // ignored if not on the page
}
```

- 확장 삽입 항목은 그 `onPressed` 안에서 `ExtensionRunner`가 `onSelected(bodyContext, insertContext())`를 동기 시작한 뒤 메뉴를 닫는다(4.3.1 — 계약 7.2.10 (v2.1)). recog 수식 패드는 그 context로 바닥 시트를 띄우고(`containerOf`는 첫 `await` 전에) 끝에 `execute(AddObjects(pageId:, objects: [math]))` → `selectObject(id)`를 부른다(X30 `done` 규칙 — CP13). `selectObject`로 생긴 선택의 `origin`은 `insert`(6.6.3).

### 6.14 새 펜 선택기 · 펜별 설정 · 레이저 · 테이프 (M5-10~12)

#### 6.14.1 펜 선택기

1차 `PenTypeSelector`는 `isP0` 다섯만 보였다. 2차는 두 줄로 10종 모두:

| 줄 | 펜 (아이콘) |
|---|---|
| 기본 | 볼펜 `edit` · 만년필 `history_edu` · 형광펜 `border_color` · 연필 `create` · 마커 `brush`(1차) |
| 추가 | 붓펜 `draw` · 캘리그래피 `gesture` · 점선 `line_style` · 레이저 `flare` · 암기 테이프 `visibility_off` |

문구(`EditorStrings.penTypeName`)에 다섯을 더한다: 붓펜·캘리그래피·점선·레이저·암기 테이프. 프리셋 바(1차 F-05)는 P1 펜 스타일도 이미 왕복한다(1차 E-07 시험) — 저장·적용은 바꿀 것 없음.

#### 6.14.2 펜별 고급 설정 (`PenExtrasControls` — 펜 설정 팝업 '고급'과 설정 > 펜 섹션)

| 펜 | 조절 | 저장 (`StrokeStyle.extras` — INK 키) |
|---|---|---|
| 붓펜 | (1차 필압 감도·곡선·보정만) | — |
| 캘리그래피 | 펜촉 각도 0~175°(5° 단위, 기본 45), 펜촉 비율 0.1~1(0.05 단위, 기본 0.25), '펜슬 돌리기로 각도 조절'(`capabilities.barrelRoll`일 때만, 기본 켬) | `nibAngleDeg`·`nibAspect`·`rollNib` |
| 점선 | 간격 3단: 촘촘 `[1, 2]` · 보통 `[4, 3]`(기본) · 긴 파선 `[8, 4]`(굵기 배수) | `dash` |
| 레이저 | 사라지는 시간 0.3~5 s(0.1 단위, 기본 1.5 — U11) | `laserFadeMs` |
| 암기 테이프 | 모양 단색·줄무늬 | `tapeStyle` |

바꾸면 `ToolController.updateStyleOf(tool, (s) => s.withInkExtras(…))`(1차 경로 — 정규화·500 ms 디바운스·synced). 미리보기 획(1차 `PenPreview` — INK `PenPreviewPainter`)이 새 펜 모양을 그린다(INK 일).

#### 6.14.3 레이저

- 펜 종류 레이저 = `activeTool: pen` + `penType: laser`. `PenInteraction.end`에서 `session.end()`가 `null`(K-9) → 아무것도 하지 않는다(최근 색 넣지 않음, 녹음 메타 넘기지 않음, 도형 보정 `off`).
- 읽기 전용 노트에서도 **이미 활성인** 레이저는 쓸 수 있게 한다 — 저장하지 않으므로(휴지통 노트 복습·발표). 1차 결정 순서 ②(읽기 전용 → 입력 없음)에 '활성 펜이 레이저면 통과'를 더한다. 도구 단추는 1차처럼 비활성이라 읽기 전용 노트 안에서 새로 고를 수는 없다.
- 레이저 자취 색은 `InkTuning.laserArgb`(INK — (v2.1, CP-INK-7) 계약 문장), EDITOR는 색을 넘기지 않는다(펜 선택기·펜 설정에서 레이저의 색 조절을 숨김).
- 시험은 동시 개발 중 **실제 R2-B3 INK**로 한다 — R2-B3가 이미 레이저 `end() → null`이다(03-ink 4.13, 검토 S-4). 가짜 세션은 만들지 않는다(`StrokeSession`은 `final class`).

#### 6.14.4 암기 테이프

- 그리기: 펜 종류 테이프로 쓰면 보통 획처럼 저장되고(1단계) INK가 cover 층에 그린다.
- 드러내기·가리기: 6.3.5 ②(손가락 탭, 펜 **점** 탭 가로채기 — 4 px·200 ms, 판정은 `end()` 전·가로채면 `cancel()`, v2.1 R-5와 같은 문턱). 테이프 위를 짧게 긋는 획(점보다 긴 것)은 보통 획이 된다. 드러낸 상태는 컨트롤러마다(저장 안 함 — U10). 노트를 다시 열면 모두 가려진다.
- 더보기 메뉴(1차 `EditorMoreMenu`)에 '테이프 모두 보이기' / '테이프 모두 가리기'(그 노트에 테이프가 있을 때만은 알 수 없으므로 언제나 보임). 노트 단위 상태(`editorTapesRevealedAllProvider`)를 두고, 지금 마운트된 컨트롤러에 `setAllTapesRevealed(v)`, 새로 마운트되는 페이지에도 그 값을 적용한다(I-10). (v2.1) INK의 `setAllTapesRevealed`는 '지금 있는 테이프'에만 적용되고 나중에 들어온 테이프는 가려진 채로 오므로, `PageMount`가 그 컨트롤러에 **`updateContent`를 넣은 뒤마다** 노트 단위 값이 `true`이면 `setAllTapesRevealed(true)`를 다시 부른다(모두 보이기 중 새로 그린 테이프·원격에서 온 테이프도 드러남 — 00-review 2.3 INK X-6). 낱개 토글은 그 뒤에 따로 바뀐다.
- 낱개 토글은 **컨트롤러 수명**이다(INK 의미 그대로 — 03-ink 12.2 Q2): 드러낸 테이프가 있는 페이지가 스크롤로 마운트 범위(앞뒤 ±2쪽, 1차 가상화)에서 빠졌다 돌아오면 다시 가려진다. 받아들인다 — 암기 테이프는 '가린 채로 복습'이 기본이고, 노트 단위 '모두 보이기'는 위 규칙으로 유지된다. 실기기 B-6에서 체감을 본다.
- 테이프 위에서 펜으로 쓰기(끌기)는 막지 않는다 — 테이프 위 획은 cover 층 아래라 가려져 보인다(INK L-1).

### 6.15 녹음 연동 (M6-4)

#### 6.15.1 펜 다운 녹음 메타 (R-1, E-5)

```dart
// src/playback/recording_link.dart
abstract final class RecordingLink {
  /// R-1, read synchronously inside pen-down handling (E-5). Laser → empty meta.
  static ink.InkStrokeMeta metaFor(core.AudioRecorderService recorder, String noteId,
      core.PenTool tool);
}
```

- `PenInteraction.start`가 `beginStroke` **바로 앞**에서 부른다(웹은 접촉 순간의 `move` 처리 안 — 6.3.2). 레이저는 빈 메타.
- 도형 도구·텍스트·이미지 객체에는 녹음 필드가 없다(7.2.2) — 연결하지 않는다.
- 일시정지 중·다른 노트에서 녹음 중이면 빈 메타(R-1, U12).

#### 6.15.2 재생 강조 (`PlaybackHighlightLogic` + `PlaybackHighlightDriver`)

결정과 출력을 나눈다(검토 M-1 → EDITOR-M1 — INK 컨트롤러를 가짜로 바꿀 수 없으므로 EDITOR 쪽 이음새로 시험한다).

```dart
// src/playback/playback_highlighter.dart
typedef PlaybackFocusSink = void Function(ink.InkPlaybackFocus? focus);
/// Pure decision (no widgets, no Ticker) — unit/playback_highlight_logic_test.dart.
final class PlaybackHighlightLogic {
  PlaybackHighlightLogic({required this.output, required Set<String> Function() noteRecordingIds,
      required ink.InkPlaybackStyle Function() style});
  final PlaybackFocusSink output;          // widget: every mounted controller (I-9); tests: a recorder
  /// Status event. Tracks the open recording and whether it is ACTIVE (R-5 v2.1): since it was
  /// opened it has been playing at least once, or a seek happened (EDITOR's own tap-to-seek calls
  /// markSeek; a seek from the media panel shows up as positionMs != the value at open).
  /// Returns true when the Ticker should run (phase playing and active).
  bool onStatus(core.PlaybackStatus status, {required int positionMs});
  void onTick(int positionMs);             // same position as last time → no output
  void markSeek();                         // called by tap-to-seek right after seekMs
  ink.InkPlaybackFocus? get current;       // for newly mounted pages
}
```

- **활성 규칙**(계약 R-5 (v2.1), PDF 검토 M-8 → EDITOR-M8 — PDF 패널의 자동 열기는 그대로 두고 EDITOR 쪽에서 푼다, CD2-14): 재생기가 이 노트의 녹음을 연 뒤 **한 번이라도 `playing`이었거나 `seekMs`가 불린 뒤**에만 초점을 넣는다. 그 전(`loading`·`ready` — 패널을 열면 최근 녹음 자동 열기, 녹음 정지 직후 자동 열기)은 `output(null)`이다. 그래서 녹음을 멈춘 직후 이어 쓰는 동안 필기가 흐려지지 않는다(`dimUnwritten`이 위치 0에서 녹음된 획을 모두 흐리게 하던 문제).
  - `seekMs`를 안 방법: EDITOR 탭 재생(6.15.3)은 `seekMs` 직후 `markSeek()`를 부른다. 패널의 탐색 막대(EDITOR 밖의 `seekMs`)는 상태 이벤트를 내지 않을 수 있으므로, 열림을 본 순간의 `positionMs()`를 기억해 두고 **상태 이벤트마다**, 그리고 아직 활성 전이고 패널이 열려 있으면 **250 ms마다** `positionMs()`를 비교한다(외삽 값이라 플랫폼 호출 없음 — 계약 주석). 달라지면 활성이다. 열림 때와 같은 위치로의 탐색은 알아채지 못한다(받아들임 — 그 경우 화면이 그대로라 차이가 없다).
  - 활성은 녹음마다다: `recordingId`가 바뀌거나 `close`(`recordingId == null`)되면 다시 '활성 전'.
- 활성 뒤의 상태별 출력:
  - `playing` → `Ticker` 시작. 매 프레임 `onTick(playback.positionMs())` — 지난 값과 같으면 건너뜀, 다르면 `output(InkPlaybackFocus(recordingId: id, positionMs: pos, style: ink 설정 값))`(I-9).
  - `ready`·`paused`·`completed` → `Ticker` 멈춤, 지금 위치로 한 번 넣음(강조 유지 — 일시정지·탐색 뒤에도 보임).
  - `loading` → 그대로.
- 녹음이 닫히거나(`recordingId == null`) `idle`·`failed`·다른 노트의 녹음이면 `output(null)`, `Ticker` 멈춤.
- 위젯 `PlaybackHighlightDriver`(`EditorBody` 안 `StatefulWidget` + `SingleTickerProviderStateMixin`)는 `audioPlaybackServiceProvider.statusStream`을 듣고 로직에 넘기며, 출력은 마운트된 모든 컨트롤러의 `setPlaybackFocus`다. 새로 마운트되는 페이지(`MountedPages` 리스너)에는 `logic.current`를 바로 넣는다.
- 스타일: `EditorSettings.playbackHighlight`는 (수정 1회차) `ink.InkPlaybackStyle` 그 자체다 — 변환 없음(Q12 답). `recentWindowMs`는 INK 기본(2000). 흐림은 INK 층 4′에서 그려지고 테이프·텍스트·수식 픽셀은 바뀌지 않는다(K-9 v2.1 — EDITOR는 값만 넘김).
- 화면이 가려지면(`AppLifecycleListener.onHide`) `Ticker`를 멈춘다(재생은 media가 계속할 수 있음 — 돌아오면 다시 시작).

#### 6.15.3 탭 재생

- 상태 조건은 6.3.5의 **탭 재생 상태**(R-5 v2.1 — `tapToSeekActive`). 적중: `controller.hitTestRecorded(pagePoint, recordingId: 열린 녹음, tolerance: 12 / scale)` → INK 획 → CORE 획(`session.pageIfLoaded(pageId).strokeById(id)`)의 `recordingOffsetMs`.
- 실행: `await playback.seekMs(max(0, offset − preRollMs))` → `logic.markSeek()` → `await playback.play()`(R-5). 실패는 보고만(재생 오류 표시는 패널 몫).
- 녹음기가 `idle`이 아니면 가로채지 않는다(R-5). media는 녹음기가 활성인 동안 `play()`를 무시하므로(계약 7.2.4 (v2.1), CP-PDF-10) 녹음 중 가로채면 소리 없이 점만 사라진다 — 그래서 조건에서 뺐다(00-review 2.3 X-4).
- `preRollMs` = `editorPreRollMsProvider`(키 `editor.playback.preRollMs` — 정수, synced, 기본 1500, 0~5000으로 클램프, 6.19). 설정 > 페이지 섹션 '필기 재생'에 슬라이더(0~5 s, 0.5 s 단위 — 놓을 때 `set`, 500 ms 디바운스)와 강조 방식(안 쓴 필기 흐리게 / 방금 쓴 필기만 강조)을 둔다.
- 복구된 녹음(M6-5)도 원래 `recordingId`를 지키므로(V16) 같은 경로로 동작한다 — `widget/tap_to_seek_test.dart`에 '복구된 녹음' 경우를 둔다(`FakeAudioRecorder`로 만든 녹음 행에 제목 '복구된 녹음').

#### 6.15.4 녹음 패널 자리 (`EditorPanelSlot`)

- `EditorExtensions.recordingPanel == null`이면 마이크 단추를 숨긴다(계약 주석).
- 마이크 단추 → `editorPanelProvider`(노트 단위, 열림/닫힘) 토글. 열리면 `EditorBody`의 `Column` 맨 아래(페이지 뷰포트 아래)에 `EditorPanelSlot`: `ConstrainedBox(maxHeight: 0.4 × 본문 높이)` + `ClipRect` 안에서 `recordingPanel(context, EditorPanelContext(noteId:, tapToSeek:, setTapToSeek:, close:))`.
  - `tapToSeek`: `EditorSettings.tapToSeek`를 비추는 `ValueNotifier<bool>`(EDITOR 소유 — 계약 주석), `setTapToSeek(v)` → `setTapToSeek` setter(device 저장).
  - `close` → 패널 닫힘. 녹음은 계속된다(패널이 닫혀도 media 녹음기는 그대로).
- 빌더 예외: 빌더 호출을 `try`로 감싸 `FlutterError.reportError` 후 자리에 한 줄 '녹음 패널을 열지 못했어요'(E-7). 빌드 중 예외(하위 위젯)는 Flutter `ErrorWidget` 처리 그대로.
- 마이크 단추 표시: `audioRecorderServiceProvider.statusStream`을 듣고 `isActive && noteId == 이 노트`면 빨간 점(패널이 닫혀도 녹음 중임을 알림). 다른 노트에서 녹음 중이면 회색 점 + 툴팁 '다른 노트에서 녹음 중이에요'.
- 패널을 연 채 노트를 떠나면 패널 상태는 버린다(노트 단위).

### 6.16 `initialFocusRectPt` · 위치 강조 (M7-2~4)

- 노트가 처음 준비되면(1차 `EditorRoot` 'ready' 뒤 첫 레이아웃) `initialPageId`가 있고 노트에 있으면 1차 `commands.navigateToPage(pageId, initialFocusRectPt)`(=`revealPageRect` — 이미 보이면 움직이지 않음, 안 보이면 가운데, 안 들어가면 축소). 마지막 위치 복원(1차 6.3.5)보다 앞선다.
- 그다음 `FocusFlash`: 그 사각형을 6 px 부풀린 둥근 사각형을 `colorScheme.tertiary` 테두리 2 px + 같은 색 20% 채움으로 그리고, 0.4 s 켜짐 → 0.3 s 꺼짐 → 0.4 s 켜짐 → 0.5 s 사라짐(합 1.6 s). 화면 좌표라 카메라를 따라간다. 사용자가 그 사이 입력하면 바로 사라진다.
- 확장 메뉴의 `EditorMenuContext.navigateToPage(pageId, focusRectPt)`(1차 — PDF 검색)도 `focusRectPt`가 있으면 같은 강조를 보인다.

### 6.17 지우개 v2 · 페이지 전체 지우기

- `EraserSettings`에 `eraseShapes`(기본 true — U22)를 더해 `toSpec()`이 `ink.EraserSpec(…, eraseShapes: eraseShapes)`를 넘긴다. JSON `editor.eraser`에 `"eraseShapes": true`(없으면 true). 지우개 패널에 토글 '도형도 지우기'. 텍스트·이미지·수식은 지우개가 지우지 않는다(INK 규칙).
- 획 지우개·**부분 지우개** 모두 도형에 닿으면 도형을 통째로 지운다. 부분 지우개는 INK가 `InkEdit(splitStrokes, removedObjectIds: {…})`를 내고 `toCommand`가 `CompositeCommand([SplitStrokes 또는 RemoveStrokes, RemoveElements(도형)])` 한 개를 만든다(7.2.9 (v2.1) 표, CP-INK-2 승인). EDITOR는 1차 `commitInkEdit` 그대로 보낸다 — 한 제스처 = 한 명령, 되돌리기 1번에 조각과 도형이 함께 돌아온다(`widget/erase_v2_test.dart`, 5.1.2 표).
- '현재 페이지 전체 지우기' 확인 창(1차)에 체크 '도형·텍스트·이미지·수식도 지우기'를 더한다. 지우개 필터가 `all`이면 기본 켬, 형광펜만·형광펜 제외면 숨김(끔). → `ClearPage(pageId: p, filter: f, includeObjects: 체크)` 1단계(v2.1 이름 있는 인자 — C21-07).

### 6.18 설정 저장 형식 v2 (1차 계획서 6.14 확장)

| 키 | scope | 2차에 더하는 것 | 쓰기 |
|---|---|---|---|
| `editor.settings.device` | device | `"tapToSeek": true`(7.4.4 v2.1 — 패널은 `EditorPanelContext`로만 읽고 씀) | 변경 500 ms 뒤 |
| `editor.settings.synced` | synced | `gestures.actions`(4.3.2), `"shapeAssist": true`, `"playbackHighlight": "dimUnwritten"`(`ink.InkPlaybackStyle.name`) | 변경 500 ms 뒤 |
| `editor.toolSelection` | device | `"lastTool"`, `"lastPenType"`, `activeTool`에 `shape`·`text`(6.2.2 폴백) | 변경 500 ms 뒤 |
| `editor.eraser` | synced | `"eraseShapes": true` | 변경 500 ms 뒤 |
| `editor.penStyles` | synced | (형식 그대로) P1 펜의 `extras`(펜촉·점선·레이저·테이프)가 실제로 쓰이기 시작 | 1차 |
| **`editor.toolOptions`** (새) | synced | `ToolOptions.toJson()`(6.2.4) | 변경 500 ms 뒤 |
| **`editor.playback.preRollMs`** (새) | synced | 정수 ms(계약 R-5·7.4.4 (v2.1)가 정한 이름 — `SettingKey.integer`, 1차 `jsonMap` 관례의 예외). `editorPreRollMsProvider`만 읽고 쓴다 | 변경 500 ms 뒤 |
| **`editor.deviceState`** (새, EDITOR 내부) | device | `EditorDeviceState.toJson()`(4.3.3): 웹 입력 방식(개발자 메뉴), 도형 표본 토글(기본 끔), Pencil 스퀴즈·롤 첫 이벤트 | 변경 500 ms 뒤 |
| **`editor.textDraft`** (새, EDITOR 내부, P-B) | device | 긴 텍스트 세션 초안 하나(6.11.2 — 세션 끝·되살리기·버리기에 지움) | 초안 변경 5 s 뒤 |

- 모든 키의 `"v"`는 1 그대로다(필드를 더하기만 함 — 1차 '모르는 키 무시, 빠진 키 기본값' 규칙으로 옛 앱과 섞여도 읽힘). 초안의 `editor.settings.device`의 `"webTextInput"`은 넣지 않는다(공개 `EditorSettings`에서 뺌 — 4.3.3).
- 내부 키 둘(`editor.deviceState`·`editor.textDraft`)은 다른 영역이 읽지 않는 EDITOR 내부 값이라 7.4.4 '키 확정' 목록(다른 영역과 맞물리는 키)에 올리지 않는다 — 1차 `editor.toolSelection`·`editor.viewport`·`editor.presetBar`와 같은 취급이다(12.2 Q15로 확인만).
- (v2.1, 검토 S-10) `EditorSettingKeys.all`의 형을 1차 `List<core.SettingKey<Map<String, Object?>>>`(`state/settings/editor_setting_keys.dart` 44 [확인])에서 **`List<core.SettingKey<Object?>>`**로 바꾼다 — `SettingKey.integer`(=`SettingKey<int>`)를 함께 담기 위해서다(Dart 제네릭 공변이라 `SettingKey<Map…>`·`SettingKey<int>` 모두 들어간다). `all`을 쓰는 곳은 EDITOR 시험 하나뿐이다(통합 HEAD `packages/`·`app/` grep — `test/unit/editor_setting_keys_test.dart` 9 [확인]). 새 키 넷을 더한다(`unit/editor_setting_keys_test.dart`의 개수 단언: P-A 끝에 **device 5 · synced 6**, P-B E2-10b의 `editor.textDraft`까지 넣으면 device 6 — 이름 접두사 `editor.`, `preRollMs`만 정수 키).

### 6.19 provider 목록 추가 (1차 계획서 6.13.2에 더함)

| provider | 범위 | 종류 | 내용 |
|---|---|---|---|
| `editorImageImporterProvider` | 루트(공개) | `Provider<EditorImageImporter?>` | 계약. INFRA override |
| `editorInitialFocusRectProvider` | 노트 | `Provider<Rect?>` | `EditorScreen` override |
| `editorToolOptionsProvider` | 루트 | `NotifierProvider` | 6.2.4 |
| `editorTextEditProvider` | 노트 | `NotifierProvider<TextEditNotifier, TextEditState?>` | 6.11.2 |
| `editorPanelProvider` | 노트 | `NotifierProvider<…, bool>` | 하단 패널 열림 |
| `editorTapesRevealedAllProvider` | 노트 | `NotifierProvider<…, bool?>` | null = 낱개 상태만 |
| `editorActionRunnerProvider` | 노트 | `Provider<EditorActionRunner>` | 6.4.3 |
| `editorExtensionRunnerProvider` | 노트 | `Provider<ExtensionRunner>` | 4.3.1·6.7.4 |
| `editorBarrelRollProvider` | 노트 | `Provider<BarrelRollTracker>` | 6.5.4 |
| `editorRecorderStatusProvider` | 노트 | `StreamProvider<core.RecorderStatus>` | 마이크 단추 표시(펜 다운은 동기 읽기 — 6.15.1) |
| `editorPlaybackStatusProvider` | 노트 | `StreamProvider<core.PlaybackStatus>` | 강조 구동기의 상태 이벤트(탭 재생 판정은 서비스 `status`를 동기로 읽음 — 6.3.5) |
| `editorPreRollMsProvider` (새, 검토 S-10) | 루트 | `NotifierProvider<PreRollMsNotifier, int>` | `editor.playback.preRollMs`(정수 키) 읽기·쓰기, 기본 1500, [0, 5000] 클램프, 500 ms 디바운스 쓰기(1차 setter 규칙). 탭 재생(6.15.3)과 설정 슬라이더가 이것만 읽는다 |
| `editorDeviceStateProvider` (새) | 루트 | `NotifierProvider<EditorDeviceStateNotifier, EditorDeviceState>` | 내부 키 `editor.deviceState`(4.3.3) — 웹 입력 방식·도형 표본 토글·Pencil 첫 이벤트 |
| `editorShapeSamplesProvider` (새, P-B) | 노트 | `Provider<ShapeSampleBuffer>` | 6.20 도형 표본 링 버퍼(토글 켬일 때만 쌓음) |
| `editorPlaybackHighlightProvider` (새) | 노트 | `Provider<PlaybackHighlightLogic>` | 6.15.2 — 구동 위젯과 탭 재생(`markSeek`)이 같은 로직을 씀 |
| `editorTextDraftStoreProvider` (새, P-B) | 노트 | `Provider<TextDraftStore>` | 6.11.2 긴 세션 초안 |

- 1차 규칙 그대로: 노트 단위 provider는 `dependencies`를 밝히고, 루트 `NotifierProvider`를 다른 Notifier의 `build()`에서 바꾸지 않는다(1차 V4).

### 6.20 개발자 표시 · 메뉴 추가 (P-B)

| 항목 | 내용 | 근거 |
|---|---|---|
| 포인터 줄 | 1차 '마지막 포인터 종류' 뒤에 `buttons` 16진수와 접촉 규칙(`native`/`web`), 공중 상태 여부 | E-4 실기기 확인(A-2) |
| 호버 출처 | `flutter(kind)` / `pencilPose(height)` | B-12(웹 Pencil 호버가 `stylus`로 오는가) |
| 녹음 줄 | 녹음기 phase, 마지막 획의 `recordingOffsetMs`, 재생 위치 | A-5, B-8 |
| 텍스트 입력 방식 | 개발자 메뉴: `inline`/`sheet`/`textarea`(웹) — `EditorDeviceState.webTextInput` | 6.11.6 |
| 텍스트 상자 시험 | 개발자 메뉴: 보이는 영역 가운데에 새 상자 세션(키 `editor.dev.textBoxProbe`) — E2-01 진입점 | 6.11.1 |
| **도형 표본 모으기**(토글) · 표본 복사 | 개발자 메뉴(아래 — 검토 S-5 → EDITOR-M11). 초안의 '마지막 획 JSON 복사'는 지웠다 | 조사 03 4.2, U18, LIBRARY 05-library 6.17 |
| 객체 수 | 지금 페이지 `objectCount` / 한도 | 6.22 |

- **도형 표본 링 버퍼**(`tools/shape_samples.dart`, P-B — LIBRARY가 도형 판정기를 실기기 표본으로 고치는 데 쓴다, 00-review 2.3 '도형 표본 형식'):
  - 초안의 '마지막 획 JSON 복사'는 쓸 수 없었다: `Stroke.toJson()`의 점은 base64 코덱이고(CORE `stroke.dart` 149 `StrokePointsCodec.encodeBase64` [확인]) `viewScale`·기대 종류가 없으며, 정작 모아야 할 '글씨가 도형으로 바뀜' 획은 자동 보정 확정 때 원래 획이 저장되지 않아(7.2.3) 커밋 획에 없다.
  - 그래서 EDITOR가 INK에 넘기는 표본을 **자기 링 버퍼**에 둔다: 개발자 토글 '도형 표본 모으기'(`EditorDeviceState.collectShapeSamples`, device, **기본 끔**)가 켜져 있을 때만, `PenInteraction`이 펜 세션마다 `{points: 페이지 pt 중심선 점들(입력 표본 그대로, 세션 끝까지), viewScale: 펜 다운 때 카메라 배율, result: 'stroke' | 'addShape:<ShapeKind.name>', at}`을 **최근 5개**만 메모리에 둔다(저장하지 않음 — 화면을 떠나면 비움). 토글이 꺼져 있으면 아무것도 쌓지 않는다(U18 동의 범위 — 내보낸 것만 사용자가 옮긴다, 00-review 3.4 검토 질문 5 답).
  - 개발자 메뉴 '도형 표본 복사' → 표본 목록 시트(최근 순, 결과 표시) → 하나를 고르면 **기대 종류 선택 시트**(`ShapeKind` 7종 + '도형 아님(글씨)') → LIBRARY 형식 그대로 `{"kind": "<기대 종류 또는 none>", "points": [[x, y], …], "viewScale": s}`(05-library 6.17 끝 형식 — X-6)를 `Clipboard.setData`(텍스트)로 복사. 점은 소수 둘째 자리까지.
  - 시험: `unit/shape_samples_test.dart`(토글 끔 → 0개, 켬 → 6번째가 1번째를 밀어냄, `addShape` 결과 기록, JSON 형식이 LIBRARY 예시와 같은 키·형 — `kind`·`points`(2원소 목록의 목록)·`viewScale`), `widget/dev_menu_test.dart` v2(기대 종류 고른 뒤 클립보드 텍스트).

### 6.21 오류 처리 (새 동작)

| 상황 | 처리 | 사용자에게 |
|---|---|---|
| 명령 거절(읽기 전용 경합 등) | 1차 `_rejected` 표 그대로. INK 경유 편집은 `discardEdit`, EDITOR가 만든 객체 명령은 미리보기만 지움 | 1차 문구 |
| 객체 한도 초과 | 명령을 보내지 않음 | '이 페이지에는 더 넣을 수 없어요(최대 2,000개)' |
| 핸들·꼭짓점·폭 끌기 끝에 원본이 원격에서 사라짐 | **명령 전 동기 검사**(`pageIfLoaded(pageId)?.objectById(id) == null`)로 알아채 명령을 보내지 않고 미리보기만 지움(검토 S-1). 검사와 실행 사이의 경합만 1차 `_rejected` `default:`(보고 + '실행하지 못했어요')로 간다 — 드묾, 받아들임 | 없음(경합 때만 1차 문구) |
| 텍스트 세션 끝에 원본이 사라짐 | 같은 동기 검사 → `UpdateObjects` 없이 새 id로 `AddObjects`(6.11.5) | 없음 |
| 텍스트 세션 끝의 명령이 읽기 전용으로 거절 | 1차 안내 + 쓴 글을 시스템 클립보드에 복사, `editor.textDraft` 지움(6.11.5 — 검토 S-11) | 1차 문구 + '편집한 글을 클립보드에 복사해 두었어요' |
| 자리 콜백 예외(메뉴 항목·`pick`·패널 빌더) | `FlutterError.reportError(library: 'feature_editor')`(E-7) | '실행하지 못했어요' / '이미지를 넣지 못했어요' / '녹음 패널을 열지 못했어요' |
| `isVisible` 예외 | 그 항목 숨김 + 보고(메뉴 열림마다 항목당 1회) — E-7 (v2.1) 예외 | 없음 |
| 자리 콜백이 끝났는데 노트 화면이 이미 닫힘(`bodyContext.mounted == false`) | 결과 버림(명령·스낵바 없음) | 없음 |
| 재생기 `seekMs`·`play` 실패 | 보고만 | 없음(패널이 상태로 보임) |
| `InkTextLayout.measure` 실패·2 s 초과, `measureSync`가 `null` | 오버레이의 마지막 렌더 높이를 쓴다 | 없음 |
| `InkFonts.ensureLoaded` 실패(v2.1 — 5 s 상한 뒤 실패로 끝남) | 시스템 글꼴로 편집(저장되는 글은 같음, INK 렌더는 INK 규칙) | 없음 |
| `stylusExtrasProvider.events` 오류 | 무시 | 없음 |

### 6.22 성능 목표 (1차 계획서 6.15 #9에 더함 — `unit/performance_smoke_test.dart`, VM, 다른 영역과 CPU 공유)

| 측정 | 목표 |
|---|---|
| 펜 다운 추가 비용(접촉 판정 + 녹음 메타 + 롤 각) 1만 회 | < 20 ms |
| 재생 강조 한 프레임의 EDITOR 몫(`positionMs` + 마운트 8쪽 `setPlaybackFocus` 호출, INK 그리기 제외) 1천 회 | < 50 ms |
| 획 5천 + 객체 200 페이지에서 혼합 선택(전부) 회전 미리보기 한 번(`setPreviewTransform`) | < 2 ms(EDITOR 몫) |
| 도형 끌기 move 1천 회(`ShapeDrafts.geometry` + `setPreviewObjects` 호출) | < 30 ms(EDITOR 몫) |
| 붙여넣기 `instantiate` 획 2천 + 객체 200 | < 20 ms |
| 텍스트 편집 중 글자 1개 입력이 캔버스(`PageViewport`의 페이지 슬롯)를 다시 빌드하지 않음 | 다시 빌드 0회(빌드 수 계수) |

- **EDITOR 몫의 정의와 여유 규칙**(검토 S-12(d)): 'EDITOR 몫'은 INK 호출을 포함한 그 경로 전체를 잰 값이다(INK를 떼어 내지 않는다 — 가짜 INK가 없으므로). 목표는 그 전체 값에 대한 상한이고, 1차 성능 스모크의 여유 규칙을 그대로 쓴다: 한 번 데운 뒤 5회 재서 **가장 짧은 값**을 상한과 비교(공유 CPU에서 한 번이 느려져도 흔들리지 않게 — 1차 `unit/performance_smoke_test.dart` 머리 주석 [확인]), 타이머·대기 없음(`fakeAsync`).
- 실기기 목표(1차 PLAN 5.4): 필기 지연 20 ms — 2차가 펜 다운 경로에 더하는 일은 위 첫 줄뿐이다. 재생 강조 중 iPad 스크롤이 1차와 같은 프레임 시간인지 B-8에서 개발자 표시로 본다.

### 6.23 웹 · 네이티브 차이

| 기능 | 웹(iPad Safari) | 안드로이드 APK | iPad 네이티브(TF 뒤) |
|---|---|---|---|
| 접촉 판정 | `web` 규칙(접촉 비트) | `native` | `native` |
| S펜 버튼 | (안드로이드 Chrome에서만) 접촉 비트 + 버튼 비트 | 버튼 비트 0x02 | 해당 없음 |
| 지우개 끝(`invertedStylus`) | 오지 않음(웹 엔진이 만들지 않음 — 조사 02 8.4) | 지우개 끝 있는 펜 | 해당 없음 |
| Pencil 더블탭·스퀴즈·롤·포즈 | 없음, 설정 줄 숨김 | 없음 | `pencil_bridge` → 6.5 |
| 호버 커서 | `kind: stylus` 호버(1차) | 스타일러스 호버(1차) | `StylusHoverPose`(6.5.3) |
| 캘리그래피 각 | 고정 각 | 고정 각 | 롤 반영(옵션) |
| 텍스트 입력 | 방식 셋(6.11.6) | `inline` | `inline` |
| 이미지 출처 | media가 주는 것(사진·카메라·파일 + 클립보드 API가 있으면 붙여넣기) | 같음(클립보드 없음) | 같음 |
| 재생 강조·탭 재생 | 같음 | 같음 | 같음 |

플랫폼 판정은 `kIsWeb`(접촉 규칙·텍스트 입력 방식의 기본값) 하나뿐이고, 나머지는 서비스 능력(`capabilities`, `sources`, 자리 null 여부)으로 정한다(7.4.1).

### 6.24 import 규칙 v2 (1차 계획서 6.16 확장)

- 1차 규칙 ①~⑤ 그대로(SDK Material·Cupertino 금지, `lib/`의 플랫폼 import 금지, 다른 패키지 `src/` 금지, `testing*.dart` 금지, `setViewport`·`discardPending` 호출 금지, 피처끼리 import 금지).
- **예외 하나(P-C, 안 B를 할 때만)**: `lib/src/text/textarea_overlay_browser.dart`에서만 `dart:js_interop`·`dart:js_interop_unsafe`를 허용한다(INFRA R4 `web_only_imports`·`web_suffixes`와 같은 규칙). `package:web`·`dart:html`은 여전히 금지. `unit/no_platform_imports_test.dart`가 이 파일 하나만 예외로 두는지 검사한다.
- **새 금지**: `lib/`에서 `package:media_io/`·`package:ink_recognition/`·`package:pencil_bridge/` import(7.1 규칙 4 — 피처 ↔ 서비스). test에서도 금지(EDITOR 시험은 가짜만 — 7.4.6).
- `dart:io` `Platform` 금지는 1차와 같이 `lib/` 전체(플랫폼 파일이 없으므로).

---

## 7. 외부 패키지

7.5 고정표에 `feature_editor` 행 변화는 없다. 새 외부 의존을 넣지 않는다.

| 패키지 | 버전 | 쓰는 곳 | 비고 |
|---|---|---|---|
| `flutter_riverpod` | 3.4.3 | lib | 1차 7.5 고정값 그대로 |
| `material_ui` | 1.10.0 | lib·test | 새 아이콘 전부 있음(V3) |
| `collection` | 1.19.1 | lib | `ListEquality`·`MapEquality`·`SetEquality` |
| `meta` | 1.19.0 | lib | `@immutable` |
| `fake_async` | 1.3.3 (dev) | test | 녹음 시계·재생 `Ticker`·디바운스 시험 |
| `note_core`·`ink_engine` | `any`(형제) | lib·test | `testing.dart`는 test에서만 |
| (SDK) `dart:js_interop`·`dart:js_interop_unsafe` | Dart 3.13.7 | `text/textarea_overlay_browser.dart`(P-C) | pub 의존 아님(V2) |

넣지 않음: `super_clipboard`(시스템 클립보드 — 1.3), `package:web`(안 B도 SDK로 충분 — V2), 플러그인 전부(R16 — 피처 패키지).

---

## 8. 작업 분해

각 작업은 **완료 조건의 시험이 통과하면 완료**다(경로는 `packages/feature_editor/test/` 기준). 모든 작업 공통 조건(1차와 같음): 루트 `flutter analyze --fatal-infos` 0건, `dart format` 변경 없음, 그때까지의 패키지 시험 통과, `ws check` 위반 0. 시험은 평소 패키지 단위(`cd packages/feature_editor && flutter test <파일>`)만 돌리고, 체크포인트에서만 패키지 전체·Chrome을 돌린다(00-overview 5장 부하 규칙).

### 8.1 기반 단계 R2-B5 (동시 개발 시작 전 `main`에 커밋 — 7.6)

| ID | 작업 | 선행 | 완료 조건 |
|---|---|---|---|
| R2-B5 | 7.2.10 공개 표면 전부: `EditorExtensions` v2(새 필드 셋, `==`), `EditorSelectionContext`·`EditorSelectionMenuItem`·`EditorInsertContext`·`EditorInsertMenuItem`·`EditorPanelBuilder`·`EditorPanelContext`, `EditorImageImporter`·`editorImageImporterProvider`(기본 `null`), `EditorScreen.initialFocusRectPt`(받기만 — scoped provider에 넣음, 동작 없음), `EditorGesture`·`EditorAction`·`GestureSettings` v2(4.3.2 — `actionFor`·`defaultFor`·`allowedFor`·JSON 왕복·`withAction`), Stylus v2 타입(`StylusPreferredAction`·`StylusSqueezePhase`·`StylusDoubleTap`/`StylusSqueeze` 선택 인자·`StylusHoverPose`·`StylusCapabilities`·`StylusExtrasSource.capabilities`, (v2.1) `StylusExtraEvent.timestamp`·`super.timestamp`), `NoStylusExtras.capabilities`, 4.3.3 `EditorSettings` 새 필드 3개(`playbackHighlight`는 `ink.InkPlaybackStyle` — 모델·JSON만, 적용은 동시 개발), export 목록 v2(4.1 — 새 이름 14개). 1차 라우터·호스트는 바꾸지 않는다(bool이 그대로 있어 컴파일·동작 유지) | R2-B2(CORE 묶음), R2-B3(INK) | `widget/smoke_test.dart`(가짜 저장소로 `EditorScreen(initialFocusRectPt: …)` 표시·닫기), `unit/api_surface_test.dart`(export = 4.1 목록 — `PlaybackHighlightStyle`·`WebTextInputMode` 없음), `unit/gesture_settings_test.dart`(v1.4 JSON `{"twoFingerUndo":false,…}` → `actionFor(twoFingerTap) == none`, `actions` 왕복, 모르는 제스처·동작·`allowedFor` 밖 값 무시, `withAction`이 기본값이면 명시 항목을 지움(bool `false` 제스처 예외), `toJson` bool = `action != none`, 표 7행 기본값·허용값 전부), `unit/stylus_extras_test.dart`(`NoStylusExtras().capabilities == StylusCapabilities.none`, 새 이벤트 값 동등 — `timestamp`가 다르면 다름), `unit/editor_extensions_test.dart`(새 필드 `==`·기본값), `unit/editor_settings_test.dart`(새 필드 JSON 왕복·기본값·모르는 값, `playbackHighlight` JSON 이름 = `InkPlaybackStyle.name`) |

### 8.2 동시 개발

등급은 3.4(P-A 2차 완료 조건, P-B 미뤄도 완료, P-C 여유 있으면). '선행'의 R2-Bx는 기반 단계. (수정 1회차, 검토 S-3 → EDITOR-M13) E2-04·E2-07을 나눴고(E2-04a·b, E2-07a·b·c), E2-16의 선행에서 E2-13을 뺐고(마이크 단추는 E2-16이 만듦), E2-01이 자기 진입점(개발자 메뉴 '텍스트 상자 시험')을 만든다.

| ID | 작업 | 등급 | 선행 | 완료 조건 (시험 파일) |
|---|---|---|---|---|
| E2-00 | 정리: import 규칙 v2(6.24 — 서비스 패키지 금지, `*_browser.dart` 한 파일 예외 자리), 문구 상수 추가(1.2 표의 모든 새 문구 — 해요체), 시험 도우미 v2(`pumpEditor`가 객체·녹음 시드, `PointerDriver`에 펜 버튼·웹 공중 → 접촉 순서·지우개 끝, `FakeStylusExtras`, `FakeImageImporter`(호출 시점 기록 — 6.12.2), `fake_extensions.dart`, `ink_edit_builders.dart`, `mapping_table.dart`). 재생 호출 기록은 CORE `FakeAudioPlayback.calls`(CP-8 — 감싸개 없음) | P-A | R2-B5 | `unit/no_platform_imports_test.dart`(v2 규칙 — 검사 자체 시험은 `lib/`가 아니라 **임시 폴더에 만든 가짜 트리**(위반 파일 하나)로 돌려 다른 검사·분석과 겹치지 않게 — 검토 S-12(e)), `unit/helpers_smoke_test.dart`(새 도우미: 펜 버튼 0x02 down이 `Listener`에 그대로, 웹 순서 `down 0x02 → move 0x03 → move 0x02 → up` 재생, 가짜 가져오기가 가짜 저장소에 에셋을 넣고 `ImportedImage` 반환, 가짜 Pencil 이벤트 주입) |
| E2-01 | **텍스트 입력 시제품(첫 작업 — 위험 #4)**: `TextEditNotifier` 최소판(새 상자·기존 상자, 세션 끝 = 명령 하나, 끝 사유 — 라우터 쪽 연결은 E2-10), `inline` 오버레이(`material_ui` `TextField` collapsed + `textStyleOf`·`strutStyleOf` + 변환, 위쪽 형제 배치), 안 A `sheet` 최소판(위쪽 패널·미리보기 우선), 개발자 메뉴 입력 방식 전환(`EditorDeviceState`·`editorDeviceStateProvider`·내부 키 `editor.deviceState`를 이 작업에서 만든다 — 4.3.3)·**'텍스트 상자 시험' 진입점**(6.11.1 — E2-03 없이 돌게, 검토 S-3) | P-A | E2-00 | `unit/editor_device_state_test.dart`(JSON 왕복·모르는 값 → 기본값·`seenSqueeze` 기록), `unit/text_edit_session_test.dart`(세션 끝 표 6.11.5 경우 전부 → 명령 0/1개·`undoDepth`, 멱등 `end` 두 번(사유 둘) → 명령 1개·첫 사유, 조합 중 글자 포함, `hiddenIdsOf` 표), `widget/text_box_inline_test.dart`(개발자 메뉴 '텍스트 상자 시험' → 편집기 포커스, 편집기 `TextField`의 `style == textStyleOf(style)`·`strutStyle == strutStyleOf(style)`·장식 `contentPadding == EdgeInsets.zero`, 한글 조합 값 주입(V1 방식) → 툴바 자리 탭(`tapOutside`) → `AddObjects` 1회·`content.objects`에 '안녕', 회전·확대 상태에서도 같음, iOS 변형: 두 번 탭 → 낱말 선택·`AdaptiveTextSelectionToolbar`, 메뉴를 눌러도 세션 유지(V6 ④)), `widget/text_input_sheet_test.dart`(패널이 본문 위쪽·높이 ≤ 40%, `viewInsets.bottom` 400 → 패널이 키보드 위로 줄어듦, 입력 중 getter `previewObjects`에 같은 id 초안·`hiddenObjectIds == {id}`(미리보기 우선), 초안 높이 = `measureSync` 값, [완료] → 명령 1회), `web/text_input_browser_test.dart`(`@TestOn('browser')`, `setUpAll(useInkTestFonts)`: **웹 컴파일·세션 규칙** — Chrome에서 `tester.enterText('안녕 hello')` → 세션 끝 → 객체 텍스트 일치, `inline`·`sheet` 둘 다. IME 판정은 하지 않음 — B-2·B-15, 검토 S-9) |
| E2-02 | 문서 v2: `PageMount`가 `objects` 전달, 새 마운트에 재생 초점·테이프 상태 적용 자리, **`updateContent` 뒤 테이프 '모두 보이기' 다시 적용**(I-10), 선택 재검증 `elementById` | P-A | E2-00 | `unit/page_mount_test.dart` v2(객체가 든 페이지 `load` → `InkPageContent.objects` 일치, `AddObjects`·`UpdateObjects`·`RemoveElements`·되돌리기 → `updateContent` 1회씩, 리스너 안 `execute` 없음, '모두 보이기' 켬 + 원격 테이프 획 추가 → `updateContent` 뒤 `isTapeRevealed(새 id) == true`), `unit/selection_revalidate_test.dart`(객체 id 사라짐 → 선택에서 빠짐, 모두 사라짐 → 해제, 끌기 중 무시, `origin` 유지) |
| E2-03 | 도구 모델 v2: `EditorTool` + shape·text, `lastTool`·`lastPenType`·`swapWithLast`, 저장값 폴백(6.2.2), `ToolOptions`·`editorToolOptionsProvider`(`editor.toolOptions`), `EditorSettingKeys` v2(`all` 형 `List<SettingKey<Object?>>`, 새 키 `toolOptions`·`playback.preRollMs` — `deviceState`는 E2-01, `textDraft`는 E2-10b가 더함)·`editorPreRollMsProvider` | P-A | E2-00 | `unit/tool_controller_test.dart` v2(모르는 `activeTool` `"ruler"` → `pen`·오류 보고 0, 문자열 아님 → `pen`·보고 1, `lastTool` 저장·복원, `swapWithLast` 왕복, 1차 지우개 `previousTool` 규칙 그대로), `unit/tool_options_test.dart`(JSON 왕복·잘못된 값 → 기본값·화살표 `arrowHeads` 규칙·변 수 3~12 클램프·synced 저장 500 ms), `unit/editor_setting_keys_test.dart` v2(그때까지 더한 키 목록과 같음 — P-A 끝에 device 5 · synced 6, E2-10b 뒤 device 6, 접두사 `editor.`, `preRollMs`만 정수 키), `unit/pre_roll_test.dart`(기본 1500, 9000 → 5000·−1 → 0 클램프, 500 ms 디바운스 쓰기) |
| E2-04a | 입력 v2 ①: `StylusContactRule`·공중/접촉 상태(6.3.2 — E-4 v2.1 접촉 끝 포함), 접촉 순간 제스처(6.3.3), `beginInteraction(gesture:)`, 펜 버튼·지우개 끝 임시 도구(6.2.3), `noteStylusPoseHover` | P-A | E2-00, E2-03 | `unit/stylus_contact_test.dart`(규칙 × 버튼 비트 표 전부), `unit/input_router_test.dart` v2 — 1차 R1~R33 그대로 + **R34** 웹 `down 0x02` → 상호작용 없음·호버 커서 갱신, **R35** 이어 `move 0x03` → 그 지점에서 `penButton` 상호작용 시작, **R36** 접촉 중 `move 0x02` → `end` 1회·이후 `move 0x03` → 새 상호작용, **R37** 네이티브 `down 0x02` → 바로 `penButton`, **R38** 네이티브 `down 0x01` → 제스처 없음, **R39** `invertedStylus` → `invertedStylus`, **R40** 획 도중 버튼 눌림/뗌 → 상호작용 그대로, **R41** 띄운 채 버튼 토글(호버 `buttons 0x02`) → 아무것도 없음, **R42** 공중 down 동안 손가락 down → 팜 리젝션 P2(펜 활동)로 거부, 마우스 오른쪽 버튼은 1차 그대로 |
| E2-04b | 입력 v2 ②: 손가락 탭·길게 누르기를 `actionFor`로(6.3.4), 펜 점 탭 판정 문턱(4 px·200 ms)·`end()` 전 가로채기 훅(`interceptPenDot` — 6.3.5), 텍스트 세션 중 손가락 = 펜 전용 처리·세션 끝 신호(`InputPolicy.textSessionActive` — 6.3.4) | P-A | E2-04a | `unit/input_router_test.dart` v2 — **R43** 2 손가락 탭 `actionFor == none` → `tapGesture` 안 옴, **R44** `redo`로 바꾸면 `tapGesture(2)`, **R45** 길게 누르기 `none` → 타이머 없음, **R46** 포즈 호버 뒤 `penCooldown` 안 손가락 → 거부(`treatHoverAsPenActivity`), **R47** 펜 3 px·150 ms 접촉 → 펜 점 탭으로 `interceptPenDot` 1회·가로채면 `cancel` 1회·`end` 0회, **R48** 펜 6 px 또는 250 ms → 점 탭 아님(`end` 1회, 훅 0회), **R49** 세션 중(`textSessionActive`) 손가락 필기 모드에서 한 손가락 down → 상호작용 없음·끌기 = 스크롤, **R50** 세션 중 두 손가락 끌기·핀치 → 세션 끝 신호 0회, **R51** 세션 중 한 손가락 탭 → `tapGesture(1)` 1회, **R52** 세션 중 거부된 손바닥 down(P1) → 신호 0회 |
| E2-05 | 제스처 동작 실행기(`EditorActionRunner` 6.4.3)·호스트 `tapGesture` 연결·설정 UI(6.4.4)·`EditorSettings` 새 setter | P-A | E2-04b | `unit/editor_action_runner_test.dart`(동작 11개 각각의 결과 — 도구·팝업·undo/redo 호출, 상호작용 중 무시, 읽기 전용 규칙), `widget/gesture_settings_section_test.dart`(줄 7개 + 고정 3줄, Pencil 줄은 `capabilities`일 때만·스퀴즈 줄은 `seenSqueeze`까지, 웹에서 '펜 뒤쪽 지우개' 줄 없음, 시트에 `allowedFor` 값만, 고르면 `editor.settings.synced`에 `actions` 기록, [기본값으로]), `widget/undo_redo_test.dart` v2(2 손가락 탭을 `redo`로 바꾸면 redo 1회, `none`이면 아무것도) |
| E2-06 | 선택 v2: 혼합 선택(`allIds`), **선택 우선 (a′)**(6.6.2 — `selectionPriority`·`origin`)·이동 시작 문턱·선택 탭, 탭으로 객체 선택(올가미·도형 도구), 프레임 v2(축 정렬·회전된 프레임·회전 핸들), 회전 끌기(15° 맞춤·절대/상대 각 — 폴리라인은 상대)·각도 꼬리표, 90° 돌리기, 붙여넣기·복제 뒤 도구 유지 | P-A | E2-02, E2-04a | `unit/selection_hit_test_test.dart` v2(회전된 프레임의 핸들 위치·적중, 회전 핸들, 8방향), `unit/selection_priority_test.dart`(6.6.2 표 전부: 도구 × `origin` × 핸들/본체/밖), `widget/lasso_mixed_test.dart`(획 3 + 도형·텍스트·이미지 올가미 → `elementIds` 6, 이동 → `transform` 1단계·객체 `frame`도 이동, **펜 도구 + 올가미 선택 본체 끌기 → 이동**, **펜 도구 + 붙여넣은 선택 본체 끌기 → `TransformElements` 1회(이동)·획 0**(검토 M-4), 문턱 안 탭 → 명령 0), `widget/rotate_test.dart`(회전 핸들 47° 끌기 → 45°로 맞춤·1단계, 단일 이미지 절대 각 맞춤(처음 10° → 끌어 **32°** → 30° — 경계값 33°를 쓰지 않음, 검토 S-2), 20° → 맞춤 없음, 폴리라인 도형은 상대 각·꼬리표 상대 각, 90° 돌리기 → 1단계, 실패 주입 → `discardEdit`·선택 유지), `goldens/selection_frame_v2_golden_test.dart`(다중 프레임·회전 중 프레임·단일 회전 객체 프레임·회전 핸들 — INK 출력은 빈 페이지 고정) |
| E2-07a | 클립보드 v2(`ElementClipboardNotifier` — 이름 바꿈), 붙여넣기 v2(합성 명령 규칙·한도·`origin: paste`), 컨텍스트 메뉴 v2(붙여넣기·이미지 붙여넣기 자리), 단축키 ⌘X·⌘D·S·T(텍스트 편집 중 양보) | P-A | E2-06 | `unit/element_clipboard_test.dart`(1차 시험 옮김 + 객체: 새 id·`copyTo`·`createdAt + i`가 획과 객체를 통틀어 z 순서, `UnknownObject`는 제자리, 이미지 `assetId` 유지), `widget/paste_test.dart`(다른 페이지 붙여넣기 → 획만이면 `add-strokes`·혼합이면 합성 1개·도구 그대로·`origin == paste`, 한도 초과 → 안내·명령 0), `widget/shortcuts_test.dart` v2(⌘X·⌘D·S·T, 텍스트 편집 중 양보 — ⌘V는 편집기 글자 붙여넣기) |
| E2-07b | 선택 메뉴 v2(잘라내기·색·복제·더보기·넘침), 색 팝업·`recolor` | P-A | E2-07a | `widget/selection_menu_test.dart`(항목·읽기 전용 비활성·이미지만 선택 시 '색' 숨김·`UnknownObject`만이면 색·돌리기 숨김, 잘라내기 → 클립보드 내용 + `RemoveElements` 1단계, 복제 → 합성 1단계·새 요소 선택), `widget/recolor_test.dart`(도형·텍스트·획 혼합 → 합성 1단계, 실패 주입 → `discardEdit`) |
| E2-07c | **확장 항목 `selectionMenuItems`** + `EditorSelectionContext` + `ExtensionRunner`(E-7, **동기 시작·본문 context** — 4.3.1) | P-A | E2-07b | `widget/selection_extensions_test.dart`(시험 항목이 받은 문맥의 `strokes`·`objects`가 z 순서·`boundsPt`, `execute` 1회 = `undoDepth` +1, `execute`가 읽기 전용에서 다시 던짐, **`onSelected`가 막대 닫힘 전에(같은 `onPressed` 안에서) 불림·받은 context가 `EditorBody`의 것이고 메뉴가 닫힌 뒤에도 mounted**(검토 S-6), 동기 예외도 메뉴는 닫힘, `isVisible` false → 숨김, `isVisible` 예외 → 숨김 + 보고 1회·스낵바 0, `onSelected` 예외 → 보고 1회 + 스낵바, 빈 목록 → 막대에 없음(E-7), 3개 이상 → '⋯'로 넘침), `unit/extension_runner_test.dart`(두 번 누름 무시, 화면이 닫힌 뒤 끝나면 결과 버림) |
| E2-08 | 단일 객체 핸들·꼭짓점 편집(6.6.5): `ObjectResize`(**`cornerScale`** 포함), `ObjectEditInteraction`(`setPreviewObjects` → 명령 전 동기 검사 → `UpdateObjects`), 텍스트 폭 핸들, 이미지 비율 고정 풀기, 직선·화살표 끝점, 다각형 꼭짓점 모드(**별은 P-C**) | P-A (별 P-C) | E2-06 | `unit/object_resize_test.dart`(폴리라인 변 끌기 → 점 배율, 회전 타원 변 끌기 → 지역 축 `rect`·각 유지, 텍스트 폭 최소 40 pt, 최소 크기 멈춤, 끝점 각도 맞춤, **`cornerScale`: 30° 회전 이미지(frame 200×100) 오른쪽 아래 모서리를 대각선 방향으로 끌기 → 반대(회전된 왼쪽 위) 모서리 좌표 그대로(오차 1e-9)·비율 2:1 유지·`rotation` 그대로, 대각선에 수직인 delta → 배율 1, 반대 모서리를 넘어 끌기 → 최소 크기에서 멈춤, 회전 0이면 `SelectionGeometry.resize(keepAspect: true)` 결과와 같음**(검토 S-2 → EDITOR-M5)), `widget/object_handles_test.dart`(종류별 핸들 개수 = 6.6.4 표, 변 끌기 → `UpdateObjects` 1단계·같은 id, 끌기 중 getter `previewObjects`에 같은 id·끝에 빈 목록, 회전된 텍스트 상자 모서리 끌기 → `TransformElements` 1단계·`fontSizePt × s`(CP-2), **원격 삭제 뒤 끝 → 명령 0·스낵바 0·`FlutterError` 보고 0·미리보기 지움**(검토 S-1)), `widget/vertex_edit_test.dart`(직선 끝점 → `UpdateObjects`, '꼭짓점 편집' 켬 → 다각형 점 N개 핸들, 선택 해제 → 꺼짐, `shapeKind` 그대로) |
| E2-09 | 도형 도구: `ShapeToolPopup`·`ShapeStyleControls`, `ShapeInteraction`·`ShapeDrafts`(맞춤), 그린 뒤 선택(`origin: drawn`), 선택한 도형 스타일 변경(단일·여럿) | P-A | E2-03, E2-06 | `unit/shape_drafts_test.dart`(7종 기하 = CORE 템플릿 결과, 직선 14° → 15° 맞춤·20° 그대로, 정비율 문턱 0.06, Shift·Alt), `widget/shape_tool_test.dart`(끌기 → getter `previewObjects`에 미리보기 → `AddObjects` 1단계·새 도형 선택(`drawn`)·도구 그대로, **방금 그린 사각형 안에서 원 끌기 → `AddObjects` 1회(새 원)·사각형 `frame` 그대로·선택 = 새 원**(검토 M-4), 방금 그린 사각형의 모서리 핸들 끌기 → 크기 조절(핸들 우선), 8 px 미만 → 탭(객체 선택 `tap`), 탭 선택한 도형 본체 끌기 → 새 도형, 취소 → 명령 0, 읽기 전용 → 없음, 한도 초과 → 안내·명령 0, **(수정 3회차) 자동 도형 확정 커밋 경로**: `ink_edit_builders`의 `InkEdit(addShape)`(R2-B3 `InkEditKind.addShape`)를 마운트된 페이지 컨트롤러로 1차 `commitInkEdit` → `AddObjects` 1단계·획 없음·`content.objects`에 `ShapeObject` 1개 — 5.1.2 '자동 도형 보정 확정' 행을 덮는 P-A 시험이고 `mapping_table`이 이 파일을 가리킨다), `widget/shape_style_test.dart`(팝업 값 → `editor.toolOptions`, 선택 도형 3개 색 바꿈 → `UpdateObjects` 1단계, 직선에 채우기 줄 없음) |
| E2-10 | 텍스트 상자 완성: 6.11.1 시작 규칙 전부(끌어 폭 정하기 — 테두리는 EDITOR overlay), 서식 바(`TextFieldTapRegion`·포커스 안 가져감), `InkFonts` 지연 적재, `measureSync`·`measure` 높이, `hiddenIdsOf` → `setHiddenObjectIds`(E-6), 뷰포트 `TextFieldTapRegion(enabled: 세션)`, (수정 2회차) **`EditorCanvasFocus` 세션 중 포커스 양보·끝난 뒤 되찾기**(6.11.3 '캔버스 포커스 양보' — 1차 `editor_shortcuts.dart` 222–230을 넓힘), **라우터 기반 세션 끝**(6.11.5 표 전부 — 펜 접촉·한 손가락 탭·길게 누르기·포커스 잃음·묶음 밖 down), 키보드 높이 따라 스크롤, 원본 사라짐 → 새 상자(동기 검사), 읽기 전용 거절 → 클립보드 복사, 선택 메뉴 '편집'·'서식', 도구 팝업 `TextToolPopup` | P-A | E2-01, E2-04b, E2-06 | `widget/text_box_test.dart`(새 상자 위치·폭 규칙, 빈 곳 끌기 → `NewTextBoxOutline` 보임·getter `previewObjects` 빈 목록, 기존 상자 탭 → `hiddenIdsOf == {id}`·getter `hiddenObjectIds == {id}` → 끝 → `{}`, 서식 바 누름 → 세션 유지, 크기 24로 바꿈·글 수정 → 끝에 `UpdateObjects` **1회**·높이 = `measure` 값, 모두 지움 → `RemoveElements(elementIds: [id])`, **편집 중 두 손가락 끌기·핀치 → 세션 유지·명령 0·편집기 위치가 카메라를 따라 바뀜·편집기 `focusNode.hasFocus == true`·포커스 잃음 0회**, **거부된 손바닥 down → 유지·`hasFocus` 유지**, **펜 전용 한 손가락 끌기 → 유지·`hasFocus` 유지**, 웹 규칙 공중 `down 0x02` → 유지·`hasFocus` 유지 — (수정 2회차) 이 경우들은 1차 `EditorCanvasFocus`가 든 실제 `PageViewport`에서 몰고, 각 동작 뒤 `pump`로 마이크로태스크를 비운 다음 단언한다(V7 — 맨 `Listener` 하네스로는 포커스 경로가 안 보임), 한 손가락 탭 → 끝 1회(탭 소비), 펜 접촉 → 세션 끝 후 그 접촉이 현재 도구로 이어짐(펜 도구에서 선택 메뉴 '편집'으로 연 세션이면 획 1개 — 글을 바꿨으면 명령 2: `UpdateObjects` + 획, 각각 1단계), 길게 누르기 → 끝 + 메뉴, (수정 2회차) 펜 접촉·한 손가락 탭으로 끝난 뒤 캔버스 `FocusNode.hasPrimaryFocus`(키 P → 펜 도구 — 단축키 복귀), `FocusNode.unfocus()`(키보드 내림 흉내) → 끝(`focusLost`) → 캔버스가 주 포커스, 하네스의 다른 `TextField`에 `requestFocus()` → 끝(`focusLost`)·그 입력란이 주 포커스로 남음(캔버스가 빼앗지 않음), 툴바 자리 탭 → 끝(`tapOutside`), 도구 바꿈·Esc·뒤로·앱 숨김 → 각각 끝, 툴바 되돌리기 → 세션 끝 + undo → 원래 상태, 원격 삭제 중 편집 → 끝에 `UpdateObjects` 없이 `AddObjects` 새 id·스낵바 0, 읽기 전용 거절 → 클립보드에 글·안내), `widget/text_format_bar_test.dart`(크기 6~144 클램프, 색·굵게·정렬·배경 → 초안 스타일, `ToolOptions.textStyle` 갱신, 서식 단추가 포커스를 가져가지 않음), `widget/text_tool_misc_test.dart`(읽기 전용 → 도구 비활성, 10,000자 한도, 편집 중 단축키가 글자로) |
| E2-10b | 긴 텍스트 세션 초안 보관(6.11.2 — `editor.textDraft`, 5 s, 다시 열 때 되살리기) | P-B | E2-10 | (키 `editor.textDraft`를 `EditorSettingKeys`에 더함) `unit/text_draft_store_test.dart`(`fake_async`: 변경 → 5 s 뒤 1회 기록, 세션 끝 명령 뒤 지움, 다른 노트 초안 무시), `widget/text_draft_restore_test.dart`(초안이 남은 노트 열기 → 배너, 되살리기 → `AddObjects` 1단계·새 id, 버리기 → 키 지움) |
| E2-11 | 웹 대체안 B `textarea`(6.11.6) — **B-2에서 `inline`·`sheet`가 모두 불합격일 때만**. 시작 전 시제품 시험 한 번으로 `HtmlElementView.fromTagName`이 Chrome 시험 바인딩에서 실제 `<textarea>`·`onElementCreated`를 주는지 확인(검토 S-9) | P-C | E2-10 | `web/textarea_overlay_browser_test.dart`(`@TestOn('browser')`, `setUpAll(useInkTestFonts)`: 겹친 `textarea`에 값 넣고 `input` 이벤트 → 초안 갱신, `blur` → 세션 끝 명령 1회 — 시제품에서 플랫폼 뷰가 안 만들어지면 '컴파일·조건부 export'까지), `unit/no_platform_imports_test.dart`(예외가 이 파일 하나) |
| E2-12 | 이미지·삽입: `InsertMenu`(이미지 하위 메뉴 + **확장 `insertMenuItems`** + `EditorInsertContext`), 이미지 삽입 흐름·배치(6.12.2 — **`pick` 동기 시작 → 메뉴 닫기**, `origin: insert`), 이미지 붙여넣기(컨텍스트 메뉴·⌘V), 페이지 추가 시트 '이미지' 줄·이미지 페이지(6.12.3 — 동기 시작 → 시트 닫기) | P-A | E2-06, E2-07c | `unit/object_placement_test.dart`(보이는 영역·페이지 클램프, 세로로 긴 이미지 높이 기준, 페이지보다 큰 이미지, 보이는 영역이 빌 때), `widget/image_insert_test.dart`(가짜 가져오기 `photos` → `AddObjects([ImageObject])` 1단계·`assetId`·`px` 일치·선택됨, **`pick`이 메뉴가 아직 열려 있는 동안(같은 `onPressed` 안) 불림·받은 context = `EditorBody`의 것·메뉴는 그 뒤 닫힘**(검토 S-6), **이미지 삽입 직후 이미지 본체를 펜으로 끌기 → `TransformElements` 1회(이동)·획 0**(검토 M-4), `null` → 명령 0·안내 0, 예외(동기·비동기) → 보고 + '이미지를 넣지 못했어요', 진행 중 두 번 누름 무시, 자리 `null` → 메뉴·시트 줄·붙여넣기 항목 모두 없음, `sources` 비어도 없음), `widget/insert_menu_test.dart`(확장 삽입 항목이 받은 `visibleRectPt`가 보이는 영역, `onSelected` 동기 시작, `selectObject(id)` → 그 객체 선택(`insert`), 이미지·확장 둘 다 없으면 `[+]` 숨김), `widget/add_page_sheet_test.dart` v2(1차 시험 + '이미지' 줄 → 위치 기억 → `pick`이 시트가 닫히기 전에 불림 → `InsertPages` 1단계·`ImageBackground(fit: contain)`·방향 규칙 3경우) |
| E2-13 | 툴바 v2: 도형·텍스트 단추, `[+]`, 마이크 단추를 v2 배치로 옮김(단추는 E2-16), 좁은 폭 접기, 제목 폭 문턱 | P-A | E2-09, E2-10, E2-12, E2-16 | `widget/toolbar_test.dart` v2(1차 시험 + 단추 순서, 활성 재누름 → 도구 팝업, 720 px 미만 → `[⋯도구]`, 1032×1376(iPad 13" 세로)·1376×1032(가로) 넘침 없음(`tester.takeException() == null`)) |
| E2-14 | 새 펜: 선택기 10종 두 줄, `PenExtrasControls`, 레이저(명령 없음·읽기 전용 허용·색 조절 숨김), 테이프 탭(손가락·펜 점 가로채기), '테이프 모두 보이기/가리기' | P-A | E2-03, E2-04b | `widget/pen_types_v2_test.dart`(10칸·문구·키, P1 펜 고르면 `penType`·저장, 레이저에서 색 줄 없음), `widget/pen_extras_controls_test.dart`(펜별 조절 줄 = 6.14.2 표, 값 → `withInkExtras`·`editor.penStyles`, 롤 줄은 `capabilities.barrelRoll`·`seenBarrelRoll`일 때만), `widget/laser_test.dart`(**실제 R2-B3 INK**: 레이저로 긋기 → 명령 0·`undoDepth` 0·최근 색 그대로, 읽기 전용에서 상호작용 시작됨 — 가짜 세션 없음, 검토 S-4), `widget/tape_test.dart`(손가락 탭 → `toggleTape`·명령 0, 펜 점(3 px·150 ms) → 점 획 없음·토글, 펜 6 px 짧은 획 → 보통 획 1개, 펜 끌기 → 보통 획, 모두 보이기 → 마운트된 컨트롤러 전부 + 나중에 마운트된 페이지 + 그 뒤 새로 그린 테이프도 드러남, 낱개 토글한 페이지가 마운트에서 빠졌다 돌아오면 가림, 다시 열면 가림) |
| E2-15 | 자동 도형 보정 연결: 설정 토글(펜 팝업·설정 섹션), `shapeAssistFor`(6.10), `addShape` 커밋(1차 `commitInkEdit` 경로 그대로 — 새 코드 없음, 커밋 단언은 E2-09), `NoShapeFitter`이면 숨김·`off`, 개발자 토글 켬일 때 표본 링 버퍼에 결과 기록(6.20) | P-B | E2-03, E2-04a | `unit/shape_assist_for_test.dart`(펜 종류 10개 × 설정 2 × fitter(`NoShapeFitter`/INK `FakeInkShapeFitter`) → `holdToSnap`/`off` 표), `widget/shape_assist_test.dart`(펜 다운 뒤 getter `StrokeSession.shapeAssist`가 표 값, `NoShapeFitter` override → 토글 없음, `FakeInkShapeFitter` override → 토글 보임) — (수정 3회차) `InkEdit(addShape)` → `commitInkEdit` → `AddObjects` 1단계·획 없음 단언은 P-A E2-09 `widget/shape_tool_test.dart`로 옮겼다(이 작업을 미뤄도 10 #4 매핑 커버리지가 판정된다). 실제 멈춤 흐름은 E2-21b(P-B — INK T39와 이 작업이 둘 다 병합됐을 때만, 8.3) |
| E2-16 | 녹음 연동 ①: `RecordingLink`(R-1·E-5), 펜 다운에 메타, **마이크 단추**(1차 툴바에 — 녹음 중 표시), `EditorPanelSlot`(40%·`EditorPanelContext`·예외), `tapToSeek` 플래그 | P-A | E2-04a | `unit/recording_link_test.dart`(`FakeAudioRecorder`: 녹음 중 같은 노트 → 메타(id·offset), 일시정지 → 빈 메타, 다른 노트 → 빈 메타, `advance` 뒤 offset 증가·일시정지 구간 제외, 레이저 → 빈 메타), `widget/recording_link_test.dart`(녹음 중 획 3개 → CORE 획의 `recordingId`·`recordingOffsetMs`가 각 펜 다운 때 `offsetNowMs` 값, 웹 규칙에서 공중 down 뒤 접촉 순간 값), `widget/recording_panel_slot_test.dart`(`recordingPanel == null` → 마이크 단추 없음, 열기 → 높이 ≤ 40%, `setTapToSeek(false)` → `editor.settings.device` 기록·`tapToSeek.value` 반영, `close` → 닫힘, 빌더 예외 → 보고 + 문구, 녹음 중 빨간 점·다른 노트 녹음 회색 점) |
| E2-17 | 녹음 연동 ②: `PlaybackHighlightLogic`(출력 주입·활성 규칙)·`PlaybackHighlightDriver`(Ticker), 탭 재생(**탭 재생 상태 R-5 v2.1** — `tapToSeekActive`, 손가락 탭·펜 점 `end()` 전 가로채기), `editorPreRollMsProvider`·강조 방식 설정(설정 > 페이지 '필기 재생') | P-A | E2-16, E2-02, E2-04b | `unit/tap_to_seek_state_test.dart`(`tapToSeekActive` 조합 전부 — 녹음기 phase 5 × 재생 phase 7 × 패널 2 × 종류 2 × 설정 2 × 이 노트 녹음 여부 2), `unit/playback_highlight_logic_test.dart`(출력 기록: `ready`(열기만) → `null`, `playing` → 초점·같은 위치 건너뜀, `paused` → 마지막 위치 유지, **열림 뒤 `positionMs` 변경(패널 탐색) → 활성**, `markSeek` → 활성, 다른 녹음 열림 → 다시 비활성·`null`), `widget/playback_highlight_test.dart`(`FakeAudioPlayback` playing + `setPositionMs` → 다음 프레임 모든 마운트 컨트롤러 getter `playbackFocus` 위치, paused → Ticker 멈춤·초점 유지, 녹음 닫힘 → `null`, 다른 노트 녹음 → 초점 없음, 새로 마운트된 페이지에 초점, 앱 숨김 → Ticker 멈춤, **정지 직후 흐림 없음: `FakeAudioRecorder` 녹음 → `stop` → 재생기 `open`(ready) → 모든 컨트롤러 `playbackFocus == null`, 패널 열기(ready)도 `null`, 이어서 `play` → 초점**(PDF 검토 M-8 → EDITOR-M8)), `widget/tap_to_seek_test.dart`(**① 녹음 정지 직후(재생기 `ready`)·패널 닫힘 → 녹음된 획 위 15 px 펜 획 → 커밋됨(획 +1)·`calls`에 `seek` 없음, ② 패널 열림 + `ready` → 손가락 탭 → `calls == [open, seek:<offset − 1500>, play]`·같은 상태에서 펜 점(3 px) → 점 획 커밋·seek 없음, ③ 녹음 중(녹음기 `recording`) → 손가락 탭·펜 점 모두 가로채지 않음**(검토 M-3 → EDITOR-M3), 재생 중 펜 점 → `seek`·점 획 0(`cancel` — `end` 전), offset < 1500 → `seek:0`, 토글 끔 → 보통 동작, 녹음 안 된 획 → 보통 동작, preRoll 3000 설정 반영, '복구된 녹음'(제목) 녹음의 획도 같음) |
| E2-18 | Pencil 소비: `StylusExtrasListener`, `followSystem` 표, 스퀴즈 `ended`만, 위치 지정 팝업(빠른 펜·색), 호버 포즈 커서·팜 리젝션(`timestamp` 있으면 사용), 배럴 롤 → 펜촉 각, `prefersPencilOnlyDrawing`(입력 정책에서 계산), 첫 스퀴즈·롤 이벤트 기록(`seenSqueeze`·`seenBarrelRoll`), '다음 시작 때 반영' 안내 | P-B | E2-05, E2-14 | `unit/follow_system_test.dart`(8값), `unit/barrel_roll_test.dart`(롤 30° + 기본 45° → 75°, 170° + 45° → 35°(mod 180), 500 ms 넘은 롤 → 기본 각(`timestamp` 기준·없으면 `Stopwatch`), `followBarrelRoll` 끔 → 기본 각, `capabilities.barrelRoll` 거짓 → 기본 각), `widget/stylus_extras_test.dart`(`FakeStylusExtras`: 더블탭 `switchEraser` → 지우개 ↔ 이전, 설정을 `undo`로 → undo 1회, 스퀴즈 `began`·`changed` → 무시·`ended` + `showContextualPalette` → 빠른 펜 팝업이 `hoverPosition`에, 첫 스퀴즈 → `seenSqueeze` 저장·설정 줄 보임(그 전에는 없음), 포즈 → 펜 점 커서(높이로 크기), 포즈 뒤 손가락 down → 거부, `isSupported == false` → 구독 없음, `prefersPencilOnlyDrawing` → `auto`가 펜 전용) |
| E2-19 | `initialFocusRectPt`·위치 강조(6.16), 지우개 v2(`eraseShapes` 토글·전체 지우기 + 객체) | P-A | E2-02 | `widget/initial_focus_test.dart`(페이지 30 + 사각형 → 그 페이지가 현재 페이지·사각형이 화면 안, 강조 1.6 s 뒤 사라짐(`pump`), 모르는 페이지 → 무시, `initialPageId` 없음 → 무시, 확장 `navigateToPage(id, rect)`도 강조), `widget/erase_v2_test.dart`(1차 시험 + 획 지우개가 도형을 지나면 명령 1회에 도형 포함(`RemoveElements`), **부분 지우개가 획과 도형을 함께 지남 → 명령 1개(`CompositeCommand`)·되돌리기 1번에 도형과 조각 모두 복구**(CP-INK-2 → EDITOR-M9), 토글 끔 → 도형 남음·`editor.eraser`에 기록, 전체 지우기 체크 → `ClearPage(includeObjects: true)`·되돌리기 1번에 모두 복구, 필터 형광펜만 → 체크 없음) |
| E2-20 | 개발자 표시·메뉴 추가(6.20 — 도형 표본 링 버퍼·LIBRARY 형식 복사 포함) | P-B | E2-04a, E2-16 | `widget/dev_overlay_v2_test.dart`(버튼 16진수·접촉 규칙·호버 출처·녹음 줄·객체 수 줄), `unit/shape_samples_test.dart`(6.20 — 토글 끔 0개, 켬 → 최근 5개, LIBRARY 형식), `widget/dev_menu_test.dart` v2(도형 표본 복사 → 기대 종류 시트 → `Clipboard.setData` 텍스트가 `{kind, points, viewScale}`, 입력 방식 전환은 웹에서만 보임, '텍스트 상자 시험' 항목) |
| E2-22 | 마무리: 골든 v2, 성능 스모크 v2(6.22 — 1차 여유 규칙), 결과 보고(변경 요청 목록, iPad·APK 체크리스트 초안) | P-A | 전부(P-C 제외) | `goldens/object_handles_golden_test.dart`(단일 도형·타원·텍스트·이미지 핸들, 꼭짓점 모드), `unit/performance_smoke_test.dart` v2(6.22 표), 패키지 VM 전체·Chrome 전체 통과(체크포인트 1회) |

- 병렬: E2-01과 E2-02·E2-03·E2-04a는 서로 독립(E2-00 뒤 — E2-01은 자기 진입점이 있어 E2-03을 기다리지 않음). E2-04b는 E2-04a 뒤. E2-06 이후 E2-07a·E2-08·E2-09는 독립(E2-07b·c는 a 뒤 순서대로), E2-14는 E2-04b 뒤, E2-15는 E2-04a 뒤 아무 때나. **E2-16은 E2-04a 뒤 바로**, E2-17은 E2-16·E2-04b 뒤 — 도형·텍스트·이미지·툴바 v2를 기다리지 않는다(초안의 'E2-16 ← E2-13' 사슬을 끊었다).
- 일정이 밀리면 3.4대로: P-C(E2-11, 별 꼭짓점) → P-B(E2-10b·E2-15·E2-18·E2-20) 순으로 자른다. (수정 3회차) 잘라도 완료 판정이 막히지 않게 5.1.2 매핑 행은 모두 P-A 시험이 덮고(10 #4 — '자동 도형 보정 확정' 행은 E2-09), INFRA V5·V6의 자동 도형 단계가 P-B 미병합으로 실패하는 것은 EDITOR 원인 실패로 세지 않는다(E2-23·10 #5). P-A 안에서는 E2-01(IME 시제품)·E2-04a·b(입력)·E2-06·E2-07a~c(올가미 고급)·E2-16·E2-17(녹음 연동)이 앞이다.

### 8.3 통합 단계 몫 (7.7 6단계 'EDITOR')

| ID | 작업 | 시점 | 완료 조건 |
|---|---|---|---|
| E2-21 | 통합 스모크 v2: 실제 INK(동시 개발 결과) + 실제 CORE(`openTestNoteStore()` — DB v2) + CORE 가짜 오디오 포트 | 7.7 6단계(CORE·INK 병합 뒤) | `integration/objects_smoke_test.dart`(`@Tags(['integration'])`, `@TestOn('vm')`: 노트 열기 → 획 1개 → 텍스트 상자 '회의록 abc' → 도형 사각형 → 가짜 가져오기 이미지 → 올가미 전부 → 90° 돌리기·색 변경·잘라내기·붙여넣기 → (총괄 직접 수정 — 1차 v1.5 C15-04 순서, 13.4) 되돌리기 사슬 끝까지(처음 상태 — 노트를 연 직후의 획·객체) → 다시 실행으로 원래 상태 → 화면 닫고 다시 열기 → 모두 유지·`content.objects` 종류·개수·다시 연 세션 `undoDepth == 0`(C15-04 — `noteSessionProvider`가 autoDispose라 다시 연 세션은 되돌리기가 없다. 1차 `test/integration/real_core_ink_smoke_test.dart` 276행과 같은 단언). (수정 2회차) P-A 기능만 거친다 — `inkShapeFitterProvider`는 override하지 않아 기본 `NoShapeFitter` → `shapeAssistFor`가 `off`라 획 단계가 INK T39·E2-15 유무와 관계없이 같은 결과다. 자동 도형 단계는 E2-21b로 뗐다), `integration/recording_link_smoke_test.dart`(가짜 녹음기 녹음 중 획 3개 → 정지 → 실제 CORE `Recording` 행 → 재생기 `open`(ready) → 실제 INK getter `playbackFocus == null`(정지 직후 흐림 없음) → `play`·가짜 재생 위치 바꿈 → 실제 INK 초점(`InkPlaybackFocus`)이 바뀜 → 획 탭 → `calls`에 `seek`), `web/editor_browser_smoke_v2_test.dart`(`@TestOn('browser')`, `setUpAll(useInkTestFonts)`: 가짜 저장소 + 실제 INK로 도형 1개·텍스트 상자 1개·되돌리기, 웹 접촉 규칙이 켜져 있음 — 웹 컴파일·세션 규칙) |
| E2-21b | (수정 2회차) 자동 도형 통합 스모크(**P-B** — M5-6): 실제 INK의 멈춤 감지(T39)와 EDITOR 연결(E2-15)을 실제 CORE에서 한 번에 | 7.7 6단계, **INK T39(03-ink 8.2, P-B)와 E2-15(P-B)가 둘 다 병합됐을 때만**. 하나라도 빠졌으면 이 파일을 만들지 않고 진행 기록 '2차' 절에 '미룸 — 빠진 작업(T39/E2-15)'을 적는다(10 #1 규칙, 2차 완료 판정에 들지 않음). 뒤에 둘이 모두 들어오면 그 병합 때 만든다 | `integration/shape_assist_smoke_test.dart`(`@Tags(['integration'])`, `@TestOn('vm')`, 실제 INK + `openTestNoteStore()`: `inkShapeFitterProvider`를 INK `FakeInkShapeFitter(fit: 사각형)`로 override → 펜 도구로 `SyntheticInk.loopThenHold` 표본을 포인터로 몰고 `fake_async` 600 ms 멈춤(검토 S-4) → 떼기 → `content.objects`에 `ShapeObject`(`ShapeKind.rectangle`) 1개·획 0개, `undoDepth` +1(1단계) → 되돌리기 → 도형 없음·획 없음(원래 획은 저장되지 않음 — 7.2.3) → 다시 실행 → 도형 1개 → 화면 닫고 다시 열기 → 도형 유지) |
| E2-23 | INFRA V5·V6 지원: 부록 C 키로 앱 스모크가 에디터를 몰 수 있는지 INFRA와 함께 확인(V5 '90° 돌리기'는 선택 메뉴 경로 — CP-E8 승인), 실패 원인이 EDITOR면 고침 | 7.7 7단계 | INFRA `app_smoke_v2_test.dart`(V5)·`app_smoke_v2_browser_test.dart`(V6) 통과(EDITOR 원인 실패 0). (총괄 직접 수정 — 12.2 Q16 총괄 답, 계약 v2.2 C22-07, 13.4) V5·V6 본 흐름에는 P-B 단계가 없다 — '합성 멈춤으로 자동 도형'은 **V5b**(INFRA `app/test/integration/app_smoke_shape_assist_test.dart`, VM, P-B)로 떨어졌다. V5b는 INK T39·EDITOR E2-15·LIBRARY L2-06이 **모두** 병합됐을 때만 INFRA가 만들고 판정에 넣으며, 하나라도 빠졌으면 통합 진행 기록에 '미룸 — V5b, 빠진 작업(T39/E2-15/L2-06)'으로 남아 2차 완료 판정(10 #5)을 막지 않는다(00-overview 7.7.2 'P-B에 기대는 기준'). 셋이 모두 병합됐으면 V5b에서도 EDITOR 원인 실패가 없어야 한다. V5·V6의 한 단계가 실패하면 원인을 좁히는 EDITOR 시험은 **단계별로** 다음과 같다(01-infra 9.1 V5 단계 번호): 2~5단계(획·텍스트 상자·도형 도구·이미지 삽입·올가미 전부·90° 돌리기·색 변경·잘라내기·붙여넣기 → 되돌리기 사슬 → 다시 실행 → 닫기·다시 열기 — C15-04 순서) = E2-21 `integration/objects_smoke_test.dart`, 6~7단계(마이크 단추 → `editor.panelSlot` 패널 자리, 녹음 중 획 메타 → 재생 강조 → 획 탭 → 탐색) = E2-21 `integration/recording_link_smoke_test.dart` + E2-16 `widget/recording_panel_slot_test.dart`, 8단계(선택·삽입 메뉴의 확장 항목 `editor.ext.recog.*`) = E2-07c `widget/selection_extensions_test.dart`·E2-12 `widget/insert_menu_test.dart`, 9단계(검색 결과 → `initialFocusRectPt`·`editor.focusFlash`) = E2-19 `widget/initial_focus_test.dart`. V6(Chrome)에서만 실패하면 E2-21 `web/editor_browser_smoke_v2_test.dart`를 먼저 본다. V5b가 실패하면 E2-21b `integration/shape_assist_smoke_test.dart`·E2-15 `widget/shape_assist_test.dart`가 대응 시험이다. 실패가 있었으면 진행 기록 '2차' 절 E2-23 줄에 실패 단계·대응 시험(위 대응)·원인(EDITOR 몫이면 고친 커밋)을 적는다 |
| E2-24 | 실기기 확인 대응: B-2·B-15(IME·선택 손잡이·스크롤 중 편집) 결과로 `webTextInput` 기본값 결정(`inline`/`sheet` — 둘 다 불합격이면 E2-11), B-4 자동 도형 체감 → 개발자 토글로 모은 표본을 LIBRARY 형식으로 LIBRARY에 전달(6.20), A-2 S펜 결과로 E-4 규칙 보정 | 7.7 9단계 뒤 | 진행 기록에 결과·결정 |

(통합 단계 결과 2026-11-12 — E2-21·E2-21b 완료, E2-23 대응 시험 준비·V5 통과, E2-24는 실기기 대기: [진행 기록 '2차 › 통합 단계'](../progress/editor.md#통합-단계-1))

### 8.4 작업량

| 묶음 | 작업 | 추정(1차 T ≈ 1) |
|---|---|---|
| 올가미 고급·클립보드 | E2-06·E2-07a·E2-07b·E2-07c | 2.5(a 0.7·b 0.6·c 0.6 + E2-06) |
| 텍스트 도구·IME | E2-01·E2-10 (+ E2-10b P-B 0.3, E2-11 P-C 0.5) | 3 |
| 도형 도구·핸들·꼭짓점 | E2-08·E2-09 | 3 |
| 이미지 삽입·이미지 페이지·삽입 메뉴 | E2-12 | 1.5 |
| 제스처·펜 버튼·Pencil | E2-04a·E2-04b·E2-05·E2-18 | 3 |
| 새 펜·테이프·레이저·자동 보정 | E2-14·E2-15 | 1.5 |
| 녹음 연동 | E2-16·E2-17 | 2 |
| 자리·위치로 열기·지우개 v2·정리 | R2-B5·E2-00·E2-02·E2-03·E2-13·E2-19·E2-20·E2-22 | 0.5 + 정리 몫 |
| **합계** | | **약 17**(00-overview 2.4 추정과 같음. 나눈 작업은 세션 하나에 끝나는 크기 — 검토 S-3) |

---

## 9. 테스트 계획

### 9.1 실행 명령과 부하 규칙

| 종류 | 명령 | 언제 |
|---|---|---|
| 작업 하나 | `cd packages/feature_editor && flutter test test/<파일>` | 평소 |
| 패키지 VM | `flutter test`(골든 포함, `integration` 기본 건너뜀) | 체크포인트(E2-07c·E2-12·E2-17·E2-22 뒤) |
| 패키지 Chrome | `flutter test --platform chrome test/web/` | 체크포인트(`CHROME_EXECUTABLE=/usr/local/bin/chrome-nosandbox`) |
| 골든만 | `flutter test --tags golden` | 골든을 바꾼 작업 |
| 통합 | `ws test --run-skipped -t integration`(EDITOR 묶음) | 통합 단계 E2-21(·E2-21b가 있으면 함께) |
| 영향 범위 | `ws test --affected-since <기준>` | 병합 전 |

EDITOR는 `media`·`emulator` 태그 시험이 없다. 같은 컨테이너에서 다른 영역이 Chrome 가짜 마이크 시험을 돌리는 동안에도 EDITOR의 Chrome 시험은 일반 래퍼를 쓴다(겹쳐도 되지만 체크포인트 때만 돌린다 — 00-overview 5장).

### 9.2 시험 묶음

| 묶음 | 파일 (2차에 새로·바뀌는 것) | 무엇을 |
|---|---|---|
| VM 단위 | `unit/gesture_settings_test.dart`, `unit/stylus_extras_test.dart`, `unit/stylus_contact_test.dart`, `unit/input_router_test.dart` v2(R34~R52), `unit/editor_action_runner_test.dart`, `unit/follow_system_test.dart`, `unit/barrel_roll_test.dart`, `unit/tool_controller_test.dart` v2, `unit/tool_options_test.dart`, `unit/pre_roll_test.dart`, `unit/editor_device_state_test.dart`, `unit/element_clipboard_test.dart`, `unit/extension_runner_test.dart`, `unit/object_resize_test.dart`(`cornerScale` 포함), `unit/selection_priority_test.dart`, `unit/shape_drafts_test.dart`, `unit/shape_assist_for_test.dart`, `unit/shape_samples_test.dart`, `unit/object_placement_test.dart`, `unit/text_edit_session_test.dart`, `unit/text_draft_store_test.dart`(P-B), `unit/recording_link_test.dart`, `unit/tap_to_seek_state_test.dart`, `unit/playback_highlight_logic_test.dart`, `unit/page_mount_test.dart` v2, `unit/selection_revalidate_test.dart`, `unit/selection_hit_test_test.dart` v2, `unit/mapping_coverage_test.dart`, `unit/editor_settings_test.dart` v2, `unit/editor_setting_keys_test.dart` v2, `unit/api_surface_test.dart` v2, `unit/no_platform_imports_test.dart` v2, `unit/performance_smoke_test.dart` v2 | 순수 계산·상태 기계·JSON·규칙 — EDITOR의 **결정**은 여기서(이음새: `shapeAssistFor`·`PlaybackHighlightLogic`·`hiddenIdsOf`·`tapToSeekActive`·`selectionPriority`) |
| VM 위젯 | `widget/lasso_mixed_test.dart`, `widget/rotate_test.dart`, `widget/paste_test.dart`, `widget/selection_menu_test.dart`, `widget/recolor_test.dart`, `widget/selection_extensions_test.dart`, `widget/object_handles_test.dart`, `widget/vertex_edit_test.dart`, `widget/shape_tool_test.dart`, `widget/shape_style_test.dart`, `widget/shape_assist_test.dart`, `widget/text_box_inline_test.dart`, `widget/text_box_test.dart`, `widget/text_input_sheet_test.dart`, `widget/text_format_bar_test.dart`, `widget/text_tool_misc_test.dart`, `widget/text_draft_restore_test.dart`(P-B), `widget/image_insert_test.dart`, `widget/insert_menu_test.dart`, `widget/add_page_sheet_test.dart` v2, `widget/toolbar_test.dart` v2, `widget/pen_types_v2_test.dart`, `widget/pen_extras_controls_test.dart`, `widget/laser_test.dart`, `widget/tape_test.dart`, `widget/recording_link_test.dart`, `widget/recording_panel_slot_test.dart`, `widget/playback_highlight_test.dart`, `widget/tap_to_seek_test.dart`, `widget/stylus_extras_test.dart`, `widget/gesture_settings_section_test.dart`, `widget/undo_redo_test.dart` v2, `widget/shortcuts_test.dart` v2, `widget/initial_focus_test.dart`, `widget/erase_v2_test.dart`, `widget/dev_overlay_v2_test.dart`, `widget/dev_menu_test.dart` v2, `widget/smoke_test.dart` v2 | 가짜 저장소 + **실제 INK**(R2-B3부터 — INK 가짜 없음) + 가짜 자리·포트. 단언은 ① CORE 결과(명령 수·`undoDepth`·내용) ② INK에 넘긴 값(읽기 getter `previewObjects`·`hiddenObjectIds`·`playbackFocus`·`StrokeSession.shapeAssist`, `isTapeRevealed`) ③ 위젯 상태 — 5.2.4 |
| 골든 (`golden`, `@TestOn('vm')`) | `goldens/selection_frame_v2_golden_test.dart`, `goldens/object_handles_golden_test.dart` (+ 1차 세 파일 그대로) | EDITOR 오버레이만(INK 출력은 빈 페이지·`SolidBackgroundBuilder`로 고정). 글자는 Ahem만(7.4.6) — 각도 꼬리표는 골든에서 숨김 |
| Chrome (`@TestOn('browser')`) | `web/text_input_browser_test.dart`, `web/editor_browser_smoke_v2_test.dart`(+ 1차 `web/editor_browser_smoke_test.dart`), (P-C) `web/textarea_overlay_browser_test.dart` | 모두 `setUpAll(useInkTestFonts)`(v2.1, C21-26 — Chrome에서 `rootBundle.load`가 응답하지 않음). **웹 컴파일·세션 규칙**: 웹 빌드에서 컴파일되고 세션·명령 규칙이 VM과 같음, 웹 접촉 규칙이 켜진 상태의 기본 흐름. `tester.enterText`는 `TestTextInput`이 `flutter/textinput` 채널을 가로채 엔진의 DOM 입력 요소·IME를 거치지 않으므로 **IME 판정은 실기기 B-2·B-15뿐**이다(검토 S-9). 1차 메모대로 펜 미리보기를 여는 위젯은 Chrome에서 돌리지 않는다(`PencilGrain` 타이머) |
| 통합 (`integration`) | `integration/objects_smoke_test.dart`, `integration/recording_link_smoke_test.dart` (+ 1차 `real_core_ink_smoke_test.dart`), (P-B) `integration/shape_assist_smoke_test.dart`(E2-21b — INK T39·E2-15가 둘 다 병합됐을 때만 생김) | 실제 INK + 실제 CORE v2 |

### 9.3 계약 보장 ↔ 시험

| 보장 | 시험 |
|---|---|
| E-4 (접촉·버튼 판정, 웹 공중 down으로 시작하지 않음, (v2.1) 접촉 비트가 빠진 `move` = 접촉 끝) | `unit/stylus_contact_test.dart`, `unit/input_router_test.dart` R34~R42(R36이 v2.1 문장) |
| E-5 (R-1로만 메타, 펜 다운 안에서 동기 읽기) | `unit/recording_link_test.dart`, `widget/recording_link_test.dart` |
| E-6 (세션 1회 = 명령 1회 = 1단계, 편집 중 숨김) | `unit/text_edit_session_test.dart`, `widget/text_box_test.dart`, `widget/text_box_inline_test.dart` |
| E-7 (빈 자리 숨김, 콜백 예외 보고 + 문구, (v2.1) `isVisible` 예외는 숨김 + 보고만, 자리 콜백은 누름 처리 안에서 동기 시작·에디터 본문 `context`) | `widget/selection_extensions_test.dart`, `widget/insert_menu_test.dart`, `widget/image_insert_test.dart`, `widget/add_page_sheet_test.dart` v2, `widget/recording_panel_slot_test.dart`, `unit/extension_runner_test.dart` |
| 7.2.10 (v2.1) 능력은 시작 때 한 번·스퀴즈·롤 항목은 첫 이벤트 뒤 | `widget/stylus_extras_test.dart`, `widget/gesture_settings_section_test.dart` |
| R-5 (v2.1) 탭 재생 상태·`end()` 전 판정·강조 초점 활성 규칙 | `unit/tap_to_seek_state_test.dart`, `unit/playback_highlight_logic_test.dart`, `widget/tap_to_seek_test.dart` ①~③, `widget/playback_highlight_test.dart` '정지 직후 흐림 없음', 통합 `recording_link_smoke_test.dart` |
| 7.2.9 (v2.1) 미리보기 > 숨김 · 테이프 '모두 보이기'는 `updateContent` 뒤마다 | `widget/text_input_sheet_test.dart`, `unit/page_mount_test.dart` v2, `widget/tape_test.dart` |
| E-3·K-9 (레이저 저장 안 함 — EDITOR 쪽) | `widget/laser_test.dart`, 통합 `objects_smoke_test.dart` |
| 7.4.10 (모르는 도구 → pen, 자리 UI 높이) | `unit/tool_controller_test.dart` v2, `widget/recording_panel_slot_test.dart` |
| 7.2.3 EDITOR 명령 매핑 (5.1.2 표의 모든 행이 1단계 — (v2.1) 이름 있는 인자·`elementIds: [id]`·부분 지우개 + 도형 합성 행 포함) | 각 위젯 시험의 `undoDepth` 단언(행마다 하나 이상 — 표를 `test/helpers/mapping_table.dart`로 두고 덮였는지 `unit/mapping_coverage_test.dart`가 확인). (수정 3회차) 표는 행마다 덮는 시험 파일을 함께 적고, 그 시험은 모두 P-A 작업 몫이다 — '자동 도형 보정 확정' 행은 P-B E2-15 `shape_assist_test`가 아니라 P-A E2-09 `widget/shape_tool_test.dart`(1차 `commitInkEdit` + R2-B3 `InkEditKind.addShape`)가 덮는다 |
| 1차 E-1·E-2·N-2 (회귀) | 1차 시험 전부 그대로 통과 |

### 9.4 실기기 체크리스트 (7.8 중 EDITOR 몫 + EDITOR 추가)

A. 안드로이드 APK (기기가 있을 때 — U2)

| # | 확인 | EDITOR 관련 |
|---|---|---|
| A-2 | S펜: 닿은 채 측면 버튼 누르고 쓰기 → 지우기, 떼면 펜. Air command 켬/끔 각각. 개발자 표시의 `buttons` 값 기록 | E2-04a(네이티브 규칙), E2-20 |
| A-5 | 녹음 시계 오차 — EDITOR는 개발자 표시 '마지막 획 offset'·재생 위치를 보여 줌 | E2-20 |
| A-6 | 가로·세로·분할 화면: 툴바 접기(720 px), 녹음 패널 40%, 텍스트 편집 중 키보드 | E2-13·E2-16·E2-10 |
| A-E1 | (추가) 지우개 끝이 있는 펜이면 뒤집어 쓰기 → 지우개 | E2-04a |

B. iPad 웹(Safari, 홈 화면 앱) — 통합 미리보기 배포 직후((v2.1) Firebase Hosting이 생긴 뒤 — U24·CD2-02. 없는 동안은 통합 9단계의 컨테이너 Playwright 스모크가 일부를 대신한다 — 3.7)

| # | 확인 | EDITOR 관련 |
|---|---|---|
| B-2 | 텍스트 상자 한글: 조합 중 글자·자동 완성·받침 이동·줄바꿈, **확대·회전된 상자**, 방식 `inline`과 `sheet`를 개발자 메뉴로 바꿔 비교 → 기본값 결정(`sheet`는 키보드가 올라와도 입력 패널이 가리지 않는지) | E2-01·E2-10·E2-24 |
| B-3 | 사진 보관함·카메라로 이미지 삽입(HEIC 포함), 배치 크기, 이미지 페이지 방향. (v2.1) **삽입 메뉴·페이지 추가 시트·컨텍스트 메뉴에서 사진 보관함·카메라·붙여넣기가 한 번 눌러 바로 열림**(두 번 눌러야 하거나 '허용 뒤 다시'가 나오면 불합격 — 동기 시작, 7.2.10) | E2-12 |
| B-4 | 도형 7종·맞춤(15°·정비율), 방금 그린 도형 안에 다른 도형 그리기, 자동 도형 보정 체감(오인식이면 개발자 토글 '도형 표본 모으기'를 켜고 다시 그린 뒤 '도형 표본 복사' — LIBRARY 형식), 꼭짓점 편집, 회전된 이미지·텍스트 상자 모서리 크기 조절 | E2-08·E2-09·E2-15·E2-20 |
| B-5 | 올가미 회전 15° 맞춤·90°·색 변경·잘라내기·붙여넣기(획 + 객체), 펜 도구에서 올가미·붙여넣기 선택 끌기(선택 우선 (a′)) | E2-06·E2-07a·E2-07b |
| B-6 | 붓펜·캘리그래피·점선 필기감, 레이저 사라짐, 테이프 손가락 탭·Pencil 점 탭 드러냄, 테이프 위 짧은 획은 획으로 남음, 스크롤로 멀리 갔다 오면 낱개 드러냄이 가려지는 체감 | E2-14 |
| B-7 | 제스처 동작 바꾸기(두 손가락 탭 → 다시 실행, 세 손가락 → 끄기) | E2-05 |
| B-8 | 녹음 30분 → 재생 강조(두 방식)·필기 탭 재생(앞당김 1.5 s)·배속 중 강조 따라옴, 재생 중 스크롤 프레임 시간(개발자 표시). (v2.1) **녹음 정지 직후·패널만 연 상태에서 필기가 흐려지지 않음**, 패널을 닫고 이어 쓴 짧은 획·마침표가 남음(탭 재생 상태 R-5) | E2-16·E2-17 |
| B-10 | 검색 결과 누르면 그 페이지·위치로 + 강조 깜빡임 | E2-19 |
| B-11 | 수식 객체 이동·크기·회전·색 | E2-06·E2-07b |
| B-12 | Pencil 호버가 `kind: stylus` 호버로 오는가(개발자 표시 '호버 출처') | E2-20 |
| B-13 | 복합 노트(이미지 20 + 녹음 30분)에서 혼합 선택 회전·재생 강조 | E2-06·E2-17 |
| B-14 | 녹음 중 탭 닫기 → 복구된 녹음의 획 탭 재생 | E2-17 |
| B-15 | (v2.1) 텍스트 상자(키보드 없이): 두 번 탭 낱말 선택·선택 손잡이·붙여넣기 메뉴, 편집 중 두 손가락 스크롤·핀치에도 편집이 이어짐(키보드가 내려가지 않음 — (수정 2회차) 6.11.3 '캔버스 포커스 양보', E2-10 뒤 판정), 키보드 '내림' 단추로 편집이 끝남, 편집이 끝날 때 글자가 튀지 않음(INK `textStyleOf`·`strutStyleOf`) | E2-01·E2-10 |
| B-E1 | (추가) 툴바 가로·세로 배치, 분할 화면(Slide Over 등)에서 접기 | E2-13 |
| B-E2 | (추가) 펜 전용 모드에서 손가락 탭 재생·테이프, 손가락 필기 모드에서 같은 동작(펜 탭 가로채기 경로) | E2-14·E2-17 |

C. TestFlight 뒤 — 2차 완료 조건 아님

| # | 확인 | EDITOR 관련 |
|---|---|---|
| C-1 | Pencil 더블탭·스퀴즈(시스템 설정 따르기·앱 설정 각각), 스퀴즈 팔레트가 펜 끝 위치에, 배럴 롤 캘리그래피, 호버 높이 커서, '펜슬로만 그리기' 따르기 | E2-18 |
| C-4 | 네이티브 필기 지연(PLAN 5.4) — 2차 펜 다운 추가 비용 포함 | E2-04a·E2-16 |

---

## 10. 완료 기준

1. 8.1 R2-B5와 8.2의 **P-A 작업 전부**가 완료 조건 시험을 통과한다(P-B·P-C는 하지 못하면 진행 기록에 '미룸'으로 남긴다 — 3.4).
2. 1차 EDITOR 시험 전부가 그대로 통과한다(이름 바꾼 `element_clipboard_test.dart` 포함).
3. 패키지 VM 전체·Chrome(`test/web/`)·골든이 통과하고, 루트 `flutter analyze --fatal-infos` 0건, `dart format` 변경 없음, `ws check` 위반 0(V1·V2·V3의 EDITOR 몫).
4. 9.3 표의 계약 보장(E-4~E-7, 7.4.10, 7.2.3 매핑)이 모두 시험으로 덮인다(`unit/mapping_coverage_test.dart`). (수정 3회차) 5.1.2 매핑 행을 덮는 시험은 모두 P-A 작업 몫이라(5.1.2·9.3 — '자동 도형 보정 확정' 행은 E2-09 `widget/shape_tool_test.dart`) P-B·P-C를 미뤄도 이 판정은 그대로 된다.
5. 통합 단계 E2-21이 통과하고, INFRA V5·V6 앱 스모크에서 EDITOR 원인 실패가 없다(E2-23). (수정 2회차) E2-21의 시험은 P-A 기능만 거친다. 자동 도형 통합 스모크 E2-21b는 P-B라 #1 규칙을 따른다 — INK T39·E2-15가 둘 다 병합됐으면 통과해야 하고, 아니면 진행 기록에 '미룸'으로 남기며 2차 완료 판정을 막지 않는다. (총괄 직접 수정 — Q16 총괄 답, 계약 v2.2 C22-07) INFRA V5·V6 본 흐름에는 자동 도형 단계가 없다. '합성 멈춤으로 자동 도형'은 V5b(P-B)이고 같은 #1 규칙이다 — INK T39·EDITOR E2-15·LIBRARY L2-06이 모두 병합됐을 때만 판정에 들고, 아니면 통합 진행 기록에 '미룸'으로 남으며 2차 완료 판정을 막지 않는다. 셋이 모두 병합됐으면 V5b에서도 EDITOR 원인 실패가 없어야 한다. V5·V6 단계가 실패할 때 원인을 좁히는 EDITOR 시험의 단계별 대응은 E2-23에 있다.
6. 공개 API가 4.1 목록과 같다(`api_surface_test`). 계약과 다른 곳이 없다(다르게 해야 했던 점은 12.1에만).
7. 진행 기록 `docs/plans/progress/editor.md`에 '2차' 절(작업별 커밋·시험·변경 요청·실기기 결과)을 이어 쓴다.
8. 실기기 B 체크리스트 중 B-2·B-3·B-5·B-7·B-8·B-15가 합격(나머지는 기록). A는 기기가 있을 때, C는 TF 뒤. (v2.1) B는 Hosting이 생긴 뒤의 판정이고, 그 전까지 2차 완료 판정(1~7)은 컨테이너 시험으로 한다(CD2-03·CD2-04).

---

## 11. 리스크와 대응

| # | 리스크 | 영향 | 대응 |
|---|---|---|---|
| 1 | iPad Safari의 Flutter 웹 한글 IME 품질(조합·받침 이동·변환된 입력 위치) | 텍스트 상자 사용성 — M5-2 체감 | E2-01을 첫 작업으로(시제품 + 방식 전환), 안 A(시트)를 P-A로 함께, 안 B(`textarea`)는 V2로 뼈대 확인 — B-2 결과로 기본값 결정. 미리보기를 앞당길 수 있으면 동시 개발 첫 주에 B-2(12.2 Q1) |
| 2 | INK 기반 단계(R2-B3)가 단순 구현이고 INK 컨트롤러·세션이 `final class`라 가짜로 바꿀 수 없음 | EDITOR 위젯 시험이 INK에 무엇을 넣었는지 못 봄(초안 시험 다수가 작성 불가 — 검토 M-1) | (v2.1) EDITOR 결정은 EDITOR 이음새(`shapeAssistFor`·`PlaybackHighlightLogic` 출력 주입·`hiddenIdsOf`·`tapToSeekActive`·`selectionPriority`)로, 넘긴 값은 INK 읽기 getter 4개(R2-B3에 들어옴 — CD2-08)로, 결과는 CORE로 단언한다(5.2.4). 화면 결과(층 4′ 흐림·새 펜 모양)는 통합 E2-21·실기기 |
| 3 | 선택 우선 규칙이 펜으로 선택 위에 쓰려는 사용자를 막음 | 필기 방해 | (a′)(6.6.2): 그리기 도구에서는 핸들만 우선하고, 본체 끌기 이동은 올가미·붙여넣기·삽입 메뉴 선택만 — 방금 그린 도형·탭 선택 위 down은 새 도형·새 획. 남는 경우(이미지 삽입 직후 그 위에 쓰기)는 빈 곳 한 번 탭으로 풀린다(총괄 결정). 이동 시작 문턱(4 px)으로 작은 접촉은 명령이 없다. B-4·B-5에서 체감 확인 |
| 4 | 회전된 객체의 모서리 크기 조절이 손가락을 따라오지 않음(축 정렬 수학) / 텍스트 상자 크기 조절 뒤 글이 잘림 | M5-2·M5-3 크기 조절 | `ObjectResize.cornerScale`(회전된 반대 모서리 고정 — 30° 시험, 6.6.5). 텍스트 글자 크기는 CORE CP-2 승인으로 `PageObject.transformed`가 함께 배율(K-6) — 초안의 `UpdateObjects` 우회는 없앰 |
| 5 | 웹 접촉 규칙이 CDP 흉내로만 확인됨(실제 S펜 + 안드로이드 Chrome 순서 미확인) | 웹 S펜에서 공중 획·지우기 | 규칙을 순수 함수로 두고 개발자 표시에 버튼 값을 보여 실기기에서 바로 고칠 수 있게(E2-24). 네이티브 APK는 엔진 소스로 확인된 경로 |
| 6 | Pencil 기능은 TestFlight 전까지 실기기 확인 불가 | 더블탭·스퀴즈·롤 동작 미검증 | Dart 쪽 전부를 가짜 소스로 시험(E2-18), 능력 없으면 설정에서 숨김. INFRA 어댑터 표와 1:1로 맞춤(5.3) |
| 7 | 탭 가로채기(테이프·탭 재생)가 사용자가 쓴 짧은 획을 버림(필기 손실 — 검토 M-3) | 마침표·짧은 획이 사라짐 | (v2.1 R-5) 탭 재생 상태를 좁힘(녹음기 `idle` + 손가락: 패널 열림 또는 재생·일시정지 / 펜: 재생·일시정지만), 펜은 '점'(4 px·200 ms)만 탭, 판정은 `end()` 전·가로채면 `cancel()` — 가로채지 않은 펜 입력은 언제나 획. 패널의 탭 재생 토글로 끌 수 있음(12.2 Q3) |
| 8 | 재생 강조 `Ticker`가 iPad에서 프레임마다 8쪽에 초점을 넣는 비용 | 재생 중 스크롤 끊김 | K-7(INK가 경계를 넘은 획만 다시 그림) + EDITOR는 위치가 같으면 건너뜀, 가려지면 멈춤. 6.22 수치·B-8 개발자 표시 |
| 9 | 툴바 단추가 늘어 좁은 화면에서 넘침 | 분할 화면 사용성 | 720 px 미만 접기, 1000 px 미만 제목 숨김, iPad 13" 두 방향 넘침 시험(E2-13) |
| 10 | 1차 코드 넓히기 중 회귀(라우터·선택·클립보드 이름 바꿈) | 1차 기능 깨짐 | 1차 시험 전부를 완료 조건에 둠(10 #2). 라우터는 공중/접촉 상태를 따로 두어 네이티브 경로는 1차 코드 그대로 지나감 |
| 11 | 동시 개발 중 자리 타입·`EditorExtensions`를 INFRA·recog·media가 같이 씀 | 바뀌면 여러 영역이 흔들림 | R2-B5에 계약 원문 그대로 넣고 동시 개발 중에는 '추가만'(7.4.9). EDITOR가 바꾸고 싶은 것은 12.1에 모아 통합 뒤로 |
| 12 | 녹음 패널(media)·변환 창(recog) UX가 EDITOR와 갈림 | 일관성 | 자리 쪽에서 높이·위치를 강제(40%·하단), 7.4.10 규칙을 시험 패널로 단언, V5가 한 번씩 엶 |
| 13 | 객체 한도·큰 이미지로 페이지가 무거워짐 | iPad 메모리 | 한도 검사, 이미지 배치 크기 제한(6.12.2). 디코드 예산은 INK(7.4.5 v2.1 — 래스터 공유 장부 96 MB) |
| 14 | (수정 1회차) 텍스트 세션이 원치 않을 때 끝남(포커스 잃음이 끝 사유가 되어, Safari·iPadOS가 편집 중 포커스를 빼면 그때마다 커밋) 또는 끝나야 할 때 안 끝남(뷰포트가 같은 탭 묶음이라 캔버스 down이 바깥이 아님) | 되돌리기 단계가 쪼개지거나 키보드가 남음 | 캔버스 안의 끝은 라우터 표(6.11.5)로만 정하고 시험으로 덮는다(R47~R52, `text_box_test`). (수정 2회차) 1차 `EditorCanvasFocus`가 캔버스 down마다 포커스를 가져가 세션을 `focusLost`로 끝내던 경로는 세션 중 양보·끝난 뒤 되찾기로 막고(6.11.3, V7), `text_box_test`는 실제 `PageViewport`에서 `hasFocus` 유지를 단언한다. 포커스 잃음은 끝이 멱등이라 데이터 손실은 없다 — 쪼개짐 체감은 B-15에서 본다. 서식 바는 포커스를 가져가지 않게, 색 패널은 HEX 입력란 없이 |
| 15 | 자리 콜백을 동기 시작해도 Safari가 선택기·클립보드를 막음(사용자 동작 판정이 Flutter 웹 이벤트 처리 경로에서 끊김) [추측] | 이미지 삽입·붙여넣기가 주 기기에서 안 열림 | `onPressed` 안 동기 시작(4.3.1)·본문 context를 계약 문장으로 맞춤(C21-14). B-3에서 확인하고, 안 되면 media와 함께 '준비 중 시트의 단추를 한 번 더 누름'(media `importImageForNote`의 준비 중 시트 — CP-PDF-11) 경로로 바꾼다 |

---

## 12. 총괄에게 묻는 질문 · 계약 변경 제안

### 12.1 계약 변경 제안 (승인 전까지 이 계획서는 계약 원문대로 — 7.4.9)

초안의 제안 8건은 총괄 검토에서 모두 판정이 났다(00-review 2.2 — 승인 7, 수정해서 승인 1). 계약 v2.1에 들어간 곳을 '반영'에 적는다. 이번 수정에서 **새 계약 변경 제안은 없다.**

| # | 7장 | 제안 | 판정 (00-review 2.2) | v2.1 반영 | 이 계획서에서 |
|---|---|---|---|---|---|
| CP-E1 | 7.2.3 | CORE CP-1 지지 — 새 명령 3개를 1차 명령 모양(`const`, 이름 있는 인자, `label`)으로 | **승인**(CD2-06). `RemoveElements.elementIds`는 `List<ElementId>` — EDITOR도 형 변경까지 지지한다(1차 id 목록이 모두 `List`라 섞이지 않음, 검토 X-7) | C21-07 | 5.1.2 원문·호출 표(`elementIds: [id]`), 6.11.5·6.17 |
| CP-E2 | 7.2.3 규칙 | CORE CP-2 지지 — `TransformElements`가 텍스트 글자 크기도 배율 | **승인**(CORE CP-2). 단일 규칙 `PageObject.transformed`(CD2-07) | C21-06 | 6.6.5 — 초안의 '단일 텍스트 상자 `UpdateObjects` 우회' 삭제 |
| CP-E3 | 7.6 R2-B3 | R2-B3 목록에 `setPreviewObjects`·`hitTestTape`·`hitTestRecorded`·레이저 `end() == null`을 밝힌다 | **수정해서 승인** — R2-B3 문장을 03-ink 4.13 표 + 읽기 getter로 정리 | C21-29(7.6.2 R2-B3 행) | 5.2.4 표를 03-ink 4.13에 맞춤 |
| CP-E4 | 7.2.10 E-4 | 웹 접촉 중 접촉 비트가 빠진 `move` = 그 접촉의 끝 | **승인** | C21-14·C21-19(E-4) | 6.3.2 표시를 'EDITOR 내부'에서 '계약 문장'으로 |
| CP-E5 | 7.2.3 매핑 표 | 원문 표에 EDITOR 추가 행(내용 모두 지움 → `RemoveElements`, 전체 지우기 → `ClearPage(includeObjects: true)`, 복제)과 '(빈 쪽은 뺌)' | **승인** | C21-07(매핑 표 4행 추가 — 부분 지우개 + 도형 행 포함) | 5.1.2 |
| CP-E6 | 7.2.10 | `StylusExtraEvent.timestamp`(선택) | **승인**(P-B) | C21-14 | 4.3.4·6.5.3·6.5.4 |
| CP-E7 | 7.4.4 | EDITOR 키 밝히기(`editor.toolOptions`, `editor.playback.preRollMs` 정수 키, `tapToSeek` 위치) | **승인** | C21-24 | 6.18·6.19 |
| CP-E8 | 7.7 V5 | V5 '90° 회전'을 선택 메뉴 90° 돌리기 경로로 | **승인** | C21-32 | 6.6.6·E2-23, 부록 C 키 |

다른 영역의 제안에 대한 EDITOR의 답(검토 X-2·X-6·X-7 — 모두 v2.1에 들어감, EDITOR가 그대로 쓴다)

| 제안 | EDITOR 답 | 쓰는 곳 |
|---|---|---|
| CORE CP-1(명령 모양 + `elementIds: List`) | 지지(위 CP-E1) | 5.1.2 |
| CORE CP-2(텍스트·수식 글자 크기 배율)·CP-4·CP-5·CP-6 | 지지 — 미리보기도 `PageObject.transformed` 하나(CD2-07) | 5.1.1·6.6.5 |
| CORE CP-8(`FakeAudioRecorder.abandon`·`FakeAudioPlayback.calls`) | 지지 — 초안의 감싸개(`recording_playback.dart`)를 만들지 않음 | 5.1.5·E2-17 |
| INK CP-INK-2(부분 지우개 + 도형 → 합성 명령 하나) | 지지 — EDITOR는 `toCommand` 결과를 그대로 보내고 시험만 더함 | 5.1.2·6.17·`erase_v2_test` |
| INK CP-INK-3(`InkTextLayout.textStyleOf`·`strutStyleOf`) | **지지하고 사용**한다 — 편집기 글자 모양을 INK 함수로, 안쪽 여백 0(검토 S-7 → EDITOR-M7, 00-review 2.3 '텍스트 편집기 글자 모양'). R2-B3에 들어오므로(검토 질문 3 답) E2-01 시제품부터 쓴다 | 6.11.3 |
| INK 미리보기 > 숨김, `measureSync`(검토 X-3) | 사용 — 시트 방식은 E-6 숨김 + 같은 id 미리보기(미리보기가 보임), 초안 높이 `measureSync` | 6.11.6 |
| INK 테이프 '모두 보이기' 의미(03-ink 12.2 Q2) | INK 의미 그대로 받아들이고 EDITOR가 `updateContent` 뒤마다 다시 적용, 낱개 토글의 컨트롤러 수명 수용 | 6.14.4·I-10 |
| INK CP-INK-7(레이저 색 고정) | 수용 — 펜 선택기에서 레이저 색 숨김 | 6.14.3 |
| LIBRARY CP-L3(선택 문맥 `done` = `clearSelection`, 바꾸기 뒤에만)·CP-L5(`isVisible`은 그릴 때마다·가볍게) | 지지 — EDITOR 6.7.4와 같은 내용 | 4.3.1·6.7.4 |
| LIBRARY 도형 표본 형식 `{kind, points, viewScale}`(검토 X-6) | 개발자 메뉴가 그 형식 그대로 낸다(05-library 12.2 Q7 '모으기 EDITOR, 판정 LIBRARY'에 대한 답) | 6.20 |
| PDF CP-PDF-10(녹음 중 `play()` 무시)·CP-PDF-11(준비 중 시트) | 수용 — 녹음 중에는 탭 재생을 가로채지 않음, 이미지 `pick`은 본문 context로 동기 시작 | 6.15.3·6.12.2 |

### 12.2 질문 (답이 없으면 '기본 진행'대로 한다)

초안의 Q1~Q14는 총괄이 답했다(00-review 3.4 '질문 답'). 답을 '총괄 답'에 적고 그대로 따른다. Q15는 수정 1회차, Q16은 수정 2회차에서 생긴 확인 질문이다(Q16의 질문·기본 진행은 수정 3회차에 넓혔다 — 13.3). Q15·Q16은 최종 승인 때 총괄이 답했다(00-review '최종 승인', 13.4).

| # | 질문 | 기본 진행 | 총괄 답 |
|---|---|---|---|
| Q1 | 텍스트 IME 시제품(E2-01)을 동시 개발 첫 주에 `area2/editor` 빌드로 미리보기 채널에 한 번 올려 사용자 iPad에서 B-2만 먼저 볼 수 있는가(INFRA·총괄 경로) | 못 하면 통합 미리보기에서 B-2. 그 전에는 Chrome 시험만 | Hosting이 있으면 한다(`area2/editor` 브랜치 미리보기 채널 — U24) |
| Q2 | B-2에서 `inline`·`sheet`가 모두 불합격이면 안 B(`textarea`, P-C)를 2차 안에 해도 되는가 | 한다(SDK `dart:js_interop`만 — 의존 추가 없음) | 한다 |
| Q3 | 탭 재생 상태에서 녹음된 획 위 펜 점·테이프 위 펜 점이 점 획 대신 재생·드러내기가 되는 것(6.3.5) — (수정 1회차) 탭 재생 상태 = R-5 v2.1(녹음기 `idle`, 손가락: 패널 열림 또는 재생·일시정지 / 펜 점: 재생·일시정지만) | 그대로 | v2.1 R-5로 좁혀 그대로(U26) |
| Q4 | 자동 도형 보정 대상 펜: 볼펜·만년필·연필·마커·붓펜·캘리그래피·점선(형광펜·레이저·테이프 제외) | 그대로 | 기본값 |
| Q5 | 텍스트 상자 내용을 모두 지우고 나가면 상자 삭제(`RemoveElements`) | 그대로 | 기본값 |
| Q6 | 이미지 페이지 크기 = 지금 페이지 크기 + 이미지 방향, `contain`. 페이지 패널 '배경 바꾸기'에 이미지 고르기는 이번에 넣지 않음 | 그대로 | 기본값 |
| Q7 | `EditorAction.previousTool` = 마지막으로 쓰던 (도구, 펜 종류)와 맞바꿈(Apple '이전 도구') | 그대로 | 기본값 |
| Q8 | 선택 우선 규칙, 붙여넣기 뒤 올가미로 도구를 바꾸지 않음(1차는 바꿨음) — (수정 1회차) (a′): 그리기 도구에서는 핸들만 우선, 본체 끌기 이동은 올가미·붙여넣기·삽입 선택만(6.6.2) | (a′) | (a′) — 붙여넣기 뒤 도구는 바꾸지 않고 본체 끌기는 허용 |
| Q9 | 자동 도형 보정으로 바뀐 도형은 녹음 연결을 잃음(객체에 녹음 필드 없음) | 받아들임. 필요하면 다음 라운드에 객체 녹음 필드 | 기본값 |
| Q10 | 재생 '따라가기'(쓰이던 페이지로 자동 이동)는 이후(1.3) | 이후 | 기본값 |
| Q11 | 레이저를 읽기 전용(휴지통) 노트에서도 쓸 수 있게 함(저장 안 하므로) | 허용 | 기본값 |
| Q12 | `EditorSettings`·`GestureSettings` 추가 필드와 공개 enum 추가를 7.0.1 표에 올리지 않는다 | 올리지 않음 | 올리지 않아도 된다. 다만 `PlaybackHighlightStyle`은 빼고 INK enum을 쓴다 — 반영(4.1·4.3.3, `WebTextInputMode`도 내부로) |
| Q13 | 펜 버튼 동작을 모든 도구에서 같게(도형·텍스트 도구 중에도 버튼 = 지우개) | 그대로 | 기본값 |
| Q14 | 스퀴즈 `toolPalette` = 빠른 펜 팝업(펜 종류·색·굵기), `colorPalette` = 색 팝업, 둘 다 `hoverPosition`에 | 그대로 | 기본값 |
| Q15 | (수정 1회차) EDITOR 내부 device 키 2개(`editor.deviceState` — 웹 입력 방식·도형 표본 토글·Pencil 첫 이벤트, `editor.textDraft` — 긴 텍스트 세션 초안, P-B)를 7.4.4 '키 확정' 목록에 올리지 않는다 — 다른 영역이 읽지 않는 내부 키이고 1차 `editor.toolSelection`·`editor.viewport`와 같은 취급이다(6.18) | 올리지 않음 | 올리지 않는다(기본 진행 그대로 — 다른 영역이 읽지 않는 기기 키는 1차처럼 영역 내부 키로 둔다. 다른 영역이 읽게 되면 그때 7.4.9 절차) |
| Q16 | (수정 2회차) E2-21과 같은 묶임이 다른 영역 완료 조건에도 있다: INFRA V5 2단계 '합성 멈춤으로 자동 도형'(00-overview 7.7.2 V5 문장, 01-infra 9.1 V5 단계 표 — 기대 결과 `ShapeObject` 2)과 7.7.1 5단계 LIBRARY `ink_recognition/test/integration/shape_assist_flow_test.dart`는 INK T39(P-B)가 있어야 통과하는데(수정 3회차 — V5 단계는 앱의 실제 EDITOR를 거치므로 EDITOR E2-15(P-B — `shapeAssistFor`가 `holdToSnap`을 넘김)도 있어야 한다. LIBRARY 시험은 INK 컨트롤러를 직접 쓰므로 T39만), 7.7.2는 V3·V5를 '전부 통과해야 2차 통합 완료'로 둔다. 3.4대로 T39(V5는 T39 또는 E2-15)를 미루면 2차 통합 완료를 판정할 수 없다. EDITOR는 E2-21에서 그 단계를 떼어 E2-21b(P-B)로 옮겼다(8.3) — V5·LIBRARY 쪽도 'T39(V5는 T39·E2-15) 병합 때만'으로 할지 | EDITOR는 E2-21b로만 처리하고 다른 영역 문서는 고치지 않는다. (수정 3회차) E2-23·10 #5: V5(·V6)의 자동 도형 단계가 P-B(INK T39 **또는** EDITOR E2-15) 미병합으로 실패하면 EDITOR 원인 실패로 세지 않고 진행 기록 '2차' 절에 '미룸 — 빠진 작업(T39/E2-15)'으로 남기며 2차 완료 판정을 막지 않는다. (총괄 직접 수정 — 13.4) 그 실패로 뒤 단계가 돌지 않을 때의 대체 판정 문장은 지웠다 — 총괄 답으로 V5 본 흐름에서 자동 도형 단계가 빠졌고, 단계가 실패할 때 원인을 좁히는 EDITOR 시험은 E2-23의 단계별 대응(2~5단계 `objects_smoke_test`, 6~7단계 `recording_link_smoke_test` + `recording_panel_slot_test`, 8단계 `selection_extensions_test`·`insert_menu_test`, 9단계 `initial_focus_test`)을 따른다. 둘 다 병합됐는데 실패하면 보통 실패로 다룬다 | **V5 문장을 고친다**(계약 v2.2 C22-07). ① 7.7.2에 'P-B에 기대는 기준' 규칙과 표를 둔다 — 표의 P-B 작업이 모두 병합됐을 때만 그 기준(또는 부분)이 판정에 들고, 아니면 통합 진행 기록에 '미룸 — 기준, 빠진 작업'으로 남아 2차 통합 완료를 막지 않는다. P-B 단계는 P-A 시험 안에 두지 않고 따로 뗀 시험으로 둔다(시험이 실행 중에 병합 여부를 알 수 없으므로 — 이 계획서 E2-21b와 같은 판단). ② V5 본 흐름에서 '합성 멈춤으로 자동 도형'을 빼 **V5b**(`app/test/integration/app_smoke_shape_assist_test.dart`, VM — INK T39·EDITOR E2-15·LIBRARY L2-06이 모두 병합됐을 때만 INFRA가 만듦)로 옮긴다. V5 2단계 기대값은 `ShapeObject` 1(도구)이다(01-infra 9.1 — 총괄 직접 수정). ③ 7.7.1 5단계 LIBRARY `shape_assist_flow_test`(L2-I3 — INK T39·LIBRARY L2-06), V9의 도형 판정 1,400개(L2-06), V13(SYNC 서버 함수·LIBRARY L2-16), V15 기대 목록의 '자동 도형 보정'(E2-15·L2-06)도 같은 규칙이다. EDITOR 쪽은 E2-21·E2-21b 구성 그대로이고 E2-23·10 #5를 이 답에 맞췄다 |

---

## 13. 검토 반영 내역

### 13.1 수정 1회차 (2026-11-05) — 총괄 검토 [00-review.md](00-review.md) 3.4 · 대리 검토 [reviews/editor.md](reviews/editor.md) · 계약 v2.1

공통 처리(모든 항목의 바탕)

- **계약 원문 교체**: 4.2(7.2.10)·5.1.1(7.2.2)·5.1.2(7.2.3 — 블록 둘과 매핑 표·끝 문장)·5.1.3(7.2.4 오디오 포트·R-1~R-8)·5.1.4(7.2.6 앞부분 — 바뀐 곳 없음)·5.1.5(7.6 시험 도우미 블록의 앞부분: `note_core/testing.dart`·`testing_web.dart`·`ink_engine/testing.dart`)·5.2.1(7.2.9 — 펜 extras·L-1 표(층 4′)·컨트롤러/세션/편집 블록·`toCommand` 표·수식/글꼴/텍스트 배치 블록(원문 블록의 뒷부분)·끝 문장)을 00-overview 7장 v2.1에서 **글자 그대로** 다시 옮겼다. 파이썬으로 코드 블록을 기계 대조했다 — 통째로 옮긴 블록은 원문과 같고, 일부만 옮긴 셋(7.2.6 앞부분, 7.6 앞부분, 7.2.9 마지막 블록 뒷부분)은 원문의 이어진 부분 문자열이다. 표시 줄을 `// 계약 v2.1 …`로 바꾸고 생략한 부분을 적었다.
- **상태 줄·기준**: 머리말을 '수정 1회차 (통합 계약 v2.1 기준)', 1차 기준 v1.5(C21-01), 바탕 코드 = 1차 통합 HEAD(CD2-01 — `lib/`는 1차 작업 트리와 같고 `test/`는 61파일 [확인])로 고쳤다.
- **실험 V6 추가**: `material_ui` `TextField`(collapsed)·`TextFieldTapRegion` 묶음·선택 메뉴 동작을 VM 위젯 시험 4개로 확인했다(머리말 표 — `/tmp/claude-0/plan57-scratch/editor57/probe/test/text_region_probe_test.dart`).

| # | 근거 | 무엇을 어떻게 바꿨나 | 위치 |
|---|---|---|---|
| EDITOR-M1 | 검토 M-1, CD2-08 | INK 가짜를 두지 않는다고 못 박고(`final class`), 위젯 시험 단언을 셋으로 나눴다 — ① EDITOR 결정은 이음새(순수 함수 `shapeAssistFor`, `PlaybackHighlightLogic`의 출력 주입 `PlaybackFocusSink`, `TextEditState`에서 나오는 `hiddenIdsOf`, 추가로 `tapToSeekActive`·`selectionPriority`) ② INK에 넘긴 값은 v2.1 읽기 getter(`previewObjects`·`hiddenObjectIds`·`playbackFocus`·`StrokeSession.shapeAssist` — 시험에서만 읽음, I-15) ③ CORE 결과. 레이저는 실제 R2-B3(`end() → null`)로 동시 개발 중 시험, 자동 도형 실제 멈춤 흐름은 INK `FakeInkShapeFitter`·`SyntheticInk.loopThenHold`로 통합 E2-21에서. 5.2.4 표를 03-ink 4.13·7.6.2 v2.1 R2-B3 행에 맞춰 다시 썼다. E2-01·E2-08·E2-09·E2-10·E2-14·E2-15·E2-17·E2-21의 완료 조건 문구를 위 단언으로 바꿨다 | 5.2.2 I-2·I-15, 5.2.4, 5.5, 6.10, 6.11.2, 6.15.2, 8.2, 9.2 |
| EDITOR-M2 | 검토 M-2 | 텍스트 세션 끝을 라우터가 정한다: 펜·마우스 접촉(6.3.6 3), 한 손가락 탭 확정(6.3.5 ⓪), 길게 누르기 동작, 2·3 손가락 undo/redo만 끝내고 두 손가락 끌기·핀치·펜 전용 한 손가락 스크롤·거부된 손바닥·웹 공중 down은 유지(6.11.5 표). 세션 중 손가락은 펜 전용처럼(핀치의 첫 손가락이 획을 시작하지 않게 — 6.3.4, `InputPolicy.textSessionActive`). 페이지 뷰포트를 편집기·서식 바와 같은 탭 묶음에 넣었다 — 다만 검토가 말한 별도 `TextEditGroup` 대신 **Flutter 기본 묶음 `EditableText`**를 쓴다: Flutter 선택 손잡이·메뉴가 기본 묶음의 `TextFieldTapRegion`으로 감싸여 있어 같은 묶음이어야 손잡이·메뉴를 눌러도 세션이 끝나지 않는다(V6 ④, `text_selection.dart` 1805·1836·1980). 뷰포트 묶음은 세션 중에만 `enabled`(다른 입력란 영향 없음 — V6 ③). 편집기는 입력 `Listener`의 위쪽 형제로 두어 편집기 위 접촉이 라우터에 가지 않는다. `TextEditEndReason`에 `focusLost`(키보드 내림·포커스 이동)와 `penContact`·`canvasTap`·`longPress`를 더했다. 시험: `text_box_test`에 두 손가락 끌기·핀치(유지·명령 0·오버레이 위치 갱신)·손바닥·펜 전용 한 손가락 끌기·공중 down·포커스 잃음·묶음 밖 down, `input_router_test` R49~R52 | 6.1, 6.3.1, 6.3.4, 6.3.5, 6.3.6, 6.11.2~6.11.5, E2-04b·E2-10, 11 #14 |
| EDITOR-M3 | 검토 M-3, CD2-14, R-5 v2.1 | 탭 재생 상태를 순수 함수 `tapToSeekActive`로 두고 계약 R-5 그대로(설정 켬 + 녹음기 `idle` + 손가락: 패널 열림 또는 `playing`·`paused` / 펜 점: `playing`·`paused`만 + 이 노트 녹음). 펜 점 탭 문턱 4 px·200 ms(`penTapMaxMovement`·`penTapMaxDuration` — 손가락 20 px·250 ms와 따로, 테이프 ②도 같은 문턱). 판정은 `_session.end()` 전, 가로채면 `cancel()`(end 뒤 가로채기 경로 없음). 손가락 필기 모드의 손가락은 펜 점 문턱 + 손가락 조건. E2-17에 시험 셋(① 정지 직후 `ready`·패널 닫힘 → 15 px 획 커밋 ② 패널 열림 + `ready` → 손가락 탭 seek·펜 점은 획 ③ 녹음 중 → 가로채지 않음)과 `unit/tap_to_seek_state_test.dart`. Q3 문구를 v2.1 조건으로 | 5.1.3 R-5 규칙, 6.3.5, 6.3.7, 6.14.4, 6.15.3, E2-04b·E2-17, 12.2 Q3 |
| EDITOR-M4 | 검토 M-4, Q8 답 (a′) | 선택에 `origin`(`lasso`·`paste`·`insert`·`drawn`·`tap`)을 두고 6.6.2를 표로 다시 썼다: 그리기 도구(펜·지우개·도형·텍스트)에서는 핸들만 우선, 본체 끌기 이동은 `lasso`(임시 올가미 포함)·`paste`·`insert`만, 도형 도구로 그려 생긴 선택(`drawn`)과 탭 선택(`tap`)의 본체 down은 선택을 풀고 새 도형·새 획. 올가미 도구는 1차 그대로. 판정은 순수 함수 `selectionPriority`(라우터 `hitsSelection`도 같은 함수). 시험 셋: E2-09 '사각형 안에서 원 끌기 → `AddObjects` 1회', E2-12 '이미지 삽입 직후 본체 끌기 → 이동', E2-06 '펜 도구 + 붙여넣은 선택 본체 끌기 → 이동' + `unit/selection_priority_test.dart` | 6.3.6 5, 6.6.1~6.6.3, 6.9.2, 6.11.1, 6.12.2, 6.13.2, E2-06·E2-09·E2-12, 11 #3, 12.2 Q8 |
| EDITOR-M5 | 검토 S-2 승격 | `ObjectResize.cornerScale(frame, corner, deltaPagePt) → Affine2`(frame 지역 축으로 delta를 돌려 대각선에 투영한 균일 배율, 원점 = 회전된 반대 모서리, 최소·최대 크기 클램프)를 두고 단일 객체 모서리 핸들 전부(폴리라인·타원·텍스트·이미지·수식)가 이것 → `setPreviewTransform` → `TransformElements`를 쓴다. `object_resize_test`에 '30° 회전 이미지 모서리 끌기 → 반대 모서리 고정·비율 유지' 등 넷. 폴리라인 회전을 상대 각 무리로 옮기고 꼬리표도 상대 각. 회전 시험 각을 경계 안쪽(32° → 30°, 47° → 45°, 20° 그대로)으로 | 5.2.2 I-6, 6.6.4~6.6.6, E2-06·E2-08, 11 #4 |
| EDITOR-M6 | 검토 S-6 승격, CD2-15, C21-14·C21-22 | 자리 콜백 실행 규칙을 바꿨다: `onPressed` 안에서 두 번 누름 검사 → `onSelected`·`pick` Future를 **동기적으로 시작** → 메뉴·시트 닫기 → 기다리기(동기 예외여도 닫음). 넘기는 `context` = 에디터 본문(`EditorBody`)의 것, 끝난 뒤 처리는 `mounted` 검사 뒤. 이미지 출처(삽입 메뉴·페이지 추가 시트·컨텍스트 메뉴·⌘V)와 확장 선택·삽입 항목 모두. 9.4 B-3에 '한 번 눌러 바로 열림'(7.8 v2.1 B-3 문장). 시험: `selection_extensions_test`·`image_insert_test`·`add_page_sheet_test`·`insert_menu_test`에 '메뉴가 열려 있는 동안 불림·본문 context' | 4.3.1, 6.7.4, 6.8, 6.12.2·6.12.3, 6.13.2, 부록 A, E2-07c·E2-12, 9.3, 9.4 B-3, 11 #15 |
| EDITOR-M7 | 검토 S-7 승격, CP-INK-3 | 편집기를 `material_ui` `TextField`(`InputDecoration.collapsed` — 안쪽 여백 0 확인 V6 ①)로 — 두 번 탭 낱말 선택·선택 손잡이·적응형 붙여넣기 메뉴(V6 ④). 글자 모양은 INK `InkTextLayout.textStyleOf`·`strutStyleOf` 그대로(EDITOR 자체 변환 삭제), 12.1에서 CP-INK-3 지지·사용을 밝혔다. 1.3 문구를 '캔버스 수준 붙여넣기(시스템 텍스트 → 새 상자)는 없음, 편집 중 글자 붙여넣기·복사는 됨'으로, 6.7.6의 ⌘C·⌘V를 '시스템 클립보드 글자 편집'으로. B-15를 9.4에 | 1.2, 1.3, 3, 6.7.6, 6.11.3, 6.11.7, 12.1, 9.4 B-15, E2-01 |
| EDITOR-M8 | PDF 검토 M-8, CD2-14, R-5 v2.1 | `PlaybackHighlightLogic`에 '활성' 규칙: 이 녹음을 연 뒤 한 번이라도 `playing`이었거나 `seekMs` 뒤에만 초점, 그 전(`ready` — 패널 자동 열기·정지 직후 자동 열기)은 `null`. EDITOR 탭 재생은 `markSeek()`, 패널 탐색은 열림 때 `positionMs()`와의 차로 안다(상태 이벤트마다 + 패널 열림·활성 전이면 250 ms마다 — 플랫폼 호출 없음). `playback_highlight_test`에 '정지 직후 흐림 없음', 통합 `recording_link_smoke_test`에도. CP-PDF-10(녹음 중 `play` 무시)을 6.15.3에 — 녹음 중에는 가로채지 않는 이유 | 5.2.2 I-9, 6.15.2·6.15.3, E2-17·E2-21, 9.4 B-8 |
| EDITOR-M9 | C21-07, CP-INK-2 | 명령 호출을 v2.1 모양으로: 5.1.2에 '실제 호출' 표를 두고 `AddObjects(pageId:, objects:)`·`UpdateObjects(…)`·`RemoveElements(pageId:, elementIds: [id])`·`ClearPage(pageId:, filter:, includeObjects: true)`·`TransformElements(…, scaleStrokeWidth: true)`·`InsertPages(drafts:, position:)`로 적었다. 부분 지우개 + 도형 행(`InkEdit(splitStrokes, removedObjectIds)` → `CompositeCommand([SplitStrokes 또는 RemoveStrokes, RemoveElements])`)과 획 지우개 + 도형 행을 더했다. `erase_v2_test`에 '부분 지우개가 도형을 지남 → 명령 1개·되돌리기 1번에 도형과 조각 복구'. 초안의 '위치 인자 가정'(5.5)을 지웠다 | 5.1.2, 5.5, 6.11.5, 6.17, E2-19 |
| EDITOR-M10 | 검토 S-8, INK X-4·X-5·X-6 | 시트 방식: E-6 숨김은 그대로 두고 같은 id 미리보기를 함께(미리보기 > 숨김 — v2.1이라 초안이 보임, 검토가 제시한 '함께' 쪽 — E-6 문장과 어긋나지 않게), 초안 높이 `measureSync`(null이면 직전 값 → `measure`), 입력 패널을 **본문 위쪽**(높이 ≤ 40%, `viewInsets`가 있으면 줄임 — EDITOR 자체 UI라 7.4.10 바닥 시트 규칙 대상 아님). 빈 곳 끌기 새 상자 테두리는 EDITOR overlay(`NewTextBoxOutline`)가 직접(INK 변경 없음). 테이프 '모두 보이기'는 `PageMount`가 `updateContent` 뒤마다 다시 적용, 낱개 토글의 컨트롤러 수명(마운트에서 빠지면 다시 가림)을 받아들임 | 5.2.2 I-3·I-10, 5.2.3 K-8, 6.11.1, 6.11.6, 6.14.4, E2-01·E2-02·E2-14 |
| EDITOR-M11 | 검토 S-5, LIBRARY X-1 | '마지막 획 JSON 복사'를 지우고(점이 base64이고 바뀐 획은 저장되지 않아 쓸 수 없음) 도형 표본 링 버퍼를 뒀다: 개발자 토글 '도형 표본 모으기'(`EditorDeviceState.collectShapeSamples`, device, 기본 끔)가 켜졌을 때만 최근 5개 펜 세션의 페이지 pt 점·`viewScale`·결과를 메모리에, 개발자 메뉴가 기대 종류 시트 뒤 LIBRARY 형식 `{kind, points, viewScale}`으로 복사 | 6.10, 6.19, 6.20, E2-20·E2-24, 9.4 B-4, 부록 C |
| EDITOR-M12 | C21-14·19·24, 검토 S-10, Q12 답 | CP-E4: 6.3.2 행 표시를 '계약 E-4 (v2.1)'로. CP-E6: `timestamp`를 포즈 호버·롤 유효 시간에(없으면 `Stopwatch`, 두 기준을 섞지 않음). CP-E7: 6.18 키 표. CP-E8: E2-23. E-7 `isVisible` 예외(숨김 + 보고만). 능력은 앱 시작 때 한 번(설정 안내 '다시 열 때 반영'), 스퀴즈·롤 설정 줄은 첫 이벤트 뒤(`seenSqueeze`·`seenBarrelRoll` — device 저장). `EditorSettingKeys.all` 형 → `List<core.SettingKey<Object?>>`(쓰는 곳은 EDITOR 시험 하나 [확인]), `editorPreRollMsProvider`(루트·500 ms·[0, 5000]). `PlaybackHighlightStyle` 대신 `ink.InkPlaybackStyle`, `WebTextInputMode`는 내부 device 키 `editor.deviceState`로 옮겨 공개 이름 16 → 14 | 1.5, 4.1, 4.3.1, 4.3.3, 4.3.4, 6.3.2, 6.4.4, 6.5.1·6.5.3·6.5.4, 6.18, 6.19, 12.1 |
| EDITOR-M13 | 검토 S-3 | E2-07 → E2-07a(클립보드·붙여넣기·컨텍스트 메뉴·단축키)·E2-07b(선택 메뉴·색)·E2-07c(확장 항목·`ExtensionRunner`), E2-04 → E2-04a(접촉·버튼·지우개 끝, R34~R42)·E2-04b(손가락 동작·길게 누르기·펜 점 탭 훅·세션 중 손가락, R43~R52). 마이크 단추를 E2-16이 만들고 E2-16 선행에서 E2-13을 뺐다(E2-13은 배치만 — 선행에 E2-16). E2-01은 선행을 늘리지 않고 최소 진입점(개발자 메뉴 '텍스트 상자 시험')을 함께 만든다(E2-03을 기다리지 않아 첫 작업으로 남음). 다른 절의 작업 번호 인용을 모두 고쳤다 | 1.2, 2, 6.11.1, 6.13.1, 8.2·8.4, 9.1, 9.4 |
| EDITOR-M14 | C21-26, 검토 S-9 | Chrome 시험 전부 `setUpAll(useInkTestFonts)`. 9.2 Chrome 행과 E2-01·E2-21 설명을 '웹 컴파일·세션 규칙'으로 — `tester.enterText`는 `TestTextInput`이 채널을 가로채 DOM 입력·IME를 거치지 않으므로 IME 판정은 B-2·B-15뿐. E2-11은 시작 전 시제품 시험으로 플랫폼 뷰 실행 가능성 확인 | 5.1.5, 6.11.6, 8.2(E2-01·E2-11·E2-21), 9.2 |

권장(00-review 3.4 '권장' — 영역 판단)

| # | 반영 | 무엇을 어떻게 / 반영하지 않은 이유 | 위치 |
|---|---|---|---|
| S-1 | 반영 | `UpdateObjects`를 보내기 전에 `session.pageIfLoaded(pageId)?.objectById(id) == null`을 동기 검사해 '원본 사라짐'을 명령 없이 처리(핸들: 미리보기만 지움, 텍스트: 새 id `AddObjects`) — 1차 `_rejected` `default:`가 `ArgumentError`를 보고 + 스낵바로 처리함을 확인했다(`editor_commands.dart` 608–635). 검사와 실행 사이 경합만 1차 처리. E2-08·E2-10에 '스낵바·보고 없음' 단언 | 5.1.2, 5.1.6, 6.6.5, 6.6.7, 6.11.5, 6.21 |
| S-11 | 반영(일부 P-B) | 읽기 전용 거절 때 쓴 글을 시스템 클립보드로 복사 + 안내(P-A, E2-10). 긴 세션 초안의 주기 저장(내부 device 키 `editor.textDraft`, 5 s)·다시 열 때 '되살리기'는 P-B 작업 E2-10b로 두었다 — 명령은 여전히 세션 끝 1회(E-6) | 6.11.2, 6.11.5, 6.18, 6.21, E2-10b |
| S-12(a) | 반영하지 않음 | 13절 = 검토 반영 내역 + 부록 A·B·C 모양을 총괄이 인정했다(CD2-25 — 번호를 다시 매기지 않음) | — |
| S-12(b) | 반영 | '펜 뒤쪽 지우개' 줄을 웹에서 숨김(웹 엔진이 `invertedStylus`를 만들지 않음) | 6.4.4 |
| S-12(c) | 반영 | `prefersPencilOnlyDrawing`을 반영한 펜 전용 판정은 1차 `InteractionHost.policy`(라우터용 `InputPolicy` 스냅샷)가 계산 — `EditorSettings.isPenOnlyEffective`는 그대로 | 6.5.3 |
| S-12(d) | 반영 | 'EDITOR 몫' = INK 호출을 포함한 경로 전체(INK 가짜 없음), 1차 성능 스모크의 여유 규칙(데운 뒤 5회 중 최단값) 그대로 | 6.22 |
| S-12(e) | 반영 | `no_platform_imports_test`의 자체 시험은 임시 폴더의 가짜 트리로 | E2-00 |
| S-12(f) | 반영 | 회전 각을 포인터 좌표로 만들 때 맞춤 경계값을 피함(EDITOR-M5와 함께) | 6.6.6, E2-06 |

대리 검토의 나머지 항목

| 검토 항목 | 처리 |
|---|---|
| S-2·S-6·S-7 | 총괄이 반드시로 올림 → EDITOR-M5·M6·M7 |
| S-3·S-4·S-5·S-8·S-9·S-10 | EDITOR-M13·M1·M11·M10·M14·M12에 담김 |
| X-1(INK getter) | CD2-08로 계약에 들어옴 → 5.2.1·5.2.4 |
| X-2(CP-INK-2·3, 테이프 수명) | 12.1 '다른 영역 제안에 대한 답', 6.11.3, 6.14.4, 6.17 |
| X-3(미리보기 > 숨김) | 계약 v2.1(7.2.9) → 6.11.6 |
| X-4·X-5(PDF media — 탭 재생 상태·동기 시작·context) | R-5·7.2.10 v2.1 문장 → 6.3.5·6.15.3·4.3.1 |
| X-6(LIBRARY 표본 형식, CP-L3·CP-L5) | 6.20, 12.1 |
| X-7(CORE `elementIds` 형, CP-8) | `List` 형까지 지지(12.1 CP-E1), CP-8로 감싸개 없음 |
| X-8(INFRA CP-E8·능력 한 번) | CP-E8 승인(E2-23), 6.5.1 안내 |
| C-1~C-7 | 모두 v2.1에서 닫힘(00-review 2.3): C-1 getter(CD2-08), C-2 `final class`(5.2.1 원문), C-3 능력 시작 때 한 번(CD2-24 — 6.5.1), C-4 `isVisible` 예외(E-7 — 4.3.1), C-5 CP-E4 계약 문장(6.3.2), C-6 명령 표기(5.1.2), C-7 R-5 탭 재생 상태(6.3.5) |
| 검토 질문 1~5 | 00-review 3.4 답대로: 1 (a′)·B-5는 올가미·붙여넣기 선택으로(6.6.2) · 2 펜은 재생 중에만(6.3.5) · 3 CP-INK-3 함수는 R2-B3에 들어옴 — E2-01부터 사용(6.11.3) · 4 시트 패널은 EDITOR 자체 UI(6.11.6) · 5 표본은 개발자 토글 켬일 때만(6.20) |
| 초안 Q1~Q14 | 총괄 답을 12.2 '총괄 답' 칸에 적고 따랐다. Q15(내부 키 둘)는 이번 수정에서 생긴 확인 질문 |

### 13.2 수정 2회차 (2026-11-05) — 총괄 승인 검토의 새 모순 2건 · 계약 v2.1(바뀐 곳 없음)

공통 처리

- **계약 버전·원문**: 00-overview 7장은 여전히 v2.1(7.9 C21-01~C21-35)이다. 이 계획서의 `// 계약 v2.1 …` 표시 아래 코드 블록 15개를 파이썬으로 다시 대조해 모두 00-overview의 부분 문자열(글자 그대로)임을 확인했다 — 이번 수정은 계약 블록을 건드리지 않고, 새 계약 변경 제안도 없다(12.1). 상태 줄을 '수정 2회차 (통합 계약 v2.1 기준)'로 고쳤다.
- **실험 V7 추가**: 총괄 시제품(`/tmp/claude-0/plan57-scratch/approve-editor/probe/test/canvas_focus_probe_test.dart`)의 결과를 대조 시험으로 다시 얻고, 고친 규칙(세션 중 양보·끝난 뒤 되찾기)을 VM 위젯 시험 6개로 확인했다(`/tmp/claude-0/plan57-scratch/editor57/probe/test/canvas_focus_session_probe_test.dart`, 머리말 표).
- 다른 파일은 고치지 않았다. 다른 영역 완료 조건에 남은 같은 묶임은 12.2 Q16으로 총괄에게 넘겼다.

| # | 근거 | 무엇을 어떻게 바꿨나 | 위치 |
|---|---|---|---|
| 1 | 총괄 승인 검토 — EDITOR-M2 후속(새 모순: 1차 `EditorCanvasFocus`가 텍스트 세션을 끝냄) | 1차 `EditorCanvasFocus`(`input/editor_shortcuts.dart` 222–230 [확인])는 캔버스 전체를 감싸고(`viewport/page_viewport.dart` 117 [확인]) 포인터 down마다 마이크로태스크로 캔버스 포커스를 요청하므로, 편집기를 그 바깥 위쪽 형제로 두고 `focusLost`를 끝 사유로 넣은 수정 1회차 설계에서는 두 손가락 끌기·핀치·거부된 손바닥·펜 전용 한 손가락 끌기·웹 공중 down의 첫 down에 세션이 끝났다(6.11.5 '유지'·E2-10 '세션 유지·명령 0'·B-15와 모순 — V7 ①로 재현). 6.11.3에 **'캔버스 포커스 양보'** 항목을 새로 두었다: ① 텍스트 세션 동안(`editorTextEditProvider != null`) `EditorCanvasFocus`는 포인터 down에서 포커스를 요청하지 않는다(판정은 그 down 처리 순간의 상태 — 라우터가 같은 down에서 먼저 끝을 시작해도 끝이 멱등이라 명령 1회) ② 캔버스 포커스는 세션이 `null`이 된 뒤 `ref.listen` → 마이크로태스크로 되찾되, 주 포커스가 `null`·범위 노드·편집기 자신일 때만(다른 입력란은 빼앗지 않음 — V7 ⑤) ③ 그래서 `focusLost`의 출처는 키보드 '내림'·시스템 포커스 이동·다른 입력란뿐 ④ 웹 DOM 입력 요소의 브라우저 쪽 blur는 [추측]으로 B-15에 ⑤ 시험은 실제 `PageViewport`에서. 6.3.6 3·6.3.1 표·6.11.2 `focusLost` 주석·6.11.5 표(유지 행·`focusLost` 행)·3절 트리(`editor_shortcuts.dart`)에 같은 규칙을 적었다. E2-10 작업 내용에 '`EditorCanvasFocus` 세션 중 양보·끝난 뒤 되찾기'를, `text_box_test`에 '두 손가락 끌기·핀치·거부된 손바닥·펜 전용 한 손가락 끌기·공중 down 뒤 편집기 `focusNode.hasFocus == true`·포커스 잃음 0회(실제 `PageViewport`, 마이크로태스크를 비운 뒤)', '펜 접촉·한 손가락 탭으로 끝난 뒤 캔버스 주 포커스(키 P → 펜)', '`unfocus()` → `focusLost` → 캔버스 주 포커스', '다른 입력란 포커스 → `focusLost`·캔버스가 빼앗지 않음'을 넣었다. 6.11.6 순서에 'E2-01 미리보기에서는 IME·선택 손잡이만, B-15 스크롤 항목은 E2-10 뒤'를, 9.4 B-15·11 #14에 이 규칙을 더했다 | 머리말 V7, 3, 6.3.1, 6.3.6, 6.11.2, 6.11.3, 6.11.5, 6.11.6, E2-10, 9.4 B-15, 11 #14 |
| 2 | 총괄 승인 검토 — 새 모순(완료 조건이 P-B에 묶임) | E2-21 `integration/objects_smoke_test.dart`의 '실제 `ShapeAssist` 멈춤 → 자동 도형' 단계는 INK T39(03-ink 8.2, P-B)와 E2-15(P-B)가 있어야 통과하는데 10 #5가 E2-21 통과를 2차 완료 조건으로 두어, 00-overview 3.4대로 M5-6을 미루면 완료를 판정할 수 없었다. 두 안 중 **별도 시험 파일로 떼는 쪽**을 택했다 — 한 파일 안의 조건부 단계는 'T39가 병합됐는가'를 시험이 실행 중에 알 길이 없어(INK 공개 표면은 T39 전후로 같음 — `shapePreview`가 늘 `null`인 B3 동작도 계약을 지킴, 03-ink 8.2) 건너뛰기 판정이 사람 손에 남기 때문이다. `objects_smoke_test`에서 그 단계를 빼고 'P-A 기능만, `inkShapeFitterProvider`는 override하지 않음(기본 `NoShapeFitter` → `off`라 획 단계가 T39 유무와 무관)'을 적었다. 새 P-B 작업 **E2-21b** `integration/shape_assist_smoke_test.dart`(`FakeInkShapeFitter(fit: 사각형)` + `SyntheticInk.loopThenHold` + `fake_async` 600 ms → `ShapeObject` 1·획 0·1단계, 되돌리기·다시 실행·다시 열기)를 8.3에 두고, **INK T39와 E2-15가 둘 다 병합됐을 때만** 만들며 아니면 진행 기록에 '미룸 — 빠진 작업'으로 남긴다. 10 #5에 'E2-21은 P-A만, E2-21b는 #1 규칙(P-B — 완료 판정을 막지 않음)'을 적었다. E2-15·5.1.5·5.2.4·5.5·2.1 표·M5-6 행·3절 트리·9.1·9.2의 'E2-21에서 실제 멈춤' 인용을 E2-21b로 고쳤다. 13.1 EDITOR-M1 행의 '통합 E2-21에서'는 수정 1회차 기록이라 그대로 둔다 | 1.2 M5-6, 2.1, 3, 5.1.5, 5.2.4, 5.5, E2-15, E2-21·E2-21b(8.3), 9.1, 9.2, 10 #5, 12.2 Q16 |

### 13.3 수정 3회차 (2026-11-05) — 총괄 검토의 새 모순 2건(완료 조건이 P-B에 묶임) · 계약 v2.1(바뀐 곳 없음)

공통 처리

- **계약 버전·원문**: 00-overview 7장은 여전히 v2.1(7.9 C21-01~C21-35)이다. `// 계약 v2.1 …` 표시 아래 코드 블록 15개를 파이썬으로 다시 대조해 모두 00-overview의 부분 문자열(글자 그대로)임을 확인했다. 이번 수정은 계약 블록과 5.1.2의 원문 매핑 표를 건드리지 않고(고친 곳은 그 아래 EDITOR '명령 매핑 전체' 표), 새 계약 변경 제안도 없다(12.1). 상태 줄을 '수정 3회차 (통합 계약 v2.1 기준)'로 고쳤다.
- **같은 종류의 묶임 점검**: 5.1.2 '명령 매핑 전체' 표 16행을 8.2 완료 조건과 대조했다. '자동 도형 보정 확정' 행 말고는 모두 P-A 작업의 시험이 덮는다(E2-06 `rotate_test`·`lasso_mixed_test`, E2-07a `paste_test`, E2-07b `selection_menu_test`·`recolor_test`, E2-07c `selection_extensions_test`, E2-08 `object_handles_test`·`vertex_edit_test`, E2-09 `shape_tool_test`·`shape_style_test`, E2-10 `text_box_test`, E2-12 `image_insert_test`·`add_page_sheet_test`, E2-19 `erase_v2_test`). 10 #5의 통합 몫은 수정 2회차에 E2-21(P-A)·E2-21b(P-B)로 나눠 두었고, 남은 묶임은 이번 항목 2의 V5·V6 자동 도형 단계뿐이다.
- 다른 파일은 고치지 않았다. V5 문장(00-overview 7.7.2, 01-infra 9.1 V5 2단계)은 그대로 두고 12.2 Q16의 질문·기본 진행을 넓혀 총괄에게 넘겼다.

| # | 근거 | 무엇을 어떻게 바꿨나 | 위치 |
|---|---|---|---|
| 1 | 총괄 검토 — 새 모순(수정 2회차 항목 2와 같은 종류: 10 #4가 P-B에 묶임) | 5.1.2 '명령 매핑 전체' 표의 '자동 도형 보정 확정' 행(`InkEdit(addShape).toCommand()` = `AddObjects`)은 `test/helpers/mapping_table.dart`에 그대로 들어가고 `unit/mapping_coverage_test.dart`가 모든 행이 덮였는지 확인하는데(9.3), 이 행을 덮는 시험이 P-B E2-15의 `widget/shape_assist_test.dart`뿐이어서 8.2 자르기 순서대로 E2-15를 미루면 커버리지 시험이 실패해 10 #4(2차 완료 조건)를 판정할 수 없었다. 두 안 중 **P-A 시험으로 옮기는 쪽**을 택했다 — 이 단언은 1차 `commitInkEdit`(`commands/editor_commands.dart` 88 — `edit.isEmpty`·`toCommand()`만 보고 종류를 가리지 않음 [확인])와 R2-B3의 `InkEditKind.addShape`(`InkEdit` v2·`toCommand` 최종 — 5.2.4)만 있으면 되므로 P-B 작업에 기댈 이유가 없고, 'P-B 행은 커버리지 대상에서 뺀다'는 안은 미룬 사실을 사람이 표에 적어야 해 판정이 사람 손에 남기 때문이다. E2-09 `widget/shape_tool_test.dart`에 '`ink_edit_builders`의 `InkEdit(addShape)`를 마운트된 페이지 컨트롤러로 `commitInkEdit` → `AddObjects` 1단계·획 없음·`content.objects`에 `ShapeObject` 1개'를 더하고, E2-15 `shape_assist_test`에서는 그 단언을 빼 'E2-09로 옮김'을 적었다(E2-15 작업 내용의 '`addShape` 커밋'도 '1차 경로 그대로 — 새 코드 없음, 커밋 단언은 E2-09'로). 규칙으로 `mapping_table.dart`가 행마다 덮는 시험 파일을 함께 적고 그 시험은 모두 P-A 작업 몫이라고 5.1.2 표 머리·9.3·10 #4에 적었다. 같은 인용이 있는 1.2 M5-6 행·2.1 F-11 행·3절 트리(`mapping_table.dart`)·5.2.4 표·6.10·8.2 자르기 문단도 맞췄다 | 1.2 M5-6, 2.1 F-11, 3, 5.1.2(표 머리·자동 도형 행), 5.2.4, 6.10, E2-09, E2-15, 8.2 자르기, 9.3, 10 #4 |
| 2 | 총괄 검토 — 새 모순(10 #5·E2-23이 V5를 거쳐 EDITOR 자신의 P-B E2-15에 묶임) | 00-overview 7.7.2 V5와 01-infra 9.1 V5 2단계의 '합성 멈춤으로 자동 도형'은 조건 없이 들어 있고, 이 단계는 INK T39와 EDITOR E2-15(`shapeAssistFor`가 `holdToSnap`을 넘김 — E2-15가 없으면 `PenInteraction`이 `off`를 넘겨 INK가 멈춤을 보지 않음)가 둘 다 있어야 통과한다. 수정 2회차의 Q16 기본 진행은 'V5 실패가 **T39 미병합** 때문이면 EDITOR 원인 아님'만 적어, E2-15를 미루면 V5 실패가 EDITOR 원인이 되어 10 #5를 채울 수 없었고 E2-23 완료 조건 'INFRA `app_smoke_v2_test.dart` 통과'도 T39가 미뤄지면 글자 그대로는 통과할 수 없었다. **E2-23 완료 조건**에 'V5(같은 스모크를 Chrome에서 도는 V6 포함)의 자동 도형 단계가 P-B 미병합 — INK T39 **또는** EDITOR E2-15 중 하나라도 빠짐 — 으로 실패하면 EDITOR 원인 실패로 세지 않고 진행 기록 2차 절에 미룸(빠진 작업)으로 남기며 2차 완료 판정을 막지 않는다'를 적고, 미병합 여부는 INK·EDITOR 진행 기록으로 가리며, 둘 다 병합됐는데 실패하면 보통 실패로 다룬다고 적었다. 그 단계가 실패하면 한 시험 안의 뒤 단계(90° 돌리기·색·잘라내기·붙여넣기·녹음 등)가 돌지 않아 'EDITOR 원인 실패 0'을 볼 수 없으므로, 뒤 단계의 EDITOR 경로는 같은 순서를 P-A 기능만으로 거치는 E2-21(`objects_smoke_test`·`recording_link_smoke_test`·`web/editor_browser_smoke_v2_test`)의 통과로 판정하고 같은 진행 기록 줄에 적는다고 더했다. **10 #5**에 같은 규칙과 'T39·E2-15가 둘 다 병합됐으면 그 단계에서도 EDITOR 원인 실패가 없어야 한다'를, **12.2 Q16**의 질문에 'V5 단계는 E2-15도 있어야 함(LIBRARY 시험은 T39만)'을, 기본 진행에 같은 규칙을 적었다(12.2 머리에 '수정 3회차에 넓힘'). 8.2 자르기 문단에도 한 줄 더했다. V5 문장 자체는 고치지 않는다 — 총괄이 Q16에 답할 몫이다 | E2-23(8.3), 8.2 자르기, 10 #5, 12.2 머리·Q16 |


### 13.4 총괄 직접 수정 (2026-11-05, 최종 승인 — 계약 v2.2)

승인 확인에서 남은 2건은 완료 조건을 글자 그대로 채울 수 없게 하는 모순이라(중대) 총괄이 이 계획서를 직접 고쳤다. 같은 자리에 걸린 12.2 Q15·Q16에 총괄 답을 적었고, Q16 답은 계약 v2.2 C22-07(00-overview 7.7.2 'P-B에 기대는 기준'·V5b)이다. 계약 블록·5.1.2 원문 매핑 표·12.1은 건드리지 않았다.

| # | 남은 항목 | 무엇을 어떻게 바꿨나 | 위치 |
|---|---|---|---|
| 1 | E2-21 `objects_smoke_test`의 순서 '… 붙여넣기 → 닫고 다시 열기 → 유지 → 되돌리기 사슬로 처음 상태'가 1차 v1.5 C15-04·계약 V5 문장·01-infra 9.1 V5 5단계와 맞지 않음(다시 연 세션은 되돌리기가 없음 — 실제 CORE에서 다시 연 뒤 `undoDepth == 0`, 1차 `real_core_ink_smoke_test.dart` 276행) | 순서를 '… 붙여넣기 → 되돌리기 사슬 끝까지(처음 상태) → 다시 실행으로 원래 상태 → 닫고 다시 열기 → 모두 유지·`content.objects` 종류·개수·다시 연 세션 `undoDepth == 0`(C15-04)'로 바꿨다. E2-21b는 이미 C15-04 순서라 그대로 | E2-21(8.3) |
| 2 | E2-23·10 #5·12.2 Q16 기본 진행의 '뒤 단계의 EDITOR 경로는 같은 순서를 P-A 기능만으로 거치는 E2-21로 판정'이 부정확(① 항목 1의 순서 차이 ② E2-21은 V5 6단계 `editor.panelSlot`, 8단계 `editor.ext.recog.*`, 9단계 `initialFocusRectPt`·`editor.focusFlash`를 거치지 않음) | Q16 총괄 답으로 V5 본 흐름에서 자동 도형 단계가 빠져(V5b — P-B, INK T39·EDITOR E2-15·LIBRARY L2-06이 모두 병합됐을 때만) '뒤 단계가 돌지 않을 때의 대체 판정'이 필요 없어졌으므로 그 문장을 지웠다. 대신 E2-23에 V5·V6 단계가 실패할 때 원인을 좁히는 EDITOR 시험을 **단계별로** 적었다: 2~5단계 = E2-21 `objects_smoke_test`(항목 1 순서), 6~7단계 = E2-21 `recording_link_smoke_test` + E2-16 `widget/recording_panel_slot_test.dart`, 8단계 = E2-07c `widget/selection_extensions_test.dart`·E2-12 `widget/insert_menu_test.dart`, 9단계 = E2-19 `widget/initial_focus_test.dart`, V6만 실패 = `web/editor_browser_smoke_v2_test.dart`, V5b = E2-21b·E2-15 `shape_assist_test`. 실패가 있으면 진행 기록 '2차' 절 E2-23 줄에 실패 단계·대응 시험·원인을 적는다. 10 #5는 'V5b는 #1 규칙(P-B)'으로, 12.2 Q16 기본 진행의 같은 문장은 '지움 — E2-23 단계별 대응'으로 고쳤다 | E2-23(8.3), 10 #5, 12.2 머리·Q16 |
| 3 | 12.2 Q15(내부 device 키 2개) 답 대기 | 총괄 답: 올리지 않는다(1차 `editor.toolSelection`·`editor.viewport`와 같은 내부 키 취급) | 12.2 Q15 |

### 13.5 동시 개발 착수 정리 (2026-11-06 — 계약 v2.3, C22-09)

| # | 항목 | 처리 | 위치 |
|---|---|---|---|
| 1 | 상태 줄 | '승인 · 계약 v2.3' | 머리 |
| 2 | C22-08 바탕 HEAD | `18c5ae5` 인용을 `b6c9d0a`로 읽는다고 적음(EDITOR 코드 차이 없음) | 머리 '이어받는 문서' |
| 3 | C22-04 R-3 | 이미 v2.2 문장(총괄 최종 승인 때 맞춤) — 바꿀 것 없음 | 5.1.3 R-3 |
| 4 | C22-07 E2-23·10 #5 | 이미 총괄 직접 수정(13.4) — 바꿀 것 없음 | 8.3, 10 |
| 5 | C23-05 함수 값 비교·`withAction` 문구 | `recordingPanel`·항목 함수 필드 = Dart 함수 `==`. `withAction`·`fromJson` 행을 R2-B5 코드에 맞춤 | 4.3.1, 4.3.2 |
| 6 | C23-07 시험 도우미 | `FakeInkShapeFitter.result`·`InkMathRenderer.layout` 바인딩 주의를 5.5에 적음 | 5.5 |
| 7 | 5.5 '가정' | 없음 — 기반 단계 실제 타입으로 확인 | 5.5 |
| 8 | 00-review '최종 승인' EDITOR-F1~F4 | F1(E2-21 C15-04 순서)·F2(E2-23 기록)는 통합 단계 몫으로 진행 기록 작업 표에, F3(E2-15를 미루면 `E2-15 미룸`)은 진행 기록 '동시 개발' 메모에, F4(E2-01 첫 작업 — Hosting 없음 → Chrome 시험과 통합 Playwright 스모크)는 작업 순서에 반영 | 진행 기록 '## 2차 / 동시 개발' |

---

## 14. 수식 펜 1단계 (2026-11-13, 계약 v2.8 C28-04)

`EditorTool.math`('수식 펜' — `EditorExtensions.mathPen`이 있을 때만 툴바·'도구 더보기'에 보임, 없으면 저장값 `"math"`는 펜처럼 동작). 획은 볼펜 스타일의 보통 획(한 단계씩, 저장됨), 묶음 소속은 편집기 메모리(`tools/math_pen/math_pen_controller.dart`)에만. 묶음 판정 `mathPenJoins`(가장 가까운 소속 획까지 gapX ≤ 1.5 H, gapY ≤ 0.6 H, H = 점 획을 뺀 높이 중앙값 8~72 pt, 400획·40 000점), 변환 계기(말풍선 탭·도구 전환(지우개 제외)·먼 곳에 새 묶음), 노트를 떠나면 변환하지 않음, 수식 근처 획 = 다시 열기 한 명령(`EditorCommands.commitInkEditWith`), 수식 탭 메뉴 [고치기][손글씨로 열기](손가락 탭·마우스 클릭 — 스타일러스 점은 쓴다), 말풍선 층 `ui/overlays/math_pen_layer.dart`(Listener 바깥 형제, 손바닥 탭 무시 `InputRouter.rejectsAsPalm`, 화면 밖이면 숨김). (1단계 검토 반영) 배경 변환은 노트 기록이 계기 때와 같을 때만(`stillWanted`), 새 묶음의 옛 묶음 변환은 새 획보다 먼저, 되돌린 변환은 그 되돌리기에서 한 번만 수식 펜·지우개일 때 다시 열린다. 설계·결정·이번에 하지 않은 것: [research/math-pen-phase1.md](research/math-pen-phase1.md). 부록 C 키(계약 아님): `editor.toolbar.math`, `editor.mathPen.bubble`, `editor.mathPen.formulaMenu`, `editor.mathPen.fix`, `editor.mathPen.reopen`.

## 15. 텍스트 펜 1단계 (2026-11-13, 계약 v2.9 C29-01)

`EditorTool.textPen`('텍스트 펜', 아이콘 `edit_note` — `EditorExtensions.textPen`이 있을 때만 툴바·'도구 더보기'의 '수식 펜' 옆에 보임, 없으면 저장값 `"textPen"`은 펜처럼). 획은 볼펜 스타일의 보통 획(한 단계씩, 저장됨)이고 묶음 소속은 편집기 메모리(`tools/text_pen/text_pen_controller.dart`)에만 있다. 묶음 판정 `textPenJoins`(`tools/text_pen/text_pen_group.dart`): 같은 줄은 가장 가까운 소속 획까지 gapX ≤ 2.5 H(낱말 사이 띄어쓰기)·gapY ≤ 0.6 H, 다음 줄은 묶음 아래 ≤ 1.2 H이고 옆으로 겹칠 때, 20줄·400획·40 000점까지(H는 수식 펜과 같은 규칙). 펜을 뗀 뒤 약 500 ms에 말풍선이 인식한 글을 보여 주고, **말풍선을 탭할 때만** 텍스트 상자로 바꾼다(한 단계, `recog-text-pen`). 수식 펜과 달리 도구 전환·먼 곳의 새 묶음·노트 떠나기에서는 배경 변환을 하지 않는다 — 잘못 읽은 글이 손글씨를 몰래 바꾸면 안 되기 때문이다(도구를 바꾸면 묶음은 손글씨로 남은 채 닫힘, 지우개는 묶음을 유지). 말풍선 길게 누르기나 '고치기'는 기존 변환 창(줄마다 고치기·후보)을 연다. 변환을 되돌리면 같은 획이 그대로 돌아오고, 텍스트 펜·지우개일 때 한 번 다시 열린 묶음이 된다. 묶음 동기화(되돌리기·원격·지우개 조각)는 수식 펜과 공유하는 `tools/pen_group/pen_group_members.dart`, 말풍선 틀(자리·손바닥 무시)은 `PenBubbleLayout`·`PenBubbleTap`(`math_pen_layer.dart`)을 같이 쓴다 — 수식 펜 동작은 그대로. 바꾸기 전 손글씨는 보통 잉크라 '검색용 자동 인식'이 켜져 있으면 다른 손글씨처럼 색인된다.

찾기 쉽게: [+] 메뉴 첫 줄(이미지 다음) '손글씨를 텍스트로' — 손글씨를 선택해 두었으면 그 손글씨의 변환 창, 아니면 텍스트 펜을 고른다. 선택 막대에서는 `EditorSelectionMenuItem.pinned` 항목(recog '텍스트로 변환')이 폭과 상관없이 언제나 ⋯ 앞에 있다(나머지가 남은 자리를 채움). 키보드 텍스트 도구는 그대로. 부록 C 키(계약 아님): `editor.toolbar.textPen`, `editor.textPen.bubble`, `editor.insert.handwritingToText`.

## 부록 A. 확장 지점 · 자리 사용표 (개요 6장 13절)

EDITOR가 **여는 자리**(다른 영역이 채움)

| 자리 | 종류 | 채우는 영역 · id (INFRA 연결) | 비었을 때 (E-7) | EDITOR 시험 가짜 |
|---|---|---|---|---|
| `EditorExtensions.selectionMenuItems` | 선택 메뉴 항목 | recog: `recog.toText`·`recog.copyText`·`recog.toMath`·`recog.editMath` | 막대에 확장 항목 없음 | `RecordingSelectionItem` |
| `EditorExtensions.insertMenuItems` | 삽입 메뉴 항목 | recog: `recog.mathPad` | 삽입 메뉴에서 빠짐(이미지도 없으면 `[+]` 숨김) | `RecordingInsertItem` |
| `EditorExtensions.recordingPanel` | 하단 패널 빌더 | media: `RecordingPanel` | 마이크 단추 숨김 | `_TestPanel` |
| `EditorExtensions.moreMenuItems`·`addPageSources` | (1차) | PDF | (1차) | (1차) |
| `editorImageImporterProvider` | 이미지 가져오기 | media: `supportedImageSources()` + `importImageForNote` | 이미지 메뉴·시트 줄·이미지 붙여넣기 숨김 | `FakeImageImporter` |
| `stylusExtrasProvider` | Pencil 이벤트 | INFRA: `PencilStylusExtrasSource`(iOS 네이티브만) | `NoStylusExtras` — Pencil 설정 줄 숨김, 구독 없음 | `FakeStylusExtras` |
| `devOverlaySectionsProvider` | (1차) 개발자 표시 섹션 | PDF·media·recog(7.3.3) | (1차) | (1차) |
| `EditorScreen.initialFocusRectPt` | 생성자 인자 | INFRA 라우트 `?page=&focus=` | 강조 없음 | 직접 인자 |

- (v2.1, C21-14) 선택·삽입 메뉴 항목과 `EditorImageImporter.pick`은 누름 처리(`onPressed`) 안에서 **동기적으로** 시작하고 메뉴·시트는 그 뒤에 닫는다. 넘기는 `context`는 에디터 본문의 것이다(4.3.1). `isVisible`의 예외는 숨김 + 보고만(E-7 v2.1).

EDITOR가 **채우는 자리**(다른 영역이 연 것)

| 자리 (정의) | EDITOR가 하는 일 |
|---|---|
| CORE `audioRecorderServiceProvider`·`audioPlaybackServiceProvider` | 읽기만(override 안 함). 기본 '지원 안 함'이면 메타 없음·강조 없음 |
| INK `inkShapeFitterProvider` | 읽기만(`NoShapeFitter`면 자동 도형 토글 숨김) |
| INK `pageBackgroundBuildersProvider` | 1차처럼 썸네일·미리보기에 그대로 넘김(이미지 배경은 INK 기본 목록) |

## 부록 B. 네이티브 · 권한 요구표 (개요 6장 14절)

EDITOR는 플러그인을 쓰지 않으므로 **네이티브 요구가 없다**(R16 — 피처 패키지). iOS 배포 대상·Info.plist 키·안드로이드 권한·서비스 선언·minSdk/compileSdk 모두 해당 없음. 이미지 선택(`NSPhotoLibraryUsageDescription`·`NSCameraUsageDescription`)·마이크·Pencil 플러그인 요구는 각각 PDF(media)·INFRA(`pencil_bridge`) 계획서 14절에 있다. 웹 대체안 B(P-C)는 SDK `dart:js_interop`만 쓰므로 웹 정적 자산·CSP 요구도 없다(글꼴 `@font-face`는 INK 글꼴 에셋 URL을 그대로 쓴다 — 하게 되면 INK와 경로를 맞춘다).

## 부록 C. 통합 시험용 위젯 키 (INFRA V5·V6)

계약은 아니지만 INFRA 앱 스모크가 쓴다. 바꿀 때 진행 기록과 INFRA에 알린다. 1차 키(`editor.toolbar.pen` 등)는 그대로다.

| 키 (`ValueKey<String>`) | 위젯 |
|---|---|
| `editor.toolbar.shape` · `editor.toolbar.text` · `editor.toolbar.insert` · `editor.toolbar.mic` · `editor.toolbar.overflowTools` | 툴바 새 단추 |
| `editor.insert.image.photos` · `.camera` · `.files` · `.clipboard` | 삽입 메뉴 이미지 출처 |
| `editor.ext.<id>` | 확장 항목(선택·삽입 메뉴 — 예 `editor.ext.recog.toText`) |
| `editor.selectionMenu.cut` · `.copy`(1차) · `.delete`(1차) · `.color` · `.more` · `.duplicate` · `.rotate90` · `.style` · `.vertices` · `.editText` · `.format` · `.clear`(1차) | 선택 메뉴 |
| `editor.recolor.swatch.<argb16진>` | 색 팝업 칸 |
| `editor.selection.rotateHandle` | 회전 핸들(적중 영역) |
| `editor.shapePopup.kind.<ShapeKind.name>` | 도형 종류 칸 |
| `editor.textEditor` · `editor.textFormatBar` · `editor.textSheet.done` · `editor.textSheet.panel` | 텍스트 편집기(`TextField`)·서식 바·시트 완료·시트 방식 위쪽 패널 |
| `editor.newTextBoxOutline` | 빈 곳 끌기 새 상자 테두리(EDITOR overlay) |
| `editor.dev.textBoxProbe` · `editor.dev.shapeSamples.toggle` · `editor.dev.shapeSamples.copy` · `editor.dev.shapeSamples.kind.<ShapeKind.name 또는 none>` | 개발자 메뉴: 텍스트 상자 시험·도형 표본 토글·복사·기대 종류 |
| `editor.textDraft.restore` · `editor.textDraft.discard` | (P-B) 저장되지 않은 글 배너 |
| `editor.panelSlot` | 하단 패널 자리 |
| `editor.focusFlash` | 위치 강조 |
| `editor.pen.type.<PenTool.name>` | 펜 종류 칸(1차 규칙 그대로 — 10종) |
| `editor.addPage.image.<source>` | 페이지 추가 시트 이미지 출처 |
| `editor.settings.gesture.<EditorGesture.name>` | 설정 제스처 줄 |
