# INFRA 진행 기록

## 요약

- 마지막 세션: **2차 동시 개발 2/11** — **R2-B8b**(라우팅 `?page=&focus=`·`pencil_bridge` Dart 표면·Pencil 어댑터), **J0 ①②③**(네이티브 설정·`native_config` 정적 시험·웹 빌드 실측; ④ CI 실측은 첫 체크포인트 푸시 뒤) — 아래 '## 2차' > '### 동시 개발'. 그 앞 1/11은 작업 표·문서 정리(C22-09·C23-01)·R2-B8a, 기반 단계 R2-final(`708a1c1`)·R2-B2 묶음 검사·R2-B2i·R2-B1.
- 다음 할 일: '### 동시 개발' 작업 표 순서 — J1 → J2~J22(J0 ④는 총괄의 첫 체크포인트 푸시 뒤 — 체크포인트 병합 Q14; R2-B8a·R2-B8b·J0 체크포인트 요청함).
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
| R2-B2 묶음 검사 (2차) | 완료 | — (검사 전용) | HEAD `7dacf36`에서 `flutter pub get --enforce-lockfile`·`ws check`(·`--strict`)·루트 analyze·`ws test`(VM 11개·Chrome 7개 멤버)·`dart test tool/test` 모두 통과(아래 '## 2차' > 'R2-B2 묶음 검사') |
| R2-final (2차) | 완료 | 708a1c1 | 2차 기반 단계 전체 확인: 앱 시험 3곳의 배경 빌더 목록을 계약 v2.2(C2-20)로(`modules/pdf_module_test`·`modules/production_modules_test`·`support/smoke_scenario`). HEAD `708a1c1`에서 pub get·`ws check`(·`--strict`)·analyze·`dart format`·`ws test`(VM 11개·Chrome 9개 멤버, V5·V6 포함)·`dart test tool/test`·릴리스 웹 빌드·`functions/` `npm ci && npm test` 모두 통과(아래 '## 2차' > 'R2-final') |

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

### R2-B2 묶음 검사 (계약 7.6.2 — CORE B2-α·B2-β + SYNC R2-B7a + INFRA R2-B2i)

- 검사 대상: 작업 트리 HEAD `7dacf36`(깨끗함 — 커밋 안 된 파일 없음). 묶음 커밋: CORE `2b2e4b0`(B2-α 계약 타입 커밋)·`9777fde`(B2-β JSON 골든)·`c443015`·`38f3578`·`12ab8c4`·`0798096`(B2-β 끝), SYNC `99b8ead`, INFRA `59ed567`, 각 진행 기록 커밋. 검사 전용 단계라 코드 변경 없음(이 기록 줄만).
- 2026-11-06 01:24–02:00 UTC, 다른 에이전트의 무거운 시험 없음(잠금 대기 0초, load 1–2.5).

| 검사 | 결과 | 시간 |
|---|---|---|
| `flutter pub get --enforce-lockfile` | 통과(lock 변화 없음) | — |
| `ws check` / `ws check --strict` (R1–R16) | 0 · 0 | 약 1분씩 |
| 루트 `flutter analyze --fatal-infos` | 0건 | 14초 |
| `ws test` (VM, 11개 멤버) | 모두 통과 — note_core 880(+5 건너뜀)·ink_engine 780·feature_editor 591(+1)·feature_library 626(+1)·pdf_io 580(+7)·sync_engine 782(+4)·ink_lab 1·media_io 1·ink_recognition 1·pencil_bridge 6·noteapp 261(+1 = V5) | 약 7분 30초 |
| `ws test --platform chrome` (전체, 무거운 시험 잠금) | 7개 멤버 통과 — note_core 71(+1)·ink_engine 194·feature_editor 1·feature_library 17·pdf_io 54(+1) **try 2**·sync_engine 26·noteapp 11(+1 = V6). `ink_lab`·`media_io`·`ink_recognition`·`pencil_bridge`는 `test/web/` 없음 | 22분 31초(그중 pdf_io 첫 시도 멈춤 15분) |
| `ws test --package pdf_io --platform chrome --member-timeout 5` (재현 확인) | 54 통과 · 1 건너뜀, 멈춤 없음 | 1분 19초 |
| `dart test tool/test` | 372 통과 | 58초 |

- **pdf_io Chrome 첫 시도 멈춤**: `compose_browser_test.dart`가 끝난 뒤(시험 시계 00:17) `loading .../pdf_io/test/web/pure_logic_browser_test.dart`에서 더 진행하지 않아 멤버 제한 15분에 끝내고 다시 실행 → `ok (try 2, after a time-out)`. 따로 다시 돌리면 재현되지 않음. 1차 'Chrome 실행 안정화'에 적은 헤드리스 Chrome 멈춤과 같은 모양(시험 파일 불러오기 중 멈춤, 원인 미확정)이고, 이번 묶음은 `packages/pdf_io`를 바꾸지 않았다(의존하는 `note_core`만 바뀜). 재시도 정책이 의도대로 동작했다. 다시 자주 보이면 CI 잡 제한(전체 Chrome 단계가 15분 더 걸림)과 함께 살핀다.
- 이전 메모의 '묶음 뒤 전체 Chrome 실행'(R2-B1·R2-B2i)은 위로 끝냈다.

### R2-final — 2차 기반 단계 전체 확인 (계약 7.6.2 — 동시 개발 시작 조건 = R2-B1~R2-B6이 `main`에 있음)

- 커밋: `708a1c1`(앱 시험 고침), 이 기록 줄은 그 뒤 커밋. 검사 대상 = HEAD `708a1c1`(작업 트리 깨끗함). 그 앞 기반 단계 커밋: INFRA R2-B1 `3c77de3`, SYNC R2-B7b `9cdd3fb`, CORE T25a `b6beece`·B2-α `2b2e4b0`·B2-β `9777fde`..`0798096`, SYNC R2-B7a `99b8ead`, INFRA R2-B2i `59ed567`, INK R2-B3 `fd3370f`, EDITOR R2-B5 `78d7f25`, PDF R2-B4 `5636d4e`, LIBRARY R2-B6 `99cdeef`(각 진행 기록 커밋 포함).
- **고친 것(INFRA 경로만)**: INK R2-B3·PDF R2-B4가 배경 빌더 목록을 계약 v2.2 7.2.9·7.2.12·7.3.3(C2-20)으로 바꿔 앱 시험 3곳이 1차 목록을 기대하고 있었다(INK·EDITOR·PDF 변경 요청). `app/test/modules/pdf_module_test.dart`(시작 실패 → INK 기본 `[image, template]`, 기본 인자 → `[pdf, image, template]`), `app/test/modules/production_modules_test.dart`(모듈 함께 → `[pdf, image, template]` — B4 뒤 새로 깨졌던 곳), `app/test/support/smoke_scenario.dart`(V5·V6 → 같은 세 빌더). `PdfModule.overrides()` 문서 주석의 기본 목록 문구도. 동작 변화 없음.
- 2026-11-06 03:53–04:21 UTC, 다른 에이전트의 무거운 시험 없음(잠금 대기 0초, load 1–2).

| 검사 | 결과 | 시간 |
|---|---|---|
| `flutter pub get --enforce-lockfile` | 통과(lock 변화 없음) | 2초 |
| `ws check` / `ws check --strict` (R1–R16) | 0 · 0 | 55초 · 51초 |
| 루트 `flutter analyze --fatal-infos` | 0건 | 10초 |
| `dart format --output=none --set-exit-if-changed` (추적 중인 Dart 1,315개, R11 대상) | 변경 0 | 5초 |
| `dart test tool/test` | 372 통과 | 52초 |
| `ws test` (VM, 11개 멤버) | 모두 통과 — note_core 880(+5 건너뜀)·ink_engine 889·feature_editor 658(+1)·feature_library 628(+1)·pdf_io 604(+7)·sync_engine 782(+4)·ink_lab 1·media_io 37·ink_recognition 57·pencil_bridge 6·noteapp 261(+1 = V5) | 8분 9초 |
| `ws test --package noteapp --run-skipped -t integration` (V5, 잠금 아래) | 1 통과 | 23초 |
| `ws test --platform chrome` (전체, 무거운 시험 잠금) | 9개 멤버 통과, 시간 초과·재시도 없음 — note_core 71(+1)·ink_engine 199·feature_editor 1·feature_library 17·pdf_io 54(+1)·sync_engine 26·media_io 3·ink_recognition 9·noteapp 11(+1 = V6). `ink_lab`·`pencil_bridge`는 `test/web/` 없음 | 9분 46초 |
| `ws test --package noteapp --platform chrome --run-skipped -t integration` (V6, 잠금 아래) | 준비 ok · 1 통과 | 1분 28초 |
| `cd app && flutter build web --release` (잠금 아래) | 성공(wasm dry run 성공) | 2분 1초(컴파일 117초) |
| `ws web-assets verify` | 2개, 문제 0 | 2초 |
| `functions/` `npm ci && npm test` (Node 22.23.4, npm 10.9.9) | 721개 설치 · `# tests 37`, 37 통과 | 21초 + 2초 |

- **웹 크기**(`dart:io` gzip — `ws finalize-web`과 같은 방식): `main.dart.js` **4,667,466 B**(1차 G4 4,633,843 B 대비 **+33,623 B, +0.73%**), gzip **1,375,483 B**(1차 1,366,038 B 대비 +9,445 B — 시작 한도 1,666,038 B까지 290,555 B 남음). 앱 셸이 아직 새 모듈(`MediaModule`·`RecognitionModule`)·새 확장 자리를 연결하지 않아(R2-B8a) `media_io`·`ink_recognition` 코드와 객체 편집 UI 대부분이 트리 셰이킹으로 빠진 값이다 — 기준 갱신은 J0(R2-B8b 뒤)에서.
- **시작 글꼴**(`FontManifest.json`): 14개 패밀리 — `flutter_math_fork` KaTeX 12개 패밀리 20개 파일 + MaterialIcons + CupertinoIcons, 합계 661,088 B · gzip **382,428 B**(계획 4.3.3 초안 `startup_fonts_gzip_max: 400000`까지 17,572 B). KaTeX 20개가 370,093 B gzip(MaterialIcons 10,170 B·CupertinoIcons 1,011 B)으로 거의 전부다 — J0에서 묶음별 한도를 제안할 때 이 값을 쓴다. `NoteSans`는 `FontManifest`에도 `AssetManifest`에도 없다(계약 7.4.5의 '`FontManifest`에 넣지 않음'은 지켜짐; INK 글꼴 파일은 아직 `ink_engine` pubspec `flutter: assets:`에 없다 — 아래).
- pdf_io Chrome 멈춤(R2-B2 묶음 검사)은 이번에 다시 나타나지 않았다(92초, 첫 시도 통과).
- **남은 것(다른 영역·총괄)**: INK가 INFRA에 요청한 `packages/ink_engine/pubspec.yaml`의 `flutter: assets:` 블록(글꼴 3줄)은 INFRA가 넣지 않았다 — 그 파일에서 INFRA가 고칠 수 있는 것은 R2-B1의 의존 4줄(CP3 한 번 예외)뿐이고, 01-infra 3.3은 글꼴 블록을 INK R2-B3 몫으로 적었다. 총괄에게 결정을 요청했다(INK가 동시 개발 첫 작업으로 넣거나 INFRA에 한 번 더 예외). 블록이 없는 동안 앱·VM 패키지 시험에서 `InkFonts.ensureLoaded()`는 실패하고 대체 글꼴을 쓴다(INK 보고 — 예외 없음); 이번 검사는 그 때문에 실패한 시험이 없다.

### 동시 개발 (계획 8.1b·8.2 — 작업 트리 `/home/user/wt2/infra`, 브랜치 `area2/infra`, 바탕 `5843ec3` = 계약 v2.3)

다른 영역의 2차 구현은 이 작업 트리에서 기반 단계 표면(단순 구현·가짜)이다. 실제 구현이 필요한 판정은 `integration`·`media`·`emulator` 태그 시험으로 써 두고 통합 단계(H1~H8)에서 판정한다.

#### 작업 표

