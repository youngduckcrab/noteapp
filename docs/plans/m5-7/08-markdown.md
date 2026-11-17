# 08 · MARKDOWN — MD 문서 v1 (선택안 ①: 파일 그대로 앱 안에서 보기 · 고치기)

> 상태: **설계 (제품 코드 없음)** · 작성 2026-11-17 · 영역 ID **MD** · 바탕 HEAD `c100b05`(브랜치 `claude/note-app-planning-bk29xb`) · 계약 행: 00-overview 7.9에 **v2.17-md C217M-01~C217M-16**으로 더한다(이 문서 14절이 원문). 이 문서와 00-overview 7장이 다르면 7장이 우선한다. 7장에 행이 들어가기 전에는 이 문서 14절이 계약이다.
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
| D2 | 본문은 **열 하나(TEXT)**, 블롭/에셋 아님. 상한 **400,000 바이트(UTF-8)** | 청크 상한 1,000,000 B에 JSON 이스케이프(최악 ≈ 2배는 `\n`만 있는 파일) 여유. 보통 문서는 10~50 KB |
| D3 | 형식 표시 = `Note.format`(JSON `'format'`, ink면 키 생략) + MD 문서의 `schemaVersion = 100`(`kMarkdownNoteSchemaVersion`) | `format`이 진실. 100은 옛 앱 보호막: `format`을 모르는 앱은 `requiresNewerApp`으로 읽기 전용 → 페이지를 더하지 못함. 1~99는 필기 형식 몫 |
| D4 | **동기화한다**(로컬 전용 아님). 본문 `text`는 한 단위 LWW + **충돌 사본** 규칙 | 새 `EntityKind`는 어차피 sync_engine의 빠짐없는 switch를 고쳐야 한다(안 하면 컴파일 안 됨). 로컬 전용이면 `Note`는 동기화되고 본문은 안 가서 **다른 기기에서 문서가 통째로 빈 채** — 요구('문서를 조용히 잃지 않음') 위반. 5절 |
| D5 | 화면은 새 패키지 **`packages/feature_markdown`**(의존 note_core · ink_engine · ui_kit, 플러그인 없음) | 편집기(잉크)와 라이브러리에 파서 · 렌더러를 섞지 않음. 7.1 규칙: 기능 패키지끼리 import 안 함. 웹에서 패키지째 지연 로드 가능 |
| D6 | 파서 = **`markdown` 7.3.1** + 직접 만든 위젯. 수식 = `MathPreview` | 순수 Dart, 의존 추가 없음, GFM. 2.5 |
| D7 | 경로 **`/md/:noteId?q=<검색어>`**. `/notes/:id`로 MD 문서가 오면 `/md/:id`로 돌림 | 편집기(NoteSession)가 MD 문서를 열면 안 됨(페이지를 만들 수 있음). CORE도 막음(4.5) |
| D8 | 파일 고르기 · 저장은 **pdf_io**에 일반 파일 도우미를 더하고, 공유 · 외부 링크 열기는 **앱**(share_plus · url_launcher) | R16: file_picker는 pdf_io만. 앱은 이미 share_plus를 직접 가짐, url_launcher는 잠금에 이미 있음 |
| D9 | 웹은 `feature_markdown` 화면을 **deferred import** | 파서 +59 KB gzip을 main.dart.js 밖으로 |

---

## 4. 저장 모델

### 4.1 `Note` 확장 (기반 단계)

```dart
enum NoteFormat { ink, markdown } // JSON 'format' = name; 'ink'면 키를 쓰지 않음(기존 골든 그대로)
const int kMarkdownNoteSchemaVersion = 100; // MD 문서의 Note.schemaVersion

// Note
final NoteFormat format;              // 기본 ink, 만들 때 정하고 바꾸지 않음(copyWith 없음)
bool get isMarkdown => format == NoteFormat.markdown;
bool get requiresNewerApp => isMarkdown
    ? schemaVersion > kMarkdownNoteSchemaVersion
    : schemaVersion > kNoteSchemaVersion;
```

- `fromJson`: `'format'` 없음 → ink, `'ink'`/`'markdown'` 외 → `FormatException`(받은 기록은 malformed로 건너뜀 — 6.3.5와 같음). `==`/`hashCode`/`toString`에 넣음.
- MD 문서의 `cover`는 `FirstPageCover`(무시 — 카드가 따로 그림), `pageCount` 0, `firstPageId` null.
- `NoteMigrator`는 MD 문서를 건드리지 않는다(형식이 다르므로 단계 없음 — 트랙 A가 가드).

### 4.2 `MarkdownText` 엔티티 (트랙 A)

```dart
final class MarkdownText implements SyncEntity { // EntityKind.markdown (wire name 'markdown')
  static String idFor(NoteId noteId) => 'md_$noteId';
  final String id;        // = idFor(noteId), 결정적
  final NoteId noteId;
  final String text;      // 원문 그대로(BOM · CRLF 포함), ≤ MarkdownLimits.maxTextBytes UTF-8 바이트
  final EpochMillis createdAt, updatedAt;
  final EpochMillis? deletedAt; // v1은 쓰지 않음(휴지통은 노트 단위) — 키는 다른 종류와 같게 둠
  final Hlc? version;
}
// JSON 키: id, noteId, text, createdAt, updatedAt, deletedAt, version
```

결정적 id라서 두 기기가 같은 문서의 본문을 따로 만들 일이 없다(노트 id가 같으면 본문 id도 같다).

### 4.3 DB 스키마 v3 (트랙 A)

`kDatabaseSchemaVersion = 3`, `kSchemaSteps = {1: upgradeV1ToV2, 2: upgradeV2ToV3}`, `drift_schema_v3.json` · 생성 단계 파일 · 이전 시험은 CORE 방식 그대로.

- `notes`에 열 `format TEXT NOT NULL DEFAULT 'ink'` (ALTER TABLE ADD COLUMN — 열 목록 끝, 6.11 규칙).
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
| text_bytes | INTEGER | 로컬 · 파생(UTF-8 바이트 — 저장 공간 표시, 상한 검사) |
| base_text_version | TEXT NULL | **로컬 전용**: 서버에 있다고 알고 있는 `text`의 필드 판본(5.3 충돌 판정). outbox · 백업에 안 감 |

- v3에서 내려가기는 기존 규칙(`NewerSchemaError`)으로 막힌다 → 옛 앱이 'markdown' 검색 원천을 읽을 일 없음.

### 4.4 크기 상한 · 판본

```dart
abstract final class MarkdownLimits {
  static const int maxTextBytes = 400000;   // UTF-8 바이트(원문 그대로)
  static const int maxImportFiles = 20;     // 한 번에 가져오기
  static const int previewChars = 400;      // 카드 미리보기
}
final class MarkdownTooLargeException extends NoteCoreException { final int bytes; }
```

- `saveText`/`create`가 넘으면 `MarkdownTooLargeException` — **아무것도 바꾸지 않음**. 편집기는 글을 그대로 들고 '너무 길어서 저장하지 못했어요' 띠를 보인다(글을 잃지 않음).
- 판본: 쓰기 한 번 = `text` 필드 HLC 하나(outbox `changedFields ['text']`), 노트의 `updatedAt`도 올림(목록 정렬 · 최근). 되돌리기 기록은 CORE 기록(`HistoryState`)에 넣지 않는다 — 편집기 안의 되돌리기(8.7).

### 4.5 CORE 규칙 (트랙 A)

- `MarkdownRepository.create`: `Note`(format markdown, schemaVersion 100, 제목 규칙 1차 그대로 — 다듬기, 1~200자) + `MarkdownText`를 **한 트랜잭션**으로.
- `copyItems`(복제) · `duplicateNoteForRecovery`: 본문을 새 id(`md_<newNoteId>`)로 복사.
- 휴지통: 노트만 `deletedAt`/`trashRootId` — 본문은 그대로. 영구 삭제(purge · 자동 정리 · `RemotePurge`): 노트 묶음과 함께 본문 행 삭제 + 검색 소유자 삭제.
- `openSession(noteId)`가 MD 문서면 `NoteCoreException`(새 하위형 `WrongNoteFormatException`) — 잉크 편집기가 MD 문서에 페이지를 만들지 못하게.
- 백업 내보내기: `EntityKind.values` 순서라서 저절로 들어감(골든 갱신). `base_text_version`·`text_bytes`는 로컬 열이라 빠짐.

### 4.6 원문 보존 규칙 (BOM · 줄 끝)

- 저장은 원문 그대로: 가져온 파일의 U+FEFF(BOM)과 `\r\n`도 `text`에 남긴다 → 손대지 않고 내보내면 **바이트가 같다**.
- 편집기(트랙 B)는 읽을 때 BOM을 떼고 `\r\n`→`\n`으로 보여 주고, 원래 BOM 유무 · CRLF 여부를 기억했다가 저장할 때 되돌린다(`LineEndingCodec`). 고친 문서도 원래 줄 끝 모양을 지킨다. 섞인 줄 끝(일부만 CRLF)인 파일은 편집 전에는 그대로, 한 번 편집하면 많은 쪽으로 통일 — 18절 위험에 적음.

