# 08 · MARKDOWN — MD 문서 v1 (선택안 ①: 파일 그대로 앱 안에서 보기 · 고치기)

> 상태: **기반 구현됨 · 검토 반영 · 트랙 A(데이터 · 동기화 · 검색 · 라이브러리 · 경로) 구현됨 · 트랙 A 검토 반영(`track/md-data`, 20 · 21절 · progress/markdown.md) · 트랙 B(화면) 구현됨 · 트랙 B 코드 검토 반영(8.12 · 19.1) · 통합(22절) · 오너 시각 검토(23절) · 세로 글씨 버그 고침 `0af6469` · 블록 바로 편집(24절, 계약 v2.18-md C218M-01~C218M-10 — 설계 검토 반영 24.15 · 구현 24.16)** · 작성 2026-11-17 · 영역 ID **MD** · 바탕 HEAD `c100b05`(브랜치 `claude/note-app-planning-bk29xb`), 설계 `47e2fc3`, 기반 커밋 `31e7ef2`(트랙 B의 `658f361`과 트리 같음) · 계약 행: 00-overview 7.9 **v2.17-md C217M-01~C217M-17**(이 문서 14절과 같음). 이 문서와 00-overview 7장이 다르면 7장이 우선한다. 데이터 · UX 검토 37건의 판정은 19절.
>
> 오너 요청: 'PDF뿐만 아니라 md파일도 읽을 수 있으면 좋겠다' → 오너 선택: **md 파일 자체를 앱 안에서 쓴다(필기 노트로 바꾸지 않음)**, 범위 **①**. ②(블록마다 펜 필기)와 ③(원본 파일과 살아 있는 연결)은 뒤 라운드다.
>
> 표기: [확인] = 이번에 코드·명령으로 직접 확인함, [추측] = 확인하지 못한 판단(맡은 트랙이 처음에 확인한다).

## 목차

1. 목적과 범위
2. 조사 결과 (근거)
3. 결정 요약
4. 저장 모델
5. 동기화
6. 검색
7. 패키지 배치 · 의존 규칙
8. 보기 · 편집 화면 (렌더링 방식, 편집, 자동 저장)
9. 라이브러리
10. 가져오기 · 내보내기
11. 라우팅
12. 공개 API (기반 단계에서 얼리는 것)
13. 키 이름
14. 계약 행 v2.17-md (00-overview 7.9에 더할 표)
15. 작업 분해 — 기반 · 트랙 A(데이터) · 트랙 B(화면)
16. 수용 시험
17. 웹 예산
18. 위험 · 열린 질문
19. 검토 반영 내역
20. 트랙 A 구현 기록
21. 트랙 A 검토 반영
22. 통합
23. 오너 시각 검토
24. 블록 바로 편집 — 보기 상태에서 고치기 (설계, v2.18-md)

---

## 1. 목적과 범위

### 1.1 이번 범위 (v1)

- 라이브러리에 새 문서 종류 **'MD 문서'**. 노트처럼 폴더 · 홈 · 최근 · 즐겨찾기 · 휴지통에 나오고, 이름 바꾸기 · 옮기기 · 복제 · 삭제 · 되살리기 · 영구 삭제가 된다. 카드 · 표지는 필기 노트와 다르게 보인다(본문 첫 줄 미리보기 + 'MD' 표시).
- 들어오는 길: '새로 만들기' 메뉴 → **'MD 가져오기'**(`.md` · `.markdown` · `.txt`, 여러 개 한 번에) · **'새 MD 문서'**(빈 문서).
- 열면 **보기**(렌더링): 제목 h1~h6, 문단, 강조(굵게 · 기울임 · 취소선), 링크(누르면 묻고 — 열기 또는 복사, 저절로 네트워크에 가지 않음), 목록(중첩 · 번호 · 할 일 `[ ]` `[x]` — 체크 상자를 누르면 원문이 바뀜), 인용, 코드(인라인 · 펜스, 고정폭, 가로 스크롤), 표(GFM, 가로 스크롤), 가로줄, 수식 `$…$` · `$$…$$`(앱의 KaTeX 렌더러 — `MathPreview`), 이미지(원격 URL은 **가져오지 않음** — 대체 글 자리 표시, `data:` 이미지만 그림). 편집기 스타일(크래프트 · 미니멀 · 스튜디오) · 밝게/어둡게 · 한국어 · 태블릿에서 넓고 편한 읽기 폭 · 폰도 됨.
- 버튼 하나로 **보기 ↔ 편집**(원문 그대로 고치는 고정폭 편집기, 자동 저장(지연 저장), 되돌리기 · 다시 하기, 뒤로 가기 · 앱 종료에도 잃지 않음). 넓은 가로 태블릿에서 **나란히(편집 + 미리보기)** 는 있으면 좋은 것(B-12).
- 라이브러리 검색이 MD 문서 본문을 찾고, 결과를 누르면 그 문서의 맞는 곳으로 간다.
- **'.md로 내보내기'**: 원문을 바이트 그대로(UTF-8) 공유 · 저장, 파일 이름은 제목에서.
- 앱 안에 **사본**으로 저장. 원본 파일과의 연결 없음(③은 뒤). 펜 필기 없음(②는 뒤) — 다만 블록마다 필기를 뒤에 붙일 수 있게 저장 모델에 자리를 둔다(4.7).
- 동기화: 기존 동기화 엔진에 넣는다(5절의 근거와 규칙). 실연결(M4)은 여전히 이번 범위 밖이다.

### 1.2 이번에 하지 않음

- 펜 주석(②), 원본 파일 연결 · 다시 읽기(③), HTML 렌더링(원시 HTML은 글자 그대로 보임), Mermaid 등 다이어그램, 원격 이미지 내려받기, 문서 안 찾기 창(라이브러리 검색만), MD → PDF 내보내기, 다른 앱에서 '공유로 열기'(PDF도 아직 없음 — `PdfIncomingFileSource`가 빈 스트림).

---

## 2. 조사 결과 (근거)

### 2.1 note_core

- [확인] 'PDF 노트'는 따로 된 종류가 아니다: `Note` + 배경이 PDF인 `Page`(`PageBackground` 'pdf', `pages.bg_asset_id`). 라이브러리 · 휴지통 · 최근 · 즐겨찾기 · 검색 · 복제 · 영구 삭제는 모두 `Note` 단위로 짜여 있다(`LibraryRepository`, `TrashRepository`, `LibraryListing.notes`, `NoteRef`, `TrashItem`).
- [확인] `EntityKind`(`lib/src/model/sync_entity.dart`)는 10개이고 `EntityJson.decode`, `row_mappers`, `drift_sync_store`, `drift_trash_repository`, `fake_note_store` 등에서 **빠짐없는 switch**로 쓰인다. 2차에서 `handwriting`(노트에 딸린, 결정적 id `hw_<pageId>`)을 더한 선례가 있다(R2-B7a).
- [확인] 저장소 스키마는 drift v2(`kDatabaseSchemaVersion = 2`, `drift_schemas/note_db/drift_schema_v{1,2}.json`, `migrations.dart` `kSchemaSteps = {1: upgradeV1ToV2}`). 새 표 · 새 열은 v3 단계로 더한다(빌드 러너는 CORE만 돌림 — 계약 7.4.7).
- [확인] 노트 내용 형식 판본: `Note.schemaVersion`, `kNoteSchemaVersion = 1`, `requiresNewerApp => schemaVersion > kNoteSchemaVersion` → 세션 읽기 전용 + 라이브러리 메타 '새 버전 앱 필요'(`note_meta.dart`, `read_only_banner.dart`).
- [확인] 검색 색인: `SearchSource {ink, pdf, text, math}`, `PageSearchHit(noteId, pageId, …)`. 실제 색인의 생존 판정 SQL은 `pages p JOIN notes n ON p.id = u.page_id`(`drift_search_index.dart` 380~395줄) — 페이지가 없는 문서는 지금 그대로는 걸리지 않는다. `SearchText`는 공개(`note_core.dart` export).
- [확인] 필드 판본 `EntityFieldVersions`(필드마다 HLC), 바깥 쓰기는 outbox(`changedFields`).

### 2.2 sync_engine

- [확인] 엔진은 종류 표로 **일반화**되어 있다: `FieldUnits.keysOf/groupsOf/wholeUnitExcept`, `SyncScopes.scopeOf`, `ChunkPacker.kindOrder`, `SyncDoc.ownerId` — 모두 `EntityKind` 빠짐없는 switch. 새 종류는 표에 행을 더하면 코덱 · 병합 · 게이트가 그대로 쓴다.
- [확인] 모르는 종류의 기록은 청크째 버리지 않고 **그 기록만 보류**(`UnknownKindRecord`, `isKnownKind` — S-13). 옛 앱이 새 종류를 받아도 잃지 않는다.
- [확인] 기록 하나의 청크 상한 `chunkHardLimitBytes = 1000000`, 넘으면 `entityTooLarge`로 격리(로컬에만) — 본문 크기 상한의 근거(4.4).
- [확인] 앱은 아직 `sync_engine`에 의존하지 않는다(`app/pubspec.yaml`, `workspace_rules.yaml` 주석 — 실연결 M4에서). 즉 v1에서 실제로 오가는 동기화는 없고, 형식 · 병합 규칙 · 시험만 맞춘다.

### 2.3 feature_library · app · pdf_io

- [확인] '새로 만들기' = `new_menu_button.dart`(새 노트 · 새 폴더 · PDF 가져오기). PDF 가져오기는 **자리(slot) provider**(`libraryPdfImportActionProvider`)를 앱이 덮어써서 연결(`integration/pdf_slots.dart`, `pdf_flows.dart` — 실행 중 표시, 오류 보고).
- [확인] 노트 열기: `LibraryScreen(onOpenNote, onOpenNoteAt)` → 앱 `AppNavigator` → `/notes/:noteId?page=&focus=`(`app_routes.dart`, `app_router.dart`). 편집기 경로는 `wrapEditor`(= `EditorStyleScope` — 필기 화면 스타일)로 감싼다.
- [확인] 파일 고르기는 `pdf_io`만 가진다: `FilePickerPdfSource`(file_picker 13.3.2, 웹은 탭 처리기 안에서 동기 호출). R16: `file_picker` 예외는 `pdf_io`뿐이고 **늘릴 수 없다**(`r16BaselineExceptions`), 새 멤버는 플러그인 없음 목록에 든다.
- [확인] 내보내기 출력: `PdfOutputSink`(네이티브 = 저장 대화상자 `FilePicker.saveFile` + 앱이 주는 공유 `PdfShareFiles`(share_plus, `app/lib/src/modules/pdf_share_native.dart`), 웹 = Web Share · 다운로드 · 새 탭). 형식이 `PdfExportResult`(mime 'application/pdf' 고정)에 묶여 있다. 파일 이름 정리 `PdfFileNaming.sanitize`.
- [확인] `url_launcher 6.3.3`은 이미 잠금 파일에 있다(pdfrx의 간접 의존) — 앱이 직접 의존해도 잠금 변화 없음.

### 2.4 ink_engine · ui_kit

- [확인] 수식: `InkMathRenderer.validate(latex)`(오류 문장 또는 null), `MathPreview(latex, fontSize, color, onError)` — 래스터가 아닌 위젯 트리(flutter_math_fork `Math.tex`), 크기가 바뀌어도 선명. `layout()`은 프레임 단계 밖에서만(S-9) — 화면은 `MathPreview`만 쓴다.
- [확인] `StyleTokens.of(context)`(canvas, card, paperInk, textPrimary/Secondary/Tertiary, accent, accentSoft, outline, hairline, radius*, toolbarHeight …), `AppIcon`/`AppIconKind`(메뉴 전용 뜻은 Material 둥근 글리프로 충분), 새 날 색 금지(`tool/test/ui_colors_test.dart`).

### 2.5 마크다운 파서

- [확인] pub.dev 접속 됨. `markdown` 7.3.1(dart-lang, 순수 Dart, 2026-03-18 공개 — 14일 규칙 통과), 의존 `args ^2.0.0` · `meta ^1.3.0`(둘 다 이미 고정 2.7.0 · 1.19.0) → 잠금에 **`markdown` 한 줄만** 더해진다. GFM 표 · 할 일 목록(`UnorderedListWithCheckboxSyntax`/`OrderedListWithCheckboxSyntax`) · 취소선 · 자동 링크 · 각주 포함, 수식 문법은 없음(직접 `InlineSyntax`/`BlockSyntax`). AST에 원문 위치가 없다(할 일 토글은 8.5의 원문 훑기로).
- [확인] 크기 측정(스크래치 — `dart compile js -O4`, 파서 + GFM + AST 걷기): **211,240 B raw / 69,547 B gzip**, 빈 프로그램 31,315 / 10,337 B → 파서 몫 약 **+59 KB gzip**. 웹 예산은 이미 약 2 KB 넘어 있다 → **지연 import(deferred) 필수**(17절).
- `flutter_markdown`은 단종 — 쓰지 않는다. 위젯은 직접 만든다.

---

## 3. 결정 요약

| # | 결정 | 이유 |
|---|---|---|
| D1 | MD 문서 = **`Note`(format = markdown) + 본문 엔티티 `MarkdownText`(새 `EntityKind.markdown`, id `md_<noteId>`)** | 라이브러리 · 휴지통 · 최근 · 즐겨찾기 · 이동 · 복제가 전부 `Note` 단위 — 그대로 얻는다. 본문을 따로 두면 노트 행은 가볍고(목록), 본문 병합 단위가 분명하다. `handwriting` 선례 |
| D2 | 본문은 **열 하나(TEXT)**, 블롭/에셋 아님. 상한 **400,000 바이트(UTF-8)** 그리고 JSON 문자열로 **900,000 바이트** | 청크 상한 1,000,000 B. 제어 문자는 `\u00XX`로 6배가 되므로 인코딩 크기도 봄(검토 D4). 보통 문서는 10~50 KB |
| D3 | 형식 = **`Note.schemaVersion`의 범위**(1~99 필기 · 100~199 MD · ≥200 뒤 형식), MD 문서는 `kMarkdownNoteSchemaVersion = 100`. 새 필드 · JSON 키 · 열 없음 | 복사 · 복구 · 변환 길이 모두 `schemaVersion`을 이미 넘김 → 형식이 떨어져 나갈 길이 없음(검토 D6). 100은 옛 앱 보호막: 옛 앱은 `requiresNewerApp`으로 읽기 전용 → 페이지를 더하지 못함 |
| D4 | **동기화한다**(로컬 전용 아님). 본문 `text`는 한 단위 LWW + **두 겹의 충돌 사본** 규칙(이 기기 안 `saveText` base 검사, 받을 때 SYNC 판정) | 새 `EntityKind`는 어차피 sync_engine의 빠짐없는 switch를 고쳐야 한다. 로컬 전용이면 노트는 동기화되고 본문은 안 가서 **다른 기기에서 문서가 통째로 빈 채** — 요구 위반. 5절 |
| D5 | 화면은 새 패키지 **`packages/feature_markdown`**(의존 note_core · ink_engine · ui_kit, 플러그인 없음) | 편집기(잉크)와 라이브러리에 파서 · 렌더러를 섞지 않음. 7.1 규칙: 기능 패키지끼리 import 안 함. 웹에서 패키지째 지연 로드 가능 |
| D6 | 파서 = **`markdown` 7.3.1** + 직접 만든 위젯. 수식 = `MathPreview` | 순수 Dart, 의존 추가 없음, GFM. 2.5 |
| D7 | 경로 **`/md/:noteId?q=<검색어>`**. `/notes/:id`로 MD 문서가 오면 `/md/:id`로 돌림 | 편집기(NoteSession)가 MD 문서를 열면 안 됨(페이지를 만들 수 있음). CORE도 막음(4.5) |
| D8 | 파일 고르기 · 저장은 **pdf_io**에 일반 파일 도우미를 더하고, 공유 · 외부 링크 열기는 **앱**(share_plus · url_launcher) | R16: file_picker는 pdf_io만. 앱은 이미 share_plus를 직접 가짐, url_launcher는 잠금에 이미 있음 |
| D9 | 웹은 `feature_markdown` 화면을 **deferred import** | 파서 +59 KB gzip을 main.dart.js 밖으로 |

---

## 4. 저장 모델

### 4.1 `Note`의 형식 (기반 — 구현됨)

```dart
// note_core lib/src/model/note.dart (구현됨)
const int kMarkdownNoteSchemaVersion = 100;     // MD 문서의 Note.schemaVersion
const int kLaterNoteFormatSchemaVersion = 200;  // 뒤 형식 몫의 첫 값
enum NoteFormat { ink, markdown, unknown;
  static NoteFormat ofSchemaVersion(int v); }   // <100 ink · 100~199 markdown · ≥200 unknown
// Note (필드 · JSON 키 · 열 추가 없음)
NoteFormat get format => NoteFormat.ofSchemaVersion(schemaVersion);
bool get isMarkdown => format == NoteFormat.markdown;
bool get requiresNewerApp => switch (format) {
  ink => schemaVersion > kNoteSchemaVersion,
  markdown => schemaVersion > kMarkdownNoteSchemaVersion,
  unknown => true };
```

- **형식은 `schemaVersion`의 범위에서 나온다**(검토 D6 · D13 반영 — 처음 안의 `Note.format` 필드 + JSON `'format'` 키 + `notes.format` 열을 버림). 근거: 노트를 복사하거나 다시 만드는 길(`copyNote` · 가짜 복사 · `duplicateNoteForRecovery` · 행/JSON 변환 · 동기화)이 모두 `schemaVersion`을 이미 그대로 넘긴다 → 기본값 ink로 떨어져 MD 문서가 '열 수 없는 필기 노트'가 되는 길이 생기지 않는다. 노트 JSON · 골든 · `FieldUnits.keysOf(note)` · `core_json_keys_test`가 바뀌지 않는다.
- 필기 형식 판본은 1~99에 머문다(지금 1). `NoteMigrator`는 `schemaVersion >= kNoteSchemaVersion`이면 건너뛰므로 MD 문서를 저절로 건드리지 않는다 [확인 note_migrator.dart 61줄].
- 동기화 병합은 노트 `schemaVersion`을 '큰 값'으로 합친다(`field_merge.dart`) — 한 노트 id는 한 형식으로만 만들어지므로 범위를 넘을 일이 없다. CORE는 **저장된 노트의 형식 범위를 바꾸는 원격 쓰기를 거절**한다(malformed로 건너뜀 — 트랙 A, A-1).
- MD 문서의 `cover`는 `FirstPageCover`(카드가 따로 그림), `pageCount` 0, `firstPageId` null. `toString`에 ', markdown'.
- `openSession`은 MD 문서에 `WrongNoteFormatException`(기반에서 가짜 · 실제 저장소 둘 다 구현됨). 형식 `unknown`(≥200)은 '새 버전 앱 필요'로 읽기 전용 — 라이브러리는 지금처럼 열지 않는다.

### 4.2 `MarkdownText` 엔티티 (트랙 A)

```dart
final class MarkdownText implements SyncEntity { // EntityKind.markdown (wire name 'markdown')
  static String idFor(NoteId noteId) => 'md_$noteId';
  final String id;        // = idFor(noteId), 결정적 (isValidEntityId 통과 — 64자 이내 확인)
  final NoteId noteId;
  final String text;      // 원문 그대로(BOM · CRLF 포함), MarkdownLimits.check 통과
  final EpochMillis createdAt, updatedAt;
  final EpochMillis? deletedAt; // v1은 쓰지 않음(휴지통은 노트 단위) — 키는 다른 종류와 같게 둠
  final Hlc? version;
}
// JSON 키: id, noteId, text, createdAt, updatedAt, deletedAt, version
```

결정적 id라서 두 기기가 같은 문서의 본문을 따로 만들 일이 없다.

### 4.3 DB 스키마 v3 (트랙 A)

`kDatabaseSchemaVersion = 3`, `kSchemaSteps = {1: upgradeV1ToV2, 2: upgradeV2ToV3}`, `drift_schema_v3.json` · 생성 단계 파일 · 이전 시험은 CORE 방식 그대로. **`notes`에 열을 더하지 않는다**(형식은 `schema_version`에서 — 4.1).

- 새 표 `md_docs`:

| 열 | 형 | 뜻 |
|---|---|---|
| id | TEXT PK | `md_<noteId>` |
| note_id | TEXT | 인덱스 `idx_md_note(note_id)` |
| text | TEXT | 본문 |
| created_at · updated_at | INTEGER | |
| deleted_at | INTEGER NULL | |
| version | TEXT | = versions.max |
| field_versions | TEXT NULL | 7.2.10 |
| text_bytes | INTEGER | 로컬 · 파생(UTF-8 바이트 — 저장 공간 표시) |
| base_text_version | TEXT NULL | **로컬 전용**: 이 기기가 서버에 있다고 아는 `text`의 필드 판본(5.3). outbox · 백업 · `kLocalOnlyFields`에 넣어 밖으로 안 감 |

- 이전 전 사본(검토 D14): `NoteDatabase.onUpgrade`는 `from == 1`일 때만 v1 사본을 만든다. v2→v3는 **표 하나 더하기만**이고 한 트랜잭션이라 사본을 만들지 않는다 — 실패하면 v2 그대로 남는다(롤백). 시험: v2 고정물 → v3 실패 주입 → v2 그대로, v1 고정물 → v3 한 번에 → v1 사본이 생김.
- v3에서 내려가기는 기존 규칙(`NewerSchemaError`)으로 막힌다.

### 4.4 크기 상한 · 판본 (기반 — 구현됨)

```dart
abstract final class MarkdownLimits {
  static const int maxTextBytes = 400000;    // UTF-8 바이트(원문 그대로)
  static const int maxEncodedBytes = 900000; // JSON 문자열로 쓴 UTF-8 바이트(동기화 기록 한 개)
  static const int maxImportFiles = 20;
  static const int previewChars = 400;
  static int utf8BytesOf(String text);       // 인코딩 없이 셈(외톨이 서로게이트 = 3)
  static int encodedBytesOf(String text);    // utf8(jsonEncode(text)) 길이
  static void check(String text);            // 넘으면 MarkdownTooLargeException
}
// common/errors.dart (sealed NoteCoreException의 하위형은 이 파일에만 둘 수 있음 — 검토 D7)
final class MarkdownTooLargeException extends NoteCoreException { final int bytes, encodedBytes; }
final class WrongNoteFormatException extends NoteCoreException {}
```

- 두 상한을 모두 본다(검토 D4): `jsonEncode`는 C0 제어 문자를 `\u00XX`(6바이트)로 쓰므로 400 KB 원문이 1 MB 기록 상한을 넘을 수 있다. `maxEncodedBytes` 900,000은 나머지 키 · 필드 판본에 100 KB를 남긴다. 트랙 A는 실제 `ChunkCodec.encodeRecord` 길이와 `encodedBytesOf`의 차이가 그 여유 안인지 시험한다(A-10).
- 만들기 · 저장 · 가져오기 · 충돌 사본이 모두 **바꾸기 전에** `check`를 부른다 → 넘으면 아무것도 안 바뀐다. 편집기는 글을 그대로 들고 띠를 보인다(8.7).
- 그래도 기록이 `entityTooLarge`로 격리되면(형식 바뀜 등) 일반 동기화 문제 보고가 알린다. **MD 전용 문구는 두지 않음 — 받아들인 차이(21절)**. 노트만 가고 본문이 안 가는 상태는 받은 쪽에서 읽기 전용 + 띠(5.3 끝)로 보인다.
- 판본: 쓰기 한 번 = `text` 필드 HLC 하나(outbox `changedFields ['text']`, **noteId 힌트 포함** — 5.2 purge 판정), 노트의 `updatedAt`도 올림. 되돌리기 기록은 CORE `HistoryState`에 넣지 않는다(편집기 안 — 8.7).

### 4.5 CORE 규칙 (트랙 A, 가짜는 기반에서 구현됨)

