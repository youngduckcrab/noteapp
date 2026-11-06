# INFRA 진행 기록

## 요약

- 마지막 세션: **2차 기반 단계 R2-B2i**(아래 '## 2차' — 계획 docs/plans/m5-7/01-infra.md 8.1, 계약 v2.2 7.6.2) — 그 앞은 R2-B1.
- 다음 할 일: 동시 개발 R2-B8a → R2-B8b → J0(동시 개발 시작 조건 = R2-B1~R2-B6이 `main`에 있음).
- 1차: 기반 단계 B1(0bbebf8)·B8(2cec46a, eda674f), 통합 G1~G4 완료(아래). 1차 G5(푸시·CI)는 총괄이 끝냄 — 전체 CI 1회 실측 30분.

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| B1 | 기반 단계에서 완료 | 0bbebf8 | 워크스페이스·패키지 골격·`ws` 최소(list·check R1–R3·R7–R9·R15·test·analyze)·`ci.yml` 최소 |
| B8 | 기반 단계에서 완료 | 2cec46a, eda674f | 최소 라우터·자리표시 화면 연결, R15 `tags:` 인식 수정(계약 v1.4 C14-02) |
| I1 | 완료 | ac34ca7 | `tool/test/rules_test.dart`(R1–R13), `test_tags_test.dart`(회귀), `test_command_test.dart`(`--affected-since` 포함), `affected_test.dart`, `channel_id_test.dart`, `build_info_file_test.dart`, `web_finalize_test.dart`, `web_assets_test.dart`, `dart_imports_test.dart`, `flutter_runner_test.dart`(회귀), `hosting_config_test.dart`(`--isolate` 변환만 — I12에서 `firebase.json` 검사 추가). 새 명령: `affected`, `channel-id`, `build-info`, `finalize-web`, `web-assets verify\|fetch`, `hosting-config`; `check --no-format`·`--no-exports`(R14는 G3) |
| I2 | 완료 | baabeeb | `app/test/runtime/build_info_test.dart`, `runtime_info_test.dart` (계획서의 `test/build/` → `test/runtime/`, 아래 '계획과 다르게 한 점') |
| I3 | 완료 | 99d47c9 | `app/test/errors/app_error_log_test.dart`, `error_handlers_test.dart`(+`appErrorWidgetBuilder`), `diagnostic_report_test.dart`(6.7 형식 스냅숏·알 수 없음·8,000자·오류 5건·스택 15줄), `app_provider_observer_test.dart`. `StartupReport`·`StartupStep`·`StartupStepOutcome`(4.5.4)을 `src/bootstrap/startup_report.dart`에 먼저 만들었다(I5가 사용) |
| I4 | 완료 | d25743b | `app/test/web/web_platform_browser_test.dart`(Chrome 8건: 절대 URL, 404·시간 초과 → null, `pagehide`·`visibilitychange` 대응·구독 해제, standalone false, 내려받기 true, 공유 불가면 `unsupported`). `app/test/fakes/fake_web_platform.dart`(5.7). VM 스텁 사용은 I2 `test/runtime/runtime_info_test.dart`에서 |
| I5 | 완료 | 0aa54f0 | `app/test/bootstrap/app_bootstrapper_test.dart`(fake_async 21건), `overrides_unique_test.dart`, `bootstrap_app_test.dart`(+`runNoteApp`), `startup_error_screen_test.dart`(6.7 문구 표·가로/세로), `foundation_modules_test.dart`(임시 모듈). 가짜 `test/fakes/fake_app_module.dart`·`counting_note_store.dart`. I10·I10b에서 `overrides_unique_test`를 실제 모듈 3개로, `bootstrap_app_test`에 CoreModule 늦은 저장소 경우(`openCount == 2`가 `closeCount == 1` 뒤)를 더한다 |
| I6 | 완료 | 09cd0db | `app/test/routing/app_routes_test.dart`, `app_router_test.dart`(자리표시 화면: 인자·페이지 종류·라이브러리 State 유지·닫기·새로고침·NotFound·observers). B8 `foundation_routing_test.dart` → `test/routing/production_screens_test.dart`(`AppScreenBuilders.production()` 연결, `FoundationApp`·`foundationOverrides` 없이) |
| I7 | 완료 | d715ce0 | `app/test/app/note_app_test.dart`(material_ui `MaterialApp`·locale ko·seed `0xFF3949AB`·브리지 없음·라우터 provider dispose·셸 provider `name:`), `lifecycle_bridge_test.dart`(hidden·paused·detached·웹 hidden, 1초 안 반복 무시, dispose 뒤 없음). `builder`의 `UpdateBanner` 감싸기·그 테스트는 I8 |
| I8 | 완료 | f155981 | `app/test/update/update_checker_test.dart`(fake_async: 비활성 3경우·초기 5초·10분 주기·숨김 동안 없음·visible 60초 규칙·실패 4종 상태 유지·dismiss·applyUpdate flush → reload·500ms 상한·dispose), `update_banner_test.dart`(Available일 때만·버튼 2개·해요체·Overlay 없음·위 여백 이동·아래 State 유지). `note_app_test`에 `builder` = `UpdateBanner` 단언 |
| I9 | 완료 | b66f4e6 | `app/test/settings/settings_screen_test.dart`(제공 순서대로 머리글·본문 위치, 연속 `group` 머리글 1번(끊기면 다시), 닫기 → `onClose`, 내용 너비 ≤ 720 가운데·좁은 창 16 여백, 운영 섹션 세로·가로 넘침 없음 + '일반' 1번), `settings_sections_test.dart`(id 순서·그룹·제목·계약 위젯 타입·`app.account` 없음·provider 기본값), `storage_section_test.dart`(표시 값, 임시·단일 탭, 보일 때 `refreshCount` 1 → 다시 확인 2, 로딩 중 `storageInfoProvider` 값, 첫 프레임 저장 상태 줄, 연속 실패 ≥ 3 문구·마지막 오류, '다시 확인' 뒤 다른 `Consumer`의 `storageInfoProvider` 갱신(INFRA-2-5), await 중 닫기 → 예외 없음·다음 갱신 때 반영, 갱신 실패 문구), `about_section_test.dart`(표시 값·오류 목록 최근 5건, 네이티브, 진단 복사(Clipboard 모의)·스낵바, 라이선스 페이지, 새 버전 확인(비활성·최신·새 버전 → 새로고침 = flush 뒤 reload), 백업: 진행 줄·버튼 비활성 → 시트, 공유 버튼은 `canShareFiles`일 때만, 버튼 6경우 → 결과별 스낵바·errorLog, 시트 닫기 → 스낵바 없음, 내보내기 실패, **대기 취소(INFRA-3-3)**), `backup_export_test.dart`(flush → export 순서, 취소(flush 대기·export 대기) → 즉시 null·기록 없음·늦은 결과/오류 버림, 취소 2번, 미리 취소, 실패 기록, 파일 이름, deliver 7경우 + 공유가 같은 턴에 시작). `test/routing/production_screens_test.dart`를 `SettingsScreen`으로 |
| I10 | 완료 | 50d1300 | `app/test/modules/core_module_test.dart`(절대 URL·기본값·publish/override·flush·close·예외 전파·`canResetAfter` 표·reset 마지막 config·상태 오류 기록·늦은 저장소 close 1회(모듈 단독·부트스트래퍼·shutdown 2초 대기)·늦은 close 실패 기록·늦은 열기 실패), `pdf_module_test.dart`(실패 시 overrides 제외·기본 `pdfIoOverrides()`로 INK 배경 2개), `production_modules_test.dart`(id 순서·유일·새 인스턴스, 세 모듈 함께, `BootstrapApp` 기본 앱 → 라이브러리). `overrides_unique_test`를 실제 모듈로, `bootstrap_app_test`에 CoreModule 늦은 저장소 → 다시 시도(두 번째 open 때 늦은 저장소 `closeCount == 1`) |
| I10b | 완료 | d95a066 | `app/test/modules/feature_wiring_module_test.dart`(PDF 시작됨: 썸네일 렌더러 = INK 인스턴스·가져오기/내보내기 = 주입 함수 `identical`·메뉴 id 순서·`pdf.render` 섹션 3줄(B4 0 통계, 통계 provider override 없음)·기본 인자; PDF 실패: 두 자리 null·확장 빈 목록·섹션 없음·썸네일은 그대로; `overrides()` 순서), `pdf_wiring_test.dart`(`pdfMenuInvocationOf` 4필드·같은 `Rect`, `editorMenuItemFromPdf` id·label·icon·`onSelected` → `run`·`isEnabled` 변환, `editorExtensionsFromPdf`, `formatPdfRenderStats` 6.8 스냅숏, `PdfRenderStatsLines` 1초 100번 → ≤ 4번·dispose, 모듈 overrides만 넣은 컨테이너의 `pdfRenderStatsSection` 3줄·dispose). `overrides_unique_test`가 7.3.3 '이번' 행 전부 = 루트 overrides의 origin 집합임을 단언 |
| I11 | 완료 | f60b187 | `tool/test/web_files_test.dart`(manifest 필드·아이콘 4개 경로·실제 크기, index.html 문서·PWA/iOS 메타·CSP 없음·`html, body` CSS 11개·viewport 덮어쓰기·제스처 4종 `passive: false`·contextmenu 가드(입력 요소 예외)·로더(첫 프레임 제거, 30초·error·unhandledrejection → 새로고침), flutter_bootstrap.js 토큰 2개만·서비스 워커 없음+`unregister`·렌더러 선택·`wasmAllowList`, 아이콘 생성기: 크기·커밋된 PNG = 생성 결과(바이트 비교)·maskable 안전 영역·`--out`), `ws check` R13 0건(favicon 32×32), `app/test/web/app_boot_browser_test.dart`(Chrome 3건: 가짜 모듈 → `NoteApp` → 라이브러리 자리표시·`runtimeInfo.isWeb`, 필수 모듈 실패 → 시작 오류 화면, 운영 모듈 3개(CountingNoteStore) → `LibraryScreen`), `web_finalize_test`에 실제 빌드 모양(로더가 `serviceWorkerSettings`를 이름으로 가짐) 2건 + 커밋된 템플릿 확장 검사. 실제 `flutter build web` → `ws finalize-web` ok |
| I12 | 완료 | 4825da3 | `tool/test/hosting_config_test.dart`(커밋된 `app/firebase.json`: public·ignore·rewrites·no-cache·wasm MIME·COOP/COEP 없음·`--isolate`로만 추가·M4 키 없음, `hostingConfigProblems` 규칙별 위반, M4 모양 임시 픽스처의 rules/indexes 경로 존재·없으면 실패, `ws hosting-config` 위반 시 1), `web_assets_test.dart`(커밋된 `tool/web_assets.yaml` = 계약 7.4.9 두 항목, `app/web` 파일 크기·sha256 일치, `ws web-assets verify` 0), `ws check` R12·R15 0건, `ws web-assets fetch`로 두 파일 내려받아 커밋, `app/test/tool/prepare_web_test_test.dart`, 기본 `ws test --package noteapp`: VM 259 통과·1 건너뜀(`integration/app_smoke_test`), Chrome 준비 ok·11 통과·1 건너뜀(`app_smoke_browser_test`) |
| I13 | 완료 | af088b2 | `tool/test/workflows_test.dart`(42건: 워크플로 4개·이슈 템플릿 2개 존재·파싱, 잡별 `timeout-minutes`(25·30·25·45)·`permissions: contents: read`, 액션 버전 = 7.3 고정표, flutter-action `flutter-version-file: pubspec.yaml`·`cache: true`, `pub get --enforce-lockfile`만, `if`에 `secrets.` 없음, `steps.<id>`는 앞 단계만, 빌드 훅 캐시 3곳 같은 키, `flutter build` 4곳 `--release`·빌드 정보·실행 번호·`app/`, **워크플로의 `ws` 호출 19개를 실제 `ws` 인자 해석기로 `--help` 파싱**, `build-info` 채널 값, 배포 2곳 시크릿·변수 게이트·`firebaseToolsVersion: 15.34.2`·`disableComment`·repoToken 없음, **`run` 스크립트 전부 `bash -n`**; ci: 트리거·입력 2개·동시성·잡 env·6.13 1–17단계 순서와 명령·`fetch-depth: 0`·캐시 2종 키·준비 산출물 경로(앱 `.gitignore`와 대조)·main `check --strict`/브랜치 `--affected-since origin/main`·통합 단계 `inputs.integration`·채널·배포 `if`·요약·단계 시간 기록; android: main 푸시·Java 17·단계 순서·APK 아티팩트 7일·압축 0; web-experiment: 입력 2개·`--wasm`·격리(`hosting-config --isolate`·`--no-web-resources-cdn`)·`exp-wasm`; ios: 수동·변수 게이트·시크릿 4개·`ExportOptions.plist`·`CFBundleDisplayName`; 이슈 양식 입력 8개·필수 5개). 실제 GitHub 실행은 하지 않음(G5) |
| I14 | 완료 | 819ce39 | `tool/test/guides_test.dart`(21건: 3.7의 7개 파일만 있음, 상대 링크 대상 존재(안내서 7개 + 루트 README, 링크 검사 자체 확인), README 순서 01 → 02 → 04 → 03·05·06과 루트 README의 안내서 링크, 01–06 공통 형식(맨 위 '소요 시간'·'끝나면 Claude에게 알려줄 것', `##` 첫 제목 '준비물'·'확인 방법'·마지막 '문제 해결', '스크린샷을 보내 주세요', 합니다체·한다체 문장 끝 없음), 01 M4 위치 권장(`asia-northeast3`·`us-central1`·바꿀 수 없음·미확인)·`authDomain`·승인된 도메인, 02 `ci.yml`이 읽는 Secret·Variable 이름·워크플로 이름·요약의 'Firebase 미설정' 문장 글자 그대로·역할 4개·조직 정책, 03 Blaze 때만·요금을 멈추지 않음·50/90/100%·릴리스 10개, 04 미리보기 데이터 분리·임시·테스트 전용·홈 화면 앱 권장·백업 두 버튼과 대안·**인용한 화면 문구 22개 = `AppStrings` 값**·배너 문장·로더 문구 = `index.html`·백업 파일 이름 = `backupFileName`·9.3 체크리스트 1–17·18a·18b·19·20, 05 워크플로 이름·아티팩트 이름·APK 파일 이름·보관 일수 = `android.yml`, 06 초안 표시·워크플로 이름·Secret 4개·게이트 변수 = `ios-testflight.yml`) |
| I15 | 완료 | abe97df | 8.2 전체(9.1 표의 테스트 파일 전부 있음 — `export_names_test`만 G3) + `ws check` 0·`ws check --strict` 0 · `ws analyze` 0 · `dart test tool/test` 265 통과 · `ws test` 7개 멤버 통과(noteapp 259 통과·1 건너뜀 = `integration/app_smoke_test`) · `ws test --platform chrome` 4개 멤버 통과(noteapp 준비 ok·11 통과·1 건너뜀 = `app_smoke_browser_test`) · `dart format` 352개 변경 없음 · `ws build-info --channel preview` → `cd app && flutter build web --release --dart-define-from-file=../build/build_info.json`(wasm dry run 성공, 1분 37초) → `ws finalize-web` ok(`main.dart.js` 2,747,922 B · gzip 814,454 B)·`ws web-assets verify` 0·`ws hosting-config` 0. 계획서 6.13 '실측 항목' 표에 로컬 측정값을 적었다(GitHub 실측은 G5) |
| G1 | 완료 | 52de08c | `flutter pub get --enforce-lockfile`, `ws check --strict` 0. lock은 ink lab 등록·`analyzer` 직접 의존과 함께 한 번만 재생성(해석 버전 변화 없음) |
| G3 | 완료 | 52de08c | `tool/test/export_names_test.dart`, `ws check`(R1–R15) 0 |
| 통합 도구 | 완료 | 52de08c, d5938c6, 5adf710 | ink lab 멤버 등록(INFRA-O1)·`ws affected` 중첩 멤버, `android.yml` 개발 브랜치 푸시·안내서 05, `ws test` 멤버별 시간 제한·재시도·신호 처리 |
| G2 | 완료 | 3cf0b84 | `app/test/integration/app_smoke_test.dart`(V5)·`app/test/web/app_smoke_browser_test.dart`(V6, Chrome) 통과 — 3~8단계 공용 `app/test/support/smoke_scenario.dart`. 릴리스 빌드에서 찾은 라우팅 결함 2건 수정(`app_router_test`·`bootstrap_app_test` 경우 추가) |
| G4 | 완료 | 3cf0b84 | V1~V4: `ws check`(R1–R15)·`--strict` 0, 루트 analyze 0, `dart format` 변경 없음(R11), `ws test`·`ws test --platform chrome`·`dart test tool/test`, `flutter build web --release`, `ws web-assets verify` |
| G5 | 총괄·사용자 | | 푸시·CI·미리보기 배포·iPad 체크리스트(컨테이너 밖) |
| R2-B1 (2차) | 완료 | 3c77de3 | `tool/test/rules_test.dart`(R4 `Platform`·R16·2차 목록)·`chrome_fakemedia_test`·`heavy_lock_test`·`test_command_test`(잠금·`media` 래퍼)·`hosting_config_test`(`functions`·`emulators`)·`workflows_test`(시험 범위·`functions.yml`·수동 APK)·`repo_hygiene_test`·`workspace_test`(`functions/`)·`guides_test`(05), `packages/pencil_bridge/test/pencil_wire_contract_test.dart` |
| R2-B2i (2차) | 완료 | 59ed567 | `app/test/fakes/counting_note_store.dart`: `recordings`·`recordingDrafts`·`handwriting`·`search` → `inner` 위임 4줄(바탕 = CORE 계약 타입 커밋 `2b2e4b0`, R2-B2·R2-B7a와 한 묶음). INFRA 기존 시험 전부 |

