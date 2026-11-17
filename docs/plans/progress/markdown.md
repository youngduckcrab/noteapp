# MD (MD 문서 v1) 진행 기록

계획: [m5-7/08-markdown.md](../m5-7/08-markdown.md) · 계약 행: m5-7/00-overview 7.9 v2.17-md C217M-01~17.

## 요약

- (2026-11-17, 트랙 A — 브랜치 `track/md-data`, worktree) 데이터 · 저장소 · 동기화 · 검색 · 라이브러리 · 가져오기/내보내기 · 경로 끝. A-1~A-15, A-17(측정) 처리. 통합(I)은 트랙 B 병합 뒤.
- 기반(F-1~F-9)은 본 checkout에 커밋되지 않은 채 있었다 → 트랙 A 브랜치 첫 커밋 `31e7ef2`로 **글자 그대로 옮겨** 그 위에서 작업했다(본 브랜치는 건드리지 않음). 트랙 B도 같은 기반을 따로 옮겼다면 같은 내용이라 병합 때 충돌하지 않는다 — 다르면 기반 쪽을 하나로 맞춰야 한다.

## 트랙 A 작업 표

| ID | 상태 | 내용 · 시험 |
|---|---|---|
| A-1 | 완료 | `EntityKind.markdown` · `MarkdownText`(id `md_<noteId>`, JSON 7키), `EntityJson.decode`, row_mappers · drift_sync_store · drift_trash_repository · 가짜 저장소 · 백업 골든(`backup_v2.json`에 MD 문서 하나) · JSON 골든 `markdown.json`. 저장된 노트의 형식 범위(ink ↔ MD)를 바꾸는 원격 노트 쓰기 → `ArgumentError`(SYNC는 malformedRemoteData로 그 기록만 거름) |
| A-2 | 완료 | DB v3: `md_docs`(+ `idx_md_note`), `upgradeV2ToV3`(표 · 인덱스만, 사본 없음), `drift_schema_v3.json` · `note_database.steps.dart` · 생성 시험 `schema_v3.dart`. 시험: 생성 이전 시험 1→2 · 1→3 · 2→3, v2→v3 행 보존, v2→v3 실패 주입 → v2 그대로(md_docs 없음), V7 v1 고정물 → v3 한 번에 + v1 사본, `schema_v2_test`(16표 · v3 json) |
| A-3 | 완료 | `DriftMarkdownRepository`: create(노트 + 본문 한 job), saveText(같은 글 unchanged / base 다르면 저장된 글을 사본으로 남기고 씀, outbox `['text']` + noteId 힌트, 노트 updated_at은 로컬 값), watch/get, preview(SQL `substr`). 공유 계약 `test/shared/markdown_contract.dart` — 가짜(`fake_markdown_test`)와 실제(`markdown_contract_real_test`) 모두 통과 |
| A-4 | 완료 | copyItems · duplicateNoteForRecovery(본문 복사, 본문 없으면 빈 본문), 영구 삭제 · 자동 정리 · RemotePurge(`deleteNoteContents`가 md_docs · outbox markdown · 검색 소유자 · `md.conflictCopy.<id>` kv까지) |
| A-5 | 완료 | openSession 거절(기반), NoteMigrator가 MD 문서를 건드리지 않음 시험 |
| A-6 | 완료 | 가짜: 본문 쓰기가 `EntityKind.markdown` 바뀜도 알림, 복제 · 영구 삭제 · 검색(메모리 색인 markdown 소유자 · 생존 판정) · rebuild · 백업 |
| A-7 | 완료 | `SearchSource.markdown`(무게 1.0), `MarkdownIndexText.units`(빈 줄 블록, 펜스 · `$$` 한 블록, 머리말 따로, 가벼운 정리, 1,000자 넘으면 나눔 — 자르지 않음), 쓰기 훅(savepoint) · pending 다시 하기 · rebuild(`indexMarkdownChunk`), 생존 SQL(`notes` 휴지통 밖, pages 조인 없음). feature_library · feature_editor 빠짐없는 switch 팔('문서'), `searchRequeryOf` markdown = 지연 |
| A-8 | 완료 | `MarkdownImport.decode`: UTF-8만, 앞 BOM 보존(Dart 디코더가 떼므로 직접 셈), NUL → notText, CP949 · 외톨이 서로게이트 → notUtf8, 상한 → tooLarge, 제목(확장자 뗌 · 한글 자모 합성 · 흔한 이름이면 머리말 title → 첫 h1 → '가져온 문서', 200자) |
| A-9 | 완료 | L2 = `SyncStore.keepMarkdownConflictCopy`(CORE 판정 + 사본, 10분 안 다시 쓰기, base := 받은 판본), base 갱신 셋(원격 적용 · 사본 · `OutboxAck.uploadedTextVersion`). `test/sync/md_conflict_copy_test.dart` 8개(받은 쪽 이김 · 로컬 이김 · 같은 글 · 재전달 · 자기 기록 · 안 올린 것 없음 · 10분 묶기/휴지통 사본 · 같은 기록 두 번) |
| A-10 | 완료 | FieldUnits(units {noteId} {text} {deletedAt}) · scopes · kindOrder 끝 · record_gate `_purged` · purge_guard `_editedInOutbox` markdown 팔, 업로드 ack에 `uploadedTextVersion`, 다운로드 파이프라인 `markdownGuard`(PurgeGuard 바로 뒤) → `MarkdownConflictCopied` 알림, 가짜 SyncStore · 하네스, 기록 크기 시험(상한 글 4종 < 1,000,000 B) |
| A-11 | 완료 | `test/integration/core_markdown_test.dart`(실제 v3 저장소 둘 + 엔진): M1 전달(BOM · CRLF · 검색), M2 동시 수정 → 수렴 + 사본 정확히 하나 + 알림 하나, M3 같은 글 → 사본 없음, M4 휴지통 대 수정, M5 영구 삭제 대 안 올린 수정 → 본문 든 복구 사본, M6 markdown을 모르는 기기 → 노트만, 본문 없음(읽기 전용) |
| A-12 | 완료 | `core_json_keys_test`에 markdown 골든 |
| A-13 | 완료 | `PickedTextFile` · `TextFileSource` · `FilePickerTextSource`(md · markdown · txt, 여러 개, 웹은 첫 호출을 기다림 없이, 네이티브는 필터 실패 시 아무 파일 + 확장자 검사), `DocumentFile` · `DocumentOutputAction` · `DocumentShareFile` · `DocumentFileOutput` · `createPlatformDocumentOutput`(기존 output_sink 세 파일 안 — 플랫폼 파일 규칙상 같은 조건부 export로), PDF 쪽 저장 대화 · 다운로드 · 공유 실패 해석을 함수로 빼서 같이 씀(`PdfOutputSink` 표면 그대로) |
| A-14 | 완료 | 새로 만들기 '새 MD 문서'(이름 대화 → create → 편집으로) · 'MD 가져오기'(자리, 실행 중 꺼짐), `LibraryScreen.onOpenMarkdown(id, {query, edit})`, MD 카드(`inkSwatch` 글 페이지 + 'MD' 표, 미리보기 30초 캐시, 썸네일 건너뜀), 목록 줄 메타 '문서 · N KB', ⋯ 메뉴(표지 · PDF 빼고 '.md로 내보내기'), 여러 개 PDF 내보내기에서 MD 문서 빼고 알림, 검색 MD 줄(키 `library.hit.markdown.<id>`, '문서') → 검색어와 함께 열기. 시험 `markdown_library_test` 7개 |
| A-15 | 완료(링크 열기 제외) | `/md/:noteId?q=&edit=1`, `MarkdownRouteArgs`, `markdownRoute`, `AppNavigator.openMarkdown`/`closeMarkdown`, deferred `feature_markdown.dart`(정적 Future + 불렸음 표시), `/notes/<MD>` → `/md/` redirect(`isMarkdownNote`, 저장소 없으면 동기 false), 열 때 `markOpened`(최근), `markdown_wiring.dart`(가져오기 20개 · 메시지 · 내보내기 시트 · 바이트 그대로), `document_share_native.dart`, FeatureWiringModule이 자리 셋 덮음. 시험 `markdown_routing_test` 5개 · `markdown_wiring_test` 9개 + 기존 override 순서 시험 갱신 |
| A-16 | 완료 | 이 기록, 계획 상태 줄 · 20절 |
| A-17 | 측정 | 아래 '웹 예산' |

