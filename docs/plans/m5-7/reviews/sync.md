# SYNC 2차 계획서 검토 — `07-sync.md`

> 검토자: 총괄 대리 검토자 · 검토일 2026-11-05
> 대상: [07-sync.md](../07-sync.md)(1,874줄, 초안) — 동기화 · 서버 함수, 소유 경로 `packages/sync_engine/`, `functions/`
> 기준: 개요 [00-overview.md](../00-overview.md) 7장 통합 계약 v2.0 초안(7.0.1·7.0.2·7.2.2·7.2.7·7.2.8·7.2.13·7.3·7.4.6·7.4.7·7.5·7.6.2·7.7), 조사 01(3.4·3.11·R2)·03(6·7)·04(6), PLAN.md(F-07·F-10·F-14·F-16, 7.4, 8장 지표, 10장 M4·M7), 1차 SYNC 작업 트리 `/home/user/wt/sync`(`1f4b639`)와 진행 기록, 다른 영역 계획서 01·02·05의 맞닿은 절, 이미 나온 검토(core·infra·library)
> 확인 방법: 계획서 전 절을 읽었다. 계획서가 인용한 1차 코드 위치를 모두 열어 대조했다 — `field_units.dart` `keysOf` 21–54·`groupsOf` 57–78, `scopes.dart` 19–28, `record_gate.dart` `_purged` 132–154·`hasOwner` 108–114, `purge_guard.dart` `_editedInOutbox` 93–117·`scopesSent` 39–46, `chunk_codec.dart` `_kind` 201–206, `download_pipeline.dart` 426–428·488–493·`keep()` 518–528·`_libStrokeNotes` 716–747, `compactor.dart` 194–205, `fake_sync_server.dart` `mergedState` 94–160, `fake_sync_store.dart` switch 10곳(모두 `_ =>`/`default:` — `SyncEntity`는 sealed가 아님), `UploadPipeline._hint` 283, `AuthService.refreshSession` `@internal` 169. npm 판·게시일(`npm view … time`), `@anthropic-ai/sdk 1.1.0` 꾸러미의 `.d.ts`(`npm pack`), Node 22.23.4에서 `node --test` 디렉터리 인자와 `AbortSignal.timeout` + mock timers를 직접 실험했다. 계획서의 에뮬레이터 실험(`/tmp/claude-0/plan57-scratch/sync57/probe`)의 스크립트·설정도 읽었다. 무거운 시험은 돌리지 않았다. 임시 작업 `/tmp/claude-0/plan57-scratch/syncrev/`.

---

## 총평

계약 원문(7.2.8·7.2.13·7.3·7.4.7)을 글자 그대로 옮기고, 다르게 읽힐 곳은 해석 표 + CP로 분리한 구조가 좋다. 1차 코드에 대한 사실은 거의 모두 맞았다.

- **R2-B7 컴파일 패치 목록이 정확하다.** 기본 갈래가 없는 exhaustive switch는 `keysOf`·`groupsOf`·`scopeOf`·`_purged` 4곳뿐이고, `kindOrder`는 컴파일은 되나 `indexOf == -1`로 정렬이 틀어지며, 시험 쪽은 `entity_fixtures.dart` `fixtureJson` 하나다. 계약 7.0.2의 '8곳'보다 계획서 6.4가 맞다(C-1).
- **D-S1('나머지 전부' 한 단위)과 6.2.2 반례**는 맞는 지적이다. 1차 `FieldMerge`는 단위 계산 키 = `keysOf ∪ 두 JSON 키 ∪ overrides 키`이고 없는 키는 `present=false`로 쓰지 않으므로(`field_merge.dart` 70–76·241–246), `unitsFor`만 바꾸면 성질(교환·결합·멱등)이 유지된다.
- **S-13 설계**(바이트째 보관, 상한 → 되감기 표시, 압축이 모르는 청크를 지우지 않음, `releaseHolds: false`)는 1차의 `deferredFrom`·`HeldChunks.collapsed` 되감기(`download_pipeline.dart` 300–315)와 같은 원리라 자연스럽다. 특히 '압축이 새 앱 데이터를 지운다'(D-S3)와 '합성 청크가 기존 `sync.held`를 푼다'(6.3.4)를 찾아낸 것은 좋다.
- **서버 함수**: 처리 순서(입력 검사 → 상한 → 엔진), 엔진 429를 `resource-exhausted`로 보내지 않는 판단, 커밋하는 `.env.demo-noteapp`(CI 더미 env 문제 — INFRA 검토 X-6 — 를 해결), uid를 지정한 에뮬레이터 사용자 규약은 실험으로 뒷받침된다. npm 판·게시일(`firebase-functions 7.4.0` 09-15, `firebase-admin 14.5.0` 09-23·`node >=22`, `typescript 6.0.3`, `@types/node 22.20.5`, `firebase-tools 15.34.2` 10-28, `@anthropic-ai/sdk 1.1.0` 10-21)이 모두 맞다. Claude 어댑터 스케치의 `fallbacks: "default"` + `server-side-fallback-2026-07-01`, `output_config.effort/format`은 SDK 1.1.0 타입에 있다(`BetaFallbacksParam = Array<…> | 'default'`) — `tsc --strict`로 통과할 모양이다. 단가 $4/$20도 맞다.