| ID | 상태 | 커밋 | 완료 조건 시험 파일 |
|---|---|---|---|
| R2-B1 | 기반 단계에서 완료 | `3c77de3` | (위 '### R2-B1') |
| R2-B2i | 기반 단계에서 완료 | `59ed567` | (위 '### R2-B2i') |
| R2-final | 기반 단계에서 완료 | `708a1c1` | (위 '### R2-final') |
| 문서(C22-09) | 완료 | `f3261fe` | 계획 상태 줄 '승인 · 계약 v2.3', 5절 머리, 13.8, C23-01 `firebaseToolsVersion` 15.34.1 — `tool/test/workflows_test.dart` |
| R2-B8a | 완료 | `a4c9cca` | `app/test/features/app_features_test.dart`, `bootstrap/app_bootstrapper_test.dart`(v2 묶음 — skipped·실패 모듈 기여 제거·대체 기여·늦은 기여 무시·기능 해석), `bootstrap/idle_tasks_test.dart`(6.5.1 표), `modules/media_module_test.dart`, `modules/recognition_module_test.dart`, `modules/pdf_module_test.dart`(이음새), `modules/feature_wiring_module_test.dart` v2, `modules/production_modules_test.dart`(`modulesFor` 4조합), `bootstrap/overrides_unique_test.dart` v2(표 6경우), `settings/settings_sections_test.dart`(기여 섹션 위치) |
| R2-B8b | 완료 | `6e7b753` | `app/test/routing/app_routes_test.dart`(왕복 20·잘못된 값 9 + 숫자 형식 9·`%2C`·주소에서 버림), `routing/app_router_test.dart`(`?page=&focus=` 7경우 — 인자 전달·`%2C`·잘못된 focus·page 없는 focus·`openNote` 푸시·새로고침 같은 위치), `routing/production_screens_test.dart`(`onOpenNoteAt` → 에디터 인자 3경우), `packages/pencil_bridge/test/pencil_bridge_test.dart`(디코딩·두 구독 → cancel 1회 → listen 2회째·캐시·오류 버림·`capabilities`·다른 플랫폼 채널 0회), `packages/pencil_bridge/test/api_surface_test.dart`, `app/test/pencil/pencil_stylus_extras_test.dart`, `modules/feature_wiring_module_test.dart`(Pencil 5경우), `bootstrap/overrides_unique_test.dart`(iPad 경우) |
| J0 | 진행 중 — ①②③ 완료, ④ 대기(첫 체크포인트 푸시 뒤 GitHub 실행 기록 필요) | `1fd1aea`(①②③) | `tool/test/native_config_test.dart`(파서 7·커밋된 파일 8·규칙마다 깨뜨리기 23), 웹 빌드 측정 표(아래·계획 6.15), CI 실측 표(6.16 — ④) |
| J1 | 완료 | `3ff3b76` | `tool/test/native_reqs_test.dart`(파서 9·깨끗한 픽스처 2·NR1~NR7 각각 깨뜨리기 8·실제 워크스페이스 2·`ws native-reqs` 명령 3), `native_config_test`(J1 묶음 4 — NR7을 커밋된 파일에), `ws native-reqs` 0 |
| J2 | 완료 | `0da5b71` | `native_config_test`(서명 분기 — 커밋된 파일 1·파서 2·규칙마다 깨뜨리기 4), `workflows_test` `android.yml` 묶음 15(단계 순서·NDK·시크릿은 잡 `env`만·`key.properties` 경로·**서명 세 갈래**를 셸 조각으로 실행·아티팩트 이름 두 갈래·가짜 `apksigner` 4경우) — 실제 서명은 GitHub(H6, V14) |
| J3 | 완료 | `44609e8` | `workflows_test` `ios-compile.yml` 묶음 7(입력·게이트·`macos-26`·45분·`concurrency`·시크릿·변수 없음·`--no-codesign`·`pipefail`+`tee`·아티팩트·요약 셸 조각을 표본 로그·`Podfile.lock`으로 실행) + `ios-testflight.yml` 묶음 7(`macos-26`·`IOS_SIGNING_MODE`·수동 서명 단계·**두 서명 갈래**를 가짜 `xcodebuild`로 실행·Admin 주석), `guides_test` 06 — 실행은 U19(H6) |
| J4 | 완료 | `3779a8f` | `app/test/storage/native_storage_paths_test.dart`(경로 문자열·폴더 생성(재귀·두 번째 호출)·끝 `/`·실패 4종 전파·기본 `CoreModule` 2경우), `core_module_test`(경로 묶음 8 — 두 필드 모두·순서·실패 → 기록 + 둘 다 없음·웹 stub·`configFor`·`defaultNoteStoreConfig`·`resetLocalData`·경로 중 포기), `tool/test/native_config_test.dart` '앱 셸 경로' 묶음(토큰 2·커밋된 파일 1·주석 무관 1·규칙마다 깨뜨리기 12·파일 없음 1) |
| J5 | 완료 | `16b9c4b` | `app/test/features/feature_switch_section_test.dart`(12 — 문구·빌드에서 끔·저장·시작 때와 다름·인식 꺼짐에서 수식 엔진·[다시 시작] flush → reload·녹음 중(녹음·일시정지) 막기·flush 실패·flush 2초 초과·네이티브 문구·저장 실패·가로), `settings/settings_sections_test.dart` v2(`app.features` 위치·제목·빌더), `settings_screen_test`(8개), `bootstrap/app_module_context_test.dart`(7 — 빌드 ∧ 메뉴·한 번 읽기·동시 호출·저장소 전 캐시 안 함·500 ms 초과·안쪽·읽기 실패) |
| J6 | 완료 | `864317a` | `app/test/bootstrap/idle_tasks_test.dart` 보강(`AppIdleCleanup` 4 — 마지막 콜백까지 기다림·2초 제한·기다리는 중 더한 정리·첫 작업 전 dispose), `bootstrap/bootstrap_app_test.dart`(유휴 4 — 성공 화면 ProviderScope → AppLifecycleBridge → 실행기(`success.idleTasks`)·오류 화면에는 없음 → 다시 시도 → 새 시도의 작업만·dispose 때 색인기 정리(1초) 끝난 뒤 모듈 stop·정리가 안 끝나면 2초 뒤 stop + 기록) |
| J7 | 완료 | `852cce5` | `app/test/modules/media_module_test.dart`(J7 묶음 7 — `abandon()` 초안 복구 0·1·2·실패·최근 갱신 창, 이탈 경고 상태 전이·실행기 안 첫 프레임 직후), `update/update_banner_test.dart` v2(녹음 중 안내·reload 0회·녹음 꺼짐), `web/web_platform_browser_test.dart`(Chrome — `setLeaveGuard` 리스너 1개) |
| J8 | 완료 | `b0ffee5` — 본문은 R2-B8a `a4c9cca` | `app/test/modules/recognition_module_test.dart`(J8 묶음 4 — 두 번 dispose → 1회·실행기 안 3초 뒤 start 1·scope 사라짐 → dispose 1·start 실패 → 기록 1·dispose 0·`recog.indexer` 섹션) |
| J9 | 완료 | `ea21681` | `app/test/modules/recognition_wiring_test.dart`(새 — 필드 표·`done` 두 갈래·`execute` 감싸기·동기 시작), `media_wiring_test.dart`(새 — 패널·이미지 가져오기·`media` 섹션·복구 순서·상태 안 읽음), `search_wiring_test.dart`(새 — ≤ 4 Hz·형식·dispose), `feature_wiring_module_test.dart` v2(반복 id 3경우) |
| J10 | 완료 | `fcf949d` — 본문은 R2-B8a `a4c9cca` | `app/test/modules/pdf_module_test.dart` v2(기록용 리더 start 1·dispose 1·PDF 실패 → 작업 없음 + 기본 리더·실행기 안 0 → 10 → 20 순서) |
| J11 | 완료 | `fe6100d` — 본문은 R2-B8b `6e7b753` | `app/test/routing/production_screens_test.dart`(J11 +4 — `%2C`·잘못된 focus 9가지(페이지는 열림)·page 없는 focus·폴더 검색 결과 → 보고된 주소 → 새로고침 → 같은 페이지·사각형 → 닫으면 홈), `app_router_test`(R2-B8b — 자리표시 화면 7경우) |
| J12 | 완료 | `5b71ea3` | `packages/pencil_bridge/test/pencil_wire_contract_test.dart`(28 — ⓪~⑨ + 가용성 판독기 자체 11경우), `pencil_bridge_test`(+1 — Swift 빌더 모양의 squeeze 순서·자세 없는 tap) — **컴파일은 `ios-compile.yml`(U19)**, 동작은 TestFlight 뒤(C-1) |
| J13 | 완료 | `f771299` — 능력 조회 시간 제한·실패 처리·`timestamp`는 R2-B8b `6e7b753` | `app/test/pencil/pencil_stylus_extras_test.dart`(J13 +3 — `os`·대체 `?`·`seen` 전이(구독자 없으면 안 셈·tap·hover·모르는 단계는 안 셈·종류마다 알림 1번·되돌아가지 않음·능력 불변)·두 구독자에 알림 1번), `modules/feature_wiring_module_test.dart`(Pencil 5경우 — 지원·미지원·기본 포트·실패·500 ms 초과, J13: `os` '17.5'·'?'), `settings/about_section_test.dart`(J13 +5 — 지원 안 함 2·'iOS 17.5 · 더블탭 · 호버' → 스퀴즈 받음 → 롤 받음·섹션 자신의 구독·떠나면 구독 끊김·열기 전에 받은 것·읽기 실패 문구·가로) |
| J14 | 완료 | `9e10ac3` | `app/test/settings/storage_section_test.dart` v2(첨부 파일 6 — 세 종류·없는 종류 0 MB·작은 크기 `<0.1 MB`·첨부 없음 '0개 · 0 MB'·CORE 가짜 저장소의 `bytesByType`·보일 때 1회·[다시 확인]·다시 보일 때·`usage()` 실패; 검색 색인 6 — 상태 따라감·확인 창 취소·확인 → `rebuild()` 1회·진행 중 비활성·실패 문구 + 기록 1건·닫기·가로), `settings/about_section_test.dart` v2(기능 줄 4가지 — 모두 켬·빌드에서 끔·개발자 메뉴로 끔(`skipped`)·시작 실패 + 진단 복사·가로, Pencil 줄 키), `app/test/app/licenses_test.dart`(가짜 에셋 번들 있음/없음·기록 1번·지연 읽기·앱 번들에 실제 에셋·라이선스 화면), `errors/diagnostic_report_test.dart` v2(기능 줄·`skipped` 단계), `features/feature_status_test.dart`(새 — 상태 표) |
| J14b | 완료 | `b0cefb5` | `app/test/settings/v1_copy_section_test.dart`(새, 19 — `v1CopyMimeType` 표, 다섯 상태: 사본 있음(웹·네이티브 이름)·사본 실패(quota·io·other·모르는 값)·사본 없음·아직 볼 수 없음(기록 0)·읽기 오류(기록 1), 확인 중 줄, 보일 때마다 `info`, 기본 api(CORE B2-α 선언) → '사본 없음', 내보내기 두 이름(4 MiB·4 MiB·1 B → 시트의 `BackupFile` 바이트·`info.fileName`·MIME → 내려받기)·[취소]·스트림 오류·떠나면 구독 끊김, 지우기 확인 → `delete` 1 → 다시 조회 · 취소 · 오류, 가로), `backup_export_test`(+1 — 기본 MIME `application/json`·준 MIME이 내려받기·공유까지), `settings_sections_test`(`app.v1Copy` 위치·제목·빌더), `settings_screen_test`(섹션 9개) |
| J15 | 남음 | | `test_command_test` v2·`workflows_test`(잡 5개) |
| J16 | 남음 | | `workflows_test`(functions) — 실행은 GitHub(V13) |
| J17 | 완료 | `95d88a8` | `tool/test/web_budget_test.dart`(16 — 형식 3(4.3.3 모양·잘못된 파일 7가지·커밋된 `tool/web_budget.yaml` 값), 측정 2(gzip = 파일별 `dart:io` gzip 합·없는 보고 자산 → null·빌드/`main.dart.js`/`FontManifest.json` 없음·깨진 JSON), 보고 7(한도 안 · 넘음(크기·증가분·묶음) · 원본 글꼴 한도 · 금지 글꼴 · 빌드에 없는 글꼴 파일 · `measure`는 표시만 · 표 형식), 명령 4(`check` 0 + 요약 파일 · 넘으면 1 / `measure` 0 · `--budget` · 빌드·예산 없음 → 3 · 예산 없이 `measure`)), `workflows_test`(`ci.yml` 'Web budget' 단계 — 순서·명령·조건 없음, `ws` 호출 21개) |
| J18 | 완료 | `1e29a75` | `tool/test/guides_test.dart` v2(30 — 파일 9개·README 순서 01 → 02 → 04 → 08·공통 형식 8개(08은 계약 문장 줄을 뺀 해요체)·01 첫 단락 'Hosting만'·'Spark'·'실연결'·'실연결 때 정할 것' 절·03 Functions 한 줄·04 B-1 네 단계(마지막 = `AppStrings.sectionV1Copy`·`v1CopyPresent` 머리)·B-15·B-16 하는 법·마이크·'복구된 녹음'·되돌리기 금지·`reloadBlockedByRecording`·05 아티팩트 두 이름(`android.yml` 식에서)·'고정 키 등록은 07'·'파일 두 개'·'앱을 지우지 말고'·06 `ios-compile.yml` 이름·입력·`ios-compile-<번호>`·`ITSAppUsesNonExemptEncryption`(Info.plist `false`)·07 시크릿 4개·변수(= `android.yml` 잡 `env`)·`::error::` 두 문장·요약 줄·08 **계약 7.8 A-1~A-6·B-1~B-16·C-1~C-4 순서와 문장 글자 그대로**·머리말 3줄·항목마다 '알려 줄 것'·보고 양식·B-13 순서·C-1 다시 열기) |
| J19 | 완료 | `0b3c5d2` | `app/test/integration/app_smoke_v2_test.dart`(V5 v2 — 지금 되는 단계: 시작 5모듈 ok·7.3.3 행 한 번씩·오디오/인식 행의 출처 모듈·값, 자리 4개(이미지 = 주입 가져오기·녹음 패널 = `mediaRecordingPanel`·선택/삽입 = 실제 recog 동작 id), 개발자 섹션 순서·`recog.settings` 위치·유휴 작업 4개, 5모듈 위 1차 V5 흐름, 9 라우팅(`onOpenNoteAt` → `?page=&focus=` → 에디터 인자·주소)), `integration/feature_switch_test.dart`(V15 — 기대 행 표 1 + 주입 8조합 + 모두 끔 1차 흐름 + `AppFeatures.compileTime`(H5는 `--dart-define` 3개)), `web/app_smoke_v2_browser_test.dart`(V6 v2 — `setUpAll(useInkTestFonts)`, 웹 저장소, 같은 단계, 오류 기록 0·`MissingPluginException` 0), `support/smoke_v2_fakes.dart` |
| J20 | 완료 | `8e1f05a` | `tool/test/lock_age_test.dart`(21 — 잠금 파서 3(hosted만·서버 주소·실제 워크스페이스 lock·깨진 파일 4가지), 바뀐 항목 3(새·판 바뀜·서버 바뀜 / 같음·지움 제외 / 기준에 lock 없음 → 전부), API 답 2(`published`·없는 판·깨진 답 5가지), 달력 일수(UTC 날짜 — 13·14 경계·시간대), `checkLockAge` 3(가짜 HTTP: **13일 → 위반·14일 → 통과·네트워크 오류(null·예외)·목록에 없는 판·깨진 답 → 경고**, 이름 순 요청 1번씩, 표·줄 형식, `--min-days`, 바뀐 것 없음 → 요청 0), 명령 9(실제 git 저장소 + 가짜 내려받기: 위반 → 1·통과 → 0 + 요약 파일·네트워크 오류 → 0·`--now` 없으면 컨텍스트 시계·기준 ref에 lock 없음·커밋 아닌 ref → 경고 0·사용 오류 7가지 → 2·lock 없음 → 3·**실제 `httpDownload` + 127.0.0.1 서버 → 답·닫힌 포트 → 경고**)), `workflows_test`(+1 'Lock age' 단계 — `continue-on-error`·위치·`bash -n`·가짜 `git`/`dart`로 6경우, 단계 순서·명령·`ws` 호출 22개) |
| J21 | 남음 | | `workflows_test`(android-emulator) |
| J22 | 남음 | | 마감 확인 묶음(8.2 J22 행) |
| H1~H8 | 통합 단계 | | (계획 8.3) |

#### R2-B8a — 앱 셸 v2 연결 (계획 8.1b)

- 새 파일(`app/lib/src/`): `features/app_features.dart`(4.6.1 — 섹션 UI 제외), `bootstrap/idle_tasks.dart`(4.6.2 — `AppIdlePriority`·`AppIdleTask`·`AppIdleContext`·`AppIdleTaskRunner`), `modules/idle_indexers.dart`, `modules/media_module.dart`, `modules/recognition_module.dart`, `modules/media_wiring.dart`, `modules/recognition_wiring.dart`, `modules/search_wiring.dart`.
- 바꾼 파일: `AppModule`(`isEnabled`·`idleTasks`·`fallbackContribution`), `AppModuleContext`(`compileTimeFeatures`·`resolveFeatures`·`featureOn`·`contribute`·`contributions`), `ShellContribution`, `StartupStepOutcome.skipped`, `BootstrapSuccess`(`idleTasks`·`contributions`·`features`), `AppBootstrapper(features:)`, `BootstrapApp`(ProviderScope → AppLifecycleBridge → **AppIdleTaskRunner** → 앱, `runNoteApp`은 `AppFeatures.compileTime`), `PdfModule(indexer:)`·`pdf.searchIndexer`, `FeatureWiringModule` v2(기여 합치기·이미지 가져오기 직접·개발자 표시 `[pdf.render?, media?, recog.indexer?, search.index]`), `productionModules()`(5개, `if (kFeature*)`)·`modulesFor`, `shellContributionsProvider`·`defaultSettingsSections(contributed:)`.
- 다른 영역 2차 구현은 기반 단계 표면이다: `supportedImageSources()` = 빈 집합이라 실제 앱에는 아직 `editorImageImporterProvider` override가 없다(가짜 주입 시험으로 확인), `recognitionSelectionActions()`·`recognitionInsertActions()` = 빈 목록, `mediaIoOverrides()` = 빈 목록. 실제 패키지 사례는 H2.

| 검사 | 결과 |
|---|---|
| `app` `flutter analyze --fatal-infos` | 0건 |
| `ws check` (R1–R16) | 0 |
| `ws test --package noteapp` (VM — `flutter test`) | 360 통과 · 1 건너뜀(V5) |
| `ws test --package noteapp --platform chrome` | 준비 ok · 11 통과 · 1 건너뜀(V6) · 147초 |
| `ws test --package noteapp --run-skipped -t integration` (V5, VM) | 1 통과 · 33초 |
| `ws test --package noteapp --platform chrome --run-skipped -t integration` (V6) | 1 통과 · 110초 |

#### R2-B8b — 라우팅 `?page=&focus=` · `pencil_bridge` Dart 표면 · Pencil 어댑터 (계획 8.1b)

- 커밋: `6e7b753`, 이 기록 줄은 그 뒤 커밋.

- **① 라우팅**(4.6.6·6.8, S2-6): `AppRoutes.focusQueryKey`·`note(noteId, pageId:, focus:)`, `FocusRectCodec`(`encode` 0.1 pt 반올림·끝 `.0` 없음·쉼표 그대로, `decode` 네 수·유한·`l ≤ r`·`t ≤ b`·`|v| ≤ 100000`·`%2C` 받음), `EditorRouteArgs.initialFocusRectPt`(page 없으면 assert), `AppNavigator.openNote(…, focusRectPt:)`, 라우터가 `page`가 있을 때만 `focus`를 해석, 운영 화면 빌더 `LibraryScreen(onOpenNoteAt:)` → `openNote` → `EditorScreen(initialFocusRectPt:)`. 자리표시 에디터는 'focus: …' 줄을 보인다.
- **② `packages/pencil_bridge`**(4.4.2·4.4.3·6.12.1): `lib/pencil_bridge.dart`(계약 이름 7개만 `show`), `src/pencil_events.dart`(값 타입 — `==`·`hashCode`·`toString`, `PencilCapabilities.fromWire`·`unsupported`), `src/wire.dart`(`PencilWire` 상수·`decode`), `src/pencil_bridge_impl.dart`(`isSupported`, `capabilities()` — 지원 안 함 → 채널 호출 없음, 오류 다시 던짐; `events` — 캐시한 `receiveBroadcastStream().handleError(…).map(decode).where(…).cast()`, `asBroadcastStream` 없음; `debugDroppedEvents`·`debugReset`). R2-B1 스모크 시험은 지웠다(실제 시험으로 바뀜). README 갱신. Swift는 아직 R2-B1의 빈 등록(J12) — 그때까지 iOS에서 `capabilities()`는 `MissingPluginException`이고 어댑터가 대체 능력을 쓴다.
- **③ 앱 어댑터**(4.6.5·6.12.3, X35): `src/modules/pencil_wiring.dart`(`PencilPort`), `src/pencil/pencil_stylus_extras.dart`(`PencilStylusExtrasSource`·`stylusCapabilitiesOf`·`kPencilFallbackCapabilities`·`stylusEventOf`·`stylusPreferredActionOf`·`stylusSqueezePhaseOf` — 네 종류 모두 `timestamp` 전달), `FeatureWiringModule(pencil:)` — `isSupported`이면 `start`에서 능력을 한 번 읽고(500 ms, 실패·시간 초과 → 기록 1건 + 대체 능력) `stylusExtrasProvider` override. 시험 가짜 `app/test/fakes/fake_pencil_port.dart`(모듈 생성자 주입 — S2-2).
- EDITOR 요청(인수인계 메모) 처리: `StylusExtrasSource.capabilities`(실행 중 고정)·이벤트 `timestamp`·`EditorScreen(initialFocusRectPt:)` 연결 — 끝. 능력 조회 시간 제한·실패 처리도 여기서 했다(J13 몫을 당김 — 아래 '계획과 다르게 한 점').
- `asBroadcastStream()`을 넣으면 `pencil_bridge_test`의 '두 구독 → cancel 1회' 시험이 실패하는 것을 한 번 확인했다(되돌림).

| 검사 | 결과 |
|---|---|
| `app`·`pencil_bridge` `flutter analyze --fatal-infos` / 루트 `flutter analyze --fatal-infos` | 0건 / 0건 |
| `dart format --output=none --set-exit-if-changed app packages/pencil_bridge` | 변경 0 |
| `ws check` (R1–R16) | 0 |
| `ws test --package pencil_bridge` (VM) | 33 통과 |
| `ws test --package noteapp` (VM) | 428 통과 · 1 건너뜀(V5) · 63초 |
| `ws test --package noteapp --platform chrome` | 준비 ok · 11 통과 · 1 건너뜀(V6) · 87초 |
| `ws test --package noteapp --run-skipped -t integration` (V5, VM) | 1 통과 · 28초 |
| `ws test --package noteapp --platform chrome --run-skipped -t integration` (V6) | 1 통과 · 97초 |
| `dart test tool/test` | 372 통과 · 75초 |

#### J0 ①②③ — 네이티브 설정 · `native_config` 정적 시험 · 웹 빌드 실측 (계획 8.2, 6.10.1, 6.11.1~6.11.4, 6.15)

- 커밋: `1fd1aea`(①②③), 이 기록 줄은 그 뒤 커밋. ④는 아직.

