# 07 · SYNC — 동기화 · 서버 함수 (2차 라운드 M5·M6·M7)

> 상태: **승인 · 계약 v2.3** (개발 착수 정리 2026-11-06 — 계약 7.6.2 마지막 bullet·C22-09: 5.5 '가정' 블록을 실제 타입으로, 계약 인용 표시를 v2.3으로(블록 11개 모두 v2.3 7장의 부분 문자열 [확인 — 줄 단위 대조]), C23-01·C23-02 반영, 00-review '최종 승인' SYNC-F1~F3 처리 — 13.5) · 이전: **승인** (최종 승인 2026-11-05 · 통합 계약 v2.2 — [00-review.md '최종 승인'](00-review.md#최종-승인)) · 승인한 판본: 수정 2회차 (1회차: 총괄 검토 [00-review.md](00-review.md) 3.7 SYNC-M1~M10과 공통 결정 CD2-01·05·12·19·21·22 반영. 2회차: 총괄 재검토 항목 1~4 — 13.4)

> 작성 2026-11-05 · 수정 2026-11-05(1회차·2회차) · 영역 ID **SYNC** · 소유 경로 `packages/sync_engine/`, `functions/`(새, 저장소 루트, Node — 워크스페이스 멤버 아님) · 기준: [00-overview.md 7장 '통합 계약 v2.3'](00-overview.md)(작성 때 v2.1 — v2.2·v2.3은 시그니처 변경이 SYNC에 없다) — **이 문서와 7장이 다르면 7장이 우선**한다. 7장이 덮어쓰지 않은 곳은 1차 계약 v1.5(1차 [00-overview.md](../00-overview.md) 7장 — 1차 통합 반영, 시그니처는 v1.4와 같다)가 그대로 유효하다. 이 문서의 `v1.4` 표기는 '1차 계약 그대로(v1.5에서도 같음)'라는 뜻이다.
>
> 이어받는 것: 1차 계획서 `/home/user/wt/sync/docs/plans/07-sync.md`(이하 **'1차 07-sync'**, 절 번호는 '1차 6.3.1'처럼 적는다), 진행 기록 `docs/plans/progress/sync.md`. **바탕 코드 = 1차 통합 HEAD**(`/home/user/noteapp` 브랜치 `claude/note-app-planning-bk29xb` `18c5ae5` — CD2-01). 그 HEAD의 `packages/sync_engine/`은 1차 작업 트리 `/home/user/wt/sync`(`1f4b639`)에 통합 커밋 `22abbea`(T16 실제 CORE 실행 — `test/integration/` 4파일만, `lib/` 변경 없음) 하나를 더한 것이다 [확인 — `git diff --stat 1f4b639 HEAD -- packages/sync_engine`]. 그래서 이 문서의 `lib/` 줄 인용은 통합 HEAD에서도 맞다. 통합 HEAD 기준 수치(1차 진행 기록 '통합 세션 1'): 패키지 VM 시험 777개 통과·건너뜀 4(`integration`, 약 76 s), Chrome `test/web` 26개, `--run-skipped -t integration` 42개(47.6 s — 계약 스위트 C-01~C-25 + 실제 CORE 전용 2 + 시나리오 7 + JSON 키 대조 5 + 폴더 순환 3). 조사: [01-hooks 3.4·3.11·R2](research/01-hooks.md), [03-recognition 6·7](research/03-recognition.md), [04-native 6](research/04-native.md). 판정: [judgement.md](drafts/judgement.md).
>
> 표기: [확인] = 이번에 코드·명령으로 직접 확인함, [추측] = 확인하지 못한 판단. 코드 인용의 파일·줄은 통합 HEAD 기준이다(SYNC `lib/`은 1차 작업 트리와 같음 — 다른 영역 코드의 줄은 기반 단계 시작 때 고친다).

## 목차

1. 목적과 범위
2. PLAN.md 요구사항 대응표
3. 소유 경로와 패키지 구조
4. 공개 API
5. 사용하는 다른 영역의 계약
6. 설계 상세
7. 외부 패키지
8. 작업 분해
9. 테스트 계획
10. 완료 기준
11. 리스크와 대응
12. 총괄에게 묻는 질문 · 계약 변경 제안
13. 검토 반영 내역
- 부록 A. 확장 지점 · 자리 사용표 (개요 6장 13절)
- 부록 B. 네이티브 · 권한 · 클라우드 요구표 (개요 6장 14절)

---

## 1. 목적과 범위

### 1.1 목적

2차 라운드에서 SYNC는 두 가지를 한다.

1. **실연결 전 사전 정비(P-A)** — M5·M6·M7이 만드는 새 동기화 엔티티(`pageObject`·`handwriting`)와 녹음 이름(`Recording.title`)을 1차 동기화 엔진(`sync_engine`)의 코덱·병합·게이트·영구 삭제 보호·페이지 되살림에 넣고, **모르는 종류의 기록을 청크째 버리지 않고 그 기록만 보류**하도록 바꾼다(S-13). 실연결(M4 앱 연결)은 이번에 하지 않으므로(계약 3.3) 배포된 옛 앱이 없는 지금 형식을 정해 두는 것이 가장 싸다. 완료 판정은 실제 CORE v2 두 개를 쓰는 시나리오 시험 **T16-v2**다(계약 7.7.1 3단계).
2. **서버 함수(P-B·P-C)** — 저장소 루트 `functions/`에 Firebase callable 함수 `recognizeMath`(수식 인식 중계, 외부 API 키 보호 — PLAN F-14 '외부 API 키는 앱에 넣지 않고 서버 함수를 거쳐 호출')를 만들고, 에뮬레이터 시험(V13)까지 끝낸다. 실제 엔진 호출·배포는 Firebase(Blaze)·로그인·엔진 계정 뒤다. 엔진 비교 도구 `functions/tool/math_eval.ts`(P-C)도 만든다.

그리고 실연결 미니 라운드(D16, INFRA + SYNC — 2차 통합 뒤, 사용자가 Firebase 프로젝트를 만든 다음)가 '연결만 하면 되는' 상태가 되도록 준비한다(6.10).

### 1.2 이번 범위

| 묶음 | 내용 | 등급 (계약 3.4) | 계약 절 | 작업 (8장) |
|---|---|---|---|---|
| R2-B7a 컴파일 패치 | CORE R2-B2의 `EntityKind` 값 2개(`pageObject`·`handwriting`)로 깨지는 SYNC switch를 '노트 범위 일반 기록'으로 메워 컴파일·1차 시험 전부 통과, `kPageObjectTypeKeys`, JSON 키 대조 v2 단언. 바탕 = CORE **B2-α 해시**, R2-B2·R2-B2i(INFRA)와 **한 묶음 병합**(새 종류 디코드·키 대조 시험은 B2-β JSON 골든 커밋 뒤) | P-A | 7.0.2, 7.6.2 R2-B7a | B7a |
| R2-B7b `functions/` 골격 | `package.json`(정확한 고정, 따옴표 글롭 `npm test`)·`tsconfig.json`·가짜 엔진·단위 시험·`.env.demo-noteapp`. Dart와 무관하므로 **R2-B1 바로 뒤에 따로 병합**(CD2-05) | P-B(골격은 기반 단계 몫) | 7.6.2 R2-B7b, 7.4.7 | B7b |
| 새 종류 매핑 | 키 표·병합 단위(객체 단위 LWW + 따로 `engine`, 손글씨 한 단위, 녹음 `title` 따로)·청크 범위·정렬·게이트(영구 삭제 노트의 하위 기록)·영구 삭제 보호(`PurgeGuard`)·페이지 되살림(객체는 근거, 손글씨는 근거 아님)·lib 범위 요소의 노트 찾기 | P-A | 7.2.8, X24, C2-05·C2-06·C2-13 | S2-1~S2-5 |
| 모르는 종류 보류 | 관용 디코드(`UnknownKindRecord`), 메타 KV `sync.heldRecords`(여러 키로 나눔 — 키당 < 256 KiB, 총 2 MiB), **청크 단위 전부/전무**, `needsAppUpdate` 한 번, 앱 갱신 뒤 연결할 때 다시 적용(세션 LRU 밖, K1 기록은 보관에 남김), 상한 초과·깨진 값은 되감기 표시, 압축은 그런 청크를 지우지 않음 | P-A | 7.2.8 S-13, 7.3.2 S-13 | S2-6, S2-7a, S2-7b |
| 시험용 가짜 v2 | `FakeLocalStore`(새 종류의 힌트·영구 삭제·복구 사본·`contentRevision`), `TestDevice` v2(객체·손글씨·녹음 이름 편집), `FakeSyncServer.mergedState` v2, 하네스 `knownKinds`·`restart`·`checkConverged(kinds:)`, SyncStore 계약 스위트 C-26~C-31 | P-A | 1차 07-sync 4.11·5.1.4 | S2-4a, S2-4b |
| 시나리오 시험 | 가짜 시나리오 S23~S30 + 무작위 수렴 v2(기본 실행), **T16-v2**(실제 CORE v2 두 개: 객체 동시 편집·삭제 대 수정·모르는 `type` 왕복·모르는 `kind` 보류·손글씨 결과, + 녹음 이름·JSON 키 대조 v2) | P-A | 7.7.1 3단계 | S2-8, S2-9 |
| 서버 함수 `recognizeMath` | asia-northeast3, 로그인 필수, 소유자 UID 목록, `defineSecret`, `maxInstances 2`, 입력 검사, 하루 상한(Firestore 카운터), 엔진 포트 + 가짜 엔진(출력 규칙 = 계약 7.6), 엔진 제한 시간 주입(`engineSignal`), 오류 변환, 에뮬레이터 시험 V13(SYNC 쪽 — 컨테이너 전역 잠금 + CI 반복) | P-B | 7.2.13, 7.4.6, 7.4.7, F-1, X36 | S2-10a, S2-10b, S2-11 |
| 실제 엔진 어댑터 | Mathpix(REST)·Claude(공식 SDK — CP-S5) — 코드 + 가짜 응답 시험. 실제 호출은 계정 뒤 | P-C | 7.2.13 `engine` 값 | S2-12 |
| 수식 엔진 비교 도구 | `functions/tool/math_eval.ts` — 고정 자료(획 JSON + 정답 LaTeX) → 엔진별 호출 → 점수표(조사 03 6.6) | P-C | 7.2.13 `tool` | S2-13 |
| 실연결 미니 라운드 준비 | `AuthService.idToken`(CP-S7), 패키지 README '실연결 체크리스트', 규칙 에뮬레이터 시험(1차가 '선택'으로 남긴 것) | P-C | D16, 3.3 | S2-14 |

### 1.3 이후 범위 (자리만 준비하거나 다음 라운드)

| 항목 | 이번 처리 |
|---|---|
| 동기화 실연결(앱의 `sync_engine` 의존, `SyncModule`, 로그인 화면, 배포) | 실연결 미니 라운드(D16). 이번에는 6.10의 준비만 |
| `recognizeMath` 배포·실제 엔진 호출·엔진 결정 | Firebase(Blaze)·엔진 계정 뒤(U3·U6). 코드·에뮬레이터 시험·가짜 응답 시험까지 |
| `engine: 'gemini'` | 값은 계약대로 받되 이번에는 구현하지 않는다(`unavailable`). Gemini는 Firebase AI Logic(앱 쪽, 서버 함수 불필요 — 조사 04 6.1)이 더 자연스러워 실연결 뒤 다시 판단(Q3) |
| `mathpixToken`(Mathpix 단기 토큰 발급 — 라이브 미리보기용, 조사 03 7.3) | 계약에 없다. 엔진이 Mathpix로 정해지고 라이브 미리보기가 필요하면 그때 '추가'로 제안 |
| App Check 강제 | `enforceAppCheck: false`(계약 7.2.13 — 사이드로드 APK는 Play Integrity를 통과하지 못함). 실연결 뒤 웹(reCAPTCHA)·iOS(App Attest) 사정을 보고 다시 판단 |
| 손글씨 결과의 줄 단위 병합(사용자가 확정한 줄을 다른 기기의 자동 재인식이 덮지 않게) | 이번에는 계약대로 한 단위 LWW(위험 R6, Q7) |
| 다중 탭 리더 선출, tombstone 정리, 고아 에셋 GC | 계약 3.2 '이후' 유지 |

### 1.4 제외 (다른 영역 책임)

| 항목 | 담당 |
|---|---|
| 새 엔티티의 JSON 키·outbox·`EntityChange` 힌트(`noteId`·`pageId` 항상)·원격 고아 객체 입양·영구 삭제 때 객체·손글씨 결과 지우기·`UnknownObject` 왕복(C-12)·노트 복사의 녹음·객체·손글씨 복사(R-6) | CORE (02-core 5.6·6.13·6.14) |
| 앱 쪽 수식 클라이언트 `CallableMathRecognizer`(`package:http`, callable 규약)·동의 게이트(G-3)·Dart `emulator` 시험 | LIBRARY (05-library 6.11) |
| `app/firebase.json`의 `functions`·`emulators` 항목, `.github/workflows/functions.yml`, `.gitignore`, 전역 무거운 시험 잠금 | INFRA (01-infra 6.14·6.13) — SYNC는 '변경 요청'(5.2) |
| 녹음 초안(`recording_drafts`)·검색 색인(`search_*`)의 '동기화하지 않음' 보장 | CORE(기기 로컬 테이블 — outbox·`readVersioned`에 나오지 않음). SYNC는 계약 스위트 C-30으로 확인만 |
| 이미지·오디오 에셋의 화면 쪽 내려받기 요청(`ensureLocal`) | INK(이미지 캐시)·media(재생) — 1차 `RemoteAssetFetcher` 경로 그대로 |

### 1.5 핵심 결정 요약

| # | 결정 | 근거 |
|---|---|---|
| D-S1 | `pageObject`의 병합 단위는 '객체 단위 하나'(계약 7.2.8)를 **'메타 키와 `pageId`·`deletedAt`·`engine`을 뺀 나머지 키 전부(모르는 키 포함)'**로 구현한다. 알려진 키에 대해서는 계약의 목록 `{type, frame, shape, geometry, style, text, assetId, px, latex}`과 정확히 같다. 손글씨도 같은 방식(`noteId`·`pageId`·`deletedAt` 제외 = `{engineId, sourceRev, lines}`) | 모르는 키를 따로 단위로 두면 판이 다른 앱끼리 승자가 갈려 영구 불일치가 생긴다(6.2.2 반례). (v2.1) CP-S1 승인 — 계약 7.2.8 표가 이 문장이 되었다 |
| D-S2 | 모르는 종류 기록은 **기록 바이트 그대로**(헤더 JSON + 이진 필드) 보관한다. (v2.1) 보관은 **청크 단위 전부 또는 전무**다 — 한 청크의 모르는 기록이 다 들어가지 않으면 그 청크의 기록은 하나도 저장하지 않고(이미 저장된 같은 청크 기록도 뺀다) '되감기 표시'(종류와 가장 이른 청크 시각)에만 올리고, 앱이 그 종류를 알게 되면 커서를 되돌려 통째로 다시 받는다. 보관 값은 메타 키 10개(`sync.heldRecords` 머리 + `sync.heldRecords.1`~`.9` — 키당 ≤ 224 KiB, 총 ≤ 2 MiB)로 나눈다. 깨진 값을 읽으면 '모든 종류 되감기 표시'로 바꾼다 | 계약의 `rawJson`만으로는 새 종류의 이진 필드를 잃는다. 메타 값은 256 KiB 미만 규칙(1차 계약 7.2.10)이 있다. 청크 중간에서 상한이 걸려 '저장분 + 표시분'으로 갈리면 다시 적용과 되감기 사이에 표시분이 사라질 수 있다(검토 M-1 — 6.3.2). 되감기는 1차 6.6.5(새 형식 청크)와 같은 원리(계약 7.2.8 CP-S2 ①~③) |
| D-S3 | 압축(compaction)은 모르는 종류 기록이 든 청크를 **지우지 않는다**(1차의 '해석할 수 없는 청크는 남김'과 같은 취급) | 옛 앱이 압축하면서 모르는 기록을 버리면 새 앱 기기의 데이터가 사라진다(계약 7.2.8 ④) |
| D-S4 | 다시 적용은 **로그인 상태로 연결할 때(attach), 받기 전에** 한다. (v2.1) 다시 적용 호출은 **세션 LRU에 청크 id를 넣지 않고**(`_apply(remember: false)`), 기존 `sync.held` 항목을 풀지 않는다. 다시 적용한 기록이 K1(미래 시각)에 걸리면 `sync.held`에 넣지 않고 **`sync.heldRecords`에 해제 시각(`ra`)과 함께 남겨** 그 연결의 K2 해제 단계(`releaseHeld`)에서 다시 시도한다 — 원래 청크의 존재에 기대지 않는다 | 합성 청크가 원래 청크 id를 쓰므로 LRU에 들어가면 뒤이은 받기가 원래 청크를 중복으로 건너뛴다(검토 M-1). 원래 청크가 그 사이 압축으로 지워지면 `sync.held` 경로는 기록을 잃는다(검토 S-1). 원래 청크의 다른 기록이 K1로 보류 중일 수 있다(6.3.4) — 계약 7.2.8 ⑤ |
| D-S5 | 서버 함수의 처리 순서: 로그인 → 소유자 UID → 입력 검사 → 엔진 선택 → 하루 상한 차감 → 엔진 호출(25 s, `engineSignal`) → 출력 검사 | 잘못된 입력은 상한을 쓰지 않게, 상한은 엔진 비용이 드는 호출 앞에 |
| D-S6 | 하루 상한 카운터는 Firestore 최상위 컬렉션 `fnQuota/{uid}_{yyyymmdd}`(서울 날짜)에 Admin SDK로만 쓴다 — 1차 규칙 파일은 바꾸지 않는다(클라이언트 접근은 기본 거부). 에뮬레이터 시험(`--only functions,auth`)에서는 `QUOTA_STORE=memory` | 계약 7.2.8 '규칙은 바뀌지 않는다', 계약 7.4.7의 에뮬레이터 목록. (v2.1) CP-S6 승인 — 계약 7.2.13 `rules` 주석 |
| D-S7 | 가짜 엔진 출력은 입력에서 **결정적으로** 정해진다(6.8.5) — LIBRARY의 Dart 에뮬레이터 시험이 같은 값을 단언한다. 운영에서는 `ALLOW_FAKE_ENGINE=false`라 쓸 수 없다 | V13을 두 언어가 같은 함수로 확인. (v2.1) CP-S3 ⑥ 승인 — 출력 규칙이 계약 7.6 시험 도우미 블록이 되었다 |
| D-S8 | 에뮬레이터 사용자는 Auth 에뮬레이터 관리 REST로 **uid를 지정해** 만든다(`owner-uid`·`stranger-uid`). 소유자 목록은 커밋하는 `functions/.env.demo-noteapp`(데모 프로젝트 전용 값만)에 둔다. (v2.1) 운영 `OWNER_UIDS`도 **커밋하는 `functions/.env.<projectId>`**에 둔다(uid는 비밀이 아니고, `.env.local`은 에뮬레이터만 읽는다) | [확인] 2026-11-05 에뮬레이터 실험(6.8.11). LIBRARY Q4 답. 계약 7.4.7 CP-S4·미니 라운드 순서 |
| D-S9 | Claude 어댑터는 공식 SDK `@anthropic-ai/sdk 1.1.0`(CP-S5 승인 — 계약 7.5)으로만 쓰고(직접 `fetch` 구현을 하지 않음), 모델은 매개변수 `CLAUDE_MODEL`로만 정한다 — (v2.3, C23-02) 기본값은 빈 문자열이고 비어 있으면 Claude 엔진은 `notConfigured`(P-C) | 공식 SDK의 서버 쪽 대체·구조화 출력 타입을 그대로 쓴다 |
| D-S10 | SYNC 공개 표면 변화는 '추가'만이다: `SyncEngineDebug.heldRecords`, `SyncTestHarness.device(knownKinds:)`·`restart`·(v2.1) `checkConverged(…, kinds:)`, `TestDevice` 편집 도우미, `FieldUnits.wholeUnitExcept`, (P-C) `AuthService.idToken`. 1차 공개 이름의 시그니처·의미는 바꾸지 않는다(새 인자는 모두 기본값이 있는 이름 인자) | 1차 계약 7.2.20 표면 — 다른 영역은 아직 `sync_engine`을 쓰지 않는다(앱 의존 없음 — 계약 7.1) |
| D-S11 | (v2.1) **손글씨 결과는 편집이 아니다** — `PurgeGuard`의 outbox 판정과 '최근 10분 보냄' 모두에서. 업로드 파이프라인은 `handwriting` 기록만 실린 청크의 범위를 `onScopesCommitted`에 넘기지 않는다. 1차 T11 결정 ①('노트 범위 청크면 무엇이든 최근 보냄')을 바꾼다(총괄 승인 — CD2-12) | iPad(웹, 주 기기)에서 쓴 노트를 안드로이드 색인기가 몇 분 안에 인식해 올린 뒤 사용자가 iPad에서 노트를 영구 삭제하면, 안드로이드가 '(복구됨)' 사본을 만들어 되돌려 보낸다(검토 M-3). 계약 7.2.8 `handwriting` 행 |
| D-S12 | (v2.1) 서버 함수의 시험 이음새는 **주입**이다: 엔진 제한 시간 신호 `HandlerDeps.engineSignal(ms)`(기본 `AbortSignal.timeout` — 시험은 `AbortController`), 엔진 어댑터는 생성자로 키·모델·클라이언트를 받고 `params.ts`는 등록부(`registry.ts`)만 읽는다. `engineVersion`은 **실제로 답한 엔진·모델 판**(Claude는 응답의 `model`)이고 대체 여부는 로그에만 | `AbortSignal.timeout`은 Node mock timers로 움직이지 않는다 [확인 — 검토 S-6]. 비교 도구가 같은 어댑터를 서버 밖에서 쓴다(검토 S-7). 계약 7.2.13 v2.1 `engineVersion` |

### 1.6 1차 계약(v1.4) 대비 변경 중 SYNC가 받는 것

| # (계약 7.0.1) | 변경 | SYNC에 미치는 것 | SYNC 처리 |
|---|---|---|---|
| C2-03 | `PageObject`(sealed) 하위 계층 | SYNC `fake_sync_store.dart`의 `SyncEntity` switch는 모두 `_ =>` 기본 갈래가 있다 [확인 — 6.5 표] | 기본 갈래 그대로 컴파일. 새 종류 처리는 S2-4a |
| C2-05 | `EntityKind`에 `pageObject`·`handwriting` | **깨짐**: `lib/`의 exhaustive switch 4곳(`FieldUnits.keysOf`·`groupsOf`, `SyncScopes.scopeOf`, `RecordGate._purged`) + 목록 1곳(`ChunkPacker.kindOrder` — 컴파일은 되나 `indexOf == -1`로 정렬이 틀어짐) + `test/support/entity_fixtures.dart` `fixtureJson`(exhaustive) [확인 — 6.4 표]. (v2.1, C21-04) 계약 7.0.1·7.0.2 문구가 이 목록으로 정정되었다 | R2-B7a |
| C2-06 | `Recording.title` | 병합 단위 `{title}`(녹음은 묶음이 없어 기본 규칙으로 따로 한 단위), `keysOf(recording)`에 `title` | B7a(키 표) — 녹음 엔티티 디코드는 CORE |
| C2-13 | outbox·`EntityChange` 힌트(새 두 종류 `noteId`·`pageId` 항상), 병합 단위·청크 범위·정렬·게이트 표 | 7.2.8 표 전부 | S2-1~S2-5 |
| C2-15 | `NoteStore` getter 4개 | SYNC의 `NoteStore` 구현은 `test/local/core_sync_local_store_test.dart`의 `_ScriptedChanges`(`noSuchMethod`) 하나 — 영향 없음 [확인] | 없음 |
| C2-28 | 동작 보장 S-13, F-1 | 4.1 원문 | S2-6·S2-7a·S2-7b, S2-10a·S2-10b·S2-11 |
| C2-31 | 태그 `emulator` | `sync_engine`에는 Dart `emulator` 시험이 없다(서버 함수 시험은 TypeScript, `functions/`). `dart_test.yaml`은 그대로 | 3.3 |
| C2-35 | 기반 단계 R2-B7a·R2-B7b, 통합 3단계 T16-v2, V13 | 8장 | 8장 |

(v2.1) 계약 v2.0 → v2.1 변경(7.9 C21-xx) 중 SYNC 몫:

| # | 변경 | SYNC 처리 |
|---|---|---|
| C21-01·02 | 1차 기준 v1.5, 바탕 코드 = 1차 통합 HEAD `18c5ae5` | 머리말. SYNC `lib/`은 1차 작업 트리와 같다 [확인] |
| C21-04 | C2-05 깨지는 곳 정정(switch 4 + `kindOrder` + `fixtureJson`) | 없음 — 6.4 표가 이미 그 목록 |
| C21-09 | `HandwritingRepository.update`, 신선함 = `sourceRev` + 언어 | 손글씨 한 단위 LWW를 그대로 받아들인다(R6·Q7). SYNC는 `update`를 쓰지 않는다(원격 적용은 `applyRemote`) |
| C21-11 | `math.engine` 항상(null), 키 집합 고정 | `kPageObjectTypeKeys['math']`에 `engine`이 고정으로 든다(6.2.1) |
| C21-12 | 7.2.8: 병합 단위 = 나머지 키 전부(CP-S1), 영구 삭제 문구(노트 단위), 손글씨는 편집이 아님(최근 보냄 포함), S-13 보강(청크 단위 전부/전무·메타 키 나눔·깨진 값 되감기·LRU 제외·K1 보관 유지), JSON 키 대조 v2 | 4.1 원문, 6.2.2·6.2.4·6.2.5·6.3, 6.4(B7a 키 대조) |
| C21-17 | 7.2.13: `engineVersion` = 실제 응답 판, callable 규칙(CP-S3), 하루 상한 저장(CP-S6) | 4.1 원문, 4.5, 6.8.2·6.8.4·6.8.6 |
| C21-26 | 7.4.6: `emulator`는 컨테이너(전역 잠금) + CI, 잠금 고정 경로·`NOTEAPP_HEAVY_LOCK_HELD`·`with-heavy-lock` | 5.2 RQ-5, 6.8.11 `emulator_suite.sh` |
| C21-27 | 7.4.7: `.gitignore` 보강·`.env.demo-noteapp` 커밋, 에뮬레이터 규약, `npm test` 따옴표 글롭·시험 수 > 0, `hashFiles` 가드, 미니 라운드 배포 순서 | 3.4, 5.2, 6.8.9, 6.10, 8.1 B7b |
| C21-28 | 7.5: CP-S5(`@anthropic-ai/sdk 1.1.0`) 승인, `firebase-tools` 14일 재확인(R2-B1·R2-B7b — 2026-11-11부터 통과) | 3.4, 7.2 |
| C21-29 | 7.6.2: R2-B7b 앞당김(R2-B1 바로 뒤 따로), R2-B7a 바탕 = B2-α 해시·완료 조건, 이정표 커밋 | 6.4, 8.1, 6.7.2 CORE 선행 작업 표 |
| C21-30 | 7.6 블록: 가짜 엔진 출력 규칙(CP-S3 ⑥) | 5.3 원문, 6.8.5 |
| C21-32 | 7.7.2 V13: 컨테이너 전역 잠금 + CI 반복, 두 언어가 같은 값, `owner-uid`·`stranger-uid` | 6.8.11, 8.3 I-3 |

---

## 2. PLAN.md 요구사항 대응표

| PLAN | 요구 | SYNC가 하는 것 | 작업 | 완료 조건 시험 |
|---|---|---|---|---|
| F-07, 7.4 ④ | '획·도형 등 페이지 요소: ID 기반 추가/삭제 표시 → 양쪽에서 쓴 필기 모두 보존' | 객체는 id 단위 엔티티, 삭제는 `deletedAt` 따로 단위(1차 획과 같음) — 한쪽 삭제 + 다른 쪽 수정이면 둘 다 반영 | S2-1, S2-8 | `scenarios/s24_object_delete_vs_update_test.dart`, `integration/core_objects_scenarios_test.dart` O2 |
| F-07, 7.4 ④ | '이동·색 변경 등 속성 수정: 요소별 마지막 수정 우선(HLC)' | 객체 단위 LWW(계약 D3) — 같은 객체를 동시에 고치면 나중 것이 객체째 이긴다 | S2-1 | `scenarios/s23_object_concurrent_edit_test.dart`, O1 |
| F-07 | '데이터 손실 0건'(PLAN 8장 지표) | 모르는 종류 기록 보류(S-13) — 옛 앱이 새 종류 기록이 섞인 청크를 버리지 않음. (v2.1) 보관은 청크 단위 전부/전무, 넘치거나 깨지면 되감기 표시 — 어느 경로로도 기록을 잃지 않음. 모르는 `type`은 CORE `UnknownObject`가 키 하나 빠짐없이 보존(C-12)하고 SYNC는 일반 기록으로 실어 나름 | S2-6, S2-7a, S2-7b | `scenarios/s27_unknown_kind_held_test.dart`, `scenarios/s26_unknown_type_roundtrip_test.dart`, `integration/core_unknown_kind_test.dart`, `integration/core_unknown_type_test.dart` |
| F-07 | 오프라인 편집 뒤 영구 삭제가 와도 편집을 잃지 않음(1차 S08), (v2.1) 일부러 지운 노트가 다른 기기의 손글씨 인식 업로드로 되살아나지 않음 | `PurgeGuard`가 객체 편집도 '보내지 않은 편집'으로 본다. 손글씨 결과는 파생 데이터라 outbox·'최근 10분 보냄' 어디서도 편집으로 세지 않는다(D-S11) | S2-5 | `merge/purge_guard_test.dart`, `engine/upload_pipeline_test.dart`, `scenarios/s28_handwriting_test.dart`, `scenarios/s30_purge_vs_unsent_objects_test.dart`, O5 |
| F-07 | 삭제된 페이지 vs 새 필기(1차 S06) | 페이지 되살림 근거에 새 객체를 더한다. 손글씨 결과는 근거가 아니다 | S2-5 | `merge/page_resurrection_test.dart`, `scenarios/s25_page_delete_vs_new_object_test.dart`, O3 |
| F-10, 5.2 '손글씨 검색' | 웹(iPad Safari)은 ML Kit을 못 쓰므로 네이티브가 만든 인식 결과를 동기화로 받아 검색(계약 D7) | `handwriting` 종류 매핑(노트 범위, 한 단위), 영구 삭제 노트의 결과 버림 | S2-1, S2-3 | `scenarios/s28_handwriting_test.dart`, `integration/core_handwriting_test.dart`(받은 결과가 B의 `searchPages`로 찾아짐) |
| F-11, F-14, 5.1 | 도형·텍스트 상자·이미지·수식 객체 동기화 | `pageObject` 한 종류(계약 D2) — 종류별 키는 JSON `type`이 나눔 | B7a(키 대조), S2-1~S2-4b | `integration/core_json_keys_test.dart` v2 |
| F-13 (이미지 페이지), 5.1 이미지 삽입 | 이미지 에셋 동기화 | 1차 에셋 파이프라인 그대로(내용 해시, 업로드 상한 300 MiB) — 이미지 객체의 `assetId`는 일반 키 | — | 1차 `assets/asset_sync_test.dart`(변경 없음) |
| F-16 | 녹음 '압축 후 동기화', 이름, '녹음만 따로 삭제' | `Recording.title` 따로 단위, 녹음 행·오디오 에셋은 1차 경로. 녹음 초안은 동기화하지 않음(C-30 확인) | S2-1, S2-4b | `scenarios/s29_recording_title_test.dart`, `integration/core_recording_title_test.dart`, 계약 스위트 C-30·C-31 |
| F-14 | '외부 API 키는 앱에 넣지 않고 서버 함수를 거쳐 호출' | `recognizeMath` — 키는 Secret Manager(`defineSecret`), 앱·저장소에 없음(F-1) | S2-10b, S2-11 | `functions/test/handler.test.ts`, `functions/test-emulator/recognize_math.emulator.test.ts` |
| F-14 | '엔진 후보 비교(직접 손글씨로)', '교체 가능한 구조' | 서버 쪽 엔진 포트(`MathEngine`)·등록부(매개변수를 읽는 유일한 곳), 비교 도구 `math_eval.ts`(같은 어댑터를 생성자로) | S2-10a, S2-12, S2-13 | `functions/test/registry.test.ts`, `functions/tool/test/math_eval.test.ts` |
| 6.3 비용 | '예산 알림 소액', Blaze | `maxInstances 2`, 하루 상한(`DAILY_CAP`), 가짜 엔진은 데모 프로젝트에서만, 엔진 호출 25 s 제한, 비용 추정표(6.8.12) | S2-10b, S2-11 | `functions/test/quota.test.ts` |
| 12장 위험 '동기화 버그로 데이터 손실' | 충돌 병합 자동 시험 | 시나리오 S23~S30, 무작위 수렴 v2, T16-v2 | S2-8, S2-9 | 9장 |
| 12장 위험 '수식 인식 정확도·비용' | 엔진 비교, 교체 구조 | 6.9 비교 도구, 모델을 매개변수로 | S2-13 | `math_eval.test.ts` |
| 10장 M4 | 실연결 | 이번에는 준비만(1.3, 6.10) | S2-14 | `auth/auth_service_test.dart`(idToken), `functions/test-emulator/rules.emulator.test.ts`(P-C) |

---

## 3. 소유 경로와 패키지 구조

### 3.1 `packages/sync_engine/` (1차 트리에 더하는 것만 — `[새]`·`[변경]`)

```text
packages/sync_engine/
├─ README.md                                   [변경] '2차 매핑'·'실연결 체크리스트'(6.10) 절
├─ dart_test.yaml                              (그대로 — scenario·golden·integration)
├─ pubspec.yaml                                (그대로 — 새 Dart 의존 없음)
├─ firebase/                                   (그대로 — 규칙·색인 파일은 바뀌지 않음, 계약 7.2.8)
├─ lib/
│  ├─ sync_engine.dart                         (export 목록 그대로)
│  ├─ testing.dart                             (export 목록 그대로)
│  └─ src/
│     ├─ model/
│     │  ├─ field_units.dart                   [변경] keysOf 새 두 종류·recording.title, wholeUnitExcept, unitsFor (6.2.2)
│     │  └─ scopes.dart                        [변경] pageObject → 힌트, handwriting → json noteId (6.2.3)
│     ├─ codec/
│     │  ├─ chunk_codec.dart                   [변경] decodeTolerant, UnknownKindRecord, DecodedPayload (6.3.1)
│     │  └─ chunk_packer.dart                  [변경] kindOrder + pageObject, handwriting (6.2.3)
│     ├─ merge/
│     │  ├─ record_gate.dart                   [변경] _purged 새 두 종류, strokeNoteId → elementNoteId (6.2.4)
│     │  ├─ page_resurrection.dart             [변경] 새 객체도 근거 (6.2.6)
│     │  └─ purge_guard.dart                   [변경] 보내지 않은 객체 편집도 편집 (6.2.5)
│     ├─ engine/
│     │  ├─ held_records.dart                  [새] sync.heldRecords 값 — 청크 단위 전부/전무·키 나눔·되감기 표시·ra (6.3.2)
│     │  ├─ meta_keys.dart                     [변경] + heldRecords(머리) · heldRecordParts(.1~.9)
│     │  ├─ download_pipeline.dart             [변경] 관용 디코드·보관·다시 적용(remember: false)·K1 기록 ra·되감기·lib 범위 요소 (6.3.3~6.3.5, 6.2.7)
│     │  ├─ upload_pipeline.dart               [변경] 손글씨만 실린 청크의 범위는 onScopesCommitted에 넘기지 않음 (6.2.5)
│     │  ├─ engine_controller.dart             [변경] attach 때 reapplyHeldRecords(세션 플래그), 다시 적용 지표, debugKnownKinds (6.3.4, 6.3.8)
│     │  └─ sync_engine.dart                   [변경] SyncEngineDebug.heldRecords (4.2)
│     ├─ compaction/compactor.dart             [변경] 모르는 종류 청크 남김 (6.3.6)
│     ├─ auth/
│     │  ├─ auth_backend.dart                  [변경, P-C] idToken (CP-S7, 6.10)
│     │  └─ auth_service.dart                  [변경, P-C] idToken
│     ├─ firebase/firebase_auth_backend.dart   [변경, P-C] idToken = getIdToken
│     └─ testing/
│        ├─ fake_sync_store.dart               [변경] 객체·손글씨 색인·힌트·영구 삭제·복구 사본·contentRevision (6.5)
│        ├─ fake_local_store.dart              [변경] objectsOf·handwritingOf (@internal)
│        ├─ fake_sync_server.dart              [변경] mergedState v2 (관용 디코드, 새 종류 하위 기록)
│        ├─ fake_auth_backend.dart             [변경, P-C] idToken
│        ├─ sync_test_harness.dart             [변경] device(knownKinds:), restart, checkConverged(kinds:) (4.3)
│        └─ test_device.dart                   [변경] 객체·손글씨·녹음 도우미 (4.3)
└─ test/
   ├─ support/
   │  ├─ entity_fixtures.dart                  [변경, B7a] 새 두 종류 fixtureJson, objectFixture(type), kCoreJsonKeys, kPageObjectTypeKeys (계약 생성자 + T20a toJson — PageObjectFixtures 안 씀, 5.1.5)
   │  ├─ raw_records.dart                      [새] 모르는 kind·모르는 type 기록 바이트 만들기 (S-13 시험)
   │  └─ local_writes.dart                     [변경] objectWrite·handwritingWrite
   ├─ model/field_units_test.dart              [변경] (B7a) 종류별 키 비교 · (S2-1) 새 종류·wholeUnitExcept·판 섞임 수렴
   ├─ model/scopes_test.dart                   [변경]
   ├─ codec/chunk_codec_test.dart              [변경] 관용 디코드 경우 표
   ├─ codec/chunk_packer_test.dart             [변경] 새 종류 정렬
   ├─ goldens/chunk_v1_kinds_golden.bin        [새] fmt 1 + 새 종류 + 모르는 kind 기록 (6.3.1)
   ├─ goldens/chunk_v1_kinds_golden_test.dart  [새]
   ├─ goldens/make_chunk_kinds_golden.py       [새] 골든을 Dart와 따로 만드는 스크립트(시험 실행에는 쓰지 않음)
   ├─ shared/chunk_kinds_cases.dart            [새] 관용 디코드·새 종류 골든 본문(VM·Chrome 공용)
   ├─ shared/held_records_cases.dart           [새] HeldRecords 왕복·상한 본문(VM·Chrome 공용)
   ├─ merge/field_merge_test.dart              [변경] 새 종류 행
   ├─ merge/field_merge_properties_test.dart   [변경] 생성기에 새 종류
   ├─ merge/record_gate_test.dart              [변경]
   ├─ merge/page_resurrection_test.dart        [변경]
   ├─ merge/purge_guard_test.dart              [변경] 객체 편집 → 사본, 손글씨만(outbox·최근 보냄) → 사본 없음
   ├─ engine/held_records_test.dart            [새] 청크 단위 전부/전무·키 나눔·깨진 값·ra
   ├─ engine/download_pipeline_test.dart       [변경] S-13 묶음(LRU 밖·표시분·겹침 재수신·K1 ra), lib 범위 객체
   ├─ engine/upload_pipeline_test.dart         [변경] 손글씨만 든 커밋 → onScopesCommitted 범위 없음
   ├─ engine/engine_state_test.dart            [변경] needsAppUpdate(모르는 종류), 다시 적용 순서·재연결 재시도·지표
   ├─ compaction/compactor_test.dart           [변경] 모르는 종류 청크
   ├─ contract/sync_store_contract.dart        [변경] C-26~C-31, 드라이버 멤버 추가
   ├─ testing/*_test.dart                      [변경] 가짜 v2, sync_test_harness_test(knownKinds·restart·checkConverged(kinds:))
   ├─ scenarios/s23_object_concurrent_edit_test.dart        [새]
   ├─ scenarios/s24_object_delete_vs_update_test.dart       [새]
   ├─ scenarios/s25_page_delete_vs_new_object_test.dart     [새]
   ├─ scenarios/s26_unknown_type_roundtrip_test.dart        [새]
   ├─ scenarios/s27_unknown_kind_held_test.dart             [새]
   ├─ scenarios/s28_handwriting_test.dart                   [새]
   ├─ scenarios/s29_recording_title_test.dart               [새]
   ├─ scenarios/s30_purge_vs_unsent_objects_test.dart       [새]
   ├─ scenarios/fuzz_convergence_test.dart     [변경] 연산에 객체·손글씨·녹음 이름
   ├─ integration/core_json_keys_test.dart     [변경, B7a] v2 단언(합집합·kPageObjectTypeKeys·unknown 제외)
   ├─ integration/core_sync_store_contract_test.dart [변경] C-26~C-31 실제 CORE 드라이버
   ├─ integration/core_objects_scenarios_test.dart   [새] T16-v2 O1~O5
   ├─ integration/core_unknown_type_test.dart        [새] T16-v2
   ├─ integration/core_unknown_kind_test.dart        [새] T16-v2
   ├─ integration/core_handwriting_test.dart         [새] T16-v2
   ├─ integration/core_recording_title_test.dart     [새] T16-v2
   ├─ integration/support/core_store_driver.dart     [변경] addObject·putHandwriting·renameRecording
   ├─ web/pure_logic_browser_test.dart         [변경] 관용 디코드·보관 값·새 종류 병합 성질(Chrome)
   └─ api_surface_test.dart                    [변경] 4.2·4.3 추가 멤버(checkConverged kinds: 포함)
```

### 3.2 `functions/` (새 — 저장소 루트, Node 22 + TypeScript, Dart 워크스페이스 멤버 아님)

```text
functions/
├─ package.json            # 3.4 — 정확한 고정, scripts build·test·test:emulator·eval:math
├─ package-lock.json       # 커밋, npm ci
├─ tsconfig.json           # rootDir ".", include src·test·test-emulator·tool, outDir lib
├─ .env.demo-noteapp       # 커밋 — 데모 프로젝트(에뮬레이터) 전용 값만 (6.8.9)
├─ (.env.<projectId>)      # 미니 라운드에 만들어 커밋 — 운영 OWNER_UIDS·MATH_ENGINE·DAILY_CAP (6.8.9, 6.10 L5)
├─ README.md               # 실행법, 매개변수·비밀값 표, 배포 체크리스트(미니 라운드)
├─ src/
│  ├─ index.ts             # export { recognizeMath } — 배포 표면은 이것 하나
│  ├─ recognize_math.ts    # onCall 연결 + createRecognizeMathHandler(deps — engineSignal 주입) (6.8.2)
│  ├─ protocol.ts          # 요청·응답 타입(계약 7.2.13), parseRequest, LIMITS (6.8.3)
│  ├─ params.ts            # defineSecret·defineString·defineInt·defineBoolean (6.8.9) — 읽는 곳은 registry.ts·onCall 연결뿐
│  ├─ access.ts            # 소유자 UID 판정
│  ├─ quota.ts             # QuotaStore, FirestoreQuotaStore, MemoryQuotaStore, seoulDayKey (6.8.7)
│  ├─ errors.ts            # EngineError → HttpsError (6.8.8)
│  ├─ log.ts               # 구조화 로그(내용 없이 크기·엔진·시간만 — 6.8.10)
│  └─ engines/
│     ├─ engine.ts         # MathEngine 포트, EngineInput·EngineOutput, EngineError (6.8.4)
│     ├─ registry.ts       # 'auto'·이름 → 엔진, 설정 확인. params 값을 읽어 어댑터 생성자에 넘김 (6.8.4)
│     ├─ fake.ts           # 결정적 가짜 (6.8.5)
│     ├─ mathpix.ts        # P-C (6.8.6) — 생성자 {appId, apiKey, fetch?}
│     ├─ claude.ts         # P-C, CP-S5 (6.8.6) — 생성자 {apiKey, model, client?}
│     └─ latex.ts          # 출력 정리·정규화(비교 도구와 공용)
├─ test/                   # node:test 단위 시험 (npm test)
│  ├─ protocol.test.ts · access.test.ts · quota.test.ts · handler.test.ts
│  ├─ registry.test.ts · fake_engine.test.ts · latex.test.ts
│  ├─ secrets_hygiene.test.ts                        # 커밋 대상 파일에 키 꼴 문자열 없음 (6.8.9)
│  └─ mathpix.test.ts · claude.test.ts               # P-C (가짜 fetch / 가짜 SDK 클라이언트)
├─ test-emulator/          # emulators:exec 안에서만 (npm run test:emulator)
│  ├─ support/auth_emulator.ts                       # 사용자 만들기·ID 토큰 (6.8.11)
│  ├─ recognize_math.emulator.test.ts                # V13 (SYNC 쪽)
│  ├─ rules.emulator.test.ts                         # P-C, 실연결 준비 (6.10)
│  └─ firebase.rules-test.json                       # P-C — 규칙 시험 전용 에뮬레이터 설정(SYNC 소유)
├─ scripts/
│  └─ emulator_suite.sh    # test:emulator 본문 — ws with-heavy-lock으로 다시 실행(CI 제외) + emulators:exec (6.8.11)
└─ tool/
   ├─ math_eval.ts         # P-C 비교 도구 (6.9)
   ├─ eval_score.ts        # 채점·표 만들기(순수 함수 — 시험 대상)
   ├─ fixtures/math/README.md                        # 고정 자료 형식·동의 규칙(U18)
   ├─ fixtures/math/synthetic/*.json                 # 합성 5개(도구 자체 시험용)
   └─ test/math_eval.test.ts
```

- `functions/`는 `app/` 밖, 저장소 루트다(계약 2.2). `ws check`·루트 `flutter analyze` 대상이 아니다(INFRA가 `analysis_options.yaml` `exclude`에 `functions/**`를 둔다 — 01-infra W2-9).
- 산출물 `lib/`, `node_modules/`, `eval-out/`, 비밀값 `.secret.local`, 개인 값 `.env.local`, `firebase-debug*.log`는 커밋하지 않는다(INFRA `.gitignore` — 5.2 RQ-2, 01-infra 3.1에 반영됨). **`.env.demo-noteapp`은 커밋한다**(데모 프로젝트에서만 읽히고 비밀값이 없다 — 6.8.9). (v2.1) 미니 라운드에 만드는 **`.env.<projectId>`도 커밋한다**(운영 `OWNER_UIDS` — uid는 비밀이 아니다. `.env.local`은 에뮬레이터만 읽어 배포에 쓰이지 않는다 — 계약 7.4.7).

### 3.3 `dart_test.yaml` · pubspec

- `sync_engine`의 `dart_test.yaml`·`pubspec.yaml`은 바뀌지 않는다. 새 Dart 의존이 없고(관용 디코드·보관은 1차 의존 `collection`·`meta`·`crypto` 안에서), 새 태그도 없다. 새 시나리오는 1차처럼 `scenario` 태그(기본 실행), T16-v2 파일은 `integration` 태그(기본 skip).
- 계약 C2-31의 `emulator` 태그는 Dart 쪽 서버 함수 클라이언트 시험(LIBRARY `ink_recognition`)이 쓴다. SYNC의 서버 함수 시험은 TypeScript `node:test`라 태그 체계 밖이다(실행 방법은 3.4 스크립트와 6.8.11).

### 3.4 `functions/package.json`

```json
{
  "name": "noteapp-functions",
  "private": true,
  "main": "lib/src/index.js",
  "type": "commonjs",
  "engines": { "node": "22" },
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "test": "npm run build && node --test 'lib/test/**/*.test.js' 'lib/tool/test/**/*.test.js'",
    "test:emulator": "npm run build && bash scripts/emulator_suite.sh",
    "eval:math": "npm run build && node lib/tool/math_eval.js"
  },
  "dependencies": {
    "firebase-admin": "14.5.0",
    "firebase-functions": "7.4.0"
  },
  "devDependencies": {
    "@types/node": "22.20.5",
    "firebase-tools": "15.34.1",
    "typescript": "6.0.3"
  }
}
```

- (v2.1, SYNC-M2) **`test` 스크립트는 따옴표 친 글롭을 Node에 넘긴다.** 디렉터리 인자(`node --test lib/test/ lib/tool/test/`)는 Node 22에서 디렉터리를 모듈로 불러 `Cannot find module '…/lib/test'`로 실패하고, 인자 없이 기본 패턴에 맡기면 `lib/test-emulator/*.emulator.test.js`까지 잡혀 에뮬레이터 없이 실패한다(검토 M-2). [확인 — 2026-11-05 Node 22.23.4, `/tmp/claude-0/plan57-scratch/sync57r`] 따옴표 글롭 두 개 → `# tests 2`·`# pass 2`, 단위 글롭은 `*.emulator.test.js`를 잡지 않음, 에뮬레이터 글롭 `'lib/test-emulator/**/*.emulator.test.js'`는 그 파일만 잡음. **맞는 파일이 없는 글롭도 `# tests 0`·종료 코드 0으로 끝난다** — 그래서 완료 조건(8.1 B7b·S2-10a·S2-10b)과 CI(INFRA `functions.yml` — 01-infra 6.14)는 출력의 `# tests N`이 N > 0인지 따로 본다. 출력을 파이프로 받으면(TTY 아님) Node 22 기본 보고 형식이 TAP이라 `# tests N` 줄이 나온다 [확인 — 같은 실험]. 완료 조건 명령(이하 **'`npm test`(시험 수 > 0)'**): `set -o pipefail; npm test 2>&1 | tee "${TMPDIR:-/tmp}/sync-npm-test.log" && grep -Eq '^# tests [1-9][0-9]*$' "${TMPDIR:-/tmp}/sync-npm-test.log"`.
- 버전은 계약 7.5 표 그대로이고, (v2.3, C23-01) `firebase-tools 15.34.1`(2026-10-21 게시 — 14일 규칙을 지난 판 중 최신. 15.34.2로 올리는 것은 실연결 미니 라운드 때 다시 판단)은 INFRA 요청 R-6(01-infra 5.9 — CI가 lock된 같은 판을 `npx`/npm 스크립트로 부름)을 받아들인 것이다(계약 7.4.7 CP11). 1차 고정값이지만 게시일이 2026-10-28이라 작성일(11-05)에는 14일이 안 된다 [확인 — `npm view firebase-tools time`]. (v2.1, C21-28) R2-B1·**R2-B7b 커밋 때 14일이 지났는지 다시 확인**한다(2026-11-11부터 통과 — 그 전이면 B7b를 미룬다).
- (P-C, CP-S5 승인 — 계약 7.5) `dependencies`에 `"@anthropic-ai/sdk": "1.1.0"`(게시 2026-10-21, 의존 `standardwebhooks`·`json-schema-to-ts`·`@opentelemetry/api`, `zod`는 선택 peer [확인 — `npm view`]). S2-12(Claude 어댑터)에서 더하고 간접 의존 판은 lock을 만들 때 7.2 방식으로 확인한다.
- `tsconfig.json`: 조사 04 6.4 골격(`module`·`moduleResolution` `NodeNext`, `strict`, `noImplicitReturns`, `noUnusedLocals`, `target es2022`, `skipLibCheck`, `types ["node"]`)에서 `rootDir: "."`, `include: ["src", "test", "test-emulator", "tool"]`로 바꾼다(배포 진입점은 `lib/src/index.js`). 린터(eslint)는 두지 않는다 — 의존을 늘리지 않고 `tsc --strict`를 검사로 삼는다.
- 시험 실행기는 Node 내장 `node:test`·`node:assert/strict`, HTTP는 Node 22 내장 `fetch`다(추가 의존 없음 — 조사 04 6.4 골격과 같음).

---
## 4. 공개 API

### 4.0 이 절의 구성

- 4.1은 SYNC가 소유하는 **계약 v2.1 원문**(7.2.8 동기화 문서 매핑, 7.2.13 서버 함수 형식, 7.6 블록의 가짜 엔진 규칙, 7.3의 SYNC 행, 7.4.7)을 글자 그대로 옮긴다. v2.0 초안의 제안 CP-S1~CP-S9는 v2.1에서 모두 받아들여졌고(12.1), 원문이 비워 둔 세부를 어떻게 채우는지는 4.1 끝의 표에 적는다.
- 4.2는 `package:sync_engine/sync_engine.dart`의 2차 변화(추가만), 4.3은 `package:sync_engine/testing.dart`의 추가, 4.4는 내부(export하지 않는) 타입 — 다른 영역은 쓰지 않지만 시험·검토를 위해 적는다. 4.5는 `functions/`의 TypeScript 표면이다.
- 1차 공개 이름(1차 07-sync 4.0 표 — `api_surface_test`의 `kSyncEngineSurface`·`kTestingSurface`·`kFirebaseSurface`·`kPlatformSurface`)은 **하나도 지우거나 시그니처를 바꾸지 않는다**. 새 최상위 이름도 없다(새 것은 모두 기존 클래스의 멤버거나 내부 파일).

### 4.1 계약 원문 (SYNC 소유)

`// 계약 v2.3 7.2.8 원문`

#### 7.2.8 동기화 문서 매핑 (1차 7.2.10 — sync_engine)

원격 구조(Firestore `users/{uid}/changes/{chunkId}` + 코덱 v1 이진 페이로드)는 바뀌지 않는다. 문서 필드에 엔티티 종류가 없으므로 Firestore·Storage 규칙도 바뀌지 않는다(조사 01 3.11). 코덱 형식 `fmt`는 **1 그대로** 둔다 — 배포된 옛 앱이 없고, 이번에 '모르는 종류 보류'가 들어가므로 이후 종류 추가에도 `fmt`를 올릴 필요가 없다.

| `EntityKind` | 청크 범위 | outbox 힌트 (CORE, 1차 7.2.10 규칙 확장) | 병합 단위(필드 묶음) | 하위 기록·게이트 |
|---|---|---|---|---|
| `stroke` | 노트 | v1.4 | v1.4 (`{recordingId, recordingOffsetMs}`) | v1.4 |
| `pageObject` | 노트 | `noteId` 항상, `pageId` 항상 | **객체 단위 하나**: (v2.1, CP-S1) 메타 키와 `pageId`·`deletedAt`·`engine`을 뺀 **나머지 키 전부**(모르는 키 포함 — 알려진 키로는 `{type, frame, shape, geometry, style, text, assetId, px, latex}`) + 따로 `{engine}`. 같은 객체를 두 기기가 동시에 고치면 나중 것이 이긴다(삭제 규칙은 v1.4 그대로) | (v2.1 정정) 노트 영구 삭제 때 함께(`purge_guard`·`record_gate`에 추가 — 페이지는 소프트 삭제만 있다). 삭제된 페이지에 상대가 모르는 객체가 있으면 페이지를 되살림(`page_resurrection` — 획과 같은 근거) |
| `handwriting` | 노트 | `noteId` 항상, `pageId` 항상 | 하나: (v2.1, CP-S1) 메타 키와 `noteId`·`pageId`·`deletedAt`을 뺀 나머지 전부(알려진 키로는 `{engineId, sourceRev, lines}`) | (v2.1 정정) 노트 영구 삭제 때 함께. 되살림 근거가 **아니다**(파생 데이터). (v2.1) 편집으로 세지 않는다 — outbox 판정과 영구 삭제 보호의 '최근 보냄'(10분) 모두에서 손글씨만 실린 청크의 범위를 뺀다(SYNC 검토 M-3: 안드로이드 색인기의 업로드가 사용자가 지운 노트를 되살리지 않게) |
| `recording` | 노트 | v1.4 | v1.4 + `{title}` 따로 | v1.4 |
| (모르는 종류) | — | — | — | **보류**(아래) |

- 정렬(`chunk_packer.kindOrder`): `folder, note, page, penPreset, setting, asset, recording, stroke, pageObject, handwriting`.
- 이진 필드(`blobKeys`): 새 종류에는 없다(객체 JSON에 점 배열을 넣지 않는다).
- **모르는 종류 보류(S-13)**: `ChunkCodec`은 모르는 `kind` 기록을 실패시키지 않고 `UnknownKindRecord(kind, rawJson)`로 디코드한다. 다운로드 파이프라인은 같은 청크의 나머지 기록을 적용하고, 모르는 기록만 메타 KV(`sync.heldRecords`)에 보관한 뒤 `SyncIssueCode.needsAppUpdate`를 한 번 낸다. 앱이 갱신되어 그 종류를 알게 되면 보관분을 순서대로 다시 적용한다. 커서는 정상 진행한다(청크를 버리지 않는다). (v2.1, CP-S2 보강) ① 보관 단위는 기록 바이트(헤더 JSON + 이진 필드). ② 한 청크의 모르는 기록은 **전부 보관하거나 전부 표시**한다 — 상한에 걸리면 그 청크는 기록 없이 '되감기 표시'(종류·가장 이른 청크 시각)에만 올리고, 앱 갱신 뒤 커서를 되돌려 통째로 다시 받는다. ③ 보관은 메타 키 여러 개로 나눈다(키당 < 256 KiB, 총 상한 2 MiB). 깨진 값을 읽으면 '모든 종류 되감기 표시'로 바꾼다(비싸지만 잃지 않음). ④ 압축은 모르는 종류 기록이 든 청크를 지우지 않는다. ⑤ 다시 적용은 '로그인 상태로 연결할 때, 받기 전에' 하고, 세션 중복 제거 목록(LRU)에 넣지 않으며, 기존 `sync.held`를 풀지 않는다. 다시 적용 중 미래 시각(K1)에 걸린 기록은 보관에 남겨 다음 연결에서 다시 시도한다(원래 청크의 존재에 기대지 않음).
- 모르는 `type`의 `pageObject`는 CORE가 `UnknownObject`로 받아 저장·동기화하므로 SYNC 입장에서는 일반 기록이다(C-12).
- 에셋: 이미지·오디오는 1차 에셋 파이프라인 그대로(업로드 상한 300 MiB — 64 kbps 3시간 녹음 86 MB에 여유). `recording_drafts`·`search_units`·`search_fts`는 기기 로컬이라 동기화 대상이 아니다.
- SYNC T16 'JSON 키 대조'(1차)를 새 두 종류에도 돌린다. (v2.1, CP-S1) `handwriting`: CORE `toJson` 키 집합 = `FieldUnits.keysOf(kind)`. `pageObject`: 알려진 4종 골든 키의 합집합 = `keysOf(pageObject)`, 각 골든 키 = `kPageObjectTypeKeys[type]`, `unknown`은 키 대조에서 빼고 `SyncDoc` 왕복만 본다(R2-B7a에서). 이후 라운드에 두 종류에 키를 더해도 따로 병합 단위를 만들지 않는다('나머지 전부' 단위에 들어간다 — 판이 다른 앱끼리 승자가 갈리지 않게).

`// 계약 v2.3 7.2.13 원문 (functions/ 부분)`

```text
functions/ (SYNC) — Node 22, TypeScript, firebase-functions 7.4.0, firebase-admin 14.5.0
callable recognizeMath  (region asia-northeast3, maxInstances 2, timeout 30 s, memory 256 MiB)
  auth   : request.auth required; uid ∈ OWNER_UIDS (defineString) else permission-denied
  secrets: MATH_API_KEY (+ engine-specific) via defineSecret — never in the app or the repo
  in     : { v: 1, engine?: 'auto' | 'mathpix' | 'claude' | 'gemini' | 'fake',
             strokes?: { x: number[][], y: number[][], t?: number[][] },   // page pt, ≤ 512 KB
             //   (v2.1, CP-L8) x, y: page pt with 1 decimal; t: integer ms from the first
             //   sample of the first stroke
             pngBase64?: string (≤ 2 MB), locale?: 'ko' | 'en' }
  out    : { latex: string, confidence?: number, alternatives?: string[],
             engine: string, engineVersion: string, ms: number }
           (v2.1) engineVersion = the engine / model that actually answered (a server-side
           fallback may switch models — taken from the engine response, fallback logged)
  errors : unauthenticated | permission-denied | invalid-argument | resource-exhausted
           (daily cap per uid, Firestore counter) | unavailable | internal
  rules  : (v2.1, CP-S3) engine omitted = 'auto' = server MATH_ENGINE; 'fake' only where
           ALLOW_FAKE_ENGINE (demo project); v ≠ 1 → invalid-argument; unknown input keys ignored;
           input the engine cannot take (strokes only, image engine) → invalid-argument;
           unavailable = engine not configured / temporarily down (engine 429 included — not
           resource-exhausted); internal = unreadable or refused engine response.
           (CP-S6) daily counter in top-level Firestore `fnQuota` (TTL expireAt, clients denied by
           default — no rules file change); the default emulator run uses QUOTA_STORE=memory.
  App Check: enforceAppCheck false this round (sideloaded APK cannot pass Play Integrity).
tool   : functions/tool/math_eval.ts — reads fixtures (stroke JSON + expected LaTeX), calls each
         engine with keys from developer env vars, writes the 03-recognition 6.6 score table.
```

앱 쪽 `CallableMathRecognizer`(ink_recognition)는 `package:http`로 callable 규약(`{"data": …}` + `Authorization: Bearer`)을 직접 구현한다 — `cloud_functions`(Firebase 네이티브 SDK)를 이번에 넣지 않아 iOS 혼합 모드 위험을 피한다(3.3). 실연결 미니 라운드에서 `cloud_functions 7.0.1`로 바꿀지 다시 정한다.

`// 계약 v2.1 7.6 기반 단계 시험 도우미 블록 원문 (functions/ 가짜 엔진 — SYNC 소유)`

```text
// functions/ fake engine — (v2.1, CP-S3 ⑥) deterministic; SYNC's emulator test and LIBRARY's Dart
// emulator test (CallableMathRecognizer) assert the same values. engine 'fake', engineVersion '1'
// → app engineId 'fake/1'. Demo config only (ALLOW_FAKE_ENGINE).
//   strokes (S strokes, P points in total) → latex "\frac{S}{P}", confidence 1, alternatives ["S/P"]
//   pngBase64 only (B decoded bytes)       → latex "\sqrt{B}", confidence 1, alternatives []
//   first point of the first stroke (-1,-1) → unavailable; (-2,-2) → internal; (-3,-3) → unavailable
```

`// 계약 v2.1 7.3.1·7.3.2의 SYNC 행 원문`

| # | 제공 | 소비 | 인터페이스 | 핵심 규칙 |
|---|---|---|---|---|
| X24 | CORE | SYNC | `EntityKind.pageObject`·`handwriting`, JSON(7.2.7), outbox 힌트, `UnknownObject` | 7.2.8 매핑, S-13 |
| X36 | functions/ (SYNC) | recog | `recognizeMath` callable 형식(7.2.13) | 형식 바꿀 때 1차 7.4.12 절차 |

| # | 주체 | 보장 |
|---|---|---|
| S-13 | SYNC | 모르는 `kind` 기록은 그 기록만 보류하고 같은 청크의 나머지는 적용한다. 보류분은 앱 갱신 뒤 다시 적용된다. (v2.1) 보류는 청크 단위 전부/전무이고 넘치면 되감기 표시다 — 어느 경로로도 기록을 잃지 않는다(7.2.8) |
| F-1 | SYNC(functions) | 외부 API 키는 Secret Manager(에뮬레이터는 `.secret.local`)에만 있고 앱·저장소에 없다. 로그인 + 소유자 UID 목록 밖 호출은 거절한다 |

`// 계약 v2.3 7.4.7 원문`

- 저장소 루트 `functions/`(SYNC). npm 의존은 **정확한 버전** + `package-lock.json` 커밋 + `npm ci`. `.env.local`·`.secret.local`·`node_modules/`·`lib/`·(v2.1) `eval-out/`·`firebase-debug*.log`는 `.gitignore`(INFRA가 기반 단계에서 넣음).
- (v2.1, CP-S4) **`functions/.env.demo-noteapp`은 커밋한다**(데모 값만: `OWNER_UIDS=owner-uid`, `MATH_ENGINE=fake`, `ALLOW_FAKE_ENGINE=true`, `QUOTA_STORE=memory`, `DAILY_CAP=1000`) — 어떤 무시 규칙에도 걸리지 않음을 INFRA 시험이 확인한다. 시험 비밀값은 없다(`MATH_API_KEY` 없음 → 빈 값 + 경고, 가짜 엔진은 키를 쓰지 않음 [확인 — 07-sync 6.8.11]). 에뮬레이터 사용자는 `owner-uid`·`stranger-uid`(Auth 에뮬레이터 관리 REST — `Authorization: Bearer owner` + `localId`, 이미 있으면 로그인)로 SYNC·LIBRARY 시험이 같이 쓴다.
- `app/firebase.json`에 `"functions": [{"source": "../functions"}]`(INFRA, 에뮬레이터에서 동작 확인됨 — 조사 04 6.4).
- CI `functions` 잡(INFRA 소유 워크플로, SYNC 스크립트 호출): `ubuntu-latest`, Node 22, `npm ci && npm test && npm run test:emulator`(`firebase emulators:exec --only functions,auth --project demo-noteapp`, firebase-tools 15.34.2). 경로 필터 `functions/**`. (v2.1, CP11) `firebase-tools`는 `functions/package.json` devDependency(정확한 판)로 잠그고, 스크립트 이름은 `build`·`test`·`test:emulator`, 에뮬레이터 설정은 `--config ../app/firebase.json`이다. `npm test`는 따옴표 친 글롭(`node --test 'lib/test/**/*.test.js' 'lib/tool/test/**/*.test.js'` — 디렉터리 인자는 Node 22에서 실패한다 [확인 — SYNC 검토 M-2])이고 완료 조건에서 돌린 시험 수 > 0을 본다. `functions/`가 아직 없는 커밋에서는 잡을 건너뛴다(`hashFiles('functions/package.json')` 가드).
- 배포(`firebase deploy --only functions`)는 Firebase 프로젝트 + Blaze 뒤(3.3, U3·U6). (v2.1) 미니 라운드의 순서: 비밀값(Secret Manager — 엔진이 정해지기 전에도 자리 값이 있어야 함 [추측 — 배포 때 확인]) → 커밋하는 `functions/.env.<projectId>`(운영 `OWNER_UIDS` — uid는 비밀이 아니고, `.env.local`은 에뮬레이터만 읽는다) → 배포 → `MATH_ENGINE=none`에서 소유자 호출 = `unavailable`·남 계정 = `permission-denied` 확인 → 엔진 설정 뒤 실제 호출 1회. 운영에서는 가짜 엔진을 쓸 수 없다(`ALLOW_FAKE_ENGINE=false`).

- (v2.3, C23-01) 위 인용의 CI 줄 'firebase-tools 15.34.2'는 계약 7.4.7 본문 그대로다. 고정 판은 7.5 표와 C23-01대로 **15.34.1**이고 `functions/package.json`도 15.34.1이다(7.4.7 본문 문구는 총괄에게 알림 — 진행 기록 '변경 요청').

계약 원문과 이 계획서 구현의 관계(v2.0 초안의 CP-S1~CP-S9는 v2.1에서 모두 받아들여졌다 — CP-S2는 보강해서, 00-review 2.2. 아래는 원문이 비워 둔 세부를 이 계획서가 어떻게 채우는지다. 원문을 바꾸지 않는다):

| 원문 | 이 계획서의 구현 | 절 |
|---|---|---|
| `pageObject` '나머지 키 전부(모르는 키 포함) + 따로 `{engine}`', `handwriting` '나머지 전부' | `FieldUnits.wholeUnitExcept(kind)`가 따로 단위 키(`pageId`·`deletedAt`·`engine` / `noteId`·`pageId`·`deletedAt`)를 돌려주고, `unitsFor`가 '두 스냅숏에 있는 키 − 메타 키 − 그 집합'을 한 단위로 만든다 | 4.2, 6.2.2 |
| 'JSON 키 대조 v2 … (R2-B7a에서)' | B7a가 `kPageObjectTypeKeys`와 `core_json_keys_test` v2 단언을 함께 만들고, `field_units_test`의 'CORE 키 표 = 엔티티 직렬화'도 종류별 비교로 바꾼다. 실행은 CORE B2-β JSON 골든(T20a) 커밋 위에서 | 6.4, 8.1 |
| `handwriting` '편집으로 세지 않는다 — outbox 판정과 최근 보냄 모두' | outbox: `_editedInOutbox`가 `handwriting` 항목을 보지 않는다(1차 기본 갈래 그대로). 최근 보냄: `UploadPipeline`이 **`handwriting` 기록만 실린 청크**의 범위를 `onScopesCommitted`에 넘기지 않는다(같은 청크에 획이 함께 있으면 센다) | 6.2.5 |
| ① `UnknownKindRecord(kind, rawJson)` + '기록 바이트' | 헤더 JSON(= rawJson)과 **기록의 원래 바이트**(op·헤더·이진 필드)를 함께 들고, 보관은 바이트(base64)로 한다 | 4.4, 6.3.1 |
| ② '전부 보관하거나 전부 표시' | `HeldRecords.add(chunk, records)`가 그 청크의 모르는 기록 전부가 상한 안에 들어갈 때만 저장한다. 아니면 저장된 같은 청크 기록까지 빼고 표시(`o`)만 갱신한다. 표시가 이미 덮는 청크(시각 ≥ `o.f`, 종류 ⊆ `o.k`)는 저장하지 않는다 | 6.3.2 |
| ③ '메타 키 여러 개(키당 < 256 KiB, 총 2 MiB)' | 머리 `sync.heldRecords`(판·조각 수·표시·요약) + 조각 `sync.heldRecords.1`~`sync.heldRecords.9`(기록). 조각 하나 ≤ 224 KiB(`HeldRecords.maxPartBytes`), 전체 ≤ 2 MiB(`maxTotalBytes`). 모든 키는 한 `writeMeta`(마지막 적용 호출)로 함께 쓴다 | 6.3.2 |
| ③ '깨진 값 → 모든 종류 되감기 표시' | 머리나 조각 하나라도 읽을 수 없으면 기록을 모두 버리고 `o = {f, k: ['*']}`로 바꿔 곧바로 다시 쓴다. `f` = 머리의 '가장 이른 보관 시각' 요약(머리도 깨졌으면 0 = 처음부터). `'*'` 표시는 그 표시를 쓴 앱보다 아는 종류가 많은 앱(= 앱 갱신 뒤)에서 되감는다 — 머리가 깨져 그 집합을 모르면 바로 되감는다 | 6.3.5 |
| '앱이 갱신되어 … 보관분을 순서대로 다시 적용' | (청크 serverTime, 청크 id, 기록 위치) 순으로 합성 청크를 만들어 적용한다 | 6.3.4 |
| ⑤ '로그인 상태로 연결할 때, 받기 전에' | 1차 attach 순서 `PurgedSet.load → DownloadPipeline.load` 다음, `catchUp` 전. 세션 플래그로 한 세션에 한 번이고, 실패하면 같은 세션의 다음 연결에서 다시 한다(1차 `if (!s.loaded)` 블록 밖) | 6.3.4 |
| ⑤ 'LRU에 넣지 않으며, 기존 `sync.held`를 풀지 않는다' | `_apply(…, release: true, remember: false, releaseHolds: false)` — `remember: false`는 `keep()`의 LRU 갱신을 끄고, `releaseHolds: false`는 1차의 `held.release(c.id)`를 끈다 | 6.3.4 |
| ⑤ 'K1 기록은 보관에 남겨 다음 연결에서 다시 시도' | 그 기록은 `sync.heldRecords`에 해제 시각 `ra`와 함께 남는다(`sync.held`에 넣지 않음). 다시 시도는 K2 해제 단계(`releaseHeld` — 연결마다 `catchUp` 뒤, live 중 1분마다)에서 g′(= min(서버 시각 추정, 벽시계)) ≥ `ra`일 때, g′를 K1 기준으로 한다. 1차 `sync.held`와 같은 시점이라 '다음 연결'보다 이를 수 있지만, 해제 시각 전에는 시도하지 않고 기록은 성공할 때까지 보관에 있다 | 6.3.4 |
| '`needsAppUpdate`를 한 번' | 새로 보관하거나 표시한 기록이 있는 적용 호출마다 문제 한 건(같은 기록을 다시 받아도 다시 내지 않음) | 6.3.3 |
| `engine?` 생략 = `'auto'` = `MATH_ENGINE`, `'fake'`는 `ALLOW_FAKE_ENGINE`에서만 | 요청이 `'auto'`가 아닌 이름을 직접 고르면 그 이름이 `MATH_ENGINE`과 같거나(설정됨) `'fake'`(허용됨)일 때만 받는다 | 6.8.4 |
| `unavailable` / `internal` 구분 | `EngineError` 종류별 표(`notConfigured`·`rateLimited`·`upstream`·`timeout` → `unavailable`, `badResponse`·`refused` → `internal`) | 6.8.8 |
| '`MATH_API_KEY` (+ engine-specific)' | `MATH_API_KEY` = `MATH_ENGINE`이 고른 엔진의 키(운영에서 엔진은 한 번에 하나). 엔진별 비밀이 아닌 값(`MATHPIX_APP_ID`)은 `defineString` | 6.8.9 |
| `engineVersion` = 실제로 답한 엔진·모델 판 | 가짜 `'1'`, Mathpix `'v3'`(응답에 판이 없어 API 경로 판), Claude = **응답의 `model`**(요청한 `CLAUDE_MODEL`이 아님). 어댑터가 `EngineOutput.version`으로 돌려주고 처리 본문은 그 값을 쓴다 | 4.5, 6.8.4, 6.8.6 |
| 미니 라운드 배포 순서 | 6.10 L5 표의 다섯 단계와 `functions/README.md` 체크리스트 | 6.10 |

### 4.2 `package:sync_engine/sync_engine.dart` — 2차 변화 (추가만)

```dart
// lib/src/model/field_units.dart — exported (1차 4.2). (v2.0) changes
abstract final class FieldUnits {
  static const Set<String> metaKeys = {'id', 'key', 'version', 'createdAt', 'updatedAt'};   // v1.4

  /// v1.4 + (v2.0):
  ///   recording   += 'title'
  ///   pageObject  = id, pageId, type, frame, shape, geometry, style, text, assetId, px, latex,
  ///                 engine, createdAt, updatedAt, deletedAt, version   (union of the 4 known types)
  ///   handwriting = id, noteId, pageId, engineId, sourceRev, lines, createdAt, updatedAt,
  ///                 deletedAt, version
  static Set<String> keysOf(EntityKind kind);

  /// Explicit multi-key groups (v1.4 table 6.3.1). pageObject / handwriting → const []:
  /// they are merged by [wholeUnitExcept] instead.
  static List<Set<String>> groupsOf(EntityKind kind);

  /// (v2.0) Kinds merged as ONE unit: every non-meta key present in either snapshot (unknown
  /// keys included) except these, which are units of their own. null for the v1.4 kinds.
  ///   pageObject  → {'pageId', 'deletedAt', 'engine'}
  ///   handwriting → {'noteId', 'pageId', 'deletedAt'}
  static Set<String>? wholeUnitExcept(EntityKind kind);

  /// v1.4 signature. (v2.0) For a [wholeUnitExcept] kind: [rest] (if not empty) + each present
  /// excepted key as its own unit.
  static List<Set<String>> unitsFor(EntityKind kind, Iterable<String> keys);
}

// lib/src/model/scopes.dart — exported. Signature v1.4; (v2.0) table:
//   pageObject  → noteIdHint ?? 'lib'                      (like stroke)
//   handwriting → json['noteId'] ?? noteIdHint ?? 'lib'    (like page — v1.4 recording is
//                                                           noteIdHint ?? json['noteId'])
abstract final class SyncScopes { /* v1.4 */ }

// lib/src/engine/sync_engine.dart — exported. (v2.0) more counters (defaults keep v1.4 calls).
// v1.4 SyncEngineDebug has no ==, hashCode or toString [확인] — nothing else to extend.
@immutable
final class SyncEngineDebug {
  const SyncEngineDebug({/* v1.4 */, this.heldRecords = 0, this.heldRecordsMarked = false,
      this.reappliedChunks = 0, this.reappliedRecords = 0});
  /// Records stored in sync.heldRecords (S-13): kinds this app does not know yet, plus re-applied
  /// records waiting for their K1 release time.
  final int heldRecords;
  /// (v2.1) A rewind mark (overflow or corrupt value) is waiting for an app update.
  final bool heldRecordsMarked;
  /// (v2.1) Synthetic chunks / records applied by reapplyHeldRecords in this engine's life — kept
  /// out of chunksReceived and the remote-apply latency (old serverTimes would distort them).
  final int reappliedChunks, reappliedRecords;
}
```

- `SyncIssueCode`는 바뀌지 않는다 — 모르는 종류 보류는 1차의 `needsAppUpdate`(비차단, '새 형식 청크'와 같은 코드)를 쓴다. 메시지는 `'<n> record(s) of kind <k> held until the app is updated'`, `ref`는 null(모르는 종류는 `EntityRef`로 나타낼 수 없다).
- `SyncConfig`(1차 4.6)에 필드를 더하지 않는다. 보관 상한(조각 하나 224 KiB·전체 2 MiB)은 내부 상수(`HeldRecords.maxPartBytes`·`maxTotalBytes` — 시험은 내부 인자로 줄인다)다.

(P-C, CP-S7 — 실연결 미니 라운드 준비)

```dart
// lib/src/auth/auth_backend.dart — exported port (1차 4.3). (v2.0, P-C) one member
abstract interface class AuthBackend {
  /* v1.4 */
  /// Firebase ID token of the signed-in user (null when signed out). [forceRefresh] → new token.
  /// Errors: SyncBackendException (network → network, revoked → unauthenticated).
  Future<String?> idToken({bool forceRefresh = false});
}
// lib/src/auth/auth_service.dart — exported (1차 4.3). (v2.0, P-C)
final class AuthService {
  /* v1.4 */
  /// For RecognitionConfig.idTokenProvider (INFRA wires it in the 실연결 미니 라운드).
  /// null when signed out or no backend (unavailable); never throws (logs and returns null).
  Future<String?> idToken({bool forceRefresh = false});
}
```

- `AuthBackend`는 SYNC 안에서만 구현한다(`FirebaseAuthBackend`, `FakeAuthBackend`) — 멤버 추가로 깨지는 다른 영역 코드가 없다 [확인 — 앱이 `sync_engine`에 의존하지 않음, 계약 7.1].

### 4.3 `package:sync_engine/testing.dart` — 추가 (시험 전용)

```dart
// lib/src/testing/sync_test_harness.dart — (v2.0) one optional argument
final class SyncTestHarness {
  TestDevice device(String name, {/* v1.4 */,
      /// (v2.0) Kinds this device's codec knows (default: EntityKind.values). A device built
      /// without, say, handwriting behaves like an older app (S-13); rebuilding it with the
      /// default set (same name → same store, new engine) is the "app update".
      Set<EntityKind>? knownKinds});
  /// (v2.0) Rebuilds [name]'s engine on the same FakeLocalStore (app restart / update).
  TestDevice restart(String name, {Set<EntityKind>? knownKinds});
  /// v1.4 + (v2.1, SYNC-M6) [kinds]: compare only entities of these kinds (null = all, v1.4).
  /// For an old-app device (no handwriting) against the server merged state:
  /// `checkConverged([a, b], kinds: EntityKind.values.toSet()..remove(EntityKind.handwriting))`.
  /// The dump of every participant is filtered the same way before the comparison.
  void checkConverged(Iterable<TestDevice> devices,
      {bool includeServer = true, Set<EntityKind>? kinds});
}

// lib/src/testing/test_device.dart — (v2.0) edit helpers. Every helper is one local write
// (FakeLocalStore.localWrite) with exactly the JSON keys CORE would stamp (C-11).
final class TestDevice {
  /// ShapeObject rectangle (same defaults as PageObjectFixtures.shape, built with the contract
  /// constructors + toJson — lib/ may not import note_core/testing.dart, INFRA R4) or the other
  /// known types: type 'text' | 'image' (needs [assetId]) | 'math'. Returns the object id.
  String addObject(String pageId, {String type = 'shape', AssetId? assetId, int seed = 0});
  /// TransformElements-like: frame (+ geometry for shapes) moved by dx, dy. Fields {frame, geometry}.
  void moveObject(String objectId, {double dx = 10, double dy = 0});
  /// UpdateObjects-like style change. Fields {style}.
  void restyleObject(String objectId, int colorArgb);
  /// Text box text. Fields {text}.
  void editText(String objectId, String text);
  /// RemoveElements-like. Fields {deletedAt}.
  void deleteObject(String objectId);
  /// Writes [json] as a pageObject row as received from a newer app (UnknownObject when the
  /// type is unknown). Used to seed UnknownObject cases without a codec.
  void putRawObject(String pageId, Map<String, Object?> json);
  /// HandwritingRepository.put-like upsert of hw_<pageId> with one line per entry.
  void putHandwriting(String pageId, List<String> lines, {String engineId = 'fake'});
  void removeHandwriting(String pageId);
  /// Recording row (+ a small audio asset when [assetId] is null). Returns the recording id.
  Future<String> addRecording(String noteId, {AssetId? assetId, int durationMs = 1000});
  void renameRecording(String recordingId, String? title);
  void deleteRecording(String recordingId);
  /// Active objects / the handwriting result of a page as SyncDoc (null when absent).
  List<SyncDoc> activeObjectsOf(String pageId);
  SyncDoc? handwritingOf(String pageId);
}
```

- 이름은 1차 도우미(`addStroke`·`recolorStroke`·`moveStroke`·`eraseStroke`·`activeStrokesOf`)와 같은 꼴이다. 새 최상위 이름은 없다(`api_surface_test`는 멤버 목록만 갱신 — `device(knownKinds:)`·`restart`·`checkConverged(kinds:)`·`TestDevice` 도우미·`SyncEngineDebug` 새 필드).
- (v2.1) 하네스의 `knownKinds`·`restart`·`checkConverged(kinds:)`는 **한 작업**(S2-4b)이 만들고 시험한다(`test/testing/sync_test_harness_test.dart`). S2-7b는 그것을 쓰기만 한다(검토 S-4). `checkConverged`의 종류 필터는 `canonicalDump()`의 키(`<kind>/<id>` 꼴 — 1차 T6 형식)를 종류로 거른다. 1차 호출(`kinds` 없음)의 결과는 그대로다.
- `FakeLocalWrite`·`FakeSyncServer.commitRaw`(1차)는 그대로 쓴다 — 모르는 `kind` 기록은 `test/support/raw_records.dart`(export 안 함, 4.4)로 바이트를 만들어 `commitRaw`로 서버에 넣는다.

### 4.4 내부 타입 (export 안 함 — 시험·검토용)

```dart
// lib/src/codec/chunk_codec.dart — internal. (v2.0) additions; decode() keeps its v1.4 meaning.
/// A well-formed record whose header kind 'k' this app does not know (S-13).
@immutable
final class UnknownKindRecord {
  const UnknownKindRecord({required this.kindName, required this.op, required this.id,
      required this.header, required this.bytes, required this.index});
  final String kindName;                 // header 'k'
  final int op;                          // 0x01 upsert | 0x02 purge
  final String? id;                      // header 'id' when it is a string
  final Map<String, Object?> header;     // the record header JSON (the contract's rawJson)
  final Uint8List bytes;                 // the exact encoded record: op, header, blobs
  final int index;                       // position in the payload (0-based)
}

@immutable
final class DecodedPayload {
  const DecodedPayload(this.records, this.unknown);
  final List<SyncRecord> records;        // known kinds, payload order
  final List<UnknownKindRecord> unknown; // payload order
  bool get hasUnknown;
}

abstract final class ChunkCodec {
  /* v1.4: formatVersion = 1, maxRecords, maxHeaderBytes, maxBlobs, blobKeys, encode, assemble,
     payloadLength, encodeRecord, decode (strict: unknown kind → FormatException), maxHlcOf */
  /// (v2.0) decode() with S-13: a record whose 'k' fails [isKnownKind] (default: an
  /// EntityKind name) becomes an UnknownKindRecord; its header must still be a JSON object
  /// with string 'k' (and string 'id' for an upsert). Any other malformation still throws
  /// FormatException for the whole chunk (v1.4).
  static DecodedPayload decodeTolerant(Uint8List bytes, {bool Function(String kindName)? isKnownKind});
}
```

```dart
// lib/src/engine/held_records.dart — internal (new). Value of the sync.heldRecords keys (6.3.2).
final class HeldRecords {
  HeldRecords({this.maxPartBytes = defaultMaxPartBytes, this.maxTotalBytes = defaultMaxTotalBytes,
      required Set<String> knownKinds});
  static const int defaultMaxPartBytes = 224 * 1024;      // per meta value < 256 KiB (1차 7.2.10)
  /// Head + all parts (contract 7.2.8 ③). At the defaults it never binds: the parts hold at most
  /// maxParts × defaultMaxPartBytes = 2,016 KiB and the head stays far below the 32 KiB left —
  /// the real cap is the per-part packing (a record entry is never split across parts, 6.3.2).
  /// Tests lower it (S27 (c)) to reach the all-or-nothing branch with small records.
  static const int defaultMaxTotalBytes = 2 * 1024 * 1024;
  static const int maxParts = 9;                           // sync.heldRecords.1 … .9
  /// [values]: MetaKeys.heldRecordKeys → stored text (absent / '' = empty). Corrupt head or part
  /// (bad JSON, wrong v, part count mismatch, bad base64) → records dropped and the mark becomes
  /// {f: head summary or 0, k: ['*'], a: head 'a' or null}; [wasCorrupt] true so the caller writes
  /// the converted value at once (log warning). Never throws.
  factory HeldRecords.decode(Map<String, String?> values, {required Set<String> knownKinds,
      int maxPartBytes = defaultMaxPartBytes, int maxTotalBytes = defaultMaxTotalBytes});
  bool get wasCorrupt;
  HeldRecords copy();
  bool get isEmpty;                      // no record and no mark
  int get length;                        // stored records (SyncEngineDebug.heldRecords)
  Set<String> get kinds;                 // stored + marked kinds ('*' when corrupt)
  /// Rewind mark: chunks NOT stored (over the cap, or a corrupt value). [from] = earliest chunk
  /// serverTime among them; [kinds] may contain '*'; [writtenBy] = the knownKinds of the app that
  /// set the mark (null if unknown — a corrupt head).
  ({ServerCursor from, Set<String> kinds, Set<String>? writtenBy})? get mark;
  /// Chunk-level all-or-nothing (v2.1, contract 7.2.8 ②). Dedup by (kind, id, fv text). If every
  /// unknown record of [chunk] (new and already stored) fits under maxPartBytes per part and
  /// maxTotalBytes in all, they are stored; otherwise NONE of them is stored — records already
  /// stored under chunk.id are removed — and the mark takes min(from, chunk.serverTime) and the
  /// chunk's kinds. A chunk the mark already covers (serverTime ≥ mark.from and kinds ⊆ mark.kinds
  /// or '*' ∈ mark.kinds) is not stored. Returns how many records were NEW (stored or marked).
  int add(RemoteChunk chunk, List<UnknownKindRecord> records);
  /// Stored records whose kind [isKnown] now and that have no release time (ra), regrouped into
  /// synthetic chunks (original id / scope / serverTime / author, payload = assembled record
  /// bytes), ordered by (serverTime, chunk id, index). The records STAY stored until [settle].
  List<RemoteChunk> knownChunks(bool Function(String kindName) isKnown);
  /// Stored records with ra ≤ [referenceMillis] (K1-held during a re-apply), as above.
  List<RemoteChunk> dueChunks(int referenceMillis);
  /// After a successful re-apply call: records of [applied] are removed, records of [heldUntil]
  /// (chunk id + index → releaseAtMillis) stay with ra set (K1 — contract 7.2.8 ⑤).
  void settle({required Iterable<(String chunkId, int index)> applied,
      required Map<(String chunkId, int index), int> heldUntil});
  /// When the mark should fire now (a marked kind is known, or '*' and [knownKinds] ⊋ writtenBy
  /// or writtenBy == null): the mark is cleared and its from returned (the caller rewinds the
  /// cursor to from − cursorOverlap). Otherwise null.
  ServerCursor? takeMarkIfDue();
  /// MetaKeys.heldRecordKeys → text for every key ('' for an unused part — writeMeta cannot
  /// delete). Canonical JSON, records sorted (s, c, i) and packed into parts in that order.
  Map<String, String> encode();
}

// lib/src/engine/meta_keys.dart — (v2.0, v2.1 split)
abstract final class MetaKeys { /* v1.4 */
  static const String heldRecords = 'sync.heldRecords';                    // head
  static const List<String> heldRecordParts = [                            // records
      'sync.heldRecords.1', /* … */ 'sync.heldRecords.9'];
  static const List<String> heldRecordKeys = [heldRecords, ...heldRecordParts];
}

// lib/src/engine/download_pipeline.dart — internal. (v2.0, v2.1) changes
final class DownloadPipeline {
  DownloadPipeline({/* v1.4 */, Set<EntityKind>? knownKinds});   // default EntityKind.values
  HeldRecords get heldRecords;
  /// v1.4 + reads the sync.heldRecords keys. A corrupt value is written back converted (all-kinds
  /// mark); a mark that is due (HeldRecords.takeMarkIfDue) moves the cursor back (like
  /// deferredFrom, 6.6.5) in the same writeMeta and clears the session LRU.
  Future<void> load();
  /// (v2.0, v2.1) S-13 re-apply at attach, before catchUp: HeldRecords.knownChunks go through
  /// steps 4–8 of applyChunks (purge view, gate, merge, PurgeGuard, groups) via
  /// _apply(release: true, remember: false, releaseHolds: false, reapply: true):
  ///   release      — no LRU skip, cursor and scope statistics unchanged (v1.4 meaning);
  ///   remember     — false: keep() does NOT add the chunk ids to the session LRU (M-1);
  ///   releaseHolds — false: existing sync.held entries are never released or replaced;
  ///   reapply      — K1 holds are reported per record to HeldRecords.settle (ra) instead of
  ///                  sync.held; ApplyResult.latestServerTime = null.
  /// The sync.heldRecords keys ride on the last apply call (one writeMeta when nothing applies).
  /// On failure the in-memory value is unchanged (records not lost) and the next connection of
  /// the session tries again. No-op when nothing is known now.
  Future<ApplyResult> reapplyHeldRecords();
  /// v1.4 K2 + (v2.1) HeldRecords.dueChunks(g′) re-applied the same way with g′ as the K1
  /// reference.
  Future<ApplyResult> releaseHeld();
}
// ApplyResult (internal) — (v2.0) + int heldRecords (records newly stored or marked),
//   (v2.1) + int reappliedChunks, reappliedRecords (counted apart from chunks / applied).

// lib/src/engine/engine_controller.dart — internal. (v2.0, v2.1)
//   attach (1차 6.10.3): PurgedSet.load → DownloadPipeline.load (once per session — v1.4
//   `if (!s.loaded)`), then OUTSIDE that block `if (!s.heldReapplied) reapplyHeldRecords`
//   (s.heldReapplied = true only on success — a failed attempt runs again at the session's next
//   connection), → catchUp → releaseHeld → live.
//   _absorbApply: reapplied counts go to SyncEngineDebug.reappliedChunks / reappliedRecords, not
//   to chunksReceived / lastRemoteApplyLatency.
//   @visibleForTesting set debugKnownKinds(Set<EntityKind>) — before start(); the harness passes
//   TestDevice knownKinds through it.

// lib/src/engine/upload_pipeline.dart — internal. (v2.1, contract 7.2.8 handwriting row)
//   p.onScopesCommitted({for (c in group) if (!c.items.every((i) => i.record.ref.kind ==
//       EntityKind.handwriting)) c.write.scope})   — 1차 line 363; handwriting-only chunks are not
//   'recently sent' for PurgeGuard.

// lib/src/merge/record_gate.dart — internal. (v2.0) check(…, String? elementNoteId) — the
// renamed strokeNoteId: the note of a 'lib'-scope stroke OR pageObject (6.2.4).

// lib/src/compaction/compactor.dart — internal. (v2.0) chunks with unknown-kind records are
// kept like malformed ones (CompactionResult.unknownKindChunks).
```

```dart
// test/support/raw_records.dart — test only (not exported). Builds v1 records byte-for-byte
// with any kind name (canonical JSON header, like ChunkCodec.encodeRecord).
Uint8List rawUpsertRecord({required String kind, required String id,
    required Map<String, Object?> entity, required Map<String, Object?> fieldVersions,
    Map<String, Uint8List> blobs = const {}});
Uint8List rawPurgeRecord({required String kind, required String id, required String hlc});
Uint8List rawPayload(List<Uint8List> records);   // = ChunkCodec.assemble
```

### 4.5 `functions/` 표면 (TypeScript)

배포 표면은 callable 함수 `recognizeMath` 하나다(`src/index.ts`가 그것만 export). 요청·응답 형식은 4.1 원문이고, 아래는 그 원문을 타입으로 옮긴 것과 내부 모듈 시그니처다.

```ts
// src/protocol.ts — the callable format (contract 7.2.13), version 1
export const PROTOCOL_VERSION = 1 as const;
export type EngineName = "auto" | "mathpix" | "claude" | "gemini" | "fake";
export type Locale = "ko" | "en";
export interface StrokesInput { x: number[][]; y: number[][]; t?: number[][]; }   // page pt
export interface RecognizeMathRequest {          // after parseRequest: defaults filled
  v: 1; engine: EngineName; strokes?: StrokesInput; pngBase64?: string; locale: Locale;
}
export interface RecognizeMathResult {
  latex: string; confidence?: number; alternatives?: string[];
  engine: string; engineVersion: string; ms: number;
}
export const LIMITS: {
  readonly strokesJsonBytes: 524288;   // JSON.stringify(strokes) UTF-8 bytes (≤ 512 KB)
  readonly pngBase64Chars: 2097152;    // ≤ 2 MB of base64 text
  readonly maxStrokes: 2000; readonly maxPointsPerStroke: 10000;
  readonly latexChars: 4000;           // = CORE PageObjectLimits.maxLatexLength
  readonly alternatives: 5;
};
/** Checks shape and limits (6.8.3). Unknown top-level keys are ignored (v1 is additive). */
export function parseRequest(data: unknown): RecognizeMathRequest | { error: string };

// src/recognize_math.ts
export interface HandlerDeps {
  ownerUids(): readonly string[];      // OWNER_UIDS, comma separated, trimmed; empty → nobody
  engines: EngineRegistry;
  quota: QuotaStore;
  dailyCap(): number;                  // DAILY_CAP (≤ 0 → no cap)
  now(): number;                       // epoch ms
  /** (v2.1, SYNC-M7) The engine-call deadline signal. Production: AbortSignal.timeout(ms).
   *  Tests pass a function returning their own AbortController's signal and abort() it —
   *  AbortSignal.timeout does not follow node:test mock timers [확인 — 검토 S-6]. */
  engineSignal(ms: number): AbortSignal;
  log: Logger;
}
export const ENGINE_TIMEOUT_MS = 25_000;
/** The callable body without firebase-functions types (unit-testable). Throws HttpsError. */
export function createRecognizeMathHandler(deps: HandlerDeps):
    (req: { auth?: { uid: string } | null; data: unknown }) => Promise<RecognizeMathResult>;
export const recognizeMath: CallableFunction<unknown, Promise<RecognizeMathResult>>;  // onCall(…)

// src/engines/engine.ts
export interface EngineInput { strokes?: StrokesInput; png?: Buffer; locale: Locale; }
export interface EngineOutput {
  latex: string; confidence?: number; alternatives?: string[];
  /** (v2.1, contract 7.2.13) The engine / model that actually answered → engineVersion
   *  (Claude: the response `model` — a server-side fallback may switch it). */
  version: string;
  /** Logged only (never returned): e.g. Claude fallback happened, token counts. */
  logInfo?: Record<string, string | number | boolean>;
}
export interface MathEngine {
  readonly name: Exclude<EngineName, "auto">;
  readonly accepts: { strokes: boolean; png: boolean };
  recognize(input: EngineInput, signal: AbortSignal): Promise<EngineOutput>;
}
export type EngineErrorKind = "notConfigured" | "unsupportedInput" | "rateLimited" | "upstream"
    | "timeout" | "refused" | "badResponse";
export class EngineError extends Error { constructor(readonly kind: EngineErrorKind, message: string); }
export interface EngineRegistry {
  /** 'auto' → MATH_ENGINE; 'fake' only with ALLOW_FAKE_ENGINE; else EngineError. */
  resolve(requested: EngineName): MathEngine | EngineError;
}

// src/engines/registry.ts — (v2.1, SYNC-M7) the ONLY module that reads src/params.ts (besides the
// onCall options in recognize_math.ts). Adapters take everything through their constructors so
// the comparison tool (6.9) builds the same adapters from developer env vars.
export interface EngineSettings {
  mathEngine: string; allowFake: boolean; apiKey: string;   // MATH_ENGINE, ALLOW_FAKE_ENGINE, MATH_API_KEY
  mathpixAppId: string; claudeModel: string;                // MATHPIX_APP_ID, CLAUDE_MODEL
}
export function createRegistry(settings: () => EngineSettings,
    factories?: Partial<EngineFactories>): EngineRegistry;   // factories: test seam
export function registryFromParams(): EngineRegistry;       // reads params .value() per call
// src/engines/fake.ts · mathpix.ts · claude.ts
export class FakeEngine implements MathEngine { constructor(); }
export class MathpixEngine implements MathEngine {
  constructor(opts: { appId: string; apiKey: string; fetch?: typeof fetch }); }
export class ClaudeEngine implements MathEngine {             // P-C, CP-S5
  constructor(opts: { apiKey: string; model: string; client?: ClaudeMessagesClient }); }
export interface ClaudeMessagesClient {                       // thin seam over the SDK
  create(params: BetaMessageCreateParamsNonStreaming, opts: { signal: AbortSignal }): Promise<BetaMessage>;
}

// src/quota.ts
export interface QuotaStore {
  /** Atomically counts one call of [uid] on [dayKey]; allowed false (count unchanged) at [cap]. */
  take(uid: string, dayKey: string, cap: number): Promise<{ allowed: boolean; used: number }>;
}
export class FirestoreQuotaStore implements QuotaStore { constructor(db: Firestore, collection?: string); }  // 'fnQuota'
export class MemoryQuotaStore implements QuotaStore {}
export function seoulDayKey(epochMs: number): string;      // 'yyyymmdd' in UTC+9 (no DST)

// tool/eval_score.ts (P-C)
export function normalizeLatex(latex: string): string;     // 6.9.3
export interface EvalRow { fixtureId: string; engine: string; ok: boolean; latex?: string;
  expected: string; ms: number; error?: string; costUsd?: number; }
export function summarize(rows: EvalRow[]): EvalSummary;   // per engine
export function renderSummaryMarkdown(s: EvalSummary): string;   // the 03-recognition 6.6 table
```

---
## 5. 사용하는 다른 영역의 계약

계약 원문을 글자 그대로 옮긴다(`// 계약 v2.1 7.x.x 원문`). SYNC 코드는 CORE만 import한다(1차 계약 7.1 — `sync_engine`의 허용 의존은 `note_core`). `functions/`는 어떤 Dart 패키지도 import하지 않고, 소비자(LIBRARY)와는 callable 형식(X36)으로만 만난다.

### 5.1 CORE (`package:note_core/note_core.dart`)

#### 5.1.1 페이지 객체 — 쓰는 부분

`// 계약 v2.3 7.2.2 원문` (발췌: SYNC가 쓰는 `PageObject`·`UnknownObject`·`EntityKind`)

```dart
// lib/src/model/stroke.dart — PageElement stays sealed; the new subtypes are `part` files
// of this library (page_object.dart, shape_object.dart, …).
sealed class PageElement implements SyncEntity { /* v1.4: id, pageId, bounds, createdAt, updatedAt */ }
final class Stroke extends PageElement { /* v1.4 */ }

/// (v2.0) Every page element that is not a Stroke: EntityKind.pageObject, table
/// `page_objects`, subtype chosen by JSON `type`.
sealed class PageObject extends PageElement {
  const PageObject();
  @override EntityKind get kind => EntityKind.pageObject;
  String get type;                               // 'shape' | 'text' | 'image' | 'math' | unknown
  ElementFrame get frame;
  @override EpochMillis? get deletedAt;
  @override Hlc? get version;
  /// Assets this object references (ImageObject: {assetId}); others empty.
  Set<AssetId> get referencedAssets;
  /// (v2.1) THE object transform rule. CORE's resolver (TransformElements) and every preview
  /// (INK selection / pending display, EDITOR) call this same function (INK review M-2):
  ///   frame / geometry transformed by m; s = m.uniformScale;
  ///   ShapeObject: style.strokeWidth × s clamped [0.1, 30] when [scaleWidth];
  ///   TextBoxObject: style.fontSizePt × s clamped [6, 144] (CP-2 — wrap width and text scale
  ///   together, so the frame height still fits; K-6);
  ///   MathObject: style.fontSizePt × s clamped [6, 144]; ImageObject: frame only;
  ///   UnknownObject: returns itself unchanged.
  PageObject transformed(Affine2 m, {bool scaleWidth = true});
  /// Paste / duplicate / page copy: new id, page and createdAt; version and deletedAt cleared.
  PageObject copyTo({required ElementId id, required PageId pageId, required EpochMillis createdAt});
  PageObject copyWithMeta({EpochMillis? updatedAt, EpochMillis? deletedAt,
      bool clearDeletedAt = false, Hlc? version});
  /// (v2.1, CP-4) History memory estimate (02-core 4.3 formula).
  int get estimatedBytes;
  @override Map<String, Object?> toJson();
  /// Dispatches on `type`; an unknown type → UnknownObject (never throws for that reason).
  /// (v2.1, CP-6) A known type with an enum name this app does not know (`shape`, `dash`,
  /// `arrowHeads`, `align`) is also read as UnknownObject. Never normalizes (remote values
  /// round-trip unchanged; normalization happens when a LOCAL command is resolved).
  factory PageObject.fromJson(Map<String, Object?> json);
}

abstract final class PageObjectLimits {
  static const int maxObjectsPerPage = 2000;
  static const int maxTextLength = 10000;        // TextBoxObject.text, String.length
  static const int maxLatexLength = 4000;
  static const int maxPolylinePoints = 64;
}
```

```dart
/// Object written by a newer app (or, v2.1 CP-6, a known type with an unknown enum name). It can
/// be selected, deleted and copied as a whole and is synced unchanged; it cannot be transformed or
/// edited. JSON round-trips key-for-key (C-12).
final class UnknownObject extends PageObject {
  /// (v2.1, CP-4) rawJson must carry id, pageId, type, createdAt, updatedAt (FormatException
  /// otherwise); kept as an unmodifiable deep copy; frame / deletedAt / version read from it.
  UnknownObject(Map<String, Object?> rawJson);
  @override final String type;
  final Map<String, Object?> rawJson;
  /// From rawJson['frame'] when decodable, else ElementFrame(PageRect(0, 0, 1, 1)).
  @override final ElementFrame frame;
  @override PageRect get bounds => frame.bounds;
  /// (v2.1) A string `assetId` key in rawJson is reported (so a later asset GC keeps it).
  @override Set<AssetId> get referencedAssets;
  /// (v2.1) rawJson with the meta keys (id, pageId, createdAt, updatedAt, deletedAt, version) set
  /// to the current values; every other key as read. ==, hashCode: deep equality of toJson().
  @override Map<String, Object?> toJson();
}
```

- `EntityKind`(깨짐): `enum EntityKind { folder, note, page, stroke, penPreset, asset, recording, setting, pageObject, handwriting }` — 뒤에 둘을 더한다. 이름(wire)은 enum 이름 그대로다.
- `Stroke.compareOrder(PageElement a, PageElement b)`는 그대로 객체에도 쓴다(createdAt → id).
- 붙여넣기·복제된 객체는 `copyTo`로 새 `createdAt`(= 붙여넣은 시각 + i, 1차 획 클립보드 규칙과 같음)을 받는다.
- (v2.1, CP-4·CP-5) 4종의 공통 필드(`id`·`pageId`·`createdAt`·`updatedAt`(생성자 `updatedAt ?? createdAt`)·`deletedAt`·`version`)와 값 `==`·`hashCode`는 종류마다 같다. 스타일 정규화: `ShapeStyle.normalized()`는 `strokeColorArgb`·`fillColorArgb` 알파를 0xFF로(불투명도는 `*Opacity`가 가짐), `TextBoxStyle.backgroundArgb` 알파는 그대로(반투명 배경 허용). 정규화는 **로컬 명령 해석 때만** 하고 `fromJson`은 하지 않는다. 세부 표·`estimatedBytes` 공식은 02-core 4.3·6.2.3이 단일 출처다.
- (v2.1) 소비자는 객체 종류를 Dart 타입(`is TextBoxObject`, `switch`)으로 나눈다. `type` 문자열은 저장 형식용이다(`UnknownObject`도 `'shape'` 같은 알려진 이름을 가질 수 있다).

SYNC가 이 타입을 쓰는 곳: `SyncDoc.toEntity()`(1차 — `EntityJson.decode`가 `pageObject → PageObject.fromJson`), 가짜 로컬 저장소의 페이지별 색인·노트 찾기(`PageObject.pageId`), 복구 사본(`copyTo`), `TestDevice` 도우미(계약 생성자 + `toJson()`으로 만든 JSON — (수정 2회차) `TestDevice`는 `lib/` 코드라 INFRA R4(`test_only_entrypoints`)로 `package:note_core/testing.dart`의 `PageObjectFixtures`를 import할 수 없다. 기본값만 그 도우미와 같게 둔다 — 5.1.5). SYNC는 객체의 종류별 필드를 해석하지 않는다(병합은 JSON 키 단위).

#### 5.1.2 녹음 이름

`// 계약 v2.3 7.2.4 원문` (발췌)

```dart
// Recording (v1.4 CORE 4.2) — 추가: title
final class Recording implements SyncEntity {
  const Recording({/* v1.4 fields */, this.title});
  final String? title;                           // trimmed 1..100 chars; null → UI shows '녹음 N' by startedAt order
  Recording copyWith({/* v1.4 */, String? title, bool clearTitle = false});
  // JSON: 'title' — (v2.1, CP-7) always written (null when unset); absent on read = null.
  // Old apps ignore it (no deployed old app before 실연결).
}
```

- (v2.1) 02-core CP-7이 계약 문장이 되었다: `Recording.toJson`은 `title` 키를 **항상** 쓴다(없으면 null) — SYNC 키 표의 집합이 고정된다(6.2.1). 읽을 때 키가 없으면 null이고, 병합에서는 '없는 키는 그쪽 base 버전'(1차 T4 결정 ①)이라 결과가 같다.

#### 5.1.3 손글씨 인식 결과

`// 계약 v2.3 7.2.5 원문` (발췌: 결정 문장과 엔티티)

결정(조사 01 R7, 03 R3·R8 채택):

- 손글씨 인식 결과는 **동기화되는 엔티티**(`EntityKind.handwriting`)로 페이지마다 하나 둔다. 웹(ML Kit 불가)은 네이티브가 만든 결과를 받아 검색만 한다(실연결 뒤).
- id는 결정적이다: `HandwritingText.idFor(pageId) = 'hw_' + pageId`(1차 7.4.6 ID 규칙의 예외에 추가 — 두 기기가 같은 페이지를 인식해도 같은 엔티티가 된다).
- 검색 색인(`search_units` + FTS5)은 **기기 로컬 파생 데이터**다. 동기화·백업하지 않고 언제든 다시 만든다.
- 한국어 토큰화는 '음절 바이그램을 Dart에서 만들어 `unicode61` 내용 없는 테이블에 넣는' 방식(조사 03 9.2 실험)으로 한다. 정규화 함수는 제목·PDF·손글씨·텍스트 상자가 **하나**(`SearchText.normalize`)를 쓴다.

```dart
@immutable
final class HandwritingLine {
  const HandwritingLine({required this.text, this.alternatives = const [], required this.rect,
      required this.strokeIds, this.languageTag = 'ko', this.userConfirmed = false});
  final String text;                             // best, user-chosen or user-edited text
  final List<String> alternatives;               // ≤ 5, engine order
  final PageRect rect;                           // union of the line strokes' pointBounds, page pt
  final List<ElementId> strokeIds;
  final String languageTag;                      // BCP-47 of the model that produced [text]
  /// Set by the conversion UI. (v2.1) Auto re-recognition keeps a confirmed line's text while
  /// ≥ 80 % of its old strokeIds are still in the new line and the added strokes are small (each
  /// box ≤ the line's median glyph height); otherwise the engine text replaces it, userConfirmed
  /// becomes false and the old confirmed text goes first in alternatives. Rule owner: recog
  /// (05-library 6.9.4); writers merge through HandwritingRepository.update (G-4).
  final bool userConfirmed;
  Map<String, Object?> toJson();
  factory HandwritingLine.fromJson(Map<String, Object?> json);
}

final class HandwritingText implements SyncEntity {
  HandwritingText({required this.noteId, required this.pageId, required this.engineId,
      required this.sourceRev, required this.lines, required this.createdAt, int? updatedAt,
      this.deletedAt, this.version}) : id = idFor(pageId);
  static String idFor(PageId pageId) => 'hw_$pageId';
  /// Input strokes = active strokes of the page whose tool is not highlighter / tape / laser.
  /// sourceRev = first 16 hex chars of sha256 over "id:updatedAt;" of those strokes sorted by id.
  static String sourceRevOf(Iterable<Stroke> inputStrokes);
  static bool isRecognitionInput(Stroke s);
  @override final String id;
  final NoteId noteId; final PageId pageId;
  final String engineId;                         // 'mlkit-digital-ink/19.0.0:ko' — provenance only.
  // (v2.1) Freshness = same sourceRev AND same language tail (':ko'); a result from another engine,
  // engine version or device is fresh (no double recognition across devices after 실연결).
  final String sourceRev;
  final List<HandwritingLine> lines;             // reading order
  @override EntityKind get kind => EntityKind.handwriting;
  // createdAt, updatedAt, deletedAt, version, isDeleted, toJson / fromJson, ==,
  // (v2.1, CP-13) copyWith (HandwritingLine too); put validation: 02-core 6.9.4
}

abstract interface class HandwritingRepository {
  Future<HandwritingText?> forPage(PageId pageId);
  Stream<HandwritingText?> watchPage(PageId pageId);
  /// Upsert. Also re-indexes the page's ink units (same transaction when possible; an index
  /// failure never fails the write — C-13). (v2.1) Local writers (indexer, conversion UI) use
  /// [update] so a write that arrived meanwhile is merged, not overwritten (G-4).
  Future<void> put(HandwritingText value);
  /// (v2.1) Read-merge-write in ONE CORE write transaction: [transform] gets the stored value
  /// (null if none / deleted) and returns the value to store (null = leave as is). Synchronous and
  /// pure (no await inside). Returns the stored value afterwards. Same validation as put.
  Future<HandwritingText?> update(PageId pageId,
      HandwritingText? Function(HandwritingText? current) transform);
  Future<void> removeForPage(PageId pageId);
  /// Active pages of [noteId] whose input strokes' sourceRevOf differs from the stored value
  /// (or that have none and at least one input stroke). Cheap: uses DB columns, no point decode.
  /// (v2.1) Page order.
  Future<List<PageId>> stalePages(NoteId noteId);
  /// (v2.1) Active notes with ≥ 1 stale page, one query over the pages.ink_rev cache — the
  /// indexer's start-up catch-up. Most recently updated note first.
  Future<List<NoteId>> notesWithStalePages();
}
final handwritingRepositoryProvider = Provider<HandwritingRepository>(/* store.handwriting */);
```

SYNC가 쓰는 것: `EntityKind.handwriting`, `HandwritingText.idFor`(결정적 id — 두 기기가 같은 페이지를 인식하면 **같은 엔티티**가 되어 병합으로 만난다), JSON 키. `HandwritingRepository`는 CORE·LIBRARY 사이 API이고 SYNC는 쓰지 않는다(원격 적용은 1차 `SyncStore.applyRemote` 경로 — CORE가 쓰기 훅으로 색인을 다시 만든다, 02-core 6.13). T16-v2(`core_handwriting_test`)는 실제 CORE의 `store.handwriting.put`(다른 기기의 결과 흉내)·`forPage`·`search.searchPages`를 시험 도구로 부른다. (v2.1) `update`(G-4 — 색인기·변환 창의 로컬 병합 쓰기)와 신선함 규칙(`sourceRev` + 언어)은 SYNC 병합에 영향이 없다 — 기기 사이에서는 손글씨가 한 단위 LWW다(R6·Q7, C21-09).

#### 5.1.4 JSON 키 (저장 형식)

`// 계약 v2.3 7.2.7 원문` (발췌: 페이지 객체 JSON 표·예시·손글씨·녹음 JSON)

페이지 객체 JSON(동기화·백업 공통, camelCase, 모르는 키 무시 — 1차 규칙 그대로):

| `type` | 공통 키 | 종류별 키 |
|---|---|---|
| (모두) | `id`, `pageId`, `type`, `frame`(`[l,t,r,b,rot]` — **모든 종류가 쓴다**: 옛 앱이 모르는 종류를 자리표시로 그릴 수 있게. 도형은 기하에서 계산한 값을 쓰고 읽을 때는 무시), `createdAt`, `updatedAt`, `deletedAt`, `version` | |
| `shape` | | `shape`(`ShapeKind` 이름), `geometry`(`{"poly":[x0,y0,…],"closed":true}` 또는 `{"ellipse":[l,t,r,b,rot]}`), `style`(`ShapeStyle.toJson`) |
| `text` | | `text`, `style`(`TextBoxStyle.toJson`) |
| `image` | | `assetId`, `px`(`[w,h]`) |
| `math` | | `latex`, `style`(`MathStyle.toJson`), `engine`((v2.1) 항상 씀 — 없으면 `null`) |

예시(`shape`, 회전 0 사각형 — 키 순서는 JSON에서 의미 없음):

```json
{"id":"0193a1f0-…","pageId":"0193a1e2-…","type":"shape",
 "frame":[120.0,80.0,320.0,200.0,0.0],
 "shape":"rectangle",
 "geometry":{"poly":[120.0,80.0,320.0,80.0,320.0,200.0,120.0,200.0],"closed":true},
 "style":{"strokeColorArgb":4279900698,"strokeWidth":2.0,"strokeOpacity":1.0,"dash":"solid","fillColorArgb":null,"fillOpacity":1.0,"arrowHeads":"none"},
 "createdAt":1762300000000,"updatedAt":1762300000000,"deletedAt":null,"version":"…"}
```

- 종류별 키 이름(`style` 안 키 포함)은 CORE `entity_json` 골든과 SYNC 'JSON 키 대조' 시험(1차 T16)이 함께 검사한다. `style` 안 키는 각 `toJson`의 필드 이름(camelCase) 그대로다.
- (v2.1) 종류별 키 집합은 고정이다 — 값이 없어도 키를 쓴다(`engine: null`, `Recording.title: null`). SYNC `kPageObjectTypeKeys`와 CORE 골든이 같은 집합을 대조한다(`math` 골든에 `engine: null` 사례 포함).

손글씨 결과 JSON: `id`, `noteId`, `pageId`, `engineId`, `sourceRev`, `lines`(배열), `createdAt`, `updatedAt`, `deletedAt`, `version`. 녹음 JSON: v1.4 + `title`.

#### 5.1.5 기반 단계 시험 도우미

`// 계약 v2.3 7.6 원문` (발췌: SYNC 시험이 JSON 고정 자료를 만들 때 쓰는 부분 — 같은 블록의 가짜 오디오 등은 SYNC가 쓰지 않아 생략)

```dart
// package:note_core/testing.dart — v2.0 additions (web-safe, test/ only)
/// v1.4 signature unchanged. v2.0 behaviour: page objects (AddObjects / UpdateObjects /
/// RemoveElements / TransformElements / ClearPage.includeObjects / PageDraft.objects), recordings
/// (RecordingRepository), recording drafts (memory), handwriting (HandwritingRepository, (v2.1)
/// incl. update / notesWithStalePages) and a memory SearchIndex that applies (v2.1, CP-14) the
/// SAME judgement, candidate order and ranking code as the real FTS index — results AND order
/// equal the real store for the 7.7 V10 query set. openTestNoteStore (testing_vm.dart) is the
/// real CORE v2.
NoteStore createFakeNoteStore({/* v1.4 args */});
abstract final class PageObjectFixtures {
  static ShapeObject shape({required String pageId, ShapeKind kind = ShapeKind.rectangle,
      PageRect rect = const PageRect(100, 100, 300, 220), int createdAt = 1, String? id});
  static TextBoxObject textBox({required String pageId, String text = '안녕 hello',
      PageRect rect = const PageRect(100, 300, 400, 340), int createdAt = 1, String? id});
  static ImageObject image({required String pageId, required AssetId assetId,
      PageRect rect = const PageRect(100, 400, 300, 550), int pixelWidth = 400,
      int pixelHeight = 300, int createdAt = 1, String? id});
  static MathObject math({required String pageId, String latex = r'\frac{a}{b}',
      PageRect rect = const PageRect(100, 600, 200, 650), int createdAt = 1, String? id});
  static UnknownObject unknown({required String pageId, String type = 'sticker',
      PageRect rect = const PageRect(400, 100, 450, 150), String? id});
}
```

- (수정 2회차 — 재검토 항목 1) **B7a의 SYNC 고정 자료는 `PageObjectFixtures`를 쓰지 않는다.** 그 도우미는 B2-α에서 선언만 있고(`UnimplementedError('CORE T23b')`) B2-β 끝(T23b)부터 동작한다(02-core 8.1 'B2 상태' 표 `PageObjectFixtures` 행, 02-core 5.8 '다른 영역이 개발 중 쓰는 CORE 쪽' 표 'B2-β 끝(T23b)부터 동작' — SYNC는 그 행의 대상이 아니다). B7a의 마지막 확인은 T20a 해시 위에서 하므로(6.4·8.1), `test/support/entity_fixtures.dart`의 `fixtureJson(pageObject)`·`fixtureJson(handwriting)`과 새 `objectFixture(type)`(`'shape'`·`'text'`·`'image'`·`'math'`·`'sticker'`)는 **계약 생성자**(`ShapeObject(…)`·`TextBoxObject(…)`·`ImageObject(…)`·`MathObject(…)`·`UnknownObject(rawJson)`·`HandwritingText(…)`·`HandwritingLine(…)` — 'B2 상태' 첫 행 '생성자·필드·`==`·enum·상수는 실제', B2-α부터. `UnknownObject` 생성자가 부르는 `ElementFrame.fromJson`은 T20a)로 객체를 만들고 **T20a의 `toJson()`**으로 JSON을 얻는다. 도형 기하는 템플릿(`ShapeGeometry.rectangle` — T20b)이 아니라 `PolylineGeometry([…4점], closed: true)`를 직접 만든다(도형 `frame` 키는 `toJson`이 기하에서 계산 — 02-core 6.2.6 마지막 행, T20a). 값(사각형·글자·크기)은 위 `PageObjectFixtures` 기본값과 같게 둔다. 그래서 '종류마다 도는 시험'과 `field_units_test` 종류별 비교가 T20a 해시에서 판정된다.
- `PageObjectFixtures`는 SYNC의 `test/`가 동시 개발 단계(R2-B2 묶음 병합 뒤 — T23b 포함)에 필요할 때만 쓴다. `lib/src/testing/test_device.dart`(4.3)는 R4 때문에 쓰지 못하고 같은 생성자 방식으로 만든다. 새 시험은 `createFakeNoteStore()` v2를 쓰지 않는다 — SYNC의 로컬 쪽 가짜는 자기 `FakeLocalStore`(1차 07-sync 4.11)다(1차 시험 `providers_test`·`local/core_sync_local_store_test`의 v1 사용은 그대로 — [확인] 1차 작업 트리 `grep`).
- 실제 CORE는 1차처럼 `openTestNoteStore(filePath:)`(`testing_vm.dart`)로 연다. 실제 저장소의 객체 명령은 CORE T27, 녹음·손글씨·검색 쓰기는 T30·T32·T33까지 `UnimplementedError`(02-core 8.1 'B2 상태')라 T16-v2는 작성만 하고 기본 skip이다(1차 T16과 같은 처리). 파일·경우별로 기다리는 CORE 이정표 커밋은 6.7.2의 선행 작업 표(T24·T26~T33)다.

#### 5.1.6 동기화 창구 — CORE가 맞추는 것 (02-core 5.6)

| 항목 | CORE 보장 | SYNC가 확인하는 시험 |
|---|---|---|
| outbox·`EntityChange` 힌트 | `pageObject`·`handwriting`은 `noteId`·`pageId` **항상**. 페이지 행이 없는 객체(원격 고아)는 1차 고아 획처럼 `noteId = ''` | 계약 스위트 C-26·C-27 |
| 원격 고아 객체 | 페이지보다 먼저 온 객체는 `note_id = ''`로 저장, 페이지가 오는 커밋에서 입양 — 그 `EntityChange`는 페이지가 온 커밋의 batch | C-28 |
| `content_rev` | 객체·손글씨가 쓰인 기존 페이지는 원격 적용 끝에 `contentRevision + 1`(1차 7.2.10 v1.1 규칙의 확장) | C-29 |
| 영구 삭제 | 노트 영구 삭제(휴지통 비우기·자동 정리·`RemotePurge`)가 그 노트의 객체·손글씨 결과와 outbox 항목을 지움(02-core 6.14.2) | C-30 |
| 기기 로컬 | `recording_drafts`·`search_*`·페이지 캐시 열은 outbox·`readVersioned`·백업에 나오지 않음 | C-30 |
| 녹음 이름 | `renameRecording`은 `title` 필드만 새 버전 | C-31 |
| 노트 복사(`duplicateNoteForRecovery` 포함) | 녹음 행 새 id + 획 `recordingId` 바꿈 → 객체 `copyTo` → 손글씨 결과 새 id(`hw_<새 페이지>`)·`strokeIds` 바꿈(02-core 6.14.1) | `PurgeGuard` 사본 — S30, O5 |
| `UnknownObject` | 읽은 JSON을 키 하나 빠짐없이 그대로 씀(C-12). 선택·삭제·통째 복사만 됨 | `core_unknown_type_test` |
| 모르는 키(알려진 `type`) | 읽을 때 무시 — 이 앱에서 그 객체를 고치면 그 키는 사라진다(02-core 6.2.6) | 6.2.2의 판 섞임 규칙, `field_units_test` |

### 5.2 INFRA (앱 셸 · 빌드 · CI)

`// 계약 v2.3 7.4.6 원문` (발췌: 태그 `emulator`·무거운 시험 잠금)

| 항목 | 규칙 |
|---|---|
| 태그 `emulator` | `functions/` 에뮬레이터 + Dart HTTP 클라이언트(VM) 시험. 기본 skip. (v2.1 정정) **컨테이너에서 전역 잠금으로 돌리고 CI `functions` 잡에서 반복**한다(조사 04 6.4·07-sync 6.8.11에서 컨테이너 실행 확인 — V13은 컨테이너 기준) |
| 무거운 시험 잠금 (v2.1) | `media`·`emulator`·전체 Chrome 실행은 컨테이너 전역 잠금 하나로 한 번에 하나만 돈다. 잠금 파일은 고정 경로 `/tmp/noteapp-heavy-tests.lock`(환경 변수 `NOTEAPP_HEAVY_LOCK`으로 바꿈 — 에이전트마다 `$TMPDIR`가 다를 수 있다). 잠금을 쥔 프로세스는 자식에게 `NOTEAPP_HEAVY_LOCK_HELD=1`을 넘기고, 그 환경의 `ws test`는 잠금을 다시 잡지 않는다(중첩 교착 방지 — SYNC 검토 X-2). npm·셸 스크립트는 `dart run tool/ws.dart with-heavy-lock -- <명령>`으로 감싼다(INFRA. bash 쪽 구현을 따로 두지 않는다). 재시도·`--member-timeout` 동안 잠금을 유지한다 |

INFRA가 SYNC를 위해 하는 것과 SYNC의 변경 요청:

| # | 내용 | INFRA 계획서 | SYNC 처리 |
|---|---|---|---|
| RQ-1 | `app/firebase.json`의 `functions`(`source: "../functions"`)·`emulators`(functions 5001, auth 9099, 127.0.0.1) — R2-B1 | 01-infra 6.14 | 받아들임. [확인] 같은 모양의 설정으로 `--project demo-noteapp` 에뮬레이터를 띄우면 `functions/.env.demo-noteapp`을 읽는다(6.8.11 실험) |
| RQ-2 | `.gitignore`: `functions/node_modules/`·`functions/lib/`·`functions/.env.local`·`functions/.secret.local`·`functions/eval-out/`·`firebase-debug*.log` — **`functions/.env.demo-noteapp`은 무시하지 않는다**(커밋) | 01-infra 3.1 `.gitignore` 추가분(R2-B1 ⑩, INFRA-M11) + `tool/test/repo_hygiene_test.dart`(`git check-ignore`로 `.env.demo-noteapp`·`package.json`·`package-lock.json` 미무시, `.env.local`·`.secret.local`·`lib/x.js`·`node_modules/a`·`eval-out/r.json`·`firebase-debug*.log` 무시) | **반영 확인**(2026-11-05, 01-infra 3.1 블록 — 계약 7.4.7 목록과 같다). 미니 라운드의 `functions/.env.<projectId>`도 어떤 패턴에도 걸리지 않는다(`.env.local`만 무시 — 같은 블록) |
| RQ-3 | `functions.yml`: `npm ci` → `npm test` → `npm run test:emulator` → Flutter → Dart `emulator` 시험. Dart 단계의 `firebase emulators:exec`는 SYNC의 `.env.demo-noteapp` 값(`OWNER_UIDS=owner-uid`, `MATH_ENGINE=fake`, `ALLOW_FAKE_ENGINE=true`, `QUOTA_STORE=memory`)으로 함수가 뜬다 | 01-infra 6.14 J16 | 받아들임 |
| RQ-4 | INFRA 요청 R-6: `functions/package.json`에 `firebase-tools 15.34.1`(devDependencies — v2.3, C23-01. 요청 당시 15.34.2)와 `build`·`test`·`test:emulator`, 에뮬레이터 설정은 `--config ../app/firebase.json` | 01-infra 5.9 R-6, CP11 | **받아들임**(3.4). (v2.1 정정, SYNC-M2) `test:emulator`는 `scripts/emulator_suite.sh`가 `npx firebase emulators:exec --config ../app/firebase.json --only functions,auth --project demo-noteapp "node --test 'lib/test-emulator/**/*.emulator.test.js'"`를 부른다(따옴표 글롭 — 디렉터리 인자는 Node 22에서 실패, 3.4) |
| RQ-5 | 컨테이너 전역 무거운 시험 잠금을 **npm 스크립트에서도** 잡을 수 있게 감싸기를 둔다 | (v2.1) 계약 7.4.6 '무거운 시험 잠금'·01-infra 4.2 `with-heavy-lock`(R2-B1 ⑦)·6.13·5.9 R-10 | **INFRA 답 받아들임**: `emulator_suite.sh`는 `dart run tool/ws.dart with-heavy-lock -- …`로 자기 자신을 다시 실행하고, 안쪽(Dart `ws test -t emulator` 포함)은 `NOTEAPP_HEAVY_LOCK_HELD=1`을 물려받아 다시 잡지 않는다. 셸 잠금 구현은 두지 않는다(R2-B7b가 R2-B1 바로 뒤라 필요 없다). 잠금 고정 경로 `/tmp/noteapp-heavy-tests.lock`(6.8.11) |
| RQ-6 | (배포용) `app/firebase.json` `functions[0].ignore`에 `src`·`test`·`test-emulator`·`tool`·`lib/test`·`lib/test-emulator`·`lib/tool`·`scripts`를 더한다 — 배포 꾸러미에 시험·도구가 들어가지 않게 | 01-infra 6.14 — R2-B1 ⑧에서 함께 넣음(INFRA X-6 답) | 받아들임. 미니 라운드 배포 전에 꾸러미 목록을 한 번 본다(`firebase deploy --only functions --dry-run` [추측 — firebase-tools 옵션 이름, 미니 라운드에서 확인], 6.10 L5) |
| RQ-7 | (미니 라운드) 앱의 `RecognitionConfig.idTokenProvider` = `() => ref.read(authServiceProvider).idToken()` | 01-infra 1장 미니 라운드 | 4.2 `AuthService.idToken`(P-C, CP-S7) |
| RQ-8 (새) | `functions.yml`의 단계 순서(01-infra 6.14: `npm ci` → `npm test` → `npm run test:emulator` → flutter-action → Dart `emulator`)에서 `npm run test:emulator`는 **Flutter·Dart가 설치되기 전**에 돈다. 그래서 `emulator_suite.sh`는 `CI=true`(GitHub Actions가 늘 넣는 값)이면 `with-heavy-lock` 없이 바로 돈다(CI 러너는 잡마다 따로라 잠금이 비어 있다 — 01-infra 6.13과 같은 판단). INFRA 쪽 변경은 없고, `workflows_test`가 이 순서를 바꾸면 이 줄도 함께 본다 | 01-infra 6.14 | 정보(변경 요청 아님) — 6.8.11 스크립트 |

### 5.3 LIBRARY (`ink_recognition` — `recognizeMath`의 소비자)

LIBRARY는 callable 규약을 `package:http`로 구현한다(05-library 6.11). SYNC가 서버에서 지키는 것과 LIBRARY 계획서의 기대를 맞춘 표:

| LIBRARY 기대 (05-library) | SYNC 서버 동작 | 확인 |
|---|---|---|
| 요청 `POST`, `{"data": <in>}`, 선택 `Authorization: Bearer` / 성공 200 `{"result": …}` / 실패 `{"error": {"status": "UNAUTHENTICATED" …, "message"}}` (5.6 [추측]) | firebase-functions `onCall` 규약 그대로 | **[확인]** 에뮬레이터: 토큰 없음 → 401 `{"error":{"message":"sign-in required","status":"UNAUTHENTICATED"}}`, 소유자 아님 → 403 `PERMISSION_DENIED`, 잘못된 입력 → `INVALID_ARGUMENT`, 정상 → `{"result":{…}}`(6.8.11). 상태 코드 표(firebase-functions 7.4.0 `lib/common/providers/https.js` `errorCodeMap`): invalid-argument 400, unauthenticated 401, permission-denied 403, resource-exhausted 429, internal 500, unavailable 503 [확인] |
| `engine: 'auto'`(앱 기본), 시험은 `'fake'` | 4.1 표의 해석(CP-S3) | `handler.test.ts`, 에뮬레이터 |
| `strokes.t` = 첫 획 첫 점부터 ms(정수), 좌표 페이지 pt 소수 1자리(CP-L8) | 지지 — 서버는 `t`를 정수 ms ≥ 0, 획마다 단조 비감소로 검사(6.8.3) | `protocol.test.ts` |
| `strokes` JSON ≤ 512 KB(앱이 점을 줄여 맞춤), `pngBase64` ≤ 2 MB(넘으면 앱이 뺌) | 같은 한도로 검사, 넘으면 `invalid-argument` | `protocol.test.ts` |
| 가짜 엔진 결과 `engineId` `'fake/<판>'`(앱이 `'<engine>/<engineVersion>'`로 만듦) | `engine: "fake"`, `engineVersion: "1"`, LaTeX는 계약 7.6 가짜 엔진 규칙(4.1 원문 — 6.8.5). (v2.1) 실제 엔진의 `engineVersion`은 실제로 답한 판(Claude는 응답 `model`) | LIBRARY `callable_emulator_test`(L2-I6 — SYNC E1~E3·E5~E9 값을 그대로 단언), SYNC `recognize_math.emulator.test.ts` |
| 소유자 `owner-uid`·남 `stranger-uid`(05-library 6.11.7, Q4) | `.env.demo-noteapp` `OWNER_UIDS=owner-uid`, 사용자 만들기 규약 6.8.11 | 같은 두 시험 |
| `RESOURCE_EXHAUSTED` → '오늘 쓸 수 있는 수식 인식 횟수를 다 썼어요' | 하루 상한에서만 낸다. 엔진 쪽 429는 `unavailable`(사용자 상한과 섞지 않음) | `handler.test.ts` |
| 시간 제한 35 s(서버 30 s + 5 s) | 엔진 호출 25 s(`HandlerDeps.engineSignal(25_000)` — 운영 `AbortSignal.timeout`) + 처리, 함수 `timeoutSeconds: 30` | `handler.test.ts`(시험이 넘긴 `AbortController`를 `abort()` — 6.8.2) |

`// 계약 v2.3 7.2.11 원문` (발췌: 서버 함수 주소를 앱에 넘기는 값 — SYNC는 읽기만. v2.0과 같음)

```dart
@immutable final class RecognitionConfig {
  const RecognitionConfig({this.mathEndpoint, this.idTokenProvider});
  final Uri? mathEndpoint;                       // callable URL (emulator in dev); null → manual only
  final Future<String?> Function()? idTokenProvider;   // M4 auth later; null → no Authorization header
}
```

- 이번 라운드에 앱은 `idTokenProvider == null`이라 `Authorization` 헤더 없이 부른다 → 서버는 `unauthenticated`다. 즉 **에뮬레이터 밖에서 실제로 쓰이는 것은 실연결 미니 라운드부터**다(LIBRARY 6.11.2와 같은 판단). 에뮬레이터 시험은 시험이 직접 ID 토큰을 받아 넣는다.

### 5.4 EDITOR · INK · PDF

코드 의존이 없다. 객체·녹음·손글씨의 동기화 의미(객체 단위 LWW, 삭제는 따로, 녹음 이름 따로)는 실연결 뒤 화면에 보이는 결과로만 만난다. EDITOR의 객체 명령 매핑(계약 7.2.3 표)이 어떤 JSON 키를 바꾸는지는 CORE C-11이 정하고, SYNC는 키 단위로 병합할 뿐이다.

### 5.5 동시 개발 중 가짜와 가정 (계약 4.3 SYNC 행 구체화)

(v2.3 — 개발 착수 정리, 계약 7.6.2 마지막 bullet) 기반 단계가 끝나 '가정'이던 CORE 값 타입·JSON은 실제 타입이다: B2-α `2b2e4b0`(계약 표면) → B2-β `9777fde`(T20a JSON 골든)·`c443015`(T20b 기하·`copyTo`)·`38f3578`(T21 값 타입)·`12ab8c4`(T23a 해석기·세션 객체)·`0798096`(T23b 가짜 저장소 v2·`PageObjectFixtures`·`testing_web`), 모두 `main` `5843ec3`(계약 v2.3)에 있다. SYNC R2-B7a(`99b8ead`)가 그 위에서 통과했다. 실제 CORE 저장소의 객체·녹음·손글씨 쓰기(T27·T29~T33)는 아직이라 T16-v2는 기본 skip(6.7.2)이다.

| 의존 | 개발 중 쓰는 것 | 실제와 맞춰 보는 시점 |
|---|---|---|
| CORE 값 타입·JSON(`PageObject`·`HandwritingText`·`Recording.title`·`EntityJson.decode`) | **실제 타입**(R2-B2 — B2-α `2b2e4b0` + B2-β `9777fde`~`0798096`, 위 문단) | 끝남 — R2-B7a가 T20a 위에서 확인(I-1) |
| CORE 로컬 저장소(SyncStore·AssetStore) | 자기 `FakeLocalStore` v2(6.5) — 1차처럼 CORE 동작 계약(02-core 5.6·6.13·6.14)을 흉내 | 통합 3단계: 계약 스위트를 실제 CORE에(`core_sync_store_contract_test`) |
| 실제 CORE v2 | `openTestNoteStore` — (v2.1 정정, SYNC-M6) 파일·경우마다 기다리는 CORE 이정표가 다르다: 객체 O1~O4는 T27, 손글씨 H1~H4는 T32·T33b, 녹음 R1·R2·C-31은 T30, 복사가 드는 O5·U2는 T29, C-30 뒷문장은 T31·T33a(6.7.2 선행 작업 표). 개발 중 CORE 커밋을 **읽기만** | 각 이정표 뒤 로컬 1회, 판정은 통합 3단계 T16-v2 |
| 서버 | 1차 `FakeSyncServer`(+ `mergedState` v2), `commitRaw`로 모르는 `kind` 청크 | — |
| 앱 갱신 | `TestDevice(knownKinds:)` + `SyncTestHarness.restart`(6.3.8) | — |
| Firebase(함수) | 단위 시험: 가짜 의존(`HandlerDeps`), 엔진 어댑터: 가짜 `fetch`·가짜 SDK 클라이언트. 에뮬레이터: Functions·Auth(`demo-noteapp`) | V13 |
| LIBRARY 클라이언트 | SYNC 에뮬레이터 시험은 Node `fetch`로 같은 규약을 부른다(Dart 클라이언트와 독립) | CI `functions` 잡에서 두 시험이 같은 에뮬레이터 실행 안에서 |

### 5.6 다른 영역 요청에 대한 답

| 요청 | 출처 | 답 |
|---|---|---|
| R-6 `functions/package.json`에 `firebase-tools`·스크립트, `--config ../app/firebase.json` | 01-infra 5.9 | 받아들임(3.4, RQ-4) |
| Q4 에뮬레이터 소유자 UID `owner-uid`·남 `stranger-uid`, Auth 에뮬레이터로 사용자 만들기 | 05-library 12.2 | 받아들임. 규약은 6.8.11(관리 REST `Authorization: Bearer owner` + `localId` 지정 → `accounts:signInWithPassword`) [확인] |
| CP-L8 `strokes.t` 기준·좌표 정밀도 주석 | 05-library 12.1 | 지지 — (v2.1) 계약 7.2.13 `in` 주석이 되었다(C21-17) |
| CP-L9 설정 키 `recog.*` 목록 | 05-library 12.1 | 영향 없음 — 설정은 1차 `setting` 종류(키 문자열)라 SYNC 매핑이 바뀌지 않는다 |
| CORE CP-4(`UnknownObject(Map rawJson)` 생성자·메타 키 규칙) | 02-core 12.1 | 지지 — SYNC 시험이 `UnknownObject` JSON을 만들 수 있어야 한다(지금은 `putRawObject`로 JSON만 쓰면 되므로 막히지는 않음) |
| CORE CP-6(알려진 `type`의 모르는 enum 값 → `UnknownObject`) | 02-core 12.1 | 지지 — 옛 앱이 고쳐 쓰며 값을 잃지 않는다. SYNC 병합은 그대로(키 단위) |
| CORE CP-7(`Recording.toJson`의 `title` 항상) | 02-core 12.1 | 지지(5.1.2) — (v2.1) CP-4·CP-6·CP-7 모두 계약 문장이 되었다(C21-06·C21-08) |
| (v2.1) R-10 `scripts/emulator_suite.sh`는 `dart run tool/ws.dart with-heavy-lock -- …`로 감싸고 안쪽 Dart 시험은 `NOTEAPP_HEAVY_LOCK_HELD`를 받는다 | 01-infra 5.9 | 받아들임(6.8.11 스크립트, 5.2 RQ-5·RQ-8) |
| (v2.1) LIBRARY-M11 수식 고정 자료 내보내기(6.9.1 형식)는 수식 패드의 P-C 개발자 동작 | 05-library 6.14.7 L2-22 | 받아들임 — 6.9.1 형식이 그 출력의 계약이다. 형식을 바꿀 때는 LIBRARY에 알린다(Q4 닫힘) |
| (v2.1) CORE: R2-B7a 바탕 = B2-α(T22) 해시, 키 대조 = T20a 해시, T16-v2 이정표 T24·T26~T33 | 02-core 8.1·8.5 | 받아들임(6.4, 6.7.2 선행 작업 표, 8.1) |

---
## 6. 설계 상세

1차 07-sync 6장의 구조(시계·병합·원격 구조·업로드·수신·충돌 규칙·에셋·로그인·압축)는 그대로다. 아래는 바뀌거나 새로 생기는 것만 적고, 이어받는 1차 절을 밝힌다.

### 6.1 전체 그림 — 2차에서 바뀌는 곳

```text
CORE (outbox: pageObject / handwriting 힌트 noteId·pageId 항상)
  └─ UploadPipeline (1차 6.5) ── SyncScopes.scopeOf ◀ 6.2.3 (새 종류 범위)
        │   onScopesCommitted ◀ (v2.1) 손글씨만 실린 청크의 범위는 뺌 → PurgeGuard '최근 보냄' (6.2.5)
        └─ ChunkPacker ◀ kindOrder + pageObject, handwriting (6.2.3)
              └─ ChunkCodec.encode (fmt 1 그대로, blobKeys 그대로)
                         ⇅ FakeSyncServer / Firestore (변경 없음 — 문서 필드에 엔티티 종류 없음)
DownloadPipeline._apply (1차 6.6.3)
  2–3. 자기 청크·형식·디코드 ◀ decodeTolerant: 모르는 kind → HeldRecords (6.3)
  4.   영구 삭제 보기 (1차)
  5.   RecordGate ◀ _purged: pageObject(범위·lib 범위 요소), handwriting(json noteId) (6.2.4)
       FieldMerge  ◀ FieldUnits v2: 객체·손글씨 '한 단위', 녹음 title (6.2.2)
  6.   PurgeGuard ◀ 보내지 않은 객체 편집도 편집 (6.2.5)
  7–8. applyRemote (CORE) → afterGroup: 폴더 순환 + PageResurrection ◀ 새 객체도 근거 (6.2.6)
attach (1차 6.10.3): PurgedSet.load → DownloadPipeline.load ◀ 되감기 표시·깨진 값 (6.3.5)
                   → reapplyHeldRecords ◀ 새 (6.3.4 — LRU 밖, K1은 보관에 ra) → catchUp
                   → releaseHeld ◀ (v2.1) ra가 된 보관 기록도 (6.3.4) → live
Compactor (1차 6.13) ◀ 모르는 종류 청크는 남김 (6.3.6)
```

### 6.2 새 종류 매핑 (1차 6.3·6.4.3·6.3.5·6.7.3·6.7.4 확장)

#### 6.2.1 키 표 (`FieldUnits.keysOf`)

CORE 6.3 키 표(02-core 6.3, 계약 7.2.7)와 대조했다. T16 'JSON 키 대조' v2(`integration/core_json_keys_test.dart`)가 CORE 골든과 다시 대조한다.

| 종류 | 키 (메타 키 포함) |
|---|---|
| `pageObject` | `id`, `pageId`, `type`, `frame`, `shape`, `geometry`, `style`, `text`, `assetId`, `px`, `latex`, `engine`, `createdAt`, `updatedAt`, `deletedAt`, `version` — **알려진 4종의 합집합** |
| `pageObject` · `type: shape` | 공통 8개(`id`·`pageId`·`type`·`frame`·`createdAt`·`updatedAt`·`deletedAt`·`version`) + `shape`·`geometry`·`style` |
| `pageObject` · `type: text` | 공통 8개 + `text`·`style` |
| `pageObject` · `type: image` | 공통 8개 + `assetId`·`px` |
| `pageObject` · `type: math` | 공통 8개 + `latex`·`style`·`engine`((v2.1, C21-11) 항상 씀 — 없으면 null. `kPageObjectTypeKeys['math']`에 고정으로 든다 — 계약 7.2.7) |
| `handwriting` | `id`, `noteId`, `pageId`, `engineId`, `sourceRev`, `lines`, `createdAt`, `updatedAt`, `deletedAt`, `version` |
| `recording` | v1.4(`id`·`noteId`·`assetId`·`durationMs`·`startedAt`·`createdAt`·`updatedAt`·`deletedAt`·`version`) + `title` |

- `style`은 `shape`·`text`·`math`가 같은 이름의 키를 쓰지만 안의 모양이 다르다(`ShapeStyle`·`TextBoxStyle`·`MathStyle`). `type`은 바뀌지 않으므로(CORE `UpdateObjects`가 막음) 같은 객체의 두 스냅숏에서 `style`의 모양이 섞이지 않는다.
- 메타 키(`FieldUnits.metaKeys` = `id`·`key`·`version`·`createdAt`·`updatedAt`)는 1차 그대로다. CORE는 `pageId`·`type`도 필드 버전을 찍지 않는 키로 다룬다(02-core 6.3 '필드 버전 키 = JSON 키 − 메타 키(id·pageId·type·…)') — 바뀌지 않는 키라 SYNC 쪽에서 단위에 들어 있어도 병합 결과는 같다(그 키의 버전은 언제나 base).

#### 6.2.2 병합 단위 — '객체 단위 하나'의 구현 (CP-S1)

규칙:

| 종류 | 한 단위 (`wholeUnitExcept`의 나머지) | 따로 단위 (각자 하나) |
|---|---|---|
| `pageObject` | 두 스냅숏에 있는 키 − 메타 키 − {`pageId`, `deletedAt`, `engine`} — 알려진 키로는 `{type, frame, shape, geometry, style, text, assetId, px, latex}`, **모르는 키도 여기에 든다** | `pageId`, `deletedAt`, `engine` |
| `handwriting` | 두 스냅숏에 있는 키 − 메타 키 − {`noteId`, `pageId`, `deletedAt`} — 알려진 키로는 `{engineId, sourceRev, lines}` | `noteId`, `pageId`, `deletedAt` |
| `recording` | (묶음 없음 — 1차 그대로 모든 키가 각자 단위) | `title` 포함 전부 |

구현: `FieldUnits.unitsFor(kind, keys)`가 `wholeUnitExcept(kind) != null`이면 위 규칙으로 단위를 만든다. `FieldMerge.mergeRecords`(1차 T4)는 손대지 않는다 — 단위를 `unitsFor`에서 받기 때문이다(1차 T4 결정 ①: 단위 계산의 키 = `keysOf(kind)` ∪ 두 JSON 키 ∪ 두 overrides 키). 교환·결합·멱등 성질 시험(1차 `field_merge_properties_test`)에 새 두 종류를 생성기로 넣는다(모르는 키를 섞은 스냅숏 포함).

**왜 '나머지 전부'인가 — 판이 섞인 기기의 반례.** 계약 문장을 '목록에 없는 키는 1차 기본 규칙대로 각자 단위'로 읽으면, 다음 라운드에 새 앱이 객체에 키 `K`를 더했을 때 옛 앱과 새 앱이 서로 다른 단위로 병합한다.

| 단계 | 새 앱 A | 새 앱 B | 옛 앱 C (K를 모름) |
|---|---|---|---|
| 1 | 같은 객체를 오프라인에서 이동(`frame`, HLC t1) | 같은 객체의 `K`를 바꿈(t2 > t1) | 둘 다 받는다 |
| 2 · 단위(새 앱이 K를 객체 단위에 넣은 경우) | 객체 단위: A 쪽 최대 t1 vs B 쪽 t2 → **B 이김** → `frame` = 옛 값 | 같음 | 목록 규칙이면 `{…, frame}` 단위 A(t1) 이김 → `frame` = **A 값**, `{K}` 단위 B 이김 |
| 결과 | A·B: 이동이 사라짐 | | C: 이동이 남음 → **A·B와 C가 영구히 다름** |

'나머지 전부' 규칙이면 C도 K를 객체 단위에 넣어 B가 이기므로 셋이 같다(C의 CORE가 K를 저장하지 못하는 것은 표현의 문제이고, 알려진 키의 값은 같다). 그래서:

- **이후 라운드 규칙**(CP-S1에 포함): `pageObject`·`handwriting`에 키를 더할 때 따로 단위를 새로 만들지 않는다. 새 키는 언제나 '한 단위'에 든다. 따로 단위가 꼭 필요하면 새 `EntityKind`나 `fmt` 판단으로 다룬다.
- 옛 앱이 그 객체를 고쳐 올리면 그 스냅숏에는 `K`가 없고, 단위 승자가 옛 앱이면 `K`는 사라진다(객체 단위 LWW의 정의대로 — '나중 것이 객체째 이긴다'). 모르는 `type` 전체(`UnknownObject`)는 옛 앱이 고칠 수 없어 이 일이 없다(C-12). 알려진 `type`의 모르는 enum 값도 CORE가 `UnknownObject`로 읽어 막는다(02-core CP-6).

사용자 동작별 결과(EDITOR 명령 매핑 — 계약 7.2.3 표 → CORE C-11이 바꾸는 키 → SYNC 단위):

| 동작 (명령) | 바뀌는 키 [CORE C-11] | 단위 | 두 기기가 같은 객체에 동시에 하면 |
|---|---|---|---|
| 선택 이동·비율 유지 크기·회전 (`TransformElements`) | `frame`(+ 도형 `geometry`, 수식은 `style.fontSizePt`) | 객체 | 나중 HLC가 객체째 이김 |
| 핸들 크기·꼭짓점·스타일 (`UpdateObjects`) | 바뀐 키만(`geometry`·`frame`·`style`) | 객체 | 같음 |
| 텍스트 편집 세션 (`UpdateObjects`) | `text`, `frame`(높이) | 객체 | 같음 — 높이와 글이 어긋나지 않는다(계약 D3의 이유) |
| 선택 색 변경 (`CompositeCommand([RestyleStrokes, UpdateObjects])`) | 객체 `style` | 객체 | 같음 |
| 삭제·잘라내기 (`RemoveElements`) | `deletedAt` | 따로 | 한쪽 삭제 + 다른 쪽 수정 → **삭제되고 수정값도 남음**(1차 S05와 같은 모양 — 되살리면 수정값이 보임) |
| 수식 다시 인식 (`UpdateObjects`) | `latex`, `engine`, (크기 바뀌면 `frame`) | 객체 + `engine` | `latex`는 객체 단위로, 출처 `engine`은 따로 — 출처가 LaTeX와 어긋날 수 있으나 표시용 정보라 받아들인다(계약 원문 '따로 `{engine}`') |
| 손글씨 결과 쓰기 (`HandwritingRepository.put`) | `lines`·`sourceRev`·`engineId` | 손글씨 | 나중 HLC가 결과째 이김 — 색인기는 `sourceRev`가 지금 획과 다르면 다시 인식한다(02-core 6.9) |
| 녹음 이름 (`renameRecording`) | `title` | 따로 | 나중 이름이 이김. 이름 + 삭제 → 삭제되고 이름도 남음 |

- (동시 개발 S2-8, 무작위 수렴 v2가 찾음) **한 단위 종류의 메타 키 `createdAt`은 이기는 단위를 따라간다** — 한 단위의 승자 스냅숏이 `createdAt`을 주고, 두 단위 상태가 같을 때만 1차 규칙(작은 값)이다. 손글씨 결과 id는 언제나 `hw_<pageId>`라 두 기기가 같은 id를 각자의 `createdAt`으로 만들 수 있다. 1차 규칙(작은 값)이면 승자 스냅숏을 통째로 받은 기기(`TakeRemote`)·자기 행을 지킨 기기(`KeepLocal`)가 병합 값과 다르고, 진 쪽의 작은 값은 아무도 올리지 않아 서버 병합 상태와 기기가 영구히 갈린다. 승자를 따르면 `KeepLocal`·`TakeRemote` 결정이 그대로 병합 값이다(교환·결합·멱등 — 단위 비교가 전순서). 객체는 id가 겹치지 않아 실제로는 차이가 없다. 시험: `field_merge_test` '(S2-8)' 두 행, `sync_merge_policy_test` '(2nd round, S2-8)', `fuzz_convergence_test`.

#### 6.2.3 청크 범위 · 정렬 · 코덱 (1차 6.4.3·6.4.4)

| 종류 | `SyncScopes.scopeOf` | 근거 |
|---|---|---|
| `pageObject` | `noteIdHint ?? 'lib'` — 힌트는 outbox `noteId`(항상, 고아면 `''` → `UploadPipeline._hint`가 null로 바꿔 'lib') | 획과 같다(JSON에 `noteId`가 없음) |
| `handwriting` | `json['noteId'] ?? noteIdHint ?? 'lib'` | (v2.1 정정 — 검토 S-12) **페이지와 같다**(1차 `page` = `noteIdKey ?? noteIdHint ?? 'lib'`, `scopes.dart` 25). 1차 `recording`은 `noteIdHint ?? noteIdKey` 순서라 다르다. JSON에 `noteId`가 있어 고아가 생기지 않는다(02-core 6.13) |

- `ChunkPacker.kindOrder` = 계약 7.2.8 순서(`…, stroke, pageObject, handwriting`). 같은 범위 안에서 페이지·획 뒤에 객체가 오므로, 한 청크에 페이지와 그 객체가 함께 실리면 받는 쪽은 페이지를 먼저 디코드한다(정확성은 순서와 무관 — 적용은 한 `applyRemote` 호출 묶음 안의 병합 결과다. 순서는 결정성과 골든을 위해 고정한다).
- `ChunkCodec.blobKeys`는 그대로(`stroke: ['points']`). 새 종류는 JSON 헤더만이다. 텍스트 상자 글(≤ 10,000자 ≈ 30 KB UTF-8)·손글씨 줄(페이지당 수십 줄 × 후보 ≤ 5)·`UnknownObject` 원본도 기록 하나가 헤더 상한 1,000,000 B(1차 6.4.4) 안이다. 넘으면 1차 규칙대로 그 기록만 `entityTooLarge` 격리.
- 코덱 형식 `fmt`는 1 그대로(계약). 새 골든 `test/goldens/chunk_v1_kinds_golden.bin`은 범위 하나에 페이지 1 + 도형 객체 1 + 텍스트 상자 1 + 손글씨 1 + 이름 있는 녹음 1 + 모르는 kind(`bookmark`) upsert 1을 담은 청크다. 1차 골든처럼 Dart 인코더와 **따로** 만든 바이트(`test/goldens/make_chunk_kinds_golden.py`, `python3 -I`로 한 번 실행 — 시험 실행에는 쓰지 않음)와 같음을 확인하고, `decodeTolerant`가 모르는 기록 1개 + 알려진 기록 5개를 돌려주는지 본다(VM·Chrome 공용 본문 `test/shared/chunk_kinds_cases.dart`).

#### 6.2.4 게이트 — 영구 삭제된 노트의 하위 기록 (1차 6.3.5)

`RecordGate._purged`(`merge/record_gate.dart` 132–155)에 두 줄을 더한다:

| 종류 | 노트를 찾는 방법 | 그 노트가 영구 삭제 보기에 있으면 |
|---|---|---|
| `page`·`recording` | `json['noteId']` (1차) | 버림(로그만) |
| `stroke` | 청크 범위, 'lib' 범위면 파이프라인이 찾은 노트(1차) | 버림 |
| **`pageObject`** | 청크 범위, 'lib' 범위면 파이프라인이 찾은 노트(6.2.7) — 획과 같음 | 버림 |
| **`handwriting`** | `json['noteId']` | 버림 |

- (v2.1 정정 — 계약 7.2.8 '노트 영구 삭제 때 함께', 검토 C-2) 영구 삭제 기록은 folder·note뿐이다(`record_gate.dart` 83, `chunk_codec.dart` `_purge`). 페이지는 소프트 삭제(`deletedAt`)만 있으므로 하위 기록 게이트는 **노트 단위**이고, 페이지 삭제는 그 페이지의 객체·손글씨 행을 건드리지 않는다(되살림 판단만 — 6.2.6).
- 1차 '좁은 틈'(보기가 새로 고쳐지기 전에 통과한 기록이 남기는 고아 행은 무해 — 1차 6.7.4, SYNC-3-3)은 새 종류에도 같다. CORE는 영구 삭제된 노트의 페이지가 다시 오지 않으므로 그 객체·손글씨 행이 화면에 나오지 않는다.
- `hasOwner` 판정(1차 — folder·note·penPreset·asset만 `ownerId`)은 그대로다. 객체·손글씨에는 소유자 열이 없다(노트를 따름 — 02-core 6.13).
- 게이트 인자 이름 `strokeNoteId` → `elementNoteId`(내부 — 시험 호출부만 바뀜).

#### 6.2.5 영구 삭제 보호 (`PurgeGuard`, 1차 6.7.4)

`PurgeGuard.guard`(`merge/purge_guard.dart` 59–89)는 영구 삭제되는 노트가 '이 기기에서 편집 중'이면 복구 사본을 만든다. 편집 중 = ① 최근 10분(`purgeGuardWindow`) 안에 그 노트 범위로 올린 기록이 있음(`_sent` — `scopesSent` 39–46) 또는 ② outbox에 그 노트의 보내지 않은 편집이 있음(`_editedInOutbox` 93–117). (v2.1) **손글씨 결과는 ①·② 어디서도 편집이 아니다**(계약 7.2.8 `handwriting` 행, D-S11).

② outbox 판정 — '편집으로 보는 outbox 항목'에 `pageObject`를 더한다:

```text
case page | stroke | recording | pageObject:   // (v2.0) pageObject — the note's user content
  if e.noteId ∈ purgedNotes → that note is being edited
case note: (v1.4 — non-trash fields)
handwriting: NOT an edit (derived data — re-recognized from the copied strokes; CORE copyNote
             also copies the result, 02-core 6.14.1 step 4) — v1.4 `default:` branch, no code
```

① 최근 보냄 — (v2.1, 검토 M-3 — 1차 T11 결정 ① 변경, 총괄 승인 CD2-12) `UploadPipeline`의 커밋 성공 처리(`upload_pipeline.dart` 363)가 넘기는 범위에서 **`handwriting` 기록만 실린 청크**를 뺀다:

```text
// 1차: p.onScopesCommitted({for (final c in group) c.write.scope});
p.onScopesCommitted({
  for (final c in group)
    if (!c.items.every((i) => i.record.ref.kind == EntityKind.handwriting)) c.write.scope,
});
```

- 판정은 커밋 그룹 청크의 실린 기록 종류(`PackItem.record.ref.kind`)로 한다. 같은 청크에 획·객체 등 다른 기록이 하나라도 있으면 그 범위는 1차처럼 센다(사용자 편집이 섞였다). 손글씨 결과는 `kindOrder`의 맨 뒤라 한 범위의 기록이 많으면 손글씨만 든 꼬리 청크가 생길 수 있는데, 그 청크만 빠진다.
- 왜: 주 기기는 iPad Safari(ML Kit 없음)이고 손글씨 결과는 안드로이드가 만든다(계약 D7). LIBRARY 색인기는 원격으로 받은 획의 페이지도 낡은 페이지로 보고 인식한다(02-core `stalePages` '원격 획 변경 뒤', G-2 '입력 3초 뒤'). 1차 규칙이면 iPad에서 쓴 노트를 안드로이드가 몇 분 안에 인식해 `hw_<pageId>`를 올리고, 그 10분 안에 사용자가 iPad에서 노트를 지우고 휴지통을 비우면 안드로이드가 '(복구됨)' 사본을 만들어 iPad로 되돌려 보낸다 — 사용자가 일부러 지운 노트가 돌아온다. 안드로이드 쪽 사용자는 그 노트를 건드리지 않았다. '손글씨는 파생 데이터라 편집이 아니다'(②)와 '최근에 올린 손글씨는 편집이다'(①)가 한 기능 안에서 다르던 것도 같이 없어진다.
- 잃는 것: 손글씨만 올린 기기에서 노트가 영구 삭제되면 그 기기의 손글씨 결과도 함께 사라진다. 파생 데이터라 원본 획에서 다시 만들 수 있고, 원본 노트는 사용자가 지운 것이다.
- 복구 사본은 CORE `duplicateNoteForRecovery`(= `copyNote`)가 만든다 — 녹음·객체·손글씨 결과까지 복사한다(02-core 6.14.1). 가짜 로컬 저장소도 같은 순서로 복사한다(6.5).
- 시험: `merge/purge_guard_test.dart` — '손글씨만 최근에 올림(`scopesSent` 없음 — 업로드가 범위를 넘기지 않음) → 사본 없음', 대조 '획을 최근에 올림 → 사본 있음', 'outbox에 손글씨 항목만 → 사본 없음', 'outbox에 객체 항목 → 사본 있음'. `engine/upload_pipeline_test.dart` — '손글씨만 든 커밋 → `onScopesCommitted`에 그 범위 없음', '획 + 손글씨가 한 청크 → 범위 있음', '손글씨 꼬리 청크와 획 청크가 한 그룹 → 범위 있음(획 청크 몫)'. 시나리오 S28은 가상 시간을 10분 안에 두어 이 규칙을 실제 경로로 확인한다(6.7.1).

#### 6.2.6 페이지 되살림 (`PageResurrection`, 1차 6.7.3)

1차 규칙 '삭제된 페이지에 상대가 모르는 획이 있으면 페이지를 되살린다'에 객체를 더한다:

| 쪽 | 1차 (획) | 2차 추가 |
|---|---|---|
| (a) 지운 쪽 — 이 기기가 지운 페이지(`deletedAt` 버전 노드 = 이 기기) | 이번 적용 묶음에서 `created`된 활성 **획**이 그 페이지에 있음 | `created`된 활성 **`pageObject`**도 근거 |
| (b) 쓴 쪽 — 다른 기기가 지운 페이지를 받음(`taken`·`merged`) | outbox에 그 페이지의 보내지 않은 획 생성(`'*'`)이 있음 | 보내지 않은 **`pageObject` 생성**(`'*'`, `pageId` 힌트 — 항상)도 근거 |
| 근거 아님 | 기존 획의 수정·삭제 | 기존 객체의 수정(`UpdateObjects`·`TransformElements`)·삭제, **손글씨 결과**(생성·수정 모두 — 파생 데이터), 녹음 |

- 되살림 쓰기는 1차 그대로 `{deletedAt}` 단위 하나(`commitRepairs`), 알림 `PageRestored`.
- 노트 행이 없는 고아 페이지는 (a)·(b) 모두 되살리지 않는다(1차 SYNC-3-3).

#### 6.2.7 lib 범위 요소의 노트 찾기 (1차 6.3.5 'lib 범위 획')

`DownloadPipeline._libStrokeNotes`(716–747)를 `_libElementNotes`로 넓힌다: 'lib' 범위로 온 `stroke`**와 `pageObject`**의 `pageId` → 같은 묶음의 페이지 기록 → 로컬 페이지 행(`readVersioned`) 순으로 노트를 찾아 게이트에 넘긴다. 페이지를 모르면 버리지 않는다(고아로 저장 — 1차와 같음). 'lib' 범위 객체는 보내는 쪽에서 페이지 행이 없었을 때만 생긴다(CORE 원격 고아 객체가 같은 기기에서 다시 올라가는 드문 경우).

#### 6.2.8 모르는 `type`의 객체 (`UnknownObject`, C-12)

- SYNC에는 일반 `pageObject` 기록이다. 병합은 키 단위이고 모르는 키는 객체 단위에 든다(6.2.2) — 다른 기기가 고치지 않는 한(고칠 수 없음 — 선택·삭제·통째 복사만) 원본 키가 그대로 남는다.
- 이 앱에서 할 수 있는 변경은 삭제(`deletedAt` — 따로 단위)와 복사(새 id)뿐이다. 삭제 기록의 스냅숏도 원본 키를 모두 싣는다(CORE가 `rawJson`을 그대로 쓰고 `deletedAt`·`updatedAt`·`version`만 바꿈 — 02-core CP-4).
- 압축 스냅숏·`FakeSyncServer.mergedState`·`canonicalDump`는 JSON을 그대로 다루므로 따로 할 일이 없다. 시험(S26, `core_unknown_type_test`)은 서버 병합 상태의 JSON 키 집합이 처음 쓴 원본과 같음을 본다.

#### 6.2.9 녹음 이름 · 녹음 에셋 · 이미지 에셋 (1차 6.9)

- `Recording.title`은 녹음의 따로 단위다(녹음은 묶음이 없음 — 1차 6.3.1 표의 '—'). `keysOf(recording)`에 `title`만 더한다.
- 녹음 파일·이미지는 1차 에셋 파이프라인(내용 해시 id, `storagePath` 'null 아닌 값이 이김', 업로드 상한 300 MiB, 요청 시 내려받기) 그대로다. 이미지 객체의 `assetId`, 이미지 페이지 배경의 에셋 참조는 일반 JSON 키다. 화면 쪽 `ensureLocal` 요청(INK 이미지 캐시·media 재생)은 1차 `SyncRemoteAssetFetcher` 경로이고 실연결 뒤에 동작한다.
- 녹음 초안(`recording_drafts`)·검색 색인(`search_*`)은 CORE가 outbox에 넣지 않는다 — 계약 스위트 C-30이 '초안·색인을 만든 뒤 `pendingChanges`에 그 종류가 없음'을 실제 CORE로 본다.

### 6.3 모르는 종류 보류 (S-13 — 1차 6.6.3·6.6.5 확장)

#### 6.3.1 관용 디코드 (`ChunkCodec.decodeTolerant`)

1차 `decode`는 헤더 `k`가 `EntityKind` 이름이 아니면 `FormatException('chunk: unknown kind')`을 던지고(`codec/chunk_codec.dart` 201–206), 파이프라인은 그 청크 전체를 `malformedRemoteData`로 건너뛴다(`download_pipeline.dart` 426–428) [확인]. 같이 실린 획까지 잃고 되돌릴 수 없다(조사 01 3.11). 2차의 관용 디코드는 '형식은 맞는데 종류만 모르는' 기록만 따로 꺼낸다.

| 입력 | `decode` (1차, 그대로) | `decodeTolerant` (2차) |
|---|---|---|
| 알려진 종류의 올바른 upsert·purge | 기록 | 기록 |
| upsert 헤더 `k`가 문자열이고 모르는 이름, `id`가 문자열, `e`·`fv`가 객체 | `FormatException`(청크 전체) | `UnknownKindRecord`(바이트 = 그 기록의 `op`부터 이진 필드 끝까지) |
| purge 헤더 `k`가 모르는 이름, `id`·`h`가 문자열 | `FormatException` | `UnknownKindRecord`(op 0x02) |
| purge 헤더 `k`가 **알려진** 종류인데 folder·note가 아님 | `FormatException` | `FormatException`(1차와 같음 — 형식 오류) |
| 헤더가 JSON 객체가 아님, `k`가 문자열이 아님, 길이·varuint·꼬리 바이트 오류, 모르는 `op` | `FormatException` | `FormatException`(청크 전체 — 1차와 같음) |
| 알려진 종류인데 엔티티 디코드 실패(`EntityJson.decode`) | 기록(게이트가 `malformedRemoteData`로 건너뜀 — 1차) | 같음 |
| `fmt` 2 이상 | 파이프라인이 디코드 전에 미룸(1차 6.6.5) | 같음 |

- 모르는 기록의 이진 필드(`blobCount` ≤ 4)도 바이트에 그대로 남는다 — 새 종류가 이진 필드를 쓰더라도 앱 갱신 뒤 다시 디코드할 수 있다(계약의 `rawJson`만으로는 잃는 부분 — CP-S2).
- `isKnownKind`의 기본은 `EntityKind.values`의 이름이다. 시험은 `{…} − handwriting` 같은 집합을 넘겨 '옛 앱'을 만든다(6.3.8).
- 비용: 알려진 종류만 든 청크에서 `decodeTolerant`는 `decode`와 같은 일을 한다(종류 조회 하나만 다름). 성능 목표 6.12.

#### 6.3.2 보관 형식 (`sync.heldRecords` — 머리 + 조각 9개)

메타 KV 규칙(1차 6.6.6: 키는 `sync.`로 시작, 값 < 256 KiB, 쓰기는 마지막 적용 호출의 `metaUpdates`와 같은 트랜잭션, `writeMeta`는 키를 지울 수 없어 `''` = 없음)을 따른다. (v2.1, 계약 7.2.8 ③ — 검토 S-3) 값 하나에 다 넣지 않고 **키 10개**로 나눈다(1차 `sync.purged.0`~`.4`가 이미 여러 키를 쓴다 — `meta_keys.dart` 12).

```json
// sync.heldRecords (head)
{"v": 2, "n": <parts in use 0..9>, "e": <earliest stored serverTimeMicros or null>,
 "a": ["<kind names known by the app that wrote this value>"],
 "o": {"f": <earliest serverTimeMicros>, "k": ["<kindName>" | "*", ...], "a": [...] | null} | null}
// sync.heldRecords.1 … .9 (parts; '' when unused)
{"v": 2, "p": <part index 1..9>,
 "r": [{"c": "<chunkId>", "s": <serverTimeMicros>, "sc": "<scope>", "by": "<authorNode>",
        "i": <index>, "k": "<kindName>", "op": 1, "id": "<id>", "fv": "<fv canonical JSON>",
        "ra": <releaseAtMillis — only for a re-applied record held by K1>,
        "b": "<base64 of the record bytes>"}]}
```

- `r`는 (`s`, `c`, `i`) 순으로 정렬해 조각 1부터 차례로 채운다(결정적 — `encode()`는 정렬된 정규 JSON). 한 청크의 기록이 두 조각에 걸칠 수 있다 — 모든 키를 한 트랜잭션으로 쓰므로 문제없다. 기록 **하나**(`r`의 항목 하나)는 조각 사이로 나뉘지 않는다 — 다음 항목이 지금 조각에 들어가지 않으면 다음 조각에서 시작한다.
- 상한: 조각 하나의 인코딩 길이(UTF-8) ≤ `maxPartBytes`(224 KiB — base64 확장 4/3과 JSON 테두리를 넣고도 값 규칙 256 KiB 미만), 머리 + 조각 전체 ≤ `maxTotalBytes`(2 MiB). 기록 하나가 조각 하나보다 크면(헤더 상한 1,000,000 B — 1차 6.4.4) 그 청크는 언제나 표시로 간다. (수정 2회차, 재검토 항목 2) **기본값에서 실제 한도는 조각 9개 × 224 KiB = 2,016 KiB(2,064,384 B)이고 `maxTotalBytes`(2,097,152 B)는 걸리지 않는다** — 둘의 차이 32 KiB보다 머리(판·조각 수·종류 이름 몇 개·표시 — 수백 B)가 훨씬 작기 때문이다. 그래서 보관 개수는 조각별 채움으로 정해진다: 같은 크기 항목(인코딩 길이 `e`)이면 조각 하나에 `⌊(maxPartBytes − w + 1) / (e + 1)⌋`개(`w` = 빈 조각 테두리 `{"p":1,"r":[],"v":2}` 20 B, 항목 사이 쉼표 1 B), 전체 `maxParts` × 그 값이다. `maxTotalBytes`는 계약 ③의 '총 상한'을 지키는 안전장치이고, 시험이 작게 줄여(S27 (c)) 전부/전무 갈래를 작은 기록으로 시험할 때 걸린다.
- 중복 제거 키 = (`k`, `id`, `fv`). 같은 기록이 겹침 재수신(커서 − 5분)·LRU 밖 재수신·K2 재수신·다른 기기의 압축 스냅숏으로 다시 와도 한 번만 남는다. `fv`가 다르면(같은 엔티티의 다른 판) 따로 남긴다 — 다시 적용할 때 병합이 정리한다.
- `serverTime`은 µs 정수다. 2^53 미만이라 웹(dart2js) JSON에서도 정확하다(1차 `ServerCursor.parse`의 상한 규칙과 같음).
- **청크 단위 전부 또는 전무**(v2.1, 계약 7.2.8 ② — 검토 M-1): `add(chunk, records)`는 그 청크의 모르는 기록 전부(새 기록 + 같은 청크 id로 이미 저장된 기록)를 넣은 결과가 두 상한 안일 때만 저장한다. 하나라도 넘치면 그 청크의 기록은 **하나도 저장하지 않고**(이미 저장된 같은 청크 기록도 뺀다) **되감기 표시** `o`만 갱신한다 — `f` = min(`f`, 그 청크 `serverTime`), `k` ∪= 그 청크의 종류. 그러면 앱 갱신 뒤 되감기로 그 청크를 통째로 다시 받는 것만으로 충분하고, '저장분 + 표시분'으로 갈린 청크가 생기지 않는다(6.3.4·6.3.5에서 왜 위험한지).
- 표시가 덮는 청크: `o`가 있고 그 청크의 `serverTime` ≥ `o.f`이며 종류가 모두 `o.k`에 있으면(또는 `'*'` ∈ `o.k`) 저장하지 않는다 — 되감기가 그 시각 뒤를 전부 다시 받으므로 저장은 자리만 쓴다. 새로 표시에 오른 기록 수만 센다.
- 보관 개수 기준(6.12, 수정 2회차에서 정정): 손글씨 결과 기록 하나는 `strokeIds`(UUID 36자 × 획 수)·`rect`·후보를 담아 획 300개 페이지면 약 10 KB(엔티티 JSON)다. 보관 항목 하나는 기록 바이트(헤더 JSON = 엔티티 JSON + `fv`·`id`·`k`)의 base64(약 13.5–13.8 KB)에 `c`·`s`·`sc`·`by`·`i`·`k`·`op`·`id`·`fv`를 더해 약 13.8–14.1 KB다 [확인 — 1차 형식(`chunkIdOf` 41자, HLC 37자, `EntityFieldVersions.toJson` `{"b":…}`)으로 만든 모형 항목의 길이, `/tmp/claude-0/plan57-scratch/sync57-r2`]. 위 식으로 조각당 16개(항목 13,491–14,333 B 구간), **전체 약 144개(페이지 약 144쪽)**까지 바이트로 보관하고, 넘는 청크는 표시로 간다. 항목이 13,490 B 이하면 조각당 17개(153개), 14,334 B를 넘으면 15개(135개)다 — 그래서 시험은 숫자를 박지 않고 상수와 잰 항목 길이로 경계를 계산해 단언한다(6.12, S2-6). v2.0 초안의 값 하나(200 KiB)면 같은 식으로 14쪽이었다.
- **깨진 값**(v2.1, 계약 7.2.8 ③): 머리나 조각 하나라도 읽을 수 없으면(JSON 아님, `v` 다름, `n`과 조각 수가 안 맞음, `p` 번호가 다름, base64 오류) 기록을 모두 버리고 **'모든 종류 되감기 표시'** `o = {f: 머리의 e(머리도 깨졌으면 0), k: ['*'], a: 머리의 a(머리가 깨졌으면 null)}`로 바꿔, `load()`가 그 값을 곧바로 다시 쓴다(경고 로그). 바이트는 잃지만 원본 청크가 서버에 남아 있거나(압축은 모르는 기록이 든 청크를 지우지 않음 — 6.3.6) 그 상태가 더 새 스냅숏에 들어 있으므로, 되감기로 다시 받으면 같은 상태가 된다(비싸지만 잃지 않음). `f = 0`이면 처음부터 다시 받는다(1차 첫 동기화와 같은 쪽 수).
- `a`(그 값을 쓴 앱이 아는 종류 이름)는 `'*'` 표시가 언제 되감을지 정하는 데만 쓴다(6.3.5).

#### 6.3.3 받기 흐름 (1차 6.6.3 2–3단계 변경)

```text
for each fresh chunk c (own delta skipped, fmt > codecFormat deferred — v1.4):
  try:
    d = ChunkCodec.decodeTolerant(c.payload, isKnownKind: knownKinds)
  on FormatException: issue(malformedRemoteData) ; continue            // v1.4
  decoded += (c, d.records)                                            // known records → steps 4–8
  if d.unknown not empty:
    newly += held.add(c, d.unknown)          // dedup; the whole chunk is stored or only marked
if newly > 0: issue(needsAppUpdate, '<n> record(s) of kind <k…> held until the app is updated')
meta += the sync.heldRecords keys whose text changed                  // rides on the last apply call
cursor advances as in v1.4 (the chunk is NOT deferred)
```

- 모르는 기록은 게이트(4·5단계)에 들어가지 않는다 — 모르는 종류의 영구 삭제 관계·소유자 규칙을 알 수 없기 때문이다. 다시 적용할 때 그 판의 게이트를 지난다.
- 같은 청크의 알려진 기록이 K1으로 보류되면 1차대로 청크 id가 `sync.held`에 든다(받기 경로 — 다시 적용 경로의 K1은 6.3.4). K2 해제 때 그 청크를 다시 받아 디코드하면 모르는 기록은 다시 `held.add` → 저장된 청크면 중복 제거, 표시된 청크면 표시가 덮어 그대로(새 문제 없음).
- 메타 쓰기는 1차 원칙(마지막 적용 호출과 한 트랜잭션, 실패하면 메모리 값도 바꾸지 않음 — `keep()`)을 그대로 따른다. 앱이 그 사이에 죽으면 같은 쪽을 다시 받고 같은 결과가 된다(멱등).

#### 6.3.4 다시 적용 (`reapplyHeldRecords` — 앱 갱신 뒤)

시점: 로그인 상태로 연결할 때(1차 6.10.3 attach) `PurgedSet.load()` → `DownloadPipeline.load()` 다음, `catchUp()` **전**(계약 7.2.8 ⑤). 보관분은 커서보다 오래된 기록이라 먼저 적용하고 새 청크를 그 위에 받는다(LWW 정확성은 순서와 무관하지만, 되살림·영구 삭제 보호가 '이번 묶음에서 처음 본 것'을 기준으로 판단하므로 원래 순서에 가깝게 둔다).

```text
reapplyHeldRecords():
  chunks = held.knownChunks(isKnownKind)          // records of kinds known now and without ra;
                                                  // synthetic chunks: original id, scope,
                                                  // serverTime, author; payload = assemble(record
                                                  // bytes); order (serverTime, chunk id, index)
  if chunks is empty: return
  result = _apply(chunks,
                  release: true,                  // no LRU skip, cursor & scope stats unchanged
                  remember: false,                // (v2.1) keep() does NOT put the ids in the LRU
                  releaseHolds: false,            // (v2.0) never release existing sync.held entries
                  reapply: true)                  // (v2.1) K1 → per-record ra, not sync.held
  // gate (purged notes dropped, foreign owner skipped), merge, PurgeGuard, groups, afterGroup — v1.4
  // keep(): held.settle(applied: records that passed the gate (accepted, dropped, skipped),
  //                     heldUntil: K1 records → ra) ; the sync.heldRecords keys ride on the
  //         last apply call (or one writeMeta)
  if result.error: in-memory held unchanged; s.heldReapplied stays false → retried at the
                   session's next connection (records not lost)

releaseHeld():   (v1.4 K2, then)
  due = held.dueChunks(g′)                        // re-applied records whose ra ≤ g′
  if due not empty: _apply(due, reference: g′, release: true, remember: false,
                           releaseHolds: false, reapply: true)   // same settle rules
```

- **`remember: false`가 필요한 이유**(검토 M-1): 1차 `_apply`는 성공한 호출 끝의 `keep()`에서 `fresh`의 모든 청크 id를 세션 LRU(`_applied`)에 넣는다(`download_pipeline.dart` 520–528). `release: true`는 LRU 검사를 건너뛸 뿐 넣기는 그대로다. 합성 청크는 원래 청크 id를 쓰므로, 다시 적용 뒤 `catchUp`이 겹침 재수신(커서 − 5분)이나 되감기로 원래 청크 C를 다시 받으면 `release`가 아닌 받기가 C를 중복으로 버린다(372–383). C에 보관되지 않은 기록(예: 되감기 표시로만 남은 기록)이 있었다면 그 기록은 적용되지 않고 표시는 이미 지워져 영구히 사라진다. `remember: false`면 C는 LRU에 없으므로 정상 디코드·적용되고, 이미 다시 적용한 기록은 병합에서 `kept`(멱등)다.
- **청크 단위 전부/전무**(6.3.2)가 함께 있어야 하는 이유: LRU만 고치면 되감기 경로가, 전부/전무만 고치면 겹침 재수신 경로가 남는다(검토 Q-1 — 둘 다 고침).
- `releaseHolds: false`가 필요한 이유: 원래 청크의 **다른** 알려진 기록이 K1으로 `sync.held`에 있을 수 있다. 1차 `_apply`는 보류가 없는 청크를 처리하면 `held.release(c.id)`로 그 항목을 지우는데(`download_pipeline.dart` 488–493), 합성 청크(모르던 기록만 든)로 그 항목을 지우면 보류 중인 기록을 잃는다.
- **K1에 걸린 다시 적용 기록**(v2.1, 계약 7.2.8 ⑤ — 검토 S-1): `sync.held`(청크 id 기준 — K2가 `getChunks`로 원래 청크를 다시 받음)에 넣지 **않고** `sync.heldRecords`에 해제 시각 `ra`와 함께 남긴다. 1차 `sync.held` 경로는 원래 청크가 그 사이 압축으로 지워지면 '돌아오지 않은 id는 잊음'이라 기록을 잃는다 — 옛 앱 A가 청크 C1의 손글씨 기록 h를 보관한 뒤, 새 앱 기기 B가 그 범위를 압축해 스냅숏 S(h 포함)를 만들고 C1을 지우면, A가 받은 S의 h는 같은 (`k`, `id`, `fv`)라 중복으로 버려지고 커서는 S를 지난다. A가 갱신 → 다시 적용에서 h가 K1에 걸리면 1차 경로로는 h를 되찾을 길이 없다. 보관에 남기면 원래 청크의 존재에 기대지 않는다. 다시 시도는 K2 해제 단계(`releaseHeld` — 연결마다 `catchUp` 뒤, live 중 1분마다 — 1차 6.2.5와 같은 시점)에서 g′ ≥ `ra`일 때 g′를 K1 기준으로 한다(4.1 해석 표).
- **재시도 위치**(검토 S-2): 1차 attach의 `if (!s.loaded) { purged.load; download.load }` 블록(`engine_controller.dart` 553–558) **밖**에 `if (!s.heldReapplied)`로 둔다. 성공했을 때만 `s.heldReapplied = true` — 실패하면 같은 세션의 다음 연결(오프라인 → 온라인 등)에서 다시 한다. 블록 안에 두면 같은 세션의 재연결에서 다시 하지 않는다.
- **지표**(검토 S-2): 다시 적용의 `ApplyResult`는 `latestServerTime: null`이고 청크·기록 수는 `reappliedChunks`·`reappliedRecords`로 따로 센다. 1차 `_absorbApply`(`engine_controller.dart` 993–1000)는 `latestServerTime`으로 `_lastRemoteApplyLatency`를, `r.chunks`로 `chunksReceived`를 계산하므로, 옛 serverTime의 합성 청크가 섞이면 지연이 며칠로 찍힌다. 다시 적용 결과는 `SyncEngineDebug.reappliedChunks`·`reappliedRecords`(4.2)에만 더한다. 문제·알림(`PageRestored`, `NoteRecoveredFromPurge`)은 1차와 같다.
- 다시 적용은 **원격 적용**이다(outbox·되돌리기 히스토리 밖 — 1차 계약 7.2.10 `applyRemote`).
- 로그인하지 않은 동안·계정 불일치(1차 6.10.4)·`disabled` 단계에서는 하지 않는다(attach가 일어나지 않음). 로그아웃해도 `sync.heldRecords`는 남는다(1차의 커서·`sync.held`와 같이 — 같은 계정으로 다시 로그인하면 이어 감).
- 시험(`engine/download_pipeline_test.dart` 'S-13' 묶음, 9.2): ① 다시 적용 뒤 `wasApplied(C)` = false ② 다시 적용 직후 겹침 재수신된 원래 청크 C가 정상 디코드·적용되고 결과가 같음(멱등, `kept`) ③ 저장분 + 표시분이 같은 청크로 갈리는 일이 없음(작은 상한 — `held_records_test`와 함께) ④ 다시 적용 K1 → `sync.held` 변화 없음, 보관에 `ra` ⑤ **다시 적용 K1 + 원래 청크가 압축으로 지워짐 → 해제 시각 뒤 `releaseHeld`가 보관분을 적용**(검토 S-1) ⑥ `releaseHolds: false` — 원래 청크의 다른 기록이 `sync.held`에 그대로 ⑦ 저장 실패 → 메모리 값 그대로, `engine_state_test`에서 같은 세션의 재연결이 다시 시도 ⑧ 다시 적용이 `chunksReceived`·`lastRemoteApplyLatency`를 바꾸지 않음.

#### 6.3.5 되감기 (상한 초과 · 깨진 값)

```text
load():  (v1.4 deferredFrom handling, then)
  held = HeldRecords.decode(sync.heldRecords keys, knownKinds)
  if held.wasCorrupt: meta += held.encode()                       // the converted all-kinds mark
  from = held.takeMarkIfDue()
  if from != null:
    back = from − cursorOverlap
    meta += {sync.cursor: min(cursor, back)} + held.encode()       // mark cleared
    LRU cleared                                                    // like 6.6.5 'deferredFrom'
  if meta not empty: writeMeta(meta)
```

- 표시가 언제 되감는가(`takeMarkIfDue`): 표시의 종류 이름 하나라도 지금 앱이 알면. `'*'`(깨진 값)이면 지금 앱이 아는 종류가 표시를 쓴 앱(`o.a`)보다 많을 때(= 앱 갱신 뒤), `o.a`를 모르면(머리가 깨짐) 바로. 같은 판의 앱에서는 되감지 않는다 — 다시 받아도 같은 종류를 또 모르기 때문이다.
- 되돌린 커서부터 다시 받으면 이미 적용한 알려진 기록은 병합에서 `kept`(멱등), 새로 아는 종류의 기록은 정상 적용되고, 여전히 모르는 종류의 기록은 다시 보관(또는 다시 표시)된다. 1차 6.6.5(새 형식 청크)와 같은 원리이고, 압축으로 원본 청크가 지워졌어도 스냅숏 청크(그 뒤 serverTime)가 같은 상태를 준다.
- 저장된 기록(`r`)과 되감기 표시(`o`)가 함께 있으면: `load()`가 먼저 되감고(표시 지움), 그다음 `reapplyHeldRecords()`가 저장분을 적용하고, `catchUp()`이 되감은 커서부터 받는다. 청크 단위 전부/전무라 한 청크가 두 쪽에 걸치지 않고, 다시 적용이 LRU에 넣지 않으므로 되감은 받기가 표시된 청크를 건너뛰지 않는다(6.3.4 — 검토 M-1의 데이터 손실 경로가 닫힘). 같은 기록이 두 경로로 와도 중복 제거·멱등이다.
- 되감기는 비용이 크다(그 시각 이후 전부 다시 받음 — 개인 사용량에서 수천 청크). 그래서 기본은 바이트 보관(조각 9개 × 224 KiB = 2,016 KiB — 손글씨 결과 약 144쪽, 6.3.2)이고, 되감기는 그보다 큰 경우와 깨진 값의 안전망이다.

#### 6.3.6 압축 · 가짜 서버 (1차 6.13)

- `Compactor`는 범위의 청크를 `decodeTolerant`로 읽는다. 모르는 기록이 든 청크는 **해석할 수 없는 청크와 같이** 스냅숏에 넣지 않고 지우지도 않는다(1차 `compactor.dart` 194–205의 `malformed` 갈래, `CompactionResult.unknownKindChunks` 카운터 추가). 그 청크의 알려진 기록은 청크가 남아 있으므로 잃지 않는다(받는 기기는 스냅숏과 남은 청크를 모두 받아 병합 — 멱등).
- 이 규칙이 없으면 옛 앱 기기가 압축하면서 새 종류 기록을 버리고 원본 청크를 지워 **새 앱 기기의 데이터를 잃는다**(D-S3).
- `FakeSyncServer.mergedState`(시험 기준 상태)는 `decodeTolerant`로 읽고 모르는 기록은 무시한다(알려진 기록은 병합). 1차는 그런 청크를 통째로 건너뛰었다 — 새 규칙에서는 기기 상태와 서버 기준 상태가 같은 알려진 기록을 본다. 새 종류 하위 기록의 영구 삭제 정리(페이지·노트)도 더한다(6.5).

#### 6.3.7 상태 · 문제 · 개발자 표시

- 문제: `needsAppUpdate`(비차단, 1차 `StatusBuilder`의 사건 문제 — (code, ref) 키로 횟수를 세고 로그아웃까지 남음 — 1차 T10 결정 ⑥). ref는 null이라 모르는 종류 보류는 '새 형식 청크'와 같은 키 하나로 합쳐 세어진다. 메시지가 종류를 말한다.
- `SyncEngineDebug.heldRecords` = `HeldRecords.length`, `heldRecordsMarked` = 표시 있음, `reappliedChunks`·`reappliedRecords` = 다시 적용 수(4.2). 개발자 표시(INFRA, 실연결 뒤)는 1차 `heldChunks`와 나란히 보인다. 깨진 값을 표시로 바꾼 일은 경고 로그(`SyncLogLevel.warning`)로 남는다.
- 사용자 문구(1차 계약 7.4.5 해요체 — 동기화 상태 화면은 실연결 뒤 INFRA): '앱을 업데이트하면 다른 기기에서 만든 일부 내용을 볼 수 있어요.' — `needsAppUpdate` 한 문구를 새 형식 청크와 같이 쓴다(1차 문구표에 이미 있으면 그대로).

#### 6.3.8 시험 훅 — '옛 앱'과 '앱 갱신'

- `DownloadPipeline(knownKinds:)`·`Compactor(knownKinds:)`(내부 인자), `EngineController.debugKnownKinds`(`@visibleForTesting`, `start()` 전), `SyncTestHarness.device(name, knownKinds:)`·`restart(name, knownKinds:)`(4.3).
- 실제 종류로 시험한다: '옛 앱' = `EntityKind.values − {handwriting}`(또는 `− {pageObject}`). 새 앱이 쓴 손글씨 결과가 섞인 청크를 옛 앱이 받아 획은 적용하고 손글씨만 보관 → `restart(knownKinds: 기본)` = 앱 갱신 → 다시 적용 → 수렴. 진짜로 모르는 종류(`bookmark`)는 `raw_records.dart`로 만든 바이트를 `commitRaw`로 넣고, 갱신 뒤에도 계속 보관됨을 본다.
- T16-v2(`core_unknown_kind_test`)는 같은 훅을 실제 CORE 엔진(직접 만든 `SyncEngine` + `EngineController.of(engine).debugKnownKinds`)에 쓴다.

---
### 6.4 R2-B7a 컴파일 패치 · R2-B7b `functions/` 골격 (기반 단계)

**R2-B7a**(R2-B2·R2-B2i와 한 묶음)의 목표는 **컴파일 + 1차 시험 전부 통과 + JSON 키 대조 v2**다(계약 7.6.2). 새 종류는 '노트 범위 일반 기록'으로 들어가고, 2차 의미(한 단위 병합·게이트·되살림·보류)는 동시 개발(S2-1~)에서 넣는다. [확인] 아래 목록은 1차 작업 트리에서 `grep -rn 'switch (.*kind)\|EntityKind.values'`와 `EntityKind\.` 사용처를 모두 본 결과다. `lib/`의 종류 `switch` 8개(`keysOf`·`groupsOf`·`scopeOf`·`_purged`·`SyncDoc.ownerId`·`RecordGate` `hasOwner`·`PurgeGuard._editedInOutbox`·`FakeSyncServer.mergedState`) 중 기본 갈래가 없어 실제로 깨지는 것은 앞의 4개다 — (v2.1, C21-04) 계약 7.0.1·7.0.2 문구가 이 목록으로 정정되었다.

| 파일 (1차 줄) | 깨지는 이유 | B7a 변경 |
|---|---|---|
| `lib/src/model/field_units.dart` `keysOf` (21–54) | exhaustive switch | + `pageObject`(합집합 16키), `handwriting`(10키), `recording`에 `title` |
| 같은 파일 `groupsOf` (57–78) | exhaustive switch | + `pageObject`·`handwriting` → `const []`(모든 키가 각자 단위 — '일반 기록') |
| `lib/src/model/scopes.dart` `scopeOf` (19–28) | exhaustive switch | + `pageObject` → `noteIdHint ?? library`, `handwriting` → `noteIdKey ?? noteIdHint ?? library`(최종 규칙과 같음 — 페이지와 같은 순서, 6.2.3) |
| `lib/src/merge/record_gate.dart` `_purged` (142–154) | exhaustive switch | + `pageObject`·`handwriting` → `null`(버리지 않음 — S2-3에서 최종 규칙) |
| `lib/src/codec/chunk_packer.dart` `kindOrder` (56–65) | 컴파일은 되나 `indexOf == -1`로 정렬이 틀어짐 | + `pageObject`, `handwriting`(최종 순서) |
| `test/support/entity_fixtures.dart` `fixtureJson` (65–) | exhaustive switch | + 도형 객체 JSON(계약 7.2.7 예시와 같은 모양), 손글씨 결과 JSON(줄 2개). (수정 2회차, 재검토 항목 1) 두 JSON 모두 **계약 생성자 + T20a `toJson()`**으로 만든다(`ShapeObject(…, geometry: PolylineGeometry([…4점], closed: true), style: ShapeStyle(strokeColorArgb: 0xFF1A1A1A), …)`·`HandwritingText(…, lines: [HandwritingLine(…) ×2])` — 5.1.5). `PageObjectFixtures`(T23b까지 `UnimplementedError`)는 쓰지 않는다. 같은 파일에 종류별 객체 도우미 `objectFixture(String type, {String? id})`(`'shape'`·`'text'`·`'image'`·`'math'` → 4종 생성자, `'sticker'` → `UnknownObject(rawJson)` — 모르는 키 `stickerId` 포함)를 더하고 `fixtureJson(pageObject)` = `objectFixture('shape').toJson()`이다. `kCoreJsonKeys`에 두 종류(pageObject = 합집합), 새 `kPageObjectTypeKeys`(종류별 키 — 6.2.1 표, `math`는 `engine` 포함 — C21-11) |
| `test/model/field_units_test.dart` — '키 표 = fixture 키'(묶음 표) | 'fixture 키 = 키 표'가 `pageObject`에서 합집합과 다름 | `pageObject`는 '종류별 키 = `kPageObjectTypeKeys[type]`, 합집합 = `keysOf`'로 바꿈. 묶음 표에 새 두 종류 `[]` |
| `test/model/field_units_test.dart` — 'the CORE key table matches what CORE entities serialize'(통합 HEAD 77행) | `fixtureEntity(kind).toJson().keys == kCoreJsonKeys[kind]`가 `pageObject`에서 깨짐(도형 11키 vs 합집합 16키) | (v2.1, SYNC-M4) **종류별 비교**로 바꾼다: `pageObject`는 알려진 4종 고정 자료(수정 2회차: SYNC `objectFixture('shape'/'text'/'image'/'math')` — 계약 생성자 + T20a `toJson`, `PageObjectFixtures`를 쓰지 않음)마다 `toJson().keys == kPageObjectTypeKeys[type]`, 네 집합의 합집합 = `kCoreJsonKeys[pageObject]` = `keysOf(pageObject)`, `objectFixture('sticker')`(`UnknownObject`)는 키 비교에서 빼고 `EntityJson.decode(pageObject, json).toJson()` 왕복(키 하나 빠짐없이 같음)만. 다른 종류는 1차 그대로 |
| `test/integration/core_json_keys_test.dart` (통합 HEAD 50–75행) | `_kindOf`가 새 골든 이름을 모름(→ `kinds == EntityKind.values` 단언 실패), '골든 키 = `keysOf(kind)`'(60–66)가 `pageObject` 골든에서 깨짐(`shape_rect.json` 11키, `unknown.json`의 모르는 키) | (v2.1, SYNC-M4 — 계약 7.2.8 'JSON 키 대조 v2 (R2-B7a에서)') **v2 단언을 B7a에 넣는다**: `_kindOf`에 새 골든 이름(`shape_rect`·`shape_ellipse`·`shape_arrow`·`text_box`·`image`·`math`·`unknown` → `pageObject`, `handwriting` → `handwriting`), 알려진 4종 골든 키의 합집합 = `keysOf(pageObject)`, 각 골든 키 = `kPageObjectTypeKeys[type]`(`math` 골든의 `engine: null` 포함), `unknown`은 키 대조에서 빼고 `SyncDoc` 왕복(키 하나 빠짐없이 같음)만, `handwriting`·`recording` 골든 키 = `keysOf`, 모든 골든에서 메타 키가 아닌 키가 정확히 한 단위에 든다(1차 '한 단위' 단언 — `pageObject`는 1차 단위 규칙으로 각자 단위이고, S2-1이 `wholeUnitExcept`로 바꿀 때 같은 단언이 '한 단위 + 따로 3키'로 바뀐다) |
| `EntityKind.values`를 도는 시험(`records_test`·`sync_doc_test`·`chunk_codec_test`·`field_merge_test`·`record_gate_test`) | 새 종류의 고정 자료가 CORE `EntityJson.decode`를 지나야 함 | 고정 자료만으로 통과(코드 변경 없음). **전제: B2-β 첫 조각(T20a)의 `toJson`·`PageObject.fromJson`·`HandwritingText.fromJson`·`Recording.title` JSON** — B2-α(T22)에서는 그 본문이 `UnimplementedError('CORE T20a')`다(02-core 8.1 'B2 상태'). (수정 2회차) 고정 자료가 생성자(α부터 실제)와 T20a 본문만 쓰므로 T20a 해시에서 판정된다 — `PageObjectFixtures`(T23b)를 쓰면 이 행과 `field_units_test` 두 행이 T23b까지 `UnimplementedError('CORE T23b')`로 실패한다(재검토 항목 1) |

- 기본 갈래(`_ =>`)가 있어 컴파일은 되는 곳(`SyncDoc.ownerId`, `RecordGate` `hasOwner`, `PurgeGuard._editedInOutbox`, `FakeSyncServer.mergedState`, `fake_sync_store.dart`의 `SyncEntity` switch들 — 모두 `_ =>`/`default:`, `SyncEntity`는 sealed가 아님 [확인 — 검토])은 B7a에서 건드리지 않는다 — 1차 동작(새 종류는 소유자 없음·편집 아님·정리 안 함)이 '일반 기록'과 같다.
- (v2.1, SYNC-M9 — CD2-05, CORE X-4 ①) **바탕과 두 단계 확인**: B7a의 switch 패치는 `EntityKind` 값만 필요하므로 CORE **B2-α(T22) 해시**('계약 타입 커밋' — 02-core 8.5 이정표 표) 위에서 만든다. 그 위에서는 컴파일·`flutter analyze --fatal-infos`·새 종류 디코드를 거치지 않는 1차 시험이 돈다. 새 종류 디코드(위 표 마지막 행)·`field_units_test` 종류별 비교·`core_json_keys_test` v2는 **B2-β JSON 골든(T20a) 커밋 뒤**에 그 해시 위로 다시 얹어(rebase) 확인한다(CP-S9 — 계약 7.6.2 R2-B7a 완료 조건 '새 종류 디코드·키 대조 시험(CP-S9)은 B2-β JSON 조각이 들어온 뒤'). 두 해시를 SYNC 진행 기록에 적는다. (수정 2회차, 재검토 항목 1) 이 'T20a 위' 확인이 그 해시에서 실제로 판정되려면 쓰는 CORE 본문이 T20a 것뿐이어야 한다 — 고정 자료는 계약 생성자(α부터 실제) + T20a `toJson`/`fromJson`/`EntityJson.decode`로만 만들고, B2-β 끝(T23b)에야 동작하는 `PageObjectFixtures`와 `createFakeNoteStore()`의 v2 멤버(객체·녹음·손글씨 쓰기)는 B7a 시험에서 쓰지 않는다(5.1.5 — 1차 시험 `providers_test`·`local/core_sync_local_store_test`가 쓰는 가짜 저장소의 v1 동작은 α부터 그대로다). `core_json_keys_test` v2는 CORE 골든 파일과 T20a `fromJson`/`toJson`만 쓰므로 원래 T20a에서 돈다. 그래서 확인 시점을 T23b로 옮기지 않고, 02-core 8.1 '이정표 알림'(SYNC는 T20a 해시 뒤)과 계약 7.6.2 R2-B7a 행도 그대로 맞다.
- 병합 순서: 총괄이 R2-B2(CORE, α+β) + R2-B7a(SYNC) + R2-B2i(INFRA) 세 브랜치를 함께 병합한 뒤 검사한다(계약 7.6.2 예외 하나). 그때 B7a 완료 조건 전부(8.1)가 통과해야 한다.

**R2-B7b**(`functions/` 골격 — v2.1, C-5·CD2-05)는 Dart와 무관하므로 **R2-B1(INFRA — `app/firebase.json`·`.gitignore`·`functions.yml` 골격·`with-heavy-lock`) 바로 뒤에 따로 병합**한다. 그러면 R2-B1의 `functions.yml`이 `functions/` 없이 도는 기간이 짧아진다(INFRA `hashFiles('functions/package.json')` 가드는 그대로 둔다 — INFRA 검토 S-11). 내용: `package.json`(3.4 — 스크립트 `build`·`test`·`test:emulator`, `eval:math`는 S2-13에서), `package-lock.json`, `tsconfig.json`, `.env.demo-noteapp`, `src/index.ts`·`src/recognize_math.ts`(로그인·소유자·가짜 엔진만 — `engineSignal` 주입 자리 포함), `src/engines/fake.ts`(계약 7.6 규칙), `scripts/emulator_suite.sh`(6.8.11 — `with-heavy-lock`), `test/fake_engine.test.ts`. 완료 조건은 8.1(`npm test` 시험 수 > 0). 커밋 전에 `firebase-tools 15.34.2`의 14일 경과(2026-11-11부터)를 다시 확인한다(C21-28).

### 6.5 시험용 가짜 v2 (`FakeLocalStore`·`FakeSyncServer`·`TestDevice` — 1차 07-sync 4.11·5.1.4)

1차 원칙 그대로: 가짜는 CORE 동작 계약(02-core 5.6·6.13·6.14의 SYNC 관련 문장)을 흉내 내고, 같은 SyncStore 계약 스위트(6.6)를 가짜와 실제 CORE에 함께 돌려 어긋남을 잡는다.

| 파일 (1차 줄) | 1차 | 2차 |
|---|---|---|
| `fake_sync_store.dart` 페이지별 색인 (36, 151–167) | `_strokesByPage` | + `_objectsByPage`, `_handwritingByPage`(행 쓰기·지우기의 `SyncEntity` switch에 `PageObject()`·`HandwritingText()` 갈래) |
| 같은 파일 `hintsOf` (283–293) | Page·Recording·Stroke | + `PageObject()` → (페이지의 `noteId`, 없으면 `''` — CORE 고아 값, `pageId`), `HandwritingText()` → (`noteId`, `pageId`) |
| `_fillOrphanHints` (297–318) | 그 페이지의 고아 획 항목 | + 고아 객체 항목 |
| `touchPage` 부르는 곳 | 획 쓰기 | + 객체·손글씨 쓰기 → 페이지 `contentRevision + 1`(한 트랜잭션에 한 번 — 1차 규칙, CORE C-29) |
| `noteOf` (417–423), `updatedAtOf` (425–433) | 1차 종류 | + `PageObject`(페이지의 노트), `HandwritingText`(`noteId`) |
| `removeGroup` (541–565) | 노트의 페이지·획·녹음 + outbox | + 객체·손글씨 결과 + 그 outbox 항목(CORE 6.14.2) |
| `duplicateNoteForRecovery` (888–957) | 노트·페이지·획 | CORE 6.14.1 순서: 녹음 새 id(같은 `assetId`·`title`)와 옛 → 새 표 → 획(`recordingId` 바꿈) → 객체 `copyTo(새 id, 새 페이지, createdAt 원래 값)` → 손글씨 결과(`hw_<새 페이지>`, `strokeIds`를 새 획 id로, 복사되지 않은 id는 뺌, `sourceRev = HandwritingText.sourceRevOf(복사된 입력 획)`) |
| `fake_sync_server.dart` `mergedState` (94–160) | `decode`(엄격), 영구 삭제 정리: 페이지·녹음·획 | `decodeTolerant`(모르는 기록 무시), 정리에 `pageObject`(지워진 페이지의 것 또는 범위가 영구 삭제 노트)·`handwriting`(`noteId`) |
| `test_device.dart` | 4.3 1차 도우미 | 4.3 2차 도우미. 각 도우미가 쓰는 필드 집합은 CORE C-11(바뀐 JSON 키만)과 같게: 이동 `{frame, geometry}`(도형)·`{frame}`(그 밖), 스타일 `{style}`, 글 `{text, frame}`, 삭제 `{deletedAt}`, 손글씨 `put`은 바뀐 키만, 녹음 이름 `{title}` |
| `sync_test_harness.dart` (201–204 `checkConverged`) | `device()`, `checkConverged(devices, {includeServer})` | + `knownKinds:`, `restart(name)`(같은 `FakeLocalStore`에 새 엔진 — 메타·outbox 유지), (v2.1) `checkConverged(…, kinds:)`(참가자 덤프를 종류로 거름 — 옛 앱 기기 대 서버 병합 상태 비교, 4.3). 세 가지를 한 작업(S2-4b)이 만들고 `testing/sync_test_harness_test.dart`로 시험한다 |

- 가짜 시험(`testing/*_test.dart`)은 1차 시험 옆에 위 표의 각 행을 한 경우 이상 더한다(예: 고아 객체 항목이 페이지가 온 뒤 힌트를 받음, 복구 사본의 손글씨 `strokeIds`가 새 획 id, `checkConverged(kinds:)`가 거른 종류의 차이는 무시하고 나머지 차이는 잡음).
- (v2.1, 검토 S-10) 작업 나눔: 위 표의 가짜 저장소·서버 행(`fake_sync_store`·`fake_local_store`·`fake_sync_server`)과 그 `testing/*_test`는 **S2-4a**, `TestDevice`·하네스 행과 계약 스위트 C-26~C-31(6.6)·실제 CORE 드라이버 멤버는 **S2-4b**다(8.2).

### 6.6 SyncStore 계약 스위트 v2 (1차 C-01~C-25에 더함)

`test/contract/sync_store_contract.dart`의 드라이버(`SyncStoreContractDriver`, 1차 5.1.4)에 `addObject(pageId)`·`restyleObject(id)`·`removeObject(id)`·`putHandwriting(pageId)`·`createRecording(noteId)`·`renameRecording(id, title)`를 더한다. 가짜 드라이버는 `FakeLocalStore` 로컬 쓰기, 실제 CORE 드라이버(`integration/support/core_store_driver.dart`)는 세션 `AddObjects`·`UpdateObjects`·`RemoveElements`, `store.handwriting.put`, `store.recordings.createRecording`·`renameRecording`을 쓴다.

| # | 계약 문장 (CORE 5.6·6.13·6.14, 계약 7.2.8) | 확인 |
|---|---|---|
| C-26 | 객체 로컬 쓰기의 outbox 항목은 `kind == pageObject`, `noteId` = 페이지의 노트, `pageId` 있음. `changedFields`: 추가 `{'*'}`, 스타일 `{style}`, 삭제 `{deletedAt}` | 두 드라이버 |
| C-27 | 손글씨 결과 쓰기의 outbox 항목은 `noteId`·`pageId` 있음, id = `hw_<pageId>`. 같은 값 다시 쓰기는 항목을 만들지 않음, `lines`만 바꾸면 `{lines}` | 두 드라이버 |
| C-28 | 원격 객체가 페이지보다 먼저 오면(다른 `applyRemote` 호출) 저장되고(고아), 페이지가 오는 호출에서 입양된다 — 그 객체는 페이지가 온 호출의 `localChanges`/`EntityChange` 묶음에 나온다 | 두 드라이버 |
| C-29 | 기존 페이지에 원격 객체·손글씨 결과를 적용하면 그 페이지 `contentRevision`이 한 번 오른다(1차 C-9 꼴) | 두 드라이버 |
| C-30 | 노트 영구 삭제 뒤 그 노트의 객체·손글씨 결과는 `readVersioned`가 null이고 outbox 항목도 없다. 녹음 초안·검색 단위를 만들어도 `pendingChanges`·`watchPendingCount`가 바뀌지 않는다 | 앞 문장은 두 드라이버, 뒤 문장은 실제 CORE만(`recordingDrafts.begin`·`search.replaceUnits`) |
| C-31 | 녹음 JSON에 `title` 키가 있고, `renameRecording`의 outbox `changedFields`는 `{title}` | 두 드라이버 |

### 6.7 시나리오 시험 설계 (1차 07-sync 9.1.2 확장)

#### 6.7.1 가짜 시나리오 (`test/scenarios/`, 태그 `scenario`, 기본 실행, fakeAsync 하네스)

| ID | 흐름 | 단언 |
|---|---|---|
| S23 객체 동시 편집 | A·B 같은 노트. 도형 X를 A가 오프라인에서 이동(t1), B가 오프라인에서 색 변경(t2 > t1). 둘 다 연결 | 두 기기·서버의 X = B의 스냅숏(색 B, 위치 **원래**) — 객체 단위 LWW(A의 이동은 사라짐, 계약 D3). 다른 객체 Y를 A가, Z를 B가 고친 것은 둘 다 남음. `checkConverged` |
| S24 삭제 대 수정 | A가 텍스트 상자 T 삭제, B가 오프라인에서 T 글 수정 | 양쪽 T `deletedAt` 있음 + 글은 B 값(따로 단위 — 1차 S05와 같은 모양) |
| S25 페이지 삭제 대 새 객체 | (a) A가 페이지 P 삭제, B가 오프라인에서 P에 이미지 객체 추가 → (a1) B가 먼저 연결 / (a2) A가 먼저. (b) A가 P 삭제, B는 P의 손글씨 결과만 새로 씀 | (a) 두 순서 모두 P가 되살아나고(`PageRestored` 1회) 객체가 보임. (b) P는 삭제된 채(손글씨는 근거 아님), 손글씨 결과 행은 남음 |
| S26 모르는 `type` 왕복 | X(새 앱 흉내)가 `type: "sticker"` + 중첩 맵·배열·모르는 키를 가진 객체를 `putRawObject`로 쓰고 올림. A가 받아 그 객체를 삭제. B가 받음 | A·B·서버 병합 상태의 JSON 키 집합 = 원본 키 집합(+`deletedAt` 값만 다름), 원본 값 그대로 |
| S27 모르는 `kind` 보류 | (a) `commitRaw`로 [획 1, `bookmark` 기록 1]인 청크 → A: 획 적용, `bookmark` 보관 1, `needsAppUpdate` 1회, 커서 진행, 겹침 재수신에 문제 다시 없음. (b) A = `knownKinds − {handwriting}`, B(새 앱)가 손글씨 결과 + 획을 한 청크로 보냄 → A 획만, 보관 1 → `h.restart('A')`(기본 종류) = 앱 갱신 → A에 손글씨 결과 = B와 같음, 보관 0, `bookmark`는 계속 보관. 갱신 직후 재시작(겹침 재수신 안에 원래 청크)도 같은 결과. (c) (v2.1, SYNC-M1) **상한이 청크 중간에서 걸리는 모양**: 보관 상한을 작게(내부 인자 `maxTotalBytes` = 손글씨 기록 2개 남짓) 하고, B가 손글씨 결과 1개가 든 청크 C1과 3개가 든 청크 C2를 차례로 보냄(C1은 들어가고, C2를 다 넣으면 넘침 — 1차 방식이면 C2의 첫 기록만 저장되고 둘은 표시로 갈렸을 모양) → A: C1 저장, **C2는 하나도 저장하지 않고 표시**만(`heldRecordsMarked`) → 갱신 → `load()` 되감기 + 다시 적용(C1, LRU 밖) + `catchUp`이 C1·C2를 다시 받음 → A에 손글씨 4개 모두 = B, 보관 0·표시 없음. (d) 옛 앱 A가 압축을 돌려도 `bookmark`·손글씨가 든 청크는 남음 → 새 기기 D가 처음 동기화해 손글씨 결과를 받음. (e) (v2.1, SYNC-M5) A의 시계를 크게 앞당겨 다시 적용에서 손글씨 기록이 K1에 걸림 → 그 사이 B가 그 범위를 압축(원래 청크 삭제) → A의 해제 시각이 지나 K2 단계 → 보관분이 적용됨(`sync.held` 경로를 쓰지 않음). (f) 깨진 값: A의 `sync.heldRecords.1`을 손으로 깨뜨린 뒤 갱신 → 모든 종류 되감기 → 손글씨 결과가 B와 같음 | 각 경우 `checkConverged`(알려진 종류 — 옛 앱 단계에서는 `kinds: values − {handwriting}`, 4.3). 데이터 손실 0(갱신 뒤 `checkConverged` 전체) |
| S28 손글씨 결과 | A가 페이지 P 결과를 씀 → B 받음. A·B가 오프라인에서 각자 P를 다시 인식(다른 `lines`) → 연결. 다음, B가 **연결된 채** P의 결과를 다시 써 올림(B의 '최근 보냄'에 손글씨만) → 가상 시간 **2분 뒤**(10분 창 안 — v2.1, SYNC-M3) A가 노트를 휴지통 → 영구 삭제. 마지막으로 B가 오프라인에서 결과를 또 씀 → 연결 | 결과 id = `hw_P` 하나, 나중 쓰기가 이김. B의 `PurgeGuard`는 손글씨만 올리고 손글씨만 outbox에 있는 노트를 '편집 중'으로 보지 않음(`recentlySent`에 N 없음) → **복구 사본 없음**, `NoteRecoveredFromPurge` 0. 영구 삭제 뒤 B의 늦은 결과는 게이트가 버림, 양쪽에 결과 행 없음. 대조: 같은 흐름에서 B가 2분 전에 **획**을 올렸으면 사본 1(1차 규칙 그대로) |
| S29 녹음 이름 | A가 녹음 R 이름을 '1강'으로, B가 오프라인에서 R 삭제 → 연결. 다음 A·B가 각자 이름을 바꿈 | 첫째: 삭제됨 + 이름 '1강'(따로 단위). 둘째: 나중 이름 |
| S30 영구 삭제 대 보내지 않은 객체 편집 | B가 노트 N에 오프라인으로 객체 2개 추가·1개 수정 + 녹음 1개 + 손글씨 결과. A가 N을 휴지통 → 영구 삭제하고 올림. B 연결 | B의 `PurgeGuard`가 사본 N'를 만듦(`NoteRecoveredFromPurge`). N'에 객체·녹음(새 id)·획의 `recordingId`가 새 녹음 id·손글씨 결과(`hw_<N'의 페이지>`)가 있고, A도 N'를 받음. N은 양쪽에서 사라짐 |
| 무작위 수렴 v2 | 1차 `fuzz_convergence_test`(시드 1..20 × 연산 500, 기기 3대, 무작위 오프라인·커밋 장애)의 연산에 `addObject`·`moveObject`·`restyleObject`·`editText`·`deleteObject`·`putHandwriting`·`renameRecording` 추가 | 수렴·손실 0·순환 없음(1차 단언) |

- 시나리오 전체 시간 목표: 1차 약 31 s → 2차 ≤ 60 s(1차 상한 90 s 유지).

#### 6.7.2 T16-v2 — 실제 CORE v2 두 개 (`test/integration/`, 태그 `integration`, 통합 3단계)

1차 `core_scenarios_test`처럼 하네스 없이 실제 시간에서 `openTestNoteStore(filePath: 임시 파일)` 두 개 + `CoreSyncLocalStore` + `SyncEngine` 두 개 + `FakeSyncServer`(가짜 서버는 1차처럼 실제 시간용 시계)로 돈다. 상태를 50 ms 간격으로 기다리고(상한 3분) 시간은 단언하지 않는다. 수렴은 건드린 엔티티를 두 저장소의 `readVersioned`로 읽어 `canonicalDumpOf`로 비교한다(1차 T16 결정).

| 파일 | 경우 | 실제 CORE로만 보이는 것 |
|---|---|---|
| `core_objects_scenarios_test.dart` | O1 동시 편집(A `TransformElements`, B `UpdateObjects` 스타일 — S23), O2 삭제 대 수정(A `RemoveElements`, B 스타일 — S24), O3 페이지 삭제 대 새 객체(A `DeletePages`, B 오프라인 `AddObjects` — S25 a), O4 텍스트 편집 세션 대 이동, O5 영구 삭제 대 보내지 않은 객체 편집(S30 — CORE `duplicateNoteForRecovery`의 녹음·객체·손글씨 복사) | CORE C-11(바뀐 키만 새 버전)이 SYNC 단위와 맞물림, 원격 고아 객체 입양, `PageContent.objects`에 원격 객체가 보임(열린 세션 N-7) |
| `core_unknown_type_test.dart` | U1 `commitRaw`로 `type: "sticker"` 객체(중첩 값·모르는 키) → A 받음 → A가 그 객체만 `RemoveElements` → B 받음 → 서버 병합 상태의 키 집합 = 원본(C-12). U2 A가 그 노트를 복사(`copyItems`) → 복사본의 객체도 원본 키 그대로 | CORE `UnknownObject` 보존·삭제·복사 |
| `core_unknown_kind_test.dart` | K1 `commitRaw` [획, `bookmark`] → A 획 적용·보관 1·`needsAppUpdate`. K2 A를 `debugKnownKinds = values − {handwriting}`로 시작, B가 `handwriting.put` + 획 → A 보관 → A 엔진 dispose 후 같은 저장소 파일로 다시 열고 기본 종류로 시작(앱 갱신) → A `handwriting.forPage` = B의 결과, 보관분 0 | 실제 CORE의 메타 KV 트랜잭션(커서·`sync.heldRecords`가 함께 저장되는지 — 다시 열기 뒤 값) |
| `core_handwriting_test.dart` | H1 A `put` → B `forPage` 같음 + **B `search.searchPages(낱말)`이 그 페이지를 찾음**(원격 적용 쓰기 훅의 색인 — 02-core 6.13). H2 두 기기 동시 `put` → 나중 것. H3 페이지에 손글씨만 있는 상태에서 A가 페이지 삭제, B가 결과를 다시 씀 → 되살리지 않음. H4 노트 영구 삭제 → 양쪽 `forPage` null, 색인에서도 사라짐 | CORE 색인 훅, `stalePages`(원격 결과를 받은 기기에서 `sourceRev`가 맞으면 낡지 않음) |
| `core_recording_title_test.dart` | R1 이름 대 삭제(S29), R2 `createRecording` → B의 `watchRecordings`에 나옴(오디오 에셋은 1차 에셋 경로 — 가짜 Blob) | `Recording.title` JSON·필드 버전 |
| `core_json_keys_test.dart` (변경 — **R2-B7a에서**, 6.4) | 1차 5개 + 새 골든 9개(`shape_rect`·`shape_ellipse`·`shape_arrow`·`text_box`·`image`·`math`·`unknown`·`handwriting`·`recording`): 알려진 4종 골든의 키 합집합 = `keysOf(pageObject)`, 각 골든 키 = `kPageObjectTypeKeys[type]`, `unknown`은 키 대조에서 빼고 `SyncDoc` 왕복이 키 하나 빠짐없이 같음, 손글씨·녹음 키 = `keysOf`, 모든 골든에서 메타 키가 아닌 키가 정확히 한 단위에 든다(6.2.2 규칙). (v2.1, SYNC-M4) 이 단언은 B7a가 만들고 B2-β JSON 골든(T20a) 뒤부터 돈다 — T16-v2에서는 다시 돌리기만 한다 | CORE 골든 파일 |
| `core_sync_store_contract_test.dart` (변경) | 계약 스위트 C-01~C-31을 실제 CORE 드라이버로 | 6.6 |

**CORE 선행 작업 표**(v2.1, SYNC-M6 — 검토 S-5. 02-core 8.1 'B2 상태'와 8.2 T24~T33의 완료 조건으로 다시 셈). 실제 저장소의 `AddObjects`·`UpdateObjects`는 T27까지, `recordings`·`handwriting`·`search` 쓰기는 T30~T33까지 `UnimplementedError`다. 아래 '돌기 시작하는 이정표'는 그 경우가 실제로 단언까지 가는 가장 이른 CORE 커밋이다(뒤 커밋은 앞 커밋을 포함 — T26 ⊂ T27·T28, T29는 T27·T30·T32·T33a 뒤).

| 파일 | 경우 | 돌기 시작하는 CORE 이정표 | 그 이정표가 필요한 이유 |
|---|---|---|---|
| `core_json_keys_test` | 키 대조 v2 | **T20a**(B2-β JSON 골든) | 새 골든 9개·`toJson` |
| `core_sync_store_contract_test` | C-01~C-25 | (이미 통과 — 통합 HEAD 42개), T24 뒤 다시 | DB v2에서 1차 문장이 그대로인지(회귀) |
| 〃 | C-26(객체 outbox) | **T27** | 실제 저장소의 객체 명령 열기(T26 힌트 포함) |
| 〃 | C-27(손글씨 outbox) | **T32** | `handwriting.put` |
| 〃 | C-28(원격 고아 객체 입양)·C-29(`content_rev`) | **T28** | `DriftSyncStore`의 새 종류 `applyRemote`(T26 행 변환·고아 입양 포함) |
| 〃 | C-30 앞(영구 삭제 → 객체·손글씨·outbox 지움) | **T29** | `deleteNoteContents` 확장·`RemotePurge`(T27·T32 쓰기 뒤) |
| 〃 | C-30 뒤(초안·색인은 outbox 밖) | **T31**·**T33a** | 실제 초안 저장소 `recordingDrafts.begin`, 색인 쓰기 `search.replaceUnits` |
| 〃 | C-31(녹음 `title`) | **T30** | `createRecording`·`renameRecording` |
| `core_objects_scenarios_test` | O1~O4 | **T27**·**T28** | 세션 객체 명령(보내는 쪽) + 새 종류 `applyRemote`(받는 쪽), N-7 원격 객체 보임 |
| 〃 | O5(영구 삭제 대 보내지 않은 객체 편집) | **T29** | `duplicateNoteForRecovery`의 녹음·객체·손글씨 복사(T30·T32·T33a 뒤) |
| `core_unknown_type_test` | U1 | **T28**(+ 삭제는 T27) | `UnknownObject` `applyRemote` 왕복, `RemoveElements` |
| 〃 | U2(노트 복사) | **T29** | `copyItems`의 객체 복사 |
| `core_unknown_kind_test` | K1([획, `bookmark`]) | 지금(1차 경로) | 획·메타 KV만 — 새 CORE 쓰기 없음 |
| 〃 | K2(옛 앱 → 갱신) | **T32**·**T28** | B의 `handwriting.put`, A의 손글씨 `applyRemote` |
| `core_handwriting_test` | H1(받은 결과가 검색됨) | **T32**·**T28**·**T33b** | 손글씨 쓰기·원격 적용·색인 질의 |
| 〃 | H2·H3 | **T32**·**T28** | |
| 〃 | H4(노트 영구 삭제 → 색인에서도 사라짐) | **T29**·**T33b** | 영구 삭제 확장·색인 질의 |
| `core_recording_title_test` | R1·R2 | **T30**·**T28** | 녹음 저장소·원격 적용 |

- 동시 개발 중에는 '작성 + 컴파일'까지가 S2-9의 완료 조건이고, 실행·판정은 통합 3단계다(1차 T16과 같은 처리). CORE 진행 기록의 **이정표 커밋 표**(02-core 8.5 — B2-α·T20a·T24·T26~T33 해시가 한 줄씩 들어간다, 계약 7.6.2 '이정표 커밋 알림')에 위 표의 커밋이 올라올 때마다 해당 파일만 `flutter test --run-skipped test/integration/<파일>`로 로컬에서 한 번씩 돌려 미리 어긋남을 찾고 결과를 SYNC 진행 기록에 적는다(무거운 전체 실행은 하지 않음 — 패키지 하나, 파일 하나). 아직 이정표 전인 경우는 `UnimplementedError('CORE T…')`로만 실패한다(컴파일은 됨) — 그 실패 메시지의 작업 번호가 위 표와 맞는지도 본다.
- CORE에 요청한 것(X-4 ②): T27·T29·T30·T31·T32·T33(a·b) 커밋도 이정표 표에 알린다 — 02-core 8.1·8.5에 이미 들어 있다(2026-11-05 확인).

---
### 6.8 서버 함수 `recognizeMath` (`functions/`, 새)

#### 6.8.1 구조와 원칙

- 배포 표면은 callable 함수 하나(`src/index.ts` → `recognizeMath`). 처리 본문은 firebase-functions 타입 없이 `createRecognizeMathHandler(deps)`(4.5)로 두어 단위 시험이 에뮬레이터 없이 돈다(`test/handler.test.ts`). `onCall` 연결은 `src/recognize_math.ts`의 몇 줄뿐이다.
- 엔진은 포트(`MathEngine`) 뒤에 둔다 — 서버 안에서 엔진을 바꿔도 앱(LIBRARY `CallableMathRecognizer`)은 바뀌지 않는다(PLAN F-14 '교체 가능한 구조'). 앱 쪽 포트(`MathRecognizer`)와 이름은 겹치지만 언어가 달라 충돌하지 않는다.
- 함수 옵션(계약 7.2.13): `region: "asia-northeast3"`, `maxInstances: 2`, `timeoutSeconds: 30`, `memory: "256MiB"`, `enforceAppCheck: false`, `secrets: [MATH_API_KEY]`. callable의 CORS는 firebase-functions 기본(모든 출처 허용 — 인증은 ID 토큰과 소유자 목록이 한다).

#### 6.8.2 처리 순서

```text
handler({auth, data}):
  t0 = now()
  1. auth == null                         → HttpsError('unauthenticated', 'sign-in required')
  2. auth.uid ∉ ownerUids()               → 'permission-denied'      (empty list → nobody passes)
  3. req = parseRequest(data); error      → 'invalid-argument', message = the reason
  4. engine = engines.resolve(req.engine)
       EngineError(notConfigured)          → 'unavailable'           ('none', no key, 'gemini')
       unknown name / 'fake' not allowed   → 'invalid-argument'
     input fits engine.accepts? else       → 'invalid-argument'      (e.g. strokes only, png engine)
  5. cap = dailyCap(); if cap > 0:
       q = quota.take(uid, seoulDayKey(t0), cap); !q.allowed → 'resource-exhausted'
       (store failure → 'unavailable', logged; the engine is NOT called)
  6. out = engine.recognize(input, deps.engineSignal(ENGINE_TIMEOUT_MS))   // 25 s; prod =
       AbortSignal.timeout — (v2.1) injected so tests abort their own AbortController
       EngineError → table 6.8.8 ; abort → EngineError(timeout) ; other exception → 'internal'
  7. checkOutput(out): latex non-empty string ≤ 4000 chars (CORE maxLatexLength), confidence ∈ [0,1]
       or dropped, alternatives: strings, ≤ 5, each ≤ 4000, empty ones dropped; else → 'internal'
  8. log(…, out.logInfo) ; return {latex, confidence?, alternatives?, engine: engine.name,
                      engineVersion: out.version, ms: now() − t0}
       // (v2.1, contract 7.2.13) engineVersion = the engine / model that actually answered
```

- 입력 검사(3)를 상한 차감(5)보다 먼저 한다 — 잘못 만든 요청이 하루 횟수를 쓰지 않게. 상한은 엔진 호출(비용) 바로 앞이다.
- 상한은 엔진이 실패해도 차감된 채로 둔다(남용 방지 — 실패 반복도 한도에 걸림). 개인 사용량에서 하루 200회(기본)를 실패로 다 쓰는 일은 드물다.
- `HttpsError`의 `details`는 쓰지 않는다(앱은 `status`·`message`만 본다 — 05-library 6.11.4). 예상 밖 예외는 firebase-functions가 `INTERNAL`로 감싸 메시지를 숨긴다.
- (v2.1, SYNC-M7 — 검토 S-6) 제한 시간은 `HandlerDeps.engineSignal`로 주입한다. [확인 — 검토, Node 22.23.4] `mock.timers.enable({apis: ['setTimeout', 'Date']})` 뒤 만든 `AbortSignal.timeout(25000)`은 `tick(26000)`에도 `aborted == false`다 — 처리 본문이 직접 부르면 `handler.test.ts`의 시간 제한 경우를 가짜 시계로 시험할 수 없다. 시험은 `engineSignal: () => ctl.signal`을 넘기고, 가짜 엔진이 신호를 기다리는 동안 `ctl.abort()` → `unavailable`(`timeout`)을 단언한다. 운영 기본값은 `(ms) => AbortSignal.timeout(ms)`(`recognize_math.ts`의 `onCall` 연결). 비교 도구(6.9)도 같은 주입을 쓴다.

#### 6.8.3 입력 검사 (`parseRequest`)

| 필드 | 규칙 | 위반 메시지(영어, 앱은 보이지 않고 `status`로 문구를 고름) |
|---|---|---|
| `data` | 객체 | `data must be an object` |
| `v` | 정확히 `1`(없으면 오류) | `unsupported protocol version` |
| `engine` | 없으면 `'auto'`. `'auto'`·`'mathpix'`·`'claude'`·`'gemini'`·`'fake'` 중 하나 | `unknown engine` |
| `locale` | 없으면 `'ko'`. `'ko'`·`'en'` | `unknown locale` |
| `strokes`·`pngBase64` | 적어도 하나 | `strokes or pngBase64 is required` |
| `strokes.x`·`strokes.y` | 배열의 배열, 획 수 1..2000, 같은 모양(획마다 길이 같음), 획당 점 1..10000, 유한한 수 | `strokes.x/y must be number[][] of the same shape` |
| `strokes.t` | 있으면 `x`와 같은 모양, 정수 ms ≥ 0, 획 안에서 비감소(CP-L8 — 첫 획 첫 점부터의 ms) | `strokes.t must be non-decreasing integer ms` |
| `strokes` 크기 | `Buffer.byteLength(JSON.stringify(strokes))` ≤ 524,288 | `strokes is larger than 512 KB` |
| `pngBase64` | 문자열, 길이 1..2,097,152, base64 문자(`A–Z a–z 0–9 + / =`), 풀었을 때 PNG 서명(`89 50 4E 47 0D 0A 1A 0A`) | `pngBase64 is not a PNG` 등 |
| 그 밖의 키 | 무시(v1은 더하기만 — 계약 7.4.9 '추가만') | — |

- 좌표계는 페이지 pt(계약 7.2.13 주석)이고 서버는 값의 범위(음수 포함)를 제한하지 않는다 — 수식이 페이지 밖으로 나간 획도 보낼 수 있다.

#### 6.8.4 엔진 포트와 등록부

| 엔진 | `name` / `engineVersion`(v2.1 — 실제로 답한 판) | `accepts` | 설정이 되었다고 보는 조건 | 등급 |
|---|---|---|---|---|
| 가짜 | `fake` / `1` | 획·이미지 | `ALLOW_FAKE_ENGINE=true` | P-B |
| Mathpix | `mathpix` / `v3`(응답에 판이 없어 API 경로 판) | 획(`v3/strokes`)·이미지(`v3/text`) | `MATH_ENGINE=mathpix`, `MATHPIX_APP_ID` ≠ '', `MATH_API_KEY`(app_key) ≠ '' | P-C |
| Claude | `claude` / **응답의 `model`**(요청은 `CLAUDE_MODEL` — (v2.3, C23-02) 기본 빈 문자열. 서버 쪽 대체가 돌면 다른 모델일 수 있다) | 이미지만 | `MATH_ENGINE=claude`, `MATH_API_KEY` ≠ '', `CLAUDE_MODEL` ≠ '' (CP-S5 승인 — 계약 7.5) | P-C |
| Gemini | `gemini` | — | 이번에는 없음 → 언제나 `notConfigured` | 이후(1.3) |

- (v2.1, SYNC-M7 — 검토 S-7) **매개변수를 읽는 곳은 등록부 하나**다: `registryFromParams()`가 요청마다 `params.ts`의 값(`.value()`)을 읽어 `EngineSettings`를 만들고, 어댑터는 생성자로 `{apiKey, appId?, model, client?/fetch?}`를 받는다. 어댑터 파일은 `firebase-functions/params`를 import하지 않는다 — 비교 도구(6.9)가 같은 어댑터를 개발자 환경 변수로 만들고, 시험 주입점(가짜 `fetch`·가짜 SDK 클라이언트·`createRegistry(settings, factories)`)도 같은 곳이 된다. `secrets_hygiene.test.ts` 옆에 '`src/engines/*.ts`가 `params`를 import하지 않음' 소스 검사를 하나 둔다.

- `'auto'`는 `MATH_ENGINE`(기본 `'none'` → `notConfigured`)을 따른다. 운영에서 엔진은 한 번에 하나다 — `MATH_API_KEY`는 그 엔진의 키다(계약 '`MATH_API_KEY` (+ engine-specific)'의 해석, 4.1 표).
- 요청이 `'auto'`가 아닌 이름을 직접 고르면, 그 이름이 `MATH_ENGINE`과 같거나 `'fake'`(허용된 경우)일 때만 받는다 — 키가 없는 엔진을 고르면 `unavailable`.

#### 6.8.5 가짜 엔진 — 결정적 출력 (LIBRARY 에뮬레이터 시험과 공유, D-S7)

(v2.1, CP-S3 ⑥ 승인) 이 규칙은 계약 7.6 시험 도우미 블록의 문장이다(원문은 4.1). 아래 표는 그 원문을 풀어 쓴 것이고, 바꿀 때는 계약 7.4.9 절차를 거친다(LIBRARY Dart 에뮬레이터 시험 L2-I6이 같은 값을 단언한다).

| 입력 | 출력 |
|---|---|
| `strokes` 있음 (S = 획 수, P = 점 수 합) | `latex = "\frac{S}{P}"`, `confidence = 1`, `alternatives = ["S/P"]` |
| `pngBase64`만 (B = 푼 바이트 수) | `latex = "\sqrt{B}"`, `confidence = 1`, `alternatives = []` |
| 첫 획 첫 점이 (−1, −1) | `EngineError(upstream)` → `unavailable` |
| 첫 획 첫 점이 (−2, −2) | `EngineError(badResponse)` → `internal` |
| 첫 획 첫 점이 (−3, −3) | `EngineError(rateLimited)` → `unavailable` |

- `engine: "fake"`, `engineVersion: "1"` → 앱의 `engineId`는 `'fake/1'`(05-library 6.11.2). 네트워크·시계·난수를 쓰지 않는다. 조사 04 6.4 골격의 가짜(`\frac{길이}{2}`)는 입력 모양을 반영하지 않아 위 규칙으로 바꾼다.

#### 6.8.6 실제 엔진 어댑터 (P-C — 코드 + 가짜 응답 시험, 실제 호출은 계정 뒤)

**Mathpix** (`src/engines/mathpix.ts`, Node 내장 `fetch` — Mathpix는 공식 Node SDK가 없다 [추측]. (v2.1) 생성자 `new MathpixEngine({appId, apiKey, fetch?})` — 등록부·비교 도구가 값을 넘긴다):

| 입력 | 요청 [추측 — 조사 03 6.2 검색 요약, 문서 원문 미확인] |
|---|---|
| 획 | `POST https://api.mathpix.com/v3/strokes`, 헤더 `app_id`·`app_key`, 본문 `{"strokes": {"strokes": {"x": [[…]], "y": [[…]]}}}` |
| 이미지(획이 없을 때) | `POST https://api.mathpix.com/v3/text`, 본문 `{"src": "data:image/png;base64,…", "formats": ["latex_styled"]}` |
| 응답 | `latex_styled`(→ `latex`), `confidence`(있으면), `error`가 있으면 실패 |

시험(`test/mathpix.test.ts`): 주입한 가짜 `fetch`로 요청 모양(주소·헤더에 키가 들어가고 로그에는 없음·본문), 응답 해석, HTTP 401/403 → `notConfigured`, 429 → `rateLimited`, 5xx·연결 실패 → `upstream`, 넘긴 신호가 abort됨(시험이 `AbortController.abort()` — 6.8.2) → `timeout`, `error` 필드·`latex_styled` 없음 → `badResponse`, `engineVersion` = `'v3'`. 컨테이너에서는 `api.mathpix.com`이 막혀 있어 실제 호출 시험이 없다(계약 5장).

**Claude** (`src/engines/claude.ts`, 공식 SDK `@anthropic-ai/sdk 1.1.0` — CP-S5 승인, 계약 7.5. (v2.1) 생성자 `new ClaudeEngine({apiKey, model, client?})` — 매개변수를 직접 읽지 않는다):

```ts
// sketch — the shapes follow the official TypeScript SDK; verified against real calls only after the
// account exists (U6). No temperature/top_p (rejected by current API versions).
// (v2.1) constructor({ apiKey, model, client }) — client defaults to a thin wrapper over
// new Anthropic({ apiKey, maxRetries: 0, timeout: 25_000 }).beta.messages; tests pass a fake.
const res = await this.client.create({
  model: this.model,                                 // CLAUDE_MODEL via the registry (default '' → notConfigured)
  max_tokens: 16000,
  betas: ["server-side-fallback-2026-07-01"],
  fallbacks: "default",                              // server-side fallback on a refusal
  output_config: {
    effort: "low",                                   // one formula — Opus 5.5 default is medium
    format: { type: "json_schema", schema: LATEX_SCHEMA },  // {latex, confidence, alternatives}
  },
  system: SYSTEM_PROMPT,                             // "Transcribe the handwritten math in the image as LaTeX …"
  messages: [{ role: "user", content: [
    { type: "image", source: { type: "base64", media_type: "image/png", data: pngBase64 } },
    { type: "text", text: localeHint(locale) },     // e.g. Korean words inside \text{…}
  ] }],
}, { signal });
if (res.stop_reason === "refusal") throw new EngineError("refused", "declined");
// first text block → JSON.parse → validate (LATEX_SCHEMA) → EngineOutput with
//   version: res.model               // (v2.1) the model that actually answered (fallback incl.)
//   logInfo: { requestedModel: this.model, fallback: res.model !== this.model, inTok, outTok }
```

- (v2.3, C23-02) 모델은 매개변수 `CLAUDE_MODEL`로만 정하고 기본값은 빈 문자열이다. 비어 있으면 등록부가 Claude 엔진을 `notConfigured`(`unavailable`)로 답한다. 모델 이름은 코드·커밋에 쓰지 않고 프로젝트별 `functions/.env.<projectId>`(실연결 미니 라운드, U6)에만 둔다. 어떤 엔진·모델을 쓸지는 비교 도구 결과로 사용자가 정한다(U6, Q1). 비용 추정은 6.8.12.
- 거절(`stop_reason: "refusal"`)에 대비해 서버 쪽 대체(`fallbacks: "default"`)를 기본으로 켠다 — 수식 받아쓰기는 거절될 일이 드물지만 켜는 비용이 없다. (v2.1, SYNC-M7 — 검토 S-8, 계약 7.2.13) 대체가 돌면 답한 모델이 요청한 모델과 다르므로 **`engineVersion` = 응답의 `model`**이다(앱의 `MathObject.engineId` `'claude/<판>'`가 출처를 바르게 남긴다). 대체 여부는 로그에만 남긴다 — 요청 모델과 응답 `model`의 비교, 그리고 SDK 1.1.0 타입이 주는 사용량의 대체 정보(검토가 본 `usage.iterations`의 대체 표시 [추측 — 필드 뜻은 실제 호출로 확인, U6 뒤]).
- 이미지만 받는다(`accepts.strokes = false`). 앱이 PNG를 못 만들면(렌더러 자리 없음 — 05-library 6.11.3) `invalid-argument`가 된다(CP-S3 — LIBRARY 문구 '이 필기는 수식으로 보낼 수 없어요').
- 시험(`test/claude.test.ts` — (수정 2회차) 두 항목으로 나뉘어 있던 것을 하나로 합침): SDK 클라이언트를 4.5의 얇은 이음새 `ClaudeMessagesClient.create(params, opts)` 뒤에 두고(생성자 `client` 인자로 가짜를 넘김) 가짜로 요청 인자(모델·`betas`·`fallbacks`·`output_config`·이미지 블록·`opts.signal`)·응답 해석·거절(`stop_reason: "refusal"` → `refused`)·JSON 아님·스키마 위반·SDK 오류 종류별 변환을 본다. (v2.1, SYNC-M7) '가짜 클라이언트가 요청과 다른 `model`로 답함 → `engineVersion` = 그 값, 로그 `fallback: true`' 경우도 같은 파일에 둔다.

#### 6.8.7 하루 상한 (`QuotaStore`, D-S6)

| 항목 | 값 |
|---|---|
| 상한 | `DAILY_CAP`(`defineInt`, 기본 200, ≤ 0이면 상한 없음) — 사용자(uid)·서울 날짜(UTC+9, 일광 절약 없음)마다 |
| 운영 저장 | `FirestoreQuotaStore`: 최상위 컬렉션 `fnQuota`, 문서 `<uid>_<yyyymmdd>` = `{count, uid, day, expireAt(+2일), updatedAt}`, Admin SDK 트랜잭션(읽기 → `count ≥ cap`이면 거절 → `count + 1`) |
| 규칙 | 1차 `firestore.rules`는 바꾸지 않는다 — `fnQuota`에 맞는 규칙이 없어 클라이언트 접근은 기본 거부되고, Admin SDK는 규칙을 우회한다. 1차 `rules_ownership_test`의 'match 경로 4개' 단언도 그대로다 |
| 정리 | `expireAt`에 Firestore TTL 정책을 켠다(배포 때 — 미니 라운드 체크리스트 6.10) |
| 에뮬레이터·단위 시험 | `MemoryQuotaStore`(`QUOTA_STORE=memory` — `.env.demo-noteapp`). [확인] 에뮬레이터의 함수 작업자는 연속 호출에서 같은 프로세스였다(pid 같음 — 6.8.11) — 그래도 상한 동작은 단위 시험(`quota.test.ts`)으로 확인하고 에뮬레이터에서는 단언하지 않는다 |
| (P-C) 실제 카운터 | Firestore 에뮬레이터(자바 필요, 첫 실행에 jar 내려받기 — 조사 04 6.5 확인)로 `FirestoreQuotaStore`의 트랜잭션·동시 호출 2개를 시험하는 선택 실행(`--only functions,auth,firestore` — 계약 7.4.7 목록 밖이라 CI 기본 잡에는 넣지 않음, CP-S6) |

#### 6.8.8 오류 변환

| 원인 | `HttpsError` 코드 | HTTP [확인 — firebase-functions 7.4.0 `errorCodeMap`] | 앱(05-library 6.11.4) |
|---|---|---|---|
| ID 토큰 없음·검증 실패 | `unauthenticated` | 401 | '로그인한 뒤에 …' |
| 소유자 목록 밖 | `permission-denied` | 403 | '이 계정에서는 …' |
| 입력 검사 실패, 모르는 엔진 이름, `fake` 금지, 엔진이 받지 않는 입력 | `invalid-argument` | 400 | '이 필기는 수식으로 보낼 수 없어요.' |
| 하루 상한 | `resource-exhausted` | 429 | '오늘 쓸 수 있는 수식 인식 횟수를 다 썼어요.' |
| `EngineError`: `notConfigured`·`rateLimited`·`upstream`·`timeout`, 상한 저장소 실패 | `unavailable` | 503 | '수식 인식 서버에 연결할 수 없어요 …' |
| `EngineError`: `badResponse`·`refused`, 출력 검사 실패, 예상 밖 예외 | `internal` | 500 | '수식을 인식하지 못했어요 …' |

- 엔진 쪽 429는 `resource-exhausted`로 보내지 않는다 — 앱 문구가 '오늘 횟수를 다 썼어요'라 사용자를 잘못 안내한다(5.3 표).
- 함수 자체의 30 s 시간 초과는 플랫폼이 끊는다(`DEADLINE_EXCEEDED` — 계약 오류 목록 밖이지만 LIBRARY는 `UNAVAILABLE`과 같이 '연결할 수 없어요'로 본다). 엔진 호출을 25 s로 끊어 정상 경로에서는 일어나지 않게 한다.

#### 6.8.9 매개변수 · 비밀값 · 환경 파일 (F-1)

| 이름 | 종류 | 기본 | 에뮬레이터(`.env.demo-noteapp`, 커밋) | 운영(미니 라운드) |
|---|---|---|---|---|
| `MATH_API_KEY` | `defineSecret` | — | 없음 → 빈 값 + 경고 [확인 6.8.11]. 실제 엔진 시험이 필요하면 개발자가 `functions/.secret.local`(커밋 안 함) | `firebase functions:secrets:set MATH_API_KEY` (Secret Manager). (v2.1, SYNC-M8) **첫 배포 전에** 값이 있어야 한다 — `recognizeMath`가 `secrets: [MATH_API_KEY]`를 묶으므로 엔진이 정해지기 전(`MATH_ENGINE=none`)에도 자리 값(예: `unset`)을 넣는다 [추측 — firebase-tools 배포 검사, 미니 라운드에서 확인] |
| `OWNER_UIDS` | `defineString` | `''`(아무도 못 씀 — 닫힌 기본) | `owner-uid` | 사용자의 실제 uid(로그인 뒤 확인) — (v2.1, SYNC-M8) **커밋하는 `functions/.env.<projectId>`**(uid는 비밀이 아니다). `.env.local`은 에뮬레이터만 읽으므로 거기 두면 배포된 함수의 값이 기본 `''`(아무도 못 씀)이 된다 [문서 기억 — 검토 S-9, 배포 때 확인] |
| `MATH_ENGINE` | `defineString` | `none` | `fake` | 첫 배포는 `none`(503 확인용 — 6.10 L5), 엔진 결정 뒤(U6) 바꿈 |
| `ALLOW_FAKE_ENGINE` | `defineBoolean` | `false` | `true` | `false` |
| `DAILY_CAP` | `defineInt` | `200` | `1000` | `200`(Q2) |
| `QUOTA_STORE` | `defineString` | `firestore` | `memory` | `firestore` |
| `MATHPIX_APP_ID` | `defineString` | `''` | `''` | Mathpix를 고르면 |
| `CLAUDE_MODEL` | `defineString` | `''` (v2.3, C23-02 — 비면 Claude `notConfigured`) | (기본) | 엔진 비교 결과(`.env.<projectId>`) |

- 키는 저장소·앱 어디에도 없다(F-1): `.secret.local`·`.env.local`은 INFRA `.gitignore`(RQ-2), 시험은 키 없이 돈다(가짜 엔진·가짜 `fetch`·가짜 SDK). `functions/test/secrets_hygiene.test.ts`가 저장소의 `functions/` 아래 커밋 대상 파일에 `sk-ant-`·`app_key=`·`MATH_API_KEY=` 값 꼴이 없는지 소스 검사한다(가벼운 안전망).
- `.env.demo-noteapp`은 프로젝트 id가 `demo-noteapp`인 실행(에뮬레이터)에서만 읽힌다. 운영 프로젝트로 배포하면 `.env`(없음)와 `.env.<projectId>`만 쓰인다 — 그래서 운영 값은 `.env.<projectId>`에 둔다(계약 7.4.7 v2.1). 그 파일에는 비밀값을 넣지 않는다(`secrets_hygiene.test.ts`가 `functions/.env*` 커밋 대상 파일도 검사한다).

#### 6.8.10 로그 · 개인정보

- 로그(`firebase-functions/logger`, 구조화)에 남기는 것: uid, 엔진 이름·판, 획 수·점 수·PNG 바이트 수, 결과 코드, 걸린 ms, 상한 사용 수, (Claude) 토큰 수·대체 여부. **남기지 않는 것**: 획 좌표, PNG, LaTeX 결과, 키. 노트 id·제목은 요청에 없다(05-library 6.11.3 — 앱이 보내지 않음).
- 외부 엔진으로 가는 것은 사용자가 고른 수식 영역의 획·PNG뿐이고, 그 전에 앱이 동의 게이트(G-3, `recog.mathConsent`)를 지난다. 서버는 동의를 다시 확인하지 않는다(설정은 앱 쪽 — 서버는 로그인·소유자만).

#### 6.8.11 에뮬레이터 시험 (V13 — SYNC 쪽)과 사용자 만들기 규약

[확인] 2026-11-05 컨테이너 실험(`/tmp/claude-0/plan57-scratch/sync57/probe`, firebase-tools 15.34.2, `app/firebase.json` 모양 = 01-infra 6.14, 소유자 검사를 넣은 골격, `.secret.local` 없음):

| 단계 | 결과 |
|---|---|
| `firebase emulators:exec --only functions,auth --project demo-noteapp ../call.sh` | 전체 16 s(시작·종료 포함). `functions/.env.demo-noteapp`(`OWNER_UIDS=owner-uid`)를 읽음 |
| 사용자 만들기: `POST http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/projects/demo-noteapp/accounts`, 헤더 `Authorization: Bearer owner`, 본문 `{"localId":"owner-uid","email":"owner-uid@example.test","password":"test-password"}` (같은 방법으로 `stranger-uid`) | 지정한 uid로 만들어짐 |
| ID 토큰: `POST …/v1/accounts:signInWithPassword?key=fake-api-key` `{"email", "password", "returnSecureToken": true}` → `idToken` | 함수 검증 로그 `auth: VALID` |
| 토큰 없이 호출 | HTTP 401 `{"error":{"message":"sign-in required","status":"UNAUTHENTICATED"}}` |
| `stranger-uid` 토큰 | HTTP 403 `PERMISSION_DENIED` |
| `owner-uid` + 잘못된 입력 | `INVALID_ARGUMENT` |
| `owner-uid` + 정상 | `{"result":{…}}`, 비밀값 없음 → 경고 `No value found for secret parameter "MATH_API_KEY"`·빈 값(함수는 계속 동작), 두 번 호출 모두 같은 작업자 pid |
| 경고(무해) | 'Firebase Authentication function was not triggered due to emulation error'(사용자 만들기 때) — 차단 함수가 없어 생기는 알림 |

이 결과를 규약으로 고정한다(LIBRARY Q4 답 — Dart 시험도 같은 REST로):

| 규약 | 값 |
|---|---|
| 프로젝트 | `demo-noteapp` |
| 함수 주소 | `http://127.0.0.1:5001/demo-noteapp/asia-northeast3/recognizeMath` |
| 사용자 | `owner-uid` / `owner-uid@example.test`, `stranger-uid` / `stranger-uid@example.test`, 비밀번호 `test-password`. 이미 있으면(`DUPLICATE_LOCAL_ID`·`EMAIL_EXISTS`) 그대로 로그인 — 두 언어의 시험이 같은 에뮬레이터 실행 안에서 순서와 무관하게 돈다 |
| 관리 REST 헤더 | `Authorization: Bearer owner`(Auth 에뮬레이터의 관리 권한 표시) |

`functions/test-emulator/recognize_math.emulator.test.ts`(Node `fetch`, `node:test`):

| # | 경우 | 기대 |
|---|---|---|
| E1 | 토큰 없음 | 401 `UNAUTHENTICATED` |
| E2 | `stranger-uid` | 403 `PERMISSION_DENIED` |
| E3 | `owner-uid` + `{v: 1}`(입력 없음) | 400 `INVALID_ARGUMENT` |
| E4 | `owner-uid` + `{v: 2, …}` | 400 `INVALID_ARGUMENT` |
| E5 | `owner-uid` + `engine: 'fake'` + 획 2개(점 5개) | 200 `latex == "\\frac{2}{5}"`, `engine == "fake"`, `engineVersion == "1"`, `ms ≥ 0` |
| E6 | `owner-uid` + PNG만(67바이트 1×1 PNG) | `latex == "\\sqrt{67}"` |
| E7 | `owner-uid` + `engine: 'auto'` | 가짜 엔진 결과(데모 값 `MATH_ENGINE=fake`) |
| E8 | `owner-uid` + `engine: 'gemini'` | 503 `UNAVAILABLE` |
| E9 | `owner-uid` + 첫 점 (−1, −1) / (−2, −2) | 503 `UNAVAILABLE` / 500 `INTERNAL` |
| E10 | `owner-uid` + `pngBase64` 2,097,153자 | 400 `INVALID_ARGUMENT` |

`scripts/emulator_suite.sh`(= `npm run test:emulator`) — (v2.1, SYNC-M10) 셸 잠금을 따로 두지 않고 INFRA `ws with-heavy-lock`으로 **자기 자신을 다시 실행**한다(계약 7.4.6 '무거운 시험 잠금', 01-infra 4.2·6.13):

```bash
#!/usr/bin/env bash
# npm run test:emulator (cwd functions/). Contract 7.4.6: the container-wide heavy-test lock is
# taken by INFRA's `ws with-heavy-lock` (fixed path /tmp/noteapp-heavy-tests.lock, override
# NOTEAPP_HEAVY_LOCK); it sets NOTEAPP_HEAVY_LOCK_HELD=1 for every child, so an inner
# `ws test -t emulator` does not take it again (no nested deadlock). No bash lock of our own.
# CI (CI=true): one job per runner and no Dart yet at this step of functions.yml → no lock.
set -euo pipefail
fn_dir="$(cd "$(dirname "$0")/.." && pwd)"          # functions/
root="$(cd "$fn_dir/.." && pwd)"
if [[ -z "${NOTEAPP_HEAVY_LOCK_HELD:-}" && "${CI:-}" != "true" ]]; then
  cd "$root"
  exec dart run tool/ws.dart with-heavy-lock -- bash functions/scripts/emulator_suite.sh "$@"
fi
for port in 5001 9099; do                              # risk R9: another agent's emulator
  if command -v ss >/dev/null && ss -ltn "sport = :$port" | grep -q LISTEN; then
    echo "port $port is busy (another emulator?)" >&2; exit 3
  fi
done
cd "$fn_dir"
inner="node --test 'lib/test-emulator/**/*.emulator.test.js'"
if [[ "${1:-}" == "--with-dart" ]]; then             # SYNC + LIBRARY in one emulator run (I-3)
  inner="$inner && (cd .. && dart run tool/ws.dart test --package ink_recognition --run-skipped -t emulator)"
fi
npx firebase emulators:exec --config ../app/firebase.json --only functions,auth \
  --project demo-noteapp "$inner"
```

- 컨테이너: `npm run test:emulator`(SYNC만) 또는 `npm run test:emulator -- --with-dart`(SYNC 노드 시험 + LIBRARY Dart `emulator` 시험을 한 번의 에뮬레이터 실행으로 — 8.3 I-3). 안쪽 `ws test -t emulator`는 `NOTEAPP_HEAVY_LOCK_HELD=1`을 물려받아 잠금을 다시 잡지 않는다 — 검토 X-2의 중첩 교착(바깥 잠금을 쥔 채 안쪽이 자기 잠금을 20분 기다리다 종료 코드 4)이 생기지 않는다. LIBRARY가 따로 돌 때 쓰는 명령(`dart run tool/ws.dart with-heavy-lock -- firebase emulators:exec … "dart run tool/ws.dart test --run-skipped -t emulator --package ink_recognition"` — 05-library L2-I6)과 같은 잠금·같은 넘김이다.
- `with-heavy-lock`은 다른 프로세스가 잠금을 쥐고 있으면 그 PID·시작 시각·명령을 1분마다 출력하며 기다리고, 시간 초과(기본 20분)면 종료 코드 4다(01-infra 4.2). 신호를 받으면 자식 트리를 끝내고 잠금을 푼다. 시작·끝 시각은 잠금 로그(`/tmp/noteapp-heavy-tests.log` — INFRA)와 SYNC 진행 기록에 남긴다.
- CI(`functions.yml`, INFRA — 01-infra 6.14): `npm ci` → `npm test`(시험 수 > 0) → `npm run test:emulator` → flutter-action → LIBRARY Dart `emulator` 시험(따로 `emulators:exec`). `test:emulator` 단계에는 아직 Dart가 없으므로 `CI=true`면 잠금 없이 바로 돈다(5.2 RQ-8). 두 시험이 같은 규약(주소·사용자·가짜 엔진 규칙)을 쓰므로 CI도 `--with-dart` 한 번으로 바꿀 수 있지만, 그 결정과 단계 순서는 INFRA 워크플로의 몫이다.
- 포트 검사는 `ss`가 없으면 건너뛴다(`command -v ss` 가드). 바쁘면 에뮬레이터를 띄우기 전에 종료 코드 3으로 끝낸다(잠금 밖에서 다른 에이전트가 띄운 에뮬레이터 — 위험 R9).
- 에뮬레이터 시험 파일 글롭은 3.4와 같은 따옴표 글롭이다(디렉터리 인자는 Node 22에서 실패 — SYNC-M2).

#### 6.8.12 성능 · 비용

| 항목 | 목표 / 추정 |
|---|---|
| 처리 본문(엔진 제외) | 에뮬레이터에서 가짜 엔진 왕복 중앙값 ≤ 50 ms(실험: 함수 실행 3~20 ms [확인]) |
| 콜드 스타트 | 측정은 배포 뒤(미니 라운드). `minInstances` 0(비용) — 첫 호출이 느릴 수 있음을 앱 시간 제한 35 s가 덮는다 |
| Mathpix | 요청당 약 $0.002, 설정비 $19.99 [추측 — 조사 03 6.1·6.5의 검색 요약, 가격표 원문 미확인] |
| Claude(`CLAUDE_MODEL`로 고른 모델, effort low — 작성 때 가정한 모델 기준) | $4/$20 per MTok. 수식 PNG 하나 ≈ 입력 1,000~1,500 토큰(이미지 ≈ 530 [추측 공식] + 지시문), 출력(생각 포함) 300~1,000 토큰 → 요청당 약 $0.01~0.026, 하루 30개 × 30일 = 월 약 $9~23 [추정]. 더 싼 모델로 바꿀지는 비교 도구 결과로 사용자가 정한다(U6·Q1) |
| Firebase | 호출·계산은 무료 사용량 안으로 본다(개인 사용량), 컨테이너 이미지 저장 소액 — 예산 알림(INFRA 안내서) [추측 — 조사 04 6.2] |
| 남용 상한 | `maxInstances 2` × 30 s, 하루 200회/uid, 소유자 목록 — 토큰이 새도 비용의 상한이 있다 |

### 6.9 수식 엔진 비교 도구 (`functions/tool/math_eval.ts`, P-C)

PLAN F-14 'M7 착수 시 직접 손글씨로 비교해 결정'과 조사 03 6.6 방법을 실행하는 개발자 도구다. 앱·서버 함수와 같은 엔진 어댑터(`src/engines/*`)를 직접 부른다(서버 함수를 거치지 않음 — 키는 개발자 환경 변수). (v2.1, SYNC-M7) 어댑터는 생성자로 키·모델을 받으므로(6.8.4) 도구가 `new MathpixEngine({appId: env.MATHPIX_APP_ID, apiKey: env.MATHPIX_APP_KEY})`·`new ClaudeEngine({apiKey: env.ANTHROPIC_API_KEY, model})`로 만든다 — Firebase 매개변수(`params.ts`)를 읽지 않는다. 결과의 엔진 판 열은 응답의 `version`(Claude는 실제로 답한 모델)이다.

#### 6.9.1 고정 자료 형식 (`tool/fixtures/math/*.json`)

```json
{"id": "frac-01", "tags": ["fraction"], "expected": "\\frac{a+b}{c}",
 "strokes": {"x": [[312.4, 313.1]], "y": [[88.0, 88.6]], "t": [[0, 8]]},
 "png": "frac-01.png", "source": "synthetic"}
```

- `strokes`는 서버 함수 입력과 같은 모양(CP-L8 규칙), `png`는 같은 폴더의 파일(선택). `source`: `synthetic`(저장소에 커밋, 도구 자체 시험용 5개) 또는 `user-<기기>-<날짜>`.
- 사용자 손글씨 표본은 **수식만**, 사용자 동의 뒤 넣는다(U18 기본값 '도형·수식만'). (v2.1, Q4 답 — LIBRARY-M11) 표본을 앱에서 이 형식으로 내보내는 개발자 기능은 **LIBRARY 수식 패드의 고정 자료 모드**(P-C — 05-library 6.14.7, L2-22, 웹 포함)다. EDITOR 도형 표본(`{kind, points, viewScale}`)과는 따로다. 이 절의 형식이 그 출력의 계약이고, 바꿀 때는 LIBRARY에 알린다.

#### 6.9.2 실행과 안전장치

```text
npm run eval:math -- --fixtures tool/fixtures/math --engines fake,mathpix,claude
                     [--claude-model <모델 — 필수, 기본값 없음>] [--limit 60] [--confirm-cost] [--out eval-out/<날짜>]
```

- 키는 환경 변수에서만 읽는다: `MATHPIX_APP_ID`·`MATHPIX_APP_KEY`·`ANTHROPIC_API_KEY`. 결과 파일·로그에 키를 쓰지 않는다.
- 유료 엔진이 하나라도 있으면 시작 전에 '호출 수 × 단가' 최대 추정을 보이고, `--confirm-cost` 없이는 호출하지 않는다. `--limit`(기본 60)을 넘는 호출을 하지 않는다(50개 × 엔진 2개 ≈ 100호출이면 사용자가 명시적으로 올림).
- 동시 호출 2, 엔진 호출마다 25 s 제한(서버와 같은 `ENGINE_TIMEOUT_MS`·같은 신호 주입 — 도구 시험은 `AbortController`로 시간 초과 행을 만든다). 엔진 오류는 그 행의 실패로 기록하고 계속한다.
- 출력 폴더 `eval-out/`은 커밋하지 않는다(RQ-2).

#### 6.9.3 채점

| 열 | 정의 |
|---|---|
| 정확 일치 | `latex.trim() == expected.trim()` |
| 정규화 일치 | `normalizeLatex(a) == normalizeLatex(b)` — 공백 제거, `$…$`·`\[…\]`·`\(…\)` 바깥 떼기, `\left`·`\right` 제거, `\dfrac`·`\tfrac` → `\frac`, 글자 하나짜리 중괄호 `^{2}` → `^2`·`_{i}` → `_i`, 간격 명령(`\,` `\;` `\!` `\ `·`\quad`) 제거, `\operatorname{sin}` → `\sin` |
| 해석 성공 | (선택) `flutter_math_fork`가 읽는가 — Dart 쪽 도구가 필요해 이 TS 도구는 비워 둔다. LIBRARY에 `results.jsonl`을 읽어 `InkMathRenderer.validate`로 채우는 작은 Dart 명령을 요청(Q5) |
| 지연 | 엔진 호출 ms의 중앙값·p90 |
| 실패 | 오류 종류별 건수(6.8.8 `EngineError` 종류) |
| 비용 | Mathpix 호출 수 × $0.002, Claude는 응답 사용량(토큰) × 단가표(도구 안 상수 — 조사 03 6.4와 같은 값, 날짜 표기) |

#### 6.9.4 출력

- `eval-out/<날짜>/results.jsonl`(고정 자료 × 엔진 한 줄씩: `fixtureId`·`engine`·`ok`·`latex`·`expected`·`ms`·`error`·`costUsd`), `summary.md`(엔진별 위 표 — 조사 03 6.6의 결과표 형식, 계획서·진행 기록에 붙임).
- 시험(`tool/test/math_eval.test.ts`): 합성 고정 자료 5개 × 가짜 엔진으로 `summary.md` 전체가 고정 문자열과 같음(결정적), `normalizeLatex` 경우 표 20개, `--confirm-cost` 없이 유료 엔진 → 호출 0으로 끝남, 키 없는 엔진 → 그 엔진 행이 '설정 안 됨'으로 표시.

### 6.10 실연결 미니 라운드 준비 (D16, INFRA와 함께)

미니 라운드(2차 통합 뒤, 사용자가 Firebase 프로젝트를 만든 다음 — 계약 3.3)를 '연결과 확인'만 하는 짧은 라운드로 만들기 위해 이번에 준비하는 것:

| # | 미니 라운드 항목 | 담당 | 이번 라운드에 SYNC가 해 두는 것 |
|---|---|---|---|
| L1 | Firebase 프로젝트·웹 앱·Blaze·예산 알림·Firestore 위치 `asia-northeast3` | 사용자 + INFRA 안내서 | 패키지 README '실연결 체크리스트'에 SYNC가 필요한 설정값(Firestore 색인·규칙·Storage 버킷·TTL) 목록 |
| L2 | 앱이 `sync_engine`에 의존, `SyncModule`(1차 7.3.3 M4 행), `connectivitySignalProvider` | INFRA | 1차 T14 provider·`FirebaseSyncBindings` 그대로 — 2차 변경이 공개 표면을 깨지 않음(`api_surface_test`) |
| L3 | 로그인 화면·리디렉션, 설정 '계정 · 동기화' | INFRA | 1차 `AuthService`. (P-C) `AuthService.idToken`(4.2, CP-S7) — `firebase_auth_mocks`로 시험 |
| L4 | 규칙·색인·Storage 규칙 배포 | INFRA(배포 설정) + SYNC(파일) | (P-C) `functions/test-emulator/rules.emulator.test.ts`: SYNC 소유 설정 `functions/test-emulator/firebase.rules-test.json`(규칙 경로 `../../packages/sync_engine/firebase/*`)로 Firestore·Storage·Auth 에뮬레이터를 띄워, Auth 에뮬레이터 토큰을 단 REST 요청으로 1차 규칙을 실제로 검사(자기 문서 쓰기·남의 uid 거부·청크 필드 검증·같은 id 재쓰기는 `su`만·Storage 크기·sha256 메타). (v2.1, 검토 S-12) firebase-tools가 설정 파일 밖 `../../` 규칙 경로를 읽는지는 확인하지 않았다 [추측 — 조사 04 6.4는 `functions.source`의 `../`만 확인]. 안 되면 시험 스크립트가 임시 디렉터리(`${TMPDIR:-/tmp}/noteapp-rules-test/`)에 규칙 파일을 복사하고 그 안에 설정을 만들어 띄운다. (동시 개발 S2-14 [확인]) firebase-tools 15.34.1은 설정 밖 규칙 경로를 거절한다('is outside of project directory') → `scripts/rules_suite.sh`가 임시 디렉터리 방식으로 띄운다(`npm run test:rules`, R1~R11). Storage 에뮬레이터는 업로드를 모두 `create`로 판정해 '덮어쓰기 금지'와 300 MiB 상한은 배포 뒤 확인으로 남긴다(패키지 README 체크리스트). 1차가 '선택'으로 남긴 '규칙 전체 검증은 에뮬레이터'(1차 진행 기록 T17)를 배포 전에 한다. 자바와 jar 내려받기가 필요해 CI 기본 잡에 넣지 않는다(Q6). 돌릴 때는 `dart run tool/ws.dart with-heavy-lock -- …`로 감싼다 |
| L5 | `recognizeMath` 배포 | SYNC(명령) + 사용자(키·uid) | `functions/README.md` 배포 체크리스트 — (v2.1, SYNC-M8 — 계약 7.4.7 순서, 검토 S-9) **① 비밀값**: `firebase functions:secrets:set MATH_API_KEY`(엔진이 정해지기 전이면 자리 값 — 첫 배포가 그 비밀을 묶는다 [추측 — 배포 검사, 이때 확인]) **② 운영 값 파일**: 사용자가 로그인한 뒤 uid를 확인해 `functions/.env.<projectId>`(`OWNER_UIDS=<uid>`, `MATH_ENGINE=none`, `DAILY_CAP=200`, `QUOTA_STORE=firestore`, `ALLOW_FAKE_ENGINE=false`)를 만들어 **커밋**(uid는 비밀이 아님, `.env.local`은 배포에 쓰이지 않음) **③ 배포**: `firebase deploy --only functions --config app/firebase.json`(RQ-6 `ignore` 확인) + `fnQuota.expireAt` TTL 정책 **④ 확인**: `MATH_ENGINE=none` 상태에서 소유자 계정 호출 → 503 `UNAVAILABLE`(로그인·소유자 검사를 지났다는 뜻), 다른 Google 계정 → 403 `PERMISSION_DENIED`, 로그인 없이 → 401 **⑤ 엔진 설정 뒤**(U6): `MATH_ENGINE`·(Mathpix면 `MATHPIX_APP_ID`)·실제 `MATH_API_KEY`를 넣고 다시 배포 → 실제 엔진 1회. 운영에서는 가짜 엔진을 쓸 수 없으므로(`ALLOW_FAKE_ENGINE=false` — D-S7) 배포 확인을 가짜 엔진으로 하지 않는다 |
| L6 | 앱의 `RecognitionConfig.mathEndpoint`(= 배포 주소 `https://asia-northeast3-<projectId>.cloudfunctions.net/recognizeMath` [추측 — 2세대 callable의 주소 형식, 배포 결과로 확인])·`idTokenProvider` | INFRA | L3의 `idToken` |
| L7 | `cloud_functions 7.0.1`로 바꿀지 | INFRA + SYNC | 판단 재료: 지금 `package:http` 규약 구현이 에뮬레이터에서 동작(V13). App Check를 켤 때만 SDK가 이득 |
| L8 | iOS SwiftPM + CocoaPods 혼합(Firebase + ML Kit) 컴파일 | INFRA | — |
| L9 | 실기기 확인(9.3 C) | 사용자 | 체크리스트 |

### 6.11 웹과 네이티브

- `sync_engine`의 새 코드도 순수 Dart다(1차 `no_dart_io_test`가 계속 검사): 관용 디코드·보관 값은 `dart:convert`(base64·JSON)와 `Uint8List`만, 서버 시각은 µs `int`(2^53 미만 — dart2js에서 정확). Chrome 시험 `test/web/pure_logic_browser_test.dart`에 관용 디코드 경우 표·`HeldRecords` 왕복·새 종류 병합 성질(시드 1..3)을 더한다(VM과 같은 본문 `test/shared/*_cases.dart`).
- iPad 웹은 ML Kit이 없어(계약 7.4.2) 손글씨 결과를 **받기만** 한다. 실연결 뒤 웹의 손글씨 검색은 이 동기화가 유일한 경로다(계약 D7) — S28·H1이 '받은 결과가 검색됨'을 본다.
- 보관 값(키 10개, 키당 ≤ 224 KiB, 합계 ≤ 2 MiB — 6.3.2)은 CORE 메타 KV(웹은 sqlite3 wasm 파일 — 1차)에 들어간다. 1차 `sync.purged.*`(5키, 키당 < 256 KiB)보다 크지만 웹 메모리 예산(계약 7.4.5)에 견주어 작고, 평소에는 비어 있다(모르는 종류가 있을 때만 — 실연결 전에는 0).
- `functions/`는 플랫폼과 무관하다(서버). 앱 쪽 호출 차이(웹은 CORS — callable 기본 허용)는 LIBRARY.

### 6.12 성능 목표

| 항목 | 목표 | 확인 |
|---|---|---|
| `decodeTolerant` (알려진 기록 2,000개 청크) | 1차 `decode` 대비 +5% 이내(VM) | `codec/chunk_codec_test.dart` 측정 단언(느슨하게 ×5 — 검토 S-12) + 진행 기록에 수치 |
| `HeldRecords.encode`/`decode` (가득 찬 값 — 조각 9개 × 224 KiB + 머리, 키 10개) | 목표 각 ≤ 100 ms(VM), ≤ 300 ms(Chrome). (v2.1, 검토 S-12) 단언은 느슨한 상한 ×5(VM ≤ 500 ms, Chrome ≤ 1.5 s)로 두고 실측은 진행 기록에 — 같은 컨테이너에서 다른 영역 시험이 돌면 흔들린다 | `engine/held_records_test.dart`, `test/web/pure_logic_browser_test.dart` |
| `reapplyHeldRecords` (보관 기록 1,000개) | 목표 ≤ 1 s(VM, 가짜 로컬), 단언 ≤ 5 s | `engine/download_pipeline_test.dart` |
| 보관 개수 기준 (v2.1, 검토 S-3 — 수정 2회차에서 정정) | 손글씨 결과 기록 '10 KB(엔티티 JSON) × n': 보관 항목 약 13.8–14.1 KB → 실제 한도 **조각 9개 × 224 KiB = 2,016 KiB**에 조각당 16개, **n ≈ 144**(획 300개 페이지 약 144쪽). 기본값에서 `maxTotalBytes`(2 MiB)는 걸리지 않는다(머리 < 32 KiB — 6.3.2). 획 100개 페이지(약 3.5 KB, 항목 약 5.1–5.4 KB)면 조각당 42–44개, 약 380–400쪽. 넘는 청크는 표시 → 앱 갱신 뒤 되감기 | `held_records_test` '기본 상한 보관 개수': 크기가 같은 10,000 B 손글씨 기록을 청크마다 하나씩 넣고, 기록 하나만 든 값의 조각 길이로 항목 길이 `e`를 잰 뒤 경계 `N = HeldRecords.maxParts × ⌊(defaultMaxPartBytes − 20 + 1) / (e + 1)⌋`(6.3.2 식)를 계산한다 → `N`개 청크는 모두 저장(표시 없음), `N + 1`번째 청크는 기록 0개 저장·표시(`mark.from` = 그 청크 시각), 그때 `encode()` 전체 길이 < `defaultMaxTotalBytes`(총 상한이 걸리지 않음을 확인). `N`·`e` 실측은 진행 기록에(참고 144) |
| 객체 기록 병합 | 1차 획 병합과 같은 규모(단위 계산 한 번 더) | 성질 시험 시간 |
| 시나리오 전체 | ≤ 60 s(VM) | 9장 |
| 서버 함수 단위 시험 | `npm test` ≤ 15 s(빌드 포함) | CI |
| 에뮬레이터 묶음 | ≤ 60 s(시작 포함 — 실험 16 s) | CI·진행 기록 |

### 6.13 오류 처리 요약

| 상황 | 처리 |
|---|---|
| 모르는 종류 기록 | 보관 + `needsAppUpdate`(비차단), 커서 진행, 같은 청크의 알려진 기록은 적용 |
| 보관 상한 초과 | 그 청크는 하나도 저장하지 않고 되감기 표시(청크 단위 전부/전무) — 앱 갱신 뒤 커서 되감기(6.3.2·6.3.5) |
| 다시 적용 중 저장 실패 | 메모리 보관 값 그대로, 같은 세션의 다음 연결에서 다시(`s.heldReapplied` — 잃지 않음), 1차 `localStoreFailure` 규칙 그대로 |
| 다시 적용 기록의 K1 | (v2.1) `sync.heldRecords`에 해제 시각 `ra`와 함께 남음 → K2 단계(`releaseHeld`)에서 다시 적용. `sync.held`는 쓰지 않는다(원래 청크가 압축으로 지워져도 잃지 않음) |
| 깨진 `sync.heldRecords` 값 | (v2.1) 기록을 버리고 **모든 종류 되감기 표시**(`k: ['*']`, `f` = 머리의 가장 이른 보관 시각 또는 0)로 바꿔 곧바로 다시 씀 + 경고 로그 — 앱 갱신 뒤(머리가 깨졌으면 바로) 되감아 다시 받는다(6.3.5) |
| 모르는 `type` 객체 | 일반 기록(C-12) |
| 객체 기록 디코드 실패(알려진 `type`, 필수 키 없음) | 1차 게이트 `malformedRemoteData`(그 기록만) |
| 서버 함수 | 6.8.8 표 |

---
## 7. 외부 패키지

### 7.1 Dart (`packages/sync_engine/pubspec.yaml`) — 변경 없음

1차 그대로다(`note_core: any`, `riverpod 3.4.3`, `web 1.1.2`, `meta 1.19.0`, `collection 1.19.1`, `clock 1.1.3`, `crypto 3.0.8`, `firebase_core 5.1.0`, `firebase_auth 7.0.1`, `cloud_firestore 7.1.0`, `firebase_storage 14.0.1`, `connectivity_plus 7.3.2` / dev `fake_async 1.3.3`, `fake_cloud_firestore 4.5.0`, `firebase_auth_mocks 0.16.0`) [확인 — 1차 작업 트리 pubspec]. 계약 7.5의 기존 잠금 변화 `xml 7.1.0 → 7.0.1`은 `sync_engine`이 직접 쓰지 않는다. R16(피처 패키지에 플러그인 없음)에서 `sync_engine`의 Firebase·`connectivity_plus`는 1차 기존 예외(계약 7.4.1)다.

### 7.2 npm (`functions/package.json`) — 계약 7.5 표의 자기 행

확인: 2026-11-05 `npm view <pkg> time license engines` [확인].

| 패키지 | 판 | 게시일 | 라이선스 | 쓰임 | 비고 |
|---|---|---|---|---|---|
| `firebase-functions` | 7.4.0 | 2026-09-15 | MIT | `onCall`·`HttpsError`·`params`·`logger` | 계약 7.5. 최신과 같음 |
| `firebase-admin` | 14.5.0 | 2026-09-23 | Apache-2.0 | `FirestoreQuotaStore`(Firestore) | 계약 7.5. `engines.node >=22` — Node 22와 맞음 |
| `typescript` (dev) | 6.0.3 | 2026-04-16 | Apache-2.0 | 빌드·검사 | 계약 7.5. 최신 7.0.2는 계약 밖(바꾸지 않음) |
| `@types/node` (dev) | 22.20.5 | 2026-10-01 | MIT | 타입 | 계약 7.5. Node 22 줄기 |
| `firebase-tools` (dev) | 15.34.1 | 2026-10-21 | MIT | `emulators:exec`(npm 스크립트·CI `npx`) | 계약 7.5 (v2.3, C23-01), INFRA R-6. 15.34.2(2026-10-28)는 R2-B7b 때 14일 미만이라 15.34.1로 고정. 올리는 것은 실연결 미니 라운드 때 |
| `@anthropic-ai/sdk` | 1.1.0 | 2026-10-21 | Apache-2.0 | Claude 어댑터(P-C) | (v2.1) **계약 7.5 행 — CP-S5 승인**(P-C Claude 어댑터만, S2-12에서 더함). 의존 `standardwebhooks`·`json-schema-to-ts`·`@opentelemetry/api`, `zod`는 선택 peer(쓰지 않음). 최신 1.5.0(2026-11-04)·1.2.0~1.4.0은 14일 미만. 쓰는 매개변수(`fallbacks`·`output_config`)가 1.1.0 타입에 있다 [확인 — 검토] |

- 시험·HTTP는 Node 내장(`node:test`, `fetch`)이라 추가 dev 의존이 없다. 린터를 두지 않는다(3.4).
- 간접 의존은 `package-lock.json`이 고정한다(`npm ci`). 14일 규칙(계약 7.5)은 직접 의존에 적용하고, 간접 의존은 lock을 만들 때 `npm view`로 14일 미만 판이 끌려오는지 보고 진행 기록에 남긴다(npm은 pubspec처럼 간접 고정을 쓰지 않으므로 필요하면 `overrides`로 내린다 — 그때 총괄에 알림).

### 7.3 넣지 않음

| 후보 | 이유 |
|---|---|
| `cloud_functions`(앱) | 계약 D10 — 실연결 미니 라운드에서 판단 |
| `@google/genai`(Gemini) | 이번에 Gemini 어댑터를 두지 않는다(1.3, Q3) |
| `@firebase/rules-unit-testing`, `firebase-functions-test`, `jest`·`mocha`·`eslint` | 의존을 늘리지 않는다 — 규칙 시험은 에뮬레이터 REST, 함수 시험은 처리 본문 직접 호출(4.5 `createRecognizeMathHandler`)과 에뮬레이터 |
| `zod` | Claude 구조화 출력은 JSON 스키마 + 손 검사로 충분 |

---

## 8. 작업 분해

### 8.1 기반 단계 몫 (계약 7.6.2 R2-B7a·R2-B7b)

`// 계약 v2.3 7.6.2 원문` (SYNC 행 — 순서: R2-B1 → **R2-B7b** → (R2-B2 + **R2-B7a** + R2-B2i 묶음) → R2-B3 → …)

| 단계 | 담당 | 경로 | 내용 | 완료 조건 |
|---|---|---|---|---|
| R2-B7b | SYNC | `functions/` | (v2.1, C-5) `functions/` 골격: `package.json`(정확한 고정, `firebase-tools` devDependency, 스크립트 `build`·`test`·`test:emulator`), `tsconfig.json`, 가짜 엔진, 단위 시험 1개, `.env.demo-noteapp`. Dart와 무관하므로 **R2-B1 바로 뒤에 따로 병합**한다 | `npm ci && npm test`(돌린 시험 수 > 0) |
| R2-B7a | SYNC | `packages/sync_engine/lib/**`, `test/**` | (R2-B2와 한 묶음, 바탕 = B2-α 해시) `EntityKind` switch 4곳·`kindOrder`·`fixtureJson`에 새 두 값을 '노트 범위 일반 기록'으로, `kPageObjectTypeKeys`, `core_json_keys_test` v2 단언(7.2.8) | SYNC 기존 시험 전부. 새 종류 디코드·키 대조 시험(CP-S9)은 B2-β JSON 조각이 들어온 뒤 |

| ID | 작업 | 선행 | 등급 | 완료 조건 (컨테이너에서 실행) |
|---|---|---|---|---|
| B7b | `functions/` 골격(6.4 끝 문단). **R2-B1 바로 뒤 따로 병합**(v2.1, SYNC-M9) | INFRA R2-B1(`app/firebase.json`·`.gitignore`·`functions.yml` 골격·`with-heavy-lock`), `firebase-tools 15.34.2` 14일 경과(2026-11-11~) | P-B | `cd functions && npm ci && npm test`(**시험 수 > 0** — 3.4의 명령: `# tests N`에서 N ≥ 1, `lib/test/fake_engine.test.js`가 돈다 — v2.1, SYNC-M2), `npm run build`가 `tsc --strict` 오류 0, `git check-ignore functions/.env.demo-noteapp`이 아무것도 내지 않음(INFRA `repo_hygiene_test`와 같은 확인). `npm run test:emulator`는 B7b 완료 조건이 아니다(E1~E10은 S2-11) |
| B7a | `EntityKind` 컴파일 패치 + `kPageObjectTypeKeys` + JSON 키 대조 v2 단언(6.4 표 전부) — R2-B2(CORE)·R2-B2i(INFRA)와 **한 묶음** | 작성: CORE **B2-α(T22) 해시**. 키 대조·새 종류 디코드 확인: CORE **B2-β JSON 골든(T20a) 해시**(02-core 8.5 이정표 표) | P-A | **α 위**: `flutter analyze --fatal-infos` 0, `cd packages/sync_engine && flutter test`에서 새 종류 디코드를 거치지 않는 1차 시험 전부. **T20a 위(병합 전 최종)**: `flutter test`(1차 VM 시험 전부 — 통합 HEAD 777개 + B7a가 더한 경우, `scenario` 포함), `flutter test --platform chrome test/web`, `flutter test --run-skipped test/integration/core_json_keys_test.dart`(v2 단언 — CORE 새 골든 9개), `test/model/field_units_test.dart`(종류별 비교), 루트 `dart run tool/ws.dart check`. (수정 2회차, 재검토 항목 1) 이 목록은 모두 T20a 해시에서 판정된다 — 고정 자료(`fixtureJson`·`objectFixture`)가 계약 생성자 + T20a `toJson`이고, B7a 브랜치의 `packages/sync_engine/test/`에 `PageObjectFixtures` 사용이 없다(`grep -rn PageObjectFixtures packages/sync_engine/test` 0줄 — 5.1.5. 1차 시험의 `createFakeNoteStore()`는 v1 동작만 써서 α부터 그대로 돈다). 묶음 병합 뒤: 총괄이 전체 검사(8.3 I-1) |

- 6.4 표의 `core_json_keys_test`·`field_units_test` 행은 B7a가 끝낸다(v2.1, SYNC-M4 — 계약 7.2.8 'JSON 키 대조 v2 … (R2-B7a에서)'). 그래서 S2-1에는 `field_units_test`의 단위 규칙(`wholeUnitExcept`) 부분만 남는다.

### 8.2 동시 개발 단계

순서: B7a → S2-1 → S2-2 → S2-6 → S2-4a → S2-4b → S2-3 → S2-5 → S2-7a → S2-7b → S2-8 → S2-9 → S2-15. `functions/` 줄(B7b → S2-10a → S2-10b → S2-11 → S2-12 → S2-13)은 Dart 줄과 독립이라 세션 사이에 끼워 넣는다. S2-14는 여유가 있을 때. (v2.1, 검토 S-10) 1차 진행 기록이 'T6(가짜 로컬 + 계약 스위트 + `TestDevice` + 하네스)이 크다 — 한 세션을 통째로'라고 적었으므로(1차 `progress/sync.md`) 큰 작업 셋(S2-4·S2-7·S2-10)을 둘씩 나눠 작업 단위가 세션 경계와 맞게 했다. 세션 추정(6~7)은 그대로다.

| ID | 작업 | 선행 | 등급 | 완료 조건 (시험 파일) |
|---|---|---|---|---|
| S2-1 | `FieldUnits` v2: 최종 `keysOf`, `wholeUnitExcept`, `unitsFor`(6.2.2), `FieldMerge` 성질 생성기에 새 종류(모르는 키 섞음) | B7a | P-A | `test/model/field_units_test.dart`(단위 표·판 섞임 반례가 수렴함·모르는 키가 객체 단위에 듦 — 키 표 비교는 B7a가 이미 함), `test/merge/field_merge_test.dart`(새 종류 행 — 6.2.2 동작 표), `test/merge/field_merge_properties_test.dart`(시드 1..20 × 100: 교환·결합·멱등), `test/web/pure_logic_browser_test.dart`(Chrome, 시드 1..3) |
| S2-2 | 범위·정렬·코덱 골든(6.2.3) | B7a | P-A | `test/model/scopes_test.dart`(`handwriting` = 페이지와 같은 순서), `test/codec/chunk_packer_test.dart`(새 종류 정렬·결정성), `test/goldens/chunk_v1_kinds_golden_test.dart`(골든 바이트 = Python 산출 = Dart 인코더) |
| S2-6 | 관용 디코드 + `HeldRecords`(6.3.1·6.3.2) | B7a | P-A | `test/codec/chunk_codec_test.dart`(6.3.1 표의 각 행 — 1차 오류 27종은 그대로 `FormatException`), `test/engine/held_records_test.dart`(왕복·정렬·중복 제거·키 10개 나눔과 조각 경계·**청크 단위 전부/전무: 상한이 청크 중간에서 걸림 → 그 청크는 전부 표시, 이미 저장된 같은 청크 기록도 빠짐**·표시가 덮는 청크는 저장 안 함·`knownChunks`/`dueChunks` 순서·`settle`(`ra`)·**깨진 머리/조각 → 모든 종류 표시**(`f`·`a`)·`takeMarkIfDue`(종류 앎·`'*'` + 앱 갱신·`a` 모름)·(수정 2회차) **기본 상한 보관 개수**: 같은 크기 10,000 B 기록으로 상수와 잰 항목 길이에서 계산한 경계 `N = maxParts × ⌊(maxPartBytes − 20 + 1) / (e + 1)⌋`(참고 약 144)개 저장·`N + 1`번째 청크는 표시·그때 전체 < `maxTotalBytes` — 6.3.2·6.12), `test/web/pure_logic_browser_test.dart`(같은 본문 Chrome) |
| S2-4a | 가짜 저장소·서버 v2(6.5 표의 `fake_sync_store`·`fake_local_store`·`fake_sync_server` 행) | B7a | P-A | `test/testing/fake_local_store_test.dart`(힌트·고아 객체·`contentRevision`·영구 삭제 정리·복구 사본 순서), `test/testing/fake_sync_server_test.dart`(`mergedState` v2 — 관용 디코드, 새 종류 하위 기록 정리), `test/contract/fake_local_store_contract_test.dart`(1차 C-01~C-25 그대로 통과) |
| S2-4b | `TestDevice` v2(4.3)·하네스 `knownKinds`·`restart`·`checkConverged(kinds:)`(한 작업 — v2.1, SYNC-M6) + 계약 스위트 C-26~C-31(6.6)·드라이버 두 벌(가짜·실제 CORE 멤버) | S2-4a | P-A | `test/testing/test_device_test.dart`(도우미의 필드 집합 = CORE C-11), `test/testing/sync_test_harness_test.dart`(`knownKinds` → 옛 앱 보관, `restart` → 같은 저장소·메타 유지, `checkConverged(kinds:)` → 거른 종류의 차이 무시·나머지 차이는 `StateError`), `test/contract/fake_local_store_contract_test.dart`(C-01~C-31), `test/api_surface_test.dart`(`checkConverged`의 `kinds` 인자 포함 — 4.3), 실제 CORE 드라이버는 `flutter analyze`로 컴파일만 |
| S2-3 | 게이트 v2 + lib 범위 요소의 노트 찾기(6.2.4·6.2.7) | S2-1 | P-A | `test/merge/record_gate_test.dart`(영구 삭제 노트의 객체·손글씨 버림, 다른 노트 통과, 'lib' 범위 객체), `test/engine/download_pipeline_test.dart`('lib-scope pageObject' 묶음) |
| S2-5 | 페이지 되살림·영구 삭제 보호 v2(6.2.5·6.2.6) + **손글씨만 실린 청크는 '최근 보냄'에서 뺌**(v2.1, SYNC-M3 — `upload_pipeline.dart` 363) | S2-4b | P-A | `test/merge/page_resurrection_test.dart`((a)·(b) 객체 근거, 객체 수정·손글씨는 근거 아님), `test/merge/purge_guard_test.dart`(보내지 않은 객체 편집 → 사본, **손글씨만 최근에 올림 → 사본 없음**, 대조 **획을 최근에 올림 → 사본 있음**, outbox 손글씨만 → 사본 없음, 사본에 녹음·객체·손글씨), `test/engine/upload_pipeline_test.dart`(**손글씨만 든 커밋 → `onScopesCommitted`에 그 범위 없음**, 획 + 손글씨 한 청크 → 범위 있음, 손글씨 꼬리 청크 + 획 청크 한 그룹 → 범위 있음) |
| S2-7a | 파이프라인 S-13 ①: 관용 디코드를 받기·압축·가짜 서버에 연결, 받을 때 보관(청크 단위)·`needsAppUpdate`(6.3.3·6.3.6·6.3.7) | S2-6, S2-4b | P-A | `test/engine/download_pipeline_test.dart`('S-13 받기' 묶음: 같은 청크의 알려진 기록 적용·커서 진행·문제 1회·재수신 중복 없음·K2 재수신에 새 문제 없음·보관 키가 마지막 적용 호출과 한 트랜잭션), `test/compaction/compactor_test.dart`(모르는 종류 청크 남김·`unknownKindChunks`) |
| S2-7b | 파이프라인 S-13 ②: 다시 적용(`remember: false`·`releaseHolds: false`·K1 → `ra`)·`releaseHeld`의 `ra` 기록·되감기(상한·깨진 값)·attach 위치(세션 플래그)·지표·`debugKnownKinds`(6.3.4·6.3.5·6.3.8) | S2-7a | P-A | `test/engine/download_pipeline_test.dart`('S-13 다시 적용' 묶음 — 6.3.4 시험 ①~⑧: **다시 적용 뒤 원래 청크가 LRU에 없음**, **다시 적용 직후 겹침 재수신된 원래 청크가 정상 디코드·적용(멱등)**, **저장분 + 표시분이 한 청크로 갈리지 않고 갱신 뒤 모든 기록 적용**, K1 → 보관 `ra`·`sync.held` 불변, **K1 + 원래 청크 압축 삭제 → 해제 뒤 적용**, `releaseHolds: false`, 깨진 값 → 되감기), `test/engine/engine_state_test.dart`(attach 순서 load → reapply → catchUp → releaseHeld, **실패 뒤 같은 세션의 재연결에서 다시 시도**, 다시 적용이 `chunksReceived`·`lastRemoteApplyLatency`를 바꾸지 않음, `needsAppUpdate`) |
| S2-8 | 가짜 시나리오 S23~S30 + 무작위 수렴 v2(6.7.1) | S2-1~S2-7b | P-A | `test/scenarios/s23_object_concurrent_edit_test.dart` … `s30_purge_vs_unsent_objects_test.dart`(S27 (a)~(f) — (c) 청크 중간 상한, (e) K1 + 압축, S28 10분 안 '사본 없음'과 대조), `test/scenarios/fuzz_convergence_test.dart`. 시나리오 전체 ≤ 60 s |
| S2-9 | T16-v2 작성(6.7.2) + 실제 CORE 드라이버 확장 | S2-4b, S2-7b (실행: 6.7.2 CORE 선행 작업 표) | P-A | 작성·컴파일: `flutter analyze --fatal-infos`, `flutter test`(integration은 skip). 실행 판정은 8.3 I-2. 6.7.2 표의 CORE 이정표 커밋마다 해당 파일만 `flutter test --run-skipped test/integration/<파일>` 로컬 1회(결과는 진행 기록) |
| S2-10a | 서버 함수 ①: `protocol`·`access`·`registry`(매개변수는 여기서만 — `EngineSettings`)·가짜 엔진(계약 7.6 규칙)·`latex` | B7b | P-B | `npm test`(시험 수 > 0): `test/protocol.test.ts`(6.8.3 표 각 행·경계 값), `test/access.test.ts`, `test/registry.test.ts`('auto'·이름·`fake` 금지·`gemini` → `notConfigured`, `createRegistry(settings, factories)` 주입, 어댑터 파일이 `params`를 import하지 않음 — 소스 검사), `test/fake_engine.test.ts`(계약 7.6 규칙 표 — `version` `'1'`), `test/latex.test.ts` |
| S2-10b | 서버 함수 ②: `MemoryQuotaStore`·`seoulDayKey`·`createRecognizeMathHandler`(`engineSignal` 주입)·`errors`·`log`·위생 시험(6.8.2·6.8.7·6.8.8·6.8.10) | S2-10a | P-B | `npm test`(시험 수 > 0): `test/quota.test.ts`(경계 = cap·서울 자정·cap ≤ 0), `test/handler.test.ts`(처리 순서 — 잘못된 입력은 상한을 쓰지 않음·상한은 엔진 앞·오류 변환 표·출력 검사·**시간 제한 = 주입한 `AbortController.abort()` → `unavailable`**(mock timers 아님 — v2.1, SYNC-M7)·`engineVersion` = 엔진 출력의 `version`), `test/secrets_hygiene.test.ts`(`functions/.env*` 포함) |
| S2-11 | `onCall` 연결(`engineSignal` 기본 = `AbortSignal.timeout`)·`params`·`FirestoreQuotaStore`·`.env.demo-noteapp`·`emulator_suite.sh`(`with-heavy-lock`)·에뮬레이터 시험 E1~E10(6.8.9·6.8.11) | S2-10b | P-B | 컨테이너: `cd functions && npm run test:emulator`(잠금 — `lib/test-emulator/recognize_math.emulator.test.js` E1~E10 통과, `# tests` > 0, 시작~끝 ≤ 60 s, 잠금 대기·시각 진행 기록). CI `functions.yml` 1회(INFRA J16 뒤) |
| S2-12 | Mathpix 어댑터 + Claude 어댑터(CP-S5 승인 — 생성자 주입, `version` = 응답 판, 6.8.6) | S2-10a | P-C | `test/mathpix.test.ts`, `test/claude.test.ts`(가짜 `fetch`·가짜 SDK 클라이언트 — 네트워크 없음, 대체 모델 응답 → `engineVersion` = 응답 `model`·로그 `fallback: true`) |
| S2-13 | 비교 도구 `math_eval.ts`·`eval_score.ts`·합성 고정 자료 5개(6.9 — 어댑터를 환경 변수로 생성) | S2-10a (S2-12 있으면 함께) | P-C | `tool/test/math_eval.test.ts`(요약 고정 문자열·`normalizeLatex` 20경우·`--confirm-cost` 없으면 호출 0·`AbortController`로 시간 초과 행) — `npm test`에 포함 |
| S2-14 | 미니 라운드 준비(6.10): `AuthBackend`·`AuthService`·`FirebaseAuthBackend`·`FakeAuthBackend`의 `idToken`(CP-S7), 패키지 README·`functions/README.md` 체크리스트(L5 다섯 단계), 규칙 에뮬레이터 시험 | S2-11 | P-C | `test/auth/auth_service_test.dart`(`idToken` — 로그아웃 null·`unavailable` null·오류 → null + 로그), `test/firebase/firebase_auth_backend_test.dart`(`getIdToken(forceRefresh)` 위임·오류 변환), `functions/test-emulator/rules.emulator.test.ts`(수동 실행 — Q6, `with-heavy-lock`) |
| S2-15 | 공개 표면·문서·진행 기록 | 모두 | P-A | `test/api_surface_test.dart`(4.2·4.3 추가 멤버, 새 최상위 이름 없음), `test/no_dart_io_test.dart`, `dart run tool/ws.dart check`, `flutter analyze --fatal-infos`, `dart format` 변경 없음, `docs/plans/progress/sync.md` '2차' 절(이정표 대기 표 포함) |

작업량(계약 2.4 단위로 다시 잼): 새 종류 매핑(S2-1~S2-5) 3, 모르는 종류 보류(S2-6·S2-7a·S2-7b) 2.5(v2.1 보강 — 키 나눔·전부/전무·`ra`·깨진 값), 시나리오·계약 시험(S2-4a·S2-4b·S2-8·S2-9) 2.5, 서버 함수(B7b·S2-10a·S2-10b·S2-11) 2.5, 어댑터(S2-12) 0.5, 비교 도구(S2-13) 1, 준비(S2-14) 0.5 → **12.5**(개요 추정 11 — 계약 스위트 확장, 어댑터 시험, v2.1 보관 보강이 늘어난 몫). 세션 추정 6~7(1차 8세션의 약 80%) — 세션마다 위 작업 둘 안팎이 들어간다.

### 8.3 통합 단계 몫

| ID | 시점 (계약 7.7.1) | 할 일 | 완료 조건 |
|---|---|---|---|
| I-0 | 기반 단계 R2-B7b(R2-B1 바로 뒤) | 총괄이 `functions/` 골격을 병합한 뒤 `functions.yml`이 `hashFiles` 가드를 지나 실제로 돈다 | B7b 완료 조건(`npm test` 시험 수 > 0) + CI `functions` 잡 1회. 에뮬레이터 시험 파일은 S2-11에서 생기므로 B7b 시점의 `test:emulator`는 에뮬레이터만 띄우고 `# tests 0`으로 지나간다(실패 아님 — INFRA는 `npm test`의 시험 수만 본다) |
| I-1 | 기반 단계 R2-B2 묶음 | 총괄이 세 브랜치(CORE α+β·SYNC B7a·INFRA B2i)를 병합한 뒤 SYNC 시험 전부 | B7a 완료 조건(T20a 위 — 키 대조 v2 포함) |
| I-2 | 3단계 SYNC 병합 | `dart run tool/ws.dart test --run-skipped -t integration`(SYNC 패키지): 1차 T16 파일 4개(통합 HEAD 42개) + T16-v2 5개 + 계약 스위트 실제 CORE(C-01~C-31) + JSON 키 대조 v2(6.7.2 CORE 선행 작업 표의 이정표가 모두 `main`에 있어야 한다). 실패하면 원인을 나눈다 — CORE 동작(힌트·고아·키 집합·`content_rev`·복사)이면 CORE에 알림(02-core I-2), 가짜가 틀렸으면 `FakeLocalStore`를 고침(1차 5.1.4 원칙 — 계약 문장 기준) | 전부 통과 |
| I-3 | 3단계 함께 | 컨테이너: `cd functions && npm ci && npm test`(시험 수 > 0) `&& npm run test:emulator -- --with-dart`(바깥 `ws with-heavy-lock` 하나가 잠금을 쥐고, 같은 에뮬레이터 실행 안에서 SYNC 노드 시험 E1~E10과 LIBRARY Dart `emulator` 시험(L2-I6)이 돈다 — 안쪽 `ws test`는 `NOTEAPP_HEAVY_LOCK_HELD=1`로 잠금을 다시 잡지 않음). CI `functions.yml` 1회(V13 'CI 반복') | V13 통과(두 언어가 가짜 엔진 값을 같게 단언) |
| I-4 | 8단계 | 통합 태그 전체(`-t integration`, `-t emulator`) 안에서 SYNC 몫 다시 — `emulator`는 계약 7.7.1 8단계 명령(`with-heavy-lock` + `emulators:exec` 안 `ws test -t emulator`)에 SYNC 노드 시험을 같은 실행으로 붙일 수 있다(`emulator_suite.sh --with-dart`) | 통과 |
| I-5 | 9단계 | 실기기 확인은 SYNC 항목 없음(9.3). PLAN 체크리스트 갱신 재료(M4 사전 정비 완료, M7-6 서버 함수 에뮬레이터까지)를 진행 기록으로 총괄에 | 진행 기록 |

---

## 9. 테스트 계획

### 9.1 컨테이너 자동 시험

| 종류 | 위치 | 실행 | 언제 |
|---|---|---|---|
| VM 단위·병합·파이프라인 | `packages/sync_engine/test/**`(integration 제외) | `cd packages/sync_engine && flutter test` | 평소(패키지 단위 — 전체 `ws test`는 체크포인트 때만, 계약 5장) |
| 시나리오(가짜) | `test/scenarios/`(태그 `scenario`, 기본 실행) | 위와 같음 | 평소 |
| 골든 | `test/goldens/`(태그 `golden`, VM) — 1차 `chunk_v1_golden` + 새 `chunk_v1_kinds_golden` | 위와 같음 | 평소 |
| Chrome | `test/web/`(순수 로직 — 코덱·보관 값·병합 성질, Firebase 어댑터 컴파일) | `flutter test --platform chrome test/web` | 체크포인트 |
| 통합(실제 CORE) | `test/integration/`(태그 `integration`, 기본 skip) | `flutter test --run-skipped test/integration/<파일>` | 6.7.2 CORE 선행 작업 표의 이정표마다 해당 파일 로컬 1회, `core_json_keys_test`는 B7a(T20a 뒤)부터, 통합 3·8단계 |
| 서버 함수 단위 | `functions/test/**`, `functions/tool/test/**` | `cd functions && npm test`(따옴표 글롭, 시험 수 > 0 — 3.4) | 평소 |
| 서버 함수 에뮬레이터 | `functions/test-emulator/recognize_math.emulator.test.ts` | `npm run test:emulator`(컨테이너: `ws with-heavy-lock`으로 다시 실행 — 고정 경로 잠금, 한 번에 하나, 시작·끝 시각 기록. CI: 잠금 없이), `-- --with-dart`면 LIBRARY Dart 시험도 같은 실행 | 체크포인트·통합 3단계(컨테이너가 판정 — 계약 7.4.6), CI `functions` 잡에서 반복 |
| 규칙 에뮬레이터(P-C) | `functions/test-emulator/rules.emulator.test.ts` | 수동(자바·jar 내려받기, `with-heavy-lock`) | 미니 라운드 전 1회 |

### 9.2 계약 항목 → 시험

| 계약 | 시험 |
|---|---|
| 7.2.8 표 `pageObject`(범위·힌트·단위·게이트·되살림) | `scopes_test`, `field_units_test`, `field_merge_test`, `record_gate_test`, `page_resurrection_test`, `purge_guard_test`, S23~S25·S30, O1~O5, C-26·C-28·C-29 |
| 7.2.8 표 `handwriting` | `field_units_test`, `record_gate_test`, `page_resurrection_test`(근거 아님), (v2.1) '편집으로 세지 않음' — `purge_guard_test`(최근 보냄·outbox 모두)·`upload_pipeline_test`(손글씨만 든 커밋 → 범위 없음)·S28(10분 안 사본 없음), S25 b, H1~H4, C-27·C-30 |
| 7.2.8 표 `recording` + `title` | `field_units_test`, S29, R1·R2, C-31 |
| 7.2.8 정렬·`blobKeys`·`fmt 1` | `chunk_packer_test`, `chunk_v1_kinds_golden_test`, `chunk_v1_golden_test`(1차 그대로) |
| 7.2.8 S-13 ①~⑤ · 7.3.2 S-13 | ① `chunk_codec_test`·`chunk_v1_kinds_golden_test` ② `held_records_test`(청크 중간 상한 → 전부 표시)·S27 (c) ③ `held_records_test`(키 나눔·깨진 값 → 모든 종류 표시)·S27 (f) ④ `compactor_test`·S27 (d) ⑤ `download_pipeline_test`('S-13 다시 적용' — LRU 밖·겹침 재수신 멱등·`releaseHolds: false`·K1 `ra`·K1 + 압축)·`engine_state_test`(위치·재시도)·S27 (b)·(e), K1·K2 |
| 7.2.8 모르는 `type`(C-12) | S26, U1·U2 |
| 7.2.8 JSON 키 대조 v2 | `core_json_keys_test` v2(B7a), `field_units_test` 종류별 비교(B7a) |
| 7.2.13 형식 · X36 | `protocol_test`, `handler_test`(`engineSignal` 주입 시간 제한, `engineVersion` = 엔진 출력 판), `claude_test`(응답 `model`), E1~E10, LIBRARY `callable_emulator_test` |
| 7.6 가짜 엔진 규칙 | `fake_engine_test`(표 전부), E5~E9, LIBRARY L2-I6(같은 값) |
| 7.3.2 F-1 | `handler_test`(소유자 목록·빈 목록 거절), E1·E2, `secrets_hygiene_test` |
| 7.4.7 CI 명령·글롭·시험 수 > 0 | `npm test`의 따옴표 글롭(3.4), B7b 완료 조건의 `# tests` 검사, `emulator_suite.sh`가 그 명령을 그대로 부름(INFRA `workflows_test`가 워크플로 쪽 인자를 검사) |
| 7.4.6 무거운 시험 잠금 | `emulator_suite.sh`가 `ws with-heavy-lock`으로 다시 실행·`HELD` 넘김(INFRA `heavy_lock_test`·`test_command_test`가 잠금 쪽을 시험) |
| 7.4.7 미니 라운드 순서 | `functions/README.md` 체크리스트(6.10 L5) — 미니 라운드에서 실행 |
| 7.7.2 V13 | 위 E1~E10 + LIBRARY L2-I6(컨테이너, 전역 잠금) + CI 잡 반복 |

### 9.3 실기기 체크리스트

**A. 안드로이드 APK · B. iPad 웹 (이번 라운드)** — SYNC 항목 없음. 실연결 전이라 앱이 `sync_engine`에 의존하지 않고(계약 7.1), 서버 함수도 배포되지 않는다. 계약 7.8 A·B 표에도 SYNC 항목이 없다. 사용자가 할 일은 없다.

**실연결 미니 라운드 뒤** — 모두 Firebase 프로젝트(Blaze)·로그인 뒤다. (v2.1, 검토 S-11) 안드로이드 태블릿이 있는지는 아직 모른다(U2). 그래서 ML Kit이 필요 없는 항목은 **iPad Safari ↔ PC Chrome(웹 ↔ 웹)**으로도 할 수 있게 적고, 안드로이드(또는 TestFlight 뒤 iPad 네이티브)가 꼭 필요한 것은 SC-4 하나다.

| # | 확인 | 기기 | 근거 |
|---|---|---|---|
| SC-1 | 한 기기에서 만든 도형·텍스트 상자·이미지·수식 객체가 다른 기기에 2초 안에 보이고, 반대도 같다 | iPad 웹 ↔ PC Chrome(또는 안드로이드) | PLAN 8장 지표, 7.2.8 |
| SC-2 | 두 기기를 오프라인으로 두고(웹은 개발자 도구 '오프라인' 또는 기기 비행기 모드) 같은 객체를 한쪽은 이동, 다른 쪽은 색 변경 → 연결 → 두 화면이 같다(나중 것) | 웹 ↔ 웹 가능 | 객체 단위 LWW(D3) |
| SC-3 | 한쪽에서 객체 삭제, 다른 쪽에서 같은 페이지에 새 이미지 → 연결 → 객체는 지워지고 새 이미지는 남음. 페이지를 지운 경우 새 객체가 있으면 페이지가 돌아옴 | 웹 ↔ 웹 가능 | 6.2.6 |
| SC-4 | 안드로이드에서 손글씨 자동 인식(색인) → iPad 웹 검색에서 그 손글씨 낱말로 페이지가 찾아짐. (v2.1) 이어서 iPad에서 그 노트를 휴지통 → 영구 삭제하면 안드로이드에 '(복구됨)' 사본이 **생기지 않는다**(SYNC-M3) | **안드로이드 필요**(ML Kit) — 없으면 TestFlight 뒤 iPad 네이티브 | 계약 D7, H1, 6.2.5 |
| SC-5 | 녹음 이름 바꾸기·삭제가 다른 기기에 반영, 다른 기기에서 녹음 재생(파일 내려받기) | 웹 ↔ 웹 가능(웹 녹음 — 7.4.2) | F-16 |
| SC-6 | 이미지 객체의 이미지를 다른 기기에서 처음 열 때 내려받아 보임 | 웹 ↔ 웹 가능 | 1차 에셋 경로 |
| SC-7 | 수식 인식 서버: (v2.1, SYNC-M8) 첫 배포(`MATH_ENGINE=none`) 뒤 소유자 계정으로 수식 인식 → '수식 인식 서버에 연결할 수 없어요'(503 — 로그인·소유자 검사는 통과), **다른 Google 계정**(하나 더 필요)으로 → '이 계정에서는 수식 인식을 쓸 수 없어요'(403). 엔진 설정 뒤 소유자 계정으로 실제 인식 1회 성공 | 웹 하나로 가능 | 6.8, 6.10 L5, F-1 |
| SC-8 | 1차 07-sync 9.2 체크리스트(로그인·실시간·오프라인 양쪽 편집·휴지통·영구 삭제·계정 바꿈) 다시 | 웹 ↔ 웹 가능 | 1차 |

**TestFlight 뒤 (Apple 유료 계정 가입 후 — 2차 완료 조건 아님)**: iOS 네이티브에서 SC-1~SC-7, ML Kit iOS 인식 결과가 웹·안드로이드로 동기화됨(계약 7.8 C-3과 함께).

---

## 10. 완료 기준

2차 SYNC 완료 = 아래 전부(P-A는 필수, P-B는 '해야 하지만 미뤄도 2차 완료', P-C는 여유 — 계약 3.4).

- [ ] (P-A) B7a가 R2-B2 묶음으로 병합된 뒤 1차 SYNC 시험이 VM·Chrome에서 전부 통과하고, JSON 키 대조 v2(`core_json_keys_test`·`field_units_test` 종류별 비교)가 CORE B2-β 골든으로 통과한다. 병합 전 마지막 확인은 CORE T20a 해시 위에서 한다 — (수정 2회차) SYNC 고정 자료가 계약 생성자 + T20a `toJson`이라 T23b(`PageObjectFixtures`)를 기다리지 않는다(5.1.5, 8.1).
- [ ] (P-A) S2-1~S2-9(S2-4a·b, S2-7a·b 포함)·S2-15의 완료 조건 시험이 통과한다(9.1의 VM·Chrome·골든·시나리오). 특히 S-13 '어느 경로로도 잃지 않음'(청크 중간 상한·겹침 재수신·K1 + 압축·깨진 값 — S27 (c)·(e)·(f))과 손글씨 '편집 아님'(S28 10분 안 사본 없음).
- [ ] (P-A) 통합 3단계에서 T16-v2(실제 CORE v2 두 개: 객체 동시 편집·삭제 대 수정·모르는 `type` 왕복·모르는 `kind` 보류·손글씨 결과·녹음 이름)와 계약 스위트 C-01~C-31(실제 CORE), JSON 키 대조 v2가 통과한다.
- [ ] (P-A) 공개 표면 변화가 4.2·4.3의 '추가'뿐이다(`api_surface_test`), `no_dart_io_test`·`ws check`·`flutter analyze --fatal-infos` 0.
- [ ] (P-B) `functions/`: `npm ci && npm test` 통과(**돌린 시험 수 > 0**), 에뮬레이터 시험 E1~E10 통과(컨테이너 — `ws with-heavy-lock` 전역 잠금), CI `functions` 잡 1회 통과(V13 — LIBRARY Dart 시험과 같은 가짜 엔진 값).
- [ ] (P-B) 저장소·앱에 외부 키가 없다(`secrets_hygiene` 시험, `.gitignore` RQ-2).
- [ ] (P-C) Mathpix·Claude 어댑터 가짜 응답 시험(`engineVersion` = 실제 응답 판), 비교 도구 시험, `AuthService.idToken`, 규칙 에뮬레이터 시험(수동 1회), `functions/README.md` 미니 라운드 배포 체크리스트(6.10 L5 다섯 단계).
- [ ] 진행 기록 `docs/plans/progress/sync.md` '2차' 절(작업 표·커밋·계획과 다르게 한 점·에뮬레이터 실행 시각).

---

## 11. 리스크와 대응

| # | 리스크 | 영향 | 대응 |
|---|---|---|---|
| R1 | CORE DB v2·행 변환·동기화 창구 v2와 저장소들(T24·T26~T33)이 늦음 | T16-v2를 동시 개발 중에 돌려 볼 수 없음 | 가짜 `FakeLocalStore` v2 + 같은 계약 스위트로 개발(1차와 같음). (v2.1) 6.7.2 CORE 선행 작업 표대로 이정표 커밋(02-core 8.5)마다 해당 파일만 로컬 1회 실행해 어긋남을 일찍 찾는다. 판정은 통합 3단계 |
| R2 | 가짜와 실제 CORE의 어긋남(고아 객체 입양 시점, `contentRevision`, 복사 순서, `title` 키) | 가짜 시나리오는 통과하는데 실제에서 실패 | 계약 스위트 C-26~C-31을 두 쪽에 같은 본문으로. 다르면 계약 문장 기준으로 판단(1차 5.1.4) |
| R3 | (v2.1 닫힘) CP-S1('나머지 전부' 단위)이 받아들여지지 않음 | — | CP-S1 승인 — 계약 7.2.8 문장이 되었다. 남은 일: 다음 라운드에 객체 키를 더할 때 따로 단위를 만들지 않는다(계약 문장) |
| R4 | `sync.heldRecords` 값 손상·상한 초과 | 모르는 종류 기록 손실 | (v2.1) 청크 단위 전부/전무 + 넘치면 되감기 표시(바이트 없이도 다시 받음), 키 10개로 나눠 2 MiB까지, 깨진 값은 모든 종류 되감기 표시, 다시 적용은 LRU 밖, K1 기록은 보관에 남음, 압축은 그런 청크를 지우지 않음. 형식 시험(왕복·조각 경계·깨진 값)과 S27 (c)·(e)·(f) |
| R5 | 모르는 종류 청크가 압축에서 계속 남음 | 그 범위가 줄지 않음 | 새 종류는 모든 기기를 갱신하면 '알려진 종류'가 되어 다음 압축에서 정리된다. 1차 `markAttempted`(24 h 간격)로 다시 읽기 비용을 제한 |
| R6 | 손글씨 결과 한 단위 LWW가 사용자가 고친 줄(`userConfirmed`)을 다른 기기의 자동 재인식으로 덮음 | 변환 창에서 고친 글이 검색에서 사라짐 | 단일 사용자에서 드묾(두 기기가 같은 페이지를 동시에 인식해야 함). 색인기는 로컬에서 `userConfirmed`를 지킨다(계약 7.2.5). 줄 단위 병합은 다음 라운드(Q7) |
| R7 | Node 22 런타임 지원 종료(2027-04-30 예정)·firebase-functions 판이 배포 없이 낡음 | 미니 라운드 재작업 | CI 에뮬레이터 시험을 계속 돌리고, 미니 라운드에서 판을 다시 확인(계약 위험 12) |
| R8 | Mathpix·Claude 요청·응답 모양이 추측(문서 원문 미확인) | 실제 호출에서 실패 | 어댑터는 P-C이고 가짜 응답 시험뿐임을 명시. 계정이 생기면 비교 도구로 1회 실호출해 고정 자료(응답 표본)를 갱신 |
| R9 | 에뮬레이터 시험이 컨테이너에서 다른 에이전트와 포트(5001·9099)·CPU를 다툼 | 잘못된 실패·부하 | 고정 경로 전역 잠금(`ws with-heavy-lock` — RQ-5, 중첩은 `NOTEAPP_HEAVY_LOCK_HELD`로 넘김), 시작 전 포트 확인(`ss -ltn` — 바쁘면 종료 코드 3), 판정은 컨테이너 + CI 반복(계약 7.4.6) |
| R10 | `firebase-tools`를 devDependency로 두어 `npm ci`가 무거움(수백 패키지) | CI 시간 | `setup-node` npm 캐시(01-infra 6.14). 컨테이너는 한 번 설치 |
| R11 | 토큰 유출 등으로 서버 함수가 남용됨 | 엔진 비용 | 소유자 UID 목록(닫힌 기본), 하루 상한, `maxInstances 2`, 25 s 제한, 예산 알림(PLAN 6.3) |
| R12 | (v2.1 닫힘) CP-S5(`@anthropic-ai/sdk`) 미승인 | — | CP-S5 승인(계약 7.5). 남은 위험: 간접 의존이 14일 미만 판을 끌어오면 lock을 만들 때 `overrides`로 내리고 총괄에 알린다(7.2) |
| R13 | `knownKinds` 시험 훅이 운영 경로에 영향 | 잘못된 보관 | 내부 인자·`@visibleForTesting` 세터뿐, 공개 생성자(`SyncEngine(...)`)는 그대로. 기본값은 `EntityKind.values` |
| R14 (새) | 손글씨만 실린 청크를 '최근 보냄'에서 빼서(D-S11), 손글씨만 올린 기기에서 노트가 영구 삭제될 때 그 기기의 손글씨 결과가 사본 없이 사라짐 | 파생 데이터 손실(획에서 다시 만들 수 있음) | 의도한 동작(검토 M-3 — 사용자가 지운 노트를 되살리지 않는 쪽을 택함). 획·객체가 같은 청크에 있으면 1차처럼 센다. S28·SC-4로 확인 |
| R15 (새) | 미니 라운드 배포 순서의 [추측](첫 배포 전 비밀값 필요, `.env.local` 배포 미사용, `--dry-run`)이 틀림 | 배포 실패·소유자 목록 빈 값 | 6.10 L5 순서는 안전한 쪽(비밀값 먼저, 운영 값은 커밋 파일)이라 틀려도 손해가 없다. 배포 뒤 확인(503·403·401)으로 소유자 목록이 들어갔는지 바로 안다 |
| R16 (새) | `emulator_suite.sh`가 `CI=true`일 때 잠금을 건너뜀 — 컨테이너에서 누가 `CI=true`를 넣고 돌리면 잠금 없이 돔 | 다른 에이전트 시험과 겹침 | 컨테이너 명령에는 `CI`를 넣지 않는다(진행 기록 양식). 포트 검사가 같은 에뮬레이터 겹침은 막는다 |

---

## 12. 총괄에게 묻는 질문 · 계약 변경 제안

### 12.1 계약 변경 제안 — (v2.1) 모두 판정됨

v2.0 초안의 제안 9개는 총괄 검토에서 모두 받아들여졌다(00-review 2.2 — CP-S2는 보강해서). 아래 표는 기록으로 남기고, 마지막 열에 v2.1 판정과 계약 위치를 적는다. 새 제안은 없다 — 이번 수정의 변경은 모두 v2.1 계약 문장 안이다(13장).

| # | 7장 | 제안 | 분류 | 영향 | 이유 | v2.1 판정 |
|---|---|---|---|---|---|---|
| CP-S1 | 7.2.8 표 | `pageObject`의 '객체 단위 하나'를 '메타 키와 `pageId`·`deletedAt`·`engine`을 뺀 나머지 키 전부(모르는 키 포함)', `handwriting`의 '하나'를 '메타 키와 `noteId`·`pageId`·`deletedAt`을 뺀 나머지 전부'로 적는다. 알려진 키로는 원문 목록과 같다. 덧붙여 ① 'JSON 키 대조'는 `pageObject`에서 '알려진 4종 키의 합집합 = `keysOf`, 각 종류 키 ⊆ `keysOf`' ② 이후 라운드에 두 종류에 키를 더할 때 따로 단위를 만들지 않는다 | 규칙 | CORE(설명만 — 코드 영향 없음), SYNC | 목록 밖 키를 1차 기본 규칙(각자 단위)으로 두면 판이 다른 앱끼리 승자가 갈려 영구 불일치가 생긴다(6.2.2 반례). 원문 '`toJson` 키 집합 = `keysOf`'는 `type`마다 키가 달라 문자 그대로는 성립하지 않는다 | 승인 — 7.2.8 표 `pageObject`·`handwriting` 행, JSON 키 대조 v2 문장(C21-12) |
| CP-S2 | 7.2.8 S-13 | ① 보관 단위는 기록 바이트(헤더 JSON = rawJson + 이진 필드) ② 메타 값 상한(200 KiB)을 넘으면 그 종류·가장 이른 청크 시각만 남기고 앱 갱신 뒤 커서를 되돌려 다시 받는다 ③ 압축은 모르는 종류 기록이 든 청크를 지우지 않는다 ④ '시작 시'를 '로그인 상태로 연결할 때, 받기 전에'로, 다시 적용은 기존 `sync.held`를 풀지 않는다 | 규칙 | SYNC만 | 원문만으로는 새 종류의 이진 필드를 잃고, 메타 값 256 KiB 규칙 때문에 무한히 보관할 수 없으며, 옛 앱의 압축이 새 앱 데이터를 지울 수 있다 | **수정해서 승인** — ①~⑤로 보강: 청크 단위 전부/전무, 메타 키 나눔(키당 < 256 KiB·총 2 MiB), 깨진 값 → 모든 종류 되감기, LRU에 넣지 않음, K1 기록은 보관에 남김(C21-12, CD2-21) |
| CP-S3 | 7.2.13 | 주석으로: ① `engine` 생략 = `'auto'` = 서버 `MATH_ENGINE`, `'fake'`는 데모 설정(`ALLOW_FAKE_ENGINE`)에서만 ② `v` ≠ 1 → `invalid-argument`, 모르는 입력 키 무시 ③ `unavailable` = 엔진 미설정·엔진 일시 장애(엔진 429 포함), `internal` = 엔진 응답 해석 실패·거절 ④ 엔진이 받지 않는 입력(이미지 전용 엔진에 획만) → `invalid-argument` ⑤ `strokes.t` = 첫 획 첫 점부터 정수 ms, 좌표 페이지 pt(05-library CP-L8 지지) ⑥ 가짜 엔진 출력 규칙(6.8.5)을 계약 시험 도우미 문장으로 | 규칙 | LIBRARY(문구 선택 — 이미 6.11.4 표와 같음) | 두 언어의 에뮬레이터 시험이 같은 값을 단언하고, LIBRARY 오류 문구가 원인과 맞게 | 승인 — 7.2.13 `rules` 주석, ⑥은 7.6 가짜 엔진 블록(C21-17·C21-30) |
| CP-S4 | 7.4.7 | 에뮬레이터 규약: 사용자 `owner-uid`·`stranger-uid`(Auth 에뮬레이터 관리 REST `Authorization: Bearer owner` + `localId`), 커밋하는 `functions/.env.demo-noteapp`(데모 값만 — `OWNER_UIDS=owner-uid`, `MATH_ENGINE=fake`, `ALLOW_FAKE_ENGINE=true`, `QUOTA_STORE=memory`, `DAILY_CAP=1000`). `.gitignore`는 이 파일을 무시하지 않는다 | 규칙 | INFRA(`.gitignore`·`functions.yml`), LIBRARY(Dart 시험) | [확인] 실험으로 동작을 봤다(6.8.11). LIBRARY Q4 | 승인 — 7.4.7(C21-27) |
| CP-S5 | 7.5 | npm `@anthropic-ai/sdk 1.1.0`(Apache-2.0, 2026-10-21) 을 `functions/` 전용 의존으로 추가(P-C — Claude 어댑터). 기반 단계 때 14일이 지난 더 새 판이 있으면 그 판으로 다시 확인 | 규칙(의존 추가) | SYNC만(앱 의존 아님) | 계약 7.5 표에 없는 의존. 공식 SDK로만 구현한다(직접 HTTP 구현 안 함) | 승인 — 7.5 행(C21-28) |
| CP-S6 | 7.4.7 | 하루 상한 저장 = Firestore 최상위 `fnQuota`(규칙 파일 변경 없음, 클라이언트 기본 거부, TTL `expireAt`). 에뮬레이터 기본 실행(`--only functions,auth`)은 `QUOTA_STORE=memory`, (P-C) Firestore 에뮬레이터를 더한 선택 실행으로 실제 카운터 시험 | 규칙 | INFRA(미니 라운드 TTL 설정 안내) | 원문 '(daily cap per uid, Firestore counter)'와 에뮬레이터 목록 `functions,auth`가 서로 맞지 않는다(Firestore 에뮬레이터 없이는 실제 카운터를 쓸 수 없음) | 승인 — 7.2.13 `rules` 주석(C21-17) |
| CP-S7 | 1차 7.2.20 표면 | `AuthBackend.idToken({bool forceRefresh})`·`AuthService.idToken(...)` 추가(P-C) — 미니 라운드에서 `RecognitionConfig.idTokenProvider`를 채움 | 추가 | INFRA(미니 라운드) | 1차 `AuthService.refreshSession()`은 `@internal`이고 토큰을 돌려주지 않는다 | 승인(P-C) |
| CP-S8 | 1차 7.2.20 표면 | 시험 표면 추가: `SyncEngineDebug.heldRecords`(기본 0), `SyncTestHarness.device(knownKinds:)`·`restart(name)`, `TestDevice` 편집 도우미(4.3) | 추가 | 없음(SYNC 시험만) | S-13·새 종류 시나리오 | 승인 + `checkConverged(…, kinds:)`(4.3 — SYNC-M6) |
| CP-S9 | 7.6.2 R2-B7 | R2-B7 완료 조건에 'SYNC 시험 고정 자료(`entity_fixtures`)의 새 두 종류가 CORE `EntityJson.decode`를 지난다'를 적고, 그 전제로 R2-B2의 `PageObject.fromJson`·`HandwritingText.fromJson`·`Recording.title`(`toJson`이 `title`을 항상 씀 — 02-core CP-7)이 기반 단계에서 동작함을 명시 | 규칙 | CORE | `EntityKind.values`를 도는 SYNC 시험 5개가 새 종류의 디코드를 요구한다(6.4 표 마지막 행) | 승인 — 7.6.2 R2-B7a 완료 조건(디코드·키 대조는 B2-β JSON 뒤 — C21-29) |

### 12.2 질문 — (v2.1) 모두 답을 받음(00-review 3.7 '질문 답')

| # | 질문 | 기본 진행 | v2.1 답 (반영) |
|---|---|---|---|
| Q1 | Claude 어댑터의 기본 모델을 특정 모델로(effort `low`, 요청당 약 $0.01~0.026 추정)로 두고 매개변수로 바꿀 수 있게 하는 것 — 엔진·모델 결정은 비교 도구 결과로 사용자가(U6) | 그렇게 한다 | 그렇게 한다 — 모델은 매개변수, 엔진·모델 결정은 U6 뒤(6.8.6). (v2.3, C23-02) 기본값은 빈 문자열로 바뀜 |
| Q2 | 하루 상한 `DAILY_CAP` 기본 200회/uid가 적당한가(하루 수식 30개 가정의 약 7배) | 200 | 200(6.8.7) |
| Q3 | `engine: 'gemini'`를 이번에 구현하지 않고 `unavailable`로 두는 것(Gemini는 Firebase AI Logic — 앱 쪽 — 이 자연스러움) | 구현하지 않음 | 구현하지 않음(1.3) |
| Q4 | 수식 고정 자료(6.9.1 형식)를 앱에서 내보내는 개발자 기능을 LIBRARY 수식 입력 패드(또는 EDITOR 개발자 메뉴 E2-24)에 요청해도 되는가 | LIBRARY에 P-C로 요청 | LIBRARY 수식 패드의 P-C 개발자 동작(LIBRARY-M11 — 05-library 6.14.7, 6.9.1) |
| Q5 | 비교표의 '해석 성공' 열을 채울 작은 Dart 명령(`results.jsonl` → `InkMathRenderer.validate`)을 LIBRARY(`ink_recognition/tool/`)에 둘지 | 이번에는 빈 열 — 실제 비교 실험(계정 뒤) 때 결정 | 빈 열(6.9.3) |
| Q6 | 규칙 에뮬레이터 시험(자바·jar 내려받기)을 CI에 넣을지 | 수동(미니 라운드 전 1회) | 수동(6.10 L4) |
| Q7 | 손글씨 결과 한 단위 LWW로 사용자가 확정한 줄이 다른 기기의 자동 재인식에 덮일 수 있는 것을 이번에 받아들이는가 | 받아들임(R6) — 다음 라운드에 줄 단위 검토 | 받아들임 — 같은 기기 안 경합은 LIBRARY 확정 줄 규칙 + CORE `update`(G-4)가 막고, 기기 간 LWW는 다음 라운드(R6) |
| Q8 | `firebase-tools 15.34.2`는 1차 고정값이지만 게시일이 2026-10-28이다(오늘 기준 8일). R2-B7 시점(1차 통합 뒤)에는 14일이 지난다 — 그대로 두는가 | 그대로(1차 고정값, R2-B7 때 다시 확인) | 그대로, R2-B1·R2-B7b 때 14일 재확인(3.4, 7.2). (v2.3, C23-01) R2-B7b 때 14일 미만이라 15.34.1로 고정 |
| Q9 | 운영 `OWNER_UIDS`를 커밋하는 `functions/.env.<projectId>`에 둘지(uid는 비밀이 아님), 배포 때 `.env.local`로 넣을지 | 미니 라운드에서 결정 — 기본은 커밋하지 않는 `.env.local` | **커밋하는 `functions/.env.<projectId>`**(SYNC-M8 — 기본값을 바꿈, 6.8.9·6.10 L5) |

검토 질문(reviews/sync.md)의 답: Q-1 'LRU에 넣지 않음'과 '청크 단위 전부/전무' **둘 다**(6.3.2·6.3.4) · Q-2 손글씨만 올린 범위를 '최근 10분 보냄'에서 빼는 것에 **동의**(1차 T11 결정 ① 변경 승인 — 6.2.5) · Q-3 안드로이드 태블릿 여부는 U2(사용자 질문) — 9.3에 웹 ↔ 웹 대체 경로 · Q-4 **커밋**(Q9와 같음) · Q-5 B7b를 R2-B1 바로 뒤 따로 병합 — **된다**(R2-B7b, 6.4·8.1).

---

## 13. 검토 반영 내역

13.1~13.3은 수정 1회차, 13.4는 수정 2회차다.

수정 1회차(2026-11-05). 기준: 총괄 검토 [00-review.md](00-review.md) 3.7(SYNC-M1~M10)·2.1 공통 결정·2.2 CP 판정·2.3 X-/C- 판정, 대리 검토 [reviews/sync.md](reviews/sync.md), 통합 계약 v2.1(00-overview 7장, 변경 이력 7.9 C21-01~35 중 SYNC 몫 — 1.6 둘째 표). 계약 블록은 v2.1 원문을 글자 그대로 다시 옮겼다(4.1 — 7.2.8·7.2.13·7.6 가짜 엔진·7.3 SYNC 행·7.4.7, 5.1 — 7.2.2·7.2.4·7.2.5·7.2.7·7.6, 5.2 — 7.4.6, 5.3 — 7.2.11, 8.1 — 7.6.2 SYNC 행). 프로그램으로 각 블록이 00-overview 안에 그대로 있는지 대조했다(차이 없음).

### 13.1 반드시 고칠 것 (SYNC-M1~M10)

| # | 무엇을 어떻게 바꿨나 | 위치 |
|---|---|---|
| SYNC-M1 (검토 M-1) | ① 다시 적용 호출은 세션 LRU에 넣지 않는다 — `_apply`에 내부 인자 `remember: false`(1차 `keep()` 520–528의 LRU 갱신을 끔)를 두고, 다시 적용·`ra` 해제 두 경로가 쓴다. 왜 필요한지(합성 청크가 원래 청크 id → 뒤이은 받기가 중복으로 건너뜀 → 표시분 손실)를 6.3.4에 적었다. ② `HeldRecords.add`를 **청크 단위 전부 또는 전무**로 바꿨다 — 다 들어가지 않으면 그 청크는 하나도 저장하지 않고(이미 저장된 같은 청크 기록도 뺌) 표시에만 올린다. 표시가 이미 덮는 청크는 저장하지 않는다. ③ 시험 4가지: `held_records_test` '상한이 청크 중간에서 걸림 → 그 청크는 전부 표시', `download_pipeline_test` '저장분 + 표시분이 같은 청크 → 갱신 뒤 모든 기록 적용'·'다시 적용 직후 겹침 재수신된 원래 청크가 정상 디코드·적용(멱등)'(+ '다시 적용 뒤 원래 청크가 LRU에 없음'), S27 (c)를 '작은 상한으로 C2가 갈릴 모양 → 전부 표시 → 갱신 뒤 C1·C2 모두 적용'으로 다시 썼다. 검토 Q-1 답(둘 다)을 6.3.4에 이유와 함께 | 1.5 D-S2·D-S4, 4.1 해석 표 ②·⑤, 4.4 `HeldRecords.add`·`reapplyHeldRecords`, 6.3.2, 6.3.4(의사 코드·시험 ①~③), 6.3.5, 6.7.1 S27 (c), 8.2 S2-6·S2-7b, 9.2 |
| SYNC-M2 (검토 M-2) | `npm test` = `npm run build && node --test 'lib/test/**/*.test.js' 'lib/tool/test/**/*.test.js'`(따옴표 글롭). 에뮬레이터 글롭 `'lib/test-emulator/**/*.emulator.test.js'`. [확인] Node 22.23.4에서 다시 실험했다(`/tmp/claude-0/plan57-scratch/sync57r`): 따옴표 글롭 2/2 통과, 단위 글롭이 `*.emulator.test.js`를 잡지 않음, **맞는 파일이 없는 글롭도 `# tests 0`·종료 코드 0** — 그래서 B7b 완료 조건에 '`# tests N`에서 N > 0'을 명령(`grep -Eq '^# tests [1-9][0-9]*$'`)으로 넣었다(파이프 출력은 TAP이라 그 줄이 나온다). RQ-4 문장의 디렉터리 인자를 고쳤다. S2-10a·S2-10b·S2-11 완료 조건에도 같은 검사 | 3.4, 5.2 RQ-4, 6.8.11 스크립트, 8.1 B7b, 8.2, 9.1, 9.2, 10 |
| SYNC-M3 (검토 M-3) | `UploadPipeline` 커밋 처리(`upload_pipeline.dart` 363)가 `onScopesCommitted`에 넘기는 범위에서 **`handwriting` 기록만 실린 청크**를 뺀다(판정 = 청크의 `PackItem.record.ref.kind`). 1차 T11 결정 ①('노트 범위 청크면 무엇이든') 변경 — 총괄 승인(CD2-12, 검토 Q-2 동의)을 D-S11로 적었다. 6.2.5 문구를 '손글씨 결과는 outbox·최근 보냄 모두 편집으로 세지 않는다'로 고치고, 옛 문장('손글씨만 올린 노트도 최근 보냄으로 세게 되는데 … 드묾')을 지우고 iPad(웹) + 안드로이드(색인기) 시나리오로 이유를 적었다. 시험: `purge_guard_test` '손글씨만 최근에 올림 → 사본 없음'·대조 '획을 최근에 올림 → 사본 있음'(+ outbox 두 경우), S28을 가상 시간 2분 뒤(10분 안) 영구 삭제로 다시 써 '사본 없음'과 대조(획)를 단언, `upload_pipeline_test` '손글씨만 든 커밋 → 범위 없음'(+ 획 섞인 청크·꼬리 청크 두 경우) | 1.5 D-S11, 2장 F-07 행, 3.1 트리, 4.1 해석 표, 4.4 `upload_pipeline.dart`, 6.1, 6.2.5, 6.7.1 S28, 8.2 S2-5, 9.2, 9.3 SC-4, 11 R14 |
| SYNC-M4 (검토 M-4) | `core_json_keys_test` v2 단언(알려진 4종 골든 키 합집합 = `keysOf(pageObject)`, 각 골든 키 = `kPageObjectTypeKeys[type]`, `unknown`은 키 대조에서 빼고 `SyncDoc` 왕복만, 손글씨·녹음 = `keysOf`)을 **B7a로 옮겼다**(계약 7.2.8 '(R2-B7a에서)'). 6.4 표의 그 행('컴파일만')을 'v2 단언을 B7a에 넣는다'로 바꿔 8.1 완료 조건(`--run-skipped …core_json_keys_test.dart` 실행)과 같게 했다. `field_units_test`의 'the CORE key table matches what CORE entities serialize'(통합 HEAD 77행)도 6.4 표에 따로 한 행을 두어 **종류별 비교**(4종 고정 자료마다 `kPageObjectTypeKeys[type]`, 합집합 = `kCoreJsonKeys[pageObject]`, `unknown` 제외)로 바꾼다고 적었다. 6.7.2 표의 `core_json_keys_test` 행은 'B7a가 만들고 T16-v2는 다시 돌리기만'으로 | 6.4 표, 6.7.2 표, 8.1 B7a, 8.2 S2-1(키 표 부분은 B7a), 9.2, 10 |
| SYNC-M5 (검토 S-1·S-3 승격) | ① 다시 적용 중 K1에 걸린 기록은 `sync.held`에 넣지 않고 `sync.heldRecords`에 해제 시각 `ra`와 함께 남긴다 — D-S4의 '원래 청크 id로 `sync.held`' 규칙을 지웠다. 다시 시도는 K2 해제 단계(`releaseHeld`)의 `dueChunks(g′)`. 검토 S-1의 손실 경로(옛 앱 보관 → 새 앱 압축 → 원래 청크 삭제)를 6.3.4에 적고 시험 '다시 적용 K1 + 원래 청크 압축 삭제 → 해제 뒤 적용'(`download_pipeline_test` ⑤, S27 (e))을 더했다. ② 메타 키 나눔: 머리 `sync.heldRecords` + 조각 `sync.heldRecords.1`~`.9`, 조각 ≤ 224 KiB(< 256 KiB), 합계 ≤ 2 MiB. ③ 깨진 값 → 기록을 버리고 **모든 종류 되감기 표시**(`k: ['*']`, `f` = 머리의 가장 이른 보관 시각 또는 0, `a` = 표시를 쓴 앱의 종류)로 바꿔 곧바로 다시 쓰고, 앱 갱신 뒤(머리가 깨졌으면 바로) 되감는다(S27 (f)). ④ 6.12에 '기록 10 KB × n' 보관 개수(2 MiB에 약 150쪽, 1차 값 하나면 약 15쪽)와 그 시험 — (수정 2회차) 실제 한도 9 × 224 KiB 기준 약 144쪽·계산한 경계 단언으로 정정(13.4 항목 2) | 1.5 D-S2·D-S4, 4.1 해석 표 ③·⑤, 4.2(상수), 4.4 `HeldRecords`·`MetaKeys`, 6.3.2, 6.3.4, 6.3.5, 6.12, 6.13, 8.2 S2-6·S2-7b, 11 R4 |
| SYNC-M6 (검토 S-4·S-5 승격) | ① `SyncTestHarness.checkConverged(devices, {includeServer, Set<EntityKind>? kinds})`를 4.3 시그니처에 더하고(덤프 키 `<kind>/<id>`로 거름 — [확인] `canonical_dump.dart` 14), CP-S8 판정 열(12.1)·`api_surface_test` 갱신 대상(3.1 트리, 8.2 S2-4b)에 넣었다. ② 하네스 `knownKinds`·`restart`·`checkConverged(kinds:)`는 **한 작업 S2-4b**로 정하고, S2-7b 완료 조건에서 `sync_test_harness_test`를 뺐다(쓰기만). ③ 6.7.2에 **파일·경우별 CORE 선행 작업 표**(T20a·T24·T27·T28·T29·T30·T31·T32·T33a·T33b)를 두었다 — 'T26부터 시나리오 가능, T28부터 전부'는 사실과 달라 지웠다(5.1.5·5.5·11 R1도 같이). CORE가 이정표 커밋을 8.5 표에 알리는 것은 02-core 8.1·8.5에 이미 있다(확인) | 1.5 D-S10, 4.3, 5.1.5, 5.5, 6.5, 6.7.1 S27, 6.7.2 선행 작업 표, 8.2 S2-4b·S2-9, 9.1, 11 R1, 12.1 |
| SYNC-M7 (검토 S-6·S-8 승격, S-7) | ① `HandlerDeps.engineSignal(ms): AbortSignal`(운영 `AbortSignal.timeout`, 시험은 `AbortController`를 넘겨 `abort()`) + `ENGINE_TIMEOUT_MS = 25_000`. `handler.test.ts`의 시간 제한 경우를 '가짜 시계'에서 '주입한 신호 abort'로 바꿨다(이유: mock timers가 `AbortSignal.timeout`을 움직이지 않음 [확인 — 검토]). 비교 도구도 같은 주입. ② `engineVersion` = 엔진 출력의 `version`(`EngineOutput.version` 새 필드 — `MathEngine.version` 정적 필드를 지움). Claude는 **응답의 `model`**, 대체 여부는 `logInfo`(요청 모델과 비교 + SDK 사용량 정보 [추측])로 로그에만. 시험 '다른 모델로 답함 → `engineVersion` = 그 값'. ③ 어댑터는 생성자 주입(`MathpixEngine({appId, apiKey, fetch?})`·`ClaudeEngine({apiKey, model, client?})`), `params.ts`는 등록부(`registryFromParams` → `EngineSettings`)만 읽는다. 어댑터가 `params`를 import하지 않는지 소스 검사 | 1.5 D-S5·D-S12, 3.2 트리, 4.5, 5.3 표, 6.8.2, 6.8.4, 6.8.6, 6.9, 8.2 S2-10a·S2-10b·S2-12·S2-13, 9.2 |
| SYNC-M8 (검토 S-9 승격) | ① 운영 `OWNER_UIDS`는 **커밋하는 `functions/.env.<projectId>`**(uid는 비밀이 아님, `.env.local`은 에뮬레이터만 읽음) — Q9 기본값을 바꿨다. ② 배포 뒤 확인 = `MATH_ENGINE=none`에서 소유자 → 503 `UNAVAILABLE`(로그인·소유자 검사 통과 확인), 남 계정 → 403, 로그인 없이 → 401, 엔진 설정 뒤 실제 1회. '가짜 엔진 → 실제 엔진' 문장(L5·SC-7)을 지웠다(운영 `ALLOW_FAKE_ENGINE=false`와 모순). ③ 비밀값은 **첫 배포 전**(엔진 전이면 자리 값) [추측 — 배포 검사]. 6.10 L5를 계약 7.4.7 순서(비밀값 → `.env.<projectId>` 커밋 → 배포 → 503·403 확인 → 엔진 1회)의 다섯 단계로 다시 썼다 | 1.5 D-S8, 3.2, 6.8.9 표, 6.10 L5, 9.3 SC-7, 11 R15, 12.2 Q9, 부록 B |
| SYNC-M9 (C21-12·17·29·30) | ① CP-S1~S9 v2.1 반영: 4.1을 v2.1 원문으로 바꾸고, 원문이 비워 둔 세부를 4.1 끝 해석 표로 다시 정리했다(CP-S2 보강 ①~⑤ 각각의 구현). 12.1에 판정 열을 두었다(CP-S2 '수정해서 승인', 나머지 승인 — CP-S8은 `checkConverged(kinds:)` 포함). ② CP-S3 ⑥(가짜 엔진 출력 규칙)은 계약 7.6 블록이 되었으므로 4.1에 원문을 옮기고 6.8.5는 그 풀이로. ③ **B7a 바탕 = CORE B2-α(T22) 해시**, 새 종류 디코드·키 대조 시험은 **B2-β JSON 골든(T20a) 뒤** rebase해서 확인(6.4 '바탕과 두 단계 확인', 8.1 완료 조건을 'α 위'·'T20a 위'로 나눔 — 'EntityKind 2값 커밋 해시' 문구를 지움). ④ **B7b는 R2-B1 바로 뒤 따로 병합**(6.4 끝 문단, 8.1, 8.3 I-0). ⑤ 4.2 `handwriting` 범위 주석·6.2.3 '근거'를 '녹음과 같음' → **'페이지와 같음'**(1차 `page` = `noteIdKey ?? noteIdHint`, `recording`은 `noteIdHint ?? noteIdKey` — [확인] `scopes.dart` 25–27) | 상태 줄, 1.2, 1.5, 1.6 둘째 표, 4.0, 4.1, 4.2, 6.2.3, 6.4, 6.8.5, 8.1, 8.3, 12.1 |
| SYNC-M10 (C21-26, 검토 X-2) | `emulator_suite.sh`를 셸 잠금 대신 `dart run tool/ws.dart with-heavy-lock -- bash functions/scripts/emulator_suite.sh "$@"`로 **자기 자신을 다시 실행**하는 모양으로 다시 썼다. 안쪽은 `NOTEAPP_HEAVY_LOCK_HELD=1`을 물려받으므로 `--with-dart`(SYNC 노드 시험 + LIBRARY Dart `emulator` 시험을 한 에뮬레이터 실행에서)의 안쪽 `ws test -t emulator`가 잠금을 다시 잡지 않는다(중첩 교착 없음). 고정 경로 `/tmp/noteapp-heavy-tests.lock`. CI(`CI=true`)에서는 `functions.yml`의 그 단계에 아직 Dart가 없어 잠금 없이 — INFRA에 정보로 RQ-8을 남겼다. RQ-5를 'INFRA 답 받아들임'으로 닫았다(셸 잠금 구현 삭제). `.gitignore` RQ-2는 01-infra 3.1 블록(R2-B1 ⑩ — `functions/eval-out/`·`firebase-debug*.log` 포함)과 `repo_hygiene_test`(`.env.demo-noteapp` 미무시)로 **반영 확인**했다 | 1.6 둘째 표, 3.2 트리, 5.2 RQ-2·RQ-5·RQ-8, 5.6, 6.8.11, 8.2 S2-11, 8.3 I-3·I-4, 9.1, 9.2, 11 R9·R16 |

### 13.2 공통 결정·권장·영역 간 항목

| 항목 | 반영 | 위치 |
|---|---|---|
| CD2-01 바탕 코드 = 1차 통합 HEAD | 머리말을 통합 HEAD `18c5ae5`로 바꿨다. [확인] 그 HEAD의 `sync_engine`은 1차 작업 트리 `1f4b639` + 통합 커밋 `22abbea`(`test/integration/` 4파일)뿐이라 `lib/` 줄 인용은 그대로 맞다. 통합 HEAD 수치(VM 777·Chrome 26·integration 42)를 머리말·8.1·8.3에 | 머리말, 8.1, 8.3 |
| CD2-05 기반 단계 재구성 | R2-B1 → R2-B7b → (R2-B2 + R2-B7a + R2-B2i) 순서, B2-α/β, 이정표 커밋 | 1.2, 6.4, 8.1, 6.7.2 |
| CD2-12·CD2-21·CD2-22 | 손글씨는 편집 아님 / S-13 보강 / `functions/` 규약 — 위 M3·M1·M5·M2·M7·M8 | 13.1 |
| CD2-19 시험 실행 규칙 | `with-heavy-lock`·`HELD` 넘김, `emulator`는 컨테이너 + CI | 6.8.11, 9.1 |
| CD2-20 `firebase-tools` 14일 | R2-B1·R2-B7b 때 재확인(2026-11-11부터) — B7b 선행 조건에 넣음 | 3.4, 6.4, 7.2, 8.1 |
| 검토 S-2 (다시 적용 지표·재시도 위치) | **반영**: 다시 적용 `ApplyResult.latestServerTime = null`, 수는 `reappliedChunks`·`reappliedRecords`(새 `SyncEngineDebug` 필드 — `chunksReceived`·`lastRemoteApplyLatency` 밖). 위치는 1차 `if (!s.loaded)` 블록 밖 + 세션 플래그 `heldReapplied`(성공 때만 true). 시험 `engine_state_test` '실패 뒤 같은 세션의 재연결에서 다시 시도'·'지표 불변' | 4.2, 4.4, 6.3.4, 8.2 S2-7b |
| 검토 S-10 (큰 작업 나누기) | **반영**: S2-4 → S2-4a(가짜 저장소·서버)·S2-4b(`TestDevice`·하네스·계약 스위트·드라이버), S2-7 → S2-7a(관용 디코드 연결·받기 보관)·S2-7b(다시 적용·되감기·훅), S2-10 → S2-10a(`protocol`·`access`·`registry`·가짜 엔진)·S2-10b(`quota`·처리 본문·오류·로그·위생). 세션 추정 6~7 그대로, 작업량 12 → 12.5(v2.1 보관 보강 몫) | 8.2 |
| 검토 S-11 (실기기 대체 경로) | **반영**: 9.3을 '기기' 열이 있는 표로 — SC-1~SC-3·SC-5·SC-6·SC-8은 iPad Safari ↔ PC Chrome(웹 ↔ 웹)으로 가능, SC-4만 안드로이드(또는 TestFlight 뒤 iPad 네이티브) 필요, SC-7은 다른 Google 계정 하나가 더 필요. SC-4에 M3 확인(영구 삭제 뒤 사본 없음)을 더함 | 9.3 |
| 검토 S-12 ① `handwriting` 범위 근거 | 반영(M9 ⑤) | 4.2, 6.2.3 |
| 검토 S-12 ② 시간 단언 | **반영**: 6.12의 시간 목표는 진행 기록에 수치로 남기고 단언은 ×5 느슨한 상한(`HeldRecords` VM ≤ 500 ms·Chrome ≤ 1.5 s, 다시 적용 ≤ 5 s, `decodeTolerant` ×5) | 6.12 |
| 검토 S-12 ③ 규칙 시험 설정 경로 | **반영**: `firebase.rules-test.json`의 `../../packages/sync_engine/firebase/*`에 [추측]을 붙이고, 안 되면 임시 디렉터리에 규칙 파일을 복사한 설정을 만든다고 적음 | 6.10 L4 |
| 검토 S-12 ④ `SyncEngineDebug`의 `==`·`hashCode`·`toString` | **반영하지 않음 — 할 것이 없다**: [확인] 1차 `SyncEngineDebug`(`engine/sync_engine.dart` 116–153)에는 `==`·`hashCode`·`toString`이 없다(필드만). 새 필드는 기본값이 있는 이름 인자라 1차 호출이 그대로 컴파일된다. 4.2 주석에 적음 | 4.2 |
| 검토 S-12 ⑤ Mathpix 단가 | **반영**: `[추측 — 검색 요약]` 표시 | 6.8.12 |
| X-1 (INFRA `.gitignore`) | 반영 확인(M10) | 5.2 RQ-2 |
| X-2 (잠금 중첩) | 반영(M10) | 6.8.11 |
| X-3 (B7b 따로 병합·CI 더미 env·안내서) | B7b는 R2-B1 바로 뒤(M9 ④), `hashFiles` 가드는 INFRA가 유지, CI 더미 env는 커밋하는 `.env.demo-noteapp`(그대로), 미니 라운드 안내서 순서는 6.10 L5(INFRA 안내서가 이것을 옮긴다)·RQ-6 `ignore`는 01-infra R2-B1 ⑧에 들어감 | 5.2 RQ-6, 6.4, 6.10 |
| X-4 (CORE) | ① B7a 바탕: 검토는 'T22 해시로 통일'이라 했고 총괄 결정은 **B2-α 해시**(= T22 — 02-core 8.1 'B2-α (T22)')다 — 같은 커밋이라 모순이 없다. 단 `EntityJson.decode`(T20a)·`Recording.title`(T20a/T21)은 B2-β라 디코드·키 대조는 T20a 뒤(M9 ③). ② T27·T29~T33 이정표 — 6.7.2 표, 02-core 8.5에 이미 있음. ③ `math.engine` 항상 — C21-11, `kPageObjectTypeKeys['math']`에 `engine` 고정 | 6.4, 6.7.2, 6.2.1 |
| X-5 (LIBRARY) | ① 두 언어가 같은 값을 단언(LIBRARY L2-I6이 E1~E3·E5~E9 값을 그대로 적음 — 확인), 사용자 만들기 REST 공유 ② M-3은 SYNC 쪽만 바꿈(LIBRARY 변경 없음) ③ 엔진 id가 다른 결과도 신선 — 손글씨 한 단위 LWW로 받아들임(R6·Q7) | 5.3, 6.2.5, 5.1.3 |
| X-6 (수식 고정 자료 내보내기) | 총괄 판정: LIBRARY 수식 패드의 P-C 개발자 동작(LIBRARY-M11 — 05-library 6.14.7). 6.9.1·Q4·5.6에 적음 | 6.9.1, 5.6, 12.2 Q4 |
| C-1 (switch 수) | C21-04로 계약 정정됨 — 6.4 표가 그대로 맞음 | 1.6, 6.4 |
| C-2 (영구 삭제 문구) | C21-12로 계약 정정됨(노트 단위). 6.2.4에 '페이지는 소프트 삭제만' 한 줄 | 4.1, 6.2.4 |
| C-3·C-4 (CP-S1·CP-S2) | 계약 문장이 됨 — M9 ① | 4.1 |
| C-5 (R2-B7b 따로) | C21-29 — M9 ④ | 6.4, 8.1 |
| C-6 (`firebase-tools` 14일) | C21-28 — R2-B1·B7b 재확인 | 3.4, 7.2 |
| C-7 (`engineVersion`) | C21-17 — M7 ② | 4.5, 6.8 |
| C-8 (CP-S5) | 승인 — 간접 의존은 lock 만들 때 확인(7.2 방식) | 3.4, 7.2 |
| 검토 질문 Q-1~Q-5·계획서 Q1~Q9 | 모두 답을 받아 12.2에 적음 | 12.2 |

### 13.3 이번에 새로 확인한 것·새로 생긴 판단

- [확인] Node 22.23.4: 맞는 파일이 없는 `node --test` 글롭은 실패가 아니라 `# tests 0`으로 끝난다 — 'B7b 완료 조건의 시험 수 > 0'이 꼭 필요한 이유(3.4).
- [확인] 1차 `canonicalDump` 키 형식 `<kind>/<id>`(`canonical_dump.dart` 14) — `checkConverged(kinds:)`를 덤프 키로 거를 수 있다(4.3).
- [확인] 1차 `SyncEngineDebug`에는 값 비교 멤버가 없다(4.2).
- 새 판단: INFRA `functions.yml`에서 `npm run test:emulator`가 flutter-action보다 먼저 돌므로 `emulator_suite.sh`는 `CI=true`면 잠금 없이 돈다(5.2 RQ-8 — 정보, 위험 R16).
- 새 판단: 보관 값의 깨진 값 표시는 표시를 쓴 앱의 종류 집합(`a`)을 남겨 '같은 판에서는 되감지 않음, 갱신 뒤 되감음'을 정한다(6.3.5) — 계약 ③ '모든 종류 되감기 표시'의 발동 시점을 채운 세부다.
- 새 판단: 다시 적용 K1 기록의 재시도는 1차 `sync.held`와 같은 K2 시점(`releaseHeld`)이라 계약 ⑤의 '다음 연결'보다 이를 수 있다 — 해제 시각 전에는 시도하지 않으므로 같은 결과다(4.1 해석 표).

### 13.4 수정 2회차 — 총괄 재검토 항목 1~4

수정 2회차(2026-11-05). 기준: 총괄 재검토 항목 1~4(아래 표의 # = 항목 번호), 통합 계약 v2.1(7.9의 최신판 — 새 판 없음, 그래서 계약 블록은 바꾸지 않았다). 계약을 옮긴 블록(4.1, 5.1.5 `PageObjectFixtures` 블록, 8.1 R2-B7a·R2-B7b 행)이 00-overview 안에 글자 그대로 있는지 프로그램으로 다시 대조했다(차이 없음). 다른 파일은 고치지 않았다.

| # | 무엇을 어떻게 바꿨나 | 위치 |
|---|---|---|
| 1 (B7a 'T20a 위' 완료 조건을 그 시점에 판정할 수 없음) | **①을 골랐다** — `fixtureJson`(새 종류)과 `field_units_test` 77행 종류별 비교의 고정 자료를 `PageObjectFixtures`가 아니라 **계약 생성자(B2-α부터 실제) + T20a `toJson`**으로 만든다. 새 도우미 `objectFixture(type)`(`'shape'`·`'text'`·`'image'`·`'math'` → 4종 생성자, `'sticker'` → `UnknownObject(rawJson)`)를 `test/support/entity_fixtures.dart`에 두고 `fixtureJson(pageObject)` = `objectFixture('shape').toJson()`, 손글씨는 `HandwritingText(…)`·`HandwritingLine(…)` + `toJson`. 도형은 템플릿(`ShapeGeometry.rectangle` — T20b) 대신 `PolylineGeometry(…, closed: true)`를 직접 만들고, 도형 `frame` 키는 `toJson`이 기하에서 계산한다(02-core 6.2.6 마지막 행 — T20a '6.2.6 표 전부'). 그러면 `EntityKind.values`를 도는 시험 5개와 종류별 비교가 T20a 해시에서 판정된다. 8.1 B7a 완료 조건에 `grep -rn PageObjectFixtures packages/sync_engine/test` 0줄을 더해 다시 끼어드는 것을 막았다. ②(확인 시점을 T23b로)를 고르지 않은 근거: 계약 7.6.2 R2-B7a 행('새 종류 디코드·키 대조 시험(CP-S9)은 B2-β JSON 조각이 들어온 뒤')과 02-core 8.1 '이정표 알림'(SYNC는 T20a 해시 뒤)이 그대로 맞고 CORE에 알릴 것이 없다. 또 T23b까지 기다리면 B7a의 판정이 B2-β 끝으로 밀려 묶음 병합 직전에 어긋남이 몰린다. `core_json_keys_test` v2는 골든 파일 + T20a `fromJson`/`toJson`만 써서 원래 T20a에서 돈다(그대로). 함께 고친 것: ⓐ 5.1.1 끝의 '`TestDevice` 도우미(CORE `PageObjectFixtures`로 만든 JSON)'는 INFRA R4(`test_only_entrypoints` — 01-infra 662–666: `lib/` 파일은 `package:note_core/testing.dart`를 import할 수 없다)와 어긋났다 [확인 — 1차 `test_device.dart`도 `note_core.dart`만 import]. `TestDevice`는 같은 생성자 방식으로 만든다고 고쳤다(4.3 주석도). ⓑ 5.1.5의 '`createFakeNoteStore()`는 쓰지 않는다'는 1차 시험 `providers_test`·`local/core_sync_local_store_test`가 v1 동작으로 쓰고 있어 사실과 달랐다 [확인 — 1차 작업 트리 `grep`]. '새 시험은 v2를 쓰지 않는다(1차의 v1 사용은 α부터 그대로 돈다)'로 고쳤다 | 3.1 트리(`entity_fixtures.dart`), 4.3 `TestDevice.addObject` 주석, 5.1.1 끝, 5.1.5 둘째·셋째 항목, 6.4 표(`entity_fixtures`·`field_units_test` 77행·`EntityKind.values` 행)와 '바탕과 두 단계 확인', 8.1 B7a 완료 조건, 10 첫 항목 |
| 2 (`held_records_test` '150개 저장·151번째 표시'를 만족시킬 수 없음) | 지적대로 기록 하나(`r`의 항목)는 조각 사이로 나뉘지 않으므로 보관 개수는 조각별 채움으로 정해지고, 기본값에서 실제 한도는 **조각 9개 × 224 KiB = 2,016 KiB**다. 같은 크기 항목(길이 `e`)이면 조각당 `⌊(maxPartBytes − w + 1) / (e + 1)⌋`개(`w` = 빈 조각 테두리 20 B, 쉼표 1 B), 전체 9배다 — 항목 ≤ 13,490 B면 17개(153), 13,491–14,333 B면 16개(144), 14,334–15,289 B면 15개(135). [확인] 1차 형식(`chunkIdOf` 41자, HLC 37자, `EntityFieldVersions.toJson`)으로 만든 모형 항목을 재면 엔티티 JSON 10,000 B 기록의 항목이 13,780–14,107 B라 조각당 16개, **약 144개**다(`/tmp/claude-0/plan57-scratch/sync57-r2`의 계산). 그래서 ① `held_records_test`·S2-6 완료 조건은 숫자를 박지 않고 상수와 잰 `e`로 계산한 경계 `N`을 단언한다(`N`개 저장·`N + 1`번째 청크는 기록 0개·표시·그때 전체 길이 < `maxTotalBytes`, 실측 `N`·`e`는 진행 기록에 — 참고 144). ② 6.3.2·6.3.5·6.12의 '2 MiB에 약 150쪽'을 '9 × 224 KiB에 약 144쪽'으로, 획 100개 페이지 예(약 450쪽)를 같은 식으로 약 380–400쪽으로, v2.0 초안 값 하나(200 KiB)의 예를 약 15쪽 → 14쪽으로 고쳤다. ③ **기본값에서 `maxTotalBytes`(2 MiB)는 걸리지 않는다**는 것(차이 32 KiB > 머리 수백 B)을 6.3.2·6.12와 4.4 상수 주석에 적었다 — 계약 ③의 '총 상한 2 MiB'를 지키는 안전장치이고, 시험이 줄일 때(S27 (c)) 걸린다. 상한 값 자체(키당 ≤ 224 KiB, 총 ≤ 2 MiB — 1.2·1.5 D-S2·4.1 해석 표 ③·6.11)는 맞으므로 그대로 두었다. `maxTotalBytes`를 2,016 KiB로 낮춰 '걸리게' 만드는 안은 계약 문장(총 2 MiB)을 바꾸지 않고도 할 수 있지만 얻는 것이 없어 하지 않았다. 13.1 SYNC-M5 ④에 정정 표시를 달았다 | 4.4 `HeldRecords` 상수 주석, 6.3.2('`r` 채움'·'상한'·'보관 개수 기준'), 6.3.5, 6.12 두 행, 8.2 S2-6, 13.1 SYNC-M5 |
| 3 (6.2.1 `math` 행의 '`engine`(선택 …)') | 괄호를 '(v2.1, C21-11) 항상 씀 — 없으면 null'로 바꾸고 '`kPageObjectTypeKeys['math']`에 고정' + 계약 7.2.7 근거를 붙였다. 1.6 둘째 표·6.4 표·13.2 X-4 ③과 같아졌다 | 6.2.1 키 표 |
| 4 (Claude 이음새 이름 어긋남) | 6.8.6의 `messagesCreate(params, opts)`를 4.5 정의대로 `ClaudeMessagesClient.create(params, opts)`로 고치고, 두 번 따로 있던 '시험(`test/claude.test.ts`)' 항목을 하나로 합쳤다(요청 인자에 `betas`·`fallbacks`·`opts.signal`을 더 적고, 대체 모델 응답 경우는 같은 항목 안에). 6.8.6 코드 스케치(`this.client.create(…, { signal })`)·3.2 트리·8.2 S2-12·9.2 표는 이미 같은 이름·내용이라 그대로다 | 6.8.6 |

### 13.5 개발 착수 정리 — 계약 v2.3 (2026-11-06, 동시 개발 세션 1)

계약 7.6.2 마지막 bullet(C22-09)과 v2.3(C23-01~07)을 반영했다. 시그니처 변경은 없다.

| 항목 | 처리 | 위치 |
|---|---|---|
| '가정' 블록 → 실제 타입 | CORE B2-α·B2-β 커밋 해시로 5.5 머리 문단과 첫 행을 바꿈 | 5.5 |
| 계약 인용 | 인용 블록 11개를 계약 v2.3 7장과 줄 단위로 대조 — 모두 부분 문자열이라 본문은 그대로 두고 표시만 `계약 v2.3 … 원문`으로. 7.4.7 인용의 CI 줄 '15.34.2'는 계약 본문 그대로라 아래에 C23-01 주석을 붙임 | 4.1, 5.x, 8.1 |
| C23-01 `firebase-tools 15.34.1` | 3.4 `package.json` 블록·설명, 7.2 표, RQ-4, Q8 답 | 3.4, 5.2, 7.2, 12.2 |
| C23-02 `CLAUDE_MODEL` 기본값 `''` → Claude `notConfigured` | D-S9, 6.8.4 표, 6.8.6 블록 주석·문장, 6.8.9 표, 6.8.12 비용 표, 6.9.2 `--claude-model`(기본값 없음), Q1 답. 계획서·코드에 모델 이름을 기본값으로 두지 않는다 | 1.5, 6.8, 6.9, 12.2 |
| C22-01~08 | SYNC 인용 문장에 바뀐 곳 없음(C22-07 V13은 이미 P-B 표시) | — |
| 00-review '최종 승인' SYNC-F1 | S2-10a·S2-10b·S2-11은 P-B — 미루면 V13을 `미룸`으로 적는다(진행 기록 '2차' 절). R2-B7b `npm ci && npm test`(시험 수 > 0)는 P-A처럼 지킴(동시 개발 세션마다 `npm test`) | 8.2, 진행 기록 |
| SYNC-F2 | C23-01로 닫힘 — R2-B7b는 15.34.1로 기반 단계에 들어갔다(`9cdd3fb`) | 3.4 |
| SYNC-F3 | 끝남 — R2-B7a `99b8ead`(바탕 B2-α `2b2e4b0`), 키 대조·새 종류 디코드는 T20a `9777fde` 위에서 통과(진행 기록 R2-B7a) | 8.1 |
| 다른 영역 → SYNC 변경 요청(기반 단계 메모) | CORE: B7a switch 자리·T20a 전 `UnimplementedError` — B7a에서 처리함. INFRA: `functions.yml` 시험 수 검사·`with-heavy-lock` — B7b에서 처리함. 새로 할 일 없음 | — |

---

## 부록 A. 확장 지점 · 자리 사용표 (개요 6장 13절)

| 구분 | 이름 | 제공 / 소비 | 비고 |
|---|---|---|---|
| 여는 자리(포트) | `recognizeMath` callable(4.1·4.5) | SYNC 제공 → LIBRARY `CallableMathRecognizer` 소비(X36) | 형식 변경은 1차 7.4.12 절차, 동시 개발 중 '추가만'(7.4.9) |
| 여는 자리(포트, P-C) | `AuthService.idToken`(4.2) | SYNC 제공 → INFRA가 미니 라운드에 `RecognitionConfig.idTokenProvider`로 | CP-S7 |
| 여는 자리(서버 엔진) | `MathEngine` 포트·등록부(4.5) | `functions/` 안 | 새 엔진 = 어댑터 파일 하나 + 등록부 한 줄 |
| 채우는 자리 | 없음(이번 라운드) | — | 1차 7.3.3 M4 행(`authBackendProvider`·`syncBackendFactoryProvider`·`connectivitySignalProvider`·`syncBadgeProvider`·`remoteAssetFetcherProvider`)은 미니 라운드에 INFRA가 채움 |
| provider | 새 provider 없음 | — | 1차 `providers.dart` 그대로 |

## 부록 B. 네이티브 · 권한 · 클라우드 요구표 (개요 6장 14절)

`sync_engine`은 새 플러그인이 없다(Info.plist 키·안드로이드 권한·minSdk 변화 없음 — INFRA `native_config_test`·`ws native-reqs`의 입력 없음). 실연결 때 필요한 것은 1차 07-sync 6.18 목록 그대로이고, 2차 서버 함수가 더하는 클라우드 요구는 아래와 같다(INFRA 안내서·미니 라운드 체크리스트 6.10의 입력).

| 항목 | 값 | 시점 |
|---|---|---|
| 요금제 | Blaze(종량제) — 함수 배포 필수(조사 04 6.2) + 예산 알림 | 미니 라운드 |
| 지역 | 함수 `asia-northeast3`, Firestore 위치 `asia-northeast3`(INFRA 안내서 01) | 프로젝트 생성 때(Firestore 위치는 바꿀 수 없음) |
| Secret Manager | `MATH_API_KEY` — (v2.1, SYNC-M8) **첫 배포 전**(엔진이 정해지기 전이면 자리 값, 엔진 계정 뒤 실제 값으로 바꿈) [추측 — 배포 검사, 미니 라운드에서 확인] | 미니 라운드 첫 배포 전 / 엔진 계정 뒤 |
| 함수 매개변수 | **커밋하는 `functions/.env.<projectId>`**(v2.1): `OWNER_UIDS`(사용자 uid — 비밀 아님), `MATH_ENGINE`(첫 배포 `none`), `DAILY_CAP`, `QUOTA_STORE=firestore`, `ALLOW_FAKE_ENGINE=false`, (선택) `MATHPIX_APP_ID`·`CLAUDE_MODEL`. `.env.local`은 배포에 쓰이지 않는다 | 미니 라운드(로그인 뒤 uid 확인) |
| Firestore TTL | 컬렉션 `fnQuota`, 필드 `expireAt` | 미니 라운드 |
| 배포 서비스 계정 역할 | 1차 INFRA 안내서 02의 역할 + Functions 배포·Secret Manager·Cloud Build·Artifact Registry 관련 역할 [추측 — 조사 04 6.5] | 미니 라운드(CI 배포를 쓰면) |
| App Check | 이번에는 강제하지 않음(`enforceAppCheck: false`) | 실연결 뒤 재검토 |
