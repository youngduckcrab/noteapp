# CORE 2차 계획서 검토 — `02-core.md`

> 검토자: 총괄 대리 검토자 · 검토일 2026-11-05
> 대상: [02-core.md](../02-core.md)(2,274줄, 초안) — 문서 모델 · 저장 · 되돌리기 · 색인, 소유 경로 `packages/note_core/`
> 기준: 개요 [00-overview.md](../00-overview.md) 7장 통합 계약 v2.0 초안(7.2.2~7.2.8·7.3.2·7.6·7.7.2·7.8), 조사 01·02·03·04, PLAN.md(F-10·F-11·F-13·F-14·F-16, 5.1·5.2·5.4, 7.2, 10장), 1차 CORE 작업 트리 `/home/user/wt/core`(`4336967`), 1차 통합 브랜치 `/home/user/noteapp`(`6c470ab` — `packages/note_core`는 `4336967`과 같음, 1차 통합에서 CORE 코드 변경 없음 확인), 다른 영역 계획서 01·03~07의 맞닿은 절
> 확인 방법: 계획서 전 절을 읽었다. 7장 Dart 블록과 계획서 '원문' 블록을 줄 단위로 기계 대조했다(7.2.2~7.2.7·7.6의 계약 코드 줄이 계획서에 **모두** 있고, 계획서에만 있는 줄은 'CORE 확정 세부' 블록 안에만 있음). 1차 코드 인용·pub 캐시(drift 2.35.3·drift_dev 2.35.2·sqlite3 3.8.0)·pub.dev API를 확인했고, 계획서의 FTS5 실험(`/tmp/claude-0/plan57-scratch/core57/bin/probe.dart`)을 다시 돌렸다(같은 결과). 무거운 시험은 돌리지 않았다. 임시 작업 `/tmp/claude-0/plan57-scratch/core-review/`.

---

## 총평

계약 7장을 글자 그대로 옮기고, 7장이 비워 둔 곳만 'CORE 확정 세부'로 채운 뒤 CP로 올리는 구조가 깔끔하다. 다시 확인한 사실은 대부분 맞았다.

- 1차 코드 인용: 명령이 `CompositeCommand`를 빼고 모두 이름 있는 인자 + `const` + `label`이고 `EditCommand.label`이 추상 getter(`edit/commands.dart` 14–25) — CP-1의 근거가 맞다. `WriteTxn._hints`(`storage/write_queue.dart` 514, `default:` 있는 switch), `kLocalOnlyFields`(`outbox_writer.dart` 22), `Affine2.rotation = atan2(b, a)`(`geometry.dart` 164), `copyNote`(`drift_library_repository.dart` 935), `idx_strokes_page (page_id, deleted_at)`, `PageBackground` JSON 키(`type`·`assetId`·`pdfPageIndex`), `drift_sync_store.dart`의 `EntityKind.` 21곳, `failNextCommits`·`fieldLwwPolicy()`·`json_web_format_cases.dart` 존재, `NoteStore.clock`(가짜 녹음기의 `startedAt`) 모두 확인.
- 외부 사실: `sqlite3 3.9.0` 게시 2026-11-05T08:58Z(14일 규칙으로 제외 — 맞음), drift `WasmDatabase.open(initializeDatabase:)`(`drift-2.35.3/lib/wasm.dart` 161), `doc/hook.md`의 `SQLITE_ENABLE_FTS5`, FTS5 `contentless_delete=1`·`remove_diacritics 0`·`json_extract`(VM 3.54.1 재실행 통과). drift `SchemaVerifier`는 `ValidationOptions.validateDropped` 기본값이 `false`라(`drift_dev-2.35.2/lib/api/migrations_common.dart` 181) **6.11 1안(customStatement로 FTS)이 생성 마이그레이션 시험과 충돌하지 않는다** — 2안 대비 문장은 줄여도 된다.
- 설계: 'B2 상태' 표(실제 저장소의 새 멤버가 작업 번호를 단 `UnimplementedError`), 가짜·실제 공유 계약 본문, 실제·가짜가 같은 판정·랭킹 파일을 쓰는 검색(6.10.6), 점 디코드 없는 `stalePages` 페이지 캐시(6.9.3), savepoint 색인 + 타이머 없는 재시도(C-13), V7 고정 자료를 실제 1차 코드로 만드는 방식이 좋다. 다른 영역도 CP를 대부분 받아들였다(EDITOR CP-1·CP-2, INK CP-2·5·6·9, PDF CP-3·7·8·10·11·12와 Q3·Q4·Q8 답, LIBRARY CP-13·14).