### 4.7 뒤에 블록마다 필기(②)를 붙일 자리

- v1 MD 문서는 페이지 0장. ②에서는 **같은 노트의 `Page`**(+ `Stroke`/`PageObject`)를 '주석 페이지'로 쓰고, 페이지에 새 키 `mdAnchor {blockKey, textHash}`를 단다 → 동기화 · 영구 삭제 · 복제 · 렌더 파이프라인을 그대로 쓴다.
- `blockKey` 규칙을 지금 정한다(v1은 저장하지 않고 화면 안에서만 씀 — 스크롤 복원 · 검색 이동): 최상위 블록의 순번이 아니라 **블록 원문(앞뒤 공백 정리)의 SHA-1 앞 8자 + 같은 해시 안에서의 순번** — 위쪽을 고쳐도 아래 블록의 키가 안 바뀐다.
- v1 규칙: MD 문서에 페이지가 있어도(뒤 버전 앱이 만든 것) **지우지도 보여 주지도 않는다**. 복제 · 영구 삭제는 기존 노트 규칙대로 페이지도 함께.

---

## 5. 동기화

### 5.1 결정과 근거

**동기화한다.** 근거 셋:

1. 엔진은 종류 표로 일반화되어 있다(2.2) — 표에 한 행씩이면 코덱 · 병합 · 게이트 · 보류가 그대로 돈다. `handwriting`도 같은 방식으로 들어왔다.
2. 새 `EntityKind`를 더하면 sync_engine의 빠짐없는 switch를 어차피 고쳐야 한다 — '로컬 전용'으로 해도 이 비용은 그대로이고, 거기에 outbox를 건너뛰는 새 장치가 더 든다.
3. 로컬 전용이면 `Note`(format markdown)는 노트로 동기화되는데 본문은 안 간다 → 다른 기기에 **빈 문서**가 생기고, 거기서 고치면 원래 기기의 본문과 영영 갈린다. '문서를 통째로 조용히 잃지 않음'을 지키려면 본문도 같이 가야 한다.

비용: sync_engine 표 6곳 + 시험(트랙 A, A-10~A-12). 실연결은 여전히 M4.

### 5.2 표 행 (트랙 A — sync_engine)

| 표 | markdown 행 | note 행 바뀜 |
|---|---|---|
| `FieldUnits.keysOf` | `{id, noteId, text, createdAt, updatedAt, deletedAt, version}` | `'format'` 더함 |
| `groupsOf` | `const []` → 단위 `{noteId}` · `{text}` · `{deletedAt}` | 그대로(`format`은 자기 단위, 만든 뒤 안 바뀜) |
| `wholeUnitExcept` | `null` | — |
| `SyncScopes.scopeOf` | `json['noteId']`, 없으면 `noteIdHint`, 없으면 `'lib'`(handwriting과 같음) | — |
| `ChunkPacker.kindOrder` | 맨 끝(`…, handwriting, markdown`) — 기존 순서 그대로 | — |
| `SyncDoc.ownerId` | null(소유자는 노트로 — handwriting과 같음) | — |

`record_gate`의 영구 삭제 판정은 노트 기준(`purged.isStored(EntityRef(note, scope))`)이라 본문도 같이 걸린다 — 시험으로 확인(A-11).

### 5.3 충돌 규칙 (문서 전체를 조용히 잃지 않기)

`text`는 한 단위 LWW(필드 HLC가 큰 쪽)다. 그것만으로는 두 기기가 동시에 고치면 진 쪽의 글이 통째로 사라진다. 그래서 **CORE의 `applyRemote` 안에서**(정책이 결정을 낸 뒤, 같은 트랜잭션) 다음을 한다:

- 조건(모두 참): 받은 기록이 `markdown` 업서트 · 로컬 행이 있음 · 로컬 outbox에 `text`(또는 `*`)가 남아 있음(= 아직 안 올린 로컬 수정) · 받은 `text` ≠ 로컬 `text` · 받은 `text`의 필드 판본 ≠ `base_text_version`(= 로컬 수정이 그 판본을 보고 한 것이 아님 → 동시 수정).
- 동작: 결정이 받은 글을 쓰면(TakeRemote / WriteMerged의 text가 받은 쪽) **로컬 글**을, 로컬 글을 지키면(KeepLocal / WriteMerged의 text가 로컬 쪽) **받은 글**을 새 MD 문서 `'<제목> (충돌 사본 yyyy-MM-dd HH:mm)'`로 같은 폴더에 만든다(로컬 쓰기 — outbox에 들어가 다른 기기에도 감). 사본은 진 쪽 글을 바이트 그대로 가진다.
- `base_text_version` 갱신: 받은 `text`를 쓸 때 = 받은 판본, `acknowledge`로 `text`가 올라갔음이 확인될 때 = 올린 판본.
- 결과: 어느 기기에서 판정되든 두 글이 모두 남는다(한쪽은 원래 문서, 다른 쪽은 사본). 같은 내용이면 사본을 만들지 않는다.
- 나머지는 기존 규칙: 한쪽이 휴지통에 넣고 다른 쪽이 고침 → 단위가 달라 둘 다 반영(휴지통 안 문서가 최신 글). 한쪽이 **영구 삭제**하고 다른 쪽이 안 올린 수정을 가짐 → 필기 노트와 같은 영구 삭제 규칙(purged set — 되살리지 않음). 필기 노트와 같은 수준으로 받아들이고 이 문서에 적어 둔다.
- 노트(format markdown)가 본문보다 먼저 도착(다른 청크 범위): `MarkdownDoc.bodyPresent = false` → 화면은 '내용을 받는 중이에요'를 보이고 **편집을 막는다**(그 사이 고치면 빈 글 위에 새 HLC로 써서 진짜 본문을 이겨 버림). 본문이 오면 그대로 열림.

### 5.4 옛 앱(이 판 이전)과 섞일 때

- `markdown` 기록 → 모르는 종류로 보류(잃지 않음) [확인 S-13].
- `format` 키가 든 노트 → 옛 앱은 키를 모르지만 `schemaVersion 100 > 1` → 읽기 전용 · '새 버전 앱 필요'. 옛 앱이 이름만 바꿔 올려도 필드 단위 병합이라 `format`은 그대로(없는 키는 기준 판본 — `FieldUnits` 주석).

---

## 6. 검색 (트랙 A)

- `SearchSource`에 **`markdown`** 을 더한다(빠짐없는 switch: feature_library `library_strings.dart` · feature_editor `note_search_panel.dart` · `editor_strings.dart` — 트랙 A가 고침, 이름 '문서').
- 소유자: `source 'markdown'`, `ownerKey = noteId`, `note_id = noteId`, `page_id = MarkdownText.idFor(noteId)`(가짜 페이지 id — 히트의 `pageId`), `sourceRev = '<본문 version>:<SearchText.normalizerVersion>'`. 본문 쓰기의 SAVEPOINT 안에서 색인(C-13 방식 — 실패하면 소유자만 pending).
- 단위: 펜스 밖의 빈 줄로 블록을 나누고, 가벼운 정리(파서 안 씀 — note_core는 `markdown` 패키지에 의존하지 않음): 앞의 `#`·`>`·목록 표시·할 일 표시 떼기, `*_~\`` 연속 떼기, `[글](주소)`→글, `![대체](…)`→대체, HTML 태그 떼기, 표의 `|`→공백. 펜스 안 코드는 그대로 색인. 한 단위 ≤ 1,000자(넘으면 자름). `MarkdownIndexText.units(text)`(note_core 내부, 단위 시험).
- 생존 판정 SQL에 분기: `WHEN u.source = 'markdown' THEN (SELECT n.updated_at FROM notes n WHERE n.id = u.note_id AND n.deleted_at IS NULL AND n.owner_id = ?)` — 페이지 JOIN 없음. 사각형 없음(`rects` 비움). 가짜 저장소의 메모리 색인도 같은 판정(CP-14).
- 라이브러리 검색 결과: 제목 맞음은 지금처럼 노트 목록, 본문 맞음은 '노트 내용' 묶음에 **MD 줄**(문서 아이콘 + 조각, 페이지 썸네일 없음) → 누르면 `onOpenMarkdown(noteId, query: 검색어)`.
- 문서 안 이동: 화면(트랙 B)이 `q`를 `SearchText.normalize`로 맞춰 첫 블록을 찾아 스크롤하고 그 부분을 3초 강조한다(8.8).

---

## 7. 패키지 배치 · 의존 규칙

### 7.1 새 패키지 `packages/feature_markdown`

