# 00 · 총괄 관리자 검토 결과

> 상태: 1차 검토 완료 (2026-11-04) · 대상: 01~07 계획서 초안 · 확정한 공통 결정: [00-overview.md 7장 '통합 계약' v1.0](00-overview.md#7-통합-계약)
> 판정 기준: ① 이 계획서들만 보고 서로 다른 개발자가 독립적으로 구현했을 때 통합이 깨지지 않는가 ② PLAN.md 요구사항이 빠짐없이 구현되는가 ③ 컨테이너와 iPad Safari 웹에서 검증 가능한가

---

## 1. 전체 평가

**판정: 7개 계획서 모두 '수정 후 재검토'.** 계획서 각각의 깊이는 높다. 수치·알고리즘·작업별 완료 테스트가 구체적이고, 실험으로 확인한 사실(웹 포인터 이벤트 소스, CanvasKit 강제, drift 웹 저장 방식, PDFium 합성 탐침, 가짜 Firestore 동작 등)이 많아 단독으로는 그대로 구현할 수 있는 수준이다.

문제는 **영역 사이**다. INK·EDITOR는 CORE 계획을 보지 못한 채 CORE 타입을 각자 가정했고, 그 결과 같은 개념이 2~3벌 생겼다. 그대로 동시 개발하면 통합 때 다시 써야 하는 범위가 크다.

| 판정 기준 | 평가 | 주된 원인 |
|---|---|---|
| ① 독립 구현 후 통합 | **불충분** | 획·점·펜 스타일·배경·명령이 CORE/INK/EDITOR에 세 벌. 점의 두 번째 채널 의미 충돌(원시 필압 vs 굽힌 굵기 계수). EDITOR 세션·INK 어댑터 포트가 실제 API와 다름. 배경 확장 지점 두 곳. 썸네일 생산자 없음. SYNC가 차단으로 표시한 필드 버전이 CORE에 없음. provider·타입 이름 충돌. |
| ② PLAN 요구사항 | **대체로 충족, 일부 누락** | 표지 썸네일(F-01), 악보·플래너 속지(F-13), 다중 선택 일괄 내보내기(F-01), 원격 에셋 받기(F-07), 저장 경고 표시 담당, 설정 화면 구성·계정 섹션 담당, M4 전 백업(12장) |
| ③ 컨테이너·웹 검증 | **대체로 충족, 실행 경로 수정 필요** | `test 1.33.0`·`build_runner 2.17.1`로는 워크스페이스 해석 실패, 브라우저 테스트 디렉터리·준비 스크립트가 영역마다 다름, `MaterialUiCompatibilityBridge`가 deprecated라 `--fatal-infos` 실패, 웹 메모리 합계 예산 없음 |

이번 검토에서 총괄이 직접 확인한 것

- 00-overview 7.5 표 그대로(정확한 버전, 모든 멤버 `environment.flutter: 3.47.9`, `test 1.31.1`, `build_runner 2.16.1`, 앱은 `sync_engine` 미의존)의 7개 멤버 + 루트 pubspec으로 `flutter pub get` 해석 성공. 해석 결과 `analyzer 13.3.0`, `test_api 0.7.12`, `meta 1.19.0`, `vector_math 2.4.4`(`/tmp/claude-0/plan-scratch/lead/ws`).
- 순수 Dart 멤버(`note_core`, flutter 의존 없음)에 `environment.flutter: 3.47.9`를 두고 `flutter test` 실행 성공. `package:riverpod/misc.dart`가 `Override`를 export함.
- `material_ui-1.10.0/lib/src/migration_utility.dart`의 `MaterialUiCompatibilityBridge`는 클래스·생성자 모두 `@Deprecated`.
- Flutter SDK `flutter_test`는 `test_api: 0.7.12`, `flutter`는 `meta: ^1.18.3`으로 고정(→ `test` 1.31.1, `meta` 1.19.0이 맞음).

수정 규모 예상: EDITOR·INK 큼(포트·타입 교체) / CORE 중간(계약 확장, 대부분 추가) / SYNC·PDF·INFRA 중간~작음 / LIBRARY 작음.

---

## 2. 공통 결정 요약 (상세: 00-overview 7장)

| # | 결정 | 7장 |
|---|---|---|
| CD-01 | 패키지 7개·의존 방향은 초안 그대로. `note_core`는 순수 Dart, `sync_engine`은 주 라이브러리만 순수 Dart. 앱은 이번 범위에서 `sync_engine`에 의존하지 않는다(M4 연결 때 추가) | 7.1 |
| CD-02 | 한 개념 = 한 소유 패키지. 공개 export 이름 충돌 금지(통합 시 R14 검사). 중복 정의 정리표(19개 개념) | 7.2.0 |
| CD-03 | 공유 데이터 타입(획·점·펜 스타일·배경·속지·페이지 크기·명령·세션·저장소·동기화 창구·에셋·썸네일 인터페이스·동기화 표시 상태)은 전부 CORE 소유 | 7.2.1 |
| CD-04 | 점의 두 번째 채널 = **굽힌 굵기 계수 `widthQ`**(원시 필압 저장 안 함). `r = 2·width·widthQ`, 코덱 bit0 = hasWidthQ, 기본 0.25, `t` = `createdAt` 기준 ms(조각은 유지) | 7.2.3 |
| CD-05 | `Stroke.bounds` = 점 경계 + `width · max(2·maxWidthQ, 0.75)`(CORE 계산, 직렬화 안 함). INK는 렌더 외곽이 그 안에 있음을 테스트로 보장 | 7.2.3, 7.3.2 |
| CD-06 | 펜 스타일 = CORE `StrokeStyle`/`PenTool`/`PressureCurve.evaluate`. 기본값·곡선 상수는 INK 표. `pressureSensitivity` 기본 1.0(=INK 프로필 게인 배율), 투명도 하한 0.05, 알파 0xFF. 형광펜 직선 보정은 `extras['hlStraight']`. 전역 필압 곡선 설정 없음(활성 펜 스타일이 기준) | 7.2.4 |
| CD-07 | 기본 프리셋 = 결정적 ID `preset-default-<tool>` + 한국어 이름(CORE) + 시드 HLC `Hlc(1,0,'0'×16)` | 7.2.4 |
| CD-08 | 속지 = CORE `PageTemplate`(매개변수 nullable → INK 기본값, 선 색 null = 종이 밝기 자동). 기본 수치는 INK 6.16이 단일 출처. **6종 모두 이번에 INK가 그린다** | 7.2.5, 7.8 |
| CD-09 | 종이 색 4종(INK 값), 페이지 크기 프리셋(A4·Letter·16:9 세로형)·사용자 입력 한계 100~3000pt를 CORE에 둔다 | 7.2.5 |
| CD-10 | 편집 명령은 CORE `EditCommand` 하나. INK `InkEdit.toCommand()`가 매핑(표). 부분 지우개 누적은 INK `EraserSession`만(CORE·EDITOR 것 삭제) | 7.2.7, 7.2.15 |
| CD-11 | EDITOR는 CORE `NoteSession`을 직접 쓴다(포트·낙관적 표시층 삭제). CORE `execute`는 동기 반영 + 동기 스트림 전달을 보장 | 7.2.8 |
| CD-12 | EDITOR는 INK `InkPageController`/`InkPageView`를 직접 쓴다(InkAdapter 삭제). 기반 단계 INK 스텁은 '단순하지만 동작하는 구현'이라 EDITOR 테스트가 첫날부터 가능 | 7.2.15, 7.6 B3 |
| CD-13 | 입력 정규화·필압 감지·필압 모드는 INK 단일 소유. EDITOR는 설정값을 `pressureModeProvider.notifier.set()`으로 넣는다 | 7.2.15 |
| CD-14 | 배경 확장 지점은 INK `PageBackgroundLayerBuilder` 하나(+ 선택 `PageBackgroundStillRenderer`, `isThumbnail`). 빌더 목록 override는 `pdfIoOverrides()`만 | 7.2.16, 7.3.3 |
| CD-15 | 썸네일: CORE `PageThumbnailRenderer` 인터페이스 → INK 구현 → INFRA 주입 → LIBRARY 표지 예약, PDF 가져오기 표지. EDITOR 캐시 쓰기는 선택 | 7.2.11 |
| CD-16 | 화면용 동기화 상태는 CORE `SyncDisplayState`·`SyncBadge`·`syncBadgeProvider`(기본 off). SYNC 풍부한 상태는 SYNC 안에. M4에 INFRA가 연결 | 7.2.13 |
| CD-17 | SYNC R1~R12 전부 수용: 필드별 HLC(`field_versions` 열), 버전 포함 병합 정책, `readVersioned`, `pendingChanges(afterSeq)`, `commitRepairs`, 메타 KV, `reassignOwner` 런타임 전환(이번 범위 구현), `duplicateNoteForRecovery`, outbox 힌트·`storagePath` 기록 | 7.2.10 |
| CD-18 | LWW 판정은 HLC, 증분 커서는 서버 시각. 24시간 넘게 앞선 원격 HLC는 적용하지 않고 격리 | 7.2.10 |
| CD-19 | 원격 에셋: CORE `AssetStore.bytesArrived` + `RemoteAssetFetcher`(SYNC 구현, M4 주입). PDF는 원본 없음 → 요청·재시도 | 7.2.11 |
| CD-20 | 앱 시작: INFRA는 CORE `openNoteStore`를 그대로 감싼다. 오류 분류 `NoteStoreOpenException`, 초기화 `deleteLocalNoteData`. 웹 `persist()`·`estimate()`는 CORE만 | 7.2.12 |
| CD-21 | 라우트·화면 계약은 INFRA 형태: `/notes/:noteId?page=`, `EditorScreen(noteId, initialPageId, onClose, onOpenSettings)`. 라이브러리 두 경로는 같은 페이지 키·무전환, 에디터는 무전환 | 7.2.17, 7.3.3 |
| CD-22 | 피처 간 연결은 소비자가 정의한 자리 + 앱 셸 override. override 소유표 하나, 중복은 스모크 테스트가 잡는다. 패키지 내부 하위 scope는 자기 provider만 | 7.3.3, 7.4.4 |
| CD-23 | 설정 화면은 INFRA 틀 + 섹션 조립(EDITOR 4 · LIBRARY 새 노트 기본값 · INFRA 저장 공간·앱 정보 · M4 계정). 로그인 화면·동기화 알림도 INFRA. 저장 경고 배너는 LIBRARY·EDITOR(조건 함수 CORE) | 7.4.5, 7.4.11 |
| CD-24 | Material = `material_ui` 1.10.0 단독, `MaterialUiCompatibilityBridge` 미사용 | 7.4.2, 7.4.3 |
| CD-25 | 설정 키는 각 영역이 CORE `SettingKey`로 선언. 기기별 값 = device, 사용자 취향 = synced | 7.4.6 |
| CD-26 | 테스트: 브라우저 테스트는 `test/web/` 한 곳 + 패키지별 `tool/prepare_web_test.dart`, 골든은 VM 전용 `test/goldens/`, iPad 13" 1032×1376, 테스트 코드 네트워크 금지(빌드 훅 다운로드는 허용·캐시) | 7.4.8 |
| CD-27 | 웹: COOP/COEP 없음, CanvasKit, 정적 파일 2개(`sqlite3.wasm`, `drift_worker.js`), 앱 관리 캐시 합계 ≤ 300MB(영역별 웹 예산) | 7.4.9, 7.4.10 |
| CD-28 | 외부 패키지 버전 고정표(해석 확인됨). `test 1.31.1`, `build_runner 2.16.1`, `meta 1.19.0`, `go_router 18.1.2` | 7.5 |
| CD-29 | 기반 단계 B1~B8(파일 경로·담당), CORE `createFakeNoteStore()` 포함 | 7.6 |
| CD-30 | 통합 순서 CORE → INK → 피처 4개 → INFRA → 통합 태그 테스트 → iPad, 검증 기준 V1~V7 | 7.7 |
| CD-31 | 범위: 악보·플래너·일괄 PDF 내보내기 포함, 전역 PDF 텍스트 검색·다른 노트 페이지 복사 이후, 백업 내보내기는 M4 연결 전 선행 | 7.8 |

검토자 의견 중 바꿔 채택한 것: ① 펜별 팽창 계수 표 대신 `widthQ` 기반 고정 공식(CD-05) ② 악보·플래너는 'UI에서 숨김' 대신 INK가 그림(PLAN F-13 P0) ③ EDITOR 얇은 어댑터 유지 대신 어댑터 삭제 + 동작하는 INK 스텁 ④ 웹 래스터 타일을 끄는 대신 512px 타일로 시작해 iPad 실측(INK S1) ⑤ persist 요청은 CORE 단일 소유.

---

## 3. 영역별 피드백

표기: **M** = 필수 수정(재검토 승인 조건) · **S** = 권장 수정 · **O** = 선택. '근거' 열은 해당 계획서의 절 번호.

### 3.1 INFRA — `01-infra.md` · 판정: 수정 후 재검토

워크스페이스·검사 규칙·CI·웹 배포 설계는 확인한 사실이 많고 그대로 쓸 수 있다. 수정은 다른 영역과의 연결부(CORE 시작 계약, 모듈 연결, 테스트 실행 방식)에 집중된다.

**필수 수정**

| # | 근거 | 문제 | 고치는 방법 |
|---|---|---|---|
| INFRA-M1 | 5.1, 4.5.9, 5.7, 6.7 | CORE 시작 계약을 `openNoteCore`/`NoteCoreHandle`/`NoteCoreOpenException`으로 가정 — CORE에는 없음 | 7.2.12로 교체: `CoreModule({Future<NoteStore> Function(NoteStoreConfig) open = openNoteStore})`, `start`에서 `NoteStore` publish, `overrides()` = `[noteStoreProvider.overrideWithValue(store)]`, `onAppHidden()` = `store.flush()`(500ms), `stop()` = `store.close()`. 6.7 문구 표를 `NoteStoreOpenFailure` 기준으로(`newerSchema` → "앱을 새로고침해 최신 버전을 받아 주세요"). `onResetLocalData` = `deleteLocalNoteData(config)`. 5.7 `FakeNoteCoreHandle` 삭제 → CORE `createFakeNoteStore()` |
| INFRA-M2 | 4.5.9, 8.2 I10, 8.3 G2 | 다른 영역이 기대하는 override·어댑터(썸네일 렌더러, PDF 가져오기·내보내기 자리, 에디터 메뉴, 개발자 표시 섹션)를 만드는 작업이 없음 | `FeatureWiringModule`(정적 override 모듈)을 4.5.9에 추가하고 7.3.3 표 그대로 구현. `productionModules()` = core → pdf → featureWiring. PDF 시작 실패 시 PDF 관련 override 생략(`AppModuleContext`로 성공 여부 전달). `PdfMenuAction` → `EditorMenuItem` 변환 함수(`EditorMenuContext` → `PdfMenuInvocation`, `onNavigate: m.navigateToPage`)와 PDF 렌더 통계 `DevOverlaySection` 변환을 이 모듈에. 작업 ID(예: I10b)와 테스트(`feature_wiring_module_test.dart`: override 목록, PDF 실패 시 생략) 추가. G2 스모크는 7.7 V5 그대로 |
| INFRA-M3 | 4.4, 6.3, 9.1 `note_app_test` | `MaterialUiCompatibilityBridge`는 deprecated → `flutter analyze --fatal-infos`(F8·10장 기준) 실패. 이번 범위에 SDK Material을 쓰는 외부 패키지도 없음 | 위젯 트리에서 뺀다. `note_app_test`는 브리지가 **없음**을 확인. 4.4 위젯 트리 설명 수정. 나중에 필요해지면 7.4.2 절차(ignore + 사유 + 승인) |
| INFRA-M4 | 4.1, 4.2, 6.13 | `ws test --platform chrome`이 `flutter test --platform chrome test/web`만 실행 → CORE(`sqlite3.wasm`·`drift_worker.js` 준비)·PDF(pdfrx 자산 준비, `test/browser/`) 브라우저 테스트가 CI에서 실패하거나 실행되지 않음. 4.1 '테스트에서 네트워크 금지'와 빌드 훅 다운로드 충돌 | 7.4.8대로: chrome 실행 전 멤버에 `tool/prepare_web_test.dart`가 있으면 먼저 실행, 대상 디렉터리는 `test/web/` 하나, `CHROME_EXECUTABLE` 처리. 4.1 문구를 "테스트 코드는 네트워크 금지, 빌드 훅·준비 스크립트 다운로드는 허용"으로. `ci.yml`에 `.dart_tool/hooks_runner`·준비 산출물 캐시(키 = `pubspec.lock` 해시). `integration` 태그는 기본 skip, 통합 단계에 `ws test --run-skipped -t integration`(옵션 추가) |
| INFRA-M5 | 3.3, 4.3, 6.2 | `pinned_external`이 5개뿐(같은 문제가 다시 생김), CORE `testing_vm.dart`가 R4에 걸림, 순수 Dart 멤버의 R2 처리 미정, 앱이 `sync_engine`에 의존 | `pinned_external` = 7.5 표 전부. `workspace_rules.yaml`에 `lib_exceptions: [packages/note_core/lib/testing_vm.dart]`, R6은 `lib/`에만 적용. 3.3: `note_core` 골격은 순수 Dart(`flutter` 의존 없음, `environment.flutter`는 유지, dev `test: 1.31.1`). 3.3·3.4·7.1 앱 의존에서 `sync_engine` 제거(M4에 추가) |
| INFRA-M6 | 4.5.8, 5.2, 6.8, 1.4 | 설정 화면 섹션 목록이 'EDITOR 섹션 + 앱 정보'뿐 — LIBRARY '새 노트 기본값', 저장 공간, M4 계정 섹션이 빠짐. 5.2의 `EditorSettingsSection`(1개)·`featureEditorOverrides` 가정이 EDITOR와 다름 | `settingsSectionsProvider` 기본값 = [EDITOR 입력·펜·페이지 넘김·개발자 표시 4종, LIBRARY `LibrarySettingsSection`(일반 › 새 노트 기본값), INFRA 저장 공간·앱 정보], M4에 계정·동기화(INFRA가 SYNC API로 작성). 5.2를 7.2.17로 교체 |
| INFRA-M7 | 6.6, 4.5.5 | `/notes/:noteId`의 페이지 종류 미정(네이티브 iOS에서 `MaterialPage`는 가장자리 스와이프 뒤로가기가 펜 획을 가로챔). `/`와 `/folders/:id`가 다른 페이지면 폴더 이동마다 화면이 새로 만들어지고 미끄러짐(LIBRARY I-2) | `/notes/:noteId` = `NoTransitionPage`. `/`·`/folders/:folderId` = 같은 `ValueKey('library')`의 `NoTransitionPage`(또는 `ShellRoute`). `app_router_test`에 "폴더 이동 시 `LibraryScreen` State 유지" 추가 |

**권장 수정**

| # | 근거 | 내용 |
|---|---|---|
| INFRA-S1 | 4.5.2, 6.4, 4.5.3 | `WebPlatform.requestPersistentStorage/estimateStorage` 삭제(CORE 단일 소유). `StartupReport.persistence`·`DiagnosticReport` 저장소 줄은 `storageInfoProvider`/`refreshStorageInfo()` 값으로 |
| INFRA-S2 | 6.13, 8.1 F8 | CI 시간 예산은 추정치. B8(F8)에서 첫 CI 실행 시간·`main.dart.js` 크기·Chrome 첫 `openNoteStore` 시간을 재고 예산표 갱신 |
| INFRA-S3 | 6.2 | R14(공개 export 이름 충돌) 검사를 통합 단계에 추가(`package:analyzer` export namespace 비교, root dev 의존 `analyzer: 13.3.0` 고정) |
| INFRA-S4 | 3.4, 6.12, 6.16 | M4 대비: `app/firebase.json`이 `../packages/sync_engine/firebase/{firestore.rules, storage.rules, firestore.indexes.json}`을 참조하는 형태를 문서화하고(연결은 M4), `hosting_config_test`가 참조 파일 존재 확인. 안내서 04에 "미리보기 주소의 데이터·로그인은 따로(임시)", 안내서 01에 Firestore `asia-northeast3`·Storage US 리전 권장(사용자 선택, 미확인 표시)과 `authDomain` |
| INFRA-S5 | 6.9 | EDITOR 5.3 #5(a) 답: 엔진이 `contextmenu`를 이미 막으므로 `BrowserContextMenu.disableContextMenu()`는 쓰지 않는다고 근거와 함께 명시 |
| INFRA-S6 | 4.5.8 | 앱 정보에 '백업 내보내기' 버튼(CORE `exportBackupJson()` → 웹 다운로드). M4 실연결 전 선행 조건(PLAN 12장) |
| INFRA-S7 | 6.4 | 부트스트랩 `ownerId`: CORE에 저장된 소유자가 우선(첫 로그인 후 `reassignOwner`). `AppModuleContext.ownerId`는 새 DB 생성 때만 의미 |

**선택**

| # | 내용 |
|---|---|
| INFRA-O1 | INK ink lab(`packages/ink_engine/example`)을 INK가 만들면 워크스페이스 멤버 등록 + `web-experiment.yml`에 `target` 입력(`app`/`ink_lab`) |

**질문 답변**

| Q | 답 |
|---|---|
| Q1 | 확정. 모든 패키지 `material_ui`만, SDK Material 금지(R7). 브리지 미사용(INFRA-M3) |
| Q2 | 확정. 루트 `.gitignore`·`pubspec.lock`·`.gitattributes`는 INFRA 소유. 패키지별 `.gitignore`는 각 영역 소유 허용. `firebase.json`은 `app/` 안 |
| Q3 | 맞다. 단 기반 단계 경계를 7.6 B1~B8로 고정(CORE·INK·PDF·EDITOR·LIBRARY·SYNC가 각자 계약 표면을 커밋, INFRA가 B1·B8) |
| Q4 | 예. 7.5 표의 모든 외부 의존을 B1에서 넣는다 |
| Q5 | `note_core` 순수 Dart, `sync_engine`은 Flutter 패키지(주 라이브러리는 순수 Dart). 둘 다 `environment.flutter: 3.47.9` |
| Q6 | 분담은 CD-23. 에디터 `onOpenSettings`는 둔다(선택 콜백, 더보기 '설정') |
| Q7 | CORE 형태로 확정(INFRA-M1, 7.2.12) |
| Q8 | COOP/COEP 불필요(CORE는 헤더 없이 `sharedIndexedDb`, PDF V13). 정적 파일은 `sqlite3.wasm`·`drift_worker.js` 2개(7.4.9) |
| Q9 | CORE 인터페이스가 아니라 LIBRARY 자리(`libraryPdfImportActionProvider`) + PDF 함수 + 앱 셸 override(흐름에 `BuildContext` 필요) |
| Q10 | 이후. 필요해지면 `note_core`에 타입 + provider(제안대로) |
| Q11 | 넣었다(7.4.4, 7.4.5) |
| Q12 | '필기노트', `dev.noteapp.noteapp`은 자리표시로 진행. 네이티브 전환 전 사용자 결정(4장) |
| Q13 | 체크포인트·통합 때만 푸시(7.4.12) |
| Q14 | 동의. PLAN.md M0 문구 수정은 총괄이 PLAN 갱신 때 반영(5장) |
| Q15 | 생성 파일 커밋, CI는 build_runner 안 돌림(7.4.7) |
| Q16 | 맞다. 상세 순서·기준은 7.7 |

### 3.2 CORE — `02-core.md` · 판정: 수정 후 재검토

데이터 모델·HLC·분수 인덱스·outbox·되돌리기 별칭·drift 웹 연결은 이번 계획서 묶음의 중심이 될 만큼 탄탄하다. 수정은 ① 다른 영역과 의미가 갈린 타입(점·펜 스타일·속지) ② SYNC가 차단으로 요청한 동기화 창구 확장 ③ 새 공유 인터페이스 추가다. 동기화 창구는 4.6을 7.2.10으로 **교체**한다.

**필수 수정**

| # | 근거 | 문제 | 고치는 방법 |
|---|---|---|---|
| CORE-M1 | 4.2 `stroke_points`·`stroke`, 6.2.4, 6.2.5, 5.2 K-1 | 점 채널이 '원시 필압(기본 0.5)'인데 INK는 '굽힌 굵기 계수 q'로 해석 → 필압 없는 획이 굵기 2배, 연필 기울기 시 렌더가 `bounds`(width) 밖으로 나감 | 7.2.3 그대로: `widthQ`(기본 `kNominalWidthQ` 0.25), `kMaxWidthFactor` 4, `StrokePoints.fromInterleaved`, `maxWidthQ`, `hasPressure` 제거, 코덱 bit0 = hasWidthQ(쓰기는 항상 1, 없으면 0.25), `t` = `createdAt` 기준(조각 유지), `bounds` = `pointBounds.inflate(width·max(2·maxWidthQ, 0.75))`. 6.2.4 골든 2건 다시 계산(flags 0 예시는 widthQ 없음 → 읽을 때 0.25), `StrokeFixtures`는 widthQ 생성. T2·T3 테스트 갱신 |
| CORE-M2 | 4.2 `pen_style`, 6.2.2, 6.2.3 | 기본값·곡선 상수·감도 의미가 INK와 다름(볼펜 0.8 vs 1.6pt 등, `soft` 값 다름, 감도 0.5 vs 1.0), 투명도 하한 없음 | 7.2.4로: 기본값 표 교체(INK 6.9 값), `pressureSensitivity` 기본 1.0(INK 게인 배율), `minOpacity` 0.05, `normalized()`가 색 알파를 0xFF로, `PressureCurve.soft/firm` = INK 값. 기본 프리셋: 결정적 ID·한국어 이름·`sortKey a0~a4`·시드 HLC `Hlc(1,0,'0'×16)`(6.2.2 갱신) |
| CORE-M3 | 4.2 `page`, 6.2.6 | `PageTemplate.spacing` 필수·`lineColorArgb` 기본값 고정 → INK의 '종이 밝기 자동 선 색'이 동작 안 함(LIBRARY Q13), 종이 색 값이 INK·EDITOR와 다름, extras 키 이름 불일치(`cueWidth`), 페이지 크기 한계가 3곳 | `PageTemplate` 매개변수 nullable + `defaults(kind)` = `PageTemplate(kind: kind)`, `TemplateExtrasKeys`, `PaperColors`(INK 값 + `all`·`luminance`·`isDark`), `PageSizePreset`·`PageSizeLimits` 추가. 6.2.6 속지 수치 표는 삭제하고 "INK 03-ink 6.16이 단일 출처"로 |
| CORE-M4 | 4.3 `erase_session`, 6.7.5, 8 T11 | `StrokeEraseSession`이 INK `EraserSession`·EDITOR 것과 3중(EDITOR 것과 이름도 겹침) | 공개 API에서 삭제(INK가 제스처 1회를 `SplitStrokes`/`RemoveStrokes` 하나로 만든다). `erase_session_test`의 "5획 절단 → 1 command → undo 1회" 검증은 `command_resolution_test`·`undo_chain_test`로 옮김 |
| CORE-M5 | 4.6, 6.10, 6.11, 1.3, 8 T14 | SYNC 차단 요청(R1·R2 필드 버전, R4 `commitRepairs`, R3·R5·R6·R8·R9·R11) 미반영 → `CoreSyncLocalStore` 구현 불가, 6.3.4 반례(서로 다른 필드 동시 수정)에서 영구 불일치. `reassignOwner` 구현이 M4로 미뤄져 SYNC T16 실패 | 4.6을 7.2.10으로 교체. 스키마: 엔티티 테이블마다 `field_versions` TEXT NULL 열(`version` = max). 로컬 쓰기는 `changedFields`만 새 HLC, `*`는 전체. `applyRemote`는 정책 결과의 버전을 그대로 쓴다(재스탬프 금지), `WriteMerged`면 outbox 필드를 정확히 `fieldsToUpload`로. `reassignOwner`는 **이번 범위에 구현**(행 갱신 + `kv['store.ownerId']` 영속 + 런타임 전환, 1.3 문구 수정). 원격 적용 시 영향 노트의 로컬 `updatedAt` = max(현재, 적용값)(outbox 없음). T14 테스트 추가: 6.3.4 반례 수렴, `entity.version == versions.max` 불변식, `afterSeq`, `commitRepairs`가 히스토리 밖·outbox 기록, `reassignOwner` 후 다시 열어도 새 소유자, `duplicateNoteForRecovery`(휴지통 원본), 메타 KV 원자성 |
| CORE-M6 | 4.7, 4.8, 4.9 | 다른 영역이 쓸 공유 인터페이스가 없음: id·시계 provider(INK·EDITOR), 썸네일 렌더러 자리(LIBRARY·INK), 동기화 표시 상태(LIBRARY·EDITOR·SYNC), 원격 에셋 hook·도착 스트림(PDF·SYNC), 저장 경고 조건 | 7.2.11~7.2.14 추가: `NoteStore.ids`·`clock`, `idGeneratorProvider`·`clockProvider`, `PageThumbnailRenderer`·`pageThumbnailRendererProvider`, `SyncDisplayState`·`SyncBadge`·`syncBadgeProvider`, `RemoteAssetFetcher`·`RemoteAssetState`·`RemoteAssetProgress`·`remoteAssetFetcherProvider`, `AssetStore.bytesArrived`, `StorageWarning`·`storageWarningOf`. T4 `api_surface_test`에 포함 |
| CORE-M7 | 4.1, 4.8, 5.1, 6.12 | 앱 시작 오류가 `StorageUnavailableException` 하나라 시작 화면이 원인을 구분 못함, 데이터 초기화 수단 없음, persist를 INFRA·CORE가 둘 다 요청 | `NoteStoreOpenFailure`·`NoteStoreOpenException`(7.2.2), `deleteLocalNoteData(config)`. `StorageUnavailableException` 삭제. 열 때 `persist()`는 최대 1초 기다리고 결과를 `StorageInfo.persistGranted`에. `NoteStoreConfig.ownerId`는 새 DB 생성 때만, 저장된 소유자 우선. 5.1 I-6 문구 갱신 |
| CORE-M8 | 3, 3.1, 7.1 | `test 1.33.0`은 Flutter `test_api 0.7.12` 고정과 충돌(해석 실패), `build_runner 2.17.1`은 `test 1.31.1`과 analyzer 범위 충돌. 패키지 `analysis_options.yaml`(R3 위반), `connect_web`·`persistence_web`·`content_hasher_web/_vm`(R5 위반), `testing_vm.dart`(R4) | pubspec: `test: 1.31.1`, `build_runner: 2.16.1`(`drift_dev 2.35.2` 유지), `environment.flutter: 3.47.9`. `analysis_options.yaml` 삭제(`*.g.dart` exclude는 루트에 이미 있음). 파일 이름 `_browser.dart`·`_native.dart`로(7.4.3). `testing_vm.dart`는 R4 예외 목록(INFRA). 준비 스크립트 이름 `tool/prepare_web_test.dart`, 복사 자산은 패키지 `.gitignore`. 7.3에 `build_runner 2.16.1`로 코드 생성 재확인 기록 |
| CORE-M9 | 6.3, 9.1 | 웹(dart2js)은 `jsonEncode(1.0)` = `"1"` → `fromJson`이 `FormatException`, JSON 골든 바이트 비교가 브라우저에서 깨짐(SYNC R10) | 모든 실수 필드 `(v as num).toDouble()`. JSON 골든은 `@TestOn('vm')`. 웹 형식(정수로 된 실수) 입력 디코드 테스트를 VM·Chrome 둘 다 |
| CORE-M10 | 4.4, 6.1, 6.14, 6.16 | EDITOR가 의존할 세션 의미(동기 반영·동기 이벤트·순서·읽기 전용·`markOpened`)가 문장으로만 있고 테스트가 없음 | 7.2.8 N-1~N-7을 4.4 문서 주석으로 옮기고 `note_session_test`에 "`execute` 반환 전에 `pageChanges` 리스너가 호출됨", "`pages`/`history` 즉시 갱신" 테스트 추가. 세션 스트림은 동기 broadcast 컨트롤러 |
| CORE-M11 | 8, 12 Q1 | 기반 단계 범위 미정 → LIBRARY·SYNC·EDITOR가 값 타입·가짜를 직접 만들거나 착수 지연 | 7.6 B2를 8장 맨 앞에 명시: T1~T4(동작 구현 포함) + T5 `createFakeNoteStore()`(라이브러리·휴지통·프리셋·설정·세션 execute/undo/redo·동기 `pageChanges`·썸네일 캐시·에셋 메모리). T5의 "outbox 없음"은 유지 가능(SYNC 계약 테스트는 통합 단계에 `openTestNoteStore`로) |
| CORE-M12 | 5.2, 5.3 | INK·EDITOR에 대한 기대(K-1 width 기준, E-2 `StrokeEraseSession`, E-6 EDITOR 썸네일 필수, E-7)가 새 계약과 다름 | 5.2·5.3을 7.3.2·7.2.11로 다시 씀(K-1 = 새 bounds 공식, E-2 삭제, E-6 = 선택, E-7 = EDITOR 개발자 표시가 `StorageInfo`·`lastCommitLatency` 표시) |

**권장 수정**

| # | 근거 | 내용 |
|---|---|---|
| CORE-S1 | 4.5, 4.2 | LIBRARY·EDITOR 요청 반영: `NoteContentReader.getPage`, `LibraryRepository.reorderItems`, `FolderTree.folders`, `PenPresetRepository.reorderPresets(orderedIds)`, `SettingKey.stringList/jsonMap`, `Stroke.copyWith(id:)`, `NoteStore.refreshStorageInfo()` (모두 7.2에 계약으로 들어감 — 구현은 T8·T12·T3) |
| CORE-S2 | 6.7.4 | `HistoryLimits.platformDefault`: 웹 32 MiB, 그 외 64 MiB(7.4.10 메모리 예산) |
| CORE-S3 | 1.3, 2.2 | `Future<Uint8List> exportBackupJson()`(활성·휴지통 엔티티 전체 JSON + 에셋 메타, 바이트 제외). PLAN 12장 'M4 전 백업 내보내기'의 선행 조건 |
| CORE-S4 | 6.8, 11 | 검색 정규화(`name_norm`)에 한글 조합형 자모 합성(U+1100~U+11C2 → 음절, PDF 6.10.1 4단계와 같은 규칙)을 넣는다. macOS·iOS 파일 이름 유래 제목은 NFD일 수 있음 |
| CORE-S5 | 5.1, 9.2 | Chrome 첫 `openNoteStore`(빈 DB / 획 1만 개) 시간을 재서 기록 → INFRA 시작 시간 제한 20초 근거 |

**질문 답변**

| Q | 답 |
|---|---|
| Q1 | 넣는다. CORE가 B2로 작성: T1~T4(동작 구현 포함) + `createFakeNoteStore()` |
| Q2 | M0~M3 헤더 없음(`sharedIndexedDb`). OPFS는 실험 채널에서만 |
| Q3 | 확정. `openNoteStore` + override, 숨김 시 `flush()`, 웹 자산 2개 복사·검증 스크립트는 INFRA |
| Q4 | (a) 공식 `max(2·maxWidthQ, 0.75)·width`로 해결, INK가 불변식 테스트 (b) 입력 시점 적용(스무딩된 점 + 굽힌 굵기 저장) (c) 기본값은 INK 6.9, 속지는 INK 6.16 |
| Q5 | 라이브러리 화면 LIBRARY, 에디터 화면 EDITOR. 조건은 CORE `storageWarningOf` 하나 |
| Q6 | CD-15. LIBRARY 예약 + INK 렌더러로 한 번도 열지 않은 노트도 표지가 생긴다 |
| Q7 | (a)~(d) 승인 + SYNC R1~R12(7.2.10). (e) LWW = HLC, 커서 = 서버 시각 |
| Q8 | 이번 범위 정리 없음. 이후 방향: 모든 기기 커서 최솟값보다 오래된 삭제 표시만, 90일 미접속 기기 제외(SYNC Q15) |
| Q9 | 이후 범위(전역 PDF 텍스트 검색). 그때 CORE 테이블 + FTS5로 하고 `sqlite3.wasm`의 FTS5 포함 여부를 먼저 확인 |
| Q10 | 확정. 각 영역이 `<영역>.` 접두사로 선언, CORE는 저장만. 전역 필압 곡선·보정 설정은 두지 않음(CD-06) |
| Q11 | 기기 로컬 |
| Q12 | CORE가 한국어 이름으로 넣는다(사용자 데이터라 UI 문구가 아님) |
| Q13 | 최소 1장 규칙 유지(`LastPageDeletionException`), EDITOR가 버튼 비활성 |
| Q14 | 확인됨. INFRA·INK·EDITOR·LIBRARY scratch에서 웹 빌드·Chrome 테스트 통과 |

### 3.3 INK — `03-ink.md` · 판정: 수정 후 재검토

입력 근거(웹 엔진 소스), 1€ 필터, 굽힌 굵기 계수, 외곽선·부분 지우개 기하, 형광펜 합성, 캐시 설계는 우수하다. 굵기 계수 저장(R1)·packed 점(R2)·z 순서(R3)·`t` 기준(R4)·알파 규칙(R6)·불변(R7)·명령 단위(R8)는 **채택**했다. R5(INK bounds 저장), R9(프리셋에 불투명 JSON), R10(문자열 속지 id)은 채택하지 않았다. 수정은 CORE 타입 사용과 공개 API 정리다.

**필수 수정**

| # | 근거 | 문제 | 고치는 방법 |
|---|---|---|---|
| INK-M1 | 5.1, 5.2, 6.23, T09 | CORE를 가정한 타입(`StrokeTool`, `BoundingBox`, `DateTime createdAt`, 가정 명령 4종, `PenPreset.pressureCurve` 맵, 문자열 속지)이 실제 CORE와 다름 | 5.1을 7.2.3~7.2.7·7.2.14 이름으로 다시 쓴다. `core_interop`: `InkPoints.fromRaw(stroke.points.rawData)`(채널 [2] = `widthQ`), 획 생성 = `core.Stroke(points: StrokePoints.fromInterleaved(...), createdAt: 펜 다운 nowMillis)`, bounds는 CORE 값. `InkCoreServices{newStrokeId, nowMillis}`. 5.2 표의 R5·R9·R10을 '철회'로, 나머지는 '채택'으로 갱신 |
| INK-M2 | 4.0, 4.1, 4.2, 4.10 | CORE와 겹치는 공개 타입(`PenStyle`, `PressureCurve`, `PaperColors`, `PageTemplateKind`, `PageTemplateSpec`, `InkTool`, `EraserFilter`, `kNominalQ`·`kMaxWidthFactor`) | 공개 export에서 삭제. 세션·미리보기·프로필은 `core.StrokeStyle`/`core.PenTool`을 받는다. `StrokeStyleInk` 확장(`profile`, `previewRadius`, `highlighterStraightening`, `withHighlighterStraightening`)과 `InkStyleExtras.highlighterStraightening = 'hlStraight'` 추가. `inkParamsToJson`/`fromPreset` 삭제. P1 도구는 ballpoint 프로필로 대체 렌더. 내부 전용 타입은 `src/`에 두고 export하지 않음 |
| INK-M3 | 4.6, 4.8, 6.19~6.23 | `InkEdit.toCommand()`가 없는 CORE 명령을 만듦, before/after 획 목록 방식이 CORE `TransformElements(Affine2)`와 다름, `clearPage`가 EDITOR 경로와 중복, 변형 굵기 한계 [0.05, 100]이 CORE [0.1, 30]과 다름 | `InkEdit` 형태와 매핑 표를 7.2.15로. `InkPageController.clearPage` 삭제(EDITOR가 `core.ClearPage` 실행). 부분 지우개 조각 = `core.Stroke.fragment`(createdAt·t 유지). `InkAffine` → `core.Affine2` 변환 함수. 6.22·6.28 `widthMinPt/widthMaxPt` = 0.1/30. T09 `ink_edit_test`를 새 표로 |
| INK-M4 | 4.10, 6.16, 6.17, 1.3, T13 | 배경 확장 지점에 썸네일 표시·화면 밖 렌더 경로 없음(PDF Q13), 속지가 문자열 id 기반, 악보·플래너 미지원(PLAN F-13 P0) | 7.2.16으로: `InkBackgroundSpec.template: core.PageTemplate?`, `PageBackgroundContext.isThumbnail`, `PageBackgroundStillRenderer`(선택 인터페이스, `TemplateBackgroundLayerBuilder`도 구현), `TemplateVectors.build(core.PageTemplate, …)`. 6.16 기본값 표를 모든 `TemplateExtrasKeys`로 확장(단일 출처). **악보(오선 5줄, `staffGap`)·플래너(`layout: 'weekly'`) 렌더 추가** — 새 작업 T13b(`template_vectors_test` 확장 + 골든 2종 × 흰/검정). 1.3의 '악보·플래너 이후' 삭제 |
| INK-M5 | 4.9, T20 | `InkThumbnailRenderer`는 `ui.Image`만 내고 CORE `PageThumbnail`(PNG·revision)을 만들지 않음, PDF 배경을 화면 밖에서 그릴 수 없음 | `InkPageThumbnailRenderer implements core.PageThumbnailRenderer` + `inkPageThumbnailRendererProvider`(7.2.16). PDF·이미지 배경은 `PageBackgroundStillRenderer`, `null`이면 결과 `null`. T20에 테스트: PNG 디코드 가능·긴 변 ≤ `maxSidePx`·`contentRevision` 복사·`SolidBackgroundBuilder`가 still renderer일 때 합성 |
| INK-M6 | 4.3, 4.13, 6.4 | `pressureModeProvider`가 단순 `Provider`라 EDITOR가 값을 넣으려면 다른 패키지 provider를 override해야 함. EDITOR도 별도 감지 규칙을 둠 | `NotifierProvider<PressureModeNotifier, PressureMode>`(`set()`). 감지 규칙은 6.4 하나만 계약(EDITOR 규칙 폐기). `pressureCapabilityProvider`를 EDITOR 개발자 표시·설정 섹션이 읽는다고 4.13 표에 명시 |
| INK-M7 | 6.7, 6.9, 9.1 | CORE 계약 K-1(렌더 외곽 ⊆ bounds) 검증 테스트 없음 — 연필은 기울기로 f가 4까지 | `unit/model/bounds_invariant_test.dart`: 5종 × (최대 필압·최대 기울기·taper·점 획) 외곽선 다각형 ⊆ `core.Stroke.bounds`(허용 0.01pt) |
| INK-M8 | 3, 5.5, 7, 9.1 | pubspec R2·R9 위반(`flutter: ">=3.47.0"`, `meta: ^1.18.3`), 패키지 `analysis_options.yaml`, `ink_clock_web.dart`(R5), chrome에서 `test/unit` 실행(INFRA 실행기와 다름), 골든 디렉터리 이름 | `meta: 1.19.0`, `environment.flutter: 3.47.9`, `analysis_options.yaml` 삭제, `ink_clock_browser.dart`. Chrome은 `test/web/`만(웹에서 다시 돌릴 결정성 테스트는 `test/web/`에 감쌈). 골든은 `test/goldens/` |
| INK-M9 | 4.15 | 기반 단계 스텁이 '동작 없음'(`end()`가 `null`) → EDITOR가 동시 개발 중 펜·지우개·올가미 흐름을 테스트할 수 없음 | 7.6 B3대로 '단순하지만 동작하는 구현'으로 4.15 표를 고침(세션이 `InkEdit`를 돌려주고 `toCommand()` 동작, `InkPageView`는 폴리라인) |

**권장 수정**

| # | 근거 | 내용 |
|---|---|---|
| INK-S1 | 4.9 `InkRenderConfig`, 6.13, 6.14 | 웹 기본값: `outlineBudgetBytes` 32MB, `rasterBudgetBytes` 96MB, `chunkSizePt` 128(타일 ≤ 512px — CanvasKit `toImageSync`는 끊을 수 없는 동기 GPU→CPU 읽기). 개발자 표시에 `lastTileRasterMs` p95, iPad에서 8ms를 넘으면 웹은 `rasterTiles: false`로 바꾸는 조건을 11장에 |
| INK-S2 | 4.14, Q9 | `package:ink_engine/dev_tools.dart`에 `InkDevTools.syntheticStrokes`(CORE `Stroke` 목록, 결정적) — EDITOR 개발자 메뉴 '합성 획 N개'(`testing.dart`는 앱 코드에서 import 금지라 분리) |
| INK-S3 | 9.3 | iPad 확인 추가: ⑮ 형광펜 가장자리를 작은 부분 지우개로 스치기(폭 전체가 잘려 보이는지 기록) ⑯ 7.7 V7 복합 메모리 시나리오 |
| INK-S4 | 4.7, 6.22 | `SelectionGeometry`가 선택 변형 수학의 유일한 구현임을 명시(EDITOR는 핸들 적중 판정만). 수치(배율 0.05~20, 최소 4pt)는 계약 |
| INK-S5 | 6.21 | 올가미 포함 규칙(중심선 길이 비율 ≥ 0.5, nonzero)을 4.7 문서 주석에 계약으로 |

**선택**

| # | 내용 |
|---|---|
| INK-O1 | T23 ink lab: 만들면 INFRA가 멤버 등록·실험 채널 배포(INFRA-O1). M0 확인을 EDITOR 통합 전에 할 수 있어 가치가 있음 |

**질문 답변**

| Q | 답 |
|---|---|
| Q1 | 예. 이름은 `widthQ`(CORE 7.2.3). 원시 필압은 저장하지 않고 개발자 표시에서만 |
| Q2 | 예. `StrokePoints.rawData` stride 6 = `[x, y, widthQ, tilt, azimuth, t]` |
| Q3 | `createdAt` → `id`. 조각은 원본 `createdAt`·`t` 유지 |
| Q4 | 아니요. 감도·곡선은 `StrokeStyle`의 정식 필드, 직선 보정은 `extras['hlStraight']`(기본 `off`) |
| Q5 | CORE `EditCommand` 이름을 쓴다(매핑 7.2.15). `idGeneratorProvider`·`clockProvider`는 CORE가 추가 |
| Q6 | 아니요. 타입이 있는 `TemplateBackground(PageTemplate)`. 사용자 지정 매개변수는 `PageTemplate` 필드·`extras` |
| Q7 | 5.3 동의. 지우개 크기는 **pt**로 저장·전달(EDITOR Q14) |
| Q8 | 예 |
| Q9 | 예. `InkDevTools`(INK-S2) |
| Q10 | 기록한다(INFRA-S2, 기반 단계 B8) |
| Q11 | 선택(INK-O1, INFRA-O1) |
| Q12 | 예. Chrome은 `test/web/`만, 골든 VM, 벤치마크 제외 |
| Q13 | CanvasKit 기준(dart2js 기본 빌드) |
| Q14 | 예 + `isThumbnail`, `PageBackgroundStillRenderer` |
| Q15 | 예(PDF V5·V6로 확인) |
| Q16 | LIBRARY는 `note_core`만. 썸네일은 CORE 자리 + INK 렌더러(CD-15) |
| Q17 | 예 |

### 3.4 EDITOR — `04-editor.md` · 판정: 수정 후 재검토 (수정 규모 가장 큼)

입력 분배 상태 기계(R1~R32), 팜 리젝션의 웹 한계 정리, 뷰포트·가상화, 색 피커·굵기 매핑, iPad 체크리스트는 좋다. 그러나 CORE·INK를 보지 못한 채 만든 포트(`NoteEditSession`, `InkAdapter`, `EditorPreferencesStore`)와 가정 타입이 실제 API와 달라 **5절과 6.4·6.7·6.13·6.14를 크게 다시 써야 한다.** 포트를 고치는 대신 CORE·INK API를 직접 쓰는 쪽으로 정했다(CD-11·CD-12) — CORE `execute`가 동기 반영을 보장하므로 낙관적 표시층이 필요 없고, INK 스텁이 동작하므로 가짜 어댑터도 필요 없다.

**필수 수정**

| # | 근거 | 문제 | 고치는 방법 |
|---|---|---|---|
| EDITOR-M1 | 5.1.1~5.1.5, 4.3, 4.10, 6.13.2, E-01 | `NoteEditSession`·`NoteEditSessionFactory`·`PageContentHandle`·`NotePage`·`StrokeTransform`·`PageSpec`·`PageInsertPosition`·`HistoryStepResult`·`NoteNotFoundException`을 가정 — CORE에 없음, 어댑터 소유자도 없음 | CORE `NoteSession`을 직접 사용. `editorSessionProvider` = `ref.watch(core.noteSessionProvider(noteId).future)`. 5.1에 매핑 표: 획 추가·지우개·올가미 = INK `edit.toCommand()` → `session.execute`, 붙여넣기 = `AddStrokes`, 페이지 전체 지우기 = `ClearPage(pageId, filter)`, 페이지 추가 = `executeAsync(InsertPages([PageDraft(size, background)], PageBefore/PageAfter/PageAtEnd))` → `receipt.edit.insertedPageIds.first`, 복제 = `executeAsync(DuplicatePages([id]))`, 삭제 = `DeletePages([id])`, 이동 `(id, toIndex)` = `MovePages([id], toIndex == 0 ? PageAtStart() : PageAfter(나머지[toIndex − 1]))`, 되돌리기 = `UndoRedoResult.affectedPageIds`(노트 순서 첫 페이지), 저장 오류 = `persistenceStatusProvider`, 노트 없음 = `EntityNotFoundException`, 읽기 전용 = `isReadOnly` 안내·도구 끔. 가짜는 CORE `createFakeNoteStore()`. `testing.dart`의 가짜 3종 삭제 |
| EDITOR-M2 | 4.6, 5.2, 6.4.2~6.4.4, 6.6.3~6.6.8, 6.7, E-04·E-21 | `InkAdapter` 포트가 INK 실제 구조(페이지별 컨트롤러·세션·`InkPageView`)와 다름. `PageOverrides`·자체 레이어 합성이 INK pending·합성과 중복. INK 진단 값이 0으로 남음 | `InkAdapter`·`LiveStrokeHandle`·`StrokeEraseSession`·`InkEngineAdapter`·`FakeInkAdapter` 삭제. 페이지 = `InkPageView(controller: ref.watch(ink.inkPageControllerProvider(pageId)), ancestorScale, isScaling, visiblePageRect)`, 내용은 CORE `pageChanges` → `controller.updateContent(InkPageContent.fromCore(...))`. EDITOR가 그리는 것은 선택 프레임·핸들·커서·메뉴만(올가미 경로는 INK 오버레이). `PageOverrides`·`PageContentRegistry` 삭제. 스포이드 = `controller.hitTest`, 붙여넣기 = `AddStrokes` 후 `controller.select(ids)`. E-21은 "실제 INK + CORE 메모리 저장소 스모크"로 |
| EDITOR-M3 | 6.5.7, 4.8, 6.13.2 | 필압 정규화·감지를 INK와 따로 구현(규칙도 다름), `PressureMode` 값이 다름(`always/never`) | `PointerNormalizer`·`PressureCapabilityDetector`·EDITOR `PressureMode`/`PressureCapability`/`pressureCapabilityProvider` 삭제. 샘플은 `ink.InkSampleAdapter.fromPointerEvent`. `EditorSettings.pressureMode: ink.PressureMode`(JSON `auto`·`alwaysReal`·`alwaysSimulated`, 옛 `always`/`never`도 읽음). `EditorSettingsNotifier`가 로드·변경 때 `ink.pressureModeProvider.notifier.set()`. 감지 상태 표시는 `ink.pressureCapabilityProvider` |
| EDITOR-M4 | 3 pubspec, 6.16, 7, Q15 | SDK `package:flutter/material.dart` 사용, `material_ui` 없음 → R7 위반, go_router 전환·Theme 탐색 불일치 | `material_ui: 1.10.0` 의존, lib·test 전부 `package:material_ui/material_ui.dart`. `no_platform_imports_test`에 SDK Material 금지 추가 |
| EDITOR-M5 | 4.1~4.5 | 공개 API가 INFRA·PDF 계약과 다름: `EditorRoute`, `onExit`, 포트 provider 7개, `EditorMenuContext.session`, 선택 페이지·이동 콜백 없음 | 7.2.17로: `EditorScreen(noteId, initialPageId, onClose(필수, flush 후), onOpenSettings)`, `EditorRoute` 삭제(경로는 INFRA `AppRoutes`), 포트 provider 삭제(`stylusExtrasProvider`·`editorExtensionsProvider`만 유지), `EditorMenuContext`에 `selectedPageIds`·`navigateToPage` 추가·`session` 제거, `DevOverlaySection`·`devOverlaySectionsProvider` 추가, `featureEditorOverrides()` |
| EDITOR-M6 | 4.4, 5.1.6, 6.14 | 설정이 자체 포트(기본 메모리)라 어댑터가 없으면 새로고침 때 사라지고, 키별 동기화 범위를 정할 수 없음 | CORE `SettingsRepository` + `SettingKey.jsonMap`으로 직접 저장. 6.14 표를 7.4.6 기준으로 나눔: device(입력 모드·팜 리젝션·필압 모드·`stylusSeen`·개발자 표시·뷰포트·프리셋 바 필터), synced(펜 종류별 스타일·지우개·최근 색·팔레트·제스처·페이지 넘김). 키 이름은 `editor.` 접두사로 EDITOR가 정함 |
| EDITOR-M7 | 5.1.1, 5.1.5, 6.6.1, 6.9, 6.10, 6.11, 6.13.2 | 가정 타입·자체 기본값·자체 프리셋 순서·자체 페이지 크기/색 표, 이름 충돌(`penPresetsProvider`·`historyStateProvider`·`penPresetRepositoryProvider`·`PageThumbnail`·`SelectionHandle`·`EraserMode`·`EraserTarget`) | `core.StrokeStyle`/`core.PenTool`, 기본값 = `StrokeStyle.defaultsFor`(6.6.1 표 삭제), `ToolState.penStyles: Map<PenTool, StrokeStyle>`. 프리셋은 CORE 저장소 메서드(`watchPresets`·`createPreset`·`updatePreset`·`deletePreset`·`reorderPresets`), `PresetOrdering`은 전체 id 순서를 만들어 `reorderPresets`. 이름 입력 1~20자. 페이지 크기·한계·종이 색은 CORE(`PageSizePreset`·`PageSizeLimits`·`PaperColors`), 속지 선택지 = 빈 페이지 + 6종. 지우개 = `ink.EraserMode` + `core.StrokeFilter`, 크기 pt. provider는 CORE 것 사용(노트별 브리지가 필요하면 `editorHistoryProvider`), 위젯 `PagePanelThumbnail`, `ink.SelectionHandle`·`SelectionGeometry` |
| EDITOR-M8 | 3 pubspec | R2·R9·R3 위반(`flutter: ">=3.47.0"`, `collection ^`, `meta ^`, `fake_async ^`, 패키지 `analysis_options.yaml`) | 7.4.1 형식, `collection: 1.19.1`, `meta: 1.19.0`, `fake_async: 1.3.3`, `environment.flutter: 3.47.9`, `analysis_options.yaml` 삭제 |
| EDITOR-M9 | 6.11, E-17, 4.5 | PDF '선택한 페이지 내보내기'·'PDF에서 찾기' 결과 이동이 불가능(페이지 다중 선택·이동 콜백 없음) | 페이지 패널에 선택 모드(다중 선택, 노트 순서 유지) → `selectedPageIds`. `navigateToPage(pageId, focusRectPt)` = `jumpToPage` + 해당 사각형이 보이게 스크롤. E-17에 작업·테스트(`page_panel_selection_test`, `navigate_to_page_test`) 추가 |
| EDITOR-M10 | 6.12, E-19 | 지연·입력 Hz·필압을 INK와 따로 측정(측정 지점이 달라 수치가 엇갈림), 다른 영역 값(CORE 저장 지연, PDF 렌더 통계)을 넣을 자리 없음 | 지연·입력 Hz·필압·프레임 p95·캐시 = `ink.inkDiagnosticsProvider`(오버레이가 보일 때 `enabled = true`). `DevMetrics`는 포인터 종류·팜 거부 수·뷰포트·페이지 획 수만. CORE `StorageInfo`·`PersistenceStatus.lastCommitLatency` 줄, `devOverlaySectionsProvider` 섹션 표시. 6.12 화면 예시 갱신 |

**권장 수정**

| # | 근거 | 내용 |
|---|---|---|
| EDITOR-S1 | 6.12 | 개발자 메뉴: '합성 노트 만들기'(CORE `seedSyntheticNote`), '현재 페이지에 합성 획 1,000/3,000개'(`InkDevTools.syntheticStrokes` → `AddStrokes`) — CORE E-7·INK Q9 |
| EDITOR-S2 | 6.17 | 에디터 저장 경고 배너(`storageWarningOf`, LIBRARY와 같은 문구) |
| EDITOR-S3 | 6.9.3, 4.9, 2.1 F-03 | 펜 팝업 '고급'에 필압 곡선 선택(부드럽게·보통·단단하게 = `soft`·`linear`·`firm`)과 형광펜 직선 보정(끔·뗄 때 보정·항상 직선, 형광펜일 때만). `EditorPenSettingsSection`은 활성 펜 종류의 같은 값을 편집 |
| EDITOR-S4 | 9.1 `pumpEditor` | 기본 크기를 13" **1032×1376**으로(2048×2732는 12.9" 값). LIBRARY와 같은 값(7.4.8) |
| EDITOR-S5 | 9.2 A9 | 'Safari 탭에서 왼쪽 가장자리 스와이프 없음'은 웹에서 보장 불가 → 홈 화면 앱(standalone)에서 합격, 탭 모드는 기록만. "뒤로 가기가 일어나도 노트를 다시 열면 위치·내용 복원"(A21 연계) 항목 추가 |
| EDITOR-S6 | 1.3, 4.5 | 툴바에 `core.syncBadgeProvider` 작은 아이콘(`off`면 숨김). `appBarTrailing`은 예약만 |
| EDITOR-S7 | 6.11 | 페이지 패널 썸네일: 신선한 `pageThumbnailProvider` 이미지가 있으면 그것, 없으면 `ink.InkPageThumbnail`. 캐시 쓰기는 선택(CD-15) |
| EDITOR-S8 | E-18, Q13 | 좌우 넘기기는 이번 범위·마지막 순위. 통합 단계로 밀려도 M1 합격 전 완료 |

