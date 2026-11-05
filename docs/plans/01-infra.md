# 01. 기반 · 빌드 · 배포 (INFRA) 상세 계획서

> 상태: **승인** (00-review '최종 승인' — 4차 검토 승인, 판본 3차 수정 v0.4 + 개발 중 반영 INFRA-4-1·4-2) · 마스터 기획서: [docs/PLAN.md](../PLAN.md) v1.1 · 영역 지도·통합 계약: [00-overview.md](00-overview.md) 7장 **v1.5**(1차 통합 반영 — INFRA는 C15-02 6.2 R6 행, 13.5) · 검토: [00-review.md](00-review.md) 3.1(1차), '2차 검토' 2.4.1, '3차 검토' 3.4.1, '4차 검토' 4.4.1, '최종 승인'
> 작성 기준일: 2026-11-05 · 검증 환경: Flutter 3.47.9 / Dart 3.13.7, 리눅스 컨테이너
>
> 이 문서에서 **(확인함)** 은 저장소 밖 실험 폴더(`/tmp/claude-0/plan-scratch/`)에서 실제로 실행해 확인한 사실이고, **(미확인)** 은 문서·기억에 근거해 구현 때 다시 확인해야 하는 사항이다.
> 다른 영역의 타입·provider·함수 이름은 모두 00-overview 7장 '통합 계약'을 따른다(이하 '계약 7.x'). 이 문서와 계약이 다르면 계약이 우선하며, 계약에 대한 의견은 12.3 '계약 변경 제안'에만 적는다. 검토 반영 내역은 13절.

---

## 1. 목적과 범위

### 1.1 목적

1. 7개 영역이 **동시에** 개발할 수 있는 바탕(Dart pub workspace, 패키지 골격, 공통 린트, 검사 스크립트)을 먼저 만든다.
2. 각 패키지를 하나의 앱으로 묶는 **앱 셸**(시작 순서, 의존성 주입, 피처 연결, 라우팅, 오류 화면, 설정 화면 틀)을 만든다.
3. 사용자가 개발 환경 없이 **iPad Safari로 테스트**할 수 있도록 웹 빌드 → Firebase Hosting 자동 배포 경로를 만든다.
4. 사용자가 웹 콘솔만으로 Firebase · GitHub 설정을 끝낼 수 있게 **안내서**를 쓴다.

### 1.2 이번 동시 개발 범위

| 단계 | 내용 |
|---|---|
| 기반 단계 (계약 7.6 **B1**·**B8** v1.2, 8.1) | B1: 루트 파일(`pubspec.yaml`·`pubspec.lock`·`analysis_options.yaml`·`.gitignore`·`.gitattributes`), 패키지 6개 골격(**계약 7.5의 외부 의존 전부 선반영**, `note_core`는 순수 Dart), `app/` 생성(`sync_engine` 미의존), 최소 `tool/ws.dart`(list·test·check R1–R3·R7–R9·**R15**(계약 7.6 B1 v1.2, C12-01 — 태그 선언 검사, `skip_by_default_tags`·`test_tags_test` 포함), 브라우저 테스트 준비 스크립트 선실행 포함), 최소 CI(배포 없음). B8: 최소 라우터 + B5·B6 자리표시 화면 연결 + 전체 확인 + **실측**(CI 1회 시간·`main.dart.js` 크기·가능하면 Chrome 첫 `openNoteStore` 시간) 후 6.13 예산표 갱신. B2~B7은 각 영역 담당 |
| 동시 개발 단계 (8.2) | 검사 스크립트 완성(R4–R6·R10–R13 추가 → R1–R13·R15 — R15는 B1에서 완료, 테스트 실행 옵션), 빌드 정보, 오류 처리, 부트스트랩, 모듈 어댑터(`CoreModule`·`PdfModule`·**`FeatureWiringModule`**), 라우팅(무전환 페이지·라이브러리 공용 페이지 키), 테마, 수명주기 연결, 웹 플랫폼 파사드(새 버전 감지·파일 내려받기·기준 URL), 설정 화면 틀 + **섹션 조립**(EDITOR 4종 · LIBRARY 새 노트 기본값 · INFRA 저장 공간·앱 정보) + **백업 내보내기**, `web/` 파일(index.html · 부트스트랩 · PWA · 아이콘), 웹 정적 파일 2개(`sqlite3.wasm`·`drift_worker.js`), Firebase Hosting 설정, GitHub Actions 4종, 이슈 템플릿, 사용자 안내서 |
| 통합 단계 지원 (계약 7.7, 8.3) | lock 재생성, 실제 패키지 구현을 앱 셸에 연결, 통합 스모크 테스트(V5 VM · V6 Chrome), **R14 export 이름 충돌 검사**(`package:analyzer` 13.3.0), 미리보기 배포 |

### 1.3 이후 범위

- iOS TestFlight 워크플로 **실행·검증** (이번엔 비활성 초안만) — 네이티브 전환 단계
- **M4 동기화 연결**(Firebase 프로젝트 생성 후, 6.4 끝의 'M4 연결' 참고): `app/pubspec.yaml`에 `sync_engine` 추가 + `allowed_dependencies` 간선 추가, `SyncModule`(계약 7.3.3의 M4 행: `syncBadgeProvider`·`remoteAssetFetcherProvider`·`syncConfigProvider`·`authBackendProvider`·`syncBackendFactoryProvider`·`connectivitySignalProvider`. 계약 7.9 v1.2 '보류'의 SYNC-CP7 — SYNC 소유 선택 자리 `syncLogSinkProvider`(기본 `null`)를 `SyncModule`이 override해 SYNC 로그를 `AppErrorLog`로 넘기는 방향은 승인됐고, 7.3.3 표 반영은 M4 연결 계획 때. 이름·모양은 그때 계약을 따른다), `FIREBASE_ENABLED` dart-define과 `firebase_options.dart`, 로그인 화면(`/login`)과 리디렉션, 설정 '계정 · 동기화' 섹션, 루트 `ScaffoldMessenger`의 동기화 알림 스낵바(`syncNoticesProvider`), `app/firebase.json`의 규칙·색인 참조(6.12)와 CI 규칙 배포
- 기능 스위치(feature flag) 주입 — 유료 기능이 생길 때 (PLAN 7.6)
- 다크 모드 테마 전환 (PLAN 5.2) — `buildAppTheme(brightness:)` 매개변수만 미리 둔다
- 네이티브 앱 아이콘 · 스플래시 (`flutter_launcher_icons` 등) — 네이티브 전환 단계
- 안드로이드 고정 서명 키 (태블릿 보유 확인 후, 6.14)
- 크래시 리포트 수집 서버 (2단계)
- 한국어 웹 폰트 번들링 (iPad 확인 결과에 따라, 11절)
- (선택, INFRA-O1 — INK 12.2 Q4는 이 방식으로 **선택 승인**, 00-review 2차 INFRA-2-14) INK가 ink lab(`packages/ink_engine/example`)을 만들기로 하면 워크스페이스 멤버 등록 + `allowed_dependencies`에 그 멤버(이름 예: `ink_lab`) → `[note_core, ink_engine]`(계약 7.1 표) + `web-experiment.yml`에 `target` 입력(`app`/`ink_lab`) 추가 + **`workspace_rules.yaml` `lib_exceptions`에 `packages/ink_engine/example/lib/`**(ink lab `lib/`이 `package:note_core/testing.dart`의 `createFakeNoteStore()`를 쓰므로 R4 test-only 규칙 예외 — INFRA-2-12)

### 1.4 제외 (다른 영역 책임)

| 항목 | 담당 |
|---|---|
| 개발자 표시 오버레이 (프레임 시간 · 입력 지연 · 필압) | EDITOR. INFRA는 PDF 렌더 통계 섹션을 `devOverlaySectionsProvider`로 **연결만** 한다(4.5.9) |
| 문서 모델 · 로컬 DB · 자동 저장 · drift 웹 저장 방식, 웹 `navigator.storage.persist()`·`estimate()` 호출, 백업 JSON 생성(`exportBackupJson`) | CORE. INFRA는 결과 표시(저장 공간 섹션)와 파일 내려받기만 |
| 라이브러리 · 에디터 화면 내용, 기반 단계 자리표시 화면(B5·B6) | EDITOR · LIBRARY |
| 저장 경고 배너 | 라이브러리 화면 LIBRARY · 에디터 화면 EDITOR (조건 함수 CORE `storageWarningOf`) |
| 페이지 썸네일 렌더러 구현 · 표지 예약 생성 | INK · LIBRARY (INFRA는 `pageThumbnailRendererProvider` 주입만) |
| PDF 엔진 초기화 내용 · 가져오기/내보내기 흐름 | PDF (INFRA는 자리 provider에 연결만) |
| 동기화 · 로그인 로직 | SYNC |
| 설정 섹션 내용: 입력 · 펜 · 페이지 넘김 · 개발자 표시 / 새 노트 기본값 | EDITOR(4종) / LIBRARY. INFRA는 설정 화면 틀·조립과 '저장 공간'·'앱 정보' 섹션(M4에 '계정 · 동기화') |

### 1.5 핵심 결정 요약

| # | 결정 | 근거 |
|---|---|---|
| D1 | Dart **pub workspace** 사용, **melos 미사용** | 단일 해석·단일 lock·루트에서 analyze 한 번 (확인함). 패키지별 test 반복은 Dart 스크립트(`tool/ws.dart`)로 충분 |
| D2 | Material은 **`package:material_ui`만** 사용, `package:flutter/material.dart`·`cupertino.dart` import 금지(R7). **`MaterialUiCompatibilityBridge`는 쓰지 않는다** | go_router 18.x · pdfrx 2.11이 material_ui 사용 (확인함). 두 Material이 섞이면 `Theme`·`MaterialLocalizations` 조상 탐색이 서로 안 보인다. 브리지는 클래스·생성자 모두 `@Deprecated`라 `flutter analyze --fatal-infos`가 실패하고, 이번 범위에 SDK Material을 쓰는 외부 패키지가 없다 (계약 7.4.2, 6.3) |
| D3 | 라우터는 **go_router 18.1.2**. `/`·`/folders/:folderId`는 같은 키(`ValueKey('library')`)의 `NoTransitionPage`, `/notes/:noteId`는 `NoTransitionPage` | 경로 URL로 새로고침해도 같은 화면. 폴더 이동 때 라이브러리 화면 `State` 유지(확인함, 6.6), 에디터에 iOS 가장자리 스와이프 뒤로가기 제스처가 생기지 않음 |
| D4 | 의존성 주입: 패키지는 provider 자리를 정의하고, 앱 셸 부트스트랩이 시작 시 **루트 `ProviderScope.overrides`를 한 번** 만든다. override 주체·값은 계약 7.3.3 표 그대로. 패키지 내부 하위 `ProviderScope`는 자기 패키지 provider만(계약 7.4.4) | 실행 중 교체 없음 → 재시작 = 부트스트랩 재실행. 같은 provider 두 번 override는 Riverpod 디버그 assert로 실패(확인함) + 통합 스모크 테스트가 잡는다 |
| D5 | 피처 화면은 **go_router를 모른다**. 앱 셸이 생성자 콜백(`onOpenNote` 등)으로 이동을 연결 | 패키지 간 공유 타입 없이 경계 유지, 화면 단위 테스트 용이 |
| D6 | 웹 렌더러: **dart2js + CanvasKit** 기본. skwasm(wasm)은 실험 채널에서만 | Flutter 3.47.9 로더의 기본 `wasmAllowList`가 blink(크롬 계열)만 허용 → iPad Safari는 `--wasm` 빌드여도 CanvasKit으로 대체됨 (확인함, 6.10) |
| D7 | 서비스 워커 **사용 안 함** + 모든 응답 `Cache-Control: no-cache` + 새 버전 감지 배너 | Flutter 3.47.9가 만드는 `flutter_service_worker.js`는 자기 자신을 해제하는 정리용 (확인함). '옛 버전이 보이는' 문제를 HTTP 재검증과 앱 내 감지로 해결 (6.11) |
| D8 | 외부 패키지는 **계약 7.5 표의 정확한 버전**, 루트 `pubspec.lock` 커밋, CI는 `--enforce-lockfile` | 동시 개발 중 해석 결과 흔들림 방지 (확인함: workspace에서 `--enforce-lockfile` 동작). `pinned_external` = 7.5 표 전부(R9) |
| D9 | 테스트는 VM `flutter test` + **Chrome `flutter test --platform chrome test/web`**. 브라우저 테스트는 `test/web/` 한 곳, 준비가 필요한 멤버는 `tool/prepare_web_test.dart`를 두고 `ws test --platform chrome`이 먼저 실행 | 계약 7.4.8. 컨테이너에 Chrome(`/usr/bin/google-chrome`, Chrome for Testing 153) 있음, 별도 설정 없이 동작 (확인함) |
| D10 | Flutter 버전은 **루트 `pubspec.yaml`의 `environment.flutter: 3.47.9`** 한 곳에서 CI가 읽음(모든 멤버도 같은 값, R2) | flutter-action이 `yq '.environment.flutter'`로 읽는 것 확인 (확인함) |
| D11 | 앱 시작 = CORE **`openNoteStore`를 그대로 감싸는** `CoreModule`(계약 7.2.12, X1). 웹 `persist()`·`estimate()`는 CORE만 호출하고 INFRA는 `StorageInfo`를 표시 | 한 개념 한 소유(계약 7.2.0). 오류 분류는 `NoteStoreOpenException.reason`, 초기화는 `deleteLocalNoteData(config)` |
| D12 | 피처 간 연결은 **`FeatureWiringModule`**(비동기 작업 없는 정적 override 모듈)이 계약 7.3.3 표대로 만든다. 모듈 순서 `core` → `pdf`(비필수) → `featureWiring` → (M4) `sync` | 소비자 자리 + 앱 셸 override(계약 7.1 규칙 1). PDF 시작 실패 시 PDF 관련 override만 빠지고 노트 기능은 동작 |

---

## 2. PLAN.md 요구사항 대응표

범위 표기: **이번** = 이번 동시 개발에서 완료 · **공동** = 다른 영역과 함께 · **초안** = 문서·비활성 파일만 · **이후** · **다른 영역**

| PLAN 위치 | 요구사항 | 이 계획서의 작업 (8절 작업 ID) | 범위 |
|---|---|---|---|
| 1.3 대상 기기 | iPad + 안드로이드 태블릿, 웹은 초기 테스트 용도 | B1 앱 생성(web · android · ios), I13 CI 빌드 | 이번 |
| 2 개발 환경 | Mac·PC 개발 환경 없음 → 모든 빌드는 GitHub Actions | I13 `ci.yml` · `android.yml` | 이번 |
| 2 Apple 개발자 계정 | 나중에 가입 | I13 `ios-testflight.yml` 비활성 초안, I14 안내서 06 초안 | 초안 |
| F-01 다중 선택 일괄 내보내기 | 선택한 노트를 PDF로 | I10b `FeatureWiringModule`이 `libraryPdfExportActionProvider` ← `exportNotesAsPdf` 연결 | 공동 (PDF·LIBRARY 주) |
| F-01 표지 썸네일 | 그리드 표지 | I10b `pageThumbnailRendererProvider` ← `inkPageThumbnailRendererProvider` 주입 | 공동 (INK·LIBRARY 주) |
| F-02 · F-15 PDF 가져오기·내보내기 | 라이브러리·에디터 메뉴 | I10b: `libraryPdfImportActionProvider` ← `importPdfAsNewNote`, `editorExtensionsProvider` ← `PdfMenuAction` 변환 | 공동 (PDF 주) |
| 5.1 자동 저장 | 강제 종료에도 손실 없음 | I7 수명주기 브리지 → I10 `CoreModule.onAppHidden()` = `store.flush()`(500ms) | 공동 (CORE 주) |
| 5.1 오프라인 사용 | 로컬 우선, 오프라인 동작 | 웹은 테스트 전용이라 오프라인 캐시(서비스 워커) 제외. 네이티브 오프라인은 CORE | 공동 / 웹 오프라인 제외 |
| 5.4 앱 시작 | 2초 이내 라이브러리 표시 | 6.4 시작 순서·시간 제한, I5 `StartupReport` 측정, I9 앱 정보에 표시, B8·G2 실측 | 이번 (측정) / 공동 (최적화) |
| 5.4 데이터 안전 | 크래시·강제 종료에도 마지막 획 보존 | I7 숨김 시 flush. 웹 `persist()`는 CORE가 열 때 요청 → I9 저장 공간 섹션에 결과 표시 | 공동 |
| 5.4 보안 | TLS | Firebase Hosting 기본 HTTPS | 이번 |
| 5.4 측정 | 개발자 표시 | EDITOR. INFRA는 앱 정보(빌드·렌더러·시작 시간) + PDF 렌더 통계 섹션 연결(I10b) | 다른 영역 / 이번 일부 |
| 5.2 다크 모드 | UI + 페이지 색 반전 | `buildAppTheme(brightness:)` 매개변수만 | 이후 |
| 5.2 전체 백업 / 12 리스크 'M4 전 백업 내보내기' | 데이터 손실 대비 | I9 앱 정보 '백업 내보내기'(CORE `NoteStore.exportBackupJson()`(계약 7.2.12 v1.1) → 웹 공유 시트 '파일에 저장' 또는 다운로드) — **M4 실연결 전 선행 조건**(계약 7.8) | 이번 |
| 5.3 웹 버전(출시) | 2단계 이후 | — | 제외 |
| 6.1 Flutter · 웹 빌드로 Safari 테스트 | | B1, B8, I11 | 이번 |
| 6.2 상태 관리 Riverpod | | 6.5 주입 방식, 계약 7.5 버전 고정 | 이번 |
| 6.2 CI (분석·테스트·웹/안드로이드/iOS 빌드) | | I13 | 이번 (iOS는 초안) |
| 6.2 테스트용 웹 배포 Firebase Hosting | | I12, I13 | 이번 |
| 6.2 iOS 배포 TestFlight | | I13 초안 | 초안 → 이후 |
| 6.2 착수 시 패키지 최신 상태 재확인 | | 7절 (pub.dev 확인 결과), 계약 7.5 | 이번 |
| 6.3 무료 사용량 확인 · 예산 알림 | | I14 안내서 01 · 03 | 이번 |
| 6.3 종량제(Blaze) 등록 | Storage·Functions 필요 시 | 안내서 03에 '전환할 때' 절차 | 이후 (M4) |
| 7.1 전체 구조 | UI · 에디터 · 서비스 · 저장소 · 동기화 결합 | 6.4 부트스트랩, 6.5 모듈 주입, 계약 7.3.3 | 이번 |
| 7.6 기능 스위치 | | 이후 (12.1 Q10) | 이후 |
| 7.6 모든 데이터에 ownerId | | `CoreModule`이 `NoteStoreConfig.ownerId`(새 DB 생성 때만 의미, 저장된 소유자 우선) 전달 (6.4) | 공동 |
| 8 IA: 로그인 | Google 로그인 화면 | `/login` 경로 예약 | 이후 (M4) |
| 8 IA: 라이브러리 | | `/`, `/folders/:folderId` → `LibraryScreen` (같은 페이지 키) | 이번 (라우팅) |
| 8 IA: 노트 에디터 | | `/notes/:noteId?page=` → `EditorScreen` (무전환) | 이번 (라우팅) |
| 8 IA: 설정 | 계정 · 입력 · 펜 · 일반 · 개발자 표시 | `/settings` 틀 + 섹션 조립: EDITOR 4종(입력·펜·페이지 넘김·개발자 표시), LIBRARY 새 노트 기본값, INFRA 저장 공간·앱 정보. 계정·동기화는 M4(INFRA가 SYNC API로) | 이번 (틀·조립) / 다른 영역 (내용) |
| 8 IA: 설정 > 저장 용량 | | I9 '저장 공간' 섹션(CORE `StorageInfo`·`PersistenceStatus`, `refreshStorageInfo()`) | 이번 |
| 8 IA: 노트 에디터 > 더보기 | PDF 내보내기 · 공유 · 인쇄 | I10b `editorExtensionsProvider` 연결 | 공동 (PDF·EDITOR 주) |
| 9.2 진행 사이클 2–3 | 푸시 → Actions → 웹 테스트 주소 갱신 | I13 `ci.yml` 배포 + 실행 요약에 주소 | 이번 |
| 9.3 피드백 전달 (GitHub 이슈) | 기기·동작·기대·실제·스크린샷 | I13 `.github/ISSUE_TEMPLATE/feedback.yml`, I9 '진단 정보 복사' | 이번 |
| 9.4 개발자 표시 | | EDITOR | 다른 영역 |
| 9.5 단계 A | 푸시 → 웹 자동 배포, '홈 화면에 추가' | I11 · I12 · I13, 안내서 04 | 이번 |
| 9.5 단계 A 한계 | Safari가 저장 데이터를 지울 수 있음 | CORE `persist()` 결과를 저장 공간 섹션에 표시 + 백업 내보내기 + I14 안내서 04 경고 | 이번 |
| 9.5 플랫폼 전용 기능 분리 | M0~M2는 웹에서도 동작 | 6.2 검사 규칙 R4–R6 (금지 import · 조건부 import) | 이번 |
| 9.5 단계 B | Apple 계정 → macOS 빌드 → TestFlight | I13 초안, 안내서 06 초안 | 초안 → 이후 |
| 9.5 macOS 10배 과금 | 마일스톤 단위로만 iOS 빌드 | `workflow_dispatch` + 저장소 변수 게이트 | 이번 (초안) |
| 9.5 안드로이드 | Actions가 만든 APK를 내려받아 설치 | I13 `android.yml`, 안내서 05 | 이번 |
| 10 M0 | Flutter 프로젝트 생성, 폴더 구조, 린트 규칙 | B1, 6.2 | 이번 |
| 10 M0 | Firebase 프로젝트 생성(안내), 예산 알림 | 안내서 01 · 03 (예산 알림은 Blaze 전환 시 — PLAN 문구 갱신은 총괄) | 이번 |
| 10 M0 | Actions: 분석·테스트·웹 빌드 → Hosting 배포·APK | B1(배포 없는 CI), I13 | 이번 |
| 10 M0 | 펜 1종 프로토타입 | INK · EDITOR (INFRA는 배포 경로) | 다른 영역 |
| 10 M0 | 개발자 표시 | EDITOR | 다른 영역 |
| 10 M0 완료 기준 | iPad Safari에서 필기·필압 | 9.3 iPad 체크리스트의 터치·확대 차단 항목 | 공동 |
| 10 M1 완료 기준 | 껐다 켜도 내용 유지 | 6.4 DB 열기 순서(I5 · I10), 통합 스모크 V5(다시 열어 획 유지) | 공동 |
| 10 네이티브 전환 | macOS 빌드 → TestFlight 자동 업로드 | I13 초안 | 초안 → 이후 |
| 10 M4 | Google 로그인, 동기화 상태 표시 | `/login`, `SyncModule`, 계정·동기화 섹션, `syncBadgeProvider` override (1.3) | 이후 |
| 10 2단계 | 오픈소스 라이선스 고지 | I9 앱 정보 '오픈소스 라이선스' 버튼 (`showLicensePage`) | 이번 (간단) |
| 10 2단계 | 크래시 리포트 | `AppErrorLog`는 기기 안에만 보관 | 이후 |
| 11 #1 | 펜슬 종류 · iPad 모델 확인 | 안내서 04에 확인 방법 | 이번 |
| 11 #3 | Firebase 프로젝트 생성 | 안내서 01 | 이번 |
| 11 #4 | Apple 개발자 계정 | 안내서 06 초안 | 이후 |
| 12 리스크 | 웹 저장 데이터 삭제 | CORE persist 요청 결과 표시 + 백업 내보내기 + 안내 + 미리보기 주소마다 데이터가 따로라는 안내 | 이번 |
| 12 리스크 | Mac·계정 없음 | CI 빌드 | 이번 |
| 12 리스크 | 클라우드 비용 | 예산 알림 안내, Hosting 릴리스 보관 개수 설정 안내 | 이번 |

---

## 3. 소유 경로와 패키지 구조

### 3.1 저장소 전체

```text
noteapp/
├─ pubspec.yaml              # workspace root                       (INFRA)
├─ pubspec.lock              # single lockfile, generated           (INFRA)
├─ analysis_options.yaml     # shared lint config                   (INFRA)
├─ .gitignore                # root ignores                         (INFRA)
├─ .gitattributes            # eol / binary / generated markers     (INFRA)
├─ app/                      # Flutter app shell, package `noteapp` (INFRA)
├─ packages/
│  ├─ note_core/             # CORE    (B1: skeleton by INFRA, pure Dart)
│  ├─ ink_engine/            # INK     (B1 skeleton)
│  ├─ feature_editor/        # EDITOR  (B1 skeleton)
│  ├─ feature_library/       # LIBRARY (B1 skeleton)
│  ├─ pdf_io/                # PDF     (B1 skeleton)
│  └─ sync_engine/           # SYNC    (B1 skeleton)
├─ tool/                     # workspace scripts                    (INFRA)
├─ .github/                  # workflows, issue templates           (INFRA)
└─ docs/
   ├─ PLAN.md, plans/        # 총괄 관리자
   └─ guides/                # user guides (Korean)                 (INFRA)
```

- B1 이후 `packages/<name>/` 안의 모든 파일(골격 포함)은 해당 영역 소유다. 패키지별 `.gitignore`(준비 스크립트가 복사한 테스트 자산용)도 각 영역이 둔다(계약 7.4.1).
- 루트 `.gitignore`: `.dart_tool/`, `build/`, `**/.flutter-plugins-dependencies`, `app/android/key.properties`, `*.jks`, `.firebase/`, `.firebaserc`.
- 루트 `.gitattributes`: `* text=auto eol=lf`, `*.png binary`, `*.wasm binary`, `*.pdf binary`, `pubspec.lock linguist-generated=true`, `*.g.dart linguist-generated=true`.

### 3.2 루트 `pubspec.yaml`

| 항목 | 값 | 비고 |
|---|---|---|
| `name` | `noteapp_workspace` | 루트 패키지는 lib 없음, `tool/`만 사용 |
| `publish_to` | `none` | |
| `environment.sdk` | `^3.13.0` | 모든 멤버 동일 (R2) |
| `environment.flutter` | `3.47.9` | **정확 고정**. CI가 이 값을 읽음 (D10) |
| `workspace` | `app`, `packages/note_core`, `packages/ink_engine`, `packages/feature_editor`, `packages/feature_library`, `packages/pdf_io`, `packages/sync_engine` | 목록 순서 고정 |
| `dev_dependencies` | `flutter_lints: 6.0.0`, `yaml: 3.1.4`, `args: 2.7.0`, `path: 1.9.1`, `test: 1.31.1`, `image: 4.12.0`, **`crypto: 3.0.8`**(계약 7.5 v1.1 — `ws web-assets` sha256 계산, C11-29) (+ 통합 단계 G3에 `analyzer: 13.3.0`) | `tool/` 스크립트·테스트 전용, 계약 7.5. `test`는 Flutter 3.47.9의 `test_api 0.7.12` 고정과 호환되는 최신이 1.31.1 (확인함). 이 구성(+ 아래 3.3 표)으로 `flutter pub get --offline --enforce-lockfile` 해석 성공, lock은 `crypto`가 `direct dev`로만 바뀜 (확인함: 총괄 `lead/ws-v11`의 사본 `/tmp/claude-0/plan-scratch/infra3/ws-v11`) |
| `dependency_overrides` | 없음 | 필요 시 루트에만 (R10) |

### 3.3 패키지 골격 (기반 단계 B1에서 생성)

각 패키지 공통 구조 (계약 7.6 B1):

```text
packages/<name>/
├─ pubspec.yaml               # 7.4.1 format, deps = 7.5 table column '쓰는 멤버'
├─ README.md                  # one line: owning area + link to docs/plans/NN-*.md
├─ lib/
│  └─ <name>.dart             # empty barrel: library doc comment only
└─ test/
   └─ <name>_smoke_test.dart  # imports the barrel, trivial expect
```

`pubspec.yaml` 형식 (계약 7.4.1):

```yaml
# Flutter package members (ink_engine, feature_editor, feature_library, pdf_io, sync_engine)
name: <name>
description: <one line>
publish_to: none
version: 0.0.1
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  flutter:
    sdk: flutter
  # workspace siblings: `any` (never path:) ; external: EXACT version from 7.5
dev_dependencies:
  flutter_test:
    sdk: flutter
  fake_async: 1.3.3
```

```yaml
# Pure Dart member (note_core): NO flutter / flutter_test dependency (R2),
# environment.flutter kept; tests still run with `flutter test` in the package dir (ws).
name: note_core
description: Document model, local storage, undo, sync outbox (CORE).
publish_to: none
version: 0.0.1
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  riverpod: 3.4.3
  # ... rest of the 7.5 column for note_core (table below)
dev_dependencies:
  test: 1.31.1
  fake_async: 1.3.3
  build_runner: 2.16.1
  drift_dev: 2.35.2
```

기반 단계의 패키지별 의존성 (계약 7.1 의존 방향 + 7.5 v1.1 '쓰는 멤버' 열 그대로. 총괄이 같은 구성으로 `flutter pub get` 해석 성공을 확인함 — v1.1 추가 3건 포함, INFRA도 사본으로 다시 확인함):

| 패키지 | 종류 | dependencies | dev_dependencies |
|---|---|---|---|
| `note_core` | **순수 Dart** | `riverpod: 3.4.3`, `web: 1.1.2`, `meta: 1.19.0`, `collection: 1.19.1`, `clock: 1.1.3`, `crypto: 3.0.8`, `drift: 2.35.3`, `sqlite3: 3.8.0`, `idb_shim: 2.11.2`, `uuid: 4.6.0` | `test: 1.31.1`, `fake_async: 1.3.3`, `build_runner: 2.16.1`, `drift_dev: 2.35.2` |
| `ink_engine` | Flutter | `flutter`(sdk), `note_core: any`, `riverpod: 3.4.3`, `meta: 1.19.0` | `flutter_test`(sdk), `fake_async: 1.3.3`, `perfect_freehand: 2.5.2+1` |
| `feature_editor` | Flutter | `flutter`(sdk), `note_core: any`, `ink_engine: any`, `flutter_riverpod: 3.4.3`, `material_ui: 1.10.0`, `meta: 1.19.0`, `collection: 1.19.1` | `flutter_test`(sdk), `fake_async: 1.3.3` |
| `feature_library` | Flutter | `flutter`(sdk), `note_core: any`, `flutter_riverpod: 3.4.3`, `material_ui: 1.10.0`, **`collection: 1.19.1`**(계약 7.5 v1.1) | `flutter_test`(sdk), `fake_async: 1.3.3`, **`clock: 1.1.3`**(계약 7.5 v1.1 — 테스트 시계용 dev 의존만, 프로덕션 코드는 `clockProvider`) |
| `pdf_io` | Flutter | `flutter`(sdk), `note_core: any`, `ink_engine: any`, `flutter_riverpod: 3.4.3`, `material_ui: 1.10.0`, `web: 1.1.2`, `meta: 1.19.0`, `collection: 1.19.1`, `crypto: 3.0.8`, `pdfrx: 2.11.0`, `pdfium_dart: 0.4.1`, `ffi: 2.2.0`, `file_picker: 13.3.2` | `flutter_test`(sdk), `fake_async: 1.3.3` |
| `sync_engine` | Flutter (주 라이브러리는 순수 Dart) | `flutter`(sdk), `note_core: any`, `riverpod: 3.4.3`, `web: 1.1.2`, `meta: 1.19.0`, `collection: 1.19.1`, `clock: 1.1.3`, `crypto: 3.0.8`, `firebase_core: 5.1.0`, `firebase_auth: 7.0.1`, `cloud_firestore: 7.1.0`, `firebase_storage: 14.0.1`, `connectivity_plus: 7.3.2` | `flutter_test`(sdk), `fake_async: 1.3.3`, `fake_cloud_firestore: 4.5.0`, `firebase_auth_mocks: 0.16.0` |
| `noteapp` (app) | Flutter 앱 | `flutter`(sdk), `flutter_web_plugins`(sdk), `note_core: any`, `ink_engine: any`, `feature_editor: any`, `feature_library: any`, `pdf_io: any`, `flutter_riverpod: 3.4.3`, `material_ui: 1.10.0`, `go_router: 18.1.2`, `cupertino_icons: 2.0.0`, `web: 1.1.2` — **`sync_engine` 없음**(M4 연결 때 추가, 계약 7.1) | `flutter_test`(sdk), `fake_async: 1.3.3` |

- 계약 v1.1 영향: `feature_library` 행에 `collection`·dev `clock`, 루트(3.2)에 dev `crypto`가 더해졌다(C11-29). SYNC `testing.dart`는 lib에서 `fake_async`·matcher를 쓰지 않기로 해(C11-22) `sync_engine` 행은 그대로다(`fake_async`는 dev 유지).
- 동시 개발 중 외부 의존 추가는 자기 pubspec에 정확 버전으로 넣고 결과 보고에 '의존성 추가'로 남긴다. `ws check`는 7.5 표에 없는 외부 의존을 경고(R9w)로만 알리고, 통합 G1에서 INFRA가 `pinned_external`에 올린 뒤 `--strict`로 확인한다.
- 기반 단계 smoke test: 순수 Dart 멤버는 `package:test/test.dart`, Flutter 멤버는 `package:flutter_test/flutter_test.dart`. 둘 다 `ws test`가 각 멤버 디렉터리에서 `flutter test`로 실행(순수 Dart 멤버도 동작함을 총괄이 확인).

### 3.4 `app/`

```text
app/
├─ pubspec.yaml                  # name: noteapp, version: 0.1.0+1 (deps: 3.3 table)
├─ dart_test.yaml                # tags: integration {skip: "..."} (계약 7.4.8 v1.1, content in 8.2 I12)
├─ .gitignore                    # flutter create default + test/web/sqlite3.wasm, test/web/drift_worker.js
├─ firebase.json                 # Hosting config (6.12); M4 adds rules refs to ../packages/sync_engine/firebase/*
├─ tool/
│  └─ prepare_web_test.dart      # copies app/web/sqlite3.wasm + drift_worker.js → test/web/ (V6 smoke)
├─ lib/
│  ├─ main.dart                  # entry point only: calls runNoteApp()
│  └─ src/
│     ├─ app/
│     │  ├─ note_app.dart        # NoteApp (MaterialApp.router, material_ui)
│     │  ├─ theme.dart           # buildAppTheme()
│     │  ├─ strings.dart         # AppStrings (Korean UI text of the shell, 해요체)
│     │  └─ lifecycle_bridge.dart
│     ├─ bootstrap/
│     │  ├─ app_module.dart      # AppModule, AppModuleContext, StaticOverridesModule
│     │  ├─ app_bootstrapper.dart
│     │  ├─ startup_report.dart
│     │  ├─ bootstrap_app.dart   # BootstrapApp, splash, startup error screen
│     │  ├─ splash_view.dart
│     │  └─ startup_error_screen.dart
│     ├─ build/
│     │  ├─ build_info.dart
│     │  └─ runtime_info.dart
│     ├─ errors/
│     │  ├─ app_error_log.dart
│     │  ├─ error_handlers.dart
│     │  ├─ app_error_widget.dart
│     │  ├─ diagnostic_report.dart
│     │  └─ app_provider_observer.dart
│     ├─ modules/
│     │  ├─ core_module.dart           # adapts package:note_core (openNoteStore)
│     │  ├─ pdf_module.dart            # adapts package:pdf_io (initializePdfIo, pdfIoOverrides)
│     │  ├─ feature_wiring_module.dart # 00-overview 7.3.3 static overrides
│     │  ├─ pdf_wiring.dart            # PdfMenuAction → EditorMenuItem, PDF stats → DevOverlaySection
│     │  └─ production_modules.dart
│     ├─ providers.dart          # shell-level providers (4.5.10, 6.8)
│     ├─ routing/
│     │  ├─ app_routes.dart
│     │  ├─ app_navigator.dart
│     │  ├─ screen_builders.dart
│     │  ├─ app_router.dart
│     │  └─ not_found_screen.dart
│     ├─ settings/
│     │  ├─ settings_screen.dart
│     │  ├─ settings_sections.dart     # SettingsSectionEntry, defaultSettingsSections()
│     │  ├─ storage_section.dart       # '저장 공간' (CORE StorageInfo / PersistenceStatus)
│     │  ├─ about_section.dart         # '앱 정보'
│     │  ├─ backup_export.dart         # BackupCancelToken, prepareBackup(): flush → exportBackupJson (cancellable wait); deliverBackup(): share / download
│     │  └─ backup_sheet.dart          # BackupReadySheet: [공유 · 파일에 저장] [내려받기] (fresh user activation)
│     ├─ update/
│     │  ├─ update_checker.dart
│     │  └─ update_banner.dart
│     └─ web/
│        ├─ web_platform.dart          # interface + conditional import
│        ├─ web_platform_stub.dart     # VM/native no-op
│        └─ web_platform_browser.dart  # package:web implementation
├─ test/
│  ├─ fakes/                     # FakeWebPlatform, FakeAppModule, CountingNoteStore, fakeOpenNoteStore,
│  │                             # RecordingLocalDataEraser, fake PDF actions (5.7)
│  ├─ app/  bootstrap/  build/  errors/  modules/  routing/  settings/  update/
│  ├─ support/contract_strings.dart  # 계약 7.4.5 fixed banner sentences (V5·V6 compare screens with these)
│  ├─ integration/               # @Tags(['integration']) — V5 smoke (G2)
│  └─ web/                       # @TestOn('browser') only, run by `ws test --platform chrome`
├─ web/
│  ├─ index.html
│  ├─ flutter_bootstrap.js
│  ├─ manifest.json
│  ├─ favicon.png                # 32x32
│  ├─ icons/  Icon-180.png  Icon-192.png  Icon-512.png  Icon-maskable-192.png  Icon-maskable-512.png
│  ├─ sqlite3.wasm               # tool/web_assets.yaml (CORE, 계약 7.4.9)
│  └─ drift_worker.js            # tool/web_assets.yaml (CORE, 계약 7.4.9)
├─ android/                      # flutter create 생성 + 서명 설정 (6.14)
└─ ios/                          # flutter create 생성 + ExportOptions.plist (6.15)
```

### 3.5 `tool/`

```text
tool/
├─ ws.dart                    # CLI entry (4.2)
├─ gen_icons.dart             # generates app/web icons (package:image)
├─ workspace_rules.yaml       # check rules data (4.3)
├─ web_assets.yaml            # files required in app/web (4.3, 계약 7.4.9)
├─ src/
│  ├─ workspace.dart          # Workspace, WorkspaceMember (pubspec parsing, graph, pure Dart flag)
│  ├─ rules.dart              # WorkspaceRules, checkWorkspace(), RuleViolation (R1–R13, R15)
│  ├─ test_tags.dart          # R15 (B1-4): @Tags / tags: literal scanner + dart_test.yaml check (계약 7.4.8 v1.2)
│  ├─ export_names.dart       # R14 (integration stage G3, package:analyzer 13.3.0)
│  ├─ dart_imports.dart       # import/export directive scanner
│  ├─ affected.dart           # affectedPackages()
│  ├─ test_command.dart       # TestPlan: vm / chrome, prepare scripts, tags, run-skipped
│  ├─ flutter_runner.dart     # locate & run flutter/dart executables, Chrome lookup
│  ├─ channel_id.dart         # previewChannelId()
│  ├─ build_info_file.dart    # build_info.json writer
│  ├─ web_finalize.dart       # finalize build/web (copy info, manifest label, verify, size report)
│  ├─ web_assets.dart         # verify/fetch tool/web_assets.yaml entries (sha256: package:crypto 3.0.8)
│  └─ png_size.dart           # read PNG IHDR width/height
└─ test/
   ├─ fixtures/               # tiny fake workspaces for rule / test-plan / export-name tests
   └─ *_test.dart             # 9.1 표
```

### 3.6 `.github/`

```text
.github/
├─ workflows/
│  ├─ ci.yml                  # verify + web build + Firebase deploy (all branches)
│  ├─ android.yml             # APK (main push + manual)
│  ├─ web-experiment.yml      # manual: --wasm / cross-origin isolation preview
│  └─ ios-testflight.yml      # manual + repo variable gate, DRAFT
└─ ISSUE_TEMPLATE/
   ├─ feedback.yml            # PLAN 9.3 feedback form (Korean)
   └─ config.yml
```

### 3.7 `docs/guides/`

```text
docs/guides/
├─ README.md                  # 순서와 목록
├─ 01-firebase-project.md     # Firebase 프로젝트 만들기 + Hosting 시작
├─ 02-github-secrets.md       # 서비스 계정 키 → GitHub Secret / Variable
├─ 03-budget-alert.md         # 요금제 확인, 예산 알림, Hosting 릴리스 보관 개수
├─ 04-ipad-web-test.md        # 테스트 주소 열기, 홈 화면에 추가, 새 버전, 문제 해결, 피드백
├─ 05-android-apk.md          # APK 내려받아 설치
└─ 06-ios-testflight.md       # 초안 (네이티브 전환 때 완성)
```

---

## 4. 공개 API

INFRA는 의존 그래프의 맨 위(앱)라서 다른 패키지가 import하는 Dart API는 없다. 다른 영역이 **사용하거나 지켜야 하는 것**은 워크스페이스 규약, `tool/ws.dart` 명령, 앱 셸의 런타임 규약이다(4.1–4.4). 4.5는 앱 셸 내부 API로, 구현자와 테스트가 쓰는 전체 시그니처다.

### 4.1 워크스페이스 규약 (모든 영역)

계약 7.4.1~7.4.8을 INFRA 도구가 강제하는 형태로 정리한 것이다. 내용이 다르면 계약이 우선한다.

| 규약 | 내용 | 강제 |
|---|---|---|
| 패키지 pubspec | 3.3 형식. `resolution: workspace`, 환경 블록 동일(`sdk: ^3.13.0`, `flutter: 3.47.9` — 순수 Dart 멤버도), 형제 패키지는 `any`(`path:` 금지), 외부 패키지는 **계약 7.5의 정확한 버전** | R1·R2·R8·R9 |
| 순수 Dart 멤버 | `note_core`는 `sdk: flutter` 의존이 없고 `package:flutter/`·`package:flutter_test/`를 import하지 않는다. 테스트는 `test: 1.31.1`, 실행은 `ws test`(멤버 디렉터리의 `flutter test`) | R2 |
| 새 외부 의존성 | 자기 pubspec에 정확 버전으로 추가 가능, 결과 보고에 '의존성 추가'. `pubspec.lock`은 루트 단일 파일이라 통합 때 INFRA가 재생성(6.1). 7.5 표에 없는 패키지는 `ws check`가 경고(R9w), 통합 G1 이후 `--strict`에서 위반 | R9 |
| analysis_options | 패키지에 **두지 않는다**. 루트 파일이 자동 적용 (확인함) | R3 |
| Material | `package:material_ui/material_ui.dart`만 사용. `package:flutter/material.dart` · `package:flutter/cupertino.dart` 금지 (lib, test 모두). `MaterialUiCompatibilityBridge` 사용 안 함 | R7 |
| 진입점만 import | 다른 워크스페이스 패키지는 `lib/` 최상위 진입점만 import(`package:<pkg>/src/` 금지, lib·test 모두). `testing.dart`·`testing_vm.dart`는 `test/`에서만 — `lib/`에서는 `package:` URI로 import 금지(같은 패키지의 `lib/testing*.dart`끼리 상대 import는 허용) | R7, R4 |
| 플랫폼 분리 | `lib/`에서 `dart:io` · `dart:ffi` · `dart:html` · `dart:js` · `dart:js_util` · `package:js` 금지. 네이티브 전용은 `*_native.dart`(또는 `*_io.dart`), 웹 전용(`dart:js_interop`, `package:web`)은 `*_browser.dart`에 두고 **조건부 import/export로만** 불러온다. 네이티브 전용 패키지(`package:ffi/`, `package:pdfium_dart/`, `package:drift/native.dart`)도 `*_native.dart`·`*_io.dart`에서만. 예외 파일: `packages/note_core/lib/testing_vm.dart`(VM 테스트 전용) | R4·R5·R6 |
| 조건부 import 형태 | `import 'x_stub.dart' if (dart.library.js_interop) 'x_browser.dart' if (dart.library.ffi) 'x_native.dart';` (계약 7.4.3) | R6 |
| VM 테스트 | `test/` 아래 (`test/web/` 제외). **테스트 코드의 네트워크 접근 금지**, 실제 시간 대기 금지 (`fake_async`·`tester.pump`) | 리뷰 |
| 브라우저 테스트 | **`test/web/` 한 곳**, 파일 첫 줄 `@TestOn('browser')`. 준비가 필요한 멤버는 `tool/prepare_web_test.dart`를 두면 `ws test --platform chrome`이 먼저 실행한다(멤버 디렉터리에서 `dart run tool/prepare_web_test.dart`). 복사된 자산은 패키지 `.gitignore`로 제외 | `ws test` |
| 다운로드 | 테스트 코드는 네트워크 금지. **빌드 훅**(sqlite3 미리 빌드 라이브러리, pdfium_dart의 PDFium 바이너리·gcc)과 **준비 스크립트**의 다운로드는 허용하고 CI에서 캐시한다(6.13) | CI 캐시 |
| 태그 | `golden`(VM), `perf`(기본 skip), `bench`(기본 제외 — `ws test`가 `-x bench`), `pdfium`, `integration`(통합 단계에서만 → `ws test --run-skipped -t integration`), `scenario`(SYNC). **계약 7.4.8 v1.1**: 태그를 쓰는 패키지는 패키지 `dart_test.yaml`의 `tags:`에 모두 선언하고 `integration`·`perf`는 거기서 `skip: "<사유>"`(예: `integration: {skip: "integration stage only — ws test --run-skipped -t integration"}`). `ws test`의 기본 제외는 `-x bench`뿐이라 선언이 없으면 동시 개발 중 B2 상태 CORE로 통합 테스트가 돌아 실패한다. **계약 7.4.8 v1.2**(C12-01): `ws check` R15가 **B1부터** 이 규칙을 위반(종료 1)으로 검사하므로 각 영역 브랜치에서 바로 잡힌다. R15 스캐너는 **문자열 리터럴 태그만** 인식하므로 태그는 `@Tags(['integration'])`·`tags: ['golden']`처럼 리터럴로 쓴다(변수·상수로 넘기지 않는다). `dart_test.yaml`은 그 패키지에서 태그를 쓰는 첫 테스트보다 먼저(보통 골격 작업에서) 만든다 | `ws test`, R15(B1부터) |
| 골든 테스트 | `test/goldens/` 아래, `@Tags(['golden'])` + `@TestOn('vm')`. 컨테이너(리눅스)에서 생성하고 CI(ubuntu)에서 비교 | 리뷰 |
| 화면 크기 | 위젯 테스트 기준 iPad Pro 13" 논리 크기(DPR 2) 세로 1032×1376, 가로 1376×1032 (계약 7.4.8) | 리뷰 |
| 앱이 주입할 provider | 기본 구현이 없으면 `throw UnimplementedError('<name> must be overridden by the app shell')`, 선택 자리는 `Provider<T?>((ref) => null)`. 모든 provider는 `name:` 인자에 같은 이름(계약 7.4.4). 루트 override는 계약 7.3.3 표에 있는 것만 | G2 스모크 |
| 오류 보고 | Flutter 패키지: 복구 가능한 오류는 삼키지 말고 `FlutterError.reportError(FlutterErrorDetails(exception:, stack:, library: '<package>'))`. 순수 Dart 패키지(CORE·SYNC): 상태 스트림으로 알리고 INFRA 모듈이 `AppErrorLog`로 넘긴다(계약 7.4.5) | — |
| 버퍼된 쓰기 | 앱이 숨겨질 때 앱 셸이 CORE `NoteStore.flush()`를 호출(500ms 안). 다른 패키지가 쓰기를 모아 두면 결과 보고로 요청 → 모듈 `onAppHidden()`에 추가 | — |
| 웹 정적 파일 | `app/web/`에 넣을 파일은 `tool/web_assets.yaml`로만 관리(현재 `sqlite3.wasm`, `drift_worker.js` — 계약 7.4.9). 추가는 결과 보고 '변경 요청' | R12 |

### 4.2 `tool/ws.dart` 명령

실행: 저장소 루트에서 `dart run tool/ws.dart <command>` (컨테이너에서는 `/opt/flutter/bin/dart`).

| 명령 | 옵션 | 동작 | 종료 코드 |
|---|---|---|---|
| `list` | | 멤버를 위상 순서(의존 대상 먼저)로 출력 | 0 |
| `check` | `--no-format`, `--strict`, `--no-exports` | 규칙 R1–R13·R15 검사 (B1 판은 R1–R3·R7–R9·R15 — 계약 7.6 B1 v1.2, I1에서 R4–R6·R10–R13 추가, 통합 단계 G3부터 R14 포함, `--no-exports`로 건너뜀). 위반은 `경로:줄: [규칙] 메시지`로 출력. 경고(R9w)는 `--strict`일 때만 위반 | 0 / 1 |
| `analyze` | | 루트에서 `flutter analyze --fatal-infos` | analyze 종료 코드 |
| `test` | `--package <name>`(반복), `--affected-since <git-ref>`, `--platform vm\|chrome`(기본 vm), `-t/--tags <tag>`(반복), `-x/--exclude-tags <tag>`(반복, 기본 `bench`), `--run-skipped`, `--reporter <r>`, `--member-timeout <분>`(통합 단계 추가 — 기본 chrome 15·vm 없음, 0 = 없음) | 멤버마다 멤버 디렉터리에서 `flutter test` 실행. **vm**: `test/` 아래 `*_test.dart` 중 `test/web/` 밖의 파일만 넘긴다. **chrome**: `test/web/`가 있는 멤버만, ① 그 멤버에 `tool/prepare_web_test.dart`가 있으면 먼저 `dart run tool/prepare_web_test.dart`(5분 제한, 실패하면 그 멤버를 '준비 실패'로 기록하고 테스트 건너뜀) ② `flutter test --platform chrome test/web`. Chrome: 환경 변수 `CHROME_EXECUTABLE`이 있으면 그대로 전달, 없으면 `PATH`에서 `google-chrome`·`google-chrome-stable`·`chromium`·`chromium-browser`를 찾고 없으면 종료 코드 3. 태그 옵션은 그대로 `flutter test`에 전달(통합 단계: `ws test --run-skipped -t integration`). 끝에 멤버별 결과 요약 표(멤버·플랫폼·준비·통과/실패/건너뜀·시간). **통합 단계 추가(CI 권고)**: 멤버 실행 하나가 시간 제한을 넘으면 프로세스 트리(flutter·Chrome·flutter_tester)를 SIGTERM → 5초 → SIGKILL로 끝내고 1회 다시 실행, 두 번째도 넘으면 그 멤버 실패('TIMED OUT')·다음 멤버 진행. 밖에서 온 신호로 자식이 끝나거나 `ws`가 SIGINT·SIGTERM을 받으면 자식 트리를 끝내고 남은 멤버는 실행하지 않는다(`ws`는 130·143으로 종료) | 하나라도 실패 시 1 |
| `affected` | `--since <git-ref>` | 바뀐 멤버 + 그 멤버에 의존하는 멤버를 위상 순서로 출력 | 0 |
| `channel-id` | `--branch <name>` | Firebase 미리보기 채널 ID 출력 (6.12) | 0 / 2 |
| `build-info` | `--out <file>`, `--channel <live\|preview\|experiment\|local>`, `--version <x.y.z>`(기본: app pubspec) | 빌드 정보 JSON 작성. `GITHUB_SHA`, `GITHUB_REF_NAME`, `GITHUB_RUN_NUMBER` 환경 변수 사용, 없으면 `local` | 0 / 2 |
| `finalize-web` | `--build-dir <dir>`, `--info <file>` | `build_info.json` 복사, 비-live 채널이면 manifest 이름 변경, 필수 파일 존재 확인, `main.dart.js` 크기 출력(`GITHUB_STEP_SUMMARY`가 있으면 거기에도) | 0 / 1 |
| `web-assets` | `verify` \| `fetch` | `tool/web_assets.yaml` 항목의 존재·크기·sha256 확인 / 내려받기 | 0 / 1 |
| `hosting-config` | `--isolate` | `app/firebase.json`에 COOP/COEP 헤더를 더한 사본 출력 (실험 채널용) | 0 |

공통: 사용법 오류 2, 환경 오류(flutter·git·Chrome 없음) 3. flutter 실행 파일 찾기 순서: 환경 변수 `FLUTTER_BIN` → `FLUTTER_ROOT/bin/flutter` → `Platform.resolvedExecutable`이 `<root>/bin/cache/dart-sdk/bin/dart`이면 `<root>/bin/flutter` → `PATH`의 `flutter` (컨테이너에서 `FLUTTER_ROOT=/opt/flutter`, `resolvedExecutable=/opt/flutter/bin/cache/dart-sdk/bin/dart` 확인함). 컨테이너는 `CHROME_EXECUTABLE` 없이 `/usr/bin/google-chrome`이 잡힌다 (확인함). `flutter test`가 `--run-skipped`·`-t`·`-x`를 지원함 (확인함, 3.47.9 `flutter test -h`).

### 4.3 tool 설정 파일 형식

`tool/workspace_rules.yaml`:

```yaml
allowed_dependencies:          # workspace sibling edges (R8) = 00-overview 7.1
  note_core: []
  ink_engine: [note_core]
  feature_editor: [note_core, ink_engine]
  feature_library: [note_core]
  pdf_io: [note_core, ink_engine]
  sync_engine: [note_core]
  # 7.1: the app may use every package, but this scope's app does NOT depend on
  # sync_engine. The sync_engine edge is added together with app/pubspec.yaml at M4.
  noteapp: [note_core, ink_engine, feature_editor, feature_library, pdf_io]
  # 7.1 optional row: the ink lab app packages/ink_engine/example (INFRA-O1, 통합 단계에서 등록).
  ink_lab: [note_core, ink_engine]
app_members: [noteapp, ink_lab]  # R14: apps — their lib/ is not a public entry point (통합 단계 G3)
pure_dart_members: [note_core]  # R2: no `sdk: flutter` deps, no package:flutter/ imports
pinned_external:               # R9: must be identical wherever declared = 00-overview 7.5 (all rows)
  flutter_riverpod: 3.4.3
  riverpod: 3.4.3
  material_ui: 1.10.0
  go_router: 18.1.2
  cupertino_icons: 2.0.0
  web: 1.1.2
  meta: 1.19.0
  collection: 1.19.1
  clock: 1.1.3
  crypto: 3.0.8
  drift: 2.35.3
  sqlite3: 3.8.0
  idb_shim: 2.11.2
  uuid: 4.6.0
  pdfrx: 2.11.0
  pdfium_dart: 0.4.1
  ffi: 2.2.0
  file_picker: 13.3.2
  firebase_core: 5.1.0
  firebase_auth: 7.0.1
  cloud_firestore: 7.1.0
  firebase_storage: 14.0.1
  connectivity_plus: 7.3.2
  test: 1.31.1
  build_runner: 2.16.1
  drift_dev: 2.35.2
  fake_async: 1.3.3
  perfect_freehand: 2.5.2+1
  fake_cloud_firestore: 4.5.0
  firebase_auth_mocks: 0.16.0
  flutter_lints: 6.0.0
  yaml: 3.1.4
  args: 2.7.0
  path: 1.9.1
  image: 4.12.0
  analyzer: 13.3.0             # root dev (tool/), R14 — integration step G3
forbidden_imports:
  lib: [dart:io, dart:ffi, dart:html, dart:js, dart:js_util, package:js/]
  lib_and_test: [package:flutter/material.dart, package:flutter/cupertino.dart]
native_only_imports:           # R4: in lib/, only from files ending with native_suffixes
  - package:ffi/
  - package:pdfium_dart/
  - package:drift/native.dart
test_only_entrypoints: [testing.dart, testing_vm.dart]
  # R4: a lib/ file must not import/export package:<member>/<entry> for these entries.
  # Checked on package: URIs. Relative imports between the SAME package's
  # lib/testing*.dart files are allowed (e.g. testing_vm.dart → 'testing.dart');
  # a relative URI from any other lib/ file that resolves to lib/testing*.dart is a violation.
lib_exceptions:                # R4 exceptions (00-overview 7.4.2); a trailing '/' = whole directory
  - packages/note_core/lib/testing_vm.dart   # VM test helper (dart:ffi, drift native); imported from test/ only
  - packages/ink_engine/example/lib/         # ink lab app (1.3, INFRA-O1): lib/ uses the testing.dart fakes
web_only_imports: [dart:js_interop, dart:js_interop_unsafe, package:web/]
native_suffixes: [_io.dart, _native.dart]
web_suffixes: [_browser.dart]
generated_files: ['*.g.dart', '*.freezed.dart', 'schema_versions.dart']   # skipped by R11 format
fixture_dirs: [tool/test/fixtures/]   # skipped by R11 format and by root analysis (6.2 exclude): checker test fixtures
skip_by_default_tags: [integration, perf]   # R15 (from B1, 계약 7.4.8 v1.2): must have `skip:` in the package dart_test.yaml
global_triggers: [pubspec.yaml, pubspec.lock, analysis_options.yaml, tool/, .github/workflows/]
```

`tool/web_assets.yaml` (I12에서 채움 — 값은 계약 7.4.9, 두 URL 모두 내려받아 크기·sha256 일치 확인함):

```yaml
assets:
  - path: sqlite3.wasm               # relative to app/web/
    url: https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.8.0/sqlite3.wasm
    bytes: 758619
    sha256: efd308be92a34f3aa15f289a37f213b0230fd80888a1364326ee29579d892d37
    owner: CORE
    reason: drift web database (sqlite3 3.8.0 — must match note_core's sqlite3 pin)
  - path: drift_worker.js
    url: https://github.com/simolus3/drift/releases/download/drift-2.35.3/drift_worker.js
    bytes: 361829
    sha256: a54b81412d4c4ab56653bb9e4c02912b0820bb37e2bba00722ddef4d78083d4a
    owner: CORE
    reason: drift web worker (drift 2.35.3 — same bytes as pub cache drift-2.35.3/drift_worker.js)
```

- `web-assets fetch`는 sha256이 일치할 때만 파일을 쓴다. sha256은 `package:crypto` 3.0.8(`sha256.convert(bytes)`)로 계산한다 — 루트 dev 의존(3.2, 계약 7.5 v1.1 C11-29, 12.3 P4 승인). 외부 프로그램(`sha256sum`)에는 기대지 않는다.
- 두 파일은 커밋한다(빌드·배포에 네트워크가 필요 없게). CORE·`sqlite3`·`drift` 버전을 올리면 이 표도 같이 바꾼다(R12가 불일치를 잡음).

### 4.4 앱 셸 런타임 규약 (다른 영역이 기대할 수 있는 것)

| 항목 | 보장 내용 |
|---|---|
| 위젯 트리 | 루트 `ProviderScope` 1개(overrides = 계약 7.3.3 표) → `AppLifecycleBridge` → `MaterialApp.router`(material_ui) → `builder:` `UpdateBanner` → 라우트 화면. `ScaffoldMessenger`, `Overlay`, `Navigator` 사용 가능. **`MaterialUiCompatibilityBridge`는 트리에 없다**(D2) |
| 지역화 | `locale: Locale('ko')`, `supportedLocales: [ko, en]`, `localizationsDelegates: GlobalMaterialLocalizations.delegates` (material_ui 버전, 확인함) |
| 테마 | `buildAppTheme()` (Material 3, seed `0xFF3949AB`). 패키지는 `Theme.of(context).colorScheme`만 사용, 자체 `MaterialApp`·`ProviderScope` 금지 (테스트·패키지 내부 하위 scope 제외, 계약 7.4.4·7.4.11) |
| provider 주입 | 앱 시작 시 한 번, 루트 `ProviderScope.overrides`로. 주체·값은 계약 7.3.3(`CoreModule`·`PdfModule`·`FeatureWiringModule`·`BootstrapApp`). 실행 중 교체 없음 (재시작 = 부트스트랩 재실행). `ink.pressureModeProvider`는 override가 아니라 EDITOR가 `notifier.set()` |
| 화면 이동 | 피처 화면은 생성자 콜백만 호출. URL 경로·페이지 종류는 6.6 (`/notes/:noteId?page=`, 무전환) |
| 수명주기 | 앱이 숨겨지면(웹 `visibilitychange: hidden`·`pagehide`, 네이티브 `AppLifecycleState.hidden/paused/detached`) 시작된 모듈의 `onAppHidden()` 호출 → CORE `store.flush()`(500ms 제한). 최소 간격 1초. 종료·재시도 때 `stop()` → `store.close()` |
| 오류 수집 | `FlutterError.onError`, `PlatformDispatcher.onError`, Riverpod `providerDidFail`, CORE `PersistenceStatus.lastError`(CoreModule이 구독) 모두 `AppErrorLog`로 (최근 100건) |
| 런타임 정보 | 렌더러·빌드 정보는 앱 셸 내부 전용. 패키지가 렌더러를 알아야 하면 `kIsWasm`(flutter/foundation, 확인함) 사용 |
| 웹 기준 URL | **계약 7.2.12·7.4.3(v1.1, C11-11)**. 경로 URL 전략이라 `Uri.base`(dart2js = `self.location.href`, 확인함)는 `/notes/<id>` 같은 깊은 경로가 된다. 앱 셸은 운영에서 CORE `WebStorageConfig`에 `document.baseURI` 기준으로 해석한 **절대 URL**을 넘긴다(6.4). CORE는 `Uri.base.resolve(path)`를 그대로 쓰고 절대 URL은 그 호출을 그대로 통과하므로, INFRA는 절대 URL만 넘기면 된다(CORE 쪽 변경 없음). 상대 경로는 테스트에서만. 어떤 패키지도 정적 파일·에셋 주소를 `Uri.base` 상대로 만들지 않는다(주소 질의 읽기 `Uri.base.queryParameters`는 대상 밖) |

### 4.5 앱 셸 내부 API (시그니처 전체)

`material_ui`, `flutter_riverpod`, `go_router`를 import한다고 가정한다. `Override`는 `package:flutter_riverpod/misc.dart`에서 export됨 (확인함). 다른 패키지 타입은 접두사 없이 쓴다(`package:note_core/note_core.dart`, `package:ink_engine/ink_engine.dart`, `package:feature_editor/feature_editor.dart`, `package:feature_library/feature_library.dart`, `package:pdf_io/pdf_io.dart`). 모든 셸 provider는 `name:`에 같은 이름을 준다(계약 7.4.4).

#### 4.5.1 빌드 · 런타임 정보 — `src/build/`

```dart
/// Where a build is served from.
enum BuildChannel { local, preview, live, experiment }

/// Compile-time build metadata.
///
/// Injected with `--dart-define-from-file=build/build_info.json`; the same
/// JSON file is served as `/build_info.json` for update detection (6.11).
@immutable
final class BuildInfo {
  const BuildInfo({
    required this.version,
    required this.buildNumber,
    required this.gitSha,
    required this.gitRef,
    required this.channel,
    this.builtAt,
  });

  /// Reads APP_VERSION, APP_BUILD_NUMBER, APP_GIT_SHA, APP_GIT_REF,
  /// APP_CHANNEL, APP_BUILD_TIME via String.fromEnvironment.
  /// Missing or malformed values fall back to [local] field by field.
  factory BuildInfo.fromEnvironment();

  /// Parses the same keys (APP_*) from a decoded build_info.json map.
  /// Throws [FormatException] when APP_GIT_SHA is missing.
  factory BuildInfo.fromJson(Map<String, Object?> json);

  /// Used by `flutter run`, tests and builds without defines.
  static const BuildInfo local = BuildInfo(
    version: '0.0.0',
    buildNumber: 0,
    gitSha: 'local',
    gitRef: 'local',
    channel: BuildChannel.local,
  );

  final String version;
  final int buildNumber;
  final String gitSha;
  final String gitRef;
  final BuildChannel channel;
  final DateTime? builtAt;

  bool get isLocal;

  /// First 7 characters of [gitSha], or `local`.
  String get shortSha;

  /// e.g. `0.1.0 (#42 · a1b2c3d · main)`.
  String get displayLabel;

  Map<String, String> toJson();
}

enum WebRenderer { notWeb, canvasKit, skwasm }

@immutable
final class RuntimeInfo {
  const RuntimeInfo({
    required this.isWeb,
    required this.renderer,
    required this.isStandalone,
    this.userAgent,
  });

  /// isWeb = kIsWeb; renderer = kIsWasm ? skwasm : canvasKit (web only);
  /// isStandalone/userAgent from [web].
  factory RuntimeInfo.detect(WebPlatform web);

  final bool isWeb;
  final WebRenderer renderer;

  /// True when launched from the iPad home screen (display-mode: standalone).
  final bool isStandalone;
  final String? userAgent;

  /// e.g. `CanvasKit (dart2js)`, `skwasm (wasm)`, `네이티브`.
  String get rendererLabel;
}
```

#### 4.5.2 웹 플랫폼 파사드 — `src/web/`

저장소 유지 요청(`persist()`)과 사용량(`estimate()`)은 **여기에 없다**. 웹 `navigator.storage` 호출은 CORE만 하고(계약 7.2.12), 앱 셸은 CORE `StorageInfo`·`refreshStorageInfo()` 값을 표시한다(INFRA-S1).

```dart
enum WebVisibility { visible, hidden }

enum WebShareResult { shared, cancelled, unsupported, failed }

/// Browser-only APIs behind an interface. The VM/native implementation is a
/// no-op so that every caller works in `flutter test` and on native builds.
abstract interface class WebPlatform {
  bool get isSupported;
  String? get userAgent;

  /// matchMedia('(display-mode: standalone)') || navigator.standalone.
  bool get isStandalone;

  /// performance.now(), i.e. ms since navigation start. Null if unsupported.
  double? get millisecondsSinceNavigationStart;

  /// Absolute URL of [relativePath] resolved against `document.baseURI`
  /// (honours `<base href>`; dart2js `Uri.base` is `location.href`, which is a
  /// deep path such as `/notes/<id>` under the path URL strategy).
  /// 계약 7.2.12 · 7.4.3 (v1.1): production passes ONLY these absolute URLs to
  /// CORE WebStorageConfig; CORE keeps Uri.base.resolve(path), which returns an
  /// absolute URL unchanged. Non-web: returns [relativePath] unchanged.
  String resolveAppUrl(String relativePath);

  /// GET [relativePath] (resolved by fetch() against document.baseURI) with
  /// `cache: 'no-store'` and a `?t=<epochMs>` query.
  /// Returns null on non-2xx, network error or after [timeout].
  Future<String?> fetchTextNoStore(
    String relativePath, {
    Duration timeout = const Duration(seconds: 5),
  });

  /// Starts a browser download of [bytes]: Blob + `<a download=fileName>` click,
  /// object URL revoked after 30 s (Safari needs the delay).
  /// Returns false when unsupported (non-web) or when the browser threw.
  /// Never throws. NOTE (미확인, 11절): an iPadOS home-screen app may ignore
  /// `<a download>`; [shareFile] is the second path. Call from a tap handler.
  Future<bool> downloadBytes(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/octet-stream',
  });

  /// navigator.canShare({files: [File([], 'probe', {type: mimeType})]}).
  /// False off-web, when navigator.share / canShare is missing, or when it
  /// throws. Never throws.
  bool canShareFiles({String mimeType = 'application/octet-stream'});

  /// navigator.share({files: [File([bytes], fileName, {type: mimeType})]})
  /// (Safari 15+ — 미확인). Must be called directly from a tap handler (user
  /// activation). AbortError → cancelled; missing API → unsupported; any
  /// other error → failed. Never throws.
  Future<WebShareResult> shareFile(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/octet-stream',
  });

  /// document 'visibilitychange' (+ 'pagehide' mapped to hidden).
  /// Single broadcast stream, listener attached lazily once.
  Stream<WebVisibility> get visibilityChanges;

  /// window.location.reload().
  void reload();
}

/// Conditional import: web_platform_stub.dart /
/// web_platform_browser.dart (if dart.library.js_interop).
WebPlatform createWebPlatform();
```

#### 4.5.3 오류 처리 — `src/errors/`

```dart
enum AppErrorSource { flutter, platform, provider, bootstrap, module, manual }

@immutable
final class AppErrorRecord {
  const AppErrorRecord({
    required this.time,
    required this.source,
    required this.summary,
    this.details,
    this.stackTrace,
    this.fatal = false,
  });

  /// summary = details.exceptionAsString() truncated to 300 chars;
  /// details = details.context + library; stack truncated to 4000 chars.
  factory AppErrorRecord.fromFlutterErrorDetails(
    FlutterErrorDetails details, {
    DateTime? now,
  });

  factory AppErrorRecord.fromError(
    Object error,
    StackTrace? stackTrace, {
    required AppErrorSource source,
    bool fatal = false,
    DateTime? now,
  });

  final DateTime time;
  final AppErrorSource source;
  final String summary;
  final String? details;
  final String? stackTrace;
  final bool fatal;
}

/// In-memory ring buffer. Oldest record is dropped when full.
final class AppErrorLog extends ChangeNotifier {
  AppErrorLog({this.capacity = 100});

  final int capacity;

  /// Oldest first, unmodifiable.
  List<AppErrorRecord> get records;

  /// Total records ever added, including dropped ones.
  int get totalCount;

  void add(AppErrorRecord record);
  void clear();
}

/// Installs FlutterError.onError, PlatformDispatcher.instance.onError and,
/// in release mode, ErrorWidget.builder = appErrorWidgetBuilder.
/// Previous handlers are chained (called after logging).
/// Returns a callback that restores the previous handlers (for tests).
VoidCallback installGlobalErrorHandlers(
  AppErrorLog log, {
  bool presentToConsole = true,
});

/// Release-mode replacement for the red error box: grey box + icon +
/// "이 부분을 표시하지 못했어요".
Widget appErrorWidgetBuilder(FlutterErrorDetails details);

/// Logs providerDidFail to [log] with source provider.
final class AppProviderObserver extends ProviderObserver {
  AppProviderObserver(this.log);
  final AppErrorLog log;

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  );
}

/// Plain-text report the user pastes into chat or a GitHub issue.
abstract final class DiagnosticReport {
  /// Max 8000 chars. Sections: header, build, runtime, startup, storage
  /// (CORE StorageInfo — backend, durable, multi-tab, persistGranted, usage /
  /// quota, missing features), persistence (CORE PersistenceStatus — pending,
  /// last commit + latency, consecutive failures), last [maxErrors] errors
  /// (newest first) with [maxStackLines] lines each.
  static String format({
    required BuildInfo build,
    required RuntimeInfo runtime,
    StartupReport? startup,
    StorageInfo? storage,
    PersistenceStatus? persistence,
    required List<AppErrorRecord> errors,
    DateTime? now,
    int maxErrors = 5,
    int maxStackLines = 15,
  });
}
```

#### 4.5.4 부트스트랩 — `src/bootstrap/`

```dart
/// One unit of startup work, adapting one workspace package.
/// Implementations live in app/lib/src/modules/. Packages never see this type.
abstract class AppModule {
  const AppModule();

  /// Stable id for logs and the startup report, e.g. `core`.
  String get id;

  /// Korean label for the splash screen, e.g. `노트 저장소 여는 중`.
  String get label;

  /// Failure in [start] aborts startup when true (default).
  bool get critical => true;

  Duration get startTimeout => const Duration(seconds: 10);

  /// Async initialization. May publish values to [context] for later modules.
  Future<void> start(AppModuleContext context);

  /// Overrides for the root ProviderScope. Called once, after [start] succeeded.
  List<Override> overrides();

  /// App became hidden. Must finish within 500 ms (enforced by caller).
  Future<void> onAppHidden() async {}

  /// Release resources. Called in reverse start order on retry/shutdown.
  Future<void> stop() async {}

  /// Called by AppBootstrapper right after [start] exceeded [startTimeout].
  /// The start future is NOT cancelled and may still complete later; the
  /// returned future completes once that late result has been cleaned up
  /// (CoreModule: a late NoteStore is closed at once). AppBootstrapper.shutdown
  /// awaits it (at most 2 s) so a retry never runs next to a late resource.
  /// Must not throw; log failures to the context's errorLog.
  Future<void> onStartAbandoned() async {}

  /// Destructive last-resort recovery for the startup error screen
  /// ("이 기기 데이터 지우고 다시 시작"). Only CoreModule provides one.
  Future<void> Function()? get resetLocalData => null;

  /// Whether [resetLocalData] may be offered after [start] threw [error].
  bool canResetAfter(Object error) => false;
}

/// Overrides-only module (no async init), e.g. for tests and simple wiring.
final class StaticOverridesModule extends AppModule {
  StaticOverridesModule({
    required this.id,
    required this.label,
    required List<Override> overrides,
  });

  @override
  final String id;
  @override
  final String label;
  @override
  Duration get startTimeout => const Duration(seconds: 1);
  @override
  Future<void> start(AppModuleContext context);
  @override
  List<Override> overrides();
}

final class AppModuleContext {
  AppModuleContext({
    required this.buildInfo,
    required this.runtimeInfo,
    required this.web,
    required this.ownerId,
    required this.errorLog,
  });

  final BuildInfo buildInfo;
  final RuntimeInfo runtimeInfo;
  final WebPlatform web;

  /// Owner id handed to CORE as NoteStoreConfig.ownerId. It matters ONLY when
  /// CORE creates a NEW database: a persisted owner (e.g. after
  /// SyncStore.reassignOwner on first login) wins, and the effective owner is
  /// always NoteStore.ownerId. Until M4: kLocalOwnerId.
  final OwnerId ownerId;
  final AppErrorLog errorLog;

  /// Makes [value] available to modules started later.
  /// Throws StateError when a value of type T was already published.
  void publish<T extends Object>(T value);

  /// Throws StateError when no value of type T was published.
  T require<T extends Object>();

  T? maybe<T extends Object>();

  /// Outcome of a module that already ran in this attempt; null when it has
  /// not run (yet). FeatureWiringModule uses it to skip PDF overrides.
  StartupStepOutcome? outcomeOf(String moduleId);

  /// outcomeOf(moduleId) == StartupStepOutcome.ok.
  bool isStarted(String moduleId);

  /// Called by AppBootstrapper right after each module (never by modules).
  /// Throws StateError when [moduleId] already has an outcome.
  void recordOutcome(String moduleId, StartupStepOutcome outcome);
}

enum StartupStepOutcome { ok, failedNonCritical, timedOut, failedCritical }

@immutable
final class StartupStep {
  const StartupStep({
    required this.id,
    required this.elapsed,
    required this.outcome,
    this.error,
  });
  final String id;
  final Duration elapsed;
  final StartupStepOutcome outcome;
  final Object? error;
}

@immutable
final class StartupReport {
  const StartupReport({
    required this.steps,
    required this.bootstrapElapsed,
    this.sinceNavigationStart,
    this.storage,
  });

  final List<StartupStep> steps;

  /// From AppBootstrapper.run() start to result.
  final Duration bootstrapElapsed;

  /// Web: performance.now() when bootstrap finished (page open → app ready).
  final Duration? sinceNavigationStart;

  /// CORE NoteStore.storageInfo right after open (includes persistGranted:
  /// CORE awaited persist() for at most 1 s). Null when CORE did not start.
  final StorageInfo? storage;
}

sealed class BootstrapResult {
  const BootstrapResult({required this.report});
  final StartupReport report;
}

final class BootstrapSuccess extends BootstrapResult {
  const BootstrapSuccess({
    required super.report,
    required this.overrides,
    required this.startedModules,
  });

  /// Shell overrides first, then module overrides in module order.
  final List<Override> overrides;
  final List<AppModule> startedModules;
}

final class BootstrapFailure extends BootstrapResult {
  const BootstrapFailure({
    required super.report,
    required this.moduleId,
    required this.moduleLabel,
    required this.error,
    required this.stackTrace,
    this.resetLocalData,
  });

  final String moduleId;
  final String moduleLabel;
  final Object error;
  final StackTrace stackTrace;

  /// failedModule.resetLocalData when failedModule.canResetAfter(error), else null.
  final Future<void> Function()? resetLocalData;

  /// Korean message (해요체) chosen by error type (6.7).
  String get userMessage;

  /// True for NoteStoreOpenException(newerSchema) on web: offer "새로고침".
  bool get offersReload;
}

final class AppBootstrapper {
  AppBootstrapper({
    required List<AppModule> modules,
    required this.buildInfo,
    required this.runtimeInfo,
    required this.web,
    required this.errorLog,
    required this.ownerId,
    this.slowStageThreshold = const Duration(seconds: 3),
  });

  final BuildInfo buildInfo;
  final RuntimeInfo runtimeInfo;
  final WebPlatform web;
  final AppErrorLog errorLog;

  /// See AppModuleContext.ownerId (new database only).
  final OwnerId ownerId;
  final Duration slowStageThreshold;

  /// Current stage label for the splash screen.
  ValueListenable<String> get stageLabel;

  /// True while the current stage exceeded [slowStageThreshold].
  ValueListenable<bool> get isSlow;

  /// Runs once; repeated calls return the same future.
  Future<BootstrapResult> run();

  /// Calls onAppHidden() on started modules in parallel, 500 ms timeout each.
  /// Errors are logged (source: module), never thrown.
  Future<void> notifyAppHidden();

  /// Stops started modules in reverse order (2 s timeout each), then awaits
  /// the onStartAbandoned() cleanups of modules whose start timed out (2 s
  /// max in total; a cleanup still running after that is logged, source:
  /// module). BootstrapApp's "다시 시도" creates the next bootstrapper only
  /// after this completes (6.4 2-2).
  Future<void> shutdown();
}

/// Root widget before the ProviderScope exists.
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({
    super.key,
    required this.createBootstrapper,
    required this.errorLog,
    this.appBuilder,
  });

  /// Called for the first attempt and for every retry — a retry calls it only
  /// after the previous bootstrapper's shutdown() completed (late-store
  /// cleanup included, 6.4 2-2).
  final AppBootstrapper Function() createBootstrapper;
  final AppErrorLog errorLog;

  /// Defaults to `(success) => const NoteApp()`.
  final Widget Function(BootstrapSuccess success)? appBuilder;

  @override
  State<BootstrapApp> createState();
}

class SplashView extends StatelessWidget {
  const SplashView({
    super.key,
    required this.stageLabel,
    required this.isSlow,
  });
  final ValueListenable<String> stageLabel;
  final ValueListenable<bool> isSlow;
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({
    super.key,
    required this.failure,
    required this.diagnostics,
    required this.onRetry,
    this.onResetLocalData,
    this.onReload,
  });
  final BootstrapFailure failure;

  /// DiagnosticReport text, copied by the "진단 정보 복사" button.
  final String diagnostics;
  final VoidCallback onRetry;

  /// failure.resetLocalData wrapped by BootstrapApp (then retry). Two-step
  /// confirm. Hidden when null (storageUnavailable, newerSchema, timeouts …).
  final Future<void> Function()? onResetLocalData;

  /// WebPlatform.reload, shown when failure.offersReload.
  final VoidCallback? onReload;
}

/// Entry used by main.dart. Steps in 6.4.
Future<void> runNoteApp({
  AppBootstrapper Function()? createBootstrapper,
});
```

#### 4.5.5 라우팅 — `src/routing/`

```dart
abstract final class AppRoutes {
  static const String library = '/';
  static const String folderPattern = '/folders/:folderId';
  static const String notePattern = '/notes/:noteId';
  static const String settings = '/settings';
  static const String pageQueryKey = 'page';

  /// Shared page key of `/` and `/folders/:folderId`: the Navigator keeps ONE
  /// library route, so folder changes update LibraryScreen instead of
  /// recreating it (6.6).
  static const ValueKey<String> libraryPageKey = ValueKey<String>('library');

  /// '/folders/<encoded id>'
  static String folder(String folderId);

  /// '/notes/<encoded id>' + '?page=<encoded pageId>' when given (계약 7.2.17).
  static String note(String noteId, {String? pageId});
}

@immutable
final class LibraryRouteArgs {
  const LibraryRouteArgs({this.folderId});
  final String? folderId; // null = root
}

@immutable
final class EditorRouteArgs {
  const EditorRouteArgs({required this.noteId, this.initialPageId});
  final String noteId;
  final String? initialPageId;
}

/// Shell-internal navigation API. Feature screens get plain callbacks.
abstract interface class AppNavigator {
  void openLibrary({String? folderId});
  void openNote(String noteId, {String? pageId});
  void closeNote();
  void openSettings();
  void closeSettings();
}

final class GoRouterAppNavigator implements AppNavigator {
  GoRouterAppNavigator(this.router);
  final GoRouter router;
  // semantics in 6.6
}

typedef LibraryScreenBuilder = Widget Function(
  BuildContext context,
  LibraryRouteArgs args,
  AppNavigator navigator,
);
typedef EditorScreenBuilder = Widget Function(
  BuildContext context,
  EditorRouteArgs args,
  AppNavigator navigator,
);
typedef SettingsScreenBuilder = Widget Function(
  BuildContext context,
  AppNavigator navigator,
);

@immutable
final class AppScreenBuilders {
  const AppScreenBuilders({
    required this.library,
    required this.editor,
    required this.settings,
  });

  /// Real screens: LibraryScreen / EditorScreen (계약 7.2.17, 7.2.18) and
  /// SettingsScreen (4.5.8). Wiring in 6.6.
  factory AppScreenBuilders.production();

  /// Simple shell-owned widgets showing args as text (tests, smoke builds).
  /// The library placeholder is a StatefulWidget that counts initState calls
  /// (State-retention test, 9.1).
  factory AppScreenBuilders.placeholders();

  final LibraryScreenBuilder library;
  final EditorScreenBuilder editor;
  final SettingsScreenBuilder settings;
}

/// Page types (6.6): `/` and `/folders/:folderId` →
/// NoTransitionPage(key: AppRoutes.libraryPageKey); `/notes/:noteId` →
/// NoTransitionPage(key: state.pageKey); `/settings` → default page
/// (material_ui MaterialPage); unknown → NotFoundScreen.
GoRouter createAppRouter({
  required AppScreenBuilders screens,
  String initialLocation = AppRoutes.library,
  List<NavigatorObserver>? observers,
});

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({
    super.key,
    required this.location,
    required this.onGoHome,
  });
  final String location;
  final VoidCallback onGoHome;
}
```

#### 4.5.6 앱 · 테마 · 수명주기 — `src/app/`

```dart
/// MaterialApp.router (material_ui) with routerConfig = appRouterProvider,
/// theme = buildAppTheme(), locale ko, builder: (context, child) =>
/// UpdateBanner(child: child!). No MaterialUiCompatibilityBridge (D2).
class NoteApp extends ConsumerWidget {
  const NoteApp({super.key});
}

ThemeData buildAppTheme({Brightness brightness = Brightness.light});

abstract final class AppStrings {
  static const String appName = '필기노트';
  // shell texts (해요체, 계약 7.4.5): splash, startup errors, settings
  // headers, storage, about, backup, update banner …
}

/// Listens to AppLifecycleListener (onHide / onPause / onDetach) and
/// WebPlatform.visibilityChanges (hidden), debounced to 1 call per second,
/// then calls AppBootstrapper.notifyAppHidden() (→ CoreModule: store.flush()).
class AppLifecycleBridge extends ConsumerStatefulWidget {
  const AppLifecycleBridge({super.key, required this.child});
  final Widget child;
}
```

#### 4.5.7 새 버전 감지 — `src/update/`

```dart
@immutable
final class UpdateCheckConfig {
  const UpdateCheckConfig({
    this.initialDelay = const Duration(seconds: 5),
    this.interval = const Duration(minutes: 10),
    this.minGapOnResume = const Duration(seconds: 60),
    this.fetchTimeout = const Duration(seconds: 5),
    this.path = 'build_info.json',
  });
  final Duration initialDelay;
  final Duration interval;
  final Duration minGapOnResume;
  final Duration fetchTimeout;
  final String path;
}

sealed class UpdateStatus {
  const UpdateStatus();
}

/// Non-web, local build, or channel == local.
final class UpdateDisabled extends UpdateStatus {
  const UpdateDisabled();
}

final class UpdateUnknown extends UpdateStatus {
  const UpdateUnknown();
}

final class UpdateUpToDate extends UpdateStatus {
  const UpdateUpToDate(this.checkedAt);
  final DateTime checkedAt;
}

final class UpdateAvailable extends UpdateStatus {
  const UpdateAvailable(this.remote);
  final BuildInfo remote;
}

final class UpdateDismissed extends UpdateStatus {
  const UpdateDismissed(this.remote);
  final BuildInfo remote;
}

class UpdateChecker extends Notifier<UpdateStatus> {
  @override
  UpdateStatus build();

  /// Fetch now, ignoring throttling. Never throws.
  Future<void> checkNow();

  /// Hide the banner until a build with another sha appears.
  void dismiss();

  /// notifyAppHidden() (flush) then WebPlatform.reload().
  Future<void> applyUpdate();
}

final updateCheckConfigProvider = Provider<UpdateCheckConfig>(
    (ref) => const UpdateCheckConfig(), name: 'updateCheckConfigProvider');

final updateCheckerProvider = NotifierProvider<UpdateChecker, UpdateStatus>(
    UpdateChecker.new, name: 'updateCheckerProvider');

/// Shows a MaterialBanner above [child] while status is UpdateAvailable.
/// Lives in MaterialApp.builder (above the Navigator): no Overlay, so the
/// banner must not use Tooltip/PopupMenu; plain TextButtons only.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key, required this.child});
  final Widget child;
}
```

#### 4.5.8 설정 화면 틀 · 섹션 조립 · 저장 공간 · 앱 정보 — `src/settings/`

설정 화면(`/settings`)은 INFRA 틀 + 섹션 조립이다(계약 7.4.11, CD-23). 섹션 위젯은 `Column`만 돌려주고(Scaffold·스크롤 없음, 계약 7.2.17), 화면이 `ListView` 안에 머리글과 함께 차례로 넣는다.

```dart
@immutable
final class SettingsSectionEntry {
  const SettingsSectionEntry({
    required this.id,
    required this.title,
    required this.builder,
    this.group,
  });

  /// Stable id '<area>.<name>' (e.g. 'editor.input'); widget key and tests.
  final String id;

  /// Section header (Korean).
  final String title;

  /// Optional group header shown once above consecutive entries ('일반').
  final String? group;

  /// Column-only section body (no Scaffold, no scrolling).
  final WidgetBuilder builder;
}

/// Production order (table below). M4 prepends the 'app.account' entry.
List<SettingsSectionEntry> defaultSettingsSections();

final settingsSectionsProvider = Provider<List<SettingsSectionEntry>>(
    (ref) => defaultSettingsSections(), name: 'settingsSectionsProvider');

/// Scaffold + AppBar('설정', close button → onClose) + ListView of
/// [group header] + section header + section body; content width ≤ 720,
/// centered (iPad landscape).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, required this.onClose});
  final VoidCallback onClose;
}

/// '저장 공간': CORE StorageInfo and PersistenceStatus.
/// - StorageInfo: shows latestStorageInfoProvider (re-queried when the section
///   is shown; "다시 확인" = ref.invalidate(latestStorageInfoProvider)), and
///   storageInfoProvider while that is loading. latestStorageInfoProvider is
///   the ONLY place in the app shell that calls refreshStorageInfo(); right
///   after it returns it calls ref.invalidate(storageInfoProvider) (계약 7.2.12
///   v1.1, C11-10) so the LIBRARY / EDITOR banners and diagnostics see the new
///   persistGranted / usage. This section uses the returned value directly.
/// - PersistenceStatus: persistenceStatusProvider (first value arrives right
///   after subscribing — 계약 7.2.12 v1.1, C11-09; the first frame falls back
///   to NoteStore.persistenceStatus).
/// Shows backend, durable, multi-tab safety, persistGranted, usage / quota,
/// missing browser features, pending writes, last commit time + latency,
/// consecutive failures.
class StorageSection extends ConsumerWidget {
  const StorageSection({super.key});
}

/// '앱 정보': build label, renderer, standalone, startup times, error count
/// + list, "진단 정보 복사", "새 버전 확인", "백업 내보내기",
/// "오픈소스 라이선스" (showLicensePage).
/// "백업 내보내기": prepareBackup() with a progress row (button disabled):
/// spinner + '백업을 만드는 중…' + [취소]. [취소] calls
/// BackupCancelToken.cancel() → prepareBackup returns null at once, the
/// button is enabled again, no snackbar, no errorLog record (only the wait
/// ends; CORE's write queue keeps retrying — 계약 7.2.9 v1.2, C12-09).
/// While waiting, if storageWarningOf(storageInfoProvider,
/// persistenceStatusProvider) == StorageWarning.writeFailing the row adds
/// '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.'.
/// On a BackupFile → BackupReadySheet; the sheet's buttons call
/// deliverBackup() from their own tap (fresh user activation for share /
/// download).
class AboutSection extends ConsumerStatefulWidget {
  const AboutSection({super.key});
}

/// Backup bytes ready to hand to the browser.
@immutable
final class BackupFile {
  const BackupFile({required this.bytes, required this.fileName});
  final Uint8List bytes;
  final String fileName;               // backupFileName(now)
  String get mimeType => 'application/json';
}

enum BackupDelivery { share, download }

enum BackupExportOutcome { shared, downloaded, cancelled, unsupported, failed }

/// Ends the WAIT of one prepareBackup call (계약 7.2.9 v1.2, C12-09: flush()
/// and exportBackupJson() — which flushes first — neither complete nor fail
/// while a commit is being retried). Cancelling does not touch the store.
final class BackupCancelToken {
  BackupCancelToken();
  bool get isCancelled;
  /// Idempotent. The pending prepareBackup completes with null right away.
  void cancel();
}

/// Step 1: store.flush() → store.exportBackupJson() (계약 7.2.12 v1.1,
/// C11-08). Never throws. No timeout of its own: during a write retry both
/// calls stay pending (계약 7.2.9 v1.2), so the caller offers [cancel].
/// - success → BackupFile.
/// - flush / export error → null + one record in [errorLog] (source: manual).
/// - cancel.cancel() before completion → null at once, NO errorLog record;
///   a late result or error of the abandoned calls is dropped (a storage
///   failure is already logged by CoreModule via PersistenceStatus.lastError).
Future<BackupFile?> prepareBackup({
  required NoteStore store,
  required AppErrorLog errorLog,
  BackupCancelToken? cancel,
  DateTime? now,
});

/// Step 2, called directly from a BackupReadySheet button:
/// share → web.shareFile(...) (shared / cancelled / unsupported / failed),
/// download → web.downloadBytes(...) (downloaded / unsupported).
/// Never throws; `failed` adds one record to [errorLog] (source: manual),
/// `cancelled` adds none.
Future<BackupExportOutcome> deliverBackup(
  BackupFile file, {
  required BackupDelivery via,
  required WebPlatform web,
  required AppErrorLog errorLog,
});

/// Bottom sheet: file name + size, [공유 · 파일에 저장] (only when
/// web.canShareFiles(mimeType: 'application/json')) and [내려받기].
/// Closes with the BackupExportOutcome of the pressed button (null = dismissed).
class BackupReadySheet extends StatelessWidget {
  const BackupReadySheet({super.key, required this.file, required this.web,
      required this.errorLog});
  final BackupFile file;
  final WebPlatform web;
  final AppErrorLog errorLog;
}

/// 'noteapp-backup-20261104-182031.json' (local time).
String backupFileName(DateTime localTime);
```

`defaultSettingsSections()` (순서는 PLAN 8 IA: 계정 · 동기화 상태 · 저장 용량 → 입력 → 펜 → 일반 → 개발자 표시, 마지막에 앱 정보):

| 순서 | `id` | `group` | `title` | `builder` | 소유 | 시점 |
|---|---|---|---|---|---|---|
| 0 | `app.account` | — | 계정 · 동기화 | `AccountSyncSection()` (INFRA, SYNC `authServiceProvider`·`syncEngineProvider` 사용) | INFRA | **M4** |
| 1 | `app.storage` | — | 저장 공간 | `StorageSection()` | INFRA | 이번 |
| 2 | `editor.input` | — | 입력 | `EditorInputSettingsSection()` | EDITOR | 이번 |
| 3 | `editor.pen` | — | 펜 | `EditorPenSettingsSection()` | EDITOR | 이번 |
| 4 | `editor.page` | 일반 | 페이지 넘김 | `EditorPageSettingsSection()` | EDITOR | 이번 |
| 5 | `library.newNote` | 일반 | 새 노트 기본값 | `LibrarySettingsSection()` | LIBRARY | 이번 |
| 6 | `editor.developer` | — | 개발자 표시 | `EditorDeveloperSettingsSection()` | EDITOR | 이번 |
| 7 | `app.about` | — | 앱 정보 | `AboutSection()` | INFRA | 이번 |

- 테마 설정(PLAN 8 '일반 › 테마')은 다크 모드와 함께 이후(1.3).
- 백업 내보내기 문구: 내려받음 '백업 파일을 내려받았어요. 파일 앱에 보관해 주세요.', 공유함 '공유 시트로 보냈어요. 파일 앱에 저장됐는지 확인해 주세요.', 취소 — 문구 없음, 미지원 '이 기기에서는 이 방법으로 백업 파일을 저장할 수 없어요. 다른 방법을 눌러 주세요.', 실패(만들기·공유 오류) '백업을 만들지 못했어요. 진단 정보를 복사해 보내 주세요.' 만드는 중에는 버튼 비활성 + 진행 표시('백업을 만드는 중…' + [취소]).
- **백업 준비 대기** (INFRA-3-3, 계약 7.2.9 v1.2 C12-09): CORE 쓰기 `Future`는 커밋 뒤 완료되고, 커밋이 실패해 재시도하는 동안에는 **완료도 오류도 없다**(`NoteStore.flush()`도 같음 — 앞에 쌓인 쓰기가 재시도 중이면 그 뒤). `exportBackupJson()`은 먼저 flush하므로 같다. 그래서 `prepareBackup`은 시간 제한으로 실패 처리하지 않고(재시도가 곧 성공하면 그대로 백업이 나온다) 진행 표시에 **[취소]**를 둔다: 누르면 대기만 끊고 `null`, 버튼 다시 활성, 스낵바·errorLog 없음(쓰기 큐·메모리 상태는 그대로 — 계약 7.2.9 '소비하는 쪽은 저장 실패를 예외로 기대하지 않는다'). 기다리는 동안 `storageWarningOf(info, status) == StorageWarning.writeFailing`이면 진행 줄 아래에 '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.'(셸 문구, `AppStrings`)를 띄운다 — 배너 문구(계약 7.4.5 고정 문장)와는 다른 진행 표시 문구다. 저장 실패 자체는 `CoreModule`이 `PersistenceStatus.lastError`로 errorLog에 남기므로 취소가 따로 기록하지 않는다.
- 두 단계로 나눈 이유: `navigator.share`는 사용자 탭 직후(사용자 활성화)에만 허용되고, Safari가 `await`(flush·JSON 생성) 뒤에도 활성화를 유지하는지 미확인이다. 바이트를 먼저 만들고 시트의 버튼 탭에서 바로 공유·내려받기를 부르면 두 경로 모두 새 활성화를 받는다. iPadOS 홈 화면 앱에서 `<a download>`가 동작하지 않을 수 있는 위험(11절)에 대한 두 번째 경로가 공유 시트의 '파일에 저장'이다.
- **기반 단계 주의** (INFRA-2-2): B2 가짜 저장소의 `exportBackupJson`은 `UnimplementedError`다(계약 7.6, CORE T19에서 구현). 그래서 `backup_export_test`·`about_section_test`는 가짜 저장소에 위임하지 않고 `CountingNoteStore`의 `exportBackupResult`(결과·예외 주입, 5.7)를 쓴다. 실제 형식 확인은 CORE T19 테스트 몫이다.

#### 4.5.9 모듈 어댑터 — `src/modules/`

모듈 순서와 override 주체는 계약 7.3.3 그대로다: `core` → `pdf`(비필수) → `featureWiring`(정적) → (M4) `sync`.

```dart
/// Opens local storage via package:note_core (계약 7.2.12, X1) and owns
/// the store's lifetime.
final class CoreModule extends AppModule {
  CoreModule({
    Future<NoteStore> Function(NoteStoreConfig) open = openNoteStore,
    Future<void> Function(NoteStoreConfig) deleteLocalData = deleteLocalNoteData,
    NoteStoreConfig Function(AppModuleContext context) configFor =
        defaultNoteStoreConfig,
  });

  static const String moduleId = 'core';

  @override
  String get id => moduleId;
  @override
  String get label => '노트 저장소 여는 중';
  @override
  Duration get startTimeout => const Duration(seconds: 20); // critical

  /// config = configFor(context); _opening = open(config); store = await
  /// _opening; if onStartAbandoned() already ran → return without publishing
  /// (the late store is closed there). Else context.publish<NoteStore>(store);
  /// subscribes store.persistenceStatusStream (its first event is the current
  /// status, right after listen — 계약 7.2.12 v1.1) and logs every NEW
  /// lastError (lastErrorAt differs from the last seen event; a non-null
  /// lastError in the first event is logged once) to context.errorLog
  /// (source: module, 계약 7.4.5).
  @override
  Future<void> start(AppModuleContext context);

  /// start() exceeded 20 s (INFRA-2-9). Marks the attempt abandoned; when
  /// _opening later completes with a NoteStore it is closed AT ONCE (close
  /// failure → errorLog, source: module); a late open failure is ignored (the
  /// timeout is already reported). Completes when that close has finished, so
  /// a retry's openNoteStore / deleteLocalNoteData never meets the late store
  /// (CORE 6.18: StateError while a store with that config is open).
  /// Idempotent; never closes a store twice.
  @override
  Future<void> onStartAbandoned();

  /// [noteStoreProvider.overrideWithValue(store)] — the only CORE override.
  @override
  List<Override> overrides();

  /// store.flush(); the caller enforces 500 ms.
  @override
  Future<void> onAppHidden();

  /// Cancels the status subscription, then store.close().
  @override
  Future<void> stop();

  /// () => deleteLocalData(<config of the last start attempt>).
  @override
  Future<void> Function()? get resetLocalData;

  /// True for NoteStoreOpenException with reason migrationFailed, corrupted
  /// or unknown. False for storageUnavailable (reset cannot help),
  /// newerSchema (would destroy data a newer build can read) and timeouts.
  @override
  bool canResetAfter(Object error);
}

/// NoteStoreConfig(
///   ownerId: context.ownerId,            // new database only (S7)
///   web: WebStorageConfig(
///     sqlite3WasmPath: context.web.resolveAppUrl('sqlite3.wasm'),
///     driftWorkerPath: context.web.resolveAppUrl('drift_worker.js'),
///   ),
/// ) — every other field keeps the CORE 4.8 default
/// (databaseName 'noteapp', requestPersistentStorage true, …).
/// 계약 7.2.12 · 7.4.3 (v1.1, C11-11): on the web both paths are ABSOLUTE
/// URLs resolved against document.baseURI; CORE's Uri.base.resolve(path)
/// returns them unchanged. Never relative in production.
NoteStoreConfig defaultNoteStoreConfig(AppModuleContext context);

/// Initializes package:pdf_io. Non-critical: PDF failure must not block notes.
final class PdfModule extends AppModule {
  PdfModule({
    Future<void> Function() initialize = initializePdfIo,
    List<Override> Function() pdfOverrides = pdfIoOverrides,
  });

  static const String moduleId = 'pdf';

  @override
  String get id => moduleId;
  @override
  String get label => 'PDF 엔진 준비 중';
  @override
  bool get critical => false;
  @override
  Duration get startTimeout => const Duration(seconds: 10);

  /// await initialize() — returns in < 10 ms; the wasm warm-up is not
  /// awaited (계약 7.2.19).
  @override
  Future<void> start(AppModuleContext context);

  /// pdfOverrides(): the ONLY override of ink.pageBackgroundBuildersProvider
  /// (+ pdfIoConfigProvider). Not used when start failed → default builders
  /// (template only).
  @override
  List<Override> overrides();
}

/// Static wiring between feature packages (계약 7.3.3). No async work.
/// PDF-related overrides are added only when the PDF module started.
/// The PDF render stats section takes no injected stats: pdfRenderStatsProvider
/// is read as is (B4: zero-stats notifier, 계약 7.6 B4 v1.2 — C12-06).
final class FeatureWiringModule extends AppModule {
  FeatureWiringModule({
    LibraryPdfImportAction importPdf = importPdfAsNewNote,
    LibraryPdfExportAction exportPdf = exportNotesAsPdf,
    List<PdfMenuAction> Function() moreMenuActions = pdfEditorMoreMenuActions,
    List<PdfMenuAction> Function() addPageActions = pdfEditorAddPageSources,
  });

  static const String moduleId = 'featureWiring';

  @override
  String get id => moduleId;
  @override
  String get label => '화면 연결 중';
  @override
  bool get critical => false;
  @override
  Duration get startTimeout => const Duration(seconds: 1);

  /// pdfAvailable = context.isStarted(PdfModule.moduleId); builds the list.
  @override
  Future<void> start(AppModuleContext context);

  /// In this order:
  ///   ...featureEditorOverrides(), ...featureLibraryOverrides(),
  ///   pageThumbnailRendererProvider.overrideWith(
  ///       (ref) => ref.watch(inkPageThumbnailRendererProvider)),
  ///   if (pdfAvailable) ...[
  ///     libraryPdfImportActionProvider.overrideWithValue(importPdf),
  ///     libraryPdfExportActionProvider.overrideWithValue(exportPdf),
  ///     editorExtensionsProvider.overrideWithValue(editorExtensionsFromPdf(
  ///         moreMenu: moreMenuActions(), addPageSources: addPageActions())),
  ///     devOverlaySectionsProvider.overrideWith(
  ///         (ref) => [pdfRenderStatsSection(ref)]),
  ///   ]
  @override
  List<Override> overrides();
}

// --- src/modules/pdf_wiring.dart (pure mapping, unit-tested) ---

/// EditorMenuContext → PdfMenuInvocation (06-pdf 5.5 example).
/// onNavigate is navigateToPage itself: focusRectPt is passed through
/// unchanged (계약 7.2.17 v1.1, C11-21 — displayed page pt of the note's
/// Page.size, origin top-left, y down; INFRA never converts it).
PdfMenuInvocation pdfMenuInvocationOf(EditorMenuContext menu) =>
    PdfMenuInvocation(
      noteId: menu.noteId,
      currentPageId: menu.currentPageId,
      selectedPageIds: menu.selectedPageIds,
      onNavigate: menu.navigateToPage,
    );

/// Same id / label / icon. onSelected: (ctx, m) => action.run(ctx,
/// pdfMenuInvocationOf(m)); isEnabled: null when action.isEnabled is null,
/// else (m) => action.isEnabled!(pdfMenuInvocationOf(m)).
EditorMenuItem editorMenuItemFromPdf(PdfMenuAction action);

/// EditorExtensions(moreMenuItems: [...], addPageSources: [...]),
/// appBarTrailing stays null (reserved).
EditorExtensions editorExtensionsFromPdf({
  required List<PdfMenuAction> moreMenu,
  required List<PdfMenuAction> addPageSources,
});

/// Lines over PDF render stats, recomputed at most once per [minInterval]
/// (≤ 4 Hz as DevOverlaySection requires).
final class PdfRenderStatsLines extends ChangeNotifier
    implements ValueListenable<List<String>> {
  PdfRenderStatsLines(
    ValueListenable<PdfRenderStats> stats, {
    Duration minInterval = const Duration(milliseconds: 250),
  });

  @override
  List<String> get value;

  /// Removes the stats listener and cancels the pending timer.
  @override
  void dispose();
}

/// Three lines (6.8): memory, queue, timing.
List<String> formatPdfRenderStats(PdfRenderStats stats);

/// DevOverlaySection(id: 'pdf.render', title: 'PDF 렌더',
///   lines: PdfRenderStatsLines(ref.watch(pdfRenderStatsProvider)))
/// — the lines object is disposed with the provider (ref.onDispose).
/// Reads the REAL pdfRenderStatsProvider (no injection parameter): in the
/// foundation stage PDF B4 builds it without exception as
/// ValueNotifier(PdfRenderStats.zero) (계약 7.6 B4 v1.2, C12-06), so a
/// container holding only the module overrides can build this section.
DevOverlaySection pdfRenderStatsSection(Ref ref);

/// [CoreModule(), PdfModule(), FeatureWiringModule()] — ids unique.
List<AppModule> productionModules();
```

#### 4.5.10 셸 provider — `src/providers.dart`

```dart
// Overridden by BootstrapApp with values created before the scope
// (계약 7.3.3 '셸 provider').
final buildInfoProvider = Provider<BuildInfo>(
    (ref) => BuildInfo.fromEnvironment(), name: 'buildInfoProvider');
final webPlatformProvider = Provider<WebPlatform>(
    (ref) => createWebPlatform(), name: 'webPlatformProvider');
final runtimeInfoProvider = Provider<RuntimeInfo>(
    (ref) => RuntimeInfo.detect(ref.watch(webPlatformProvider)),
    name: 'runtimeInfoProvider');
final appErrorLogProvider = Provider<AppErrorLog>(
    (ref) => throw UnimplementedError(
        'appErrorLogProvider must be overridden by the app shell'),
    name: 'appErrorLogProvider');
final startupReportProvider = Provider<StartupReport>(
    (ref) => throw UnimplementedError(
        'startupReportProvider must be overridden by the app shell'),
    name: 'startupReportProvider');
final appBootstrapperProvider = Provider<AppBootstrapper>(
    (ref) => throw UnimplementedError(
        'appBootstrapperProvider must be overridden by the app shell'),
    name: 'appBootstrapperProvider');

// Not overridden in production (tests override appScreenBuildersProvider).
final appScreenBuildersProvider = Provider<AppScreenBuilders>(
    (ref) => AppScreenBuilders.production(), name: 'appScreenBuildersProvider');
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = createAppRouter(screens: ref.watch(appScreenBuildersProvider));
  ref.onDispose(router.dispose);
  return router;
}, name: 'appRouterProvider');
final appNavigatorProvider = Provider<AppNavigator>(
    (ref) => GoRouterAppNavigator(ref.watch(appRouterProvider)),
    name: 'appNavigatorProvider');

/// CORE StorageInfo re-queried (persisted() / estimate() inside CORE) each
/// time the storage section or a diagnostics copy needs it. The app shell's
/// ONLY caller of refreshStorageInfo(). 계약 7.2.12 (v1.1, C11-10): after it
/// returns, invalidate storageInfoProvider (a plain Provider that never
/// re-reads by itself) so other screens — LIBRARY / EDITOR banners,
/// diagnostics — see the new persistGranted / usage; this provider's own
/// readers use the returned value. backend / isDurable never change at
/// runtime, so the notDurable banner decision is unaffected.
/// `ref.mounted` guards the case where the section was closed during the
/// await — that value then reaches other screens with the next refresh
/// (Riverpod 3.4.3: Ref use after dispose throws UnmountedRefException;
/// invalidate after await + mounted guard 확인함, scratch infra3/invalidate).
final latestStorageInfoProvider =
    FutureProvider.autoDispose<StorageInfo>((ref) async {
  final info = await ref.watch(noteStoreProvider).refreshStorageInfo();
  if (ref.mounted) ref.invalidate(storageInfoProvider);
  return info;
}, retry: noRetry, name: 'latestStorageInfoProvider');
```

---

## 5. 사용하는 다른 영역의 계약

초안의 '가정한 시그니처'(`openNoteCore`, `NoteCoreHandle`, `NoteCoreConfig`, `NoteCoreOpenException`, `EditorSettingsSection`, `startSync` 등)는 **모두 폐기**했다. 아래 코드 블록은 계약 7장의 원문 발췌(본문 생략)이고, 앱 셸에서 이 이름을 쓰는 곳은 모듈 어댑터(`app/lib/src/modules/*`), 화면 빌더(`screen_builders.dart`), 설정 섹션 목록(`settings_sections.dart`), 백업(`backup_export.dart`)뿐이다.

### 5.1 CORE (`package:note_core/note_core.dart`, 계약 7.2.2 · 7.2.9 · 7.2.12 · 7.2.14 — v1.2 기준)

```dart
// 계약 7.2.2 (원문 발췌)
typedef OwnerId = String;   typedef EpochMillis = int; // UTC ms since epoch
const OwnerId kLocalOwnerId = 'local';
enum NoteStoreOpenFailure { storageUnavailable, migrationFailed, corrupted, newerSchema, unknown }
final class NoteStoreOpenException extends NoteCoreException {
  const NoteStoreOpenException(this.reason, super.message, {this.cause});
  final NoteStoreOpenFailure reason;
  final Object? cause;
}

// 계약 7.2.12 (v1.2 기준 원문 그대로 — 블록은 v1.1 이후 바뀌지 않음, v1.2는 시그니처 변경 없음)
final class PersistenceStatus { /* CORE 4.8 */ }
enum StorageBackend { /* CORE 4.8 */ }
final class StorageInfo { /* CORE 4.8: backend, isDurable, isMultiTabSafe, missingBrowserFeatures,
                             persistGranted, usageBytes, quotaBytes */ }

enum StorageWarning { writeFailing, notDurable }
/// writeFailing when status.consecutiveFailures >= 3, else notDurable when !info.isDurable,
/// else null. LIBRARY (library screen) and EDITOR (editor screen) show the same banner text.
StorageWarning? storageWarningOf(StorageInfo info, PersistenceStatus status);

final class WebStorageConfig {
  /* CORE 4.8: sqlite3.wasm, drift_worker.js, blob DB name.
     (v1.1) Paths are resolved with Uri.base.resolve(path), so an absolute URL is used as is.
     In production the app shell ALWAYS passes absolute URLs resolved against
     document.baseURI (01-infra 6.4) — dart2js Uri.base is location.href, which breaks
     relative paths on deep links such as /notes/<id>. Relative paths are for tests only. */
}
final class NoteStoreConfig {
  /* CORE 4.8. ownerId is used only when a new database is created; a persisted owner
     (after reassignOwner) wins. requestPersistentStorage: web persist() is called during
     open and awaited at most 1 s; the result goes to StorageInfo.persistGranted.
     (v1.1) inMemory: true reports StorageBackend.nativeMemory → isDurable == false →
     storageWarningOf == notDurable, i.e. the storage banner shows (tests expect it). */
}

abstract interface class NoteStore {
  // ... CORE 4.8 (ownerId, library, trash, penPresets, settings, content, assets,
  //     thumbnails, sync, changes, persistenceStatus, storageInfo, openSession,
  //     flush, close) ...
  /// (v1.1) Emits the current persistenceStatus ONCE right after each listen, then on every
  /// change (same rule as the watch streams, LIBRARY C-1). The fake store does the same.
  Stream<PersistenceStatus> get persistenceStatusStream;
  IdGenerator get ids;                  // the store's generator (UUIDv7 in production)
  Clock get clock;                      // package:clock
  Future<StorageInfo> refreshStorageInfo();   // re-query persisted() / estimate()
  /// (v1.1) Backup (7.8, CORE 6.17): every active and trashed entity as CORE 6.3 JSON with
  /// field versions + asset metadata, NO asset bytes, no device settings / sync meta /
  /// thumbnails. One UTF-8 JSON document, deterministic order. Flushes first.
  Future<Uint8List> exportBackupJson();
}

/// Opens (and migrates) the database. Throws NoteStoreOpenException.
Future<NoteStore> openNoteStore(NoteStoreConfig config);
/// Drops the SQLite DB and the blob IndexedDB of [config] (startup error screen reset).
Future<void> deleteLocalNoteData(NoteStoreConfig config);

// 계약 7.2.14 (원문 발췌)
final pageThumbnailRendererProvider = Provider<PageThumbnailRenderer?>(
    (ref) => null, name: 'pageThumbnailRendererProvider');
final remoteAssetFetcherProvider = Provider<RemoteAssetFetcher?>(
    (ref) => null, name: 'remoteAssetFetcherProvider');
// syncBadgeProvider — 7.2.13
// (INFRA 메모, 계약 원문 아님) 계약 7.2.14의 승인된 CORE provider 중 INFRA가 쓰는 것:
// noteStoreProvider(앱 셸 override 필수, 기본 UnimplementedError), persistenceStatusProvider,
// storageInfoProvider, noRetry.
```

계약 7.2.12 본문 규칙(v1.2 기준, INFRA에 해당하는 두 문장, 원문 그대로):

- 웹 `navigator.storage.persist()`·`estimate()` 호출은 **CORE만** 한다. INFRA 앱 정보·진단은 `storageInfoProvider`/`refreshStorageInfo()` 값을 표시한다.
- `storageInfoProvider`는 plain `Provider`라 자동으로 다시 읽지 않는다(v1.1). `refreshStorageInfo()`를 부른 쪽은 끝난 뒤 `ref.invalidate(storageInfoProvider)`를 불러 다른 화면(LIBRARY·EDITOR 배너, 진단)이 새 `persistGranted`·사용량을 보게 한다. 부른 화면 자신은 반환값을 바로 써도 된다. `backend`·`isDurable`은 실행 중 바뀌지 않으므로 `storageWarningOf`의 `notDurable` 판정에는 영향이 없다.

계약 7.2.9 v1.2 '쓰기 `Future`의 완료 시점'(C12-09 — INFRA에 해당하는 두 문장, 원문 그대로):

- 저장소 변경 메서드(`LibraryRepository`·`TrashRepository`·`PenPresetRepository`·`SettingsRepository`의 쓰기, `createNote` 포함)는 **DB 커밋 뒤** 완료된다. 커밋이 실패하면 CORE `WriteQueue`가 무한 재시도(02-core 6.9: 100 ms → 400 ms → 1.6 s → 5 s 간격)하므로 그동안 **완료되지도, 오류로 끝나지도 않는다**. 원인은 `PersistenceStatus`·`storageWarningOf`(`writeFailing`)로만 보인다. `NoteStore.flush()`·`NoteSession.flush()`도 같다(앞에 쌓인 쓰기가 재시도 중이면 그 뒤).
- 소비하는 쪽은 저장 실패를 예외로 기대하지 않는다(대기가 끝나지 않을 수 있음). 기다리는 화면의 처리는 각 영역이 정한다: PDF 가져오기·내보내기 진행 창은 `writeFailing`이면 지연 문구 + 닫기·취소(06-pdf), EDITOR 뒤로가기는 '저장하는 중…'을 띄우고 계속 기다림(04-editor 6.17.4). 어느 경우든 메모리 상태와 쓰기 큐는 그대로 남아 계속 재시도된다.

INFRA의 `flush()` 대기는 모두 상한이나 취소가 있다(INFRA-3-3): `onAppHidden()` → 호출자 500 ms 제한(4.5.4), `UpdateChecker.applyUpdate()` → `notifyAppHidden()`(500 ms) 뒤 새로고침(6.11), 백업 준비 `prepareBackup` → 사용자 [취소](4.5.8 — `exportBackupJson()`도 먼저 flush하므로 같다). `shutdown()`의 `stop()`(= `store.close()`)도 모듈마다 2초 제한이다(4.5.4 `AppBootstrapper.shutdown`).

```dart
// 계약 7.6 'B2 테스트·개발 도우미' (v1.1 도입, v1.2 기준 변경 없음 — INFRA가 쓰는 두 진입점, 원문 그대로)
// package:note_core/testing.dart — web-safe, test/ only
NoteStore createFakeNoteStore({Clock? clock, IdGenerator? ids, OwnerId ownerId = kLocalOwnerId,
    bool seedDefaultPenPresets = true,
    StorageInfo storageInfo = const StorageInfo(backend: StorageBackend.nativeFile),
    FakeNoteStoreFaults? faults});
/// Failure / latency injection for other areas' tests.
final class FakeNoteStoreFaults {
  FakeNoteStoreFaults();
  /// The next [count] commits fail with [error]; PersistenceStatus reports them and the
  /// in-memory state is kept (like the real WriteQueue retry).
  void failNextCommits(int count, {Object error = const FormatException('injected')});
  /// Every commit completes after [delay] (use with fake_async).
  Duration commitDelay = Duration.zero;
}
// StrokeFixtures, newerVersionWinsPolicy — CORE 4.10

// package:note_core/testing_vm.dart — VM tests only (lib_exceptions, 7.4.2)
/// Real CORE on NativeDatabase (filePath null = in-memory). deviceNodeId fixes the HLC node.
/// storageInfo: value reported by NoteStore.storageInfo; null = the real backend
/// (in-memory → nativeMemory → notDurable banner).
Future<NoteStore> openTestNoteStore({Clock? clock, IdGenerator? ids,
    OwnerId ownerId = kLocalOwnerId, String? filePath, String? deviceNodeId,
    bool seedDefaultPenPresets = true, StorageInfo? storageInfo});
```

INFRA가 쓰는 CORE 멤버 (CORE 4.8·4.10 승인분 — 필드 이름은 02-core 확정본을 따른다):

| 사용처 | CORE 멤버 |
|---|---|
| `CoreModule` (I10) | `NoteStoreConfig(ownerId:, web:)`, `WebStorageConfig(sqlite3WasmPath:, driftWorkerPath:)`(절대 URL — 계약 7.2.12·7.4.3 v1.1), `openNoteStore`, `NoteStore.flush()`·`close()`·`persistenceStatusStream`(구독 즉시 현재 값 1회 — 계약 7.2.12 v1.1)·`storageInfo`·`ownerId`, `deleteLocalNoteData`, `noteStoreProvider.overrideWithValue` |
| 시작 오류 화면 (I5) | `NoteStoreOpenException.reason`(`NoteStoreOpenFailure` 5종) |
| 저장 공간 섹션·진단 (I9, I3) | `storageInfoProvider`, `NoteStore.refreshStorageInfo()`(`latestStorageInfoProvider` 한 곳, 끝나면 `ref.invalidate(storageInfoProvider)` — 계약 7.2.12 v1.1), `persistenceStatusProvider`, `StorageInfo`·`StorageBackend`·`PersistenceStatus` 필드(`pendingOps`, `isWriting`, `lastCommittedAt`, `lastCommitLatency`, `lastError`, `lastErrorAt`, `consecutiveFailures`) |
| 앱 정보 '백업 내보내기' (I9) | `NoteStore.flush()`·`NoteStore.exportBackupJson()` — **계약 7.2.12 v1.1**(C11-08, 위 블록). `prepareBackup`(4.5.8) 한 곳에서만 부른다. 쓰기 재시도 중에는 둘 다 끝나지 않으므로(계약 7.2.9 v1.2, C12-09) 대기는 사용자 [취소]로 끊는다(INFRA-3-3), `persistenceStatusProvider`·`storageInfoProvider` → `storageWarningOf`로 지연 문구 |
| `FeatureWiringModule` (I10b) | `pageThumbnailRendererProvider` |
| 테스트 | `createFakeNoteStore({Clock? clock, IdGenerator? ids, OwnerId ownerId = kLocalOwnerId, bool seedDefaultPenPresets = true, StorageInfo storageInfo = const StorageInfo(backend: StorageBackend.nativeFile), FakeNoteStoreFaults? faults})` (`testing.dart`, 기반 단계 B2 — 위 블록), `openTestNoteStore({Clock? clock, IdGenerator? ids, OwnerId ownerId = kLocalOwnerId, String? filePath, String? deviceNodeId, bool seedDefaultPenPresets = true, StorageInfo? storageInfo})` (`testing_vm.dart`, VM 전용 — 위 블록. INFRA V5는 실제 경로 `CoreModule` → `openNoteStore(NoteStoreConfig(inMemory: true))`를 쓰므로 직접 부르지 않고, 필요할 때만 쓴다) |
| M4 `SyncModule` | `syncBadgeProvider`·`remoteAssetFetcherProvider` override, `NoteStore.ownerId`(실제 소유자) |

B2 단계 값(계약 7.6 v1.1)과 INFRA 테스트:

- 가짜 저장소 기본 `storageInfo` = `nativeFile` → 배너 없음. 가짜 `exportBackupJson`은 B2에서 `UnimplementedError`(CORE T19에서 구현) → `backup_export_test`·`about_section_test`는 지금처럼 `CountingNoteStore`의 결과 주입(`exportBackupResult`, 5.7)을 쓴다.
- 가짜 `SyncStore`는 `ownerId`·`deviceNodeId`·`pendingChanges()`(빈 목록)·`watchPendingCount()`(0)만 값을 주고 나머지는 `UnsupportedError` — 이번 범위 INFRA는 `SyncStore`를 쓰지 않는다.
- `openTestNoteStore`는 CORE T6 전까지 `UnimplementedError`, 실제 `openNoteStore`도 B2에서 `UnimplementedError` 허용 → 실제 CORE를 쓰는 INFRA 테스트(V5·V6)는 `integration` 태그라 동시 개발 중 기본 `ws test`에서 건너뛴다(`app/dart_test.yaml`, 계약 7.4.8 v1.1).

CORE에 대한 기대 (초안의 '추가 요청'은 계약 7.4.9·CORE-S5로 모두 답이 났다):

| # | 기대 | 근거 |
|---|---|---|
| C-I1 | `openNoteStore`의 알려진 실패는 `NoteStoreOpenException(reason)`로만 던진다. 그 밖의 예외는 오류 화면의 '그 외' 문구 | 계약 7.2.2 |
| C-I2 | 웹 `persist()`는 열기 안에서 최대 1초 기다리고 결과는 `StorageInfo.persistGranted`. INFRA는 따로 요청하지 않는다 | 계약 7.2.12 |
| C-I3 | `WebStorageConfig`의 두 경로는 `Uri.base.resolve(path)`로 해석되므로 **절대 URL**은 그대로 쓰인다(CORE 변경 없음). 앱 셸은 운영에서 항상 `document.baseURI` 기준 절대 URL만 넘긴다(4.4, 6.4) | 계약 7.2.12·7.4.3 v1.1 (C11-11) |
| C-I4 | `flush()`는 보통 500ms 안에 끝난다. 넘으면 앱 셸이 기다림만 끊고(쓰기는 계속) `errorLog`에 남긴다. 커밋 재시도 중에는 끝나지도 오류로 끝나지도 않는다 — INFRA는 이를 예외로 기대하지 않고 모든 대기에 상한(500ms)이나 취소(백업)를 둔다(위 7.2.9 요약) | 계약 X1, 계약 7.2.9 v1.2 (C12-09) |
| C-I5 | `deleteLocalNoteData(config)`는 스토어가 열려 있지 않을 때(열기 실패 후, 또는 `shutdown()`으로 닫은 뒤) 호출된다. 열린 저장소가 있으면 `StateError`(CORE 6.18) — 시간 초과 뒤 늦게 열린 저장소도 먼저 닫는다(6.4 2-2) | 계약 7.2.12, CORE 6.18 |
| C-I6 | Chrome 첫 `openNoteStore` 시간(빈 DB / 획 1만 개, CORE-S5)을 9.2 결과로 공유 → `CoreModule.startTimeout` 20초 근거 | CORE-S5, INFRA-S2 |

### 5.2 EDITOR (`package:feature_editor/feature_editor.dart`, 계약 7.2.17)

```dart
// 계약 7.2.17 (v1.2 기준 원문 그대로 — v1.1 이후 변경 없음)
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.noteId, this.initialPageId, required this.onClose,
      this.onOpenSettings});
  final String noteId;
  /// null → last viewed position of this note, else page 0 at fit width.
  final String? initialPageId;
  /// Back button / system back, called AFTER session.flush(). A missing note shows a
  /// message with a button that calls this.
  final VoidCallback onClose;
  /// "설정" in the more menu (hidden when null).
  final VoidCallback? onOpenSettings;
}
List<Override> featureEditorOverrides() => const <Override>[];

@immutable
class EditorMenuContext {
  const EditorMenuContext({required this.noteId, required this.pageIds,
      required this.currentPageIndex, this.selectedPageIds = const [], required this.navigateToPage});
  final String noteId;
  final List<String> pageIds;                 // note order
  final int currentPageIndex;
  final List<String> selectedPageIds;         // page panel multi-select, note order
  /// Jump/scroll to the page; when focusRectPt is given, bring that page rect into view.
  /// (v1.1) focusRectPt is in displayed page coordinates: pt of the note's Page.size,
  /// origin top-left, y down — same as core.Stroke points (PDF converts its search hits).
  final void Function(String pageId, Rect? focusRectPt) navigateToPage;
  String? get currentPageId;
}
@immutable
class EditorMenuItem { /* EDITOR 4.5: id, label, icon, onSelected(context, menu), isEnabled */ }
@immutable
class EditorExtensions {
  const EditorExtensions({this.moreMenuItems = const [], this.addPageSources = const [],
      this.appBarTrailing});
  final List<EditorMenuItem> moreMenuItems;   // PDF: export, share, print, search
  final List<EditorMenuItem> addPageSources;  // PDF: insert pages from PDF
  final WidgetBuilder? appBarTrailing;        // reserved, unused in this scope
}
final editorExtensionsProvider = Provider<EditorExtensions>(
    (ref) => const EditorExtensions(), name: 'editorExtensionsProvider');

@immutable
class DevOverlaySection {
  const DevOverlaySection({required this.id, required this.title, required this.lines});
  final String id;
  final String title;
  final ValueListenable<List<String>> lines;  // short text lines, updated ≤ 4 Hz
}
/// Extra developer-overlay blocks from other areas (INFRA wires PDF render stats).
final devOverlaySectionsProvider = Provider<List<DevOverlaySection>>(
    (ref) => const [], name: 'devOverlaySectionsProvider');

// EditorSettings / InputMode / PageFlipMode / PalmRejectionSettings / GestureSettings
// — EDITOR 4.8, with `final ink.PressureMode pressureMode` (EDITOR's own enum removed).
final editorSettingsProvider =
    NotifierProvider<EditorSettingsNotifier, EditorSettings>(EditorSettingsNotifier.new,
        name: 'editorSettingsProvider');
// Settings sections (Column only, no Scaffold): EditorInputSettingsSection,
// EditorPenSettingsSection, EditorPageSettingsSection, EditorDeveloperSettingsSection.
// StylusExtrasSource / stylusExtrasProvider — EDITOR 4.7 (unchanged, default NoStylusExtras).
```

- `focusRectPt`(v1.1, C11-21): INFRA는 `pdf_wiring`에서 `navigateToPage`를 `PdfMenuInvocation.onNavigate`로 **그대로 넘길 뿐** 좌표를 바꾸지 않는다(계약 7.2.17 'INFRA(전달만)').
- `EditorMenuItem` 필드(EDITOR 4.5, 계약 승인): `id`(String), `label`(String), `icon`(IconData), `onSelected`(`Future<void> Function(BuildContext context, EditorMenuContext menu)`), `isEnabled`(`bool Function(EditorMenuContext menu)?`). `editorMenuItemFromPdf`(4.5.9)가 이 생성자를 쓴다.
- INFRA는 `editorSettingsProvider`·`stylusExtrasProvider`를 override하지 않는다(계약 7.3.3 표에 없음). 필압 모드는 EDITOR가 `ink.pressureModeProvider.notifier.set()`으로 넣는다.

### 5.3 LIBRARY (`package:feature_library/feature_library.dart`, 계약 7.2.18)

```dart
// 계약 7.2.18 (v1.2 기준 원문 그대로 — v1.1 이후 변경 없음)
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.folderId, required this.onOpenFolder,
      required this.onOpenNote, required this.onOpenSettings});
  final String? folderId;                     // null = 홈; unknown id → 'folder missing' view
  final ValueChanged<String?> onOpenFolder;   // null = 홈
  final ValueChanged<String> onOpenNote;      // also right after creating / importing a note
  final VoidCallback onOpenSettings;
}
List<Override> featureLibraryOverrides() => const <Override>[];

/// PDF import flow owned by pdf_io; returns the created note id or null (cancel / handled error).
typedef LibraryPdfImportAction = Future<String?> Function(BuildContext context, {String? folderId});
final libraryPdfImportActionProvider = Provider<LibraryPdfImportAction?>(
    (ref) => null, name: 'libraryPdfImportActionProvider');   // null → menu disabled '준비 중'

/// Multi-select bulk export (F-01) owned by pdf_io; null → button hidden.
typedef LibraryPdfExportAction = Future<void> Function(BuildContext context, List<String> noteIds);
final libraryPdfExportActionProvider = Provider<LibraryPdfExportAction?>(
    (ref) => null, name: 'libraryPdfExportActionProvider');

class LibrarySettingsSection extends ConsumerWidget { const LibrarySettingsSection({super.key}); }
// FolderIcons, FolderPalette, CoverPalette, coverForegroundFor — LIBRARY 4.4 (approved)
```

- 저장 경고 배너(계약 7.4.5 v1.1, C11-24): 라이브러리 화면의 배너 문구는 고정 문장이다. `notDurable` 배너에는 닫기 버튼이 있다(05-library 6.16.2) → INFRA V5 스모크는 **닫기 전에** 문구를 대조한다(8.3 G2).

- 라우트가 바뀌어도 `LibraryScreen`의 `State`가 유지된다(같은 페이지 키, 6.6) → LIBRARY는 `didUpdateWidget`에서 `folderId` 변화를 처리한다(05-library I-2 기대와 같음).

### 5.4 PDF (`package:pdf_io/pdf_io.dart`, 계약 7.2.19)

```dart
// 계약 7.2.19 (v1.2 기준 원문 그대로 — v1.1 이후 변경 없음)
Future<void> initializePdfIo({PdfIoConfig config = const PdfIoConfig()});   // idempotent, < 10 ms
/// The ONLY override of ink.pageBackgroundBuildersProvider:
///   [pdfBackgroundLayerBuilder, const ink.TemplateBackgroundLayerBuilder()] (+ pdfIoConfigProvider).
List<Override> pdfIoOverrides({PdfIoConfig? config});
/// LibraryPdfImportAction shape.
Future<String?> importPdfAsNewNote(BuildContext context, {String? folderId});
/// LibraryPdfExportAction shape: one PDF per note, then the result sheet (share all / download).
Future<void> exportNotesAsPdf(BuildContext context, List<String> noteIds);
List<PdfMenuAction> pdfEditorMoreMenuActions();   // pdf.export, pdf.share, pdf.print, pdf.search
List<PdfMenuAction> pdfEditorAddPageSources();    // pdf.insert
final class PdfMenuAction { /* PDF 4.11 */ }
final class PdfMenuInvocation { /* PDF 4.11: noteId, currentPageId, selectedPageIds, onNavigate */ }
final pdfRenderStatsProvider = Provider<ValueListenable<PdfRenderStats>>(/* PDF 4.12 */);
// PdfBackgroundLayerBuilder implements ink.PageBackgroundLayerBuilder, ink.PageBackgroundStillRenderer
```

- PDF 4.11 필드(계약 승인): `PdfMenuAction(id, label, icon, run, isEnabled)` — `run`은 `Future<void> Function(BuildContext context, PdfMenuInvocation invocation)`, `isEnabled`는 `bool Function(PdfMenuInvocation invocation)?`. `PdfMenuInvocation(noteId, currentPageId, selectedPageIds = const [], onNavigate)` — `onNavigate`는 `void Function(PageId pageId, Rect? focusRectPt)?`로 `EditorMenuContext.navigateToPage`와 같은 모양이다.
- `PdfRenderStats` 필드(PDF 4.7): `previewBytes`, `tileBytes`, `thumbnailBytes`, `liveImages`, `queued`, `inflight`, `rendered`, `cancelled`, `lastRenderMs`, `p95RenderMs`, `openDocuments`, `overBudgetBytes`.
- 기반 단계 B4의 자리표시(`importPdfAsNewNote`는 `null`, 메뉴 함수는 빈 목록)로도 `FeatureWiringModule`은 그대로 동작한다. B4 `pdfIoOverrides()`의 빌더 목록은 본문이 `UnimplementedError`일 수 있는 provider를 watch하지 않는다(00-review 2차 PDF-2-2) → `PdfModule`이 켜진 INFRA 테스트에서 INK가 `pageBackgroundBuildersProvider`를 읽어도 예외가 없다. INFRA `overrides_unique_test`는 가짜 `pdfOverrides`를 쓰고, `pdf_module_test`는 기본 인자(실제 `pdfIoOverrides`)의 `overrides()`로 만든 컨테이너에서 `ink.pageBackgroundBuildersProvider`를 한 번 read해(예외 없음, 2개) 이를 확인한다.
- **계약 7.6 B4 v1.2 (C12-06)**: 다른 영역이 기반 단계·동시 개발 중 읽는 PDF provider(`pdfIoOverrides()`가 override하는 provider, `pdfRenderStatsProvider`)는 B4에서도 예외 없이 만들어지고, `pdfRenderStatsProvider`의 B4 본문은 `ValueNotifier(PdfRenderStats.zero)`다. 그래서 `FeatureWiringModule`·`pdfRenderStatsSection(ref)`는 지금 모양 그대로(통계 주입 함수·테스트 전용 override 없이) 실제 `pdfRenderStatsProvider`를 읽는다(4.5.9). INFRA `feature_wiring_module_test`·`pdf_wiring_test`가 '모듈 overrides만 넣은 컨테이너에서 `pdf.render` 섹션의 `lines` 값을 읽어도 예외 없음'으로 확인한다(9.1). 실제 통계(PDF T8) 병합 뒤 G2에서도 같은 단언이 돈다 — 운영 루트 컨테이너도 모듈 overrides만 가지므로, 그때 예외가 나면 7.3.3 연결 누락이다.
- PDF 기대(06-pdf 5.5): 웹 정적 파일 추가 없음, COOP/COEP 불필요, `.wasm`은 `application/wasm`, `<base href>` 유지(6.9·6.12), VM 테스트의 빌드 훅 다운로드·gcc → CI 캐시(6.13), 브라우저 테스트는 `test/web/` + `tool/prepare_web_test.dart`(계약 7.4.8).

### 5.5 INK · SYNC

INK (`package:ink_engine/ink_engine.dart`, 계약 7.2.16 원문 발췌) — 앱 셸이 직접 쓰는 것은 썸네일 렌더러 provider 하나다:

```dart
final inkPageThumbnailRendererProvider = Provider<core.PageThumbnailRenderer>(
    (ref) => InkPageThumbnailRenderer(backgroundBuilders: ref.watch(pageBackgroundBuildersProvider),
        pencilGrain: ref.watch(pencilGrainProvider)),
    name: 'inkPageThumbnailRendererProvider');
```

- `pageBackgroundBuildersProvider`는 INFRA가 직접 override하지 않는다(`pdfIoOverrides()`만, 계약 7.2.16). v1.2 C12-03의 주석 정리('Read by inkPageControllerProvider and inkPageThumbnailRendererProvider; callers of InkPageThumbnail pass its value (the widget reads no provider).')는 앱 셸에 영향이 없다 — 앱 셸은 이 provider를 읽지 않고 `InkPageThumbnail`도 쓰지 않으며, 썸네일은 위 `inkPageThumbnailRendererProvider`를 `pageThumbnailRendererProvider`로 연결할 뿐이다.

SYNC (`package:sync_engine`, 계약 7.2.20 · 7.3.3 M4 행) — **이번 범위 앱은 `sync_engine`에 의존하지 않는다**(계약 7.1). M4 연결 때 쓸 이름(초안의 `startSync`/`SyncHandle` 가정은 폐기):

```dart
// 계약 7.2.13 (CORE, v1.2 기준 원문 그대로 — v1.1 이후 변경 없음)
@immutable
final class SyncBadge {
  const SyncBadge({required this.display, this.pendingChanges = 0, this.lastSyncedAt, this.issueCode});
  static const SyncBadge off = SyncBadge(display: SyncDisplayState.off);
  final SyncDisplayState display;
  final int pendingChanges;          // local changes not yet acknowledged
  final EpochMillis? lastSyncedAt;
  final String? issueCode;           // SYNC SyncIssueCode.name of the first blocking issue
  /// (v1.1) Value equality over all four fields (7.4.4) — the M4 override uses .distinct().
  @override bool operator ==(Object other);
  @override int get hashCode;
}

/// Default: off ("이 기기에 저장"). From M4 the app shell overrides it with SYNC's status.
final syncBadgeProvider = StreamProvider<SyncBadge>(
    (ref) => Stream<SyncBadge>.value(SyncBadge.off), name: 'syncBadgeProvider');

// 계약 7.2.20 (SYNC, v1.2 기준 원문 그대로 — v1.2 C12-04는 '값 동등' 표에 AuthUser 추가뿐)
/// For the app shell's syncBadgeProvider override (M4).
core.SyncBadge syncBadgeOf(SyncStatus status);
/// core.RemoteAssetFetcher over SyncAssetService (M4 wiring by INFRA).
final class SyncRemoteAssetFetcher implements core.RemoteAssetFetcher {
  SyncRemoteAssetFetcher(SyncAssetService service);
}
```

- 계약 7.2.20 v1.1 표면 갱신(C11-22) 확인: INFRA가 M4에 쓰는 이름(아래 표 — `syncEngineProvider`·`authServiceProvider`·`syncNoticesProvider`·`FirebaseSyncBindings`·`syncBadgeOf`·`SyncRemoteAssetFetcher`, 설정 provider 4개)은 바뀌지 않았다. 삭제된 `syncClockProvider`(→ CORE `clockProvider`)·`syncDisplayStateProvider`는 INFRA가 override하지 않는다.

| 용도 | SYNC 이름 | INFRA 작업 (M4) |
|---|---|---|
| 화면용 상태 | `syncBadgeOf(SyncStatus)` | `syncBadgeProvider.overrideWith((ref) => ref.watch(syncEngineProvider).statusStream.map(syncBadgeOf).distinct())` — 값 = 계약 7.3.3 v1.1 `syncEngine.statusStream.map(syncBadgeOf).distinct()`(C11-13: `SyncBadge` 값 동등이라 배지가 같으면 다시 그리지 않음) |
| 원격 에셋 | `SyncRemoteAssetFetcher(SyncAssetService)` | `remoteAssetFetcherProvider` override |
| 엔진·인증·알림 | `syncEngineProvider`, `authServiceProvider`, `syncNoticesProvider`, `FirebaseSyncBindings` | 시작 시 `syncEngineProvider`를 한 번 읽어 즉시 시작(SYNC I-2), 수명주기 → `setLifecycle`/`flushPendingUploads`, `/login`·리디렉션, 계정·동기화 섹션, 루트 `ScaffoldMessenger` 알림 스낵바 |
| 설정 | `syncConfigProvider`, `authBackendProvider`, `syncBackendFactoryProvider`, `connectivitySignalProvider` | `SyncModule.overrides()`, Firebase 미설정이면 override 없음 |
| Firebase 파일 | `packages/sync_engine/firebase/{firestore.rules, storage.rules, firestore.indexes.json}` | `app/firebase.json`이 참조(6.12), CI `firebase deploy --only firestore:rules,firestore:indexes,storage` |

### 5.6 모든 패키지 공통 기대

- 4.1 규약 준수 (`dart run tool/ws.dart check` 통과), 계약 7.4 공통 규칙.
- 공개 위젯은 `MaterialApp`/`ProviderScope`를 만들지 않는다 (테스트·패키지 내부 하위 scope 제외).
- `lib/` 최상위 진입점(계약 7.1 표)에서 공개 API를 export하고, export 이름이 다른 패키지와 겹치지 않는다(통합 단계 R14).
- 루트 override가 필요한 새 자리를 만들면 결과 보고 '변경 요청'으로 → 총괄이 계약 7.3.3 표에 넣은 뒤 INFRA가 `FeatureWiringModule`에 추가.

### 5.7 테스트용 가짜 구현 (`app/test/fakes/`)

| 가짜 | 대신하는 것 | 동작 |
|---|---|---|
| `FakeWebPlatform` | `WebPlatform` | 필드로 지정한 응답(`buildInfoJson`, `isStandalone`, `baseUri`, `downloadResult`, `canShareFilesResult`, `shareResult`), `visibility` 이벤트 수동 발생(`emitVisibility`), `fetchCount`·`reloadCount`·`downloads`·`shares`(파일 이름·크기·MIME) 기록. `resolveAppUrl`은 `baseUri.resolve(path)` |
| `FakeAppModule` | `AppModule` | 생성자: `id`, `critical`, `startDelay`, `startError`, `gate`(`Completer`로 완료 시점 제어), `overrides`, `hiddenDelay`, `resetLocalData`, `resettable`, `abandonDelay`. `started`·`stopped`·`hiddenCalls`·`abandonedCalls` 기록 |
| `CountingNoteStore` | `NoteStore` (CORE 인터페이스 구현) | `createFakeNoteStore(...)`(계약 7.6 시그니처, 5.1)에 멤버를 위임하고 `flushCount`·`closeCount`·`refreshCount`를 센다. 주입: `flushDelay`·`flushError`·`closeError`·`closeDelay`, **`flushGate`**(`Completer<void>?` — 설정하면 `flush()`와 `exportBackupJson()`이 그 Completer가 끝날 때까지 끝나지 않음: 쓰기 재시도 중 상태 재현, 계약 7.2.9 v1.2), **`emitStatus(PersistenceStatus)`**(그 값을 `persistenceStatus`로 바꾸고 `persistenceStatusStream`에 내보냄 — 구독 즉시 현재 값 1회 규칙 유지, `consecutiveFailures: 3`으로 `writeFailing` 재현), `refreshResult`(설정하면 `refreshStorageInfo()`가 그 값을 돌려주고 그 뒤 `storageInfo`도 그 값 — '다시 확인 후 `storageInfoProvider` 갱신' 테스트용), `exportBackupResult`(`Uint8List` 또는 던질 예외). **`exportBackupJson`은 가짜에 위임하지 않는다** — B2 가짜는 `UnimplementedError`(계약 7.6) |
| `fakeOpenNoteStore` | `openNoteStore` | `({Duration delay, Object? error, NoteStore? store, Completer<NoteStore>? gate})` → `Future<NoteStore> Function(NoteStoreConfig)`. 받은 `config`를 `lastConfig`에, 호출 횟수를 `openCount`에 기록. `gate`로 시간 초과 뒤 늦은 완료를 만든다(INFRA-2-9) |
| `RecordingLocalDataEraser` | `deleteLocalNoteData` | 호출된 `NoteStoreConfig` 목록, 지정한 예외 |
| 가짜 PDF 동작 | `importPdfAsNewNote` 등 | 닫힘(closure)으로 만든 `LibraryPdfImportAction`·`LibraryPdfExportAction`, `PdfMenuAction` 목록(호출된 `PdfMenuInvocation` 기록), `ValueNotifier<PdfRenderStats>`(`PdfRenderStats.zero`에서 시작 — `PdfRenderStatsLines` 단위 테스트에 직접 넘김). 필요하면 `package:pdf_io/testing.dart`(PDF 4.14). **PDF T8 전(B4): `pdfRenderStatsProvider` = 0 통계 notifier(`ValueNotifier(PdfRenderStats.zero)`, 계약 7.6 B4 v1.2 C12-06) — 테스트 컨테이너에 `pdfRenderStatsProvider`를 따로 override하지 않는다**(`pdfRenderStatsSection`은 실제 provider를 읽음) |
| `AppScreenBuilders.placeholders()` | 피처 화면 | 인자를 텍스트로 표시하고 콜백 버튼 제공 (`Key('open-note')` 등). 라이브러리 자리표시는 `initState` 횟수를 센다 |

- `createFakeNoteStore()`는 CORE 기반 단계 B2에 포함된다(계약 7.6). 초안의 `FakeNoteCoreHandle`·`fakeOpenNoteCore`는 삭제했다.
- `testing.dart`·`testing_vm.dart`는 `app/test/`에서만 import한다(R4).

---

## 6. 설계 상세

### 6.1 워크스페이스 · 의존성 · lock 정책

확인한 동작 (scratch 워크스페이스, 7개 멤버):

- 루트에서 `flutter pub get` 한 번 → 루트에 `pubspec.lock` 1개, `.dart_tool/` 1개. 멤버에는 lock이 생기지 않음. 빌드 훅 산출물도 루트 `.dart_tool/hooks_runner/`(sqlite3 미리 빌드 라이브러리 등)에 생긴다 (확인함, 총괄 scratch `lead/ws`).
- 루트에서 `flutter analyze` → 모든 멤버 분석 (20초).
- 루트에서 `flutter test`는 동작하지 않음("Test directory test not found"). 루트에서 경로를 넘기면(`flutter test app/test`) **현재 패키지의 자산이 번들되지 않아** material_ui 셰이더 자산 오류로 실패 → **테스트는 반드시 각 멤버 디렉터리에서** 실행 (`tool/ws.dart test`가 처리).
- 순수 Dart 멤버(`flutter` 의존 없음, `environment.flutter` 있음)도 멤버 디렉터리에서 `flutter test` 동작 (총괄 확인).
- `flutter build web`은 `app/`에서 실행, 결과는 `app/build/web`.
- `flutter pub get --enforce-lockfile` 동작.

melos 판단: 미사용. pub workspace가 해석·lock·분석을 해결하고, 남는 "멤버마다 명령 반복 · 영향 범위 계산 · 준비 스크립트 선실행"은 `tool/ws.dart`로 충분하다. melos 8.10.0은 CI에서 추가 설치(전역 활성화 또는 개발 의존성 다수)가 필요하고 버전 관리·배포 기능은 쓰지 않는다.

lock 충돌 정책 (동시 개발, 계약 7.4.1):

1. 기반 단계 B1에서 **계약 7.5의 모든 외부 의존을 각 pubspec에 미리 넣고**(3.3 표) lock을 만든다.
2. 동시 개발 중 새 패키지가 필요하면 자기 pubspec에 정확 버전으로 추가하고 `flutter pub get`, 결과 보고에 '의존성 추가'로 남긴다(`ws check`는 R9w 경고).
3. 통합 시 `pubspec.lock` 충돌은 손으로 고치지 않는다: 기본 브랜치의 lock을 받고 루트에서 `flutter pub get` → `pinned_external` 갱신 → `ws check --strict` → 커밋. 외부 의존은 정확 고정이라 직접 의존 버전은 그대로 재현된다.

### 6.2 정적 분석과 검사 규칙

루트 `analysis_options.yaml` (규칙 이름 전부 Dart 3.13 분석기에서 유효함을 확인함, 계약 7.4.2):

| 구분 | 설정 |
|---|---|
| include | `package:flutter_lints/flutter.yaml` |
| formatter | `page_width: 80` (Dart 3.13 tall style, 후행 쉼표는 포매터가 관리 → `require_trailing_commas` 사용 안 함) |
| language | `strict-casts`, `strict-inference`, `strict-raw-types` 모두 true |
| errors 승격 | `invalid_use_of_visible_for_testing_member`, `invalid_use_of_protected_member`, `missing_required_argument`, `unused_import` → error; `todo` → ignore |
| exclude | `**/build/**`, `**/*.g.dart`, `**/*.freezed.dart`, `app/android/**`, `app/ios/**`, `app/web/**`, `tool/test/fixtures/**`(규칙 검사기 시험용 가짜 작업 공간 — 일부러 위반·미해석 import·포맷 안 된 코드를 담는다. B1부터 `test_tags_test` 픽스처가 생기므로 B1-1에서 함께 넣는다). 비고(INFRA-2-13, CORE 02-core 11절·6.16 요청): drift v2부터 생기는 생성 파일(`schema_versions.dart`, `make-migrations`가 만드는 생성 테스트)이 루트 lint에 걸리면 그 경로를 여기에 추가한다(INFRA 단독 커밋, R11 `generated_files`에도 같은 패턴). v1에서는 `*.g.dart`만 생겨 추가할 것이 없다 |
| 추가 lint (18개) | `always_declare_return_types`, `avoid_dynamic_calls`, `avoid_slow_async_io`, `avoid_type_to_string`, `cancel_subscriptions`, `close_sinks`, `directives_ordering`, `no_adjacent_strings_in_list`, `only_throw_errors`, `prefer_final_locals`, `prefer_single_quotes`, `prefer_void_to_null`, `test_types_in_equals`, `unawaited_futures`, `unnecessary_lambdas`, `unnecessary_parenthesis`, `use_named_constants`, `use_super_parameters` |
| CI 실행 | `flutter analyze --fatal-infos` (info도 실패) — `@Deprecated` API 사용(`deprecated_member_use`)도 실패하므로 꼭 필요하면 그 줄에 `// ignore: deprecated_member_use` + 사유 주석, INFRA 승인(계약 7.4.2) |

`tool/ws.dart check` 규칙 (계약 7.4.2 v1.2의 보완 포함 — R1~R13·R15, 통합 단계 R14. B1 판 범위는 R1–R3·R7–R9·R15, 계약 7.6 B1 v1.2):

| ID | 규칙 | 대상 |
|---|---|---|
| R1 | 루트 `workspace` 목록 = 실제 멤버 디렉터리, 각 멤버 `resolution: workspace` | pubspec |
| R2 | 모든 멤버 `environment`가 루트와 동일(`sdk: ^3.13.0`, `flutter: 3.47.9`) — **순수 Dart 멤버도**. `pure_dart_members`(= `note_core`)는 추가로 `dependencies`·`dev_dependencies`에 `sdk: flutter` 항목이 없고, `lib/`·`test/`에서 `package:flutter/`·`package:flutter_test/` import가 없어야 함 | pubspec, Dart |
| R3 | 멤버 디렉터리에 `analysis_options.yaml` 없음 | 파일 |
| R4 | `lib/`에서 ① `forbidden_imports.lib` 금지(파일명이 `native_suffixes`로 끝나면 `dart:io`·`dart:ffi` 허용) ② **`native_only_imports`**(`package:ffi/`, `package:pdfium_dart/`, `package:drift/native.dart`)는 파일명이 `native_suffixes`(`_io.dart`·`_native.dart`)로 끝나는 파일에서만 ③ 워크스페이스 패키지의 `test_only_entrypoints`(`testing.dart`·`testing_vm.dart`) import·export 금지 — **`package:` URI 기준**(`package:<멤버>/testing*.dart`). 같은 패키지의 `lib/testing*.dart`끼리는 상대 import 허용(예: `testing_vm.dart` → `'testing.dart'`), 그 밖의 `lib/` 파일이 상대 경로로 `lib/testing*.dart`에 닿으면 위반. **예외 `lib_exceptions`**(파일, 또는 `/`로 끝나면 디렉터리 전체 — ①②③ 모두 면제): `packages/note_core/lib/testing_vm.dart`(+ ink lab이 멤버가 되면 `packages/ink_engine/example/lib/`, 1.3) | Dart |
| R5 | `web_only_imports`는 파일명이 `web_suffixes`(`_browser.dart`)로 끝나는 파일에서만 — `lib/`와, `test/` 중 `test/web/` 밖의 파일이 대상(`test/web/`의 브라우저 테스트는 직접 import 허용) | Dart |
| R6 | **`lib/` 안의 import·export에만 적용**: `_io/_native/_browser` 파일(플랫폼 파일)은 조건부 절(`if (dart.library.…)`)로만 불러오고, 같은 지시문에 기본(스텁) 파일이 있어야 함. **계약 7.4.2 v1.5 해석(C15-02)**: ① 플랫폼 파일 안에서는 **같은 플랫폼**의 플랫폼 파일(`*_native.dart`·`*_io.dart`끼리, `*_browser.dart`끼리)을 조건 없이 불러와도 된다 — 그 파일 자체가 조건부 절로만 불러와지므로 안전하다 ② 패키지 진입점 `lib/<패키지>.dart`는 이름이 `_io.dart`로 끝나도(`pdf_io.dart`) 플랫폼 파일이 아니다(R4·R5·R6 접미사 판정 공통). 다른 플랫폼 파일(네이티브 → 브라우저 등)은 여전히 조건부 절로만. `test/`는 플랫폼 구현 파일을 직접 import해도 됨 | Dart |
| R7 | `lib/`·`test/`에서 `forbidden_imports.lib_and_test`(SDK `material.dart`·`cupertino.dart`) 금지 + 다른 워크스페이스 패키지의 `package:<pkg>/src/` import 금지 (`tool/` 제외) | Dart |
| R8 | 형제 의존은 `allowed_dependencies` 안에서만, 버전은 `any`(`path:` 금지) | pubspec |
| R9 | 외부 의존은 정확 버전(`^`, `>=`, `any` 금지, `sdk:` 의존은 제외), `pinned_external`(= 계약 7.5 표 전부)에 있으면 그 버전과 일치. 표에 없는 외부 의존은 경고 `R9w`(종료 코드 0) — `--strict`(main CI·통합 G1)에서는 위반 | pubspec |
| R10 | `dependency_overrides`는 루트에만 | pubspec |
| R11 | `dart format --output=none --set-exit-if-changed <파일 목록>` — `app`·`packages`·`tool`의 `*.dart` 중 `generated_files`(`*.g.dart`, `*.freezed.dart`, `schema_versions.dart`)와 `tool/test/fixtures/` 아래 제외(drift 생성 코드는 `build_runner`가 자기 포매터로 쓴다, 픽스처는 일부러 포맷 안 된 파일을 담는다). **이 파일 집합이 'dart format 변경 없음'(G4·10절 7·계약 V2)의 대상이다**(R11 기준 — 생성 파일 제외) | 포맷 |
| R12 | `web_assets.yaml` 파일이 `app/web/`에 있고 크기·sha256 일치 | 파일 |
| R13 | `app/web/icons/*`, `favicon.png` PNG 크기가 파일명과 일치 (IHDR 읽기) | 파일 |
| R14 | **통합 단계 G3부터**: 6개 패키지(`app` 제외) 공개 진입점(`lib/` 최상위 `*.dart` 전부)의 export 이름 교집합 = ∅ (같은 패키지 안의 진입점끼리는 비교하지 않음, 예외 목록 없음). 구현: 루트 dev `analyzer: 13.3.0`, `AnalysisContextCollection(includedPaths: 진입점)` → `getResolvedLibrary` → `ResolvedLibraryResult.element.exportNamespace.definedNames2`의 키를 패키지별로 모아 비교. 출력 `R14 <이름>: <pkgA>/<entry> & <pkgB>/<entry>`. **통합 단계 구현**(G3): 대상 = `app_members`(noteapp·ink_lab)를 뺀 멤버. analyzer 부분(`tool/src/export_namespace.dart`)은 별도 프로세스 `dart run tool/export_names.dart --out <json> <진입점…>`(10분 제한)에서만 돈다 — `ws`에 import하면 모든 `ws` 명령의 컴파일이 약 12초 늘어서. `ws`는 `tool/src/export_names.dart`(진입점·겹침 판정)만 쓴다. 출력은 다른 규칙과 같은 `경로:1: [R14] <이름>: <pkgA>/<entry> & <pkgB>/<entry>`, 진입점 자신에 오류가 있으면(해석 안 되는 `export` 등) 해석 실패 → 종료 3 | Dart |
| R15 | **태그 선언**(계약 7.4.2·7.4.8 v1.2 C12-01 — **기반 단계 B1부터 위반 = 종료 코드 1**, 규칙 자체는 7.4.8 v1.1 C11-26): 멤버의 `test/**/*.dart`에서 쓰인 태그(`@Tags([...])`·`@Tags(<String>[...])`, `test(`/`testWidgets(`/`group(`의 `tags: '...'`·`tags: [...]` 문자열 리터럴)를 모아, ① 모두 그 멤버 `dart_test.yaml`의 `tags:` 아래에 선언돼 있어야 하고 ② `skip_by_default_tags`(`integration`, `perf`)는 그 선언에 `skip:`(문자열 사유 또는 `true`)이 있어야 한다. 태그를 하나도 안 쓰면 `dart_test.yaml`이 없어도 된다. 출력 `R15 <멤버>: tag 'integration' used in test/x_test.dart but dart_test.yaml does not skip it` | Dart, YAML |

import 스캐너: 줄 시작이 `import`/`export`인 지시문을 `;`까지 이어 붙여 파싱(주석 줄·블록 주석 제외), 조건부 절(`if (dart.library.X) 'uri'`)을 분리 저장. 상대 URI는 파일 경로로 풀어 같은 멤버의 `lib/` 파일인지 판정한다(R4 ③). 생성 파일(`*.g.dart`)도 import 검사(R4–R7)는 한다.

R15 태그 스캐너(`tool/src/test_tags.dart`): 주석을 뺀 테스트 파일 본문에서 `@Tags(` 뒤 대괄호 안, `tags:` 뒤 문자열 리터럴 또는 대괄호 안의 `'…'`/`"…"` 리터럴만 모은다. 이 제약은 계약 7.4.8 v1.2(C12-01)가 규칙으로 정했다: "R15 스캐너는 **문자열 리터럴 태그만** 인식하므로 태그는 `@Tags(['integration'])`·`tags: ['golden']`처럼 리터럴로 쓴다(변수·상수로 넘기지 않는다). `dart_test.yaml`은 그 패키지에서 태그를 쓰는 첫 테스트보다 먼저(보통 골격 작업에서) 만든다". `dart_test.yaml`은 `package:yaml`로 읽고 `tags.<name>`이 맵이면 `skip` 키, 문자열·null이면 '선언만'으로 본다. **R15는 B1-4에서 만든다**(계약 7.6 B1 v1.2: `ws.dart`(list·test·check R1–R3·R7–R9·R15)·`workspace_rules.yaml`(`skip_by_default_tags` 포함)·`tool/test/`(`test_tags_test.dart` 포함)) — 기반 단계부터 main의 `ws check`에 들어가므로, 동시 개발 중 각 영역 브랜치의 `ws check`가 선언 누락·`skip` 누락을 위반(종료 1)으로 잡는다(EDITOR·LIBRARY가 2차에서 놓쳤던 C11-26의 재발 방지). B1 시점에는 태그를 쓰는 테스트가 없어(골격의 `test/<name>_smoke_test.dart`는 태그 없음) B1의 `ws check`는 0이다. I1은 R15를 다시 만들지 않고 나머지 규칙(R4–R6·R10–R13)만 더한다.

R14 확인 실험 (확인함, `/tmp/claude-0/plan-scratch/infra2/r14`): `analyzer 13.3.0`(SDK `^3.11.0`, BSD-3-Clause)으로 ① 순수 Dart 픽스처 2개(`show`로 일부만 export, private·숨긴 이름 제외)에서 겹친 이름 1개만 보고 ② material_ui·flutter_riverpod을 쓰는 Flutter 패키지 진입점도 오류 없이 해석되어 `[probeProvider, ProbeScreen]`을 얻음(`dart:ui`는 sky_engine으로 해석). 2개 패키지 해석 15초 → 7개 멤버는 1분 안팎 예상(미확인) — `ws check --no-exports`로 로컬에서 건너뛸 수 있다. `analyzer`는 `test 1.31.1`이 이미 13.3.0으로 해석하므로 직접 의존을 더해도 lock의 버전은 바뀌지 않는다(계약 7.5).

### 6.3 Material 라이브러리 결정 (D2)

확인한 사실:

- Flutter 3.47.9 SDK에 `package:flutter/material.dart`가 아직 있고 deprecated 표시는 없다. 동시에 `material_ui`(1.10.0, 2026-11-03)가 SDK Material의 **복사본**으로 배포되며 README가 `dart fix --apply --code=migrate_design_widgets`로 이전을 안내한다.
- `material_ui`는 `export 'package:flutter/widgets.dart'` + 자체 `src/` 클래스. 즉 `MaterialApp`, `Theme`, `ThemeData`, `Material`, `MaterialLocalizations`가 SDK 쪽과 **다른 클래스**다.
- go_router 18.0.0부터 `findAncestorWidgetOfExactType<MaterialApp>()`를 material_ui 쪽으로 검사 → SDK `MaterialApp`을 쓰면 전환 애니메이션 없는 `NoTransitionPage`로 떨어진다.
- pdfrx 2.11.0도 material_ui 의존. 계약 7.5 표의 외부 패키지 중 SDK Material을 import하는 것은 없다(총괄 확인, 계약 7.4.2).
- `material_ui-1.10.0/lib/src/migration_utility.dart`의 `MaterialUiCompatibilityBridge`는 클래스·생성자 모두 `@Deprecated`다(총괄 확인) → 쓰면 `deprecated_member_use` info로 `flutter analyze --fatal-infos`가 실패한다.

결정 (계약 7.4.2·7.4.3):

1. 모든 패키지 `material_ui`만 사용, R7로 SDK Material·Cupertino import 금지(lib·test 모두, 위젯 테스트의 `MaterialApp`도 material_ui 것).
2. **`MaterialUiCompatibilityBridge`는 위젯 트리에 넣지 않는다.** `note_app_test`는 브리지가 **없음**을 확인한다(9.1 — 그 테스트 한 줄만 `// ignore: deprecated_member_use // absence check, INFRA-M3`).
3. 나중에 SDK Material을 쓰는 외부 패키지(예: 수식 렌더링)가 꼭 필요해지면 계약 7.4.2 절차(그 줄에 ignore + 사유, INFRA 승인, 총괄 공지)로만 브리지를 넣는다.

실험: material_ui `MaterialApp.router` + go_router 18.1.2 + `GlobalMaterialLocalizations.delegates`로 화면 이동 위젯 테스트 통과, `flutter build web` 통과 (확인함).

### 6.4 앱 시작 순서

```mermaid
sequenceDiagram
  participant H as index.html
  participant M as main()
  participant B as BootstrapApp
  participant S as AppBootstrapper
  participant C as CoreModule (openNoteStore)
  participant P as ProviderScope/NoteApp
  H->>H: HTML loader, viewport / gesture / contextmenu guards
  H->>M: flutter_bootstrap.js loads engine (CanvasKit)
  M->>M: ensureInitialized, usePathUrlStrategy, AppErrorLog, installGlobalErrorHandlers
  M->>B: runApp(BootstrapApp)
  B->>H: first frame (SplashView) → 'flutter-first-frame' removes HTML loader
  B->>S: run()
  S->>C: core (20 s, critical): openNoteStore(config) — CORE awaits persist() ≤ 1 s itself
  C-->>S: NoteStore published, StorageInfo
  S->>S: pdf (10 s, non-critical): initializePdfIo()
  S->>S: featureWiring (1 s, non-critical): static overrides (PDF part only if pdf ok)
  S-->>B: BootstrapSuccess(overrides, report) / BootstrapFailure
  B->>P: ProviderScope(overrides, observers: [AppProviderObserver]) → AppLifecycleBridge → NoteApp
  P->>P: router → LibraryScreen; UpdateChecker starts after 5 s
```

단계별 규칙:

1. `main()` (`runNoteApp`)
   1. `WidgetsFlutterBinding.ensureInitialized()`
   2. `usePathUrlStrategy()` (`flutter_web_plugins/url_strategy.dart`, 비웹에서는 아무 일 안 함)
   3. `final errorLog = AppErrorLog(capacity: 100)`; `installGlobalErrorHandlers(errorLog)`
   4. `buildInfo = BuildInfo.fromEnvironment()`, `web = createWebPlatform()`, `runtime = RuntimeInfo.detect(web)`
   5. `runApp(BootstrapApp(createBootstrapper: () => AppBootstrapper(modules: productionModules(), …, ownerId: kLocalOwnerId), errorLog: errorLog))`
2. `AppBootstrapper.run()`
   1. 스톱워치 시작. `AppModuleContext(buildInfo, runtimeInfo, web, ownerId, errorLog)` 생성. **INFRA는 `persist()`를 요청하지 않는다**(CORE가 열기 안에서 요청, 계약 7.2.12).
   2. 모듈을 목록 순서대로 하나씩: `stageLabel = module.label` → `module.start(ctx).timeout(module.startTimeout)` → `ctx.recordOutcome(module.id, outcome)`
      - 단계가 3초(`slowStageThreshold`)를 넘으면 `isSlow = true` → 스플래시에 "시간이 걸리고 있어요… (n초)"
      - 실패: `critical`이면 이미 시작한 모듈을 역순 `stop()`(각 2초 제한) 후 `BootstrapFailure`(그 모듈의 `canResetAfter(error)`가 참이면 `resetLocalData` 포함). 아니면 `failedNonCritical`/`timedOut` 기록, `errorLog`에 남기고 그 모듈의 overrides 제외 → 뒤 모듈은 `ctx.isStarted(id)`로 알 수 있다(`FeatureWiringModule`이 PDF override를 생략).
      - **시간 초과 뒤 늦은 완료**(INFRA-2-9): `.timeout`은 `start`를 취소하지 않는다. 시간이 넘으면 부트스트래퍼가 바로 그 모듈의 `onStartAbandoned()`를 부르고 그 Future를 보관한다. `CoreModule`은 20초 뒤에 늦게 열린 `NoteStore`를 **즉시 `close()`**(실패하면 `errorLog`, source: module)하고 publish·override하지 않는다(늦은 열기 실패는 무시 — 시간 초과로 이미 보고됨). "다시 시도"는 `shutdown()`이 그 close가 끝나기를 **최대 2초** 기다린 뒤에만 새 부트스트래퍼를 만든다 — 웹에서 늦게 열린 저장소가 DB(IndexedDB/OPFS)를 쥔 채 다음 `openNoteStore`와 겹치거나, `deleteLocalNoteData`가 `StateError`(CORE 6.18)를 내지 않게. 2초 안에 안 끝나면 기록하고 진행(그래도 막히면 오류 화면이 다시 뜬다).
   3. overrides 조립: 셸 overrides(`buildInfoProvider`, `webPlatformProvider`, `runtimeInfoProvider`, `appErrorLogProvider`, `startupReportProvider`, `appBootstrapperProvider`) → 모듈 순서대로(`core` → `pdf` → `featureWiring`). 결과 목록 = 계약 7.3.3 표의 '이번' 행 전부.
   4. `StartupReport(bootstrapElapsed, sinceNavigationStart: web.millisecondsSinceNavigationStart, storage: ctx.maybe<NoteStore>()?.storageInfo)`
3. 성공 → `ProviderScope(key: ValueKey(attempt), overrides: …, observers: [AppProviderObserver(errorLog)], child: AppLifecycleBridge(child: NoteApp()))`
   - (G2에서 추가) 스플래시·오류 화면의 틀(`_ShellFrame`)은 엔진에 라우트를 보고하지 않는다: `MaterialApp(home:)`의 루트 Navigator가 `/`를 보고하면 웹 엔진이 처음 연 주소를 잊어(`defaultRouteName`이 첫 navigation 메시지에서 `/`가 됨 — 엔진 `platform_dispatcher.dart`) 시작 뒤 만들어지는 GoRouter가 `/notes/<id>` 새로고침을 라이브러리로 연다(릴리스 빌드에서 Playwright로 확인). 그래서 `MaterialApp(builder:)` 안에 자기 `Navigator(pages: [MaterialPage(child)])`(`reportsRouteUpdateToEngine` 기본 false — 오류 화면 대화상자용)를 둔다. `bootstrap_app_test` '라우트를 보고하지 않음' 경우가 스플래시·오류 화면 동안 `SystemChannels.navigation` 호출 0건을 확인한다.
4. 실패 → `StartupErrorScreen` (6.7). "다시 시도"는 `shutdown()` 후 `createBootstrapper()`로 새 인스턴스, `attempt + 1`. "이 기기 데이터 지우고 다시 시작"은 2단계 확인 → `shutdown()`(열린 저장소가 없게 — CORE 6.18) → `failure.resetLocalData()` → 성공하면 자동 다시 시도.
5. 목표 수치 (PLAN 5.4 '앱 시작 2초'): 캐시된 재방문 기준 `sinceNavigationStart ≤ 2,000 ms`, 빈 DB 기준 `bootstrapElapsed ≤ 500 ms`. 앱 정보에 표시해 iPad에서 측정. `CoreModule.startTimeout` 20초는 CORE의 Chrome 첫 `openNoteStore` 측정(CORE-S5)과 B8·G2 실측(INFRA-S2)으로 다시 정한다.

`CoreModule` 세부 (INFRA-M1, S7):

- 설정: `defaultNoteStoreConfig(ctx)` = `NoteStoreConfig(ownerId: ctx.ownerId, web: WebStorageConfig(sqlite3WasmPath: ctx.web.resolveAppUrl('sqlite3.wasm'), driftWorkerPath: ctx.web.resolveAppUrl('drift_worker.js')))`, 나머지는 CORE 기본값.
- **소유자**: `ctx.ownerId`(이번 범위 `kLocalOwnerId`)는 CORE가 **새 DB를 만들 때만** 쓴다. 저장된 소유자(M4 첫 로그인 후 `SyncStore.reassignOwner`)가 우선하며, 실제 소유자는 언제나 `store.ownerId`다. 앱 셸은 `ctx.ownerId`를 다른 곳에 쓰지 않는다.
- **절대 URL** (계약 7.2.12·7.4.3 v1.1, C11-11 — 초안의 12.3 P3가 수정 채택됨): 경로 URL 전략에서 `/notes/<id>`로 새로고침하면 dart2js `Uri.base`(= `self.location.href`, Dart SDK `js_helper.dart` `currentUri()` 확인함)가 그 깊은 경로가 되어, 상대 경로 `sqlite3.wasm`이 `/notes/sqlite3.wasm`으로 해석되고 Hosting 재작성 규칙이 `index.html`을 돌려준다(wasm 컴파일 실패 → 시작 실패). 그래서 운영에서는 **항상** `document.baseURI`(= `<base href>` 반영) 기준 절대 URL을 넘긴다. CORE는 해석 기준을 바꾸지 않고 `Uri.base.resolve(path)`를 그대로 쓰며, 절대 URL은 그 호출에서 그대로 돌아오므로 INFRA는 절대 URL만 넘기면 된다(CORE 브라우저 테스트의 상대 경로도 그대로 동작). `fetch('build_info.json')`(새 버전 감지)과 pdfrx 자산은 Dart `Uri.base`를 거치지 않고 브라우저가 `document.baseURI` 기준으로 해석하므로 계약 규칙에 맞는다.
- 상태 전달: `store.persistenceStatusStream`(구독 즉시 현재 값 1회 — 계약 7.2.12 v1.1, C11-09)에서 `lastErrorAt`이 직전 이벤트와 달라질 때마다 `AppErrorRecord.fromError(lastError, null, source: module)`(요약에 `consecutiveFailures`)를 `errorLog`에 넣는다(계약 7.4.5). 첫 이벤트에 이미 `lastError`가 있으면 그것도 1건. 저장 경고 배너 자체는 LIBRARY·EDITOR 몫.
- 수명주기: `onAppHidden()` = `store.flush()`(호출자가 500ms 제한), `stop()` = 구독 취소 후 `store.close()`. 시간 초과 뒤 늦게 열린 저장소는 `onStartAbandoned()`가 닫는다(위 2-2).

M4 연결 (이후, 1.3): `productionModules()` 끝에 `SyncModule`(비필수) 추가 — `start`는 `FIREBASE_ENABLED`일 때만 Firebase 초기화(`firebase_options.dart`), `overrides()` = 계약 7.3.3 M4 두 행: `syncBadgeProvider.overrideWith((ref) => ref.watch(syncEngineProvider).statusStream.map(syncBadgeOf).distinct())`(계약 7.3.3 v1.1 값 `syncEngine.statusStream.map(syncBadgeOf).distinct()`, C11-13 — `SyncBadge` 값 동등), `remoteAssetFetcherProvider` ← `SyncRemoteAssetFetcher`, SYNC 설정 4종(Firebase 미설정이면 SYNC 설정 override 없음 → `SyncPhase.disabled`). 루트 위젯(`AppLifecycleBridge`)이 `syncEngineProvider`를 한 번 읽어 엔진을 즉시 시작하고(SYNC I-2, 지연 생성 금지) 숨김·표시를 `setLifecycle`·`flushPendingUploads`로 넘긴다. 라우터에 `/login` + `authServiceProvider` 기반 리디렉션, 설정에 `app.account` 섹션, 루트 `ScaffoldMessenger`에 `syncNoticesProvider` 스낵바. 이때 `app/pubspec.yaml`·`allowed_dependencies`에 `sync_engine`을 더한다.

### 6.5 의존성 주입 (D4)

- 패키지가 자리(provider)를 정의한다: 앱이 반드시 넣어야 하면 기본 `UnimplementedError`, 선택이면 `Provider<T?>((ref) => null)`(계약 7.4.4).
- 앱 셸 모듈이 **계약 7.3.3 표의 provider만** override하고, 부트스트랩이 그 목록을 모아 루트 `ProviderScope.overrides`에 한 번 넣는다. 표에 없는 provider를 앱 코드에서 override하지 않는다(테스트 제외). 새 연결이 필요하면 총괄이 표를 고친 뒤 `FeatureWiringModule`에 추가.
- 같은 provider를 두 번 override하면 Riverpod 3.4.3이 디버그에서 `AssertionError: Tried to override a provider twice within the same container`를 던진다 (확인함, `/tmp/claude-0/plan-scratch/infra2/router`). 릴리스에서는 assert가 꺼지므로 **테스트가 잡는다**: `bootstrap/overrides_unique_test.dart`와 통합 스모크(V5)가 `Override.origin`(Riverpod이 `@visibleForTesting`으로 공개 — 앱 `lib/`에서는 쓰지 않음)으로 중복이 없음을 단언한다.
- 런타임 중 재구성 없음. 재시도는 `ProviderScope`를 새 key로 다시 만든다.
- 패키지 내부 하위 `ProviderScope`(예: EDITOR 노트별 scope)는 자기 패키지 provider만 override한다(계약 7.4.4). 앱 셸은 하위 scope를 만들지 않는다.
- 테스트는 `ProviderContainer.test(overrides: …)` (Riverpod 3.4.3, 자동 dispose — 확인함) 또는 위젯 테스트의 `ProviderScope(overrides:)`.

### 6.6 라우팅 (D3, D5)

| 경로 | 이름 | 화면 | 페이지 | 인자 |
|---|---|---|---|---|
| `/` | `library` | `screens.library` | `NoTransitionPage(key: AppRoutes.libraryPageKey)` | `LibraryRouteArgs()` |
| `/folders/:folderId` | `folder` | `screens.library` | `NoTransitionPage(key: AppRoutes.libraryPageKey)` — **`/`와 같은 키** | `LibraryRouteArgs(folderId)` |
| `/notes/:noteId` | `note` | `screens.editor` | `NoTransitionPage(key: state.pageKey)` | `EditorRouteArgs(noteId, initialPageId: ?page=)` |
| `/settings` | `settings` | `screens.settings` | 기본(material_ui `MaterialPage`) | — |
| (그 외) | — | `NotFoundScreen` ("페이지를 찾을 수 없어요" + 홈 버튼) | `NoTransitionPage` | `state.uri` |
| `/login` | — | 예약 (M4) | — | — |

페이지 종류의 이유 (INFRA-M7):

- **에디터 무전환**: 네이티브 iOS에서 `MaterialPage`(Cupertino 전환)는 왼쪽 가장자리 스와이프 뒤로가기 제스처를 붙여 펜 획을 가로챈다. `NoTransitionPage`는 전환·제스처가 없다. 웹 Safari 탭 자체의 가장자리 스와이프는 앱이 막을 수 없어 홈 화면 앱(standalone) 사용을 안내한다(안내서 04, EDITOR-S5).
- **라이브러리 공용 키**: `/`와 `/folders/:id`가 같은 `ValueKey('library')`의 같은 페이지 타입이면 `Page.canUpdate`가 참이라 Navigator가 라우트를 새로 만들지 않고 갱신한다 → `LibraryScreen`의 `State`가 유지되고(스크롤·선택·사이드바 펼침 유지), 폴더 이동마다 화면이 다시 만들어지거나 미끄러지지 않는다. 확인함(`/tmp/claude-0/plan-scratch/infra2/router`, go_router 18.1.2 + material_ui 1.10.0): `/` → `/folders/a` → `/folders/b` → `/` → `/folders/a` → push `/notes/n1` → pop 동안 라이브러리 `initState` 1회, 매번 새 `folderId`로 build.

`GoRouterAppNavigator` 의미:

| 메서드 | 동작 | 이유 |
|---|---|---|
| `openLibrary(folderId)` | `router.go('/')` 또는 `go(AppRoutes.folder(id))` | 폴더 이동은 스택을 쌓지 않음(같은 페이지 키라 화면 유지) |
| `openNote(id, pageId)` | `router.push(AppRoutes.note(id, pageId: …))` | 닫으면 같은 폴더로 복귀 |
| `closeNote()` / `closeSettings()` | `router.canPop() ? router.pop() : router.go('/')` | 새로고침으로 에디터·설정에서 시작한 경우 대비 |
| `openSettings()` | `router.push('/settings')` | |

- 웹 URL은 경로 방식 (`usePathUrlStrategy`). Hosting이 모든 경로를 `index.html`로 재작성 (6.12). 깊은 경로에서 시작해도 정적 파일은 `<base href>` 기준으로 받는다(6.4).
- 라우터 옵션: `initialLocation: '/'`, `errorPageBuilder`, `debugLogDiagnostics: kDebugMode`. 리디렉션 없음 (M4에서 로그인 리디렉션 추가).
- (G2에서 추가) `createAppRouter`가 `GoRouter.optionURLReflectsImperativeAPIs = true`를 켠다. go_router 기본값(false)에서는 `push`가 브라우저 주소를 바꾸지 않아, 릴리스 빌드에서 노트를 열어도 주소가 `/`로 남았다(Playwright로 확인) — 9.3 #16(노트에서 새로고침 → 같은 노트)이 성립하지 않는다. `app_router_test` '보고된 브라우저 주소' 경우가 push·pop마다 `routeInformationUpdated`의 `uri`를 확인한다.
- ID는 `Uri.encodeComponent`로 인코딩.
- `AppScreenBuilders.production()` 연결:
  - library: `LibraryScreen(folderId: args.folderId, onOpenFolder: (id) => nav.openLibrary(folderId: id), onOpenNote: nav.openNote, onOpenSettings: nav.openSettings)`
  - editor: `EditorScreen(key: ValueKey(args.noteId), noteId: args.noteId, initialPageId: args.initialPageId, onClose: nav.closeNote, onOpenSettings: nav.openSettings)`
  - settings: `SettingsScreen(onClose: nav.closeSettings)`

### 6.7 오류 처리

| 상황 | 처리 |
|---|---|
| 위젯 빌드 오류 | `FlutterError.onError` → `AppErrorLog` (+ 디버그 콘솔). 릴리스에서는 `appErrorWidgetBuilder`의 회색 상자 |
| 비동기 미처리 오류 | `PlatformDispatcher.instance.onError` → 기록, `true` 반환(앱 유지) |
| provider 실패 | `AppProviderObserver.providerDidFail` → 기록 (source provider) |
| CORE 쓰기 실패 | `CoreModule`이 `PersistenceStatus.lastError`를 기록(source module). 배너는 LIBRARY·EDITOR(`storageWarningOf`) |
| 시작 실패 | `StartupErrorScreen`: 제목 "앱을 시작하지 못했어요", `userMessage`, 접힌 상세(예외 문자열·모듈 ID), 버튼 [다시 시도] [진단 정보 복사] [(`offersReload`) 새로고침] [(`resetLocalData` 있음) 이 기기 데이터 지우고 다시 시작 → 확인 대화상자 2단계] |
| 없는 경로 | `NotFoundScreen` |

`BootstrapFailure.userMessage` 선택 규칙 (해요체, 계약 7.4.5) — `NoteStoreOpenFailure` 기준 (INFRA-M1):

| 오류 | 문구 | 추가 버튼 |
|---|---|---|
| `NoteStoreOpenException(storageUnavailable)` | "이 브라우저에서는 저장소를 쓸 수 없어요. 개인정보 보호(비공개) 탭이라면 일반 탭이나 홈 화면 앱으로 열어 주세요." | — |
| `NoteStoreOpenException(migrationFailed)` | "저장된 데이터를 새 형식으로 바꾸지 못했어요. 진단 정보를 복사해 보내 주세요." | 데이터 지우기 |
| `NoteStoreOpenException(corrupted)` | "저장된 데이터가 손상되어 열 수 없어요. 진단 정보를 복사해 보내 주세요." | 데이터 지우기 |
| `NoteStoreOpenException(newerSchema)` | "더 새로운 버전에서 저장한 데이터예요. 앱을 새로고침해 최신 버전을 받아 주세요." | 새로고침(웹) — 데이터 지우기는 **없음**(새 버전이 읽을 수 있는 데이터) |
| `NoteStoreOpenException(unknown)` | "저장소를 여는 중 문제가 생겼어요. 다시 시도해 주세요." | 데이터 지우기 |
| `TimeoutException` | "시작이 너무 오래 걸려요({모듈 label}). 다시 시도해 주세요." | — |
| 그 외 | "앱을 시작하지 못했어요. 다시 시도해 주세요." | — |

데이터 지우기 확인 2단계: ① "이 기기에 저장된 노트·폴더·펜 설정이 모두 지워져요. 되돌릴 수 없어요." [취소] [계속] ② "정말 지울까요?" [취소] [지우기]. `deleteLocalNoteData(config)` 성공 → 자동 다시 시도, 실패 → "데이터를 지우지 못했어요." 표시 + `errorLog`.

'진단 정보' 텍스트 형식 (`DiagnosticReport.format`, 최대 8,000자):

```text
[필기노트 진단 정보] 2026-11-04 18:20:31 (+09:00)
빌드: 0.1.0 (#42 · a1b2c3d · main) live, 2026-11-04T09:10:00Z
실행: 웹 · CanvasKit (dart2js) · 홈 화면 앱: 예
브라우저: Mozilla/5.0 (iPad; …) Safari/…
시작: 페이지 열기→준비 1,234ms / 부트스트랩 412ms (core 380ms ok, pdf 3ms ok, featureWiring 1ms ok)
저장소: webSharedIndexedDb · 영구 보관 허용 · 다중 탭 안전 · 12.3MB / 1.2GB · 부족한 기능 없음
저장 상태: 대기 0건 · 마지막 저장 18:19:58 (23ms) · 연속 실패 0
오류 3건 (최근 순, 최대 5건)
--- #3 18:19:02 flutter ---
<summary>
<stack 15줄>
```

### 6.8 상태 관리 (Riverpod provider 목록)

셸 provider (INFRA 정의, 이름은 워크스페이스 전체에서 유일 — 계약 7.4.4):

| provider | 타입 | 기본값 / 덮어쓰기 | 사용처 |
|---|---|---|---|
| `buildInfoProvider` | `Provider<BuildInfo>` | `fromEnvironment()` / `BootstrapApp`이 같은 인스턴스로 | 앱 정보, 업데이트 감지, 진단 |
| `webPlatformProvider` | `Provider<WebPlatform>` | `createWebPlatform()` / `BootstrapApp` | 업데이트 감지, 수명주기, 백업 공유·다운로드 |
| `runtimeInfoProvider` | `Provider<RuntimeInfo>` | `detect()` / `BootstrapApp` | 앱 정보, 진단 |
| `appErrorLogProvider` | `Provider<AppErrorLog>` | 덮어쓰기 필수 | 앱 정보, 진단, 백업 |
| `startupReportProvider` | `Provider<StartupReport>` | 덮어쓰기 필수 | 앱 정보, 진단 |
| `appBootstrapperProvider` | `Provider<AppBootstrapper>` | 덮어쓰기 필수 | 수명주기 브리지, 업데이트 적용 전 flush |
| `appScreenBuildersProvider` | `Provider<AppScreenBuilders>` | `production()` / 테스트에서 `placeholders()` | 라우터 |
| `appRouterProvider` | `Provider<GoRouter>` | `createAppRouter` (dispose 연결) | `NoteApp` |
| `appNavigatorProvider` | `Provider<AppNavigator>` | `GoRouterAppNavigator` | 화면 빌더 |
| `updateCheckConfigProvider` | `Provider<UpdateCheckConfig>` | 기본값 / 테스트에서 짧은 간격 | 업데이트 감지 |
| `updateCheckerProvider` | `NotifierProvider<UpdateChecker, UpdateStatus>` | — | `UpdateBanner`, 앱 정보 |
| `settingsSectionsProvider` | `Provider<List<SettingsSectionEntry>>` | `defaultSettingsSections()` (4.5.8 표) | 설정 화면 |
| `latestStorageInfoProvider` | `FutureProvider.autoDispose<StorageInfo>` | `noteStore.refreshStorageInfo()` → 끝나면 `ref.invalidate(storageInfoProvider)`(계약 7.2.12 v1.1), `retry: noRetry` | 저장 공간 섹션, 진단 복사 (앱 셸의 유일한 `refreshStorageInfo()` 호출처) |

앱 셸이 루트에서 덮어쓰는 다른 영역 provider (계약 7.3.3 그대로):

| provider (정의) | 주체 | 값 | 시점 |
|---|---|---|---|
| `noteStoreProvider` (CORE) | `CoreModule` | `overrideWithValue(store)` | 이번 |
| `ink.pageBackgroundBuildersProvider`, `pdfIoConfigProvider` (INK, PDF) | `PdfModule` → `pdfIoOverrides()` | PDF 빌더 + 속지 빌더. PDF 시작 실패 시 없음 | 이번 |
| `pageThumbnailRendererProvider` (CORE) | `FeatureWiringModule` | `overrideWith((ref) => ref.watch(ink.inkPageThumbnailRendererProvider))` | 이번 |
| `libraryPdfImportActionProvider` (LIBRARY) | `FeatureWiringModule` | `overrideWithValue(importPdfAsNewNote)` (PDF 실패 시 생략) | 이번 |
| `libraryPdfExportActionProvider` (LIBRARY) | `FeatureWiringModule` | `overrideWithValue(exportNotesAsPdf)` (PDF 실패 시 생략) | 이번 |
| `editorExtensionsProvider` (EDITOR) | `FeatureWiringModule` | `editorExtensionsFromPdf(...)` (PDF 실패 시 생략) | 이번 |
| `devOverlaySectionsProvider` (EDITOR) | `FeatureWiringModule` | `[pdfRenderStatsSection(ref)]` (PDF 실패 시 생략) | 이번 |
| (`featureEditorOverrides()`, `featureLibraryOverrides()`의 항목) | `FeatureWiringModule` | 각 패키지가 정한 값(현재 빈 목록) | 이번 |
| `syncBadgeProvider`, `remoteAssetFetcherProvider` (CORE) + SYNC 설정 4종 | `SyncModule` | 계약 7.3.3 M4 행: `syncEngine.statusStream.map(syncBadgeOf).distinct()`(v1.1), `SyncRemoteAssetFetcher`, SYNC 5.2 | M4 |

PDF 렌더 통계 섹션 문구(`formatPdfRenderStats`, 4 Hz 이하 갱신):

```text
메모리 미리보기 12.3 · 타일 40.1 · 썸네일 2.0 MB (초과 0 MB)
대기 3 · 진행 1 · 완료 120 · 취소 4 · 이미지 18
렌더 최근 12ms · p95 30ms · 열린 문서 2
```

코드 생성(riverpod_generator)은 쓰지 않는다 (빌드 단계 추가 없음, 계약 7.4.7).

### 6.9 웹 플랫폼 설정과 iPad Safari 대응

#### 엔진이 이미 하는 일 (Flutter 3.47.9 엔진 소스 `engine/src/flutter/lib/web_ui/lib/src/engine/` + 컴파일된 `main.dart.js` 확인함)

- `<meta name="viewport">`를 **모두 지우고** `width=device-width, initial-scale=1.0, maximum-scale=5.0`을 새로 넣는다(`view_embedder/embedding_strategy/full_page_embedding_strategy.dart` `_applyViewportMeta`) → index.html에 쓴 viewport는 무시된다.
- 호스트 요소(`body`)에 `position: fixed; overflow: hidden; user-select: none; -webkit-user-select: none; touch-action: none`(같은 파일 `_setHostStyles`).
- 포인터 다운이 Flutter 뷰에 떨어지면 `pointerdown`을 `preventDefault`(포커스 처리용, `pointer_binding.dart`).
- **브라우저 `contextmenu`는 기본으로 막지 않는다.** 엔진 `mouse/context_menu.dart`의 `ContextMenu`는 `_enabled = true`로 시작하고, `contextmenu` `preventDefault` 리스너는 프레임워크가 `flutter/contextmenu` 채널로 `disableContextMenu`를 보낼 때만 붙는다(`platform_dispatcher.dart`). 프레임워크·material_ui는 기본으로 이 호출을 하지 않는다(`BrowserContextMenu.enabled` 기본 true). 초안의 "엔진이 contextmenu를 막는다"는 틀린 기록이었고, 이 확인 결과가 계약 7.4.9 v1.1에 반영됐다(12.3 P1 승인, C11-28 — 총괄도 엔진 소스로 확인).
- `-webkit-touch-callout`, `overscroll-behavior`, `gesturestart`는 다루지 않는다.
- 첫 프레임에 `window`로 `flutter-first-frame` 이벤트.

#### `app/web/index.html` 요구 사항

| 항목 | 내용 |
|---|---|
| 문서 | `<html lang="ko">`, `<base href="$FLUTTER_BASE_HREF">`(**유지** — PDF·CORE 자산 주소의 기준, 계약 7.4.9), `<meta charset="UTF-8">` |
| PWA·iOS 메타 | `theme-color #3949AB`, `mobile-web-app-capable yes`, `apple-mobile-web-app-capable yes`, `apple-mobile-web-app-status-bar-style default`, `apple-mobile-web-app-title 필기노트`, `format-detection telephone=no`, `apple-touch-icon → icons/Icon-180.png`, `icon → favicon.png`, `manifest → manifest.json` |
| CSS (html, body) | `margin:0; height:100%; overflow:hidden; overscroll-behavior:none; background:#FFFFFF; -webkit-user-select:none; user-select:none; -webkit-touch-callout:none; -webkit-tap-highlight-color:transparent; -webkit-text-size-adjust:100%; touch-action:none` — iPad 손가락·펜슬 길게 누르기의 콜아웃·텍스트 선택은 이 CSS로 막는다 |
| viewport 고정 | 인라인 스크립트: `head`에 `MutationObserver(childList)` → 추가되는 `meta[name=viewport]`의 content를 `width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no`로 덮어씀 (엔진이 넣는 `maximum-scale=5.0` 무력화, 입력란 포커스 시 자동 확대도 방지) |
| 제스처 차단 | `document`에 `gesturestart` · `gesturechange` · `gestureend` · `dblclick` 리스너 `{passive:false}`로 `preventDefault()` (Safari 페이지 핀치·더블탭 확대 방지 — EDITOR 5.3 #5(b)) |
| contextmenu 가드 | `document`에 `contextmenu` 리스너: 대상이 `input`·`textarea`·`[contenteditable]` 안이 **아니면** `preventDefault()` (마우스·트랙패드 우클릭, 길게 누르기로 `contextmenu`를 내는 브라우저의 메뉴 차단). 텍스트 입력의 브라우저 편집 메뉴는 남긴다 — 아래 'BrowserContextMenu 결정' |
| HTML 로더 | `#app-loader`: 앱 이름, CSS 회전 표시, 상태 문구(`#app-loader-status`: "불러오는 중…" → 부트스트랩 JS가 "엔진 준비 중…"으로 갱신). `flutter-first-frame`에서 제거 |
| 로딩 실패 표시 | 30초 안에 첫 프레임이 없거나, 그 전에 `error`/`unhandledrejection` 발생 → `#app-loader-error`에 "불러오지 못했어요" + 메시지 + [새로고침] 버튼 |
| 기타 | `<noscript>` 안내, `<script src="flutter_bootstrap.js" async>`. CSP 메타는 두지 않는다(계약 7.4.9) |

#### `BrowserContextMenu` 결정 (EDITOR 5.3 #5(a) 답, INFRA-S5 → 계약 7.4.9 v1.1)

계약 7.4.9 v1.1 문장(C11-28, 원문 그대로):

> `BrowserContextMenu.disableContextMenu()`는 쓰지 않는다(텍스트 입력의 브라우저 메뉴까지 끄고 프레임워크가 자체 선택 메뉴로 바뀜). iPad 길게 누르기 콜아웃·선택은 CSS(엔진 `user-select:none` + index.html `-webkit-touch-callout:none`)로, 우클릭 메뉴는 index.html이 입력 요소 밖에서만 `contextmenu`를 `preventDefault`해 막는다(v1.1 근거 정정 — Flutter 3.47.9 엔진 `mouse/context_menu.dart`는 `_enabled = true`로 시작하고 `disable()`에서만 리스너를 단다. 총괄 확인).

- INFRA 구현은 이 문장 그대로다: ① 엔진 호스트 CSS `user-select:none` + index.html `html, body`의 `-webkit-touch-callout:none`·`user-select:none`(iPad 길게 누르기 콜아웃·선택) ② index.html `contextmenu` 가드(입력 요소 밖 우클릭 메뉴, 위 표). `disableContextMenu()`를 쓰지 않는 이유: 루트 요소 전체의 `contextmenu`를 막아 텍스트 입력의 브라우저 메뉴까지 끄고, `BrowserContextMenu.enabled == false`가 되면 프레임워크가 웹에서도 자체 텍스트 선택 메뉴로 바꾼다(`editable_text.dart` `_webContextMenuEnabled`).
- 00-review 3.1 INFRA-S5·3.4 Q11의 옛 근거('엔진이 이미 막음')는 이 문장으로 대체됐다(00-review 2차 2.2 INFRA P1 '수용').
- 확인: 9.3 #5(손가락·펜슬 길게 누르기)·#19(트랙패드 우클릭). 가드가 부족하면(메뉴가 뜨면) 직접 바꾸지 않고 계약 7.4.12 절차(결과 보고 '변경 요청' → 총괄 승인 → 7.4.9 개정)로 `disableContextMenu()` 사용 여부를 다시 정한다.

#### `app/web/flutter_bootstrap.js` (사용자 지정 템플릿, 확인함)

- 첫 줄 `{{flutter_js}}`, 다음 `{{flutter_build_config}}` 토큰 (빌드 시 치환됨 확인).
- **서비스 워커 등록 안 함** (`serviceWorkerSettings` 생략) + 이미 등록된 것 모두 `unregister()` (오류 무시).
- 렌더러 선택: URL `?renderer=skwasm|canvaskit|default` 또는 `localStorage['noteapp.renderer']`(try/catch). `skwasm` 요청 + `_flutter.buildConfig.builds`에 dart2wasm 빌드가 있을 때만 `config = {renderer: 'skwasm', wasmAllowList: {blink: true, gecko: true, webkit: true}}`, 그 밖에는 `{renderer: 'canvaskit'}`. `default`는 저장값 삭제.
- `_flutter.loader.load({config, onEntrypointLoaded})`에서 상태 문구 갱신 후 `initializeEngine()` → `runApp()`.
- `--web-define` 템플릿 변수는 쓰지 않는다 (정의 없이 `flutter run`하면 치환 안 된 `{{…}}`가 남아 JS 오류가 나기 때문).

#### `app/web/manifest.json`

| 필드 | 값 |
|---|---|
| `id` / `start_url` / `scope` | `/` / `/` / `/` |
| `name` / `short_name` | `필기노트 (테스트)` / `필기노트` — 비-live 채널은 `finalize-web`이 `필기노트 미리보기 (<채널>)` / `노트β`로 변경 |
| `display` | `standalone` |
| `orientation` | `any` (태블릿 가로·세로) |
| `background_color` / `theme_color` | `#FFFFFF` / `#3949AB` |
| `lang` | `ko` |
| `icons` | 192, 512 (`purpose: any`), maskable 192, 512 (`purpose: maskable`) |

#### 아이콘 (`tool/gen_icons.dart`, package:image 4.12.0)

- 배경 `#3949AB`, 흰 둥근 종이 사각형(가로 56%) + 줄 3개 + 대각선 펜 획. maskable은 안전 영역 80% 안에 그림.
- 출력: `favicon.png` 32, `Icon-180.png`, `Icon-192.png`, `Icon-512.png`, `Icon-maskable-192.png`, `Icon-maskable-512.png`. 생성물 커밋, R13이 크기 검사.

### 6.10 웹 렌더러 선택 근거 (D6)

| 사실 (Flutter 3.47.9, 확인함) | 의미 |
|---|---|
| `flutter build web` 기본 결과: `builds: [{dart2js, canvaskit}]` | 기본은 CanvasKit |
| `--wasm` 결과: `[{dart2wasm, skwasm}, {dart2js, canvaskit}]` (빌드 66초, `main.dart.wasm` 2.1MB 추가) | 브라우저가 고름 |
| 로더 기본 `wasmAllowList = {blink: true, gecko: false, webkit: false}` | **Safari(WebKit)는 skwasm 제외 → CanvasKit** |
| skwasm은 `crossOriginIsolated`가 아니면 단일 스레드 | 다중 스레드에는 COOP/COEP 헤더 필요 |
| 기본 빌드도 wasm dry run 통과 (riverpod · go_router · material_ui 포함) | 코드가 wasm 호환 상태 |
| CanvasKit은 기본적으로 `https://www.gstatic.com/flutter-canvaskit/<엔진 리비전>`에서 받음 | `build/web/canvaskit/`(37MB)은 CDN을 끌 때만 사용 |

결정: 기본 채널은 dart2js + CanvasKit (`--no-wasm-dry-run`으로 CI 시간 절약). 필기 지연 비교가 필요하면 `web-experiment.yml`로 `--wasm` 빌드를 `exp-wasm` 채널에 올리고, iPad에서 같은 주소를 `?renderer=skwasm`/`?renderer=canvaskit`으로 번갈아 열어 EDITOR의 개발자 표시로 비교. 필기감 최종 판정은 PLAN대로 네이티브 전환 단계.

### 6.11 '옛 버전이 보이는' 문제 대응 (D7)

원인과 대응:

| 원인 | 대응 |
|---|---|
| 서비스 워커 캐시 | 등록 안 함 + 부트스트랩에서 기존 등록 해제. Flutter가 만드는 `flutter_service_worker.js`도 자기 해제 + 클라이언트 새로고침 코드임 (확인함) |
| HTTP 캐시 (`main.dart.js`, `flutter_bootstrap.js`는 파일명에 해시가 없음) | Hosting 전 경로 `Cache-Control: no-cache` → 매번 ETag 재검증(바뀌지 않았으면 304) |
| iPad 홈 화면 앱은 백그라운드에서 돌아와도 페이지를 다시 읽지 않음 | `UpdateChecker`가 `/build_info.json`을 확인 → 배너 |
| 사용자가 어느 버전인지 모름 | 앱 정보에 `displayLabel`, 진단 정보에 포함 |

`UpdateChecker` 알고리즘:

1. `build()`: `runtime.isWeb == false` 또는 `build.isLocal` 또는 `channel == local` → `UpdateDisabled`, 끝.
2. 아니면 `UpdateUnknown`, `initialDelay`(5초) 뒤 첫 확인, 이후 `interval`(10분)마다 — 단 화면이 보일 때만. `visibilityChanges`의 `visible` 이벤트에서는 마지막 확인이 `minGapOnResume`(60초)보다 오래됐으면 확인. 타이머·구독은 `ref.onDispose`에서 해제.
3. 확인: `fetchTextNoStore('build_info.json', timeout: 5초)` → JSON → `BuildInfo.fromJson`. 실패(null·형식 오류)면 상태 유지 (오류 로그에 남기지 않음, 디버그 출력만).
4. `remote.gitSha == local.gitSha` → `UpdateUpToDate(now)`. 다르면: `dismissedSha == remote.gitSha` → `UpdateDismissed`, 아니면 `UpdateAvailable(remote)`.
5. 배너(해요체): "새 버전이 나왔어요 (#43 · b2c3d4e). 새로고침하면 적용돼요." [나중에] → `dismiss()`, [새로고침] → `applyUpdate()` = `notifyAppHidden()`(저장 flush, 최대 500ms) → `reload()`.
6. 자동 새로고침은 하지 않는다 (필기 중 끊김 방지).

빌드 정보 전달:

- `tool/ws.dart build-info --channel <c> --out build/build_info.json` → `{"APP_VERSION": "0.1.0", "APP_BUILD_NUMBER": "42", "APP_GIT_SHA": "<40자>", "APP_GIT_REF": "main", "APP_CHANNEL": "live", "APP_BUILD_TIME": "2026-11-04T09:10:00Z"}` (값은 모두 문자열).
- `flutter build web --dart-define-from-file=../build/build_info.json --build-number=$GITHUB_RUN_NUMBER`.
- `finalize-web`이 같은 파일을 `app/build/web/build_info.json`으로 복사 → 컴파일된 값과 서버 파일이 항상 같은 출처.

### 6.12 Firebase Hosting

`app/firebase.json` (배포 기준 디렉터리 `app/`, Actions의 `entryPoint: app`):

| 키 | 값 |
|---|---|
| `hosting.public` | `build/web` |
| `hosting.ignore` | `["firebase.json", "**/.*"]` |
| `hosting.rewrites` | `[{"source": "**", "destination": "/index.html"}]` (정적 파일이 있으면 그 파일이 우선) |
| `hosting.headers` | `[{"source": "**", "headers": [{"key": "Cache-Control", "value": "no-cache"}]}, {"source": "**/*.wasm", "headers": [{"key": "Content-Type", "value": "application/wasm"}]}]` — **COOP/COEP 없음**(계약 7.4.9). `.wasm` 줄은 CORE I-3·PDF I-2 요구(Hosting 기본 MIME도 `application/wasm`일 가능성이 높음 — 미확인, G5 배포 후 `curl -I`로 확인) |
| 격리 변형 (`ws.dart hosting-config --isolate`) | 위 헤더에 `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp` 추가. 이때 빌드는 `--no-web-resources-cdn`(CanvasKit 자체 호스팅). `web-experiment` 채널 전용 |

- `.firebaserc`는 커밋하지 않는다. 프로젝트 ID는 GitHub 저장소 변수 `FIREBASE_PROJECT_ID`.
- 배포 전 `web-assets verify`로 `sqlite3.wasm`·`drift_worker.js` 누락·변조 방지 (누락 시 재작성 규칙 때문에 `index.html`이 대신 응답되어 원인을 찾기 어려움).
- CSP는 두지 않는다(계약 7.4.9). 둔다면 PDF I-2의 `worker-src blob:`, `script-src 'self' blob: 'wasm-unsafe-eval'`가 필요하다.

M4 형태 (INFRA-S4, 연결은 M4 — 이번에는 문서화와 검사기만): SYNC 규칙·색인 파일은 SYNC 소유 경로에 두고 `app/firebase.json`이 상대 경로로 참조한다(07-sync 3절·5.2 I-4, SYNC-S1).

```json
{
  "hosting": { "...": "as above" },
  "firestore": {
    "rules": "../packages/sync_engine/firebase/firestore.rules",
    "indexes": "../packages/sync_engine/firebase/firestore.indexes.json"
  },
  "storage": { "rules": "../packages/sync_engine/firebase/storage.rules" }
}
```

- `hosting_config_test`(9.1)는 `firestore.rules`·`firestore.indexes`·`storage.rules` 키가 있으면 각 경로가 `app/` 기준으로 **존재하는 파일**인지 확인한다. 이번 범위 `firebase.json`에는 키가 없으므로 M4 형태 픽스처(`tool/test/fixtures/firebase_m4/`)로 검사기를 시험한다.
- firebase-tools가 `firebase.json` 밖(`../`) 경로를 읽는지는 미확인 → M4에서 `firebase deploy --only firestore:rules --dry-run`으로 확인하고, 안 되면 CI가 배포 직전 세 파일을 `app/build/firebase/`로 복사한 뒤 그 경로를 쓰는 형태로 바꾼다.
- CI 배포 명령(M4): `firebase deploy --only firestore:rules,firestore:indexes,storage`(SYNC I-4), Hosting 배포와 같은 서비스 계정 + 역할 추가(안내서 02 갱신).

채널 전략:

| 푸시 대상 | 채널 ID | 만료 | 주소 |
|---|---|---|---|
| `main` | `live` | 없음 | `https://<프로젝트 ID>.web.app` (고정, 홈 화면에 추가할 주소, M4 로그인·동기화 확인도 여기서만) |
| 그 밖의 브랜치 | `previewChannelId(branch)` | 7일 (재배포 시 연장) | `https://<프로젝트 ID>--<채널>-<무작위>.web.app` — Actions 실행 요약에 표시. **출처가 달라 데이터·홈 화면 앱·로그인이 live와 따로이고 임시**다(계약 7.4.9) |
| 실험 | `exp-wasm` | 7일 | 같은 형식 |

`previewChannelId(branch)` (FirebaseExtended/action-hosting-deploy는 `channelId`가 비면 `pull_request` 이벤트 정보로만 ID를 만들어 **push 이벤트에서는 쓸 수 없음** — 소스 확인함):

1. `refs/heads/` 접두어 제거, 소문자화, `claude/` 접두어 제거
2. `[a-z0-9]` 외 문자는 `-`, 연속 `-`는 하나로, 양끝 `-` 제거
3. `slug` = 앞 12자 (끝 `-` 제거), 비면 `branch`
4. `hash` = 원래 브랜치 이름 UTF-8의 FNV-1a 32비트 → 16진 8자리 중 앞 6자리
5. 결과 `b-<slug>-<hash>` (최대 21자: DNS 레이블 63자 = 프로젝트 ID 최대 30 + `--` + 채널 + `-` + 무작위 8 이내)

예: `claude/note-app-planning-bk29xb` → `b-note-app-pla-xxxxxx`, 영역 브랜치 `area/infra`(계약 7.4.12) → `b-area-infra-xxxxxx`.

### 6.13 GitHub Actions

공통: Flutter는 `subosito/flutter-action@v2`의 `flutter-version-file: pubspec.yaml`(루트, `environment.flutter: 3.47.9`) + `cache: true`(SDK 캐시, pub 캐시 키 = `**/pubspec.lock` 해시 — action.yaml 확인함). 모든 잡에 `timeout-minutes`, `permissions: contents: read`. 시크릿은 잡 `env`로 받아 `if: env.X != ''`로 판단 (`if`에서 `secrets` 직접 참조 불가).

#### `ci.yml` — 검사 + 웹 빌드 + 배포 (잡 1개: 분 단위 올림 과금을 줄이기 위해)

| 항목 | 설정 |
|---|---|
| 트리거 | `push` (모든 브랜치, `paths-ignore: docs/**, **/*.md, .github/ISSUE_TEMPLATE/**`), `workflow_dispatch` (입력 `deploy: boolean = true`, `integration: boolean = false`) |
| 동시성 | `group: ci-${{ github.ref }}`, `cancel-in-progress: true` |
| 러너 / 제한 | `ubuntu-latest`, `timeout-minutes: 25` |
| env | `FIREBASE_SA: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}`, `FIREBASE_PROJECT_ID: ${{ vars.FIREBASE_PROJECT_ID }}` |

단계:

| # | 단계 | 명령 | 조건 |
|---|---|---|---|
| 1 | 체크아웃 | `actions/checkout@v7`, `fetch-depth: 0` | |
| 2 | Flutter | `subosito/flutter-action@v2` | |
| 3 | 빌드 훅 캐시 | `actions/cache@v6`: `path: .dart_tool/hooks_runner`(워크스페이스 루트 — sqlite3 미리 빌드 라이브러리, pdfium_dart의 PDFium 바이너리·게이트 라이브러리), `key: hooks-${{ runner.os }}-${{ hashFiles('pubspec.lock') }}`, `restore-keys: hooks-${{ runner.os }}-` | |
| 4 | 준비 산출물 캐시 | `actions/cache@v6`: `path:` 각 멤버 준비 스크립트 산출물(계약 7.4.8: `packages/note_core/test/web/sqlite3.wasm`, `packages/note_core/test/web/drift_worker.js`, `packages/pdf_io/test/web/pdfium/`, `app/test/web/sqlite3.wasm`, `app/test/web/drift_worker.js`), `key: prep-${{ runner.os }}-${{ hashFiles('pubspec.lock', 'tool/web_assets.yaml', '**/tool/prepare_web_test.dart') }}`. 경로가 바뀌면 캐시만 빗나가고(스크립트가 다시 받음) 실패하지 않는다 | |
| 5 | 의존성 | `flutter pub get --enforce-lockfile` (루트) | |
| 6 | 규칙 | main: `dart run tool/ws.dart check --strict` / 그 외: `ws.dart check` | |
| 7 | 분석 | `dart run tool/ws.dart analyze` | |
| 8 | VM 테스트 | main: `ws.dart test` / 그 외: `ws.dart test --affected-since origin/main` (PDF `pdfium` 태그 테스트도 이 규칙으로 PDF가 바뀐 브랜치에서만 — PDF-S8) | |
| 9 | 브라우저 테스트 | main: `ws.dart test --platform chrome` / 그 외: `… --platform chrome --affected-since origin/main`. `ws`가 멤버별 `tool/prepare_web_test.dart`를 먼저 실행. 러너 기본 Chrome(`google-chrome`) 사용 — 미확인, 없으면 `browser-actions/setup-chrome` + `CHROME_EXECUTABLE` | |
| 10 | 통합 태그 테스트 | `ws.dart test --run-skipped -t integration` 후 `ws.dart test --platform chrome --run-skipped -t integration` | `inputs.integration == true` (통합 단계 G2 이후 수동 실행) |
| 11 | 채널 결정 | main → `live`, 그 외 → `ws.dart channel-id --branch "$GITHUB_REF_NAME"` → `$GITHUB_OUTPUT` | |
| 12 | 빌드 정보 | `ws.dart build-info --channel … --out build/build_info.json` | |
| 13 | 웹 자산 확인 | `ws.dart web-assets verify` | |
| 14 | 웹 빌드 | `cd app && flutter build web --release --no-wasm-dry-run --dart-define-from-file=../build/build_info.json --build-number=$GITHUB_RUN_NUMBER` | |
| 15 | 마무리 | `ws.dart finalize-web --build-dir app/build/web --info build/build_info.json` (`main.dart.js` 크기를 요약에 기록) | |
| 16 | 배포 | `FirebaseExtended/action-hosting-deploy@v0`: `firebaseServiceAccount: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}`, `projectId: ${{ vars.FIREBASE_PROJECT_ID }}`, `channelId`, `expires: 7d`, `entryPoint: app`, `firebaseToolsVersion: 15.34.2`, `disableComment: true` (repoToken 안 줌) | `env.FIREBASE_SA != '' && env.FIREBASE_PROJECT_ID != '' && (github.event_name == 'push' \|\| inputs.deploy)` |
| 17 | 요약 | `$GITHUB_STEP_SUMMARY`에 빌드 라벨, 채널, 주소(`steps.deploy.outputs.details_url`) 또는 "Firebase 미설정 — docs/guides/02-github-secrets.md", 단계별 소요 시간, `main.dart.js` 크기 | `always()` |

- 테스트 코드는 네트워크를 쓰지 않는다. 네트워크가 필요한 것은 빌드 훅(첫 `flutter test`·`flutter build` 때)과 준비 스크립트뿐이며 3·4단계 캐시로 반복 다운로드를 피한다(계약 7.4.8, INFRA-M4).
- 기반 단계 B1의 `ci.yml`은 1·2·5–9·14단계만(배포·채널·빌드 정보 없음, 웹 빌드는 정의 없이).
- 커밋 메시지에 `[skip ci]`가 있으면 GitHub가 실행하지 않는다 (기본 기능).

#### `android.yml` — APK

| 항목 | 설정 |
|---|---|
| 트리거 | `push: branches: [main]` (`paths-ignore` 동일), `workflow_dispatch`. **통합 단계 추가**: 기본 브랜치에 합치기 전까지 개발 브랜치 `claude/note-app-planning-bk29xb`도 `push` 목록에 둔다(`workflow_dispatch`는 기본 브랜치에 파일이 있어야 버튼이 생겨서 — 안내서 05 '개발 브랜치에서 받기'). 합친 뒤 지운다 |
| 러너 / 제한 | `ubuntu-latest`, `timeout-minutes: 30` |
| 단계 | 체크아웃 → `actions/setup-java@v6` (`temurin`, `17`, `cache: gradle`) → flutter-action → 빌드 훅 캐시(3단계와 같은 키) → `pub get --enforce-lockfile` → `build-info` → `cd app && flutter build apk --release --split-per-abi --build-number=$GITHUB_RUN_NUMBER --dart-define-from-file=…` → `actions/upload-artifact@v7` (`name: noteapp-apk-${{ github.run_number }}`, `path: app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`, `retention-days: 7`, `compression-level: 0`) |
| 참고 | 생성된 안드로이드 설정: AGP 9.1.0, Gradle 9.3.1, Kotlin 2.4.0, Java 17 대상 (확인함). 컨테이너에 Android SDK가 없어 APK 빌드는 CI에서만 확인 가능 (미확인). 이번 범위 앱은 `sync_engine`(Firebase 플러그인)에 의존하지 않으므로 APK에 Firebase가 들어가지 않는다 |

#### `web-experiment.yml` — 렌더러 실험 (수동)

입력 `wasm: boolean = true`, `isolate: boolean = false`. `--wasm` 빌드(+ `isolate`면 `--no-web-resources-cdn`과 `hosting-config --isolate` 결과로 `app/firebase.json` 교체) → 채널 `exp-wasm`, 7일. `timeout-minutes: 25`. (INK ink lab이 멤버가 되면 입력 `target: app|ink_lab` 추가 — INFRA-O1. **통합 단계에서 추가**: `ink_lab`이면 `packages/ink_engine/example`에서 같은 플래그로 빌드 → `app/build/web`으로 복사 → 채널 `exp-ink-lab`(app은 `exp-wasm` 그대로), `finalize-web`은 app만)

#### `ios-testflight.yml` — 초안 (비활성)

| 항목 | 설정 |
|---|---|
| 트리거 | `workflow_dispatch`만, 입력 `confirm`("macOS 10배 과금 확인: yes 입력") |
| 게이트 | 잡 `if: vars.IOS_TESTFLIGHT_ENABLED == 'true' && inputs.confirm == 'yes'` |
| 러너 / 제한 | `macos-latest` (라벨 미확인), `timeout-minutes: 45` |
| 시크릿 | `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`(p8 내용) |
| 단계 (미검증) | 체크아웃 → flutter-action → pub get → p8 파일 기록 → `flutter build ios --release --no-codesign --build-number=$GITHUB_RUN_NUMBER --dart-define-from-file=…` → `xcodebuild archive -allowProvisioningUpdates -authenticationKeyPath/-ID/-IssuerID DEVELOPMENT_TEAM=… CODE_SIGN_STYLE=Automatic` → `xcodebuild -exportArchive` (`app/ios/ExportOptions.plist`: `method: app-store-connect`, `destination: upload`) |

#### 이슈 템플릿 (`.github/ISSUE_TEMPLATE/feedback.yml`)

입력: 기기(드롭다운: iPad Pro 13 / 안드로이드 태블릿 / 기타), 펜슬 종류, 앱 버전(앱 정보의 빌드 라벨 붙여넣기), 무엇을 했는지, 기대한 동작, 실제 동작, 진단 정보(선택, 앱에서 복사), 스크린샷·화면 녹화. `config.yml`: `blank_issues_enabled: true`.

#### 무료 사용 시간(월 2,000분, macOS 10배) 예산

아래 1회 시간은 **추정치**다. 기반 단계 B8의 첫 CI 실행(체크포인트 푸시)에서 단계별 시간·`main.dart.js` 크기를 재고, Chrome 첫 `openNoteStore` 시간(CORE가 B2에서 `UnimplementedError`이면 통합 G2에서)과 함께 이 표와 6.4의 시간 제한을 갱신한다(INFRA-S2, 계약 7.6 B8). 실측 기록란은 9.2.

| 워크플로 | 1회 예상 (캐시 적중, 추정) | 월 가정 | 월 분 |
|---|---|---|---|
| `ci.yml` | 8분 (설정 1 + 검사·분석 1 + VM 테스트 2 + 브라우저(준비 포함) 1.5 + 빌드 1.5 + 배포 0.5 + 여유 0.5) | 120회 | 960 |
| `android.yml` | 8분 | 20회 | 160 |
| `web-experiment.yml` | 6분 | 4회 | 24 |
| `ios-testflight.yml` | 15분 × 10배 | 3회 | 450 |
| 합계 | | | 약 1,594 (여유 20%) |

| 실측 항목 (B8에서 채움) | 값 | 반영 |
|---|---|---|
| `ci.yml` 1회 총 시간 / 단계별(캐시 없음·있음) | GitHub 실행은 아직 없음(동시 개발 중 푸시 금지 — G5에서 채움). 로컬 컨테이너 대용 측정(빌드 훅 캐시 있음): B8 `ws test` 54.8초 · `--platform chrome` 99.0초 · 웹 빌드(`--no-wasm-dry-run`) 42.5초. I15(다른 에이전트와 CPU 공유): `ws test` 1분 56초 · `--platform chrome` 3분 44초 · `flutter build web --release`(wasm dry run 포함) 1분 37초 · `dart test tool/test` 16초 · `ws analyze` 5초 | 위 표 (G5 실측 뒤 고침) |
| `main.dart.js` 크기 (기반 단계 / 통합 후) | B1 1,742,932 B · B8 2,471,812 B(gzip 733,501 B) · I15(다른 영역 자리표시 상태) 2,747,922 B(gzip 814,454 B) / 통합 후 G4(실제 7개 영역, `cd app && flutter build web --release`, wasm dry run 포함 1분 52초 — 컴파일 110초) **4,633,843 B(gzip 1,366,038 B)** — I15보다 +1.89 MB(gzip +552 KB). iPad 재방문 시작 2초 목표(6.4 5)는 G5 iPad 확인(9.3 #1)에서 잰다 | 11절 리스크, 시작 시간 목표 |
| Chrome 첫 `openNoteStore` (빈 DB) | B8·동시 개발 중 측정 불가(이 작업 트리의 CORE는 B2 자리표시) → **G2 V6(헤드리스 Chrome, 백엔드 `webSharedIndexedDb`): `core` 단계 2.8~3.0초, 부트스트랩→라이브러리 3.4~3.8초**(3회, 다른 에이전트와 CPU 공유). 릴리스 빌드(Playwright, 1032×1376)에서 첫 프레임까지 약 1.7초 | `CoreModule.startTimeout` 20초 유지(여유 충분) |

절약 장치: 문서만 바꾼 푸시 제외, 같은 브랜치 이전 실행 취소, 브랜치는 영향받은 패키지만 테스트, 빌드 훅·준비 산출물 캐시, 통합 태그 테스트는 수동, APK는 main·수동만, iOS는 수동 + 변수 게이트, 모든 잡 시간 제한, Dependabot 미사용(PR마다 CI 소모). 동시 개발 중 영역 브랜치는 **체크포인트·통합 때만 푸시**한다(계약 7.4.12). 실측이 예산을 넘으면 브랜치 푸시의 브라우저 테스트를 영향받은 멤버로만 줄이는 것부터 조정한다.

### 6.14 안드로이드 서명

- 기본: 템플릿 그대로 release를 debug 키로 서명. CI가 매번 새 debug 키를 만들기 때문에 **새 APK를 기존 앱 위에 덮어 설치할 수 없음** (지우고 설치 → 로컬 데이터 삭제). 안내서 05에 명시.
- 선택 (안드로이드 태블릿 보유 확인 후): 시크릿 `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`가 있으면 CI가 `app/android/key.properties`와 키스토어를 만들고 `build.gradle.kts`가 그 파일이 있을 때만 release 서명에 사용. 키스토어는 컨테이너의 `keytool`(OpenJDK 21 있음, 확인함)로 Claude가 만들어 사용자에게 시크릿 등록을 안내.
- `applicationId`/번들 ID는 기반 단계에 `flutter create --org`로 정해지고 설치 후 바꾸면 다른 앱이 된다 → Q12.

### 6.15 iOS 초안

- 기반 단계 `flutter create --platforms=web,android,ios`로 `app/ios/` 생성 (Swift Package Manager 기본 켜짐 — Flutter 설정 확인함).
- `app/ios/ExportOptions.plist`, `CFBundleDisplayName = 필기노트`만 추가. 실제 서명·업로드 검증은 네이티브 전환 단계.

### 6.16 사용자 안내서 (`docs/guides/`)

공통 형식: 맨 위 "소요 시간 · 준비물 · 끝나면 Claude에게 알려줄 것", 단계마다 **어느 화면에서 무엇을 누르는지**, 화면 이름이 다르면 "콘솔 위 검색창에 '…' 입력" 대안, 마지막에 "확인 방법"과 "문제 해결". 콘솔 메뉴 이름은 작성 시점 기억 기반이므로 "화면이 다르면 스크린샷을 보내 주세요" 문구 포함. 문체는 해요체.

| 파일 | 내용 |
|---|---|
| `README.md` | 순서: 01 → 02 → 04 (→ 03은 Blaze 전환 때, 05는 태블릿이 있을 때, 06은 네이티브 전환 때) |
| `01-firebase-project.md` | console.firebase.google.com → 프로젝트 추가 → 이름 → Google 애널리틱스 끄기 → 만들기. 왼쪽 메뉴 Hosting → 시작하기 (CLI 단계는 건너뛰기 — Claude가 처리). 프로젝트 설정에서 **프로젝트 ID** 확인 → Claude에게 전달. 요금제가 Spark(무료)인지 확인. **'M4 때 정할 것(지금은 만들지 않음)' 상자**(INFRA-S4, SYNC-S3): Firestore 데이터베이스 위치 권장 `asia-northeast3`(서울), Cloud Storage 버킷 위치는 무료 사용량 조건 때문에 US 리전(예: `us-central1`) 권장 — **위치는 만든 뒤 바꿀 수 없고, 무료 조건은 작성 시점 기억 기반이라 콘솔에서 다시 확인(미확인)**, 최종 선택은 사용자(00-review U3). Google 로그인용 `authDomain`은 앱이 서비스되는 Hosting 도메인(`<프로젝트 ID>.web.app`)으로 두고 '승인된 도메인'에 live 주소가 있는지 확인(상세 절차는 M4 때 갱신) |
| `02-github-secrets.md` | Google Cloud 콘솔 → IAM 및 관리자 → 서비스 계정 → 만들기 (`github-deploy`) → 역할 4개: Firebase Hosting 관리자(`roles/firebasehosting.admin`), Firebase 인증 관리자(`roles/firebaseauth.admin`), Cloud Run 뷰어(`roles/run.viewer`), API 키 뷰어(`roles/serviceusage.apiKeysViewer`) (action 문서 확인함) → 키 → JSON 만들기 → GitHub 저장소 Settings → Secrets and variables → Actions → Secret `FIREBASE_SERVICE_ACCOUNT`(JSON 전체), Variables 탭 `FIREBASE_PROJECT_ID`. 받은 JSON 파일은 등록 후 삭제. 문제 해결: 조직 정책으로 키 생성이 막힌 경우(`iam.disableServiceAccountKeyCreation`), 개인 Gmail 계정이면 보통 해당 없음. 확인: Actions → CI → Re-run → 요약에 주소. (M4에 규칙 배포 역할 추가 예정 표시) |
| `03-budget-alert.md` | Spark 요금제에는 결제 계정이 없어 예산 알림을 걸 수 없음 → **Blaze로 바꿀 때(M4 Storage·Functions) 즉시** 설정: Google Cloud 콘솔 → 결제 → 예산 및 알림 → 예산 만들기 (금액 예: 1,000원, 알림 50·90·100%). 예산 알림은 과금을 멈추지 않는다는 점. Hosting → 릴리스 기록 보관 개수 10개로 설정 (저장 용량 절약). 무료 한도(Hosting 저장 10GB · 전송 360MB/일)는 기억 기반 수치 — 콘솔 '사용량 및 결제'에서 확인 (미확인) |
| `04-ipad-web-test.md` | 주소 찾기(live 고정 주소 / 브랜치 미리보기 주소는 Actions 실행 요약), Safari로 열기, 공유 버튼 → '홈 화면에 추가'(**필기는 홈 화면 앱으로** — Safari 탭은 왼쪽 가장자리 스와이프가 뒤로 가기를 일으킬 수 있음, EDITOR-S5), 설정 → 앱 정보에서 빌드 라벨 확인, 새 버전 배너와 새로고침, 홈 화면 앱 완전 종료 방법, **웹 버전은 테스트 전용 — 중요한 노트 금지**, 설정 → 저장 공간에서 '영구 보관' 확인, **설정 → 앱 정보 → 백업 내보내기**로 백업 파일을 파일 앱에 보관하는 방법(시트의 두 버튼: [내려받기] → 다운로드 폴더 / [공유 · 파일에 저장] → 공유 시트의 '파일에 저장'. **홈 화면 앱에서는 [내려받기]가 아무 일도 안 할 수 있으니(미확인) 그때는 [공유 · 파일에 저장]**. 둘 다 안 되면 백업은 아직 못 하는 상태이므로 바로 알려 주기. 백업을 만드는 중 '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.'가 뜨고 끝나지 않으면 [취소] → 설정 → 저장 공간 확인 → 진단 정보 복사로 알려 주기(노트 저장이 재시도 중이라는 뜻 — 4.5.8) — 홈 화면 앱과 Safari 탭은 저장 공간이 따로일 수 있어(미확인) Safari 탭에서 백업해도 홈 화면 앱의 노트가 들어가지 않을 수 있다), **미리보기 주소는 live와 데이터·홈 화면 앱·로그인이 따로이고 임시**(7일 뒤 주소가 사라지면 그 데이터도 못 씀), 로그인·동기화 확인은 live 주소에서만(M4), 문제 해결(흰 화면 → 30초 후 오류 표시 확인 → 새로고침 → 시작 오류 화면의 '진단 정보 복사' → 웹사이트 데이터 삭제·'이 기기 데이터 지우기'는 최후 수단, 테스트 노트 삭제됨), 피드백 방법(진단 정보 복사 → 채팅 / GitHub 이슈 양식), 펜슬 종류·모델 확인 방법(설정 → 일반 → 정보 → 모델 이름), 9.3 체크리스트 |
| `05-android-apk.md` | 태블릿 브라우저로 GitHub 로그인 → Actions → Android APK → 최근 실행 → Artifacts 내려받기 → zip 풀기 → '출처를 알 수 없는 앱' 허용 → 설치. 서명 때문에 업데이트 시 삭제 후 설치가 필요할 수 있음(6.14) |
| `06-ios-testflight.md` | 초안: Apple Developer Program 가입, App Store Connect 앱 등록(번들 ID), API 키(App Manager) 발급 → 시크릿 4개, 저장소 변수 `IOS_TESTFLIGHT_ENABLED=true`, TestFlight 앱 설치. "네이티브 전환 때 Claude가 최신 화면 기준으로 갱신" 표시 |

---

## 7. 외부 패키지

확인 방법: `curl https://pub.dev/api/packages/<name>`(최신 버전·pubspec), `/score`(플랫폼·라이선스 태그), 실제 해석·빌드는 scratch 워크스페이스. 확인일 2026-11-04. **버전은 계약 7.5 표가 단일 기준**이고, 다른 멤버의 외부 의존(3.3 표)은 B1에서 INFRA가 그 표대로 넣는다(웹 지원·라이선스 확인은 각 영역 계획서 7절).

### 7.1 Dart/Flutter 패키지 (INFRA가 직접 사용)

| 패키지 | 쓰는 곳 | 고정 버전 | pub.dev 최신 (게시일) | SDK 제약 | 웹 | 라이선스 | 비고 |
|---|---|---|---|---|---|---|---|
| `flutter_riverpod` | app | 3.4.3 | 3.4.3 (2026-09-03) | sdk ^3.12.0, flutter >=3.0.0 | pub.dev 태그 **없음** → 웹 빌드·wasm dry run·Chrome 테스트 통과 (확인함, INK·EDITOR·LIBRARY 실험도 같음) | MIT | 태그 누락 원인: 내부에서 `flutter_test` → `dart:io` import (pub.dev 정적 분석 결과). 중복 override는 디버그 assert (확인함) |
| `go_router` | app | 18.1.2 | 18.1.3 (2026-11-04) — 계약 7.5대로 18.1.2 유지 | sdk ^3.12.0, flutter >=3.44.0 | ✓, wasm-ready | BSD-3-Clause | 18.0.0부터 material_ui 사용. 같은 키 `NoTransitionPage`로 State 유지 (확인함) |
| `material_ui` | app | 1.10.0 | 1.10.0 (2026-11-03) | sdk ^3.13.0, flutter >=3.47.0 | ✓, wasm-ready | BSD-3-Clause | 매주 릴리스 — 올리는 것은 INFRA 단독 작업(계약 7.5). `MaterialUiCompatibilityBridge`는 deprecated → 미사용 |
| `cupertino_icons` | app | 2.0.0 | 2.0.0 (2026-09-29) | sdk ^3.12.0 | ✓ | MIT | 없으면 웹 빌드에 폰트 경고 (추가 시 사라짐 확인함) |
| `web` | app (`*_browser.dart`) | 1.1.2 | 1.1.2 (2026-10-23) | sdk ^3.13.0 | 웹 전용 | BSD-3-Clause | `fetch`·`visibilitychange`·`Blob`·`URL.createObjectURL` 사용 코드가 analyze·Chrome 테스트 통과 (fetch·visibilitychange 확인함, 다운로드는 I4에서 확인). 공유: `Navigator.share([ShareData])`·`Navigator.canShare([ShareData])`·`ShareData.files`(`JSArray<File>`) 바인딩이 1.1.2에 있음 (확인함: `lib/src/dom/html.dart`·`web_share.dart`), 실제 동작은 I4·iPad 18a/18b |
| `flutter_web_plugins` | app | SDK | — | — | ✓ | BSD-3-Clause | `usePathUrlStrategy` |
| `flutter_test` | app dev | SDK | — | — | — | BSD-3-Clause | |
| `fake_async` | app dev | 1.3.3 | 1.3.3 (2025-01-28) | sdk ^3.3.0 | ✓ | Apache-2.0 | flutter_test가 해석한 버전과 동일 |
| `flutter_lints` | 루트 dev | 6.0.0 | 6.0.0 (2025-05-27) | sdk ^3.8.0 | — | BSD-3-Clause | |
| `yaml` | 루트 dev (tool) | 3.1.4 | 3.1.4 (2026-08-28) | sdk ^3.4.0 | ✓ | MIT | |
| `args` | 루트 dev | 2.7.0 | 2.7.0 (2025-03-12) | sdk ^3.3.0 | ✓ | BSD-3-Clause | |
| `path` | 루트 dev | 1.9.1 | 1.9.1 (2024-10-17) | sdk ^3.4.0 | ✓ | BSD-3-Clause | |
| `test` | 루트 dev | **1.31.1** | 1.33.0 (2026-10-08) | sdk ^3.11.0 | ✓ | BSD-3-Clause | 최신은 Flutter 3.47.9의 `test_api 0.7.12` 고정과 충돌 → 1.31.1 (확인함, 계약 7.5). `note_core`도 이 버전 |
| `image` | 루트 dev (아이콘 생성) | 4.12.0 | 4.12.0 (2026-10-11) | sdk ^3.0.0 | ✓ | MIT | |
| `crypto` | 루트 dev (`ws web-assets` sha256) | 3.0.8 | 3.0.8 (2026-10-26) | sdk ^3.4.0 | ✓, wasm-ready | BSD-3-Clause | 계약 7.5 v1.1(C11-29, 12.3 P4 승인). note_core·pdf_io·sync_engine과 같은 버전이라 lock의 해석 버전은 그대로, 표기만 `direct dev` (확인함, 3.2) |
| `analyzer` | 루트 dev (R14, **통합 G3부터**) | **13.3.0** | 14.7.0 (2026-10-29) | sdk ^3.11.0 (13.3.0) | — (VM 도구) | BSD-3-Clause | `test 1.31.1`이 해석한 버전과 같게(계약 7.5). 13.3.0 게시일 2026-06-11. `exportNamespace.definedNames2` 동작 확인함(6.2) |

앱 셸이 쓰는 워크스페이스 패키지: `note_core`, `ink_engine`(썸네일 렌더러 provider), `feature_editor`, `feature_library`, `pdf_io` — 모두 `any`. `sync_engine`은 M4에 추가.

### 7.2 검토 후 사용하지 않음

| 패키지 | 최신 | 라이선스 | 판단 |
|---|---|---|---|
| `melos` | 8.10.0 (sdk ^3.9.0) | Apache-2.0 | pub workspace + `tool/ws.dart`로 충분 (6.1) |
| `very_good_analysis` | 11.0.0 (sdk ^3.13.0) | MIT | 규칙이 많아 동시 개발 초기 마찰(문서 주석 강제 등). flutter_lints + 선별 규칙 |
| `riverpod_lint` / `riverpod_generator` / `custom_lint` | 3.1.9 / 4.0.9 / 0.8.1 | MIT | 분석기 플러그인·코드 생성 단계 추가(계약 7.4.7). 이후 검토 |
| `package_info_plus` | 10.2.2 | BSD-3-Clause | dart-define 빌드 정보로 대체 |
| `flutter_native_splash` | 2.4.8 | MIT (미확인) | index.html 로더로 대체 |
| `flutter_launcher_icons` | 0.14.4 | MIT | 웹 미지원 태그. 네이티브 아이콘은 이후 |
| `firebase_core` 등 Firebase 패키지 | 5.1.0 … | BSD-3-Clause | 앱은 이번 범위에 직접 의존하지 않음. M4에 `sync_engine`을 통해 들어옴 |

### 7.3 도구 · GitHub Actions

| 항목 | 고정 | 확인 결과 |
|---|---|---|
| Flutter SDK | 3.47.9 stable | 2026-10-29 릴리스, Dart 3.13.7, 현재 stable (releases_linux.json 확인함) |
| `subosito/flutter-action` | `@v2` | v3 태그 없음, `flutter-version-file` · `cache` 입력 확인 (action.yaml). 라이선스 미확인 |
| `actions/checkout` | `@v7` | v7 태그 있음, v8 없음 (raw 파일 존재로 확인). 릴리스 노트 미확인 |
| `actions/cache` | `@v6` | v6 있음(`using: node24`), v7 없음 (raw `action.yml`로 확인함) |
| `actions/setup-java` | `@v6` | v6 있음, v7 없음 |
| `actions/upload-artifact` | `@v7` | v7 있음, v8 없음 |
| `FirebaseExtended/action-hosting-deploy` | `@v0` | v1 없음, 런타임 node24, Apache-2.0 (action.yml 머리말), 입력 `channelId`·`expires`·`entryPoint`·`firebaseToolsVersion`·`disableComment` 확인 |
| `firebase-tools` | 15.34.2 | npm 최신, Node >=20 |
| Chrome (브라우저 테스트) | — | 컨테이너: `/usr/bin/google-chrome`(Chrome for Testing 153.0.8010.12), `CHROME_EXECUTABLE` 없이 동작 (확인함). GitHub ubuntu 러너 기본 설치 (미확인) |
| 커밋 SHA 고정 | — | github.com 태그 목록 접근 불가로 메이저 태그 사용. 구현 시 가능하면 SHA 고정 |

---

## 8. 작업 분해

순서대로 진행. 각 작업의 "완료 조건"은 컨테이너에서 실행 가능한 명령/테스트다. `ws` = `dart run tool/ws.dart`.

### 8.1 기반 단계 (동시 개발 전, main에 커밋 — 계약 7.6)

INFRA는 **B1**과 **B8**을 맡는다. B2(CORE: 계약 타입·동작 구현·`createFakeNoteStore()`) → B3(INK) / B6(LIBRARY) / B7(SYNC) → B4(PDF) / B5(EDITOR)(`ink_engine`을 쓰므로 B3 뒤)는 각 영역이 자기 경로만 커밋한다. 계약 7.6 v1.2(C12-08): 각 영역은 CORE T4 커밋 뒤 자기 작업 트리에서 미리 작성할 수 있지만 B3~B7의 main 커밋·완료 조건은 B2 완료(T1~T5) 뒤다. 단계마다 `ws check`(B1부터 R15 포함)·`flutter analyze --fatal-infos`·`ws test`가 통과해야 다음 단계로 간다. B8은 B2~B7이 모두 main에 들어간 뒤다.

| ID | 작업 | 완료 조건 |
|---|---|---|
| B1-1 | 루트 `pubspec.yaml`(3.2), `analysis_options.yaml`(6.2 — exclude에 `tool/test/fixtures/**` 포함), `.gitignore`·`.gitattributes`(3.1) | 루트 `flutter pub get` 성공, `pubspec.lock` 생성 |
| B1-2 | 패키지 6개 골격(3.3): `pubspec.yaml`(**계약 7.5의 모든 외부 의존**, `note_core`는 순수 Dart), `README.md`, `lib/<name>.dart`(빈 barrel), `test/<name>_smoke_test.dart` | 각 멤버 디렉터리 `flutter test` 통과 |
| B1-3 | `flutter create --platforms=web,android,ios --org dev.noteapp --project-name noteapp app` → `app/analysis_options.yaml`·`test/widget_test.dart` 삭제, pubspec 교체(3.3 — `sync_engine` 없음), 최소 `main.dart`(자리표시 문구) | `cd app && flutter build web` 성공 |
| B1-4 | `tool/ws.dart` 최소: `list`, `test`(vm/chrome, `--package`, **chrome 전 `tool/prepare_web_test.dart` 선실행**, Chrome 찾기), `check`(R1–R3·R7–R9·**R15** — 계약 7.6 B1 v1.2, C12-01) + **`tool/src/test_tags.dart`**(R15 리터럴 태그 스캐너 + `dart_test.yaml` 확인, 6.2) + `tool/workspace_rules.yaml`(4.3 전체 — `pinned_external` 7.5 전부, `lib_exceptions`, `pure_dart_members`, **`skip_by_default_tags: [integration, perf]`**) + `tool/test/`(**`test_tags_test.dart`** 포함 — 9.1 행 그대로) | `dart test tool/test` 통과(**`test_tags_test.dart`** 포함), `ws check` 0(R15 포함 — B1 시점에 태그를 쓰는 테스트 없음). 이후 각 영역 브랜치의 `ws check`가 태그 선언·`integration`·`perf` `skip` 누락을 위반(종료 1)으로 잡는다 |
| B1-5 | 최소 `ci.yml`: 6.13의 1·2·5–9·14단계(배포 없음) | `tool/test/workflows_test.dart`(YAML 파싱·`timeout-minutes`·`flutter-version-file`) 통과 |
| B1 완료 | | `flutter pub get --enforce-lockfile`, `ws check`(R1–R3·R7–R9·R15), `ws test`, `dart test tool/test`(계약 7.6 B1·B8 v1.3) → 커밋 |
| B8-1 | `app/lib/**`·`app/test/**`: 최소 go_router(`/`, `/folders/:folderId`, `/notes/:noteId`, `/settings`) + B6 `LibraryScreen`·B5 `EditorScreen` 자리표시 연결 + 셸 설정 자리표시. `main.dart`는 `openNoteStore(const NoteStoreConfig())`를 시도하고, 실패(B2의 `UnimplementedError` 포함)하면 안내 문구만 표시(전체 부트스트랩은 I5). **비고**(INFRA-3-4): 이 `openNoteStore(const NoteStoreConfig())`(정적 파일 경로가 기본 상대 경로 `'sqlite3.wasm'`·`'drift_worker.js'`)는 **임시 진입점**이다 — 배포 없음(B1·B8 CI는 배포하지 않음, 6.13)이라 깊은 경로 새로고침 문제(계약 7.4.3)가 사용자에게 닿지 않는다. I5에서 `runNoteApp`·`CoreModule`의 `defaultNoteStoreConfig`(`document.baseURI` 기준 절대 URL, 계약 7.2.12·7.4.3)로 교체한다 | `app/test/foundation_routing_test.dart`: `noteStoreProvider` ← `createFakeNoteStore()` → `LibraryScreen` 표시 → 그 위젯의 `onOpenNote('n1')` → `/notes/n1`에 `EditorScreen(noteId: 'n1')` → `onClose()` → `LibraryScreen` (자리표시 본문 문구에 의존하지 않음) |
| B8-2 | 전체 확인 | `ws check` 0, `flutter analyze --fatal-infos` 0, `ws test`, `ws test --platform chrome`, `dart test tool/test`(계약 7.6 B1·B8 v1.3), `cd app && flutter build web --release` 성공 → 커밋 |
| B8-3 | **실측**(INFRA-S2): 체크포인트 푸시로 첫 CI 1회 실행 → 단계별 시간, `main.dart.js` 크기, (CORE가 구현돼 있으면) Chrome 첫 `openNoteStore` 시간 | 6.13 예산표·실측표 갱신, 값은 결과 보고에 |

### 8.2 동시 개발 단계 (INFRA worktree, 브랜치 `area/infra`)

| ID | 작업 | 선행 | 완료 조건 (통과해야 할 테스트) |
|---|---|---|---|
| I1 | `tool/ws.dart` 완성: R1–R13(4.3·6.2 — R2 순수 Dart, R4 `lib_exceptions`(디렉터리 항목 포함)·`native_only_imports`·test-only 진입점(`package:` URI 기준, 같은 패키지 `lib/testing*.dart`끼리 상대 허용), R5 `test/web` 제외, R6 `lib/`만, R7 `src/` 금지, R9 전체 고정·R9w·`--strict`, R11 생성 파일·픽스처 제외). **R15 태그 선언은 B1-4에서 완료**(계약 7.6 B1 v1.2, C12-01 — I1은 새로 만들지 않고 회귀만 확인), `test` 옵션(`--affected-since`, `-t`, `-x`(기본 `bench`), `--run-skipped`, `--reporter`), `affected`, `channel-id`, `build-info`, `finalize-web`, `web-assets`(**`package:crypto` 3.0.8** sha256), `hosting-config`, flutter·Chrome 실행 파일 찾기 | B1 | `tool/test/rules_test.dart`, `test_tags_test.dart`(B1-4에서 완료 — 회귀), `test_command_test.dart`, `affected_test.dart`, `channel_id_test.dart`, `build_info_file_test.dart`, `web_finalize_test.dart`, `web_assets_test.dart`, `dart_imports_test.dart`, `flutter_runner_test.dart` |
| I2 | `BuildInfo`, `RuntimeInfo` | — | `app/test/build/build_info_test.dart`, `runtime_info_test.dart` |
| I3 | 오류 처리: `AppErrorLog`, `installGlobalErrorHandlers`, `appErrorWidgetBuilder`, `AppProviderObserver`, `DiagnosticReport`(CORE `StorageInfo`·`PersistenceStatus`) | I2 | `test/errors/app_error_log_test.dart`, `error_handlers_test.dart`, `diagnostic_report_test.dart`, `app_provider_observer_test.dart` |
| I4 | `WebPlatform` (스텁·브라우저 구현: `resolveAppUrl`, `fetchTextNoStore`, `downloadBytes`, **`canShareFiles`·`shareFile`**, `visibilityChanges`, `reload`, standalone, 내비게이션 시각 — **persist·estimate 없음**) + `FakeWebPlatform` | — | `test/web/web_platform_browser_test.dart` (Chrome), VM: `test/build/runtime_info_test.dart`가 스텁 사용 |
| I5 | 부트스트랩: `AppModule`(+`resetLocalData`·`canResetAfter`·**`onStartAbandoned`**), `StaticOverridesModule`, `AppModuleContext`(+`web`·`outcomeOf`·`isStarted`), `AppBootstrapper`(시간 초과 → `onStartAbandoned`, `shutdown`이 그 정리를 최대 2초 기다림), `StartupReport`(+`storage`), `BootstrapApp`, `SplashView`, `StartupErrorScreen`(+새로고침·데이터 지우기), `runNoteApp` | I2–I4 | `test/bootstrap/app_bootstrapper_test.dart`, `overrides_unique_test.dart`, `bootstrap_app_test.dart`, `startup_error_screen_test.dart` |
| I6 | 라우팅: `AppRoutes`(+`libraryPageKey`), `AppNavigator`, `AppScreenBuilders`, `createAppRouter`(무전환 페이지·공용 키), `NotFoundScreen` | B8 | `test/routing/app_routes_test.dart`, `app_router_test.dart` |
| I7 | `NoteApp`(브리지 없음), `buildAppTheme`, `AppStrings`(해요체), `AppLifecycleBridge`(hide·pause·detach + 웹 hidden), 셸 provider(`name:`) | I5, I6 | `test/app/note_app_test.dart`, `lifecycle_bridge_test.dart` |
| I8 | `UpdateChecker`, `UpdateBanner` | I7 | `test/update/update_checker_test.dart`, `update_banner_test.dart` |
| I9 | 설정 화면 틀 + `defaultSettingsSections()`(EDITOR 4종 · LIBRARY · INFRA 2종) + `StorageSection`(CORE `StorageInfo`·`PersistenceStatus`, `latestStorageInfoProvider` → `ref.invalidate(storageInfoProvider)`) + `AboutSection`(빌드 라벨 · 렌더러 · 홈 화면 앱 여부 · 시작 시간 · 오류 목록 · 진단 복사 · 새 버전 확인 · **백업 내보내기** · 라이선스 — PDF 12.2 Q1 답) + `prepareBackup`·`deliverBackup`·`BackupReadySheet` | I4, I7, I8 | `test/settings/settings_screen_test.dart`, `settings_sections_test.dart`, `storage_section_test.dart`, `about_section_test.dart`, `backup_export_test.dart` |
| I10 | 모듈 어댑터: `CoreModule`(계약 7.2.12: `openNoteStore`/`NoteStoreOpenException`/`deleteLocalNoteData`, 절대 URL 설정, 상태 오류 기록, **시간 초과 뒤 늦게 열린 저장소 즉시 close**), `PdfModule`, `productionModules()` | I5 | `test/modules/core_module_test.dart`, `pdf_module_test.dart`, `production_modules_test.dart` |
| **I10b** | **`FeatureWiringModule` + `pdf_wiring.dart`**: 계약 7.3.3 '이번' 행 중 `FeatureWiringModule` 몫 전부(썸네일 렌더러, PDF 가져오기·내보내기 자리, `EditorExtensions` 변환, PDF 렌더 통계 `DevOverlaySection`), PDF 시작 실패 시 PDF 관련 생략 | I10 | `test/modules/feature_wiring_module_test.dart`, `pdf_wiring_test.dart` |
| I11 | 웹 파일: `index.html`(contextmenu 가드 포함), `flutter_bootstrap.js`, `manifest.json`, `tool/gen_icons.dart` + 아이콘 생성 | — | `tool/test/web_files_test.dart`, `ws check`(R13), `test/web/app_boot_browser_test.dart` (Chrome에서 `BootstrapApp` + 가짜 모듈 → 라이브러리 자리표시 표시), `cd app && flutter build web` 결과의 `flutter_bootstrap.js`에 `serviceWorkerSettings` 없음 (`web_finalize_test`가 검사) |
| I12 | `app/firebase.json`(`.wasm` 헤더, COOP/COEP 없음), `tool/web_assets.yaml`(2개) + `web-assets fetch` + `app/web/sqlite3.wasm`·`drift_worker.js` 커밋, `app/tool/prepare_web_test.dart`, `app/dart_test.yaml`(계약 7.4.8 v1.1: `tags:` 아래 `integration: {skip: "integration stage only — ws test --run-skipped -t integration"}` — 앱이 쓰는 태그는 이것뿐. 계약 7.4.8 v1.2: 앱에서 태그를 쓰는 첫 테스트(`app_smoke_test`·`app_smoke_browser_test`, 리터럴 `@Tags(['integration'])`)보다 먼저 만든다 — 그 두 파일은 이 작업 뒤에만 추가), `app/.gitignore` | I1 | `tool/test/hosting_config_test.dart`, `web_assets_test.dart`, `ws check`(R12·R15), `ws web-assets verify`, 기본 `ws test`에서 `app/test/integration/`·`app_smoke_browser_test`가 '건너뜀'으로 집계됨 |
| I13 | 워크플로 4종 완성(캐시 2종, 브라우저 테스트, 통합 입력) + 이슈 템플릿 | I1, I12 | `tool/test/workflows_test.dart` (6.13 표의 트리거·동시성·시간 제한·캐시 키·게이트·고정 버전·시크릿 조건 검사) |
| I14 | `docs/guides/` 7개 파일 (6.16 — 미리보기 데이터·로그인 분리, Firebase 위치 권장·`authDomain`, 백업 내보내기, 홈 화면 앱 권장) | I13 | `tool/test/guides_test.dart` (파일 존재, 상대 링크 대상 존재, 필수 제목: '준비물' · '확인 방법' · '문제 해결', 04에 '미리보기'·'백업' 문구) |
| I15 | 동시 개발 마감 확인 | 전부 | 8.2 전체 테스트 + `ws check` + `ws analyze` + `ws test` + `ws test --platform chrome` + `flutter build web` |

### 8.3 통합 단계 (계약 7.7 — INFRA는 CORE·INK·피처 4개 병합 뒤 4번째 순서)

| ID | 작업 | 완료 조건 |
|---|---|---|
| G1 | 병합 후 `pubspec.lock` 재생성(6.1 정책), 영역 결과 보고의 '의존성 추가'를 `pinned_external`에 반영(총괄이 계약 7.5 갱신) | `flutter pub get --enforce-lockfile`, `ws check --strict` 0 (V1 일부) |
| G2 | `AppScreenBuilders.production()`·`CoreModule`·`PdfModule`·`FeatureWiringModule`을 실제 구현에 연결(계약 7.7 4단계). **통합 스모크 V5** `app/test/integration/app_smoke_test.dart`(`@Tags(['integration'])`) — 아래 'V5 스모크 단계'. **V6** 같은 시나리오를 `app/test/web/app_smoke_browser_test.dart`(`@TestOn('browser')`, `@Tags(['integration'])`)로 Chrome에서: 실제 CORE 웹 저장, `app/tool/prepare_web_test.dart`가 복사한 두 파일 사용, 테스트마다 다른 `databaseName`과 `WebStorageConfig.blobDatabaseName`(INFRA-3-5 — `NoteStoreConfig`에 `copyWith`가 없으므로 아래 'V6 설정'처럼 직접 생성), 끝에 **`bootstrapper.shutdown()`(= `store.close()`)을 기다린 뒤 `deleteLocalNoteData(config)`**(INFRA-2-10 — 열린 저장소가 있으면 `StateError`, CORE 6.18). Chrome 첫 `openNoteStore` 시간 기록(B8에서 못 쟀으면). 계약 7.7 5단계의 다른 영역 통합 태그 테스트(LIBRARY L21, PDF `integration`, SYNC T16, EDITOR E-21)도 같은 명령으로 함께 돈다 | `ws test --run-skipped -t integration`, `ws test --platform chrome --run-skipped -t integration` 통과 (V3·V5·V6) |
| G3 | **R14**: 루트 dev `analyzer: 13.3.0` + `pinned_external` 추가, `tool/src/export_names.dart`, `ws check`에 R14 포함 | `tool/test/export_names_test.dart`, `ws check`(R1–R15) 0 (V1) |
| G4 | 최종 확인: 루트 `flutter analyze --fatal-infos` 0, `dart format` 변경 없음(**R11 기준** — `app`·`packages`·`tool`의 `*.dart`에서 `generated_files`·`fixture_dirs` 제외, INFRA-2-13), `ws test`·`ws test --platform chrome`·`dart test tool/test`, `cd app && flutter build web --release`, `ws web-assets verify` | V2·V3·V4 |
| G5 | 브랜치 푸시 → CI 녹색 → 미리보기 배포(`curl -I`로 `.wasm` MIME·`Cache-Control` 확인) → 사용자 iPad 체크리스트(9.3 + 계약 V7 복합 항목) | 사용자 확인 결과를 PLAN.md 체크리스트에 반영 (총괄) |

V5 스모크 단계 (계약 7.7 V5 + 7.4.5 v1.1 배너 대조, INFRA-2-7 — C11-12·24·30):

1. 실제 모듈로 부트스트랩: `CoreModule(configFor: (_) => const NoteStoreConfig(inMemory: true))`, 실제 `PdfModule()`·`FeatureWiringModule()`, `AppScreenBuilders.production()`. 화면 크기 1032×1376(DPR 2). 부트스트랩 결과의 overrides가 계약 7.3.3 '이번' 행 전부이고 `Override.origin` 기준 중복 없음.
2. 메모리 CORE 전제 확인: `container.read(storageInfoProvider).backend == StorageBackend.nativeMemory`, `storageWarningOf(info, store.persistenceStatus) == StorageWarning.notDurable`(계약 7.2.12 v1.1 `NoteStoreConfig` 주석 — `inMemory`는 `nativeMemory` → `isDurable == false`).
3. **라이브러리 배너 대조**: `LibraryScreen`이 뜬 첫 화면에서, LIBRARY 배너의 [닫기]를 누르기 **전에** `find.text(ContractStrings.storageNotDurable)` → `findsOneWidget`. `ContractStrings`(`app/test/support/contract_strings.dart`)는 계약 7.4.5 v1.1 고정 문장을 글자 그대로 담는다: `storageNotDurable` = "이 브라우저에서는 노트가 임시로만 저장돼요. 테스트 용도로만 사용하세요.", `storageWriteFailing` = "저장에 계속 실패하고 있어요. 브라우저 저장 공간을 확인해 주세요."(V5에서는 실패를 만들 수 없어 `writeFailing`은 각 영역의 문구 상수 테스트가 맡는다 — 계약 7.4.5). 배너는 닫지 않는다(닫기 동작은 LIBRARY 자체 테스트 몫).
4. 새 노트: LIBRARY의 '새 노트' 흐름(라벨 텍스트로 찾음) → `EditorScreen` 표시.
5. **에디터 배너 대조**: `find.text(ContractStrings.storageNotDurable)` → `findsOneWidget`(라이브러리 라우트는 에디터 아래에 남아 있어도 `Offstage`라 기본 finder에 잡히지 않음 — `skipOffstage: true`). 두 화면이 같은 문장을 보인다는 대조가 이것으로 끝난다(계약 7.4.5 '두 화면 대조는 INFRA V5').
6. 합성 스타일러스 포인터로 획 1개: 시작·끝 좌표는 **`tester.getRect(find.byType(InkPageView).first)`에서 계산**(페이지 영역 중앙 근처, 폭의 ±20%) — 고정 좌표를 쓰지 않으므로 배너 높이(최소 48, 줄 수에 따라 다름)·툴바 높이가 바뀌어도 같은 위치에 닿는다. 이후 단계의 모든 탭도 finder로 찾은 위젯을 누르고 위치를 가정하지 않는다.
7. EDITOR 닫기(뒤로 버튼 → flush 뒤 `onClose`) → 라이브러리 → 같은 노트 다시 열기(노트 타일을 제목 텍스트로 찾음) → 획 1개 유지: `await store.flush()` 뒤 `store.content.pagesOf(noteId)` 첫 페이지의 `store.content.loadPage(pageId)`가 `strokes.length == 1`(CORE `NoteContentReader`, 계약 7.2.9 — 화면 구조에 기대지 않음).
8. 되돌리기(EDITOR 툴바 되돌리기 버튼) → 같은 방법으로 `strokes.length == 0`(빈 페이지).

**통합 단계 G2 실행 순서(계획과 다른 점)**: 8을 7보다 먼저 한다 — 6(획 1개) → 8(되돌리기 → 빈 페이지, 다시 실행 → 같은 획 id 1개) → 7(닫기 → 다시 열기 → 같은 획 1개 유지, 새 세션의 되돌리기 버튼 비활성). CORE `noteSessionProvider`는 autoDispose라 에디터를 떠나면 세션이 닫히고 히스토리도 닫힌다(02-core 6.16 '재진입 시 빈 히스토리', 승인된 설계) — 다시 연 뒤에는 앞 세션의 획을 되돌릴 수 없어 위 7 → 8 순서는 성립하지 않는다(G2에서 실제 CORE로 확인: 다시 연 뒤 되돌리기 버튼 비활성). 끝 상태(획 1개·빈 페이지·다시 열어 유지)는 모두 단언한다. 계약 7.7 V5 문구 정리는 총괄에 변경 요청. 버튼은 접근성 라벨(`뒤로`·`되돌리기`·`다시 실행` — EDITOR 툴바 아이콘의 `semanticLabel`), 라이브러리는 보이는 문구(`새 노트`·`만들기`·`제목 없는 노트`)로 찾는다(`app/test/support/smoke_scenario.dart`의 `SmokeLabels`).
9. 정리: `bootstrapper.shutdown()`.

V6(Chrome)는 1·4·6~9를 같게 하고, 2·3·5의 배너 단언은 실제 웹 백엔드에 맞춘다: `w = storageWarningOf(storageInfoProvider 값, store.persistenceStatus)`가 `notDurable`이면 두 화면 모두 `ContractStrings.storageNotDurable` 1개, `null`이면 두 문장 모두 0개(헤드리스 Chrome의 웹 백엔드가 무엇일지는 미확인이라 결과에 맞춰 단언). 1의 설정은 아래 'V6 설정', 9 뒤에 `deleteLocalNoteData(config)`(shutdown이 `store.close()`를 끝낸 뒤 — INFRA-2-10).

V6 설정 (INFRA-3-5): 테스트마다 SQLite DB 이름과 blob IndexedDB 이름(CORE 기본 `'noteapp_blobs'`, 02-core 4.8)을 **둘 다** 다르게 준다 — 하나라도 같으면 앞 테스트(또는 정리 실패한 이전 실행)의 에셋·썸네일이 남아 보인다. CORE `NoteStoreConfig`·`WebStorageConfig`에는 `copyWith`가 없으므로 `defaultNoteStoreConfig`를 고쳐 쓰지 않고 테스트가 직접 만든다(필드 이름은 02-core 4.8 생성자 그대로, 나머지 필드는 CORE 기본값):

```dart
// app/test/web/app_smoke_browser_test.dart — one config per test (n = test index + run id)
NoteStoreConfig smokeConfigFor(AppModuleContext context, String n) =>
    NoteStoreConfig(
      databaseName: 'noteapp_smoke_$n',
      ownerId: context.ownerId,
      web: WebStorageConfig(
        // Absolute URLs as in production (resolveAppUrl = document.baseURI).
        // If the test page's baseURI does not reach test/web/ (unverified),
        // the relative defaults are allowed here — tests only (계약 7.4.3).
        sqlite3WasmPath: context.web.resolveAppUrl('sqlite3.wasm'),
        driftWorkerPath: context.web.resolveAppUrl('drift_worker.js'),
        blobDatabaseName: 'noteapp_smoke_${n}_blobs',
      ),
    );
// late NoteStoreConfig config;
// CoreModule(configFor: (ctx) => config = smokeConfigFor(ctx, n));
// after `await bootstrapper.shutdown()`: `await deleteLocalNoteData(config)`
// drops both databases (SQLite DB + blob IndexedDB).
```

---

## 9. 테스트 계획

### 9.1 컨테이너 자동 테스트

명령: `ws check` · `ws analyze` · `ws test` · `ws test --platform chrome` · `dart test tool/test` (루트) · `cd app && flutter build web --release`. 통합 단계: `ws test --run-skipped -t integration`(VM·Chrome).

공통: 위젯 테스트 화면은 iPad Pro 13" 세로 논리 1032×1376(DPR 2, `tester.view.physicalSize = Size(2064, 2752)`)을 기본으로 하고 가로 1376×1032도 설정 화면에서 한 번 확인(계약 7.4.8). 시간은 `fake_async`·`tester.pump`만, 네트워크 없음(`web_assets_test`의 fetch는 로컬 HTTP 서버).

| 파일 | 주요 경우 |
|---|---|
| `tool/test/dart_imports_test.dart` | 단일 줄·여러 줄 import, 조건부 절 2개(`dart.library.js_interop`·`dart.library.ffi`), 주석 처리된 import 무시, `export` 포함 |
| `tool/test/rules_test.dart` | 픽스처별 R1–R13 위반 각각 1건 검출 + 정상 픽스처 0건. 추가 경우: **R2** 순수 Dart 멤버에 `flutter: sdk` 의존 → 위반, `environment.flutter` 누락 → 위반, `package:flutter_test` import → 위반 · **R4** `lib/a.dart`의 `dart:io` → 위반, `lib/a_native.dart` 허용, `packages/note_core/lib/testing_vm.dart`의 `dart:io`·`package:drift/native.dart` → 허용(`lib_exceptions`), `lib/`에서 `package:note_core/testing.dart` → 위반 · **R4 native_only**(INFRA-2-12): `pdf_io/lib/src/compose/compose_backend.dart`의 `package:pdfium_dart/pdfium_dart.dart` → 위반 1, 같은 import가 `compose_backend_native.dart`에 있으면 허용 1 · **R4 test-only**: `note_core/lib/src/a.dart`의 `package:note_core/testing.dart` → 위반 1, `note_core/lib/testing_vm.dart`의 `import 'testing.dart'`(같은 패키지 상대) → 허용 1, `note_core/lib/src/a.dart`의 `import '../testing.dart'` → 위반, 디렉터리 항목 `lib_exceptions: [packages/x/example/lib/]` 아래 파일의 `package:note_core/testing.dart` → 허용 · **R5** `test/web/x_test.dart`의 `package:web` 허용, `test/unit/x_test.dart`면 위반 · **R6** `lib/`의 `_native.dart` 무조건 import → 위반, `test/`에서는 허용 · **R7** test의 `material.dart` → 위반, `ink_engine/lib`의 `package:note_core/src/x.dart` → 위반 · **R8** `feature_library → feature_editor` → 위반, `noteapp → sync_engine` → 위반(이번 범위), `path:` → 위반 · **R9** `^1.0.0` → 위반, `riverpod: 3.4.2` → 고정값 불일치, 표에 없는 `foo: 1.0.0` → R9w(종료 0), `--strict`면 종료 1 · **R11** 포맷 안 된 `*.g.dart`·`fixture_dirs`(`tool/test/fixtures/`) 아래 파일은 보고하지 않음 · `pinned_external`이 계약 7.5 표의 행 수·값과 같음(표를 픽스처로 둔 스냅숏) |
| `tool/test/test_tags_test.dart` (R15, **B1-4** — 계약 7.6 B1 v1.2) | 픽스처: `@Tags(['integration'])` + `dart_test.yaml` 없음 → 위반 · 선언은 있으나 `skip` 없음 → 위반 · `integration: {skip: "..."}` → 0건 · `perf`도 같게 · `golden`은 선언만 있으면 0건, 선언 없으면 위반 · `testWidgets('x', tags: ['golden'], ...)`·`tags: 'golden'` 인식 · 주석 처리된 `@Tags` 무시 · 태그를 안 쓰는 멤버는 `dart_test.yaml`이 없어도 0건 · 같은 멤버의 여러 파일 태그를 합쳐 한 번만 보고 · 변수로 넘긴 태그(`const kTags = ['integration']; … tags: kTags`)는 인식하지 않음(0건 — 계약 7.4.8 v1.2 '리터럴만 인식' 제약을 고정하는 경우) · 위반이 있으면 `ws check` 종료 코드 1 |
| `tool/test/test_command_test.dart` | 가짜 프로세스 실행기로: vm은 `test/web/` 밖 파일만 넘김 · chrome은 `test/web/`가 있는 멤버만 · `tool/prepare_web_test.dart`가 있으면 **먼저** 멤버 디렉터리에서 실행, 없으면 실행 안 함 · 준비 실패 → 그 멤버 '준비 실패'·테스트 건너뜀·전체 종료 1 · `--run-skipped -t integration` 전달 · 기본 `-x bench` · `CHROME_EXECUTABLE` 있으면 그대로 환경에 전달, 없고 `PATH`에도 없으면 종료 3 · `--affected-since` 필터 · 요약 표 |
| `tool/test/affected_test.dart` | `packages/note_core/lib/x.dart` 변경 → note_core + 의존 멤버 5개(ink_engine·feature_editor·feature_library·pdf_io·sync_engine) + noteapp, `packages/feature_library/…` → feature_library, noteapp, `pubspec.lock` → 전체, `docs/a.md` → 없음, 위상 순서 |
| `tool/test/channel_id_test.dart` | 예시 브랜치 → 기대값, `area/infra` 예, 길이 ≤ 21, `[a-z0-9-]`만, 같은 입력 같은 결과, 대소문자만 다른 브랜치 → 다른 hash, 빈 slug 처리 |
| `tool/test/build_info_file_test.dart` | 환경 변수 있음/없음, 값 모두 문자열, `--channel` 검증, sha 40자 |
| `tool/test/web_finalize_test.dart` | 가짜 build 디렉터리: info 복사, preview면 manifest 이름 변경·live면 유지, 필수 파일 누락 시 1, `flutter_bootstrap.js`에 `serviceWorkerSettings` 있으면 실패, `main.dart.js` 크기 줄 출력 |
| `tool/test/web_assets_test.dart` | 계약 7.4.9 두 항목(경로·크기·sha256) 파싱, 파일 없음/크기 불일치/sha 불일치 실패(sha256은 `package:crypto` — 외부 프로세스 호출 없음), fetch는 로컬 HTTP 서버로(sha 일치할 때만 기록) |
| `tool/test/web_files_test.dart` | `manifest.json` 필수 필드·아이콘 경로 존재, `index.html` 필수 메타·CSS 속성·`flutter-first-frame`·`gesturestart`·viewport 덮어쓰기 문자열·`contextmenu` 가드(입력 요소 예외 포함)·`<base href`·`lang="ko"`·CSP 메타 없음, `flutter_bootstrap.js` 토큰 2개·`unregister`·`wasmAllowList` |
| `tool/test/hosting_config_test.dart` | `firebase.json` JSON 유효, `public`, 재작성, `no-cache`, `**/*.wasm` → `application/wasm`, 기본 설정에 COOP/COEP **없음**, `--isolate` 결과에 COOP/COEP, M4 픽스처의 `firestore.rules`·`firestore.indexes`·`storage.rules` 경로가 `app/` 기준으로 존재(없는 경로 → 실패) |
| `tool/test/workflows_test.dart` | 모든 잡 `timeout-minutes`, ci 동시성, `flutter-version-file: pubspec.yaml`, `actions/cache@v6` 2개(키에 `hashFiles('pubspec.lock'`), 브라우저 테스트 단계, 통합 단계는 `inputs.integration` 조건, main은 `check --strict`, 배포 단계 `if`에 시크릿 조건, `firebaseToolsVersion` 고정, iOS 잡 변수 게이트, android `retention-days` |
| `tool/test/guides_test.dart` | 6.16 파일 존재, 상대 링크 유효, 필수 소제목, 04에 미리보기 데이터 분리·백업 내보내기 문구, 01에 위치 권장(미확인 표시) 문구 |
| `tool/test/flutter_runner_test.dart` | flutter 찾기 순서 4단계, Chrome 찾기(`CHROME_EXECUTABLE` → `PATH` 이름 4개) |
| `tool/test/export_names_test.dart` (G3) | 픽스처 패키지 3개: 겹친 공개 이름 1개만 보고, `show`/`hide`·private 반영, 같은 패키지의 진입점끼리는 비교 안 함, 해석 실패 시 종료 3 |
| `app/test/build/build_info_test.dart` | defines 없음 → `local`, JSON 왕복, 잘못된 숫자 → 0, `displayLabel`·`shortSha` |
| `app/test/build/runtime_info_test.dart` | 가짜 웹 플랫폼으로 standalone·userAgent, VM에서 `notWeb` |
| `app/test/errors/app_error_log_test.dart` | 용량 초과 시 오래된 것 삭제, `totalCount`, `notifyListeners` |
| `app/test/errors/error_handlers_test.dart` | `FlutterError.reportError` → 기록, `PlatformDispatcher.onError` → 기록·true, 복원 콜백 |
| `app/test/errors/diagnostic_report_test.dart` | 고정 시각으로 텍스트 스냅샷(6.7 예시 형식), CORE `StorageInfo`·`PersistenceStatus` 값 → 저장소·저장 상태 줄, null → '알 수 없음', 8,000자 자르기, 오류 5건·스택 15줄 제한 |
| `app/test/bootstrap/app_bootstrapper_test.dart` (fake_async) | 순서대로 시작, 단계 라벨 변화, `recordOutcome`·`isStarted`, critical 실패 → 역순 stop + Failure(`canResetAfter`가 참일 때만 `resetLocalData`), non-critical 실패 → Success + 기록 + 그 모듈 overrides 제외 + 뒤 모듈에서 `isStarted == false`, 시간 초과 → `timedOut` + 그 모듈의 `onStartAbandoned` 1회(`FakeAppModule.abandonedCalls`), `shutdown()`은 `abandonDelay` 1초면 그 완료를 기다리고 5초면 2초 뒤 진행 + `errorLog` 1건, 3초 초과 → `isSlow`, `run()` 두 번 → 같은 Future, `notifyAppHidden` 500ms 제한, `StartupReport.storage` = 공개된 `NoteStore.storageInfo`, **`persist` 관련 호출 없음** |
| `app/test/bootstrap/overrides_unique_test.dart` | 가짜를 넣은 실제 모듈 3개(`CoreModule(open: fakeOpenNoteStore(store: CountingNoteStore()))`, `PdfModule(initialize: …, pdfOverrides: …)`, `FeatureWiringModule(가짜 PDF 동작)`)로 부트스트랩 → `overrides`의 `Override.origin`이 모두 다름, `ProviderContainer.test(overrides:)` 생성 시 assert 없음. 일부러 같은 provider를 두 모듈에 넣으면 이 검사가 실패함을 확인 |
| `app/test/bootstrap/bootstrap_app_test.dart` | 스플래시 → 앱, 실패 → 오류 화면 → 다시 시도 → 성공 (새 bootstrapper 생성 확인), 초기화 가능 실패 → 대화상자 2단계 → `RecordingLocalDataEraser` 호출 → 자동 다시 시도, **CORE 시간 초과 → 오류 화면 → 늦게 열린 저장소 → 다시 시도: 새 `open` 호출(`openCount == 2`)이 늦은 저장소의 `closeCount == 1` 이후**(fake_async) |
| `app/test/bootstrap/startup_error_screen_test.dart` | `NoteStoreOpenFailure` 5종 + 시간 초과 + 그 외 문구(6.7 표), 새로고침 버튼은 `newerSchema`(웹)만, 데이터 지우기 버튼은 콜백이 있을 때만·2단계 확인, 진단 복사(Clipboard 모의) |
| `app/test/routing/app_routes_test.dart` | 인코딩, `?page=`, `libraryPageKey` |
| `app/test/routing/app_router_test.dart` (placeholders) | `/` · `/folders/f1` · `/notes/n1?page=p3` 인자, 없는 경로 → NotFound → 홈, openNote → 닫기 시 이전 폴더, 새로고침 시나리오(초기 위치 `/notes/n1`) 닫기 → `/`. **페이지 종류**: `/`·`/folders/:id`는 `NoTransitionPage`이고 key == `AppRoutes.libraryPageKey`, `/notes/:id`는 `NoTransitionPage`. **폴더 이동 시 `LibraryScreen` State 유지**: `/` → `/folders/a` → `/folders/b` → `/` 동안 라이브러리 자리표시 `initState` 1회, push `/notes/n1` → pop 뒤에도 1회 |
| `app/test/app/note_app_test.dart` | material_ui `MaterialApp` 존재, locale ko, 테마 seed, `builder`가 `UpdateBanner`로 감쌈, **`MaterialUiCompatibilityBridge`가 없음**(`find.byType(...)`, 이 한 줄만 `// ignore: deprecated_member_use` + 사유) |
| `app/test/app/lifecycle_bridge_test.dart` | `AppLifecycleState.hidden`·`paused`·`detached` · 웹 hidden 이벤트 → `notifyAppHidden` 1회, 1초 안 반복 무시 |
| `app/test/update/update_checker_test.dart` (fake_async) | local 빌드 → Disabled, 같은 sha → UpToDate, 다른 sha → Available, 5초 초기 지연, 10분 주기, hidden 동안 주기 확인 안 함, visible 60초 규칙, 실패 시 상태 유지, dismiss 후 같은 sha 무시·새 sha 표시, applyUpdate → flush 후 reload |
| `app/test/update/update_banner_test.dart` | Available일 때만 배너, 버튼 동작, 문구 해요체 |
| `app/test/settings/settings_screen_test.dart` | provider 목록 순서대로 머리글 + 섹션, `group` '일반' 머리글 한 번, 닫기 → `onClose`, 가로·세로 크기에서 넘침 없음 |
| `app/test/settings/settings_sections_test.dart` | `defaultSettingsSections()` id 순서 == `app.storage, editor.input, editor.pen, editor.page, library.newNote, editor.developer, app.about`, 각 builder가 계약 위젯 타입(`EditorInputSettingsSection` … `LibrarySettingsSection`, `StorageSection`, `AboutSection`)을 만듦, M4 전 `app.account` 없음 |
| `app/test/settings/storage_section_test.dart` | `createFakeNoteStore()` 기반 `CountingNoteStore`로 backend·영구 보관·사용량 표시, '다시 확인' → `refreshStorageInfo` 재호출(`refreshCount`), `consecutiveFailures ≥ 3` 문구, 로딩 중에는 `storageInfoProvider` 값, 첫 프레임부터 저장 상태 줄 표시(`persistenceStatusStream` 첫 값 — 계약 7.2.12 v1.1). **'다시 확인' 후 `storageInfoProvider` 값 갱신**(INFRA-2-5): `refreshResult = StorageInfo(backend: webSharedIndexedDb, persistGranted: true)`를 주고 '다시 확인' → 같은 트리의 별도 `Consumer`가 `ref.watch(storageInfoProvider).persistGranted == true`로 다시 그려짐, `ProviderContainer`의 `storageInfoProvider` 값도 같음 · 섹션을 닫는 중(`await` 사이 dispose)에 끝나도 예외 없음 |
| `app/test/settings/about_section_test.dart` | 표시 값, 진단 복사, 라이선스 페이지 열림, 백업 버튼 → `prepareBackup`(진행 중 버튼 비활성) → `BackupReadySheet`: `canShareFilesResult == false`면 [공유 · 파일에 저장] 숨김 / true면 표시, 각 버튼 → `deliverBackup` → 결과별 스낵바 문구(4.5.8), 취소 → 스낵바 없음 · **백업 준비 대기 취소**(INFRA-3-3, 계약 7.2.9 v1.2): `CountingNoteStore(flushGate: Completer<void>())`(끝나지 않는 Completer) → 백업 버튼 → 진행 줄·[취소] 표시, 버튼 비활성 → `emitStatus(PersistenceStatus(pendingOps: 1, isWriting: true, consecutiveFailures: 3))` → '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.' 표시 → [취소] → 진행 줄 사라짐, **버튼 다시 활성, 스낵바 없음, `BackupReadySheet` 없음, `errorLog.totalCount` 변화 없음**, 그 뒤 Completer를 끝내도 시트·스낵바가 뜨지 않음 |
| `app/test/settings/backup_export_test.dart` | `prepareBackup`: `flush` → `exportBackupJson` 순서, `BackupCancelToken.cancel()`(flush 대기 중) → 즉시 `null`·errorLog 0건, 그 뒤 늦게 끝난 결과·`exportBackupResult` 예외도 기록 없음, `cancel()` 두 번 → 문제없음(INFRA-3-3), 파일 이름 패턴·`mimeType == 'application/json'`, `exportBackupResult` 예외 → null + `errorLog` 1건(가짜 저장소 `exportBackupJson`은 B2 `UnimplementedError`라 `CountingNoteStore` 주입 사용 — 계약 7.6) · `deliverBackup`: download → `downloads`에 같은 바이트·이름·MIME, `downloadResult == false` → `unsupported` · share → `shares`에 같은 값, `shareResult` `cancelled` → `cancelled`(errorLog 없음), `failed` → `failed` + errorLog 1건, `unsupported` → `unsupported` |
| `app/test/modules/core_module_test.dart` | `start` → `open`이 받은 `config.ownerId == ctx.ownerId`, `config.web.sqlite3WasmPath`·`driftWorkerPath`가 `FakeWebPlatform.baseUri` 기준 **절대 URL**(`Uri.parse(path).isAbsolute`, 현재 위치가 `/notes/x`여도 — 계약 7.2.12·7.4.3 v1.1), `NoteStore` publish · `overrides()`로 만든 컨테이너의 `noteStoreProvider`가 같은 인스턴스 · `onAppHidden` → `flushCount` 1 · `stop` → `closeCount` 1 + 상태 구독 해제 · `NoteStoreOpenException` 그대로 전파 · `canResetAfter` 표(6.7) · `resetLocalData` → 마지막 config로 eraser 호출 · `PersistenceStatus.lastErrorAt`이 바뀔 때마다 `errorLog` 1건(같은 오류 반복 이벤트는 1건, 첫 이벤트에 오류가 있으면 1건) · **시간 초과 뒤 늦게 열린 저장소는 close 1회**(INFRA-2-9, fake_async): `fakeOpenNoteStore(gate:)` + 부트스트래퍼 → 20초 → `timedOut` → gate 완료 → 늦은 `CountingNoteStore.closeCount == 1`, publish·override 없음, 이후 `stop()`·`shutdown()`이 다시 닫지 않음(여전히 1) · 늦은 close 실패(`closeError`) → `errorLog` 1건 · 늦은 열기 실패 → close 없음·추가 기록 없음 |
| `app/test/modules/pdf_module_test.dart` | non-critical, `initialize` 호출, `overrides()` == `pdfOverrides()` 결과, 실패 시 부트스트랩이 overrides 제외, 기본 인자(B4 자리표시 `pdfIoOverrides()`)의 `overrides()`로 만든 컨테이너에서 `ink.pageBackgroundBuildersProvider` read → 예외 없음·2개(PDF-2-2 확인) |
| `app/test/modules/feature_wiring_module_test.dart` | PDF 시작됨: 컨테이너에서 `pageThumbnailRendererProvider`가 `inkPageThumbnailRendererProvider`와 같은 인스턴스, `libraryPdfImportActionProvider`·`libraryPdfExportActionProvider`가 주입한 함수와 `identical`, `editorExtensionsProvider`의 메뉴 id가 가짜 동작 순서와 같음, `devOverlaySectionsProvider`에 `pdf.render` · **B4 통계 provider**(INFRA-3-2, 계약 7.6 B4 v1.2 C12-06): 모듈 overrides만(`CoreModule(open: fakeOpenNoteStore(store: CountingNoteStore()))`·기본 인자 `PdfModule()`·이 모듈의 결과 — `pdfRenderStatsProvider` 테스트 override 없음) 넣은 컨테이너에서 `devOverlaySectionsProvider`를 read → `pdf.render` 섹션의 `lines.value`를 read → 예외 없음, 3줄(B4 = `PdfRenderStats.zero`) · PDF 실패(`isStarted('pdf') == false`): 두 자리 null, `editorExtensionsProvider` 기본값(빈 목록), `devOverlaySectionsProvider` 빈 목록, 썸네일 렌더러는 그대로 · `featureEditorOverrides()`·`featureLibraryOverrides()` 항목 포함 |
| `app/test/modules/pdf_wiring_test.dart` | `pdfRenderStatsSection`(INFRA-3-2, 계약 7.6 B4 v1.2 C12-06): 모듈 overrides만 넣은 컨테이너(위와 같음, 테스트용 `pdfRenderStatsProvider` override 없음)에서 `Provider((ref) => pdfRenderStatsSection(ref))`를 read → `id == 'pdf.render'`, `lines.value` read → 예외 없음, 3줄(B4에서는 `formatPdfRenderStats(PdfRenderStats.zero)`와 같음 — G2의 실제 PDF에서도 예외 없음만 단언), 컨테이너 dispose 뒤 lines 리스너 해제 · `pdfMenuInvocationOf` 4개 필드 대응(`onNavigate('p2', Rect.fromLTWH(10, 20, 30, 40))` → `navigateToPage`가 **같은 `Rect`**를 받음 — 변환 없음, 계약 7.2.17 v1.1), `editorMenuItemFromPdf`의 id·label·icon 동일·`onSelected` → `run(ctx, invocation)`·`isEnabled` null 유지/변환, `PdfRenderStatsLines`: 1초 동안 통계 100번 변경 → 갱신 ≤ 4번(fake_async)·dispose 후 리스너 없음, `formatPdfRenderStats` 텍스트 스냅숏(6.8) |
| `app/test/modules/production_modules_test.dart` | id 순서 `core, pdf, featureWiring`, 유일 |
| `app/test/integration/app_smoke_test.dart` (`integration`, G2) | 계약 V5 (8.3 'V5 스모크 단계' 1~9 — 순서는 8.3 'G2 실행 순서', 3~8단계는 V6와 공용 `test/support/smoke_scenario.dart`). **배너 단언**(INFRA-2-7, 계약 7.4.5 v1.1): 메모리 CORE = `nativeMemory` → `notDurable`, 라이브러리 화면(닫기 전)과 에디터 화면 각각 `find.text(ContractStrings.storageNotDurable)` → `findsOneWidget`. 획 좌표는 `InkPageView` 영역에서 계산(배너 높이 무관), 획 수는 `store.content`로 확인 |
| `app/test/web/web_platform_browser_test.dart` (Chrome) | `resolveAppUrl('sqlite3.wasm')`가 절대 URL이고 `/sqlite3.wasm`으로 끝남, 404 fetch → null, `visibilityChanges` 구독·해제, `isStandalone == false`, `downloadBytes`가 예외 없이 true, `canShareFiles()`가 예외 없이 bool(헤드리스 Chrome 값은 미확인)이고 false면 `shareFile` → `unsupported` |
| `app/test/web/app_boot_browser_test.dart` (Chrome) | 가짜 모듈로 `BootstrapApp` → 라이브러리 자리표시, 오류 화면 경로 — dart2js 컴파일 상태에서 `dart:io` 런타임 사용이 없음을 확인 |
| `app/test/web/app_smoke_browser_test.dart` (Chrome, `integration`, G2) | 계약 V6 — V5와 같은 시나리오, 실제 CORE 웹 저장. 테스트마다 다른 `databaseName`·`WebStorageConfig.blobDatabaseName`을 `NoteStoreConfig(web: WebStorageConfig(sqlite3WasmPath: …, driftWorkerPath: …, blobDatabaseName: …), databaseName: …)`로 직접 생성(`copyWith` 없음 — 8.3 'V6 설정', INFRA-3-5). 배너는 `storageWarningOf` 결과에 맞춰 두 화면 모두 고정 문장 1개 또는 0개. 끝에 `bootstrapper.shutdown()` 완료 뒤 같은 config로 `deleteLocalNoteData(config)`(INFRA-2-10 — 두 DB 모두 지워짐) |

### 9.2 GitHub에서만 확인 가능한 것 (B8 체크포인트 푸시, I13 후, G5)

- `ci.yml` 녹색, 실행 요약에 주소·단계 시간·`main.dart.js` 크기, 시크릿 없을 때 배포 건너뜀 표시
- 두 번째 실행에서 빌드 훅·준비 산출물 캐시 적중, `flutter-action` 캐시 적중 시 설정 단계 1분 이내
- 러너에 Chrome이 있어 브라우저 테스트가 `CHROME_EXECUTABLE` 없이 도는지(없으면 `setup-chrome` 추가)
- `android.yml` 아티팩트(APK) 생성, 출력 경로 일치
- 첫 배포 후 `curl -I https://<프로젝트 ID>.web.app/sqlite3.wasm` → `Content-Type: application/wasm`, `Cache-Control: no-cache`, COOP/COEP 없음
- 실측 기록(INFRA-S2): 6.13 '실측 항목' 표 3줄을 채워 결과 보고에 남기고 예산표를 고친다

### 9.3 사용자가 iPad에서 확인할 항목 (안내서 04에 체크리스트로)

| # | 확인 | 기대 결과 |
|---|---|---|
| 1 | live 주소를 Safari로 열기 | 로딩 표시 후 라이브러리 화면. 앱 정보의 '페이지 열기→준비'가 재방문 시 2초 이내 |
| 2 | 공유 → 홈 화면에 추가 → 아이콘으로 실행 | 아이콘·'필기노트' 이름, 주소창 없는 전체 화면, 앱 정보 '홈 화면 앱: 예' |
| 3 | 두 손가락 핀치 (빈 곳) | 웹 페이지 전체가 확대되지 않음 |
| 4 | 빠르게 두 번 탭 | 확대되지 않음 |
| 5 | 손가락·펜슬로 길게 누르기 (라이브러리·에디터) | 텍스트 선택·돋보기·'이미지 저장' 메뉴가 뜨지 않음 |
| 6 | 위·아래로 세게 끌기 | 페이지가 튕기거나 새로고침되지 않음 |
| 7 | 가로·세로 회전 | 화면이 새 크기에 맞게 다시 그려짐 |
| 8 | 설정 → 저장 공간 → '영구 보관' | 허용됨 / 허용되지 않음 기록 (결과를 알려 주기) |
| 9 | 새 버전 배포 후 홈 화면 앱으로 돌아오기 | 1분 안에 '새 버전' 배너 → 새로고침 → 빌드 번호 증가 |
| 10 | 처음 열 때 한글 | 글자가 네모로 보이는 시간이 있는지, 몇 초인지 |
| 11 | 설정 → 앱 정보 → 진단 정보 복사 → 채팅에 붙여넣기 | 빌드·브라우저·시작 시간·저장소 줄이 들어 있음 |
| 12 | 앱 전환기에서 위로 밀어 종료 후 다시 실행 | 정상 시작 (M1부터: 쓴 내용 유지 — CORE·EDITOR 공동) |
| 13 | Apple Pencil로 화면 위에 긋기 (M0 프로토타입) | 페이지가 스크롤·선택되지 않고 필기만 (INK·EDITOR 공동) |
| 14 | 브랜치 미리보기 주소 열기 | live와 별개로 동작, 데이터도 별개(임시) |
| 15 | (요청 시) `exp-wasm` 주소 `?renderer=skwasm` vs `?renderer=canvaskit` | 앱 정보 렌더러 표시가 바뀜, 필기 지연 체감 비교 |
| 16 | 노트를 연 상태(주소 `/notes/…`)에서 Safari 새로고침 | 정상 시작, 같은 노트가 다시 열림 (깊은 경로에서도 `sqlite3.wasm`을 받는지 — 6.4 절대 URL) |
| 17 | 라이브러리에서 폴더를 여러 번 오가기 | 화면이 새로 그려지며 미끄러지거나 깜빡이지 않고, 사이드바 펼침·스크롤 위치 유지 |
| 18a | **Safari 탭**에서 설정 → 앱 정보 → 백업 내보내기 → 시트의 [내려받기], 다시 [공유 · 파일에 저장] → '파일에 저장' | 각각 파일 앱에 `noteapp-backup-….json`(크기 0보다 큼)이 생기는지 기록. 둘 중 하나 이상 성공 = 합격 |
| 18b | **홈 화면 앱**에서 같은 순서 | 각각 기록(`<a download>`가 무시될 수 있음 — 11절). 둘 중 하나 이상 성공 = 합격. 둘 다 실패하면 즉시 알려 주기(백업은 M4 실연결 전 선행 조건 — 다른 경로를 계약 변경 요청으로 추가) |
| 19 | (키보드·트랙패드가 있으면) 라이브러리·에디터 빈 곳 우클릭 / 노트 제목 입력란 우클릭 | 빈 곳에서는 브라우저 메뉴 없음, 입력란에서는 편집 메뉴 사용 가능 |
| 20 | (통합 후) 계약 7.7 V7 ①②③ 복합 항목 | 각 영역 체크리스트와 함께 확인 |

### 9.4 안드로이드 (태블릿이 있을 때)

APK 내려받기·설치, 실행 시 라이브러리 화면, 새 APK 덮어 설치 가능 여부(서명, 6.14) 기록.

---

## 10. 완료 기준

1. 기반 단계: B1·B8 완료 조건(계약 7.6 v1.2 — B1 `ws check`에 R15 포함) 충족 상태로 main에 커밋되어 다른 영역이 worktree를 만들 수 있음. B8 실측값이 6.13 표에 기록됨.
2. 동시 개발 마감(I15, 컨테이너): `ws check` 위반 0, `flutter analyze --fatal-infos` 0건, `ws test`·`ws test --platform chrome`·`dart test tool/test` 전부 통과, `cd app && flutter build web --release` 성공.
3. 9.1 표의 모든 테스트 파일 존재·통과(통합 태그 2개와 `export_names_test`는 통합 단계).
4. GitHub: `ci.yml`이 main·브랜치 푸시에서 녹색, 시크릿 등록 후 live·미리보기 주소가 실행 요약에 표시, `android.yml` APK 아티팩트 생성.
5. 사용자가 안내서 01·02만 보고 Firebase 프로젝트와 시크릿 등록을 마침 (막히면 안내서 수정 후 재확인).
6. iPad 체크리스트 1–9, 11, 16, 17, 18a, 18b 통과 (10, 12–15, 19는 기록만).
7. 통합 단계(G1–G4): 계약 7.7 V1(`flutter pub get --enforce-lockfile`, `ws check` **R1~R15** 위반 0 — 계약 7.7 V1 v1.2, C12-01)·V2(`dart format` 변경 없음은 **R11 기준**: `app`·`packages`·`tool`의 `*.dart`에서 `generated_files`·`fixture_dirs` 제외)·V3·V4·V5(두 화면 배너 문구 = 계약 7.4.5 고정 문장 포함)·V6 중 INFRA 몫 통과, 계약 7.3.3 '이번' 행의 override가 모두 실제 구현이고 중복 없음.

---

## 11. 리스크와 대응

| 리스크 | 영향 | 대응 |
|---|---|---|
| Material 이원화(SDK vs material_ui) 혼용 | `Theme`·지역화·`Material` 조상 누락으로 위젯 오류·테스트 실패 | R7 금지 import, 브리지 없이 material_ui 단독(D2), 버전 고정, 꼭 필요하면 계약 7.4.2 절차 |
| material_ui 주간 릴리스로 변경 | 동시 개발 중 동작 차이 | 정확 고정, 업그레이드는 INFRA 단독 커밋 |
| flutter_riverpod의 pub.dev 웹 태그 없음 | 웹에서 예상 못 한 오류 | 웹 빌드 + Chrome 테스트로 실제 경로 검증 (확인함), CI에서 매번 |
| 엔진의 viewport `maximum-scale=5.0` | iPad에서 페이지 확대·입력란 자동 확대 | MutationObserver로 덮어쓰기 + `gesturestart` 차단, 체크리스트 3·4 |
| 엔진이 `contextmenu`를 막지 않음 (확인함, 계약 7.4.9 v1.1) | 우클릭·일부 길게 누르기에 브라우저 메뉴 | CSS(`-webkit-touch-callout`·`user-select`) + index.html 가드(계약 7.4.9 v1.1 문장 그대로), 체크리스트 5·19, 부족하면 계약 7.4.12 절차로 `disableContextMenu()` 재검토(6.9) |
| 깊은 경로(`/notes/…`)에서 상대 자산 경로가 틀어짐 (확인함: dart2js `Uri.base` = `location.href`) | 새로고침·복원 시 `sqlite3.wasm` 대신 `index.html`이 와서 시작 실패 | CORE에 `document.baseURI` 기준 절대 URL 전달(6.4, 계약 7.2.12·7.4.3 v1.1 — CORE `Uri.base.resolve`는 절대 URL을 그대로 통과), `core_module_test`·체크리스트 16 |
| iPadOS 홈 화면 앱에서 Blob + `<a download>`가 동작하지 않을 수 있음 (미확인, INFRA-2-11) | 백업 파일을 만들 수 없음 → M4 실연결 선행 조건(계약 7.8) 미충족 | 백업 시트에 두 번째 경로 **`navigator.share({files})`**(Safari 15+, 미확인)를 [공유 · 파일에 저장]으로 둔다(4.5.8). 두 버튼 모두 시트의 탭에서 바로 불러 사용자 활성화를 받는다. 체크리스트 18a(Safari 탭)·18b(홈 화면 앱)로 경로마다 기록, 둘 다 실패하면 M4 전에 다른 경로를 계약 변경 요청으로 추가 |
| 홈 화면 앱과 Safari 탭의 저장 공간이 따로일 수 있음 (미확인) | Safari 탭에서 백업해도 홈 화면 앱 노트가 빠짐, 사용자 혼동 | 안내서 04에 명시(6.16), 백업은 노트를 쓴 그 앱(홈 화면 앱)에서 하게 안내, 18b 결과로 확정 |
| CORE 시작이 20초를 넘긴 뒤 늦게 열림 | 늦게 열린 저장소가 DB를 쥔 채 다시 시도·데이터 지우기와 겹침(`deleteLocalNoteData` `StateError`) | `onStartAbandoned`가 즉시 `close()`, 다시 시도는 그 close 뒤(최대 2초) — 6.4 2-2, `core_module_test`·`bootstrap_app_test` |
| Safari에서 CanvasKit만 사용 | 필기 지연이 네이티브보다 큼 | 판정은 네이티브 전환(PLAN), skwasm 실험 채널로 비교 수단 확보 |
| 옛 버전이 보임 | 피드백이 잘못된 버전 기준 | 서비스 워커 해제, `no-cache`, 새 버전 배너, 빌드 라벨 표시 |
| Safari 저장 데이터 삭제 | 테스트 노트 유실 | CORE `persist()` 요청 결과 표시, 백업 내보내기(M4 전 선행 조건, 두 경로), 홈 화면 앱 사용 권장, 테스트 전용 안내 |
| 동시 개발 중 패키지가 `dart_test.yaml` 태그 선언·skip 없이 `integration` 테스트를 추가 (C11-26) | 기본 `ws test`가 B2 CORE로 통합 테스트를 돌려 실패 | 계약 7.4.8 v1.1, R15 검사(6.2 — B1-4부터 main의 `ws check`에 포함, 계약 7.6 B1 v1.2 C12-01: 각 영역 브랜치에서 위반 = 종료 1) |
| 태그를 변수·상수로 넘겨 R15 스캐너가 못 봄 | 선언·skip 누락이 검사를 빠져나감 | 계약 7.4.8 v1.2(리터럴 태그만 — 규칙으로 고정), 리뷰에서 리터럴로, `test_tags_test`가 '변수 태그 = 인식 안 함'을 고정해 한계를 드러냄 |
| CORE 쓰기 재시도 중 `flush()`·`exportBackupJson()`이 끝나지 않음 (계약 7.2.9 v1.2, C12-09) | 백업 준비 진행 표시가 끝나지 않고 버튼이 계속 비활성 | 진행 표시에 [취소](대기만 끊고 `null`, errorLog 없음)와 `writeFailing` 지연 문구(4.5.8, INFRA-3-3), 수명주기·새 버전 적용의 flush는 500ms 상한(5.1 C-I4) |
| 한글 대체 폰트 지연 로딩(CanvasKit은 gstatic에서 Noto 글꼴을 받음) | 첫 실행 시 한글이 잠시 안 보임 | 체크리스트 10으로 측정, 문제면 한국어 서브셋 폰트 번들 (이후) |
| GitHub Actions 무료 시간 초과 | 빌드 중단 | 6.13 절약 장치, B8 실측 후 예산 재계산, 체크포인트·통합 때만 푸시(계약 7.4.12) |
| CI에서 빌드 훅·준비 스크립트 다운로드 실패 | 테스트 실패(코드 문제 아님) | 캐시 2종, 다시 실행. 테스트 코드 자체는 네트워크를 쓰지 않음(계약 7.4.8) |
| 서비스 계정 키 생성이 조직 정책으로 막힘 | 배포 불가 | 안내서 02 문제 해결, 대안으로 Workload Identity Federation (이후) |
| `action-hosting-deploy`가 push 이벤트에서 채널 ID 자동 생성 불가 | 미리보기 배포 실패 | `ws channel-id`로 직접 계산 (확인함: 소스) |
| 액션 메이저 태그의 예기치 않은 변경 | CI 실패 | `firebase-tools` 버전 고정, 가능하면 SHA 고정 |
| 루트 `pubspec.lock` 병합 충돌 | 통합 지연 | B1에 계약 7.5 전부 선반영, 재생성 정책 (6.1), R9w로 미등록 의존 조기 발견 |
| 같은 provider 중복 override가 릴리스에서 안 잡힘 | 한쪽 값이 조용히 무시됨 | 디버그 assert(확인함) + `overrides_unique_test`·V5에서 `Override.origin` 비교 |
| 통합 때 피처 섹션·화면 이름이 계약과 다름 | 앱 셸 컴파일 실패 | 이름은 계약 7.2.17·7.2.18 그대로, B5·B6 자리표시가 기반 단계부터 같은 이름 → G2에서 즉시 드러남 |
| R14 분석 시간·`analyzer` API 변경 | `ws check`가 느려지거나 깨짐 | `analyzer 13.3.0` 고정(API 확인함), `--no-exports`로 로컬 생략, CI는 main에서만 강제 가능 |
| 웹 자산(`sqlite3.wasm`) 누락 | 재작성 규칙 때문에 `index.html`이 응답되어 원인 파악 어려움 | R12 + `web-assets verify` + `finalize-web` 확인 |
| (M4) firebase-tools가 `../` 규칙 경로를 못 읽음 | 규칙 배포 실패 | `--dry-run`으로 확인, 안 되면 배포 직전 복사(6.12) |
| 안드로이드 debug 서명 매번 변경 | 업데이트 시 재설치·데이터 삭제 | 안내서 명시, 태블릿 확인 후 고정 키 (6.14) |
| 새 Flutter 버전 출시 | 버전 불일치 | 루트 한 곳 고정(R2가 멤버 일치 강제), 업그레이드는 별도 작업 |
| 컨테이너에서 APK·iOS 빌드 불가 | 설정 오류를 늦게 발견 | CI 첫 실행을 B8 체크포인트에 포함, iOS는 초안 표시 |

---

## 12. 총괄 관리자에게 묻는 질문

### 12.1 1차 질문 처리 (00-review 3.1 답 반영)

| # | 답 (요약) | 반영 위치 |
|---|---|---|
| Q1 | 확정: 모든 패키지 material_ui만, 브리지 미사용 | D2, 4.1, 6.3 |
| Q2 | 확정: 루트 `.gitignore`·`pubspec.lock`·`.gitattributes` INFRA, 패키지별 `.gitignore`는 각 영역, `firebase.json`은 `app/` | 3.1, 3.4 |
| Q3 | 기반 단계 경계 = 계약 7.6 B1~B8 | 1.2, 8.1 |
| Q4 | 7.5 표의 모든 외부 의존을 B1에서 넣음 | 3.3, 6.1 |
| Q5 | `note_core` 순수 Dart, `sync_engine` Flutter 패키지(주 라이브러리 순수 Dart), 둘 다 `environment.flutter: 3.47.9` | 3.3, 4.3 `pure_dart_members`, R2 |
| Q6 | 설정 분담 CD-23, 에디터 `onOpenSettings` 유지 | 4.5.8, 6.6 |
| Q7 | CORE 형태(`openNoteStore` 등)로 확정 | 4.5.9, 5.1, 6.4, 6.7 |
| Q8 | COOP/COEP 불필요, 정적 파일 2개 | 4.3, 6.12 |
| Q9 | LIBRARY 자리 + PDF 함수 + 앱 셸 override | 4.5.9 `FeatureWiringModule` |
| Q10 | 기능 스위치는 이후 | 1.3 |
| Q11 | 규약을 계약에 넣음(7.4.4·7.4.5) | 4.1 |
| Q12 | '필기노트'·`dev.noteapp.noteapp` 자리표시로 진행(사용자 결정 U2) | 8.1 B1-3 |
| Q13 | 체크포인트·통합 때만 푸시 | 6.13 |
| Q14 | PLAN M0 문구는 총괄이 갱신 | 2절 |
| Q15 | 생성 파일 커밋, CI는 build_runner 안 돌림 | 6.2 R11, 7.2 |
| Q16 | 통합 순서·기준 = 계약 7.7 | 8.3 |

### 12.2 새 질문 (답이 없으면 '기본 진행'대로 한다)

| # | 질문 | 기본 진행 | 결정 (00-review 2차 INFRA-2-14) |
|---|---|---|---|
| N1 | 설정 섹션 순서를 PLAN 8 IA 순서(계정·동기화 → 저장 공간 → 입력 → 펜 → 일반(페이지 넘김·새 노트 기본값) → 개발자 표시 → 앱 정보)로 해도 되는가 (계약 7.4.11은 구성만 정함) | 4.5.8 표대로 | **승인** — 4.5.8 표 그대로 |
| N2 | 동시 개발 중 계약 7.5에 없는 외부 의존은 `ws check` 경고(R9w)로만 두고, main CI·통합 G1에서 `--strict`로 위반 처리하는 방식이 맞는가 | 그렇게 | **승인** — R9w + main·G1 `--strict`(6.2, 6.13) |
| N3 | 계약 7.1의 '앱은 전부 허용 + 이번 범위 `sync_engine` 미의존'을 `allowed_dependencies`에서 앱 → `sync_engine` 간선을 M4까지 빼 두는 것으로 강제해도 되는가 | 그렇게(M4에 간선 추가) | **승인** — 4.3 `allowed_dependencies`, 간선은 M4에 추가(1.3, 6.4) |

다른 영역 질문 중 INFRA 답(00-review 2차 INFRA-2-14):

| 질문 | 답 | 위치 |
|---|---|---|
| PDF 12.2 Q1 (라이선스 화면) | 이미 있음 — 앱 정보 '오픈소스 라이선스'(`showLicensePage`), 그대로 | 4.5.8 `AboutSection`, I9 |
| INK 12.2 Q4 (ink lab 실험 채널) | **선택 승인**(INFRA-O1대로): INK가 만들면 멤버 등록 + `allowed_dependencies` + `lib_exceptions`(`example/lib/`) + `web-experiment.yml` `target` 입력 | 1.3, 4.3, 6.2 R4, 6.13 |

### 12.3 계약 변경 제안 (승인 전에는 계획서를 계약대로 유지)

| # | 대상 | 제안 | 근거 | 결정 (00-review 2차 2.2 · 3차 3.2 · 4차 4.2) |
|---|---|---|---|---|
| P1 | 7.4.9 괄호 문구(+ 00-review 3.4 Q11 답, INFRA-S5) | "엔진이 `contextmenu`를 이미 막으므로 `BrowserContextMenu.disableContextMenu()`는 쓰지 않는다" → "`BrowserContextMenu.disableContextMenu()`는 쓰지 않는다(텍스트 입력의 브라우저 메뉴까지 끄고 프레임워크가 자체 선택 메뉴로 바뀜). iPad 길게 누르기 콜아웃·선택은 CSS(엔진 `user-select:none` + index.html `-webkit-touch-callout:none`)로, 우클릭 메뉴는 index.html이 입력 요소 밖에서만 `contextmenu`를 `preventDefault`해 막는다(01-infra 6.9)" | Flutter 3.47.9 엔진 `mouse/context_menu.dart`(`_enabled = true`), `platform_dispatcher.dart`(`disableContextMenu` 채널에서만 리스너 추가), 컴파일된 `main.dart.js`에서 같은 구조 확인함. 결정(쓰지 않음)은 그대로, 근거만 정정 | **승인** — 계약 7.4.9 v1.1(C11-28). 6.9에 계약 문장 인용 |
| P2 | 7.2.12 `NoteStore` | `Future<Uint8List> exportBackupJson();`(CORE-S3: 활성·휴지통 엔티티 JSON + 에셋 메타, 바이트 제외)를 시그니처에 명시 | 계약 7.8이 'INFRA 앱 정보 버튼 + M4 실연결 전 선행 조건'으로 정했지만 7.2.12에 멤버가 없어 INFRA가 위치를 가정해야 함(5.1) | **승인**(CORE CP-2와 한 건) — 계약 7.2.12 v1.1(C11-08). 5.1·4.5.8은 계약 인용 |
| P3 | 7.2.12 `WebStorageConfig` (+ 7.4.3) | "경로가 상대 경로면 `document.baseURI` 기준으로 해석한다(dart2js `Uri.base`는 `location.href`). 앱 셸은 절대 URL을 넘긴다"를 계약에 명시. 다른 패키지도 정적 파일 주소를 `Uri.base` 상대로 만들지 않는다 | Dart SDK `js_helper.dart` `Primitives.currentUri()` = `self.location.href` 확인함. 경로 URL 전략 + Hosting `**` 재작성에서 `/notes/<id>` 새로고침 시 `sqlite3.wasm` 요청이 `index.html`을 받음 → 시작 실패. INFRA는 이번 계획에서 절대 URL로 우회(6.4) | **수정 승인** — 계약 7.2.12·7.4.3 v1.1(C11-11): CORE 해석 기준(`Uri.base.resolve`)은 유지, 운영은 `document.baseURI` 기준 절대 URL, 상대는 테스트만, 대상은 정적 파일·에셋 URL(질의 읽기 제외). INFRA 설계는 원래 절대 URL만 넘겨 그대로 맞음(4.4, 6.4) |
| P4 | 7.5 `crypto` 행 | '쓰는 멤버'에 '루트(`tool/`)' 추가(같은 3.0.8, lock 변화 없음) | `ws web-assets`의 sha256 계산 | **승인** — 계약 7.5 v1.1(C11-29). 3.2·4.3·7.1에 반영, `sha256sum` 대체 경로 삭제 |
| **P5** | 7.4.2 첫 bullet · 7.6 B1 · 7.7 V1 | 7.4.2 "`tool/ws.dart check` 규칙 R1~R13(01-infra 6.2)"에 **R15(태그 선언: 테스트가 쓰는 태그는 패키지 `dart_test.yaml`에 선언, `integration`·`perf`는 `skip`)**를 더하고, 7.6 B1의 `ws check` 범위를 'R1–R3·R7–R9·**R15**'로, V1을 'R1~R15'로 | 계약 7.4.8 v1.1(C11-26)이 정한 규칙을 도구가 강제한다. 지금 계약대로면 R15는 INFRA 브랜치(I1)에서 만들어져 INFRA 병합 뒤에야 전 멤버에 적용된다(6.2). 2차 검토에서 EDITOR·LIBRARY가 같은 선언을 빠뜨렸던 것처럼, 동시 개발 중 각 영역 브랜치에서 바로 잡으려면 B1부터 켜야 한다. 구현은 작다(태그 리터럴 스캔 + YAML 확인, 6.2). B1 시점에는 태그를 쓰는 테스트가 없어 다른 영역 B2~B7 작업에 추가 부담이 없다. CORE·INK·PDF·SYNC는 이미 계획에 `dart_test.yaml`이 있고, EDITOR·LIBRARY는 3차 수정 지시(EDITOR-2-7, LIBRARY-2-1)로 넣는다 | **승인 — 계약 v1.2 C12-01**(7.4.2·7.4.8·7.6 B1·7.7 V1, 00-review 3차 3.2). 담당 조건 둘(B1부터 위반 = 종료 1, '리터럴만 인식' 제약을 7.4.8에)이 그대로 들어갔다. 계획서 반영: 1.2·4.1·4.2·4.3·6.2 R15·8.1 B1-4·8.2 I1·9.1·10절·11절 (INFRA-3-1) |
| **P6** (새, 사소) | 7.6 B1·B8 '완료 조건' 열 | B1 완료 조건 '`flutter pub get --enforce-lockfile`, `ws check`, `ws test`'에 **`dart test tool/test`**를 더하고, B8 '전체' 목록에도 같은 항목 | v1.2로 B1 경로에 `tool/test/`(`test_tags_test.dart` 포함)가 들어갔지만, `ws test`는 워크스페이스 멤버만 돌리므로(루트 `tool/test/`는 멤버가 아님, 4.2) 계약 문구대로면 R15 검사기의 테스트가 B1·B8 완료 판정에서 실행되지 않는다. V3에는 이미 `dart test tool/test`가 있어 통합 기준과 맞추는 문구 정리일 뿐이고, 다른 영역 작업에 영향 없음(B2~B7은 `tool/`을 바꾸지 않음) | **승인 — 계약 v1.3 C13-01** (8.1 B1 완료·B8-2 인용을 '계약 7.6 B1·B8 v1.3'으로, INFRA-4-1) |

---

## 13. 검토 반영 내역

### 13.1 1차 수정 (00-review 1차 검토, 2026-11-04)

필수 수정

| 항목 | 반영 내용 |
|---|---|
| INFRA-M1 (5.1, 4.5.9, 5.7, 6.7) | `openNoteCore`·`NoteCoreHandle`·`NoteCoreConfig`·`NoteCoreOpenException` 가정 삭제 → 계약 7.2.12: `CoreModule({Future<NoteStore> Function(NoteStoreConfig) open = openNoteStore, …})`, `start`에서 `NoteStore` publish, `overrides()` = `[noteStoreProvider.overrideWithValue(store)]`, `onAppHidden()` = `store.flush()`(500ms), `stop()` = `store.close()`(4.5.9, 6.4). 6.7 문구 표를 `NoteStoreOpenFailure` 5종 기준으로 다시 씀(`newerSchema` → "앱을 새로고침해 최신 버전을 받아 주세요" + 새로고침 버튼). `onResetLocalData` = `deleteLocalNoteData(config)`(`AppModule.resetLocalData`/`canResetAfter`, `BootstrapFailure.resetLocalData`, `migrationFailed`·`corrupted`·`unknown`일 때만). 5.1을 계약 원문 발췌로 교체. 5.7 `FakeNoteCoreHandle`·`fakeOpenNoteCore` 삭제 → CORE `createFakeNoteStore()` + 그것에 위임하는 `CountingNoteStore`, `fakeOpenNoteStore`, `RecordingLocalDataEraser` |
| INFRA-M2 (4.5.9, 8.2 I10, 8.3 G2) | `FeatureWiringModule` + `pdf_wiring.dart` 추가(4.5.9): 계약 7.3.3 표의 썸네일 렌더러(`pageThumbnailRendererProvider` ← `inkPageThumbnailRendererProvider`), `libraryPdfImportActionProvider`·`libraryPdfExportActionProvider`, `PdfMenuAction` → `EditorMenuItem` 변환(`EditorMenuContext` → `PdfMenuInvocation`, `onNavigate: navigateToPage`), PDF 렌더 통계 `DevOverlaySection`(≤ 4 Hz). `productionModules()` = core → pdf → featureWiring. PDF 시작 실패 시 PDF 관련 override 생략 — `AppModuleContext.outcomeOf`/`isStarted`로 전달. 작업 I10b, 테스트 `feature_wiring_module_test.dart`·`pdf_wiring_test.dart`·`overrides_unique_test.dart`. G2 스모크를 계약 7.7 V5·V6 문장 그대로(8.3) |
| INFRA-M3 (4.4, 6.3, 9.1) | `MaterialUiCompatibilityBridge`를 위젯 트리·결정·리스크에서 제거(D2, 4.4, 6.3, 11). `note_app_test`는 브리지 **부재**를 확인(그 한 줄만 ignore + 사유). 필요해지면 계약 7.4.2 절차 |
| INFRA-M4 (4.1, 4.2, 6.13) | `ws test --platform chrome` = `test/web/`만 + 멤버별 `tool/prepare_web_test.dart` 선실행(실패 처리·5분 제한), `CHROME_EXECUTABLE` 전달·Chrome 찾기(4.2). 4.1 문구 "테스트 코드는 네트워크 금지, 빌드 훅·준비 스크립트 다운로드는 허용(CI 캐시)". `ci.yml`에 `actions/cache@v6` 2종(`.dart_tool/hooks_runner` 키 = `pubspec.lock` 해시, 준비 산출물 키 = lock + 준비 스크립트), `integration` 태그 실행 옵션(`ws test --run-skipped -t integration`, `-t`·`-x`·`--run-skipped`, dispatch 입력 `integration`) |
| INFRA-M5 (3.3, 4.3, 6.2) | `pinned_external` = 계약 7.5 표 전부(35개 + G3에 `analyzer`). `lib_exceptions: [packages/note_core/lib/testing_vm.dart]`(R4), R6은 `lib/`에만, R2 순수 Dart 처리(`pure_dart_members`, `environment.flutter` 유지, Flutter SDK 의존·import 금지). 3.3: `note_core` 골격 순수 Dart(`test: 1.31.1`) + 멤버별 7.5 의존표. 3.3·3.4·7.1·4.3: 앱 의존에서 `sync_engine` 제거(M4 추가, `allowed_dependencies`도) |
| INFRA-M6 (4.5.8, 5.2, 6.8, 1.4) | `settingsSectionsProvider` 기본값 = `defaultSettingsSections()`: EDITOR 4종(입력·펜·페이지 넘김·개발자 표시) + LIBRARY `LibrarySettingsSection`(일반 › 새 노트 기본값) + INFRA '저장 공간'(`StorageSection`)·'앱 정보'(`AboutSection`), M4에 '계정 · 동기화'(INFRA가 SYNC API로). 5.2를 계약 7.2.17 원문으로 교체(`EditorSettingsSection` 1개 가정 삭제). 1.4 제외 표 갱신 |
| INFRA-M7 (6.6, 4.5.5) | `/notes/:noteId` = `NoTransitionPage`, `/`·`/folders/:folderId` = 같은 `ValueKey('library')`(`AppRoutes.libraryPageKey`)의 `NoTransitionPage`. go_router 18.1.2 + material_ui 1.10.0 실험으로 State 유지 확인(6.6). `app_router_test`에 "폴더 이동 시 `LibraryScreen` State 유지"·페이지 종류 검사 추가 |

권장 수정

| 항목 | 반영 내용 |
|---|---|
| INFRA-S1 (4.5.2, 6.4, 4.5.3) | `WebPlatform.requestPersistentStorage/estimateStorage`, `StoragePersistence`, `StorageEstimate`, `storageEstimateProvider`, 부트스트랩 persist 단계·`persistTimeout` 삭제. `StartupReport.storage`(CORE `StorageInfo`), `DiagnosticReport`는 `StorageInfo`·`PersistenceStatus`, 저장 공간 섹션은 `storageInfoProvider`/`refreshStorageInfo()`(`latestStorageInfoProvider`) |
| INFRA-S2 (6.13, F8→B8) | 6.13 예산을 '추정'으로 표시하고 B8-3 실측 작업(첫 CI 시간·`main.dart.js` 크기·Chrome 첫 `openNoteStore`) + 실측 표 + 9.2 기록. `finalize-web`이 크기를 요약에 남김 |
| INFRA-S3 (6.2) | R14를 통합 단계 G3에 추가: 루트 dev `analyzer: 13.3.0`, `exportNamespace.definedNames2` 비교(실험으로 API 확인), `export_names_test.dart`, `--no-exports` |
| INFRA-S4 (3.4, 6.12, 6.16) | 6.12에 M4 `app/firebase.json` 형태(`../packages/sync_engine/firebase/{firestore.rules, storage.rules, firestore.indexes.json}`) 문서화, `hosting_config_test`가 참조 파일 존재 확인(M4 픽스처). 안내서 04에 미리보기 데이터·로그인 분리(임시)·로그인은 live에서만, 안내서 01에 Firestore `asia-northeast3`·Storage US 리전 권장(사용자 선택, 미확인 표시)과 `authDomain` |
| INFRA-S5 (6.9) | `BrowserContextMenu.disableContextMenu()` 미사용을 6.9에 명시. **단, 제시된 근거('엔진이 이미 막음')는 엔진 소스·`main.dart.js` 확인 결과 사실이 아니어서** 실제 근거(CSS + index.html `contextmenu` 가드, 텍스트 입력 메뉴 보존)로 적고, 계약 문구 정정은 12.3 P1로 제안. 초안 6.9의 같은 오기록도 수정 |
| INFRA-S6 (4.5.8) | 앱 정보에 '백업 내보내기' 버튼: `exportBackup()` = `flush` → CORE `exportBackupJson()` → `WebPlatform.downloadBytes`(새 멤버). M4 실연결 전 선행 조건으로 2절·11절에 표시, 위치 명시는 12.3 P2 |
| INFRA-S7 (6.4) | `AppModuleContext.ownerId`·`AppBootstrapper.ownerId` 문서 주석과 6.4에 "새 DB 생성 때만 의미, 저장된 CORE 소유자 우선(첫 로그인 후 `reassignOwner`), 실제 소유자는 `store.ownerId`" |

선택 · 기타

| 항목 | 반영 내용 |
|---|---|
| INFRA-O1 | 이번 차수 반영 대상 아님. INK가 ink lab을 만들기로 하면 멤버 등록 + `web-experiment.yml` `target` 입력을 추가한다고 1.3·6.13에 적어 둠 |
| 질문 답 Q1–Q16 | 12.1 표로 반영 위치 정리 |
| (자체) 해요체 | 계약 7.4.5에 맞춰 셸 사용자 문구를 해요체로(오류 상자·시작 오류·NotFound·스플래시 지연·로딩 실패·새 버전 배너·백업) |
| (자체) 깊은 경로 자산 URL | dart2js `Uri.base` = `location.href` 확인 → `WebPlatform.resolveAppUrl` + `defaultNoteStoreConfig`가 절대 URL 전달(4.4, 4.5.2, 6.4), 체크리스트 16, 12.3 P3 |
| (자체) 조건부 import 형태 | 계약 7.4.3 형태(`dart.library.ffi` → `_native.dart`)로 4.1 갱신 |
| (자체) 검사 규칙 보완 | R5는 `test/web/` 제외, R7에 다른 패키지 `src/` import 금지, R4에 `testing.dart`·`testing_vm.dart`의 `lib/` import 금지, R11은 생성 파일 제외, R9w·`--strict` |
| (자체) provider 규칙 | 모든 셸 provider에 `name:`, `routerProvider` → `appRouterProvider`(이름 유일성), 앱 주입 provider 오류 문구를 계약 7.4.4 형식으로 |
| (자체) 순수 Dart 상태 스트림 | CORE `PersistenceStatus.lastError`를 `CoreModule`이 `AppErrorLog`로 넘김(계약 7.4.5) |
| (자체) 중복 override 검출 | Riverpod 3.4.3 디버그 assert 확인, 릴리스 대비 `Override.origin` 기반 테스트(`@visibleForTesting`이라 앱 `lib/`에서는 쓰지 않음) |
| (자체) 웹 자산 | 계약 7.4.9 두 파일의 URL·크기·sha256을 내려받아 확인하고 `web_assets.yaml`을 채움, Hosting `.wasm` MIME 헤더, `actions/cache@v6` 태그 확인 |
| (자체) 기반 단계 표기 | 초안 F1–F8을 계약 7.6 B1·B8로 재구성(F4 피처 자리표시는 B5·B6 영역 몫, F7은 B2) |

### 13.2 2차 수정 (00-review '2차 검토(승인 검토)' 2.4.1 · 통합 계약 v1.1, 2026-11-04)

지시별 반영 (00-review 2차 2.4.1 — [계약] 8건은 재승인 조건, [권장] 5건·[사소] 2건도 모두 반영)

| 지시 | 종류 | 반영 내용 (위치) |
|---|---|---|
| INFRA-2-1 (C11-28) | 계약 | 6.9 'BrowserContextMenu 결정'에 계약 7.4.9 v1.1 문장을 원문 그대로 인용하고 INFRA 구현(엔진 CSS + index.html `-webkit-touch-callout`·`contextmenu` 가드)을 그 문장에 맞춤. 옛 근거('엔진이 이미 막음')와 '총괄 승인 후 한 줄 변경' 문구를 '계약 7.4.12 절차로 재검토'로 교체. 6.9 '엔진이 이미 하는 일'·11절 리스크 행의 '12.3 P1' 인용을 계약 인용으로. 12.3 P1 **승인** 표시 |
| INFRA-2-2 (C11-08) | 계약 | 5.1: 계약 7.2.12 블록을 v1.1 원문으로 교체(`exportBackupJson` 포함), 'CORE-S3 … 12.3 P2로 명시 요청' 가정 블록 삭제, 'INFRA가 쓰는 CORE 멤버' 표의 백업 행 = `NoteStore.exportBackupJson()` **계약 7.2.12 v1.1**. 4.5.8 `prepareBackup` 주석도 '계약 7.2.12 v1.1'. B2 가짜 저장소의 `exportBackupJson`은 `UnimplementedError`(계약 7.6)라서 `backup_export_test`·`about_section_test`는 `CountingNoteStore`의 `exportBackupResult` 주입을 유지한다는 줄을 4.5.8·5.1·5.7·9.1에. 12.3 P2 **승인** |
| INFRA-2-3 (C11-11) | 계약 | 4.4 '웹 기준 URL' 행, 4.5.2 `resolveAppUrl` 주석, 4.5.9 `defaultNoteStoreConfig` 주석, 5.1 C-I3, 6.4 '절대 URL', 11절 리스크 행의 '12.3 P3' → **계약 7.2.12·7.4.3 v1.1**. CORE는 `Uri.base.resolve(path)`를 그대로 쓰고 절대 URL은 그대로 통과하므로 INFRA는 운영에서 절대 URL만 넘기면 된다(CORE 변경 없음, 상대는 테스트만, 질의 읽기는 대상 밖)를 명시. `core_module_test`에 `Uri.parse(path).isAbsolute`. 12.3 P3 **수정 승인** |
| INFRA-2-4 (C11-29) | 계약 | 3.2 루트 dev에 `crypto: 3.0.8`, 3.3 표 `feature_library` 행에 `collection: 1.19.1`·dev `clock: 1.1.3`. 4.3 `web-assets` 비고를 `package:crypto`로(대체 경로 삭제), 7.1 표에 `crypto` 행 추가(pub.dev 3.0.8, 2026-10-26, sdk ^3.4.0, BSD-3-Clause, 웹 ✓), 7.2 표의 `crypto` 미사용 행·7.3 표의 `sha256sum` 행 삭제, 8.2 I1·9.1 `web_assets_test`를 `package:crypto`로. `pinned_external` 확인: `collection 1.19.1`·`clock 1.1.3`·`crypto 3.0.8`이 이미 있고 v1.1에서 버전 변화 없음(35개 + G3 `analyzer`). 총괄 `lead/ws-v11` 사본으로 `flutter pub get --offline --enforce-lockfile` 성공 확인(확인함, `/tmp/claude-0/plan-scratch/infra3/ws-v11`). 12.3 P4 **승인** |
| INFRA-2-5 (C11-10) | 계약 | 4.5.10 `latestStorageInfoProvider` = `refreshStorageInfo()` 뒤 `if (ref.mounted) ref.invalidate(storageInfoProvider)`(앱 셸의 유일한 호출처), 4.5.8 `StorageSection` 주석에 같은 규칙과 '반환값은 바로 사용'. Riverpod 3.4.3에서 await 뒤 invalidate·`mounted` 가드 동작을 scratch로 확인함(`/tmp/claude-0/plan-scratch/infra3/invalidate`). 5.1 표·6.8 표 갱신. 5.7 `CountingNoteStore`에 `refreshResult`·`refreshCount`. 9.1 `storage_section_test`에 '다시 확인 후 `storageInfoProvider` 값 갱신'(별도 `Consumer`가 새 `persistGranted`로 다시 그려짐)과 dispose 중 완료 경우 |
| INFRA-2-6 (C11-13) | 계약 | 5.5 SyncModule 표·6.4 'M4 연결'·6.8 M4 행의 `syncBadgeProvider` 값 = `syncEngine.statusStream.map(syncBadgeOf).distinct()`(override 식은 `ref.watch(syncEngineProvider)…distinct()`). 5.5에 계약 7.2.13 `SyncBadge`(`==`/`hashCode`)·`syncBadgeProvider`, 7.2.20 `syncBadgeOf`·`SyncRemoteAssetFetcher` 원문 블록 추가 |
| INFRA-2-7 (C11-12·24·30) | 계약 | 8.3 G2에 'V5 스모크 단계' 1~9: 메모리 CORE(`NoteStoreConfig(inMemory: true)`) = `nativeMemory` → `notDurable` 전제 단언, 라이브러리(배너 **닫기 전**)·에디터 두 화면에서 `find.text(ContractStrings.storageNotDurable)` 1개(`app/test/support/contract_strings.dart` = 계약 7.4.5 고정 문장 2개), 획 좌표는 `InkPageView` 영역에서 계산·탭은 finder로·획 수는 `store.content`로 확인해 배너 높이에 기대지 않음. V6는 `storageWarningOf` 결과에 맞춰 1개/0개. 9.1 `app_smoke_test`·`app_smoke_browser_test` 행에 배너 단언, 10절 7에 V5 배너 포함. 5.3에 LIBRARY 배너 닫기 버튼 메모 |
| INFRA-2-8 (C11-27) | 계약 | 5.1에 계약 7.6 'B2 테스트·개발 도우미' 블록(`createFakeNoteStore` 전체 시그니처·`FakeNoteStoreFaults`·`openTestNoteStore(storageInfo:)`) 원문 그대로, 'INFRA가 쓰는 CORE 멤버' 표 '테스트' 행도 전체 시그니처. B2 단계 값(가짜 `nativeFile` 기본, 가짜 `SyncStore` 멤버 처리, `openTestNoteStore`·`openNoteStore` B2 `UnimplementedError` → INFRA 실제 CORE 테스트는 `integration` 태그) 정리 |
| INFRA-2-9 | 권장 | 4.5.4 `AppModule.onStartAbandoned()` 추가, `AppBootstrapper.shutdown()`이 그 정리를 최대 2초 기다림. 4.5.9 `CoreModule.start`·`onStartAbandoned`: 20초 시간 초과 뒤 늦게 열린 `NoteStore`는 publish하지 않고 즉시 `close()`(실패 → errorLog), 다시 시도는 그 close가 끝난 뒤(최대 2초). 6.4 2-2 항목 추가, 5.1 C-I5, 5.7 `fakeOpenNoteStore(gate:)`·`FakeAppModule.abandonDelay`, 9.1 `core_module_test`('close 1회', 늦은 close 실패, 늦은 열기 실패)·`app_bootstrapper_test`·`bootstrap_app_test`, 11절 리스크 행 |
| INFRA-2-10 | 권장 | 8.3 G2 V6와 9.1 `app_smoke_browser_test`: 끝 정리를 `bootstrapper.shutdown()`(= `store.close()`) 뒤 `deleteLocalNoteData(config)`로(CORE 6.18 `StateError`) |
| INFRA-2-11 | 권장 | 11절에 'iPadOS 홈 화면 앱에서 Blob + `<a download>` 미동작 가능(미확인)' 행 + 대응 `navigator.share({files})`. 4.5.2 `WebPlatform`에 `canShareFiles`·`shareFile`·`WebShareResult`(package:web 1.1.2 바인딩 확인함), 4.5.8 백업을 `prepareBackup` → `BackupReadySheet`([공유 · 파일에 저장]·[내려받기], 탭마다 새 사용자 활성화) → `deliverBackup`으로 나눔, 문구 추가. 6.16 안내서 04 백업 절차, 9.3 #18 → **18a Safari 탭 / 18b 홈 화면 앱**, 10절 6. 관련 미확인 위험 '홈 화면 앱과 Safari 탭의 저장 공간 분리'도 11절·안내서에 |
| INFRA-2-12 | 권장 | 4.3 `native_only_imports`(`package:ffi/`·`package:pdfium_dart/`·`package:drift/native.dart` — `native_suffixes` 파일에서만, `lib_exceptions`의 `testing_vm.dart` 예외), `test_only_entrypoints` 규칙을 `package:` URI 기준(같은 패키지 `lib/testing*.dart`끼리 상대 허용)으로 명시, `lib_exceptions` 디렉터리 항목. 6.2 R4·4.1 표 갱신. 1.3 INFRA-O1에 ink lab `example/lib/`의 `lib_exceptions` 추가 줄. 9.1 `rules_test`에 native_only 위반 1·허용 1, test-only 위반 1·허용 1(+ 상대 경로 우회·디렉터리 예외) |
| INFRA-2-13 | 권장 | 8.3 G4·10절 7·6.2 R11: 'dart format 변경 없음'의 대상 = **R11 기준**(`app`·`packages`·`tool`의 `*.dart`, `generated_files` 제외). 6.2 exclude 비고: drift 생성 파일(`schema_versions.dart`, 생성 테스트)이 lint에 걸리면 exclude·`generated_files`에 추가(CORE 11절 요청) |
| INFRA-2-14 | 사소 | 12.2 N1~N3 **승인** 표시(결정 열). PDF 12.2 Q1은 I9·4.5.8 `AboutSection`의 '오픈소스 라이선스'로 이미 답이 있음, INK 12.2 Q4는 INFRA-O1대로 **선택 승인** — 12.2 '다른 영역 질문' 표와 1.3. 이 13.2 표 |
| INFRA-2-15 | 사소(선택) | **반영**: `ws check` R15(6.2·4.3 `skip_by_default_tags`·`tool/src/test_tags.dart`) — 테스트가 쓰는 태그는 패키지 `dart_test.yaml`에 선언, `integration`·`perf`는 `skip`. 계약 7.6 B1 범위대로 I1에서 만들고 G1부터 전 멤버 적용, B1 선적용은 12.3 **P5**로 제안. 9.1 `test_tags_test`, 11절 리스크 행. 앱 자신의 `app/dart_test.yaml` 내용도 I12에 명시(계약 7.4.8 v1.1). *(3차: P5 승인 — R15는 B1-4로 옮김, 13.3 INFRA-3-1)* |

계약 v1.1 변경 항목(00-overview 7.9)별 INFRA 영향

| 항목 | INFRA 영향 · 반영 |
|---|---|
| C11-01·02·03·04·05·06·07 | 없음(CORE·SYNC·EDITOR·INK·PDF·LIBRARY 내부 의미). INFRA는 세션·`SyncStore`를 쓰지 않는다 |
| C11-08 | INFRA-2-2 |
| C11-09 | `CoreModule` 상태 구독(첫 이벤트 = 현재 값, 그 안의 오류도 1건)과 `StorageSection` 첫 프레임 — 4.5.8, 4.5.9, 6.4, 9.1 |
| C11-10 | INFRA-2-5 |
| C11-11 | INFRA-2-3 |
| C11-12 | INFRA-2-7(V5 전제·배너), INFRA-2-8(`openTestNoteStore(storageInfo:)`), 5.1 `NoteStoreConfig` v1.1 주석 |
| C11-13 | INFRA-2-6 |
| C11-14·15·16·17·18·19·20 | 없음(INK·EDITOR·PDF 사이). INFRA는 `pageThumbnailRendererProvider` ← `inkPageThumbnailRendererProvider` 연결만이고 그 형태는 그대로 |
| C11-21 | 5.2 `EditorMenuContext` 원문에 v1.1 주석 2줄, `pdfMenuInvocationOf`는 `focusRectPt`를 변환 없이 전달(4.5.9 주석, 9.1 `pdf_wiring_test`) — 계약 '전달만' |
| C11-22 | 5.5에서 INFRA가 M4에 쓰는 SYNC 이름이 바뀌지 않았음을 확인, 3.3 `sync_engine` 행 변화 없음(lib에서 `fake_async` 미사용) |
| C11-23·25 | 없음 |
| C11-24 | INFRA-2-7 |
| C11-26 | 4.1 '태그' 행, `app/dart_test.yaml` 내용(I12), R15(INFRA-2-15) |
| C11-27 | INFRA-2-8 |
| C11-28 | INFRA-2-1 |
| C11-29 | INFRA-2-4 |
| C11-30 | 8.3 G2(배너 대조, 5단계 통합 태그 테스트를 같은 명령으로), 6.13 10단계 명령 `ws test --run-skipped -t integration` 그대로 |
| 기각 CORE CP-3·CP-4 | 없음 |

자체 정리 (2차)

| 항목 | 반영 내용 |
|---|---|
| 계약 원문 발췌의 글자 일치 | 5.1(7.2.12·7.6), 5.2(7.2.17 — `editorSettingsProvider`·`StylusExtrasSource` 줄 포함), 5.3(7.2.18 끝 주석), 5.4(7.2.19 끝 주석), 5.5(7.2.13·7.2.20) 블록을 v1.1 원문 그대로로 바꾸고 머리에 'v1.1 (원문 그대로)' 표시 |
| PDF-2-2 확인 | 5.4·9.1 `pdf_module_test`: B4 자리표시 `pdfIoOverrides()`로 `ink.pageBackgroundBuildersProvider`를 읽어도 예외 없음(2개)을 INFRA 쪽에서도 확인 |
| 데이터 지우기 순서 | INFRA-2-10과 같은 이유(CORE 6.18 `StateError`)로 시작 오류 화면의 '이 기기 데이터 지우고 다시 시작'도 `shutdown()` 뒤 `resetLocalData()`(6.4 4단계), `BootstrapApp.createBootstrapper` 주석에 '다시 시도는 이전 `shutdown()` 완료 뒤' |
| 상태 줄 | 머리말 상태를 '2차 수정 v0.3 · 계약 v1.1'로 |

### 13.3 3차 수정 (00-review '3차 검토(승인 검토)' 3.4.1 · 통합 계약 v1.2, 2026-11-05)

지시별 반영 (00-review 3차 3.4.1 — [계약] 2건은 재승인 조건, [권장] 1건·[사소] 2건·[절차] 1건도 모두 반영. 미반영 없음)

| 지시 | 종류 | 반영 내용 (위치) |
|---|---|---|
| INFRA-3-1 (C12-01) | 계약 | P5 승인으로 R15를 기반 단계 B1로 옮김. **1.2** B1 설명 'check R1–R3·R7–R9' → 'R1–R3·R7–R9·**R15**'(계약 7.6 B1 v1.2, `skip_by_default_tags`·`test_tags_test` 포함), 동시 개발 행은 'R4–R6·R10–R13 추가, R15는 B1에서 완료'. **6.2** R15 아래 문단의 'B1에는 넣지 않고 I1에서 만든다 … 12.3 P5로 제안한다' → '**R15는 B1-4에서 만든다**(계약 7.6 B1 v1.2) — 동시 개발 중 각 영역 브랜치의 `ws check`가 선언 누락을 위반(종료 1)으로 잡는다', 리터럴 태그 제약은 **계약 7.4.8 v1.2 문장 인용**으로(태그는 리터럴로, `dart_test.yaml`은 태그를 쓰는 첫 테스트보다 먼저), R15 표 행에 'B1부터 위반 = 종료 1', 규칙 표 머리에 B1 판 범위. **8.1 B1-4** 산출물에 `tool/src/test_tags.dart`·`workspace_rules.yaml` `skip_by_default_tags: [integration, perf]`·`tool/test/test_tags_test.dart`(9.1 행 그대로), 완료 조건에 `test_tags_test` 통과·`ws check` 0(R15 포함). **8.2 I1**의 R15 = 'B1-4에서 완료(회귀만)'. **10절 7** 'V1(`ws check` R1–R14 — INFRA는 R15도 0)' → '계약 7.7 V1 **R1~R15**(v1.2)'(10절 1에도 B1 R15). **11절** C11-26 행에서 '전 멤버 적용은 INFRA 병합 뒤, 12.3 P5로 B1 선적용 제안' 삭제 → 'B1-4부터 main `ws check`, 각 영역 브랜치에서 위반 = 종료 1'. **12.3 P5** 결정 = '**승인 — 계약 v1.2 C12-01**'. 함께 맞춘 곳: 3.5 `test_tags.dart` 주석(B1-4, v1.2), 4.1 '태그' 행(v1.2 문장), 4.2 `check` 행(B1 판 범위), 4.3 `skip_by_default_tags` 주석, I12 `app/dart_test.yaml`(앱의 첫 태그 테스트 G2보다 먼저), 9.1 `test_tags_test`(B1-4, 변수 태그 = 인식 안 함 경우, 종료 1) |
| INFRA-3-2 (C12-06) | 계약 | 계약 7.6 B4 v1.2로 PDF B4의 `pdfRenderStatsProvider` = `ValueNotifier(PdfRenderStats.zero)`가 되므로 **4.5.9 `FeatureWiringModule`·`pdfRenderStatsSection(ref)`는 지금 모양 유지**(통계 주입 함수 없음) — 두 주석에 'B4: 0 통계 notifier, 실제 provider를 읽음'만 추가. **5.4**에 계약 7.6 B4 v1.2 bullet(다른 영역이 읽는 PDF provider는 B4에서도 예외 없음, G2에서 같은 단언이 7.3.3 연결 누락을 잡음). **5.7 '가짜 PDF 동작'** 행에 'PDF T8 전(B4): `pdfRenderStatsProvider` = 0 통계 notifier(계약 7.6 B4 v1.2) — 테스트 컨테이너에 따로 override하지 않음'. **9.1** `feature_wiring_module_test`·`pdf_wiring_test`에 '모듈 overrides만(`CoreModule`(가짜 열기)·기본 `PdfModule()`·`FeatureWiringModule`) 넣은 컨테이너에서 `devOverlaySectionsProvider`의 `pdf.render` 섹션을 만들고 `lines` 값을 읽어도 예외 없음(3줄 = `formatPdfRenderStats(PdfRenderStats.zero)`)' 단언 |
| INFRA-3-3 (C12-09) | 권장 | **4.5.8**: `BackupCancelToken`(`isCancelled`·`cancel()`) 추가, `prepareBackup({…, BackupCancelToken? cancel, …})` — `flush()`·`exportBackupJson()`(먼저 flush)은 쓰기 재시도 중 끝나지 않으므로(계약 7.2.9 v1.2) 시간 제한을 두지 않고, 취소 시 **대기만 끊고 `null`, errorLog 없음**(쓰기 큐·메모리 상태는 그대로, 늦은 결과·오류는 버림 — 저장 실패는 `CoreModule`이 `PersistenceStatus.lastError`로 이미 기록). `AboutSection`(→ `ConsumerStatefulWidget`, 토큰·진행 상태 보유) 진행 줄 = '백업을 만드는 중…' + **[취소]**, `storageWarningOf(…) == writeFailing`이면 '**저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.**'(셸 문구 — 계약 7.4.5 배너 문장과 별개). 4.5.8 bullet '백업 준비 대기', 3.4 트리 주석. **5.1**: 계약 7.2.9 v1.2 '쓰기 `Future`의 완료 시점' 두 문장 원문 인용 + INFRA의 flush 대기 목록(숨김·새 버전 적용 500ms, 백업 취소), 백업 행·C-I4 갱신. **5.7** `CountingNoteStore`에 `flushGate`(끝나지 않는 `Completer`)·`emitStatus(PersistenceStatus)`. **9.1** `about_section_test`에 'flush 미완료(끝나지 않는 Completer) → `writeFailing` 문구 → 취소 → 버튼 다시 활성, 스낵바·시트 없음, errorLog 변화 없음, 뒤늦은 완료도 무시' 1건, `backup_export_test`에 취소 경우. **6.16** 안내서 04·**11절** 리스크 행 |
| INFRA-3-4 | 사소 | **8.1 B8-1** 비고: '`main.dart`의 `openNoteStore(const NoteStoreConfig())`(기본 상대 경로)는 임시 진입점 — 배포 없음(B1·B8 CI는 배포하지 않음), I5에서 `runNoteApp`·`defaultNoteStoreConfig`(`document.baseURI` 기준 절대 URL, 계약 7.2.12·7.4.3)로 교체' |
| INFRA-3-5 | 사소 | **8.3 G2**·V6 단락에 'V6 설정' 코드 블록: 테스트마다 다른 `databaseName`과 `WebStorageConfig.blobDatabaseName`(CORE 기본 `'noteapp_blobs'`, 02-core 4.8). `NoteStoreConfig`에 `copyWith`가 없으므로 `NoteStoreConfig(databaseName: …, ownerId: context.ownerId, web: WebStorageConfig(sqlite3WasmPath: context.web.resolveAppUrl(…), driftWorkerPath: …, blobDatabaseName: …))`를 직접 생성(필드 이름 = 02-core 4.8 생성자), 정리는 같은 config로 `deleteLocalNoteData`. **9.1** `app_smoke_browser_test` 행 같게 |
| INFRA-3-6 | 절차 | 이 13.3 표(지시 번호 그대로 인용), 머리 상태 줄 '**3차 수정 v0.4** · 계약 **v1.2**'. 계약 인용을 v1.2로: 1.2(계약 7.6 B1·B8 v1.2), 5.1(절 머리 '7.2.2 · 7.2.9 · 7.2.12 · 7.2.14 — v1.2 기준', 블록 표시 'v1.2 기준 원문 그대로', 7.2.9 v1.2 인용 추가), 6.2(규칙 표 머리 '계약 7.4.2 v1.2', R15 행·문단 v1.2 인용). 5.2~5.5 발췌 표시도 'v1.2 기준 원문 그대로'(시그니처 변경 없음 — 발췌의 모든 줄이 00-overview 7장 현재 본문에 그대로 있음을 줄 단위로 대조함) |

계약 v1.2 변경 항목(00-overview 7.9 C12-01~09)별 INFRA 영향

| 항목 | INFRA 영향 · 반영 |
|---|---|
| C12-01 | INFRA-3-1 |
| C12-02 | 없음 — INFRA는 `ChangeBatch`·`EntityChange`를 구독하지 않는다 |
| C12-03 | 없음(확인) — 5.5에 한 줄: 앱 셸은 `pageBackgroundBuildersProvider`를 읽지 않고 `InkPageThumbnail`도 쓰지 않음, 썸네일 연결(`pageThumbnailRendererProvider` ← `inkPageThumbnailRendererProvider`)은 그대로 |
| C12-04 | 없음(확인) — M4 `syncBadgeProvider` override의 `.distinct()`는 `SyncBadge` 값 동등(C11-13)에 기대고, `AuthUser` 값 동등은 SYNC 상태 클래스 쪽 보장. 5.5 7.2.20 발췌 표시에 메모 |
| C12-05 | 없음(확인) — SYNC T16(계약 스위트 C-01~C-25·순환 대조 추가)은 같은 명령 `ws test --run-skipped -t integration`(8.3 G2, 6.13 10단계)으로 돈다. 명령·태그 변화 없음 |
| C12-06 | INFRA-3-2 |
| C12-07 | 없음 — PDF 검색 하이라이트 색 예외. INFRA 테마(`buildAppTheme`)와 무관 |
| C12-08 | 8.1 머리 문단의 기반 단계 순서를 계약 7.6 v1.2 풀이대로(B3·B6·B7은 B2 뒤, B4·B5는 B3 뒤, main 커밋·완료 조건은 B2(T1~T5) 완료 뒤, B8은 B2~B7 뒤). INFRA의 B1은 B2보다 먼저라 영향 없음 |
| C12-09 | INFRA-3-3(백업 대기). 숨김 flush·새 버전 적용 flush는 이미 500ms 상한 — 5.1 C-I4에 근거 추가 |
| 보류 SYNC-CP7 | 1.3 M4 목록에 방향만 메모(SYNC 소유 선택 자리 `syncLogSinkProvider`, 기본 `null`, `SyncModule`이 override). 이름·모양은 M4 연결 계획 때 계약 7.3.3 반영을 따른다 — 이 계획서에 자체 시그니처를 두지 않음 |

자체 정리 (3차)

| 항목 | 반영 내용 |
|---|---|
| 검사기 픽스처 제외 | R15가 B1로 오면서 `tool/test/fixtures/`(일부러 위반·미해석 import·포맷 안 된 코드를 담은 가짜 작업 공간)가 B1부터 생긴다. 루트 `flutter analyze --fatal-infos`(계약 7.6 '모든 단계 후')와 R11·'dart format 변경 없음'(V2)이 이를 잡지 않게 6.2 `analysis_options.yaml` exclude에 `tool/test/fixtures/**`(B1-1), 4.3 `workspace_rules.yaml`에 `fixture_dirs: [tool/test/fixtures/]`(R11 제외), R11·G4·10절 7 문구, 9.1 `rules_test`에 'fixture_dirs 아래 포맷 안 된 파일 보고 안 함' |
| `dart test tool/test`를 B1·B8 완료 조건에 | 계약 7.6 B1 완료 조건(`ws check`·`ws test`)은 루트 `tool/test/`를 돌리지 않는다(멤버가 아님). INFRA는 B1 완료·B8-2에 `dart test tool/test`를 넣어 계약보다 엄격하게 진행하고, 계약 문구 정리를 **12.3 P6**(사소)로 제안 |
| 11절 리스크 | '태그를 변수로 넘겨 R15가 못 봄'(계약 7.4.8 v1.2 리터럴 규칙, `test_tags_test` 고정), 'CORE 쓰기 재시도 중 백업 대기가 끝나지 않음'(INFRA-3-3) 두 행 추가 |
| 상태 줄 | 머리말 상태를 '3차 수정 v0.4 · 계약 v1.2', 작성 기준일 2026-11-05로 |

### 13.4 최종 승인 (00-review '4차 검토' 4.4.1 · '최종 승인' · 통합 계약 v1.3→v1.4, 2026-11-05)

4차 검토에서 승인(재승인 조건 없음). 개발 착수 때 반영: **INFRA-4-1**(C13-01) 12.3 P6 결정 칸 = '승인 — 계약 v1.3 C13-01', 8.1 B1 완료·B8-2 인용 = '계약 7.6 B1·B8 v1.3'(동작 변경 없음). **INFRA-4-2**(C13-05) 머리 상태 줄 = '승인'·계약 인용 v1.4(v1.4는 기반 단계 뒤 C14-01 `SelectionGeometry` 이름 겹침 → `hide`/접두사, C14-02 R15 `tags:` 인식 수정 완료 — 시그니처 변경 없음). 본문의 개별 'v1.1/v1.2' 인용은 그 조항이 들어간 판을 가리키므로 그대로 둔다. 진행 기록은 [progress/infra.md](progress/infra.md).

### 13.5 1차 통합 뒤 (통합 계약 v1.5, 2026-11-05)

| 항목 | 반영 |
|---|---|
| C15-02 (계약 7.4.2 R6 해석) | 6.2 R6 행을 v1.5 문구로: 같은 플랫폼 파일끼리는 조건 없이 불러와도 되고, 패키지 진입점 `lib/<패키지>.dart`(`pdf_io.dart`)는 플랫폼 파일이 아니다(R4·R5·R6 공통). `ws check`는 I1부터 이 규칙이라 코드 변경 없음. 머리 계약 인용 = v1.5 |