## 웹 예산 (A-17)

- 측정: `cd app && flutter build web --release` → `ws web-budget check`(dart:io gzip).
- 기반 커밋 `31e7ef2`: main.dart.js **6,866,730 B raw / 2,026,031 B gzip**(이미 상한 2,000,000 위 — 기반 몫 포함).
- 트랙 A 끝(`track/md-data`): **6,935,929 / 2,044,504** → **+69,199 raw / +18,473 gzip**. `main.dart.js_1.part.js` 1,778 B(기반 임시 화면뿐 — 파서는 트랙 B 화면이 쓰기 시작하면 part로 감). 게이트: `main.dart.js` 상한 **over**(이전부터), 기준 대비 증가 +141,535 < +300,000 ok, 글꼴 ok.
- 늘어난 것의 대부분: drift 생성 코드(`md_docs` 표 + `Schema3` 단계 도우미 — `note_database.steps.dart` +15 KB 원문), 라이브러리 MD 카드 · 메뉴 · 흐름, `DocumentFileOutput`, 경로 · 연결. 계획 17절대로 **상한 올리기는 총괄 판단**(숫자 보고만).
- Hosting: `app/firebase.json` `**` → `Cache-Control: no-cache` — part 파일도 매번 재검증이라 main과 어긋날 일 없음.
- APK: 이 컨테이너에 Android SDK가 없어 빌드하지 못함 — 네이티브 `loadLibrary()` 즉시 완료는 VM 시험(`markdown_routing_test`의 `MarkdownScreenLoader.isLoaded`)으로만 확인. 실기기 체크리스트에 남김.
- 라이선스: 빌드된 `assets/NOTICES`에 `markdown` 항목 있음(Flutter가 pub 의존 LICENSE를 모음).

