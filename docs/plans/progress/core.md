# CORE 진행 기록

## 요약

- 2차 마지막 세션: **R2-B2b(B2-β) 완료 — T20a `9777fde`('B2-β JSON 골든' 이정표) → T20b `c443015` → T21 `38f3578` → T23a `12ab8c4` → T23b `0798096`('B2-β 끝' 이정표)**(아래 '## 2차' > 'B2-β'). 가짜 저장소 v2(객체·녹음·초안·손글씨·메모리 색인)·`PageObjectFixtures`·`FakeAudioRecorder`·`FakeAudioPlayback`·`testing_web.dart`가 동작한다. 실제 저장소는 8.1 'B2 상태' 'β 끝' 열(객체 명령 T27, 새 저장소 쓰기 T30~T33a, DB v1). 그 앞은 T22(B2-α) `2b2e4b0`, T25a `b6beece`.
- 2차 다음 할 일: 총괄이 R2-B2(α + β) + SYNC R2-B7a + INFRA R2-B2i 묶음을 `main`에 병합하고 묶음 검사(7.6.2 예외) → R2-B3(INK) … → 동시 개발(T24 DB v2·마이그레이션 먼저 — 8.2).
- 1차 마지막 세션: **통합 단계(7개 영역 병합 뒤)** — SYNC 통합 담당의 변경 요청 2건 처리(아래 '## 통합 단계' > '7개 영역 병합 뒤 — SYNC 변경 요청'): `openTestNoteStore`의 drift 다중 DB 경고 끔, 파일 DB 롤백 저널을 문서·테스트로 고정. 커밋 실패 공개 훅은 계약 7.6 변경이라 **총괄 결정 대기**. 그 앞은 1차 통합(CORE → INK → EDITOR·LIBRARY) 확인, 동시 개발 마지막은 세션 5
- 다음 할 일: 총괄이 7.6 커밋 실패 훅(SYNC 요청 1)을 채택하면 CORE가 구현(아래 제안). iPad 확인(계획서 9.2·10절 #9). 10절 #7(SYNC T16을 막는 CORE 결함 없음)은 통합 태그 전체 통과로 확인(SYNC 42개)

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
| T8 | 완료 | 6d0c569 | `test/shared/library_contract.dart` → `test/repo/library_contract_fake_test.dart`·`library_contract_real_test.dart`, `test/repo/library_repository_test.dart` |
| T9 | 완료 | 6bb6c01 | `test/repo/trash_repository_test.dart`, 공유 계약 `test/shared/library_contract.dart` 'C-8 / trash'(가짜·실제). 열린 세션 읽기 전용 전환·복원 시 해제는 세션 DB 백엔드가 있어야 해 T10 테스트로 |
| T10 | 완료 | aaa6285 | `test/session/note_session_contract_real_test.dart`(공유 본문 + N-7), `note_session_test.dart`, `content_reader_test.dart`, `test/repo/trash_repository_test.dart` '열린 세션 읽기 전용 전환·복원 시 해제'(T9 남은 몫) |
| T11 | 완료 | 7fa9c6d | `test/edit/undo_remote_conflict_test.dart`, `undo_field_versions_test.dart`(필드 버전·outbox 필드, 100단계 undo 후 초기 상태, 별칭 정리) |
| T12 | 완료 | 3503f6c | `test/repo/pen_preset_repository_test.dart`, `settings_repository_test.dart`, 공유 본문 `test/shared/preset_contract.dart`(프리셋·설정) → 가짜 `test/repo/preset_contract_fake_test.dart` |
| T13 | 완료 | ac1965c | `test/assets/blob_store_test.dart`, `asset_store_test.dart`, `thumbnail_cache_test.dart`, `test/web/blob_store_browser_test.dart`, `hasher_browser_test.dart` |
| T14 | 완료 | 4f43deb | `test/sync/sync_store_test.dart`(outbox·readVersioned·세 결정·기기 로컬 필드·pendingLocalFields·origin·세션 N-7/영구 삭제·쓰기 Future 규칙), `field_lww_convergence_test.dart`, `version_invariant_test.dart`(500단계), `commit_repairs_test.dart`, `meta_kv_test.dart`, `reassign_owner_test.dart`, `duplicate_for_recovery_test.dart`, 도우미 `test/sync/support/sync_support.dart` |
| T15 | 완료 | 8f001f9 | `test/migration/note_migrator_test.dart`(v0→v1 1회·outbox 바뀐 필드, 실패 시 롤백·재시도 없음, 단계 없음 `StateError`, `openSession` 이주 후 열기·실패 시 읽기 전용, 새 버전 노트 `ReadOnlyNoteException`·이주 안 함) |
| T16 | 완료 | e430894 | `test/web/drift_web_persistence_test.dart`(쓰기→닫기→같은 이름 다시 열기: 백업 바이트·outbox·획 점·에셋 바이트·설정 동일, `deviceNodeId`·HLC 이어짐, backend 보고), `storage_info_browser_test.dart`(persist 요청·estimate 채움, 응답 없는 persist 상한, `refreshStorageInfo`), `delete_local_data_browser_test.dart`(삭제 후 빈 DB·새 노드, 열린 동안 `StateError`, 막히면 `TimeoutException`), `open_time_browser_test.dart`(perf), VM `test/storage/storage_query_test.dart`(fake_async: 1 s 상한·늦은 응답은 refresh가 읽음), `backup_export_browser_test.dart`에 실제 웹 저장소 그룹 추가 |
| T17 | 완료 | 13b5be9 | 공유 본문 `test/shared/providers_contract.dart`(T5 본문을 옮김) → 가짜 `test/providers/providers_fake_test.dart`·실제 `test/providers/providers_real_test.dart`(+ `refreshStorageInfo` 뒤 invalidate 전 옛 값·뒤 새 값, 원격 획 `applyRemote` → `pageContentProvider` 갱신·히스토리 불변, 쓰기 없는 새 메모리 저장소의 `persistenceStatusProvider` 첫 값) |
| T18 | 완료 | 3b97101 | `test/perf/`(`perf` 태그·`@TestOn('vm')`): `large_note_perf_test.dart`(10만 획 시드 기록·`openSession` < 200 ms), `page_perf_test.dart`(2,000획 `openPage` < 300 ms, 5,000획 페이지 `execute` 평균 < 2 ms), `commit_latency_perf_test.dart`(파일 DB 1획 커밋 중앙값 < 30 ms), `codec_perf_test.dart`(점 100만 개 < 300 ms), `listing_perf_test.dart`(폴더 200 + 노트 1,000 첫 값 < 100 ms), 도우미 `perf_support.dart`. README 사용 예 + `test/readme_examples_test.dart`(README 예제를 가짜·실제 저장소로 실행) |
| T19 | 완료 | 2c2b1e2 | 공유 본문 `test/shared/backup_cases.dart` → 실제 `test/backup/backup_export_test.dart`, 가짜 `test/testing/fake_backup_export_test.dart`(같은 골든 바이트 `test/goldens/backup/backup_v1.json`, `golden` 태그), 브라우저 `test/web/backup_export_browser_test.dart`(가짜 저장소로 웹 생성·파싱) |

순서(계획서 8.2 병렬화 메모): T6 → T7 → (T8, T9, T12, T13) → T10 → T11 → T14. T15·T16은 T6 이후 언제든, T19는 T14 이후, T17·T18은 끝 무렵.

## 변경 요청

- 총괄 결정 대기(계약 7.6 B2 도우미): `openTestNoteStore` 커밋 실패 주입 공개 훅 — SYNC 통합 담당 요청. CORE 의견과 두 안은 '## 통합 단계' > '7개 영역 병합 뒤 — SYNC 변경 요청'

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
- T9: 영구 삭제 때 그 노트들의 페이지·획·녹음 outbox 대기 항목은 지운다(대표·폴더·노트마다 purge 1건만 남김 — "페이지·획은 생략"의 해석, 행이 없는 upsert를 SYNC가 읽지 않게). `ChangeBatch`에는 폴더·노트 purge만(가짜와 같음).
- T9: 자동 정리 타이머(10초 뒤 1회, 이후 6시간마다)는 `openNoteStore`만 켠다(`DriftNoteStore.open(autoPurge: true)`). `openTestNoteStore`는 타이머를 만들지 않는다(다른 영역 위젯 테스트의 '타이머 남음' 방지). `close()`가 멈춘다. 보관 기간은 `NoteStoreConfig.trashRetention`.
- T9: 다른 소유자 행은 휴지통 목록·purge·emptyTrash에서 보이지 않고, `restore`는 `EntityNotFoundException`. 복원 부모 사슬에 순환이 있으면 최상위.
- T12: `seedDefaultPenPresets: true`(기본값)면 `DriftNoteStore.open`이 돌려주기 전에 `ensureDefaults()`를 한 커밋으로 실행한다(가짜처럼 열자마자 `getPresets()`에 5종). 그래서 `openTestNoteStore()` 기본값으로 연 저장소의 outbox에는 기본 프리셋 5건(`*`, 시드 HLC)이 있다 — outbox 수를 세는 다른 영역 테스트는 `seedDefaultPenPresets: false`를 넘긴다. 기본 프리셋 쓰기는 `putLocal(fixedVersion: Hlc(1, 0, '0'×16))`(outbox 항목의 hlc도 시드 값).
- T12: 설정 읽기는 키의 scope대로(synced → `settings` 행, device → `kv['setting.<name>']`). 가짜는 이름으로 device 값을 먼저 보지만 같은 이름을 두 scope로 쓰지 않는 한 결과가 같다. 저장된 JSON이 깨졌으면 기본값. 다시 `set`하면 소프트 삭제가 풀린다(바뀐 필드 `deletedAt`·`valueJson` 중 실제로 다른 것).
- T6: 실제 저장소의 아직 구현하지 않은 멤버(라이브러리·휴지통·프리셋·설정·내용·에셋·썸네일·`SyncStore`의 ID 두 개 밖·`openSession`·`exportBackupJson`)는 해당 작업 번호를 적은 `UnimplementedError`를 던진다(T7~T19에서 채움). `connect_browser.dart`(WasmDatabase)는 T6에서 썼고 브라우저 검증은 T16, BlobStore·해셔 연결은 T13.

- T13: 내부 인터페이스를 둘로 나눴다 — `BlobStore`(바이트 값, `asset_chunks`)와 `ThumbnailStore`(`thumbnails`, 값 `{rev, w, h, mime, bytes}`). 둘 다 `IdbBlobDatabase`(`assets/idb_blob_store.dart`)가 idb_shim으로 구현. IndexedDB는 **처음 쓸 때** 연다(저장소 열기를 막지 않음, 실패하면 다음 작업이 다시 시도). 다른 연결의 versionchange(다른 탭의 삭제)면 닫고 다음 사용 때 다시 연다.
- T13: IDB 팩토리는 `connect_*.dart`의 `blobIdbFactory(config)` — 웹 `idbFactoryBrowser`(`inMemory`면 메모리), VM은 메모리 DB 저장소마다 새 `newIdbFactoryMemory()`, 파일 DB는 경로별 프로세스 전역 메모리 팩토리(같은 파일을 다시 열면 바이트·썸네일이 남음, `deleteLocalNoteData`가 지움 — 네이티브 파일 바이트 저장은 이후 범위 1.3). `openTestNoteStore`·`openNoteStore` 둘 다 이것을 넘긴다. `DriftNoteStore.open(blobFactory:, assetChunks:)` — `assetChunks`는 테스트용 청크 저장소 주입(@visibleForTesting). 웹 `deleteLocalData`는 블롭 DB도 지운다(브라우저 확인은 T16).
- T13: '바이트가 있음' = 행의 `hasLocalBytes` **그리고** `chunk_count`개 청크 키가 모두 있음(`put` 중복 제거 판정과 `hasBytes`). `readBytes`는 청크가 하나라도 없거나 길이가 `size`와 다르면 `null`. 빈 바이트는 청크 0개.
- T13: 메타만 있던 행(원격)에 `put`하면 그 행의 메타(fileName 등)는 그대로, 로컬 열(`hasLocalBytes`·`chunk_count`)만 쓴다(outbox 없음). `putDownloadedBytes`는 행이 없어도 쓰기 큐를 거친다(앞에 쌓인 원격 메타 쓰기가 먼저 커밋되게) — 행이 없으면 청크만 남고 `bytesArrived`는 낸다. 나중에 원격 메타가 새 행으로 오면 T14가 `AssetStoreImpl.localStateOf(id, size)`(모든 청크 키 확인 → `hasLocalBytes`·`chunkCount`)로 로컬 열을 정한다.
- T13: `markUploaded`는 값이 같아도 항상 outbox `{storagePath}`·`ChangeBatch(local)`(가짜와 같음). `usage()`의 `assetCount`는 삭제 안 된 행 전부(소유자 무관, 가짜와 같음), `totalBytes`는 그중 `hasLocalBytes`인 것의 `size` 합. `listAssets`는 소유자·삭제 안 됨 필터, 정렬 `createdAt`·`id`.
- T13: `put`은 입력 바이트 전체를 복사하지 않는다(300 MB PDF 메모리). 청크는 복사해서 저장(브라우저 IndexedDB는 typed array 뷰를 저장할 때 버퍼 전체를 복제하므로 뷰 금지). 웹 해셔는 `crypto.subtle`이 없으면(비보안 컨텍스트) `package:crypto`로 대체.
- T13: 썸네일 작업은 한 줄로 순서대로 실행(쓰기 뒤 읽기가 그 쓰기를 봄). 휴지통 영구 삭제는 커밋 뒤 그 페이지들의 썸네일을 지운다(`dropPurged`, `updates` 이벤트 없음 — 가짜와 같음).
- T13: `close()` 순서 — 에셋(진행 중 바이트 쓰기와 그 메타 커밋 기다림) → 썸네일 → 쓰기 큐 → watch → bus → 블롭 DB → SQLite.

- T10: 세션 등록부 `DriftSessions`(`storage/drift_sessions.dart`). 쓰기 큐에 `onCommitted` 훅을 두어 커밋마다 ChangeBatch 발행 뒤·watch 재질의와 그 커밋의 `Future` 완료 **전에** 부른다. 열린 노트의 노트 행 변경(이름·휴지통·복원 — N-4)은 노트 행을 다시 읽어 `noteCommitted`, `origin: remote`의 페이지·획 변경은 행을 다시 읽어 새 엔진 메서드 `SessionEngine.remoteCommitted`로 반영한다(N-7: 로드된 페이지의 획 갱신·`PageContentChange(origin: remote)`, 페이지 목록·노트 갱신, 히스토리에 넣지 않음). 메모리 `contentRevision`은 행이 쓰인 페이지 = max(DB 값, 메모리 + 1), 획만 바뀐 페이지 = 메모리 + 1.
- T10: 세션 쓰기는 엔진이 찍은 버전 그대로 쓴다(`putLocal(fixedVersion: e.version)` — 메모리와 행의 버전이 같아야 undo의 버전 비교(6.7.3)가 원격 변경을 알아본다; 원격 변경 뒤 undo 건너뜀은 이미 동작, `note_session_test`). `localPages`는 `content_rev`만 UPDATE. 노트 파생 값은 `refreshNoteDerived(tx, noteId, updatedAt:)`(`page_count`·`first_page_id`는 DB 페이지 행으로 다시 계산, `updated_at` = max) — 버전·outbox 없음, ChangeBatch에는 노트 항목을 넣는다(가짜와 같음).
- T10: 아직 커밋 안 된 세션 쓰기의 엔티티는 `write()`부터 그 커밋의 `afterCommit`까지 잡아 두고(도메인 오류로 끝나면 완료 때 해제), 원격 반영은 잡힌 엔티티를 건너뛴다(뒤에 커밋될 로컬 쓰기가 메모리 값과 같아짐). 같은 트랜잭션에 든 로컬 쓰기는 이미 풀려 있어 DB 최종 값을 읽는다.
- T10: `loadStrokes`는 그 페이지만이 아니라 쓰기 큐 전체를 flush한 뒤 읽는다. 동시에 들어온 `openSession` 두 번은 생성 하나를 공유한다. 다른 소유자 노트는 `EntityNotFoundException`. `schemaVersion >` 현재 → `requiresNewerApp`로 읽기 전용, `<`(마이그레이션)은 T15(지금은 v1뿐). 저장소 `close()`는 열린 세션을 잊는다.

- T11: 별칭 정리 — B2는 '히스토리가 빌 때까지 유지'였다. T11은 엔티티마다 그 엔티티를 건드리는 단계 수(undo + redo 스택)를 세어, 마지막 단계가 빠질 때 그 엔티티의 별칭을 함께 지운다(`EditHistory._steps`, 계획서 6.7.3 '해당 항목이 빠질 때'를 엔티티 단위로 해석 — 아래 단계가 같은 엔티티의 별칭을 필요로 하는 경우(지우개 → undo → 새 편집 → 추가 undo)를 지키려고). 새 단계는 redo를 비우기 전에 센다. 어떤 단계도 건드리지 않는 엔티티의 별칭은 만들지 않는다. 테스트용 `debugAliasedEntityCount`.
- T11: 원격 충돌·바뀐 필드 계산은 B2 엔진(`changedFieldsOf`, 버전 + 별칭 비교)이 이미 하고 있었고, T10에서 세션 쓰기가 엔진 버전을 그대로 쓰게 되어 실제 저장소에서도 성립한다. T11은 실제 저장소 테스트로 고정했다.

- T14: `DriftSyncStore`(`storage/drift_sync_store.dart`). 모든 쓰기는 쓰기 큐 작업 1개(= 그 트랜잭션의 savepoint). `ArgumentError`는 큐 전(검증), `StateError`(WriteMerged 불변식·종류/ID 불일치, reassignOwner `from` 불일치)는 작업 안에서. **정책 예외**는 내부 `Error` 래퍼(`_PolicyFailure`)로 작업 밖에 실어 재시도 없이 savepoint만 되돌리고, `applyRemote`가 원래 예외를 원래 스택으로 다시 던진다(쓰기 큐의 '그 밖의 예외 = 저장 실패 → 재시도' 규칙을 피함). 커밋 실패는 재시도(정책도 다시 호출 — 순수 함수라 같은 결과).
- T14: `HlcClock.receive`는 작업 끝에서 한 번(모든 `RemoteUpsert`의 최대 버전) — `WriteTxn.putRemote(advanceClock: false)`. 정책 예외로 끝나면 시계도 그대로.
- T14: 원격·복구 행 쓰기 = `putRemote`(받은 버전 그대로, 기존 행의 로컬 열 유지) + 새 행 규칙(노트는 로컬 값 없이 — `lastOpenedAt` null·`pageCount` 0 뒤 재계산, 페이지 `contentRevision` 0, 에셋은 `AssetStoreImpl.localStateOf`로 `hasLocalBytes`·`chunk_count`). 노트 행 자체의 `updatedAt`도 max(현재, 받은 값). 작업 끝에 쓰인(이미 있던) 페이지 `content_rev + 1`(한 번), 영향 노트마다 `refreshNoteDerived(updatedAt: 받은 값 최대)`.
- T14: `RemotePurge`는 그 id의 폴더/노트 행(**로컬에서 활성이어도**) + `trashRootId == id`인 폴더·노트 + 노트들의 페이지·획·녹음과 그 outbox 항목 전부를 지우고 새 outbox 항목은 없다. 지운 행이 하나라도 있을 때만 `purged++`. `affectedNoteIds` = taken/merged로 쓰인 노트(페이지·획·녹음의 노트 포함) ∪ 영구 삭제된 노트. 트래시 `_purgeGroup`의 페이지·획·녹음 삭제를 `deleteNoteContents(tx, noteIds)`로 빼서 같이 쓴다(획 outbox는 `pageId`로도 지움).
- T14: `WriteMerged.fieldsToUpload`는 걸러내지 않고 그대로 저장(계약 'EXACTLY'). 항목 `hlc` = `versions.max`, 힌트 채움. `TakeRemote`는 purge 항목이면 `dropPendingLocal`과 무관하게 지움(v1.3).
- T14: `commitRepairs`의 `fields`는 `syncedFieldsOf`로 메타 키·로컬 전용 키를 빼고, 남는 것이 없으면 `ArgumentError`. `*`가 있으면(또는 행이 없으면) 엔티티 전체를 `*`·새 HLC로. 엔티티 ID 검사는 `isValidEntityId`, 설정은 설정 키 규칙(`checkSettingKeyName` — 키에 `.`가 있어 ID 규칙과 다름).
- T14: `reassignOwner` — `to`가 빈 문자열이면 `ArgumentError`. `from` 비교는 트랜잭션 안에서 kv `store.ownerId`(같은 트랜잭션에 앞서 큐에 든 reassign 반영)와. 바뀐 행(folders·notes·pen_presets·assets)마다 `EntityChange`, 커밋 뒤(`afterCommit`) `DriftNoteStore.switchOwner(to)` → watch 재질의가 새 소유자로. `from == to`면 쓰기 없음.
- T14: `duplicateNoteForRecovery` — 원본 행은 소유자를 따지지 않는다(행이 있으면 복사). 폴더 = 원래 폴더가 (현재 소유자의) 활성이면 그 폴더, 아니면 최상위. 대상 위치의 맨 뒤 sortKey. `titleSuffix`가 200자 이상이면 `ArgumentError`(`copyItems`와 같음). 복사는 `DriftLibraryRepository.copyNote`.
- T14: `watchPendingCount` = `WatchHub` 재질의(엔티티 종류를 건드린 커밋, 또는 의사 kv 키 `#outbox`를 건드린 커밋 — `acknowledge` 등) + distinct. `pendingChanges(limit < 1)` → `ArgumentError`. `readVersioned`는 종류별 `IN` 질의(500개씩), 요청 순서대로(중복 허용). `readMeta`는 큐를 flush하지 않고 커밋된 값을 읽는다.
- T14: 열린 세션의 노트가 영구 삭제되면(트래시 purge·`RemotePurge`) 세션 노트를 `deletedAt`을 찍은 마지막 상태로 바꿔 읽기 전용으로 만든다(`DriftSessions.committed`, 6.10.3 끝 문단).

- T19: 문서 작성기 `BackupJsonWriter`(`backup/backup_export.dart`)를 실제·가짜가 같이 쓴다 — 압축 JSON(들여쓰기 없음), 머리 키 순서 `format, formatVersion, exportedAt, ownerId, deviceNodeId, schema, entities`, 엔티티 `{"kind","data"(6.3 JSON),"versions"}`를 하나씩 바이트로 붙임(`JsonUtf8Encoder`, `BytesBuilder(copy: false)` + `takeBytes`). 순서 = `EntityKind.values` 순 → id(설정은 key) 순. 소유자로 거르지 않는다(기기 전체). 실제 저장소는 `flush()` 뒤 읽기 트랜잭션 하나에서 종류별 keyset 페이지(2,000행, `readVersionedPage`)로 읽는다(쓰기 큐는 그동안 뒤에서 기다림 — 세션 메모리 편집은 막히지 않음). 가짜는 맵을 id 정렬, 버전 = `EntityFieldVersions(entity.version)`(필드 버전 없음 → 골든 상태는 엔티티 단위 버전만 씀). 닫힌 저장소 → `StateError`.
- T19: 골든 상태의 획 `updatedAt`은 노트 `updatedAt` 이하로 둔다 — 실제 저장소 시드(`applyRemote` TakeRemote)가 노트 `updatedAt`을 자식 적용값의 max로 올리기 때문(6.10.3). 골든 파일 갱신은 `UPDATE_BACKUP_GOLDEN=1 flutter test test/backup/backup_export_test.dart`(VM 전용 — 웹은 1.0을 1로 씀).
- T19: 웹 테스트는 가짜 저장소와 (T16부터) 실제 웹 저장소(WasmDatabase, `openWebStoreWithNode`)에서 공유 본문을 돌고, 골든 상태에서 두 저장소의 바이트가 같은지도 본다.
- T19: `fake_store_test`의 'exportBackupJson is UnimplementedError in B2'를 '백업 형식을 씀'으로 바꿨다. `lib/testing.dart` 주석('UnimplementedError in B2; the same format as the real store from CORE T19')은 계약 7.6 문구라 그대로 둔다.

- T15: `NoteMigrator(steps, store:)`(`migration/note_migrator.dart`, 계획서 6.15 모양에 `store:`만 더함). 단계들은 쓰기 큐 작업 하나(= 한 트랜잭션)에서 돌고, `putPage`·`putStroke`는 모아 두었다가 끝에 바뀐 JSON 키만 로컬 쓰기(`putLocal` — 필드 버전·outbox), 노트는 `{schemaVersion}`(+ `updatedAt` = max(현재, 지금)). 단계 예외는 내부 `Error` 래퍼로 재시도 없이 되돌린 뒤 원래 예외를 다시 던지고, 단계가 없으면 `StateError`. 앱의 단계 표 `kNoteMigrationSteps`는 비어 있다(v1이 첫 형식). 테스트는 `store.noteMigrator = NoteMigrator(...)`(@visibleForTesting).
- T15: `openSession`은 `schemaVersion < kNoteSchemaVersion`이면 먼저 이주하고, 실패하면 열기 실패가 아니라 그 노트를 옛 버전 그대로 연다 — `SessionEngine.isReadOnly`에 `schemaVersion < kNoteSchemaVersion`을 더해 읽기 전용(6.15 '그 노트만 읽기 전용'; 계약 N-4의 두 경우(휴지통·새 스키마)에 더해지는 CORE 내부 경우).

- T16: `tool/prepare_web_test.dart` — `drift_worker.js`는 `Isolate.resolvePackageUri(package:drift)`로 찾은 drift 패키지에서 복사(작업 공간이라 멤버 `.dart_tool/package_config.json`이 없음). `sqlite3.wasm`은 캐시(`.dart_tool/note_core_web_test/sqlite3-3.8.0.wasm`) → **drift 패키지의 `extension/devtools/build/sqlite3.wasm`(같은 릴리스 파일, sha256 일치)** → 7.1 주소 다운로드(`HttpClient.findProxyFromEnvironment`) 순. 둘 다 sha256 검증. 다운로드 경로도 컨테이너 프록시로 200·758,619 B 확인.
- T16: `navigator.storage` 처리를 순수 Dart `storage/web_storage/storage_query.dart`(`StorageQuery` 인터페이스, `storageInfoAtOpen`·`refreshedStorageInfo`)와 브라우저 바인딩 `persistence_browser.dart`(`platformStorageQuery()`, stub은 null)로 나눴다 — 1초 상한을 VM fake_async로 검증하려고. persist()뿐 아니라 persisted()·estimate()도 호출마다 1초 상한(멈춘 브라우저 API가 열기를 막지 않게), 실패·초과는 그 필드 null(refresh는 이전 값 유지). `openNoteStore`는 이 조회를 DB 열기와 **동시에** 돌리고 끝나면 `DriftNoteStore.storageInfoAtOpen`에 넣는다(열기 시간에 persist 대기가 더해지지 않음).
- T16: 웹 `deleteLocalNoteData`의 10초 제한은 `connect_browser.dart` `deleteLocalData(config, {timeout})`(`deleteBlockedTimeout`). 브라우저 테스트는 300 ms로 막힘을 확인한다.
- T16: `flutter test --platform chrome`은 DDC(디버그) 컴파일이라 웹 시간 기록은 운영 빌드보다 느린 값이다. 실측(다른 영역과 CPU 공유): 빈 DB 567 ms, 획 1만 개 다시 열기 338~411 ms(계획서 6.18에 기록, 7.3 기준값 2배 이내).

- T17: provider 테스트 본문을 `test/shared/providers_contract.dart`(`defineProviderContractTests(open)`, `readWhileListening(container, provider)`)로 옮겨 두 저장소에 돌린다. 공유 본문의 `syncPendingCountProvider` 기대값은 `pendingChanges().length`(가짜 0, 실제는 기본 프리셋 outbox 5). `storageInfoProvider` 갱신 테스트는 VM에 `navigator.storage`가 없어 `DriftNoteStore.open(storageQuery: 테스트 더블)`로 실제 저장소를 연다.

- T18: 성능 예산은 VM에서 측정(다른 영역과 CPU 공유, 2026-11-05): 10만 획 시드 45.9~55.2 s(기록), `openSession` 5.2~5.7 ms, 2,000획 `openPage` 중앙값 58~88 ms, 5,000획 페이지 `execute` 평균 0.35~0.37 ms, 1획 커밋 중앙값 6.8~7.8 ms, 점 100만 개 디코드 60~90 ms, `watchListing` 첫 값 중앙값 17~20 ms — 모두 예산 안. 측정마다 워밍업을 두고 중앙값(또는 평균)으로 판정한다. 값은 README 표에도 있다.
- T18: README의 예제 코드 블록은 `test/readme_examples_test.dart`가 같은 코드로 컴파일·실행한다(앱 셸은 VM이라 `inMemory`, 웹 경로 config는 `storageUnavailable` 분류 확인).

- 기반 단계(B2) 차이는 `/home/user/wt/notes/foundation-core.md` '계획과 다르게 한 점'에 있다(값 타입 `==`·`copyWith` 추가, `pageChanges` 첫 load 전달 시점, 히스토리 별칭 보존, 가짜 저장소 세부 동작 등).

## 다음 세션 메모

- 세션 5 끝 상태: T16·T17·T18 완료 → 동시 개발 단계 몫(T6~T19) 전부 완료. 검사: 패키지 VM 617개 통과(perf 파일 5개는 파일 단위 skip, `--run-skipped -t perf`로 6개 테스트 통과), Chrome 47개 통과(perf 1 skip, 따로 돌려 통과), `ws check` 0, 루트 `flutter analyze --fatal-infos` 0.
- 세션 5: T16 완료. 브라우저 테스트 도우미 `test/web/web_store_support.dart` — `freshWebConfig(tag)`(테스트마다 새 DB·블롭 DB 이름), `dropAfterTest(config)`(닫은 뒤 삭제 — 저장소 close보다 **먼저** 등록), `closeAndDropAfterTest(store, config)`(그룹 tearDown보다 먼저 돌아야 할 때, 예: 공유 본문의 setUp에서 연 저장소), `openWebStoreWithNode(config, node)`(고정 HLC 노드 — 백업 골든 비교용). 브라우저에서 두 저장소를 동시에 열면 `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true`.
- 웹 자산 준비: 패키지 디렉터리에서 `dart run tool/prepare_web_test.dart`(ws가 먼저 실행). 헤드리스 Chrome은 `sharedIndexedDb`, `persist()` = false, 할당량 약 10 GiB.
- 세션 4 끝 상태: T14·T19·T15 완료. 실제 저장소의 `SyncStore` 전부, `exportBackupJson`(실제·가짜), 노트 형식 이주가 동작한다 — 실제 저장소에 남은 `UnimplementedError` 없음. 검사: 패키지 VM 591개·Chrome 29개 통과, `ws check` 0, 루트 `flutter analyze --fatal-infos` 0.
- T14 테스트 도우미(`test/sync/support/sync_support.dart`): `upsert(entity, hlc, overrides)`(JSON 디코드 + version = max, SYNC가 넘기는 모양), `remoteAfter(store)`(로컬 스탬프보다 새 원격 HLC), `RecordingPolicy`(호출 기록), `fieldLwwPolicy()`(SYNC 6.3.4 모양의 필드 단위 LWW, `entityVersionOnly: true`는 대조군), `push(from, to, policy)`(outbox → readVersioned → applyRemote → ack). 두 저장소를 동시에 여는 테스트는 `driftRuntimeOptions.dontWarnAboutMultipleDatabases`를 켠다.
- 원격 쓰기 흉내는 이제 `store.sync.applyRemote([...], policy: newerVersionWinsPolicy)`로 써도 된다(T10·T11 테스트의 `queue.run(... putRemote ...)`는 그대로 둠).
- 테스트 도우미: 원격 쓰기 흉내는 `store.queue.run((tx) => tx.putRemote(...), origin: ChangeOrigin.remote)`(`test/edit/undo_support.dart` `UndoFixture.remote`, `note_session_test`의 `_putRemote`). T14가 `applyRemote`를 만들면 그것으로 바꿔도 된다.
- 세션 3 끝 상태: T13·T10·T11 완료. 실제 저장소의 `assets`·`thumbnails`·`openSession`(N-1~N-7)·undo/redo(원격 충돌 건너뜀, 필드 단위 outbox)가 동작한다. 남은 `UnimplementedError`: `SyncStore` 나머지(T14), `exportBackupJson`(T19). 검사: 패키지 VM 513개·Chrome 24개 통과, `ws check` 0, 루트 `flutter analyze --fatal-infos` 0.
- **fake_async 주의(다른 영역에도 알릴 것)**: idb_shim 메모리 IndexedDB(sembast)는 0.1 ms 타이머로 끝난다. `openTestNoteStore` 저장소에서 에셋 `put`·썸네일 쓰기를 fake_async 안에서 쓰면 `flushMicrotasks`만으로는 안 끝나고 시간을 진행해야 한다(`asset_store_test`의 `pumpUntil` — 1 ms씩 elapse). 라이브러리·세션 쓰기(SQLite)는 전처럼 마이크로태스크만으로 끝난다.
- T13 사용법: 에셋 바이트 경로 도우미는 `assets/blob_store.dart`(`writeChunks`·`readChunks`·`hasAllChunks`·`chunkCountFor`·`chunkKey`·`chunkPrefix`, 청크 4 MiB). 저장소의 블롭 DB는 `store.blobs`(`chunks`·`thumbnails`). `putLocal(..., assetChunkCount:)` 추가(null = 행 값 유지).

- T7 쓰기 경로 사용법(T8 이후 모든 쓰기는 이것으로): `store.queue.run((tx) async { ... }, origin: ChangeOrigin.local, bytes: 점 바이트)`. 작업 안에서 `tx.putLocal(entity, 바뀐 JSON 키)`(HLC 찍기·필드 버전·행·outbox·`EntityChange`, `{*}` = 새로/전체, 로컬 전용·메타 키만이면 버전 유지·outbox 없음), `tx.putRemote(entity, versions)`(원격·복구 경로: 그대로 저장·outbox 없음·로컬 열 유지·고아 획 처리·HLC receive), `tx.purge(ref)`(행 삭제 + outbox purge), `tx.addChange`, `tx.afterCommit(f)`(커밋 뒤·ChangeBatch 전 메모리 갱신), `tx.noteIdOfPage`. 작업이 `Error`·`NoteCoreException`을 던지면 그 작업만 savepoint로 되돌리고 재시도 없이 그 오류로 완료, 그 밖의 예외는 트랜잭션 전체 롤백·재시도. 테스트 주입은 `store.queue.failNextCommits(n)`, 트랜잭션 수는 `debugTransactionCount`. 행 변환은 `row_mappers.dart`(`writeEntityRow`·`readVersionedRow`·`*Of(row)`), outbox 읽기는 `readOutbox`.
- fake_async 안에서 drift `NativeDatabase.memory()`가 타이머 없이 마이크로태스크만으로 돈다(write_queue_test에서 확인) → 재시도 간격 테스트를 실제 저장소로 쓸 수 있다.
- T6 산출물: `lib/src/storage/`(db/tables·note_database(+.g)·migrations, kv_keys, open_errors, connect/*, drift_note_store), `drift_schemas/note_db/drift_schema_v1.json`. 스키마를 바꾸면 패키지 디렉터리에서 `dart run build_runner build` → `dart run drift_dev make-migrations`(`--delete-conflicting-outputs`는 쓰지 않음). `schema_test`가 drift_schemas JSON과 실제 테이블·인덱스를 대조한다.
- T8 사용법(T9 이후): 라이브러리 쓰기는 `DriftLibraryRepository`(`storage/drift_library_repository.dart`). 활성 행·트리 도우미 `activeFolders()`, 복사 경로 `copyNote(tx, note, folderId:, sortKey:, title:)`(T14 `duplicateNoteForRecovery`가 재사용), 이름 검사 `checkLibraryName`, 접미사 자르기 `nameWithSuffix`. watch는 `store.watches.watch(affects:, query:, equals:)`.
- 세션 2 끝 상태: T8·T9·T12 완료(커밋 6d0c569·6bb6c01·3503f6c). 실제 저장소에서 라이브러리·휴지통·프리셋·설정·`NoteContentReader`가 동작하고, 세션(`openSession`, T10)·에셋·썸네일(T13)·`SyncStore` 나머지(T14)·`exportBackupJson`(T19)은 아직 `UnimplementedError`. 검사: 패키지 VM 419개·Chrome 12개 통과, `ws check` 0, 루트 `flutter analyze --fatal-infos` 0.
- 세션 1 끝 상태: T6·T7 완료. 실제 저장소는 열기·쓰기 경로까지 동작하고, 저장소 멤버(라이브러리 등)는 아직 `UnimplementedError`. T8은 계획서 6.8(라이브러리·휴지통 규칙)·4.5(LibraryRepository 계약)·6.19(가짜와 같은 의미)를 읽고, 가짜 `lib/src/fake/fake_note_store.dart`의 `_FakeLibrary`를 동작 기준으로 삼아 `test/shared/library_contract.dart`를 두 저장소에 돌린다. watch 스트림은 커밋 뒤 재질의(가짜의 `watch()`처럼 구독 즉시 1회 + 바뀔 때) — `queue`의 커밋 알림에 붙이면 된다(`WriteTxn.afterCommit` 또는 `bus.stream`).
- 세션 1: 문서 절차(C13-05, CORE-4-1~4-3) 끝 — 02-core.md 상태 줄 '승인'·계약 v1.4, 4.6·4.7 v1.3 주석, 6.13 bullet, 12.2 CP-8 결정, 13.4. 코드 계약 파일은 B2에서 이미 v1.3 주석.
- Riverpod 3.4.3은 리스너 없는 provider를 멈춘다. 테스트에서 `container.listen(p.future, (_, _) {})` 뒤 `sub.read()`.

## 통합 단계

1차 통합(계약 7.7 순서 CORE → INK → EDITOR·LIBRARY 병합 뒤, 통합 브랜치 `claude/note-app-planning-bk29xb`, 기준 7632d20). PDF·SYNC·INFRA는 아직 동시 개발 중이라 이 브랜치의 `pdf_io`·`sync_engine`·`app`은 기반 단계 자리표시다. 이 브랜치의 `packages/note_core`는 영역 브랜치 끝(4336967)과 같다 — CORE `lib/`·`test/`는 바꾸지 않았다(이 기록만).

### 확인 (2026-11-05, CPU 4를 다른 영역 통합 담당과 공유 — load 5~6)

| 검사 | 결과 |
|---|---|
| `ws test --run-skipped -t integration --package note_core` | 해당 테스트 없음(`no matching tests` — ws는 통과로 셈). CORE는 `integration` 태그를 쓰지 않는다(계획서 8.2 병렬화 메모·9.1). 실제 CORE를 쓰는 통합 테스트는 다른 영역 몫(아래) |
| `ws test --package note_core` (VM, 골든 포함) | 617개 통과, 5개 건너뜀(perf 파일) |
| `ws test --platform chrome --package note_core` | 준비 스크립트 ok, 47개 통과, 1개 건너뜀(perf `open_time_browser_test`) |
| `flutter test --run-skipped -t perf` (패키지, 10절 #2 '성능 예산') | 6개 통과 — 1획 커밋 중앙값 27.6 ms(< 30), `watchListing` 첫 값 29 ms(< 100), 2,000획 `openPage` 131 ms(< 300), 5,000획 `execute` 평균 1.54 ms(< 2), 점 100만 개 디코드 72 ms(< 300), 10만 획 `openSession` 4.4 ms(< 200), 10만 획 시드 63.6 s(기록만) |
| `ws check` | 위반 0 |
| 루트 `flutter analyze --fatal-infos` | 0건 |
| `dart format` (`packages/note_core`·`packages/ink_engine`) | 변경 없음 |
| R14 미리 보기(INFRA G3 전 — scratch 스크립트, 루트 lock의 `analyzer` 13.3.0으로 6개 패키지 `lib/` 최상위 진입점 15개의 `exportNamespace` 비교) | 패키지 사이 겹치는 이름 **0**. note_core 진입점 4개 = 198·4·1·1 이름. PDF·SYNC는 기반 단계 표면 기준이라 그 병합 뒤 INFRA G3가 정식 판정 |

- perf 메모: 1획 커밋 중앙값이 T18 측정(6.8~7.8 ms)보다 크게 나온 것은 부하(load 5.8, 다른 에이전트 테스트 동시 실행) 때문이다 — CORE 코드는 T18 이후 그대로. 부하가 더 크면 30 ms 예산을 넘길 수 있으니 판정은 load < 4에서 다시 잰다(계획서 9.1).

### 다른 영역 통합 테스트에서 본 CORE (이 브랜치 기준)

- EDITOR E-21(`feature_editor/test/integration/real_core_ink_smoke_test.dart` — `openTestNoteStore()` 기본값 + 실제 INK)·브라우저 스모크: EDITOR 통합 담당이 통과 확인(editor.md '통합 단계', 299001b). CORE 쪽 변경 요청 없음. 실제 INK 합류로 깨졌던 EDITOR 테스트 2개도 CORE와 무관(INK B3 세부 동작 전제).
- LIBRARY L21(`feature_library/test/integration/core_contract_test.dart`): LIBRARY 통합 담당이 실제 CORE로 조정 중. 이 기록 시점까지 CORE 쪽 변경 요청을 받은 것 없음.
- PDF `integration`(CORE 게이트웨이)·SYNC T16(실제 CORE 2개로 S01·S02·S05·S15 + JSON 키 대조 + `CoreSyncLocalStore(openTestNoteStore)` 계약 스위트 C-01~C-25 + `FolderTree.findCycles()` 대조): 그 영역 병합 뒤(계획서 10절 #7).
- INFRA V5·V6 스모크, G2(저장 경고 배너 문구가 두 화면에서 같음 — 메모리 CORE·`openTestNoteStore()` 기본은 `nativeMemory` → `notDurable`, 5.1 I-12): INFRA 병합 뒤.

### 다른 영역 통합 담당이 알아 둘 CORE 동작 (앞 세션 메모에서 옮김)

- `openTestNoteStore`(VM, `NativeDatabase` 테스트 isolate)의 라이브러리·세션 쓰기는 마이크로태스크만으로 끝난다(fake_async 안에서도). **에셋 `put`·썸네일 쓰기는 idb_shim 메모리 IndexedDB(0.1 ms 타이머)를 거치므로 fake_async 안에서는 시간을 진행해야 끝난다**(`asset_store_test`의 `pumpUntil` — 1 ms씩 elapse). PDF `integration`(에셋)에 해당.
- `openTestNoteStore`는 휴지통 자동 비우기 타이머를 만들지 않는다(`openNoteStore`만). 같은 프로세스에서 두 저장소를 동시에 열면 `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true`(SYNC T16).
- 원격 쓰기 흉내는 `store.sync.applyRemote([...], policy: newerVersionWinsPolicy)`.

### 남은 것

- 계획서 10절 #7: SYNC T16을 막는 CORE 결함이 없음 — SYNC 병합 뒤 판정. 결함이 보고되면 CORE가 고친다.
- 10절 #9·9.2: 앱 웹 빌드(INFRA 병합 뒤)에서 사용자 iPad 확인.
- INFRA G3 R14 정식 판정(위 미리 보기는 참고값).
- 변경 요청: 없음. 의존성 요청: 없음(`pubspec.lock` 변경 없음). 공개 API 변경 없음.

### 7개 영역 병합 뒤 — SYNC 변경 요청 (2026-11-05, 통합 브랜치 기준 95c151f)

7개 영역이 모두 병합된 통합 브랜치에서 SYNC 통합 담당이 보낸 `[core]` 요청 2건. 둘 다 `openTestNoteStore`(`testing_vm.dart`) 관련, 시그니처 변경 없음. 커밋 c4966ce.

| 요청 | 재현 | 판단 | 처리 |
|---|---|---|---|
| 1. (optional, low) `openTestNoteStore`용 커밋 실패 훅. SYNC S-20 실제 CORE 테스트 2개는 열린 DB 파일을 옮겨(`CoreTestStore.failCommits`, SQLITE_READONLY_DBMOVED) 커밋을 실패시키는데, 이는 `openTestNoteStore` 파일 DB가 롤백 저널이라서만 된다(앱 `connect_native`는 WAL) | 재현됨: `testing_vm.dart` 파일 DB를 잠시 `NativeDatabase(..., setup: PRAGMA journal_mode = WAL)`로 바꾸고 `sync_engine`에서 `flutter test --run-skipped -t integration --plain-name S-20 test/integration/core_scenarios_test.dart test/integration/core_sync_store_contract_test.dart` → 두 테스트가 'fault injection did not take effect'(쓰기 8개가 `value`, rename 커밋됨)로 실패. 되돌림 | 타당(우회가 CORE 내부 성질에 기댐). 그러나 공개 훅은 계약 7.6 B2 도우미 시그니처 추가 → 7.4.12 절차, **총괄 결정 필요** — 구현하지 않음 | 시그니처 없이 할 수 있는 몫: 기대고 있는 성질을 CORE가 명시하고 테스트로 고정 — `openTestNoteStore` 문서 주석에 CORE 줄('파일 DB는 SQLite 기본 롤백 저널(WAL 아님, `openNoteStore`와 다름), 열린 파일을 옮기면 커밋이 실패·재시도(6.9) — SYNC S-20이 기댐'), `open_test_store_test` 'a file database keeps the rollback journal …'(`PRAGMA journal_mode` = `delete`; 파일을 옮긴 동안 쓰기 Future 미완료·`consecutiveFailures ≥ 1`·`lastError`·`pendingOps > 0`·읽기 계속; 되돌리면 그 쓰기가 커밋·실패 수 0). 누가 WAL로 바꾸면 CORE 테스트가 먼저 실패한다 — WAL로 바꿔 pragma 단언 실패, pragma 단언을 빼도 '쓰기 미완료' 단언 실패를 확인(시간 기반 단언 없음: 실패 상태 또는 쓰기 완료 중 먼저 오는 것을 기다림) |
| 2. (low) 한 isolate에서 실제 CORE 2개를 열면(두 기기) debug에서 열 때마다 'WARNING (drift): … NoteDatabase multiple times' + 스택. executor가 달라 실제 문제 없음, 소음. SYNC는 drift 의존이 없어(7.5) 끌 수 없음 | 재현됨: `sync_engine`에서 `flutter test --run-skipped -t integration test/integration/core_scenarios_test.dart` → 경고 7번(7개 통과) | 타당. `openTestNoteStore`는 호출마다 executor를 새로 만들어 drift가 경고하는 '같은 QueryExecutor' 위험이 없다 | `openTestNoteStore`가 `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true`(isolate 전역 — drift의 열린 DB 수가 전역이라 범위를 좁히면 수가 어긋남). 앱 경로 `openNoteStore`는 그대로(경고 유지). 새 테스트 `test/testing/open_test_store_drift_warning_test.dart`(파일 따로 — 대조군이 앞 테스트가 남긴 수에 흔들리지 않게): 대조군 `openNoteStore(inMemory)` 2개 동시 → 경고가 잡힘, `openTestNoteStore` 3개(메모리 2·파일 1) 동시 → 경고 0, 서로 다른 DB. 수정 줄을 빼면 이 테스트가 실패함을 확인. SYNC 같은 명령: 경고 7 → **0**, 7개 통과 |

요청 1 — 총괄 결정용 CORE 의견:

- 안 A(계약 7.6 변경): `openTestNoteStore({…, FakeNoteStoreFaults? faults})` — 이미 계약 타입인 `FakeNoteStoreFaults`를 실제 저장소에도 받아 `WriteQueue`가 커밋마다 확인(`failNextCommits(count, error)` → 내부 `WriteQueue.failNextCommits`와 같은 재시도 경로, `commitDelay`도 같은 의미). SYNC의 '되돌릴 때까지 실패'(`healCommits`)는 지금 `FakeNoteStoreFaults`에 해제 멤버가 없어 `failNextCommits`의 횟수로만 표현된다 — 필요하면 해제 멤버(예: `clearCommitFailures()`)도 같은 7.6 변경에 넣는다(가짜·실제 둘 다). CORE 작업량: `testing_vm.dart`·`write_queue.dart`·`api_surface_test`·테스트 1개, SYNC는 `CoreTestStore.failCommits`만 바꿈.
- 안 B(계약 변경 없음, 이번에 한 것): 지금의 파일 옮기기를 유지하고, 기대는 성질(롤백 저널)을 CORE 문서·테스트로 고정. SYNC 테스트는 그대로 통과.
- CORE 권장: 당장은 B로 충분(SYNC S-20이 실제 CORE 재시도 경로 — SQLite 오류 → 롤백 → 6.9 재시도 — 를 그대로 지남). 실제 앱처럼 WAL 파일 DB로 시험하고 싶거나 가짜·실제가 같은 실패 주입 타입을 쓰게 하려면 A.

확인 (2026-11-05, load 0.5~2)

| 검사 | 결과 |
|---|---|
| `flutter test test/testing/`(패키지) | 44개 통과(새 테스트 2개 포함) |
| `ws test --package note_core` (VM) | 619개 통과(617 + 2), 5개 건너뜀(perf 파일), drift 경고 0 |
| `ws test --platform chrome --package note_core` | 준비 ok, 47개 통과, 1개 건너뜀(perf) — 새 테스트는 `@TestOn('vm')` |
| `ws test --run-skipped -t integration` (전 멤버 VM) | feature_editor 1·feature_library 10·pdf_io 19·noteapp 1·sync_engine 42 통과(note_core·ink_engine·ink_lab은 해당 없음), drift 경고 0 |
| SYNC 요청 재현 명령(`core_scenarios_test`, `integration`) | 7개 통과, 경고 7 → 0 |
| `ws check` | R1~R15 위반 0 |
| 루트 `flutter analyze --fatal-infos` | 0건 |
| `dart format` (`packages/note_core`) | 변경 없음 |

- 공개 API(시그니처) 변경 없음, 새 외부 의존 없음(`drift`는 이미 note_core 의존 — `driftRuntimeOptions`만 import), `pubspec.lock` 변경 없음.
- 변경 요청(다른 영역으로): 없음.

## 2차

계획 docs/plans/m5-7/02-core.md(승인 · 계약 v2.3 — 2026-11-06 동시 개발 착수 때 상태 줄·인용 맞춤). 바탕: `main` `e3aa110` = 1차 통합 HEAD `b6c9d0a` + 계획 병합 `a23c14f` + INFRA R2-B1 `3c77de3`·`7e6a2e6` + SYNC R2-B7b `9cdd3fb`·`e3aa110`. `packages/note_core` 트리는 `b6c9d0a`와 같다(`5e728c8`) — 1차 CORE 코드 그대로.

### 이정표 커밋 (CORE 2차)

| 이정표 | 작업 | 커밋 | 날짜 | 이 커밋으로 할 수 있게 되는 것 | 기다리는 영역 |
|---|---|---|---|---|---|
| V7 고정 자료 | T25a | b6beece | 2026-11-05 | 1차 v1 DB 고정 자료(생성 커밋은 fixture_source.json) | 총괄 |
| B2-α 계약 타입 커밋 | T22 | 2b2e4b0 | 2026-11-05 | 공개 선언 전부 컴파일 — R2-B7a 바탕, R2-B2i 위임, 전 영역 코드 작성 시작 | SYNC·INFRA·전 영역 |
| B2-β JSON 골든 | T20a | 9777fde | 2026-11-06 | 객체·손글씨·녹음 JSON 키 고정 — 키 대조 시험(CP-S9) | SYNC(R2-B7a가 이 해시로 판정 — sync.md) |
| B2-β 끝 | T23b | 0798096 | 2026-11-06 | 가짜 저장소 v2·가짜 오디오·픽스처·testing_web 동작 | 전 영역 |
| DB v2·마이그레이션 | T24 | a2b0489 | 2026-11-06 | openTestNoteStore가 v2 DB, v1 사본(네이티브 파일·웹 블롭 덤프), dev_tools v1 사본 API 동작 — 새 종류의 행 쓰기는 T26부터 | SYNC·PDF·LIBRARY·INFRA |
| 쓰기 경로 | T26 | 3bfff8a | 2026-11-06 | 새 종류(객체·손글씨) 행·`recordings.title`·`pages.bg_*`, 힌트(`noteId`·`pageId` 항상), 원격 고아 객체 입양, `readVersioned`·백업 읽기 — SYNC 시나리오 시험 가능(원격 객체의 `content_rev`는 T28) | SYNC |
| 객체 읽기·쓰기 DB | T27 | 2db774e | 2026-11-06 | 실제 저장소(`openTestNoteStore`·웹 저장소) 세션의 객체 명령 전부(Add/Update/Remove/Transform/Clear/Insert·DuplicatePages)·undo/redo, `createNote(PageDraft.objects)`, `NoteContentReader.loadPage(…).objects`(PDF 내보내기 `integration`), 원격 객체 → 로드된 페이지 `PageContentChange(remote)`(N-7) | EDITOR(E-2x)·PDF |
| 동기화 창구 v2 | T28 | 3d49685 | 2026-11-06 | `applyRemote`·`commitRepairs`·`readVersioned`·`pendingChanges`가 새 종류(객체·손글씨)로 동작, 원격 객체·손글씨가 쓰인 페이지 `content_rev + 1`, 모르는 `type` 왕복(C-12) — T16-v2(로컬 객체 편집은 실제 저장소 세션 T27부터, 녹음·손글씨 저장소 T30·T32) | SYNC |
| 복사·휴지통·백업 | T29 | | | copyNote·영구 삭제·백업 v2 | LIBRARY·SYNC |
| 녹음 저장소 | T30 | 3b5adfa | 2026-11-06 | 실제 저장소 `recordings`: `createRecording`(id 멱등 — 검증보다 먼저 저장된 행)·`renameRecording`·`deleteRecording`·`recordingsOf`·`watchRecordings`·`audioBytesOf`, 공유 본문 `recording_contract`가 가짜·실제 둘 다 | PDF(media)·EDITOR |
| 실제 초안 저장소 | T31 | 2d8dd0a | 2026-11-06 | 실제 저장소(`openTestNoteStore`·`openWebTestNoteStore`)의 `recordingDrafts`: meta 먼저·부른 순서 `append`(커밋 뒤 완료)·빈 조각·행 유실 → meta로 되살림·첫 사용 고아 정리·`readAll` 한 벌·`discard` — PDF `media` Chrome 시험(X-1, V16) | PDF(media) |
| 손글씨 저장소 | T32 | | | update·stalePages·notesWithStalePages | LIBRARY |
| 색인 쓰기 | T33a | | | SearchIndexWriter 실제 — PDF 색인기 | PDF |
| 검색 색인 | T33b | | | searchPages·searchLibrary.pages 실제 | LIBRARY·PDF |
| 네이티브 저장 | T35 | | | 파일 DB + 파일 블롭 | INFRA(A-1) |

### 작업 표 (2차)

| ID | 상태 | 커밋 | 비고 — 완료 조건 |
|---|---|---|---|
| T25a | 완료 | b6beece | B2-0 V7 고정 자료. `tool/make_v1_fixture.dart`·`tool/v1_fixture_manifest.dart`·`tool/src/v1_dump.dart`, `test/fixtures/db_v1/`(5개 파일), `test/migration/v1_fixture_files_test.dart`(VM 3건) |
| T22 | 완료 | 2b2e4b0 | B2-α 계약 표면. `test/api_surface_test.dart` v2, `test/model/b2_alpha_values_test.dart`, `test/shared/b2_alpha_store_cases.dart` → `test/testing/open_test_store_test.dart`(실제)·`test/testing/fake_store_b2_alpha_test.dart`(가짜 — T23b에서 지움), `test/shared/providers_contract.dart` v2(가짜·실제), `test/web/testing_web_browser_test.dart` |
| T20a | 완료 | 9777fde | B2-β ① JSON·골든. `test/model/object_json_test.dart`, `recording_title_test.dart`, `handwriting_text_test.dart`(JSON), `test/goldens/json_golden_test.dart`(새 골든 9개 + `recording.json`), `test/shared/object_json_web_cases.dart` → `test/model/object_json_web_format_test.dart`(VM)·`test/web/object_json_browser_test.dart`(Chrome) |
| T20b | 완료 | c443015 | B2-β ② 기하·변형. `test/common/element_frame_test.dart`, `test/model/shape_geometry_test.dart`, `test/model/page_object_test.dart`, `test/edit/calligraphy_transform_test.dart`(순수 — Chrome도 `object_json_web_cases`) |
| T21 | 완료 | 38f3578 | B2-β ③ 값 타입·순수 함수. `test/shared/search_text_cases.dart` → `test/search/search_text_test.dart`·`test/web/search_text_browser_test.dart`, `test/search/search_query_test.dart`, `search_rects_codec_test.dart`, `test/media/audio_ports_test.dart`, `test/assets/storage_usage_test.dart`, `test/model/image_import_test.dart`, `handwriting_text_test.dart`(값), `asset_store_test`(CP-11) |
| T23a | 완료 | 12ab8c4 | B2-β ④ 해석기·세션. `test/edit/object_commands_test.dart`, `calligraphy_transform_test.dart`(undo — SQLite 저장소), `test/shared/object_session_contract.dart` → `test/session/object_session_contract_fake_test.dart`, `b2_alpha_store_cases`(실제 — 객체 명령 T27) |
| T23b | 완료 | 0798096 | B2-β ⑤ 가짜 v2·가짜 오디오·픽스처·testing_web. `test/shared/{recording,recording_draft,handwriting,search}_contract.dart` → `test/repo/recording_contract_fake_test.dart`·`test/media/recording_draft_contract_fake_test.dart`·`test/repo/handwriting_contract_fake_test.dart`·`test/search/search_contract_fake_test.dart`, `test/testing/fake_store_v2_test.dart`, `fake_audio_recorder_test.dart`, `fake_audio_playback_test.dart`, `page_object_fixtures_test.dart`, `test/web/testing_web_browser_test.dart`(실제 웹 저장소) |

### T25a — V7 고정 자료 (계획 6.12.3·8.1, 00-review CORE-F2)

- 커밋: `b6beece`(생성기·고정 자료·manifest·지킴 시험·README), 이 기록은 그 뒤 커밋. `lib/` 변경 없음.
- **생성 절차**: `git archive e3aa110 | tar -x -C /tmp/claude-0/core-v1-fixture` → 생성기 두 파일(`tool/make_v1_fixture.dart`·`tool/src/v1_dump.dart`)만 복사 → `flutter pub get --enforce-lockfile` → 패키지에서 `dart run tool/make_v1_fixture.dart --out /tmp/claude-0/core-v1-fixture-out --source-commit e3aa1105d7a1bf560a9640ef12b8561b4ec7b140 --core-tree 5e728c80864959c9052fe3fb7f6195fbcaddef5a` → 산출물을 `test/fixtures/db_v1/`로 복사 → 2차 트리에서 `dart run tool/v1_fixture_manifest.dart`. 임시 트리를 `e3aa110`의 새 `git archive`와 `diff -rq`로 비교하면 차이는 pub get 산출물(`.dart_tool`·`app/` 생성 파일)과 생성기 두 파일뿐 — 2차 코드 없음.
- **내용**(v1.4 공개 API만): 폴더 2개('2026 가을 학기'와 그 아래 전각 라틴 + 자모 분해 한글 이름 — v2 `SearchText.normalize`로 `name_norm`이 달라짐), 노트 A(10쪽, 합성 획 950 + 녹음 연결 획 50, 지운 획 4·옮긴 획 3, 태그·표지), 노트 B(8쪽 800획, PDF 배경 4쪽·템플릿 1쪽, 색 바꾼 획 5, 이름 바꿈·즐겨찾기), 노트 C(2쪽 200획, 휴지통), PDF 에셋 1개(4쪽, 1,990 B), 원격 녹음 1개와 그 오디오 에셋(메타만 — `applyRemote`), 동기 설정 1·기기 설정 1, 기본 펜 프리셋 5. 동기화하지 않아 로컬 쓰기 2,032건이 모두 outbox에 있다.
- 시계: 2026-10-26T00:00:00Z에서 시작해 00:32:05Z에 끝(고정 시계, id는 그 시계의 UUIDv7 모양). 노트 C 휴지통 시각 00:31:05Z — **2026-11-25T00:31:05Z 뒤에 실제 시계로 `openNoteStore`를 열면 10초 뒤 자동 정리가 노트 C를 지운다**(보관 30일). T25b 시험은 고정 시계를 쓴다(`fixture_source.json` `clock`).

| 파일 | 바이트 | sha256 |
|---|---|---|
| `noteapp_v1.sqlite` (VM·네이티브 — `openNoteStore`가 남긴 그대로, WAL 머리) | 2,142,208 | `3ec154b50a3f9046dd56d52c20c0e9abdacfd14a1baaa651ebf07bf13dbcf9e7` |
| `noteapp_v1_web.sqlite` (Chrome — 같은 행, 롤백 저널 머리) | 2,142,208 | `242c3c1ba1a9963266d0dd727471bf2acbdd9d83c61c8ae194d0a6570ae8d134` |
| `pdf_asset.pdf` (= PDF 에셋 id) | 1,990 | `a9d04a94683249a064d05127ae71571899d12bb520b437f697f4309eed125f06` |
| `fixture_source.json` | 3,539 | `71227600c6b4dfd46ddd25b2174fde516c5fb3943b7fb33ad2803e4f4d6aefd7` |
| `manifest.json` | 7,083 | `69f464bcb01f67d08ccadb446b58525b3e0e25efafc3ff07c35910111d1ad39b` |

- 정규 덤프(`noteapp-v1-dump 1`, 2,074,055 B): `fullDumpSha256` `cf89876473bb45d823621ff7b9427f3c61622ee902cff44287c82633376943d5`, `entityDumpSha256` `c99ca4ebb671820b8477b233b78c4db1f30794abdf1c1c2943a0cc38e3b9d9bc`, `outboxDumpSha256` `3f6d27be99da63a120c005aab9cdf9b60e632b836a8a2f81e4df661394909cb9`, `kvDumpSha256` `316de0e9a972a4ea1c8bdd1b02fdaa86ff87b484432f58b60a9a4193594bc815`. 행 수: assets 2·folders 2·kv 5·notes 3·outbox 2,032·pages 20·pen_presets 5·recordings 1·settings 1·strokes 2,000(점 60,000).

확인 (2026-11-05, load 0~1)

| 검사 | 결과 | 시간 |
|---|---|---|
| 생성기 다시 실행(같은 임시 트리, 다른 출력 폴더) | VM 파일의 정규 덤프가 기기 노드 id(`openNoteStore`가 무작위로 만듦)만 바꾸면 커밋한 것과 바이트 단위로 같음, `fixture_source.json`도 시각·노드·해시 외 같음 | 12초 |
| Chrome 확인(임시 시험 — 커밋 안 함, `flutter test --platform chrome`) | `WasmDatabase.open(initializeDatabase: 웹 형태 바이트)` → `sharedIndexedDb`, `user_version` 1, `journal_mode` delete, SQLite 3.54.1, **브라우저 안 정규 덤프 SHA-256 = `fullDumpSha256`**. VM(WAL) 형태를 초기 바이트로 주면 첫 질의에서 `SqliteException(26) file is not a database` | 37초 |
| `dart run tool/v1_fixture_manifest.dart --check` | 최신 | 12초 |
| `ws test --package note_core --platform vm` | 622개 통과(619 + 지킴 시험 3), 5개 건너뜀(perf 파일) | 36초 |
| `ws test --package note_core --platform chrome` | 준비 ok, 47개 통과, 1개 건너뜀(perf). 첫 시도는 테스트 페이지가 하나도 뜨지 않은 채(시험 호스트 페이지만 열림, load 0) 멈춰 15분 제한에 끝나고, `ws`가 다시 돌린 두 번째 시도가 통과 — 1차 INFRA 기록의 헤드리스 Chrome 초기화 멈춤과 같은 모양 | 956.7초(두 번째 시도 약 56초) |
| `ws check` | R1~R16 위반 0·경고 0 | 44초 |
| `packages/note_core` `flutter analyze --fatal-infos` | 0건 | 9초 |
| `dart format --set-exit-if-changed` (새 파일 5개) | 변경 없음 | — |
| `dart test tool/test/repo_hygiene_test.dart tool/test/workspace_test.dart` | 16개 통과, `git check-attr`: 두 `.sqlite`·`.pdf` `binary` | 3초 |

#### T25b가 알아 둘 것

- 브라우저 시험은 패키지의 `test/` 밖을 import할 수 없다(`flutter test --platform chrome`의 앱 뿌리 = `test/` — `../../tool/src/v1_dump.dart`는 'File not found'). Chrome의 덤프는 T24의 `lib/src/storage/db/canonical_dump.dart`를 쓰고, 그 출력은 `tool/src/v1_dump.dart`와 바이트 단위로 같아야 한다(지킴 시험·manifest가 그 형식의 해시).
- 고정 자료 바이트는 `tool/prepare_web_test.dart`가 `test/web/fixtures_v1/`로 복사한다(6.18.1). 웹은 `noteapp_v1_web.sqlite`를 쓴다 — WAL 머리 파일은 웹 워커가 열지 못한다(위 확인). 블롭 DB 항목(키 `<pdfId>/000000`, 1청크)은 `manifest.json` `blobs`.
- 지킴 시험은 커밋한 생성기의 sha256이 `fixture_source.json`의 값과 같기를 요구한다 — 생성기를 고치면(주석·포맷 포함) 같은 절차(1차 트리 `5e728c8`)로 고정 자료를 다시 만든다.

#### 계획과 다르게 한 점 (T25a)

- 생성 커밋 = 지금의 `main` `e3aa110`(작업 지시 '지금 main의 1차 CORE 코드'). `b6c9d0a` 뒤 커밋은 CORE 파일을 바꾸지 않아 `packages/note_core` 트리가 같다(`5e728c8`) — `fixture_source.json`에 커밋·트리 둘 다 적었다.
- 산출물에 `noteapp_v1_web.sqlite`를 더했다(계획 6.12.3은 `noteapp_v1.sqlite` 하나). VM 형태는 `openNoteStore`가 남긴 WAL 머리라 웹 워커가 초기 바이트로 받지 못하고, 행은 같고 머리만 다른 파일을 두면 Chrome 시험이 바이트를 고치지 않아도 된다. 두 파일의 정규 덤프가 같은지 생성기·manifest 도구가 확인한다.
- `manifest.json`과 그 도구(`tool/v1_fixture_manifest.dart`), 덤프 형식(`tool/src/v1_dump.dart`)을 T25b가 아닌 지금 만들었다(CORE-F2 '고정 자료 manifest에 정규 덤프 해시'). 표별 해시·kv 행·블롭 항목도 담았다.
- 계획에 없던 VM 지킴 시험 `test/migration/v1_fixture_files_test.dart`(manifest 최신·파일 해시·V7 모양).
- B2-α 커밋에 넣지 않고 따로 커밋했다(작업 지시 — 이정표 커밋은 다른 작업과 섞지 않음, 8.5).
- 기기 노드 id가 무작위라 다시 돌리면 바이트가 다르다(v1.4 API로는 고정할 수 없음) — 커밋한 파일이 고정 자료이고 manifest가 그 해시다.

### T22 — B2-α 계약 표면 (계획 4.1~4.11·8.1, 계약 7.6.2 R2-B2 행, 00-review CORE-F1·F3)

- 커밋: **`2b2e4b02172b99a3e28d2f6edf478682d683f1f0`**(계약 타입 커밋 — SYNC R2-B7a·INFRA R2-B2i의 바탕), 이 기록은 그 뒤 커밋. 바탕 `051386b`.
- **실제로 동작하는 것**(8.1 'B2 상태' 'α 끝' 열): 생성자·필드·기본값·`==`·`hashCode`·`toString`, enum·한도 상수, `kind`·`type`·`isDeleted`, `referencedAssets`(도형·텍스트·수식 빈 집합, 이미지 `{assetId}`), 계약이 `=>`로 적은 위임(`ShapeObject.frame => geometry.frame`, `bounds => frame.bounds`, `EllipseGeometry.frame` = `ellipseFrame`), `HandwritingText.idFor`·`id = 'hw_' + pageId`, `Recording.title`·`copyWith(title:, clearTitle:)`, `PageContent` 객체 멤버, `PageDraft.objects`·`copyOf`, 명령 3종 `label`·`ClearPage.includeObjects`, `Unsupported*`(6.8.2 표), provider 6개, `SearchText.normalizerVersion`, `ImageImportLimits`.
- **작업 번호를 단 `UnimplementedError('CORE <작업>: <멤버>')`**: JSON 전부(`toJson`·`fromJson`·`EntityJson`의 새 두 갈래, `UnknownObject(rawJson)`) — T20a. `ElementFrame` 기하·`normalized`, `PagePoint.transformed`, 템플릿 6종, `bounds`(도형)·`arrowHeadLength`, `transformed`·`copyTo`·`copyWithMeta`·`estimatedBytes`, 스타일·객체 `normalized`·`copyWith` — T20b. `sourceRevOf`·`isRecognitionInput`·`HandwritingLine/Text.copyWith`, `SearchText` 함수 4개, `RecorderStatus.isActive`·`copyWith`, `PlaybackStatus.copyWith` — T21. 객체를 만들거나 고치는 명령(`AddObjects`·`UpdateObjects`·객체가 든 `InsertPages` — 복합 명령 안 포함)은 해석 **전에** T23a. `PageObjectFixtures`·`FakeAudioRecorder`·`FakeAudioPlayback` 메서드·`openWebTestNoteStore`·`deleteWebTestNoteStore` — T23b.
- **저장소 getter 4개**: 읽기는 빈 결과(`watchRecordings`·`watchPage`·`status`는 값 하나를 내고 열린 채 — 1차 watch 규칙), `readAll`은 초안이 없으므로 `StateError`(계약 '모르는 draftId'), 쓰기는 실제 T30(녹음)·T31(초안)·T32(손글씨)·T33a(색인), 가짜 T23b. `searchLibrary`의 `pages`는 빈 목록, `usage().bytesByType`은 빈 맵, `kDatabaseSchemaVersion`은 1.
- **실제 저장소의 새 두 종류**: `readVersioned`·백업 쪽 읽기(`readVersionedRow`·`readVersionedPage`·`_readKind`)는 '행 없음'(v1 DB에 테이블이 없다), 행 쓰기·지우기(`writeEntityRow`·`deleteEntityRow`)는 `UnimplementedError('CORE T26: …')`(쓰기 큐에서는 도메인 오류라 재시도 없음).
- **`dev_tools.dart` v1 사본 API**(C22-01): `v1DatabaseCopyInfo` → 언제나 `null`. 실제 저장소의 `readV1DatabaseCopy`·`deleteV1DatabaseCopy`는 T24, 사본이 없는 저장소(가짜)는 읽기 `StateError`·지우기 아무것도 안 함.
- `RemoveElements`는 획을 `RemoveStrokes`처럼 지우고, `ClearPage(includeObjects: true)`는 획을 `filter`대로 지운다(객체는 T23a 전에는 있을 수 없다).

확인 (2026-11-05, load 0~1)

| 검사 | 결과 | 시간 |
|---|---|---|
| `packages/note_core` `flutter analyze --fatal-infos` | 0건 | 1초 |
| `ws test --package note_core --platform vm` | 682개 통과(622 + 새 60), 5개 건너뜀(perf 파일) | 31.7초 |
| `ws test --package note_core --platform chrome` | 준비 ok, 48개 통과(47 + `testing_web_browser_test`), 1개 건너뜀(perf) | 55.4초 |
| `ws check` | R1~R16 위반 0·경고 0(R14 — 새 이름이 9개 진입점에서 겹치지 않음) | 37초 |
| 다른 멤버 `dart analyze`(고치지 않고 깨짐만 확인) | `ink_engine`·`ink_engine/example`·`feature_editor`·`feature_library`·`pdf_io`·`media_io`·`ink_recognition`·`pencil_bridge` 0건. `sync_engine` 5건·`app` 1건 — 아래 | — |

#### 묶음(R2-B2 + R2-B7a + R2-B2i)에서 고칠 곳 — 계약 7.0.2와 같음

- `packages/sync_engine/lib/src/model/field_units.dart:21` `keysOf`, `:57` `groupsOf` — `EntityKind` switch에 갈래 없음(컴파일 오류).
- `packages/sync_engine/lib/src/model/scopes.dart:19` `scopeOf` — 같음.
- `packages/sync_engine/lib/src/merge/record_gate.dart:142` `_purged` — 같음(switch 문).
- `packages/sync_engine/test/support/entity_fixtures.dart:65` `fixtureJson` — 같음.
- `packages/sync_engine/lib/src/codec/chunk_packer.dart:56` `kindOrder` — 컴파일은 되지만 새 두 값이 없다(계약 7.2.8 순서: … `stroke, pageObject, handwriting`).
- `app/test/fakes/counting_note_store.dart:24` `CountingNoteStore` — getter 4개(`recordings`·`recordingDrafts`·`handwriting`·`search`) 없음.
- SYNC 참고: `EntityKind.values`를 돌며 CORE로 인코드·디코드하는 시험(`test/model/records_test.dart:21`, `test/model/sync_doc_test.dart:69`·`:113`, `test/merge/field_merge_test.dart:479`, `test/codec/chunk_codec_test.dart:47`, `test/model/field_units_test.dart` 9·52·64·78행, `integration` `test/integration/core_json_keys_test.dart:52`)는 새 두 종류에서 `UnimplementedError('CORE T20a: …')`를 만난다(`FormatException`이 아니다 — `SyncDoc.toEntity` 주석과 다름). T20a 커밋 전에는 이 두 종류를 빼고 돌려야 한다(계약 7.6.2 R2-B7a '새 종류 디코드·키 대조 시험은 B2-β JSON 조각이 들어온 뒤').

#### 계획과 다르게 한 점 (T22)

- 계획 8.1 T25a 행은 고정 자료를 'B2-α 커밋에 함께 넣는다'고 했으나, T25a는 작업 지시대로 앞서 따로 커밋했다(`b6beece`) — 이 커밋에는 계약 표면만 있다.
- `UnknownObject(rawJson)`은 계약대로 생성자이지만, 읽기(공통 키 검사·깊은 복사·`frame` 해석)가 JSON 조각이라 T20a다. 지금은 내부 `_readUnknownParts`가 `UnimplementedError`를 던지고, 필드는 그 결과를 받는 내부 생성자가 채운다(β에서 그 함수만 채운다).
- 새 `copyWith`(스타일·객체 — T20b, 손글씨·녹음기·재생기 상태 — T21)는 계획 8.1이 '생성자·필드·`==`·enum·상수'만 실제로 둔다고 해서 본문을 비웠다. `Recording.copyWith`는 1차 멤버에 인자를 더한 것이라 실제로 동작한다.
- `Recording.toJson`·`fromJson`은 T20a까지 1차 키 그대로다(`title`을 쓰지도 읽지도 않음) — 골든 `recording.json`은 T20a에서 바뀐다(8.1 'JSON 골든' 행).
- `RecordingDraftStore.readAll`은 '읽기 빈 결과'를 따라 `UnimplementedError`가 아니라 계약의 '모르는 draftId → `StateError`'로 답한다(초안이 하나도 없으므로).
- 실제 저장소의 행 단위 쓰기(`writeEntityRow`·`deleteEntityRow`)의 새 두 종류는 표에 없는 자리라 쓰기 경로 작업 번호 T26을 달았다.
- 내부 새 파일: `lib/src/common/pending.dart`(`notYet` — 메시지 형식 'CORE <작업>: <멤버>'), `lib/src/repo/empty_v2_repositories.dart`(작업 전 저장소 4종 — 실제·가짜 공용). 둘 다 내보내지 않는다(`absent_names`).


### B2-β — R2-B2b 동작 (계획 8.1 T20a·T20b·T21·T23a·T23b, 계약 7.6.2 R2-B2 행·7.6 시험 도우미 블록)

- 바탕: B2-α `2b2e4b0` 위. 사이에 SYNC R2-B7a `99b8ead`·`5056fcb`, INFRA R2-B2i `59ed567`·`44cda79`가 들어왔다(경로 겹침 없음). 공개 시그니처는 B2-α 그대로 — `api_surface_test` v2를 바꾸지 않았다.
- 커밋(조각마다 하나, 8.1 순서):

| 조각 | 커밋 | 내용 |
|---|---|---|
| T20a JSON·골든 | `9777fde` | `ElementFrame`·`ShapeGeometry`·스타일 3종·객체 4종·`UnknownObject`(깊은 복사·meta 키·`frame` 자리·최상위 에셋 id)·`HandwritingLine/Text`(`idFor` 대조)의 `toJson`/`fromJson`, `Recording.toJson`이 `title`을 언제나 씀, `EntityJson` 새 두 갈래. 읽기는 6.2.6(모르는 `type`·아는 타입의 모르는 enum 이름 → `UnknownObject`, 필수 키 오류 → `FormatException`, 읽을 때 정규화 없음). 골든 9개 + `recording.json`. **이정표 'B2-β JSON 골든'** — SYNC가 이 해시로 키 대조(CP-S9)를 판정했다(sync.md R2-B7a '두 해시') |
| T20b 기하·변형 | `c443015` | `ElementFrame` 기하·`normalized`, `PagePoint.transformed`(시계 방향 = `Affine2.rotation`), 템플릿 6종, 스타일 `normalized`(6.2.3)·`copyWith`, 도형 `bounds`(6.2.4), `transformed` 단일 규칙·`copyTo`·`copyWithMeta`·`estimatedBytes`(6.2.5), `Stroke.transformed` 캘리그래피 각(C2-38 — 반 바퀴는 1e-9도 허용으로 키를 쓰지 않음) |
| T21 값 타입·순수 함수 | `38f3578` | `SearchText.normalize`·`normalizeMapped`·`indexTerms`·`matchQuery`(6.10.1·6.10.2, U+0130 → `i`), 내부 `search_runs`·`search_match`(판정·LIKE·FTS5 흉내)·`search_ranking`·`search_rects`(코덱·줄 묶음·비율 → pt), `sourceRevOf`·`isRecognitionInput`, `copyWith`(손글씨·녹음기·재생기 상태), `bytesByType`(실제·가짜), 로컬 이미지 형식 검사(CP-11) |
| T23a 해석기·세션 | `12ab8c4` | `CommandResolver`의 `AddObjects`·`UpdateObjects`·`RemoveElements`·`TransformElements` 객체 쪽·`ClearPage(includeObjects:)`·초안 객체(6.4.1), 히스토리 바이트, `SessionEngine` 객체 상태·`PageContentChange` id. `SessionBackend.loadStrokes` → `loadContent`·`storesPageObjects` — SQLite 저장소는 해석 전에 `UnimplementedError('CORE T27: …')`(`createNote`의 초안 객체 포함) |
| T23b 가짜 v2·가짜 오디오·픽스처·testing_web | `0798096` | 아래 'T23b' |

#### T23b — 가짜 v2 · 가짜 오디오 · 픽스처 · testing_web (6.6·6.7·6.8.3·6.8.4·6.9·6.10.6·6.14·6.17·6.18.1·4.9)

- **녹음**(`fake/fake_v2_repositories.dart` `FakeRecordings`): 6.6 검증, 같은 id는 검증보다 먼저 그 행(삭제된 행도 그대로·쓰기 없음), 휴지통 노트 허용, 제목 자르기·100룬, `startedAt` → id 순, 소유자 필터, watch(같은 값 안 냄), `audioBytesOf` 서로 다른 에셋.
- **초안**(`FakeRecordingDrafts`): 메모리 블롭 맵에 실제 키 `rd/<draftId>/<6자리>`·`rd/<draftId>/meta`. `begin`은 meta → 행(쓰기 순서를 `blobWrites`에 남김 — 공유 본문 훅), `append`는 부른 순서, 빈 조각은 `activeMs`·`updatedAt`만, 4 MiB·음수·999,999 검사. `listDrafts`는 조각과 맞춤(끊김 없는 조각 수·남는 조각 바이트), 행 없는 meta → 되살림(`activeMs 0`·`updatedAt = startedAt`, 행 다시 씀), 조각 0 초안 유지, 처음 쓸 때 행도 meta도 없는 접두사만 정리. 노트 영구 삭제 때 그 노트의 초안(행·meta의 `noteId`)도 지움.
- **손글씨**(`FakeHandwriting`): `put` 검증(6.9.4), `update` = 쓰기 큐 작업 하나 안의 읽기-`transform`-쓰기(경합 사례 1·2·4~7), `transform` 안에서 부른 저장소 쓰기는 `Zone` 표시로 `StateError`, `removeForPage` 소프트 삭제, `stalePages`(메모리 획으로 직접, 페이지 순서)·`notesWithStalePages`(정확한 답, `updatedAt` ↓ → id ↑, 휴지통·다른 소유자 제외).
- **메모리 색인**(`fake/memory_search_index.dart`, 6.10.6): 단위 id = 지금 최대 + 1(빈 목록이면 1 — rowid 규칙), 후보 = FTS5 흉내(`ftsCandidateMatches`) 또는 1글자 LIKE 경로 + 살아 있음(휴지통·삭제 페이지·`withinNote`, pdf는 그 에셋 쪽을 배경으로 쓰는 살아 있는 페이지) → id 내림차순 2,000개. 그 뒤 단계(판정·pdf 펼침·페이지 묶음·점수 순서·발췌·사각형)는 **새 내부 파일 `search/search_pipeline.dart`**(`rankSearchCandidates`·`searchHitOf`)에 두어 T33b의 실제 색인이 같은 함수를 부르게 했다. 쓰기 훅: 텍스트 상자·수식(객체 쓰기 — 세션·undo·초안·복사·원격), 손글씨(`put`·`update`·`removeForPage`·복사). pdf는 `SearchIndexWriter`(6.10.3 검증 — `ArgumentError`, 아무것도 안 바꿈, 사각형은 1/65535 정밀도로 저장). 빈 단위 목록도 소유자 유지. `rebuild`는 `rebuilding: true` → 텍스트·수식·손글씨 다시 만듦·pdf는 지우기만 → `false`·`lastRebuildAt`. `searchLibrary.pages = search(limit: 100)`.
- **노트 복사**(6.14.1): 녹음 새 id(같은 에셋·제목·시각) → 획의 `recordingId` 바꿈(없는 것은 그대로 — R-7) → 객체 `copyTo` → 손글씨(새 노트·페이지, 획 id 바꿈·복사 안 된 id 뺌, 복사된 입력 획의 `sourceRev`) → 바로 검색됨. **영구 삭제**(6.14.2): 녹음·초안·손글씨·그 노트의 색인 소유자(단위 없는 소유자 포함, pdf 소유자는 남음). 백업에 새 종류(`EntityKind.values` 순).
- **`PageObjectFixtures`**: 7.6 원문 기본값, id 생략 → `fx-<type>-<6자리>`(격리 안에서 겹치지 않음), 화살표는 끝 머리, 다각형 오각형·별 5꼭짓점, `unknown`은 공통 키 + `frame` + 중첩 `payload`.
- **`FakeAudioRecorder`**(6.8.3): 타이머·실제 시간 없음, `advance`가 1초 경계마다 16바이트 조각(녹음 중)·빈 조각(일시정지 중)을 내부 사슬로 `append`, `stop` = `finishing` → 사슬 기다림 → 0 ms면 버리고 `null` → 에셋 → `createRecording`(M-1) → 버림 → idle, 저장 실패면 초안 남김·idle + `error`·그 예외, `pendingDrafts`·`recoverDraft`(`'복구된 녹음'`)의 제외 규칙은 `store.clock` 기준 10 000 ms, `abandon`은 사슬을 기다린 뒤 메모리 상태만 버림. 상태 스트림은 구독 즉시 현재 값(비동기 전달 — 시험은 마이크로태스크 하나 기다림).
- **`FakeAudioPlayback`**(6.8.4): `open` → `loading` → `ready`, `play`(ready·paused·completed에서)·`pause`(playing에서), 위치 `[0, durationMs]`·속도 `[0.5, 2.0]`로 자름, `calls`(자르기 전 인자, `setPositionMs`는 기록 안 함, 읽기 전용 목록).
- **`testing_web.dart`**(4.9): `openWebTestNoteStore(name)` = `openNoteStore(databaseName 'webtest_<name>', 블롭 'webtest_<name>_blobs', 기본 자산 URL, requestPersistentStorage false)`, `deleteWebTestNoteStore(name)` = 그 설정의 `deleteLocalNoteData`(열려 있으면 `StateError`), 이름 `^[A-Za-z0-9_-]{1,40}$` 아니면 `ArgumentError`. `tool/prepare_web_test.dart --out <dir>`(또는 `--out=<dir>`)로 다른 패키지가 자기 `test/web`에 `sqlite3.wasm`·`drift_worker.js`를 받는다 — README에 사용법.

확인 (2026-11-06, load 2~3.5 — 같은 컨테이너에서 다른 영역 시험이 함께 돎)

| 검사 | 결과 | 시간 |
|---|---|---|
| `packages/note_core` `flutter analyze --fatal-infos` | 0건 | 3초 |
| `dart format --set-exit-if-changed lib test tool` | 변경 없음 | 1초 |
| `ws test --package note_core --platform vm` | **880개 통과**(B2-α 682 + β 198), 5개 건너뜀(perf 파일) | 55.7초 |
| `ws test --package note_core --platform chrome` | 준비 ok, **71개 통과**(B2-α 48 + β 23 — `testing_web_browser_test` 실제 웹 저장소 시나리오 포함), 1개 건너뜀(perf) | 106.1초 |
| `ws check` | R1~R16 위반 0·경고 0 | 57초 |
| `dart run tool/prepare_web_test.dart --out <임시>/test/web` | 두 파일 설치, 잘못된 인자는 사용법 오류 | — |
| 가짜를 쓰는 다른 멤버(고치지 않고 깨짐만 확인) | `feature_library` VM 626 통과, `sync_engine` VM 782 통과, `pdf_io` VM 580 통과, `app` 가짜 사용 시험 3개 파일 37 통과, `feature_editor` VM 591 통과, `ink_engine` VM 780 통과 | — |
| 루트 `dart test tool/test` | 372개 통과 | 52초 |

#### 다른 영역이 알아 둘 것 (B2-β 끝)

- `createFakeNoteStore()`의 새 저장소 4개가 동작한다. 텍스트 상자·수식·손글씨는 가짜가 스스로 색인하고, pdf는 `store.search.replaceUnits`(PDF 색인기)로 넣는다. `searchLibrary`의 `pages`가 채워진다.
- `FakeAudioRecorder`의 '최근 갱신' 판정은 `store.clock`이다 — 복구 시험은 `createFakeNoteStore(clock: Clock(() => now))`처럼 조절 가능한 시계를 넘기고 10초 넘게 옮긴다. 녹음 시계는 `advance`로만 간다.
- **실제 저장소**(`openTestNoteStore`)는 8.1 'B2 상태' 'β 끝' 열 그대로다: 객체 명령 `UnimplementedError('CORE T27: …')`(메모리 상태 불변), 녹음·초안·손글씨·색인 쓰기 `CORE T30`·`T31`·`T32`·`T33a`, 읽기는 빈 결과. 그래서 실제 메모리 CORE 위의 `FakeAudioRecorder.start`는 `CORE T31`을 던지고 idle로 돌아간다(`fake_audio_recorder_test` 마지막 사례).
- `pagesTruncated`: 살아 있는 후보가 2,000개를 **넘을 때**(2,001번째가 있을 때) 또는 페이지가 `limit`보다 많을 때 `true` — 정확히 2,000개면 `false`(공유 본문 '2,000 candidates' 사례). T33b의 실제 질의는 `LIMIT 2001`로 같은 판정을 한다.

#### 계획과 다르게 한 점 (B2-β)

- 파일 이름: 계획 3장 나무의 `fake/fake_recordings.dart`·`fake/fake_handwriting.dart` 대신 한 파일 `fake/fake_v2_repositories.dart`(녹음·초안·손글씨)에 두었다. 질의 2·3단계를 실제·가짜가 함께 쓰도록 계획 나무에 없던 내부 파일 `search/search_pipeline.dart`를 더했다(내보내지 않음 — 6.10.6 '같은 판정·같은 순서'를 코드 공유로).
- `fake_audio_recorder_test`의 '실제 메모리 CORE + `testWidgets` + `runAsync` 사례'(8.1 T23b 완료 조건): note_core는 순수 Dart 멤버라(`sdk: flutter` 없음 — R2, pubspec은 INFRA 소유) `testWidgets`를 쓸 수 없다. 그리고 실제 저장소의 초안 쓰기가 T31이라 지금은 `start`가 `CORE T31`을 내는 B2 상태를 단언한다. 정지·복구 전체 흐름(에셋이 idb_shim 타이머를 거침)은 T31이 `fake_async` + `elapse`로 이 사례를 바꾸고, `testWidgets` 모양은 6.8.3 X-4대로 EDITOR·INFRA 시험 몫이다.
- `ElementFrame` JSON 부분(오류 8종·웹 정수 입력·경계값 왕복 — 8.1 T20a)은 `element_frame_test`가 아니라 VM·Chrome 공유 본문 `test/shared/object_json_web_cases.dart`에 있다(Chrome에서도 같이 돌게).
- B2-α 가짜 시험 `test/testing/fake_store_b2_alpha_test.dart`를 지웠다(가짜가 α 상태를 벗어남). 그 안의 v1 사본 API 사례(사본 없는 저장소: 읽기 `StateError`·지우기 아무것도 안 함)는 `fake_store_v2_test`로 옮겼다. `test/shared/b2_alpha_store_cases.dart`는 실제 저장소에만 돈다.
- 초안 저장소의 고아 정리는 가짜를 다시 열 수 없어 공유 본문으로는 보이지 않는다 — 가짜 전용 사례(처음 쓰기 전에 남겨 둔 블롭)를 `recording_draft_contract_fake_test`에 더했다. 공유 본문은 `reopen()` 훅이 있는 실제 저장소(T31)에서 정리까지 본다.
- 6.18.1 ②(V7 고정 자료를 `test/web/fixtures_v1/`로 복사·`.gitignore`)는 T23b 행에 없어 T25b(고정 자료 Chrome 시험)로 둔다 — 'T25b가 알아 둘 것'과 같다.

### 동시 개발

2차 동시 개발 단계(M5·M6·M7). 작업 트리 `/home/user/wt2/core`(`area2/core`), 바탕 `5843ec3`(총괄 계약 v2.3 커밋 — 기반 단계 R2-B1~B8 전부 들어감). 할 일은 계획 8.2 표(선행 순서 T24 → T26 → (T27, T28, T30, T31, T32) → T33a → T33b → T34 → T29 → T36 → T37, T35는 언제든·T25b 전).

#### 작업 표 (동시 개발)

| ID | 상태 | 커밋 | 완료 조건 시험 파일 |
|---|---|---|---|
| T25a | 기반 단계에서 완료 | b6beece | `test/migration/v1_fixture_files_test.dart` |
| T22 | 기반 단계에서 완료 | 2b2e4b0 | `test/api_surface_test.dart` v2 외 — 위 '작업 표 (2차)' |
| T20a·T20b·T21·T23a·T23b | 기반 단계에서 완료 | 9777fde·c443015·38f3578·12ab8c4·0798096 | 위 '작업 표 (2차)' |
| T24 | 완료 | a2b0489 | `test/storage/schema_v2_test.dart`(1차 `schema_test.dart`를 대신함), `test/storage/generated_migrations/note_db/migration_test.dart`, `test/storage/migration_v2_test.dart`, `test/storage/v1_copy_test.dart`, `test/storage/canonical_dump_test.dart`, `test/web/canonical_dump_browser_test.dart`, `test/web/v1_copy_browser_test.dart`, `test/common/text_normalize_test.dart`, `test/storage/open_errors_test.dart` |
| T35 | 남음 | | `test/assets/file_blob_store_test.dart`, `test/storage/native_file_store_test.dart` |
| T25b | 남음 | | `test/migration/v1_fixture_migration_test.dart`, `test/web/v1_fixture_migration_browser_test.dart`, `test/perf/migration_perf_test.dart` |
| T26 | 완료 | 3bfff8a | `test/storage/row_mappers_v2_test.dart`, `test/storage/outbox_v2_test.dart`, `test/storage/change_bus_v2_test.dart`, 1차 `test/storage/field_version_writer_test.dart`(모든 종류 왕복) |
| T27 | 완료 | 2db774e | `test/session/object_session_contract_real_test.dart`(공유 본문 7 + N-7), `test/session/note_session_objects_test.dart`, `test/edit/undo_objects_test.dart`, `test/session/content_reader_test.dart`(+ objects) |
| T28 | 완료 | 3d49685 | `test/sync/sync_store_v2_test.dart`, `test/sync/field_lww_convergence_v2_test.dart`, `test/sync/unknown_object_roundtrip_test.dart` |
| T30 | 완료 | 3b5adfa | `test/repo/recording_contract_real_test.dart`(공유 본문 — 가짜와 같은 6건), `test/repo/recording_repository_test.dart` |
| T31 | 완료 | 2d8dd0a | `test/media/recording_draft_contract_real_test.dart`(공유 본문 9 — 파일 DB + 메모리 IndexedDB, 다시 열기 포함), `test/media/recording_draft_store_test.dart`(12), `test/web/recording_draft_browser_test.dart`(4), `test/perf/draft_append_perf_test.dart`(PF-7), `test/testing/fake_audio_recorder_test.dart`(실제 메모리 CORE 흐름) |
| T32 | 완료 | (이 커밋) | `test/repo/handwriting_contract_real_test.dart`(공유 본문 13 + 경합 사례 3 두 건), `test/repo/handwriting_repository_test.dart`(16), `test/perf/stale_pages_perf_test.dart`(PF-6·PF-11), `test/web/handwriting_browser_test.dart`(공유 본문 13 — 실제 웹 저장소), 공유 본문에 1건 더함(같은 값 다시 쓰기 → 쓰기 없음·`createdAt` 유지 — 가짜도) |
| T33a | 남음 | | `test/search/search_index_writer_test.dart`, `test/web/search_fts_browser_test.dart`(쓰기) |
| T33b | 남음 | | `test/search/search_contract_real_test.dart`, `test/search/search_index_test.dart`, `test/search/fts_candidate_equivalence_test.dart`, `test/web/search_fts_browser_test.dart`, `test/perf/search_perf_test.dart`, `test/perf/search_real_shape_perf_test.dart`, `test/web/search_reopen_time_browser_test.dart` |
| T34 | 남음 | | `test/repo/library_search_v2_test.dart`, 1차 `library_contract` |
| T29 | 남음 | | `test/repo/note_copy_v2_test.dart`, `test/repo/trash_purge_v2_test.dart`, `test/backup/backup_export_test.dart`·`test/testing/fake_backup_export_test.dart`·`test/web/backup_export_browser_test.dart` |
| T36 | 남음 | | `test/providers/providers_fake_test.dart`·`providers_real_test.dart`(`test/shared/providers_contract.dart` v2) |
| T37 | 남음 | | `-t perf` PF-1~PF-11, Chrome `perf`, `test/readme_examples_test.dart` v2 |
| I-1~I-7 | 통합 단계 | | 계획 8.3 |

#### 00-review '최종 승인' CORE 항목 처리

| ID | 처리 |
|---|---|
| CORE-F1 | B2-α `2b2e4b0`에 `dev_tools.dart` 선언(본문 `null`·`StateError`·아무것도 안 함, 실제 저장소는 `CORE T24`). 동작·`v1_copy_test`·`v1_copy_browser_test`·첫날 Chrome 확인(웹 정규 덤프 사본 만들기·해시·지우기·다시 열기 시간)은 T24 |
| CORE-F2 | 완료 — T25a `b6beece`(manifest에 `fullDumpSha256`·`entityDumpSha256`) |
| CORE-F3 | 완료 — B2-α `2b2e4b0`의 `Recording.durationMs` R-3 주석이 C22-04 문장 |
| CORE-F4 | 유지 — 다시 연 세션 히스토리 비어 있음(C15-04)은 1차 동작 그대로. T27: 실제 저장소 객체 세션도 같은 성질 — `note_session_objects_test` 'a reopened session … its history is empty (C15-04)' |
| C22-09 | 계획서 상태 줄 '승인 · 계약 v2.3', 12.1 CP-16·17 판정 열(C22-02·C22-01), 5.8 표를 실제 타입·커밋으로(2026-11-06) |

#### 변경 요청 (동시 개발)

- 다른 영역이 기반 단계에서 CORE에 보낸 변경 요청: 없음(`/home/user/wt2/notes/*.md`에서 `[CORE]` 검색 — 2026-11-06).
- 보낸 것: 없음.

#### 의존성 요청 (동시 개발)

- 없음.

#### T24 — DB 스키마 v2 · 마이그레이션 · v1 사본 · 정규 덤프 (계획 6.10.1·6.11·6.12·8.2, 계약 7.2.7 C22-01·C22-02)

- **스키마**(`storage/db/tables.dart`): 새 테이블 5개(`page_objects`·`handwriting`·`recording_drafts`·`search_owners`·`search_units` — 행 클래스 `PageObjectRow`·`HandwritingRow`·`RecordingDraftRow`·`SearchOwnerRow`·`SearchUnitRow`), `pages` + `ink_rev`·`ink_rev_at`·`bg_asset_id`·`bg_pdf_index`, `recordings` + `title`(새 열은 열 목록 **끝** — `ALTER TABLE ADD COLUMN`과 같은 자리), 색인 9개 + `idx_recordings_note`·`idx_pages_bg`, `recording_drafts.recording_id` UNIQUE, `search_units` UNIQUE(`source`,`owner_key`,`seq`)·`id` = rowid(AUTOINCREMENT 없음 — 'max + 1'). FTS5 `search_fts`는 drift 밖(`kSearchFtsCreateSql` — 6.11 1안): `onCreate`·업그레이드 3단계에서 `customStatement`. 새 DB도 kv `search.normalizerVersion = '1'`을 쓴다. `kDatabaseSchemaVersion = 2`.
- **생성물**: `dart run build_runner build` → `dart run drift_dev make-migrations` — `drift_schemas/note_db/drift_schema_v2.json`, `lib/src/storage/db/note_database.steps.dart`, `test/storage/generated_migrations/note_db/{generated/schema.dart,schema_v1.dart,schema_v2.dart,migration_test.dart}`.
- **업그레이드**(`storage/db/migrations.dart` `kSchemaSteps = {1: upgradeV1ToV2}`): 0단계(사본)는 `NoteDatabase.onUpgrade`에서 `runSchemaUpgrade` **앞**(트랜잭션 밖), 1~6단계는 한 트랜잭션 안 — 생성 `migrationSteps(from1To2:)`로 1·2단계(`Schema2`의 테이블·열·색인), 3 FTS, 4 `bg_*`(`json_extract`, pdf·image만), 5 `name_norm`·`title_norm`을 `SearchText.normalize`로 **달라진 행만** UPDATE, 6 kv `search.normalizerVersion`·`db.v1Copy`.
- **v1 사본**(`storage/v1_copy/` — 6.12.4): 저장 방식은 `StorageInfo.backend`로 고른다(네이티브 파일 → `VACUUM INTO '<path>-v1-backup.tmp'` → 이름 바꾸기, 웹(메모리 제외) → 블롭 저장소 `db/v1-backup/<6자리>` 4 MiB 조각 + **마지막에** `db/v1-backup/meta`, 메모리 → 없음). 실패하면 쓴 것을 지우고 실패 기록(`{failed: quota|io|other, at, method, normalOpens}` — 분류는 오류 문자열로, 백그라운드 isolate·웹 워커를 거친 오류는 타입이 없음)을 남기고 이주는 진행. 열기가 오류 없이 끝날 때마다 `normalOpens + 1`(업그레이드한 열기 포함 → 1), `normalOpens ≥ 5` **이고** 7일 지난 첫 열기에서 바이트 → kv 순으로 지움. `deleteLocalNoteData`(네이티브)가 사본·`.tmp`도 지운다(웹은 블롭 DB째 지움 — 1차 그대로). `dev_tools.dart` 함수 4개가 실제로 동작(`fileName` `noteapp-v1-backup.sqlite` | `.sql.txt`, 실패 기록만 있으면 `readV1DatabaseCopy`는 `StateError`).
- **정규 덤프**(`storage/db/canonical_dump.dart`): `tool/src/v1_dump.dart`와 같은 바이트(V7 고정 자료에서 `fullDumpSha256`·`entityDumpSha256` 그대로). 첫 열이 NOT NULL 단일 기본 키인 표는 `quote(pk) || ','` 키로 2,000행씩 읽는다(그 키는 겹치지 않고 서로의 접두사가 아니라 줄 전체 순서와 같다 — 안쪽 질의는 키만 비교, 바깥 질의는 그 쪽의 줄만 만든다). 그 밖의 표는 한 번에. 4 MiB 조각 스트림.
- **정규화 위임**(6.10.1, 검토 S-16): `normalizeForSearch` = `SearchText.normalize`(실제·가짜 저장소의 `name_norm`·`title_norm`·제목 질의).

확인 (2026-11-06, load 6~9 — 다른 영역 시험이 함께 돎)

| 검사 | 결과 | 시간 |
|---|---|---|
| **첫날** `flutter analyze --fatal-infos`(`note_database.steps.dart` 포함) | 0건 — 생성 머리말 `ignore_for_file: type=lint` | 7초 |
| **첫날** FTS 1안 `SchemaVerifier`(`generated_migrations/note_db/migration_test.dart` — `migrateAndValidate` 1 → 2, 자료 보존 사례) | 통과(스키마 밖 `search_fts`는 검사하지 않음) | 1초 |
| **첫날** Chrome 웹 사본(`v1_copy_browser_test` — 합성 v1 + 획 2,000개 randomblob(257), 덤프 1,423,335 B) | 만들기·해시(meta sha256 = 브라우저 안 덤프)·읽기·지우기 동작. 업그레이드 열기(사본 포함) 1,856~2,466 ms, 사본 있는 다시 열기 250~268 ms, 지우기 14~21 ms, 지운 뒤 다시 열기 182~272 ms(두 번 실행). 같은 DB의 덤프만 279 ms(2,000행 쪽)·223 ms(한 번에) | — |
| `packages/note_core` `flutter analyze --fatal-infos` | 0건 | 4초 |
| `dart format --set-exit-if-changed lib test tool` | 변경 없음 | 1초 |
| `flutter test`(VM) | **915개 통과**, 5개 건너뜀(perf 파일) | 98~113초 |
| `ws test --package note_core --platform chrome` | 준비 ok, **74개 통과**(71 + `canonical_dump_browser_test` 1 + `v1_copy_browser_test` 2), 1개 건너뜀(perf) | 156.1초 |
| `ws check` | R1~R16 위반 0·경고 0 | 69초 |
| 루트 `flutter analyze --fatal-infos` | 0건 | 12초 |
| 다른 멤버(고치지 않고 확인 — 가짜의 정규화 위임·v2 DB) | `ws test --package feature_library --platform vm` 628 통과, `sync_engine` VM 782 통과(통합 태그는 기본 skip) | 334초·154초 |
| 세션 끝 다시 돌림(커밋 `409c4f2` 뒤) | `ws check` 0, `ws test --package note_core --platform chrome` 74 통과 | 214초 |

#### T26 — 행 변환 · 쓰기 경로 (계획 6.11·6.13·8.2, C2-13)

- **행 변환**(`storage/row_mappers.dart`): `page_objects` — `note_id`는 비정규화(획과 같은 `strokeNoteId` 인자 — 원격 고아는 `''`), `type` 열, `min_x…max_y` = `bounds`, `data_json` = `toJson()`에서 **열이 따로 있는 키**(`kObjectColumnKeys` = `id`·`pageId`·`type`·`createdAt`·`updatedAt`·`deletedAt`·`version`)를 뺀 것(`toJson` 순서 그대로 — `frame`·종류별 키·`UnknownObject`의 모르는 키), `asset_id` = `referencedAssets`(이미지, 최상위 `assetId`가 AssetId인 `UnknownObject`). 읽기는 열 키 + `data_json`을 `PageObject.fromJson`으로(`UnknownObject`는 키·값·순서까지 돌아온다). `handwriting` — `lines_json` = `lines[i].toJson()` 배열. `recordings.title` 쓰기·읽기(업데이트 때 NULL로 지우기 포함). `pages`의 `bg_asset_id`·`bg_pdf_index`는 **쓰기마다** 배경에서 파생(`backgroundColumns` — 업그레이드 4단계와 같은 규칙, `keepLocal`과 상관없음), `ink_rev`·`ink_rev_at`은 엔티티 쓰기가 건드리지 않는다(새 행 NULL, 업데이트는 유지 — 6.9.3 캐시는 T32가 쓴다). `deleteEntityRow`·`readVersionedRow`·`readVersionedPage`(백업 키셋 페이지)와 `DriftSyncStore._readKind`(`readVersioned`)에 두 종류.
- **힌트**(`WriteTxn._hints`): `PageObject` → `noteId = noteIdOfPage(pageId)`, `pageId`; `HandwritingText` → 그대로 — 둘 다 항상(outbox·`EntityChange`, 로컬·원격·`commitRepairs`·`WriteMerged`).
- **원격 고아 객체**: `putRemote`가 페이지 행이 없는 객체를 `note_id = ''`로 저장하고 그 커밋에는 내지 않는다. `_adoptOrphans`(페이지가 오는 `putRemote`)가 획과 함께 객체의 `note_id`·outbox `noteId`를 채우고 `EntityChange`를 그 커밋 batch에 넣는다(같은 `applyRemote` 호출 안에서 객체가 먼저 와도 batch 하나).
- 남긴 것(T28): `_RemoteWriter.write`의 객체·손글씨 경우(쓰인 기존 페이지 `content_rev + 1`, 영향 노트 `refreshNoteDerived`), 색인 훅. 지금은 원격 객체가 행·힌트·고아 입양만 되고 페이지 `content_rev`는 오르지 않는다.

확인 (2026-11-06, 다른 영역 시험이 함께 돎)

| 검사 | 결과 | 시간 |
|---|---|---|
| `packages/note_core` `flutter analyze --fatal-infos` | 0건 | 3초 |
| `dart format --set-exit-if-changed lib test tool` | 변경 없음 | 2초 |
| `ws test --package note_core --platform vm` | **939개 통과**(915 + 새 24), 5개 건너뜀(perf) | 81초 |
| `ws test --package note_core --platform chrome` | 준비 ok, **74개 통과**(바뀐 시험 없음 — 행 변환이 웹에서도 컴파일·동작), 1개 건너뜀(perf). 첫 시도는 부하로 시간 초과, 두 번째 시도 통과(ws 자동 재시도) | 1,026초(잠금 대기 포함) |

#### T28 — 동기화 창구 v2 (계획 6.13·8.2)

- `_RemoteWriter.write`(원격 적용·`commitRepairs` 공용)에 두 종류: **객체**는 획과 같다 — 쓰인 페이지(옮겨졌으면 옛 페이지도)를 `written`에, 그 노트를 영향 노트로(`updatedAt = max(현재, 객체 updatedAt)`). **손글씨 결과**는 쓰인 페이지를 `written`에(작업 끝 `content_rev + 1` 한 번 — 썸네일·`ink_rev` 캐시), 노트는 영향 노트(`affectedNoteIds`·`page_count` 재계산)지만 `updatedAt`은 옮기지 않는다(파생 기록 — 로컬 `put`(6.9.4)과 같게, 다른 기기의 인식 결과가 라이브러리 '최근' 순서를 바꾸지 않게). 고아(페이지 행 없음)는 올릴 페이지·영향 노트가 없다. 새로 만든 페이지는 1차처럼 0에서 시작.
- `pendingChanges`·`acknowledge`·`readVersioned`(`_readKind`는 T26)·정책 호출(`local`·`pending`)·`KeepLocal`·`TakeRemote(dropPendingLocal)`·`WriteMerged`·`commitRepairs`(필드만 새 HLC, 없는 행은 `{*}`)는 종류에 무관한 1차 코드가 그대로 돈다 — 시험으로 확인.
- 색인 훅(원격 텍스트 상자·수식·손글씨 → 검색 단위)은 T33a(쓰기 훅을 한 곳에 둔다).
- 수렴(`field_lww_convergence_v2_test`): 두 저장소의 로컬 편집은 쓰기 큐 `putLocal`(바뀐 키)로 낸다 — 실제 저장소의 객체 명령은 T27, 녹음·손글씨 저장소는 T30·T32. 객체 다른 키 동시 편집(키마다 새 값), 같은 키(나중 것), 삭제 대 수정(둘 다 삭제 + 새 텍스트), 녹음 `title` 대 삭제, 손글씨 `lines`·`engineId`·`sourceRev` — 다섯 경우 모두 JSON·필드 버전 같음, outbox 빔.

확인 (2026-11-06)

| 검사 | 결과 | 시간 |
|---|---|---|
| `packages/note_core` `flutter analyze --fatal-infos` | 0건 | 2초 |
| `dart format --set-exit-if-changed lib test tool` | 변경 없음 | 2초 |
| `ws test --package note_core --platform vm` | 첫 실행 1개 실패(부하 — 출력을 남기지 못함), 다시 돌려 **960개 통과**(939 + 새 21), 5개 건너뜀(perf). `test/sync`·`test/storage` 두 번 더 돌려 195개 모두 통과 | 75~96초 |
| `ws test --package note_core --platform chrome` | 준비 ok, **74개 통과**, 1개 건너뜀(perf) | 226초 |

#### T30 — 녹음 저장소 (계획 6.6·8.2, 계약 7.2.4)

- `storage/drift_recording_repository.dart` `DriftRecordingRepository` — `DriftNoteStore.recordings`(B2의 `EmptyRecordingRepository`는 지웠다). 쓰기는 큐 작업 하나(`putLocal`): 새 행 `{*}`(`createdAt = updatedAt = now`, `isNew`), `renameRecording` `{title, updatedAt}` → outbox `{title}`(같은 값이면 쓰지 않음), `deleteRecording` `{deletedAt, updatedAt}` → `{deletedAt}`(이미 삭제면 아무것도 안 함). outbox·`EntityChange` 힌트 `noteId`(1차 `_hints`).
- `createRecording`(CP-7 멱등): 같은 id의 행이 있으면 **검증보다 먼저** 그 행을 그대로(삭제된 행도 — 되살리지 않음, 쓰기·`ChangeBatch` 없음). 인자가 저장된 행과 다르면(`noteId`·`assetId`·`durationMs`·`startedAt`) `@visibleForTesting`이 아닌 내부 계수 `debugIdempotentMismatches`만 올린다 — note_core에 개발 로그 창구가 없어서다(6.6 '개발 로그'). 검증 순서: id → 노트 행(휴지통 허용, 영구 삭제 = 행 없음 → `EntityNotFoundException`) → 에셋 행·`type == audio`(M-1) → `durationMs ≥ 0` → 제목(앞뒤 공백 자름, 빈 값 null, 룬 100자 초과 `ArgumentError`).
- 읽기: `recordingsOf`·`watchRecordings` = 노트 소유자가 현재 소유자일 때만, 활성 행 `startedAt` → id(`idx_recordings_note`). watch는 `WatchHub`(녹음·노트 커밋마다 다시 읽고 같은 값이면 내지 않음 — 노트 이름 바꾸기·다른 노트 녹음은 내지 않음). 원격으로 온 녹음(1차 경로)도 같은 목록·watch. `getRecording`은 삭제된 것도. `audioBytesOf` = 활성 녹음의 **서로 다른** 에셋 행 `size` 합(바이트가 이 기기에 없어도).
- 삭제는 획의 `recordingId`·`recordingOffsetMs`를 건드리지 않는다(R-7), 에셋 바이트는 남는다(U13). 히스토리 밖(R-8).
- `test/shared/b2_alpha_store_cases.dart`의 `tasks.recordings`를 null 허용으로(실제 저장소는 T30부터 녹음 묶음을 건너뜀).

확인 (2026-11-06)

| 검사 | 결과 | 시간 |
|---|---|---|
| `packages/note_core` `flutter analyze --fatal-infos` | 0건 | 3초 |
| `dart format --set-exit-if-changed lib test tool` | 변경 없음 | 2초 |
| `ws test --package note_core --platform vm` | **973개 통과**(960 + 공유 본문 6 + 저장소 9 − B2 녹음 묶음 2), 5개 건너뜀(perf) | 122초 |
| `ws test --package note_core --platform chrome` | 준비 ok, **74개 통과**, 1개 건너뜀(perf) | 235초 |
| `ws check` | R1~R16 위반 0·경고 0 | 192초 |
| 루트 `flutter analyze --fatal-infos` | 0건 | 13초 |
| 다른 멤버(고치지 않고 확인 — 실제 CORE v2 행·창구) | `ws test --package sync_engine --platform vm` 782 통과(통합 태그는 기본 skip) | 105초 |

#### T27 — 세션·내용 읽기 DB (계획 6.4·6.5·8.2)

- **읽기**(`storage/drift_sessions.dart` `readActiveContent`): 페이지의 활성 `strokes`·`page_objects`를 **한 읽기 트랜잭션**에서(두 읽기 사이에 원격 커밋이 끼지 않게), 둘 다 `Stroke.compareOrder`. 세션 `loadContent`(쓰기 큐 flush 뒤 — 1차 T10)와 `DriftContentReader.loadPage`(`objects` 채움 — PDF 내보내기·썸네일)가 같이 쓴다.
- **쓰기**: 세션 쓰기는 1차 경로 그대로(`putLocal(strokeNoteId: _noteId)`가 객체 행 `note_id`에도 — T26), 큐 바이트에 `PageObject.estimatedBytes`를 더했다. `SessionBackend.storesPageObjects`와 엔진의 B2 가드(`notYet('T27', …)` 두 곳, `_writesObjects`)는 지웠다 — 가짜·실제 둘 다 객체를 저장한다.
- **`createNote(PageDraft.objects)`**(`drift_library_repository.dart`): 쓰기 전에 초안마다 객체 ≤ 2,000·`checkObjectLimits`(`ArgumentError` — 노트가 생기지 않음), 객체마다 `copyTo(새 id, 새 페이지, 원래 createdAt)` → `normalizedObject` → `updatedAt = now`, `{*}`·`isNew`·`strokeNoteId: noteId`(InsertPages·가짜 `insertDraftPages`와 같은 규칙).
- **N-7**(`DriftSessions.committed`): 원격 커밋의 `pageObject` 변경(힌트 `pageId` 항상 — T26)을 획처럼 모아, 로드된 페이지의 것이고 큐에 남은 세션 쓰기가 없으면 `page_objects` 행을 다시 읽어 `remoteCommitted(objects:)`로 넘긴다. 객체가 쓰인 페이지는 `contentPages`(로드 안 된 페이지도 `contentRevision + 1`). DB의 `content_rev + 1`은 T28의 원격 작성기(`applyRemote`) 몫 — 저수준 `tx.putRemote`만 쓰면 오르지 않는다.
- `test/shared/b2_alpha_store_cases.dart`: '객체 명령이 `CORE T27`을 던짐' 시험과 `tasks.objects`를 지우고, 같은 묶음의 획 쪽 시험 3개(`RemoveElements`·`ClearPage(includeObjects:)`·`PageDraft.copyOf`)는 'the stroke part of the 2nd-round commands (v1.4)' 묶음으로 남겼다.
- `test/edit/undo_support.dart` `UndoFixture.open(objects:)`: 객체는 세션 `AddObjects` + `clearHistory()`로 넣는다(초안 객체는 새 id를 받아 시험이 id로 가리킬 수 없다).

확인 (2026-11-06)

| 검사 | 결과 | 시간 |
|---|---|---|
| `packages/note_core` `flutter analyze --fatal-infos` | 0건 | 2초 |
| `dart format --set-exit-if-changed lib test tool` | 변경 없음 | 1초 |
| `ws test --package note_core --platform vm` | **998개 통과**(973 + 객체 계약 실제 8 + 세션 객체 12 + undo 5 + 내용 읽기 1 − B2 객체 시험 1), 5개 건너뜀(perf) | 83초 |
| `ws test --package note_core --platform chrome` | 준비 ok, **74개 통과**(바뀐 웹 시험 없음 — 한 읽기 트랜잭션·객체 행 읽기가 웹 워커에서도 컴파일·동작), 1개 건너뜀(perf) | 123초 |

#### T31 — 녹음 초안 저장소 (계획 6.7·8.2, 계약 7.2.4)

- `storage/drift_recording_draft_store.dart` `DriftRecordingDraftStore` — `DriftNoteStore.recordingDrafts`(B2의 `EmptyRecordingDraftStore`는 지웠다). 블롭은 에셋과 같은 저장소(`assetChunks ?? blobs.chunks` — 웹 IndexedDB, VM은 메모리 IndexedDB, 네이티브 파일 블롭은 T35), 키 `rd/<draftId>/<6자리>`·`rd/<draftId>/meta`(UTF-8 JSON `{v:1, recordingId, noteId, mimeType, startedAt}`). 행 `recording_drafts`는 쓰기 큐 작업으로 직접 쓴다(`putLocal` 아님 — 버전·outbox·`ChangeBatch`·백업 없음).
- `begin`: 검증(`ArgumentError`) → 첫 사용 정리 → 같은 `recordingId`의 행 **또는 행 없는 meta**가 있으면 `StateError` → ① meta `put`(기다림) → ② 큐 작업에서 같은 `recordingId` 행을 다시 보고(경합) 행 삽입 → 커밋 뒤 초안(`updatedAt = tx.now`). ②가 `StateError`면 ①의 meta를 지운다(나중에 meta로 되살아나지 않게).
- `append`: 초안마다 Future 사슬(부른 순서), 조각은 **부를 때 복사**. 사슬 안에서 행 또는 meta 확인(없으면 `StateError`) → 4 MiB·`activeMs` 검사(`ArgumentError`) → 번호(`_next` — 처음엔 블롭 키에서 0부터 끊김 없는 수) → ① 조각 `put` → ② 큐 작업(행이 없으면 `StateError` — 다른 곳에서 버림)으로 `chunk_count`·`bytes`·`active_ms`·`updated_at`. Future는 ② 커밋 뒤(재시도 중 미완료). 빈 조각은 ①을 건너뛴다. 999,999 넘으면 `ArgumentError`.
- `listDrafts`: 정리 → 진행 중 사슬·큐 flush → 행마다 블롭 키로 맞춤(끊김 없는 조각 수, 행보다 많은 조각의 길이 더함, 적으면 조각 길이 합) → 행 없는 meta 접두사는 meta로 되살려(`activeMs 0`, `updatedAt = startedAt`) 큐 작업으로 행을 다시 쓴다(그 사이 같은 id·`recordingId` 행이 생겼으면 건너뜀 — UNIQUE 충돌로 큐가 재시도에 갇히지 않게) → `startedAt`, `draftId` 순.
- `readAll`: 그 초안의 사슬·큐를 기다린 뒤, 결과 한 벌 + 조각 하나(M-4) — 행의 `chunkCount`가 조각 수와 같으면 행 `bytes`로 버퍼를 잡고, 다르면 길이를 먼저 읽는다. `discard`: 사슬 기다림 → (없으면 아무것도 안 함) ① `deletePrefix` ② 큐 작업으로 행 삭제.
- 첫 사용 정리: `rd/` 키 전부와 행 id를 보고 **행도 meta도 없는** 접두사만 지운다(실패하면 다음에 다시).
- 시험 이음새: `@visibleForTesting debugWriteOrder`(블롭 키 `put`과 `row:<id>`를 일어난 순서로 — 가짜의 `blobWrites`와 같은 형식).
- `test/testing/fake_audio_recorder_test.dart`의 'start waits for CORE T31'을 실제 메모리 CORE에서 `stop`(에셋 → 녹음, 초안 없어짐)·`abandon` → 10초 뒤 `pendingDrafts` → `recoverDraft` 흐름으로 바꿨다(시험 파일 머리말이 T31에 바꾸라고 적어 둔 것).
- `test/shared/b2_alpha_store_cases.dart` `tasks.drafts`를 null 허용으로(실제 저장소는 초안 묶음을 건너뜀).

확인 (2026-11-06)

| 검사 | 결과 | 시간 |
|---|---|---|
| `packages/note_core` `flutter analyze --fatal-infos` | 0건 | 4초 |
| `dart format --set-exit-if-changed lib test tool` | 변경 없음 | 1초 |
| `ws test --package note_core --platform vm` | **1,017개 통과**(998 + 계약 실제 9 + 저장소 12 − B2 초안 묶음 2), 6개 건너뜀(perf — PF-7 더함). 첫 실행은 `fake_audio_recorder_test`의 B2 상태 시험이 실패(기대대로 — 위처럼 바꿈) | 125초 |
| PF-7 VM(`flutter test --run-skipped -t perf test/perf/draft_append_perf_test.dart`) | 중앙값 **5.83 ms**(예산 ≤ 10 ms) — 파일 DB + 메모리 IndexedDB 블롭(네이티브 파일 블롭은 T35 뒤 다시 잼) | 1초 |
| `ws test --package note_core --platform chrome` | 준비 ok, **78개 통과**(74 + `recording_draft_browser_test` 4), 1개 건너뜀(perf) | 207초 |
| Chrome 기록(`recording_draft_browser_test` — 실제 웹 저장소, 다른 영역 시험이 함께 돎) | PF-7 Chrome `append` 8 KiB 중앙값 **10.70 ms**(기록 — ≤ 30 ms). 30분 분량(1,800 × 8 KiB = 14,745,600 B): 조각 쓰기 2,785 ms, `readAll` **1,601 ms**, `AssetStore.put` **142 ms**; `usedJSHeapSize` 299.2 → `readAll` 뒤 332.1 → `put` 뒤 347.0 MB(+33 MB ≈ 결과 한 벌 14 MB + GC 전 조각들 — M-4 '한 벌' 범위) | — |
| `ws check` | R1~R16 위반 0·경고 0 | 96초 |
| 루트 `flutter analyze --fatal-infos` | 0건 | 26초 |

#### T32 — 손글씨 저장소 · `pages.ink_rev` 캐시 (계획 6.9·8.2, 계약 7.2.5)

- `storage/drift_handwriting_repository.dart` `DriftHandwritingRepository` — `DriftNoteStore.handwriting`(B2의 `EmptyHandwritingRepository`는 지웠다 — `empty_v2_repositories.dart`에는 `EmptySearchIndex`(T33a)만 남음).
- 쓰기는 모두 쓰기 큐 작업(`putLocal`): 새 행 `{*}`, 있으면 바뀐 JSON 키만(`changedJsonKeys` — 삭제됐던 행은 `deletedAt`이 풀려 되살아남), `removeForPage`는 `{deletedAt}`. 있던 행의 `createdAt`은 유지, `updatedAt` = 트랜잭션 시각. 활성 행과 동기 키가 하나도 다르지 않으면 쓰지 않고(ChangeBatch·outbox·버전 없음) 저장된 값을 돌려준다 — 가짜도 같게 고쳤다(공유 본문 새 사례).
- 검증(6.9.4): 페이지 행 없음 → `EntityNotFoundException`(삭제된 페이지 행은 허용), 노트 불일치·후보 > 5·빈 `languageTag` → `ArgumentError`, `update`는 결과의 `pageId` 불일치도 `ArgumentError`.
- `update`: 큐 작업 하나(= 한 쓰기 트랜잭션) 안에서 행 읽기 → `transform`(동기, transform 존) → 검증·쓰기. `transform`이 던진 예외는 **작업의 결과로 돌려 받아**(그때까지 쓴 것 없음) 호출자에게 다시 던진다 — `FormatException` 같은 비도메인 예외가 큐의 커밋 재시도(저장 실패 취급)로 가지 않게. 같은 커밋의 다른 작업은 그대로 커밋된다(`handwriting_repository_test`).
- transform 안 쓰기 금지: `common/write_guard.dart`(`kInTransformZoneKey`·`inUpdateTransform`·`runUpdateTransform` — 가짜에서 옮김)를 `WriteQueue.run`이 본다 → 실제 저장소의 모든 큐 쓰기가 transform 존에서 `StateError`로 바로 실패(가짜는 `FakeNoteStore.write`). 큐를 거치기 전에 블롭부터 쓰는 API(`assets.put`·초안 `append`의 ①)는 블롭 쓰기 뒤 큐에서 실패한다.
- `stalePages`·`notesWithStalePages`(6.9.3): `refresh`는 `ink_rev`가 있고 `ink_rev_at = content_rev`인 페이지는 캐시를 믿고, 나머지만 50쪽씩 **SQL에서 입력 획을 이어 붙여**(`group_concat(id || ':' || updated_at || ';', '' ORDER BY id)`, 도구 highlighter·tape·laser 제외 — 페이지당 한 행만 Dart로) `sourceRevOfJoined`(SHA-256)로 해시한다. 캐시 쓰기는 다시 계산한 페이지 전부를 **큐 작업 하나**로(50행씩 `UPDATE pages … FROM (VALUES …) WHERE content_rev = 읽은 값` — 그 사이 내용이 바뀐 페이지는 쓰지 않음, outbox·ChangeBatch·touch 없음), 호출이 끝나기 전에 기다린다. `notesWithStalePages`는 ① 낡은 캐시 페이지(소유자의 활성 노트·활성 페이지) → `refresh` → ② 한 질의(`EXISTS` + `LEFT JOIN handwriting ON id = 'hw_' || page_id`) — `updated_at ↓, id ↑`.
- 해시 이음새: `common/source_rev.dart`(`sourceRevOfPairs`·`sourceRevOfJoined`·`kEmptySourceRev`) — `HandwritingText.sourceRevOf`가 위임. 엔티티 id는 ASCII(`isValidEntityId`)라 SQLite BINARY 순서 = `String.compareTo` 순서(혼합 id 시험).
- 시험 이음새: `@visibleForTesting debugInkRefreshedPages`(획 행을 다시 읽은 페이지 수).
- 색인(ink 단위 다시 색인 — 6.10.3)은 T33a 몫: `put`·`update`·`removeForPage`·원격 `putRemote` 훅에 넣는다.

확인 (2026-11-06)

| 검사 | 결과 | 시간 |
|---|---|---|
| `packages/note_core` `flutter analyze --fatal-infos` | 0건 | 2초 |
| `dart format --set-exit-if-changed lib test tool` | 변경 없음 | 1초 |
| `ws test --package note_core --platform vm` | **1,047개 통과**, 7개 건너뜀(perf) | 102초 |
| PF-6·PF-11 VM(`flutter test --run-skipped -t perf test/perf/stale_pages_perf_test.dart`, load 8) | PF-6 첫 `stalePages` **50.2 ms**(≤ 150), 캐시 최신 1.3 ms, 바뀐 페이지 1개 중앙값 **4.7 ms**(≤ 10). PF-11(5,000쪽·획 10만, DB 163 MiB) 첫 따라잡기 **390 ms**(≤ 1.5 s), 그 뒤 `notesWithStalePages` 중앙값 **1.0 ms**(≤ 30) — 덮개 색인 없이 예산 안 | 111초(시드 99초) |
| `ws test --package note_core --platform chrome` | 준비 ok, **91개 통과**(78 + `handwriting_browser_test` 13), 1개 건너뜀(perf) | 158초 |
| `ws check` | R1~R16 위반 0·경고 0 | 92초 |
| 루트 `flutter analyze --fatal-infos` | 0건 | 21초 |

#### 계획과 다르게 한 점 (동시 개발)

- T24: 1차 `test/storage/schema_test.dart`(v1 테이블 10개)를 지우고 `schema_v2_test.dart`가 그 검사를 v2로 이어받았다(테이블 15 + FTS·그림자 4, 색인 22개, `field_versions` 10, `user_version` 2, `drift_schemas` v1·v2).
- T24: '새 v2 = 이주한 v2의 `sqlite_master`' 비교는 v1 원본을 **V7 고정 자료**(1차 코드가 쓴 DB)로 하고, 식별자 따옴표·괄호 앞 공백을 정규화해 비교한다. 생성 `schema_v1`이 만든 v1 표와 업그레이드가 생성 `Schema2`로 만든 새 표는 `PRIMARY KEY(id)`처럼 1차 실제 표(`PRIMARY KEY ("id")`)와 글자가 조금 다르다(열·형·제약·순서는 같음). 이주 시험(`migration_v2_test`)의 합성 v1은 계획대로 생성 `schema_v1`로 만든다.
- T24: 생성 시험 `migration_test.dart`는 `package:flutter_test` 대신 `package:test` + `@TestOn('vm')`(note_core는 순수 Dart 멤버)로 고쳤고, 자료 보존 사례를 실제 행(폴더 `name_norm` 재계산·pdf 배경 `bg_*`·녹음 `title` NULL·outbox)으로 채웠다.
- T24: `kDatabaseSchemaVersion`이 2가 되어 백업 골든 `test/goldens/backup/backup_v1.json`의 `schema.database`가 1 → 2(그 한 글자만)로 바뀌었다 — T24 커밋에 함께 넣었다(골든 다시 만들기 별도 커밋 규칙의 예외: 버전 상수가 바뀌는 커밋에서 바로 깨지므로). `backup_v2.json`(객체·손글씨·녹음 제목)은 계획대로 T29.
- T24: v1 사본의 실패 기록도 같은 수명(정상 열기 5번 + 7일)으로 지운다(계획은 실패 기록의 수명을 정하지 않음). 사본 kv(`db.v1Copy`)는 기기 로컬 기록이라 쓰기 큐를 거치지 않고 DB에 바로 쓴다(열기 끝·`deleteV1DatabaseCopy` — outbox·HLC 없음, 실패해도 열기를 막지 않음).
- T24: 시험 이음새 — `DriftNoteStore.open`의 `@visibleForTesting databaseFactory`가 `(executor, v1CopyMaker)`를 받도록 바꿨고(1차 `open_errors_test`의 3곳 고침), `@visibleForTesting v1CopyMethod`로 VM에서 웹 형식(블롭 덤프)을 돌린다. `open_errors_test`의 '새 앱' DB는 v3로 올렸다.
- T24: `test/shared/b2_alpha_store_cases.dart`의 `tasks.v1Copy`를 null 허용으로(실제 저장소는 T24부터 사본 API가 동작 — 메모리 저장소는 사본 없음).
- T28: 원격 손글씨 결과는 노트를 영향 노트로 두되 `updatedAt`은 옮기지 않는다(계획 6.13은 '영향 노트 `refreshNoteDerived`'만 적음 — 로컬 `put`과 같게).
- T26: `DriftSyncStore._readKind`의 새 두 종류(계획은 T28의 '종류 switch')를 T26에 했다 — 완료 조건의 `readVersioned` 행과 고아 시험(`applyRemote`로 객체 → 페이지)이 쓴다. T28에는 `_RemoteWriter`의 `content_rev`·노트 갱신과 색인 훅이 남는다.
- T26: `data_json`은 메타 키에 더해 `type`도 뺀다(열이 따로 있음 — 계획 표의 '종류별 키 + `frame`'). `writeEntityRow`·`putLocal`의 `strokeNoteId` 인자 이름은 그대로 두고 객체 행의 `note_id`에도 쓴다(내부 이름).
- T26: 1차 `field_version_writer_test`의 '모든 표본 왕복'이 `kSampleEntities` 전부(객체 8·손글씨·제목 있는 녹음)를 돌게 했고, v1 DB 전용 표본 `kV1RowSamples`(`test/shared/entity_samples.dart`)는 지웠다.
- T27: 계획 6.5의 `SessionBackend` 변경(`loadStrokes` → `loadContent`)은 B2-β에서 이미 했다. T27은 B2 가드(`storesPageObjects`)를 **지웠다**(내부 — 두 백엔드 모두 객체를 저장). `NoteContentReader.loadPage`도 세션과 같은 한 읽기 트랜잭션 함수(`readActiveContent`)로 읽는다(계획은 세션 읽기에만 트랜잭션을 적음).
- T27: 원격 객체가 옛 페이지에서 다른 페이지로 옮겨진 경우(로컬 명령으로는 생기지 않음 — `UpdateObjects`가 `pageId`를 고정)는 1차 획과 같이 힌트 `pageId`(새 페이지)만 고친다 — 옛 페이지가 로드돼 있으면 다시 열 때까지 남는다. 1차와 같은 한계라 고치지 않았다.
- T31: 계획 표의 '①이 실패하면 행을 쓰지 않음' 외에 ②가 경합으로 `StateError`면 ①의 meta도 지운다(계획에 없음 — meta만 남으면 다음 `listDrafts`가 초안으로 되살리므로). 30분 분량 Chrome 기록은 조각 1,800개를 `append` ①과 같은 키로 블롭에 바로 쓰고 행을 한 번 고쳐 만든다(`append` 1,800번은 커밋 1,800번이라 공유 Chrome 시간을 줄이려고 — `append` 시간은 PF-7 Chrome 기록이 따로 잰다).
- T31: 노트 영구 삭제 때 초안(행·meta·조각)을 버리는 것(6.7.2 끝·6.14.2)은 계획 8.2대로 T29(`deleteNoteContents` 확장) 몫 — 지금 실제 저장소는 영구 삭제된 노트의 초안을 남긴다.
- T32: 6.9.3의 `refresh`를 두 군데 바꿨다(PF-6·PF-11 첫 측정이 예산을 넘어서 — 첫 구현 293 ms / 2.46 s). ① 획 행(`page_id, id, updated_at, tool`)을 Dart로 읽어 고르는 대신 SQL 집계(`group_concat … ORDER BY id` — SQLite ≥ 3.44, VM·wasm·네이티브 모두 묶인 3.54.1)로 페이지당 한 행만 읽는다(drift `TypedResult.read`가 2만 행에 130~190 ms). ② 캐시 쓰기를 50쪽 묶음마다 큐 작업 하나가 아니라 `refresh` 한 번에 큐 작업 하나로(파일 DB `journal_mode=delete`·`synchronous=FULL`에서 커밋 하나가 약 15 ms — 5,000쪽이면 100번에 1.5 s). 읽기 묶음(50쪽)과 '그 사이 content_rev가 바뀐 페이지는 쓰지 않음'은 그대로다. 덮개 색인 `idx_strokes_ink`는 넣지 않았다(PF-11 390 ms — 예산 안).
- T32: 계획 6.9.4에 없는 두 가지 — 있던 행의 `createdAt` 유지(메타 키라 동기화되지 않으므로 기기마다 달라지지 않게), 동기 키가 같으면 쓰지 않음(색인기가 같은 결과를 다시 써도 동기화·`ChangeBatch`가 생기지 않게). 가짜도 같이 고쳤고 공유 본문에 사례를 더했다.
- T32: 알려진 경합(1차와 같은 한계 — 썸네일 `contentRevision`도 같음): 세션의 로컬 커밋은 `content_rev`를 세션 메모리 값으로 **덮어쓴다**(`+1`이 아님). 원격 획 커밋과 그 페이지가 열린 세션의 로컬 커밋이 엇갈리면 두 변경 뒤에도 `content_rev`가 한 번만 오를 수 있고, 그 사이에 계산된 `ink_rev` 캐시가 최신으로 보일 수 있다(다음 획 변경에서 바로잡힘). 고치려면 세션 쓰기를 `MAX(content_rev + 1, 세션 값)`으로 — 1차 동작이라 T32에서는 건드리지 않았다(다음 세션 메모).
- T24: V7 고정 자료로 하는 웹 시간 측정(6.12.3 Chrome·PF-8)은 T25b 몫이라, 첫날 확인은 같은 크기의 합성 v1(획 2,005개)로 했다. **웹 업그레이드 열기가 1.9~2.5초**(load 6~9)로 PF-8 예산 '사본 포함 1초'를 넘었다 — 덤프 자체는 0.3초라 나머지(블롭 1.4 MB `put`, IndexedDB VFS의 업그레이드 쓰기)를 T25b의 PF-8 시험에서 고정 자료로 다시 재고 넘으면 원인을 나눠 본다.

#### 다음 세션 메모

- 끝난 것(동시 개발): T24, T26, T27, T28, T30, T31, T32. 다음은 **T33a**(T26·T32 뒤 — 색인 쓰기 훅을 한 곳에: 로컬 세션 쓰기·원격 `_RemoteWriter`·손글씨 `put`/`update`/`removeForPage`·원격 손글씨) → T33b → T34 → T29 → T36 → T37. T35(네이티브 파일 블롭·파일 DB)는 T25b 전 언제든 — T35 뒤 PF-7(VM)을 파일 블롭으로 다시 잰다.
- T33a가 손글씨에 붙일 곳: `DriftHandwritingRepository._store`(새 행·바뀐 행 — 같은 트랜잭션의 savepoint에서 ink 단위 다시 색인, 실패는 원천 쓰기를 막지 않음 C-13)와 `removeForPage`(ink 단위 제거), 원격은 `_RemoteWriter`의 `HandwritingText` 경우.
- `content_rev` 경합(위 '계획과 다르게 한 점' T32): 세션 로컬 쓰기(`drift_sessions.dart` `localPages`·`putLocal(Page)`)를 `MAX(content_rev + 1, 값)`으로 바꿀지 T37(또는 통합) 전에 판단 — 썸네일 캐시도 같은 이득.
- T29가 할 것(초안 몫): 영구 삭제 때 그 노트의 `recording_drafts` 행 삭제 + 커밋 뒤 `rd/<draftId>/` 블롭 삭제(6.14.2 — `afterCommit`). 지금은 남는다.
- 초안 저장소 시험 도구: `test/media/draft_store_support.dart` `openDraftStore(path, idbFactory)`(파일 DB + 같은 메모리 IndexedDB로 다시 열기), `DriftRecordingDraftStore.debugWriteOrder`·`.blobs`.
- 행 쓰기의 규칙(T26): 객체 행의 `note_id`는 `writeEntityRow(strokeNoteId:)`·`putLocal(strokeNoteId:)` 인자로 준다(없으면 `_hints`가 `noteIdOfPage`). 원격 고아는 `''` → 페이지가 오는 커밋의 `_adoptOrphans`.
- 원격 `content_rev`(T28): 객체·손글씨가 쓰인 기존 페이지 `+1`(`applyRemote`의 원격 작성기 — 저수준 `tx.putRemote`만으로는 오르지 않음, T27 `note_session_objects_test`는 `applyRemote`로 확인). 손글씨는 노트 `updatedAt`을 옮기지 않는다.
- 남은 2차 표면 `UnimplementedError`: 색인 T33a(`empty_v2_repositories.dart` `EmptySearchIndex`).
- 생성물 다시 만들기: 패키지에서 `dart run build_runner build` → `dart run drift_dev make-migrations`(`migration_test.dart`는 손으로 고친 판을 유지). 스키마를 바꾸면 `schema_v2_test`의 표·색인 목록도 고친다.
- v1 사본 시험 도구: `test/shared/v1_database.dart`(`createV1Database`). T25b의 고정 자료 초기 바이트 훅(`connect_browser.dart` `@visibleForTesting`)은 아직 없다.
- Chrome 시험은 무거운 잠금 대기가 길 수 있다(다른 영역 웹 빌드·media 시험 — 이번 세션 한 번은 15분 대기). `--heavy-lock-timeout <분>`을 넉넉히.