## 변경 요청

- (통합 단계 2/2, 총괄에게) 계약 7.7 V5 문구 '획 1개 → 닫기 → 다시 열어 획 1개 유지 → **되돌리기 → 빈 페이지**'는 CORE 02-core 6.16(`noteSessionProvider` autoDispose — 에디터를 떠나면 세션·히스토리가 닫힘, '재진입 시 빈 히스토리', 승인된 설계)과 함께 성립하지 않는다(실제 CORE로 확인: 다시 연 뒤 되돌리기 버튼 비활성). INFRA V5는 '획 1개 → 되돌리기 → 빈 페이지 → 다시 실행 → 닫기 → 다시 열어 같은 획 1개 유지(새 세션은 되돌리기 없음)' 순서로 끝 상태를 모두 단언했다(01-infra 8.3 'G2 실행 순서'). 제안: V5 문구를 이 순서로 고치고, 04-editor 10장 7의 같은 문구도 함께.

## 의존성 요청

- 없음

## 계획과 다르게 한 점

- (세션 1, I1) R6: 플랫폼 파일(`*_native.dart`·`*_io.dart`)은 같은 플랫폼 파일(`*_native.dart`·`*_io.dart`, 웹은 `*_browser.dart`)을 조건 없이 import해도 된다(그 파일 자체가 조건부 절로만 불러와지므로 안전). 계획서 6.2 문구는 '조건부 절로만'.
- (세션 1, I1) R4·R5·R6의 접미사 판정에서 패키지 진입점 `<패키지>.dart`는 플랫폼 파일로 보지 않는다. `pdf_io/lib/pdf_io.dart`가 `_io.dart`로 끝나 `package:pdf_io/pdf_io.dart` import가 R6 위반으로 잡혔기 때문(오탐).
- (세션 1, I1) R12: `tool/web_assets.yaml`이 아직 없으면(I12에서 생김) 검사할 것이 없다(0건). R13: `icons/*-<n>.png`는 n×n, 이름에 크기가 없는 `favicon.png`는 정사각형만 확인한다(지금 favicon은 `flutter create`의 16×16). 32×32는 I11 `gen_icons` 뒤 `web_files_test`에서 확인한다.
- (세션 1, I1) R11은 `dart format`을 실행하는 비동기 검사라 `checkFormat()`으로 따로 두고 `ws check`가 함께 돌린다(`--no-format`으로 생략). 형식 대상은 `formatTargets()` = `app`·`packages`·`tool`의 `*.dart` 중 `generated_files`·`fixture_dirs`·`build/`·숨김 디렉터리 제외.
- (세션 1, I1) `ws check --no-exports`는 R14가 없는 지금은 아무 일도 하지 않는 옵션으로 받아 둔다(G3에서 R14와 연결).
- (세션 1, I1) `ProcessRunner.run`에 `echo`(기본 true) 인자를 더했다. git·`dart format` 출력은 화면에 흘리지 않고 모으기만 한다.
- (세션 1, I1) `channel-id`의 hash 입력 = `refs/heads/`를 뗀 브랜치 이름(소문자화·`claude/` 제거 전). `ws affected`·`--affected-since`의 변경 목록 = `git merge-base <ref> HEAD` 이후 커밋 + 작업 트리 변경 + 무시되지 않은 새 파일. `finalize-web` 필수 파일 = `index.html`·`flutter.js`·`flutter_bootstrap.js`·`main.dart.js`·`manifest.json`·`favicon.png`·`build_info.json` + `web_assets.yaml` 항목, 크기 줄에 gzip 크기도 적는다. `build-info --channel` 기본값 `local`.
- (세션 1, I4) `createWebPlatform()`은 `web_platform.dart`가 스텁/브라우저 파일을 조건부 `export … show createWebPlatform`으로 내보낸다(두 구현 클래스는 비공개). `shareFile`의 `AbortError` 판정은 오류 문자열로 한다(dart2js가 DOMException을 그대로 던짐 — 헤드리스 Chrome에서는 공유 API가 없어 미확인).
- (세션 1, I2) 계획서 3.4의 `app/lib/src/build/`·`app/test/build/`를 `src/runtime/`·`test/runtime/`으로 바꿨다. 루트 `.gitignore`의 `build/`, `analysis_options.yaml`의 `**/build/**`, `ws`의 `build` 디렉터리 건너뛰기가 모두 그 폴더를 빌드 산출물로 보아 커밋·분석·테스트에서 빠졌다. 파일 이름(`build_info.dart`·`runtime_info.dart`·`*_test.dart`)과 API는 그대로. `RuntimeInfo.rendererLabel`의 '네이티브'는 `AppStrings.rendererNative`. `BuildInfo`에 값 동등(`==`)을 더했다(JSON 왕복 테스트용). `isLocal` = `gitSha == 'local'`.
- (세션 1, I3) `installGlobalErrorHandlers(presentToConsole: true)`는 `FlutterError.presentError`로 콘솔에 출력하고, 이전 처리기가 그 기본 함수이면 다시 부르지 않는다(두 번 출력 방지). 그 밖의 이전 처리기는 기록 뒤에 호출한다. `AppErrorLog.clear()`는 `totalCount`를 유지한다. `add()`의 알림은 동기라서 이 로그를 듣는 위젯(I9 `AboutSection`)은 프레임 뒤에 setState해야 한다(빌드 중 오류 기록 가능). `appErrorWidgetBuilder`는 `Directionality`가 없는 곳(앱 위)에서도 그려지도록 감싼다. 진단 정보 문구(머리·줄 이름)는 `diagnostic_report.dart` 안의 상수, `AppStrings`에는 화면 문구만 둔다(`errorWidgetMessage`). 진단 정보의 저장소 줄은 `isDurable == false`일 때만 '임시 저장(새로고침하면 사라짐)'을 더하고, 용량은 1024 기준 `12.3MB`.
- (세션 2, I6) `LibraryRouteArgs`·`EditorRouteArgs`에 값 동등(`==`·`hashCode`·`toString`)을 더했다(테스트 비교용). B8의 `AppRoutes.folderIdParam`·`noteIdParam`(4.5.5에 없는 멤버)은 지우고 `app_router.dart`의 비공개 상수로 옮겼다. 라우트 인자 두 클래스는 `app_routes.dart`에 둔다(3.4에 따로 파일이 없음).
- (세션 2, I6) `AppScreenBuilders.production()`의 설정 라우트는 I9 전까지 `SettingsPlaceholderScreen(onClose: navigator.closeSettings)`. 무전환 페이지 두 종류에 `name: state.name`을 넣었다(observers·진단에서 라우트 이름이 보이도록 — go_router 기본 페이지와 같게). go_router는 끝 `/`를 떼므로 `/notes/`는 `/notes`로 보고 NotFound가 된다.
- (세션 2, I6) `AppScreenBuilders.placeholders()`의 라이브러리 자리표시는 제목 `library #<n>`(n = 그 State의 `initState` 일련번호, 전역 카운터)을 보인다. 테스트는 번호가 그대로인지로 '`initState` 1회'를 확인한다. 자리표시 화면에는 설정·뒤로 버튼(툴팁 `AppStrings.settings`·`back`)이 있어 스모크 빌드에서도 이동할 수 있다. 자리표시 본문 문구(`folderId: …`, `noteId: …`)는 개발용 영어.
- (세션 2, I5) B8 임시 진입(`buildFoundationRoot`·`foundationOverrides`·`FoundationStartupNotice`)을 지우고 `foundation_bootstrap.dart`를 **임시 모듈 `foundationModules({open, initializePdf})`**(core 20초 필수: `open(const NoteStoreConfig())`·publish·`noteStoreProvider`, 숨김 시 flush, stop 시 close / pdf 비필수: `initializePdfIo`·`pdfIoOverrides()` / featureWiring: 피처 두 패키지 override)로 바꿨다. `runNoteApp()`의 기본 bootstrapper는 I10 전까지 이 목록을 쓴다(I10에서 `productionModules()`). `main.dart`는 이제 `runNoteApp()`만 부른다. `BootstrapApp`의 기본 `appBuilder`는 I7 전까지 `FoundationApp`(I7에서 `NoteApp` + `AppLifecycleBridge`로 감쌈).
- (세션 2, I5) `BootstrapFailure.offersReload`는 '`newerSchema`인가'만 보고, '웹에서만'은 `BootstrapApp`이 `web.isSupported`일 때만 `onReload`를 넘겨 맞춘다(VM 테스트에서 `FakeWebPlatform(isSupported:)`로 확인하려고 — `kIsWeb`이면 VM에서 참 경우를 시험할 수 없음).
- (세션 2, I5) `AppBootstrapper`: 필수 모듈 실패는 `errorLog`에 1건(source bootstrap, `fatal: true` — 진단 정보에 보이도록), 비필수 실패·시간 초과는 source module 1건. 필수 모듈의 시간 초과 결과는 `timedOut`(`failedCritical` 아님). `start` 성공 뒤 `overrides()`가 던지면 그 모듈의 시작 실패로 보고 그 모듈을 stop한다. `canResetAfter`는 `resetLocalData`가 있을 때만 묻는다. `shutdown()`은 한 번만 돌고(같은 Future), 진행 중인 `run()`을 먼저 기다린다. 늦은 정리 2초 대기는 취소되는 Timer로 한다(위젯 테스트의 남은 타이머 방지).
- (세션 2, I5) `BootstrapApp`: '다시 시도'는 shutdown 동안 스플래시를 보이고, '데이터 지우기'는 shutdown·`resetLocalData` 동안 오류 화면을 그대로 둔다(실패 문구를 그 화면이 보이도록). `resetLocalData` 실패는 `errorLog`(source bootstrap, details `resetLocalData failed`) + 오류 화면 스낵바. `BootstrapApp`이 dispose되면 `shutdown()`을 부른다. 스플래시·오류 화면은 `MaterialApp(locale: ko)` 안(테마는 I7에서 `buildAppTheme`).
- (세션 2, I5) `SplashView`(StatelessWidget)는 비공개 상태 위젯을 두어 단계 라벨이 바뀐 뒤 지난 초(1초 주기 Timer)를 '(n초)'로 보인다.
- (세션 2, I5) `providers.dart`는 4.5.10의 9개를 먼저 만들었다(`latestStorageInfoProvider`는 I9). 셸 overrides 6개(`buildInfoProvider` … `appBootstrapperProvider`)는 `BootstrapSuccess.overrides` 맨 앞.
- (세션 2, I5) 가짜: `FakeAppModule`에 5.7 목록 밖의 `startTimeout`·`hiddenError`·`stopDelay`·`stopError`·`onStart`(시작 때 context 확인·publish)·`events`(공유 순서 기록)·`overridesCalls`·`resetQueries`를 더했다. `CountingNoteStore`에 `exportCount`·`hasStatusListeners`를 더했다. `NoteStore.clock`의 `Clock`은 note_core가 내보내지 않아(앱 의존성에 `clock` 없음) 타입을 추론에 맡기고 `// ignore: always_declare_return_types`.
- (세션 2, I5) B8의 `app/test/foundation_startup_test.dart`를 지우고 `test/bootstrap/foundation_modules_test.dart`로 옮겼다(임시 모듈 + `BootstrapApp` 기본 경로).
- (세션 2, I7) `NoteApp`의 `builder: (context, child) => UpdateBanner(child: child!)`는 `UpdateBanner`가 생기는 I8에서 넣는다(그 단언도 I8의 `note_app_test`에). `BootstrapApp`이 성공 화면을 `AppLifecycleBridge`로 감싸고 기본 `appBuilder`는 `NoteApp`이다. B8 `FoundationApp`은 지웠다. `AppStrings`는 작업마다 자기 문구를 더한다(설정·저장 공간·앱 정보·백업·업데이트 문구는 I8·I9).
- (세션 2, I7) `AppLifecycleBridge`의 '초당 1회'는 첫 신호를 바로 보내고 그 뒤 1초 동안 오는 신호를 버리는 방식(throttle)이다. `notifyAppHidden()`은 던지지 않으므로 결과를 기다리지 않는다.
- (세션 3, I8) `UpdateChecker`는 시간을 벽시계가 아니라 Timer로만 잰다(앱 의존성에 `clock`이 없어 fake_async가 `DateTime.now()`를 못 바꿈): '마지막 확인 뒤 60초'는 확인을 시작할 때 켜는 `minGapOnResume` Timer가 살아 있는지로 본다(실패한 확인도 '확인'으로 센다). `UpdateUpToDate.checkedAt`만 `DateTime.now()`. 첫 확인 전(`initialDelay` Timer 대기 중)의 `visible`은 확인하지 않는다(초기 Timer가 곧 확인). 첫 확인 때 숨김이면 건너뛰고 다음 `visible`에서 확인한다. `checkNow()`는 비활성이면 아무것도 안 하고, 진행 중인 확인이 있으면 그 Future를 돌려준다. `applyUpdate()`는 중복 탭을 무시하고, `appBootstrapperProvider`가 없는 컨테이너에서도(예외를 잡아) 새로고침한다. dispose 뒤 끝난 fetch는 `ref.mounted`로 버린다.
- (세션 3, I8) `UpdateBanner`는 배너 유무와 관계없이 `Column[배너?, Expanded(key)]` 모양을 유지해 아래 Navigator의 State가 그대로다. 배너가 보이는 동안 위쪽 안전 영역은 배너가 받고(`SafeArea(bottom: false)`), 아래 화면에는 `MediaQuery.removePadding(removeTop)`. 배너 색은 `colorScheme.surfaceContainerLow`(M3 기본값과 같음, `elevation: 0` → 아래 구분선), 앞에 `Icons.system_update_alt`. 문구는 `AppStrings.updateAvailable(buildNumber, shortSha)`·`AppStrings.later`(새로고침은 기존 `AppStrings.reload`).
- (세션 3, I8) 가짜 `FakeWebPlatform`에 `fetchDelay`·`hasVisibilityListener`를 더했다(5.7 목록 밖).
- (세션 3, I10) `productionModules()`의 세 번째 모듈은 I10b 전까지 임시 `StaticOverridesModule(id: 'featureWiring', label: '화면 연결 중', overrides: [...featureEditorOverrides(), ...featureLibraryOverrides()])`(기반 단계와 같은 연결, `critical` 기본값 true). I10b에서 `FeatureWiringModule()`로 바꾼다. `foundation_bootstrap.dart`(임시 `foundationModules`)와 `test/bootstrap/foundation_modules_test.dart`는 지웠고 그 시나리오는 `production_modules_test`로 옮겼다. `runNoteApp()` 기본값은 `productionModules()`.
- (세션 3, I10) `CoreModule`·`PdfModule` 생성자는 Dart의 비공개 이름 매개변수(`this._open` → 이름 `open`)로 계획서 시그니처의 공개 이름(`open`·`deleteLocalData`·`configFor`, `initialize`·`pdfOverrides`)을 그대로 유지한다. `overrides()`는 시작 전·늦은 저장소면 `StateError`. `resetLocalData`는 항상 있는 함수이고 시작 전에 부르면 `StateError`(부트스트래퍼는 `canResetAfter`가 참일 때만 넘긴다).
- (세션 3, I10) 상태 구독 해제는 `cancel()`을 부르고 그 Future를 기다리지 않는다(부른 뒤로는 이벤트가 오지 않음). CORE 가짜 저장소의 broadcast 구독 `cancel()`은 루트 zone의 완료된 Future를 돌려줘 fake_async(위젯 테스트)에서 끝나지 않으므로, 기다리면 `stop()`이 2초 제한까지 막혔다. 계획서 '구독 취소 후 `store.close()`' 순서는 지킨다.
- (세션 3, I10) 저장 오류 기록: 요약 `note_core write failed (consecutiveFailures: n): <오류>`, 기록 시각은 `lastErrorAt`(없으면 지금). 상태 스트림 자체 오류도 source module로 기록. 시간 초과와 같은 턴에 시작이 끝나 이미 publish된 저장소도 `onStartAbandoned`가 구독 해제 후 닫는다.
- (세션 3, I10) `overrides_unique_test`의 `PdfModule`은 계획서 5.4의 '가짜 `pdfOverrides`' 대신 실제 `pdfIoOverrides()`(기본 인자)를 쓴다 — 운영 목록에서 중복을 찾는 것이 목적이라서. `initialize`만 빈 함수. 가짜 `fake_note_store_opener.dart`: `fakeOpenNoteStore(...)`는 `FakeNoteStoreOpener`(호출 가능 객체, `openCount`·`lastConfig`·`configs`)를 돌려주고 `CoreModule(open: opener.call)`로 넘긴다. `RecordingLocalDataEraser`는 `calls`·`error`·`delay`.
- (세션 3, I10b) `productionModules()` = `[CoreModule(), PdfModule(), FeatureWiringModule()]`(임시 featureWiring 제거). `FeatureWiringModule` 생성자도 비공개 이름 매개변수로 공개 이름(`importPdf`·`exportPdf`·`moreMenuActions`·`addPageActions`)을 유지한다. PDF가 시작되지 않았으면 `moreMenuActions()`·`addPageActions()`를 부르지 않는다.
- (세션 3, I10b) `PdfRenderStatsLines`는 통계가 바뀌면 `minInterval`(250ms) Timer를 걸고 그 Timer가 끝날 때 마지막 통계로 다시 계산한다(뒤쪽 throttle — 1초에 최대 4번, 앞쪽 즉시 갱신은 하지 않음). 줄이 같으면 알리지 않는다. `formatPdfRenderStats`의 MB는 1024×1024 기준 소수 한 자리, 0이면 `0`(6.8 예시의 '초과 0 MB'와 맞춤), ms는 반올림 정수. `editorExtensionsFromPdf`의 두 목록은 수정 불가 목록.
- (세션 3, I10b) 가짜 `test/fakes/fake_pdf_actions.dart`: `FakePdfActions`(`importPdf`·`exportPdf` 함수 객체 하나씩 — `identical` 비교용, `action(id, withIsEnabled:)`, `moreMenuActions()`·`addPageActions()`, 기록 `importFolders`·`exports`·`runs`·`enabledChecks`).
- (세션 4, I9) `SettingsScreen`: 닫기 버튼은 `Icons.close`(툴팁 `AppStrings.close`). 좁은 `ListView` 대신 화면 전체 `ListView`에 좌우 여백 `max(16, (너비 − 720) / 2)`를 줘 어디서나 스크롤된다. 그룹 머리글은 바로 앞 항목과 `group`이 다를 때 보인다(끊겼다 다시 나오면 다시 보임). 섹션 본문은 `KeyedSubtree(key: ValueKey(entry.id))`, 머리글은 `ValueKey('settings-header-<id>')`. B8 `SettingsPlaceholderScreen`·`AppStrings.settingsPlaceholder`는 지웠다(`placeholders()`의 설정 자리표시는 그대로).
- (세션 4, I9) `StorageSection` 행: 저장 방식(한국어 + `backend.name`)·데이터 보존·여러 탭·영구 보관·사용량·부족한 브라우저 기능·저장 대기·마지막 저장(시각 + 지연)·연속 실패·(있으면) 마지막 오류. 연속 실패 ≥ 3이면 셸 문구 `AppStrings.storageWriteFailing`(계약 7.4.5 배너 고정 문장과 다른 문장 — 배너는 LIBRARY·EDITOR 몫). 갱신이 실패하면 `storageInfoProvider` 값을 보이고 '저장 공간 정보를 다시 읽지 못했어요.'를 더한다. '다시 확인'은 갱신 중 비활성(작은 진행 표시).
- (세션 4, I9) `AboutSection`: `ref.listen(latestStorageInfoProvider)`로 그 provider를 살려 둬 '진단 정보 복사'가 **await 없이** 최신 `StorageInfo`(없으면 `storageInfoProvider`)로 문장을 만들고 바로 클립보드에 쓴다(Safari 사용자 활성화). `persistenceStatusProvider`·`storageInfoProvider`는 백업 대기 중에만 watch(지연 문구 판단). 오류 목록은 최근 5건(최신 위), `AppErrorLog` 알림은 프레임 뒤 setState. 새 버전: `UpdateDisabled`면 버튼 비활성 + 문구, `UpdateAvailable`·`UpdateDismissed`면 '새로고침' 버튼(`applyUpdate`). 섹션이 dispose되면 백업 대기를 취소한다(아무것도 안 띄움). 시트 결과가 `unsupported`여도 시트는 닫히고(4.5.8 'Closes with the outcome') 스낵바가 다른 방법을 안내한다 — 다시 '백업 내보내기'를 누른다.
- (세션 4, I9) `prepareBackup`: flush 대기 중 취소되면 `exportBackupJson()`을 부르지 않는다. 기본 파일 이름 시각은 내보내기가 끝난 때. 실패 기록 details는 `prepareBackup failed`·`deliverBackup failed`. `deliverBackup`은 첫 `await` 전에 `shareFile`·`downloadBytes`를 부른다(같은 탭 턴 — 테스트로 확인). `BackupReadySheet`(StatelessWidget)는 비공개 상태 위젯으로 전달 중 두 버튼을 비활성화한다. 버튼 키 `backup-share`·`backup-download`, 앱 정보 버튼 키 `about-*`.
- (세션 4, I9) `AppStrings`에 숫자 형식 도우미 `groupDigits`(천 단위 쉼표)·`bytes`(1024 기준 `12.3MB`)를 static 멤버로 뒀다(공개 최상위 이름을 늘리지 않으려고). `DiagnosticReport` 안의 같은 비공개 함수는 그대로 둔다.
- (세션 4, I9) 가짜 `CountingNoteStore`에 5.7 목록 밖의 `refreshGate`·`refreshError`(갱신 대기·실패)·`exportGate`(export만 대기 — export 대기 중 취소 경우)를 더했다. 설정 테스트 공용 준비는 `app/test/support/settings_harness.dart`(`SettingsHarness.overrides()`·`pump()`, `useIpadView`, `sectionPage`). `production_screens_test`는 설정 화면의 앱 정보 섹션 때문에 `appErrorLogProvider`·`startupReportProvider`를 override한다.
- (세션 4, I11) `finalize-web`의 `serviceWorkerSettings` 검사를 빌드된 `flutter_bootstrap.js` 중 **`_flutter.buildConfig = …` 줄 뒤(앱 몫)**에만 한다(`bootstrapAppScript()`, `tool/src/web_finalize.dart`). `{{flutter_js}}`로 들어가는 Flutter 로더가 자기 `load({serviceWorkerSettings:e,…})` 시그니처에 그 이름을 가져, 실제 빌드가 I1의 단순 문자열 검사에 걸렸다. 표시줄이 없으면(템플릿 빌드가 아님) 전체를 본다.
- (세션 4, I11) index.html: 처음부터 고정 viewport 메타를 두고, 엔진이 넣는 메타(`flt-viewport`)는 `MutationObserver`가 덮어쓴다 — 헤드리스 Chrome으로 릴리스 빌드를 띄워 덮어쓴 content·첫 프레임 뒤 로더 제거·`flt-renderer="canvaskit"`을 확인했다(로컬 CanvasKit으로 바꾼 사본, 커밋 안 함). 로더 상태 문구는 '불러오는 중…' → '엔진 준비 중…' → '앱 시작 중…'(마지막은 계획서 밖). 새로고침 버튼은 전역 `window.noteappReload()`. 30초 문구 '30초 안에 앱이 시작되지 않았어요.'. 로더 색은 index.html 안의 리터럴(웹 파일이라 `colorScheme` 규칙 밖). CDN CanvasKit을 막은 오류 경로는 헤드리스 가상 시간으로 재현되지 않아 실측하지 않았다(문자열 검사만).
- (세션 4, I11) manifest.json에 `description`·`prefer_related_applications: false`를 더했다. `gen_icons.dart`: 1024 원본에 그린 뒤 `copyResize(average)`로 줄이고, 펜 획은 원을 찍어 그린다(굵은 `drawLine` 안티에일리어싱 줄무늬 회피). `--out <dir>` 옵션. 아이콘을 바꾸면 `dart run tool/gen_icons.dart`로 다시 만들어 커밋한다(`web_files_test`가 바이트 비교). 세션 1 메모의 favicon 16×16은 32×32가 됐다.
- (세션 4, I12) `ws hosting-config`가 출력 전에 `hostingConfigProblems()`(6.12 표: public `build/web`, `**` → `/index.html` 재작성, `**` no-cache, `**/*.wasm` `application/wasm`, COOP/COEP 없음, M4 `firestore.rules`·`firestore.indexes`·`storage.rules` 경로가 `app/` 기준으로 존재)를 검사하고 위반이 있으면 종료 1(4.2 표는 0만). M4 픽스처는 B1 관례대로 커밋하지 않고 테스트가 임시 작업 공간(`FixtureWorkspace.clean`)에 쓴다(`tool/test/fixtures/firebase_m4/` 없음).
- (세션 4, I12) `.gitattributes`에 `app/web/drift_worker.js -text`(sha256으로 검사하는 파일이라 줄 끝 변환 금지)를 더했다. `app/.gitignore`는 `flutter create` 기본 + `/test/web/sqlite3.wasm`·`/test/web/drift_worker.js`. `app/tool/prepare_web_test.dart`는 `prepareWebTest(appDir)` 함수를 두고 `app/test/tool/prepare_web_test_test.dart`가 시험한다.
- (세션 4, I12) 완료 조건의 '기본 `ws test`에서 건너뜀'을 확인하려고 **G2 몫인 스모크 테스트의 뼈대**를 미리 썼다: `app/test/integration/app_smoke_test.dart`(V5 1–3·9단계: 실제 모듈 3개 + `NoteStoreConfig(inMemory: true)` → `NoteApp`, overrides origin 유일, `nativeMemory`·`notDurable`, 라이브러리 배너 고정 문장) · `app/test/web/app_smoke_browser_test.dart`(V6 1–3·9: 실행마다 다른 DB·blob DB 이름(`smokeConfigFor`), 배너는 `storageWarningOf` 결과에 맞춤, shutdown 뒤 `deleteLocalNoteData`) · `app/test/support/contract_strings.dart`(계약 7.4.5 두 문장). 이 작업 트리의 CORE는 자리표시라 이 두 파일은 돌려 보지 못했다(분석·컴파일만 확인). 4–8단계(새 노트·에디터 배너·획·다시 열기·되돌리기)는 실제 화면의 라벨을 알아야 해서 G2에서 더한다. 실제 I/O를 기다리는 부분은 `tester.runAsync` 반복(최대 10초·20초)으로 썼다 — G2에서 실측해 조정.
- (세션 1) 계약 v1.3 C13-05 절차: 계획서 머리 상태 줄 '승인'·계약 인용 v1.4, 12.3 P6 결정 칸·8.1 B1 완료/B8-2 인용(INFRA-4-1), 13.4 '최종 승인' 한 줄(INFRA-4-2). 본문 개별 조항의 v1.1/v1.2 인용은 그 조항이 들어간 판이라 그대로 뒀다.
- (세션 5, I13) `ci.yml`: 6.13 1–17단계에 B1의 '도구 테스트'(`dart test tool/test`, 계약 7.6 B1 v1.3·V3)를 8단계 뒤에 그대로 두었다. main/브랜치 분기(6·8·9단계)는 같은 명령의 두 단계를 `if: github.ref ==`/`!=`로 나눴다. 통합 단계(10)도 VM·Chrome 두 단계. 맨 앞에 **'Start clock' 단계**를 더하고, 시간이 드는 `run` 단계마다 끝에 `printf '%s %s\n' "$SECONDS" '<라벨>' >> "$RUNNER_TEMP/step-seconds"`를 둬 17단계 요약이 단계별 시간 표(준비(체크아웃·Flutter·캐시)·배포 포함)를 보인다(GitHub가 단계 시간을 다음 단계에 주지 않아서). `main.dart.js` 크기는 15단계 `finalize-web`이 같은 요약에 이미 쓴다. 요약의 주소 줄: 배포 성공 → `details_url`, 시크릿·변수 없음 → 'Firebase 미설정 — docs/guides/02-github-secrets.md', 수동 실행 `deploy=false` → '배포하지 않음', 실패 → '배포 실패'. 빌드 라벨은 `jq`로 `BuildInfo.displayLabel`과 같은 모양. 채널 단계(`id: channel`)는 `id`(Hosting 채널)와 `build`(build-info 채널: main `live`, 그 밖 `preview`)를 출력한다.
- (세션 5, I13) `android.yml`: 6.13에 없는 `concurrency`(`android-<ref>`)와 업로드 `if-no-files-found: error`를 더했다. `build-info --channel`은 main이면 `live`, 아니면 `preview`(웹 밖에서는 새 버전 확인이 꺼져 있어 표시용). 6.14 서명(키스토어 시크릿)은 '태블릿 보유 확인 후'라 넣지 않았다(debug 키 그대로). `web-experiment.yml`: `concurrency: web-experiment`, `wasm=false`면 `--no-wasm-dry-run`, `build-info --channel experiment`, 격리면 `ws hosting-config --isolate` 결과로 `app/firebase.json`을 바꾼 뒤 빌드, 요약 단계. `ios-testflight.yml`(초안, 미검증): `build-info --channel live`, p8은 `$RUNNER_TEMP`에 쓰고 마지막에 지움, `ExportOptions.plist`의 `teamID`는 빈 값으로 커밋하고 CI가 `plutil -replace`로 채운다. 6.15대로 `app/ios/ExportOptions.plist`를 더하고 `Info.plist`의 `CFBundleDisplayName`을 `필기노트`로 바꿨다.
- (세션 5, I13) 이슈 양식 `feedback.yml`은 `labels`를 두지 않았다(저장소에 없는 라벨일 수 있음). 필수: 기기·앱 버전·무엇을 했나요·기대한 동작·실제 동작. `workflows_test`는 B1의 '배포·시크릿 없음' 검사를 지우고 6.13 표 전체로 바꿨다. 워크플로 안 `ws` 호출은 셸 변수(`$BUILD_CHANNEL`·`$GITHUB_REF_NAME`)를 견본 값으로 바꿔 실제 `runWs([..., '--help'])`로 해석한다(옵션 이름·허용 값 오류를 잡음). actionlint는 컨테이너에 없어 쓰지 않았다.
- (세션 5, I14) 안내서 문체·형식: 맨 위 굵은 목록 두 줄('소요 시간'·'끝나면 Claude에게 알려줄 것') 뒤 `## 준비물`(6.16의 '준비물'을 제목으로), 본문 `## 따라 하기`의 `### n단계`, 끝에 `## 확인 방법`·`## 문제 해결`(표). 콘솔 메뉴 이름은 기억 기반이라 모든 안내서 문제 해결 표 끝에 '화면이 안내서와 달라요 → 스크린샷을 보내 주세요'. 04는 9.3 체크리스트를 '확인 방법' 표로 옮겼고(20번은 '그때 안내'), 피드백 양식 파일로 상대 링크를 건다. 6.16 표에 없는 것: 04의 '먼저 알아 둘 것' 절, 펜슬 종류 확인('설정 → Apple Pencil'은 단서만), 05의 Play 프로텍트·32비트 항목, 06의 실행 1회 약 150분 안내. 06은 초안 표시와 함께 App Store Connect 메뉴 이름(통합 → App Store Connect API → 팀 키)을 기억으로 적었다.
- (세션 5, I14) 워크플로 `name:`을 안내서에 보이는 이름으로 바꿨다: `CI`·`Android APK`·`Web experiment`·`iOS TestFlight`(6.16의 'Actions → CI'·'Actions → Android APK'와 맞춤 — 파일 이름·동시성 그룹은 그대로). 루트 `README.md`에 안내서·`ws` 줄을 더했다.
- (세션 5, I15) 계획서 6.13 '실측 항목' 표 세 줄을 채웠다(B8 결과 보고의 로컬 측정값 + I15 측정값, GitHub 실측은 G5·Chrome 첫 `openNoteStore`는 G2). 10장 1의 'B8 실측값이 6.13 표에 기록됨'은 로컬 값으로만 채운 상태다.