그러나 **그대로 승인할 수 없다(revise)**. ① 다시 적용(reapply)의 합성 청크가 1차 세션 LRU에 들어가, 상한이 한 청크 안에서 걸려 '저장분 + 되감기 표시'로 나뉜 경우 **표시분 기록이 영구히 사라진다**(S-13이 막으려는 바로 그 데이터 손실). ② `npm test` 스크립트가 Node 22에서 **실패한다**(디렉터리 인자 — 실험으로 확인) — B7b·S2-10의 완료 조건이 돌지 않는다. ③ 영구 삭제 보호의 '최근 10분 보냄'이 손글씨 결과 업로드도 세어, S28 단언과 모순되고 iPad(웹, 주 기기) + 안드로이드(색인기) 조합에서 **사용자가 지운 노트가 복구 사본으로 되살아난다**. ④ B7a 완료 조건의 `core_json_keys_test` 실행이 B7a 변경 목록대로면 실패한다. 그 밖에 다시 적용 중 K1과 압축이 겹칠 때의 손실, 서버 함수 시험의 가짜 시계, 미니 라운드 준비의 사실 오류(`.env.local`, 운영 가짜 엔진, 비밀값 순서), T16-v2의 실제 CORE 선행 작업 누락, 큰 작업 쪼개기를 고치면 좋다.

---

## 반드시 고칠 것

### M-1. 다시 적용의 합성 청크가 세션 LRU에 들어가, 같은 청크를 다시 받을 때 건너뛴다 — 상한이 청크 중간에서 걸리면 되감기 표시분 기록을 잃는다 (데이터 손실)

- **위치**: 4.4 `HeldRecords.add`('Records that do not fit go to the overflow mark')·`reapplyHeldRecords`, 6.3.2 '상한' 문단, 6.3.4 의사 코드 `_apply(chunks, release: true, releaseHolds: false, …)`, 6.3.5 '저장된 기록(`r`)과 되감기 표시(`o`)가 함께 있으면 …(되감은 받기에서 같은 기록이 다시 와도 중복 제거·멱등)'.
- **문제** [확인 — 1차 코드]:
  1. 1차 `_apply`는 성공한 호출 끝의 `keep()`에서 `fresh`의 **모든 청크 id를 `_applied`(세션 LRU)에 넣는다**(`download_pipeline.dart` 524–528). `release: true`는 LRU 검사를 건너뛸 뿐 넣기는 그대로다. 그리고 `release`가 아닌 받기는 `_applied`에 있는 청크를 중복으로 버린다(372–383).
  2. 합성 청크는 **원래 청크 id**를 쓴다(4.4 `takeKnown`). 순서는 `load()`(되감기 — LRU 지움, 1차 240) → `reapplyHeldRecords()`(합성 청크 C를 적용 → `_applied`에 C) → `catchUp()`(되감은 커서부터 다시 받음)이다.
  3. `add`가 기록마다 상한을 보므로 한 청크 C의 모르는 기록이 일부는 `r`에 저장되고 일부는 `o`(표시)로 갈 수 있다. 앱 갱신 뒤 `load()`가 `o`를 지우고 커서를 되돌린 다음, 다시 적용이 C의 저장분을 적용하며 C를 LRU에 넣는다. 이어 `catchUp`이 C를 다시 받으면 **중복으로 건너뛰므로 C의 표시분 기록은 적용되지 않고, 표시는 이미 지워졌다** — 되돌릴 길이 없다. 겹침 재수신(커서 − 5분) 안에 C가 있을 때도 같다(앱 갱신 직후 재시작 — S27 (b)·K2 모양).
  4. 6.3.5는 '다시 와도 멱등'이라고 적어 이 경로를 안전하다고 보지만, 1차 LRU 때문에 '다시 오지 않는다'.
- **고칠 방향**:
  - 다시 적용 호출은 세션 LRU에 넣지 않는다 — `_apply`에 `remember: false`(내부 인자)를 두어 `keep()`의 LRU 갱신을 끈다. 4.4 `reapplyHeldRecords` 주석과 6.3.4 의사 코드에 명시한다.
  - `HeldRecords.add`를 **청크 단위 전부 또는 전무**로 한다: 한 청크의 모르는 기록이 다 들어가지 않으면 그 청크의 기록은 하나도 저장하지 않고 표시(`o`)에만 올린다(이미 같은 청크 id로 저장된 기록이 있으면 그것도 뺀다). 그러면 되감기로 그 청크를 통째로 다시 받는 것만으로 충분하다.
  - 시험: `held_records_test`에 '상한이 청크 중간에서 걸림 → 그 청크는 전부 표시', `download_pipeline_test` 'S-13' 묶음에 '저장분 + 표시분이 같은 청크 → 갱신 뒤 모든 기록 적용', '다시 적용 직후 겹침 재수신된 원래 청크가 정상 디코드·적용됨(멱등)', S27 (c)를 이 모양(작은 상한으로 청크가 갈리는 경우)으로 만든다.