- 의존: `note_core`, `ink_engine`, `ui_kit`(형제, 버전 `any`), `flutter_riverpod 3.4.3`, `material_ui 1.10.0`, `markdown 7.3.1`, `meta 1.19.0`. 개발 의존: `flutter_test`.
- 진입점 둘:
  - `package:feature_markdown/feature_markdown.dart` — 화면(`MarkdownScreen`), `MarkdownKeys`. **웹에서 지연 import** 대상.
  - `package:feature_markdown/slots.dart` — 앱이 덮어쓰는 자리 provider와 typedef만(파서 · 화면 import 없음). 앱은 이것만 즉시 import한다(17절).
- `ink_engine`을 쓰는 곳은 `MathPreview`·`InkMathRenderer.validate`뿐.

### 7.2 `tool/workspace_rules.yaml` 바뀜 (기반 단계)

```yaml
allowed_dependencies:
  feature_markdown: [note_core, ink_engine, ui_kit]
  noteapp: [..., feature_markdown]          # 기존 목록 끝에 더함
plugin_free_members: [..., feature_markdown]
pinned_external:
  markdown: 7.3.1                            # (v2.17-md) feature_markdown direct
  url_launcher: 6.3.3                        # (v2.17-md) app direct — 트랙 A가 앱에 넣을 때(잠금 그대로)
```

- 루트 `pubspec.yaml` `workspace:`에 `packages/feature_markdown` (R1). 패키지에 `analysis_options.yaml` 두지 않음(R3). `lib/`에 `dart:io` 없음(R4). 기능 패키지끼리 import 없음(7.1 규칙 1 · R7 — 라이브러리는 화면을 import하지 않고 앱이 연결).
- `tool/test/ui_colors_test.dart` · `ui_icons_test.dart` 훑는 목록에 `packages/feature_markdown/lib`, `workspace_test.dart` 기대 목록에 새 멤버.
- R16 기준 목록(`r16BaselinePluginFreeMembers`)은 그대로(새 멤버는 yaml에만 더함 — 기준은 '최소'라서 더하는 것은 허용) [확인 rules.dart 1100~1150줄].
- `url_launcher`를 앱에 직접 넣는 것은 앱이 R16 검사 대상이 아니라서 규칙상 되지만, 계약 정신('새 플러그인은 서비스 패키지')과 맞는지 총괄 판단이 필요하다 → 18절 Q1. 기본값: 넣는다(이미 앱이 해석하는 플러그인 — `plugin_packages`에 있음, 새 플러그인이 아님). 안 되면 '열기' 없이 '복사'만.

---

## 8. 보기 · 편집 화면 (트랙 B)

### 8.1 구성

```
packages/feature_markdown/lib/
  feature_markdown.dart          # MarkdownScreen, MarkdownKeys (기반에서 이름 고정)
  slots.dart                     # 자리 provider · typedef (기반에서 고정)
  src/
    screen/markdown_screen.dart  # Scaffold, 위 막대, 보기/편집/나란히, ⋯ 메뉴, 띠
    screen/markdown_controller.dart # 문서 상태: 원문, dirty, 저장 상태, 모드
    parse/md_document.dart       # markdown.Document 설정 + 수식 문법 → 블록 목록
    parse/math_syntax.dart       # $…$ 인라인, $$…$$ / ```math 블록
    parse/task_marks.dart        # 원문에서 할 일 표시 위치 훑기 (8.5)
    parse/block_keys.dart        # 4.7 blockKey, 블록 평문(검색 이동)
    render/md_view.dart          # 최상위 블록 ListView.builder(긴 문서 지연 생성)
    render/md_blocks.dart        # 제목·문단·목록·인용·가로줄·각주
    render/md_inline.dart        # TextSpan 만들기(강조·코드·링크·인라인 수식 WidgetSpan)
    render/md_code.dart · md_table.dart · md_math.dart · md_image.dart · md_link.dart
    render/md_style.dart         # MarkdownStyle.from(StyleTokens, TextTheme, 폭)
    edit/md_editor.dart          # 고정폭 TextField + UndoHistoryController
    edit/autosave.dart           # 지연 저장 · 비우기
    edit/line_endings.dart       # BOM · CRLF 코덱 (4.6)
    strings_ko.dart
```

### 8.2 파서 설정

- `markdown.Document(extensionSet: ExtensionSet.gitHubFlavored, encodeHtml: false, blockSyntaxes: [MathBlockSyntax()], inlineSyntaxes: [MathInlineSyntax()])`. `gitHubWeb`은 쓰지 않는다(이모지 표가 커짐).
- 수식: 인라인 `$x$` — 여는 `$` 뒤와 닫는 `$` 앞이 공백 아님, 닫는 `$` 뒤가 숫자 아님(pandoc 규칙 — '$5 and $6' 보호), `\$`는 글자. 블록 `$$`가 줄 처음에서 열고 닫음, 그리고 ` ```math ` 펜스. 코드 안의 `$`는 코드(코드 문법이 먼저 잡음 — 시험).
- 원시 HTML(블록 · 인라인)은 **글자 그대로** 보인다(해석 안 함).
- 문서가 50 KB를 넘으면 파싱을 `compute`로(네이티브 — 웹은 같은 스레드), 입력 중 미리보기는 200 ms 지연.

### 8.3 렌더링 규칙

| 요소 | 그리는 법 |
|---|---|
| 제목 h1~h6 | `TextTheme` headline/title 크기, h1·h2 아래 `hairline` 선, 위 여백 큰 편 |
| 문단 | `bodyLarge`, 줄 높이 1.6(한국어), `textPrimary` |
| 강조 · 취소선 | w700 · italic · lineThrough |
| 인라인 코드 | 고정폭(`fontFamily: 'monospace'`), `accentSoft` 배경, 둥근 `radiusSmall` |
| 펜스 코드 | 카드(`card` 배경, `hairline` 테두리), 고정폭, **가로 스크롤**(줄 바꿈 안 함), 언어 이름 작은 글씨, [복사] 단추. 문법 색칠 없음(v1) |
| 표 | **가로 스크롤**, 머리줄 w600 + `accentSoft`, 정렬(`:--` `:-:` `--:`) 지킴, 칸 최소 폭 |
| 목록 | 중첩 들여쓰기 24 px씩, 글머리 기호 깊이마다 ● ○ ■, 번호 목록 시작 번호 지킴 |
| 할 일 | 체크 상자(누를 수 있음 — 8.5), 끝난 항목은 `textSecondary` |
| 인용 | 왼쪽 4 px `accent` 띠 + `textSecondary` |
| 가로줄 | `hairline` 1 px |
| 수식 | 인라인 `WidgetSpan(MathPreview(fontSize = 본문 크기, color = textPrimary))`, 블록은 가운데 + 가로 스크롤. `validate` 오류면 원문을 코드 모양 + 경고 색(`StyleTokens`의 오류 색이 없으면 colorScheme.error)으로 |
| 이미지 | `http(s)://` 등 원격: **가져오지 않음** — 점선 상자 + 대체 글 + 호스트 이름 + '이미지를 불러오지 않았어요'. `data:image/(png|jpeg|gif|webp);base64` 이고 풀린 크기 ≤ 2 MB면 `Image.memory`. 상대 경로: '원본 파일의 이미지는 가져오지 않았어요' |
| 링크 | `accent` + 밑줄. 누르면 8.6 |
| 각주 | 위첨자 번호, 문서 끝 각주 목록 |

- 색은 모두 `StyleTokens`/`ColorScheme`에서(새 날 색 금지). 편집기 스타일(`EditorStyleScope` — 11절)과 밝게/어둡게를 그대로 따른다.
- 읽기 폭: 본문 최대 **720 px** 가운데, 좌우 여백 폰 16 / 태블릿 32. 글자 크기는 시스템 글자 배율을 따른다. 보기 모드는 `SelectionArea`(글 고르기 · 복사).

### 8.4 위 막대 · 메뉴

- [←] 제목(누르면 이름 바꾸기 — `LibraryRepository.renameNote`) · **[보기|편집] 단추 하나**(누를 때마다 바뀜, 아이콘 + 글) · (넓을 때) [나란히] · 편집 중이면 [↶][↷] · 저장 상태(작게: '저장됨' / '저장 중…' / '저장하지 못했어요') · [⋯] (`.md로 내보내기`(자리가 있을 때), `이름 바꾸기`, `정보`(글자 수 · 바이트 · 수정 시각)).
- 새 문서('새 MD 문서'로 막 만든 것 — 열 때 `initialMode: edit`)는 편집으로, 그 밖은 보기로 연다.
- 읽기 전용(휴지통 안 · `requiresNewerApp` · `bodyPresent == false`)이면 편집 단추가 꺼지고 이유 띠.

### 8.5 할 일 체크 상자 토글