- (통합 단계 2/2, G2) V5 순서: 계획서 8.3의 7(닫기·다시 열기) → 8(되돌리기)을 8 → 7로 했다(위 '변경 요청' — 히스토리는 세션과 함께 닫힘). 8에 '다시 실행'을 더해 같은 획 id가 돌아오는지도 본다.
- (통합 단계 2/2, G2) V5·V6의 3~8단계는 한 파일(`app/test/support/smoke_scenario.dart`)에 두고 두 테스트가 배너 기대값(V5 1개, V6 `storageWarningOf`에 따라)만 달리 준다. 화면 조작은 보이는 문구·접근성 라벨(`SmokeLabels`: '새 노트'·'만들기'·'제목 없는 노트'·'뒤로'·'되돌리기'·'다시 실행')로 찾는다 — 각 패키지의 문구 상수는 `src/` 아래라 앱 테스트가 import하지 않는다(R7).
- (통합 단계 2/2, G2) 저장소 읽기는 `tester.runAsync`가 아니라 `settle()`(작업을 테스트 영역에서 시작하고 실제 시간을 흘리며 pump)로 한다: 저장소는 부트스트래퍼가 위젯 테스트의 fake-async 영역에서 열었으므로 웹에서는 Web Worker 응답이 그 영역에서 처리돼 pump해야만 진행된다 — `runAsync` 안에서 기다리면 끝나지 않았다(V6 첫 실행이 4단계에서 멈춘 원인).
- (통합 단계 2/2, G2) 계획서 6.4·6.6에 없던 라우팅 설정 2가지를 더했다(아래 '통합 단계 2/2 — 릴리스 빌드에서 찾은 결함'): `GoRouter.optionURLReflectsImperativeAPIs = true`, 스플래시·오류 화면 틀의 Navigator가 엔진에 라우트를 보고하지 않음. 계획서 6.4·6.6에 적었다.