### M-2. `functions/package.json`의 `test` 스크립트가 Node 22에서 실패한다 — B7b·S2-10 완료 조건이 돌지 않는다

- **위치**: 3.4 `"test": "npm run build && node --test lib/test/ lib/tool/test/"`, 5.2 RQ-4 `"node --test lib/test-emulator/"`, 8.1 B7b·8.2 S2-10/S2-13 완료 조건(`npm test`).
- **문제** [확인 — Node 22.23.4, `/tmp/claude-0/plan57-scratch/syncrev`]: `node --test lib/test/ lib/tool/test/`는 디렉터리를 모듈로 불러 `Cannot find module '…/lib/test'`로 **두 항목 모두 실패**한다(`# fail 2`). 인자 없이 기본 패턴에 맡기면 `lib/test-emulator/*.emulator.test.js`까지 잡혀 에뮬레이터 없이 실패한다. 계획서 작성 때의 실험 골격(`probe/functions/package.json`)은 셸 glob `lib/test/*.test.js`를 썼는데, 계획서로 옮기며 바뀌었다.
- **고칠 방향**: 따옴표 친 glob을 Node에 넘긴다 — `node --test 'lib/test/**/*.test.js' 'lib/tool/test/**/*.test.js'`(Node 22 내장 glob, 같은 실험에서 2/2 통과). 에뮬레이터 쪽은 6.8.11 스크립트처럼 `'lib/test-emulator/**/*.emulator.test.js'`로 적고, RQ-4 문장의 디렉터리 인자를 고친다. B7b 완료 조건에 '`npm test`가 시험 파일 수 ≥ 1을 실제로 돌림(출력의 `# tests` > 0)'을 더해 같은 실수를 막는다.

### M-3. 영구 삭제 보호의 '최근 10분 보냄'이 손글씨 결과 업로드도 센다 — S28 단언과 모순되고, 사용자가 지운 노트가 복구 사본으로 되살아난다

- **위치**: 6.2.5 둘째 문단('손글씨 결과만 올린 노트도 최근에 보냄으로 세게 되는데 … 드묾'), 6.7.1 S28 단언('B의 `PurgeGuard`는 손글씨만 쓴 노트를 편집 중으로 보지 않음 → 복구 사본 없음'), 1차 `purge_guard.dart` 39–46(`scopesSent`)·`upload_pipeline.dart` 363(`onScopesCommitted({for (c in group) c.write.scope})`).
- **문제**:
  1. S28 흐름에서 B는 둘째 단계에서 다시 인식한 결과를 **연결해 올린다** → `_sent[N] = t`. 그 뒤 A가 휴지통 → 영구 삭제하고 B가 그 영구 삭제를 받으면, 가상 시간이 10분(`purgeGuardWindow`) 안이면 `guard()`가 `_sent`만 보고 사본을 만든다(`purge_guard.dart` 63–67). 계획서 6.2.5 자신의 문장대로라면 S28의 '사본 없음'은 성립하지 않는다.
  2. 이 사용자의 실제 조합에서는 드물지 않다. 주 기기는 iPad Safari(ML Kit 없음)이고 손글씨 결과는 네이티브(안드로이드)가 만든다(계약 D7). LIBRARY 색인기는 **원격으로 받은 획**의 페이지도 낡은 페이지로 보고 인식한다(02-core T32 `stalePages` '원격 획 변경 뒤', G-2 '입력 3초 뒤'). 그래서 iPad에서 쓴 노트를 안드로이드가 몇 분 안에 인식해 `hw_<pageId>`를 올리고, 그 10분 안에 사용자가 iPad에서 노트를 지우고 휴지통을 비우면 안드로이드가 '(복구됨)' 사본을 만들어 iPad로 되돌려 보낸다 — 사용자가 일부러 지운 노트가 돌아온다. 안드로이드 쪽 사용자는 그 노트를 건드리지 않았다.
  3. '손글씨는 파생 데이터라 편집이 아니다'(outbox 판정, 6.2.5 표)와 '최근에 올린 손글씨는 편집이다'(10분 창)가 한 기능 안에서 서로 다르다.
- **고칠 방향**: `onScopesCommitted`에 넘기는 범위에서 **`handwriting` 기록만 실린 청크의 범위를 뺀다**(커밋 그룹의 `c.items`의 종류로 판정 — `upload_pipeline.dart` 363 한 줄). 6.2.5 문장을 '손글씨 결과는 outbox·최근 보냄 모두 편집으로 세지 않는다'로 고친다. 시험: `purge_guard_test`에 '손글씨만 최근에 올림 → 사본 없음'과 대조 경우 '획을 최근에 올림 → 사본 있음', S28은 지금 단언 그대로(가상 시간을 10분 안으로 두어 이 규칙을 실제로 확인), `upload_pipeline_test`에 '손글씨만 든 커밋은 `onScopesCommitted`에 범위가 없음'.