- `TaskMarks.scan(source)`: 원문을 줄 단위로 훑어(펜스 코드 · 들여쓴 코드 · HTML 블록은 건너뜀, `>` 인용 접두 허용) `^\s*(?:[-*+]|\d+[.)])\s+\[( |x|X)\]` 의 대괄호 안 글자 위치를 문서 순서로 모은다.
- 렌더된 체크 상자 수 == 훑은 수일 때만 토글을 켠다: i번째 상자 → i번째 위치의 글자를 `' '`↔`'x'`로 바꾸고 바로 저장(지연 없이). 수가 다르면(파서와 훑기가 어긋남) 상자는 보이기만 하고 개발자 로그 한 줄 — 원문을 잘못 고치는 일이 없게.
- 편집 모드의 되돌리기 기록에는 들어가지 않음(보기에서 한 일).

### 8.6 링크

- 누르면 바닥 시트: 주소 전체 + [복사] + (자리 `markdownOpenLinkProvider`가 있을 때) [외부 앱에서 열기] + [취소]. 저절로 여는 일 없음. `#제목` 링크는 문서 안 제목으로 스크롤. `mailto:`·`tel:`도 같은 시트.
- 열기는 `http`/`https`/`mailto`/`tel`만, 그 밖(`javascript:`, `file:`, `intent:` …)은 복사만.

### 8.7 편집 · 자동 저장 · 되돌리기

- 편집기: 여러 줄 `TextField`, 고정폭, 맞춤법 줄 끄기(`autocorrect: false`, `enableSuggestions: false` — 마크다운 기호 보호), 같은 읽기 폭, 줄 높이 1.5. 한국어 입력(IME 조합 중에는 저장하지 않고 조합이 끝난 뒤 지연 저장 시작).
- 자동 저장: 마지막 입력 뒤 **700 ms**, 계속 입력 중이면 최대 **5 s**마다 한 번. 그리고 **즉시 비우기**: 보기로 바꿀 때, 뒤로(`PopScope`), 화면 dispose, 앱 숨김/일시정지/분리(`AppLifecycleListener` onHide·onPause·onDetach — 저장을 넣은 뒤 `noteStore.flush()`까지 스스로 부름; 앱의 `AppLifecycleBridge`와 순서가 정해져 있지 않으므로).
- 저장 실패(쓰기 큐 오류 · 상한 초과): 글은 편집기에 그대로, 띠 + [다시 시도]. 성공 전에는 '저장됨'을 보이지 않음.
- 들어오는 변경(`watch`)은 **편집기가 깨끗할 때만** 반영. 고치는 중에 바뀌면 무시(내 저장이 나중에 이김 — 다른 기기 동시 수정은 5.3이 사본으로 지킴).
- 되돌리기 · 다시 하기: `UndoHistoryController`(Ctrl+Z / Ctrl+Shift+Z도). 기록은 화면을 떠나면 사라짐(문서에 적음). 
- 줄 끝 · BOM: 4.6 코덱.

### 8.8 검색 이동

- `initialQuery`가 있으면 첫 프레임 뒤: 블록 평문(`block_keys.dart`)을 `SearchText.normalize`로 맞춰 첫 블록을 찾고, 추정 높이로 뛰어간 뒤 `ensureVisible`, 맞은 글을 `accentSoft`로 3초 강조. 못 찾으면 맨 위(오류 없음).

### 8.9 나란히(있으면 좋은 것)

- 본문 폭 ≥ 1,100 px · 가로일 때만 [나란히]. 왼쪽 편집, 오른쪽 미리보기(200 ms 지연 파싱), 스크롤 연동은 v1 안 함. 선택 상태는 이 기기 설정(`SettingsRepository` 키 `markdown.splitView` — 기기 로컬, 동기화 안 함).

---

## 9. 라이브러리 (트랙 A — feature_library)

- 목록 · 최근 · 즐겨찾기 · 휴지통: MD 문서도 `Note`라 그대로 나온다. 카드 · 줄:
  - 표지 = **글 미리보기 카드**: `card` 바탕에 첫 제목(굵게) + 다음 몇 줄(`textSecondary`, 6.6의 가벼운 정리를 거친 글) + 오른쪽 아래 'MD' 표(`accentSoft` 바탕, 키 `library.tile.mdBadge`). 미리보기는 `markdownPreviewProvider(noteId)`(note_core, `MarkdownRepository.preview` — 400자, 보이는 카드만 읽음). 썸네일 스케줄러는 MD 문서를 건너뜀.
  - 메타 줄: 페이지 수 대신 '문서 · 2.1 KB'(목록 줄), 그 밖은 지금 규칙.
- 메뉴(⋯ · 길게 누름): MD 문서에는 'PDF로 내보내기' · '표지 바꾸기'를 빼고 **'.md로 내보내기'** (자리 `libraryMarkdownExportActionProvider`). 여러 개 고르고 'PDF로 내보내기'를 누르면 MD 문서는 빼고 내보내고 'MD 문서 N개는 빼고 내보냈어요' 알림.
- '새로 만들기': '새 노트' · '새 폴더' · **'새 MD 문서'**(이름 대화상자, 기본 '새 MD 문서' → `MarkdownRepository.create` → 편집 모드로 엶) · 'PDF 가져오기' · **'MD 가져오기'**(자리 `libraryMarkdownImportActionProvider`가 있을 때 — 실행 중이면 꺼짐, `pdf_flows.dart`와 같은 보호).
- 열기: `LibraryScreen`에 `onOpenMarkdown(NoteId id, {String? query, bool edit = false})` 를 더한다. 라이브러리는 `note.isMarkdown`이면 이것을, 아니면 `onOpenNote`를 부른다. `onOpenMarkdown`이 null이면 `onOpenNote`로(앱이 돌림 — 11절).
- 다른 노트를 고르는 곳(PDF '이 노트에 가져오기' 대상 등)에서 MD 문서는 고를 수 없음 — 트랙 A가 `grep`으로 찾아 막는다.

---

## 10. 가져오기 · 내보내기 (트랙 A — pdf_io 일반 파일 도우미 + 앱)

### 10.1 고르기 (pdf_io)

- 새 `lib/src/files/text_file_source.dart`(공개): `TextFileSource.pickTextFiles({bool allowMultiple = true}) → Future<List<PickedPdfFile>?>`(이름은 그대로 쓰되 별칭 `PickedFile` typedef), `FilePicker.pickFiles(type: custom, allowedExtensions: ['md','markdown','txt'], allowMultiple)`. 웹: 탭 처리기 안 동기 호출(Safari) — PDF와 같은 규칙. Android에서 확장자 필터가 MIME으로 안 걸리는 기기는 `FileType.any`로 물러남 + 확장자 검사 [추측 — A가 실기기에서 확인].

### 10.2 해석 (note_core, 순수 Dart)

`MarkdownImport.decode(Uint8List bytes, {required String fileName}) → MarkdownDecodeResult`:

- 크기 > `maxTextBytes` → `tooLarge`('파일이 너무 커요 (최대 400 KB)').
- NUL(0x00) 있음 → `notText`.
- `utf8.decode(bytes, allowMalformed: false)` 실패 → `notUtf8`('UTF-8 텍스트 파일만 가져올 수 있어요'). CP949 등은 v1에서 받지 않는다(바이트 그대로 내보내기를 지킬 수 없음).
- 성공: `text` = 풀린 글 그대로(BOM 포함 — 4.6), `title` = 파일 이름에서 확장자 뗌, NFC로 정규화(macOS NFD 이름), 다듬기, 비면 '가져온 문서', 200자로 자름.
- 시험: `utf8.encode(decode(b).text)`가 `b`와 같다(BOM · CRLF · 한글 · 이모지 · 4바이트 글자).

### 10.3 흐름 (앱 — `app/lib/src/modules/markdown_wiring.dart`)

- 고른 파일마다(최대 20, 넘으면 앞의 20개 + 알림) 해석 → 성공은 `MarkdownRepository.create(folderId, title, text)`. 하나면 그 문서를 연다, 여럿이면 'MD 문서 N개를 가져왔어요' (+ 실패 'M개는 가져오지 못했어요 — 이유'). 같은 이름은 그대로 둔다(노트 규칙과 같음).

### 10.4 내보내기

- 바이트 = `utf8.encode(text)`(text는 원문 그대로 — BOM · CRLF 보존 → 가져온 그대로면 바이트 같음). 파일 이름 = `PdfFileNaming.sanitize(title)` + (제목이 `.md`/`.markdown`으로 끝나지 않으면) `.md`. MIME `text/markdown`.
- 출력: pdf_io에 새 공개 `DocumentFileOutput`(같은 플랫폼 분기 — 네이티브: `FilePicker.saveFile` '저장' + 앱의 공유 함수 '공유', 웹: Web Share(파일 공유 가능할 때) · 다운로드). 기존 `PdfOutputSink` 내부의 저장 · 다운로드 함수를 바이트 + 이름 + MIME 형으로 빼서 둘이 같이 쓴다(`PdfOutputSink` 공개 표면은 그대로). 앱은 `pdf_share_native.dart` 옆에 `document_share_native.dart`(share_plus `XFile.fromData(mimeType: 'text/markdown')`).
- 작은 시트 '[공유] [저장]'(웹 '[공유] [다운로드]') — `PdfExportResultSheet`를 쓰지 않고 앱이 간단히 그림(PDF 문구가 박혀 있음).
- 자리 둘을 같은 앱 함수로: 화면 ⋯ 메뉴(`markdownExportActionProvider` — feature_markdown slots) · 라이브러리 메뉴(`libraryMarkdownExportActionProvider` — feature_library).

