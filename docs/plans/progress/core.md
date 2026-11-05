# CORE 진행 기록

## 요약

- 마지막 세션: 2 (동시 개발 단계)
- 다음 할 일: T9 (휴지통) — 그다음 T12·T13(순서 무관), T10

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| T0 | 기반 단계에서 완료 | 7bb1c59 | 패키지 골격(`build.yaml`·`dart_test.yaml`·`.gitignore`) |
| T1 | 기반 단계에서 완료 | 7bb1c59 | `test/common/*` |
| T2 | 기반 단계에서 완료 | 7bb1c59 | `test/model/pen_style_test.dart`·`stroke_points_test.dart`·`stroke_points_codec_test.dart`, `test/web/codec_browser_test.dart` |
| T3 | 기반 단계에서 완료 | 7bb1c59 | `test/model/entity_json_test.dart`, `test/goldens/json_golden_test.dart`, `test/sync/field_versions_test.dart` 등 |
| T4 | 기반 단계에서 완료 | 7bb1c59 | `test/api_surface_test.dart`, `test/repo/folder_tree_test.dart` 등 |
| T5 | 기반 단계에서 완료 | 7bb1c59 | `test/edit/*`, `test/session/note_session_contract_fake_test.dart`, `test/testing/fake_store_test.dart`, `test/dev/seed_synthetic_note_test.dart`, `test/providers/providers_fake_test.dart` |
| T6 | 완료 | d2a5cf9 | `test/storage/schema_test.dart`, `test/storage/open_errors_test.dart`, `test/testing/open_test_store_test.dart` |
| T7 | 완료 | 4a3cfaa (+ 다음 커밋: close 수정) | `test/storage/write_queue_test.dart`, `outbox_test.dart`, `change_bus_test.dart`, `field_version_writer_test.dart` |
| T8 | 완료 | (이 커밋) | `test/shared/library_contract.dart` → `test/repo/library_contract_fake_test.dart`·`library_contract_real_test.dart`, `test/repo/library_repository_test.dart` |
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
- T7: 한 커밋에 origin이 다른 작업이 섞이면 이어진 같은 origin 작업끼리 `ChangeBatch` 하나(같은 엔티티는 첫 위치·마지막 값). outbox 병합 때 `enqueuedAt`은 처음 값을 유지한다(계약에 규칙 없음). purge 항목에 upsert가 병합돼도 purge로 남는다(`WriteMerged`의 purge→upsert 전환은 T14에서 따로).
- T7: 저장소 `close()`는 쌓인 쓰기를 먼저 flush한 뒤 닫는다(재시도 중이면 끝날 때까지 기다림, 트랜잭션 여러 개여도 모두). 닫은 뒤 쓰기는 `StateError`.
- T8: 실제 저장소의 watch 스트림은 drift `.watch()`(닫을 때 `Timer.run`)를 쓰지 않고 `WatchHub`(`storage/watch_hub.dart`)로 직접 재질의한다. 트랜잭션마다 건드린 종류(`WriteTxn.touch`/`putLocal`/`putRemote`/`purge`, kv는 `touchKv`)를 모으고, 커밋 → `ChangeBatch` 발행 → 영향받는 watch 재질의·발행을 **기다린 뒤** 그 커밋의 쓰기 `Future`를 완료한다(가짜와 같은 순서 — 4.5 머리말 '같은 시점'). 타이머 없음 → fake_async에서도 돈다. 저장소를 닫으면 watch 스트림도 닫힌다(done).
- T8: 목록 정렬은 SQL이 아니라 Dart에서(가짜와 같은 비교 — UTF-16 코드 단위 순서, `name_norm` 열 사용). 최상위 목록의 고아 판정은 `NOT IN (활성 폴더 id 부분 질의)`.
- T8: `markOpened`는 `lastOpenedAt`만 쓰는 로컬 전용 쓰기(버전·outbox·`ChangeBatch` 항목 없음, watch는 재질의). 값이 같은 편집(같은 이름, 이미 대상에 있는 이동 등)은 쓰지 않는다. 바뀐 필드 = JSON 키 비교(`entity_diff.dart` `changedJsonKeys`) — 이동해도 sortKey가 같으면 `{folderId}`만.
- T8: `reorderItems`의 '부모가 섞임' `ArgumentError`는 현재 상태가 필요해 큐에 넣은 뒤 그 작업 안에서 판정한다(가짜와 같음, 아무것도 안 바뀜). 종류 섞임·앵커가 옮길 항목인 경우는 큐에 넣기 전.
- T8: `createNote`의 draft 페이지 id 중복(draft끼리)·형식 오류는 큐 전, 이미 있는 페이지 id와 겹침은 작업 안에서 `ArgumentError`.
- T8: `NoteContentReader`(`drift_content_reader.dart`)를 T10에 앞서 구현했다(복사 확인에 필요). T10 `content_reader_test.dart`는 T10에서.
- T8: 가짜 저장소 수정 2건 — `watchFolderTree`가 폴더가 같으면 다시 내지 않음(내부 `sameFolderTree`), `ChangeBatch`를 커밋마다 origin 연속 구간당 1개로 묶음(이전에는 쓰기 호출마다 1개 — "one per commit" 위반).
- T6: 실제 저장소의 아직 구현하지 않은 멤버(라이브러리·휴지통·프리셋·설정·내용·에셋·썸네일·`SyncStore`의 ID 두 개 밖·`openSession`·`exportBackupJson`)는 해당 작업 번호를 적은 `UnimplementedError`를 던진다(T7~T19에서 채움). `connect_browser.dart`(WasmDatabase)는 T6에서 썼고 브라우저 검증은 T16, BlobStore·해셔 연결은 T13.