## 다음 세션 메모

- 세션 1 끝 상태: `ws check`(R1–R13·R15) 0, 루트 `flutter analyze --fatal-infos` 0, `dart test tool/test` 182건, `ws test` 7개 멤버 통과(noteapp VM 38건), `ws test --package noteapp --platform chrome` 8건 통과.
- 이미 있는 앱 셸 조각: `src/web/`(WebPlatform), `src/runtime/`(BuildInfo·RuntimeInfo), `src/errors/`(AppErrorLog 등·DiagnosticReport), `src/bootstrap/`(AppModule·AppBootstrapper·BootstrapApp·SplashView·StartupErrorScreen·`runNoteApp`·임시 `foundationModules`), `src/routing/`(I6 전부), `src/providers.dart`(9개), `src/app/`(NoteApp·buildAppTheme·AppStrings·AppLifecycleBridge). (세션 4: B8 임시 이름 `SettingsPlaceholderScreen`은 I9에서 지움 — 이제 `src/settings/` 전부.)
- (세션 2) 5.7은 자리표시 화면에 `Key('open-note')` 같은 콜백 버튼을 적었는데 I6 자리표시는 설정·뒤로 버튼(툴팁)만 있다. I11 `app_boot_browser_test`에 필요하면 그때 더한다.
- (세션 2) 세션 2 끝 상태: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 앱 VM 132건, 앱 Chrome(`flutter test --platform chrome test/web`) 8건, `dart test tool/test` 182건, I5 뒤 `cd app && flutter build web --release --no-wasm-dry-run` 성공(55초).
- 가짜: `app/test/fakes/fake_web_platform.dart`. `FakeAppModule`·`CountingNoteStore`(I5), `fakeOpenNoteStore`·`RecordingLocalDataEraser`(I10)는 있다. 가짜 PDF 동작 `FakePdfActions`(I10b)도 있다.
- (세션 4에서 해결) `app/dart_test.yaml`은 I12에서 생겼다 — 태그는 `integration`만.
- 앱 폴더 이름에 `build`를 쓰지 않는다(`.gitignore`·분석 제외·`ws`가 빌드 산출물로 본다).