## 계획과 다르게 한 점

- L2 판정 자리: 계획대로 SYNC가 적용 **전**에 CORE에 묻는다 — 새 공개 메서드는 `SyncStore.keepMarkdownConflictCopy(MarkdownText, EntityFieldVersions)` 하나(판정 + 사본 + base를 CORE 한 job에서). `RemoteApplyReport`에는 더하지 않았다(알림 `MarkdownConflictCopied`로 앱에 감).
- `MarkdownImport`가 `MarkdownImport.titleFor` · `composeHangul`(시험용) · `fallbackTitle` · `genericNames`도 가진다. `PickedTextFile`은 `{name, bytes}` 대신 PDF처럼 `{name, sizeBytes, readBytes}`(큰 파일을 읽기 전에 거름).
- pdf_io 새 공개 이름이 계획(5개)보다 많다: `DocumentFile` · `DocumentOutputAction` · `DocumentShareFile`(출력 포트에 필요). 구현은 기존 `output_sink_{native,browser,stub}.dart` 안(플랫폼 파일은 조건부 export 두 곳으로만 — `no_platform_imports_test`).
- 링크 열기(url_launcher, Q1): **넣지 않았다** — Q1이 승인되지 않았다. `markdownOpenLinkProvider`는 null(링크 시트는 복사만). 승인되면 앱에 `url_launcher: 6.3.3` 한 줄 + 자리 하나.
- SQLite 드라이버가 TEXT 열의 앞 BOM을 읽을 때 뗀다(Dart `utf8.decode`) → `markdownTextOf`가 `text_bytes`와의 차이로 되돌린다(실제 저장소 왕복 시험).
- 노트 고르기에서 MD 빼기: 라이브러리에 다른 노트를 고르는 곳이 없다('이 노트에 가져오기'는 필기 편집기 안에서만 — MD 문서는 편집기로 안 열림). 할 일 없음.
- 본문 없는 문서의 '복제' 끄기는 하지 않았다 — 복제는 빈 본문으로 만들어 잃을 글이 없다(4.5). '.md로 내보내기'는 본문이 없으면 알림만.
- `entityTooLarge` 격리 알림: 기존 SYNC 문제 보고(`entityTooLarge` 이슈)에 맡겼다 — MD 전용 문구는 앱 연결(M4) 때.

## 확인 (트랙 A 끝)

- `dart run tool/ws.dart check --strict` 0 · 0, 루트 `flutter analyze` 0, `dart format` 0 변경, `dart test tool/test` 566 통과.
- note_core VM 전부 통과(이전 1,273 + 새 시험), sync_engine(integration 포함) 통과, pdf_io · feature_library · app 통과 — 수치는 커밋 메시지와 최종 보고.
- 통합(I) · 실기기 체크리스트 8항목은 트랙 B 병합 뒤.