- `MarkdownRepository.create`: `Note`(schemaVersion 100, 제목 규칙 = createNote) + `MarkdownText`를 **한 트랜잭션**으로.
- `saveText(id, text, {required Hlc? baseVersion})`(검토 D1 · U6): 같은 글 → `unchanged`. 저장된 판본 == `baseVersion` → `saved`. 다르면(그 사이 다른 기기 글이 들어왔거나 다른 쓰기가 있었음) **저장된 글을 먼저 충돌 사본으로 남기고** 받은 글을 쓴다 → `savedWithConflictCopy(conflictCopyId)`. 한 트랜잭션. 열린 편집기 · 할 일 토글 · 나란히 미리보기가 모두 이 길만 쓴다 → 다른 기기 글을 덮어쓰고 잃는 길이 없다.
- `copyItems`(복제) · `duplicateNoteForRecovery`: 본문을 새 id로 복사. 본문이 아직 없는 문서(`bodyPresent false`)의 복제는 빈 본문으로 만든다(잃을 글이 없음). 라이브러리는 '복제'를 끄지 않는다 — 받아들인 차이(21절).
- 휴지통: 노트만. 영구 삭제(purge · 자동 정리 · `RemotePurge`): 본문 행 + 검색 소유자 함께 삭제.
- `openSession`: MD 문서면 `WrongNoteFormatException`(기반 구현). `NoteMigrator`: 4.1대로 저절로 건너뜀 — 시험만(A-5).
- 저장된 노트의 형식 범위를 바꾸는 원격 쓰기 거절(4.1).
- 백업 내보내기: `EntityKind.values` 순서라 저절로 들어감(골든 갱신). `base_text_version`·`text_bytes`는 빠짐.

### 4.6 원문 보존 규칙 (BOM · 줄 끝)

- 저장은 원문 그대로: U+FEFF(BOM)와 `\r\n`도 `text`에 남긴다 → 손대지 않고 내보내면 **바이트가 같다**.
- 편집기(트랙 B)는 BOM을 떼고 `\r\n`→`\n`으로 보여 주고, 저장할 때 되돌린다(`LineEndingCodec`). 섞인 줄 끝 파일은 편집 전에는 그대로, 한 번 편집하면 많은 쪽으로 통일(18절 R2).
- **모든 위치 계산(할 일 표시 · 검색 이동 · 블록 원문 범위)은 편집기의 풀린 글(LF, BOM 없음) 기준**이다(검토 U6). 저장된 원문에서 직접 위치를 재지 않는다.

### 4.7 뒤에 블록마다 필기(②)를 붙일 자리