그러나 **그대로 승인할 수 없다(revise)**. ① PDF 전역 색인의 글자 상자·원문을 SQLite에 넣어 **주 시험 기기인 iPad Safari에서 DB 메모리·열기 시간이 커지는데**(1차 CORE 자신의 원칙 '대용량 바이트는 SQLite에 넣지 않는다' 위반) 크기 예산·시험이 없고, 질의가 후보 2,000개의 사각형 BLOB까지 읽는다. ② 기반 단계 R2-B2가 한 세션을 넘고 계약 타입 커밋(T22)이 구현 뒤라 7개 영역의 임계 경로 맨 앞을 늘린다. ③ iPad의 실제 1차 노트 마이그레이션을 미리 확인할 길도, 성공 뒤 되돌릴 길도 없는데 위험 1의 대응('미리보기 채널에서 먼저 확인')은 출처가 달라 실제 데이터를 보지 못한다. 그 밖에 `ElementFrame.fromJson` 정규화 문장 모순, make-migrations 산출 파일 이름, 웹 초안 내구성 가정, V7 Chrome 고정 자료 전달 방법, `replaceUnits` 빈 목록 의미 등을 고쳐야 한다.

---

## 반드시 고칠 것

### M-1. PDF 색인의 글자 상자·원문을 SQLite에 넣어 웹 DB 메모리·열기 시간이 커진다 — 크기 예산·시험이 없고, 질의가 사각형 BLOB까지 읽는다

- **위치**: 6.10.3 표 `pdf` 행·테이블 문단, 6.11 `search_units.rects`(float32 l,t,r,b 반복 BLOB)·`body`·`norm`, 6.10.4 의사 코드(`SELECT u.* … LIMIT 2000`), 4.6 'CORE 확정 세부'의 `rects` 해석 규칙, 6.10.7, 6.19 PF-3~PF-5, 11 위험 3, 9.5 B-13.
- **문제**:
  1. PDF가 확정한 단위는 **쪽 하나 = 단위 하나 + 글자마다 상자**(`rects.length == body.length` — 06-pdf 6.4.1, 12.2 Q3 답)이고, 노트에 가져오지 않은 쪽까지 **에셋 전체**를 색인한다(06-pdf 12.3 Q8). 상자 16 B/글자라 2,000자 쪽 32 KB, 500쪽 교재 약 16 MB(PDF 자체 계산) + `body`·`norm`(한국어 UTF-8 3 B × 2열) 약 10 KB/쪽 + FTS가 쌓인다. 교재 몇 권이면 수십~100 MB가 된다.
  2. iPad Safari는 `sharedIndexedDb`로 동작하고(1차 7.4.9), drift의 `IndexedDbFileSystem`은 **DB 파일 전체를 메모리 캐시에 두고 열 때 전부 읽는다**(1차 02-core 2988·3400행: '대용량 바이트는 SQLite에 넣지 않는다 … PDF·오디오가 DB 메모리를 키우지 않게 BlobStore로 분리', 획 10만 개 ≈ 76 MB에서 열기 1.6~1.7 s). 색인 BLOB은 바로 그 금지한 일이고 7.4.5 메모리 300 MB 예산과 앱 시작 시간을 직접 깎는다.
  3. 6.10.7의 크기 추정은 FTS만(조사 03 9.2의 '5,000쪽 × 80낱말, 사각형 없음' 합성 자료) 세고 사각형·원문 열을 빼먹었다. PF-3~5도 같은 합성 자료라 이 문제를 드러내지 못한다.
  4. 6.10.4 후보 질의가 `u.*`로 후보 최대 2,000개의 `rects`(쪽 단위라 개당 수십 KB)까지 읽는다 — 흔한 낱말에서 한 번 입력에 수십 MB를 읽는다. 사각형이 필요한 것은 최종 `limit`개 대표 단위뿐이다.
