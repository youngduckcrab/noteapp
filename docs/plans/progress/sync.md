# SYNC 진행 기록

## 요약

- 마지막 세션: 2 (동시 개발 단계 개발 세션 2/8) — T5 완료 (세션 1: 문서·T1·T2·T3)
- 다음 할 일: T7 스케줄러·백오프 → T4 병합(+ `FakeSyncServer.mergedState`) → T6 가짜 로컬·계약 스위트·하네스 …
- 순서(계획서 8장): T1→T2→T3→T5→T7→T4→T6→T8→T9→T10→T11→T12→T13→T14→T15→T17→T16

## 작업 표

| ID | 상태 | 커밋 | 비고 — 완료 조건 테스트 파일 |
|---|---|---|---|
| T1 | 완료 (앞부분 B7은 기반 단계에서 완료) | 4d7a82f (B7), 8dd1fe5 | `test/no_dart_io_test.dart`(B7), `test/dart_test_yaml_test.dart`(태그 선언·`integration` skip 소스 검사), `test/web/firebase_compile_test.dart`(Chrome), `ws check` 0. 4장 시그니처 파일 전부(본문은 `UnimplementedError('SYNC Tn')` — n = 채울 작업). 값 클래스 7종 `==`·`SyncConfig.copyWith`·`syncBadgeOf`·`ManualConnectivitySignal`은 이미 구현(테스트는 T10) |
| T2 | 완료 | af0340b | `common/server_cursor_test.dart`, `common/varuint_test.dart`, `common/lru_set_test.dart`, `common/errors_test.dart`(추가), `model/field_versions_ext_test.dart`, `model/field_units_test.dart`, `model/scopes_test.dart`(추가), `model/sync_doc_test.dart`, `model/records_test.dart`, `codec/canonical_json_test.dart`. 커서·varuint 본문은 `test/shared/*_cases.dart`(T3 Chrome 테스트가 다시 씀). 엔티티 8종 고정 JSON은 `test/support/entity_fixtures.dart` |
| T3 | 완료 | 2fbf922 | `goldens/chunk_v1_golden_test.dart`(golden·VM: 824 B·sha-256·청크 ID·상수 사본 = 파일), `codec/chunk_codec_test.dart`(왕복, 디코드 오류 27종, fmt 2 거부), `codec/chunk_packer_test.dart`(범위·정렬 결정성·256 KiB·2,000개·단독 큰 기록·1,000,000 B 격리·16청크·8 MiB), `test/web/pure_logic_browser_test.dart`(Chrome: 코덱 골든·varuint·`ServerCursor` — 병합 성질은 T4에서 추가). 골든 `test/goldens/chunk_v1_golden.bin`은 Python으로 따로 만들어 Dart 인코더 출력과 같음을 확인 |
| T4 | 남음 | | `merge/field_merge_test.dart`, `merge/field_merge_properties_test.dart`, `merge/sync_merge_policy_test.dart`, `merge/merge_recorder_test.dart`, `merge/record_gate_test.dart` |
| T5 | 완료 | (이 커밋) | `testing/fake_sync_server_test.dart`(원자 커밋·같은 su·같은 순간 커밋은 +1 µs, (su,id) 정렬·쪽 나눔·꽉 찬 마지막 쪽 뒤 빈 쪽, since, fetchScope·count·delete, watch 초기(빈 결과도)·추가·modified·취소·삭제 미보고, 늦은 가시성, 오프라인 스트림 오류·호출 실패·응답 유실, 장애 5종(`FakeNetworkError`·`FakeAckLost`·`FakeErrorCode`·`FakeInterrupt`·`rejectCommitsWhere`)·순서, 규칙: uid·크기 2단계·필드·청크 ID·같은 ID 재쓰기, 카운터·`callCount`, `upsertDevice` 서버 시각·`firstSeenAt` 유지, 프로필, `getChunks`, `commitRaw`, `close`), `testing/fake_blob_store_test.dart`(조각 진행률, 60% 중단 후 재시도, 같은 sha256 재업로드, 저장소 규칙, 다운로드 maxBytes·notFound·중단, 오프라인·취소, stat 장애, 서버 쪽 직접 접근·바이트 손상). `mergedState`는 T4(`FieldMerge`)에서 채움 |
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
| 문서 | 완료 | 749fa45 | C13-05·SYNC-4-1~4-3: 계획서 상태 줄 '승인', 계약 인용 v1.4, 5.1.1 블록 = 계약 7.2.10 원문, C-11·C-12 purge 대기 경우, 12.2 결정 칸, 13.4 |