- v1 MD 문서는 페이지 0장. ②에서는 같은 노트의 `Page`(+ `Stroke`/`PageObject`)를 '주석 페이지'로 쓰고, 페이지에 새 키 `mdAnchor {blockKey, textHash}`를 단다.
- **블록 = 우리가 만든 최상위 블록 나누기(`BlockSplitter`, 트랙 B)가 원문에서 자른 범위**(검토 U8 — `markdown` 패키지 AST에는 원문 위치가 없음 [확인]): 펜스 코드(``` · ~~~, 닫힐 때까지) · `$$` 수식 · 빈 줄 · 목록/인용 이어짐 · 표(머리줄 + 구분줄 + 이어진 `|` 줄) · 앞의 YAML 머리말을 규칙대로 자르고, 각 범위를 따로 파싱한다. 범위가 있으니 검색 이동 · 보기↔편집 위치 옮기기 · 할 일 위치가 모두 같은 표를 쓴다.
- `blockKey` = 블록 원문(앞뒤 공백 정리, LF)의 SHA-1 앞 8자 + 같은 해시 안에서의 순번 — 위쪽을 고쳐도 아래 블록 키가 안 바뀐다. v1은 저장하지 않고 화면 안에서만 쓴다.
- v1 규칙: MD 문서에 페이지가 있어도(뒤 버전 앱이 만든 것) 지우지도 보여 주지도 않는다. 복제 · 영구 삭제는 기존 노트 규칙대로 페이지도 함께.

---

## 5. 동기화

### 5.1 결정과 근거

**동기화한다.** 근거:

1. 엔진은 종류 표로 일반화되어 있다(2.2) — `handwriting`도 같은 방식으로 들어왔다.
2. 새 `EntityKind`를 더하면 sync_engine의 빠짐없는 switch를 어차피 고쳐야 한다 — '로컬 전용'으로 해도 이 비용은 그대로이고, outbox를 건너뛰는 장치가 더 든다.
3. 로컬 전용이면 노트(schemaVersion 100)는 동기화되는데 본문은 안 간다 → 다른 기기에 **빈 문서**, 거기서 고치면 원래 본문과 영영 갈린다. '문서를 통째로 조용히 잃지 않음'을 지키려면 본문도 같이 가야 한다.

비용: sync_engine 표 + 보호 장치 + 시험(트랙 A, A-10~A-12). 실연결은 여전히 M4.

### 5.2 표 행 (트랙 A — sync_engine · note_core)

| 곳 | markdown 행 |
|---|---|
| `FieldUnits.keysOf` | `{id, noteId, text, createdAt, updatedAt, deletedAt, version}` (노트 행은 그대로 — 4.1) |
| `groupsOf` · `wholeUnitExcept` | `const []` · `null` → 단위 `{noteId}` · `{text}` · `{deletedAt}` |
| `SyncScopes.scopeOf` | `json['noteId']` → `noteIdHint` → `'lib'` (handwriting과 같음) |
| `ChunkPacker.kindOrder` | 맨 끝 |
| `SyncDoc.ownerId` | null (노트로) |
| `record_gate._purged` (빠짐없는 switch) | `json['noteId']` 팔 — 영구 삭제된 노트의 본문을 거름(검토 D9 — 처음 안의 '저절로 걸림'은 틀림) |
| `purge_guard._editedInOutbox` (`default:`가 있어 컴파일이 안 잡음) | **`EntityKind.markdown` 팔 = `e.noteId`**(outbox 쓰기가 noteId 힌트를 가짐 — 4.4) → 안 올린 MD 수정이 있으면 영구 삭제 전에 `duplicateNoteForRecovery`(본문 복사 — 4.5)로 살림(검토 D2) |
| outbox `kLocalOnlyFields` | `text_bytes`, `base_text_version` |
| `applyRemote`의 '고친 노트의 updatedAt 올리기' | 본문 기록의 `noteId`도 넣음 — 다른 기기의 최근 순서가 맞게 |
| feature_library `search_requery.dart` (빠짐없는 switch) | markdown = 내용 바뀜으로 다시 찾기(지연) |

### 5.3 충돌 규칙 (문서 전체를 조용히 잃지 않기)

`text`는 한 단위 LWW다. 그것만으로는 동시 수정에서 진 쪽 글이 사라진다. 그래서 두 곳에서 지킨다.

**L1 — 이 기기 안(CORE, 기반에서 계약 고정)**: `saveText`의 `baseVersion` 검사(4.5). 받은 글이 편집기 디바운스 중에 들어와도, 받은 쪽이 이긴 뒤 편집기가 옛 버퍼로 저장해도, 저장된 글이 사본으로 남는다(검토 D1의 두 경우).

**L2 — 받기(SYNC 쪽에서 판정, PurgeGuard와 같은 자리 — 검토 D12)**: 다운로드 파이프라인이 markdown 업서트를 적용하기 **전에** CORE에 묻는다(`SyncStore`의 새 내부 메서드 — A 안에서만): 로컬 행이 있고 · 로컬 outbox에 안 올린 `text`가 있고 · 받은 `text` ≠ 로컬 `text` 이고 · **받은 `text` 판본 > `base_text_version` 이고 그 HLC 노드가 이 기기(`deviceNodeId`)가 아님**(검토 D3a — 같거나 옛 판본의 재전달 · 압축 스냅숏 · 보류 해제 · 내 기록은 동시 수정이 아님). 참이면:

- 진 쪽 글(받은 쪽이 이기면 로컬 글, 로컬이 이기면 받은 글 — 한 필드 단위의 병합 규칙, 새 판본이 이김)을 새 MD 문서 `MarkdownConflictCopy.titleFor(제목, 지금)`에 바이트 그대로 남긴다(같은 폴더, 로컬 쓰기 — 다른 기기에도 감).
- **두 번 판정한다(트랙 A 검토 A1 · B2)**: 엔진이 적용 전에 `SyncStore.keepMarkdownConflictCopy(remote, versions)`를 부른다(자기 job — 사본 id가 돌아와 알림을 낼 수 있음). 이 단계는 base를 올리지 않고 비교한 판본 쌍(받은 판본 · 저장된 판본)을 kv `md.guarded.<noteId>`에 적는다. 그다음 `applyRemote`가 **같은 job 안에서, 그 순간의 행으로** 같은 규칙을 다시 본다: 판본 쌍이 그대로면 이미 처리됨, 사이에 편집기 자동 저장이 끼었으면(저장된 판본이 바뀜) 다시 판정해 진 쪽 글을 사본으로 남긴다. 앞 단계를 거치지 않은 적용도 같은 규칙을 탄다. 적용 안에서 만든 사본은 로컬 변경(ChangeBatch local · outbox)이고 알림은 없다(드묾 — 라이브러리에 '(충돌 사본 …)'으로 보임).
- 그리고 적용 job에서 **`base_text_version` := 받은 판본**(검토 D3b — 갈라짐 하나에 사본 하나), `md.guarded` 지움.
- **사본은 다시 쓰지 않는다**(트랙 A 검토 A2 · A3 · B1 · B3): 사본은 사용자가 고칠 수 있는 보통 MD 문서이고, 한 사본에 들어간 진 쪽 글이 다음 진 쪽 글의 조상이라는 보장이 없다(받은 쪽이 이긴 뒤 사용자는 받은 글을 고침). 사본 폭주는 이렇게만 막는다: 같은 문서에 이 기기가 10분 안에 만든 사본(kv `md.conflictCopy.<noteId>` = 사본 id + 시각)이 살아 있고 **진 쪽 글과 똑같으면** 새로 만들지 않고 그 사본을 가리킨다. 아니면 새 사본 — 두 기기가 계속 칠 때 사본이 여럿 생길 수 있지만 글은 하나도 사라지지 않는다.
- `SyncNotice` `MarkdownConflictCopied(noteId, copyId)` → 앱이 '다른 기기에서 고친 글을 사본으로 남겼어요' 알림(검토 D12). `RemoteApplyReport`에는 더하지 않음.
- 받은 본문에 `deletedAt`이 있으면(v1은 쓰지 않음 — 뒤 판 · 잘못된 기록) 본문 없음과 같이 읽기 전용(`bodyMissing`), 검색에서도 빠짐(트랙 A 검토 A4).
- `base_text_version` 갱신 셋: (1) 받은 글을 쓸 때 = 받은 판본, (2) 사본을 만들 때 = 받은 판본, (3) 올린 것이 확인될 때 = **올린 기록의 `text` 필드 판본**. (3)은 `OutboxAck`가 `(seq, rev)`만 가지고 outbox `hlc`가 합쳐질 때 덮이므로(검토 D3c), SYNC가 올린 기록에서 그 판본을 읽어 `OutboxAck.uploadedTextVersion`(선택 필드, markdown 기록만)으로 넘기고 CORE는 `max(base, 그 값)`으로 둔다. 업로드 중에 계속 친 경우(rev가 바뀌어 행이 안 지워짐)에도 base는 올린 판본으로 맞는다.

나머지:

- 한쪽 휴지통 + 다른 쪽 수정 → 단위가 달라 둘 다 반영(휴지통 안 문서가 최신 글).
- 한쪽 **영구 삭제** + 다른 쪽 안 올린 수정 → PurgeGuard가 복구 사본을 만든다(5.2, 검토 D2 — 처음 안의 '되살리지 않음, 받아들임'은 틀림). 시나리오 시험 S08-md.
- 노트가 본문보다 먼저 도착: `MarkdownDoc.bodyPresent = false` → 읽기 전용(`MarkdownReadOnlyReason.bodyMissing`). 본문이 보류 · 격리되어 오래 안 오면(화면이 2분 넘게 본 상태) 띠 문구가 '아직 내용을 받지 못했어요 — 다른 기기에서 이 문서를 한 번 열어 주세요'로 바뀐다(B-10, 검토 D15).

### 5.4 옛 앱(이 판 이전)과 섞일 때

- `markdown` 기록 → 모르는 종류로 보류(잃지 않음) [확인 S-13].
- MD 노트 → 옛 앱은 `schemaVersion 100 > 1` → 읽기 전용 · '새 버전 앱 필요'. 옛 앱이 이름만 바꿔 올려도 필드 단위 병합이라 `schemaVersion`은 그대로(큰 값).

---

## 6. 검색 (트랙 A)

- `SearchSource`에 **`markdown`**(빠짐없는 switch: feature_library `library_strings.dart` · `search_requery.dart`(5.2) · feature_editor `note_search_panel.dart` · `editor_strings.dart`, 이름 '문서').
- 소유자: `source 'markdown'`, `ownerKey = noteId`, `note_id = noteId`, `page_id = MarkdownText.idFor(noteId)`(히트의 `pageId`), `sourceRev = '<본문 version>:<normalizerVersion>'`. 본문 쓰기의 SAVEPOINT 안에서 색인(C-13 — 실패하면 소유자만 pending).
- **다시 세우기 · 다시 하기**(검토 D5): `DriftSearchIndex.rebuild()`에 `indexMarkdownChunk` 고리(정규화 판본이 바뀌어 저장소를 열 때 전부 다시 세우는 길), pending 소유자 다시 하기에 markdown 분기. 시험: rebuild 뒤 MD 본문 낱말이 그대로 찾아짐.
- 단위(`MarkdownIndexText.units`, note_core 내부, 파서 없음): 4.7과 같은 규칙으로 블록을 나누고 가벼운 정리(`MarkdownPreviewText`와 같은 정규식 — 머리말 · 기호 · 링크 주소 · HTML 태그 뗌, 펜스 안 코드는 그대로). **블록이 1,000자를 넘으면 1,000자씩 여러 단위로 나눈다**(검토 D10 — 자르지 않음). 시험: 1,000자 뒤의 낱말이 찾아짐.
- 생존 판정 SQL 분기: `WHEN u.source = 'markdown' THEN (SELECT n.updated_at FROM notes n WHERE n.id = u.note_id AND n.deleted_at IS NULL AND n.owner_id = ?)`. 사각형 없음. 가짜 메모리 색인도 같은 판정(CP-14).
- 라이브러리 결과: 본문 맞음은 '노트 내용' 묶음에 **MD 줄**(문서 아이콘 + 조각) → `onOpenMarkdown(noteId, query: 검색어)`.
- 문서 안 이동(트랙 B, 8.8): 맞는 곳을 **원문(편집기 글)에서** 찾고 4.7의 블록 범위로 블록에 맞춘다(검토 U17 — 색인 정리와 화면 평문이 달라 못 찾는 일을 없앰).

---

## 7. 패키지 배치 · 의존 규칙

### 7.1 새 패키지 `packages/feature_markdown` (기반 — 만들어짐)

- 의존: `note_core`, `ink_engine`, `ui_kit`(형제, `any`), `flutter_riverpod 3.4.3`, `material_ui 1.10.0`, `markdown 7.3.1`, `meta 1.19.0`, `collection 1.19.1`, `crypto 3.0.8`(blockKey). 개발 의존: `flutter_test`, `fake_async 1.3.3`(검토 D15 — 트랙 B가 pubspec을 바꾸지 않게 미리 넣음). `crypto` · `collection` · `fake_async`는 이미 잠금에 있음.
- 진입점 둘:
  - `package:feature_markdown/feature_markdown.dart` — `MarkdownScreen`, `MarkdownKeys`. **웹에서 지연 import** 대상.
  - `package:feature_markdown/slots.dart` — 자리 provider와 typedef만(파서 · 화면 import 없음 — api_surface 시험이 따라가며 확인). 앱은 이것만 즉시 import한다.
- `ink_engine`을 쓰는 곳은 `MathPreview` · `InkMathRenderer.validate`뿐.

### 7.2 `tool/workspace_rules.yaml` (기반 — 바뀜)

```yaml
allowed_dependencies:
  feature_markdown: [note_core, ink_engine, ui_kit]
  noteapp: [..., ui_kit, feature_markdown]
plugin_free_members: [..., ui_kit, feature_markdown]
pinned_external:
  markdown: 7.3.1                            # (v2.17-md) feature_markdown direct
  # url_launcher: 6.3.3 — 트랙 A가 앱에 넣을 때(Q1, 잠금 그대로)
```

- 루트 `pubspec.yaml` `workspace:` 끝에 `packages/feature_markdown`, 앱 `pubspec.yaml`에 `feature_markdown: any`(아직 import 없음 — A가 연결). 잠금은 `markdown 7.3.1` 한 줄만 더해짐 [확인].
- `tool/test/ui_colors_test.dart` · `ui_icons_test.dart` 훑는 목록에 `packages/feature_markdown/lib`, `rules_test` · `workspace_test` · `cli_process_test` · `affected_test` · `export_names_test` 기대 목록에 새 멤버.
- `url_launcher`를 앱에 직접 넣는 것은 규칙상 되지만 계약 정신('새 플러그인은 서비스 패키지')과 맞는지 총괄 판단 → 18절 Q1. 기본값: 넣는다(이미 앱이 해석하는 플러그인 — `plugin_packages`에 있음). 안 되면 '복사'만.

---

## 8. 보기 · 편집 화면 (트랙 B)

### 8.1 구성

```
packages/feature_markdown/lib/
  feature_markdown.dart          # MarkdownScreen, MarkdownKeys (기반에서 고정)
  slots.dart                     # 자리 provider · typedef (기반에서 고정)
  src/
    markdown_keys.dart           # 13절 키 (기반에서 고정 — 더하기만)
    slots_impl.dart              # 자리 둘 (기반에서 고정)
    markdown_screen.dart         # (기반 임시 화면 → B가 바꿈) Scaffold, 위 막대, 모드, 띠, 떠나기 대화
    screen/markdown_controller.dart # 문서 상태의 유일한 주인: 풀린 버퍼, base 판본, dirty, 저장 상태, 모드
    parse/block_splitter.dart    # 4.7 최상위 블록 + 원문 범위 (머리말 · 펜스 · $$ · 목록 · 인용 · 표)
    parse/md_document.dart       # 블록마다 markdown.Document 파싱 + 수식 문법
    parse/math_syntax.dart       # $…$, \(…\), $$…$$(한 줄 포함), \[…\], ```math
    parse/html_lite.dart         # 원시 HTML 작은 허용 목록(8.2)
    parse/task_marks.dart        # 블록 범위 안의 할 일 표시 위치 (8.5)
    parse/block_keys.dart        # blockKey
    render/md_view.dart          # 블록 ListView.builder (큰 목록 · 표는 항목 · 행 단위로 쪼갬 — 8.11)
    render/md_blocks.dart · md_inline.dart · md_code.dart · md_table.dart · md_math.dart
    render/md_image.dart · md_link.dart · md_style.dart · front_matter.dart
    edit/md_editor.dart          # 고정폭 TextField(expands) + 기호 줄
    edit/bounded_undo.dart       # 상한 있는 되돌리기 기록 (8.7)
    edit/autosave.dart · line_endings.dart
    strings_ko.dart
```

### 8.2 파서 설정

- 블록 나누기(4.7) 뒤 블록마다 `markdown.Document(extensionSet: ExtensionSet.gitHubFlavored, encodeHtml: false, blockSyntaxes: [MathBlockSyntax()], inlineSyntaxes: [MathInlineSyntax()])`. `gitHubWeb`은 쓰지 않는다(이모지 표가 큼). 각주 정의는 블록을 넘어가므로 문서 전체에서 한 번 모아 넘긴다.
- 수식: 인라인 `$x$` — 여는 `$` 뒤와 닫는 `$` 앞이 공백 아님, 닫는 `$` 뒤가 숫자 아님(pandoc — '$5 and $6' 보호), `\$`는 글자. `\(…\)`도 인라인. 블록 = `$$` 줄 쌍, **한 줄 `$$ … $$`**, `\[…\]`, ` ```math ` 펜스(검토 U20). 코드 안의 `$`는 코드.
- **YAML 머리말**(검토 U10): 문서 첫 줄 `---` … `---`/`...`는 접힌 작은 '정보' 상자(기본 접힘, 키 `md.frontMatter`)로 — 가로줄 + 제목으로 잘못 보이지 않게.
- **원시 HTML 작은 허용 목록**(검토 U10, `html_lite.dart`): `<br>` → 줄바꿈, `<img src alt>` → 8.3 이미지 규칙(원격은 안 가져옴), `<details>/<summary>` → 접는 상자(**v1 구현: 안 글만 — 8.12**), `<b> <i> <em> <strong> <code> <sub> <sup> <kbd>` → 해당 모양, `<p align>` · `<div>` · `<span>` → 안 글만. 그 밖의 태그는 떼고 안 글만. 스크립트 · 스타일 · iframe은 안 글도 버림. HTML은 실행하지 않는다.
- 문서가 50 KB를 넘으면 파싱을 `compute`로(웹은 같은 스레드), 입력 중 미리보기는 200 ms 지연. 블록 나누기는 원문 범위가 같은 블록의 파싱 결과를 다시 쓴다(고친 블록만 다시 파싱).
- 줄바꿈: GFM 기본(한 줄바꿈은 띄어쓰기). '줄바꿈 그대로 보기' 설정은 v1에 넣지 않는다(검토 U20 — 19절 거절 사유).

### 8.3 렌더링 규칙 (색은 모두 `StyleTokens`/`ColorScheme`, 새 날 색 금지)

| 요소 | 그리는 법 |
|---|---|
| 바탕 | 화면 전체 `toolbar`(토큰 뜻 '전체 화면' — 검토 U14, `canvas`는 쓰지 않음), 본문 열 최대 720 px 가운데, 본문 글자 16 px(태블릿 — 짧은 변 ≥ 600 — 은 17 px, 제목도 같은 비율 — 23절) |
| 제목 h1~h6 | `TextTheme` headline/title, h1·h2 아래 `hairline` 선 |
| 문단 | `bodyLarge`, 줄 높이 1.6, `textPrimary` |
| 강조 · 취소선 | w700 · italic · lineThrough |
| 인라인 코드 | 고정폭, `accentSoft` 바탕 + **`onAccentSoft` 글자**, `radiusSmall` |
| 펜스 코드 | `card` 바탕 + `hairline` 테두리, 고정폭, **가로 스크롤**(줄 바꿈 안 함), 언어 이름(없으면 머리 줄 없이 [복사]가 코드 옆 — 23절), [복사](`AppIconKind.copyText`). 문법 색칠 없음 |
| 표 | **가로 스크롤**, 머리줄 w600 + `card` 바탕, 정렬 지킴, 칸 폭 48~320 px. **100행 넘는 표는 앞 100행 + [더 보기](100행씩, 키 `md.table.<i>.more`), 칸 폭은 머리줄 + 앞 40행 표본으로 한 번 재서 고정**(8.11 · 19.1 A7) |
| 목록 | 중첩 24 px씩, 글머리 깊이마다 ● ○ ■, 번호 시작 지킴 |
| 할 일 | 체크 상자(누를 곳 48 dp 이상 — 8.5), 끝난 항목 `textSecondary` |
| 인용 | 왼쪽 4 px `accent` 띠 + `textSecondary` |
| 가로줄 | `hairline` 1 px |
| 수식 | 인라인 `WidgetSpan(MathPreview(fontSize = 본문 크기, color = textPrimary), alignment: middle)`, 블록은 가운데 + 가로 스크롤. `validate` 오류면 원문을 코드 모양 + `colorScheme.error` |
| 이미지 | 원격(`http(s)://` 등): **가져오지 않음** — 점선(`outline`) 상자 + 대체 글 + 호스트 + '이미지를 불러오지 않았어요'(`AppIconKind.imageBlocked`). `data:image/(png|jpeg|gif|webp);base64`이고 풀린 크기 ≤ 2 MB면 `Image.memory` — **풀기는 블록 파싱 때 한 번, 결과를 캐시**(검토 U20). 상대 경로: '원본 파일의 이미지는 가져오지 않았어요' |
| 링크 | **`textPrimary` 글자 + `accent` 밑줄 2 px**(검토 U14 — `accent`는 글자 대비 보장이 없음). 누르면 8.6 |
| 검색 강조 | `accentSoft` 채움 + `accent` 1.5 px 테두리, 맞은 **낱말만**(블록 전체 아님 — 검토 U14 · U17). **v1 구현은 맞은 낱말이 든 블록 전체를 3초 강조**(8.12) |
| 각주 | 위첨자 번호, 문서 끝 각주 목록 |

- 편집기 스타일(`EditorStyleScope`)과 밝게/어둡게를 따른다. 좌우 여백 폰 16 / 태블릿 32, 시스템 글자 배율을 따름. 보기 모드는 `SelectionArea`(터치는 길게 눌러 고르기).
- 골든: 크래프트 · 미니멀 · 스튜디오 × 밝게 · 어둡게 × 폰 390 · 태블릿 1194 가로 = **12장**(검토 U22) + 폰 편집 모드 글자 배율 1.3 한 장 + 링크 · 인라인 코드 · 강조 대비 시험(6 테마 모두 4.5:1).

### 8.4 위 막대 · 메뉴 · 뒤로

> **v2.18-md(24절)**: 모드 단추는 보기 ↔ **원문**(옛 '편집'), 보기에서도 고칠 수 있으면 [↶][↷]. 뒤로 순서는 ① 시트 ② 열린 블록 확정 ③ 원문/나란히 → 보기 ④ 닫기(24.8). 아래 글의 '편집'은 원문 모드를 뜻한다.


- 넓을 때(본문 폭 ≥ 600): [←] 제목(누르면 이름 바꾸기 — `libraryRepository.renameNote`) · **[보기|편집] 단추 하나**(아이콘 `viewRendered`/`editSource` + 글) · (≥ 1,100 가로) [나란히] · 편집 중 [↶][↷] · 저장 상태 글('저장됨' / '저장 중…' / '저장하지 못했어요') · [⋯].
- **좁을 때(< 600 — 폰, 검토 U12)**: 모드 단추도 글을 단다(아이콘 + '보기'/'편집', 좌우 여백만 줄임 — 오너 시각 검토 23절, 아이콘만이면 못 찾음), 저장 상태는 아이콘(툴팁 · 의미 이름), [↶][↷]는 기호 줄로 옮김. 390 px · 글자 배율 1.3에서 넘침 없음(골든).
- [⋯]: '.md로 내보내기'(자리가 있을 때) · '이름 바꾸기' · '정보'(글자 수 · 바이트 · 수정 시각).
- 나란히 모드에서 모드 단추 = '나란히 끄기'(편집으로 돌아감)(검토 U22).
- **뒤로 순서**(검토 U22, 편집기 `editor_screen.dart`의 순서와 같음): ① 열린 시트 · 메뉴 닫기 ② 편집/나란히 모드면 보기로(저장 비우기) ③ 화면 닫기. 저장이 실패한 채면 ③ 대신 8.7의 떠나기 대화. **위 막대 [←]도 시스템 뒤로와 같은 순서**다(19.1 B8).
- 새 문서(`initialEdit`)는 편집으로, 그 밖은 보기로 연다.
- 읽기 전용(`MarkdownDoc.readOnlyReason`: 휴지통 · 새 버전 · 본문 없음, 그리고 8.7의 편집 상한)이면 편집 단추가 꺼지고 이유 띠(13절 키).

### 8.5 할 일 체크 상자 토글

- 위치 찾기: `TaskMarks.scan`이 **각 블록의 원문 범위 안에서**(4.7) 줄을 훑는다(펜스 · 들여쓴 코드(목록 항목 안의 들여쓴 코드도) · HTML 블록 건너뜀, `>` 접두 허용(목록 항목 안에서는 들여쓴 `>`도), `^\s*(?:[-*+]|\d+[.)])\s+\[( |x|X)\]`). 블록마다 **훑은 상자가 파서의 상자와 같을 때만** 그 블록의 토글을 켠다: 수가 같고, 상자마다 `[` 표시 `]`가 있고, 체크 상태가 파서와 같고, 상자 뒤 글의 첫 낱말이 그 항목 글의 첫 낱말과 같다(`TaskMarks.matches` — 수만 같으면 다른 줄(코드 안)을 고칠 수 있었음, 19.1 A4). 어긋나면 그 블록만 보이기만, 개발자 로그 한 줄. `toggleTaskAt`도 `[` 표시 `]`를 다시 확인한다.
- **모든 바뀜은 컨트롤러의 풀린 버퍼를 거친다**(검토 U6): 토글 = 버퍼에서 그 글자를 `' '`↔`'x'`로 바꾸는 편집 하나 → 되돌리기 기록에 들어감 → 자동 저장 길(바로 비우기). 나란히 모드에서 미리보기의 상자를 눌러도 같은 편집이라 입력 중인 글과 부딪히지 않는다. 보기는 `watch`가 아니라 **버퍼**를 그린다(편집→보기 때 옛 글이 번쩍이지 않음).
- 실수 막기(검토 U7): 토글 뒤 4초 '할 일을 바꿨어요 [되돌리기]'(키 `md.taskUndo`). [되돌리기]는 **버퍼가 토글 직후 그대로일 때만** 상자를 되돌린다(그 사이 입력 · 다른 기기 글 · 다른 토글로 위치가 움직였으면 아무것도 안 함 — 19.1 A3). 누를 곳 48 dp 이상. 손바닥 거부 설정이 켜져 있으면 `PointerDeviceKind.unknown`은 무시(**v1 구현 안 됨 — 8.12**).

### 8.6 링크

- 누르면 바닥 시트(`md.linkSheet`): 주소 전체 + [복사](`copyText`) + (자리 `markdownOpenLinkProvider`가 있고 스킴이 `http`/`https`/`mailto`/`tel`일 때) [외부 앱에서 열기](`openExternal`) + [취소]. 저절로 여는 일 없음. `#제목` 링크는 문서 안 제목으로 스크롤. 그 밖 스킴(`javascript:`, `file:`, `intent:` …)은 복사만.

### 8.7 편집 · 자동 저장 · 되돌리기

> **v2.18-md(24절)**: 원문 편집기는 보기에서 마운트하지 않는다(Offstage로 남기지 않음 — `0af6469`의 세로 글씨 원인 자리). 보기의 블록 입력 칸은 같은 버퍼 · 자동 저장 · 되돌리기 기록에 쓴다(24.3 · 24.6 · 24.15). 원문 글자당 약 480 ms(100 KB, VM)에 비해 블록 입력 칸은 문서 크기와 상관없이 약 14 ms(24.16).


- 편집기: 여러 줄 `TextField`(`expands: true`, `maxLines: null` — 스스로 스크롤해 커서가 키보드 위에 남음), 고정폭, `autocorrect: false`, `enableSuggestions: false`, 같은 읽기 폭, 줄 높이 1.5.
- **기호 줄**(검토 U11, 키 `md.accessory`): 편집 중 키보드 위에 `#` `-` `[ ]` `*` `` ` `` `$` `|` `>` [들여쓰기][내어쓰기](`indent`/`outdent`) (+ 좁을 때 [↶][↷]). 하드웨어 키보드 Tab / Shift+Tab = 지금 목록 줄 들여쓰기 / 내어쓰기(포커스가 밖으로 나가지 않음).
- **편집 상한**(검토 U3): 풀린 글이 **150,000 UTF-16 단위**를 넘으면 편집기를 열지 않고 보기 전용 + 띠 `md.banner.tooLargeToEdit`('이 문서는 너무 길어서 앱에서 고칠 수 없어요 — 보기만 돼요'). 값은 B-13 측정(100 KB · 400 KB 문서의 글자당 프레임 시간)으로 정하고 바꿀 수 있다 — 저장 상한(400 KB)과 따로. **측정(VM 디버그, `perf_test` 'one keystroke…')**: 글자 하나에 100 KB 중앙값 약 520 ms, 149,900 단위 약 750 ms(대부분 Flutter `TextField` 배치). 400 KB(저장 상한) 문서는 보기 전용으로 열리고 첫 그림 약 120 ms. 릴리스 · 실기기 수치가 없어 상한은 150,000 그대로 두고 **오너 태블릿 체크(15.4)에서 100 KB 입력이 끊기면 내린다**.
- **자동 저장**: 마지막 입력 뒤 **700 ms**, 계속 입력 중이면 최대 **5 s**마다 한 번. 저장하는 글 = `value.text`(조합 중인 글자 포함 — 조합 범위는 저장과 상관없음). **IME 조합 중에는 지연 저장만 최대 1 s 미룬다**(검토 U2 — 한국어 키보드는 마지막 글자를 조합 상태로 오래 둠). **즉시 비우기**(보기로 바꿈, 뒤로, dispose, `AppLifecycleListener` onHide · onPause · onDetach)는 조합을 무시하고 바로 저장한 뒤 `noteStore.flush()`.
- 저장 = `saveText(id, 인코딩한 버퍼, baseVersion: 컨트롤러의 base)`. 결과의 `textVersion`이 다음 base. `savedWithConflictCopy`면 띠 `md.banner.conflictCopy`('다른 기기에서 바뀐 글을 사본으로 남겼어요 [사본 열기][닫기]'). [사본 열기](키 `md.banner.conflictCopy.open`)는 앱이 `MarkdownScreen.onOpenMarkdown`을 줄 때만 보이고, 저장 · 비우기 뒤 그 사본 id로 부른다(19.1 B4).
- **들어오는 변경**(`watch`, 검토 U5): ① `textVersion`이 마지막 내 저장의 판본과 같으면 무시(내 메아리), ② `LineEndingCodec.decode(받은 글)` == 버퍼면 base만 갱신, ③ 버퍼가 깨끗하면 받은 글로 바꾸되 **커서 위치 · 스크롤을 지키고**(커서는 바뀐 곳 앞이면 그대로, 뒤면 길이 차만큼 옮김 — `mapOffsetThroughChange`; 보기는 맨 위 블록을 키로 찾아 같은 높이에 둠) **되돌리기 기록은 비운다**(계획의 '외부 변경 한 칸'은 그 칸을 되돌리면 다른 기기 글을 사본 없이 덮으므로 바꿈 — 19.1 A2), ④ 버퍼가 dirty면 반영하지 않음(다음 저장에서 L1이 사본으로 지킴).
- **저장 실패**(쓰기 큐 오류 · `MarkdownTooLargeException`): 글은 편집기에 그대로, 띠 + [다시 시도]. 성공 전에는 '저장됨'을 보이지 않음. **떠나기**(검토 U1 · D11): 뒤로(`PopScope(canPop: false)`)에서 비우기가 실패하면 대화 `md.leave` — [머무르기] / [복사하고 나가기](버퍼를 클립보드에) / [버리고 나가기]. 비우기를 300 ms 넘게 기다리면 '저장 중…' 표시(편집기 `_SavingNotice`와 같음). 앱 일시정지 · 분리 때는 대화를 띄울 수 없으므로 저장을 시도하고, 실패하면 버퍼를 기기 로컬 설정 `markdown.unsaved`(`SettingKey.jsonMap`, **`{<noteId>: {text, base, at}}` — 문서마다 한 칸, 최대 8문서(오래된 것부터 버림), `base` = 그 글이 바탕으로 한 `textVersion`**)에 넣어 다음에 그 문서를 열 때 '저장하지 못한 글이 있어요 [되살리기][버리기]'. 화면이 [←]/뒤로 말고 다른 길로 닫혀(경로 교체 등) dispose의 마지막 저장이 실패해도 같은 칸에 넣는다(19.1 A8). **그 문서의 저장이 나중에 성공하면 이 화면이 넣은 칸은 지운다**(옛 글이 새 글을 덮지 않게 — 19.1 A1). [되살리기]는 칸의 `base`로 저장한다(`restoreText`): 그 사이 다른 기기 글이 들어왔으면 L1이 그 글을 충돌 사본으로 남긴다(19.1 B1). [버리고 나가기]는 정말 버린다(`discard` — dispose의 마지막 저장도 안 함); [복사하고 나가기]는 복사한 뒤에도 dispose에서 저장을 시도하고, 실패하면 칸에 넣는다.
- **되돌리기 · 다시 하기**(검토 U4): Flutter `UndoHistoryController`는 기록 수 상한이 없다 [확인 undo_history.dart 399~437줄] → 직접 `BoundedUndoHistory`(최대 200칸 **그리고** 모든 칸의 글자 합 ≤ 4,000,000 UTF-16 단위, 넘으면 오래된 것부터 버림, 500 ms 묶기 — 타이머라 시험의 가짜 시간과 맞음). Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y와 [↶][↷]는 이 기록으로 간다(`UndoTextIntent` · `RedoTextIntent`를 편집기 위에서 덮음). 할 일 토글 · 되살리기는 한 칸씩. 기록은 화면을 떠나면 사라짐. **필드 자체의 기록**: `TextField` 안의 `UndoHistory`는 끌 수 없고 상한 없이 쌓이므로, 컨트롤러가 그 크기를 어림해(500 ms마다 글 길이) 4,000,000 단위를 넘으면 같은 값의 새 `TextEditingController`로 바꿔 그 기록을 비운다(`renewField` — 조합 중이면 미룸; `UndoHistory`는 값 알림이 바뀌면 기록을 비움 [확인 undo_history.dart didUpdateWidget]).
- **보기 ↔ 편집 위치**(검토 U9): 보기에서 맨 위에 보이는 블록의 원문 시작 → 편집기의 커서 · 스크롤을 그 줄로, 편집에서 커서가 있는 블록 → 보기에서 그 블록을 맨 위로.
- 줄 끝 · BOM: 4.6 코덱. 위치 계산은 모두 풀린 버퍼 기준. **외톨이 CR(옛 Mac) 줄 끝이 가장 많은 파일**은 LF 줄로 보여 주고 CR로 다시 쓴다(19.1 A9). 섞인 줄 끝은 첫 편집에서 많은 쪽으로 맞춘다(18 R2 그대로).

### 8.8 검색 이동

- `initialQuery`가 있으면 첫 프레임 뒤: `SearchText.normalize`로 맞춘 검색어를 **풀린 원문**에서 찾고(검토 U17) 그 위치가 든 블록(4.7 범위)으로 — 추정 높이로 뛰어간 뒤 `ensureVisible`, 맞은 낱말을 3초 강조(`md.highlight`, 8.3). 못 찾으면 맨 위(오류 없음). 시험: 목록 · 표 · 펜스 코드 안의 낱말, 2,000 블록 문서.

### 8.9 나란히(있으면 좋은 것)

> **v2.18-md**: 나란히 = 원문 + 미리보기. 미리보기는 바로 편집하지 않는다(24.1).


- 본문 폭 ≥ 1,100 px · 가로일 때만 [나란히]. 왼쪽 편집, 오른쪽 미리보기(버퍼에서, 200 ms 지연 파싱), 스크롤 연동은 v1 안 함. 선택 상태는 기기 로컬 설정 `markdown.splitView`.

### 8.10 펜(스타일러스)으로 볼 때 (검토 U16)

- 보기에서 펜 끌기 = 스크롤(글 고르기는 길게 누르기). MD 문서에서 처음 펜이 닿으면 한 번만 안내 'MD 문서에는 아직 펜으로 쓸 수 없어요 — 편집에서 글로 고칠 수 있어요'(기기 로컬 설정 `markdown.penHintShown`) — **v1 구현 안 됨(8.12)**.
- 편집기에서 Android 펜 손글씨 → 글자 입력(Scribe/Samsung)이 `autocorrect: false` TextField에서 되는지 실기기 체크리스트에 넣는다.

### 8.11 긴 문서 (검토 U20 · U3)

- 블록 `ListView.builder`. 최상위 목록은 **항목 단위로**(40항목 넘으면 20항목씩) 빌더 자식을 쪼갠다. 표는 행 묶음으로 쪼개면 묶음마다 가로 스크롤이 따로 놀므로 **앞 100행 + [더 보기]**로 바꾸고 칸 폭을 표본으로 고정한다(`IntrinsicColumnWidth`가 칸마다 두 번 재서 500행 표 첫 빌드 4.4 s — 19.1 A7). 시험: 2,000항목 목록에서 첫 그림 시간(perf), 250행 표 [더 보기].
- **띄어쓰기 없는 긴 줄**(19.1 A5): markdown 패키지의 낱말 문법 `[A-Za-z0-9]+(?=\s)`와 GFM 메일 자동 링크 `[-_.+a-z0-9]+@`가 줄의 위치마다 나머지를 다시 훑어 제곱 시간(16,000자 7.6 s, 500,000자는 끝나지 않음). `LongRunSyntax`(`[-_.+/=A-Za-z0-9]{256,}`를 글자 그대로 한 번에)를 GFM 자동 링크 바로 뒤에 둔다 — 주소 · 메일은 그대로 링크. 500,000자 줄 약 0.1 s(시험).
- **닫히지 않은 `$$`**(19.1 A6): pandoc처럼 닫는 `$$`(`\]`)가 뒤에 없으면 수식 블록이 아니라 글(블록 나누기 · `MathBlockSyntax.canParse` 둘 다). 문서 끝까지 사라지지 않음.

### 8.12 트랙 B 구현에서 계획과 다른 점 (2026-11-17, 코드 검토 뒤)

| 계획 | 구현 | 이유 · 뒤 일 |
|---|---|---|
| 검색 강조는 맞은 낱말만(8.3 · 8.8) | 맞은 낱말이 든 **블록 전체**를 3초 강조 | 렌더러가 블록마다 `RichText`라 낱말 범위를 칸에 옮기는 일이 커서 뒤 라운드. 이동 · 블록은 원문 기준으로 맞음 |
| `<details>/<summary>` 접는 상자(8.2) | 태그를 떼고 안 글만(다른 모르는 태그와 같음) | v1 오너 목록에 없음. 접는 상자는 머리말 상자를 다시 써서 뒤에 더함 |
| 처음 펜 안내 `markdown.penHintShown`(8.10) | 없음 | 보기의 펜 끌기는 스크롤로 동작함. 안내 문구는 ②(펜 필기) 라운드와 함께 |
| 할 일 상자의 손바닥 거부(8.5) | 없음(48 dp 상자 + [되돌리기]만) | 편집기의 손바닥 거부 설정을 이 패키지에서 읽을 길이 아직 없음 — 통합(A)에서 자리를 정하면 더함 |
| 들어온 변경 = 되돌리기 한 칸(8.7 ③) | 들어온 변경에서 기록을 비움 | 19.1 A2 |
| 표 50행 묶음 지연 생성(8.11) | 앞 100행 + [더 보기], 표본 칸 폭 | 8.11 |
| `markdown.unsaved` = 마지막 하나(8.7) | 문서마다 한 칸 + `base` | 19.1 A1 · B1 |
| 400 KB 글자당 프레임 측정(B-13) | 400 KB는 편집 상한을 넘어 보기 전용 — 첫 그림만 잼. 글자당은 100 KB · 149,900 단위 | 8.7 |

---

## 9. 라이브러리 (트랙 A — feature_library)

- 목록 · 최근 · 즐겨찾기 · 휴지통: MD 문서도 `Note`라 그대로 나온다.
- **MD 카드**(검토 U15): 표지 자리에 '글 페이지' — 노트 표지처럼 `inkSwatch` 바탕(모든 밝기에서 종이색)에 미리보기 글(첫 줄 굵게 + 다음 몇 줄)을 `paperInk`로(대비 4.5:1 시험 — 모자라면 총괄에 토큰 요청) + 오른쪽 아래 'MD' 표(`accentSoft` 바탕 + `onAccentSoft`, 키 `library.tile.mdBadge`, `AppIconKind.markdownDoc`). 미리보기는 `markdownPreviewProvider((noteId:, updatedAt:))`(기반 구현 — 고친 뒤 옛 미리보기가 안 남음), 그리드 스크롤 깜빡임을 막으려고 라이브러리 쪽에서 30초 캐시. 썸네일 스케줄러는 MD 문서를 건너뜀. 골든: 필기 카드와 섞인 그리드, 스타일 3 × 밝기 2.
- 메타 줄: '문서 · 2.1 KB' — 크기는 `libraryMarkdownSizeProvider((noteId, updatedAt))`로 판본마다 한 번 읽음(본문 watch가 아님 — 다른 쓰기마다 보이는 줄의 본문을 다시 읽지 않음, 검토 B5).
- 메뉴(⋯ · 길게 누름): MD 문서는 'PDF로 내보내기' · '표지 바꾸기'를 빼고 **'.md로 내보내기'**(자리 `libraryMarkdownExportActionProvider`). 본문 없는 문서: '.md로 내보내기'는 눌렀을 때 '아직 내용을 받지 못한 문서는 내보낼 수 없어요', '복제'는 빈 본문으로(끄지 않음 — 21절). 여러 개 'PDF로 내보내기'는 MD 문서를 빼고 'MD 문서 N개는 빼고 내보냈어요'.
- '새로 만들기': '새 노트' · '새 폴더' · **'새 MD 문서'**(`newMarkdown`, 이름 대화 기본 '새 MD 문서' → `MarkdownRepository.create` → 편집으로 엶) · 'PDF 가져오기' · **'MD 가져오기'**(`importMarkdown`, 자리 `libraryMarkdownImportActionProvider`, 실행 중이면 꺼짐).
- 열기: `LibraryScreen.onOpenMarkdown(NoteId id, {String? query, bool edit = false})`. `note.isMarkdown`이면 이것을, 아니면 `onOpenNote`. null이면 `onOpenNote`로(앱이 돌림).
- 다른 노트를 고르는 곳(PDF '이 노트에 가져오기' 대상 등)에서 MD 문서는 고를 수 없음(`isMarkdown` 거름) — 지금 라이브러리에는 노트 고르기가 없어 할 일 없음(20절).

---

## 10. 가져오기 · 내보내기 (트랙 A — pdf_io 일반 파일 도우미 + note_core + 앱)

### 10.1 고르기 (pdf_io)

- 새 공개 `TextFileSource` / `FilePickerTextSource.pickTextFiles({bool allowMultiple = true}) → Future<List<PickedTextFile>?>`(`PickedTextFile{name, bytes}` — PDF 형 이름을 빌리지 않음), `allowedExtensions: ['md','markdown','txt']`. 웹: 탭 처리기 안 동기 호출. Android에서 확장자 필터가 안 먹으면 `FileType.any`로 물러남 [추측 — 실기기 확인]. 고른 파일은 모두 돌려주고 **앱이 파일마다** 확장자(`FilePickerTextSource.hasTextExtension`) · 크기 · 해석을 판정한다(트랙 A 검토 A5).

### 10.2 해석 (note_core, 순수 Dart)

`MarkdownImport.decode(Uint8List bytes, {required String fileName}) → MarkdownDecodeResult`:

- `MarkdownLimits.check`를 넘음 → `tooLarge`('파일이 너무 커요 (최대 400 KB)').
- NUL(0x00) → `notText`.
- UTF-8 아님 → `notUtf8`('UTF-8 텍스트 파일만 가져올 수 있어요 — 메모장에서 UTF-8로 저장한 뒤 다시 가져와 주세요')(검토 U21).
- 성공: `text` = 풀린 글 그대로(BOM 포함). `title` = 파일 이름에서 확장자 뗌 → NFC → 다듬기. 이름이 흔한 것(`README` · `index` · `untitled` · `제목 없음`, 대소문자 무시)이거나 비면 **머리말 `title:` → 첫 h1 → '가져온 문서'** 순으로(검토 U21). 200자로 자름.
- 시험: `utf8.encode(decode(b).text) == b`(BOM · CRLF · 한글 · 이모지 · 4바이트 글자), CP949 바이트, NUL, 제어 문자 많은 파일(encoded 상한).

### 10.3 흐름 (앱 — `app/lib/src/modules/markdown_wiring.dart`)

- 고른 파일마다(최대 20, 넘으면 앞 20개 + 알림) 해석 → `MarkdownRepository.create`. 하나면 그 문서를 연다, 여럿이면 'MD 문서 N개를 가져왔어요' (+ 'M개는 가져오지 못했어요 — 파일 이름: 이유, …'(셋까지, 나머지 '외 K개')). 거절은 파일마다 셈(같은 이름 둘이면 둘).

### 10.4 내보내기

- 바이트 = `utf8.encode(text)`(원문 그대로 → 가져온 그대로면 바이트 같음). 파일 이름 = `PdfFileNaming.sanitize(title)` + (`.md`/`.markdown`으로 안 끝나면) `.md`.
- MIME: **공유는 `text/plain`**(이름은 `.md` 그대로 — 메신저 등이 `text/markdown`을 거르는 일, 검토 U21), 저장 · 다운로드는 `text/markdown`.
- 출력: pdf_io 새 공개 `DocumentFileOutput`/`createPlatformDocumentOutput`(네이티브: `FilePicker.saveFile` + 앱의 공유 함수, 웹: Web Share · 다운로드). 기존 `PdfOutputSink` 내부의 저장 · 다운로드를 바이트 + 이름 + MIME 형으로 빼서 같이 씀(`PdfOutputSink` 공개 표면 그대로). 앱 `document_share_native.dart`(share_plus `XFile.fromData`).
- 작은 시트 '[공유] [저장]'(웹 '[공유] [다운로드]') — 앱이 그림.
- 자리 둘을 같은 앱 함수로: 화면 ⋯(`markdownExportActionProvider`) · 라이브러리 메뉴(`libraryMarkdownExportActionProvider`).

---

## 11. 라우팅 (트랙 A — app)

- `AppRoutes.markdownPattern = '/md/:noteId'`, 쿼리 `q`(검색어) · `edit=1`, `AppRoutes.markdown(noteId, {query, edit})`, `MarkdownRouteArgs`, `AppScreenBuilders.markdown`, `AppNavigator.openMarkdown(id, {query, edit})` · `closeMarkdown()`.
- 페이지: `NoTransitionPage(key: state.pageKey)` + `wrapEditor`(편집기 스타일).
- `/notes/:noteId`에 MD 문서가 오면 `/md/:id`로: **라이브러리 · 검색 · 최근에서 여는 길은 처음부터 `openMarkdown`을 부르므로 DB를 읽지 않는다**(검토 U18 · D15). `createAppRouter(isMarkdownNote:)`의 비동기 redirect는 주소 직접 · 옛 즐겨찾기용 대비책이다. 앱 안의 `AppNavigator.openNote`는 필기 노트에만 불리므로 `extra: AppRoutes.inkNoteExtra`를 달고, redirect는 그 표시를 보면 바로 통과한다(DB 안 읽음 — `noteProvider` 캐시 대신, 라이브러리가 그 캐시를 채우지 않아서; 시험 `markdown_routing_test`).
- `/md/:id`에 필기 노트가 오면 화면이 '이 문서는 MD 문서가 아니에요' + [노트로 열기](`onOpenAsNote`).
- 화면 생성: `deferred as md` → **한 번만 부르는 정적 `Future` + '불렸음' 표시**(검토 U19): 불린 뒤에는 `MarkdownScreen`을 바로 만든다(빈 프레임 없음). 네이티브는 앱 시작 뒤 한가할 때 `loadLibrary()`를 미리 부른다(`FeatureWiringModule` 한가 작업 `featureWiring.markdownScreen`, 우선순위 30 — 웹은 안 부름). 실패한 부르기는 잊고 화면의 [다시 시도]가 다시 부른다(검토 B8 · B9).

---

## 12. 공개 API (기반 단계에서 얼린 것 — 구현됨)

### 12.1 note_core

```dart
// src/model/note.dart — 4.1
const int kMarkdownNoteSchemaVersion = 100;
const int kLaterNoteFormatSchemaVersion = 200;
enum NoteFormat { ink, markdown, unknown; static NoteFormat ofSchemaVersion(int v); }
// Note: + NoteFormat get format, bool get isMarkdown, requiresNewerApp(형식별)