- **고칠 방향**:
  - 저장: `rects`를 SQLite 밖 `BlobStore`(웹 IndexedDB `noteapp_blobs`, 네이티브 파일 블롭 — 이미 있는 경로)에 키 `si/<source>/<ownerKey>/<seq>`로 두거나, 최소한 쪽 비율 좌표를 uint16(÷65535)로 양자화하고 줄 상자 + 글자 x 경계만 두는 압축 형식(약 2~4 B/글자)으로 줄인다. 계약은 '비율 좌표'만 정하므로 내부 형식은 CORE가 바꿀 수 있다(정밀도는 PDF와 합의 — X-1, C-5).
  - 질의: 후보는 `id·source·owner_key·note_id·page_id·asset_id·pdf_index·norm`만 읽고, `body`·`rects`는 판정을 통과해 묶음의 대표가 된 `limit`개만 읽는다.
  - 예산·시험: 6.10.7에 '실제 모양'(쪽 단위 2,000~3,000자 + 글자 상자, 한국어·영어) 기준 크기 예산을 두고(예: 500쪽당 색인 ≤ N MB), PF에 그 모양의 500쪽 고정 자료로 `replaceUnits` 바이트·질의 시간을 잰다. Chrome에서 색인 뒤 **저장소 다시 열기 시간**을 기록하는 시험(1차 `open_time_browser_test` 방식)을 T33/T37에 더한다. 9.5 B-13에 'PDF 500쪽 색인 뒤 앱 다시 열기 시간·메모리'를 더한다. 위험 3을 '저장 공간'뿐 아니라 '웹 DB 메모리·열기 시간'으로 넓힌다.

### M-2. 기반 단계 R2-B2(T20~T23)가 한 세션을 넘고, 계약 타입 커밋이 구현 뒤에 있어 임계 경로를 늘린다

- **위치**: 8.1 작업 표·'순서: T20 → T21 → T22(계약 타입 고정) → T23', 1.2 표 첫 행, 8.4.
- **문제**:
  - R2-B2 한 묶음에 T20(객체 모델·템플릿·JSON·골든 9개·웹 시험) + T21(녹음·손글씨·검색 값 타입, `SearchText` 정규화·바이그램·판정·랭킹, 오디오 포트·`Unsupported*`, `bytesByType` 실제·가짜, 웹 시험 2개) + T22(명령·인터페이스·provider·진입점·B2 상태) + T23(해석기·세션 객체 상태·메모리 백엔드·가짜 v2의 녹음/초안/손글씨/메모리 색인·`FakeAudioRecorder`·`FakeAudioPlayback`·`PageObjectFixtures`·공유 계약 본문 5개)가 들어 있다. 1차 B2(T0~T5, 커밋 `7bb1c59`)와 같거나 크고, 계획서는 세션 수를 적지 않았다. T23 하나만으로도 한 세션을 넘기 쉽다.
  - 계약 7.6은 '각 영역은 **CORE 계약 타입 커밋** 뒤 자기 작업 트리에서 코드를 쓰기 시작해도 된다'이고, R2-B7(SYNC)·R2-B2i(INFRA)는 T22 해시를 기다린다(8.1 순서 문단). 그런데 T22가 T20·T21의 **구현과 시험이 끝난 뒤**라 INK·EDITOR·LIBRARY·PDF·SYNC·INFRA가 모두 그만큼 늦게 시작한다. 4.4 임계 경로 맨 앞이 CORE다.
- **고칠 방향**: R2-B2를 세션 크기로 나누고 계약 표면을 먼저 낸다.
  - **B2-α(표면, 약 0.5세션)**: 4.1~4.11의 모든 공개 선언 — enum·한도 상수·생성자·필드·`==`·`EntityKind` 2값·`NoteStore` getter 4개(B2 상태)·provider 6개·진입점 export — 를 실제로, 알고리즘 본문(`SearchText`·템플릿·`sourceRevOf`·해석기 객체 분기)은 작업 번호를 단 `UnimplementedError`로 둔 커밋 + `api_surface_test` v2. 이 해시를 SYNC·INFRA·총괄에 알린다.
  - **B2-β(동작, 1.5~2세션)**: T20·T21 순수 함수·골든·웹 시험, T23을 'T23a 해석기·세션' / 'T23b 가짜 v2(녹음·초안·손글씨·메모리 색인)·가짜 오디오·픽스처'로 나눔.
  - `main` 병합은 계약대로 B2 전체(α+β) + R2-B7 + R2-B2i 묶음 뒤다. 각 조각의 완료 조건과 세션 추정을 8.1에 적는다. SYNC가 JSON 키 대조에 쓰는 골든(T20·T21)은 β 앞쪽에 둔다.