**질문 답변**

| Q | 답 |
|---|---|
| Q1 | CORE 세션은 'execute(동기) + Stream + `receipt.persisted`' 형태이고 #1·#2를 보장한다(7.2.8 N-1·N-2). EDITOR가 이 형태를 직접 쓴다 |
| Q2 | 예, CORE `StrokeStyle`. 필압 곡선은 제어점 곡선(`PressureCurve`), 감도는 0~1 스칼라 — 둘 다 있다 |
| Q3 | CORE `PenPreset`에 `pinned`(기본 true)·`group`(nullable) 이미 있음 |
| Q4 | `extras['hlStraight']` + INK `StrokeStyleInk` 접근자. EDITOR 토글 추가(EDITOR-S3) |
| Q5 | INFRA(설정 화면 틀·조립). EDITOR는 섹션 4개 |
| Q6 | LIBRARY `library.newNote.defaults`(synced) + `LibrarySettingsSection`. EDITOR 페이지 추가 기본값은 '현재 페이지와 같게' 그대로 |
| Q7 | CORE 설정 저장소를 EDITOR가 직접 사용(어댑터 없음). device/synced 구분(EDITOR-M6) |
| Q8 | 빈 페이지·속지·PDF 모두 INK `PageBackgroundLayerBuilder` 목록, 합성은 INK `InkPageView`. EDITOR는 위 오버레이만 |
| Q9 | INK 규칙(중심선 길이 비율 ≥ 0.5, nonzero) |
| Q10 | 표지·캐시 썸네일은 CORE 자리 + INK 렌더러. 페이지 패널은 INK `InkPageThumbnail` 위젯(EDITOR-S7) |
| Q11 | 무전환 에디터 라우트·index.html 대책 수용(INFRA-M7, 01-infra 6.9). `disableContextMenu()`는 불필요(엔진이 막음) |
| Q12 | `auto` 동의(펜을 보기 전엔 손가락 필기, 본 뒤엔 펜 전용) |
| Q13 | 이번 범위, 마지막 순위(EDITOR-S8) |
| Q14 | 동의: 기본 부분 지우개, 크기 단위 pt |
| Q15 | `flutter_riverpod` 3.4.3 정확 고정·코드 생성 없음은 동의. Material은 **`material_ui` 1.10.0**(EDITOR-M4) |
| Q16 | 획 id는 INK 세션이 `InkCoreServices.newStrokeId`(= CORE `idGeneratorProvider`)로. 붙여넣기 id는 `idGeneratorProvider` |
| Q17 | 예. M0 프로토타입 = EDITOR `EditorScreen` + INK, INFRA 기반 단계는 자리표시만 |
| Q18 | 예, 모두 각 1단계 |