### M-4. B7a 완료 조건의 `core_json_keys_test` 실행이 B7a 변경 목록대로면 실패한다

- **위치**: 6.4 표 `core_json_keys_test.dart` 행('integration — 기본 skip, 컴파일만 … `_kindOf`만'), 8.1 B7a 완료 조건(`flutter test --run-skipped test/integration/core_json_keys_test.dart` — 'CORE 골든이 들어온 뒤'), 6.7.2 JSON 키 대조 v2.
- **문제** [확인 — `test/integration/core_json_keys_test.dart` 60–66]: 1차 시험은 골든 파일마다 `json.keys.toSet() == FieldUnits.keysOf(kind)`를 단언한다. B7a에서 `keysOf(pageObject)`는 4종 합집합(16키)인데 `shape_rect.json`은 11키, `unknown.json`은 모르는 키를 가진다 → `_kindOf`만 바꾸면 이 시험이 실패한다. CORE 새 골든 9개는 R2-B2(T20·T21 — 02-core 8.1 'JSON 골든: 새 9개')에 들어오므로 B7a 시점에 실제로 돈다. 6.4 표('컴파일만')와 8.1 완료 조건('실행')도 서로 다르다.
- **고칠 방향**: 6.7.2에 적은 v2 단언(알려진 4종 골든 키 합집합 = `keysOf(pageObject)`, 각 골든 키 = `kPageObjectTypeKeys[type]`, `unknown`은 키 대조에서 빼고 `SyncDoc` 왕복만)을 **B7a로 옮긴다**(B7a는 이미 `kPageObjectTypeKeys`를 만든다). 아니면 이 명령을 B7a 완료 조건에서 빼고 S2-1로 넘긴다. 어느 쪽이든 6.4 표와 8.1을 같게 적는다. `field_units_test`의 'CORE key table matches what CORE entities serialize'(77행)도 같은 종류별 비교로 바꾼다는 것을 6.4 표의 그 행에 적는다.

---

## 권장

### S-1. 다시 적용 중 K1 보류를 원래 청크 id로 `sync.held`에 넣으면, 원래 청크가 압축으로 지워졌을 때 기록을 잃는다

- **위치**: D-S4, 6.3.4 둘째 항목('그 사이 압축으로 원래 청크가 지워졌으면 … 그 내용은 압축 스냅숏으로 들어온다'), 6.3.2 중복 제거 키.
- **문제**: 옛 앱 A가 청크 C1의 손글씨 기록 h를 보관했다. 그 뒤 새 앱 기기 B가 범위를 압축해 스냅숏 S(h 포함)를 만들고 C1을 지운다. A는 S를 받지만 h는 같은 (`k`, `id`, `fv`)라 **중복으로 버려지고**(C1 기준 보관이 남음) 커서는 S를 지난다. A가 갱신 → 다시 적용에서 h가 K1(미래 시각)에 걸리면 `sync.held[C1]` → K2가 `getChunks(C1)` → 돌아오지 않음 → 1차 규칙대로 '잊음' → h를 잃는다. 스냅숏은 이미 커서 뒤라 다시 오지 않는다. K1은 기기 시계가 크게 앞선 드문 경우지만 S-13의 목적(손실 0)과 어긋난다.
- **고칠 방향**: 다시 적용에서 K1에 걸린 기록은 `sync.heldRecords`에 **남기고**(해제 시각 `ra`를 함께 적음) 다음 attach 또는 K2 해제 시점에 다시 시도한다 — 원래 청크의 존재에 기대지 않는다. 이러면 D-S4의 '원래 청크 id로 `sync.held`' 규칙과 `releaseHolds` 문제도 함께 사라진다. 시험 하나('다시 적용 K1 + 원래 청크 압축 삭제 → 해제 뒤 적용').

### S-2. 다시 적용 결과가 1차 지표를 흐린다 / 재시도 시점

- `_absorbApply`(`engine_controller.dart` 993–1000)는 `latestServerTime`으로 `_lastRemoteApplyLatency`를 계산하고 `r.chunks`를 `chunksReceived`에 더한다. 합성 청크는 옛 serverTime이라 지연이 며칠로 찍힌다. 다시 적용의 `ApplyResult`는 `latestServerTime: null`, 청크 수는 따로(`SyncEngineDebug.heldRecords` 옆) 센다.
- 6.3.4 '저장 실패 → 다음 attach에 다시'는 1차 `_connect`의 `if (!s.loaded) { purged.load; download.load }` 블록(`engine_controller.dart` 553–558) 안에 다시 적용을 넣으면 같은 세션의 재연결에서는 다시 하지 않는다는 뜻이 된다. 위치(그 블록 밖, 세션 플래그 `heldReapplied`)를 명시하고, 실패 뒤 재연결에서 다시 시도하는 시험을 `engine_state_test`에 둔다.

### S-3. 보관 상한 200 KiB 값 하나 — '되감기는 드문 안전망'이 아닐 수 있다