- **① 네이티브 설정 파일**(부록 B): `app/android/app/src/main/AndroidManifest.xml`(`xmlns:tools`, 권한 5개 `INTERNET`·`RECORD_AUDIO`·`FOREGROUND_SERVICE`·`FOREGROUND_SERVICE_MICROPHONE`·`POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED` `tools:node="remove"`, 라벨 `필기노트`, `allowBackup="false"`(D20), `flutter_foreground_task` `ForegroundService`(`microphone`·`exported=false`·`stopWithTask=true`), `RebootReceiver` 제거 — 서비스·수신기 이름은 pub 캐시 `flutter_foreground_task-11.0.3`의 매니페스트·README로 다시 확인함), `app/ios/Runner/Info.plist`(마이크·사진·카메라 문구 확정본 글자 그대로, `UIBackgroundModes` `[audio]`, `ITSAppUsesNonExemptEncryption` false), `project.pbxproj` `IPHONEOS_DEPLOYMENT_TARGET` 3곳 15.0 → **15.5**, 새 `app/ios/Podfile`(Flutter 3.47.9 `templates/cocoapods/Podfile-ios` + ML Kit README 줄 — `platform :ios, '15.5'`·`$iOSVersion`·armv7 제외·배포 대상 올림), `Debug.xcconfig`·`Release.xcconfig` 첫 줄 `#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.<debug|release>.xcconfig"`(Flutter `addPodsDependencyToFlutterXcconfig`가 쓰는 줄과 같음 — CI 빌드가 저장소 파일을 바꾸지 않게).
- **② `tool/src/native_config.dart`**: `NativeConfigPaths`, `AndroidManifestInfo.parse`(`package:xml` — 주석·속성 순서 무관), `parsePlist`, `pbxDeploymentTargets`, `PodfileInfo.parse`(줄 전체 주석 무시), `xcconfigIncludes`, `NativeConfig.load`, `AppNativeExpectations`(값 표), `appNativeConfigProblems`(한 줄씩 — J1 `ws native-reqs`가 같은 `NativeConfig`를 읽는다). **`tool/test/native_config_test.dart`**: 파서 단위 시험, 커밋된 파일 검사(문구 글자 그대로·15.5 정확히 3번·Podfile 템플릿 줄 보존 — 이 Flutter의 템플릿 파일과 대조), 규칙마다 커밋된 파일을 하나씩 깨뜨려 그 문제 한 줄(부팅 권한은 두 줄)만 나오는지 23경우.
- **③ 웹 빌드 실측**(잠금 안 — `ws with-heavy-lock`): 기본 `flutter build web --release`와 기능 셋을 끈 빌드. 결과 표와 묶음별 한도 제안은 계획 6.15 'J0 실측 결과'(여기 요약):

| 측정 | 값 |
|---|---|
| `main.dart.js` 기본 | 4,694,993 B · gzip **1,382,988 B**(1차 기준 +16,950 B, 한도 1,666,038 B까지 283,050 B) |
| `main.dart.js` 기능 셋 끔(`FEATURE_MEDIA`·`FEATURE_RECOGNITION`·`FEATURE_MATH_ENGINE` = false) | 4,682,895 B · gzip 1,379,757 B(−3,231 B) |
| 시작 글꼴 합계 | 661,088 B · gzip **382,428 B**(한도 400,000 B까지 17,572 B) — KaTeX 12패밀리 20파일 gzip 371,014 B, 아이콘 gzip 11,414 B(MaterialIcons 10,391 · CupertinoIcons 1,023) |
| `NoteSans` | `FontManifest`·`AssetManifest`에 없음(지연 적재), 빌드 산출물에는 파일로 있음 |
| `record_web` 워크릿 | 11,762 B |
| `ws web-assets verify` | 2개, 문제 0 |

- 한도 제안(총괄 결정 — changeRequests): KaTeX `gzip_max` 380,000 · 아이콘 `gzip_max` 20,000(합계 400,000 유지). 계획 문장('KaTeX 실측 + 5%')대로면 KaTeX 389,565 + 아이콘 실측 11,414가 이미 합계 한도를 넘어, 합계를 410,000으로 올리는 안도 함께 적었다.
- **④ CI 단계별 시간 실측**: 컨테이너에서 할 수 없다(푸시·GitHub 실행 기록). 총괄의 첫 체크포인트 푸시(R2-B8a·R2-B8b·J0) 뒤 `ci.yml` 실행의 단계 시간을 받아 6.16 표·월 분 재계산·잡 분리안(J15)을 정한다 — 그때까지 J0은 '진행 중'.

| 검사 | 결과 |
|---|---|
| `dart test tool/test/native_config_test.dart` | 37 통과 |
| `cd app && flutter build web --release` (잠금 안) | 성공 · 컴파일 260초(부하 평균 8 — 다른 에이전트와 CPU 공유) |
| 같은 빌드 + `--dart-define` 기능 셋 false | 성공 · 136초 |

#### J1 — `ws native-reqs` (계획 8.2, 4.3.2, 6.3)

- 커밋: `3ff3b76`.

- **`tool/native_requirements.yaml`**(4.3.2 그대로 + `flutter_defaults: {min_sdk: 24, compile_sdk: 36}` — 6.3 문장의 대체값): `app:`(15.5·`flutter`·`flutter`·필기노트·`false`·필기노트), `cocoapods_only_allowed` ML Kit 둘, `plugins` 10개(영역 열 = 요구를 낸 계획서), `plugins_without_requirements` 13개, `app_extra`(`INTERNET`, `ITSAppUsesNonExemptEncryption: false`).
- **`tool/src/native_reqs.dart`**: `NativeRequirements.parse/load`(키·태그·SDK 값 검사, 두 목록 겹침 거절), `FlutterPluginsDependencies.parse/load`(`plugins.ios/android` — `native_build`·`dev_dependency`, `dependencyGraph` 이름 집합, 상대 경로는 파일 위치 기준), `podspecIosMinimum`(`s.platform`·`ios.deployment_target` 큰 값), `swiftPackageIosMinimum`(`"x"`·`.vNN`·`.vNN_M`), `flutterGradleDefaults`(`FlutterExtension.kt`), `PluginNativeInfo.read`(`ios/`·`darwin/`·`android/build.gradle(.kts)`), `nativeRequirementProblems`(NR7 — `native_config_test`와 같은 함수), `checkNativeRequirements`(NR1~NR7) → `NativeReqsReport.format()`(표·앱 줄·발견·요약).
- **`tool/src/native_config.dart`**: `gradleSdkValue`(kts·groovy·괄호·주석 무시, Flutter 기본값 식 → `flutter`), `AndroidGradleInfo`, `NativeConfigPaths.androidGradle`, `NativeConfig.androidGradle`(J2가 서명 분기를 여기에 더한다).
- **`ws native-reqs`**(`cli.dart`): 입력이 없거나 틀리면 종료 3(`flutter pub get` 안내), 위반 1, NR4만 있으면 0. NR7에는 `appNativeConfigProblems`(J0) 줄도 더한다(같은 문구는 한 줄).
- 실제 워크스페이스 실행 결과(컨테이너): 플러그인 23개, `app: ios 15.5 · minSdk 24 (flutter — FlutterExtension.kt) · compileSdk 36 (flutter — FlutterExtension.kt) · CocoaPods-only: google_mlkit_commons, google_mlkit_digital_ink_recognition`, 위반 0·경고 0. `plugin_packages`(53) = `dependencyGraph`. Dart 전용(`native_build: false`)은 `path_provider_android` 2.3.1·`path_provider_foundation` 2.6.0.

| 검사 | 결과 |
|---|---|
| `dart run tool/ws.dart native-reqs` | 종료 0 · 23개 · 위반 0 · 경고 0 |
| `dart test tool/test/native_reqs_test.dart tool/test/native_config_test.dart` | 65 통과 |
| `dart test tool/test` | 437 통과 · 130초 |
| `dart analyze --fatal-infos tool` / `dart format` | 0건 / 변경 0 |
| `ws check` (R1–R16) | 0 |

#### J2 — release 고정 서명 · `android.yml` v2 (계획 8.2, 6.10.2·6.10.3)

- 커밋: `0da5b71`.

- **`app/android/app/build.gradle.kts`**(6.10.2 그대로): `rootProject.file("key.properties")`(= `app/android/key.properties`, gitignore에 있음)가 있으면 `signingConfigs.create("release")`(네 값) + release 빌드가 그 키, 없으면 debug 키(1차와 같음).
- **`tool/src/native_config.dart`**: `AndroidGradleInfo`에 `keyPropertiesFile`·`createsReleaseSigningOnlyWithKeyProperties`·`signingProperties`·`releaseUsesReleaseKeyElseDebug`(주석 무시·변수 이름 무관), `AppNativeExpectations.keyProperties`·`signingProperties`, `appNativeConfigProblems`에 서명 줄 4종.
- **`.github/workflows/android.yml` v2**(6.10.3): 잡 `env`에 시크릿 4개 + `vars.ANDROID_CERT_SHA256`. 단계 `Signing`(`id: signing` — Checkout 바로 뒤): 넷 다 있음 → `$RUNNER_TEMP/release.jks` + `key.properties` 4줄 + `mode=release` / 하나라도 없고 변수 있음 → `::error::고정 키 서명 재료가 없어요 — 이 APK는 덮어 설치할 수 없어 만들지 않아요(docs/guides/07-android-signing.md)` + 실패(뒤 단계는 정리만 돈다) / 그 밖 → `mode=debug`. `Cache Android NDK`(`ndk-28.2.13676358` — `FlutterExtension.kt` `ndkVersion`과 대조), 훅 캐시 단계 이름 'Build hooks (downloads sqlite3 when not cached)', `Check signature`(가장 높은 build-tools의 `apksigner verify --print-certs` → `SHA-256 digest`, release이고 변수가 있는데 다르면 실패 — 변수는 keytool 꼴(대문자·콜론)도 받음, 실행 요약 '서명: 고정 키 (앞 16자)' 또는 '서명: debug 키 — 이전 APK 위에 덮어 설치할 수 없어요. 설치가 안 되면 앱을 지우지 말고 알려 주세요'), 아티팩트 이름 `noteapp-${{ … 'apk' || 'debug-signed' }}-<run>`, `Remove signing material`(`if: always()`, 마지막).
- 실제 서명·APK는 GitHub에서만(H6 — V14). 고정 키 만들기·전달(6.10.4, U20 ①)은 사용자와 함께 하는 일이라 이 작업에 넣지 않았다(아래 '다음 세션 메모').

| 검사 | 결과 |
|---|---|
| `dart test tool/test/native_config_test.dart tool/test/workflows_test.dart` | 48 · 63 통과(서명 세 갈래·가짜 `apksigner`는 `bash -e`/`-eo pipefail`로 실제 실행) |
| `dart test tool/test` | 454 통과 · 90초 |
| `dart analyze --fatal-infos tool` / `dart format` | 0건 / 변경 0 |
| `ws check` (R1–R16) / `ws native-reqs` | 0 / 0 |

#### J3 — `ios-compile.yml` · `ios-testflight.yml` 갱신 (계획 8.2, 6.11.5·6.11.6)

- 커밋: `44609e8`, 커밋 번호 기록은 그 뒤 커밋.

- **`.github/workflows/ios-compile.yml`**(새, 6.11.5): `workflow_dispatch`만(입력 `confirm` 'macOS 10배 과금 확인: yes 입력', `ipa` bool 기본 false), 잡 `if: inputs.confirm == 'yes'`, `macos-26`, 45분, `concurrency: ios-compile`(취소 안 함), 시크릿·변수 없음. 단계: Checkout → Flutter(`cache: true`) → `Cache CocoaPods`(`~/Library/Caches/CocoaPods`·`app/ios/Pods`, key `pods-${{ hashFiles('pubspec.lock', 'app/ios/Podfile') }}`) → 훅 캐시(1차 키) → `pub get --enforce-lockfile` → `ws build-info --channel experiment` → `set -o pipefail` + `flutter build ios --release --no-codesign … 2>&1 | tee "$RUNNER_TEMP/ios-build.log"`(걸린 초 → `steps.build.outputs.seconds`) → (`ipa`) `flutter build ipa --no-codesign …` + `ditto`로 `Runner.xcarchive.zip` → 요약(`always()` — 걸린 시간, 'This will become an error' 줄 수와 Flutter가 적은 CocoaPods 전용 플러그인 이름, `Podfile.lock` `PODS:` 수) → 아티팩트 `ios-compile-<run>`(`Podfile.lock`·빌드 로그, `always()`, 7일), (`ipa`) `ios-xcarchive-<run>`(7일).
- **`.github/workflows/ios-testflight.yml`**(6.11.6, 초안 유지): `macos-latest` → `macos-26`, 잡 `env`에 `IOS_SIGNING_MODE: ${{ vars.IOS_SIGNING_MODE || 'cloud' }}`. `manual`이면 단계 'Certificate and profile (manual signing)'(그 단계 `env`에만 시크릿 `IOS_DIST_P12_BASE64`·`IOS_DIST_P12_PASSWORD`·`IOS_PROFILE_BASE64`) — 임시 키체인에 `.p12`, 프로파일을 `Provisioning Profiles/<UUID>.mobileprovision`로, `IOS_KEYCHAIN`·`IOS_PROFILE_NAME`·`IOS_BUNDLE_ID`를 `$GITHUB_ENV`로. Archive는 `cloud` → 1차의 `-allowProvisioningUpdates`·API 키·`CODE_SIGN_STYLE=Automatic`, `manual` → `CODE_SIGN_STYLE=Manual`·`CODE_SIGN_IDENTITY=Apple Distribution`·`PROVISIONING_PROFILE_SPECIFIER`. Export는 `manual`이면 ExportOptions 사본을 `signingStyle manual`·`signingCertificate`·`provisioningProfiles`(PlistBuddy — 번들 ID의 점 때문)로 고친다. 정리 단계(`always()`, 마지막)는 키체인도 지운다. 머리 주석에 '클라우드 서명은 Admin 키가 필요할 수 있음'(조사 04 요약 11)·'ios-compile.yml 먼저'.
- **안내서 06**: 4단계 아래 '서명 방식' 소절(클라우드 기본·Admin 보고, 수동 서명 시크릿 3개 + Variable `IOS_SIGNING_MODE` = `manual`, CSR은 Claude가), 문제 해결 줄 보강. `guides_test` 06(잡 `env` 이름이 안내서에 있음)이 이것을 본다.
- 실행은 U19 승인 때(H6) — 컨테이너에는 macOS가 없다.

| 검사 | 결과 |
|---|---|
| `dart test tool/test/workflows_test.dart tool/test/guides_test.dart` | 73 · 22 통과 |
| `dart test tool/test` | 464 통과 · 130초 |
| `dart analyze --fatal-infos tool` / `dart format` | 0건 / 변경 0 |
| `ws check` (R1–R16) | 0 |

#### J4 — 네이티브 저장 경로 (계획 8.2, 4.6.3·4.6.4·6.9, 계약 7.2.6 v2.1)

- **`app/lib/src/storage/`**(새): `native_storage_paths.dart`(`export 'native_storage_paths_stub.dart' if (dart.library.io) 'native_storage_paths_native.dart' show resolveNativeStoragePaths` + 타입 export), `native_storage_paths_types.dart`(`NativeStoragePaths` — `==`·`hashCode`·`toString`), `_stub.dart`(null), `_native.dart`(`getApplicationSupportDirectory()` → `<support>/noteapp/`를 `create(recursive: true)` → `…/noteapp.sqlite`·`…/assets`; `assets/`·파일은 CORE 몫이라 만들지 않음, 실패는 그대로 던짐). `path_provider`는 이 파일만 import(R4).
- **`CoreModule(nativePaths:)`**(기본 `resolveNativeStoragePaths`): `start`가 먼저 경로를 읽고(던지면 기록 1건 source module, 경로 없음) 있으면 `publish<NativeStoragePaths>`, 그다음 1차 순서. 경로를 읽는 동안 `onStartAbandoned()`가 불리면 열지 않고 돌아간다(늦은 저장소가 생기지 않게). **`defaultNoteStoreConfig`**: `context.maybe<NativeStoragePaths>()` 하나에서 `nativeDatabasePath`·`nativeAssetDirectoryPath` 둘 다(없으면 둘 다 없음). `resetLocalData`는 같은 config(두 경로)로 지운다.
- **`tool/src/app_shell_storage.dart`**(새, J0에서 미룬 '앱 셸 두 경로 정적 묶음'): `dartTokens`(주석 버림·문자열 한 토큰)·`appShellStoragePathProblems` 5규칙 — 조건부 export, `path_provider`·`_native.dart`를 다른 `lib/` 파일이 부르지 않음, `defaultNoteStoreConfig`의 두 필드가 한 번씩 같은 변수(`context.maybe<NativeStoragePaths>()`)에서, `CoreModule` 기본값 두 개, `productionModules()`·`modulesFor()`가 인자 없는 `CoreModule()`.
- VM 시험의 기본 경로 함수는 `MissingPluginException`(시험 바인딩 없으면 'Binding has not yet been initialized')으로 던져 기록 1건이 생긴다 — 오류 기록·순서를 세는 시험(`core_module_test`·`production_modules_test`·`pdf_wiring_test`·`feature_wiring_module_test`·`overrides_unique_test`·`bootstrap_app_test`·V5 `app_smoke_test`)은 새 가짜 `test/fakes/fake_native_paths.dart`의 `noNativePaths`를 넘긴다. 늦은 저장소 시험 2개는 경로를 읽는 한 차례가 더 생겨 `flushMicrotasks()` 한 번 뒤에 포기한다(시나리오 '여는 중 20초 초과' 그대로).
- H2 몫: 실제 CORE VM 파일 DB로 한 번(`openNoteStore` → 노트 1개 → 닫고 다시 열기 → 남아 있음). 실기기 위치·백업 제외는 A-1.

| 검사 | 결과 |
|---|---|
| `app` `flutter analyze --fatal-infos` / 루트 `flutter analyze --fatal-infos` | 0건 / 0건 |
| `dart format --output=none --set-exit-if-changed app tool` | 변경 0 |
| `ws check` (R1–R16) | 0 |
| `ws test --package noteapp` (VM) | 446 통과 · 1 건너뜀(V5) · 51초 |
| `ws test --package noteapp --run-skipped -t integration` (V5, VM) | 1 통과 · 28초 |
| `ws test --package noteapp --platform chrome` | 준비 ok · 11 통과 · 1 건너뜀(V6) · 77초 |
| `dart test tool/test/native_config_test.dart` | 65 통과 |