### 3.5 LIBRARY — `05-library.md` · 판정: 수정 후 재검토 (수정 규모 작음)

01~04 초안을 읽고 이름을 맞춘 덕에 계약 충돌이 가장 적다. 썸네일 렌더러 자리·PDF 가져오기 자리·CORE 동작 기대(C-1~C-10)·드래그 앤 드롭 실험 결과는 그대로 채택했다.

**필수 수정**

| # | 근거 | 문제 | 고치는 방법 |
|---|---|---|---|
| LIBRARY-M1 | 5.1.2(b), 6.16, L9 | CORE에 `SyncStatus`·`SyncPhase`·`syncStatusProvider`를 제안 — SYNC의 같은 이름 타입과 충돌, EDITOR와 표시 방식 불일치 | `core.syncBadgeProvider`·`SyncBadge`·`SyncDisplayState`(7.2.13)로 교체. 6.16 표: `off` → '이 기기에 저장', `done` → '동기화됨', `inProgress` → '동기화 중'(`pendingChanges > 0`이면 '· n'), `offline` → '오프라인', `error` → '동기화 오류'(툴팁은 일반 문구, `issueCode`로 세분은 M4) |
| LIBRARY-M2 | 6.12, 4.5, L3·L12 | 페이지 크기 한계(50~1000mm)·종이 색·16:9 값이 CORE·EDITOR와 다름 | `NewNoteOptions`는 `core.PageSizePreset`·`PageSizeLimits`·`PaperColors` 사용. 사용자 지정 mm 입력 범위 = 100~3000pt 환산(35.3~1058.3mm, 소수 1자리), 오류 문구도 이 범위. 16:9 세로 540×960. 속지 7칸 유지(INK가 6종 모두 그림) |
| LIBRARY-M3 | 5.1.1, 5.1.2(a)(c)(d), 5.2, 5.3 | 5절 가정이 확정 계약과 조금씩 다름: `InkPageThumbnailRenderer()` 직접 생성 예시, `getPage`·`reorderItems`·`FolderTree.folders` 대체 경로, 기반 단계 요청 | 5.2 예시를 7.3.3 표로(`pageThumbnailRendererProvider`는 INFRA가 `inkPageThumbnailRendererProvider`로 연결 — LIBRARY는 CORE 자리만 읽음). (c1)~(c3)은 CORE가 제공 → 대체 경로 삭제하거나 '없을 때'를 지움. (d)는 7.6 B2로 충족 |

**권장 수정**

| # | 근거 | 내용 |
|---|---|---|
| LIBRARY-S1 | 4.2, 4.3, 6.12 | `markOpened` 직접 호출 삭제 — CORE `openSession`이 부른다(7.2.8 N-6, 중복 쓰기 방지). `onOpenNote` 문서 주석 수정 |
| LIBRARY-S2 | 1.3, 6.9, Q12 | 일괄 PDF 내보내기: `LibraryPdfExportAction`·`libraryPdfExportActionProvider` 자리(7.2.18), 선택 막대 '내보내기' 버튼(자리가 null이면 숨김), 작업 L18에 테스트 |
| LIBRARY-S3 | 6.16 | `StorageWarningBanner` 조건을 `core.storageWarningOf`로 |
| LIBRARY-S4 | 5.7, D-L8 | `FakeLibraryBackend`는 유지해도 되나 CORE 값 타입을 그대로 쓰고, 가능하면 `createFakeNoteStore()` 위에 실패·지연 주입만 얹는다. L21(실제 CORE 계약 테스트)은 필수 |
| LIBRARY-S5 | 6.3.4 | `expandedFolders` = `SettingKey.stringList`, `newNoteDefaults` = `SettingKey.jsonMap` + `NewNoteOptions.fromJson` |

**선택**

| # | 내용 |
|---|---|
| LIBRARY-O1 | PDF 노트 표지를 '원본 도착' 후 다시 그리기: `AssetStore.bytesArrived` 수신 시 해당 에셋을 첫 페이지 배경으로 쓰는 노트의 `_checked`를 비움(첫 페이지 조회 비용이 있으므로 선택) |

**질문 답변**

| Q | 답 |
|---|---|
| Q1 | 확정(CD-15). PDF 배경 합성은 PDF가 `PageBackgroundStillRenderer`를 구현하고 INK 렌더러가 사용 |
| Q2 | 상태 타입은 CORE `SyncBadge`, 두 화면이 직접 그림(LIBRARY-M1, EDITOR-S6) |
| Q3 | 승인. LIBRARY 자리 + PDF `importPdfAsNewNote` + 앱 셸 override |
| Q4 | 넣었다(INFRA-M7) |
| Q5 | 승인. 설정 화면 '일반'에 `LibrarySettingsSection` |
| Q6 | CORE에 `PageSizePreset`·`PageSizeLimits`(LIBRARY-M2) |
| Q7 | 라이브러리 화면 LIBRARY, 에디터 EDITOR, 조건 함수 CORE |
| Q8 | 아니요. CORE `openSession`이 `markOpened`를 부르므로 LIBRARY·EDITOR 모두 부르지 않는다 |
| Q9 | 예(7.6 B2: 동작 구현 + `createFakeNoteStore()`) |
| Q10 | C-1~C-10 승인, (c1)~(c3) 모두 CORE가 제공 |
| Q11 | 기기 로컬에 동의 |
| Q12 | 이번 범위(LIBRARY-S2, PDF-S3) |
| Q13 | INK가 종이 밝기로 정함(CORE `lineColorArgb` null = 자동) |
| Q14 | 동의 |
| Q15 | 해요체 통일(7.4.5) |

### 3.6 PDF — `06-pdf.md` · 판정: 수정 후 재검토

후보 엔진을 실제로 비교해 PDFium 합성으로 정한 근거(V1~V16), 웹 합성 워커, 배율 버킷·타일·예산, 한글 정규화가 매우 좋다. INK 확장 지점을 기준으로 설계한 방향이 최종 계약과 같다. 수정은 확정된 INK·CORE 이름 반영과 테스트 배치다.

**필수 수정**

| # | 근거 | 문제 | 고치는 방법 |
|---|---|---|---|
| PDF-M1 | 4.7, 5.2, 6.8, 6.9, 6.11.8 | INK 계약 가정이 최종과 다름: `PageBackgroundStillRenderer`가 '추가되면', `isThumbnail` 없음, `PageTemplateSpec.resolved`·`TemplateVectors.build(spec…)` 형태 | 7.2.16 반영: `PdfBackgroundLayerBuilder implements ink.PageBackgroundLayerBuilder, ink.PageBackgroundStillRenderer`(조건 문구 삭제), `usesThumbnailMode`에 `ctx.isThumbnail` 포함, 속지 underlay = `TemplateVectors.build(page.background.template, pageSize:, paperColorArgb:)`(INK가 6종 모두 낸다 → K-6의 '빈 목록' 문구 삭제) |
| PDF-M2 | 3, 9.1, 10, T2·T3·T14·T16·T18 | 브라우저 테스트 디렉터리 `test/browser/`, 준비 스크립트 `tool/prepare_test_assets.dart` — INFRA 실행기(`test/web/` + `tool/prepare_web_test.dart`)와 다름 | `test/browser/` → `test/web/`, 자산은 `test/web/pdfium/`(패키지 `.gitignore`), 스크립트 `tool/prepare_web_test.dart`. `dart_test.yaml`·9.1 명령·T 표의 경로 갱신 |
| PDF-M3 | 3.1 | R2·R3 위반(`flutter: ">=3.47.0"`, 패키지 `analysis_options.yaml`) | `environment.flutter: 3.47.9`, `analysis_options.yaml` 삭제 |
| PDF-M4 | 5.3, 5.5 | `EditorMenuContext` 확장이 '요청'으로 남음, 앱 셸 연결 예시가 확정 이름과 다를 수 있음 | 5.3·5.5를 7.2.17·7.3.3으로(필드 `selectedPageIds`·`navigateToPage` 확정, `session` 없음, 연결은 INFRA `FeatureWiringModule`) |
| PDF-M5 | 6.9, 5.4 L-2 | "CORE `ThumbnailCache`를 만드는 일은 EDITOR 책임"이 최종 분담과 다름 | 7.2.11 썸네일 경로 표로 교체(가져오기 직후 표지는 PDF 그대로) |

**권장 수정**

| # | 근거 | 내용 |
|---|---|---|
| PDF-S1 | 1.3, 6.6, 6.7.5, 6.8, Q9 | 원격 에셋: `assetMissing`일 때 `core.remoteAssetFetcherProvider`가 있으면 `ensureLocal(assetId)` 요청 + `watch`로 '내려받는 중' 표시. 문서 풀은 `AssetStore.bytesArrived`를 구독해 실패 캐시를 지우고 다시 `acquire`. 이번에는 fetcher 없이(null) 동작 + 가짜 fetcher 테스트 |
| PDF-S2 | 4.9, Q12 | `missingAssetPolicy` 기본값 `blankPage` + 결과 시트 경고('n쪽은 원본이 없어 빈 페이지로 넣었어요') |
| PDF-S3 | 1.3, 4.11 | `exportNotesAsPdf(context, noteIds)`: 노트별 순차 내보내기, 취소 가능 진행률, 결과 시트(공유 가능하면 여러 파일 한 번에 `navigator.share`, 아니면 개별 다운로드). 작업 T15b + 테스트 |
| PDF-S4 | 4.1 `PdfRenderBudget.web()` | 웹 예산 32 / 64 / 16 MB(7.4.10). U16 기준도 112MB로 |
| PDF-S5 | 7 | `flutter_riverpod` 웹 '미확인' → 'INFRA·INK·EDITOR·LIBRARY 실험으로 확인됨' |
| PDF-S6 | 6.3 | `suggestedTitle`에 한글 자모 합성(6.10.1 4단계, 소문자화 제외) — iOS·macOS 파일 이름은 NFD일 수 있음(CORE-S4와 같은 규칙) |
| PDF-S7 | 7, T19 | PDFium 바이너리 배포본(chromium/8125)의 LICENSE와 third_party 목록(FreeType, libjpeg-turbo, OpenJPEG, lcms2, zlib, Abseil 등)을 확인해 `THIRD_PARTY_NOTICES.md` 초안 |
| PDF-S8 | 9.1, Q10 | `pdfium`·`web` 테스트는 기본 CI에 포함하되 `--affected-since`로 PDF가 바뀐 브랜치에서만, 훅 산출물 캐시(INFRA-M4) |

**질문 답변**

| Q | 답 |
|---|---|
| 1 | INK `PageBackgroundLayerBuilder` 하나로 통일, EDITOR 것 삭제 |
| 2 | 반영(7.2.17, EDITOR-M9) |
| 3 | LIBRARY 자리안 확정 |
| 4 | 제안대로 구현(사용자 암호 PDF는 해제 사본 + 암호 창 안내, 권한 암호만이면 원본). **사용자 확인 대기**(4장) — 결과가 다르면 정책 상수 하나로 바꿀 수 있게 |
| 5 | 충돌 없음으로 확정(7.2.11). LIBRARY 예약기는 `isStaleFor == false`면 건너뜀 |
| 6 | 이번은 노트 안 검색만. 전역 검색·색인은 이후(CORE 테이블 + FTS, 7.8) |
| 7 | 확정: 추가 정적 파일·COOP/COEP 없음, `.wasm` MIME, `<base href>` 유지, CSP 없음(7.4.9) |
| 8 | 예. 기반 단계 B1에서 INFRA가 전부 넣음(7.5) |
| 9 | 이번에 예약 + 구현(`bytesArrived`는 CORE가 지금 구현, fetcher 구현은 SYNC, 주입은 M4) |
| 10 | 기본 CI에 포함, 영향받은 경우만 실행 + 캐시(PDF-S8) |
| 11 | 확정(7.2.8 N-5) |
| 12 | `blankPage` + 경고(PDF-S2) |
| 13 | 추가 확정(7.2.16) |

### 3.7 SYNC — `07-sync.md` · 판정: 수정 후 재검토

불변 변경 묶음 로그 + 필드 단위 HLC LWW + 받기 먼저 + 결정적 시나리오 22개·무작위 수렴 검사는 데이터 손실 0 목표에 맞는 설계다. 차단으로 표시한 CORE 요청(R1~R12)은 모두 수용해 7.2.10에 넣었다. 수정은 확정된 CORE 이름 반영과 몇 가지 안전 규칙이다.

**필수 수정**

| # | 근거 | 문제 | 고치는 방법 |
|---|---|---|---|
| SYNC-M1 | 3, 3.1 | `note_core: path: ../note_core`(R8), `flutter: ">=3.47.0"`(R2), 패키지 `analysis_options.yaml`(R3), `display_mode_web.dart`(R5) | `note_core: any`, `environment.flutter: 3.47.9`, `analysis_options.yaml` 삭제, `display_mode_browser.dart` |
| SYNC-M2 | 4.9, 5.1.1~5.1.3, T6, T16 | CORE 쪽 이름 제안(`readVersioned`, `applyRemoteVersioned`, `VersionedMergePolicy`, `KeepLocalV` 등)과 확정 계약이 다름 | 5.1을 7.2.10으로: `readVersioned`, `RemoteMergePolicy`(버전 포함 단일 형태), `KeepLocal`/`TakeRemote`/`WriteMerged(entity, versions, fieldsToUpload)`, `applyRemote(metaUpdates:)`, `readMeta`/`writeMeta`, `commitRepairs(List<RepairWrite>)`(병합 단위로 펼친 필드 전달), `SyncStore.duplicateNoteForRecovery`. 5.1.3 대응표 갱신. `FakeLocalStore` 의미를 7.2.10 문장과 1:1로 맞추고, T16에 같은 계약 테스트를 `FakeLocalStore`·`CoreSyncLocalStore(openTestNoteStore)` 둘 다에 돌리는 공용 스위트 |
| SYNC-M3 | 4.4, 4.7, 5.3 | `SyncDisplayState`를 SYNC가 정의 — CORE `SyncDisplayState`(화면용)와 이중 | SYNC는 `core.SyncDisplayState`를 쓰고 다시 export하지 않는다. `syncBadgeOf(SyncStatus)`, `SyncRemoteAssetFetcher implements core.RemoteAssetFetcher` 추가(7.2.20) + 단위 테스트 |
| SYNC-M4 | 6.3.5, 6.2.2, 9.1.2 S14 | '서버 시간 + 24h 넘는 버전은 적용하되 경고' — CORE는 그런 값으로 시계를 올리지 않으므로 이후 그 필드의 로컬 편집이 항상 져서 outbox에서 조용히 빠짐 | 7.2.10 규칙: 그런 기록은 적용하지 않고 격리(`clockSkew` 차단 문제), 자기 측정 오차 > 24h면 업로드 중지. 시나리오 S14b(+48h 시계) 추가: 받는 기기 상태 불변·손실 0·문제 표시 |
| SYNC-M5 | 5.2 I-7, 10장 3 | 이번 범위 앱은 `sync_engine`에 의존하지 않음(7.1) → "INFRA 기반 단계 웹 빌드로 Firebase 포함 확인"이 성립하지 않음 | SYNC 자체 브라우저 컴파일 테스트 `test/web/firebase_compile_test.dart`(`@TestOn('browser')`, `firebase.dart`·`platform.dart` import, 초기화 없이 타입 사용) — dart2js 컴파일 오류를 잡음. 앱 웹 빌드 확인은 M4 연결 때 |

**권장 수정**

| # | 근거 | 내용 |
|---|---|---|
| SYNC-S1 | 5.2 I-4 | '루트 `firebase.json`' → `app/firebase.json`이 `../packages/sync_engine/firebase/…`를 참조(M4에 INFRA가 연결) |
| SYNC-S2 | 9.2 | 로그인·동기화 확인은 live 채널에서만(미리보기 주소는 출처가 달라 `authDomain`·저장소가 따로) |
| SYNC-S3 | 6.18, Q16 | 위치는 사용자 선택으로 안내서에(권장: Firestore `asia-northeast3`, Storage US 리전 — 미확인 표시) |
| SYNC-S4 | 6.11 | 필드 버전이 생겼으므로 '되돌리려는 필드와 원격이 바꾼 필드가 겹칠 때만 건너뛰기'는 CORE 이후 개선 후보로 기록(이번엔 엔티티 단위 유지) |

**질문 답변**

| Q | 답 |
|---|---|
| 1 | 수용(7.2.10, CORE-M5) |
| 2 | 수용(`commitRepairs`) |
| 3 | 수용(`afterSeq`, 힌트 항상, `{storagePath}` 기록) |
| 4 | 수용 + 이름은 CORE가 한국어로(CD-07) |
| 5 | 수용, 이번 범위에 구현 |
| 6 | 수용(CORE-M9) |
| 7 | 수용(7.6 B2) |
| 8 | 승인. PLAN 7.4 문구는 총괄이 갱신(5장) |
| 9 | CORE `RemoteAssetFetcher`(제안대로) |
| 10 | INFRA(로그인 화면·계정 섹션·알림 스낵바, M4). 배지는 LIBRARY·EDITOR가 `syncBadgeProvider`로 |
| 11 | 승인. `FIREBASE_ENABLED`·`firebase_options.dart`는 INFRA(M4) |
| 12 | COOP/COEP 없음 → 팝업 사용 가능. `authDomain` = Hosting 도메인은 M4 안내서에 |
| 13 | 승인(페이지만 되살림, 노트·폴더는 휴지통 유지). 알림 문구는 INFRA |
| 14 | `' (동기화 복구)'` 승인(LIBRARY 복사 접미사 `' 사본'`과 구분) |
| 15 | 방향 승인, 구현은 이후 |
| 16 | 사용자 선택으로 안내(SYNC-S3) |
| 17 | `SyncStore.duplicateNoteForRecovery`(휴지통 원본 허용) |
| 18 | 예. 원격 적용 시 로컬 `updatedAt` = max(현재, 적용값), outbox 없음 |
| 19 | 예, INFRA(M4 `SyncModule`) |
| 20 | 이후로 미룸(멱등이라 안전) |

---

## 4. 사용자 확인이 필요한 항목