// src/common/errors.dart — 4.4
final class MarkdownTooLargeException extends NoteCoreException { final int bytes, encodedBytes; }
final class WrongNoteFormatException extends NoteCoreException {}

// src/repo/markdown_repository.dart
abstract final class MarkdownLimits { maxTextBytes 400000, maxEncodedBytes 900000, maxImportFiles 20,
  previewChars 400; utf8BytesOf, encodedBytesOf, check }
enum MarkdownReadOnlyReason { trashed, newerApp, bodyMissing }
final class MarkdownDoc { Note note; String text; bool bodyPresent; Hlc? textVersion;
  MarkdownReadOnlyReason? readOnlyReason; bool isReadOnly; }          // ==/hashCode
enum MarkdownSaveOutcome { saved, unchanged, savedWithConflictCopy }
final class MarkdownSaveResult { outcome; Hlc? textVersion; NoteId? conflictCopyId; }
abstract final class MarkdownConflictCopy { static String titleFor(String title, DateTime at); }
abstract final class MarkdownPreviewText { static String of(String text, {int maxChars}); }
typedef MarkdownPreviewKey = ({NoteId noteId, EpochMillis updatedAt});

abstract interface class MarkdownRepository {
  Stream<MarkdownDoc?> watch(NoteId id);   // 없음 · MD 아님 → null, 휴지통 문서는 나옴(읽기 전용)
  Future<MarkdownDoc?> get(NoteId id);
  Future<Note> create({FolderId? folderId, required String title, String text = ''});
  Future<MarkdownSaveResult> saveText(NoteId id, String text, {required Hlc? baseVersion}); // 4.5
  Future<String> preview(NoteId id, {int maxChars = MarkdownLimits.previewChars});
}
// NoteStore: + MarkdownRepository get markdown;
// providers: markdownRepositoryProvider, markdownDocProvider (autoDispose.family<MarkdownDoc?, NoteId>),
//            markdownPreviewProvider (autoDispose.family<String, MarkdownPreviewKey>)

// testing.dart (시험 전용)
abstract final class FakeMarkdownHooks {
  static Future<void> removeBody(NoteStore store, NoteId noteId);           // 본문 아직 안 옴
  static Future<Hlc> remoteText(NoteStore store, NoteId noteId, String text); // 다른 기기 글 도착
}
```

- 가짜 저장소(`createFakeNoteStore`): `markdown` 전부 동작(만들기 · 저장 · 충돌 사본 · 읽기 전용 · 상한 · watch · 미리보기), `copyItems` 본문 복사, 영구 삭제 본문 삭제, `openSession` 거절. 바뀜은 아직 노트의 `EntityChange`로 알린다(`EntityKind.markdown`은 트랙 A).
- 실제 저장소: `DriftNoteStore.markdown` = `DriftMarkdownRepository`(파일 `storage/drift_markdown_repository.dart`) — 지금은 모든 호출이 `UnsupportedError`. 트랙 A가 같은 파일에서 바꾼다. 실제 `openSession` 거절은 구현됨.

### 12.2 feature_markdown

```dart
// feature_markdown.dart (deferred 대상)
class MarkdownScreen extends ConsumerStatefulWidget {
  const MarkdownScreen({super.key, required NoteId noteId, String? initialQuery,
    bool initialEdit = false, required VoidCallback onClose, VoidCallback? onOpenAsNote,
    ValueChanged<NoteId>? onOpenMarkdown}); // 트랙 B가 더함: 충돌 사본 [사본 열기], null → 단추 숨김
}
abstract final class MarkdownKeys { /* 13절 */ }

