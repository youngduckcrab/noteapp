# INFRA 진행 기록

## 요약

- 마지막 세션: 1 / 8 (동시 개발 단계)
- 다음 할 일: I2 (`BuildInfo`·`RuntimeInfo`) → I3 (오류 처리) → I6 → I5 순서. 계획서 8.2 표의 선행 관계를 따른다.
- 기반 단계: B1(0bbebf8)·B8(2cec46a, eda674f) 완료. 계약 v1.4(C14-01·C14-02) 반영 확인.

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| B1 | 기반 단계에서 완료 | 0bbebf8 | 워크스페이스·패키지 골격·`ws` 최소(list·check R1–R3·R7–R9·R15·test·analyze)·`ci.yml` 최소 |
| B8 | 기반 단계에서 완료 | 2cec46a, eda674f | 최소 라우터·자리표시 화면 연결, R15 `tags:` 인식 수정(계약 v1.4 C14-02) |
| I1 | 완료 | ac34ca7 | `tool/test/rules_test.dart`(R1–R13), `test_tags_test.dart`(회귀), `test_command_test.dart`(`--affected-since` 포함), `affected_test.dart`, `channel_id_test.dart`, `build_info_file_test.dart`, `web_finalize_test.dart`, `web_assets_test.dart`, `dart_imports_test.dart`, `flutter_runner_test.dart`(회귀), `hosting_config_test.dart`(`--isolate` 변환만 — I12에서 `firebase.json` 검사 추가). 새 명령: `affected`, `channel-id`, `build-info`, `finalize-web`, `web-assets verify\|fetch`, `hosting-config`; `check --no-format`·`--no-exports`(R14는 G3) |
| I2 | 남음 | | `app/test/build/build_info_test.dart`, `runtime_info_test.dart` |
| I3 | 남음 | | `app/test/errors/app_error_log_test.dart`, `error_handlers_test.dart`, `diagnostic_report_test.dart`, `app_provider_observer_test.dart` |
| I4 | 완료 | (이 커밋) | `app/test/web/web_platform_browser_test.dart`(Chrome 8건: 절대 URL, 404·시간 초과 → null, `pagehide`·`visibilitychange` 대응·구독 해제, standalone false, 내려받기 true, 공유 불가면 `unsupported`). `app/test/fakes/fake_web_platform.dart`(5.7). VM 스텁 사용은 I2 `runtime_info_test`에서 |
| I5 | 남음 | | `app/test/bootstrap/app_bootstrapper_test.dart`, `overrides_unique_test.dart`, `bootstrap_app_test.dart`, `startup_error_screen_test.dart` |
| I6 | 남음 | | `app/test/routing/app_routes_test.dart`, `app_router_test.dart` (B8의 `AppRoutes`·임시 라우터를 교체) |
| I7 | 남음 | | `app/test/app/note_app_test.dart`, `lifecycle_bridge_test.dart` |
| I8 | 남음 | | `app/test/update/update_checker_test.dart`, `update_banner_test.dart` |
| I9 | 남음 | | `app/test/settings/settings_screen_test.dart`, `settings_sections_test.dart`, `storage_section_test.dart`, `about_section_test.dart`, `backup_export_test.dart` |
| I10 | 남음 | | `app/test/modules/core_module_test.dart`, `pdf_module_test.dart`, `production_modules_test.dart` |
| I10b | 남음 | | `app/test/modules/feature_wiring_module_test.dart`, `pdf_wiring_test.dart` |
| I11 | 남음 | | `tool/test/web_files_test.dart`, `ws check`(R13), `app/test/web/app_boot_browser_test.dart`, 빌드 결과 `flutter_bootstrap.js`에 `serviceWorkerSettings` 없음 |
| I12 | 남음 | | `tool/test/hosting_config_test.dart`, `web_assets_test.dart`, `ws check`(R12·R15), `ws web-assets verify`, 기본 `ws test`에서 integration 건너뜀 |
| I13 | 남음 | | `tool/test/workflows_test.dart` (6.13 표) |
| I14 | 남음 | | `tool/test/guides_test.dart` |
| I15 | 남음 | | 8.2 전체 + `ws check`·`ws analyze`·`ws test`·`ws test --platform chrome`·`flutter build web` |
| G1–G5 | 통합 단계 | | 계획서 8.3 (G3의 R14·`analyzer` 추가 포함) |

## 변경 요청

- 없음

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
- (세션 1) 계약 v1.3 C13-05 절차: 계획서 머리 상태 줄 '승인'·계약 인용 v1.4, 12.3 P6 결정 칸·8.1 B1 완료/B8-2 인용(INFRA-4-1), 13.4 '최종 승인' 한 줄(INFRA-4-2). 본문 개별 조항의 v1.1/v1.2 인용은 그 조항이 들어간 판이라 그대로 뒀다.

## 다음 세션 메모

- 환경: `export PATH=/opt/flutter/bin:$PATH CHROME_EXECUTABLE=/usr/local/bin/chrome-nosandbox`, `ws` = `dart run tool/ws.dart`.
- 다른 영역 구현은 이 작업 트리에서 기반 단계 자리표시다. CORE `createFakeNoteStore()`와 계획서 5.7의 가짜로 개발한다.