- (세션 3) 세션 3 끝 상태: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 앱 VM 211건, 앱 Chrome(`test/web`, 바뀌지 않음) 8건, `cd app && flutter build web --release --no-wasm-dry-run` 성공(47초, `main.dart.js` 2,605,325 B). `modules/` 전부(CoreModule·PdfModule·FeatureWiringModule·pdf_wiring)가 웹 빌드에 들어간다.
- (세션 3, I9에서 처리됨) I9 메모: 설정 라우트는 아직 `SettingsPlaceholderScreen`. `AboutSection`의 '새 버전 확인'은 `updateCheckerProvider.notifier.checkNow()`(비활성이면 아무것도 안 함 — 버튼을 숨기거나 상태 문구로 `UpdateDisabled` 표시), 상태 표시는 `updateCheckerProvider` 값. `UpdateUpToDate.checkedAt`이 있다. CORE 가짜 저장소의 broadcast `cancel()` Future는 fake_async 위젯 테스트에서 끝나지 않으니 구독 해제를 기다리지 않는다(I10 메모).
- 환경: `export PATH=/opt/flutter/bin:$PATH CHROME_EXECUTABLE=/usr/local/bin/chrome-nosandbox`, `ws` = `dart run tool/ws.dart`.
- 다른 영역 구현은 이 작업 트리에서 기반 단계 자리표시다. CORE `createFakeNoteStore()`와 계획서 5.7의 가짜로 개발한다.

- (세션 4) 세션 4 끝 상태: `ws check`(R1–R13·R15) 0, 루트 `flutter analyze --fatal-infos` 0, `dart test tool/test` 212건, `ws test --package noteapp` VM 259 통과·1 건너뜀, `ws test --package noteapp --platform chrome` 준비 ok·11 통과·1 건너뜀, `cd app && flutter build web --release --no-wasm-dry-run` 성공(약 55초, `main.dart.js` 2,747,922 B · gzip 814,454 B — 설정 화면으로 +142 KB), 그 결과에 `ws finalize-web` ok(두 웹 자산 포함)·`ws hosting-config` 0.
- (세션 4) I13 메모: `tool/test/workflows_test.dart`와 `.github/workflows/ci.yml`은 B1 최소판이 있다. 6.13 표(트리거·동시성·시간 제한·캐시 2종 `actions/cache@v6` 키 `hashFiles('pubspec.lock'`·브라우저 테스트·`inputs.integration`·main `check --strict`·배포 `if` 시크릿 조건·`firebaseToolsVersion` 고정·iOS 변수 게이트·android `retention-days`)를 채운다. CI의 Chrome 단계는 `ws test --platform chrome`이 멤버의 `tool/prepare_web_test.dart`를 먼저 돌린다(앱에 생김). 배포 전 `ws web-assets verify`·`ws finalize-web`(이제 `sqlite3.wasm`·`drift_worker.js`도 필수 파일). 실제 푸시·배포 실측은 하지 않는다.
- (세션 4) I14 메모: 안내서 04에 설정 → 저장 공간('영구 보관' 행)·앱 정보(빌드 라벨·'새 버전 확인'·'진단 정보 복사')·백업 내보내기(시트 [내려받기] / [공유 · 파일에 저장], 만드는 중 '저장이 늦어지고 있어요…' → [취소]) 문구는 `AppStrings`(app/lib/src/app/strings.dart)와 같게 쓴다.
- (세션 4) 앱 테스트에 이제 태그를 쓸 수 있다(`app/dart_test.yaml`의 `integration`만, 리터럴). 스모크 뼈대(V5·V6)는 G2에서 4–8단계를 더한다.
- (세션 4) 헤드리스 Chrome으로 릴리스 빌드를 직접 띄울 때는 CanvasKit을 CDN에서 받으므로(네트워크 없음) 사본의 `flutter_bootstrap.js`에 `canvasKitBaseUrl: 'canvaskit/'`를 넣어 확인했다(커밋하지 않음). 띄운 서버·Chrome은 PID로만 끝낸다(다른 에이전트 프로세스를 건드리지 않게 `pkill -f` 금지).

- (세션 5) 세션 5 끝 상태: `ws check`(R1–R13·R15)·`--strict` 0, 루트 `flutter analyze --fatal-infos` 0, `dart test tool/test` 265건, `ws test` 7개 멤버 통과, `ws test --platform chrome` 4개 멤버 통과, `flutter build web --release` → `finalize-web` ok.
- (세션 5) 통합 단계 G 준비 메모: G1 `pubspec.lock` 재생성 뒤 `ci.yml`의 캐시 키(`hashFiles('pubspec.lock')`)가 바뀌어 첫 실행은 캐시가 빗나간다(정상). G2 스모크 뼈대 두 파일(세션 4 메모)과 `ci.yml` 10단계(`workflow_dispatch`의 `integration` 입력)로 통합 태그 테스트를 GitHub에서도 돌릴 수 있다. G5에서 확인할 것(9.2): 러너 Chrome(없으면 `browser-actions/setup-chrome`), 두 번째 실행의 캐시 적중, 요약의 주소·단계 시간 표, `android.yml` 아티팩트 경로, 배포 뒤 `curl -I …/sqlite3.wasm`. 워크플로에 actionlint를 돌려 본 적은 없다(컨테이너에 없음) — G5 첫 푸시에서 GitHub가 YAML 오류를 보이면 고친다.
- (세션 5) 6.14 안드로이드 release 서명(키스토어 시크릿 4개 → `key.properties`, `build.gradle.kts`가 있을 때만 사용)은 태블릿 보유 확인 뒤 할 일로 남겼다(동시 개발 몫 아님).
- (통합 2/2) 끝 상태: `ws check`(R1–R15)·`--strict` 0, 루트 analyze 0, `dart test tool/test` 295, `ws test` 8개 멤버·`ws test --platform chrome` 7개 멤버 통과, 통합 태그 VM·Chrome 통과(V5·V6 포함), `flutter build web --release` 성공(`main.dart.js` 4,633,843 B). 남은 것은 G5(컨테이너 밖)뿐.
- (통합 2/2) 릴리스 빌드를 직접 볼 때: 127.0.0.1 정적 서버(없는 경로 → `index.html`) + Playwright `chromium.launch()`, CanvasKit은 `build/web/canvaskit/`에서 route로 주고(`www.gstatic.com`은 프록시가 403), 글꼴은 `fonts.gstatic.com`을 프록시 `curl`로 받아 넘긴다. Flutter 화면 조작은 `flt-semantics-placeholder`를 눌러 접근성 트리를 켠 뒤 `getByRole('button', {name, exact: true})`. Playwright route는 나중에 등록한 것이 먼저 맞으므로 '그 밖의 외부 요청 막기'를 가장 먼저 등록한다.
- (통합 2/2) 위젯 테스트에서 앱이 연 실제 저장소를 읽을 때는 `tester.runAsync`로 감싸지 말고 `smoke_scenario.dart`의 `settle()`을 쓴다(웹에서 끝나지 않음 — '계획과 다르게 한 점').

## 통합 단계

통합 브랜치 `claude/note-app-planning-bk29xb`, 7개 영역 병합(efc5511) 뒤. 이번 몫(1/2): 8.3의 G1·G3, ink lab 등록(INFRA-O1), Chrome 실행 안정화, `android.yml` 개발 브랜치 푸시.

- (1차 통합 뒤, V1~V6 통과 88808e3 이후) GitHub CI가 푸시마다 종료 3(`git merge-base origin/main HEAD` — 원격에 `main` 없음, 기본 브랜치 = 이 개발 브랜치) → `ci.yml` 비교 기준 = `github.event.repository.default_branch`, `FULL_RUN`(main·기본 브랜치 자신) = `check --strict`·모든 멤버, 그 밖은 `ws test --affected-since "origin/$DEFAULT_BRANCH" --all-if-no-base`(새 플래그: 커밋이 아닌 기준·merge base 없음 → 모든 멤버, 다른 git 실패는 종료 3), 잡 제한 25 → 60분(2코어 러너 전체 실행 30~40분 추정), live는 `main`만(바뀌지 않음 — 개발 브랜치는 미리보기 채널, 시크릿 없으면 배포 건너뜀), `android.yml`·`web-experiment.yml` 주석·안내서 02·04·05(개발 브랜치가 기본 브랜치라 Run workflow 있음, `main` 전 live 주소 비어 있음), 계약 v1.5 C15-02 계획서 6.2 R6 행. `dart test tool/test` 306 통과, `ws check --strict` 0·0, `ws analyze` 0. 커밋 54bb561(R6 행)·bb1bc60(CI). 위험: 기본 브랜치 푸시마다 전체 실행 → 월 2,000분이면 약 50회(계획서 6.13 메모).

### G1 — lock 정책 (6.1)

- 병합 직후 `flutter pub get --enforce-lockfile` 통과, `ws check --strict` 0. 영역 진행 기록의 '의존성 요청'은 INK의 ink lab 항목(새 패키지·버전 없음)뿐 — `pinned_external` 값 변경 없음.
- lock 재생성은 한 번(G3의 루트 dev `analyzer: 13.3.0` + ink lab 멤버 등록과 함께): 루트 `flutter pub get` → `pubspec.lock` 변경은 `analyzer`의 `dependency: transitive` → `"direct dev"` 한 줄뿐(해석 버전 전부 그대로). 이때 pub이 ink lab의 옛 단독 해석 파일(`example/pubspec.lock`, `example/.dart_tool/package_config.json`)을 지웠고, 남은 `example/.dart_tool/`도 지웠다(무시 파일).
- 이 커밋 뒤 `ci.yml` 캐시 키(`hashFiles('pubspec.lock')`)가 바뀌어 첫 CI 실행은 캐시가 빗나간다(정상).

### ink lab 등록 (INFRA-O1, INK T23 변경 요청)

- 루트 `pubspec.yaml` `workspace:`에 `packages/ink_engine/example`(멤버 이름 `ink_lab`). `workspace_rules.yaml`: `allowed_dependencies: ink_lab: [note_core, ink_engine]`(계약 7.1 선택 행), `lib_exceptions: packages/ink_engine/example/lib/`(lib/이 `testing.dart` 가짜를 씀 — R4), 새 키 `app_members: [noteapp, ink_lab]`(R14가 비교하지 않는 앱 멤버).
- INK 소유 `example/pubspec.yaml`·`example/.gitignore`는 INK 요청대로 INFRA가 고쳤다(progress/ink.md에 한 줄): `resolution: workspace`, `ink_engine`·`note_core: any`, `riverpod 3.4.3`·`material_ui 1.10.0`(7.5 고정값), `dependency_overrides` 삭제(R10), dev `flutter_lints` 삭제 — 워크스페이스에서는 루트 dev 의존이 `analysis_options.yaml`의 include를 해석하므로 다른 멤버처럼 필요 없다(계약 7.5 '쓰는 멤버'에 `ink_lab`이 생기는 것은 `riverpod`·`material_ui` 두 행뿐 — 총괄이 7.5 갱신).
- `ws affected`: 중첩 멤버(`packages/ink_engine/example` ⊂ `packages/ink_engine`)의 파일은 가장 안쪽 멤버(`ink_lab`)에만 속하게 고쳤다(`memberOfPath` — 전에는 ink_engine과 그 의존 멤버 전체가 영향받음으로 나왔다). `affected_test` 경우 추가.
- `web-experiment.yml`: 입력 `target`(choice `app`|`ink_lab`, 기본 `app`), 동시성 그룹 `web-experiment-<target>`, 채널은 잡 env `CHANNEL_ID`(`app` → `exp-wasm` 그대로, `ink_lab` → `exp-ink-lab` — 두 실험이 서로 덮어쓰지 않게). `ink_lab`이면 `packages/ink_engine/example`에서 같은 플래그로 `flutter build web` → 결과를 `app/build/web`(= `app/firebase.json`의 `public`)으로 복사 → 같은 배포 단계. ink lab에는 manifest·아이콘·웹 자산이 없어 `finalize-web`은 `app`일 때만.
- 확인: `ws list` 8개 멤버, `ws check --strict` 0(R4 예외 동작), `ws test --package ink_lab` 스모크 1개 통과(VM). ink lab에는 `test/web/`가 없어 Chrome 실행에서는 '건너뜀'.

### G3 — R14 (export 이름 교집합)

