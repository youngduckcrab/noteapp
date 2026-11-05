# CORE 진행 기록

## 요약

- 마지막 세션: 1 (동시 개발 단계)
- 다음 할 일: T7 (쓰기 경로 — `WriteQueue`·outbox·필드 버전·`ChangeBus`·HLC 영속)

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| T0 | 기반 단계에서 완료 | 7bb1c59 | 패키지 골격(`build.yaml`·`dart_test.yaml`·`.gitignore`) |
| T1 | 기반 단계에서 완료 | 7bb1c59 | `test/common/*` |
| T2 | 기반 단계에서 완료 | 7bb1c59 | `test/model/pen_style_test.dart`·`stroke_points_test.dart`·`stroke_points_codec_test.dart`, `test/web/codec_browser_test.dart` |
| T3 | 기반 단계에서 완료 | 7bb1c59 | `test/model/entity_json_test.dart`, `test/goldens/json_golden_test.dart`, `test/sync/field_versions_test.dart` 등 |
| T4 | 기반 단계에서 완료 | 7bb1c59 | `test/api_surface_test.dart`, `test/repo/folder_tree_test.dart` 등 |
| T5 | 기반 단계에서 완료 | 7bb1c59 | `test/edit/*`, `test/session/note_session_contract_fake_test.dart`, `test/testing/fake_store_test.dart`, `test/dev/seed_synthetic_note_test.dart`, `test/providers/providers_fake_test.dart` |
| T6 | 완료 | (이 커밋) | `test/storage/schema_test.dart`, `test/storage/open_errors_test.dart`, `test/testing/open_test_store_test.dart` |
| T7 | 남음 | | `test/storage/write_queue_test.dart`, `outbox_test.dart`, `change_bus_test.dart`, `field_version_writer_test.dart` |
| T8 | 남음 | | `test/shared/library_contract.dart` → fake·real, `test/repo/library_repository_test.dart` |
| T9 | 남음 | | `test/repo/trash_repository_test.dart` |
| T10 | 남음 | | `test/session/note_session_contract_real_test.dart`, `note_session_test.dart`, `content_reader_test.dart` |
| T11 | 남음 | | `test/edit/undo_remote_conflict_test.dart`, `undo_field_versions_test.dart` |
| T12 | 남음 | | `test/repo/pen_preset_repository_test.dart`, `settings_repository_test.dart` |
| T13 | 남음 | | `test/assets/blob_store_test.dart`, `asset_store_test.dart`, `thumbnail_cache_test.dart`, `test/web/blob_store_browser_test.dart`, `hasher_browser_test.dart` |
| T14 | 남음 | | 9.1 '동기화 창구 테스트' 전부 (`test/sync/*`) |
| T15 | 남음 | | `test/migration/note_migrator_test.dart` |
| T16 | 남음 | | `test/web/drift_web_persistence_test.dart`, `storage_info_browser_test.dart`, `delete_local_data_browser_test.dart`, `open_time_browser_test.dart`(perf) |
| T17 | 남음 | | `test/providers/providers_real_test.dart` |
| T18 | 남음 | | `test/perf/*`(perf 태그), README |
| T19 | 남음 | | `test/shared/backup_cases.dart` → `test/backup/backup_export_test.dart`, `test/testing/fake_backup_export_test.dart`, `test/web/backup_export_browser_test.dart` |

순서(계획서 8.2 병렬화 메모): T6 → T7 → (T8, T9, T12, T13) → T10 → T11 → T14. T15·T16은 T6 이후 언제든, T19는 T14 이후, T17·T18은 끝 무렵.

## 변경 요청

- 없음

## 의존성 요청

- 없음

## 계획과 다르게 한 점

- T6: DB 스키마 버전은 이미 공개 계약 상수인 `kDatabaseSchemaVersion`(`model/sync_entity.dart`)을 쓴다. `drift_dev make-migrations`는 `schemaVersion` getter가 정수 리터럴이나 **static 필드** 상수일 때만 읽으므로 `NoteDatabase.currentSchemaVersion = kDatabaseSchemaVersion`(static const)을 두고 getter가 그것을 돌려준다.
- T6: 스키마 단계는 `migrations.dart`의 `runSchemaUpgrade`가 한 트랜잭션에서 `Map<int, SchemaUpgradeStep>`(v1은 빈 맵)을 돈다(drift는 마이그레이션을 트랜잭션으로 감싸지 않는다). v2부터 `make-migrations` 생성 `stepByStep` 도우미를 이 맵의 단계 안에서 쓴다. 테스트는 `NoteDatabase(upgradeSteps:)`(@visibleForTesting) + `schemaVersion`을 올린 하위 클래스, `DriftNoteStore.open(databaseFactory:)`로 실패 단계를 주입한다.
- T6: 백그라운드 isolate(`NativeDatabase.createInBackground`)·웹 워커를 거친 마이그레이션 오류는 타입이 사라지고 문자열로 오므로, 열기 오류 분류는 `NewerSchemaError.prefix`·`SchemaStepError.prefix`·SQLite 손상 문구도 문자열로 맞춘다.
- T6: 같은 DB를 한 프로세스에서 두 번 여는 것은 막지 않는다(열린 수를 센다). `deleteLocalNoteData`는 그 DB가 하나라도 열려 있으면 `StateError`.
- T6: `openTestNoteStore`는 테스트 isolate의 `NativeDatabase`(백그라운드 아님)를 쓴다. `openNoteStore`(VM)는 `inMemory`면 `NativeDatabase.memory()`, 아니면 `nativeDatabasePath`의 `createInBackground`(WAL·`synchronous = NORMAL`), 경로도 `inMemory`도 없으면 `storageUnavailable`.
- T6: 실제 저장소의 아직 구현하지 않은 멤버(라이브러리·휴지통·프리셋·설정·내용·에셋·썸네일·`SyncStore`의 ID 두 개 밖·`openSession`·`exportBackupJson`)는 해당 작업 번호를 적은 `UnimplementedError`를 던진다(T7~T19에서 채움). `connect_browser.dart`(WasmDatabase)는 T6에서 썼고 브라우저 검증은 T16, BlobStore·해셔 연결은 T13.

- 기반 단계(B2) 차이는 `/home/user/wt/notes/foundation-core.md` '계획과 다르게 한 점'에 있다(값 타입 `==`·`copyWith` 추가, `pageChanges` 첫 load 전달 시점, 히스토리 별칭 보존, 가짜 저장소 세부 동작 등).

## 다음 세션 메모

- T6 산출물: `lib/src/storage/`(db/tables·note_database(+.g)·migrations, kv_keys, open_errors, connect/*, drift_note_store), `drift_schemas/note_db/drift_schema_v1.json`. 스키마를 바꾸면 패키지 디렉터리에서 `dart run build_runner build` → `dart run drift_dev make-migrations`(`--delete-conflicting-outputs`는 쓰지 않음). `schema_test`가 drift_schemas JSON과 실제 테이블·인덱스를 대조한다.
- 세션 1: 문서 절차(C13-05, CORE-4-1~4-3) 끝 — 02-core.md 상태 줄 '승인'·계약 v1.4, 4.6·4.7 v1.3 주석, 6.13 bullet, 12.2 CP-8 결정, 13.4. 코드 계약 파일은 B2에서 이미 v1.3 주석.
- Riverpod 3.4.3은 리스너 없는 provider를 멈춘다. 테스트에서 `container.listen(p.future, (_, _) {})` 뒤 `sub.read()`.