### M-3. iPad의 실제 1차 노트 마이그레이션을 미리 확인할 길도, 성공 뒤 되돌릴 길도 없다 — 위험 1 대응이 실제 데이터를 보지 못한다

- **위치**: 11 위험 1, 6.12.1, 6.12.3 끝 문단, 9.5 B-1, 4.8 'NewerSchemaError' 문단.
- **문제**:
  - 위험 1 대응의 '미리보기 채널(출처가 달라 데이터 분리 — 1차 7.4.9)에서 먼저 확인'은 바로 그 이유로 **실제 노트를 이주하지 않는다**. 미리보기 채널 id는 브랜치마다 다르다(`ci.yml` 174행 `ws channel-id --branch`). 사용자의 실제 DB는 live(또는 1차 확인에 쓴 특정 채널) 출처에만 있으므로, 실제 이주는 2차가 그 출처에 배포되는 순간 처음 일어난다. 계약 7.8 B-1 '통합 미리보기 배포 직후'도 같은 이유로 실제 노트를 보지 못한다(C-6).
  - 실패하면 한 트랜잭션이라 v1이 남아 되돌린 배포가 연다(좋다). 그러나 **이주가 성공한 뒤** 2차 코드의 버그로 데이터가 상하면 1차로 돌아갈 수 없고(`NewerSchemaError` — 앱 전체가 안 열림), 백업 **복원**은 이번 범위 밖이다(1.3). 사용자 데이터는 iPad 웹 하나뿐이라(6.12.3) 마지막 안전망이 없다.
- **고칠 방향**:
  1. 업그레이드 트랜잭션 직전에 v1 사본을 같은 저장소에 남긴다: `VACUUM INTO '<databaseName>-v1-backup'`(SQLite 내장 — 웹 IndexedDB VFS·네이티브 파일 모두, 새 의존 없음. 웹 VFS에서 새 파일 만들기가 되는지는 [추측] → T24 첫날 Chrome 시험으로 확인). kv에 사본 시각을 남기고, 사본은 'v2로 N번 정상 열기 뒤' 자동 삭제 또는 개발자 메뉴에서 삭제. 개발자 메뉴 'v1 DB 사본 내보내기'(파일 저장)는 INFRA 연결(X-6). V7 시험(VM·Chrome)에 '사본의 v1 정규 덤프 해시 = manifest' 단언을 더한다.
  2. 위험 1·6.12.3·9.5 B-1 문구를 '실제 데이터의 이주는 그 데이터가 있는 출처에 배포될 때 처음 일어난다'로 고치고, B-1 절차를 '배포 전 백업 내보내기(INFRA 안내서) → 그 출처에 배포 → 첫 실행 → 확인'으로 적는다.
  3. 사용자의 1차 노트가 어느 출처에 있는지, 그 DB를 어느 빌드로 만들었는지를 묻는다(질문 Q-1 — V7 고정 자료의 대표성과도 걸린다).

---

## 권장