- 루트 dev `analyzer: 13.3.0` + `pinned_external` 추가(계약 7.5 표 36행 전부 — `rules_test` 스냅숏 갱신).
- 구현을 둘로 나눴다(계획서 6.2와 다른 점): `tool/src/export_names.dart`(analyzer 없음 — 진입점 찾기, 겹침 판정, 프로세스 약속)와 `tool/src/export_namespace.dart`(analyzer — `AnalysisContextCollection(includedPaths: 진입점)` → `getResolvedLibrary` → `exportNamespace.definedNames2`, setter 키 `name=` → `name`, private 제외), 실행 스크립트 `tool/export_names.dart --out <json> <진입점…>`. `ws check`는 이 스크립트를 별도 프로세스(`dart run`, 10분 제한)로 돌린다 — analyzer를 `ws`에 import하면 모든 `ws` 명령이 컴파일에 약 12초 더 걸렸다(측정: `dart run` 0.3초 → 13초).
- 대상: `app_members`(noteapp·ink_lab)를 뺀 멤버의 `lib/*.dart` 최상위 파일 = 6개 패키지 진입점 15개. 같은 패키지 진입점끼리는 비교하지 않는다. 출력 `packages/<a>/lib/<e>.dart:1: [R14] <이름>: <a>/<e>.dart & <b>/<e>.dart`(다른 규칙과 같은 `경로:줄: [규칙]` 형식, 그 이름을 내보내는 진입점 전부). 진입점 자신의 단위에 오류가 있거나(예: 해석 안 되는 `export` URI — `pub get` 안 함) 라이브러리가 아니면 '해석 실패' → 스크립트 종료 3 → `ws check` 종료 3.
- 결과: 진입점 15개(note_core 4·ink_engine 3·feature_editor 1·feature_library 1·pdf_io 2·sync_engine 4) 모두 해석, **겹치는 이름 0**. 이름 수: note_core.dart 198, pdf_io.dart 150, ink_engine.dart 85, sync_engine.dart 73, feature_editor.dart 26, feature_library.dart 11 등. 해석 약 43초(+ 스크립트 컴파일 13초) — `ws check` 전체 약 64초(load 5 안팎).
- `ws check --no-exports`로 건너뜀(픽스처 작업 공간으로 다른 규칙을 보는 기존 테스트 5곳에 `--no-exports`를 더했다 — 픽스처에는 해석기 스크립트·package config가 없다).
- `tool/test/export_names_test.dart` 13건: 픽스처 패키지 3개 + 앱(직접 쓴 `package_config.json`, pub get 없음) — 겹친 이름 1개만(`Shared`, 진입점 3개 나열), `show`/`hide`·private 반영, 같은 패키지 진입점끼리 비교 안 함, `exportOverlaps` 3개 패키지 정렬, 해석 실패(없는 패키지 export → 스크립트 종료 3 → `ws check` 종료 3, part 파일·없는 파일), 해석기 프로세스 문제(비정상 종료·시간 초과·JSON 아님·진입점 누락·스크립트 없음) → 환경 오류, `ws check`가 진입점 전부를 스크립트에 넘김, `--no-exports`면 프로세스 없음, 실제 스크립트 프로세스(종료 3·0, `process` 태그).

### 실기기 경로 — `android.yml` 개발 브랜치 푸시

- `on.push.branches`에 `claude/note-app-planning-bk29xb` 추가(`main`과 함께, `paths-ignore` 같음). 기본 브랜치에 이 파일이 없으면 GitHub가 **Run workflow** 버튼을 보여 주지 않으므로(`workflow_dispatch`), 합치기 전까지는 이 브랜치 푸시가 APK를 받는 길이다. 빌드 정보 채널은 main 밖이라 `preview`, 앱 정보 빌드 줄 끝에 브랜치 이름. 합친 뒤 이 줄을 지운다(워크플로 주석에 적음).
- 안내서 `docs/guides/05-android-apk.md`: 머리말에 개발 브랜치 한 줄, `### 개발 브랜치에서 받기`(Actions → Android APK → **Branch** 필터 → 최근 녹색 실행 → Artifacts, Run workflow 없음 — 새 APK는 Claude에게 푸시 요청), 문제 해결 2행(버튼 없음·필터에 브랜치 없음).
- 테스트: `workflows_test` android 트리거(`[main, <개발 브랜치>]`, main 밖 `preview`), `guides_test` 05(push 목록의 main 밖 브랜치가 모두 안내서에 있고, 받는 방법 문구 3개).

### Chrome 실행 안정화 (`ws test`, CI 권고)

알려진 문제: 전체 `ws test --platform chrome`이 헤드리스 Chrome의 CanvasKit 초기화에서 무기한 멈춘 적이 있고, `ws`의 flutter 실행에 시간 제한이 없었으며, SIGTERM 뒤에도 `ws`가 다음 멤버로 넘어갔다.

- `IoProcessRunner`(`tool/src/flutter_runner.dart`): 시간 제한을 넘으면 **프로세스 트리 전체**를 끝낸다 — `ps -A -o pid=,ppid=`로 자손을 먼저 모은 뒤(부모가 죽으면 손자가 init으로 옮겨 가 못 찾으므로) 전부 SIGTERM → 루트 종료를 최대 5초 기다림 → 남은 것 SIGKILL(Windows `taskkill /T /F`). 전에는 `process.kill()`로 `flutter`만 SIGTERM했다. 출력 파이프는 프로세스가 끝난 뒤 최대 10초만 기다린다(남은 손자가 파이프를 쥐고 있어도 멈추지 않음). 출력 디코딩은 `allowMalformed`.
- `TerminationGuard`(같은 파일) + `tool/ws.dart`: SIGINT·SIGTERM(Windows는 SIGINT만)을 받으면 실행 중인 자식 트리를 끝내고(`terminateAll` — 이후 새 프로세스는 시작하지 않고 `interrupted` 결과) `128 + 신호 번호`(130·143)로 종료. 명령이 먼저 끝나도 `main`이 가드의 종료를 기다린다. 두 번째 신호는 바로 종료.
- `ws test`(`tool/src/test_command.dart`): 멤버 실행마다 시간 제한 — chrome 기본 15분(`defaultChromeMemberTimeout`), vm 없음, `--member-timeout <분>`(0 = 없음). 넘으면 트리를 끝내고 **1회 다시 실행**(준비 스크립트는 다시 돌리지 않음) — 통과하면 `ok (try 2, after a time-out)`, 또 넘으면 `TIMED OUT (2 tries)`(실패)로 다음 멤버 진행. 밖에서 온 신호로 자식이 끝나면(종료 코드 음수, 시간 제한·`ws` 종료가 아님) 그 멤버는 `INTERRUPTED`, 남은 멤버는 `not run (interrupted)`로 실행하지 않는다(관찰된 '다음 멤버로 넘어감'을 막음). 준비 스크립트도 같은 트리 종료를 쓴다.
- 테스트(가짜 프로세스 러너): `test_command_test` 7건(기본 제한 chrome 15분·vm 없음, `--member-timeout` 값·0·잘못된 값 → 2, 시간 초과 → 재시도 → 통과, 두 번 초과 → 실패·다음 멤버 진행, 밖의 신호 → 중단·남은 멤버 미실행, `ws` 종료 중 준비·실행 → 중단, `killedBySignal`), `flutter_runner_test` 7건(가드: SIGTERM → 자식 정리 뒤 143, SIGINT 130·두 번째 신호 즉시, 정리 실패해도 종료; `terminateAll` 뒤 새 프로세스 없음; 실제 `sh` 트리로 시간 초과·`terminateAll`이 손자까지 끝냄·`processTree` — `process` 태그, Linux `/proc`), `cli_process_test` 1건(실제 `dart run tool/ws.dart test`에 SIGTERM → 143, 가짜 flutter의 손자 종료, 다음 멤버 시작 안 함).
- 개발 중 고친 것: 첫 구현에서 출력 스트림의 `asFuture`를 프로세스 종료 뒤에 걸어, 이미 끝난 스트림의 future가 완료되지 않아 10초 상한까지 기다렸다 — 구독 직후에 걸도록 고침(위 테스트가 잡음).

전체 실행 확인(2026-11-05 15:07–15:15, load 1–2): `timeout 6000 dart run tool/ws.dart test --platform chrome` → **7개 멤버 통과, 끝까지 감(약 8분 30초)**, 시간 초과·재시도 없음.

| 멤버 | 준비 | 통과 | 건너뜀 | 시간 |
|---|---|---|---|---|
| note_core | ok | 47 | 1 | 76.4s |
| ink_engine | - | 193 | 0 | 78.7s |
| feature_editor | - | 1 | 0 | 51.7s |
| feature_library | - | 17 | 0 | 72.3s |
| pdf_io | ok | 54 | 1 | 94.9s |
| noteapp | ok | 11 | 1 | 77.8s |
| sync_engine | - | 26 | 0 | 52.7s |
| ink_lab | | | | `test/web/` 없음 |

멈춤 원인 조사(재현 안 됨 — 위 전체 실행과, 다른 멤버 3개(ink_engine·feature_library·sync_engine)를 동시에 돌린 부하 실험(`--member-timeout 6`, 1분 43초) 모두 멈춤·시간 초과 없음):

- Chrome 프로필: flutter_tools(`web/chrome.dart`)가 실행마다 새 임시 `--user-data-dir`(`flutter_tools_chrome_device.*`)를 만든다 — `ws`는 이 플래그를 넘기지 않으므로 재사용 없음. 실행 뒤 남은 프로필 디렉터리 0개.
- 포트: `--remote-debugging-port`와 테스트 서버 모두 실행마다 빈 포트를 새로 고른다. 멤버 사이에 남은 Chrome 프로세스 0개(전체 실행 중 확인).
- CanvasKit 경로: flutter_tools(`test/flutter_web_platform.dart`)가 `canvasKitBaseUrl: "/canvaskit/"`로 엔진 산출물(`/opt/flutter/bin/cache/flutter_web_sdk/canvaskit/`, `chromium/` 변형 포함)을 로컬에서 준다 — CDN·네트워크를 쓰지 않음. Chrome의 배경 연결(`www.google.com`·`android.clients.google.com`·`*.gvt1.com`)은 프록시가 곧바로 403으로 거절해 기다림이 없다.
- 남은 가능성: 다른 에이전트가 동시에 돌린 무거운 실행에서 헤드리스 Chrome의 소프트웨어 WebGL(CanvasKit) 초기화가 끝나지 않은 경우 — 재현하지 못했다. 컨테이너에는 3시간 전에 끝난 실행이 남긴 고아 `flutter_tester` 2개(PPID 1, CPU 0%)가 있었다 — 부모만 죽이면 자식이 남는다는 증거이고, 이번 트리 종료가 막는 경우다(다른 에이전트 것일 수 있어 건드리지 않음).
- 결론: 원인을 하나로 확정하지 못했지만, 이제 멈춤 하나가 멤버 하나의 제한 시간(기본 15분)만 쓰고 자동으로 1회 다시 시도하며, 남는 프로세스 없이 끝난다.
- CI 주의(G5): 이제 7개 멤버 모두 실제 브라우저 테스트가 있어 main의 Chrome 단계만 로컬 약 8.5분이다. `ci.yml` 잡 제한 25분(6.13)에 R14(약 1분)·VM 테스트·도구 테스트(약 1분)·웹 빌드가 함께 들어가므로 첫 GitHub 실행에서 단계 시간 표로 확인하고, 넘치면 잡 제한 또는 `--member-timeout`을 조정한다.

### 이번 몫 끝 확인

- `flutter pub get --enforce-lockfile` 통과, `ws check`(R1–R15) 0 · `--strict` 0, 루트 `flutter analyze --fatal-infos` 0, `dart format` 변경 없음, `dart test tool/test` 295건 통과, `ws test --package ink_lab` 1건, 전체 `ws test --platform chrome` 7개 멤버 통과.
- 다른 통합 담당에게: 잠금 파일·도구 변경은 52de08c에서 끝났다(이후 lock 변경 없음). `ws check`는 이제 R14 때문에 약 1분 더 걸린다 — 빠른 확인은 `ws check --no-exports`. 전체 Chrome 실행이 멈추면 `ws`가 15분 뒤 그 멤버를 끝내고 다시 시도하며, `timeout`으로 감싸 SIGTERM을 보내면 자식까지 끝내고 143으로 종료한다.

## 통합 단계 2/2 — G2·G4 (계획서 8.3, 계약 7.7 4단계)

### G2 — 실제 구현 연결

- 병합 뒤 상태 확인: 모듈 어댑터의 기본 인자가 이미 실제 함수다(I10·I10b) — `productionModules()` = `CoreModule()`(`openNoteStore`·`deleteLocalNoteData`·`defaultNoteStoreConfig` 절대 URL) → `PdfModule()`(`initializePdfIo`·`pdfIoOverrides`) → `FeatureWiringModule()`(`importPdfAsNewNote`·`exportNotesAsPdf`·`pdfEditorMoreMenuActions`·`pdfEditorAddPageSources`, 실제 `pdfRenderStatsProvider`), `AppScreenBuilders.production()` = `LibraryScreen`·`EditorScreen`·`SettingsScreen`, `main.dart` → `runNoteApp()` → `productionModules()`. 그래서 연결 코드는 바꿀 것이 없었고 B4 시절 주석만 고쳤다(`feature_wiring_module.dart`·`pdf_wiring.dart`, 테스트 이름 1개).
- V5·V6가 확인하는 연결(공용 `expectContractOverrides`): 세 모듈 모두 `ok`; 루트 overrides의 `origin` 집합 == 계약 7.3.3 '이번' 8개(`noteStoreProvider`, `ink.pageBackgroundBuildersProvider`, `pdfIoConfigProvider`, `pageThumbnailRendererProvider`, `libraryPdfImportActionProvider`, `libraryPdfExportActionProvider`, `editorExtensionsProvider`, `devOverlaySectionsProvider`) + 셸 6개 + `featureEditorOverrides()`·`featureLibraryOverrides()`(지금 빈 목록), 중복 없음; 값: 배경 빌더 [`PdfBackgroundLayerBuilder`, `TemplateBackgroundLayerBuilder`], `pdfIoConfigProvider == PdfIoConfig()`, 썸네일 렌더러 = INK 인스턴스, 가져오기·내보내기 자리 = pdf_io 함수와 `identical`, 에디터 메뉴 id = pdf_io 동작 id 순서, 개발자 표시 `pdf.render` 3줄.