#### J5 — 개발자 메뉴 기능 스위치 · 설정 배치 (계획 8.2, 4.6.1·6.6·6.17·S2-9)

- **`app/lib/src/features/feature_switch_section.dart`**(새): `FeatureSwitchSection`(섹션 `app.features` '기능 켜고 끄기') — 스위치 3개('녹음' · '녹음·녹음 패널. 이미지 넣기는 꺼지지 않아요', '인식' · '손글씨·수식 인식, 자동 도형 보정', '수식 엔진'), 값은 `settingsSnapshotProvider`, 쓰기는 `settingsRepositoryProvider.set(AppFeatureKeys.of(f), v)`. 빌드에서 꺼진 스위치는 비활성·꺼짐·'이 빌드에서 꺼져 있어요'. **빌드 ∧ 메뉴**가 이번 시작(`appFeaturesProvider`)과 `isOn`으로 다르면 '다시 시작하면 적용돼요' + 웹 [다시 시작](녹음 중 → 6.17 문구·reload 0회 / 아니면 `store.flush()`(2초) → `web.reload()`), 네이티브는 '… 앱을 완전히 닫았다가 다시 열어 주세요'(단추 없음). `FeatureSwitchSectionKeys`(시험·V15).
- **설정 배치**(S2-9): `defaultSettingsSections`에 `app.features`를 `editor.developer` 뒤에(`app.v1Copy`는 J14b). 기여 섹션은 R2-B8a 그대로 `library.newNote` 뒤.
- **`AppModuleContext.resolveFeatures`**: 저장소가 publish되기 전 호출은 빌드 값을 돌려주되 **캐시하지 않는다**(전에는 캐시해서 그 뒤 모듈도 메뉴 값을 못 봄). 문자열 `AppStrings.reloadBlockedByRecording`은 J7 업데이트 배너도 쓴다.
- 시험 가짜: `test/fakes/fake_settings_repository.dart`(읽기 기록·지연·실패), `CountingNoteStore.settingsOverride`.

| 검사 | 결과 |
|---|---|
| `app` `flutter analyze --fatal-infos` | 0건 |
| `dart format` (app) | 변경 0 |
| `ws test --package noteapp` (VM) | 465 통과 · 1 건너뜀(V5) · 48초 |
| `ws test --package noteapp --run-skipped -t integration` (V5, VM) | 1 통과 · 31초 |
| `ws test --package noteapp --platform chrome` | 준비 ok · 11 통과 · 1 건너뜀(V6) · 99초 |
| `ws test --package noteapp --platform chrome --run-skipped -t integration` (V6) | 1 통과 · 135초 |

#### J6 — 유휴 작업 실행기 마무리 (계획 8.2, 6.5.1 ⑤)

- R2-B8a에서 30초 기록·늦은 `onDispose` 즉시 호출·dispose 역순 2초는 끝났다. 이번에 남은 '정리 순서'를 넣었다.
- **`AppIdleCleanup`**(`idle_tasks.dart`, 앱 내부): 끝나지 않은 실행기 정리(`onDispose` 콜백들)를 모아 `done`으로 기다린다. `AppIdleTaskRunner(cleanup:)`(선택 인자)가 dispose 때 자기 정리를 넘긴다.
- **`BootstrapApp`**: 실행기에 `cleanup`을 주고, 모든 `shutdown()`(다시 시도·데이터 지우기·위젯 dispose = 앱 끝) 앞에서 `await _idleCleanup.done` — 색인기 `dispose`가 끝난 뒤 모듈이 멈추고(저장소 닫기 포함), 새 scope가 옛 색인기와 겹치지 않는다. 위젯 트리는 자식부터 unmount되므로 `BootstrapApp.dispose` 때 실행기 정리는 이미 시작돼 있다.
- `bootstrap_app_test`의 `runNoteApp` 시험이 앞 시험이 가짜 시계를 오래 돌리면 실패하는 것을 찾았다(`runApp`의 warm-up 프레임이 앞 시험의 마지막 프레임 시각을 다시 씀 → 스플래시 스피너 ticker가 시간이 거꾸로 감). `runNoteApp` 전에 `pump()` 한 번.

| 검사 | 결과 |
|---|---|
| `app` `flutter analyze --fatal-infos` / `dart format` | 0건 / 변경 0 |
| `ws test --package noteapp` (VM) | 473 통과 · 1 건너뜀(V5) · 70초 |
| `ws test --package noteapp --run-skipped -t integration` (V5, VM) | 1 통과 · 43초 |
| `ws test --package noteapp --platform chrome` | 준비 ok · 11 통과 · 1 건너뜀(V6) · 97초 |

#### J7 — `MediaModule` 완성 (계획 8.2, 6.5.2·6.17, 4.6.4·4.6.7)

- **`WebPlatform.setLeaveGuard(bool)`**(4.6.7 그대로): 브라우저 구현은 JS 함수 하나(`late final`)를 `beforeunload`에 붙이고 뗀다(`preventDefault()` + `returnValue = ''`). 같은 값이면 아무것도 하지 않아 리스너는 언제나 0개 또는 1개, 던지지 않는다. VM·네이티브 stub은 아무것도 하지 않는다. `FakeWebPlatform`은 호출 목록 `leaveGuardCalls`와 현재 값 `leaveGuard`를 남긴다.
- **`media.leaveGuard`**(immediate, 6.17): `audioRecorderServiceProvider.statusStream`(구독 때 현재 값부터 — 계약 7.2.4) → `web.setLeaveGuard(status.isActive)`. 스트림 오류는 기록 1건(source module). 정리(`onDispose`)는 구독 취소(기다리지 않음) + `setLeaveGuard(false)`.
- **`media.recoverDrafts`**: 본문은 R2-B8a의 `recoverPendingRecordings` 그대로(`pendingDrafts()`만 따름 — `status.isActive`를 보지 않음, `startedAt` 오름차순, 실패는 'recoverDraft <draftId> failed: …' 기록 후 다음).
- **`UpdateBanner`**(6.17): [새로고침] 때 `ref.read(audioRecorderServiceProvider).status.isActive`(녹음·일시정지)면 새로 고치지 않고(flush도 없음) 배너에 둘째 줄 '녹음 중에는 새로 고칠 수 없어요. 녹음을 멈춘 뒤 눌러 주세요.'(문구는 J5의 `AppStrings.reloadBlockedByRecording`). 다음 누름에서 다시 확인 — 녹음이 끝났으면 둘째 줄을 지우고 1차 흐름(flush → reload). `ConsumerWidget` → `ConsumerStatefulWidget`(생성자 그대로).
- 시험: `media_module_test` J7 묶음 7 — 복구 5(초안 0·1(원래 `recordingId`·'복구된 녹음'·초안 지워짐)·2(`pendingDrafts()`가 최신부터 줘도 오래된 것부터)·하나 실패(기록 1건·다음 계속·실패한 초안 남음)·최근 갱신 창 안 초안 제외 → 창이 지난 뒤 다음 시작에서 복구), 이탈 경고 2(상태 전이 → 켬·일시정지도 켬·정지 → 끔·정리 → 끔 + 구독 끊김 / 실행기 안: 첫 프레임 직후 3초 지연 전·앞의 긴 복구 작업(25초)이 도는 동안 녹음 시작 → 켬 → 정리 → 끔). 초안은 모두 CORE `FakeAudioRecorder.abandon()`(녹음기 A)으로 만들고, 같은 저장소의 녹음기 B를 `MediaModule(mediaOverrides:)` 주입 인자로 넣어 부트스트래퍼 → `success.overrides`·`success.idleTasks`로 돌린다. `update_banner_test` v2 2(녹음 중·일시정지 → 안내·`notifyAppHidden` 0회·`reload` 0회 → 정지 뒤 누름 → reload 1회 / 녹음 꺼짐(기본 `UnsupportedAudioRecorder`) → reload). `web_platform_browser_test`(Chrome) `setLeaveGuard` 3(두 번 켜도 리스너 1개·두 번 꺼도 0개·켜고 끄기 두 번·실제 `beforeunload`가 취소됨 — `preventDefault`를 센 수로 리스너 수를 잰다).

| 검사 | 결과 |
|---|---|
| `app` `flutter analyze --fatal-infos` / `dart format` | 0건 / 변경 0 |
| `ws test --package noteapp` (VM) | 482 통과 · 1 건너뜀(V5) · 78초 |
| `ws test --package noteapp --platform chrome` | 준비 ok · 14 통과 · 1 건너뜀(V6) · 92초 |

#### J8 — `RecognitionModule` 완성 (계획 8.2, 4.6.4·6.5)

- 본문(설정 → `RecognitionConfig`, 기여 — 선택·삽입 메뉴·`recog.settings`·`recog.indexer` 섹션, `recognition.indexer` 유휴 작업)은 R2-B8a에서 이미 완성(`a4c9cca`). 이번에는 완료 조건 시험만 보탰다 — 코드 변경 없음.
- `recognition_module_test` J8 묶음 4: 컨텍스트를 두 번 dispose해도 색인기 `dispose` 1회 · **실제 `AppIdleTaskRunner` 안**: 2.9초에는 시작 안 함 → 3초 뒤 읽기 1·start 1, 루트 scope가 사라지면 dispose 1, 다시 트리를 바꿔도 그대로(1, 1)·기록 0 · `start()`가 던지면 기록 1건('idle task recognition.indexer failed', source module)·dispose 등록 없음(0) · `recog.indexer` 섹션(id·제목 '손글씨 색인'·`lines`가 `recognitionDevOverlayLinesProvider`의 같은 객체). 기존(R2-B8a): 설정 4조합 + 메뉴로 끔 + 잘못된 값 4개(null + 기록 1건, `details` = 원래 값), 리더 null → 작업 없음, start 1·dispose 1, 꺼짐 2경우. provider override 가짜 없음(기록용 `IndexerHandleReader` — `test/fakes/idle_fakes.dart`의 `RecordingIndexer`).
- 실제 색인기의 '두 번 `dispose` 안전'은 H2(계획 8.4).

| 검사 | 결과 |
|---|---|
| `app` `flutter analyze --fatal-infos` / `dart format` | 0건 / 변경 0 |
| `flutter test test/modules/recognition_module_test.dart` | 22 통과 |

#### J9 — 자리 변환 · 연결 함수 시험 · 합치기 규칙 (계획 8.2, 6.7, 4.6.5)

- 연결 함수 세 파일(`recognition_wiring.dart`·`media_wiring.dart`·`search_wiring.dart`)의 본문은 R2-B8a. 이번에는 **합치기 규칙**(6.7 '같은 id의 메뉴 항목 → 디버그 assert + 오류 기록, 뒤의 것 버림')을 `FeatureWiringModule.start`에 넣었다: 기여의 선택·삽입 항목을 모듈 순서로 잇되 칸(선택·삽입)마다 id가 이미 나왔으면 기록 1건('duplicate <칸> menu item id <id> — the one of <모듈> is dropped', `details` 'first contributed by <모듈>', source module) + 버림. 모든 기록 뒤 디버그 빌드에서 assert(시작 실패 → 비필수라 그 모듈 override 없음). 시험용 정적 스위치 `FeatureWiringModule.debugAssertUniqueMenuIds`(`@visibleForTesting`, 기본 true).
- 시험: `recognition_wiring_test`(새, 10) — 선택 대상 필드 표 전부(`strokes`·`objects` 같은 객체·`areaPt` = `boundsPt`·`execute` 그대로·`done` = `clearSelection`), 삽입 대상(빈 `strokes`·`objects`·`areaPt` = `visibleRectPt`·`execute` 전달), 삽입 `done`: `AddObjects` 마지막 객체·`CompositeCommand` 안(중첩도) 마지막·추가 없는 뒤 명령은 기억 유지·뒤의 추가가 바꿈·추가 없음 → 아무것도 안 함·던지는 명령 → 기억 안 함, 메뉴 항목 두 종류 — `onSelected`가 **첫 마이크로태스크 전에** `run`을 부르고 `run`의 Future를 돌려줌·`isVisible` 같은 대상·삽입은 `isVisible` 안 씀. `media_wiring_test`(새, 6) — 패널 인자(`media_module_test`에서 옮김), `mediaImageImporterOrNull`(소스 없음 → null / 있으면 그 소스·`importImageForNote`·수정 불가), `media` 섹션(같은 `ValueListenable`), `recoverPendingRecordings` 3(0개·`startedAt` 오름차순 + null 결과는 세지 않음·실패 기록 문구 'recoverDraft d-b failed: Bad state: …' 후 다음 — 녹음기의 `status`를 읽으면 실패하는 가짜로 '복구는 상태를 보지 않음'을 확인). `search_wiring_test`(새, 8 — fake_async) — 줄 형식(없음·재구축 중·지역 시각 `MM-dd HH:mm:ss`), **100 Hz 상태 → 1초에 4번·간격 ≥ 250 ms·조용해지면 마지막 상태**, 조용한 뒤 다음 상태는 바로, 스트림 오류 → 줄 유지, dispose → 구독 끊김·대기 타이머 없음, `searchIndexSection`(id·제목·provider dispose 때 줄도 dispose). `feature_wiring_module_test` v2 +3 — 반복 id(assert 끔: 기록 2·첫 것 남음·순서 / 기본(assert 켬): 기록 2 뒤 시작 실패(`failedNonCritical`)·에디터 자리 기본값 / 칸이 다르면 같은 id여도 기록 없음).

| 검사 | 결과 |
|---|---|
| `app` `flutter analyze --fatal-infos` / `dart format` | 0건 / 변경 0 |
| `ws test --package noteapp` (VM) | 512 통과 · 1 건너뜀(V5) · 69초 |

#### J10 — `PdfModule` v2 (계획 8.2, 4.6.4·6.5)

- `pdf.searchIndexer` 유휴 작업(주입 이음새 `indexer: IndexerHandleReader`, 기본 `readPdfSearchIndexer`)은 R2-B8a ④에서 완성(`a4c9cca`) — 이번에는 시험만 보탰다(코드 변경 없음).
- `pdf_module_test` v2 +2: 기본 리더가 가짜 저장소 위에서 `pdfSearchIndexerProvider`를 읽어(그 provider는 `noteStoreProvider`가 있어야 함 — PDF 인수인계 요청 2) start·dispose를 넘기고, 작업의 dispose 뒤 provider 자신의 `onDispose`(두 번째 dispose)도 던지지 않음(R2-B4 표면 — 실제 색인기의 '두 번 dispose 안전'은 H2) · **실제 실행기 안 순서**: 모듈 순서를 recognition → pdf → media로 넣어도 `media.recoverDrafts`(0) → `pdf.searchIndexer`(10) → `recognition.indexer`(20), 기록 0. 기존(R2-B8a): 작업 1개·우선순위·3초·기록용 리더로 start 1·dispose 1·start 실패 → dispose 등록 없음·PDF 실패 → 작업 없음(리더 읽기 0).

| 검사 | 결과 |
|---|---|
| `app` `flutter analyze --fatal-infos` / `dart format` | 0건 / 변경 0 |
| `flutter test test/modules/pdf_module_test.dart` | 10 통과 |

#### J11 — 검색 결과 → 위치로 열기 마무리 (계획 8.2, 4.6.6·6.8)

- 커밋: `fe6100d`, 이 기록 줄은 그 뒤 커밋.
- 코드(라우터 `?page=&focus=`·`FocusRectCodec`·`LibraryScreen(onOpenNoteAt:)` → `openNote` → `EditorScreen(initialFocusRectPt:)`)는 R2-B8b ①에서 끝났다(`6e7b753`) — 이번에는 운영 화면 시험만 보탰다(코드 변경 없음).
- `production_screens_test` +4: `%2C`로 받은 focus → 같은 사각형 · 읽을 수 없는 focus 9가지(`l > r`·`t > b`·셋·다섯·숫자 아님·빈 값·`1e9`·100001·`NaN`) → `EditorScreen`은 같은 noteId·pageId로 열리고 사각형 없음 · page 없는 focus → 버림 · 폴더 `/folders/f9`의 검색 결과(`onOpenNoteAt`) → 브라우저에 보고된 주소(`routeInformationUpdated`)가 `AppRoutes.note(…, focus: 0.1 pt 반올림)` → 닫으면 그 폴더 → 다시 열고 그 주소로 새 앱 시작(새로고침) → 같은 noteId·pageId·사각형, 아래에 라이브러리 없음 → 닫으면 홈.

| 검사 | 결과 |
|---|---|
| `app` `flutter analyze --fatal-infos` / `dart format` | 0건 / 변경 0 |
| `flutter test test/routing/production_screens_test.dart` | 14 통과 |
| `ws test --package noteapp` (VM) | 518 통과 · 1 건너뜀(V5) · 108초 |

#### J12 — `pencil_bridge` Swift 구현 · 와이어 대조 시험 (계획 8.2, 4.4.3·4.4.4·6.12.2·6.12.4)

