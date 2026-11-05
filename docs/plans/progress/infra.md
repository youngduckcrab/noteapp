# INFRA 진행 기록

## 요약

- 마지막 세션: 1 / 8 (동시 개발 단계)
- 다음 할 일: I1 (`tool/ws.dart` 완성) → I2 → I4 → I3 순서. 계획서 8.2 표의 선행 관계를 따른다.
- 기반 단계: B1(0bbebf8)·B8(2cec46a, eda674f) 완료. 계약 v1.4(C14-01·C14-02) 반영 확인.

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| B1 | 기반 단계에서 완료 | 0bbebf8 | 워크스페이스·패키지 골격·`ws` 최소(list·check R1–R3·R7–R9·R15·test·analyze)·`ci.yml` 최소 |
| B8 | 기반 단계에서 완료 | 2cec46a, eda674f | 최소 라우터·자리표시 화면 연결, R15 `tags:` 인식 수정(계약 v1.4 C14-02) |
| I1 | 남음 | | `tool/test/rules_test.dart`, `test_tags_test.dart`(회귀), `test_command_test.dart`, `affected_test.dart`, `channel_id_test.dart`, `build_info_file_test.dart`, `web_finalize_test.dart`, `web_assets_test.dart`, `dart_imports_test.dart`, `flutter_runner_test.dart`. B1에서 된 것: R1–R3·R7–R9·R15, `test`의 `-t`·`-x`·`--run-skipped`·`--reporter`, flutter·Chrome 찾기, `analyze` |
| I2 | 남음 | | `app/test/build/build_info_test.dart`, `runtime_info_test.dart` |
| I3 | 남음 | | `app/test/errors/app_error_log_test.dart`, `error_handlers_test.dart`, `diagnostic_report_test.dart`, `app_provider_observer_test.dart` |
| I4 | 남음 | | `app/test/web/web_platform_browser_test.dart`(Chrome), VM `test/build/runtime_info_test.dart` |
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

- (세션 1) 계약 v1.3 C13-05 절차: 계획서 머리 상태 줄 '승인'·계약 인용 v1.4, 12.3 P6 결정 칸·8.1 B1 완료/B8-2 인용(INFRA-4-1), 13.4 '최종 승인' 한 줄(INFRA-4-2). 본문 개별 조항의 v1.1/v1.2 인용은 그 조항이 들어간 판이라 그대로 뒀다.

## 다음 세션 메모

- 환경: `export PATH=/opt/flutter/bin:$PATH CHROME_EXECUTABLE=/usr/local/bin/chrome-nosandbox`, `ws` = `dart run tool/ws.dart`.
- 다른 영역 구현은 이 작업 트리에서 기반 단계 자리표시다. CORE `createFakeNoteStore()`와 계획서 5.7의 가짜로 개발한다.