- **S-1. `ElementFrame.fromJson`의 정규화 문장이 서로 모순이다.** 6.2.1은 "`normalized()`·`fromJson`·`transformed`가 접는다", 6.2.3 끝은 "정규화(스타일과 `ElementFrame.normalized()`)는 로컬 명령 해석 때 한다. `fromJson`은 정규화하지 않는다(원격 값과 해시·버전이 어긋나지 않게)". 읽을 때 접으면 경계값(`−π` → `π`)·범위 밖 값이 다시 쓸 때 바뀌어 C-12·SYNC 키 값 대조·`changedJsonKeys`가 흔들린다. 6.2.3대로 '`fromJson`은 접지 않는다'로 통일하고 6.2.1을 고친 뒤, `−π`·`3π`·변 0 값 왕복 시험을 `element_frame_test`에 둔다.
- **S-2. make-migrations 산출 파일 이름이 다르다.** drift_dev 2.35.2 `make-migrations`는 단계 도우미를 데이터베이스 파일 옆 `note_database.steps.dart`로 만든다(`lib/src/cli/commands/make_migrations.dart` 524–525 `p.setExtension(dbClassFile, '.steps.dart')`). 3절 트리·3절 원칙('`schema_versions.dart`는 `generated_files`에 이미 있다')·6.12.1의 `schema_versions.dart`를 고치고, INFRA `workspace_rules.yaml` `generated_files`에 `*.steps.dart`를 더해 달라고 요청한다(X-6). 생성 머리말에 `// ignore_for_file: type=lint,unused_import`가 있어 analyze는 통과할 것이다(`lib/src/utils/header.dart`) — T24 첫날 `flutter analyze --fatal-infos`로 확인. 생성 시험 파일은 `test/storage/generated_migrations/note_db/`(1차에는 빈 `generated/`만 있음) 아래다.
- **S-3. 웹 초안의 '내구 저장' 가정이 1차 웹 저장 방식과 다르고, 고아 조각 정리가 살아 있는 녹음을 지울 수 있다.** 6.7.3 '②는 drift 웹 워커의 SQLite 커밋 … 탭 닫힘은 완료된 ①②를 잃지 않는다'는 `sharedIndexedDb`의 비동기 반영(1차 02-core 2676행 '문장마다 IndexedDB로 flush, 수 ms 구간 손실 가능', 2988행 'no guarantees on durability')과 다르다. `begin` 행이 반영되기 전에 탭이 닫히고 조각(①, IndexedDB 트랜잭션 완료라 남음)만 남으면, 6.7.2의 '행 없는 `rd/` 접두사 정리'가 그 녹음 조각을 **모두** 지운다 — D13(P-A)이 막으려던 '녹음 전체 손실'이다. `begin`에서 행과 함께 `rd/<draftId>/meta`(recordingId·noteId·mimeType·startedAt JSON)를 블롭 저장소에 먼저 쓰고, `listDrafts`는 행이 없으면 meta로 초안을 되살리며, 정리는 '행도 meta도 없는' 접두사만 지우게 한다. 6.7.3 문장도 실제 보장('조각은 IndexedDB 트랜잭션 완료 시 내구, 행은 수 ms 늦을 수 있고 `listDrafts`가 맞춤')으로 고친다.
- **S-4. 웹 정지 경로도 전체 바이트를 한 버퍼로 만든다.** 6.7.3 '웹은 복구 순간에만 그만큼 쓴다'는 5.4 'M-2 웹 조각'의 '정지 때 `readAll` → `AssetStore.put(audio)`'와 모순이다 — 정상 정지마다 녹음 전체(3시간 ≈ 86 MB)가 메모리에 올라온다. 문장을 고치고, Chrome 시험에 30분 분량(약 14 MB) `readAll` → `put`의 시간·최대 메모리 기록을 더하며, 위험 8을 '정지·복구 모두'로 넓힌다.
- **S-5. V7 Chrome 시험의 고정 자료 전달 방법이 없고, T25 선행에 T35가 빠졌다.** Chrome 시험은 `dart:io`로 `test/fixtures/db_v1/noteapp_v1.sqlite`·`pdf_asset.pdf`를 읽을 수 없다. `tool/prepare_web_test.dart`가 `test/web/`로 복사하고(패키지 `.gitignore`에 복사본 추가 — CORE 소유) 1차 `sqlite3.wasm`처럼 상대 URL로 받는 방식을 정한다(또는 `flutter test --platform chrome`이 `test/fixtures/`를 서빙하는지 T25 첫날 확인). VM 시험은 '파일 DB + 파일 블롭'으로 여므로 T25 선행에 T35를 더한다.
- **S-6. `replaceUnits(…, [])`의 의미를 적는다.** PDF의 따라잡기는 '`#0` 소유자가 마지막 = 완료 표시'이고 글자 없는 스캔 쪽도 `replaceUnits`를 부른다(06-pdf 6.4.2). 빈 목록이어도 **소유자 행(`sourceRev`)을 남긴다**를 6.10.3에 적고 `search_index_test`에 넣는다(C-5).
- **S-7. `MathObject.toJson`의 `engine` 키도 항상 쓴다(`null`이면 `null`).** 6.3은 '공통 키는 항상'만 말하고, 7.2.7은 `engine`(선택)이라 SYNC 6.2.1이 'CORE가 항상 쓰는지 모호'라고 적었다. `Recording.title`처럼 종류별 키 집합을 고정하고 `math.json` 골든에 `engine: null` 사례를 하나 더한다(C-7).
- **S-8. 후보 상한 2,000의 선택 기준을 정한다.** `MATCH … LIMIT 2000`은 사실상 rowid 순(오래된 단위)이라 흔한 낱말에서 결과가 오래된 내용으로 치우친다. 최근 단위 우선(`ORDER BY rowid DESC`) 등 규칙을 정하고 가짜도 같게 한다(6.10.6 '상한에 걸리지 않는 한 같음'의 예외를 줄임).
- **S-9. T33을 나눈다.** 테이블·쓰기 훅·작성기 검증·`rebuild`·`status`·보류 재시도(T33a)와 질의·판정 연결·점수·발췌·사각형·`searchLibrary.pages`·Chrome·perf(T33b)로. 지금 T33은 시험 목록만 열두 항목이라 한 세션을 넘는다.
- **S-10. `stalePages`의 라이브러리 전체 첫 실행 비용을 잰다.** LIBRARY 색인기는 시작 때 모든 노트에 `stalePages`를 부른다(05-library 6.9.5 따라잡기). 마이그레이션 직후에는 모든 페이지가 D에 들어 라이브러리의 모든 획 행을 한 번 읽는다. PF-6(20쪽 × 1,000획)에 '10만 획 라이브러리 첫 따라잡기 합계'를 더한다. 또 `strokes.updated_at`은 `points` BLOB 뒤 열이라(`tables.dart` 115·125행) 긴 획은 넘침 페이지를 따라가야 읽힌다 — 6.9.3 '`points` 열은 읽지 않음' 문장을 보정하고, 필요하면 덮개 색인 `(page_id, deleted_at, tool, updated_at, id)`를 검토한다.
- **S-11. 9.5 A-1을 현실에 맞춘다.** 1차 앱 셸은 `nativeDatabasePath`를 넘기지 않아(`app/lib/src/modules/core_module.dart` 216–222) 1차 APK는 노트를 저장하지 못했다(조사 04 요약 5 ②). '1차 노트'는 없으므로 '2차 APK에서 노트·이미지·녹음 작성 → 다음 빌드 덮어 설치 → 남아 있음'으로 쓴다(C-6).
- **S-12. 보류 색인 재시도 시점.** 재시도가 '다음 쓰기 트랜잭션 끝 / 저장소 열 때'뿐이라 쓰기가 없는 동안 보류가 남는다. 계약 C-13 '다음 유휴 시간'과 문구를 맞추고(C-4), 보류가 남은 상태가 `status.pendingOwners`로 보인다는 것을 6.10.5에 적는다.
- **S-13. `UnknownObject`의 에셋 참조를 보존한다.** 새 종류(예: 스티커)가 `assetId` 문자열 키를 가지면 `referencedAssets`와 `page_objects.asset_id`에 넣어, 이후 고아 에셋 GC(U13)가 새 앱의 에셋을 지우지 않게 한다(옛 앱 보존 원칙 C-12의 연장).
- **S-14. 6.7.2 `discard` 설명의 '조각 0개 초안은 media가 버린다'를 고친다.** PDF 6.9.5는 네이티브 초안이 원래 '행만(조각 0)'이라 정상 상태다. `listDrafts` 시험에 '조각 0 초안 유지'를 넣고 12.2 Q4 기본값을 PDF 답(조각 없이 행만)으로 바꾼다.
- **S-15. 점수 문구 정정.** 6.10.4 '정수·덧셈만'은 사실과 다르다(0.95·0.0005 곱 포함). 같은 연산 순서의 IEEE 754 배정밀도라 VM·웹이 같다는 근거로 바꾼다(결정성 시험은 이미 있음).
- **S-16. 정규화 위임 순서.** 마이그레이션 단계 5(T24)가 `name_norm`·`title_norm`을 새 함수로 다시 계산하는데 쓰기 경로의 위임은 T34라, 개발 중 두 함수 값이 섞인다. 위임(`normalizeForSearch` → `SearchText.normalize`)을 T24에 포함하거나 T34를 T24 선행으로 옮긴다.
- **S-17. `ClearPage` 표기.** 7.2.3의 `ClearPage(pageId, filter = StrokeFilter.all, {bool includeObjects = false})`는 약식 표기이고 1차는 이름 있는 인자 `const ClearPage({required this.pageId, this.filter})`다. 4.4에 '1차 생성자에 이름 있는 선택 인자 `this.includeObjects = false`를 더한다'고 적는다(EDITOR CP-E5의 `ClearPage(includeObjects: true)`와 같음).