| # | 질문 | 기본 진행 | 언제까지 |
|---|---|---|---|
| U1 | 사용자 암호가 걸린 PDF는 암호를 푼 사본을 노트에 저장해도 되는가?(다른 기기·다음 실행에서 암호를 다시 묻지 않음, 내보낸 PDF에도 암호 없음) | 제안대로 구현 | M3 실사용 전 |
| U2 | 앱 표시 이름('필기노트')과 번들 ID(`dev.noteapp.noteapp`) | 자리표시로 진행 | 네이티브 전환 전 |
| U3 | Firebase 프로젝트를 만들 때 Firestore·Storage 위치 | 안내서 권장안 | M4 연결 전 |
| U4 | (PLAN 11장 #1) 펜슬 종류·iPad 모델 | 필압 없음에도 동작하게 구현 | M0 확인 때 |

## 5. 다음 단계

1. 각 영역이 3장의 M(필수)·S(권장)를 반영해 계획서를 고친다. 질문 답변과 다르게 하려면 결과 보고에 '변경 요청'으로.
2. 총괄이 수정본을 다시 검토해 승인. 승인 기준 = 모든 M 해결 + 7장과 충돌 없음.
3. 총괄 후속: PLAN.md 7.4 '서버 시간 기준' → 'HLC(커서는 서버 시각)', 10장 M0 '예산 알림 설정' → '요금제 확인(예산 알림은 Blaze 전환 시)' 문구 갱신.
4. 기반 단계 B1~B8(7.6) → 동시 개발 → 통합(7.7).

---

## 2차 검토 (승인 검토)

> 날짜: 2026-11-04 · 대상: 01~07 1차 수정본 · 방식: 영역별 승인 검토 담당 7명의 판정을 총괄이 종합하고, 판정 근거가 된 계획서 줄·Flutter 3.47.9 엔진 소스·pub 해석을 총괄이 직접 다시 확인 · 결과: **통합 계약 v1.1**([00-overview.md 7.9](00-overview.md#79-계약-변경-이력)), 7개 영역 모두 **3차 수정 후 재승인**

### 2.1 판정 요약

| 영역 | 담당 판정 | 총괄 최종 | 사유 | 3차 수정 규모 |
|---|---|---|---|---|
| INFRA | 승인 | **미승인 (계약 반영)** | 필수 결함 없음. 계약 v1.1 중 10건(C11-08·10·11·12·13·24·27·28·29·30)을 계획서에 옮겨야 함 | 작음 |
| CORE | 미승인 | 미승인 | 필수 4건(원격·복구 쓰기의 로컬 필드, 상태 스트림 첫 값, K-1 문구, B2 범위) + 계약 반영 | 중간 |
| INK | 미승인 | 미승인 | 필수 2건(EDITOR 호출 규약 확정 형태, 썸네일 시그니처 반영) + 계약 반영 | 작음 |
| EDITOR | 미승인 | 미승인 | 필수 7건(담당 6 + 총괄 추가 1: `dart_test.yaml` 없음) — 대부분 INK 1차 수정 API를 따라가는 일 | 중간 |
| LIBRARY | 미승인 | 미승인 | 필수 1건(`dart_test.yaml`) + 계약 반영(표지 원격 갱신 포함) | 작음 |
| PDF | 미승인 | 미승인 | 필수 2건(배경 위젯 배율, B4 자리표시 provider — 총괄이 권장→필수로 올림) + 계약 반영 | 작음 |
| SYNC | 미승인 | 미승인 | 필수 4건(`testing.dart` lib 의존, 받기 먼저에서 영구 삭제 되살아남, 이분 재시도 결과 소실, 압축된 보류 청크) + 계약 반영 | 중간 |

전체 평가

- 1차 필수 수정(3장의 M)은 7개 영역 모두 해결됐다(담당 확인, 총괄 표본 확인: CORE 13.1·INK 13장·EDITOR 13장·SYNC 4.0 삭제 목록).
- 남은 문제는 세 종류다. ① 1차 수정 중 **한 영역이 바꾼 API를 다른 영역이 아직 옛 모양으로 호출**(INK → EDITOR 4건). ② **동기화 경계의 세부 의미**(원격 쓰기의 기기 로컬 필드, purge 대기, 이분 재시도). ③ **테스트 실행 경로**(`dart_test.yaml` 없는 패키지의 통합 테스트가 동시 개발 중 B2 상태 CORE로 실행됨).
- 이번에 계약을 v1.1로 올렸다(30항목). 대부분 주석·문구 수준이다. 시그니처 추가는 `NoteStore.exportBackupJson`, `openTestNoteStore(storageInfo:)`, `SyncBadge`의 `==`/`hashCode` 명시뿐이고, `InkPageThumbnail`·`setViewport`는 INK 4.9·4.8에 이미 있던 형태를 계약 블록으로 옮겼다. 의미만 바뀐 것은 `persistenceStatusStream` 첫 값, `pagesStream` 내보내는 조건, 원격·복구 쓰기의 로컬 필드, SYNC 보류 조건이다.
- 3차 수정은 diff 중심으로 다시 본다. 각 영역은 13장에 '2차 반영 내역'을 표로 남기고, 아래 지시 번호(예: `CORE-2-1`)를 그대로 인용한다.

### 2.2 계약 변경 결정

| 제안 | 낸 영역 | 결정 | 근거·조정 | 계약 반영 |
|---|---|---|---|---|
| INFRA P1 | INFRA | **수용** | 총괄이 Flutter 3.47.9 `engine/.../mouse/context_menu.dart`를 직접 확인: `_enabled = true`로 시작하고 `disable()`에서만 `contextmenu` `preventDefault` 리스너를 단다. 결정(미사용)은 그대로, 근거·실제 방어 수단만 정정. 00-review 3.4 Q11 답·3.1 INFRA-S5 문장도 이 항목으로 대체한다 | 7.4.9 (C11-28) |
| INFRA P2 · CORE CP-2 | INFRA, CORE | **수용(한 건으로 합침)** | 7.8이 정한 M4 선행 조건인데 7.2.12 시그니처에 없었다 | 7.2.12 (C11-08) |
| INFRA P3 | INFRA | **수정 수용** | 문제는 실재(경로 URL + Hosting `**` 재작성에서 `/notes/<id>` 새로고침 시 `sqlite3.wasm` 대신 `index.html`). 단 CORE의 해석 기준은 바꾸지 않는다 — `Uri.base.resolve(path)`는 절대 URL을 그대로 돌려주고, CORE 브라우저 테스트가 상대 경로에 기댄다. 규칙은 '운영은 `document.baseURI` 기준 절대 URL, 상대는 테스트만, 어떤 패키지도 정적 파일·에셋 URL을 `Uri.base` 상대로 만들지 않음'으로, 대상은 정적 파일·에셋 URL로 한정(EDITOR `?dev=1` 질의 읽기는 대상 밖) | 7.2.12, 7.4.3 (C11-11) |
| INFRA P4 | INFRA | **수용** | 같은 3.0.8, 외부 `sha256sum` 의존 제거. 총괄 scratch(`/tmp/claude-0/plan-scratch/lead/ws-v11`)에서 해석 성공·버전 변화 없음 확인 | 7.5 (C11-29) |
| CORE CP-1 | CORE | **수용** | 동기 broadcast 전달 중 재전달 불가(Dart "Cannot fire new event")를 계약에 명시. EDITOR E-4+·INK 5.3 #7이 이미 따름 | 7.2.8 N-2·N-4 (C11-01) |
| CORE CP-3 | CORE | **기각** | 반례가 공식의 `max(…, 0.75)` 하한을 빠뜨렸다: width 0.1·widthQ 0.075 → 팽창 0.1 × 0.75 = 0.075pt > 렌더 하한 0.05pt. 공식 유지, 근거 한 줄만 K-1에 추가(INK P2) | 7.3.2 K-1 (C11-23) |
| CORE CP-4 | CORE | **기각(불필요)** | SYNC 1차 수정이 포트 `RepairWrite`·`RepairReason`을 지우고 CORE `typedef`를 그대로 쓴다(07-sync 4.0·4.9). R14 충돌 없음 | — (7.2.20 삭제 목록에 기록) |
| CORE CP-5 | CORE | **수용** | SYNC 5.1.2 S-9 동의. `markUploaded`·`duplicateNoteForRecovery` = local, `reassignOwner` = remote | 7.2.10 (C11-04) |
| CORE CP-6 | CORE | **수용 + 보충** | '부른 화면은 반환값을 바로 써도 됨', '`backend`·`isDurable`은 실행 중 불변 → 배너 판정 영향 없음'을 함께 적었다 | 7.2.12 (C11-10) |
| INK P1 · PDF P1 | INK, PDF | **수용(INK 문구로 한 벌)** | 같은 절의 두 주석이 null 의미를 반대로 말하는 실제 모순. `renderStill` 주석 = `// null → cannot render now (InkPageThumbnailRenderer returns null)`, 렌더러 주석에 'Also null for pdf / image backgrounds when no listed builder is a still renderer that handles them' + '호출자는 null을 캐시하지 않고 나중에 다시 시도'(PDF의 'callers retry'는 렌더러 주석으로) | 7.2.16 (C11-18) |
| INK P2 | INK | **수용** | 위 CP-3 검산과 같음 | 7.3.2 K-1 (C11-23) |
| (INK 담당 요청 P3) | — | **총괄 직접 채택** | 계약의 `/* backgroundBuilders from the provider */`가 '위젯이 provider를 읽음'으로 읽혔다(EDITOR가 그렇게 씀). INK는 `flutter_riverpod` 비의존이라 불가능 → INK 4.9 시그니처를 계약에 그대로 박음. INK가 따로 제안할 필요 없음 | 7.2.16 (C11-19) |
| EDITOR CP-E1 | EDITOR | **수용 + 보충** | '표시 페이지 pt = 노트 `Page.size` 기준'까지 명시(P-1로 크기가 바뀐 PDF 페이지 대비) | 7.2.17 (C11-21) |
| EDITOR CP-E2 | EDITOR | **수용** | 손에 든 도구는 기기별 값. 펜 종류별 스타일은 synced 유지라 F-05와 충돌 없음 | 7.4.6 (C11-25) |
| EDITOR CP-E3 | EDITOR | **수용** | INK 정의를 계약으로 옮길 뿐 | 7.2.15 (C11-14) |
| LIBRARY CP-L1 | LIBRARY | **수용** | 총괄 scratch에서 해석 성공·버전 변화 없음 재확인 | 7.5 (C11-29) |
| LIBRARY CP-L2 | LIBRARY | **수용** | 두 화면 배너 시점 통일. CORE 담당 필수 2와 같은 항목 | 7.2.12 (C11-09) |
| LIBRARY CP-L3 | LIBRARY | **수용 + 보충** | CORE 4.10 원문을 계약 블록으로. 총괄 결정 추가: `openTestNoteStore(storageInfo:)`(CORE 담당이 '정해 달라'고 한 항목), 가짜 저장소 `SyncStore` 멤버 처리(값 2개·빈 목록·0, 나머지 `UnsupportedError` — CORE 4.10과 6.19의 불일치 해소), B2 단계 값(`seedSyntheticNote` 동작, `openTestNoteStore`·가짜 `exportBackupJson`은 `UnimplementedError`) | 7.4.8, 7.6 (C11-12, C11-27) |
| SYNC-CP0 | SYNC | **수용 + 보충** | SYNC 소유 이름 정리. 총괄 결정으로 `testing.dart` 정리(아래 SYNC-2-1)와 상태 값 클래스 값 동등을 같은 표에 넣었다 | 7.2.20 (C11-22) |
| SYNC-CP1 | SYNC | **수용 + 보충** | 받는 기기 벽시계 기준이 CORE `HlcClock.receive`와 맞는다. 해제 조건도 같은 기준. SYNC 12.3 Q-N2(자기 오차 > 24 h면 받기도 멈춤)도 수용해 같은 문장에 넣었다 | 7.2.10 (C11-07) |
| SYNC-CP2 | SYNC | **수용** | CORE `Asset` 생성자 기본값 `hasLocalBytes = true`(02-core 4.2.4)와 6.10.4 'JSON 덮어쓰기 후 디코드' 경로를 총괄이 직접 확인 — 명시가 없으면 원격 에셋이 '바이트 있음'으로 저장되고 '최근 노트'가 지워진다. 필드별 규칙까지 계약에 적었다 | 7.2.10 (C11-03) |
| SYNC-CP3 | SYNC | **수용** | `SyncBadge` `==`/`hashCode`를 계약 블록에 명시 | 7.2.13, 7.3.3 (C11-13) |
| SYNC-CP4 | SYNC | **수용** | `core-integration` 태그는 어디에도 정의되지 않음 | 7.7 (C11-30) |

총괄이 이번에 직접 넣은 계약 항목(제안 없이, 승인 검토에서 드러난 모호함 해소): C11-02 `pagesStream` 내보내는 조건(EDITOR Q-E1 답), C11-05 purge 대기의 `pendingLocalFields`(SYNC 되살림 수정의 전제), C11-06 `EntityChange` 힌트·원격과 C-9(LIBRARY 표지 갱신의 전제), C11-15 `setViewport` 소유자(INK·EDITOR가 서로 다르게 적음), C11-16 커밋 실패 시 `discardEdit`, C11-17 `InkPageContent` 생성자, C11-20 배경 위젯 배율(PDF 결함의 계약 쪽 근거), C11-24 저장 경고 문구 고정·대조 방법, C11-26 `dart_test.yaml` 태그 선언 규칙.

### 2.3 담당 판정에 대한 총괄 조정

| 영역 | 조정 | 근거 (총괄 직접 확인) |
|---|---|---|
| INFRA | 담당 '승인'은 계획서 자체로는 타당(권장 9건 모두 동의). 다만 계약 v1.1이 INFRA 계획서 여러 곳을 바꾸므로 규칙대로 **미승인** | 01-infra 3.3 표 `feature_library` 행에 `collection`·`clock` 없음, 3.2 루트 dev에 `crypto` 없음, SyncModule 표 `.distinct()` 없음 |
| CORE | 필수 4건 모두 확인. 담당이 열어 둔 질문 2개를 총괄이 결정(`openTestNoteStore(storageInfo:)` 추가, 가짜 `SyncStore` 멤버 처리). 다른 영역 질문 3건을 CORE 권장으로 추가(INK Q5, EDITOR Q-E1, LIBRARY Q-L1) | 02-core 6.10.3(`pageCount/firstPageId recomputed`만), 940행 `hasLocalBytes = true`, 8.1 T4·T5 산출물에 `seedSyntheticNote`·`openTestNoteStore`·`exportBackupJson` 없음(T18·T6·T19에만), 4.10 주석 'N-1..N-7' vs 6.19 '원격 변경 없음' |
| INK | 담당 필수 2(P3 제안 추가)는 총괄이 계약에 직접 넣었으므로 '계약 반영'으로 바뀜. 담당 필수 1(c)의 두 방법 중 **새 API 없이 `fromCore` + `core.Page`**로 결정. 담당 권장 4(`setViewport` 소유)는 **`InkPageView`만 부름**으로 결정해 계약에 넣음 | 03-ink 4.8 'fromCore is the ONLY constructor', `setViewport`가 'render side (used by InkPageView)', 4.9 `InkPageThumbnail` 생성자 `required this.backgroundBuilders` |
| EDITOR | 담당 필수 6건 모두 확인. **총괄 추가 필수 1건**: 계획서에 `dart_test.yaml`이 없다(3절 트리·작업 표 어디에도). E-21(`@Tags(['integration'])`, `openTestNoteStore`)이 동시 개발 중 기본 `ws test`에서 B2 CORE로 실행돼 실패한다 — LIBRARY 담당이 찾은 것과 같은 결함인데 EDITOR 담당은 놓쳤다. 담당 필수 5(E-21 문구 대조)는 총괄이 방식을 정함(각 영역 고정 문장 테스트 + INFRA V5) | 04-editor 941·2236·2503·1011·1403행, 1102행(`setViewport(deviceScale:)` 직접 호출 문장 — 담당 목록 밖, 같이 고칠 곳), `grep dart_test 04-editor.md` 결과 없음 |
| LIBRARY | 담당 필수 1 확인. 담당 권장 5의 'Q-L3를 CORE에 묻기'는 **불필요** — 총괄이 답했다(원격 적용에는 C-9가 적용되지 않음, 계약 7.2.10 v1.1). LIBRARY 쪽 해결안(원격 `ChangeBatch` 구독)은 유지하고 계약이 `EntityChange.noteId`를 보장한다 | 05-library 6.15.3 `_checked[note.id] == note.updatedAt`, 02-core 6.10.3 `max(current, applied updatedAt)` |
| PDF | 담당 필수 1 확인. **담당 권장 T0(B4) 자리표시 provider를 필수로 올림**: `pdfIoOverrides()`의 빌더 provider가 `pdfPageRendererProvider`(B4 본문 `UnimplementedError` 허용)를 watch하면, PdfModule이 켜진 앱·테스트에서 INK가 `pageBackgroundBuildersProvider`를 읽는 순간 예외 → 기반 단계·INFRA 동시 개발 테스트가 깨진다. PDF Q1은 INFRA가 이미 답을 갖고 있음(01-infra I9 앱 정보 '오픈소스 라이선스' `showLicensePage`) | 06-pdf 832행·2277행(`viewScale × ancestorScale`), 1361행(`renderer: ref.watch(pdfPageRendererProvider)`), 2635행 T0 |
| SYNC | 담당 필수 4건 모두 확인. 필수 1의 두 방법 중 **lib에서 `fake_async`를 쓰지 않는 쪽**으로 결정(의존 변경 없음 → INFRA 3.3 표 영향 없음). 필수 2의 ①이 기대는 CORE 동작(purge 대기의 `pendingLocalFields = {'*'}`)을 계약에 넣었다. 담당이 다루지 않은 SYNC 12.3 Q-N1·Q-N2에 답했다 | 07-sync 3.1(`fake_async`는 dev), 1368~1385행(`FakeAsync`, `syncScenario`, `expectConverged`), 6.3.4 첫 줄 `local == null → TakeRemote(dropPendingLocal: true)`, 6.3.5 표 |

### 2.4 영역별 남은 문제 (3차 수정 지시)

표기: **[필수]** 재승인 조건 · **[계약]** 통합 계약 v1.1을 계획서에 반영(재승인 조건) · **[권장]** · **[사소]**. 지시 번호는 `<영역>-2-<n>`. 계약 반영은 해당 계획서의 '제안' 표기를 '계약 7.x(v1.1)' 인용으로 바꾸고 12장 제안 표에 결정(승인·기각)을 적는 것까지 포함한다.

#### 2.4.1 INFRA — 미승인 (계약 반영만)

| # | 종류 | 지시 |
|---|---|---|
| INFRA-2-1 | 계약 C11-28 | 6.9·12.3 P1: `disableContextMenu()` 미사용 근거를 계약 7.4.9 v1.1 문장으로 인용, P1 '승인' |
| INFRA-2-2 | 계약 C11-08 | 5.1 'INFRA가 쓰는 CORE 멤버' 표·4.5.8 `backup_export`의 `exportBackupJson`을 '계약 7.2.12'로(제안 표기 삭제). 기반 단계 가짜 저장소는 `exportBackupJson`이 `UnimplementedError`(계약 7.6)이므로 `backup_export_test`는 지금처럼 `CountingNoteStore`(결과 주입)로 둔다고 한 줄 |
| INFRA-2-3 | 계약 C11-11 | 4.4·4.5.2 `resolveAppUrl`·6.4의 '제안 P3' 표기를 '계약 7.2.12·7.4.3'으로. CORE는 `Uri.base.resolve`를 그대로 쓰므로(절대 URL 통과) INFRA는 절대 URL만 넘기면 된다는 점 명시 |
| INFRA-2-4 | 계약 C11-29 | 3.2 루트 `pubspec.yaml` dev_dependencies에 `crypto: 3.0.8`, 3.3 표 `feature_library` 행 dependencies에 `collection: 1.19.1`·dev_dependencies에 `clock: 1.1.3`, 4.3 web-assets 비고·7.2 표·7.3 `sha256sum` 행 정리(승인됐으므로 대체 경로 삭제), `pinned_external` 목록 확인 |
| INFRA-2-5 | 계약 C11-10 | (담당 권장 3과 같음) 4.5.10 `latestStorageInfoProvider`·4.5.8 `StorageSection`: `refreshStorageInfo()` 뒤 `ref.invalidate(storageInfoProvider)`. `storage_section_test`에 '다시 확인 후 `storageInfoProvider` 값 갱신' |
| INFRA-2-6 | 계약 C11-13 | `SyncModule` 표(5.5·6.4)의 `syncBadgeProvider` 값 = `syncEngine.statusStream.map(syncBadgeOf).distinct()` |
| INFRA-2-7 | 계약 C11-12·24·30 | 8.3 G2 V5 스모크: 메모리 CORE(`NoteStoreConfig(inMemory: true)`)는 `nativeMemory`라 `notDurable` 배너가 라이브러리·에디터 두 화면에 뜬다. 스모크에서 두 화면의 배너 문구가 계약 7.4.5 고정 문장과 같은지 `find.text`로 확인(LIBRARY 배너는 닫기 버튼이 있으니 닫기 전에)하고, 나머지 단계가 배너 높이에 기대지 않게 적는다. 9.1 표에 이 단언 추가 |
| INFRA-2-8 | 계약 C11-27 | (담당 사소 1과 같음) 5.1 표의 `createFakeNoteStore` 시그니처를 계약 7.6 블록 전체 형태로, `openTestNoteStore`는 `storageInfo:` 포함으로 |
| INFRA-2-9 | 권장 | (담당 권장 1) 4.5.9 `CoreModule.start`·6.4 2-2: 시작 시간 제한(20초) 뒤 늦게 완료된 `NoteStore`는 즉시 `close()`(실패는 errorLog), 다시 시도는 그 close가 끝난 뒤(최대 2초). 9.1 `core_module_test`에 '시간 초과 뒤 늦게 열린 저장소는 close 1회' |
| INFRA-2-10 | 권장 | (담당 권장 2) 8.3 G2 V6: '끝에 `deleteLocalNoteData`' → '`bootstrapper.shutdown()`(= `store.close()`) 뒤 `deleteLocalNoteData(config)`'(CORE 6.18: 열린 저장소가 있으면 `StateError`) |
| INFRA-2-11 | 권장 | (담당 권장 4) 4.5.2 `downloadBytes`·6.16 안내서 04·9.3 #18·11절: iPadOS 홈 화면 앱에서 Blob + `<a download>`가 동작하지 않을 수 있음(미확인)을 리스크 표에, 대응 `navigator.share({files})`(Safari 15+, 미확인). #18을 Safari 탭/홈 화면 앱 두 줄로 — 백업은 M4 선행 조건이라 실기기 경로 하나는 확실해야 한다 |
| INFRA-2-12 | 권장 | (담당 권장 5·6) R4: `native_only_imports`(`package:ffi/`, `package:pdfium_dart/`, `package:drift/native.dart`)는 `native_suffixes` 파일에서만, `lib_exceptions`의 `testing_vm.dart` 예외. 'test_only_entrypoints import 금지'는 `package:` URI 기준(같은 패키지 `lib/testing*.dart`끼리 상대 import 허용). ink lab이 멤버가 되면 `example/lib`의 `package:note_core/testing.dart` 사용을 `lib_exceptions`에 추가(1.3 INFRA-O1에 한 줄). `rules_test`에 위반 1·허용 1 |
| INFRA-2-13 | 권장 | (담당 권장 7) 8.3 G4·10절 7: 'dart format 변경 없음'의 대상 = R11과 같은 파일 집합(generated 제외)이라고 표에 'R11 기준'. drift 생성 파일이 lint에 걸리면 6.2 exclude에 추가한다는 CORE 11절 요청을 6.2 비고에 |
| INFRA-2-14 | 사소 | 12.2 N1~N3: 기본 진행대로 **승인**(N1 PLAN 8 IA 순서, N2 R9w 경고 + main·G1 `--strict`, N3 앱 → `sync_engine` 간선은 M4에 추가). PDF 12.2 Q1(라이선스 화면)은 I9에 이미 있음 — 그대로. INK 12.2 Q4(ink lab 실험 채널)는 INFRA-O1대로 선택 승인 |
| INFRA-2-15 | 사소(선택) | `ws check`에 '`@Tags([... 'integration' ...])`를 쓰는 패키지는 `dart_test.yaml`에 `integration` skip이 있어야 함' 검사를 둘지 검토(C11-26 재발 방지) |

#### 2.4.2 CORE — 미승인

| # | 종류 | 지시 |
|---|---|---|
| CORE-2-1 | 필수 (계약 C11-03) | (담당 필수 1) 6.10.3·6.10.4에 원격·복구 쓰기의 기기 로컬 필드 규칙: (a) 들어온 엔티티의 로컬 전용 값은 무시 (b) `Note.lastOpenedAt`은 현재 행 값 유지(새 행 null) (c) `pageCount`·`firstPageId` 재계산 (d) `Page.contentRevision` = 현재 + 1(새 행 0) (e) `Asset.hasLocalBytes`·`chunkCount`는 현재 행 값 유지, 새 행은 BlobStore에 바이트가 있는지로(없으면 false) (f) `Asset.fromJson`은 `hasLocalBytes: false`(4.2.4 주석·6.3). 4.6 bullet에 한 줄 요약. 9.1 `sync_store_test`·`commit_repairs_test`: 원격 에셋 TakeRemote 뒤 `listAssets(hasLocalBytes: false)`에 포함, 원격 노트 TakeRemote·`commitRepairs` 뒤 `lastOpenedAt` 유지, WriteMerged도 같은 결과 |
| CORE-2-2 | 필수 (계약 C11-09) | (담당 필수 2) 4.8.1 `persistenceStatusStream` 문서 주석 = '구독 즉시 현재 `persistenceStatus` 1회, 이후 바뀔 때마다'. 6.19 가짜도 같게. T5 `providers_fake_test`·T17 `providers_real_test`에 '`persistenceStatusProvider` 첫 값이 쓰기 전에 도착' |
| CORE-2-3 | 필수 (계약 C11-23) | (담당 필수 3) 5.2 K-1 행 끝의 'INK `kMinRadius`(0.05pt)가 공식보다 큰 아주 가는 획은 12.2 CP-3' 삭제, 12.2 CP-3 '기각(총괄 2차 검토 — 검산 오류)'. K-1 행에 '`minRadiusPt` 0.05 ≤ 0.75 × `StrokeStyle.minWidth`(0.075)' 근거 한 줄 |
| CORE-2-4 | 필수 (계약 C11-27) | (담당 필수 4) 8.1 B2 범위를 4장 머리말과 맞춘다: (a) `seedSyntheticNote`는 `NoteStore` 인터페이스(`library.createNote` + 세션 `AddStrokes`)만으로 구현 → 작업 위치 T5, B2에서 가짜 저장소로 동작 (b) `openTestNoteStore`는 B2에 시그니처(`storageInfo:` 포함), T6 전까지 `UnimplementedError` (c) 가짜 `exportBackupJson`은 B2 `UnimplementedError`, T19에서 같은 형식(6.19 '`exportBackupJson`(같은 형식)' 문구도 'T19부터'로). B2 `api_surface_test`에 `dev_tools.dart`·`testing.dart`·`testing_vm.dart` 이름 포함. T18의 `dev_tools.dart` 산출물은 README·성능 측정만 남김 |
| CORE-2-5 | 계약 C11-27·12 | (담당 권장 1·4 해결) 4.10 `createFakeNoteStore` 주석과 6.19를 계약 7.6 문장과 같게: 세션 N-1~N-6(N-7은 원격 경로가 없어 해당 없음), `SyncStore`는 `ownerId`·`deviceNodeId` 값·`pendingChanges()` 빈 목록·`watchPendingCount()` 0·**나머지 전부 `UnsupportedError`**. `openTestNoteStore`에 `StorageInfo? storageInfo`(null = 실제 백엔드: 메모리면 `nativeMemory` → `notDurable` 배너), `NoteStoreConfig.inMemory` 주석에 같은 설명. 테스트 1건(인자를 주면 `storageInfo`가 그 값) |
| CORE-2-6 | 계약 C11-01 | 4.4 `NoteSession` 주석의 재진입·undo/redo 읽기 전용 문장을 '(7.2.8 N-2·N-4)' 인용으로, 12.2 CP-1 '승인'. `note_session_contract`에 '읽기 전용 노트 `undo`/`redo` → `ReadOnlyNoteException`, 쓰기 없음' |
| CORE-2-7 | 계약 C11-02 | (EDITOR Q-E1 답) 4.4 `pagesStream` 주석 = '활성 페이지 목록 또는 그 안의 `Page` 값(로컬 `contentRevision` 포함)이 바뀔 때마다'. `note_session_contract`에 'AddStrokes 뒤 `pagesStream`이 새 `contentRevision`을 가진 목록을 냄' |
| CORE-2-8 | 계약 C11-04 | 4.6·6.10.5·6.13: `markUploaded` = `ChangeBatch(origin: local)`, `duplicateNoteForRecovery` = local, `reassignOwner` = remote를 '계약 7.2.10' 인용으로. 12.2 CP-5 '승인'. T13·T14에 세 호출의 origin 단언 |
| CORE-2-9 | 계약 C11-05 | 6.10.3: 정책에 넘기는 `pending`은 outbox 항목의 `changedFields`, 항목이 `op: purge`면 `{'*'}`(행이 없어 `local == null`). T14 테스트 1건(로컬 purge 대기 중 원격 upsert → 정책이 `pending == {'*'}`을 받음) |
| CORE-2-10 | 계약 C11-06 | 4.8.1 `EntityChange` 주석: `noteId`는 page·stroke·recording에 항상, `pageId`는 stroke에 항상(outbox와 같은 비정규화 열). C-9 주석에 '로컬 편집 규칙, 원격은 `max(현재, 적용값)` — 7.2.10'. T7 또는 T10에 '원격 획 batch의 `EntityChange.noteId`' 단언 |
| CORE-2-11 | 계약 C11-08·10·11 | 4.8.1 `exportBackupJson` 주석의 'Placement … = proposal 12.2 CP-2' → '7.2.12'. 4.9 `storageInfoProvider` 주석·4.8.1 bullet의 'CP-6' → '7.2.12'. `WebStorageConfig` 주석: 'resolved with `Uri.base.resolve(path)` — absolute URLs pass through; production passes absolute URLs from `document.baseURI`(7.2.12); relative paths only in tests'. 12.2 CP-2·CP-6 '승인' |
| CORE-2-12 | 계약 C11-13 | 4.8.2 `SyncBadge`에 `==`/`hashCode`, T4 테스트 1건 |
| CORE-2-13 | 계약 C11-07·25 | 4.6의 시계 문구 인용을 계약 v1.1 문장으로(CORE 동작은 그대로). 5.3 E-5+의 device 목록에 `editor.toolSelection` |
| CORE-2-14 | 계약 | 12.2 CP-4 '기각(불필요 — SYNC가 포트 삭제)'. 13절에 '13.2 2차 수정' 표 |
| CORE-2-15 | 권장 | (담당 권장 2) 12.3 Q-A '해결: SYNC 6.3.1 병합 단위 표가 page `size`(`[w, h]` 한 키)를 채택'. Q-B: 총괄 답 = **승인**(전체 한 파일, iPad에서 문제가 보이면 노트별 내보내기를 계약 변경으로 제안) |
| CORE-2-16 | 권장 | (INK 12.2 Q5 답) 5.2 K-6+의 '새 획의 첫 점 0' → '보통 0(시작 갈고리를 잘라내면 > 0, 범위 [0, 500000] 안)', `Stroke.recordingOffsetMs` 주석 'to points[0]' → 'to createdAt'. CORE 검증 동작은 그대로 |
| CORE-2-17 | 권장 | (LIBRARY 12.3 Q-L1 답) 4.5 머리말 주석에 저장소 변경 메서드 `Future`의 완료 시점을 한 줄로. 총괄 기본안: DB 커밋 뒤 완료(쓰기 재시도 중에는 끝나지 않음, 6.9), 도메인 오류(`FolderCycleException`·`EntityNotFoundException`·`ArgumentError`)는 커밋 전에 즉시 오류로 완료. 실제 구현이 다르면 실제 동작을 적는다 |
| CORE-2-18 | 사소 | (담당 사소) 7.3 실험 표 '테스트 자산 경로' 행 `WasmStorageConfig` → `WebStorageConfig` |

#### 2.4.3 INK — 미승인

| # | 종류 | 지시 |
|---|---|---|
| INK-2-1 | 필수 | (담당 필수 1, 총괄 결정 반영) 5.3 'EDITOR 호출 규약'에 확정 형태 4건: (a) 속지 선택 미리보기도 5.3 #15처럼 `InkPageThumbnail(content:, width:, backgroundBuilders: ref.watch(ink.pageBackgroundBuildersProvider), pencilGrain: ref.watch(ink.pencilGrainProvider))` (b) `PenPreviewPainter(style:, pencilGrain: ref.watch(ink.pencilGrainProvider))` — `PencilGrain` 그대로, painter가 `repaint: pencilGrain`으로 다시 그림 (c) 미리보기 내용은 **새 API 없이** `InkPageContent.fromCore(page: current.copyWith(size: s, background: b), strokes: const [], revision: 0)`(계약 7.2.15 v1.1) — 4.8 `fromCore` 문서 주석에도 이 예 (d) `testing.dart`에 `SequentialIds`는 없음 → `core.SequentialIdGenerator` 또는 `testInkCoreServices()`. EDITOR에 대한 수정 지시는 총괄이 EDITOR-2-*로 냈으므로 12.2에 Q6을 따로 둘 필요는 없다 |
| INK-2-2 | 필수 (계약 C11-19) | (담당 필수 2 대체) 계약 7.2.16 v1.1이 `InkPageThumbnail` 시그니처를 박았다. 4.9 `thumbnail.dart` 머리 주석 'backgroundBuilders from the provider' → '호출자가 provider 값을 넘김(계약 7.2.16)', 13장 '자체 정리'의 해당 줄도 계약 인용으로. P3 제안은 내지 않는다 |
| INK-2-3 | 계약 C11-14 | (담당 권장 3) 4.8 `beginStroke`/`beginErase`/`beginLasso`의 `viewScale`에 `/// logical px per page pt (no devicePixelRatio; device scale goes to setViewport)` |
| INK-2-4 | 계약 C11-15 | (담당 권장 4, 총괄 결정) `setViewport`는 **`InkPageView`만** 자기 인자(`visiblePageRect`·`isScaling`·`ancestorScale`·DPR)로 부른다. 4.8 주석, 5.3 #4·#8, 6.12에 적고, build 중 알림이 나가지 않게 부르는 시점(예: `didUpdateWidget`/레이아웃 뒤, 또는 `setViewport`는 `notifyListeners`를 하지 않고 다음 프레임에 반영)을 명시. 위젯 테스트 1건(인자 변경 → `renderStats.currentBucket` 갱신, build 중 예외 없음) |
| INK-2-5 | 계약 C11-16·01 | 5.3 #5(`discardEdit`)를 '계약 7.2.15 v1.1' 인용으로, 12.2 Q1 '해결(EDITOR 채택)'. 5.3 #7을 'N-2(v1.1)' 인용으로 |
| INK-2-6 | 계약 C11-18·20 | 4.10 `renderStill` 주석을 계약 문구로, 12.1 P1 '승인(PDF P1과 한 벌)'. 4.10 `PageBackgroundContext`·`PageBackgroundLayerBuilder.build` 주석에 '레이아웃은 `viewScale`만, `ancestorScale`은 `deviceScale`로만'(계약 7.2.16 v1.1), 6.17 `TemplateBackgroundLayerBuilder`도 이 규칙 |
| INK-2-7 | 계약 C11-23 | 12.1 P2 '승인', 6.7 K-1 증명에 계약 인용 |
| INK-2-8 | 계약 | 12.2 Q2 '해결(LIBRARY 6.15.3이 null → `bytesArrived` 재시도)', Q3 '승인 — 6.16 기본 배치로 시작, iPad #12 피드백으로 표만 조정', Q4 '선택 승인(INFRA-O1)', Q5 '승인 — CORE가 문구 수정(CORE-2-16)'. 13장에 2차 반영 표 |
| INK-2-9 | 사소 | (담당 경미 1) 6.2 표 W1 'INK 설계 반영' 칸의 `InkSampleAdapter.kindOf` → '내부 kind 매핑 함수(6.3)' |
| INK-2-10 | 사소 | (담당 경미 2) 3장 'core_interop.dart 외 파일은 CORE 객체를 만들지 않는다' vs 6.20 P8 미리보기 `fragment`·6.22 `source.transformed(m)`: 6.23 함수표에 `previewFragmentOf`·`previewTransformedOf`를 추가하거나 '미리보기용 임시 객체는 예외'를 규칙에 |
| INK-2-11 | 사소 | (담당 경미 3) 6.7 F8: 획 시간이 `t` 상한 500 000 ms를 넘는 경우 처리(예: 도달 시 그 시점에 획을 끝내고 새 획 시작). K4: 연필 f가 1.6 × 2.8 = 4.48까지 올라도 K6에서 `widthQ` 1로 포화, 라이브 미리보기도 같은 clamp |

#### 2.4.4 EDITOR — 미승인

| # | 종류 | 지시 |
|---|---|---|
| EDITOR-2-1 | 필수 (계약 C11-16) | (담당 필수 1) 6.6.3 `commitInkEdit`·5.1.3 `_run`·6.7 표: 실패 시 `controller.discardEdit(edit)`(예: `_run(command, {VoidCallback? onRejected})`, `commitInkEdit`은 `onRejected: () => controller.discardEdit(edit)`). 843·875·956·1959·2089·3084행의 `discardPending` 문장을 모두 이 규칙으로. 6.7 '지우개·변형 실패 시 INK가 세션 종료 시 처리' → 'EDITOR가 `discardEdit(edit)`'. 5.2.1 사용 API에 `discardEdit`. E-08·E-09·E-10 완료 조건: '실패(읽기 전용 경합 주입) → `discardEdit` 뒤 `pendingIds` 비어 있음, 지운 획이 다시 보임' |
| EDITOR-2-2 | 필수 (계약 C11-19) | (담당 필수 2) 5.2.1 '미리보기·썸네일' 행(941행), 6.11.3 `PagePanelThumbnail`(2441행), 6.11.4 추가 시트: `InkPageThumbnail(content:, width:, backgroundBuilders: ref.watch(ink.pageBackgroundBuildersProvider), pencilGrain: ref.watch(ink.pencilGrainProvider))`. 4.3 'EDITOR가 직접 읽는 provider' 표(와 6.13.2의 'INK 5개' 개수)에 `ink.pageBackgroundBuildersProvider`를 '읽기만, override 안 함'으로. 5.2.1 '쓰지 않는 것'은 'override하지 않음'으로 |
| EDITOR-2-3 | 필수 (계약 C11-17) | (담당 필수 3) 6.11.4 속지 미리보기(2503행): `ink.InkPageContent.fromCore(page: current.copyWith(size: size, background: backgroundFor(choice, color)), strokes: const [], revision: 0)`. 칸마다 `ValueKey((choice, color, size))`로 위젯 구분 |
| EDITOR-2-4 | 필수 (계약 C11-19) | (담당 필수 4) 6.9.3 #2(2236행): `ink.PenPreviewPainter(style: currentPen, pencilGrain: ref.watch(ink.pencilGrainProvider))`, `ValueListenableBuilder` 설명 삭제. 4.3 표 `pencilGrainProvider` 용도에 `InkPageThumbnail` 추가 |
| EDITOR-2-5 | 필수 (계약 C11-24) | (담당 필수 5, 총괄 방식 결정) E-21·6.17.3·12.3 Q-E4에서 'LIBRARY 문구 상수 대조'를 지운다(피처 간 import 금지 — test 포함). 대신 ① EDITOR 단위 테스트가 `editor_strings.dart`의 두 문장을 계약 7.4.5 고정 문장과 비교 ② 두 화면 대조는 INFRA V5 스모크(INFRA-2-7). 세 곳을 같은 문장으로 |
| EDITOR-2-6 | 필수 (계약 C11-15) | (담당 필수 6, 총괄 결정) EDITOR는 `setViewport`를 부르지 않는다. 6.4.3 마지막에서 두 번째 항목(1403행 '같은 시점에 `controller.setViewport(...)`'), 1102행('기기 픽셀 배율은 `controller.setViewport(deviceScale: …)`로 따로 준다'), 5.2.1 표(931행), 6.2 마지막 항목, 6.4.2 표(1365행)에서 직접 호출을 지우고 '`InkPageView`에 `ancestorScale`·`isScaling`·`visiblePageRect`만 넘긴다(INK가 `setViewport`)'로. 인용 'INK 5.3 #7' → '#8' |
| EDITOR-2-7 | 필수 (계약 C11-26, 총괄 추가) | `packages/feature_editor/dart_test.yaml`을 3절 트리와 E-00(골격 작업)에 추가: `tags:` 아래 `golden: {}`, `integration: {skip: "integration stage only — ws test --run-skipped -t integration"}`. 9.1·2897행의 '통합 태그는 통합 단계에' 문장의 근거로 이 파일을 적는다. 없으면 E-21이 동시 개발 중 기본 `ws test`에서 B2 CORE(`openTestNoteStore` = `UnimplementedError`)로 돌아 실패한다 |
| EDITOR-2-8 | 계약 C11-01·02·09·12 | 5.1.3·6.6의 리스너 안 `execute` 금지를 'N-2(v1.1)' 인용으로, `_run`이 `undo`/`redo`의 `ReadOnlyNoteException`도 잡는지 확인. 12.3 Q-E1 '해결(N-1 v1.1 — `contentRevision` 변경에도 냄, EDITOR의 걸러 쓰기 유지)'. 6.17.3 '로딩 중엔 배너 없음'은 첫 프레임(AsyncLoading)만 해당한다고 정리(첫 값이 구독 즉시 옴). E-21은 `openTestNoteStore()` 기본이 `nativeMemory` → `notDurable` 배너가 뜬다는 점을 단언에 반영(또는 `storageInfo: const StorageInfo(backend: StorageBackend.nativeFile)`) |
| EDITOR-2-9 | 계약 C11-14·21·25 | 5.2.2 #4·6.2의 `viewScale` 정의, 6.2·6.11.6의 `focusRectPt` 해석, 6.14 `editor.toolSelection`(device)을 각각 계약 7.2.15·7.2.17·7.4.6 v1.1 인용으로. 12.2 CP-E1~E3 '승인' |
| EDITOR-2-10 | 권장 | (담당 권장 1) 5.5 가짜 표(1011행): `SequentialIds` → `ink.testInkCoreServices()` 또는 `core.SequentialIdGenerator`, 필요하면 `ink.MemoryPressureStore` |
| EDITOR-2-11 | 권장 | (담당 권장 2) 5.1.3 매핑 표 '붙여넣기'·'합성 획'·'펜 획' 행: `core.AddStrokes(pageId: …, strokes: …)` named 형태로 통일 |
| EDITOR-2-12 | 권장 | (담당 권장 3·4) 3절 `test/helpers/`에 `recording_note_session.dart`. 12.3 Q-E2 '해결됨(INK 4.15 B3 표)'(E-08 '같은 프레임 pending 정리' 단언 유지), Q-E3 '승인(fps 없이)'. 13장에 2차 반영 표 |

#### 2.4.5 LIBRARY — 미승인

| # | 종류 | 지시 |
|---|---|---|
| LIBRARY-2-1 | 필수 (계약 C11-26) | (담당 필수 1) 3절 트리·3.1·8절 B6(또는 L0)에 `packages/feature_library/dart_test.yaml`(`tags:` 아래 `golden: {}`, `integration: {skip: "integration stage only — ws test --run-skipped -t integration"}`). 9.1 'integration(기본 skip)'의 근거로 이 파일을 적는다. 같은 수정에서 3절 트리에 B6의 `test/feature_library_smoke_test.dart` |
| LIBRARY-2-2 | 계약 C11-06 | (담당 권장 5, 총괄 조정) 6.15.3 예약기: `NoteStore.changes`에서 `ChangeBatch(origin: remote)`를 구독해 `c.kind == note ? c.id : c.noteId`의 `_checked`를 지우고 `_visible`에 있으면 다시 `request`(화면 밖은 다음 표시 때). 근거는 계약 7.2.10 v1.1(원격 적용에는 C-9 미적용, `EntityChange.noteId` 보장). **Q-L3는 추가하지 않는다**(총괄 답). 11절 리스크 행, L11 테스트 1건(가짜 저장소에 원격 batch를 흘릴 수 없으면 예약기 단위 테스트에 `changes` 스트림 주입) |
| LIBRARY-2-3 | 계약 C11-27·12 | 5.7의 CORE 발췌를 계약 7.6 블록과 같게(`openTestNoteStore(storageInfo:)` 추가). L21은 실제 메모리 CORE가 `notDurable` 배너를 띄운다는 점을 시나리오 단언에 반영하거나 `storageInfo:`로 끈다. 12.2 CP-L3 '승인' |
| LIBRARY-2-4 | 계약 C11-29·09·13·18·24 | 3.1·7.1 `collection`·dev `clock`을 '계약 7.5' 인용, CP-L1 '승인'. 6.16.2: 첫 값이 구독 즉시 오므로 `NoteStore.persistenceStatus` 대체는 첫 프레임용으로만(삭제해도 됨), CP-L2 '승인'. 5.5 Y-1 `distinct`는 계약 7.3.3 인용. 5.3 K-4는 계약 7.2.16 v1.1 인용. 6.16 배너 문구 = 계약 7.4.5 고정 문장 — 문구 상수 비교 테스트 1건 |
| LIBRARY-2-5 | 계약 | 12.3 Q-L1 '답: CORE가 4.5에 명시(CORE-2-17) — LIBRARY의 "둘 다 견딤"(6.11) 유지', Q-L2 '승인(이번은 노트만, 폴더는 건너뜀)'. 13장에 2차 반영 표 |
| LIBRARY-2-6 | 권장 | (담당 권장 2) 5.7·L0·L21 시나리오 공유 도구: (a) `LibraryHarness`/`LibraryTestHarness` 이름 하나로 (b) `FakeLibraryBackend`의 실제 CORE 생성 경로를 시그니처로(예: `static Future<FakeLibraryBackend> overStore(Future<NoteStore> Function(Clock clock) open, {TestClock? clock})`), `faults`는 nullable, L21에서는 `failNextCommits` 시나리오 제외 규칙 (c) 11절: 실제 drift 저장소를 `testWidgets`에서 쓰면 스트림 타이머가 남을 수 있음 → `tester.runAsync` + 끝에 `store.close()` |
| LIBRARY-2-7 | 권장 | (담당 권장 3) 6.8 그리드 타일 즐겨찾기 ★ 'amber' 하드코딩 → `colorScheme.tertiary` 등 테마 색(7.4.11) |
| LIBRARY-2-8 | 권장 | (담당 권장 4) 7.4.6: `NewNoteOptions.fromJson` 웹 형식 입력(`customW: 210` 같은 정수, 범위 밖 맞춤) 디코드 테스트를 `test/web/`에도(예: L3 또는 L20에 `test/web/new_note_options_browser_test.dart`) |

#### 2.4.6 PDF — 미승인

| # | 종류 | 지시 |
|---|---|---|
| PDF-2-1 | 필수 (계약 C11-20) | (담당 필수 1) 4.7 `PdfBackgroundLayerBuilder.build` 주석(832행), 4.7 `PdfPageBackgroundView.viewScale` 주석, 6.8 마지막 두 항목(2277행): 위젯 크기·painter 배율은 `ctx.viewScale`만 — `build` = `PdfPageBackgroundView(params: paramsFrom(ctx), viewScale: ctx.viewScale)`. `ancestorScale`은 `params.deviceScale`(= `ctx.deviceScale`)로 해상도·버킷 선택에만. `PdfPageBackgroundView.viewScale`은 required로 바꾸거나 미지정 시 부모 제약 폭 / `pageSize.width`, 'deviceScale / DPR' 대체 규칙 삭제. T9 `widget/ink_builder_adapter_test.dart`에 `ancestorScale: 2`: 위젯 크기 = pageSize × viewScale, `params.deviceScale` = viewScale × 2 × DPR |
| PDF-2-2 | 필수 (총괄이 권장 → 필수로) | (담당 권장 T0) B4 자리표시 `pdfIoOverrides()`의 빌더 목록 override가 본문이 `UnimplementedError`일 수 있는 provider(`pdfPageRendererProvider` → `PdfRenderService`·풀·엔진)를 watch하지 않게 하거나, 그 provider 사슬이 B4에서도 예외 없이 만들어지게 한다(예: B4 자리표시 빌더는 `renderer` 없이 종이만 칠하는 별도 생성자). T0 완료 조건에 `unit/init_test`: '`pdfIoOverrides()`를 넣은 컨테이너에서 `ink.pageBackgroundBuildersProvider`를 read해도 예외 없음, 목록 = [PDF 빌더, 속지 빌더]' |
| PDF-2-3 | 계약 C11-18 | (담당 권장 9 대체) 12.1 P1 '승인(계약 7.2.16 v1.1 — INK 문구로 한 벌)'. 4.7·5.2 발췌 주석을 계약 문구로(`// null → cannot render now (InkPageThumbnailRenderer returns null)`) |
| PDF-2-4 | 계약 C11-21 | (담당 권장 5) 4.8 `PdfSearchHit.rects`·6.10.2 7단계·6.8 ④ 하이라이트: 좌표 = 노트 페이지 pt(왼쪽 위 원점, y 아래, 노트 `Page.size` 기준). 노트 크기와 PDF 표시 크기가 다를 때(6.5 s ≠ 1)는 charRects에 6.11.3 F 변환을 적용한 값. `navigateToPage`의 `focusRectPt`와 하이라이트에 같은 값(계약 7.2.17 v1.1). T11 검색 테스트(하이라이트·`focusRectPt` 좌표)와 T1 `unit/page_size_policy_test.dart`에 s ≠ 1 경우 |
| PDF-2-5 | 계약 C11-11·13·01 | 5.5에 '정적 자산 URL은 `document.baseURI` 기준(계약 7.4.3 v1.1) — 이미 그렇게 함' 한 줄. 7.3.3 사본 표의 `syncBadgeProvider` 값에 `.distinct()`. 4.4 세션 사용에서 리스너 안 `execute` 금지를 N-2 인용으로 |
| PDF-2-6 | 계약 | 12.2 Q1 '해결 — INFRA 01-infra I9 앱 정보에 오픈소스 라이선스(`showLicensePage`) 있음', Q2 '해결 — LIBRARY 채택(05-library 6.15.3)', Q3 '해결 — 07-sync 6.9.3·T12로 확인', Q4 '사용자 확인 대기(U1), 기본 진행'. 5.4 L-4의 '(LIBRARY-O1, 선택)' → 'LIBRARY 채택(05-library 6.15.3)', 11절 '동기화로 들어온 PDF 노트의 표지' 행도 같게(담당 권장 1·2). 13장에 2차 반영 표 |
| PDF-2-7 | 권장 | (담당 권장 4) 5.1·5.2·5.3 '글자 그대로 발췌'에서 표시 없이 빠진 멤버에 `// ...`(PageSize 프리셋·방향 멤버, `InkVectorPath.bounds`·`toUiPath`, `InkExportOptions` 필드, `InkFillShape.strokeId`·`tool`, `InkHighlighterLine.strokeId`, `InkPageVectors.bounds`, `InkVectorExport.exportStrokes`, `EditorMenuItem`의 `@immutable`) |
| PDF-2-8 | 권장 | (담당 권장 6·7·8) 4.12 첫 문단: 'PDF 소유 provider 중 루트 override는 `pdfIoConfigProvider` 하나(그 밖에 `pdfIoOverrides()`가 `ink.pageBackgroundBuildersProvider`를 override)'. 6.13(또는 6.14 앞)에 계약 7.4.5 보고 규칙(6.3 6단계 표지 실패, 6.6 `ensureLocal` 예외, 합성·렌더 엔진 오류 → `FlutterError.reportError(... library: 'pdf_io')`, 사용자 문구는 6.14만). 5.1 C-9는 'CORE 02-core 6.13에 이미 정의된 동작의 확인(새 요구 아님)' 표시 |

#### 2.4.7 SYNC — 미승인

| # | 종류 | 지시 |
|---|---|---|
| SYNC-2-1 | 필수 (계약 C11-22) | (담당 필수 1, 총괄 방법 결정) `lib/testing.dart`가 순수 Dart·lint 규칙을 깨지 않게: **`fake_async`를 lib에서 쓰지 않는다**(의존 변경 없음). `SyncTestHarness`는 `Clock`과 시간 진행 콜백(`elapse(Duration)`·`flushMicrotasks()`)을 받는다. `syncScenario`는 `test/scenarios/support/sync_scenario.dart`(test 전용, `fakeAsync`로 harness를 만듦)로 옮긴다. `expectConverged`는 matcher 없이 차이를 담은 예외를 던지는 `checkConverged`(lib)로 바꾸거나 test 지원 파일로. 4.0 export 표, 4.11, T6·T13·T14(`api_surface_test`), 9.1.1 문구 같이 |
| SYNC-2-2 | 필수 (계약 C11-05) | (담당 필수 2) 받기 먼저(D7)에서 보내지 않은 로컬 purge가 되살아나는 문제: ① 6.3.4 `local == null && pending != null`이면 `KeepLocal()`(CORE는 purge 대기 항목에 `{'*'}`를 넘김 — 계약 7.2.10 v1.1) ② 연결 시(6.10.3 6단계)와 로컬 purge 때 outbox의 op purge 항목을 영구 삭제 집합(메모리 뷰)에 먼저 넣음 ③ `RecordGate`(6.3.5)가 영구 삭제된 노트의 하위 기록(page·stroke·recording, `noteId` ∈ 집합)도 버림(CORE S-4 고아 허용으로 쓰레기 행이 생기는 것 방지) ④ 시나리오 S08b(A 오프라인 purge, B 오프라인 편집, A 받기 먼저 → A purge 유지·전송, B 복구 사본)와 T4 `merge/sync_merge_policy_test.dart` 케이스. `FakeLocalStore`도 purge 대기의 `pending = {'*'}`을 같게 |
| SYNC-2-3 | 필수 | (담당 필수 3) 6.6.3 7~8단계·4.9 `MergeRecorder`: 호출마다 임시 맵에 기록하고 `applyRemote`가 성공 반환한 뒤에만 묶음 결과에 합침, 실패·롤백 호출 기록은 버림, 8단계 검사는 적용 묶음(6단계)마다 모든 조각이 끝난 뒤 합친 결과로 한 번(예: `beginCall()/commitCall()/discardCall()`). T9 `download_pipeline_test`에 '이분된 묶음의 앞 조각에서 created된 획 → 되살림이 일어남' |
| SYNC-2-4 | 필수(작음) | (담당 필수 4) 6.2.5 K2·6.13·T9: 압축(6.13 `deleteChunks`)으로 지워진 보류 청크는 `getChunks` 결과에 없다 → `sync.held`에서 지우고 문제를 다시 계산. 그 기록은 압축 스냅숏 청크(새 serverTime)에 들어 있어 다시 받을 때 K1로 다시 판정. T9 `engine/held_chunks_test.dart` 케이스 |
| SYNC-2-5 | 계약 C11-07 | 12.2 SYNC-CP1 '승인' + 12.3 Q-N2 '승인'(계약 7.2.10 v1.1). 6.2.5 K1·K2(해제 = `min(serverNow(), 벽시계) ≥ releaseAt`)·K3(업로드·받기 모두 멈춤), 6.3.5 표 행, T4 `merge/record_gate_test.dart` 경계값, S14b에 '받는 기기가 늦은' 변형 |
| SYNC-2-6 | 계약 C11-03 | 12.2 SYNC-CP2 '승인'. 5.1.2 S-12를 계약 7.2.10 v1.1 인용으로, 5.1.4 계약 스위트에 C-25(원격·복구 쓰기 뒤 로컬 필드 보존·재계산), `FakeLocalStore`도 같은 의미 |
| SYNC-2-7 | 계약 C11-04 | (담당 권장 3 대체) 5.1.4 C-22·C-23의 `origin: local` 근거를 '계약 7.2.10 v1.1'로(CP-5 승인됨 — 'CP-5 승인 조건' 표시·S-9 대안 문장 삭제). 12.2 '다른 영역 제안 의견'의 CP-4·CP-5 줄을 결정으로 갱신 |
| SYNC-2-8 | 계약 C11-22·13·30 | 12.2 SYNC-CP0·CP3·CP4 '승인'. (담당 권장 1) 4.4·4.5 상태 값 클래스(`SyncStatus`, `SyncIssue`, `AuthState`, `AssetAvailability`, `AssetTransferSummary`, `InitialSyncProgress`)에 `==`/`hashCode`(컬렉션은 collection Equality) — 시그니처 주석과 T 작업 테스트 1건. 4.4.1·5.2의 override 값에 `.distinct()`. 9.1.3 T16 태그 `integration` 확인 |
| SYNC-2-9 | 계약 | 12.3 Q-N1 '승인 — 안내 문구는 M4 INFRA 계정·동기화 섹션, HLC는 되돌리지 않음'. 13장에 2차 반영 표 |
| SYNC-2-10 | 권장 | (담당 권장 2) 3·6.4.4 코덱 바이트 골든을 계약 7.4.8대로 `test/goldens/chunk_v1_golden.bin` + `@Tags(['golden'])` + `@TestOn('vm')`로(CORE `test/goldens/json/`과 같은 방식). 아니면 '이미지 골든이 아닌 바이트 픽스처라 `test/fixtures`'를 근거와 함께 명시하고 `@TestOn('vm')`은 유지 |

### 2.5 사용자 확인 항목 (변동 없음)

4장 U1~U4 그대로. INK 12.2 Q3(악보 12단·주간 플래너 2×4 기본 배치)은 '기본값으로 시작, iPad 확인 #12 피드백으로 조정'으로 사용자 확인 없이 진행한다.

### 2.6 다음 단계

1. 7개 영역이 2.4의 [필수]·[계약]을 반영하고 13장에 '2차 반영 내역'(지시 번호 인용)을 남긴다. [권장]·[사소]도 가능한 한 함께.
2. 총괄 3차 검토: 지시 번호별 diff 확인 → 모두 해결되면 이 문서에 '최종 승인' 절을 추가하고 00-overview 상태를 '확정 — 개발 시작 가능'으로 바꾼다.
3. 계약을 더 바꿀 일이 생기면 7.4.12 절차(v1.2)로. 3차 수정에서 계약과 다르게 쓰지 않는다.

---

## 3차 검토 (승인 검토)

> 날짜: 2026-11-05 · 대상: 01~07 2차 수정본(각 계획서 13.2 — 00-review '2차 검토' 2.4 지시 반영본) · 방식: 영역별 승인 검토 담당 7명의 판정을 총괄이 종합하고, 판정 근거가 된 계획서 줄과 영역 사이 의존(쓰기 `Future` 완료 시점, B4 자리표시 provider, 태그 선언)을 총괄이 직접 다시 확인 · 결과: **통합 계약 v1.2**([00-overview.md 7.9](00-overview.md#79-계약-변경-이력) C12-01~09), **EDITOR·LIBRARY 승인**, INFRA·CORE·INK·PDF·SYNC는 3차 수정(각 계획서 13.3) 후 재승인

### 3.1 판정 요약

| 영역 | 담당 판정 | 총괄 최종 | 사유 | 3차 수정 규모 |
|---|---|---|---|---|
| INFRA | 승인 | **미승인 (계약 반영)** | 필수 결함 없음. INFRA가 낸 P5(R15를 B1부터)를 수용해 계획서 5곳이 바뀌고, C12-06(B4 통계 provider)으로 권장 1이 계약 쪽에서 풀림 | 작음 |
| CORE | 승인 | **미승인 (계약 반영)** | 필수 결함 없음. CP-7 수용(C12-02)에 따라 6.10.4 `commitRepairs` 규칙 1줄이 필요하고, PDF-3-1의 근거인 완료 시점 문구(C12-09)를 CORE 주석·`put`에 맞춰야 함 | 작음 |
| INK | 승인 | **미승인 (계약 반영)** | 필수 결함 없음. INK P4 수용(C12-03)으로 4.13 provider 주석 1줄이 계약과 달라짐 + 10절 R15 표기 | 아주 작음 |
| EDITOR | 승인 | **승인** | 필수·계약 결함 없음. v1.2 변경 중 EDITOR 계획서를 바꿔야 하는 것이 없음(C12-01·03·09 확인 — 3.4.4). 권장·사소 2건은 구현 때 3.4.4대로 | — |
| LIBRARY | 승인 | **승인** | 필수·계약 결함 없음. v1.2 변경 중 LIBRARY 계획서를 바꿔야 하는 것이 없음(C12-01·02·09 확인 — 3.4.5). 사소 3건은 구현 때 3.4.5대로 | — |
| PDF | 미승인 | 미승인 | 필수 3건(저장 실패를 예외로 가정, 상태 클래스 값 동등 누락, B4 통계 provider — 총괄이 권장 → 필수) + 계약 반영 | 중간 |
| SYNC | 미승인 | 미승인 | 필수 2건(배지 동등 문장 오류, 압축 데이터 손실) + 계약 반영 | 중간 |

전체 평가

- 2차 지시([필수]·[계약])는 7개 영역 모두 반영됐다(담당 확인, 총괄 표본 확인: 각 계획서 13.2 표, `dart_test.yaml`이 7개 계획서 전부에 있고 각 영역이 쓰는 태그 = 선언한 태그 — `grep @Tags` 대조).
- 이번에 새로 드러난 결함은 두 종류다. ① **CORE 쓰기 재시도의 의미를 소비하는 쪽이 놓침**(PDF가 저장 실패를 `storageFailed` 예외로 기대 — CORE는 무한 재시도하며 `Future`를 끝내지 않음). 2차에 LIBRARY Q-L1로 CORE 4.5 머리말에 적었지만 계약 본문에는 요약이 없어 PDF가 따라가지 못했다 → 계약 7.2.9에 요약을 올렸다(C12-09). ② **영역 내부 알고리즘의 데이터 손실 경로**(SYNC 압축이 자기 스냅숏을 건너뛰는 규칙·해석 못 하는 청크 삭제).
- 계약은 v1.2로 올렸다(9항목). **시그니처 변경은 없다.** 5건은 담당 제안(INFRA P5, CORE CP-7, INK P4, SYNC-CP5·CP6), 4건은 총괄이 검토에서 드러난 모호함을 정한 것(C12-06~09).

### 3.2 계약 변경 결정

| 제안 | 낸 영역 | 결정 | 근거·조정 | 계약 반영 |
|---|---|---|---|---|
| INFRA P5 | INFRA | **수용** | C11-26은 2차에서 EDITOR·LIBRARY가 실제로 빠뜨린 규칙이다. R15를 I1에서 만들면 INFRA 병합(통합 4번째) 뒤에야 전 멤버에 적용된다. 총괄 확인: B1 시점에는 태그를 쓰는 테스트가 없고, PDF를 뺀 6개 계획서는 태그를 쓰는 첫 테스트보다 먼저 `dart_test.yaml`을 만든다(CORE T0, INK T01, EDITOR E-00, LIBRARY B6, SYNC T1, INFRA I12). PDF는 파일 내용(9.1)은 있으나 만드는 작업이 8장에 없어 PDF-3-8로 배정. 모든 태그가 리터럴이다(`grep` 확인). 담당 조건 둘(B1부터 위반 = 종료 1, 리터럴만 인식한다는 제약을 7.4.8에)을 그대로 넣었다 | 7.4.2, 7.4.8, 7.6 B1, 7.7 V1 (C12-01) |
| INFRA P1~P4 | INFRA | 이미 수용(v1.1 C11-28·08·11·29) | 담당이 계획서 반영을 확인함. 할 일 없음 | — |
| CORE CP-7 | CORE | **수용 + 보충** | 원격 획 JSON에는 `noteId`가 없고 고아를 허용하므로(S-4) '항상 채움'을 지키는 방법은 페이지가 도착하는 커밋으로 미루는 것뿐이다. CORE 4.8.1·6.10.3이 이미 그렇게 쓴다. 보충: 담당 사소 5대로 '페이지 행을 만드는 `commitRepairs`'도 그 커밋에 포함 | 7.2.10 (C12-02) |
| INK P4 | INK | **수용** | 같은 절 `InkPageThumbnail` 주석(C11-19)과 provider 주석('Read by … INK thumbnails')이 반대로 읽히는 실제 모순. 제안 문구가 03-ink 4.13 정의와 같다. 의미 변경 없음 | 7.2.16 (C12-03) |
| EDITOR CP-E1~E3 | EDITOR | 이미 수용(v1.1 C11-21·25·14) | 담당이 계획서·테스트 반영을 확인함 | — |
| LIBRARY CP-L1~L3 | LIBRARY | 이미 수용(v1.1 C11-29·09·27·12) | 담당이 계획서 반영을 확인함 | — |
| PDF P1 | PDF | 이미 수용(v1.1 C11-18) | 담당이 4.7·5.2·K-7·6.9 문구가 계약과 같음을 확인함 | — |
| SYNC-CP5 | SYNC | **수용** | `AuthState.user`·`SyncStatus.user`가 `AuthUser`라 이것이 값 동등이 아니면 두 클래스의 값 동등과 INFRA `.distinct()`가 성립하지 않는다. 7.4.4 범위 명시일 뿐 | 7.2.20 (C12-04) |
| SYNC-CP6 | SYNC | **수용** | 가짜와 실제 CORE의 의미 차이를 잡는 핵심 검사(계약 스위트)가 7.7 문구에 없어 '통합 완료' 판정에서 빠질 수 있다. 명령·태그는 같다 | 7.7 5단계 (C12-05) |
| SYNC-CP7 (담당 권장으로 제안 예정) | SYNC | **보류(방향 승인)** | `SyncEngine(log:)`를 앱 셸이 넣을 자리가 없다는 지적은 맞다. 이번 범위(앱이 `sync_engine`에 의존하지 않음)에는 영향이 없으므로 7.3.3 표 반영은 M4 연결 계획 때. 방향: SYNC 소유 선택 자리 `syncLogSinkProvider`(기본 `null`)를 INFRA `SyncModule`이 override | — (7.9 v1.2 '보류'에 기록) |

총괄이 이번에 직접 넣은 계약 항목(제안 없이, 검토에서 드러난 모호함 해소)

| # | 내용 | 계기 |
|---|---|---|
| C12-06 (7.6 B4) | 다른 영역이 기반 단계·동시 개발 중 읽는 PDF provider(`pdfIoOverrides()` 대상, `pdfRenderStatsProvider`)는 B4에서도 예외 없이 만들어진다. `pdfRenderStatsProvider` B4 본문 = `ValueNotifier(PdfRenderStats.zero)` | PDF 담당 PDF-3-3과 INFRA 담당 권장 1이 같은 결함을 양쪽에서 봄. 지금 계약 B4 행은 '본문 `UnimplementedError` 허용'이라 INFRA 브랜치의 `feature_wiring_module_test`(`pdf.render` 섹션)가 B4 PDF로 예외를 낸다. 2차 PDF-2-2(빌더 provider)와 같은 종류라 같은 방식으로 계약에 적었다 → INFRA 쪽 테스트 우회(주입 함수·테스트 override)는 필요 없음 |
| C12-07 (7.4.11) | 색 하드코딩 예외에 PDF 검색 하이라이트(`PdfTuning` 상수 한 곳) | PDF 담당 PDF-3-5가 '테마 색으로 바꾸거나 계약 예외 제안' 두 안을 냄. 총괄 결정: 하이라이트는 종이 위에 겹치는 표시라 기준은 UI 테마가 아니라 종이와의 대비다(종이 팔레트 예외와 같은 이유, 다크 모드가 와도 종이 위 색은 테마를 따르지 않아야 함). PDF 계획서의 현재 설계를 유지하고 근거만 계약으로 |
| C12-08 (7.6) | B3~B7: CORE T4 뒤 작업 트리에서 미리 작성 가능, main 커밋·완료 조건은 B2(T1~T5) 완료 뒤, B4·B5는 B3 뒤 | CORE 담당 권장 3. '계약 파일이 커밋되면 병렬'과 '각 단계 통과 뒤 다음 단계'가 T4/T5 사이에서 두 가지로 읽혔다. B5·B6 스모크 테스트는 `createFakeNoteStore`(T5)가 있어야 돈다 |
| C12-09 (7.2.9, 7.2.11) | 쓰기 `Future` 완료 시점 요약(커밋 뒤 완료, 재시도 중에는 완료도 오류도 없음, 인자·상태 오류만 재시도 없이 오류) + `AssetStore.put`의 청크 쓰기 실패는 즉시 오류·메타 없음 | PDF-3-1. CORE 4.5 머리말(2차 CORE-2-17)은 이미 계약이지만 7.2.9 본문에 요약이 없어 PDF가 놓쳤다. `put`은 CORE 4.5 머리말 범위(4.5 저장소) 밖이라 CORE 4.7·6.13 서술('중간 실패 시 고아 청크만')을 계약 문장으로 고정했다. 기다리는 화면 처리는 각 영역 몫으로 두고 현재 EDITOR 동작(뒤로가기 무기한 대기 + '저장하는 중…')을 그대로 인정했다(3.3) |

기각: 없음.

### 3.3 담당 판정에 대한 총괄 조정

| 영역 | 조정 | 근거 (총괄 직접 확인) |
|---|---|---|
| INFRA | 담당 '승인'은 계획서 자체로는 타당. INFRA P5 수용으로 계획서 1.2·6.2·8.1 B1-4·8.2 I1·10절 7이 바뀌므로 규칙대로 **미승인**. 담당 권장 1(통계 provider)은 C12-06으로 PDF 쪽에서 고치므로 INFRA는 5.7·9.1 문장만. **총괄 추가 권장 1건**(INFRA-3-3): 백업 준비 대기 | 01-infra 2115행('B1에는 넣지 않고 I1에서'), 2651행 B1-4 `check(R1–R3·R7–R9)`, 1401행 `prepareBackup` = `flush` → `exportBackupJson`(둘 다 재시도 중 미완료 — 계약 7.2.12 'Flushes first') |
| CORE | 담당 '승인'은 계획서 자체로는 타당. CP-7 수용·C12-09로 CORE 문구 몇 줄이 바뀌므로 **미승인**. 담당 권장 1(완료 시점 문구)을 [계약]으로 올림(PDF-3-1의 근거). 담당 권장 2의 권장안(purge 항목 + `TakeRemote` → purge 항목 삭제)을 **총괄 결정**으로 채택 | 02-core 1371행 'complete them at once', 1294행 상태 오류 목록의 `LastPageDeletionException`, 2728행 '지우거나 … 바꿈', 3222행 T4 메모, 3345행 10절 7 |
| INK | 담당 '승인' 타당. P4 수용으로 4.13 한 줄이 계약과 달라지므로 **미승인**(사소 3건과 함께 한 번에) | 03-ink 1656~1657행, 2787행 'ws check(R1~R13)' |
| EDITOR | 담당 '승인' 유지. v1.2 영향 확인: C12-01(E-00 `dart_test.yaml`, 리터럴 태그), C12-03(5.2.1·6.11.3이 이미 `backgroundBuilders: ref.watch(...)`를 넘김), C12-09(6.17.4 '시간 제한으로 끊지 않음, 300 ms 뒤 저장하는 중…' = 계약 요약과 같음). 담당 권장 1(5.1.3 표 '호출' 열)은 표 바로 아래 '`CORE를 부르는 곳은 이 셋뿐`' 문장과 6.6.4·6.11.4가 기준이라 문서 불일치일 뿐 설계 결함이 아님 → 재승인 조건 아님, 구현 규칙으로 3.4.4에 고정 | 04-editor 866~870행(표), 877행(규칙 문장), 2938행(뒤로가기) |
| EDITOR(알려진 한계, 결함 아님) | 저장 실패가 계속되면 에디터 뒤로가기가 '저장하는 중…'에서 계속 기다린다(탈출 = 탭 새로고침). '기다리지 않고 나가기'를 두려면 CORE가 '닫히는 중인 세션(마지막 `close()`의 flush 대기)에 `openSession`이 다시 오는 경우'를 정해야 해서 이번에는 넣지 않는다. iPad에서 문제가 되면 7.4.12 절차로 CORE·EDITOR 함께 제안 | 02-core 3020행('0이 되면 `flush()` 후 메모리 해제'), 04-editor 2938행 |
| LIBRARY | 담당 '승인' 유지. v1.2 영향 확인: C12-01(B6 `dart_test.yaml`, 리터럴 태그), C12-02(6.15.3이 인용한 CORE 4.8.1 동작이 그대로 계약 문장이 됨 — 인용 유효), C12-09(6.11 '둘 다 견딤' — 대화상자 즉시 닫기, 결과 표시는 완료 뒤). 담당 사소 2(저장 실패 배너 테스트 위치)는 총괄이 (b)로 정함(3.4.5) | 05-library 1995행(6.11), 2247행 6.15.3, 2542행 B6 |
| PDF | 담당 필수 2건 확인(1: 02-core 1293행 '재시도 중에는 완료되지 않는다' vs 06-pdf 544·550·567·724행 `storageFailed`, 2: `grep 'operator ==' 06-pdf.md` = 0). **담당 권장 PDF-3-3을 필수로 올림**(C12-06, 2차 PDF-2-2와 같은 종류 — INFRA 브랜치 테스트가 깨짐). 담당 PDF-3-5는 총괄이 '계약 예외'로 결정(C12-07) → PDF 설계 변경 없음, 인용만. 담당이 다루지 않은 C12-01 영향: `dart_test.yaml`을 만드는 작업이 8장에 없음 | 06-pdf 1409~1410행, 1573~1574행, 177행, 2840~2842행(T0~T2), 2871행 |
| SYNC | 담당 필수 2건 확인(1: 4.4.1 표 `pendingChanges = status.pendingUploads` vs 708행 '대기 수·진행률만 바뀐 상태 발행은 배지 이벤트를 내지 않는다', 2: 6.6.3 2단계 '`by == deviceNodeId` → 디코드 없이 건너뜀' + 6.13 4단계 `deleteChunks(ids of R)`가 해석 못 한 청크까지 지움 — 모든 기기 데이터 손실 경로). 담당 권장 3건 동의 | 07-sync 701~708행, 2243행(6.6.3 2단계), 2576~2584행(6.13 1·4단계) |

### 3.4 영역별 남은 문제 (3차 수정 지시)

표기: **[필수]** 재승인 조건 · **[계약]** 통합 계약 v1.2를 계획서에 반영(재승인 조건) · **[권장]** · **[사소]** · **[절차]**. 지시 번호는 `<영역>-3-<n>`. 각 영역은 13장에 '13.3 3차 수정' 표를 만들어 지시 번호를 그대로 인용하고, 계약 인용은 'v1.2(C12-xx)'로 적는다. 승인된 영역(EDITOR·LIBRARY)은 계획서를 고치지 않고, 3.4.4·3.4.5의 항목을 해당 작업 구현 때 이 문서 기준으로 따른다.

#### 3.4.1 INFRA — 미승인 (계약 반영)

| # | 종류 | 지시 |
|---|---|---|
| INFRA-3-1 | 계약 C12-01 | (P5 승인) R15를 기반 단계 B1로 옮긴다: 1.2 B1 설명 'check R1–R3·R7–R9' → '·R15'. 6.2 R15 아래 문단의 'B1에는 넣지 않고 I1에서 만든다 … 12.3 P5로 제안한다' → 'B1-4에서 만든다(계약 7.6 B1 v1.2) — 각 영역 브랜치의 `ws check`가 선언 누락을 위반(종료 1)으로 잡는다'. 리터럴만 인식한다는 제약은 계약 7.4.8 v1.2 인용으로. 8.1 B1-4에 `tool/src/test_tags.dart`·`workspace_rules.yaml` `skip_by_default_tags`·`tool/test/test_tags_test.dart`(9.1 행 그대로)를 산출물·완료 조건으로, 8.2 I1의 R15는 'B1-4에서 완료'로. 10절 7 'V1(`ws check` R1–R14 — INFRA는 R15도 0)' → '계약 V1 R1~R15'. 11절 C11-26 행 대응 문구에서 '전 멤버 적용은 INFRA 병합 뒤, 12.3 P5로 B1 선적용 제안' 삭제. 12.3 P5 결정 '승인 — 계약 v1.2 C12-01' |
| INFRA-3-2 | 계약 C12-06 | (담당 권장 1 해결) 계약 7.6 B4 v1.2로 PDF B4의 `pdfRenderStatsProvider`가 `ValueNotifier(PdfRenderStats.zero)`가 된다 → 4.5.9 `FeatureWiringModule`·`pdfRenderStatsSection(ref)`는 지금 모양 유지(주입 함수 불필요). 5.7 '가짜 PDF 동작' 행에 'PDF T8 전(B4): `pdfRenderStatsProvider` = 0 통계 notifier(계약 7.6 B4 v1.2) — 테스트 컨테이너에 따로 override하지 않음'. 9.1 `feature_wiring_module_test`·`pdf_wiring_test`에 '모듈 overrides만 넣은 컨테이너에서 `devOverlaySectionsProvider`의 `pdf.render` 섹션을 만들고 `lines` 값을 읽어도 예외 없음' 단언 |
| INFRA-3-3 | 권장 (C12-09, 총괄 추가) | 4.5.8 `prepareBackup`: `flush()`와 `exportBackupJson()`(먼저 flush함)은 쓰기 실패 재시도 중 끝나지 않는다(계약 7.2.9 v1.2). 진행 표시에 '취소'(대기만 끊고 `null`, errorLog 없음 — 쓰기 큐는 그대로)와, `storageWarningOf == writeFailing`이면 '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.' 한 줄. `about_section_test`에 '`CountingNoteStore` flush 미완료(끝나지 않는 Completer) → 취소 → 버튼 다시 활성, 스낵바 없음' 1건 |
| INFRA-3-4 | 사소 | (담당 사소 1) 8.1 B8-1 비고: '`main.dart`의 `openNoteStore(const NoteStoreConfig())`(상대 경로)는 임시 진입점 — 배포 없음(B1·B8 CI는 배포하지 않음), I5에서 `runNoteApp`·`defaultNoteStoreConfig`(절대 URL, 계약 7.4.3)로 교체' |
| INFRA-3-5 | 사소 | (담당 사소 2) 8.3 G2 V6 단락·9.1 `app_smoke_browser_test`: 테스트마다 다른 `databaseName`과 `WebStorageConfig.blobDatabaseName`(기본 `'noteapp_blobs'`, 02-core 4.8). `NoteStoreConfig`에는 `copyWith`가 없으므로 테스트가 `NoteStoreConfig(web: WebStorageConfig(sqlite3WasmPath: …, driftWorkerPath: …, blobDatabaseName: …), databaseName: …)`를 직접 만든다 |
| INFRA-3-6 | 절차 | 13장 '13.3 3차 수정' 표, 머리 상태 줄(v0.4, 계약 v1.2). 1.2·5.1·6.2의 계약 인용을 v1.2로 맞춘다 |

#### 3.4.2 CORE — 미승인 (계약 반영)

| # | 종류 | 지시 |
|---|---|---|
| CORE-3-1 | 계약 C12-02 | (CP-7 승인 + 담당 사소 5) 6.10.4 `commitRepairs`: 현재 행이 없어 페이지 행을 `*`로 새로 쓰는 경우에도 6.10.3과 같이 그 페이지의 고아 획 `strokes.note_id`를 채우고 그 획들의 `EntityChange`(`noteId`·`pageId`)를 이 커밋 batch에 넣는다. 4.8.1 `ChangeBatch.changes` 주석의 'the commit that brings its page'에 '(applyRemote, or commitRepairs creating the row)'. 12.2 CP-7 '승인 — 계약 7.2.10 v1.2(C12-02)'. 9.1 `commit_repairs_test`에 '고아 획 적용 → 그 페이지 행을 만드는 `commitRepairs` → 그 batch에 획의 `EntityChange`(noteId·pageId)' 1건 |
| CORE-3-2 | 계약 C12-09 | (담당 권장 1, 총괄이 [계약]으로) 완료 시점 문구 통일: `LibraryRepository` 문서 주석(1371행) → `/// ArgumentError completes them before enqueue; FolderCycleException / EntityNotFoundException inside the transaction (after earlier queued writes) — never retried, nothing changed (4.5 head, 7.2.9 v1.2).` 5.4 L-5+·13.2 CORE-2-17 행의 '즉시' → '재시도 없이(인자 오류는 큐 전, 상태 오류는 그 트랜잭션에서)'. 4.5 머리말 상태 오류 목록에서 `LastPageDeletionException` 삭제(세션 `DeletePages` 예외 — 6.5, 저장소 메서드는 던지지 않음). 4.7 `AssetStore.put` 주석과 6.13 `put` bullet에 계약 7.2.11 v1.2 문장(청크 쓰기 실패 = 재시도 없이 그 오류로 즉시 완료·메타 행 없음, 메타 커밋은 4.5 머리말 규칙). 6.19 가짜: `put`의 메타 쓰기도 커밋 1건으로 센다(`failNextCommits` 대상 — PDF-3-1 테스트가 기대). `asset_store_test`에 'BlobStore 쓰기 실패 주입 → `put`이 그 오류로 완료, `getAsset` null, `bytesArrived` 없음' 1건 |
| CORE-3-3 | 권장 (총괄 결정) | (담당 권장 2) 6.10.3: 대기 항목이 `op: purge`인데 정책이 `TakeRemote`를 돌려주면(`dropPendingLocal` 값과 무관 — 행이 되살아났으므로) 행을 쓰고 purge 항목은 **삭제**, `WriteMerged`면 purge 항목을 `fieldsToUpload`의 upsert 항목으로 바꾼다(비면 삭제, seq 유지·rev 증가). 2728행 '지우거나 … 바꿈'을 이 규칙으로. 9.1 `sync_store_test` pendingLocalFields 행에 'purge 대기 + `TakeRemote(dropPendingLocal: false)` → 행 있음, 그 엔티티의 outbox 항목 없음' 1건 |
| CORE-3-4 | 계약 C12-08 | (담당 권장 3) 8.1 순서 메모 'T4(계약 고정, B3~B7이 이 시점부터 병렬 가능 — 7.6)' → 'T4 커밋 뒤 다른 영역은 작업 트리에서 코드 작성을 시작할 수 있고, B3~B7의 main 커밋·완료 조건(스모크 테스트)은 B2(T1~T5) 완료 뒤(계약 7.6 v1.2)' |
| CORE-3-5 | 계약 C12-05 | 10절 7 'SYNC T16(실제 CORE 2개로 S01·S02·S05·S15 + JSON 키 대조)'에 '+ SyncStore 계약 스위트 C-01~C-25(`CoreSyncLocalStore(openTestNoteStore)`) + 폴더 순환 판정 대조'(계약 7.7 5단계 v1.2) |
| CORE-3-6 | 사소 | (담당 사소 1) 5.1 `CoreModule` 예시 블록의 `open(const NoteStoreConfig())`(상대 경로 — I-11·계약 7.4.3과 어긋남): 01-infra 4.5.9 형태(`configFor = defaultNoteStoreConfig`, `start(): store = await open(configFor(context)) // web: absolute URLs resolved against document.baseURI (I-11)`, `onResetLocalData(): await deleteLocalData(config)`)로, 또는 'abbreviated, see 01-infra 4.5.9'를 달고 인자만 `configFor(context)` |
| CORE-3-7 | 사소 | (담당 사소 3) 5.3 E-5+ device 목록 = 계약 7.4.6 v1.1 목록 그대로(`stylusSeen`·개발자 표시 포함) 또는 '7.4.6 목록 그대로' 인용 |
| CORE-3-8 | 절차 | 13장 '13.3 3차 수정' 표, 머리 상태 줄(계약 v1.2) |

#### 3.4.3 INK — 미승인 (계약 반영)

| # | 종류 | 지시 |
|---|---|---|
| INK-3-1 | 계약 C12-03 | (P4 승인) 4.13 `pageBackgroundBuildersProvider` 주석 첫 줄을 계약 7.2.16 v1.2 문구(`/// Read by inkPageControllerProvider and inkPageThumbnailRendererProvider; callers of` / `/// InkPageThumbnail pass its value (the widget reads no provider).`)로, '// contract 7.2.16 (doc wording: 12.1 P4)' 표시는 '// contract 7.2.16 v1.2'로. 12.1 P4 결정 '승인 — 계약 v1.2 C12-03' |
| INK-3-2 | 계약 C12-01 | (담당 사소 3 포함) 10절 2 '`ws check`(R1~R13) 위반 0' → 'R1~R13·R15 위반 0(R15는 B1부터 — 3장 `dart_test.yaml`), 통합 단계 R14는 4.0 `show` 목록 + `testing.dart`·`dev_tools.dart` 이름(5.5)으로 검사' |
| INK-3-3 | 사소 | (담당 사소 1) 3장 'CORE 객체 생성 지점' 예외 목록에 ④ '`InkPageThumbnailRenderer.render`의 결과 `core.PageThumbnail`'을 추가하거나, 6.23 함수표에 `core.PageThumbnail thumbnailOf(core.Page page, {required int width, required int height, required Uint8List png})`를 넣고 6.17 4단계가 그것을 부른다고 |
| INK-3-4 | 사소(선택) | (담당 사소 2) 4.8 세션 3종 앞 INK 보충 주석 끝을 '(…; the device scale reaches setViewport through InkPageView, never from EDITOR)'로(계약 줄 2개는 그대로) |
| INK-3-5 | 절차 | 13장 '13.3 3차 수정' 표, 머리 상태 줄(v0.4, 계약 v1.2) |

#### 3.4.4 EDITOR — 승인 (구현 때 따를 것, 계획서 수정 없음)

| # | 종류 | 내용 |
|---|---|---|
| EDITOR-3-1 | 권장 (구현 규칙) | (담당 권장 1) 5.1.3 매핑 표의 '호출' 열보다 표 아래 문장('CORE를 부르는 곳은 `_run`·`_runAsync`·`_runHistory` 셋뿐')이 우선한다: '현재 페이지 전체 지우기'·'페이지 추가'·'페이지 복제' = `_runAsync` → `session.executeAsync`, '페이지 삭제'·'페이지 이동' = `_run` → `session.execute`(6.8 `EditorCommands.deletePages`·`movePage`도 `_run` 경유 — 읽기 전용 경합의 `ReadOnlyNoteException`을 잡음, N-4 v1.1). E-17 `page_panel_test`에 `rejectNext` 주입 → 삭제 거부, 예외가 버튼 핸들러 밖으로 나가지 않음 1건 |
| EDITOR-3-2 | 사소 (구현 규칙) | (담당 사소 1) 12.3 Q-E1 결과 칸의 'id·크기·배경이 같으면'보다 6.3.4 `updatePages`·6.4.3 슬롯 키 `(page.id, page.size, settledScale)`·6.13.2 표('id 순서·크기가 같으면 레이아웃을 다시 계산하지 않음, 배경 변경은 `pageChanges` → INK 컨트롤러')가 기준 |
| EDITOR-3-3 | 확인 (변경 없음) | 계약 v1.2: C12-01(E-00 `dart_test.yaml`, 태그 리터럴 — 맞음), C12-03(이미 호출자가 provider 값을 넘김), C12-09(6.17.4 뒤로가기 = 계약 요약과 같음). 알려진 한계(저장 실패 지속 시 뒤로가기 대기)는 3.3 |

#### 3.4.5 LIBRARY — 승인 (구현 때 따를 것, 계획서 수정 없음)

| # | 종류 | 내용 |
|---|---|---|
| LIBRARY-3-1 | 사소 (구현 규칙) | (담당 사소 1) 5.1.2 `AssetStore` 발췌의 `markUploaded` 주석은 CORE 4.7 원문(`Records {storagePath} in the outbox and publishes ChangeBatch(origin: local) (7.2.10 v1.1).`)이 기준. LIBRARY는 `markUploaded`를 쓰지 않아 구현 영향 없음 |
| LIBRARY-3-2 | 사소 (총괄 결정) | (담당 사소 2) 저장 실패 배너 테스트는 **(b)** — L18 `widget/storage_banner_test.dart`의 단독 위젯 테스트(가짜 전용, `faults` 주입, 공유 시나리오 아님). 5.7 표 '저장 경고 배너' 행·L21 ①·13.2의 'needsFaults 시나리오' 표현은 이 결정으로 읽는다. L21의 `where((s) => !s.needsFaults)` 필터는 그대로 두되 지금은 해당 시나리오가 없다 |
| LIBRARY-3-3 | 사소 (구현 규칙) | (담당 사소 3) 3.1 pubspec 블록의 `description:` 문구는 INFRA B1 값을 따른다. B6에서는 의존·버전·형식(계약 7.4.1)만 확인 |
| LIBRARY-3-4 | 확인 (변경 없음) | 계약 v1.2: C12-01(B6 `dart_test.yaml`, 태그 리터럴), C12-02(6.15.3 인용 유효), C12-09(6.11 '둘 다 견딤'. 5.1.4 아래 문단의 '도메인 오류는 즉시'는 '인자 오류는 큐 전, 상태 오류는 앞 쓰기 뒤 그 트랜잭션에서'로 읽는다 — 화면 동작은 같음) |

#### 3.4.6 PDF — 미승인

| # | 종류 | 지시 |
|---|---|---|
| PDF-3-1 | 필수 (계약 C12-09) | (담당 필수 1) PDF는 `createNote`·`flush`가 저장 실패 때 `storageFailed`를 던진다고 가정하지만 CORE는 커밋 실패를 무한 재시도하고 그동안 `Future`를 끝내지 않는다(계약 7.2.9 v1.2 — CORE 4.5 머리말·6.9). 고칠 곳: (a) 4.4 `PdfNoteGateway`의 `putPdf`(메타 커밋)·`createNote`·`flush` 주석과 4.6 `PdfImportSession.commit` 주석에 '커밋 재시도 중에는 완료되지 않음(계약 7.2.9 v1.2)'. `insertPages`는 `receipt.persisted`를 기다리지 않으므로 커밋 실패를 `storageFailed`로 던지지 않는다(세션 열기·페이지 로드가 앞의 대기 쓰기 뒤로 늦어질 수는 있음 — CORE 6.9 `openPage`) — 'Throws … storageFailed'를 지우고 '저장 실패는 `PersistenceStatus`로만(에디터 배너)'으로. `storageFailed`는 CORE가 실제로 던지는 비재시도 오류에만: `AssetStore.put`의 청크 쓰기 실패(계약 7.2.11 v1.2), 그 밖의 `NoteCoreException`. 4절 머리말의 예외 매핑 문장도 같게. (b) 6.11.2 1단계(`flush`)와 6.10.2(검색 전 flush), 5.1 표 '내보내기·검색 읽기': 대기를 `PdfCancelSignal.whenCancelled`와 경쟁(`Future.any`)시켜 취소하면 바로 `cancelled`. (c) 6.3 가져오기 진행 창: `core.persistenceStatusProvider` + `storageWarningOf(...) == writeFailing`이면 '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.'(6.14에 추가)와 '닫기'. 닫은 뒤 동작(작업은 계속, `importPdfAsNewNote`는 `null`, 커밋되면 노트가 라이브러리에 나타남)을 4.11 `runPdfImportFlow`·`importPdfAsNewNote` 주석에. (d) 테스트: T4 `core_gateway_fake_store_test`에 `FakeNoteStoreFaults.failNextCommits(3)` → `createNote` `Future`가 재시도 동안 미완료, 커밋 성공 뒤 완료(fake_async). T15 `export_service_test`에 '커밋 실패 주입 중 flush 대기 → cancel → `cancelled`'. T6 `import_flow_test`에 '실패 주입 → 지연 문구·닫기 → `null`'. (e) 11절 리스크 1행 |
| PDF-3-2 | 필수 (계약 7.4.4) | (담당 필수 2) 4절 상태 클래스에 `==`/`hashCode`가 하나도 없다. `@override bool operator ==(Object other); @override int get hashCode;`를 시그니처로: 4.2 `PdfProgress`·`PdfBatchProgress`·`PdfJobIdle/Running/Succeeded/Failed`, 4.8 `PdfSearchHit`(`rects`는 `ListEquality`)·`PdfSearchState`(`hits`는 `ListEquality`), 4.12 `PdfBatchJobIdle/Running/Finished/Failed`, 4.7 `PdfRenderStats`(`ValueNotifier`가 `==`로 알림을 거름). `PdfIoException`은 `code`·`detail` 기준 동등. 결과 페이로드는 `PdfImportResult`만 값 동등, `PdfExportResult`·`PdfBatchExportResult`는 바이트를 담아 동일 객체 비교라고 주석에. family 키로 쓰는 값 타입이 있으면 그것도 값 동등. 6.13에 '상태 클래스는 값 동등(계약 7.4.4)' 한 줄, T1·T11에 동등 테스트 1건씩 |
| PDF-3-3 | 필수 (계약 C12-06, 총괄이 권장 → 필수) | (담당 권장 3) T0 B4 본문 `pdfRenderStatsProvider = (ref) => ValueNotifier(PdfRenderStats.zero)`(렌더 사슬을 watch하지 않음). 4.12 주석에 B4 본문 / T8 본문(`ref.watch(pdfPageRendererProvider).statsListenable`) 구분. T0 `unit/init_test`에 '`pdfIoOverrides()`만 넣은 컨테이너에서 `pdfRenderStatsProvider` read → 예외 없음, `value == PdfRenderStats.zero`'. 근거: 계약 7.6 B4 v1.2, INFRA `feature_wiring_module_test`가 동시 개발 중 이 provider를 읽는다(2차 PDF-2-2와 같은 종류) |
| PDF-3-4 | 권장 | (담당 권장 4) 4.12 `pdfBackgroundLayerBuilderProvider`의 `renderer: () => ref.read(pdfPageRendererProvider)`는 그 provider의 `ref`를 클로저에 가둔다. '이 provider는 앱 수명 동안 다시 만들어지지 않는다 — watch 대상 `pdfSearchHighlightsProvider`는 `ref.listen`만 하므로 안정'을 주석에, T17 `providers_test`에 '검색 시작·선택·지우기 뒤에도 `pdfBackgroundLayerBuilderProvider` 인스턴스가 같다' 단언 |
| PDF-3-5 | 계약 C12-07 | (담당 권장 5, 총괄 결정 = 계약 예외) 3절 원칙의 '(종이 색·검색 하이라이트 상수 제외, 계약 7.4.11)' → '(종이 팔레트·PDF 검색 하이라이트 — 계약 7.4.11 v1.2 예외)', 4.13 `PdfTuning.searchHighlightArgb`·`searchCurrentArgb` 주석에 같은 인용. 상수는 `PdfTuning` 한 곳에만(painter·위젯에 색 리터럴 없음). 테마 색으로 바꾸지 않는다 |
| PDF-3-6 | 사소 | (담당 사소 6) 6.7.1 버킷 식의 지수 `k`(`b(s) = 1.25^k`)를 `n`으로(같은 문단 `PdfPageFit.k`와 구분) |
| PDF-3-7 | 계약 C12-03 | 5.2 발췌(1968행)의 `pageBackgroundBuildersProvider` 주석을 계약 7.2.16 v1.2 문구로 |
| PDF-3-8 | 계약 C12-01 | (총괄 추가) 9.1의 `dart_test.yaml`을 만드는 작업이 8장에 없다. T0(B4) 산출물에 넣는다(첫 태그 테스트 T2 `pdfium/`보다 먼저 — R15가 B1부터 검사). 10절 1 '`ws check` 위반 0(R1–R13: …)' → 'R1–R13·R15'. 태그는 리터럴로(계약 7.4.8 v1.2) |
| PDF-3-9 | 절차 | 13장 '13.3 3차 수정' 표(지시 번호 인용), 머리 상태 줄 v0.4(계약 v1.2) |

#### 3.4.7 SYNC — 미승인

| # | 종류 | 지시 |
|---|---|---|
| SYNC-3-1 | 필수 (작음) | (담당 필수 1) 4.4.1 두 번째 bullet과 T10 `status/sync_badge_test.dart`의 '대기 수·진행률만 바뀐 상태 → 같은 `SyncBadge`'는 틀렸다(`pendingChanges = status.pendingUploads`, 계약 7.2.13 `SyncBadge`의 `==`는 네 필드 전부). bullet → '배지 네 필드(`display`·`pendingUploads`·`lastSyncedAt`·첫 차단 문제 코드) 밖의 값(`assets` 전송량, `initialSync` 진행률, `isPushing`, `nextRetryAt`, `clockSkew`, 비차단 문제)만 바뀐 상태 발행은 배지 이벤트를 내지 않는다'. T10 → '배지 밖 필드만 다른 두 상태 → 같은 `SyncBadge` → `.distinct()`가 1번' + '`pendingUploads`만 다른 두 상태 → 다른 `SyncBadge` → 2번'. 12.2 SYNC-CP3 '이유' 칸 '대기 수·진행률 변화로' → '진행률·전송량 변화로' |
| SYNC-3-2 | 필수 | (담당 필수 2) 압축하는 기기는 자기 스냅숏 청크를 받을 때 건너뛰므로(6.6.3 2단계), R 안에 이 기기가 아직 적용하지 않은 기록(fetchScope가 실시간 구독보다 먼저 본 청크, 늦게 보인 청크 — S13)은 이 기기에 영영 오지 않는다. 또 디코드할 수 없는 청크(특히 `fmt` > 지원 형식, 6.6.5 `needsAppUpdate`)를 4단계 `deleteChunks`가 지우면 **모든 기기에서 데이터가 사라진다**. ① 6.6.3 2단계: '`by == deviceNodeId`이고 `kind == delta`인 청크만 건너뜀. 자기 `snapshot` 청크는 디코드·적용(멱등 — 이미 있는 기록은 `KeepLocal`, 시계 표본은 두 종류 모두)'. 6.13 '안전성' bullet과 1단계 주석의 '자기 스냅숏은 건너뜀' 근거도 같이(보류 청크 범위 제외 규칙은 남겨도 됨). ② 6.13 1~2단계: 'R에 `fmt` > `ChunkCodec` 지원 형식인 청크가 있거나 `sync.deferredFrom`이 있으면 그 범위를 건너뜀. 디코드 실패(malformed) 청크는 스냅숏에 넣지 않고 4단계 삭제 대상에서도 뺀다(지우는 것 = 스냅숏에 병합한 청크만)'. ③ T15 `compactor_test`에 'fmt 2 청크가 든 범위 → 압축 안 함·서버 청크 그대로', 'malformed 청크는 삭제되지 않음', '이 기기가 아직 받지 않은 청크가 R에 든 채 압축 → 자기 스냅숏을 받아 그 기록이 적용됨'. 11장 리스크 1행 |
| SYNC-3-3 | 권장 | (담당 권장 1) 6.7.4·6.3.5 보내지 않은 로컬 purge의 좁은 틈: 보기가 '낡음'으로 표시되기 전(`localChanges` 비동기 전달)에 적용이 시작되면 그 노트의 page·stroke·recording 기록이 `TakeRemote`로 고아 행이 된다. 6.6.3 4단계 '낡았으면'을 '적용 묶음마다 outbox 끝 seq(`pendingChanges(afterSeq)` 결과)가 마지막 새로 고침 뒤 바뀌었으면'처럼 신호 지연에 기대지 않는 조건으로 바꾸거나, 이 틈의 고아 행이 화면에 나오지 않고 무해하다는 것(CORE S-4)을 6.7.4에 명시 |
| SYNC-3-4 | 권장 | (담당 권장 2) 6.6.3 7단계 '이분 횟수 소진 → 하나씩 적용' 분기: 그 조각이 메타(커서·`sync.held`)를 가졌을 때 메타를 어디에 싣는지(예: 마지막 단건 호출의 `metaUpdates`, 그 기록이 실패하면 `writeMeta`). T9에 이 경우 1건 |
| SYNC-3-5 | 권장 | (담당 권장 3) 4.7·5.2: `SyncEngine(log:)`(`SyncLogSink`)를 앱 셸이 넣을 자리를 12.2에 **SYNC-CP7**(제안)로. 총괄 답을 미리 적는다: '보류(방향 승인) — SYNC 소유 선택 자리 `syncLogSinkProvider`(기본 `null`)를 INFRA `SyncModule`이 override, 7.3.3 표 반영은 M4 연결 계획 때(계약 7.9 v1.2 보류)'. 이번 범위에서는 `log:` = null |
| SYNC-3-6 | 계약 C12-04·05 | 12.2 SYNC-CP5·CP6 결정 '승인 — 계약 v1.2 C12-04·C12-05'. 4.3 `AuthUser` 주석과 10절 5의 '값 동등 6종' → '7종(`AuthUser` 포함, 계약 7.2.20 v1.2)'. 9.1.3·T16 설명이 계약 7.7 5단계 v1.2와 같은지 확인 |
| SYNC-3-7 | 절차 | 13장 '13.3 3차 수정' 표, 머리 상태 줄(계약 v1.2) |

### 3.5 사용자 확인 항목 (변동 없음)

4장 U1~U4 그대로.

### 3.6 다음 단계

1. INFRA·CORE·INK·PDF·SYNC가 3.4의 [필수]·[계약]을 반영하고 13장에 '13.3 3차 수정'(지시 번호 인용)을 남긴다. [권장]·[사소]도 가능한 한 함께. EDITOR·LIBRARY는 계획서를 고치지 않는다(3.4.4·3.4.5는 구현 때 이 문서 기준).
2. 총괄 4차 검토(승인 검토): 지시 번호별 diff 확인 → 모두 해결되면 이 문서에 '최종 승인' 절을 추가하고 00-overview 상태를 '확정 — 개발 시작 가능'으로 바꾼다.
3. 계약을 더 바꿀 일이 생기면 7.4.12 절차(v1.3)로. 3차 수정에서 계약 v1.2와 다르게 쓰지 않는다.
4. 총괄 후속(이전 검토에서 이월, 이번 작업 범위 밖이라 미실행): PLAN.md 7.4 '서버 시간 기준' → 'HLC 기준(커서는 서버 시각)', 10장 M0 '예산 알림 설정' → '요금제 확인(예산 알림은 Blaze 전환 시)' 문구 갱신. 최종 승인 뒤 PLAN 갱신 작업에서 한다.

---

## 4차 검토 (승인 검토)

> 날짜: 2026-11-05 · 대상: INFRA·CORE·INK·PDF·SYNC 3차 수정본(각 계획서 13.3 — '3차 검토' 3.4 지시 반영본). EDITOR·LIBRARY는 3차에서 승인(계획서 변경 없음) · 방식: 영역별 승인 검토 담당 5명의 판정과 계약 변경 제안 6건을 총괄이 종합하고, 제안의 근거가 된 계획서 줄과 3차 [필수]·[계약] 반영(INFRA-3-1·3-2, CORE-3-1·3-2·3-3, INK-3-1·3-2, PDF-3-1·3-2·3-3·3-8, SYNC-3-1·3-2)을 총괄이 직접 다시 확인 · 기준: 마지막 승인 검토 — 통합을 깨는 문제가 아니면 승인하고 개발 중 해결 사항으로 기록 · 결과: **통합 계약 v1.3**([00-overview.md 7.9](00-overview.md#79-계약-변경-이력) C13-01~05, 시그니처 변경 없음), **7개 영역 모두 승인** → 아래 '최종 승인'

### 4.1 판정 요약

| 영역 | 담당 판정 | 총괄 최종 | 사유 | 남은 일 |
|---|---|---|---|---|
| INFRA | 승인 | **승인** | 3차 지시 6건 반영 확인(R15를 B1-4로, B4 통계 provider 단언, 백업 대기 취소, B8-1 임시 진입점 비고, V6 설정 블록, 13.3 표). P6 수용(C13-01)은 계획서가 이미 따르는 내용(8.1 B1 완료·B8-2) | 개발 중 반영 2건(4.4.1) |
| CORE | 승인 | **승인** | 3차 지시 8건 반영 확인(6.10.4 고아 획 batch, 완료 시점 문구 통일·`put` 주석·가짜 `put` 메타 = 커밋 1건, purge 대기 + `TakeRemote`/`WriteMerged` 규칙, 8.1 순서 메모, 10절 7). CP-8(C13-02)·SYNC-CP8(C13-04) 수용은 CORE 6.9·6.10.3·6.13 동작 그대로 — 주석을 옮기는 일뿐 | 개발 중 반영 3건(4.4.2) |
| INK | 승인 | **승인** | 3차 지시 5건 반영 확인(4.13 주석 = 계약 v1.2 글자 그대로, 10절 R15, `PageThumbnail` 생성 지점, 4.8 보충 주석). P5 수용(C13-03)은 6.12 R8·6.28·T17 설계 그대로 | 개발 중 반영 2건(4.4.3) |
| EDITOR | (3차 승인) | **승인 유지** | v1.3 영향 없음: C13-03의 올가미 색은 INK가 그린다(EDITOR 선택 핸들 등은 `colorScheme`), C13-02·04는 CORE↔SYNC 경계, C13-01은 INFRA 기반 단계 | 3차 3.4.4 구현 규칙 그대로 + 절차 1건 |
| LIBRARY | (3차 승인) | **승인 유지** | v1.3 영향 없음: `SyncStore`·`markUploaded`·`putDownloadedBytes`를 쓰지 않는다(5.1.2 발췌의 `markUploaded` 주석은 3차 LIBRARY-3-1대로 CORE 원문 기준) | 3차 3.4.5 구현 규칙 그대로 + 절차 1건 |
| PDF | 승인 | **승인** | 3차 [필수] 3건(쓰기 재시도 의미, 상태 클래스 값 동등, B4 통계 provider)과 [계약] 3건(C12-01·03·07) 반영 확인. P1은 v1.1 C11-18로 이미 수용, 새 제안 없음. v1.3 영향 없음(`AssetStore`는 `put`만 씀, `PdfTuning`이 이미 C13-03 조건을 만족) | 개발 중 주의 1건 + 절차 1건(4.4.6) |
| SYNC | 승인 | **승인** | 3차 [필수] 2건(배지 동등 문장, 압축 데이터 손실)과 권장 3건 반영 확인. SYNC-CP8 수용(C13-04)은 5.1.2 S-20 그대로, CP-8(C13-02)은 SYNC 정책이 `KeepLocal`을 돌려주는 경우라 엔진 동작 영향 없음. SYNC-CP7 보류 유지 | 개발 중 반영 2건(4.4.7) |

전체 평가

- 3차 지시의 [필수]·[계약]은 5개 영역 모두 반영됐다(담당 확인 + 총괄 표본 확인 — 4.3). 각 영역 13.3 표의 '미반영' = 없음.
- 이번 제안 6건은 모두 '이미 계획서에 있는 동작·기준을 계약 문장으로 옮기자'는 것이었다. 4건 수용(C13-01~04, 2건은 총괄 보충), 1건 이미 수용(PDF P1), 1건 보류 유지(SYNC-CP7). 기각 없음.
- 통합을 깨는 문제는 남지 않았다. v1.3을 계획서로 옮기는 일(결정 칸·인용·주석 복사, SYNC 계약 스위트 검사 1건)은 7장 머리말('이 장이 우선')에 따라 계약만으로 구현 기준이 정해지므로 재승인 조건으로 두지 않고 **개발 중 반영**(4.4, 계약 7.6 C13-05)으로 기록한다.

### 4.2 계약 변경 결정

| 제안 | 낸 영역 | 결정 | 근거·조정 (총괄 확인) | 계약 반영 |
|---|---|---|---|---|
| INFRA P6 | INFRA | **수용** | `ws test`는 워크스페이스 멤버만 돌리고 루트 `tool/`은 멤버가 아니다(01-infra 4.2). v1.2(C12-01)로 B1 경로에 `tool/test/test_tags_test.dart`가 들어갔는데 7.6 B1·B8 완료 조건에는 그 테스트를 돌리는 명령이 없어, R15 검사기 자체의 테스트가 기반 단계 판정에서 빠진다. V3에는 이미 `dart test tool/test`가 있으므로 V3에 맞추는 문구 정리다. INFRA 8.1 B1 완료(01-infra 2693행)·B8-2(2695행)에 이미 들어 있음을 확인했다. B2~B7은 `tool/`을 바꾸지 않으므로 다른 영역 작업량은 그대로다 | 7.6 B1·B8 (C13-01) |
| CORE CP-8 | CORE | **수용 + 보충** | 3차 총괄 결정 CORE-3-3을 계약 문장으로 옮긴다. 02-core 2760행(6.10.3 bullet)·3326행(9.1 `sync_store_test`)은 이미 이 규칙이다. 반면 07-sync C-11(1817행)에는 '`dropPendingLocal`이면 항목 삭제'만 있어 `FakeLocalStore`가 purge 항목을 남기는 구현이 가능했다. SYNC 5.1.4가 '계약 문장 1:1, 차이가 나면 계약 기준으로 가짜를 고친다'이므로 계약에 적는 것이 맞는 해결이다. **보충**: CORE-3-3의 나머지 절반인 `WriteMerged` 쪽(purge 항목 → `fieldsToUpload`의 upsert 항목)도 한 줄로 적었다. 기존 'fields become EXACTLY this set'만으로는 op가 바뀌는지 읽히지 않는다. 동작 영향은 없다. SYNC 정책은 purge 대기에서 `KeepLocal`을 돌려준다(07-sync T4 `sync_merge_policy_test`) | 7.2.10 `TakeRemote`·`WriteMerged` 주석 (C13-02) |
| INK P5 | INK | **수용 + 보충** | C12-07과 근거가 같다. 종이 위에 겹쳐 그리는 표시 색이라 기준은 UI 테마가 아니라 종이와의 대비다. 또 INK는 Material에 의존하지 않으므로(7.1) `colorScheme`을 읽을 수 없다. 03-ink 2295행 R8 painter에 리터럴이 없고, 상수는 2560행 상수 표에, 단언은 2688행 T17에 있음을 확인했다. 기각할 때의 대안(`InkPageView.overlayColor`)은 EDITOR 호출을 바꿔야 해서 비용이 더 크다. **보충**: PDF·INK 공통 조건('예외 색은 painter·위젯에 리터럴 없이 상수 참조')을 한 문장으로 적었다 | 7.4.11 (C13-03) |
| PDF P1 | PDF | 이미 수용(v1.1 C11-18) | 06-pdf 4.7·5.2·K-7 문구가 계약 7.2.16 v1.1과 같다(담당 확인). 12.1의 B4/T8 메모는 제안이 아니다. 총괄 확인 결과, INFRA `feature_wiring_module_test`·`pdf_wiring_test`는 `CoreModule(open: fakeOpenNoteStore(...))`로 컨테이너를 만들고 `pdf_module_test`는 빌더 provider만 읽는다. 계약 변경은 필요 없고 개발 중 주의로 남긴다(PDF-4-2) | — |
| SYNC-CP7 | SYNC | **보류 유지** | v1.2 결정(방향 승인) 그대로다. 이번 범위의 앱은 `sync_engine`에 의존하지 않고(7.1), SYNC 4.7·5.2 I-10은 `log:` = `null`로 서로 일치한다. 7.3.3 표 반영과 provider 정의는 M4 연결 계획 때 한다 | — (7.9 v1.3 '보류 유지') |
| SYNC-CP8 | SYNC | **수용 + 보충** | 3차에서 PDF와 SYNC가 둘 다 '저장 실패 = 예외'로 가정했다가 고쳤다(PDF-3-1, SYNC 6.5.4·6.6.3). 같은 오해를 개발 중에 다시 막으려면 이 규칙이 `SyncStore`에서도 읽혀야 한다. 근거로 확인한 곳: 02-core 2653행('쓰기는 모두 단일 직렬 큐(… 원격 적용)'), 2656행(무한 재시도), 6.10.3(정책 예외 → 롤백 후 다시 던짐), 07-sync 1751행 S-20. **보충**: `putDownloadedBytes`의 청크 쓰기 실패도 `put`과 같게 적었다. S-20이 '계약 7.2.11은 `put`만 명시'라고 짚은 틈이다. CORE 6.13 `put` ③과 같은 BlobStore 경로이므로 구현은 바뀌지 않고, SYNC는 이미 이 경우를 6.9.2 다운로드 실패로 처리한다. 반영 위치: 7.2.10 `SyncStore` 문서 주석, 7.2.11 `AssetStore` 주석, 7.2.9 요약 bullet | 7.2.9·7.2.10·7.2.11 (C13-04) |

총괄이 이번에 직접 넣은 계약 항목: **C13-05**(7.6 마지막 bullet). 기반 단계 뒤 '가정' 블록을 교체할 때 각 영역이 계획서 상태 줄('승인')과 계약 인용(v1.3)을 맞추고, 아래 '최종 승인'의 자기 영역 '개발 중 반영' 항목을 처리한다. 계획서 01~07을 총괄이 고치지 않으므로, 승인 상태와 v1.3 인용을 계획서에 남기는 주체와 시점을 정한 것이다.

기각: 없음.

### 4.3 담당 판정에 대한 총괄 조정

5개 영역 모두 담당 '승인'을 유지한다(조정 없음). 아래는 총괄이 직접 확인한 근거다.

| 영역 | 조정 | 근거 (총괄 직접 확인) |
|---|---|---|
| INFRA | 없음 | 01-infra 2691행 B1-4(`check` R1–R3·R7–R9·**R15**, `test_tags.dart`, `skip_by_default_tags`, `tool/test/test_tags_test.dart`), 2693행 B1 완료·2695행 B8-2(`dart test tool/test`), 13.3 표 INFRA-3-1~3-6 '미반영 없음' |
| CORE | 없음 | 02-core 1670·2760행(purge 대기 + `TakeRemote` → 삭제, `WriteMerged` → upsert 항목), 3326행(테스트 행), 3152행(가짜 `put` 메타 쓰기 = 커밋 1건 — PDF T4·T6이 기대하는 동작), 1688~1691행(`put` 주석 = 계약 7.2.11 v1.2), 13.3 '미반영 없음' |
| INK | 없음 | 03-ink 1659행(4.13 주석 = 계약 7.2.16 v1.2 글자 그대로), 228·2615행(`dart_test.yaml`이 첫 태그 테스트 T08보다 먼저, R15), 13.3 '미반영 없음'(선택 항목 INK-3-4까지 반영) |
| PDF | 없음 | 06-pdf 586행(`storageFailed` = 재시도 없는 쓰기 오류만), 2533행(`putPdf`를 `raceCancel`로), 3044행 T4(`failNextCommits(3)` → 미완료 → 완료, `storageFailed` 없음), `operator ==` 20곳(4.2·4.7·4.8·4.12), 13.3 PDF-3-3(B4 본문 `ValueNotifier(PdfRenderStats.zero)`)·PDF-3-8(T0에 `dart_test.yaml`) |
| SYNC | 없음 | 07-sync 2618~2638행(6.13: 읽을 수 없는 형식·`deferredFrom`이 있는 범위는 건너뜀, malformed 청크는 스냅숏·삭제 모두에서 제외, 지우는 것 = 병합한 청크만), T9 '자기 `delta`만 건너뜀·자기 `snapshot` 적용', 13.3 SYNC-3-1(배지 밖 필드만 다를 때만 같은 배지) |
| 공통 | 계획서 머리 상태 줄 | 01~07의 '재승인 대기'·'최종 승인 대기'·'4차 검토 대기' 표기는 이 검토로 **승인**으로 읽는다. 표기 자체는 C13-05에 따라 각 영역이 개발 착수 때 고친다 |

### 4.4 영역별 남은 문제 (개발 중 반영)

재승인 조건은 **없다**. 아래는 계약 v1.3을 계획서와 구현에 옮기는 항목이다. 처리 시점은 C13-05대로 기반 단계 뒤 '가정' 블록을 교체할 때, 또는 해당 작업(T 번호)을 할 때다. 지시 번호는 `<영역>-4-<n>`. 3차 3.4.4·3.4.5(EDITOR·LIBRARY 구현 규칙)는 그대로 유효하다.

#### 4.4.1 INFRA — 승인

| # | 종류 | 내용 |
|---|---|---|
| INFRA-4-1 | 개발 중 반영 (C13-01) | 12.3 P6 결정 칸 → '승인 — 계약 v1.3 C13-01'. 8.1 B1 완료·B8-2의 '(12.3 P6 — 계약 문구보다 엄격)' → '(계약 7.6 B1·B8 v1.3)'. 동작 변경 없음 |
| INFRA-4-2 | 절차 (C13-05) | 머리 상태 줄 '승인'·계약 v1.3, 13장에 '13.4 최종 승인' 한 줄(4차 지시 번호 인용) |

#### 4.4.2 CORE — 승인

| # | 종류 | 내용 |
|---|---|---|
| CORE-4-1 | 개발 중 반영 (C13-02) | T4 계약 파일의 `TakeRemote`·`WriteMerged` 주석을 계약 7.2.10 v1.3 두 줄 그대로 쓰고, 4.6 블록도 같게 맞춘다. 1670행 '계약 주석은 12.2 CP-8 제안' → '계약 7.2.10 v1.3(C13-02)', 12.2 CP-8 결정 → '승인 — C13-02'. 동작·테스트(9.1 `sync_store_test`)는 이미 맞음 |
| CORE-4-2 | 개발 중 반영 (C13-04) | 4.6 `SyncStore` 문서 주석과 4.7 `AssetStore`의 `putDownloadedBytes`·`markUploaded` 주석을 계약 7.2.10·7.2.11 v1.3 그대로 옮긴다. 6.13 `putDownloadedBytes` bullet에 한 줄을 더한다: '바이트 청크 쓰기는 `put` ③과 같은 BlobStore 경로다. 실패하면 재시도 없이 그 오류로 즉시 완료하고 메타는 바뀌지 않는다. `hasLocalBytes` 커밋은 4.5 머리말 규칙을 따른다.' (권장) `asset_store_test`에 1건: 'BlobStore 쓰기 실패 주입 → `putDownloadedBytes`가 그 오류로 완료, `hasLocalBytes` 유지, `bytesArrived` 없음'. 구현 변경 없음 |
| CORE-4-3 | 절차 (C13-05) | 머리 상태 줄 '승인'·계약 v1.3, 13장 '13.4' 한 줄 |

#### 4.4.3 INK — 승인

| # | 종류 | 내용 |
|---|---|---|
| INK-4-1 | 개발 중 반영 (C13-03) | 12.1 P5 결정 → '승인 — 계약 v1.3 C13-03'. 6.12 R8·6.28 `lassoPathArgb` 행·13.3의 '예외 목록 명시는 12.1 P5로 제안' → '계약 7.4.11 v1.3 예외'. 설계·테스트 변경 없음 |
| INK-4-2 | 절차 (C13-05) | 머리 상태 줄 '승인'·계약 v1.3, 13장 '13.4' 한 줄 |

#### 4.4.4 EDITOR — 승인 (계획서 변경 없음)

| # | 종류 | 내용 |
|---|---|---|
| EDITOR-4-1 | 확인 · 절차 (C13-05) | v1.3 영향 없음. 3차 EDITOR-3-1(CORE 호출은 `_run`·`_runAsync`·`_runHistory` 셋뿐 — 표의 '호출' 열보다 우선)·EDITOR-3-2(Q-E1 레이아웃 기준) 구현 규칙 그대로. 착수 때 머리 상태 줄 '승인'·계약 v1.3 |

#### 4.4.5 LIBRARY — 승인 (계획서 변경 없음)

| # | 종류 | 내용 |
|---|---|---|
| LIBRARY-4-1 | 확인 · 절차 (C13-05) | v1.3 영향 없음. 3차 LIBRARY-3-1~3-3(`markUploaded` 주석 기준, 저장 실패 배너 테스트 = L18 단독 위젯 테스트, pubspec `description`은 INFRA B1 값) 구현 규칙 그대로. 착수 때 머리 상태 줄 '승인'·계약 v1.3 |

#### 4.4.6 PDF — 승인

| # | 종류 | 내용 |
|---|---|---|
| PDF-4-1 | 확인 (C13-03) | `PdfTuning` 한 곳·리터럴 없음(T1 `no_platform_imports_test`)이 이미 C13-03 공통 조건이다. 3절 원칙의 계약 인용만 v1.3 |
| PDF-4-2 | 개발 중 주의 | T8부터 `pdfRenderStatsProvider` 본문이 `pdfPageRendererProvider` → `core.noteStoreProvider`를 필요로 한다(06-pdf 4.12). 계약 7.6 B4의 '`pdfIoOverrides()`만 넣은 컨테이너에서 예외 없음'은 B4 본문 조건이다. T8 커밋 때 PDF는 INFRA에 공지하고, 이 provider를 읽는 컨테이너(INFRA `FeatureWiringModule` 테스트·운영)는 `CoreModule`(또는 가짜 저장소)을 갖는다 — 지금 INFRA 9.1 테스트 구성이 이미 그렇다 |
| PDF-4-3 | 절차 (C13-05) | 머리 상태 줄 '승인'·계약 v1.3, 13장 '13.4' 한 줄 |

#### 4.4.7 SYNC — 승인

| # | 종류 | 내용 |
|---|---|---|
| SYNC-4-1 | 개발 중 반영 (C13-02) | 5.1.4 계약 스위트에 2건을 넣는다(T6). C-11: 'purge 대기(`localPurge`) + `TakeRemote(dropPendingLocal: false)` → 행 있음, 그 엔티티의 outbox 항목 없음'. C-12: 'purge 대기 + `WriteMerged(F)` → `op: upsert`·`changedFields == F`·seq 유지·rev + 1, `F` 빈 집합이면 항목 없음'. `FakeLocalStore`도 같은 규칙으로 구현하며, 4.11 주석에 한 줄 적는다. T16에서 실제 CORE와 기대값이 같아야 한다(CORE 9.1이 같은 경우를 검사함) |
| SYNC-4-2 | 개발 중 반영 (C13-04) | 5.1.1 블록을 계약 7.2.10 v1.3 원문으로 바꾼다(스크립트 대조). S-20의 '계약 7.2.11 v1.2는 `put`만 명시' → '계약 7.2.10·7.2.11 v1.3'. 12.2 결정 칸: SYNC-CP8 '승인 — C13-04', SYNC-CP7 '보류 유지(v1.3)'. 동작 변경 없음 |
| SYNC-4-3 | 절차 (C13-05) | 머리 상태 줄 '승인'·계약 v1.3, 13장 '13.4' 한 줄 |

### 4.5 사용자 확인 항목 (변동 없음)

4장 U1~U4 그대로. 어느 것도 개발 시작을 막지 않는다(기본 진행으로 개발, '최종 승인' 주의 11).

---

## 최종 승인

> 날짜: 2026-11-05 · 총괄 관리자 · 기준: 통합 계약 **v1.3**([00-overview.md](00-overview.md) 7장) · 00-overview 상태: **확정 — 개발 시작 가능**

### 승인 요약

| 영역 | 계획서 | 승인 회차 | 승인한 판본 | 개발 중 반영 |
|---|---|---|---|---|
| INFRA | [01-infra.md](01-infra.md) | 4차 | 3차 수정 v0.4 | INFRA-4-1·4-2 |
| CORE | [02-core.md](02-core.md) | 4차 | 3차 수정본 | CORE-4-1~4-3 |
| INK | [03-ink.md](03-ink.md) | 4차 | v0.4 | INK-4-1·4-2 |
| EDITOR | [04-editor.md](04-editor.md) | 3차 | 2차 수정본 v0.3 | EDITOR-3-1·3-2(구현 규칙), EDITOR-4-1 |
| LIBRARY | [05-library.md](05-library.md) | 3차 | 2차 수정 | LIBRARY-3-1~3-3(구현 규칙), LIBRARY-4-1 |
| PDF | [06-pdf.md](06-pdf.md) | 4차 | 3차 수정 v0.4 | PDF-4-1~4-3 |
| SYNC | [07-sync.md](07-sync.md) | 4차 | 3차 수정 | SYNC-4-1~4-3 |

- 범위: PLAN.md M0~M2 전체 + M3(PDF)·M4(동기화) 핵심 로직(00-overview 1·3장, 범위 결정 7.8).
- 공통 기준의 변화: v1.0 → v1.1(30항목) → v1.2(9항목) → v1.3(5항목). v1.2 이후 시그니처 변경은 없다. 계획서와 계약이 다르면 **계약이 우선**이고, 각 계획서 5절의 '가정한 시그니처'는 폐기한다(7장 머리말).
- 계획서 01~07 머리 상태 줄의 '재승인 대기' 등은 이 절에 따라 **승인**으로 읽는다. 표기는 C13-05에 따라 각 영역이 개발 착수 때 고친다.

### 개발 중 주의할 점

1. **진행 순서(7.6)**: B1(INFRA) → B2(CORE, 가장 긴 경로, T1~T5) → B3(INK) → B4(PDF)·B5(EDITOR)는 B3 뒤, B6(LIBRARY)·B7(SYNC)은 B2 뒤 → B8(INFRA 전체 확인). CORE T4 커밋 뒤에는 작업 트리에서 미리 코드를 써도 되지만, main 커밋과 완료 조건은 B2 완료 뒤다(C12-08). 매 단계 `ws check`·`flutter analyze --fatal-infos`·`ws test`를 돌리고, B1·B8은 `dart test tool/test`를 더한다(C13-01). B8에서 CI 시간·`main.dart.js` 크기·첫 `openNoteStore` 시간을 기록한다.
2. **계약 고정과 변경**: B2·B3은 계약 블록의 이름·주석을 글자 그대로 옮긴다(CORE `api_surface_test`). 동시 개발 중 계약을 바꿀 일이 생기면 결과 보고 '변경 요청' → 총괄 승인 → 7장 v1.4(7.4.12) 순서로 한다. 승인 전에는 계약 이름·의미를 그대로 쓴다. 다른 영역 경로와 공용 파일은 직접 고치지 않는다(4장 2).
3. **쓰기 `Future` 완료 시점(7.2.9·7.2.10·7.2.11, v1.2·v1.3)**: 3차에서 PDF·SYNC가 함께 빠졌던 가장 흔한 오해다. CORE는 커밋 실패를 무한 재시도하고, 그동안 쓰기 `Future`는 완료되지도 오류로 끝나지도 않는다. 소비하는 쪽은 저장 실패를 예외로 기대하지 않는다. 기다리는 화면은 지연 문구 + 닫기·취소로 처리하고 시간 제한으로 끊지 않는다. 테스트는 `FakeNoteStoreFaults.failNextCommits`(가짜도 `put` 메타 쓰기를 커밋 1건으로 셈)와 `fake_async`로 쓴다.
4. **태그·테스트(7.4.8)**: 태그는 문자열 리터럴로만 쓴다. `dart_test.yaml`은 태그를 쓰는 첫 테스트보다 먼저 만들고, `integration`·`perf`는 `skip`. R15가 B1부터 누락을 위반(종료 1)으로 잡는다. 통합 태그 테스트는 통합 단계에서만 돈다(`ws test --run-skipped -t integration`, 7.7 5단계). 실제 시간 대기와 네트워크는 금지.
5. **가짜와 실제의 차이**: 영역 자체 가짜(SYNC `FakeLocalStore`, PDF `FakePdfNoteGateway`, 각 영역 테스트 래퍼)는 계약 문장을 기준으로 맞춘다. 가짜가 계약보다 앞서거나 뒤처지면 가짜를 고친다. 통합 단계에서는 실제 CORE(`openTestNoteStore`)로 같은 시나리오를 다시 돌린다(LIBRARY L21, PDF `integration`, SYNC T16 계약 스위트, EDITOR E-21, INFRA G2).
6. **기반 단계 자리표시(7.6 B4 v1.2)**: 다른 영역이 기반 단계·동시 개발 중 읽는 provider는 자리표시 단계에서도 예외 없이 만들어져야 한다. PDF T8부터 `pdfRenderStatsProvider`가 `noteStoreProvider`를 필요로 하므로, 이를 읽는 컨테이너에는 `CoreModule`이 있어야 한다(PDF-4-2).
7. **웹 우선(7.4.3)**: `lib/`에서 `dart:io`·`dart:html` 등을 쓰지 않고 조건부 import(`*_browser.dart`·`*_native.dart`)로 나눈다. 정적 파일 URL은 `document.baseURI` 기준 절대 URL로 만들고(C11-11), 64비트 정수 연산·비트 연산 색 처리는 쓰지 않는다. Material은 `material_ui`만, Riverpod은 3.4.3 코드 생성 없이 쓴다.
8. **색(7.4.11)**: `colorScheme`만 쓴다. 예외는 폴더·표지·종이 팔레트, PDF 검색 하이라이트(`PdfTuning`), INK 올가미 오버레이(`InkTuning`)다. 예외 색도 상수 한 곳에 두고 리터럴로 쓰지 않는다(C13-03).
9. **외부 패키지(7.5)**: 고정 버전을 그대로 쓴다. 추가·변경은 결과 보고 '의존성 추가'로 남기고, 통합 때 INFRA가 lock을 다시 만든다. `material_ui` 버전 올리기는 INFRA 단독 작업이고, `go_router` 18.1.3은 채택하지 않는다.
10. **알려진 한계(결함 아님 — 그대로 둠)**
    - EDITOR: 저장 실패가 계속되면 뒤로가기가 '저장하는 중…'에서 계속 기다린다. 탈출은 탭 새로고침이다(3차 3.3). iPad에서 문제가 되면 CORE·EDITOR가 함께 7.4.12 절차로 제안한다.
    - SYNC: 보내지 않은 로컬 purge와 원격 적용이 겹치는 좁은 틈에서 고아 행이 생길 수 있다. 화면에 나오지 않고 업로드되지도 않는다(07-sync 6.7.4, SYNC-3-3).
    - PDF: 저장 단계에서 취소한 `put`의 메타가 나중에 커밋되면 어느 페이지도 가리키지 않는 에셋이 남는다(PDF C-8, GC는 이후).
    - 동기화 실연결(Firebase 프로젝트·로그인 화면·앱 셸의 `sync_engine` 의존·`syncLogSinkProvider`)은 M4 연결 계획 때 한다(7.8, SYNC-CP7 보류).
11. **사용자 확인(4장 U1~U4)**: 답을 기다리지 않고 기본 진행대로 개발한다. 시점: U4(펜슬·iPad 모델)는 M0 확인 때, U1(암호 PDF 사본)은 M3 실사용 전, U2(앱 이름·번들 ID)는 네이티브 전환 전, U3(Firebase 위치)는 M4 연결 전.
12. **기기 확인은 사용자 몫**: 각 계획서 9.2·9.3과 통합 V7은 사용자가 iPad에서 확인한다. 웹 빌드는 필기감 수치만 기록하고, 필기감 합격 판정은 네이티브 전환 단계에서 한다(PLAN 9.5). 웹 버전은 테스트 전용이므로 중요한 노트를 쓰지 않도록 안내한다.

### 다음 단계

1. 기반 단계 B1~B8(00-overview 7.6). 끝나면 각 영역이 '가정' 블록을 교체하면서 C13-05와 4.4의 자기 항목을 처리한다.
2. 동시 개발(영역별 git worktree, 브랜치 `area/<id>`, GitHub 푸시는 체크포인트·통합 때만 — 7.4.12).
3. 통합(7.7): CORE → INK → EDITOR·LIBRARY·PDF·SYNC → INFRA 순서로 병합하고, 통합 태그 테스트를 돌린 뒤 V1~V7이 모두 통과하면 '통합 완료'. 그다음 미리보기 배포 → 사용자 iPad 확인 → PLAN.md 체크리스트 갱신(총괄).
4. 총괄 후속(이전 검토에서 이월): PLAN.md 7.4 '서버 시간 기준' → 'HLC 기준(커서는 서버 시각)', 10장 M0 '예산 알림 설정' → '요금제 확인(예산 알림은 Blaze 전환 시)'. 이 문서 작업 범위 밖이라 PLAN 갱신 작업 때 한다.