- **위치**: D-S2, 6.3.2, 6.3.5 셋째 항목.
- **문제**: 손글씨 결과 기록 하나는 `strokeIds`(UUID 36자 × 획 수)·`rect`·후보를 담는다. 획 300개 페이지면 기록 하나가 10 KB를 넘고, base64(4/3)까지 더하면 200 KiB에 10쪽 남짓만 들어간다. 다음 라운드에 큰 기록을 가진 새 종류가 생기면 보관은 금방 넘치고 '수천 청크 다시 받기'가 기본 경로가 된다. 깨진 값을 빈 값으로 읽어 기록을 잃는 경로(6.3.2 마지막 항목)도 남는다.
- **고칠 방향**: 메타 키를 여러 개로 나눈다(`sync.heldRecords`, `sync.heldRecords.1` … — 키당 < 256 KiB, 총 상한 예 2 MiB, 1차 `sync.purged.*`가 이미 여러 키를 쓴다 — `meta_keys.dart` 12). 깨진 값을 읽으면 '모든 종류 되감기 표시'(`o.f` = 0 또는 가장 오래된 보관 시각, `k` = `*`)로 바꿔 다음 갱신 때 통째로 다시 받게 한다(비싸지만 잃지 않음). 6.12에 '기록 10 KB × n' 기준 보관 개수를 적는다.

### S-4. `checkConverged`에 종류 필터가 필요한데 4.3·CP-S8에 없다

- S27 (b)·(c)의 '각 경우 `checkConverged`(알려진 종류)'는 옛 앱 기기(손글씨 없음)와 서버 병합 상태(손글씨 있음)를 비교하므로 1차 `checkConverged(devices, {includeServer})`(`sync_test_harness.dart` 201–204)로는 실패한다. `checkConverged(…, {Set<EntityKind>? kinds})`를 4.3 추가 목록·CP-S8·`api_surface_test` 갱신 대상에 넣는다. 같은 맥락에서 하네스 `knownKinds`·`restart`가 6.5 표(S2-4)와 S2-7 완료 조건(`sync_test_harness_test`) 두 곳에 있다 — 한 작업으로 정한다.

### S-5. T16-v2의 실제 CORE 선행 작업이 T26·T28만이 아니다

- **위치**: 5.5 표 '실제 CORE v2' 행, 6.7.2 마지막 항목, 11 R1.
- **문제**: 02-core 8.1의 'B2 상태'에서 실제 저장소의 `AddObjects`·`UpdateObjects`는 T27까지 `UnimplementedError`이고, `recordings`·`handwriting`·`search` 쓰기는 T30~T33까지 `UnimplementedError`다. 그래서 O1~O4는 T27, H1~H4는 T32·T33, O5·U2(복사)는 T29(T27·T30·T32·T33 뒤), R1·R2·C-31은 T30, C-30 뒷문장은 T31·T33이 있어야 돈다. 'T26부터 시나리오 가능, T28부터 전부'는 사실과 다르고, 동시 개발 중 '미리 어긋남 찾기'의 시점 판단을 틀리게 한다.
- **고칠 방향**: 6.7.2에 파일·경우별 CORE 선행 작업 표를 두고, CORE에 T27·T29·T30·T32·T33 커밋도 이정표로 알려 달라고 요청한다(X-4).

### S-6. 서버 함수 시험의 '25 s 제한(가짜 시계)' — `AbortSignal.timeout`은 mock timers로 움직이지 않는다

- [확인 — Node 22.23.4] `mock.timers.enable({apis: ['setTimeout','Date']})` 뒤 `AbortSignal.timeout(25000)`을 만들고 `tick(26000)`해도 `aborted == false`다. 6.8.2의 `AbortSignal.timeout(25_000)`을 처리 본문 안에서 직접 부르면 `handler.test.ts`의 시간 제한 경우를 가짜 시계로 시험할 수 없다.
- `HandlerDeps`(4.5)에 `engineSignal(ms: number): AbortSignal`(기본 `AbortSignal.timeout`)을 더하고, 시험은 직접 `AbortController`를 넘겨 `abort()`한다. 비교 도구의 25 s 제한도 같은 주입을 쓴다.

### S-7. 엔진 어댑터가 Firebase 매개변수를 직접 읽는 스케치 — 비교 도구와 공유할 수 없다

- 6.8.6 Claude 스케치는 어댑터 안에서 `MATH_API_KEY.value()`·`CLAUDE_MODEL.value()`를 부른다. 6.9는 같은 어댑터를 서버 밖에서 `ANTHROPIC_API_KEY`·`MATHPIX_APP_KEY`로 부른다고 한다. 어댑터는 생성자로 `{apiKey, appId?, model, client?/fetch?}`를 받고, `params.ts`를 읽는 것은 등록부(`registry.ts`)만 하도록 4.5에 적는다(시험 주입점도 같은 곳이 된다).

### S-8. Claude 서버 쪽 대체가 돌면 `engineVersion`이 실제 응답 모델과 다르다