---

## 다른 영역과 걸리는 것

| # | 상대 | 내용 |
|---|---|---|
| X-1 | PDF | (1) M-1: `rects` 저장 형식·정밀도(uint16 비율 등)와 질의 때 사각형 지연 읽기를 합의한다 — PDF 6.4.1이 이미 크기(500쪽 16 MB)를 짚고 CORE Q3에 맡겼다. (2) S-6 빈 단위 목록 = 소유자 행 유지. (3) PDF `media`(Chrome) 시험이 실제 CORE 초안 저장소를 일찍 쓸 수 있게 T31 커밋을 SYNC의 T26처럼 '실제 초안 저장소 사용 가능' 이정표로 알린다. (4) S-14 네이티브 조각 0 초안, PDF Q3·Q4·Q8 답을 12.2 기본값에 반영 |
| X-2 | LIBRARY | 05-library 12.2 Q8 `notesWithStalePages()`: CORE는 `pages.ink_rev` 캐시로 라이브러리 전체 낡은 페이지를 한 질의로 답할 수 있다. 이번 라운드 '추가'로 넣을지 CORE가 입장을 정한다(S-10과 함께). L2-D10의 '일부 확정 줄 + 낡은 `sourceRev`로 `put`'은 CORE `put` 검증과 충돌 없음(확인) |
| X-3 | INK | INK CP-INK-4(캘리그래피 획 변형 때 CORE `Stroke.transformed`가 `nibAngleDeg`에 회전각을 더함)는 CORE 동작 변경인데 CORE 계획서에 입장이 없다. 해석기의 `TransformElements`는 이미 스타일이 바뀌면 `style` 키를 기록하므로(`command_resolver.dart` 185) 영향은 작다 — 동의 여부와 시험(`undo_objects_test` 옆)을 12장에 적는다 |
| X-4 | EDITOR | CP-1 지지(CP-E1). EDITOR는 `RemoveElements({id})`처럼 **집합 리터럴**을 쓴다(04-editor 876·1979행) — CP-1의 'elementIds를 List로' 부분은 빼는 편이 낫다(C-1). `FakeAudioRecorder`를 실제 메모리 CORE와 `testWidgets`에서 쓰면 에셋 `put`이 idb_shim 타이머를 거쳐 시간 진행(pump)이 필요하다(1차 CORE 진행 기록 '통합 단계' 메모) — 6.8.3에 적어 알린다 |
| X-5 | SYNC | S-7 `engine` 키 항상. SYNC 계약 스위트 C-26~C-31·T16-v2가 CORE T26·T28을 전제로 한다 — 이정표 커밋 알림(8.2에 이미 있음)을 진행 기록 양식에 고정. `UnknownObject.toJson`의 메타 키 갱신 규칙(SYNC 6.2.8이 기대)은 CP-4로 계약에 올린다 |
| X-6 | INFRA | (1) S-2 `generated_files`에 `*.steps.dart`. (2) M-3 개발자 메뉴 'v1 DB 사본 내보내기·지우기'. (3) 앱 셸이 네이티브에서 두 경로를 모두 넘기는지 정적 시험(S-11의 원인). (4) V5 스모크에서 `FakeAudioRecorder` + 실제 메모리 CORE 조합의 시간 진행(X-4와 같음) |