---

## 11. 라우팅 (트랙 A — app)

- `AppRoutes.markdownPattern = '/md/:noteId'`, `AppRoutes.markdownQueryKey = 'q'`, `AppRoutes.markdownEditKey = 'edit'`(값 `1`), `AppRoutes.markdown(String noteId, {String? query, bool edit = false})`.
- `MarkdownRouteArgs(noteId, initialQuery, initialEdit)`, `AppScreenBuilders.markdown`, `AppNavigator.openMarkdown(id, {query, edit})` · `closeMarkdown()`(= `closeNote`와 같은 돌아가기).
- 페이지: `NoTransitionPage(key: state.pageKey)` + `wrapEditor`(**편집기 스타일**로 — 필기 화면 스타일이 '문서를 읽고 쓰는 화면'의 스타일).
- `/notes/:noteId`에 MD 문서가 오면(주소 직접 · 옛 즐겨찾기): `createAppRouter(…, isMarkdownNote: Future<bool> Function(String noteId))` 를 받고 그 경로의 `redirect`(go_router 비동기 redirect)에서 참이면 `/md/:id`로. 기본값은 `(_) async => false`(지금 시험 그대로). 앱은 `libraryRepository.getNote(id)`로 판정.
- `/md/:id`에 필기 노트가 오면 화면(트랙 B)이 '이 문서는 MD 문서가 아니에요' + [노트로 열기](`onOpenAsNote` 콜백).
- 화면 생성: `deferred as md` import → `md.loadLibrary()`를 `FutureBuilder`로 기다리며 빈 바탕(`canvas`)만 보임(네이티브는 바로 끝남 [추측 — 17절]).
- `LibraryScreen.onOpenMarkdown` → `navigator.openMarkdown`. 검색 결과 → `query` 붙임. '새 MD 문서' → `edit: true`.

---

## 12. 공개 API (기반 단계에서 얼리는 것)

### 12.1 note_core

```dart
// src/model/note.dart
enum NoteFormat { ink, markdown }
const int kMarkdownNoteSchemaVersion = 100;
// Note: + NoteFormat format (생성자 기본 ink), + bool get isMarkdown, requiresNewerApp(4.1)

// src/repo/markdown_repository.dart
abstract final class MarkdownLimits {
  static const int maxTextBytes = 400000;
  static const int maxImportFiles = 20;
  static const int previewChars = 400;
}

final class MarkdownTooLargeException extends NoteCoreException {
  const MarkdownTooLargeException(super.message, {required this.bytes});
  final int bytes;
}

@immutable
final class MarkdownDoc {               // ==/hashCode
  const MarkdownDoc({required this.note, required this.text, required this.bodyPresent, this.textVersion});
  final Note note;                      // format == markdown
  final String text;                    // bodyPresent == false → ''
  final bool bodyPresent;               // 본문 엔티티가 아직 없음(동기화 중) → 편집 금지
  final Hlc? textVersion;               // 마지막 text 쓰기의 필드 판본(화면은 비교만)
  bool get isReadOnly => note.isDeleted || note.requiresNewerApp || !bodyPresent;
}

abstract interface class MarkdownRepository {
  /// 노트가 없거나 MD 문서가 아니면 null. 첫 값은 listen 직후 한 번(라이브러리 C-1 규칙).
  Stream<MarkdownDoc?> watch(NoteId id);
  Future<MarkdownDoc?> get(NoteId id);
  /// Note(format markdown, schemaVersion 100) + 본문을 한 트랜잭션으로. 제목 규칙은 createNote와 같음.
  /// ArgumentError(제목), MarkdownTooLargeException(본문).
  Future<Note> create({FolderId? folderId, required String title, String text = ''});
  /// 로컬 쓰기(outbox 'text', note.updatedAt 올림). 같은 글이면 아무것도 안 함.
  /// EntityNotFoundException(없음·MD 아님), ReadOnlyNoteException(휴지통·새 버전·본문 없음),
  /// MarkdownTooLargeException(상한).
  Future<void> saveText(NoteId id, String text);
  /// 카드 미리보기: 앞 [maxChars]자를 6장의 가벼운 정리로(본문 없으면 '').
  Future<String> preview(NoteId id, {int maxChars = MarkdownLimits.previewChars});
}

// NoteStore: + MarkdownRepository get markdown;
// providers.dart
final markdownRepositoryProvider = Provider<MarkdownRepository>((ref) => ref.watch(noteStoreProvider).markdown);
final markdownDocProvider = StreamProvider.autoDispose.family<MarkdownDoc?, NoteId>(...);
final markdownPreviewProvider = FutureProvider.autoDispose.family<String, NoteId>(...);
```

- 기반 단계 구현: `FakeNoteStore.markdown` = 동작하는 메모리 구현(가짜 라이브러리 목록 · 휴지통에 나옴, `watch` 갱신, 상한 · 읽기 전용 검사) — 트랙 B가 이것으로 시험한다. `DriftNoteStore.markdown` = `UnsupportedError('markdown: track A')`를 던지는 자리(트랙 A가 바꿈 — 그 전에는 앱이 화면을 연결하지 않으므로 안 불림).

### 12.2 feature_markdown

```dart
// feature_markdown.dart
class MarkdownScreen extends ConsumerStatefulWidget {
  const MarkdownScreen({
    super.key,
    required this.noteId,
    this.initialQuery,          // 검색 이동(8.8)
    this.initialEdit = false,   // 편집 모드로 열기
    required this.onClose,      // 뒤로(저장을 비운 뒤 부름)
    this.onOpenAsNote,          // /md/에 필기 노트가 왔을 때 [노트로 열기]
  });
}
abstract final class MarkdownKeys { /* 13절 문자열 전부 */ }

// slots.dart (파서 import 없음)
typedef MarkdownExportAction = Future<void> Function(BuildContext context, {required String title, required String text});
final markdownExportActionProvider = Provider<MarkdownExportAction?>((ref) => null); // null → 메뉴 숨김
typedef MarkdownOpenLinkAction = Future<bool> Function(Uri uri);                       // false = 열지 못함 → '열지 못했어요'
final markdownOpenLinkProvider = Provider<MarkdownOpenLinkAction?>((ref) => null);     // null → [열기] 없음, 복사만
```

### 12.3 ui_kit (AppIconKind 더함, Material 글리프만 — 선 그림 없음)

`markdownDoc`(description), `newMarkdown`(note_add), `importMarkdown`(file_open), `exportMarkdown`(file_download), `editSource`(edit_note), `viewRendered`(chrome_reader_mode), `splitView`(vertical_split), `link`(link).

### 12.4 트랙 A가 더하는 공개 표면(기반 뒤 — A 안에서만 바뀜)

- note_core: `EntityKind.markdown`, `MarkdownText`, `SearchSource.markdown`, `WrongNoteFormatException`, `MarkdownImport`/`MarkdownDecodeResult`(+ `MarkdownDecodeFailure {tooLarge, notText, notUtf8}`).
- feature_library: `LibraryScreen.onOpenMarkdown`, `LibraryMarkdownImportAction`/`libraryMarkdownImportActionProvider`, `LibraryMarkdownExportAction`/`libraryMarkdownExportActionProvider`.
- pdf_io: `TextFileSource`, `FilePickerTextSource`, `DocumentFileOutput`, `createPlatformDocumentOutput`.

---

## 13. 키 이름

화면(트랙 B, `MarkdownKeys`): `md.screen` · `md.back` · `md.title` · `md.mode`(보기/편집 단추) · `md.split` · `md.undo` · `md.redo` · `md.saveState` · `md.more` · `md.menu.export` · `md.menu.rename` · `md.menu.info` · `md.view`(보기 스크롤) · `md.editor`(TextField) · `md.banner.readOnly` · `md.banner.receiving` · `md.banner.tooLarge` · `md.banner.saveFailed` · `md.notMarkdown` · `md.block.<i>` · `md.task.<i>` · `md.link.<i>` · `md.linkSheet` · `md.linkSheet.copy` · `md.linkSheet.open` · `md.code.<i>` · `md.code.<i>.copy` · `md.table.<i>` · `md.math.<i>` · `md.image.<i>` · `md.highlight`(검색 강조).