// slots.dart (파서 · 화면 없음)
typedef MarkdownExportAction = Future<void> Function(BuildContext context, {required String title, required String text});
final markdownExportActionProvider = Provider<MarkdownExportAction?>((ref) => null); // null → 메뉴 숨김
typedef MarkdownOpenLinkAction = Future<bool> Function(Uri uri);  // false = 열지 못함
final markdownOpenLinkProvider = Provider<MarkdownOpenLinkAction?>((ref) => null);    // null → 복사만
```

- 기반의 `MarkdownScreen`은 임시 화면(제목 · 원문 그대로 · 뒤로 · 'MD 문서가 아니에요')이다. 트랙 B가 `src/` 안에서 바꾼다.

### 12.3 ui_kit (AppIconKind 더함, Material 글리프만 — 구현됨)

`markdownDoc`(article), `newMarkdown`(post_add), `importMarkdown`(file_open), `exportMarkdown`(file_download), `editSource`(edit_document), `viewRendered`(menu_book — 23절, 옆 패널처럼 보이던 chrome_reader_mode 대신), `splitView`(vertical_split), `link`(link), `openExternal`(open_in_browser), `copyText`(copy_all), `imageBlocked`(image_not_supported), `indent` · `outdent`(format_indent_increase/decrease). 글리프가 겹치지 않음(`app_icons_test`).

### 12.4 트랙 A가 더하는 공개 표면

- note_core: `EntityKind.markdown`, `MarkdownText`, `SearchSource.markdown`, `MarkdownImport` · `MarkdownDecodeResult` · `MarkdownDecodeFailure {tooLarge, notText, notUtf8}`, `SyncNotice`의 `MarkdownConflictCopied`(sync_engine), `OutboxAck.uploadedTextVersion`.
- feature_library: `LibraryScreen.onOpenMarkdown`, `LibraryMarkdownImportAction`/`libraryMarkdownImportActionProvider`, `LibraryMarkdownExportAction`/`libraryMarkdownExportActionProvider`.
- pdf_io: `TextFileSource`, `FilePickerTextSource`, `PickedTextFile`, `DocumentFileOutput`, `createPlatformDocumentOutput`.

---

## 13. 키 이름

> **v2.18-md**: 키 더함 · 뜻 바뀜은 24.11 · 24.16(`md.live.*`, `md.linkSheet.edit`; `md.mode` = 보기 ↔ 원문, `md.editor` = 원문 편집기, `md.emptyEdit`는 더 보이지 않음).


화면(`MarkdownKeys`, 기반에서 고정 — B는 더하기만): `md.screen` · `md.back` · `md.title` · `md.mode` · `md.split` · `md.undo` · `md.redo` · `md.saveState` · `md.more` · `md.menu.export` · `md.menu.rename` · `md.menu.info` · `md.view` · `md.emptyEdit`(23절) · `md.editor` · `md.accessory` · `md.highlight` · `md.notMarkdown` · `md.notMarkdown.open` · `md.banner.trashed` · `md.banner.newerApp` · `md.banner.receiving` · `md.banner.tooLarge` · `md.banner.tooLargeToEdit` · `md.banner.saveFailed` · `md.banner.retry` · `md.banner.conflictCopy` · `md.leave` · `md.leave.stay` · `md.leave.copy` · `md.leave.discard` · `md.linkSheet` · `md.linkSheet.copy` · `md.linkSheet.open` · `md.linkSheet.cancel` · `md.taskUndo` · `md.block.<i>` · `md.task.<i>` · `md.link.<i>` · `md.code.<i>` · `md.code.<i>.copy` · `md.table.<i>` · `md.math.<i>` · `md.image.<i>`. B가 더함: `md.frontMatter` · `md.split.preview` · `md.banner.unsaved` · `md.banner.unsaved.restore` · `md.banner.unsaved.discard` · `md.banner.dismiss` · `md.banner.conflictCopy.open` · `md.rename.field` · `md.rename.ok` · `md.accessory.<기호>` · `md.accessory.fade.start|end` · `md.table.<i>.more`.

라이브러리(트랙 A): `library.new.markdown` · `library.new.importMarkdown` · `library.tile.mdBadge` · `library.tile.mdPreview` · `library.menu.exportMarkdown` · `library.hit.markdown.<noteId>`.

설정 키(모두 기기 로컬): `markdown.splitView`(bool, 기본 false) · `markdown.penHintShown`(bool — v1 쓰지 않음) · `markdown.unsaved`(jsonMap, `{<noteId>: {text, base, at}}` — 8.7). CORE kv(로컬): `md.conflictCopy.<noteId>`(5.3).

---

## 14. 계약 행 v2.17-md (00-overview 7.9에 넣음)

#### v2.17-md (2026-11-17, MD 문서 v1 — 오너 말 'PDF뿐만 아니라 md파일도 읽을 수 있으면 좋겠다', 선택안 ①)

추가와 저장 형식 바뀜(DB 스키마 v3 표 하나, 새 동기화 종류 `markdown`). 노트 JSON 키 · 열은 바뀌지 않음(형식 = `schemaVersion` 범위). 설계는 [08-markdown.md](08-markdown.md).

| # | 절 | 변경 | 출처 | 반영할 영역 |
|---|---|---|---|---|
| C217M-01 | 7.2.6 CORE 노트 | `NoteFormat {ink, markdown, unknown}` = `schemaVersion` 범위(1~99 · 100~199 · ≥200), `kMarkdownNoteSchemaVersion = 100`, `kLaterNoteFormatSchemaVersion = 200`, `Note.format` · `isMarkdown`, `requiresNewerApp`는 형식별 판본과 비교. 필드 · JSON 키 · 열 없음. 저장된 노트의 형식 범위를 바꾸는 원격 쓰기 거절 | 오너 요청 · 검토 D6 | 기반(처리됨) · A(거절) |
| C217M-02 | 7.2.6 CORE 새 엔티티 | `EntityKind.markdown`(wire 'markdown') · `MarkdownText{id 'md_<noteId>', noteId, text, createdAt, updatedAt, deletedAt, version}`. 노트 하나에 하나 | 오너 요청 | A |
| C217M-03 | 7.2.7 저장 형식 | DB 스키마 v3: 새 표 `md_docs`(+ 로컬 `text_bytes`, `base_text_version`), 단계 v2→v3(표 더하기만, 사본 없음, 한 트랜잭션). 백업에 `markdown` 종류 | 오너 요청 | A |
| C217M-04 | 7.2.x CORE 저장소 | `MarkdownRepository`(watch/get/create/saveText(baseVersion)/preview), `MarkdownDoc`, `MarkdownReadOnlyReason`, `MarkdownSaveResult`/`Outcome`, `MarkdownLimits{maxTextBytes 400000, maxEncodedBytes 900000, maxImportFiles 20, previewChars 400}`, `MarkdownTooLargeException`, `WrongNoteFormatException`, `MarkdownConflictCopy`, `MarkdownPreviewText`, `MarkdownPreviewKey`, `NoteStore.markdown`, provider 셋, `FakeMarkdownHooks`(testing) | 오너 요청 · 검토 D1 · D4 · D7 | 기반(형 · 가짜, 처리됨) · A(실제) |
| C217M-05 | 7.2.x CORE 규칙 | 만들기 = 노트 + 본문 한 트랜잭션. `saveText`: 같은 글 unchanged, base가 다르면 저장된 글을 충돌 사본으로 남긴 뒤 씀. 복제 · 복구 복제는 본문 복사(본문 없으면 빈 본문). 휴지통은 노트만, 영구 삭제는 본문 · 검색 소유자 함께. `openSession`은 MD 문서에 `WrongNoteFormatException`. MD 문서의 페이지(뒤 버전)는 지우지도 보이지도 않음 | 오너 요청 | 기반(openSession · 가짜) · A |
| C217M-06 | 7.2.8 SYNC 매핑 | keysOf(markdown) = {id, noteId, text, createdAt, updatedAt, deletedAt, version}, groupsOf = [], wholeUnitExcept = null, scope = json noteId → hint → 'lib', kindOrder 맨 끝, ownerId null. `record_gate._purged` markdown 팔, `purge_guard._editedInOutbox` markdown 팔(noteId 힌트), `kLocalOnlyFields` 둘, applyRemote 노트 updatedAt에 본문 noteId. keysOf(note) 그대로 | 5.1 · 검토 D2 · D9 | A |
| C217M-07 | 7.2.10 충돌 규칙 | L1: `saveText` base 검사(CORE). L2: SYNC가 적용 전 판정 — 안 올린 text · 글 다름 · 받은 판본 > base_text_version · 남의 노드 → 진 쪽 글을 '<제목> (충돌 사본 yyyy-MM-dd HH:mm)'로(같은 폴더, 10분 안 같은 문서 사본은 다시 씀), base := 받은 판본, `SyncNotice` `MarkdownConflictCopied`. `OutboxAck.uploadedTextVersion`으로 올린 판본을 base에. 본문 없는 문서는 편집 금지 | 오너 요구 '문서 통째로 조용히 잃지 않음' · 검토 D1 · D3 · D12 | A |
| C217M-08 | 7.2.5 검색 | `SearchSource.markdown`, 소유자 = noteId, 히트 pageId = 'md_<noteId>', 사각형 없음, 생존 = 노트가 휴지통 밖. 단위 = 블록 + 가벼운 정리, 1,000자 넘는 블록은 여러 단위. rebuild · pending 다시 하기에 markdown | 오너 요청 · 검토 D5 · D10 | A |
| C217M-09 | 7.1 패키지 | 새 멤버 `feature_markdown`(의존 note_core · ink_engine · ui_kit, 플러그인 없음, 진입점 `feature_markdown.dart` · `slots.dart`). 앱 의존 더함. workspace_rules: allowed_dependencies · plugin_free_members · noteapp 행 | D5 | 기반(처리됨) |
| C217M-10 | 7.5 외부 버전 | `markdown 7.3.1`(feature_markdown 직접 — 잠금에 한 줄), `url_launcher 6.3.3`(앱 직접 — 잠금 그대로, Q1) | 2.5 | 기반(markdown, 처리됨) · A(url_launcher) |
| C217M-11 | 7.2.11 LIBRARY | `LibraryScreen.onOpenMarkdown(id, {query, edit})`, '새로 만들기'에 '새 MD 문서' · 'MD 가져오기'(자리 `libraryMarkdownImportActionProvider`), MD 카드(`inkSwatch` 글 페이지 + 'MD' 표, 미리보기 키에 updatedAt), MD 메뉴 '.md로 내보내기'(자리 `libraryMarkdownExportActionProvider`) · PDF 내보내기 · 표지 바꾸기 뺌, 검색 MD 줄, 노트 고르기에서 뺌 | 오너 요청 · 검토 U15 | A |
| C217M-12 | 7.2.12 PDF 파일 도우미 | pdf_io 공개 `TextFileSource`/`FilePickerTextSource`/`PickedTextFile`(md · markdown · txt, 여러 개), `DocumentFileOutput`/`createPlatformDocumentOutput`(바이트 + 이름 + MIME). `PdfOutputSink` 표면 그대로 | R16 | A |
| C217M-13 | 4.5.5 INFRA 경로 | `/md/:noteId?q=&edit=1`, `MarkdownRouteArgs`, `AppNavigator.openMarkdown`/`closeMarkdown`, 편집기 스타일, 라이브러리는 처음부터 `/md/`로(redirect는 주소 직접용 대비책), 화면은 deferred import(한 번 부른 뒤 동기) | D7 · D9 · 검토 U18 · U19 | A |
| C217M-14 | 화면 | `MarkdownScreen(noteId, initialQuery, initialEdit, onClose, onOpenAsNote, onOpenMarkdown)`(마지막은 트랙 B가 더함 — 충돌 사본 [사본 열기]), 보기 ↔ 편집 단추 하나, 모든 바뀜은 버퍼 하나를 거쳐 `saveText(baseVersion)`, 자동 저장(700 ms · 최대 5 s · 조합은 1 s만 미룸 · 떠날 때 · 앱 숨김 때 비움), 실패하면 떠나기 대화, 못 저장한 글은 문서마다 `base`와 함께 기기에 두고 되살리면 그 base로 저장(L1 사본), 상한 있는 되돌리기(200칸 · 4,000,000 단위, 다른 기기 글이 들어오면 기록 비움), 편집 상한(150,000 단위 — 넘으면 보기 전용), 할 일 토글(블록별로 훑은 상자가 파서 상자와 같을 때만, 되돌리기 알림은 버퍼가 그대로일 때만), 링크는 묻고 열기/복사, 원격 이미지 안 가져옴, 수식 MathPreview, 머리말 · HTML 허용 목록, 넓은 화면 나란히. 계획과 다른 점은 08-markdown 8.12 | 오너 요청 · 검토 U1~U12 · U16 · U20 · 트랙 B 코드 검토 | B |
| C217M-15 | 자리 | feature_markdown `slots.dart`: `MarkdownExportAction`/`markdownExportActionProvider`, `MarkdownOpenLinkAction`/`markdownOpenLinkProvider`(앱이 url_launcher로, http · https · mailto · tel만) | D8 | 기반(형, 처리됨) · A(연결) |
| C217M-16 | 가져오기 · 내보내기 | UTF-8만(BOM 허용 · 보존), NUL 거절, `MarkdownLimits.check`, 원문 그대로 저장, 내보내기 = `utf8.encode(text)` → 가져온 그대로면 바이트 같음. 이름 = 정리한 제목 + '.md'(흔한 파일 이름이면 머리말 title → 첫 h1). 공유 MIME `text/plain`, 저장 `text/markdown` | 오너 요청 · 검토 U21 | A |
| C217M-17 | 7.2.x UI 아이콘 | `AppIconKind` 13개 더함(12.3) — 메뉴 · 화면 글리프만 | 12.3 | 기반(처리됨) |

---

## 15. 작업 분해

### 15.0 원칙

- **기반**은 이 브랜치에 커밋됨(15.1). 트랙 A · B는 **겹치는 파일 없이** 따로 간다(각자 worktree/브랜치 → 이 브랜치로 병합, push · PR 없음).
- 트랙 A 소유: `packages/note_core/**`, `packages/sync_engine/**`, `packages/feature_library/**`, `packages/pdf_io/**`, `packages/feature_editor/lib/src/ui/search/note_search_panel.dart` · `packages/feature_editor/lib/src/ui/editor_strings.dart`(+ 그 시험), `packages/ink_recognition/test/support/recording_store.dart`(필요할 때만), `app/**`, `tool/workspace_rules.yaml`(url_launcher 한 줄) + 그 `tool/test/rules_test.dart` 기대값, `pubspec.lock`(바뀌면 안 됨 — 확인만), `docs/**`.
- 트랙 B 소유: `packages/feature_markdown/**` 만(pubspec은 바꾸지 않음 — 필요한 의존이 이미 있음). 공개 표면(12.2 · 13절)은 이름 · 매개변수를 바꾸지 않는다(더하기는 api_surface 시험과 함께).
- 통합(I)은 A가 한다.

### 15.1 기반 (처리됨)

| # | 파일 | 내용 |
|---|---|---|
| F-1 | `note_core/lib/src/model/note.dart` | `NoteFormat` · 상수 둘 · `format` · `isMarkdown` · `requiresNewerApp` · toString |
| F-2 | `note_core/lib/src/common/errors.dart`, `repo/markdown_repository.dart`(새), `repo/note_store.dart`, `providers.dart`, `note_core.dart` | 12.1 형 · 인터페이스 · provider 셋 |
| F-3 | `note_core/lib/src/fake/fake_markdown.dart`(새), `fake/fake_note_store.dart` | 동작하는 가짜, 복제 · 영구 삭제 · openSession 거절 |
| F-4 | `note_core/lib/src/storage/drift_markdown_repository.dart`(새 — 자리), `drift_note_store.dart`, `drift_sessions.dart`(openSession 거절) | |
| F-5 | `note_core/lib/testing.dart` | `FakeMarkdownHooks` |
| F-6 | 시험: `note_core/test/model/note_format_test.dart` · `test/repo/markdown_limits_test.dart` · `test/repo/fake_markdown_test.dart`(새), `test/api_surface_test.dart`, `app/test/fakes/counting_note_store.dart`, `ink_recognition/test/support/recording_store.dart`(검토 D8) | |
| F-7 | `ui_kit/lib/src/app_icons.dart` | 13개 |
| F-8 | `packages/feature_markdown/`(새): pubspec · dart_test.yaml · README · `lib/feature_markdown.dart` · `lib/slots.dart` · `lib/src/{markdown_keys,markdown_screen,slots_impl}.dart` · `test/api_surface_test.dart` | 12.2 · 13 |
| F-9 | 루트 `pubspec.yaml` · `pubspec.lock`(markdown 한 줄) · `app/pubspec.yaml` · `tool/workspace_rules.yaml` · `tool/test/{ui_colors,ui_icons,rules,workspace,cli_process,affected,export_names}_test.dart` | |

### 15.2 트랙 A · 15.3 트랙 B

최종 과제 목록은 총괄 보고의 '## TRACK A TASKS' · '## TRACK B TASKS'와 같고, 여기 요약한다.

- A: A-1 엔티티 · switch · 형식 범위 거절 / A-2 DB v3 / A-3 `DriftMarkdownRepository` + 공유 계약 시험 / A-4 복제 · 복구 · 영구 삭제 / A-5 migrator 시험 / A-6 가짜를 실제와 같게(`EntityKind.markdown` 바뀜) / A-7 검색(rebuild · 긴 블록 · requery) / A-8 가져오기 해석 / A-9 L2 충돌 규칙 · base 갱신 셋 · ack / A-10 sync 표 · purge guard · record gate · 크기 알림 / A-11 두 기기 시나리오 / A-12 JSON 키 / A-13 pdf_io 파일 도우미 / A-14 라이브러리 / A-15 앱 경로 · 연결 · 내보내기 · 링크 / A-16 문서 / A-17 웹 예산.
- B: B-1 블록 나누기 · 파서 · 수식 · 머리말 · HTML / B-2 blockKey / B-3 렌더러 · 골든 12장 / B-4 수식 / B-5 이미지 / B-6 링크 / B-7 할 일 / B-8 편집기 · 기호 줄 · Tab / B-9 컨트롤러 · 자동 저장 · 메아리 · 떠나기 / B-10 위 막대 · 띠 · 메뉴 / B-11 검색 이동 / B-12 나란히 / B-13 성능 · 편집 상한 / B-14 문구 · 접근성 · 펜 안내.

### 15.4 통합 (A가, 둘 병합 뒤)

앱 끝까지(실제 CORE, VM): 가져오기(가짜 고르기) → 열림 → 편집 → 뒤로 → 라이브러리 미리보기 갱신 → 검색 → 맞는 곳 → 내보내기 바이트 같음 → 휴지통 → 되살리기 → 영구 삭제. Android 실기기 체크리스트 MD 항목 12개(가져오기 필터 · 한국어 IME 자동 저장 · 펜 손글씨 입력 · 100 KB 첫 그림 · **100 KB · 150,000자 문서에서 입력이 끊기지 않는지(아니면 편집 상한을 내림 — 8.7)** · 400 KB 편집 상한 띠 · 공유 대상 · 저장 · **저장한 파일 이름이 `.md`인지(SAF가 `text/markdown`에 `.md.txt`를 붙이면 `text/plain`으로 물러남 — 트랙 A 검토 A8)** · 링크 복사 · 앱 종료 뒤 글 · 다크 모드). 트랙 A는 `MarkdownScreen.onOpenMarkdown`을 `AppNavigator.openMarkdown`에 잇는다.

---

## 16. 수용 시험

> **v2.18-md**: 블록 바로 편집의 수용 시험은 24.14(MD-T21~MD-T35), 시험 파일은 24.16 · 24.17.


| ID | 시험 | 트랙 |
|---|---|---|
| MD-T01 | 형식 범위 · `requiresNewerApp` · 노트 JSON 키 그대로 · copyWith가 형식 유지 (`note_format_test`) | 기반(통과) |
| MD-T02 | 가짜 · 실제 공유 계약(`markdown_contract.dart`): create → 목록 · 최근, saveText saved/unchanged/savedWithConflictCopy, watch 새 값, note.updatedAt, outbox `['text']`(실제), 상한(원문 · 인코딩) 거절하고 아무것도 안 바뀜, 휴지통 · 본문 없음 → ReadOnly, MD 아님 → WrongNoteFormat, openSession 거절 | 기반(가짜 통과) · A(실제) |
| MD-T03 | 복제 → 본문 같음(본문 없으면 빈 본문), 영구 삭제 → `md_docs` 행 · 검색 소유자 없음, 휴지통 → 되살리기 글 그대로 | A |
| MD-T04 | v1 · v2 고정물 → v3: `md_docs` 빈 표, 생성 SQL이 새 v3와 같음, v2→v3 실패 주입 → v2 그대로, v1→v3 → v1 사본 | A |
| MD-T05 | 검색: 본문 낱말, 1,000자 뒤 낱말, 휴지통 문서 안 나옴, 한 글자(LIKE), 표 · 목록 안 낱말, rebuild 뒤에도 찾아짐 | A |
| MD-T06 | 가져오기 바이트 왕복(BOM + CRLF + 한글 + 이모지), CP949 → notUtf8, NUL → notText, ESC 많은 파일 → tooLarge, README.md → 첫 h1 제목 | A |
| MD-T07 | 동기화 표 · record gate · purge guard · 옛 앱 보류 | A |
| MD-T08 | 두 기기 동시 수정 → 수렴 + 진 글이 사본 정확히 하나, 같은 글이면 사본 없음, 순서 바꿔도 같음, **압축 스냅숏 · 자기 기록 재전달 → 사본 없음, 둘이 계속 칠 때 10분 안 사본 하나**, ack 뒤 base = 올린 판본 | A |
| MD-T09 | 노트가 본문보다 먼저 → `bodyPresent false` · 화면 편집 금지 · 2분 뒤 문구 · 본문 오면 열림 | A + B |
| MD-T10 | 라이브러리: 새로 만들기 두 항목, 실행 중 꺼짐, MD 카드 · 미리보기 갱신, MD 메뉴, 골든(섞인 그리드 6장) | A |
| MD-T11 | 경로: 카드 → `/md/<id>`(DB 안 읽음), 검색 → `?q=`, `/notes/<md id>` → `/md/<id>`, `/md/<노트 id>` → 'MD 문서가 아니에요', deferred 두 번째 열기에 빈 프레임 없음 | A |
| MD-T12 | 렌더: 오너 요청 목록 전부 + 머리말 · HTML 허용 목록 · 한 줄 `$$` 고정물 · 골든 12장 + 폰 편집 1장 · 대비 시험(`contrast_test`, 6 테마) · 닫히지 않은 `$$` · 긴 줄 | B(통과) |
| MD-T13 | 원격 이미지 · 링크: 네트워크 요청 0(HttpOverrides), 시트, 열기는 자리 있을 때만, `javascript:` 열기 없음 | B |
| MD-T14 | 할 일 토글 → 그 글자만 바뀜 · 저장 · 되돌리기 알림(버퍼가 움직이면 아무것도 안 함) · 훑은 상자 ≠ 파서 상자면 보이기만 · 나란히에서 입력 중 토글해도 글 안 잃음 | B(통과) |
| MD-T15 | 자동 저장(fake_async): 700 ms · 5 s · 조합 중 1 s 미룸 · 비우기는 조합 무시 · 보기 전환/뒤로/앱 숨김 → 저장 + flush · 실패 → 글 남고 띠 · 뒤로 → 떠나기 대화 셋 · 메아리로 커서가 안 움직임 · 다른 기기 글 → 사본 띠 · 커서가 바뀐 곳 둘레를 따라감 · 못 저장한 글: 나중 저장 성공이면 지움, 되살리기는 옛 base로(사본), 다른 길로 닫혀도 남김 | B(통과) |
| MD-T16 | CRLF/BOM 문서 한 글자 고침 → CRLF · BOM 그대로 | B |
| MD-T17 | 검색 이동(원문 기준, 목록 · 표 · 코드 안) · 강조(블록 — 8.12) · 보기↔편집 위치 유지 · 다른 기기 글이 와도 보기의 맨 위 블록 유지 | B(통과) |
| MD-T18 | 규칙 · 예산: `ws check --strict` 0, `flutter analyze` 0, 날 색 · 아이콘 시험, main.dart.js 차이 보고(17절) | 기반(통과) · A |
| MD-T19 | 되돌리기 상한: 200칸 · 글자 합 상한에서 오래된 것부터 버림 · 다른 기기 글에서 비움 · 키보드 Ctrl+Z도 이 기록 · 필드 기록 비우기(`renewField`) | B(통과) |
| MD-T20 | 성능(perf): 100 KB 첫 그림 < 300 ms, 100 KB · 149,900 단위 글자당 시간(400 KB는 보기 전용 첫 그림), 2,000항목 목록 | B(VM 수치 — 8.7; 첫 그림은 기계 부하로 240~360 ms 오감) |

---

## 17. 웹 예산

- 기준: `tool/web_budget.yaml` main.dart.js gzip 상한 2,000,000 B, **지금 이미 약 2 KB 넘음 — 게이트는 이 작업 전부터 빨강**. 파서 몫 약 +59 KB gzip(2.5).
- 방법: 앱은 `feature_markdown/slots.dart`만 즉시 import, 화면은 `deferred as md`. note_core · feature_library는 파서를 import하지 않는다(api_surface 시험이 slots.dart 쪽을 확인).
- 정직한 예상(검토 U13): 즉시 쪽에 남는 것 — `md_docs` drift 표(생성 코드: handwriting 표가 약 21 KB + 관리자 11 KB Dart 원문), v2→v3 단계, `MarkdownImport` · `MarkdownIndexText` · 충돌 사본 · `DocumentFileOutput` · 카드 · 메뉴 · 경로. 형식을 열로 두지 않아(4.1) 조금 줄었지만 **수 KB gzip는 늘 것**이다. 처음 안의 '+3 KB 목표'는 버린다.
- 정해 둔 길: A는 A-2 직후와 끝에 웹 빌드로 차이를 재서 보고한다. 넘는 만큼은 **총괄에게 숫자와 함께 상한 올리기를 요청**한다(6.15 규칙 — 영역이 스스로 올리지 않음). 다른 곳 줄이기는 이 라운드 범위 밖. 즉 이 라운드가 '막혀서' 끝나지 않는다: 게이트 결과(빨강 · 숫자)를 그대로 보고하는 것이 완료 조건.
- 배포 캐시: part 파일도 `no-cache`/해시 이름인지 A가 Hosting 머리글 확인(R4).
- Android: deferred import는 지연 구성 요소를 켜지 않으면 한 덩어리 — `loadLibrary()`는 곧바로 끝난다 [추측 — A-17 apk 확인]. APK 증가 보고만.

---

## 18. 위험 · 열린 질문

| # | 위험 / 질문 | 대응 |
|---|---|---|
| R1 | 할 일 훑기와 파서가 어긋남 | 블록별로 수가 다르면 그 블록 토글 끔. 고정물 30개 |
| R2 | 섞인 줄 끝 파일은 편집하면 통일 → 바이트 그대로가 깨짐(편집한 경우만) | 문서에 적음 |
| R3 | 400 KB 문서 저장마다 색인 | 같은 글 건너뜀, 지연 저장, CORE perf(100 KB 저장 + 색인 < 50 ms VM) |
| R4 | 웹 deferred part 캐시 어긋남 | Hosting 머리글 확인, '새 버전' 배너 |
| R5 | `base_text_version` 갱신 누락 → 사본 너무 많음/빠짐 | 갱신 셋(5.3) 각각 시험 + 압축 · 재전달 · 계속 치기 시나리오(MD-T08) |
| R6 | 한국어 IME 조합 · 되돌리기 | 조합은 지연만 1 s, 비우기는 무시(8.7), 실기기 체크 |
| R7 | Android 파일 고르기 `.md` 필터 | `FileType.any` + 확장자 검사 |
| R8 | KaTeX가 줄 높이를 흔듦 | `WidgetSpan` middle |
| R9 | 큰 글 TextField 느림 | 편집 상한(8.7) + perf 측정으로 값 조정 |
| R10 | 웹 예산 게이트 빨강(이미) | 17절 — 숫자 보고 + 총괄 판단 |
| R11 | 사본 10분 묶기에서 중간 글이 사라짐 | **고침(트랙 A 검토)**: 처음 규칙(10분 안 사본을 다시 씀)은 사용자가 사본에 쓴 글, 앞 진 쪽 글(받은 글이든 이 기기 글이든)을 지울 수 있었다. 이제 사본은 다시 쓰지 않고, 같은 글일 때만 묶는다(5.3) — 사본이 더 생길 수 있음을 받아들임 |
| Q1 | 앱이 `url_launcher`를 직접 의존해도 되는가 | 기본값: 된다(이미 해석되는 플러그인, 잠금 그대로). 안 되면 '복사'만 |
| Q2 | 카드 미리보기 읽기가 많을 때 | 보이는 카드만 · 키에 updatedAt · 30초 캐시. 문제가 보이면 로컬 파생 열(A) |
| Q3 | 충돌 사본 이름 · 위치 | 기본값대로 |

---

## 19. 검토 반영 내역 (2026-11-17, 데이터 검토 D1~D15 · UX 검토 U1~U22)

| 항목 | 판정 | 반영 |
|---|---|---|
| D1 열린 편집기가 다른 기기 글을 덮어씀 | 받아들임 | `saveText(…, {required baseVersion})` + `MarkdownSaveResult`를 기반에서 고정 · 구현(4.5, L1). 편집기 · 할 일 · 나란히가 모두 이 길 |
| D2 영구 삭제 보호가 MD 수정을 못 봄, 문서 서술이 틀림 | 받아들임 | `_editedInOutbox` markdown 팔 + noteId 힌트, 복구 복제가 본문 복사, S08-md, 5.3 서술 고침 |
| D3 ≠ 비교로 거짓 사본 · 사본 폭주 · ack 판본 모름 | 받아들임 | `>` + 남의 노드, 사본 뒤 base := 받은 판본, 10분 묶기, `OutboxAck.uploadedTextVersion` |
| D4 400 KB가 1 MB 상한을 못 지킴 | 받아들임 | `maxEncodedBytes` + `check`(기반 구현), 격리 시 알림 |
| D5 rebuild가 MD를 버림 | 받아들임 | A-7 |
| D6 `format` 기본 ink로 떨어짐 | 받아들임(다른 해법) | 필드를 없애고 형식 = `schemaVersion` 범위(4.1) — 복사 길이 이미 넘기는 값 |
| D7 sealed 하위형은 errors.dart에 | 받아들임 | 기반 구현 |
| D8 ink_recognition 가짜 저장소 | 받아들임 | 기반에서 고침 |
| D9 switch가 note_core · sync_engine 밖에도, 표 수 틀림 | 받아들임 | 5.2 표에 넷 더함, `search_requery.dart`는 A 소유 |
| D10 1,000자 자름 | 받아들임 | 나눠서 여러 단위 |
| D11 실패 뒤 떠나면 글 잃음 · 조합 중 비우기 | 받아들임 | 떠나기 대화, 비우기는 조합 무시, 일시정지 때 `markdown.unsaved` |
| D12 충돌 사본이 원격 적용 안의 숨은 부작용 | 받아들임 | 판정을 SYNC로(PurgeGuard 자리), CORE API 호출, `SyncNotice` |
| D13 `format` 키가 JSON 키 시험을 깸 | 해소 | 키 자체가 없어짐(4.1) |
| D14 v2→v3 사본 없음 | 받아들임 | 4.3에 명시 + 시험 |
| D15 crypto · fake_async, 본문 없는 복제, 오래 '받는 중', redirect 비용 | 받아들임 | 의존 미리 넣음(기반), 빈 본문 + 복제 끔, 2분 뒤 문구, 라이브러리는 바로 `/md/` |
| U1 실패 뒤 떠나기 | 받아들임 | D11과 같음 |
| U2 조합 중 저장 안 함 → 멈춤 | 받아들임 | 조합 포함 저장, 지연만 1 s, 비우기는 무시 |
| U3 큰 TextField | 받아들임 | 편집 상한 150,000 단위(측정으로 조정) + perf |
| U4 되돌리기 기록 상한 없음 | 받아들임 | `BoundedUndoHistory` |
| U5 메아리로 커서 · 되돌리기 초기화 | 받아들임 | 판본 · 풀린 글 비교로 무시 |
| U6 바뀜의 주인이 여럿 | 받아들임 | 컨트롤러 버퍼 하나 + 풀린 글 기준 위치 |
| U7 펜 · 손바닥으로 할 일 실수 | 받아들임 | 되돌리기 알림, 48 dp, unknown 포인터 무시 |
| U8 AST에 원문 위치 없음 | 받아들임 | 직접 만든 블록 나누기(4.7 (a)안) |
| U9 보기↔편집 위치 | 받아들임 | 블록 범위로 옮김 |
| U10 머리말 · HTML | 받아들임 | 접는 정보 상자, 허용 목록 |
| U11 기호 입력 · Tab | 받아들임 | 기호 줄, Tab 들여쓰기, `expands` |
| U12 폰 위 막대 넘침 | 받아들임 | 좁을 때 규칙 + 골든 |
| U13 +3 KB 목표 비현실 | 받아들임 | 목표 버림, 측정 보고 + 총괄 요청(17절) |
| U14 바탕 · 대비 토큰 | 받아들임 | `toolbar` 바탕, 링크 = textPrimary + accent 밑줄, `onAccentSoft`, 강조 모양 따로 |
| U15 MD 카드가 필기 카드와 어긋남 | 받아들임 | `inkSwatch` 글 페이지, 키에 updatedAt(기반 구현), 섞인 골든 |
| U16 펜으로 볼 때 | 받아들임 | 펜 끌기 = 스크롤, 한 번 안내, 손글씨 입력 체크 |
| U17 검색 정규화 둘 | 받아들임 | 원문에서 찾기, 낱말 강조 |
| U18 redirect 비용 | 받아들임 | 바로 `/md/`, redirect는 대비책 |
| U19 deferred 빈 프레임 | 받아들임 | 정적 Future + 불렸음 표시, 네이티브 미리 부름 |
| U20 큰 목록 · 표, 한 줄 `$$`, data: 캐시, 줄바꿈 설정 | 일부 받아들임 | 앞 셋 받아들임. **'줄바꿈 그대로 보기' 설정은 거절**(v1 범위 · 설정 늘리기 — GFM이 오너가 가져올 파일들의 표준이고, 오너가 실제로 요청하면 설정 하나로 더할 수 있음) |
| U21 공유 MIME · README 제목 · CP949 문구 | 받아들임 | 10.2 · 10.4 |
| U22 골든 수 · 나란히 단추 · 뒤로 순서 · 실기기 수치 | 받아들임 | 12장, 8.4, 15.4 체크리스트 |

### 19.1 트랙 B 코드 검토 반영 (2026-11-17, 검토 A: 정확성 · 데이터 안전 A1~A10, 검토 B: 계약 · UX B1~B13)

| 항목 | 판정 | 반영 |
|---|---|---|
| A1 · B1 일시정지 때 남긴 글이 나중 새 글을 덮음 · 다른 기기 글을 사본 없이 덮음 | 받아들임 | 칸을 문서마다 `{text, base, at}`로, 그 문서 저장이 성공하면 이 화면이 넣은 칸을 지움, 되살리기는 칸의 `base`로 저장(`restoreText`) → L1 사본. 시험: `review_fixes_test` 첫 둘, `controller_test` restoreText |
| A2 되돌리기가 다른 기기 글을 사본 없이 지움 | 받아들임 | `BoundedUndoHistory.reset` — 들어온 변경 · 첫 읽기에서 기록 비움(8.7 ③을 바꿈) |
| A3 · B6 토글 알림 [되돌리기]가 다른 상자를 뒤집음 | 받아들임 | 토글 직후 버퍼와 같을 때만, `toggleTaskAt`이 `]`도 확인 |
| A4 수만 같으면 코드 줄을 고침 | 받아들임 | `TaskMarks.matches`(표시 · 체크 상태 · 첫 낱말), 목록 안 들여쓴 코드 건너뜀, 목록 안 들여쓴 `>` |
| A5 띄어쓰기 없는 긴 줄이 파싱을 멈춤 | 받아들임 | `LongRunSyntax`(8.11), 500,000자 시험 |
| A6 닫히지 않은 `$$`가 나머지를 삼킴 | 받아들임 | 닫는 것이 있을 때만 수식 블록(8.11) |
| A7 큰 표 한 번에 빌드 | 받아들임(다른 해법) | 행 묶음 대신 앞 100행 + [더 보기], 표본 칸 폭(8.11) |
| A8 · B7 다른 길로 닫히면 글 잃음 · [버리고 나가기]가 저장함 | 받아들임 | dispose의 저장이 실패하면 칸에 넣음, `discard()` |
| A9 섞인 줄 끝 · 외톨이 CR | 일부 받아들임 | 외톨이 CR 파일은 CR로 왕복(4.6 코덱 `cr`). **섞인 줄 끝을 첫 편집에서 맞추는 것은 그대로**(18 R2 — 줄마다 원래 끝을 기억하려면 버퍼 밖 위치 표가 필요해 v1에 과함, 드묾) |
| A10 · B2 되돌리기 상한 없음 | 받아들임 | `BoundedUndoHistory` + 키보드 단축키를 그쪽으로 + 필드 기록 비우기(8.7), MD-T19 |
| B3 계획 · 계약이 구현과 다름 | 받아들임 | 이 절 · 8.12 · C217M-14 · MD-T 행. 대비 시험(`contrast_test`)은 만듦 |
| B4 [사본 열기]를 만들 API 없음 | 받아들임 | `MarkdownScreen.onOpenMarkdown`(12.2 · C217M-14), 통합 때 A가 연결 |
| B5 편집 상한 측정 없음 | 받아들임 | perf 시험 둘(8.7 수치), 실기기 체크 항목(15.4). 상한은 실기기 수치 전까지 그대로 |
| B8 [←]가 뒤로 순서를 건너뜀 | 받아들임 | [←] = 시스템 뒤로와 같은 순서 |
| B9 보기로 바꿀 때 `noteStore.flush()` 안 함 | 받아들임 | `flush(store: true)` |
| B10 들어온 변경에서 위치 잃음 | 받아들임 | 커서는 `mapOffsetThroughChange`, 보기는 맨 위 블록 키 + 높이 유지(`topAnchor` · `restoreAnchor`) |
| B11 폰 기호 줄이 넘치는데 표시 없음 · 44 dp | 받아들임 | 끝 가장자리 흐림(`toolbar` 토큰), 단추 48 dp |
| B12 할 일 줄이 글머리 줄보다 훨씬 높음 | 거절 | 누를 곳 48 dp(8.5 · 검토 U7)는 줄끼리 겹칠 수 없어 줄 높이가 곧 누를 곳이다 — 오너는 태블릿에서 손가락 · 펜으로 누름. 상자 위치 7 px은 글머리 기호도 같은 칸 가운데라 맞춰져 있음 |
| B13 계획의 시험 빠짐 | 받아들임 | MD-T12 대비, MD-T15 커서, MD-T17 위치, MD-T19, MD-T20 |


---

## 20. 트랙 A 구현 기록 (2026-11-17)

진행 기록 전체는 [progress/markdown.md](../progress/markdown.md). 계약 행과 다른 점만:

- C217M-07: L2는 `SyncStore.keepMarkdownConflictCopy(remote, versions)` 하나로 — 다운로드 파이프라인이 PurgeGuard 바로 뒤(적용 전)에 markdown 업서트마다 부른다. CORE가 판정(안 올린 text · 글 다름 · 받은 판본 > base · 남의 노드)과 사본 · base 갱신을 한 job에서 한다. `RemoteApplyReport`에는 더하지 않음(알림 `MarkdownConflictCopied`).
- C217M-10: `url_launcher`는 Q1 미승인으로 넣지 않음 — 링크 시트는 복사만.
- C217M-12: 공개 이름 `DocumentFile` · `DocumentOutputAction` · `DocumentShareFile`이 더 있음. `PickedTextFile`은 `{name, sizeBytes, readBytes}`.
- 웹 예산: 기반 대비 main.dart.js **+18,473 B gzip**(2,026,031 → 2,044,504), 상한 2,000,000 over(기반부터) — 총괄 판단 요청(17절).

## 21. 트랙 A 검토 반영 (2026-11-17)

검토 A(정확성 · 데이터 안전) · 검토 B(계획 대조)의 판정. 시험은 먼저 실패를 재현한 뒤 고쳤다(옛 코드에서 7개 실패 확인).

| 항목 | 판정 | 반영 |
|---|---|---|
| A1 · B2 앞 단계와 적용 사이 자동 저장이 받은 글을 잃음 | 받아들임 | `applyRemote` 안에서 같은 규칙을 다시 판정(5.3), 앞 단계는 kv `md.guarded.<noteId>`에 비교한 판본 쌍만 적음, base는 적용 job에서. `WriteTxn.putLocal`이 원격 job 안에서 쓴 변경은 local 출처로 냄. 시험 `md_conflict_copy_test` 7번 묶음(5개) |
| A2 · B1 10분 안 사본 다시 쓰기가 사용자가 사본에 쓴 글을 지움 | 받아들임 | 사본을 다시 쓰지 않음, 같은 글일 때만 묶음. 시험 6 · 6b. 가짜 `FakeSyncStore`도 같음 |
| A3 · B3 연달아 진 글이 앞 사본을 덮음 | 받아들임 | 위와 같음(새 사본). 시험 6c. R11 문구 고침 |
| A4 받은 본문 묘비가 반만 적용됨 | 받아들임 | 묘비 = 본문 없음(읽기 전용, 검색에서 빠짐) |
| A5 · B12 가져오기 거절이 파일마다가 아님 · 확장자 거름이 조용함 · 이름 없음 | 받아들임 | 거절 목록 `(name, reason)`, 확장자는 앱이 판정, 알림에 이름 셋까지 |
| A6 외톨이 서로게이트로 저장마다 새 판본 | 받아들임 | 저장 · 만들기 전에 U+FFFD로 바꿈 → 같은 글 다시 저장은 unchanged |
| A7 파일 이름이 '.md'뿐 | 받아들임 | 확장자만이면 이름 없음 → 머리말 · h1 → '가져온 문서' |
| A8 Android 저장 MIME 미확인 | 받아들임(확인은 실기기) | 15.4 체크리스트에 더함 |
| B4 필기 노트 열기마다 DB 읽기 redirect | 받아들임(방법 바꿈) | `openNote`의 `extra` 표시로 바로 통과(11절). 시험: 응답 없는 DB 판정에도 필기 노트가 바로 열림 |
| B5 목록 줄이 본문 전체를 읽고 쓰기마다 다시 읽음 | 받아들임(방법 바꿈) | `libraryMarkdownSizeProvider((noteId, updatedAt))` — 판본마다 한 번, 30초 캐시. 계약 표면(`MarkdownRepository`)은 그대로 — 새 메서드는 트랙 B의 시험용 구현을 깨므로 하지 않음 |
| B6 MD 카드 골든 없음 | 받아들임 | `library_markdown_golden_test` 6장(스타일 3 × 밝기 2, 섞인 그리드) |
| B7 웹 예산 증가 | 보고(총괄 판단) | 이번 고침의 차이는 progress/markdown.md |
| B8 실패한 deferred 부르기를 다시 못 함 | 받아들임 | 실패 Future를 잊음 + [다시 시도] 단추 |
| B9 네이티브 미리 부르기 없음 | 받아들임 | 한가 작업 `featureWiring.markdownScreen` |
| B10 계약 표 · 본문 낡음 | 받아들임 | 00-overview 7.9 'v2.17-md 고침' 표, 이 문서 상태 줄 · 4.4 · 4.5 · 5.3 · 9 · 10 · 11 · R11 |
| B11 (a) MD 전용 entityTooLarge 알림 · (b) 본문 없는 문서 '복제' 끄기 | 받아들인 차이 | (a) 일반 동기화 문제 보고로 충분, 받은 쪽은 읽기 전용 띠. (b) 빈 본문 복제는 잃을 글이 없고, 끄려면 메뉴마다 본문을 읽어야 함 |
| B13 남의 탐침 시험 파일 | 해당 없음 | 작업 트리 깨끗(추적 안 된 파일 없음) |


## 22. 통합 (2026-11-17, 15.4)

- 병합: `track/md-data`(A) → `track/md-ui`(B), 둘 다 `--no-ff`. 두 트랙의 기반 커밋(`31e7ef2` · `658f361`)은 트리가 같아 코드 충돌은 모두 한쪽만 바꾼 파일의 add/add — 바꾼 쪽을 택함. 이 문서와 00-overview는 기반을 공통 조상으로 다시 3방향 병합(19.1 → 20 → 21 순서, 15.4 실기기 항목은 둘 다 넣어 12개).
- 이은 것: `MarkdownScreen.onOpenMarkdown` → `AppNavigator.openMarkdown`(충돌 띠 [사본 열기], 사본이 위에 열리고 뒤로 가면 원래 문서). `FeatureWiringModule(markdownOutput:)` — 시험이 '.md로 내보내기'의 출력(공유 · 저장)을 바꿔 끼우는 자리, 제품은 null(플랫폼 출력).
- 앱 끝까지 시험(MD-T11 확장): `app/test/support/markdown_e2e_scenario.dart` — 실제 모듈 · 라우터 · 라이브러리 · MD 화면으로 새로 만들기 › MD 가져오기 → 보기(제목 · 할 일 상자 · 수식) → 편집 → [←] 두 번 → 저장 확인 · 카드 → 라이브러리 검색 → 결과 → `/md/<id>?q=` · 강조 → ⋯ › .md로 내보내기 › 저장(바이트 같음, 이름 `<제목>.md`) → 새 MD 문서(편집으로 열림) → 휴지통으로 이동 → 휴지통 › 복원 → 홈 · 최근에 다시 보임. 가짜 CORE로 기본 실행(`app/test/app/markdown_end_to_end_test.dart`), 실제 CORE(메모리)로 integration 단계(`app/test/integration/markdown_real_core_test.dart`) — 둘 다 통과.
- 남은 것: 실기기 체크리스트 12항목(15.4), APK 빌드, `app_smoke_v2_test`(integration)의 MD와 무관한 override 표 4줄(21절 · progress).
- 웹 예산(병합 뒤 `flutter build web --release`, `ws web-budget check`): main.dart.js **6,971,472 raw / 2,056,242 gzip** — 트랙 A 검토 반영 뒤(2,045,178) 대비 **+11,064 gzip**, MD 이전 바탕(2,026,031) 대비 **+30,211 gzip**. MD 화면 deferred part `main.dart.js_1.part.js` 258,031 raw / 87,485 gzip(첫 화면에 안 실림). 상한 2,000,000은 바탕부터 over — 총괄 판단(17절). 글꼴 · 성장 상한은 통과.

## 23. 오너 시각 검토 (2026-11-17, 통합 뒤)

통합된 앱에서 MD 화면을 다시 그려 봄(크래프트 · 미니멀 · 스튜디오 × 밝게 · 어둡게, 1280×800 가로 · 800×1280 세로 · 390×844 폰, 한국어 예시 + 경계 사례: 140행 넓은 표, 아주 긴 코드 줄, 수식 · 잘못된 수식, 3단 할 일, 원격 · 상대 경로 이미지, 빈 문서, 5,000줄 문서 스크롤 · 편집 전환). 고친 것:

| 본 것 | 고침 |
|---|---|
| 폰에서 [보기/편집] 단추가 아이콘만이고 '보기' 아이콘이 옆 패널처럼 보여 못 찾음 | 폰도 글 단 단추(48 dp), `viewRendered` 글리프 menu_book(책 = 읽기) |
| 태블릿 본문 16 px — 팔 길이에서 읽기 작음 | 짧은 변 ≥ 600이면 본문 17 px · 제목 같은 비율 · 코드 14.5 px(폰은 그대로). 720 px 열에서 한 줄 약 42자 |
| 언어 없는 코드 블록 위에 빈 머리 줄(복사 단추만) | 언어 없으면 머리 줄 없이 [복사]가 코드 옆 |
| 빈 문서의 보기가 작은 회색 글 한 줄뿐 | MD 문서 표시 + '아직 내용이 없어요' + [편집하기](`md.emptyEdit`, 고칠 수 있을 때만) |
| 라이브러리 MD 카드 미리보기에 `$E = mc^2$` · `[^1]` · `$$` 줄이 날것으로 | `MarkdownPreviewText`가 인라인 수식 달러(pandoc 규칙 — '$5 and $6'은 그대로) · 각주 표시 · 각주 정의 머리 · `$$` 줄을 지움 |
| 빈 MD 문서 카드가 흰 종이뿐 | 빈 노트 카드처럼 가운데 MD 문서 표시(종이 잉크 35 %) |

그대로 둔 것(이유):
- 할 일 줄 높이 48 dp — 19.1 B12 판정 유지(누를 곳 = 줄 높이, 펜 · 손가락 실수 막기). 17 px 본문으로 글머리 줄과의 차이는 조금 줆.
- 뒤로 순서(편집 → 보기 → 나가기, 8.4) — 시스템 뒤로와 [←]가 같은 순서라 헷갈리지 않음. 앱 끝까지 시험이 이 순서를 지킴.
- 저장 상태: 편집 중 '저장 중…' → '저장됨'(폰은 아이콘), 보기에서는 저장됨이면 숨김 — 그대로 충분.
- 취소선이 한글에서 조금 낮게 그어짐 — 글꼴 지표 탓, 기기 글꼴로 실기기 확인(15.4).

## 24. 블록 바로 편집 — '보기 상태에서 고치기' (설계, 2026-11-17, 계약 v2.18-md)

> **설계 검토 반영(24.15)과 구현 기록(24.16)이 24.1~24.14보다 우선한다.** 크게 바뀐 것: Enter는 입력 칸을 나누지 않고 같은 칸 안에서 새 문단 · 새 항목 줄을 만든다(칸 · 키보드 · IME 연결이 그대로 — U′5), 목록 단위는 최상위 항목 하나(안쪽 항목 포함 — D′8), 입력 칸이 열린 동안 들어온 다른 기기 글은 붙잡아 둔다(D′1).

> 오너 말(Android 태블릿 · 펜): '편집을 누르면 텍스트 파일처럼 보이도록 나오는데 notion처럼 잘 보이는 상태에서 편집할 수는 없는거야?' 같은 보고의 '다시 보기를 누르면 글씨가 세로로' 버그는 `0af6469`에서 고쳤다(`MarkdownScreen._body`의 `Stack`이 `StackFit.loose`라 Offstage 편집기 크기 0을 따라 폭 0 — 시험 `test/screen/view_width_test.dart` · 앱 끝까지 시나리오 5단계). 이 절은 기능 쪽 설계다. **설계만 — 코드는 아직 없음.** 8.4 · 8.7 · 8.9와 다르면 이 절이 우선한다(구현 커밋에서 그 절들을 고친다).

### 24.1 무엇을 만드나 (결정)

- **블록 단위 바로 편집**(Obsidian 실시간 미리보기 · Typora 방식). 보기 화면은 그대로 그려 두고, **누른 블록 하나만** 그 자리에서 작은 입력 칸으로 바뀌어 그 블록의 **마크다운 원문**을 보여 준다(모양은 그 블록이 그려진 모양에 가깝게 — 제목은 제목 크기, 코드는 고정폭). 나머지 블록은 계속 그려진 채로 있다. 블록 밖을 누르거나 Esc · [완료] · 뒤로를 누르면 그 블록이 다시 그려진다.
- 왜 블록마다 원문인가(대안과 견줌):
  - **WYSIWYG(서식 글을 직접 고침, 표식 숨김)**: 렌더러는 `MdInline` 나무에서 `RichText`를 만들고 원문 위치를 갖고 있지 않다 [확인 `md_model.dart` · `md_inline.dart`]. 표식을 숨긴 채 고치려면 고친 서식 글을 다시 마크다운으로 써 내야 하고, 그러면 사용자가 손대지 않은 표식 · 띄어쓰기 · 이스케이프까지 바뀐다 — '저장된 글은 사용자가 고친 곳 말고는 바이트 그대로'(4.6 · C217M-16)를 지킬 수 없다. 거절.
  - **블록마다 원문**: 고친 블록의 원문 범위만 바꾸면 되므로 바이트 규칙을 그대로 지키고, 블록 범위 · 블록 키 · 할 일 위치 등 이미 있는 원문 기준 장치(4.7 · 8.5 · `block_splitter.dart` · `block_keys.dart`)를 그대로 쓴다. 표식은 보이지만 흐린 색으로(24.5). 받아들임.
- **기본 모드**: 새 문서 · 기존 문서 모두 **보기(= 바로 편집)** 로 연다. 지금의 '편집'(문서 전체 고정폭 `TextField`)은 **'원문'** 으로 이름을 바꿔 남긴다. 위 막대의 모드 단추: 보기에서는 [원문](`editSource`, 글 '원문'), 원문에서는 [보기](`viewRendered`). 나란히(8.9, 넓은 가로)는 '원문 + 미리보기' 그대로다. 미리보기 칸은 바로 편집하지 않는다(누르면 왼쪽 원문 커서가 그 블록으로 — 두 입력 칸이 한 버퍼를 함께 쓰지 않게).
- 고칠 수 없는 문서(휴지통 · 새 버전 · 본문 없음 · 편집 상한 `kMaxEditUnits` 150,000 — 8.4 · 8.7)는 지금처럼 보기 전용: 블록을 눌러도 입력 칸이 열리지 않는다(링크 · 각주 · 접기만). 편집 상한은 바꾸지 않는다(24.9 — 원문 모드 성능과 되돌리기 기록 크기 둘 다의 상한이라서).

### 24.2 편집 단위 (어떤 것이 '블록'인가)

기본은 `splitBlocks`의 최상위 블록 하나 = 편집 단위 하나 [확인 `block_splitter.dart`]. 예외는 목록뿐이다.

| 원문 블록(`SourceBlockKind`) | 편집 단위 | 입력 칸 모양 | Enter |
|---|---|---|---|
| `paragraph` | 블록 전체(여러 줄) | 본문 글꼴 | 새 문단(24.4) |
| `heading` | 그 한 줄 | 그 단계 제목 크기 · 굵기, `#`은 흐리게 | 뒤에 새 문단 |
| `list` | **항목 하나** — 그 항목의 표식 줄 + 이어지는 줄(이어진 문단 · 목록 안 들여쓴 코드 · 목록 안 펜스), **다음 항목 표식 줄(어느 깊이든) 앞까지**. 안쪽 항목은 따로 단위 | 본문 글꼴, 표식 `- ` · `1. ` · `[ ]`는 흐리게, 깊이만큼 들여씀 | 같은 표식의 다음 항목 |
| `fence` · `indentedCode` · `math` · `html` · `frontMatter` | 블록 전체 | 고정폭, `card` 바탕(코드 블록과 같음) | 줄바꿈 |
| 표(문단 블록이 표로 파싱됨) | 블록 전체 | 고정폭, 가로 스크롤 | 줄바꿈 |
| 인용(`>`로 시작하는 문단 블록) | 블록 전체 | 본문 + 왼쪽 띠, `>`는 흐리게 | 다음 줄에 같은 `> ` |
| `footnote`(각주 정의) · 링크 참조 정의만 있는 문단 | 블록 전체 | 고정폭 작은 글 | 줄바꿈 |
| `rule` | 블록 전체(한 줄) | 고정폭 | 뒤에 새 문단 |

- **블록 하나에 노드가 여럿**(예: 빈 줄 없이 문단 다음 목록 줄 — 문단 블록 안에 `p` + `ul`, 4.7)이면 블록 전체가 한 단위다. 표 · 인용도 문단 블록이 파싱된 결과를 보고 고른다(노드가 `MdTable`/`MdQuote` 하나뿐일 때 그 모양).
- **목록 항목 범위 찾기**(새 `parse/list_items.dart`, 할 일 표식 8.5와 같은 방식): `ListItemSpans.scan(text, block)`이 블록 범위 안에서 펜스 · 들여쓴 코드를 건너뛰며 항목 표식 줄(`^\s*(?:[-*+]|\d{1,9}[.)])(?:[ \t]|$)`, `>` 접두 허용)을 찾아 **앞에서부터(전위 순서)** `{start, end, depth, markerEnd, marker}`를 낸다. `end`는 다음 표식 줄 시작 앞, 끝의 빈 줄은 뺌. **파서의 `MdListItem`을 같은 전위 순서로 센 수와 같고, 항목마다 표식 뒤 첫 낱말이 그 항목 글의 첫 낱말과 같을 때만** 항목 단위를 켠다(`ListItemSpans.matches` — `TaskMarks.matches`와 같은 이유, 19.1 A4). 어긋나면 **그 목록 블록 전체가 한 단위**(입력 칸에 목록 원문 전체 — 잃는 것 없음, 조금 덜 편할 뿐), 개발자 로그 한 줄.
- 안쪽 항목이 있는 항목을 고칠 때: 입력 칸은 그 항목 자기 줄만, 안쪽 목록은 입력 칸 아래에 계속 그려진다(`MdListItem.children` 중 `MdList`가 아닌 노드 자리를 입력 칸이 대신함).
- **블록 사이 빈 줄은 어느 블록에도 속하지 않는다**(4.7 그대로). 입력 칸은 블록 원문 범위 `[start, end)`만 보여 주고 바꾼다 — 앞뒤 빈 줄 · 다른 블록은 입력 칸에 없다.
- 각주 정의 · 링크 참조 정의는 지금 제자리에 아무것도 그리지 않는다 [확인 `md_document.dart` 275줄 — 각주 정의는 문서 끝 목록으로 감, 정의만 있는 문단은 `p`가 비어 null]. 바로 편집에서는 그 자리에 **흐린 한 줄 표식**(`정의 [^1]` · `링크 정의 [label]`, 고정폭 작게, 키 `md.live.def.<i>`)을 그려 누를 수 있게 한다. 고칠 수 없는 문서에서는 지금처럼 안 그린다.

### 24.3 바뀜 규칙 (데이터 안전)

- **버퍼는 하나뿐**: 컨트롤러의 풀린 버퍼(`MarkdownController.text`, BOM 없음 · LF — 4.6)가 문서 상태의 유일한 주인이다(8.5 U6 그대로). 입력 칸은 블록마다 새로 만드는 작은 `TextEditingController`(`LiveBlockField`)이고, **입력 칸 값이 바뀔 때마다 버퍼의 그 범위를 바꾼다**: `buffer = buffer[0, start) + field.text + buffer[end, …)`, `end = start + field.text.length`. 범위 밖 글자는 한 글자도 건드리지 않는다 — 이것이 이 절의 핵심 불변식이고 시험으로 지킨다(MD-T21).
- 버퍼가 바뀌면 지금의 `_onText` 길을 그대로 탄다: 되돌리기 기록(`BoundedUndoHistory.record`), dirty, 자동 저장(700 ms · 5 s), 저장 = `codec.encode(버퍼)` → `saveText(baseVersion)`. 즉 **자동 저장 · BOM/CRLF 복원 · 충돌 사본(L1 · L2) · 못 저장한 글 칸(`markdown.unsaved`) · 떠나기 대화는 하나도 바뀌지 않는다**(8.7).
- **IME 조합**: 버퍼에 쓸 때 입력 칸의 조합 범위를 `start`만큼 옮겨 버퍼 값의 `composing`에도 넣는다. 그래야 자동 저장의 '조합 중이면 1 s만 미룸'(`AutosaveScheduler.isComposing`이 버퍼의 `composing`을 봄 [확인 `markdown_controller.dart` 50줄])이 지금처럼 동작한다. 즉시 비우기(모드 바꿈 · 뒤로 · 앱 숨김)는 조합을 무시하고 저장한다(그대로).
- **빈 새 블록은 글자를 칠 때까지 버퍼에 없다**: Enter · [+] · 도구 막대로 만든 빈 블록은 화면 상태(`LivePending{after: blockIndex|-1, prefix}`)일 뿐이다. 첫 글자가 들어오는 순간 `구분자 + prefix + 글자`를 한 편집으로 넣는다. 빈 채로 떠나면 아무것도 쓰지 않는다 — 빈 줄 · 빈 표식이 문서에 쌓이지 않는다.
- **구분자**: 새 블록을 블록 b 뒤에 넣을 때 `b.end` 자리에 넣는다. 문단 · 제목 · 코드 등 = `"\n\n"`, 목록 항목 = `"\n"`(그 목록이 느슨한 목록 — 항목 사이에 빈 줄 — 이면 `"\n\n"`, 앞 항목 사이의 구분자를 그대로 본뜸). 문서 끝이면 b.end 뒤의 끝 줄바꿈은 그대로 두고 그 앞에 넣는다(마지막 줄바꿈 유무를 바꾸지 않음). 문서 맨 앞(빈 문서 포함)은 구분자 없이.
- **블록 지우기 · 합치기**(24.4의 Backspace)는 `[앞 블록 end, 이 블록 end)`를 지우거나(빈 블록), `[앞 블록 end, 이 블록 내용 시작)`을 지운다(합치기) — 지우는 것은 두 블록 사이 빈 줄과 이 블록의 표식뿐이고 그 밖은 그대로.
- 줄 끝 · BOM: 버퍼가 풀린 글이므로 블록 편집은 늘 LF로 일하고, 저장 때 코덱이 CRLF/BOM/외톨이 CR을 되살린다(4.6 · 8.7 그대로). 섞인 줄 끝은 첫 편집에서 많은 쪽으로(R2 그대로).
- 입력 칸이 열린 동안 **다른 블록의 그림은 다시 파싱하지 않는다**(바뀐 것이 없으므로). 활성 블록 뒤 블록들의 원문 위치는 `delta = 지금 입력 칸 길이 − 연 때 길이`만큼 밀린 것으로 본다. 입력 칸을 닫을 때(확정) 버퍼 전체를 다시 파싱한다(지금의 `parseMarkdownAsync` — 50 KB 넘으면 다른 isolate). 확정 사이에 붙여 넣은 글이 빈 줄을 품어 블록이 여럿이 되면 다시 파싱한 결과가 그대로 여러 블록으로 그려진다(버퍼는 그냥 글이다).
- **들어오는 변경**: ~~입력 칸이 열린 채 ③이 올 수 있는 때는 '아직 한 글자도 안 친 활성 블록'뿐~~ — 틀림(자동 저장이 칸이 열린 채 dirty를 끈다). **24.15 D′1이 우선**: 입력 칸이 열린 동안 들어온 다른 기기 글은 버퍼가 깨끗해도 반영하지 않고 붙잡아 두었다가, 칸을 닫을 때 그때도 깨끗하면 반영한다.

### 24.4 키 · 손짓

입력 칸 안(블록 종류는 24.2 표):

| 입력 | 문단 · 제목 · 목록 항목 · 인용 | 코드 · 수식 · 표 · HTML · 머리말 · 정의 |
|---|---|---|
| Enter(화면 키보드 · 하드웨어) | 커서에서 둘로 나눔: 앞은 이 블록에 남고 뒤는 새 블록(목록이면 같은 표식의 새 항목 — 번호 목록은 다음 번호, 할 일은 `- [ ] `, 같은 들여쓰기; 인용은 `> ` 줄). **빈 항목 · 빈 인용 줄에서 Enter = 목록 · 인용에서 나옴**(표식을 지우고 문단으로) | 줄바꿈 |
| Shift+Enter(하드웨어) | 블록 안 줄바꿈: 문단은 `\` + 줄바꿈(CommonMark 강제 줄바꿈 — 보기에서도 줄이 바뀜 [추측: `markdown 7.3.1` LineBreakSyntax가 `\` 줄바꿈을 받는지 L-1에서 확인, 안 되면 두 칸 띄어쓰기]), 목록 항목은 이어지는 줄(들여쓴 줄) | 줄바꿈 |
| Backspace, 커서가 내용 맨 앞 | ① 표식이 있으면 표식만 지움(목록 항목 → 문단, 제목 → 문단, 인용 → 문단 — Notion과 같음) ② 표식이 없으면 앞 블록과 합침(앞 블록이 문단 · 제목 · 항목 · 인용일 때 — 이 블록 글이 앞 블록 끝에 붙고 커서는 이음매) ③ 앞 블록이 코드 · 표 등이면 합치지 않고 앞 블록 끝으로 커서만 옮김 | 블록이 비었을 때만: 블록을 지우고 앞 블록 끝으로 |
| Backspace, 빈 블록 | 블록을 지우고(24.3) 앞 블록 끝으로 | 같음 |
| ↑ / ↓(하드웨어), 커서가 첫 줄 / 끝 줄 | 앞 / 뒤 블록을 열고 커서를 같은 가로 위치 쯤에 | 같음 |
| Tab / Shift+Tab | 목록 항목 들여쓰기 / 내어쓰기(지금 `indentLines`를 입력 칸에) | 코드: 두 칸 넣기 / 빼기 |
| Esc · 블록 밖 누름 · [완료] | 확정(24.3) | 같음 |
| Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y | 문서 되돌리기 기록으로(24.6) | 같음 |

- Enter 가로채기: 입력 칸의 `TextInputFormatter`가 '조합 범위가 비어 있고 커서 자리에 `\n` 하나만 들어온' 바뀜을 잡아 나누기로 바꾼다. **한국어 조합 중의 Enter는 키보드가 먼저 조합을 끝낸 뒤 `\n`을 보내므로** 조합 글자를 잃지 않는다 [추측 — Gboard · 삼성 키보드 실기기 체크 L-12].
- **화면 키보드의 맨 앞 Backspace**: Android 화면 키보드는 커서 앞에 글자가 없으면 글 바뀜을 보내지 않고 `KEYCODE_DEL` 키 이벤트만 보낸다. Flutter 엔진은 이 키 이벤트를 프레임워크 키 이벤트로 넘긴다 [추측 — L-1에서 Gboard · 삼성 키보드로 확인]. 입력 칸 위의 `Focus.onKeyEvent`가 그 이벤트(`LogicalKeyboardKey.backspace`, 선택 접힘 · 오프셋 0)를 잡는다. **보이지 않는 글자(제로폭 문자)를 입력 칸 앞에 두는 꾀는 쓰지 않는다**(버퍼에 새어 들어갈 위험). 키 이벤트가 오지 않는 키보드에서는 도구 막대 [블록 지우기 · 합치기]가 같은 일을 한다.
- **블록 누르기**: 블록 단위(`md.block.<i>`) 위를 한 번 누르면(손가락 · 펜 모두 — `PointerDeviceKind.stylus`도 탭) 그 단위의 입력 칸이 열리고 **누른 글자 쯤에 커서**가 놓인다. 그려진 글의 글자 위치 → 원문 위치는 `sourceOffsetForPlain(source, plain, k)`(원문과 그려진 글을 앞에서부터 같이 걸으며 원문의 표식 글자를 건너뛰는 탐욕 맞추기, 못 맞추면 블록 끝)로 어림한다 — 커서 위치만 정하고 글은 바꾸지 않으니 틀려도 안전.
- **누를 때 지금 동작이 먼저인 것**: 할 일 상자(48 dp, 한 번에 토글 — 8.5 그대로), 링크(바닥 시트 — 8.6, 시트에 [이 블록 고치기](`md.linkSheet.edit`)를 더함), 각주 번호, 코드 [복사], 표 [더 보기], 머리말 접기. 이것들 밖을 누르면 블록이 열린다.
- **길게 누르기 = 글 고르기**(지금 `SelectionArea` 그대로, 블록을 넘어 고르고 복사 가능). 여러 블록을 고른 채 글을 치거나 지우는 것은 v1 안 함(원문 모드에서). 펜 끌기 · 손가락 끌기 = 스크롤(8.10 그대로 — 바로 편집이 펜 끌기를 가로채지 않음).
- 입력 칸이 열려 있을 때 다른 블록을 누르면: 지금 칸 확정 → 다시 파싱 → 누른 블록을 **키 + 그 키 안 순서로** 다시 찾아 연다(위치가 밀렸어도 맞는 블록). 다른 블록의 할 일 상자를 누르면 같은 순서로 확정한 뒤 **(블록 키, 블록 안 상자 순서)** 로 상자를 다시 찾아 토글한다(오프셋은 확정으로 밀렸을 수 있음 — `toggleTaskAt`의 `[ ]` 재확인은 그대로 둠).
- 빈 문서: 블록 대신 빈 문단 자리 하나(`md.live.placeholder`, 흐린 글 '여기에 쓰세요'). 누르면(새 문서는 열자마자) 입력 칸 + 키보드. 문서 끝 아래 빈 곳(최소 120 px)을 누르면 끝에 새 문단(`md.live.addEnd`, [+ 새 블록] 흐린 줄). 블록 사이 [+]는 v1에 두지 않는다(터치에서 hover가 없고, 블록 끝 Enter로 충분) — 블록 끌어 옮기기도 v1 밖.
- `initialEdit`(라이브러리 '새 MD 문서', 경로 `?edit=1`)의 뜻이 '원문 편집기로 열기'에서 **'보기로 열고 바로 쓰기'** 로 바뀐다: 빈 문서면 빈 문단 자리를 열고, 아니면 마지막 블록 뒤 새 문단을 연다(키보드 올라옴). 공개 매개변수 이름은 그대로(C218M-01).

### 24.5 입력 칸 모양

- 같은 읽기 열(최대 720 px, 폰 16 / 태블릿 32 여백, 17 px 태블릿 본문 — 23절)에, 그 블록이 그려진 자리 · 비슷한 높이로. 입력 칸 둘레는 `accentSoft` 옅은 바탕 + `radiusSmall`(색은 모두 `StyleTokens`, 새 날 색 없음 — `tool/test/ui_colors_test.dart`).
- `LiveBlockField`의 `TextEditingController.buildTextSpan`을 덮어 **블록 수준 모양만** 입힌다: 블록 종류에 따른 글꼴 크기 · 굵기 · 고정폭, 줄 머리 표식(`#…`, `- `, `1. `, `[ ]`, `> `)은 `textSecondary`. 조합 범위의 밑줄은 기본 구현(`super.buildTextSpan`)과 같게 남긴다 — 표식 칠하기는 조합 범위 밖에서만. **인라인 표식 칠하기(`**굵게**`의 `**` 흐리게 + 안쪽 굵게)** 는 L-9(있으면 좋은 것): 같은 함수에서 인라인 파서 없이 짝 맞는 `**` · `*` · `~~` · `` ` `` · `$`만 칠한다(글은 안 바꿈).
- `TextField`: `maxLines: null`(스스로 늘어남 — 바깥 `ListView`가 스크롤), `keyboardType: multiline`, `textInputAction: newline`, `autocorrect` · `enableSuggestions`는 문단 · 제목 · 목록 · 인용에서 **켬**(글쓰기다 — 원문 모드는 지금처럼 끔), 코드 · 표 · 수식 · HTML · 머리말에서 끔. Android 펜 손글씨 입력(`stylusHandwritingEnabled`, 기본값)을 끄지 않는다.
- 입력 칸이 열릴 때 바깥 목록이 칸을 키보드 위로 보이게 `ensureVisible`(커서 줄 기준, 위 여백 1줄). 회전 · 창 크기 바뀜에도 활성 블록(시작 위치 + 키)과 커서는 State에 남는다.

### 24.6 되돌리기 · 다시 하기

- 기록은 문서 하나에 하나(`BoundedUndoHistory` 그대로 — 200칸 · 4,000,000 단위 · 500 ms 묶기, 다른 기기 글이 들어오면 비움). 버퍼 값이 기록 단위다.
- 블록 열기 · 확정 · 나누기(Enter) · 합치기 · 지우기 · 도구 막대 동작은 앞 묶음을 닫고(`record(single: true)`) 한 칸씩이다.
- 입력 칸 안 Ctrl+Z 등과 위 막대 [↶][↷](보기 모드에서도 고칠 수 있으면 보임 — 폰은 도구 막대 끝)는 `UndoTextIntent` · `RedoTextIntent`를 입력 칸 위에서 덮어 문서 기록으로 보낸다(`MdEditor`와 같은 방식). 입력 칸 자체의 `UndoHistory`는 블록마다 새 컨트롤러라 작고, 쓰지 않는다.
- 되돌리기 한 번 = 입력 칸 닫기 → 버퍼에 기록 값 넣기 → 다시 파싱 → **바뀐 곳**(옛 값과 새 값의 공통 앞뒤를 뺀 범위 — `mapOffsetThroughChange`와 같은 계산)이 든 블록을 열고 커서를 바뀐 곳 끝에. 바뀐 곳이 화면 밖이면 그리로 스크롤.

### 24.7 서식 도구 막대

- 입력 칸이 열려 있을 때만, 키보드 바로 위(키보드가 없으면 — 하드웨어 키보드 · 펜 손글씨 — 본문 아래 끝)에 한 줄, 가로 스크롤 + 끝 흐림(지금 `MdAccessoryRow`의 틀을 다시 씀 — 키 `md.live.toolbar`, 단추 `md.live.toolbar.<이름>`). 넓은 화면(본문 폭 ≥ 600)에서도 같은 자리(위 막대에 넣지 않음 — 쓰는 곳 가까이).
- 단추(누를 곳 48 dp, 아이콘 + 툴팁 · 의미 이름):

| 이름 | 글 | 하는 일(모두 활성 입력 칸 안, 한 편집) |
|---|---|---|
| `h1` · `h2` · `h3` | 제목 1 · 2 · 3 | 이 블록 줄 머리를 `# ` · `## ` · `### `로(같은 단계면 빼서 문단으로). 목록 항목 · 코드 등에서는 꺼짐 |
| `bold` · `italic` · `strike` · `code` | 굵게 · 기울임 · 취소선 · 코드 | 고른 글을 `**…**` · `*…*` · `~~…~~` · `` `…` ``로 감쌈(이미 감싸져 있으면 벗김). 고른 것이 없으면 짝을 넣고 커서를 가운데 |
| `link` | 링크 | `[고른 글](` 커서 `)` |
| `bullet` · `numbered` · `task` | 목록 · 번호 목록 · 할 일 | 이 블록(문단이면 줄마다)의 머리를 `- ` · `1. ` · `- [ ] `로 바꾸거나 뺌 |
| `quote` | 인용 | 줄마다 `> ` 넣기 / 빼기 |
| `indent` · `outdent` | 들여쓰기 · 내어쓰기 | 목록 항목만(24.4 Tab과 같음) |
| `codeBlock` · `mathBlock` · `table` · `rule` | 코드 블록 · 수식 · 표 · 구분선 | **이 블록 뒤에 새 블록**을 넣고 연다: ```` ``` ```` 두 줄 사이 / `$$` 두 줄 사이 / `\| 제목 \| 제목 \|` + `\| --- \| --- \|` + `\|  \|  \|`(첫 칸에 커서) / `---`(구분선은 열지 않고 그 뒤 빈 문단을 엶). 24.3 빈 블록 규칙과 달리 이것들은 넣는 순간 버퍼에 씀(틀이 곧 내용) |
| `join` | 블록 합치기 · 지우기 | 24.4의 맨 앞 Backspace와 같음(키 이벤트가 오지 않는 키보드용) |
| `done` | 완료 | 확정하고 키보드 내림 |

- 도구 막대 동작은 모두 입력 칸의 원문만 바꾼다 → 24.3 길로 버퍼에. 새 아이콘은 `AppIconKind`에 더함(C218M-07): `formatBold` · `formatItalic` · `formatStrike` · `heading` · `listBullet` · `listNumbered` · `taskBox` · `quote` · `codeBlock` · `table` · `horizontalRule` · `blockJoin` · `done`(이미 있는 `math` · `link` · `indent` · `outdent` · `undo` · `redo` · `add`는 다시 씀).

### 24.8 위 막대 · 뒤로 · 모드 바꿈

- 위 막대: [←] 제목 · [원문](보기일 때) / [보기](원문 · 나란히일 때 — 나란히는 '나란히 끄기' 그대로) · (≥ 1,100 가로, 원문일 때) [나란히] · 고칠 수 있으면 [↶][↷] · 저장 상태 · [⋯]. 보기에서도 저장 상태 글을 보인다(입력 중 '저장 중…' → '저장됨', 보기에서 저장됨이면 숨기던 규칙(23절)은 입력 칸이 닫혀 있을 때만).
- **뒤로 순서**(8.4를 바꿈, [←]과 시스템 뒤로 같음): ① 열린 시트 · 메뉴 닫기 ② **입력 칸이 열려 있으면 확정하고 닫기**(키보드가 떠 있으면 시스템이 먼저 키보드를 내림 — 그 뒤로는 앱에 오지 않음) ③ 원문/나란히면 보기로(저장 비우기) ④ 화면 닫기(저장 비우기, 실패면 8.7 떠나기 대화).
- 보기 → 원문: 입력 칸 확정 → 비우기 → 원문 편집기를 열고 커서를 같은 원문 위치에. 원문 → 보기: 비우기 → 다시 파싱 → 원문 커서가 든 블록을 맨 위로(8.7 U9 그대로, 입력 칸은 열지 않음).
- **원문 편집기는 보기 모드에서 마운트하지 않는다**(지금은 한 번 열면 `Offstage`로 남김 — 이 절 머리의 세로 글씨 버그가 난 자리). 이유: 보기에서 블록을 칠 때마다 버퍼가 바뀌는데, 마운트된 원문 `TextField`는 그때마다 문서 전체를 다시 배치한다 — 100 KB에서 글자당 약 520 ms(8.7 측정, 대부분 `TextField` 배치). 원문 편집기의 커서 · 스크롤은 컨트롤러가 기억해 두었다가(원문 위치 · 맨 위 줄) 다시 열 때 되살린다. 이것으로 `0af6469`의 `Stack`/`Offstage` 구조는 원문 → 보기 길에서 사라진다(`StackFit.expand`는 남겨도 무해).

### 24.9 성능

- 화면 위 `TextField`는 언제나 많아야 하나(활성 블록). 블록 목록은 지금 `ListView.builder` · 목록 쪼개기(8.11) 그대로. 활성 블록이 속한 단위만 다시 그린다(입력 칸이 든 단위의 `MdUnit`을 바꿔 끼움 — 다른 단위 위젯은 `const`/같은 값이라 다시 빌드해도 배치 비용 없음).
- 글자 하나당 일: 버퍼 문자열 잇기(100 KB에서 1 ms 안 [추측 — L-11 perf로 잼]), 기록 칸 하나(500 ms 묶기라 대부분 덮어씀), 자동 저장 타이머. 다시 파싱은 확정 때만.
- 목표(VM 디버그, `perf_test`): 100 KB 문서의 블록 입력 칸에서 글자 하나 중앙값 **< 16 ms**(지금 원문 모드 약 520 ms), 확정 → 다시 그림 100 KB < 300 ms(첫 그림 목표와 같음), 400 KB(편집 상한 밖)는 보기 전용 그대로.
- 편집 상한 `kMaxEditUnits`(150,000 단위)은 v2.18에서 바꾸지 않는다. 바로 편집에는 원문 모드의 배치 비용이 없지만, 되돌리기 기록이 버퍼 전체를 칸마다 담으므로(4,000,000 ÷ 150,000 ≈ 26칸) 더 큰 문서는 되돌리기가 몇 칸 안 남는다. 실기기 수치(15.4) 뒤에 '보기 편집 상한'을 따로 둘지 정한다(24.12 Q).

### 24.10 블록 키 · 펜 주석 자리(②)

- 블록 키는 그대로 '원문(trim) SHA-1 앞 8자 + 같은 해시 순서'(`block_keys.dart`). ~~블록 하나를 고치면 그 블록 키만 바뀐다~~ — 같은 원문 블록이 여럿이면 순서 번호가 밀릴 수 있다(24.15 D′7). 지키는 것: 원문이 고친 블록의 옛 글 · 새 글 어느 것과도 같지 않고 경계가 그대로인 블록의 키는 그대로(MD-T24). 나누기는 원래 블록 키를 앞 조각이 잃고 새 키 둘, 합치기는 두 키가 새 키 하나 — 4.7의 `mdAnchor{blockKey, textHash}`가 ②에서 '잃은 앵커는 가장 가까운 블록으로'를 정하면 된다(이번에 저장하는 것 없음).
- 목록 항목 단위의 키는 두지 않는다(화면 상태일 뿐). ②가 항목마다 주석을 원하면 그때 항목 키 = `블록 키 + 항목 순서`로 더한다.

### 24.11 키 이름 · 문구

- 더하는 키(`MarkdownKeys` — 더하기만): `md.live.field`(활성 입력 칸) · `md.live.placeholder` · `md.live.addEnd` · `md.live.def.<i>` · `md.live.toolbar` · `md.live.toolbar.<이름>`(24.7 표의 이름) · `md.linkSheet.edit`. 지금 키의 뜻 바뀜: `md.mode`(보기 ↔ 원문), `md.editor`(원문 편집기), `md.emptyEdit`(고칠 수 있는 빈 문서에서는 `md.live.placeholder`가 대신 — 보기 전용 빈 문서에서는 단추 없는 안내만), `md.accessory`(원문 편집기의 기호 줄 그대로).
- 문구(`strings_ko.dart`): '원문' · '보기' · '여기에 쓰세요' · '새 블록' · '완료' · '제목 1/2/3' · '굵게' · '기울임' · '취소선' · '코드' · '링크' · '목록' · '번호 목록' · '할 일' · '인용' · '들여쓰기' · '내어쓰기' · '코드 블록' · '수식' · '표' · '구분선' · '블록 합치기' · '이 블록 고치기' · '정의' · '링크 정의'.
- 설정 키 더함 없음(기본 모드는 고정 — 마지막 모드를 기억하지 않음: 열면 늘 보기).

### 24.12 위험 · 열린 질문

| # | 위험 / 질문 | 대응 |
|---|---|---|
| R12 | 화면 키보드에서 맨 앞 Backspace가 앱에 안 옴 | 키 이벤트 길(24.4) + 도구 막대 [블록 합치기]. L-1에서 Gboard · 삼성 키보드 확인, 실기기 체크 항목 |
| R13 | 한국어 조합 중 Enter · 블록 나누기에서 조합 글자 잃음 | 조합 범위가 빈 바뀜만 나누기로 가로챔, 시험(가짜 IME 조합 → Enter) + 실기기 |
| R14 | 목록 항목 범위 어긋남(이상한 들여쓰기 · lazy 줄) | `ListItemSpans.matches`가 어긋나면 목록 블록 통째 단위(잃는 것 없음). 고정물 30개(할 일 고정물 재사용 + 중첩 · 느슨한 목록 · 목록 안 펜스) |
| R15 | 누른 글자 → 원문 위치 어림이 틀림 | 커서 위치만 정함(글 안 바뀜). 시험: 굵게 · 링크 · 인라인 코드 · 수식이 섞인 줄에서 오차 ≤ 표식 길이 |
| R16 | 입력 칸 확정 때 다시 파싱으로 화면이 튐 | 확정한 블록을 (블록 순서, 위 높이)로 붙잡아 다시 그린 뒤 같은 높이에(지금 `restoreAnchor`) |
| R17 | 보기에서 실수로 고침(읽다가 펜으로 누름) | 한 번 누름 = 입력 칸 열기일 뿐(글 안 바뀜), 되돌리기 한 칸으로 돌아감. 오너 실기기 확인 뒤 '읽기 잠금'이 필요하면 [⋯]에 더함(Q2) |
| Q2 | 보기 전용으로 열어 두는 스위치가 필요한가 | 기본값: 없음(Notion과 같음). 오너가 원하면 [⋯] '읽기 전용으로 보기'(기기 로컬 `markdown.readLock`) |
| Q3 | 보기 편집 상한을 원문 상한(150,000)보다 크게 할까 | 기본값: 같게. 실기기 수치 뒤 |
| Q4 | 여러 블록을 고른 채 지우기 · 바꾸기 | v1 안 함(원문 모드). 뒤 라운드 |

### 24.13 작업 분해 (트랙 하나 — `packages/feature_markdown/**`만, 필요하면 `ui_kit` 아이콘 · `app` 시나리오)

| # | 내용 |
|---|---|
| L-1 | 조사 확인: `\` 줄바꿈 파싱, Android 맨 앞 Backspace 키 이벤트(가능한 범위 — 엔진 원문), `buildTextSpan`과 조합 밑줄 |
| L-2 | `parse/list_items.dart` `ListItemSpans.scan/matches` + 고정물 시험 |
| L-3 | `live/live_units.dart`: 블록 → 편집 단위(24.2 표), 정의 표식 |
| L-4 | `live/live_edit.dart`(순수 Dart): 범위 바꾸기 · 나누기 · 합치기 · 지우기 · 빈 블록 넣기 · 구분자 · 도구 막대 변환 — 모두 `(buffer, 단위, 입력) → (새 buffer, 새 커서)` 함수. 바이트 불변식 시험(MD-T21)의 대상 |
| L-5 | `live/live_block_field.dart`: 입력 칸, `buildTextSpan`, Enter formatter, 키 처리, 되돌리기 Intent |
| L-6 | 컨트롤러: `spliceRange(start, end, text, composing)`, 원문 편집기 커서 기억, 활성 블록 상태 |
| L-7 | `MdView`: 활성 단위 바꿔 끼움, 누름 → 단위 · 커서, 빈 문서 자리, 끝 [+], 정의 표식 |
| L-8 | 화면: 모드(보기/원문/나란히), 위 막대, 뒤로 순서, 원문 편집기 마운트 규칙, `initialEdit` 새 뜻, 링크 시트 [이 블록 고치기] |
| L-9 | 도구 막대(+ 아이콘 13개 — `ui_kit`), 인라인 표식 칠하기(있으면 좋은 것) |
| L-10 | 되돌리기 통합 · 들어오는 변경 · 회전 · 앱 숨김 |
| L-11 | perf: 100 KB 글자당 · 확정 다시 그림 |
| L-12 | 골든(보기 + 활성 문단 · 제목 · 목록 · 코드 블록, 크래프트 밝게/어둡게 × 태블릿 가로 · 폰) · 앱 끝까지 시나리오 고침(새 MD 문서 → 바로 씀 → 뒤로 → 카드 미리보기) · 실기기 체크 항목 더함 · 문서(8.4 · 8.7 · 8.9 · 13 · 16절 고침) |

### 24.14 수용 시험

| ID | 시험 |
|---|---|
| MD-T21 | **바이트 불변식**(속성 시험): 고정물 문서 40개(BOM · CRLF · 외톨이 CR · 한글 · 이모지 · 머리말 · 표 · 중첩 목록 · 각주 · 링크 정의 포함) × 무작위 블록 편집 200번(글 넣기 · 지우기 · 나누기 · 합치기 · 도구 막대) → 매번 `encoded`가 '원래 바이트에서 그 단위 범위만 바뀐 것'과 같음, 편집 없이 열고 닫으면 저장 0번 · 바이트 같음 |
| MD-T22 | 단위 표(24.2): 블록 종류마다 누르면 그 범위의 원문이 입력 칸에, 목록은 항목마다(중첩 · 번호 · 할 일 · 느슨한 목록), 어긋난 목록은 통째, 정의 표식 누름 |
| MD-T23 | 키(24.4): Enter 나누기(문단 · 제목 · 항목 · 번호 다음 · 할 일 `- [ ] ` · 빈 항목에서 나옴 · 인용), Shift+Enter, 맨 앞 Backspace ①②③(하드웨어 키 이벤트), 빈 블록 지우기, ↑↓, Tab, Esc · 밖 누름 확정 |
| MD-T24 | 블록 키: 한 블록을 고치면 다른 모든 블록 키 그대로(같은 해시 순서 포함) |
| MD-T25 | 빈 새 블록: Enter 뒤 아무것도 안 치고 나가면 버퍼 · 저장 그대로, 치면 구분자 + 글 한 편집. 빈 문서 자리 → 첫 글자 → 저장 바이트 = 친 글 그대로(앞 줄바꿈 없음) |
| MD-T26 | 자동 저장 · IME(fake_async): 입력 칸에서 치면 700 ms 저장, 조합 중 1 s 미룸(버퍼 `composing` 거울), 확정 · 원문 바꿈 · 뒤로 · 앱 숨김 비우기, 실패 → 띠 · 떠나기 대화, 한국어 조합 중 Enter에서 글자 안 잃음 |
| MD-T27 | 되돌리기: 블록 열기 · 나누기 · 합치기 · 도구 막대가 한 칸씩, 되돌리면 바뀐 블록이 열리고 커서가 바뀐 곳, 상한 그대로, 다른 기기 글 → 기록 비움 |
| MD-T28 | 들어오는 변경: 깨끗한 채 활성 블록 → 받은 글 · 맨 위 블록 유지, dirty → 반영 안 함 → 다음 저장에서 사본 띠 |
| MD-T29 | 다른 블록 할 일 상자 누름(입력 칸 열린 채, 앞 블록에 글을 더해 위치가 밀린 뒤) → 맞는 상자만 토글 |
| MD-T30 | 화면: 새 MD 문서 → 보기에서 입력 칸 + 키보드(원문 편집기 안 마운트), 뒤로 ①~④ 순서, 보기 ↔ 원문 위치, 회전 · 1280×800 · 800×1280 · 390×844에서 입력 칸 · 보기 폭(`view_width_test`의 폭 단언 재사용), 고칠 수 없는 문서에서 입력 칸 안 열림 |
| MD-T31 | 도구 막대: 단추마다 원문 결과(감싸기 · 벗기기 · 머리 넣기/빼기 · 새 블록 틀), 48 dp, 390 px · 글자 배율 1.3 넘침 없음, 색 · 아이콘 규칙 시험 |
| MD-T32 | perf(24.9): 100 KB 글자당 중앙값 < 16 ms, 확정 다시 그림 < 300 ms(VM) |
| MD-T33 | 앱 끝까지(`markdown_e2e_scenario.dart`): 새 MD 문서 → 바로 씀(한글 + 영어) → Enter → 둘째 문단 → 뒤로 → 카드 미리보기에 두 문단 → 다시 열기 → 블록 눌러 고침 → '.md로 내보내기' 바이트 = 버퍼 |
| MD-T34 | (24.17) 순수 · 편집기: 구분선 · 문단 안 번호 줄, Enter 종류, 새 블록 앞뒤 범위, 비운 블록 · 가운데 항목, 바뀜 따라 옮기기, 닫히지 않은 울타리, 인라인 모양, 표식 빠진 항목, 더한 빈 표식 줄, 큰 문서 칸 안 문단 · setext |
| MD-T35 | (24.17) 화면: Enter = 새 블록(끝 · 가운데 · 맨 앞 · setext, 키보드 · 입력 칸 그대로), 밖 누름 확정, 옮기기 + 스크롤 + 누름 오류 없음, 빈 블록 + 상자, 표 · 수식 미리보기 · 큰 표 → 원문, 울타리 [+], 알림 한 번, 칸 인라인 모양 |
| 실기기 | 15.4 체크리스트에 더함: 펜 탭으로 블록 열기 · 펜 끌기 스크롤, 펜 손글씨 → 입력 칸 글자, Gboard · 삼성 키보드의 Enter · 맨 앞 Backspace · 조합, 도구 막대가 키보드 위에 붙음, 회전 중 입력 칸 유지 |

### 24.15 설계 검토 반영 (2026-11-17, 구현 전 — 데이터 D′1~D′16 · UX U′1~U′16)

두 검토(데이터 16건 · UX 16건, `f31a9f4` 대상)의 판정. 받아들임 = 받, 바꿔 받음 = 바, 거절 = 거.

| # | 판정 | 내용 · 이유 |
|---|---|---|
| D′1 · U′1 | 받 | 입력 칸이 열린 동안(`liveHold`) 컨트롤러는 들어온 다른 기기 글을 **버퍼가 깨끗해도 반영하지 않는다**(dirty와 같게). 칸을 닫을 때 그때도 깨끗하고 저장 중이 아니면 붙잡은 글을 반영(지금 ③ 길, 기록 비움). 그 사이 사용자가 다시 치면 dirty → 다음 저장의 base 검사로 L1 사본. 덧붙여 **세대 검사**: 세션은 마지막으로 쓴 버퍼 글(`expect`)을 들고, 쓰기 전마다 `버퍼 == expect`를 본다. 다르면(복원 · 되돌리기 · 할 일 등 다른 길로 버퍼가 바뀜) 쓰지 않고 칸을 닫고 로그 한 줄. 시험: 치기 → 자동 저장 → 다른 기기 글 → 다시 치기 → 사본 또는 받은 글 그대로 |
| D′2 · U′2 | 받 | 세션이 열린 동안 `_onController`는 파싱하지 않는다(`debugParseCount` 그대로 시험). 칸에서 쓰는 것은 `revision`을 올리지 않는다. 다른 블록 할 일 상자는 `P` 오프셋을 세션 범위로 옮겨(뒤 블록은 `+delta`) 토글 |
| D′3 | 받 | 세션은 `parsed.source == 버퍼`인 파싱에서만 연다(아니면 파싱을 기다렸다가 연다). 세션은 연 때의 원문 `P`(=`base`)와 범위 `[start, end)`를 들고, 버퍼는 언제나 `P[0,start) + 바꿈 + P[end..]`로 다시 만든다 — 범위 밖은 `P` 그대로라 오프셋이 낡을 수 없다 |
| D′4 | 받 | 쓰기는 늘 `controller.text` 게터로(옛 컨트롤러를 붙들지 않음). 필드 기록 세기 · `renewField`는 원문 편집기가 마운트됐을 때만 |
| D′5 | 바 | Enter가 칸 안에서 처리되므로 문서 중간에 새 블록을 넣는 길이 없다. 남는 새 블록은 **문서 끝**(끝 [+] · `initialEdit`)과 빈 문서뿐: 마지막 블록 `end` 자리에 `"\n\n"` + 글(끝 빈 줄 · 끝 줄바꿈은 뒤에 그대로), 빈 문서는 구분자 없이. 머리말 위로는 넣지 않음(끝에만 넣으므로) |
| D′6 · U′8 | 받 | 새 블록의 구분자는 **칸이 비어 있지 않을 때만** 버퍼에 있다(버퍼를 매번 `P`에서 다시 만드므로 글자를 지우면 구분자도 함께 빠진다). 빈 새 칸에서 Enter는 아무것도 안 함 |
| D′7 | 받 | 24.10 불변식을 고쳐 씀(위). 확정 뒤 다시 찾기는 키가 아니라 오프셋(`P` 오프셋 → 앞 블록은 그대로, 뒤 블록은 `+delta`) |
| D′8 | 바 | 목록 단위 = **최상위 항목 하나**(표식 줄부터 다음 최상위 표식 줄 앞까지, 안쪽 항목 · 이어진 문단 포함). 안쪽 항목을 누르면 그 최상위 항목이 열린다 — '다음 표식 줄(어느 깊이든)' 규칙의 줄 배정 오류(부모 문단이 자식 칸에)가 생기지 않는다. 최상위 표식 = 들여쓰기 ≤ 3 이고 지금 최상위 항목의 내용 들여쓰기(표식 폭 + 띄어쓰기, 탭은 4칸 멈춤)보다 작은 표식 줄. 켜는 조건: 블록 노드가 `MdList` 하나 · 항목 수 같음 · 범위가 블록을 빈틈(공백뿐) 없이 덮음 · 항목마다 첫 글 6자가 범위 안에 있음. 아니면 블록 통째 |
| D′9 | 받 | setext 제목(`MdHeading` 하나 + 끝 줄이 `=+`/`-+`): 도구 막대 제목 단추를 숨기고, 맨 앞 Backspace의 합치기를 하지 않는다(앞 · 뒤 어느 쪽이 setext여도) |
| D′10 | 받 | `BoundedUndoHistory.seal()` 공개. 세션 열기 · 닫기 · 도구 막대 동작 앞뒤에 부름. 버퍼 값에 칸의 선택(+시작)을 거울 — 기록의 커서가 맞음 |
| D′11 · U′11 | 받 | 단위가 20,000 UTF-16 단위를 넘으면 칸을 열지 않고 원문 모드를 그 위치로 연다(스낵바 '이 블록은 길어서 원문에서 고쳐요') |
| D′12 · U′4 | 받 | 칸의 `TextEditingController` · `FocusNode` · `GlobalKey`는 화면이 갖고(`LiveEditor`), 활성 단위는 `KeepAlive`. 블록을 옮겨도 같은 칸 · 같은 포커스(GlobalKey로 자리만 옮김) — 키보드가 내려가지 않음 |
| D′13 | 받 | MD-T21은 풀린 버퍼 공간에서: `버퍼′ == P`에서 범위만 바뀐 것. 코덱(섞인 줄 끝 R2)은 따로 |
| D′14 | 받 | Tab/Shift+Tab: 줄 머리 들여쓰기 폭 = 위쪽 가장 가까운 표식 줄의 표식 폭(`1. ` → 3, `10. ` → 4, `- ` → 2), 내어쓰기는 같은 폭(없으면 한 글자) |
| D′15 | 받 | 칸(과 원문 편집기)에 입력 거르개: 붙여 넣은 `\r\n` · 외톨이 `\r` → `\n` |
| D′16 | 바 | Shift+Enter = 그냥 `\n`(보기에서는 한 칸 띄움으로 이어짐; `\` 줄바꿈 꾀는 쓰지 않음 — 끝 역슬래시 문제), 목록 항목에서는 `\n` + 내용 들여쓰기. 제목 · 구분선에서는 Enter와 같음. 커서가 표식 안이면 표식 뒤로 보고 처리 |
| U′3 | 받 | 목록 항목(첫 항목 아님) 맨 앞 Backspace: 표식을 빼고 앞 · 뒤 항목과의 `"\n"`을 `"\n\n"`으로 넓혀 목록을 나눈다(범위 = 단위 + 맞닿은 구분자, MD-T21의 '바뀐 범위'에 포함). 안쪽 항목은 칸 안 글이라 Tab/Shift+Tab으로 |
| U′5 | 바 | **Enter는 칸을 나누지 않는다**: 문단 · 제목 = 칸 안에 `"\n\n"`(새 문단 줄), 목록 줄 = `"\n" + 들여쓰기 + 같은 표식`(번호 +1, 할 일 `- [ ] `), 인용 = `"\n> "`, 빈 항목 · 빈 인용 줄 = 표식을 지워 목록에서 나옴. 확정(밖 누름 · Esc · [완료] · 뒤로) 때 다시 파싱하면 여러 블록으로 그려진다. 칸 · 포커스 · IME 연결이 그대로라 키보드 깜빡임 · 한글 상태 초기화가 없다. 다른 블록 누름 · ↑↓도 같은 칸을 옮겨 씀(D′12) |
| U′6 | 받 | 도구 막대는 Scaffold 본문 Column 맨 아래(겹치지 않음, `resizeToAvoidBottomInset`). 키보드가 올라오면 본문이 줄고 칸의 커서는 EditableText가 보이게 스크롤 |
| U′7 | 받 | 도구 막대 동작 전에 조합을 끝냄(조합 범위를 비운 값으로 한 번에 씀). Enter 가로채기는 조합 범위가 빈 바뀜만 |
| U′9 | 바 | 활성 단위는 `SelectionContainer.disabled`. 탭 경쟁: 단위의 탭 인식기가 SelectionArea보다 안쪽이라 먼저 이김(위젯 시험). 고른 것이 있을 때 탭이 고르기만 지우는지 · 펜 탭 지연은 [추측] — 실기기 체크 |
| U′10 | 바 | 칸을 열 때 스크롤하지 않음(커서가 화면 밖일 때만 EditableText가 옮김). 이미지만 있는 문단을 누르면 그 문단 칸이 열림(`![](…)`). '글 위만 누르면 열기'는 거절(짧은 블록은 여백 누름도 필요). 실기기 체크 '펜으로 2분 읽기 — 원치 않은 키보드 수' |
| U′12 | 바 | 설정 키 없이: 문서 끝 [+] 줄 글 '눌러서 이어 쓰기 · 글을 누르면 바로 고쳐요'. `initialEdit`는 불러오기 · `canEdit` 확인 · 첫 파싱 뒤에 칸을 연다 |
| U′13 | 받 | 칸 모양: `card` 바탕 + 1.5 px `accent` 테두리(검색 강조의 `accentSoft` 바탕과 다름), 표식 `textSecondary`(card 위 대비 규칙 안). 골든은 세 스타일 × 밝게/어둡게 |
| U′14 | 받 | 순서: 할 일 · 목록 · 번호 · 제목 1~3 · 굵게 · 기울임 · 취소선 · 코드 · 링크 · 인용 · 들여 · 내어 · 코드 블록 · 수식 · 표 · 구분선, 끝에 고정(스크롤 밖) [합치기][완료]. 이 칸에서 안 되는 단추는 숨김 |
| U′15 | 받 | 도구 막대는 세션이 열려 있으면 늘(키보드가 없어도) 보임. 키보드가 떠 있을 때 시스템 뒤로는 키보드만 내림, 다음 뒤로가 확정 |
| U′16 | 받 | 번호는 다시 매기지 않음(데이터 규칙). 활성 칸 안의 `[ ]`는 글자라 누름 토글 없음(v1). 조합만 바뀐 것도 버퍼 `composing`에 거울 |
| (L-1 추측) | 남김 | Android 화면 키보드의 맨 앞 Backspace 키 이벤트, 한글 조합 중 Enter, 고른 것이 있을 때의 탭 — 실기기 체크(15.4). `\` 줄바꿈 확인은 D′16으로 필요 없음 |

### 24.16 구현 기록 (2026-11-17, v2.18-md)

- **코드**: `packages/feature_markdown/lib/src/live/` — `live_units.dart`(파싱 → 편집 단위, 목록은 최상위 항목, 정의 칩, setext 표시), `live_edit.dart`(순수 편집: `composeLive` · `LiveRange` · Enter/Shift+Enter · 표식 빼기 · 도구 막대 변환 · 들여쓰기 폭 · CR 거르개 · Enter 거르개 · 탭 → 커서 어림), `live_editor.dart`(세션 · 쓰기 · 세대 검사 · 닫기 · 맨 앞 Backspace · 합치기), `live_field.dart`(입력 칸 · 키 처리 · 도구 막대). `parse/list_items.dart`(최상위 항목 범위 + 파서와 맞춰 보기, 블록 안 여러 목록도 항목마다). `MdView`는 `MdLiveView`가 있으면 `liveUnitsOf`로 단위를 만들고(항목마다 한 단위, 열린 범위는 입력 칸 하나, 끝에 [+]/빈 문서 자리), 단위 탭은 `GestureDetector`(링크 · 상자 · 버튼이 먼저). 화면은 원문 편집기를 보기에서 마운트하지 않는다.
- **컨트롤러**: `liveHold`(D′1, 저장으로 base가 바뀌었으면 붙잡은 글을 다시 반영하지 않음 — 저장소가 이미 사본으로 남김), `countFieldHistory`(D′4). `BoundedUndoHistory.seal()`(D′10).
- **함께 고친 것**: `markdown 7.3.1`이 `[]()` 다음 표 구분 줄 같은 입력에서 `BlockParser.parseLines is not advancing`을 던져 문서 전체 파싱이 실패하던 것 — 그 블록만 글로 그린다(`parseMarkdown`, 속성 시험이 찾음; 릴리스에서도 던지는 오류).
- **성능(VM 디버그, `perf_test`)**: 블록 입력 칸 글자당 중앙값 2 KB 15.9 ms · 100 KB 13.6 ms(문서 크기와 무관 — 원문은 100 KB에서 480 ms), 확정 → 다시 그림 100 KB 59 ms. 24.9의 '< 16 ms'는 VM 디버그 TextField 한 글자의 바닥값(약 15~20 ms)과 겹쳐, 시험은 '100 KB ≤ 2 KB의 2배 + 8 ms, < 40 ms'로 둔다. 열린 동안 화면은 저장 상태 등 보이는 것이 바뀔 때만 다시 빌드한다.
- **시험**: `test/live/live_edit_test.dart`(MD-T22 · T23 · T31 순수), `test/live/live_property_test.dart`(MD-T21: 40문서 × 200편집, 열고 닫기만 = 저장 0 · 바이트 같음, 세대 검사, 붙잡기 · 사본, 되돌리기 묶음, 목록 Backspace, 빈 블록), `test/live/live_screen_test.dart`(MD-T22~T30: 새 문서, 탭 커서, CRLF · BOM, 목록 · 번호 · 할 일, Backspace · ↑↓ · Tab · Esc, 도구 막대 · 조합, 되돌리기, 자동 저장 · 조합 1 s · 파싱 없음, 뒤로, 앱 멈춤, 다른 기기 글, 다른 블록 상자, 원문 · 나란히, 검색 착지, 읽기 전용, 끝 [+], 스크롤 유지, 정의 칩 · 링크 시트, 긴 블록 → 원문, 회전), `perf_test` MD-T32, 앱 `markdown_e2e_scenario` 5단계(MD-T33).
- **남은 것 · 실기기**: 24.15 끝의 [추측] 셋(화면 키보드 맨 앞 Backspace 키 이벤트, 한글 조합 중 Enter, 고른 것이 있을 때 탭)과 '펜으로 2분 읽기'. 블록 사이 이동(다른 블록 누름 · ↑↓)은 50 KB 넘는 문서에서는 파싱을 기다리는 동안 키보드가 잠깐 내려갈 수 있다(작은 문서는 같은 프레임). 안쪽 항목만 따로 여는 것과 항목 키(②)는 뒤 라운드.

### 24.17 구현 검토 반영 (2026-11-17, 구현 뒤 — 데이터 검토 1~8 · UX 검토 1~11)

오너 말('노션처럼 잘 보이는 상태에서 편집')에 비해 열린 칸이 여전히 '텍스트 파일'처럼 보인다는 UX 검토와, 바이트는 지키지만 블록 모양이 사용자 뜻과 달라지는 경우를 찾은 데이터 검토를 반영했다. 바이트 규칙(24.3)은 그대로 — 아래 바뀜은 모두 열린 범위(와 그 앞뒤 구분 빈 줄) 안이다.

- **L′1 Enter = 새 블록(U′5 바꿈, UX 1 · 데이터 1)**: 새 문단을 만드는 Enter(목록 · 인용 줄이 아니고, 코드 칸 · 울타리 안이 아니고, 조합 중이 아닐 때)는 칸 안에 빈 줄을 넣지 않고 블록을 나눈다. 블록 끝 → 블록을 닫고 그 뒤에 빈 새 블록(`pendingAfter`), 가운데 → 거기서 둘로 나누고 뒷부분을 커서 0에서 연다, 맨 앞 → 그 앞에 빈 새 블록(`pendingBefore`). 목록 마지막 줄의 빈 항목에서 Enter(목록 나가기)도 빈 항목을 지우고 블록 뒤 새 블록. 같은 `TextField` · `FocusNode` · `GlobalKey`라 키보드와 IME 연결은 그대로(작은 문서는 같은 프레임에 닫고 연다). 새 블록 뒤 줄에 글이 바로 붙어 있으면(`# 제목\n본문`) 뒤에도 빈 줄을 넣어 새 문단이 본문에 붙지 않는다. **50 KB 넘는 문서**(파싱이 다른 isolate)는 Enter마다 키보드가 내려가지 않도록 예전처럼 칸 안 새 문단 — 이때도 뒤 줄에 글이 붙어 있으면 범위 뒤에 빈 줄 하나(`paragraphInField`). 빈 새 블록에서 맨 앞 Backspace = 그 블록을 버리고 앞 블록 끝으로(남는 바이트 없음).
- **L′2 setext 제목(데이터 2)**: 제목 줄에서 Enter는 밑줄 뒤에 새 블록(큰 문서는 칸 안에서 밑줄 뒤 새 문단).
- **L′3 목록 항목 표식이 빠질 때(데이터 3)**: Backspace만이 아니라 도구 막대(목록 · 번호 · 할 일 끄기) · 빈 첫 줄 Enter 등 어떤 길로든 항목 첫 줄에 목록 표식이 없으면 그 동안 범위 앞뒤를 빈 줄로 넓혀(`itemWide`) 위아래 항목과 떨어진 문단이 된다. 표식이 돌아오면 원래 범위로(고정이 아니라 쓸 때마다 계산).
- **L′4 끝 [+] · 빈 문서 자리(데이터 4)**: 마지막 블록이 닫히지 않은 울타리 · HTML 블록이면(`runsToEnd`) 새 블록 대신 그 블록을 끝에서 연다(새 글이 그 안에 들어가는 것을 숨기지 않음).
- **L′5 블록 비우기(데이터 5 · 목록)**: 비운 블록은 앞뒤 빈 줄과 함께 지우되 양쪽 블록 사이에는 빈 줄 하나가 남는다(`para1\n# H\npara2` → `para1\n\npara2`). 가운데 목록 항목은 뒤 줄바꿈과 함께 지워 한 목록이 유지된다(`- a\n- b\n- c` → `- a\n- c`; 예전엔 표식을 먼저 뺀 뒤 비우면 `- a- c`가 될 수 있었다).
- **L′6 할 일 상자(데이터 6)**: 다른 블록이 열린 채 상자를 누르면 그 블록을 닫은 뒤(정리로 글이 움직이면) 상자 위치를 그 바뀜에 맞춰 옮겨 바꾼다(`mapThroughChange`).
- **L′7 줄 판정(데이터 7)**: 구분선(`* * *`, `- - -`)은 목록 줄이 아니다(Enter · 표식 빼기 · 도구 막대). 문단 안의 `2024. …` 줄은 목록 줄이 아니다 — 번호 줄은 칸 첫 줄 · 빈 줄 뒤 · 목록 줄 뒤 · 번호 1일 때만 이어 간다.
- **L′8 빈 항목 남기지 않기(UX 7)**: 닫을 때 마지막 줄이 이 세션이 더한 목록 · 인용 표식뿐이면 지운다(원래 있던 줄은 둔다).
- **L′9 칸 안 인라인 모양(UX 2, 24.5 L-9 구현)**: `**굵게**` · `*기울임*` · `~~취소~~` · `` `코드` `` · `$수식$` · `[링크](주소)`의 표식과 주소는 흐리게, 사이 글은 굵게 · 기울임 · 취소선 · 고정폭 · 링크 밑줄로(`live/live_inline.dart`, 그리기만 — 글자는 그대로). 조합 중인 글자에는 인라인 모양을 칠하지 않는다.
- **L′10 표 · 수식 미리보기(UX 3)**: 표 · 수식 블록을 열면 칸 아래에 그 칸의 글을 그린 모양이 함께 나오고 입력이 멈추면 250 ms 뒤 다시 그린다(누름 막음, `md.live.preview`).
- **L′11 큰 표(UX 3)**: 4,000자 넘는 표는 20,000자 넘는 블록처럼 원문에서 그 자리를 연다(`kMaxLiveTableChars`).
- **L′12 알아보기(UX 8)**: 원문 단추 아이콘을 연필에서 소스 글리프(`Icons.integration_instructions_outlined`)로. 고칠 수 있는 문서를 처음 보기로 열면 기기당 한 번 '글을 누르면 바로 고칠 수 있어요' 알림(`markdown.liveHintShown`, 기기 범위 설정 키 하나 더함, `md.live.hint`).
- **L′13 고르기 오류(UX 5)**: 블록을 옮겨 연 뒤 멀리 스크롤하고 누르면 `RenderBox was not laid out`(SelectionArea가 keep-alive로 남은, 배치 안 된 문단을 셈)이 나던 것 — 목록 칸의 항목에 키를 주고 열린 칸 항목만 따로 키를 줘서(`findChildIndexCallback`) keep-alive 요소가 칸을 따라가고 그려진 단위 밑에 남지 않게 했다. 재현 시험 포함.
- **L′14 밖 누름 = 확정(UX 4, C218M-04 그대로 구현)**: 보기의 빈 곳(여백 · 문서 아래)을 누르면 열린 블록이 닫힌다. 다른 블록 · 링크 · 상자 누름은 그대로 우선, 칸 테두리 누름은 칸.
- **L′15 도구 막대 끝 흐림(UX 11)**: 폰에서 가로로 넘치는 줄 끝 24 px을 막대 색으로 흐리게.
- **받지 않음 · 미룸**: UX 9(뒤로 최대 세 번) — 키보드가 내려간 것을 '닫기'로 보면 회전 · 떠 있는 키보드에서 칸이 닫히므로 그대로 두고 [완료] · 밖 누름으로 닫는다. UX 10(펜 누름마다 키보드)과 24.15 끝의 [추측] 셋은 실기기 확인. 큰 문서의 Enter는 칸 안 문단(L′1). 데이터 검토 8(남의 임시 파일)은 이미 없음.
- **시험**: `test/live/live_structure_test.dart`(MD-T34: 줄 판정 · Enter 종류 · 범위 · 비우기 · 바뀜 따라 옮기기 · `runsToEnd` · 인라인 모양 · 편집기 L′3/L′5/L′8/L′1 큰 문서/L′2), `test/live/live_blocks_screen_test.dart`(MD-T35: 제목 뒤 Enter, 가운데 · 맨 앞 Enter, setext, 밖 누름, 옮기기 + 스크롤 + 누름 두 가지, 빈 블록 + 상자, 표 · 수식 미리보기 · 큰 표 → 원문, 닫히지 않은 울타리 [+], 알림 한 번, 칸 인라인 모양). `live_screen_test`의 새 문서 · 목록 시험과 앱 `markdown_e2e_scenario` 5단계는 Enter = 새 블록으로 바꿈.