### V5·V6 스모크

- `app/test/integration/app_smoke_test.dart`(V5, 메모리 CORE): 1(실제 모듈, 1032×1376 DPR 2, overrides) → 2(`nativeMemory` → `notDurable`) → 3(라이브러리 배너 `ContractStrings.storageNotDurable` 1개, 닫기 전) → 4('새 노트' → 대화상자 '만들기' → `EditorScreen`, 저장소에 제목 '제목 없는 노트'·빈 첫 페이지) → 5(에디터 배너 1개 — 라이브러리 라우트는 Offstage) → 6(합성 스타일러스 획 1개 — `InkPageView` 영역 가운데 폭 40%, 저장소 획 1개, 획 폭/페이지 폭 ≈ 0.4·가운데 ≈ 0.5) → 8(되돌리기 → 빈 페이지, 다시 실행 → 같은 획 id) → 7(뒤로 → 라이브러리 → 제목 타일 → 같은 노트, 저장소 같은 획 1개, 새 세션 되돌리기 비활성, 배너 1개) → 9(`shutdown`). `errorLog` 0건. VM 약 4초.
- `app/test/web/app_smoke_browser_test.dart`(V6, Chrome): 같은 시나리오, 'V6 설정'대로 실행마다 다른 `databaseName`·`blobDatabaseName`(절대 URL). 결과: 백엔드 `webSharedIndexedDb`, `storageWarningOf` = `null` → 두 화면 모두 고정 문장 0개(`writeFailing` 문장도 0개). 정리: `shutdown()` 뒤 그 실행의 IndexedDB 2개(`noteapp_smoke_<n>`·`noteapp_smoke_<n>_blobs`)가 있는 것을 기록 → `deleteLocalNoteData(config)` → 그 실행의 IndexedDB 0개, 같은 config로 다시 열면 그 노트 없음 → 닫고 다시 지움 → 0개. Chrome 약 13초(컴파일 제외). 단계마다 `V6: step …` 줄을 출력한다(멈추면 어디서인지 보인다).
- Chrome 첫 `openNoteStore`(빈 DB, 헤드리스 Chrome, 다른 에이전트와 CPU 공유): `core` 단계 2.8~3.0초, 부트스트랩 → 라이브러리 3.4~3.8초(3회). 계획서 6.13 실측표에 적었다 — `CoreModule.startTimeout` 20초는 그대로.

### 통합 태그 테스트 (계약 7.7 5단계)

`dart run tool/ws.dart test --run-skipped -t integration`(VM, 4분 3초) — 8개 멤버 통과:

| 멤버 | 통과 | 내용 |
|---|---|---|
| feature_editor | 1 | E-21 `real_core_ink_smoke_test` |
| feature_library | 10 | L21 `core_contract_test` |
| pdf_io | 19 | `core_gateway_test`·`ink_thumbnail_test`·`ink_vectorizer_test` |
| noteapp | 1 | V5 |
| sync_engine | 42 | T16(그때 작업 트리 — SYNC 통합 담당이 `test/integration/`을 고치는 중이었다) |
| note_core·ink_engine·ink_lab | 0 | 통합 태그 없음 |

`dart run tool/ws.dart test --platform chrome --run-skipped -t integration`(7분 34초) — 7개 멤버 통과, 통합 태그 Chrome 테스트는 noteapp V6 1개(다른 멤버는 '일치하는 테스트 없음').

### 통합 단계 2/2 — 릴리스 빌드에서 찾은 결함 (INFRA, 고침)

릴리스 빌드를 실제로 띄워 보다가(아래 '앱 실행 확인') 앱 셸 라우팅 결함 2개를 찾아 고쳤다. 둘 다 위젯 테스트(VM)의 기존 경우로는 잡히지 않았다.