라이브러리(트랙 A): `library.new.markdown` · `library.new.importMarkdown` · `library.tile.mdBadge` · `library.tile.mdPreview` · `library.menu.exportMarkdown` · `library.hit.markdown.<noteId>`.

설정 키: `markdown.splitView`(기기 로컬, bool, 기본 false).

---

## 14. 계약 행 v2.17-md (00-overview 7.9에 그대로 더함)

#### v2.17-md (2026-11-17, MD 문서 v1 — 오너 말 'PDF뿐만 아니라 md파일도 읽을 수 있으면 좋겠다', 선택안 ①)

추가와 저장 형식 바뀜(DB 스키마 v3, 새 동기화 종류 `markdown`, 노트 JSON 키 `format`). 설계는 [08-markdown.md](08-markdown.md).

| # | 절 | 변경 | 출처 | 반영할 영역 |
|---|---|---|---|---|
| C217M-01 | 7.2.6 CORE 노트 | `NoteFormat {ink, markdown}`, `Note.format`(JSON `'format'`, ink면 키 없음, 그 밖의 값은 FormatException), `kMarkdownNoteSchemaVersion = 100`, `requiresNewerApp`는 형식별 판본과 비교. 만든 뒤 형식은 안 바뀜 | 오너 요청 | 기반 |
| C217M-02 | 7.2.6 CORE 새 엔티티 | `EntityKind.markdown`(wire 'markdown') · `MarkdownText{id 'md_<noteId>', noteId, text, createdAt, updatedAt, deletedAt, version}`. 노트 하나에 하나, 결정적 id | 오너 요청 | A |
| C217M-03 | 7.2.7 저장 형식 | DB 스키마 v3: `notes.format TEXT NOT NULL DEFAULT 'ink'`, 새 표 `md_docs`(+ 로컬 `text_bytes`, `base_text_version`), 단계 v2→v3. 백업에 `markdown` 종류 | 오너 요청 | A |
| C217M-04 | 7.2.x CORE 저장소 | `MarkdownRepository`(watch/get/create/saveText/preview), `MarkdownDoc{note, text, bodyPresent, textVersion}`, `MarkdownLimits{maxTextBytes 400000, maxImportFiles 20, previewChars 400}`, `MarkdownTooLargeException`, `NoteStore.markdown`, `markdownRepositoryProvider` · `markdownDocProvider` · `markdownPreviewProvider` | 오너 요청 | 기반(형·가짜) · A(실제) |
| C217M-05 | 7.2.x CORE 규칙 | 만들기 = 노트 + 본문 한 트랜잭션. 복제 · 복구 복제는 본문 복사. 휴지통은 노트만, 영구 삭제는 본문 · 검색 소유자 함께. `openSession`은 MD 문서에 `WrongNoteFormatException`. 노트 형식 이전은 MD 문서를 건드리지 않음. MD 문서의 페이지(뒤 버전)는 지우지도 보이지도 않음 | 오너 요청 | A |
| C217M-06 | 7.2.8 SYNC 매핑 | keysOf(markdown) = {id, noteId, text, createdAt, updatedAt, deletedAt, version}, groupsOf = [], wholeUnitExcept = null, scope = json noteId → hint → 'lib', kindOrder 맨 끝, ownerId null. keysOf(note)에 'format' | 5.1 결정 | A |
| C217M-07 | 7.2.10 충돌 규칙 | `applyRemote`에서 본문 동시 수정(로컬 outbox에 text · 글 다름 · 받은 판본 ≠ base_text_version)이면 진 쪽 글을 새 MD 문서 '<제목> (충돌 사본 yyyy-MM-dd HH:mm)'로 같은 폴더에(로컬 쓰기). 같은 글이면 사본 없음. 본문이 아직 없는 문서는 편집 금지(bodyPresent) | 오너 요구 '문서 통째로 조용히 잃지 않음' | A |
| C217M-08 | 7.2.5 검색 | `SearchSource.markdown`, 소유자 = noteId, 히트 pageId = 'md_<noteId>', 사각형 없음, 생존 = 노트가 휴지통 밖. 단위 = 빈 줄 블록 + 가벼운 기호 정리, ≤ 1,000자 | 오너 요청 | A |
| C217M-09 | 7.1 패키지 | 새 멤버 `feature_markdown`(의존 note_core · ink_engine · ui_kit, 플러그인 없음, 진입점 `feature_markdown.dart` · `slots.dart`). 앱 의존 더함. workspace_rules: allowed_dependencies · plugin_free_members · noteapp 행 | 6.x 결정 | 기반 |
| C217M-10 | 7.5 외부 버전 | `markdown 7.3.1`(feature_markdown 직접 — 잠금에 한 줄), `url_launcher 6.3.3`(앱 직접 — 잠금 그대로) | 2.5 | 기반(markdown) · A(url_launcher) |
| C217M-11 | 7.2.11 LIBRARY | `LibraryScreen.onOpenMarkdown(id, {query, edit})`, '새로 만들기'에 '새 MD 문서' · 'MD 가져오기'(자리 `libraryMarkdownImportActionProvider`), MD 카드(글 미리보기 + 'MD' 표), MD 메뉴 '.md로 내보내기'(자리 `libraryMarkdownExportActionProvider`) · PDF 내보내기 · 표지 바꾸기 뺌, 검색 MD 줄 | 오너 요청 | A |
| C217M-12 | 7.2.12 PDF 파일 도우미 | pdf_io 공개 `TextFileSource`/`FilePickerTextSource`(md · markdown · txt, 여러 개), `DocumentFileOutput`/`createPlatformDocumentOutput`(바이트 + 이름 + MIME 저장 · 공유 · 다운로드). `PdfOutputSink` 표면 그대로 | R16 | A |
| C217M-13 | 4.5.5 INFRA 경로 | `/md/:noteId?q=&edit=1`, `MarkdownRouteArgs`, `AppNavigator.openMarkdown`/`closeMarkdown`, 편집기 스타일로 감쌈, `/notes/:id`의 MD 문서는 `/md/:id`로(비동기 redirect), 화면은 deferred import | D7 · D9 | A |
| C217M-14 | 화면 | `MarkdownScreen(noteId, initialQuery, initialEdit, onClose, onOpenAsNote)`, 보기 ↔ 편집 단추 하나, 자동 저장(700 ms · 최대 5 s · 떠날 때 · 앱 숨김 때 비움), 되돌리기, 할 일 토글(원문 훑기 수가 맞을 때만), 링크는 묻고 열기/복사, 원격 이미지 안 가져옴, 수식 MathPreview, 넓은 화면 나란히(설정 `markdown.splitView`) | 오너 요청 | B |
| C217M-15 | 자리 | feature_markdown `slots.dart`: `MarkdownExportAction`/`markdownExportActionProvider`, `MarkdownOpenLinkAction`/`markdownOpenLinkProvider`(앱이 url_launcher로, http · https · mailto · tel만) | D8 | 기반(형) · A(연결) |
| C217M-16 | 가져오기 · 내보내기 | UTF-8만(BOM 허용 · 보존), NUL 있으면 거절, 원문 그대로 저장, 내보내기 = `utf8.encode(text)` → 가져온 그대로면 바이트 같음. 이름 = 정리한 제목 + '.md'. 400 KB 넘으면 거절 | 오너 요청 | A |

---

## 15. 작업 분해

### 15.0 원칙

- **기반(FOUNDATION)** 을 먼저 이 브랜치에 커밋한다. 그 뒤 트랙 A · B는 **겹치는 파일 없이** 따로 간다(각자 worktree/브랜치 → 이 브랜치로 병합, push · PR 없음).
- 트랙 A 소유: `packages/note_core/**`, `packages/sync_engine/**`, `packages/feature_library/**`, `packages/pdf_io/**`, `packages/feature_editor/**`(SearchSource 분기 두 파일만), `app/**`, `tool/workspace_rules.yaml`(url_launcher 한 줄), `docs/**`.
- 트랙 B 소유: `packages/feature_markdown/**` 만. 공개 표면(12.2의 이름 · 매개변수)은 바꾸지 않는다(더하는 것은 B 안에서 — R14 · api_surface 시험 함께).
- 마지막 **통합(I)** 은 A가 한다(앱에서 실제 화면으로 끝까지 시험).

### 15.1 기반 (작게 — 한 커밋)