## 변경 요청

- 없음

## 의존성 요청

- 없음

## 계획과 다르게 한 점

- (B7) `test/support/lib_boundary.dart`를 테스트 도우미 위치로 추가(계획 3장 트리에 없는 경로). B1의 `test/sync_engine_smoke_test.dart` 삭제.
- (T1) pubspec은 B1(INFRA) 그대로 둠: 의존 목록·버전은 3.1과 같고 `description` 문구만 다름(INFRA B1 값 유지 — LIBRARY-3-3과 같은 처리).
- (T1) `dart_test.yaml` 소스 검사는 `test/dart_test_yaml_test.dart`(3장 트리에 없는 파일)로 둠. `ws check` R15가 기준이고 이 테스트는 같은 규칙 + '선언 태그 = 3.2의 3개'를 본다.
- (T1) 4장에 생성자가 없는 테스트 도우미(`FakeSyncBackend`·`FakeBlobStore`·`TestDevice`)는 `@internal` 이름 붙은 생성자(`.internal`)로 둠(패키지 밖에서 만들지 않음 — 각각 `FakeSyncServer.connect`·`blobsOf`·`SyncTestHarness.device`가 만든다).
- (T2) 내부 파일 `common/varuint.dart`는 `abstract final class VarUint`(`write`·`read`·`encode`·`lengthOf`), `common/lru_set.dart`는 `LruSet<T>`, `codec/canonical_json.dart`는 `canonicalJson`·`canonicalJsonBytes`(모두 export 안 함). `ServerCursor`·`SyncDoc`·`UpsertRecord`·`PurgeRecord`에 `==`/`hashCode` 추가(4장 시그니처에 없는 멤버 — 값 비교·테스트용). `ServerCursor.parse`는 2^53 이상을 `FormatException`으로 거부. `SyncDoc.toEntity`는 CORE가 `FormatException` 밖의 오류(TypeError 등)를 던지면 `FormatException`으로 감싸고, 디코드한 `entity.id`가 다르면 `FormatException`. `SyncScopes.scopeOf`: recording은 힌트가 없으면 `json['noteId']`, page는 `json['noteId']`가 없으면 힌트.
- (T3) 코덱 내부 API(export 안 함): `ChunkCodec`(`encode`·`encodeRecord`·`assemble`·`payloadLength`·`decode`·`maxHlcOf`·`blobKeys`), `chunkIdOf(node, payload)`, `ChunkPacker(config:, authorNodeId:).pack<T>(List<PackItem<T>>, kind:)` → `PackResult`(`commits`: `PackedCommit`→`PackedChunk`(`write`·`items`), `tooLarge`). 범위(scope)는 호출자가 `PackItem.scope`로 넘긴다(T8이 `SyncScopes`로 계산). 같은 종류·id면 upsert가 purge보다 앞. 격리 기준은 '그 기록 하나만 든 청크의 페이로드 > `chunkHardLimitBytes`'.
- (T1) `FirebaseSyncBackend`의 `uid`·`blobs`는 생성자 인자를 받는 `final` 필드(이름 있는 인자 이름은 4.10 그대로).
- (T5) `@internal` 생성자 인자: `FakeSyncBackend.internal(server:, uid:, link:)`, `FakeBlobStore.internal(uid:)`. 백엔드·Blob 보기가 쓰는 `@internal` 멤버: `FakeNetworkLink.beginCall`·`rejectionFor`·`onOffline`, `FakeSyncServer.now`·`serveCommit`·`serveFetch`·`serveScope`·`serveCount`·`serveGetChunks`·`serveDelete`·`serveProfile`·`serveDevice`·`serveWatch`, `FakeBlobStore.uid`·`serveStat`·`serveUpload`·`serveDownload`(공개 최상위 이름 추가 없음). `FakeSyncBackend.blobs`는 링크를 거치는 비공개 보기(`blobsOf`의 `FakeBlobStore` 자체는 지연·장애 없는 서버 쪽 직접 접근).
- (T5) 가짜 서버 동작으로 정한 것(4.11에 없던 세부): 서버 시각은 주입 `Clock`의 µs를 모든 쓰기에 걸쳐 단조 증가(같은 순간이면 +1 µs). 쪽 토큰은 `(su, id)` startAfter, 꽉 찬 쪽이면 항상 토큰(Firestore 어댑터와 같음 — 다음 쪽이 빌 수 있음). watch는 listen 때 열리고 첫 결과를 비어 있어도 보낸다. `readCount` = 내준 청크 문서 수(fetch·fetchScope·getChunks·watch 묶음, count 제외), `writeCount` = 청크 문서 쓰기(재쓰기·`commitRaw` 포함, 프로필·기기 제외), `deleteCount` = 삭제 요청 id 수. `getChunks`는 늦은 가시성과 무관(id 읽기). 크기 규칙 2단계: 문서 > 1 MiB → `invalidArgument`, `data` > 1,000,000 B → `permissionDenied`(규칙). 배치 > 500 → `invalidArgument`. `FakeInterrupt`를 전송이 아닌 호출이 가져가면 `FakeNetworkError`처럼, `FakeAckLost`를 읽기가 가져가면 서버가 읽은 뒤 네트워크 오류. `FakeErrorCode`는 왕복 뒤. 오프라인이면 호출이 즉시 network. `close()` 뒤 watch는 오류 없이 끝나고 새 호출은 `StateError`. Blob: 1 MiB 조각당 10 ms(가상), 진행률은 0 다음 조각마다, 같은 sha256 재업로드는 쓰기 없이 성공(`FirebaseBlobStore`의 permission-denied → stat 처리와 같은 결과), `uploadCount`/`downloadCount` = 쓴 객체/끝난 전송.
- (T5) 테스트 도우미 `test/support/fake_time.dart`(`runFake`·`runFakeError` — fakeAsync 안에서 future를 끝까지 진행).

