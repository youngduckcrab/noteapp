# 02 · CORE — 문서 모델 · 저장 · 되돌리기 · 색인 (2차 라운드 M5·M6·M7)

> 상태: **승인 · 계약 v2.5** (2026-11-06 — v2.4(C24-01·02)는 CORE 시그니처·인용 문장 변화 없음. v2.5 C25-01(**CP-18 승인** — V10의 5,000쪽 합성 색인 질의 예산)을 6.19 PF-3·PF-4·PF-10 행, 6.10.7, 10장 #1, 12.1 CP-18 판정 칸에 반영했다. C25-02~04는 INK·EDITOR 몫 — CORE 변화 없음) · 이전: **승인 · 계약 v2.3** (2026-11-06 동시 개발 착수 때 인용 맞춤 — C22-09: 계약 v2.2가 바꾼 문장(R-3·M-4·7.2.7 v1 사본 문단·`dev_tools.dart` 블록)은 최종 승인 때 이미 맞췄고 12.1 CP-16·17 판정 열을 고쳤다. v2.3(C23-01~07)은 CORE 시그니처·인용 문장 변화 없음. 5.8 표를 기반 단계 결과(실제 타입·커밋)로 바꿨다. 00-review '최종 승인' CORE-F1~F4 처리는 진행 기록 '## 2차' > '### 동시 개발') · 이전: **승인** (최종 승인 2026-11-05 · 통합 계약 **v2.2** — [00-review.md '최종 승인'](00-review.md#최종-승인), 이 영역의 개발 중 반영 항목은 그 절의 '영역별 개발 중 반영' 표) · 승인한 판본: 수정 1회차. 이 계획서와 계약이 다르면 계약이 우선이다. 이전 상태: **수정 1회차** (통합 계약 **v2.1** 기준 — 총괄 검토 [00-review.md](00-review.md) 3.2 CORE-M1~M13과 대리 검토 [reviews/core.md](reviews/core.md) 반영, 13절에 항목별 반영 내역)
>
> 동시 개발 중 고친 곳 (2026-11-06, CORE 보완 2.1): 4.11 `dev_tools.dart` 줄과 12.1 CP-9 행에 `objectsPerPage` 구현(T37로 — 8.2 표에 작업이 없었음).
>
> 동시 개발 중 고친 곳 (2026-11-06, CORE 보완 1.1 — 독립 검토 미비점 3·4): 6.19 PF-10 질의 예산을 첫 측정으로 정한 값(≤ 50 ms)으로, 6.10.7 끝 문단, 6.19 PF-3·PF-4 행에 CP-18 표시, 12.1 **CP-18**(V10 질의 예산 — 판정 대기) 추가. 승인 전까지 PF-3·PF-4는 원문(V10)으로 판정한다(7.4.9). (보완 1.4) CP-18 제안의 '원문 예산을 지키는 질의' 경계를 후보 300개(1글자 LIKE 600개) 미만 → **100개 미만**으로 — load < 4에서도 136개 질의 3.3~5.2 ms, 576개 LIKE 14.2~15.8 ms로 예산 경계였다. (v2.5, 2026-11-06) **CP-18 승인(C25-01)** — 6.19 PF-3·PF-4 행이 v2.5 예산(후보 100개 미만 ≤ 5 ms·1글자 LIKE ≤ 15 ms, 그 밖 ≤ 50 ms)이고 `search_perf_test`가 질의마다 센 후보 수로 예산을 고른다('V10 as written'·'CP-18 as proposed' 두 시험을 하나로). 6.10.7 질의 예산 문단, 6.19 PF-10 행(같은 50 ms임을 적음), 10장 #1, 12.1 CP-18 판정 칸을 고쳤다.
>
> 작성 2026-11-05 · 수정 2026-11-05 · 기준: [00-overview.md 7장 '통합 계약 v2.1'](00-overview.md)(변경 이력 7.9 C21-01~35 중 CORE 몫: C21-04·05·06·07·08·09·10·11·19·23·25·29·30·32·33) — **이 문서와 7장이 다르면 7장이 우선**한다. 7장이 덮어쓰지 않은 곳은 1차 계약 v1.5(1차 [00-overview.md](../00-overview.md) 7장 — 시그니처는 v1.4와 같음)가 그대로 유효하다.
> 이어받는 1차 계획서: [1차 02-core.md](../02-core.md)(승인, 계약 v1.4 — 바탕 코드 작업 트리 `/home/user/wt/core/docs/plans/02-core.md`). 이 문서는 그 위에 **더하고 바꾸는 것만** 적는다. 1차 계획서의 절은 언제나 **'1차 6.x'**, 1차 계약의 절은 **'1차 7.x'**, 이 라운드 계약의 절은 **'7.x'**로 적는다.
> 소유 경로: `packages/note_core/` (순수 Dart, Flutter SDK 의존 없음) · 바탕 코드(v2.1, CD2-01): **1차 통합 HEAD** `/home/user/noteapp` 브랜치 `claude/note-app-planning-bk29xb` `18c5ae5`(`packages/note_core`는 영역 끝 `4336967` + 통합 커밋 `c4966ce` — `openTestNoteStore`의 drift 다중 DB 경고 끔·파일 DB 롤백 저널 고정, 시그니처 변화 없음. VM 시험 619개·Chrome 47개 통과) · 2차 작업 트리: `/home/user/wt2/core`(`area2/core`)
> 조사: [01-hooks](research/01-hooks.md) 3.2~3.5·3.9~3.11·4.1 · [02-audio-stylus](research/02-audio-stylus.md) 4.3·6 · [03-recognition](research/03-recognition.md) 9 · [04-native](research/04-native.md) 3·7 · 판정 [judgement.md](drafts/judgement.md)

이 문서만 보고 별도 작업 트리에서 CORE 2차 몫을 구현할 수 있게 쓴다. 코드 블록 읽는 법:

- 머리 주석이 `// 계약 v2.1 7.x.x 원문`인 블록은 7장(v2.1)의 Dart 정의·표·문단을 **글자 그대로** 옮긴 것이다(7장 머리말 '영역 계획서 4·5절은 이 장의 Dart 정의를 그대로 복사' — 이번 수정에서 스크립트로 7장 줄을 그대로 다시 붙였다). 고치지 않는다.
- 머리 주석이 `// CORE 확정 세부`인 블록은 7장이 '본문 생략'(`/* … */`, `// … as Stroke`)으로 둔 멤버, 이름만 정한 기본값(`UnsupportedAudioRecorder` 등), 그리고 (v2.1) 7장이 '02-core 4.x·6.x가 단일 출처'라고 가리킨 세부다. 계약의 이름·시그니처와 충돌하지 않는 **추가**만 담았다. v2.0의 CP-1~CP-15는 v2.1에 모두 반영됐고(12.1), 새 제안은 CP-16·CP-17이다.
- 7장과 다르게 해야 한다고 본 곳은 바꾸지 않고 12.1에 제안했다. 승인 전까지는 7장 원문대로 구현한다(7.4.9). (v2.1) CP-1(새 명령의 생성자 형태)은 승인되어 원문이 이름 있는 인자·`List`가 됐다.
- 줄 번호·파일 경로 인용은 1차 통합 HEAD(`/home/user/noteapp`) 기준이다 — `packages/note_core`는 1차 작업 트리(`/home/user/wt/core`)와 `testing_vm.dart`·`test/testing/` 두 곳만 다르다(위 `c4966ce`). 다른 영역 파일의 줄 번호는 기반 단계 시작 때 다시 확인한다(CD2-01).

---

## 1. 목적과 범위

### 1.1 목적

CORE는 2차에서도 다른 영역이 함께 쓰는 **데이터의 단일 출처**다(7.2.0 '공유 데이터 타입은 CORE'). 2차에 새로 정의·저장하는 것은 다음 여섯 묶음이다.

1. **페이지 객체**(M5·M7): 도형·텍스트 상자·이미지·수식과, 새 앱이 쓴 모르는 종류를 원본째 보존하는 `UnknownObject` — 모델·JSON·`bounds`·DB·편집 명령·되돌리기·복사.
2. **녹음**(M6): 로컬 녹음 생성·목록·이름·삭제 저장소, 녹음 중 조각을 탭이 닫혀도 남게 하는 초안 저장소(웹 조각 저장 P-A — D13), 녹음·재생 포트와 '지원 안 함' 기본값. **녹음·재생 구현은 PDF(`media_io`)**가 한다.
3. **손글씨 인식 결과**(M7): 페이지마다 하나인 동기화 엔티티(`hw_<pageId>`)와 낡은 페이지 조회. **인식 엔진·색인기는 LIBRARY(`ink_recognition`)**가 한다.
4. **검색 색인**(M7, 1차 7.8 미룬 'PDF 전역 검색'): FTS5 음절 바이그램 색인, 정규화 함수 하나(`SearchText`), PDF용 작성기, 페이지 단위 검색 결과.
5. **이미지 가져오기 타입·에셋 용량**(M5·M6): 가져오기 결과·한도 타입, 종류별 에셋 용량. **선택·디코드·재인코딩은 `media_io`**가 한다.
6. **네이티브 저장**(공통-1): 파일 DB + 파일 블롭. 안드로이드 APK·iOS 네이티브에서 노트가 남게 하는 선행 조건이다.

### 1.2 이번 범위

등급은 개요 3.4(P-A = 2차 완료 조건, P-B = 미뤄도 2차 완료, P-C = 여유가 있으면)다. 작업 번호는 8장.

| 구분 | 내용 | 등급 | 계약 | 작업 |
|---|---|---|---|---|
| 기반 단계 R2-B2 | (v2.1) B2-0 V7 고정 자료 → **B2-α** 7.2.2~7.2.7의 공개 선언 전부 + `api_surface_test` v2(해시 알림) → **B2-β** 동작 구현(JSON·골든 먼저 → 기하·값 타입 → 해석기·세션 → 가짜 v2·`testing.dart` v2.1·`testing_web.dart`). DB v2는 동시 개발 몫 | P-A | 7.6 | T25a, T22(α), T20a·T20b·T21·T23a·T23b(β) |
| 페이지 객체 모델 | `PagePoint`·`ElementFrame`, `PageObject`(sealed) + `ShapeObject`·`TextBoxObject`·`ImageObject`·`MathObject`·`UnknownObject`(`referencedAssets`), 스타일·기하·템플릿, `PageObjectLimits`, JSON(비정규화·키 항상), `bounds`(K-6의 기준), (v2.1) **`transformed(m, {scaleWidth})` 단일 변형 규칙** | P-A | 7.2.2 | T20a·T20b |
| 편집 명령 | `AddObjects`·`UpdateObjects`·`RemoveElements`(이름 있는 인자·`List` — CP-1), `TransformElements` 의미 확장(+ 캘리그래피 각 C2-38), `ClearPage.includeObjects`(이름 있는 선택 인자), `PageDraft.objects`, `PageContent.objects`·`elementById`, 되돌리기·필드 버전(C-11) | P-A | 7.2.3 | T22, T20b, T23a, T27 |
| 엔티티 종류 | `EntityKind.pageObject`·`handwriting`(R2-B7a SYNC·R2-B2i INFRA와 한 묶음 병합 — 바탕 = B2-α 해시) | P-A | 7.2.2, 7.0.2 | T22 |
| 녹음 | `Recording.title`(키 항상), `RecordingRepository`(`createRecording` 멱등), `RecordingDraftStore`·`RecordingDraft`(웹 meta·되살림·조각 0 초안), 오디오 포트 `AudioRecorderService`·`AudioPlaybackService` + `Unsupported*` 기본값, provider, R-6(노트 복사 때 녹음 복사)·R-7·R-8 | P-A | 7.2.4 | T21, T22, T30, T31, T29 |
| 손글씨 결과 | `HandwritingLine`·`HandwritingText`(결정적 id `hw_<pageId>`, `sourceRevOf`, `isRecognitionInput`, `copyWith`), `HandwritingRepository`(`stalePages`(페이지 순서)·(v2.1) **`update`**(한 쓰기 트랜잭션 병합 — G-4)·**`notesWithStalePages`**) | P-A(색인의 입력) | 7.2.5 | T21, T32 |
| 검색 색인 | `SearchText`(정규화·`normalizeMapped`·바이그램·질의 — 제목 검색과 통합), `SearchIndexWriter`(`sourceRevOf`·`sourceRevs`·`replaceUnits`(빈 목록 = 소유자 유지)·`removeOwner`), `SearchIndex.searchPages`(후보 2,000 최근 우선·대표 결과만 원문·사각형)·`status`·`rebuild`, `LibrarySearchResult.pages`, C-13, (v2.1) **PDF 글자 상자는 SQLite 밖**·크기 목표 500쪽 ≤ 12 MB | P-A | 7.2.5, 7.4.5 | T21, T33a, T33b, T34 |
| 이미지·에셋 | `ImageImportSource`·`ImportedImage`·`ImageImportLimits`, `AssetStorageUsage.bytesByType` | P-A | 7.2.6 | T21 |
| 저장 형식 | DB 스키마 v2(`kDatabaseSchemaVersion` 2), 마이그레이션 한 단계, (v2.1) **업그레이드 직전 v1 사본**·개발자 메뉴 API(CP-17), 1차 v1 DB 고정 자료로 VM·Chrome 시험(V7 — 사본 해시 포함, C-14), JSON 골든 | P-A | 7.2.7 | T24, T25a, T25b |
| 변경 기록·동기화 창구 | 새 두 종류의 outbox 힌트(`noteId`·`pageId` 항상)·`EntityChange`·원격 고아 객체, `applyRemote`·`readVersioned`·`pendingChanges`, 원격 객체의 `content_rev` | P-A | 7.2.8, C2-13 | T26, T28 |
| 복사·휴지통·백업 | `copyNote`·`duplicateNoteForRecovery`·영구 삭제·`RemotePurge`·`exportBackupJson`이 객체·녹음·손글씨 결과를 함께 다룸 | P-A | 7.2.3, R-6, 3.2 | T29 |
| 네이티브 저장 | `NoteStoreConfig.nativeAssetDirectoryPath`, 파일 블롭 저장소(청크 4 MiB 파일, 루트 디렉터리는 CORE가 만듦), `deleteLocalNoteData` 네이티브 | P-A(공통-1) | 7.2.6 | T35 |
| 공용 가짜 v2.1 | `createFakeNoteStore()` v2(객체·녹음·초안·손글씨(`update`)·메모리 검색 — 실제와 같은 판정·순서), `PageObjectFixtures`, `FakeAudioRecorder`(`UnsupportedError`·초안·`pendingDrafts` 제외 규칙·`abandon`), `FakeAudioPlayback`(`calls`), **`testing_web.dart`**(`openWebTestNoteStore`·`deleteWebTestNoteStore`) | P-A(기반 단계) | 7.6 | T23b |
| provider | `audioRecorderServiceProvider`·`audioPlaybackServiceProvider`·`recordingRepositoryProvider`·`noteRecordingsProvider`·`handwritingRepositoryProvider`·`searchIndexProvider` | P-A | 7.2.4, 7.2.5 | T22, T36 |
| 이정표 커밋 | B2-α·B2-β JSON·T24·T26~T33 커밋 해시를 진행 기록 표에 고정(8.5) | P-A | 7.6.2 | 전 작업 |
| 성능·문서 | 2차 예산 시험(6.19 PF-1~PF-11 — 실제 모양 500쪽 색인 크기·다시 열기 시간, 10만 획 첫 따라잡기 포함), README 2차 사용 예 | P-A(예산)·P-C(문서 확장 예제) | 7.7 V10 | T37 |

### 1.3 이후 범위 (이번에는 자리만 두거나 하지 않음)

- 객체 z 순서 필드·'맨 앞/뒤로'(D2) — `Stroke.compareOrder`(createdAt → id)를 그대로 쓴다.
- 이미지 자르기·투명도, 텍스트 부분 서식·목록·표 — 모르는 JSON 키는 읽을 때 무시하는 1차 규칙이라 나중에 키만 더하면 된다.
- 다른 노트의 페이지 복사 UI(U23) — `PageDraft.objects`가 객체까지 담으므로 데이터 쪽은 이번에 끝난다.
- 녹음 바이트 회수(고아 에셋 GC — U13), tombstone 정리, 다중 탭 리더 선출, 백업 **복원**과 v1 사본 **되돌리기**(사본은 만들고 내보내기·지우기까지만 — 6.12.4).
- 녹음 시계 보정 필드(R-3 — 실기기 A-5 실측 뒤 판단, 계약 변경).
- 웹에서 손글씨 인식 결과 만들기(서버 경유 OCR — U5). 웹은 동기화된 결과로만 검색한다(실연결 뒤).
- 검색 색인 설정(PDF 색인 끄기·색인 크기 상한 설정) — (v2.1) 크기는 목표(500쪽 ≤ 12 MB·다시 열기 +300 ms — 7.4.5)를 두고 재지만, 사용자 설정은 이번에 없다(12.2 Q7 답).
- `DuplicatePages`로 복제된 페이지의 손글씨 결과 복제(6.14.3 — 이번에는 노트 복사만 결과를 옮긴다).

### 1.4 제외 (다른 영역 책임)

| 항목 | 책임 영역 |
|---|---|
| 객체 렌더·적중 판정·선택 기하·층(L-1)·도형 보정 미리보기, 텍스트 레이아웃 높이 측정(`InkTextLayout.measure`), 수식 검증·래스터(`InkMathRenderer`), 새 펜 extras 키(`InkStyleExtras`) | INK |
| 객체 도구·핸들·IME, 명령 매핑(7.2.3 표), 녹음 시점 연결(R-1·E-5), 텍스트 편집 세션 1단계(E-6) | EDITOR |
| 녹음·재생 구현, 녹음 시계(R-2·7.4.8), 웹 MediaRecorder 조각 저장(M-2)·복구 시점, 이미지 선택·디코드·재인코딩(M-3), PDF 텍스트 추출·`PdfSearchIndexer`, `PdfTextNormalizer`와의 동치 시험(C2-27) | PDF(`pdf_io`·`media_io`) |
| 인식 엔진·줄 나누기·`HandwritingIndexer`(G-2 유휴 규칙), 변환 UI, 검색 결과 화면(L-1) | LIBRARY(`feature_library`·`ink_recognition`) |
| 새 종류의 병합 단위·청크 범위·게이트·영구 삭제 보호·페이지 되살림, 모르는 종류 보류(S-13), JSON 키 대조(T16) | SYNC |
| 네이티브 경로 결정(`path_provider`), `CountingNoteStore` 위임(R2-B2i), 웹 자산(`sqlite3.wasm`·`drift_worker.js`), 앱 연결·기능 스위치(`AppFeatures`), 백업 안내서 | INFRA |

### 1.5 1차 대비 바뀌는 CORE 공개 표면 (7.0.1 중 CORE 행)

| 7.0.1 | 변경 | 분류 | 이 문서 |
|---|---|---|---|
| C2-03 | `PageElement` 아래 `PageObject`(sealed) + 5종(같은 라이브러리 `part`), `PagePoint`·`ElementFrame` | 깨짐(형식상 — CORE 내부 switch만) | 4.1~4.3, 6.2 |
| C2-05 | `EntityKind`에 `pageObject`·`handwriting` | 깨짐((v2.1 정정) SYNC 기본 갈래 없는 switch 4곳 + `kindOrder` + 시험 `fixtureJson`) | 4.2, 8.1 묶음 병합 |
| C2-06 | `Recording.title`, `copyWith(title:, clearTitle:)` | 추가 | 4.5, 6.6 |
| C2-07 | `kDatabaseSchemaVersion` 1 → 2, `kNoteSchemaVersion` 1 유지 | 규칙 | 6.11, 6.12 (T24 — 동시 개발) |
| C2-08·09 | 명령 3종(이름 있는 인자·`List` — CP-1), `TransformElements` 의미 확장(`PageObject.transformed` 단일 규칙), `ClearPage.includeObjects`(이름 있는 선택 인자), `PageDraft.objects` | 깨짐(형식상)·추가·규칙 | 4.4, 6.2.5, 6.4 |
| C2-10 | `PageContent.objects`·`objectById`·`elementById`·`objectCount`, `PageContentChange` id 의미 확장 | 추가·규칙 | 4.4, 6.5 |
| C2-11 | `LibrarySearchResult.pages`·`pagesTruncated`, `searchLibrary`가 `pages`를 채움 | 추가·규칙 | 4.6, 6.10 |
| C2-12 | `RecordingRepository`·`RecordingDraftStore`·`HandwritingRepository`(v2.1 `update`·`notesWithStalePages`)·`SearchIndex`(`SearchIndexWriter`), 오디오 포트 | 추가 | 4.5, 4.6, 6.9 |
| C2-13 | outbox·`EntityChange` 힌트 규칙에 새 두 종류 | 규칙 | 6.13 |
| C2-14 | `AssetStorageUsage.bytesByType`(선택 인자, 기본 `const {}`) | 추가 | 4.7, 6.15 |
| C2-15 | `NoteStore` getter 4개 | 깨짐(INFRA 시험 가짜 1곳) | 4.7, 8.1 묶음 병합 |
| C2-16 | `NoteStoreConfig.nativeAssetDirectoryPath` | 추가·규칙 | 4.7, 6.15.3 |
| C2-17 | CORE provider 6개 | 추가 | 4.10, 6.16 |
| C2-27 | `SearchText.normalize` = `PdfTextNormalizer`와 같은 결과 | 규칙 | 6.10.1 |
| C2-30 | ID 규칙 예외 `hw_<pageId>` | 규칙 | 6.9 |
| C2-38 | (v2.1) `Stroke.transformed`: 캘리그래피 `nibAngleDeg`(없으면 45) + 회전각 → [0, 180) | 규칙(CORE 동작 — 1차 표면의 유일한 동작 변경) | 6.2.7 |
| C2-39 | (v2.1) 진입점 `testing_web.dart`(`openWebTestNoteStore`·`deleteWebTestNoteStore`) | 추가 | 4.9, 4.11, 6.18.1 |
| (CP-17) | (v2.1 제안) `dev_tools.dart` v1 사본 함수 4개 | 추가 | 6.12.4 |

---

## 2. PLAN.md 요구사항 대응표

'CORE가 하는 일'은 저장·모델·명령 쪽 몫만 적는다. 화면·엔진 몫은 1.4의 영역이 한다.

### 2.1 기능 명세 (PLAN 4장)

| PLAN | 요구 | CORE가 하는 일 | 작업 |
|---|---|---|---|
| F-03 (P1 추가 펜) | 붓펜·캘리그래피·점선·레이저·테이프 | 1차 `PenTool` 10값·`StrokeStyle.defaultsFor` 그대로(C2-04 — 값 추가 없음). extras 키 의미는 INK `InkStyleExtras`, CORE는 extras 맵을 그대로 저장·동기화 — 예외 하나: (v2.1, C2-38) 캘리그래피 획을 회전하면 `Stroke.transformed`가 `nibAngleDeg`를 함께 돌린다(6.2.7). 레이저 획은 명령으로 오지 않는다(INK K-9, 1차 E-3). 테이프·레이저·형광펜은 손글씨 인식 입력에서 뺀다(`isRecognitionInput`) | T20b, T21 |
| F-10 | 올가미 손글씨 → 텍스트 상자 / 복사, 결과 수정 | `CompositeCommand([RemoveElements(획), AddObjects([TextBoxObject])])` = 되돌리기 1단계(7.2.3 표). 변환 창이 고친 줄은 `HandwritingLine.userConfirmed`로 — (v2.1) `HandwritingRepository.update`로 저장된 값과 한 트랜잭션에서 병합(G-4) | T22, T23a, T32 |
| F-10 | 같은 인식 결과로 손글씨 검색 색인 | `HandwritingText`(동기화 엔티티) → CORE가 `search_units(source ink)`로 직접 색인, 색인기 시작 때 `notesWithStalePages` | T32, T33a·T33b |
| F-11 | 도형 7종, 테두리 색·굵기·선 스타일·채우기, 크기·회전·꼭짓점 | `ShapeObject`(`ShapeKind`·`ShapeGeometry` 절대 좌표·`ShapeStyle`), 템플릿(`ShapeGeometry.line/rectangle/…/star`), 꼭짓점 이동·비율 무시 크기 = `UpdateObjects`, 비율 유지·회전 = `TransformElements` | T20a·T20b, T22 |
| F-11 | 자동 도형 보정 | INK `InkEdit(addShape)` → `AddObjects([ShapeObject])`(원래 획은 저장되지 않음) | T22 |
| F-12 | 제스처·펜 버튼 | CORE 몫 없음(EDITOR 설정 JSON은 1차 `SettingsRepository` `jsonMap` 키) | — |
| F-13 | 이미지 페이지 | 1차 `ImageBackground`(모델·JSON·동기화 완료) + `InsertPages`. 검색·참조용 파생 열 `pages.bg_asset_id` | T24 |
| F-14 | 수식 객체: 이동·크기·색·다시 편집·LaTeX 복사 | `MathObject`(`latex`·`MathStyle`·`engineId`), `TransformElements`가 `fontSizePt`도 배율, 검색 단위(source math) | T20a·T20b, T33a·T33b |
| F-14 | 엔진 교체 구조, 외부 키는 서버 함수 | 출처 `engineId`만 저장(엔진·서버 함수는 LIBRARY·SYNC) | T20a·T20b |
| F-16 | 노트당 여러 녹음, 녹음만 따로 삭제, 용량 표시 | `RecordingRepository`(`watchRecordings`·`createRecording`·`renameRecording`·`deleteRecording`(소프트 — U13)·`audioBytesOf`), `AssetStorageUsage.bytesByType[audio]` | T30 |
| F-16 | 녹음 중 쓴 획마다 시점 → 재생 강조·탭 재생 | 1차 `Stroke.recordingId/recordingOffsetMs` 그대로. 연결 없음 규칙 R-7(녹음 행이 없거나 삭제·취소), 노트 복사 R-6 | T29, T30 |
| F-16 | 백그라운드 녹음·끊김 대비 | `RecordingDraftStore`(조각 ≤ 4 MiB, 쓰기 Future = 내구 저장 뒤 완료, 다음 실행 때 `listDrafts`) — 웹 1초 조각(M-2, D13) | T31 |
| F-16 | 압축 후 동기화 | 1차 에셋·`Recording` 동기화 경로 그대로(+ `title` 필드) | T26, T28 |
| F-16 | 녹음 동의 안내 | CORE 몫 없음(문구 고정 — 7.4.4, media) | — |

### 2.2 추가 기능 (PLAN 5장) · 아키텍처 (7장) · 로드맵 (10장)

| PLAN | 요구 | CORE가 하는 일 | 작업 |
|---|---|---|---|
| 5.1 올가미(M5 고급) | 회전·색 변경·잘라내기·붙여넣기, 획과 객체 함께 | `TransformElements`(획 + 객체 한 커밋 — C-11), 색 변경 `CompositeCommand([RestyleStrokes, UpdateObjects])`, 잘라내기 `RemoveElements`, 붙여넣기 `CompositeCommand([AddStrokes, AddObjects])` + `PageObject.copyTo` | T22, T23a, T27 |
| 5.1 텍스트 상자 | 키보드 입력 | `TextBoxObject`·`TextBoxStyle`, 편집 세션 1회 = `AddObjects`/`UpdateObjects` 1회(E-6), 검색 단위(source text) | T20a·T20b, T33a·T33b |
| 5.1 이미지 삽입 | 사진·카메라·붙여넣기 | `ImageObject`(`assetId`·`pixelWidth/Height`), `ImageImportLimits`·`ImportedImage` | T20a·T20b, T21 |
| 5.1 검색 | 제목 → PDF 텍스트 → 손글씨 내용 | `searchLibrary`가 `pages`(손글씨·PDF·텍스트 상자·수식)를 채움, `SearchIndexWriter`(PDF) | T33a·T33b |
| 5.2 손글씨 검색 | M7 | 위 + `HandwritingRepository.stalePages`(색인기 입력) | T32, T33a·T33b |
| 5.2 레이저·암기 테이프 | | 저장 형식 변화 없음. 테이프 드러냄 상태는 저장하지 않는다(U10 — INK) | — |
| 5.2 전체 백업 | | 백업 JSON에 `pageObject`·`handwriting`·녹음 `title` 포함, 색인·초안 제외(3.2) | T29 |
| 5.4 데이터 안전 | 강제 종료에도 손실 없음 | 마이그레이션 한 트랜잭션(실패 시 v1 그대로) + (v2.1) 업그레이드 직전 v1 사본(성공 뒤 손상 대비), 녹음 조각 1초마다 내구 저장 + 초안 meta(행 유실에도 되살림), 파일 블롭 원자적 쓰기(임시 파일 → 이름 바꾸기) | T24, T31, T35 |
| 5.4 성능 | 500쪽 PDF·획 10만 개 | `stalePages`는 점 디코드 없이 페이지 캐시 열(6.9.3), 검색 5,000쪽 질의 중앙값 — 후보 100개 미만 ≤ 5 ms(1글자 LIKE ≤ 15 ms), 그 밖 ≤ 50 ms(V10, v2.5 C25-01), (v2.1) PDF 500쪽 색인 DB ≤ 12 MB·다시 열기 +300 ms(글자 상자는 SQLite 밖), 객체 2,000개 페이지 열기 | T32, T33a·T33b, T37 |
| 5.4 저장 용량 | 압축·중복 제거 | 노트 복사·녹음 복사는 에셋 해시 공유, 색인 크기 측정 | T29, T37 |
| 7.2 데이터 모델 | `Shape{kind, geometry, strokeStyle, fill, transform}`, `TextBox{rect, content, style}`, `MathObject{rect, latex, color}`, `ImageObject{rect, rotation, assetId}` | `ShapeObject{shapeKind, geometry(절대 pt — transform을 기하에 반영), style(테두리·채우기)}`, `TextBoxObject{frame(rect + rotation), text, style}`, `MathObject{frame, latex, style(color·size)}`, `ImageObject{frame(rect + rotation), assetId, px}` | T20a·T20b |
| 7.5 되돌리기 | 변경분만, 100단계 | 객체 명령도 `EntityDelta`(before/after) — 메모리 추정 `estimatedBytes`에 글자 수 반영 | T23a |
| 7.6 수익화 대비 | 기능 스위치, `Asset.size`, `schemaVersion` | 오디오 포트 기본값 '지원 안 함'(스위치로 끈 모듈 = override 없음 — D14), `bytesByType`, `kNoteSchemaVersion` 1 유지(D4)·DB v2 | T21, T24 |
| 10장 M5 | 올가미 고급, 텍스트 상자·이미지, 도형 + 자동 보정 | 위 각 행 | T20a~T23b, T27 |
| 10장 M6 | 녹음·백그라운드·재생 바, 획별 시점 | 녹음 저장소·초안·포트 | T21, T30, T31 |
| 10장 M7 | 손글씨 → 텍스트, 손글씨 검색 색인, 수식 | 손글씨 결과·검색 색인·수식 객체 | T20a·T20b, T32, T33a·T33b |
| 1차 7.8 미룬 항목 | 이미지 페이지, 라이브러리 전역 PDF 텍스트 검색, 백업에 새 엔티티 | 위 F-13·5.1 검색·5.2 백업 행 | T24, T29, T33a·T33b |
| 개요 3.1 공통-1 | 네이티브 저장 | 파일 DB + 파일 블롭 | T35 |

---

## 3. 소유 경로와 패키지 구조

1차 트리(1차 3절)에 더하는 것만 표시한다. `(새)` = 새 파일, `(변경)` = 1차 파일 수정. 나머지는 1차 그대로다.

```text
packages/note_core/
├─ pubspec.yaml                 # 변경 없음 — 새 의존 없음 (3.1)
├─ build.yaml                   # 변경 없음(6.11 1안 — 확정). 1안이 예상 밖으로 실패할 때만 sqlite_modules: [fts5]
├─ dart_test.yaml               # 변경 없음 — 태그 perf(기본 skip)·golden. CORE는 integration·media 태그를 쓰지 않는다
├─ .gitignore                   # (변경) test/web/fixtures_v1/ 추가 (6.18.1)
├─ README.md                    # (변경) 2차 사용 예 (T37)
├─ drift_schemas/note_db/
│  ├─ drift_schema_v1.json
│  └─ drift_schema_v2.json      # (새) make-migrations 산출물
├─ tool/
│  ├─ prepare_web_test.dart     # (변경) --out <dir>(다른 패키지 test/web), V7 고정 자료를 test/web/fixtures_v1/로 복사 (6.18.1)
│  ├─ make_v1_fixture.dart      # (새) V7 고정 자료 생성기 — v1.4 API만, 1차 통합이 main에 들어간 커밋에서 실행 (T25a, 6.12.3)
│  └─ v1_fixture_manifest.dart  # (새) manifest.json(행 수·fullDumpSha256·entityDumpSha256) — 2차 정규 덤프로 계산 (T25b)
├─ lib/
│  ├─ note_core.dart            # (변경) 새 export: search/, media/, repo/recording_repository.dart, repo/handwriting_repository.dart, assets/image_import.dart
│  ├─ testing.dart              # (변경) v2 도우미: PageObjectFixtures, FakeAudioRecorder, FakeAudioPlayback
│  ├─ testing_web.dart          # (새, v2.1 — C2-39) openWebTestNoteStore, deleteWebTestNoteStore (브라우저 시험 전용, INFRA R4 예외)
│  ├─ testing_vm.dart           # 변경 없음 (openTestNoteStore는 v2 DB를 연다 — 시그니처 그대로, 통합 c4966ce 동작 유지)
│  ├─ dev_tools.dart            # (변경) CP-9 objectsPerPage(P-C), (v2.1) CP-17 V1DatabaseCopyInfo·v1DatabaseCopyInfo·readV1DatabaseCopy·deleteV1DatabaseCopy
│  └─ src/
│     ├─ common/
│     │  ├─ geometry.dart       # (변경) PagePoint, ElementFrame
│     │  └─ text_normalize.dart # (변경) normalizeForSearch → SearchText.normalize 위임(내부 이름 유지, T24 — 검토 S-16)
│     ├─ model/
│     │  ├─ stroke.dart         # (변경) part 지시문 5개, PageElement 주석
│     │  ├─ page_object.dart    # (새, part of stroke.dart) PageObject, PageObjectLimits, 공통 JSON 도우미
│     │  ├─ shape_object.dart   # (새, part) ShapeObject
│     │  ├─ text_box_object.dart# (새, part) TextBoxObject
│     │  ├─ image_object.dart   # (새, part) ImageObject
│     │  ├─ math_object.dart    # (새, part) MathObject
│     │  ├─ unknown_object.dart # (새, part) UnknownObject
│     │  ├─ shape_geometry.dart # (새) ShapeKind, LineDash, ArrowHeads, ShapeGeometry(sealed)·Polyline·Ellipse, 템플릿
│     │  ├─ object_styles.dart  # (새) ShapeStyle, TextAlignKind, TextBoxStyle, MathStyle
│     │  ├─ handwriting.dart    # (새) HandwritingLine, HandwritingText
│     │  ├─ asset.dart          # (변경) Recording.title
│     │  ├─ sync_entity.dart    # (변경) EntityKind 2값(B2), kDatabaseSchemaVersion 2(T24)
│     │  └─ entity_json.dart    # (변경) pageObject·handwriting 디코드
│     ├─ edit/
│     │  ├─ commands.dart       # (변경) AddObjects, UpdateObjects, RemoveElements, ClearPage.includeObjects
│     │  ├─ page_draft.dart     # (변경) PageDraft.objects, copyOf
│     │  ├─ command_resolver.dart # (변경) 새 명령·객체 변형·검증 (6.4)
│     │  └─ applied_edit.dart   # (변경) EntityDelta.estimatedBytes에 객체
│     ├─ session/
│     │  ├─ page_content.dart   # (변경) objects, objectById, elementById, objectCount
│     │  ├─ session_backend.dart# (변경) loadStrokes → loadContent(획 + 객체)
│     │  └─ session_engine.dart # (변경) 객체 상태·원격 반영(N-7)
│     ├─ media/                 # (새)
│     │  ├─ audio_ports.dart    # 계약 경로 — 포트·상태 타입 (7.2.4)
│     │  └─ unsupported_audio.dart # UnsupportedAudioRecorder, UnsupportedAudioPlayback
│     ├─ search/                # (새)
│     │  ├─ search_text.dart    # SearchText, SearchTextMapping (+ 내부: 낱말 나누기, 일치 판정 searchMatches, FTS 후보 흉내 ftsCandidateMatches)
│     │  ├─ search_types.dart   # SearchSource, SearchUnitDraft, PageSearchHit, SearchIndexStatus, SearchIndexWriter, SearchIndex
│     │  ├─ search_ranking.dart # (내부) 점수·발췌·사각형 변환 — 실제·가짜 공용 (6.10.4)
│     │  └─ search_rects.dart   # (내부) SearchRectsCodec — PDF 글자 상자 1/65535 형식 (6.10.3)
│     ├─ repo/
│     │  ├─ note_store.dart     # (변경) getter 4개, nativeAssetDirectoryPath
│     │  ├─ library_types.dart  # (변경) LibrarySearchResult.pages·pagesTruncated
│     │  ├─ recording_repository.dart  # (새) RecordingRepository, RecordingDraftStore, RecordingDraft
│     │  └─ handwriting_repository.dart # (새) HandwritingRepository
│     ├─ assets/
│     │  ├─ asset_store.dart    # (변경) AssetStorageUsage.bytesByType, 로컬 이미지 형식 검사(CP-11)
│     │  ├─ blob_store.dart     # (변경, 내부) getMany(keys) — 검색 사각형 묶음 읽기 (6.10.4)
│     │  ├─ image_import.dart   # (새) ImageImportSource, ImportedImage, ImageImportLimits
│     │  ├─ blob_backend.dart   # (새, 내부) BlobStore + ThumbnailStore 묶음 팩토리 (조건부: _stub/_browser/_native)
│     │  └─ file_blob_store_native.dart # (새, 내부) 파일 블롭·썸네일 (dart:io — 6.15.3)
│     ├─ storage/
│     │  ├─ db/tables.dart      # (변경) 새 테이블 5개·열·색인 (6.11)
│     │  ├─ db/note_database.dart(.g.dart) # (변경) schemaVersion 2, onCreate에 FTS
│     │  ├─ db/migrations.dart  # (변경) kSchemaSteps = {1: upgradeV1ToV2}
│     │  ├─ db/migration_v2.dart# (새) v1 → v2 단계 본문 (6.12)
│     │  ├─ db/note_database.steps.dart # (새, 생성·커밋) make-migrations 단계 도우미 (v2.1 정정 — drift_dev 2.35.2 산출 이름)
│     │  ├─ db/v1_copy.dart     # (새, 내부) 업그레이드 직전 v1 사본·수명 (6.12.4 — 네이티브 VACUUM INTO는 *_native.dart)
│     │  ├─ db/canonical_dump.dart # (새, 내부) 정규 덤프 — 웹 사본 형식이자 V7 해시 (6.12.3)
│     │  ├─ row_mappers.dart    # (변경) page_objects, handwriting, recordings.title, pages 파생 열
│     │  ├─ write_queue.dart    # (변경) 힌트·고아 객체·색인 훅 (6.13)
│     │  ├─ search_indexer.dart # (새) 쓰기 트랜잭션 안 색인 갱신·보류 재시도 (6.10.5)
│     │  ├─ drift_search_index.dart        # (새) SearchIndex 구현
│     │  ├─ drift_recording_repository.dart# (새)
│     │  ├─ drift_recording_draft_store.dart # (새)
│     │  ├─ drift_handwriting_repository.dart # (새)
│     │  ├─ drift_sessions.dart, drift_content_reader.dart, drift_sync_store.dart,
│     │  │  drift_trash_repository.dart, drift_library_repository.dart, drift_note_store.dart # (변경)
│     │  ├─ connect/connect_native.dart # (변경) 파일 블롭 선택·삭제, 루트 디렉터리 만들기, v1 사본 파일(VACUUM INTO·이름 바꾸기·삭제)
│     │  ├─ connect/connect_browser.dart # (변경) 시험용 초기 바이트 인자(@visibleForTesting — V7 Chrome)
│     │  └─ kv_keys.dart        # (변경) search.normalizerVersion, search.lastRebuildAt, db.v1Copy
│     ├─ backup/backup_export.dart # (변경) 새 종류 (6.14.4)
│     ├─ fake/
│     │  ├─ fake_note_store.dart # (변경) 객체·getter 4개
│     │  ├─ fake_recordings.dart # (새) 녹음·초안 메모리 구현
│     │  ├─ fake_handwriting.dart# (새)
│     │  ├─ memory_search_index.dart # (새) 메모리 색인 — 같은 id 규칙·FTS 후보 흉내·후보 순서 (6.10.6)
│     │  ├─ fake_audio.dart     # (새) FakeAudioRecorder, FakeAudioPlayback
│     │  └─ page_object_fixtures.dart # (새)
│     ├─ migration/note_migrator.dart # (변경, 내부) 컨텍스트에 objectsOf·putObject
│     └─ providers.dart         # (변경) 새 provider 6개
└─ test/
   ├─ model/        # (새 파일) page_object_test, shape_geometry_test, object_json_test, handwriting_text_test, recording_title_test, image_import_test
   ├─ common/       # (새 파일) element_frame_test (+ text_normalize_test 변경)
   ├─ search/       # (새) search_text_test, search_query_test, search_rects_codec_test, search_index_writer_test, search_index_test, fts_candidate_equivalence_test, search_contract_{fake,real}_test
   ├─ media/        # (새) audio_ports_test, recording_draft_store_test, recording_draft_contract_{fake,real}_test
   ├─ repo/         # (새 파일) recording_contract_{fake,real}_test, recording_repository_test, handwriting_contract_{fake,real}_test, handwriting_repository_test, note_copy_v2_test, trash_purge_v2_test, library_search_v2_test
   ├─ edit/         # (새 파일) object_commands_test, undo_objects_test, calligraphy_transform_test (C2-38)
   ├─ session/      # (새 파일) object_session_contract_{fake,real}_test, note_session_objects_test
   ├─ storage/      # (새 파일) schema_v2_test, migration_v2_test, v1_copy_test, canonical_dump_test, outbox_v2_test, change_bus_v2_test, row_mappers_v2_test, native_file_store_test
   │  └─ generated_migrations/note_db/ # (새, 생성·커밋) generated/schema_v1.dart·schema_v2.dart, migration_test.dart (1차 build.yaml test_dir)
   ├─ migration/    # (새 파일) v1_fixture_migration_test
   ├─ assets/       # (새 파일) file_blob_store_test, storage_usage_test
   ├─ sync/         # (새 파일) sync_store_v2_test, field_lww_convergence_v2_test, unknown_object_roundtrip_test
   ├─ testing/      # (새 파일) fake_store_v2_test, fake_audio_recorder_test, fake_audio_playback_test, page_object_fixtures_test
   ├─ shared/       # (새 공유 본문) object_session_contract, recording_contract, recording_draft_contract, handwriting_contract, search_contract, search_text_cases, object_json_web_cases
   ├─ web/          # (새) testing_web_browser_test, object_json_browser_test, search_text_browser_test, search_fts_browser_test, search_reopen_time_browser_test(perf), recording_draft_browser_test, v1_fixture_migration_browser_test, v1_copy_browser_test, canonical_dump_browser_test
   │  └─ fixtures_v1/  # (복사본 — .gitignore) prepare_web_test.dart가 fixtures/db_v1/에서 복사
   ├─ perf/         # (새 파일) object_page_perf_test, search_perf_test, search_real_shape_perf_test(PF-10), stale_pages_perf_test(PF-6·PF-11), draft_append_perf_test, migration_perf_test
   ├─ goldens/json/ # (새 파일) shape_rect.json, shape_ellipse.json, shape_arrow.json, text_box.json, image.json, math.json, math_no_engine.json, unknown.json, handwriting.json, recording.json(변경)
   ├─ goldens/backup/backup_v2.json   # (새 — backup_v1.json을 대신함, 6.14.4)
   └─ fixtures/db_v1/                 # (새) noteapp_v1.sqlite, pdf_asset.pdf, fixture_source.json (T25a), manifest.json (T25b) (6.12.3)
```

원칙(1차 3절 그대로 + 더함)

- `PageObject`와 5종은 `sealed class PageElement`와 **같은 라이브러리**여야 하므로 `model/stroke.dart`의 `part` 파일이다(7.2.2 주석). `part` 파일은 import를 갖지 못하므로 필요한 import(`shape_geometry.dart`·`object_styles.dart`·`dart:convert` 등)는 `stroke.dart`에 둔다. 스타일·기하는 하위 타입이 아니라 별도 라이브러리다.
- `dart:io`는 1차 규칙대로 `*_native.dart`(이번에 `assets/file_blob_store_native.dart` 추가)·`testing_vm.dart`·`tool/`에서만 쓴다. `dart:io` `Platform`은 쓰지 않는다(7.4.1).
- `lib/src/search/search_ranking.dart`·`storage/search_indexer.dart`·`fake/memory_search_index.dart`는 내보내지 않는다. 실제 색인과 가짜 색인이 **같은 일치 판정·점수 함수**를 쓰게 하려고 랭킹을 한 파일에 모았다(6.10.6).
- 생성 코드(`*.g.dart`, `drift_schemas/`, (v2.1 정정) `note_database.steps.dart`, `test/storage/generated_migrations/`)는 커밋한다(1차 7.4.7). drift_dev 2.35.2 `make-migrations`의 산출 이름은 `<db 파일>.steps.dart`다(`make_migrations.dart` 524–525 [확인] — v2.0 계획의 `schema_versions.dart`는 틀렸다). INFRA R2-B1이 `workspace_rules.yaml` `generated_files`에 `*.steps.dart`를 더한다(7.6.2 R2-B1 — 지금 목록은 `*.g.dart`·`*.freezed.dart`·`schema_versions.dart`, 통합 HEAD 83행 [확인]).
- `test/fixtures/db_v1/noteapp_v1.sqlite`는 이진 파일(약 2 MB 목표 — INFRA `.gitattributes` `*.sqlite binary`)이다. 커밋 크기를 줄이려고 점 수가 적은 합성 획을 쓴다(6.12.3).
- `testing_web.dart`는 브라우저 전용 진입점이다(`test/web/`에서만 import — INFRA `lib_exceptions`에 `note_core/lib/testing_web.dart`, C2-39). VM `api_surface_test`는 이것을 import하지 않는다.

### 3.1 pubspec.yaml

**새 의존이 없다.** 1차 pubspec(1차 3.1) 그대로이고, 7.5 고정표의 note_core 열도 바뀌지 않는다.

| 쓰는 곳 | 기존 의존 |
|---|---|
| `sourceRevOf`(SHA-256 앞 16 hex) | `crypto: 3.0.8`(1차 해셔 대체 경로에서 이미 씀) |
| FTS5(`contentless_delete=1`)·`json_extract` | `sqlite3: 3.8.0`(SQLite 3.54.1 — 웹 `sqlite3.wasm`과 같은 판), `drift: 2.35.3` |
| 파일 블롭 | `dart:io`(SDK) — `path_provider`는 INFRA 앱 셸만 쓴다(7.5, 7.4.1) |
| 녹음 시계 | 없음 — 시계는 media_io 몫. CORE 가짜는 수동 시계(`advance`)라 `Stopwatch`·`clock.stopwatch()`를 쓰지 않는다(7.4.8) |

- `sqlite3 3.9.0`(2026-11-05 게시)은 게시 14일 규칙(7.5)으로 채택하지 않는다. `drift`·`drift_dev`·`build_runner`도 1차 값 그대로다.
- 순수 Dart 패키지 규칙(R2) 그대로 — `flutter` 의존 없음.


---

## 4. 공개 API

모든 공개 타입은 1차처럼 `package:note_core/note_core.dart`(웹 안전)에서 export한다. 시험 도우미는 `testing.dart`(웹 안전, `test/`에서만), VM 전용 도우미는 `testing_vm.dart`, (v2.1) 브라우저 시험 전용 도우미는 `testing_web.dart`(`test/web/`에서만 — C2-39)다(1차 7.1 규칙 2). **4.1~4.11의 공개 선언 전부가 기반 단계 R2-B2의 첫 커밋 B2-α('계약 타입 커밋')에 들어간다**(8.1 — 알고리즘 본문은 작업 번호를 단 `UnimplementedError`). 동작은 B2-β가 채우고, DB v2·FTS5·파일 블롭은 동시 개발 몫이라 그 전까지 실제 저장소의 새 멤버는 8.1 'B2 상태' 표대로 동작한다.

| 이 절 | 7장 | 내용 |
|---|---|---|
| 4.1 | 7.2.2 | `PagePoint`, `ElementFrame` |
| 4.2 | 7.2.2 | 페이지 객체 5종, `EntityKind` 2값 |
| 4.3 | — | CORE 확정 세부(객체) |
| 4.4 | 7.2.3 | `PageContent`·`PageDraft`·명령 3종·의미 변경 |
| 4.5 | 7.2.4 | 녹음 엔티티·저장소·초안·오디오 포트·연결 규칙 |
| 4.6 | 7.2.5 | 손글씨 결과·검색 색인·`SearchText`·`LibrarySearchResult.pages` |
| 4.7 | 7.2.6 | 이미지 가져오기·에셋 용량·`NoteStore` getter·`nativeAssetDirectoryPath` |
| 4.8 | 7.2.7 | JSON 키·DB 스키마 v2·마이그레이션 규칙 |
| 4.9 | 7.6 | `testing.dart` v2.1, `testing_web.dart` |
| 4.10 | 7.2.4·7.2.5 | provider 추가 |
| 4.11 | 7.1 | 진입점·`api_surface_test` v2 |

### 4.1 기초 타입 — `PagePoint` · `ElementFrame` (7.2.2)

`// 계약 v2.1 7.2.2 원문` (첫 블록 — 나머지는 4.2)

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

- (v2.1) `fromJson`은 값을 접지도 자르지도 않는다 — `−π`·`3π`·변 0을 받은 그대로 담고 그대로 쓴다(검토 S-1, 6.2.1). 접는 것은 `normalized()`와 로컬 명령 해석뿐이다. `maxSide`·`normalized()`·`==`는 CP-4 승인으로 원문 주석에 들어갔다.

### 4.2 페이지 객체 (7.2.2)

`// 계약 v2.1 7.2.2 원문` — 결정 문장, 나머지 Dart 정의, 끝 문단(첫 블록은 4.1)

결정 (조사 01 R1·R3 채택, 변형 포함):

- 획이 아닌 페이지 요소는 **`EntityKind` 하나(`pageObject`)와 테이블 하나(`page_objects`)**로 넣고, 종류는 JSON `type`(`shape`·`text`·`image`·`math`)으로 나눈다. 종류마다 `EntityKind`를 두면 SYNC·CORE switch와 매핑이 네 배가 된다.
- 모르는 `type`은 원본 JSON을 보존하는 `UnknownObject`로 읽고, `frame` 자리에 자리표시를 그리고, 그대로 동기화한다(다음 라운드에 종류가 늘어도 옛 앱이 기록을 잃지 않음).
- 모든 객체는 회전 가능한 상자 `ElementFrame`을 가진다. 도형만 꼭짓점 기하(`ShapeGeometry`)가 원본이고 `frame`은 거기서 계산한다.
- z 순서는 1차 `Stroke.compareOrder`(createdAt → id) 그대로다. '맨 앞/뒤로'는 이번에 하지 않는다(3.5 D2). 층(어느 묶음이 위에 그려지는가)은 INK가 종류로 정한다(7.2.9 L-1).

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

- `EntityKind`(깨짐): `enum EntityKind { folder, note, page, stroke, penPreset, asset, recording, setting, pageObject, handwriting }` — 뒤에 둘을 더한다. 이름(wire)은 enum 이름 그대로다.
- `Stroke.compareOrder(PageElement a, PageElement b)`는 그대로 객체에도 쓴다(createdAt → id).
- 붙여넣기·복제된 객체는 `copyTo`로 새 `createdAt`(= 붙여넣은 시각 + i, 1차 획 클립보드 규칙과 같음)을 받는다.
- (v2.1, CP-4·CP-5) 4종의 공통 필드(`id`·`pageId`·`createdAt`·`updatedAt`(생성자 `updatedAt ?? createdAt`)·`deletedAt`·`version`)와 값 `==`·`hashCode`는 종류마다 같다. 스타일 정규화: `ShapeStyle.normalized()`는 `strokeColorArgb`·`fillColorArgb` 알파를 0xFF로(불투명도는 `*Opacity`가 가짐), `TextBoxStyle.backgroundArgb` 알파는 그대로(반투명 배경 허용). 정규화는 **로컬 명령 해석 때만** 하고 `fromJson`은 하지 않는다. 세부 표·`estimatedBytes` 공식은 02-core 4.3·6.2.3이 단일 출처다.
- (v2.1) 소비자는 객체 종류를 Dart 타입(`is TextBoxObject`, `switch`)으로 나눈다. `type` 문자열은 저장 형식용이다(`UnknownObject`도 `'shape'` 같은 알려진 이름을 가질 수 있다).

### 4.3 CORE 확정 세부 — 페이지 객체

7장이 '02-core 4.3·6.2.3이 단일 출처'라고 가리킨 세부와, 아직 `// … as Stroke`로 둔 멤버다(CP-2·CP-4·CP-5·CP-6은 v2.1에 승인되어 원문으로 옮겨졌다 — 아래는 원문과 겹치지 않는 나머지). 모두 원문 이름과 겹치지 않는 **추가**다.

```dart
// CORE 확정 세부 — 7.2.2가 02-core를 가리킨 곳과 '// … as Stroke'로 둔 멤버 (v2.1)

// lib/src/common/geometry.dart
final class PagePoint {
  // ==, hashCode (x, y), toString — no JSON of its own (frames and geometry write arrays)
}
final class ElementFrame {
  /// (contract: maxSide, normalized) width / height clamped to [0, maxSide] around the same
  /// center; rotation folded into (-pi, pi] (so -pi → pi, 3·pi → pi). The const constructor and
  /// fromJson keep the given values.
  ElementFrame normalized();
  // ==, hashCode over the raw (rect, rotation): ElementFrame(r, rotation: -pi) != ElementFrame(r, rotation: pi)
}

// lib/src/model/page_object.dart (part of stroke.dart)
sealed class PageObject extends PageElement {
  /// (contract: '02-core 4.3 formula') History memory estimate (6.4.4):
  /// 160 B + 2·text.length (text) | 2·latex.length (math) | 16·points (polyline)
  /// | 2·(UTF-16 length of jsonEncode(rawJson)) (unknown).
  int get estimatedBytes;
  // transformed(m, {scaleWidth}) — the single rule; exact table: 6.2.5.
}

final class ShapeObject extends PageObject {     // same member set for TextBoxObject, ImageObject, MathObject
  @override final ElementId id;
  @override final PageId pageId;
  @override final EpochMillis createdAt;
  @override final EpochMillis updatedAt;         // constructor: updatedAt ?? createdAt (as Stroke)
  @override final EpochMillis? deletedAt;
  @override final Hlc? version;
  // ==, hashCode over every field
}

final class UnknownObject extends PageObject {
  /// (contract: '(v2.1) A string assetId key in rawJson is reported') Top-level key 'assetId'
  /// only, and only when it is an AssetId (64 lowercase hex — 1차 ids.dart); otherwise {}.
  /// The same value goes to page_objects.asset_id (6.11) so a later asset GC keeps it (검토 S-13).
  @override Set<AssetId> get referencedAssets;
}

// lib/src/model/object_styles.dart, shape_geometry.dart
// ShapeStyle, TextBoxStyle, MathStyle, PolylineGeometry, EllipseGeometry: ==, hashCode (1차 7.4.4).
// Normalization table (the contract's 'single source'): 6.2.3.
```

### 4.4 페이지 내용 · 초안 · 편집 명령 (7.2.3)

`// 계약 v2.1 7.2.3 원문` — Dart 정의(EDITOR 명령 매핑 표는 5.3)

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

- (v2.1, CP-1 승인 — CD2-06) 새 명령 3종은 1차 명령과 같은 모양(`const`·이름 있는 인자·`label`)이다. `RemoveElements.elementIds`는 `List<ElementId>`다(검토자 권고 `Set` 대신 — 1차 id 목록 `RemoveStrokes.strokeIds`·`TransformElements.elementIds`와 같게, 중복 id는 무시). 소비자는 `RemoveElements(pageId: p, elementIds: [id])`로 쓴다.
- (v2.1, CP-2 승인 — CD2-07) `TransformElements`의 객체 쪽은 `PageObject.transformed(m, scaleWidth: scaleStrokeWidth)` **하나만** 부른다(6.2.5 표). INK·EDITOR 미리보기도 같은 함수를 부르므로 미리보기와 저장 결과가 갈리지 않는다. 캘리그래피 획의 펜촉 각(C2-38)은 `Stroke.transformed`가 함께 돌린다(6.2.7).
- (v2.1, 검토 S-17) `ClearPage`는 1차 생성자 `const ClearPage({required this.pageId, this.filter = StrokeFilter.all})`(`edit/commands.dart` 80–86)에 **이름 있는 선택 인자** `this.includeObjects = false`와 `final bool includeObjects` 필드를 더한다. `label`은 `'clear-page'` 그대로다. EDITOR CP-E5의 `ClearPage(pageId: p, includeObjects: true)`가 이 모양이다.
- 명령별 검증·바뀐 필드·`AppliedEdit`은 6.4.

### 4.5 녹음 (7.2.4) — 엔티티 · 저장소 · 오디오 포트 · 획 연결 규칙

`// 계약 v2.1 7.2.4 원문`

```dart
// Recording (v1.4 CORE 4.2) — 추가: title
final class Recording implements SyncEntity {
  const Recording({/* v1.4 fields */, this.title});
  final String? title;                           // trimmed 1..100 chars; null → UI shows '녹음 N' by startedAt order
  Recording copyWith({/* v1.4 */, String? title, bool clearTitle = false});
  // JSON: 'title' — (v2.1, CP-7) always written (null when unset); absent on read = null.
  // Old apps ignore it (no deployed old app before 실연결).
}

/// (v2.0) Local create / list API (v1.4 had only the remote-apply path).
abstract interface class RecordingRepository {
  Stream<List<Recording>> watchRecordings(NoteId noteId);   // active, startedAt asc
  Future<List<Recording>> recordingsOf(NoteId noteId);
  Future<Recording?> getRecording(RecordingId id);           // also deleted ones
  /// Called by media_io AFTER AssetStore.put(audio) returned (M-1). [id] was chosen at
  /// record start so strokes could link to it immediately. (v2.1, CP-7) Idempotent per id: a retry with the
  /// same id returns the existing row (recovery after a failed save does not duplicate).
  Future<Recording> createRecording({required RecordingId id, required NoteId noteId,
      required AssetId assetId, required int durationMs, required EpochMillis startedAt, String? title});
  Future<void> renameRecording(RecordingId id, String? title);
  /// Soft delete; no restore UI this round. Strokes keep recordingId (R-7). Asset bytes stay
  /// until asset GC (later, 3.2).
  Future<void> deleteRecording(RecordingId id);
  /// Σ Asset.size of the note's active recordings (재생 바 '용량').
  Future<int> audioBytesOf(NoteId noteId);
}

/// (v2.0) Crash-safe staging of an in-progress recording. Device-local: never synced, never in
/// backups, not in outbox. Chunks live in the asset blob store under a private prefix.
abstract interface class RecordingDraftStore {
  Future<RecordingDraft> begin({required RecordingId recordingId, required NoteId noteId,
      required String mimeType, required EpochMillis startedAt});
  /// Ordered append; each chunk ≤ 4 MiB; completes after the chunk is durable (write-Future rule).
  /// (v2.1) An empty chunk is allowed and only updates activeMs / updatedAt (keep-alive while
  /// paused). Unknown draftId → StateError (the draft was recovered or discarded elsewhere).
  Future<void> append(String draftId, Uint8List chunk, {required int activeMs});
  /// Leftovers after a crash / closed tab. (v2.1) A web draft whose chunks are stored but whose row
  /// was not yet durable is rebuilt from the meta the store writes next to the chunks at begin();
  /// a draft with a row and 0 chunks (native — media writes rows only) is normal and kept. Orphan
  /// cleanup removes only prefixes that have neither a row nor a meta.
  Future<List<RecordingDraft>> listDrafts();
  Future<Uint8List> readAll(String draftId);
  Future<void> discard(String draftId);
}
@immutable
final class RecordingDraft {
  const RecordingDraft({required this.draftId, required this.recordingId, required this.noteId,
      required this.mimeType, required this.startedAt, required this.chunkCount, required this.bytes,
      required this.activeMs, required this.updatedAt});
  final String draftId; final RecordingId recordingId; final NoteId noteId; final String mimeType;
  final EpochMillis startedAt; final int chunkCount, bytes, activeMs; final EpochMillis updatedAt;
}
```

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

```dart
// CORE 확정 세부 — 7.2.4가 이름만 정한 기본값, 02-core를 가리킨 곳, 생략한 인자 목록 (v2.1: CP-7·CP-8 승인)

// lib/src/media/unsupported_audio.dart — the provider defaults (web / VM without media_io,
// and every build where AppFeatures turned recording off — D14·D17). Behaviour table: 6.8.2
// (contract: 'Unsupported* behaviour table: 02-core 6.8.2').
final class UnsupportedAudioRecorder implements AudioRecorderService {
  const UnsupportedAudioRecorder();
}
final class UnsupportedAudioPlayback implements AudioPlaybackService {
  const UnsupportedAudioPlayback();
}

// lib/src/media/audio_ports.dart — argument lists of the contract's '(v2.1, CP-7) copyWith'
final class RecorderStatus {
  RecorderStatus copyWith({RecorderPhase? phase, RecordingId? recordingId, NoteId? noteId,
      int? activeMs, bool? backgroundCapable, bool? interrupted, String? mimeType,
      bool? crossPlatformPlayable, Object? error, bool clearRecording = false,
      bool clearError = false});                 // clearRecording: recordingId, noteId, mimeType → null
}
final class PlaybackStatus {
  PlaybackStatus copyWith({PlaybackPhase? phase, RecordingId? recordingId, int? durationMs,
      double? speed, bool? unsupportedFormat, Object? error, bool clearRecording = false,
      bool clearError = false});
}
// RecordingDraft: ==, hashCode, toString

// lib/src/repo/recording_repository.dart — the contract's draft rules, CORE side (6.7.2):
//   one draft per recordingId (a second begin → StateError); web chunks and a meta blob
//   'rd/<draftId>/meta' are written BEFORE the row is durable; listDrafts rebuilds a row-less
//   draft from its meta (activeMs 0, updatedAt = startedAt) and reconciles chunkCount / bytes
//   with the chunks; discard = chunks + meta first, then the row.
```

- (v2.1, CP-7) `Recording.toJson`은 `title`을 **항상** 쓴다(없으면 `null` — 키 집합 고정, SYNC 키 대조). `createRecording`은 id마다 멱등이다(같은 id가 있으면 그 행을 돌려준다 — 6.6). `pendingDrafts`·`recoverDraft`의 뜻은 원문 주석이 계약이고, CORE가 기본값·가짜에서 지키는 방식은 6.8.1~6.8.3이다.

### 4.6 손글씨 인식 결과 · 검색 색인 (7.2.5)

`// 계약 v2.1 7.2.5 원문` — 결정 문장과 Dart 정의

결정(조사 01 R7, 03 R3·R8 채택):

- 손글씨 인식 결과는 **동기화되는 엔티티**(`EntityKind.handwriting`)로 페이지마다 하나 둔다. 웹(ML Kit 불가)은 네이티브가 만든 결과를 받아 검색만 한다(실연결 뒤).
- id는 결정적이다: `HandwritingText.idFor(pageId) = 'hw_' + pageId`(1차 7.4.6 ID 규칙의 예외에 추가 — 두 기기가 같은 페이지를 인식해도 같은 엔티티가 된다).
- 검색 색인(`search_units` + FTS5)은 **기기 로컬 파생 데이터**다. 동기화·백업하지 않고 언제든 다시 만든다.
- 한국어 토큰화는 '음절 바이그램을 Dart에서 만들어 `unicode61` 내용 없는 테이블에 넣는' 방식(조사 03 9.2 실험)으로 한다. 정규화 함수는 제목·PDF·손글씨·텍스트 상자가 **하나**(`SearchText.normalize`)를 쓴다.

```dart
@immutable
final class HandwritingLine {
  const HandwritingLine({required this.text, this.alternatives = const [], required this.rect,
      required this.strokeIds, this.languageTag = 'ko', this.userConfirmed = false});
  final String text;                             // best, user-chosen or user-edited text
  final List<String> alternatives;               // ≤ 5, engine order
  final PageRect rect;                           // union of the line strokes' pointBounds, page pt
  final List<ElementId> strokeIds;
  final String languageTag;                      // BCP-47 of the model that produced [text]
  /// Set by the conversion UI. (v2.1) Auto re-recognition keeps a confirmed line's text while
  /// ≥ 80 % of its old strokeIds are still in the new line and the added strokes are small (each
  /// box ≤ the line's median glyph height); otherwise the engine text replaces it, userConfirmed
  /// becomes false and the old confirmed text goes first in alternatives. Rule owner: recog
  /// (05-library 6.9.4); writers merge through HandwritingRepository.update (G-4).
  final bool userConfirmed;
  Map<String, Object?> toJson();
  factory HandwritingLine.fromJson(Map<String, Object?> json);
}

final class HandwritingText implements SyncEntity {
  HandwritingText({required this.noteId, required this.pageId, required this.engineId,
      required this.sourceRev, required this.lines, required this.createdAt, int? updatedAt,
      this.deletedAt, this.version}) : id = idFor(pageId);
  static String idFor(PageId pageId) => 'hw_$pageId';
  /// Input strokes = active strokes of the page whose tool is not highlighter / tape / laser.
  /// sourceRev = first 16 hex chars of sha256 over "id:updatedAt;" of those strokes sorted by id.
  static String sourceRevOf(Iterable<Stroke> inputStrokes);
  static bool isRecognitionInput(Stroke s);
  @override final String id;
  final NoteId noteId; final PageId pageId;
  final String engineId;                         // 'mlkit-digital-ink/19.0.0:ko' — provenance only.
  // (v2.1) Freshness = same sourceRev AND same language tail (':ko'); a result from another engine,
  // engine version or device is fresh (no double recognition across devices after 실연결).
  final String sourceRev;
  final List<HandwritingLine> lines;             // reading order
  @override EntityKind get kind => EntityKind.handwriting;
  // createdAt, updatedAt, deletedAt, version, isDeleted, toJson / fromJson, ==,
  // (v2.1, CP-13) copyWith (HandwritingLine too); put validation: 02-core 6.9.4
}

abstract interface class HandwritingRepository {
  Future<HandwritingText?> forPage(PageId pageId);
  Stream<HandwritingText?> watchPage(PageId pageId);
  /// Upsert. Also re-indexes the page's ink units (same transaction when possible; an index
  /// failure never fails the write — C-13). (v2.1) Local writers (indexer, conversion UI) use
  /// [update] so a write that arrived meanwhile is merged, not overwritten (G-4).
  Future<void> put(HandwritingText value);
  /// (v2.1) Read-merge-write in ONE CORE write transaction: [transform] gets the stored value
  /// (null if none / deleted) and returns the value to store (null = leave as is). Synchronous and
  /// pure (no await inside). Returns the stored value afterwards. Same validation as put.
  Future<HandwritingText?> update(PageId pageId,
      HandwritingText? Function(HandwritingText? current) transform);
  Future<void> removeForPage(PageId pageId);
  /// Active pages of [noteId] whose input strokes' sourceRevOf differs from the stored value
  /// (or that have none and at least one input stroke). Cheap: uses DB columns, no point decode.
  /// (v2.1) Page order.
  Future<List<PageId>> stalePages(NoteId noteId);
  /// (v2.1) Active notes with ≥ 1 stale page, one query over the pages.ink_rev cache — the
  /// indexer's start-up catch-up. Most recently updated note first.
  Future<List<NoteId>> notesWithStalePages();
}
final handwritingRepositoryProvider = Provider<HandwritingRepository>(/* store.handwriting */);
```

```dart
enum SearchSource { ink, pdf, text, math }

@immutable
final class SearchUnitDraft {
  const SearchUnitDraft({required this.body, this.rects = const [], this.pdfPageAspect});
  final String body;                             // original text (CORE normalizes)
  /// source pdf: fractions [0,1] of the PDF page — one per char of body, or empty; PageRect.zero =
  /// position unknown (skipped when hit rects are merged per line). (v2.1) CORE may store them at
  /// reduced precision (≥ 1/65535 of the page) and outside SQLite (7.4.5 index size).
  final List<PageRect> rects;
  final double? pdfPageAspect;                   // (v2.1, CP-3) pdf only: PDF page width / height
}

/// For pdf_io (source pdf only). ink / text / math are indexed by CORE itself from
/// HandwritingText and PageObject rows (no other package writes them).
abstract interface class SearchIndexWriter {
  /// ownerKey for pdf: '<assetId>#<pdfPageIndex>' (one entry per PDF page, shared by every note
  /// that uses the asset). sourceRev for pdf: '<assetId>:<SearchText.normalizerVersion>' plus an
  /// optional pdf_io tail (':x<extractorVersion>', v2.1 CP-PDF-2); CORE compares it as a string.
  Future<String?> sourceRevOf(SearchSource source, String ownerKey);
  /// ownerKey → sourceRev of every owner of [source] (a feeder's start-up catch-up in one query).
  Future<Map<String, String>> sourceRevs(SearchSource source);
  /// (v2.1) An empty [units] list still records the owner with [sourceRev] (a scanned page, or the
  /// '#0 last' completion mark of pdf_io) — sourceRevOf / sourceRevs then return it.
  Future<void> replaceUnits(SearchSource source, String ownerKey, List<SearchUnitDraft> units,
      {required String sourceRev});
  Future<void> removeOwner(SearchSource source, String ownerKey);
}

@immutable
final class PageSearchHit {
  const PageSearchHit({required this.noteId, required this.pageId, required this.source,
      required this.snippet, required this.matchRange, this.rects = const [], required this.score});
  final NoteId noteId; final PageId pageId; final SearchSource source;
  final String snippet;                          // ≤ 80 chars of original text around the match
  final (int, int) matchRange;                   // [start, end) in snippet
  final List<PageRect> rects;                    // page pt of the note's Page.size (pdf converted)
  final double score;                            // higher = better; for ordering only
}

@immutable
final class SearchIndexStatus {
  const SearchIndexStatus({this.pendingOwners = 0, this.rebuilding = false, this.lastRebuildAt});
  final int pendingOwners; final bool rebuilding; final EpochMillis? lastRebuildAt;
}

abstract interface class SearchIndex implements SearchIndexWriter {
  /// normalize → bigram phrase query (FTS5) or LIKE fallback for 1-char queries; trashed notes
  /// excluded; results grouped by page, best score first. (v2.1) At most 2,000 candidates, most
  /// recent units first; candidates are judged without reading body excerpts or rects — only the
  /// returned hits read them. createFakeNoteStore uses the same judgement and order (CP-14).
  Future<List<PageSearchHit>> searchPages(String query, {int limit = 100, NoteId? withinNote});
  Stream<SearchIndexStatus> get status;
  /// Drops and rebuilds derived rows (also run when normalizerVersion changes).
  Future<void> rebuild({Set<SearchSource>? sources});
}
final searchIndexProvider = Provider<SearchIndex>(/* store.search */);

abstract final class SearchText {
  static const int normalizerVersion = 1;
  /// Hangul jamo composition → lowercase → whitespace folding. THE normalizer for titles
  /// (searchLibrary), PDF text, handwriting and text boxes (replaces common/text_normalize.dart's
  /// private copy and must equal pdf_io PdfTextNormalizer on the same input — test in PDF).
  static String normalize(String text);
  static String indexTerms(String normalized);  // syllable bigrams for Hangul words, words otherwise
  static String? matchQuery(String normalized); // FTS5 MATCH text; null → use LIKE fallback
  /// (v2.1, CP-10) normalize with a map back to source offsets (pdf_io highlight) — the same
  /// result text as normalize(); fields: 02-core 4.6.
  static SearchTextMapping normalizeMapped(String text);
}

// LibrarySearchResult (1차 7.2.9) — 추가
final class LibrarySearchResult {
  const LibrarySearchResult({required this.query, required this.folders, required this.notes,
      this.pages = const [], this.pagesTruncated = false});
  final List<PageSearchHit> pages;               // content hits (ink, pdf, text, math)
  final bool pagesTruncated;                     // (v2.1, CP-14) more pages than limit, or the 2,000-candidate cap was hit
}
// LibraryRepository.searchLibrary(query, {limit = 50}) now also fills pages (≤ 100).
```

```dart
// CORE 확정 세부 — 7.2.5가 02-core를 가리킨 곳과 생략한 인자 목록 (v2.1: CP-3·CP-10·CP-13·CP-14 승인)

// lib/src/search/search_text.dart — fields of SearchText.normalizeMapped (contract: 'fields: 02-core 4.6')
@immutable
final class SearchTextMapping {
  const SearchTextMapping({required this.text, required this.sourceStart, required this.sourceEnd});
  final String text;                             // == SearchText.normalize(source), always
  /// For normalized code unit i: the source range [sourceStart[i], sourceEnd[i]) in the input
  /// (same shape as pdf_io's 1차 PdfNormalizedText — PDF's normalize can wrap this one).
  final Int32List sourceStart, sourceEnd;
  // ==, hashCode (text and both lists)
}

// lib/src/model/handwriting.dart — argument lists of the contract's '(v2.1, CP-13) copyWith'
final class HandwritingLine {
  HandwritingLine copyWith({String? text, List<String>? alternatives, PageRect? rect,
      List<ElementId>? strokeIds, String? languageTag, bool? userConfirmed});
  // ==, hashCode
}
final class HandwritingText {
  HandwritingText copyWith({String? engineId, String? sourceRev, List<HandwritingLine>? lines,
      EpochMillis? updatedAt, EpochMillis? deletedAt, bool clearDeletedAt = false, Hlc? version});
  // ==, hashCode, toString
}
// SearchUnitDraft, PageSearchHit, SearchIndexStatus, LibrarySearchResult(+ pages): ==, hashCode
//
// SearchUnitDraft (source pdf) — how CORE reads rects (6.10.4):
//   rects.length == body.length → one box per UTF-16 code unit of body; a hit's rects are the
//     boxes of the matched range merged per text line, PageRect.zero boxes skipped;
//   rects empty → no boxes (a hit without rects); any other length → ArgumentError.
//   Fractions become note-page pt by PDF 1차 PdfPageFit (contain, centered) using
//   pdfPageAspect; without it (null) the fractions fill the note page (exact for imported pages,
//   1차 PDF C-2). Stored quantized to 1/65535 of the page OUTSIDE SQLite (blob store, 6.10.3).
// SearchIndexWriter.sourceRev: any string ≤ 200 chars, compared and stored as given (CP-PDF-2 tail).
```

### 4.7 이미지 가져오기 · 에셋 · 저장소 묶음 (7.2.6)

`// 계약 v2.1 7.2.6 원문`

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

// AssetStorageUsage — 추가
final class AssetStorageUsage { /* v1.4 */ final Map<AssetType, int> bytesByType; }

// NoteStoreConfig — 추가
final class NoteStoreConfig { /* v1.4 */ final String? nativeAssetDirectoryPath; }   // file BlobStore root (native)

// NoteStore — 깨짐(CORE 구현만): new getters
abstract interface class NoteStore {
  /* v1.4 */
  RecordingRepository get recordings;
  RecordingDraftStore get recordingDrafts;
  HandwritingRepository get handwriting;
  SearchIndex get search;
}
```

- 네이티브 저장(공통-1): `nativeDatabasePath`와 `nativeAssetDirectoryPath`가 모두 있으면 CORE는 파일 DB + 파일 블롭 저장소(`*_native.dart`, 청크 4 MiB 파일)를 쓴다. 둘 중 하나라도 없으면 1차처럼 `storageUnavailable`. 앱 셸이 `path_provider`의 앱 지원 디렉터리로 두 경로를 넘긴다(INFRA).
- 이미지 에셋은 `ImageImportLimits.storedMimeTypes`만 저장한다(PDF 이미지 객체 입력 형식과 같게 — JPEG는 `FPDFImageObj_LoadJpegFileInline`, PNG는 비트맵). (v2.1, CP-11) 로컬 `AssetStore.put(type: image)`이 `storedMimeTypes` 밖이면 `ArgumentError`다(원격 `putDownloadedBytes`는 검사하지 않음 — PDF 내보내기는 그래도 다른 형식에 대비한다).
- (v2.1) 네이티브 블롭 루트 디렉터리가 없으면 CORE가 만든다(INFRA는 경로만 넘긴다). 앱 셸이 네이티브에서 두 경로를 모두 넘기는지는 INFRA 정적 시험이 본다(1차 셸은 넘기지 않아 1차 APK가 노트를 저장하지 못했다).

```dart
// CORE 확정 세부 — 7.2.6 생성자 (C2-14·C2-16: 기본값이 있는 선택 인자, 7.0.2 끝 문단)
final class AssetStorageUsage {
  const AssetStorageUsage({required this.assetCount, required this.totalBytes,
      required this.thumbnailBytes, this.bytesByType = const {}});
  /// Σ Asset.size of rows with hasLocalBytes, per type (same rule as totalBytes, 1차 T13);
  /// a type with no bytes is absent (read as 0). == / hashCode include it.
  final Map<AssetType, int> bytesByType;
}
final class NoteStoreConfig {
  const NoteStoreConfig({/* v1.4 arguments */, this.nativeAssetDirectoryPath});
}
// ImportedImage: ==, hashCode. (v2.1, CP-11) local AssetStore.put(type: image) with a mimeType
// outside ImageImportLimits.storedMimeTypes → ArgumentError before any write (6.15.2).
```

### 4.8 저장 형식 — JSON 키 · DB 스키마 v2 · 마이그레이션 (7.2.7)

`// 계약 v2.1 7.2.7 원문` — 표의 DB 이름은 계약이 'CORE 내부, 이름은 CORE가 바꿀 수 있음'으로 둔 것이다. CORE가 실제로 쓰는 테이블·열(원문에 더한 `search_owners`·`pages` 파생 열, 사각형 참조 열 등)은 6.11, 업그레이드 직전 v1 사본의 저장 방식·수명은 6.12.4에 있다.

페이지 객체 JSON(동기화·백업 공통, camelCase, 모르는 키 무시 — 1차 규칙 그대로):

| `type` | 공통 키 | 종류별 키 |
|---|---|---|
| (모두) | `id`, `pageId`, `type`, `frame`(`[l,t,r,b,rot]` — **모든 종류가 쓴다**: 옛 앱이 모르는 종류를 자리표시로 그릴 수 있게. 도형은 기하에서 계산한 값을 쓰고 읽을 때는 무시), `createdAt`, `updatedAt`, `deletedAt`, `version` | |
| `shape` | | `shape`(`ShapeKind` 이름), `geometry`(`{"poly":[x0,y0,…],"closed":true}` 또는 `{"ellipse":[l,t,r,b,rot]}`), `style`(`ShapeStyle.toJson`) |
| `text` | | `text`, `style`(`TextBoxStyle.toJson`) |
| `image` | | `assetId`, `px`(`[w,h]`) |
| `math` | | `latex`, `style`(`MathStyle.toJson`), `engine`((v2.1) 항상 씀 — 없으면 `null`) |

예시(`shape`, 회전 0 사각형 — 키 순서는 JSON에서 의미 없음):

```json
{"id":"0193a1f0-…","pageId":"0193a1e2-…","type":"shape",
 "frame":[120.0,80.0,320.0,200.0,0.0],
 "shape":"rectangle",
 "geometry":{"poly":[120.0,80.0,320.0,80.0,320.0,200.0,120.0,200.0],"closed":true},
 "style":{"strokeColorArgb":4279900698,"strokeWidth":2.0,"strokeOpacity":1.0,"dash":"solid","fillColorArgb":null,"fillOpacity":1.0,"arrowHeads":"none"},
 "createdAt":1762300000000,"updatedAt":1762300000000,"deletedAt":null,"version":"…"}
```

- 종류별 키 이름(`style` 안 키 포함)은 CORE `entity_json` 골든과 SYNC 'JSON 키 대조' 시험(1차 T16)이 함께 검사한다. `style` 안 키는 각 `toJson`의 필드 이름(camelCase) 그대로다.
- (v2.1) 종류별 키 집합은 고정이다 — 값이 없어도 키를 쓴다(`engine: null`, `Recording.title: null`). SYNC `kPageObjectTypeKeys`와 CORE 골든이 같은 집합을 대조한다(`math` 골든에 `engine: null` 사례 포함).

손글씨 결과 JSON: `id`, `noteId`, `pageId`, `engineId`, `sourceRev`, `lines`(배열), `createdAt`, `updatedAt`, `deletedAt`, `version`. 녹음 JSON: v1.4 + `title`.

DB 스키마 v2(`kDatabaseSchemaVersion = 2`, 규칙 — CORE 내부, 이름은 CORE가 바꿀 수 있음):

| 테이블 | 열 | 비고 |
|---|---|---|
| `page_objects` | `id` PK, `page_id`, `note_id`(비정규화 — 영구 삭제·복사), `type`, `min_x`·`min_y`·`max_x`·`max_y`(= `bounds`), `data_json`(종류별 키 + `frame`), `asset_id`(이미지만, 참조·GC용), `created_at`, `updated_at`, `deleted_at`, `version`, `field_versions` | 색인 `(page_id, deleted_at)`, `note_id`, `asset_id` |
| `handwriting` | `id` PK(`hw_<pageId>`), `page_id`, `note_id`, `engine_id`, `source_rev`, `lines_json`, 시간 열, `version`, `field_versions` | |
| `recordings` | + `title` (NULL 허용) | `ALTER TABLE ADD COLUMN` |
| `recording_drafts` | `draft_id` PK, `recording_id`, `note_id`, `mime_type`, `started_at`, `chunk_count`, `bytes`, `active_ms`, `updated_at` | 기기 로컬, outbox·백업 제외 |
| `search_owners` · `search_units` | (v2.1 정정, CP-15) 소유자 `search_owners`(`source`, `owner_key`, `source_rev`, UNIQUE(`source`,`owner_key`)) + 단위 `search_units`(`id` INTEGER PK, `source`, `owner_key`, `seq`, `note_id`, `page_id`(pdf는 NULL), `body`, 정규화 열, UNIQUE(`source`,`owner_key`,`seq`)). PDF 글자 사각형은 줄인 정밀도로 SQLite 밖(블롭 저장소) 또는 압축 BLOB — CORE 선택, 7.4.5 크기 목표 | 파생, 기기 로컬 |
| `search_fts` | FTS5 `(g, content='', contentless_delete=1, tokenize='unicode61 remove_diacritics 0')`(v2.1 정정), rowid = `search_units.id` | 마이그레이션 단계의 `customStatement`로 만든다(drift `.drift` 파일·`sqlite_modules` 옵션은 쓰지 않아도 됨 — CORE 선택) |
| `strokes` | (변경 없음) | `stalePages`용으로 `(page_id, tool, updated_at)` 조회가 색인 범위 안인지 CORE가 확인 |

- `kNoteSchemaVersion`은 **1 그대로**다(조사 01 Q3 기본안). 객체가 든 노트도 옛 앱에서 읽기 전용이 되지 않는다. 배포된 옛 앱이 없고(실연결 전) 사용자 한 명이 모든 기기를 함께 갱신하기 때문이다.
- 마이그레이션 v1 → v2는 한 트랜잭션(1차 `runSchemaUpgrade`)이고, `dart run drift_dev make-migrations`가 만든 단계 도우미(`note_database.steps.dart` — (v2.1 정정) INFRA `generated_files`에 `*.steps.dart`)와 생성 시험을 커밋한다. **1차 v1 DB 고정 자료**(1차 통합이 `main`에 들어간 커밋의 코드로 만든 노트·획·PDF 에셋 — CORE가 R2-B2 전에 만든다)를 v2로 여는 시험을 VM과 Chrome 둘 다 둔다(V7). iPad에 1차 웹으로 쓴 실제 노트가 생길 수 있기 때문이다((v2.1) Hosting이 없어 아직 배포된 적은 없다 — U25).
- (v2.1) **업그레이드 직전 v1 사본**: 업그레이드 트랜잭션 전에 같은 저장소 안에 v1 사본을 만든다. (v2.2, C22-02 — CORE CP-16) 방법은 저장 방식마다 정한다 — **네이티브 파일 DB**: `VACUUM INTO '<nativeDatabasePath>-v1-backup.tmp'` 뒤 이름 바꾸기 `<nativeDatabasePath>-v1-backup`(있던 사본은 먼저 지움, 결과는 그대로 열리는 v1 SQLite 파일). **웹**: 블롭 저장소(`WebStorageConfig.blobDatabaseName` — 기본 `noteapp_blobs`)의 `db/v1-backup/` 접두사에 **정규 덤프**(≤ 4 MiB 조각, 마지막에 `meta`를 쓴다 — `meta`가 있어야 완전한 사본, 형식은 02-core 6.12.3·6.12.4). 웹 IndexedDB VFS 안의 `VACUUM INTO` 사본은 지울 길이 없고 열 때마다 메모리로 읽히므로 쓰지 않는다. 새 DB·메모리 DB는 사본을 만들지 않는다. 사본 만들기가 실패하면(용량·I/O) 이주는 그대로 진행하고 kv에 실패를 남긴다(개발자 표시·메뉴에 보임). kv에 사본 시각·방법·크기·정상 열기 횟수를 남기고, **정상 열기 5번 이상이면서 만든 지 7일이 지난** 첫 열기에서 자동 삭제하거나 개발자 메뉴('v1 DB 사본 내보내기·지우기' — INFRA, 아래 API)에서 지운다. `deleteLocalNoteData`는 사본도 지우고, 백업 내보내기에는 넣지 않는다. V7의 '정규 덤프 해시'는 같은 덤프 형식으로 낸다. 이주가 성공한 뒤 2차 버그로 데이터가 상해도 되돌릴 마지막 안전망이다(백업 **복원**은 이번 범위 밖). (총괄 기입 — v2.2 C22-01의 `dev_tools.dart` 블록은 6.12.4와 본문이 같다.)
- 옛 앱이 v2 DB를 열면 `NewerSchemaError` → 앱 전체가 열리지 않는다(1차 동작). 웹 배포를 되돌릴 때 주의(위험 8 #9).
- 검색 색인 채우기: 마이그레이션 직후 텍스트 상자는 없고, PDF는 `PdfSearchIndexer`가 백그라운드로 채운다(7.2.12). `search_state`(정규화 판·재구축 표시)는 CORE 메타 KV에 둔다.

### 4.9 `testing.dart` v2.1 · `testing_web.dart` (7.6 기반 단계 시험 도우미 — CORE 몫)

`// 계약 v2.1 7.6 원문` (CORE 부분만 — `ink_engine`·`ink_recognition`·`media_io`의 시험 도우미는 INK·LIBRARY·PDF 계획서)

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
```

```dart
// CORE 확정 세부 — testing.dart v2.1 · testing_web.dart (원문 시그니처 그대로, 동작 세부)
final class FakeAudioRecorder implements AudioRecorderService {
  // abandon() completes after the draft chunks queued by advance() are stored.
  // Chunk interval of the fake = 1 s (one 16-byte chunk per advanced second), so the 7.2.4
  // 'recently updated' window is max(10 s, 5 × 1 s) = 10 s measured on store.clock (6.8.3).
}
// StrokeFixtures (v1.4) unchanged. createFakeNoteStore: v1.4 arguments + nothing new.
//
// testing_web.dart (imports drift web + package:web; browser tests only — INFRA R4 exception):
//   openWebTestNoteStore(name): databaseName 'webtest_<name>', blobs 'webtest_<name>_blobs',
//     WebStorageConfig default asset URLs (sqlite3.wasm, drift_worker.js next to the test page),
//     the stored HLC node (a new random one for a new database — as openNoteStore),
//     requestPersistentStorage false. Opening the same name again reopens the same data
//     (V16 '새 컨테이너'). [name] must match ^[A-Za-z0-9_-]{1,40}$ (ArgumentError otherwise).
//   deleteWebTestNoteStore(name): deleteLocalNoteData of that config (the store must be closed).
//   Assets: a package that uses it runs CORE's script into its own test/web
//     (`dart run <note_core>/tool/prepare_web_test.dart --out test/web` — 6.18.1).
```

동작 세부(시계·상태 순서·M-1 순서·초안·`pendingDrafts` 제외 규칙)는 6.8, 가짜 저장소 v2는 6.17, 브라우저 시험 자산 전달은 6.18.1.

### 4.10 provider 추가 (7.2.4 · 7.2.5 — `package:riverpod` 3.4.3)

| provider | 타입 | 값 | override |
|---|---|---|---|
| `audioRecorderServiceProvider` | `Provider<AudioRecorderService>` | `const UnsupportedAudioRecorder()` | `mediaIoOverrides()`만(X28, 7.3.3) |
| `audioPlaybackServiceProvider` | `Provider<AudioPlaybackService>` | `const UnsupportedAudioPlayback()` | `mediaIoOverrides()`만 |
| `recordingRepositoryProvider` | `Provider<RecordingRepository>` | `ref.watch(noteStoreProvider).recordings` | 없음(7.3.3 마지막 행) |
| `noteRecordingsProvider` | `StreamProvider.autoDispose.family<List<Recording>, NoteId>` | `watchRecordings(noteId)`, `retry: noRetry`(1차 저장소 스트림 규칙) | 없음 |
| `handwritingRepositoryProvider` | `Provider<HandwritingRepository>` | `store.handwriting` | 없음 |
| `searchIndexProvider` | `Provider<SearchIndex>` | `store.search` | 없음 |

- 이름은 1차처럼 `name:` 인자 = 변수 이름이다(1차 6.16, provider 이름 검사 시험).

### 4.11 진입점 · `api_surface_test` v2 (7.1)

| 진입점 | 2차에 더하는 이름 |
|---|---|
| `note_core.dart` | `PagePoint`, `ElementFrame`, `PageObject`, `ShapeObject`, `TextBoxObject`, `ImageObject`, `MathObject`, `UnknownObject`, `PageObjectLimits`, `ShapeKind`, `LineDash`, `ArrowHeads`, `ShapeStyle`, `ShapeGeometry`, `PolylineGeometry`, `EllipseGeometry`, `TextAlignKind`, `TextBoxStyle`, `MathStyle`, `AddObjects`, `UpdateObjects`, `RemoveElements`, `RecordingRepository`, `RecordingDraftStore`, `RecordingDraft`, `AudioSupport`, `RecorderPhase`, `RecorderStatus`, `AudioRecorderService`, `PlaybackPhase`, `PlaybackStatus`, `AudioPlaybackService`, `UnsupportedAudioRecorder`, `UnsupportedAudioPlayback`, `HandwritingLine`, `HandwritingText`, `HandwritingRepository`, `SearchSource`, `SearchUnitDraft`, `SearchIndexWriter`, `PageSearchHit`, `SearchIndexStatus`, `SearchIndex`, `SearchText`, (v2.1, CP-10) `SearchTextMapping`, `ImageImportSource`, `ImportedImage`, `ImageImportLimits`, provider 6개(4.10) |
| `testing.dart` | `PageObjectFixtures`, `FakeAudioRecorder`, `FakeAudioPlayback` |
| (v2.1) `testing_web.dart` (새 진입점 — C2-39) | `openWebTestNoteStore`, `deleteWebTestNoteStore` |
| `dev_tools.dart` | (v2.1, CP-17) `V1DatabaseCopyInfo`, `v1DatabaseCopyInfo`, `readV1DatabaseCopy`, `deleteV1DatabaseCopy`(6.12.4 — INFRA 개발자 메뉴). 이름 추가 없이 (CP-9, P-C) `seedSyntheticNote`에 이름 있는 인자 `int objectsPerPage = 0` |
| `testing_vm.dart` | 없음 |

- `api_surface_test`(1차 T4·T5)에 위 이름을 모두 참조하는 컴파일 검사를 더하고, 내보내지 않아야 할 이름(`test/support/absent_names.dart`)에 `normalizeForSearch`, `DriftSearchIndex`, `MemorySearchIndex`, `SearchIndexer`, `FileBlobDatabase`, `upgradeV1ToV2`, `searchMatches`(내부 일치 판정), `ftsCandidateMatches`(내부 FTS 후보 흉내 — 6.10.6), `canonicalDump`(내부 정규 덤프 — 6.12.4), `SearchRectsCodec`(내부 사각형 형식 — 6.10.3)를 더한다. `testing_web.dart`는 `@TestOn('browser')` 시험 하나(`test/web/testing_web_browser_test.dart`)가 두 이름을 참조해 컴파일·동작을 본다(VM `api_surface_test`는 브라우저 전용 진입점을 import하지 않는다).
- 이름 충돌 검사(R14): `TextBox`(dart:ui)·`Ink`(material_ui)를 피한 이름이다(7.2.0). `SearchText`·`SearchTextMapping`·`PageSearchHit`·`V1DatabaseCopyInfo`는 9개 공개 진입점에서 겹치지 않는다 — B2-α 커밋 전에 `ws check` R14로 확인한다.


---

## 5. 사용하는 다른 영역의 계약

CORE는 형제 패키지를 import하지 않는다(7.1 — 허용 의존 '—'). 그래서 이 절의 '사용하는 계약'은 ① 다른 영역이 CORE의 타입·명령을 어떻게 쓰기로 했는가(CORE가 그 쓰임을 받쳐야 함), ② 다른 영역이 지키기로 한 동작 보장 중 CORE 데이터의 전제가 되는 것, ③ CORE가 맞춰야 하는 다른 영역의 형식이다. 표의 행은 7장 원문을 그대로 옮겼다.

### 5.1 제공 → 소비 (7.3.1 중 CORE 행)

| # | 제공 | 소비 | 인터페이스 | 핵심 규칙 |
|---|---|---|---|---|
| X18 | CORE | EDITOR | `PageObject` 계열, `AddObjects`·`UpdateObjects`·`RemoveElements`·`ClearPage.includeObjects`, `PageContent.objects` | 7.2.3 명령 매핑, C-11 |
| X19 | CORE | EDITOR, media | 오디오 포트(`audioRecorderServiceProvider`·`audioPlaybackServiceProvider`), `RecordingRepository`, `noteRecordingsProvider` | R-1~R-8, M-1·M-2 |
| X20 | CORE | media | `AssetStore.put(audio/image)`, `RecordingRepository.createRecording`, `RecordingDraftStore`, `ImageImportLimits` | 에셋 먼저, 녹음 행은 그 뒤(M-1) |
| X21 | CORE | LIBRARY | `LibrarySearchResult.pages`, `PageSearchHit` | 결과를 그대로 표시(1차 L-1) |
| X22 | CORE | recog | `HandwritingRepository`(`stalePages`·`put`·(v2.1) `update`·`notesWithStalePages`), `HandwritingText.sourceRevOf`·`isRecognitionInput`, `NoteStore.changes` | 웹에서는 쓰기 없음 |
| X23 | CORE | PDF | `SearchIndexWriter`(source pdf), `PageContent.objects`, 이미지 에셋 | 사각형은 PDF 페이지 비율 좌표 |
| X24 | CORE | SYNC | `EntityKind.pageObject`·`handwriting`, JSON(7.2.7), outbox 힌트, `UnknownObject` | 7.2.8 매핑, S-13 |

### 5.2 INK (`ink_engine`)

| # | 주체 | 보장 |
|---|---|---|
| K-6 | INK | 모든 `PageObject`의 렌더 외곽 ⊆ CORE `bounds`. 텍스트는 frame으로 자르고, 수식은 frame 안에 contain으로 맞추고, 도형은 둥근 이음·캡으로 `strokeWidth·0.75` 안에 그린다. 새 펜 5종도 1차 K-1을 지킨다(불변식 시험에 추가) |

- **CORE가 받치는 것**: K-6의 기준인 `PageObject.bounds` 공식(7.2.2 `ShapeObject.bounds`, 나머지는 `frame.bounds`)을 CORE가 정의하고 DB `page_objects.min_x…max_y`에 저장한다(1차 K-1의 `Stroke.bounds`와 같은 역할). INK 불변식 시험은 CORE `bounds`를 기준으로 쓴다. 공식을 바꾸면 모든 기기의 저장값이 달라지므로 바꾸지 않는다(6.2.4).
- (v2.1, CD2-07) **객체 변형의 단일 규칙**: INK 선택·대기 표시 미리보기는 CORE `PageObject.transformed(m, scaleWidth:)`를 그대로 부른다(INK 검토 M-2 — 미리보기와 저장 결과가 같은 함수). 캘리그래피 획 미리보기도 CORE `Stroke.transformed`를 다시 부르면 펜촉 각이 함께 돈다(C2-38, 6.2.7).
- **INK가 내는 명령**(7.2.9 `InkEdit.toCommand` v2.1 원문):

| `InkEditKind` | `toCommand()` (v2.0) |
|---|---|
| `addShape` | `core.AddObjects(pageId: …, objects: addedObjects)` |
| `eraseStrokes`, `deleteStrokes` | (v2.1) `removedObjectIds`가 비면 `core.RemoveStrokes`(v1.4), 아니면 `core.RemoveElements(elementIds: removedIds)` |
| `splitStrokes` | (v2.1, CP-INK-2) `removedObjectIds`가 비면 v1.4(`SplitStrokes`), 아니면 `core.CompositeCommand([SplitStrokes(획 조각) 또는 RemoveStrokes, RemoveElements(removedObjectIds)])`(빈 쪽은 뺌) — 한 제스처 = 한 명령 |
| `transformStrokes` | `core.TransformElements`(획 + 객체 — 이름은 v1.4 유지) |
| `recolorStrokes` | `core.CompositeCommand([RestyleStrokes, UpdateObjects])`(빈 쪽은 뺌) |
| `duplicateStrokes` | `core.CompositeCommand([AddStrokes, AddObjects])`(빈 쪽은 뺌) |
| 그 밖 | v1.4 |

- 펜 extras: 새 키(`nibAngleDeg`·`nibAspect`·`rollNib`·`dash`·`laserFadeMs`·`tapeStyle`)는 INK `InkStyleExtras`가 소유하고 CORE는 `StrokeStyle.extras` 맵을 그대로 저장·동기화한다. 예외 하나: (v2.1, C2-38) `Stroke.transformed`가 캘리그래피 획의 `nibAngleDeg`를 바꾼다 — CORE는 키 문자열을 내부 상수(`'nibAngleDeg'` — 1차 `StrokeStyle.defaultsFor(calligraphy)`의 extras와 같은 글자)로 들고, INK `InkStyleExtras.nibAngleDeg`와 같은 값인지는 통합 2단계 시험(8.3 I-1)이 본다. `StrokeStyle.defaultsFor`의 P1 5종 값은 v1.4 그대로이고, 값 조정은 INK의 변경 요청으로만 한다(7.2.9 문단).
- 텍스트 상자 높이: `TextBoxObject.frame` 높이는 EDITOR가 INK `InkTextLayout.measure`로 잰 값을 쓴다. CORE는 높이를 다시 계산하지 않는다(글꼴·레이아웃은 INK 몫). (v2.1, CP-2) `transformed`가 글자 크기와 줄바꿈 폭을 같은 배율로 바꾸므로 비율 유지 크기 조절 뒤에도 frame 높이가 내용과 맞는다. 수식은 INK `InkMathRenderer.validate(latex) == null`을 EDITOR·recog가 확인한 뒤 넣는다 — CORE는 `latex` 길이만 검사한다.
- 시험용 가짜: 없음(CORE는 INK를 쓰지 않는다).

### 5.3 EDITOR (`feature_editor`)

EDITOR 명령 매핑(7.2.3 원문 '04-editor 5.1 표에 더할 것' — CORE 명령 해석기·되돌리기가 받쳐야 하는 사용 방식):

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

| # | 주체 | 보장 |
|---|---|---|
| E-5 | EDITOR | 펜 다운 시 R-1 규칙으로만 `InkStrokeMeta`를 채운다. `offsetNowMs()`는 펜 다운 이벤트 처리 안에서 동기적으로 읽는다 |
| E-6 | EDITOR | 텍스트 상자 편집 세션(포커스 들어옴 → 나감) 1회 = 명령 1회 = 되돌리기 1단계. 편집 중에는 INK에서 그 상자를 숨긴다(`setHiddenObjectIds`) |

- E-6(편집 세션 1회 = 명령 1회): CORE는 `AddObjects`/`UpdateObjects`/`RemoveElements` 하나를 되돌리기 1단계로 기록한다. 편집 중의 글자 하나하나는 명령이 아니다.
- E-5·R-1: 획의 `recordingId/recordingOffsetMs`는 EDITOR가 INK 메타로 넘긴 값 그대로 저장한다. CORE는 그 녹음 행이 있는지 확인하지 않는다(R-7 — 녹음 행은 정지 뒤에 생긴다).
- (v2.1) 명령 모양: EDITOR는 이름 있는 인자로 만든다(`RemoveElements(pageId: p, elementIds: [id])`, `ClearPage(pageId: p, includeObjects: true)` — CP-1·CP-E5). 04-editor의 집합 리터럴(`{id}`)은 `List`로 바뀐다(CD2-06).

### 5.4 PDF (`pdf_io`) · 미디어 (`media_io`)

| # | 주체 | 보장 |
|---|---|---|
| M-1 | media | `stop()`은 에셋(`AssetStore.put`)을 먼저 쓰고 그다음 `createRecording`을 부른다. `offsetNowMs()`는 한 녹음 안에서 단조 증가하고 일시정지 구간을 빼며, `durationMs`는 파일 안 타임라인 길이다(R-2·R-3). (v2.1) 저장(`put`·`createRecording`)에 실패하면 초안을 지우지 않고 예외로 끝난다 — 다음 실행 복구가 같은 `recordingId`로 마무리한다 |
| M-2 | media | 웹에서 탭이 가려진 동안 녹음하지 않는다: 가려지는 즉시 `pause()`(`interrupted = true`), 돌아와도 자동 재개하지 않는다. 녹음 중 Screen Wake Lock. 웹 녹음 조각은 `webDraftChunkMs`(1초)마다 `RecordingDraftStore.append`로 쓰고, 탭이 닫히거나 새로 고침되면 다음 실행 때 INFRA가 `pendingDrafts()` → `recoverDraft()`로 **묻지 않고** 녹음으로 만든다(7.2.12 — 잃는 것은 마지막 1초 이하). (v2.1 정리) 돌아왔을 때의 '이어서 녹음할까요?' 안내(7.4.2)는 가려짐 일시정지에 대한 것이고 복구와 다르다 |
| M-3 | media | 이미지 에셋은 `ImageImportLimits`를 지킨다(긴 변 2048 px, 8 MiB, JPEG/PNG만) |
| M-4 | media | (v2.1) 웹 녹음의 `durationMs`는 파일 안 타임라인(WebM 블록 타임코드)에서 계산한다(R-3). 정지·복구는 같은 녹음 바이트를 전체 크기로 두 벌 넘게 동시에 들지 않는다(앞 단계 버퍼를 버리고, (v2.2, C22-05 — CP-PDF-13) 길이 보정은 머리만 새로 만들어 원본 나머지와 한 번 복사해 합친 뒤 원본을 바로 버린다 — `AssetStore.put`이 연속한 `Uint8List` 한 벌을 받으므로 그 순간만 두 벌). 다른 탭이 녹음 중인 초안을 복구하지 않는다(7.2.4 `pendingDrafts`) |

PDF 전역 색인(7.2.12 v2.1 원문 발췌):

```dart
/// Library-wide PDF text index (1차 7.8 이후 항목): watches PDF assets / PdfBackground pages,
/// extracts with PdfTextService, writes core.SearchIndexWriter (source pdf, rects as page
/// fractions). Skips owners whose sourceRev is current. Idle-time, one PDF page per slice.
/// (v2.1) Pauses while SearchIndex.status.rebuilding is true (drops its queue) and re-judges every
/// asset afterwards. The public constructor stays as below — CP-PDF-1 rejected: the document pool
/// and the schedule gate are injected inside pdf_io (provider / src-only factory), no new public
/// type. dispose() is idempotent.
final class PdfSearchIndexer {
  PdfSearchIndexer(core.NoteStore store);
  void start();
  Future<void> dispose();
}
final pdfSearchIndexerProvider = Provider<PdfSearchIndexer>(/* started by INFRA PdfModule */);
```

- **M-1 순서**: CORE `createRecording`은 그 `assetId`의 에셋 행이 이미 있고 `type == audio`인지 확인한다(없으면 `ArgumentError` — 6.6). 그래서 media_io가 순서를 바꾸면 시험에서 바로 드러난다. (v2.1) 저장 실패 뒤 다음 실행의 복구가 같은 `recordingId`로 `createRecording`을 다시 부르면 CORE는 이미 있는 행을 돌려준다(멱등 — 6.6).
- **M-2 웹 조각**: media_io 웹 녹음기는 `RecordingDraftStore.begin` → 1초마다 `append`(`activeMs` 포함, 일시정지 중에는 빈 조각으로 `activeMs`·`updatedAt`만 갱신) → 정지 때 `readAll` → `AssetStore.put(audio)` → `createRecording` → `discard`. 남은 초안은 다음 실행 때 INFRA `MediaModule`이 `pendingDrafts()` → `recoverDraft()`로 **묻지 않고** 녹음으로 만든다(v2.1 M-2 정리). CORE는 조각을 키 하나씩 원자적으로 쓰고, `begin`은 행보다 먼저 블롭 쪽 `rd/<draftId>/meta`를 쓰며, `append`의 Future는 조각 바이트가 저장되고 행 갱신이 커밋된 뒤에 완료한다(6.7). 웹에서 행의 IndexedDB 반영은 커밋보다 수 ms 늦을 수 있어 `listDrafts`가 조각·meta로 맞춘다(6.7.3).
- **M-4 버퍼**: CORE `readAll`은 조각을 하나씩 읽어 한 버퍼에 이어 붙인다 — 동시에 드는 것은 결과 한 벌 + 조각 하나다(6.7.3). 그 뒤 버퍼를 버리는 것은 media 몫이다.
- **네이티브 녹음**: 네이티브는 `record`가 파일에 직접 쓰고 초안 저장소에는 **행만**(조각 0) 쓴다(PDF 6.9.5 — 12.2 Q4 답). CORE는 조각 0 초안을 정상 상태로 유지하고 `listDrafts`에 그대로 낸다. 파일로부터의 복구는 media 몫이다.
- **M-3**: 이미지 에셋 한도는 media_io가 지키고, (v2.1, CP-11) CORE 로컬 `AssetStore.put(type: image)`도 `storedMimeTypes` 밖을 `ArgumentError`로 막는다(6.15.2).
- **PDF 정규화**: C2-27 — PDF 시험이 `PdfTextNormalizer.normalizeQuery(x) == SearchText.normalize(x)`를 같은 입력 표로 확인한다. CORE `SearchText.normalize`는 1차 PDF 6.10.1 단계 1~5 + 앞뒤 공백 제거와 같게 만든다(6.10.1). (v2.1, CP-10) PDF는 하이라이트용으로 `SearchText.normalizeMapped`를 감싸 쓸 수 있다.
- **PDF 사각형·소유자**(v2.1, CD2-11): `SearchUnitDraft.rects`는 PDF 페이지 비율 좌표(X23)이고 `rects.length == body.length` 또는 빈 목록이다. CORE는 1/65535 정밀도로 줄여 **SQLite 밖**(블롭 저장소)에 두고(6.10.3), 노트 페이지 pt로 바꿀 때 `pdfPageAspect`(CP-3)로 contain·가운데를 맞춘다(6.10.4). `replaceUnits(pdf, key, [], sourceRev: …)`도 소유자 행을 남긴다(스캔 쪽·`#0` 완료 표시 — 06-pdf 6.4.2). `sourceRev`는 꼬리(`:x<extractorVersion>`, CP-PDF-2)까지 문자열 그대로 비교한다.
- **재구축 중 멈춤**: `PdfSearchIndexer`는 `status.rebuilding`이 참인 동안 멈춘다(원문). CORE는 `rebuild()` 시작 전에 `rebuilding: true`, 마지막 작업 커밋 뒤 `false`를 낸다(6.10.5).

### 5.5 LIBRARY (`feature_library`) · 인식 (`ink_recognition`)

| # | 주체 | 보장 |
|---|---|---|
| G-1 | recog | 웹에서 ML Kit을 부르지 않는다(조건부 import + `RecognizerUnsupported`). 인식 실패는 EDITOR로 예외를 던지지 않고 recog 자기 창에서 문구로 보인다 |
| G-2 | recog | 색인기는 사용자가 쓰는 페이지를 방해하지 않는다: 마지막 입력 3초 뒤, 한 번에 한 줄, 앱이 뒤로 가면 멈춘다. (v2.1) 먼저 `stalePages`로 낡았는지 보고(점 디코드 없음) 낡았을 때만 페이지를 읽고, 줄 사이마다 양보한다 |
| G-4 | recog · CORE | (v2.1) 손글씨 결과의 로컬 쓰기(색인기·변환 창)는 `HandwritingRepository.update`로 저장된 값과 한 트랜잭션에서 병합한다 — 그 사이 들어온 확정 줄·원격 결과를 덮지 않는다. 변환 창의 복사 경로는 `NoteStore.flush()` 뒤 `loadPage`로 방금 쓴 획까지 본다. 확정 줄 유지 규칙은 7.2.5 `userConfirmed` 주석 |

색인기(7.2.11 v2.1 원문 발췌 — CORE `HandwritingRepository`의 주 사용자):

```dart
// --- background indexing ---
final class HandwritingIndexer {
  HandwritingIndexer({required core.NoteStore store, required HandwritingRecognizer recognizer,
      required ValueListenable<bool> enabled,
      ValueListenable<bool>? foreground});        // (v2.1, CP-L10) default: AppLifecycleListener
  /// Watches NoteStore.changes (stroke → pageId; (v2.1) handwriting → abandon that page's job and
  /// requeue it), waits for idle (≥ 3 s no local input on that page, 30 s after a remote change),
  /// asks stalePages first (no point decode), recognizes line by line yielding between lines, writes
  /// with HandwritingRepository.update (merged with what is stored — G-4). (v2.1) Fresh = same
  /// sourceRev and language; another engine id / version / device is fresh. Start-up catch-up:
  /// notesWithStalePages(). Never runs on web. dispose() is idempotent.
  void start();
  Future<void> dispose();
  ValueListenable<HandwritingIndexerStatus> get status;
}
// (v2.1, CP-L1) status fields (05-library 4.4.1 — toString() is the one-line overlay form):
enum HandwritingIndexerPhase { off, disabled, waitingModel, idle, waitingInput, recognizing, paused }
@immutable final class HandwritingIndexerStatus {
  const HandwritingIndexerStatus({this.phase = HandwritingIndexerPhase.off, this.languageTag,
      this.queuedPages = 0, this.indexedPages = 0, this.failedPages = 0, this.currentPageId,
      this.lastError});
  final HandwritingIndexerPhase phase; final String? languageTag;
  final int queuedPages, indexedPages, failedPages; final String? currentPageId, lastError;
}
/// (v2.1, CP-L2 = INFRA CP4) Developer overlay lines; same shape as mediaDevOverlayLinesProvider.
final recognitionDevOverlayLinesProvider = Provider<ValueListenable<List<String>>>(/* … */);
final handwritingIndexerProvider = Provider<HandwritingIndexer?>(/* null unless recognizer available */);
```

- `HandwritingIndexer`는 `NoteStore.changes`(획 `EntityChange.pageId` 항상 — 1차 v1.1)로 페이지를 모으고, 유휴 때 `stalePages(noteId)` → 줄 인식 → (v2.1) `update`로 저장된 값과 병합해 쓴다(G-4). 시작 때 따라잡기는 `notesWithStalePages()`다. CORE는 둘 다 **점 디코드 없이** 답한다(6.9.3). 웹에서는 색인기가 돌지 않으므로(G-1) 웹 CORE에는 로컬 쓰기가 오지 않는다(실연결 뒤에는 원격 적용으로 온다).
- 검색 결과 화면은 CORE 결과를 그대로 보인다(1차 L-1). 그래서 결과 순서·발췌·사각형은 CORE가 정하고, 실제 저장소와 가짜 저장소가 같은 함수·같은 후보 순서를 쓴다(6.10.6, CP-14).
- (v2.1) 확정 줄 유지 규칙(7.2.5 `userConfirmed` 주석)의 주인은 recog다. CORE `update`는 병합 함수(`transform`)를 한 쓰기 트랜잭션 안에서 부를 뿐 규칙을 해석하지 않는다(6.9.4). '신선함 = `sourceRev` + 언어'도 recog의 판정이다 — CORE `stalePages`는 `sourceRev`만 비교한다(언어 꼬리는 recog가 `engineId`로 본다).

### 5.6 SYNC (`sync_engine`)

동기화 문서 매핑(7.2.8 v2.1 원문 — CORE는 outbox 힌트·JSON 키·영구 삭제를 맞춘다):

원격 구조(Firestore `users/{uid}/changes/{chunkId}` + 코덱 v1 이진 페이로드)는 바뀌지 않는다. 문서 필드에 엔티티 종류가 없으므로 Firestore·Storage 규칙도 바뀌지 않는다(조사 01 3.11). 코덱 형식 `fmt`는 **1 그대로** 둔다 — 배포된 옛 앱이 없고, 이번에 '모르는 종류 보류'가 들어가므로 이후 종류 추가에도 `fmt`를 올릴 필요가 없다.

| `EntityKind` | 청크 범위 | outbox 힌트 (CORE, 1차 7.2.10 규칙 확장) | 병합 단위(필드 묶음) | 하위 기록·게이트 |
|---|---|---|---|---|
| `stroke` | 노트 | v1.4 | v1.4 (`{recordingId, recordingOffsetMs}`) | v1.4 |
| `pageObject` | 노트 | `noteId` 항상, `pageId` 항상 | **객체 단위 하나**: (v2.1, CP-S1) 메타 키와 `pageId`·`deletedAt`·`engine`을 뺀 **나머지 키 전부**(모르는 키 포함 — 알려진 키로는 `{type, frame, shape, geometry, style, text, assetId, px, latex}`) + 따로 `{engine}`. 같은 객체를 두 기기가 동시에 고치면 나중 것이 이긴다(삭제 규칙은 v1.4 그대로) | (v2.1 정정) 노트 영구 삭제 때 함께(`purge_guard`·`record_gate`에 추가 — 페이지는 소프트 삭제만 있다). 삭제된 페이지에 상대가 모르는 객체가 있으면 페이지를 되살림(`page_resurrection` — 획과 같은 근거) |
| `handwriting` | 노트 | `noteId` 항상, `pageId` 항상 | 하나: (v2.1, CP-S1) 메타 키와 `noteId`·`pageId`·`deletedAt`을 뺀 나머지 전부(알려진 키로는 `{engineId, sourceRev, lines}`) | (v2.1 정정) 노트 영구 삭제 때 함께. 되살림 근거가 **아니다**(파생 데이터). (v2.1) 편집으로 세지 않는다 — outbox 판정과 영구 삭제 보호의 '최근 보냄'(10분) 모두에서 손글씨만 실린 청크의 범위를 뺀다(SYNC 검토 M-3: 안드로이드 색인기의 업로드가 사용자가 지운 노트를 되살리지 않게) |
| `recording` | 노트 | v1.4 | v1.4 + `{title}` 따로 | v1.4 |
| (모르는 종류) | — | — | — | **보류**(아래) |

- 정렬(`chunk_packer.kindOrder`): `folder, note, page, penPreset, setting, asset, recording, stroke, pageObject, handwriting`.
- 이진 필드(`blobKeys`): 새 종류에는 없다(객체 JSON에 점 배열을 넣지 않는다).
- **모르는 종류 보류(S-13)**: `ChunkCodec`은 모르는 `kind` 기록을 실패시키지 않고 `UnknownKindRecord(kind, rawJson)`로 디코드한다. 다운로드 파이프라인은 같은 청크의 나머지 기록을 적용하고, 모르는 기록만 메타 KV(`sync.heldRecords`)에 보관한 뒤 `SyncIssueCode.needsAppUpdate`를 한 번 낸다. 앱이 갱신되어 그 종류를 알게 되면 보관분을 순서대로 다시 적용한다. 커서는 정상 진행한다(청크를 버리지 않는다). (v2.1, CP-S2 보강) ① 보관 단위는 기록 바이트(헤더 JSON + 이진 필드). ② 한 청크의 모르는 기록은 **전부 보관하거나 전부 표시**한다 — 상한에 걸리면 그 청크는 기록 없이 '되감기 표시'(종류·가장 이른 청크 시각)에만 올리고, 앱 갱신 뒤 커서를 되돌려 통째로 다시 받는다. ③ 보관은 메타 키 여러 개로 나눈다(키당 < 256 KiB, 총 상한 2 MiB). 깨진 값을 읽으면 '모든 종류 되감기 표시'로 바꾼다(비싸지만 잃지 않음). ④ 압축은 모르는 종류 기록이 든 청크를 지우지 않는다. ⑤ 다시 적용은 '로그인 상태로 연결할 때, 받기 전에' 하고, 세션 중복 제거 목록(LRU)에 넣지 않으며, 기존 `sync.held`를 풀지 않는다. 다시 적용 중 미래 시각(K1)에 걸린 기록은 보관에 남겨 다음 연결에서 다시 시도한다(원래 청크의 존재에 기대지 않음).
- 모르는 `type`의 `pageObject`는 CORE가 `UnknownObject`로 받아 저장·동기화하므로 SYNC 입장에서는 일반 기록이다(C-12).
- 에셋: 이미지·오디오는 1차 에셋 파이프라인 그대로(업로드 상한 300 MiB — 64 kbps 3시간 녹음 86 MB에 여유). `recording_drafts`·`search_units`·`search_fts`는 기기 로컬이라 동기화 대상이 아니다.
- SYNC T16 'JSON 키 대조'(1차)를 새 두 종류에도 돌린다. (v2.1, CP-S1) `handwriting`: CORE `toJson` 키 집합 = `FieldUnits.keysOf(kind)`. `pageObject`: 알려진 4종 골든 키의 합집합 = `keysOf(pageObject)`, 각 골든 키 = `kPageObjectTypeKeys[type]`, `unknown`은 키 대조에서 빼고 `SyncDoc` 왕복만 본다(R2-B7a에서). 이후 라운드에 두 종류에 키를 더해도 따로 병합 단위를 만들지 않는다('나머지 전부' 단위에 들어간다 — 판이 다른 앱끼리 승자가 갈리지 않게).

| # | 주체 | 보장 |
|---|---|---|
| S-13 | SYNC | 모르는 `kind` 기록은 그 기록만 보류하고 같은 청크의 나머지는 적용한다. 보류분은 앱 갱신 뒤 다시 적용된다. (v2.1) 보류는 청크 단위 전부/전무이고 넘치면 되감기 표시다 — 어느 경로로도 기록을 잃지 않는다(7.2.8) |

- **CORE가 맞추는 것**: ① 새 두 종류의 outbox·`EntityChange` 힌트(`noteId`·`pageId` 항상 — 6.13), ② `toJson` 키 집합을 고정(골든 — SYNC 'JSON 키 대조'가 `FieldUnits.keysOf(kind)`·`kPageObjectTypeKeys`와 비교, (v2.1) `math`의 `engine`·녹음 `title`은 값이 없어도 키를 씀), ③ 노트 영구 삭제 때 객체·손글씨 결과도 지움(6.14.2 — 페이지는 소프트 삭제만), ④ `UnknownObject` 왕복(C-12).
- SYNC 시나리오 시험(T16-v2)은 실제 CORE 2개(`openTestNoteStore`)를 쓴다. CORE DB v2(T24)·행 변환(T26)·동기화 창구(T28)가 들어오는 대로 SYNC는 개발 중 CORE 커밋을 읽기만 한다(8.2 이정표 커밋). 그 전에는 SYNC 자기 `fake_sync_store`(v2 종류)로 개발한다.
- (v2.1) R2-B7a(SYNC switch 패치)의 바탕은 **B2-α 해시**다(SYNC 검토 X-4 — 8.1). R2-B2 + R2-B7a + R2-B2i는 한 묶음으로 병합된다(7.0.2). SYNC의 새 종류 디코드·키 대조 시험(CP-S9)은 B2-β JSON 골든 커밋 뒤에 돈다.

### 5.7 INFRA (앱 셸 · 빌드 · 시험 도구)

| 계약 | CORE에 대한 의미 |
|---|---|
| R2-B2i | `app/test/fakes/counting_note_store.dart`에 `recordings`·`recordingDrafts`·`handwriting`·`search` 위임 4줄(7.0.2). getter 이름은 원문 그대로이고, CORE는 **B2-α 해시**를 알린다(8.1 — INFRA·SYNC의 묶음 패치 바탕) |
| 7.2.6 문단 | 앱 셸이 `path_provider`의 앱 지원 디렉터리로 `nativeDatabasePath`·`nativeAssetDirectoryPath`를 넘긴다. CORE는 두 경로가 모두 있을 때만 파일 저장을 열고, (v2.1) 블롭 루트 디렉터리가 없으면 **CORE가 만든다**(6.15.3). 두 경로를 넘기는지는 INFRA 정적 시험(1차 셸은 넘기지 않아 1차 APK가 노트를 저장하지 못했다 — 검토 S-11) |
| 7.3.3 마지막 행 | '`core.recordingRepositoryProvider` 등 CORE 새 provider — `noteStoreProvider`에서 파생(override 없음)'. CORE provider 6개 중 override되는 것은 오디오 포트 둘뿐이다 |
| 7.3.3 모듈 순서 | `core`가 첫 모듈. 오디오 provider는 `MediaModule`만 override — 꺼진 기능(D14, (v2.1) `FEATURE_MEDIA`는 녹음만 — D17)이면 CORE 기본값 `Unsupported*`가 남는다 |
| 1차 7.4.9 웹 자산 | `app/web/sqlite3.wasm`(sqlite3 3.8.0, SQLite 3.54.1, sha256 `efd308be…`)에 FTS5가 있다 [확인 — 조사 01 4.1]. 바꾸지 않는다 |
| `workspace_rules.yaml` | (v2.1 정정, 검토 S-2) drift_dev 2.35.2 `make-migrations`의 단계 도우미는 `lib/src/storage/db/note_database.steps.dart`다(`make_migrations.dart` 524–525 `p.setExtension(dbClassFile, '.steps.dart')` [확인]). INFRA R2-B1이 `generated_files`에 `*.steps.dart`를 더한다(지금 목록은 `*.g.dart`·`*.freezed.dart`·`schema_versions.dart` — 통합 HEAD 83행 [확인]). `lib_exceptions`에 `note_core/lib/testing_web.dart`(R4 — C2-39). CORE의 `dart:io`는 `*_native.dart`·`testing_vm.dart`·`tool/`에만(R4 `native_suffixes`) |
| 위험 9(개요 8장)·7.8 B-1 | 실제 노트가 있는 출처(live)에 2차를 배포하기 전 '백업 내보내기' 안내, v2 이후 웹 배포 되돌리기 금지 — INFRA 안내서 08. CORE는 `NewerSchemaError` 분류(1차 6.18)를 그대로 두고, (v2.1) 업그레이드 직전 v1 사본을 남긴다(6.12.4) — INFRA 개발자 메뉴 'v1 DB 사본 내보내기·지우기'가 `dev_tools.dart`의 CP-17 함수를 부른다 |
| V5·V6 | 앱 스모크 v2는 메모리 CORE(실제 저장소 `inMemory`)를 쓴다 — 객체·녹음(가짜 녹음기)·검색이 실제 CORE에서 돈다. (v2.1, 검토 X-4·X-6) `FakeAudioRecorder`를 실제 메모리 CORE와 `testWidgets`에서 쓰면 에셋 `put`이 idb_shim 메모리 IndexedDB 타이머를 거치므로 `tester.runAsync` 또는 시간 진행(`pump`)이 필요하다(6.8.3) |
| 7.4.6 Chrome 시험 | (v2.1) `testing_web.dart`를 쓰는 다른 패키지의 Chrome 시험은 자기 `tool/prepare_web_test.dart`에서 CORE 스크립트를 `--out test/web`으로 부른다(6.18.1) — `ws test`가 멤버의 준비 스크립트를 먼저 돌리는 1차 규칙(`tool/src/test_command.dart` 41) 그대로 |

### 5.8 동시 개발 중 가짜와 가정

| 의존 | 개발 중 CORE가 쓰는 것 | 실제와 맞춰 보는 시점 |
|---|---|---|
| (없음) | 자기 실제 구현. 동기화 쪽 동작은 1차 `SyncStore` 계약 시험(1차 T14)과 `test/sync/support/sync_support.dart`의 `fieldLwwPolicy()`(SYNC 6.3.4 모양) | 통합 3단계 SYNC T16-v2 |
| INK `InkTextLayout` | 쓰지 않음(높이는 EDITOR가 씀). 시험의 텍스트 상자 frame은 고정 값 | — |
| PDF `PdfSearchIndexer` | `test/search/`의 손으로 만든 `SearchUnitDraft`(쪽 단위 + 글자 상자, 빈 목록, `PageRect.zero` 섞임, `pdfPageAspect` 있음·없음) + 실제 모양 500쪽 합성 자료(6.19 PF-10) | 통합 4단계 PDF `integration` |
| recog 색인기 | 시험이 `HandwritingRepository.put`·`update`를 직접 부름(경합 사례는 공유 계약 본문 — 6.9.4) | 통합 5단계 L2x |
| media 녹음기 | 시험이 `RecordingDraftStore`·`createRecording`을 직접 부름(+ CORE `FakeAudioRecorder`) | 통합 4단계 `media`(V8·V16) |

다른 영역이 개발 중 쓰는 CORE 쪽 (기반 단계 결과로 바꿈 — 2026-11-06, 가정 없음: 모두 이 작업 트리에 있는 실제 타입·함수):

| 영역 | 쓰는 것 (실제 이름) | 상태 · 커밋 |
|---|---|---|
| INK·EDITOR·LIBRARY·PDF·INFRA | `createFakeNoteStore()` v2(`recordings`·`recordingDrafts`·`handwriting`·`search` 동작), `PageObjectFixtures`·`FakeAudioRecorder`·`FakeAudioPlayback`(`package:note_core/testing.dart`) | B2-α `2b2e4b0` 컴파일, B2-β 끝 T23b `0798096`부터 동작 |
| PDF(V8·V16·V11 Chrome) | `openWebTestNoteStore`·`deleteWebTestNoteStore`(`package:note_core/testing_web.dart` — 실제 웹 CORE), 준비 `dart run <note_core>/tool/prepare_web_test.dart --out test/web` | T23b `0798096`부터 열림(v1 DB). 객체·녹음·초안 쓰기는 T24·T27·T30·T31 이정표 뒤 |
| SYNC·PDF·LIBRARY 통합 태그 | `openTestNoteStore()`(`package:note_core/testing_vm.dart` — 실제 CORE) | 동시 개발 시작 시점 v1 DB(`kDatabaseSchemaVersion` 1)라 객체·녹음·손글씨·색인 쓰기가 `UnimplementedError('CORE T27/T30/T32/T33a: …')`(8.1 'B2 상태' β 끝 열). DB v2는 T24 이정표부터 — 진행 기록 '이정표 커밋' 표 |
| PDF(정규화 동치 시험) | `SearchText.normalize`·`normalizeMapped` | T21 `38f3578`에서 완성 |
| SYNC(JSON 키 대조) | 객체·손글씨·녹음 JSON 골든(`test/goldens/json/*.json`)과 `toJson` | T20a `9777fde`에서 고정(SYNC R2-B7a가 이 해시로 CP-S9 판정) |
| INFRA 개발자 메뉴(J14b) | `dev_tools.dart` `V1DatabaseCopyInfo`·`v1DatabaseCopyInfo`·`readV1DatabaseCopy`·`deleteV1DatabaseCopy`(C22-01) | 선언 B2-α `2b2e4b0`(언제나 `null`), 동작 T24 |

---

## 6. 설계 상세

1차 6장(1차 계획서)의 구조를 그대로 두고 바뀌는 것만 적는다. 각 절 제목 괄호 안이 이어받는 1차 절이다.

### 6.1 계층과 데이터 흐름 (1차 6.1에 더함)

```text
EDITOR · INK(InkEdit) · recog ──EditCommand──▶ NoteSession(SessionEngine) ──▶ CommandResolver ──▶ AppliedEdit
                                                    │ N-1 동기 반영 (획 + 객체)                    │ EntityDelta (undo/redo)
                                                    ▼                                               ▼
                                             SessionBackend ──▶ WriteQueue / WriteTxn ──▶ SQLite v2 (strokes, page_objects …)
                                                                   │ putLocal / putRemote 훅
                                                                   ├──▶ outbox (힌트 noteId·pageId) · ChangeBatch
                                                                   └──▶ SearchIndexer (savepoint) ──▶ search_owners · search_units · search_fts
media_io ──▶ RecordingDraftStore ──▶ BlobStore 'rd/<draftId>/meta' (begin 때 먼저) · 'rd/<draftId>/<n>' + recording_drafts 행
        └──▶ AssetStore.put(audio) ──▶ RecordingRepository.createRecording (M-1, id마다 멱등)
recog   ──▶ HandwritingRepository.update(transform) ──▶ 한 쓰기 트랜잭션: 읽기 → transform → handwriting 행 (+ ink 단위 색인)
        ◀── stalePages · notesWithStalePages ◀── pages.ink_rev 캐시 (6.9.3)
pdf_io  ──▶ SearchIndexWriter.replaceUnits(pdf) ──▶ search_owners · search_units(원문·정규화) · search_fts
                                                └──▶ BlobStore 'si/pdf/<assetId>/<pdfIndex>/<token>' (글자 상자, 1/65535 — SQLite 밖)
LIBRARY ──▶ LibraryRepository.searchLibrary / SearchIndex.searchPages ──▶ FTS5 MATCH | LIKE (최근 단위 먼저 2,000)
                                                                     ──▶ 공용 판정·랭킹(norm만) ──▶ 대표 limit개만 원문·사각형 읽기 ──▶ PageSearchHit
열기(v1 DB) ──▶ v1 사본(네이티브 VACUUM INTO 파일 / 웹 블롭 'db/v1-backup/…' 정규 덤프) ──▶ 업그레이드 트랜잭션 v1 → v2 (6.12)
```

- 색인 쓰기는 원천 쓰기와 **같은 트랜잭션의 savepoint**에서 한다. 색인이 실패해도 원천 쓰기는 커밋된다(C-13, 6.10.5).
- 녹음 행·손글씨 결과·색인은 되돌리기 히스토리 밖이다(R-8). 히스토리에 들어가는 것은 세션 명령(획·객체·페이지)뿐이다.

### 6.2 페이지 객체 모델 (1차 6.2 확장)

#### 6.2.1 `ElementFrame` 기하

- 좌표: 페이지 pt, y 아래 방향(1차 6.2.6). `rect`는 회전 전 상자, `rotation`(rad)은 `rect` 중심 기준 회전이다. y가 아래 방향이라 양의 각은 **화면에서 시계 방향**이고, 1차 `Affine2.rotation = atan2(b, a)`(`common/geometry.dart` 164)와 같은 부호다.
- 꼭짓점: `p' = c + R(θ)(p − c)`, `R(θ) = [[cos θ, −sin θ], [sin θ, cos θ]]`. `corners` = 회전한 tl, tr, br, bl. `bounds` = 네 꼭짓점의 축 정렬 상자.
- `transformed(m)`: `c' = m(c)`, `s = m.uniformScale`(= √|det|), `w' = w·s`, `h' = h·s`, `θ' = norm(θ + m.rotation)`, `rect' = c'를 중심으로 w'×h'`. 이동·균등 배율·회전(닮음 변환)은 정확하다. 비균등 배율·기울임·뒤집기(det < 0)는 같은 식으로 근사한다 — EDITOR는 비균등 크기 조절을 `UpdateObjects`로 보내고 뒤집기를 보내지 않는다(CP-12 ① 승인 — 7.2.3 C2-38 문장 '뒤집기는 EDITOR가 보내지 않는다').
- `norm(θ)`: `(−π, π]`로 접는다(`θ − 2π·⌈(θ − π) / 2π⌉` — `norm(−π) = π`, `norm(3π) = π`). (v2.1 정정, 검토 S-1) `ElementFrame` 생성자(const)와 **`fromJson`은 값을 그대로 담는다** — 원격·백업에서 읽은 값이 다시 쓸 때 바뀌면 C-12·SYNC 키 값 대조·`changedJsonKeys`가 흔들리기 때문이다(7.2.2 '(v2.1) never normalizes'). 접는 것은 `normalized()`(로컬 명령 해석 때 — 6.2.3)와 `transformed`(새 값을 계산할 때)뿐이다.
- `contains(p, tolerance)`: `p`를 중심 기준 `−θ`로 되돌린 뒤 `rect.inflate(tolerance)` 포함 여부.
- JSON `[left, top, right, bottom, rotation]`. `fromJson`은 길이 5, 모두 유한한 수(정수 허용 — 웹은 `1.0`을 `1`로 쓴다, 1차 `json_web_format_cases`), `right ≥ left`, `bottom ≥ top`, 변 ≤ 14400이 아니면 `FormatException`. 변 0(직선·점)은 허용한다. 회전은 유한하기만 하면 범위를 보지 않는다(`3π`도 받는다).
- 경계값 왕복 시험(`test/common/element_frame_test.dart`, VM + `object_json_web_cases` → Chrome): `[…, −π]`·`[…, 3π]`·`[10, 10, 10, 40, 0]`(너비 0)·`[0, 0, 14400, 14400, 0]`을 `fromJson` → `toJson`하면 입력과 같은 값이고(`==`도 원래 값 기준), `normalized()`만 회전을 `π`로 접으며, 접기 전후의 `corners`·`bounds`가 1e-9 안에서 같다. `14400.0001` 변은 `FormatException`.

#### 6.2.2 `ShapeGeometry`와 템플릿

- `PolylineGeometry.points`는 절대 페이지 pt다. `frame` = 점들의 축 정렬 상자(회전 0). 그래서 회전한 사각형 도형의 `frame`은 회전하지 않은 큰 상자다(계약 주석 그대로) — 선택 핸들 모양은 INK·EDITOR가 정한다.
- `EllipseGeometry.ellipseFrame`이 원본이고 `frame`은 그것 자체다.
- `transformed(m)`: 폴리라인은 점마다 `m`(정확), 타원은 `ellipseFrame.transformed(m)`(닮음 변환에서 정확).
- JSON `{"poly":[x0,y0,…],"closed":bool}` 또는 `{"ellipse":[l,t,r,b,rot]}`. 두 키가 다 있거나 다 없으면, 점 배열 길이가 홀수이거나 점이 2개 미만이면 `FormatException`. 점 수 상한(64)은 **로컬 명령의 검증**이고(6.4.1), 읽기는 64개를 넘어도 받는다(새 앱이 상한을 올려도 옛 앱이 기록을 잃지 않게).
- 템플릿(순수 기하 — EDITOR 도형 도구와 recog 도형 판정기가 같은 결과를 내도록 식을 고정한다. '시계 방향' = y 아래 좌표에서 각이 커지는 방향):

| 템플릿 | 결과 |
|---|---|
| `line(a, b)` | `[a, b]`, `closed: false` |
| `rectangle(r, rotation)` | `r`의 tl, tr, br, bl을 `r` 중심 기준 `rotation`만큼 돌린 4점, `closed: true` |
| `ellipse(r, rotation)` | `EllipseGeometry(ElementFrame(r, rotation: rotation))` |
| `triangle(r)` | 꼭대기 `(cx, top)` → `(right, bottom)` → `(left, bottom)`(이등변, 꼭대기가 위), `closed: true` |
| `regularPolygon(r, sides, rotation)` | `k = 0..sides−1`, `α = −π/2 + rotation + 2πk/sides`, `(cx + (w/2)cos α, cy + (h/2)sin α)` — 맨 위에서 시계 방향. `sides`가 3..12 밖이면 `ArgumentError` |
| `star(r, points, innerRatio)` | `2·points`개 점: 짝수 번째는 바깥(반지름 w/2·h/2), 홀수 번째는 안쪽(`innerRatio`배), 맨 위 바깥 점에서 시계 방향. `points` 3..12, `innerRatio` 0.1..0.9 밖이면 `ArgumentError` |

- 화살표(`ShapeKind.arrow`)는 `line` 기하 + `ShapeStyle.arrowHeads`(`end`/`both`)다. 별도 템플릿을 두지 않는다.

#### 6.2.3 스타일 정규화

| 타입 | `normalized()` |
|---|---|
| `ShapeStyle` | `strokeColorArgb` 알파 0xFF, `strokeWidth` [0.1, 30], `strokeOpacity` [0.05, 1], `fillColorArgb` 알파 0xFF(CP-5), `fillOpacity` [0, 1]. NaN은 기본값 |
| `TextBoxStyle` | `fontSizePt` [6, 144], `colorArgb` 알파 0xFF, `lineHeight` [1.0, 3.0], `backgroundArgb` 그대로 |
| `MathStyle` | `colorArgb` 알파 0xFF, `fontSizePt` [6, 144] |

- 알파 맞추기는 비트 연산 없이 산술로 한다(`0xFF000000 + c % 0x1000000` — 1차 7.4.3 웹 안전 수치).
- 정규화(스타일과 `ElementFrame.normalized()` — 회전을 `(−π, π]`로)는 **로컬 명령 해석 때**(`AddObjects`·`UpdateObjects`·`InsertPages` 초안) 한다. `fromJson`은 정규화하지 않고 받은 값을 그대로 둔다(1차 `Stroke.fromJson`과 같음 — 원격 값과 해시·버전이 어긋나지 않게, 7.2.2 (v2.1)). 이 표가 7.2.2가 가리킨 '단일 출처'다.
- `transformed`(6.2.5)는 표의 배율 필드만 바꾸고 자른다. 나머지 스타일 필드(알파 등)는 정규화하지 않는다 — 원격에서 온 값을 변형해도 배율 필드 말고는 바뀌지 않게.

#### 6.2.4 `bounds` (K-6의 기준)

| 종류 | `bounds` (파생, 직렬화하지 않음, 모든 기기에서 같음) |
|---|---|
| `ShapeObject` | `geometry.frame.bounds.inflate(style.strokeWidth·0.75 + (arrowHeads ≠ none ∧ shapeKind ∈ {line, arrow} ? max(6, 3·strokeWidth) : 0))` |
| `TextBoxObject`, `ImageObject`, `MathObject`, `UnknownObject` | `frame.bounds` |

- `late final`로 한 번 계산한다(1차 `Stroke.bounds`와 같음). DB `page_objects.min_x…max_y`에 저장하고 공간 질의·내보내기 범위에 쓴다.
- 도형의 0.75는 1차 형광펜 사각 캡 근거(√2/2 < 0.75)와 같다. INK는 둥근 이음·캡으로 그 안에 그린다(K-6). 공식을 바꾸면 모든 기기의 저장값이 바뀌므로 바꾸지 않는다.

#### 6.2.5 복사 · 메타 · 변형

| 멤버 | 동작 |
|---|---|
| `copyTo(id:, pageId:, createdAt:)` | 새 id·페이지·`createdAt`, `version`·`deletedAt` 비움, `updatedAt = createdAt`(저장 때 CORE가 지금 시각으로 바꿈). 나머지 필드는 그대로. `UnknownObject`는 `rawJson`의 메타 키만 바꾼 새 객체 |
| `copyWithMeta(...)` | `updatedAt`·`deletedAt`·`version`만 바꿈(해석기·원격 적용 경로) |
| `transformed(m, {scaleWidth = true})` — (v2.1) **객체 변형의 단일 규칙**(CD2-07) | `s = m.uniformScale`. 도형: `geometry.transformed(m)`, `scaleWidth`면 `style.strokeWidth × s`를 [0.1, 30]으로 자름(아니면 굵기 그대로). 텍스트 상자: `frame.transformed(m)` + `style.fontSizePt × s`를 [6, 144]로 자름(CP-2 — 줄바꿈 폭과 글자를 같은 배율로, `scaleWidth`와 무관). 수식: `frame.transformed(m)` + `style.fontSizePt × s`를 [6, 144]로. 이미지: `frame.transformed(m)`만. `UnknownObject`: 같은 인스턴스(변형 불가 — 해석기가 건너뜀) |

- (v2.1, CP-2·CD2-07) CORE 해석기의 `TransformElements`(6.4.1)와 INK 선택·대기 표시 미리보기, EDITOR 핸들 미리보기가 **이 함수 하나**를 부른다. 그래서 화면에 보인 변형 결과와 저장된 값이 같다(INK 검토 M-2). 글자 크기가 [6, 144]에 걸려 잘리면 frame 높이와 내용이 조금 어긋날 수 있고, 그때는 INK가 frame으로 자른다(K-6) — EDITOR가 변형 뒤 높이를 다시 재 `UpdateObjects`로 맞출지는 EDITOR 몫이다.
- 시험(`test/model/page_object_test.dart`): 종류마다 이동·균등 배율 2·0.5·회전 90°, `scaleWidth: false`, 자름 경계(굵기 30·글자 144·6), `UnknownObject` 동일 인스턴스, 미리보기 경로와 해석기 경로가 같은 값(해석기 결과 객체 == `transformed` 결과에 `updatedAt`·`version`만 다름).

#### 6.2.6 JSON 읽기 규칙 (C-12, 모르는 것)

| 입력 | 결과 |
|---|---|
| `type`이 `shape`·`text`·`image`·`math`이고 본문을 읽을 수 있음 | 그 종류 |
| `type`이 그 밖의 값 | `UnknownObject`(원본 보존) |
| 알려진 `type`인데 이 앱이 모르는 enum 이름(`shape: "heart"`, `dash: "wavy"`, `arrowHeads`·`align`의 새 값) | `UnknownObject`(`type`은 그 알려진 이름) — 고쳐 쓰면 새 값을 잃으므로 보존한다(CP-6) |
| 알려진 `type`인데 필수 키가 없거나 타입이 틀림 | `FormatException`(그 기록을 버림 — 1차 `Stroke.fromJson`과 같음, SYNC 게이트는 `malformedRemoteData`) |
| 알려진 종류 안의 모르는 키 | 읽을 때 무시(1차 7.4.6 규칙). 이 앱에서 그 객체를 고치면 모르는 키는 사라진다 — SYNC의 '없는 키는 스냅숏 기준 버전'(조사 01 3.4) 시나리오로 확인 |
| `UnknownObject`의 공통 키(`id`·`pageId`·`type`·`createdAt`·`updatedAt`) 누락 | `FormatException` |
| 도형의 `frame` | 기하에서 계산해 쓰고, 읽을 때는 무시 |

- `UnknownObject.frame`: `rawJson['frame']`을 `ElementFrame.fromJson`으로 읽고, 실패하면 `PageRect(0, 0, 1, 1)`.
- 로컬 한도(글자 10,000자·LaTeX 4,000자·점 64개·페이지당 2,000개)는 원격·백업 읽기에는 적용하지 않는다(6.4.1의 명령 검증에서만).
- (v2.1, CP-6) 모르는 enum 이름으로 `UnknownObject`가 된 알려진 종류도 `referencedAssets`는 4.3 규칙(최상위 `assetId`)을 따른다 — 이미지 객체가 새 enum 값 때문에 `UnknownObject`가 되어도 에셋 참조를 잃지 않는다.

#### 6.2.7 캘리그래피 획 변형 (C2-38 — INK CP-INK-4, CORE 동작 변경)

1차 `Stroke.transformed(m, {scaleWidth})`(`model/stroke.dart` 73–90)에 한 갈래를 더한다. 회전한 캘리그래피 글씨가 화면 그대로 같이 돌게 하는 규칙이다(INK는 펜촉 각으로 외곽선을 만든다).

| 조건 | 동작 |
|---|---|
| `style.tool != calligraphy` | 1차 그대로 |
| `tool == calligraphy`, `r = fold(deg(m.rotation))` | `deg(x) = x · 180 / π`, `fold(a) = a − 180·⌊a / 180⌋`(결과 [0, 180)) |
| `r == 0`(이동·배율만, 또는 180° 회전) | extras 그대로 — 키가 없을 때 새로 쓰지 않는다(바뀐 키가 생기지 않게) |
| `r != 0` | `old = extras['nibAngleDeg']`(수가 아니거나 없으면 45 — 1차 `StrokeStyle.defaultsFor(calligraphy)`의 값), `extras' = {...extras, 'nibAngleDeg': fold(old + r)}`(double) |

- 키 문자열은 CORE 내부 상수 `kCalligraphyNibAngleKey = 'nibAngleDeg'`(내보내지 않음)다. INK `InkStyleExtras.nibAngleDeg`와 같은 글자인지는 통합 2단계(INK 병합 뒤 — 8.3 I-1)에 INK 시험이 CORE 상수와 비교한다(CORE는 INK를 import하지 않는다).
- 뒤집기(det < 0)는 EDITOR가 보내지 않는다(C2-38). 보내더라도 같은 식(회전 성분만)이다.
- 해석기는 바뀐 `style` 키를 이미 기록하므로(1차 `command_resolver.dart` 183–186: `_put(s, t, {'points', if (t.style != s.style) 'style'})` [확인]) 필드 버전·동기화에 새 규칙이 없다. undo는 1차 절차로 옛 각을 되돌린다.
- INK 미리보기는 같은 `Stroke.transformed`를 다시 부르면 된다(C2-38 '미리보기 = 다시 기록 그대로').
- 시험(`test/edit/calligraphy_transform_test.dart` — `undo_objects_test` 옆, 순수 Dart라 B2-β에서): 키 없음 + 30° → 75, 170 + 30° → 20, −90° → 135, 180° → extras 불변(키 없으면 여전히 없음), 이동만 → 불변, 볼펜 획 → 불변, 문자열 값 `'x'` → 45로 보고 계산, `TransformElements` 한 번 → undo → 옛 extras·`style` 필드 버전, VM = Chrome(`test/shared/object_json_web_cases.dart`에 사례).

### 6.3 직렬화 (1차 6.3 확장)

- 키 표는 4.8(7.2.7 원문). 공통 키 `id`·`pageId`·`type`·`frame`·`createdAt`·`updatedAt`·`deletedAt`·`version`은 모든 종류가 항상 쓴다(값이 null이어도 키를 쓴다 — 1차 `Stroke.toJson`과 같음, SYNC 키 대조의 집합이 고정되게).
- (v2.1, 검토 S-7 — C21-11) **종류별 키도 항상 쓴다**: `math`의 `engine`은 `engineId`가 없으면 `"engine": null`, 도형 `style`의 `fillColorArgb`, 텍스트 `style`의 `backgroundArgb`도 null이면 null로 쓴다. 키 집합은 종류마다 고정이고 SYNC `kPageObjectTypeKeys`와 CORE 골든이 같은 집합을 대조한다. 읽을 때는 키가 없어도 null로 받는다(1차 '모르는 키 무시·없는 키 기본값' 규칙).
- 손글씨 결과: `id`·`noteId`·`pageId`·`engineId`·`sourceRev`·`lines`·`createdAt`·`updatedAt`·`deletedAt`·`version`. `lines[i]` = `{text, alternatives, rect:[l,t,r,b], strokeIds, languageTag, userConfirmed}`.
- 녹음: v1.4 키 + `title`(항상 씀, 없으면 null).
- JSON 골든(`@Tags(['golden'])`·`@TestOn('vm')`, 1차 T3 방식) — 새 파일 9개 + 변경 1개. **B2-β의 첫 조각**에서 커밋하고 그 해시를 알린다(SYNC CP-S9 키 대조 시험이 이것을 기다린다 — 8.1):

| 파일 | 내용 |
|---|---|
| `shape_rect.json` | 7.2.7 예시 그대로(회전 0 사각형) |
| `shape_ellipse.json` | 회전 0.5 rad 타원, 채우기 있음 |
| `shape_arrow.json` | `arrow`, `arrowHeads: both`, `dash: dashed` |
| `text_box.json` | 한글·영문·줄바꿈, 굵게·가운데, 배경색 |
| `image.json` | `assetId`·`px` |
| `math.json` | `\frac{a}{b}`, `engine: "manual"` |
| `math_no_engine.json` | (v2.1) `engine: null` — 키가 있고 값이 null(C21-11) |
| `unknown.json` | `type: "sticker"` + 중첩 맵·배열·모르는 키 — 왕복 뒤 키 하나도 빠짐없이 같음(C-12) |
| `handwriting.json` | 줄 2개(후보 있음, `userConfirmed` 하나) |
| `recording.json` | (변경) `title` 키 추가(값 있는 사례) — `title: null` 사례는 `recording_contract`의 `toJson` 단언으로 |

- 웹 형식: 웹은 정수인 실수를 정수로 쓴다. 객체·손글씨 JSON도 1차 `test/shared/json_web_format_cases.dart`에 사례를 더해 VM·Chrome 양쪽에서 읽는다(`test/shared/object_json_web_cases.dart` → VM + `test/web/object_json_browser_test.dart`).
- `EntityJson`(`model/entity_json.dart`)의 종류별 디코드 switch에 `pageObject → PageObject.fromJson`, `handwriting → HandwritingText.fromJson`을 더한다.
- 필드 버전 키 = JSON 키 − 메타 키(`id`·`pageId`·`type`·`createdAt`·`updatedAt`·`version`). `type`은 바뀌지 않는다(`UpdateObjects`가 막음). 로컬 전용 키는 새 종류에 없다(`kLocalOnlyFields` 그대로 — `storage/outbox_writer.dart` 22).

### 6.4 명령 해석 (1차 6.5 확장)

#### 6.4.1 새 명령과 의미가 바뀐 명령

검증 오류는 모두 **아무것도 바꾸기 전에** 던진다. 1차 해석기는 한 명령(복합 포함)의 변경을 모았다가 끝에서 한 번에 반영하므로, 복합 명령 안 어느 하위 명령이 실패해도 전체가 반영되지 않는다(`edit/command_resolver.dart` `finish`). 대상 페이지가 로드되지 않았으면 1차처럼 `PageNotOpenException`(N-3).

| 명령 | 검증 (`ArgumentError`) | 적용 · delta | 바뀐 필드 |
|---|---|---|---|
| `AddObjects` | 객체마다 `pageId == 명령 pageId`, `version == null`, `deletedAt == null`, `isValidEntityId(id)`, 그 id가 세션이 아는 id와 겹치지 않음(1차 `_strokeIdTaken`과 같은 규칙 — 로드된 페이지·이번 편집·세션이 아는 삭제 id, **획 id와 객체 id를 한 공간으로** 본다), 같은 명령 안 중복 없음, 적용 뒤 활성 객체 ≤ 2,000, 글자 ≤ 10,000·LaTeX ≤ 4,000·점 2..64, 이미지 `pixelWidth/Height ≥ 1`. `UnknownObject`도 받는다(붙여넣기 — 통째로 복사 가능) | 스타일 정규화, `updatedAt = now`, `version = v`, `before = null` | `{*}` |
| `UpdateObjects` | id마다 이 페이지의 **활성** 객체가 있고, 같은 Dart 타입·같은 `type`, 저장된 것도 주어진 것도 `UnknownObject`가 아님, `pageId`·`createdAt` 같음(z 순서 고정 — D2), 위 한도 | 정규화 뒤 값이 같으면 건너뜀(delta 없음). 다르면 `updatedAt = now`, `version = v` | `changedJsonKeys(before, after)` − 메타 키(C-11) |
| `RemoveElements` | 없음(모르는·이미 삭제된·반복된 id는 무시 — `RemoveStrokes`와 같음, `elementIds`는 `List` — CP-1) | 획·객체 모두 `deletedAt = now`(같은 id 두 번 = 한 번) | `{deletedAt}` |
| `TransformElements` (의미 확장) | v1.4 그대로 | 획: v1.4 + (v2.1) 캘리그래피 펜촉 각(6.2.7). 객체: (v2.1) **`PageObject.transformed(m, scaleWidth: scaleStrokeWidth)` 하나**(6.2.5 — 미리보기와 같은 함수), `UnknownObject`는 건너뜀. 결과가 같으면 건너뜀. 획과 객체가 **한 커밋**(C-11) | 획: v1.4(`points` + 바뀌면 `style`). 객체: `changedJsonKeys` — `frame`, 도형 `geometry`·`style`, 텍스트·수식 `style` |
| `ClearPage(pageId: …, includeObjects: true)` (이름 있는 선택 인자 — 4.4) | v1.4 그대로 | 획은 `filter`대로, 객체는 `UnknownObject` 포함 전부 삭제. `includeObjects: false`(기본)면 1차 동작 그대로 | `{deletedAt}` |
| `InsertPages` | 초안마다 객체 ≤ 2,000, 객체 한도 | 초안 객체마다 `copyTo(id: 새 id, pageId: 새 페이지, createdAt: 원래 createdAt)`(z 순서 보존 — 1차 획 규칙), 정규화 | `{*}` |
| `DuplicatePages` | v1.4 그대로 | 원본 페이지의 활성 객체를 `InsertPages`와 같은 방식으로 복사 | `{*}` |
| `DeletePages` | v1.4 그대로 | 페이지만 소프트 삭제(획·객체 행은 그대로 — 영구 삭제 때 함께 지움, 6.14.2) | `{deletedAt}` |
| `CompositeCommand` | v1.4 그대로 | 하위 명령 순서대로. 같은 엔티티를 여러 번 건드리면 첫 before·마지막 after(1차) | — |

- `PageDraft.copyOf(content)`는 `content.objects`까지 담는다. 초안의 객체 id는 무시되고 새로 만든다(획과 같음).
- 도형 자동 보정(`InkEdit(addShape)` → `AddObjects`)과 손글씨 → 텍스트(`Composite[RemoveElements, AddObjects]`)는 일반 명령이라 따로 다루지 않는다.

#### 6.4.2 `AppliedEdit` · `PageContentChange`

- `AppliedEdit.insertedElementIds`에 새 객체 id도 들어간다(EDITOR가 붙여넣은 것을 선택할 때 씀). `affectedPageIds`는 v1.4 그대로.
- `PageContentChange.added/removed/updated`는 획과 객체 id를 함께 담는다(C2-10). 소비자는 모르는 id를 무시한다.

#### 6.4.3 되돌리기 (1차 6.7)

- 객체 명령도 `EntityDelta(kind: pageObject, before, after)`로 기록되어 1차 undo/redo 절차(1차 6.7.2)·원격 변경 건너뛰기(1차 6.7.3)·별칭 정리(1차 T11)·필드 버전(1차 6.7.6)이 그대로 적용된다.
- undo가 쓰는 필드 = 되돌린 값과 현재 값의 JSON 키 차이(1차 6.7.6). 그래서 `UpdateObjects`로 `text`만 바꾼 뒤 undo하면 `text`만 새 버전을 받는다(C-11 시험).
- 손글씨 결과·녹음·색인은 히스토리에 들어가지 않는다(R-8). 손글씨 → 텍스트 변환을 undo하면 획이 되살아나고 텍스트 상자가 지워지며, 손글씨 결과는 색인기가 다음 유휴 때 다시 맞춘다(`stalePages`).

#### 6.4.4 메모리 추정 (1차 6.7.4)

- `EntityDelta.estimatedBytes`에 객체 몫을 더한다: `PageObject.estimatedBytes`(4.3) — 기본 160 B + 글자·LaTeX 2 B/글자 + 폴리라인 16 B/점 + `UnknownObject`는 JSON 길이 × 2. 이미지 바이트는 에셋이라 히스토리에 없다.
- 1만 자 텍스트 상자를 100번 고쳐도 약 4 MB(before + after)로 1차 상한(웹 32 MiB)에 한참 못 미친다.

### 6.5 노트 세션 · 지연 로딩 (1차 6.14 확장)

- `SessionBackend.loadStrokes(pageId)`를 `loadContent(pageId)`(획 목록 + 객체 목록)로 바꾼다(내부 인터페이스). DB 백엔드는 쓰기 큐를 flush한 뒤 `strokes`·`page_objects`를 같은 읽기 트랜잭션에서 읽는다(1차 T10 '큐 전체 flush 뒤 읽기' 그대로).
- 엔진의 페이지 상태 `_Loaded`에 `objectsById`·정렬 목록을 더하고, `PageContent`는 두 목록을 `Stroke.compareOrder`로 정렬한 불변 목록으로 만든다. 바뀌지 않은 객체는 같은 인스턴스를 유지한다(1차 K-4 — INK diff).
- 객체 변경도 그 페이지의 `contentRevision`을 1 올린다(썸네일 무효화·`ink_rev` 캐시 판정이 이것을 본다).
- 원격 변경(N-7): `DriftSessions.committed`가 원격 커밋의 `page_objects` 행을 다시 읽어 `SessionEngine.remoteCommitted(objects: Map<ElementId, (PageId, PageObject?)>)`로 넘긴다. 로드된 페이지에 `PageContentChange(origin: remote)`가 나가고 히스토리는 그대로다.
- `NoteContentReader.loadPage`(PDF 내보내기·썸네일)도 `objects`를 채운다.
- 읽기 전용(N-4)·재진입 금지(N-2)·페이지 LRU 8·핀은 1차 그대로다.

### 6.6 녹음 저장소 (`RecordingRepository`)

| 멤버 | 규칙 |
|---|---|
| `createRecording` | `isValidEntityId(id)` 아니면 `ArgumentError`. 노트 행이 없거나 영구 삭제됐으면 `EntityNotFoundException`(휴지통에 있는 노트는 허용 — 녹음 중 노트를 휴지통에 넣어도 소리를 잃지 않게). `assetId`의 에셋 행이 없거나 `type != audio`면 `ArgumentError`(M-1 순서 검사). `durationMs < 0`이면 `ArgumentError`. `title`은 앞뒤 공백을 자르고, 비면 null, 100자(룬 기준) 초과면 `ArgumentError`. (v2.1, CP-7 — 7.2.4 '멱등') **같은 id가 이미 있으면 검증보다 먼저 그 행을 그대로 돌려준다**(삭제된 행이어도 되살리지 않고 그대로 — 쓰기·`ChangeBatch` 없음). 인자가 저장된 행과 다르면(복구가 길이 보정을 다르게 해 `assetId`가 달라진 경우 등) 개발 로그에 남기고 저장된 값을 이긴 것으로 둔다 — 복구 재시도가 예외로 막히면 같은 초안이 매 실행 다시 실패하기 때문이다(새 에셋은 고아로 남고 GC(U13)가 회수). 새 행은 `createdAt = updatedAt = now`, `putLocal {*}`, `ChangeBatch(local)` |
| `renameRecording` | 없거나 삭제된 녹음이면 `EntityNotFoundException`. 같은 값이면 쓰지 않음. 바뀐 필드 `{title}` |
| `deleteRecording` | 없으면 `EntityNotFoundException`, 이미 삭제면 아무것도 안 함. 바뀐 필드 `{deletedAt}`. 획은 건드리지 않는다(R-7). 에셋 바이트는 남는다(U13) |
| `recordingsOf`·`watchRecordings` | 그 노트의 활성 녹음, `startedAt` → id 오름차순. 노트 소유자가 현재 소유자가 아니면 빈 목록(1차 소유자 필터). watch는 구독 즉시 1회 + 녹음 행이 바뀐 커밋마다(`WatchHub` `affects: {recording}`, 같은 값이면 내지 않음) |
| `getRecording` | 삭제된 것도 돌려준다. 없으면 null |
| `audioBytesOf` | 그 노트의 활성 녹음이 가리키는 **서로 다른** 에셋의 `Asset.size` 합(메타데이터 크기 — 바이트가 이 기기에 없어도 셈) |

- 원격으로 온 녹음(1차 경로)도 같은 테이블·같은 watch를 탄다. `title`은 SYNC 병합 단위에서 따로 묶인다(7.2.8 표).
- 녹음은 되돌리기 밖(R-8)이다. 삭제 확인 창은 media_io 몫이다.
- 노트 복사 때 녹음 복사(R-6)는 6.14.1, 영구 삭제 때 행 삭제는 1차 그대로(T9·T14).

### 6.7 녹음 초안 저장소 (`RecordingDraftStore`)

#### 6.7.1 저장 위치

- 초안 행: `recording_drafts`(기기 로컬 — 버전·outbox·`ChangeBatch`·백업·동기화 없음). 쓰기는 쓰기 큐 작업으로 한다(1차 '모든 쓰기는 큐'), 엔티티 경로(`putLocal`)는 쓰지 않는다.
- 조각 바이트: 에셋과 같은 블롭 저장소(웹 IndexedDB `noteapp_blobs`, 네이티브 파일 블롭)의 키 `rd/<draftId>/<index 6자리>`. 에셋 키는 `<sha256 64 hex>/<index>`라 겹치지 않는다. 키 하나 = 값 하나 = 원자적 쓰기(1차 6.13).
- (v2.1, CORE-M4 — 검토 S-3 승격) **초안 meta**: 같은 블롭 저장소의 `rd/<draftId>/meta` = UTF-8 JSON `{"v":1,"recordingId":…,"noteId":…,"mimeType":…,"startedAt":…}`. `begin`이 **행보다 먼저** 쓴다. 웹에서 행의 내구성이 조각보다 늦을 수 있으므로(6.7.3), 행을 잃어도 meta와 조각만으로 초안을 되살린다.

#### 6.7.2 동작

| 멤버 | 규칙 |
|---|---|
| `begin` | `isValidEntityId(recordingId)`·`noteId`, `mimeType` 비어 있지 않음(아니면 `ArgumentError`). 같은 `recordingId`의 초안이 이미 있으면 `StateError`(녹음 하나 = 초안 하나). `draftId = ids.newId()` → ① 블롭 `put(rd/<id>/meta)`(완료를 기다림) → ② 큐 작업으로 행 쓰기 → 커밋 뒤 `RecordingDraft(chunkCount: 0, bytes: 0, activeMs: 0, updatedAt: now)`. ①이 실패하면 행을 쓰지 않고 그 오류로 끝난다 |
| `append` | 모르는(또는 버린 — 다른 탭이 복구·정리한 경우 포함) `draftId`면 `StateError`(7.2.4 원문). 조각 > 4 MiB 또는 `activeMs < 0`이면 `ArgumentError`. 한 초안의 `append`는 **부른 순서대로** 이어서 처리한다(초안마다 내부 사슬). 단계: ① 블롭 `put(rd/<id>/<n>, 복사본)` ② 큐 작업으로 행 갱신(`chunk_count = n + 1`, `bytes += len`, `active_ms`, `updated_at = now`). Future는 ②가 커밋된 뒤 완료한다(커밋 재시도 중에는 미완료 — 1차 쓰기 Future 규칙). (v2.1) **빈 조각**은 ①을 건너뛰고 `active_ms`·`updated_at`만 갱신한다(일시정지 중 살아 있음 표시 — `pendingDrafts`의 '최근 갱신' 판정이 이것을 본다). 조각 번호가 999,999를 넘으면 `ArgumentError` |
| `listDrafts` | 모든 초안(기기 전체 — 소유자 무관), `startedAt` 오름차순. ① 행이 있는 초안: 행 값을 블롭 키와 맞춰 돌려준다 — `chunkCount` = 0부터 끊김 없이 있는 조각 수, 행보다 조각이 많으면 그 조각들의 길이를 `bytes`에 더한다(①과 ② 사이에 끊긴 경우). ② (v2.1) **행이 없고 meta가 있는** 접두사: meta로 초안을 되살린다(`activeMs: 0`, `updatedAt: meta.startedAt` — 알 수 없는 값을 '오래전'으로 두어 `pendingDrafts`가 영원히 '최근'으로 빼지 않게, `chunkCount`·`bytes`는 조각에서). 되살린 행은 큐 작업으로 다시 쓴다(다음 `readAll`·`discard`가 같은 경로를 타게). ③ **조각 0 초안은 정상**이다 — 네이티브 media는 행만 쓴다(PDF 6.9.5). 그대로 낸다 |
| `readAll` | 0부터 끊김 없이 있는 조각을 이어 붙인 바이트. 모르는 `draftId`면 `StateError`. 조각을 하나씩 읽어 결과 버퍼에 복사하고 버린다(동시에 드는 것 = 결과 한 벌 + 조각 하나 — M-4) |
| `discard` | ① `deletePrefix('rd/<id>/')`(조각과 meta를 함께 — 웹은 IndexedDB 트랜잭션 하나) ② 행 삭제. 중간에 끊기면 행만 남아 다음 `listDrafts`에 조각 0 초안으로 보인다 — 웹 초안이면 media `recoverDraft`가 빈 초안을 버리고(바이트 없음 → `null`), 네이티브 초안이면 media가 파일로 복구를 시도한다(정상 경로). 없는 초안이면 아무것도 안 함 |

- **고아 정리**(v2.1 정정): 저장소를 연 뒤 초안 저장소를 처음 쓸 때 `rd/` 아래 접두사 중 **행도 meta도 없는 것만** 지운다(지우다 끊긴 조각). meta가 있으면 행이 없어도 지우지 않는다 — 행이 IndexedDB에 반영되기 전에 탭이 닫힌 녹음을 통째로 지우면 D13(P-A)이 막으려던 '녹음 전체 손실'이 된다(검토 S-3). 열기를 막지 않는다(1차 T13 '처음 쓸 때 연다'와 같은 방식).
- 노트 영구 삭제 때 그 노트의 초안도 버린다(6.14.2 — 행과 meta의 `noteId`로). `deleteLocalNoteData`는 블롭 DB째 지우므로 초안도 사라진다.
- 시험(`test/media/recording_draft_store_test.dart`, 공유 본문 `test/shared/recording_draft_contract.dart`): `begin`의 meta가 행보다 먼저(블롭 쓰기 기록 순서), 행을 지운 뒤(행 유실 흉내) `listDrafts`가 meta로 되살림·`updatedAt == startedAt`·다시 열어도 같음, 행도 meta도 없는 접두사만 정리됨(meta만 있는 접두사·조각 0 행은 남음), 빈 조각 `append`가 `activeMs`·`updatedAt`을 바꾸고 `chunkCount`는 그대로, 조각 0 초안이 `listDrafts`에 남음, `discard` 중간 끊김(①만) → 조각 0 초안.

#### 6.7.3 내구성 · 성능 · 메모리

- (v2.1 정정, 검토 S-3) **웹의 실제 보장**: ① 조각·meta는 IndexedDB 트랜잭션 완료 시점에 내구다(브라우저 기본 내구성 — `put`의 Future가 그 뒤 완료). ② 행은 drift `sharedIndexedDb`가 SQLite 커밋 뒤 IndexedDB로 **비동기 반영**하므로 커밋보다 수 ms 늦게 내구가 된다(1차 02-core '문장마다 IndexedDB로 flush, 수 ms 구간 손실 가능' — sqlite3 3.8.0 `IndexedDbFileSystem`은 `writeAutomatically`가 '내구성 보장 없음'이라고 적는다 [확인 — `lib/src/wasm/vfs/indexed_db.dart` 465–468]). 그래서 탭이 닫히면 마지막 행 갱신(또는 `begin`의 행)을 잃을 수 있고, `listDrafts`가 조각·meta로 맞춘다(6.7.2). 잃을 수 있는 것은 조각 쓰기가 끝나지 않은 마지막 조각(1초 이하)뿐이다(M-2 '마지막 1초 이하'). OS 수준 강제 종료에서는 브라우저가 IndexedDB 반영을 미룬 몫까지 잃을 수 있다(위험 15).
- 1초마다 쓰기 큐 커밋이 하나 늘어난다. 획 커밋과 같은 큐라 그룹 커밋으로 묶이고, 1차 1획 커밋 중앙값 6.8~7.8 ms(VM)에 비해 작다. `append` 예산(6.19): VM 중앙값 ≤ 10 ms, Chrome ≤ 30 ms(DDC 디버그 빌드 측정).
- (v2.1 정정, 검토 S-4) `readAll`은 결과를 한 버퍼로 만든다. **정지와 복구 모두** 그 한 벌을 든다(웹 정지 경로도 `readAll` → `AssetStore.put` — 5.4). 64 kbps 3시간 ≈ 86 MB(조사 02 3.5, D19 지원 범위)라 웹에서 정지 순간 결과 한 벌 + 조각 하나 + media의 머리 보정 `Blob`(M-4 — 같은 바이트를 두 벌 넘게 들지 않음)이 잠깐 생긴다. 7.4.5 '웹 녹음 메모리 조각 ≤ 8 MB'는 녹음 중 규칙이라 이것과 별개다. 1차 `AssetStore.put`은 입력 전체를 복사하지 않고 4 MiB 청크로 나눠 쓴다(1차 T13). Chrome 시험(`test/web/recording_draft_browser_test.dart`)이 30분 분량(약 14 MB, 1,800조각) `readAll` → `put`의 시간과 `performance.memory`(Chrome 전용 — 없으면 기록 생략)를 진행 기록에 남긴다.

### 6.8 오디오 포트 · 기본값 · 가짜

#### 6.8.1 포트 의미 (CORE가 정하는 부분)

- 앱에 녹음기 하나·재생기 하나(7.2.4 주석). provider는 `Provider`라 앱 수명 동안 같은 인스턴스다.
- `statusStream`은 구독 즉시 현재 값을 한 번 내고, 그다음 바뀔 때마다 낸다(1차 watch 스트림 규칙과 같음). 같은 값은 내지 않는다(`==`).
- `offsetNowMs()`는 동기·저비용(R-1·E-5). 가짜도 즉시 답한다.
- (v2.1, CORE-M10 — 7.2.4 원문 주석의 CORE 쪽 풀이) **`pendingDrafts()`** = `RecordingDraftStore.listDrafts()`에서 ① 이 녹음기의 진행 중 세션(`phase` `starting`…`finishing`)의 초안 ② 지금 복구 중인 초안 ③ `now − updatedAt < max(10 s, 5 × 조각 간격)`인 초안(다른 탭이 아직 녹음 중일 수 있음 — D19)을 뺀 목록이다. 복구 결정은 이 목록만 따른다(호출자는 `status.isActive`를 보지 않는다). 조각 0 초안(네이티브 행만)도 목록에 들어간다.
- **`recoverDraft(draftId)`** = 그 초안을 같은 `recordingId`의 녹음으로 마무리한다: 바이트(웹 `readAll`, 네이티브는 media가 파일에서) → `AssetStore.put(audio)` → `createRecording(id: 초안의 recordingId, …)`(멱등 — 6.6) → `discard` → 그 `Recording`. 바이트가 없으면 초안을 버리고 `null`. 저장에 실패하면 초안을 남기고 예외(M-1 v2.1 — 다음 실행에 다시). 앞 단계(`pendingDrafts`)가 뺀 초안(진행 중·복구 중·최근 갱신)을 직접 부르면 가짜는 `StateError`다. media 구현의 같은 경우는 PDF가 정한다(06-pdf — '다른 탭이 녹음 중인 초안을 복구하지 않는다'(M-4·7.4.2)와 같은 결과를 권한다).
- **`stop()` 실패**(v2.1, CP-PDF-5): 에셋 `put` 또는 `createRecording`이 실패하면 초안을 지우지 않고 예외로 끝난다(원문). 초안은 다음 실행의 `pendingDrafts`에 나온다. 실패 뒤 상태는 가짜에서 `idle` + `error`(6.8.3)이고, media는 PDF가 정한다.

#### 6.8.2 `UnsupportedAudioRecorder` · `UnsupportedAudioPlayback`

| 호출 | 녹음기 | 재생기 |
|---|---|---|
| `status` / `statusStream` | `RecorderStatus()`(idle) / 그 값 1회 | `PlaybackStatus()`(idle) / 그 값 1회 |
| `checkSupport` | `AudioSupport.unsupported` | — |
| `start` / `open` | `UnsupportedError` | `UnsupportedError` |
| `pause`·`resume`·`cancel` / `play`·`pause`·`seekMs`·`setSpeed`·`close` | 아무것도 안 함 | 아무것도 안 함 |
| `stop` / `recoverDraft` / `pendingDrafts` | `null` / `null` / `[]`(초안 저장소를 읽지 않는다 — 녹음을 끈 빌드는 복구도 하지 않음, D17) | — |
| `offsetNowMs` / `positionMs` | `null` | `0` |

- EDITOR는 `checkSupport()`가 `supported`가 아니면 녹음 패널 자리를 숨기거나 안내만 보인다(E-7·7.3.3 '이 기기에서 녹음할 수 없어요'). 읽기만으로는 예외가 나지 않으므로 기능 스위치로 끈 빌드(V15)에서도 에디터가 뜬다.

#### 6.8.3 `FakeAudioRecorder` (testing.dart — v2.1)

| 호출 | 상태 변화 · 저장소 쓰기 |
|---|---|
| `checkSupport()` | 생성자의 `support` |
| `start(recordingId, noteId)` | (v2.1, CP-PDF-5) `support != supported`면 **`UnsupportedError`**(실제 녹음기와 같음 — PDF 검토 X-6①), 이미 활성이면 `StateError`. `starting` → `recording`(두 상태를 차례로 냄), `store.recordingDrafts.begin(mimeType: 'audio/mp4', startedAt: store.clock 지금)` — 넘겨받은 `store`의 초안 저장소(가짜든 실제든)에 쓴다(meta → 행, 6.7.2) |
| `advance(d)` | 녹음 중일 때만 활성 시간 += d. 1초 경계를 넘을 때마다 16바이트 조각을 초안에 `append`(내부 사슬, 순서 보장). 일시정지 중에는 1초 경계마다 **빈 조각**을 `append`(활성 시간·`updatedAt`만 갱신 — 7.2.4 v2.1, 다른 녹음기의 `pendingDrafts`가 이 초안을 '최근 갱신'으로 뺀다). 조각 간격 = 1초 |
| `offsetNowMs()` | `recording`이면 활성 시간(ms), 아니면 null |
| `pause()` / `resume()` | `recording` ↔ `paused`(`interrupted: false`) |
| `interrupt()` | `recording` → `paused`, `interrupted: true` |
| `stop()` | 활성이 아니면 null. `finishing` → 쌓인 조각 저장을 기다림 → 활성 시간이 0이면 초안을 버리고 null → 아니면 바이트(녹음 id를 담은 결정적 무음 바이트)를 `store.assets.put(type: audio, mimeType: 'audio/mp4')` **먼저**, 그다음 `store.recordings.createRecording(durationMs: 활성 시간 + stopDurationErrorMs, startedAt: 시작 시각)`(M-1), 초안 버림 → idle, 녹음 반환. (v2.1) 저장이 실패하면(`FakeNoteStoreFaults` 등) 초안을 남기고 idle(`error` 채움) + 그 예외 |
| `cancel()` | 초안 버림, idle, 녹음 행 없음 |
| `pendingDrafts()` | (v2.1) 6.8.1 규칙 그대로: `listDrafts()`에서 이 녹음기의 진행 중 세션(`starting`…`finishing`) 초안, 복구 중인 초안, `store.clock` 기준 `now − updatedAt < 10 000 ms`(= max(10 s, 5 × 1 s))인 초안을 뺀 것 |
| `recoverDraft(draftId)` | 6.8.1 규칙: 위 제외 대상이면 `StateError` → `readAll` → 비면 버리고 null → 아니면 에셋 → `createRecording(id: 초안의 recordingId, title: '복구된 녹음', durationMs: 초안 activeMs, startedAt: 초안 startedAt)` → 버림 → 녹음 |
| `abandon()`(CP-8 — v2.1 원문) | 쌓인 조각 저장을 기다린 뒤 메모리 상태만 버리고 idle — 초안은 남는다(탭 닫힘 흉내). 같은 저장소의 **새** `FakeAudioRecorder`가 `store.clock`을 10초 넘게 진행한 뒤 `pendingDrafts()`로 그 초안을 받는다(V16 모양) |

- 실제 시간·타이머를 쓰지 않는다(`Stopwatch`·`clock.stopwatch()` 없음 — 7.4.8). `fake_async` 안팎 모두에서 결정적이다. '최근 갱신' 판정의 시각은 `store.clock`이므로 시험은 `createFakeNoteStore(clock: …)`(또는 `openTestNoteStore(clock: …)`)에 조절 가능한 시계를 넘긴다.
- `backgroundCapable: false`, `crossPlatformPlayable: true`, `mimeType: 'audio/mp4'`.
- (v2.1, 검토 X-4 — EDITOR·INFRA에 알림) `createFakeNoteStore()`와 쓰면 모든 쓰기가 마이크로태스크로 끝난다. **실제 메모리 CORE**(`openTestNoteStore()`·앱 스모크의 `inMemory`)와 `testWidgets` 안에서 쓰면 `stop()`·`recoverDraft()`의 에셋 `put`과 초안 조각이 idb_shim 메모리 IndexedDB(0.1 ms 타이머)를 거치므로, 시험은 `tester.runAsync(() => recorder.stop())` 또는 시간 진행(`tester.pump(const Duration(milliseconds: 1))` 반복)으로 기다린다 — 1차 CORE 진행 기록 '통합 단계' 메모와 같은 성질이다. `fake_async` 안이면 `elapse`로 진행한다(1차 `asset_store_test`의 `pumpUntil`).

#### 6.8.4 `FakeAudioPlayback` (testing.dart — v2.1)

| 호출 | 동작 |
|---|---|
| `open(recording)` | `loading` → `ready`, `recordingId`, `durationMs = recording.durationMs`, 위치 0. 바이트는 읽지 않는다(저장소 인자 없음) |
| `play()` / `pause()` | `ready`·`paused`·`completed` → `playing` / `playing` → `paused` |
| `seekMs(p)` / `setPositionMs(p)` | 위치 = `p`를 `[0, durationMs]`로 자른 값 |
| `setSpeed(x)` | `[0.5, 2.0]`로 자름 |
| `positionMs()` | 마지막으로 정한 위치(외삽 없음 — 시험이 직접 움직인다) |
| `close()` | idle |
| `calls`(CP-8 — v2.1 원문) | 받은 호출 기록, 순서대로: `'open:<recordingId>'`, `'play'`, `'pause'`, `'seek:<ms>'`(자르기 전 인자 정수), `'speed:<x>'`(Dart `double.toString` — VM `2.0`, 웹 `2`이므로 시험은 `startsWith('speed:')` + 값 파싱으로 비교), `'close'`. `setPositionMs`는 기록하지 않는다(시험 쪽 조작) |

- 가짜 재생기는 녹음기를 모른다(생성자 인자 없음 — 원문). 그래서 7.2.4의 '`play()` — 녹음기가 활성이면 아무것도 안 함'(CP-PDF-10)은 흉내 내지 않는다 — 그 규칙의 시험은 media 실제 구현 몫이고, EDITOR가 그 상황을 시험하려면 녹음 중에는 `play`를 부르지 않는다는 자기 쪽 규칙을 `calls`로 확인한다.

### 6.9 손글씨 인식 결과 (`HandwritingText` · `HandwritingRepository`)

#### 6.9.1 엔티티

- id = `'hw_' + pageId`(C2-30). 1차 ID 규칙 `^[0-9A-Za-z_-]{1,64}$`를 통과한다(UUIDv7 36자 + 3 = 39자). `isValidEntityId`는 바꾸지 않는다.
- 생성자는 id를 받지 않는다(7.2.5 — `idFor(pageId)`). `fromJson`은 JSON의 `id`가 `idFor(pageId)`와 다르면 `FormatException`.
- `updatedAt` 기본값 = `createdAt`(1차 엔티티와 같음).
- 손글씨 결과는 노트 범위 동기화 기록이고(7.2.8), 페이지 되살림 근거가 아니다(파생 데이터 — SYNC).

#### 6.9.2 `sourceRevOf` · `isRecognitionInput`

- `isRecognitionInput(s)` = `s.style.tool ∉ {highlighter, tape, laser}`. 삭제 여부는 호출자가 거른다(`sourceRevOf`에는 활성 획만 넘긴다 — 7.2.5 주석 'active strokes').
- `sourceRevOf(strokes)`: 획을 id 오름차순(`String.compareTo` — UTF-16 순서, VM·웹 같음)으로 놓고 `"<id>:<updatedAt>;"`를 이어 붙인 UTF-8의 SHA-256(`package:crypto` — 순수 Dart, 웹 동일), 소문자 hex 앞 16자. 입력이 비면 `'e3b0c44298fc1c14'`(빈 문자열 해시).
- 고정 벡터 시험(VM·Chrome 같은 값)을 `test/model/handwriting_text_test.dart`·`test/shared/search_text_cases.dart`에 둔다.

#### 6.9.3 `stalePages` · `notesWithStalePages` — 페이지 캐시 열

계약은 '점 디코드 없이 DB 열로 싸게'다. 노트 전체 획 행을 매번 읽지 않도록 **페이지 행에 기기 로컬 캐시 열 두 개**를 둔다.

| 열 (`pages`, 로컬 — 버전·outbox 없음) | 뜻 |
|---|---|
| `ink_rev TEXT NULL` | 그 페이지 입력 획의 `sourceRevOf` 값 |
| `ink_rev_at INTEGER NULL` | `ink_rev`를 계산했을 때의 `content_rev` |

```text
refresh(P):   -- 캐시가 낡은 페이지만 다시 계산 (stalePages·notesWithStalePages 공용)
  D = { p ∈ P | p.ink_rev_at IS NULL OR p.ink_rev_at != p.content_rev }      -- 내용이 바뀐 페이지만
  D를 50쪽씩: SELECT page_id, id, updated_at, tool FROM strokes WHERE page_id IN (…) AND deleted_at IS NULL  (idx_strokes_page)
       → 페이지마다 입력 획만 골라 sourceRevOf → 쓰기 큐 로컬 작업 하나로 ink_rev·ink_rev_at 갱신(outbox·ChangeBatch 없음)
       → 묶음 사이 이벤트 루프에 양보(await)

stalePages(noteId):
  1. P = SELECT id, sort_key, content_rev, ink_rev, ink_rev_at FROM pages WHERE note_id = ? AND deleted_at IS NULL
  2. refresh(P)
  3. H = SELECT page_id, source_rev FROM handwriting WHERE note_id = ? AND deleted_at IS NULL
  4. 낡음 = { p | H[p] 없음 ∧ ink_rev(p) ≠ 빈 집합 해시 }  ∪  { p | H[p] 있음 ∧ ink_rev(p) ≠ H[p] }
  5. 페이지 순서(sort_key ↑, 같으면 id ↑)로 반환

notesWithStalePages():   -- (v2.1, C21-09) 색인기 시작 때 따라잡기
  1. P = 활성 노트(휴지통 아님, 현재 소유자)의 활성 페이지 전부
  2. refresh(P)          -- 캐시가 최신인 페이지는 읽지 않는다
  3. 한 질의: pages ⋈ notes LEFT JOIN handwriting ON page_id, 위 4의 조건을 만족하는 페이지가 있는 노트
  4. notes.updated_at ↓, 같으면 id ↑ (가장 최근 노트 먼저 — 원문)
```

- `content_rev`는 획·객체가 바뀐 모든 커밋(로컬·undo·원격)에서 오르는 1차 로컬 열이다(1차 T10·T14). 그래서 `ink_rev_at`과 같으면 입력 획이 바뀌지 않았다. 객체만 바뀐 페이지도 다시 계산하지만 결과는 같다(무해).
- `notesWithStalePages`는 `refresh`를 먼저 해 **정확한 답**을 낸다(낡았을 수 있는 노트를 다 내는 상위 집합이 아니다) — 가짜(메모리 획으로 직접 계산)와 공유 계약 본문에서 같은 결과여야 하기 때문이다. 캐시가 최신인 뒤에는 3단계 질의 하나다.
- (v2.1 보정, 검토 S-10) **'`points` 열은 읽지 않음'의 실제 뜻**: SQLite는 요청한 열만 *디코드*하지만, `strokes.updated_at`은 `points` BLOB **뒤** 열이라(1차 `tables.dart` 115·125행 — `points` 다음에 `point_count`·`min_x…`·`created_at`·`updated_at` [확인]) 레코드 머리를 따라 BLOB을 건너뛰어야 한다. BLOB이 페이지에 들어가면 같은 페이지 안의 건너뛰기라 추가 I/O가 없고, 긴 획(약 4 KB 넘는 BLOB)만 넘침 페이지 사슬을 따라 읽는다. 컨테이너 실험(VM 파일 DB, 획 10만 개·5 %가 6 KB, `/tmp/claude-0/plan57-scratch/core57-rev/bin/stale.dart`): 5,000쪽 전부 읽기 **121~163 ms**, 덮개 색인 `idx_strokes_ink (page_id, deleted_at, tool, updated_at, id)`를 두면 **75~104 ms**이고 DB가 **+10.3 MiB** 커졌다(135.0 → 145.3 MiB) [확인]. 색인기는 네이티브에서만 돌고(G-1) 첫 따라잡기는 한 번이지만, 덮개 색인은 웹 DB(열 때 통째로 메모리 — 6.10.7)까지 키우므로 **넣지 않는다**. PF-11이 예산을 넘으면 그때 다시 본다(스키마 v2는 2차 통합 전까지 바꿀 수 있다 — 배포 전).
- 마이그레이션 직후에는 모든 페이지가 D에 들어 첫 `notesWithStalePages`가 라이브러리의 모든 획 행을 한 번 읽는다. 예산(6.19 PF-11): 획 10만 개 라이브러리에서 첫 `notesWithStalePages` + 각 노트 `stalePages` 합계 ≤ 1.5 s(VM), 그 뒤 호출 ≤ 30 ms. 실험값(읽기 0.12~0.16 s) + SHA-256(획당 약 45바이트 — 합 4.5 MB)으로 본 추정이다 [추측].
- 예산(6.19 PF-6): 20쪽 × 1,000획 노트에서 첫 `stalePages` ≤ 150 ms, 바뀐 페이지 1개일 때 ≤ 10 ms(VM).
- 가짜는 메모리 획으로 직접 계산한다(같은 결과 — 공유 계약 시험 `handwriting_contract`).

#### 6.9.4 `put` · `update` · `removeForPage` · 조회

| 멤버 | 규칙 |
|---|---|
| `put(value)` | 페이지 행이 없으면 `EntityNotFoundException`. 페이지의 `noteId ≠ value.noteId`면 `ArgumentError`. 줄의 `alternatives` > 5개, `languageTag`가 비었으면 `ArgumentError`. 새 행이면 `putLocal {*}`, 있으면 바뀐 JSON 키만(삭제됐던 행이면 `deletedAt`도 풀림). 같은 트랜잭션의 savepoint에서 ink 단위를 다시 색인(6.10.3). `ChangeBatch(local)`에 `handwriting` 변경 |
| `update(pageId, transform)` | (v2.1, C21-09·G-4) **쓰기 큐 작업 하나 = 한 쓰기 트랜잭션** 안에서 ① 저장된 행을 읽고(없거나 삭제됐으면 `null`) ② `transform(current)`을 **동기로** 부르고 ③ 결과가 `null`이면 쓰지 않고 지금 저장된 값(활성 행 또는 `null`)을 돌려주며 ④ 아니면 `put`과 같은 검증(+ 결과의 `pageId == pageId`)을 거쳐 같은 방식으로 쓰고, 저장된 값(CORE가 채운 `updatedAt`·`version`)을 돌려준다. `transform`이 던지면 트랜잭션을 되돌리고 그 예외로 끝난다. 큐가 작업을 차례로 돌리므로 그 사이에 다른 `put`·`update`·원격 적용이 끼어들지 않는다 |
| `removeForPage(pageId)` | 활성 행이면 소프트 삭제(`{deletedAt}`) + ink 단위 제거. 없으면 아무것도 안 함 |
| `forPage` | 활성 행 또는 null |
| `watchPage` | 구독 즉시 1회 + 그 행이 바뀐 커밋마다(삭제·없음은 null), 같은 값이면 내지 않음 |

- `transform`은 동기·순수 함수다(원문 '(no await inside)'). 타입이 `HandwritingText? Function(HandwritingText?)`라 `async`를 넘기면 컴파일되지 않는다. 안에서 저장소 쓰기를 부르면 같은 큐를 기다려 교착이 되므로, `transform`이 도는 동안의 쓰기 API 호출은 `StateError`로 바로 실패시킨다(`Zone` 표시 — 1차 '재진입 금지' N-2와 같은 취지).
- **경합 사례**(공유 계약 본문 `test/shared/handwriting_contract.dart` — 가짜·실제 둘 다, 검토 CORE-M7):
  1. `await` 없이 `update` 두 번 → 둘째 `transform`이 첫째 결과를 `current`로 받는다(확정 줄 유지 병합이 앞 쓰기를 잃지 않음).
  2. `put(A)` 직후 `await` 없이 `update` → `transform`이 A를 받는다.
  3. 실제만: 색인기 흉내(`forPage` → 인식 중 `await`) 사이에 `applyRemote`로 원격 결과 B 도착 → `update`의 `transform`이 B를 받는다(원격 결과를 덮지 않음 — G-4).
  4. `transform`이 `null` → 쓰기·`ChangeBatch`·outbox 없음, 반환 = 저장된 값.
  5. `transform`이 던짐 / 검증 실패(`ArgumentError`) → 아무것도 바뀌지 않고 그 예외.
  6. 삭제된 행 → `transform(null)`, 결과를 쓰면 되살아남(`deletedAt` 풀림 — `put`과 같음).
  7. 없는 페이지 → `EntityNotFoundException`(`transform`을 부르기 전).
- 원격으로 온 손글씨 결과(실연결 뒤)도 `putRemote` 훅에서 같은 색인을 한다. 웹은 이 경로로만 손글씨 검색이 된다.
- 확정 줄 유지 규칙(7.2.5 `userConfirmed` 주석)은 recog가 `transform` 안에서 적용한다. CORE는 규칙을 해석하지 않는다.
- 히스토리 밖(R-8과 같은 취지). 노트 복사·영구 삭제는 6.14.


### 6.10 검색 색인 (새 — 1차 6.8 제목 검색 확장)

#### 6.10.1 `SearchText.normalize` — 정규화 하나

제목(`searchLibrary`)·PDF·손글씨·텍스트 상자·수식이 모두 이 함수 하나를 쓴다(7.2.5). PDF 1차 `PdfTextNormalizer`(PDF 6.10.1 — `/home/user/wt/pdf/packages/pdf_io/lib/src/text/text_normalizer.dart`)의 단계와 **같은 결과**가 되게 그 단계를 그대로 옮기고, 질의형(`normalizeQuery`)처럼 앞뒤 공백을 자른다.

| 단계 | 규칙 |
|---|---|
| 1 | 줄 끝 하이픈 잇기: 글자·숫자 + `-` + (`\r`?`\n`) + 글자·숫자 → `-`와 줄바꿈을 지움 |
| 2 | U+00AD, U+200B..U+200D, U+FEFF를 지움 |
| 3 | 공백 연속(Dart·JS `\s` 집합을 **코드 단위 목록으로 고정** — U+00A0·U+3000 포함, 단계 2 문자가 섞여도 한 덩어리) → 공백 하나 |
| 4 | 한글 조합형 자모(L + V [+ T], LV 음절 + T) → 완성형 음절 |
| 5 | **코드 포인트마다** 소문자(문맥 의존 규칙 없음 — 웹 `String.toLowerCase`의 그리스어 끝 시그마 같은 차이를 피해 VM·웹이 같게) |
| 6 | 앞뒤 공백 제거 |

- `normalizerVersion = 1`. 규칙을 바꾸면 이 값을 올리고, 저장소를 열 때 kv `search.normalizerVersion`과 다르면 색인을 다시 만든다(6.10.5).
- 1차 `common/text_normalize.dart`의 `normalizeForSearch`(제목 검색·`name_norm`·`title_norm` 열)는 내부 이름만 남기고 `SearchText.normalize`에 위임한다. (v2.1, 검토 S-16) 이 위임은 **T24**(마이그레이션 단계 5와 같은 작업)에서 한다 — 마이그레이션이 새 함수로 다시 계산한 열과 쓰기 경로가 만드는 열이 개발 중에 섞이지 않게. 1차 함수와 다른 점은 단계 1·2·5뿐이라 차이는 하이픈·줄바꿈·폭 없는 문자가 든 제목에서만 난다. 마이그레이션이 `name_norm`·`title_norm`을 새 함수로 다시 계산한다(파생 열 — 엔티티·버전·outbox 그대로, 6.12.1).
- (v2.1, CP-10 승인) `SearchText.normalizeMapped(text)`(정규화 결과의 코드 단위 → 원문 범위, PDF `PdfNormalizedText`와 같은 모양 — 4.6 `SearchTextMapping`)로 발췌의 일치 범위를 원문에 되돌린다(6.10.4). 공개 함수이고 PDF가 하이라이트용 사본을 없애고 이것을 감쌀 수 있다. `normalizeMapped(x).text == normalize(x)`를 `search_text_cases` 전부에서 단언한다.
- VM·Chrome 동치: `test/shared/search_text_cases.dart`(한글 NFD·자모·하이픈 줄바꿈·폭 없는 문자·NBSP·전각 공백·터키어 İ·그리스어 Σ·이모지·라틴 악센트) → VM `test/search/search_text_test.dart` + Chrome `test/web/search_text_browser_test.dart`. PDF는 같은 입력 표를 자기 시험에 복사해 `PdfTextNormalizer`와 비교한다(C2-27 — PDF 몫).

#### 6.10.2 낱말 · 색인 낱말 · 질의 · 일치 판정

조사 03 9.2의 '음절 바이그램을 Dart에서 만들어 `unicode61` 내용 없는 테이블에 넣는' 방식이다. 규칙은 모두 `search/search_text.dart` 한 곳에 있고, 실제 FTS 경로와 가짜 메모리 경로가 같은 판정 함수로 결과를 확정한다(6.10.6).

- **낱말(run)**: 정규화된 글에서 `[\p{L}\p{N}\p{Co}]+`(유니코드 속성 정규식 — VM·웹 지원)의 최대 연속. FTS5 `unicode61`의 기본 토큰 문자 범주(`L* N* Co`)와 같다. 그 밖(공백·문장 부호·기호·결합 표시)은 구분자다.
- **CJK 낱말**: 한글·한자·히라가나·가타카나(`\p{Script=Hangul}`·`Han`·`Hiragana`·`Katakana`) 글자를 하나라도 가진 낱말.
- **`indexTerms(normalized)`**: 낱말마다 — CJK 낱말이면 코드 포인트 겹침 바이그램(`회의록을` → `회의 의록 록을`, 한 글자 낱말은 그대로), 아니면 낱말 그대로. 공백으로 이어 FTS `g` 열에 넣는다.
- **`matchQuery(normalized)`**: 질의 낱말 중 **두 글자 이상**만 쓴다. CJK 낱말 → 바이그램 구(`"방정 정식"`), 아닌 낱말 → 접두사(`"meet"*`). 여럿이면 ` AND `. 두 글자 이상 낱말이 하나도 없으면 `null`(→ LIKE 경로). 각 항목은 큰따옴표로 감싸고 안의 `"`는 두 번 쓴다(FTS 문법 주입 방지).
- **일치 판정 `searchMatches(unitNorm, queryNorm)`**(내부, 실제·가짜 공용 — 최종 결과를 정한다): 질의 낱말 `q`가 **모두** 다음을 만족해야 한다.

| `q` | 만족 조건 |
|---|---|
| 한 글자 | `unitNorm`이 `q`를 포함 |
| 두 글자 이상, CJK | 단위의 어떤 CJK 낱말 `r`이 `q`를 부분 문자열로 포함 |
| 두 글자 이상, CJK 아님 | 어떤 비CJK 낱말 `r`이 `q`로 시작, 또는 (`q`가 두 글자이고) 어떤 CJK 낱말이 `q`를 포함 |

- FTS 후보는 판정을 만족하는 단위를 모두 포함한다(바이그램 구 = 낱말 안 부분 문자열의 상위 집합, 접두사 = 낱말 시작). 판정이 낱말 경계를 넘는 구 일치(`방정 정식` 두 낱말) 같은 거짓 양성을 걸러낸다.
- 알려진 한계(조사 03 9.2): CJK가 섞인 낱말 안의 세 글자 이상 라틴 부분(`aim모델`의 `aim`)은 찾지 못한다. 한 글자 CJK 질의는 LIKE 경로라 낱말 끝 음절도 찾는다.

| 질의 (조사 03 9.2 표 + 더함) | 경로 | 찾는 문서 |
|---|---|---|
| `회의`, `회의록`, `의록` | FTS 구 | 1(`오늘 회의록을 정리했다 meeting notes`) |
| `정식` | FTS 구 | 2(`방정식`), 4(`정식 계약서`) |
| `정`, `록` | LIKE | 포함하는 모든 문서 |
| `meet`, `LAPLACE` | FTS 접두사 | 1, 2 |
| `확률 통계`, `단어 암기` | FTS AND | 3, 5 |
| `방정 정식`(낱말 둘) | FTS AND + 판정 | 2(두 낱말 모두 `방정식`에 포함) |
| `eeting` | FTS 접두사 → 0건 | 없음(비CJK는 낱말 시작만 — 가짜도 같음) |

#### 6.10.3 테이블과 쓰기 경로

| 원천 `SearchSource` | 소유자 키 | `sourceRev` | 단위 | 쓰는 쪽 |
|---|---|---|---|---|
| `text` | 객체 id | `<객체 version>:<normalizerVersion>` | 상자 하나 = 단위 하나(`body` = `text`, 사각형 = `bounds` 하나) | CORE(객체 쓰기 훅) |
| `math` | 객체 id | 같음 | 수식 하나(`body` = `latex`) | CORE |
| `ink` | `hw_<pageId>` | `<HandwritingText.sourceRev>:<version>:<normalizerVersion>` | 줄 하나 = 단위 하나(`body` = `line.text`, 사각형 = `line.rect` 하나, 빈 줄 제외) | CORE(손글씨 쓰기 훅) |
| `pdf` | `<assetId>#<pdfPageIndex>` | (v2.1 원문) `<assetId>:<normalizerVersion>` + 선택 꼬리 `:x<extractorVersion>`(CP-PDF-2) — CORE는 **문자열 그대로** 저장·비교하고 해석하지 않는다(≤ 200자) | PDF가 정함 — (v2.1 PDF 결정, 12.2 Q3) **쪽 하나 = 단위 하나 + 글자마다 상자**(`rects.length == body.length`), 30,000자 넘는 쪽은 줄 경계로 나눔 | `pdf_io` → `SearchIndexWriter` |

- 테이블(6.11): `search_owners`(소유자 행 — 원천·키·노트·페이지·`sourceRev`·보류 표시), `search_units`(단위 행 — 원문 `body`, 정규화 `norm`, 비pdf 사각형 4열, pdf는 `asset_id`·`pdf_index`·사각형 블롭 참조 `rects_ref`·`pdf_aspect`), `search_fts`(FTS5, rowid = 단위 id). 계약 표의 `search_units`·`search_fts`에 소유자 테이블을 더한 것이다 — 한 소유자가 단위 여럿을 가지므로(`replaceUnits`의 목록) 계약 표의 `UNIQUE(source, owner_key)`를 소유자 테이블로 옮기고 단위는 `UNIQUE(source, owner_key, seq)`로 둔다(v2.1 원문 표에 반영됨 — CP-15).
- (v2.1, CORE-M1 — CD2-11) **PDF 글자 상자는 SQLite 밖**(블롭 저장소 — 웹 IndexedDB `noteapp_blobs`, 네이티브 파일 블롭, 1차·6.15.3 경로 그대로)에 둔다. 웹 DB는 열 때 파일 전체가 메모리에 올라오므로(6.10.7) 큰 BLOB을 넣지 않는다는 1차 원칙('대용량 바이트는 SQLite에 넣지 않는다')을 색인에도 지킨다. 검토 Q-3 답(기본 = SQLite 밖)과 같다. 압축 BLOB(SQLite 안)은 실험(6.10.7)에서 8 B/글자 형식으로도 500쪽 한국어 17.2 MiB라 12 MB 목표를 넘어 고르지 않았다.
  - 키: `si/pdf/<assetId>/<pdfPageIndex>/<token>` — `token`은 `replaceUnits` 한 번마다 새로 뽑는 16 hex + `-<seq 4자리>`(같은 키를 덮어쓰지 않는다 — 아래 순서). 소유자 키의 `#`를 `/`로 바꾼 꼴이라 파일 블롭에서도 안전한 경로다.
  - 형식(CORE 내부 `search/search_rects.dart` `SearchRectsCodec`): 머리 `"SR"` + 판 1 + 글자 수 `n`(uint32) + 줄 묶음 수 `L`(uint32) / 줄 묶음마다 시작 글자·길이(uint32 둘) + `top`·`bottom`(uint16 둘) / 글자마다 `left`·`right`(uint16 둘). 좌표는 쪽 비율 × 65535를 반올림한 정수(정밀도 1/65535 — 7.2.5 '≥ 1/65535'). 같은 `top`·`bottom`이 이어지는 글자들이 한 줄 묶음이다. `PageRect.zero`는 `left = right = top = bottom = 0`으로 그대로 담는다(읽을 때 건너뜀). 크기 ≈ 4 B/글자 + 12 B/줄(2,500자 쪽 약 11 KB). 모든 수는 리틀 엔디언 `ByteData`(64비트 정수 없음 — 1차 7.4.3 웹 안전 수치).
  - `pdfPageAspect`(CP-3)는 `search_units.pdf_aspect REAL NULL`에 둔다(대표 결과의 좌표 변환에만 쓰므로 블롭을 읽기 전에 안다).
- **`replaceUnits(pdf, key, units, sourceRev:)` 순서**: ① 사각형이 있는 단위마다 새 `token` 키로 블롭 `put`(완료를 기다림) ② 한 큐 작업: 옛 단위 행·FTS 행 삭제(옛 `rects_ref` 모음) → 새 단위 행(`rects_ref` = ①의 키)·FTS 행 → 소유자 행 upsert(`sourceRev`, `pending = 0`) → 커밋 ③ 커밋 뒤(`afterCommit`) 옛 `rects_ref` 블롭 삭제. ②가 실패하면 ①의 새 블롭을 지운다(최선 노력). 어디서 끊겨도 참조되지 않는 블롭만 남고, 저장소를 연 뒤 색인을 처음 쓸 때 `si/` 아래 키 중 `search_units.rects_ref`에 없는 것을 한 번 정리한다(초안 고아 정리와 같은 방식 — 열기를 막지 않음). 블롭이 없는 `rects_ref`(정리 경합)는 '사각형 없음'으로 읽는다 — 색인은 파생 데이터라 결과는 그대로 나온다(C-13).
- (v2.1, 검토 S-6 — C21-09) **빈 단위 목록**: `replaceUnits(source, key, [], sourceRev: r)`도 소유자 행을 `r`로 남긴다(단위·FTS·블롭은 모두 지움). 그 뒤 `sourceRevOf`·`sourceRevs`가 `r`을 돌려준다 — 글자 없는 스캔 쪽과 pdf_io의 '`#0` 마지막 = 완료 표시'(06-pdf 6.4.2)가 이것에 기댄다. 소유자를 없애는 것은 `removeOwner`뿐이다.
- FTS 테이블: `CREATE VIRTUAL TABLE search_fts USING fts5(g, content='', contentless_delete=1, tokenize='unicode61 remove_diacritics 0')`(v2.1 원문 표와 같음).
  - `content=''`: 원문은 `search_units`에만 둔다(색인 크기 — 조사 03 9.2).
  - `contentless_delete=1`(SQLite 3.43+): 내용 없는 테이블에서도 `DELETE … WHERE rowid = ?`가 된다 — 지울 때 옛 색인 낱말을 다시 만들 필요가 없다. [확인 — `/tmp/claude-0/plan57-scratch/core57/bin/probe.dart`, sqlite3 3.8.0(SQLite 3.54.1) VM에서 생성·MATCH·DELETE·재삽입·`INSERT OR REPLACE`·`bm25()` 모두 동작(검토자 재실행 같은 결과). 웹 `sqlite3.wasm`은 같은 SQLite 판이고 T33a의 Chrome 시험이 다시 확인한다.]
  - `remove_diacritics 0`: 악센트를 접지 않아 FTS 후보와 판정(부분 문자열)이 같은 의미가 된다. [확인 — 같은 실험에서 `cafe`는 `café`에 일치하지 않음]
- 쓰기 훅(`storage/search_indexer.dart`): `WriteTxn.putLocal`·`putRemote`가 `TextBoxObject`·`MathObject`를 쓰면 그 소유자를 다시 색인하고, 삭제(`deletedAt`)면 소유자를 지운다. `HandwritingText`도 같다. 도형·이미지·`UnknownObject`는 글이 없어 색인하지 않는다. 페이지 삭제·노트 휴지통은 색인을 지우지 않고 질의 때 거른다(복원하면 바로 다시 찾힘). 영구 삭제는 그 노트의 소유자를 지운다(pdf 소유자는 에셋 단위라 남는다).
- `SearchIndexWriter`(pdf 전용) 검증(어기면 `ArgumentError`, 아무것도 바꾸지 않음): `source != pdf`(ink·text·math는 CORE만 씀 — 7.2.5 주석), `ownerKey`가 `^[0-9a-f]{64}#[0-9]+$`가 아님, 소유자당 단위 > 10,000, `body` > 200,000자, `rects.length`가 0도 `body.length`도 아님, 비율 좌표가 유한하지 않거나 [0, 1] 밖(1e-6 허용 뒤 자름), `pdfPageAspect`가 있는데 유한한 양수가 아님, `sourceRev`가 비었거나 200자 초과. `replaceUnits`는 위 순서의 한 큐 작업이다(outbox·`ChangeBatch` 없음). `sourceRevs(pdf)`는 소유자 테이블 한 번의 질의다(P5 — PDF 수천 쪽 따라잡기).
- 쓰기 비용: 텍스트 상자 편집 세션 1회 = 단위 1개 지우고 넣기. 정규화·바이그램은 Dart에서 1만 자에 1 ms 수준이라 커밋 예산(1차 7 ms 중앙값)에 묻힌다 — T37에서 측정. pdf 한 쪽 = 블롭 하나(약 11 KB) + 행 하나 + FTS 행 하나.

#### 6.10.4 질의 (`searchPages` · `searchLibrary`)

```text
searchPages(query, limit = 100, withinNote):
  q = SearchText.normalize(query); q가 비면 []
  runs = q의 낱말
  -- 1) 후보: 원문·사각형을 읽지 않는다 (CORE-M1)
  열 = u.id, u.source, u.owner_key, u.note_id, u.page_id, u.asset_id, u.pdf_index, u.norm
  if 두 글자 이상 낱말 없음:  후보 = SELECT 열 FROM search_units u WHERE (u.norm LIKE '%x%' ESCAPE '\' 낱말마다 AND) AND 살아있음(u)
                                      ORDER BY u.id DESC LIMIT 2000
  else:                        후보 = SELECT 열 FROM search_fts f JOIN search_units u ON u.id = f.rowid
                                      WHERE f MATCH matchQuery(q) AND 살아있음(u) ORDER BY f.rowid DESC LIMIT 2000
  살아있음(u): 비pdf → EXISTS pages(id = u.page_id, deleted_at IS NULL) ⋈ notes(deleted_at IS NULL, owner_id = 현재 소유자)
               pdf   → EXISTS pages(bg_asset_id = u.asset_id, bg_pdf_index = u.pdf_index, deleted_at IS NULL) ⋈ notes(…)
               withinNote가 있으면 그 노트만
  -- 2) 판정·펼침·점수: norm만으로
  판정:      searchMatches(u.norm, q) — 거짓이면 버림
  펼침:      pdf 단위 → 그 에셋 쪽을 배경으로 쓰는 살아 있는 노트 페이지마다 하나 (한 질의로 모아 읽음)
  묶음:      (noteId, pageId)마다 단위들 → 점수 최대 단위가 대표
  정렬:      점수 ↓ → note.updatedAt ↓ → pageId ↑ ;  앞의 limit개
  -- 3) 돌려줄 페이지만: 원문·사각형 읽기
  SELECT id, body, rect_l, rect_t, rect_r, rect_b, rects_ref, pdf_aspect FROM search_units WHERE id IN (돌려줄 페이지의 일치 단위)
  pdf 대표 단위의 rects_ref → 블롭 묶음 읽기 한 번(내부 BlobStore.getMany — 웹은 IndexedDB 트랜잭션 하나), 일치 범위의 글자 상자만 푼다
```

- (v2.1, 검토 S-8 — C21-09) **후보 상한 2,000은 최근 단위 먼저**다: 단위 id(SQLite rowid — 새 행은 언제나 '지금 최대 + 1')의 내림차순. 흔한 낱말에서 결과가 오래된 내용으로 치우치지 않는다. `replaceUnits`·쓰기 훅은 옛 행을 지우고 새로 넣으므로 다시 색인된 내용도 '최근'이 된다. 후보는 살아 있는 단위만 센다(휴지통·삭제 페이지 단위가 상한을 먹지 않게). FTS5는 `ORDER BY rowid DESC`를 문서 목록 역순으로 바로 돌린다(정렬 단계 없음 — T33b `EXPLAIN QUERY PLAN` 단언).
- 후보 상한을 채우면 결과가 잘릴 수 있다 → `LibrarySearchResult.pagesTruncated = true`. 페이지가 `limit`보다 많아도 `true`(원문 '(v2.1, CP-14)').
- **점수**(내부 `search_ranking.dart`, 실제·가짜 공용 — `norm`만 씀): 단위 점수 = 원천 가중치(`text` 1.0, `math` 0.95, `ink` 0.9, `pdf` 0.8) + 0.3(첫 질의 낱말이 낱말 시작에서 일치) + 0.05 × min(첫 질의 낱말 일치 수, 6) − 0.0005 × min(첫 일치 위치, 400). 페이지 점수 = 대표 단위 점수 + 0.02 × min(일치 단위 수 − 1, 10). (v2.1 정정, 검토 S-15) 값은 정수만이 아니라 0.95·0.0005 곱이 든 실수다. 같은 입력이면 VM·웹·가짜가 같은 값을 내는 근거는 **같은 연산 순서의 IEEE 754 배정밀도 덧셈·곱셈**(Dart VM과 JS 모두 배정밀도, 융합 곱셈-덧셈 없음)이고, 결정성 시험(`search_query_test` — 고정 입력의 점수를 비트 단위로 VM = Chrome)이 묶는다.
- **발췌**(`snippet` ≤ 80자): 대표 단위의 원문(3단계에서 읽음)에서 첫 일치 범위(`normalizeMapped`로 원문 범위)를 중심으로 앞 30자부터 80자. 코드 포인트 경계에서 자르고, 줄바꿈·탭은 공백으로 바꾼다(길이 같음 — 범위 유지). `matchRange` = 발췌 안의 `[start, end)`.
- **사각형**(`rects`, 노트 페이지 pt):

| 원천 | 사각형 |
|---|---|
| `ink` | 일치한 줄(단위)들의 `line.rect`(최대 8개) |
| `text`·`math` | 객체 `bounds`(색인 때 저장 — 객체가 움직이면 다시 색인되므로 최신) |
| `pdf` | 글자 상자가 있으면 일치 범위 글자 상자를 **줄 묶음마다 합친** 상자(`PageRect.zero` 글자는 건너뜀 — v2.1 원문), 상자가 없으면 빈 목록. 비율 좌표 → pt: 1차 PDF `PdfPageFit`(contain, 가운데)를 `pdf_aspect`(CP-3)로 계산하고, `null`이면 비율 좌표 × 노트 페이지 크기(가져온 페이지는 PDF 페이지 크기 그대로라 정확 — 1차 PDF C-2) |

- `searchLibrary(query, {limit = 50})`: 폴더·노트(1차 그대로 — 정규화만 `SearchText`) + `pages = searchPages(query, limit: 100)`. 내용 결과가 많아도 `folders`·`notes`의 1차 의미는 그대로다.

#### 6.10.5 실패 격리 · 보류 · 재구축 · 상태 (C-13)

- 색인 쓰기는 원천 쓰기 트랜잭션 안의 **savepoint**에서 한다. 실패하면 savepoint만 되돌리고 소유자 행에 `pending = 1`을 남긴 뒤 원천 쓰기를 커밋한다(원천 쓰기의 Future는 정상 완료). 보류 표시조차 못 쓰면 오류를 삼키고 개발 로그에 남긴다(그때는 DB가 이미 망가진 상태).
- (v2.1 정정, 검토 S-12 — C-13 원문 '다음 쓰기 트랜잭션 또는 저장소 열기') **재시도는 타이머 없이**: 보류 소유자가 있으면 CORE의 **다음 쓰기 트랜잭션 끝**에서 최대 20개를 다시 색인하고, **저장소를 열 때** 보류가 있으면 큐 작업 하나를 넣는다. 쓰기가 없는 동안에는 보류가 남고, 그 상태는 `status.pendingOwners`(> 0)로 보인다(LIBRARY 개발자 표시·결과 화면 안내가 읽는다). `openTestNoteStore`가 타이머를 만들지 않는다는 1차 규칙(1차 T9 — 다른 영역 위젯 시험의 '타이머 남음')을 지킨다.
- `rebuild({sources})`: 시작 전에 `status`에 `rebuilding: true`를 내고, 고른 원천의 단위·소유자를 지우고 원천 행에서 다시 만든다 — `text`·`math`는 `page_objects`, `ink`는 `handwriting`에서 200개씩 끊어 큐 작업 여러 개로(쓰기 큐를 오래 막지 않게). 마지막 작업이 커밋된 뒤 `rebuilding: false`·`lastRebuildAt`. `pdf`는 CORE가 원문을 모르므로 pdf 단위·소유자·`si/pdf/` 블롭을 지우기만 하고, `PdfSearchIndexer`가 `rebuilding`이 거짓으로 돌아온 뒤 `sourceRevs(pdf)`가 빈 것을 보고 다시 채운다(v2.1 원문 '재구축 중 멈춤', 12.2 Q8). 멱등이다 — 두 번 돌려도 같은 행.
- 저장소를 열 때 kv `search.normalizerVersion`이 현재 값과 다르면 전체 `rebuild()`를 예약한다(열기를 막지 않음).
- `status`: 구독 즉시 현재 값 1회 + 바뀔 때. `pendingOwners` = 보류 소유자 수, `rebuilding` = 재구축 작업이 남아 있음, `lastRebuildAt` = kv `search.lastRebuildAt`.

#### 6.10.6 가짜 색인과의 동치 (CP-14 승인 — v2.1 원문 '같은 판정·같은 순서')

- 가짜 저장소(`fake/memory_search_index.dart`)는 단위를 메모리 목록에 두고 실제와 **같은 단계**를 밟는다: ① 단위 id를 실제와 같은 규칙(새 단위 = 지금 최대 id + 1, 빈 목록이면 1)으로 매기고 ② **FTS 후보 흉내** `ftsCandidateMatches(indexTerms(u.norm), matchQuery(q))`(내부, `search_text.dart` — 우리가 만드는 질의 모양인 바이그램 구·접두사·`AND`에 대한 FTS5 의미: 구 = 색인 낱말 열의 연속 일치, 접두사 = 어떤 색인 낱말의 시작) 또는 1글자 LIKE 경로(`norm`이 포함)를 만족하고 살아 있는 단위를 id 내림차순으로 2,000개까지 고르고 ③ 같은 `searchMatches`·`search_ranking.dart`로 판정·점수·발췌·사각형을 만든다. 그래서 **후보 상한에 걸릴 때도** 실제와 가짜의 결과·순서·`pagesTruncated`가 같다(v2.0 계획의 '상한에 걸리지 않는 한 같음' 예외를 없앴다 — 검토 S-8).
- `ftsCandidateMatches`가 SQLite FTS5와 같은지는 무작위 시험이 묶는다(`test/search/fts_candidate_equivalence_test.dart` — 고정 시드 단위 2,000개·질의 500개에서 FTS5 `MATCH` 결과 집합 = 흉내 결과 집합, VM + `test/web/search_fts_browser_test.dart`).
- 공유 본문 `test/shared/search_contract.dart`(V10 질의 표 + 6.10.2 표 + 휴지통·삭제 페이지 제외 + `withinNote` + pdf 공유 에셋 + 발췌·범위 + 빈 단위 목록의 소유자 유지 + 후보 2,000 초과 시 최근 우선·`pagesTruncated` + `PageRect.zero` 건너뜀 + `pdfPageAspect` 변환)를 가짜(`test/search/search_contract_fake_test.dart`, B2-β T23b)와 실제(`…_real_test.dart`, T33b)·Chrome(`test/web/search_fts_browser_test.dart`)에 돌린다.

#### 6.10.7 크기 · 성능 (v2.1 — CORE-M1, CD2-11)

- **웹 DB 메모리·열기 시간이 왜 문제인가**: iPad Safari는 `sharedIndexedDb`로 동작하고(1차 7.4.9), sqlite3 3.8.0의 `IndexedDbFileSystem`은 열 때 그 파일 시스템의 **모든 파일을 메모리로 읽어** 들고 있다(`lib/src/wasm/vfs/indexed_db.dart` `_readFiles` [확인]). 1차 실측: 획 10만 개 ≈ 76 MB DB의 열기 1.6~1.7 s(1차 02-core). 그래서 색인이 키운 DB 바이트가 그대로 앱 시작 시간과 메모리(7.4.5 '웹 합계 ≤ 300 MB' 밖의 DB 메모리 사본)를 깎는다.
- **목표**(7.4.5 v2.1 원문): 실제 모양(쪽당 2,000~3,000자 + 글자 상자, 한국어·영어) 500쪽 색인이 DB 파일을 **≤ 12 MB** 키우고, Chrome 저장소 다시 열기 시간 증가 **≤ 300 ms**.
- **실험**(컨테이너 VM, sqlite3 3.8.0 파일 DB `page_size` 4096, 쪽당 2,500자 합성 — 한국어: 음절 400개·낱말 4,000개 Zipf 분포, 혼용: 낱말 30 %가 영어, 영어: 영어 낱말만, 실제 색인과 같은 바이그램 `g`·FTS 옵션, `optimize`·`VACUUM` 뒤, `/tmp/claude-0/plan57-scratch/core57-rev/bin/size.dart`) [확인]:

| 500쪽 DB 크기 | 한국어 | 혼용 | 영어 |
|---|---|---|---|
| FTS + `norm` | 5.50 MiB | 3.89 MiB | 2.33 MiB |
| FTS + `norm` + `body` (**채택 — 사각형은 SQLite 밖**) | **7.70 MiB** | **6.67 MiB** | **2.82 MiB** |
| + 사각형 float32 16 B/글자 BLOB (v2.0 계획) | 26.98 MiB | 25.40 MiB | 22.11 MiB |
| + 사각형 uint16 8 B/글자 BLOB | 17.22 MiB | 15.96 MiB | 12.37 MiB |

  - 채택안은 목표(12 MB) 안이다. 다시 열기 시간은 1차 비율(76 MB에 약 1.6 s ≈ 21 ms/MB)로 보면 7.7 MiB ≈ 170 ms [추측] — Chrome 시험이 잰다. 사각형 블롭은 IndexedDB `noteapp_blobs`(열 때 읽지 않음)에 500쪽 약 5.5 MB 생긴다.
  - 합성 자료의 음절 분포는 실제 교재와 다르다(실제 한국어는 쓰이는 음절이 더 많아 바이그램 종류가 늘 수 있음) [추측]. 실제 PDF로 잰 값이 목표를 넘으면 ① `body`도 블롭으로 옮긴다(한국어 −2.2 MiB — 대표 결과만 읽으므로 질의 비용은 블롭 읽기 몇 번) ② 그래도 넘으면 색인 범위 축소(노트가 쓰는 쪽만)를 총괄에 올린다(7.4.5 원문).
- **시험**: PF-10(6.19) — 실제 모양 500쪽 합성 고정 자료(위와 같은 생성기, 시드 고정, 한국어·혼용·영어 각각, 글자 상자 포함)로 `replaceUnits` 시간·DB 증가 바이트·블롭 바이트·질의 시간을 잰다(VM). `test/web/search_reopen_time_browser_test.dart`(T33b, 1차 `open_time_browser_test` 방식 — `perf` 태그): 같은 자료 500쪽을 실제 웹 저장소에 색인 → 닫기 → 다시 열기 시간을 색인 전과 비교해 진행 기록에 남기고 +300 ms 안인지 단언한다(기록 실패 시 load를 함께 남김 — 1차 9.1 부하 규칙).
- 조사 03 9.2의 '5,000쪽 × 80낱말, 사각형 없음' 합성 색인은 **질의 속도 예산**(V10 — v2.5 C25-01)용으로 남긴다(PF-3·PF-4). 크기 판정은 위 실제 모양 자료로 한다(검토 M-1 ③).
- 질의 예산(V10 — (v2.5) C25-01, 12.1 **CP-18** 승인): 5,000쪽 합성 색인에서 **후보 100개 미만** 질의(2·3글자·낱말 중간·영문 접두사·AND) 중앙값 ≤ 5 ms(VM), 1글자 LIKE ≤ 15 ms(VM), **그 밖의 질의**(후보 상한 2,000까지 읽음) ≤ 50 ms(VM). 후보 수는 FTS5 MATCH·LIKE 행(상한 전)이고 시험이 질의마다 세어 예산을 고른다. 7.2.5 후보 규칙(살아 있는 후보만 2,000개, 최근 먼저)과 CP-14(가짜와 같은 판정·순서)는 그대로다 — 흔한 낱말(1,000~5,000개)의 20~46 ms는 이 두 규칙(후보마다 살아있음·`norm` 판정·점수)과 돌려주는 쪽 수(100까지)에서 나온다. (동시 개발 T33b — v2.4까지의 원문 '중앙값 ≤ 5 ms, 1글자 LIKE ≤ 15 ms'는 흔한 낱말이 넘어 CP-18을 올렸다.) 실제 모양 500쪽(사각형 블롭 읽기 포함, 결과 100쪽) 중앙값 ≤ 50 ms(VM — T33b 첫 측정 32~42 ms로 확정, 같은 프로세스 저장소에서 단언, 네이티브 저장소는 기록). Chrome(DDC)은 기록만 한다(1차 T16 방식).

### 6.11 DB 스키마 v2 (1차 6.11 확장)

`kDatabaseSchemaVersion = 2`(T24 — 기반 단계에서는 1 그대로, C2-07 '동시 개발'). 1차 규칙 그대로: 외래 키 없음(고아 허용), 시간은 정수 ms, 엔티티 테이블마다 `field_versions`, 행 클래스 이름 `XxxRow`.

| 테이블 | 열 | 색인 | 비고 |
|---|---|---|---|
| `page_objects` (새) | `id` PK, `page_id`, `note_id`(비정규화 — 원격 고아는 `''`), `type`, `min_x`·`min_y`·`max_x`·`max_y`(= `bounds`), `data_json`(종류별 키 + `frame` — `toJson`에서 메타 키를 뺀 것), `asset_id`(이미지, (v2.1) 그리고 최상위 `assetId`가 에셋 id인 `UnknownObject` — 4.3·검토 S-13), `created_at`, `updated_at`, `deleted_at`, `version`, `field_versions` | `idx_objects_page (page_id, deleted_at)`, `idx_objects_note (note_id)`, `idx_objects_asset (asset_id)` | 7.2.7 표 그대로 |
| `handwriting` (새) | `id` PK(`hw_<pageId>`), `page_id`, `note_id`, `engine_id`, `source_rev`, `lines_json`, `created_at`, `updated_at`, `deleted_at`, `version`, `field_versions` | `idx_handwriting_note (note_id, deleted_at)` | |
| `recordings` (변경) | + `title TEXT NULL` | + `idx_recordings_note (note_id, deleted_at)` | 1차에는 노트별 색인이 없었다 — `watchRecordings`용 |
| `pages` (변경) | + `ink_rev TEXT NULL`, `ink_rev_at INTEGER NULL`(로컬 캐시 — 6.9.3), + `bg_asset_id TEXT NULL`, `bg_pdf_index INTEGER NULL`(배경에서 파생 — pdf 검색 결과를 노트 페이지로 펼침, 이미지 페이지 참조) | + `idx_pages_bg (bg_asset_id, bg_pdf_index)` | 파생·로컬 열 — 버전·outbox 없음, 행 변환이 페이지를 쓸 때마다 채움 |
| `recording_drafts` (새) | `draft_id` PK, `recording_id`(UNIQUE), `note_id`, `mime_type`, `started_at`, `chunk_count`, `bytes`, `active_ms`, `updated_at` | `idx_drafts_note (note_id)` | 기기 로컬 |
| `search_owners` (새) | `source`, `owner_key`, `note_id`(pdf NULL), `page_id`(pdf NULL), `source_rev`, `pending`(0/1), PK(`source`, `owner_key`) | `idx_search_owners_note (note_id)`, `idx_search_owners_pending (pending)` | 기기 로컬 파생 |
| `search_units` (새) | `id` INTEGER PK(rowid 별칭 — '최근 먼저' 순서, 6.10.4), `source`, `owner_key`, `seq`, `note_id`, `page_id`, `asset_id`·`pdf_index`(pdf만), `body`, `norm`, (v2.1) `rect_l`·`rect_t`·`rect_r`·`rect_b REAL NULL`(비pdf 단위의 사각형 하나 — 페이지 pt), `rects_ref TEXT NULL`(pdf 글자 상자 블롭 키 — SQLite 밖, 6.10.3), `pdf_aspect REAL NULL`(CP-3), UNIQUE(`source`, `owner_key`, `seq`) | `idx_search_units_note (note_id)`, `idx_search_units_pdf (asset_id, pdf_index)` | 기기 로컬 파생. (v2.0의 `rects` BLOB 열은 없앴다 — CORE-M1) |
| `search_fts` (새, 가상) | FTS5 `(g)` 6.10.3 문장 | — | rowid = `search_units.id` |
| `strokes` | 변경 없음 | 변경 없음 | `stalePages`는 `idx_strokes_page`(1차)와 페이지 캐시 열로 충분(6.9.3 — 덮개 색인은 실험 뒤 넣지 않음) — 계약 표의 '색인 범위 확인' 결과 |

- kv 키(`storage/kv_keys.dart`) 추가: `search.normalizerVersion`, `search.lastRebuildAt`, (v2.1) `db.v1Copy`(업그레이드 직전 v1 사본 정보 — 6.12.4).
- 블롭 저장소 키 접두사(기기 로컬 — 동기화·백업 없음): 에셋 `<sha256>/`(1차), 녹음 초안 `rd/`(6.7), (v2.1) 검색 글자 상자 `si/`(6.10.3), 웹 v1 사본 `db/v1-backup/`(6.12.4). 서로 겹치지 않는다(에셋 키는 64 hex로 시작).
- **FTS 테이블 만드는 방법**: drift가 모르는 가상 테이블이라 1안은 마이그레이션 단계와 `onCreate`(새 DB)에서 `customStatement`로 만들고, `schema_test`가 `sqlite_master`에서 `search_fts`와 그림자 테이블(`search_fts_data`·`_idx`·`_docsize`·`_config`)을 확인한다. (v2.1, 검토 확인) drift `SchemaVerifier`는 `ValidationOptions.validateDropped`의 기본값이 `false`라(`drift_dev-2.35.2/lib/api/migrations_common.dart` 181 [확인]) 스키마 밖 가상 테이블이 있어도 생성 마이그레이션 시험이 실패하지 않는다 — **1안으로 정한다**. 2안(`.drift` 파일 + `build.yaml` `sqlite_modules: [fts5]`)은 1안이 예상 밖으로 실패할 때만 쓴다.
- `schema_test` v2: 새로 만든 v2 DB와 v1에서 이주한 v2 DB의 `sqlite_master`(정렬·공백 정규화)가 같다.

### 6.12 마이그레이션 v1 → v2 (1차 6.15 확장)

#### 6.12.1 단계 (한 트랜잭션 — 1차 `runSchemaUpgrade`)

`kSchemaSteps = {1: upgradeV1ToV2}`. `dart run drift_dev make-migrations`가 만든 단계 도우미 **`lib/src/storage/db/note_database.steps.dart`**(v2.1 정정 — drift_dev 2.35.2가 데이터베이스 파일 옆에 `.steps.dart`로 만든다, `make_migrations.dart` 524–525 [확인])의 `stepByStep`을 이 단계 안에서 쓴다(1차 '계획과 다르게 한 점' T6 방식). 생성 시험은 1차 `build.yaml`의 `test_dir`대로 `test/storage/generated_migrations/note_db/`(`generated/schema_v1.dart`·`schema_v2.dart`·`migration_test.dart`) 아래다. 생성 머리말 `// ignore_for_file: type=lint,unused_import`가 있어 analyze를 통과할 것이고(`drift_dev-2.35.2/lib/src/utils/header.dart` 3 [확인]), T24 첫날 `flutter analyze --fatal-infos`로 확인한다.

0. (v2.1, 트랜잭션 **전** — 6.12.4) 업그레이드 직전 v1 사본을 만든다. `VACUUM INTO`는 트랜잭션 안에서 돌지 않으므로(SQLite: 'cannot VACUUM from within a transaction' [확인 — VM SQLite 3.54.1]) `onUpgrade`에서 `runSchemaUpgrade`의 `db.transaction` 앞에 둔다. drift는 마이그레이션 콜백을 트랜잭션으로 감싸지 않는다(`engines.dart` `_runMigrations` → `user.beforeOpen` [확인]).
1. 새 테이블 5개와 색인 만들기(`m.createTable`·`m.createIndex`).
2. `recordings.title`, `pages.ink_rev`·`ink_rev_at`·`bg_asset_id`·`bg_pdf_index` 열 더하기(`m.addColumn`) + `idx_recordings_note`·`idx_pages_bg`.
3. `search_fts` 가상 테이블(6.11 1안 — `customStatement`).
4. `pages`의 배경 파생 열 채우기: `UPDATE pages SET bg_asset_id = json_extract(background_json, '$.assetId'), bg_pdf_index = CASE json_extract(background_json, '$.type') WHEN 'pdf' THEN json_extract(background_json, '$.pdfPageIndex') END WHERE json_extract(background_json, '$.type') IN ('pdf', 'image')`(SQLite 내장 JSON — [확인] 같은 실험에서 `json_extract` 동작).
5. `folders.name_norm`·`notes.title_norm`을 `SearchText.normalize`로 다시 계산해 **달라진 행만** 갱신(Dart에서 읽고 비교). (v2.1, 검토 S-16) 쓰기 경로의 `normalizeForSearch` 위임도 같은 T24에서 바꾼다(6.10.1).
6. kv `search.normalizerVersion = '1'`, (v2.1) kv `db.v1Copy`(0단계가 만든 사본 정보 — 6.12.4).

- 엔티티 열·`version`·`field_versions`·outbox·kv의 기존 키는 건드리지 않는다(C-14). 4·5는 파생 열이다.
- 실패하면 트랜잭션 전체가 되돌아가고 `SchemaStepError` → 1차 6.18 분류 `migrationFailed`(앱 시작 오류 화면). DB는 v1 그대로라 1차 앱(되돌린 배포)이 다시 열 수 있다. 0단계 사본은 남는다(다음 시도가 새로 만든다).
- 옛 앱이 v2 DB를 열면 `NewerSchemaError` → `newerSchema`(1차 그대로 — 위험 9, INFRA 안내서).
- 1차 웹 DB(iPad)의 크기: 노트 수십·획 수만 개 규모에서 단계 4·5는 행 수에 비례하는 한 번의 질의다. 예산은 사본 포함 1초 이내(V7 고정 자료로 측정 — 6.19 PF-8).

#### 6.12.2 노트 형식 (`kNoteSchemaVersion` 1 유지 — D4)

- 객체가 든 노트도 `schemaVersion` 1이다(7.2.7). `NoteMigrator`(1차 T15)는 바꿀 단계가 없다. 내부 `NoteMigrationContext`에 `objectsOf(pageId)`·`putObject`를 더해 둔다(다음 형식 변경 대비 — '시험용으로 열어 둔' 내부 인터페이스, 계약 아님).

#### 6.12.3 V7 고정 자료 — 1차 코드로 만든 v1 DB

계약 V7: '1차 코드로 만든 v1 DB 고정 자료(노트 3개·페이지 20장·획 2,000개·PDF 에셋 1개·설정·outbox 미전송 기록)를 v2로 열기 — VM(파일 DB)과 Chrome(웹 워커) 둘 다 … (v2.1) 업그레이드 직전 v1 사본이 같은 저장소에 있고 그 정규 덤프 해시가 고정 자료 manifest와 같음'.

| 항목 | 방법 |
|---|---|
| 생성 시점 (v2.1, Q2 답 — C21-11) | **R2-B2 전**, 작업 B2-0(8.1). 1차 통합이 `main`에 들어간 커밋(총괄이 병합 뒤 해시를 알림 — 아직 태그 없음)을 임시 작업 트리(`/tmp/claude-0/core-v1-fixture/`)로 꺼내 생성기를 복사해 돌리고, 산출물을 B2-α 커밋에 함께 넣는다. 그 커밋에 CORE 2차 코드가 섞이지 않게 2차 작업 트리의 첫 작업으로 한다 |
| 생성기 | `tool/make_v1_fixture.dart`(VM). **v1.4 공개 API만** 쓴다 — `openNoteStore(NoteStoreConfig(nativeDatabasePath:, idGenerator: 고정, clock: 고정))`, `library.createFolder/createNote`, `dev_tools.dart` `seedSyntheticNote`(점 30개짜리 획), `assets.put`(작은 PDF), `SetPageBackground(PdfBackground)`, `settings.set`(synced·device 각 1개), `sync.applyRemote`로 녹음 1개(1차에는 로컬 생성 API가 없음 — 획 일부가 그 녹음을 가리킴), 노트 하나 휴지통. 동기화하지 않으므로 모든 쓰기가 outbox에 남는다. v1.4 API는 v2의 부분 집합이라 같은 파일이 두 판에서 컴파일된다 |
| 산출물 | `test/fixtures/db_v1/noteapp_v1.sqlite`(약 2 MB — INFRA `.gitattributes` `*.sqlite binary`), `pdf_asset.pdf`(에셋 바이트 — 1차 네이티브 블롭은 메모리라 DB에 없음), `fixture_source.json`(생성 커밋 해시·시각·생성기 sha256). `manifest.json`은 T25b가 2차 도구 `tool/v1_fixture_manifest.dart`로 고정 자료 파일에서 계산해 더한다: 테이블·열 목록(v1), 테이블별 행 수, **`fullDumpSha256`**(v1 모든 테이블·열의 정규 덤프 — 사본 대조용), **`entityDumpSha256`**(같은 덤프에서 파생 열 `folders.name_norm`·`notes.title_norm`을 뺀 것 — C-14 대조용), outbox·kv 덤프 SHA-256 |
| 정규 덤프 (CORE 내부 `storage/db/canonical_dump.dart`) | 머리 줄 `noteapp-v1-dump 1`, 테이블마다(이름 순, `sqlite_%` 제외) `#table <이름> <열1>,<열2>,…` 줄 다음 행마다 `SELECT quote(c1) || ',' || quote(c2) || … FROM t ORDER BY 1` 한 줄(UTF-8, `\n`). `quote()`가 SQLite 안에서 값을 SQL 리터럴로 만들므로(정수 `1762300000000`, 실수 왕복 정밀도 `0.30000000000000004`·`1.0`, 문자열 `'it''s 한글'`, BLOB `X'0102FF'`, NULL) VM·웹이 같은 바이트를 낸다 [확인 — VM SQLite 3.54.1, 웹은 같은 판 wasm이고 Chrome 시험이 확인]. 행 순서는 rowid가 아니라 행 문자열 순이다 — `VACUUM INTO`가 rowid를 바꿀 수 있기 때문이다(정수 기본 키가 없는 표). 질의 함수(`Future<List<String>> Function(String sql)`)만 받으므로 drift(`customSelect` — 웹·네이티브)와 `package:sqlite3`(도구·VM 시험)가 같은 구현을 쓴다 |
| VM 시험 | `test/migration/v1_fixture_migration_test.dart`: 임시 디렉터리에 복사 → `openNoteStore(파일 DB + 파일 블롭)`(T35) → v2 → ① v1 열 정규 덤프(파생 열 제외)의 SHA-256 = `entityDumpSha256`(C-14), 파생 열 = `SearchText.normalize(이름)` ② `field_versions`·outbox·kv 덤프 같음 ③ 새 테이블 비어 있음, `bg_asset_id` 채워짐 ④ (v2.1) **사본** `<path>-v1-backup`가 있고 그 파일의 정규 덤프 SHA-256 = `fullDumpSha256`, `user_version` 1, kv `db.v1Copy` 있음 ⑤ 이어서 객체 추가·녹음 생성·검색이 동작, 다시 열어도 같음(사본은 그대로, `normalOpens` 1 증가) |
| Chrome 시험 | `test/web/v1_fixture_migration_browser_test.dart`: 고정 자료 바이트를 받아(아래 '전달') drift `WasmDatabase.open(initializeDatabase: () => 고정 자료 바이트)`(drift 2.35.3 지원 [확인 — `drift-2.35.3/lib/wasm.dart` 161])로 새 웹 DB를 채운 뒤 `openNoteStore` → 같은 검사 ①~③⑤ + (v2.1) ④′ 블롭 저장소 `db/v1-backup/meta`가 있고 조각을 이어 붙인 바이트의 SHA-256 = `fullDumpSha256`(웹 사본은 정규 덤프 그 자체 — 6.12.4). PDF 바이트는 블롭 DB에 1차 키 형식으로 먼저 넣는다. `connect_browser.dart`에 시험용 `@visibleForTesting` 초기 바이트 인자를 더한다(내부). 사본이 있을 때와 지운 뒤의 다시 열기 시간을 진행 기록에 남긴다(6.12.4 '웹 비용') |
| 전달 (v2.1, 검토 S-5) | Chrome 시험은 `dart:io`로 `test/fixtures/`를 읽을 수 없다. `tool/prepare_web_test.dart`가 `test/fixtures/db_v1/`의 세 파일을 `test/web/fixtures_v1/`로 복사하고(1차 `sqlite3.wasm`과 같은 방식 — 패키지 `.gitignore`에 `test/web/fixtures_v1/` 추가, CORE 소유), 시험은 시험 페이지 기준 상대 URL(`fixtures_v1/noteapp_v1.sqlite`)을 `package:web` `fetch`로 받는다. 파일이 없으면 시험은 '준비 스크립트를 먼저 돌리라'는 메시지로 실패한다(건너뛰지 않음) |
| 생성 마이그레이션 시험 | `test/storage/generated_migrations/note_db/`(make-migrations 산출) — 스키마만 검사 |

- (v2.1, U25 기본값) 사용자의 1차 실제 노트는 **없는 것으로 본다** — Hosting이 없어 1차 웹이 배포된 적이 없다(00-review 4장). 그래서 V7은 고정 자료로만 확인한다. 고정 자료는 실제 DB와 같은 코드 경로로 만들어지지만 원격 적용 행이 거의 없다는 점이 다르다 — 위험 1.
- **실제 데이터의 이주는 그 데이터가 있는 출처에 2차가 배포될 때 처음 일어난다.** 미리보기 채널은 출처가 달라(1차 7.4.9 — 채널 id가 브랜치마다 다름) 실제 노트를 보지 못한다. 그래서 7.8 B-1 절차는 '배포 전 백업 내보내기 → 실제 노트가 있는 출처(live)에 배포 → 첫 실행 → 확인'이다(9.5, 위험 1).

#### 6.12.4 업그레이드 직전 v1 사본 (v2.1 — CORE-M3, CD2-23, 7.2.7 원문)

이주가 성공한 뒤 2차 코드의 버그로 데이터가 상해도 되돌릴 마지막 안전망이다(백업 **복원**은 이번 범위 밖 — 1.3). 사본을 만드는 것은 `from == 1`인 업그레이드에서만이다(새 DB·메모리 DB(`inMemory`·메모리 `openTestNoteStore`)는 만들지 않는다).

| 저장 방식 | 사본 | 이름 · 위치 | 지우기 |
|---|---|---|---|
| 네이티브 파일 DB(안드로이드·iOS, VM 파일 DB 시험) | `VACUUM INTO '<nativeDatabasePath>-v1-backup.tmp'` → 이름 바꾸기 `<nativeDatabasePath>-v1-backup`(있는 파일은 먼저 지움 — `VACUUM INTO`는 대상이 있으면 실패 [확인]). 결과는 그대로 열리는 v1 SQLite 파일(`user_version` 1, `journal_mode` delete [확인]) | DB 파일 옆(`*_native.dart`) | 파일 삭제 |
| 웹(drift 웹 워커) | **블롭 저장소의 정규 덤프**(6.12.3 형식): 표마다 2,000행씩 읽어 4 MiB 이하 조각으로 `db/v1-backup/<6자리>`에 쓰고, 다 쓴 뒤 **마지막에** `db/v1-backup/meta`(`{createdAt, bytes, chunkCount, sha256, format: 'noteapp-v1-dump 1'}`)를 쓴다 — meta가 있으면 사본이 완전하다. 행이 SQL 리터럴이라 `INSERT INTO t VALUES (<행>)`으로 v1 DB를 다시 만들 수 있다 | IndexedDB `noteapp_blobs`(에셋과 같은 저장소 — 같은 출처) | `deletePrefix('db/v1-backup/')` |

- **웹은 계약의 '안 되면 같은 저장소 안의 다른 사본 방법' 갈래다**(CP-16으로 문구 구체화 요청): 웹 VFS 안의 `VACUUM INTO` 사본은 계약이 함께 요구한 **수명(자동 삭제)을 채울 수 없다** — drift 웹 API에는 DB 전체 삭제(`WasmDatabase.deleteDatabase` — `wasm_setup.dart` 381–384 [확인])만 있고 파일 하나를 지울 길이 없으며, 클라이언트에는 VFS 파일을 지울 SQL도 없다. 게다가 sqlite3 3.8.0 `IndexedDbFileSystem`은 열 때 그 파일 시스템의 **모든 파일을 메모리로 읽는다**(`indexed_db.dart` `_readFiles` [확인]). drift는 DB 이름마다 파일 시스템 하나에 `/database`를 두므로(`drift-2.35.3/lib/src/web/wasm_setup/shared.dart` 359–387 [확인]) 같은 파일 시스템의 사본은 남아 있는 내내 **매 열기의 메모리·시간을 두 배**로 만든다(6.10.7과 같은 문제). 블롭 저장소는 열 때 읽지 않고 접두사째 지울 수 있다. 그래서 검토 M-3의 'T24 첫날 Chrome 확인'은 웹 VFS `VACUUM INTO` 대신 **블롭 정규 덤프 사본의 만들기·해시·지우기·다시 열기 시간**을 T24 첫날 Chrome에서 확인하는 것으로 바꾼다(13절).
- 이름: 계약의 `'<databaseName>-v1-backup'`을 저장 방식마다 'DB가 사는 곳의 이름 + `-v1-backup`'으로 읽는다 — 네이티브는 DB 파일 경로(`nativeDatabasePath`) 옆 파일, 웹은 그 저장소의 블롭 DB(`WebStorageConfig.blobDatabaseName` — 기본 `noteapp_blobs`, 1차) 안 `db/v1-backup/` 접두사.
- 순서: 0단계(사본) → 업그레이드 트랜잭션(6.12.1 1~6, kv `db.v1Copy = {"createdAt":…, "method":"vacuum"|"dump", "bytes":…, "normalOpens":0}`) → 커밋. 사본 만들기가 실패하면(용량·I/O) **이주는 그대로 진행**하고 kv에 `{"failed": "<분류>", "at": …}`를 남긴다 — 사본 실패로 앱이 열리지 않는 것보다 낫고, 1차 안전망(배포 전 백업 내보내기 — B-1)이 앞에 있다. 실패는 개발자 표시와 개발자 메뉴에 보인다.
- **수명**: 열기가 오류 없이 끝날 때마다(마이그레이션 직후 열기 포함) `normalOpens += 1`. `normalOpens ≥ 5` **이고** 사본을 만든 지 7일이 지난 첫 열기에서 자동으로 지우고 kv를 없앤다(둘 다 — 버그를 알아챌 시간과 열기 횟수). 개발자 메뉴에서 언제든 지울 수 있다. `deleteLocalNoteData`는 사본도 지운다(네이티브 파일 + 웹 블롭 DB). 백업 내보내기에는 넣지 않는다.
- **개발자 메뉴 API**(INFRA 'v1 DB 사본 내보내기·지우기' — X-6, CP-17로 계약 반영 요청, `dev_tools.dart`):

```dart
// package:note_core/dev_tools.dart — (v2.1) CORE 확정 세부, CP-17
@immutable
final class V1DatabaseCopyInfo {
  const V1DatabaseCopyInfo({required this.createdAt, required this.bytes,
      required this.normalOpens, required this.fileName, this.failure});
  final EpochMillis createdAt;
  final int bytes;
  final int normalOpens;
  /// 'noteapp-v1-backup.sqlite' (native, a SQLite file) | 'noteapp-v1-backup.sql.txt' (web, the canonical dump)
  final String fileName;
  /// Set when the copy could not be made ('quota' | 'io' | 'other'); bytes is 0 then.
  final String? failure;
}
/// null when there is no copy and no failure record (new DB, deleted, or a store without one — fakes).
Future<V1DatabaseCopyInfo?> v1DatabaseCopyInfo(NoteStore store);
/// The copy in ≤ 4 MiB chunks (INFRA writes a file / web download). StateError when there is none.
Stream<Uint8List> readV1DatabaseCopy(NoteStore store);
/// Deletes the copy and its kv record; no-op when none.
Future<void> deleteV1DatabaseCopy(NoteStore store);
```

- **웹 비용**: 사본 만들기는 한 번, v1 DB 전체를 한 번 읽는다(획 10만 개 ≈ 76 MB면 수 초 [추측] — 열기가 그만큼 늦는다. 1차 DB가 이 크기면 7.8 B-1의 '첫 실행'이 길다고 안내서에 적는다 — INFRA). 사본이 블롭 저장소에 있는 동안 저장 공간이 DB 크기만큼 더 들고, 열기 메모리는 늘지 않는다. Chrome 시험이 V7 고정 자료(2 MB)의 사본 시간·열기 시간을 남긴다.
- 시험: `test/storage/v1_copy_test.dart`(VM 파일 DB: 사본 생성·이름 바꾸기·이전 사본 덮기·실패 주입 → 이주 진행 + kv `failed`·수명 규칙(가짜 시계로 5번·7일)·`deleteLocalNoteData`·`readV1DatabaseCopy` 조각 크기·`deleteV1DatabaseCopy` 멱등·메모리 DB는 사본 없음), V7 VM·Chrome(6.12.3 ④·④′), `test/web/v1_copy_browser_test.dart`(웹 정규 덤프 meta 마지막 쓰기 — meta 전에 끊긴 사본은 다음 시도가 지우고 다시 만듦).

### 6.13 변경 기록 · 힌트 · 원격 적용 (1차 6.10 확장)

- **outbox·`EntityChange` 힌트**(C2-13): `WriteTxn._hints`(`storage/write_queue.dart` 514–532)에 두 경우를 더한다 — `PageObject(:pageId)` → `noteId = noteIdOfPage(pageId)`, `pageId`; `HandwritingText(:noteId, :pageId)` → 그대로. 둘 다 '항상'이다. 1차 outbox 시험의 '항상' 단언을 새 종류에 돌린다(`test/storage/outbox_v2_test.dart`).
- **원격 고아 객체**: 페이지 행보다 먼저 온 객체는 `note_id = ''`로 저장하고, 그 페이지가 오는 커밋에서 `_adoptOrphans`가 획과 함께 노트를 채운다 — 그 `EntityChange`는 페이지가 온 커밋의 batch에 나온다(1차 v1.2 고아 획 규칙의 확장). 손글씨 결과는 JSON에 `noteId`가 있어 고아가 생기지 않는다.
- **원격 적용**(`DriftSyncStore.applyRemote`): `EntityJson`으로 디코드 → 정책(SYNC) → `putRemote`. 객체·손글씨가 쓰인 기존 페이지는 1차처럼 작업 끝에 `content_rev + 1`(썸네일·`ink_rev` 무효화), 영향 노트 `refreshNoteDerived`. 쓰기 훅이 색인을 갱신한다(6.10.3). 열린 세션은 N-7(6.5).
- `pendingChanges`·`readVersioned`·`commitRepairs`·`reassignOwner`는 종류에 무관한 1차 코드에 switch 행만 더한다(`drift_sync_store.dart`의 `EntityKind` 21곳 — 조사 01 3.11 목록). 객체·손글씨에는 소유자 열이 없다(노트를 따름 — 1차 획과 같음).
- 기기 로컬 테이블(`recording_drafts`·`search_*`)과 페이지 캐시·파생 열은 outbox·`readVersioned`·백업에 나오지 않는다.

### 6.14 노트 복사 · 휴지통 · 백업 (1차 6.8 · 6.17 확장)

#### 6.14.1 `copyNote` (복사·`copyItems`·`duplicateNoteForRecovery` 공용 — `drift_library_repository.dart` 935)

한 트랜잭션에서 1차 순서(노트 → 페이지 → 획) 뒤에 이어서:

1. **녹음**(R-6): 원본 노트의 활성 녹음마다 새 id, 같은 `assetId`(해시라 바이트 중복 없음)·`title`·`durationMs`·`startedAt`, `createdAt = updatedAt = now`. 옛 id → 새 id 표를 만든다.
2. **획**: 복사된 획의 `recordingId`가 1의 표에 있으면 새 id로 바꾼다(없으면 — 삭제된 녹음 등 — 그대로, R-7 '연결 없음').
3. **객체**: 활성 객체마다 `copyTo(id: 새 id, pageId: 새 페이지, createdAt: 원래 값)`.
4. **손글씨 결과**: 복사된 페이지마다 원본에 활성 결과가 있으면 `HandwritingText(noteId: 새 노트, pageId: 새 페이지, engineId 같음, lines의 strokeIds를 새 획 id로 바꿈(복사되지 않은 id는 뺌), sourceRev = sourceRevOf(복사된 입력 획))` — 웹처럼 인식할 수 없는 기기에서도 복사본이 바로 검색된다.
5. 색인: 3·4의 쓰기 훅이 text·math·ink 단위를 만든다.

- 가짜 저장소도 같은 순서·같은 결과(공유 `library_contract` 확장 — `test/repo/note_copy_v2_test.dart`).

#### 6.14.2 영구 삭제 (휴지통 비우기·자동 정리·`RemotePurge`)

- 1차 `deleteNoteContents(tx, noteIds)`(페이지·획·녹음 + outbox)에 `page_objects`·`handwriting`(+ 그 outbox 항목), `search_owners`·`search_units`·FTS 행(그 노트의 것 — pdf 제외), `recording_drafts` 행을 더한다. 초안 조각·meta(`rd/<draftId>/`)는 커밋 뒤 `afterCommit`에서 지운다(1차 썸네일 `dropPurged`와 같은 방식). 그 노트의 단위에는 사각형 블롭이 없다(비pdf는 행 안 4열, pdf 소유자는 에셋 단위라 남음 — 6.10.3).
- `ChangeBatch`에는 1차처럼 폴더·노트 purge만 넣는다.

#### 6.14.3 페이지 복제와 손글씨 결과

- `DuplicatePages`(세션 명령)는 손글씨 결과를 복제하지 않는다 — 히스토리 밖 엔티티를 히스토리 안 명령이 만들면 undo가 그것을 지우지 못한다. 복제된 페이지는 네이티브에서 색인기가 다시 인식한다. 웹에서는 실연결 전까지 그 페이지의 손글씨 검색이 되지 않는다(1.3 이후 범위).

#### 6.14.4 백업 내보내기

- 종류 순서 = `EntityKind.values`(새 두 값이 끝 — `pageObject`, `handwriting`), 그다음 id 순(1차 T19). `formatVersion`은 **1 그대로**(문서 구조가 같고 종류만 늘었다 — 읽는 쪽은 모르는 `kind`를 건너뛴다), `schema.database`는 2.
- 색인·초안·페이지 캐시·파생 열·(v2.1) v1 사본(6.12.4)은 넣지 않는다(3.2).
- 골든: `test/goldens/backup/backup_v1.json`을 `backup_v2.json`으로 바꾼다(골든 상태에 객체 5종·손글씨 결과 1개·제목 있는 녹음을 더함). 실제·가짜·웹이 같은 바이트(1차 T19 공유 본문).

### 6.15 에셋 · 네이티브 저장 (1차 6.13 확장)

#### 6.15.1 `bytesByType`

`SELECT type, SUM(size) FROM assets WHERE deleted_at IS NULL AND has_local_bytes GROUP BY type` — 1차 `totalBytes`와 같은 행 집합이라 `Σ bytesByType == totalBytes`(시험). 가짜도 같다.

#### 6.15.2 이미지 에셋 형식

- 7.2.6 '이미지 에셋은 `storedMimeTypes`만 저장한다'는 media_io가 지킨다(M-3). (v2.1, CP-11 승인) CORE 로컬 `AssetStore.put(type: image)`도 `mimeType`이 `ImageImportLimits.storedMimeTypes` 밖이면 **쓰기 전에** `ArgumentError`다. 원격 `putDownloadedBytes`는 검사하지 않는다(동기화로 온 다른 형식도 잃지 않게 — PDF 내보내기는 그래도 다른 형식에 대비한다, 7.2.6 원문). 다른 영역의 기존 시험은 모두 `image/png`다(검토 때 `grep "AssetType.image"` [확인]). 시험: `test/assets/asset_store_test.dart`에 `image/gif` 로컬 → `ArgumentError`·행 없음, 원격 → 저장.

#### 6.15.3 네이티브 파일 블롭 (공통-1)

| 항목 | 규칙 |
|---|---|
| 열기 | 네이티브(`dart.library.ffi`)에서 `inMemory`가 아니면 `nativeDatabasePath`와 `nativeAssetDirectoryPath`가 **둘 다** 있어야 한다. 하나라도 없으면 `NoteStoreOpenException(storageUnavailable)`(7.2.6). 둘 다 있으면 파일 DB(1차 `createInBackground`, WAL) + 파일 블롭, `StorageInfo(backend: nativeFile)`(durable — 저장 경고 없음). (v2.1, C21-10) 블롭 루트 `<dir>`와 하위 `blobs/`·`thumbs/`가 없으면 **CORE가 만든다**(`Directory.create(recursive: true)` — INFRA는 경로만 넘긴다). 만들 수 없으면(권한·읽기 전용) `storageUnavailable`. DB 파일의 부모 디렉터리도 같다 |
| 배치 | `<dir>/blobs/<key>` — 키의 `/`가 하위 디렉터리(`<assetId>/000003`, `rd/<draftId>/000012`). 썸네일은 `<dir>/thumbs/<pageId>.bin`(머리 12바이트 = `contentRevision`·`width`·`height`(각 uint32 LE) + MIME 길이·MIME + 바이트) |
| 원자적 쓰기 | 같은 디렉터리의 `.<name>.tmp-<난수>`에 쓰고 `flush: true` 뒤 `rename` — 키 하나가 통째로 있거나 없다(1차 'IndexedDB 값 하나 = 원자적'과 같은 성질). 열 때 남은 `.tmp-` 파일을 지운다 |
| `keys(prefix)` | 접두사의 디렉터리를 나열해 정렬(1차 `BlobStore` 계약: 오름차순) |
| `deletePrefix` | 그 디렉터리를 재귀 삭제 |
| `deleteLocalNoteData` | DB 파일·`-wal`·`-shm`(1차) + (v2.1) v1 사본 `-v1-backup`(6.12.4) + `<dir>/blobs`·`<dir>/thumbs`를 지운다(루트 디렉터리 자체는 남김) |
| 오류 | 파일 쓰기 실패는 1차 '청크 쓰기 실패' 규칙(즉시 그 오류로 완료, 재시도 없음 — 1차 v1.2) |
| 파일 | `assets/file_blob_store_native.dart`(`dart:io`). `connect_native.dart`가 고른다. `testing_vm.dart`의 `openTestNoteStore`는 1차처럼 메모리 블롭(시그니처·동작 그대로) |

- 1차 CORE 시험 중 파일 DB 경로만 넘기던 것(`open_errors_test`·`asset_store_test`·`commit_latency_perf_test`)은 임시 블롭 디렉터리를 함께 넘기도록 고친다(CORE 내부).
- 경로는 INFRA가 `path_provider`의 앱 지원 디렉터리 아래로 정한다(7.2.6 문단). 백업 대상: (v2.1, D20 — C21-23) 안드로이드 자동 백업은 끈다(`android:allowBackup="false"` — INFRA 매니페스트), iOS는 기본값(앱 지원 디렉터리는 iCloud 백업에 들어감 — 실연결 미니 라운드에서 다시 본다). 보존 수단은 백업 내보내기 → 실연결 뒤 동기화다(U27, 부록 B).
- 시험(`test/storage/native_file_store_test.dart`)에 '없는 루트·하위 디렉터리를 만들고 연다', '읽기 전용 디렉터리 → `storageUnavailable`'을 더한다.
- 웹은 바뀌지 않는다(IndexedDB `noteapp_blobs` — 1차 T13·T16).

### 6.16 provider 세부 (1차 6.16)

- 4.10 표대로. 저장소에서 파생하는 4개는 `noteStoreProvider`를 `watch`한다(저장소가 바뀌면 함께 다시 만듦 — 1차와 같음).
- `noteRecordingsProvider`는 `autoDispose.family`, 저장소 스트림이라 `retry: noRetry`(1차 규칙). Riverpod 3.4.3은 리스너 없는 provider를 멈추므로 시험은 `container.listen` 뒤 읽는다(1차 진행 기록 메모).
- 오디오 provider는 `Provider`(앱 수명) — media_io 구현이 자기 `dispose`를 `ref.onDispose`로 건다(media 몫).

### 6.17 공용 가짜 저장소 v2 (1차 6.19 확장)

`createFakeNoteStore()`의 시그니처는 그대로이고 동작만 넓힌다(7.6 원문 주석).

| 기능 | 가짜의 동작 |
|---|---|
| 페이지 객체 | 세션 명령 전부(6.4 — 같은 `CommandResolver`·`SessionEngine`을 메모리 백엔드로 돌린다, 1차 T5와 같은 구조), `NoteContentReader.loadPage`의 `objects`, 노트 복사(6.14.1) |
| 녹음 | `RecordingRepository` 전부(6.6과 같은 검증·멱등 — 같은 id는 그 행), watch |
| 녹음 초안 | 메모리 맵(키 `rd/…`·`rd/<id>/meta` 구조까지 같게 — `listDrafts` 맞춤·meta 되살림·조각 0 초안·고아 정리 규칙 포함, 6.7.2) |
| 손글씨 | `HandwritingRepository` 전부 — (v2.1) `update`(같은 동기 섹션 안의 읽기-`transform`-쓰기라 끼어듦 없음)·`notesWithStalePages`(정확한 답, 같은 순서), `stalePages`는 메모리 획으로 직접 계산(페이지 순서) |
| 검색 | 메모리 색인 + 같은 id 규칙·FTS 후보 흉내·후보 2,000 최근 우선·공용 판정·랭킹(6.10.6) — 실제와 결과·순서·`pagesTruncated` 같음(CP-14) |
| 에셋 | `bytesByType` |
| SyncStore | 1차 그대로(`pendingChanges()` 빈 목록, 나머지 `UnsupportedError`) — 원격 경로가 없으므로 N-7·고아·원격 색인은 실제 저장소 시험만 |
| 백업 | 새 종류 포함(실제와 같은 바이트 — 6.14.4) |

- `FakeNoteStoreFaults`(1차)는 그대로. 색인 실패 주입(C-13)은 실제 저장소의 내부 시험 훅으로만 한다(다른 영역이 쓸 일이 없음).
- 공유 계약 본문(`test/shared/*_contract.dart`)을 가짜·실제 양쪽에 돌려 의미가 같음을 고정한다(1차 T8·T10·T12·T17 방식).

### 6.18 웹과 네이티브 차이

| 항목 | 웹(iPad Safari) | 네이티브(안드로이드 APK·iOS) | VM 시험 |
|---|---|---|---|
| DB | sqlite3.wasm + drift 웹 워커(1차) | 파일 DB(`createInBackground`, WAL) | `NativeDatabase` 메모리·파일 |
| 블롭(에셋·썸네일·초안·(v2.1) 검색 글자 상자·v1 사본) | IndexedDB(idb_shim) — 열 때 읽지 않음 | 파일 블롭(6.15.3, v1 사본은 DB 옆 파일) | 메모리 IDB(`openTestNoteStore`) 또는 임시 디렉터리 파일 블롭 |
| DB 열기 비용 | (v2.1) 파일 전체를 메모리로 읽음(`IndexedDbFileSystem` [확인]) — 색인 크기 목표(6.10.7)의 이유 | 필요한 페이지만 읽음 | — |
| v1 사본(6.12.4) | 블롭 저장소 정규 덤프 | `VACUUM INTO` 파일 | 파일 DB면 `VACUUM INTO`, 메모리 DB는 없음 |
| FTS5 | wasm(SQLite 3.54.1)에 포함 [확인] | sqlite3 빌드 훅 기본 바이너리 `SQLITE_ENABLE_FTS5` [확인 — `sqlite3-3.8.0/doc/hook.md`] (안드로이드·iOS 실행은 미확인 — 위험 7) | 리눅스 바이너리 [확인] |
| 손글씨 결과 쓰기 | 없음(ML Kit 불가 — G-1). 실연결 뒤 원격으로만 | recog 색인기 | 시험이 직접 |
| 녹음 초안 | 1초 조각 + meta(M-2, 6.7) — 주 사용처 | (v2.1 PDF 결정) 행만, 조각 0(12.2 Q4) | 시험이 직접 |
| 정규화·바이그램·판정·랭킹 | 같은 Dart 코드(코드 포인트 단위·고정 공백 목록) | 같음 | 같음 |
| SHA-256(`sourceRevOf`) | `package:crypto`(동기) | 같음 | 같음 |
| 수치 | 글자 상자 uint16·uint32 LE(`ByteData`), 점수는 IEEE 754 배정밀도(6.10.4), 64비트 정수 연산 없음(1차 7.4.3) | 같음 | 같음 |

#### 6.18.1 브라우저 시험 자산 (v2.1 — 검토 S-5, PDF Q2)

- `tool/prepare_web_test.dart`(1차 T16)에 두 가지를 더한다. ① `--out <dir>`(기본 = note_core의 `test/web`): 다른 패키지가 자기 `test/web`으로 `sqlite3.wasm`·`drift_worker.js`를 받는다 — `testing_web.dart`를 쓰는 패키지(PDF `media_io`·`pdf_io`)는 자기 `tool/prepare_web_test.dart`에서 `Isolate.resolvePackageUri(Uri.parse('package:note_core/note_core.dart'))`로 note_core 디렉터리를 찾아 `dart run <그곳>/../tool/prepare_web_test.dart --out test/web`을 부른다(몇 줄 — 예시는 `testing_web.dart` 문서 주석과 README). `ws test --platform chrome`이 멤버의 준비 스크립트를 먼저 돌리는 1차 규칙(INFRA `tool/src/test_command.dart` 41)이 그대로 적용된다. ② note_core 자신일 때만 V7 고정 자료 세 파일을 `test/web/fixtures_v1/`로 복사한다(6.12.3 '전달').
- 패키지 `.gitignore`(CORE 소유)에 `test/web/fixtures_v1/`를 더한다. 다른 패키지의 `test/web/sqlite3.wasm`·`drift_worker.js` 무시 줄은 그 패키지 소유다(INFRA R2-B1 `.gitignore` 보강 목록과 맞춤 — X-6).

### 6.19 성능 목표 (`test/perf/`, `perf` 태그 — 1차 T18 방식: 워밍업 뒤 중앙값, 다른 영역과 CPU 공유)

| # | 항목 | 예산(VM) | 시험 |
|---|---|---|---|
| PF-1 | 객체 2,000개 + 획 2,000개 페이지 `openPage` | ≤ 400 ms (1차 2,000획 300 ms 예산 + 객체) | `object_page_perf_test` |
| PF-2 | 객체 2,000개 페이지에서 `UpdateObjects` 1개 `execute` | 평균 ≤ 2 ms | 같은 파일 |
| PF-3 | 5,000쪽 합성 색인 질의(2·3글자·낱말 중간·접두사·AND) | (V10, v2.5 C25-01 — 12.1 CP-18 승인) 후보 100개 미만 중앙값 ≤ 5 ms, 그 밖(후보 상한 2,000까지) ≤ 50 ms. 후보 수(FTS5 MATCH 행, 상한 전)는 시험이 질의마다 센다 | `search_perf_test`(시험 하나 — 질의마다 센 후보 수로 예산을 고름, 두 칸 모두에 질의가 있는지도 봄) |
| PF-4 | 같은 색인 1글자 LIKE 질의 | (V10, v2.5 C25-01) 후보(LIKE 행) 100개 미만 중앙값 ≤ 15 ms, 그 밖 ≤ 50 ms. 이 자료의 음절은 가장 드문 것도 576개라 100개 미만 칸은 자료에 없는 음절(후보 0 — 5,000단위를 다 훑는 바닥값)로 잰다 | 같은 파일 |
| PF-5 | 5,000쪽 색인 만들기(pdf 단위 `replaceUnits`) | 기록(예산 없음) — 크기 판정은 PF-10 | 같은 파일 |
| PF-6 | `stalePages` 20쪽 × 1,000획, 첫 호출 / 바뀐 페이지 1개 | ≤ 150 ms / ≤ 10 ms | `stale_pages_perf_test` |
| PF-7 | 초안 `append`(8 KiB) | 중앙값 ≤ 10 ms (Chrome ≤ 30 ms 기록) | `draft_append_perf_test` |
| PF-8 | V7 고정 자료 v1 → v2 마이그레이션(v1 사본 포함 — 6.12.4) | ≤ 1 s | `migration_perf_test` |
| PF-9 | 1차 예산 전부(10만 획 `openSession`, 1획 커밋 등) | 1차 값 유지(회귀 없음) | 1차 `test/perf/*` |
| PF-10 | (v2.1, CORE-M1) **실제 모양 500쪽 PDF 색인**(쪽당 2,500자 + 글자 상자, 한국어·혼용·영어 각각 — 6.10.7 생성기, 시드 고정): `replaceUnits` 합계 시간, DB 증가 바이트, 블롭 바이트, 질의(결과 100쪽·사각형 포함) 중앙값 | DB 증가 ≤ 12 MB(목표 — 7.4.5), 질의 ≤ 50 ms(T33b 첫 측정 32~42 ms로 확정 — 같은 프로세스 저장소 `openTestNoteStore`에서 단언, 네이티브 저장소 `openNoteStore`의 같은 질의는 기록만: 후보 행이 drift 배경 isolate를 건너는 값이 더해짐. 계약 V10의 질의 예산은 5,000쪽 합성 색인 몫(PF-3·PF-4)이고 이 값은 CORE 예산이다 — (v2.5) C25-01의 '그 밖의 질의 ≤ 50 ms'와 같은 값, 이 질의의 후보는 500개라 그 칸에 해당), 나머지 기록 | `search_real_shape_perf_test` |
| PF-10w | (v2.1) 같은 자료 500쪽 색인 뒤 Chrome **저장소 다시 열기 시간** 증가 | ≤ +300 ms(7.4.5 목표) | `test/web/search_reopen_time_browser_test.dart`(`perf`) |
| PF-11 | (v2.1, 검토 S-10) 획 10만 개 라이브러리(5,000쪽)의 첫 따라잡기: `notesWithStalePages` + 각 노트 `stalePages` 합계 / 그 뒤 `notesWithStalePages` | ≤ 1.5 s / ≤ 30 ms [추측 — 6.9.3 실험 근거] | `stale_pages_perf_test` |

### 6.20 오류 분류 (새 API)

| 오류 | 언제 |
|---|---|
| `ArgumentError` | 명령 검증(6.4.1), `createRecording`의 id·에셋·제목·길이(새 id일 때만 — 같은 id는 그 행), 초안 조각 크기·음수 시간, `HandwritingRepository.put`·`update`의 노트 불일치·후보 수·`pageId` 불일치, `SearchIndexWriter`의 원천·키·크기·사각형 수·좌표·`pdfPageAspect`·`sourceRev`(6.10.3), (v2.1, CP-11) 로컬 `AssetStore.put(type: image)`의 형식, 템플릿 인자 범위 |
| `StateError` | 같은 `recordingId`의 두 번째 초안, 모르는·버린 초안에 `append`·`readAll`(다른 탭이 복구·정리한 경우 포함 — 7.2.4), 녹음기의 중복 `start`(가짜 포함), 가짜 녹음기에서 `pendingDrafts`가 뺀 초안의 `recoverDraft`(6.8.1), `update`의 `transform` 안에서 부른 저장소 쓰기(6.9.4), 없는 v1 사본의 `readV1DatabaseCopy` |
| `EntityNotFoundException`(1차) | 없는 노트의 녹음 생성, 없는·삭제된 녹음 이름·삭제, 없는 페이지의 손글씨 결과 |
| `PageNotOpenException`·`ReadOnlyNoteException`(1차) | 객체 명령의 대상 페이지 미로드·읽기 전용 노트(N-3·N-4) |
| `UnsupportedError` | `Unsupported*` 기본값의 `start`·`open`, (v2.1, CP-PDF-5) `FakeAudioRecorder.start`에서 `support != supported` |
| `FormatException` | 객체·손글씨 JSON의 구조 오류(6.2.6), `ElementFrame.fromJson` |
| `NoteStoreOpenException` | `storageUnavailable`(네이티브 경로 하나 없음), `migrationFailed`(v2 단계 실패), `newerSchema` |

- 새 예외 타입은 만들지 않는다(1차 `NoteCoreException`은 sealed — 하위 타입을 더하면 다른 패키지의 switch가 깨질 수 있다).


---

## 7. 외부 패키지

### 7.1 채택 — 1차 고정값 그대로 (7.5 고정표에 note_core 변화 없음)

| 패키지 | 버전 | 2차에서 새로 쓰는 곳 | 웹 |
|---|---|---|---|
| `drift` | 2.35.3 | 새 테이블 5개·마이그레이션 `stepByStep`·`customStatement`(FTS5) | ✔ (웹 워커 `drift_worker.js` 2.35.3 — 1차 7.4.9) |
| `sqlite3` | 3.8.0 | FTS5 `contentless_delete=1`, `json_extract`, (v2.1) `VACUUM INTO`(네이티브 v1 사본)·`quote()`(정규 덤프 — 실수 왕복 정밀도) — SQLite 3.54.1 [확인] | ✔ (`sqlite3.wasm` 같은 판) |
| `crypto` | 3.0.8 | `HandwritingText.sourceRevOf`(SHA-256) | ✔ (순수 Dart) |
| `idb_shim` | 2.11.2 | 녹음 초안 조각·meta, (v2.1) 검색 글자 상자·웹 v1 사본(웹 블롭 DB) | ✔ |
| `collection` | 1.19.1 | 객체·손글씨·검색 값 타입 `==` | ✔ |
| `riverpod` | 3.4.3 | provider 6개 | ✔ |
| `meta`, `clock`, `uuid`, `web` | 1.19.0, 1.1.3, 4.6.0, 1.1.2 | 1차 그대로(`clock`은 저장소 시각만 — 녹음 시계에 쓰지 않음, 7.4.8). `web`은 (v2.1) 브라우저 시험의 고정 자료 `fetch`(`testing_web.dart`·V7 Chrome)에도 | ✔ |
| dev: `drift_dev`, `build_runner`, `test`, `fake_async` | 2.35.2, 2.16.1, 1.31.1, 1.3.3 | `make-migrations`(v2 스키마 스냅숏·생성 시험), 가짜 녹음기 시험 | — |

- 라이선스·점수는 1차 7.1 표 그대로다(새 패키지 없음 — R9 `pinned_external` 변화 없음).

### 7.2 검토 후 넣지 않음

| 후보 | 이유 |
|---|---|
| `sqlite3 3.9.0` | 2026-11-05 게시 — 게시 14일 규칙(7.5) |
| `sqlite3_flutter_libs` | sqlite3 3.x는 빌드 훅으로 SQLite를 묶는다(기본 바이너리에 `SQLITE_ENABLE_FTS5` — `sqlite3-3.8.0/doc/hook.md` [확인]). 따로 넣으면 같은 라이브러리가 두 번 들어갈 수 있다 |
| FTS5 `trigram` 토크나이저 | 2글자 질의가 MATCH로 0건(조사 01 4.1·03 9.2). 바이그램이 모든 질의에서 LIKE와 같거나 낫다 |
| ICU 토크나이저 | 웹·네이티브 바이너리에 없다 [확인 — 조사 01 4.1] |
| `path_provider`(note_core 의존) | 경로는 앱 셸(INFRA)이 정해 `NoteStoreConfig`로 넘긴다(7.2.6). CORE는 순수 Dart를 유지한다 |
| 녹음 시계용 패키지 | 시계는 media_io 몫. CORE 가짜는 수동 시계 |

---

## 8. 작업 분해

완료 조건은 적힌 시험이 패키지 디렉터리에서 `flutter test`(브라우저는 `dart run tool/prepare_web_test.dart && flutter test --platform chrome test/web/<파일>`, 성능은 `--run-skipped -t perf`)로 통과하고 `flutter analyze --fatal-infos` 0건, `ws check` 위반 0인 것이다(1차 8장 규칙). 작업 번호는 1차 T0~T19에 이어 T20부터 쓴다.

### 8.1 기반 단계 R2-B2 (동시 개발 시작 전 `main`에 커밋 — 7.6)

(v2.1, CORE-M2 — 검토 M-2, CD2-05) R2-B2를 **세션 크기 조각**으로 나누고 계약 표면을 먼저 낸다. 1차 B2(T0~T5, 커밋 `7bb1c59`)보다 일이 많아 한 세션에 끝나지 않고, 계약 타입 커밋이 구현 뒤에 있으면 7개 영역의 임계 경로 맨 앞(4.4)이 늘어나기 때문이다.

```text
B2-0 (T25a)  V7 고정 자료 생성 — 1차 통합이 main에 들어간 커밋의 코드로 (R2-B2 '전')
   │
B2-α (T22)   계약 표면: 4.1~4.11의 공개 선언 전부 + api_surface_test v2      ──▶ 해시 알림 = '계약 타입 커밋'
   │                                                                              (SYNC R2-B7a 바탕, INFRA R2-B2i, 전 영역 코드 작성 시작)
B2-β         T20a JSON·골든 ──▶ 해시 알림(SYNC CP-S9 키 대조)
             → T20b 객체 기하·변형 → T21 값 타입·순수 함수·포트 → T23a 해석기·세션 → T23b 가짜 v2·가짜 오디오·픽스처·testing_web
   │
main 병합    B2 전체(α + β) + R2-B7a + R2-B2i 묶음(총괄 — 7.6.2 예외)
```

**B2 상태**(실제 저장소 — DB v2·FTS5·파일 블롭은 동시 개발 몫이라 B2 끝에도 이렇다. 1차 B2에서 실제 저장소 멤버가 작업 번호를 단 `UnimplementedError`였던 것과 같은 방식):

| 항목 | B2-α 끝 | B2 전체(β) 끝 | 구현 작업 |
|---|---|---|---|
| 객체 모델·JSON·`bounds`·템플릿·`transformed`, 값 타입·`SearchText`·`sourceRevOf`·오디오 포트 타입 | 선언만(본문 `UnimplementedError('CORE T20a/T20b/T21')`. 생성자·필드·`==`·enum·상수는 실제) | 동작(순수 Dart) | T20a·T20b·T21 |
| `Unsupported*` 기본값·provider 6개 | 동작(작은 본문이라 α에 넣음 — 다른 영역의 provider read가 바로 됨) | 동작 | T22 |
| 세션의 객체를 만들거나 고치는 명령(`AddObjects`·`UpdateObjects`·객체가 든 초안의 `InsertPages`) | 해석 **전에** `UnimplementedError('CORE T23a')` | 실제 저장소: `UnimplementedError('CORE T27: page objects need DB v2')`(메모리 상태 불변). 실제 저장소에는 객체가 없으므로 `RemoveElements`·`TransformElements`·`ClearPage(includeObjects: true)`는 획만 다루는 1차 동작 / 가짜: 동작 | T23a·T27 |
| `recordings`·`recordingDrafts`·`handwriting`·`search`(실제·가짜) | 읽기는 빈 결과(`watchRecordings` → `[]`, `getRecording`·`forPage` → null, `stalePages`·`notesWithStalePages`·`listDrafts`·`searchPages` → `[]`, `status` 기본값, `sourceRevs` → `{}`), 쓰기는 `UnimplementedError('CORE T3x')` | 실제: 같음 / 가짜: 동작 | T23b(가짜)·T30~T33b(실제) |
| `searchLibrary`의 `pages` | 빈 목록(폴더·노트는 1차 그대로) | 실제: 빈 목록 / 가짜: 동작 | T23b·T33b |
| `AssetStorageUsage.bytesByType`, 로컬 이미지 형식 검사(CP-11) | 필드만(빈 맵) | 동작(1차 테이블 질의) | T21 |
| `nativeAssetDirectoryPath` | 필드만 — 1차 동작(파일 DB + 메모리 블롭) 그대로 | 같음 | T35 |
| `kDatabaseSchemaVersion` | **1 그대로** | 1 그대로 | T24에서 2 |
| `PageObjectFixtures`·`FakeAudioRecorder`·`FakeAudioPlayback` | 선언만(`UnimplementedError('CORE T23b')`) | 동작 | T23b |
| `testing_web.dart` `openWebTestNoteStore`·`deleteWebTestNoteStore` | 선언만 | 동작(실제 웹 저장소 v1 DB — 새 테이블은 T24 뒤) | T23b |
| `dev_tools.dart` v1 사본 함수(CP-17) | 선언만(`v1DatabaseCopyInfo` → null, 나머지 `UnimplementedError('CORE T24')`) | 같음 | T24 |
| JSON 골든 | — | 새 9개 + `recording.json`(`title`) + 백업 골든(녹음 `title` 키) 갱신 | T20a·T21 |

| # | 작업 (조각) | 세션 추정 | 산출물 | 완료 조건 |
|---|---|---|---|---|
| T25a | **B2-0** V7 고정 자료 생성 | 0.1~0.2 | `tool/make_v1_fixture.dart`(v1.4 API만), `test/fixtures/db_v1/noteapp_v1.sqlite`·`pdf_asset.pdf`·`fixture_source.json`(6.12.3) | 총괄이 알린 '1차 통합이 `main`에 들어간 커밋'을 임시 작업 트리로 꺼내 생성기를 돌림, 산출물 sha256을 진행 기록에. 2차 코드가 섞이지 않음(생성기만 복사). B2-α 커밋에 함께 넣는다 |
| T22 | **B2-α** 계약 표면 | 약 0.5 | 4.1~4.11의 공개 선언 전부: enum·한도 상수·생성자·필드·`==`·`hashCode`, `EntityKind` 2값(+ `EntityJson` switch 갈래 — 본문 `UnimplementedError`), 명령 3종(`label`)·`ClearPage.includeObjects`·`PageDraft.objects`·`PageContent` 객체 멤버, 새 인터페이스 4개·`NoteStore` getter 4개(위 B2 상태), `LibrarySearchResult.pages`, provider 6개, `Unsupported*`, 진입점 export(`testing.dart` 추가 이름, **`testing_web.dart`**, `dev_tools.dart` CP-17), `SearchTextMapping` | `test/api_surface_test.dart` v2(4.11 이름 전부 + 없어야 할 이름), `test/web/testing_web_browser_test.dart`(컴파일·이름 참조만 — 동작은 T23b), `test/providers/providers_fake_test.dart`(새 provider 이름 = `name:`, 오디오 기본값 `Unsupported*`·6.8.2 표), `test/testing/open_test_store_test.dart`(B2 상태 표 'α 끝' 열: 읽기 빈 결과, 쓰기·객체 명령 `UnimplementedError` 메시지에 작업 번호, 메모리 상태 불변), **1차 CORE 시험 전부**(VM 619·Chrome 47 — 통합 HEAD 기준), `ws check` R14 0, analyze 0. **커밋 해시를 진행 기록 '이정표 커밋' 표(8.5)·SYNC·INFRA·총괄에 알린다** |
| T20a | B2-β ① **JSON·골든**(맨 앞 — SYNC 키 대조가 기다림) | 약 0.3 | 객체 5종·스타일·기하·`ElementFrame`·`HandwritingLine/Text`·`Recording.title`의 `toJson`/`fromJson`(비정규화 — 6.2.6, `engine`·`title` 키 항상 — 6.3), `EntityJson` 디코드 | `test/model/object_json_test.dart`(6.2.6 표 전부, C-12 키 보존, 모르는 enum → `UnknownObject`, `referencedAssets`), `test/common/element_frame_test.dart`의 JSON 부분(오류 8종·웹 정수 입력·**경계값 왕복** `−π`·`3π`·변 0 — 6.2.1), `test/model/recording_title_test.dart`(`title` 키 항상·없는 키 → null), `test/model/handwriting_text_test.dart`의 JSON 부분(id 결정·`fromJson` id 불일치 `FormatException`), `test/goldens/json_golden_test.dart`(새 골든 9개 + `recording.json`), `test/shared/object_json_web_cases.dart` → VM + `test/web/object_json_browser_test.dart`. **커밋 해시를 알린다**('B2-β JSON 골든' 이정표 — SYNC CP-S9) |
| T20b | B2-β ② 객체 기하·변형 | 약 0.3 | `ElementFrame` 기하·`normalized`, 템플릿 6종, `bounds` 공식, `PageObject.transformed(m, {scaleWidth})` 단일 규칙(6.2.5), `copyTo`·`copyWithMeta`, `estimatedBytes`, 스타일 정규화(6.2.3), `Stroke.transformed` 캘리그래피 각(C2-38 — 6.2.7) | `test/common/element_frame_test.dart`(꼭짓점·`bounds`·회전 부호가 `Affine2.rotation`과 같음·닮음 변환 정확·비균등 근사·`norm`·`contains`), `test/model/shape_geometry_test.dart`(템플릿 꼭짓점 값·시계 방향·인자 범위 `ArgumentError`, `transformed`), `test/model/page_object_test.dart`(종류별 `bounds` — 화살표 머리·굵기, `transformed` 표 전부·자름 경계·`scaleWidth: false`, 정규화 표, `==`, `estimatedBytes`), `test/edit/calligraphy_transform_test.dart`의 순수 부분(6.2.7 사례 — undo 부분은 T23a) |
| T21 | B2-β ③ 녹음·손글씨·검색·이미지 값 타입 + 순수 함수 + 포트 | 약 0.5 | `handwriting.dart`(`sourceRevOf`·`isRecognitionInput`·`copyWith`), `search/search_text.dart`(`normalize`·`normalizeMapped`·`indexTerms`·`matchQuery`·내부 `searchMatches`·`ftsCandidateMatches`)·`search_types.dart`·`search_ranking.dart`·`search_rects.dart`(형식 코덱 — 6.10.3), `assets/image_import.dart`, `AssetStorageUsage.bytesByType`(실제·가짜 질의)·로컬 이미지 형식 검사(CP-11), `NoteStoreConfig.nativeAssetDirectoryPath`, `media/audio_ports.dart`(`isActive`·`copyWith`) | `test/model/handwriting_text_test.dart`(`sourceRevOf` 고정 벡터·빈 집합 `e3b0c44298fc1c14`, `isRecognitionInput` 10종, `copyWith`), `test/shared/search_text_cases.dart` → `test/search/search_text_test.dart` + `test/web/search_text_browser_test.dart`(6.10.1 벡터, `normalizeMapped(x).text == normalize(x)`, VM = Chrome), `test/search/search_query_test.dart`(`indexTerms`·`matchQuery`·`searchMatches` — 6.10.2 표, FTS 문법 문자 주입, 점수 비트 결정성), `test/search/search_rects_codec_test.dart`(왕복·1/65535 반올림·`PageRect.zero`·줄 묶음·웹 = VM 바이트), `test/media/audio_ports_test.dart`(`isActive`·`==`·`copyWith`), `test/assets/storage_usage_test.dart`(`Σ bytesByType == totalBytes`, 가짜·실제), `test/model/image_import_test.dart`, `asset_store_test`의 CP-11 사례 |
| T23a | B2-β ④ 해석기·세션(메모리) | 약 0.4 | `CommandResolver`(6.4 — 새 명령·`ClearPage.includeObjects`·`PageDraft.objects`·`TransformElements`가 `transformed` 하나를 부름), `SessionEngine` 객체 상태, 메모리 백엔드 | `test/edit/object_commands_test.dart`(6.4.1 표 전부: 검증 오류 뒤 상태 불변, delta·바뀐 필드, 획 + 객체 변형 한 단계, `includeObjects`, `RemoveElements` 반복 id, 초안·복제의 객체 복사·`createdAt` 보존, 복합 명령 중간 실패 = 전체 불변, 2,000개 한도), `test/edit/calligraphy_transform_test.dart`(`TransformElements` → undo → 옛 extras·`style` 필드 버전), `test/shared/object_session_contract.dart` → `test/session/object_session_contract_fake_test.dart`(N-1~N-6에 객체, `PageContentChange` id), 1차 시험 전부 |
| T23b | B2-β ⑤ 공용 가짜 v2·가짜 오디오·픽스처·`testing_web.dart` | 약 0.5 | `fake/` v2(녹음·초안(meta 규칙 포함)·손글씨(`update`·`notesWithStalePages`)·메모리 색인(같은 id·후보 순서 — 6.10.6)), `PageObjectFixtures`, `FakeAudioRecorder`(v2.1 — 6.8.3), `FakeAudioPlayback`(`calls`), `testing_web.dart`(6.18.1·4.9), `tool/prepare_web_test.dart --out` | `test/shared/{recording,recording_draft,handwriting,search}_contract.dart` → 각 `test/{repo,media,search}/*_contract_fake_test.dart`(경합 사례 1·2·4~7 — 6.9.4, 빈 단위 소유자 유지, 후보 2,000 최근 우선), `test/testing/fake_store_v2_test.dart`(1차 `fake_store_test` + 객체 노트 복사·백업 새 종류), `test/testing/fake_audio_recorder_test.dart`(6.8.3 표: 상태 순서·`offsetNowMs` 일시정지 제외·빈 조각·`interrupt`·M-1 순서(`ChangeBatch` 순서로 확인)·저장 실패 → 초안 남음·`stopDurationErrorMs`·0 ms → null·`cancel` 행 없음·`start` `UnsupportedError`·`abandon` → 10초 전 `pendingDrafts` 0개 → 10초 뒤 새 녹음기의 `pendingDrafts` 1개 → `recoverDraft` 같은 `recordingId`, 진행 중 초안 제외, `fake_async` 안팎, 실제 메모리 CORE + `testWidgets` + `runAsync` 사례), `test/testing/fake_audio_playback_test.dart`(`calls` 순서·형식), `test/testing/page_object_fixtures_test.dart`(기본값 = 7.6 원문, JSON 왕복), `test/web/testing_web_browser_test.dart`(열기 → 쓰기 → 닫기 → 같은 이름 다시 열기 → 남음 → `deleteWebTestNoteStore` → 빈 저장소), 1차 시험 전부 |

- 순서: T25a → T22(B2-α) → T20a → T20b → T21 → T23a → T23b. α 뒤에는 T20a·T20b·T21이 서로 기대지 않아 순서를 바꿀 수 있지만, T20a를 맨 앞에 둔다(SYNC가 기다림).
- **이정표 알림**(CORE-M13): T22(B2-α)와 T20a 커밋 해시는 진행 기록 '이정표 커밋' 표(8.5)에 적고 SYNC·INFRA·총괄에 알린다. **SYNC R2-B7a의 바탕은 B2-α 해시**다(SYNC 검토 X-4 — R2-B7a의 switch 패치는 `EntityKind` 값만 필요). INFRA R2-B2i(위임 4줄)도 B2-α 위에서 만든다. SYNC의 새 종류 디코드·키 대조 시험(CP-S9)은 T20a 해시 뒤.
- R2-B2 완료 조건 = 위 조각의 시험 전부 + `api_surface_test` v2 + 1차 CORE 시험 전부(VM·Chrome) + **묶음 검사**(R2-B2 + R2-B7a + R2-B2i를 총괄이 함께 병합한 뒤 `ws check`·`ws test`·analyze — 7.6.2 예외). `main` 병합은 계약대로 B2 전체(α + β) 뒤다 — α만 따로 병합하지 않는다(다른 영역의 시험이 기대는 가짜 동작이 β에 있다).
- B2 착수 전 총괄 결정이 필요했던 것: CP-1(명령 생성자 모양) — v2.1에서 승인됐다(이름 있는 인자·`List`). 남은 선행 조건은 '1차 통합이 `main`에 들어간 커밋 해시'(총괄 알림 — T25a).

### 8.2 동시 개발

| # | 작업 | 선행 | 등급 | 완료 조건 (시험 파일) |
|---|---|---|---|---|
| T24 | DB 스키마 v2: `tables.dart`, `NoteDatabase` v2(`onCreate`에 FTS — 6.11 1안), `drift_schemas/drift_schema_v2.json`, (v2.1 정정) `note_database.steps.dart`, 생성 마이그레이션 시험(`test/storage/generated_migrations/note_db/`), `upgradeV1ToV2`(6.12.1 단계 0~6), (v2.1) **업그레이드 직전 v1 사본**(6.12.4 — 네이티브 `VACUUM INTO`, 웹 블롭 정규 덤프, 수명, `dev_tools.dart` CP-17 함수), 정규 덤프(`canonical_dump.dart`), (v2.1, 검토 S-16) **`normalizeForSearch` → `SearchText.normalize` 위임**, `kDatabaseSchemaVersion = 2` | B2 | P-A | `test/storage/schema_v2_test.dart`(새 v2 = 이주한 v2의 `sqlite_master`, 일반 테이블 15 + FTS 가상 테이블과 그 그림자 테이블, 색인 전부, `field_versions` 열 10개, `search_units`에 `rects` BLOB 열 없음), `test/storage/generated_migrations/note_db/*`, `test/storage/migration_v2_test.dart`(생성 `schema_v1`로 만든 합성 v1 → v2: 0~6 단계 결과, 단계 실패 주입 → v1 그대로 + `migrationFailed` + 사본은 남음, `bg_*` 열, 바뀐 `name_norm`만 갱신, 엔티티·버전·outbox 불변), `test/storage/v1_copy_test.dart`(6.12.4), `test/storage/canonical_dump_test.dart`(`quote()` 형식·행 문자열 순·VM = Chrome 바이트 — `test/web/canonical_dump_browser_test.dart`), `test/web/v1_copy_browser_test.dart`, `test/common/text_normalize_test.dart`(1차 벡터 + 단계 1·2·5 벡터 — 쓰기 경로 위임), 1차 `open_errors_test`(`user_version` 99 → `newerSchema`). **첫날**: `flutter analyze --fatal-infos`로 `*.steps.dart` 확인, FTS 1안 `SchemaVerifier` 통과 확인, (검토 M-3 — 6.12.4) Chrome에서 웹 사본(블롭 정규 덤프)의 만들기·해시·지우기와 사본 있음·없음의 다시 열기 시간 확인 — 진행 기록에 |
| T25b | V7 시험: `tool/v1_fixture_manifest.dart`로 `manifest.json`(행 수·`fullDumpSha256`·`entityDumpSha256`·outbox·kv 해시 — 6.12.3), 웹 초기 바이트 시험 훅, `prepare_web_test.dart`의 고정 자료 복사(`test/web/fixtures_v1/` — 6.18.1) | T24, (v2.1, 검토 S-5) **T35**(VM 시험이 파일 DB + 파일 블롭으로 연다), T25a | P-A | `test/migration/v1_fixture_migration_test.dart`(VM 파일 DB: 6.12.3 ①~⑤ — `entityDumpSha256`(C-14), 파생 열, 새 테이블 빈, `bg_asset_id`, **사본 `fullDumpSha256`**, 이어서 객체·녹음·검색 동작, 다시 열어도 같음), `test/web/v1_fixture_migration_browser_test.dart`(Chrome 웹 워커: 같은 검사 + 블롭 사본 해시 ④′, 사본 있음·없음의 다시 열기 시간 기록), `test/perf/migration_perf_test.dart`(PF-8 — 사본 포함) |
| T26 | 행 변환·쓰기 경로: `row_mappers`(page_objects·handwriting·`recordings.title`·`pages` 파생/캐시 열), `WriteTxn._hints` 새 두 종류, 원격 고아 객체 입양, `readVersioned` 행 | T24 | P-A | `test/storage/row_mappers_v2_test.dart`(종류마다 행 ↔ 엔티티 왕복, `UnknownObject` 키 보존 C-12, `data_json`에 메타 키 없음, 페이지 쓰기마다 `bg_*` 채움), `test/storage/outbox_v2_test.dart`(새 두 종류 `noteId`·`pageId` 항상 — 로컬·원격, 녹음 `{title}`), `test/storage/change_bus_v2_test.dart`(원격 고아 객체 → 페이지 도착 커밋 batch에 `noteId`와 함께) |
| T27 | 세션·내용 읽기(DB): `loadContent`, `DriftSessions` 객체·N-7, `DriftContentReader` 객체, 실제 저장소 객체 명령 열기(B2 `UnimplementedError` 제거) | T26 | P-A | `test/session/object_session_contract_real_test.dart`(T23a 공유 본문 + N-7), `test/session/note_session_objects_test.dart`(다른 페이지 객체를 읽지 않음, K-4 객체 동일성, 원격 객체 변경 → `PageContentChange(remote)`·히스토리 불변, `contentRevision`), `test/edit/undo_objects_test.dart`(`text`만 바꾼 `UpdateObjects` undo → `text`만 새 버전(C-11), 획 + 객체 변형 한 커밋·한 단계, 객체 100단계 undo 뒤 초기 상태, 원격이 바꾼 객체 undo 건너뜀), `test/session/content_reader_test.dart`(+ objects) |
| T28 | 동기화 창구 v2: `DriftSyncStore`의 종류 switch, 원격 객체·손글씨의 `content_rev`·색인 훅 | T26 | P-A | `test/sync/sync_store_v2_test.dart`(`pendingChanges`·`readVersioned`·`applyRemote`·`commitRepairs`를 새 종류로, 원격 객체가 쓰인 페이지 `content_rev + 1`), `test/sync/field_lww_convergence_v2_test.dart`(`fieldLwwPolicy` 두 저장소: 객체 동시 편집 → 객체 단위 LWW 수렴, 삭제 대 수정, 녹음 `title`, 손글씨 결과), `test/sync/unknown_object_roundtrip_test.dart`(`applyRemote` → `readVersioned` → `exportBackupJson`에서 키 집합·값 같음 — C-12) |
| T29 | 복사·휴지통·백업: `copyNote` 1~5단계(6.14.1), `deleteNoteContents` 확장(초안 meta 포함), `RemotePurge`, 백업 새 종류·골든 v2(v1 사본·색인 제외) | T27, T30, T32, T33a | P-A | `test/repo/note_copy_v2_test.dart`(공유 `library_contract` 확장 — 가짜·실제: 객체 새 id·같은 에셋·`createdAt` 보존, 녹음 새 id·획 `recordingId` 바뀜(R-6), 삭제된 녹음은 복사 안 함, 손글씨 결과 `strokeIds` 재매핑·복사본 `stalePages` 빈 목록, `duplicateNoteForRecovery` 같음), `test/repo/trash_purge_v2_test.dart`(영구 삭제가 객체·손글씨·색인·초안까지, outbox 정리, pdf 단위는 남음), `test/backup/backup_export_test.dart`·`test/testing/fake_backup_export_test.dart`·`test/web/backup_export_browser_test.dart`(골든 `backup_v2.json` 같은 바이트) |
| T30 | 녹음 저장소(DB) | T26 | P-A | `test/repo/recording_contract_real_test.dart`(T23b 공유 본문), `test/repo/recording_repository_test.dart`(6.6 표 전부: 검증·**같은 id는 인자와 상관없이 그 행**(v2.1 멱등)·삭제된 행도 그대로, watch 순서·같은 값 안 냄, `audioBytesOf` 서로 다른 에셋, 삭제 뒤 획 그대로(R-7), outbox `{title}`·`{deletedAt}`, 휴지통 노트 허용·영구 삭제 노트 `EntityNotFoundException`) |
| T31 | 녹음 초안 저장소(DB + 블롭) — (v2.1) meta 먼저·meta로 되살림·고아 정리 규칙·빈 조각·조각 0 초안(6.7) | T24 (네이티브 파일은 T35) | P-A | `test/media/recording_draft_contract_real_test.dart`(T23b 공유 본문), `test/media/recording_draft_store_test.dart`(동시 `append` 순서, Future가 커밋 재시도 중 미완료(`failNextCommits`), ①·② 사이 끊김 → `listDrafts` 맞춤, **행 유실 → meta로 되살림**, **행도 meta도 없는 접두사만 정리**, 빈 조각 `activeMs`·`updatedAt`, 조각 0 초안 유지, `discard` 순서·멱등, 4 MiB 초과·음수 `ArgumentError`, 같은 `recordingId` 두 번째 `StateError`, 버린 초안 `append` `StateError`), `test/web/recording_draft_browser_test.dart`(실제 웹 저장소: 120조각 → 닫기 → 같은 이름으로 다시 열기 → `listDrafts`·`readAll` 같음, 행 지운 뒤 meta 되살림, 30분 분량 `readAll` → `put` 시간·메모리 기록 — V16의 CORE 부분), `test/perf/draft_append_perf_test.dart`(PF-7). **이정표**: '실제 초안 저장소 사용 가능'(PDF `media` Chrome 시험 — X-1) |
| T32 | 손글씨 저장소(DB) + `pages.ink_rev` 캐시 — (v2.1) `update`(한 쓰기 트랜잭션)·`notesWithStalePages`·페이지 순서 | T26 | P-A | `test/repo/handwriting_contract_real_test.dart`(T23b 공유 본문 — **경합 사례 1~7**, 6.9.4), `test/repo/handwriting_repository_test.dart`(`put` 검증, `forPage`·`watchPage`·`removeForPage`, `stalePages` 경우 전부 — 결과 없음 + 입력 있음, 획 추가·수정·삭제, 형광펜·테이프만, 빈 페이지, 삭제된 페이지 제외, 원격 획 변경 뒤, undo 뒤, `put` 뒤 빈 목록, 페이지 순서, 캐시 쓰기에 outbox 없음; `notesWithStalePages` — 정확한 답·최근 노트 먼저·휴지통 제외·캐시 갱신 뒤 빈 목록; `update` — `transform` 안 쓰기 `StateError`), `test/perf/stale_pages_perf_test.dart`(PF-6·**PF-11** — 덮개 색인 없이, 넘으면 6.9.3 재검토) |
| T33a | 검색 색인 ① 쓰기 쪽: 테이블·쓰기 훅(text·math·ink)·`SearchIndexWriter`(검증·**빈 목록 = 소유자 유지**·`sourceRev` 문자열·글자 상자 블롭 쓰기 순서·고아 블롭 정리)·`rebuild`(`rebuilding` 신호)·`status`·보류 재시도 | T26, T32 | P-A | `test/search/search_index_writer_test.dart`(텍스트 상자 편집·삭제·undo 반영, `sourceRevOf`·`sourceRevs`(꼬리 `:x2` 그대로), **`replaceUnits(…, [])` 뒤 `sourceRevOf` = 그 값**, 작성기 검증 전부(사각형 수·좌표·`pdfPageAspect`·`sourceRev`), 블롭 쓰기 → 행 커밋 → 옛 블롭 삭제 순서, 커밋 실패 → 새 블롭 지움, 고아 블롭 정리, `rebuild` 멱등·`rebuilding` true → false, 정규화 판 바뀜 → 재구축, 색인 실패 주입: 원천 커밋·`pending`·다음 쓰기 트랜잭션·저장소 열기 재시도·타이머 없음·`pendingOwners`(C-13)), `test/web/search_fts_browser_test.dart`의 쓰기 부분(wasm `contentless_delete`·DELETE·재삽입). **이정표**: PDF 색인기가 실제 CORE에 쓸 수 있음 |
| T33b | 검색 색인 ② 질의 쪽: 후보(최근 단위 먼저 2,000·살아 있음 먼저)·판정·펼침·점수·발췌·**대표 결과만** 원문·사각형 읽기·`PageRect.zero` 건너뜀·`pdfPageAspect` 변환·`searchLibrary.pages` | T33a | P-A | `test/search/search_contract_real_test.dart`(T23b 공유 본문 — 가짜와 같은 결과·순서·`pagesTruncated`, 후보 상한 넘는 자료 포함), `test/search/search_index_test.dart`(휴지통·삭제 페이지 제외와 복원, `withinNote`, 소유자 필터, pdf 공유 에셋 → 노트 둘에 펼침, 글자 상자 줄 묶음 합치기·`PageRect.zero` 건너뜀·빈 상자, 비율 → pt(`pdfPageAspect` 있음·없음), 후보 질의가 `body`·`rects_ref`를 읽지 않음(SQL 기록 훅), 후보 2,000 최근 우선 + `EXPLAIN QUERY PLAN`에 정렬 단계 없음), `test/search/fts_candidate_equivalence_test.dart`(6.10.6), `test/web/search_fts_browser_test.dart`(MATCH·V10 질의 표가 VM과 같은 결과·흉내 동치), `test/perf/search_perf_test.dart`(PF-3~5), `test/perf/search_real_shape_perf_test.dart`(**PF-10**), `test/web/search_reopen_time_browser_test.dart`(**PF-10w**, `perf`). **이정표**: T33(계약 7.6.2의 '검색 색인') |
| T34 | `searchLibrary` v2: 제목 검색 회귀·`pages`·`pagesTruncated`(정규화 위임 자체는 T24) | T33b | P-A | `test/repo/library_search_v2_test.dart`(제목 결과가 1차 시험 그대로, `pages`·`pagesTruncated`, 가짜·실제 같음), 1차 `library_contract` 가짜·실제 |
| T35 | 네이티브 파일 블롭·파일 DB(6.15.3) — (v2.1) 루트·하위 디렉터리를 CORE가 만듦, `deleteLocalNoteData`에 v1 사본 | B2 | P-A | `test/assets/file_blob_store_test.dart`(임시 디렉터리: 원자적 쓰기·`keys` 정렬·`deletePrefix`·남은 임시 파일 정리·9 MiB 에셋 3청크 왕복·썸네일 파일 왕복), `test/storage/native_file_store_test.dart`(두 경로 → `nativeFile`·경고 없음, **없는 루트를 만들고 연다**, 읽기 전용 → `storageUnavailable`, 다시 열면 에셋·썸네일·초안 남음, 하나만 → `storageUnavailable`, `deleteLocalNoteData`가 블롭·사본까지, 열린 동안 `StateError`), 1차 `open_errors_test`·`asset_store_test`·`commit_latency_perf_test` 갱신 통과 |
| T36 | provider v2(실제 저장소) | T30~T33b | P-A | `test/shared/providers_contract.dart` v2 → `test/providers/providers_fake_test.dart`·`providers_real_test.dart`(새 provider: `noteRecordingsProvider` 갱신·dispose, `handwritingRepositoryProvider`·`searchIndexProvider` 값, 오디오 기본값) |
| T37 | 성능·문서: 6.19 예산 전부(PF-1~PF-11), 색인 크기 기록(PF-10 — README·INFRA 웹 예산표), README 2차 사용 예 | 전부 | P-A(예산)·P-C(README 확장 예제) | `flutter test --run-skipped -t perf`(PF-1~PF-11), Chrome `perf`(PF-10w·1차 `open_time_browser_test`), `test/readme_examples_test.dart` v2(객체 넣기·녹음 만들기·초안·PDF 색인 작성기·검색·네이티브 설정·`update`를 가짜·실제로 실행) |

- 병렬화: T24 → T26 → (T27, T28, T30, T31, T32) → T33a → T33b → T34 → T29 → T36 → T37. T35는 B2 뒤 언제든(T25b·T31 네이티브 시험 전), T25b는 T24·T35 뒤.
- **이정표 커밋 알림**(v2.1, CORE-M13 — 7.6.2 원문 목록): B2-α(T22), B2-β JSON 골든(T20a), T24(DB v2·마이그레이션 — SYNC·PDF·LIBRARY의 `integration` 시험이 v2를 연다), T26(쓰기 경로 — SYNC 시나리오 시험 가능), T27(객체 읽기·쓰기 DB — EDITOR E-2x, PDF 내보내기 `integration`), T28(동기화 창구 v2 — SYNC T16-v2), T29(복사·휴지통·백업), T30(녹음 저장소), T31(실제 초안 저장소 — PDF `media`), T32(손글씨 저장소 — LIBRARY L2x), T33a(PDF 색인기 쓰기), T33b(= 7.6.2의 T33, 검색 색인 — LIBRARY 결과 화면). 커밋마다 진행 기록의 '이정표 커밋' 표(8.5 양식)에 한 줄을 더하고, 기다리는 영역 이름을 적는다. 기다리는 쪽은 이 표로 시점을 판단한다.
- 일정이 밀리면 자를 것: 3.4 등급상 CORE 몫은 거의 P-A다. P-C만 먼저 뺀다 — README 확장 예제, CP-9(합성 노트 객체), 색인 크기 측정 자동화(수동 측정으로 대체). v1 사본(6.12.4)·초안 meta(6.7)·사각형 블롭(6.10.3)은 데이터 안전·웹 메모리 규칙이라 자르지 않는다.

### 8.3 통합 단계 몫 (7.7)

| # | 7.7.1 단계 | CORE가 하는 일 |
|---|---|---|
| I-1 | 1단계 CORE 병합 | INFRA lock 재생성 뒤 CORE 시험 전부(VM·Chrome·perf) + **V7**(VM·Chrome — v1 사본 해시 포함) + `ws check` 0. (v2.1) INK 병합(2단계) 뒤 INK 시험이 CORE 캘리그래피 키 상수 = `InkStyleExtras.nibAngleDeg`를 확인하는지 본다(C2-38) |
| I-2 | 3단계 SYNC | T16-v2(실제 CORE 2개: 객체 동시 편집·삭제 대 수정·모르는 `type` 왕복·모르는 `kind` 보류·손글씨 결과)가 실패하면 CORE 원인(힌트·고아·키 집합·`content_rev`)을 고친다 |
| I-3 | 4단계 PDF | `integration`(객체 내보내기 — `NoteContentReader.loadPage`의 `objects`, 실제 색인 사각형 — V10), `media`(V8·V16 — `openWebTestNoteStore`의 실제 CORE 초안·meta·에셋·녹음 행) 실패 시 CORE 쪽 수정 |
| I-4 | 5단계 LIBRARY | L2x(실제 CORE 색인: `searchLibrary.pages`, 가짜 엔진으로 `notesWithStalePages` → `stalePages` → `update` → 검색) |
| I-5 | 6단계 EDITOR | E-2x(실제 INK + 실제 CORE: 객체 도구·혼합 선택·`transformed` 미리보기 = 저장 결과·녹음 연동) |
| I-6 | 7단계 INFRA | V5·V6 앱 스모크 v2(메모리 CORE), V10의 CORE 부분(VM·Chrome 같은 결과, 5,000쪽 예산, (v2.1) 실제 모양 500쪽 크기·다시 열기 시간) 판정, 네이티브 경로 연결 확인(정적 시험), 개발자 메뉴 v1 사본 내보내기·지우기(CP-17) |
| I-7 | 끝 | 진행 기록 '2차' 절, README, 7.8 실기기 확인(9.5) 결과 받기 |

### 8.4 작업량

| 묶음 (개요 2.4 단위) | 개요 추정 | 이 계획 |
|---|---|---|
| 객체 모델·JSON·불변식 | 2 | 2 (T22 일부·T20a·T20b·T23a 일부) |
| DB v2·마이그레이션·행 변환·outbox | 3 | 4 (T24·T25a·T25b·T26 — V7 Chrome 시험·생성기 +0.5, (v2.1) v1 사본·정규 덤프 +0.5) |
| 명령·해석기·세션·초안 | 2 | 2 (T23a·T27) |
| 복사·휴지통·백업·가짜 | 2 | 2 (T29·T23b 일부) |
| 녹음 저장소·초안·포트·가짜 | 2.5 | 2.5 (T21 일부·T30·T31·T23b 일부) |
| 손글씨 결과·저장소 | 1 | 1.5 (T32 — (v2.1) `update`·`notesWithStalePages`·경합 본문 +0.5) |
| 검색 색인 | 3 | 3.5 (T21 일부·T33a·T33b·T34 — (v2.1) 사각형 블롭·후보 흉내·크기 시험 +0.5) |
| 네이티브 저장 | 1.5 | 1.5 (T35) |
| 동기화 창구 v2 | (DB 묶음 안) | 0.5 (T28을 따로 셈) |
| provider·성능·문서 | — | 0.5 (T36·T37) |
| **합계** | **17** | **20** |

- 기반 단계 R2-B2의 세션 추정(8.1): B2-0 0.1~0.2, **B2-α 약 0.5**(해시 알림까지), B2-β 약 2.0(T20a 0.3·T20b 0.3·T21 0.5·T23a 0.4·T23b 0.5). 다른 영역은 B2-α 해시 뒤 코드 작성을 시작할 수 있으므로 임계 경로 맨 앞의 CORE 몫은 약 0.6세션이다(v2.0 계획은 T20~T22 끝까지 약 1.5세션 [추측]).
- +3은 V7 브라우저 시험·생성기, v1 사본, 손글씨 `update` 경합, 검색 사각형 블롭·크기 시험, 동기화 창구 시험, provider·성능을 따로 센 몫이다. 1차 CORE가 19 작업을 5세션에 끝낸 속도로 보면 동시 개발 기간 안에 들지만 여유가 줄었다(11장 위험 9).

### 8.5 진행 기록 양식 — 이정표 커밋 (v2.1, CORE-M13)

2차 진행 기록 `docs/plans/progress/core.md`의 '2차' 절 맨 위에 아래 표를 두고, 이정표 커밋마다 한 줄을 더한다(빈 줄을 미리 만들어 둔다). 다른 영역은 이 표로 기다리던 시점을 판단하고(7.6.2 '진행 기록 양식에 고정'), 총괄은 묶음 병합 때 B2-α·T20a 해시를 이 표에서 읽는다.

```markdown
### 이정표 커밋 (CORE 2차)

| 이정표 | 작업 | 커밋 | 날짜 | 이 커밋으로 할 수 있게 되는 것 | 기다리는 영역 |
|---|---|---|---|---|---|
| V7 고정 자료 | T25a | | | 1차 v1 DB 고정 자료(생성 커밋은 fixture_source.json) | 총괄 |
| B2-α 계약 타입 커밋 | T22 | | | 공개 선언 전부 컴파일 — R2-B7a 바탕, R2-B2i 위임, 전 영역 코드 작성 시작 | SYNC·INFRA·전 영역 |
| B2-β JSON 골든 | T20a | | | 객체·손글씨·녹음 JSON 키 고정 — 키 대조 시험(CP-S9) | SYNC |
| B2-β 끝 | T23b | | | 가짜 저장소 v2·가짜 오디오·픽스처·testing_web 동작 | 전 영역 |
| DB v2·마이그레이션 | T24 | | | openTestNoteStore가 v2 DB, v1 사본 | SYNC·PDF·LIBRARY·INFRA |
| 쓰기 경로 | T26 | | | 새 종류 행·힌트·고아 — SYNC 시나리오 시험 | SYNC |
| 객체 읽기·쓰기 DB | T27 | | | 실제 저장소 객체 명령·N-7 | EDITOR·PDF |
| 동기화 창구 v2 | T28 | | | applyRemote·readVersioned 새 종류 — T16-v2 | SYNC |
| 복사·휴지통·백업 | T29 | | | copyNote·영구 삭제·백업 v2 | LIBRARY·SYNC |
| 녹음 저장소 | T30 | | | createRecording(멱등)·watch | PDF(media)·EDITOR |
| 실제 초안 저장소 | T31 | | | meta·되살림·조각 — V16 | PDF(media) |
| 손글씨 저장소 | T32 | | | update·stalePages·notesWithStalePages | LIBRARY |
| 색인 쓰기 | T33a | | | SearchIndexWriter 실제 — PDF 색인기 | PDF |
| 검색 색인 | T33b | | | searchPages·searchLibrary.pages 실제 | LIBRARY·PDF |
| 네이티브 저장 | T35 | | | 파일 DB + 파일 블롭 | INFRA(A-1) |
```

- 한 줄마다 '확인'(그 커밋에서 돌린 시험·결과)을 진행 기록 본문에 1차처럼 적는다. 이정표 커밋은 다른 작업과 섞지 않는다(기다리는 쪽이 그 해시를 바탕으로 쓰므로).

---

## 9. 테스트 계획

### 9.1 실행 명령과 부하 규칙

```text
flutter test                                          # VM 단위·통합 (@TestOn('browser') 자동 제외, perf skip)
dart run tool/prepare_web_test.dart                   # test/web/sqlite3.wasm, drift_worker.js, (v2.1) fixtures_v1/ 준비 (1차 T16 + 6.18.1)
dart run tool/prepare_web_test.dart --out <dir>       # (v2.1) 다른 패키지의 test/web으로 wasm·worker만 (testing_web.dart 사용처)
flutter test --platform chrome test/web/<file>        # 브라우저 — 평소에는 바꾼 파일만
flutter test --run-skipped -t perf                    # 성능 예산 (체크포인트 때)
UPDATE_BACKUP_GOLDEN=1 flutter test test/backup/backup_export_test.dart   # 백업 골든 갱신 (VM 전용, 1차 T19)
```

- 같은 컨테이너에서 영역 7개와 다른 에이전트가 시험을 돌린다(5장). 평소에는 패키지 단위·바꾼 파일만, `test/web` 전체와 `perf`는 체크포인트 때만 돌린다. (v2.1, CD2-19) 전체 Chrome 실행은 `dart run tool/ws.dart with-heavy-lock -- …`(또는 `ws test --platform chrome`이 잡는 전역 잠금 `/tmp/noteapp-heavy-tests.lock`) 안에서만 한다. CORE는 `media`·`emulator`·`integration` 태그를 쓰지 않는다(`dart_test.yaml` 그대로 — `perf`·`golden`).
- 골든은 1차 규칙(`@Tags(['golden'])` + `@TestOn('vm')`, 바이트 비교). 의도한 골든 변경은 `recording.json`과 백업 골든 두 개뿐이다(새 골든 9개는 추가).
- 성능 판정은 load < 4에서 다시 잰다(1차 통합 진행 기록 — 부하 5.8에서 1획 커밋 중앙값이 27.6 ms까지 올랐다).

### 9.2 시험 묶음

| 묶음 | VM | Chrome | 비고 |
|---|---|---|---|
| 계약 표면 (T22 — B2-α) | `api_surface_test` v2, `providers_fake_test`, `open_test_store_test`(B2 상태) | `testing_web_browser_test`(컴파일) | 1차 시험 전부와 함께 |
| 모델·JSON (T20a·T20b·T21) | `test/model/*`, `test/common/element_frame_test.dart`(경계값 왕복), `calligraphy_transform_test`, `search_rects_codec_test`, 골든 | `object_json_browser_test`, `search_text_browser_test` | 웹 정수 입력·VM = 웹 정규화·점수 비트 같음 |
| 명령·세션·되돌리기 (T23a·T27) | `test/edit/object_commands_test`, `undo_objects_test`, `calligraphy_transform_test`, `test/session/*objects*` | — | 공유 본문(가짜·실제) |
| 저장·마이그레이션 (T24~T26·T35) | `test/storage/*v2*`, `v1_copy_test`, `canonical_dump_test`, `native_file_store_test`, `test/migration/v1_fixture_migration_test` | `v1_fixture_migration_browser_test`, `v1_copy_browser_test`, `canonical_dump_browser_test` | V7(사본 해시 포함) |
| 동기화 창구 (T28) | `test/sync/*v2*`, `unknown_object_roundtrip_test` | — | SYNC T16-v2의 CORE 쪽 받침 |
| 녹음·초안 (T30·T31) | `test/repo/recording_*`, `test/media/*` | `recording_draft_browser_test` | V16의 CORE 부분(meta 되살림 포함) |
| 손글씨 (T32) | `test/repo/handwriting_*`(경합 사례) | — | G-4 |
| 검색 (T33a·T33b·T34) | `test/search/*`, `library_search_v2_test` | `search_fts_browser_test`, `search_reopen_time_browser_test`(`perf`) | V10(크기·다시 열기 시간 포함) |
| 복사·휴지통·백업 (T29) | `note_copy_v2_test`, `trash_purge_v2_test`, 백업 | `backup_export_browser_test` | R-6 |
| 가짜·도우미 (T23b) | `test/testing/*` | `testing_web_browser_test` | 다른 영역이 기대는 동작 |
| provider (T36) | `test/providers/*` | — | |
| 성능 (T37) | `test/perf/*`(PF-1~PF-11) | PF-10w, 그 밖은 기록만(1차 T16 방식) | `perf` 태그 |

### 9.3 계약 보장 ↔ 시험

| 계약 | 시험 |
|---|---|
| C-11 (변형 한 커밋, 바뀐 키만 새 버전) | `object_commands_test`, `undo_objects_test`, `outbox_v2_test` |
| C-12 (`UnknownObject` 키 보존) | `object_json_test`, `row_mappers_v2_test`, `unknown_object_roundtrip_test`, 골든 `unknown.json` |
| C-13 (색인은 파생, 실패 격리, `rebuild` 멱등, (v2.1) 다음 쓰기 트랜잭션·저장소 열기 재시도·`pendingOwners`) | `search_index_writer_test`(실패 주입·재구축·재시도 시점) |
| C-14 (마이그레이션이 1차 데이터를 바꾸지 않음) | `migration_v2_test`, `v1_fixture_migration_test`(VM·Chrome — `entityDumpSha256`) |
| 7.2.7 (v2.1) 업그레이드 직전 v1 사본 · V7 사본 해시 | `v1_copy_test`, `v1_copy_browser_test`, `v1_fixture_migration_test` ④·④′(`fullDumpSha256`) |
| 7.2.2 (v2.1) 단일 변형 규칙·`fromJson` 비정규화·`referencedAssets` | `page_object_test`, `element_frame_test`(경계값 왕복), `object_json_test` |
| C2-38 캘리그래피 각 | `calligraphy_transform_test` |
| K-6의 기준(`bounds`) | `page_object_test`(공식), INK 불변식 시험이 CORE 값 사용 |
| R-6·R-7·R-8 | `note_copy_v2_test`, `recording_repository_test`, `undo_objects_test`(녹음·손글씨가 히스토리에 없음) |
| M-1 받침(에셋 없으면 `ArgumentError`, (v2.1) `createRecording` 멱등·저장 실패 시 초안 유지) | `recording_repository_test`, `fake_audio_recorder_test` |
| M-2 받침(초안 내구성·순서·(v2.1) meta·빈 조각) | `recording_draft_store_test`, `recording_draft_browser_test` |
| M-4 받침(`readAll` 한 벌) | `recording_draft_browser_test`(30분 분량 기록) |
| 7.2.4 `pendingDrafts` 제외 규칙(가짜) | `fake_audio_recorder_test` |
| G-4 (`update` 한 트랜잭션 병합) | `handwriting_contract_{fake,real}_test`(경합 사례 1~7) |
| X21·L-1(결과 그대로), CP-14(가짜 같은 판정·순서) | `search_contract_{fake,real}_test` 같은 결과·순서·`pagesTruncated`, `fts_candidate_equivalence_test` |
| X22(`stalePages`·`put`·`update`·`notesWithStalePages`) | `handwriting_repository_test`, PF-11 |
| X23(`SearchIndexWriter`·비율 좌표·빈 목록 소유자·`pdfPageAspect`) | `search_index_writer_test`, `search_index_test` |
| 7.4.5 (v2.1) 색인 크기 목표 | PF-10·PF-10w |
| X24·7.2.8 힌트 | `outbox_v2_test`, `change_bus_v2_test` |
| 7.2.6 네이티브 저장·(v2.1) 루트 디렉터리·CP-11 | `native_file_store_test`, `asset_store_test` |
| C2-15 묶음 | R2-B2 묶음 검사(8.1) |

### 9.4 다른 영역 시험이 CORE에 기대는 것 (통합 때 같이 본다)

- SYNC T16-v2, PDF `integration`·`media`(V8·V16 — `openWebTestNoteStore`), LIBRARY L2x, EDITOR E-2x, INFRA V5·V6·V15 — 모두 실제 CORE v2를 쓴다(8.3).
- PDF 정규화 동치(C2-27): PDF가 CORE `SearchText.normalize`(·`normalizeMapped`)를 부른다. CORE는 `search_text_cases.dart`의 입력 표를 PDF 계획서·진행 기록에 알린다.
- INK 미리보기 = CORE `PageObject.transformed`·`Stroke.transformed`(CD2-07·C2-38): INK·EDITOR 시험이 CORE 함수를 직접 부르므로 CORE 쪽 변경은 이 함수들의 시험(`page_object_test`·`calligraphy_transform_test`)이 먼저 잡는다.

### 9.5 실기기 체크리스트 (7.8 중 CORE 몫 + CORE 추가)

A. 안드로이드 APK (기기가 있을 때 — U2. 없으면 '코드만, 확인은 이후')

| # | 확인 | 근거 |
|---|---|---|
| A-1 | (v2.1 원문, 검토 S-11) 고정 키 2차 APK에서 노트·이미지·녹음 작성 → 다음 판 고정 키 APK를 덮어 설치 → 모두 남아 있음(파일 DB·파일 에셋). 처음 한 번은 기존 앱(1차 debug 서명 APK — 러너마다 키가 다르고 노트를 저장하지 못했다)을 지우고 설치한다. '설치되지 않음'이 뜨면 앱을 지우지 말고 알린다. **1차 노트는 없다** — 1차 앱 셸이 `nativeDatabasePath`를 넘기지 않았다(`app/lib/src/modules/core_module.dart` 216–222 `defaultNoteStoreConfig` [확인]) | 공통-1, 6.15.3 |
| A-c1 | 텍스트 상자·PDF 글자 검색이 결과를 냄(안드로이드 sqlite3 빌드 훅 바이너리의 FTS5) | 위험 7 |
| A-c2 | 앱 정보 '저장 공간'에 녹음 용량(`bytesByType[audio]`)이 보이고, 녹음 삭제 뒤 목록에서 빠짐(바이트는 남음 — U13) | F-16 |

B. iPad 웹(Safari, 홈 화면 앱) — (v2.1) Firebase Hosting이 생긴 뒤(3.7, U24). 통합 미리보기 채널에서 확인하고, B-1만 실제 노트가 있는 live 채널

| # | 확인 | 근거 |
|---|---|---|
| B-1 | (v2.1 원문, 검토 M-3) 1차로 쓴 실제 노트가 있는 출처(live 채널 홈 화면 앱 — U25)에서: **배포 전 백업 내보내기**(INFRA 안내서 08) → 그 출처에 2차 배포 → 첫 실행 → 노트가 그대로 열림(DB v2 이주) → 개발자 메뉴에 v1 사본 있음(크기·만든 시각 — CP-17). 실제 노트가 없으면(U25 기본값) 1차 빌드로 노트 몇 개를 만든 뒤 같은 절차. 미리보기 채널은 출처가 달라 이 확인이 되지 않는다 | V7 실사용, 6.12.3·6.12.4, 위험 1 |
| B-10 | 텍스트 상자·PDF 텍스트·수식으로 찾기 → 그 페이지·위치로 열림, 발췌·강조 범위가 맞음 | M7-2~4 |
| B-13 | 복합 노트에서 개발자 표시 캐시 합계 ≤ 300 MB, 저장 공간 추정(1차 `StorageInfo`)에 색인 증가분 기록. (v2.1 원문) **PDF 500쪽 색인이 끝난 뒤 앱 다시 열기 시간·메모리**(개발자 표시 열기 시간 + Safari 탭이 다시 읽히지 않음) 기록 — 목표 +300 ms(6.10.7) | 7.4.5, 6.10.7 |
| B-14 | 녹음 중 탭 닫기 → 다시 열면 '복구된 녹음'(초안 저장소 — meta 되살림 포함) | M-2, D13 |
| B-c1 | 백업 내보내기 파일에 `pageObject`·`handwriting` 기록과 녹음 `title`이 있음 | 6.14.4 |
| B-c2 | (v2.1) 개발자 메뉴 'v1 DB 사본 내보내기'로 받은 파일이 열림(정규 덤프 텍스트), '지우기' 뒤 메뉴에서 사라짐. 정상 열기 5번 + 7일 뒤 자동으로 사라짐(다음 확인 때) | 6.12.4 |

C. TestFlight 뒤 (2차 완료 조건 아님)

| # | 확인 |
|---|---|
| C-c1 | iOS 네이티브 파일 DB·파일 블롭(앱 지원 디렉터리 — CORE가 만듦), FTS5 검색(iOS sqlite3 바이너리), 앱 갱신 뒤 노트 유지 |

---

## 10. 완료 기준

1. 8.1·8.2의 T20a~T37(T22·T25a·T25b·T33a·T33b 포함) 완료 조건 시험이 모두 통과한다(VM·Chrome·골든), `--run-skipped -t perf`가 PF-1~PF-11 예산 안이다(PF-3·PF-4는 (v2.5) C25-01 예산 — 후보 100개 미만 ≤ 5 ms·1글자 LIKE ≤ 15 ms, 그 밖 ≤ 50 ms, 판정은 load < 4(9.1). PF-10의 DB 증가 ≤ 12 MB·PF-10w의 다시 열기 +300 ms 포함 — 넘으면 6.10.7의 대응을 하고 총괄에 알린다).
2. 1차 CORE 시험(1차 통합 HEAD 기준 VM 619개·Chrome 47개)이 모두 통과한다. 골든 변경은 `recording.json`·백업 골든뿐이다.
3. 공유 계약 본문(객체 세션·녹음·초안·손글씨(경합 사례)·검색(후보 상한 포함)·provider·라이브러리 복사)이 가짜와 실제 양쪽에서 같은 결과를 낸다.
4. V7(VM·Chrome — v1 사본 해시 포함)과 V10의 CORE 부분(같은 결과·5,000쪽 예산·실제 모양 500쪽 크기·다시 열기 시간)이 통과한다.
5. 패키지 `flutter analyze --fatal-infos` 0건(생성 `note_database.steps.dart` 포함), `dart format` 변경 없음, `ws check` 위반 0(R14 이름 충돌 포함).
6. R2-B2 묶음(R2-B7a·R2-B2i와 함께) 병합 뒤 전체 `ws test`가 통과했고, B2-α·T20a 해시가 진행 기록 이정표 표(8.5)에 있다.
7. 통합 단계 I-1~I-6에서 CORE 원인 실패가 남아 있지 않다.
8. README에 2차 사용 예가 있고 `readme_examples_test`가 실행한다. 진행 기록 `docs/plans/progress/core.md`에 '2차' 절(이정표 커밋 표·작업 표·계획과 다르게 한 점·변경 요청)이 있다.
9. 12.1 계약 변경 제안 중 승인된 것이 코드·이 문서에 반영되고, 거절·보류된 것은 원문대로 구현되어 있다.

---

## 11. 리스크와 대응

| # | 위험 | 영향 | 대응 |
|---|---|---|---|
| 1 | (v2.1 정정, 검토 M-3) **실제 데이터의 이주는 그 데이터가 있는 출처(live)에 2차가 배포될 때 처음 일어난다** — 미리보기 채널은 출처가 달라 실제 노트를 보지 못하고, 고정 자료는 실제 DB와 행 형태·크기가 다를 수 있다. 이주가 실패하거나, 성공한 뒤 2차 버그로 데이터가 상할 수 있다 | 노트를 열 수 없음 / 1차로 돌아갈 수 없음(`NewerSchemaError`) | ① 한 트랜잭션(실패 시 v1 그대로 — 되돌린 배포가 연다), 단계마다 이름 붙은 `SchemaStepError` ② V7 VM·Chrome ③ **업그레이드 직전 v1 사본**(6.12.4 — 네이티브 `VACUUM INTO` 파일, 웹 블롭 정규 덤프, 정상 열기 5번 + 7일 보관, 개발자 메뉴 내보내기) — 이주 성공 뒤 손상에도 되돌릴 마지막 안전망 ④ 7.8 B-1 절차: **배포 전 백업 내보내기(INFRA 안내서 08) → 실제 노트가 있는 출처에 배포 → 첫 실행 → 확인** ⑤ U25 기본값(실제 노트 없음)이 틀려도 ③이 있다 |
| 2 | wasm에서 FTS5 `contentless_delete`가 동작하지 않음(VM만 확인) | 웹 색인 삭제 불가 | T33a 첫날 Chrome 시험. 안 되면 외부 내용 테이블(`content='search_units'` + 색인 낱말 열 `terms`, 'delete' 명령)로 바꾼다 — 크기는 커지지만 의미는 같다(6.10.7 목표 다시 확인) |
| 3 | (v2.1 확대, 검토 M-1) 검색 색인이 **웹 DB 메모리·열기 시간**과 저장 공간(Safari 할당량·축출)을 압박 — 웹 DB는 열 때 통째로 메모리에 올라온다 | 앱 시작 지연·메모리 초과로 탭 재로드, 저장 실패 | 글자 상자는 SQLite 밖(블롭, 1/65535 — 6.10.3), 질의는 대표 결과만 원문·사각형을 읽음(6.10.4), 크기 목표 500쪽 ≤ 12 MB·다시 열기 +300 ms(7.4.5)와 실험(한국어 7.7 MiB — 6.10.7), PF-10·PF-10w·B-13. 넘으면 `body`도 블롭으로 → 그래도 넘으면 색인 범위 축소를 총괄에 올림. 저장 공간은 1차 `persist()`·저장 경고 그대로 |
| 4 | 가짜와 실제의 검색 결과 차이로 LIBRARY 시험이 통합 때 깨짐 | 통합 지연 | 판정·랭킹을 한 파일에서 공용, 후보 순서·상한까지 같은 규칙과 FTS 후보 흉내(동치 무작위 시험), 공유 계약 본문을 둘 다에 돌림(6.10.6) |
| 5 | 객체 JSON 키가 SYNC `FieldUnits`·`kPageObjectTypeKeys`와 어긋남 | 동기화 때 필드 유실 | B2-β 첫 조각(T20a)에 골든 고정·해시 알림, 종류별 키 항상(`engine: null`), SYNC 키 대조, 키 바꿀 때 7.4.9 절차 |
| 6 | 웹 초안 1초 쓰기(IndexedDB + SQLite 커밋)가 필기 지연에 영향 | 필기감 저하 | DB는 웹 워커, PF-7 측정, B-8 실기기. 크면 media가 조각을 메모리에서 묶어 쓰기 횟수를 줄이는 안(D13 1초는 계약 값 — 변경 절차) |
| 7 | 안드로이드·iOS에서 sqlite3 빌드 훅 바이너리(내려받기)·FTS5가 실제로 동작하지 않음 | 네이티브 저장·검색 실패 | `android.yml` 첫 빌드(V14)에서 훅 내려받기 확인, A-1·A-c1, iOS는 TF 뒤(C-c1). 문서상 기본 바이너리가 모든 플랫폼 `ENABLE_FTS5` |
| 8 | (v2.1 확대, 검토 S-4) 긴 녹음의 **정지와 복구 모두** 웹에서 녹음 전체(3시간 ≈ 86 MB)를 한 버퍼로 든다 | 탭 재로드 | `readAll`은 결과 한 벌 + 조각 하나(6.7.3), media는 두 벌 넘게 들지 않음(M-4), 복구는 앱 시작 뒤 유휴 때 하나씩·시도 2회 상한(7.2.12 — INFRA `MediaModule`·PDF), 30분 분량 Chrome 기록. 문제가 되면 다음 라운드에 `AssetStore`에 조각 단위 넣기 API |
| 9 | CORE 작업량(20)과 기반 단계 조각 수가 늘어 임계 경로가 길어짐 | 일정 지연 | B2-α(약 0.5세션)를 먼저 내 다른 영역이 바로 시작(8.1), 이정표 커밋 표(8.5)로 기다림을 줄임, P-C부터 자름(8.2) |
| 10 | `EntityKind`·`NoteStore` 깨짐 묶음(R2-B2·B7a·B2i)의 병합 순서가 어긋남 | `main` 빌드 깨짐 | B2-α 해시를 바탕으로 통일(SYNC·INFRA), 총괄이 세 브랜치를 함께 병합 |
| 11 | 마이그레이션 직후 라이브러리 전체 첫 따라잡기(`notesWithStalePages`)가 느림 | 색인기 첫 실행 지연(네이티브만) | 페이지 단위 계산·캐시·50쪽 묶음 사이 양보(6.9.3), 색인기는 유휴 때(G-2), 10만 획 읽기 실험 0.12~0.16 s, PF-11. 넘으면 덮개 색인 재검토(웹 DB +10 MB 비용과 견줌) |
| 12 | 웹 v1 사본 만들기가 큰 1차 DB에서 첫 실행을 늦춤(76 MB면 수 초 [추측]) | 첫 실행 지연(한 번) | 표마다 2,000행씩 스트리밍(메모리 일정), V7 Chrome 시간 기록, INFRA 안내서에 '첫 실행이 길 수 있음'. 사본 실패는 이주를 막지 않음(6.12.4) |
| 13 | 정규화 통합으로 제목 검색·정렬이 일부 바뀜 | 사용자 혼란(드묾) | 차이는 하이픈 줄바꿈·폭 없는 문자뿐, 마이그레이션이 파생 열 재계산·쓰기 경로 위임을 같은 T24에서(검토 S-16), 1차 시험 그대로 통과 확인 |
| 14 | 객체가 많은 페이지의 메모리·되돌리기 비용 | 탭 재로드 | `PageObjectLimits`(2,000), `estimatedBytes`, PF-1·PF-2 |
| 15 | IndexedDB 기본 내구성(브라우저가 fsync를 미룸)과 drift 웹 행의 비동기 반영 — OS 수준 강제 종료에서 마지막 조각·행 손실 | 1초 미만 손실, 행 유실 | 행 유실은 meta·조각으로 되살림(6.7.2 — 검토 S-3), 탭 닫힘·새로 고침은 조각 기준 안전(B-14). 계약 문장 '잃는 것은 마지막 1초 이하'(M-2)와 같다 |
| 16 | 7장이 02-core를 가리킨 세부(4.3·4.5·4.6·6.2.3·6.8.2)가 다른 영역의 기대와 다름 | 통합 때 수정 | B2-α 커밋 때 README·`api_surface_test`로 공개, 12.1 CP로 7장에 반영 요청, 가짜와 실제가 같은 공유 본문 |
| 17 | (v2.1) 캘리그래피 각 규칙(C2-38)의 키 문자열이 INK와 어긋남 | 회전한 캘리그래피 글씨가 원래 각으로 그려짐 | CORE 상수 = 1차 `defaultsFor` extras 키, 통합 2단계 INK 시험이 대조(8.3 I-1) |

---

## 12. 총괄에게 묻는 질문 · 계약 변경 제안

### 12.1 계약 변경 제안 (승인 전까지 원문대로 구현 — 7.4.9)

v2.0 초안의 CP-1~CP-15는 총괄 검토(00-review 2.2)에서 모두 받아들여져 계약 v2.1에 들어갔다. 아래 '판정'은 그 결과이고, 이 문서 4절은 v2.1 원문을 옮겼다. 새 제안은 CP-16·CP-17이다. 동시 개발 중 새 제안: CP-18 — (v2.5) **승인**(C25-01).

| # | 7장 | 제안 | 판정 (v2.1 · CP-16·17은 v2.2 · CP-18은 v2.5) | 반영 위치 |
|---|---|---|---|---|
| CP-1 | 7.2.3 | 새 명령을 1차 모양으로(`const`·이름 있는 인자·`label`), `RemoveElements.elementIds`를 `List<ElementId>`로 | **승인**(C21-07 — 검토자 권고 `Set`이 아니라 제안대로 `List`) | 4.4, 5.3, 6.4.1 |
| CP-2 | 7.2.3 규칙 | `TransformElements`가 `TextBoxObject.style.fontSizePt`도 배율([6, 144]) | **승인** — `PageObject.transformed(m, {scaleWidth})` 단일 규칙으로(C21-06, CD2-07) | 4.2 원문, 6.2.5 |
| CP-3 | 7.2.5 | `SearchUnitDraft.pdfPageAspect`, `rects` 해석 규칙 | **승인**(C21-09) | 4.6, 6.10.3·6.10.4 |
| CP-4 | 7.2.2 | 생략 멤버 계약화(공통 필드, `UnknownObject` 생성자·`toJson` 메타 키, `normalized`·`maxSide`, `estimatedBytes`, `==`) | **승인**(C21-06) | 4.1·4.2 원문, 4.3 |
| CP-5 | 7.2.2 | 스타일 정규화 표, `MathStyle.normalized`·`copyWith`·한도 | **승인**(C21-06) | 4.2 원문, 6.2.3 |
| CP-6 | 7.2.2 규칙 | 알려진 `type`의 모르는 enum 이름 → `UnknownObject` | **승인**(C21-06) | 4.2 원문, 6.2.6 |
| CP-7 | 7.2.4 | `Unsupported*` 동작표, `copyWith`·`==`, `title` 키 항상, `createRecording` 멱등, 초안 규칙 | **승인**(C21-08) | 4.5, 6.6, 6.7, 6.8.2 |
| CP-8 | 7.6 | `FakeAudioRecorder.abandon()`·초안 쓰기, `FakeAudioPlayback.calls` | **승인**(C21-30) | 4.9 원문, 6.8.3·6.8.4 |
| CP-9 | 1차 4.10 | `seedSyntheticNote(…, int objectsPerPage = 0)` | **승인(P-C)** | 3절 트리, 4.11, 8.2 '자를 것'. (동시 개발 보완 2.1 — 8.2 표에 작업이 없어 T37(성능 도구)로 구현) 쪽마다 획 뒤에 세션 `AddObjects` 하나, 0~`PageObjectLimits.maxObjectsPerPage`, 쪽 안 격자, 17개마다 도형 10(모든 `ShapeKind` 차례로)·텍스트 상자 5·수식 1·이미지 1(노트마다 64 × 48 PNG 에셋 하나 — `store.assets.put`), 340 = INK B14 객체 페이지(도형 200·텍스트 100·수식 20·이미지 20). 시험 `test/dev/seed_synthetic_note_test.dart` |
| CP-10 | 7.2.5 | `SearchText.normalizeMapped` 공개 | **승인**(C21-09) | 4.6(`SearchTextMapping` 필드), 6.10.1 |
| CP-11 | 7.2.6 규칙 | 로컬 `AssetStore.put(type: image)` 형식 검사 | **승인**(C21-10) | 4.7 원문, 6.15.2 |
| CP-12 | 7.2.2·7.2.4 문구 | ① 뒤집기 근사 문구 ② M-2 '묻지 않고' | **승인**(C21-19·C2-38) | 5.4 원문, 6.2.1 |
| CP-13 | 7.2.5 | 손글씨 `copyWith`·`==`, `put` 검증, `stalePages` 페이지 순서 | **승인**(C21-09) | 4.6, 6.9 |
| CP-14 | 7.6·7.2.5 규칙 | 가짜 검색 = 실제와 같은 판정·같은 순서, `pagesTruncated` 뜻 | **승인**(C21-30·C21-09) | 4.6·4.9 원문, 6.10.6 |
| CP-15 | 7.2.7 표 | 검색 테이블 표 정정(소유자 테이블·`seq`·FTS 옵션) | **수정 승인** — 사각형 열 변경까지 함께 정정(C21-11) | 4.8 원문, 6.11 |
| **CP-16** | 7.2.7 문단 (v2.1 사본) | '업그레이드 직전 v1 사본' 문장을 저장 방식별로 구체화: **네이티브 = `VACUUM INTO '<nativeDatabasePath>-v1-backup'`, 웹 = 블롭 저장소(`noteapp_blobs`)의 정규 덤프(`db/v1-backup/…` — 계약의 '같은 저장소 안의 다른 사본 방법')**, 수명 N = 정상 열기 5번 + 7일, V7 '정규 덤프 해시' = 6.12.3 형식 | **승인**(C22-02 — 7.2.7 문단) | 근거 [확인]: 웹 VFS 사본은 지울 길이 없어 계약의 자동 삭제를 채우지 못하고, 남아 있는 동안 열기 메모리·시간을 두 배로 만든다(6.12.4). INFRA 안내서 08·개발자 메뉴가 이 방법·수명을 적는다 |
| **CP-17** | 7.1 `dev_tools.dart`·7.2.7 | `dev_tools.dart`에 `V1DatabaseCopyInfo`, `v1DatabaseCopyInfo(store)`, `readV1DatabaseCopy(store)`(≤ 4 MiB 조각 스트림), `deleteV1DatabaseCopy(store)` 추가(6.12.4 블록) | **승인**(C22-01 — 7.1 표·7.2.7 블록) | INFRA 개발자 메뉴 'v1 DB 사본 내보내기·지우기'(X-6, CD2-23)가 부를 CORE 표면이 계약에 없다. 가짜 저장소는 `null`·아무것도 안 함 |
| **CP-18** | 7.7.2 V10 (+ 이 문서 6.19 PF-3·PF-4, 6.10.7) | (동시 개발 T33b, 2026-11-06 — 진행 기록 '변경 요청 (동시 개발)' [총괄] V10) '5,000쪽 합성 색인 질의 중앙값 ≤ 5 ms(VM)'를 **'후보 100개 미만 질의 ≤ 5 ms(1글자 LIKE는 ≤ 15 ms), 그 밖의 질의(후보 상한 2,000까지) ≤ 50 ms(VM)'**로. (보완 1.4에서 고침 — 처음 제안의 경계 '300개 미만(1글자 LIKE 600개 미만)'은 load < 4에서도 136개·결과 100쪽 질의가 3.3~5.2 ms, 576개 1글자 LIKE가 14.2~15.8 ms로 여유가 없었다) | **승인 v2.5 C25-01**(2026-11-06 — 제안 문구 그대로: '후보 100개 미만 질의 중앙값 ≤ 5 ms(1글자 LIKE ≤ 15 ms), 그 밖의 질의(후보 상한 2,000까지) ≤ 50 ms(VM)', 7.2.5 후보 규칙·CP-14는 그대로). 반영: `test/perf/search_perf_test.dart`의 두 시험('V10 as written' — 판정 전 원문 예산, 흔한 낱말에서 실패 / 'CP-18 as proposed' — 회귀 방지)을 v2.5 판정 시험 하나로 합침(질의마다 센 후보 수로 예산을 고르고, PF-3·PF-4 각각 100개 미만·이상 칸에 질의가 있는지 봄 — PF-4의 100개 미만 칸은 자료에 없는 음절로 더함, 질의 15개). 판정 전 기록: 원문으로는 흔한 낱말 7개가 load < 4에서도 22~31 ms·1글자 LIKE 19~23 ms(보완 1.4, 여덟 번) | 6.19 PF-3·PF-4·PF-10, 6.10.7, 10장 #1, `search_perf_test`(v2.5). 근거 [확인]: 7.2.5 '살아 있는 후보만 2,000개, 최근 먼저'와 CP-14 '가짜와 같은 판정·순서'를 지키려면 후보마다 살아있음 판정과 `norm`(쪽당 ~320자)의 판정·점수를 Dart에서 해야 한다 — 상한에서 FTS MATCH 1 ms, 살아있음 3, `norm` 옮기기 6~8, 판정·순위 3~5, 결과 읽기 2~3 ms(조사 03 9.2의 5 ms 근거는 MATCH만 잰 값). 예산을 두는 대안: 후보 상한 낮추기(7.2.5 `SearchIndex.searchPages`·`LibrarySearchResult.pagesTruncated` 주석 변경 — 흔한 낱말에서 `pagesTruncated`가 늘 참, 결과가 최근 단위 몇백 개로 좁아짐). 상한 300 실험에서도 PF-3 흔한 낱말 5개 중 4개가 5.1~9.7 ms(load 6)라 300으로는 모자란다(상한 ≲ 150 또는 결과 수 축소까지 필요). 비용은 읽는 후보 수(상한까지)와 돌려주는 쪽 수(100까지 — 원문·발췌 ≈ 3 ms)에 함께 비례하고, 1글자 LIKE는 5,000단위 전부를 훑는 바닥값(≈ 5 ms)이 더해진다 |

판정(총괄 기입 — 최종 승인 2026-11-05, 계약 v2.2): **CP-16 승인**(C22-02 — 00-overview 7.2.7 문장을 저장 방식별 방법·수명 5번 + 7일·실패 시 이주 진행으로 고쳤다), **CP-17 승인**(C22-01 — 6.12.4 블록을 7.2.7에 글자 그대로 옮겼다. 머리 주석 한 줄만 계약 표기). B2-α에 선언을 두고 T24에서 동작을 채운다.

### 12.2 질문

| # | 질문 | 답 (00-review 3.2) · 반영 |
|---|---|---|
| Q1 | CP-1을 기반 단계 전에 결정해 줄 수 있는가 | 승인(이름 있는 인자, `List`) — 4.4 |
| Q2 | V7 고정 자료를 커밋해도 되는가, 생성 커밋은 | 커밋한다. 생성 커밋 = 1차 통합이 `main`에 들어간 커밋(병합 뒤 총괄이 해시를 알림) — 6.12.3, T25a(R2-B2 전) |
| Q3 | PDF 색인 단위·글자 상자 | 쪽 단위 + 글자 상자(PDF 결정), 저장은 CORE-M1(SQLite 밖) — 6.10.3 |
| Q4 | 네이티브 녹음도 `RecordingDraftStore`를 쓰는가 | 행만(조각 0) + 파일 복구 시도(PDF 결정) — 6.7.2 '조각 0 초안은 정상', 5.4 |
| Q5·Q6·Q8·Q9·Q10 | 페이지 복제의 손글씨 결과, 휴지통 노트 녹음, `rebuild(pdf)`, 제목 재계산, `pages` 로컬 열 | 기본값대로 받아들임 — 6.14.3, 6.6, 6.10.5, 6.12.1, 6.11 |
| Q7 | 검색 색인 크기 예산·'PDF 색인 끄기' 설정 | 크기 목표·측정(CORE-M1 — 6.10.7, PF-10), 'PDF 색인 끄기' 설정은 이번에 없음 |
| 검토 Q-1 | 사용자의 1차 실제 노트가 어느 출처에 있는가 | U25(기본: 실제 노트 없음 — Hosting이 없었다) — 6.12.3, 9.5 B-1 |
| 검토 Q-3 | 사각형 저장: 블롭 분리 vs 양자화 | 기본 = SQLite 밖(블롭 저장소), 압축 BLOB도 허용 — 실험으로 블롭 선택(6.10.7) |
| 검토 Q-4 | 안드로이드 태블릿이 있는가 | U2 — 9.5 A는 기기가 생길 때까지 '코드만' |
| Q11 (새) | CP-17은 B2-α 전에, CP-16은 T24 전에 판정해 줄 수 있는가 — CP-17은 B2-α의 공개 선언(`dev_tools.dart`), CP-16은 T24의 사본 구현과 INFRA 안내서·개발자 메뉴 문구에 걸린다 | 기본값: 이 문서대로 한다(CP-17은 추가만이라 다른 영역을 깨지 않고, CP-16은 계약이 허용한 갈래). 거절되면 CP-17 함수를 지우고 INFRA 메뉴를 숨긴다 |
| Q12 (새) | v1 사본 수명 '정상 열기 5번 + 7일'이 적당한가 | 기본값 그대로. 웹은 사본이 블롭 저장소에 있어 열기 메모리는 늘지 않고 저장 공간만 DB 크기만큼 더 든다 |

총괄 답(최종 승인): **Q11** 지금 판정했다 — CP-17·CP-16 모두 승인(위 12.1). 거절 갈래는 쓰지 않는다. **Q12** 기본값 그대로(정상 열기 5번 이상 + 7일).

---

## 13. 검토 반영 내역

수정 1회차(2026-11-05). 기준: 총괄 검토 [00-review.md](00-review.md) 3.2(CORE-M1~M13·질문 답)와 2장 공통 결정(CD2-01~25), 대리 검토 [reviews/core.md](reviews/core.md)(M-1~M-3·S-1~S-17·X-1~X-6·C-1~C-9·Q-1~Q-4), 계약 v2.1(00-overview 7장 — 변경 이력 C21-01~35). 계약 원문 블록(4.1~4.9, 5.1~5.6)은 7장 줄을 스크립트로 그대로 다시 붙였다(손으로 고친 줄 없음 — 13.3).

### 13.1 반드시 고칠 것 (CORE-M1~M13)

| # | 근거 | 무엇을 어떻게 바꿨나 | 위치 |
|---|---|---|---|
| CORE-M1 | 검토 M-1, CD2-11, C21-09·11·25 | ① PDF 글자 상자를 **SQLite 밖**(블롭 저장소 `si/pdf/<assetId>/<pdfPageIndex>/<token>`, 1/65535 uint16 형식 `SearchRectsCodec` ≈ 4 B/글자)으로 옮기고 `search_units.rects` BLOB 열을 없앴다(`rects_ref`·`pdf_aspect`·비pdf 사각형 4열로). 쓰기 순서(블롭 → 행 커밋 → 옛 블롭 삭제)와 고아 블롭 정리를 정했다. ② 질의는 후보에서 `id·source·owner_key·note_id·page_id·asset_id·pdf_index·norm`만 읽고, 판정·점수도 `norm`만으로 하며, **돌려줄 페이지의 일치 단위만** 원문·사각형을 읽는다(사각형 블롭은 묶음 읽기 한 번). ③ 실제 모양 크기를 컨테이너에서 쟀다: 500쪽(쪽당 2,500자) DB가 한국어 7.70 / 혼용 6.67 / 영어 2.82 MiB — float32 BLOB이면 26.98 MiB, uint16 BLOB이면 17.22 MiB라 압축 BLOB(SQLite 안)은 고르지 않았다. 목표(≤ 12 MB·다시 열기 +300 ms)와 넘을 때의 대응(원문도 블롭 → 범위 축소)을 적었다. ④ PF-10(실제 모양 500쪽 고정 자료 — 생성기·시드 고정)·PF-10w(Chrome 저장소 다시 열기 시간, `search_reopen_time_browser_test`)를 T33b에 두었다. ⑤ 9.5 B-13에 'PDF 500쪽 색인 뒤 다시 열기 시간·메모리'. ⑥ 위험 3을 '웹 DB 메모리·열기 시간'으로 넓혔다 | 6.10.3·6.10.4·6.10.7, 6.11, 6.18, 6.19, 8.2 T33a·T33b, 9.5, 11 위험 3 |
| CORE-M2 | 검토 M-2·S-9, CD2-05, C21-29 | R2-B2를 **B2-0(T25a, V7 고정 자료) → B2-α(T22, 공개 선언 전부 + `api_surface_test` v2, 약 0.5세션, 해시 알림) → B2-β(T20a JSON·골든 → T20b 기하·변형 → T21 값 타입·순수 함수 → T23a 해석기·세션 → T23b 가짜 v2·가짜 오디오·픽스처·`testing_web.dart`, 약 2.0세션)**로 나눴다. 'B2 상태' 표를 'α 끝'·'β 끝' 두 열로 다시 쓰고, 조각마다 산출물·완료 조건·세션 추정을 적었다. `main` 병합은 B2 전체 + R2-B7a + R2-B2i 묶음 뒤다. T33을 T33a(쓰기·`rebuild`·`status`·재시도)와 T33b(질의·판정·점수·발췌·사각형·`searchLibrary.pages`·Chrome·perf)로 나눴다. 작업량 합계 18.5 → 20 | 8.1, 8.2, 8.4 |
| CORE-M3 | 검토 M-3, CD2-23, C21-11·33 | ① 업그레이드 트랜잭션 **직전 v1 사본**(6.12.4 새 절): 네이티브는 `VACUUM INTO '<path>-v1-backup.tmp'` → 이름 바꾸기(트랜잭션 안에서 안 됨·대상이 있으면 실패 [확인]), 웹은 **블롭 저장소 정규 덤프**(`db/v1-backup/…`, meta 마지막). 웹이 `VACUUM INTO`가 아닌 이유는 계약의 '안 되면' 갈래 — 웹 VFS 파일 하나를 지울 길이 없어 계약의 자동 삭제를 채우지 못하고(drift 웹 API는 DB 전체 삭제뿐 [확인]), `IndexedDbFileSystem`이 열 때 모든 파일을 메모리로 읽어 사본이 매 열기를 두 배로 만든다 [확인]. 그래서 'T24 첫날 웹 VFS 확인'은 '웹 덤프 사본의 만들기·해시·지우기·다시 열기 시간 확인'으로 바꿨다(CP-16으로 문구 구체화 요청). ② 사본 수명 = 정상 열기 5번 + 7일, kv `db.v1Copy`, 사본 실패는 이주를 막지 않음, 개발자 메뉴 API(`dev_tools.dart` — CP-17). ③ V7에 '사본의 정규 덤프 해시 = manifest `fullDumpSha256`'(VM ④·Chrome ④′), 정규 덤프 형식(SQLite `quote()` — VM·웹 같은 바이트, 실수 왕복 정밀도 [확인])을 정했다. ④ 위험 1·6.12.3·9.5 B-1 문구를 '실제 데이터의 이주는 그 데이터가 있는 출처에 배포될 때 처음 일어난다'로, B-1 절차를 '배포 전 백업 내보내기 → 실제 노트가 있는 출처에 배포 → 첫 실행 → 확인(개발자 메뉴에 v1 사본)'으로 고쳤다 | 6.12.1·6.12.3·6.12.4, 6.15.3, 9.5 B-1·B-c2, 11 위험 1·12, 12.1 CP-16·CP-17 |
| CORE-M4 | 검토 S-3(승격)·S-14, C21-08 | `begin`이 행보다 먼저 블롭 `rd/<draftId>/meta`를 쓰고, `listDrafts`가 행 없는 meta 접두사를 되살리며(`activeMs` 0·`updatedAt = startedAt` — '최근 갱신'으로 영원히 빠지지 않게, 행 다시 씀), 고아 정리는 **행도 meta도 없는** 접두사만 지운다. 6.7.3 내구성 문장을 실제 보장(조각·meta는 IndexedDB 트랜잭션 완료 시 내구, 행은 수 ms 늦을 수 있음 — `IndexedDbFileSystem` '내구성 보장 없음' [확인])으로 정정했다. 빈 조각 `append`가 `active_ms`·`updated_at`을 갱신하고, 조각 0 초안(네이티브 — 행만)은 정상으로 유지한다. `discard` 설명의 '조각 0 초안은 media가 버린다'를 고쳤다. 12.2 Q4 = PDF 답(행만 + 파일 복구) | 6.7.1~6.7.3, 6.8.3, 6.17, 12.2 Q4 |
| CORE-M5 | C21-06·07, CD2-06·07, 검토 S-1·S-17 | 4.4에 v2.1 원문(이름 있는 인자·`const`·`label`, `RemoveElements.elementIds: List`)을 옮기고 CP-1·CP-2 승인을 적었다. `PageObject.transformed(m, {scaleWidth = true})`를 **단일 규칙**으로 6.2.5 표에 정리했다(도형 굵기 × s [0.1, 30] when `scaleWidth`, 텍스트·수식 글자 × s [6, 144], 이미지 frame만, `UnknownObject` 그대로) — 해석기 `TransformElements`는 이것만 부른다(6.4.1). 6.2.1의 '`fromJson`이 접는다' 모순을 '생성자·`fromJson`은 그대로 담고 `normalized()`·`transformed`만 접는다'로 통일하고 `−π`·`3π`·변 0·최대 변 경계값 왕복 시험을 `element_frame_test`에 두었다. `ClearPage`는 1차 생성자에 이름 있는 선택 인자 `this.includeObjects = false`(4.4) | 4.1·4.4, 5.3, 6.2.1·6.2.3·6.2.5, 6.4.1 |
| CORE-M6 | C21-04, C2-38, CP-INK-4, 검토 X-3·C-8 | 6.2.7 새 절: `Stroke.transformed`가 캘리그래피 획의 `nibAngleDeg`(수가 아니거나 없으면 45)에 회전각(도)을 더해 [0, 180)으로 접는다(회전 성분이 0이면 extras 그대로 — 키를 새로 쓰지 않음). 키 문자열은 CORE 내부 상수(1차 `defaultsFor(calligraphy)` extras와 같은 글자)이고 INK `InkStyleExtras.nibAngleDeg`와의 대조는 통합 2단계(8.3 I-1). 해석기가 이미 `style` 키를 기록함을 1차 코드로 확인했다(`command_resolver.dart` 183–186). 시험 `test/edit/calligraphy_transform_test.dart`(`undo_objects_test` 옆 — 순수 부분 T20b, undo 부분 T23a) | 1.5, 2.1 F-03, 5.2, 6.2.7, 6.4.1, 8.1, 11 위험 17 |
| CORE-M7 | C21-09, CD2-12, G-4, 검토 S-10·X-2 | `HandwritingRepository.update`(쓰기 큐 작업 하나 = 한 트랜잭션: 읽기 → 동기 `transform` → 검증·쓰기, `null`이면 쓰지 않음, 예외면 되돌림, `transform` 안 쓰기 API는 `StateError`)와 `notesWithStalePages`(캐시 갱신 뒤 정확한 답, 최근 노트 먼저)를 6.9.3·6.9.4에 넣었다. 공유 계약 본문에 **경합 사례 7개**(연달은 `update`, `put` 직후 `update`, 인식 중 원격 결과 도착 등)를 적었다. `stalePages`는 페이지 순서. S-10: '`points` 열은 읽지 않음' 문장을 'BLOB 뒤 열이라 건너뛰며 읽는다(긴 획만 넘침 페이지)'로 보정하고, 덮개 색인 `idx_strokes_ink`를 실험으로 판단했다 — 10만 획 읽기 121~163 ms vs 덮개 75~104 ms, DB +10.3 MiB [확인] → 웹 DB를 키우므로 넣지 않음. PF-11(10만 획 첫 따라잡기 합계 ≤ 1.5 s [추측]) | 5.5, 6.9.3·6.9.4, 6.17, 6.19, 8.2 T32 |
| CORE-M8 | C21-09·11, CD2-11, 검토 S-6·S-8·S-15·C-5·C-9 | `replaceUnits(…, [])`도 소유자(`sourceRev`)를 남긴다(6.10.3 + `search_index_writer_test`). 후보 상한 2,000은 **최근 단위(rowid 큰 것) 먼저**, 살아 있는 단위만 세고, 가짜도 같은 id 규칙·FTS 후보 흉내(`ftsCandidateMatches` — FTS5와의 동치 무작위 시험)로 같은 집합을 고른다(CP-14 — 상한에 걸릴 때도 같은 결과). `pdfPageAspect`로 contain 변환(CP-3), `PageRect.zero` 글자 건너뜀, pdf `sourceRev`는 꼬리(`:x<ver>`)까지 문자열 그대로 저장·비교(≤ 200자). CP-15 정정은 v2.1 원문 표에 사각형 저장 방식까지 들어갔다. 점수 문구를 'IEEE 754 배정밀도·같은 연산 순서'로 고쳤다 | 4.6, 5.4, 6.10.3~6.10.6, 6.11, 12.1 |
| CORE-M9 | C21-30·05, 검토 X-4, PDF X-6·Q2 | `testing.dart` v2.1 원문(4.9)을 옮기고 6.8.3·6.8.4를 고쳤다: `FakeAudioRecorder.start`가 지원 안 함이면 `UnsupportedError`(v2.0 계획의 `StateError` 정정), 초안을 실제 초안 저장소에 쓰고 일시정지 중 빈 조각, `pendingDrafts` 제외 규칙(진행 중 세션·복구 중·`store.clock` 10초 안 갱신), 저장 실패 시 초안 남김, `abandon()` → 새 녹음기가 10초 뒤 복구(V16 모양), `FakeAudioPlayback.calls` 형식(웹 `double.toString` 차이 안내), 가짜 재생기는 '녹음 중 `play` 무시'를 흉내 내지 않음. idb_shim 메모리 IndexedDB 타이머 때문에 실제 메모리 CORE + `testWidgets`에서 `runAsync`·`pump`가 필요하다는 안내를 EDITOR·INFRA용으로 적었다. **`testing_web.dart`**(`openWebTestNoteStore`·`deleteWebTestNoteStore`)의 이름 규칙·자산 전달(`prepare_web_test.dart --out`)을 정했다 | 4.9, 4.11, 5.7, 5.8, 6.8.3·6.8.4, 6.18.1 |
| CORE-M10 | C21-08 | `pendingDrafts`·`recoverDraft`의 계약 주석을 CORE 쪽 풀이로 6.8.1에 적고(복구 결정은 목록만, 제외 대상의 `recoverDraft`는 가짜에서 `StateError`(media는 PDF가 정함), 저장 실패는 초안 유지), `Unsupported*` 표(CP-7 동작표 — 6.8.2)와 가짜(6.8.3)가 같은 규칙을 따른다. `createRecording` 멱등을 원문대로 '같은 id면 인자와 상관없이 그 행'으로 고쳤다(v2.0 계획은 인자가 다르면 `StateError` — 길이 보정이 다른 복구 재시도를 막을 수 있어 바꿈, 6.20에서도 뺌). `Recording.toJson` `title` 항상(4.5 원문·6.3) | 4.5, 6.6, 6.8.1~6.8.3, 6.20 |
| CORE-M11 | C21-11, 검토 S-2·S-5·S-7·S-16·Q-2 | ① `math`의 `engine` 키 항상(`null`) — 6.3에 종류별 키 고정 규칙, 골든 `math_no_engine.json` 추가(새 골든 9개). ② make-migrations 산출을 `lib/src/storage/db/note_database.steps.dart`로 정정(drift_dev 2.35.2 `make_migrations.dart` 524–525 [확인]) — 3절 트리·원칙·5.7·6.12.1, INFRA `generated_files`에 `*.steps.dart`(7.6.2 R2-B1). 생성 시험 경로 `test/storage/generated_migrations/note_db/`. ③ V7 고정 자료는 **1차 통합이 `main`에 들어간 커밋**으로 **R2-B2 전**(T25a — B2-0)에 생성. ④ Chrome 고정 자료 전달: `prepare_web_test.dart`가 `test/web/fixtures_v1/`로 복사(`.gitignore`), 상대 URL `fetch`. ⑤ T25b 선행에 T35. ⑥ `normalizeForSearch` 위임을 T24로 옮겼다(T34는 `searchLibrary` v2만) | 3, 5.7, 6.3, 6.10.1, 6.12.1·6.12.3, 6.18.1, 8.1, 8.2 |
| CORE-M12 | C21-10·23, 검토 S-13 | ① 네이티브 블롭 루트·하위 디렉터리를 CORE가 만든다(만들 수 없으면 `storageUnavailable` — 시험 추가). ② `UnknownObject.referencedAssets` = 최상위 `assetId`가 에셋 id면 그것(4.3), `page_objects.asset_id`에도(6.11), 모르는 enum으로 `UnknownObject`가 된 이미지도 같음(6.2.6). ③ 부록 B·6.15.3의 'DB·블롭은 백업 대상' 문구를 '안드로이드 자동 백업은 끈다(D20 — `allowBackup="false"`), iOS는 기본, 보존은 백업 내보내기 → 동기화'로 고쳤다 | 4.3, 6.2.6, 6.11, 6.15.3, 부록 A·B |
| CORE-M13 | C21-29, 검토 X-5, SYNC X-4 | 진행 기록 '이정표 커밋' 표 양식을 8.5에 고정했다(V7 고정 자료·B2-α·B2-β JSON·B2-β 끝·T24·T26~T33a·T33b·T35 — 커밋·날짜·되는 것·기다리는 영역). **SYNC R2-B7a의 바탕 = B2-α 해시**, INFRA R2-B2i도 같음(5.6·5.7·8.1) | 5.6, 5.7, 8.1, 8.2, 8.5 |

### 13.2 권장 · 영역 간 · 계약 · 질문 (대리 검토)

| # | 처리 | 위치 |
|---|---|---|
| S-1 | 반영(CORE-M5) | 6.2.1 |
| S-2 | 반영(CORE-M11) | 3, 6.12.1 |
| S-3 | 반영(CORE-M4로 승격) | 6.7 |
| S-4 | 반영: 웹 정지 경로도 `readAll` 한 벌을 든다고 6.7.3 문장을 고치고, 30분 분량(약 14 MB) `readAll` → `put` 시간·메모리를 Chrome 시험이 기록, 위험 8을 '정지·복구 모두'로 | 5.4, 6.7.3, 8.2 T31, 11 위험 8 |
| S-5 | 반영(CORE-M11) | 6.12.3, 6.18.1 |
| S-6 | 반영(CORE-M8) | 6.10.3 |
| S-7 | 반영(CORE-M11) | 6.3 |
| S-8 | 반영(CORE-M8) | 6.10.4·6.10.6 |
| S-9 | 반영(CORE-M2) | 8.2 |
| S-10 | 반영(CORE-M7) — 덮개 색인은 실험 뒤 넣지 않음 | 6.9.3, 6.19 PF-11 |
| S-11 | 반영: 9.5 A-1을 v2.1 원문(고정 키 2차 APK끼리 덮어 설치, 1차 노트 없음 — 1차 셸 `core_module.dart` 216–222 [확인])으로 | 9.5 A-1 |
| S-12 | 반영: 재시도 시점을 C-13 원문('다음 쓰기 트랜잭션 또는 저장소 열기 — 타이머 없음')과 맞추고 남은 보류가 `status.pendingOwners`로 보인다고 적음 | 6.10.5 |
| S-13 | 반영(CORE-M12) | 4.3, 6.11 |
| S-14 | 반영(CORE-M4) | 6.7.2, 12.2 Q4 |
| S-15 | 반영(CORE-M8) | 6.10.4 |
| S-16 | 반영(CORE-M11) | 6.10.1, 6.12.1, 8.2 T24 |
| S-17 | 반영(CORE-M5) | 4.4, 6.4.1 |
| X-1 (PDF) | ① 저장 형식·정밀도(1/65535, SQLite 밖)·지연 읽기 — CORE-M1로 정하고 v2.1 원문(7.2.5 `rects` 주석)과 맞춤 ② 빈 목록 = 소유자 유지 ③ T31을 '실제 초안 저장소 사용 가능' 이정표로(8.5) ④ 조각 0 초안·Q3·Q4·Q8 답 | 5.4, 6.7, 6.10, 8.5, 12.2 |
| X-2 (LIBRARY) | `notesWithStalePages`를 이번에 추가(C21-09) — `pages.ink_rev` 캐시로 한 질의 | 6.9.3 |
| X-3 (INK) | CP-INK-4 동의·구현·시험(CORE-M6) | 6.2.7 |
| X-4 (EDITOR) | CP-1의 `elementIds`는 총괄 결정대로 `List`(검토자 권고 `Set`은 채택 안 됨 — CD2-06, EDITOR 쪽이 `[id]`로 바꿈). idb_shim 시간 진행 안내 | 5.3, 6.8.3 |
| X-5 (SYNC) | `engine` 키 항상(CORE-M11), 이정표 표(CORE-M13). `UnknownObject.toJson` 메타 키 규칙은 CP-4 승인으로 v2.1 원문(4.2) | 4.2, 6.3, 8.5 |
| X-6 (INFRA) | ① `*.steps.dart`(R2-B1) ② 개발자 메뉴 'v1 DB 사본 내보내기·지우기' — CORE 함수(CP-17) ③ 네이티브 두 경로 정적 시험(INFRA 몫 — 5.7에 적음) ④ V5의 가짜 녹음기 + 실제 메모리 CORE 시간 진행 안내 | 5.7, 6.8.3, 6.12.4 |
| C-1 | 총괄 결정: CP-1 승인, `elementIds`는 `List`(C21-07) | 4.4 |
| C-2 | 총괄 결정: 7.6 주석을 CP-14대로(C21-30) — 원문 옮김 | 4.9, 6.10.6 |
| C-3 | '묻지 않고'로 정리(C21-19) — 원문 옮김 | 5.4 |
| C-4 | C-13 문구 정리(C21-19) — 원문 옮김 | 6.10.5 |
| C-5 | 빈 목록·정밀도·`pdfPageAspect` 계약 주석(C21-09) — 원문 옮김 | 4.6 |
| C-6 | A-1·B-1 현실화(C21-33) — 원문을 9.5에 옮김 | 9.5 |
| C-7 | `math.engine` 항상(C21-11) — 원문 옮김 | 4.8, 6.3 |
| C-8 | CP-INK-4 = C2-38(C21-04) — CORE 의견: 동의 | 6.2.7 |
| C-9 | CP-15 정정에 사각형 열 포함(C21-11) — 원문 옮김 | 4.8, 6.11 |
| Q-1 | U25 기본값(실제 노트 없음 — Hosting이 없었다) | 6.12.3, 9.5 B-1 |
| Q-2 | 생성 커밋 = 1차 통합이 `main`에 들어간 커밋, R2-B2 전 | 6.12.3, 8.1 T25a |
| Q-3 | 기본 = SQLite 밖(블롭) — 실험으로 확인 | 6.10.7 |
| Q-4 | U2 | 9.5 A |

### 13.3 계약 v2.1 옮김 · 그 밖에 바꾼 것

- **계약 원문 다시 붙이기**: 4.1(7.2.2 첫 블록)·4.2(결정 문장·나머지 블록·끝 문단)·4.4(7.2.3 블록 둘)·4.5(7.2.4 블록 둘·R 표)·4.6(7.2.5 결정·블록 둘)·4.7(7.2.6 블록·문단)·4.8(7.2.7 전체)·4.9(7.6 CORE 부분 — `testing.dart`·`testing_web.dart`), 5.1(X18~X24)·5.2(K-6·`toCommand` 표)·5.3(명령 매핑 표·E-5·E-6)·5.4(M-1~M-4·`PdfSearchIndexer`)·5.5(G-1·G-2·G-4·`HandwritingIndexer`)·5.6(7.2.8 본문·S-13)을 00-overview의 해당 줄 범위에서 그대로 복사했다(`/tmp/claude-0/plan57-scratch/core57-rev/splice.py`·`splice5.py`). 원문 블록 머리 표기를 `계약 v2.1`로 바꿨다.
- **CORE 확정 세부 블록**: CP-2~CP-8·CP-10·CP-13이 원문에 들어가 겹치는 줄을 지우고, 7장이 02-core를 가리킨 곳(`estimatedBytes` 공식, `Unsupported*` 동작표, `SearchTextMapping` 필드, `copyWith` 인자 목록)만 남겼다.
- **바탕 코드**(CD2-01·C21-02): 머리말을 1차 통합 HEAD(`18c5ae5`, note_core = `4336967` + `c4966ce`)와 시험 수(VM 619·Chrome 47)로 고쳤다. 10절 완료 기준도 같은 기준이다.
- **계약 v2.1의 다른 CORE 몫**: C21-04(C2-05 깨지는 곳 정정 — 1.5), C21-05·C2-39(`testing_web.dart` — 3·4.9·4.11), C21-10(CP-11 로컬 이미지 형식 검사 — 6.15.2), C21-19(M-1 저장 실패 시 초안 유지 — 6.8.1), C21-25(색인 크기 목표 — 6.10.7), C21-32(V7·V10·V16 문구 — 6.12.3·6.10.7·4.9), D17(`FEATURE_MEDIA`는 녹음만 — 5.7).
- **새 계약 변경 제안**: CP-16(7.2.7 사본 방법을 저장 방식별로 구체화 — 웹 = 블롭 정규 덤프, 수명), CP-17(`dev_tools.dart` v1 사본 함수 4개 — INFRA 개발자 메뉴용). 판정 요청은 12.2 Q11·Q12.
- **반영하지 않은 것**: 없음. 다만 검토 M-3의 'T24 첫날 웹 VFS `VACUUM INTO` 확인'은 위 근거(지울 수 없음·열기 두 배 [확인])로 '웹 덤프 사본 확인'으로 바꿨다(CORE-M3 행).

---

## 부록 A. 확장 지점 · 자리 사용표 (개요 6장 13절)

CORE가 **여는** 자리:

| 자리 | 종류 | 채우는 쪽 | 규칙 |
|---|---|---|---|
| `audioRecorderServiceProvider`·`audioPlaybackServiceProvider` | 포트 provider(기본 `Unsupported*`) | media_io `mediaIoOverrides()`만(X28) | 꺼진 기능(D14)이면 override 없음 |
| `SearchIndexWriter`(`NoteStore.search`) | 인터페이스(CORE 구현) | pdf_io `PdfSearchIndexer`가 **부름**(source pdf만) | ink·text·math는 CORE 전용. 빈 목록도 소유자 유지, 글자 상자는 SQLite 밖(6.10.3) |
| `HandwritingRepository`(`NoteStore.handwriting`) | 인터페이스(CORE 구현) | recog `HandwritingIndexer`·변환 창이 부름 — (v2.1) 로컬 쓰기는 `update`만(G-4) | 웹에서는 쓰지 않음(G-1) |
| `RecordingDraftStore`·`RecordingRepository` | 인터페이스(CORE 구현) | media_io가 부름 | M-1 순서 |
| `PageObject`의 `type` | 저장 형식 확장점 | 다음 라운드의 새 종류 | 옛 앱은 `UnknownObject`로 보존(C-12, CP-6) |
| `StrokeStyle.extras` | 저장 형식 확장점 | INK `InkStyleExtras` 키 | CORE는 맵을 그대로 저장 |
| `recordingRepositoryProvider`·`noteRecordingsProvider`·`handwritingRepositoryProvider`·`searchIndexProvider` | 파생 provider | override 없음(7.3.3) | — |
| (v2.1, CP-17) `dev_tools.dart` v1 사본 함수 | 개발자 도구 함수 | INFRA 개발자 메뉴 'v1 DB 사본 내보내기·지우기'가 **부름**(X-6) | 가짜 저장소는 `null`·아무것도 안 함 |
| (v2.1) `testing_web.dart` | 시험 도우미 진입점 | PDF(`media` V8·V16·V11 Chrome)가 **부름** | `test/web/`에서만, 자산은 CORE 준비 스크립트 `--out`(6.18.1) |

CORE가 **채우는** 자리: 없음(CORE는 형제 패키지에 의존하지 않는다).

## 부록 B. 네이티브 · 권한 요구표 (개요 6장 14절)

| 항목 | 요구 |
|---|---|
| 플러그인 | 없음(순수 Dart). `dart:io`는 `*_native.dart`·`testing_vm.dart`·`tool/`에서만 |
| 네이티브 라이브러리 | `sqlite3 3.8.0` 빌드 훅 기본 바이너리(안드로이드·iOS — GitHub 릴리스에서 내려받고 sha256 대조, `SQLITE_ENABLE_FTS5`). CI(`android.yml`·`ios-compile.yml`)에서 내려받기가 막히지 않아야 한다(INFRA) |
| 경로 | `NoteStoreConfig.nativeDatabasePath`·`nativeAssetDirectoryPath` — 앱 지원 디렉터리 아래(INFRA `path_provider`, `*_native.dart`). 두 경로는 같은 볼륨이어야 한다(임시 파일 `rename`은 같은 디렉터리 안에서만 — 6.15.3). (v2.1) 디렉터리가 없으면 CORE가 만든다 — INFRA는 경로만 넘긴다(C21-10). v1 사본은 DB 파일 옆 `<nativeDatabasePath>-v1-backup`(6.12.4) |
| 권한 | 없음(앱 전용 디렉터리) |
| 백업 대상 | (v2.1 정정, D20 — C21-23) **안드로이드 자동 백업은 끈다**(`android:allowBackup="false"` — INFRA 매니페스트: 25 MB 상한, 실행 중 파일 복사 불일치, 다른 기기로 복원할 때 기기 식별·HLC 노드 id 복제가 동기화 전제와 충돌). iOS는 기본값(앱 지원 디렉터리가 iCloud 백업에 들어감 — 실연결 미니 라운드에서 다시 본다). 노트 보존 수단은 백업 내보내기(1차) → 실연결 뒤 동기화(U27). 기기 로컬 파생 데이터(색인)·초안·v1 사본은 같은 저장소 안이라 iOS 백업에서 따로 빼지 않는다 |
| iOS 배포 대상·minSdk | 영향 없음(INFRA 값 그대로) |
| 웹 | `sqlite3.wasm`·`drift_worker.js`(1차 7.4.9 그대로), IndexedDB `noteapp_blobs`(초안 조각 포함) |