| # | 파일 | 내용 |
|---|---|---|
| F-1 | `packages/note_core/lib/src/model/note.dart` | `NoteFormat`, `Note.format`(JSON 생략 규칙, ==, hashCode, toString), `kMarkdownNoteSchemaVersion`, `isMarkdown`, `requiresNewerApp` |
| F-2 | `packages/note_core/lib/src/repo/markdown_repository.dart`(새), `repo/note_store.dart`, `providers.dart`, `note_core.dart`(export) | 12.1 형 · 인터페이스 · provider 셋 |
| F-3 | `packages/note_core/lib/src/fake/fake_note_store.dart`(+ 필요하면 `fake/fake_markdown.dart` 새) | 동작하는 메모리 `MarkdownRepository`(가짜 라이브러리에 나옴) |
| F-4 | `packages/note_core/lib/src/storage/drift_note_store.dart` | `markdown` → `UnsupportedError` 자리 |
| F-5 | `NoteStore` 구현 시험 가짜 3곳: `note_core/test/api_surface_test.dart`, `sync_engine/test/local/core_sync_local_store_test.dart`, `app/test/fakes/counting_note_store.dart` | getter 더함. api_surface에 새 이름 |
| F-6 | `packages/note_core/test/model/note_format_test.dart`(새) · `test/repo/fake_markdown_test.dart`(새) | JSON 왕복 · 생략 규칙 · 모르는 값 거절 · requiresNewerApp · 가짜 저장소 동작 |
| F-7 | `packages/ui_kit/lib/src/app_icons.dart` | 12.3의 8개 |
| F-8 | `packages/feature_markdown/`(새): `pubspec.yaml`, `lib/feature_markdown.dart`(`MarkdownScreen` — 빈 화면 + '준비 중', `MarkdownKeys` 전부), `lib/slots.dart`, `test/api_surface_test.dart`, `README.md` 한 단락 | 12.2 고정 |
| F-9 | 루트 `pubspec.yaml`(workspace), `pubspec.lock`(markdown 한 줄), `tool/workspace_rules.yaml`(7.2 — url_launcher 줄은 A), `tool/test/ui_colors_test.dart` · `ui_icons_test.dart` · `workspace_test.dart` | 규칙 · 목록 |
| F-10 | 검사 | `dart run tool/ws.dart check --strict` 0, 루트 `flutter analyze` 0, `dart format`, note_core · ui_kit · feature_markdown · tool 시험, `ws lock-age` |

기반에 넣지 않는 것: `EntityKind.markdown`(빠짐없는 switch가 note_core · sync_engine 안에만 있어 A 안에서 닫힘), `SearchSource.markdown`(A — feature_library · feature_editor 분기 포함), 앱 경로.

### 15.2 트랙 A — 데이터 · 저장 · 동기화 · 검색 · 라이브러리 · 가져오기/내보내기 · 경로

| # | 일 | 시험(대표) |
|---|---|---|
| A-1 | `EntityKind.markdown` · `MarkdownText`(JSON) · `EntityJson.decode` · 모든 note_core switch(row_mappers, drift_sync_store, drift_trash_repository, fake store, backup/canonical dump 골든) | `markdown_text_test`, core JSON 골든 |
| A-2 | DB v3: `tables.dart`(`MdDocs`, `notes.format`), `migrations.dart` v2→v3, `drift_dev make-migrations`(스키마 json · steps · 생성 이전 시험), V7 고정물 이전 시험 v1→v3 · v2→v3 | `schema_v3_test`, 이전 시험 |
| A-3 | `DriftMarkdownRepository`(create · saveText · watch · get · preview, 상한, 읽기 전용, outbox 'text', note.updatedAt, ChangeBatch) + `DriftNoteStore.markdown` | 공유 계약 시험 `markdown_contract.dart`(실제 + 가짜 둘 다 통과) |
| A-4 | 복제 · 복구 복제 · 영구 삭제 · 자동 정리 · `RemotePurge`에 본문 | `note_copy_md_test`, `trash_md_test` |
| A-5 | `openSession` 가드(`WrongNoteFormatException`), `NoteMigrator` 가드 | `session_md_guard_test` |
| A-6 | 가짜 저장소를 실제와 같게(복제 · 영구 삭제 · 검색 · 충돌 사본 없음 표시) | 공유 계약 시험 |
| A-7 | 검색: `SearchSource.markdown`, `MarkdownIndexText.units`, 색인기 hook, 생존 SQL 분기, 가짜 메모리 색인, feature_library · feature_editor 분기 | `md_index_text_test`, `library_search_md_test`(실제 + 가짜) |
| A-8 | `MarkdownImport.decode` | 바이트 왕복 표(BOM · CRLF · 한글 · 이모지 · 잘못된 UTF-8 · NUL · 상한) |
| A-9 | 충돌 규칙(5.3) — `applyRemote` 안, `base_text_version` 갱신(applyRemote · acknowledge) | `md_conflict_copy_test`(사본 생김 / 안 생김 6경우) |
| A-10 | sync_engine 표 6곳(5.2) + `field_units_test` · `scopes_test` · `chunk_packer_test` · 시험 장치(`test_device`, `fake_sync_store`, `sync_test_harness`)의 markdown 행 | 단위 시험 |
| A-11 | 두 기기 시나리오(실제 CORE v3 둘, `integration` 태그): 만들기 → 다른 기기에 본문, 동시 수정 → 사본, 휴지통 vs 수정, 영구 삭제, 노트 먼저 · 본문 나중 | `core_markdown_scenarios_test` |
| A-12 | `core_json_keys_test`에 markdown · note.format | JSON 키 대조 |
| A-13 | pdf_io: `TextFileSource`, `DocumentFileOutput`(sink 내부 함수 빼기), 배럴 export, R14 이름 시험 · api_surface | 네이티브 · 브라우저 단위 시험(가짜 저장/공유 함수) |
| A-14 | feature_library: 새 메뉴 2개 · 자리 provider 2개 · `onOpenMarkdown` · MD 카드/줄 · 메타 · 메뉴 분기 · 여러 개 PDF 내보내기 거르기 · 썸네일 건너뜀 · 검색 MD 줄 · 노트 고르기 대상에서 빼기 | 위젯 시험(가짜 저장소) |
| A-15 | 앱: 경로 · 인자 · navigator · 화면 builder(deferred) · `/notes/` redirect · `markdown_wiring.dart`(가져오기 흐름, 내보내기 시트, 링크 열기 url_launcher — Q1 판정 뒤) · `document_share_native.dart` · 자리 override(FeatureWiringModule) · `licenses.dart`(markdown BSD 표시가 자동인지 확인) | `production_screens_test` · `markdown_routing_test` · `markdown_wiring_test` |
| A-16 | 문서: 00-overview 7.9에 14절 표, 이 문서 상태 줄 · 진행 기록 | — |
| A-17 | 웹 빌드로 main.dart.js 차이 재기(17절), `ws web-budget check` 결과 보고 | 숫자 보고 |

### 15.3 트랙 B — 화면 (`packages/feature_markdown/**`)