- 커밋: `5b71ea3`, 이 기록 줄은 그 뒤 커밋.
- Swift 파일 4개(`ios/pencil_bridge/Sources/pencil_bridge/`): `PencilBridgePlugin.swift`(플러그인 — `register(with:)`는 채널 두 개와 핸들러만, UI 작업 없음; `handle` → `capabilities`, 그 밖은 `FlutterMethodNotImplemented`; `detachFromEngine(for:)` → detach; `capabilities()` = `os`·`squeeze`/`roll`(17.5+)·`hover`(16.1+)·`prefersPencilOnlyDrawing`·선호 동작 둘), `PencilEventStream.swift`(`FlutterStreamHandler` + `UIPencilInteractionDelegate` + `UIGestureRecognizerDelegate` — `onListen` → attach, `onCancel` → detach + `eventSink = nil`; attach 대상 = `registrar?.viewController?.view` → 없으면 활성 `UIWindowScene.keyWindow`의 root view → 없으면 `UIWindow.didBecomeKeyNotification`을 기다림; 붙이는 것: `UIPencilInteraction`(delegate self), `UIHoverGestureRecognizer`(펜슬만·`cancelsTouchesInView = false`·delegate self), 17.5+ `PencilRollRecognizer`(delegate self); `shouldRecognizeSimultaneouslyWith` → `true`; 더블탭 17.5 미만(`pencilInteractionDidTap` — 위치 없음)·17.5+(`didReceiveTap` — `hoverPose`의 위치·`zOffset`), 스퀴즈 17.5+(단계 4개, 모르는 단계는 보내지 않음, `hoverPose`의 위치·`zOffset`·`rollAngle`), 호버 `.began`·`.changed`(16.1 `zOffset`·16.4 `altitudeAngle`·`azimuthAngle(in:)`·17.5 `rollAngle`, 16 ms보다 짧은 간격 버림)), `PencilRollRecognizer.swift`(17.5+ 수동 인식기 — `cancelsTouchesInView`·`delaysTouchesBegan`·`delaysTouchesEnded` 모두 false, 펜슬만, `touchesBegan/Moved`에서 `touch.rollAngle`을 16 ms 간격 이상으로, 끝·취소 때 `.failed` — 인식하지 않음), `PencilWire.swift`(Dart `PencilWire`의 Swift 사본 — 채널 이름 3개, `minInterval` 0.016 s, 종류마다 맵 빌더 하나(`tapEvent`·`squeezeEvent`·`hoverEvent`·`rollEvent` — 사전 리터럴 = `type`·`t`·필수 키, 선택 키는 값이 있을 때만 `event["k"] =`, 숫자는 모두 `Double`), `actionName`(17.5 블록 안 전체 `switch` + `@unknown default: "unknown"`, 그 아래는 16.0 `showInkAttributes` + 옛 4개)).
- `pencil_wire_contract_test` 다시 씀(R2-B1의 '빈 등록' 사례는 지움): ⓪⑥ 클래스 = `pluginClass`·`FlutterPlugin`을 채택한 파일은 하나·`register`에 UI 작업 없음, ① Swift 상수 = Dart 상수·채널·메서드가 그 상수를 씀·문자열은 한 번만, ②③ `"type"` 값 = `PencilWire.types`·빌더마다 리터럴 키 = `type`·`t`·필수, `event["k"]` = 선택(4.4.3 표 = `PencilWire.eventKeys`)·그 키로 만든 맵(필수만·전부)이 Dart `decode`에서 맞는 타입·빌더 4개가 모두 쓰임·`capabilities` 키 7개 = `fromWire`가 읽는 것, ④ 동작 이름 = `PencilWire.actions`·`case .x: return "x"`·17.5 `switch`가 7개 전부, 스퀴즈 단계 = `PencilWire.phases`, ⑤ 16.0~17.5 API 12개(`didReceiveTap`·`didReceiveSqueeze`·`hoverPose`·`rollAngle`·`preferredSqueezeAction`·`showContextualPalette`·`runSystemShortcut`·`PencilRollRecognizer`·`altitudeAngle`·`azimuthAngle`·`zOffset`·`showInkAttributes`)의 모든 사용이 그 판 이상의 `@available`/`#available` 안(중괄호 머리 판독 — `else`·`guard … else` 블록은 보장 없음, `if #available(…), 조건` 조건부도 인정) + 판독기 자체 11경우, ⑦⑧ `Package.swift`(`sources:`·`exclude:` 없음)·podspec이 Swift 파일 4개 전부·iOS 15.0 ≤ 앱 15.5(Podfile·pbxproj 3곳), ⑨ `onListen` → attach·`onCancel` → detach·`viewController`가 `keyWindow`보다 먼저·delegate self 3개·펜슬만·`return true`·detach가 셋 다 뗌·롤 인식기 수동(상태는 `.failed`만)·60 Hz.
- 시험이 잡는지 한 번씩 확인(되돌림): `rollAngle`을 가용성 블록 밖으로·동시 인식 `false`·선택 키 이름 바꿈·채널 이름 바꿈·`keyWindow` 먼저·동작 이름 틀림·롤 인식기 `.recognized` — 7가지 모두 실패.
- README(상태·파일 4개·시험 설명)와 `lib/src/wire.dart` 머리 주석(Swift 사본 경로) 갱신. Dart 코드 변경 없음.

| 검사 | 결과 |
|---|---|
| `pencil_bridge` `flutter analyze --fatal-infos` / `dart format` | 0건 / 변경 0 |
| `ws test --package pencil_bridge` (VM) | 57 통과 · 6.7초 |
| `ws native-reqs` | 23 플러그인 · 위반 0 · 경고 0 |
| `ws check` (R1–R16) | 0 |
| `dart test tool/test/native_reqs_test.dart tool/test/native_config_test.dart` | 89 통과 |
| Swift 컴파일 | 컨테이너에 Xcode 없음 — `ios-compile.yml`(U19, H6) |

#### J13 — Pencil 어댑터 마무리 · 앱 정보 Apple Pencil 줄 (계획 8.2, 6.12.3·6.18)

- 커밋: `f771299`, 이 기록 줄은 그 뒤 커밋.
- 능력 조회 500 ms 제한·실패 → 기록 1건 + `kPencilFallbackCapabilities`, 네 종류 `timestamp` 전달은 R2-B8b ③에서 끝났다(`6e7b753`, 위 '계획과 다르게 한 점' R2-B8b).
- `PencilStylusExtrasSource`(앱 내부)에 `os`(시작 때 능력의 `systemVersion`, 읽기 실패면 `'?'`)와 `seen`(`ValueListenable<({bool squeeze, bool roll})>` — 이번 실행에서 스퀴즈·롤을 받았는지, 어느 구독자의 `events`든 지나가면 켜지고 꺼지지 않음)을 더했다. `events`는 `late final` 한 번 만든 `map → where → cast`(브로드캐스트 그대로, `asBroadcastStream` 없음 — 기존 시험 그대로 통과).
- `AboutSection`: `stylusExtrasProvider.isSupported`이면 '빌드·렌더러·홈 화면 앱' 아래 'Apple Pencil' 줄 — 'iOS 17.5 · 더블탭 · 호버' + 받은 뒤에만 '· 스퀴즈(받음)'·'· 롤(받음)'(6.12.3 — 능력은 OS 가용성일 뿐), 능력 읽기 실패면 '능력을 읽지 못했어요 · 더블탭'. 섹션이 보이는 동안 스스로 `events`를 구독한다(라이브러리 → 설정처럼 에디터가 없을 때도 설정 화면에서 스퀴즈하면 줄이 바뀜 — 네이티브 쪽은 구독 수로 attach/detach). 문구는 `AppStrings.aboutPencil*`.
- 진단 정보 복사의 Pencil 줄은 넣지 않았다(진단 보고 v2는 J14).

| 검사 | 결과 |
|---|---|
| `app` `flutter analyze --fatal-infos` / `dart format` | 0건 / 변경 0 |
| `flutter test test/pencil test/settings/about_section_test.dart test/modules/feature_wiring_module_test.dart` | 19 · 17 · 25 통과 |
| `ws test --package noteapp` (VM) | 526 통과 · 1 건너뜀(V5) · 111초 |

#### J14 — 설정·앱 정보 v2 (계획 8.2, 6.18·4.6.7)

- 커밋: `9e10ac3`.
- **저장 공간**(`StorageSection` → `ConsumerStatefulWidget`, 공개 이름 그대로): '첨부 파일 n개 · x MB (녹음 a MB · 이미지 b MB · PDF c MB)' — `assetStoreProvider.usage()`의 `bytesByType`(없는 종류 0). 섹션이 보일 때 한 번, [다시 확인]으로 다시(1차 규칙). '검색 색인: 대기 n개 · 재구축 중'(`searchIndexProvider.status` 구독) + [다시 만들기](키 `app.storage.rebuildIndex`, 확인 창 '검색 색인을 처음부터 다시 만들어요. 시간이 걸릴 수 있어요.' → `rebuild()`(모든 원천), 이 섹션의 재구축 중이거나 상태가 `rebuilding`이면 비활성, 실패 → 문구 + 기록 1건(manual)).
- **앱 정보**: '기능' 줄(키 `app.about.features`) — `appFeatureStatesOf(compileTime, appFeaturesProvider, startupReport.steps)` → '녹음 켬 · 인식 꺼짐(개발자 메뉴) · 수식 엔진 꺼짐(빌드)'. 하나라도 꺼져 있으면 오류 색(11절 위험 9). Pencil 줄에 키 `app.about.pencil`(부록 C). 진단 정보 복사에 같은 줄.
- **`registerAppLicenses`**(`app/lib/src/app/licenses.dart`): `LicenseRegistry`에 지연 수집기 하나 — 'NoteSans (Noto Sans KR subset)' + `packages/ink_engine/assets/fonts/OFL.txt`. 에셋이 없으면 항목 없음 + 기록 1번(수집할 때마다 다시 시도). `runNoteApp`이 오류 처리기 설치 직후 부른다(6.4).
- **`DiagnosticReport` v2**: '시작' 다음 줄에 '기능: …'(모르면 '알 수 없음' — 시작 실패 화면). `skipped` 단계는 1차부터 시작 줄에 결과 이름으로 나왔다('media 0ms skipped') — 시험으로 못 박음.

| 검사 | 결과 |
|---|---|
| `app` `flutter analyze --fatal-infos` / `dart format --set-exit-if-changed lib test` | 0건 / 변경 0 |
| `flutter test` storage·about·diagnostic·licenses·feature_status | 21 · 23 · 6 · 6 · 8 통과 |
| `ws test --package noteapp` (VM) | 559 통과 · 1 건너뜀(V5) · 129초 |

#### J14b — 개발자 메뉴 `V1CopySection` · `BackupFile.mimeType` (계획 8.2, 6.18·4.6.7, 계약 7.2.7 · C22-01 CP-17)

- 커밋: `b0cefb5`.
- `app/lib/src/settings/v1_copy_section.dart`: `V1CopyApi`(기본값 = `package:note_core/dev_tools.dart`의 CP-17 함수 셋)·`V1CopySection`·`v1CopyMimeType` — 계획 4.6.7 시그니처·주석 그대로. 다섯 상태, 내보내기 두 단계(`BytesBuilder(copy: false)`로 조각 모음 → `BackupReadySheet` → 1차 `deliverBackup`, 결과 문구는 1차 백업과 같은 스낵바), 지우기(확인 창 → `delete` → 다시 조회). 키 `app.v1Copy.export`·`app.v1Copy.delete`(부록 C) + `app.v1Copy.cancel`·`app.v1Copy.progress`·`app.v1Copy.delete.confirm`·`.cancel`.
- `BackupFile.mimeType`을 필드로(기본 `application/json` — 1차 호출부 그대로). 시트의 `canShareFiles(mimeType:)`가 그 값을 쓴다.
- 설정 섹션 `app.v1Copy`('이전 판 DB 사본')를 `app.features`와 `app.about` 사이에(S2-9). 이 작업 트리의 CORE는 B2-α 선언(`v1DatabaseCopyInfo` → `null`)이라 실제 앱에서는 '사본 없음'이 보인다 — 실제 CP-17 함수 + 실제 CORE VM 파일 DB로 '사본 없음' 1회는 H2(T24 뒤).

| 검사 | 결과 |
|---|---|
| `app` `flutter analyze --fatal-infos` / `dart format --set-exit-if-changed lib test` | 0건 / 변경 0 |
| `ws check` (R1–R16) | 0 |
| `flutter test test/settings/` | 89 통과(v1 사본 19) |

#### J17 — `ws web-budget` · `tool/web_budget.yaml` · CI 단계 (계획 8.2, 4.2·4.3.3·6.15)

- 커밋: `95d88a8`.
- `tool/src/web_budget.dart`: `WebBudget.parse/load`(4.3.3 형식 — 모든 한도는 `null` 가능 = 표시만), `measureWebBuild`(`main.dart.js` 원본·gzip, `assets/FontManifest.json`의 패밀리마다 파일 합, `report_assets`), `webBudgetReport`(`check`면 한도 대조, `measure`면 모두 'report'), Markdown 표 + 끝줄 `ws web-budget check: N violation(s)`. `ws web-budget measure|check [--build-dir] [--budget]`, `GITHUB_STEP_SUMMARY`가 있으면 '### Web budget (check)' + 표를 덧붙임.
- `tool/web_budget.yaml`: 4.3.3 그대로(묶음별 `gzip_max: null` — 위 '변경 요청'의 총괄 결정 전까지 표시만).
- `ci.yml`: 'Finalize web build' 다음, 배포 앞에 'Web budget' 단계(`ws web-budget check --build-dir app/build/web`, 조건 없음 — 넘으면 배포 전에 멈춤). J15의 잡 분리 때 웹 빌드 잡으로 함께 옮긴다.
- 실제 빌드로 한 번(J0 때 남은 `app/build/web` = 기능 끈 빌드): `main.dart.js` 4,682,895 B · gzip 1,379,757 B(한도 1,666,038 — ok, 기준 대비 +13,719), 시작 글꼴 14 패밀리 22 파일 gzip 382,428 B(한도 400,000 — ok), KaTeX 371,014 B · 아이콘 11,414 B(표시만), 금지 글꼴 없음, 워크릿 11,762 B — J0 측정 표와 같은 값. 종료 0.

| 검사 | 결과 |
|---|---|
| `dart analyze --fatal-infos tool` / `dart format` | 0건 / 변경 0 |
| `dart test tool/test/web_budget_test.dart` | 16 통과 |
| `dart test tool/test/workflows_test.dart` | 73 통과 |
| `dart test tool/test` | 497 통과 · 155초 (처음 1회는 `workflows_test`의 `ws` 호출 수 20 → 21에서 실패 — 고침) |

#### J18 — 안내서 v2 (계획 8.2, 3.7·6.21, 계약 3.7·7.8)

- 커밋: `1e29a75`.
- `docs/guides/01`: 맨 위 굵은 단락 '2차 라운드에서는 Hosting만 써요 — Spark(무료) 요금제, 결제 계정 없음. 동기화·로그인·서버 함수(Blaze)는 나중의 실연결 단계에서 따로 켜요.' + 'Hosting(Spark)은 실연결이 아니에요', 순서 'Spark로 프로젝트 만들기 → Hosting 시작 → [02]'(약 15분), 1차 'M4 때 정할 것' 절 → '실연결 때 정할 것 (지금은 하지 않음)'(Firestore·Storage·Authentication·Functions). `03`: 'Functions 배포는 실연결 미니 라운드' 한 줄. `README`: 01 → 02 → 04 → 08, 07(05보다 먼저)·08 줄.
- `04`: 머리에 08 링크, '먼저 알아 둘 것'에 **웹 배포 되돌리기 금지**(옛 판은 DB v2 노트를 열지 못함), 새 절 '10단계 — 2차 판으로 옮기기 (08 B-1)'(① 배포 전에 백업 내보내기 — 출처는 `main` 뒤 live·그 전 개발 브랜치 미리보기, ② 2차 배포 — 개발 브랜치가 기본 브랜치라 DB v2 병합 푸시가 곧 배포 → Claude가 병합 전에 ① 요청, ③ 첫 실행, ④ **설정 → 이전 판 DB 사본** '사본 있음: …'), '녹음할 때'(Safari 마이크 허용 — 탭은 'aA', 홈 화면 앱은 iPad 설정(미확인), 탭 닫지 않기·'복구된 녹음', 자동 일시정지, 녹음 중 새로고침 문구 = `AppStrings.reloadBlockedByRecording`), 'B-15 하는 법'·'B-16 하는 법'. 1차 단락('live 주소에는 `main`에 올린 코드만 …')과 9.3 표 1~20은 그대로.
- `05`: 아티팩트 이름 표(`noteapp-apk-<번호>` 고정 키 판 / `noteapp-debug-signed-<번호>` '덮어 설치할 수 없는 시험판 — 실제 노트가 든 기기에는 설치하지 마세요'), '4단계 — 처음 쓸 때 허가하기'(마이크·알림, ML Kit 모델 Wi-Fi 약 20 MB — 미확인, 08 링크), '새 버전으로 바꿀 때' v2('고정 키 등록은 07을 보세요(키는 Claude가 파일 두 개로 건네요 — Claude는 GitHub 설정을 직접 바꿀 수 없어요)', 고정 키 판끼리 덮어 설치, 처음 한 번은 지우고 설치, **'앱이 설치되지 않음'이 뜨면 앱을 지우지 말고 알려 주세요**, 자동 백업에 노트 없음 → 백업 내보내기). 1차의 '설치 오류 → 지우고 설치' 문장과 문제 해결 줄은 '지우지 말고 알려 주세요'로 바꿈.
- `06`: '먼저 알아 둘 것'(웹 노트를 앱으로 옮기기는 아직 안 됨 — Q12, `ITSAppUsesNonExemptEncryption` false), 새 절 'iOS 컴파일 확인 (계정 없이)'(언제 — U19 승인 시 통합 뒤 1회 / 아니면 첫 TestFlight 전 필수, 10배, **confirm** `yes`·**ipa**, `ios-compile-<번호>` 7일), 5단계에 '처음이면 컴파일 확인 먼저', 문제 해결 2줄.
- `07`(새): 6.10.4 절차 — 파일 두 개(`noteapp-signing-secrets.txt`·`noteapp-sideload.p12`) → Secrets 4개(칸 이름 표)·Variables `ANDROID_CERT_SHA256` → 따로 보관 → Run workflow → 확인('서명: 고정 키 (…)'·`noteapp-apk-<번호>`), 'Claude는 이 저장소의 GitHub 설정을 직접 바꿀 수 없어요(권한이 없어요)', 문제 해결에 `android.yml`의 `::error::` 두 문장('고정 키 서명 재료가 없어요' — 시크릿 삭제·오타, '… ANDROID_CERT_SHA256와 달라요' — 시크릿이 바뀜)과 'debug 키' 요약 줄.
- `08`(새): 계약 7.8 A·B·C의 머리말(`> ` 인용 줄)과 항목 26개를 **글자 그대로** `- [ ] **A-1** …` 체크박스로, 항목마다 바로 아래 '하는 법'/'알려 줄 것'(예: A-5 개발자 표시 `녹음`(`media`) 섹션 사진), 'B-13 순서'(9단계 — 1차 V7 500쪽·색인 뒤 다시 열기 포함), C-1에 'iPadOS Apple Pencil 설정을 바꾼 뒤에는 **앱을 완전히 닫았다 열어요**(시작할 때 한 번 읽음)', '확인 방법' = 결과 보고 양식(기기·판·항목·결과·메모), 문제 해결.

