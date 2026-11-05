# 2차 라운드 기술 조사 01 — 계약·코드에 마련된 M5~M7 자리와 빈틈

> 상태: 조사 완료(2026-11-05) · 담당: 2차 라운드 기술 조사 · 기준 계약: [00-overview.md 7장 v1.4](../../00-overview.md#7-통합-계약) · 마스터 기획서: [PLAN.md](../../../PLAN.md) F-03·F-10·F-11·F-12·F-14·F-16, 5장, 10장 M5~M7
>
> 이 문서는 **지도**다. 1차 계약과 영역 작업 트리의 최신 코드에서 M5(편집 강화)·M6(녹음)·M7(인식)을 위해 이미 마련된 자리와 빠진 자리를 항목별로 적는다. 설계 결정은 하지 않고, 결정이 필요한 곳은 9절 '열린 질문'으로, 조사자의 의견은 8절 '권장안'으로 분리한다.

표기

| 표시 | 뜻 |
|---|---|
| **[확인]** | 코드를 읽거나 명령을 실행해 직접 확인한 사실(경로·줄 번호·명령을 함께 적음) |
| **[문서]** | 계획서·계약 문서에 적힌 내용(코드로는 확인하지 않음) |
| **[추측]** | 확인하지 않은 판단. 근거를 함께 적고, 설계 전에 확인이 필요하다 |

계약 변경 분류(각 표의 '계약' 열)

| 값 | 뜻 |
|---|---|
| 없음 | 영역 내부(`lib/src/`, 진입점에서 export하지 않음) 변경만 |
| 추가 | 공개 진입점에 새 타입·멤버·선택 인자를 더함. 기존 호출은 그대로 컴파일된다(그래도 7.4.12 절차 대상) |
| 깨짐 | 기존 공개 시그니처·의미가 바뀌거나, sealed/enum 값 추가로 **다른 패키지의** exhaustive switch가 컴파일되지 않음 |
| 규칙 | Dart 시그니처는 같고 계약 문장(override 소유표·예산·힌트 규칙 등)만 바뀜 |

---

## 1. 요약 — 핵심 사실

1. **예약 펜 5종은 저장·동기화까지 이미 된다.** `core.PenTool`에 `brush·calligraphy·dashed·laser·tape`가 있고 `StrokeStyle.defaultsFor`에 기본값(캘리그래피 `nibAngleDeg: 45`, 점선 `dash: [4, 3]` 등)도 있다. INK는 `PenProfile.of`에서 5종 모두 볼펜 프로필로 그린다. 빠진 것은 렌더 방식(펜촉 외곽선·점선 분할·사라지는 획·가림 레이어)과 EDITOR 선택기 노출뿐이다. [확인]
2. **획 이외의 페이지 요소는 자리만 있다.** `PageElement`는 sealed이고 하위 타입은 `Stroke` 하나다(주석: "Shape, TextBox, MathObject and ImageObject are added in M5/M7"). `EntityKind`·DB 테이블·`PageContent`·`PageDraft`·INK `InkPageContent`·벡터 내보내기·SYNC 코덱이 모두 획만 다룬다. 요소를 넣으면 CORE·INK·EDITOR·PDF·SYNC 5개 영역의 계약이 바뀐다. [확인]
3. **`TransformElements`는 이름만 일반형이다.** 명령은 `elementIds`를 받지만 CORE 해석기는 획만 찾아 변형한다(`command_resolver.dart` 172–187). [확인]
4. **`ImageBackground`(이미지 페이지)는 CORE 모델·JSON·동기화까지 있고 그리는 쪽이 없다.** INK는 종이 색만 칠하고, 썸네일 렌더러는 `null`, PDF 내보내기는 빈 페이지로 낸다. INK `InkBackgroundSpec`에는 `fit` 필드가 없다. 이미지 배경 빌더를 넣으려면 "`pageBackgroundBuildersProvider`는 `pdfIoOverrides()`만 override" 규칙(7.2.16·7.3.3)도 바뀌어야 한다. [확인]
5. **녹음 연동에 필요한 시간 정보는 모두 저장된다.** `StrokePoint.t`(획 시작부터 ms, 0.1ms 양자화, 최대 500,000ms), `Stroke.createdAt`(펜 다운 벽시계 ms), `Stroke.recordingId·recordingOffsetMs`(SYNC 병합 단위 한 묶음, DB 색인 `idx_strokes_recording`), INK `InkStrokeMeta`가 펜 다운 때 두 값을 받아 획에 넣고 긴 획 분할 때 오프셋도 맞춘다. EDITOR는 지금 `InkStrokeMeta`를 넘기지 않는다. [확인]
6. **`Recording` 엔티티는 테이블·JSON·동기화만 있고 로컬에서 만드는 API가 없다.** 원격 적용 경로로만 행이 생긴다. `assetId`가 필수라 오디오 바이트가 다 모인 뒤(해시 계산 뒤)에야 행을 쓸 수 있고, 녹음 중에 쓴 획은 아직 없는 녹음 id를 가리킨다(외래 키가 없어 허용). 재생 중 획 강조용 INK API도 없다. [확인]
7. **올가미 회전·색 변경 계산은 INK에 있고 UI가 없다.** `SelectionGeometry.rotate`·`snapAngle`(15°, ±3°), `InkSelection.recolor`·`duplicate`가 있다. EDITOR 선택 메뉴는 `[복사] [삭제] [선택 해제]` 세 개, 변형은 이동·비율 유지 크기 조절뿐이다. 붙여넣기는 길게 누르기·우클릭 메뉴에 있다. 클립보드는 앱 내부 전역(획만)이다. [확인]
8. **S펜 측면 버튼은 플러그인 없이 받을 수 있다.** Flutter 3.47.9 안드로이드 엔진이 `BUTTON_STYLUS_PRIMARY`를 `PointerEvent.buttons`의 `kPrimaryStylusButton`으로 바꿔 준다(`AndroidTouchProcessor.java` 338–345). EDITOR `InputRouter`는 펜의 버튼 비트를 보지 않는다. Apple Pencil 더블탭·스퀴즈는 Flutter iOS 임베딩에 `UIPencilInteraction` 연결이 없어 **네이티브 플러그인이 필요**하고, `PointerEvent`에는 배럴 롤 필드도 없다. [확인]
9. **제스처 설정은 켜기/끄기 bool 세 개다.** `GestureSettings`(공개 타입, synced 키 `editor.settings.synced`의 `gestures`)는 모르는 키를 무시하고 빠진 키는 기본값으로 읽어 확장에 유리하다. 동작 매핑 구조는 없다. [확인]
10. **`sqlite3.wasm`(3.8.0, 계약 sha256 `efd308be…`)에 FTS5가 들어 있고 웹에서 동작한다.** 헤드리스 Chrome에서 실제로 `CREATE VIRTUAL TABLE … USING fts5`를 만들고 한글 질의를 돌렸다. `unicode61`은 공백 단위 낱말·접두사 질의(`회의*`)가 되고 낱말 중간(`의록`)은 안 된다. `trigram`은 3글자 이상 부분 문자열이 되고 **2글자 질의는 MATCH로 0건**(LIKE로는 찾음)이다. 네이티브 미리 빌드 라이브러리(SQLite 3.54.1)도 `ENABLE_FTS5`다. ICU는 없다. drift_dev 2.35.2는 `sqlite_modules: [fts5]` 옵션을 지원한다. [확인]
11. **PDF 합성 경로는 경로(path) 채우기·선 긋기만 한다.** 그러나 pdfrx 2.11.0의 `pdfium.wasm`은 이미지 객체(`FPDFImageObj_LoadJpegFile`·`FPDFImageObj_SetBitmap`·`FPDFPageObj_NewImageObj`)와 텍스트 객체(`FPDFText_LoadFont`·`FPDFPageObj_CreateTextObj`·`FPDFText_SetText`) 함수를 export한다(482개 export 중). 텍스트 상자·이미지·수식을 PDF에 넣는 길은 열려 있다(실행은 미확인). [확인]
12. **SYNC 코덱은 모르는 `kind`를 만나면 청크 전체를 버린다.** `ChunkCodec._kind`가 `FormatException`을 던지고 다운로드 파이프라인이 그 청크를 `malformedRemoteData`로 건너뛴다(커서 진행 = 되돌릴 수 없음). 새 엔티티 종류를 추가한 앱과 옛 앱이 섞이면 옛 앱은 그 청크에 같이 실린 **기존 종류(획 등)까지** 잃는다. [확인]
13. **안드로이드 APK는 지금 durable 저장소를 열 수 없다.** 앱 셸이 `nativeDatabasePath`를 넘기지 않아 네이티브에서 `openNoteStore`가 `storageUnavailable`로 실패하고, 네이티브 에셋 바이트·썸네일은 프로세스 메모리(`newIdbFactoryMemory`)에만 있다. 네이티브에서만 검증할 수 있는 M6(백그라운드 녹음)·M7(ML Kit)의 선행 조건이다. [확인]
14. **텍스트 상자에 쓸 한글 글꼴이 번들되어 있지 않다.** 앱에 `fonts:`가 없고 Flutter 웹 CanvasKit은 대체 글꼴을 `https://fonts.gstatic.com/s/`에서 받는다. 계약 7.4.9는 서비스 워커가 없다. PDF에 텍스트를 넣으려면 글꼴 바이트도 필요하다. [확인 — 오프라인 영향은 추측]

---

## 2. 조사 기준과 방법

### 2.1 기준 작업 트리 (모두 읽기 전용으로 읽음, 2026-11-05)

| 영역 | 경로 | 브랜치 | HEAD | 상태 |
|---|---|---|---|---|
| CORE | `/home/user/wt/core` | `area/core` | `4336967` | 개발 중(T16~T18까지) |
| INK | `/home/user/wt/ink` | `area/ink` | `3411e53` | 개발 중(T21 벡터 내보내기까지) |
| EDITOR | `/home/user/wt/editor` | `area/editor` | `93dc827` | 동시 개발 완료 |
| LIBRARY | `/home/user/wt/library` | `area/library` | `ec403be` | 동시 개발 완료 |
| PDF | `/home/user/wt/pdf` | `area/pdf` | `300774e` | 개발 중(조사 중 HEAD가 `902b15b`에서 바뀜 — 인용한 부분은 새 HEAD에서 다시 확인) |
| SYNC | `/home/user/wt/sync` | `area/sync` | `fbe8197` | 개발 중(조사 중 `86b3d0e`에서 바뀜 — 인용한 부분은 새 HEAD에서 다시 확인) |
| INFRA | `/home/user/wt/infra` | `area/infra` | `1a62fba` | 개발 중 |

모든 영역의 진행 기록(`docs/plans/progress/<id>.md`) '변경 요청' 절은 INK의 문구 명확화 1건(`LassoOptions` 면적 정의, 시그니처 변화 없음) 외에 비어 있다. [확인]

### 2.2 실행한 명령 (요약)

```bash
export PATH=/opt/flutter/bin:$PATH CHROME_EXECUTABLE=/usr/local/bin/chrome-nosandbox
# 목차·심볼 찾기
grep -n '^##' docs/plans/00-overview.md 02-core.md …
grep -rn 'EntityKind\.recording' packages/note_core/lib packages/sync_engine/lib
# 계약 wasm 해시와 문자열
sha256sum /home/user/wt/infra/app/web/sqlite3.wasm          # efd308be…2d37 (계약 7.4.9와 같음)
strings -n 4 …/sqlite3.wasm | grep -i fts5                    # 37줄, trigram·unicode61 토크나이저 이름 포함
# FTS5 실제 실행 (4.1절)
cd /tmp/claude-0/plan57-scratch/fts && dart pub get --offline && dart test -p chrome test/fts_probe_test.dart
dart run bin/vm_probe.dart
# pdfium.wasm export 표 파싱 (4.2절)
python3 -I /tmp/claude-0/plan57-scratch/tools/wasm_exports.py ~/.pub-cache/hosted/pub.dev/pdfrx-2.11.0/assets/pdfium.wasm FPDFImageObj_… FPDFText_…
# Flutter 엔진 소스 (/opt/flutter/engine/src/flutter, 3.47.9 = c197ca5)
grep -rn 'BUTTON_STYLUS\|TOOL_TYPE_ERASER' shell/platform/android/…/AndroidTouchProcessor.java
grep -rln 'UIPencilInteraction' shell/platform/darwin                  # 결과 없음
grep -n 'fontFallbackBaseUrl' lib/web_ui/lib/src/engine/configuration.dart
grep -n -i 'roll' packages/flutter/lib/src/gestures/events.dart        # 배럴 롤 필드 없음
# pub.dev
curl -s https://pub.dev/api/packages/<name>
```

### 2.3 출처

| 출처 | 접근 | 쓴 곳 |
|---|---|---|
| 작업 트리 소스·계획서 (위 표) | 직접 읽음 | 전체 |
| Flutter 3.47.9 엔진·프레임워크 소스 `/opt/flutter` (커밋 `c197ca5199e9`) | 직접 읽음 | 3.7, 3.8 |
| `~/.pub-cache/hosted/pub.dev/sqlite3-3.8.0/doc/hook.md` (미리 빌드 라이브러리 컴파일 옵션 표) | 직접 읽음 | 3.10 |
| `~/.pub-cache/hosted/pub.dev/drift_dev-2.35.2/lib/src/analysis/options.dart`·`generated/analysis/options.g.dart` | 직접 읽음 | 3.3, 3.10 |
| `~/.pub-cache/hosted/pub.dev/pdfrx-2.11.0/assets/pdfium.wasm` | export 표 파싱 | 3.8 |
| https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.8.0/sqlite3.wasm | `tool/web_assets.yaml`의 주소. 같은 sha256 파일(`app/web/sqlite3.wasm`)로 실험 | 3.10 |
| https://pub.dev/api/packages/google_mlkit_digital_ink_recognition 및 그 보관 파일(README·`lib/src/digital_ink_recognizer.dart`) | 받아서 읽음(`/tmp/claude-0/plan57-scratch/dl/mlkit/`) | 3.5, 3.10 |
| https://pub.dev/api/packages/{record, image_picker, flutter_math_fork, super_clipboard, path_provider, drift, sqlite3, pdfrx} | 받아서 읽음 | 10절 |
| https://www.sqlite.org/fts5.html, https://developers.google.com/ml-kit/vision/digital-ink-recognition/base-models | **접근 불가**(세션 네트워크 허용 목록 밖 — `getaddrinfo ENOTFOUND`). FTS5 동작은 실험으로 대신 확인했고, ML Kit 한국어 지원은 확인하지 못했다 | — |

---

## 3. 영역별 지도

### 3.1 펜 — 예약 펜 5종과 INK 렌더 경로

| 항목 | 경로 · 심볼 | 현재 동작 | M5에 필요한 변경 | 계약 |
|---|---|---|---|---|
| 펜 종류 enum | `note_core/lib/src/model/pen_style.dart` `PenTool`(`isP0`, `wireName`, `fromWireName`) | P0 5종 + P1 5종이 이미 값으로 있음. 모르는 이름은 `FormatException`. 획 테이블 `strokes.tool`에 이름 텍스트로 저장 [확인] | 값 추가 없음(5종이면). 6번째 펜을 더하면 옛 앱이 그 획을 디코드하지 못한다(3.11) | 없음 |
| P1 기본값 | 같은 파일 `StrokeStyle.defaultsFor` 80–108 | brush `0xFF1F1F1F`·2.0 / calligraphy 2.5·`{'nibAngleDeg': 45}` / dashed 1.0·`{'dash': [4, 3]}` / laser `0xFFFF3B30`·3.0 / tape `0xFF7E57C2`·14.0·smoothing 0.3 [확인] | INK가 렌더 의미를 확정한 뒤 값 조정 가능(7.2.4 표 '`P1 5종` CORE 6.2.2 값 유지'를 실제 값으로 갱신) | 규칙 |
| extras 키 소유 | INK `InkStyleExtras`(계약 7.2.15) | 키는 `hlStraight` 하나. CORE 기본값이 `nibAngleDeg`·`dash`를 쓰지만 INK가 공식 키로 선언하지 않음 [확인] | INK가 `nibAngleDeg`·`dash`(+ 테이프 등 새 키)를 `InkStyleExtras`에 선언하고 `StrokeStyleInk` 확장에 읽기 도우미 추가 | 추가 |
| 펜 → 프로필 | `ink_engine/lib/src/pen/pen_profile.dart` `PenProfile.of` 66–79 | P1 5종 → `ballpoint` 프로필 [확인] | 붓펜: 값만 다른 프로필. 캘리그래피: 펜촉 방향에 따른 외곽선(새 `InkRenderMethod` 값). 점선: 중심선 분할. 레이저·테이프: 아래 행 | 추가(공개 enum `InkRenderMethod`·`InkLayer`·`InkCap`에 값 추가. PDF가 `InkCap`·`InkBlendMode`를 switch하므로 `InkCap` 값 추가는 PDF에 깨짐) |
| 렌더 층 | `ink_engine/lib/src/model/ink_layer.dart` `InkLayer { highlighter, ink }`, `InkRenderLayer { background, highlighterBase, highlighterActive, inkBase, inkActive, overlay }` | 형광펜 층 아래, 일반 필기 위. z 순서는 층 안에서 `compareOrder` [확인] | 테이프(가림)는 일반 필기 **위**에 그려야 하는지 결정 필요(9절 Q5). 위라면 새 층 | 추가 |
| 렌더 외곽 불변식 K-1 | CORE `Stroke.bounds` = `pointBounds.inflate(width · max(2·maxWidthQ, 0.75))`, DB `strokes.min_x…max_y`에 저장 [확인] | 모든 펜이 이 안에 그려져야 함(INK `bounds_invariant_test`) [문서 03-ink 11장] | 새 펜도 공식 안에 맞춘다: 캘리그래피 펜촉 반길이 ≤ `2·width·widthQ`, 점선 캡 원형, 테이프 사각 캡 ≤ 0.75·w. 공식을 바꾸면 모든 기기 bounds·DB 열 재계산 = 깨짐 | 없음(공식 유지 시) |
| 레이저 포인터 | 계약 7.3.2 E-3 "레이저 포인터 획(M5)은 저장하지 않는다" | INK 세션은 `end() → InkEdit?`. 레이저 전용 동작 없음 [확인] | INK: 레이저 스타일 세션은 `InkEdit`을 내지 않고 일정 시간 뒤 사라지는 자취를 overlay 층에 그림(`InkTuning`에 지속 시간). 시그니처 변화 없이 의미만 추가 가능 | 규칙(7.2.15 주석) |
| 암기 테이프 | — | 가림·드러냄 상태 개념 없음. `hitTest`는 있음 [확인] | INK: 테이프 id별 드러냄 상태(`InkPageController`에 상태 집합·토글) + 탭 판정 필터. 상태를 저장할지(기기 로컬/동기화/저장 안 함), 썸네일·PDF에 가린 채 낼지 결정 필요 | 추가 |
| 방위각 · 배럴 롤 | INK W4(03-ink 2049): 웹 `orientation`은 항상 0 [문서]. Flutter `PointerEvent`에 roll 필드 없음 [확인 `events.dart`] | 웹 캘리그래피는 `nibAngleDeg` 고정 각만 가능 | 네이티브 iPad는 `orientation`(방위각)으로 펜촉 각, Pencil Pro 배럴 롤은 `StylusBarrelRoll`(EDITOR `StylusExtrasSource`, 네이티브 플러그인 필요) | 없음 |
| 펜 선택기 | `feature_editor/lib/src/ui/pen/pen_type_selector.dart` 24행 `isP0` 필터, `editor_strings.dart` 65–69에 P1 이름 있음 [확인] | P1 미노출 | 노출 + 펜별 고급 설정(펜촉 각, 점선 패턴) | 없음 |
| 지우개 필터 | CORE `StrokeFilter { all, highlighterOnly, exceptHighlighter }` | 펜 종류 기준 [확인] | 테이프·요소를 '전체 지우기'·지우개가 지우는지 규칙 필요 | 규칙 또는 추가 |

### 3.2 요소 · 배경 모델

| 항목 | 경로 · 심볼 | 현재 동작 | M5~M7에 필요한 변경 | 계약 |
|---|---|---|---|---|
| 페이지 요소 기반 타입 | `note_core/lib/src/model/stroke.dart` 13–24 `sealed class PageElement implements SyncEntity`(`id`, `pageId`, `bounds`, `createdAt`, `updatedAt`) | 하위 타입은 `Stroke`뿐. 주석: "Shape, TextBox, MathObject and ImageObject are added in M5/M7 (exhaustive switches will then fail to compile on purpose)" [확인] | 도형·텍스트 상자·이미지·수식 하위 타입. sealed라 하위 타입이 **같은 라이브러리**(`stroke.dart` 또는 그 `part` 파일)에 있어야 함 | 추가(다른 패키지에 `PageElement` switch 없음 — `grep` 결과 SYNC 가짜 저장소의 `case Stroke():`는 `SyncEntity` 대상이라 영향 없음) |
| z 순서 | `Stroke.compareOrder(PageElement a, PageElement b)` 55–58 | `createdAt` 오름차순 → id. 이미 `PageElement`를 받음 [확인] | '맨 앞으로/뒤로'가 필요하면 별도 순서 필드가 필요. 획의 `createdAt`은 바꿀 수 없음(점 `t`의 기준, 녹음 동기화) | 깨짐(순서 규칙 변경 시) |
| 엔티티 종류 | `note_core/lib/src/model/sync_entity.dart` `EntityKind` 8종 | folder, note, page, stroke, penPreset, asset, recording, setting [확인] | 요소용 종류(하나 또는 여럿)와 M7 인식 결과 종류 | 깨짐(SYNC·CORE exhaustive switch — 3.11 목록) |
| 페이지 내용 | `note_core/lib/src/session/page_content.dart` `PageContent(page, strokes, revision)`, `strokeById` | 획만. `PageContentChange.added/removed/updated`는 id 집합이라 일반형 [확인] | `elements` 목록·`elementById` | 추가 |
| INK 페이지 내용 | `ink_engine/lib/src/render/ink_page_content.dart` `InkPageContent.fromCore(page:, strokes:, revision:)`(유일한 생성자, v1.1) | 획만. 생성 지점: EDITOR `page_mount.dart`·`page_panel_thumbnail.dart`·`add_page_sheet.dart`, PDF `ink_vectorizer.dart`, INK `testing.dart` [확인] | `elements:` 선택 인자 | 추가 |
| PLAN 데이터 모델 | PLAN 7.2 | `Shape{kind, geometry, strokeStyle, fill, transform}`, `TextBox{rect, content, style}`, `MathObject{rect, latex, color}`, `ImageObject{rect, rotation, assetId}` [문서] | 계약 7.2에 Dart 최종 정의 | 추가 |
| 이미지 배경 | `note_core/lib/src/model/page_background.dart` 197–231 `ImageBackground(assetId, fit: ImageFit{contain, cover, fill}, paperColorArgb)` | JSON `type: 'image'`, `referencedAssets`, 동기화 키 `background`(페이지 필드 하나) [확인]. 쓰는 UI 없음. EDITOR '마지막 페이지와 같게'는 이미지 배경을 빈 페이지로 바꿈(`editor_commands.dart` 474–480) [확인] | 이미지 페이지 추가 흐름, INK 렌더, 썸네일, PDF 내보내기 | 없음(모델은 그대로) |
| 모르는 배경 | `PageBackground.fromJson` 79–100 | 모르는 `type`은 `FormatException` → 페이지 디코드 실패 [확인]. INK에는 `InkBackgroundKind.unknown`이 있지만 "only for hand-made specs" [확인] | 새 배경 종류를 더하면 옛 앱이 그 페이지 기록을 버림(SYNC 게이트 `malformedRemoteData`). 원본 JSON을 보존하는 '모르는 배경'을 둘지 결정 | 추가(둘 경우) |
| INK 배경 사양 | `ink_engine/lib/src/background/background_spec.dart` `InkBackgroundSpec(kind, paperColorArgb, template, assetId, pdfPageIndex)` | `ImageBackground` → `image` + `assetId`, **`fit`은 버려짐** [확인] | `imageFit` 필드 | 추가(7.2.16) |

### 3.3 저장 — DB 스키마 · 마이그레이션

| 항목 | 경로 · 심볼 | 현재 동작 | M5~M7에 필요한 변경 | 계약 |
|---|---|---|---|---|
| 테이블 | `note_core/lib/src/storage/db/tables.dart` | kv, folders, notes, pages, strokes(스타일을 열로 펼침, `points` BLOB, bounds 4열, `recording_id` 색인), pen_presets, assets(`chunk_count`·`has_local_bytes` 로컬), recordings, settings, outbox. 외래 키 없음(고아 허용), 엔티티 테이블마다 `field_versions` [확인] | 요소 테이블(`note_id` 비정규화 — 휴지통 영구 삭제·복사에 필요), 인식 결과·검색 색인 테이블(+ FTS5 가상 테이블) | 없음(내부) |
| DB 스키마 버전 | `kDatabaseSchemaVersion = 1`(`model/sync_entity.dart` 28, 공개 상수), `storage/db/migrations.dart` `kSchemaSteps = {}`·`runSchemaUpgrade`(단계 전체를 한 트랜잭션) [확인] | v2부터 `dart run drift_dev make-migrations`가 `schema_versions.dart`·생성 테스트를 만듦 [문서 02-core 6.15] | 새 테이블 → v2 단계. 옛 앱이 v2 DB를 열면 `NewerSchemaError` → `NoteStoreOpenFailure.newerSchema`로 **앱 전체가 열리지 않음**(웹 롤백·미리보기 채널 전환 때 주의) | 규칙(상수 값) |
| drift 빌드 옵션 | `note_core/build.yaml`(`databases`, `schema_dir`, `test_dir`) | `sqlite_modules` 없음 [확인] | `.drift` 파일로 FTS5를 쓰려면 `sqlite_modules: [fts5]`(drift_dev 2.35.2 `SqlModule.fts5`, 옵션 키 `sqlite_modules` — `options.g.dart` 26·215행) [확인]. Dart 테이블만 쓰고 가상 테이블은 마이그레이션 단계의 `customStatement`로 만들 수도 있음 | 없음 |
| 노트 내용 형식 | `kNoteSchemaVersion = 1`, `migration/note_migrator.dart` `NoteMigrator`(지연 실행, 한 트랜잭션), `kNoteMigrationSteps = {}`, `NoteMigrationContext`(`pages()`, `strokesOf()`, `putPage`, `putStroke`) | 새 버전 노트는 `Note.requiresNewerApp` → 읽기 전용(N-4) [확인] | 요소가 들어오면 컨텍스트에 요소 읽기·쓰기 추가. 노트 형식 버전을 올릴지(옛 앱에서 읽기 전용) 결정 필요(9절 Q3) | 없음(내부, "exposed for tests") |
| 점 코덱 | `stroke_points_codec.dart`, 첫 바이트 = 1 | 디코더는 v1만 받음 [확인] | 펜에 새 채널(예: 배럴 롤)이 필요하면 v2 — 이번 범위는 불필요로 보임 [추측] | 없음 |
| 네이티브 저장 | `storage/connect/connect_native.dart` 14–58 | `nativeDatabasePath`가 없으면 `NoteStoreOpenException(storageUnavailable)`. 에셋·썸네일 블롭은 `newIdbFactoryMemory()`(프로세스 메모리) [확인]. 앱 셸 `defaultNoteStoreConfig`는 웹 경로만 넘김(`infra/app/lib/src/modules/core_module.dart` 216–223), `path_provider` 의존 없음 [확인] | 안드로이드 APK·iOS 실기기 테스트 전에: 파일 DB 경로(`path_provider`), 파일 기반 `BlobStore`. CORE 1.3이 '네이티브 전환 시'로 미뤄 둔 항목 | 없음(CORE 내부 + INFRA 설정). `path_provider`는 7.5 고정표 추가 |

### 3.4 편집 명령 · 되돌리기 · 필드 버전

| 항목 | 경로 · 심볼 | 현재 동작 | M5~M7에 필요한 변경 | 계약 |
|---|---|---|---|---|
| 명령 13종 | `note_core/lib/src/edit/commands.dart` | 획 전용: `AddStrokes`, `RemoveStrokes`, `SplitStrokes`, `RestyleStrokes`, `ClearPage(filter)`. 일반형 이름: `TransformElements(elementIds, transform, scaleStrokeWidth)`. 페이지: `InsertPages`, `DeletePages`, `DuplicatePages`, `MovePages`, `SetPageBackground`, `ResizePages`. 묶음: `CompositeCommand` [확인] | 요소 추가·삭제·수정 명령(예: `AddElements`/`RemoveElements`/`UpdateElements`), `RestyleStrokes`에 대응하는 요소 스타일 변경. 잘라내기 = 복사 + `RemoveStrokes` 1회, '텍스트로 변환' = `CompositeCommand(RemoveStrokes + AddElements)`로 1단계 가능 | 추가(`EditCommand`는 sealed지만 switch는 CORE 해석기에만 있음 — `grep` 확인) |
| 변형 해석 | `edit/command_resolver.dart` 172–187 | `_active(pageId, id)`(획 조회)로 획만 변형, 나머지 id는 조용히 무시 [확인] | 요소도 변형(이미지·텍스트 상자 rect·회전, 도형 꼭짓점). 획만 굵기 배율(`scaleStrokeWidth`) | 없음(동작 확장, 계약 주석 갱신) |
| 페이지 초안 | `edit/page_draft.dart` `PageDraft(id?, size, background, strokes)`, `PageDraft.copyOf(PageContent)` | 복제·삽입이 획만 복사(해석기 348–360) [확인] | `elements` 추가 — `DuplicatePages`·'다른 노트 페이지 복사'가 요소도 복사 | 추가 |
| 되돌리기 | `edit/history.dart`, `applied_edit.dart` `EntityDelta.estimatedBytes`(페이지 256 B, 그 밖 96 B + 점 배열) | 엔티티 단위 before/after [확인] | 새 요소는 96 B 기본으로 충분(이미지 바이트는 에셋이라 히스토리 밖) [추측]. 녹음 생성·삭제는 히스토리 밖으로 두는 것이 자연스러움 | 없음 |
| 필드 버전 | 7.2.10 `EntityFieldVersions`, CORE `storage/entity_diff.dart` `changedJsonKeys` | 로컬 쓰기는 바뀐 JSON 키만 새 HLC. 키 비교는 일반형 [확인] | 새 엔티티의 JSON 키 설계 = 병합 단위 설계(예: 텍스트 상자 `text`와 `rect`를 따로 두면 두 기기의 위치 이동·글 수정이 함께 살아남음) | 추가(엔티티 정의) |
| 옛 앱의 모르는 키 | 7.4.6 "모르는 키 무시" | 옛 앱이 새 선택 키를 모르면 읽을 때 무시 [문서] | 옛 앱이 그 엔티티를 수정해 올리면 스냅숏에 새 키가 없고, SYNC는 "absent key carries the snapshot's base version"(`field_units.dart` 17–20)으로 다룸 → 옛 앱의 수정 HLC가 더 크면 새 키 값이 사라질 수 있음 [추측 — 시나리오 테스트로 확인 필요]. 기존 엔티티에 키를 더할 때 주의 | 규칙 |

### 3.5 시간 정보 — 녹음 동기화

| 항목 | 경로 · 심볼 | 현재 동작 | M6에 필요한 변경 | 계약 |
|---|---|---|---|---|
| 점 시간 | `note_core/lib/src/model/stroke_points.dart` `StrokePoint.t`, `tScale = 10`(0.1 ms), `maxT = 500000` | `Stroke.createdAt`부터의 ms, 조각은 `t`를 유지(재기준 없음) [확인] | 없음. 재생 위치 p에서 점 i가 쓰였는지 = `recordingOffsetMs + t(i) ≤ p` | 없음 |
| 획 시작 시각 | `Stroke.createdAt`(7.2.3: "Wall-clock ms of the first input sample (INK InkCoreServices.nowMillis at pen down)") | 벽시계(CORE `clockProvider`) [확인] | 녹음 위치는 벽시계 차가 아니라 **녹음기 위치**로 정해야 일시정지가 반영됨 [추측 — 설계 판단] | 없음 |
| 녹음 연결 필드 | `Stroke.recordingId`, `recordingOffsetMs`(주석 "ms from recording start to createdAt (point i: + t(i))"), DB 색인 `idx_strokes_recording`, SYNC 병합 묶음 `{recordingId, recordingOffsetMs}`(`field_units.dart` 69–71) [확인] | 이미 저장·동기화 | 없음 |
| INK 전달 | `ink_engine/lib/src/stroke/stroke_meta.dart` `InkStrokeMeta(recordingId, recordingOffsetMs)`, `beginStroke(..., meta:)`; 긴 획 분할(500,000 ms 초과) 때 `offset + Σ⌊t_b⌋`(`stroke_builder.dart` 312–316) [확인] | EDITOR가 meta를 넘기지 않음(`grep InkStrokeMeta feature_editor/lib` 결과 없음) [확인] | EDITOR 펜 다운 때 녹음 중이면 `InkStrokeMeta(recordingId, 녹음기 현재 위치)`. 04-editor 6.x "녹음이 붙으면 `meta:`만 추가한다" [문서] | 없음 |
| 조각·변형 | `Stroke.fragment`·`transformed` | 녹음 필드 유지 [확인] | 없음 | 없음 |
| 복제·붙여넣기 | EDITOR `stroke_clipboard.dart` 83행 `copyWith(id, pageId, createdAt: createdAt + i)`, INK `core_interop.dart` 106행 `duplicateOf` | `createdAt`은 바뀌고 `recordingId·recordingOffsetMs`는 유지 [확인] | 복사본이 원래 녹음 시점을 계속 가리키게 할지, 연결을 끊을지 결정(9절 Q7) | 없음 |
| 노트 복사 | CORE `drift_library_repository.dart` `copyNote` 933–1000, `SyncStore.duplicateNoteForRecovery` | 획의 `recordingId`를 그대로 복사, **녹음 행은 복사하지 않음** [확인] | 녹음도 새 id로 복사(에셋은 해시라 바이트 중복 없음)하거나 연결을 끊음 | 규칙(CORE 동작 계약 C-5 계열) |
| 녹음 엔티티 | `note_core/lib/src/model/asset.dart` 142–244 `Recording(id, noteId, assetId, durationMs, startedAt, createdAt, updatedAt, deletedAt, version)` | 테이블·JSON·SYNC 범위(노트 범위 청크)·휴지통 영구 삭제 포함. **로컬 생성·조회 API 없음**(`repo/`·`session/`에 없음, 원격 적용 경로뿐) [확인]. 제목·진행 상태 없음, `assetId` 필수 | 녹음 저장소 API(목록·생성·이름·삭제), 녹음 중 임시 저장(아래 3.9), 녹음 진행 중을 나타낼 방법 | 추가 |
| 재생 강조 | `InkPageController` 공개 멤버(`updateContent`, 세션 3종, `select`, `hitTest`, `strokeIdsInRect`, `discard*`, `setViewport` …) | 강조·흐리게·시간 필터 API 없음 [확인] | 예: `setPlaybackFocus(recordingId, positionMs)` — 아직 쓰이지 않은 획을 흐리게, 방금 쓴 획을 강조. 기본 래스터 캐시를 다시 만들지 않도록 overlay 층에서 그리는 방식 권장(8절) | 추가 |
| 획 탭 → 재생 | `InkPageController.hitTest(pagePoint, tolerance, filter)` → `InkStroke.source`의 녹음 필드 [확인] | 펜 탭은 점 획을 만든다(EDITOR) | 재생 모드에서 탭을 그리기가 아닌 '그 시점부터 재생'으로 해석(EDITOR 내부) | 없음 |
| 인식 엔진 입력 | `google_mlkit_digital_ink_recognition` 0.16.1 `StrokePoint(x, y, int t)` [확인 보관 파일 `lib/src/digital_ink_recognizer.dart` 113–124] | — | `createdAt + t(i)` 반올림으로 그대로 만들 수 있음. 이름이 `core.StrokePoint`와 같아 import 접두사 필수 | 없음 |

### 3.6 올가미 · 선택 · 메뉴 · 클립보드

| 항목 | 경로 · 심볼 | 현재 동작 | M5·M7에 필요한 변경 | 계약 |
|---|---|---|---|---|
| 변형 계산 | `ink_engine/lib/src/edit/selection_geometry.dart` `SelectionGeometry`(`boundsOf`, `resize`, `move`, `rotate(bounds:, radians:)`, `snapAngle`, `transformedBounds`, `transformedCorners`, `transformedWidth`) [확인] | 회전 = 중심 기준 `Affine2.rotation`, 15° 단위 ±3° 맞춤 [문서 03-ink 2456] | UI만 필요 | 없음 |
| INK 선택 | `ink_engine/lib/src/render/selection.dart` `InkSelection`(`strokeIds`, `bounds`, `setPreviewTransform`, `commitTransform`, `delete`, `duplicate`, `recolor`) [확인] | 획 id만 | 요소를 함께 선택하려면 id 집합을 요소로 넓힘(이름 `strokeIds`). INK 계획 L6: "획 외 요소(도형·텍스트 상자)는 M5에서 EDITOR가 합침" [문서] | 깨짐(이름·의미 변경 시) 또는 추가(별도 집합) |
| 편집 결과 | `InkEditKind` 7종(`addStroke`, `eraseStrokes`, `splitStrokes`, `transformStrokes`, `recolorStrokes`, `deleteStrokes`, `duplicateStrokes`), `InkEdit.toCommand()` [확인] | 획 명령으로만 바뀜 | 요소 변형·삭제·복제를 INK가 다룰지에 따라 값 추가 | 추가 |
| EDITOR 선택 상태 | `feature_editor/lib/src/tools/selection.dart` `EditorSelection(pageId, strokeIds, isDragging)` | 내부 타입 [확인] | 요소 포함 | 없음 |
| 선택 메뉴 | `ui/overlays/selection_menu.dart` | `[복사] [삭제] [선택 해제]` [확인]. 계획: "M5에서 회전·색 변경·잘라내기, M7에서 텍스트/수식 변환이 이 목록에 붙는다"(04-editor 2098) [문서] | 잘라내기·색 변경(EDITOR `ui/color/` 색 선택기 재사용)·굵기·회전 핸들, M7 변환 | 없음(EDITOR 안에서 만들면) |
| 변형 상호작용 | `tools/selection_transform_interaction.dart` | 이동 + 모서리 비율 유지 크기 조절. 회전 핸들 없음 [확인] | 회전 핸들, `snapAngle` 사용 | 없음 |
| 붙여넣기 | `ui/overlays/context_menu.dart`(길게 누르기·우클릭) → `EditorCommands.paste(screenPoint:)` [확인] | 있음 | 없음 | 없음 |
| 클립보드 | `tools/stroke_clipboard.dart` `StrokeClipboardNotifier`(앱 전역, 획만, 반복 붙여넣기 +16 pt, `createdAt + i`) [확인] | 시스템 클립보드 연동 없음 | 요소 포함. M7 '텍스트로 복사'·'LaTeX 복사'는 Flutter `Clipboard.setData`(텍스트). 이미지 붙여넣기(스크린샷)는 Flutter 기본 API로 불가 → 웹 `navigator.clipboard.read()` 또는 플러그인 [추측 — 다른 조사 주제] | 없음 |
| 다른 패키지의 선택 메뉴 항목 | 7.2.17 `EditorExtensions(moreMenuItems, addPageSources, appBarTrailing)`, `EditorMenuContext(noteId, pageIds, currentPageIndex, selectedPageIds, navigateToPage)` | **선택 메뉴 확장 자리와 선택 정보(선택한 획·페이지)가 없음** [확인] | 인식(M7)을 별도 패키지가 맡으면 `selectionMenuItems` + 선택 정보(페이지 id, 획 id, 획 목록 읽기)가 필요 | 추가 |

### 3.7 입력 — EditorExtensions · StylusExtrasSource · GestureSettings · InputRouter

| 항목 | 경로 · 심볼 | 현재 동작 | M5에 필요한 변경 | 계약 |
|---|---|---|---|---|
| 입력 분류 | `feature_editor/lib/src/input/input_router.dart` `_kindOf` 161–167 | `stylus`·`invertedStylus` → 펜, `mouse`, `touch`·`unknown` → 손가락, `trackpad` → 무시. 마우스 보조 버튼만 따로 처리(188행). **펜 버튼 비트·지우개 끝을 보지 않음** [확인] | 펜 다운 때 `buttons & kPrimaryStylusButton` → 설정된 동작(기본 지우개), `invertedStylus` → 지우개 | 없음(내부) |
| 손가락 탭 | 같은 파일 514–523, `InputTargets.tapGesture(fingerCount, centroid)` 주석 "1 = dismiss, 2 = undo, 3 = redo" | 1손가락 = 닫기, 2 = 되돌리기(`twoFingerTapUndo`), 3 = 다시 실행(`threeFingerTapRedo`), 길게 누르기 = 메뉴(`longPressMenu`) [확인] | 탭 → 동작 enum으로 연결 | 없음(내부) |
| 제스처 설정 | `state/settings/editor_settings.dart` 112–170 `GestureSettings(twoFingerTapUndo, threeFingerTapRedo, longPressMenu)`, JSON `twoFingerUndo`·`threeFingerRedo`·`longPressMenu`, synced 키 `editor.settings.synced`의 `gestures` | 주석 "M1: on/off only (contract 7.8). M5 adds per-gesture action mapping." `fromJson`은 모르는 키 무시·빠진 키 기본값 [확인] | 제스처별 동작(끄기 포함) + 펜 버튼·Pencil 더블탭·스퀴즈 동작. 계약 7.2.17이 이 타입을 공개 이름으로 적어 둠 | 추가(새 필드에 기본값) 또는 깨짐(bool을 매핑으로 교체) |
| S펜 버튼 | Flutter 엔진 `AndroidTouchProcessor.java` 338–345: 스타일러스는 `buttons = (getButtonState() >> 4) & 0xF` → `BUTTON_STYLUS_PRIMARY`(0x20) = 0x2 = `kPrimaryStylusButton`(`events.dart` 101). 576행 `TOOL_TYPE_ERASER` → `invertedStylus` [확인] | 플러그인 불필요. 안드로이드 APK에서 실기기 확인 가능. 안드로이드 Chrome 웹에서 `pointerType: pen`의 배럴 버튼 비트가 같은 값으로 오는지는 [추측](웹 엔진 `pointer_binding.dart` `convertButtonToButtons` 경로만 봄) | 없음 |
| Apple Pencil 더블탭 · 스퀴즈 | `/opt/flutter/engine/src/flutter/shell/platform/darwin`에 `UIPencilInteraction` 없음(`FlutterIndirectScribbleDelegate.h`뿐) [확인]. iPad Safari 웹에는 해당 이벤트 API가 없다 [추측 — 알려진 사실이지만 이번에 문서로 확인하지 못함] | 웹·현재 앱에서 받을 수 없음 | Swift 플러그인(`UIPencilInteraction` 델리게이트) → `StylusExtrasSource` 구현. Mac 없이 GitHub Actions macOS로 빌드는 되지만 **실기기 확인은 Apple 계정·TestFlight 이후** | 없음(구현) / 규칙(7.3.3 표에 `stylusExtrasProvider` override 행) |
| 부가 이벤트 인터페이스 | `di/stylus_extras.dart` `sealed StylusExtraEvent`(`StylusDoubleTap`, `StylusSqueeze(hoverPosition)`, `StylusBarrelRoll(angle)`), `StylusExtrasSource(isSupported, events)`, `NoStylusExtras`, `stylusExtrasProvider` | 구독하는 곳 없음. 7.2.17 "EDITOR 4.7 (unchanged, default NoStylusExtras)" [확인] | iPadOS의 사용자 기본 동작(시스템 설정의 '더블탭 동작')과 스퀴즈 단계(시작/끝)를 실을지 결정 | 추가(필드 추가 시) |
| 도구 enum | `tools/tool_state.dart` 8행 `enum EditorTool { pen, eraser, lasso } // M5: shape, text, image, math` | device 키 `editor.toolSelection`에 저장 [확인] | 도형·텍스트·이미지(·수식) 도구 | 없음(내부) |
| 확장 자리 | 7.2.17 `EditorExtensions.appBarTrailing` | "reserved, unused in this scope" [확인] | M6 녹음 버튼·재생 바를 다른 패키지가 맡으면 이 자리 또는 새 자리(재생 바는 하단 띠라 별도 자리 필요) | 추가 |

### 3.8 INK 배경 확장 지점 · 썸네일 · 벡터 내보내기 · PDF 출력 경로

| 항목 | 경로 · 심볼 | 현재 동작 | M5·M7에 필요한 변경 | 계약 |
|---|---|---|---|---|
| 배경 확장 지점 | 7.2.16 `PageBackgroundLayerBuilder(handles, build)`, `PageBackgroundStillRenderer(renderStill)`, `pageBackgroundBuildersProvider`(기본 `[TemplateBackgroundLayerBuilder()]`) | 첫 `handles` 빌더, 없으면 속지 빌더가 종이만(`background/builder_choice.dart`) [확인]. 규칙: "Overridden ONLY through pdf_io's pdfIoOverrides()" | 이미지 배경 빌더(화면 + still). 누가 만들고 어떻게 목록에 넣을지: INK 기본 목록에 넣고 PDF override 목록에도 넣거나, override 규칙을 바꿈 | 규칙 + 추가 |
| 썸네일 | 7.2.16 `InkPageThumbnailRenderer.render` | 이미지 배경은 still 렌더러가 없어 `null`(계약 v1.1). 획만 합성 [확인] | 이미지 배경·요소 합성. 이미지 디코드는 비동기 | 없음(동작 확장) |
| 벡터 내보내기 | `ink_engine/lib/src/export/vector_export.dart` `InkVectorExport.exportStrokes/exportPage` → `InkPageVectors(highlighterGroups, inkShapes, bounds)` | 획만. 형광펜 그룹을 먼저, 그다음 잉크 외곽선 [확인] | 도형은 벡터 경로로 낼 수 있음. 텍스트·이미지·수식은 경로가 아님 → 새 항목 종류. 요소와 형광펜·잉크의 z 순서(층) 규칙 필요 | 추가 |
| PDF 벡터화 | `pdf_io/lib/src/ink_adapter/ink_vectorizer.dart` `InkEngineVectorizer.vectorize(page, strokes, …)`(내부), `export/vectors.dart` `sealed PdfVectorItem { PdfFillItem, PdfStrokeItem }` | 내부 타입 [확인] | 요소 인자 + 이미지·텍스트 항목 | 없음(내부) |
| PDF 합성 명령 | `pdf_io/lib/src/export/compose_plan.dart` `PdfComposeOpcodes`(moveTo, lineTo, cubicTo, close, endObject, paint stride 10), 웹 `web/pdf_io_compose_ext.js`(경로 API만 — `FPDFPageObj_CreateNewPath`·`FPDFPath_*`·색·선 굵기·블렌드) [확인], 네이티브 FFI 해석기(06-pdf T13) | 경로 채우기·선 긋기만 | 이미지 객체·텍스트 객체 명령 추가. 필요한 PDFium 함수는 pdfium.wasm에 있음(4.2절) [확인]. 한글 텍스트는 TTF를 `FPDFText_LoadFont(…, cid)`로 넣어야 함 — 한글 CID 동작은 [추측, 미실행] | 없음(내부, JS·FFI 함께) |
| 이미지 페이지 내보내기 | 06-pdf 6.11 2단계 "이미지(M5 전까지 빈 페이지로) → `PdfComposeBlankPage`", `PdfComposePagePlan` sealed "이미지 페이지 추가 자리"(06-pdf 45) [문서] | 빈 페이지 | 이미지 객체를 페이지 크기에 `fit`대로 배치 | 없음(내부) |
| 글꼴 | `infra/app/pubspec.yaml`에 `fonts:` 없음, `web/index.html`의 한글 글꼴 지정은 HTML 시작 화면용 CSS뿐 [확인]. Flutter 웹 대체 글꼴 기본 주소 `https://fonts.gstatic.com/s/`(`lib/web_ui/lib/src/engine/configuration.dart` 366–368) [확인]. 서비스 워커 없음(7.4.9) [문서] | UI 한글도 대체 글꼴을 내려받아 그림 [추측: 오프라인 첫 실행에서 한글이 두부 글자] | 텍스트 상자 렌더·PDF 글꼴 넣기·수식 글꼴. 글꼴 번들(크기·라이선스) 결정 | 규칙(INFRA 에셋, 7.4.10 크기 예산) |
| 메모리 예산 | 7.4.10 표(INK 외곽선 32 MB·타일 96 MB, PDF 32/64/16 MB, 합계 ≤ 300 MB) | 이미지 디코드 캐시 항목 없음 [확인] | 이미지 요소·이미지 배경 디코드 캐시 예산 | 규칙 |

### 3.9 AssetStore — 이미지 · 오디오 파일

| 항목 | 경로 · 심볼 | 현재 동작 | M5·M6에 필요한 변경 | 계약 |
|---|---|---|---|---|
| 에셋 종류 | `model/asset.dart` `AssetType { pdf, image, audio }`, `Asset(id = sha-256, type, mimeType, size, fileName, storagePath, …)` [확인] | 이미지·오디오 값 이미 있음 | 없음 | 없음 |
| 쓰기 · 읽기 | `assets/asset_store.dart` `put(Uint8List bytes, type:, mimeType:, fileName:)`, `readBytes`, `hasBytes`, `listAssets`, `usage()`, `bytesArrived`, `markUploaded`, `putDownloadedBytes` | 바이트 전체를 한 번에 받고 해시 → 4 MiB 청크로 IndexedDB(`assets/blob_store.dart` 13–14 `kAssetChunkBytes`) [확인]. 이어 쓰기·범위 읽기·삭제 없음. 고아 에셋 정리는 '이후'(7.8) [문서] | 녹음: 해시는 끝나야 알 수 있으므로 녹음 중 조각을 임시로 저장하고(탭이 닫혀도 남게) 끝날 때 `put`하는 별도 자리가 필요. 1시간 AAC 64 kbps ≈ 29 MB [계산 — 추측 범위] | 추가 |
| 동기화 | SYNC `config.dart` `maxAssetUploadBytes` 300 MiB, `maxAssetDownloadBytes` 512 MiB [확인]. Storage 규칙: 크기 ≤ 300 MiB, sha256 메타 일치, 콘텐츠 형식 제한 없음 [문서 07-sync 6.x storage.rules]. 07-sync F-16 행 "`recording` 기록 + 오디오 에셋은 일반 에셋 파이프라인으로 처리" [문서] | 이미지·오디오도 그대로 흐름 | 없음 | 없음 |
| 용량 표시 | `AssetStore.usage()` → `AssetStorageUsage(assetCount, totalBytes, thumbnailBytes)` [확인] | 종류별 합계 없음 | '녹음 용량' 표시가 필요하면 종류별 합계 | 추가 |
| 녹음 삭제 | — | 에셋 삭제 API 없음, GC 이후 | '녹음만 따로 삭제'(F-16)는 `Recording` 소프트 삭제까지는 가능, 바이트 회수는 GC 결정 필요(9절 Q8) | 규칙 |
| 네이티브 | 3.3 '네이티브 저장' 행 | 네이티브 에셋 바이트는 메모리 [확인] | 파일 기반 BlobStore | 없음(내부) |

### 3.10 LIBRARY 검색 · CORE FTS 가능성

| 항목 | 경로 · 심볼 | 현재 동작 | M7에 필요한 변경 | 계약 |
|---|---|---|---|---|
| 검색 API | CORE `repo/library_repository.dart` `searchLibrary(String query, {int limit = 50})` → `LibrarySearchResult(query, folders, notes)`(`repo/library_types.dart` 105–126), `librarySearchProvider` family [확인] | 폴더 이름·노트 제목만. 정규화(`common/text_normalize.dart`: 한글 자모 조합 → 소문자 → 공백 정리) 후 `LIKE '%q%'`(`drift_library_repository.dart` 353–394) [확인] | 페이지 단위 결과(노트 id, 페이지 id, 일치 위치 rect, 발췌)를 결과에 추가 | 추가 |
| 검색 화면 | LIBRARY `ui/content/search_results_view.dart`('폴더 (n)'·'노트 (n)' 묶음), `model/search_match.dart`(제목 안 일치 범위) [확인]. 05-library 45: "검색 결과 화면을 '폴더 · 노트' 묶음 구조로 만들어 묶음 추가가 쉽게" [문서] | 묶음 추가 쉬움 | '손글씨'(·'PDF 텍스트') 묶음 | 없음 |
| 결과 열기 | 7.2.18 `LibraryScreen.onOpenNote: ValueChanged<String>`(노트 id만). 앱 셸 `AppRoutes.note(noteId, {pageId})`·`?page=` 쿼리·`EditorScreen.initialPageId`는 있음(`infra/app/lib/src/routing/app_routes.dart` 23–27) [확인] | 페이지로 바로 열 수 없음. 일치 위치로 스크롤할 인자도 없음 | `onOpenNote`에 페이지 id(+ 일치 rect)를 넘길 방법. `EditorScreen`에 처음 보여 줄 rect | 추가 |
| 변경 알림 | CORE `NoteStore.changes` → `ChangeBatch(origin, changes: EntityChange(kind, id, noteId, pageId, deleted, purged))`(`repo/events.dart` 15–40, 페이지·획·녹음은 noteId 항상, 획은 pageId 항상) [확인] | — | 색인 갱신 예약(획이 바뀐 페이지만 다시 인식)의 입력으로 그대로 씀 | 없음 |
| FTS5 (웹) | `app/web/sqlite3.wasm`(sqlite3 3.8.0, SQLite 3.54.1, sha256 `efd308be…2d37`) | **동작함**: `fts5` 가상 테이블 생성·삽입·`MATCH`·`bm25` [확인 4.1절 실험] | 색인 테이블 + FTS5 가상 테이블(drift 마이그레이션 v2) | 없음(내부) |
| FTS5 (네이티브) | sqlite3 3.8.0 빌드 훅의 미리 빌드 라이브러리 | 리눅스 VM에서 `PRAGMA compile_options` = `ENABLE_FTS5`, trigram 동작 [확인]. 문서상 모든 플랫폼 기본 바이너리가 `SQLITE_ENABLE_FTS5`·`SQLITE_ENABLE_RTREE`(`doc/hook.md` 20–40) [확인 — iOS·안드로이드 바이너리는 실행 미확인] | 없음 | 없음 |
| 한글 토크나이저 | FTS5 `unicode61`, `trigram`. ICU 없음(`compile_options`에 ICU 없음) [확인] | `unicode61`: 공백 단위 낱말, 대소문자 무시(`MEETING` 일치), 접두사 `회의*` 일치, 낱말 중간 `의록` 불일치. `trigram`: `방정식` 일치, 2글자 `정식` MATCH 0건, `LIKE '%정식%'`는 일치(전체 훑기) [확인] | 한국어 낱말은 조사가 붙어 한 토큰이 되므로(`회의록을`) 접두사 질의가 필요. 2글자 질의 대책(LIKE 대체 경로) 필요 | 없음 |
| 인식 엔진 위치 | PLAN F-10: ML Kit Digital Ink(기기 안) [문서]. `google_mlkit_digital_ink_recognition` 0.16.1 플랫폼 = android·ios, README "Web or any other platform is not supported" [확인] | 웹에서 인식 불가 | 웹(iPad Safari)에서 색인을 만들 수 없음 → 인식 결과를 동기화해 웹이 받아 쓰거나, 웹은 서버 경유 엔진을 쓰거나, 웹은 검색만. 한국어 모델 지원 여부는 외부 문서 접근 불가로 **미확인** | 규칙/추가(결과를 엔티티로 둘 경우) |

### 3.11 SYNC 문서 매핑 — 새 엔티티를 넣을 때 필요한 것

원격 구조: Firestore `users/{uid}/changes/{chunkId}` 문서의 `data`(코덱 v1 이진 페이로드)에 여러 기록을 묶는다. 문서 필드(`fmt`, `scope`, `by`, `n`, `bytes`, `maxHlc`, `kind`, `data`, `su`)에 엔티티 종류가 없으므로 **Firestore 규칙·색인은 새 종류와 무관**하다. Storage 규칙도 콘텐츠 형식을 제한하지 않는다. [문서 07-sync 6.4]

| 손댈 곳 | 경로 · 심볼 | 현재 | 새 종류에 필요한 것 |
|---|---|---|---|
| 병합 단위 | `sync_engine/lib/src/model/field_units.dart` `FieldUnits.keysOf` 21–54, `groupsOf` 57–78 | 종류별 JSON 키 목록과 함께 움직일 키 묶음(획: `{recordingId, recordingOffsetMs}`) [확인] | 새 종류의 키 목록·묶음(예: 이미지 `{rect, rotation}`을 한 묶음으로 둘지) |
| 청크 범위 | `model/scopes.dart` `SyncScopes.scopeOf` 13–29 | lib 범위(folder·note·penPreset·setting·asset), 노트 범위(page·stroke·recording) [확인] | 페이지 요소·인식 결과는 노트 범위(`OutboxEntry.noteId` 힌트) |
| 정렬 | `codec/chunk_packer.dart` `kindOrder` 56행 | folder, note, page, penPreset, setting, asset, recording, stroke [확인] | 새 종류의 자리(페이지 뒤) |
| 이진 필드 | `codec/chunk_codec.dart` `blobKeys` 30–32 | 획 `points`만 base64 → 원시 바이트 [확인] | 요소 안에 점 배열(예: 수식의 원본 잉크)을 넣으면 그 키 |
| 종류 디코드 | `ChunkCodec._kind` 201–206 → `FormatException('chunk: unknown kind')`, `engine/download_pipeline.dart` 426–428에서 청크 통째로 `malformedRemoteData` [확인] | 옛 앱은 새 종류가 든 **청크 전체**(같이 실린 획 포함)를 되돌릴 수 없게 건너뜀 | 모르는 종류 기록만 보류(`needsAppUpdate`, 6.6.5 `fmt`와 같은 '나중에 다시 받기')하도록 바꾸거나, 새 종류를 넣을 때 `fmt`를 2로 올림. M4 실연결 **전에** 정하는 것이 쌈(배포된 옛 앱이 없음) |
| 게이트 | `merge/record_gate.dart` 142–153(영구 삭제 노트의 하위 기록: page·recording은 `e.noteId`, stroke는 청크 범위) [확인] | — | 새 종류의 하위 기록 규칙 |
| 페이지 되살림 | `merge/page_resurrection.dart`(삭제된 페이지에 상대가 모르는 획이 있으면 페이지를 되살림) [확인] | 획만 | 요소도 되살림 근거로 볼지 |
| 영구 삭제 보호 | `merge/purge_guard.dart` 104행 `case EntityKind.page || EntityKind.stroke || EntityKind.recording` [확인] | — | 새 노트 하위 종류 추가 |
| 다운로드 특례 | `engine/download_pipeline.dart` 461·729행(lib 범위로 온 획의 페이지→노트 조회) [확인] | 획만 | 같은 특례가 새 종류에 필요한지 |
| 테스트 도구 | `testing/fake_sync_store.dart`(154·164·391 `case Stroke()`), `test_device.dart`, `fake_sync_server.dart`, `canonical_dump.dart`, SYNC T16 'JSON 키 대조' [확인·문서] | — | 새 종류 지원 + 시나리오(요소 동시 편집·삭제 vs 수정·영구 삭제) |
| CORE 쪽 힌트 규칙 | 7.2.10 "noteId is ALWAYS set for page / stroke / recording; pageId ALWAYS for stroke", `EntityChange` 같은 규칙, `storage/write_queue.dart` 519–527 [확인] | — | 새 종류에 같은 규칙(계약 문장 변경 = 규칙) |
| CORE 쪽 고아 규칙 | 7.2.10 v1.2 "remote orphan stroke … listed in the batch of the commit that brings its page row" [문서] | 획만 | 페이지 요소도 같은 규칙 |

CORE 안에서 새 종류마다 손댈 곳(`grep -rln 'EntityKind\.recording'` 결과 + 획 경로): `model/sync_entity.dart`(enum), `model/entity_json.dart`(디코드 switch), `storage/db/tables.dart`, `storage/row_mappers.dart`(129·154·239·297·345·402·437·548행 계열), `storage/drift_sync_store.dart`(546–563 원격 적용·영향 노트, 729 영구 삭제), `storage/write_queue.dart`(519–527 outbox 힌트), `storage/drift_trash_repository.dart`(328–358 영구 삭제), `storage/drift_library_repository.dart`(`copyNote`), `backup/backup_export.dart`(종류 순서), `fake/fake_note_store.dart`(공용 가짜, 7.6 B2 계약), `edit/command_resolver.dart`, `session/`(페이지 로드), `migration/note_migrator.dart`. [확인]

### 3.12 INFRA · 앱 셸

| 항목 | 경로 | 현재 | M5~M7에 필요한 것 | 계약 |
|---|---|---|---|---|
| 권한 | `infra/app/android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist` | 권한 항목 없음(`uses-permission`·`UIBackgroundModes`·`NSMicrophoneUsageDescription` 등 grep 결과 없음) [확인] | M6: 안드로이드 `RECORD_AUDIO`·포그라운드 서비스(마이크 종류)·알림, iOS 마이크 설명·`UIBackgroundModes: audio`. M5: 카메라·사진 설명 [추측 — 플러그인 문서로 확정 필요] | 없음 |
| 앱 의존 | `infra/app/pubspec.yaml` | `sync_engine` 없음(7.1), 플러그인은 pdf_io 경유 `file_picker` 정도 [확인·문서] | 녹음·재생·이미지 선택·인식 플러그인. 이 플러그인들을 어느 패키지가 소유할지(EDITOR 직접 vs 새 패키지) | 규칙(7.1·7.5) |
| 워크플로 | `.github/workflows/android.yml`, `ios-testflight.yml` [확인] | 초안 | 네이티브 저장(3.3)·권한이 들어가야 APK 실사용 가능 | 없음 |
| override 소유표 | 7.3.3 | `stylusExtrasProvider`·녹음·인식 자리 행 없음 [문서] | 새 자리 provider 행 | 규칙 |

---

## 4. 실험 기록

### 4.1 sqlite3.wasm FTS5 (헤드리스 Chrome) · 네이티브 FTS5 (VM)

위치: `/tmp/claude-0/plan57-scratch/fts/` (pubspec: `sqlite3: 3.8.0`, dev `test: 1.31.1`, `dart pub get --offline`). wasm은 `/home/user/wt/infra/app/web/sqlite3.wasm`을 `test/`로 복사(sha256 `efd308be92a34f3aa15f289a37f213b0230fd80888a1364326ee29579d892d37` — 계약 7.4.9 값과 같음).

```dart
// test/fts_probe_test.dart (요지)
final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
final db = sqlite.openInMemory();
db.execute("CREATE VIRTUAL TABLE t USING fts5(body, tokenize='unicode61')");
db.execute("CREATE VIRTUAL TABLE g USING fts5(body, tokenize='trigram')");
// '오늘 회의록 정리 meeting notes', '미분 방정식 풀이', '확률과 통계 Bayes' 삽입 후 MATCH
```

결과(`dart test -p chrome test/fts_probe_test.dart`, 통과):

```text
version Version(libVersion: 3.54.1, sourceId: 2026-10-16 14:45:20 555e07ef…, number: 3054001)
compile_options: []                      ← wasm 빌드는 진단 옵션 목록을 비움(OMIT_COMPILEOPTION_DIAGS로 보임 — 추측)
unicode61 회의록: [오늘 회의록 정리 meeting notes]
unicode61 회의*: [오늘 회의록 정리 meeting notes]
unicode61 의록 (substring): []
unicode61 MEETING: [오늘 회의록 정리 meeting notes]
trigram 방정식: [미분 방정식 풀이]
trigram 정식 (2 chars): []
trigram LIKE %정식%: [미분 방정식 풀이]
bm25: [오늘 회의록 정리 meeting notes]
```

VM(`dart run bin/vm_probe.dart`): `libVersion 3.54.1`, trigram `방정식` 일치, `PRAGMA compile_options` 중 FTS·ICU 관련 = `[ENABLE_FTS5]`.

해석: 웹·네이티브 모두 FTS5를 쓸 수 있다. drift 웹 워커(`drift_worker.js` 2.35.3)는 같은 `sqlite3.wasm`을 불러 쓰므로(CORE `WebStorageConfig.sqlite3WasmPath`) 앱 안에서도 같은 기능이다 [확인 — 워커 경유 실행 자체는 이번에 돌리지 않음].

### 4.2 pdfium.wasm export (pdfrx 2.11.0)

`/tmp/claude-0/plan57-scratch/tools/wasm_exports.py`로 wasm export 절(section id 7)을 파싱했다. 전체 482개 export 중 다음이 있다:

```text
FPDFBitmap_CreateEx  FPDFImageObj_LoadJpegFile  FPDFImageObj_LoadJpegFileInline
FPDFImageObj_SetBitmap  FPDFPageObj_CreateTextObj  FPDFPageObj_NewImageObj
FPDFPageObj_NewTextObj  FPDFText_LoadFont  FPDFText_LoadStandardFont  FPDFText_SetText
```

`pdf_io/web/pdf_io_compose_ext.js`는 지금 이 중 어느 것도 부르지 않는다(경로 함수만 — `grep -c 'FPDFImageObj\|FPDFText_'` = 0). 네이티브(`pdfium_dart` 0.4.1)는 같은 PDFium C API를 쓰므로 같은 함수가 있다고 본다 [추측 — 바인딩 목록은 확인하지 않음].

### 4.3 Flutter 3.47.9 소스 확인

| 질문 | 위치 | 결과 |
|---|---|---|
| S펜 버튼 | `engine/src/flutter/shell/platform/android/io/flutter/embedding/android/AndroidTouchProcessor.java` 338–345, 576 | 스타일러스 `buttons = (getButtonState() >> 4) & 0xF`, `TOOL_TYPE_ERASER` → `INVERTED_STYLUS` |
| 버튼 상수 | `packages/flutter/lib/src/gestures/events.dart` 101, 142 | `kPrimaryStylusButton = kSecondaryButton`, `kSecondaryStylusButton = kTertiaryButton` |
| Pencil 더블탭·스퀴즈 | `engine/src/flutter/shell/platform/darwin` 전체 grep `UIPencilInteraction` | 없음 |
| 배럴 롤 | `events.dart` 필드(`pressure`, `distance`, `size`, `radius*`, `orientation`, `tilt` …) | roll 없음 |
| 웹 대체 글꼴 | `engine/src/flutter/lib/web_ui/lib/src/engine/configuration.dart` 366–368 | 기본 `https://fonts.gstatic.com/s/` |

---

## 5. 영역별 빈틈 한눈에 보기

| 기능 (PLAN) | 이미 있는 자리 | 빠진 것 | 바뀌는 계약 |
|---|---|---|---|
| 올가미 회전·색 변경·잘라내기·붙여넣기 (5.1, M5) | INK `rotate`·`snapAngle`·`recolor`·`duplicate`, CORE `TransformElements`·`RestyleStrokes`, EDITOR 붙여넣기·색 선택기 | 회전 핸들·메뉴 항목·잘라내기(EDITOR 내부) | 없음(획만이면) |
| 텍스트 상자 (5.1) | `PageElement` sealed 자리, `EditorTool` 주석 | 엔티티·테이블·명령·렌더·편집 UI·글꼴·PDF 텍스트 | CORE·INK·SYNC 추가/깨짐, PDF 내부, INFRA 글꼴 |
| 이미지 삽입 · 이미지 페이지 (5.1, F-13) | `ImageBackground`, `AssetType.image`, `AssetCover`, 배경 확장 지점, PDF 이미지 페이지 자리(sealed 계획), PDFium 이미지 함수 | 이미지 요소 엔티티, 이미지 배경 빌더·`fit`, 이미지 선택·디코드·크기 줄이기, 썸네일, PDF 이미지 명령, 디코드 캐시 예산 | CORE·INK 추가, 7.2.16·7.3.3·7.4.10 규칙 |
| 도형 + 자동 보정 (F-11) | INK 형광펜 직선 보정(`stroke/straighten.dart`) 경험, 벡터 경로 타입 | 도형 엔티티(종류·꼭짓점·선·채우기), 인식 알고리즘, 꼭짓점 편집 | CORE·INK 추가 |
| 제스처 사용자 지정 (F-12) | `GestureSettings`(확장 가능한 JSON), `InputRouter` 탭 분기 | 동작 매핑 모델·설정 UI | EDITOR 공개 타입(추가/깨짐) |
| 펜 버튼 (F-12) | `StylusExtrasSource`, 엔진의 S펜 버튼 비트 | 라우터의 버튼 처리, iOS 플러그인, 7.3.3 행 | 규칙(+추가) |
| 추가 펜 5종 (F-03) | `PenTool` 값·기본값·저장·동기화 | INK 프로필·렌더 방식·레이저·테이프 상태, EDITOR 노출 | INK 추가 |
| 녹음·백그라운드·재생 바 (F-16) | `Recording` 엔티티·테이블·동기화, `AssetType.audio`, 에셋 업로드 경로, `appBarTrailing` 자리 | 녹음 저장소 API, 녹음 중 임시 저장, 플러그인·권한, 네이티브 저장, 재생 UI | CORE 추가, 7.1·7.5·7.3.3 규칙 |
| 획별 녹음 시점 · 강조 · 탭 재생 (F-16) | `StrokePoint.t`, `createdAt`, `recordingId/OffsetMs`, `InkStrokeMeta`, `hitTest` | EDITOR의 meta 전달, INK 강조 API, 복사본의 연결 규칙 | INK 추가 |
| 손글씨 → 텍스트 (F-10) | 올가미 결과(획 id·시간 보존), `CompositeCommand` | 인식 엔진 패키지·자리, 선택 메뉴 확장, 결과 편집 UI | EDITOR 추가(선택 메뉴 자리) |
| 손글씨 검색 색인 (5.2, M7) | FTS5 동작 확인, `ChangeBatch`, LIBRARY 묶음 구조, `?page=` 경로 | 색인 테이블·갱신 예약기, 검색 결과 타입, 페이지 열기 콜백, 웹 색인 공급 방법 | CORE·LIBRARY 추가 |
| 수식 인식 → LaTeX → 렌더 (F-14) | 엔진 교체 가능 구조 요구(PLAN), SYNC 범위의 '서버 함수 제외'(07-sync 56) | 수식 엔티티, 엔진 비교 구조, 서버 함수(키 보호), 수식 렌더·PDF 출력 | CORE·INK 추가, 서버(Firebase Functions)는 Firebase 프로젝트 필요 |

---

## 6. 새 요소 엔티티를 넣을 때 영역별 작업 목록 (조사 결과 정리)

1. **CORE**: `PageElement` 하위 타입(같은 라이브러리), `EntityKind` 값, JSON(`toJson`/`fromJson`, 모르는 키 무시), 테이블 + 스키마 v2 단계, `row_mappers`·outbox 힌트(`noteId`·`pageId`)·`EntityChange`·고아 규칙, 명령·해석기(`TransformElements`가 요소도 처리), `PageContent.elements`, `PageDraft.elements`(복제·복사), 휴지통 영구 삭제, `copyNote`·`duplicateNoteForRecovery`, 백업 JSON, `createFakeNoteStore`, `NoteMigrator` 컨텍스트, `api_surface_test`.
2. **INK**: `InkPageContent` 요소 인자, 요소 렌더(층 결정), 공간 색인·적중 판정·올가미 포함, 선택·변형 미리보기, 썸네일 합성, 벡터 내보내기 항목, `bounds` 불변식(요소마다 `bounds` 정의).
3. **EDITOR**: 도구·상호작용(생성·편집 핸들), 선택 메뉴, 클립보드, 명령 매핑, 텍스트 입력(IME — 웹 iPad Safari 한글 조합) [추측: 별도 확인 필요].
4. **PDF**: 벡터화 입력에 요소, 이미지·텍스트 합성 명령(웹 JS 확장 + 네이티브 해석기), 이미지 배경 페이지.
5. **SYNC**: 3.11 표 전부 + 모르는 종류 처리 + 시나리오 테스트.
6. **LIBRARY**: 표지 썸네일이 요소를 그리는지(INK 렌더러가 하면 자동), `AssetCover` 고르기.
7. **INFRA**: 글꼴 에셋, 권한, 플러그인 의존, 7.3.3 override 행, 웹 자산 크기 예산.

---

## 7. 동기화 실연결(M4 앱 연결·로그인)과의 관계 — 판단 재료

- 엔진·가짜 서버·Firebase 어댑터 골격은 1차 범위에 있고, 앱은 `sync_engine`에 의존하지 않는다(7.1). 실연결에는 Firebase 프로젝트(웹 앱 설정값), 앱 의존 추가, `SyncModule` override(7.3.3 M4 행), 로그인 화면(INFRA)이 필요하다. [문서]
- Firebase 프로젝트가 없으므로 이번 라운드에 실연결을 **검증**할 수는 없다. 가짜 서버로 하는 시나리오 테스트는 지금도 가능하다. [문서 + 추측]
- 새 엔티티 종류(요소·인식 결과)를 실연결 **전에** 코덱·병합 규칙에 넣으면, 배포된 옛 앱이 없어 3.11의 '모르는 종류' 문제를 피할 수 있다. 실연결을 먼저 하고 나중에 종류를 더하면 형식 전환 규칙이 반드시 필요하다. [추측 — 순서에 따른 비용 비교]
- M7 수식 인식의 서버 함수(외부 API 키 보호, PLAN F-14)도 Firebase 프로젝트가 있어야 한다. [문서]

---

## 8. 권장안 (조사자 의견 — 설계에서 채택 여부 결정)

R1. **요소는 `EntityKind` 하나(예: `element`)와 테이블 하나로 넣고, 종류는 JSON `type`으로 나눈다.** 도형·텍스트 상자·이미지·수식을 종류마다 `EntityKind`로 만들면 3.11의 SYNC 손댈 곳과 CORE switch가 4배가 된다. 요소 공통 열(`id`, `page_id`, `note_id`, `type`, bounds, `created_at`, `updated_at`, `deleted_at`, `version`, `field_versions`) + 종류별 데이터 JSON. 모르는 `type`은 원본 JSON을 보존하는 `UnknownElement`로 읽어 bounds 자리표시로 그리고 그대로 동기화한다(다음 라운드에 종류가 늘어도 옛 앱이 깨지지 않음).

R2. **SYNC는 실연결 전에 '모르는 종류 기록 = 보류'로 바꾼다.** `ChunkCodec`이 모르는 `kind` 기록을 실패시키지 말고 따로 모아, 6.6.5 `needsAppUpdate`처럼 나중에 다시 받게 한다. 같은 원리로 CORE `PageBackground`의 모르는 `type`도 원본 보존형을 검토한다. 이번 라운드에 요소·인식 결과 종류를 모두 확정해 넣고, 실연결은 그 뒤에 한다.

R3. **INK가 모든 페이지 요소의 렌더·적중 판정·선택 기하를 맡는다.** 획과 이미지를 한 올가미로 함께 옮기려면 선택이 한 곳에 있어야 한다. `InkSelection`을 요소 id 집합으로 넓히고 `TransformElements`를 CORE 해석기에서 요소까지 처리한다(이미 이름이 일반형). 층은 PLAN 7.3(배경 → 형광펜 → 필기·도형·텍스트 → 선택)에 맞춰 '이미지는 형광펜 아래 요소 층, 도형·텍스트·수식은 잉크 층(z = `createdAt`)'을 기본안으로 제안한다. 맨 앞/뒤 정렬은 M5에서 빼고, 필요하면 요소 전용 순서 필드를 나중에 추가한다.

R4. **재생 강조는 overlay 층 API로 넣는다.** `InkPageController`에 녹음 id + 재생 위치를 주면 아직 쓰이지 않은 획을 흐리게(또는 방금 쓴 획을 강조) 그리되, 기본 래스터 타일은 다시 만들지 않는다. 획 탭 재생은 기존 `hitTest`를 쓴다.

R5. **녹음 시점은 녹음기 위치로 정한다.** EDITOR가 펜 다운 때 `InkStrokeMeta(recordingId, 녹음기 현재 위치 ms)`를 넘긴다(일시정지 구간 제외). 녹음 행은 녹음이 끝나 에셋이 생긴 뒤 쓰고, 녹음 중에는 조각을 임시 저장소(CORE가 소유하는 '녹음 초안' 자리)에 계속 써서 탭이 닫혀도 남게 한다. 복제·붙여넣기된 획은 녹음 연결을 유지한다(같은 내용의 복사본이라 원래 시점이 의미 있음) — 9절 Q7에서 확정.

R6. **오디오·인식 플러그인은 새 패키지가 소유하고 소비자 쪽 자리로 연결한다(PDF 방식).** 예: `media_io`(녹음·재생·이미지 선택, 조건부 import로 웹/네이티브 분리), `ink_recognition`(ML Kit 등 엔진 교체 구조). EDITOR·LIBRARY는 자기 패키지에 자리 provider를 두고 INFRA가 7.3.3 표에 행을 더해 override한다. 이렇게 하면 EDITOR 위젯 테스트(웹 포함)가 플러그인에 묶이지 않는다.

R7. **손글씨 인식 결과는 동기화되는 엔티티로 저장하고, 검색 색인(FTS5)은 각 기기에서 그 결과로 다시 만든다.** 웹(iPad Safari)에서는 ML Kit가 돌지 않으므로, 네이티브 기기가 인식한 결과를 받아 웹도 검색할 수 있어야 한다. 결과에는 낱말별 rect와 대상 획 id(또는 획 집합 해시)를 넣어 낡음 판정과 일치 위치 표시에 쓴다. FTS는 `unicode61`(접두사 질의) + 2글자 이하 질의는 일반 테이블 `LIKE`로 대체하는 이중 경로를 기본안으로 둔다. 색인 테이블은 기기 로컬(동기화 안 함)로 둔다.

R8. **S펜 버튼·지우개 끝은 이번 라운드에 구현·실기기 확인하고, Apple Pencil 더블탭·스퀴즈는 동작 매핑과 가짜 `StylusExtrasSource` 테스트까지만 한다.** iOS 플러그인 코드는 초안으로 두고, 확인은 Apple 계정·TestFlight 이후로 남긴다.

R9. **`GestureSettings`는 기존 bool 키를 유지한 채 동작 매핑 키를 추가한다.** 예: `actions: {"twoFingerTap": "undo", "penButton": "eraserHold", "pencilDoubleTap": "toggleEraser", …}`. 옛 키는 읽기 호환용으로 남겨 옛 앱과 새 앱이 함께 있어도 해석이 일관되게 한다(계약은 '추가').

R10. **안드로이드 APK 실사용을 위해 네이티브 저장을 이번 라운드 선행 작업으로 넣는다.** CORE 파일 기반 BlobStore + INFRA `path_provider`로 `nativeDatabasePath`. M6 백그라운드 녹음과 M7 ML Kit는 네이티브에서만 검증할 수 있으므로 이것 없이는 완료 판정을 할 수 없다.

R11. **한글 글꼴 하나를 앱 에셋으로 번들한다(텍스트 상자 렌더 + PDF 글꼴 넣기 공용).** 크기 예산(웹 첫 로드)과 라이선스(OFL 계열)를 INFRA 예산표에 올린다. PDF는 텍스트 객체(검색 가능)를 기본으로, 실패하면 래스터 대체로 낸다. 수식은 우선 래스터로 PDF에 넣는다 [추측: 수식 글꼴 넣기 비용이 큼].

R12. **이미지 배경 빌더는 INK가 만들고 기본 목록에 넣는다.** `pageBackgroundBuildersProvider` 기본값 = `[ImageBackgroundLayerBuilder(...), TemplateBackgroundLayerBuilder()]`, `pdfIoOverrides()`는 PDF 빌더를 앞에 더한 목록을 돌려주도록 7.2.16·7.2.19·7.3.3 문장을 고친다. `InkBackgroundSpec`에 `imageFit`을 더한다. 이미지 바이트는 `core.assetStoreProvider`로 읽는다(INK는 이미 `riverpod`와 CORE provider를 씀).

---

## 9. 열린 질문 (사용자 또는 총괄이 정할 것)

| # | 질문 | 왜 필요한가 | 조사자 기본안 |
|---|---|---|---|
| Q1 | 동기화 실연결(M4)을 이번 라운드에 넣는가? | Firebase 프로젝트가 아직 없어 실연결 검증이 불가. 새 엔티티 종류를 먼저 넣고 연결하면 형식 전환 문제가 없다 | 넣지 않음. 단, SYNC 코덱·병합에 새 종류와 '모르는 종류 보류'를 이번에 넣는다(R2) |
| Q2 | 요소를 `EntityKind` 하나로 묶는가, 종류마다 나누는가? | SYNC·CORE 변경량, 옛 앱 호환 | 하나(R1) |
| Q3 | 요소가 든 노트의 `schemaVersion`을 올려 옛 앱에서 읽기 전용으로 만드는가? | 옛 앱이 요소를 모른 채 '페이지 복제'·'전체 지우기'를 하면 요소가 빠진다 | 올리지 않음(단일 사용자가 모든 기기를 갱신). 대신 옛 앱은 요소 기록을 보류(R2) |
| Q4 | 이미지·도형·텍스트의 층 위치와 '맨 앞/뒤로' 지원 여부 | INK 캐시 구조와 z 순서 규칙(`createdAt`)이 정해짐 | 이미지 = 형광펜 아래, 그 밖 = 잉크 층, 정렬 기능은 M5 제외(R3) |
| Q5 | 암기 테이프의 드러냄 상태를 저장하는가(저장 안 함 / 기기 로컬 / 동기화), 썸네일·PDF에서는 가린 채인가? | INK 상태 위치와 내보내기 결과 | 저장 안 함(열 때마다 가림), 썸네일·PDF는 가린 채 |
| Q6 | 레이저 포인터 자취 지속 시간, 여러 페이지에 걸친 동작 | E-3(저장 안 함)만 정해져 있음 | 1.5초 뒤 사라짐, 현재 페이지에만 [추측 값] |
| Q7 | 복제·붙여넣기·노트 복사된 획이 원래 녹음 연결을 유지하는가? 노트 복사 때 녹음도 복사하는가? | 지금은 획은 연결 유지, 녹음 행은 복사 안 됨(다른 노트의 녹음을 가리킴) | 획은 유지, 노트 복사 때 녹음 행도 새 id로 복사(에셋 공유) |
| Q8 | '녹음만 따로 삭제' 때 오디오 바이트를 회수하는가(에셋 GC 범위)? | GC는 7.8에서 '이후'. 오디오는 커서 저장 공간 압박이 큼 | 이번에는 소프트 삭제만, 로컬 GC는 '업로드 전·참조 0' 에셋부터 검토 |
| Q9 | 손글씨 인식 결과를 동기화하는가? 웹에서 인식을 어떻게 하는가(안 함 / 서버 경유)? | ML Kit는 웹 불가. 웹에서 검색하려면 결과가 동기화돼야 함 | 결과 동기화, 웹은 인식하지 않고 받은 결과로만 검색(R7) |
| Q10 | ML Kit 한국어 모델이 실제로 쓸 만한가? | 외부 문서 접근이 막혀 이번에 확인 못 함. 실기기(안드로이드 APK)에서만 판정 가능 | 안드로이드 APK 실험 작업을 M7 첫 작업으로 |
| Q11 | 녹음·인식·이미지 선택 플러그인을 어느 패키지가 소유하는가? | 7.1 의존 표·7.3.3 override 표·테스트 구조 | 새 패키지 + 소비자 쪽 자리(R6) |
| Q12 | 한글 글꼴 번들 크기·종류(웹 첫 로드 예산) | 텍스트 상자·PDF 텍스트·오프라인 표시 | 한글 글꼴 1종(부분 집합 검토), INFRA 예산표 갱신(R11) |
| Q13 | 네이티브 저장(파일 DB·파일 블롭)을 이번 라운드에 넣는가? | 안드로이드 APK·M6·M7 실기기 검증의 선행 조건 | 넣음(R10) |
| Q14 | Apple Pencil 더블탭 시 iPadOS 시스템 설정(사용자 기본 동작)을 따를 것인가, 앱 설정만 쓸 것인가? | `StylusDoubleTap`에 기본 동작 필드를 둘지 | 시스템 설정 우선(앱 설정은 '시스템 따름' 기본) [추측 — Apple 지침 확인 필요] |

---

## 10. 확인한 버전

| 패키지 · 도구 | 버전 | 확인 방법 | 비고 |
|---|---|---|---|
| sqlite3 (Dart) | 3.8.0 | pub 캐시 `sqlite3-3.8.0`, pub.dev API 버전 목록에 존재. scratch에서 `dart pub get --offline` 해석 | 최신은 3.9.0(2026-11-05 공개 — 오늘). 채택하지 않음 |
| sqlite3.wasm | sqlite3-3.8.0 릴리스, SQLite 3.54.1 (`sourceId 2026-10-16 … 555e07ef`) | sha256 대조 + Chrome에서 `sqlite.version` 출력 | FTS5·trigram·unicode61 동작 |
| 네이티브 SQLite (빌드 훅 미리 빌드) | 3.54.1 | VM `dart run` 출력, `PRAGMA compile_options`에 `ENABLE_FTS5` | iOS·안드로이드 바이너리는 `doc/hook.md` 문서만 |
| drift | 2.35.3 | pub.dev API(최신 = 2.35.3, 2026-10-23) | 계약 고정값 그대로 |
| drift_dev | 2.35.2 | pub 캐시 소스 `options.dart`·`options.g.dart` | `sqlite_modules: [fts5]` 지원 |
| pdfrx | 2.11.0 | pub.dev API(최신 = 2.11.0, 2026-10-29) + 캐시 `assets/pdfium.wasm` export 파싱 | 이미지·텍스트 객체 함수 export 확인 |
| Flutter / Dart | 3.47.9 / 3.13.7 (`c197ca5199e9`, 2026-10-29) | `/opt/flutter` git 로그, 엔진 소스 경로 | S펜 버튼 매핑 있음, `UIPencilInteraction` 없음 |
| google_mlkit_digital_ink_recognition | 0.16.1 (2026-08-17, sdk ^3.12.0, flutter >=3.44.0, android·ios) | pub.dev API + 보관 파일 README·소스, 안드로이드 `com.google.mlkit:digital-ink-recognition:19.0.0` | 웹 미지원(README). 참고용 — 채택은 M7 조사가 결정 |
| record | 7.1.2 (2026-10-09, sdk ^3.12.0, flutter >=3.44.0, android·ios·web·windows·macos·linux) | pub.dev API | 참고용 — M6 조사가 결정 |
| image_picker | 1.2.4 (2026-10-06, sdk ^3.11.0, web 포함) | pub.dev API | 참고용 |
| flutter_math_fork | 0.7.4 (2025-05-21, 플러그인 아님) | pub.dev API | 참고용 |
| super_clipboard | 0.9.1 (2025-06-11) | pub.dev API | 참고용 |
| path_provider | 2.1.6 (2026-06-15, android·ios·linux·macos·windows — 웹 없음) | pub.dev API | 네이티브 저장(R10)에 필요, 웹에서는 쓰지 않음(조건부 import) |

임시 작업 위치: `/tmp/claude-0/plan57-scratch/`(`fts/`, `tools/wasm_exports.py`, `dl/mlkit/`, `*.json`). 작업 트리·`/home/user/noteapp`은 수정하지 않았다.