- 기반 단계(B2) 차이는 `/home/user/wt/notes/foundation-core.md` '계획과 다르게 한 점'에 있다(값 타입 `==`·`copyWith` 추가, `pageChanges` 첫 load 전달 시점, 히스토리 별칭 보존, 가짜 저장소 세부 동작 등).

## 다음 세션 메모

- T7 쓰기 경로 사용법(T8 이후 모든 쓰기는 이것으로): `store.queue.run((tx) async { ... }, origin: ChangeOrigin.local, bytes: 점 바이트)`. 작업 안에서 `tx.putLocal(entity, 바뀐 JSON 키)`(HLC 찍기·필드 버전·행·outbox·`EntityChange`, `{*}` = 새로/전체, 로컬 전용·메타 키만이면 버전 유지·outbox 없음), `tx.putRemote(entity, versions)`(원격·복구 경로: 그대로 저장·outbox 없음·로컬 열 유지·고아 획 처리·HLC receive), `tx.purge(ref)`(행 삭제 + outbox purge), `tx.addChange`, `tx.afterCommit(f)`(커밋 뒤·ChangeBatch 전 메모리 갱신), `tx.noteIdOfPage`. 작업이 `Error`·`NoteCoreException`을 던지면 그 작업만 savepoint로 되돌리고 재시도 없이 그 오류로 완료, 그 밖의 예외는 트랜잭션 전체 롤백·재시도. 테스트 주입은 `store.queue.failNextCommits(n)`, 트랜잭션 수는 `debugTransactionCount`. 행 변환은 `row_mappers.dart`(`writeEntityRow`·`readVersionedRow`·`*Of(row)`), outbox 읽기는 `readOutbox`.
- fake_async 안에서 drift `NativeDatabase.memory()`가 타이머 없이 마이크로태스크만으로 돈다(write_queue_test에서 확인) → 재시도 간격 테스트를 실제 저장소로 쓸 수 있다.
- T6 산출물: `lib/src/storage/`(db/tables·note_database(+.g)·migrations, kv_keys, open_errors, connect/*, drift_note_store), `drift_schemas/note_db/drift_schema_v1.json`. 스키마를 바꾸면 패키지 디렉터리에서 `dart run build_runner build` → `dart run drift_dev make-migrations`(`--delete-conflicting-outputs`는 쓰지 않음). `schema_test`가 drift_schemas JSON과 실제 테이블·인덱스를 대조한다.
- T8 사용법(T9 이후): 라이브러리 쓰기는 `DriftLibraryRepository`(`storage/drift_library_repository.dart`). 활성 행·트리 도우미 `activeFolders()`, 복사 경로 `copyNote(tx, note, folderId:, sortKey:, title:)`(T14 `duplicateNoteForRecovery`가 재사용), 이름 검사 `checkLibraryName`, 접미사 자르기 `nameWithSuffix`. watch는 `store.watches.watch(affects:, query:, equals:)`.
- 세션 2: T8 완료. 라이브러리 C-8(복원 위치)은 T9에서 공유 계약에 넣는다. C-9의 세션 부분(획 편집 → `contentRevision`·`updatedAt`)은 T10 세션 계약(실제)에서.
- 세션 1 끝 상태: T6·T7 완료. 실제 저장소는 열기·쓰기 경로까지 동작하고, 저장소 멤버(라이브러리 등)는 아직 `UnimplementedError`. T8은 계획서 6.8(라이브러리·휴지통 규칙)·4.5(LibraryRepository 계약)·6.19(가짜와 같은 의미)를 읽고, 가짜 `lib/src/fake/fake_note_store.dart`의 `_FakeLibrary`를 동작 기준으로 삼아 `test/shared/library_contract.dart`를 두 저장소에 돌린다. watch 스트림은 커밋 뒤 재질의(가짜의 `watch()`처럼 구독 즉시 1회 + 바뀔 때) — `queue`의 커밋 알림에 붙이면 된다(`WriteTxn.afterCommit` 또는 `bus.stream`).
- 세션 1: 문서 절차(C13-05, CORE-4-1~4-3) 끝 — 02-core.md 상태 줄 '승인'·계약 v1.4, 4.6·4.7 v1.3 주석, 6.13 bullet, 12.2 CP-8 결정, 13.4. 코드 계약 파일은 B2에서 이미 v1.3 주석.
- Riverpod 3.4.3은 리스너 없는 provider를 멈춘다. 테스트에서 `container.listen(p.future, (_, _) {})` 뒤 `sub.read()`.