| 검사 | 결과 |
|---|---|
| `dart test tool/test/guides_test.dart` | 30 통과 |
| `dart analyze --fatal-infos tool` / `dart format` | 0건 / 변경 0 |

#### J19 — 앱 스모크 v2 골격 · 기능 스위치 시험 (계획 8.2, 9.1 '앱 스모크 v2 단계', 계약 V5·V6·V15 v2.1)

- 커밋: `0b3c5d2`.
- `app/test/support/smoke_v2_fakes.dart`(새): `SmokeV2Fakes` — **가짜는 모듈 주입 인자로만**(9.1, 계약 7.3.3 '시험 이음새'): `MediaModule(initialize: 호출 수만 셈, mediaOverrides: FakeAudioRecorder(저장소를 provider에서 읽음)·FakeAudioPlayback)`, `RecognitionModule(overridesFor: FakeHandwritingRecognizer·FakeMathRecognizer·GeometricShapeFitter(), mathEndpoint: 'https://math.invalid/recognize')`, `FeatureWiringModule(imageImporter: 1×1 PNG 한 장을 앱 에셋 저장소에 넣는 가짜)`; 나머지(CoreModule·PdfModule·PDF 동작)는 실제. `modules(core, features:)` = `modulesFor`(꺼진 모듈은 만들지도 않음). `bootSmokeV2App`, `expectContractOverridesV2`(시작 단계·시작한 모듈 순서·override 출처 = 7.3.3 행 + 셸 행 + 패키지 목록, 각 한 번, 오디오 행은 `MediaModule.overrides()`에서만·인식 행은 `RecognitionModule.overrides()`에서만, 값 = 주입 가짜·실제 PDF), `featureRows`/`expectedFeatureRows`(V15 행 6개 — 녹음·인식 메뉴·수식 엔진·자동 도형 보정·이미지 삽입·이미지 페이지, provider 값 문자열), `differingRows`, `expectNoMissingPlugin`.
- `support/smoke_scenario.dart`: `bootSmokeApp`을 `bootSmokeAppWith(modules:, features:)` 위로 옮김(1차 V5·V6는 그대로 3모듈).
- `integration/app_smoke_v2_test.dart`(새, V5 v2): 9.1 표의 'J19' 단계 — 1 시작, 자리 4개(provider 값), 5모듈 위 1차 V5 흐름(새 노트 → 획 → 되돌리기/다시 → 닫기 → 다시 열기), 9 라우팅. 2~8·10(텍스트 상자·도형·이미지·올가미·녹음·재생·내보내기 개수)은 H3에서 이 파일에 더한다.
- `integration/feature_switch_test.dart`(새, V15): 기대 행 표가 '켠 구성과의 차이 = V15 문장'(녹음 / 인식 메뉴·수식 엔진·자동 도형 보정 / 수식 엔진, 이미지 두 행은 늘 같음)인지(순수 시험), 주입 8조합마다 시작·override 표·행 = 기대, 모두 끔에서 1차 V5 흐름, `AppFeatures.compileTime`(평소 모두 켬 — H5가 `--dart-define` 3개로 같은 파일을 돌림).
- `web/app_smoke_v2_browser_test.dart`(새, V6 v2): `setUpAll(useInkTestFonts)`(C23-07), 실행마다 따로인 웹 저장소(`noteapp_smoke2_<run>`), V5 v2와 같은 단계, 오류 기록 0·`MissingPluginException` 기록 0, 끝에 두 DB 삭제.

| 검사 | 결과 |
|---|---|
| `flutter test --run-skipped -t integration test/integration/app_smoke_v2_test.dart` | 1 통과(5초) |
| `flutter test --run-skipped -t integration test/integration/feature_switch_test.dart` | 11 통과(9초) |
| `ws with-heavy-lock -- ws test --package noteapp --platform chrome --run-skipped -t integration` | 2 통과(V6 v2·V6 1차, 130초) |
| `ws test --package noteapp --run-skipped -t integration`(VM) | 13 통과(V5 1차 1·V5 v2 1·V15 11, 54초) |
| `ws test --package noteapp`(VM) | 579 통과·3 건너뜀(integration 파일, 103초) |
| `ws check` | 0 |
| `flutter analyze --fatal-infos`(app) / `dart format` | 0건 / 변경 0 |

#### J20 — `ws lock-age` · `ci.yml` 'Lock age' 경고 단계 (계획 8.2, 4.2·6.1, Q8 — P-C)

- 커밋: `8e1f05a`.
- `tool/src/lock_age.dart`(새): `parseHostedPackages`(pubspec.lock의 `source: hosted`만 — 이름·판·`description.url`), `changedHostedPackages`(기준 대비 새로 생기거나 판·서버가 바뀐 것, 이름 순; 기준 lock 없음 → 전부), `publishedOf`(`<url>/api/packages/<이름>` 답의 `versions[].published`), `calendarDaysBetween`(UTC 날짜 차), `checkLockAge`(패키지마다 요청 1번 — 일수 < `--min-days`면 위반, 못 읽으면 경고), `LockAgeReport.format`(표 + `violation:`/`warning:` 줄 + 끝줄 `ws lock-age: N violation(s), M warning(s)`).
- `ws lock-age --since <git-ref> [--min-days 14] [--now YYYY-MM-DD]`(`cli.dart`): 기준 lock = `git show <ref>:pubspec.lock`(ref가 커밋이 아니면 경고 + 비교 없음, ref에 lock이 없으면 모든 hosted 항목이 새것), 내려받기는 `WsContext.download`(= `web-assets fetch`의 `httpDownload` — 환경 프록시 사용), `GITHUB_STEP_SUMMARY`가 있으면 '### Lock age (since <ref>)' + 표. 종료 코드 0(통과·경고만) / 1(위반) / 2(사용 오류) / 3(작업 폴더에 pubspec.lock 없음·`git show` 실패).
- `ci.yml`: 'Dependencies' 바로 다음 'Lock age' 단계 — `continue-on-error: true`(Q8 '경고 단계': 위반은 단계만 표시, 잡은 계속), 기준 `LOCK_BASE = AFFECTED_BASE`(영역 브랜치 = `origin/<기본 브랜치>`) 없으면 `BEFORE_SHA`(기본 브랜치의 이전 푸시), 기준이 없거나 0이면 건너뜀, `git diff --quiet <기준> -- pubspec.lock`이 같으면 건너뜀, 다르면 `ws lock-age --since "$LOCK_BASE"`.
- 실제 실행 한 번(컨테이너, 프록시 경유 pub.dev): `ws lock-age --since b6c9d0a`(1차 통합 HEAD — R2-B1 lock 변경 대비) → 새·바뀐 hosted 항목 48개 전부 14일 이상(가장 짧은 것 `image_picker_ios` 0.8.13+13 · `shared_preferences_android` 2.5.3 — 2026-10-22, 15일), `0 violation(s), 0 warning(s)`, 종료 0.

| 검사 | 결과 |
|---|---|
| `dart test tool/test/lock_age_test.dart` | 21 통과 |
| `dart test tool/test/workflows_test.dart` | 74 통과 |
| `dart analyze --fatal-infos tool` / `dart format` | 0건 / 변경 0 |
| `dart test tool/test` | 527 통과 · 89초 |

#### 변경 요청

- [총괄] J0 실측(계획 6.15 'J0 실측 결과')으로 시작 글꼴 묶음별 한도 제안 — KaTeX gzip 380,000 B · 아이콘 gzip 20,000 B(합계 400,000 B 유지). 대안: 합계 410,000 B + KaTeX 389,565 B(실측 + 5%). 결정되면 J17 `web_budget.yaml`에 넣는다.

#### 의존성 요청

- 없음

#### 계획과 다르게 한 점

- (J20) 계획 4.2는 `lock-age`의 종료 코드를 0 / 1로 적었다. 인자 오류(2)와 작업 폴더에 `pubspec.lock`이 없을 때(3)는 다른 `ws` 명령과 같은 코드를 쓴다. `--since`의 ref가 커밋이 아니면 실패가 아니라 경고(0)다 — '네트워크 오류는 경고'와 같은 취지(경고 단계에서 비교할 기준이 없으면 막지 않음). 14일은 게시 시각이 아니라 UTC 달력 날짜 차로 센다(`--now`가 날짜뿐이라).
- (J19) 자리 3·4(선택·삽입 메뉴)는 지금 '비어 있지 않음'이 아니라 '실제 `recognitionSelectionActions()`·`recognitionInsertActions()`의 id와 같음'으로 본다 — 이 작업 트리의 recog는 R2-B6 표면이라 두 목록이 비어 있다(9.1 표의 '자리 4개가 비어 있지 않음'은 자리 1·2만 지금 성립). LIBRARY 병합 뒤 H3에서 두 목록 `isNotEmpty`를 더한다. 녹음 패널 열기(단계 6)·삽입 메뉴 열기(단계 8)도 화면이 아니라 provider 값으로 봤다 — 이 작업 트리의 EDITOR는 마이크 버튼·삽입 메뉴가 없는 기반 표면이다(H3에서 화면으로).
- (J19) V15의 행 비교는 위젯이 아니라 provider 값(녹음 패널·녹음기 종류·개발자 섹션·유휴 작업 / recog 메뉴 id·`recog.settings`·색인기 / `RecognitionConfig.mathEndpoint`·수식 인식기 / `inkShapeFitterProvider` / `editorImageImporterProvider`·페이지 추가 출처)이다. '자동 도형 보정' 행은 provider 값(주입 `GeometricShapeFitter` ↔ 기본 `NoShapeFitter`)이라 지금도 차이에 든다 — 화면의 보정 토글 비교(C22-07: E2-15·L2-06이 모두 병합됐을 때만 기대 목록)는 H5.
- (J19) '주입' 방식은 `AppBootstrapper.features` + `modulesFor(features:)`(= `productionModules()`가 `--dart-define`으로 하는 일 — 꺼진 모듈은 없음)다. 개발자 메뉴로 끈 경우(`skipped`)는 `app_bootstrapper_test`·`app_module_context_test`가 본다.
- (J18) 08의 항목 문장은 계약 7.8 표의 '확인' 칸에서 개정 표시 `(v2.1) `과 굵게 표시 `**`만 뺀 글자 그대로다(`guides_test`도 같은 규칙으로 대조). 계약 문장은 한다체('설치한다.')라서 공통 형식의 해요체 검사는 08의 계약 문장 줄(`- [ ] **X-n** …`·`> …`)을 빼고 본다. 해요체 검사에 '했다.'를 더했다(기존 안내서에 없음).
- (J18) 04 B-1 ④는 계획 6.21의 '설정 → 개발자 → 이전 판 DB 사본'이 아니라 앱 그대로 **설정 → 이전 판 DB 사본**이다 — 설정 화면에 '개발자' 묶음이 없고 `app.v1Copy` 섹션이 바로 있다(J14b). 08은 계약 문장('개발자 메뉴에 v1 사본 있음')을 그대로 두고 '먼저 알아 둘 것'에서 '개발자 메뉴' = 설정 아래쪽의 개발자 표시·기능 켜고 끄기·이전 판 DB 사본 섹션이라고 푼다.
- (J18) 계획 6.21의 01 첫 문장 '… Hosting만 씁니다'는 공통 형식(해요체)에 맞춰 '써요'로 썼다.
- (R2-B8a) `AppModuleContext.recordOutcome`에 이름 있는 인자 `fallback:`을 더했다(계획 4.6.2는 '1차 그대로'). 실패·시간 초과 결과를 기록하는 순간 그 모듈의 기여를 지우고 대체 기여를 같은 자리에 넣어야 해서다 — 부트스트래퍼만 부른다.
- (R2-B8a) `appFeaturesProvider`·`shellContributionsProvider`는 `BootstrapApp`이 아니라 `AppBootstrapper`의 셸 override 묶음(`BootstrapSuccess.overrides` 앞부분)에 넣었다 — `BootstrapApp`은 그 목록을 그대로 쓰므로 결과는 같고, `overrides_unique_test`가 한 곳에서 본다. 셸 override는 6개 → 8개.
- (R2-B8a) J6 몫 일부를 당겨 했다: 30초 넘는 작업 기록 1줄, 정리 뒤 늦은 `onDispose` 등록은 바로 호출. J6에는 `BootstrapApp` 재시도 때 이전 실행기 정리가 새 scope 전에 끝나는 순서와 `bootstrap_app_test`가 남는다.
- (R2-B8a) J9 몫의 연결 함수(`recognition_wiring.dart`·`media_wiring.dart`·`search_wiring.dart`)는 모듈이 쓰므로 본문까지 만들었다. 전용 시험과 '같은 id 메뉴 항목' 규칙은 J9에서 끝냈다.
- (R2-B8a) `media.recoverDrafts`의 본문(`recoverPendingRecordings` — `startedAt` 오름차순, 실패 기록 후 다음)은 만들었고, `media.leaveGuard`는 빈 본문이다(`WebPlatform.setLeaveGuard`가 J7). 복구 시험(`FakeAudioRecorder.abandon()`)은 J7.
- (R2-B8a) 계획 시그니처에 없는 앱 내부 보조 이름: `ShellContribution.hasEditorItems`·`toString`, `AppModuleContext.featureReadTimeout`(500 ms), `MediaModule.lateStartWait`(10 s), `RecognitionModule.config`(시험용 읽기), `SearchIndexLines`·`formatSearchIndexStatus`(줄 형식 '대기 n · 재구축 중|대기 · 마지막 재구축 MM-dd HH:mm:ss|없음'). 앱 셸 내부라 계약 표면이 아니다.
- (R2-B8a) `MATH_ENDPOINT` 검사: `Uri.tryParse`가 되고 `http`/`https`이고 host가 있어야 쓴다. 아니면 null + 기록 1건(`details` = 원래 값).
- (R2-B8a) `idle_tasks_test`에서 Flutter 시험 바인딩의 `pump()`는 0초 타이머(`Timer.run` — 스케줄러 작업 루프)를 돌리지 않아 `pump(Duration.zero)`를 쓴다. 한 시험이 `scheduleTask`를 남긴 채 끝나면 바인딩의 작업 루프가 다음 시험에서 멈추므로(관찰함) 시험마다 끝까지 흘려보낸다.
- (R2-B8a) 1차 V5 스모크(`test/support/smoke_scenario.dart`)의 기대값을 셸 행 2개와 `search.index` 섹션만큼 고쳤다(V5 v2는 J19).
- (R2-B8a) J5의 `app_module_context_test`(설정 읽기 500 ms 초과·캐시 1회)는 아직 없다 — 기능 해석의 기본 사례는 `app_bootstrapper_test`의 2차 묶음에 있다.
- (R2-B8b) `FocusRectCodec`에 앱 내부 보조 `maxAbs`(100000)·`canEncode(rect)`를 더했다. `AppRoutes.note`는 `decode`가 다시 읽지 못할 focus(무한대·NaN·`l > r`·`t > b`·±100000 밖)를 주소에 넣지 않는다 — 만든 주소가 언제나 열리게. `encode`는 유한하지 않은 사각형에 `ArgumentError`.
- (R2-B8b) `FocusRectCodec.decode`의 수 형식은 `-?숫자(.숫자)?`만 받는다(지수·`+`·공백·`NaN`·`Infinity`·`.5`·`1.` 거절 — `encode`가 쓰지 않는 형식). 계획의 '유한한 수 4개'보다 좁다.
- (R2-B8b) `GoRouterAppNavigator.openNote`는 `pageId` 없는 `focusRectPt`를 assert 없이 버린다(`AppRoutes.note`의 assert는 직접 부를 때만 — 화면 콜백은 늘 page와 함께 부름).
- (R2-B8b) `PencilBridge.capabilities()`: 결과가 맵이 아니면 `PlatformException(code: 'invalid-result')`(계획에 없음 — 앱 어댑터가 다른 오류처럼 대체 능력으로 처리). `PencilCapabilities.fromWire`는 타입이 틀린 값도 '없음'으로 보고 기본값을 쓴다(`os` 기본 '').
- (R2-B8b) `PencilWire`에 `eventKeys`(종류별 필수·선택 키 표, 4.4.3)를 더했다 — `decode`가 쓰고 J12 와이어 대조 시험 ③이 Swift 키 집합과 비교한다(내부 상수, 진입점에 없음). `decode`는 선택 키도 타입이 틀리면 버린다(값이 null이면 없음으로 봄), `t`가 유한하지 않으면 버린다.
- (R2-B8b) `debugDroppedEvents`는 구독자마다 따로 센다(브로드캐스트 스트림의 `map`은 구독자마다 돈다 — 구독자 둘이면 나쁜 이벤트 하나가 2). 채널 오류는 처음 한 번만 `debugPrint`(`debugReset`이 되돌림).
- (R2-B8b, J13 몫을 당김) 능력 조회 500 ms 시간 제한·실패 처리(기록 1건 + `kPencilFallbackCapabilities`, override는 남음)를 `FeatureWiringModule.start`에 넣었다. 상수 `FeatureWiringModule.pencilCapabilitiesTimeout`(앱 내부). J13에는 앱 정보 Pencil 줄(스퀴즈·롤은 이벤트를 받은 뒤)과 Swift 쪽(J12) 뒤 마무리가 남는다.
- (R2-B8b) `overrides_unique_test`에 7번째 경우 'iPad(펜슬 지원)'를 더했다 — `stylusExtrasProvider`가 한 번만(`FakePencilPort` 주입).
- (J0) `native_config_test`의 9.1 묶음 중 `build.gradle.kts` 서명 분기는 J2, `native_requirements.yaml`이 모두 충족되는지는 J1(그 파일이 J1에서 생김), **앱 셸 두 경로 정적 묶음**(6.9)은 J4로 미뤘다 — 검사할 `app/lib/src/storage/native_storage_paths*.dart`·`defaultNoteStoreConfig` v2가 J4 코드라 지금 쓰면 실패하는 시험이 된다. J4 완료 조건에 'J0 정적 묶음'이 이미 있다.
- (J0) `appNativeConfigProblems`가 6.11.4 표의 `CFBundleDisplayName`도 본다(1차 값). Podfile은 `use_frameworks!`와 각 타깃 배포 대상 올림 줄까지 확인하고, 이 Flutter의 템플릿 파일(`$FLUTTER_ROOT/packages/flutter_tools/templates/cocoapods/Podfile-ios`)의 주석 아닌 줄이 커밋된 Podfile에 모두 있는지 본다(11절 위험 2 — Flutter 판 올림 때 깨져서 알려 줌; `flutter`가 PATH에 없으면 건너뜀).
- (J0) 기능 끈 빌드는 6.15 표의 두 스위치가 아니라 V15·H5와 같은 세 스위치(`FEATURE_MATH_ENGINE` 포함)로 쟀다.
- (문서) C23-01의 'INFRA(CI·functions.yml 고정값 확인)': `functions.yml`에는 판 문자열이 없다(`functions/package.json` devDependency를 `npm ci`로). 1차 고정값이 남아 있던 `ci.yml`·`web-experiment.yml` 배포 단계 `firebaseToolsVersion`을 15.34.1로 내렸다(계약 7.5 표 '(도구) firebase-tools 15.34.1 — CI').