1. **노트를 열어도 주소가 `/`에 남음**: go_router 기본값(`GoRouter.optionURLReflectsImperativeAPIs = false`)에서는 `push`(= `AppNavigator.openNote`·`openSettings`)가 브라우저 주소를 바꾸지 않는다. → `createAppRouter`가 이 옵션을 켠다(전역 정적 값, 멱등). 테스트: `app_router_test` 'the reported browser address follows push and pop' — `SystemChannels.navigation`의 `routeInformationUpdated` `uri`가 `/folders/f1` → `/notes/n1?page=p3` → `/settings` → `/notes/n1?page=p3` → `/folders/f1`(고치기 전 코드로 돌리면 `/notes/n1?page=p3` 자리에서 `/folders/f1`이 나와 실패함을 확인).
2. **`/notes/<id>`에서 새로고침하면 라이브러리가 열림**(9.3 #16, 계약 7.4.3): 스플래시·오류 화면 틀(`_ShellFrame`)의 `MaterialApp(home:)` 루트 Navigator가 시작 중에 `/`를 엔진에 보고하고, 웹 엔진은 첫 navigation 메시지에서 `defaultRouteName`을 `/`로 바꾼다(엔진 `platform_dispatcher.dart`) — 시작 뒤 만들어지는 GoRouter는 `/`에서 시작했다(Playwright로 `history.replaceState` 순서 확인). → `_ShellFrame`이 `MaterialApp(builder:)` 안에 자기 `Navigator(pages: [MaterialPage(key: 'shell', child)])`를 둔다(`reportsRouteUpdateToEngine` 기본 false, 오류 화면의 2단계 확인 대화상자는 그대로 동작). 테스트: `bootstrap_app_test` 'the splash and the error screen report no route to the engine …' — 스플래시·오류 화면 동안 `SystemChannels.navigation` 호출 0건, 다시 시도 뒤 앱은 보고함(고치기 전 코드로는 `['selectSingleEntryHistory', 'routeInformationUpdated']`로 실패함을 확인). 첫 수정(`onGenerateRoute`)은 첫 child(스플래시)를 붙잡아 오류 화면으로 바뀌지 않았다 — 기존 bootstrap 테스트 6개가 잡았고 `pages`로 고쳤다.

### G4 — 최종 확인 (V1~V4)

| 명령 | 결과 | 시간 |
|---|---|---|
| 루트 `flutter analyze --fatal-infos` | 0건 | 10초 |
| `ws check` (R1–R15) / `ws check --strict` | 0 · 0 (R11 = `dart format` 변경 없음 포함) | 59초 · 58초 |
| `ws web-assets verify` | 2개, 문제 0 | 2초 |
| `dart test tool/test` | 295 통과 | 54초 |
| `ws test` (VM) | 8개 멤버 통과 — note_core 617(+5 건너뜀)·ink_engine 779·feature_editor 591(+1)·feature_library 626(+1)·pdf_io 580(+7)·noteapp 261(+1 = V5)·sync_engine 777(+4)·ink_lab 1 | 8분 49초 |
| `ws test --platform chrome` (전체 한 번) | 7개 멤버 통과, 시간 초과·재시도 없음 — note_core 47(+1)·ink_engine 193·feature_editor 1·feature_library 17·pdf_io 54(+1)·noteapp 11(+1 = V6)·sync_engine 26, ink_lab은 `test/web/` 없음 | 8분 2초 |
| `cd app && flutter build web --release` | 성공(wasm dry run 성공) — `main.dart.js` **4,633,843 B**(gzip 1,366,038 B, I15보다 +1.89 MB) | 1분 52초(컴파일 110초) |

`ws test`의 sync_engine 수는 SYNC 통합 담당의 커밋 전 작업 트리 기준이다(경로가 겹치지 않아 건드리지 않음).

### 앱 실행 확인 (릴리스 빌드, 헤드리스 Chromium)

- 방법: 위 릴리스 빌드(`app/build/web`)를 127.0.0.1의 정적 서버(Hosting처럼 없는 경로 → `index.html`, `Cache-Control: no-cache` — 스크래치 디렉터리의 작은 Python 서버)로 띄우고 Playwright `chromium.launch()`(1032×1376, deviceScaleFactor 1, `ko-KR`)로 연다. 컨테이너 프록시가 `www.gstatic.com`을 막아 CanvasKit은 빌드에 든 `canvaskit/`에서 주고(Playwright route), Google Fonts(`fonts.gstatic.com`)는 프록시를 거친 `curl`(TLS 검증)로 받아 넘겼다. 그 밖의 외부 요청은 막았다. 조작은 Flutter 접근성 트리(semantics)를 켜고 버튼 이름으로 찾았다. 서버·브라우저는 끝나고 PID로 종료.
- 결과(고친 뒤): 첫 프레임 약 1.7초 → 라이브러리(빈 홈 '노트가 없어요', '새 노트'·'새 폴더') → '새 노트' → 대화상자(제목 '제목 없는 노트', A4·세로·줄 속지) → '만들기' → 주소 `/notes/<id>`의 에디터(줄 속지, 툴바·펜 프리셋) → '뒤로' → 라이브러리에 '제목 없는 노트' 타일(썸네일) → 그 주소로 새로고침 → 같은 노트의 에디터. **콘솔 오류 0건, 페이지 오류 0건, 실패한 요청 0건.** 경고는 헤드리스 소프트웨어 WebGL의 'GPU stall due to ReadPixels' 4줄뿐. 저장소 경고 배너는 이 Chromium에서 보이지 않았다(V6와 같은 `webSharedIndexedDb`·경고 없음).
- 고치기 전에는 '만들기' 뒤 주소가 `/`에 남았고(결함 1), `/notes/<id>`를 직접 열면 라이브러리가 떴다(결함 2).
- 스크린숏(커밋하지 않음): `/tmp/claude-0/-home-user-noteapp/43ee6a27-03fc-5e99-8039-9d32bef92c40/scratchpad/integration-shots/` — `01-library.png`, `02-new-note-dialog.png`, `03-editor.png`, `04-library-with-note.png`, `05-reload-on-note.png`, `report.json`.

### G5 — 컨테이너 밖에서 할 일 (총괄·사용자)

- 총괄: 통합 브랜치 푸시 → `ci.yml` 녹색 확인. 첫 실행은 `pubspec.lock` 캐시 키가 바뀌어 캐시가 빗나간다(정상). 잡 제한(1차 통합 뒤 25 → 60분) 안에 드는지 단계 시간 요약으로 확인 — 로컬 Chrome 단계만 약 8분, VM `ws test` 약 9분(CPU 공유 시). 넘으면 잡 제한을 올리거나 브랜치 푸시의 브라우저 테스트를 영향받은 멤버로 줄인다(6.13).
- 총괄: 통합 태그 테스트를 GitHub에서도 돌리려면 `ci.yml`을 `workflow_dispatch`로 `integration: true` 입력과 함께 실행.
- 사용자: Firebase 프로젝트 만들기·GitHub 시크릿 등록(안내서 `docs/guides/01-firebase-project.md`·`02-github-secrets.md`) — 없으면 CI가 배포를 건너뛴다. 등록 뒤 미리보기 배포 → `curl -I https://<프로젝트 ID>.web.app/sqlite3.wasm`(또는 미리보기 주소)로 `Content-Type: application/wasm`·`Cache-Control: no-cache`·COOP/COEP 없음 확인(9.2).
- 사용자: iPad 체크리스트(계획서 9.3, 안내서 `docs/guides/04-ipad-web-test.md`) — 특히 #16(노트에서 새로고침 → 같은 노트, 이번에 고친 결함 2), #1(재방문 시작 2초 — `main.dart.js`가 4.6 MB로 커짐), #18a·18b(백업 내보내기), 계약 V7 ①②③ 복합 항목.
- 사용자(선택): 안드로이드 태블릿이 있으면 `android.yml` 개발 브랜치 푸시 APK 설치(안내서 05).
- `main`이 생겨 기본 브랜치가 된 뒤: `android.yml` `on.push.branches`에서 `claude/note-app-planning-bk29xb` 삭제(워크플로 주석). 지금은 이 개발 브랜치가 기본 브랜치라 Run workflow도 이미 된다.

## 2차

계획 docs/plans/m5-7/01-infra.md(승인 · 계약 v2.2). 바탕: `main` = 1차 통합 HEAD `b6c9d0a` + 계획 병합 `a23c14f`.

### R2-B1 — 기반 단계 (계약 7.6.2, 계획 8.1)

- 커밋: `3c77de3`(R2-B1 전체), 이 기록 줄은 그 뒤 커밋
- **새 패키지 골격 3개**(소유 영역에 넘김): `packages/media_io`(PDF — 06-pdf 3.4 확정본 pubspec: 직접 의존 CP-PDF-9 6줄·간접 고정 CP1 2줄·`image_picker_ios` 간접 고정, `dart_test.yaml` `media`·`integration` skip), `packages/ink_recognition`(LIBRARY — 05-library 3.3, `google_mlkit_commons` 직접 의존 없음, `dart_test.yaml` `golden`·`integration`·`emulator`), `packages/pencil_bridge`(INFRA — iOS 전용 플러그인 `pluginClass: PencilBridgePlugin`, 빈 `register(with:)` Swift·`Package.swift`(`.iOS("15.0")`, `FlutterFramework` — Flutter 3.47.9 템플릿)·podspec). 각 README·빈 진입점·스모크 시험. 진입점 본문은 R2-B4·R2-B6·R2-B8b.
- **pubspec**: 루트(멤버 3줄, dev `xml 7.0.1`), `app`(`media_io`·`ink_recognition`·`pencil_bridge`·`path_provider 2.1.6`, dev `integration_test`), `ink_engine`(CP3 한 번 예외 — `flutter_math_fork 0.7.4`·간접 고정 `flutter_svg 2.3.0`·`vector_graphics 1.2.3`·`vector_graphics_compiler 1.3.0` 4줄만).
- **lock**(`flutter pub get` 한 번 — 계약 7.5와 같음): 기존 변화는 `xml 7.1.0 → 7.0.1`(transitive → direct dev) 한 건, 추가 49개 = 계약 7.5의 44개 + `integration_test`가 끌어온 5개(SDK `flutter_driver`·`fuchsia_remote_debug_protocol`·`integration_test`, hosted `sync_http 0.3.1`·`webdriver 3.2.0`). CP1 간접 고정 결과 `shared_preferences_android 2.5.3`·`shared_preferences_foundation 2.6.0`. 그 밖의 변화 없음. `flutter pub get --enforce-lockfile` 통과.
- **게시 14일 재확인**(2026-11-05 21:46 UTC, pub.dev API — 새로 잠긴·바뀐 hosted 47개): 모두 날짜로 14일 이상. 가장 가까운 것은 `image_picker_ios 0.8.13+13`(2026-10-22T22:00Z)·`shared_preferences_android 2.5.3`(2026-10-22T19:57Z) — 날짜로 꼭 14일(계약 표가 고른 판 그대로), 그다음 `file_selector_macos 0.9.5+2`(10-19, 17일)·`xml 7.0.1`(04-25). **`firebase-tools 15.34.2`**(npm 2026-10-28T23:18Z)는 아직 8일 — R2-B1은 새로 채택하지 않는다(`ci.yml` 배포 단계의 1차 고정값 그대로, `functions.yml` 골격에는 firebase 단계 없음). `functions/package.json` devDependency(SYNC R2-B7b)는 2026-11-11 이후(SYNC-F2).
- **`plugin_packages`** = 실제 `app/.flutter-plugins-dependencies` `dependencyGraph` 이름 53개(계획 4.3.1 목록과 같음 — 빠짐·남음 0). `rules_test`가 해석된 워크스페이스에서 같음을 단언한다.
- **`workspace_rules.yaml` v2**(계획 4.3.1 전체): R8 새 3행·`noteapp` 3개, `pinned_external` 2차 21줄(57줄), `native_only_imports` 4줄, `forbidden_io_members: [Platform]`, `test_only_entrypoints`·`lib_exceptions`에 `note_core/lib/testing_web.dart`, `generated_files` `*.steps.dart`, `skip_by_default_tags` `media`·`emulator`, R16 `plugin_free_members`·`plugin_exceptions`·`plugin_packages`. `rules.dart`: R4 `dart:io` `Platform`(식별자 토큰 — 직접·`show`·`as io` 접두어, `lib_exceptions` 면제), **R16**(목록 ∪ pubspec `flutter: plugin:`을 `.dart_tool/package_config.json`으로 찾아 판정, 예외 확장·`plugin_free_members` 축소도 위반 — 규칙 코드의 기준 상수). `implementedRules` R1–R16.
- **`tool/chrome-fakemedia`**(100755, LF) + `ws test -t media --platform chrome` 래퍼 연결(`NOTEAPP_REAL_CHROME` = `locateChrome` 결과, `CHROME_EXECUTABLE` = 래퍼).
- **무거운 시험 잠금**(`tool/src/heavy_lock.dart`): `/tmp/noteapp-heavy-tests.lock`(`NOTEAPP_HEAVY_LOCK`), 한 줄 `<pid> <ISO UTC> <명령 120자>`, 배타 생성, 죽은 pid·1분 지난 깨진 파일 회수, 1분마다 대기 출력, 로그 `noteapp-heavy-tests.log`. `ws test`는 태그 `media`·`emulator`와 `--package` 없는 Chrome 실행에서 실행 계획 뒤 첫 멤버 전에 잡아 마지막 멤버(재시도 포함) 뒤 푼다, `NOTEAPP_HEAVY_LOCK_HELD=1`이면 잡지 않고 자식 전부에 넘긴다, `--no-heavy-lock`·`--heavy-lock-timeout`(기본 20분, 종료 코드 4), 요약 끝 '잠금 대기 n초'. **`ws with-heavy-lock [--timeout] -- <명령>`**. SIGINT·SIGTERM은 자식 트리를 끝낸 뒤 잠금을 풀고 130·143(`TerminationGuard.watch(beforeExit:)`).
- **`app/firebase.json`**: `functions`(`../functions`, `default`, `ignore` 14개 — SYNC RQ-6, `predeploy` 빌드)·`emulators`(functions 127.0.0.1:5001, auth 127.0.0.1:9099, UI 끔, `singleProjectMode`). `hosting_config`가 두 항목은 이 모양만 허용.
- **`.gitignore`**(계약 7.4.7 + 서명 재료 4종)·**`.gitattributes`**(스크립트 LF 4종·`binary` 5종)·`analysis_options.yaml` exclude `functions/**`.
- **CI(총괄 지시 — 월 2,000분, 1차 통합 뒤 전체 1회 30분 실측)**: `ci.yml` 'Test scope' 단계 — 기본 브랜치(`main` 아님) 푸시는 `--affected-since <github.event.before> --all-if-no-base`(`before`가 0000…·없음 → 전체), 수동 입력 `full`(기본 끔) → 전체, `main` 푸시 그대로 전체, 영역 브랜치 그대로 기본 브랜치 대비. `check --strict`는 `main`·기본 브랜치·수동 full. 기본 브랜치 푸시는 실행마다 다른 `concurrency` 그룹(자기 변경만 시험하므로 취소·대체 금지). 요약에 '시험 범위:' 줄. `android.yml` push 트리거 제거(수동만), 새 `functions.yml`(경로·수동만, 체크아웃 뒤 모든 단계 `hashFiles` 가드, 시험 수 > 0 확인, 에뮬레이터 단계는 J16). 안내서 05(수동 APK)·02(실행 시간), 1차 계획 6.13 실측·정책, 2차 계획 6.16(실측·정책·월 분 재계산 약 1,346분)·6.10.3.
- `tool/README.md`(새, 개발자용): `ws` 명령·잠금·`emulator`·`media` 실행 명령(계획 6.13 '이 명령은 tool/README에').

| 검사 | 결과 | 시간 |
|---|---|---|
| `flutter pub get --enforce-lockfile` | 통과 | — |
| 루트 `flutter analyze --fatal-infos` | 0건 | 20초 |
| `ws check` / `ws check --strict` (R1–R16) | 0 · 0 | 54초 · 53초 |
| `dart test tool/test` | 371 통과 · 1 건너뜀(`chrome_fakemedia_test`의 'git 100755' — 커밋 전이라 추적되지 않음; 커밋 `3c77de3` 뒤 다시 돌려 통과 — 372) | 59초 |
| `ws test --package pencil_bridge` | 6 통과(`pencil_wire_contract_test` R2-B1 묶음 5 + 스모크) | — |
| `ws test` (VM, 11개 멤버) | 모두 통과 — note_core 619(+5 건너뜀)·ink_engine 780·feature_editor 591(+1)·feature_library 626(+1)·pdf_io 580(+7)·sync_engine 777(+4)·ink_lab 1·media_io 1·ink_recognition 1·pencil_bridge 6·noteapp 261(+1 = V5) | 8분 49초 |
| `ws test --platform chrome --package noteapp` (앱 웹 플러그인 등록에 `record_web`·`just_audio_web`·`image_picker_for_web`·`shared_preferences_web`이 새로 들어가므로) | 준비 ok · 11 통과 · 1 건너뜀(V6) | 1분 3초 |

- 전체 Chrome 실행(`ws test --platform chrome`, 무거운 시험 — 다른 에이전트와 CPU 공유)은 돌리지 않았다: 새 멤버 3개는 `test/web/`이 없고, 다른 멤버의 Chrome 입력 중 바뀐 것은 앱의 웹 플러그인 등록(위 표에서 확인)과 `ink_engine`의 import하지 않는 의존 4줄뿐이다. 통합 묶음(R2-B2 + B7a + B2i) 뒤 `ws test --platform chrome` 전체를 돌린다.
- `firebase-tools 15.34.2` 14일 재확인: 2026-11-11 23:18 UTC 이후 통과 — R2-B7b(SYNC)가 그 뒤에 `functions/package.json`에 넣는다.

#### 계획과 다르게 한 점 (R2-B1)

- 잠금 회수: 낡은 잠금을 지우는 '읽고-지우기'를 `<잠금 경로>.guard` 파일의 배타 `flock`(짧게) 안에서 한다 — 두 `ws`가 같은 낡은 잠금을 보고 둘 다 지우면 두 번째가 첫 번째의 새 잠금을 지우기 때문(계획 6.13에 없음). `.guard` 파일은 /tmp에 남는다(빈 파일).
- `chrome-fakemedia`: `NOTEAPP_REAL_CHROME`이 래퍼 자신이면(`-ef`) 무시하고 찾는다, `ws`도 `CHROME_EXECUTABLE`이 이미 래퍼면 `NOTEAPP_REAL_CHROME`을 넣지 않는다(자기 자신을 끝없이 실행하는 것 방지).
- '전체 Chrome 실행' 판정 = 사용자가 `--package`를 주지 않은 Chrome 실행(`--affected-since`만 있어도 잠금을 잡음 — 보수적으로).
- R16은 계획의 '예외 확장 = 위반'에 더해 `plugin_free_members`에서 기준 멤버 4개가 빠져도 위반으로 본다.
- `ws with-heavy-lock`: 신호로 끝난 자식의 종료 코드는 셸처럼 128 + n.
- `ci.yml`: 기본 브랜치에서는 바뀐 멤버만 시험해도 `check --strict`(1분 미만)를 계속 돌린다(`STRICT_CHECK`와 `FULL_RUN`을 나눔). 기본 브랜치 푸시의 `concurrency` 그룹을 실행마다 다르게 했다(계획에 없음 — 위 이유). 같은 미리보기 채널에 겹친 두 실행이 거의 같은 때 배포하면 나중에 끝난 쪽이 남는다(보통 순서대로 끝남).
- `app/firebase.json`의 `hosting.ignore`가 JSON 정리로 여러 줄이 됐다(값 같음).
- `packages/media_io`·`ink_recognition` pubspec은 블록 형식으로 썼다(06-pdf 3.4·01-infra 3.3의 흐름 형식 `{sdk: flutter}`과 값 같음), `version:` 줄 없음(확정본 그대로).

### R2-B2i — 기반 단계 (계약 7.6.2, 계획 8.1 — R2-B2·R2-B7a와 한 묶음)

- 커밋: `59ed567`(위임 4줄), 이 기록 줄은 그 뒤 커밋. 바탕 = `c443015`(CORE B2-α `2b2e4b0`·B2-β JSON `9777fde`·T20b `c443015`, SYNC R2-B7a `99b8ead` 포함).
- `CountingNoteStore`(명시 위임 — 계약 C2-15)에 계약 7.2.6 getter 4개를 `inner`로: `RecordingRepository get recordings`·`RecordingDraftStore get recordingDrafts`·`HandwritingRepository get handwriting`·`SearchIndex get search`. 그 밖의 변경 없음.
- 검사는 커밋 `59ed567`의 `git archive` 사본에서 했다(작업 중에는 작업 트리에 CORE가 아직 커밋하지 않은 B2-β 진행분이 있어 그것을 섞지 않으려고 — 처음 한 번은 `5056fcb` 사본 + 이 파일로 같은 결과). 작업 트리의 `ws check`는 그때 CORE의 커밋 전 파일 `packages/note_core/test/model/object_json_test.dart` 하나를 R11(형식)로 잡았다 — 커밋된 판은 형식이 맞고 사본의 `ws check`는 0. `dart test tool/test`는 작업 트리에서.

| 검사 | 결과 | 시간 |
|---|---|---|
| `flutter pub get --enforce-lockfile` | 통과(lock 변화 없음) | — |
| `app` `flutter analyze --fatal-infos` | 0건 | 5초 |
| `ws test --package noteapp` (VM) | 261 통과 · 1 건너뜀(V5 `integration`) | 41초 |
| `ws test --package noteapp --platform chrome` | 준비 ok · 11 통과 · 1 건너뜀(V6) | 59초 |
| `dart test tool/test` | 372 통과 | 47초 |
| `ws check` (R1–R16, HEAD 사본) | 0 | — |

- 전체 `ws test`(VM·Chrome, 모든 멤버) 묶음 검사는 총괄의 묶음 병합 뒤(계약 7.6.2). R2-B1 메모의 '묶음 뒤 전체 Chrome 실행'도 그때로 넘긴다 — 이 단계의 변경은 `noteapp` 시험 가짜 하나뿐이다.
