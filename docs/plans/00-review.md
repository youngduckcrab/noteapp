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
