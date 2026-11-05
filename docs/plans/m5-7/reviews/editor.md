# EDITOR 2차 계획서 검토 — `04-editor.md`

> 검토자: 총괄 대리 검토자 · 검토일 2026-11-05
> 대상: [04-editor.md](../04-editor.md)(2,536줄, 초안) — 에디터 화면(EDITOR), 소유 경로 `packages/feature_editor/`
> 기준: 개요 [00-overview.md](../00-overview.md) 7장 통합 계약 v2.0 초안, 조사 01~04, PLAN.md(F-03·F-09~F-16, 5장, 8장, 10장 M5·M6·M7), 1차 EDITOR 작업 트리 `/home/user/wt/editor`(`93dc827`, `lib/`는 `/home/user/noteapp` HEAD와 같음 — `diff -rq` 확인), 1차 INK 작업 트리 `/home/user/wt/ink`, 1차 CORE 작업 트리 `/home/user/wt/core`, 다른 영역 계획서 01·02·03·05·06·07(맞닿은 절만)
> 확인 방법: 계획서 전 절을 읽고, 4.2·5.1.1~5.1.5·5.2.1의 '계약 원문' 블록을 개요 7장과 기계적으로 대조했다(파이썬 diff — 7.2.10·7.2.2·7.2.3은 글자까지 같음, 7.2.4·7.2.9는 '생략' 표시한 블록만 빠짐). 1차 코드·Flutter SDK 소스·다른 계획서는 grep으로 확인했다. 시험은 돌리지 않았다.

---

## 총평

계약 7.2.10을 글자 그대로 옮기고(대조 결과 차이 0), 계약이 EDITOR에 맡긴 세부(4.3)와 계약 밖 EDITOR 추가 행(5.1.2)을 깔끔하게 나눈 계획서다. 좋은 점:

- 1차 코드 근거가 대부분 맞다. 내가 다시 본 것 — `EditorTool { pen, eraser, lasso } // M5: …`(`tool_state.dart` 8), `selectionFromJson`이 모르는 도구를 `invalid`에 넣음(`tool_controller.dart` 393–420), `_endTouch`의 bool 분기(`input_router.dart` 518–521), 길게 누르기 `policy.gestures.longPressMenu`(311), `PenInteraction.start`가 `meta` 없이 `beginStroke`(`pen_interaction.dart` 58–62), 1차 `GestureSettings` JSON 키 `twoFingerUndo`·`threeFingerRedo`·`longPressMenu`, `EditorSettingKeys` device 4·synced 4(→ 2차 6), `SettingKey.integer` 존재(`settings_repository.dart`), `ImageBackground(assetId, fit, paperColorArgb)`, `InsertPages({drafts, position})`, INK `SelectionHandle` 8방향·`snapAngle`(π/12, 3°), 새 공개 이름 16개 — 모두 맞다.
- E-4 웹 접촉 판정을 조사 02 8.4의 CDP 실측 순서 그대로 상태표로 옮겼고, '접촉 중 버튼만 남고 펜이 떨어짐'까지 다뤘다(CP-E4). iPad Safari의 Pencil은 버튼이 없고 프레임워크가 `buttons == 0`이면 0x01을 채우므로(`converter.dart` `_synthesiseDownButtons`) 주 기기에서 이 규칙이 잘못 걸릴 경로가 없다는 점도 확인했다.
- 웹 IME 위험(개요 위험 #4)에 첫 작업(E2-01)·대체안 두 가지(A 시트 P-A, B `<textarea>` P-C)·개발자 메뉴 전환·실기기 B-2 결정 흐름을 미리 깔아 두었고, V1·V2 시제품으로 근거를 남겼다(`/tmp/claude-0/plan57-scratch/editor57/probe` 확인).
- 명령 매핑(5.1.2), 자리 예외 처리(E-7을 `extension_runner.dart` 한 곳에), 녹음 R-1 동기 읽기(스트림 값을 쓰지 않는 이유까지), 계약 보장 ↔ 시험(9.3)과 매핑 덮임 시험(`mapping_coverage_test`)이 촘촘하다.

그러나 **그대로 승인할 수 없다(revise)**. ① 위젯 시험 다수가 '실제 INK 컨트롤러에 무엇을 넣었는가'를 단언하는데, INK `InkPageController`·`StrokeSession`은 `final class`이고 계약에 읽는 getter가 없어 **그 시험들을 쓸 수 없다**(동시 개발 중 가짜 부재). ② 텍스트 세션을 `TapRegion.onTapOutside`(포인터 **down**)로 끝내 **스크롤·핀치·손바닥 접촉에도 세션이 끝난다**. ③ 탭 재생 가로채기가 녹음 정지 뒤에도 켜져 있어 **사용자가 쓴 짧은 획을 조용히 버린다**(필기 손실). ④ 선택 우선 규칙과 '도형 그린 뒤 선택'이 부딪혀 **방금 그린 도형 안에서 다음 도형을 그릴 수 없다**. 그 밖에 1차 `_run`의 거절 경로와 6.21 표의 차이, 회전된 단일 객체 크기 조절, 작업 분해(E2-07 크기·E2-16 선행 사슬), 웹 사용자 동작 활성화, 도형 표본 수집 경로를 고쳐야 한다.

---

## 반드시 고칠 것

### M-1. INK에 넣은 값을 관찰할 길이 없어 위젯 시험 다수를 쓸 수 없다 (동시 개발 중 가짜 부재)

- **위치**: 5.2.4 표(1283–1291행 — '호출 인자·횟수 단언', '가짜 세션'), 5.5 INK 행, 8.2 완료 조건 — E2-01 `text_input_sheet_test`('입력 중 `setPreviewObjects` 호출'), E2-08 `object_handles_test`('끌기 중 `setPreviewObjects`에 같은 id, 끝에 빈 목록'), E2-09 `shape_tool_test`('끌기 → 미리보기'), E2-10 `text_box_test`('숨김 id `{id}` → 끝 → `{}`'), E2-14 `laser_test`('가짜 세션 `end() == null`'), E2-15 `shape_assist_test`('가짜 `beginStroke` 기록으로 … `holdToSnap`/`off` 표'), E2-17 `playback_highlight_test`('다음 프레임 모든 마운트 컨트롤러 초점 위치'), E2-21 `recording_link_smoke_test`('실제 INK 초점이 바뀜').
- **문제**:
  - 1차 INK `final class InkPageController`(`/home/user/wt/ink/packages/ink_engine/lib/src/render/ink_page_controller.dart` 128행), `final class StrokeSession`(`sessions.dart` 195행)이다. 라이브러리 밖에서 `implements`·`extends`할 수 없어 '기록하는 가짜 컨트롤러·가짜 세션'을 만들 수 없다. 1차 `PenInteraction.start`는 `controller.beginStroke`를 직접 부르므로(이음새 없음) `beginStroke` 인자를 가로챌 곳도 없다.
  - 계약 7.2.9의 새 멤버는 `setPreviewObjects`·`setHiddenObjectIds`·`setPlaybackFocus`(쓰기만)이고, 읽는 getter(`previewObjects`·`hiddenObjectIds`·`playbackFocus`)도, `StrokeSession`의 `shapeAssist` getter도 없다. INK `testing.dart` v2(03-ink 4.12)에도 기록 컨트롤러가 없다. 03-ink 5.6은 'EDITOR 시험은 **실제 INK**(INK 가짜 없음)'이라고 못 박았다.
  - 1차 EDITOR 시험은 공개 getter(`controller.pendingIds`·`controller.selection`)로만 INK 상태를 봤다. 2차에서 그런 getter가 있는 것은 `isTapeRevealed`뿐이다.
  - 그래서 위 완료 조건들은 지금 표면으로는 **작성할 수 없다**. R2-B3는 `setPlaybackFocus`를 '상태만 저장(그리기 없음)'으로 두므로 픽셀로도 볼 수 없다.
- **고칠 방향**(둘 다 하는 것을 권한다):
  1. INK에 읽기 전용 getter를 '추가'로 요청한다 — `List<core.PageObject> get previewObjects`, `Set<String> get hiddenObjectIds`, `InkPlaybackFocus? get playbackFocus`, `ShapeAssist get shapeAssist`(StrokeSession). 계약 7.2.9 추가(C-1)이고 R2-B3에 함께 넣어야 EDITOR 동시 개발 첫날부터 쓸 수 있다(X-1).
  2. EDITOR 결정은 EDITOR 이음새로 단언한다 — `RecordingLink.metaFor`처럼 `shapeAssistFor(settings, penType, fitter)`를 순수 함수로, `PlaybackHighlightDriver`에 `void Function(InkPlaybackFocus?)` 출력 주입, 텍스트 숨김은 `TextEditState`(EDITOR 상태)로.
  3. 레이저는 가짜 세션 대신 실제 R2-B3로 시험한다 — 03-ink 4.13 표가 R2-B3에서 이미 `end() → null`(K-9, C2-37)이라고 적었다(S-4와 함께 5.2.4 표를 고친다).

### M-2. 텍스트 세션을 `TapRegion.onTapOutside`로 끝내면 스크롤·핀치·손바닥에도 세션이 끝난다

- **위치**: 6.11.5 '끝나는 때: 바깥 탭(`TapRegion.onTapOutside` — 캔버스의 펜·손가락 down도 여기 해당)'(1981행), 6.3.6 3(1534행), 6.11.3 '카메라가 움직이면 오버레이가 따라간다'·'키보드에 가리면 `revealPageRect`로 스크롤'(1964–1965행), 머리말 V1.
- **문제**: Flutter 3.47.9 `TapRegion.onTapOutside`의 형은 `void Function(PointerDownEvent)`이고 `TapRegionSurface`가 **포인터 down마다** 부른다(`/opt/flutter/packages/flutter/lib/src/widgets/tap_region.dart` 45행 typedef, 375–377행). 그래서
  - 편집 중 캔버스를 두 손가락으로 끌거나 핀치하는 첫 손가락 down, 펜 전용 모드의 한 손가락 끌기 스크롤, 팜 리젝션으로 **거부된 손바닥 down**, 웹의 공중 `down(0x02)`(6.3.2 — 아직 닿지 않음)까지 모두 '바깥 탭'이 되어 세션이 끝나고 키보드가 내려간다.
  - 6.11.3이 약속한 '스크롤해도 오버레이가 따라감'과 모순되고, 세션마다 명령 1회(E-6)라 스크롤할 때마다 되돌리기 단계가 쪼개진다.
  - V1은 '탭 한 번'만 확인했다. 내비게이션은 확인하지 않았다.
- **고칠 방향**: 캔버스 안에서 세션을 끝낼지는 **라우터가 정한다** — 펜 접촉(6.3.6 3), 손가락 한 번 탭(`tapGesture(1)` — 탭 판정 뒤), 길게 누르기 메뉴만 끝낸다. 내비게이션과 거부된 접촉은 끝내지 않는다. 페이지 뷰포트를 편집기·서식 바와 같은 `TapRegion` 묶음(`groupId: TextEditGroup`)에 넣어 `onTapOutside`가 캔버스 밖(툴바·패널·시트)에서만 오게 한다(또는 `onTapUpOutside` + 라우터 판정). `FocusNode`를 잃음(iPad 키보드 '내림' 단추, 시스템 포커스 이동)도 끝 사유에 넣는다(지금 `TextEditEndReason`에 없음). 시험 추가: `text_box_test`에 '편집 중 두 손가락 끌기·핀치 → 세션 유지·명령 0·오버레이 위치 갱신', '거부된 손바닥 down → 유지', '펜 전용 한 손가락 끌기 → 유지'.

### M-3. 탭 재생 가로채기가 녹음 정지 뒤에도 켜져 있어 사용자가 쓴 짧은 획을 버린다

- **위치**: 6.3.5 '펜 탭' 정의·표 ③·끝 문단(1503–1517행), 6.15.3, 6.3.7 표, 12.2 Q3, 11 리스크 7, E2-04·E2-17 완료 조건.
- **문제**:
  - 펜 탭 = 이동 ≤ `tapMaxMovement`·시간 ≤ `singleTapMaxDuration`인데, 1차 값은 **20 px·250 ms**다(`input/input_thresholds.dart` 10–11행). 마침표·쉼표뿐 아니라 짧은 'ㅡ'·체크 표시 조각·짧은 밑줄도 '탭'이 된다.
  - '탭 재생 상태' = `tapToSeek`(기본 켬, 7.4.4) + 재생기에 이 노트 녹음이 열려 있고 phase가 `idle`·`failed`가 아님(6.3.5 끝). 그런데 media 패널은 **열 때 가장 최근 녹음을 `open`**하고, **녹음을 정지하면 그 녹음을 재생기에 연다**(06-pdf 6.13.3 2080·2082행 — 재생은 안 함, phase `ready`).
  - 결과: 강의 녹음을 정지한 뒤 같은 노트에 이어 쓰거나 고쳐 쓰는 동안, 녹음 중 쓴 획 위(허용 12 px — I-11)에 찍은 짧은 획은 `session.cancel()`로 **저장되지 않고** 재생이 시작된다. 사용자는 획이 사라진 것을 알아채기 어렵다(필기 손실). 펜 전용 모드의 손가락 한 번 탭도 ⑥ '선택 해제' 대신 재생이 된다. CP-PDF-10(녹음 중 `play()` 무시)과 겹치면 녹음 중에는 소리 없이 획만 사라진다.
  - '커밋 전에 `interceptTap`'(1515행)이 `end()` 전인지 뒤인지도 정해지지 않았다. `end()` 뒤면 획은 이미 대기 표시라 `cancel()`이 아니라 `discardEdit(edit)`이 필요하다.
- **고칠 방향**:
  1. '탭 재생 상태'를 좁힌다 — 하단 패널이 열려 있음(`editorPanelProvider`) **또는** phase가 `playing`·`paused`일 때만. `ready`(열어만 둔 상태)와 녹음기 `isActive`일 때는 가로채지 않는다.
  2. 펜 탭 가로채기 문턱을 손가락 탭과 따로 둔다(예: 이동 ≤ 4 px·≤ 200 ms — '점'만). 테이프 ②도 같은 문턱을 쓴다.
  3. 판정은 `_session.end()` **전에** 하고 가로채면 `cancel()`이라고 6.3.5에 적는다.
  4. 시험 추가(E2-17): '녹음 정지 직후·패널 닫힘 → 녹음된 획 위 15 px 획 → 커밋됨', '패널 열림 + `ready` → 점 탭 → `seekMs`', '녹음 중 → 가로채지 않음'. Q3 문구도 이 조건으로 바꾼다(X-4).

### M-4. 선택 우선 규칙과 '그린 뒤 선택'이 부딪혀 방금 그린 도형 안에서 다음 도형을 그릴 수 없다

- **위치**: 6.6.2(1688–1691행), 6.6.3 표 '도형 그리기 끝 | 새 도형 | 그대로(다음 끌기로 다음 도형)'(1702행)·'이미지 삽입 | 새 이미지'(1703행), 6.9.2 3(1884행), 6.12.2 4(2023행), E2-09 완료 조건('새 도형 선택·도구 그대로'), 11 리스크 3, 12.2 Q8.
- **문제**: 도형을 그리면 새 도형이 선택되고, 선택이 있으면 프레임 + 8 px(`bodyInflate`) 안의 down은 **도구와 무관하게** 이동이 된다(이동 문턱 4 px). 그래서
  - 사각형을 그린 뒤 그 안(또는 8 px 안)에서 원을 끌면 원이 아니라 사각형이 움직인다 — 표 그리기·도형 안 도형·겹친 도형처럼 흔한 흐름이 '빈 곳 탭으로 해제 → 다시 끌기'가 된다. 6.6.3의 '다음 끌기로 다음 도형'은 다음 끌기가 이전 도형 **밖**에서 시작할 때만 맞다.
  - 이미지를 넣은 직후(선택됨) 펜으로 이미지 위에 쓰면 첫 획이 이미지를 옮긴다(되돌리기 1단계가 생김). 수식 패드 삽입 뒤(`selectObject`)도 같다.
  - `shape_tool_test`는 '새 도형 선택'만 단언하므로 시험은 통과하고 실제 흐름이 깨진다. 리스크 3의 대응('선택은 올가미·탭·삽입·붙여넣기로만 생김')은 바로 그 삽입·도형 그리기 경로를 놓쳤다.
- **고칠 방향**(하나를 골라 6.6.2·6.6.3·Q8에 적는다):
  - (a) 그리기 도구(펜·도형·텍스트)에서는 선택 우선을 **핸들**(모서리·변·회전·꼭짓점)에만 적용하고, 본체 끌기 이동은 올가미 도구·임시 올가미로 만든 선택에서만 한다. 또는
  - (b) 도형 도구로 그린 도형은 선택하지 않는다(자동 보정처럼 — 6.10). 고치려면 탭으로 고른다.
  - 어느 쪽이든 시험을 더한다: E2-09 '방금 그린 사각형 안에서 끌기 → `AddObjects` 1회(새 도형)·이전 도형 그대로', E2-12 '이미지 삽입 직후 이미지 위 펜 끌기 → (정한 동작)', E2-06 '펜 도구 + 붙여넣은 선택 본체 끌기 → (정한 동작)'.

---

## 권장 (고치면 좋은 것)

### S-1. 1차 `_run` 거절 경로가 6.21 표와 다르다 — 거절 이유를 알 수 없다

- **위치**: 6.6.5 끝 문단(1748행), 6.6.7(1763행), 6.11.2 끝(1956행), 6.11.5 '명령이 거절되면'(1983행), 6.21 표 셋째·넷째 줄.
- **문제**: 1차 `_rejected`는 `ReadOnlyNoteException`·`SessionClosedException`·`PageNotOpenException`·`LastPageDeletionException`·`StateError` 밖의 오류(= `ArgumentError`)를 `default:` 갈래에서 **보고 + 스낵바 '실행하지 못했어요'**로 처리하고 `null`만 돌려준다(`commands/editor_commands.dart` 608–635행, `default:` 631행). 그래서 6.21의 '`UpdateObjects`가 `ArgumentError`(원격 삭제) → 보고 안 함·안내 없음'이 `_run`으로는 나오지 않고, 텍스트 세션은 거절이 '원본 사라짐'인지 '읽기 전용'인지 가를 수 없다(둘 다 `null`) — 읽기 전용이면 `AddObjects`로 다시 넣다가 두 번 거절되고 안내가 두 번 뜬다.
- **고칠 방향**: `UpdateObjects`를 보내기 전에 `session.pageIfLoaded(pageId)?.objectById(id) == null`을 동기로 검사해 '원본 사라짐'은 명령 없이 처리(핸들: 미리보기만 지움 / 텍스트: 새 id로 `AddObjects`)하고, 그 밖의 거절만 `_run`에 맡긴다. E2-08·E2-10 시험에 '원격 삭제 뒤 끝 → 스낵바 없음·`FlutterError` 보고 없음'을 단언한다.

### S-2. 회전된 단일 객체의 모서리 크기 조절 수학이 빠져 있다

- **위치**: 6.6.4 표(타원·텍스트·이미지·수식 행), 6.6.5 표 '모서리 핸들(비율 유지) → `TransformElements`(INK `SelectionGeometry.resize(keepAspect: true)`)'(1743–1746행), 6.6.6.
- **문제**: `SelectionGeometry.resize`는 **축 정렬** `Rect bounds`와 페이지 축 `delta`만 받고 반대 모서리를 그 AABB 모서리로 고정한다(`selection_geometry.dart` 41–80행). INK `InkSelection.bounds`도 회전된 객체를 AABB로 준다(03-ink 6.14). 회전된 이미지·타원·텍스트 상자·수식의 모서리 핸들은 회전된 frame 모서리에 그려지는데(6.6.4), 이 함수로 행렬을 만들면 반대 모서리가 고정되지 않고 배율도 AABB 대각선 기준이 되어 손가락을 따라오지 않는다. M5-2·M5-3의 '크기·회전'이 P-A다.
- **고칠 방향**: `ObjectResize`에 `static core.Affine2 cornerScale(core.ElementFrame frame, ink.SelectionHandle corner, Offset deltaPagePt)` — frame 지역 축으로 delta를 돌려 대각선에 투영한 균일 배율 s, 원점 = 반대쪽 **회전된** 모서리 — 를 두고 `unit/object_resize_test`에 '30° 회전 이미지 모서리 끌기 → 반대 모서리 고정·비율 유지'를 더한다. 함께: 폴리라인 도형은 `frame.rotation`이 늘 0(7.2.2)이라 6.6.6 '절대 각' 무리에 넣는 것이 뜻이 없다 — 상대 각 쪽으로 옮기고 꼬리표도 상대 각으로. `rotate_test`의 '33° → 30°'는 맞춤 문턱(±3°) 경계값이라 포인터 좌표에서 나온 각으로는 흔들린다 — 32°처럼 경계 안쪽 값을 쓴다.

### S-3. 작업 분해 — 너무 큰 작업 하나와 선행 사슬 하나

- **위치**: 8.2 E2-07(2296행), E2-04(2293행), E2-13·E2-16(2302·2305행), E2-01(2290행), 8.2 끝 '병렬'·'P-A 안에서는 … E2-16·E2-17이 앞이다'(2312–2313행).
- **문제**:
  - E2-07은 선택 메뉴 v2·색 팝업·클립보드 이름 바꿈·붙여넣기 v2·컨텍스트 메뉴 v2·단축키·확장 항목·`ExtensionRunner`에 시험 파일 7개다. 한 세션에 끝내기 어렵다(8.4가 E2-06+07에 2.5를 줬다). E2-04도 접촉 상태 기계 + 제스처 + 손가락 동작 + 펜 탭 훅에 R34~R46이다.
  - E2-16(녹음 연동 ①, '앞에 할 P-A')의 선행에 E2-13(툴바 v2)이 있고, E2-13은 E2-09·E2-10·E2-12 뒤다. 그래서 녹음 연동은 도형·텍스트 완성·이미지 뒤로 밀린다 — 8.2 끝 문장 'E2-16·E2-17은 E2-04 뒤'와 모순.
  - E2-01(첫 작업)의 시험 '탭 → 편집기 포커스'에는 텍스트 도구(`EditorTool.text` — E2-03)나 다른 진입점이 필요한데 선행이 E2-00뿐이다. Q1의 '첫 주 iPad 미리보기'도 사용자가 상자를 만들 UI 진입점이 있어야 한다.
- **고칠 방향**: E2-07을 (a) 클립보드 v2·붙여넣기·컨텍스트 메뉴·단축키, (b) 선택 메뉴 v2·색 변경, (c) `selectionMenuItems`·`EditorSelectionContext`·`ExtensionRunner`로 나눈다. E2-04를 (a) `StylusContactRule`·공중/접촉·펜 버튼·지우개 끝(R34–R42), (b) 손가락 동작·길게 누르기·펜 탭 훅(R43–R46)으로 나눈다. 마이크 단추 자리를 E2-16에 넣고 E2-16의 선행에서 E2-13을 뺀다(E2-13은 자리를 툴바 배치로 옮기기만). E2-01 선행에 E2-03을 넣거나, E2-01이 최소 진입점(개발자 메뉴 '텍스트 상자 시험' 또는 도구 키 T)을 함께 만든다고 적는다.

### S-4. INK가 이미 준 것을 '동시 개발 중 없음'으로 가정했다

- **위치**: 5.2.4 표 레이저 행(1288행 — '통합 E2-21로'), `setPreviewObjects` 행(1286행), 12.1 CP-E3(2457행), 11 리스크 2.
- **문제**: 03-ink 4.13 표는 R2-B3에 `setHiddenObjectIds`·`setPreviewObjects`(동작), `hitTestRecorded`(동작), 테이프 API(드러냄 집합 동작, `hitTestTape`는 bounds), **레이저 `end() → null`(K-9, C2-37을 R2-B3에 적용)**을 넣었다. 또 4.12에 `FakeInkShapeFitter`·`SyntheticInk.loopThenHold`(멈춤 시험용)가 있다. EDITOR는 레이저 시험을 통합으로 미루고 자동 도형 멈춤을 '시험 fitter'라고만 적었다.
- **고칠 방향**: 5.2.4 표를 03-ink 4.13에 맞춰 고치고(레이저는 동시 개발 중 실제 INK로 `laser_test`), CP-E3는 '7.6 R2-B3 문장을 03-ink 4.13 표에 맞춰 정리'로 낮춘다. E2-15·E2-21에 `FakeInkShapeFitter`·`SyntheticInk.loopThenHold`를 쓴다고 명시한다.

### S-5. 자동 도형 오인식 표본을 실제로는 모을 수 없다

- **위치**: 6.20 '마지막 획 JSON 복사'(2199행), 9.4 B-4, E2-20·E2-24.
- **문제**:
  - `Stroke.toJson()`의 점은 base64 코덱이다(`/home/user/wt/core/packages/note_core/lib/src/model/stroke.dart` 149행 `StrokePointsCodec.encodeBase64`). LIBRARY 표본 형식은 `{kind, points: [[x, y], …], viewScale}`다(05-library 6.17 끝, 1875행). 형식이 다르고 `viewScale`·기대 종류(`kind`)가 없다.
  - 정작 모아야 할 '잘못 바뀜'(글씨 → 도형) 획은 자동 보정 확정 때 **원래 획이 저장되지 않으므로**(7.2.3 원문) '가장 최근 커밋 획'에 없다. 되돌려도 원래 획은 돌아오지 않는다.
- **고칠 방향**: EDITOR가 마지막 N개(예: 5) 펜 세션의 페이지 좌표 점·`viewScale`·결과(`addShape`면 그 `kind`)를 자기 링 버퍼에 두고(EDITOR가 INK에 넘기는 표본이므로 EDITOR 안에서 된다), 개발자 메뉴가 LIBRARY 형식으로 복사한다(기대 종류는 작은 선택 시트로). LIBRARY와 형식을 맞춘다(X-6).

### S-6. 웹에서 이미지 선택을 '메뉴·시트를 닫은 뒤' 부르면 Safari가 막을 수 있다 · 넘기는 `context`

- **위치**: 4.3.1 '메뉴가 닫힌 뒤 `await`'(482행), 6.12.2 1(2020행), 6.12.3 '시트를 닫은 뒤 `pick`'(2030행), 6.8 컨텍스트 메뉴 '이미지 붙여넣기'.
- **문제**: Safari의 `navigator.clipboard.read()`와 file input `click()`(`image_picker_for_web`)은 사용자 동작 직후에만 열린다[추측 — 06-pdf 6.12.4·위험 4가 같은 우려]. 메뉴 닫힘·시트 닫힘 애니메이션 뒤에 부르면 사진 보관함·카메라·붙여넣기가 주 기기에서 열리지 않을 수 있고, media의 '허용한 뒤 다시 눌러 주세요'도 같은 경로라 다시 실패한다. 또 `pick(context, …)`·`onSelected(context, …)`에 **어느 `BuildContext`**를 넘기는지 적혀 있지 않다 — 메뉴 항목 context는 메뉴가 닫히면 unmounted인데, media는 그 context로 `showModalBottomSheet`(CP-PDF-11)를, recog는 `ProviderScope.containerOf(context)`(05-library 5.4)를 쓴다.
- **고칠 방향**: 이미지 출처 항목은 `onPressed` 안에서 **동기적으로** `pick` Future를 시작하고 메뉴·시트 닫기는 그 뒤에 한다(두 번 누름 막기·E-7 처리는 그대로). 넘기는 context는 에디터 본문(`EditorBody`)의 것이라고 4.3.1에 적는다. 9.4 B-3에 '삽입 메뉴·페이지 추가 시트에서 사진 보관함·카메라·붙여넣기가 한 번에 열림'을 더한다(X-5).

### S-7. 텍스트 편집기 — 선택 손잡이·붙여넣기 메뉴, INK와 같은 글자 위치

- **위치**: 3절 `text/text_box_editor.dart`('`EditableText` 오버레이'), 6.11.3 '텍스트 스타일 변환'(1962행), 6.7.6 끝(1831행), 1.3 둘째 줄(85행).
- **문제**:
  - 날것 `EditableText`는 `selectionControls`·`contextMenuBuilder`·선택 제스처(`TextSelectionGestureDetectorBuilder`)를 따로 주지 않으면 iPad 터치에서 두 번 탭 단어 선택·선택 손잡이·복사/붙여넣기 메뉴가 없다. 하드웨어 키보드 없는 iPad에서는 글을 고르거나 붙여넣을 방법이 없다. `material_ui` 1.10.0 `TextField`는 이것을 다 준다(pub 캐시 `lib/src/text_field.dart` 224행, `selectionControls` 325행). 1차도 HEX 입력란 등에 `TextField`를 쓴다.
  - 편집기 글자 모양을 EDITOR가 따로 변환(6.11.3)하면 INK 그림과 줄 높이·여백이 어긋나 세션 끝에 글자가 튄다. INK가 CP-INK-3(`InkTextLayout.textStyleOf`·`strutStyleOf`, 안쪽 여백 0·강제 strut)을 바로 이것 때문에 제안했는데 EDITOR 계획서는 답하지 않았다.
  - 1.3 '시스템 클립보드 연동(앱 밖 텍스트를 텍스트 상자로 붙여넣기) — 넣지 않는다'와 6.7.6 '⌘V는 `EditableText`의 글자 편집'(= 시스템 클립보드 붙여넣기)이 서로 다르게 읽힌다.
- **고칠 방향**: `material_ui` `TextField`(장식 없음, `InputDecoration.collapsed`)를 쓰거나 선택 손잡이·메뉴를 명시한다. 글자 모양은 CP-INK-3 승인 시 INK 함수를 쓴다고 6.11.3에 적고 12.1에서 지지한다(X-2). 1.3 문구를 '캔버스 수준 붙여넣기(시스템 텍스트 → 새 상자)는 넣지 않음, 편집 중 글자 붙여넣기는 됨'으로 고친다.

### S-8. 안 A(시트)가 iPad 가상 키보드에 가리고, 시트 모드의 숨김·미리보기 규칙이 없다

- **위치**: 6.11.6 표 안 A(1993행), E2-01 `text_input_sheet_test`.
- **문제**: 화면 아래쪽 50% 시트의 입력란은 iPad 가상 키보드(가로에서 화면의 약 40%)에 가리기 쉽다. Safari에서 Flutter 웹이 `viewInsets`를 정확히 받는지는 확인되지 않았다[추측]. 또 시트 모드는 기존 상자를 `setHiddenObjectIds({id})`(세션 시작 — 6.11.2 `start`)로 숨기면서 같은 id의 `setPreviewObjects([draft])`로 미리보기를 그리는데, '숨김 id와 같은 id의 미리보기' 중 무엇이 이기는지가 계약 7.2.9·03-ink 6.17 어디에도 없다 — 숨김이 이기면 미리보기가 안 보인다.
- **고칠 방향**: 안 A 입력 패널을 화면 **위쪽**에 붙이거나 `viewInsets`를 반영해 위로 올리고, 시험에 `viewInsets` 있는 경우를 더한다. 시트 모드에서는 숨김을 쓰지 않고 같은 id 미리보기(대체 규칙)만 쓴다고 적거나, INK에 '미리보기는 숨김 집합과 무관하게 그린다' 규칙을 요청한다(X-3).

### S-9. Chrome 텍스트 시험이 브라우저 입력을 거치지 않는다

- **위치**: E2-01 `web/text_input_browser_test.dart`(2290행), 9.2 Chrome 행('웹 런타임 텍스트 입력'), E2-11 `web/textarea_overlay_browser_test.dart`.
- **문제**: `flutter test --platform chrome`에서도 `tester.enterText`는 `TestTextInput`이 `flutter/textinput` 채널을 가로채 값을 넣는다 — 엔진의 DOM 입력 요소·IME를 거치지 않는다. 이 시험은 '웹에서 컴파일되고 세션 규칙이 같다'까지만 보여 준다. E2-11의 `HtmlElementView.fromTagName`이 시험 바인딩에서 실제 `<textarea>`를 만들고 `onElementCreated`를 부르는지는 V2(`flutter analyze`만)로 확인되지 않았다.
- **고칠 방향**: 9.2·9.3 설명을 '웹 컴파일·세션 규칙'으로 고치고 IME 판정은 B-2뿐이라고 밝힌다. E2-11은 P-C지만 시작 전에 시제품 시험 한 번으로 실행 가능성을 확인한다고 적는다.

### S-10. 설정 키·공개 enum 정리

- **위치**: 6.18 표 `editor.playback.preRollMs`(2168행)·끝 문단(2171행), 6.19 표, 4.3.3(525–526행), 4.1.
- **문제**: `EditorSettingKeys.all`은 `List<core.SettingKey<Map<String, Object?>>>`다(`state/settings/editor_setting_keys.dart` 44행). `SettingKey.integer`(=`SettingKey<int>`)를 그대로 넣으면 타입이 맞지 않는다. 또 preRoll 값을 읽고 쓰는 provider·notifier가 6.19 표에 없다(설정 슬라이더·탭 재생이 어디서 읽는지 불명). `PlaybackHighlightStyle`은 `ink.InkPlaybackStyle`과 1:1인데, 1차 `EditorSettings`는 이미 `ink.PressureMode`를 그대로 쓴다(`editor_settings.dart`) — 같은 enum을 하나 더 공개할 이유가 약하다. `WebTextInputMode`는 개발자 메뉴 전용인데 공개 `EditorSettings` 필드가 되어 공개 표면이 커진다.
- **고칠 방향**: `all`의 형을 `List<core.SettingKey<Object?>>`(또는 두 목록)로 바꾼다고 적고, `editorPreRollMsProvider`(루트, 500 ms 디바운스)를 6.19에 더한다. `playbackHighlight`는 `ink.InkPlaybackStyle`을 그대로 쓰고, `webTextInput`은 EDITOR 내부 device 키로 옮기는 것을 검토한다(공개 이름 2개 감소 — Q12도 단순해짐).

### S-11. 긴 텍스트 세션은 끝날 때까지 메모리에만 있다

- **위치**: 6.11.2·6.11.5, 6.21.
- **문제**: E-6 때문에 세션 중 글은 초안(메모리)뿐이다. 앱 숨김은 세션을 끝내지만, 앞에 둔 채 탭 재로드(B-13이 걱정하는 메모리 압박)·충돌이면 회의록처럼 긴 세션 전체를 잃는다. 읽기 전용 경합 때 '쓴 글은 사라짐'(1983행)도 같은 손실이다.
- **고칠 방향**: 초안을 device 키(예: `editor.textDraft`, 노트·상자 id 포함)에 몇 초마다 덮어 쓰고, 다시 열 때 남아 있으면 '저장되지 않은 글이 있어요' 복구를 제안한다(명령은 여전히 세션 끝 1회 — E-6 그대로). 읽기 전용 거절 때는 글을 시스템 클립보드로 복사하고 안내한다.

### S-12. 작은 것들

- (a) 개요 6장 공통 목차는 13절 = 확장 지점·자리 사용표, 14절 = 네이티브·권한 요구표인데 이 계획서는 13절을 '검토 반영 내역'으로 쓰고 둘을 부록 A·B로 옮겼다. 다른 영역 계획서와 같이 번호를 맞춘다.
- (b) 6.4.4 '펜 뒤쪽 지우개' 줄은 '언제나'인데 웹 엔진은 `invertedStylus`를 만들지 않는다(조사 02 8.4). 웹에서는 숨긴다(주 기기 iPad Safari에서 의미 없는 줄).
- (c) 6.5.3 `isPenOnlyEffective = … || prefersPencilOnlyDrawing` — 1차 `isPenOnlyEffective`는 `EditorSettings`의 getter라 능력 값을 모른다. 계산 위치(입력 정책 provider)를 적는다.
- (d) 6.22 '< 2 ms(EDITOR 몫)'·'< 30 ms(EDITOR 몫)'은 INK 호출을 포함한 경로에서 EDITOR 몫을 어떻게 떼는지 정의가 없다. 공유 CPU에서 흔들리지 않게 1차 성능 스모크의 여유 규칙을 그대로 적용한다고 적는다.
- (e) E2-00 `no_platform_imports_test`의 '일부러 위반한 임시 파일'은 `lib/`가 아니라 임시 폴더의 가짜 트리로 검사한다(다른 검사·분석과 겹치지 않게).
- (f) E2-21·`rotate_test` 등에서 회전 각을 포인터 좌표로 만들 때는 맞춤 경계값을 피한다(S-2).

---

## 다른 영역과 걸리는 것

### X-1. INK — 관찰용 getter (M-1)

`InkPageController.previewObjects`·`hiddenObjectIds`·`playbackFocus`, `StrokeSession.shapeAssist`(읽기 전용)를 R2-B3에 '추가'로 넣어 달라고 요청해야 한다. 없으면 EDITOR 위젯 시험 7개 묶음이 완료 조건을 못 채운다. INK 4.12 `testing.dart`에 기록용 도우미를 두는 방식도 된다(공개 표면을 늘리기 싫다면).

### X-2. INK — CP-INK-2·CP-INK-3 · 테이프 상태 수명

- CP-INK-2(부분 지우개가 도형에 닿음 → `CompositeCommand([SplitStrokes|RemoveStrokes, RemoveElements])`): EDITOR 5.1.2 표의 '지우개가 도형에 닿음' 행이 획 지우개(`eraseStrokes`)만 적었다. 부분 지우개 경우를 행에 더하고 `erase_v2_test`에 '부분 지우개가 도형을 지남 → 명령 1개·되돌리기 1번에 도형과 조각 모두 복구'를 넣는다.
- CP-INK-3(`textStyleOf`·`strutStyleOf`): EDITOR가 지지·사용한다고 답해야 한다(S-7). 03-ink 12.3 '다른 영역 요청에 대한 INK 답'에 EDITOR 쪽 대화가 없다.
- 03-ink 12.2 Q2(테이프 드러냄 = 컨트롤러 수명 — 페이지가 마운트에서 빠지면 다시 가림): EDITOR I-10은 노트 단위 '모두 보이기/가리기'만 새 마운트에 다시 넣으므로 낱개 토글은 스크롤로 사라진다. 받아들이는지 6.14.4에 적는다.

### X-3. INK — 숨김 id와 같은 id 미리보기의 우선 (S-8)

시트 모드·텍스트 폭 핸들처럼 '숨긴 상자를 같은 id 미리보기로 그리는' 경우의 규칙을 INK 6.17에 요청하거나 EDITOR가 그 조합을 쓰지 않는다.

### X-4. PDF(media) — 탭 재생 상태 (M-3)

media 패널은 열 때·정지 뒤 녹음을 `open`한다(06-pdf 6.13.3). EDITOR가 '탭 재생 상태'를 '패널 열림 또는 playing/paused'로 좁히면 media 쪽 변경은 없다. CP-PDF-10(녹음 중 `play()` 무시)에 맞춰 EDITOR는 녹음기 `isActive`일 때 가로채지 않는다고 적는다. 06-pdf 6.13.3의 'EDITOR 탭 재생 조건을 만족시킨다' 문장도 새 조건에 맞춰 PDF가 고친다.

### X-5. PDF(media) — 사용자 동작 활성화 · context (S-6)

`importImageForNote`를 메뉴 `onPressed` 안에서 동기적으로 시작하는 것을 media와 합의한다(06-pdf 12.3 Q6의 '⌘V 붙여넣기 이벤트 경로는 다음 라운드'와 별개로 이번 경로부터). 넘기는 context가 에디터 본문 것임을 PDF·LIBRARY(recog `containerOf`)에 알린다.

### X-6. LIBRARY — 도형 표본 형식 (S-5) · CP-L3·CP-L5

표본 형식 `{kind, points, viewScale}`을 EDITOR 개발자 메뉴가 그대로 내도록 맞춘다(05-library 12.2 Q7 '모으기 EDITOR, 판정 LIBRARY'에 EDITOR가 답). CP-L3('선택 문맥의 `done` = `clearSelection`, 바꾸기 뒤에만')·CP-L5(`isVisible`은 그릴 때마다 — 가볍게, provider 읽지 않음)는 EDITOR 6.7.4와 같은 내용이므로 12.1에서 지지한다고 적는다. INFRA `insertMenuItemOf`는 `RecognitionAction.isVisible`을 버린다(01-infra 4.6.5) — EDITOR 삽입 메뉴는 항상 보임으로 이해하면 된다.

### X-7. CORE — CP-1의 `RemoveElements.elementIds` 형 · CP-8

CORE CP-1은 이름 있는 인자 + `label`에 더해 `RemoveElements.elementIds`를 `Set` → `List<ElementId>`로 바꾸자고 한다(02-core 12.1). EDITOR CP-E1은 '이름 있는 인자'만 지지했다 — 형 변경까지 지지하는지 밝히고(잘라내기·텍스트 삭제가 이 명령을 만든다), INK `toCommand`와 같은 형을 쓰는지 확인한다. CP-8(`FakeAudioPlayback.calls`)이 승인되면 `recording_playback.dart` 래퍼를 지운다고 이미 적었다 — 그대로 좋다.

### X-8. INFRA — CP-E8 · 시작 시 능력 한 번

CP-E8(V5 '90° 돌리기' 메뉴 경로)은 INFRA V5 문장 변경이라 INFRA 계획서와 같이 올라가야 한다. INFRA는 `PencilBridge.capabilities()`를 시작 때 한 번 읽어 어댑터를 만든다(01-infra 4.6.5) — 앱 실행 중 '펜슬로만 그리기'·선호 동작이 바뀌면 다시 시작해야 반영된다는 점을 EDITOR 6.5.3·설정 안내에 적거나 C-3으로 계약을 넓힌다.

---

## 계약 문제

- **C-1** (7.2.9, M-1): 계약이 쓰기 멤버만 정해 소비자가 결과를 확인할 수 없다. 읽기 getter 넷(`previewObjects`·`hiddenObjectIds`·`playbackFocus`·`StrokeSession.shapeAssist`)을 '추가'로 넣는다. 동시 개발 중 '추가만' 규칙(7.4.9) 안이다.
- **C-2** (7.2.9): 계약은 `abstract class StrokeSession { … shapePreview }`로 적었지만 1차 코드는 `final class StrokeSession implements InkGestureSession`(`sessions.dart` 195행)이다. 계약 문구를 코드에 맞추거나(INK), 소비자가 상속·구현할 수 없음을 밝힌다. EDITOR는 어느 쪽이든 가짜 세션을 만들지 않는다(M-1).
- **C-3** (7.2.10): `StylusExtrasSource.capabilities`는 동기 getter이고 바뀜 알림이 없다. `prefersPencilOnlyDrawing`·선호 동작은 사용자가 iPadOS 설정에서 바꾸는 값이다. '앱 다시 시작 때 반영'을 문장으로 적거나 `Stream<StylusCapabilities>`(선택) 추가를 검토한다.
- **C-4** (7.3.2 E-7): E-7은 '자리 콜백의 예외는 보고 후 사용자 문구'인데 EDITOR는 `isVisible` 예외를 '숨김 + 보고, 문구 없음'으로 한다(4.3.1·6.21). 메뉴를 그릴 때마다 문구가 뜨면 안 되므로 EDITOR 쪽이 맞다 — E-7에 '보이기 판정 콜백은 숨김 + 보고'를 예외로 적는다.
- **C-5** (7.2.10 E-4, CP-E4): 6.3.2 상태표는 CP-E4(접촉 중 접촉 비트가 빠진 `move` = 그 접촉의 끝)를 승인 전부터 구현한다. 계약보다 좁히는 EDITOR 내부 동작이라 문제는 없지만, '승인 전까지 원문대로'(12.1 머리) 문장과 맞게 6.3.2 해당 행에 'EDITOR 내부 — CP-E4 승인 시 계약 문장'이라고 표시한다.
- **C-6** (7.2.3 원문 주석): `ClearPage(pageId, filter = StrokeFilter.all, {bool includeObjects = false})`·`TransformElements(pageId, elementIds, …)`는 위치 인자처럼 적혔지만 1차는 이름 있는 인자다(`commands.dart` 81행 `const ClearPage({required this.pageId, this.filter})`). CP-1을 정할 때 이 표기도 함께 정리한다(EDITOR 5.1.2 표의 `ClearPage(pageId, filter, includeObjects: true)` 표기도).
- **C-7** (7.2.4 R-5): '필기 탭 재생'이 언제 켜지는지(탭 재생 상태)가 계약에 없다. media가 정지 뒤 녹음을 열어 두는 동작과 맞물려 필기 손실이 생기므로(M-3) R-5에 '패널이 열려 있거나 재생·일시정지 중일 때만'을 더하는 것을 권한다.

---

## 질문

1. M-4의 (a)·(b) 중 어느 쪽인가? (a)면 '펜 도구 + 붙여넣은 선택'의 본체 끌기도 막히는데(임시 올가미 선택만 허용), B-5 '펜 도구에서 선택 끌기'(9.4) 항목과 맞는가?
2. M-3에서 '패널이 닫혀 있어도 재생 중(playing)이면 탭 재생'을 유지할 것인가, 패널이 열려 있을 때만으로 더 좁힐 것인가?
3. S-7의 CP-INK-3을 EDITOR가 받는다면, INK 함수가 나오기 전(R2-B3에는 없음) E2-01 시제품은 무엇으로 글자 모양을 맞추는가?
4. S-8 안 A 입력 패널을 화면 위쪽에 두는 것은 7.4.10 '바닥 시트' 규칙(다른 영역 UI용)과 무관한 EDITOR 자체 UI로 보면 되는가?
5. S-5의 표본 링 버퍼(획 점 보관)는 개발자 메뉴가 켜져 있을 때만 쌓는가, 늘 쌓는가(메모리·개인정보 — U18 동의 범위)?