- (J1) 픽스처(가짜 플러그인 7개 — pod만·SwiftPM만·둘 다(`darwin/`)·`.iOS(.v15)`(NR2 사례에서 `.v16`)·Gradle kts·groovy·Dart 전용 — 와 가짜 `.flutter-plugins-dependencies`)는 `tool/test/fixtures/native/`에 커밋하지 않고 시험마다 임시 폴더에 쓴다(`tool/test/support/fixture_workspace.dart`의 기존 방식 — 사례마다 파일 하나만 바꾸기 쉽다).
- (J1) NR7 = `nativeRequirementProblems`(요구 파일이 정한 것: 플러그인 요구·`app:`·`app_extra:`). 확정 문구·Podfile 줄 같은 J0 값은 `appNativeConfigProblems`가 맡고, `ws native-reqs`는 두 함수의 줄을 합쳐(같은 설정은 같은 문구라 한 줄) NR7로 보인다. CI 게이트는 `native_config_test`(두 함수 모두 + 요구 파일 ↔ `AppNativeExpectations` 값 대조).
- (J1) NR1에 반대 방향을 경고로 더했다: 요구 파일에 있지만 앱이 iOS·안드로이드로 해석하지 않는 이름(종료 0).
- (J1) 플러그인 iOS 최소 = podspec 값과 `Package.swift` 값 중 큰 것, 앱 값 = Xcode 프로젝트의 가장 낮은 `IPHONEOS_DEPLOYMENT_TARGET`(없으면 요구 파일 값). Gradle 값이 'flutter'를 담은 식이면(`flutter.compileSdkVersion`, `android_file_picker`의 `flutterCompileSdkVersion`) Flutter 기본값으로 보고 비교하지 않는다. `native_build: false`인 플러그인은 파일을 읽지 않고 표에 '(Dart only)'.
- (J1) 표의 열은 6.3 예시의 `spm`(yes/no) 대신 `ios(spm)`(그 `Package.swift`의 iOS 값, 없으면 `no`), 마지막 줄은 `ws native-reqs: N plugin(s), V violation(s), W warning(s)`(다른 `ws` 명령과 같은 꼴).

- (J2) `Signing` 단계를 Java·Flutter 준비보다 앞(Checkout 바로 뒤)에 두었다 — 재료가 없으면 몇 초 안에 실패한다. 계획 표의 단계 순서(빌드 → 서명 확인)와 결과는 같다.
- (J2) 훅 캐시 단계 이름은 `android.yml`만 'Build hooks (downloads sqlite3 when not cached)'로 바꿨다(6.10.3). `ci.yml`·`web-experiment.yml`은 'Cache build hooks' 그대로(경로·키는 세 곳 같음 — `workflows_test`가 본다).
- (J2) `guides_test`의 05 사례를 아티팩트 이름 식(두 갈래)에 맞췄다. 안내서 05에 `noteapp-debug-signed-<번호>`·'지우지 말고 알려 주세요'를 넣는 것과 `::error::`가 가리키는 `docs/guides/07-android-signing.md`를 만드는 것은 J18(안내서 v2) 몫이다.
- (J2) `key.properties`의 비밀번호는 글자·숫자만 쓴다고 정해(6.10.4 무작위 32자) Java properties 이스케이프를 하지 않는다(워크플로 주석).

- (J3) `ios-compile.yml`의 빌드 단계는 `cd app &&` 대신 `working-directory: app`(다른 워크플로와 같은 꼴 — `workflows_test`의 '모든 flutter build' 사례가 그대로 본다). 계획 표의 `cd app && flutter build ios …`와 결과는 같다.
- (J3) `ios-testflight.yml`의 수동 서명 시크릿은 잡 `env`가 아니라 그 단계 `env`에만 둔다(클라우드 서명 실행에는 들어가지 않게). 안내서 06의 J18 몫(`ios-compile.yml` 언제·어떻게, 웹 노트 옮기기)은 아직이다 — 이번에는 6.11.6이 정한 서명 방식만 넣었다.
- (J3) 수동 서명의 실제 동작(키체인·프로파일·export)은 검증 전 초안이다 — 시험은 단계 구조와 Archive 인자 두 갈래(가짜 `xcodebuild`)까지.

- (J4) 계획 6.9의 `native_storage_paths_test`는 `PathProviderPlatform.instance`를 바꾸지 않고 `plugins.flutter.io/path_provider` 채널을 시험 메신저로 흉내 낸다(앱은 `path_provider_platform_interface`에 의존하지 않음 — 계약 7.5). 플랫폼 인터페이스의 기본 구현이 이 채널이라 실제 함수 경로 그대로다.
- (J4) 앱 셸 정적 묶음은 `native_config.dart`가 아니라 새 `tool/src/app_shell_storage.dart`에 두고 `native_config_test`가 부른다(네이티브 설정 파일이 아닌 Dart 소스라서). 토큰 비교는 `package:analyzer` 없이 작은 토크나이저로 한다(시험 컴파일 시간).
- (J5) `FeatureSwitchSection`에 앱 내부 인자 `compileTime`(기본 `AppFeatures.compileTime` — 시험이 빌드에서 끈 경우를 만든다)과 상수 `flushTimeout`(2초)을 더했다(계획 시그니처는 `const FeatureSwitchSection({super.key})`).
- (J5) '다시 시작하면 적용돼요'는 '바꾼 뒤'가 아니라 **빌드 ∧ 메뉴 ≠ 이번 시작**일 때 보인다 — 화면을 나갔다 와도 남고, 시작 때 설정 읽기가 시간 초과였던 경우도 알려 준다. 되돌리면 사라진다.
- (J5) [다시 시작]은 `store.flush()`가 2초 안에 끝나지 않거나 실패하면 새로 고치지 않고 '저장이 아직 끝나지 않아 다시 시작하지 않았어요. 잠시 뒤 다시 눌러 주세요.' + 기록 1건(계획에 없음 — 쓰기 대기 중 새로 고침으로 잃는 것을 막으려고). 설정 쓰기 실패는 '설정을 저장하지 못했어요.' + 기록 1건(source manual). 수식 엔진 설명 '수식 인식 서버(인식이 켜져 있을 때). 수식 직접 입력은 꺼지지 않아요'는 계획에 문구가 없어 6.6 표('남는 것')에서 만들었다.
- (J5) 계획 6.6 시험 목록의 `app_module_context_test`는 새 파일 `app/test/bootstrap/app_module_context_test.dart`(1차에는 없었다).
- (J6) 계획의 '재시도 때 이전 실행기의 정리가 새 scope 전에 끝남': 지금 '다시 시도'·'데이터 지우기'는 시작 오류 화면에서만 열리고 그 화면에는 실행기가 없다(성공 화면에서 다시 시작하는 길이 없음). 그래서 순서 보장은 모든 `shutdown()` 앞의 `AppIdleCleanup.done`으로 넣고, 시험은 실제로 일어나는 두 경우 — 앱 끝(`BootstrapApp` dispose: 색인기 정리 → 모듈 stop)과 오류 화면 → 다시 시도 → 새 실행기 — 로 했다. M4 등에서 성공 화면에서 다시 시작하는 길이 생기면 그 경로도 `_shutdown`을 쓰면 된다(옛 scope가 한 프레임 뒤 unmount되므로 그 프레임을 먼저 기다릴 것).
- (J6) `AppIdleTaskRunner`에 선택 인자 `cleanup`(계획 4.6.2 시그니처에 없음 — 앱 내부)과 `AppIdleCleanup` 클래스를 더했다.
- (J4) `CoreModule`이 경로 함수 실패를 기록할 때 `AppErrorRecord.fromError(error, stackTrace, source: module)` 한 건 — 계획은 '오류 기록(source module)'까지만 정했다. 경로를 읽는 중 포기되면 `open`을 부르지 않는다(계획에 없음 — 늦은 저장소 닫기 규칙(INFRA-2-9)이 경로 단계에도 맞게).

- (J7) `media_module_test`의 녹음기 B는 CORE `FakeAudioRecorder`를 감싼 시험용 `_RecorderB`(인터페이스 위임)다 — 복구 호출 순서를 보고, `pendingDrafts()` 목록을 최신부터 주어 정렬을 확인하고(가짜 초안 저장소는 시작 순서대로 돌려줘 정렬이 안 보인다), 한 초안의 복구를 던지게 하려고. 초안 만들기·복구 자체는 `FakeAudioRecorder` 그대로. 저장소 시계는 `FakeAsync().getClock(…)` + `elapseBlocking`(앱은 `package:clock`에 의존하지 않는다 — 계약 7.5).
- (J7) 6.17 시험의 '앞에 30초짜리 복구 작업'은 25초로 했다 — 실행기가 30초를 넘긴 작업을 기록하므로(6.5.1 ④) '기록 0건'을 함께 보려고.
- (J7) `media.leaveGuard` 정리는 구독 취소를 기다리지 않는다(취소 즉시 이벤트가 멈춤). 시험 바인딩의 가짜 시간 안에서는 루트 zone의 취소 Future가 2초 제한 안에 끝나지 않아 정리 실패 기록이 생겼다(관찰함).
- (J7) 업데이트 배너의 녹음 중 안내는 배너 안 둘째 줄(오류 색)이다 — 계획은 문구만 정했다. 배너는 Navigator 위라 SnackBar·Overlay를 쓰지 않는다(1차 규칙).

- (J9) 반복 id의 디버그 assert는 기록과 버림을 마친 **뒤** `start()` 끝에서 실패한다 — 디버그 빌드에서는 `FeatureWiringModule` 시작이 실패해(비필수) 그 모듈의 override가 모두 빠진다(크게 보이게). 릴리스는 기록 + 뒤의 것 버림만. 시험은 `@visibleForTesting static bool debugAssertUniqueMenuIds`로 두 동작을 다 본다(계획에 없는 앱 내부 이름). 칸(선택·삽입)이 다르면 같은 id도 허용한다.
- (J9) `mediaRecordingPanel` 인자 시험을 `media_module_test`에서 `media_wiring_test`로 옮겼다(함수가 있는 파일 기준).

- (J12) 계획 4.4.4는 한 클래스(`PencilBridgePlugin`)가 `FlutterPlugin`·`FlutterStreamHandler`·`UIPencilInteractionDelegate`·`UIGestureRecognizerDelegate`를 모두 채택하는 요지다. 실제로는 플러그인 클래스(`FlutterPlugin`만)와 이벤트 쪽 클래스 `PencilEventStream`(`FlutterStreamHandler` + UIKit delegate 둘)으로 나눴다 — 캐시의 `file_picker_darwin` 2.4.2(`FilePickerPlugin` + `IOSFilePickerHandler`)와 같은 꼴로, UIKit delegate 채택이 메인 액터 격리를 추론하게 해도 `FlutterPlugin` 요구 사항과 섞이지 않게. 채널 상수와 맵 빌더는 `PencilWire.swift`(계획에 없는 파일 — 대조 시험이 한 곳을 읽게). ⓪ 시험의 '`FlutterPlugin`을 채택한 클래스는 하나'는 그대로다.
- (J12) 위치는 붙인 뷰(`registrar.viewController.view` = 이 엔진의 Flutter 뷰) 좌표 그대로 보낸다 — 계획 6.12.2 표의 '`view` 좌표 → 창 좌표' 변환은 하지 않았다. 4.4.3의 전제(Flutter 뷰가 창 전체를 덮음)에서는 같은 값이고, Flutter 전역 논리 px는 Flutter 뷰 기준이라 이쪽이 맞다(실기기 C-1에서 확인).
- (J12) 시각 `t`는 모든 종류에서 `ProcessInfo.processInfo.systemUptime`(롤만 `UITouch.timestamp` — 같은 기준), 17.5의 `Tap`·`Squeeze` 객체 시각은 쓰지 않았다(계획 표 그대로·컴파일 확인 전 API를 줄이려고). 모르는 스퀴즈 단계(`@unknown default`)는 보내지 않는다. `actionName`의 17.5 미만 길은 `showInkAttributes`를 `#available(iOS 16.0, *)`로 따로 본다(캐시의 `apple_pencil_double_tap` 2.0.0과 같은 판). 롤 인식기는 끝·취소 때 `state = .failed`를 직접 넣는다(계획 '상태를 바꾸지 않음 → 끝에 .failed'와 같은 결과를 명시). `detachFromEngine(for:)`에서 detach(계획에 없음 — 엔진이 먼저 사라질 때 인식기를 떼려고).
- (J12) 컴파일 위험(11절 위험 1): `UIPencilInteraction.Tap`·`.Squeeze`·`hoverPose`(`location`·`zOffset`·`rollAngle`)·`UIHoverGestureRecognizer`의 16.1~17.5 속성·`UIPencilPreferredAction` 7개 이름은 캐시의 공개 플러그인 두 개가 쓰는 이름과 SDK 기억으로 맞췄다 — 첫 `ios-compile.yml` 실행(U19)에서 확인해야 한다. 실패하면 앱 전체 iOS 빌드가 깨지므로 TestFlight 전에 반드시 한 번.

- (J13) `PencilStylusExtrasSource`에 앱 내부 `os`·`seen`을 더했다(계획 4.6.5 시그니처에 없음 — 앱 정보 줄이 OS 판과 '받음'을 알아야 해서). 새 최상위 이름은 없다(`seen`은 레코드 타입). 앱 정보 섹션이 보이는 동안 스스로 이벤트를 구독하는 것도 계획에 없다 — 에디터가 없는 설정 화면에서도 '받음'이 생기게.
- (J13) 계획 4.6.7의 줄 예시('iOS 17.5 · 스퀴즈 · 호버 · 롤')가 아니라 6.12.3(v2.1)의 규칙('스퀴즈·롤은 받은 뒤 · 스퀴즈(받음)')을 따랐고, 더블탭은 iOS면 언제나 붙는다(능력 표 그대로). 능력 읽기 실패(`os` '?')는 'iOS ?' 대신 '능력을 읽지 못했어요'.

- (J14) 계획에 없는 앱 내부 이름: `features/feature_status.dart`의 `AppFeatureState`(on·offInBuild·offInMenu·startFailed·offWithRecognition)·`appFeatureStatesOf`·`appFeatureStatusLine`·`mediaStepId`·`recognitionStepId`(시작 단계 id — 시험이 모듈 id와 같은지 본다), `licenses.dart`의 `noteSansLicenseAsset`·`noteSansLicenseName`, `AboutSection(compileTime:)`(J5 `FeatureSwitchSection`과 같은 시험 이음새), `DiagnosticReport.format(features:)`, `AppStrings.megabytes` 등 문구. 계약 표면이 아니다.
- (J14) 기능 줄의 상태는 계획 예시의 세 가지(켬·꺼짐(개발자 메뉴)·꺼짐(빌드))에 '시작 실패'(모듈 단계 `failedNonCritical`·`timedOut`·`failedCritical`)와 수식 엔진 전용 '꺼짐(인식 꺼짐)'(빌드·메뉴로는 켜져 있지만 인식이 꺼졌거나 실패 — `AppFeatures.isOn(mathEngine)`과 같은 규칙)을 더했다. `MATH_ENDPOINT`가 비어 수식 엔진 주소가 없는 경우는 따로 표시하지 않는다(스위치 상태만).
- (J14) 'x MB'는 1024 기준 소수 한 자리, 0은 '0 MB', 0이 아니지만 0.05 MB 미만은 '<0.1 MB'(0.0 MB로 보이지 않게). 1차 '사용량' 줄의 `AppStrings.bytes`('12.3MB')와 따로 둔 이유는 계획 문구가 'x MB'라서.
- (J14) `usage()` 실패는 '첨부 파일 정보를 읽지 못했어요'(오류 색)만 — 기록은 남기지 않는다(1차 '다시 확인' 실패 문구와 같은 취급). 다시 만들기 실패는 기록 1건(사용자가 누른 동작 — source manual).
- (J14) 라이선스 화면 시험: `LicensePage`를 `pumpAndSettle`로 기다린 첫 실행이 5분 넘게 끝나지 않아(CPU 0 % — 멈춤으로 보고 끊음) 100 ms씩 다섯 번 `pump`한다. `CachingAssetBundle`은 실패한 `loadString`도 캐시해서 '수집할 때마다 다시 시도'가 보이지 않으므로 시험의 가짜 번들은 `AssetBundle`을 바로 상속한다.