- `fallbacks: "default"`는 거절되면 다른 모델로 다시 돌린다. 지금 표(6.8.4)는 `version` = `CLAUDE_MODEL`이라 앱의 `MathObject.engineId`('claude/<판>' — 출처 기록)가 틀린다. `engineVersion`은 응답의 `model`(실제로 답한 모델)로 정하고, 대체 여부는 로그(`usage.iterations`의 `fallback_message`)에 남긴다. 계약 7.2.13의 `engineVersion` 뜻도 '실제로 응답한 판'으로 적는다(C-7).
- 참고로 SDK 쪽 확인: 1.1.0의 `resources/beta/messages/messages.d.ts`에 `fallbacks?: BetaFallbacksParam | null`(`Array<BetaFallbackParam> | 'default'`), `AnthropicBeta`에 `'server-side-fallback-2026-07-01'`, `BetaOutputConfig.effort`·`format`이 있다. 꾸러미는 CommonJS `require` 진입점이 있어 `"type": "commonjs"` 빌드와 맞는다.

### S-9. 미니 라운드 준비의 사실 오류·모순

- **`.env.local`은 배포에 쓰이지 않는다.** Q9 기본값 '운영 `OWNER_UIDS`는 커밋하지 않는 `.env.local`'은, Firebase가 `.env.local`을 **에뮬레이터에서만** 읽으므로 배포된 함수의 `OWNER_UIDS`가 기본값 `''`(아무도 못 씀)이 된다 [문서 기억 — 배포 때 확인]. 6.8.9 표('`.env.<projectId>` — 커밋 가능')와도 다르다. 기본을 '커밋하는 `functions/.env.<projectId>`(uid는 비밀이 아님)'로 고친다.
- **운영에서 가짜 엔진으로 확인할 수 없다.** 6.10 L5 '배포 뒤 확인 순서(로그인 사용자로 가짜 엔진 → 실제 엔진 1회)'와 SC-7 '가짜 엔진 → 실제 엔진'은 6.8.9·D-S7의 운영 `ALLOW_FAKE_ENGINE=false`와 모순이다. '`MATH_ENGINE=none` 상태에서 소유자 → 503 `UNAVAILABLE`(로그인·소유자 검사 통과 확인), 남 계정 → 403' → 엔진 설정 뒤 실제 1회로 바꾼다.
- **비밀값이 첫 배포 전에 있어야 한다.** `recognizeMath`가 `secrets: [MATH_API_KEY]`를 묶으므로 엔진이 정해지기 전(`MATH_ENGINE=none`)에도 첫 배포 전에 Secret Manager에 값이 있어야 한다 [추측 — firebase-tools 배포 검사, 미니 라운드에서 확인]. L5 순서와 부록 B의 시점('엔진 계정 뒤')을 '첫 배포 전 — 자리 값 가능'으로 고친다.

### S-10. 작업 분해 — 한 세션을 넘을 작업

- 1차 진행 기록은 'T6(가짜 로컬 + 계약 스위트 + `TestDevice` + 하네스)이 크다 — 한 세션을 통째로'라고 적었다(1차 `progress/sync.md` 141행). 2차 S2-4는 그 위에 가짜 저장소 8곳 + 가짜 서버 v2 + `TestDevice` 도우미 12개 + 계약 스위트 6경우와 드라이버 두 벌이다. S2-7(받기 보관·문제·다시 적용·되감기·압축·시험 훅), S2-10(모듈 9 + 시험 파일 8)도 크다.
- 쪼갠다: S2-4a(가짜 저장소·서버 v2 + `testing/*_test`), S2-4b(`TestDevice`·하네스 + 계약 스위트 C-26~C-31 + 실제 CORE 드라이버 멤버), S2-7a(관용 디코드를 파이프라인·압축·가짜 서버에 연결, 받기 보관·문제), S2-7b(다시 적용·되감기·`debugKnownKinds`·`restart`), S2-10a(`protocol`·`access`·`registry`·가짜 엔진), S2-10b(`quota`·처리 본문·오류·로그·위생 시험). 세션 추정(6~7)은 그대로 두되 작업 단위가 세션 경계와 맞게 한다.

### S-11. 실기기 체크리스트(미니 라운드 뒤)의 현실성

- 안드로이드 태블릿 여부가 미확인(U2)이다. SC-1~SC-3·SC-5·SC-6은 ML Kit이 필요 없으므로 'iPad Safari ↔ PC Chrome(웹 ↔ 웹)'으로도 할 수 있다고 대체 경로를 적고, SC-4(손글씨 결과 동기화 → 웹 검색)만 안드로이드 또는 TestFlight 뒤 iPad 네이티브가 필요하다고 나눈다. SC-7의 '다른 계정'에는 Google 계정이 하나 더 필요하다는 것도 적는다. 모두 Firebase 프로젝트(Blaze) 뒤라는 전제는 맞다.

### S-12. 작은 것들