## 다음 세션 메모

- cloud_firestore 7.1.0은 `Type`(파이프라인 식)을 export해 `dart:core`의 `Type`을 가린다. Firestore를 import하면서 `Type`을 쓰는 파일은 `import 'package:cloud_firestore/cloud_firestore.dart' hide Type;`(T1 `firebase_compile_test`에서 발견, T17 주의).
- `lib/src/firebase/display_mode.dart`의 내부 함수 이름은 `isStandaloneDisplayMode()`(export 안 함). `FirebaseAuthBackend(isStandaloneWebApp:)` 기본값.
- 세션 1 끝 상태: `ws check` 0, 루트 `flutter analyze --fatal-infos` 0, 패키지 VM 테스트 151개 통과, Chrome(`flutter test --platform chrome test/web`) 21개 통과(첫 컴파일 약 40초).
- 아직 `UnimplementedError('SYNC Tn')`인 본문: n이 그 본문을 채울 작업이다(4장 시그니처는 T1에서 모두 만들어 둠 — 파일을 새로 만들지 말고 본문을 채운다). 예외: `AuthService`는 T14로 적었지만 T10 엔진(`auth_attach_test`)이 먼저 쓰므로 T10에서 채워도 된다. `FakeAuthBackend`는 T10으로 적음.
- `FakeSyncServer.mergedState`는 아직 `UnimplementedError('SYNC T4')`다. T4에서 `FieldMerge`로 채우고(청크 디코드 → purge 적용 → 병합) 테스트한다.
- 가짜 서버 테스트는 `fakeAsync` + `test/support/fake_time.dart`의 `runFake`로 쓴다(가짜 서버·Blob은 `Future.delayed`·`Timer`로 지연을 만든다 — 실제 시간에서 돌리지 않는다).
- 공용 테스트 자료: `test/support/entity_fixtures.dart`(엔티티 8종 JSON·`kCoreJsonKeys`·`hlcText`·`kNodeA`), `test/shared/*_cases.dart`(VM·Chrome 공용 본문 — T4 병합 성질도 여기에 두고 `test/web/pure_logic_browser_test.dart`에 group 추가).
- 다른 영역은 이 작업 트리에서 기반 단계 상태다. CORE는 `createFakeNoteStore()`(SyncStore 대부분 `UnsupportedError`)와 실제 값 타입(B2)만 쓸 수 있다.
