# SYNC 진행 기록

## 요약

- 마지막 세션: 1 (동시 개발 단계 개발 세션 1/8)
- 다음 할 일: T1 나머지(`dart_test.yaml`, `display_mode.dart`, 4장 공개 시그니처 빈 구현, `test/web/firebase_compile_test.dart`) → T2 기초 타입 → T3 코덱
- 순서(계획서 8장): T1→T2→T3→T5→T7→T4→T6→T8→T9→T10→T11→T12→T13→T14→T15→T17→T16

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| T1 | 진행 중 (앞부분 B7은 기반 단계에서 완료) | 4d7a82f (B7) | B7: 진입점 4개 빈 틀 + `test/no_dart_io_test.dart`(+ `test/support/lib_boundary.dart`). 남은 것: `dart_test.yaml`, `display_mode.dart` 조건부 export, 4장 시그니처 빈 구현, `test/web/firebase_compile_test.dart` |
| T2 | 남음 | | `common/server_cursor_test.dart`, `common/varuint_test.dart`, `common/lru_set_test.dart`, `model/field_versions_ext_test.dart`, `model/field_units_test.dart`, `model/sync_doc_test.dart`, `model/records_test.dart`, `codec/canonical_json_test.dart` |
| T3 | 남음 | | `goldens/chunk_v1_golden_test.dart`, `codec/chunk_codec_test.dart`, `codec/chunk_packer_test.dart`, `test/web/pure_logic_browser_test.dart`(코덱 부분) |
| T4 | 남음 | | `merge/field_merge_test.dart`, `merge/field_merge_properties_test.dart`, `merge/sync_merge_policy_test.dart`, `merge/merge_recorder_test.dart`, `merge/record_gate_test.dart` |
| T5 | 남음 | | `testing/fake_sync_server_test.dart`, `testing/fake_blob_store_test.dart` |
| T6 | 남음 | | `contract/fake_local_store_contract_test.dart`(C-11·C-12 purge 대기 경우 포함 — SYNC-4-1), `testing/test_device_test.dart`, `testing/fake_local_store_test.dart`, `testing/sync_test_harness_test.dart` |
| T7 | 남음 | | `engine/push_scheduler_test.dart`, `engine/backoff_test.dart`, `engine/serial_executor_test.dart` |
| T8 | 남음 | | `engine/upload_pipeline_test.dart` |
| T9 | 남음 | | `engine/download_pipeline_test.dart` 외 |
| T10 | 남음 | | `engine/engine_state_test.dart`, `engine/auth_attach_test.dart`, `status/status_builder_test.dart`, `status/sync_badge_test.dart`, `status/value_equality_test.dart`, `engine/lifecycle_test.dart` 외 |
| T11 | 남음 | | `merge/folder_cycles_test.dart`, `merge/page_resurrection_test.dart`, `merge/purge_guard_test.dart`, `merge/purged_set_test.dart` |
| T12 | 남음 | | `assets/asset_sync_test.dart`, `assets/sync_remote_asset_fetcher_test.dart` |
| T13 | 남음 | | `scenarios/s01_*` ~ `s22_*`, `s08b_*`, `s14b_*`, `fuzz_convergence_test.dart` (태그 `scenario`) |
| T14 | 남음 | | `providers_test.dart`, `auth/auth_service_test.dart`, `api_surface_test.dart` |
| T15 | 남음 | | `compaction/compactor_test.dart` |
| T16 | 남음 (어댑터 코드는 동시 개발, 실행·판정은 통합 단계) | | `CoreSyncLocalStore` 코드 + `integration/core_sync_store_contract_test.dart`, `integration/core_scenarios_test.dart`, `integration/core_json_keys_test.dart`, `integration/core_folder_cycles_test.dart`(태그 `integration`, 기본 skip) |
| T17 | 남음 | | `firebase/firestore_chunk_mapper_test.dart`, `firebase/firebase_sync_backend_test.dart`, `firebase/firebase_auth_backend_test.dart`, `firebase/firebase_error_mapper_test.dart`, `firebase/rules_ownership_test.dart`, `test/web/firebase_compile_test.dart` 확장 |
| 문서 | 완료 | (이 세션) | C13-05·SYNC-4-1~4-3: 계획서 상태 줄 '승인', 계약 인용 v1.4, 5.1.1 블록 = 계약 7.2.10 원문, C-11·C-12 purge 대기 경우, 12.2 결정 칸, 13.4 |

## 변경 요청

- 없음

## 의존성 요청

- 없음

## 계획과 다르게 한 점

- (B7) `test/support/lib_boundary.dart`를 테스트 도우미 위치로 추가(계획 3장 트리에 없는 경로). B1의 `test/sync_engine_smoke_test.dart` 삭제.

## 다음 세션 메모

- 다른 영역은 이 작업 트리에서 기반 단계 상태다. CORE는 `createFakeNoteStore()`(SyncStore 대부분 `UnsupportedError`)와 실제 값 타입(B2)만 쓸 수 있다.