- 4.2 `handwriting → json['noteId'] ?? noteIdHint ?? 'lib' (like recording)` — 1차 `recording`은 `noteIdHint ?? noteIdKey`(`scopes.dart` 27)라 '녹음과 같음'이 아니라 '페이지와 같음'이다. 6.2.3 표 '근거' 열도 같다.
- 6.12 시간 단언(`HeldRecords` Chrome ≤ 60 ms 등) — 같은 컨테이너에서 다른 영역 시험이 돌 때 흔들린다. 수치는 진행 기록에 남기고 단언은 느슨한 상한(×5)으로 둔다.
- 6.10 L4 규칙 시험 설정 `functions/test-emulator/firebase.rules-test.json`의 규칙 경로 `../../packages/sync_engine/firebase/*`를 firebase-tools가 읽는지는 확인되지 않았다(조사 04 6.4는 `functions.source`의 `../`만 확인). `[추측]`을 붙이고, 안 되면 시험이 임시 디렉터리에 규칙 파일을 복사한 설정을 만들게 한다.
- `SyncEngineDebug`에 필드를 더할 때 1차 클래스의 `==`·`hashCode`·`toString`에도 넣는다(값 비교 시험이 있으면 깨지지 않게).
- 6.8.12 Mathpix 단가·설정비는 '검색 요약'이라 `[추측]` 표시를 붙인다(Claude 단가는 확인됨).

---

## 다른 영역과 걸리는 것

| # | 상대 | 내용 |
|---|---|---|
| X-1 | INFRA | `.gitignore` 추가분(01-infra R2-B1 ⑨)에 **`functions/eval-out/`이 없다** — SYNC RQ-2가 요청하는 항목이다. 같은 변경에서 `functions/.env.demo-noteapp`(커밋 대상)이 어떤 패턴에도 걸리지 않는지 `hosting_config_test` 옆에 한 줄 확인을 둔다 |
| X-2 | INFRA · LIBRARY | **전역 잠금 중첩**: SYNC `emulator_suite.sh`(잠금을 잡음) 안에서 LIBRARY Dart 시험(`ws test -t emulator` — 01-infra 438, 다시 잠금을 잡음)을 돌리면 자기 잠금을 기다리다 20분 뒤 종료 코드 4가 된다. 6.8.11 '한 번의 실행으로 바꿔도 된다'와 LIBRARY L2-21 '컨테이너 1회 실행'이 바로 이 모양이다. 잠금 넘김 환경 변수(예: `NOTEAPP_HEAVY_LOCK_HELD=<pid>` — 자식 프로세스는 잠금을 다시 잡지 않음)를 INFRA `heavy_lock.dart`가 존중하거나, 안쪽 호출에 `--no-heavy-lock`을 쓴다고 정한다. RQ-5(npm에서 쓸 잠금 감싸기)는 INFRA 계획서에 없다 — bash 구현과 Dart 구현이 같은 파일 형식을 쓰는지 `heavy_lock_test`에 bash 쪽이 만든 잠금 파일을 읽는 경우 하나를 더한다 |
| X-3 | INFRA | B7b를 R2-B1 직후 따로 병합하면 INFRA 검토 S-11(R2-B1 시점 `functions/` 부재로 `functions.yml`이 실패)이 짧아진다 — 그래도 `hashFiles` 가드는 둔다. CI 더미 env 질문(INFRA 검토 X-6)의 답은 커밋하는 `.env.demo-noteapp`다(SYNC 6.8.9). 미니 라운드 안내서에 S-9 순서(비밀값 → `.env.<projectId>` → 배포 → 503 확인 → 엔진 1회)와 RQ-6 `ignore`를 넣는다 |
| X-4 | CORE | ① B7a의 바탕 커밋: 02-core 5.6은 'EntityKind 2값 커밋 해시', 8.1은 'T22 커밋 해시'를 알린다고 한다. B7a는 `Recording.title`(T21)과 `EntityJson.decode`(T20)까지 필요하므로(CP-S9) **T22 해시**로 통일한다. ② T16-v2 선행 이정표(S-5): T27·T29·T30·T31·T32·T33 커밋도 진행 기록에 알린다. ③ `math`의 `engine` 키를 항상 씀(CORE 검토 C-7) — 그러면 `kPageObjectTypeKeys['math']`가 고정된다 |
| X-5 | LIBRARY | ① Dart 에뮬레이터 시험이 SYNC 6.8.5·E1~E10의 값(`\frac{2}{5}`, `\sqrt{67}`, `engineId 'fake/1'`, `gemini` → `UNAVAILABLE`)을 그대로 단언하고 사용자 만들기 REST(`Authorization: Bearer owner` + `localId`, `DUPLICATE_LOCAL_ID`·`EMAIL_EXISTS`면 로그인)를 같이 쓴다(LIBRARY 검토 S-6과 같음). ② M-3: 색인기가 원격 획 페이지를 인식해 올리는 것은 그대로 두고 SYNC가 '최근 보냄'에서 손글씨를 뺀다 — LIBRARY 쪽 변경 없음. ③ LIBRARY 검토 X-3 질문(엔진 id가 다른 결과도 신선으로 봄)에 대해: SYNC는 손글씨를 한 단위 LWW로 병합하므로 받아들일 수 있다(R6·Q7과 같은 한계) |
| X-6 | EDITOR · LIBRARY | Q4 수식 고정 자료 내보내기: EDITOR E2-24 개발자 메뉴는 도형 표본 형식(`{kind, points, viewScale}` — 05-library 1875행)만 다룬다. 6.9.1 형식(`strokes: {x, y, t}` + `expected`)을 누가 내보낼지 정해지지 않았다. LIBRARY 수식 패드의 P-C 개발자 동작으로 두거나, `math_eval.ts`가 E2-24 형식을 읽는 변환기를 가진다 — 한쪽으로 정해 Q4 답에 적는다 |