- (J14b) 계획 4.6.7에 없는 것: 확인 중 줄('확인하는 중…' — `info()`가 답하기 전), 모르는 `failure` 값은 'other' 문구, 사본 크기·진행 표시는 J14의 `AppStrings.megabytes`('12.3 MB'), 만든 시각은 지역 시각 `yyyy-MM-dd HH:mm`. 내보내기·지우기 실패 기록의 `details`는 'readV1DatabaseCopy failed'·'deleteV1DatabaseCopy failed'·'v1DatabaseCopyInfo failed'(1차 'prepareBackup failed'와 같은 꼴). 시트를 닫은 뒤 스낵바 문구는 1차 백업 것을 그대로 쓴다('백업 파일을 내려받았어요…').
- (J14b) 섹션 본문에 `ValueKey('app.v1Copy')`를 달았다가 설정 화면이 섹션 본문을 같은 키로 감싸서(1차 `SettingsScreen` — `ValueKey(entry.id)`) `settings_screen_test`가 '요소가 둘'로 실패했다 — 섹션 자신에는 키를 달지 않는다.

- (J17) 계획 4.2 표의 종료 코드는 0 / 1이다. 빌드 폴더·`main.dart.js`·`FontManifest.json`·예산 파일이 없거나 형식이 틀리면 다른 `ws` 명령과 같이 3(환경 오류)으로 했다. `FontManifest.json`에 있지만 빌드에 없는 글꼴 파일은 'missing' 줄(위반 아님), `measure`는 예산 파일이 없어도 잰다(묶음·보고 자산 없이). 원본 글꼴 한도(`startup_fonts_raw_max`)는 합계 줄 하나에 gzip 한도와 함께 보인다('400,000 · raw 700,000'). 도구 내부 이름(`ByteSize`·`FontBundle`·`WebBudgetRow`·`groupBytes` 등)은 계약 표면이 아니다. 'Web budget' 단계는 `ci.yml`에만 넣었다(`web-experiment.yml`은 실험 채널 — 계획이 정하지 않음).

#### 다른 영역이 기반 단계에서 보낸 요청 (인수인계 메모 [INFRA])

| 보낸 곳 | 내용 | 처리 |
|---|---|---|
| CORE | R2-B2i `CountingNoteStore` getter 4개 | 기반 단계에서 완료(`59ed567`) |
| INK 1 | `ink_engine/pubspec.yaml` `flutter: assets:` 블록 | 총괄이 넣음(C23-03) — INFRA 몫 없음 |
| INK 2·PDF 1·EDITOR 5 | `pdf_module_test` 배경 빌더 목록 | R2-final에서 완료(`708a1c1`) |
| INK 3 | Chrome 시험의 `useInkTestFonts()`, `InkMathRenderer.layout` WidgetsBinding | J19 `app_smoke_v2_browser_test` 등 앱 Chrome 시험 작성 때(C23-07) |
| EDITOR 1~4 | `StylusExtrasSource.capabilities`, 이벤트 `timestamp`, `editorImageImporterProvider` 기본 null·`EditorExtensions` 새 필드, `EditorScreen(initialFocusRectPt:)` | R2-B8a(③)·R2-B8b(①③)·J13 |
| PDF 2 | `pdfSearchIndexerProvider`를 읽으면 `core.noteStoreProvider` 필요, `PdfSearchIndexer` `start`·`dispose` 반복 안전 | J10(기본 리더 — 가짜 저장소 위에서 읽기·두 번 dispose 던지지 않음, R2-B4 표면)·H2(실제 색인기) |
| SYNC | `functions/` 생김 → `functions.yml` 단계가 돈다(`# tests 37`) | J16(첫 푸시가 실행 — H6) |

#### 이정표 커밋

- 체크포인트 병합 요청(INFRA-F3, Q14): R2-B8a·R2-B8b·J0 끝마다 결과 보고에 적는다.
- **R2-B8a 체크포인트**: `a4c9cca`(+ 이 기록 커밋) — 총괄에게 `main` 병합 요청(다른 영역의 시작 조건 아님, D24).
- **R2-B8b 체크포인트**: `6e7b753`(+ 기록 커밋 `20f831d`) — 총괄에게 `main` 병합 요청(D24).
- **J0 체크포인트(①②③)**: `1fd1aea`(+ 이 기록 커밋) — 총괄에게 `main` 병합 요청. 이 체크포인트의 첫 푸시 CI 실행 기록이 J0 ④(6.16 실측)의 입력이다.
- (2차 동시 개발 세션 3) J1 `3ff3b76`·J2 `0da5b71`·J3 `44609e8`(+ 기록 커밋) — 체크포인트 아님(INFRA-F3의 체크포인트는 R2-B8a·R2-B8b·J0). 다음 병합 때 함께 들어가면 된다.
- (2차 동시 개발 세션 4) J4 `3779a8f`·J5 `16b9c4b`·J6 `864317a`(+ 기록 커밋) — 체크포인트 아님. 세션 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, `dart format`(app·tool·pencil_bridge) 변경 0, `ws test --package noteapp` VM 473 통과·Chrome 11 통과, V5·V6 통과, `dart test tool/test` 481 통과(117초).
- (2차 동시 개발 세션 5) J7 `852cce5`·J8 `b0ffee5`·J9 `ea21681`·J10 `fcf949d`(+ 이 기록 커밋) — 체크포인트 아님. 세션 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, `dart format`(app) 변경 0, `ws test --package noteapp` VM 514 통과(65초)·Chrome 14 통과(110초), V5(`--run-skipped -t integration`) 1 통과. `tool`·`pencil_bridge`는 이번에 바뀌지 않아 돌리지 않았다.

- (2차 동시 개발 세션 6) J11 `fe6100d`·J12 `5b71ea3`·J13 `f771299`(+ 이 기록 커밋) — 체크포인트 아님. 세션 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, `dart format`(app·pencil_bridge) 변경 0, `ws test --package noteapp` VM 526 통과(111초)·Chrome 14 통과·1 건너뜀(111초), V5(`--run-skipped -t integration`, VM) 1 통과(53초), `ws test --package pencil_bridge` 57 통과, `ws native-reqs` 위반 0, `dart test tool/test/native_reqs_test.dart tool/test/native_config_test.dart` 89 통과(`tool`은 바뀌지 않음).

- (2차 동시 개발 세션 7) J14 `9e10ac3`·J14b `b0cefb5`·J17 `95d88a8`(+ 이 기록 커밋) — 체크포인트 아님. 세션 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, `dart format`(app·tool) 변경 0, `ws test --package noteapp` VM 579 통과·1 건너뜀(75초)·Chrome 14 통과·1 건너뜀(104초), V5(`--run-skipped -t integration`, VM) 1 통과(45초), `dart test tool/test` 497 통과(155초). `pencil_bridge`는 바뀌지 않아 돌리지 않았다.

- (2차 동시 개발 세션 8) J18 `1e29a75`·J19 `0b3c5d2`·J20 `8e1f05a`(+ 이 기록 커밋) — 체크포인트 아님. 세션 끝 확인: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, `dart format`(app·tool) 변경 0, `ws test --package noteapp` VM 579 통과·3 건너뜀(103초)·Chrome 14 통과·2 건너뜀(110초), `--run-skipped -t integration` VM 13 통과(54초)·Chrome 2 통과(130초, 잠금 안), `dart test tool/test` 527 통과(89초). `pencil_bridge`는 바뀌지 않아 돌리지 않았다.

#### 다음 세션 메모

- (2차 동시 개발 세션 3 끝) J1·J2·J3 끝. 다음: J4(네이티브 저장 경로 6.9 — `resolveNativeStoragePaths`·`CoreModule` 경로 publish·`defaultNoteStoreConfig` v2 + `native_config_test`의 앱 셸 두 경로 정적 묶음)·J5·J6.
- (2차 동시 개발 세션 4) J4·J5·J6 끝. 다음: J7(`MediaModule` 완성 — `media.leaveGuard`·`WebPlatform.setLeaveGuard`, 복구 시험(`FakeAudioRecorder.abandon()`), 업데이트 배너 보호 — 문구는 J5에서 만든 `AppStrings.reloadBlockedByRecording`)·J8·J9. 새 VM 시험에서 기본 `CoreModule`을 `start`하면 경로 함수가 던져 기록 1건이 생긴다 — 오류 기록을 세면 `nativePaths: noNativePaths`(`test/fakes/fake_native_paths.dart`).
- J4 주의(2차 동시 개발 세션 3에서 본 것): ① 앱은 `path_provider_platform_interface`에 의존하지 않는다(계약 7.5에 없음) — `native_storage_paths_test`는 `PathProviderPlatform.instance`를 바꾸지 말고 `MethodChannel('plugins.flutter.io/path_provider')`의 `getApplicationSupportDirectory`를 `TestDefaultBinaryMessengerBinding`으로 흉내 내면 된다(플랫폼 인터페이스 2.1.3의 기본 구현이 그 채널이고 `flutter test`는 Dart 플러그인 등록을 돌리지 않는다 — 처음 실행 때 확인). ② 기본 `nativePaths`로 `CoreModule(...)`을 만드는 VM 시험이 많다(`core_module_test`·`production_modules_test`·`bootstrap_app_test`·`overrides_unique_test`·`feature_wiring_module_test` 등) — VM에서는 기본 경로 함수가 `MissingPluginException`으로 실패해 오류 기록 1건이 생긴다. 오류 기록을 세는 시험은 `nativePaths: () async => null`을 넘기거나 채널을 흉내 낸다. ③ `app_smoke_test`(V5)는 `configFor`로 `inMemory`를 쓰므로 경로와 무관.
- (총괄·사용자) 고정 키(6.10.4, U20 ①)는 아직 없다 — 키를 만들어 파일 두 개로 건네는 일은 사용자와 함께(안내서 07은 J18). 그 전까지 `android.yml`은 `mode=debug`(`noteapp-debug-signed-<run>`)로 돈다. 시크릿 없이 변수만 넣으면 실패하는지(V14)는 H6.
- (2차 동시 개발 세션 5) J7·J8·J9·J10 끝. 다음: J11(검색 결과 → 위치로 열기 마무리 — `production_screens_test`의 새로고침·`%2C`·잘못된 focus 세 경우, 라이브러리 콜백·에디터 인자 — 자리표시 화면 사례는 R2-B8b `app_router_test`에 이미 있음)·J12(`pencil_bridge` Swift + 와이어 대조 시험 ①~⑨, 컴파일은 CI)·J13·J14·J14b. J8·J10은 코드가 R2-B8a에서 이미 완성돼 시험만 보탰다 — J11도 R2-B8b에서 상당 부분 끝났으니 먼저 남은 사례만 확인할 것.
- 위젯 시험에서 `setUp`(루트 zone)에서 만든 녹음기·스트림의 `cancel()` Future는 시험 바인딩의 가짜 시간 안에서 끝나지 않을 수 있다(J7에서 관찰) — 정리 콜백에서 그런 Future를 기다리지 말 것. 가짜 저장소·녹음기 조작은 `tester.runAsync` 안에서.
- 저장소 시계를 움직이는 VM 시험은 `FakeAsync().getClock(…)` + `elapseBlocking`(앱은 `package:clock` 의존 없음 — `media_module_test`의 `_Clocked`).
- J0 ④(CI 단계별 시간 실측 → 6.16·J15)는 총괄의 첫 체크포인트 푸시 뒤 실행 기록이 있어야 한다. 받으면 J0을 '완료'로 바꾼다.
- J11(검색 결과 → 위치로 열기)의 자리표시 화면 사례(새로고침·`%2C`·잘못된 focus)는 R2-B8b `app_router_test`에 이미 있다 — J11에는 `production_screens_test`의 같은 세 경우와 라이브러리 콜백·에디터 인자 마무리가 남는다.
- 남은 J6·J7·J9 몫은 위 '계획과 다르게 한 점'(R2-B8a)에, J13 몫은 (R2-B8b)에 적었다.
- (2차 동시 개발 세션 6) J11·J12·J13 끝. 다음: J14(설정·앱 정보 v2 6.18 — `storage_section` 종류별 용량(`AssetStore.usage().bytesByType`)·검색 색인 줄 + [다시 만들기](확인 창·진행 중 비활성), `about_section` 기능 상태 줄 4가지(모두 켬·빌드에서 끔·개발자 메뉴로 끔·시작 실패 — `appFeaturesProvider` + `startupReportProvider`), `registerAppLicenses`(NoteSans OFL — 가짜 에셋 번들 있음/없음, `licenses_test`), `DiagnosticReport` v2(기능 상태·`skipped` 단계 — 원하면 Pencil 줄도))·J14b(`V1CopySection` 다섯 상태 + `BackupFile.mimeType`)·J15. J14의 앱 정보 섹션에는 J13의 'Apple Pencil' 줄이 이미 있다(빌드·렌더러·홈 화면 앱 아래) — 기능 줄은 그 근처에.
- J12 Swift는 컴파일된 적이 없다(컨테이너에 Xcode 없음). 첫 `ios-compile.yml` 실행(U19·H6)에서 API 이름(`UIPencilInteraction.Tap`/`.Squeeze`·`hoverPose`·`UIHoverGestureRecognizer.zOffset`/`altitudeAngle`/`azimuthAngle(in:)`/`rollAngle`·`UIPencilPreferredAction` 7개·`showInkAttributes` 16.0)을 확인할 것 — 위 '계획과 다르게 한 점'(J12) 마지막 줄. 고칠 때는 `pencil_wire_contract_test`를 함께 맞춘다.
- 위젯 시험에서 스트림 이벤트로 바뀐 `ValueListenable`을 보려면 `pump()`를 두 번(첫 번째는 예약된 프레임이 없어 마이크로태스크만 비운다 — J13 `about_section_test`의 `deliver`).
- (2차 동시 개발 세션 7) J14·J14b·J17 끝. 남은 동시 개발 몫: J0 ④(첫 체크포인트 푸시의 CI 실행 기록 — 총괄), J15(`ws test --dart-define`·`ci.yml` 잡 분리 — **J0 ④ 실측이 선행**이라 잡별 시간 제한 값은 실측 뒤. `--dart-define`·`test_command_test` v2 부분과 잡 구조·시나리오 5개 시험은 실측 없이도 먼저 쓸 수 있음 — 제한 값만 비워 두고 진행 기록에 적을 것), J16(`functions.yml` 완성 — SYNC R2-B7b 골격·LIBRARY emulator 시험이 선행. 이 작업 트리의 `functions/` 상태를 먼저 볼 것), J18(안내서 v2 — J2·J3·J14b 끝나서 시작 가능: 01 Hosting만, 04 B-1·B-15·B-16, 05 '지우지 말고 알려 주세요'·'고정 키 등록은 07', 07 새 파일(`android.yml`의 `::error::`가 가리킴), 08 ↔ 계약 7.8 문장 대조), J19(앱 스모크 v2·`feature_switch_test` — J7~J9 끝, `useInkTestFonts` C23-07), J20(`ws lock-age`, P-C), J21(`android-emulator.yml`, P-C), J22(마감). 다음 순서 추천: J18 → J19 → J20 → J21 → J15(실측 없이 되는 부분) → J16 → J22.
- (2차 동시 개발 세션 8) J20 끝. J15에서 `ci.yml`을 잡으로 나눌 때 'Lock age' 단계는 `check` 잡(의존성 다음)으로 옮기고, `workflows_test`의 'lock age' 사례(`steps.indexOf(Dependencies) + 1`)를 그 잡 기준으로 고친다.
- (2차 동시 개발 세션 8) J19 끝. H3는 `app_smoke_v2_test.dart`에 9.1 표의 2~8·10 단계를 더하고(`SmokeV2Fakes.recorder`·`playback`·`picks`·`math`·`handwriting`이 그때 쓸 가짜), 자리 3·4 `isNotEmpty`를 더한다. H5는 `feature_switch_test.dart`를 `--dart-define FEATURE_MEDIA=false --dart-define FEATURE_RECOGNITION=false --dart-define FEATURE_MATH_ENGINE=false`로 돌린다(`ws test --dart-define`은 J15).
- (2차 동시 개발 세션 8) J18 끝. `guides_test`의 1차 사례 '02, 04: live는 `main`만'과 02 사례는 아직 `ci.yml`의 `jobs.values.single`에서 Channel 단계·`env`를 찾는다 — **J15 잡 분리 때 `web` 잡(배포 잡)에서 찾도록 같이 고칠 것**(계획 6.21 끝).
- J17의 묶음별 글꼴 한도(`tool/web_budget.yaml`의 `gzip_max: null` 두 개)는 위 '변경 요청'의 총괄 결정이 오면 넣고 `web_budget_test`의 '커밋된 파일' 사례를 같이 고친다. J15 잡 분리 때 'Web budget' 단계는 웹 빌드 잡의 'Finalize web build' 바로 다음에 둔다(`workflows_test`의 순서·명령·조건 사례가 본다).
- J14의 `StorageSection`은 이제 `ConsumerStatefulWidget`이고 `assetStoreProvider`·`searchIndexProvider`를 읽는다(시험은 두 provider를 가짜로 override). 실제 CORE `usage().bytesByType`·`rebuild()`는 H2에서.
- `LicensePage`를 `pumpAndSettle`로 기다리는 시험은 쓰지 말 것(J14 — 첫 실행이 5분 넘게 끝나지 않음). 100 ms씩 몇 번 `pump`.
- (2차 동시 개발 세션 8 끝) J18·J19·J20 끝. 남은 동시 개발 몫: J0 ④(첫 체크포인트 푸시의 CI 실행 기록 — 총괄), J21(`android-emulator.yml` + `app/integration_test/native_smoke_test.dart`, P-C — 6.10.5: 수동만·KVM 권한 단계·`reactivecircus/android-emulator-runner@v2`·`api-level: 34`·`google_apis`·`x86_64`·30분, 시험 = `workflows_test` 구조. `integration_test`는 R2-B1에서 lock에 있음. 액션 판은 계획 7.3 표에서 확인하고 없으면 의존성 요청), J15(`ws test --dart-define` + `ci.yml` 잡 분리 — 잡별 시간 제한 값만 J0 ④ 실측 뒤. 이때 `guides_test` 02·04 사례와 'Lock age'·'Web budget' 단계의 잡 위치를 같이 고침), J16(`functions.yml` 완성 — 이 작업 트리의 `functions/` 상태 먼저), J22(마감). 다음 순서 추천: J21 → J15(실측 없이 되는 부분) → J16 → J22.