---

## 계약 문제

- **C-1. CP-1(새 명령 생성자 모양)은 R2-B2 착수 전 결정이 필요하다.** 계획서의 기본 경로(원문 위치 인자 + `label`)는 컴파일된다. 받아들인다면 `const AddObjects({required pageId, required objects})` 모양으로 하되 **`RemoveElements.elementIds`는 원문대로 `Set<ElementId>`를 유지**하기를 권한다 — LIBRARY(05-library 1732·1815행 `RemoveElements(pageId, {…})`)·EDITOR(`RemoveElements({id})`)가 집합 리터럴을 쓰고, 동작 차이도 없다. 받아들이면 7.2.3 블록과 7.2.9 `InkEdit.toCommand` 표(`core.AddObjects(pageId, addedObjects)`)를 함께 고친다.
- **C-2. 7.6 `testing.dart` 주석('substring match … ordering may differ')과 R2-B2 표('검색은 메모리 `LIKE`')**가 CORE CP-14(실제와 같은 판정·같은 순서)와 다르다. LIBRARY가 지지했으므로 7.6 문구를 CP-14대로 바꾼다.
- **C-3. 7.3.2 M-2 '복구를 묻는다' vs 7.2.12 '묻지 않고'**: CORE CP-12 ② = PDF CP-PDF-4. 한 문장으로 정리한다.
- **C-4. C-13 '다음 유휴 시간으로 미룸'**은 '타이머 없음'(1차 T9) 규칙과 함께 읽으면 'CORE의 다음 쓰기 트랜잭션 또는 저장소 열기'가 된다 — 문구를 맞춘다(S-12).
- **C-5. 7.2.5 `SearchIndexWriter`**: ① `replaceUnits`에 빈 목록 = 소유자 표시 유지(S-6) ② `rects`는 CORE가 정밀도를 줄여 저장할 수 있음(M-1 — 예: 쪽의 1/65535) ③ CP-3 `pdfPageAspect`. PDF가 기대는 의미라 계약 주석에 올린다.
- **C-6. 7.8 A-1·B-1의 현실성**: A-1 '1차·2차 노트가 남아 있음'은 1차 APK가 노트를 저장하지 못했으므로 성립하지 않는다(S-11). B-1 '통합 미리보기 배포 직후'는 미리보기 출처에 실제 노트가 없어 확인할 수 없다(M-3) — 'v1 데이터가 있는 출처에 배포한 직후'로 고친다.
- **C-7. 7.2.7 `math`의 `engine`(선택)** → '항상 씀, 없으면 null'로(S-7).
- **C-8. CP-INK-4**는 CORE 동작(1차 7.2.3 `Stroke.transformed`)을 바꾸는 제안이다. 영향 영역에 CORE가 있으므로 총괄 결정 때 CORE 의견을 함께 받는다(X-3).
- **C-9. CP-15(검색 테이블 표 정정)는 정보용**이다(7.2.7 '이름은 CORE가 바꿀 수 있음'). M-1을 반영하면 `rects` 열이 바뀌므로 같은 정정에 포함한다.

---

## 질문

| # | 질문 | 왜 |
|---|---|---|
| Q-1 | 사용자의 1차 실제 노트는 어느 출처(live 채널 / 어느 미리보기 채널)에 있고, 그 DB는 어느 빌드로 처음 만들었는가(1차 통합 전 미리보기 빌드인가) | M-3 — 2차를 어디에 먼저 배포해야 실제 이주를 확인하는지, V7 고정 자료가 그 DB를 대표하는지 |
| Q-2 | V7 고정 자료는 1차 통합 **완료** 커밋에서 만들어야 한다. 지금 1차 통합은 SYNC·PDF·INFRA 단계가 진행 중이다(HEAD `6c470ab`). 생성 시점·담당을 기반 단계 일정에 넣을 것인가 | 12.2 Q2의 기본값 '1차 통합 완료 태그'가 아직 없다 |
| Q-3 | M-1의 사각형 저장 방식으로 BlobStore 분리와 양자화 중 무엇을 기본으로 할 것인가(PDF와 합의) | 크기·질의 비용·구현량의 균형 |
| Q-4 | 안드로이드 태블릿이 실제로 있는가(U2) | A 체크리스트를 '코드만'으로 둘지 |