| # | 일 | 시험(대표) |
|---|---|---|
| B-1 | 파서 설정 · 수식 문법(8.2) | `parse_test`(GFM 표 · 할 일 · 각주 · 코드 안 `$` · '$5 and $6' · `\$` · `$$` 블록 · ```math) |
| B-2 | 블록 모델 · blockKey(4.7) · 평문 | `block_keys_test`(위를 고쳐도 아래 키 그대로) |
| B-3 | 렌더러: 블록 · 인라인 · 코드(가로 스크롤 · 복사) · 표(가로 스크롤 · 정렬) · 목록(중첩 · 번호 시작) · 인용 · 가로줄 · 각주 | 위젯 시험 + 골든(크래프트/미니멀/스튜디오 × 밝게/어둡게, 폰 390 · 태블릿 1194 가로) |
| B-4 | 수식(MathPreview, 오류 대체) | 위젯 시험 |
| B-5 | 이미지(원격 자리 표시 · data: 그림 · 2 MB 상한 · 상대 경로) — 네트워크 호출 0 확인 | `HttpOverrides`로 호출 감지 시험(VM) |
| B-6 | 링크 시트(복사 · 자리 있을 때 열기 · 막는 스킴 · `#` 이동) | 위젯 시험 |
| B-7 | 할 일 토글 + `TaskMarks.scan` | 원문 바뀜 · 수 어긋나면 읽기 전용 · 인용 · 펜스 안 무시 |
| B-8 | 편집기 · 줄 끝/BOM 코덱 · 되돌리기 | 코덱 왕복 · 되돌리기 단추 |
| B-9 | 자동 저장(지연 · 최대 · 비우기 — 모드 바꿈 · 뒤로 · dispose · 앱 숨김) · 실패 띠 · 깨끗할 때만 watch 반영 · IME 조합 중 보류 | `fake_async` 시험, 저장 실패 가짜 |
| B-10 | 화면: 위 막대 · 모드 단추 · 읽기 전용 띠(휴지통 · 새 버전 · 받는 중 · 상한) · ⋯ 메뉴(내보내기 자리, 이름 바꾸기, 정보) · MD 아님 화면 | 위젯 시험 |
| B-11 | 검색 이동 · 강조(8.8) | 긴 문서(2,000 블록)에서 찾아감 |
| B-12 | (있으면 좋음) 나란히 · 설정 키 | 폭 1,100 기준 |
| B-13 | 성능: 100 KB 문서 첫 그림 < 300 ms(VM 위젯 시험 기준치, `perf` 태그), 입력 한 글자 프레임 영향 없음(미리보기 지연) | perf 시험 |
| B-14 | 문구 · 접근성(의미 이름: 체크 상자 '할 일 완료/안 함', 링크 '링크: <주소>') · 글자 배율 2.0 | 위젯 시험 |

### 15.4 통합 (A가, 둘 병합 뒤)

`app` 끝까지: 가져오기(가짜 고르기) → 열림 → 편집 → 뒤로 → 라이브러리 미리보기 갱신 → 검색 → 맞는 곳 → 내보내기 바이트 같음 → 휴지통 → 되살리기 → 영구 삭제. 실제 CORE(VM). Android 실기기 체크리스트(00-overview 7.8 형식)에 MD 항목 8개.

---

## 16. 수용 시험

| ID | 시험 | 트랙 |
|---|---|---|
| MD-T01 | `Note` JSON: ink는 `'format'` 키 없음(기존 골든 바이트 그대로), markdown 왕복, 모르는 값 FormatException, MD 문서 `requiresNewerApp` = schemaVersion > 100 | 기반 |
| MD-T02 | 가짜 · 실제 저장소 공유 계약: create → 라이브러리 목록 · 최근에 나옴, saveText → watch 새 값 · note.updatedAt 올라감 · outbox `['text']`, 400,001 바이트 거절하고 아무것도 안 바뀜, 휴지통 문서 saveText → ReadOnlyNoteException | A |
| MD-T03 | 복제 → 새 id 본문 같은 글, 영구 삭제 → `md_docs` 행 · 검색 소유자 없음, 휴지통 → 되살리기 글 그대로 | A |
| MD-T04 | 스키마 v1 · v2 고정물 → v3 이전: 노트 전부 format ink, `md_docs` 빈 표, 생성 SQL이 새 v3 DB와 같음 | A |
| MD-T05 | 검색: 본문 낱말로 `searchLibrary` → `PageSearchHit(source markdown, pageId 'md_<id>')`, 휴지통 문서는 안 나옴, 한 글자 검색(LIKE), 표 · 목록 기호 안의 낱말 | A |
| MD-T06 | 가져오기 바이트 왕복: BOM + CRLF + 한글 + 이모지 파일 → 내보낸 바이트가 같음. CP949 바이트 → notUtf8, NUL → notText | A |
| MD-T07 | 동기화 표: keysOf/units/scope/kindOrder, 옛 앱(markdown 모르는 kind 목록) → 보류 · 버리지 않음 | A |
| MD-T08 | 두 기기 동시 수정 → 둘 다 수렴하고 진 글이 '충돌 사본' 문서로 정확히 하나, 같은 글이면 사본 없음, 순서 바꿔도 같은 결과 | A |
| MD-T09 | 노트가 본문보다 먼저 도착 → `bodyPresent false` · 화면 편집 금지 · 본문 오면 열림 | A + B |
| MD-T10 | 라이브러리: '새로 만들기'에 두 항목, 'MD 가져오기' 실행 중 꺼짐, MD 카드 'MD' 표 · 미리보기, MD 메뉴에 '.md로 내보내기'만(PDF · 표지 없음) | A |
| MD-T11 | 경로: 카드 누름 → `/md/<id>`, 검색 결과 → `/md/<id>?q=…`, `/notes/<md id>` → `/md/<id>`, `/md/<노트 id>` → 'MD 문서가 아니에요' | A |
| MD-T12 | 렌더: 오너 요청 목록 전부(제목 · 강조 · 링크 · 중첩 목록 · 할 일 · 인용 · 코드 · 표 · 가로줄 · 수식 · 이미지)가 한 고정물 문서에서 보임 · 골든 6장(스타일 3 × 밝기 2) | B |
| MD-T13 | 원격 이미지 · 링크: 그리는 동안 네트워크 요청 0, 링크 누름 → 시트, 열기는 자리 있을 때만, `javascript:` 열기 없음 | B |
| MD-T14 | 할 일 토글 → 원문의 그 자리 글자만 바뀜(다른 바이트 그대로) · 저장됨 | B |
| MD-T15 | 자동 저장: 입력 후 700 ms에 한 번, 계속 입력 5 s에 한 번, 보기로 바꿈 · 뒤로 · 앱 숨김 → 바로 저장 + flush, 저장 실패 → 글 남고 띠 | B |
| MD-T16 | CRLF/BOM 문서를 편집기에서 한 글자 고침 → 저장된 글이 CRLF · BOM 그대로(그 한 글자만 다름) | B |
| MD-T17 | 검색 이동: `initialQuery`의 블록이 화면 안 · 강조 키 보임 | B |
| MD-T18 | 규칙 · 예산: `ws check --strict` 0, `flutter analyze` 0, 날 색 시험 · 아이콘 시험 통과, main.dart.js gzip 차이 ≤ +3 KB(17절) | 기반 · A |

---

## 17. 웹 예산

- 기준: `tool/web_budget.yaml` main.dart.js gzip 상한 2,000,000 B, 지금 약 2 KB 넘음(과제 설명). 파서 몫 측정 약 +59 KB gzip(2.5) — 그대로 넣으면 더 넘는다.
- 방법: 앱은 `feature_markdown/slots.dart`만 즉시 import, 화면 `feature_markdown.dart`는 `deferred as md`로만 → dart2js가 파서 · 화면을 `main.dart.js_<n>.part.js`로 뺀다. note_core의 색인 정리 · 미리보기는 파서를 쓰지 않는다(정규식 몇 개). feature_library도 파서를 import하지 않는다.
- 목표: main.dart.js gzip 차이 **≤ +3 KB**(자리 provider · 경로 · 카드 · 메뉴). 넘으면 A가 원인을 찾아 보고하고, 상한 올리기는 총괄 판단(6.15 규칙 — 올리지 않음).
- 위험: 배포가 바뀌는 사이 옛 main.dart.js가 새 part 파일을 읽는 캐시 어긋남 — Hosting 캐시 머리글이 part 파일에도 `no-cache`/해시 이름인지 A가 확인(18절 R4).
- Android(오너가 쓰는 것): deferred import는 '지연 구성 요소'를 켜지 않으면 한 덩어리로 컴파일되고 `loadLibrary()`는 곧바로 끝난다 [추측 — A-17에서 apk로 확인]. APK 크기 증가는 파서 + 화면 몫(수백 KB 미만 예상) — 보고만.

---

## 18. 위험 · 열린 질문

| # | 위험 / 질문 | 대응 |
|---|---|---|
| R1 | 할 일 훑기와 파서가 어긋남(복잡한 중첩 · 지연 이어짐 줄) | 수가 다르면 토글 끔(원문 안 바꿈). 고정물 30개로 시험 |
| R2 | 섞인 줄 끝 파일은 편집하면 한 모양으로 통일 → 바이트 그대로가 깨짐(편집한 경우만) | 문서에 적음. 편집 안 한 문서는 그대로 |
| R3 | 400 KB 문서 저장마다 색인 다시(블록 수천 개) | 같은 글이면 건너뜀(sourceRev), 지연 저장으로 횟수 줄임, CORE perf 시험(100 KB 저장 + 색인 < 50 ms VM) |
| R4 | 웹 deferred part 파일 캐시 어긋남 | 17절 — Hosting 머리글 확인, 실패하면 '새 버전' 배너 흐름(이미 있음)으로 새로 고침 |
| R5 | 충돌 사본 규칙의 `base_text_version` 갱신 누락 → 사본이 너무 많거나 빠짐 | 두 기기 시나리오 + 순서 바꾼 실행으로 시험(MD-T08) |
| R6 | IME(한국어) 조합 중 저장 · 되돌리기 동작 | 조합 중 저장 보류, 실기기 체크리스트 |
| R7 | Android 파일 고르기에서 `.md` 확장자 필터가 안 먹는 기기 | `FileType.any` 물러남 + 확장자 검사(10.1) |
| R8 | KaTeX 수식이 문단 안에서 줄 높이를 흔듦 | `WidgetSpan` 정렬 middle, 큰 수식은 블록으로 쓰라고 문서(오너 안내 없음 — 보기 문제만) |
| Q1 | 앱이 `url_launcher`를 직접 의존해도 되는가(계약 7.4.1 '새 플러그인은 서비스 패키지') | 기본값: 된다 — 이미 앱이 해석하는 플러그인이고 잠금 그대로. 안 된다면 v1은 '복사'만 |
| Q2 | 카드 미리보기를 위해 보이는 카드마다 `preview` 읽기 — 폴더에 MD 문서 수백 개 | 보이는 카드만 · autoDispose · 400자 SQL `substr` — 문제가 보이면 `notes`에 로컬 파생 열(미리보기)로 바꿈(A 판단) |
| Q3 | 충돌 사본 이름 형식 · 위치(같은 폴더) | 기본값대로. 오너가 다르게 원하면 문구만 바꿈 |