---

## 계약 문제

- **C-1. 7.0.1 C2-05·7.0.2 'SYNC `lib/` switch 8곳'**: 실제로 깨지는 것은 기본 갈래 없는 switch 4곳(`keysOf`·`groupsOf`·`scopeOf`·`_purged`) + 목록 `kindOrder`(컴파일은 되나 정렬 틀림) + 시험 `fixtureJson`이다. 나머지 4곳(`SyncDoc.ownerId`·`hasOwner`·`_editedInOutbox`·`mergedState`)은 기본 갈래가 있다 [확인]. 표 문구를 계획서 6.4대로 고친다.
- **C-2. 7.2.8 `handwriting` '페이지 영구 삭제 때 함께'**: 영구 삭제 기록은 folder·note뿐이고(`record_gate.dart` 83, `chunk_codec.dart` `_purge`), 페이지는 소프트 삭제만 있다(02-core 6.4.1 `DeletePages`). '노트 영구 삭제 때 함께(페이지 삭제는 하위 행을 건드리지 않음)'로 적는다. `pageObject` 행의 '페이지·노트 영구 삭제'도 같다.
- **C-3. CP-S1 지지.** 원문 'CORE `toJson` 키 집합 = `keysOf(kind)`'는 `pageObject`에서 문자 그대로 성립하지 않는다(M-4가 그 결과). ① 합집합·종류별 포함 ② '이후 키는 한 단위에' 둘 다 계약 문장으로 올린다.
- **C-4. CP-S2 지지 + 보강.** ②에 'M-1: 한 청크의 모르는 기록은 전부 보관하거나 전부 표시한다', S-3의 '여러 메타 키'와 '깨진 값 → 모든 종류 되감기'를 함께 적는다. ④ '시작 시' → '로그인 상태로 연결할 때, 받기 전에'는 1차 attach 순서와 맞다.
- **C-5. 7.6.2 R2-B7 행**은 `functions/` 골격을 R2-B2 묶음에 넣지만, 계획서 6.4는 B7b를 묶음 밖에서 먼저 병합해도 된다고 한다(Dart와 무관 — 타당). 계약 행에 '(`functions/` 골격은 R2-B1 뒤 따로 병합 가능)'을 더한다.
- **C-6. 7.5 '게시 14일 규칙'과 `firebase-tools 15.34.2`(게시 2026-10-28, 오늘 8일, 최신 15.35.0)**: 1차 고정값 예외로 둘지, R2-B1 때 14일이 지난 판으로 다시 확인할지 계약에 한 줄 적는다(계획서 Q8 — 기본 '그대로, R2-B7 때 재확인'에 동의).
- **C-7. 7.2.13 `engineVersion`**의 뜻을 '실제로 응답한 엔진·모델 판(대체 포함)'으로 적는다(S-8). CP-S3 ⑥(가짜 엔진 출력 규칙을 계약 시험 도우미 문장으로)은 LIBRARY 단언이 기대므로 지지한다.
- **C-8. CP-S5 지지.** `@anthropic-ai/sdk 1.1.0`은 2026-10-21 게시(15일)로 14일 규칙을 넘고, 쓰려는 매개변수가 타입에 있다 [확인]. 간접 의존(`standardwebhooks`·`json-schema-to-ts`·`@opentelemetry/api`)의 판은 lock 만들 때 7.2의 방식대로 확인한다.

---

## 질문

| # | 질문 | 왜 |
|---|---|---|
| Q-1 | M-1을 'LRU에 넣지 않음'과 '청크 단위 전부 또는 전무' 둘 다로 고치는가(검토자 기본값: 둘 다) | 하나만 고치면 겹침 재수신·되감기 중 한 경로가 남는다 |
| Q-2 | M-3: 손글씨 결과만 올린 범위를 '최근 10분 보냄'에서 빼는 것에 동의하는가 | 1차 T11 결정 ①(노트 범위 청크면 무엇이든)을 바꾸는 일이다 |
| Q-3 | 안드로이드 태블릿이 있는가(U2) | SC-4만 그 기기가 필요하고 나머지는 웹 ↔ 웹 대체 경로로 할 수 있다(S-11) |
| Q-4 | 운영 `OWNER_UIDS`를 커밋하는 `functions/.env.<projectId>`에 두는가(S-9) | `.env.local`은 배포에 쓰이지 않는다 |
| Q-5 | B7b(`functions/` 골격)를 R2-B2 묶음 밖에서 R2-B1 직후 병합해도 되는가(C-5) | INFRA `functions.yml`이 R2-B1부터 돈다 |
